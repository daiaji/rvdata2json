# 包含 RGSS3 (RPG Maker VX Ace) 特有的类定义或对共享类的修改

require_relative "shared" # 加载共享定义

# --- RGSS3 特有类定义或覆盖 ---
module RPG

  # --- 重打开共享类以适应 RGSS3 ---

  # 角色类 (调整自 shared.rb 的 RPG::BaseItem)
  class Actor < RPG::BaseItem
    # RGSS3 特有属性
    attr_accessor :nickname, :class_id, :initial_level, :max_level # 昵称, 职业ID, 初始等级, 最高等级
    attr_accessor :character_name, :character_index, :face_name, :face_index, :equips # 行走图/头像文件名/索引, 初始装备ID列表
    # 继承自 BaseItem 的 features 属性

    # 解包角色相关名称
    def unpack_names(rgss_version = "RGSS3")
      super(rgss_version) # 调用 BaseItem 的 unpack_names (处理 name, description, note)
      Utils.unpack_names_for(self, :nickname, :character_name, :face_name) # 解包昵称, 行走图, 头像文件名
    end

    # 初始化 Actor 对象 (RGSS3 版本)
    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # 调用 BaseItem 初始化，确保 features=[]
      # 设置 RGSS3 特有属性默认值
      @nickname = ""; @class_id = 1; @initial_level = 1; @max_level = 99
      @character_name = ""; @character_index = 0; @face_name = ""; @face_index = 0
      @equips = [0, 0, 0, 0, 0] # 初始装备 [武器, 盾, 头, 身, 饰品]
      # 确保移除 RGSS2 可能存在的属性
      RPG.remove_ivar_if_exists(self, :@exp_basis)
      RPG.remove_ivar_if_exists(self, :@exp_inflation)
      RPG.remove_ivar_if_exists(self, :@parameters) # RGSS2 的能力值 Table
      RPG.remove_ivar_if_exists(self, :@weapon_id) # RGSS2 的独立装备 ID
      RPG.remove_ivar_if_exists(self, :@armor1_id)
      RPG.remove_ivar_if_exists(self, :@armor2_id)
      RPG.remove_ivar_if_exists(self, :@armor3_id)
      RPG.remove_ivar_if_exists(self, :@armor4_id)
      RPG.remove_ivar_if_exists(self, :@two_swords_style) # RGSS2 的独立特性
      RPG.remove_ivar_if_exists(self, :@fix_equipment)
      RPG.remove_ivar_if_exists(self, :@auto_battle)
      RPG.remove_ivar_if_exists(self, :@super_guard)
      RPG.remove_ivar_if_exists(self, :@pharmacology)
      RPG.remove_ivar_if_exists(self, :@critical_bonus)
    end
  end # Actor

  # 职业类 (RGSS3 中继承自 BaseItem)
  class Class < RPG::BaseItem
    # RGSS3 特有属性
    attr_accessor :exp_params, :params, :learnings # 经验曲线参数, 能力值曲线(Table), 学习技能列表
    # 继承 features

    # 解包职业相关名称 (只有 BaseItem 的通用名称需要)
    def unpack_names(rgss_version = "RGSS3")
      super(rgss_version) # 调用 BaseItem 处理 name, description, note
      # learnings 列表由 JsonExporter 递归处理
    end

    # 初始化 Class 对象 (RGSS3 版本)
    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # 调用 BaseItem 初始化，确保 features=[]
      # 设置 RGSS3 特有属性默认值
      @exp_params = [30, 20, 30, 30] # 经验曲线参数 [基础值, 补正A, 补正B, 加速度B]
      @params = Table.new([2, 8, 99, 1, 8 * 99]) # 8种能力值(MHP..LUK), 99级
      @learnings = [] # RPG::Class::Learning 对象数组

      # 添加 RGSS3 职业默认特性
      # 注意：这里的特性代码和数据ID可能需要根据VX Ace编辑器默认值精确调整
      @features.push(RPG::BaseItem::Feature.new(23, 0, 1))    # 元素有效度? 特性代码23，数据ID 0 (第一个元素?), 值 1 (100%?) - 需要核实
      @features.push(RPG::BaseItem::Feature.new(22, 0, 0.95)) # 能力值: 命中率(数据ID 0) +95%
      @features.push(RPG::BaseItem::Feature.new(22, 1, 0.05)) # 能力值: 回避率(数据ID 1) +5%
      @features.push(RPG::BaseItem::Feature.new(22, 2, 0.04)) # 能力值: 会心率(数据ID 2) +4% - VX Ace默认是0，这里可能是示例
      @features.push(RPG::BaseItem::Feature.new(41, 1))       # 装备武器类型: 允许装备 ID 为 1 的武器类型
      @features.push(RPG::BaseItem::Feature.new(51, 1))       # 攻击元素: 附加 ID 为 1 的元素
      @features.push(RPG::BaseItem::Feature.new(52, 1))       # 攻击状态: 附加 ID 为 1 的状态? - 需要核实默认值

      # 确保移除 RGSS2 可能存在的属性
      RPG.remove_ivar_if_exists(self, :@position)
      RPG.remove_ivar_if_exists(self, :@weapon_set)
      RPG.remove_ivar_if_exists(self, :@armor_set)
      RPG.remove_ivar_if_exists(self, :@element_ranks)
      RPG.remove_ivar_if_exists(self, :@state_ranks)
      RPG.remove_ivar_if_exists(self, :@skill_name_valid)
      RPG.remove_ivar_if_exists(self, :@skill_name)
    end

    # 嵌套类：职业学习技能 (RGSS3 版本)
    class Learning
      include Jsonable
      attr_accessor :level, :skill_id, :note # 学习等级, 技能ID, 备注

      # 解包备注字符串
      def unpack_names(rgss_version = "RGSS3")
        Utils.unpack_names_for(self, :note) # 解包 @note
      end

      # 初始化 Learning 对象
      def initialize
        @level = 1; @skill_id = 1; @note = ""
      end
    end # Learning
  end # Class

  # 技能类 (调整自 shared.rb 的 RPG::UsableItem)
  class Skill < RPG::UsableItem
    # RGSS3 特有属性
    attr_accessor :stype_id, :mp_cost, :tp_cost, :message1, :message2 # 技能类型ID, MP/TP消耗, 使用信息1/2
    attr_accessor :required_wtype_id1, :required_wtype_id2 # 需要装备的武器类型1/2 ID
    # 继承 RGSS3 UsableItem 的属性 (damage, effects, etc.)

    # 解包技能相关名称
    def unpack_names(rgss_version = "RGSS3")
      super(rgss_version) # 调用 UsableItem 的 unpack_names (处理 name, description, note, damage.formula)
      Utils.unpack_names_for(self, :message1, :message2) # 解包使用信息
      # damage 对象本身由 UsableItem 的 unpack_names 处理
    end

    # 初始化 Skill 对象 (RGSS3 版本)
    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # 调用 UsableItem 初始化 (处理版本相关的 damage/effects 等)
      @scope = 1 # 覆盖默认范围为 "敌方单体"
      # 设置 RGSS3 特有属性默认值
      @stype_id = 1; @mp_cost = 0; @tp_cost = 0
      @message1 = ""; @message2 = ""
      @required_wtype_id1 = 0; @required_wtype_id2 = 0
      # 确保移除 RGSS2 可能存在的属性 (UsableItem 初始化已处理部分)
      RPG.remove_ivar_if_exists(self, :@hit) # RGSS2 的命中率
    end
  end # Skill

  # 物品类 (调整自 shared.rb 的 RPG::UsableItem)
  class Item < RPG::UsableItem
    # RGSS3 特有属性
    attr_accessor :itype_id, :price, :consumable # 物品类型ID(1普通,2关键), 价格, 是否消耗
    # 继承 RGSS3 UsableItem 的属性

    # 初始化 Item 对象 (RGSS3 版本)
    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # 调用 UsableItem 初始化
      @scope = 7 # 覆盖默认范围为 "己方单体"
      # 设置 RGSS3 特有属性默认值
      @itype_id = 1; @price = 0; @consumable = true
      # 确保移除 RGSS2 可能存在的属性 (UsableItem 初始化已处理部分)
      RPG.remove_ivar_if_exists(self, :@hp_recovery_rate)
      RPG.remove_ivar_if_exists(self, :@hp_recovery)
      RPG.remove_ivar_if_exists(self, :@mp_recovery_rate)
      RPG.remove_ivar_if_exists(self, :@mp_recovery)
      RPG.remove_ivar_if_exists(self, :@parameter_type)
      RPG.remove_ivar_if_exists(self, :@parameter_points)
    end
  end # Item

  # 装备物品基类 (RGSS3 特有, 武器和防具的父类, 继承自 BaseItem)
  class EquipItem < RPG::BaseItem
    # RGSS3 装备特有属性
    attr_accessor :price, :etype_id, :params # 价格, 装备类型ID(0武器, 1盾, 2头, 3身, 4饰), 能力值加成列表
    # 继承 features

    # 初始化 EquipItem 对象 (RGSS3 版本)
    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # 调用 BaseItem 初始化，确保 features=[]
      # 设置 EquipItem 属性默认值
      @price = 0
      @etype_id = 0 # 默认为武器类型，子类会覆盖
      @params = [0] * 8 # 8种能力值(MHP..LUK)的加成，默认为0
      # 确保移除 RGSS2 Armor/Weapon 可能存在的属性 (以防万一)
      RPG.remove_ivar_if_exists(self, :@kind) # 来自 RGSS2 Armor
      RPG.remove_ivar_if_exists(self, :@eva)  # 来自 RGSS2 Armor
      RPG.remove_ivar_if_exists(self, :@hit)  # 来自 RGSS2 Weapon/Skill/Enemy
      # RGSS2 的 atk, def, spi, agi 已被 RGSS3 的 params 覆盖
    end
  end # EquipItem

  # 武器类 (RGSS3 版本, 继承自 EquipItem)
  class Weapon < RPG::EquipItem
    # RGSS3 武器特有属性
    attr_accessor :wtype_id, :animation_id # 武器类型ID, 攻击动画ID
    # 继承 price, etype_id, params, features

    # 初始化 Weapon 对象 (RGSS3 版本)
    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # 调用 EquipItem 初始化
      @etype_id = 0 # 武器的装备类型 ID 固定为 0
      # 设置武器特有属性默认值
      @wtype_id = 0; @animation_id = 0
      # 添加 RGSS3 武器默认特性
      @features.push(RPG::BaseItem::Feature.new(31, 1, 0)) # 攻击元素: 物理 (元素 ID 1?) - 需要核实
      @features.push(RPG::BaseItem::Feature.new(22, 0, 0)) # 能力值: 命中率 +0%
      # 确保移除 RGSS2 可能存在的属性 (EquipItem 已处理部分)
      RPG.remove_ivar_if_exists(self, :@hit) # 再次确认移除 RGSS2 hit
      # @atk 等已被 params 覆盖
    end
  end # Weapon

  # 防具类 (RGSS3 版本, 继承自 EquipItem)
  class Armor < RPG::EquipItem
    # RGSS3 防具特有属性
    attr_accessor :atype_id # 防具类型ID
    # 继承 price, etype_id, params, features

    # 初始化 Armor 对象 (RGSS3 版本)
    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # 调用 EquipItem 初始化
      @etype_id = 1 # 默认装备类型为盾 (ID 1)，编辑器中会根据防具类型自动调整
      # 设置防具特有属性默认值
      @atype_id = 0
      # 添加 RGSS3 防具默认特性
      @features.push(RPG::BaseItem::Feature.new(22, 1, 0)) # 能力值: 回避率 +0%
      # 确保移除 RGSS2 可能存在的属性 (EquipItem 已处理部分)
      RPG.remove_ivar_if_exists(self, :@kind) # 再次确认移除 RGSS2 kind
      RPG.remove_ivar_if_exists(self, :@eva)  # 再次确认移除 RGSS2 eva
      # @def 等已被 params 覆盖
    end
  end # Armor

  # 敌人种类 (RGSS3 版本, 继承自 BaseItem)
  class Enemy < RPG::BaseItem
    # RGSS3 特有属性
    attr_accessor :battler_name, :battler_hue, :params, :exp, :gold, :drop_items, :actions # 战斗图文件名/色相, 能力值列表, 经验, 金钱, 掉落物品列表(对象数组), 行动模式列表(对象数组)
    # 继承 features

    # 解包敌人名称
    def unpack_names(rgss_version = "RGSS3")
      super(rgss_version) # 调用 BaseItem 处理 name, description, note
      Utils.unpack_names_for(self, :battler_name) # 解包战斗图文件名
      # drop_items 和 actions 由 JsonExporter 递归处理
    end

    # 初始化 Enemy 对象 (RGSS3 版本)
    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # 调用 BaseItem 初始化，确保 features=[]
      # 设置 RGSS3 特有属性默认值
      @battler_name = ""; @battler_hue = 0
      @params = [100, 0, 10, 10, 10, 10, 10, 10] # 默认能力值 [MHP,MMP,ATK,DEF,MAT,MDF,AGI,LUK]
      @exp = 0; @gold = 0
      @drop_items = Array.new(3) { RPG::Enemy::DropItem.new } # 3个掉落物品栏位
      @actions = [RPG::Enemy::Action.new] # 默认包含一个行动模式
      # 添加 RGSS3 敌人默认特性
      @features.push(RPG::BaseItem::Feature.new(22, 0, 0.95)) # 能力值: 命中率 +95%
      @features.push(RPG::BaseItem::Feature.new(22, 1, 0.05)) # 能力值: 回避率 +5%
      @features.push(RPG::BaseItem::Feature.new(31, 1, 0))    # 攻击元素: 物理 (ID 1?)
      # 确保移除 RGSS2 可能存在的属性
      RPG.remove_ivar_if_exists(self, :@maxhp) # RGSS2 的独立能力值
      RPG.remove_ivar_if_exists(self, :@maxmp)
      RPG.remove_ivar_if_exists(self, :@atk)
      RPG.remove_ivar_if_exists(self, :@def)
      RPG.remove_ivar_if_exists(self, :@spi)
      RPG.remove_ivar_if_exists(self, :@agi)
      RPG.remove_ivar_if_exists(self, :@hit) # RGSS2 的命中/回避
      RPG.remove_ivar_if_exists(self, :@eva)
      RPG.remove_ivar_if_exists(self, :@drop_item1) # RGSS2 的独立掉落物对象
      RPG.remove_ivar_if_exists(self, :@drop_item2)
      RPG.remove_ivar_if_exists(self, :@levitate) # RGSS2 的独立特性
      RPG.remove_ivar_if_exists(self, :@has_critical)
      RPG.remove_ivar_if_exists(self, :@element_ranks) # RGSS2 的有效度 Table
      RPG.remove_ivar_if_exists(self, :@state_ranks)
    end

    # 嵌套类：敌人行动模式 (RGSS3 版本)
    class Action
      include Jsonable
      attr_accessor :skill_id, :condition_type, :condition_param1, :condition_param2, :rating # 技能ID, 条件类型, 条件参数1/2, 行动权重

      # 初始化 Action 对象
      def initialize
        @skill_id = 1; @condition_type = 0 # 默认使用技能1, 条件为"总是"
        @condition_param1 = 0; @condition_param2 = 0; @rating = 5 # 条件参数, 默认权重5
      end
    end # Action

    # 嵌套类：敌人掉落物品 (RGSS3 版本)
    class DropItem
      include Jsonable
      attr_accessor :kind, :data_id, :denominator # 种类(0无,1物品,2武器,3防具), 数据ID, 掉落率分母 (1/denominator)

      # 初始化 DropItem 对象
      def initialize
        @kind = 0; @data_id = 1; @denominator = 1 # 默认无掉落
      end
    end # DropItem
  end # Enemy

  # 状态类 (RGSS3 版本, 继承自 BaseItem)
  class State < RPG::BaseItem
    # RGSS3 特有属性
    attr_accessor :restriction, :priority, :remove_at_battle_end, :remove_by_restriction # 行动限制, 优先级, 战斗结束时解除?, 被其他状态限制时解除?
    attr_accessor :auto_removal_timing, :min_turns, :max_turns, :remove_by_damage # 自动解除时机, 最少/最多持续回合, 受伤时解除?
    attr_accessor :chance_by_damage, :remove_by_walking, :steps_to_remove # 受伤解除率(%), 行走时解除?, 解除所需步数
    attr_accessor :message1, :message2, :message3, :message4 # 状态附加/持续/解除时的信息
    # 继承 features

    # 解包状态相关信息
    def unpack_names(rgss_version = "RGSS3")
      super(rgss_version) # 调用 BaseItem 处理 name, description, note
      Utils.unpack_names_for(self, :message1, :message2, :message3, :message4) # 解包信息字符串
    end

    # 初始化 State 对象 (RGSS3 版本)
    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # 调用 BaseItem 初始化，确保 features=[]
      # 设置 RGSS3 特有属性默认值
      @restriction = 0; @priority = 50 # 默认无限制, 优先级50
      @remove_at_battle_end = false; @remove_by_restriction = false # 默认不解除
      @auto_removal_timing = 0; @min_turns = 1; @max_turns = 1 # 默认无自动解除, 持续1回合
      @remove_by_damage = false; @chance_by_damage = 100 # 默认不受伤害解除
      @remove_by_walking = false; @steps_to_remove = 100 # 默认不因行走解除
      @message1 = ""; @message2 = ""; @message3 = ""; @message4 = "" # 默认无信息
      # 确保移除 RGSS2 可能存在的属性
      RPG.remove_ivar_if_exists(self, :@atk_rate) # RGSS2 的能力值变化率
      RPG.remove_ivar_if_exists(self, :@def_rate)
      RPG.remove_ivar_if_exists(self, :@spi_rate)
      RPG.remove_ivar_if_exists(self, :@agi_rate)
      RPG.remove_ivar_if_exists(self, :@nonresistance) # RGSS2 的独立特性
      RPG.remove_ivar_if_exists(self, :@offset_by_opposite)
      RPG.remove_ivar_if_exists(self, :@slip_damage)
      RPG.remove_ivar_if_exists(self, :@reduce_hit_ratio)
      RPG.remove_ivar_if_exists(self, :@battle_only)
      RPG.remove_ivar_if_exists(self, :@release_by_damage) # RGSS2 的受伤解除布尔值
      RPG.remove_ivar_if_exists(self, :@hold_turn)
      RPG.remove_ivar_if_exists(self, :@auto_release_prob)
      RPG.remove_ivar_if_exists(self, :@element_set) # RGSS2 的防御集合
      RPG.remove_ivar_if_exists(self, :@state_set)
    end
  end # State

  # 图块集类 (RGSS3 特有, Tilesets.rvdata2)
  class Tileset
    include Jsonable
    attr_accessor :id, :mode, :name, :tileset_names, :flags, :note # ID, 模式(1:VX兼容, 2:XP?), 名称, 图块文件名列表, 标志数据(Table), 备注

    # 解包图块集名称、备注和文件名列表
    def unpack_names(rgss_version = "RGSS3")
      Utils.unpack_names_for(self, :name, :note) # 解包名称和备注
      # 解包图块文件名数组中的每个字符串
      @tileset_names.map! { |name| name.is_a?(String) ? RPG.unpack_str(name) : name }
    end

    # 初始化 Tileset 对象
    def initialize
      @id = 0; @mode = 1; @name = "" # 默认 ID 0, VX 兼容模式, 空名称
      @tileset_names = Array.new(9) { "" } # 9个图块文件槽位 (A1-A5, B, C, D, E)
      @flags = Table.new([1, 8192, 1, 1, 8192]) # 标志数据: 1维, 8192个元素 (对应图块 ID 0-8191)
      # 设置默认标志值 (参考 VX Ace 编辑器行为)
      @flags[0] = 0x0010 # ID 0 (空白格) 默认标记?
      (2048..2815).each { |i| @flags[i] = 0x000F } # 自动图块 A1-A4 范围标记 (通行度等)
      (4352..8191).each { |i| @flags[i] = 0x000F } # 图块 B-E 范围标记
      @note = "" # 默认空备注
    end
  end # Tileset

  # --- RGSS3 特有的嵌套类定义 ---

  # 地图遇敌列表项 (RGSS3 版本)
  class Map::Encounter
    include Jsonable
    attr_accessor :troop_id, :weight, :region_set # 队伍ID, 权重, 有效区域ID列表

    # 初始化 Encounter 对象
    def initialize
      @troop_id = 1; @weight = 10; @region_set = [] # 默认队伍1, 权重10, 无区域限制
    end
  end

  # 特性类 (用于 BaseItem 的 features 数组)
  class BaseItem::Feature
    include Jsonable
    attr_accessor :code, :data_id, :value # 特性代码, 数据ID, 值

    # 初始化 Feature 对象
    # code: 特性代码 (整数, 标识特性类型)
    # data_id: 相关数据ID (如元素ID, 状态ID, 能力值索引等)
    # value: 特性值 (通常是浮点数或整数, 表示倍率、固定值等)
    def initialize(code = 0, data_id = 0, value = 0)
      @code = code; @data_id = data_id; @value = value
    end
  end

  # 效果类 (用于 UsableItem 的 effects 数组)
  class UsableItem::Effect
    include Jsonable
    attr_accessor :code, :data_id, :value1, :value2 # 效果代码, 数据ID, 效果值1, 效果值2

    # 初始化 Effect 对象
    # code: 效果代码 (整数, 标识效果类型)
    # data_id: 相关数据ID (如状态ID, 技能ID, 属性索引等)
    # value1, value2: 效果参数 (根据效果类型含义不同)
    def initialize(code = 0, data_id = 0, value1 = 0, value2 = 0)
      @code = code; @data_id = data_id; @value1 = value1; @value2 = value2
    end
  end

  # 伤害类 (用于 UsableItem 的 damage 属性)
  class UsableItem::Damage
    include Jsonable
    attr_accessor :type, :element_id, :formula, :variance, :critical # 类型, 元素ID, 公式(字符串), 分散度(%), 允许会心?

    # 解包伤害公式字符串
    def unpack_names(rgss_version = "RGSS3")
      Utils.unpack_names_for(self, :formula) # 解包 @formula
    end

    # 初始化 Damage 对象
    def initialize
      @type = 0; @element_id = 0; @formula = "0"; @variance = 20; @critical = false # 默认无伤害
    end
  end
end # RPG 模块 RGSS3 特有补充结束
