# lib/rgss_extensions.rb
# 包含 RPG Maker 类特定版本的属性和初始化/解包逻辑 Mixin
# 修正: 根据新的理解，RGSS3 Frame 的 @cell_data 在 Marshal 层级仍为 Table，
#       因此 RGSS3 的 Mixin 初始化也应该使用 Table。

module RPG

  # --- BaseItem Extensions ---
  module BaseItemExtensionsRGSS2
    # BaseItem 在 RGSS2 中没有特定于其自身的、需要 Mixin 管理的属性
    def initialize_baseitem_rgss2_specifics
      # No specific attributes to initialize here for RGSS2 BaseItem itself
    end

    def unpack_names_baseitem_rgss2
      # No specific string unpacking here for RGSS2 BaseItem itself
    end
  end

  module BaseItemExtensionsRGSS3
    # RGSS3 BaseItem 及其子类拥有 features
    attr_accessor :features

    def initialize_baseitem_rgss3_specifics
      @features = []
    end

    def unpack_names_baseitem_rgss3
      # features (which might contain notes) are handled recursively by JsonExporter
    end
  end

  # --- UsableItem Extensions ---
  module UsableItemExtensionsRGSS2
    # RGSS2 UsableItem 独有的属性 (Item/Skill 也会用到)
    attr_accessor :common_event_id, :base_damage, :variance, :atk_f, :spi_f
    attr_accessor :physical_attack, :damage_to_mp, :absorb_damage, :ignore_defense
    attr_accessor :element_set, :plus_state_set, :minus_state_set

    def initialize_usableitem_rgss2_specifics
      # 设置 UsableItem 及其子类 (Item/Skill) 共享的 RGSS2 属性默认值
      @common_event_id = 0
      @base_damage = 0
      @variance = 20
      @atk_f = 0
      @spi_f = 0
      @physical_attack = false
      @damage_to_mp = false
      @absorb_damage = false
      @ignore_defense = false
      @element_set = []
      @plus_state_set = []
      @minus_state_set = []
    end

    def unpack_names_usableitem_rgss2
      # 这些属性没有需要直接解包的字符串
    end

    # RGSS2 Helper methods (保持不变)
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
    # RGSS3 UsableItem 独有的属性 (Item/Skill/Weapon/Armor 也会用到)
    attr_accessor :success_rate, :repeats, :tp_gain, :hit_type
    attr_accessor :damage, :effects

    def initialize_usableitem_rgss3_specifics
      # 设置 UsableItem 及其子类共享的 RGSS3 属性默认值
      @success_rate = 100
      @repeats = 1
      @tp_gain = 0
      @hit_type = 0
      # 需要在 rgss3.rb 中定义这些类
      @damage = RPG::UsableItem::Damage.new if defined?(RPG::UsableItem::Damage)
      @effects = [] # Effect 对象在 rgss3.rb 中定义
    end

    def unpack_names_usableitem_rgss3
      # damage/effects 由 exporter 递归处理，但 damage.formula 需要特殊处理
      @damage.unpack_names if @damage.respond_to?(:unpack_names)
    end
  end

  # --- Actor Extensions ---
  module ActorExtensionsRGSS2
    # RGSS2 Actor 独立属性 (不继承 BaseItem)
    attr_accessor :id, :name
    attr_accessor :class_id, :initial_level, :exp_basis, :exp_inflation
    attr_accessor :character_name, :character_index, :face_name, :face_index, :parameters
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id
    attr_accessor :two_swords_style, :fix_equipment, :auto_battle, :super_guard
    attr_accessor :pharmacology, :critical_bonus

    def initialize_actor_rgss2_specifics
      # 初始化所有 RGSS2 Actor 属性
      @id = 0
      @name = ""
      @class_id = 1
      @initial_level = 1
      @exp_basis = 25
      @exp_inflation = 35
      @character_name = ""
      @character_index = 0
      @face_name = ""
      @face_index = 0
      # 需要在 shared.rb 中定义 Table 类
      @parameters = Table.new([])
      @parameters.resize(6, 99) # HP, MP, ATK, DEF, SPI, AGI for 99 levels
      @weapon_id = 0
      @armor1_id = 0
      @armor2_id = 0
      @armor3_id = 0
      @armor4_id = 0
      @two_swords_style = false
      @fix_equipment = false
      @auto_battle = false
      @super_guard = false
      @pharmacology = false
      @critical_bonus = false
    end

    def unpack_names_actor_rgss2
      # 解包 RGSS2 Actor 的字符串属性
      # 需要在 shared.rb 中定义 Utils 模块
      Utils.unpack_names_for(self, :name, :character_name, :face_name)
    end
  end

  module ActorExtensionsRGSS3
    # RGSS3 Actor 独有属性 (继承自 BaseItem)
    attr_accessor :nickname, :class_id, :initial_level, :max_level
    attr_accessor :character_name, :character_index, :face_name, :face_index, :equips
    # features 继承自 BaseItemExtensionsRGSS3

    def initialize_actor_rgss3_specifics
      # 初始化 RGSS3 Actor 特有属性
      @nickname = ""
      @class_id = 1
      @initial_level = 1
      @max_level = 99
      @character_name = ""
      @character_index = 0
      @face_name = ""
      @face_index = 0
      @equips = [0, 0, 0, 0, 0] # Weapon, Shield, Head, Body, Accessory
    end

    def unpack_names_actor_rgss3
      # 解包 RGSS3 Actor 特有字符串 (name/description/note 由 BaseItem 处理)
      Utils.unpack_names_for(self, :nickname, :character_name, :face_name)
    end
  end

  # --- Armor Extensions ---
  module ArmorExtensionsRGSS2
    # RGSS2 Armor 独有属性 (继承自 BaseItem)
    attr_accessor :kind, :price, :eva, :atk, :def, :spi, :agi
    attr_accessor :prevent_critical, :half_mp_cost, :double_exp_gain, :auto_hp_recover
    attr_accessor :element_set, :state_set

    def initialize_armor_rgss2_specifics
      # 初始化 RGSS2 Armor 特有属性
      @kind = 0 # 0:Shield, 1:Head, 2:Body, 3:Accessory
      @price = 0
      @eva = 0
      @atk = 0
      @def = 0
      @spi = 0
      @agi = 0
      @prevent_critical = false
      @half_mp_cost = false
      @double_exp_gain = false
      @auto_hp_recover = false
      @element_set = []
      @state_set = []
    end

    def unpack_names_armor_rgss2
      # No specific string unpacking needed here
    end
  end

  module ArmorExtensionsRGSS3
    # RGSS3 Armor 独有属性 (继承自 EquipItem -> BaseItem)
    attr_accessor :atype_id # Armor Type ID
    # price, etype_id, params, features 继承

    def initialize_armor_rgss3_specifics
      # 初始化 RGSS3 Armor 特有属性
      @atype_id = 0
      # etype_id (Equip Type) 和 features 的具体设置/添加在 rgss3.rb 的 Armor#initialize 中完成
    end

    def unpack_names_armor_rgss3
      # No specific string unpacking needed here
    end
  end

  # --- Weapon Extensions ---
  module WeaponExtensionsRGSS2
    # RGSS2 Weapon 独有属性 (继承自 BaseItem)
    attr_accessor :animation_id, :price, :hit, :atk, :def, :spi, :agi
    attr_accessor :two_handed, :fast_attack, :dual_attack, :critical_bonus
    attr_accessor :element_set, :state_set

    def initialize_weapon_rgss2_specifics
      # 初始化 RGSS2 Weapon 特有属性
      @animation_id = 0
      @price = 0
      @hit = 95
      @atk = 0
      @def = 0
      @spi = 0
      @agi = 0
      @two_handed = false
      @fast_attack = false
      @dual_attack = false
      @critical_bonus = false
      @element_set = []
      @state_set = []
    end

    def unpack_names_weapon_rgss2
      # No specific string unpacking needed here
    end
  end

  module WeaponExtensionsRGSS3
    # RGSS3 Weapon 独有属性 (继承自 EquipItem -> BaseItem)
    attr_accessor :wtype_id, :animation_id # Weapon Type ID, Animation ID
    # price, etype_id, params, features 继承

    def initialize_weapon_rgss3_specifics
      # 初始化 RGSS3 Weapon 特有属性
      @wtype_id = 0
      @animation_id = 0
      # etype_id 和 features 的具体设置/添加在 rgss3.rb 的 Weapon#initialize 中完成
    end

    def unpack_names_weapon_rgss3
      # No specific string unpacking needed here
    end
  end

  # --- Item Extensions ---
  module ItemExtensionsRGSS2
    # RGSS2 Item 独有属性 (继承自 UsableItem)
    attr_accessor :price, :consumable, :hp_recovery_rate, :hp_recovery
    attr_accessor :mp_recovery_rate, :mp_recovery, :parameter_type, :parameter_points
    # UsableItem RGSS2 属性通过 include 获得

    def initialize_item_rgss2_specifics
      # 初始化 Item 特有属性
      @price = 0
      @consumable = true
      @hp_recovery_rate = 0
      @hp_recovery = 0
      @mp_recovery_rate = 0
      @mp_recovery = 0
      @parameter_type = 0 # 0:None, 1:MaxHP, 2:MaxMP, 3:ATK, 4:DEF, 5:SPI, 6:AGI
      @parameter_points = 0
      # 调用 UsableItem RGSS2 的初始化
      initialize_usableitem_rgss2_specifics
    end

    def unpack_names_item_rgss2
      # No specific string unpacking needed here
    end
  end

  module ItemExtensionsRGSS3
    # RGSS3 Item 独有属性 (继承自 UsableItem -> BaseItem)
    attr_accessor :itype_id, :price, :consumable # Item Type ID (1:Regular, 2:Key)
    # UsableItem RGSS3 和 BaseItem RGSS3 属性通过继承获得

    def initialize_item_rgss3_specifics
      # 初始化 Item 特有属性
      @itype_id = 1
      @price = 0
      @consumable = true
      # UsableItem/BaseItem 的初始化由 rgss3.rb 的 Item#initialize 中的 super() 调用链处理
    end

    def unpack_names_item_rgss3
      # No specific string unpacking needed here
    end
  end

  # --- Skill Extensions ---
  module SkillExtensionsRGSS2
    # RGSS2 Skill 独有属性 (继承自 UsableItem)
    attr_accessor :mp_cost, :hit, :message1, :message2
    # UsableItem RGSS2 属性通过 include 获得

    def initialize_skill_rgss2_specifics
      # 初始化 Skill 特有属性
      @mp_cost = 0
      @hit = 100
      @message1 = ""
      @message2 = ""
      # 调用 UsableItem RGSS2 的初始化
      initialize_usableitem_rgss2_specifics
    end

    def unpack_names_skill_rgss2
      # 解包 Skill 特有字符串
      Utils.unpack_names_for(self, :message1, :message2)
    end
  end

  module SkillExtensionsRGSS3
    # RGSS3 Skill 独有属性 (继承自 UsableItem -> BaseItem)
    attr_accessor :stype_id, :mp_cost, :tp_cost, :message1, :message2 # Skill Type ID
    attr_accessor :required_wtype_id1, :required_wtype_id2 # Required Weapon Type IDs
    # UsableItem RGSS3 和 BaseItem RGSS3 属性通过继承获得

    def initialize_skill_rgss3_specifics
      # 初始化 Skill 特有属性
      @stype_id = 1
      @mp_cost = 0
      @tp_cost = 0
      @message1 = ""
      @message2 = ""
      @required_wtype_id1 = 0
      @required_wtype_id2 = 0
      # UsableItem/BaseItem 的初始化由 rgss3.rb 的 Skill#initialize 中的 super() 调用链处理
    end

    def unpack_names_skill_rgss3
      # 解包 Skill 特有字符串 (UsableItem/BaseItem 的解包由 super() 调用链处理)
      Utils.unpack_names_for(self, :message1, :message2)
    end
  end

  # --- Enemy Extensions ---
  module EnemyExtensionsRGSS2
    # RGSS2 Enemy 独立属性 (不继承 BaseItem)
    attr_accessor :id, :name, :note # Note is present in RGSS2 Enemy
    attr_accessor :battler_name, :battler_hue, :maxhp, :maxmp, :atk, :def, :spi, :agi
    attr_accessor :hit, :eva, :exp, :gold, :drop_item1, :drop_item2, :levitate, :has_critical
    attr_accessor :element_ranks, :state_ranks, :actions

    def initialize_enemy_rgss2_specifics
      # 初始化所有 RGSS2 Enemy 属性
      @id = 0
      @name = ""
      @note = ""
      @battler_name = ""
      @battler_hue = 0
      @maxhp = 10
      @maxmp = 10
      @atk = 10
      @def = 10
      @spi = 10
      @agi = 10
      @hit = 95
      @eva = 5
      @exp = 0
      @gold = 0
      # 需要在 rgss2.rb 中定义这些类
      @drop_item1 = RPG::Enemy::DropItem.new if defined?(RPG::Enemy::DropItem)
      @drop_item2 = RPG::Enemy::DropItem.new if defined?(RPG::Enemy::DropItem)
      @levitate = false
      @has_critical = false
      # 需要在 shared.rb 中定义 Table 类
      @element_ranks = Table.new([]); @element_ranks.resize(1) # Size depends on game data, default to 1
      @state_ranks = Table.new([]); @state_ranks.resize(1)   # Size depends on game data, default to 1
      @actions = [RPG::Enemy::Action.new] if defined?(RPG::Enemy::Action)
    end

    def unpack_names_enemy_rgss2
      # 解包 RGSS2 Enemy 的字符串属性
      Utils.unpack_names_for(self, :name, :note, :battler_name) # 需要 Utils 定义
    end
  end

  module EnemyExtensionsRGSS3
    # RGSS3 Enemy 独有属性 (继承自 BaseItem)
    attr_accessor :battler_name, :battler_hue, :params, :exp, :gold, :drop_items, :actions
    # id, name, note, features 继承

    def initialize_enemy_rgss3_specifics
      # 初始化 RGSS3 Enemy 特有属性
      @battler_name = ""
      @battler_hue = 0
      @params = [100, 0, 10, 10, 10, 10, 10, 10] # MHP,MMP,ATK,DEF,MAT,MDF,AGI,LUK
      @exp = 0
      @gold = 0
      # 需要在 rgss3.rb 中定义这些类
      @drop_items = Array.new(3) { RPG::Enemy::DropItem.new } if defined?(RPG::Enemy::DropItem)
      @actions = [RPG::Enemy::Action.new] if defined?(RPG::Enemy::Action)
      # features 的具体添加在 rgss3.rb 的 Enemy#initialize 中完成
    end

    def unpack_names_enemy_rgss3
      # 解包 RGSS3 Enemy 特有字符串 (name/note 由 BaseItem 处理)
      Utils.unpack_names_for(self, :battler_name)
    end
  end

  # --- State Extensions ---
  module StateExtensionsRGSS2
    # RGSS2 State 独立属性 (不继承 BaseItem)
    attr_accessor :id, :name, :note, :icon_index # Icon index exists in RGSS2 State
    attr_accessor :restriction, :priority, :atk_rate, :def_rate, :spi_rate, :agi_rate
    attr_accessor :nonresistance, :offset_by_opposite, :slip_damage, :reduce_hit_ratio
    attr_accessor :battle_only, :release_by_damage, :hold_turn, :auto_release_prob
    attr_accessor :message1, :message2, :message3, :message4
    attr_accessor :element_set, :state_set

    def initialize_state_rgss2_specifics
      # 初始化所有 RGSS2 State 属性
      @id = 0
      @name = ""
      @note = ""
      @icon_index = 0
      @restriction = 0 # 0:None, 1:Attack Enemy, 2:Attack Anyone, 3:Attack Ally, 4:Cannot Move
      @priority = 5
      @atk_rate = 100
      @def_rate = 100
      @spi_rate = 100
      @agi_rate = 100
      @nonresistance = false
      @offset_by_opposite = false
      @slip_damage = false
      @reduce_hit_ratio = false
      @battle_only = true
      @release_by_damage = false
      @hold_turn = 0
      @auto_release_prob = 0
      @message1 = ""
      @message2 = ""
      @message3 = ""
      @message4 = ""
      @element_set = []
      @state_set = []
    end

    def unpack_names_state_rgss2
      # 解包 RGSS2 State 的字符串属性
      Utils.unpack_names_for(self, :name, :note, :message1, :message2, :message3, :message4)
    end
  end

  module StateExtensionsRGSS3
    # RGSS3 State 独有属性 (继承自 BaseItem)
    attr_accessor :restriction, :priority, :remove_at_battle_end, :remove_by_restriction
    attr_accessor :auto_removal_timing, :min_turns, :max_turns, :remove_by_damage
    attr_accessor :chance_by_damage, :remove_by_walking, :steps_to_remove
    attr_accessor :message1, :message2, :message3, :message4
    # id, name, note, icon_index, features 继承

    def initialize_state_rgss3_specifics
      # 初始化 RGSS3 State 特有属性
      @restriction = 0 # 0..4, same meaning as RGSS2
      @priority = 50
      @remove_at_battle_end = false
      @remove_by_restriction = false
      @auto_removal_timing = 0 # 0:None, 1:Action End, 2:Turn End
      @min_turns = 1
      @max_turns = 1
      @remove_by_damage = false
      @chance_by_damage = 100
      @remove_by_walking = false
      @steps_to_remove = 100
      @message1 = "" # Actor message
      @message2 = "" # Enemy message
      @message3 = "" # Already State message
      @message4 = "" # Removed message
      # features 由 BaseItem 初始化
    end

    def unpack_names_state_rgss3
      # 解包 RGSS3 State 特有字符串 (name/note 由 BaseItem 处理)
      Utils.unpack_names_for(self, :message1, :message2, :message3, :message4)
    end
  end

  # --- Map Extensions ---
  module MapExtensionsRGSS2
    # RGSS2 Map 独有属性
    attr_accessor :data # Table(width, height, 3)
    attr_accessor :encounter_list # Array of [troop_id, weight, ???] (last element unused?)

    def initialize_map_rgss2_specifics(width, height)
      # 初始化 RGSS2 Map 特有属性
      # 需要 Table 定义
      @data = Table.new([])
      @data.resize(width, height, 3)
      @encounter_list = []
    end

    def unpack_names_map_rgss2
      # No specific string unpacking needed here
    end
  end

  module MapExtensionsRGSS3
    # RGSS3 Map 独有属性
    attr_accessor :display_name, :tileset_id, :specify_battleback
    attr_accessor :battleback1_name, :battleback2_name, :note
    attr_accessor :data # Table(width, height, 4)
    attr_accessor :encounter_list # Array of RPG::Map::Encounter

    def initialize_map_rgss3_specifics(width, height)
      # 初始化 RGSS3 Map 特有属性
      @display_name = ""
      @tileset_id = 1
      @specify_battleback = false
      @battleback1_name = ""
      @battleback2_name = ""
      @note = ""
      # 需要 Table 定义
      @data = Table.new([])
      @data.resize(width, height, 4)
      @encounter_list = [] # 需要在 rgss3.rb 中定义 RPG::Map::Encounter
    end

    def unpack_names_map_rgss3
      # 解包 RGSS3 Map 特有字符串
      Utils.unpack_names_for(self, :display_name, :battleback1_name, :battleback2_name, :note)
    end
  end

  # --- System Extensions ---
  module SystemExtensionsRGSS2
    # RGSS2 System 独有属性
    attr_accessor :passages # Table(8192)

    def initialize_system_rgss2_specifics
      # 初始化 RGSS2 System 特有属性
      # 需要 Table 和 SE 定义
      @passages = Table.new([])
      @passages.resize(8192)
      @sounds = Array.new(20) { RPG::SE.new }
      # terms 在 rgss2.rb 的 System#initialize 中创建
    end

    def unpack_names_system_rgss2
      # 解包 RGSS2 System 的数组字符串 (elements/switches/variables 由共享处理)
      # @terms 的解包在 rgss2.rb 的 System#unpack_names 中处理
    end
  end

  module SystemExtensionsRGSS3
    # RGSS3 System 独有属性
    attr_accessor :japanese, :currency_unit, :skill_types, :weapon_types, :armor_types
    attr_accessor :title1_name, :title2_name, :opt_draw_title, :opt_use_midi, :opt_transparent
    attr_accessor :opt_followers, :opt_slip_death, :opt_floor_death, :opt_display_tp, :opt_extra_exp
    attr_accessor :window_tone, :battleback1_name, :battleback2_name
    # magic_number, elements, switches, variables, sounds, terms 在共享/覆盖中处理

    def initialize_system_rgss3_specifics
      # 初始化 RGSS3 System 特有属性
      @japanese = true
      @currency_unit = ""
      @skill_types = [nil, ""]
      @weapon_types = [nil, ""]
      @armor_types = [nil, ""]
      @title1_name = ""
      @title2_name = ""
      @opt_draw_title = true
      @opt_use_midi = false
      @opt_transparent = false
      @opt_followers = true
      @opt_slip_death = false
      @opt_floor_death = false
      @opt_display_tp = true
      @opt_extra_exp = false
      # 需要 Tone 和 SE 定义
      @window_tone = Tone.new([0.0, 0.0, 0.0, 0.0])
      @sounds = Array.new(24) { RPG::SE.new }
      @battleback1_name = ""
      @battleback2_name = ""
      @magic_number = 1 # 覆盖共享默认值
      # terms 在 rgss3.rb 的 System#initialize 中创建
    end

    def unpack_names_system_rgss3
      # 解包 RGSS3 System 特有字符串
      Utils.unpack_names_for(self, :currency_unit, :title1_name, :title2_name,
                             :battleback1_name, :battleback2_name)
      # 解包数组字符串 (elements/switches/variables 由共享或覆盖处理)
      [:@skill_types, :@weapon_types, :@armor_types].each do |ivar|
        array = instance_variable_get(ivar)
        # Check if array is not nil before mapping
        array&.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item }
      end
      # @terms 的解包在 rgss3.rb 的 System#unpack_names 中处理
    end
  end

  # --- Animation::Frame Extensions ---
  module AnimationFrameExtensionsRGSS2
    # RGSS2 Frame 独有属性
    attr_accessor :cell_data # Table

    def initialize_animation_frame_rgss2_specifics
      # 初始化 RGSS2 Frame 特有属性
      # 需要 Table 定义
      @cell_data = Table.new([])
      @cell_data.resize(0, 0) # 通常由恢复器填充，或保持默认空 Table
    end

    def unpack_names_animation_frame_rgss2
      # No specific string unpacking needed here
    end
  end

  module AnimationFrameExtensionsRGSS3
    # RGSS3 Frame 独有属性
    # 根据新的理解，@cell_data 在 Marshal 层级仍然是 Table
    attr_accessor :cell_data # Table

    def initialize_animation_frame_rgss3_specifics
      # 初始化 RGSS3 Frame 特有属性 (按照 Table 处理)
      # 需要 Table 定义
      @cell_data = Table.new([])
      @cell_data.resize(0, 0) # 初始化为空 Table
    end

    def unpack_names_animation_frame_rgss3
      # No specific string unpacking needed here
    end
  end

  # --- Troop::Member Extensions ---
  module TroopMemberExtensionsRGSS2
    # RGSS2 Member 独有属性
    attr_accessor :immortal

    def initialize_troop_member_rgss2_specifics
      # 初始化 RGSS2 Member 特有属性
      @immortal = false
    end

    def unpack_names_troop_member_rgss2
      # No specific string unpacking needed here
    end
  end

  module TroopMemberExtensionsRGSS3
    # RGSS3 Member 无特有属性
    def initialize_troop_member_rgss3_specifics
      # No specific attributes to initialize here
    end

    def unpack_names_troop_member_rgss3
      # No specific string unpacking needed here
    end
  end

  # --- System::TestBattler Extensions ---
  module SystemTestBattlerExtensionsRGSS2
    # RGSS2 TestBattler 独有属性
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id

    def initialize_system_testbattler_rgss2_specifics
      # 初始化 RGSS2 TestBattler 特有属性
      @weapon_id = 0
      @armor1_id = 0
      @armor2_id = 0
      @armor3_id = 0
      @armor4_id = 0
    end

    def unpack_names_system_testbattler_rgss2
      # No specific string unpacking needed here
    end
  end

  module SystemTestBattlerExtensionsRGSS3
    # RGSS3 TestBattler 独有属性
    attr_accessor :equips

    def initialize_system_testbattler_rgss3_specifics
      # 初始化 RGSS3 TestBattler 特有属性
      @equips = [0, 0, 0, 0, 0]
    end

    def unpack_names_system_testbattler_rgss3
      # No specific string unpacking needed here
    end
  end

  # --- EquipItem Extensions (RGSS3 Only Base Class) ---
  module EquipItemExtensionsRGSS3
    # RGSS3 EquipItem (及子类 Weapon/Armor) 共享属性
    attr_accessor :price, :etype_id, :params
    # features 继承自 BaseItemExtensionsRGSS3

    def initialize_equipitem_rgss3_specifics
      # 初始化 RGSS3 EquipItem 共享属性
      @price = 0
      @etype_id = 0 # Default (Weapon), overridden by Armor if needed
      @params = [0] * 8 # MHP,MMP,ATK,DEF,MAT,MDF,AGI,LUK
      # features 由 BaseItem 初始化
    end

    def unpack_names_equipitem_rgss3
      # No specific string unpacking needed here
    end
  end

  # --- Class Extensions (RGSS3 Only) ---
  module ClassExtensionsRGSS3
    # RGSS3 Class 独有属性 (继承自 BaseItem)
    attr_accessor :exp_params, :params, :learnings
    # id, name, note, icon_index, description, features 继承

    def initialize_class_rgss3_specifics
      # 初始化 RGSS3 Class 特有属性
      @exp_params = [30, 20, 30, 30] # Basis, Increase A, Increase B, Accel B
      # 需要 Table 定义
      @params = Table.new([])
      @params.resize(8, 99) # MHP,MMP,ATK,DEF,MAT,MDF,AGI,LUK for 99 levels
      @learnings = [] # 需要在 rgss3.rb 中定义 RPG::Class::Learning
      # features 的具体添加在 rgss3.rb 的 Class#initialize 中完成
    end

    def unpack_names_class_rgss3
      # learnings (which might contain notes) are handled recursively by JsonExporter
    end
  end
end # module RPG
