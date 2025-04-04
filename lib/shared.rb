# lib/shared.rb
# 包含 RGSS2 和 RGSS3 共用的类定义和基础模块

require_relative "utils" # 加载通用工具函数

# --- RPG 模块 ---
module RPG
  # 解包字符串 (委托给 Utils.unpack_string)
  def self.unpack_str(str)
    Utils.unpack_string(str)
  end
end

# --- 基础数据结构 ---
class Color
  attr_accessor :red, :green, :blue, :alpha

  def initialize(data)
    d = Array(data) + [0.0] * (4 - Array(data).size)
    @red, @green, @blue, @alpha = *d[0..3].map(&:to_f)
  end

  def _dump(_limit); [@red.to_f, @green.to_f, @blue.to_f, @alpha.to_f].pack("EEEE"); end

  def self._load(obj); new(obj.unpack("EEEE")); end
end

class Table
  attr_accessor :num_of_dimensions, :xsize, :ysize, :zsize, :num_of_elements
  attr_reader :elements

  def initialize(data)
    dimensions, x, y, z, count, *elements_array = *Array(data)
    @num_of_dimensions = dimensions.to_i; @xsize = x.to_i; @ysize = y.to_i; @zsize = z.to_i; @num_of_elements = count.to_i
    actual_elements = elements_array.flatten.map(&:to_i)
    expected_size = [@num_of_elements, 0].max
    if actual_elements.size < expected_size
      actual_elements.fill(0, actual_elements.size, expected_size - actual_elements.size)
    elsif actual_elements.size > expected_size
      actual_elements = actual_elements.slice(0, expected_size)
    end
    @elements = actual_elements
  end

  def _dump(_limit); dump_elements = @elements.map(&:to_i); [@num_of_dimensions, @xsize, @ysize, @zsize, @num_of_elements, *dump_elements].pack("VVVVVv*"); end

  def self._load(obj); new(obj.unpack("VVVVVv*")); end

  def [](x, y = 0, z = 0)
    return nil if @xsize <= 0 && (@num_of_dimensions >= 2 || @num_of_dimensions >= 3)
    return nil if @ysize <= 0 && @num_of_dimensions >= 3
    index = x; index += y * @xsize if @num_of_dimensions >= 2; index += z * @xsize * @ysize if @num_of_dimensions >= 3
    return nil if x < 0 || (@num_of_dimensions >= 2 && y < 0) || (@num_of_dimensions >= 3 && z < 0)
    return nil if x >= @xsize || (@num_of_dimensions >= 2 && y >= @ysize) || (@num_of_dimensions >= 3 && z >= @zsize)
    return nil if index < 0 || index >= @num_of_elements
    @elements[index]
  end

  def []=(*args)
    value = args.pop.to_i; x, y, z = 0, 0, 0
    case @num_of_dimensions
    when 1; raise ArgumentError, "1D Table: expected 1 index, got #{args.size}" unless args.size == 1; x = args[0]
    when 2; raise ArgumentError, "2D Table: expected 2 indices, got #{args.size}" unless args.size == 2; x, y = args
    when 3; raise ArgumentError, "3D Table: expected 3 indices, got #{args.size}" unless args.size == 3; x, y, z = args
    else; return nil     end
    return nil if x < 0 || (@num_of_dimensions >= 2 && y < 0) || (@num_of_dimensions >= 3 && z < 0)
    return nil if x >= @xsize || (@num_of_dimensions >= 2 && y >= @ysize) || (@num_of_dimensions >= 3 && z >= @zsize)
    return nil if @xsize <= 0 && (@num_of_dimensions >= 2 || @num_of_dimensions >= 3)
    return nil if @ysize <= 0 && @num_of_dimensions >= 3
    index = x; index += y * @xsize if @num_of_dimensions >= 2; index += z * @xsize * @ysize if @num_of_dimensions >= 3
    @elements[index] = value if index >= 0 && index < @num_of_elements
  end

  def resize(x, y = nil, z = nil)
    @xsize = x.to_i
    if y.nil?; @num_of_dimensions = 1; @ysize = 1; @zsize = 1 elsif z.nil?; @num_of_dimensions = 2; @ysize = y.to_i; @zsize = 1 else; @num_of_dimensions = 3; @ysize = y.to_i; @zsize = z.to_i end
    raise ArgumentError, "Table dimensions cannot be negative" if @xsize < 0 || @ysize < 0 || @zsize < 0
    @num_of_elements = @xsize * @ysize * @zsize
    @elements = Array.new([@num_of_elements, 0].max, 0)
    self
  end
end

class Tone
  attr_accessor :red, :green, :blue, :gray

  def initialize(data); d = Array(data) + [0.0] * (4 - Array(data).size); @red, @green, @blue, @gray = *d[0..3].map(&:to_f); end
  def _dump(_limit); [@red.to_f, @green.to_f, @blue.to_f, @gray.to_f].pack("EEEE"); end

  def self._load(obj); new(obj.unpack("EEEE")); end
end

class Rect
  attr_accessor :x, :y, :width, :height

  def initialize(x = 0, y = 0, width = 0, height = 0); set(x, y, width, height); end
  def _dump(_limit); [@x.to_i, @y.to_i, @width.to_i, @height.to_i].pack("iiii"); end

  def self._load(obj); new(*obj.unpack("iiii")); end

  def set(x, y, width, height); @x = x.to_i; @y = y.to_i; @width = width.to_i; @height = height.to_i; self; end
  def empty; set(0, 0, 0, 0); end
  def to_s; "(#{@x}, #{@y}, #{@width}, #{@height})"; end
end

# --- 基础 RPG Maker 类 ---

module RPG
  class MoveRoute; attr_accessor :repeat, :skippable, :wait, :list; def initialize; @repeat = true; @skippable = false; @wait = false; @list = [RPG::MoveCommand.new]; end; end
  class MoveCommand; attr_accessor :code, :parameters; def initialize(code = 0, parameters = []); @code = code; @parameters = parameters; end; end
  class EventCommand; attr_accessor :code, :indent, :parameters; def unpack_names; return unless @parameters.is_a?(Array); @parameters.map! { |p| p.is_a?(String) ? RPG.unpack_str(p) : p }; end; def initialize(code = 0, indent = 0, parameters = []); @code = code; @indent = indent; @parameters = parameters; end; end
  class MapInfo; attr_accessor :name, :parent_id, :order, :expanded, :scroll_x, :scroll_y; def unpack_names; Utils.unpack_names_for(self, :name); end; def initialize; @name = ""; @parent_id = 0; @order = 0; @expanded = false; @scroll_x = 0; @scroll_y = 0; end; end
  class Event; attr_accessor :id, :name, :x, :y, :pages; def unpack_names; Utils.unpack_names_for(self, :name); end; def initialize(x = 0, y = 0); @id = 0; @name = ""; @x = x; @y = y; @pages = [RPG::Event::Page.new]; end; class Page; attr_accessor :condition, :graphic, :move_type, :move_speed, :move_frequency, :move_route, :walk_anime, :step_anime, :direction_fix, :through, :priority_type, :trigger, :list; def unpack_names; end; def initialize; @condition = RPG::Event::Page::Condition.new; @graphic = RPG::Event::Page::Graphic.new; @move_type = 0; @move_speed = 3; @move_frequency = 3; @move_route = RPG::MoveRoute.new; @walk_anime = true; @step_anime = false; @direction_fix = false; @through = false; @priority_type = 0; @trigger = 0; @list = [RPG::EventCommand.new]; end; class Condition; attr_accessor :switch1_valid, :switch2_valid, :variable_valid, :self_switch_valid, :item_valid, :actor_valid, :switch1_id, :switch2_id, :variable_id, :variable_value, :self_switch_ch, :item_id, :actor_id; def initialize; @switch1_valid = false; @switch2_valid = false; @variable_valid = false; @self_switch_valid = false; @item_valid = false; @actor_valid = false; @switch1_id = 1; @switch2_id = 1; @variable_id = 1; @variable_value = 0; @self_switch_ch = "A"; @item_id = 1; @actor_id = 1; end; end; class Graphic; attr_accessor :tile_id, :character_name, :character_index, :direction, :pattern; def unpack_names; Utils.unpack_names_for(self, :character_name); end; def initialize; @tile_id = 0; @character_name = ""; @character_index = 0; @direction = 2; @pattern = 0; end; end; end; end
  class AudioFile; attr_accessor :name, :volume, :pitch; def unpack_names; Utils.unpack_names_for(self, :name); end; def initialize(name = "", volume = 100, pitch = 100); @name = name.to_s; @volume = volume.to_i; @pitch = pitch.to_i; end; end
  class BGM < AudioFile; @@last = RPG::BGM.new; attr_accessor :pos; def play(pos = 0); @@last = self.dup rescue self; @pos = pos if respond_to?(:pos=); end; def replay; play(@pos || 0); end; def self.stop; @@last = RPG::BGM.new; end; def self.fade(_time); @@last = RPG::BGM.new; end; def self.last; @@last; end; end
  class BGS < AudioFile; @@last = RPG::BGS.new; attr_accessor :pos; def play(pos = 0); @@last = self.dup rescue self; @pos = pos if respond_to?(:pos=); end; def replay; play(@pos || 0); end; def self.stop; @@last = RPG::BGS.new; end; def self.fade(_time); @@last = RPG::BGS.new; end; def self.last; @@last; end; end
  class ME < AudioFile; def play; end; def self.stop; end; def self.fade(_time); end; end
  class SE < AudioFile; def play; end; def self.stop; end; end

  class Map; end # Base definition for Map, reopened in rgssX.rb

  class BaseItem; attr_accessor :id, :name, :icon_index, :description, :note; def unpack_names; Utils.unpack_names_for(self, :name, :description, :note); end; def initialize; @id = 0; @name = ""; @icon_index = 0; @description = ""; @note = ""; end; end
  class UsableItem < RPG::BaseItem; attr_accessor :scope, :occasion, :speed, :animation_id; def unpack_names; super(); end; def initialize; super(); @scope = 0; @occasion = 0; @speed = 0; @animation_id = 0; end; end

  class System; end # Base definition for System, reopened below and in rgssX.rb

  # Reopen System class to define nested shared classes AND add shared accessors
  class System
    # Define SHARED accessors here
    attr_accessor :game_title, :version_id, :party_members, :elements, :switches, :variables
    attr_accessor :boat, :ship, :airship, :title_bgm, :battle_bgm, :battle_end_me, :gameover_me
    attr_accessor :sounds, :test_battlers, :test_troop_id, :start_map_id, :start_x, :start_y
    attr_accessor :terms # Terms object itself is shared structure placeholder
    attr_accessor :battler_name, :battler_hue, :edit_map_id
    # Version-specific accessors are added via Mixins in rgssX.rb

    # Define nested shared classes
    class Vehicle
      attr_accessor :character_name, :character_index, :bgm, :start_map_id, :start_x, :start_y

      def unpack_names; Utils.unpack_names_for(self, :character_name); end
      def initialize; @character_name = ""; @character_index = 0; @bgm = RPG::BGM.new; @start_map_id = 0; @start_x = 0; @start_y = 0; end
    end

    class TestBattler
      attr_accessor :actor_id, :level
      # Version-specific accessors are added via Mixins in rgssX.rb
      def initialize; @actor_id = 1; @level = 1; end
    end

    # Define placeholder for Terms class which is fully defined in rgssX.rb
    class Terms; end

    # NOTE: Shared initialize logic is now handled within rgssX.rb initialize methods
    # NOTE: Shared unpack logic is now handled within rgssX.rb unpack_names methods
  end # System reopening

  class Animation; attr_accessor :id, :name, :animation1_name, :animation1_hue, :animation2_name, :animation2_hue, :position, :frame_max, :frames, :timings; def unpack_names; Utils.unpack_names_for(self, :name, :animation1_name, :animation2_name); end; def initialize; @id = 0; @name = ""; @animation1_name = ""; @animation1_hue = 0; @animation2_name = ""; @animation2_hue = 0; @position = 1; @frame_max = 1; @frames = []; @timings = []; end
    
 # Revert Frame initialize back to original (no args)
    class Frame; attr_accessor :cell_max; def initialize; @cell_max = 0; end; end
    class Timing; attr_accessor :frame, :se, :flash_scope, :flash_color, :flash_duration; def unpack_names; end; def initialize; @frame = 0; @se = RPG::SE.new("", 80); @flash_scope = 0; @flash_color = Color.new([255.0, 255.0, 255.0, 255.0]); @flash_duration = 5; end; end;   end

  class CommonEvent; attr_accessor :id, :name, :trigger, :switch_id, :list; def unpack_names; Utils.unpack_names_for(self, :name); end; def initialize; @id = 0; @name = ""; @trigger = 0; @switch_id = 1; @list = [RPG::EventCommand.new]; end; def autorun?; @trigger == 1; end; def parallel?; @trigger == 2; end; end

  class Troop; attr_accessor :id, :name, :members, :pages; def unpack_names; Utils.unpack_names_for(self, :name); end; def initialize; @id = 0; @name = ""; @members = []; @pages = []; end; class Member; attr_accessor :enemy_id, :x, :y, :hidden; def initialize; @enemy_id = 1; @x = 0; @y = 0; @hidden = false; end; end; class Page; attr_accessor :condition, :span, :list; def unpack_names; end; def initialize; @condition = RPG::Troop::Page::Condition.new; @span = 0; @list = [RPG::EventCommand.new]; end; class Condition; attr_accessor :turn_ending, :turn_valid, :enemy_valid, :actor_valid, :switch_valid, :turn_a, :turn_b, :enemy_index, :enemy_hp, :actor_id, :actor_hp, :switch_id; def initialize; @turn_ending = false; @turn_valid = false; @enemy_valid = false; @actor_valid = false; @switch_valid = false; @turn_a = 0; @turn_b = 0; @enemy_index = 0; @enemy_hp = 50; @actor_id = 1; @actor_hp = 50; @switch_id = 1; end; end; end; end
end # RPG
