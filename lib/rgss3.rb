# 包含 RGSS3 (RPG Maker VX Ace) 特有的类定义或对共享类的修改

require_relative "shared"         # 加载共享定义 (包括基类 RPG::BaseItem, RPG::UsableItem)
require_relative "rgss_extensions" # 加载版本特定扩展 Mixin

module RPG
  # --- RGSS3 特有嵌套类定义 ---
  # 在 BaseItem 和 UsableItem 模块内部提前定义这些嵌套类，以便后续使用

  # -- 特性 (Feature) 类 --
  # 嵌套在 BaseItem 下，用于定义各种数据库对象（角色、职业、物品、敌人、状态等）的特性
  class BaseItem
    class Feature
      attr_accessor :code, :data_id, :value # 特性代码, 数据ID, 值
      # code: 特性类型 (见编辑器)
      # data_id: 关联的数据ID (如元素ID, 状态ID, 技能ID等)
      # value: 特性的数值 (如比率, 固定值等)
      def initialize(code = 0, data_id = 0, value = 0.0) # 值可以是浮点数
        @code = code; @data_id = data_id; @value = value
      end
    end
  end

  # -- 效果 (Effect) 和 伤害 (Damage) 类 --
  # 嵌套在 UsableItem (技能和物品的基类) 下
  class UsableItem
    # -- 效果类 --
    # 定义技能/物品使用时的效果
    class Effect
      attr_accessor :code, :data_id, :value1, :value2 # 效果代码, 数据ID, 值1, 值2
      # code: 效果类型 (见编辑器)
      # data_id: 关联的数据ID (如状态ID, 参数ID, 公共事件ID等)
      # value1, value2: 效果的参数值
      def initialize(code = 0, data_id = 0, value1 = 0.0, value2 = 0.0) # 值可以是浮点数
        @code = code; @data_id = data_id; @value1 = value1; @value2 = value2
      end
    end

    # -- 伤害类 --
    # 定义技能/物品造成的伤害属性
    class Damage
      attr_accessor :type, :element_id, :formula, :variance, :critical
      # 类型, 元素ID, 伤害公式, 分散度%, 允许暴击?
      # type: 0:无, 1:HP伤害, 2:MP伤害, 3:HP恢复, 4:MP恢复, 5:HP吸收, 6:MP吸收
      # element_id: 伤害/恢复的属性 (-1:普通攻击, 0:无, 1..n:元素ID)
      # formula: 计算伤害的 Ruby 公式字符串
      # variance: 伤害波动范围百分比
      # critical: 是否允许暴击

      # 解包伤害公式字符串
      def unpack_names; Utils.unpack_names_for(self, :formula); end

      def initialize
        @type = 0; @element_id = 0; @formula = "0"; @variance = 20; @critical = false
      end
    end
  end

  # --- 重打开或定义 RGSS3 核心 RPG 类 ---
  # 注意: RGSS3 中大部分数据库对象都继承自 RPG::BaseItem

  # -- 角色类 (Actor) --
  class Actor < RPG::BaseItem # 继承自 BaseItem
    include RPG::BaseItemExtensionsRGSS3 # 引入 RGSS3 BaseItem 的通用属性 (@features)
    include RPG::ActorExtensionsRGSS3   # 引入 RGSS3 Actor 的特定属性

    # 初始化方法，调用父类和 Mixin 初始化
    def initialize; super(); initialize_baseitem_rgss3_specifics; initialize_actor_rgss3_specifics; end

    # 解包方法，调用父类和 Mixin 解包
    def unpack_names; super(); unpack_names_actor_rgss3; end
  end

  # -- 职业类 (Class) --
  class Class < RPG::BaseItem # 继承自 BaseItem
    include RPG::BaseItemExtensionsRGSS3 # 引入 RGSS3 BaseItem 的通用属性 (@features)
    include RPG::ClassExtensionsRGSS3   # 引入 RGSS3 Class 的特定属性

    # 初始化方法，调用父类和 Mixin 初始化，并添加默认特性
    def initialize
      super()
      initialize_baseitem_rgss3_specifics
      initialize_class_rgss3_specifics
      # 添加默认的职业特性 (如命中率、回避率、会心率、物理减伤、魔法减伤等)
      @features ||= []
      @features.push(RPG::BaseItem::Feature.new(23, 0, 1))    # 装备类型: 武器
      @features.push(RPG::BaseItem::Feature.new(22, 0, 0.95)) # 特殊能力值: 物理伤害率 95%
      @features.push(RPG::BaseItem::Feature.new(22, 1, 0.05)) # 特殊能力值: 魔法回避率 5%
      @features.push(RPG::BaseItem::Feature.new(22, 2, 0.04)) # 特殊能力值: 会心一击率 4%
      @features.push(RPG::BaseItem::Feature.new(41, 1))       # 攻击属性: 物理
      @features.push(RPG::BaseItem::Feature.new(51, 1))       # 装备武器类型: 匕首 (示例，可能因默认职业不同而异)
      @features.push(RPG::BaseItem::Feature.new(52, 1))       # 装备防具类型: 轻甲 (示例)
    end

    # 解包方法，调用父类和 Mixin 解包，并递归解包学习技能的备注
    def unpack_names
      super()
      unpack_names_class_rgss3
      @learnings&.each { |l| l.unpack_names if l.respond_to?(:unpack_names) }
    end

    # RGSS3 职业的嵌套“学习”类
    class Learning
      attr_accessor :level, :skill_id, :note # 等级, 技能ID, 备注
      # 解包备注字符串
      def unpack_names; Utils.unpack_names_for(self, :note); end
      def initialize; @level = 1; @skill_id = 1; @note = ""; end
    end
  end # Class

  # -- 技能类 (Skill) --
  class Skill < RPG::UsableItem # 继承自 UsableItem
    include RPG::BaseItemExtensionsRGSS3    # 引入 RGSS3 BaseItem 的通用属性 (@features)
    include RPG::UsableItemExtensionsRGSS3  # 引入 RGSS3 UsableItem 的特定属性
    include RPG::SkillExtensionsRGSS3       # 引入 RGSS3 Skill 的特定属性

    # 初始化方法，调用各层父类和 Mixin 初始化，设置默认范围
    def initialize; super(); initialize_baseitem_rgss3_specifics; initialize_usableitem_rgss3_specifics; initialize_skill_rgss3_specifics; @scope = 1; end # 默认范围：敌方单体
    # 解包方法，调用各层父类和 Mixin 解包
    def unpack_names; super(); unpack_names_usableitem_rgss3; unpack_names_skill_rgss3; end
  end

  # -- 物品类 (Item) --
  class Item < RPG::UsableItem # 继承自 UsableItem
    include RPG::BaseItemExtensionsRGSS3    # 引入 RGSS3 BaseItem 的通用属性 (@features)
    include RPG::UsableItemExtensionsRGSS3  # 引入 RGSS3 UsableItem 的特定属性
    include RPG::ItemExtensionsRGSS3        # 引入 RGSS3 Item 的特定属性

    # 初始化方法，调用各层父类和 Mixin 初始化，设置默认范围
    def initialize; super(); initialize_baseitem_rgss3_specifics; initialize_usableitem_rgss3_specifics; initialize_item_rgss3_specifics; @scope = 7; end # 默认范围：我方单体
    # 解包方法，调用各层父类和 Mixin 解包
    def unpack_names; super(); unpack_names_usableitem_rgss3; unpack_names_item_rgss3; end
  end

  # -- 装备物品基类 (EquipItem) --
  # RGSS3 新增的基类，用于武器和护甲
  class EquipItem < RPG::BaseItem # 继承自 BaseItem
    include RPG::BaseItemExtensionsRGSS3   # 引入 RGSS3 BaseItem 的通用属性 (@features)
    include RPG::EquipItemExtensionsRGSS3 # 引入 RGSS3 EquipItem 的特定属性

    # 初始化方法，调用父类和 Mixin 初始化
    def initialize; super(); initialize_baseitem_rgss3_specifics; initialize_equipitem_rgss3_specifics; end

    # 解包方法，调用父类和 Mixin 解包
    def unpack_names; super(); unpack_names_equipitem_rgss3; end
  end

  # -- 武器类 (Weapon) --
  class Weapon < RPG::EquipItem # 继承自 EquipItem
    include RPG::WeaponExtensionsRGSS3 # 引入 RGSS3 Weapon 的特定属性

    # 初始化方法，调用父类和 Mixin 初始化，设置默认装备类型和特性
    def initialize
      super()
      initialize_weapon_rgss3_specifics
      @etype_id = 0 # 装备类型，0 通常代表武器
      @features ||= []
      @features.push(RPG::BaseItem::Feature.new(31, 1, 0)) # 攻击属性: 物理 (示例)
      @features.push(RPG::BaseItem::Feature.new(22, 0, 0)) # 特殊能力值: 物理伤害率 0% (表示使用武器自身攻击力)
    end

    # 解包方法，调用父类和 Mixin 解包
    def unpack_names; super(); unpack_names_weapon_rgss3; end
  end

  # -- 护甲类 (Armor) --
  class Armor < RPG::EquipItem # 继承自 EquipItem
    include RPG::ArmorExtensionsRGSS3 # 引入 RGSS3 Armor 的特定属性

    # 初始化方法，调用父类和 Mixin 初始化，添加默认特性
    def initialize
      super()
      initialize_armor_rgss3_specifics
      @features ||= []
      @features.push(RPG::BaseItem::Feature.new(22, 1, 0)) # 特殊能力值: 魔法回避率 0% (示例)
    end

    # 解包方法，调用父类和 Mixin 解包
    def unpack_names; super(); unpack_names_armor_rgss3; end
  end

  # -- 敌人种类类 (Enemy) --
  class Enemy < RPG::BaseItem # 继承自 BaseItem
    include RPG::BaseItemExtensionsRGSS3 # 引入 RGSS3 BaseItem 的通用属性 (@features)
    include RPG::EnemyExtensionsRGSS3   # 引入 RGSS3 Enemy 的特定属性

    # 初始化方法，调用父类和 Mixin 初始化，添加默认特性
    def initialize
      super()
      initialize_baseitem_rgss3_specifics
      initialize_enemy_rgss3_specifics
      @features ||= []
      @features.push(RPG::BaseItem::Feature.new(22, 0, 0.95)) # 特殊能力值: 物理伤害率 95% (示例)
      @features.push(RPG::BaseItem::Feature.new(22, 1, 0.05)) # 特殊能力值: 魔法回避率 5% (示例)
      @features.push(RPG::BaseItem::Feature.new(31, 1, 0))    # 攻击属性: 物理 (示例)
    end

    # 解包方法，调用父类和 Mixin 解包
    def unpack_names; super(); unpack_names_enemy_rgss3; end

    # RGSS3 敌人的嵌套“行动”类
    class Action
      attr_accessor :skill_id, :condition_type, :condition_param1, :condition_param2, :rating
      # 技能ID, 条件类型, 条件参数1, 条件参数2, 评价

      def initialize; @skill_id = 1; @condition_type = 0; @condition_param1 = 0; @condition_param2 = 0; @rating = 5; end
    end

    # RGSS3 敌人的嵌套“掉落物品”类
    class DropItem
      attr_accessor :kind, :data_id, :denominator
      # 种类 (0:无, 1:物品, 2:武器, 3:护甲), 数据ID (物品/武器/护甲ID), 掉落率分母

      def initialize; @kind = 0; @data_id = 1; @denominator = 1; end
    end
  end # Enemy

  # -- 移动路线类 (MoveRoute) --
  # (与 RGSS2 结构相同)
  class MoveRoute
    attr_accessor :repeat, :skippable, :wait, :list # 是否重复, 是否可跳过, 是否等待移动结束, 移动指令列表

    def initialize
      @repeat = true
      @skippable = false
      @wait = false # RGSS3 包含 @wait
      @list = [RPG::MoveCommand.new] # 移动指令列表
    end
  end

  # -- 状态类 (State) --
  class State < RPG::BaseItem # 继承自 BaseItem
    include RPG::BaseItemExtensionsRGSS3 # 引入 RGSS3 BaseItem 的通用属性 (@features)
    include RPG::StateExtensionsRGSS3   # 引入 RGSS3 State 的特定属性

    # 初始化方法，调用父类和 Mixin 初始化
    def initialize; super(); initialize_baseitem_rgss3_specifics; initialize_state_rgss3_specifics; end

    # 解包方法，调用父类和 Mixin 解包
    def unpack_names; super(); unpack_names_state_rgss3; end
  end

  # -- 图块组类 (Tileset) --
  # RGSS3 的 Tileset 类结构与 RGSS1/2 完全不同
  class Tileset
    include RPG::TilesetExtensionsRGSS3 # 引入 RGSS3 Tileset 的特定属性和方法

    # 初始化方法，调用 Mixin 初始化
    def initialize; initialize_tileset_rgss3_specifics; end

    # 解包名称、备注、图块集文件名数组的方法
    def unpack_names; unpack_names_tileset_rgss3; end
  end

  # -- 地图类 (Map) --
  # 重打开共享的 RPG::Map 类，添加 RGSS3 特定内容
  class Map
    include RPG::MapExtensionsRGSS3 # 引入 RGSS3 Map 的特定属性和方法

    # RGSS3 地图初始化 (VX Ace 默认尺寸 17x13)
    def initialize(width = 17, height = 13)
      # --- 设置共享属性 (来自 shared.rb 但在这里初始化) ---
      @width = width; @height = height
      @scroll_type = 0; @autoplay_bgm = false; @bgm = RPG::BGM.new
      @autoplay_bgs = false; @bgs = RPG::BGS.new; @disable_dashing = false
      @encounter_step = 30; @parallax_name = ""
      @parallax_loop_x = false; @parallax_loop_y = false
      @parallax_sx = 0; @parallax_sy = 0; @parallax_show = false
      @events = {}
      # --- 共享属性设置结束 ---

      # 调用 Mixin 中的特定初始化逻辑 (设置 @display_name, @tileset_id, @data 等)
      initialize_map_rgss3_specifics(width, height)
    end

    # 解包地图的特定名称属性 (远景图, 显示名称, 战斗背景等) 和 Mixin 中的属性
    def unpack_names
      Utils.unpack_names_for(self, :parallax_name) # 解包共享的远景图名称
      unpack_names_map_rgss3 # 调用 Mixin 中的解包逻辑 (处理显示名称、战斗背景、备注等)
      @events&.each_value { |e| e.unpack_names if e.respond_to?(:unpack_names) } # 递归解包事件
      @bgm&.unpack_names # 解包 BGM 文件名
      @bgs&.unpack_names # 解包 BGS 文件名
    end

    # RGSS3 地图的嵌套“遭遇”类
    class Encounter
      attr_accessor :troop_id, :weight, :region_set # 队伍ID, 权重, 区域ID集合

      def initialize; @troop_id = 1; @weight = 10; @region_set = []; end
    end
  end # Map

  # -- 系统设置类 (System) --
  # 重打开共享的 RPG::System 类，添加 RGSS3 特定内容
  class System
    include RPG::SystemExtensionsRGSS3 # 引入 RGSS3 System 的特定属性和方法

    # RGSS3 系统设置初始化
    def initialize
      # --- 设置共享属性 (来自 shared.rb 但在这里初始化) ---
      @game_title = ""; @version_id = 0; @party_members = [1]
      @elements = [nil, ""]; @switches = [nil, ""]; @variables = [nil, ""] # 注意: elements 在 RGSS3 中有定义
      @boat = RPG::System::Vehicle.new; @ship = RPG::System::Vehicle.new; @airship = RPG::System::Vehicle.new
      @title_bgm = RPG::BGM.new; @battle_bgm = RPG::BGM.new
      @battle_end_me = RPG::ME.new; @gameover_me = RPG::ME.new
      # @sounds 在 RGSS3 Mixin 中定义
      @test_battlers = []; @test_troop_id = 1
      @start_map_id = 1; @start_x = 0; @start_y = 0
      @edit_map_id = 1
      @battler_name = ""; @battler_hue = 0
      # --- 共享属性设置结束 ---

      # 实例化 RGSS3 特定的 Terms 对象
      @terms = RPG::System::Terms.new
      # 调用 Mixin 中的特定初始化逻辑 (设置 @japanese, @skill_types, @window_tone, @sounds 等)
      initialize_system_rgss3_specifics
    end

    # 解包系统设置中的特定名称属性和 Mixin 中的属性
    def unpack_names
      # 解包共享的名称属性
      Utils.unpack_names_for(self, :game_title, :battler_name)
      # 调用 Mixin 中的解包逻辑 (处理货币单位、标题画面、战斗背景、类型名称数组、声音数组等)
      unpack_names_system_rgss3
      # 解包术语
      @terms.unpack_names if @terms.respond_to?(:unpack_names)
      # 解包 BGM/ME
      [:@title_bgm, :@battle_bgm, :@battle_end_me, :@gameover_me].each { |ivar| instance_variable_get(ivar)&.unpack_names }
      # 解包交通工具
      [@boat, @ship, @airship].each { |v| v&.unpack_names }
      # 递归处理测试战斗者
      @test_battlers&.each { |b| b.unpack_names if b.respond_to?(:unpack_names) }
    end

    # RGSS3 系统设置的嵌套“术语”类
    class Terms
      attr_accessor :basic, :params, :etypes, :commands
      # 基本状态 (等级, HP, MP...), 能力值 (力量, 敏捷...), 装备类型 (武器, 盾...), 指令 (攻击, 防御...)

      # 解包所有术语数组中的字符串
      def unpack_names
        [:@basic, :@params, :@etypes, :@commands].each do |ivar|
          array = instance_variable_get(ivar)
          # 对数组中的每个字符串元素进行解包
          array&.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item }
        end
      end

      def initialize
        # 初始化为包含空字符串的数组
        @basic = Array.new(8) { "" }    # 等级, HP, MP, TP, 等级缩写, HP缩写, MP缩写, TP缩写
        @params = Array.new(8) { "" }   # 最大HP, 最大MP, 攻击力, 防御力, 魔法攻击, 魔法防御, 敏捷, 幸运
        @etypes = Array.new(5) { "" }   # 武器, 盾, 头, 身体, 饰品
        @commands = Array.new(23) { "" } # 攻击, 防御, 物品, 技能, 装备, 状态, 队形, 保存, 游戏结束...
      end
    end # Terms

    # RGSS3 系统设置的嵌套“测试战斗者”类
    # 重打开共享的 TestBattler 类，添加 RGSS3 特定内容
    class TestBattler
      include RPG::SystemTestBattlerExtensionsRGSS3 # 引入 RGSS3 TestBattler 的特定属性和方法

      # 初始化方法，先调用父类(共享TestBattler)初始化，再调用 Mixin 初始化
      def initialize
        # --- 设置共享属性 ---
        @actor_id = 1; @level = 1
        # --- 共享属性结束 ---
        # 调用 Mixin 初始化 (设置 @equips 数组)
        initialize_system_testbattler_rgss3_specifics
      end

      # TestBattler 没有名称需要解包
    end
  end # System

  # -- 动画帧类 (Animation::Frame) --
  # 重打开共享的 Animation::Frame 类，添加 RGSS3 特定内容
  class Animation::Frame
    include RPG::AnimationFrameExtensionsRGSS3 # 引入 RGSS3 Frame 的特定属性和方法

    # 初始化方法，先调用父类(共享 Frame)初始化，再调用 Mixin 初始化
    def initialize
      super() # 调用共享 Frame 的 initialize (@cell_max = 0)
      # 调用 Mixin 初始化 (设置 @cell_data)
      initialize_animation_frame_rgss3_specifics
    end

    # Frame 没有名称需要解包
  end

  # -- 动画时序类 (Animation::Timing) --
  # 重打开共享的 Animation::Timing 类，添加 RGSS3 特定内容
  class Animation::Timing
    include RPG::AnimationTimingExtensionsRGSS3 # 引入 RGSS3 Timing 的特定属性和方法

    # 初始化方法，先调用父类(共享 Timing)初始化，再调用 Mixin 初始化
    def initialize
      # --- 设置共享属性 ---
      @frame = 0; @se = RPG::SE.new("", 80); @flash_scope = 0
      @flash_color = Color.new([255.0, 255.0, 255.0, 255.0]); @flash_duration = 5
      # --- 共享属性结束 ---
      # 调用 Mixin 初始化 (RGSS3 无特殊属性)
      initialize_animation_timing_rgss3_specifics
    end

    # 解包 SE 文件名
    def unpack_names
      unpack_names_animation_timing_rgss3 # 调用 Mixin 解包 (处理 @se)
    end
  end

  # -- 队伍成员类 (Troop::Member) --
  # 重打开共享的 Troop::Member 类，添加 RGSS3 特定内容
  class Troop::Member
    include RPG::TroopMemberExtensionsRGSS3 # 引入 RGSS3 Troop Member 的特定属性和方法

    # 初始化方法，先调用父类(共享 Member)初始化，再调用 Mixin 初始化
    def initialize
      # --- 设置共享属性 ---
      @enemy_id = 1; @x = 0; @y = 0; @hidden = false
      # --- 共享属性结束 ---
      # 调用 Mixin 初始化 (RGSS3 无特殊属性)
      initialize_troop_member_rgss3_specifics
    end

    # Member 没有名称需要解包
  end
end # module RPG
