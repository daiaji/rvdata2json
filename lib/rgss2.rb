# lib/rgss2.rb
# 包含 RGSS2 (RPG Maker VX) 特有的类定义或对共享类的修改
# 修正: RPG::Animation::Frame#initialize 添加 super() 调用

require_relative "shared" # 加载共享定义
require_relative "rgss_extensions" # 加载版本特定扩展

# --- RGSS2 特有类定义 ---
module RPG
  class Area
    # (保持不变)
    attr_accessor :id, :name, :map_id, :rect, :encounter_list, :order

    def unpack_names; Utils.unpack_names_for(self, :name); end
    def initialize; @id = 0; @name = ""; @map_id = 0; @rect = Rect.new; @encounter_list = []; @order = 0; end
  end

  # --- RGSS2 类定义 (不再继承 BaseItem) ---
  class Actor # Removed < RPG::BaseItem
    include RPG::ActorExtensionsRGSS2

    def initialize; initialize_actor_rgss2_specifics; end # Removed super()
    def unpack_names; unpack_names_actor_rgss2; end # Removed super()
  end

  class Armor < RPG::BaseItem # Armor 仍然继承 BaseItem
    include RPG::ArmorExtensionsRGSS2

    def initialize; super(); initialize_armor_rgss2_specifics; end
    def unpack_names; super(); unpack_names_armor_rgss2; end
  end

  class Weapon < RPG::BaseItem # Weapon 仍然继承 BaseItem
    include RPG::WeaponExtensionsRGSS2

    def initialize; super(); initialize_weapon_rgss2_specifics; end
    def unpack_names; super(); unpack_names_weapon_rgss2; end
  end

  class Item < RPG::UsableItem # Item 仍然继承 UsableItem
    include RPG::UsableItemExtensionsRGSS2
    include RPG::ItemExtensionsRGSS2

    def initialize; super(); initialize_item_rgss2_specifics; @scope = 7; end
    def unpack_names; super(); unpack_names_item_rgss2; end
  end

  class Skill < RPG::UsableItem # Skill 仍然继承 UsableItem
    include RPG::UsableItemExtensionsRGSS2
    include RPG::SkillExtensionsRGSS2

    def initialize; super(); initialize_skill_rgss2_specifics; @scope = 1; end
    def unpack_names; super(); unpack_names_skill_rgss2; end
  end

  class Enemy # Removed < RPG::BaseItem
    include RPG::EnemyExtensionsRGSS2

    def initialize; initialize_enemy_rgss2_specifics; end # Removed super()
    def unpack_names; unpack_names_enemy_rgss2; end # Removed super()
    # Nested classes (保持不变)
    class Action; attr_accessor :kind, :basic, :skill_id, :condition_type, :condition_param1, :condition_param2, :rating; def initialize; @kind = 0; @basic = 0; @skill_id = 1; @condition_type = 0; @condition_param1 = 0; @condition_param2 = 0; @rating = 5; end; def skill?; @kind == 1; end; end
    class DropItem; attr_accessor :kind, :item_id, :weapon_id, :armor_id, :denominator; def initialize; @kind = 0; @item_id = 1; @weapon_id = 1; @armor_id = 1; @denominator = 1; end; end
  end

  class MoveRoute
    attr_accessor :repeat, :skippable, :wait, :list

    def initialize
      @repeat = true
      @skippable = false
      @wait = false # RGSS2 includes wait
      @list = [RPG::MoveCommand.new] # RPG::MoveCommand is from shared.rb
    end
  end

  class State # Removed < RPG::BaseItem
    include RPG::StateExtensionsRGSS2

    def initialize; initialize_state_rgss2_specifics; end # Removed super()
    def unpack_names; unpack_names_state_rgss2; end # Removed super()
  end

  # RGSS2 Class structure (保持不变)
  class Class
    attr_accessor :id, :name, :position, :weapon_set, :armor_set, :element_ranks, :state_ranks, :learnings, :skill_name_valid, :skill_name

    def unpack_names; Utils.unpack_names_for(self, :name, :skill_name); end
    def initialize; @id = 0; @name = ""; @position = 0; @weapon_set = []; @armor_set = []; @element_ranks = Table.new([]); @element_ranks.resize(1); @state_ranks = Table.new([]); @state_ranks.resize(1); @learnings = []; @skill_name_valid = false; @skill_name = ""; end
    class Learning; attr_accessor :level, :skill_id; def initialize; @level = 1; @skill_id = 1; end; end
  end

  # Reopen RPG::Map (保持不变)
  class Map
    include RPG::MapExtensionsRGSS2

    def initialize(width = 17, height = 13); @width = width; @height = height; @scroll_type = 0; @autoplay_bgm = false; @bgm = RPG::BGM.new; @autoplay_bgs = false; @bgs = RPG::BGS.new; @disable_dashing = false; @encounter_step = 30; @parallax_name = ""; @parallax_loop_x = false; @parallax_loop_y = false; @parallax_sx = 0; @parallax_sy = 0; @parallax_show = false; @events = {}; initialize_map_rgss2_specifics(width, height); end
    def unpack_names; Utils.unpack_names_for(self, :parallax_name); unpack_names_map_rgss2; end
  end

  # Reopen RPG::System (保持不变)
  class System
    include RPG::SystemExtensionsRGSS2

    def initialize; @game_title = ""; @version_id = 0; @party_members = [1]; @elements = [nil, ""]; @switches = [nil, ""]; @variables = [nil, ""]; @boat = RPG::System::Vehicle.new; @ship = RPG::System::Vehicle.new; @airship = RPG::System::Vehicle.new; @title_bgm = RPG::BGM.new; @battle_bgm = RPG::BGM.new; @battle_end_me = RPG::ME.new; @gameover_me = RPG::ME.new; @sounds = []; @test_battlers = []; @test_troop_id = 1; @start_map_id = 1; @start_x = 0; @start_y = 0; @terms = nil; @battler_name = ""; @battler_hue = 0; @edit_map_id = 1; @terms = RPG::System::Terms.new; initialize_system_rgss2_specifics; end
    def unpack_names; Utils.unpack_names_for(self, :game_title, :battler_name); unpack_names_system_rgss2; @terms.unpack_names if @terms.respond_to?(:unpack_names); end

    # Nested classes (保持不变)
    class Terms; attr_accessor :level, :level_a, :hp, :hp_a, :mp, :mp_a, :atk, :def, :spi, :agi, :weapon, :armor1, :armor2, :armor3, :armor4, :weapon1, :weapon2, :attack, :skill, :guard, :item, :equip, :status, :save, :game_end, :fight, :escape, :new_game, :continue, :shutdown, :to_title, :cancel, :gold; def unpack_names; instance_variables.each { |ivar| value = instance_variable_get(ivar); instance_variable_set(ivar, RPG.unpack_str(value)) if value.is_a?(String) }; end; def initialize; @level = ""; @level_a = ""; @hp = ""; @hp_a = ""; @mp = ""; @mp_a = ""; @atk = ""; @def = ""; @spi = ""; @agi = ""; @weapon = ""; @armor1 = ""; @armor2 = ""; @armor3 = ""; @armor4 = ""; @weapon1 = ""; @weapon2 = ""; @attack = ""; @skill = ""; @guard = ""; @item = ""; @equip = ""; @status = ""; @save = ""; @game_end = ""; @fight = ""; @escape = ""; @new_game = ""; @continue = ""; @shutdown = ""; @to_title = ""; @cancel = ""; @gold = ""; end; end
    class TestBattler; include RPG::SystemTestBattlerExtensionsRGSS2; def initialize; @actor_id = 1; @level = 1; initialize_system_testbattler_rgss2_specifics; end; end
  end

  # Reopen RPG::Animation::Frame
  class Animation::Frame
    include RPG::AnimationFrameExtensionsRGSS2
    # 修正: 添加 super() 调用
    def initialize; super(); initialize_animation_frame_rgss2_specifics; end
  end

  # Reopen RPG::Troop::Member (保持不变)
  class Troop::Member
    include RPG::TroopMemberExtensionsRGSS2

    def initialize; @enemy_id = 1; @x = 0; @y = 0; @hidden = false; initialize_troop_member_rgss2_specifics; end
  end
end # module RPG
