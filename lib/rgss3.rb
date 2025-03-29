# encoding: utf-8
# rvdata2json/lib/rgss3.rb
# 包含 RGSS3 (RPG Maker VX Ace) 特有的类定义或对共享类的修改

require_relative "shared" # 加载共享定义

# --- RGSS3 特有类定义或覆盖 ---

module RPG
  # 角色类 (RGSS3 版本)
  class Actor < RPG::BaseItem
    attr_accessor :nickname, :class_id, :initial_level, :max_level
    attr_accessor :character_name, :character_index, :face_name, :face_index, :equips

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      RPG::BaseItem.instance_method(:unpack_names).bind(self).call
      Utils.unpack_names_for(self, :nickname, :character_name, :face_name)
    end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS3")
      RPG::BaseItem.instance_method(:initialize).bind(self).call("RGSS3")
      @nickname = ""; @class_id = 1; @initial_level = 1; @max_level = 99
      @character_name = ""; @character_index = 0; @face_name = ""; @face_index = 0
      @equips = [0, 0, 0, 0, 0]
    end
  end # Actor

  # 职业类 (RGSS3 版本)
  class Class < RPG::BaseItem
    attr_accessor :exp_params, :params, :learnings

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      RPG::BaseItem.instance_method(:unpack_names).bind(self).call
      @learnings.each { |l| l.unpack_names if l.respond_to?(:unpack_names) }
    end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS3")
      RPG::BaseItem.instance_method(:initialize).bind(self).call("RGSS3")
      @exp_params = [30, 20, 30, 30]
      @params = Table.new([2, 8, 100, 1, 800]) # 默认能力表 (8项, 100级)
      @learnings = [] # [RPG::Class::Learning]
      # 添加默认特性
      @features.push(RPG::BaseItem::Feature.new(23, 0, 1))    # 特殊标志: 自动战斗?
      @features.push(RPG::BaseItem::Feature.new(22, 0, 0.95)) # 命中率
      @features.push(RPG::BaseItem::Feature.new(22, 1, 0.05)) # 回避率
      @features.push(RPG::BaseItem::Feature.new(22, 2, 0.04)) # 会心一击率
      @features.push(RPG::BaseItem::Feature.new(41, 1))    # 可装备武器类型 1
      @features.push(RPG::BaseItem::Feature.new(51, 1))    # 攻击时属性 1
      @features.push(RPG::BaseItem::Feature.new(52, 1))    # 攻击时状态 1
    end

    # 职业学习技能类 (RGSS3 嵌套类)
    class Learning
      include Jsonable
      attr_accessor :level, :skill_id, :note

      # 解包 (由 Converter::JsonExporter 处理)
      def unpack_names
        Utils.unpack_names_for(self, :note)
      end

      def initialize
        @level = 1; @skill_id = 1; @note = ""
      end
    end # Learning
  end # Class

  # 技能类 (RGSS3 版本)
  class Skill < RPG::UsableItem
    attr_accessor :stype_id, :mp_cost, :tp_cost, :message1, :message2
    attr_accessor :required_wtype_id1, :required_wtype_id2

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      RPG::UsableItem.instance_method(:unpack_names).bind(self).call # 调用父类解包
      Utils.unpack_names_for(self, :message1, :message2) # 解包自身消息
      @damage&.unpack_names if @damage.respond_to?(:unpack_names) # 解包 Damage 公式
    end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS3")
      RPG::UsableItem.instance_method(:initialize).bind(self).call("RGSS3")
      @scope = 1 # 覆盖默认值
      @stype_id = 1; @mp_cost = 0; @tp_cost = 0
      @message1 = ""; @message2 = ""
      @required_wtype_id1 = 0; @required_wtype_id2 = 0
    end
  end # Skill

  # 物品类 (RGSS3 版本)
  class Item < RPG::UsableItem
    attr_accessor :itype_id, :price, :consumable

    # 解包 (继承自 UsableItem -> BaseItem)
    # def unpack_names; super; end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS3")
      RPG::UsableItem.instance_method(:initialize).bind(self).call("RGSS3")
      @scope = 7 # 覆盖默认值
      @itype_id = 1; @price = 0; @consumable = true
    end
  end # Item

  # 装备物品基类 (RGSS3)
  class EquipItem < RPG::BaseItem
    attr_accessor :price, :etype_id, :params

    # 解包 (继承自 BaseItem)
    # def unpack_names; super; end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS3")
      RPG::BaseItem.instance_method(:initialize).bind(self).call("RGSS3")
      @price = 0; @etype_id = 0; @params = [0] * 8
    end
  end # EquipItem

  # 武器类 (RGSS3 版本)
  class Weapon < RPG::EquipItem
    attr_accessor :wtype_id, :animation_id

    # 解包 (继承自 EquipItem -> BaseItem)
    # def unpack_names; super; end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS3")
      RPG::EquipItem.instance_method(:initialize).bind(self).call

      @etype_id = 0 # 武器的 etype_id 为 0
      @wtype_id = 0; @animation_id = 0
      # 添加默认特性
      @features.push(RPG::BaseItem::Feature.new(31, 1, 0)) # 攻击属性: 物理
      @features.push(RPG::BaseItem::Feature.new(22, 0, 0)) # 命中率: +0
    end
  end # Weapon

  # 防具类 (RGSS3 版本)
  class Armor < RPG::EquipItem
    attr_accessor :atype_id

    # 解包 (继承自 EquipItem -> BaseItem)
    # def unpack_names; super; end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS3")
      RPG::EquipItem.instance_method(:initialize).bind(self).call
      # etype_id (1-4) 通常由编辑器根据 atype_id 设置，这里设个默认值
      @etype_id = 1 # 默认为盾
      @atype_id = 0 # 默认为通用防具?
      # 添加默认特性
      @features.push(RPG::BaseItem::Feature.new(22, 1, 0)) # 回避率: +0
    end
  end # Armor

  # 敌人数据类 (RGSS3 版本)
  class Enemy < RPG::BaseItem
    attr_accessor :battler_name, :battler_hue, :params, :exp, :gold, :drop_items, :actions

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      RPG::BaseItem.instance_method(:unpack_names).bind(self).call
      Utils.unpack_names_for(self, :battler_name)
      # Action 和 DropItem 没有需要解包的字符串
    end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS3")
      RPG::BaseItem.instance_method(:initialize).bind(self).call("RGSS3")
      @battler_name = ""; @battler_hue = 0
      @params = [100, 0, 10, 10, 10, 10, 10, 10] # MHP,MMP,ATK,DEF,MAT,MDF,AGI,LUK
      @exp = 0; @gold = 0
      @drop_items = Array.new(3) { RPG::Enemy::DropItem.new }
      @actions = [RPG::Enemy::Action.new]
      # 添加默认特性
      @features.push(RPG::BaseItem::Feature.new(22, 0, 0.95)) # 命中率
      @features.push(RPG::BaseItem::Feature.new(22, 1, 0.05)) # 回避率
      @features.push(RPG::BaseItem::Feature.new(31, 1, 0))    # 攻击属性: 物理
    end

    # 敌人行动模式类 (RGSS3 嵌套类)
    class Action
      include Jsonable
      attr_accessor :skill_id, :condition_type, :condition_param1, :condition_param2, :rating

      def initialize
        @skill_id = 1; @condition_type = 0
        @condition_param1 = 0; @condition_param2 = 0; @rating = 5
      end
    end # Action

    # 敌人掉落物品类 (RGSS3 嵌套类)
    class DropItem
      include Jsonable
      attr_accessor :kind, :data_id, :denominator

      def initialize
        @kind = 0; @data_id = 1; @denominator = 1
      end
    end # DropItem
  end # Enemy

  # 状态类 (RGSS3 版本)
  class State < RPG::BaseItem
    attr_accessor :restriction, :priority, :remove_at_battle_end, :remove_by_restriction
    attr_accessor :auto_removal_timing, :min_turns, :max_turns, :remove_by_damage
    attr_accessor :chance_by_damage, :remove_by_walking, :steps_to_remove
    attr_accessor :message1, :message2, :message3, :message4

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      RPG::BaseItem.instance_method(:unpack_names).bind(self).call
      Utils.unpack_names_for(self, :message1, :message2, :message3, :message4)
    end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize #(rgss_version = "RGSS3")
      RPG::BaseItem.instance_method(:initialize).bind(self).call("RGSS3")
      @restriction = 0; @priority = 50
      @remove_at_battle_end = false; @remove_by_restriction = false
      @auto_removal_timing = 0; @min_turns = 1; @max_turns = 1
      @remove_by_damage = false; @chance_by_damage = 100
      @remove_by_walking = false; @steps_to_remove = 100
      @message1 = ""; @message2 = ""; @message3 = ""; @message4 = ""
    end
  end # State

  # 图块集类 (仅 RGSS3 有)
  class Tileset
    include Jsonable
    attr_accessor :id, :mode, :name, :tileset_names, :flags, :note

    def unpack_names
      Utils.unpack_names_for(self, :name, :note)
      @tileset_names.map! { |name| name.is_a?(String) ? RPG.unpack_str(name) : name }
    end

    # 初始化 (由 Converter::RvdataRestorer 调用)
    def initialize
      @id = 0; @mode = 1; @name = ""
      @tileset_names = Array.new(9) { "" } # A1-A5, B, C, D, E

      # --- 保持正确的 Table 初始化方式 ---
      # 创建 1 维、大小为 8192 的 Table
      # 参数: [维度数, xsize, ysize, zsize, 总元素数]
      @flags = Table.new([1, 8192, 1, 1, 8192])

      # 设置一些默认标志（可选）
      @flags[0] = 0x0010 # Star passability for the first tile
      (2048..2815).each { |i| @flags[i] = 0x000F } # Default for Autotiles A1-A4
      (4352..8191).each { |i| @flags[i] = 0x000F } # Default for Tiles B-E
      @note = ""
    end
  end # Tileset

  # 地图遇敌信息类 (RGSS3 Map 嵌套类)
  class Map::Encounter
    include Jsonable
    attr_accessor :troop_id, :weight, :region_set

    def initialize
      @troop_id = 1; @weight = 10; @region_set = []
    end
  end # Map::Encounter

  # 基础物品特性类 (RGSS3 BaseItem 嵌套类)
  class BaseItem::Feature
    include Jsonable
    attr_accessor :code, :data_id, :value

    def initialize(code = 0, data_id = 0, value = 0)
      @code = code; @data_id = data_id; @value = value
    end
  end # BaseItem::Feature

  # 可使用物品/技能的效果类 (RGSS3 UsableItem 嵌套类)
  class UsableItem::Effect
    include Jsonable
    attr_accessor :code, :data_id, :value1, :value2

    def initialize(code = 0, data_id = 0, value1 = 0, value2 = 0)
      @code = code; @data_id = data_id; @value1 = value1; @value2 = value2
    end
  end # UsableItem::Effect

  # 可使用物品/技能的伤害类 (RGSS3 UsableItem 嵌套类)
  class UsableItem::Damage
    include Jsonable
    attr_accessor :type, :element_id, :formula, :variance, :critical

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      Utils.unpack_names_for(self, :formula)
    end

    def initialize
      @type = 0; @element_id = 0; @formula = "0"; @variance = 20; @critical = false
    end
  end # UsableItem::Damage
end # RPG Module additions for RGSS3
