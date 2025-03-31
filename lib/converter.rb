# 包含核心的 RVData <-> JSON 转换逻辑

require "oj"
require "fileutils"
require "set"

# 转换器模块，包含 IO、导出器和恢复器
module Converter
  # 文件 IO 操作子模块
  module IO
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

    def self.load_json_data(input_file)
      begin
        json_string = File.read(input_file, encoding: "UTF-8")
        # symbol_keys: false 确保键是字符串，与 JsonExporter 保持一致
        data = Oj.load(json_string, mode: :compat, symbol_keys: false)
        # MapInfos 的特殊处理保持不变
        if data.is_a?(Hash) && File.basename(input_file, ".json") == "MapInfos"
          data["__source_file__"] = input_file # 注入来源信息用于恢复 MapInfos key 类型
        end
        data
      rescue Oj::ParseError => e # 捕获 Oj 的解析错误
        raise "JSON 解析错误 (Oj)，文件 '#{input_file}': #{e.message}"
      rescue => e
        raise "读取或解析 JSON 文件 '#{input_file}' 时出错: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    def self.write_json_data(output_file, data)
      FileUtils.mkdir_p(File.dirname(output_file))
      begin
        # mode: :compat 确保输出标准 JSON
        # indent: 2 用于格式化输出，类似 pretty_generate
        json_string = Oj.dump(data, mode: :compat, indent: 2)
        File.write(output_file, json_string, encoding: "UTF-8")
      rescue => e
        raise "写入 JSON 文件 '#{output_file}' 时出错: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    def self.write_marshal_data(output_file, restored_object)
      FileUtils.mkdir_p(File.dirname(output_file))
      begin
        dumped_data = Marshal.dump(restored_object)
        File.binwrite(output_file, dumped_data)
      rescue TypeError => e
        problem_info = find_problematic_path(restored_object) do |obj|
          (obj.is_a?(Tone) || obj.is_a?(Color)) && obj.instance_variables.any? { |ivar| obj.instance_variable_get(ivar).nil? } ||
          (obj.is_a?(Table) && obj.instance_variable_get(:@elements).nil?) ||
          (obj.is_a?(RPG::Animation::Frame) && obj.instance_variable_get(:@cell_data).nil? && defined?(RPG::Area)) # RGSS2 check
        end
        context = problem_info ? " 问题可能在路径 #{problem_info[:path]} 的对象: #{problem_info[:object].class} #{problem_info[:object].inspect}." : ""
        raise TypeError, "写入 Marshal 文件 '#{output_file}' 时 TypeError: #{e.message}.#{context}"
      rescue => e
        raise "写入 Marshal 文件 '#{output_file}' 时发生未知错误: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    # 辅助函数，用于调试 Marshal dump 时的 TypeError
    def self.find_problematic_path(object, current_path = "root", visited = Set.new, &block)
      return nil unless object.respond_to?(:object_id)
      # 忽略基本类型和字符串
      return nil if object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)
      oid = object.object_id
      return nil if visited.include?(oid) # 防止无限递归
      visited.add(oid)

      result = nil
      begin
        # 检查当前对象是否满足问题条件
        if block.call(object)
          return { path: current_path, object: object }
        end

        # 递归检查子对象
        case object
        when Array
          object.each_with_index do |item, index|
            result = find_problematic_path(item, "#{current_path}[#{index}]", visited, &block)
            break if result
          end
        when Hash
          object.each do |key, value|
            # 跳过我们自己添加的元数据键
            next if key == "__source_file__"
            result = find_problematic_path(value, "#{current_path}{#{key.inspect}}", visited, &block)
            break if result
          end
        else # 其他对象，检查实例变量
          if object.respond_to?(:instance_variables)
            object.instance_variables.each do |ivar|
              # 跳过内部变量
              next if ivar.to_s.start_with?("@_")
              begin
                value = object.instance_variable_get(ivar)
                result = find_problematic_path(value, "#{current_path}.#{ivar}", visited, &block)
                break if result
              rescue => e
                # 忽略获取实例变量时可能发生的错误
              end
            end
          end
        end
      ensure
        # 清理访问记录，允许其他路径访问该对象
        visited.delete(oid)
      end
      result
    end
  end # IO

  # 将 Ruby 对象转换为适合 JSON 序列化的数据结构 (负责 unpack 和 过滤)
  class JsonExporter
    # 定义在导出特定版本 JSON 时应被过滤掉的属性
    DEPRECATED_ATTRIBUTES = {
      "RGSS3" => { # 导出为 RGSS3 JSON 时，过滤掉这些 RGSS2 兼容属性 或 非标准属性
        "RPG::Animation::Timing" => Set.new([:@condition]),
        "RPG::Enemy" => Set.new([:@hit, :@eva]),
        "RPG::State" => Set.new([:@release_by_damage, :@reduce_hit_ratio, :@atk_rate, :@def_rate, :@spi_rate, :@agi_rate, :@nonresistance, :@offset_by_opposite, :@slip_damage, :@battle_only, :@hold_turn, :@auto_release_prob, :@element_set, :@state_set]),
        "RPG::Actor" => Set.new([:@exp_basis, :@exp_inflation, :@parameters, :@weapon_id, :@armor1_id, :@armor2_id, :@armor3_id, :@armor4_id, :@two_swords_style, :@fix_equipment, :@auto_battle, :@super_guard, :@pharmacology, :@critical_bonus]),
        "RPG::Armor" => Set.new([:@kind, :@eva, :@atk, :@spi, :@agi, :@prevent_critical, :@half_mp_cost, :@double_exp_gain, :@auto_hp_recover, :@element_set, :@state_set]),
        "RPG::Weapon" => Set.new([:@hit, :@atk, :@def, :@spi, :@agi, :@two_handed, :@fast_attack, :@dual_attack, :@critical_bonus, :@element_set, :@state_set]),
        "RPG::Item" => Set.new([:@hp_recovery_rate, :@hp_recovery, :@mp_recovery_rate, :@mp_recovery, :@parameter_type, :@parameter_points]),
        "RPG::Skill" => Set.new([:@hit]),
        "RPG::Troop::Member" => Set.new([:@immortal]),
      },
      "RGSS2" => { # 导出为 RGSS2 JSON 时，过滤掉这些 RGSS3 特有属性 或 非标准属性
        "RPG::Animation::Timing" => Set.new([:@condition]),
        "RPG::BaseItem" => Set.new([:@features]), # 应用于所有 BaseItem 子类
        "RPG::Actor" => Set.new([:@nickname, :@max_level, :@equips]),
        "RPG::Class" => Set.new([:@exp_params, :@params, :@features]),
        "RPG::UsableItem" => Set.new([:@success_rate, :@repeats, :@tp_gain, :@hit_type, :@damage, :@effects]),
        "RPG::Skill" => Set.new([:@stype_id, :@tp_cost, :@required_wtype_id1, :@required_wtype_id2]),
        "RPG::Item" => Set.new([:@itype_id]),
        "RPG::EquipItem" => Set.new([:@price, :@etype_id, :@params, :@features]), # EquipItem 是 RGSS3 基类
        "RPG::Weapon" => Set.new([:@wtype_id, :@etype_id, :@params, :@features]), # RGSS3 Weapon 属性
        "RPG::Armor" => Set.new([:@atype_id, :@etype_id, :@params, :@features]), # RGSS3 Armor 属性
        "RPG::Enemy" => Set.new([:@params, :@drop_items, :@features]), # RGSS3 Enemy 属性
        "RPG::State" => Set.new([:@remove_at_battle_end, :@remove_by_restriction, :@auto_removal_timing, :@min_turns, :@max_turns, :@remove_by_damage, :@chance_by_damage, :@remove_by_walking, :@steps_to_remove, :@features]), # RGSS3 State 属性
        "RPG::System" => Set.new([:@japanese, :@currency_unit, :@skill_types, :@weapon_types, :@armor_types, :@title1_name, :@title2_name, :@opt_draw_title, :@opt_use_midi, :@opt_transparent, :@opt_followers, :@opt_slip_death, :@opt_floor_death, :@opt_display_tp, :@opt_extra_exp, :@window_tone, :@battleback1_name, :@battleback2_name]), # RGSS3 System 属性
        "RPG::System::Terms" => Set.new([:@basic, :@params, :@etypes, :@commands]), # RGSS3 Terms 属性
        "RPG::System::TestBattler" => Set.new([:@equips]), # RGSS3 TestBattler 属性
        "RPG::Map" => Set.new([:@display_name, :@tileset_id, :@specify_battleback, :@battleback1_name, :@battleback2_name, :@note]), # RGSS3 Map 属性
        "RPG::Map::Encounter" => Set.new([:@region_set]), # RGSS3 Encounter 属性
      },
    }.freeze

    def initialize(rgss_version)
      @rgss_version = rgss_version
      @visited_unpack = Set.new
      @visited_clean = {} # 用于处理循环引用
    end

    # 主导出方法：先解包，再清理
    def export(object)
      @visited_unpack.clear
      unpack_recursively(object) # 递归解包字符串
      @visited_clean.clear
      cleaned_data = clean_for_export(object) # 转换为纯 Ruby 结构并过滤
      cleaned_data
    end

    private

    # 递归解包对象内部的字符串
    def unpack_recursively(object)
      return if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol)
      return if object.is_a?(String) # 字符串本身不需要递归
      return unless object.respond_to?(:object_id) # 只处理对象
      oid = object.object_id
      return if @visited_unpack.include?(oid) # 防止无限递归
      @visited_unpack.add(oid)

      begin
        # 如果对象响应 unpack_names，调用它
        call_unpack_names(object) if object.respond_to?(:unpack_names)

        # 递归处理实例变量、数组元素或哈希值
        if object.respond_to?(:instance_variables)
          object.instance_variables.each do |ivar|
            next if ivar.to_s.start_with?("@_") # 跳过内部变量
            begin
              ivar_value = object.instance_variable_get(ivar)
              unpack_recursively(ivar_value)
            rescue => e
              # 忽略读取实例变量时可能发生的错误
            end
          end
        elsif object.is_a?(Array)
          object.each { |item| unpack_recursively(item) }
        elsif object.is_a?(Hash)
          object.each do |key, value|
            unpack_recursively(key) # Key 也可能是需要解包的对象（虽然不太常见）
            unpack_recursively(value)
          end
        end
      ensure
        # 在单次 export 过程中保持 visited 状态
      end
    end

    # 安全地调用对象的 unpack_names 方法
    def call_unpack_names(object)
      method_obj = object.method(:unpack_names)
      needs_version = method_needs_version_arg?(method_obj)

      begin
        if needs_version
          object.unpack_names(@rgss_version)
        elsif method_obj.arity == 0 # 明确需要0个参数
          object.unpack_names
        else # 其他情况 (arity -1, -2 等)，尝试无参数调用，如果失败再尝试带版本参数
          begin
            object.unpack_names
          rescue ArgumentError
            if needs_version # 如果检查结果是需要版本参数
              object.unpack_names(@rgss_version)
            else
              raise # 如果检查结果是不需要版本参数，那可能是其他问题，重新抛出异常
            end
          end
        end
      rescue ArgumentError => e
        puts "[警告] 调用 #{object.class}#unpack_names 时参数错误: #{e.message} (方法 arity: #{method_obj.arity}, 需要版本: #{needs_version})"
      rescue => e
        puts "[警告] 在 #{object.class} 上执行 unpack_names 时出错: #{e.class}: #{e.message}"
      end
    end

    # 检查方法是否需要 rgss_version 参数
    def method_needs_version_arg?(method_obj)
      arity = method_obj.arity
      # 如果需要1个参数，或者可以接受任意数量参数 (arity < 0)
      if arity == 1 || arity < 0
        begin
          params = method_obj.parameters # 获取参数列表 ([[:req, :arg1], [:opt, :arg2], ...])
          # 检查第一个必需或可选参数是否名为 :rgss_version
          return params.any? && [:req, :opt].include?(params.first[0]) && params.first[1] == :rgss_version
        rescue NameError, NoMethodError # 处理 C 实现的方法等可能无法获取参数名的情况
          # 作为后备，如果 arity 是 1，我们假设它需要版本参数
          return arity == 1
        end
      end
      false # 如果 arity 是 0 或 > 1，则认为不需要版本参数
    end

    # 将解包后的对象转换为纯 Ruby 结构（Hash/Array），并过滤不必要的属性
    def clean_for_export(object)
      # 处理基本类型和 nil
      return object if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)

      return unless object.respond_to?(:object_id)
      oid = object.object_id
      # 如果已处理过此对象（循环引用），直接返回缓存的结果
      return @visited_clean[oid] if @visited_clean.key?(oid)

      cleaned_object = case object
        when Array
          result = []
          @visited_clean[oid] = result # 先存入引用，防止子元素递归回来
          object.each { |item| result << clean_for_export(item) }
          result
        when Hash
          result = {}
          @visited_clean[oid] = result # 先存入引用
          object.each do |key, value|
            cleaned_key = clean_for_export(key)
            cleaned_value = clean_for_export(value)
            result[cleaned_key] = cleaned_value
          end
          result
          # 特殊处理需要保留类信息的基础数据结构
        when Table, Color, Tone, Rect
          result = { "json_class" => object.class.name }
          @visited_clean[oid] = result # 先存入引用
          object.instance_variables.each do |ivar|
            next if ivar.to_s.start_with?("@_") # 跳过内部变量
            key = ivar.to_s # 使用 '@ivar' 作为键
            value = object.instance_variable_get(ivar)
            # Table 的 @elements 需要转换为普通数组
            result[key] = (object.is_a?(Table) && ivar == :@elements) ? value.to_a : clean_for_export(value)
          end
          result
        else # 处理其他自定义 RPG 对象
          class_name_str = object.class.name
          unless class_name_str && !class_name_str.empty?
            puts "[警告] 遇到匿名或未命名类实例，无法导出: #{object.inspect}"
            return nil # 或返回特殊标记
          end

          result = { "json_class" => class_name_str }
          @visited_clean[oid] = result # 先存入引用

          # 获取需要过滤的属性集合
          deprecated_set = DEPRECATED_ATTRIBUTES[@rgss_version][class_name_str] || Set.new
          # 导出为 RGSS2 时，对所有 BaseItem 子类禁用 features
          if @rgss_version == "RGSS2" && object.is_a?(RPG::BaseItem)
            deprecated_set.add(:@features)
          end

          # 遍历实例变量
          if object.respond_to?(:instance_variables)
            object.instance_variables.sort.each do |ivar|
              ivar_s = ivar.to_s

              next if ivar_s.start_with?("@_") # 跳过内部变量
              next if deprecated_set.include?(ivar) # 跳过废弃属性

              # 特殊处理 features (确保只在非 RGSS2 导出 BaseItem 时保留)
              if ivar == :@features
                unless object.is_a?(RPG::BaseItem) && @rgss_version != "RGSS2"
                  next # 不满足条件，跳过
                end
              end

              key = ivar_s # 使用 '@ivar' 作为键
              value = object.instance_variable_get(ivar)
              result[key] = clean_for_export(value) # 递归清理值
            end
          end
          result
        end
      cleaned_object
    end
  end # JsonExporter

  # 从 JSON 解析的数据结构恢复 RVData 对象
  class RvdataRestorer
    # 预定义的特殊类构造器，用于处理需要特定参数的 initialize 方法
    REDUCED_CLASS_INSTANTIATORS = {
      "RPG::Event" => ->(data, version, restorer) { RPG::Event.new(data["@x"], data["@y"]) },
      "RPG::EventCommand" => ->(data, version, restorer) { RPG::EventCommand.new(data["@code"], data["@indent"], restorer.restore_value(data["@parameters"])) },
      "RPG::MoveCommand" => ->(data, version, restorer) { RPG::MoveCommand.new(data["@code"], restorer.restore_value(data["@parameters"])) },
      "RPG::Map" => ->(data, version, restorer) { RPG::Map.new(data["@width"], data["@height"], version) },
      "Color" => ->(data, version, restorer) { Color.new([data["@red"], data["@green"], data["@blue"], data["@alpha"]]) },
      "Tone" => ->(data, version, restorer) { Tone.new([data["@red"], data["@green"], data["@blue"], data["@gray"]]) },
      "Rect" => ->(data, version, restorer) { Rect.new(data["@x"], data["@y"], data["@width"], data["@height"]) },
      "Table" => ->(data, version, restorer) do
        # 从 JSON 的 @elements 数组恢复 Table 对象
        elements_data = restorer.restore_value(data["@elements"]) || []
        expected_count = data["@num_of_elements"].to_i
        actual_elements = elements_data.flatten.map(&:to_i)
        # 确保元素数量正确
        if actual_elements.size < expected_count
          actual_elements.fill(0, actual_elements.size, expected_count - actual_elements.size)
        elsif actual_elements.size > expected_count && expected_count >= 0
          actual_elements = actual_elements.slice(0, expected_count)
        end
        actual_elements = [] if expected_count == 0
        # 使用恢复的维度和元素数据创建 Table
        Table.new([data["@num_of_dimensions"], data["@xsize"], data["@ysize"],
                   data["@zsize"], expected_count, *actual_elements])
      end,
      "RPG::BaseItem::Feature" => ->(data, version, restorer) { RPG::BaseItem::Feature.new(data["@code"], data["@data_id"], data["@value"]) },
      "RPG::UsableItem::Effect" => ->(data, version, restorer) { RPG::UsableItem::Effect.new(data["@code"], data["@data_id"], data["@value1"], data["@value2"]) },
      # Damage 对象先用 new 创建，后续由 populate_attributes 填充
      "RPG::UsableItem::Damage" => ->(data, version, restorer) { RPG::UsableItem::Damage.new },
    # 其他需要特殊构造的类可以在这里添加
    }.freeze

    def initialize(rgss_version)
      @rgss_version = rgss_version
      @object_cache = {} # 用于处理循环引用 (基于实例？)
    end

    # 主恢复方法
    def restore(data)
      @object_cache.clear # 每次调用都清空缓存
      restore_value(data)
    end

    # 递归恢复值
    def restore_value(value)
      case value
      when Array
        restore_array(value)
      when Hash
        # 检查是否是已缓存的对象（用于循环引用）
        # 注意：由于 Oj :compat 不提供唯一 ID，这里的缓存可能需要更复杂的逻辑或依赖 Marshal
        # 暂时简化，主要依赖 restore_hash 中的 "json_class" 判断
        restore_hash(value)
      else
        value # 基本类型直接返回
      end
    end

    private

    # 恢复数组
    def restore_array(array)
      array.map { |item| restore_value(item) }
    end

    # 恢复哈希
    def restore_hash(hash)
      # 如果包含 "json_class"，则认为是需要实例化的对象
      if hash.key?("json_class")
        restore_instance(hash)
        # 特殊处理 MapInfos 文件，将键转换为整数
      elsif hash.key?("__source_file__") && File.basename(hash["__source_file__"], ".json") == "MapInfos"
        hash.except("__source_file__").transform_keys(&:to_i).transform_values { |v| restore_value(v) }
      else
        # 普通哈希，递归恢复其值
        hash.transform_values { |v| restore_value(v) }
      end
    end

    # 从包含 "json_class" 的哈希恢复对象实例
    def restore_instance(data)
      class_name = data["json_class"]
      # 特殊处理 Symbol (虽然 Oj :compat 不应生成，保留兼容性)
      return data["s"].to_sym if class_name == "Symbol" && data.key?("s")

      # --- 循环引用处理占位 ---
      # cache_key = data.hash # 或其他唯一标识符？
      # return @object_cache[cache_key] if @object_cache.key?(cache_key)
      # ---

      klass = find_class(class_name) # 查找类
      obj = instantiate_object(klass, data) # 实例化对象

      # --- 缓存对象 ---
      # @object_cache[cache_key] = obj if obj
      # ---

      populate_attributes(obj, data) if obj # 填充属性
      obj
    end

    # 根据类名字符串查找类对象
    def find_class(class_name)
      Object.const_get(class_name)
    rescue NameError
      # 改进错误信息
      raise NameError, "错误：未找到类 '#{class_name}'。请确保已加载正确的 RGSS 定义 (lib/#{@rgss_version.downcase}.rb)。", caller
    end

    # 实例化对象（使用预定义构造器或通用构造器）
    def instantiate_object(klass, data)
      if REDUCED_CLASS_INSTANTIATORS.key?(klass.name)
        begin
          # 调用预定义的 lambda 来实例化
          return REDUCED_CLASS_INSTANTIATORS[klass.name].call(data, @rgss_version, self)
        rescue => e
          raise "实例化特殊类(注册表) #{klass.name} 时出错: #{e.message}\nData: #{data.inspect}\n原始回溯:\n#{e.backtrace.first(5).join("\n")}"
        end
      else
        # 使用通用实例化逻辑
        generic_instantiate(klass, data)
      end
    end

    # 通用实例化逻辑（处理需要版本参数或无参数的 initialize）
    def generic_instantiate(klass, data)
      init_method = nil
      begin
        init_method = klass.instance_method(:initialize)
      rescue NameError # 类没有 initialize 方法
        begin
          return klass.new # 尝试无参数调用
        rescue ArgumentError => e_new
          raise ArgumentError, "实例化 #{klass.name} (无自定义 initialize) 时出错: #{e_new.message}"
        end
      end

      needs_version = method_needs_version_arg?(init_method)

      begin
        if needs_version
          klass.new(@rgss_version) # 带版本参数调用
        elsif init_method.arity == 0 || init_method.arity == -1 # 无参数或可变参数
          klass.new
        else # 需要固定数量 > 0 的参数，但不在注册表中
          raise ArgumentError, "类 #{klass.name} 的 initialize 需要 #{init_method.arity} 个参数，但不在注册表中且无法自动处理。"
        end
      rescue ArgumentError => e
        # 改进错误信息
        actual_args_desc = needs_version ? "1 argument (#{@rgss_version})" : "0 arguments"
        raise ArgumentError, "实例化通用类 #{klass.name} 时参数不匹配。错误: #{e.message}. " \
                             "尝试调用方式: #{klass.name}.new(#{actual_args_desc}). " \
                             "检查 #{klass.name}#initialize 定义。"
      rescue => e
        raise "实例化通用类 #{klass.name} 时发生未知错误: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    # 填充对象属性
    def populate_attributes(obj, data)
      data.each do |key, value|
        # 跳过元数据和内部键
        next if key == "json_class" || key == "__source_file__"
        next if key.start_with?("@_") # 兼容 JsonExporter 可能遗漏的内部变量

        # 确保 key 是实例变量格式 (@ivar)
        unless key.start_with?("@")
          # puts "[调试] (恢复) 跳过非实例变量键: #{key} for #{obj.class}"
          next
        end

        ivar_symbol = key.to_sym

        # 检查实例变量或 setter 是否存在
        has_ivar = obj.instance_variable_defined?(ivar_symbol)
        setter_method_name = ivar_symbol.to_s[1..-1] + "="
        setter_method = setter_method_name.to_sym
        has_setter = obj.respond_to?(setter_method)

        # 如果目标对象上既没有这个实例变量也没有对应的 setter，则跳过
        # 这可能是因为 JSON 数据来自于不同版本或有冗余数据
        unless has_ivar || has_setter
          # puts "[警告] (恢复) #{obj.class} 既无实例变量 #{ivar_symbol} 也无 setter 方法 #{setter_method}。跳过 JSON 属性 '#{key}'。"
          next
        end

        begin
          # 递归恢复属性值
          restored_value = restore_value(value)

          # 特殊处理 RPG::Map 的 @events 哈希键（确保是整数）
          if ivar_symbol == :@events && obj.is_a?(RPG::Map) && restored_value.is_a?(Hash)
            restored_hash = restored_value.transform_keys(&:to_i)
            has_setter ? obj.send(setter_method, restored_hash) : obj.instance_variable_set(ivar_symbol, restored_hash)
            # 优先使用 setter 方法赋值
          elsif has_setter
            obj.send(setter_method, restored_value)
            # 否则直接设置实例变量 (如果存在)
          elsif has_ivar
            obj.instance_variable_set(ivar_symbol, restored_value)
            # else 的情况已在前面 next 跳过
          end
        rescue TypeError => e
          puts "[警告] (恢复) 为 #{obj.class} 设置属性 #{ivar_symbol} 时 TypeError: #{e.message}。值: #{value.inspect[0..100]}...。跳过。"
        rescue ArgumentError => e
          puts "[警告] (恢复) 为 #{obj.class} 设置属性 #{ivar_symbol} 时 ArgumentError: #{e.message}。值: #{value.inspect[0..100]}...。跳过。"
        rescue => e
          puts "[警告] (恢复) 为 #{obj.class} 设置属性 #{ivar_symbol} 时未知错误: #{e.class}: #{e.message}。值: #{value.inspect[0..100]}...。跳过。"
        end
      end
    end

    # 检查方法是否需要 rgss_version 参数 (与 JsonExporter 中的逻辑相同)
    def method_needs_version_arg?(method_obj)
      arity = method_obj.arity
      if arity == 1 || arity < 0
        begin
          params = method_obj.parameters
          return params.any? && [:req, :opt].include?(params.first[0]) && params.first[1] == :rgss_version
        rescue NameError, NoMethodError
          return arity == 1
        end
      end
      false
    end
  end # RvdataRestorer
end # Converter
