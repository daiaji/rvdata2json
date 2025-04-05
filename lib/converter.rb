# lib/converter.rb
# 包含核心的 RVData/RXData <-> JSON 转换逻辑

require "oj"
require "fileutils"
require "set"

# 转换器模块，包含 IO、导出器和恢复器
module Converter
  # 文件 IO 操作子模块 (保持不变)
  module IO
    # ... (load_marshal_data, load_json_data, write_json_data, write_marshal_data, find_problematic_path 保持不变) ...
    def self.load_marshal_data(input_file)
      begin
        File.open(input_file, "rb") { |f| Marshal.load(f) }
      rescue ArgumentError => e
        if e.message.include?("undefined class/module") || e.message.include?("allocator is not defined")
          raise NameError, "加载 Marshal 数据 '#{File.basename(input_file)}' 时出错: #{e.message}. 请确保已加载正确的 RGSS 定义 (rgss1.rb, rgss2.rb 或 rgss3.rb)。", caller
        else
          raise ArgumentError, "加载 Marshal 数据 '#{File.basename(input_file)}' 时参数错误 (可能是版本不匹配或文件损坏): #{e.message}"
        end
      rescue TypeError => e
        raise TypeError, "加载 Marshal 数据 '#{File.basename(input_file)}' 时类型错误 (确保加载了正确的 RGSS 定义): #{e.message}"
      rescue => e
        raise "读取或解析 Marshal 文件 '#{File.basename(input_file)}' 时出错: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
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
              begin; value = object.instance_variable_get(ivar); result = find_problematic_path(value, "#{current_path}.#{ivar}", visited, &block); break if result;               rescue StandardError; end
            end
          end
        end
      ensure
        visited.delete(oid)
      end
      result
    end
  end # IO

  # 将 Ruby 对象转换为适合 JSON 序列化的数据结构 (负责 unpack 和 过滤)
  class JsonExporter
    # 定义在导出特定版本 JSON 时应被过滤掉的属性
    # (只包含 在当前版本中已废弃 的 旧版本属性)
    ATTRIBUTES_REMOVED = {
      # --- 导出为 RGSS3 (Ace) JSON 时，过滤掉这些 RGSS1/RGSS2 废弃属性 ---
      "RGSS3" => {
        # 来自 RGSS1/RGSS2，在 RGSS3 中废弃/取代
        "RPG::Actor" => Set.new([
          :@exp_basis, :@exp_inflation, :@parameters, :@weapon_id, :@armor1_id,
          :@armor2_id, :@armor3_id, :@armor4_id, :@two_swords_style, :@fix_equipment,
          :@auto_battle, :@super_guard, :@pharmacology, :@critical_bonus,
        ]),
        "RPG::Class" => Set.new([
          :@position, :@weapon_set, :@armor_set, :@element_ranks, :@state_ranks,
          :@skill_name_valid, :@skill_name,
        ]),
        "RPG::Skill" => Set.new([
          :@base_damage, :@variance, :@atk_f, :@spi_f, :@physical_attack,
          :@damage_to_mp, :@absorb_damage, :@ignore_defense, :@element_set,
          :@plus_state_set, :@minus_state_set, :@hit,
        ]),
        "RPG::Item" => Set.new([
          :@base_damage, :@variance, :@atk_f, :@spi_f, :@physical_attack,
          :@damage_to_mp, :@absorb_damage, :@ignore_defense, :@element_set,
          :@plus_state_set, :@minus_state_set, :@hp_recovery_rate, :@hp_recovery,
          :@mp_recovery_rate, :@mp_recovery, :@parameter_type, :@parameter_points,
        ]),
        "RPG::Weapon" => Set.new([
          :@hit, :@atk, :@def, :@spi, :@agi, :@two_handed, :@fast_attack,
          :@dual_attack, :@critical_bonus, :@element_set, :@state_set,
        ]),
        "RPG::Armor" => Set.new([
          :@kind, :@eva, :@atk, :@spi, :@agi, :@prevent_critical, :@half_mp_cost,
          :@double_exp_gain, :@auto_hp_recover, :@element_set, :@state_set,
        ]),
        "RPG::Enemy" => Set.new([
          :@maxhp, :@maxmp, :@atk, :@def, :@spi, :@agi, :@hit, :@eva,
          :@drop_item1, :@drop_item2, :@levitate, :@has_critical,
          :@element_ranks, :@state_ranks,
        ]),
        "RPG::Enemy::Action" => Set.new([
          :@kind, :@basic,
        ]),
        "RPG::State" => Set.new([
          :@atk_rate, :@def_rate, :@spi_rate, :@agi_rate, :@nonresistance,
          :@offset_by_opposite, :@slip_damage, :@reduce_hit_ratio, :@battle_only,
          :@release_by_damage, :@hold_turn, :@auto_release_prob,
          :@shock_release_prob, # From RGSS1
          :@element_set, :@state_set, # From RGSS2
          :@guard_element_set, :@plus_state_set, :@minus_state_set, # From RGSS1
        ]),
        "RPG::System" => Set.new([
          :@magic_number, # From RGSS1/RGSS2
          :@passages,      # From RGSS2
        ]),
        "RPG::System::TestBattler" => Set.new([
          :@weapon_id, :@armor1_id, :@armor2_id, :@armor3_id, :@armor4_id,
        ]),
        "RPG::Troop::Member" => Set.new([
          :@immortal, # From RGSS1/RGSS2
        ]),
        "RPG::Animation::Timing" => Set.new([
          :@condition, # From RGSS1
        ]),
        "RPG::Map" => Set.new([
          # RGSS1/2 Map attributes not present in Ace's Map definition
          # (Ace uses @battleback_floor/wall_name, but System has 1/2)
          # If these appear on Map object, they are non-Ace standard for Map.
          :@battleback_floor_name, :@battleback_wall_name, # If strictly following Ace RPG::Map init
        ]),
        "RPG::Tileset" => Set.new([
          # RGSS1 Tileset attributes removed in later versions
          :@tileset_name, :@autotile_names, :@panorama_name, :@panorama_hue,
          :@fog_name, :@fog_hue, :@fog_opacity, :@fog_blend_type, :@fog_zoom,
          :@fog_sx, :@fog_sy, :@battleback_name, :@passages, :@priorities,
          :@terrain_tags,
        ]),
      },

      # --- 导出为 RGSS2 (VX) JSON 时，只过滤掉这些 RGSS1 废弃属性 ---
      "RGSS2" => {
        "RPG::System" => Set.new([
          :@magic_number, # From RGSS1, removed in RGSS2
        ]),
        "RPG::State" => Set.new([
          :@shock_release_prob, # From RGSS1, removed in RGSS2
          :@guard_element_set, :@plus_state_set, :@minus_state_set, # From RGSS1, removed in RGSS2
        ]),
        "RPG::Animation::Timing" => Set.new([
          :@condition, # From RGSS1, removed in RGSS2
        ]),
        "RPG::Tileset" => Set.new([
          # RGSS1 Tileset attributes removed/changed in RGSS2 (VX uses @passages in System)
          :@tileset_name, :@autotile_names, :@panorama_name, :@panorama_hue,
          :@fog_name, :@fog_hue, :@fog_opacity, :@fog_blend_type, :@fog_zoom,
          :@fog_sx, :@fog_sy, :@battleback_name, :@passages, :@priorities,
          :@terrain_tags,
        ]),
      # NO RGSS3 attributes should be listed here for removal based on history.
      },

      # --- 导出为 RGSS1 (XP) 时，没有更旧的标准版本，不移除 ---
      "RGSS1" => {},
    }.freeze
    # --- 结束修改 ---

    def initialize(rgss_version)
      @rgss_version = rgss_version
      @visited_unpack = Set.new
      @visited_clean = {} # 用于处理循环引用
    end

    # export, unpack_recursively, call_unpack_names, clean_for_export 保持不变
    def export(object)
      @visited_unpack.clear
      unpack_recursively(object) # 递归解包字符串
      @visited_clean.clear
      cleaned_data = clean_for_export(object) # 转换为纯 Ruby 结构并过滤
      cleaned_data
    end

    private

    def unpack_recursively(object)
      return if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)
      return unless object.respond_to?(:object_id)
      oid = object.object_id
      return if @visited_unpack.include?(oid)
      @visited_unpack.add(oid)
      begin
        call_unpack_names(object) if object.respond_to?(:unpack_names)
        if object.respond_to?(:instance_variables)
          object.instance_variables.each do |ivar|
            next if ivar.to_s.start_with?("@_")
            begin; ivar_value = object.instance_variable_get(ivar); unpack_recursively(ivar_value);             rescue StandardError; end
          end
        elsif object.is_a?(Array)
          object.each { |item| unpack_recursively(item) }
        elsif object.is_a?(Hash)
          object.reject { |k, _| k == "__rvdata2json_source_file__" }.each do |key, value|
            unpack_recursively(key); unpack_recursively(value)
          end
        end
      ensure
        # Keep visited status during a single export run
      end
    end

    def call_unpack_names(object)
      begin
        object.unpack_names
      rescue ArgumentError => e
        unless e.message.include?("wrong number of arguments"); puts "[警告] 调用 #{object.class}#unpack_names 时参数错误: #{e.message}"; end
      rescue NoMethodError => e
        unless e.message.include?("super: no superclass method"); puts "[警告] 在 #{object.class} 上执行 unpack_names 时方法未找到: #{e.class}: #{e.message}"; end
      rescue => e
        puts "[警告] 在 #{object.class} 上执行 unpack_names 时出错: #{e.class}: #{e.message}"
      end
    end

    def clean_for_export(object)
      return object if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)
      unless object.respond_to?(:object_id)
        if object.is_a?(Array); return object.map { |item| clean_for_export(item) }; elsif object.is_a?(Hash); result = {}; object.reject { |k, _| k == "__rvdata2json_source_file__" }.each { |key, value| cleaned_key = clean_for_export(key); cleaned_value = clean_for_export(value); result[cleaned_key] = cleaned_value }; return result; else; puts "[错误] 无法处理类型为 #{object.class} 的无 object_id 对象。"; return nil; end
      end
      oid = object.object_id
      return @visited_clean[oid] if @visited_clean.key?(oid)
      class_name_str = object.class.name
      unless class_name_str && !class_name_str.empty?
        puts "[警告] 遇到匿名或未命名类实例，无法精确导出类型: #{object.inspect[0..100]}..."
        if object.is_a?(Array); result = []; @visited_clean[oid] = result; object.each { |item| result << clean_for_export(item) }; return result; elsif object.is_a?(Hash); result = {}; @visited_clean[oid] = result; object.reject { |k, _| k == "__rvdata2json_source_file__" }.each { |key, value| cleaned_key = clean_for_export(key); cleaned_value = clean_for_export(value); result[cleaned_key] = cleaned_value }; return result; else; puts "[错误] 无法处理匿名或未命名类的实例 (非 Array/Hash)。"; return nil; end
      end
      cleaned_object = case object
        when Array; result = []; @visited_clean[oid] = result; object.each { |item| result << clean_for_export(item) }; result
        when Hash; is_map_infos = class_name_str == "Hash" && object.keys.all? { |k| k.is_a?(Integer) }; result = {}; @visited_clean[oid] = result; object.reject { |k, _| k == "__rvdata2json_source_file__" }.each { |key, value| cleaned_key = clean_for_export(key); cleaned_value = clean_for_export(value); cleaned_key = cleaned_key.to_s if is_map_infos && cleaned_key.is_a?(Integer); result[cleaned_key] = cleaned_value }; result
        when Table; result = { "json_class" => class_name_str }; @visited_clean[oid] = result; result["@num_of_dimensions"] = dim = object.num_of_dimensions; result["@xsize"] = xsize = object.xsize; result["@ysize"] = ysize = object.ysize; result["@zsize"] = zsize = object.zsize; result["@num_of_elements"] = num_elements = object.num_of_elements; elements = object.instance_variable_get(:@elements) || []; elements = elements[0...num_elements] if elements.size > num_elements && num_elements >= 0; exported_elements = []; begin; if num_elements <= 0 || dim <= 0; exported_elements = []; elsif dim == 1; exported_elements = elements; elsif dim == 2; if xsize > 0; exported_elements = elements.each_slice(xsize).to_a; else; exported_elements = Array.new([ysize, 0].max) { [] }; end; elsif dim == 3; z_slice_size = xsize * ysize; if z_slice_size > 0; exported_elements = elements.each_slice(z_slice_size).map { |z_slice| if xsize > 0; z_slice.each_slice(xsize).to_a; else; Array.new([ysize, 0].max) { [] }; end }; else; exported_elements = Array.new([zsize, 0].max) { Array.new([ysize, 0].max) { [] } }; end; else; exported_elements = elements; puts "[警告] Table 维度 (#{dim}) 无效或不支持，导出为扁平数组。" if dim > 3; end;           rescue ArgumentError => e; puts "[警告] 处理 Table (dim=#{dim}, size=#{xsize}x#{ysize}x#{zsize}, elements=#{num_elements}) 时出错: #{e.message}. 返回扁平数组。"; exported_elements = elements; end; result["@elements"] = exported_elements; result
        when Color, Tone, Rect; result = { "json_class" => class_name_str }; @visited_clean[oid] = result; object.instance_variables.each { |ivar| next if ivar.to_s.start_with?("@_"); key = ivar.to_s; value = object.instance_variable_get(ivar); result[key] = clean_for_export(value) }; result
        else; result = { "json_class" => class_name_str }; @visited_clean[oid] = result; removed_attrs_for_target = ATTRIBUTES_REMOVED[@rgss_version] || {}; filter_set = Set.new; klass = object.class; while klass != Object && klass != nil && klass.name; set_for_class = removed_attrs_for_target[klass.name]; filter_set.merge(set_for_class) if set_for_class; if (@rgss_version == "RGSS2" || @rgss_version == "RGSS1") && defined?(RPG::BaseItem) && klass.ancestors.include?(RPG::BaseItem); filter_set.add(:@features) if removed_attrs_for_target["RPG::BaseItem"]&.include?(:@features); end; klass = klass.superclass; end; if object.respond_to?(:instance_variables); object.instance_variables.sort.each { |ivar| ivar_s = ivar.to_s; next if ivar_s.start_with?("@_"); next if filter_set.include?(ivar); key = ivar_s; value = nil; begin; value = object.instance_variable_get(ivar);         rescue => e; puts "[警告] 获取实例变量 #{ivar_s} on #{object.class} 时出错: #{e.message}"; next; end; result[key] = clean_for_export(value) }; end; result         end
      cleaned_object
    end
  end # JsonExporter

  # 从 JSON 解析的数据结构恢复 RVData/RXData 对象 (逻辑保持不变)
  class RvdataRestorer
    # REDUCED_CLASS_INSTANTIATORS, initialize, restore, restore_value, restore_array, restore_hash,
    # restore_instance, find_class, instantiate_object, generic_instantiate, populate_attributes 保持不变
    REDUCED_CLASS_INSTANTIATORS = {
      "RPG::Event" => ->(data, restorer) { RPG::Event.new(data["@x"], data["@y"]) },
      "RPG::EventCommand" => ->(data, restorer) { RPG::EventCommand.new(data["@code"], data["@indent"], restorer.restore_value(data["@parameters"])) },
      "RPG::MoveCommand" => ->(data, restorer) { RPG::MoveCommand.new(data["@code"], restorer.restore_value(data["@parameters"])) },
      "RPG::Map" => ->(data, restorer) { RPG::Map.new(data["@width"], data["@height"]) },
      "Color" => ->(data, restorer) { Color.new([data["@red"], data["@green"], data["@blue"], data["@alpha"]]) },
      "Tone" => ->(data, restorer) { Tone.new([data["@red"], data["@green"], data["@blue"], data["@gray"]]) },
      "Rect" => ->(data, restorer) { Rect.new(data["@x"], data["@y"], data["@width"], data["@height"]) },
      "Table" => ->(data, restorer) do
        dimensions = data["@num_of_dimensions"].to_i; xsize = data["@xsize"].to_i; ysize = data["@ysize"].to_i; zsize = data["@zsize"].to_i; elements_data = restorer.restore_value(data["@elements"]) || []; flat_elements = elements_data.flatten.map(&:to_i); num_elements = data["@num_of_elements"].to_i; num_elements = 0 if num_elements < 0; if flat_elements.size < num_elements; flat_elements.fill(0, flat_elements.size, num_elements - flat_elements.size); elsif flat_elements.size > num_elements; flat_elements = flat_elements.slice(0, num_elements); end; packed_data = [dimensions, xsize, ysize, zsize, num_elements] + flat_elements; Table.new(packed_data)
      end,
      "RPG::BaseItem::Feature" => ->(data, restorer) { defined?(RPG::BaseItem::Feature) ? RPG::BaseItem::Feature.new(data["@code"], data["@data_id"], data["@value"]) : nil },
      "RPG::UsableItem::Effect" => ->(data, restorer) { defined?(RPG::UsableItem::Effect) ? RPG::UsableItem::Effect.new(data["@code"], data["@data_id"], data["@value1"], data["@value2"]) : nil },
      "RPG::UsableItem::Damage" => ->(data, restorer) { defined?(RPG::UsableItem::Damage) ? RPG::UsableItem::Damage.new : nil },
    }.freeze

    def initialize(rgss_version)
      @rgss_version = rgss_version
      @object_cache = {}
    end

    def restore(data)
      @object_cache.clear
      if data.is_a?(Hash) && data.key?("__rvdata2json_source_file__") && File.basename(data["__rvdata2json_source_file__"], ".json") == "MapInfos"
        actual_data = data.reject { |k, _| k == "__rvdata2json_source_file__" }; restored_map_infos = {}; actual_data.each { |key, value_data| restored_map_infos[key.to_i] = restore_value(value_data) }; return restored_map_infos
      else
        return restore_value(data)
      end
    end

    def restore_value(value)
      case value
      when Array; restore_array(value)
      when Hash; oid = value.object_id; return @object_cache[oid] if @object_cache.key?(oid); restored = restore_hash(value); @object_cache[oid] = restored if restored; restored
      else; value;       end
    end

    private

    def restore_array(array); array.map { |item| restore_value(item) }; end
    def restore_hash(hash); hash.key?("json_class") ? restore_instance(hash) : hash.transform_values { |v| restore_value(v) }; end

    def restore_instance(data)
      class_name = data["json_class"]; return data["s"].to_sym if class_name == "Symbol" && data.key?("s"); cache_key = data.object_id; return @object_cache[cache_key] if @object_cache.key?(cache_key); klass = find_class(class_name); return nil unless klass; obj = instantiate_object(klass, data); return nil unless obj; @object_cache[obj.object_id] = obj; @object_cache[cache_key] = obj if cache_key; populate_attributes(obj, data); obj
    end

    def find_class(class_name); Object.const_get(class_name);     rescue NameError; return nil; end

    def instantiate_object(klass, data)
      if REDUCED_CLASS_INSTANTIATORS.key?(klass.name)
        begin; instance = REDUCED_CLASS_INSTANTIATORS[klass.name].call(data, self); return nil if instance.nil? && defined?(RPG) && klass.name.start_with?("RPG::") && !klass.name.include?("::Feature") && !klass.name.include?("::Effect") && !klass.name.include?("::Damage"); return instance;         rescue NameError => e; if e.message.match(/uninitialized constant RPG::(BaseItem::Feature|UsableItem::Effect|UsableItem::Damage)/); return nil; else; raise; end;         rescue => e; raise "实例化特殊类 '#{klass.name}' (注册表) 时出错: #{e.message}\nData: #{data.inspect[0..200]}...\n原始回溯:\n#{e.backtrace.first(5).join("\n")}"; end
      else; generic_instantiate(klass, data);       end
    end

    def generic_instantiate(klass, data)
      begin; klass.new;       rescue ArgumentError => e; known_param_classes = ["RPG::Event", "RPG::Map"]; if known_param_classes.include?(klass.name); raise ArgumentError, "类 #{klass.name} 需要参数来初始化，但未在 REDUCED_CLASS_INSTANTIATORS 中配置。请检查注册表或类的 initialize 方法。"; else; raise; end;       rescue => e; raise "实例化通用类 #{klass.name} 时发生未知错误: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"; end
    end

    def populate_attributes(obj, data)
      return unless obj
      data.each do |key, value|
        next if key == "json_class" || key == "__rvdata2json_source_file__" || key.start_with?("@_"); next unless key.start_with?("@"); ivar_symbol = key.to_sym; next if obj.is_a?(Table) && ivar_symbol == :@elements; has_ivar = obj.instance_variable_defined?(ivar_symbol); setter_method_name = ivar_symbol.to_s[1..-1] + "="; setter_method = setter_method_name.to_sym; has_setter = obj.respond_to?(setter_method); next unless has_ivar || has_setter
        begin
          restored_value = restore_value(value)
          if restored_value.nil? && value.is_a?(Hash) && value.key?("json_class")
            is_expected_nil = case value["json_class"]
              when "RPG::BaseItem::Feature", "RPG::UsableItem::Effect", "RPG::UsableItem::Damage", "RPG::Tileset"; @rgss_version == "RGSS1" || @rgss_version == "RGSS2"
              when "RPG::Area"; @rgss_version == "RGSS1" || @rgss_version == "RGSS3"
              else false
              end
            next if is_expected_nil
          end
          if ivar_symbol == :@events && obj.is_a?(RPG::Map) && restored_value.is_a?(Hash); restored_hash = {}; restored_value.each { |k, v| restored_hash[k.to_i] = v }; has_setter ? obj.send(setter_method, restored_hash) : obj.instance_variable_set(ivar_symbol, restored_hash) elsif has_setter; obj.send(setter_method, restored_value) elsif has_ivar; obj.instance_variable_set(ivar_symbol, restored_value) end
        rescue StandardError => e; puts "[警告] (恢复) 为 #{obj.class} 设置属性 #{ivar_symbol} 时错误: #{e.class}: #{e.message}。值: #{value.inspect[0..100]}...。跳过。";         end
      end
    end
  end # RvdataRestorer
end # Converter
