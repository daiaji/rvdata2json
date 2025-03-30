# encoding: utf-8
# rvdata2json/lib/rgss3.rb
# 包含 RGSS3 (RPG Maker VX Ace) 特有的类定义或对共享类的修改

require_relative "shared" # 加载共享定义

# --- RGSS3 特有模块修改 ---
# RPG.pack_str in shared.rb is already suitable for RGSS3 (UTF-16LE)

# --- RGSS3 特有类定义或覆盖 ---
module RPG

  # --- Reopen shared classes to adjust for RGSS3 ---

  class Actor < RPG::BaseItem
    attr_accessor :nickname, :class_id, :initial_level, :max_level
    attr_accessor :character_name, :character_index, :face_name, :face_index, :equips
    # inherits features from BaseItem

    def unpack_names(rgss_version = "RGSS3")
      super(rgss_version) # Call BaseItem unpack
      Utils.unpack_names_for(self, :nickname, :character_name, :face_name)
    end

    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # Calls BaseItem init, ensures features=[]
      @nickname = ""; @class_id = 1; @initial_level = 1; @max_level = 99
      @character_name = ""; @character_index = 0; @face_name = ""; @face_index = 0
      @equips = [0, 0, 0, 0, 0]
      # Ensure RGSS2 attrs removed
      RPG.remove_ivar_if_exists(self, :@exp_basis)
      RPG.remove_ivar_if_exists(self, :@exp_inflation)
      RPG.remove_ivar_if_exists(self, :@parameters)
      RPG.remove_ivar_if_exists(self, :@weapon_id)
      RPG.remove_ivar_if_exists(self, :@armor1_id)
      RPG.remove_ivar_if_exists(self, :@armor2_id)
      RPG.remove_ivar_if_exists(self, :@armor3_id)
      RPG.remove_ivar_if_exists(self, :@armor4_id)
      RPG.remove_ivar_if_exists(self, :@two_swords_style)
      RPG.remove_ivar_if_exists(self, :@fix_equipment)
      RPG.remove_ivar_if_exists(self, :@auto_battle)
      RPG.remove_ivar_if_exists(self, :@super_guard)
      RPG.remove_ivar_if_exists(self, :@pharmacology)
      RPG.remove_ivar_if_exists(self, :@critical_bonus)
    end
  end # Actor

  class Class < RPG::BaseItem
    attr_accessor :exp_params, :params, :learnings
    # inherits features

    def unpack_names(rgss_version = "RGSS3")
      super(rgss_version)
      # learnings handled recursively by exporter
    end

    def initialize(rgss_version = "RGSS3")
      super(rgss_version)
      @exp_params = [30, 20, 30, 30]
      @params = Table.new([2, 8, 99, 1, 8 * 99]) # 8 params, 99 levels
      @learnings = [] # Array of RPG::Class::Learning

      # Add default features specific to RGSS3 Class
      @features.push(RPG::BaseItem::Feature.new(23, 0, 1))    # Guard? -> Element Set? (Code needs verification)
      @features.push(RPG::BaseItem::Feature.new(22, 0, 0.95)) # Param: HIT
      @features.push(RPG::BaseItem::Feature.new(22, 1, 0.05)) # Param: EVA
      @features.push(RPG::BaseItem::Feature.new(22, 2, 0.04)) # Param: CRI
      @features.push(RPG::BaseItem::Feature.new(41, 1))       # Equip WTYPE 1
      @features.push(RPG::BaseItem::Feature.new(51, 1))       # Attack Element 1
      @features.push(RPG::BaseItem::Feature.new(52, 1))       # Attack State 1

      # Ensure RGSS2 attrs removed
      RPG.remove_ivar_if_exists(self, :@position)
      RPG.remove_ivar_if_exists(self, :@weapon_set)
      RPG.remove_ivar_if_exists(self, :@armor_set)
      RPG.remove_ivar_if_exists(self, :@element_ranks)
      RPG.remove_ivar_if_exists(self, :@state_ranks)
      RPG.remove_ivar_if_exists(self, :@skill_name_valid)
      RPG.remove_ivar_if_exists(self, :@skill_name)
    end

    class Learning
      include Jsonable
      attr_accessor :level, :skill_id, :note

      def unpack_names(rgss_version = "RGSS3")
        Utils.unpack_names_for(self, :note)
      end

      def initialize
        @level = 1; @skill_id = 1; @note = ""
      end
    end # Learning
  end # Class

  class Skill < RPG::UsableItem
    attr_accessor :stype_id, :mp_cost, :tp_cost, :message1, :message2
    attr_accessor :required_wtype_id1, :required_wtype_id2
    # Inherits RGSS3 UsableItem attributes (damage, effects, etc.)

    def unpack_names(rgss_version = "RGSS3")
      super(rgss_version) # Calls UsableItem unpack
      Utils.unpack_names_for(self, :message1, :message2)
      # damage handled recursively by exporter
    end

    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # Calls UsableItem init, handles its version logic
      @scope = 1 # Override default
      @stype_id = 1; @mp_cost = 0; @tp_cost = 0
      @message1 = ""; @message2 = ""
      @required_wtype_id1 = 0; @required_wtype_id2 = 0
      # Ensure RGSS2 attrs removed (UsableItem handles some)
      RPG.remove_ivar_if_exists(self, :@hit)
    end
  end # Skill

  class Item < RPG::UsableItem
    attr_accessor :itype_id, :price, :consumable
    # Inherits RGSS3 UsableItem attributes

    def initialize(rgss_version = "RGSS3")
      super(rgss_version)
      @scope = 7 # Override default
      @itype_id = 1; @price = 0; @consumable = true
      # Ensure RGSS2 attrs removed (UsableItem handles some)
      RPG.remove_ivar_if_exists(self, :@hp_recovery_rate)
      RPG.remove_ivar_if_exists(self, :@hp_recovery)
      RPG.remove_ivar_if_exists(self, :@mp_recovery_rate)
      RPG.remove_ivar_if_exists(self, :@mp_recovery)
      RPG.remove_ivar_if_exists(self, :@parameter_type)
      RPG.remove_ivar_if_exists(self, :@parameter_points)
    end
  end # Item

  # EquipItem is RGSS3 specific
  class EquipItem < RPG::BaseItem
    attr_accessor :price, :etype_id, :params
    # inherits features

    def initialize(rgss_version = "RGSS3")
      super(rgss_version)
      @price = 0
      @etype_id = 0 # 0:Weapon, 1:Shield, 2:Head, 3:Body, 4:Accessory
      @params = [0] * 8 # MHP,MMP,ATK,DEF,MAT,MDF,AGI,LUK increments
      # Ensure RGSS2 Armor/Weapon attrs removed (if somehow present)
      RPG.remove_ivar_if_exists(self, :@kind)
      RPG.remove_ivar_if_exists(self, :@eva)
      RPG.remove_ivar_if_exists(self, :@hit)
      # ... etc ...
    end
  end # EquipItem

  class Weapon < RPG::EquipItem
    attr_accessor :wtype_id, :animation_id
    # inherits price, etype_id, params, features

    def initialize(rgss_version = "RGSS3")
      super(rgss_version)
      @etype_id = 0 # Weapon etype_id is 0
      @wtype_id = 0; @animation_id = 0
      # Add default features specific to RGSS3 Weapon
      @features.push(RPG::BaseItem::Feature.new(31, 1, 0)) # Attack Element: Physical
      @features.push(RPG::BaseItem::Feature.new(22, 0, 0)) # Param: HIT + 0
      # Ensure RGSS2 attrs removed
      RPG.remove_ivar_if_exists(self, :@hit)
      RPG.remove_ivar_if_exists(self, :@atk) # Covered by params
      # ... etc ...
    end
  end # Weapon

  class Armor < RPG::EquipItem
    attr_accessor :atype_id
    # inherits price, etype_id, params, features

    def initialize(rgss_version = "RGSS3")
      super(rgss_version)
      @etype_id = 1 # Default to Shield (adjust based on atype_id if needed)
      @atype_id = 0
      # Add default features specific to RGSS3 Armor
      @features.push(RPG::BaseItem::Feature.new(22, 1, 0)) # Param: EVA + 0
      # Ensure RGSS2 attrs removed
      RPG.remove_ivar_if_exists(self, :@kind)
      RPG.remove_ivar_if_exists(self, :@eva)
      # ... etc ...
    end
  end # Armor

  class Enemy < RPG::BaseItem
    attr_accessor :battler_name, :battler_hue, :params, :exp, :gold, :drop_items, :actions
    # inherits features

    def unpack_names(rgss_version = "RGSS3")
      super(rgss_version)
      Utils.unpack_names_for(self, :battler_name)
      # drop_items/actions handled recursively
    end

    def initialize(rgss_version = "RGSS3")
      super(rgss_version)
      @battler_name = ""; @battler_hue = 0
      @params = [100, 0, 10, 10, 10, 10, 10, 10] # MHP,MMP,ATK,DEF,MAT,MDF,AGI,LUK
      @exp = 0; @gold = 0
      @drop_items = Array.new(3) { RPG::Enemy::DropItem.new } # Array of objects
      @actions = [RPG::Enemy::Action.new]
      # Add default features specific to RGSS3 Enemy
      @features.push(RPG::BaseItem::Feature.new(22, 0, 0.95)) # HIT
      @features.push(RPG::BaseItem::Feature.new(22, 1, 0.05)) # EVA
      @features.push(RPG::BaseItem::Feature.new(31, 1, 0))    # Attack Element Physical
      # Ensure RGSS2 attrs removed
      RPG.remove_ivar_if_exists(self, :@maxhp)
      RPG.remove_ivar_if_exists(self, :@maxmp)
      RPG.remove_ivar_if_exists(self, :@atk) # Covered by params
      RPG.remove_ivar_if_exists(self, :@def)
      RPG.remove_ivar_if_exists(self, :@spi) # Covered by params (MAT)
      RPG.remove_ivar_if_exists(self, :@agi)
      RPG.remove_ivar_if_exists(self, :@hit)
      RPG.remove_ivar_if_exists(self, :@eva)
      RPG.remove_ivar_if_exists(self, :@drop_item1)
      RPG.remove_ivar_if_exists(self, :@drop_item2)
      RPG.remove_ivar_if_exists(self, :@levitate)
      RPG.remove_ivar_if_exists(self, :@has_critical)
      RPG.remove_ivar_if_exists(self, :@element_ranks)
      RPG.remove_ivar_if_exists(self, :@state_ranks)
    end

    class Action
      include Jsonable
      attr_accessor :skill_id, :condition_type, :condition_param1, :condition_param2, :rating

      def initialize
        @skill_id = 1; @condition_type = 0
        @condition_param1 = 0; @condition_param2 = 0; @rating = 5
      end
    end # Action

    class DropItem
      include Jsonable
      attr_accessor :kind, :data_id, :denominator # kind: 0=None, 1=Item, 2=Weapon, 3=Armor

      def initialize
        @kind = 0; @data_id = 1; @denominator = 1
      end
    end # DropItem
  end # Enemy

  class State < RPG::BaseItem
    attr_accessor :restriction, :priority, :remove_at_battle_end, :remove_by_restriction
    attr_accessor :auto_removal_timing, :min_turns, :max_turns, :remove_by_damage
    attr_accessor :chance_by_damage, :remove_by_walking, :steps_to_remove
    attr_accessor :message1, :message2, :message3, :message4
    # inherits features

    def unpack_names(rgss_version = "RGSS3")
      super(rgss_version)
      Utils.unpack_names_for(self, :message1, :message2, :message3, :message4)
    end

    def initialize(rgss_version = "RGSS3")
      super(rgss_version)
      @restriction = 0; @priority = 50
      @remove_at_battle_end = false; @remove_by_restriction = false
      @auto_removal_timing = 0; @min_turns = 1; @max_turns = 1
      @remove_by_damage = false; @chance_by_damage = 100
      @remove_by_walking = false; @steps_to_remove = 100
      @message1 = ""; @message2 = ""; @message3 = ""; @message4 = ""
      # Ensure RGSS2 attrs removed
      RPG.remove_ivar_if_exists(self, :@atk_rate)
      RPG.remove_ivar_if_exists(self, :@def_rate)
      RPG.remove_ivar_if_exists(self, :@spi_rate)
      RPG.remove_ivar_if_exists(self, :@agi_rate)
      RPG.remove_ivar_if_exists(self, :@nonresistance)
      RPG.remove_ivar_if_exists(self, :@offset_by_opposite)
      RPG.remove_ivar_if_exists(self, :@slip_damage)
      RPG.remove_ivar_if_exists(self, :@reduce_hit_ratio)
      RPG.remove_ivar_if_exists(self, :@battle_only)
      RPG.remove_ivar_if_exists(self, :@release_by_damage)
      RPG.remove_ivar_if_exists(self, :@hold_turn)
      RPG.remove_ivar_if_exists(self, :@auto_release_prob)
      RPG.remove_ivar_if_exists(self, :@element_set)
      RPG.remove_ivar_if_exists(self, :@state_set)
    end
  end # State

  # Tileset is RGSS3 specific
  class Tileset
    include Jsonable
    attr_accessor :id, :mode, :name, :tileset_names, :flags, :note

    def unpack_names(rgss_version = "RGSS3")
      Utils.unpack_names_for(self, :name, :note)
      @tileset_names.map! { |name| name.is_a?(String) ? RPG.unpack_str(name) : name }
    end

    def initialize
      @id = 0; @mode = 1; @name = ""
      @tileset_names = Array.new(9) { "" } # A1-A5, B, C, D, E
      @flags = Table.new([1, 8192, 1, 1, 8192]) # 1 dimension, 8192 elements
      # Set default flags
      @flags[0] = 0x0010
      (2048..2815).each { |i| @flags[i] = 0x000F } # Autotiles A1-A4
      (4352..8191).each { |i| @flags[i] = 0x000F } # Tiles B-E
      @note = ""
    end
  end # Tileset

  # Nested classes for RGSS3
  class Map::Encounter
    include Jsonable
    attr_accessor :troop_id, :weight, :region_set

    def initialize
      @troop_id = 1; @weight = 10; @region_set = []
    end
  end

  class BaseItem::Feature
    include Jsonable
    attr_accessor :code, :data_id, :value

    def initialize(code = 0, data_id = 0, value = 0)
      @code = code; @data_id = data_id; @value = value
    end
  end

  class UsableItem::Effect
    include Jsonable
    attr_accessor :code, :data_id, :value1, :value2

    def initialize(code = 0, data_id = 0, value1 = 0, value2 = 0)
      @code = code; @data_id = data_id; @value1 = value1; @value2 = value2
    end
  end

  class UsableItem::Damage
    include Jsonable
    attr_accessor :type, :element_id, :formula, :variance, :critical

    def unpack_names(rgss_version = "RGSS3")
      Utils.unpack_names_for(self, :formula)
    end

    def initialize
      @type = 0; @element_id = 0; @formula = "0"; @variance = 20; @critical = false
    end
  end
end # RPG Module additions for RGSS3
