# 包含核心的 RVData <-> JSON 转换逻辑

require "json"
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
        data = JSON.parse(json_string)
        if data.is_a?(Hash) && File.basename(input_file, ".json") == "MapInfos"
          data["__source_file__"] = input_file # 注入来源信息用于恢复 MapInfos key 类型
        end
        data
      rescue JSON::ParserError => e
        raise "JSON 解析错误，文件 '#{input_file}': #{e.message}"
      rescue => e
        raise "读取或解析 JSON 文件 '#{input_file}' 时出错: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    def self.write_json_data(output_file, data)
      FileUtils.mkdir_p(File.dirname(output_file))
      begin
        json_string = JSON.pretty_generate(data, { quirks_mode: true, indent: "  ", space: " " })
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
            result = find_problematic_path(item, "#{current_path}[#{index}]", visited, &block)
            break if result
          end
        when Hash
          object.each do |key, value|
            next if key == "__source_file__"
            result = find_problematic_path(value, "#{current_path}{#{key.inspect}}", visited, &block)
            break if result
          end
        else
          if object.respond_to?(:instance_variables)
            object.instance_variables.each do |ivar|
              next if ivar.to_s.start_with?("@_")
              begin
                value = object.instance_variable_get(ivar)
                result = find_problematic_path(value, "#{current_path}.#{ivar}", visited, &block)
                break if result
              rescue => e
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

  # 将 Ruby 对象转换为适合 JSON 序列化的数据结构 (负责 unpack 和 过滤)
  class JsonExporter
    # 定义在导出特定版本 JSON 时应被过滤掉的属性
    DEPRECATED_ATTRIBUTES = {
      "RGSS3" => { # 导出为 RGSS3 JSON 时，过滤掉这些 RGSS2 兼容属性 或 非标准属性
        # ******** 修改点: 为 RGSS3 添加 Timing.@condition 过滤 ********
        "RPG::Animation::Timing" => Set.new([:@condition]),
        # ******** 结束修改 ********
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
        # ******** 修改点: 为 RGSS2 添加 Timing.@condition 过滤 ********
        "RPG::Animation::Timing" => Set.new([:@condition]),
        # ******** 结束修改 ********
        "RPG::BaseItem" => Set.new([:@features]), # Apply to all BaseItem subclasses
        "RPG::Actor" => Set.new([:@nickname, :@max_level, :@equips]),
        "RPG::Class" => Set.new([:@exp_params, :@params, :@features]),
        "RPG::UsableItem" => Set.new([:@success_rate, :@repeats, :@tp_gain, :@hit_type, :@damage, :@effects]),
        "RPG::Skill" => Set.new([:@stype_id, :@tp_cost, :@required_wtype_id1, :@required_wtype_id2]),
        "RPG::Item" => Set.new([:@itype_id]),
        "RPG::EquipItem" => Set.new([:@price, :@etype_id, :@params, :@features]),
        "RPG::Weapon" => Set.new([:@wtype_id, :@etype_id, :@params, :@features]),
        "RPG::Armor" => Set.new([:@atype_id, :@etype_id, :@params, :@features]),
        "RPG::Enemy" => Set.new([:@params, :@drop_items, :@features]),
        "RPG::State" => Set.new([:@remove_at_battle_end, :@remove_by_restriction, :@auto_removal_timing, :@min_turns, :@max_turns, :@remove_by_damage, :@chance_by_damage, :@remove_by_walking, :@steps_to_remove, :@features]),
        "RPG::System" => Set.new([:@japanese, :@currency_unit, :@skill_types, :@weapon_types, :@armor_types, :@title1_name, :@title2_name, :@opt_draw_title, :@opt_use_midi, :@opt_transparent, :@opt_followers, :@opt_slip_death, :@opt_floor_death, :@opt_display_tp, :@opt_extra_exp, :@window_tone, :@battleback1_name, :@battleback2_name]),
        "RPG::System::Terms" => Set.new([:@basic, :@params, :@etypes, :@commands]),
        "RPG::System::TestBattler" => Set.new([:@equips]),
        "RPG::Map" => Set.new([:@display_name, :@tileset_id, :@specify_battleback, :@battleback1_name, :@battleback2_name, :@note]),
        "RPG::Map::Encounter" => Set.new([:@region_set]),
      },
    }.freeze

    def initialize(rgss_version)
      @rgss_version = rgss_version
      @visited_unpack = Set.new
      @visited_clean = {}
    end

    def export(object)
      @visited_unpack.clear
      unpack_recursively(object)
      @visited_clean.clear
      cleaned_data = clean_for_export(object)
      cleaned_data
    end

    private

    def unpack_recursively(object)
      # ... (代码保持不变) ...
      return if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol)
      return if object.is_a?(String)
      return unless object.respond_to?(:object_id)
      oid = object.object_id
      return if @visited_unpack.include?(oid)
      @visited_unpack.add(oid)

      begin
        call_unpack_names(object) if object.respond_to?(:unpack_names)

        if object.respond_to?(:instance_variables)
          object.instance_variables.each do |ivar|
            next if ivar.to_s.start_with?("@_")
            begin
              ivar_value = object.instance_variable_get(ivar)
              unpack_recursively(ivar_value)
            rescue => e
            end
          end
        elsif object.is_a?(Array)
          object.each { |item| unpack_recursively(item) }
        elsif object.is_a?(Hash)
          object.each do |key, value|
            unpack_recursively(key)
            unpack_recursively(value)
          end
        end
      ensure
        # Keep visited set for the entire export run
      end
    end

    def call_unpack_names(object)
      # ... (代码保持不变) ...
      method_obj = object.method(:unpack_names)
      needs_version = method_needs_version_arg?(method_obj)

      begin
        if needs_version
          object.unpack_names(@rgss_version)
        elsif method_obj.arity == 0
          object.unpack_names
        else
          begin
            object.unpack_names
          rescue ArgumentError
            if needs_version
              object.unpack_names(@rgss_version)
            else
              raise
            end
          end
        end
      rescue ArgumentError => e
        puts "[警告] 调用 #{object.class}#unpack_names 时参数错误: #{e.message} (方法 arity: #{method_obj.arity}, 需要版本: #{needs_version})"
      rescue => e
        puts "[警告] 在 #{object.class} 上执行 unpack_names 时出错: #{e.class}: #{e.message}"
      end
    end

    def method_needs_version_arg?(method_obj)
      # ... (代码保持不变) ...
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

    def clean_for_export(object)
      # ... (处理基本类型, nil, 循环引用的代码保持不变) ...
      return object if object.nil? || object.is_a?(Numeric) || object.is_a?(TrueClass) || object.is_a?(FalseClass) || object.is_a?(Symbol) || object.is_a?(String)

      return unless object.respond_to?(:object_id)
      oid = object.object_id
      return @visited_clean[oid] if @visited_clean.key?(oid)

      cleaned_object = case object
        when Array
          result = []
          @visited_clean[oid] = result
          object.each { |item| result << clean_for_export(item) }
          result
        when Hash
          result = {}
          @visited_clean[oid] = result
          object.each do |key, value|
            cleaned_key = clean_for_export(key)
            cleaned_value = clean_for_export(value)
            result[cleaned_key] = cleaned_value
          end
          result
        when Table, Color, Tone, Rect
          result = { "json_class" => object.class.name }
          @visited_clean[oid] = result
          object.instance_variables.each do |ivar|
            next if ivar.to_s.start_with?("@_")
            key = ivar.to_s
            value = object.instance_variable_get(ivar)
            result[key] = (object.is_a?(Table) && ivar == :@elements) ? value.to_a : clean_for_export(value)
          end
          result
        else
          class_name_str = object.class.name
          unless class_name_str && !class_name_str.empty?
            puts "[警告] 遇到匿名或未命名类实例，无法导出: #{object.inspect}"
            return nil
          end

          result = { "json_class" => class_name_str }
          @visited_clean[oid] = result

          deprecated_set = DEPRECATED_ATTRIBUTES[@rgss_version][class_name_str] || Set.new
          if @rgss_version == "RGSS2" && object.is_a?(RPG::BaseItem)
            deprecated_set.add(:@features)
          end

          if object.respond_to?(:instance_variables)
            object.instance_variables.sort.each do |ivar|
              ivar_s = ivar.to_s

              next if ivar_s.start_with?("@_")
              next if deprecated_set.include?(ivar)

              # Strict filtering for @features
              if ivar == :@features
                unless object.is_a?(RPG::BaseItem) && @rgss_version != "RGSS2"
                  next # Skip @features
                end
              end

              key = ivar_s
              value = object.instance_variable_get(ivar)
              result[key] = clean_for_export(value)
            end
          end
          result
        end
      cleaned_object
    end
  end # JsonExporter

  # 从 JSON 解析的数据结构恢复 RVData 对象
  class RvdataRestorer
    # ... (RvdataRestorer 代码保持不变) ...
    REDUCED_CLASS_INSTANTIATORS = {
      "RPG::Event" => ->(data, version, restorer) { RPG::Event.new(data["@x"], data["@y"]) },
      "RPG::EventCommand" => ->(data, version, restorer) { RPG::EventCommand.new(data["@code"], data["@indent"], restorer.restore_value(data["@parameters"])) },
      "RPG::MoveCommand" => ->(data, version, restorer) { RPG::MoveCommand.new(data["@code"], restorer.restore_value(data["@parameters"])) },
      "RPG::Map" => ->(data, version, restorer) { RPG::Map.new(data["@width"], data["@height"], version) },
      "Color" => ->(data, version, restorer) { Color.new([data["@red"], data["@green"], data["@blue"], data["@alpha"]]) },
      "Tone" => ->(data, version, restorer) { Tone.new([data["@red"], data["@green"], data["@blue"], data["@gray"]]) },
      "Rect" => ->(data, version, restorer) { Rect.new(data["@x"], data["@y"], data["@width"], data["@height"]) },
      "Table" => ->(data, version, restorer) do
        elements_data = restorer.restore_value(data["@elements"]) || []
        expected_count = data["@num_of_elements"].to_i
        actual_elements = elements_data.flatten.map(&:to_i)
        if actual_elements.size < expected_count
          actual_elements.fill(0, actual_elements.size, expected_count - actual_elements.size)
        elsif actual_elements.size > expected_count && expected_count >= 0
          actual_elements = actual_elements.slice(0, expected_count)
        end
        actual_elements = [] if expected_count == 0
        Table.new([data["@num_of_dimensions"], data["@xsize"], data["@ysize"],
                   data["@zsize"], expected_count, *actual_elements])
      end,
      "RPG::BaseItem::Feature" => ->(data, version, restorer) { RPG::BaseItem::Feature.new(data["@code"], data["@data_id"], data["@value"]) },
      "RPG::UsableItem::Effect" => ->(data, version, restorer) { RPG::UsableItem::Effect.new(data["@code"], data["@data_id"], data["@value1"], data["@value2"]) },
      "RPG::UsableItem::Damage" => ->(data, version, restorer) { RPG::UsableItem::Damage.new },
    }.freeze

    def initialize(rgss_version)
      @rgss_version = rgss_version
      @object_cache = {}
    end

    def restore(data)
      @object_cache.clear
      restore_value(data)
    end

    def restore_value(value)
      case value
      when Array
        restore_array(value)
      when Hash
        if value.key?("json_class") && value.key?("@_object_id") && @object_cache.key?(value["@_object_id"])
          return @object_cache[value["@_object_id"]]
        end
        restore_hash(value)
      else
        value
      end
    end

    private

    def restore_array(array)
      array.map { |item| restore_value(item) }
    end

    def restore_hash(hash)
      if hash.key?("json_class")
        restore_instance(hash)
      elsif hash.key?("__source_file__") && File.basename(hash["__source_file__"], ".json") == "MapInfos"
        hash.except("__source_file__").transform_keys(&:to_i).transform_values { |v| restore_value(v) }
      else
        hash.transform_values { |v| restore_value(v) }
      end
    end

    def restore_instance(data)
      class_name = data["json_class"]
      return data["s"].to_sym if class_name == "Symbol" && data.key?("s")

      klass = find_class(class_name)
      obj = instantiate_object(klass, data)

      if obj && data.key?("@_object_id")
        @object_cache[data["@_object_id"]] = obj
      end

      populate_attributes(obj, data) if obj
      obj
    end

    def find_class(class_name)
      Object.const_get(class_name)
    rescue NameError
      raise NameError, "错误：未找到类 '#{class_name}'。请确保已加载正确的 RGSS 定义。", caller
    end

    def instantiate_object(klass, data)
      if REDUCED_CLASS_INSTANTIATORS.key?(klass.name)
        begin
          return REDUCED_CLASS_INSTANTIATORS[klass.name].call(data, @rgss_version, self)
        rescue => e
          raise "实例化特殊类(注册表) #{klass.name} 时出错: #{e.message}\n原始回溯:\n#{e.backtrace.first(5).join("\n")}"
        end
      else
        generic_instantiate(klass, data)
      end
    end

    def generic_instantiate(klass, data)
      init_method = nil
      begin
        init_method = klass.instance_method(:initialize)
      rescue NameError
        begin
          return klass.new
        rescue ArgumentError => e_new
          raise ArgumentError, "实例化 #{klass.name} (无自定义 initialize) 时出错: #{e_new.message}"
        end
      end

      needs_version = method_needs_version_arg?(init_method)

      begin
        if needs_version
          klass.new(@rgss_version)
        elsif init_method.arity == 0 || init_method.arity == -1
          klass.new
        else
          raise ArgumentError, "类 #{klass.name} 的 initialize 需要 #{init_method.arity} 个参数，但不在注册表中且无法自动处理。"
        end
      rescue ArgumentError => e
        actual_args_desc = needs_version ? "1 argument (#{@rgss_version})" : "0 arguments"
        raise ArgumentError, "实例化通用类 #{klass.name} 时参数不匹配。错误: #{e.message}. " \
                             "尝试调用方式: #{klass.name}.new(#{actual_args_desc}). " \
                             "检查 #{klass.name}#initialize 定义。"
      rescue => e
        raise "实例化通用类 #{klass.name} 时发生未知错误: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    def populate_attributes(obj, data)
      data.each do |key, value|
        next if key == "json_class" || key == "__source_file__" || key == "@_object_id"
        next if key.start_with?("@_")

        ivar_symbol = key.to_sym

        has_ivar = obj.instance_variable_defined?(ivar_symbol)
        setter_method_name = ivar_symbol.to_s[1..-1] + "="
        setter_method = setter_method_name.to_sym
        has_setter = obj.respond_to?(setter_method)

        unless has_ivar || has_setter
          puts "[警告] (恢复) #{obj.class} 既没有实例变量 #{ivar_symbol} 也没有 setter 方法 #{setter_method}。跳过来自 JSON 的属性 '#{key}' (这不应该发生！)。"
          next
        end

        begin
          restored_value = restore_value(value)
          if ivar_symbol == :@events && obj.is_a?(RPG::Map) && restored_value.is_a?(Hash)
            restored_hash = restored_value.transform_keys(&:to_i)
            has_setter ? obj.send(setter_method, restored_hash) : obj.instance_variable_set(ivar_symbol, restored_hash)
          elsif has_setter
            obj.send(setter_method, restored_value)
          elsif has_ivar
            obj.instance_variable_set(ivar_symbol, restored_value)
          end
        rescue TypeError => e
          puts "[警告] (恢复) 为 #{obj.class} 设置属性 #{ivar_symbol} 时 TypeError: #{e.message}。跳过。"
        rescue ArgumentError => e
          puts "[警告] (恢复) 为 #{obj.class} 设置属性 #{ivar_symbol} 时 ArgumentError: #{e.message}。跳过。"
        rescue => e
          puts "[警告] (恢复) 为 #{obj.class} 设置属性 #{ivar_symbol} 时未知错误: #{e.class}: #{e.message}。跳过。"
        end
      end
    end

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
