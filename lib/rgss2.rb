# encoding: utf-8
# rvdata2json/lib/rgss2.rb
# 包含 RGSS2 (RPG Maker VX) 特有的类定义或对共享类的修改

require_relative "shared" # 加载共享定义

# --- RGSS2 特有模块修改 ---
module RPG
  # 覆盖 pack_str，RGSS2 Marshal 时字符串通常不进行编码转换
  def self.pack_str(str)
    str
  end
end

# --- RGSS2 特有类定义 ---
module RPG
  # 区域类 (仅 RGSS2 有)
  class Area
    include Jsonable
    attr_accessor :id, :name, :map_id, :rect, :encounter_list, :order

    def unpack_names(rgss_version = "RGSS2") # Add version param
      Utils.unpack_names_for(self, :name)
    end

    def initialize
      @id = 0; @name = ""; @map_id = 0
      @rect = Rect.new
      @encounter_list = [] # Simple array in RGSS2
      @order = 0
    end
  end # Area

  # --- Reopen shared classes to adjust for RGSS2 ---
  # (These definitions replace the need for the Support modules)

  class Actor < RPG::BaseItem
    attr_accessor :class_id, :initial_level, :exp_basis, :exp_inflation
    attr_accessor :character_name, :character_index, :face_name, :face_index, :parameters
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id
    attr_accessor :two_swords_style, :fix_equipment, :auto_battle, :super_guard
    attr_accessor :pharmacology, :critical_bonus

    def unpack_names(rgss_version = "RGSS2")
      super(rgss_version) # Call BaseItem unpack
      Utils.unpack_names_for(self, :character_name, :face_name) # Unpack specific names
    end

    def initialize(rgss_version = "RGSS2")
      # Call BaseItem's initialize FIRST, ensuring features is nil for RGSS2
      super(rgss_version)
      # Now set RGSS2 specific attributes
      @class_id = 1; @initial_level = 1; @exp_basis = 25; @exp_inflation = 35
      @character_name = ""; @character_index = 0; @face_name = ""; @face_index = 0
      @parameters = Table.new([2, 6, 99, 1, 6 * 99]) # 6 params, 99 levels
      @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
      @two_swords_style = false; @fix_equipment = false; @auto_battle = false
      @super_guard = false; @pharmacology = false; @critical_bonus = false
      # Ensure RGSS3 attrs are removed (might be redundant if BaseItem handles it)
      RPG.remove_ivar_if_exists(self, :@nickname)
      RPG.remove_ivar_if_exists(self, :@max_level)
      RPG.remove_ivar_if_exists(self, :@equips)
    end
  end # Actor

  class Armor < RPG::BaseItem
    attr_accessor :kind, :price, :eva, :atk, :def, :spi, :agi
    attr_accessor :prevent_critical, :half_mp_cost, :double_exp_gain, :auto_hp_recover
    attr_accessor :element_set, :state_set

    def initialize(rgss_version = "RGSS2")
      super(rgss_version)
      @kind = 0; @price = 0; @eva = 0; @atk = 0; @def = 0; @spi = 0; @agi = 0
      @prevent_critical = false; @half_mp_cost = false; @double_exp_gain = false; @auto_hp_recover = false
      @element_set = []; @state_set = []
      # Ensure RGSS3 EquipItem attrs removed
      RPG.remove_ivar_if_exists(self, :@etype_id)
      RPG.remove_ivar_if_exists(self, :@params)
      RPG.remove_ivar_if_exists(self, :@atype_id) # From RGSS3 Armor
    end
  end # Armor

  class Weapon < RPG::BaseItem
    attr_accessor :animation_id, :price, :hit, :atk, :def, :spi, :agi
    attr_accessor :two_handed, :fast_attack, :dual_attack, :critical_bonus
    attr_accessor :element_set, :state_set

    def initialize(rgss_version = "RGSS2")
      super(rgss_version)
      @animation_id = 0; @price = 0; @hit = 95; @atk = 0; @def = 0; @spi = 0; @agi = 0
      @two_handed = false; @fast_attack = false; @dual_attack = false; @critical_bonus = false
      @element_set = []; @state_set = []
      # Ensure RGSS3 EquipItem attrs removed
      RPG.remove_ivar_if_exists(self, :@etype_id)
      RPG.remove_ivar_if_exists(self, :@params)
      RPG.remove_ivar_if_exists(self, :@wtype_id) # From RGSS3 Weapon
    end
  end # Weapon

  class Item < RPG::UsableItem
    attr_accessor :price, :consumable, :hp_recovery_rate, :hp_recovery
    attr_accessor :mp_recovery_rate, :mp_recovery, :parameter_type, :parameter_points

    def initialize(rgss_version = "RGSS2")
      super(rgss_version) # Calls UsableItem init, which handles its version logic
      @scope = 7 # Override default scope
      @price = 0; @consumable = true
      @hp_recovery_rate = 0; @hp_recovery = 0; @mp_recovery_rate = 0; @mp_recovery = 0
      @parameter_type = 0; @parameter_points = 0
      # Ensure RGSS3 attrs removed (UsableItem init should handle some)
      RPG.remove_ivar_if_exists(self, :@itype_id)
    end
  end # Item

  class Skill < RPG::UsableItem
    attr_accessor :mp_cost, :hit, :message1, :message2

    def unpack_names(rgss_version = "RGSS2")
      super(rgss_version) # Call parent unpack
      Utils.unpack_names_for(self, :message1, :message2)
    end

    def initialize(rgss_version = "RGSS2")
      super(rgss_version)
      @scope = 1 # Override default scope
      @mp_cost = 0; @hit = 100; @message1 = ""; @message2 = ""
      # Ensure RGSS3 attrs removed (UsableItem init handles some)
      RPG.remove_ivar_if_exists(self, :@stype_id)
      RPG.remove_ivar_if_exists(self, :@tp_cost)
      RPG.remove_ivar_if_exists(self, :@required_wtype_id1)
      RPG.remove_ivar_if_exists(self, :@required_wtype_id2)
    end
  end # Skill

  # Class is unique to RGSS2 (no BaseItem inheritance)
  class Class
    include Jsonable
    attr_accessor :id, :name, :position, :weapon_set, :armor_set
    attr_accessor :element_ranks, :state_ranks, :learnings
    attr_accessor :skill_name_valid, :skill_name

    def unpack_names(rgss_version = "RGSS2")
      Utils.unpack_names_for(self, :name, :skill_name)
      # learnings handled recursively by exporter
    end

    def initialize
      @id = 0; @name = ""; @position = 0
      @weapon_set = []; @armor_set = []
      # Assume 1 element/state initially, size might vary based on System data
      @element_ranks = Table.new([1, 1, 1, 1, 1])
      @state_ranks = Table.new([1, 1, 1, 1, 1])
      @learnings = [] # Array of RPG::Class::Learning
      @skill_name_valid = false; @skill_name = ""
    end

    class Learning
      include Jsonable
      attr_accessor :level, :skill_id

      def initialize
        @level = 1; @skill_id = 1
      end
    end # Learning
  end # Class

  class Enemy < RPG::BaseItem
    attr_accessor :battler_name, :battler_hue, :maxhp, :maxmp, :atk, :def, :spi, :agi
    attr_accessor :hit, :eva, :exp, :gold, :drop_item1, :drop_item2, :levitate, :has_critical
    attr_accessor :element_ranks, :state_ranks, :actions

    def unpack_names(rgss_version = "RGSS2")
      super(rgss_version)
      Utils.unpack_names_for(self, :battler_name)
      # drop_items/actions handled recursively
    end

    def initialize(rgss_version = "RGSS2")
      super(rgss_version)
      @battler_name = ""; @battler_hue = 0
      @maxhp = 10; @maxmp = 10; @atk = 10; @def = 10; @spi = 10; @agi = 10
      @hit = 95; @eva = 5; @exp = 0; @gold = 0
      @drop_item1 = RPG::Enemy::DropItem.new # Instance, not array
      @drop_item2 = RPG::Enemy::DropItem.new # Instance, not array
      @levitate = false; @has_critical = false
      @element_ranks = Table.new([1, 1, 1, 1, 1])
      @state_ranks = Table.new([1, 1, 1, 1, 1])
      @actions = [RPG::Enemy::Action.new]
      # Ensure RGSS3 attrs removed
      RPG.remove_ivar_if_exists(self, :@params)
      RPG.remove_ivar_if_exists(self, :@drop_items) # The array version
    end

    class Action
      include Jsonable
      attr_accessor :kind, :basic, :skill_id, :condition_type, :condition_param1, :condition_param2, :rating

      def initialize
        @kind = 0; @basic = 0; @skill_id = 1; @condition_type = 0
        @condition_param1 = 0; @condition_param2 = 0; @rating = 5
      end

      def skill?; @kind == 1; end
    end # Action

    class DropItem
      include Jsonable
      attr_accessor :kind, :item_id, :weapon_id, :armor_id, :denominator

      def initialize
        @kind = 0; @item_id = 1; @weapon_id = 1; @armor_id = 1; @denominator = 1
      end
    end # DropItem
  end # Enemy

  class State < RPG::BaseItem
    attr_accessor :restriction, :priority, :atk_rate, :def_rate, :spi_rate, :agi_rate
    attr_accessor :nonresistance, :offset_by_opposite, :slip_damage, :reduce_hit_ratio
    attr_accessor :battle_only, :release_by_damage, :hold_turn, :auto_release_prob
    attr_accessor :message1, :message2, :message3, :message4
    attr_accessor :element_set, :state_set

    def unpack_names(rgss_version = "RGSS2")
      super(rgss_version)
      Utils.unpack_names_for(self, :message1, :message2, :message3, :message4)
    end

    def initialize(rgss_version = "RGSS2")
      super(rgss_version)
      @restriction = 0; @priority = 5; @atk_rate = 100; @def_rate = 100; @spi_rate = 100; @agi_rate = 100
      @nonresistance = false; @offset_by_opposite = false; @slip_damage = false; @reduce_hit_ratio = false
      @battle_only = true; @release_by_damage = false; @hold_turn = 0; @auto_release_prob = 0
      @message1 = ""; @message2 = ""; @message3 = ""; @message4 = ""
      @element_set = []; @state_set = []
      # Ensure RGSS3 attrs removed
      RPG.remove_ivar_if_exists(self, :@remove_at_battle_end)
      RPG.remove_ivar_if_exists(self, :@remove_by_restriction)
      RPG.remove_ivar_if_exists(self, :@auto_removal_timing)
      RPG.remove_ivar_if_exists(self, :@min_turns)
      RPG.remove_ivar_if_exists(self, :@max_turns)
      RPG.remove_ivar_if_exists(self, :@remove_by_damage)
      RPG.remove_ivar_if_exists(self, :@chance_by_damage)
      RPG.remove_ivar_if_exists(self, :@remove_by_walking)
      RPG.remove_ivar_if_exists(self, :@steps_to_remove)
    end
  end # State
end # RPG Module additions for RGSS2
