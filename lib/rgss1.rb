# lib/rgss1.rb
# 包含 RGSS1 (RPG Maker XP) 特有的类定义

require_relative "shared" # 加载共享定义 (Table, Color, Tone, Rect, AudioFile etc.)
require_relative "rgss_extensions" # 加载所有版本的扩展 Mixin

module RPG
  # --- RGSS1 Specific Classes ---

  # Note: RGSS1 没有严格的 BaseItem, UsableItem, EquipItem 继承结构
  #       属性直接在具体类中定义，并通过 Mixin 添加

  class Actor
    include RPG::ActorExtensionsRGSS1

    def initialize; initialize_actor_rgss1_specifics; end
    def unpack_names; unpack_names_actor_rgss1; end
  end

  class Class
    include RPG::ClassExtensionsRGSS1

    def initialize; initialize_class_rgss1_specifics; end
    def unpack_names; unpack_names_class_rgss1; end

    # Nested Learning Class for RGSS1
    class Learning; attr_accessor :level, :skill_id; def initialize; @level = 1; @skill_id = 1; end; end
  end

  class Skill
    include RPG::SkillExtensionsRGSS1

    def initialize; initialize_skill_rgss1_specifics; end
    def unpack_names; unpack_names_skill_rgss1; end
  end

  class Item
    include RPG::ItemExtensionsRGSS1

    def initialize; initialize_item_rgss1_specifics; end
    def unpack_names; unpack_names_item_rgss1; end
  end

  class Weapon
    include RPG::WeaponExtensionsRGSS1

    def initialize; initialize_weapon_rgss1_specifics; end
    def unpack_names; unpack_names_weapon_rgss1; end
  end

  class Armor
    include RPG::ArmorExtensionsRGSS1

    def initialize; initialize_armor_rgss1_specifics; end
    def unpack_names; unpack_names_armor_rgss1; end
  end

  class MoveRoute
    attr_accessor :repeat, :skippable, :list

    def initialize
      @repeat = true
      @skippable = false
      @list = [RPG::MoveCommand.new] # RPG::MoveCommand is from shared.rb
    end
  end

  class Enemy
    include RPG::EnemyExtensionsRGSS1

    def initialize; initialize_enemy_rgss1_specifics; end
    def unpack_names; unpack_names_enemy_rgss1; end

    # Nested Action Class for RGSS1
    class Action; attr_accessor :kind, :basic, :skill_id, :condition_turn_a, :condition_turn_b, :condition_hp, :condition_level, :condition_switch_id, :rating; def initialize; @kind = 0; @basic = 0; @skill_id = 1; @condition_turn_a = 0; @condition_turn_b = 1; @condition_hp = 100; @condition_level = 1; @condition_switch_id = 0; @rating = 5; end; end
  end

  class Troop
    attr_accessor :id, :name, :members, :pages # Shared structure

    def initialize; @id = 0; @name = ""; @members = []; @pages = []; end
    def unpack_names; Utils.unpack_names_for(self, :name); @pages&.each { |p| p.unpack_names if p.respond_to?(:unpack_names) }; end # Unpack name and delegate pages

    # Nested Member Class for RGSS1
    class Member
      include RPG::TroopMemberExtensionsRGSS1

      def initialize; initialize_troop_member_rgss1_specifics; end

      # RGSS1 Member has no names to unpack
    end

    # Nested Page Class (Structure differs slightly from RGSS2/3)
    # Using BattleEventPage name as in rmxp_db.rb
    class Page # Aliased as BattleEventPage conceptually in RMXP?
      attr_accessor :condition, :span, :list # Shared structure

      def initialize; @condition = RPG::Troop::Page::Condition.new; @span = 0; @list = [RPG::EventCommand.new]; end
      def unpack_names; @list&.each { |c| c.unpack_names if c.respond_to?(:unpack_names) }; end # Unpack commands

      # Nested Condition Class for RGSS1
      class Condition; attr_accessor :turn_valid, :enemy_valid, :actor_valid, :switch_valid, :turn_a, :turn_b, :enemy_index, :enemy_hp, :actor_id, :actor_hp, :switch_id; def initialize; @turn_valid = false; @enemy_valid = false; @actor_valid = false; @switch_valid = false; @turn_a = 0; @turn_b = 0; @enemy_index = 0; @enemy_hp = 50; @actor_id = 1; @actor_hp = 50; @switch_id = 1; end; end
    end

    # Alias for clarity if needed, though Troop::Page is used internally
    BattleEventPage = Page
  end

  class State
    include RPG::StateExtensionsRGSS1

    def initialize; initialize_state_rgss1_specifics; end
    def unpack_names; unpack_names_state_rgss1; end
  end

  class Animation
    include RPG::AnimationExtensionsRGSS1

    def initialize; initialize_animation_rgss1_specifics; end
    def unpack_names; unpack_names_animation_rgss1; end

    # Nested Frame Class for RGSS1 (Uses Mixin)
    class Frame
      include RPG::AnimationFrameExtensionsRGSS1

      def initialize; initialize_animation_frame_rgss1_specifics; end

      # No names to unpack directly in Frame
    end

    # Nested Timing Class for RGSS1 (Uses Mixin)
    class Timing
      include RPG::AnimationTimingExtensionsRGSS1

      def initialize; initialize_animation_timing_rgss1_specifics; end
      def unpack_names; unpack_names_animation_timing_rgss1; end
    end
  end

  class Tileset
    include RPG::TilesetExtensionsRGSS1

    def initialize; initialize_tileset_rgss1_specifics; end
    def unpack_names; unpack_names_tileset_rgss1; end
  end

  class CommonEvent
    attr_accessor :id, :name, :trigger, :switch_id, :list # Shared structure

    def initialize; @id = 0; @name = ""; @trigger = 0; @switch_id = 1; @list = [RPG::EventCommand.new]; end
    def unpack_names; Utils.unpack_names_for(self, :name); @list&.each { |c| c.unpack_names if c.respond_to?(:unpack_names) }; end

    # autorun? / parallel? methods might differ or not exist, omit for simplicity unless needed
  end

  class System
    include RPG::SystemExtensionsRGSS1

    def initialize; initialize_system_rgss1_specifics; end
    def unpack_names; unpack_names_system_rgss1; end

    # Nested Words Class for RGSS1
    class Words; attr_accessor :gold, :hp, :sp, :str, :dex, :agi, :int, :atk, :pdef, :mdef, :weapon, :armor1, :armor2, :armor3, :armor4, :attack, :skill, :guard, :item, :equip; def initialize; @gold = ""; @hp = ""; @sp = ""; @str = ""; @dex = ""; @agi = ""; @int = ""; @atk = ""; @pdef = ""; @mdef = ""; @weapon = ""; @armor1 = ""; @armor2 = ""; @armor3 = ""; @armor4 = ""; @attack = ""; @skill = ""; @guard = ""; @item = ""; @equip = ""; end; def unpack_names; instance_variables.each { |ivar| value = instance_variable_get(ivar); instance_variable_set(ivar, RPG.unpack_str(value)) if value.is_a?(String) }; end; end

    # Nested TestBattler Class for RGSS1 (Uses Mixin)
    class TestBattler
      include RPG::SystemTestBattlerExtensionsRGSS1

      def initialize; initialize_system_testbattler_rgss1_specifics; end

      # No names to unpack
    end

    # RGSS1 System doesn't have a Vehicle class inside, but uses AudioFile for BGM/ME/SE directly
  end

  class Map
    include RPG::MapExtensionsRGSS1
    # Use shared definition for initialize(width, height)
    def initialize(width = 20, height = 15); initialize_map_rgss1_specifics(width, height); end # Default RMXP size?
    def unpack_names; unpack_names_map_rgss1; @events&.each_value { |e| e.unpack_names if e.respond_to?(:unpack_names) }; end
  end

  class MapInfo
    attr_accessor :name, :parent_id, :order # RGSS1 only has these

    def initialize; @name = ""; @parent_id = 0; @order = 0; end
    def unpack_names; Utils.unpack_names_for(self, :name); end
  end

  class Event
    attr_accessor :id, :name, :x, :y, :pages # Shared structure

    def initialize(x = 0, y = 0); @id = 0; @name = ""; @x = x; @y = y; @pages = [RPG::Event::Page.new]; end
    def unpack_names; Utils.unpack_names_for(self, :name); @pages&.each { |p| p.unpack_names if p.respond_to?(:unpack_names) }; end

    # Nested Page Class for RGSS1
    class Page
      attr_accessor :condition, :graphic, :move_type, :move_speed, :move_frequency, :move_route, :walk_anime, :step_anime, :direction_fix, :through, :always_on_top, :trigger, :list # Shared + always_on_top

      def initialize; @condition = RPG::Event::Page::Condition.new; @graphic = RPG::Event::Page::Graphic.new; @move_type = 0; @move_speed = 3; @move_frequency = 3; @move_route = RPG::MoveRoute.new; @walk_anime = true; @step_anime = false; @direction_fix = false; @through = false; @always_on_top = false; @trigger = 0; @list = [RPG::EventCommand.new]; end
      def unpack_names; @graphic&.unpack_names if @graphic.respond_to?(:unpack_names); @list&.each { |c| c.unpack_names if c.respond_to?(:unpack_names) }; end # Unpack graphic and commands

      # Nested Condition Class for RGSS1
      class Condition; attr_accessor :switch1_valid, :switch2_valid, :variable_valid, :self_switch_valid, :switch1_id, :switch2_id, :variable_id, :variable_value, :self_switch_ch; def initialize; @switch1_valid = false; @switch2_valid = false; @variable_valid = false; @self_switch_valid = false; @switch1_id = 1; @switch2_id = 1; @variable_id = 1; @variable_value = 0; @self_switch_ch = "A"; end; end

      # Nested Graphic Class for RGSS1 (Uses Mixin)
      class Graphic
        include RPG::EventPageGraphicExtensionsRGSS1

        def initialize; initialize_event_page_graphic_rgss1_specifics; end
        def unpack_names; unpack_names_event_page_graphic_rgss1; end
      end
    end
  end
end # module RPG

# Define global AudioFile classes if not already defined in shared
# These are simple wrappers in RGSS1
unless defined?(BGM)
  class BGM < RPG::AudioFile; end
  class BGS < RPG::AudioFile; end
  class ME < RPG::AudioFile; end
  class SE < RPG::AudioFile; end
end
