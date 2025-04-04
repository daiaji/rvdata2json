#!/usr/bin/env ruby
# validate_rgss2_structure.rb - 检查指定目录下 RVData 文件是否符合 RGSS2 结构
# (修正 validate_structure 处理数组/哈希逻辑, 确保正确检查容器内对象的实例变量)
# (增加文件内错误聚合逻辑，减少重复日志)
# (增加规则级别错误聚合总结，进一步减少 Map 等重复日志)
# (优化最终摘要，对 Map 文件进行分组)

require "pp"
require "set"
require "logger"
require "fileutils"
require "pathname"

# --- Configuration ---
MAX_RETRIES = 10
LOG_DIR = "logs"
LOG_FILENAME = "rgss2_validation_#{Time.now.strftime("%Y%m%d_%H%M%S")}.log"
FILES_TO_VALIDATE = [
  "Actors", "Animations", "Armors", "Classes", "CommonEvents",
  "Enemies", "Items", "MapInfos", "Skills", "States", "System",
  "Troops", "Weapons",
  /Map\d{3}/,
].freeze
LOG_LEVEL = Logger::INFO # 可以改为 Logger::DEBUG 查看更详细信息
# 控制是否为每个有问题的 Map 文件打印详细的聚合错误日志 (INFO级别下默认关闭)
LOG_MAP_DETAILS_IF_ERRORS = false

# --- RGSS2 Structure Definition ---
# (保持不变，省略以节省空间)
EXPECTED_RGSS2_STRUCTURES = {
  "RPG::Actor" => Set.new(["@id", "@name", "@class_id", "@initial_level", "@exp_basis", "@exp_inflation", "@character_name", "@character_index", "@face_name", "@face_index", "@parameters", "@weapon_id", "@armor1_id", "@armor2_id", "@armor3_id", "@armor4_id", "@two_swords_style", "@fix_equipment", "@auto_battle", "@super_guard", "@pharmacology", "@critical_bonus"]),
  "RPG::Class" => Set.new(["@id", "@name", "@position", "@weapon_set", "@armor_set", "@element_ranks", "@state_ranks", "@learnings", "@skill_name_valid", "@skill_name"]),
  "RPG::Class::Learning" => Set.new(["@level", "@skill_id"]),
  "RPG::Skill" => Set.new(["@id", "@name", "@icon_index", "@description", "@note", "@scope", "@occasion", "@speed", "@animation_id", "@common_event_id", "@base_damage", "@variance", "@atk_f", "@spi_f", "@physical_attack", "@damage_to_mp", "@absorb_damage", "@ignore_defense", "@element_set", "@plus_state_set", "@minus_state_set", "@mp_cost", "@hit", "@message1", "@message2"]),
  "RPG::Item" => Set.new(["@id", "@name", "@icon_index", "@description", "@note", "@scope", "@occasion", "@speed", "@animation_id", "@common_event_id", "@base_damage", "@variance", "@atk_f", "@spi_f", "@physical_attack", "@damage_to_mp", "@absorb_damage", "@ignore_defense", "@element_set", "@plus_state_set", "@minus_state_set", "@price", "@consumable", "@hp_recovery_rate", "@hp_recovery", "@mp_recovery_rate", "@mp_recovery", "@parameter_type", "@parameter_points"]),
  "RPG::Weapon" => Set.new(["@id", "@name", "@icon_index", "@description", "@note", "@animation_id", "@price", "@hit", "@atk", "@def", "@spi", "@agi", "@two_handed", "@fast_attack", "@dual_attack", "@critical_bonus", "@element_set", "@state_set"]),
  "RPG::Armor" => Set.new(["@id", "@name", "@icon_index", "@description", "@note", "@kind", "@price", "@eva", "@atk", "@def", "@spi", "@agi", "@prevent_critical", "@half_mp_cost", "@double_exp_gain", "@auto_hp_recover", "@element_set", "@state_set"]),
  "RPG::Enemy" => Set.new(["@id", "@name", "@battler_name", "@battler_hue", "@maxhp", "@maxmp", "@atk", "@def", "@spi", "@agi", "@hit", "@eva", "@exp", "@gold", "@drop_item1", "@drop_item2", "@levitate", "@has_critical", "@element_ranks", "@state_ranks", "@actions", "@note"]),
  "RPG::Enemy::DropItem" => Set.new(["@kind", "@item_id", "@weapon_id", "@armor_id", "@denominator"]),
  "RPG::Enemy::Action" => Set.new(["@kind", "@basic", "@skill_id", "@condition_type", "@condition_param1", "@condition_param2", "@rating"]),
  "RPG::Troop" => Set.new(["@id", "@name", "@members", "@pages"]),
  "RPG::Troop::Member" => Set.new(["@enemy_id", "@x", "@y", "@hidden", "@immortal"]),
  "RPG::Troop::Page" => Set.new(["@condition", "@span", "@list"]),
  "RPG::Troop::Page::Condition" => Set.new(["@turn_ending", "@turn_valid", "@enemy_valid", "@actor_valid", "@switch_valid", "@turn_a", "@turn_b", "@enemy_index", "@enemy_hp", "@actor_id", "@actor_hp", "@switch_id"]),
  "RPG::State" => Set.new(["@id", "@name", "@icon_index", "@restriction", "@priority", "@atk_rate", "@def_rate", "@spi_rate", "@agi_rate", "@nonresistance", "@offset_by_opposite", "@slip_damage", "@reduce_hit_ratio", "@battle_only", "@release_by_damage", "@hold_turn", "@auto_release_prob", "@message1", "@message2", "@message3", "@message4", "@element_set", "@state_set", "@note"]),
  "RPG::Animation" => Set.new(["@id", "@name", "@animation1_name", "@animation1_hue", "@animation2_name", "@animation2_hue", "@position", "@frame_max", "@frames", "@timings"]),
  "RPG::Animation::Frame" => Set.new(["@cell_max", "@cell_data"]),
  "RPG::Animation::Timing" => Set.new(["@frame", "@se", "@flash_scope", "@flash_color", "@flash_duration"]),
  "RPG::CommonEvent" => Set.new(["@id", "@name", "@trigger", "@switch_id", "@list"]),
  "RPG::Event" => Set.new(["@id", "@name", "@x", "@y", "@pages"]),
  "RPG::Event::Page" => Set.new(["@condition", "@graphic", "@move_type", "@move_speed", "@move_frequency", "@move_route", "@walk_anime", "@step_anime", "@direction_fix", "@through", "@priority_type", "@trigger", "@list"]),
  "RPG::Event::Page::Condition" => Set.new(["@switch1_valid", "@switch2_valid", "@variable_valid", "@self_switch_valid", "@item_valid", "@actor_valid", "@switch1_id", "@switch2_id", "@variable_id", "@variable_value", "@self_switch_ch", "@item_id", "@actor_id"]),
  "RPG::Event::Page::Graphic" => Set.new(["@tile_id", "@character_name", "@character_index", "@direction", "@pattern"]),
  "RPG::EventCommand" => Set.new(["@code", "@indent", "@parameters"]),
  "RPG::Map" => Set.new(["@width", "@height", "@scroll_type", "@autoplay_bgm", "@bgm", "@autoplay_bgs", "@bgs", "@disable_dashing", "@encounter_list", "@encounter_step", "@parallax_name", "@parallax_loop_x", "@parallax_loop_y", "@parallax_sx", "@parallax_sy", "@parallax_show", "@data", "@events"]),
  "RPG::MapInfo" => Set.new(["@name", "@parent_id", "@order", "@expanded", "@scroll_x", "@scroll_y"]),
  "RPG::MoveRoute" => Set.new(["@repeat", "@skippable", "@wait", "@list"]),
  "RPG::MoveCommand" => Set.new(["@code", "@parameters"]),
  "RPG::System" => Set.new(["@game_title", "@version_id", "@magic_number", "@party_members", "@elements", "@switches", "@variables", "@passages", "@boat", "@ship", "@airship", "@title_bgm", "@battle_bgm", "@battle_end_me", "@gameover_me", "@sounds", "@test_battlers", "@test_troop_id", "@start_map_id", "@start_x", "@start_y", "@terms", "@battler_name", "@battler_hue", "@edit_map_id"]),
  "RPG::System::Vehicle" => Set.new(["@character_name", "@character_index", "@bgm", "@start_map_id", "@start_x", "@start_y"]),
  "RPG::System::Terms" => Set.new(["@level", "@level_a", "@hp", "@hp_a", "@mp", "@mp_a", "@atk", "@def", "@spi", "@agi", "@weapon", "@armor1", "@armor2", "@armor3", "@armor4", "@weapon1", "@weapon2", "@attack", "@skill", "@guard", "@item", "@equip", "@status", "@save", "@game_end", "@fight", "@escape", "@new_game", "@continue", "@shutdown", "@to_title", "@cancel", "@gold"]),
  "RPG::System::TestBattler" => Set.new(["@actor_id", "@level", "@weapon_id", "@armor1_id", "@armor2_id", "@armor3_id", "@armor4_id"]),
  "RPG::AudioFile" => Set.new(["@name", "@volume", "@pitch"]),
  "RPG::BGM" => Set.new(["@name", "@volume", "@pitch"]),
  "RPG::BGS" => Set.new(["@name", "@volume", "@pitch"]),
  "RPG::ME" => Set.new(["@name", "@volume", "@pitch"]),
  "RPG::SE" => Set.new(["@name", "@volume", "@pitch"]),
  "Rect" => Set.new(["@x", "@y", "@width", "@height"]),
  "Tone" => Set.new(["@red", "@green", "@blue", "@gray"]),
  "Color" => Set.new(["@red", "@green", "@blue", "@alpha"]),
  "Table" => Set.new(["@dims", "@xsize", "@ysize", "@zsize", "@data"]),
}.freeze

# --- Specific Ignorable Missing Ivars ---
# (保持不变，省略以节省空间)
IGNORABLE_MISSING_IVARS_BY_CLASS = {
  "Table" => Set.new(["@data", "@dims", "@xsize", "@ysize", "@zsize"]),
  "Color" => Set.new(["@red", "@green", "@blue", "@alpha"]),
  "Tone" => Set.new(["@red", "@green", "@blue", "@gray"]),
  "Rect" => Set.new(["@x", "@y", "@width", "@height"]),
}.freeze

# --- Global Variables ---
# (保持不变)
$defined_placeholder_classes = Set.new
$logger = nil
$log_file_handle = nil
$validation_errors_found_global_flag = false
$error_file_basenames = Set.new
$log_file_path = nil

# --- Define a simple structure for validation errors ---
# (保持不变)
ValidationError = Struct.new(:type, :path, :class_name, :details, :filename)

# --- Logger Setup ---
# (保持不变)
def setup_logger
  begin
    log_dir_path = Pathname.new(LOG_DIR)
    log_dir_path.mkpath unless log_dir_path.directory?
    $log_file_path = log_dir_path.join(LOG_FILENAME)
    $log_file_handle = File.open($log_file_path, "w")
    $log_file_handle.set_encoding("UTF-8")
    $logger = Logger.new($log_file_handle)
    $logger.level = LOG_LEVEL
    $logger.formatter = proc do |severity, datetime, progname, msg|
      formatted_msg = begin
                        msg.is_a?(String) ? msg.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?") : msg.to_s
                      rescue => e
                        "[Logging Encoding Error: #{e.message}] #{msg.inspect rescue 'Uninspectable Object'}"
                      end
      "#{datetime.strftime("%Y-%m-%d %H:%M:%S")} [#{severity}] #{formatted_msg}\n"
    end
    $stdout.set_encoding("UTF-8")
    puts "日志文件已创建: #{$log_file_path.expand_path}"
    $logger.info("--- RGSS2 结构验证脚本开始 ---")
    $logger.info("日志时间: #{Time.now}")
    $logger.info("日志级别设置为: #{Logger::SEV_LABEL[LOG_LEVEL]}")
  rescue => e
    STDERR.set_encoding("UTF-8") rescue nil
    STDERR.puts "[致命错误] 无法设置或写入日志文件 '#{$log_file_path || LOG_FILENAME}': #{e.message}"
    STDERR.puts e.backtrace.first(5).join("\n")
    exit(1)
  end
end

at_exit do
  if $log_file_handle && !$log_file_handle.closed?
    $logger&.info("--- RGSS2 结构验证脚本结束 ---")
    $log_file_handle.close
  end
end

# --- Placeholder Definition ---
# (保持不变，省略以节省空间)
def define_strict_placeholder(full_name)
  unless EXPECTED_RGSS2_STRUCTURES.key?(full_name) || ["Table", "Color", "Tone", "Rect"].include?(full_name)
    $logger.error("错误: Marshal 数据请求未知的类/模块 '#{full_name}'，这不符合 RGSS2 结构。")
    return false
  end
  return true if $defined_placeholder_classes.include?(full_name)
  parts = full_name.split("::")
  current_scope = Object
  defined_path_parts = []
  parts.each_with_index do |part, index|
    const_sym = part.to_sym; is_last_part = (index == parts.size - 1); current_path_str = (defined_path_parts + [part]).join("::")
    begin
      if current_scope.const_defined?(const_sym, false)
        entity = current_scope.const_get(const_sym)
        is_our_placeholder = entity.is_a?(Class) && entity.instance_variable_defined?(:@_placeholder_name) && entity.instance_variable_get(:@_placeholder_name) == current_path_str
        is_module_or_class = entity.is_a?(Module)
        unless is_our_placeholder || is_module_or_class
          $logger.warn("警告: '#{current_path_str}' 已存在但不是模块/类 (#{entity.class})，尝试覆盖为占位符...")
          parent_scope_for_set = defined_path_parts.empty? ? Object : Object.const_get(defined_path_parts.join("::"))
          entity = create_minimal_placeholder(parent_scope_for_set, const_sym, current_path_str, is_last_part)
          return false unless entity
        end
        current_scope = entity
      else
        parent_scope_for_set = defined_path_parts.empty? ? Object : Object.const_get(defined_path_parts.join("::"))
        current_scope = create_minimal_placeholder(parent_scope_for_set, const_sym, current_path_str, is_last_part)
        return false unless current_scope
      end
      defined_path_parts << part
    rescue NameError, TypeError => e
      $logger.error("定义占位符 '#{current_path_str}' 时出错: #{e.message}")
      begin
        parent_scope_for_set = defined_path_parts.empty? ? Object : Object.const_get(defined_path_parts.join("::"))
        current_scope = create_minimal_placeholder(parent_scope_for_set, const_sym, current_path_str, is_last_part)
        return false unless current_scope
        defined_path_parts << part
      rescue => inner_e
        $logger.error("为 '#{current_path_str}' 创建占位符的恢复尝试失败: #{inner_e.message}")
        return false
      end
    rescue => e
      $logger.error("定义占位符 '#{current_path_str}' 时发生意外错误: #{e.class}: #{e.message}")
      $logger.error(e.backtrace.first(5).join("\n"))
      return false
    end
  end
  $defined_placeholder_classes.add(full_name)
  return true
end

def create_minimal_placeholder(parent_scope, const_sym, full_name, is_class)
  unless $defined_placeholder_classes.include?(full_name)
    $logger.debug("动态定义: 为预期的 RGSS2 实体创建占位符: #{full_name}")
  end
  new_entity = nil
  if parent_scope.const_defined?(const_sym, false)
    existing = parent_scope.const_get(const_sym)
    is_our_placeholder = existing.is_a?(Class) && existing.instance_variable_defined?(:@_placeholder_name) && existing.instance_variable_get(:@_placeholder_name) == full_name
    return existing if is_our_placeholder
    return existing if !is_class && existing.is_a?(Module)
  end
  begin
    klass_name_for_methods = full_name
    if is_class
      new_entity = Class.new do
        @_placeholder_name = klass_name_for_methods
        def self._load(data); allocate; end
        def initialize(*_args); @_placeholder_name = self.class.instance_variable_get(:@_placeholder_name) rescue "UnknownPlaceholder"; end
        def inspect
          ivars_str = instance_variables.reject { |v| v == :@_placeholder_name }.map { |ivar|
            begin; value_inspect = instance_variable_get(ivar).inspect; value_inspect = value_inspect[0, 80] + "..." if value_inspect.length > 80; rescue => e; value_inspect = "[Inspect Error: #{e.message}]"; end; "#{ivar}=#{value_inspect}"
          }.join(", "); "<Placeholder(#{klass_name_for_methods}) #{ivars_str}>"
        end
        define_singleton_method(:name) { klass_name_for_methods }; define_singleton_method(:to_s) { klass_name_for_methods }
      end
    else
      new_entity = Module.new do; define_singleton_method(:name) { klass_name_for_methods }; define_singleton_method(:to_s) { klass_name_for_methods }; end
    end
    parent_scope.send(:remove_const, const_sym) if parent_scope.const_defined?(const_sym, false)
    parent_scope.const_set(const_sym, new_entity)
    return new_entity
  rescue => e; $logger.error("创建或设置占位符 '#{full_name}' 时失败: #{e.class}: #{e.message}"); return nil; end
end


# --- Function to load a single RVData file ---
# (保持不变，省略以节省空间)
def load_rvdata_for_validation(filepath, log_details: true)
  $logger.info("--- 开始加载 Marshal 文件进行验证: #{filepath} ---") if log_details || $logger.debug?
  loaded_data = nil; retries = 0; failed_strict_defines = Set.new
  loop do
    begin; file_content = File.binread(filepath); loaded_data = Marshal.load(file_content); $logger.info("Marshal.load 完成: #{filepath}") if log_details || $logger.debug?; break
    rescue ArgumentError => e
      match_data = e.message.match(/undefined class\/module (\S+)/)
      if match_data && retries < MAX_RETRIES
        original_request_name = match_data[1]; undefined_entity_name = original_request_name; undefined_entity_name = "RPG" if undefined_entity_name == "RPG::"; is_rpg_module_itself = (undefined_entity_name == "RPG"); is_rpg_related = undefined_entity_name.start_with?("RPG::") || is_rpg_module_itself; is_expected_entity = EXPECTED_RGSS2_STRUCTURES.key?(undefined_entity_name) || ["Table", "Color", "Tone", "Rect"].include?(undefined_entity_name) || is_rpg_module_itself
        if is_expected_entity
          $logger.warn("尝试定义: 遇到预期但未定义的 RGSS2 实体: #{original_request_name} (文件: #{File.basename(filepath)}, 尝试次数 #{retries + 1}/#{MAX_RETRIES})")
          if is_rpg_related && !Object.const_defined?(:RPG); $logger.info("依赖检查: 定义 RPG 模块 (请求者: #{original_request_name} in #{File.basename(filepath)})..."); unless create_minimal_placeholder(Object, :RPG, "RPG", false); $logger.error("致命错误: 无法创建基础 RPG 模块，停止加载 #{File.basename(filepath)}。"); $validation_errors_found_global_flag = true; return nil; end; $defined_placeholder_classes.add("RPG"); end
          unless is_rpg_module_itself; if failed_strict_defines.include?(undefined_entity_name); $logger.error("错误: 之前尝试严格定义 #{undefined_entity_name} 失败，无法继续加载 #{File.basename(filepath)}。"); $validation_errors_found_global_flag = true; return nil; end; unless define_strict_placeholder(undefined_entity_name); $logger.error("无法定义预期的占位符 #{undefined_entity_name}，停止加载 #{File.basename(filepath)}."); failed_strict_defines.add(undefined_entity_name); $validation_errors_found_global_flag = true; return nil; end
          else; $logger.debug("跳过对基础模块 '#{undefined_entity_name}' 的严格占位符定义 (已处理)") if $logger.debug?; end; retries += 1; next
        else; $logger.error("验证错误 (#{File.basename(filepath)}): Marshal 数据需要一个非 RGSS2 标准的类/模块: '#{original_request_name}'"); $validation_errors_found_global_flag = true; return nil; end
      else
        error_source = match_data ? "'#{match_data[1]}'" : "未知实体"; reason = e.message; $logger.error("Marshal.load 失败 (#{File.basename(filepath)})。原因: #{reason}"); if match_data && retries >= MAX_RETRIES; $logger.error("已达到最大重试次数 (#{MAX_RETRIES})，仍无法加载所需的实体 #{error_source} in #{File.basename(filepath)}"); elsif reason.include?("marshal data too short") || reason.include?("invalid marshal format") || reason.include?("incompatible marshal file format"); $logger.error("提示：文件 #{File.basename(filepath)} 可能已损坏或与当前 Ruby Marshal 版本不兼容。"); end; $validation_errors_found_global_flag = true; return nil; end
    rescue TypeError, EncodingError => e; $logger.error("Marshal.load 时发生 #{e.class} (#{File.basename(filepath)}): #{e.message}"); $validation_errors_found_global_flag = true; return nil
    rescue => e; $logger.error("读取或解析 Marshal 文件 #{File.basename(filepath)} 时发生未知错误: #{e.class}: #{e.message}"); $logger.error(e.backtrace.first(5).join("\n")); $validation_errors_found_global_flag = true; return nil; end
  end; loaded_data
end

# --- Recursive Structure Validation ---
# (保持不变)
def validate_structure(path, obj, validation_results, log_path: "root", filename: "UnknownFile")
  return true if obj.nil? || obj.is_a?(Symbol) || obj.is_a?(Numeric) || obj.is_a?(TrueClass) || obj.is_a?(FalseClass) || obj.is_a?(String)
  if obj.is_a?(Array)
    all_valid = true; obj.each_with_index { |item, i| is_item_valid = validate_structure("#{path}[#{i}]", item, validation_results, log_path: "#{log_path}[#{i}]", filename: filename); all_valid &&= is_item_valid }; return all_valid
  elsif obj.is_a?(Hash)
    all_valid = true; obj.each { |key, value| key_repr = key.inspect rescue "[Bad Key]"; is_value_valid = validate_structure("#{path}[#{key_repr}]", value, validation_results, log_path: "#{log_path}[#{key_repr}]", filename: filename); all_valid &&= is_value_valid }; return all_valid
  end
  obj_class = obj.class; class_name = obj_class.name rescue nil; class_is_defined = false; begin; class_is_defined = Object.const_defined?(class_name) if class_name && !class_name.empty?; rescue NameError; class_is_defined = false; end
  if class_name.nil? || class_name.empty? || !class_is_defined; intended_name = obj.instance_variable_get(:@_placeholder_name) if obj.respond_to?(:instance_variable_defined?) && obj.instance_variable_defined?(:@_placeholder_name); class_name = intended_name if intended_name && !intended_name.empty?; end
  unless class_name && !class_name.empty?; error_details = "无法确定类名的对象: #{obj.inspect[0..200]}"; validation_results << ValidationError.new(:unknown_class, log_path, nil, error_details, filename); $validation_errors_found_global_flag = true; $error_file_basenames.add(filename); return false; end
  expected_ivars = EXPECTED_RGSS2_STRUCTURES[class_name]
  unless expected_ivars; error_details = "发现意外的类: #{class_name}"; validation_results << ValidationError.new(:unexpected_class, log_path, class_name, error_details, filename); $validation_errors_found_global_flag = true; $error_file_basenames.add(filename); return false; end
  structure_valid = true
  begin; actual_ivars = obj.instance_variables.map(&:to_s).to_set; actual_ivars.delete("@_placeholder_name")
  rescue => e; error_details = "检查对象 (#{class_name}) 的实例变量时出错: #{e.message}"; validation_results << ValidationError.new(:ivar_check_error, log_path, class_name, error_details, filename); $logger.error("CRITICAL (文件 '#{filename}.rvdata', 路径 '#{log_path}'): #{error_details}"); $validation_errors_found_global_flag = true; $error_file_basenames.add(filename); return false; end
  unexpected_ivars = actual_ivars - expected_ivars
  if unexpected_ivars.any?; ivar_list = unexpected_ivars.to_a.sort; validation_results << ValidationError.new(:unexpected_ivar, log_path, class_name, ivar_list, filename); structure_valid = false; $validation_errors_found_global_flag = true; $error_file_basenames.add(filename); end
  missing_ivars = expected_ivars - actual_ivars
  if missing_ivars.any?
    ignorable_missing_for_this_class = IGNORABLE_MISSING_IVARS_BY_CLASS[class_name] || Set.new; problematic_missing = missing_ivars - ignorable_missing_for_this_class
    if problematic_missing.any?; ivar_list = problematic_missing.to_a.sort; validation_results << ValidationError.new(:missing_ivar, log_path, class_name, ivar_list, filename); structure_valid = false; $validation_errors_found_global_flag = true; $error_file_basenames.add(filename);
    elsif missing_ivars.any? && $logger.debug?; $logger.debug("DEBUG (文件 '#{filename}.rvdata', 路径 '#{log_path}'): 对象 (#{class_name}) 跳过“缺少实例变量”检查 (均为可忽略): #{missing_ivars.to_a.sort.join(", ")}"); end
  end
  ivars_to_check_recursively = actual_ivars & expected_ivars
  ivars_to_check_recursively.each do |ivar_name|
    ivar_sym = ivar_name.to_sym
    begin; value = obj.instance_variable_get(ivar_sym); is_value_valid = validate_structure(ivar_name, value, validation_results, log_path: "#{log_path}.#{ivar_name.sub(/^@/, "")}", filename: filename); structure_valid &&= is_value_valid
    rescue => e; error_details = "获取或验证对象 (#{class_name}) 的实例变量 #{ivar_name} 值时出错: #{e.message}"; validation_results << ValidationError.new(:get_ivar_error, log_path, class_name, error_details, filename); $logger.error("CRITICAL (文件 '#{filename}.rvdata', 路径 '#{log_path}'): #{error_details}"); structure_valid = false; $validation_errors_found_global_flag = true; $error_file_basenames.add(filename); end
  end; return structure_valid
end

# --- Helper to format aggregated error message ---
def format_aggregated_error(key, agg_data)
  type, class_name, details_str = key
  count = agg_data[:count]
  first_path = agg_data[:first_path]
  details_display = details_str.split(',').join(', ') # For display

  message_base = case type
                 when :missing_ivar then "缺少预期实例变量: #{details_display}"
                 when :unexpected_ivar then "发现意外实例变量: #{details_display}"
                 when :unexpected_class then details_str # Already contains "发现意外的类: ClassName"
                 when :unknown_class then details_str # Already contains "无法确定类名..."
                 when :ivar_check_error, :get_ivar_error then "处理时发生错误: #{details_str}"
                 else "发生未知类型 (#{type}) 错误: #{details_str}"
                 end

  context = "在类 (#{class_name})" unless class_name == "N/A"
  location = "首次出现在路径 '#{first_path}'"

  if count > 1
    "#{location} #{context}: #{message_base} (共计 #{count} 次)"
  else
    "#{location} #{context}: #{message_base}"
  end
end


# --- Main Program Logic ---
if ARGV.length != 1
  STDERR.set_encoding("UTF-8") rescue nil
  STDERR.puts "用法: ruby validate_rgss2_structure.rb <要验证的目录路径>"
  STDERR.puts "       检查该目录下匹配规则的 .rvdata 文件是否符合 RGSS2 结构。"
  STDERR.puts "       详细日志和错误将写入 #{LOG_DIR}/rgss2_validation_YYYYMMDD_HHMMSS.log 格式的文件中。"
  exit 1
end

target_dir = Pathname.new(ARGV[0])
unless target_dir.directory?
  STDERR.set_encoding("UTF-8") rescue nil
  STDERR.puts "错误: 目录未找到或不是一个目录 - #{target_dir}"
  exit 1
end

setup_logger # Sets up $logger
$logger.info("开始验证目录: #{target_dir.expand_path}")
$logger.info("验证规则: #{FILES_TO_VALIDATE.inspect}")
$logger.info("将忽略以下类中特定缺失的实例变量 (因占位符加载限制):")
IGNORABLE_MISSING_IVARS_BY_CLASS.each { |k, v| $logger.info("  - #{k}: #{v.to_a.sort.join(", ")}") }
$logger.info("=======================================")

validation_performed_count = 0
global_rule_error_summary = Hash.new { |h, k| h[k] = { error_files: Set.new, common_errors: Hash.new(0) } }

FILES_TO_VALIDATE.each do |rule|
  $logger.info("\n--- 处理规则: #{rule.inspect} ---")

  files_to_process = []
  is_regex_rule = rule.is_a?(Regexp)
  regex_processed_count = 0
  regex_error_count = 0
  # Store aggregated errors specific to this rule's execution run
  rule_run_aggregated_errors = Hash.new { |h, k| h[k] = { count: 0, files: Set.new } }

  # --- File Collection ---
  if rule.is_a?(String)
    file_path = target_dir.join("#{rule}.rvdata")
    if file_path.file?; files_to_process << { base: rule, path: file_path, source_rule: rule }
    else; $logger.info("[信息] 未找到固定文件: #{file_path.basename}"); end
  elsif is_regex_rule
    begin
      found_files = Dir.entries(target_dir).select { |e| e.end_with?(".rvdata") && rule.match?(e.chomp(".rvdata")) && target_dir.join(e).file? }
      if found_files.empty?; $logger.info("[信息] 未找到匹配模式 #{rule.inspect} 的 .rvdata 文件。")
      else; found_files.sort.each { |fname| base = fname.chomp(".rvdata"); files_to_process << { base: base, path: target_dir.join(fname), source_rule: rule } }; end
    rescue Errno::ENOENT => e; $logger.error("访问目录 '#{target_dir}' 时出错: #{e.message}"); next
    rescue => e; $logger.error("处理规则 #{rule.inspect} 查找文件时发生错误: #{e.class}: #{e.message}"); next
    end
  else
    $logger.warn("[警告] 未知的验证规则类型: #{rule.inspect}。已跳过。"); next
  end

  next if files_to_process.empty?

  # --- Process Files ---
  files_to_process.each do |file_info|
    base_name = file_info[:base]
    file_path = file_info[:path]
    validation_performed_count += 1
    file_had_issues = false # Tracks if *any* issue (load or structure) occurred for this file

    # Determine if detailed logging should happen for this specific file
    # For regex rules, only log details if LOG_MAP_DETAILS_IF_ERRORS is true or log level is DEBUG
    log_details_this_file = if is_regex_rule
                              $logger.debug? || LOG_MAP_DETAILS_IF_ERRORS
                            else
                              true # Always log details for non-regex files unless level is higher than INFO
                            end

    $logger.info("[开始验证] #{base_name}.rvdata #{is_regex_rule ? "(匹配模式 " + rule.inspect + ")" : ""}") if log_details_this_file

    # --- Load Data ---
    data = load_rvdata_for_validation(file_path.to_s, log_details: log_details_this_file)

    if data.nil?
      file_had_issues = true
      $error_file_basenames.add(base_name) # Ensure marked if load failed
      global_rule_error_summary[rule][:error_files].add(base_name) # Track for rule summary
    else
      # --- Structure Validation ---
      current_file_errors_structured = []
      validate_structure("root", data, current_file_errors_structured, log_path: "root", filename: base_name)

      # --- Aggregation and Logging Step (File Level) ---
      if current_file_errors_structured.any?
        file_had_issues = true # Mark file as having issues
        $error_file_basenames.add(base_name) # Ensure marked if structure errors found
        global_rule_error_summary[rule][:error_files].add(base_name) # Track for rule summary

        aggregated_errors_this_file = Hash.new { |h, k| h[k] = { count: 0, first_path: nil } }
        current_file_errors_structured.each do |error|
          details_key = case error.details
                        when Array then error.details.sort.join(',')
                        when Set then error.details.to_a.sort.join(',')
                        else error.details.to_s
                        end
          key = [error.type, error.class_name || "N/A", details_key]
          agg = aggregated_errors_this_file[key]
          agg[:count] += 1
          agg[:first_path] ||= error.path

          # Store for rule-level aggregation as well
          if is_regex_rule
              rule_agg = rule_run_aggregated_errors[key]
              rule_agg[:count] += 1 # This counts occurrences across all files for this rule run
              rule_agg[:files].add(base_name)
              global_rule_error_summary[rule][:common_errors][key] += 1 # Track common errors globally per rule
          end
        end

        # Log the aggregated errors *for this file* only if detailed logging is enabled
        if log_details_this_file
            $logger.warn("[验证发现结构问题] #{base_name}.rvdata:")
            aggregated_errors_this_file.each do |key, agg_data|
                $logger.warn("  - #{format_aggregated_error(key, agg_data)}")
            end
        end
      end # end if current_file_errors_structured.any?
    end # end if data.nil? else ...

    # --- Update Regex Stats ---
    if is_regex_rule
      regex_processed_count += 1
      regex_error_count += 1 if file_had_issues
    elsif file_had_issues # Non-regex file with issues
         # Log general issue warning if not logged in detail above
         unless log_details_this_file
             $logger.warn("[验证发现问题] #{base_name}.rvdata (详情请调高日志级别或检查日志文件)")
         else
             # If details were logged, maybe a less severe final note?
             # Or rely on the logged WARN messages above. Let's keep it simple.
             # We already log the WARN header if log_details_this_file is true.
         end
    elsif log_details_this_file # Non-regex, no issues, detailed log enabled
         $logger.info("[验证成功] #{base_name}.rvdata: 未发现需关注的问题。")
    end

  end # end files_to_process.each

  # --- Regex Rule Summary (Improved) ---
  if is_regex_rule && regex_processed_count > 0
    regex_success_count = regex_processed_count - regex_error_count
    $logger.info("[规则总结] 模式 #{rule.inspect}:")
    $logger.info("  共检查 #{regex_processed_count} 个匹配文件。")
    $logger.info("  成功 (未发现问题): #{regex_success_count} 个。")
    if regex_error_count > 0
      $logger.warn("  发现问题 (加载或结构): #{regex_error_count} 个。")

      # Find the most frequent aggregated error *signature* across the files processed by this rule run
      most_frequent_error_key = rule_run_aggregated_errors.keys.max_by do |key|
          # We want the error signature that appeared in the most *files*
          rule_run_aggregated_errors[key][:files].size
      end

      if most_frequent_error_key
          data = rule_run_aggregated_errors[most_frequent_error_key]
          num_files_with_error = data[:files].size
          # Only report if it's common among the error files
          if num_files_with_error > 1 && num_files_with_error >= (regex_error_count * 0.5).ceil # Heuristic: common if in >= 50% of error files
               dummy_agg_data_for_format = { count: data[:count], first_path: "..." } # Need path for format, but it's rule level
               formatted_msg = format_aggregated_error(most_frequent_error_key, dummy_agg_data_for_format)
               # Adapt message for rule level
               common_issue_desc = formatted_msg.split(":", 2).last.strip.sub(/\(共计 \d+ 次\)$/, '').strip
               $logger.warn("    最常见问题: 在 #{num_files_with_error} 个文件中发现 -> #{common_issue_desc}")
          end
      end
      # Add note about where to find details if they were suppressed
      unless LOG_MAP_DETAILS_IF_ERRORS || $logger.debug?
          $logger.warn("    (设 LOG_MAP_DETAILS_IF_ERRORS = true 或 日志级别为 DEBUG 查看各文件详情)")
      end
    end
  end

end # end FILES_TO_VALIDATE.each

# --- Final Summary (Improved Grouping) ---
$logger.info("\n=======================================")
$logger.info("--- 验证完成 ---")

final_message_lines = []
exit_code = 0

if validation_performed_count == 0
  final_message_lines << "未执行任何文件验证（可能没有找到匹配的文件）。"
  exit_code = 0 # No files found isn't an error state
else
  final_message_lines << "验证完成。"
  final_message_lines << "总共检查文件数: #{validation_performed_count}"
  actual_error_file_count = $error_file_basenames.size

  if actual_error_file_count > 0
    final_message_lines << "发现问题的文件 (#{actual_error_file_count}):"

    # Group files by pattern (simple approach: check for MapXXX)
    map_files = $error_file_basenames.select { |name| name.match?(/^Map\d{3}$/) }.sort
    other_files = $error_file_basenames.reject { |name| name.match?(/^Map\d{3}$/) }.sort

    # Find the Map rule if it exists
    map_rule = FILES_TO_VALIDATE.find { |r| r.is_a?(Regexp) && r.source == 'Map\d{3}' }

    if map_files.any?
      line = "  - MapXXX.rvdata (#{map_files.size} 个文件)"
      # Try to add common issue from global summary
      if map_rule && global_rule_error_summary.key?(map_rule) && global_rule_error_summary[map_rule][:common_errors].any?
         most_common_key = global_rule_error_summary[map_rule][:common_errors].max_by { |k, v| v }[0]
         if most_common_key
             type, class_name, details_str = most_common_key
             details_display = details_str.split(',').join(', ')
             common_desc = case type
                            when :missing_ivar then "缺少 #{details_display}"
                            when :unexpected_ivar then "意外 #{details_display}"
                            else "类型 #{type} 问题"
                            end
             line += " (常见于类 #{class_name}: #{common_desc})"
         end
      end
      final_message_lines << line
    end

    other_files.each do |basename|
      final_message_lines << "  - #{basename}.rvdata"
    end

    final_message_lines << "详细信息请查看日志文件: #{$log_file_path.expand_path}"
    exit_code = 1 # Exit with error code if any file had issues
  else
    final_message_lines << "在检查的所有 #{validation_performed_count} 个文件中未发现需要关注的问题。"
    final_message_lines << "(注意: 对于 Table, Color, Tone, Rect 类, 由于占位符加载机制限制, 未检查其特定内部变量是否存在。)"
    exit_code = 0
  end
end

final_message = final_message_lines.join("\n")
$logger.info("\n" + final_message)
puts "\n" + final_message # Also print summary to console

exit(exit_code)