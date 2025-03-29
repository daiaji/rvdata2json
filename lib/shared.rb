# encoding: utf-8
# rvdata2json/lib/shared.rb
# 包含 RGSS2 和 RGSS3 共用的类定义和基础模块

require "jsonable" # 假设 jsonable gem 提供了 to_json 支持
require_relative "utils"

# --- RPG 模块 ---
module RPG
  # 解包字符串 (委托给 Utils)
  # @param str [String]
  # @return [String]
  def self.unpack_str(str)
    Utils.unpack_string(str)
  end

  # 打包字符串 (委托给 Utils, RGSS2 会覆盖此方法)
  # @param str [String]
  # @return [String]
  def self.pack_str(str)
    Utils.pack_string(str)
  end
end

# --- 基础数据结构 ---

# 颜色类
class Color
  include Jsonable
  attr_accessor :red, :green, :blue, :alpha

  # @param data [Array<Float>] 包含红、绿、蓝、透明度四个值的数组
  def initialize(data)
    @red, @green, @blue, @alpha = *data.map(&:to_f) # 确保是浮点数
  end

  # Marshal dump 实现
  def _dump(_limit)
    [@red, @green, @blue, @alpha].pack("EEEE") # E = double-precision float, little-endian
  end

  # Marshal load 实现
  def self._load(obj)
    new(obj.unpack("EEEE"))
  end
end

# 表格类 (用于地图数据、图块集标志等)
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
    @elements = elements_array.map(&:to_i).fill(0, elements_array.size, @num_of_elements - elements_array.size)
  end

  def _dump(_limit)
    [@num_of_dimensions,
     @xsize, @ysize, @zsize,
     @num_of_elements,
    *@elements].pack("VVVVVv*")
  end

  def self._load(obj)
    new(obj.unpack("VVVVVv*"))
  end

  def [](x, y = 0, z = 0)
    index = x + y * @xsize + z * @xsize * @ysize
    (@num_of_dimensions >= 1 && x >= 0 && x < @xsize &&
     (@num_of_dimensions == 1 || (y >= 0 && y < @ysize)) &&
     (@num_of_dimensions <= 2 || (z >= 0 && z < @zsize)) &&
     index >= 0 && index < @num_of_elements) ? @elements[index] : nil
  end

  # --- 修改 Table#[]= 方法 ---
  def []=(*args)
    # args 会包含所有传递的参数，例如 [index, value] 或 [x, y, value] 或 [x, y, z, value]
    case @num_of_dimensions
    when 1
      # 处理 1D 情况: table[index] = value
      unless args.length == 2
        raise ArgumentError, "wrong number of arguments for 1D Table#[]= (given #{args.length}, expected 2: index, value)"
      end
      index, val = args
      if index >= 0 && index < @num_of_elements
        @elements[index] = val.to_i
      else
        warn "Table (1D): Index #{index} out of bounds (0..#{@num_of_elements - 1}) for assignment."
      end
    when 2
      # 处理 2D 情况: table[x, y] = value
      unless args.length == 3
        raise ArgumentError, "wrong number of arguments for 2D Table#[]= (given #{args.length}, expected 3: x, y, value)"
      end
      x, y, val = args
      index = x + y * @xsize
      if x >= 0 && x < @xsize && y >= 0 && y < @ysize && index >= 0 && index < @num_of_elements # 增加 index 检查
        @elements[index] = val.to_i
      else
        warn "Table (2D): Index (#{x}, #{y}) out of bounds (x: 0..#{@xsize - 1}, y: 0..#{@ysize - 1}) for assignment."
      end
    when 3
      # 处理 3D 情况: table[x, y, z] = value
      unless args.length == 4
        raise ArgumentError, "wrong number of arguments for 3D Table#[]= (given #{args.length}, expected 4: x, y, z, value)"
      end
      x, y, z, val = args
      index = x + y * @xsize + z * @xsize * @ysize
      if x >= 0 && x < @xsize && y >= 0 && y < @ysize && z >= 0 && z < @zsize && index >= 0 && index < @num_of_elements # 增加 index 检查
        @elements[index] = val.to_i
      else
        warn "Table (3D): Index (#{x}, #{y}, #{z}) out of bounds (x: 0..#{@xsize - 1}, y: 0..#{@ysize - 1}, z: 0..#{@zsize - 1}) for assignment."
      end
    else
      raise "Table: Invalid number of dimensions (#{@num_of_dimensions}) for assignment."
    end
  end

  # --- 修改结束 ---

  def resize(x, y = nil, z = nil)
    @xsize = x.to_i
    if y.nil?
      @num_of_dimensions = 1
      @ysize = 1
      @zsize = 1
    elsif z.nil?
      @num_of_dimensions = 2
      @ysize = y.to_i
      @zsize = 1
    else
      @num_of_dimensions = 3
      @ysize = y.to_i
      @zsize = z.to_i
    end
    @num_of_elements = @xsize * @ysize * @zsize
    # 检查负数尺寸
    if @xsize < 0 || @ysize < 0 || @zsize < 0 || @num_of_elements < 0
      raise ArgumentError, "Table dimensions cannot be negative (x:#{@xsize}, y:#{@ysize}, z:#{@zsize})"
    end
    @elements = Array.new(@num_of_elements, 0)
    self
  end
end

# 色调类
class Tone
  include Jsonable
  attr_accessor :red, :green, :blue, :gray

  # @param data [Array<Float>] 包含红、绿、蓝、灰度四个值的数组
  def initialize(data)
    @red, @green, @blue, @gray = *data.map(&:to_f) # 确保是浮点数
  end

  # Marshal dump 实现
  def _dump(_limit)
    [@red, @green, @blue, @gray].pack("EEEE")
  end

  # Marshal load 实现
  def self._load(obj)
    new(obj.unpack("EEEE"))
  end
end

# --- 基础 RPG Maker 类 ---

# 移动路线类 (RGSS2/3 结构相同)
module RPG
  class MoveRoute
    include Jsonable
    attr_accessor :repeat, :skippable, :wait, :list

    def initialize
      @repeat = true
      @skippable = false
      @wait = false
      @list = [RPG::MoveCommand.new]
    end
  end

  # 移动指令类 (RGSS2/3 结构相同)
  class MoveCommand
    include Jsonable
    attr_accessor :code, :parameters

    def initialize(code = 0, parameters = [])
      @code = code
      @parameters = parameters # 参数在恢复时会被递归处理
    end
  end

  # 事件指令类 (RGSS2/3 结构相同，但参数内容可能不同)
  class EventCommand
    include Jsonable
    attr_accessor :code, :indent, :parameters

    # 解包参数中的字符串 (由 Converter::JsonExporter 处理)
    def unpack_names
      return unless @parameters.is_a?(Array)
      @parameters.map! do |param|
        param.is_a?(String) ? RPG.unpack_str(param) : param
      end
    end

    def initialize(code = 0, indent = 0, parameters = [])
      @code = code
      @indent = indent
      @parameters = parameters # 参数在恢复时会被递归处理
    end
  end

  # 地图信息类 (RGSS2/3 结构相同)
  class MapInfo
    include Jsonable
    attr_accessor :name, :parent_id, :order, :expanded, :scroll_x, :scroll_y

    # 解包地图名称 (由 Converter::JsonExporter 处理)
    def unpack_names
      Utils.unpack_names_for(self, :name)
    end

    def initialize
      @name = ""
      @parent_id = 0
      @order = 0
      @expanded = false
      @scroll_x = 0
      @scroll_y = 0
    end
  end

  # 事件类
  class Event
    include Jsonable
    attr_accessor :id, :name, :x, :y, :pages

    # 解包事件名称，并递归调用 Page (由 Converter::JsonExporter 处理)
    def unpack_names
      Utils.unpack_names_for(self, :name)
      @pages.each { |page| page.unpack_names if page.respond_to?(:unpack_names) }
    end

    # (x, y) 在恢复时通过特定实例化逻辑设置
    def initialize(x = 0, y = 0)
      @id = 0
      @name = ""
      @x = x
      @y = y
      @pages = [RPG::Event::Page.new] # Page 初始化不需版本
    end

    class Page # 嵌套 Page 类
      include Jsonable
      attr_accessor :condition, :graphic, :move_type, :move_speed, :move_frequency, :move_route
      attr_accessor :walk_anime, :step_anime, :direction_fix, :through, :priority_type, :trigger, :list

      # 解包 Graphic 和 List (由 Converter::JsonExporter 处理)
      def unpack_names
        @graphic&.unpack_names if @graphic.respond_to?(:unpack_names)
        @list.each { |command| command.unpack_names if command.respond_to?(:unpack_names) }
      end

      def initialize
        @condition = RPG::Event::Page::Condition.new # Condition 初始化不需版本
        @graphic = RPG::Event::Page::Graphic.new   # Graphic 初始化不需版本
        @move_type = 0
        @move_speed = 3
        @move_frequency = 3
        @move_route = RPG::MoveRoute.new
        @walk_anime = true
        @step_anime = false
        @direction_fix = false
        @through = false
        @priority_type = 0
        @trigger = 0
        @list = [RPG::EventCommand.new]
      end

      class Condition # 嵌套 Condition 类
        include Jsonable
        attr_accessor :switch1_valid, :switch2_valid, :variable_valid, :self_switch_valid
        attr_accessor :item_valid, :actor_valid # 保留 RGSS2/3 共同属性
        attr_accessor :switch1_id, :switch2_id, :variable_id, :variable_value
        attr_accessor :self_switch_ch, :item_id, :actor_id

        def initialize
          @switch1_valid = false
          @switch2_valid = false
          @variable_valid = false
          @self_switch_valid = false
          @item_valid = false
          @actor_valid = false
          @switch1_id = 1
          @switch2_id = 1
          @variable_id = 1
          @variable_value = 0
          @self_switch_ch = "A"
          @item_id = 1
          @actor_id = 1
        end
      end # Condition

      class Graphic # 嵌套 Graphic 类
        include Jsonable
        attr_accessor :tile_id, :character_name, :character_index, :direction, :pattern

        # 解包角色名称 (由 Converter::JsonExporter 处理)
        def unpack_names
          Utils.unpack_names_for(self, :character_name)
        end

        def initialize
          @tile_id = 0
          @character_name = ""
          @character_index = 0
          @direction = 2
          @pattern = 0
        end
      end # Graphic
    end # Page
  end # Event

  # 音频文件基类
  class AudioFile
    include Jsonable
    attr_accessor :name, :volume, :pitch

    # 解包音频文件名 (由 Converter::JsonExporter 处理)
    def unpack_names
      Utils.unpack_names_for(self, :name)
    end

    def initialize(name = "", volume = 100, pitch = 100)
      @name = name.to_s
      @volume = volume.to_i
      @pitch = pitch.to_i
    end
  end

  # 背景音乐类
  class BGM < RPG::AudioFile
    @@last = RPG::BGM.new
    attr_accessor :pos # 播放位置 (RGSS3)

    def play(pos = 0)
      # 播放逻辑依赖运行时 Audio 模块，转换器不执行
      @@last = self.dup rescue self
      @pos = pos if respond_to?(:pos=)
    end

    def replay; play(@pos || 0); end

    def self.stop; @@last = RPG::BGM.new; end
    def self.fade(_time); @@last = RPG::BGM.new; end
    def self.last; @@last; end
  end

  # 背景音效类
  class BGS < RPG::AudioFile
    @@last = RPG::BGS.new
    attr_accessor :pos # 播放位置 (RGSS3)

    def play(pos = 0)
      @@last = self.dup rescue self
      @pos = pos if respond_to?(:pos=)
    end

    def replay; play(@pos || 0); end

    def self.stop; @@last = RPG::BGS.new; end
    def self.fade(_time); @@last = RPG::BGS.new; end
    def self.last; @@last; end
  end

  # 音乐效果类
  class ME < RPG::AudioFile
    def play; end # 转换器不执行

    def self.stop; end
    def self.fade(_time); end
  end

  # 音效类
  class SE < RPG::AudioFile
    def play; end # 转换器不执行

    def self.stop; end
  end

  # 地图类 (定义在 shared，但初始化和解包依赖版本)
  class Map
    include Jsonable
    # RGSS3 特有
    attr_accessor :display_name, :tileset_id, :specify_battleback
    attr_accessor :battleback1_name, :battleback2_name, :note
    # 通用
    attr_accessor :width, :height, :scroll_type, :autoplay_bgm, :bgm, :autoplay_bgs, :bgs
    attr_accessor :disable_dashing, :encounter_list, :encounter_step, :parallax_name
    attr_accessor :parallax_loop_x, :parallax_loop_y, :parallax_sx, :parallax_sy, :parallax_show
    attr_accessor :data # 类型依赖版本
    attr_accessor :events

    # 解包名称等，行为依赖版本 (由 Converter::JsonExporter 处理)
    def unpack_names(rgss_version)
      @bgm&.unpack_names
      @bgs&.unpack_names
      Utils.unpack_names_for(self, :parallax_name)

      if rgss_version == "RGSS3"
        Utils.unpack_names_for(self, :display_name, :battleback1_name, :battleback2_name, :note) # RGSS3 有 note
        # RGSS3 的 encounter_list 可能是 Encounter 对象，也需要递归处理
        @encounter_list.each { |enc| enc.unpack_names if enc.respond_to?(:unpack_names) }
        # RGSS3 的 events 不需要递归，因为 page/command 的 unpack 会被调用
      else # RGSS2
        Utils.unpack_names_for(self, :note) if respond_to?(:note) # RGSS2 可能有脚本添加 note
        @events&.each_value { |event| event.unpack_names if event.respond_to?(:unpack_names) }
      end
    end

    # 初始化依赖版本 (由 Converter::RvdataRestorer 处理)
    # 提供带版本号的 new 方法供 restorer 调用
    def initialize(width = 17, height = 13, rgss_version = "RGSS3")
      @width = width
      @height = height
      # 通用默认值
      @scroll_type = 0
      @autoplay_bgm = false
      @bgm = RPG::BGM.new
      @autoplay_bgs = false
      @bgs = RPG::BGS.new
      @disable_dashing = false
      @encounter_list = []
      @encounter_step = 30
      @parallax_name = ""
      @parallax_loop_x = false
      @parallax_loop_y = false
      @parallax_sx = 0
      @parallax_sy = 0
      @parallax_show = false
      @events = {}

      if rgss_version == "RGSS3"
        @display_name = ""
        @tileset_id = 1
        @specify_battleback = false
        @battleback1_name = ""
        @battleback2_name = ""
        @note = ""
        # RGSS3 data 通常为 Table(w, h, 4)，但恢复时可能为 nil，依赖 JSON 数据
        @data = Table.new([@width, @height, 4]) # 默认创建4层 Table
      else # RGSS2
        # RGSS2 没有 display_name 等
        @data = Table.new([@width, @height, 3]) # 默认创建3层 Table
      end
    end
  end # Map

  # 基础物品/技能/职业等的基类
  class BaseItem
    include Jsonable
    attr_accessor :id, :name, :icon_index, :description, :note
    attr_accessor :features # RGSS3 特有，在 initialize 中根据版本添加

    # 解包通用名称、描述、备注 (由 Converter::JsonExporter 处理)
    def unpack_names
      Utils.unpack_names_for(self, :name, :description, :note)
    end

    # 初始化依赖版本 (由 Converter::RvdataRestorer 调用)
    def initialize(rgss_version = "RGSS3")
      @id = 0
      @name = ""
      @icon_index = 0
      @description = ""
      @note = ""
      @features = [] if rgss_version == "RGSS3"
    end
  end # BaseItem

  # 可使用物品/技能的基类
  class UsableItem < RPG::BaseItem
    # 通用
    attr_accessor :scope, :occasion, :speed, :animation_id
    # RGSS2 特有 (恢复时根据版本添加)
    attr_accessor :common_event_id, :base_damage, :variance, :atk_f, :spi_f
    attr_accessor :physical_attack, :damage_to_mp, :absorb_damage, :ignore_defense
    attr_accessor :element_set, :plus_state_set, :minus_state_set
    # RGSS3 特有 (恢复时根据版本添加)
    attr_accessor :success_rate, :repeats, :tp_gain, :hit_type, :damage, :effects

    # 解包 (由 Converter::JsonExporter 处理，子类可能覆盖)
    # def unpack_names; super; end

    # 初始化依赖版本 (由 Converter::RvdataRestorer 调用)
    def initialize(rgss_version = "RGSS3")
      # 使用实例方法绑定调用父类初始化，确保 features 被正确处理
      RPG::BaseItem.instance_method(:initialize).bind(self).call(rgss_version)

      # 通用属性默认值
      @scope = 0
      @occasion = 0
      @speed = 0
      @animation_id = 0 # 注意：RGSS3 武器动画在 Weapon 类

      if rgss_version == "RGSS2"
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
      else # RGSS3
        @success_rate = 100
        @repeats = 1
        @tp_gain = 0
        @hit_type = 0 # 0:必中, 1:物理, 2:魔法
        # Damage 和 Effect 对象在恢复时根据 JSON 数据创建
        @damage = RPG::UsableItem::Damage.new # 提供默认实例
        @effects = []
      end
    end

    # --- RGSS2 的辅助方法 ---
    def for_opponent?; [1, 2, 3, 4, 5, 6].include?(@scope); end
    def for_friend?; [7, 8, 9, 10, 11].include?(@scope); end
    def for_dead_friend?; [9, 10].include?(@scope); end
    def for_user?; [11].include?(@scope); end
    def for_one?; [1, 3, 4, 7, 9, 11].include?(@scope); end
    def for_two?; [5].include?(@scope); end
    def for_three?; [6].include?(@scope); end
    def for_random?; [4, 5, 6].include?(@scope); end
    def for_all?; [2, 8, 10].include?(@scope); end
    def dual?; [3].include?(@scope); end # RGSS2 专用? 检查文档
    def need_selection?; [1, 3, 7, 9].include?(@scope); end
    def battle_ok?; [0, 1].include?(@occasion); end
    def menu_ok?; [0, 2].include?(@occasion); end

    # --- RGSS3 嵌套类定义 (移至 rgss3.rb 以保持文件焦点) ---
    # 嵌套类 Effect 和 Damage 的定义移到 rgss3.rb 中
  end # UsableItem

  # 系统设定类
  class System
    include Jsonable
    # RGSS3 特有
    attr_accessor :japanese, :currency_unit, :skill_types, :weapon_types, :armor_types
    attr_accessor :title1_name, :title2_name, :opt_draw_title, :opt_use_midi, :opt_transparent
    attr_accessor :opt_followers, :opt_slip_death, :opt_floor_death, :opt_display_tp, :opt_extra_exp
    attr_accessor :window_tone, :battleback1_name, :battleback2_name
    # RGSS2 特有
    attr_accessor :passages # 通常在 Tilesets.rvdata 中定义，这里保留以防万一
    # 通用/共有 (部分在 RGSS2/3 中都存在)
    attr_accessor :game_title, :version_id, :party_members, :elements, :switches, :variables
    attr_accessor :boat, :ship, :airship, :title_bgm, :battle_bgm, :battle_end_me, :gameover_me
    attr_accessor :sounds, :test_battlers, :test_troop_id, :start_map_id, :start_x, :start_y
    attr_accessor :terms, :battler_name, :battler_hue, :edit_map_id, :magic_number # magic_number 在两者中可能都有

    # 解包：行为依赖版本 (由 Converter::JsonExporter 处理)
    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :game_title)
      @boat&.unpack_names
      @ship&.unpack_names
      @airship&.unpack_names
      @title_bgm&.unpack_names
      @battle_bgm&.unpack_names
      @battle_end_me&.unpack_names
      @gameover_me&.unpack_names
      @sounds.each { |s| s&.unpack_names }
      @terms&.unpack_names(rgss_version) # Terms 解包依赖版本

      # 版本特定解包
      if rgss_version == "RGSS3"
        Utils.unpack_names_for(self, :currency_unit, :title1_name, :title2_name,
                               :battleback1_name, :battleback2_name, :battler_name)
        # 解包数组中的字符串
        [:@elements, :@skill_types, :@weapon_types, :@armor_types, :@switches, :@variables].each do |ivar_symbol|
          array = instance_variable_get(ivar_symbol)
          if array.is_a?(Array)
            array.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item }
          end
        end
      else # RGSS2
        Utils.unpack_names_for(self, :battler_name)
        [:@elements, :@switches, :@variables].each do |ivar_symbol|
          array = instance_variable_get(ivar_symbol)
          if array.is_a?(Array)
            array.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item }
          end
        end
      end
    end

    # 初始化依赖版本 (由 Converter::RvdataRestorer 调用)
    def initialize(rgss_version = "RGSS3")
      @game_title = ""
      @version_id = 0
      @party_members = [1]
      @switches = [nil, ""]
      @variables = [nil, ""]
      @boat = RPG::System::Vehicle.new
      @ship = RPG::System::Vehicle.new
      @airship = RPG::System::Vehicle.new
      @title_bgm = RPG::BGM.new
      @battle_bgm = RPG::BGM.new
      @battle_end_me = RPG::ME.new
      @gameover_me = RPG::ME.new
      @test_battlers = []
      @test_troop_id = 1
      @start_map_id = 1
      @start_x = 0
      @start_y = 0
      @edit_map_id = 1
      @magic_number = 0 # 默认值，RGSS3 可能是 1

      if rgss_version == "RGSS3"
        @japanese = true
        @currency_unit = ""
        @skill_types = [nil, ""]
        @weapon_types = [nil, ""]
        @armor_types = [nil, ""]
        @elements = [nil, ""]
        @title1_name = ""
        @title2_name = ""
        @opt_draw_title = true
        @opt_use_midi = false
        @opt_transparent = false
        @opt_followers = true
        @opt_slip_death = false
        @opt_floor_death = false
        @opt_display_tp = true
        @opt_extra_exp = false
        @window_tone = Tone.new([0.0, 0.0, 0.0, 0.0]) # RGSS3 Tone 默认值
        @sounds = Array.new(24) { RPG::SE.new }
        @terms = RPG::System::Terms.new("RGSS3")
        @battleback1_name = ""
        @battleback2_name = ""
        @battler_name = "" # SV battler?
        @battler_hue = 0
        @magic_number = 1 # RGSS3 Ace 默认是 1
      else # RGSS2
        @elements = [nil, ""]
        @passages = nil # 通常在 Tilesets.rvdata
        @sounds = Array.new(20) { RPG::SE.new }
        @terms = RPG::System::Terms.new("RGSS2")
        @battler_name = "" # Enemy battler?
        @battler_hue = 0
      end
    end

    # 嵌套类 Vehicle, Terms, TestBattler 的定义
    class Vehicle
      include Jsonable
      attr_accessor :character_name, :character_index, :bgm, :start_map_id, :start_x, :start_y

      def unpack_names # 由 Converter::JsonExporter 处理
        Utils.unpack_names_for(self, :character_name)
        @bgm&.unpack_names
      end

      def initialize
        @character_name = ""
        @character_index = 0
        @bgm = RPG::BGM.new
        @start_map_id = 0
        @start_x = 0
        @start_y = 0
      end
    end # Vehicle

    class Terms
      include Jsonable
      # RGSS3
      attr_accessor :basic, :params, :etypes, :commands
      # RGSS2
      attr_accessor :level, :level_a, :hp, :hp_a, :mp, :mp_a, :atk, :def, :spi, :agi
      attr_accessor :weapon, :armor1, :armor2, :armor3, :armor4, :weapon1, :weapon2
      attr_accessor :attack, :skill, :guard, :item, :equip, :status, :save, :game_end
      attr_accessor :fight, :escape, :new_game, :continue, :shutdown, :to_title, :cancel, :gold

      # 解包：行为依赖版本 (由 Converter::JsonExporter 处理)
      def unpack_names(rgss_version)
        if rgss_version == "RGSS3"
          [:@basic, :@params, :@etypes, :@commands].each do |ivar|
            array = instance_variable_get(ivar)
            if array.is_a?(Array)
              array.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item }
            end
          end
        else # RGSS2
          all_rgss2_attrs = instance_variables.select { |v| v != :@basic && v != :@params && v != :@etypes && v != :@commands }
          all_rgss2_attrs.each do |ivar|
            value = instance_variable_get(ivar)
            instance_variable_set(ivar, RPG.unpack_str(value)) if value.is_a?(String)
          end
        end
      end

      # 初始化依赖版本 (由 Converter::RvdataRestorer 调用)
      def initialize(rgss_version = "RGSS3")
        if rgss_version == "RGSS3"
          @basic = Array.new(8) { "" }
          @params = Array.new(8) { "" }
          @etypes = Array.new(5) { "" }
          @commands = Array.new(23) { "" }
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
        end
      end
    end # Terms

    class TestBattler
      include Jsonable
      attr_accessor :actor_id, :level
      # RGSS3
      attr_accessor :equips
      # RGSS2
      attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id

      # 初始化依赖版本 (由 Converter::RvdataRestorer 调用)
      def initialize(rgss_version = "RGSS3")
        @actor_id = 1
        @level = 1
        if rgss_version == "RGSS3"
          @equips = [0, 0, 0, 0, 0]
        else # RGSS2
          @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0
        end
      end
    end # TestBattler
  end # System

  # 动画类
  class Animation
    include Jsonable
    attr_accessor :id, :name, :animation1_name, :animation1_hue, :animation2_name, :animation2_hue
    attr_accessor :position, :frame_max, :frames, :timings

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names #(rgss_version) # 版本信息用于 Frame
      Utils.unpack_names_for(self, :name, :animation1_name, :animation2_name)
      # Frame 不需要解包，Timing 需要解包 SE
      @timings.each { |t| t.unpack_names if t.respond_to?(:unpack_names) }
    end

    def initialize #(rgss_version = "RGSS3") # Frame 初始化依赖版本
      @id = 0
      @name = ""
      @animation1_name = ""
      @animation1_hue = 0
      @animation2_name = ""
      @animation2_hue = 0
      @position = 1
      @frame_max = 1
      # Frame 和 Timing 在恢复时根据 JSON 数据创建
      @frames = [] # 初始为空，由恢复逻辑填充
      @timings = []
    end

    class Frame # 嵌套 Frame 类
      include Jsonable
      attr_accessor :cell_max, :cell_data # cell_data 类型依赖版本

      # 初始化依赖版本 (由 Converter::RvdataRestorer 调用)
      def initialize(rgss_version = "RGSS3")
        @cell_max = 0
        # cell_data 在恢复时根据 JSON 数据创建，可能为 nil(RGSS3) 或 Table(RGSS2)
        @cell_data = (rgss_version == "RGSS3") ? nil : Table.new([0, 0])
      end
    end # Frame

    class Timing # 嵌套 Timing 类
      include Jsonable
      attr_accessor :frame, :se, :flash_scope, :flash_color, :flash_duration

      def unpack_names # 由 Converter::JsonExporter 处理
        @se&.unpack_names
      end

      def initialize
        @frame = 0
        @se = RPG::SE.new("", 80)
        @flash_scope = 0
        @flash_color = Color.new([255.0, 255.0, 255.0, 255.0])
        @flash_duration = 5
      end
    end # Timing
  end # Animation

  # 公共事件类
  class CommonEvent
    include Jsonable
    attr_accessor :id, :name, :trigger, :switch_id, :list

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      Utils.unpack_names_for(self, :name)
      @list.each { |command| command.unpack_names if command.respond_to?(:unpack_names) }
    end

    def initialize
      @id = 0
      @name = ""
      @trigger = 0 # 0:无, 1:自动执行, 2:并行处理
      @switch_id = 1
      @list = [RPG::EventCommand.new]
    end

    def autorun?; @trigger == 1; end
    def parallel?; @trigger == 2; end
  end # CommonEvent

  # 队伍类
  class Troop
    include Jsonable
    attr_accessor :id, :name, :members, :pages

    # 解包 (由 Converter::JsonExporter 处理)
    def unpack_names
      Utils.unpack_names_for(self, :name)
      @pages.each { |page| page.unpack_names if page.respond_to?(:unpack_names) }
      # Member 不需要解包
    end

    def initialize
      @id = 0
      @name = ""
      # Member 和 Page 在恢复时根据 JSON 数据创建
      @members = []
      @pages = [] #[RPG::Troop::Page.new] # 初始化为空或含默认值
    end

    class Member # 嵌套 Member 类
      include Jsonable
      attr_accessor :enemy_id, :x, :y, :hidden
      attr_accessor :immortal # RGSS2 特有

      # 初始化依赖版本 (由 Converter::RvdataRestorer 调用)
      def initialize(rgss_version = "RGSS3")
        @enemy_id = 1
        @x = 0
        @y = 0
        @hidden = false
        @immortal = false if rgss_version == "RGSS2"
      end
    end # Member

    class Page # 嵌套 Page 类
      include Jsonable
      attr_accessor :condition, :span, :list

      # 解包 List (由 Converter::JsonExporter 处理)
      def unpack_names
        @list.each { |command| command.unpack_names if command.respond_to?(:unpack_names) }
      end

      def initialize
        @condition = RPG::Troop::Page::Condition.new
        @span = 0 # 0:回合结束, 1:并行处理, 2:战斗开始
        @list = [RPG::EventCommand.new]
      end

      class Condition # 嵌套 Condition 类
        include Jsonable
        attr_accessor :turn_ending, :turn_valid, :enemy_valid, :actor_valid, :switch_valid
        attr_accessor :turn_a, :turn_b, :enemy_index, :enemy_hp, :actor_id, :actor_hp, :switch_id

        def initialize
          @turn_ending = false; @turn_valid = false; @enemy_valid = false
          @actor_valid = false; @switch_valid = false
          @turn_a = 0; @turn_b = 0; @enemy_index = 0; @enemy_hp = 50
          @actor_id = 1; @actor_hp = 50; @switch_id = 1
        end
      end # Condition
    end # Page
  end # Troop
end # RPG

# 矩形类 (在 RGSS2 的 RPG::Area 中使用)
class Rect
  include Jsonable
  attr_accessor :x, :y, :width, :height

  def initialize(x = 0, y = 0, width = 0, height = 0)
    set(x, y, width, height)
  end

  def _dump(_limit)
    [@x, @y, @width, @height].pack("iiii") # i = 32-bit signed integer
  end

  def self._load(obj)
    new(*obj.unpack("iiii"))
  end

  def set(x, y, width, height)
    @x = x.to_i
    @y = y.to_i
    @width = width.to_i
    @height = height.to_i
    self
  end

  def empty
    set(0, 0, 0, 0)
  end

  def to_s
    "(#{@x}, #{@y}, #{@width}, #{@height})"
  end
end
