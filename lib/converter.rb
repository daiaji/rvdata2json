# lib/converter.rb
# 包含核心的 RVData <-> JSON 转换逻辑
# 修正: 根据 Frame.@cell_data 始终为 Table 的理解，
#       移除 RvdataRestorer 中针对性的警告和 Array 转换逻辑。

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
        # 增强对 NameError (未定义常量) 的捕获和提示
        if e.message.include?("undefined class/module") || e.message.include?("allocator is not defined")
          raise NameError, "加载 Marshal 数据 '#{input_file}' 时出错: #{e.message}. 请确保已加载正确的 RGSS 定义 (rgss2.rb 或 rgss3.rb)。", caller
        else
          raise ArgumentError, "加载 Marshal 数据 '#{input_file}' 时参数错误 (可能是版本不匹配或文件损坏): #{e.message}"
        end
      rescue TypeError => e
        raise TypeError, "加载 Marshal 数据 '#{input_file}' 时类型错误 (确保加载了正确的 RGSS 定义): #{e.message}"
      rescue => e
        raise "读取或解析 Marshal 文件 '#{input_file}' 时出错: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    def self.load_json_data(input_file)
      begin
        json_string = File.read(input_file, encoding: "UTF-8")
        # 使用 Oj 进行解析
        data = Oj.load(json_string, mode: :compat, symbol_keys: false)
        # 特殊处理 MapInfos，添加来源文件信息用于恢复键类型
        if data.is_a?(Hash) && File.basename(input_file, ".json") == "MapInfos"
          # 使用一个不太可能冲突的键名
          data["__rvdata2json_source_file__"] = input_file
        end
        data
      rescue Oj::ParseError => e
        raise "JSON 解析错误 (Oj)，文件 '#{input_file}': #{e.message}"
      rescue => e
        raise "读取或解析 JSON 文件 '#{input_file}' 时出错: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    def self.write_json_data(output_file, data)
      FileUtils.mkdir_p(File.dirname(output_file))
      begin
        # 使用 Oj 进行序列化，保持兼容模式和缩进
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
        # 改进 TypeError 调试信息
        problem_info = find_problematic_path(restored_object) do |obj|
          # 检查 Tone/Color 是否有 nil 属性
          (obj.is_a?(Tone) || obj.is_a?(Color)) && obj.instance_variables.any? { |ivar| obj.instance_variable_get(ivar).nil? } ||
            # 检查 Table 是否完整
          (obj.is_a?(Table) && (obj.instance_variable_get(:@elements).nil? || !obj.instance_variable_get(:@elements).is_a?(Array) || obj.instance_variable_get(:@elements).any? { |el| !el.is_a?(Integer) } || obj.instance_variable_get(:@xsize).nil? || obj.instance_variable_get(:@ysize).nil? || obj.instance_variable_get(:@zsize).nil?)) ||
            # 检查 Frame 的 cell_data 是否为 nil
          (defined?(RPG::Animation::Frame) && obj.is_a?(RPG::Animation::Frame) && obj.instance_variable_get(:@cell_data).nil?) ||
            # 检查 Area 的 rect 是否为 nil (RGSS2 only)
          (defined?(RPG::Area) && obj.is_a?(RPG::Area) && obj.instance_variable_get(:@rect).nil?)
        end
        context = problem_info ? " 问题可能在路径 #{problem_info[:path]} 的对象: #{problem_info[:object].class} #{problem_info[:object].inspect[0..200]}..." : ""
        raise TypeError, "写入 Marshal 文件 '#{output_file}' 时 TypeError: #{e.message}.#{context} 检查对象初始化和恢复逻辑是否完整。"
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
          # 跳过我们自己添加的元数据键
          object.reject { |k, _| k == "__rvdata2json_source_file__" }.each do |key, value|
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
              rescue StandardError
                # Ignore errors getting instance variable value during debug search
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
    # 定义在导出特定版本 JSON 时应被过滤掉的属性 (保持不变)
    ATTRIBUTES_REMOVED = {
      "RGSS3" => { # 导出为 RGSS3 JSON 时，过滤掉这些 RGSS2 兼容属性 或 非标准属性
        "RPG::Actor" => Set.new([:@exp_basis, :@exp_inflation, :@parameters, :@weapon_id, :@armor1_id, :@armor2_id, :@armor3_id, :@armor4_id, :@two_swords_style, :@fix_equipment, :@auto_battle, :@super_guard, :@pharmacology, :@critical_bonus]),
        "RPG::Armor" => Set.new([:@kind, :@eva, :@atk, :@spi, :@agi, :@prevent_critical, :@half_mp_cost, :@double_exp_gain, :@auto_hp_recover, :@element_set, :@state_set]),
        "RPG::Weapon" => Set.new([:@hit, :@atk, :@def, :@spi, :@agi, :@two_handed, :@fast_attack, :@dual_attack, :@critical_bonus, :@element_set, :@state_set]),
        "RPG::Item" => Set.new([:@hp_recovery_rate, :@hp_recovery, :@mp_recovery_rate, :@mp_recovery, :@parameter_type, :@parameter_points]),
        "RPG::Skill" => Set.new([:@hit]),
        "RPG::Enemy" => Set.new([:@maxhp, :@maxmp, :@atk, :@def, :@spi, :@agi, :@hit, :@eva, :@drop_item1, :@drop_item2, :@levitate, :@has_critical, :@element_ranks, :@state_ranks]),
        "RPG::State" => Set.new([:@atk_rate, :@def_rate, :@spi_rate, :@agi_rate, :@nonresistance, :@offset_by_opposite, :@slip_damage, :@reduce_hit_ratio, :@battle_only, :@release_by_damage, :@hold_turn, :@auto_release_prob, :@element_set, :@state_set]),
        "RPG::System" => Set.new([:@passages]), # RGSS2 Table
        "RPG::System::TestBattler" => Set.new([:@weapon_id, :@armor1_id, :@armor2_id, :@armor3_id, :@armor4_id]),
        "RPG::Troop::Member" => Set.new([:@immortal]),
      # Keep RGSS2 classes if they exist (they won't be loaded in RGSS3 mode anyway)
      },
      "RGSS2" => { # 导出为 RGSS2 JSON 时，过滤掉这些 RGSS3 特有属性 或 非标准属性
        "RPG::Animation::Timing" => Set.new([:@condition]), # Assuming condition is non-standard if it appears
        # Filter features from all BaseItem subclasses
        "RPG::BaseItem" => Set.new([:@features]), # Applied dynamically below
        "RPG::Actor" => Set.new([:@nickname, :@max_level, :@equips]),
        "RPG::Class" => Set.new([:@exp_params, :@params, :@features]), # RGSS3 Class attributes
        "RPG::UsableItem" => Set.new([:@success_rate, :@repeats, :@tp_gain, :@hit_type, :@damage, :@effects]),
        "RPG::Skill" => Set.new([:@stype_id, :@tp_cost, :@required_wtype_id1, :@required_wtype_id2]),
        "RPG::Item" => Set.new([:@itype_id]),
        "RPG::EquipItem" => Set.new([:@price, :@etype_id, :@params, :@features]), # EquipItem is RGSS3 base class
        "RPG::Weapon" => Set.new([:@wtype_id, :@etype_id, :@params, :@features]), # RGSS3 Weapon attributes (on top of EquipItem)
        "RPG::Armor" => Set.new([:@atype_id, :@etype_id, :@params, :@features]), # RGSS3 Armor attributes (on top of EquipItem)
        "RPG::Enemy" => Set.new([:@params, :@drop_items]), # RGSS3 Enemy attributes
        "RPG::State" => Set.new([:@remove_at_battle_end, :@remove_by_restriction, :@auto_removal_timing, :@min_turns, :@max_turns, :@remove_by_damage, :@chance_by_damage, :@remove_by_walking, :@steps_to_remove]), # RGSS3 State attributes
        "RPG::System" => Set.new([:@japanese, :@currency_unit, :@skill_types, :@weapon_types, :@armor_types, :@title1_name, :@title2_name, :@opt_draw_title, :@opt_use_midi, :@opt_transparent, :@opt_followers, :@opt_slip_death, :@opt_floor_death, :@opt_display_tp, :@opt_extra_exp, :@window_tone, :@battleback1_name, :@battleback2_name]), # RGSS3 System attributes
        "RPG::System::Terms" => Set.new([:@basic, :@params, :@etypes, :@commands]), # RGSS3 Terms attributes
        "RPG::System::TestBattler" => Set.new([:@equips]), # RGSS3 TestBattler attributes
        "RPG::Map" => Set.new([:@display_name, :@tileset_id, :@specify_battleback, :@battleback1_name, :@battleback2_name, :@note]), # RGSS3 Map attributes
        "RPG::Map::Encounter" => Set.new([:@region_set]), # RGSS3 Encounter attributes
      # RGSS3 only classes: Tileset, EquipItem, Feature, Effect, Damage, Map::Encounter
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
      # 基本类型和已访问对象直接返回
      return if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)
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
            rescue StandardError
              # 忽略读取实例变量时可能发生的错误
            end
          end
        elsif object.is_a?(Array)
          object.each { |item| unpack_recursively(item) }
        elsif object.is_a?(Hash)
          # 跳过我们自己添加的元数据键
          object.reject { |k, _| k == "__rvdata2json_source_file__" }.each do |key, value|
            unpack_recursively(key) # Key 也可能是需要解包的对象（虽然不太常见）
            unpack_recursively(value)
          end
        end
      ensure
        # 在单次 export 过程中保持 visited 状态，不需要 remove
      end
    end

    # 安全地调用对象的 unpack_names 方法
    def call_unpack_names(object)
      # 简化：直接尝试调用，不再检查参数
      begin
        object.unpack_names
      rescue ArgumentError => e
        # 忽略参数数量错误，因为不同类的 unpack_names 签名不同
        unless e.message.include?("wrong number of arguments")
          puts "[警告] 调用 #{object.class}#unpack_names 时参数错误: #{e.message}"
        end
      rescue NoMethodError => e
        # 忽略 superclass method missing 错误，常见于继承链末端
        unless e.message.include?("super: no superclass method")
          puts "[警告] 在 #{object.class} 上执行 unpack_names 时方法未找到: #{e.class}: #{e.message}"
        end
      rescue => e
        puts "[警告] 在 #{object.class} 上执行 unpack_names 时出错: #{e.class}: #{e.message}"
      end
    end

    # 将解包后的对象转换为纯 Ruby 结构（Hash/Array），并过滤不必要的属性
    def clean_for_export(object)
      # 处理基本类型和 nil
      return object if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)

      # 确保是对象
      unless object.respond_to?(:object_id)
        # 如果不是对象但可迭代，尝试递归处理
        if object.is_a?(Array)
          return object.map { |item| clean_for_export(item) }
        elsif object.is_a?(Hash)
          result = {}
          # 跳过元数据键
          object.reject { |k, _| k == "__rvdata2json_source_file__" }.each do |key, value|
            cleaned_key = clean_for_export(key)
            cleaned_value = clean_for_export(value)
            result[cleaned_key] = cleaned_value
          end
          return result
        else
          # 无法处理其他非对象类型
          puts "[错误] 无法处理类型为 #{object.class} 的无 object_id 对象。"
          return nil
        end
      end

      oid = object.object_id
      # 如果已处理过此对象（循环引用），直接返回缓存的结果
      return @visited_clean[oid] if @visited_clean.key?(oid)

      # 获取类名
      class_name_str = object.class.name
      unless class_name_str && !class_name_str.empty?
        puts "[警告] 遇到匿名或未命名类实例，无法精确导出类型: #{object.inspect[0..100]}..."
        # 尝试作为 Array 或 Hash 处理匿名类
        if object.is_a?(Array)
          result = []
          @visited_clean[oid] = result # 先存入引用，防止子元素递归回来
          object.each { |item| result << clean_for_export(item) }
          return result
        elsif object.is_a?(Hash)
          result = {}
          @visited_clean[oid] = result # 先存入引用
          object.reject { |k, _| k == "__rvdata2json_source_file__" }.each do |key, value|
            cleaned_key = clean_for_export(key)
            cleaned_value = clean_for_export(value)
            result[cleaned_key] = cleaned_value
          end
          return result
        else
          puts "[错误] 无法处理匿名或未命名类的实例 (非 Array/Hash)。"
          return nil
        end
      end

      # 根据对象类型进行清理
      cleaned_object = case object
        when Array
          result = []
          @visited_clean[oid] = result # 先存入引用，防止子元素递归回来
          object.each { |item| result << clean_for_export(item) }
          result
        when Hash
          # 特殊处理 MapInfos 的 Hash (键是整数)
          is_map_infos = class_name_str == "Hash" && object.keys.all? { |k| k.is_a?(Integer) }
          result = {}
          @visited_clean[oid] = result # 先存入引用
          # 跳过元数据键
          object.reject { |k, _| k == "__rvdata2json_source_file__" }.each do |key, value|
            cleaned_key = clean_for_export(key)
            cleaned_value = clean_for_export(value)
            result[cleaned_key] = cleaned_value
          end
          result
          # 特殊处理需要保留类信息的基础数据结构
        when Table
          result = { "json_class" => class_name_str }
          @visited_clean[oid] = result # 先存入引用
          # 获取 Table 的维度和大小
          result["@num_of_dimensions"] = dim = object.num_of_dimensions
          result["@xsize"] = xsize = object.xsize
          result["@ysize"] = ysize = object.ysize
          result["@zsize"] = zsize = object.zsize
          result["@num_of_elements"] = num_elements = object.num_of_elements

          # 获取并调整元素数组
          elements = object.instance_variable_get(:@elements) || []
          # 确保元素数量不超过声明的数量
          elements = elements[0...num_elements] if elements.size > num_elements && num_elements >= 0

          # 根据维度导出元素 (创建嵌套数组)
          exported_elements = []
          begin
            if num_elements <= 0 || dim <= 0
              exported_elements = []
            elsif dim == 1
              exported_elements = elements
            elsif dim == 2
              # Handle potential zero xsize
              if xsize > 0
                exported_elements = elements.each_slice(xsize).to_a
              else
                # If xsize is 0, create an array of empty arrays for ysize
                exported_elements = Array.new([ysize, 0].max) { [] }
              end
            elsif dim == 3
              z_slice_size = xsize * ysize
              if z_slice_size > 0
                exported_elements = elements.each_slice(z_slice_size).map do |z_slice|
                  # Handle potential zero xsize within each z-slice
                  if xsize > 0
                    z_slice.each_slice(xsize).to_a
                  else
                    Array.new([ysize, 0].max) { [] }
                  end
                end
              else
                # If xsize or ysize is 0, create nested empty arrays
                exported_elements = Array.new([zsize, 0].max) { Array.new([ysize, 0].max) { [] } }
              end
            else
              # 不支持的维度，导出为扁平数组并警告
              exported_elements = elements
              puts "[警告] Table 维度 (#{dim}) 无效或不支持，导出为扁平数组。" if dim > 3
            end
          rescue ArgumentError => e
            # 处理 each_slice 等可能出现的错误
            puts "[警告] 处理 Table (dim=#{dim}, size=#{xsize}x#{ysize}x#{zsize}, elements=#{num_elements}) 时出错: #{e.message}. 返回扁平数组。"
            exported_elements = elements
          end
          result["@elements"] = exported_elements # 赋值，不再递归 clean_for_export
          result
        when Color, Tone, Rect
          result = { "json_class" => class_name_str }
          @visited_clean[oid] = result # 先存入引用
          object.instance_variables.each do |ivar|
            next if ivar.to_s.start_with?("@_") # 跳过内部变量
            key = ivar.to_s # 使用 '@ivar' 作为键
            value = object.instance_variable_get(ivar)
            result[key] = clean_for_export(value) # 递归清理值
          end
          result
        else # 处理其他自定义 RPG 对象
          result = { "json_class" => class_name_str }
          @visited_clean[oid] = result # 先存入引用

          # 获取当前版本需要移除的属性集合
          removed_attrs_for_target = ATTRIBUTES_REMOVED[@rgss_version] || {}

          # 构建最终要过滤的属性集合 (包括父类的过滤规则)
          filter_set = Set.new
          klass = object.class
          while klass != Object && klass != nil && klass.name # 向上遍历继承链
            set_for_class = removed_attrs_for_target[klass.name]
            filter_set.merge(set_for_class) if set_for_class
            # 特殊处理：导出为 RGSS2 时，移除所有 BaseItem 子类的 features
            if @rgss_version == "RGSS2" && klass.ancestors.include?(RPG::BaseItem)
              filter_set.add(:@features) if removed_attrs_for_target["RPG::BaseItem"]&.include?(:@features)
            end
            klass = klass.superclass
          end

          # 遍历实例变量并过滤
          if object.respond_to?(:instance_variables)
            object.instance_variables.sort.each do |ivar|
              ivar_s = ivar.to_s

              next if ivar_s.start_with?("@_") # 跳过内部变量
              next if filter_set.include?(ivar) # 跳过已标记为移除的属性

              key = ivar_s # 使用 '@ivar' 作为键
              value = nil
              begin
                value = object.instance_variable_get(ivar)
              rescue => e
                # Log error if getting ivar fails
                puts "[警告] 获取实例变量 #{ivar_s} on #{object.class} 时出错: #{e.message}"
                next # Skip this ivar
              end
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
    # 预定义的特殊类构造器 (保持不变)
    REDUCED_CLASS_INSTANTIATORS = {
      "RPG::Event" => ->(data, restorer) { RPG::Event.new(data["@x"], data["@y"]) },
      "RPG::EventCommand" => ->(data, restorer) { RPG::EventCommand.new(data["@code"], data["@indent"], restorer.restore_value(data["@parameters"])) },
      "RPG::MoveCommand" => ->(data, restorer) { RPG::MoveCommand.new(data["@code"], restorer.restore_value(data["@parameters"])) },
      "RPG::Map" => ->(data, restorer) { RPG::Map.new(data["@width"], data["@height"]) }, # Map.new no longer needs version
      "Color" => ->(data, restorer) { Color.new([data["@red"], data["@green"], data["@blue"], data["@alpha"]]) },
      "Tone" => ->(data, restorer) { Tone.new([data["@red"], data["@green"], data["@blue"], data["@gray"]]) },
      "Rect" => ->(data, restorer) { Rect.new(data["@x"], data["@y"], data["@width"], data["@height"]) },
      "Table" => ->(data, restorer) do
        # 从 JSON 恢复 Table 对象
        dimensions = data["@num_of_dimensions"].to_i
        xsize = data["@xsize"].to_i
        ysize = data["@ysize"].to_i
        zsize = data["@zsize"].to_i
        # 递归恢复 @elements (它现在应该是嵌套数组或扁平数组)
        elements_data = restorer.restore_value(data["@elements"]) || []
        # 将恢复后的元素展平并转换为整数
        flat_elements = elements_data.flatten.map(&:to_i)

        # 获取 JSON 中声明的元素总数
        num_elements = data["@num_of_elements"].to_i
        num_elements = 0 if num_elements < 0 # 确保非负

        # 调整扁平化后的元素数组大小以匹配声明的数量
        if flat_elements.size < num_elements
          flat_elements.fill(0, flat_elements.size, num_elements - flat_elements.size)
        elsif flat_elements.size > num_elements
          flat_elements = flat_elements.slice(0, num_elements)
        end

        # 使用恢复的维度、大小和调整后的元素数据创建 Table
        # Table.new 期望一个扁平数组包含维度、大小和所有元素
        packed_data = [dimensions, xsize, ysize, zsize, num_elements] + flat_elements
        Table.new(packed_data)
      end,
      # RGSS3 only classes - check definition before creating
      "RPG::BaseItem::Feature" => ->(data, restorer) { defined?(RPG::BaseItem::Feature) ? RPG::BaseItem::Feature.new(data["@code"], data["@data_id"], data["@value"]) : nil },
      "RPG::UsableItem::Effect" => ->(data, restorer) { defined?(RPG::UsableItem::Effect) ? RPG::UsableItem::Effect.new(data["@code"], data["@data_id"], data["@value1"], data["@value2"]) : nil },
      "RPG::UsableItem::Damage" => ->(data, restorer) { defined?(RPG::UsableItem::Damage) ? RPG::UsableItem::Damage.new : nil },
    # 其他需要特殊构造的类可以在这里添加
    }.freeze

    def initialize(rgss_version)
      @rgss_version = rgss_version
      @object_cache = {} # 用于处理循环引用
    end

    # 主恢复方法
    def restore(data)
      @object_cache.clear # 每次调用都清空缓存
      # 特殊处理 MapInfos 文件 (根级别)
      if data.is_a?(Hash) && data.key?("__rvdata2json_source_file__") && File.basename(data["__rvdata2json_source_file__"], ".json") == "MapInfos"
        actual_data = data.reject { |k, _| k == "__rvdata2json_source_file__" }
        restored_map_infos = {}
        actual_data.each do |key, value_data|
          restored_map_infos[key.to_i] = restore_value(value_data) # 恢复值并转换键为整数
        end
        return restored_map_infos
      else
        # 否则，正常恢复数据
        return restore_value(data)
      end
    end

    # 递归恢复值
    def restore_value(value)
      case value
      when Array
        restore_array(value)
      when Hash
        # 检查是否是已缓存的对象（用于循环引用）
        # 使用 input hash object_id 作为简单缓存键
        oid = value.object_id
        return @object_cache[oid] if @object_cache.key?(oid)

        restored = restore_hash(value)
        # 缓存恢复后的对象（如果成功恢复）
        @object_cache[oid] = restored if restored
        restored
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

      # --- 循环引用处理 ---
      # 使用输入数据的 object_id 作为缓存键
      cache_key = data.object_id
      return @object_cache[cache_key] if @object_cache.key?(cache_key)
      # ---

      # 查找类
      klass = find_class(class_name)
      # 如果类未找到 (例如，试图在 RGSS2 模式下恢复 RGSS3 特有类)
      unless klass
        # puts "[调试] 类 '#{class_name}' 未找到，可能由于版本不匹配。返回 nil。"
        return nil
      end

      # 实例化对象
      obj = instantiate_object(klass, data)
      # 如果实例化失败 (例如，调用 new 时出错，或特殊类返回 nil)
      unless obj
        # puts "[调试] 实例化类 '#{class_name}' 失败。返回 nil。"
        return nil
      end

      # --- 缓存对象 ---
      # 使用恢复后对象的 object_id 和原始数据的 object_id 进行缓存
      @object_cache[obj.object_id] = obj # 可能与 cache_key 不同
      @object_cache[cache_key] = obj if cache_key
      # ---

      # 填充属性
      populate_attributes(obj, data)

      obj
    end

    # 根据类名字符串查找类对象
    def find_class(class_name)
      Object.const_get(class_name)
    rescue NameError
      # 如果类找不到，返回 nil 而不是抛出错误
      # 这允许我们在尝试恢复不同版本数据时跳过不存在的类
      return nil
    end

    # 实例化对象（使用预定义构造器或通用构造器）
    def instantiate_object(klass, data)
      # 检查是否在特殊构造器列表中
      if REDUCED_CLASS_INSTANTIATORS.key?(klass.name)
        begin
          # 调用预定义的 lambda 来实例化
          instance = REDUCED_CLASS_INSTANTIATORS[klass.name].call(data, self)
          # 如果 lambda 返回 nil (例如，在 RGSS2 模式下恢复 Feature)，则返回 nil
          return nil if instance.nil? && !klass.name.start_with?("RPG::") # Allow RPG:: classes to potentially return nil? Revisit this.
          return instance
        rescue => e
          # 捕获 NameError (e.g., Feature 在 RGSS2 中未定义) 并返回 nil
          if e.is_a?(NameError) && e.message.match(/uninitialized constant RPG::(BaseItem::Feature|UsableItem::Effect|UsableItem::Damage)/)
            # puts "[调试] 特殊类 '#{klass.name}' 依赖于未定义的类，返回 nil。"
            return nil
          else
            # 其他错误则抛出
            raise "实例化特殊类 '#{klass.name}' (注册表) 时出错: #{e.message}\nData: #{data.inspect[0..200]}...\n原始回溯:\n#{e.backtrace.first(5).join("\n")}"
          end
        end
      else
        # 使用通用实例化逻辑
        generic_instantiate(klass, data)
      end
    end

    # 通用实例化逻辑（现在只尝试无参数 new）
    def generic_instantiate(klass, data)
      begin
        klass.new
      rescue ArgumentError => e
        # 如果 klass.new 仍然需要参数，则抛出错误
        raise ArgumentError, "实例化通用类 #{klass.name} 时参数不匹配: #{e.message}. 此类需要参数但未在注册表中定义，请检查类的 initialize 方法和 JSON 数据。"
      rescue => e
        raise "实例化通用类 #{klass.name} 时发生未知错误: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    # 填充对象属性
    # 移除对 @cell_data 的类型检查和警告
    def populate_attributes(obj, data)
      return unless obj # 如果对象实例化失败，直接返回

      data.each do |key, value|
        # 跳过元数据和内部键
        next if key == "json_class" || key == "__rvdata2json_source_file__"
        next if key.start_with?("@_") # 跳过可能的内部变量

        # 确保 key 是实例变量格式 (@ivar)
        unless key.start_with?("@")
          # puts "[调试] (恢复) 跳过非实例变量键: #{key} for #{obj.class}"
          next
        end

        ivar_symbol = key.to_sym

        # 特殊处理：如果对象是 Table，则跳过 @elements 的赋值
        # 因为 Table 对象应该在 REDUCED_CLASS_INSTANTIATORS 中通过构造函数完全创建
        next if obj.is_a?(Table) && ivar_symbol == :@elements

        # 检查实例变量或 setter 是否存在
        has_ivar = obj.instance_variable_defined?(ivar_symbol)
        setter_method_name = ivar_symbol.to_s[1..-1] + "="
        setter_method = setter_method_name.to_sym
        has_setter = obj.respond_to?(setter_method)

        # 如果目标对象上既没有这个实例变量也没有对应的 setter，则跳过
        # 这可能是因为 JSON 数据来自于不同版本或有冗余数据
        unless has_ivar || has_setter
          # 可以取消注释以调试版本不匹配问题
          # puts "[信息] (恢复) #{obj.class} 既无实例变量 #{ivar_symbol} 也无 setter 方法 #{setter_method}。跳过 JSON 属性 '#{key}'。"
          next
        end

        # 递归恢复属性值
        begin
          restored_value = restore_value(value)

          # 跳过赋值，如果 restore_value 返回 nil (例如，尝试恢复 RGSS3 Feature 到 RGSS2)
          if restored_value.nil? && value.is_a?(Hash) && value.key?("json_class") && value["json_class"].start_with?("RPG::")
            # 确定这个 nil 是否是预期中的版本不匹配造成的
            is_expected_nil = case value["json_class"]
              when "RPG::BaseItem::Feature", "RPG::UsableItem::Effect", "RPG::UsableItem::Damage"
                @rgss_version == "RGSS2" # 在 RGSS2 模式下恢复这些 RGSS3 类时，预期得到 nil
              else false
              end
            # 如果是预期中的 nil，则跳过赋值
            next if is_expected_nil
            # 如果不是预期中的 nil，则打印警告并跳过
            puts "[警告] (恢复) 为 #{obj.class} 的属性 #{ivar_symbol} 恢复了 nil 值，原始 JSON 类是 #{value["json_class"]}。检查版本兼容性或恢复逻辑。"
            next
          end

          # 特殊处理 RPG::Map 的 @events 哈希键（确保是整数）
          if ivar_symbol == :@events && obj.is_a?(RPG::Map) && restored_value.is_a?(Hash)
            restored_hash = {}
            restored_value.each { |k, v| restored_hash[k.to_i] = v } # Convert keys to integers
            has_setter ? obj.send(setter_method, restored_hash) : obj.instance_variable_set(ivar_symbol, restored_hash)
            # 不再需要对 @cell_data 进行特殊类型检查
            # 优先使用 setter 方法赋值
          elsif has_setter
            obj.send(setter_method, restored_value)
            # 否则直接设置实例变量 (如果存在)
          elsif has_ivar
            obj.instance_variable_set(ivar_symbol, restored_value)
            # else 的情况已在前面 next 跳过
          end
        rescue StandardError => e
          # 捕获通用错误以提高健壮性
          puts "[警告] (恢复) 为 #{obj.class} 设置属性 #{ivar_symbol} 时错误: #{e.class}: #{e.message}。值: #{value.inspect[0..100]}...。跳过。"
        end
      end # data.each
    end # populate_attributes
  end # RvdataRestorer
end # Converter
