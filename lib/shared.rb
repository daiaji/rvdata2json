# lib/shared.rb
# 包含多个 RGSS 版本共用的类定义和基础模块。
# 注意: 某些类 (如 Map, System) 在这里只定义了基本框架或共享属性，
#       具体的版本实现或扩展在 rgss1.rb, rgss2.rb, rgss3.rb 中完成。

require_relative "utils" # 加载通用工具函数 (如字符串解包)

# --- RPG 模块 ---
# 作为所有 RPG Maker 数据类的命名空间
module RPG
  # 辅助方法：解包可能非 UTF-8 的字符串 (委托给 Utils)
  # @param str [String] 输入字符串
  # @return [String] 转换为 UTF-8 的字符串
  def self.unpack_str(str)
    Utils.unpack_string(str)
  end
end

# --- 基础数据结构 ---
# 这些类实现了 _dump 和 _load 方法，以便能被 Marshal 正确序列化和反序列化。

# -- 颜色类 (Color) --
# 表示 RGBA 颜色值 (红, 绿, 蓝, 透明度)
class Color
  attr_accessor :red, :green, :blue, :alpha # 浮点数值 (0.0 - 255.0)

  # 初始化颜色
  # @param data [Array<Numeric>] 包含最多 4 个数值的数组 [r, g, b, a]
  def initialize(data)
    # 确保数组长度至少为 4，不足部分用 0.0 填充
    d = Array(data) + [0.0] * (4 - Array(data).size)
    @red, @green, @blue, @alpha = *d[0..3].map(&:to_f) # 取前 4 个并转为浮点数
  end

  # Marshal 序列化方法: 将 RGBA 值打包为 4 个单精度浮点数的二进制字符串
  def _dump(_limit)
    [@red.to_f, @green.to_f, @blue.to_f, @alpha.to_f].pack("FFFF") # 使用 'F' (单精度浮点数, 本机字节序)
  end

  # Marshal 反序列化方法: 从二进制字符串解包 RGBA 值
  def self._load(obj)
    new(obj.unpack("FFFF")) # 使用 'F' 解包
  end
end

# -- 表格类 (Table) --
# 用于存储多维数组数据 (地图图块、能力值曲线等)
class Table
  # 维度数 (1, 2, 或 3)
  attr_accessor :num_of_dimensions
  # 各维度的大小 (x, y, z)
  attr_accessor :xsize, :ysize, :zsize
  # 元素总数 (理论上等于 xsize * ysize * zsize)
  attr_accessor :num_of_elements
  # 存储元素的扁平数组 (内部存储)
  attr_reader :elements # 外部只读

  # 初始化表格
  # @param data [Array<Integer>] 包含元数据和元素的数组
  #        格式: [维度数, x大小, y大小, z大小, 元素总数, 元素1, 元素2, ...]
  def initialize(data)
    # 解包元数据
    dimensions, x, y, z, count, *elements_array = *Array(data)
    @num_of_dimensions = dimensions.to_i
    @xsize = x.to_i; @ysize = y.to_i; @zsize = z.to_i
    @num_of_elements = count.to_i

    # 处理元素数组
    actual_elements = elements_array.flatten.map(&:to_i) # 展平并转为整数
    expected_size = [@num_of_elements, 0].max # 预期大小，至少为 0
    # 调整数组大小以匹配 num_of_elements
    if actual_elements.size < expected_size
      # 如果元素不足，用 0 填充
      actual_elements.fill(0, actual_elements.size, expected_size - actual_elements.size)
    elsif actual_elements.size > expected_size
      # 如果元素过多，截断
      actual_elements = actual_elements.slice(0, expected_size)
    end
    @elements = actual_elements
  end

  # Marshal 序列化方法: 将元数据和元素打包为二进制字符串
  def _dump(_limit)
    dump_elements = @elements.map(&:to_i) # 确保所有元素为整数
    # 使用 'V' (32位无符号整数, 小端) 打包元数据，'v*' (16位无符号整数, 小端) 打包元素
    [@num_of_dimensions, @xsize, @ysize, @zsize, @num_of_elements, *dump_elements].pack("VVVVVv*")
  end

  # Marshal 反序列化方法: 从二进制字符串解包数据
  def self._load(obj)
    new(obj.unpack("VVVVVv*"))
  end

  # 获取指定位置的元素值
  # 支持 1D, 2D, 3D 访问
  def [](x, y = 0, z = 0)
    # 边界检查
    return nil if @num_of_dimensions >= 2 && @xsize <= 0
    return nil if @num_of_dimensions == 3 && @ysize <= 0
    return nil if x < 0 || x >= @xsize
    return nil if @num_of_dimensions >= 2 && (y < 0 || y >= @ysize)
    return nil if @num_of_dimensions == 3 && (z < 0 || z >= @zsize)

    # 计算扁平数组中的索引
    index = x
    index += y * @xsize if @num_of_dimensions >= 2
    index += z * @xsize * @ysize if @num_of_dimensions == 3

    # 再次检查索引范围
    return nil if index < 0 || index >= @num_of_elements

    @elements[index] # 返回元素值
  end

  # 设置指定位置的元素值
  # 支持 1D, 2D, 3D 访问
  def []=(*args)
    value = args.pop.to_i # 最后一个参数是值，确保为整数
    x, y, z = 0, 0, 0

    # 根据维度解析坐标参数
    case @num_of_dimensions
    when 1
      raise ArgumentError, "1D Table: 需要 1 个索引，得到 #{args.size} 个" unless args.size == 1
      x = args[0]
    when 2
      raise ArgumentError, "2D Table: 需要 2 个索引，得到 #{args.size} 个" unless args.size == 2
      x, y = args
    when 3
      raise ArgumentError, "3D Table: 需要 3 个索引，得到 #{args.size} 个" unless args.size == 3
      x, y, z = args
    else
      return nil # 不支持的维度
    end

    # 边界检查
    return nil if x < 0 || x >= @xsize
    return nil if @num_of_dimensions >= 2 && (y < 0 || y >= @ysize)
    return nil if @num_of_dimensions == 3 && (z < 0 || z >= @zsize)
    return nil if @num_of_dimensions >= 2 && @xsize <= 0
    return nil if @num_of_dimensions == 3 && @ysize <= 0

    # 计算索引
    index = x
    index += y * @xsize if @num_of_dimensions >= 2
    index += z * @xsize * @ysize if @num_of_dimensions == 3

    # 在有效范围内设置值
    @elements[index] = value if index >= 0 && index < @num_of_elements
  end

  # 调整表格大小和维度
  # @param x [Integer] X 维度大小
  # @param y [Integer, nil] Y 维度大小 (如果为 nil，则为 1D)
  # @param z [Integer, nil] Z 维度大小 (如果为 nil 且 y 非 nil，则为 2D)
  def resize(x, y = nil, z = nil)
    @xsize = x.to_i
    # 根据参数确定维度
    if y.nil?
      @num_of_dimensions = 1; @ysize = 1; @zsize = 1
    elsif z.nil?
      @num_of_dimensions = 2; @ysize = y.to_i; @zsize = 1
    else
      @num_of_dimensions = 3; @ysize = y.to_i; @zsize = z.to_i
    end
    # 检查尺寸是否为负
    raise ArgumentError, "Table 维度不能为负数" if @xsize < 0 || @ysize < 0 || @zsize < 0

    # 重新计算元素总数并创建新的元素数组 (用 0 填充)
    @num_of_elements = @xsize * @ysize * @zsize
    @elements = Array.new([@num_of_elements, 0].max, 0) # 确保大小至少为 0
    self
  end
end

# -- 色调类 (Tone) --
# 表示 RGBA 色调偏移值 (红, 绿, 蓝, 灰度)
class Tone
  attr_accessor :red, :green, :blue, :gray # 浮点数值 (-255.0 - 255.0)

  # 初始化色调
  # @param data [Array<Numeric>] 包含最多 4 个数值的数组 [r, g, b, gray]
  def initialize(data)
    # 确保数组长度至少为 4，不足部分用 0.0 填充
    d = Array(data) + [0.0] * (4 - Array(data).size)
    @red, @green, @blue, @gray = *d[0..3].map(&:to_f) # 取前 4 个并转为浮点数
  end

  # Marshal 序列化方法: 将 RGBA 值打包为 4 个单精度浮点数的二进制字符串
  def _dump(_limit)
    [@red.to_f, @green.to_f, @blue.to_f, @gray.to_f].pack("FFFF") # 使用 'F'
  end

  # Marshal 反序列化方法: 从二进制字符串解包 RGBA 值
  def self._load(obj)
    new(obj.unpack("FFFF")) # 使用 'F'
  end
end

# -- 矩形类 (Rect) --
# 表示一个矩形区域 (x, y, width, height)
class Rect
  attr_accessor :x, :y, :width, :height # 整数值

  # 初始化矩形
  def initialize(x = 0, y = 0, width = 0, height = 0)
    set(x, y, width, height)
  end

  # Marshal 序列化方法: 将 x, y, width, height 打包为 4 个 32 位有符号整数的二进制字符串
  def _dump(_limit)
    [@x.to_i, @y.to_i, @width.to_i, @height.to_i].pack("iiii") # 使用 'i' (32位有符号整数, 本机字节序)
  end

  # Marshal 反序列化方法: 从二进制字符串解包 x, y, width, height
  def self._load(obj)
    new(*obj.unpack("iiii")) # 使用 'i'
  end

  # 设置矩形的属性
  def set(x, y, width, height)
    @x = x.to_i; @y = y.to_i; @width = width.to_i; @height = height.to_i
    self
  end

  # 将矩形设置为空 (所有值为 0)
  def empty
    set(0, 0, 0, 0)
  end

  # 返回矩形的字符串表示形式
  def to_s
    "(#{@x}, #{@y}, #{@width}, #{@height})"
  end
end

# --- 基础 RPG Maker 类 ---
# 这些类在多个 RGSS 版本中存在，但具体属性可能不同。
# 版本特定的属性通过 Mixin 添加。

module RPG
  # -- 移动指令类 (MoveCommand) --
  # 用于 MoveRoute 中定义单个移动操作
  class MoveCommand
    attr_accessor :code, :parameters # 指令代码, 指令参数列表 (数组)

    def initialize(code = 0, parameters = [])
      @code = code; @parameters = parameters
    end
  end

  # -- 事件指令类 (EventCommand) --
  # 用于事件页或公共事件中定义单个指令
  class EventCommand
    attr_accessor :code, :indent, :parameters # 指令代码, 缩进级别, 指令参数列表 (数组)

    # 解包参数列表中的字符串
    def unpack_names
      return unless @parameters.is_a?(Array)
      @parameters.map! { |p| p.is_a?(String) ? RPG.unpack_str(p) : p }
    end

    def initialize(code = 0, indent = 0, parameters = [])
      @code = code; @indent = indent; @parameters = parameters
    end
  end

  # -- 地图信息类 (MapInfo) --
  # 存储地图树状结构中的基本信息
  class MapInfo
    # 共享属性 (所有版本都有)
    attr_accessor :name, :parent_id, :order
    # RGSS2/3 特有属性
    attr_accessor :expanded, :scroll_x, :scroll_y # 是否展开, 滚动位置 X, 滚动位置 Y

    # 解包地图名称
    def unpack_names; Utils.unpack_names_for(self, :name); end

    # 初始化方法 (包含所有可能版本的属性)
    def initialize
      @name = ""; @parent_id = 0; @order = 0
      @expanded = false; @scroll_x = 0; @scroll_y = 0
    end
  end

  # -- 事件类 (Event) --
  # 表示地图上的一个事件
  class Event
    attr_accessor :id, :name, :x, :y, :pages # ID, 名称, X坐标, Y坐标, 事件页列表 (Array<RPG::Event::Page>)

    # 解包事件名称，并递归解包所有页面
    def unpack_names
      Utils.unpack_names_for(self, :name)
      # 注意: rgssX.rb 中的 Event 类会覆盖此方法以递归调用 pages
    end

    # 初始化事件
    def initialize(x = 0, y = 0)
      @id = 0; @name = ""; @x = x; @y = y; @pages = [RPG::Event::Page.new] # 默认包含一个页面
    end

    # -- 事件页面类 (Event::Page) --
    # 定义事件的一个页面及其触发条件和内容
    class Page
      # 共享属性
      attr_accessor :condition       # 触发条件 (RPG::Event::Page::Condition 对象)
      attr_accessor :graphic         # 图像设置 (RPG::Event::Page::Graphic 对象)
      attr_accessor :move_type       # 移动类型 (0:固定, 1:随机, 2:接近, 3:自定义)
      attr_accessor :move_speed      # 移动速度 (1-6)
      attr_accessor :move_frequency  # 移动频度 (1-5)
      attr_accessor :move_route      # 自定义移动路线 (RPG::MoveRoute 对象)
      attr_accessor :walk_anime      # 行走动画?
      attr_accessor :step_anime      # 踏步动画?
      attr_accessor :direction_fix   # 固定朝向?
      attr_accessor :through         # 穿透?
      attr_accessor :priority_type   # 优先级类型 (0:低于角色, 1:与角色同层, 2:高于角色)
      attr_accessor :trigger         # 触发条件 (0:确定键, 1:接触角色, 2:接触事件, 3:自动执行, 4:并行处理)
      attr_accessor :list            # 事件指令列表 (Array<RPG::EventCommand>)
      # RGSS1 特有属性 (在 rgss1.rb 中添加)
      # attr_accessor :always_on_top

      # 解包页面图像和事件指令
      def unpack_names
        @graphic&.unpack_names if @graphic.respond_to?(:unpack_names)
        @list&.each { |c| c.unpack_names if c.respond_to?(:unpack_names) }
        # 注意: rgssX.rb 中的 Page 类可能会覆盖此方法
      end

      # 初始化事件页面
      def initialize
        @condition = RPG::Event::Page::Condition.new
        @graphic = RPG::Event::Page::Graphic.new
        @move_type = 0; @move_speed = 3; @move_frequency = 3
        @move_route = RPG::MoveRoute.new
        @walk_anime = true; @step_anime = false; @direction_fix = false; @through = false
        @priority_type = 0; @trigger = 0; @list = [RPG::EventCommand.new]
      end

      # -- 事件页面条件类 (Event::Page::Condition) --
      # 定义事件页面的触发条件
      class Condition
        # 共享条件
        attr_accessor :switch1_valid, :switch2_valid # 开关1/2 条件有效?
        attr_accessor :variable_valid              # 变量条件有效?
        attr_accessor :self_switch_valid           # 独立开关条件有效?
        attr_accessor :switch1_id, :switch2_id      # 开关1/2 ID
        attr_accessor :variable_id                 # 变量 ID
        attr_accessor :variable_value              # 变量阈值 (>=)
        attr_accessor :self_switch_ch              # 独立开关字符 ("A", "B", "C", "D")
        # RGSS2/3 特有条件
        attr_accessor :item_valid, :actor_valid     # 物品/角色 条件有效?
        attr_accessor :item_id, :actor_id          # 物品/角色 ID

        # 初始化条件
        def initialize
          @switch1_valid = false; @switch2_valid = false; @variable_valid = false; @self_switch_valid = false
          @item_valid = false; @actor_valid = false # 初始化 RGSS2/3 属性
          @switch1_id = 1; @switch2_id = 1; @variable_id = 1; @variable_value = 0
          @self_switch_ch = "A"; @item_id = 1; @actor_id = 1
        end
      end # Condition

      # -- 事件页面图像类 (Event::Page::Graphic) --
      # 定义事件页面的图像显示
      class Graphic
        # 共享属性 (RGSS2/3)
        attr_accessor :tile_id          # 图块 ID (如果使用图块)
        attr_accessor :character_name   # 角色文件名
        attr_accessor :character_index  # 角色索引 (0-7)
        attr_accessor :direction        # 初始朝向 (2下,4左,6右,8上)
        attr_accessor :pattern          # 初始动画帧 (0,1,2)
        # RGSS1 特有属性 (在 rgss1.rb 中通过 Mixin 添加)
        # attr_accessor :character_hue, :opacity, :blend_type

        # 解包角色文件名
        def unpack_names; Utils.unpack_names_for(self, :character_name); end

        # 初始化图像 (RGSS2/3 结构)
        def initialize
          @tile_id = 0; @character_name = ""; @character_index = 0
          @direction = 2; @pattern = 0
          # RGSS1 的初始化在 rgss1.rb 中通过 Mixin 完成
        end
      end # Graphic
    end # Page
  end # Event

  # -- 音频文件类 (AudioFile) --
  # BGM, BGS, ME, SE 的基类
  class AudioFile
    attr_accessor :name, :volume, :pitch # 文件名, 音量 (0-100), 音调 (50-150)

    # 解包文件名
    def unpack_names; Utils.unpack_names_for(self, :name); end

    # 初始化音频文件
    def initialize(name = "", volume = 100, pitch = 100)
      @name = name.to_s   # 确保是字符串
      @volume = volume.to_i # 确保是整数
      @pitch = pitch.to_i   # 确保是整数
    end
  end

  # -- 背景音乐类 (BGM) --
  class BGM < AudioFile
    @@last = RPG::BGM.new # 类变量，用于存储最后播放的 BGM 信息 (用于继续播放)
    attr_accessor :pos    # 播放位置 (某些版本/实现可能支持)

    # 播放 BGM，并记录信息到 @@last
    def play(pos = 0)
      # 使用 dup 复制自身状态到 @@last，以防原始对象被修改
      # 如果 dup 失败 (例如在某些旧 Ruby 版本或特殊情况下)，则直接赋值
      @@last = self.dup rescue self
      @pos = pos if respond_to?(:pos=) # 如果支持 pos 属性，则设置
      # 实际播放逻辑由游戏引擎实现
    end

    # 从记录的位置或开头重新播放
    def replay
      play(@pos || 0)
    end

    # 停止播放 BGM (重置 @@last)
    def self.stop
      @@last = RPG::BGM.new
      # 实际停止逻辑由游戏引擎实现
    end

    # 淡出 BGM (重置 @@last)
    def self.fade(_time) # _time 参数通常由引擎使用
      @@last = RPG::BGM.new
      # 实际淡出逻辑由游戏引擎实现
    end

    # 获取最后播放的 BGM 信息
    def self.last
      @@last
    end
  end

  # -- 背景音效类 (BGS) --
  # (与 BGM 结构和逻辑类似)
  class BGS < AudioFile
    @@last = RPG::BGS.new
    attr_accessor :pos

    def play(pos = 0)
      @@last = self.dup rescue self
      @pos = pos if respond_to?(:pos=)
    end

    def replay; play(@pos || 0); end

    def self.stop; @@last = RPG::BGS.new; end
    def self.fade(_time); @@last = RPG::BGS.new; end
    def self.last; @@last; end
  end

  # -- 音乐效果类 (ME) --
  # 通常用于短时音乐片段 (如升级、获得物品)
  class ME < AudioFile
    def play; end # 播放逻辑由引擎实现

    def self.stop; end # 停止逻辑由引擎实现
    def self.fade(_time); end # 淡出逻辑由引擎实现
  end

  # -- 声音效果类 (SE) --
  # 用于短时音效 (如攻击、光标移动)
  class SE < AudioFile
    def play; end # 播放逻辑由引擎实现

    def self.stop; end # 停止所有 SE 的逻辑由引擎实现 (如果支持)
  end

  # -- 地图类 (Map) --
  # 仅定义空类作为占位符，具体实现在 rgssX.rb 中
  class Map; end

  # -- 基础物品/数据类 (BaseItem) --
  # RGSS2/3 中大多数数据库对象的基类 (物品, 技能, 武器, 护甲, 角色, 职业, 敌人, 状态)
  class BaseItem
    attr_accessor :id, :name, :icon_index, :description, :note # ID, 名称, 图标索引, 描述, 备注
    # RGSS3 特有属性 (在 rgss3.rb 中通过 Mixin 添加)
    # attr_accessor :features

    # 解包名称、描述和备注
    def unpack_names; Utils.unpack_names_for(self, :name, :description, :note); end

    # 初始化 BaseItem
    def initialize
      @id = 0; @name = ""; @icon_index = 0; @description = ""; @note = ""
      # @features 的初始化在 rgss3.rb Mixin 中
    end

    # RGSS3 特有嵌套类 (在 rgss3.rb 中定义)
    # class Feature; end
  end

  # -- 可使用物品/技能类 (UsableItem) --
  # RGSS2/3 中物品和技能的基类
  class UsableItem < RPG::BaseItem # 继承自 BaseItem
    # 共享属性
    attr_accessor :scope        # 范围
    attr_accessor :occasion     # 可用时机 (0:从不, 1:战斗中, 2:菜单, 3:总是)
    attr_accessor :speed        # 速度修正
    attr_accessor :animation_id # 使用动画 ID
    # RGSS2 特有属性 (在 rgss2.rb 中通过 Mixin 添加)
    # attr_accessor :common_event_id, :base_damage, ...
    # RGSS3 特有属性 (在 rgss3.rb 中通过 Mixin 添加)
    # attr_accessor :success_rate, :repeats, ...

    # 解包 (调用父类 BaseItem 的解包)
    def unpack_names; super(); end

    # 初始化 UsableItem
    def initialize
      super() # 调用 BaseItem 初始化
      @scope = 0; @occasion = 0; @speed = 0; @animation_id = 0
      # 其他版本特定属性在 Mixin 中初始化
    end

    # RGSS3 特有嵌套类 (在 rgss3.rb 中定义)
    # class Effect; end
    # class Damage; end
  end

  # -- 系统设置类 (System) --
  # 仅定义空类和共享的嵌套类框架，具体实现在 rgssX.rb 中
  class System
    # --- 共享属性 (在 rgssX.rb 中通过 Mixin 或直接定义) ---
    # attr_accessor :game_title, :version_id, :party_members, :elements, ...
    # attr_accessor :boat, :ship, :airship, :title_bgm, ...
    # attr_accessor :sounds, :test_battlers, ...
    # attr_accessor :terms # 术语对象
    # ...

    # --- 嵌套共享类定义 ---

    # -- 交通工具类 (Vehicle) --
    class Vehicle
      attr_accessor :character_name, :character_index # 图像文件名, 图像索引
      attr_accessor :bgm                             # 乘坐时的 BGM (RPG::BGM 对象)
      attr_accessor :start_map_id, :start_x, :start_y # 初始位置地图 ID, X, Y

      # 解包角色文件名和 BGM 文件名
      def unpack_names
        Utils.unpack_names_for(self, :character_name)
        @bgm&.unpack_names
      end

      def initialize
        @character_name = ""; @character_index = 0; @bgm = RPG::BGM.new
        @start_map_id = 0; @start_x = 0; @start_y = 0
      end
    end

    # -- 测试战斗者类 (TestBattler) --
    # 定义测试战斗时的角色设置
    class TestBattler
      # 共享属性
      attr_accessor :actor_id, :level # 角色 ID, 等级
      # 版本特定属性 (在 rgssX.rb 中通过 Mixin 添加)
      # RGSS1/2: :weapon_id, :armor1_id, ...
      # RGSS3: :equips

      # 初始化共享属性
      def initialize; @actor_id = 1; @level = 1; end

      # TestBattler 没有需要解包的名称
    end

    # -- 术语类 (Terms) --
    # 仅定义空类占位符，具体实现在 rgssX.rb 中
    class Terms; end

    # 注意: System 的 initialize 和 unpack_names 方法在 rgssX.rb 中定义，
    #       因为它们需要处理版本特定的属性和逻辑。
  end # System reopening

  # -- 动画类 (Animation) --
  # (RGSS2/3 结构，RGSS1 在 rgss1.rb 中覆盖)
  class Animation
    attr_accessor :id, :name
    attr_accessor :animation1_name, :animation1_hue # 动画文件1
    attr_accessor :animation2_name, :animation2_hue # 动画文件2
    attr_accessor :position, :frame_max             # 位置, 最大帧数
    attr_accessor :frames, :timings                 # 帧列表, 时序列表

    # 解包名称和动画文件名
    def unpack_names
      Utils.unpack_names_for(self, :name, :animation1_name, :animation2_name)
      # frames 和 timings 的解包在 rgssX.rb 的 Animation 类中递归处理
    end

    def initialize
      @id = 0; @name = ""; @animation1_name = ""; @animation1_hue = 0; @animation2_name = ""; @animation2_hue = 0
      @position = 1; @frame_max = 1; @frames = []; @timings = []
    end

    # -- 动画帧类 (Animation::Frame) --
    # (RGSS2/3 结构，RGSS1 在 rgss1.rb 中覆盖)
    class Frame
      attr_accessor :cell_max  # 最大单元数
      # @cell_data 在 rgssX.rb Mixin 中定义
      def initialize; @cell_max = 0; end # 初始化共享属性
      # Frame 没有名称需要解包
    end

    # -- 动画时序类 (Animation::Timing) --
    # (RGSS2/3 结构，RGSS1 在 rgss1.rb 中覆盖)
    class Timing
      attr_accessor :frame         # 触发帧
      attr_accessor :se            # 音效 (RPG::SE 对象)
      attr_accessor :flash_scope   # 闪烁范围
      attr_accessor :flash_color   # 闪烁颜色 (Color 对象)
      attr_accessor :flash_duration # 闪烁持续时间
      # RGSS1 特有属性 (在 rgss1.rb 中通过 Mixin 添加)
      # attr_accessor :condition

      # 解包 SE 文件名
      def unpack_names
        @se&.unpack_names
        # 注意: rgssX.rb 的 Timing 类会覆盖此方法
      end

      def initialize
        @frame = 0; @se = RPG::SE.new("", 80) # 默认音效
        @flash_scope = 0; @flash_color = Color.new([255.0, 255.0, 255.0, 255.0]) # 默认白色
        @flash_duration = 5
        # 其他属性在 rgssX.rb Mixin 中初始化
      end
    end # Timing
  end # Animation

  # -- 公共事件类 (CommonEvent) --
  class CommonEvent
    attr_accessor :id, :name, :trigger, :switch_id, :list # ID, 名称, 触发条件, 开关ID, 指令列表

    # 解包名称和指令列表
    def unpack_names
      Utils.unpack_names_for(self, :name)
      @list&.each { |c| c.unpack_names if c.respond_to?(:unpack_names) }
    end

    def initialize
      @id = 0; @name = ""; @trigger = 0 # 0:无, 1:自动执行, 2:并行处理
      @switch_id = 1; @list = [RPG::EventCommand.new]
    end

    # 辅助方法：判断是否自动执行
    def autorun?; @trigger == 1; end

    # 辅助方法：判断是否并行处理
    def parallel?; @trigger == 2; end
  end

  # -- 敌人队伍类 (Troop) --
  class Troop
    attr_accessor :id, :name, :members, :pages # ID, 名称, 成员列表, 战斗事件页列表

    # 解包名称和页面列表
    def unpack_names
      Utils.unpack_names_for(self, :name)
      @pages&.each { |p| p.unpack_names if p.respond_to?(:unpack_names) }
    end

    def initialize; @id = 0; @name = ""; @members = []; @pages = []; end

    # -- 队伍成员类 (Troop::Member) --
    # (RGSS2/3 结构，RGSS1 在 rgss1.rb 中覆盖)
    class Member
      attr_accessor :enemy_id, :x, :y, :hidden # 敌人ID, X坐标, Y坐标, 初始隐藏?
      # RGSS1/2 特有属性 (在 rgssX.rb 中通过 Mixin 添加)
      # attr_accessor :immortal

      def initialize; @enemy_id = 1; @x = 0; @y = 0; @hidden = false; end

      # Member 没有名称需要解包
    end

    # -- 战斗事件页面类 (Troop::Page) --
    class Page
      attr_accessor :condition, :span, :list # 条件, 执行时机, 指令列表

      # 解包指令列表
      def unpack_names
        @list&.each { |c| c.unpack_names if c.respond_to?(:unpack_names) }
      end

      def initialize
        @condition = RPG::Troop::Page::Condition.new
        @span = 0 # 0:回合结束, 1:瞬间, 2:战斗结束 (RGSS2/3)
        @list = [RPG::EventCommand.new]
      end

      # -- 战斗事件页面条件类 (Troop::Page::Condition) --
      # (RGSS2/3 结构，RGSS1 在 rgss1.rb 中覆盖)
      class Condition
        # 条件标志
        attr_accessor :turn_ending, :turn_valid, :enemy_valid, :actor_valid, :switch_valid
        # 回合结束时?, 回合条件有效?, 敌人条件有效?, 角色条件有效?, 开关条件有效?
        # 条件参数
        attr_accessor :turn_a, :turn_b          # 回合 A + B*X
        attr_accessor :enemy_index, :enemy_hp    # 敌人索引, 敌人 HP%
        attr_accessor :actor_id, :actor_hp      # 角色 ID, 角色 HP%
        attr_accessor :switch_id               # 开关 ID

        def initialize
          @turn_ending = false; @turn_valid = false; @enemy_valid = false; @actor_valid = false; @switch_valid = false
          @turn_a = 0; @turn_b = 0; @enemy_index = 0; @enemy_hp = 50
          @actor_id = 1; @actor_hp = 50; @switch_id = 1
        end
      end # Condition
    end # Page
  end # Troop
end # module RPG
