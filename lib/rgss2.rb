# encoding: utf-8
# rvdata2json/lib/rgss2.rb
# 包含 RGSS2 (RPG Maker VX) 特有的类定义或对共享类的修改

require_relative "shared" # 加载共享定义

# --- RGSS2 特有模块修改 ---
module RPG
  # 在 RGSS2 中，Marshal dump 时字符串通常保持其原始（可能非 UTF-8）状态
  # 因此 pack_str 不执行任何转换，直接返回原字符串。
  # @param str [String] 输入字符串
  # @return [String] 原样返回字符串
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

    # 解包区域名称 (由 Converter::JsonExporter 处理)
    def unpack_names
      Utils.unpack_names_for(self, :name)
      # encounter_list 在 RGSS2 中是简单的数组 [troop_id, weight, ???]，不需要解包
    end

    def initialize
      @id = 0
      @name = ""
      @map_id = 0
      @rect = Rect.new # Rect 定义在 shared.rb
      @encounter_list = []
      @order = 0
    end
  end # Area

  # 角色类 (RGSS2 版本)
  class Actor < RPG::BaseItem
    attr_accessor :class_id, :initial_level, :exp_basis, :exp_inflation
    attr_accessor :character_name, :character_index, :face_name, :face_index, :parameters
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id
    attr_accessor :two_swords_style, :fix_equipment, :auto_battle, :super_guard
    attr_accessor :pharmacology, :critical_bonus

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      # 调用 BaseItem 的 unpack_names
      RPG::BaseItem.instance_method(:unpack_names).bind(self).call
      # 解包 Actor 特有的 name/character_name/face_name (如果 BaseItem 没处理 name)
      Utils.unpack_names_for(self, :name, :character_name, :face_name)
    end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS2") # Restorer 会传递版本
      # 调用父类 BaseItem 的初始化
      RPG::BaseItem.instance_method(:initialize).bind(self).call("RGSS2")

      # RGSS2 特有属性
      @class_id = 1
      @initial_level = 1
      @exp_basis = 25
      @exp_inflation = 35
      @character_name = ""
      @character_index = 0
      @face_name = ""
      @face_index = 0
      @parameters = Table.new([2, 6, 100, 1, 600]) # 默认参数表 (6项, 100级)
      @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
      @two_swords_style = false; @fix_equipment = false; @auto_battle = false
      @super_guard = false; @pharmacology = false; @critical_bonus = false
    end
  end # Actor

  # 防具类 (RGSS2 版本)
  class Armor < RPG::BaseItem
    attr_accessor :kind, :price, :eva, :atk, :def, :spi, :agi
    attr_accessor :prevent_critical, :half_mp_cost, :double_exp_gain, :auto_hp_recover
    attr_accessor :element_set, :state_set

    # 解包 (由 Converter::JsonExporter 处理)
    # def unpack_names; super; end # 继承自 BaseItem

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS2")
      RPG::BaseItem.instance_method(:initialize).bind(self).call("RGSS2")
      @kind = 0; @price = 0; @eva = 0; @atk = 0; @def = 0; @spi = 0; @agi = 0
      @prevent_critical = false; @half_mp_cost = false; @double_exp_gain = false; @auto_hp_recover = false
      @element_set = []; @state_set = []
    end
  end # Armor

  # 武器类 (RGSS2 版本)
  class Weapon < RPG::BaseItem
    attr_accessor :animation_id, :price, :hit, :atk, :def, :spi, :agi
    attr_accessor :two_handed, :fast_attack, :dual_attack, :critical_bonus
    attr_accessor :element_set, :state_set

    # 解包 (由 Converter::JsonExporter 处理)
    # def unpack_names; super; end # 继承自 BaseItem

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS2")
      RPG::BaseItem.instance_method(:initialize).bind(self).call("RGSS2")
      @animation_id = 0; @price = 0; @hit = 95; @atk = 0; @def = 0; @spi = 0; @agi = 0
      @two_handed = false; @fast_attack = false; @dual_attack = false; @critical_bonus = false
      @element_set = []; @state_set = []
    end
  end # Weapon

  # 物品类 (RGSS2 版本)
  class Item < RPG::UsableItem
    attr_accessor :price, :consumable, :hp_recovery_rate, :hp_recovery
    attr_accessor :mp_recovery_rate, :mp_recovery, :parameter_type, :parameter_points

    # 解包 (由 Converter::JsonExporter 处理)
    # def unpack_names; super; end # 继承自 UsableItem -> BaseItem

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS2")
      RPG::UsableItem.instance_method(:initialize).bind(self).call("RGSS2")
      @scope = 7 # 覆盖默认值
      @price = 0; @consumable = true
      @hp_recovery_rate = 0; @hp_recovery = 0; @mp_recovery_rate = 0; @mp_recovery = 0
      @parameter_type = 0; @parameter_points = 0
    end
  end # Item

  # 技能类 (RGSS2 版本)
  class Skill < RPG::UsableItem
    attr_accessor :mp_cost, :hit, :message1, :message2

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      RPG::UsableItem.instance_method(:unpack_names).bind(self).call # 调用父类解包
      Utils.unpack_names_for(self, :message1, :message2) # 解包自身消息
    end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS2")
      RPG::UsableItem.instance_method(:initialize).bind(self).call("RGSS2")
      @scope = 1 # 覆盖默认值
      @mp_cost = 0; @hit = 100; @message1 = ""; @message2 = ""
    end
  end # Skill

  # 职业类 (仅 RGSS2 有此独立定义，无 BaseItem 继承)
  class Class
    include Jsonable
    attr_accessor :id, :name, :position, :weapon_set, :armor_set
    attr_accessor :element_ranks, :state_ranks, :learnings
    attr_accessor :skill_name_valid, :skill_name # 这两个属性用途不明

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      Utils.unpack_names_for(self, :name, :skill_name)
      # learnings 内部是 Learning 对象，没有需要解包的字符串
    end

    def initialize
      @id = 0; @name = ""; @position = 0
      @weapon_set = []; @armor_set = []
      @element_ranks = Table.new([1, 1]) # 默认1个属性
      @state_ranks = Table.new([1, 1])   # 默认1个状态
      @learnings = [] # [RPG::Class::Learning]
      @skill_name_valid = false; @skill_name = ""
    end

    # 职业学习技能类 (RGSS2 嵌套类)
    class Learning
      include Jsonable
      attr_accessor :level, :skill_id

      def initialize
        @level = 1
        @skill_id = 1
      end
    end # Learning
  end # Class

  # 敌人数据类 (RGSS2 版本)
  class Enemy < RPG::BaseItem
    attr_accessor :battler_name, :battler_hue, :maxhp, :maxmp, :atk, :def, :spi, :agi
    attr_accessor :hit, :eva, :exp, :gold, :drop_item1, :drop_item2, :levitate, :has_critical
    attr_accessor :element_ranks, :state_ranks, :actions

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      RPG::BaseItem.instance_method(:unpack_names).bind(self).call
      Utils.unpack_names_for(self, :battler_name)
      # Action 和 DropItem 没有需要解包的字符串
    end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS2")
      RPG::BaseItem.instance_method(:initialize).bind(self).call("RGSS2")
      @battler_name = ""; @battler_hue = 0
      @maxhp = 10; @maxmp = 10; @atk = 10; @def = 10; @spi = 10; @agi = 10
      @hit = 95; @eva = 5; @exp = 0; @gold = 0
      @drop_item1 = RPG::Enemy::DropItem.new
      @drop_item2 = RPG::Enemy::DropItem.new
      @levitate = false; @has_critical = false
      @element_ranks = Table.new([1, 1]) # 默认1个属性
      @state_ranks = Table.new([1, 1])   # 默认1个状态
      @actions = [RPG::Enemy::Action.new]
    end

    # 敌人行动模式类 (RGSS2 嵌套类)
    class Action
      include Jsonable
      attr_accessor :kind, :basic, :skill_id, :condition_type, :condition_param1, :condition_param2, :rating

      def initialize
        @kind = 0; @basic = 0; @skill_id = 1; @condition_type = 0
        @condition_param1 = 0; @condition_param2 = 0; @rating = 5
      end

      def skill?; @kind == 1; end
    end # Action

    # 敌人掉落物品类 (RGSS2 嵌套类)
    class DropItem
      include Jsonable
      attr_accessor :kind, :item_id, :weapon_id, :armor_id, :denominator

      def initialize
        @kind = 0; @item_id = 1; @weapon_id = 1; @armor_id = 1; @denominator = 1
      end
    end # DropItem
  end # Enemy

  # 状态类 (RGSS2 版本)
  class State < RPG::BaseItem
    attr_accessor :restriction, :priority, :atk_rate, :def_rate, :spi_rate, :agi_rate
    attr_accessor :nonresistance, :offset_by_opposite, :slip_damage, :reduce_hit_ratio
    attr_accessor :battle_only, :release_by_damage, :hold_turn, :auto_release_prob
    attr_accessor :message1, :message2, :message3, :message4
    attr_accessor :element_set, :state_set

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      RPG::BaseItem.instance_method(:unpack_names).bind(self).call
      Utils.unpack_names_for(self, :message1, :message2, :message3, :message4)
    end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS2")
      RPG::BaseItem.instance_method(:initialize).bind(self).call("RGSS2")
      @restriction = 0; @priority = 5; @atk_rate = 100; @def_rate = 100; @spi_rate = 100; @agi_rate = 100
      @nonresistance = false; @offset_by_opposite = false; @slip_damage = false; @reduce_hit_ratio = false
      @battle_only = true; @release_by_damage = false; @hold_turn = 0; @auto_release_prob = 0
      @message1 = ""; @message2 = ""; @message3 = ""; @message4 = ""
      @element_set = []; @state_set = []
    end
  end # State
end # RPG Module additions for RGSS2
