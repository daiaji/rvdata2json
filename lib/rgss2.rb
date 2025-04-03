# lib/rgss2.rb
# 包含 RGSS2 (RPG Maker VX) 特有的类定义或对共享类的修改

require_relative "shared" # 加载共享定义
require_relative "rgss_extensions" # 加载版本特定扩展

# --- RGSS2 特有类定义 ---
module RPG
  class Area
    attr_accessor :id, :name, :map_id, :rect, :encounter_list, :order

    def unpack_names; Utils.unpack_names_for(self, :name); end
    def initialize; @id = 0; @name = ""; @map_id = 0; @rect = Rect.new; @encounter_list = []; @order = 0; end
  end

  # --- 重打开共享类以适应 RGSS2 ---
  class Actor
    include RPG::ActorExtensionsRGSS2

    def initialize; super(); initialize_actor_rgss2_specifics; end
    def unpack_names; super(); unpack_names_actor_rgss2; end
  end

  class Armor
    include RPG::ArmorExtensionsRGSS2

    def initialize; super(); initialize_armor_rgss2_specifics; end
    def unpack_names; super(); unpack_names_armor_rgss2; end
  end

  class Weapon
    include RPG::WeaponExtensionsRGSS2

    def initialize; super(); initialize_weapon_rgss2_specifics; end
    def unpack_names; super(); unpack_names_weapon_rgss2; end
  end

  class Item
    include RPG::ItemExtensionsRGSS2

    def initialize; super(); initialize_item_rgss2_specifics; @scope = 7; end
    def unpack_names; super(); unpack_names_item_rgss2; end
  end

  class Skill
    include RPG::SkillExtensionsRGSS2

    def initialize; super(); initialize_skill_rgss2_specifics; @scope = 1; end
    def unpack_names; super(); unpack_names_skill_rgss2; end
  end

  class Enemy
    include RPG::EnemyExtensionsRGSS2

    def initialize; super(); initialize_enemy_rgss2_specifics; end
    def unpack_names; super(); unpack_names_enemy_rgss2; end
    class Action; attr_accessor :kind, :basic, :skill_id, :condition_type, :condition_param1, :condition_param2, :rating; def initialize; @kind = 0; @basic = 0; @skill_id = 1; @condition_type = 0; @condition_param1 = 0; @condition_param2 = 0; @rating = 5; end; def skill?; @kind == 1; end; end
    class DropItem; attr_accessor :kind, :item_id, :weapon_id, :armor_id, :denominator; def initialize; @kind = 0; @item_id = 1; @weapon_id = 1; @armor_id = 1; @denominator = 1; end; end
  end

  class State
    include RPG::StateExtensionsRGSS2

    def initialize; super(); initialize_state_rgss2_specifics; end
    def unpack_names; super(); unpack_names_state_rgss2; end
  end

  class Map
    include RPG::MapExtensionsRGSS2

    def initialize(width = 17, height = 13)
      # Manually set shared attributes
      @width = width; @height = height; @scroll_type = 0; @autoplay_bgm = false; @bgm = RPG::BGM.new; @autoplay_bgs = false; @bgs = RPG::BGS.new; @disable_dashing = false; @encounter_step = 30; @parallax_name = ""; @parallax_loop_x = false; @parallax_loop_y = false; @parallax_sx = 0; @parallax_sy = 0; @parallax_show = false; @events = {}
      initialize_map_rgss2_specifics(width, height)
    end

    def unpack_names
      Utils.unpack_names_for(self, :parallax_name) # Shared part
      unpack_names_map_rgss2 # Mixin part
    end
  end

  class System
    include RPG::SystemExtensionsRGSS2

    def initialize
      # Manually set shared attributes
      @game_title = ""; @version_id = 0; @party_members = [1]; @switches = [nil, ""]; @variables = [nil, ""]; @elements = [nil, ""]; @boat = RPG::System::Vehicle.new; @ship = RPG::System::Vehicle.new; @airship = RPG::System::Vehicle.new; @title_bgm = RPG::BGM.new; @battle_bgm = RPG::BGM.new; @battle_end_me = RPG::ME.new; @gameover_me = RPG::ME.new; @test_battlers = []; @test_troop_id = 1; @start_map_id = 1; @start_x = 0; @start_y = 0; @edit_map_id = 1; @magic_number = 0; @battler_name = ""; @battler_hue = 0
      @terms = RPG::System::Terms.new # Instantiate specific Terms
      initialize_system_rgss2_specifics # Call mixin init
    end

    def unpack_names
      Utils.unpack_names_for(self, :game_title, :battler_name) # Shared part
      unpack_names_system_rgss2 # Mixin part (arrays)
      @terms.unpack_names if @terms.respond_to?(:unpack_names) # Terms part
    end

    class Terms; attr_accessor :level, :level_a, :hp, :hp_a, :mp, :mp_a, :atk, :def, :spi, :agi, :weapon, :armor1, :armor2, :armor3, :armor4, :attack, :skill, :guard, :item, :equip, :status, :save, :game_end, :fight, :escape, :new_game, :continue, :shutdown, :to_title, :cancel, :gold; def unpack_names; instance_variables.each { |ivar| value = instance_variable_get(ivar); instance_variable_set(ivar, RPG.unpack_str(value)) if value.is_a?(String) }; end; def initialize; @level = ""; @level_a = ""; @hp = ""; @hp_a = ""; @mp = ""; @mp_a = ""; @atk = ""; @def = ""; @spi = ""; @agi = ""; @weapon = ""; @armor1 = ""; @armor2 = ""; @armor3 = ""; @armor4 = ""; @attack = ""; @skill = ""; @guard = ""; @item = ""; @equip = ""; @status = ""; @save = ""; @game_end = ""; @fight = ""; @escape = ""; @new_game = ""; @continue = ""; @shutdown = ""; @to_title = ""; @cancel = ""; @gold = ""; end; end

    class TestBattler # Reopen shared
      include RPG::SystemTestBattlerExtensionsRGSS2

      def initialize; super(); initialize_system_testbattler_rgss2_specifics; end
    end
  end

  class Animation::Frame # Reopen shared
    include RPG::AnimationFrameExtensionsRGSS2

    def initialize; super(); initialize_animation_frame_rgss2_specifics; end
  end

  class Troop::Member # Reopen shared
    include RPG::TroopMemberExtensionsRGSS2

    def initialize; super(); initialize_troop_member_rgss2_specifics; end
  end

  # Define RGSS2 Class structure (no inheritance from BaseItem)
  class Class
    attr_accessor :id, :name, :position, :weapon_set, :armor_set
    attr_accessor :element_ranks, :state_ranks, :learnings
    attr_accessor :skill_name_valid, :skill_name

    def unpack_names; Utils.unpack_names_for(self, :name, :skill_name); end
    def initialize; @id = 0; @name = ""; @position = 0; @weapon_set = []; @armor_set = []; @element_ranks = Table.new([]); @element_ranks.resize(1); @state_ranks = Table.new([]); @state_ranks.resize(1); @learnings = []; @skill_name_valid = false; @skill_name = ""; end
    class Learning; attr_accessor :level, :skill_id; def initialize; @level = 1; @skill_id = 1; end; end
  end
end # module RPG
