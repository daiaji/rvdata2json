#!/usr/bin/env ruby
# validate_rgss3_structure.rb - 检查指定目录下 RVData2 文件是否符合 RGSS3 (VX Ace) 结构
# (基于 validate_rgss2_structure.rb 修改)
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
MAX_RETRIES = 50 # Increased from RGSS2 script, VX Ace can have more complex objects
LOG_DIR = "logs"
LOG_FILENAME = "rgss3_validation_#{Time.now.strftime("%Y%m%d_%H%M%S")}.log"
# Standard VX Ace data files + Map pattern
FILES_TO_VALIDATE = [
  "Actors", "Animations", "Armors", "Classes", "CommonEvents",
  "Enemies", "Items", "MapInfos", "Skills", "States", "System",
  "Tilesets", "Troops", "Weapons",
  /Map\d{3}/,
].freeze
LOG_LEVEL = Logger::INFO # 可以改为 Logger::DEBUG 查看更详细信息
# 控制是否为每个有问题的 Map 文件打印详细的聚合错误日志 (INFO级别下默认关闭)
LOG_MAP_DETAILS_IF_ERRORS = true

# --- RGSS3 (VX Ace) Structure Definition ---
# Based on rmvxace_db.rb and common_db.rb
# *** CORRECTED FOR INHERITANCE ***
EXPECTED_RGSS3_STRUCTURES = {}.tap do |h|
  # --- Define Base Classes First ---
  h["RPG::BaseItem"] = Set.new([
    "@id", "@name", "@icon_index", "@description", "@features", "@note"
  ])
  h["RPG::UsableItem"] = h["RPG::BaseItem"] | Set.new([ # Inherits BaseItem
    "@scope", "@occasion", "@speed", "@success_rate", "@repeats", "@tp_gain",
    "@hit_type", "@animation_id", "@damage", "@effects"
  ])
  h["RPG::EquipItem"] = h["RPG::BaseItem"] | Set.new([ # Inherits BaseItem
    "@price", "@etype_id", "@params"
  ])

  # --- Define Subclasses, Merging Parent's IVars ---
  h["RPG::Actor"] = h["RPG::BaseItem"] | Set.new([ # Inherits BaseItem
    "@nickname", "@class_id", "@initial_level", "@max_level", "@character_name",
    "@character_index", "@face_name", "@face_index", "@equips"
    # Note: description, features, note, icon_index, id, name are from BaseItem
  ])
  h["RPG::Class"] = h["RPG::BaseItem"] | Set.new([ # Inherits BaseItem
     "@exp_params", "@params", "@learnings"
    # Note: description, features, note, icon_index, id, name are from BaseItem
  ])
  h["RPG::Class::Learning"] = Set.new(["@level", "@skill_id", "@note"]) # No inheritance

  h["RPG::Skill"] = h["RPG::UsableItem"] | Set.new([ # Inherits UsableItem
    "@stype_id", "@mp_cost", "@tp_cost", "@message1", "@message2",
    "@required_wtype_id1", "@required_wtype_id2"
    # Note: inherits all from UsableItem, which includes BaseItem
  ])
  h["RPG::Item"] = h["RPG::UsableItem"] | Set.new([ # Inherits UsableItem
    "@itype_id", "@price", "@consumable"
    # Note: inherits all from UsableItem, which includes BaseItem
  ])
  h["RPG::Weapon"] = h["RPG::EquipItem"] | Set.new([ # Inherits EquipItem
    "@wtype_id", "@animation_id"
    # Note: inherits all from EquipItem, which includes BaseItem
  ])
  h["RPG::Armor"] = h["RPG::EquipItem"] | Set.new([ # Inherits EquipItem
    "@atype_id"
    # Note: inherits all from EquipItem, which includes BaseItem
  ])
  h["RPG::Enemy"] = h["RPG::BaseItem"] | Set.new([ # Inherits BaseItem
    "@battler_name", "@battler_hue", "@params", "@exp", "@gold", "@drop_items",
    "@actions"
    # Note: description, features, note, icon_index, id, name are from BaseItem
  ])
  h["RPG::Enemy::DropItem"] = Set.new(["@kind", "@data_id", "@denominator"]) # No inheritance
  h["RPG::Enemy::Action"] = Set.new([
    "@skill_id", "@condition_type", "@condition_param1", "@condition_param2", "@rating"
  ]) # No inheritance

  h["RPG::State"] = h["RPG::BaseItem"] | Set.new([ # Inherits BaseItem
    "@restriction", "@priority", "@remove_at_battle_end", "@remove_by_restriction",
    "@auto_removal_timing", "@min_turns", "@max_turns", "@remove_by_damage",
    "@chance_by_damage", "@remove_by_walking", "@steps_to_remove", "@message1",
    "@message2", "@message3", "@message4"
    # Note: description, features, note, icon_index, id, name are from BaseItem
  ])

  # --- Other Classes (No complex inheritance relevant here) ---
  # 替换 RPG::Map 的定义
  h["RPG::Map"] = Set.new([
    "@display_name", "@tileset_id", "@width", "@height", "@scroll_type",
    "@specify_battleback",
    "@battleback1_name", "@battleback2_name",
    "@autoplay_bgm", "@bgm", "@autoplay_bgs", "@bgs", "@disable_dashing",
    "@encounter_list", "@encounter_step", "@parallax_name", "@parallax_loop_x",
    "@parallax_loop_y", "@parallax_sx", "@parallax_sy", "@parallax_show",
    "@note", "@data", "@events"
  ])
  h["RPG::Map::Encounter"] = Set.new(["@troop_id", "@weight", "@region_set"])
  h["RPG::MapInfo"] = Set.new([
    "@name", "@parent_id", "@order", "@expanded", "@scroll_x", "@scroll_y"
  ])
  h["RPG::Event"] = Set.new(["@id", "@name", "@x", "@y", "@pages"])
  h["RPG::Event::Page"] = Set.new([
    "@condition", "@graphic", "@move_type", "@move_speed", "@move_frequency",
    "@move_route", "@walk_anime", "@step_anime", "@direction_fix", "@through",
    "@priority_type", "@trigger", "@list"
  ])
  h["RPG::Event::Page::Condition"] = Set.new([
    "@switch1_valid", "@switch2_valid", "@variable_valid", "@self_switch_valid",
    "@item_valid", "@actor_valid", "@switch1_id", "@switch2_id", "@variable_id",
    "@variable_value", "@self_switch_ch", "@item_id", "@actor_id"
  ])
  h["RPG::Event::Page::Graphic"] = Set.new([
    "@tile_id", "@character_name", "@character_index", "@direction", "@pattern"
  ])
  h["RPG::EventCommand"] = Set.new(["@code", "@indent", "@parameters"])
  h["RPG::MoveRoute"] = Set.new(["@repeat", "@skippable", "@wait", "@list"])
  h["RPG::MoveCommand"] = Set.new(["@code", "@parameters"])
  h["RPG::Troop"] = Set.new(["@id", "@name", "@members", "@pages"])
  h["RPG::Troop::Member"] = Set.new(["@enemy_id", "@x", "@y", "@hidden"])
  h["RPG::Troop::Page"] = Set.new(["@condition", "@span", "@list"])
  h["RPG::Troop::Page::Condition"] = Set.new([
    "@turn_ending", "@turn_valid", "@enemy_valid", "@actor_valid", "@switch_valid",
    "@turn_a", "@turn_b", "@enemy_index", "@enemy_hp", "@actor_id", "@actor_hp",
    "@switch_id"
  ])
  h["RPG::Animation"] = Set.new([
    "@id", "@name", "@animation1_name", "@animation1_hue", "@animation2_name",
    "@animation2_hue", "@position", "@frame_max", "@frames", "@timings"
  ])
  h["RPG::Animation::Frame"] = Set.new(["@cell_max", "@cell_data"])
  h["RPG::Animation::Timing"] = Set.new([
    "@frame", "@se", "@flash_scope", "@flash_color", "@flash_duration"
  ])
  h["RPG::Tileset"] = Set.new([
    "@id", "@mode", "@name", "@tileset_names", "@flags", "@note"
  ])
  h["RPG::CommonEvent"] = Set.new(["@id", "@name", "@trigger", "@switch_id", "@list"])

  # --- System and Subclasses ---
  h["RPG::System"] = Set.new([
    "@game_title", "@version_id", "@japanese", "@party_members", "@currency_unit",
    "@elements", "@skill_types", "@weapon_types", "@armor_types", "@switches", "@variables",
    "@boat", "@ship", "@airship", "@title1_name", "@title2_name",
    "@opt_draw_title", "@opt_use_midi", "@opt_transparent", "@opt_followers",
    "@opt_slip_death", "@opt_floor_death", "@opt_display_tp", "@opt_extra_exp",
    "@window_tone", "@title_bgm", "@battle_bgm", "@battle_end_me", "@gameover_me",
    "@sounds", "@test_battlers", "@test_troop_id", "@start_map_id", "@start_x", "@start_y",
    "@terms", "@battleback1_name", "@battleback2_name", "@battler_name", # Keep RMXP names as per Caliross data? Or stick to rmvxace_db? Let's stick to rmvxace_db for now. Reverting.
    "@battleback1_name", "@battleback2_name", "@battler_name", "@battler_hue", "@edit_map_id"
    # Corrected based on rmvxace_db.rb again:
    # "@battleback1_name", "@battleback2_name", # These are not in rmvxace_db System
    # "@battler_name", "@battler_hue", "@edit_map_id" # These are in rmvxace_db System
  ])
  # Re-checking rmvxace_db.rb for System:
   h["RPG::System"] = Set.new([
      "@game_title", "@version_id", "@japanese", "@party_members", "@currency_unit",
      "@elements", "@skill_types", "@weapon_types", "@armor_types", "@switches", "@variables",
      "@boat", "@ship", "@airship", "@title1_name", "@title2_name",
      "@opt_draw_title", "@opt_use_midi", "@opt_transparent", "@opt_followers",
      "@opt_slip_death", "@opt_floor_death", "@opt_display_tp", "@opt_extra_exp",
      "@window_tone", "@title_bgm", "@battle_bgm", "@battle_end_me", "@gameover_me",
      "@sounds", "@test_battlers", "@test_troop_id", "@start_map_id", "@start_x", "@start_y",
      "@terms",
      "@battleback1_name", "@battleback2_name", # These ARE in rmvxace_db System definition
      "@battler_name", "@battler_hue", "@edit_map_id"
    ])


  h["RPG::System::Vehicle"] = Set.new([
    "@character_name", "@character_index", "@bgm", "@start_map_id", "@start_x", "@start_y"
  ])
  h["RPG::System::Terms"] = Set.new(["@basic", "@params", "@etypes", "@commands"])
  h["RPG::System::TestBattler"] = Set.new(["@actor_id", "@level", "@equips"])

  # --- Audio Files ---
  h["RPG::AudioFile"] = Set.new(["@name", "@volume", "@pitch"])
  # BGM, BGS, ME, SE inherit AudioFile, no *additional* data instance variables defined in rmvxace_db.rb
  h["RPG::BGM"] = h["RPG::AudioFile"].clone
  h["RPG::BGS"] = h["RPG::AudioFile"].clone
  h["RPG::ME"] = h["RPG::AudioFile"].clone
  h["RPG::SE"] = h["RPG::AudioFile"].clone

  # --- Base RPG Maker Data Structures ---
  h["RPG::BaseItem::Feature"] = Set.new(["@code", "@data_id", "@value"])
  h["RPG::UsableItem::Damage"] = Set.new([
    "@type", "@element_id", "@formula", "@variance", "@critical"
  ])
  h["RPG::UsableItem::Effect"] = Set.new(["@code", "@data_id", "@value1", "@value2"])

  # --- Common Data Structures (from common_db.rb) ---
  h["Rect"] = Set.new(["@x", "@y", "@width", "@height"])
  h["Tone"] = Set.new(["@red", "@green", "@blue", "@gray"])
  h["Color"] = Set.new(["@red", "@green", "@blue", "@alpha"])
  h["Table"] = Set.new(["@dims", "@xsize", "@ysize", "@zsize", "@data"])

end.freeze # End of the tap block and freeze the resulting hash

# --- Specific Ignorable Missing Ivars ---
# Includes common Marshal load issues AND potentially missing inherited fields
# if the editor omits default/empty values like icon_index=0 or description="".
IGNORABLE_MISSING_IVARS_BY_CLASS = {
  # Common Marshal load issues with placeholders for primitive-like structures
  "Table" => Set.new(["@data", "@dims", "@xsize", "@ysize", "@zsize"]),
  "Color" => Set.new(["@red", "@green", "@blue", "@alpha"]),
  "Tone" => Set.new(["@red", "@green", "@blue", "@gray"]),
  "Rect" => Set.new(["@x", "@y", "@width", "@height"]),

  # Inherited fields from RPG::BaseItem that might be omitted by the editor if default/empty
  "RPG::Actor" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::Class" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::Enemy" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::State" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::Skill" => Set.new(["@icon_index", "@description", "@note"]), # Skills also inherit BaseItem via UsableItem
  "RPG::Item" => Set.new(["@icon_index", "@description", "@note"]),  # Items also inherit BaseItem via UsableItem
  "RPG::Weapon" => Set.new(["@icon_index", "@description", "@note"]),# Weapons also inherit BaseItem via EquipItem
  "RPG::Armor" => Set.new(["@icon_index", "@description", "@note"]), # Armors also inherit BaseItem via EquipItem

}.freeze

# --- Global Variables ---
$defined_placeholder_classes = Set.new
$logger = nil
$log_file_handle = nil
$validation_errors_found_global_flag = false
$error_file_basenames = Set.new
$log_file_path = nil

# --- Define a simple structure for validation errors ---
ValidationError = Struct.new(:type, :path, :class_name, :details, :filename)

# --- Logger Setup ---
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
    $logger.info("--- RGSS3 (VX Ace) 结构验证脚本开始 ---")
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
    $logger&.info("--- RGSS3 (VX Ace) 结构验证脚本结束 ---")
    $log_file_handle.close
  end
end

# --- Placeholder Definition ---
# (Logic remains the same, but relies on EXPECTED_RGSS3_STRUCTURES)
def define_strict_placeholder(full_name)
  # Check against RGSS3 structures
  unless EXPECTED_RGSS3_STRUCTURES.key?(full_name)
    # Allow base RPG module itself
    unless full_name == "RPG"
      $logger.error("错误: Marshal 数据请求未知的类/模块 '#{full_name}'，这不符合预期的 RGSS3 结构。")
      return false
    end
  end

  return true if $defined_placeholder_classes.include?(full_name)

  parts = full_name.split("::")
  current_scope = Object
  defined_path_parts = []

  parts.each_with_index do |part, index|
    const_sym = part.to_sym
    is_last_part = (index == parts.size - 1)
    current_path_str = (defined_path_parts + [part]).join("::")

    begin
      # Use inherit=false to avoid triggering autoload for checking definition
      if current_scope.const_defined?(const_sym, false)
        entity = current_scope.const_get(const_sym)
        is_our_placeholder = entity.is_a?(Class) && entity.instance_variable_defined?(:@_placeholder_name) && entity.instance_variable_get(:@_placeholder_name) == current_path_str
        is_module_or_class = entity.is_a?(Module)

        unless is_our_placeholder || is_module_or_class
          $logger.warn("警告: '#{current_path_str}' 已存在但不是模块/类 (#{entity.class})，尝试覆盖为占位符...")
          parent_scope_for_set = defined_path_parts.empty? ? Object : Object.const_get(defined_path_parts.join("::"))
          entity = create_minimal_placeholder(parent_scope_for_set, const_sym, current_path_str, is_last_part)
          return false unless entity # Stop if creation failed
        end
        current_scope = entity
      else
        # Does not exist, create it
        parent_scope_for_set = defined_path_parts.empty? ? Object : Object.const_get(defined_path_parts.join("::"))
        current_scope = create_minimal_placeholder(parent_scope_for_set, const_sym, current_path_str, is_last_part)
        return false unless current_scope # Stop if creation failed
      end
      defined_path_parts << part # Add to path only after successful get/create
    rescue NameError, TypeError => e
      $logger.error("定义占位符 '#{current_path_str}' 时出错: #{e.message}")
      # Attempt recovery by creating the placeholder directly if possible
      begin
        parent_scope_for_set = defined_path_parts.empty? ? Object : Object.const_get(defined_path_parts.join("::"))
        current_scope = create_minimal_placeholder(parent_scope_for_set, const_sym, current_path_str, is_last_part)
        return false unless current_scope
        defined_path_parts << part
      rescue => inner_e
        $logger.error("为 '#{current_path_str}' 创建占位符的恢复尝试失败: #{inner_e.message}")
        return false # Stop if recovery fails
      end
    rescue => e
      $logger.error("定义占位符 '#{current_path_str}' 时发生意外错误: #{e.class}: #{e.message}")
      $logger.error(e.backtrace.first(5).join("\n"))
      return false # Stop on unexpected errors
    end
  end

  # Add the fully qualified name to the set of defined placeholders
  $defined_placeholder_classes.add(full_name)
  return true
end

def create_minimal_placeholder(parent_scope, const_sym, full_name, is_class)
  # Only log if it's the first time we are creating *this specific* placeholder
  unless $defined_placeholder_classes.include?(full_name)
     # Use debug level to avoid cluttering INFO log
     $logger.debug("动态定义: 为预期的 RGSS3 实体创建占位符: #{full_name}")
  end

  new_entity = nil
  # Check again if it exists already (could have been created by recursion or another thread)
  if parent_scope.const_defined?(const_sym, false)
    existing = parent_scope.const_get(const_sym)
    is_our_placeholder = existing.is_a?(Class) && existing.instance_variable_defined?(:@_placeholder_name) && existing.instance_variable_get(:@_placeholder_name) == full_name
    return existing if is_our_placeholder # Reuse existing placeholder
    # Reuse existing module if it's not supposed to be a class
    return existing if !is_class && existing.is_a?(Module)
    # If it exists but isn't what we need, remove it before setting (warning given before call)
    begin
      parent_scope.send(:remove_const, const_sym)
    rescue NameError
      # Ignore if it somehow disappeared between check and remove
    end
  end

  begin
    klass_name_for_methods = full_name # Capture name for use inside blocks/methods
    if is_class
      new_entity = Class.new do
        # Store intended name for identification and inspect
        @_placeholder_name = klass_name_for_methods

        # Required for Marshal.load to work with this class
        def self._load(data)
           # Allocate memory, Marshal itself will populate instance variables
           allocate
        end

        # Basic initialize to store the name on the instance for easier debugging/inspect
        def initialize(*_args)
           # Store the placeholder name from the class variable onto the instance
           @_placeholder_name_inst = self.class.instance_variable_get(:@_placeholder_name) rescue "UnknownPlaceholder"
        end

        # Improved inspect for placeholders
        def inspect
          klass_name = @_placeholder_name_inst || (self.class.instance_variable_get(:@_placeholder_name) rescue self.class.name rescue "AnonPlaceholder")
          ivars_str = instance_variables.reject { |v| v.to_s.start_with?('@_') }.map { |ivar|
            begin
              value = instance_variable_get(ivar)
              value_inspect = value.inspect
              # Simple truncation for long strings or potential binary data
              if value.is_a?(String) && value.bytesize > 50 && (!value.valid_encoding? || value.bytes.any? { |b| b < 32 && ![9, 10, 13].include?(b) } || value.bytes.include?(0))
                 value_inspect = "[String len=#{value.bytesize}]"
              elsif value_inspect.length > 80
                 value_inspect = value_inspect[0, 80] + "..."
              end
            rescue => e
              value_inspect = "[Inspect Error: #{e.message}]"
            end
            "#{ivar}=#{value_inspect}"
          }.join(", ")
          "<Placeholder(#{klass_name}) #{ivars_str}>"
        end

        # Define class methods .name and .to_s to return the intended name
        define_singleton_method(:name) { klass_name_for_methods }
        define_singleton_method(:to_s) { klass_name_for_methods }
      end
    else
      # Modules are simpler, just need the name methods
      new_entity = Module.new do
        define_singleton_method(:name) { klass_name_for_methods }
        define_singleton_method(:to_s) { klass_name_for_methods }
      end
    end

    # Set the constant in the parent scope
    parent_scope.const_set(const_sym, new_entity)
    return new_entity
  rescue => e
    $logger.error("创建或设置占位符 '#{full_name}' 时失败: #{e.class}: #{e.message}")
    return nil # Indicate failure
  end
end


# --- Function to load a single RVData2 file ---
# (Logic remains the same, relies on EXPECTED_RGSS3_STRUCTURES for checks)
def load_rvdata_for_validation(filepath, log_details: true)
  basename = File.basename(filepath) # Use basename for logging
  $logger.info("--- 开始加载 Marshal 文件进行验证: #{basename} ---") if log_details || $logger.debug?
  loaded_data = nil
  retries = 0
  failed_strict_defines = Set.new # Track failures per file load attempt

  loop do
    begin
      file_content = File.binread(filepath)
      loaded_data = Marshal.load(file_content)
      $logger.info("Marshal.load 完成: #{basename}") if log_details || $logger.debug?
      break # Success
    rescue ArgumentError => e
      match_data = e.message.match(/undefined class\/module (\S+)/)
      if match_data && retries < MAX_RETRIES
        original_request_name = match_data[1] # Keep the original name Marshal requested

        # --- START MODIFICATION ---
        # Normalize the requested name: remove trailing '::' if present
        # This handles cases like "RPG::BaseItem::" becoming "RPG::BaseItem"
        normalized_entity_name = original_request_name.chomp('::')
        # Log the normalization if debugging
        if normalized_entity_name != original_request_name && $logger.debug?
             $logger.debug("Normalized Marshal request '#{original_request_name}' to '#{normalized_entity_name}'")
        end
        # --- END MODIFICATION ---


        is_rpg_module_itself = (normalized_entity_name == "RPG") # Use normalized name for logic
        is_rpg_related = normalized_entity_name.start_with?("RPG::") || is_rpg_module_itself # Use normalized name for logic
        # Check against RGSS3 structure list using the NORMALIZED name
        is_expected_entity = EXPECTED_RGSS3_STRUCTURES.key?(normalized_entity_name) || is_rpg_module_itself # *** USE NORMALIZED NAME ***

        if is_expected_entity
          # Log the attempt using the ORIGINAL name Marshal asked for, for clarity
          $logger.warn("尝试定义: 遇到预期但未定义的 RGSS3 实体: #{original_request_name} (文件: #{basename}, 尝试次数 #{retries + 1}/#{MAX_RETRIES})")

          # Ensure base RPG module exists if needed (uses "RPG", which is fine)
          if is_rpg_related && !Object.const_defined?(:RPG)
            $logger.info("依赖检查: 定义 RPG 模块 (请求者: #{original_request_name} in #{basename})...")
            unless create_minimal_placeholder(Object, :RPG, "RPG", false)
              $logger.error("致命错误: 无法创建基础 RPG 模块，停止加载 #{basename}。")
              $validation_errors_found_global_flag = true
              return nil # Failure
            end
            $defined_placeholder_classes.add("RPG") # Mark base RPG as defined
          end

          # Define the specific placeholder unless it's the RPG module itself
          unless is_rpg_module_itself
             # Use NORMALIZED name for tracking failures and definition calls
            if failed_strict_defines.include?(normalized_entity_name)
              $logger.error("错误: 之前尝试严格定义 #{normalized_entity_name} 失败，无法继续加载 #{basename}。")
              $validation_errors_found_global_flag = true
              return nil # Failure
            end

            # Use NORMALIZED name to call define_strict_placeholder
            unless define_strict_placeholder(normalized_entity_name) # *** USE NORMALIZED NAME ***
              $logger.error("无法定义预期的占位符 #{normalized_entity_name}，停止加载 #{basename}.")
              failed_strict_defines.add(normalized_entity_name) # Mark NORMALIZED name as failed
              $validation_errors_found_global_flag = true
              return nil # Failure
            end
          else
              # Log skipping the base RPG module itself (using normalized name is fine here)
              $logger.debug("跳过对基础模块 '#{normalized_entity_name}' 的严格占位符定义 (已处理)") if $logger.debug?
          end

          # If definition succeeded (or was skipped), retry Marshal.load
          retries += 1
          next
        else
          # The undefined class/module is NOT in our expected RGSS3 list even after normalization
          # Log the error with the ORIGINAL name, and maybe the normalized one for context
          $logger.error("验证错误 (#{basename}): Marshal 数据需要一个非 RGSS3 标准的类/模块: '#{original_request_name}' (规范化后为 '#{normalized_entity_name}'，仍未在预期列表中找到)")
          $validation_errors_found_global_flag = true
          return nil # Failure
        end
      else
        # Handle other ArgumentErrors or max retries reached
        error_source = match_data ? "'#{match_data[1]}'" : "未知实体"
        reason = e.message
        $logger.error("Marshal.load 失败 (#{basename})。原因: #{reason}")
        if match_data && retries >= MAX_RETRIES
            $logger.error("已达到最大重试次数 (#{MAX_RETRIES})，仍无法加载所需的实体 #{error_source} in #{basename}")
        elsif reason.include?("marshal data too short") || reason.include?("invalid marshal format") || reason.include?("incompatible marshal file format")
            $logger.error("提示：文件 #{basename} 可能已损坏或与当前 Ruby Marshal 版本不兼容。")
        end
        $validation_errors_found_global_flag = true
        return nil # Failure
      end
    # Keep other rescue blocks the same
    rescue TypeError, EncodingError => e
      # Catch specific errors that indicate file issues or placeholder problems
      $logger.error("Marshal.load 时发生 #{e.class} (#{basename}): #{e.message}")
      $validation_errors_found_global_flag = true
      return nil # Failure
    rescue => e
      # Catch-all for other unexpected errors during load
      $logger.error("读取或解析 Marshal 文件 #{basename} 时发生未知错误: #{e.class}: #{e.message}")
      $logger.error(e.backtrace.first(5).join("\n"))
      $validation_errors_found_global_flag = true
      return nil # Failure
    end
  end # loop end

  loaded_data # Return the loaded data on success
end

# --- Recursive Structure Validation ---
# (Logic remains the same, relies on EXPECTED_RGSS3_STRUCTURES and IGNORABLE_MISSING_IVARS_BY_CLASS)
def validate_structure(path, obj, validation_results, log_path: "root", filename: "UnknownFile")
  # Base cases: simple types that are inherently valid
  return true if obj.nil? || obj.is_a?(Symbol) || obj.is_a?(Numeric) || obj.is_a?(TrueClass) || obj.is_a?(FalseClass) || obj.is_a?(String)

  # Recursive cases for containers
  if obj.is_a?(Array)
    all_valid = true
    obj.each_with_index do |item, i|
      is_item_valid = validate_structure("#{path}[#{i}]", item, validation_results, log_path: "#{log_path}[#{i}]", filename: filename)
      all_valid &&= is_item_valid # Keep track if any element is invalid
    end
    return all_valid
  elsif obj.is_a?(Hash)
    all_valid = true
    obj.each do |key, value|
      # Represent key safely for path string
      key_repr = key.inspect rescue "[Bad Key]"
      is_value_valid = validate_structure("#{path}[#{key_repr}]", value, validation_results, log_path: "#{log_path}[#{key_repr}]", filename: filename)
      all_valid &&= is_value_valid # Keep track if any value is invalid
    end
    return all_valid
  end

  # --- Object Validation ---
  obj_class = obj.class
  class_name = obj_class.name rescue nil

  # Handle anonymous classes or classes where .name fails (less common with our placeholders)
  # Try to get name from our placeholder instance variable if .name is nil/empty or class isn't defined
  class_is_defined = false
  begin
    class_is_defined = Object.const_defined?(class_name) if class_name && !class_name.empty?
  rescue NameError
    class_is_defined = false # Handle cases where class_name is somehow invalid for const_defined?
  end

  if class_name.nil? || class_name.empty? || !class_is_defined
      # Check if it's one of our placeholders by checking the instance variable
      intended_name = obj.instance_variable_get(:@_placeholder_name_inst) if obj.respond_to?(:instance_variable_defined?) && obj.instance_variable_defined?(:@_placeholder_name_inst)
      if intended_name && !intended_name.empty?
          class_name = intended_name
          # $logger.debug("DEBUG: Identified object via placeholder instance variable as: #{class_name} at path #{log_path}") if $logger.debug?
      end
  end


  # If we still can't determine the class name, log an error
  unless class_name && !class_name.empty?
    error_details = "无法确定类名的对象: #{obj.inspect[0..200]}" # Limit inspect length
    validation_results << ValidationError.new(:unknown_class, log_path, nil, error_details, filename)
    $validation_errors_found_global_flag = true
    $error_file_basenames.add(filename)
    return false # Cannot validate further
  end

  # Check if this class is expected in RGSS3
  expected_ivars = EXPECTED_RGSS3_STRUCTURES[class_name]
  unless expected_ivars
    error_details = "发现意外的类: #{class_name}"
    validation_results << ValidationError.new(:unexpected_class, log_path, class_name, error_details, filename)
    $validation_errors_found_global_flag = true
    $error_file_basenames.add(filename)
    # We don't know the expected structure, so stop validation for this object, but return true
    # because the *existence* of the object isn't necessarily an error in its children.
    # Let the caller decide if the parent structure is invalid.
    # Correction: Return false here. An unexpected class *is* a structure violation at this point.
    return false
  end

  # --- Instance Variable Checks ---
  structure_valid = true # Assume valid until proven otherwise
  begin
    actual_ivars = obj.instance_variables.map(&:to_s).to_set
    # Remove internal placeholder variable from the check
    actual_ivars.delete("@_placeholder_name_inst")
  rescue => e
    # Handle potential errors during instance_variables call
    error_details = "检查对象 (#{class_name}) 的实例变量时出错: #{e.message}"
    validation_results << ValidationError.new(:ivar_check_error, log_path, class_name, error_details, filename)
    $logger.error("CRITICAL (文件 '#{filename}.rvdata2', 路径 '#{log_path}'): #{error_details}")
    $validation_errors_found_global_flag = true
    $error_file_basenames.add(filename)
    return false # Cannot proceed with ivar checks
  end

  # 1. Check for unexpected instance variables
  unexpected_ivars = actual_ivars - expected_ivars
  if unexpected_ivars.any?
    ivar_list = unexpected_ivars.to_a.sort
    validation_results << ValidationError.new(:unexpected_ivar, log_path, class_name, ivar_list, filename)
    structure_valid = false
    $validation_errors_found_global_flag = true
    $error_file_basenames.add(filename)
  end

  # 2. Check for missing expected instance variables (considering ignorable ones)
  missing_ivars = expected_ivars - actual_ivars
  if missing_ivars.any?
    ignorable_missing_for_this_class = IGNORABLE_MISSING_IVARS_BY_CLASS[class_name] || Set.new
    problematic_missing = missing_ivars - ignorable_missing_for_this_class

    if problematic_missing.any?
      ivar_list = problematic_missing.to_a.sort
      validation_results << ValidationError.new(:missing_ivar, log_path, class_name, ivar_list, filename)
      structure_valid = false
      $validation_errors_found_global_flag = true
      $error_file_basenames.add(filename)
    elsif missing_ivars.any? && $logger.debug? # Log ignored missing only in debug
      $logger.debug("DEBUG (文件 '#{filename}.rvdata2', 路径 '#{log_path}'): 对象 (#{class_name}) 跳过“缺少实例变量”检查 (均为可忽略): #{missing_ivars.to_a.sort.join(", ")}")
    end
  end

  # 3. Recursively validate the values of expected instance variables that are present
  ivars_to_check_recursively = actual_ivars & expected_ivars # Check only common ivars
  ivars_to_check_recursively.each do |ivar_name|
    ivar_sym = ivar_name.to_sym
    begin
      value = obj.instance_variable_get(ivar_sym)
      # Recursively call validate_structure for the value
      is_value_valid = validate_structure(ivar_name, value, validation_results, log_path: "#{log_path}.#{ivar_name.sub(/^@/, "")}", filename: filename)
      structure_valid &&= is_value_valid # Propagate invalidity upwards
    rescue => e
      # Handle errors getting the instance variable value
      error_details = "获取或验证对象 (#{class_name}) 的实例变量 #{ivar_name} 值时出错: #{e.message}"
      validation_results << ValidationError.new(:get_ivar_error, log_path, class_name, error_details, filename)
      $logger.error("CRITICAL (文件 '#{filename}.rvdata2', 路径 '#{log_path}'): #{error_details}")
      structure_valid = false # Mark as invalid if we can't check the child
      $validation_errors_found_global_flag = true
      $error_file_basenames.add(filename)
    end
  end

  return structure_valid
end


# --- Helper to format aggregated error message ---
# (Remains the same)
def format_aggregated_error(key, agg_data)
  type, class_name, details_str = key
  count = agg_data[:count]
  first_path = agg_data[:first_path]
  # Format details array/set nicely for display
  details_display = details_str.split(',').join(', ') # Assumes details were joined by comma

  message_base = case type
                 when :missing_ivar then "缺少预期实例变量: #{details_display}"
                 when :unexpected_ivar then "发现意外实例变量: #{details_display}"
                 when :unexpected_class then details_str # Usually "发现意外的类: ClassName"
                 when :unknown_class then details_str # Usually "无法确定类名..."
                 when :ivar_check_error then "检查实例变量时出错: #{details_display}"
                 when :get_ivar_error then "获取实例变量值时出错: #{details_display}"
                 else "发生未知类型 (#{type}) 错误: #{details_display}"
                 end

  context = (class_name && class_name != "N/A") ? "在类 (#{class_name})" : "在未知类/上下文中"
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
  STDERR.puts "用法: ruby validate_rgss3_structure.rb <要验证的目录路径>"
  STDERR.puts "       检查该目录下匹配规则的 .rvdata2 文件是否符合 RGSS3 (VX Ace) 结构。"
  STDERR.puts "       详细日志和错误将写入 #{LOG_DIR}/#{LOG_FILENAME} 格式的文件中。"
  exit 1
end

target_dir = Pathname.new(ARGV[0])
unless target_dir.directory?
  STDERR.set_encoding("UTF-8") rescue nil
  STDERR.puts "错误: 目录未找到或不是一个目录 - #{target_dir}"
  exit 1
end

# Setup logger AFTER argument validation
setup_logger

$logger.info("开始验证目录: #{target_dir.expand_path}")
$logger.info("验证规则: #{FILES_TO_VALIDATE.inspect}")
$logger.info("将忽略以下类中特定缺失的实例变量 (因占位符加载限制):")
IGNORABLE_MISSING_IVARS_BY_CLASS.each { |k, v| $logger.info("  - #{k}: #{v.to_a.sort.join(", ")}") }
$logger.info("=======================================")

validation_performed_count = 0
# Global summary per rule, tracking files with errors and common error signatures within them
global_rule_error_summary = Hash.new { |h, k| h[k] = { error_files: Set.new, common_errors: Hash.new(0) } }

# --- DEFINE file_extension HERE ---
file_extension = ".rvdata2" # Use RGSS3 extension

# Process each validation rule (filename or regex)
FILES_TO_VALIDATE.each do |rule|
  $logger.info("\n--- 处理规则: #{rule.inspect} ---")

  files_to_process = [] # Holds { base:, path:, source_rule: } hashes
  is_regex_rule = rule.is_a?(Regexp)
  regex_processed_count = 0 # Stats for regex rules
  regex_error_count = 0
  # Aggregated errors specifically for *this run* of the rule (especially useful for regex)
  # Key: [type, class_name, details_key], Value: { count:, files: Set[basename] }
  rule_run_aggregated_errors = Hash.new { |h, k| h[k] = { count: 0, files: Set.new } }

  # --- File Collection ---
  if rule.is_a?(String)
    # Handle specific filename
    file_path = target_dir.join("#{rule}#{file_extension}")
    if file_path.file?
      files_to_process << { base: rule, path: file_path, source_rule: rule }
    else
      $logger.info("[信息] 未找到固定文件: #{file_path.basename}")
    end
  elsif is_regex_rule
    # Handle regex pattern
    begin
      found_files = Dir.entries(target_dir).select do |entry|
        entry.end_with?(file_extension) &&
        rule.match?(entry.chomp(file_extension)) &&
        target_dir.join(entry).file?
      end

      if found_files.empty?
        $logger.info("[信息] 未找到匹配模式 #{rule.inspect} 的 #{file_extension} 文件。")
      else
        found_files.sort.each do |fname|
          base = fname.chomp(file_extension)
          files_to_process << { base: base, path: target_dir.join(fname), source_rule: rule }
        end
      end
    rescue Errno::ENOENT => e
      $logger.error("访问目录 '#{target_dir}' 时出错: #{e.message}")
      next # Skip to next rule if directory access fails
    rescue => e
      $logger.error("处理规则 #{rule.inspect} 查找文件时发生错误: #{e.class}: #{e.message}")
      next # Skip to next rule on other errors
    end
  else
    # Handle unknown rule type
    $logger.warn("[警告] 未知的验证规则类型: #{rule.inspect}。已跳过。")
    next
  end

  # Skip if no files matched this rule
  next if files_to_process.empty?

  # --- Process Files for this rule ---
  files_to_process.each do |file_info|
    base_name = file_info[:base]
    file_path = file_info[:path]
    validation_performed_count += 1
    file_had_issues = false # Track if load or structure validation failed for this file

    # Determine if detailed logging should happen for this specific file
    # For regex (MapXXX) rules, only log details if explicitly enabled or DEBUG level
    log_details_this_file = if is_regex_rule
                              $logger.debug? || LOG_MAP_DETAILS_IF_ERRORS
                            else
                              # Log details for specific files unless logger level is WARN or higher
                              $logger.level <= Logger::INFO
                            end

    # Log start message if detailed logging is on for this file
    if log_details_this_file
        rule_info_str = is_regex_rule ? "(匹配模式 #{rule.inspect})" : ""
        $logger.info("[开始验证] #{base_name}#{file_extension} #{rule_info_str}")
    end

    # --- Load Data ---
    data = load_rvdata_for_validation(file_path.to_s, log_details: log_details_this_file)

    if data.nil?
      # Load failed, mark as having issues
      file_had_issues = true
      $error_file_basenames.add(base_name) # Track globally
      global_rule_error_summary[rule][:error_files].add(base_name) # Track for rule summary
      # Log a warning if detailed logging was off, so user knows *something* failed
      unless log_details_this_file
          $logger.warn("[加载失败] #{base_name}#{file_extension} (详情请调高日志级别或检查日志文件)")
      end
    else
      # --- Structure Validation ---
      current_file_errors_structured = [] # Collect ValidationError structs for this file
      validate_structure("root", data, current_file_errors_structured, log_path: "root", filename: base_name)

      # --- Aggregation and Logging Step (File Level) ---
      if current_file_errors_structured.any?
        file_had_issues = true # Mark file as having issues
        $error_file_basenames.add(base_name) # Track globally
        global_rule_error_summary[rule][:error_files].add(base_name) # Track for rule summary

        # Aggregate errors within this single file to reduce log spam
        aggregated_errors_this_file = Hash.new { |h, k| h[k] = { count: 0, first_path: nil } }
        current_file_errors_structured.each do |error|
          # Create a consistent key for aggregation based on type, class, and details
          details_key = case error.details
                        when Array then error.details.sort.join(',') # Sort array details for consistency
                        when Set then error.details.to_a.sort.join(',') # Sort set details
                        else error.details.to_s # Use string representation for others
                        end
          # Key: [Type Symbol, Class Name String or "N/A", Details String]
          key = [error.type, error.class_name || "N/A", details_key]

          # Aggregate counts and first path for file-level summary
          agg = aggregated_errors_this_file[key]
          agg[:count] += 1
          agg[:first_path] ||= error.path # Record the first path where this specific error occurred

          # Store for rule-level aggregation as well (only needed for regex rules really)
          if is_regex_rule
              rule_agg = rule_run_aggregated_errors[key]
              rule_agg[:count] += 1 # This counts occurrences across *all* files for this rule run
              rule_agg[:files].add(base_name) # Track which files had this error signature
              # Also update the global rule summary's common error counts
              global_rule_error_summary[rule][:common_errors][key] += 1
          elsif !is_regex_rule # For non-regex rules, update global summary directly
              global_rule_error_summary[rule][:common_errors][key] += 1
          end
        end

        # Log the aggregated errors *for this specific file* only if detailed logging is enabled
        if log_details_this_file
            $logger.warn("[验证发现结构问题] #{base_name}#{file_extension}:")
            aggregated_errors_this_file.each do |key, agg_data|
                $logger.warn("  - #{format_aggregated_error(key, agg_data)}")
            end
        elsif !is_regex_rule # If detailed logging is off, but it's a specific file (not regex), log a general warning
             $logger.warn("[验证发现问题] #{base_name}#{file_extension} (详情请调高日志级别或检查日志文件)")
        end
      end # end if current_file_errors_structured.any?
    end # end if data.nil? else ...

    # --- Update Regex Stats ---
    if is_regex_rule
      regex_processed_count += 1
      regex_error_count += 1 if file_had_issues
    elsif file_had_issues && !log_details_this_file # Non-regex file with issues, details were NOT logged
         # Log general issue warning if not logged in detail above (already done for load failure)
         # This catches structure errors where details were suppressed.
         # $logger.warn("[验证发现问题] #{base_name}#{file_extension} (详情请调高日志级别或检查日志文件)")
         # This message might be redundant with the one inside the aggregation block. Let's rely on that one.
    elsif !file_had_issues && log_details_this_file # Non-regex, no issues, detailed log enabled
         $logger.info("[验证成功] #{base_name}#{file_extension}: 未发现需关注的问题。")
    end

  end # end files_to_process.each

  # --- Regex Rule Summary (after processing all files for the regex rule) ---
  if is_regex_rule && regex_processed_count > 0
    regex_success_count = regex_processed_count - regex_error_count
    $logger.info("[规则总结] 模式 #{rule.inspect}:")
    $logger.info("  共检查 #{regex_processed_count} 个匹配文件。")
    $logger.info("  成功 (未发现问题): #{regex_success_count} 个。")
    if regex_error_count > 0
      $logger.warn("  发现问题 (加载或结构): #{regex_error_count} 个。")

      # Find the most frequent error *signature* across the files processed *by this specific rule run*.
      # We prioritize errors that occurred in the most *distinct files*.
      most_frequent_error_key = rule_run_aggregated_errors.keys.max_by do |key|
          rule_run_aggregated_errors[key][:files].size # Find key affecting the most files
      end

      if most_frequent_error_key
          data = rule_run_aggregated_errors[most_frequent_error_key]
          num_files_with_error = data[:files].size
          # Only report if it's common among the error files for this rule
          # Heuristic: Common if in > 1 file and >= 50% of the files *that had errors*
          if num_files_with_error > 1 && num_files_with_error >= (regex_error_count * 0.5).ceil
               # Need dummy data for formatting function call (path isn't relevant here)
               dummy_agg_data_for_format = { count: data[:count], first_path: "..." }
               formatted_msg = format_aggregated_error(most_frequent_error_key, dummy_agg_data_for_format)
               # Adapt message for rule level summary (remove path and total count)
               common_issue_desc = formatted_msg.split(":", 2).last.strip.sub(/\(共计 \d+ 次\)$/, '').strip
               $logger.warn("    最常见问题: 在 #{num_files_with_error} 个文件中发现 -> #{common_issue_desc}")
          end
      end
      # Add note about where to find details if they were suppressed for map files
      unless LOG_MAP_DETAILS_IF_ERRORS || $logger.debug?
          $logger.warn("    (设 LOG_MAP_DETAILS_IF_ERRORS = true 或 日志级别为 DEBUG 查看各 Map 文件详情)")
      end
    end
  end

end # end FILES_TO_VALIDATE.each

# --- Final Summary (Improved Grouping for Maps) ---
$logger.info("\n=======================================")
$logger.info("--- 验证完成 ---")

final_message_lines = []
exit_code = 0

if validation_performed_count == 0
  final_message_lines << "未执行任何文件验证（可能没有找到匹配的 #{file_extension} 文件）。"
  exit_code = 0 # No files found isn't an error state
else
  final_message_lines << "验证完成。"
  final_message_lines << "总共检查文件数: #{validation_performed_count}"
  actual_error_file_count = $error_file_basenames.size

  if actual_error_file_count > 0
    final_message_lines << "发现问题的文件 (#{actual_error_file_count}):"

    # Group files by pattern (specifically separating MapXXX)
    map_files = $error_file_basenames.select { |name| name.match?(/^Map\d{3}$/) }.sort
    other_files = $error_file_basenames.reject { |name| name.match?(/^Map\d{3}$/) }.sort

    # Find the Map rule from the configuration to access its summary data
    map_rule = FILES_TO_VALIDATE.find { |r| r.is_a?(Regexp) && r.source == 'Map\d{3}' }

    # Log Map files summary first if any exist
    if map_files.any?
      line = "  - MapXXX#{file_extension} (#{map_files.size} 个文件)"
      # Try to add the most common issue *for the Map rule* from the global summary
      if map_rule && global_rule_error_summary.key?(map_rule) && global_rule_error_summary[map_rule][:common_errors].any?
         # Find the error signature with the highest count across all map files processed by the rule
         most_common_key = global_rule_error_summary[map_rule][:common_errors].max_by { |k, v| v }[0]
         if most_common_key
             type, class_name, details_str = most_common_key
             details_display = details_str.split(',').join(', ') # Format for display
             # Generate a short description of the common issue
             common_desc = case type
                            when :missing_ivar then "缺少 #{details_display}"
                            when :unexpected_ivar then "意外 #{details_display}"
                            when :unexpected_class then "意外类 #{details_display.split(':').last.strip}" # Extract class name
                            when :value_mismatch then "值不匹配"
                            when :type_mismatch then "类型不匹配"
                            else "类型 #{type} 问题"
                            end
             context = (class_name && class_name != "N/A") ? "在类 #{class_name}" : "在未知类中"
             line += " (常见问题: #{context}: #{common_desc})"
         end
      end
      final_message_lines << line
    end

    # Log other problematic files individually
    other_files.each do |basename|
      final_message_lines << "  - #{basename}#{file_extension}"
    end

    final_message_lines << "详细信息请查看日志文件: #{$log_file_path.expand_path}"
    exit_code = 1 # Exit with error code if any file had issues
  else
    # All checked files were valid
    final_message_lines << "在检查的所有 #{validation_performed_count} 个文件中未发现需要关注的结构问题。"
    final_message_lines << "(注意: 对于 Table, Color, Tone, Rect 类, 由于占位符加载机制限制, 未严格检查其内部变量是否存在。)"
    exit_code = 0
  end
end

# --- Output Final Summary ---
final_message = final_message_lines.join("\n")
$logger.info("\n" + final_message) # Log the final summary
puts "\n" + final_message # Also print summary to console for quick feedback

exit(exit_code)