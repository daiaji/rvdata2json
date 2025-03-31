# 包含 RGSS2 (RPG Maker VX) 特有的类定义或对共享类的修改

require_relative "shared" # 加载共享定义

# --- RGSS2 特有类定义 ---
module RPG
  # 区域类 (仅 RGSS2 有)
  class Area
    attr_accessor :id, :name, :map_id, :rect, :encounter_list, :order # ID, 名称, 地图ID, 范围(Rect), 遇敌列表, 顺序

    # 解包区域名称
    def unpack_names(rgss_version = "RGSS2") # 添加版本参数以保持接口一致
      Utils.unpack_names_for(self, :name)
    end

    # 初始化 Area 对象
    def initialize
      @id = 0; @name = ""; @map_id = 0
      @rect = Rect.new # 初始化矩形范围
      @encounter_list = [] # RGSS2 遇敌列表是简单数组 [troop_id, weight]
      @order = 0
    end
  end # Area

  # --- 重打开共享类以适应 RGSS2 ---
  # (这些定义调整了继承自 shared.rb 的类，使其符合 RGSS2 规范)

  # 角色类 (调整自 shared.rb 的 RPG::BaseItem)
  class Actor < RPG::BaseItem
    # RGSS2 特有属性
    attr_accessor :class_id, :initial_level, :exp_basis, :exp_inflation # 职业ID, 初始等级, 经验基础值/增长度
    attr_accessor :character_name, :character_index, :face_name, :face_index, :parameters # 行走图/头像文件名/索引, 能力值(Table)
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id # 初始装备ID (武器, 盾, 头, 身, 饰品)
    attr_accessor :two_swords_style, :fix_equipment, :auto_battle, :super_guard # 特性: 二刀流, 固定装备, 自动战斗, 超级防御
    attr_accessor :pharmacology, :critical_bonus # 特性: 药理知识, 会心一击修正

    # 解包角色相关名称
    def unpack_names(rgss_version = "RGSS2")
      super(rgss_version) # 调用 BaseItem 的 unpack_names (处理 name, description, note)
      Utils.unpack_names_for(self, :character_name, :face_name) # 解包行走图和头像文件名
    end

    # 初始化 Actor 对象 (RGSS2 版本)
    def initialize(rgss_version = "RGSS2")
      super(rgss_version)
      # 设置 RGSS2 特有属性的默认值
      @class_id = 1; @initial_level = 1; @exp_basis = 25; @exp_inflation = 35
      @character_name = ""; @character_index = 0; @face_name = ""; @face_index = 0
      @parameters = Table.new([2, 6, 99, 1, 6 * 99]) # 6种能力值(HP,MP,ATK,DEF,SPI,AGI), 99级
      @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
      @two_swords_style = false; @fix_equipment = false; @auto_battle = false
      @super_guard = false; @pharmacology = false; @critical_bonus = false
      # 确保移除 RGSS3 可能存在的属性
      RPG.remove_ivar_if_exists(self, :@nickname)
      RPG.remove_ivar_if_exists(self, :@max_level)
      RPG.remove_ivar_if_exists(self, :@equips)
    end
  end # Actor

  # 防具类 (调整自 shared.rb 的 RPG::BaseItem)
  class Armor < RPG::BaseItem
    # RGSS2 特有属性
    attr_accessor :kind, :price, :eva, :atk, :def, :spi, :agi # 种类(0盾,1头,2身,3饰), 价格, 回避修正, 攻击力, 防御力, 精神力, 敏捷力
    attr_accessor :prevent_critical, :half_mp_cost, :double_exp_gain, :auto_hp_recover # 特性: 防会心, MP消耗减半, EXP双倍, HP自动回复
    attr_accessor :element_set, :state_set # 防御元素集合, 防御状态集合

    # 初始化 Armor 对象 (RGSS2 版本)
    def initialize(rgss_version = "RGSS2")
      super(rgss_version) # 调用 BaseItem 初始化
      # 设置 RGSS2 特有属性默认值
      @kind = 0; @price = 0; @eva = 0; @atk = 0; @def = 0; @spi = 0; @agi = 0
      @prevent_critical = false; @half_mp_cost = false; @double_exp_gain = false; @auto_hp_recover = false
      @element_set = []; @state_set = []
      # 确保移除 RGSS3 可能存在的属性
      RPG.remove_ivar_if_exists(self, :@etype_id)
      RPG.remove_ivar_if_exists(self, :@params)
      RPG.remove_ivar_if_exists(self, :@atype_id)
    end
  end # Armor

  # 武器类 (调整自 shared.rb 的 RPG::BaseItem)
  class Weapon < RPG::BaseItem
    # RGSS2 特有属性
    attr_accessor :animation_id, :price, :hit, :atk, :def, :spi, :agi # 攻击动画ID, 价格, 命中率, 攻击力, 防御力, 精神力, 敏捷力
    attr_accessor :two_handed, :fast_attack, :dual_attack, :critical_bonus # 特性: 双手武器, 先制攻击, 连续攻击, 会心一击修正
    attr_accessor :element_set, :state_set # 攻击元素集合, 附加状态集合

    # 初始化 Weapon 对象 (RGSS2 版本)
    def initialize(rgss_version = "RGSS2")
      super(rgss_version) # 调用 BaseItem 初始化
      # 设置 RGSS2 特有属性默认值
      @animation_id = 0; @price = 0; @hit = 95; @atk = 0; @def = 0; @spi = 0; @agi = 0
      @two_handed = false; @fast_attack = false; @dual_attack = false; @critical_bonus = false
      @element_set = []; @state_set = []
      # 确保移除 RGSS3 可能存在的属性
      RPG.remove_ivar_if_exists(self, :@etype_id)
      RPG.remove_ivar_if_exists(self, :@params)
      RPG.remove_ivar_if_exists(self, :@wtype_id)
    end
  end # Weapon

  # 物品类 (调整自 shared.rb 的 RPG::UsableItem)
  class Item < RPG::UsableItem
    # RGSS2 特有属性
    attr_accessor :price, :consumable, :hp_recovery_rate, :hp_recovery # 价格, 是否消耗, HP恢复百分比, HP恢复固定值
    attr_accessor :mp_recovery_rate, :mp_recovery, :parameter_type, :parameter_points # MP恢复百分比/固定值, 能力值增加类型/点数

    # 初始化 Item 对象 (RGSS2 版本)
    def initialize(rgss_version = "RGSS2")
      super(rgss_version) # 调用 UsableItem 初始化
      @scope = 7 # 覆盖默认范围为 "己方单体"
      # 设置 RGSS2 特有属性默认值
      @price = 0; @consumable = true
      @hp_recovery_rate = 0; @hp_recovery = 0; @mp_recovery_rate = 0; @mp_recovery = 0
      @parameter_type = 0; @parameter_points = 0
      # 确保移除 RGSS3 可能存在的属性
      RPG.remove_ivar_if_exists(self, :@itype_id)
    end
  end # Item

  # 技能类 (调整自 shared.rb 的 RPG::UsableItem)
  class Skill < RPG::UsableItem
    # RGSS2 特有属性
    attr_accessor :mp_cost, :hit, :message1, :message2 # MP消耗, 命中率, 使用信息1/2

    # 解包技能相关名称
    def unpack_names(rgss_version = "RGSS2")
      super(rgss_version) # 调用 UsableItem 的 unpack_names
      Utils.unpack_names_for(self, :message1, :message2) # 解包使用信息
    end

    # 初始化 Skill 对象 (RGSS2 版本)
    def initialize(rgss_version = "RGSS2")
      super(rgss_version) # 调用 UsableItem 初始化
      @scope = 1 # 覆盖默认范围为 "敌方单体"
      # 设置 RGSS2 特有属性默认值
      @mp_cost = 0; @hit = 100; @message1 = ""; @message2 = ""
      # 确保移除 RGSS3 可能存在的属性
      RPG.remove_ivar_if_exists(self, :@stype_id)
      RPG.remove_ivar_if_exists(self, :@tp_cost)
      RPG.remove_ivar_if_exists(self, :@required_wtype_id1)
      RPG.remove_ivar_if_exists(self, :@required_wtype_id2)
    end
  end # Skill

  # 职业类 (RGSS2 中是独立类, 不继承 BaseItem)
  class Class
    # RGSS2 职业属性
    attr_accessor :id, :name, :position, :weapon_set, :armor_set # ID, 名称, 位置(0前1中2后), 可装备武器/防具ID列表
    attr_accessor :element_ranks, :state_ranks, :learnings # 元素有效度(Table), 状态有效度(Table), 学习技能列表
    attr_accessor :skill_name_valid, :skill_name # 是否使用特殊技能名称?, 特殊技能名称 (已废弃?)

    # 解包职业名称和特殊技能名称
    def unpack_names(rgss_version = "RGSS2")
      Utils.unpack_names_for(self, :name, :skill_name)
      # learnings 列表由 JsonExporter 递归处理
    end

    # 初始化 Class 对象 (RGSS2 版本)
    def initialize
      @id = 0; @name = ""; @position = 0
      @weapon_set = []; @armor_set = []
      @element_ranks = Table.new([1, 1, 1, 1, 1])
      @state_ranks = Table.new([1, 1, 1, 1, 1])
      @learnings = [] # RPG::Class::Learning 对象数组
      @skill_name_valid = false; @skill_name = ""
    end

    # 嵌套类：职业学习技能
    class Learning
      attr_accessor :level, :skill_id # 学习等级, 技能ID

      # 初始化 Learning 对象
      def initialize
        @level = 1; @skill_id = 1
      end
    end # Learning
  end # Class

  # 敌人种类 (调整自 shared.rb 的 RPG::BaseItem)
  class Enemy < RPG::BaseItem
    # RGSS2 特有属性
    attr_accessor :battler_name, :battler_hue, :maxhp, :maxmp, :atk, :def, :spi, :agi # 战斗图文件名/色相, HP, MP, 攻击, 防御, 精神, 敏捷
    attr_accessor :hit, :eva, :exp, :gold, :drop_item1, :drop_item2, :levitate, :has_critical # 命中率, 回避率, 经验, 金钱, 掉落物品1/2(对象), 浮空?, 允许会心?
    attr_accessor :element_ranks, :state_ranks, :actions # 元素/状态有效度(Table), 行动模式列表

    # 解包敌人名称
    def unpack_names(rgss_version = "RGSS2")
      super(rgss_version) # 调用 BaseItem 处理 name, description, note
      Utils.unpack_names_for(self, :battler_name) # 解包战斗图文件名
      # drop_items 和 actions 由 JsonExporter 递归处理
    end

    # 初始化 Enemy 对象 (RGSS2 版本)
    def initialize(rgss_version = "RGSS2")
      super(rgss_version) # 调用 BaseItem 初始化
      # 设置 RGSS2 特有属性默认值
      @battler_name = ""; @battler_hue = 0
      @maxhp = 10; @maxmp = 10; @atk = 10; @def = 10; @spi = 10; @agi = 10
      @hit = 95; @eva = 5; @exp = 0; @gold = 0
      @drop_item1 = RPG::Enemy::DropItem.new # RGSS2 掉落物是独立对象
      @drop_item2 = RPG::Enemy::DropItem.new
      @levitate = false; @has_critical = false
      @element_ranks = Table.new([1, 1, 1, 1, 1])
      @state_ranks = Table.new([1, 1, 1, 1, 1])
      @actions = [RPG::Enemy::Action.new] # 默认包含一个行动模式
      # 确保移除 RGSS3 可能存在的属性
      RPG.remove_ivar_if_exists(self, :@params)
      RPG.remove_ivar_if_exists(self, :@drop_items)
    end

    # 嵌套类：敌人行动模式
    class Action
      attr_accessor :kind, :basic, :skill_id, :condition_type, :condition_param1, :condition_param2, :rating # 种类(0基本/1技能), 基本行动编号/技能ID, 条件类型, 条件参数1/2, 行动权重

      # 初始化 Action 对象
      def initialize
        @kind = 0; @basic = 0; @skill_id = 1; @condition_type = 0
        @condition_param1 = 0; @condition_param2 = 0; @rating = 5
      end

      # 判断是否为技能行动
      def skill?; @kind == 1; end
    end # Action

    # 嵌套类：敌人掉落物品 (RGSS2 版本)
    class DropItem
      attr_accessor :kind, :item_id, :weapon_id, :armor_id, :denominator # 种类(1物品/2武器/3防具), 对应ID, 掉落率分母 (1/denominator)

      # 初始化 DropItem 对象
      def initialize
        @kind = 0; @item_id = 1; @weapon_id = 1; @armor_id = 1; @denominator = 1
      end
    end # DropItem
  end # Enemy

  # 状态类 (调整自 shared.rb 的 RPG::BaseItem)
  class State < RPG::BaseItem
    # RGSS2 特有属性
    attr_accessor :restriction, :priority, :atk_rate, :def_rate, :spi_rate, :agi_rate # 行动限制, 优先级, 能力值变化率(%)
    attr_accessor :nonresistance, :offset_by_opposite, :slip_damage, :reduce_hit_ratio # 特性: 无视抗性?, 反向状态抵消?, 每回合伤害?, 命中率降低?
    attr_accessor :battle_only, :release_by_damage, :hold_turn, :auto_release_prob # 特性: 仅战斗有效?, 受伤解除?, 持续回合数, 每回合自动解除率(%)
    attr_accessor :message1, :message2, :message3, :message4 # 状态附加/持续/解除时的信息
    attr_accessor :element_set, :state_set # 防御元素/状态集合 (与防具类似)

    # 解包状态相关信息
    def unpack_names(rgss_version = "RGSS2")
      super(rgss_version) # 调用 BaseItem 处理 name, description, note
      Utils.unpack_names_for(self, :message1, :message2, :message3, :message4) # 解包信息字符串
    end

    # 初始化 State 对象 (RGSS2 版本)
    def initialize(rgss_version = "RGSS2")
      super(rgss_version) # 调用 BaseItem 初始化
      # 设置 RGSS2 特有属性默认值
      @restriction = 0; @priority = 5; @atk_rate = 100; @def_rate = 100; @spi_rate = 100; @agi_rate = 100
      @nonresistance = false; @offset_by_opposite = false; @slip_damage = false; @reduce_hit_ratio = false
      @battle_only = true; @release_by_damage = false; @hold_turn = 0; @auto_release_prob = 0
      @message1 = ""; @message2 = ""; @message3 = ""; @message4 = ""
      @element_set = []; @state_set = []
      # 确保移除 RGSS3 可能存在的属性
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
end # RPG 模块 RGSS2 特有补充结束
