# lib/rgss_extensions.rb
# 包含 RPG Maker 类特定版本的属性和初始化/解包逻辑 Mixin

module RPG

  # --- BaseItem Extensions ---
  # (RGSS1 没有严格意义上的 BaseItem 基类，但可以为共享属性创建 Mixin)
  module BaseItemExtensionsRGSS1
    # RGSS1 Item, Skill, Weapon, Armor 共享的属性 (如果适用)
    # 看起来 RGSS1 的这些类没有太多共享的 *数据* 属性需要 Mixin 管理
    # name, icon_name, description 在各自的 Mixin 中处理
    def initialize_baseitem_rgss1_specifics
      # No common data ivars to initialize here for RGSS1 pseudo-base
    end

    def unpack_names_baseitem_rgss1
      # Handled in specific class mixins
    end
  end

  module BaseItemExtensionsRGSS2
    def initialize_baseitem_rgss2_specifics; end
    def unpack_names_baseitem_rgss2; end
  end

  module BaseItemExtensionsRGSS3
    attr_accessor :features

    def initialize_baseitem_rgss3_specifics; @features = []; end
    def unpack_names_baseitem_rgss3; end
  end

  # --- UsableItem Extensions ---
  # (RGSS1 没有 UsableItem 基类，相关属性在 Skill/Item 中)
  module UsableItemExtensionsRGSS2
    attr_accessor :common_event_id, :base_damage, :variance, :atk_f, :spi_f
    attr_accessor :physical_attack, :damage_to_mp, :absorb_damage, :ignore_defense
    attr_accessor :element_set, :plus_state_set, :minus_state_set

    def initialize_usableitem_rgss2_specifics; @common_event_id = 0; @base_damage = 0; @variance = 20; @atk_f = 0; @spi_f = 0; @physical_attack = false; @damage_to_mp = false; @absorb_damage = false; @ignore_defense = false; @element_set = []; @plus_state_set = []; @minus_state_set = []; end
    def unpack_names_usableitem_rgss2; end
    def for_opponent?; [1, 2, 3, 4, 5, 6].include?(@scope); end
    def for_friend?; [7, 8, 9, 10, 11].include?(@scope); end
    def for_friend_hp?; [7, 9, 11].include?(@scope); end
    def for_friend_all?; [8, 10].include?(@scope); end
    def for_user?; @scope == 12; end
    def for_all?; [2, 8, 10].include?(@scope); end
    def for_one?; [1, 3, 4, 5, 6, 7, 9, 11, 12].include?(@scope); end
    def need_selection?; [1, 3, 4, 5, 6, 7, 9].include?(@scope); end
  end

  module UsableItemExtensionsRGSS3
    attr_accessor :success_rate, :repeats, :tp_gain, :hit_type, :damage, :effects

    def initialize_usableitem_rgss3_specifics; @success_rate = 100; @repeats = 1; @tp_gain = 0; @hit_type = 0; @damage = RPG::UsableItem::Damage.new if defined?(RPG::UsableItem::Damage); @effects = []; end
    def unpack_names_usableitem_rgss3; @damage.unpack_names if @damage.respond_to?(:unpack_names); end
  end

  # --- Actor Extensions ---
  # --- 添加: ActorExtensionsRGSS1 ---
  module ActorExtensionsRGSS1
    attr_accessor :id, :name, :class_id, :initial_level, :final_level
    attr_accessor :exp_basis, :exp_inflation
    attr_accessor :character_name, :character_hue, :battler_name, :battler_hue
    attr_accessor :parameters
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id
    attr_accessor :weapon_fix, :armor1_fix, :armor2_fix, :armor3_fix, :armor4_fix

    def initialize_actor_rgss1_specifics
      @id = 0; @name = ""; @class_id = 1; @initial_level = 1; @final_level = 99
      @exp_basis = 30; @exp_inflation = 30
      @character_name = ""; @character_hue = 0; @battler_name = ""; @battler_hue = 0
      @parameters = Table.new([]); @parameters.resize(6, 100) # HP, SP, STR, DEX, AGI, INT for 100 levels
      @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
      @weapon_fix = false; @armor1_fix = false; @armor2_fix = false; @armor3_fix = false; @armor4_fix = false
    end

    def unpack_names_actor_rgss1
      Utils.unpack_names_for(self, :name, :character_name, :battler_name)
    end
  end

  # -----------------------------

  module ActorExtensionsRGSS2
    attr_accessor :id, :name, :class_id, :initial_level, :exp_basis, :exp_inflation
    attr_accessor :character_name, :character_index, :face_name, :face_index, :parameters
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id
    attr_accessor :two_swords_style, :fix_equipment, :auto_battle, :super_guard
    attr_accessor :pharmacology, :critical_bonus

    def initialize_actor_rgss2_specifics; @id = 0; @name = ""; @class_id = 1; @initial_level = 1; @exp_basis = 25; @exp_inflation = 35; @character_name = ""; @character_index = 0; @face_name = ""; @face_index = 0; @parameters = Table.new([]); @parameters.resize(6, 99); @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0; @two_swords_style = false; @fix_equipment = false; @auto_battle = false; @super_guard = false; @pharmacology = false; @critical_bonus = false; end
    def unpack_names_actor_rgss2; Utils.unpack_names_for(self, :name, :character_name, :face_name); end
  end

  module ActorExtensionsRGSS3
    attr_accessor :nickname, :class_id, :initial_level, :max_level
    attr_accessor :character_name, :character_index, :face_name, :face_index, :equips

    def initialize_actor_rgss3_specifics; @nickname = ""; @class_id = 1; @initial_level = 1; @max_level = 99; @character_name = ""; @character_index = 0; @face_name = ""; @face_index = 0; @equips = [0, 0, 0, 0, 0]; end
    def unpack_names_actor_rgss3; Utils.unpack_names_for(self, :nickname, :character_name, :face_name); end
  end

  # --- Armor Extensions ---
  # --- 添加: ArmorExtensionsRGSS1 ---
  module ArmorExtensionsRGSS1
    attr_accessor :id, :name, :icon_name, :description
    attr_accessor :kind, :auto_state_id, :price
    attr_accessor :pdef, :mdef, :eva
    attr_accessor :str_plus, :dex_plus, :agi_plus, :int_plus
    attr_accessor :guard_element_set, :guard_state_set

    def initialize_armor_rgss1_specifics
      @id = 0; @name = ""; @icon_name = ""; @description = ""
      @kind = 0; @auto_state_id = 0; @price = 0
      @pdef = 0; @mdef = 0; @eva = 0
      @str_plus = 0; @dex_plus = 0; @agi_plus = 0; @int_plus = 0
      @guard_element_set = []; @guard_state_set = []
    end

    def unpack_names_armor_rgss1
      Utils.unpack_names_for(self, :name, :icon_name, :description)
    end
  end

  # -----------------------------

  module ArmorExtensionsRGSS2
    attr_accessor :kind, :price, :eva, :atk, :def, :spi, :agi
    attr_accessor :prevent_critical, :half_mp_cost, :double_exp_gain, :auto_hp_recover
    attr_accessor :element_set, :state_set

    def initialize_armor_rgss2_specifics; @kind = 0; @price = 0; @eva = 0; @atk = 0; @def = 0; @spi = 0; @agi = 0; @prevent_critical = false; @half_mp_cost = false; @double_exp_gain = false; @auto_hp_recover = false; @element_set = []; @state_set = []; end
    def unpack_names_armor_rgss2; end
  end

  module ArmorExtensionsRGSS3
    attr_accessor :atype_id

    def initialize_armor_rgss3_specifics; @atype_id = 0; end
    def unpack_names_armor_rgss3; end
  end

  # --- Weapon Extensions ---
  # --- 添加: WeaponExtensionsRGSS1 ---
  module WeaponExtensionsRGSS1
    attr_accessor :id, :name, :icon_name, :description
    attr_accessor :animation1_id, :animation2_id, :price
    attr_accessor :atk, :pdef, :mdef
    attr_accessor :str_plus, :dex_plus, :agi_plus, :int_plus
    attr_accessor :element_set, :plus_state_set, :minus_state_set

    def initialize_weapon_rgss1_specifics
      @id = 0; @name = ""; @icon_name = ""; @description = ""
      @animation1_id = 0; @animation2_id = 0; @price = 0
      @atk = 0; @pdef = 0; @mdef = 0
      @str_plus = 0; @dex_plus = 0; @agi_plus = 0; @int_plus = 0
      @element_set = []; @plus_state_set = []; @minus_state_set = []
    end

    def unpack_names_weapon_rgss1
      Utils.unpack_names_for(self, :name, :icon_name, :description)
    end
  end

  # -----------------------------

  module WeaponExtensionsRGSS2
    attr_accessor :animation_id, :price, :hit, :atk, :def, :spi, :agi
    attr_accessor :two_handed, :fast_attack, :dual_attack, :critical_bonus
    attr_accessor :element_set, :state_set

    def initialize_weapon_rgss2_specifics; @animation_id = 0; @price = 0; @hit = 95; @atk = 0; @def = 0; @spi = 0; @agi = 0; @two_handed = false; @fast_attack = false; @dual_attack = false; @critical_bonus = false; @element_set = []; @state_set = []; end
    def unpack_names_weapon_rgss2; end
  end

  module WeaponExtensionsRGSS3
    attr_accessor :wtype_id, :animation_id

    def initialize_weapon_rgss3_specifics; @wtype_id = 0; @animation_id = 0; end
    def unpack_names_weapon_rgss3; end
  end

  # --- Item Extensions ---
  # --- 添加: ItemExtensionsRGSS1 ---
  module ItemExtensionsRGSS1
    attr_accessor :id, :name, :icon_name, :description
    attr_accessor :scope, :occasion, :animation1_id, :animation2_id
    attr_accessor :menu_se, :common_event_id, :price, :consumable
    attr_accessor :parameter_type, :parameter_points
    attr_accessor :recover_hp_rate, :recover_hp, :recover_sp_rate, :recover_sp
    attr_accessor :hit, :pdef_f, :mdef_f, :variance
    attr_accessor :element_set, :plus_state_set, :minus_state_set

    def initialize_item_rgss1_specifics
      @id = 0; @name = ""; @icon_name = ""; @description = ""
      @scope = 0; @occasion = 0; @animation1_id = 0; @animation2_id = 0
      @menu_se = RPG::AudioFile.new("", 80); @common_event_id = 0; @price = 0; @consumable = true
      @parameter_type = 0; @parameter_points = 0
      @recover_hp_rate = 0; @recover_hp = 0; @recover_sp_rate = 0; @recover_sp = 0
      @hit = 100; @pdef_f = 0; @mdef_f = 0; @variance = 0
      @element_set = []; @plus_state_set = []; @minus_state_set = []
    end

    def unpack_names_item_rgss1
      Utils.unpack_names_for(self, :name, :icon_name, :description)
      @menu_se&.unpack_names # AudioFile unpacking
    end
  end

  # -----------------------------

  module ItemExtensionsRGSS2
    attr_accessor :price, :consumable, :hp_recovery_rate, :hp_recovery
    attr_accessor :mp_recovery_rate, :mp_recovery, :parameter_type, :parameter_points

    def initialize_item_rgss2_specifics; @price = 0; @consumable = true; @hp_recovery_rate = 0; @hp_recovery = 0; @mp_recovery_rate = 0; @mp_recovery = 0; @parameter_type = 0; @parameter_points = 0; initialize_usableitem_rgss2_specifics; end
    def unpack_names_item_rgss2; end
  end

  module ItemExtensionsRGSS3
    attr_accessor :itype_id, :price, :consumable

    def initialize_item_rgss3_specifics; @itype_id = 1; @price = 0; @consumable = true; end
    def unpack_names_item_rgss3; end
  end

  # --- Skill Extensions ---
  # --- 添加: SkillExtensionsRGSS1 ---
  module SkillExtensionsRGSS1
    attr_accessor :id, :name, :icon_name, :description
    attr_accessor :scope, :occasion, :animation1_id, :animation2_id
    attr_accessor :menu_se, :common_event_id, :sp_cost, :power
    attr_accessor :atk_f, :eva_f, :str_f, :dex_f, :agi_f, :int_f
    attr_accessor :hit, :pdef_f, :mdef_f, :variance
    attr_accessor :element_set, :plus_state_set, :minus_state_set

    def initialize_skill_rgss1_specifics
      @id = 0; @name = ""; @icon_name = ""; @description = ""
      @scope = 0; @occasion = 1; @animation1_id = 0; @animation2_id = 0
      @menu_se = RPG::AudioFile.new("", 80); @common_event_id = 0; @sp_cost = 0; @power = 0
      @atk_f = 0; @eva_f = 0; @str_f = 0; @dex_f = 0; @agi_f = 0; @int_f = 100
      @hit = 100; @pdef_f = 0; @mdef_f = 100; @variance = 15
      @element_set = []; @plus_state_set = []; @minus_state_set = []
    end

    def unpack_names_skill_rgss1
      Utils.unpack_names_for(self, :name, :icon_name, :description)
      @menu_se&.unpack_names # AudioFile unpacking
    end
  end

  # -----------------------------

  module SkillExtensionsRGSS2
    attr_accessor :mp_cost, :hit, :message1, :message2

    def initialize_skill_rgss2_specifics; @mp_cost = 0; @hit = 100; @message1 = ""; @message2 = ""; initialize_usableitem_rgss2_specifics; end
    def unpack_names_skill_rgss2; Utils.unpack_names_for(self, :message1, :message2); end
  end

  module SkillExtensionsRGSS3
    attr_accessor :stype_id, :mp_cost, :tp_cost, :message1, :message2
    attr_accessor :required_wtype_id1, :required_wtype_id2

    def initialize_skill_rgss3_specifics; @stype_id = 1; @mp_cost = 0; @tp_cost = 0; @message1 = ""; @message2 = ""; @required_wtype_id1 = 0; @required_wtype_id2 = 0; end
    def unpack_names_skill_rgss3; Utils.unpack_names_for(self, :message1, :message2); end
  end

  # --- Enemy Extensions ---
  # --- 添加: EnemyExtensionsRGSS1 ---
  module EnemyExtensionsRGSS1
    attr_accessor :id, :name, :battler_name, :battler_hue
    attr_accessor :maxhp, :maxsp, :str, :dex, :agi, :int
    attr_accessor :atk, :pdef, :mdef, :eva
    attr_accessor :animation1_id, :animation2_id
    attr_accessor :element_ranks, :state_ranks, :actions
    attr_accessor :exp, :gold, :item_id, :weapon_id, :armor_id, :treasure_prob

    def initialize_enemy_rgss1_specifics
      @id = 0; @name = ""; @battler_name = ""; @battler_hue = 0
      @maxhp = 500; @maxsp = 500; @str = 50; @dex = 50; @agi = 50; @int = 50
      @atk = 100; @pdef = 100; @mdef = 100; @eva = 0
      @animation1_id = 0; @animation2_id = 0
      @element_ranks = Table.new([]); @element_ranks.resize(1)
      @state_ranks = Table.new([]); @state_ranks.resize(1)
      @actions = [RPG::Enemy::Action.new]
      @exp = 0; @gold = 0; @item_id = 0; @weapon_id = 0; @armor_id = 0; @treasure_prob = 100
    end

    def unpack_names_enemy_rgss1
      Utils.unpack_names_for(self, :name, :battler_name)
    end
  end

  # -----------------------------

  module EnemyExtensionsRGSS2
    attr_accessor :id, :name, :note # Note is present in RGSS2 Enemy
    attr_accessor :battler_name, :battler_hue, :maxhp, :maxmp, :atk, :def, :spi, :agi
    attr_accessor :hit, :eva, :exp, :gold, :drop_item1, :drop_item2, :levitate, :has_critical
    attr_accessor :element_ranks, :state_ranks, :actions

    def initialize_enemy_rgss2_specifics; @id = 0; @name = ""; @note = ""; @battler_name = ""; @battler_hue = 0; @maxhp = 10; @maxmp = 10; @atk = 10; @def = 10; @spi = 10; @agi = 10; @hit = 95; @eva = 5; @exp = 0; @gold = 0; @drop_item1 = RPG::Enemy::DropItem.new if defined?(RPG::Enemy::DropItem); @drop_item2 = RPG::Enemy::DropItem.new if defined?(RPG::Enemy::DropItem); @levitate = false; @has_critical = false; @element_ranks = Table.new([]); @element_ranks.resize(1); @state_ranks = Table.new([]); @state_ranks.resize(1); @actions = [RPG::Enemy::Action.new] if defined?(RPG::Enemy::Action); end
    def unpack_names_enemy_rgss2; Utils.unpack_names_for(self, :name, :note, :battler_name); end
  end

  module EnemyExtensionsRGSS3
    attr_accessor :battler_name, :battler_hue, :params, :exp, :gold, :drop_items, :actions

    def initialize_enemy_rgss3_specifics; @battler_name = ""; @battler_hue = 0; @params = [100, 0, 10, 10, 10, 10, 10, 10]; @exp = 0; @gold = 0; @drop_items = Array.new(3) { RPG::Enemy::DropItem.new } if defined?(RPG::Enemy::DropItem); @actions = [RPG::Enemy::Action.new] if defined?(RPG::Enemy::Action); end
    def unpack_names_enemy_rgss3; Utils.unpack_names_for(self, :battler_name); end
  end

  # --- State Extensions ---
  # --- 添加: StateExtensionsRGSS1 ---
  module StateExtensionsRGSS1
    attr_accessor :id, :name, :animation_id, :restriction
    attr_accessor :nonresistance, :zero_hp, :cant_get_exp, :cant_evade, :slip_damage
    attr_accessor :rating, :hit_rate, :maxhp_rate, :maxsp_rate
    attr_accessor :str_rate, :dex_rate, :agi_rate, :int_rate
    attr_accessor :atk_rate, :pdef_rate, :mdef_rate, :eva
    attr_accessor :battle_only, :hold_turn, :auto_release_prob, :shock_release_prob
    attr_accessor :guard_element_set, :plus_state_set, :minus_state_set

    def initialize_state_rgss1_specifics
      @id = 0; @name = ""; @animation_id = 0; @restriction = 0
      @nonresistance = false; @zero_hp = false; @cant_get_exp = false; @cant_evade = false; @slip_damage = false
      @rating = 5; @hit_rate = 100; @maxhp_rate = 100; @maxsp_rate = 100
      @str_rate = 100; @dex_rate = 100; @agi_rate = 100; @int_rate = 100
      @atk_rate = 100; @pdef_rate = 100; @mdef_rate = 100; @eva = 0
      @battle_only = true; @hold_turn = 0; @auto_release_prob = 0; @shock_release_prob = 0
      @guard_element_set = []; @plus_state_set = []; @minus_state_set = []
    end

    def unpack_names_state_rgss1
      Utils.unpack_names_for(self, :name)
    end
  end

  # -----------------------------

  module StateExtensionsRGSS2
    attr_accessor :id, :name, :note, :icon_index
    attr_accessor :restriction, :priority, :atk_rate, :def_rate, :spi_rate, :agi_rate
    attr_accessor :nonresistance, :offset_by_opposite, :slip_damage, :reduce_hit_ratio
    attr_accessor :battle_only, :release_by_damage, :hold_turn, :auto_release_prob
    attr_accessor :message1, :message2, :message3, :message4
    attr_accessor :element_set, :state_set

    def initialize_state_rgss2_specifics; @id = 0; @name = ""; @note = ""; @icon_index = 0; @restriction = 0; @priority = 5; @atk_rate = 100; @def_rate = 100; @spi_rate = 100; @agi_rate = 100; @nonresistance = false; @offset_by_opposite = false; @slip_damage = false; @reduce_hit_ratio = false; @battle_only = true; @release_by_damage = false; @hold_turn = 0; @auto_release_prob = 0; @message1 = ""; @message2 = ""; @message3 = ""; @message4 = ""; @element_set = []; @state_set = []; end
    def unpack_names_state_rgss2; Utils.unpack_names_for(self, :name, :note, :message1, :message2, :message3, :message4); end
  end

  module StateExtensionsRGSS3
    attr_accessor :restriction, :priority, :remove_at_battle_end, :remove_by_restriction
    attr_accessor :auto_removal_timing, :min_turns, :max_turns, :remove_by_damage
    attr_accessor :chance_by_damage, :remove_by_walking, :steps_to_remove
    attr_accessor :message1, :message2, :message3, :message4

    def initialize_state_rgss3_specifics; @restriction = 0; @priority = 50; @remove_at_battle_end = false; @remove_by_restriction = false; @auto_removal_timing = 0; @min_turns = 1; @max_turns = 1; @remove_by_damage = false; @chance_by_damage = 100; @remove_by_walking = false; @steps_to_remove = 100; @message1 = ""; @message2 = ""; @message3 = ""; @message4 = ""; end
    def unpack_names_state_rgss3; Utils.unpack_names_for(self, :message1, :message2, :message3, :message4); end
  end

  # --- Map Extensions ---
  # --- 添加: MapExtensionsRGSS1 ---
  module MapExtensionsRGSS1
    attr_accessor :tileset_id, :width, :height
    attr_accessor :autoplay_bgm, :bgm, :autoplay_bgs, :bgs
    attr_accessor :encounter_list, :encounter_step, :data, :events

    def initialize_map_rgss1_specifics(width, height)
      @tileset_id = 1; @width = width; @height = height
      @autoplay_bgm = false; @bgm = RPG::AudioFile.new
      @autoplay_bgs = false; @bgs = RPG::AudioFile.new("", 80)
      @encounter_list = []; @encounter_step = 30
      @data = Table.new([]); @data.resize(width, height, 3)
      @events = {}
    end

    def unpack_names_map_rgss1
      @bgm&.unpack_names
      @bgs&.unpack_names
      # Events are handled recursively
    end
  end

  # -----------------------------

  module MapExtensionsRGSS2
    attr_accessor :data, :encounter_list

    def initialize_map_rgss2_specifics(width, height); @data = Table.new([]); @data.resize(width, height, 3); @encounter_list = []; end
    def unpack_names_map_rgss2; end
  end

  module MapExtensionsRGSS3
    attr_accessor :display_name, :tileset_id, :specify_battleback
    attr_accessor :battleback1_name, :battleback2_name, :note
    attr_accessor :data, :encounter_list

    def initialize_map_rgss3_specifics(width, height); @display_name = ""; @tileset_id = 1; @specify_battleback = false; @battleback1_name = ""; @battleback2_name = ""; @note = ""; @data = Table.new([]); @data.resize(width, height, 4); @encounter_list = []; end
    def unpack_names_map_rgss3; Utils.unpack_names_for(self, :display_name, :battleback1_name, :battleback2_name, :note); end
  end

  # --- System Extensions ---
  # --- 添加: SystemExtensionsRGSS1 ---
  module SystemExtensionsRGSS1
    attr_accessor :magic_number, :party_members, :elements, :switches, :variables
    attr_accessor :windowskin_name, :title_name, :gameover_name, :battle_transition
    attr_accessor :title_bgm, :battle_bgm, :battle_end_me, :gameover_me
    attr_accessor :cursor_se, :decision_se, :cancel_se, :buzzer_se
    attr_accessor :equip_se, :shop_se, :save_se, :load_se
    attr_accessor :battle_start_se, :escape_se, :actor_collapse_se, :enemy_collapse_se
    attr_accessor :words, :test_battlers, :test_troop_id
    attr_accessor :start_map_id, :start_x, :start_y
    attr_accessor :battleback_name, :battler_name, :battler_hue, :edit_map_id

    def initialize_system_rgss1_specifics
      @magic_number = 0; @party_members = [1]; @elements = [nil, ""]; @switches = [nil, ""]; @variables = [nil, ""]
      @windowskin_name = ""; @title_name = ""; @gameover_name = ""; @battle_transition = ""
      @title_bgm = RPG::AudioFile.new; @battle_bgm = RPG::AudioFile.new; @battle_end_me = RPG::AudioFile.new; @gameover_me = RPG::AudioFile.new
      @cursor_se = RPG::AudioFile.new("", 80); @decision_se = RPG::AudioFile.new("", 80); @cancel_se = RPG::AudioFile.new("", 80); @buzzer_se = RPG::AudioFile.new("", 80)
      @equip_se = RPG::AudioFile.new("", 80); @shop_se = RPG::AudioFile.new("", 80); @save_se = RPG::AudioFile.new("", 80); @load_se = RPG::AudioFile.new("", 80)
      @battle_start_se = RPG::AudioFile.new("", 80); @escape_se = RPG::AudioFile.new("", 80); @actor_collapse_se = RPG::AudioFile.new("", 80); @enemy_collapse_se = RPG::AudioFile.new("", 80)
      @words = RPG::System::Words.new; @test_battlers = []; @test_troop_id = 1
      @start_map_id = 1; @start_x = 0; @start_y = 0
      @battleback_name = ""; @battler_name = ""; @battler_hue = 0; @edit_map_id = 1
    end

    def unpack_names_system_rgss1
      Utils.unpack_names_for(self, :windowskin_name, :title_name, :gameover_name, :battle_transition, :battleback_name, :battler_name)
      # Unpack arrays
      [:@elements, :@switches, :@variables].each do |ivar|
        array = instance_variable_get(ivar); array&.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item }
      end
      # Unpack SEs
      se_vars = [:@cursor_se, :@decision_se, :@cancel_se, :@buzzer_se, :@equip_se, :@shop_se, :@save_se, :@load_se, :@battle_start_se, :@escape_se, :@actor_collapse_se, :@enemy_collapse_se]
      se_vars.each { |ivar| instance_variable_get(ivar)&.unpack_names }
      # Unpack BGMs/ME
      [:@title_bgm, :@battle_bgm, :@battle_end_me, :@gameover_me].each { |ivar| instance_variable_get(ivar)&.unpack_names }
      # Unpack Terms
      @words&.unpack_names if @words.respond_to?(:unpack_names)
      # Test battlers handled recursively
    end
  end

  # -----------------------------

  module SystemExtensionsRGSS2
    attr_accessor :passages, :sounds # Overwrite sounds from shared

    def initialize_system_rgss2_specifics; @passages = Table.new([]); @passages.resize(8192); @sounds = Array.new(20) { RPG::SE.new }; end
    def unpack_names_system_rgss2; @sounds&.each { |s| s&.unpack_names }; end # unpack SEs in array
  end

  module SystemExtensionsRGSS3
    attr_accessor :japanese, :currency_unit, :skill_types, :weapon_types, :armor_types
    attr_accessor :title1_name, :title2_name, :opt_draw_title, :opt_use_midi, :opt_transparent
    attr_accessor :opt_followers, :opt_slip_death, :opt_floor_death, :opt_display_tp, :opt_extra_exp
    attr_accessor :window_tone, :battleback1_name, :battleback2_name, :sounds # Overwrite sounds from shared

    def initialize_system_rgss3_specifics; @japanese = true; @currency_unit = ""; @skill_types = [nil, ""]; @weapon_types = [nil, ""]; @armor_types = [nil, ""]; @title1_name = ""; @title2_name = ""; @opt_draw_title = true; @opt_use_midi = false; @opt_transparent = false; @opt_followers = true; @opt_slip_death = false; @opt_floor_death = false; @opt_display_tp = true; @opt_extra_exp = false; @window_tone = Tone.new([0.0, 0.0, 0.0, 0.0]); @sounds = Array.new(24) { RPG::SE.new }; @battleback1_name = ""; @battleback2_name = ""; end
    def unpack_names_system_rgss3; Utils.unpack_names_for(self, :currency_unit, :title1_name, :title2_name, :battleback1_name, :battleback2_name); [:elements, :switches, :variables, :skill_types, :weapon_types, :armor_types].each { |ivar_name| array = instance_variable_get("@#{ivar_name}"); array&.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item } }; @sounds&.each { |s| s&.unpack_names }; end # unpack SEs and string arrays
  end

  # --- Animation::Frame Extensions ---
  # --- 添加: AnimationFrameExtensionsRGSS1 ---
  # RGSS1 Frame 结构与 RGSS2/3 相同
  module AnimationFrameExtensionsRGSS1
    attr_accessor :cell_max, :cell_data

    def initialize_animation_frame_rgss1_specifics
      @cell_max = 0
      @cell_data = Table.new([]); @cell_data.resize(0, 0)
    end

    def unpack_names_animation_frame_rgss1; end
  end

  # -----------------------------

  module AnimationFrameExtensionsRGSS2
    attr_accessor :cell_data

    def initialize_animation_frame_rgss2_specifics; @cell_data = Table.new([]); @cell_data.resize(0, 0); end
    def unpack_names_animation_frame_rgss2; end
  end

  module AnimationFrameExtensionsRGSS3
    attr_accessor :cell_data

    def initialize_animation_frame_rgss3_specifics; @cell_data = Table.new([]); @cell_data.resize(0, 0); end
    def unpack_names_animation_frame_rgss3; end
  end

  # --- Troop::Member Extensions ---
  # --- 添加: TroopMemberExtensionsRGSS1 ---
  module TroopMemberExtensionsRGSS1
    attr_accessor :enemy_id, :x, :y, :immortal # RGSS1 有 immortal

    def initialize_troop_member_rgss1_specifics
      @enemy_id = 1; @x = 0; @y = 0; @immortal = false
    end

    def unpack_names_troop_member_rgss1; end
  end

  # -----------------------------

  module TroopMemberExtensionsRGSS2
    attr_accessor :immortal

    def initialize_troop_member_rgss2_specifics; @immortal = false; end
    def unpack_names_troop_member_rgss2; end
  end

  module TroopMemberExtensionsRGSS3
    # RGSS3 Member 无特有属性
    def initialize_troop_member_rgss3_specifics; end
    def unpack_names_troop_member_rgss3; end
  end

  # --- System::TestBattler Extensions ---
  # --- 添加: SystemTestBattlerExtensionsRGSS1 ---
  module SystemTestBattlerExtensionsRGSS1
    attr_accessor :actor_id, :level
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id

    def initialize_system_testbattler_rgss1_specifics
      @actor_id = 1; @level = 1
      @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
    end

    def unpack_names_system_testbattler_rgss1; end
  end

  # -----------------------------

  module SystemTestBattlerExtensionsRGSS2
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id

    def initialize_system_testbattler_rgss2_specifics; @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0; end
    def unpack_names_system_testbattler_rgss2; end
  end

  module SystemTestBattlerExtensionsRGSS3
    attr_accessor :equips

    def initialize_system_testbattler_rgss3_specifics; @equips = [0, 0, 0, 0, 0]; end
    def unpack_names_system_testbattler_rgss3; end
  end

  # --- EquipItem Extensions (RGSS3 Only Base Class) ---
  module EquipItemExtensionsRGSS3
    attr_accessor :price, :etype_id, :params

    def initialize_equipitem_rgss3_specifics; @price = 0; @etype_id = 0; @params = [0] * 8; end
    def unpack_names_equipitem_rgss3; end
  end

  # --- Class Extensions ---
  # --- 添加: ClassExtensionsRGSS1 ---
  module ClassExtensionsRGSS1
    attr_accessor :id, :name, :position, :weapon_set, :armor_set
    attr_accessor :element_ranks, :state_ranks, :learnings

    def initialize_class_rgss1_specifics
      @id = 0; @name = ""; @position = 0; @weapon_set = []; @armor_set = []
      @element_ranks = Table.new([]); @element_ranks.resize(1)
      @state_ranks = Table.new([]); @state_ranks.resize(1)
      @learnings = []
    end

    def unpack_names_class_rgss1
      Utils.unpack_names_for(self, :name)
      # Learnings handled recursively
    end
  end

  # -----------------------------

  # --- 添加: ClassExtensionsRGSS2 --- (从 rgss2.rb 移入并修正)
  module ClassExtensionsRGSS2
    attr_accessor :id, :name, :position, :weapon_set, :armor_set
    attr_accessor :element_ranks, :state_ranks, :learnings
    attr_accessor :skill_name_valid, :skill_name # RGSS2 only attributes

    def initialize_class_rgss2_specifics
      @id = 0; @name = ""; @position = 0; @weapon_set = []; @armor_set = []
      @element_ranks = Table.new([]); @element_ranks.resize(1)
      @state_ranks = Table.new([]); @state_ranks.resize(1)
      @learnings = []
      @skill_name_valid = false; @skill_name = ""
    end

    def unpack_names_class_rgss2
      Utils.unpack_names_for(self, :name, :skill_name)
      # Learnings handled recursively
    end
  end

  # -----------------------------

  module ClassExtensionsRGSS3
    attr_accessor :exp_params, :params, :learnings

    def initialize_class_rgss3_specifics; @exp_params = [30, 20, 30, 30]; @params = Table.new([]); @params.resize(8, 99); @learnings = []; end
    def unpack_names_class_rgss3; end
  end

  # --- Tileset Extensions ---
  # --- 添加: TilesetExtensionsRGSS1 ---
  module TilesetExtensionsRGSS1
    attr_accessor :id, :name, :tileset_name, :autotile_names
    attr_accessor :panorama_name, :panorama_hue
    attr_accessor :fog_name, :fog_hue, :fog_opacity, :fog_blend_type, :fog_zoom, :fog_sx, :fog_sy
    attr_accessor :battleback_name, :passages, :priorities, :terrain_tags

    def initialize_tileset_rgss1_specifics
      @id = 0; @name = ""; @tileset_name = ""
      @autotile_names = Array.new(7) { "" }
      @panorama_name = ""; @panorama_hue = 0
      @fog_name = ""; @fog_hue = 0; @fog_opacity = 64; @fog_blend_type = 0; @fog_zoom = 200; @fog_sx = 0; @fog_sy = 0
      @battleback_name = ""
      @passages = Table.new([]); @passages.resize(384)
      @priorities = Table.new([]); @priorities.resize(384); @priorities[0] = 5
      @terrain_tags = Table.new([]); @terrain_tags.resize(384)
    end

    def unpack_names_tileset_rgss1
      Utils.unpack_names_for(self, :name, :tileset_name, :panorama_name, :fog_name, :battleback_name)
      @autotile_names&.map! { |n| n.is_a?(String) ? RPG.unpack_str(n) : n }
    end
  end

  # -----------------------------

  # --- 添加: TilesetExtensionsRGSS3 --- (从 rgss3.rb 移入并修正)
  module TilesetExtensionsRGSS3 # RGSS3 only class
    attr_accessor :id, :mode, :name, :tileset_names, :flags, :note

    def initialize_tileset_rgss3_specifics
      @id = 0; @mode = 1; @name = ""; @tileset_names = Array.new(9) { "" }
      @flags = Table.new([]); @flags.resize(8192); @flags[0] = 0x0010
      (2048..2815).each { |i| @flags[i] = 0x000F }
      (4352..8191).each { |i| @flags[i] = 0x000F }
      @note = ""
    end

    def unpack_names_tileset_rgss3
      Utils.unpack_names_for(self, :name, :note)
      @tileset_names&.map! { |n| n.is_a?(String) ? RPG.unpack_str(n) : n }
    end
  end

  # -----------------------------

  # --- Event::Page::Graphic Extensions ---
  # --- 添加: EventPageGraphicExtensionsRGSS1 ---
  module EventPageGraphicExtensionsRGSS1
    attr_accessor :character_name, :character_hue, :direction, :pattern
    attr_accessor :opacity, :blend_type # RGSS1 特有

    def initialize_event_page_graphic_rgss1_specifics
      @character_name = ""; @character_hue = 0; @direction = 2; @pattern = 0
      @opacity = 255; @blend_type = 0
    end

    def unpack_names_event_page_graphic_rgss1
      Utils.unpack_names_for(self, :character_name)
    end
  end

  # -----------------------------

  module EventPageGraphicExtensionsRGSS2
    attr_accessor :tile_id, :character_name, :character_index, :direction, :pattern # RGSS2 特有/不同

    def initialize_event_page_graphic_rgss2_specifics
      @tile_id = 0; @character_name = ""; @character_index = 0; @direction = 2; @pattern = 0
    end

    def unpack_names_event_page_graphic_rgss2
      Utils.unpack_names_for(self, :character_name)
    end
  end

  module EventPageGraphicExtensionsRGSS3 # 与 RGSS2 相同
    attr_accessor :tile_id, :character_name, :character_index, :direction, :pattern

    def initialize_event_page_graphic_rgss3_specifics
      @tile_id = 0; @character_name = ""; @character_index = 0; @direction = 2; @pattern = 0
    end

    def unpack_names_event_page_graphic_rgss3
      Utils.unpack_names_for(self, :character_name)
    end
  end

  # --- Animation Extensions ---
  # --- 添加: AnimationExtensionsRGSS1 ---
  module AnimationExtensionsRGSS1
    attr_accessor :id, :name, :animation_name, :animation_hue # RGSS1 特有
    attr_accessor :position, :frame_max, :frames, :timings

    def initialize_animation_rgss1_specifics
      @id = 0; @name = ""; @animation_name = ""; @animation_hue = 0
      @position = 1; @frame_max = 1; @frames = []; @timings = []
    end

    def unpack_names_animation_rgss1
      Utils.unpack_names_for(self, :name, :animation_name)
      # frames/timings handled recursively
    end
  end

  # -----------------------------

  module AnimationExtensionsRGSS2
    attr_accessor :id, :name, :animation1_name, :animation1_hue, :animation2_name, :animation2_hue # RGSS2 特有
    attr_accessor :position, :frame_max, :frames, :timings

    def initialize_animation_rgss2_specifics
      @id = 0; @name = ""; @animation1_name = ""; @animation1_hue = 0; @animation2_name = ""; @animation2_hue = 0
      @position = 1; @frame_max = 1; @frames = []; @timings = []
    end

    def unpack_names_animation_rgss2
      Utils.unpack_names_for(self, :name, :animation1_name, :animation2_name)
      # frames/timings handled recursively
    end
  end

  module AnimationExtensionsRGSS3 # 与 RGSS2 相同
    attr_accessor :id, :name, :animation1_name, :animation1_hue, :animation2_name, :animation2_hue
    attr_accessor :position, :frame_max, :frames, :timings

    def initialize_animation_rgss3_specifics
      @id = 0; @name = ""; @animation1_name = ""; @animation1_hue = 0; @animation2_name = ""; @animation2_hue = 0
      @position = 1; @frame_max = 1; @frames = []; @timings = []
    end

    def unpack_names_animation_rgss3
      Utils.unpack_names_for(self, :name, :animation1_name, :animation2_name)
      # frames/timings handled recursively
    end
  end

  # --- Animation::Timing Extensions ---
  # --- 添加: AnimationTimingExtensionsRGSS1 ---
  module AnimationTimingExtensionsRGSS1
    attr_accessor :frame, :se, :flash_scope, :flash_color, :flash_duration
    attr_accessor :condition # RGSS1 特有

    def initialize_animation_timing_rgss1_specifics
      @frame = 0; @se = RPG::SE.new("", 80); @flash_scope = 0; @flash_color = Color.new([255.0, 255.0, 255.0, 255.0]); @flash_duration = 5; @condition = 0
    end

    def unpack_names_animation_timing_rgss1
      @se&.unpack_names
    end
  end

  # -----------------------------

  module AnimationTimingExtensionsRGSS2 # 无 condition
    attr_accessor :frame, :se, :flash_scope, :flash_color, :flash_duration

    def initialize_animation_timing_rgss2_specifics
      @frame = 0; @se = RPG::SE.new("", 80); @flash_scope = 0; @flash_color = Color.new([255.0, 255.0, 255.0, 255.0]); @flash_duration = 5
    end

    def unpack_names_animation_timing_rgss2
      @se&.unpack_names
    end
  end

  module AnimationTimingExtensionsRGSS3 # 与 RGSS2 相同
    attr_accessor :frame, :se, :flash_scope, :flash_color, :flash_duration

    def initialize_animation_timing_rgss3_specifics
      @frame = 0; @se = RPG::SE.new("", 80); @flash_scope = 0; @flash_color = Color.new([255.0, 255.0, 255.0, 255.0]); @flash_duration = 5
    end

    def unpack_names_animation_timing_rgss3
      @se&.unpack_names
    end
  end
end # module RPG
