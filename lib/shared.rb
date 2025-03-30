# encoding: utf-8
# rvdata2json/lib/shared.rb
# 包含 RGSS2 和 RGSS3 共用的类定义和基础模块

require "jsonable" # 假设 jsonable gem 提供了 to_json 支持
require_relative "utils"

# --- RPG 模块 ---
module RPG
  # 解包字符串 (委托给 Utils)
  def self.unpack_str(str)
    Utils.unpack_string(str)
  end

  # 打包字符串 (委托给 Utils, RGSS2 会覆盖此方法)
  def self.pack_str(str)
    Utils.pack_string(str)
  end

  # Helper to remove instance variables if they exist
  # (Moved here for easier access, or could be in Utils)
  def self.remove_ivar_if_exists(obj, ivar_symbol)
    obj.remove_instance_variable(ivar_symbol) if obj.instance_variable_defined?(ivar_symbol)
  end
end

# --- 基础数据结构 ---

# 颜色类
class Color
  include Jsonable
  attr_accessor :red, :green, :blue, :alpha

  def initialize(data)
    @red, @green, @blue, @alpha = *data.map(&:to_f)
  end

  def _dump(_limit)
    [@red.to_f, @green.to_f, @blue.to_f, @alpha.to_f].pack("EEEE") # Ensure floats before packing
  end

  def self._load(obj)
    new(obj.unpack("EEEE"))
  end
end

# 表格类
class Table
  include Jsonable
  attr_accessor :num_of_dimensions, :xsize, :ysize, :zsize, :num_of_elements
  attr_reader :elements

  def initialize(data)
    dimensions, x, y, z, count, *elements_array = *data
    @num_of_dimensions = dimensions.to_i
    @xsize = x.to_i
    @ysize = y.to_i
    @zsize = z.to_i
    @num_of_elements = count.to_i
    actual_elements = elements_array.flatten.map(&:to_i)
    if actual_elements.size < @num_of_elements
      actual_elements.fill(0, actual_elements.size, @num_of_elements - actual_elements.size)
    elsif actual_elements.size > @num_of_elements && @num_of_elements >= 0
      actual_elements = actual_elements.slice(0, @num_of_elements)
    end
    @elements = @num_of_elements == 0 ? [] : actual_elements
  end

  def _dump(_limit)
    dump_elements = @elements.map(&:to_i)
    [@num_of_dimensions, @xsize, @ysize, @zsize, @num_of_elements, *dump_elements].pack("VVVVVv*")
  end

  def self._load(obj)
    new(obj.unpack("VVVVVv*"))
  end

  def [](x, y = 0, z = 0)
    index = x + y * @xsize + z * @xsize * @ysize
    return nil if x < 0 || (@num_of_dimensions >= 2 && y < 0) || (@num_of_dimensions >= 3 && z < 0)
    return nil if x >= @xsize || (@num_of_dimensions >= 2 && y >= @ysize) || (@num_of_dimensions >= 3 && z >= @zsize)
    return nil if index < 0 || index >= @num_of_elements
    @elements[index]
  end

  def []=(*args)
    value = args.pop.to_i # Last arg is the value
    case @num_of_dimensions
    when 1
      raise ArgumentError, "1D Table needs 1 index, got #{args.size}" unless args.size == 1
      index = args[0]
      @elements[index] = value if index >= 0 && index < @num_of_elements
    when 2
      raise ArgumentError, "2D Table needs 2 indices, got #{args.size}" unless args.size == 2
      x, y = args
      index = x + y * @xsize
      @elements[index] = value if x >= 0 && x < @xsize && y >= 0 && y < @ysize && index < @num_of_elements
    when 3
      raise ArgumentError, "3D Table needs 3 indices, got #{args.size}" unless args.size == 3
      x, y, z = args
      index = x + y * @xsize + z * @xsize * @ysize
      @elements[index] = value if x >= 0 && x < @xsize && y >= 0 && y < @ysize && z >= 0 && z < @zsize && index < @num_of_elements
    else
      raise "Invalid number of dimensions: #{@num_of_dimensions}"
    end
  end

  def resize(x, y = nil, z = nil)
    @xsize = x.to_i
    if y.nil?
      @num_of_dimensions = 1; @ysize = 1; @zsize = 1
    elsif z.nil?
      @num_of_dimensions = 2; @ysize = y.to_i; @zsize = 1
    else
      @num_of_dimensions = 3; @ysize = y.to_i; @zsize = z.to_i
    end
    raise ArgumentError, "Table dimensions cannot be negative" if @xsize < 0 || @ysize < 0 || @zsize < 0
    @num_of_elements = @xsize * @ysize * @zsize
    @elements = Array.new(@num_of_elements, 0)
    self
  end
end

# 色调类
class Tone
  include Jsonable
  attr_accessor :red, :green, :blue, :gray

  def initialize(data)
    @red, @green, @blue, @gray = *data.map(&:to_f)
  end

  def _dump(_limit)
    [@red.to_f, @green.to_f, @blue.to_f, @gray.to_f].pack("EEEE") # Ensure floats
  end

  def self._load(obj)
    new(obj.unpack("EEEE"))
  end
end

# --- 基础 RPG Maker 类 ---

module RPG
  # 移动路线类
  class MoveRoute
    include Jsonable
    attr_accessor :repeat, :skippable, :wait, :list

    def initialize
      @repeat = true; @skippable = false; @wait = false
      @list = [RPG::MoveCommand.new]
    end
  end

  # 移动指令类
  class MoveCommand
    include Jsonable
    attr_accessor :code, :parameters

    def initialize(code = 0, parameters = [])
      @code = code
      @parameters = parameters # Restorer handles recursive restoration
    end
  end

  # 事件指令类
  class EventCommand
    include Jsonable
    attr_accessor :code, :indent, :parameters

    def unpack_names(rgss_version) # Pass version if needed by specific commands
      return unless @parameters.is_a?(Array)
      @parameters.map! do |param|
        param.is_a?(String) ? RPG.unpack_str(param) : param
      end
    end

    def initialize(code = 0, indent = 0, parameters = [])
      @code = code; @indent = indent; @parameters = parameters
    end
  end

  # 地图信息类
  class MapInfo
    include Jsonable
    attr_accessor :name, :parent_id, :order, :expanded, :scroll_x, :scroll_y

    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name)
    end

    def initialize
      @name = ""; @parent_id = 0; @order = 0
      @expanded = false; @scroll_x = 0; @scroll_y = 0
    end
  end

  # 事件类
  class Event
    include Jsonable
    attr_accessor :id, :name, :x, :y, :pages

    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name)
      # pages are handled recursively by JsonExporter
    end

    def initialize(x = 0, y = 0) # Version not needed here
      @id = 0; @name = ""; @x = x; @y = y
      @pages = [RPG::Event::Page.new]
    end

    class Page
      include Jsonable
      attr_accessor :condition, :graphic, :move_type, :move_speed, :move_frequency, :move_route
      attr_accessor :walk_anime, :step_anime, :direction_fix, :through, :priority_type, :trigger, :list

      def unpack_names(rgss_version)
        # graphic and list are handled recursively by JsonExporter
      end

      def initialize # Version not needed here
        @condition = RPG::Event::Page::Condition.new
        @graphic = RPG::Event::Page::Graphic.new
        @move_type = 0; @move_speed = 3; @move_frequency = 3
        @move_route = RPG::MoveRoute.new
        @walk_anime = true; @step_anime = false; @direction_fix = false; @through = false
        @priority_type = 0; @trigger = 0
        @list = [RPG::EventCommand.new]
      end

      class Condition
        include Jsonable
        attr_accessor :switch1_valid, :switch2_valid, :variable_valid, :self_switch_valid
        attr_accessor :item_valid, :actor_valid # Shared
        attr_accessor :switch1_id, :switch2_id, :variable_id, :variable_value
        attr_accessor :self_switch_ch, :item_id, :actor_id

        def initialize # Version not needed here
          @switch1_valid = false; @switch2_valid = false; @variable_valid = false; @self_switch_valid = false
          @item_valid = false; @actor_valid = false
          @switch1_id = 1; @switch2_id = 1; @variable_id = 1; @variable_value = 0
          @self_switch_ch = "A"; @item_id = 1; @actor_id = 1
        end
      end # Condition

      class Graphic
        include Jsonable
        attr_accessor :tile_id, :character_name, :character_index, :direction, :pattern

        def unpack_names(rgss_version)
          Utils.unpack_names_for(self, :character_name)
        end

        def initialize # Version not needed here
          @tile_id = 0; @character_name = ""; @character_index = 0; @direction = 2; @pattern = 0
        end
      end # Graphic
    end # Page
  end # Event

  # 音频文件基类
  class AudioFile
    include Jsonable
    attr_accessor :name, :volume, :pitch

    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name)
    end

    def initialize(name = "", volume = 100, pitch = 100)
      @name = name.to_s; @volume = volume.to_i; @pitch = pitch.to_i
    end
  end

  # BGM, BGS, ME, SE
  class BGM < RPG::AudioFile
    @@last = RPG::BGM.new
    attr_accessor :pos # RGSS3

    def play(pos = 0); @@last = self.dup rescue self; @pos = pos if respond_to?(:pos=); end
    def replay; play(@pos || 0); end

    def self.stop; @@last = RPG::BGM.new; end
    def self.fade(_time); @@last = RPG::BGM.new; end
    def self.last; @@last; end
  end

  class BGS < RPG::AudioFile
    @@last = RPG::BGS.new
    attr_accessor :pos # RGSS3

    def play(pos = 0); @@last = self.dup rescue self; @pos = pos if respond_to?(:pos=); end
    def replay; play(@pos || 0); end

    def self.stop; @@last = RPG::BGS.new; end
    def self.fade(_time); @@last = RPG::BGS.new; end
    def self.last; @@last; end
  end

  class ME < RPG::AudioFile; def play; end; def self.stop; end; def self.fade(_time); end; end
  class SE < RPG::AudioFile; def play; end; def self.stop; end; end

  # 地图类
  class Map
    include Jsonable
    # Define all possible attributes
    attr_accessor :display_name, :tileset_id, :specify_battleback # RGSS3
    attr_accessor :battleback1_name, :battleback2_name, :note      # RGSS3
    attr_accessor :width, :height, :scroll_type, :autoplay_bgm, :bgm, :autoplay_bgs, :bgs
    attr_accessor :disable_dashing, :encounter_list, :encounter_step, :parallax_name
    attr_accessor :parallax_loop_x, :parallax_loop_y, :parallax_sx, :parallax_sy, :parallax_show
    attr_accessor :data, :events

    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :parallax_name)
      # bgm, bgs, events, encounter_list handled recursively by exporter

      # Version-specific unpacking
      if rgss_version == "RGSS3"
        Utils.unpack_names_for(self, :display_name, :battleback1_name, :battleback2_name, :note)
      else # RGSS2
        # No specific string attributes here beside parallax_name
      end
    end

    def initialize(width = 17, height = 13, rgss_version = "RGSS3")
      # Common defaults
      @width = width; @height = height; @scroll_type = 0
      @autoplay_bgm = false; @bgm = RPG::BGM.new
      @autoplay_bgs = false; @bgs = RPG::BGS.new
      @disable_dashing = false; @encounter_step = 30
      @parallax_name = ""; @parallax_loop_x = false; @parallax_loop_y = false
      @parallax_sx = 0; @parallax_sy = 0; @parallax_show = false
      @events = {} # Always a Hash

      # Version-specific defaults
      if rgss_version == "RGSS3"
        @display_name = ""
        @tileset_id = 1
        @specify_battleback = false
        @battleback1_name = ""
        @battleback2_name = ""
        @note = ""
        # RGSS3 Map data: 4 layers
        @data = Table.new([4, @width, @height, 1, @width * @height * 4])
        @encounter_list = [] # Array of RPG::Map::Encounter
      else # RGSS2
        # Ensure RGSS3 attributes are not present
        @display_name = @tileset_id = @specify_battleback = nil
        @battleback1_name = @battleback2_name = @note = nil
        # RGSS2 Map data: 3 layers
        @data = Table.new([3, @width, @height, 1, @width * @height * 3])
        @encounter_list = [] # Array of simple arrays [troop_id, weight, ???]
      end
    end
  end # Map

  # 基础物品/技能/职业等的基类
  class BaseItem
    include Jsonable
    attr_accessor :id, :name, :icon_index, :description, :note
    attr_accessor :features # RGSS3

    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name, :description, :note)
      # features handled recursively by exporter
    end

    def initialize(rgss_version = "RGSS3")
      @id = 0; @name = ""; @icon_index = 0; @description = ""; @note = ""
      # Initialize based on version
      @features = (rgss_version == "RGSS3") ? [] : nil
    end
  end # BaseItem

  # 可使用物品/技能的基类
  class UsableItem < RPG::BaseItem
    # Define all possible attributes
    attr_accessor :scope, :occasion, :speed, :animation_id # Common
    attr_accessor :common_event_id, :base_damage, :variance, :atk_f, :spi_f # RGSS2
    attr_accessor :physical_attack, :damage_to_mp, :absorb_damage, :ignore_defense # RGSS2
    attr_accessor :element_set, :plus_state_set, :minus_state_set # RGSS2
    attr_accessor :success_rate, :repeats, :tp_gain, :hit_type # RGSS3
    attr_accessor :damage, :effects # RGSS3 (Objects)

    def unpack_names(rgss_version)
      # Parent unpacks common strings
      # damage/effects handled recursively by exporter
      if rgss_version == "RGSS3" && @damage.respond_to?(:unpack_names)
        @damage.unpack_names(rgss_version) # Unpack formula in Damage
      end
    end

    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # Calls BaseItem initialize
      # Common defaults
      @scope = 0; @occasion = 0; @speed = 0; @animation_id = 0

      # Version-specific defaults
      if rgss_version == "RGSS3"
        @success_rate = 100
        @repeats = 1
        @tp_gain = 0
        @hit_type = 0
        @damage = RPG::UsableItem::Damage.new # Must instantiate
        @effects = []
        # Ensure RGSS2 attributes are nil
        @common_event_id = @base_damage = @variance = @atk_f = @spi_f = nil
        @physical_attack = @damage_to_mp = @absorb_damage = @ignore_defense = nil
        @element_set = @plus_state_set = @minus_state_set = nil
      else # RGSS2
        @common_event_id = 0
        @base_damage = 0
        @variance = 20
        @atk_f = 0
        @spi_f = 0
        @physical_attack = false
        @damage_to_mp = false
        @absorb_damage = false
        @ignore_defense = false
        @element_set = []
        @plus_state_set = []
        @minus_state_set = []
        # Ensure RGSS3 attributes are nil
        @success_rate = @repeats = @tp_gain = @hit_type = nil
        @damage = @effects = nil
      end
    end

    # RGSS2 helper methods (Keep them, guarded by check if necessary)
    def for_opponent?; respond_to?(:physical_attack) && [1, 2, 3, 4, 5, 6].include?(@scope); end

    # ... other RGSS2 helpers ...
  end # UsableItem

  # 系统设定类
  class System
    include Jsonable
    # Define all possible attributes
    attr_accessor :japanese, :currency_unit, :skill_types, :weapon_types, :armor_types # RGSS3
    attr_accessor :title1_name, :title2_name, :opt_draw_title, :opt_use_midi, :opt_transparent # RGSS3
    attr_accessor :opt_followers, :opt_slip_death, :opt_floor_death, :opt_display_tp, :opt_extra_exp # RGSS3
    attr_accessor :window_tone, :battleback1_name, :battleback2_name # RGSS3
    attr_accessor :passages # RGSS2 (Maybe)
    attr_accessor :game_title, :version_id, :party_members, :elements, :switches, :variables # Common
    attr_accessor :boat, :ship, :airship, :title_bgm, :battle_bgm, :battle_end_me, :gameover_me # Common
    attr_accessor :sounds, :test_battlers, :test_troop_id, :start_map_id, :start_x, :start_y # Common
    attr_accessor :terms, :battler_name, :battler_hue, :edit_map_id, :magic_number # Common

    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :game_title)
      # boat, ship, airship, bgm, etc., terms, sounds, test_battlers handled recursively

      # Version-specific array/string unpacking
      if rgss_version == "RGSS3"
        Utils.unpack_names_for(self, :currency_unit, :title1_name, :title2_name,
                               :battleback1_name, :battleback2_name, :battler_name)
        [:@elements, :@skill_types, :@weapon_types, :@armor_types, :@switches, :@variables].each do |ivar|
          array = instance_variable_get(ivar)
          array.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item } if array.is_a?(Array)
        end
        # Unpack Terms for RGSS3
        @terms&.unpack_names(rgss_version)
      else # RGSS2
        Utils.unpack_names_for(self, :battler_name)
        [:@elements, :@switches, :@variables].each do |ivar|
          array = instance_variable_get(ivar)
          array.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item } if array.is_a?(Array)
        end
        # Unpack Terms for RGSS2
        @terms&.unpack_names(rgss_version)
      end
    end

    def initialize(rgss_version = "RGSS3")
      # Common defaults
      @game_title = ""; @version_id = 0; @party_members = [1]
      @switches = [nil, ""]; @variables = [nil, ""]
      @boat = RPG::System::Vehicle.new; @ship = RPG::System::Vehicle.new; @airship = RPG::System::Vehicle.new
      @title_bgm = RPG::BGM.new; @battle_bgm = RPG::BGM.new
      @battle_end_me = RPG::ME.new; @gameover_me = RPG::ME.new
      @test_battlers = []; @test_troop_id = 1
      @start_map_id = 1; @start_x = 0; @start_y = 0
      @edit_map_id = 1; @magic_number = 0 # Default, might be overridden

      # Version-specific defaults
      if rgss_version == "RGSS3"
        @japanese = true; @currency_unit = ""
        @skill_types = [nil, ""]; @weapon_types = [nil, ""]; @armor_types = [nil, ""]
        @elements = [nil, ""]
        @title1_name = ""; @title2_name = ""
        @opt_draw_title = true; @opt_use_midi = false; @opt_transparent = false
        @opt_followers = true; @opt_slip_death = false; @opt_floor_death = false
        @opt_display_tp = true; @opt_extra_exp = false
        @window_tone = Tone.new([0.0, 0.0, 0.0, 0.0])
        @sounds = Array.new(24) { RPG::SE.new }
        @terms = RPG::System::Terms.new(rgss_version) # Terms init handles version
        @battleback1_name = ""; @battleback2_name = ""
        @battler_name = ""; @battler_hue = 0
        @magic_number = 1
        @passages = nil # Ensure not present for RGSS3
      else # RGSS2
        @elements = [nil, ""]
        @passages = nil # Usually nil here anyway
        @sounds = Array.new(20) { RPG::SE.new }
        @terms = RPG::System::Terms.new(rgss_version) # Terms init handles version
        @battler_name = ""; @battler_hue = 0
        # Ensure RGSS3 attributes are nil
        @japanese = @currency_unit = @skill_types = @weapon_types = @armor_types = nil
        @title1_name = @title2_name = @opt_draw_title = @opt_use_midi = @opt_transparent = nil
        @opt_followers = @opt_slip_death = @opt_floor_death = @opt_display_tp = @opt_extra_exp = nil
        @window_tone = @battleback1_name = @battleback2_name = nil
      end
    end

    # Nested classes Vehicle, Terms, TestBattler
    class Vehicle
      include Jsonable
      attr_accessor :character_name, :character_index, :bgm, :start_map_id, :start_x, :start_y

      def unpack_names(rgss_version)
        Utils.unpack_names_for(self, :character_name)
        # bgm handled recursively
      end

      def initialize # Version not needed
        @character_name = ""; @character_index = 0; @bgm = RPG::BGM.new
        @start_map_id = 0; @start_x = 0; @start_y = 0
      end
    end # Vehicle

    class Terms
      include Jsonable
      # Define all possible attributes
      attr_accessor :basic, :params, :etypes, :commands # RGSS3
      attr_accessor :level, :level_a, :hp, :hp_a, :mp, :mp_a, :atk, :def, :spi, :agi # RGSS2
      attr_accessor :weapon, :armor1, :armor2, :armor3, :armor4, :weapon1, :weapon2 # RGSS2
      attr_accessor :attack, :skill, :guard, :item, :equip, :status, :save, :game_end # RGSS2
      attr_accessor :fight, :escape, :new_game, :continue, :shutdown, :to_title, :cancel, :gold # RGSS2

      def unpack_names(rgss_version)
        if rgss_version == "RGSS3"
          [:@basic, :@params, :@etypes, :@commands].each do |ivar|
            array = instance_variable_get(ivar)
            array.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item } if array.is_a?(Array)
          end
        else # RGSS2
          instance_variables.each do |ivar|
            # Skip RGSS3 arrays
            next if [:@basic, :@params, :@etypes, :@commands].include?(ivar)
            value = instance_variable_get(ivar)
            instance_variable_set(ivar, RPG.unpack_str(value)) if value.is_a?(String)
          end
        end
      end

      def initialize(rgss_version = "RGSS3")
        if rgss_version == "RGSS3"
          @basic = Array.new(8) { "" }
          @params = Array.new(8) { "" }
          @etypes = Array.new(5) { "" }
          @commands = Array.new(23) { "" }
          # Ensure RGSS2 attributes are nil
          @level = @level_a = @hp = @hp_a = @mp = @mp_a = @atk = @def = @spi = @agi = nil
          @weapon = @armor1 = @armor2 = @armor3 = @armor4 = @weapon1 = @weapon2 = nil
          @attack = @skill = @guard = @item = @equip = @status = @save = @game_end = nil
          @fight = @escape = @new_game = @continue = @shutdown = @to_title = @cancel = @gold = nil
        else # RGSS2
          @level = ""; @level_a = ""; @hp = ""; @hp_a = ""; @mp = ""; @mp_a = ""
          @atk = ""; @def = ""; @spi = ""; @agi = ""
          @weapon = ""; @armor1 = ""; @armor2 = ""; @armor3 = ""; @armor4 = ""
          @weapon1 = ""; @weapon2 = ""
          @attack = ""; @skill = ""; @guard = ""; @item = ""
          @equip = ""; @status = ""; @save = ""; @game_end = ""
          @fight = ""; @escape = ""
          @new_game = ""; @continue = ""; @shutdown = ""
          @to_title = ""; @cancel = ""; @gold = ""
          # Ensure RGSS3 attributes are nil
          @basic = @params = @etypes = @commands = nil
        end
      end
    end # Terms

    class TestBattler
      include Jsonable
      attr_accessor :actor_id, :level
      attr_accessor :equips # RGSS3
      attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id # RGSS2

      def initialize(rgss_version = "RGSS3") # Restorer handles this with version
        @actor_id = 1; @level = 1
        if rgss_version == "RGSS3"
          @equips = [0, 0, 0, 0, 0]
          @weapon_id = @armor1_id = @armor2_id = @armor3_id = @armor4_id = nil
        else # RGSS2
          @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
          @equips = nil
        end
      end
    end # TestBattler
  end # System

  # 动画类
  class Animation
    include Jsonable
    attr_accessor :id, :name, :animation1_name, :animation1_hue, :animation2_name, :animation2_hue
    attr_accessor :position, :frame_max, :frames, :timings

    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name, :animation1_name, :animation2_name)
      # frames and timings handled recursively by exporter
    end

    def initialize # Frame init depends on version, handled by restorer
      @id = 0; @name = ""; @animation1_name = ""; @animation1_hue = 0
      @animation2_name = ""; @animation2_hue = 0; @position = 1; @frame_max = 1
      @frames = []; @timings = [] # Populated by restorer
    end

    class Frame
      include Jsonable
      attr_accessor :cell_max, :cell_data # Type depends on version

      def initialize(rgss_version = "RGSS3") # Restorer handles this with version
        @cell_max = 0
        # Initialize based on version
        @cell_data = (rgss_version == "RGSS3") ? nil : Table.new([2, 0, 0, 1, 0])
      end
    end # Frame

    class Timing
      include Jsonable
      attr_accessor :frame, :se, :flash_scope, :flash_color, :flash_duration

      def unpack_names(rgss_version)
        # se handled recursively by exporter
      end

      def initialize # Version not needed
        @frame = 0; @se = RPG::SE.new("", 80)
        @flash_scope = 0; @flash_color = Color.new([255.0, 255.0, 255.0, 255.0]); @flash_duration = 5
      end
    end # Timing
  end # Animation

  # 公共事件类
  class CommonEvent
    include Jsonable
    attr_accessor :id, :name, :trigger, :switch_id, :list

    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name)
      # list handled recursively by exporter
    end

    def initialize # Version not needed
      @id = 0; @name = ""; @trigger = 0; @switch_id = 1
      @list = [RPG::EventCommand.new]
    end

    def autorun?; @trigger == 1; end
    def parallel?; @trigger == 2; end
  end # CommonEvent

  # 队伍类
  class Troop
    include Jsonable
    attr_accessor :id, :name, :members, :pages

    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name)
      # members and pages handled recursively by exporter
    end

    def initialize # Member init depends on version, handled by restorer
      @id = 0; @name = ""
      @members = []; @pages = [] # Populated by restorer
    end

    class Member
      include Jsonable
      attr_accessor :enemy_id, :x, :y, :hidden
      attr_accessor :immortal # RGSS2

      def initialize(rgss_version = "RGSS3") # Restorer handles this with version
        @enemy_id = 1; @x = 0; @y = 0; @hidden = false
        # Initialize based on version
        @immortal = (rgss_version == "RGSS2") ? false : nil
      end
    end # Member

    class Page
      include Jsonable
      attr_accessor :condition, :span, :list

      def unpack_names(rgss_version)
        # list handled recursively by exporter
      end

      def initialize # Version not needed
        @condition = RPG::Troop::Page::Condition.new
        @span = 0
        @list = [RPG::EventCommand.new]
      end

      class Condition
        include Jsonable
        attr_accessor :turn_ending, :turn_valid, :enemy_valid, :actor_valid, :switch_valid
        attr_accessor :turn_a, :turn_b, :enemy_index, :enemy_hp, :actor_id, :actor_hp, :switch_id

        def initialize # Version not needed
          @turn_ending = false; @turn_valid = false; @enemy_valid = false
          @actor_valid = false; @switch_valid = false
          @turn_a = 0; @turn_b = 0; @enemy_index = 0; @enemy_hp = 50
          @actor_id = 1; @actor_hp = 50; @switch_id = 1
        end
      end # Condition
    end # Page
  end # Troop
end # RPG

# 矩形类
class Rect
  include Jsonable
  attr_accessor :x, :y, :width, :height

  def initialize(x = 0, y = 0, width = 0, height = 0)
    set(x, y, width, height)
  end

  def _dump(_limit)
    [@x.to_i, @y.to_i, @width.to_i, @height.to_i].pack("iiii") # Ensure integers
  end

  def self._load(obj)
    new(*obj.unpack("iiii"))
  end

  def set(x, y, width, height); @x = x.to_i; @y = y.to_i; @width = width.to_i; @height = height.to_i; self; end
  def empty; set(0, 0, 0, 0); end
  def to_s; "(#{@x}, #{@y}, #{@width}, #{@height})"; end
end
