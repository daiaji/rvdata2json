# lib/converter.rb
# 包含核心的 RVData <-> JSON 转换逻辑

require "oj"
require "fileutils"
require "set"

# 转换器模块，包含 IO、导出器和恢复器
module Converter
  # 文件 IO 操作子模块
  module IO
    # ... (load_marshal_data, load_json_data, write_json_data, write_marshal_data) ...
    def self.load_marshal_data(input_file)
      begin
        File.open(input_file, "rb") { |f| Marshal.load(f) }
      rescue ArgumentError => e
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
        data = Oj.load(json_string, mode: :compat, symbol_keys: false)
        if data.is_a?(Hash) && File.basename(input_file, ".json") == "MapInfos"
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
          (obj.is_a?(Table) && (obj.instance_variable_get(:@elements).nil? || !obj.instance_variable_get(:@elements).is_a?(Array) || obj.instance_variable_get(:@elements).any? { |el| !el.is_a?(Integer) } || obj.instance_variable_get(:@xsize).nil? || obj.instance_variable_get(:@ysize).nil? || obj.instance_variable_get(:@zsize).nil?)) ||
          (defined?(RPG::Animation::Frame) && obj.is_a?(RPG::Animation::Frame) && obj.instance_variable_get(:@cell_data).nil?) ||
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
      return nil if object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)
      oid = object.object_id
      return nil if visited.include?(oid)
      visited.add(oid)
      result = nil
      begin
        if block.call(object)
          return { path: current_path, object: object }
        end
        case object
        when Array
          object.each_with_index do |item, index|
            result = find_problematic_path(item, "#{current_path}[#{index}]", visited, &block); break if result
          end
        when Hash
          object.reject { |k, _| k == "__rvdata2json_source_file__" }.each do |key, value|
            result = find_problematic_path(value, "#{current_path}{#{key.inspect}}", visited, &block); break if result
          end
        else
          if object.respond_to?(:instance_variables)
            object.instance_variables.each do |ivar|
              next if ivar.to_s.start_with?("@_")
              begin
                value = object.instance_variable_get(ivar)
                result = find_problematic_path(value, "#{current_path}.#{ivar}", visited, &block); break if result
                # === FIX: Handle unused variable 'e' ===
              rescue StandardError # Changed from "rescue => e"
                # Ignore errors getting ivar, maybe log them?
                # puts "[Debug] Error getting #{current_path}.#{ivar}"
                # ========================================
              end
            end
          end
        end
      ensure
        visited.delete(oid)
      end
      result
    end
  end # IO

  # JsonExporter remains the same
  class JsonExporter
    DEPRECATED_ATTRIBUTES = {
      "RGSS3" => { # 导出为 RGSS3 JSON 时，过滤掉这些 RGSS2 特有属性
        "RPG::Actor" => Set.new([:@exp_basis, :@exp_inflation, :@parameters, :@weapon_id, :@armor1_id, :@armor2_id, :@armor3_id, :@armor4_id, :@two_swords_style, :@fix_equipment, :@auto_battle, :@super_guard, :@pharmacology, :@critical_bonus]),
        "RPG::Armor" => Set.new([:@kind, :@price, :@eva, :@atk, :@def, :@spi, :@agi, :@prevent_critical, :@half_mp_cost, :@double_exp_gain, :@auto_hp_recover, :@element_set, :@state_set]), # price in EquipItem in RGSS3
        "RPG::Weapon" => Set.new([:@price, :@hit, :@atk, :@def, :@spi, :@agi, :@two_handed, :@fast_attack, :@dual_attack, :@critical_bonus, :@element_set, :@state_set]), # price/animation_id in EquipItem/Weapon in RGSS3
        "RPG::Item" => Set.new([:@price, :@consumable, :@hp_recovery_rate, :@hp_recovery, :@mp_recovery_rate, :@mp_recovery, :@parameter_type, :@parameter_points]), # price/consumable in Item in RGSS3
        "RPG::Skill" => Set.new([:@hit]),
        "RPG::Enemy" => Set.new([:@battler_hue, :@maxhp, :@maxmp, :@atk, :@def, :@spi, :@agi, :@hit, :@eva, :@drop_item1, :@drop_item2, :@levitate, :@has_critical, :@element_ranks, :@state_ranks]), # battler_hue, exp, gold in Enemy in RGSS3
        "RPG::State" => Set.new([:@atk_rate, :@def_rate, :@spi_rate, :@agi_rate, :@nonresistance, :@offset_by_opposite, :@slip_damage, :@reduce_hit_ratio, :@battle_only, :@release_by_damage, :@hold_turn, :@auto_release_prob, :@element_set, :@state_set]),
        "RPG::System" => Set.new([:@passages, :@battler_hue]), # battler_hue in System in RGSS3
        "RPG::System::TestBattler" => Set.new([:@weapon_id, :@armor1_id, :@armor2_id, :@armor3_id, :@armor4_id]),
        "RPG::Troop::Member" => Set.new([:@immortal]),
      },
      "RGSS2" => { # 导出为 RGSS2 JSON 时，过滤掉这些 RGSS3 特有属性
        "RPG::BaseItem" => Set.new([:@features]), # Filter features from all BaseItem subclasses
        "RPG::UsableItem" => Set.new([:@success_rate, :@repeats, :@tp_gain, :@hit_type, :@damage, :@effects]), # Filter RGSS3 UsableItem attrs
        "RPG::Actor" => Set.new([:@nickname, :@max_level, :@equips]),
        "RPG::Armor" => Set.new([:@atype_id, :@etype_id, :@params, :@price]),
        "RPG::Weapon" => Set.new([:@wtype_id, :@etype_id, :@params, :@price]),
        "RPG::Item" => Set.new([:@itype_id, :@price, :@consumable]),
        "RPG::Skill" => Set.new([:@stype_id, :@tp_cost, :@required_wtype_id1, :@required_wtype_id2]),
        "RPG::Enemy" => Set.new([:@params, :@drop_items, :@battler_hue, :@exp, :@gold]),
        "RPG::State" => Set.new([:@remove_at_battle_end, :@remove_by_restriction, :@auto_removal_timing, :@min_turns, :@max_turns, :@remove_by_damage, :@chance_by_damage, :@remove_by_walking, :@steps_to_remove]),
        "RPG::Map" => Set.new([:@display_name, :@tileset_id, :@specify_battleback, :@battleback1_name, :@battleback2_name, :@note]),
        "RPG::System" => Set.new([:@japanese, :@currency_unit, :@skill_types, :@weapon_types, :@armor_types, :@title1_name, :@title2_name, :@opt_draw_title, :@opt_use_midi, :@opt_transparent, :@opt_followers, :@opt_slip_death, :@opt_floor_death, :@opt_display_tp, :@opt_extra_exp, :@window_tone, :@battleback1_name, :@battleback2_name, :@battler_hue]),
        "RPG::System::TestBattler" => Set.new([:@equips]),
      },
    }.freeze

    def initialize(rgss_version); @rgss_version = rgss_version; @visited_unpack = Set.new; @visited_clean = {}; end
    def export(object); @visited_unpack.clear; unpack_recursively(object); @visited_clean.clear; clean_for_export(object); end

    private

    def unpack_recursively(object); return if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String); return unless object.respond_to?(:object_id); oid = object.object_id; return if @visited_unpack.include?(oid); @visited_unpack.add(oid); begin; call_unpack_names(object) if object.respond_to?(:unpack_names); if object.respond_to?(:instance_variables); object.instance_variables.each { |ivar| next if ivar.to_s.start_with?("@_"); begin; ivar_value = object.instance_variable_get(ivar); unpack_recursively(ivar_value);     rescue StandardError; end }; elsif object.is_a?(Array); object.each { |item| unpack_recursively(item) }; elsif object.is_a?(Hash); object.reject { |k, _| k == "__rvdata2json_source_file__" }.each { |key, value| unpack_recursively(key); unpack_recursively(value) }; end;     ensure; end; end
    def call_unpack_names(object); begin; object.unpack_names;     rescue ArgumentError => e; if e.message.include?("wrong number of arguments") && !object.is_a?(RPG::Map) && !object.is_a?(RPG::System); elsif !e.message.include?("super: no superclass method"); puts "[警告] 调用 #{object.class}#unpack_names 时参数错误: #{e.message}"; end;     rescue NoMethodError => e; unless e.message.include?("super: no superclass method") && (object.is_a?(RPG::Map) || object.is_a?(RPG::System)); puts "[警告] 在 #{object.class} 上执行 unpack_names 时方法未找到: #{e.class}: #{e.message}"; end;     rescue => e; puts "[警告] 在 #{object.class} 上执行 unpack_names 时出错: #{e.class}: #{e.message}"; end; end

    def clean_for_export(object); return object if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String); return nil unless object.respond_to?(:object_id); oid = object.object_id; return @visited_clean[oid] if @visited_clean.key?(oid); class_name_str = object.class.name; unless class_name_str && !class_name_str.empty?; puts "[警告] 遇到匿名或未命名类实例: #{object.inspect[0..100]}..."; if object.is_a?(Array); result = []; @visited_clean[oid] = result; object.each { |item| result << clean_for_export(item) }; return result; elsif object.is_a?(Hash); result = {}; @visited_clean[oid] = result; object.reject { |k, _| k == "__rvdata2json_source_file__" }.each { |key, value| cleaned_key = clean_for_export(key); cleaned_value = clean_for_export(value); result[cleaned_key] = cleaned_value }; return result; else; return nil; end; end; cleaned_object = case object
      when Array; result = []; @visited_clean[oid] = result; object.each { |item| result << clean_for_export(item) }; result
      when Hash; is_map_infos = class_name_str == "Hash" && object.keys.all? { |k| k.is_a?(Integer) }; result = {}; result["json_class"] = class_name_str unless is_map_infos || class_name_str == "Array"; @visited_clean[oid] = result; object.reject { |k, _| k == "__rvdata2json_source_file__" }.each { |key, value| cleaned_key = clean_for_export(key); cleaned_value = clean_for_export(value); result[cleaned_key] = cleaned_value }; result.delete("json_class") if is_map_infos; result
      when Table; result = { "json_class" => class_name_str }; @visited_clean[oid] = result; result["@num_of_dimensions"] = dim = object.num_of_dimensions; result["@xsize"] = xsize = object.xsize; result["@ysize"] = ysize = object.ysize; result["@zsize"] = zsize = object.zsize; result["@num_of_elements"] = num_elements = object.num_of_elements; elements = object.instance_variable_get(:@elements) || []; elements = elements[0...num_elements] if elements.size > num_elements && num_elements >= 0; exported_elements = []; begin; if num_elements <= 0 || dim <= 0; exported_elements = []; elsif dim == 1; exported_elements = elements; elsif dim == 2; if xsize > 0; exported_elements = elements.each_slice(xsize).to_a; else; exported_elements = Array.new([ysize, 0].max) { [] }; end; elsif dim == 3; z_slice_size = xsize * ysize; if z_slice_size > 0; exported_elements = elements.each_slice(z_slice_size).map { |z_slice| if xsize > 0; z_slice.each_slice(xsize).to_a; else; Array.new([ysize, 0].max) { [] }; end }; else; exported_elements = Array.new([zsize, 0].max) { Array.new([ysize, 0].max) { [] } }; end; else; exported_elements = elements; end;         rescue ArgumentError => e; puts "[警告] 处理 Table (dim=#{dim}, size=#{xsize}x#{ysize}x#{zsize}, elements=#{num_elements}) 时出错: #{e.message}. 返回扁平数组。"; exported_elements = elements; end; result["@elements"] = exported_elements; result
      when Color, Tone, Rect; result = { "json_class" => class_name_str }; @visited_clean[oid] = result; object.instance_variables.each { |ivar| next if ivar.to_s.start_with?("@_"); key = ivar.to_s; value = object.instance_variable_get(ivar); result[key] = clean_for_export(value) }; result
      else; result = { "json_class" => class_name_str }; @visited_clean[oid] = result; deprecated_attrs = DEPRECATED_ATTRIBUTES[@rgss_version]; filter_set = Set.new; klass = object.class; while klass != Object && klass != nil && klass.name; set_for_class = deprecated_attrs[klass.name]; filter_set.merge(set_for_class) if set_for_class; if @rgss_version == "RGSS2"; base_item_filter = deprecated_attrs["RPG::BaseItem"]; filter_set.merge(base_item_filter) if base_item_filter && klass.ancestors.include?(RPG::BaseItem); usable_item_filter = deprecated_attrs["RPG::UsableItem"]; filter_set.merge(usable_item_filter) if usable_item_filter && klass.ancestors.include?(RPG::UsableItem); end; klass = klass.superclass; end; if object.respond_to?(:instance_variables); object.instance_variables.sort.each { |ivar| ivar_s = ivar.to_s; next if ivar_s.start_with?("@_"); next if filter_set.include?(ivar); key = ivar_s; value = nil; begin; value = object.instance_variable_get(ivar);       rescue => e; puts "[警告] 获取实例变量 #{ivar_s} on #{object.class} 时出错: #{e.message}"; next; end; result[key] = clean_for_export(value) }; end; result;       end; cleaned_object;     end
  end # JsonExporter

  # RvdataRestorer with fixes
  class RvdataRestorer
    REDUCED_CLASS_INSTANTIATORS = {
      "RPG::Event" => ->(data, restorer) { RPG::Event.new(data["@x"], data["@y"]) },
      "RPG::EventCommand" => ->(data, restorer) { RPG::EventCommand.new(data["@code"], data["@indent"], restorer.restore_value(data["@parameters"])) },
      "RPG::MoveCommand" => ->(data, restorer) { RPG::MoveCommand.new(data["@code"], restorer.restore_value(data["@parameters"])) },
      "RPG::Map" => ->(data, restorer) { RPG::Map.new(data["@width"], data["@height"]) },
      "Color" => ->(data, restorer) { Color.new([data["@red"], data["@green"], data["@blue"], data["@alpha"]]) },
      "Tone" => ->(data, restorer) { Tone.new([data["@red"], data["@green"], data["@blue"], data["@gray"]]) },
      "Rect" => ->(data, restorer) { Rect.new(data["@x"], data["@y"], data["@width"], data["@height"]) },
      "Table" => ->(data, restorer) do
        dimensions = data["@num_of_dimensions"].to_i; xsize = data["@xsize"].to_i; ysize = data["@ysize"].to_i; zsize = data["@zsize"].to_i
        elements_data = restorer.restore_value(data["@elements"]) || []; flat_elements = elements_data.flatten.map(&:to_i)
        num_elements = data["@num_of_elements"].to_i; num_elements = 0 if num_elements < 0
        if flat_elements.size < num_elements; flat_elements.fill(0, flat_elements.size, num_elements - flat_elements.size); elsif flat_elements.size > num_elements; flat_elements = flat_elements.slice(0, num_elements); end
        packed_data = [dimensions, xsize, ysize, zsize, num_elements] + flat_elements; Table.new(packed_data)
      end,
      "RPG::BaseItem::Feature" => ->(data, restorer) { RPG::BaseItem::Feature.new(data["@code"], data["@data_id"], data["@value"]) },
      "RPG::UsableItem::Effect" => ->(data, restorer) { RPG::UsableItem::Effect.new(data["@code"], data["@data_id"], data["@value1"], data["@value2"]) },
      "RPG::UsableItem::Damage" => ->(data, restorer) { RPG::UsableItem::Damage.new },
    }.freeze

    def initialize(rgss_version); @rgss_version = rgss_version; @object_cache = {}; end

    def restore(data)
      @object_cache.clear
      if data.is_a?(Hash) && data.key?("__rvdata2json_source_file__") && File.basename(data["__rvdata2json_source_file__"], ".json") == "MapInfos"
        actual_data = data.reject { |k, _| k == "__rvdata2json_source_file__" }; restored_map_infos = {}; actual_data.each { |key, value_data| restored_map_infos[key.to_i] = restore_value(value_data) }; return restored_map_infos
      else; return restore_value(data);       end
    end

    def restore_value(value)
      case value
      when Array; restore_array(value)
      when Hash; restore_hash(value)
      else; value;       end
    end

    private

    def restore_array(array); array.map { |item| restore_value(item) }; end
    def restore_hash(hash); if hash.key?("json_class"); restore_instance(hash); else; hash.transform_values { |v| restore_value(v) }; end; end

    def restore_instance(data)
      class_name = data["json_class"]; return data["s"].to_sym if class_name == "Symbol" && data.key?("s"); klass = find_class(class_name); obj = instantiate_object(klass, data); populate_attributes(obj, data) if obj; obj
    end

    def find_class(class_name); Object.const_get(class_name);     rescue NameError; raise NameError, "错误：未找到类 '#{class_name}'。请确保已加载正确的 RGSS 定义。", caller; end
    def instantiate_object(klass, data); if REDUCED_CLASS_INSTANTIATORS.key?(klass.name); begin; return REDUCED_CLASS_INSTANTIATORS[klass.name].call(data, self);     rescue => e; raise "实例化特殊类 '#{klass.name}' (注册表) 时出错: #{e.message}\nData: #{data.inspect[0..200]}...\n原始回溯:\n#{e.backtrace.first(5).join("\n")}"; end; else; generic_instantiate(klass, data); end; end

    # Simplified generic_instantiate error handling
    def generic_instantiate(klass, data)
      begin
        return klass.new
      rescue ArgumentError => e
        # Avoid complex parsing, just report the mismatch if it happens
        puts "[警告] (恢复) 实例化通用类 #{klass.name} 时参数不匹配: #{e.message}. 检查 initialize 定义。"
        # Still try without args as a fallback, especially for the Frame warning
        begin
          return klass.new
        rescue ArgumentError
          # If no-arg call *also* fails, raise the original error message for clarity
          raise ArgumentError, "实例化通用类 #{klass.name} 时参数不匹配: #{e.message}. 检查 #{klass.name}#initialize 定义。"
        end
      rescue => e
        raise "实例化通用类 #{klass.name} 时发生未知错误: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    def populate_attributes(obj, data)
      return unless obj
      # puts "[Debug Populate START] Processing #{obj.class} (#{obj.object_id})" # Optional general debug

      data.each do |key, value|
        next if key == "json_class" || key == "__rvdata2json_source_file__" || key.start_with?("@_")
        next unless key.start_with?("@")

        ivar_symbol = key.to_sym

        if obj.is_a?(Table) && ivar_symbol == :@elements; next; end

        has_ivar = obj.instance_variable_defined?(ivar_symbol)
        setter_method = "#{ivar_symbol.to_s[1..-1]}=".to_sym
        has_setter = obj.respond_to?(setter_method)

        # === REMOVE DEBUG for is_system_title_bgm ===
        # is_system_title_bgm = obj.is_a?(RPG::System) && ivar_symbol == :@title_bgm
        # puts "[Debug Populate] Processing key=#{key} for #{obj.class}" if is_system_title_bgm
        # if is_system_title_bgm
        #    puts "[Debug Populate]   has_ivar=#{has_ivar}, has_setter=#{has_setter}"
        # end
        # ============================================

        unless has_ivar || has_setter; next; end

        begin
          # puts "[Debug Populate]   Calling restore_value for #{key}..." if is_system_title_bgm
          restored_value = restore_value(value)
          # if is_system_title_bgm
          #   puts "[Debug Populate]   restore_value returned: #{restored_value.inspect} (class: #{restored_value.class})"
          # end

          # === Add Nil Checks for Critical Nested Objects ===
          if obj.is_a?(RPG::System) && [:boat, :ship, :airship, :title_bgm, :battle_bgm, :battle_end_me, :gameover_me, :terms].include?(ivar_symbol) && restored_value.nil?
            puts "[警告] (恢复) RPG::System 的属性 #{ivar_symbol} 被意外恢复为 nil。JSON 值: #{value.inspect[0..100]}..."
          elsif obj.is_a?(RPG::Animation) && ivar_symbol == :timings && restored_value.nil?
            puts "[警告] (恢复) RPG::Animation 的属性 @timings 被意外恢复为 nil。JSON 值: #{value.inspect[0..100]}..."
          elsif defined?(RPG::Animation::Timing) && obj.is_a?(RPG::Animation::Timing) && ivar_symbol == :se && restored_value.nil?
            puts "[警告] (恢复) RPG::Animation::Timing 的属性 @se 被意外恢复为 nil。JSON 值: #{value.inspect[0..100]}..."
            # Add more checks if needed
          end
          # ===============================================

          if ivar_symbol == :@events && obj.is_a?(RPG::Map) && restored_value.is_a?(Hash)
            restored_hash = {}; restored_value.each { |k, v| restored_hash[k.to_i] = v }
            has_setter ? obj.send(setter_method, restored_hash) : obj.instance_variable_set(ivar_symbol, restored_hash)
          elsif ivar_symbol == :@cell_data && defined?(RPG::Animation::Frame) && obj.is_a?(RPG::Animation::Frame)
            if @rgss_version == "RGSS2"; unless restored_value.is_a?(Table); puts "[警告] (恢复) Frame (RGSS2) @cell_data 期望 Table，得到 #{restored_value.class}。跳过。"; next; end elsif @rgss_version == "RGSS3"; unless restored_value.is_a?(Array); puts "[警告] (恢复) Frame (RGSS3) @cell_data 期望 Array，得到 #{restored_value.class}。跳过。"; next; end; end
            has_setter ? obj.send(setter_method, restored_value) : obj.instance_variable_set(ivar_symbol, restored_value)
          elsif has_setter
            # puts "[Debug Populate]   Attempting obj.send(#{setter_method.inspect}, #{restored_value.inspect})" if obj.is_a?(RPG::System) && ivar_symbol == :@title_bgm
            obj.send(setter_method, restored_value)
            # if obj.is_a?(RPG::System) && ivar_symbol == :@title_bgm
            #   puts "[Debug Populate]   Value after setter: #{obj.instance_variable_get(ivar_symbol).inspect}"
            # end
          elsif has_ivar
            # puts "[Debug Populate]   Attempting obj.instance_variable_set(#{ivar_symbol.inspect}, #{restored_value.inspect})" if obj.is_a?(RPG::System) && ivar_symbol == :@title_bgm
            obj.instance_variable_set(ivar_symbol, restored_value)
            # if obj.is_a?(RPG::System) && ivar_symbol == :@title_bgm
            #   puts "[Debug Populate]   Value after ivar_set: #{obj.instance_variable_get(ivar_symbol).inspect}"
            # end
          end
          # === FIX: Handle unused variable 'e' ===
        rescue StandardError => e # Keep 'e' if we use it in the message
          puts "[警告] (恢复) 为 #{obj.class} 设置属性 #{ivar_symbol} 时错误: #{e.class}: #{e.message}。值: #{value.inspect[0..100]}...。跳过。"
          # =======================================
        end
      end
      # if obj.is_a?(RPG::System)
      #    final_bgm = obj.instance_variable_get(:@title_bgm) rescue "Error getting final value"
      #    puts "[Debug Populate END] Finished RPG::System. Final @title_bgm: #{final_bgm.inspect}"
      # end
    end
  end # RvdataRestorer
end # Converter
