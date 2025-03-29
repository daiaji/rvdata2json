# encoding: utf-8
# rvdata2json/lib/converter.rb
# 包含核心的 RVData <-> JSON 转换逻辑

require "json"
require "fileutils"
require "set"

# 转换器模块，包含 IO、导出器和恢复器
module Converter
  # 文件 IO 操作子模块
  module IO
    # 加载 Marshal 数据文件
    # @param input_file [String] 输入文件路径
    # @return [Object] 反序列化后的 Ruby 对象
    def self.load_marshal_data(input_file)
      begin
        File.open(input_file, "rb") { |f| Marshal.load(f) }
      rescue ArgumentError => e
        raise "加载 Marshal 数据 '#{input_file}' 时出错 (可能是版本不匹配或文件损坏): #{e.message}"
      rescue TypeError => e
        raise "加载 Marshal 数据 '#{input_file}' 时类型错误 (确保加载了正确的 RGSS 定义): #{e.message}"
      rescue => e
        raise "读取或解析 Marshal 文件 '#{input_file}' 时出错: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    # 加载 JSON 数据文件
    # @param input_file [String] 输入文件路径
    # @return [Object] 解析后的 Ruby 数据结构 (Hash, Array, etc.)
    def self.load_json_data(input_file)
      begin
        json_string = File.read(input_file, encoding: "UTF-8")
        data = JSON.parse(json_string)
        # 特殊处理 MapInfos，保留来源信息用于恢复 key 类型
        if data.is_a?(Hash) && File.basename(input_file, ".json") == "MapInfos"
          data["__source_file__"] = input_file # 注入来源信息
        end
        data
      rescue JSON::ParserError => e
        raise "JSON 解析错误，文件 '#{input_file}': #{e.message}"
      rescue => e
        raise "读取或解析 JSON 文件 '#{input_file}' 时出错: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    # 写入 JSON 数据文件
    # @param output_file [String] 输出文件路径
    # @param data [Object] 要序列化的 Ruby 对象/数据结构
    def self.write_json_data(output_file, data)
      FileUtils.mkdir_p(File.dirname(output_file))
      begin
        # 使用 pretty_generate 美化输出，quirks_mode 处理特殊浮点数
        json_string = JSON.pretty_generate(data, { quirks_mode: true, indent: "  ", space: " " })
        File.write(output_file, json_string, encoding: "UTF-8")
      rescue => e
        raise "写入 JSON 文件 '#{output_file}' 时出错: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    # 写入 Marshal 数据文件
    # @param output_file [String] 输出文件路径
    # @param restored_object [Object] 要序列化的 Ruby 对象
    def self.write_marshal_data(output_file, restored_object)
      FileUtils.mkdir_p(File.dirname(output_file))
      begin
        dumped_data = Marshal.dump(restored_object)
        File.binwrite(output_file, dumped_data)
      rescue TypeError => e
        problem_info = find_problematic_path(restored_object) do |obj|
          # 检查 Tone/Color 属性是否为 nil
          (obj.is_a?(Tone) || obj.is_a?(Color)) && obj.instance_variables.any? { |ivar| obj.instance_variable_get(ivar).nil? } ||
            # 检查 Table elements 是否为 nil
          (obj.is_a?(Table) && obj.instance_variable_get(:@elements).nil?) ||
            # 添加检查 RPG::Animation::Frame 的 @cell_data 是否为 nil (仅 RGSS2 不应为 nil)
          (obj.is_a?(RPG::Animation::Frame) && obj.instance_variable_get(:@cell_data).nil? && !defined?(RPG::Tileset)) # 粗略判断是否为 RGSS2 环境
          # 添加其他可能的检查
        end
        context = problem_info ? " 问题可能在路径 #{problem_info[:path]} 的对象: #{problem_info[:object].class} #{problem_info[:object].inspect}." : ""
        raise TypeError, "写入 Marshal 文件 '#{output_file}' 时 TypeError: #{e.message}.#{context}"
      rescue => e
        raise "写入 Marshal 文件 '#{output_file}' 时发生未知错误: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    # 查找满足条件的第一个对象的路径（用于调试）
    # @param object [Object] 起始对象
    # @param current_path [String] 当前路径字符串
    # @param visited [Set] 已访问对象的 ID 集合
    # @param block [Proc] 条件块，返回 true 表示找到问题对象
    # @return [Hash, nil] 包含路径和对象的哈希，或 nil
    def self.find_problematic_path(object, current_path = "root", visited = Set.new, &block)
      # 基本类型和已访问对象直接返回 nil
      return nil unless object.respond_to?(:object_id)
      return nil if object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)
      oid = object.object_id
      return nil if visited.include?(oid)
      visited.add(oid)

      result = nil
      begin
        # 检查当前对象是否满足条件
        if block.call(object)
          return { path: current_path, object: object }
        end

        # 递归检查容器或实例变量
        case object
        when Array
          object.each_with_index do |item, index|
            result = find_problematic_path(item, "#{current_path}[#{index}]", visited, &block)
            break if result
          end
        when Hash
          object.each do |key, value|
            next if key == "__source_file__" # 跳过内部使用的键
            result = find_problematic_path(value, "#{current_path}{#{key.inspect}}", visited, &block)
            break if result
          end
        else
          # 检查对象的实例变量
          if object.respond_to?(:instance_variables)
            object.instance_variables.each do |ivar|
              next if ivar.to_s.start_with?("@_") # 跳过内部/私有变量 (如 jsonable 的)
              begin
                value = object.instance_variable_get(ivar)
                result = find_problematic_path(value, "#{current_path}.#{ivar}", visited, &block)
                break if result
              rescue => e
                # 忽略访问实例变量时可能发生的错误
              end
            end
          end
        end
      ensure
        visited.delete(oid) # 回溯时移除，允许不同路径访问同一对象
      end
      result
    end
  end # IO

  # 将 Ruby 对象转换为适合 JSON 序列化的数据结构 (主要负责调用 unpack_names)
  class JsonExporter
    def initialize(rgss_version)
      @rgss_version = rgss_version
      @visited = Set.new # 用于处理递归调用的访问集合
    end

    # 导出对象 (实际导出由 jsonable gem 的 to_json 完成, 此方法主要用于 unpack)
    # @param object [Object] 待导出的 Ruby 对象
    # @return [Object] 处理过 unpack_names 的原始对象
    def export(object)
      @visited.clear # 每次导出前清空
      unpack_recursively(object)
      object # 返回处理后的对象
    end

    private

    # 递归解包对象内部的字符串
    # @param object [Object] 当前处理的对象
    def unpack_recursively(object)
      return if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)
      return unless object.respond_to?(:object_id)
      oid = object.object_id
      return if @visited.include?(oid)
      @visited.add(oid)

      begin
        # 尝试调用对象的 unpack_names 方法
        if object.respond_to?(:unpack_names)
          call_unpack_names(object)
        end

        # 递归处理容器或实例变量
        case object
        when Array
          object.each { |item| unpack_recursively(item) }
        when Hash
          object.each_value { |value| unpack_recursively(value) }
        else
          if object.respond_to?(:instance_variables)
            object.instance_variables.each do |ivar|
              next if ivar.to_s.start_with?("@_") # 跳过内部变量
              unpack_recursively(object.instance_variable_get(ivar)) rescue nil
            end
          end
        end
      ensure
        # 单次导出调用，不需要在递归返回时删除 visited 记录
      end
    end

    # 调用对象的 unpack_names 方法，智能判断是否需要版本参数
    # @param object [Object]
    def call_unpack_names(object)
      method_obj = object.method(:unpack_names)
      needs_version = method_needs_version_arg?(method_obj)

      begin
        if needs_version
          object.unpack_names(@rgss_version)
        elsif method_obj.arity == 0 # 确定不需要参数
          object.unpack_names
        else # 参数需求不明确或为负数（可变参数），尝试无参数调用
          # puts "[调试] #{object.class}#unpack_names 参数需求不明确 (arity: #{method_obj.arity})，尝试无参数调用。" if method_obj.arity != 0
          begin
            object.unpack_names
          rescue ArgumentError # 如果无参数调用失败，并且需要版本，尝试传递版本
            if needs_version
              # puts "[调试] 无参数调用 #{object.class}#unpack_names 失败，尝试传递版本。"
              object.unpack_names(@rgss_version)
            else
              # 如果不需要版本，但调用仍然失败，则抛出原始错误
              raise
            end
          end
        end
      rescue ArgumentError => e
        puts "[警告] 调用 #{object.class}#unpack_names 时参数错误: #{e.message} (需要版本参数吗？)"
      rescue => e
        puts "[警告] 在 #{object.class} 上执行 unpack_names 时出错: #{e.class}: #{e.message}"
      end
    end

    # 检查方法（如 unpack_names, initialize）是否需要 rgss_version 参数
    # @param method_obj [Method]
    # @return [Boolean]
    def method_needs_version_arg?(method_obj)
      arity = method_obj.arity
      if arity == 1 || arity < 0
        begin
          params = method_obj.parameters
          # 检查第一个必需或可选参数是否名为 :rgss_version
          return params.any? && params.first[0] != :rest && params.first[1] == :rgss_version
        rescue NameError, NoMethodError
          # puts "[调试] 无法检查 #{method_obj.owner}##{method_obj.name} 的参数名，基于 arity=#{arity} 判断。"
          return arity == 1 # 如果只有一个参数，倾向于认为需要版本
        end
      end
      false # Arity 0 或 > 1 时，假定不需要
    end
  end # JsonExporter

  # 从 JSON 解析的数据结构恢复 RVData 对象
  class RvdataRestorer
    # 注册表，处理需要特殊构造函数参数的类
    CLASS_INSTANTIATORS = {
      "RPG::Event" => ->(data, version, restorer) { RPG::Event.new(data["@x"], data["@y"]) },
      "RPG::EventCommand" => ->(data, version, restorer) { RPG::EventCommand.new(data["@code"], data["@indent"], restorer.restore_value(data["@parameters"])) },
      "RPG::MoveCommand" => ->(data, version, restorer) { RPG::MoveCommand.new(data["@code"], restorer.restore_value(data["@parameters"])) },
      "RPG::Map" => ->(data, version, restorer) { RPG::Map.new(data["@width"], data["@height"], version) },
      "Color" => ->(data, version, restorer) { Color.new([data["@red"], data["@green"], data["@blue"], data["@alpha"]]) },
      "Tone" => ->(data, version, restorer) { Tone.new([data["@red"], data["@green"], data["@blue"], data["@gray"]]) },
      "Rect" => ->(data, version, restorer) { Rect.new(data["@x"], data["@y"], data["@width"], data["@height"]) },
      "Table" => ->(data, version, restorer) do
        elements_data = restorer.restore_value(data["@elements"]) || []
        # 调用顶层的 Table.new
        Table.new([data["@num_of_dimensions"], data["@xsize"], data["@ysize"],
                   data["@zsize"], data["@num_of_elements"], *elements_data.flatten])
      end,
      "RPG::AudioFile" => ->(data, version, restorer) { RPG::AudioFile.new(data["@name"], data["@volume"], data["@pitch"]) },
      "RPG::BGM" => ->(data, version, restorer) { RPG::BGM.new(data["@name"], data["@volume"], data["@pitch"]) },
      "RPG::BGS" => ->(data, version, restorer) { RPG::BGS.new(data["@name"], data["@volume"], data["@pitch"]) },
      "RPG::ME" => ->(data, version, restorer) { RPG::ME.new(data["@name"], data["@volume"], data["@pitch"]) },
      "RPG::SE" => ->(data, version, restorer) { RPG::SE.new(data["@name"], data["@volume"], data["@pitch"]) },
      "RPG::BaseItem::Feature" => ->(data, version, restorer) { RPG::BaseItem::Feature.new(data["@code"], data["@data_id"], data["@value"]) },
      "RPG::UsableItem::Effect" => ->(data, version, restorer) { RPG::UsableItem::Effect.new(data["@code"], data["@data_id"], data["@value1"], data["@value2"]) },
      "RPG::UsableItem::Damage" => ->(data, version, restorer) { RPG::UsableItem::Damage.new }, # Damage 的属性在 populate 时设置
      "RPG::Animation::Frame" => ->(data, version, restorer) { RPG::Animation::Frame.new(version) },
      "RPG::System::TestBattler" => ->(data, version, restorer) { RPG::System::TestBattler.new(version) },
      "RPG::Troop::Member" => ->(data, version, restorer) { RPG::Troop::Member.new(version) },
    }.freeze

    def initialize(rgss_version)
      @rgss_version = rgss_version
    end

    # 恢复对象
    # @param data [Object] 从 JSON 解析的数据
    # @return [Object] 恢复后的 Ruby 对象
    def restore(data)
      restore_value(data)
    end

    # 递归恢复值（暴露给外部用于恢复 EventCommand 等参数）
    # @param value [Object]
    # @return [Object]
    def restore_value(value)
      case value
      when Array
        restore_array(value)
      when Hash
        restore_hash(value)
      else
        value # 基本类型直接返回
      end
    end

    private

    # 恢复数组
    # @param array [Array]
    # @return [Array]
    def restore_array(array)
      array.map { |item| restore_value(item) }
    end

    # 恢复哈希
    # @param hash [Hash]
    # @return [Object]
    def restore_hash(hash)
      if hash.key?("json_class")
        restore_instance(hash)
      elsif hash.key?("__source_file__") && File.basename(hash["__source_file__"], ".json") == "MapInfos"
        # 特殊处理 MapInfos，将 key 转为 Integer
        hash.except("__source_file__").transform_keys(&:to_i).transform_values { |v| restore_value(v) }
      else
        # 普通 Hash，递归恢复值
        hash.transform_values { |v| restore_value(v) }
      end
    end

    # 恢复类实例
    # @param data [Hash] 包含 json_class 的哈希
    # @return [Object] 恢复后的实例
    def restore_instance(data)
      class_name = data["json_class"]
      return data["s"].to_sym if class_name == "Symbol" && data.key?("s")

      klass = find_class(class_name)
      obj = instantiate_object(klass, data)
      populate_attributes(obj, data) if obj
      obj
    end

    # 查找类常量
    # @param class_name [String]
    # @return [Class]
    def find_class(class_name)
      Object.const_get(class_name)
    rescue NameError
      raise NameError, "错误：未找到类 '#{class_name}'。请确保已加载相应的 RGSS 定义 (#{File.exist?(File.expand_path("../#{@rgss_version.downcase}.rb", __FILE__)) ? "已加载" : "未加载？"}).", caller
    end

    # 实例化对象
    # @param klass [Class]
    # @param data [Hash] JSON 数据
    # @return [Object] 新实例
    def instantiate_object(klass, data)
      # 确认优先使用注册表
      if CLASS_INSTANTIATORS.key?(klass.name)
        begin
          return CLASS_INSTANTIATORS[klass.name].call(data, @rgss_version, self)
        rescue => e
          raise "实例化特殊类(注册表) #{klass.name} 时出错: #{e.message}\n原始回溯:\n#{e.backtrace.first(5).join("\n")}"
        end
      end
      # 如果不在注册表中，才走通用逻辑
      generic_instantiate(klass, data)
    end

    # 通用实例化
    # @param klass [Class]
    # @param data [Hash]
    # @return [Object]
    def generic_instantiate(klass, data)
      init_method = nil
      begin
        init_method = klass.instance_method(:initialize)
      rescue NameError
        begin
          return klass.new # 类没有自定义 initialize，调用默认 new
        rescue ArgumentError => e_new
          raise "实例化 #{klass.name} (无自定义 initialize) 时出错: #{e_new.message}"
        end
      end

      needs_version = method_needs_version_arg?(init_method)

      begin
        if needs_version
          klass.new(@rgss_version)
        elsif init_method.arity == 0 || init_method.arity == -1 # 无参数或可选参数
          klass.new
        else
          raise ArgumentError, "类 #{klass.name} 的 initialize 需要参数 (arity=#{init_method.arity})，但未在注册表中定义特殊处理方式。"
        end
      rescue ArgumentError => e
        # 记录更详细的调用信息
        actual_args_desc = needs_version ? "1 argument (#{@rgss_version})" : "0 arguments"
        raise ArgumentError, "实例化通用类 #{klass.name} 时参数不匹配。错误: #{e.message}. " \
                             "尝试调用方式: #{klass.name}.new(#{actual_args_desc}). " \
                             "检查 #{klass.name}#initialize 定义是否正确，或是否应加入 CLASS_INSTANTIATORS？"
      rescue => e
        raise "实例化通用类 #{klass.name} 时发生未知错误: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    # 填充对象属性
    # @param obj [Object]
    # @param data [Hash]
    def populate_attributes(obj, data)
      data.each do |key, value|
        next if key == "json_class" || key == "__source_file__"
        ivar_symbol = key.to_sym
        has_ivar = obj.instance_variable_defined?(ivar_symbol)
        setter_method_name = ivar_symbol.to_s[1..-1] + "=" # 从 "@attribute" 生成 "attribute="
        setter_method = setter_method_name.to_sym
        has_setter = obj.respond_to?(setter_method)

        unless has_ivar || has_setter
          # 仅在非预期情况下（非已知的不匹配属性）打印警告
          known_mismatches = {
            "RPG::Animation::Timing" => ["@condition"],
            "RPG::Enemy" => ["@hit", "@eva"],
            "RPG::State" => ["@release_by_damage"],
            "RPG::System" => ["@_"],
            "RPG::Map" => ["@features"],
            "RPG::BGM" => ["@features"],
            "RPG::BGS" => ["@features"],
            "RPG::Event" => ["@features"],
            "RPG::Event::Page" => ["@features"],
            "RPG::Event::Page::Condition" => ["@features"],
            "RPG::Event::Page::Graphic" => ["@features"],
            "RPG::MoveRoute" => ["@features"],
            "RPG::MoveCommand" => ["@features"],
            "RPG::EventCommand" => ["@features"],
            "RPG::MapInfo" => ["@features"],
          # 可以继续添加其他已知的不匹配项
          }
          unless known_mismatches[obj.class.name]&.include?(ivar_symbol.to_s)
            puts "[警告] #{obj.class} 既没有实例变量 #{ivar_symbol} 也没有 setter 方法 #{setter_method}。跳过属性 '#{key}'。"
          end
          next
        end

        begin
          restored_value = restore_value(value)
          if ivar_symbol == :@events && obj.is_a?(RPG::Map) && restored_value.is_a?(Hash)
            restored_hash = restored_value.transform_keys(&:to_i)
            if has_setter
              obj.send(setter_method, restored_hash)
            else
              obj.instance_variable_set(ivar_symbol, restored_hash)
            end
          elsif has_setter
            obj.send(setter_method, restored_value)
          elsif has_ivar
            obj.instance_variable_set(ivar_symbol, restored_value)
          end
        rescue TypeError => e
          puts "[警告] 为 #{obj.class} 设置属性 #{ivar_symbol} 时 TypeError: #{e.message} (值类型: #{value.class} -> #{restored_value.class rescue "未知"})。跳过。"
        rescue ArgumentError => e
          puts "[警告] 为 #{obj.class} 设置属性 #{ivar_symbol} 时 ArgumentError: #{e.message}。跳过。"
        rescue => e
          puts "[警告] 为 #{obj.class} 设置属性 #{ivar_symbol} 时未知错误: #{e.class}: #{e.message}。跳过。"
          puts e.backtrace.first(3).map { |l| "    #{l}" }.join("\n")
        end
      end
    end

    # 检查方法（如 initialize）是否需要 rgss_version 参数
    # @param method_obj [Method]
    # @return [Boolean]
    def method_needs_version_arg?(method_obj)
      arity = method_obj.arity
      if arity == 1 || arity < 0
        begin
          params = method_obj.parameters
          return params.any? && params.first[0] != :rest && params.first[1] == :rgss_version
        rescue NameError, NoMethodError
          # puts "[调试] 无法检查 #{method_obj.owner}##{method_obj.name} 的参数名，基于 arity=#{arity} 判断。"
          return arity == 1
        end
      end
      false
    end
  end # RvdataRestorer
end # Converter
