# 包含 RGSS1 (RPG Maker XP) 特有的类定义

require_relative "shared"         # 加载共享定义 (Table, Color, Tone, Rect, AudioFile 等)
require_relative "rgss_extensions" # 加载所有版本的扩展 Mixin

module RPG
  # --- RGSS1 特定类 ---

  # 注意: RGSS1 没有严格的 BaseItem, UsableItem, EquipItem 继承结构。
  #       属性直接在具体类中定义，并通过 Mixin 添加。

  # -- 角色类 --
  class Actor
    include RPG::ActorExtensionsRGSS1 # 引入 RGSS1 Actor 的特定属性和方法

    # 初始化方法，调用 Mixin 中的特定初始化逻辑
    def initialize; initialize_actor_rgss1_specifics; end

    # 解包名称相关属性 (如 name, character_name) 的方法，调用 Mixin 中的逻辑
    def unpack_names; unpack_names_actor_rgss1; end
  end

  # -- 职业类 --
  class Class
    include RPG::ClassExtensionsRGSS1 # 引入 RGSS1 Class 的特定属性和方法

    # 初始化方法，调用 Mixin 中的特定初始化逻辑
    def initialize; initialize_class_rgss1_specifics; end

    # 解包名称相关属性的方法，调用 Mixin 中的逻辑
    def unpack_names; unpack_names_class_rgss1; end

    # RGSS1 职业的嵌套“学习”类
    class Learning
      attr_accessor :level, :skill_id # 等级, 技能ID

      def initialize; @level = 1; @skill_id = 1; end
    end
  end

  # -- 技能类 --
  class Skill
    include RPG::SkillExtensionsRGSS1 # 引入 RGSS1 Skill 的特定属性和方法

    # 初始化方法，调用 Mixin 中的特定初始化逻辑
    def initialize; initialize_skill_rgss1_specifics; end

    # 解包名称、图标、描述等属性的方法，调用 Mixin 中的逻辑
    def unpack_names; unpack_names_skill_rgss1; end
  end

  # -- 物品类 --
  class Item
    include RPG::ItemExtensionsRGSS1 # 引入 RGSS1 Item 的特定属性和方法

    # 初始化方法，调用 Mixin 中的特定初始化逻辑
    def initialize; initialize_item_rgss1_specifics; end

    # 解包名称、图标、描述等属性的方法，调用 Mixin 中的逻辑
    def unpack_names; unpack_names_item_rgss1; end
  end

  # -- 武器类 --
  class Weapon
    include RPG::WeaponExtensionsRGSS1 # 引入 RGSS1 Weapon 的特定属性和方法

    # 初始化方法，调用 Mixin 中的特定初始化逻辑
    def initialize; initialize_weapon_rgss1_specifics; end

    # 解包名称、图标、描述等属性的方法，调用 Mixin 中的逻辑
    def unpack_names; unpack_names_weapon_rgss1; end
  end

  # -- 护甲类 --
  class Armor
    include RPG::ArmorExtensionsRGSS1 # 引入 RGSS1 Armor 的特定属性和方法

    # 初始化方法，调用 Mixin 中的特定初始化逻辑
    def initialize; initialize_armor_rgss1_specifics; end

    # 解包名称、图标、描述等属性的方法，调用 Mixin 中的逻辑
    def unpack_names; unpack_names_armor_rgss1; end
  end

  # -- 移动路线类 --
  class MoveRoute
    attr_accessor :repeat, :skippable, :list # 是否重复, 是否可跳过, 移动指令列表

    def initialize
      @repeat = true
      @skippable = false
      @list = [RPG::MoveCommand.new] # 移动指令列表，包含一个默认指令 (来自 shared.rb)
    end
  end

  # -- 敌人种类类 --
  class Enemy
    include RPG::EnemyExtensionsRGSS1 # 引入 RGSS1 Enemy 的特定属性和方法

    # 初始化方法，调用 Mixin 中的特定初始化逻辑
    def initialize; initialize_enemy_rgss1_specifics; end

    # 解包名称、战斗图等属性的方法，调用 Mixin 中的逻辑
    def unpack_names; unpack_names_enemy_rgss1; end

    # RGSS1 敌人的嵌套“行动”类
    class Action
      attr_accessor :kind, :basic, :skill_id, :condition_turn_a, :condition_turn_b,
                    :condition_hp, :condition_level, :condition_switch_id, :rating
      # 种类, 基本行动类型, 技能ID, 条件回合A, 条件回合B,
      # 条件HP%, 条件等级, 条件开关ID, 评价

      def initialize
        @kind = 0; @basic = 0; @skill_id = 1; @condition_turn_a = 0; @condition_turn_b = 1
        @condition_hp = 100; @condition_level = 1; @condition_switch_id = 0; @rating = 5
      end
    end
  end

  # -- 敌人队伍类 --
  class Troop
    attr_accessor :id, :name, :members, :pages # ID, 名称, 成员列表, 战斗事件页列表 (共享结构)

    def initialize
      @id = 0; @name = ""; @members = []; @pages = []
    end

    # 解包名称，并递归解包所有页面的内容
    def unpack_names
      Utils.unpack_names_for(self, :name)
      @pages&.each { |p| p.unpack_names if p.respond_to?(:unpack_names) }
    end

    # RGSS1 队伍的嵌套“成员”类
    class Member
      include RPG::TroopMemberExtensionsRGSS1 # 引入 RGSS1 Troop Member 的特定属性和方法

      # 初始化方法，调用 Mixin 中的特定初始化逻辑
      def initialize; initialize_troop_member_rgss1_specifics; end

      # RGSS1 Member 没有需要解包的名称属性
    end

    # RGSS1 队伍的嵌套“页面”类 (战斗事件页)
    # (结构与 RGSS2/3 略有不同)
    class Page # 在 RMXP 编辑器中概念上称为 BattleEventPage
      attr_accessor :condition, :span, :list # 条件, 执行时机, 事件指令列表 (共享结构)

      def initialize
        @condition = RPG::Troop::Page::Condition.new # 条件对象
        @span = 0 # 0: 回合结束, 1: 瞬间, 2: 战斗结束
        @list = [RPG::EventCommand.new] # 事件指令列表
      end

      # 递归解包页面中的事件指令
      def unpack_names
        @list&.each { |c| c.unpack_names if c.respond_to?(:unpack_names) }
      end

      # RGSS1 战斗事件页的嵌套“条件”类
      class Condition
        attr_accessor :turn_valid, :enemy_valid, :actor_valid, :switch_valid,
                      :turn_a, :turn_b, :enemy_index, :enemy_hp,
                      :actor_id, :actor_hp, :switch_id
        # 回合条件有效?, 敌人条件有效?, 角色条件有效?, 开关条件有效?,
        # 回合 A, 回合 B (条件: A + B*X), 敌人索引, 敌人 HP%,
        # 角色 ID, 角色 HP%, 开关 ID

        def initialize
          @turn_valid = false; @enemy_valid = false; @actor_valid = false; @switch_valid = false
          @turn_a = 0; @turn_b = 0; @enemy_index = 0; @enemy_hp = 50
          @actor_id = 1; @actor_hp = 50; @switch_id = 1
        end
      end
    end # Page

    # 为清晰起见设置别名，尽管内部使用 Troop::Page
    BattleEventPage = Page
  end # Troop

  # -- 状态类 --
  class State
    include RPG::StateExtensionsRGSS1 # 引入 RGSS1 State 的特定属性和方法

    # 初始化方法，调用 Mixin 中的特定初始化逻辑
    def initialize; initialize_state_rgss1_specifics; end

    # 解包名称等属性的方法，调用 Mixin 中的逻辑
    def unpack_names; unpack_names_state_rgss1; end
  end

  # -- 动画类 --
  class Animation
    include RPG::AnimationExtensionsRGSS1 # 引入 RGSS1 Animation 的特定属性和方法

    # 初始化方法，调用 Mixin 中的特定初始化逻辑
    def initialize; initialize_animation_rgss1_specifics; end

    # 解包名称、动画文件名等属性的方法，调用 Mixin 中的逻辑
    def unpack_names; unpack_names_animation_rgss1; end

    # RGSS1 动画的嵌套“帧”类 (使用 Mixin)
    class Frame
      include RPG::AnimationFrameExtensionsRGSS1 # 引入 RGSS1 Frame 的特定属性和方法

      # 初始化方法，调用 Mixin 中的特定初始化逻辑
      def initialize; initialize_animation_frame_rgss1_specifics; end

      # Frame 内部没有需要直接解包的名称属性
    end

    # RGSS1 动画的嵌套“时序”类 (使用 Mixin)
    class Timing
      include RPG::AnimationTimingExtensionsRGSS1 # 引入 RGSS1 Timing 的特定属性和方法

      # 初始化方法，调用 Mixin 中的特定初始化逻辑
      def initialize; initialize_animation_timing_rgss1_specifics; end

      # 解包 SE 音效文件名的方法，调用 Mixin 中的逻辑
      def unpack_names; unpack_names_animation_timing_rgss1; end
    end
  end # Animation

  # -- 图块组类 --
  class Tileset
    include RPG::TilesetExtensionsRGSS1 # 引入 RGSS1 Tileset 的特定属性和方法

    # 初始化方法，调用 Mixin 中的特定初始化逻辑
    def initialize; initialize_tileset_rgss1_specifics; end

    # 解包名称、图块文件名、自动图块名等属性的方法，调用 Mixin 中的逻辑
    def unpack_names; unpack_names_tileset_rgss1; end
  end

  # -- 公共事件类 --
  class CommonEvent
    attr_accessor :id, :name, :trigger, :switch_id, :list # ID, 名称, 触发条件, 触发开关ID, 事件指令列表 (共享结构)

    def initialize
      @id = 0; @name = ""; @trigger = 0 # 0:无, 1:自动执行, 2:并行处理
      @switch_id = 1; @list = [RPG::EventCommand.new]
    end

    # 解包名称，并递归解包事件指令列表
    def unpack_names
      Utils.unpack_names_for(self, :name)
      @list&.each { |c| c.unpack_names if c.respond_to?(:unpack_names) }
    end

    # RMXP 的 autorun? / parallel? 方法可能与 VX/Ace 不同或不存在，
    # 为简化起见，除非需要，否则省略。
  end

  # -- 系统设置类 --
  class System
    include RPG::SystemExtensionsRGSS1 # 引入 RGSS1 System 的特定属性和方法

    # 初始化方法，调用 Mixin 中的特定初始化逻辑
    def initialize; initialize_system_rgss1_specifics; end

    # 解包系统设置中各种字符串属性 (窗口皮肤, 标题图, BGM/SE 文件名等) 的方法
    def unpack_names; unpack_names_system_rgss1; end

    # RGSS1 系统设置的嵌套“术语”类
    class Words
      attr_accessor :gold, :hp, :sp, :str, :dex, :agi, :int, :atk, :pdef, :mdef,
                    :weapon, :armor1, :armor2, :armor3, :armor4,
                    :attack, :skill, :guard, :item, :equip
      # 金钱单位, HP, SP, 力量, 灵巧, 速度, 魔力, 攻击力, 物理防御, 魔法防御,
      # 武器, 盾, 头盔, 身体防具, 装饰品,
      # 攻击指令, 特技指令, 防御指令, 物品指令, 装备指令

      def initialize
        # 初始化所有术语为空字符串
        @gold = ""; @hp = ""; @sp = ""; @str = ""; @dex = ""; @agi = ""; @int = ""
        @atk = ""; @pdef = ""; @mdef = ""
        @weapon = ""; @armor1 = ""; @armor2 = ""; @armor3 = ""; @armor4 = ""
        @attack = ""; @skill = ""; @guard = ""; @item = ""; @equip = ""
      end

      # 解包所有术语字符串
      def unpack_names
        instance_variables.each do |ivar|
          value = instance_variable_get(ivar)
          # 如果值是字符串，则使用 RPG.unpack_str 进行解包
          instance_variable_set(ivar, RPG.unpack_str(value)) if value.is_a?(String)
        end
      end
    end # Words

    # RGSS1 系统设置的嵌套“测试战斗者”类 (使用 Mixin)
    class TestBattler
      include RPG::SystemTestBattlerExtensionsRGSS1 # 引入 RGSS1 TestBattler 的特定属性和方法

      # 初始化方法，调用 Mixin 中的特定初始化逻辑
      def initialize; initialize_system_testbattler_rgss1_specifics; end

      # TestBattler 没有需要解包的名称属性
    end

    # 注意: RGSS1 System 内部没有 Vehicle 类，而是直接使用 AudioFile 定义 BGM/ME/SE
  end # System

  # -- 地图类 --
  class Map
    include RPG::MapExtensionsRGSS1 # 引入 RGSS1 Map 的特定属性和方法

    # 使用共享的初始化定义 (但可能有不同的默认尺寸)
    # RMXP 默认地图尺寸是 20x15
    def initialize(width = 20, height = 15)
      initialize_map_rgss1_specifics(width, height) # 调用 Mixin 中的特定初始化逻辑
    end

    # 解包 BGM/BGS 文件名，并递归解包地图事件
    def unpack_names
      unpack_names_map_rgss1 # 调用 Mixin 中的解包逻辑 (处理 BGM/BGS)
      @events&.each_value { |e| e.unpack_names if e.respond_to?(:unpack_names) } # 递归处理事件
    end
  end

  # -- 地图信息类 --
  class MapInfo
    attr_accessor :name, :parent_id, :order # 名称, 父地图ID, 顺序 (RGSS1 只有这几个)
    attr_accessor :expanded, :scroll_x, :scroll_y # 展开状态, 滚动 X, 滚动 Y (在某些 Unpacker 中可能存在)

    def initialize
      @name = ""; @parent_id = 0; @order = 0
      @expanded = false; @scroll_x = 0; @scroll_y = 0 # 初始化可能存在的额外属性
    end

    # 解包地图名称
    def unpack_names
      Utils.unpack_names_for(self, :name)
    end
  end

  # -- 事件类 --
  class Event
    attr_accessor :id, :name, :x, :y, :pages # ID, 名称, X坐标, Y坐标, 事件页列表 (共享结构)

    def initialize(x = 0, y = 0)
      @id = 0; @name = ""; @x = x; @y = y; @pages = [RPG::Event::Page.new]
    end

    # 解包事件名称，并递归解包所有事件页
    def unpack_names
      Utils.unpack_names_for(self, :name)
      @pages&.each { |p| p.unpack_names if p.respond_to?(:unpack_names) }
    end

    # RGSS1 事件的嵌套“页面”类
    class Page
      attr_accessor :condition, :graphic, :move_type, :move_speed, :move_frequency,
                    :move_route, :walk_anime, :step_anime, :direction_fix, :through,
                    :always_on_top, :trigger, :list
      # 条件, 图像, 移动类型, 移动速度, 移动频度,
      # 移动路线, 行走动画, 踏步动画, 固定朝向, 穿透,
      # 总在最上层显示, 触发条件, 事件指令列表 (共享结构 + always_on_top)

      def initialize
        @condition = RPG::Event::Page::Condition.new
        @graphic = RPG::Event::Page::Graphic.new
        @move_type = 0; @move_speed = 3; @move_frequency = 3
        @move_route = RPG::MoveRoute.new
        @walk_anime = true; @step_anime = false; @direction_fix = false
        @through = false; @always_on_top = false # RGSS1 特有
        @trigger = 0; @list = [RPG::EventCommand.new]
      end

      # 解包页面图像的名称，并递归解包事件指令列表
      def unpack_names
        @graphic&.unpack_names if @graphic.respond_to?(:unpack_names)
        @list&.each { |c| c.unpack_names if c.respond_to?(:unpack_names) }
      end

      # RGSS1 事件页的嵌套“条件”类
      class Condition
        attr_accessor :switch1_valid, :switch2_valid, :variable_valid, :self_switch_valid,
                      :switch1_id, :switch2_id, :variable_id, :variable_value,
                      :self_switch_ch
        # 开关1有效?, 开关2有效?, 变量有效?, 独立开关有效?,
        # 开关1 ID, 开关2 ID, 变量 ID, 变量值 (>=),
        # 独立开关字符 ("A", "B", "C", "D")

        def initialize
          @switch1_valid = false; @switch2_valid = false; @variable_valid = false; @self_switch_valid = false
          @switch1_id = 1; @switch2_id = 1; @variable_id = 1; @variable_value = 0
          @self_switch_ch = "A"
        end
      end # Condition

      # RGSS1 事件页的嵌套“图像”类 (使用 Mixin)
      class Graphic
        include RPG::EventPageGraphicExtensionsRGSS1 # 引入 RGSS1 Graphic 的特定属性和方法

        # 初始化方法，调用 Mixin 中的特定初始化逻辑
        def initialize; initialize_event_page_graphic_rgss1_specifics; end

        # 解包角色文件名称的方法，调用 Mixin 中的逻辑
        def unpack_names; unpack_names_event_page_graphic_rgss1; end
      end # Graphic
    end # Page
  end # Event
end # module RPG

# --- 全局音频类定义 ---
# 如果 shared.rb 中没有定义，则定义 RGSS1 风格的简单包装器
# 这些类直接继承自 RPG::AudioFile
unless defined?(BGM)
  class BGM < RPG::AudioFile; end # 背景音乐
  class BGS < RPG::AudioFile; end # 背景音效
  class ME < RPG::AudioFile; end  # 音乐效果
  class SE < RPG::AudioFile; end  # 声音效果
end
