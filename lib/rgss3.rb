# lib/rgss3.rb
# 包含 RGSS3 (RPG Maker VX Ace) 特有的类定义或对共享类的修改

require_relative "shared" # 加载共享定义
require_relative "rgss_extensions" # 加载版本特定扩展

# --- RGSS3 特有类定义或覆盖 ---
module RPG
  class BaseItem; class Feature; attr_accessor :code, :data_id, :value; def initialize(code = 0, data_id = 0, value = 0); @code = code; @data_id = data_id; @value = value; end; end; end
  class UsableItem; class Effect; attr_accessor :code, :data_id, :value1, :value2; def initialize(code = 0, data_id = 0, value1 = 0, value2 = 0); @code = code; @data_id = data_id; @value1 = value1; @value2 = value2; end; end; class Damage; attr_accessor :type, :element_id, :formula, :variance, :critical; def unpack_names; Utils.unpack_names_for(self, :formula); end; def initialize; @type = 0; @element_id = 0; @formula = "0"; @variance = 20; @critical = false; end; end; end

  # --- 重打开共享类以适应 RGSS3 ---
  class Actor
    include RPG::BaseItemExtensionsRGSS3
    include RPG::ActorExtensionsRGSS3

    def initialize; super(); initialize_baseitem_rgss3_specifics; initialize_actor_rgss3_specifics; end
    def unpack_names; super(); unpack_names_actor_rgss3; end
  end

  class Class < RPG::BaseItem
    include RPG::BaseItemExtensionsRGSS3
    include RPG::ClassExtensionsRGSS3

    def initialize
      super(); initialize_baseitem_rgss3_specifics; initialize_class_rgss3_specifics
      @features ||= []; @features.push(RPG::BaseItem::Feature.new(23, 0, 1)); @features.push(RPG::BaseItem::Feature.new(22, 0, 0.95)); @features.push(RPG::BaseItem::Feature.new(22, 1, 0.05)); @features.push(RPG::BaseItem::Feature.new(22, 2, 0.04)); @features.push(RPG::BaseItem::Feature.new(41, 1)); @features.push(RPG::BaseItem::Feature.new(51, 1)); @features.push(RPG::BaseItem::Feature.new(52, 1))
    end

    def unpack_names; super(); unpack_names_class_rgss3; end
    class Learning; attr_accessor :level, :skill_id, :note; def unpack_names; Utils.unpack_names_for(self, :note); end; def initialize; @level = 1; @skill_id = 1; @note = ""; end; end
  end

  class Skill
    include RPG::BaseItemExtensionsRGSS3
    include RPG::UsableItemExtensionsRGSS3
    include RPG::SkillExtensionsRGSS3

    def initialize; super(); initialize_baseitem_rgss3_specifics; initialize_usableitem_rgss3_specifics; initialize_skill_rgss3_specifics; @scope = 1; end
    def unpack_names; super(); unpack_names_usableitem_rgss3; unpack_names_skill_rgss3; end
  end

  class Item
    include RPG::BaseItemExtensionsRGSS3
    include RPG::UsableItemExtensionsRGSS3
    include RPG::ItemExtensionsRGSS3

    def initialize; super(); initialize_baseitem_rgss3_specifics; initialize_usableitem_rgss3_specifics; initialize_item_rgss3_specifics; @scope = 7; end
    def unpack_names; super(); unpack_names_usableitem_rgss3; unpack_names_item_rgss3; end
  end

  class EquipItem < RPG::BaseItem # RGSS3 specific base class
    include RPG::BaseItemExtensionsRGSS3
    include RPG::EquipItemExtensionsRGSS3

    def initialize; super(); initialize_baseitem_rgss3_specifics; initialize_equipitem_rgss3_specifics; end
    def unpack_names; super(); unpack_names_equipitem_rgss3; end
  end

  class Weapon < RPG::EquipItem
    include RPG::WeaponExtensionsRGSS3

    def initialize
      super(); initialize_weapon_rgss3_specifics
      @etype_id = 0; @features ||= []; @features.push(RPG::BaseItem::Feature.new(31, 1, 0)); @features.push(RPG::BaseItem::Feature.new(22, 0, 0))
    end

    def unpack_names; super(); unpack_names_weapon_rgss3; end
  end

  class Armor < RPG::EquipItem
    include RPG::ArmorExtensionsRGSS3

    def initialize
      super(); initialize_armor_rgss3_specifics
      @features ||= []; @features.push(RPG::BaseItem::Feature.new(22, 1, 0))
    end

    def unpack_names; super(); unpack_names_armor_rgss3; end
  end

  class Enemy < RPG::BaseItem
    include RPG::BaseItemExtensionsRGSS3
    include RPG::EnemyExtensionsRGSS3

    def initialize
      super(); initialize_baseitem_rgss3_specifics; initialize_enemy_rgss3_specifics
      @features ||= []; @features.push(RPG::BaseItem::Feature.new(22, 0, 0.95)); @features.push(RPG::BaseItem::Feature.new(22, 1, 0.05)); @features.push(RPG::BaseItem::Feature.new(31, 1, 0))
    end

    def unpack_names; super(); unpack_names_enemy_rgss3; end
    class Action; attr_accessor :skill_id, :condition_type, :condition_param1, :condition_param2, :rating; def initialize; @skill_id = 1; @condition_type = 0; @condition_param1 = 0; @condition_param2 = 0; @rating = 5; end; end
    class DropItem; attr_accessor :kind, :data_id, :denominator; def initialize; @kind = 0; @data_id = 1; @denominator = 1; end; end
  end

  class State < RPG::BaseItem
    include RPG::BaseItemExtensionsRGSS3
    include RPG::StateExtensionsRGSS3

    def initialize; super(); initialize_baseitem_rgss3_specifics; initialize_state_rgss3_specifics; end
    def unpack_names; super(); unpack_names_state_rgss3; end
  end

  class Tileset # RGSS3 specific class
    attr_accessor :id, :mode, :name, :tileset_names, :flags, :note

    def unpack_names; Utils.unpack_names_for(self, :name, :note); @tileset_names&.map! { |n| n.is_a?(String) ? RPG.unpack_str(n) : n }; end
    def initialize; @id = 0; @mode = 1; @name = ""; @tileset_names = Array.new(9) { "" }; @flags = Table.new([]); @flags.resize(8192); @flags[0] = 0x0010; (2048..2815).each { |i| @flags[i] = 0x000F }; (4352..8191).each { |i| @flags[i] = 0x000F }; @note = ""; end
  end

  class Map
    include RPG::MapExtensionsRGSS3

    def initialize(width = 17, height = 13)
      # Manually set shared attributes
      @width = width; @height = height; @scroll_type = 0; @autoplay_bgm = false; @bgm = RPG::BGM.new; @autoplay_bgs = false; @bgs = RPG::BGS.new; @disable_dashing = false; @encounter_step = 30; @parallax_name = ""; @parallax_loop_x = false; @parallax_loop_y = false; @parallax_sx = 0; @parallax_sy = 0; @parallax_show = false; @events = {}
      initialize_map_rgss3_specifics(width, height)
    end

    def unpack_names
      Utils.unpack_names_for(self, :parallax_name) # Shared part
      unpack_names_map_rgss3 # Mixin part
    end

    class Encounter; attr_accessor :troop_id, :weight, :region_set; def initialize; @troop_id = 1; @weight = 10; @region_set = []; end; end
  end

  class System
    include RPG::SystemExtensionsRGSS3

    def initialize
      # Manually set shared attributes
      @game_title = ""; @version_id = 0; @party_members = [1]; @switches = [nil, ""]; @variables = [nil, ""]; @elements = [nil, ""]; @boat = RPG::System::Vehicle.new; @ship = RPG::System::Vehicle.new; @airship = RPG::System::Vehicle.new; @title_bgm = RPG::BGM.new; @battle_bgm = RPG::BGM.new; @battle_end_me = RPG::ME.new; @gameover_me = RPG::ME.new; @test_battlers = []; @test_troop_id = 1; @start_map_id = 1; @start_x = 0; @start_y = 0; @edit_map_id = 1; @magic_number = 0; @battler_name = ""; @battler_hue = 0
      @terms = RPG::System::Terms.new # Instantiate specific Terms
      initialize_system_rgss3_specifics # Call mixin init
    end

    def unpack_names
      Utils.unpack_names_for(self, :game_title, :battler_name) # Shared part
      unpack_names_system_rgss3 # Mixin part (arrays & specific strings)
      @terms.unpack_names if @terms.respond_to?(:unpack_names) # Terms part
    end

    class Terms; attr_accessor :basic, :params, :etypes, :commands; def unpack_names; [:@basic, :@params, :@etypes, :@commands].each { |ivar| array = instance_variable_get(ivar); array&.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item } }; end; def initialize; @basic = Array.new(8) { "" }; @params = Array.new(8) { "" }; @etypes = Array.new(5) { "" }; @commands = Array.new(23) { "" }; end; end

    class TestBattler # Reopen shared
      include RPG::SystemTestBattlerExtensionsRGSS3

      def initialize; super(); initialize_system_testbattler_rgss3_specifics; end
    end
  end

  class Animation::Frame # Reopen shared
    include RPG::AnimationFrameExtensionsRGSS3

    def initialize; super(); initialize_animation_frame_rgss3_specifics; end
  end

  class Troop::Member # Reopen shared
    include RPG::TroopMemberExtensionsRGSS3

    def initialize; super(); initialize_troop_member_rgss3_specifics; end
  end
end # module RPG
