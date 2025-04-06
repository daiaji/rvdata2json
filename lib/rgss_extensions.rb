# lib/rgss_extensions.rb
# 包含 RPG Maker 类特定版本的属性和初始化/解包逻辑的 Mixin 模块。
# 这些 Mixin 被包含在 rgss1.rb, rgss2.rb, rgss3.rb 中的相应类定义中。

module RPG

  # ============================================================================
  # --- BaseItem Extensions (物品/技能/武器/护甲等的基类) ---
  # ============================================================================

  # --- RGSS1 的伪 BaseItem Mixin ---
  # RGSS1 没有严格意义上的 BaseItem 基类，但其下的 Item, Skill, Weapon, Armor
  # 有一些共享的概念 (如名称、描述等)，在各自的 Mixin 中处理。
  module BaseItemExtensionsRGSS1
    # RGSS1 中，像 name, icon_name, description 这些属性在各自的类 Mixin 中定义。
    # 这里没有需要共享初始化的数据实例变量。
    def initialize_baseitem_rgss1_specifics
      # RGSS1 伪基类无需初始化共享数据变量
    end

    # 名称解包也在各自的类 Mixin 中处理。
    def unpack_names_baseitem_rgss1
      # 在具体的类 Mixin (如 ItemExtensionsRGSS1) 中处理
    end
  end

  # --- RGSS2 的 BaseItem Mixin ---
  # RGSS2 引入了 BaseItem，但此 Mixin 本身可能为空，
  # 因为共享属性 (@id, @name, @icon_index, @description, @note)
  # 通常直接在 shared.rb 的 BaseItem 中定义。
  module BaseItemExtensionsRGSS2
    # RGSS2 BaseItem 的额外初始化逻辑 (如果需要)
    def initialize_baseitem_rgss2_specifics
      # 通常为空
    end

    # RGSS2 BaseItem 的额外名称解包逻辑 (如果需要)
    def unpack_names_baseitem_rgss2
      # 通常为空，父类 BaseItem 已处理 @name, @description, @note
    end
  end

  # --- RGSS3 的 BaseItem Mixin ---
  # RGSS3 的 BaseItem 增加了 @features 属性。
  module BaseItemExtensionsRGSS3
    # @features: 特性列表 (Array<RPG::BaseItem::Feature>)
    attr_accessor :features

    # 初始化 @features 为空数组
    def initialize_baseitem_rgss3_specifics
      @features = []
    end

    # BaseItem 本身的 @features 不包含需要解包的名称。
    # (注意: Class::Learning 等嵌套类中的 @note 需要单独处理)
    def unpack_names_baseitem_rgss3
      # 通常为空，父类 BaseItem 已处理 @name, @description, @note
      # @features 数组内的 Feature 对象没有需要解包的名称
    end
  end

  # ============================================================================
  # --- UsableItem Extensions (可使用物品/技能的基类) ---
  # ============================================================================

  # --- RGSS1 没有 UsableItem 基类 ---
  # 相关属性直接定义在 SkillExtensionsRGSS1 和 ItemExtensionsRGSS1 中。

  # --- RGSS2 的 UsableItem Mixin ---
  # 定义了 RGSS2 中技能和物品共享的属性。
  module UsableItemExtensionsRGSS2
    # 效果和伤害相关属性
    attr_accessor :common_event_id # 公共事件 ID
    attr_accessor :base_damage     # 基本伤害 (物品特有？VX文档不清晰，但存在)
    attr_accessor :variance        # 分散度 (%)
    attr_accessor :atk_f           # 攻击力 F (影响伤害公式)
    attr_accessor :spi_f           # 精神力 F (影响伤害公式)

    # 效果标志
    attr_accessor :physical_attack # 物理攻击? (是否受防御影响等)
    attr_accessor :damage_to_mp    # 伤害 MP?
    attr_accessor :absorb_damage   # 吸收伤害?
    attr_accessor :ignore_defense  # 无视防御?

    # 元素和状态效果
    attr_accessor :element_set     # 攻击元素 (元素 ID 数组)
    attr_accessor :plus_state_set  # 附加状态 (+) (状态 ID 数组)
    attr_accessor :minus_state_set # 解除状态 (-) (状态 ID 数组)

    # 初始化 RGSS2 UsableItem 特定属性
    def initialize_usableitem_rgss2_specifics
      @common_event_id = 0
      @base_damage = 0; @variance = 20; @atk_f = 0; @spi_f = 0
      @physical_attack = false; @damage_to_mp = false; @absorb_damage = false; @ignore_defense = false
      @element_set = []; @plus_state_set = []; @minus_state_set = []
    end

    # UsableItem 本身没有需要解包的名称属性 (父类 BaseItem 处理)
    def unpack_names_usableitem_rgss2
      # 通常为空
    end

    # --- 范围判断辅助方法 (基于 @scope) ---
    def for_opponent?; [1, 2, 3, 4, 5, 6].include?(@scope); end # 目标是敌人?
    def for_friend?; [7, 8, 9, 10, 11].include?(@scope); end    # 目标是我方?
    def for_friend_hp?; [7, 9, 11].include?(@scope); end       # 目标是我方 (HP 未满)?
    def for_friend_all?; [8, 10].include?(@scope); end          # 目标是我方全体?
    def for_user?; @scope == 12; end                            # 目标是使用者?
    def for_all?; [2, 8, 10].include?(@scope); end             # 目标是全体? (敌方或我方)
    def for_one?; ![2, 8, 10].include?(@scope); end            # 目标是单体?
    def need_selection?; [1, 3, 4, 5, 6, 7, 9].include?(@scope); end # 需要选择目标?
    # --- 范围判断结束 ---
  end

  # --- RGSS3 的 UsableItem Mixin ---
  # 定义了 RGSS3 中技能和物品共享的属性。
  module UsableItemExtensionsRGSS3
    attr_accessor :success_rate # 成功率 (%)
    attr_accessor :repeats      # 连续次数
    attr_accessor :tp_gain      # 得 TP
    attr_accessor :hit_type     # 命中类型 (0:必中, 1:物理攻击, 2:魔法攻击)
    attr_accessor :damage       # 伤害信息 (RPG::UsableItem::Damage 对象)
    attr_accessor :effects      # 效果列表 (Array<RPG::UsableItem::Effect>)

    # 初始化 RGSS3 UsableItem 特定属性
    def initialize_usableitem_rgss3_specifics
      @success_rate = 100; @repeats = 1; @tp_gain = 0; @hit_type = 0
      # 确保 Damage 和 Effect 类已定义 (在 rgss3.rb 中)
      @damage = RPG::UsableItem::Damage.new if defined?(RPG::UsableItem::Damage)
      @effects = []
    end

    # 解包嵌套的 Damage 对象的属性 (如 formula)
    def unpack_names_usableitem_rgss3
      @damage.unpack_names if @damage.respond_to?(:unpack_names)
      # @effects 数组内的 Effect 对象没有需要解包的名称
    end
  end

  # ============================================================================
  # --- Actor Extensions (角色) ---
  # ============================================================================

  # --- RGSS1 Actor Mixin ---
  module ActorExtensionsRGSS1
    # 基本信息
    attr_accessor :id, :name, :class_id, :initial_level, :final_level
    # 经验值曲线参数
    attr_accessor :exp_basis, :exp_inflation
    # 图像文件名和色相
    attr_accessor :character_name, :character_hue, :battler_name, :battler_hue
    # 能力值曲线 (Table 对象, 6 行 [HP,SP,STR,DEX,AGI,INT], 100 列 [等级1-99])
    attr_accessor :parameters
    # 初始装备和固定标志
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id # 盾, 头, 身, 饰
    attr_accessor :weapon_fix, :armor1_fix, :armor2_fix, :armor3_fix, :armor4_fix

    # 初始化 RGSS1 Actor 特定属性
    def initialize_actor_rgss1_specifics
      @id = 0; @name = ""; @class_id = 1; @initial_level = 1; @final_level = 99
      @exp_basis = 30; @exp_inflation = 30
      @character_name = ""; @character_hue = 0; @battler_name = ""; @battler_hue = 0
      # 初始化能力值 Table 为 6x100
      @parameters = Table.new([]); @parameters.resize(6, 100)
      @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
      @weapon_fix = false; @armor1_fix = false; @armor2_fix = false; @armor3_fix = false; @armor4_fix = false
    end

    # 解包名称和文件名
    def unpack_names_actor_rgss1
      Utils.unpack_names_for(self, :name, :character_name, :battler_name)
    end
  end

  # --- RGSS2 Actor Mixin ---
  module ActorExtensionsRGSS2
    # 基本信息
    attr_accessor :id, :name, :class_id, :initial_level
    # 经验值曲线参数
    attr_accessor :exp_basis, :exp_inflation
    # 图像文件名/索引和色相
    attr_accessor :character_name, :character_index, :face_name, :face_index
    # 能力值曲线 (Table 对象, 6 行 [MaxHP,MaxMP,ATK,DEF,SPI,AGI], 99 列 [等级1-99])
    attr_accessor :parameters
    # 初始装备
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id # 盾, 头, 身, 饰
    # 特性标志
    attr_accessor :two_swords_style, :fix_equipment, :auto_battle, :super_guard
    attr_accessor :pharmacology, :critical_bonus # 这两个在 VX 中存在吗？文档不清晰，但数据结构中有

    # 初始化 RGSS2 Actor 特定属性
    def initialize_actor_rgss2_specifics
      @id = 0; @name = ""; @class_id = 1; @initial_level = 1
      @exp_basis = 25; @exp_inflation = 35 # VX 默认值
      @character_name = ""; @character_index = 0; @face_name = ""; @face_index = 0
      # 初始化能力值 Table 为 6x99
      @parameters = Table.new([]); @parameters.resize(6, 99)
      @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
      @two_swords_style = false; @fix_equipment = false; @auto_battle = false; @super_guard = false
      @pharmacology = false; @critical_bonus = false # 假设存在并初始化
    end

    # 解包名称和文件名
    def unpack_names_actor_rgss2
      Utils.unpack_names_for(self, :name, :character_name, :face_name)
    end
  end

  # --- RGSS3 Actor Mixin ---
  module ActorExtensionsRGSS3
    attr_accessor :nickname         # 称号
    attr_accessor :class_id         # 职业 ID
    attr_accessor :initial_level    # 初始等级
    attr_accessor :max_level        # 最高等级
    # 图像文件名/索引
    attr_accessor :character_name, :character_index, :face_name, :face_index
    # 初始装备 (数组, 索引对应装备槽: 0武器, 1盾, 2头, 3身, 4饰品)
    attr_accessor :equips

    # 初始化 RGSS3 Actor 特定属性
    def initialize_actor_rgss3_specifics
      @nickname = ""; @class_id = 1; @initial_level = 1; @max_level = 99
      @character_name = ""; @character_index = 0; @face_name = ""; @face_index = 0
      @equips = [0, 0, 0, 0, 0] # 武器, 盾, 头, 身, 饰品 的 ID
    end

    # 解包称号和文件名 (父类 BaseItem 处理 @name, @description, @note)
    def unpack_names_actor_rgss3
      Utils.unpack_names_for(self, :nickname, :character_name, :face_name)
    end
  end

  # ============================================================================
  # --- Armor Extensions (护甲) ---
  # ============================================================================

  # --- RGSS1 Armor Mixin ---
  module ArmorExtensionsRGSS1
    # 基本信息
    attr_accessor :id, :name, :icon_name, :description
    # 类型和价格
    attr_accessor :kind          # 种类 (0:盾, 1:头, 2:身, 3:饰品)
    attr_accessor :auto_state_id # 自动状态 ID
    attr_accessor :price         # 价格
    # 基本防御/回避
    attr_accessor :pdef, :mdef, :eva # 物理防御, 魔法防御, 回避修正
    # 能力值加成
    attr_accessor :str_plus, :dex_plus, :agi_plus, :int_plus # 力量+, 灵巧+, 速度+, 魔力+
    # 防御属性
    attr_accessor :guard_element_set # 防御元素 (元素 ID 数组)
    attr_accessor :guard_state_set   # 防御状态 (状态 ID 数组)

    # 初始化 RGSS1 Armor 特定属性
    def initialize_armor_rgss1_specifics
      @id = 0; @name = ""; @icon_name = ""; @description = ""
      @kind = 0; @auto_state_id = 0; @price = 0
      @pdef = 0; @mdef = 0; @eva = 0
      @str_plus = 0; @dex_plus = 0; @agi_plus = 0; @int_plus = 0
      @guard_element_set = []; @guard_state_set = []
    end

    # 解包名称、图标、描述
    def unpack_names_armor_rgss1
      Utils.unpack_names_for(self, :name, :icon_name, :description)
    end
  end

  # --- RGSS2 Armor Mixin ---
  module ArmorExtensionsRGSS2
    # 类型和价格
    attr_accessor :kind  # 种类 (0:盾, 1:头, 2:身, 3:饰品)
    attr_accessor :price # 价格
    # 能力值/回避
    attr_accessor :eva, :atk, :def, :spi, :agi # 回避修正, 攻击力+, 防御力+, 精神力+, 敏捷性+
    # 特性标志
    attr_accessor :prevent_critical # 不会受到暴击?
    attr_accessor :half_mp_cost     # MP消耗减半?
    attr_accessor :double_exp_gain  # 获得经验值加倍?
    attr_accessor :auto_hp_recover  # HP自动恢复?
    # 防御属性
    attr_accessor :element_set      # 防御元素 (元素 ID 数组)
    attr_accessor :state_set        # 防御状态 (状态 ID 数组)

    # 初始化 RGSS2 Armor 特定属性
    def initialize_armor_rgss2_specifics
      @kind = 0; @price = 0
      @eva = 0; @atk = 0; @def = 0; @spi = 0; @agi = 0
      @prevent_critical = false; @half_mp_cost = false; @double_exp_gain = false; @auto_hp_recover = false
      @element_set = []; @state_set = []
    end

    # Armor 没有额外的名称需要解包 (父类 BaseItem 处理)
    def unpack_names_armor_rgss2
      # 通常为空
    end
  end

  # --- RGSS3 Armor Mixin ---
  module ArmorExtensionsRGSS3
    # @atype_id: 护甲类型 ID (对应 System 中定义的类型)
    attr_accessor :atype_id

    # 初始化 RGSS3 Armor 特定属性
    def initialize_armor_rgss3_specifics
      @atype_id = 0 # 默认为第一个护甲类型
    end

    # Armor 没有额外的名称需要解包 (父类 EquipItem/BaseItem 处理)
    def unpack_names_armor_rgss3
      # 通常为空
    end
  end

  # ============================================================================
  # --- Weapon Extensions (武器) ---
  # ============================================================================

  # --- RGSS1 Weapon Mixin ---
  module WeaponExtensionsRGSS1
    # 基本信息
    attr_accessor :id, :name, :icon_name, :description
    # 动画和价格
    attr_accessor :animation1_id # 使用者动画 ID
    attr_accessor :animation2_id # 目标动画 ID
    attr_accessor :price         # 价格
    # 基本攻防
    attr_accessor :atk, :pdef, :mdef # 攻击力, 物理防御, 魔法防御
    # 能力值加成
    attr_accessor :str_plus, :dex_plus, :agi_plus, :int_plus # 力量+, 灵巧+, 速度+, 魔力+
    # 攻击属性
    attr_accessor :element_set     # 攻击元素 (元素 ID 数组)
    attr_accessor :plus_state_set  # 附加状态 (+) (状态 ID 数组)
    attr_accessor :minus_state_set # 解除状态 (-) (状态 ID 数组)

    # 初始化 RGSS1 Weapon 特定属性
    def initialize_weapon_rgss1_specifics
      @id = 0; @name = ""; @icon_name = ""; @description = ""
      @animation1_id = 0; @animation2_id = 0; @price = 0
      @atk = 0; @pdef = 0; @mdef = 0
      @str_plus = 0; @dex_plus = 0; @agi_plus = 0; @int_plus = 0
      @element_set = []; @plus_state_set = []; @minus_state_set = []
    end

    # 解包名称、图标、描述
    def unpack_names_weapon_rgss1
      Utils.unpack_names_for(self, :name, :icon_name, :description)
    end
  end

  # --- RGSS2 Weapon Mixin ---
  module WeaponExtensionsRGSS2
    # 动画和价格
    attr_accessor :animation_id # 动画 ID
    attr_accessor :price        # 价格
    # 能力值/命中
    attr_accessor :hit, :atk, :def, :spi, :agi # 命中率+, 攻击力+, 防御力+, 精神力+, 敏捷性+
    # 特性标志
    attr_accessor :two_handed     # 双手武器?
    attr_accessor :fast_attack    # 攻击速度快?
    attr_accessor :dual_attack    # 连续攻击?
    attr_accessor :critical_bonus # 增加会心一击率?
    # 攻击属性
    attr_accessor :element_set    # 攻击元素 (元素 ID 数组)
    attr_accessor :state_set      # 攻击状态 (状态 ID 数组)

    # 初始化 RGSS2 Weapon 特定属性
    def initialize_weapon_rgss2_specifics
      @animation_id = 0; @price = 0; @hit = 95 # VX 默认命中率?
      @atk = 0; @def = 0; @spi = 0; @agi = 0
      @two_handed = false; @fast_attack = false; @dual_attack = false; @critical_bonus = false
      @element_set = []; @state_set = []
    end

    # Weapon 没有额外的名称需要解包 (父类 BaseItem 处理)
    def unpack_names_weapon_rgss2
      # 通常为空
    end
  end

  # --- RGSS3 Weapon Mixin ---
  module WeaponExtensionsRGSS3
    attr_accessor :wtype_id     # 武器类型 ID (对应 System 中定义的类型)
    attr_accessor :animation_id # 动画 ID

    # 初始化 RGSS3 Weapon 特定属性
    def initialize_weapon_rgss3_specifics
      @wtype_id = 0 # 默认为第一个武器类型
      @animation_id = 0
    end

    # Weapon 没有额外的名称需要解包 (父类 EquipItem/BaseItem 处理)
    def unpack_names_weapon_rgss3
      # 通常为空
    end
  end

  # ============================================================================
  # --- Item Extensions (物品) ---
  # ============================================================================

  # --- RGSS1 Item Mixin ---
  module ItemExtensionsRGSS1
    # 基本信息
    attr_accessor :id, :name, :icon_name, :description
    # 使用范围和时机
    attr_accessor :scope        # 范围 (0:无, 1:敌单体, 2:敌全体, ..., 7:我方单体, ...)
    attr_accessor :occasion     # 可用时机 (0:平时, 1:战斗中, 2:菜单, 3:从不)
    # 动画和音效
    attr_accessor :animation1_id, :animation2_id # 使用者动画, 目标动画
    attr_accessor :menu_se       # 菜单中使用时的音效 (RPG::AudioFile 对象)
    # 效果和消耗
    attr_accessor :common_event_id # 调用的公共事件 ID
    attr_accessor :price           # 价格
    attr_accessor :consumable      # 是否消耗品
    # 参数变化
    attr_accessor :parameter_type   # 影响的能力值类型 (0:无, 1:MaxHP, ..., 6:MaxSP)
    attr_accessor :parameter_points # 影响的点数
    # HP/SP 恢复
    attr_accessor :recover_hp_rate, :recover_hp # HP 恢复率(%), HP 恢复量
    attr_accessor :recover_sp_rate, :recover_sp # SP 恢复率(%), SP 恢复量
    # 命中和效果修正
    attr_accessor :hit            # 命中率
    attr_accessor :pdef_f         # 物理防御 F (效果修正)
    attr_accessor :mdef_f         # 魔法防御 F (效果修正)
    attr_accessor :variance       # 分散度 (%)
    # 元素和状态效果
    attr_accessor :element_set     # 攻击元素 (元素 ID 数组)
    attr_accessor :plus_state_set  # 附加状态 (+) (状态 ID 数组)
    attr_accessor :minus_state_set # 解除状态 (-) (状态 ID 数组)

    # 初始化 RGSS1 Item 特定属性
    def initialize_item_rgss1_specifics
      @id = 0; @name = ""; @icon_name = ""; @description = ""
      @scope = 0; @occasion = 0; @animation1_id = 0; @animation2_id = 0
      @menu_se = RPG::AudioFile.new("", 80) # 默认音效
      @common_event_id = 0; @price = 0; @consumable = true
      @parameter_type = 0; @parameter_points = 0
      @recover_hp_rate = 0; @recover_hp = 0; @recover_sp_rate = 0; @recover_sp = 0
      @hit = 100; @pdef_f = 0; @mdef_f = 0; @variance = 0
      @element_set = []; @plus_state_set = []; @minus_state_set = []
    end

    # 解包名称、图标、描述以及菜单音效
    def unpack_names_item_rgss1
      Utils.unpack_names_for(self, :name, :icon_name, :description)
      @menu_se&.unpack_names # 解包 AudioFile
    end
  end

  # --- RGSS2 Item Mixin ---
  module ItemExtensionsRGSS2
    attr_accessor :price          # 价格
    attr_accessor :consumable     # 是否消耗品
    # HP/MP 恢复
    attr_accessor :hp_recovery_rate, :hp_recovery # HP 恢复率(%), HP 恢复量
    attr_accessor :mp_recovery_rate, :mp_recovery # MP 恢复率(%), MP 恢复量
    # 参数变化
    attr_accessor :parameter_type   # 影响的能力值类型 (0:无, 1:MaxHP, ..., 6:AGI)
    attr_accessor :parameter_points # 影响的点数

    # 初始化 RGSS2 Item 特定属性 (依赖 UsableItem Mixin)
    def initialize_item_rgss2_specifics
      @price = 0; @consumable = true
      @hp_recovery_rate = 0; @hp_recovery = 0
      @mp_recovery_rate = 0; @mp_recovery = 0
      @parameter_type = 0; @parameter_points = 0
      # 确保调用 RGSS2 UsableItem 的初始化
      initialize_usableitem_rgss2_specifics
    end

    # Item 没有额外的名称需要解包 (父类 UsableItem/BaseItem 处理)
    def unpack_names_item_rgss2
      # 通常为空
    end
  end

  # --- RGSS3 Item Mixin ---
  module ItemExtensionsRGSS3
    attr_accessor :itype_id   # 物品类型 (1:通常物品, 2:关键物品)
    attr_accessor :price      # 价格
    attr_accessor :consumable # 是否消耗品

    # 初始化 RGSS3 Item 特定属性
    def initialize_item_rgss3_specifics
      @itype_id = 1 # 默认为通常物品
      @price = 0; @consumable = true
    end

    # Item 没有额外的名称需要解包 (父类 UsableItem/BaseItem 处理)
    def unpack_names_item_rgss3
      # 通常为空
    end
  end

  # ============================================================================
  # --- Skill Extensions (技能) ---
  # ============================================================================

  # --- RGSS1 Skill Mixin ---
  module SkillExtensionsRGSS1
    # 基本信息
    attr_accessor :id, :name, :icon_name, :description
    # 使用范围和时机
    attr_accessor :scope, :occasion
    # 动画和音效
    attr_accessor :animation1_id, :animation2_id
    attr_accessor :menu_se       # 菜单中使用时的音效 (RPG::AudioFile 对象)
    # 效果和消耗
    attr_accessor :common_event_id # 调用的公共事件 ID
    attr_accessor :sp_cost         # SP 消耗
    attr_accessor :power           # 威力
    # 效果修正 (基于使用者属性)
    attr_accessor :atk_f, :eva_f, :str_f, :dex_f, :agi_f, :int_f
    # 命中和效果修正 (基于目标)
    attr_accessor :hit, :pdef_f, :mdef_f, :variance
    # 元素和状态效果
    attr_accessor :element_set, :plus_state_set, :minus_state_set

    # 初始化 RGSS1 Skill 特定属性
    def initialize_skill_rgss1_specifics
      @id = 0; @name = ""; @icon_name = ""; @description = ""
      @scope = 0; @occasion = 1 # 默认仅战斗中可用
      @animation1_id = 0; @animation2_id = 0
      @menu_se = RPG::AudioFile.new("", 80)
      @common_event_id = 0; @sp_cost = 0; @power = 0
      @atk_f = 0; @eva_f = 0; @str_f = 0; @dex_f = 0; @agi_f = 0; @int_f = 100 # 默认受魔力影响
      @hit = 100; @pdef_f = 0; @mdef_f = 100; @variance = 15
      @element_set = []; @plus_state_set = []; @minus_state_set = []
    end

    # 解包名称、图标、描述以及菜单音效
    def unpack_names_skill_rgss1
      Utils.unpack_names_for(self, :name, :icon_name, :description)
      @menu_se&.unpack_names
    end
  end

  # --- RGSS2 Skill Mixin ---
  module SkillExtensionsRGSS2
    attr_accessor :mp_cost  # MP 消耗
    attr_accessor :hit      # 命中率
    # 使用时的消息
    attr_accessor :message1 # 第一行消息 ("<使用者>使用了<技能>!")
    attr_accessor :message2 # 第二行消息 (通常为空)

    # 初始化 RGSS2 Skill 特定属性 (依赖 UsableItem Mixin)
    def initialize_skill_rgss2_specifics
      @mp_cost = 0; @hit = 100
      @message1 = ""; @message2 = ""
      # 确保调用 RGSS2 UsableItem 的初始化
      initialize_usableitem_rgss2_specifics
    end

    # 解包技能消息
    def unpack_names_skill_rgss2
      Utils.unpack_names_for(self, :message1, :message2)
    end
  end

  # --- RGSS3 Skill Mixin ---
  module SkillExtensionsRGSS3
    attr_accessor :stype_id     # 技能类型 ID (对应 System 中定义的类型)
    attr_accessor :mp_cost      # MP 消耗
    attr_accessor :tp_cost      # TP 消耗
    # 使用时的消息
    attr_accessor :message1     # 第一行消息
    attr_accessor :message2     # 第二行消息
    # 武器类型限制
    attr_accessor :required_wtype_id1 # 需要武器类型1 ID
    attr_accessor :required_wtype_id2 # 需要武器类型2 ID

    # 初始化 RGSS3 Skill 特定属性
    def initialize_skill_rgss3_specifics
      @stype_id = 1 # 默认为第一个技能类型
      @mp_cost = 0; @tp_cost = 0
      @message1 = ""; @message2 = ""
      @required_wtype_id1 = 0; @required_wtype_id2 = 0
    end

    # 解包技能消息 (父类 UsableItem/BaseItem 处理其他名称)
    def unpack_names_skill_rgss3
      Utils.unpack_names_for(self, :message1, :message2)
    end
  end

  # ============================================================================
  # --- Enemy Extensions (敌人) ---
  # ============================================================================

  # --- RGSS1 Enemy Mixin ---
  module EnemyExtensionsRGSS1
    # 基本信息和图像
    attr_accessor :id, :name, :battler_name, :battler_hue
    # 基本能力值
    attr_accessor :maxhp, :maxsp, :str, :dex, :agi, :int
    # 战斗相关能力值
    attr_accessor :atk, :pdef, :mdef, :eva
    # 动画
    attr_accessor :animation1_id # 受击动画 ID
    attr_accessor :animation2_id # 攻击动画 ID (如果使用普通攻击)
    # 属性和状态有效度 (Table 对象)
    attr_accessor :element_ranks, :state_ranks
    # 行动模式
    attr_accessor :actions # (Array<RPG::Enemy::Action>)
    # 战利品
    attr_accessor :exp, :gold, :item_id, :weapon_id, :armor_id, :treasure_prob # 经验, 金钱, 掉落物品/武器/护甲 ID, 掉宝率(%)

    # 初始化 RGSS1 Enemy 特定属性
    def initialize_enemy_rgss1_specifics
      @id = 0; @name = ""; @battler_name = ""; @battler_hue = 0
      @maxhp = 500; @maxsp = 500; @str = 50; @dex = 50; @agi = 50; @int = 50
      @atk = 100; @pdef = 100; @mdef = 100; @eva = 0
      @animation1_id = 0; @animation2_id = 0
      # 初始化有效度 Table (1行, 之后由数据加载调整)
      @element_ranks = Table.new([]); @element_ranks.resize(1)
      @state_ranks = Table.new([]); @state_ranks.resize(1)
      @actions = [RPG::Enemy::Action.new] # 默认包含一个行动
      @exp = 0; @gold = 0; @item_id = 0; @weapon_id = 0; @armor_id = 0; @treasure_prob = 100
    end

    # 解包名称和战斗图文件名
    def unpack_names_enemy_rgss1
      Utils.unpack_names_for(self, :name, :battler_name)
      # Action 和 Ranks 内部没有名称
    end
  end

  # --- RGSS2 Enemy Mixin ---
  module EnemyExtensionsRGSS2
    # 基本信息和图像
    attr_accessor :id, :name, :note # RGSS2 Enemy 有 @note
    attr_accessor :battler_name, :battler_hue
    # 基本能力值
    attr_accessor :maxhp, :maxmp, :atk, :def, :spi, :agi # 注意: MaxMP 和 SPI
    # 战斗相关能力值
    attr_accessor :hit, :eva # 命中率, 回避率
    # 战利品
    attr_accessor :exp, :gold
    attr_accessor :drop_item1, :drop_item2 # 掉落物品1/2 (RPG::Enemy::DropItem 对象)
    # 特性标志
    attr_accessor :levitate       # 浮空?
    attr_accessor :has_critical   # 允许暴击?
    # 属性和状态有效度 (Table 对象)
    attr_accessor :element_ranks, :state_ranks
    # 行动模式
    attr_accessor :actions # (Array<RPG::Enemy::Action>)

    # 初始化 RGSS2 Enemy 特定属性
    def initialize_enemy_rgss2_specifics
      @id = 0; @name = ""; @note = ""; @battler_name = ""; @battler_hue = 0
      @maxhp = 10; @maxmp = 10; @atk = 10; @def = 10; @spi = 10; @agi = 10
      @hit = 95; @eva = 5; @exp = 0; @gold = 0
      # 确保 DropItem 和 Action 类已定义
      @drop_item1 = RPG::Enemy::DropItem.new if defined?(RPG::Enemy::DropItem)
      @drop_item2 = RPG::Enemy::DropItem.new if defined?(RPG::Enemy::DropItem)
      @levitate = false; @has_critical = false
      @element_ranks = Table.new([]); @element_ranks.resize(1)
      @state_ranks = Table.new([]); @state_ranks.resize(1)
      @actions = [RPG::Enemy::Action.new] if defined?(RPG::Enemy::Action)
    end

    # 解包名称、备注、战斗图文件名
    def unpack_names_enemy_rgss2
      Utils.unpack_names_for(self, :name, :note, :battler_name)
      # Action, DropItem, Ranks 内部没有名称
    end
  end

  # --- RGSS3 Enemy Mixin ---
  module EnemyExtensionsRGSS3
    # 图像
    attr_accessor :battler_name, :battler_hue
    # 能力值 (数组, [MaxHP, MaxMP, ATK, DEF, MAT, MDF, AGI, LUK])
    attr_accessor :params
    # 战利品
    attr_accessor :exp, :gold
    attr_accessor :drop_items # 掉落物品列表 (Array<RPG::Enemy::DropItem>)
    # 行动模式
    attr_accessor :actions    # (Array<RPG::Enemy::Action>)

    # 初始化 RGSS3 Enemy 特定属性
    def initialize_enemy_rgss3_specifics
      @battler_name = ""; @battler_hue = 0
      # 默认能力值数组
      @params = [100, 0, 10, 10, 10, 10, 10, 10] # MHP, MMP, ATK, DEF, MAT, MDF, AGI, LUK
      @exp = 0; @gold = 0
      # 初始化掉落物品和行动列表
      @drop_items = Array.new(3) { RPG::Enemy::DropItem.new } if defined?(RPG::Enemy::DropItem)
      @actions = [RPG::Enemy::Action.new] if defined?(RPG::Enemy::Action)
    end

    # 解包战斗图文件名 (父类 BaseItem 处理 @name, @note)
    def unpack_names_enemy_rgss3
      Utils.unpack_names_for(self, :battler_name)
      # Action, DropItem 内部没有名称
    end
  end

  # ============================================================================
  # --- State Extensions (状态) ---
  # ============================================================================

  # --- RGSS1 State Mixin ---
  module StateExtensionsRGSS1
    # 基本信息和动画
    attr_accessor :id, :name, :animation_id # 状态 ID, 名称, 动画 ID
    # 限制
    attr_accessor :restriction # 行动限制 (0:无, 1:不能攻击, 2:不能用技能, 3:不能移动, 4:无法行动)
    # 特性标志
    attr_accessor :nonresistance # 无视抗性?
    attr_accessor :zero_hp       # HP为0时解除?
    attr_accessor :cant_get_exp  # 无法获得经验?
    attr_accessor :cant_evade    # 无法回避?
    attr_accessor :slip_damage   # 持续伤害? (毒)
    # 优先级和效果率
    attr_accessor :rating     # 优先级 (0-10)
    attr_accessor :hit_rate   # 命中率修正 (%)
    attr_accessor :maxhp_rate # MaxHP 修正 (%)
    attr_accessor :maxsp_rate # MaxSP 修正 (%)
    # 能力值修正率 (%)
    attr_accessor :str_rate, :dex_rate, :agi_rate, :int_rate
    attr_accessor :atk_rate, :pdef_rate, :mdef_rate
    attr_accessor :eva        # 回避修正 (固定值)
    # 持续时间和解除条件
    attr_accessor :battle_only       # 仅战斗中?
    attr_accessor :hold_turn         # 持续回合数
    attr_accessor :auto_release_prob # 每回合自动解除率 (%)
    attr_accessor :shock_release_prob # 受击解除率 (%)
    # 防御和状态变化
    attr_accessor :guard_element_set # 防御元素 (元素 ID 数组)
    attr_accessor :plus_state_set    # 附加状态 (+) (状态 ID 数组)
    attr_accessor :minus_state_set   # 解除状态 (-) (状态 ID 数组)

    # 初始化 RGSS1 State 特定属性
    def initialize_state_rgss1_specifics
      @id = 0; @name = ""; @animation_id = 0; @restriction = 0
      @nonresistance = false; @zero_hp = false; @cant_get_exp = false; @cant_evade = false; @slip_damage = false
      @rating = 5; @hit_rate = 100; @maxhp_rate = 100; @maxsp_rate = 100
      @str_rate = 100; @dex_rate = 100; @agi_rate = 100; @int_rate = 100
      @atk_rate = 100; @pdef_rate = 100; @mdef_rate = 100; @eva = 0
      @battle_only = true; @hold_turn = 0; @auto_release_prob = 0; @shock_release_prob = 0
      @guard_element_set = []; @plus_state_set = []; @minus_state_set = []
    end

    # 解包状态名称
    def unpack_names_state_rgss1
      Utils.unpack_names_for(self, :name)
    end
  end

  # --- RGSS2 State Mixin ---
  module StateExtensionsRGSS2
    # 基本信息和图标
    attr_accessor :id, :name, :note, :icon_index # RGSS2 State 有 @note 和 @icon_index
    # 限制和优先级
    attr_accessor :restriction # 行动限制 (同 RGSS1，但值可能扩展)
    attr_accessor :priority    # 优先级 (0-100)
    # 能力值修正率 (%)
    attr_accessor :atk_rate, :def_rate, :spi_rate, :agi_rate
    # 特性标志
    attr_accessor :nonresistance      # 无视抗性?
    attr_accessor :offset_by_opposite # 被相反状态抵消? (如中毒和解毒)
    attr_accessor :slip_damage        # 持续伤害?
    # RGSS2 中似乎没有 reduce_hit_ratio
    # 持续时间和解除条件
    attr_accessor :battle_only        # 仅战斗中?
    attr_accessor :release_by_damage  # 受击解除?
    attr_accessor :hold_turn          # 持续回合数
    attr_accessor :auto_release_prob  # 每回合自动解除率 (%)
    # 状态消息
    attr_accessor :message1 # 附加状态时的消息 ("<角色>中了<状态>!")
    attr_accessor :message2 # 状态持续时的消息 ("<角色>正处于<状态>状态。")
    attr_accessor :message3 # 状态解除时的消息 ("<角色>的<状态>解除了。")
    attr_accessor :message4 # 状态效果发动时的消息 (如毒伤害)
    # 防御属性
    attr_accessor :element_set # 防御元素 (元素 ID 数组)
    attr_accessor :state_set   # 防御状态 (状态 ID 数组)

    # 初始化 RGSS2 State 特定属性
    def initialize_state_rgss2_specifics
      @id = 0; @name = ""; @note = ""; @icon_index = 0
      @restriction = 0; @priority = 5 # VX 默认优先级
      @atk_rate = 100; @def_rate = 100; @spi_rate = 100; @agi_rate = 100
      @nonresistance = false; @offset_by_opposite = false; @slip_damage = false
      @battle_only = true; @release_by_damage = false
      @hold_turn = 0; @auto_release_prob = 0
      @message1 = ""; @message2 = ""; @message3 = ""; @message4 = ""
      @element_set = []; @state_set = []
    end

    # 解包名称、备注和消息
    def unpack_names_state_rgss2
      Utils.unpack_names_for(self, :name, :note, :message1, :message2, :message3, :message4)
    end
  end

  # --- RGSS3 State Mixin ---
  module StateExtensionsRGSS3
    # 限制和优先级
    attr_accessor :restriction # 行动限制 (0:无, 1:攻击敌人, 2:攻击任何人, 3:攻击同伴, 4:无法行动)
    attr_accessor :priority    # 优先级 (0-100)
    # 自动解除时机
    attr_accessor :remove_at_battle_end # 战斗结束时解除?
    attr_accessor :remove_by_restriction # 行动限制解除时解除?
    attr_accessor :auto_removal_timing  # 自动解除时机 (0:无, 1:行动结束时, 2:回合结束时)
    # 持续回合数
    attr_accessor :min_turns, :max_turns # 最短持续回合, 最长持续回合
    # 受击解除
    attr_accessor :remove_by_damage     # 受击时解除?
    attr_accessor :chance_by_damage     # 受击解除率 (%)
    # 步数解除
    attr_accessor :remove_by_walking    # 行走时解除?
    attr_accessor :steps_to_remove      # 解除所需步数
    # 状态消息
    attr_accessor :message1, :message2, :message3, :message4 # 同 RGSS2

    # 初始化 RGSS3 State 特定属性
    def initialize_state_rgss3_specifics
      @restriction = 0; @priority = 50 # Ace 默认优先级
      @remove_at_battle_end = false; @remove_by_restriction = false
      @auto_removal_timing = 0; @min_turns = 1; @max_turns = 1
      @remove_by_damage = false; @chance_by_damage = 100
      @remove_by_walking = false; @steps_to_remove = 100
      @message1 = ""; @message2 = ""; @message3 = ""; @message4 = ""
    end

    # 解包状态消息 (父类 BaseItem 处理 @name, @note)
    def unpack_names_state_rgss3
      Utils.unpack_names_for(self, :message1, :message2, :message3, :message4)
    end
  end

  # ============================================================================
  # --- Map Extensions (地图) ---
  # ============================================================================

  # --- RGSS1 Map Mixin ---
  module MapExtensionsRGSS1
    # 基本属性
    attr_accessor :tileset_id # 使用的图块组 ID
    attr_accessor :width, :height # 地图宽度, 高度 (格子数)
    # 背景音乐/音效
    attr_accessor :autoplay_bgm, :bgm # 自动播放 BGM?, BGM (RPG::AudioFile)
    attr_accessor :autoplay_bgs, :bgs # 自动播放 BGS?, BGS (RPG::AudioFile)
    # 遇敌设置
    attr_accessor :encounter_list # 敌人队伍 ID 列表
    attr_accessor :encounter_step # 平均遇敌步数
    # 地图数据 (Table 对象, width x height x 3 层)
    attr_accessor :data
    # 地图事件 (Hash, key=事件ID, value=RPG::Event)
    attr_accessor :events

    # 初始化 RGSS1 Map 特定属性
    def initialize_map_rgss1_specifics(width, height)
      @tileset_id = 1
      @width = width; @height = height
      @autoplay_bgm = false; @bgm = RPG::AudioFile.new
      @autoplay_bgs = false; @bgs = RPG::AudioFile.new("", 80)
      @encounter_list = []; @encounter_step = 30
      # 初始化地图数据 Table
      @data = Table.new([]); @data.resize(width, height, 3)
      @events = {}
    end

    # 解包 BGM 和 BGS 的文件名
    def unpack_names_map_rgss1
      @bgm&.unpack_names
      @bgs&.unpack_names
      # @events 的解包在 Map 类自身的 unpack_names 方法中递归处理
    end
  end

  # --- RGSS2 Map Mixin ---
  module MapExtensionsRGSS2
    # RGSS2 地图特有的属性 (除了在 initialize 中定义的共享属性外)
    # 地图数据 (Table 对象, width x height x 3 层)
    attr_accessor :data
    # 遇敌列表 (Array<RPG::Map::Encounter>) - 注意: RGSS2 Map 没有嵌套 Encounter 类，是直接存 Troop ID
    attr_accessor :encounter_list # (Array<Integer> - 队伍 ID 列表)

    # 初始化 RGSS2 Map 特定属性
    def initialize_map_rgss2_specifics(width, height)
      # 初始化地图数据 Table
      @data = Table.new([]); @data.resize(width, height, 3)
      @encounter_list = [] # 存 Troop ID
    end

    # RGSS2 Map Mixin 没有需要解包的名称
    def unpack_names_map_rgss2
      # @events 的解包在 Map 类自身的 unpack_names 方法中递归处理
    end
  end

  # --- RGSS3 Map Mixin ---
  module MapExtensionsRGSS3
    # 显示名称和图块组
    attr_accessor :display_name # 在游戏中显示的名称 (如果为空则使用 MapInfo 名称)
    attr_accessor :tileset_id   # 使用的图块组 ID
    # 战斗背景设置
    attr_accessor :specify_battleback # 指定战斗背景?
    attr_accessor :battleback1_name   # 战斗背景1 (地面) 文件名
    attr_accessor :battleback2_name   # 战斗背景2 (远景) 文件名
    # 备注
    attr_accessor :note
    # 地图数据 (Table 对象, width x height x 4 层)
    attr_accessor :data
    # 遇敌列表 (Array<RPG::Map::Encounter>)
    attr_accessor :encounter_list

    # 初始化 RGSS3 Map 特定属性
    def initialize_map_rgss3_specifics(width, height)
      @display_name = ""; @tileset_id = 1
      @specify_battleback = false
      @battleback1_name = ""; @battleback2_name = ""
      @note = ""
      # 初始化地图数据 Table (4层)
      @data = Table.new([]); @data.resize(width, height, 4)
      @encounter_list = [] # 包含 RPG::Map::Encounter 对象
    end

    # 解包显示名称、战斗背景文件名和备注
    def unpack_names_map_rgss3
      Utils.unpack_names_for(self, :display_name, :battleback1_name, :battleback2_name, :note)
      # @events 的解包在 Map 类自身的 unpack_names 方法中递归处理
    end
  end

  # ============================================================================
  # --- System Extensions (系统设置) ---
  # ============================================================================

  # --- RGSS1 System Mixin ---
  module SystemExtensionsRGSS1
    # 基本信息
    attr_accessor :magic_number # 用于版本检查的魔数 (通常为 0)
    attr_accessor :party_members # 初始队伍成员 (角色 ID 数组)
    # 数据库名称
    attr_accessor :elements, :switches, :variables # 元素/开关/变量 名称数组 (索引0为nil)
    # 文件名
    attr_accessor :windowskin_name, :title_name, :gameover_name, :battle_transition
    # BGM/ME 文件 (RPG::AudioFile 对象)
    attr_accessor :title_bgm, :battle_bgm, :battle_end_me, :gameover_me
    # SE 文件 (RPG::AudioFile 对象)
    attr_accessor :cursor_se, :decision_se, :cancel_se, :buzzer_se
    attr_accessor :equip_se, :shop_se, :save_se, :load_se
    attr_accessor :battle_start_se, :escape_se, :actor_collapse_se, :enemy_collapse_se
    # 术语
    attr_accessor :words # (RPG::System::Words 对象)
    # 测试战斗
    attr_accessor :test_battlers # (Array<RPG::System::TestBattler>)
    attr_accessor :test_troop_id # 测试队伍 ID
    # 初始位置
    attr_accessor :start_map_id, :start_x, :start_y
    # 编辑器相关
    attr_accessor :battleback_name # 默认战斗背景
    attr_accessor :battler_name, :battler_hue # 默认敌人图像 (似乎未使用?)
    attr_accessor :edit_map_id # 编辑器上次打开的地图 ID

    # 初始化 RGSS1 System 特定属性
    def initialize_system_rgss1_specifics
      @magic_number = 0; @party_members = [1]
      @elements = [nil, ""]; @switches = [nil, ""]; @variables = [nil, ""]
      @windowskin_name = ""; @title_name = ""; @gameover_name = ""; @battle_transition = ""
      @title_bgm = RPG::AudioFile.new; @battle_bgm = RPG::AudioFile.new
      @battle_end_me = RPG::AudioFile.new; @gameover_me = RPG::AudioFile.new
      # 初始化 SE，默认音量 80
      @cursor_se = RPG::AudioFile.new("", 80); @decision_se = RPG::AudioFile.new("", 80)
      @cancel_se = RPG::AudioFile.new("", 80); @buzzer_se = RPG::AudioFile.new("", 80)
      @equip_se = RPG::AudioFile.new("", 80); @shop_se = RPG::AudioFile.new("", 80)
      @save_se = RPG::AudioFile.new("", 80); @load_se = RPG::AudioFile.new("", 80)
      @battle_start_se = RPG::AudioFile.new("", 80); @escape_se = RPG::AudioFile.new("", 80)
      @actor_collapse_se = RPG::AudioFile.new("", 80); @enemy_collapse_se = RPG::AudioFile.new("", 80)
      @words = RPG::System::Words.new # 实例化术语对象
      @test_battlers = []; @test_troop_id = 1
      @start_map_id = 1; @start_x = 0; @start_y = 0
      @battleback_name = ""; @battler_name = ""; @battler_hue = 0; @edit_map_id = 1
    end

    # 解包系统设置中的各种文件名和名称数组
    def unpack_names_system_rgss1
      # 解包普通文件名
      Utils.unpack_names_for(self, :windowskin_name, :title_name, :gameover_name, :battle_transition, :battleback_name, :battler_name)
      # 解包名称数组
      [:@elements, :@switches, :@variables].each do |ivar|
        array = instance_variable_get(ivar)
        array&.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item }
      end
      # 解包所有 SE 文件
      se_vars = [:@cursor_se, :@decision_se, :@cancel_se, :@buzzer_se, :@equip_se, :@shop_se, :@save_se, :@load_se, :@battle_start_se, :@escape_se, :@actor_collapse_se, :@enemy_collapse_se]
      se_vars.each { |ivar| instance_variable_get(ivar)&.unpack_names }
      # 解包 BGM/ME 文件
      [:@title_bgm, :@battle_bgm, :@battle_end_me, :@gameover_me].each { |ivar| instance_variable_get(ivar)&.unpack_names }
      # 解包术语
      @words&.unpack_names if @words.respond_to?(:unpack_names)
      # @test_battlers 由 System 类递归处理
    end
  end

  # --- RGSS2 System Mixin ---
  module SystemExtensionsRGSS2
    # @passages: 图块通行度设置 (Table 对象, 8192 个元素)
    # @sounds:   音效列表 (Array<RPG::SE>)，覆盖 shared 中的定义
    attr_accessor :passages, :sounds

    # 初始化 RGSS2 System 特定属性
    def initialize_system_rgss2_specifics
      # 初始化通行度 Table
      @passages = Table.new([]); @passages.resize(8192)
      # 初始化音效数组 (20 个 SE 对象)
      @sounds = Array.new(20) { RPG::SE.new }
    end

    # 解包音效数组中的 SE 文件名
    def unpack_names_system_rgss2
      @sounds&.each { |s| s&.unpack_names }
    end
  end

  # --- RGSS3 System Mixin ---
  module SystemExtensionsRGSS3
    # 语言和货币单位
    attr_accessor :japanese       # 日文模式? (影响某些默认行为)
    attr_accessor :currency_unit  # 货币单位名称
    # 数据库类型名称 (数组, 索引0为nil)
    attr_accessor :skill_types, :weapon_types, :armor_types
    # 标题画面文件名
    attr_accessor :title1_name    # 标题画面背景1
    attr_accessor :title2_name    # 标题画面背景2 (前景/框)
    # 选项设置
    attr_accessor :opt_draw_title  # 绘制游戏标题?
    attr_accessor :opt_use_midi    # 使用 MIDI? (通常不使用)
    attr_accessor :opt_transparent # 主角初始透明?
    attr_accessor :opt_followers   # 显示队伍成员?
    attr_accessor :opt_slip_death  # 允许持续伤害致死?
    attr_accessor :opt_floor_death # 允许地形伤害致死?
    attr_accessor :opt_display_tp  # 战斗中显示 TP?
    attr_accessor :opt_extra_exp   # 额外经验值? (似乎未使用)
    # 窗口色调
    attr_accessor :window_tone    # (Tone 对象)
    # 默认战斗背景文件名
    attr_accessor :battleback1_name, :battleback2_name
    # @sounds: 音效列表 (Array<RPG::SE>)，覆盖 shared/RGSS2 定义
    attr_accessor :sounds

    # 初始化 RGSS3 System 特定属性
    def initialize_system_rgss3_specifics
      @japanese = true; @currency_unit = ""
      @skill_types = [nil, ""]; @weapon_types = [nil, ""]; @armor_types = [nil, ""]
      @title1_name = ""; @title2_name = ""
      @opt_draw_title = true; @opt_use_midi = false; @opt_transparent = false
      @opt_followers = true; @opt_slip_death = false; @opt_floor_death = false
      @opt_display_tp = true; @opt_extra_exp = false
      @window_tone = Tone.new([0.0, 0.0, 0.0, 0.0]) # 默认黑色调
      # 初始化音效数组 (24 个 SE 对象)
      @sounds = Array.new(24) { RPG::SE.new }
      @battleback1_name = ""; @battleback2_name = ""
    end

    # 解包各种文件名、货币单位和名称数组
    def unpack_names_system_rgss3
      # 解包普通文件名和字符串
      Utils.unpack_names_for(self, :currency_unit, :title1_name, :title2_name, :battleback1_name, :battleback2_name)
      # 解包名称数组
      [:elements, :switches, :variables, :skill_types, :weapon_types, :armor_types].each do |ivar_name|
        array = instance_variable_get("@#{ivar_name}")
        array&.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item }
      end
      # 解包音效数组
      @sounds&.each { |s| s&.unpack_names }
      # 其他如 BGM/ME, Terms, TestBattlers 由 System 类递归处理
    end
  end

  # ============================================================================
  # --- Animation::Frame Extensions (动画帧) ---
  # ============================================================================

  # --- RGSS1 Animation Frame Mixin ---
  # RGSS1 Frame 结构与 RGSS2/3 相同
  module AnimationFrameExtensionsRGSS1
    attr_accessor :cell_max  # 最大单元数 (RGSS1 特有?) - 似乎与 RGSS2/3 相同
    attr_accessor :cell_data # 单元数据 (Table 对象, N x 8)

    # 初始化 RGSS1 Frame 特定属性
    def initialize_animation_frame_rgss1_specifics
      @cell_max = 0
      # 初始化单元数据 Table (0x0)
      @cell_data = Table.new([]); @cell_data.resize(0, 0)
    end

    # Frame 没有需要解包的名称
    def unpack_names_animation_frame_rgss1
      # 通常为空
    end
  end

  # --- RGSS2 Animation Frame Mixin ---
  module AnimationFrameExtensionsRGSS2
    # @cell_data: 单元数据 (Table 对象, N x 8)
    attr_accessor :cell_data

    # 初始化 RGSS2 Frame 特定属性
    def initialize_animation_frame_rgss2_specifics
      # 初始化单元数据 Table (0x0)
      @cell_data = Table.new([]); @cell_data.resize(0, 0)
    end

    # Frame 没有需要解包的名称
    def unpack_names_animation_frame_rgss2
      # 通常为空
    end
  end

  # --- RGSS3 Animation Frame Mixin ---
  # (与 RGSS2 结构相同)
  module AnimationFrameExtensionsRGSS3
    # @cell_data: 单元数据 (Table 对象, N x 8)
    attr_accessor :cell_data

    # 初始化 RGSS3 Frame 特定属性
    def initialize_animation_frame_rgss3_specifics
      # 初始化单元数据 Table (0x0)
      @cell_data = Table.new([]); @cell_data.resize(0, 0)
    end

    # Frame 没有需要解包的名称
    def unpack_names_animation_frame_rgss3
      # 通常为空
    end
  end

  # ============================================================================
  # --- Troop::Member Extensions (队伍成员) ---
  # ============================================================================

  # --- RGSS1 Troop Member Mixin ---
  module TroopMemberExtensionsRGSS1
    attr_accessor :enemy_id # 敌人 ID
    attr_accessor :x, :y    # 初始 X, Y 坐标
    attr_accessor :immortal # 不朽? (不会被击倒) - RGSS1 特有

    # 初始化 RGSS1 Member 特定属性
    def initialize_troop_member_rgss1_specifics
      @enemy_id = 1; @x = 0; @y = 0; @immortal = false
    end

    # Member 没有需要解包的名称
    def unpack_names_troop_member_rgss1
      # 通常为空
    end
  end

  # --- RGSS2 Troop Member Mixin ---
  module TroopMemberExtensionsRGSS2
    # @immortal: 不朽? (不会被击倒) - RGSS2 特有
    attr_accessor :immortal

    # 初始化 RGSS2 Member 特定属性
    def initialize_troop_member_rgss2_specifics
      @immortal = false
    end

    # Member 没有需要解包的名称
    def unpack_names_troop_member_rgss2
      # 通常为空
    end
  end

  # --- RGSS3 Troop Member Mixin ---
  module TroopMemberExtensionsRGSS3
    # RGSS3 Member 没有额外的特定属性
    def initialize_troop_member_rgss3_specifics
      # 通常为空
    end

    def unpack_names_troop_member_rgss3
      # 通常为空
    end
  end

  # ============================================================================
  # --- System::TestBattler Extensions (测试战斗者) ---
  # ============================================================================

  # --- RGSS1 System TestBattler Mixin ---
  module SystemTestBattlerExtensionsRGSS1
    attr_accessor :actor_id, :level # 角色 ID, 等级
    # 装备 ID
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id

    # 初始化 RGSS1 TestBattler 特定属性
    def initialize_system_testbattler_rgss1_specifics
      @actor_id = 1; @level = 1
      @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
    end

    # TestBattler 没有需要解包的名称
    def unpack_names_system_testbattler_rgss1
      # 通常为空
    end
  end

  # --- RGSS2 System TestBattler Mixin ---
  module SystemTestBattlerExtensionsRGSS2
    # 装备 ID
    attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id

    # 初始化 RGSS2 TestBattler 特定属性
    def initialize_system_testbattler_rgss2_specifics
      @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
    end

    # TestBattler 没有需要解包的名称
    def unpack_names_system_testbattler_rgss2
      # 通常为空
    end
  end

  # --- RGSS3 System TestBattler Mixin ---
  module SystemTestBattlerExtensionsRGSS3
    # @equips: 装备 ID 数组 (同 Actor)
    attr_accessor :equips

    # 初始化 RGSS3 TestBattler 特定属性
    def initialize_system_testbattler_rgss3_specifics
      @equips = [0, 0, 0, 0, 0]
    end

    # TestBattler 没有需要解包的名称
    def unpack_names_system_testbattler_rgss3
      # 通常为空
    end
  end

  # ============================================================================
  # --- EquipItem Extensions (装备物品基类 - 仅 RGSS3) ---
  # ============================================================================

  # RGSS1 和 RGSS2 没有 EquipItem 基类

  # --- RGSS3 EquipItem Mixin ---
  module EquipItemExtensionsRGSS3
    attr_accessor :price    # 价格
    attr_accessor :etype_id # 装备类型 ID (0:武器, 1:盾, 2:头, 3:身, 4:饰品)
    # 能力值加成 (数组, [MaxHP, MaxMP, ATK, DEF, MAT, MDF, AGI, LUK])
    attr_accessor :params

    # 初始化 RGSS3 EquipItem 特定属性
    def initialize_equipitem_rgss3_specifics
      @price = 0; @etype_id = 0 # 默认为武器?
      @params = [0] * 8 # 初始化 8 个能力值加成为 0
    end

    # EquipItem 没有额外的名称需要解包 (父类 BaseItem 处理)
    def unpack_names_equipitem_rgss3
      # 通常为空
    end
  end

  # ============================================================================
  # --- Class Extensions (职业) ---
  # ============================================================================

  # --- RGSS1 Class Mixin ---
  module ClassExtensionsRGSS1
    # 基本信息
    attr_accessor :id, :name
    # 战斗图位置 (0:前排, 1:中间, 2:后排) - RMXP 似乎未使用?
    attr_accessor :position
    # 可装备的武器/护甲 ID 列表
    attr_accessor :weapon_set, :armor_set
    # 属性和状态有效度 (Table 对象)
    attr_accessor :element_ranks, :state_ranks
    # 学习技能列表 (Array<RPG::Class::Learning>)
    attr_accessor :learnings

    # 初始化 RGSS1 Class 特定属性
    def initialize_class_rgss1_specifics
      @id = 0; @name = ""; @position = 0
      @weapon_set = []; @armor_set = []
      @element_ranks = Table.new([]); @element_ranks.resize(1)
      @state_ranks = Table.new([]); @state_ranks.resize(1)
      @learnings = []
    end

    # 解包职业名称
    def unpack_names_class_rgss1
      Utils.unpack_names_for(self, :name)
      # @learnings 由 Class 类自身递归处理
    end
  end

  # --- RGSS2 Class Mixin ---
  module ClassExtensionsRGSS2
    # 基本信息 (同 RGSS1)
    attr_accessor :id, :name, :position
    # 可装备的武器/护甲 ID 列表 (同 RGSS1)
    attr_accessor :weapon_set, :armor_set
    # 属性和状态有效度 (同 RGSS1)
    attr_accessor :element_ranks, :state_ranks
    # 学习技能列表 (同 RGSS1)
    attr_accessor :learnings
    # VX 特有: 固有技能名称 (似乎用于旧版导入?)
    attr_accessor :skill_name_valid, :skill_name

    # 初始化 RGSS2 Class 特定属性
    def initialize_class_rgss2_specifics
      @id = 0; @name = ""; @position = 0
      @weapon_set = []; @armor_set = []
      @element_ranks = Table.new([]); @element_ranks.resize(1)
      @state_ranks = Table.new([]); @state_ranks.resize(1)
      @learnings = []
      @skill_name_valid = false; @skill_name = ""
    end

    # 解包职业名称和固有技能名称
    def unpack_names_class_rgss2
      Utils.unpack_names_for(self, :name, :skill_name)
      # @learnings 由 Class 类自身递归处理
    end
  end

  # --- RGSS3 Class Mixin ---
  module ClassExtensionsRGSS3
    # 经验值曲线参数 (数组, [基础值, 附加值, 加速度A, 加速度B])
    attr_accessor :exp_params
    # 能力值曲线 (Table 对象, 8 行 [MaxHP...LUK], 99 列 [等级1-99])
    attr_accessor :params
    # 学习技能列表 (Array<RPG::Class::Learning>)
    attr_accessor :learnings

    # 初始化 RGSS3 Class 特定属性
    def initialize_class_rgss3_specifics
      @exp_params = [30, 20, 30, 30] # Ace 默认值
      # 初始化能力值 Table 为 8x99
      @params = Table.new([]); @params.resize(8, 99)
      @learnings = []
    end

    # Class 没有额外的名称需要解包 (父类 BaseItem 处理)
    # @learnings 中的 note 由 Class 类自身递归处理
    def unpack_names_class_rgss3
      # 通常为空
    end
  end

  # ============================================================================
  # --- Tileset Extensions (图块组) ---
  # ============================================================================

  # --- RGSS1 Tileset Mixin ---
  module TilesetExtensionsRGSS1
    # 基本信息和文件名
    attr_accessor :id, :name, :tileset_name # 图块组 ID, 名称, 图块集文件名
    # 自动图块文件名列表 (7 个字符串)
    attr_accessor :autotile_names
    # 远景图
    attr_accessor :panorama_name, :panorama_hue # 文件名, 色相
    # 雾
    attr_accessor :fog_name, :fog_hue, :fog_opacity, :fog_blend_type, :fog_zoom, :fog_sx, :fog_sy
    # 文件名, 色相, 不透明度, 合成方式, 缩放率, X/Y 滚动速度
    # 战斗背景
    attr_accessor :battleback_name # 文件名
    # 地图图块属性 (Table 对象)
    attr_accessor :passages    # 通行度 (384 个元素)
    attr_accessor :priorities  # 优先级 (384 个元素)
    attr_accessor :terrain_tags # 地形标志 (384 个元素)

    # 初始化 RGSS1 Tileset 特定属性
    def initialize_tileset_rgss1_specifics
      @id = 0; @name = ""; @tileset_name = ""
      @autotile_names = Array.new(7) { "" }
      @panorama_name = ""; @panorama_hue = 0
      @fog_name = ""; @fog_hue = 0; @fog_opacity = 64; @fog_blend_type = 0; @fog_zoom = 200; @fog_sx = 0; @fog_sy = 0
      @battleback_name = ""
      # 初始化属性 Table
      @passages = Table.new([]); @passages.resize(384)
      @priorities = Table.new([]); @priorities.resize(384); @priorities[0] = 5 # 默认第一个图块优先级为 5
      @terrain_tags = Table.new([]); @terrain_tags.resize(384)
    end

    # 解包各种文件名和自动图块名称数组
    def unpack_names_tileset_rgss1
      Utils.unpack_names_for(self, :name, :tileset_name, :panorama_name, :fog_name, :battleback_name)
      @autotile_names&.map! { |n| n.is_a?(String) ? RPG.unpack_str(n) : n }
    end
  end

  # --- RGSS2 没有单独的 Tileset 类 ---
  # 图块属性存储在 System 的 @passages 中

  # --- RGSS3 Tileset Mixin ---
  module TilesetExtensionsRGSS3
    # 基本信息
    attr_accessor :id, :mode # 图块组 ID, 模式 (1:地域型, 2:VX兼容型)
    attr_accessor :name     # 名称
    # 图块集文件名列表 (9 个字符串: A1-A5, B, C, D, E)
    attr_accessor :tileset_names
    # 图块属性标志 (Table 对象, 8192 个元素)
    attr_accessor :flags
    # 备注
    attr_accessor :note

    # 初始化 RGSS3 Tileset 特定属性
    def initialize_tileset_rgss3_specifics
      @id = 0; @mode = 1 # 默认地域型
      @name = ""; @tileset_names = Array.new(9) { "" }
      # 初始化标志 Table 并设置默认值
      @flags = Table.new([]); @flags.resize(8192)
      @flags[0] = 0x0010 # 第一个图块 (通常为空) 默认是下层星号不可通行
      # 设置默认的 Tile B-E 通行和优先级 (?) - 这些值可能需要根据编辑器默认行为调整
      (2048..2815).each { |i| @flags[i] = 0x000F } # 可能是默认 B 图块区域？ (通行四方向 + 上层 + ?)
      (4352..8191).each { |i| @flags[i] = 0x000F } # 可能是默认 C,D,E 图块区域？
      @note = ""
    end

    # 解包名称、备注和图块集文件名数组
    def unpack_names_tileset_rgss3
      Utils.unpack_names_for(self, :name, :note)
      @tileset_names&.map! { |n| n.is_a?(String) ? RPG.unpack_str(n) : n }
    end
  end

  # ============================================================================
  # --- Event::Page::Graphic Extensions (事件页图像) ---
  # ============================================================================

  # --- RGSS1 Event Page Graphic Mixin ---
  module EventPageGraphicExtensionsRGSS1
    # 图块 ID (如果使用图块作为图像) - 似乎 RMXP 不直接使用 tile_id
    # attr_accessor :tile_id
    # 角色图像
    attr_accessor :character_name, :character_hue # 文件名, 色相
    # 显示属性
    attr_accessor :direction, :pattern # 初始朝向 (2下,4左,6右,8上), 动画帧 (0,1,2)
    attr_accessor :opacity, :blend_type # 不透明度 (0-255), 合成方式 (0:普通, 1:加法, 2:减法) - RGSS1 特有

    # 初始化 RGSS1 Graphic 特定属性
    def initialize_event_page_graphic_rgss1_specifics
      # @tile_id = 0 # RMXP 可能没有这个
      @character_name = ""; @character_hue = 0
      @direction = 2; @pattern = 0
      @opacity = 255; @blend_type = 0
    end

    # 解包角色文件名
    def unpack_names_event_page_graphic_rgss1
      Utils.unpack_names_for(self, :character_name)
    end
  end

  # --- RGSS2 Event Page Graphic Mixin ---
  module EventPageGraphicExtensionsRGSS2
    attr_accessor :tile_id         # 图块 ID (如果使用图块)
    # 角色图像
    attr_accessor :character_name, :character_index # 文件名, 索引 (0-7)
    # 显示属性
    attr_accessor :direction, :pattern # 初始朝向, 动画帧

    # 初始化 RGSS2 Graphic 特定属性
    def initialize_event_page_graphic_rgss2_specifics
      @tile_id = 0; @character_name = ""; @character_index = 0
      @direction = 2; @pattern = 0
      # VX 没有 opacity 和 blend_type
    end

    # 解包角色文件名
    def unpack_names_event_page_graphic_rgss2
      Utils.unpack_names_for(self, :character_name)
    end
  end

  # --- RGSS3 Event Page Graphic Mixin ---
  # (与 RGSS2 结构相同)
  module EventPageGraphicExtensionsRGSS3
    attr_accessor :tile_id         # 图块 ID
    attr_accessor :character_name, :character_index # 文件名, 索引
    attr_accessor :direction, :pattern # 初始朝向, 动画帧

    # 初始化 RGSS3 Graphic 特定属性
    def initialize_event_page_graphic_rgss3_specifics
      @tile_id = 0; @character_name = ""; @character_index = 0
      @direction = 2; @pattern = 0
    end

    # 解包角色文件名
    def unpack_names_event_page_graphic_rgss3
      Utils.unpack_names_for(self, :character_name)
    end
  end

  # ============================================================================
  # --- Animation Extensions (动画) ---
  # ============================================================================

  # --- RGSS1 Animation Mixin ---
  module AnimationExtensionsRGSS1
    # 基本信息和文件名
    attr_accessor :id, :name
    attr_accessor :animation_name, :animation_hue # 动画图像文件名, 色相 - RGSS1 特有
    # 播放设置
    attr_accessor :position  # 位置 (0:上方, 1:中间, 2:下方, 3:屏幕)
    attr_accessor :frame_max # 最大帧数
    # 数据
    attr_accessor :frames    # 帧列表 (Array<RPG::Animation::Frame>)
    attr_accessor :timings   # 时序列表 (Array<RPG::Animation::Timing>)

    # 初始化 RGSS1 Animation 特定属性
    def initialize_animation_rgss1_specifics
      @id = 0; @name = ""; @animation_name = ""; @animation_hue = 0
      @position = 1; @frame_max = 1
      @frames = []; @timings = []
    end

    # 解包名称和动画文件名
    def unpack_names_animation_rgss1
      Utils.unpack_names_for(self, :name, :animation_name)
      # frames 和 timings 由 Animation 类递归处理
    end
  end

  # --- RGSS2 Animation Mixin ---
  module AnimationExtensionsRGSS2
    # 基本信息和文件名 (使用两套动画文件)
    attr_accessor :id, :name
    attr_accessor :animation1_name, :animation1_hue # 动画文件1 (通常是战斗动画)
    attr_accessor :animation2_name, :animation2_hue # 动画文件2 (通常是地图动画)
    # 播放设置
    attr_accessor :position, :frame_max # 位置 (同 RGSS1), 最大帧数
    # 数据
    attr_accessor :frames, :timings # 帧列表, 时序列表

    # 初始化 RGSS2 Animation 特定属性
    def initialize_animation_rgss2_specifics
      @id = 0; @name = ""; @animation1_name = ""; @animation1_hue = 0; @animation2_name = ""; @animation2_hue = 0
      @position = 1; @frame_max = 1
      @frames = []; @timings = []
    end

    # 解包名称和两个动画文件名
    def unpack_names_animation_rgss2
      Utils.unpack_names_for(self, :name, :animation1_name, :animation2_name)
      # frames 和 timings 由 Animation 类递归处理
    end
  end

  # --- RGSS3 Animation Mixin ---
  # (与 RGSS2 结构相同)
  module AnimationExtensionsRGSS3
    attr_accessor :id, :name
    attr_accessor :animation1_name, :animation1_hue
    attr_accessor :animation2_name, :animation2_hue
    attr_accessor :position, :frame_max
    attr_accessor :frames, :timings

    # 初始化 RGSS3 Animation 特定属性
    def initialize_animation_rgss3_specifics
      @id = 0; @name = ""; @animation1_name = ""; @animation1_hue = 0; @animation2_name = ""; @animation2_hue = 0
      @position = 1; @frame_max = 1
      @frames = []; @timings = []
    end

    # 解包名称和两个动画文件名
    def unpack_names_animation_rgss3
      Utils.unpack_names_for(self, :name, :animation1_name, :animation2_name)
      # frames 和 timings 由 Animation 类递归处理
    end
  end

  # ============================================================================
  # --- Animation::Timing Extensions (动画时序) ---
  # ============================================================================

  # --- RGSS1 Animation Timing Mixin ---
  module AnimationTimingExtensionsRGSS1
    attr_accessor :frame         # 触发帧
    attr_accessor :se            # 播放的音效 (RPG::AudioFile 对象)
    # 画面闪烁效果
    attr_accessor :flash_scope   # 闪烁范围 (0:无, 1:目标, 2:画面, 3:目标并消失)
    attr_accessor :flash_color   # 闪烁颜色 (Color 对象)
    attr_accessor :flash_duration # 闪烁持续时间 (帧)
    # 播放条件
    attr_accessor :condition     # 条件 (0:无, 1:命中, 2:未命中, 3:蒸发) - RGSS1 特有

    # 初始化 RGSS1 Timing 特定属性
    def initialize_animation_timing_rgss1_specifics
      @frame = 0; @se = RPG::SE.new("", 80)
      @flash_scope = 0; @flash_color = Color.new([255.0, 255.0, 255.0, 255.0])
      @flash_duration = 5; @condition = 0
    end

    # 解包 SE 音效文件名
    def unpack_names_animation_timing_rgss1
      @se&.unpack_names
    end
  end

  # --- RGSS2 Animation Timing Mixin ---
  module AnimationTimingExtensionsRGSS2
    attr_accessor :frame
    attr_accessor :se
    attr_accessor :flash_scope, :flash_color, :flash_duration
    # RGSS2 没有 @condition

    # 初始化 RGSS2 Timing 特定属性
    def initialize_animation_timing_rgss2_specifics
      @frame = 0; @se = RPG::SE.new("", 80)
      @flash_scope = 0; @flash_color = Color.new([255.0, 255.0, 255.0, 255.0])
      @flash_duration = 5
    end

    # 解包 SE 音效文件名
    def unpack_names_animation_timing_rgss2
      @se&.unpack_names
    end
  end

  # --- RGSS3 Animation Timing Mixin ---
  # (与 RGSS2 结构相同)
  module AnimationTimingExtensionsRGSS3
    attr_accessor :frame
    attr_accessor :se
    attr_accessor :flash_scope, :flash_color, :flash_duration

    # 初始化 RGSS3 Timing 特定属性
    def initialize_animation_timing_rgss3_specifics
      @frame = 0; @se = RPG::SE.new("", 80)
      @flash_scope = 0; @flash_color = Color.new([255.0, 255.0, 255.0, 255.0])
      @flash_duration = 5
    end

    # 解包 SE 音效文件名
    def unpack_names_animation_timing_rgss3
      @se&.unpack_names
    end
  end
end # module RPG
