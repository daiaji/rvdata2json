#!/usr/bin/env ruby
# encoding: utf-8
# validate_rgss_structure.rb - 检查指定目录下数据文件是否符合指定的 RGSS 结构 (1, 2, 或 3)
#
# 用法:
#   ruby validate_rgss_structure.rb <要验证的目录路径> [-v VERSION | --version VERSION]
#
# 参数:
#   <要验证的目录路径> : 包含 .rxdata (RGSS1), .rvdata (RGSS2), 或 .rvdata2 (RGSS3) 文件的目录。
#   -v VERSION, --version VERSION : 指定要验证的 RGSS 版本 (1, 2, 或 3)。
#                                  如果省略，脚本会尝试根据目录中的文件扩展名自动检测。
#
# 功能:
#   - 根据指定的 RGSS 版本加载对应的结构定义。
#   - 加载目标目录中匹配规则的数据文件。
#   - 动态定义 Marshal 加载所需的占位符类/模块。
#   - 递归验证加载的数据结构是否符合选定版本的预期。
#   - 记录验证过程中发现的任何结构性问题（如意外/缺失的实例变量、意外的类）。
#   - 对单个文件内的重复错误进行聚合，减少日志冗余。
#   - 对 Map 等正则匹配规则下的常见错误进行聚合总结。
#   - 在脚本结束时提供包含问题文件列表（Map 文件分组显示）的摘要。
#   - ***新增***: 实时记录动态创建的占位符。
#   - ***新增***: 在脚本末尾总结所有动态创建的占位符列表。
#   - 所有注释使用中文。

require "pp"
require "set"
require "logger"
require "fileutils"
require "pathname"
require "optparse" # 用于解析命令行参数

# --- 全局配置 ---
MAX_RETRIES = 50 # 使用 RGSS3 的较高值作为默认，适应更复杂情况
LOG_DIR = "logs"
LOG_LEVEL = Logger::INFO # 可以改为 Logger::DEBUG 查看更详细信息
LOG_MAP_DETAILS_IF_ERRORS_DEFAULT = false # 默认关闭 Map 文件详细错误日志 (INFO级别)

# --- 统一的默认验证文件列表 (包含所有版本可能的文件) ---
DEFAULT_FILES_TO_VALIDATE = [
  "Actors", "Animations", "Armors", "Classes", "CommonEvents",
  "Enemies", "Items", "MapInfos", "Skills", "States", "System",
  "Tilesets", # 主要在 RGSS3, 但包含无妨
  "Troops", "Weapons",
  /Map\d{3}/, # 适用于所有版本
].freeze

# --- RGSS 版本特定数据定义 ---

# --- RGSS1 (XP) 结构定义 ---
EXPECTED_RGSS1_STRUCTURES = {
  "RPG::Actor" => Set.new(["@id", "@name", "@class_id", "@initial_level", "@final_level", "@exp_basis", "@exp_inflation", "@character_name", "@character_hue", "@battler_name", "@battler_hue", "@parameters", "@weapon_id", "@armor1_id", "@armor2_id", "@armor3_id", "@armor4_id", "@weapon_fix", "@armor1_fix", "@armor2_fix", "@armor3_fix", "@armor4_fix"]),
  "RPG::Class" => Set.new(["@id", "@name", "@position", "@weapon_set", "@armor_set", "@element_ranks", "@state_ranks", "@learnings"]),
  "RPG::Class::Learning" => Set.new(["@level", "@skill_id"]),
  "RPG::Skill" => Set.new(["@id", "@name", "@icon_name", "@description", "@scope", "@occasion", "@animation1_id", "@animation2_id", "@menu_se", "@common_event_id", "@sp_cost", "@power", "@atk_f", "@eva_f", "@str_f", "@dex_f", "@agi_f", "@int_f", "@hit", "@pdef_f", "@mdef_f", "@variance", "@element_set", "@plus_state_set", "@minus_state_set"]),
  "RPG::Item" => Set.new(["@id", "@name", "@icon_name", "@description", "@scope", "@occasion", "@animation1_id", "@animation2_id", "@menu_se", "@common_event_id", "@price", "@consumable", "@parameter_type", "@parameter_points", "@recover_hp_rate", "@recover_hp", "@recover_sp_rate", "@recover_sp", "@hit", "@pdef_f", "@mdef_f", "@variance", "@element_set", "@plus_state_set", "@minus_state_set"]),
  "RPG::Weapon" => Set.new(["@id", "@name", "@icon_name", "@description", "@animation1_id", "@animation2_id", "@price", "@atk", "@pdef", "@mdef", "@str_plus", "@dex_plus", "@agi_plus", "@int_plus", "@element_set", "@plus_state_set", "@minus_state_set"]),
  "RPG::Armor" => Set.new(["@id", "@name", "@icon_name", "@description", "@kind", "@auto_state_id", "@price", "@pdef", "@mdef", "@eva", "@str_plus", "@dex_plus", "@agi_plus", "@int_plus", "@guard_element_set", "@guard_state_set"]),
  "RPG::Enemy" => Set.new(["@id", "@name", "@battler_name", "@battler_hue", "@maxhp", "@maxsp", "@str", "@dex", "@agi", "@int", "@atk", "@pdef", "@mdef", "@eva", "@animation1_id", "@animation2_id", "@element_ranks", "@state_ranks", "@actions", "@exp", "@gold", "@item_id", "@weapon_id", "@armor_id", "@treasure_prob"]),
  "RPG::Enemy::Action" => Set.new(["@kind", "@basic", "@skill_id", "@condition_turn_a", "@condition_turn_b", "@condition_hp", "@condition_level", "@condition_switch_id", "@rating"]),
  "RPG::Troop" => Set.new(["@id", "@name", "@members", "@pages"]),
  "RPG::Troop::Member" => Set.new(["@enemy_id", "@x", "@y", "@hidden", "@immortal"]),
  "RPG::Troop::Page" => Set.new(["@condition", "@span", "@list"]), # RMXP 称为 BattleEventPage
  "RPG::Troop::Page::Condition" => Set.new(["@turn_valid", "@enemy_valid", "@actor_valid", "@switch_valid", "@turn_a", "@turn_b", "@enemy_index", "@enemy_hp", "@actor_id", "@actor_hp", "@switch_id"]),
  "RPG::State" => Set.new(["@id", "@name", "@animation_id", "@restriction", "@nonresistance", "@zero_hp", "@cant_get_exp", "@cant_evade", "@slip_damage", "@rating", "@hit_rate", "@maxhp_rate", "@maxsp_rate", "@str_rate", "@dex_rate", "@agi_rate", "@int_rate", "@atk_rate", "@pdef_rate", "@mdef_rate", "@eva", "@battle_only", "@hold_turn", "@auto_release_prob", "@shock_release_prob", "@guard_element_set", "@plus_state_set", "@minus_state_set"]),
  "RPG::Animation" => Set.new(["@id", "@name", "@animation_name", "@animation_hue", "@position", "@frame_max", "@frames", "@timings"]),
  "RPG::Animation::Frame" => Set.new(["@cell_max", "@cell_data"]),
  "RPG::Animation::Timing" => Set.new(["@frame", "@se", "@flash_scope", "@flash_color", "@flash_duration", "@condition"]),
  "RPG::Tileset" => Set.new(["@id", "@name", "@tileset_name", "@autotile_names", "@panorama_name", "@panorama_hue", "@fog_name", "@fog_hue", "@fog_opacity", "@fog_blend_type", "@fog_zoom", "@fog_sx", "@fog_sy", "@battleback_name", "@passages", "@priorities", "@terrain_tags"]),
  "RPG::CommonEvent" => Set.new(["@id", "@name", "@trigger", "@switch_id", "@list"]),
  "RPG::Event" => Set.new(["@id", "@name", "@x", "@y", "@pages"]),
  "RPG::Event::Page" => Set.new(["@condition", "@graphic", "@move_type", "@move_speed", "@move_frequency", "@move_route", "@walk_anime", "@step_anime", "@direction_fix", "@through", "@always_on_top", "@trigger", "@list"]),
  "RPG::Event::Page::Condition" => Set.new(["@switch1_valid", "@switch2_valid", "@variable_valid", "@self_switch_valid", "@switch1_id", "@switch2_id", "@variable_id", "@variable_value", "@self_switch_ch"]),
  "RPG::Event::Page::Graphic" => Set.new(["@tile_id", "@character_name", "@character_hue", "@direction", "@pattern", "@opacity", "@blend_type"]),
  "RPG::EventCommand" => Set.new(["@code", "@indent", "@parameters"]),
  "RPG::Map" => Set.new(["@tileset_id", "@width", "@height", "@autoplay_bgm", "@bgm", "@autoplay_bgs", "@bgs", "@encounter_list", "@encounter_step", "@data", "@events"]),
  "RPG::MapInfo" => Set.new(["@name", "@parent_id", "@order", "@expanded", "@scroll_x", "@scroll_y"]),
  "RPG::MoveRoute" => Set.new(["@repeat", "@skippable", "@list"]),
  "RPG::MoveCommand" => Set.new(["@code", "@parameters"]),
  "RPG::System" => Set.new(["@magic_number", "@party_members", "@elements", "@switches", "@variables", "@windowskin_name", "@title_name", "@gameover_name", "@battle_transition", "@title_bgm", "@battle_bgm", "@battle_end_me", "@gameover_me", "@cursor_se", "@decision_se", "@cancel_se", "@buzzer_se", "@equip_se", "@shop_se", "@save_se", "@load_se", "@battle_start_se", "@escape_se", "@actor_collapse_se", "@enemy_collapse_se", "@words", "@test_battlers", "@test_troop_id", "@start_map_id", "@start_x", "@start_y", "@battleback_name", "@battler_name", "@battler_hue", "@edit_map_id"]),
  "RPG::System::Words" => Set.new(["@gold", "@hp", "@sp", "@str", "@dex", "@agi", "@int", "@atk", "@pdef", "@mdef", "@weapon", "@armor1", "@armor2", "@armor3", "@armor4", "@attack", "@skill", "@guard", "@item", "@equip"]),
  "RPG::System::TestBattler" => Set.new(["@actor_id", "@level", "@weapon_id", "@armor1_id", "@armor2_id", "@armor3_id", "@armor4_id"]),
  "RPG::AudioFile" => Set.new(["@name", "@volume", "@pitch"]),
  "Rect" => Set.new(["@x", "@y", "@width", "@height"]),
  "Tone" => Set.new(["@red", "@green", "@blue", "@gray"]),
  "Color" => Set.new(["@red", "@green", "@blue", "@alpha"]),
  "Table" => Set.new(["@dims", "@xsize", "@ysize", "@zsize", "@data"]), # 使用原始 Unpacker 的属性名
}.freeze
IGNORABLE_MISSING_IVARS_BY_CLASS_RGSS1 = {
  "Table" => Set.new(["@data", "@dims", "@xsize", "@ysize", "@zsize"]),
  "Color" => Set.new(["@red", "@green", "@blue", "@alpha"]),
  "Tone" => Set.new(["@red", "@green", "@blue", "@gray"]),
  "Rect" => Set.new(["@x", "@y", "@width", "@height"]),
  "RPG::Skill" => Set.new(["@icon_name", "@description"]),
  "RPG::Item" => Set.new(["@icon_name", "@description"]),
  "RPG::Weapon" => Set.new(["@icon_name", "@description"]),
  "RPG::Armor" => Set.new(["@icon_name", "@description"]),
}.freeze

# --- RGSS2 (VX) 结构定义 (已重构) ---
EXPECTED_RGSS2_STRUCTURES = {}.tap do |h|
  # --- 定义基类概念 (用于结构定义，不代表严格的脚本继承) ---
  h["RPG::BaseItem"] = Set.new(["@id", "@name", "@icon_index", "@description", "@note"])
  h["RPG::UsableItem"] = h["RPG::BaseItem"] | Set.new([
    "@scope", "@occasion", "@speed", "@animation_id", "@common_event_id",
    "@base_damage", "@variance", "@atk_f", "@spi_f", "@physical_attack",
    "@damage_to_mp", "@absorb_damage", "@ignore_defense",
    "@element_set", "@plus_state_set", "@minus_state_set",
  ])

  # --- 定义子类 ---
  h["RPG::Skill"] = h["RPG::UsableItem"] | Set.new([
    "@mp_cost", "@hit", "@message1", "@message2",
  ])
  h["RPG::Item"] = h["RPG::UsableItem"] | Set.new([
    "@price", "@consumable", "@hp_recovery_rate", "@hp_recovery",
    "@mp_recovery_rate", "@mp_recovery", "@parameter_type", "@parameter_points",
  ])
  h["RPG::Weapon"] = h["RPG::BaseItem"] | Set.new([
    "@animation_id", "@price", "@hit", "@atk", "@def", "@spi", "@agi",
    "@two_handed", "@fast_attack", "@dual_attack", "@critical_bonus",
    "@element_set", "@state_set", # 注意: VX Weapon 有 element_set 和 state_set
  ])
  h["RPG::Armor"] = h["RPG::BaseItem"] | Set.new([
    "@kind", "@price", "@eva", "@atk", "@def", "@spi", "@agi",
    "@prevent_critical", "@half_mp_cost", "@double_exp_gain", "@auto_hp_recover",
    "@element_set", "@state_set", # 注意: VX Armor 有 element_set 和 state_set
  ])

  # --- 定义其他非继承自 BaseItem 的类 ---
  h["RPG::Actor"] = Set.new([ # Actor 在 VX 中不直接继承 BaseItem
    "@id", "@name", "@class_id", "@initial_level", "@exp_basis", "@exp_inflation",
    "@character_name", "@character_index", "@face_name", "@face_index",
    "@parameters", "@weapon_id", "@armor1_id", "@armor2_id", "@armor3_id", "@armor4_id",
    "@two_swords_style", "@fix_equipment", "@auto_battle", "@super_guard",
    "@pharmacology", "@critical_bonus",
  ])
  h["RPG::Class"] = Set.new([ # Class 在 VX 中不直接继承 BaseItem
    "@id", "@name", "@position", "@weapon_set", "@armor_set",
    "@element_ranks", "@state_ranks", "@learnings", "@skill_name_valid", "@skill_name",
  ])
  h["RPG::Class::Learning"] = Set.new(["@level", "@skill_id"])
  h["RPG::Enemy"] = Set.new([ # Enemy 在 VX 中不直接继承 BaseItem
    "@id", "@name", "@battler_name", "@battler_hue", "@maxhp", "@maxmp",
    "@atk", "@def", "@spi", "@agi", "@hit", "@eva", "@exp", "@gold",
    "@drop_item1", "@drop_item2", "@levitate", "@has_critical",
    "@element_ranks", "@state_ranks", "@actions", "@note", # Enemy 有 note
  ])
  h["RPG::Enemy::DropItem"] = Set.new(["@kind", "@item_id", "@weapon_id", "@armor_id", "@denominator"])
  h["RPG::Enemy::Action"] = Set.new(["@kind", "@basic", "@skill_id", "@condition_type", "@condition_param1", "@condition_param2", "@rating"])
  h["RPG::State"] = Set.new([ # State 在 VX 中不直接继承 BaseItem
    "@id", "@name", "@icon_index", "@restriction", "@priority", # State 有 icon_index
    "@atk_rate", "@def_rate", "@spi_rate", "@agi_rate", "@nonresistance",
    "@offset_by_opposite", "@slip_damage", "@reduce_hit_ratio", # reduce_hit_ratio 存在吗？检查文档，似乎不存在，移除
    "@battle_only", "@release_by_damage", "@hold_turn", "@auto_release_prob",
    "@message1", "@message2", "@message3", "@message4",
    "@element_set", "@state_set", "@note", # State 有 note
  ])
  # 修正: 移除不存在的 @reduce_hit_ratio
  h["RPG::State"] = Set.new([
    "@id", "@name", "@icon_index", "@restriction", "@priority",
    "@atk_rate", "@def_rate", "@spi_rate", "@agi_rate", "@nonresistance",
    "@offset_by_opposite", "@slip_damage", # 移除 @reduce_hit_ratio
    "@battle_only", "@release_by_damage", "@hold_turn", "@auto_release_prob",
    "@message1", "@message2", "@message3", "@message4",
    "@element_set", "@state_set", "@note",
  ])

  # --- 定义 Area ---
  h["RPG::Area"] = Set.new(["@id", "@name", "@map_id", "@rect", "@encounter_list", "@order"])

  # --- 定义 Animation ---
  h["RPG::Animation"] = Set.new([
    "@id", "@name", "@animation1_name", "@animation1_hue",
    "@animation2_name", "@animation2_hue", "@position", "@frame_max",
    "@frames", "@timings",
  ])
  h["RPG::Animation::Frame"] = Set.new(["@cell_max", "@cell_data"])
  h["RPG::Animation::Timing"] = Set.new(["@frame", "@se", "@flash_scope", "@flash_color", "@flash_duration"])

  # --- 定义 CommonEvent ---
  h["RPG::CommonEvent"] = Set.new(["@id", "@name", "@trigger", "@switch_id", "@list"])

  # --- 定义 Event 相关 ---
  h["RPG::Event"] = Set.new(["@id", "@name", "@x", "@y", "@pages"])
  h["RPG::Event::Page"] = Set.new([
    "@condition", "@graphic", "@move_type", "@move_speed", "@move_frequency",
    "@move_route", "@walk_anime", "@step_anime", "@direction_fix", "@through",
    "@priority_type", "@trigger", "@list",
  ])
  h["RPG::Event::Page::Condition"] = Set.new([
    "@switch1_valid", "@switch2_valid", "@variable_valid", "@self_switch_valid",
    "@item_valid", "@actor_valid", "@switch1_id", "@switch2_id", "@variable_id",
    "@variable_value", "@self_switch_ch", "@item_id", "@actor_id",
  ])
  h["RPG::Event::Page::Graphic"] = Set.new([
    "@tile_id", "@character_name", "@character_index", "@direction", "@pattern",
  ])
  h["RPG::EventCommand"] = Set.new(["@code", "@indent", "@parameters"])

  # --- 定义 Map 相关 ---
  h["RPG::Map"] = Set.new([
    "@width", "@height", "@scroll_type", "@autoplay_bgm", "@bgm",
    "@autoplay_bgs", "@bgs", "@disable_dashing", "@encounter_list",
    "@encounter_step", "@parallax_name", "@parallax_loop_x", "@parallax_loop_y",
    "@parallax_sx", "@parallax_sy", "@parallax_show", "@data", "@events",
  ])
  h["RPG::MapInfo"] = Set.new(["@name", "@parent_id", "@order", "@expanded", "@scroll_x", "@scroll_y"])

  # --- 定义 Move 相关 ---
  h["RPG::MoveRoute"] = Set.new(["@repeat", "@skippable", "@wait", "@list"])
  h["RPG::MoveCommand"] = Set.new(["@code", "@parameters"])

  # --- 定义 Troop 相关 ---
  h["RPG::Troop"] = Set.new(["@id", "@name", "@members", "@pages"])
  h["RPG::Troop::Member"] = Set.new(["@enemy_id", "@x", "@y", "@hidden", "@immortal"])
  h["RPG::Troop::Page"] = Set.new(["@condition", "@span", "@list"])
  h["RPG::Troop::Page::Condition"] = Set.new([
    "@turn_ending", "@turn_valid", "@enemy_valid", "@actor_valid",
    "@switch_valid", "@turn_a", "@turn_b", "@enemy_index", "@enemy_hp",
    "@actor_id", "@actor_hp", "@switch_id",
  ])

  # --- 定义 System 相关 ---
  h["RPG::System"] = Set.new([
    "@game_title", "@version_id", "@party_members", "@elements",
    "@switches", "@variables", "@passages", "@boat", "@ship", "@airship",
    "@title_bgm", "@battle_bgm", "@battle_end_me", "@gameover_me",
    "@sounds", "@test_battlers", "@test_troop_id", "@start_map_id",
    "@start_x", "@start_y", "@terms", "@battler_name", "@battler_hue", "@edit_map_id",
  ])
  h["RPG::System::Vehicle"] = Set.new([
    "@character_name", "@character_index", "@bgm",
    "@start_map_id", "@start_x", "@start_y",
  ])
  h["RPG::System::Terms"] = Set.new([
    "@level", "@level_a", "@hp", "@hp_a", "@mp", "@mp_a",
    "@atk", "@def", "@spi", "@agi", "@weapon", "@armor1", "@armor2",
    "@armor3", "@armor4", "@weapon1", "@weapon2", "@attack", "@skill",
    "@guard", "@item", "@equip", "@status", "@save", "@game_end",
    "@fight", "@escape", "@new_game", "@continue", "@shutdown",
    "@to_title", "@cancel", "@gold",
  ])
  h["RPG::System::TestBattler"] = Set.new([
    "@actor_id", "@level", "@weapon_id", "@armor1_id",
    "@armor2_id", "@armor3_id", "@armor4_id",
  ])

  # --- 定义音频文件 ---
  h["RPG::AudioFile"] = Set.new(["@name", "@volume", "@pitch"])
  h["RPG::BGM"] = h["RPG::AudioFile"].clone
  h["RPG::BGS"] = h["RPG::AudioFile"].clone
  h["RPG::ME"] = h["RPG::AudioFile"].clone
  h["RPG::SE"] = h["RPG::AudioFile"].clone

  # --- 定义通用数据结构 ---
  h["Rect"] = Set.new(["@x", "@y", "@width", "@height"])
  h["Tone"] = Set.new(["@red", "@green", "@blue", "@gray"])
  h["Color"] = Set.new(["@red", "@green", "@blue", "@alpha"])
  h["Table"] = Set.new(["@dims", "@xsize", "@ysize", "@zsize", "@data"])
end.freeze

IGNORABLE_MISSING_IVARS_BY_CLASS_RGSS2 = {
  "Table" => Set.new(["@data", "@dims", "@xsize", "@ysize", "@zsize"]),
  "Color" => Set.new(["@red", "@green", "@blue", "@alpha"]),
  "Tone" => Set.new(["@red", "@green", "@blue", "@gray"]),
  "Rect" => Set.new(["@x", "@y", "@width", "@height"]),
  # VX 中继承自 BaseItem 的字段，如果编辑器中为空，也可能不写入
  "RPG::Skill" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::Item" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::Weapon" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::Armor" => Set.new(["@icon_index", "@description", "@note"]),
  # Enemy 和 State 在 VX 中虽然不继承 BaseItem，但也有可能为空的 @note
  "RPG::Enemy" => Set.new(["@note"]),
  "RPG::State" => Set.new(["@note"]),
}.freeze

# --- RGSS3 (VX Ace) 结构定义 ---
EXPECTED_RGSS3_STRUCTURES = {}.tap do |h|
  # --- 先定义基类 ---
  h["RPG::BaseItem"] = Set.new(["@id", "@name", "@icon_index", "@description", "@features", "@note"])
  h["RPG::UsableItem"] = h["RPG::BaseItem"] | Set.new(["@scope", "@occasion", "@speed", "@success_rate", "@repeats", "@tp_gain", "@hit_type", "@animation_id", "@damage", "@effects"])
  h["RPG::EquipItem"] = h["RPG::BaseItem"] | Set.new(["@price", "@etype_id", "@params"])
  # --- 定义子类, 合并父类实例变量 ---
  h["RPG::Actor"] = h["RPG::BaseItem"] | Set.new(["@nickname", "@class_id", "@initial_level", "@max_level", "@character_name", "@character_index", "@face_name", "@face_index", "@equips"])
  h["RPG::Class"] = h["RPG::BaseItem"] | Set.new(["@exp_params", "@params", "@learnings"])
  h["RPG::Class::Learning"] = Set.new(["@level", "@skill_id", "@note"])
  h["RPG::Skill"] = h["RPG::UsableItem"] | Set.new(["@stype_id", "@mp_cost", "@tp_cost", "@message1", "@message2", "@required_wtype_id1", "@required_wtype_id2"])
  h["RPG::Item"] = h["RPG::UsableItem"] | Set.new(["@itype_id", "@price", "@consumable"])
  h["RPG::Weapon"] = h["RPG::EquipItem"] | Set.new(["@wtype_id", "@animation_id"])
  h["RPG::Armor"] = h["RPG::EquipItem"] | Set.new(["@atype_id"])
  h["RPG::Enemy"] = h["RPG::BaseItem"] | Set.new(["@battler_name", "@battler_hue", "@params", "@exp", "@gold", "@drop_items", "@actions"])
  h["RPG::Enemy::DropItem"] = Set.new(["@kind", "@data_id", "@denominator"])
  h["RPG::Enemy::Action"] = Set.new(["@skill_id", "@condition_type", "@condition_param1", "@condition_param2", "@rating"])
  h["RPG::State"] = h["RPG::BaseItem"] | Set.new(["@restriction", "@priority", "@remove_at_battle_end", "@remove_by_restriction", "@auto_removal_timing", "@min_turns", "@max_turns", "@remove_by_damage", "@chance_by_damage", "@remove_by_walking", "@steps_to_remove", "@message1", "@message2", "@message3", "@message4"])
  # --- 其他类 ---
  h["RPG::Map"] = Set.new(["@display_name", "@tileset_id", "@width", "@height", "@scroll_type", "@specify_battleback", "@battleback1_name", "@battleback2_name", "@autoplay_bgm", "@bgm", "@autoplay_bgs", "@bgs", "@disable_dashing", "@encounter_list", "@encounter_step", "@parallax_name", "@parallax_loop_x", "@parallax_loop_y", "@parallax_sx", "@parallax_sy", "@parallax_show", "@note", "@data", "@events"])
  h["RPG::Map::Encounter"] = Set.new(["@troop_id", "@weight", "@region_set"])
  h["RPG::MapInfo"] = Set.new(["@name", "@parent_id", "@order", "@expanded", "@scroll_x", "@scroll_y"])
  h["RPG::Event"] = Set.new(["@id", "@name", "@x", "@y", "@pages"])
  h["RPG::Event::Page"] = Set.new(["@condition", "@graphic", "@move_type", "@move_speed", "@move_frequency", "@move_route", "@walk_anime", "@step_anime", "@direction_fix", "@through", "@priority_type", "@trigger", "@list"])
  h["RPG::Event::Page::Condition"] = Set.new(["@switch1_valid", "@switch2_valid", "@variable_valid", "@self_switch_valid", "@item_valid", "@actor_valid", "@switch1_id", "@switch2_id", "@variable_id", "@variable_value", "@self_switch_ch", "@item_id", "@actor_id"])
  h["RPG::Event::Page::Graphic"] = Set.new(["@tile_id", "@character_name", "@character_index", "@direction", "@pattern"])
  h["RPG::EventCommand"] = Set.new(["@code", "@indent", "@parameters"])
  h["RPG::MoveRoute"] = Set.new(["@repeat", "@skippable", "@wait", "@list"])
  h["RPG::MoveCommand"] = Set.new(["@code", "@parameters"])
  h["RPG::Troop"] = Set.new(["@id", "@name", "@members", "@pages"])
  h["RPG::Troop::Member"] = Set.new(["@enemy_id", "@x", "@y", "@hidden"])
  h["RPG::Troop::Page"] = Set.new(["@condition", "@span", "@list"])
  h["RPG::Troop::Page::Condition"] = Set.new(["@turn_ending", "@turn_valid", "@enemy_valid", "@actor_valid", "@switch_valid", "@turn_a", "@turn_b", "@enemy_index", "@enemy_hp", "@actor_id", "@actor_hp", "@switch_id"])
  h["RPG::Animation"] = Set.new(["@id", "@name", "@animation1_name", "@animation1_hue", "@animation2_name", "@animation2_hue", "@position", "@frame_max", "@frames", "@timings"])
  h["RPG::Animation::Frame"] = Set.new(["@cell_max", "@cell_data"])
  h["RPG::Animation::Timing"] = Set.new(["@frame", "@se", "@flash_scope", "@flash_color", "@flash_duration"])
  h["RPG::Tileset"] = Set.new(["@id", "@mode", "@name", "@tileset_names", "@flags", "@note"])
  h["RPG::CommonEvent"] = Set.new(["@id", "@name", "@trigger", "@switch_id", "@list"])
  # --- System 及子类 ---
  h["RPG::System"] = Set.new(["@game_title", "@version_id", "@japanese", "@party_members", "@currency_unit", "@elements", "@skill_types", "@weapon_types", "@armor_types", "@switches", "@variables", "@boat", "@ship", "@airship", "@title1_name", "@title2_name", "@opt_draw_title", "@opt_use_midi", "@opt_transparent", "@opt_followers", "@opt_slip_death", "@opt_floor_death", "@opt_display_tp", "@opt_extra_exp", "@window_tone", "@title_bgm", "@battle_bgm", "@battle_end_me", "@gameover_me", "@sounds", "@test_battlers", "@test_troop_id", "@start_map_id", "@start_x", "@start_y", "@terms", "@battleback1_name", "@battleback2_name", "@battler_name", "@battler_hue", "@edit_map_id"])
  h["RPG::System::Vehicle"] = Set.new(["@character_name", "@character_index", "@bgm", "@start_map_id", "@start_x", "@start_y"])
  h["RPG::System::Terms"] = Set.new(["@basic", "@params", "@etypes", "@commands"])
  h["RPG::System::TestBattler"] = Set.new(["@actor_id", "@level", "@equips"])
  # --- 音频文件 ---
  h["RPG::AudioFile"] = Set.new(["@name", "@volume", "@pitch"])
  h["RPG::BGM"] = h["RPG::AudioFile"].clone
  h["RPG::BGS"] = h["RPG::AudioFile"].clone
  h["RPG::ME"] = h["RPG::AudioFile"].clone
  h["RPG::SE"] = h["RPG::AudioFile"].clone
  # --- 基础 RPG Maker 数据结构 ---
  h["RPG::BaseItem::Feature"] = Set.new(["@code", "@data_id", "@value"])
  h["RPG::UsableItem::Damage"] = Set.new(["@type", "@element_id", "@formula", "@variance", "@critical"])
  h["RPG::UsableItem::Effect"] = Set.new(["@code", "@data_id", "@value1", "@value2"])
  # --- 通用数据结构 ---
  h["Rect"] = Set.new(["@x", "@y", "@width", "@height"])
  h["Tone"] = Set.new(["@red", "@green", "@blue", "@gray"])
  h["Color"] = Set.new(["@red", "@green", "@blue", "@alpha"])
  h["Table"] = Set.new(["@dims", "@xsize", "@ysize", "@zsize", "@data"])
end.freeze
IGNORABLE_MISSING_IVARS_BY_CLASS_RGSS3 = {
  "Table" => Set.new(["@data", "@dims", "@xsize", "@ysize", "@zsize"]),
  "Color" => Set.new(["@red", "@green", "@blue", "@alpha"]),
  "Tone" => Set.new(["@red", "@green", "@blue", "@gray"]),
  "Rect" => Set.new(["@x", "@y", "@width", "@height"]),
  # 继承自 RPG::BaseItem 的字段，如果编辑器中为空，可能不会写入数据文件
  "RPG::Actor" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::Class" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::Enemy" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::State" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::Skill" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::Item" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::Weapon" => Set.new(["@icon_index", "@description", "@note"]),
  "RPG::Armor" => Set.new(["@icon_index", "@description", "@note"]),
}.freeze

# --- RGSS 版本配置聚合 ---
RGSS_CONFIG = {
  1 => {
    name: "RGSS1 (XP)",
    extension: ".rxdata",
    structures: EXPECTED_RGSS1_STRUCTURES,
    ignorable_ivars: IGNORABLE_MISSING_IVARS_BY_CLASS_RGSS1,
    files_to_validate: DEFAULT_FILES_TO_VALIDATE,
    log_map_details: true, # XP Map 通常问题较多，默认开启
  },
  2 => {
    name: "RGSS2 (VX)",
    extension: ".rvdata",
    structures: EXPECTED_RGSS2_STRUCTURES, # 使用重构后的定义
    ignorable_ivars: IGNORABLE_MISSING_IVARS_BY_CLASS_RGSS2,
    files_to_validate: DEFAULT_FILES_TO_VALIDATE,
    log_map_details: LOG_MAP_DETAILS_IF_ERRORS_DEFAULT,
  },
  3 => {
    name: "RGSS3 (VX Ace)",
    extension: ".rvdata2",
    structures: EXPECTED_RGSS3_STRUCTURES,
    ignorable_ivars: IGNORABLE_MISSING_IVARS_BY_CLASS_RGSS3,
    files_to_validate: DEFAULT_FILES_TO_VALIDATE,
    log_map_details: true, # VX Ace Map 也可能复杂，默认开启
  },
}.freeze

# --- 全局变量 ---
$defined_placeholder_classes = Set.new # 记录已动态定义的占位符类/模块
$logger = nil                         # 日志记录器实例
$log_file_handle = nil                # 日志文件句柄
$validation_errors_found_global_flag = false # 全局标记，指示是否发现任何验证错误
$error_file_basenames = Set.new        # 记录所有发现问题的文件基本名
$log_file_path = nil                  # 日志文件的完整路径

# --- 当前选择的 RGSS 版本配置 (将在版本确定后设置) ---
$current_rgss_config = nil

# --- 定义验证错误结构体 (通用) ---
ValidationError = Struct.new(:type, :path, :class_name, :details, :filename)
# type: 错误类型 (Symbol, e.g., :missing_ivar, :unexpected_class)
# path: 错误发生的对象路径 (String, e.g., "root.pages[0].list[5]")
# class_name: 发生错误的对象所属的类名 (String or nil)
# details: 错误的详细信息 (通常是实例变量列表 Array/Set 或错误消息 String)
# filename: 发生错误的文件基本名 (String)

# --- 日志记录器设置 (通用) ---
def setup_logger
  begin
    log_dir_path = Pathname.new(LOG_DIR)
    log_dir_path.mkpath unless log_dir_path.directory?
    time_str = Time.now.strftime("%Y%m%d_%H%M%S")
    # 使用选定版本的简称生成日志文件名
    version_tag = $current_rgss_config[:name].match(/\((.*?)\)/)&.captures&.first&.downcase || "rgss#{$current_rgss_config[:version]}" || "unknown"
    log_filename = "#{version_tag}_validation_#{time_str}.log"

    $log_file_path = log_dir_path.join(log_filename)
    $log_file_handle = File.open($log_file_path, "w")
    $log_file_handle.set_encoding("UTF-8") # 确保写入 UTF-8
    $logger = Logger.new($log_file_handle)
    $logger.level = LOG_LEVEL
    # 自定义日志格式
    $logger.formatter = proc do |severity, datetime, progname, msg|
      formatted_msg = begin
          msg.is_a?(String) ? msg.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?") : msg.to_s
        rescue => e
          "[日志编码错误: #{e.message}] #{msg.inspect rescue "无法检查的对象"}"
        end
      "#{datetime.strftime("%Y-%m-%d %H:%M:%S")} [#{severity}] #{formatted_msg}\n"
    end
    $stdout.set_encoding("UTF-8") rescue nil # 尝试设置标准输出为 UTF-8
    puts "日志文件已创建: #{$log_file_path.expand_path}"
    $logger.info("--- #{$current_rgss_config[:name]} 结构验证脚本开始 ---")
    $logger.info("选择的版本: #{$current_rgss_config[:version]} (#{$current_rgss_config[:name]})")
    $logger.info("日志时间: #{Time.now}")
    $logger.info("日志级别设置为: #{Logger::SEV_LABEL[LOG_LEVEL]}")
  rescue SystemCallError => e # 更具体的异常捕获
    STDERR.set_encoding("UTF-8") rescue nil
    STDERR.puts "[致命错误] 无法设置或写入日志文件 '#{$log_file_path || log_filename rescue "日志文件"}': #{e.message} (错误码: #{e.errno})"
    exit(1)
  rescue => e
    STDERR.set_encoding("UTF-8") rescue nil
    STDERR.puts "[致命错误] 初始化日志时发生未知错误: #{e.class}: #{e.message}"
    STDERR.puts e.backtrace.first(5).join("\n")
    exit(1)
  end
end

# 脚本退出时确保关闭日志文件 (通用)
at_exit do
  if $log_file_handle && !$log_file_handle.closed?
    $logger&.info("--- #{$current_rgss_config ? $current_rgss_config[:name] : "未知版本"} 结构验证脚本结束 ---")
    $log_file_handle.close
  end
end

# --- 占位符定义 (依赖 $current_rgss_config) ---
def check_expected_entity(full_name)
  # 允许 RPG 模块本身以及在当前版本结构定义中的类/模块
  $current_rgss_config[:structures].key?(full_name) || full_name == "RPG"
end

def define_strict_placeholder(full_name)
  unless check_expected_entity(full_name)
    $logger.error("错误: Marshal 数据请求了未知的类/模块 '#{full_name}'，这不符合预期的 #{$current_rgss_config[:name]} 结构。")
    return false
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
  true
end

def create_minimal_placeholder(parent_scope, const_sym, full_name, is_class)
  # --- 修改: 添加日志记录 ---
  # 仅在首次为这个名称创建占位符时记录日志
  unless $defined_placeholder_classes.include?(full_name)
    $logger.info("[占位符定义] 动态创建了 #{$current_rgss_config[:name]} 占位符: #{full_name}")
  end
  # --- 修改结束 ---

  new_entity = nil
  if parent_scope.const_defined?(const_sym, false)
    existing = parent_scope.const_get(const_sym)
    is_our_placeholder = existing.is_a?(Class) && existing.instance_variable_defined?(:@_placeholder_name) && existing.instance_variable_get(:@_placeholder_name) == full_name
    return existing if is_our_placeholder
    return existing if !is_class && existing.is_a?(Module)
    begin
      parent_scope.send(:remove_const, const_sym)
    rescue NameError
      # Ignore
    end
  end

  begin
    klass_name_for_methods = full_name
    if is_class
      new_entity = Class.new do
        @_placeholder_name = klass_name_for_methods

        def self._load(data)
          allocate
        end

        def initialize(*_args)
          @_placeholder_name_inst = self.class.instance_variable_get(:@_placeholder_name) rescue "UnknownPlaceholder"
        end

        def inspect
          klass_name = @_placeholder_name_inst || (self.class.instance_variable_get(:@_placeholder_name) rescue self.class.name rescue "AnonPlaceholder")
          ivars_str = instance_variables.reject { |v| v.to_s.start_with?("@_") }.map { |ivar|
            begin
              value = instance_variable_get(ivar)
              value_inspect = value.inspect
              if value.is_a?(String) && value.bytesize > 50 && (!value.valid_encoding? || value.bytes.any? { |b| b < 32 && ![9, 10, 13].include?(b) } || value.bytes.include?(0))
                value_inspect = "[String len=#{value.bytesize}]"
              elsif value_inspect.length > 80
                value_inspect = value_inspect[0, 80] + "..."
              end
            rescue => e
              value_inspect = "[检查错误: #{e.message}]"
            end
            "#{ivar}=#{value_inspect}"
          }.join(", ")
          "<占位符(#{klass_name}) #{ivars_str}>"
        end

        define_singleton_method(:name) { klass_name_for_methods }
        define_singleton_method(:to_s) { klass_name_for_methods }
      end
    else
      new_entity = Module.new do
        define_singleton_method(:name) { klass_name_for_methods }
        define_singleton_method(:to_s) { klass_name_for_methods }
      end
    end

    parent_scope.const_set(const_sym, new_entity)
    return new_entity
  rescue => e
    $logger.error("创建或设置占位符 '#{full_name}' 时失败: #{e.class}: #{e.message}")
    return nil
  end
end

# --- 加载单个数据文件 (依赖 $current_rgss_config) ---
def load_data_for_validation(filepath, log_details: true)
  basename = File.basename(filepath)
  $logger.info("--- 开始加载 Marshal 文件进行验证: #{basename} ---") if log_details || $logger.debug?
  loaded_data = nil
  retries = 0
  failed_strict_defines = Set.new

  loop do
    begin
      file_content = File.binread(filepath)
      loaded_data = Marshal.load(file_content)
      $logger.info("Marshal.load 完成: #{basename}") if log_details || $logger.debug?
      break # 成功
    rescue ArgumentError => e
      match_data = e.message.match(/undefined class\/module (\S+)/)
      if match_data && retries < MAX_RETRIES
        original_request_name = match_data[1]
        normalized_entity_name = original_request_name.chomp("::")
        if normalized_entity_name != original_request_name && $logger.debug?
          $logger.debug("规范化 Marshal 请求 '#{original_request_name}' 为 '#{normalized_entity_name}'")
        end

        is_rpg_module_itself = (normalized_entity_name == "RPG")
        is_rpg_related = normalized_entity_name.start_with?("RPG::") || is_rpg_module_itself
        is_expected = check_expected_entity(normalized_entity_name) # 使用当前配置检查

        if is_expected
          $logger.warn("尝试定义: 遇到预期但未定义的 #{$current_rgss_config[:name]} 实体: #{original_request_name} (文件: #{basename}, 尝试次数 #{retries + 1}/#{MAX_RETRIES})")

          if is_rpg_related && !Object.const_defined?(:RPG)
            $logger.info("依赖检查: 定义 RPG 模块 (请求者: #{original_request_name} in #{basename})...")
            unless create_minimal_placeholder(Object, :RPG, "RPG", false)
              $logger.error("致命错误: 无法创建基础 RPG 模块，停止加载 #{basename}。")
              $validation_errors_found_global_flag = true; return nil
            end
            $defined_placeholder_classes.add("RPG")
          end

          unless is_rpg_module_itself
            if failed_strict_defines.include?(normalized_entity_name)
              $logger.error("错误: 之前尝试严格定义 #{normalized_entity_name} 失败，无法继续加载 #{basename}。")
              $validation_errors_found_global_flag = true; return nil
            end

            unless define_strict_placeholder(normalized_entity_name)
              $logger.error("无法定义预期的占位符 #{normalized_entity_name}，停止加载 #{basename}.")
              failed_strict_defines.add(normalized_entity_name)
              $validation_errors_found_global_flag = true; return nil
            end
          else
            $logger.debug("跳过对基础模块 '#{normalized_entity_name}' 的严格占位符定义 (已处理)") if $logger.debug?
          end

          retries += 1
          next
        else
          $logger.error("验证错误 (#{basename}): Marshal 数据需要一个非 #{$current_rgss_config[:name]} 标准的类/模块: '#{original_request_name}' (规范化为 '#{normalized_entity_name}' 后仍未在预期列表中找到)")
          $validation_errors_found_global_flag = true; return nil
        end
      else
        error_source = match_data ? "'#{match_data[1]}'" : "未知实体"
        reason = e.message
        $logger.error("Marshal.load 失败 (#{basename})。原因: #{reason}")
        if match_data && retries >= MAX_RETRIES
          $logger.error("已达到最大重试次数 (#{MAX_RETRIES})，仍无法加载所需的实体 #{error_source} in #{basename}")
        elsif reason.include?("marshal data too short") || reason.include?("invalid marshal format") || reason.include?("incompatible marshal file format")
          $logger.error("提示：文件 #{basename} 可能已损坏或与当前 Ruby Marshal 版本不兼容。")
        end
        $validation_errors_found_global_flag = true; return nil
      end
    rescue TypeError, EncodingError => e
      $logger.error("Marshal.load 时发生 #{e.class} (#{basename}): #{e.message}")
      $validation_errors_found_global_flag = true; return nil
    rescue => e
      $logger.error("读取或解析 Marshal 文件 #{basename} 时发生未知错误: #{e.class}: #{e.message}")
      $logger.error(e.backtrace.first(5).join("\n"))
      $validation_errors_found_global_flag = true; return nil
    end
  end # loop end

  loaded_data
end

# --- 递归结构验证 (依赖 $current_rgss_config) ---
def validate_structure(path, obj, validation_results, log_path: "root", filename: "UnknownFile")
  return true if obj.nil? || obj.is_a?(Symbol) || obj.is_a?(Numeric) || obj.is_a?(TrueClass) || obj.is_a?(FalseClass) || obj.is_a?(String)

  if obj.is_a?(Array)
    all_valid = true
    obj.each_with_index do |item, i|
      is_item_valid = validate_structure("#{path}[#{i}]", item, validation_results, log_path: "#{log_path}[#{i}]", filename: filename)
      all_valid &&= is_item_valid
    end
    return all_valid
  elsif obj.is_a?(Hash)
    all_valid = true
    obj.each do |key, value|
      key_repr = key.inspect rescue "[错误键]"
      is_value_valid = validate_structure("#{path}[#{key_repr}]", value, validation_results, log_path: "#{log_path}[#{key_repr}]", filename: filename)
      all_valid &&= is_value_valid
    end
    return all_valid
  end

  obj_class = obj.class
  class_name = obj_class.name rescue nil
  class_is_defined = false
  begin
    class_is_defined = Object.const_defined?(class_name) if class_name && !class_name.empty?
  rescue NameError
    class_is_defined = false
  end

  if class_name.nil? || class_name.empty? || !class_is_defined
    intended_name = obj.instance_variable_get(:@_placeholder_name_inst) if obj.respond_to?(:instance_variable_defined?) && obj.instance_variable_defined?(:@_placeholder_name_inst)
    if intended_name && !intended_name.empty?
      class_name = intended_name
    end
  end

  unless class_name && !class_name.empty?
    error_details = "无法确定类名的对象: #{obj.inspect[0..200]}"
    validation_results << ValidationError.new(:unknown_class, log_path, nil, error_details, filename)
    $validation_errors_found_global_flag = true
    $error_file_basenames.add(filename)
    return false
  end

  # 使用当前配置检查类
  expected_ivars = $current_rgss_config[:structures][class_name]
  unless expected_ivars
    error_details = "发现意外的类: #{class_name}"
    validation_results << ValidationError.new(:unexpected_class, log_path, class_name, error_details, filename)
    $validation_errors_found_global_flag = true
    $error_file_basenames.add(filename)
    return false
  end

  structure_valid = true
  begin
    actual_ivars = obj.instance_variables.map(&:to_s).to_set
    actual_ivars.delete("@_placeholder_name_inst")
  rescue => e
    error_details = "检查对象 (#{class_name}) 的实例变量时出错: #{e.message}"
    validation_results << ValidationError.new(:ivar_check_error, log_path, class_name, error_details, filename)
    $logger.error("严重错误 (文件 '#{filename}#{$current_rgss_config[:extension]}', 路径 '#{log_path}'): #{error_details}")
    $validation_errors_found_global_flag = true
    $error_file_basenames.add(filename)
    return false
  end

  unexpected_ivars = actual_ivars - expected_ivars
  if unexpected_ivars.any?
    ivar_list = unexpected_ivars.to_a.sort
    validation_results << ValidationError.new(:unexpected_ivar, log_path, class_name, ivar_list, filename)
    structure_valid = false
    $validation_errors_found_global_flag = true
    $error_file_basenames.add(filename)
  end

  missing_ivars = expected_ivars - actual_ivars
  if missing_ivars.any?
    # 使用当前配置获取可忽略列表
    ignorable_missing_for_this_class = $current_rgss_config[:ignorable_ivars][class_name] || Set.new
    problematic_missing = missing_ivars - ignorable_missing_for_this_class

    if problematic_missing.any?
      ivar_list = problematic_missing.to_a.sort
      validation_results << ValidationError.new(:missing_ivar, log_path, class_name, ivar_list, filename)
      structure_valid = false
      $validation_errors_found_global_flag = true
      $error_file_basenames.add(filename)
    elsif missing_ivars.any? && $logger.debug?
      $logger.debug("调试 (文件 '#{filename}#{$current_rgss_config[:extension]}', 路径 '#{log_path}'): 对象 (#{class_name}) 跳过“缺少实例变量”检查 (均为可忽略): #{missing_ivars.to_a.sort.join(", ")}")
    end
  end

  ivars_to_check_recursively = actual_ivars & expected_ivars
  ivars_to_check_recursively.each do |ivar_name|
    ivar_sym = ivar_name.to_sym
    begin
      value = obj.instance_variable_get(ivar_sym)
      is_value_valid = validate_structure(ivar_name, value, validation_results, log_path: "#{log_path}.#{ivar_name.sub(/^@/, "")}", filename: filename)
      structure_valid &&= is_value_valid
    rescue => e
      error_details = "获取或验证对象 (#{class_name}) 的实例变量 #{ivar_name} 值时出错: #{e.message}"
      validation_results << ValidationError.new(:get_ivar_error, log_path, class_name, error_details, filename)
      $logger.error("严重错误 (文件 '#{filename}#{$current_rgss_config[:extension]}', 路径 '#{log_path}'): #{error_details}")
      structure_valid = false
      $validation_errors_found_global_flag = true
      $error_file_basenames.add(filename)
    end
  end

  structure_valid
end

# --- 格式化聚合错误消息的辅助函数 (通用) ---
def format_aggregated_error(key, agg_data)
  type, class_name, details_str = key
  count = agg_data[:count]
  first_path = agg_data[:first_path]

  details_display = details_str.split(",").join(", ")

  message_base = case type
    when :missing_ivar then "缺少预期实例变量: #{details_display}"
    when :unexpected_ivar then "发现意外实例变量: #{details_display}"
    when :unexpected_class then details_str # 包含 "发现意外的类: ClassName"
    when :unknown_class then details_str # 包含 "无法确定类名..."
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

# --- 自动检测 RGSS 版本 ---
def detect_rgss_version(target_dir)
  counts = { 1 => 0, 2 => 0, 3 => 0 }
  ext_map = { ".rxdata" => 1, ".rvdata" => 2, ".rvdata2" => 3 }

  begin
    Dir.glob(target_dir.join("*.r*data*")).each do |f|
      ext = File.extname(f).downcase
      if ext_map.key?(ext)
        counts[ext_map[ext]] += 1
      end
    end
  rescue SystemCallError => e
    STDERR.puts "[错误] 访问目录 '#{target_dir}' 时出错: #{e.message}"
    return nil
  end

  major_version = counts.select { |_, v| v > 0 }.max_by { |_, v| v }&.first

  if major_version
    puts "自动检测到主要文件类型为 RGSS#{major_version} (#{RGSS_CONFIG[major_version][:extension]})。"
    return major_version
  else
    STDERR.puts "[错误] 无法在目录 '#{target_dir}' 中检测到任何已知的 RGSS 数据文件扩展名 (.rxdata, .rvdata, .rvdata2)。"
    return nil
  end
end

# --- 提取出的处理单个文件的函数 ---
# 返回值: [Boolean] 是否成功处理且无错误
def process_validation_target(file_info, rule_info, global_rule_error_summary, rule_run_aggregated_errors)
  base_name = file_info[:base]
  file_path = file_info[:path]
  source_rule = rule_info[:rule]
  is_regex_rule = rule_info[:is_regex]
  file_extension = $current_rgss_config[:extension]
  log_map_details = $current_rgss_config[:log_map_details]
  file_had_issues = false

  # 决定此文件是否需要记录详细日志
  log_details_this_file = if is_regex_rule
      $logger.debug? || log_map_details
    else
      $logger.level <= Logger::INFO
    end

  if log_details_this_file
    rule_info_str = is_regex_rule ? "(匹配模式 #{source_rule.inspect})" : ""
    $logger.info("[开始验证] #{base_name}#{file_extension} #{rule_info_str}")
  end

  # --- 加载数据 ---
  data = load_data_for_validation(file_path.to_s, log_details: log_details_this_file)

  if data.nil?
    # 加载失败
    file_had_issues = true
    $error_file_basenames.add(base_name) # 全局记录
    global_rule_error_summary[source_rule][:error_files].add(base_name) # 记录到规则摘要
    unless log_details_this_file
      $logger.warn("[加载失败] #{base_name}#{file_extension} (详情请调高日志级别或检查日志文件)")
    end
  else
    # --- 结构验证 ---
    current_file_errors_structured = []
    validate_structure("root", data, current_file_errors_structured, log_path: "root", filename: base_name)

    # --- 聚合与日志记录 (文件级别) ---
    if current_file_errors_structured.any?
      file_had_issues = true
      $error_file_basenames.add(base_name) # 全局记录
      global_rule_error_summary[source_rule][:error_files].add(base_name) # 记录到规则摘要

      aggregated_errors_this_file = Hash.new { |h, k| h[k] = { count: 0, first_path: nil } }
      current_file_errors_structured.each do |error|
        details_key = case error.details
          when Array then error.details.sort.join(",")
          when Set then error.details.to_a.sort.join(",")
          else error.details.to_s
          end
        key = [error.type, error.class_name || "N/A", details_key]

        agg = aggregated_errors_this_file[key]
        agg[:count] += 1
        agg[:first_path] ||= error.path

        # 更新全局规则的常见错误计数
        global_rule_error_summary[source_rule][:common_errors][key] += 1
        # 如果是正则规则, 更新其运行期间的聚合错误
        if is_regex_rule
          rule_agg = rule_run_aggregated_errors[key]
          rule_agg[:count] += 1
          rule_agg[:files].add(base_name)
        end
      end # each error end

      if log_details_this_file
        $logger.warn("[验证发现结构问题] #{base_name}#{file_extension}:")
        aggregated_errors_this_file.each do |key, agg_data|
          $logger.warn("  - #{format_aggregated_error(key, agg_data)}")
        end
      elsif !is_regex_rule # 固定文件且未记录详细日志，记录通用警告
        $logger.warn("[验证发现问题] #{base_name}#{file_extension} (详情请调高日志级别或检查日志文件)")
      end
    end # if errors any end
  end # if data nil else end

  # 如果是固定文件，无问题，且记录了详细日志，则记录成功消息
  if !is_regex_rule && !file_had_issues && log_details_this_file
    $logger.info("[验证成功] #{base_name}#{file_extension}: 未发现需关注的问题。")
  end

  return !file_had_issues # 返回 true 表示成功且无问题
end

# --- 主程序逻辑 ---
options = {}
parser = OptionParser.new do |opts|
  opts.banner = "用法: ruby #{$0} <目录路径> [选项]"
  opts.separator ""
  opts.separator "选项:"

  opts.on("-v", "--version VERSION", Integer, "指定 RGSS 版本 (1=XP, 2=VX, 3=VX Ace)") do |v|
    if [1, 2, 3].include?(v)
      options[:version] = v
    else
      STDERR.puts "错误: 无效的版本号 '#{v}'。版本必须是 1, 2 或 3。"
      exit(1)
    end
  end

  opts.on_tail("-h", "--help", "显示此帮助信息") do
    puts opts
    exit
  end
end

begin
  parser.parse!
rescue OptionParser::MissingArgument => e
  STDERR.puts "错误: 选项 #{e.args.first} 需要一个参数。"
  puts parser; exit(1)
rescue OptionParser::InvalidOption => e
  STDERR.puts "错误: 无效选项 #{e.args.first}。"
  puts parser; exit(1)
end

if ARGV.length != 1
  STDERR.set_encoding("UTF-8") rescue nil
  STDERR.puts parser; exit 1
end

target_dir = Pathname.new(ARGV[0])
unless target_dir.directory?
  STDERR.set_encoding("UTF-8") rescue nil
  STDERR.puts "错误: 目录未找到或不是一个目录 - #{target_dir}"
  exit 1
end

# --- 确定 RGSS 版本并设置配置 ---
selected_rgss_version = nil
if options[:version]
  selected_rgss_version = options[:version]
  puts "用户指定验证 RGSS 版本: #{selected_rgss_version}"
else
  puts "未指定版本，尝试自动检测..."
  selected_rgss_version = detect_rgss_version(target_dir)
  unless selected_rgss_version
    STDERR.puts "自动检测失败。请使用 -v 或 --version 参数指定版本。"
    exit(1)
  end
end

# 设置全局配置对象
$current_rgss_config = RGSS_CONFIG[selected_rgss_version]
$current_rgss_config[:version] = selected_rgss_version # 添加版本号到配置中

# --- 初始化日志记录器 ---
setup_logger

# --- 记录版本特定的信息 ---
$logger.info("开始验证目录: #{target_dir.expand_path}")
$logger.info("验证规则 (#{$current_rgss_config[:name]}): #{$current_rgss_config[:files_to_validate].inspect}")
$logger.info("将忽略以下类中特定缺失的实例变量 (#{$current_rgss_config[:name]}):")
$current_rgss_config[:ignorable_ivars].each { |k, v| $logger.info("  - #{k}: #{v.to_a.sort.join(", ")}") }
$logger.info("=======================================")

validation_performed_count = 0
# 全局规则错误摘要: { rule => { error_files: Set[basename], common_errors: Hash[key => count] } }
global_rule_error_summary = Hash.new { |h, k| h[k] = { error_files: Set.new, common_errors: Hash.new(0) } }
file_extension = $current_rgss_config[:extension] # 获取当前文件扩展名

# --- 遍历验证规则 ---
$current_rgss_config[:files_to_validate].each do |rule|
  $logger.info("\n--- 处理规则: #{rule.inspect} ---")

  files_to_process = [] # 存储 { base:, path: }
  is_regex_rule = rule.is_a?(Regexp)
  rule_info = { rule: rule, is_regex: is_regex_rule } # 传递给处理函数的信息
  regex_processed_count = 0 # 正则规则处理计数
  regex_error_count = 0     # 正则规则错误计数
  # 本次规则运行的聚合错误: { key => { count:, files: Set[basename] } }
  rule_run_aggregated_errors = Hash.new { |h, k| h[k] = { count: 0, files: Set.new } }

  # --- 文件收集 ---
  if rule.is_a?(String)
    file_path = target_dir.join("#{rule}#{file_extension}")
    if file_path.file?
      files_to_process << { base: rule, path: file_path }
    else
      $logger.info("[信息] 未找到固定文件: #{file_path.basename}")
    end
  elsif is_regex_rule
    begin
      # 查找匹配模式且以正确扩展名结尾的文件
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
          files_to_process << { base: base, path: target_dir.join(fname) }
        end
      end
    rescue Errno::ENOENT => e
      $logger.error("访问目录 '#{target_dir}' 时出错: #{e.message}")
      next # 跳过此规则
    rescue => e
      $logger.error("处理规则 #{rule.inspect} 查找文件时发生错误: #{e.class}: #{e.message}")
      next # 跳过此规则
    end
  else
    $logger.warn("[警告] 未知的验证规则类型: #{rule.inspect}。已跳过。")
    next
  end

  next if files_to_process.empty?

  # --- 处理此规则匹配到的文件 ---
  files_to_process.each do |file_info|
    validation_performed_count += 1
    # 调用提取出的处理函数
    success = process_validation_target(file_info, rule_info, global_rule_error_summary, rule_run_aggregated_errors)

    # 更新正则规则统计
    if is_regex_rule
      regex_processed_count += 1
      regex_error_count += 1 unless success
    end
  end # files_to_process.each 结束

  # --- 正则规则总结 ---
  if is_regex_rule && regex_processed_count > 0
    regex_success_count = regex_processed_count - regex_error_count
    $logger.info("[规则总结] 模式 #{rule.inspect}:")
    $logger.info("  共检查 #{regex_processed_count} 个匹配文件。")
    $logger.info("  成功 (未发现问题): #{regex_success_count} 个。")
    if regex_error_count > 0
      $logger.warn("  发现问题 (加载或结构): #{regex_error_count} 个。")

      most_frequent_error_key = rule_run_aggregated_errors.keys.max_by do |key|
        rule_run_aggregated_errors[key][:files].size # 影响文件数最多的 key
      end

      if most_frequent_error_key
        data = rule_run_aggregated_errors[most_frequent_error_key]
        num_files_with_error = data[:files].size
        if num_files_with_error > 1 && num_files_with_error >= (regex_error_count * 0.5).ceil
          dummy_agg_data_for_format = { count: data[:count], first_path: "..." }
          formatted_msg = format_aggregated_error(most_frequent_error_key, dummy_agg_data_for_format)
          common_issue_desc = formatted_msg.split(":", 2).last.strip.sub(/\(共计 \d+ 次\)$/, "").strip
          $logger.warn("    最常见问题: 在 #{num_files_with_error} 个文件中发现 -> #{common_issue_desc}")
        end
      end
      unless $current_rgss_config[:log_map_details] || $logger.debug?
        $logger.warn("    (设相应版本的 log_map_details 为 true 或 日志级别为 DEBUG 查看各 Map 文件详情)")
      end
    end
  end
end # $current_rgss_config[:files_to_validate].each 结束

# --- 最终摘要 ---
$logger.info("\n=======================================")
$logger.info("--- 验证完成 (#{$current_rgss_config[:name]}) ---")

final_message_lines = []
exit_code = 0 # 退出码

if validation_performed_count == 0
  final_message_lines << "未执行任何文件验证（可能没有找到匹配的 #{file_extension} 文件）。"
  exit_code = 0 # 未找到文件不视为错误
else
  final_message_lines << "验证完成 (#{$current_rgss_config[:name]})。"
  final_message_lines << "总共检查文件数: #{validation_performed_count}"
  actual_error_file_count = $error_file_basenames.size

  if actual_error_file_count > 0
    final_message_lines << "发现问题的文件 (#{actual_error_file_count}):"

    map_files = $error_file_basenames.select { |name| name.match?(/^Map\d{3}$/) }.sort
    other_files = $error_file_basenames.reject { |name| name.match?(/^Map\d{3}$/) }.sort

    # 查找 Map 规则以访问其全局摘要数据
    map_rule = $current_rgss_config[:files_to_validate].find { |r| r.is_a?(Regexp) && r.source == 'Map\d{3}' }

    if map_files.any?
      line = "  - MapXXX#{file_extension} (#{map_files.size} 个文件)"
      if map_rule && global_rule_error_summary.key?(map_rule) && global_rule_error_summary[map_rule][:common_errors].any?
        most_common_key = global_rule_error_summary[map_rule][:common_errors].max_by { |k, v| v }[0]
        if most_common_key
          type, class_name, details_str = most_common_key
          details_display = details_str.split(",").join(", ")
          common_desc = case type
            when :missing_ivar then "缺少 #{details_display}"
            when :unexpected_ivar then "意外 #{details_display}"
            when :unexpected_class then "意外类 #{details_display.split(":").last.strip}"
            else "类型 #{type} 问题"
            end
          context = (class_name && class_name != "N/A") ? "在类 #{class_name}" : "在未知类中"
          line += " (常见问题: #{context}: #{common_desc})"
        end
      end
      final_message_lines << line
    end

    other_files.each do |basename|
      final_message_lines << "  - #{basename}#{file_extension}"
    end

    final_message_lines << "详细信息请查看日志文件: #{$log_file_path.expand_path}"
    exit_code = 1 # 有问题则退出码为 1
  else
    final_message_lines << "在检查的所有 #{validation_performed_count} 个文件中未发现需要关注的结构问题。"
    final_message_lines << "(注意: 对于 Table, Color, Tone, Rect 类, 由于占位符加载机制限制, 未严格检查其内部变量是否存在。)"
    exit_code = 0
  end
end

# --- 输出最终摘要到日志和控制台 ---
final_message = final_message_lines.join("\n")
$logger.info("\n" + final_message)
puts "\n" + final_message

# --- 添加: 显示动态定义的占位符 ---
$logger.info("\n--- 动态定义的占位符实体 (#{$current_rgss_config[:name]}) ---")
puts "\n--- 动态定义的占位符实体 (#{$current_rgss_config[:name]}) ---"

if $defined_placeholder_classes.empty?
  placeholder_list_message = "本次运行未动态定义任何占位符类或模块。"
  $logger.info(placeholder_list_message)
  puts placeholder_list_message
else
  sorted_placeholders = $defined_placeholder_classes.to_a.sort
  placeholder_list_message = "共动态定义了 #{sorted_placeholders.size} 个占位符实体:"
  $logger.info(placeholder_list_message)
  puts placeholder_list_message
  sorted_placeholders.each do |name|
    $logger.info("  - #{name}")
    puts "  - #{name}"
  end
end
# --- 添加结束 ---

exit(exit_code)
