# lib/rgss_extensions.rb
# 包含 RPG Maker 类特定版本的属性和初始化/解包逻辑 Mixin

module RPG

  # --- BaseItem Extensions ---
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
  module UsableItemExtensionsRGSS2
    attr_accessor :common_event_id, :base_damage, :variance, :atk_f, :spi_f
    attr_accessor :physical_attack, :damage_to_mp, :absorb_damage, :ignore_defense
    attr_accessor :element_set, :plus_state_set, :minus_state_set

    def initialize_usableitem_rgss2_specifics
      @common_event_id = 0; @base_damage = 0; @variance = 20; @atk_f = 0; @spi_f = 0
      @physical_attack = false; @damage_to_mp = false; @absorb_damage = false; @ignore_defense = false
      @element_set = []; @plus_state_set = []; @minus_state_set = []
    end

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
    attr_accessor :success_rate, :repeats, :tp_gain, :hit_type
    attr_accessor :damage, :effects

    def initialize_usableitem_rgss3_specifics
      @success_rate = 100; @repeats = 1; @tp_gain = 0; @hit_type = 0
      @damage = RPG::UsableItem::Damage.new if defined?(RPG::UsableItem::Damage)
      @effects = []
    end

    def unpack_names_usableitem_rgss3
      @damage.unpack_names if @damage.respond_to?(:unpack_names)
    end
  end

  # --- Actor Extensions ---
  module ActorExtensionsRGSS2
    attr_accessor :class_id, :initial_level, :exp_basis, :exp_inflation
    attr_accessor :character_name, :character_index, :face_name, :face_index, :parameters
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id
    attr_accessor :two_swords_style, :fix_equipment, :auto_battle, :super_guard
    attr_accessor :pharmacology, :critical_bonus

    def initialize_actor_rgss2_specifics
      @class_id = 1; @initial_level = 1; @exp_basis = 25; @exp_inflation = 35
      @character_name = ""; @character_index = 0; @face_name = ""; @face_index = 0
      @parameters = Table.new([]); @parameters.resize(6, 99)
      @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
      @two_swords_style = false; @fix_equipment = false; @auto_battle = false
      @super_guard = false; @pharmacology = false; @critical_bonus = false
    end

    def unpack_names_actor_rgss2
      Utils.unpack_names_for(self, :character_name, :face_name)
    end
  end

  module ActorExtensionsRGSS3
    attr_accessor :nickname, :class_id, :initial_level, :max_level
    attr_accessor :character_name, :character_index, :face_name, :face_index, :equips

    def initialize_actor_rgss3_specifics
      @nickname = ""; @class_id = 1; @initial_level = 1; @max_level = 99
      @character_name = ""; @character_index = 0; @face_name = ""; @face_index = 0
      @equips = [0, 0, 0, 0, 0]
    end

    def unpack_names_actor_rgss3
      Utils.unpack_names_for(self, :nickname, :character_name, :face_name)
    end
  end

  # --- Armor Extensions ---
  module ArmorExtensionsRGSS2
    attr_accessor :kind, :price, :eva, :atk, :def, :spi, :agi
    attr_accessor :prevent_critical, :half_mp_cost, :double_exp_gain, :auto_hp_recover
    attr_accessor :element_set, :state_set

    def initialize_armor_rgss2_specifics
      @kind = 0; @price = 0; @eva = 0; @atk = 0; @def = 0; @spi = 0; @agi = 0
      @prevent_critical = false; @half_mp_cost = false; @double_exp_gain = false; @auto_hp_recover = false
      @element_set = []; @state_set = []
    end

    def unpack_names_armor_rgss2; end
  end

  module ArmorExtensionsRGSS3
    attr_accessor :atype_id

    def initialize_armor_rgss3_specifics
      @atype_id = 0
    end

    def unpack_names_armor_rgss3; end
  end

  # --- Weapon Extensions ---
  module WeaponExtensionsRGSS2
    attr_accessor :animation_id, :price, :hit, :atk, :def, :spi, :agi
    attr_accessor :two_handed, :fast_attack, :dual_attack, :critical_bonus
    attr_accessor :element_set, :state_set

    def initialize_weapon_rgss2_specifics
      @animation_id = 0; @price = 0; @hit = 95; @atk = 0; @def = 0; @spi = 0; @agi = 0
      @two_handed = false; @fast_attack = false; @dual_attack = false; @critical_bonus = false
      @element_set = []; @state_set = []
    end

    def unpack_names_weapon_rgss2; end
  end

  module WeaponExtensionsRGSS3
    attr_accessor :wtype_id, :animation_id

    def initialize_weapon_rgss3_specifics
      @wtype_id = 0; @animation_id = 0
    end

    def unpack_names_weapon_rgss3; end
  end

  # --- Item Extensions ---
  module ItemExtensionsRGSS2
    attr_accessor :price, :consumable, :hp_recovery_rate, :hp_recovery
    attr_accessor :mp_recovery_rate, :mp_recovery, :parameter_type, :parameter_points

    def initialize_item_rgss2_specifics
      @price = 0; @consumable = true
      @hp_recovery_rate = 0; @hp_recovery = 0; @mp_recovery_rate = 0; @mp_recovery = 0
      @parameter_type = 0; @parameter_points = 0
    end

    def unpack_names_item_rgss2; end
  end

  module ItemExtensionsRGSS3
    attr_accessor :itype_id, :price, :consumable

    def initialize_item_rgss3_specifics
      @itype_id = 1; @price = 0; @consumable = true
    end

    def unpack_names_item_rgss3; end
  end

  # --- Skill Extensions ---
  module SkillExtensionsRGSS2
    attr_accessor :mp_cost, :hit, :message1, :message2

    def initialize_skill_rgss2_specifics
      @mp_cost = 0; @hit = 100; @message1 = ""; @message2 = ""
    end

    def unpack_names_skill_rgss2
      Utils.unpack_names_for(self, :message1, :message2)
    end
  end

  module SkillExtensionsRGSS3
    attr_accessor :stype_id, :mp_cost, :tp_cost, :message1, :message2
    attr_accessor :required_wtype_id1, :required_wtype_id2

    def initialize_skill_rgss3_specifics
      @stype_id = 1; @mp_cost = 0; @tp_cost = 0
      @message1 = ""; @message2 = ""
      @required_wtype_id1 = 0; @required_wtype_id2 = 0
    end

    def unpack_names_skill_rgss3
      Utils.unpack_names_for(self, :message1, :message2)
    end
  end

  # --- Enemy Extensions ---
  module EnemyExtensionsRGSS2
    attr_accessor :battler_name, :battler_hue, :maxhp, :maxmp, :atk, :def, :spi, :agi
    attr_accessor :hit, :eva, :exp, :gold, :drop_item1, :drop_item2, :levitate, :has_critical
    attr_accessor :element_ranks, :state_ranks, :actions

    def initialize_enemy_rgss2_specifics
      @battler_name = ""; @battler_hue = 0
      @maxhp = 10; @maxmp = 10; @atk = 10; @def = 10; @spi = 10; @agi = 10
      @hit = 95; @eva = 5; @exp = 0; @gold = 0
      @drop_item1 = RPG::Enemy::DropItem.new if defined?(RPG::Enemy::DropItem)
      @drop_item2 = RPG::Enemy::DropItem.new if defined?(RPG::Enemy::DropItem)
      @levitate = false; @has_critical = false
      @element_ranks = Table.new([]); @element_ranks.resize(1)
      @state_ranks = Table.new([]); @state_ranks.resize(1)
      @actions = [RPG::Enemy::Action.new] if defined?(RPG::Enemy::Action)
    end

    def unpack_names_enemy_rgss2
      Utils.unpack_names_for(self, :battler_name)
    end
  end

  module EnemyExtensionsRGSS3
    attr_accessor :battler_name, :battler_hue, :params, :exp, :gold, :drop_items, :actions

    def initialize_enemy_rgss3_specifics
      @battler_name = ""; @battler_hue = 0
      @params = [100, 0, 10, 10, 10, 10, 10, 10]
      @exp = 0; @gold = 0
      @drop_items = Array.new(3) { RPG::Enemy::DropItem.new } if defined?(RPG::Enemy::DropItem)
      @actions = [RPG::Enemy::Action.new] if defined?(RPG::Enemy::Action)
    end

    def unpack_names_enemy_rgss3
      Utils.unpack_names_for(self, :battler_name)
    end
  end

  # --- State Extensions ---
  module StateExtensionsRGSS2
    attr_accessor :restriction, :priority, :atk_rate, :def_rate, :spi_rate, :agi_rate
    attr_accessor :nonresistance, :offset_by_opposite, :slip_damage, :reduce_hit_ratio
    attr_accessor :battle_only, :release_by_damage, :hold_turn, :auto_release_prob
    attr_accessor :message1, :message2, :message3, :message4
    attr_accessor :element_set, :state_set

    def initialize_state_rgss2_specifics
      @restriction = 0; @priority = 5; @atk_rate = 100; @def_rate = 100; @spi_rate = 100; @agi_rate = 100
      @nonresistance = false; @offset_by_opposite = false; @slip_damage = false; @reduce_hit_ratio = false
      @battle_only = true; @release_by_damage = false; @hold_turn = 0; @auto_release_prob = 0
      @message1 = ""; @message2 = ""; @message3 = ""; @message4 = ""
      @element_set = []; @state_set = []
    end

    def unpack_names_state_rgss2
      Utils.unpack_names_for(self, :message1, :message2, :message3, :message4)
    end
  end

  module StateExtensionsRGSS3
    attr_accessor :restriction, :priority, :remove_at_battle_end, :remove_by_restriction
    attr_accessor :auto_removal_timing, :min_turns, :max_turns, :remove_by_damage
    attr_accessor :chance_by_damage, :remove_by_walking, :steps_to_remove
    attr_accessor :message1, :message2, :message3, :message4

    def initialize_state_rgss3_specifics
      @restriction = 0; @priority = 50
      @remove_at_battle_end = false; @remove_by_restriction = false
      @auto_removal_timing = 0; @min_turns = 1; @max_turns = 1
      @remove_by_damage = false; @chance_by_damage = 100
      @remove_by_walking = false; @steps_to_remove = 100
      @message1 = ""; @message2 = ""; @message3 = ""; @message4 = ""
    end

    def unpack_names_state_rgss3
      Utils.unpack_names_for(self, :message1, :message2, :message3, :message4)
    end
  end

  # --- Map Extensions ---
  module MapExtensionsRGSS2
    attr_accessor :data # Table(width, height, 3)
    attr_accessor :encounter_list # Array of [troop_id, weight, ???]

    def initialize_map_rgss2_specifics(width, height) # Need dimensions from main init
      @data = Table.new([]) # Create empty table
      @data.resize(width, height, 3) # Resize to 3 layers
      @encounter_list = []
    end

    def unpack_names_map_rgss2; end
  end

  module MapExtensionsRGSS3
    attr_accessor :display_name, :tileset_id, :specify_battleback
    attr_accessor :battleback1_name, :battleback2_name, :note
    attr_accessor :data # Table(width, height, 4)
    attr_accessor :encounter_list # Array of RPG::Map::Encounter

    def initialize_map_rgss3_specifics(width, height) # Need dimensions from main init
      @display_name = ""; @tileset_id = 1; @specify_battleback = false
      @battleback1_name = ""; @battleback2_name = ""
      @note = ""
      @data = Table.new([]) # Create empty table
      @data.resize(width, height, 4) # Resize to 4 layers
      @encounter_list = [] # Will be populated by restorer
    end

    def unpack_names_map_rgss3
      Utils.unpack_names_for(self, :display_name, :battleback1_name, :battleback2_name, :note)
    end
  end

  # --- System Extensions ---
  module SystemExtensionsRGSS2
    attr_accessor :passages # Table(8192)

    def initialize_system_rgss2_specifics
      @passages = Table.new([]); @passages.resize(8192) # VX default flags size
      @sounds = Array.new(20) { RPG::SE.new } # Requires SE class
    end

    def unpack_names_system_rgss2
      [:@elements, :@switches, :@variables].each do |ivar|
        array = instance_variable_get(ivar)
        array&.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item }
      end
    end
  end

  module SystemExtensionsRGSS3
    attr_accessor :japanese, :currency_unit, :skill_types, :weapon_types, :armor_types
    attr_accessor :title1_name, :title2_name, :opt_draw_title, :opt_use_midi, :opt_transparent
    attr_accessor :opt_followers, :opt_slip_death, :opt_floor_death, :opt_display_tp, :opt_extra_exp
    attr_accessor :window_tone, :battleback1_name, :battleback2_name

    def initialize_system_rgss3_specifics
      @japanese = true; @currency_unit = ""
      @skill_types = [nil, ""]; @weapon_types = [nil, ""]; @armor_types = [nil, ""]
      @elements = [nil, ""] # Re-initialize as RGSS3 might have different defaults? Shared init already does this.
      @title1_name = ""; @title2_name = ""
      @opt_draw_title = true; @opt_use_midi = false; @opt_transparent = false
      @opt_followers = true; @opt_slip_death = false; @opt_floor_death = false
      @opt_display_tp = true; @opt_extra_exp = false
      @window_tone = Tone.new([0.0, 0.0, 0.0, 0.0]) # Requires Tone class
      @sounds = Array.new(24) { RPG::SE.new }
      @battleback1_name = ""; @battleback2_name = ""
      @magic_number = 1 # Override shared default
    end

    def unpack_names_system_rgss3
      Utils.unpack_names_for(self, :currency_unit, :title1_name, :title2_name,
                             :battleback1_name, :battleback2_name)
      [:@elements, :@skill_types, :@weapon_types, :@armor_types, :@switches, :@variables].each do |ivar|
        array = instance_variable_get(ivar)
        array&.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item }
      end
    end
  end

  # --- Animation::Frame Extensions ---
  module AnimationFrameExtensionsRGSS2
    attr_accessor :cell_data # Table

    def initialize_animation_frame_rgss2_specifics
      @cell_data = Table.new([]); @cell_data.resize(0, 0)
    end

    def unpack_names_animation_frame_rgss2; end
  end

  module AnimationFrameExtensionsRGSS3
    attr_accessor :cell_data # Array

    def initialize_animation_frame_rgss3_specifics
      @cell_data = []
    end

    def unpack_names_animation_frame_rgss3; end
  end

  # --- Troop::Member Extensions ---
  module TroopMemberExtensionsRGSS2
    attr_accessor :immortal

    def initialize_troop_member_rgss2_specifics; @immortal = false; end
    def unpack_names_troop_member_rgss2; end
  end

  module TroopMemberExtensionsRGSS3
    def initialize_troop_member_rgss3_specifics; end
    def unpack_names_troop_member_rgss3; end
  end

  # --- System::TestBattler Extensions ---
  module SystemTestBattlerExtensionsRGSS2
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id

    def initialize_system_testbattler_rgss2_specifics
      @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
    end

    def unpack_names_system_testbattler_rgss2; end
  end

  module SystemTestBattlerExtensionsRGSS3
    attr_accessor :equips

    def initialize_system_testbattler_rgss3_specifics
      @equips = [0, 0, 0, 0, 0]
    end

    def unpack_names_system_testbattler_rgss3; end
  end

  # --- EquipItem Extensions (RGSS3 Only Base Class) ---
  module EquipItemExtensionsRGSS3
    attr_accessor :price, :etype_id, :params

    def initialize_equipitem_rgss3_specifics
      @price = 0; @etype_id = 0; @params = [0] * 8
    end

    def unpack_names_equipitem_rgss3; end
  end

  # --- Class Extensions (RGSS3 Only) ---
  module ClassExtensionsRGSS3
    attr_accessor :exp_params, :params, :learnings

    def initialize_class_rgss3_specifics
      @exp_params = [30, 20, 30, 30]
      @params = Table.new([]); @params.resize(8, 99)
      @learnings = []
    end

    def unpack_names_class_rgss3; end
  end
end # module RPG
