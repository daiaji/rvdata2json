# 包含核心的 RVData/RXData <-> JSON 转换逻辑

require "oj"        # 用于快速 JSON 解析和生成
require "fileutils" # 用于文件操作，如创建目录
require "set"       # 用于高效地处理已访问对象集合
require "zlib"      # 用于处理 Scripts.rvdata 中的压缩脚本

# Logging 模块应已加载 (通过 application.rb 或直接 require)
# require_relative "logging" # 如果需要独立运行此文件，则取消注释

module Converter

  # --- 输入/输出 模块 ---
  # 处理文件的加载和写入操作
  module IO
    # 从磁盘加载 Marshal (RVData/RXData) 文件
    # @param input_file [String] 输入文件路径
    # @return [Object] 反序列化后的 Ruby 对象
    # @raise [NameError] 如果遇到未定义的类/模块 (通常是 RGSS 版本不匹配)
    # @raise [ArgumentError] 如果文件损坏或版本不匹配
    # @raise [TypeError] 如果类型错误 (通常是 RGSS 版本不匹配)
    # @raise [RuntimeError] 如果发生其他读写或解析错误
    def self.load_marshal_data(input_file)
      file_basename = File.basename(input_file)
      Logging::Log.debug "加载 Marshal 数据: #{file_basename}" if Logging::Log.debug?
      begin
        # 以二进制读取模式打开文件并加载 Marshal 数据
        File.open(input_file, "rb") { |f| Marshal.load(f) }
      rescue ArgumentError => e
        # 处理 Marshal.load 可能抛出的 ArgumentError
        if e.message.include?("undefined class/module") || e.message.include?("allocator is not defined")
          # 明确是类/模块未定义错误
          err_msg = "加载 Marshal 数据 '#{file_basename}' 出错: #{e.message}。请确保加载了正确的 RGSS 定义 (rgss1/2/3.rb)。"
          Logging::Log.error err_msg
          # 抛出 NameError 更符合 Ruby 语义
          raise NameError, err_msg, caller
        else
          # 其他 ArgumentError，可能是文件损坏或版本不匹配
          err_msg = "加载 Marshal 数据 '#{file_basename}' 时发生参数错误 (可能是版本不匹配或文件损坏): #{e.message}"
          Logging::Log.error err_msg
          raise ArgumentError, err_msg
        end
      rescue TypeError => e
        # 处理类型错误，通常也与 RGSS 定义有关
        err_msg = "加载 Marshal 数据 '#{file_basename}' 时发生类型错误 (请确保加载了正确的 RGSS 定义): #{e.message}"
        Logging::Log.error err_msg
        raise TypeError, err_msg
      rescue => e
        # 捕获其他所有可能的异常 (文件读写、未知解析错误等)
        err_msg = "读取或解析 Marshal 文件 '#{file_basename}' 时出错: #{e.class}: #{e.message}\n调用栈:\n#{e.backtrace.join("\n")}"
        Logging::Log.error err_msg
        raise "读取或解析 Marshal 文件 '#{file_basename}' 时出错。详情请查看日志。"
      end
    end

    # 从磁盘加载 JSON 文件
    # @param input_file [String] 输入文件路径
    # @return [Object] 解析后的 Ruby 对象 (Hash, Array, etc.)
    # @raise [RuntimeError] 如果发生 JSON 解析错误或其他读写错误
    def self.load_json_data(input_file)
      file_basename = File.basename(input_file)
      Logging::Log.debug "加载 JSON 数据: #{file_basename}" if Logging::Log.debug?
      begin
        # 读取 UTF-8 编码的 JSON 文件
        json_string = File.read(input_file, encoding: "UTF-8")
        # 使用 Oj 解析 JSON，兼容模式，不使用 Symbol 键
        data = Oj.load(json_string, mode: :compat, symbol_keys: false)
        # 特殊处理: 如果是 MapInfos.json，添加来源文件信息 (用于恢复时特殊处理键)
        if data.is_a?(Hash) && File.basename(input_file, ".json") == "MapInfos"
          data["__rvdata2json_source_file__"] = input_file
        end
        data
      rescue Oj::ParseError => e
        # 处理 JSON 解析错误
        err_msg = "文件 '#{input_file}' 中 JSON 解析错误 (Oj): #{e.message}"
        Logging::Log.error err_msg
        raise "文件 '#{file_basename}' 中 JSON 解析错误。详情请查看日志。"
      rescue => e
        # 捕获其他所有可能的异常 (文件读写等)
        err_msg = "读取或解析 JSON 文件 '#{input_file}' 时出错: #{e.class}: #{e.message}\n调用栈:\n#{e.backtrace.join("\n")}"
        Logging::Log.error err_msg
        raise "读取或解析 JSON 文件 '#{file_basename}' 时出错。详情请查看日志。"
      end
    end

    # 将 Ruby 数据结构写入 JSON 文件
    # @param output_file [String] 输出文件路径
    # @param data [Object] 要写入的数据
    # @raise [RuntimeError] 如果发生写入错误
    def self.write_json_data(output_file, data)
      file_basename = File.basename(output_file)
      Logging::Log.debug "写入 JSON 数据到: #{file_basename}" if Logging::Log.debug?
      # 确保输出目录存在
      FileUtils.mkdir_p(File.dirname(output_file))
      begin
        # 使用 Oj 生成格式化的 JSON 字符串 (兼容模式, 2空格缩进)
        json_string = Oj.dump(data, mode: :compat, indent: 2)
        # 以 UTF-8 编码写入文件
        File.write(output_file, json_string, encoding: "UTF-8")
      rescue => e
        # 捕获所有可能的写入异常
        err_msg = "写入 JSON 文件 '#{output_file}' 时出错: #{e.class}: #{e.message}\n调用栈:\n#{e.backtrace.join("\n")}"
        Logging::Log.error err_msg
        raise "写入 JSON 文件 '#{file_basename}' 时出错。详情请查看日志。"
      end
    end

    # 将 Ruby 对象序列化并写入 Marshal (RVData/RXData) 文件
    # @param output_file [String] 输出文件路径
    # @param restored_object [Object] 要序列化的对象
    # @raise [TypeError] 如果对象结构不正确，导致 Marshal 失败 (常见于 Table, Color, Tone)
    # @raise [RuntimeError] 如果发生其他写入错误
    def self.write_marshal_data(output_file, restored_object)
      file_basename = File.basename(output_file)
      Logging::Log.debug "写入 Marshal 数据到: #{file_basename}" if Logging::Log.debug?
      # 确保输出目录存在
      FileUtils.mkdir_p(File.dirname(output_file))
      begin
        # 序列化对象
        dumped_data = Marshal.dump(restored_object)
        # 以二进制模式写入文件
        File.binwrite(output_file, dumped_data)
      rescue TypeError => e
        # 捕获常见的序列化 TypeError，并尝试定位问题
        problem_info = find_problematic_path(restored_object) do |obj|
          # 检查 Color/Tone 是否有 nil 属性
          is_bad_color_tone = (obj.is_a?(Tone) || obj.is_a?(Color)) && obj.instance_variables.any? { |ivar| obj.instance_variable_get(ivar).nil? }
          # 检查 Table 结构是否完整且元素类型正确
          is_bad_table = obj.is_a?(Table) && (obj.instance_variable_get(:@elements).nil? ||
                                              !obj.instance_variable_get(:@elements).is_a?(Array) ||
                                              obj.instance_variable_get(:@elements).any? { |el| !el.is_a?(Integer) } ||
                                              obj.instance_variable_get(:@xsize).nil? ||
                                              obj.instance_variable_get(:@ysize).nil? ||
                                              obj.instance_variable_get(:@zsize).nil?)
          # 检查 Animation::Frame 的 cell_data 是否存在 (如果 Frame 类已定义)
          is_bad_anim_frame = defined?(RPG::Animation::Frame) && obj.is_a?(RPG::Animation::Frame) && obj.instance_variable_get(:@cell_data).nil?
          # 检查 Area 的 rect 是否存在 (如果 Area 类已定义)
          is_bad_area = defined?(RPG::Area) && obj.is_a?(RPG::Area) && obj.instance_variable_get(:@rect).nil?

          is_bad_color_tone || is_bad_table || is_bad_anim_frame || is_bad_area
        end
        # 构造错误消息上下文
        context = problem_info ? " 问题可能位于路径 #{problem_info[:path]} 的对象: #{problem_info[:object].class} #{problem_info[:object].inspect[0..200]}..." : ""
        err_msg = "写入 Marshal 文件 '#{output_file}' 时发生 TypeError: #{e.message}。#{context} 请检查对象初始化和恢复逻辑。"
        Logging::Log.error err_msg
        raise TypeError, "写入 Marshal 文件 '#{file_basename}' 时发生 TypeError。详情请查看日志。"
      rescue => e
        # 捕获其他所有可能的写入异常
        err_msg = "写入 Marshal 文件 '#{output_file}' 时发生未知错误: #{e.class}: #{e.message}\n调用栈:\n#{e.backtrace.join("\n")}"
        Logging::Log.error err_msg
        raise "写入 Marshal 文件 '#{file_basename}' 时出错。详情请查看日志。"
      end
    end

    # 递归查找对象图中满足特定条件的第一个对象及其路径 (用于调试)
    # @param object [Object] 起始对象
    # @param current_path [String] 当前路径字符串
    # @param visited [Set] 已访问对象的 object_id 集合，防止无限循环
    # @param block [Proc] 用于检查对象是否满足条件的块
    # @return [Hash, nil] 包含 :path 和 :object 的哈希，如果找到则返回；否则返回 nil
    def self.find_problematic_path(object, current_path = "root", visited = Set.new, &block)
      # 跳过基本类型和无 object_id 的对象
      return nil unless object.respond_to?(:object_id)
      return nil if object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)

      oid = object.object_id
      # 如果已访问过此对象实例，则返回 nil 防止循环
      return nil if visited.include?(oid)
      visited.add(oid)

      result = nil
      begin
        # 检查当前对象是否满足条件
        if block.call(object)
          Logging::Log.debug "在路径 #{current_path} 找到问题对象" if Logging::Log.debug?
          return { path: current_path, object: object }
        end

        # 根据对象类型递归遍历
        case object
        when Array
          # 遍历数组元素
          object.each_with_index do |item, index|
            result = find_problematic_path(item, "#{current_path}[#{index}]", visited, &block)
            break if result # 找到后立即停止遍历
          end
        when Hash
          # 遍历哈希值 (忽略内部使用的键)
          object.reject { |k, _| k == "__rvdata2json_source_file__" }.each do |key, value|
            result = find_problematic_path(value, "#{current_path}{#{key.inspect}}", visited, &block)
            break if result # 找到后立即停止遍历
          end
        else
          # 遍历对象的实例变量 (如果支持)
          if object.respond_to?(:instance_variables)
            object.instance_variables.each do |ivar|
              # 跳过内部使用的变量 (如 Marshal 加载时可能产生的)
              next if ivar.to_s.start_with?("@_")
              begin
                value = object.instance_variable_get(ivar)
                result = find_problematic_path(value, "#{current_path}.#{ivar}", visited, &block)
                break if result # 找到后立即停止遍历
              rescue StandardError => e
                # 忽略访问实例变量时可能发生的错误 (例如权限问题)
                Logging::Log.debug "在 find_problematic_path 中访问实例变量 #{ivar} 时出错: #{e.message}" if Logging::Log.debug?
              end
            end
          end
        end
      ensure
        # 确保在函数返回前将当前对象移出 visited 集合，允许其他路径访问它
        visited.delete(oid)
      end
      result
    end
  end # module IO

  # --- JSON 导出器 类 ---
  # 负责将加载的 Ruby 对象转换为适合 JSON 导出的格式
  class JsonExporter
    # 定义不同 RGSS 版本导出时需要移除的多余属性
    # (这些属性要么是旧版本的残留，要么在目标版本中由其他机制处理)
    ATTRIBUTES_REMOVED = {
      "RGSS3" => { # 导出为 RGSS3 格式时，移除这些来自 RGSS1/2 的属性
        "RPG::Actor" => Set.new([:@exp_basis, :@exp_inflation, :@parameters, :@weapon_id, :@armor1_id, :@armor2_id, :@armor3_id, :@armor4_id, :@two_swords_style, :@fix_equipment, :@auto_battle, :@super_guard, :@pharmacology, :@critical_bonus]),
        "RPG::Class" => Set.new([:@position, :@weapon_set, :@armor_set, :@element_ranks, :@state_ranks, :@skill_name_valid, :@skill_name]),
        "RPG::Skill" => Set.new([:@base_damage, :@variance, :@atk_f, :@spi_f, :@physical_attack, :@damage_to_mp, :@absorb_damage, :@ignore_defense, :@element_set, :@plus_state_set, :@minus_state_set, :@hit]),
        "RPG::Item" => Set.new([:@base_damage, :@variance, :@atk_f, :@spi_f, :@physical_attack, :@damage_to_mp, :@absorb_damage, :@ignore_defense, :@element_set, :@plus_state_set, :@minus_state_set, :@hp_recovery_rate, :@hp_recovery, :@mp_recovery_rate, :@mp_recovery, :@parameter_type, :@parameter_points]),
        "RPG::Weapon" => Set.new([:@hit, :@atk, :@def, :@spi, :@agi, :@two_handed, :@fast_attack, :@dual_attack, :@critical_bonus, :@element_set, :@state_set]),
        "RPG::Armor" => Set.new([:@kind, :@eva, :@atk, :@spi, :@agi, :@prevent_critical, :@half_mp_cost, :@double_exp_gain, :@auto_hp_recover, :@element_set, :@state_set]),
        "RPG::Enemy" => Set.new([:@maxhp, :@maxmp, :@atk, :@def, :@spi, :@agi, :@hit, :@eva, :@drop_item1, :@drop_item2, :@levitate, :@has_critical, :@element_ranks, :@state_ranks]),
        "RPG::Enemy::Action" => Set.new([:@kind, :@basic]),
        "RPG::State" => Set.new([:@atk_rate, :@def_rate, :@spi_rate, :@agi_rate, :@nonresistance, :@offset_by_opposite, :@slip_damage, :@battle_only, :@release_by_damage, :@hold_turn, :@auto_release_prob, :@shock_release_prob, :@element_set, :@state_set, :@guard_element_set, :@plus_state_set, :@minus_state_set]),
        "RPG::System" => Set.new([:@magic_number, :@passages]), # 移除 RGSS1/2 的属性
        "RPG::System::TestBattler" => Set.new([:@weapon_id, :@armor1_id, :@armor2_id, :@armor3_id, :@armor4_id]),
        "RPG::Troop::Member" => Set.new([:@immortal]), # 移除 RGSS1/2 的属性
        "RPG::Animation::Timing" => Set.new([:@condition]), # 移除 RGSS1 的属性
        "RPG::Map" => Set.new([:@battleback_floor_name, :@battleback_wall_name]), # 移除 RGSS2 的属性
        "RPG::Tileset" => Set.new([:@tileset_name, :@autotile_names, :@panorama_name, :@panorama_hue, :@fog_name, :@fog_hue, :@fog_opacity, :@fog_blend_type, :@fog_zoom, :@fog_sx, :@fog_sy, :@battleback_name, :@passages, :@priorities, :@terrain_tags]), # 移除 RGSS1 的属性
      },
      "RGSS2" => { # 导出为 RGSS2 格式时，移除这些来自 RGSS1 或 RGSS3 的属性
        "RPG::System" => Set.new([:@magic_number]), # 移除 RGSS1 的属性
        "RPG::State" => Set.new([:@shock_release_prob, :@guard_element_set, :@plus_state_set, :@minus_state_set]), # 移除 RGSS1 的属性
        "RPG::Animation::Timing" => Set.new([:@condition]), # 移除 RGSS1 的属性
        "RPG::Tileset" => Set.new([:@tileset_name, :@autotile_names, :@panorama_name, :@panorama_hue, :@fog_name, :@fog_hue, :@fog_opacity, :@fog_blend_type, :@fog_zoom, :@fog_sx, :@fog_sy, :@battleback_name, :@passages, :@priorities, :@terrain_tags]), # 移除 RGSS1 的属性
      # 注意: 移除 RGSS3 特有属性 (如 features) 通常在 clean_for_export 中通过检查类是否存在实现，这里无需列出
      },
      "RGSS1" => {}, # 导出为 RGSS1 时，通常不需要移除旧属性，而是由加载 RGSS1 定义来确保结构
    }.freeze

    # 初始化导出器
    # @param rgss_version [String] 目标 RGSS 版本 ("RGSS1", "RGSS2", "RGSS3")
    def initialize(rgss_version)
      @rgss_version = rgss_version
      # 用于在递归解包和清理时跟踪已访问对象，防止无限循环
      @visited_unpack = Set.new
      @visited_clean = {} # 使用 Hash 存储清理结果以支持循环引用
      Logging::Log.debug "JsonExporter 初始化完成，目标版本: #{@rgss_version}" if Logging::Log.debug?
    end

    # 执行导出过程
    # @param object [Object] 从 Marshal 文件加载的顶层对象
    # @return [Object] 清理和转换后的数据结构，适合 JSON 序列化
    def export(object)
      Logging::Log.debug "开始 JSON 导出..." if Logging::Log.debug?
      @visited_unpack.clear # 清空上次导出的访问记录
      # 步骤 1: 递归调用 unpack_names (主要用于解包字符串)
      unpack_recursively(object)
      Logging::Log.debug "字符串解包完成。" if Logging::Log.debug?
      @visited_clean.clear # 清空上次导出的清理缓存
      # 步骤 2: 递归清理对象结构，移除不兼容属性，转换特殊类
      cleaned_data = clean_for_export(object)
      Logging::Log.debug "对象清理完成。" if Logging::Log.debug?
      cleaned_data
    end

    private

    # 递归遍历对象图，调用每个对象的 unpack_names 方法 (如果存在)
    # 主要用于将可能非 UTF-8 的字符串转换为 UTF-8
    def unpack_recursively(object)
      # 跳过基本类型和 Symbol
      return if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)
      # 必须有 object_id 才能跟踪访问
      return unless object.respond_to?(:object_id)

      oid = object.object_id
      # 如果已访问过，直接返回
      return if @visited_unpack.include?(oid)
      # Logging::Log.debug "Unpacking: #{object.class} (oid: #{oid})" if Logging::Log.debug? # 此日志过于频繁，默认注释掉

      @visited_unpack.add(oid)
      begin
        # 调用对象的 unpack_names 方法 (如果存在)
        call_unpack_names(object) if object.respond_to?(:unpack_names)

        # 递归遍历子对象
        if object.respond_to?(:instance_variables)
          # 遍历实例变量
          object.instance_variables.each do |ivar|
            next if ivar.to_s.start_with?("@_") # 跳过内部变量
            begin
              ivar_value = object.instance_variable_get(ivar)
              unpack_recursively(ivar_value)
            rescue StandardError => e
              Logging::Log.debug "解包实例变量 #{ivar} (在 #{object.class} 上) 时出错: #{e.message}" if Logging::Log.debug?
            end
          end
        elsif object.is_a?(Array)
          # 遍历数组元素
          object.each { |item| unpack_recursively(item) }
        elsif object.is_a?(Hash)
          # 遍历哈希键和值 (忽略内部键)
          object.reject { |k, _| k == "__rvdata2json_source_file__" }.each do |key, value|
            unpack_recursively(key)
            unpack_recursively(value)
          end
        end
      ensure
        # 注意: 这里不需要从 @visited_unpack 中移除，因为解包只需进行一次
        # ensure 块在这里主要是为了结构完整性，以防未来添加需要在结束后执行的代码
      end
    end

    # 安全地调用对象的 unpack_names 方法，并记录可能的错误
    def call_unpack_names(object)
      begin
        object.unpack_names
      rescue ArgumentError => e
        # 忽略常见的 "wrong number of arguments" 错误，这通常发生在 super 调用链中
        unless e.message.include?("wrong number of arguments")
          Logging::Log.warn "调用 #{object.class}#unpack_names 时发生参数错误: #{e.message}"
        end
      rescue NoMethodError => e
        # 忽略常见的 super 调用错误
        unless e.message.include?("super: no superclass method")
          Logging::Log.warn "在 #{object.class} 上执行 unpack_names 时发生 NoMethodError: #{e.class}: #{e.message}"
        end
      rescue => e
        # 记录其他未预料到的错误
        Logging::Log.warn "在 #{object.class} 上执行 unpack_names 时出错: #{e.class}: #{e.message}"
      end
    end

    # 递归清理对象，为 JSON 导出做准备
    # - 添加 "json_class" 键用于恢复
    # - 转换特殊类 (Table, Color, Tone, Rect) 为 Hash
    # - 移除目标 RGSS 版本不支持的属性
    # - 处理循环引用
    def clean_for_export(object)
      # 直接返回基本类型和 Symbol
      return object if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)

      # 处理没有 object_id 的特殊情况 (理论上不常见，除非是某些 C 扩展类型)
      unless object.respond_to?(:object_id)
        if object.is_a?(Array)
          # 如果是数组，递归清理其元素
          return object.map { |item| clean_for_export(item) }
        elsif object.is_a?(Hash)
          # 如果是哈希，递归清理其键和值
          result = {}
          object.reject { |k, _| k == "__rvdata2json_source_file__" }.each do |key, value|
            cleaned_key = clean_for_export(key)
            cleaned_value = clean_for_export(value)
            result[cleaned_key] = cleaned_value
          end
          return result
        else
          # 无法处理的类型
          Logging::Log.error "无法处理类型为 #{object.class} 且没有 object_id 的对象。"
          return nil
        end
      end

      oid = object.object_id
      # 如果缓存中已有清理结果 (处理循环引用)，直接返回
      return @visited_clean[oid] if @visited_clean.key?(oid)

      # 获取类名，处理匿名类
      class_name_str = object.class.name
      unless class_name_str && !class_name_str.empty?
        Logging::Log.warn "遇到匿名或未命名类的实例，无法精确导出类型: #{object.inspect[0..100]}..."
        # 尝试作为数组或哈希处理
        if object.is_a?(Array)
          result = []
          @visited_clean[oid] = result # 存入缓存以处理循环
          object.each { |item| result << clean_for_export(item) }
          return result
        elsif object.is_a?(Hash)
          result = {}
          @visited_clean[oid] = result # 存入缓存以处理循环
          object.reject { |k, _| k == "__rvdata2json_source_file__" }.each do |key, value|
            cleaned_key = clean_for_export(key)
            cleaned_value = clean_for_export(value)
            result[cleaned_key] = cleaned_value
          end
          return result
        else
          Logging::Log.error "无法处理匿名或未命名类的实例 (非数组/哈希)。"
          return nil
        end
      end

      # --- 根据对象类型进行清理 ---
      cleaned_object = case object
        when Array
          # 递归清理数组元素
          result = []
          @visited_clean[oid] = result # 存入缓存
          object.each { |item| result << clean_for_export(item) }
          result
        when Hash
          # 特殊处理 MapInfos (键为整数)
          is_map_infos = class_name_str == "Hash" && object.keys.all? { |k| k.is_a?(Integer) }
          result = {}
          @visited_clean[oid] = result # 存入缓存
          object.reject { |k, _| k == "__rvdata2json_source_file__" }.each do |key, value|
            cleaned_key = clean_for_export(key)
            cleaned_value = clean_for_export(value)
            # MapInfos 的键转为字符串，以便 JSON 正确表示
            cleaned_key = cleaned_key.to_s if is_map_infos && cleaned_key.is_a?(Integer)
            result[cleaned_key] = cleaned_value
          end
          result
        when Table
          # 将 Table 转换为包含元数据和元素数组的 Hash
          result = { "json_class" => class_name_str }
          @visited_clean[oid] = result # 存入缓存
          # 记录维度和尺寸
          result["@num_of_dimensions"] = dim = object.num_of_dimensions
          result["@xsize"] = xsize = object.xsize
          result["@ysize"] = ysize = object.ysize
          result["@zsize"] = zsize = object.zsize
          result["@num_of_elements"] = num_elements = object.num_of_elements
          # 获取元素数据，处理可能的 nil 或尺寸不匹配
          elements = object.instance_variable_get(:@elements) || []
          elements = elements[0...num_elements] if elements.size > num_elements && num_elements >= 0
          exported_elements = []
          begin
            # 根据维度重构元素数组的结构
            if num_elements <= 0 || dim <= 0
              exported_elements = []
            elsif dim == 1
              exported_elements = elements
            elsif dim == 2
              # 按 xsize 切片
              exported_elements = (xsize > 0) ? elements.each_slice(xsize).to_a : Array.new([ysize, 0].max) { [] }
            elsif dim == 3
              # 按 xsize * ysize 切片，然后内部再按 xsize 切片
              z_slice_size = xsize * ysize
              if z_slice_size > 0
                exported_elements = elements.each_slice(z_slice_size).map do |z_slice|
                  (xsize > 0) ? z_slice.each_slice(xsize).to_a : Array.new([ysize, 0].max) { [] }
                end
              else
                exported_elements = Array.new([zsize, 0].max) { Array.new([ysize, 0].max) { [] } }
              end
            else
              # 不支持超过 3 维，导出为扁平数组
              exported_elements = elements
              Logging::Log.warn "Table 维度 (#{dim}) > 3 不支持，导出为扁平数组。"
            end
          rescue ArgumentError => e
            # 处理切片等操作可能引发的错误
            Logging::Log.warn "处理 Table 时出错 (维度=#{dim}, 尺寸=#{xsize}x#{ysize}x#{zsize}, 元素数=#{num_elements}): #{e.message}。将返回扁平数组。"
            exported_elements = elements
          end
          result["@elements"] = exported_elements
          result
        when Color, Tone, Rect
          # 将这些简单结构体转换为 Hash，保留实例变量
          result = { "json_class" => class_name_str }
          @visited_clean[oid] = result # 存入缓存
          object.instance_variables.each do |ivar|
            next if ivar.to_s.start_with?("@_") # 跳过内部变量
            key = ivar.to_s
            value = object.instance_variable_get(ivar)
            result[key] = clean_for_export(value) # 递归清理属性值
          end
          result
        else
          # 处理其他 RPG Maker 类对象
          result = { "json_class" => class_name_str }
          @visited_clean[oid] = result # 存入缓存

          # --- 确定要过滤掉的属性 ---
          removed_attrs_for_target = ATTRIBUTES_REMOVED[@rgss_version] || {}
          filter_set = Set.new
          # 遍历继承链，合并所有父类需要过滤的属性
          klass = object.class
          while klass != Object && klass != nil && klass.name
            set_for_class = removed_attrs_for_target[klass.name]
            filter_set.merge(set_for_class) if set_for_class
            # 特殊处理: RGSS2/1 可能加载了 RGSS3 的 BaseItem 定义，需要移除 features
            if (@rgss_version == "RGSS2" || @rgss_version == "RGSS1") &&
               defined?(RPG::BaseItem) && klass.ancestors.include?(RPG::BaseItem)
              filter_set.add(:@features) if removed_attrs_for_target["RPG::BaseItem"]&.include?(:@features)
            end
            klass = klass.superclass
          end
          # --- 过滤属性结束 ---

          # 遍历实例变量，过滤后递归清理
          if object.respond_to?(:instance_variables)
            object.instance_variables.sort.each do |ivar|
              ivar_s = ivar.to_s
              # 跳过内部变量和需要过滤的属性
              next if ivar_s.start_with?("@_")
              next if filter_set.include?(ivar)

              key = ivar_s
              value = nil
              begin
                value = object.instance_variable_get(ivar)
              rescue => e
                # 记录获取实例变量时的错误
                Logging::Log.warn "获取对象 #{object.class} 的实例变量 #{ivar_s} 时出错: #{e.message}。跳过此属性。"
                next
              end
              result[key] = clean_for_export(value) # 递归清理
            end
          end
          result
        end # case object end

      cleaned_object
    end
  end # class JsonExporter

  # --- RVData 恢复器 类 ---
  # 负责将从 JSON 加载的数据结构恢复为 Ruby 对象
  class RvdataRestorer
    # 为特定类定义简化的实例化器
    # 这些类要么需要参数初始化，要么结构固定，可以通过构造函数直接创建
    REDUCED_CLASS_INSTANTIATORS = {
      # 事件和命令类，需要参数初始化
      "RPG::Event" => ->(data, restorer) { RPG::Event.new(data["@x"], data["@y"]) },
      "RPG::EventCommand" => ->(data, restorer) { RPG::EventCommand.new(data["@code"], data["@indent"], restorer.restore_value(data["@parameters"])) },
      "RPG::MoveCommand" => ->(data, restorer) { RPG::MoveCommand.new(data["@code"], restorer.restore_value(data["@parameters"])) },
      # Map 需要宽高初始化
      "RPG::Map" => ->(data, restorer) { RPG::Map.new(data["@width"], data["@height"]) },
      # 基本结构体，可以通过参数创建
      "Color" => ->(data, restorer) { Color.new([data["@red"], data["@green"], data["@blue"], data["@alpha"]]) },
      "Tone" => ->(data, restorer) { Tone.new([data["@red"], data["@green"], data["@blue"], data["@gray"]]) },
      "Rect" => ->(data, restorer) { Rect.new(data["@x"], data["@y"], data["@width"], data["@height"]) },
      # Table 的特殊处理，从 JSON 重构回构造函数所需的扁平数组
      "Table" => ->(data, restorer) do
        dimensions = data["@num_of_dimensions"].to_i
        xsize = data["@xsize"].to_i
        ysize = data["@ysize"].to_i
        zsize = data["@zsize"].to_i
        elements_data = restorer.restore_value(data["@elements"]) || []
        # 将可能嵌套的 JSON 数组展平
        flat_elements = elements_data.flatten.map(&:to_i)
        num_elements = data["@num_of_elements"].to_i
        num_elements = 0 if num_elements < 0 # 确保不为负
        # 调整元素数量以匹配 num_elements
        if flat_elements.size < num_elements
          flat_elements.fill(0, flat_elements.size, num_elements - flat_elements.size)
        elsif flat_elements.size > num_elements
          flat_elements = flat_elements.slice(0, num_elements)
        end
        # 构造 Table.new 所需的参数数组
        packed_data = [dimensions, xsize, ysize, zsize, num_elements] + flat_elements
        Table.new(packed_data)
      end,
      # RGSS3 特有的 Feature/Effect/Damage 类，需要参数初始化 (如果类已定义)
      "RPG::BaseItem::Feature" => ->(data, restorer) { defined?(RPG::BaseItem::Feature) ? RPG::BaseItem::Feature.new(data["@code"], data["@data_id"], data["@value"]) : nil },
      "RPG::UsableItem::Effect" => ->(data, restorer) { defined?(RPG::UsableItem::Effect) ? RPG::UsableItem::Effect.new(data["@code"], data["@data_id"], data["@value1"], data["@value2"]) : nil },
      "RPG::UsableItem::Damage" => ->(data, restorer) { defined?(RPG::UsableItem::Damage) ? RPG::UsableItem::Damage.new : nil },
    # 注意: 如果目标 RGSS 版本没有这些类，将返回 nil
    }.freeze

    # 初始化恢复器
    # @param rgss_version [String] 目标 RGSS 版本 ("RGSS1", "RGSS2", "RGSS3")
    def initialize(rgss_version)
      @rgss_version = rgss_version
      # 对象缓存，用于处理循环引用
      @object_cache = {}
      Logging::Log.debug "RvdataRestorer 初始化完成，目标版本: #{@rgss_version}" if Logging::Log.debug?
    end

    # 执行恢复过程
    # @param data [Object] 从 JSON 加载的数据结构
    # @return [Object] 恢复后的 Ruby 对象
    def restore(data)
      Logging::Log.debug "开始对象恢复..." if Logging::Log.debug?
      @object_cache.clear # 清空上次恢复的缓存

      # 特殊处理 MapInfos: 键需要从字符串转回整数
      if data.is_a?(Hash) && data.key?("__rvdata2json_source_file__") && File.basename(data["__rvdata2json_source_file__"], ".json") == "MapInfos"
        Logging::Log.debug "恢复 MapInfos (特殊处理来源文件键)..." if Logging::Log.debug?
        actual_data = data.reject { |k, _| k == "__rvdata2json_source_file__" }
        restored_map_infos = {}
        actual_data.each do |key, value_data|
          restored_map_infos[key.to_i] = restore_value(value_data) # 递归恢复值
        end
        return restored_map_infos
      else
        # 其他数据，直接调用递归恢复
        return restore_value(data)
      end
    end

    # 递归恢复值的核心方法
    def restore_value(value)
      case value
      when Array
        restore_array(value) # 恢复数组
      when Hash
        oid = value.object_id # 使用内存中的 Hash 对象 ID 作为缓存键
        # 检查缓存，处理循环引用
        return @object_cache[oid] if @object_cache.key?(oid)
        # 恢复 Hash 或其实例对象
        restored = restore_hash(value)
        # 如果恢复结果是一个新对象 (非 Hash)，将其存入缓存
        # 使用恢复后的对象 ID 和原始 Hash ID 作为键，确保能正确找到
        if restored && !restored.is_a?(Hash) && restored.respond_to?(:object_id)
          @object_cache[restored.object_id] = restored
          @object_cache[oid] = restored
        end
        restored
      else
        value # 基本类型直接返回
      end
    end

    # 恢复数组，递归恢复其元素
    def restore_array(array)
      array.map { |item| restore_value(item) }
    end

    # 恢复哈希
    # 如果包含 "json_class" 键，则恢复为实例对象
    # 否则，递归恢复其值
    def restore_hash(hash)
      hash.key?("json_class") ? restore_instance(hash) : hash.transform_values { |v| restore_value(v) }
    end

    # 恢复实例对象
    def restore_instance(data)
      class_name = data["json_class"]
      # 特殊处理 Symbol (虽然 Oj 兼容模式下不应出现)
      return data["s"].to_sym if class_name == "Symbol" && data.key?("s")

      cache_key = data.object_id # 使用原始 Hash ID 作为缓存查找键
      return @object_cache[cache_key] if @object_cache.key?(cache_key)

      # 查找对应的 Ruby 类
      klass = find_class(class_name)
      unless klass
        Logging::Log.error "恢复期间找不到类 '#{class_name}'。请检查 RGSS 定义是否正确加载。"
        return nil # 无法恢复
      end
      # Logging::Log.debug "恢复实例: #{class_name}" if Logging::Log.debug? # 日志过于频繁

      # 实例化对象
      obj = instantiate_object(klass, data)
      unless obj
        Logging::Log.warn "无法实例化类 '#{class_name}' 的对象。跳过属性填充。"
        @object_cache[cache_key] = nil # 缓存 nil 表示实例化失败
        return nil
      end

      # 存入缓存 (使用对象 ID 和原始 Hash ID)
      @object_cache[obj.object_id] = obj
      @object_cache[cache_key] = obj

      # 填充实例变量
      populate_attributes(obj, data)
      obj
    end

    # 根据类名字符串查找 Ruby 类常量
    def find_class(class_name)
      begin
        Object.const_get(class_name)
      rescue NameError
        return nil # 类未定义
      end
    end

    # 实例化对象
    # 优先使用简化的实例化器，否则调用默认构造函数
    def instantiate_object(klass, data)
      if REDUCED_CLASS_INSTANTIATORS.key?(klass.name)
        # 使用注册的特殊实例化器
        begin
          instance = REDUCED_CLASS_INSTANTIATORS[klass.name].call(data, self)
          # 特殊处理: RGSS3 特有类在非 RGSS3 环境下实例化可能返回 nil，这是正常的
          is_rgss3_feature_like = defined?(RPG::BaseItem::Feature) && [RPG::BaseItem::Feature, RPG::UsableItem::Effect, RPG::UsableItem::Damage].include?(klass)
          if instance.nil? && is_rgss3_feature_like
            Logging::Log.debug "特殊实例化器为 #{klass.name} 返回 nil (非 RGSS3 环境下预期行为)。" if Logging::Log.debug?
            return nil
          end
          # 检查 Table 实例化是否失败
          if klass == Table && instance.nil?
            Logging::Log.error "Table 实例化失败，数据: #{data.inspect[0..200]}..."
            return nil
          end
          return instance
        rescue NameError => e
          # 捕获在实例化器中可能发生的 NameError (例如 RGSS3 类不存在)
          if e.message.match(/uninitialized constant RPG::(BaseItem::Feature|UsableItem::Effect|UsableItem::Damage)/)
            Logging::Log.debug "无法实例化 #{klass.name} (可能是 RGSS 版本不匹配)。" if Logging::Log.debug?
            return nil
          else
            # 其他 NameError
            Logging::Log.error "实例化特殊类 '#{klass.name}' (注册表) 时发生 NameError: #{e.message}\n数据: #{data.inspect[0..200]}..."
            raise # 重新抛出未预料的 NameError
          end
        rescue => e
          # 捕获实例化器中的其他错误
          Logging::Log.error "实例化特殊类 '#{klass.name}' (注册表) 时出错: #{e.message}\n数据: #{data.inspect[0..200]}...\n原始调用栈:\n#{e.backtrace.first(5).join("\n")}"
          return nil
        end
      else
        # 使用通用实例化 (调用 Class.new)
        generic_instantiate(klass, data)
      end
    end

    # 通用对象实例化 (调用 Class.new)
    def generic_instantiate(klass, data)
      begin
        klass.new
      rescue ArgumentError => e
        # 处理需要参数的构造函数错误
        known_param_classes = ["RPG::Event", "RPG::Map"] # 已知需要参数但可能未在注册表中的类
        if known_param_classes.include?(klass.name)
          Logging::Log.error "类 #{klass.name} 需要初始化参数，但未在 REDUCED_CLASS_INSTANTIATORS 中配置。请检查注册表或类的 initialize 方法。"
        else
          Logging::Log.error "实例化通用类 #{klass.name} 时发生 ArgumentError: #{e.message}。是否需要参数？"
        end
        return nil
      rescue => e
        # 捕获其他实例化错误
        Logging::Log.error "实例化通用类 #{klass.name} 时发生未知错误: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        return nil
      end
    end

    # 填充对象的实例变量
    def populate_attributes(obj, data)
      return unless obj # 如果对象实例化失败则跳过

      data.each do |key, value|
        # 跳过内部使用的键和非实例变量键
        next if key == "json_class" || key == "__rvdata2json_source_file__" || key.start_with?("@_")
        next unless key.start_with?("@")

        ivar_symbol = key.to_sym
        # 跳过 Table 的 @elements，它在实例化时已处理
        next if obj.is_a?(Table) && ivar_symbol == :@elements

        # 检查对象是否有此实例变量或对应的 setter 方法
        has_ivar = obj.instance_variable_defined?(ivar_symbol)
        setter_method_name = ivar_symbol.to_s[1..-1] + "="
        setter_method = setter_method_name.to_sym
        has_setter = obj.respond_to?(setter_method)

        # 如果既没有实例变量也没有 setter，则跳过
        next unless has_ivar || has_setter

        begin
          # 递归恢复属性值
          restored_value = restore_value(value)

          # 处理恢复值为 nil 的情况 (特别是对于可选的 RGSS3 类)
          if restored_value.nil? && value.is_a?(Hash) && value.key?("json_class")
            is_expected_nil = case value["json_class"]
              # 这些类在 RGSS1/2 中不存在，恢复为 nil 是正常的
              when "RPG::BaseItem::Feature", "RPG::UsableItem::Effect", "RPG::UsableItem::Damage", "RPG::Tileset"
                @rgss_version == "RGSS1" || @rgss_version == "RGSS2"
                # Area 在 RGSS1/3 中不存在
              when "RPG::Area"
                @rgss_version == "RGSS1" || @rgss_version == "RGSS3"
              else
                false
              end
            # 如果是预期中的 nil，则跳过设置
            if is_expected_nil
              Logging::Log.debug "(恢复) 跳过为预期可选类 #{value["json_class"]} 设置 nil 值 (对象: #{obj.class}, 属性: #{ivar_symbol})" if Logging::Log.debug?
              next
            end
          end

          # 特殊处理 Map 的 @events (键需要是整数)
          if ivar_symbol == :@events && obj.is_a?(RPG::Map) && restored_value.is_a?(Hash)
            restored_hash = {}
            restored_value.each { |k, v| restored_hash[k.to_i] = v }
            # 优先使用 setter，否则直接设置实例变量
            has_setter ? obj.send(setter_method, restored_hash) : obj.instance_variable_set(ivar_symbol, restored_hash)
            # 优先使用 setter 方法赋值
          elsif has_setter
            obj.send(setter_method, restored_value)
            # 否则直接设置实例变量 (如果存在)
          elsif has_ivar
            obj.instance_variable_set(ivar_symbol, restored_value)
          end
        rescue StandardError => e
          # 记录设置属性时发生的错误
          Logging::Log.warn "(恢复) 为对象 #{obj.class} 设置属性 #{ivar_symbol} 时出错: #{e.class}: #{e.message}。值: #{value.inspect[0..100]}... 跳过此属性。"
        end
      end
    end
  end # class RvdataRestorer

  # --- 脚本处理 模块 ---
  # 负责解包和打包 Scripts.rvdata 文件
  module Scripts
    METADATA_FILENAME = "Scripts_info.json".freeze # 存储脚本元数据的文件名
    SCRIPTS_SUBDIR = "Scripts".freeze              # 存放解包后脚本的子目录名
    ASSUMED_NAME_ENCODING = "UTF-8".freeze         # 假定原始脚本名称的编码

    # 解包 Scripts.rvdata
    # @param scripts_array [Array] 从 Scripts.rvdata 加载的数组
    # @param json_output_base_dir [String] JSON 输出的基础目录
    # @raise [ArgumentError] 如果输入数据不是数组
    def self.unpack(scripts_array, json_output_base_dir)
      # 验证输入类型
      unless scripts_array.is_a?(Array)
        err_msg = "无效的脚本数据: 顶层对象不是数组。"
        Logging::Log.error err_msg
        raise ArgumentError, err_msg
      end

      # 确定脚本输出目录
      scripts_output_dir = File.join(json_output_base_dir, SCRIPTS_SUBDIR)
      Logging::Log.info "确保脚本输出目录存在: #{scripts_output_dir}"
      FileUtils.mkdir_p(scripts_output_dir)

      metadata = [] # 存储脚本元数据
      # 遍历脚本数组
      scripts_array.each_with_index do |script_entry, index|
        # 验证脚本条目格式 [id, name, compressed_code]
        unless script_entry.is_a?(Array) && script_entry.length >= 3
          Logging::Log.warn "跳过索引 #{index} 处无效的脚本条目 (非数组或长度不足): #{script_entry.inspect[0..100]}..."
          next
        end

        id, name_bytes, compressed_code = script_entry[0], script_entry[1], script_entry[2]

        # 验证 ID 类型
        unless id.is_a?(Integer) || (id.respond_to?(:to_i))
          Logging::Log.warn "跳过索引 #{index} 处无效的脚本条目 (ID 非整数): ID=#{id.inspect}"
          next
        end
        id = id.to_i # 转换为整数

        # 验证名称类型
        unless name_bytes.is_a?(String)
          Logging::Log.warn "跳过索引 #{index} 处无效的脚本条目 (名称非字符串): Name=#{name_bytes.inspect}"
          next
        end

        # --- 处理脚本名称编码 (用于 JSON 元数据) ---
        name_processed_for_json = "[转换错误]"
        begin
          # 强制编码为假定编码，然后转换为 UTF-8，替换无效字符
          name_processed_for_json = name_bytes.dup.force_encoding(ASSUMED_NAME_ENCODING).encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
          # 处理替换后变为空字符串的情况
          if name_processed_for_json.empty? && !name_bytes.empty?
            name_processed_for_json = "[替换后为空]"
          end
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError => e
          # 记录编码转换错误
          Logging::Log.warn "无法将脚本名称字节处理为 #{ASSUMED_NAME_ENCODING} (ID: #{id}, Index: #{index})。存储占位符。错误: #{e.message}"
          name_processed_for_json = "[编码错误: #{e.message}]"
        rescue => e
          # 记录其他处理错误
          Logging::Log.warn "处理脚本名称时出错 (ID: #{id}, Index: #{index})。存储占位符。错误: #{e.class} - #{e.message}"
          name_processed_for_json = "[处理错误: #{e.message}]"
        end
        # --- 编码处理结束 ---

        # --- 解压缩脚本代码 ---
        script_code = ""
        begin
          # 处理空或无效的压缩代码
          if compressed_code.nil? || !compressed_code.is_a?(String) || compressed_code.empty?
            Logging::Log.debug "脚本代码为空或类型无效 (Index #{index}, ID #{id})" if Logging::Log.debug?
            # 如果类型不正确，发出警告
            if compressed_code && !compressed_code.is_a?(String)
              Logging::Log.warn "脚本代码类型不正确 (Index #{index}, ID #{id}, Type #{compressed_code.class})。将写入空文件。"
            end
          else
            # 解压缩
            script_code = Zlib::Inflate.inflate(compressed_code)
          end
        rescue Zlib::Error => e
          # 记录解压缩错误
          Logging::Log.warn "解压缩脚本代码失败 (Index #{index}, ID #{id}, Name '#{name_processed_for_json}'): #{e.class}: #{e.message}。将写入空文件。"
          script_code = ""
        rescue TypeError => e
          # 记录非字符串错误
          Logging::Log.warn "脚本代码不是有效的压缩字符串 (Index #{index}, ID #{id}, Name '#{name_processed_for_json}'): #{e.class}: #{e.message}。将写入空文件。"
          script_code = ""
        end
        # --- 解压缩结束 ---

        # 生成脚本文件名 (按索引顺序)
        script_filename = format("%03d.rb", index)
        script_filepath = File.join(scripts_output_dir, script_filename)

        # 写入脚本文件
        begin
          File.binwrite(script_filepath, script_code) # 使用二进制写入以保留原始换行符等
          Logging::Log.info "  解包脚本: #{script_filename} (ID: #{id}, Name: '#{name_processed_for_json}')"
        rescue => e
          # 记录文件写入错误
          Logging::Log.error "写入脚本文件 '#{script_filepath}' 失败: #{e.message}"
        end

        # 添加元数据
        metadata << { id: id, name: name_processed_for_json, index: index }
      end # scripts_array.each end

      # --- 写入元数据文件 ---
      metadata_filepath = File.join(scripts_output_dir, METADATA_FILENAME)
      begin
        # 将元数据数组转换为格式化的 JSON 字符串
        json_string = Oj.dump(metadata, mode: :compat, indent: 2)
        # 以 UTF-8 编码写入元数据文件
        File.write(metadata_filepath, json_string, encoding: "UTF-8")
        Logging::Log.info "  写入脚本元数据: #{METADATA_FILENAME}"
      rescue => e
        # 记录元数据写入错误
        Logging::Log.error "写入脚本元数据文件 '#{metadata_filepath}' 失败: #{e.message}"
      end
      # --- 元数据写入结束 ---
    end # def unpack end

    # 打包脚本文件为 Scripts.rvdata
    # @param scripts_input_dir [String] 包含脚本文件和元数据文件的目录
    # @return [Array] 用于 Marshal.dump 的脚本数组
    # @raise [IOError] 如果元数据文件未找到
    # @raise [TypeError] 如果元数据文件内容不是数组
    # @raise [RuntimeError] 如果发生 JSON 解析或其他加载错误
    def self.pack(scripts_input_dir)
      metadata_filepath = File.join(scripts_input_dir, METADATA_FILENAME)
      # 检查元数据文件是否存在
      unless File.exist?(metadata_filepath)
        err_msg = "脚本元数据文件未找到: #{metadata_filepath}"
        Logging::Log.error err_msg
        raise IOError, err_msg
      end

      Logging::Log.info "加载脚本元数据: #{metadata_filepath}"
      metadata = nil
      begin
        # 加载并解析元数据 JSON 文件
        json_string = File.read(metadata_filepath, encoding: "UTF-8")
        metadata = Oj.load(json_string, mode: :compat, symbol_keys: false)
      rescue Oj::ParseError => e
        # 处理 JSON 解析错误
        err_msg = "解析脚本元数据 JSON 文件 '#{metadata_filepath}' 失败: #{e.message}"
        Logging::Log.error err_msg
        raise "元数据 JSON 解析错误。详情请查看日志。"
      rescue => e
        # 处理其他加载错误
        err_msg = "加载脚本元数据文件 '#{metadata_filepath}' 失败: #{e.message}"
        Logging::Log.error err_msg
        raise "加载元数据时出错。详情请查看日志。"
      end

      # 验证元数据格式
      unless metadata.is_a?(Array)
        err_msg = "脚本元数据文件 '#{metadata_filepath}' 的内容不是有效的 JSON 数组。"
        Logging::Log.error err_msg
        raise TypeError, err_msg
      end

      # 确定最终数组大小 (基于最大索引)
      max_index = metadata.map { |info| info["index"] }.compact.max || -1
      scripts_array = Array.new(max_index + 1) # 用 nil 填充

      Logging::Log.info "开始脚本打包过程..."
      # 遍历元数据，读取、压缩并填充脚本数组
      metadata.each do |script_info|
        index = script_info["index"]
        id = script_info["id"]
        name = script_info["name"]

        # 验证元数据条目
        unless index.is_a?(Integer) && index >= 0 && id.is_a?(Integer) && name.is_a?(String)
          Logging::Log.warn "跳过无效的元数据条目: #{script_info.inspect}"
          next
        end

        # 构造脚本文件路径
        script_filename = format("%03d.rb", index)
        script_filepath = File.join(scripts_input_dir, script_filename)
        script_code = ""

        # 读取脚本文件内容
        if File.exist?(script_filepath)
          begin
            # 使用二进制读取
            script_code = File.binread(script_filepath)
            Logging::Log.info "  打包脚本: #{script_filename} (ID: #{id}, Name: '#{name}')"
          rescue => e
            # 记录读取错误
            Logging::Log.warn "读取脚本文件 '#{script_filepath}' 失败: #{e.message}。将使用空代码。"
            script_code = ""
          end
        else
          # 记录文件未找到错误
          Logging::Log.warn "脚本文件未找到: '#{script_filepath}' (基于元数据)。将使用空代码。"
          script_code = ""
        end

        # 压缩脚本代码
        compressed_code = Zlib::Deflate.deflate("") # 默认压缩空字符串
        begin
          compressed_code = Zlib::Deflate.deflate(script_code)
        rescue => e
          # 记录压缩错误
          Logging::Log.error "压缩脚本代码失败 (Index #{index}, ID #{id}, Name '#{name}'): #{e.message}。将使用压缩后的空字符串。"
        end

        # 填充脚本数组 [id, name, compressed_code]
        # 注意: 这里的 name 直接使用从 JSON 中读取的 UTF-8 字符串
        #       Marshal.dump 会处理其内部编码
        scripts_array[index] = [id, name, compressed_code]
      end # metadata.each end

      Logging::Log.info "脚本打包完成，准备进行 Marshal 转储。"
      return scripts_array
    end # def pack end
  end # module Scripts
end # module Converter
