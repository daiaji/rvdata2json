# 包含 RGSS2 和 RGSS3 共用的类定义和基础模块

require "jsonable" # 假设 jsonable gem 提供了 to_json 支持
require_relative "utils" # 加载通用工具函数

# --- RPG 模块 ---
module RPG
  # 解包字符串 (委托给 Utils.unpack_string)
  # str: 需要解包的字符串 (通常是从 Marshal 加载的)
  # 返回: UTF-8 编码的字符串
  def self.unpack_str(str)
    Utils.unpack_string(str)
  end

  # --- pack_str 方法已移除，不再需要显式打包 ---

  # 辅助方法：如果实例变量存在，则移除它
  # obj: 目标对象
  # ivar_symbol: 实例变量的符号 (例如 :@features)
  def self.remove_ivar_if_exists(obj, ivar_symbol)
    obj.remove_instance_variable(ivar_symbol) if obj.instance_variable_defined?(ivar_symbol)
  end
end

# --- 基础数据结构 ---

# 颜色类 (用于表示 RGBA 颜色)
class Color
  include Jsonable # 混入 Jsonable 模块以支持 JSON 序列化
  attr_accessor :red, :green, :blue, :alpha # 定义颜色分量的访问器

  # 初始化 Color 对象
  # data: 包含 [red, green, blue, alpha] 的数组
  def initialize(data)
    @red, @green, @blue, @alpha = *data.map(&:to_f) # 将输入转换为浮点数并赋值
  end

  # 自定义 Marshal dump 方法
  # _limit: Marshal dump 的嵌套深度限制 (未使用)
  # 返回: 打包后的二进制字符串 (4个单精度浮点数)
  def _dump(_limit)
    [@red.to_f, @green.to_f, @blue.to_f, @alpha.to_f].pack("EEEE") # 确保是浮点数再打包
  end

  # 自定义 Marshal load 方法
  # obj: 从 Marshal 加载的二进制字符串
  # 返回: 新的 Color 对象
  def self._load(obj)
    new(obj.unpack("EEEE")) # 解包二进制数据并创建新对象
  end
end

# 表格类 (用于 RPG Maker 中的多维数组，如图块数据)
class Table
  include Jsonable
  attr_accessor :num_of_dimensions, :xsize, :ysize, :zsize, :num_of_elements # 维度、各维度大小、元素总数
  attr_reader :elements # 元素数组 (只读)

  # 初始化 Table 对象
  # data: 包含 [维度, x大小, y大小, z大小, 总数, ...元素] 的数组
  def initialize(data)
    dimensions, x, y, z, count, *elements_array = *data # 解构输入数组
    @num_of_dimensions = dimensions.to_i
    @xsize = x.to_i
    @ysize = y.to_i
    @zsize = z.to_i
    @num_of_elements = count.to_i
    actual_elements = elements_array.flatten.map(&:to_i) # 展平并转换为整数
    # 确保元素数量与 num_of_elements 匹配
    if actual_elements.size < @num_of_elements
      # 如果实际元素少于声明数量，用 0 填充
      actual_elements.fill(0, actual_elements.size, @num_of_elements - actual_elements.size)
    elsif actual_elements.size > @num_of_elements && @num_of_elements >= 0
      # 如果实际元素多于声明数量（且声明数量有效），截断
      actual_elements = actual_elements.slice(0, @num_of_elements)
    end
    @elements = @num_of_elements == 0 ? [] : actual_elements # 如果声明数量为0，则为空数组
  end

  # 自定义 Marshal dump 方法
  # 返回: 打包后的二进制字符串 (5个无符号32位整数 + N个无符号16位整数)
  def _dump(_limit)
    dump_elements = @elements.map(&:to_i) # 确保元素是整数
    [@num_of_dimensions, @xsize, @ysize, @zsize, @num_of_elements, *dump_elements].pack("VVVVVv*") # V = 32位无符号, v = 16位无符号
  end

  # 自定义 Marshal load 方法
  # obj: 从 Marshal 加载的二进制字符串
  # 返回: 新的 Table 对象
  def self._load(obj)
    new(obj.unpack("VVVVVv*")) # 解包二进制数据并创建新对象
  end

  # 获取指定位置的元素值 (支持1D, 2D, 3D)
  # x, y, z: 索引坐标
  # 返回: 元素值或 nil (如果索引越界)
  def [](x, y = 0, z = 0)
    index = x + y * @xsize + z * @xsize * @ysize # 计算一维索引
    # 边界检查
    return nil if x < 0 || (@num_of_dimensions >= 2 && y < 0) || (@num_of_dimensions >= 3 && z < 0)
    return nil if x >= @xsize || (@num_of_dimensions >= 2 && y >= @ysize) || (@num_of_dimensions >= 3 && z >= @zsize)
    return nil if index < 0 || index >= @num_of_elements
    @elements[index] # 返回对应索引的元素
  end

  # 设置指定位置的元素值 (支持1D, 2D, 3D)
  # args: 包含索引和新值的参数列表
  def []=(*args)
    value = args.pop.to_i # 最后一个参数是新值，确保是整数
    case @num_of_dimensions # 根据维度处理索引
    when 1
      raise ArgumentError, "1D Table 需要 1 个索引, 得到 #{args.size}" unless args.size == 1
      index = args[0]
      @elements[index] = value if index >= 0 && index < @num_of_elements # 边界检查后赋值
    when 2
      raise ArgumentError, "2D Table 需要 2 个索引, 得到 #{args.size}" unless args.size == 2
      x, y = args
      index = x + y * @xsize
      @elements[index] = value if x >= 0 && x < @xsize && y >= 0 && y < @ysize && index < @num_of_elements
    when 3
      raise ArgumentError, "3D Table 需要 3 个索引, 得到 #{args.size}" unless args.size == 3
      x, y, z = args
      index = x + y * @xsize + z * @xsize * @ysize
      @elements[index] = value if x >= 0 && x < @xsize && y >= 0 && y < @ysize && z >= 0 && z < @zsize && index < @num_of_elements
    else
      raise "无效的维度数量: #{@num_of_dimensions}"
    end
  end

  # 调整表格大小 (会清空所有元素)
  # x, y, z: 新的维度大小
  # 返回: self
  def resize(x, y = nil, z = nil)
    @xsize = x.to_i
    if y.nil? # 只有 x，则为 1D
      @num_of_dimensions = 1; @ysize = 1; @zsize = 1
    elsif z.nil? # 有 x 和 y，则为 2D
      @num_of_dimensions = 2; @ysize = y.to_i; @zsize = 1
    else # 有 x, y, z，则为 3D
      @num_of_dimensions = 3; @ysize = y.to_i; @zsize = z.to_i
    end
    raise ArgumentError, "Table 维度不能为负数" if @xsize < 0 || @ysize < 0 || @zsize < 0
    @num_of_elements = @xsize * @ysize * @zsize # 计算新的总元素数
    @elements = Array.new(@num_of_elements, 0) # 创建新的元素数组并填充 0
    self
  end
end

# 色调类 (用于屏幕/图片的色调调整)
class Tone
  include Jsonable
  attr_accessor :red, :green, :blue, :gray # 色调分量 (红, 绿, 蓝, 灰度)

  # 初始化 Tone 对象
  # data: 包含 [red, green, blue, gray] 的数组
  def initialize(data)
    @red, @green, @blue, @gray = *data.map(&:to_f) # 转换为浮点数并赋值
  end

  # 自定义 Marshal dump 方法
  # 返回: 打包后的二进制字符串 (4个单精度浮点数)
  def _dump(_limit)
    [@red.to_f, @green.to_f, @blue.to_f, @gray.to_f].pack("EEEE") # 确保是浮点数
  end

  # 自定义 Marshal load 方法
  # obj: 从 Marshal 加载的二进制字符串
  # 返回: 新的 Tone 对象
  def self._load(obj)
    new(obj.unpack("EEEE")) # 解包二进制数据并创建新对象
  end
end

# --- 基础 RPG Maker 类 ---

module RPG
  # 移动路线类 (用于角色或事件的移动路径)
  class MoveRoute
    include Jsonable
    attr_accessor :repeat, :skippable, :wait, :list # 是否重复, 是否可跳过, 是否等待完成, 移动指令列表

    # 初始化 MoveRoute 对象
    def initialize
      @repeat = true; @skippable = false; @wait = false
      @list = [RPG::MoveCommand.new] # 默认包含一个空指令
    end
  end

  # 移动指令类 (MoveRoute 中的单个指令)
  class MoveCommand
    include Jsonable
    attr_accessor :code, :parameters # 指令代码, 指令参数列表

    # 初始化 MoveCommand 对象
    # code: 指令代码 (整数)
    # parameters: 参数数组
    def initialize(code = 0, parameters = [])
      @code = code
      @parameters = parameters # Restorer 会处理参数的递归恢复
    end
  end

  # 事件指令类 (事件页面中的指令)
  class EventCommand
    include Jsonable
    attr_accessor :code, :indent, :parameters # 指令代码, 缩进级别, 指令参数列表

    # 解包参数中的字符串 (由 JsonExporter 调用)
    # rgss_version: RGSS 版本号 (可能影响特定指令参数的处理，虽然这里没用到)
    def unpack_names(rgss_version)
      return unless @parameters.is_a?(Array) # 仅处理数组类型的参数
      @parameters.map! do |param|
        # 如果参数是字符串，则使用 RPG.unpack_str 解包，否则保持不变
        param.is_a?(String) ? RPG.unpack_str(param) : param
      end
    end

    # 初始化 EventCommand 对象
    # code: 指令代码
    # indent: 缩进级别
    # parameters: 参数数组
    def initialize(code = 0, indent = 0, parameters = [])
      @code = code; @indent = indent; @parameters = parameters
    end
  end

  # 地图信息类 (用于 MapInfos.rvdata2，存储地图树状结构和基本信息)
  class MapInfo
    include Jsonable
    attr_accessor :name, :parent_id, :order, :expanded, :scroll_x, :scroll_y # 地图名, 父地图ID, 顺序, 是否展开, 滚动位置X, 滚动位置Y

    # 解包地图名称 (由 JsonExporter 调用)
    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name) # 使用 Utils 解包 @name
    end

    # 初始化 MapInfo 对象
    def initialize
      @name = ""; @parent_id = 0; @order = 0
      @expanded = false; @scroll_x = 0; @scroll_y = 0
    end
  end

  # 事件类 (地图上的可交互对象)
  class Event
    include Jsonable
    attr_accessor :id, :name, :x, :y, :pages # 事件ID, 事件名, X坐标, Y坐标, 事件页面列表

    # 解包事件名称 (由 JsonExporter 调用)
    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name) # 解包 @name
      # pages 属性由 JsonExporter 递归处理其内部需要解包的字符串
    end

    # 初始化 Event 对象
    # x, y: 初始坐标
    def initialize(x = 0, y = 0) # 此处初始化不需要版本号
      @id = 0; @name = ""; @x = x; @y = y
      @pages = [RPG::Event::Page.new] # 默认包含一个事件页面
    end

    # 事件页面类
    class Page
      include Jsonable
      # 定义页面属性
      attr_accessor :condition, :graphic, :move_type, :move_speed, :move_frequency, :move_route
      attr_accessor :walk_anime, :step_anime, :direction_fix, :through, :priority_type, :trigger, :list # 条件, 图形, 移动类型, 速度, 频率, 移动路线, 行走图动画,踏步动画, 固定朝向, 穿透, 优先级, 触发方式, 事件指令列表

      # 解包页面内的字符串 (此方法目前为空，因为主要字符串在 graphic 和 list 中，由 JsonExporter 递归处理)
      def unpack_names(rgss_version)
        # graphic 和 list 由 JsonExporter 递归处理
      end

      # 初始化 Page 对象
      def initialize # 此处初始化不需要版本号
        @condition = RPG::Event::Page::Condition.new # 初始化条件
        @graphic = RPG::Event::Page::Graphic.new   # 初始化图形
        @move_type = 0; @move_speed = 3; @move_frequency = 3 # 移动相关默认值
        @move_route = RPG::MoveRoute.new           # 初始化移动路线
        @walk_anime = true; @step_anime = false; @direction_fix = false; @through = false # 动画和穿透默认值
        @priority_type = 0; @trigger = 0           # 优先级和触发方式默认值
        @list = [RPG::EventCommand.new]            # 默认包含一个空指令
      end

      # 事件页面条件类
      class Condition
        include Jsonable
        # 定义条件属性
        attr_accessor :switch1_valid, :switch2_valid, :variable_valid, :self_switch_valid # 开关1/2有效, 变量有效, 独立开关有效
        attr_accessor :item_valid, :actor_valid # 物品有效, 角色有效 (RGSS2/3 共用)
        attr_accessor :switch1_id, :switch2_id, :variable_id, :variable_value # 开关1/2 ID, 变量ID, 变量值
        attr_accessor :self_switch_ch, :item_id, :actor_id # 独立开关字母, 物品ID, 角色ID

        # 初始化 Condition 对象
        def initialize # 此处初始化不需要版本号
          @switch1_valid = false; @switch2_valid = false; @variable_valid = false; @self_switch_valid = false
          @item_valid = false; @actor_valid = false
          @switch1_id = 1; @switch2_id = 1; @variable_id = 1; @variable_value = 0
          @self_switch_ch = "A"; @item_id = 1; @actor_id = 1
        end
      end # Condition

      # 事件页面图形类
      class Graphic
        include Jsonable
        # 定义图形属性
        attr_accessor :tile_id, :character_name, :character_index, :direction, :pattern # 图块ID, 行走图文件名, 行走图索引, 方向, 动画帧

        # 解包行走图文件名 (由 JsonExporter 调用)
        def unpack_names(rgss_version)
          Utils.unpack_names_for(self, :character_name) # 解包 @character_name
        end

        # 初始化 Graphic 对象
        def initialize # 此处初始化不需要版本号
          @tile_id = 0; @character_name = ""; @character_index = 0; @direction = 2; @pattern = 0
        end
      end # Graphic
    end # Page
  end # Event

  # 音频文件基类 (BGM, BGS, ME, SE 的父类)
  class AudioFile
    include Jsonable
    attr_accessor :name, :volume, :pitch # 文件名, 音量, 音调

    # 解包音频文件名 (由 JsonExporter 调用)
    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name) # 解包 @name
    end

    # 初始化 AudioFile 对象
    # name: 文件名
    # volume: 音量 (0-100)
    # pitch: 音调 (50-150)
    def initialize(name = "", volume = 100, pitch = 100)
      @name = name.to_s; @volume = volume.to_i; @pitch = pitch.to_i # 确保类型正确
    end
  end

  # BGM (背景音乐) 类
  class BGM < RPG::AudioFile
    @@last = RPG::BGM.new # 类变量，用于存储最后播放的 BGM (用于 replay)
    attr_accessor :pos # RGSS3: 播放位置 (用于 replay)

    # 播放 BGM
    # pos: RGSS3 的播放位置
    def play(pos = 0); @@last = self.dup rescue self; @pos = pos if respond_to?(:pos=); end # 记录当前 BGM 到 @@last
    # 重新播放上次的 BGM
    def replay; play(@pos || 0); end

    # 停止播放 BGM
    def self.stop; @@last = RPG::BGM.new; end
    # 淡出 BGM
    def self.fade(_time); @@last = RPG::BGM.new; end # 淡出效果实现通常在游戏引擎内部，这里仅重置 @@last
    # 获取最后播放的 BGM
    def self.last; @@last; end
  end

  # BGS (背景音效) 类
  class BGS < RPG::AudioFile
    @@last = RPG::BGS.new # 类变量，用于存储最后播放的 BGS
    attr_accessor :pos # RGSS3: 播放位置

    # 播放 BGS
    def play(pos = 0); @@last = self.dup rescue self; @pos = pos if respond_to?(:pos=); end

    # 重新播放上次的 BGS
    def replay; play(@pos || 0); end

    # 停止播放 BGS
    def self.stop; @@last = RPG::BGS.new; end
    # 淡出 BGS
    def self.fade(_time); @@last = RPG::BGS.new; end
    # 获取最后播放的 BGS
    def self.last; @@last; end
  end

  # ME (音乐效果) 类
  class ME < RPG::AudioFile; def play; end; def self.stop; end; def self.fade(_time); end; end # 方法为空，具体实现在引擎
  # SE (音效) 类
  class SE < RPG::AudioFile; def play; end; def self.stop; end; end # 方法为空，具体实现在引擎

  # 地图类
  class Map
    include Jsonable
    # 定义所有可能的属性 (RGSS2 和 RGSS3)
    attr_accessor :display_name, :tileset_id, :specify_battleback # RGSS3: 显示名称, 图块集ID, 指定战斗背景
    attr_accessor :battleback1_name, :battleback2_name, :note      # RGSS3: 战斗背景1/2文件名, 备注
    attr_accessor :width, :height, :scroll_type, :autoplay_bgm, :bgm, :autoplay_bgs, :bgs # 宽高, 滚动类型, 自动播放BGM/BGS, BGM/BGS对象
    attr_accessor :disable_dashing, :encounter_list, :encounter_step, :parallax_name # 禁止冲刺, 遇敌列表, 遇敌步数, 远景图文件名
    attr_accessor :parallax_loop_x, :parallax_loop_y, :parallax_sx, :parallax_sy, :parallax_show # 远景图循环X/Y, 滚动速度X/Y, 显示远景图
    attr_accessor :data, :events # 地图图块数据 (Table), 地图事件 (Hash {id => Event})

    # 解包地图内的字符串 (由 JsonExporter 调用)
    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :parallax_name) # 解包 @parallax_name
      # bgm, bgs, events, encounter_list 由 JsonExporter 递归处理

      # 根据 RGSS 版本解包特定字符串
      if rgss_version == "RGSS3"
        Utils.unpack_names_for(self, :display_name, :battleback1_name, :battleback2_name, :note) # 解包 RGSS3 特有字符串
      else # RGSS2
        # 除了 parallax_name，RGSS2 Map 对象本身没有其他需要直接解包的顶层字符串属性
      end
    end

    # 初始化 Map 对象
    # width, height: 地图宽高
    # rgss_version: RGSS 版本号，用于确定 data 表格的维度和特定属性的初始化
    def initialize(width = 17, height = 13, rgss_version = "RGSS3")
      # 通用默认值
      @width = width; @height = height; @scroll_type = 0
      @autoplay_bgm = false; @bgm = RPG::BGM.new
      @autoplay_bgs = false; @bgs = RPG::BGS.new
      @disable_dashing = false; @encounter_step = 30
      @parallax_name = ""; @parallax_loop_x = false; @parallax_loop_y = false
      @parallax_sx = 0; @parallax_sy = 0; @parallax_show = false
      @events = {} # 事件始终是哈希表

      # 根据版本设置特定默认值
      if rgss_version == "RGSS3"
        @display_name = ""
        @tileset_id = 1
        @specify_battleback = false
        @battleback1_name = ""
        @battleback2_name = ""
        @note = ""
        # RGSS3 地图数据: 4 层 (3 图块层 + 1 区域ID层)
        @data = Table.new([4, @width, @height, 1, @width * @height * 4])
        @encounter_list = [] # RGSS3 遇敌列表是 RPG::Map::Encounter 对象数组
      else # RGSS2
        # 确保 RGSS3 属性不存在 (设为 nil)
        @display_name = @tileset_id = @specify_battleback = nil
        @battleback1_name = @battleback2_name = @note = nil
        # RGSS2 地图数据: 3 层 (图块层)
        @data = Table.new([3, @width, @height, 1, @width * @height * 3])
        @encounter_list = [] # RGSS2 遇敌列表是 [troop_id, weight, ???] 形式的简单数组
      end
    end
  end # Map

  # 基础物品/技能/职业等的基类 (数据库中大部分项目的父类)
  class BaseItem
    include Jsonable
    attr_accessor :id, :name, :icon_index, :description, :note # ID, 名称, 图标索引, 描述, 备注
    attr_accessor :features # RGSS3: 特性列表

    # 解包通用字符串属性 (由 JsonExporter 调用)
    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name, :description, :note) # 解包名称、描述、备注
      # features 由 JsonExporter 递归处理
    end

    # 初始化 BaseItem 对象
    # rgss_version: RGSS 版本号，用于确定是否初始化 @features
    def initialize(rgss_version = "RGSS3")
      @id = 0; @name = ""; @icon_index = 0; @description = ""; @note = ""
      # 根据版本初始化 features
      @features = (rgss_version == "RGSS3") ? [] : nil # RGSS3 有 features，RGSS2 没有
    end
  end # BaseItem

  # 可使用物品/技能的基类 (继承自 BaseItem)
  class UsableItem < RPG::BaseItem
    # 定义所有可能的属性 (RGSS2 和 RGSS3)
    attr_accessor :scope, :occasion, :speed, :animation_id # 共用: 范围, 使用时机, 速度修正, 动画ID
    attr_accessor :common_event_id, :base_damage, :variance, :atk_f, :spi_f # RGSS2: 公共事件ID, 基础伤害, 分散度, 攻击力F, 精神力F
    attr_accessor :physical_attack, :damage_to_mp, :absorb_damage, :ignore_defense # RGSS2: 物理攻击, 伤害MP, 吸收伤害, 无视防御
    attr_accessor :element_set, :plus_state_set, :minus_state_set # RGSS2: 元素集合, 添加状态集合, 解除状态集合
    attr_accessor :success_rate, :repeats, :tp_gain, :hit_type # RGSS3: 成功率, 连续次数, TP获得量, 命中类型
    attr_accessor :damage, :effects # RGSS3: 伤害数据 (对象), 效果列表 (对象数组)

    # 解包字符串 (由 JsonExporter 调用)
    def unpack_names(rgss_version)
      # 父类 BaseItem 的 unpack_names 会处理 :name, :description, :note
      super(rgss_version) # 调用父类方法
      # damage/effects 由 JsonExporter 递归处理
      # 特别处理 RGSS3 的伤害公式字符串
      if rgss_version == "RGSS3" && @damage.respond_to?(:unpack_names)
        @damage.unpack_names(rgss_version) # 调用 Damage 对象的 unpack_names 解包公式
      end
    end

    # 初始化 UsableItem 对象
    # rgss_version: RGSS 版本号，用于确定初始化哪些属性
    def initialize(rgss_version = "RGSS3")
      super(rgss_version) # 调用父类 BaseItem 的初始化
      # 通用默认值
      @scope = 0; @occasion = 0; @speed = 0; @animation_id = 0

      # 根据版本设置特定默认值
      if rgss_version == "RGSS3"
        @success_rate = 100
        @repeats = 1
        @tp_gain = 0
        @hit_type = 0
        @damage = RPG::UsableItem::Damage.new # 必须实例化 Damage 对象
        @effects = []                         # 初始化效果数组
        # 确保 RGSS2 属性为 nil
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
        # 确保 RGSS3 属性为 nil
        @success_rate = @repeats = @tp_gain = @hit_type = nil
        @damage = @effects = nil
      end
    end

    # RGSS2 辅助方法: 判断是否对敌方使用 (保留，如果需要跨版本兼容性检查)
    def for_opponent?; respond_to?(:physical_attack) && [1, 2, 3, 4, 5, 6].include?(@scope); end

    # RGSS2 辅助方法: 判断是否对友方使用
    def for_friend?; respond_to?(:physical_attack) && [7, 8, 9, 10, 11].include?(@scope); end

    # RGSS2 辅助方法: 判断是否对单个友方使用
    def for_friend_hp?; respond_to?(:physical_attack) && [7, 9, 11].include?(@scope); end

    # RGSS2 辅助方法: 判断是否对全体友方使用
    def for_friend_all?; respond_to?(:physical_attack) && [8, 10].include?(@scope); end

    # RGSS2 辅助方法: 判断是否对自身使用
    def for_user?; respond_to?(:physical_attack) && @scope == 12; end

    # RGSS2 辅助方法: 判断是否为全体效果
    def for_all?; respond_to?(:physical_attack) && [2, 8, 10].include?(@scope); end

    # RGSS2 辅助方法: 判断是否对单个目标
    def for_one?; respond_to?(:physical_attack) && [1, 3, 4, 5, 6, 7, 9, 11, 12].include?(@scope); end

    # RGSS2 辅助方法: 判断是否需要指定目标
    def need_selection?; respond_to?(:physical_attack) && [1, 3, 4, 5, 6, 7, 9].include?(@scope); end
  end # UsableItem

  # 系统设定类 (System.rvdata2)
  class System
    include Jsonable
    # 定义所有可能的属性 (RGSS2 和 RGSS3)
    attr_accessor :japanese, :currency_unit, :skill_types, :weapon_types, :armor_types # RGSS3: 日文模式?, 货币单位, 技能/武器/防具类型列表
    attr_accessor :title1_name, :title2_name, :opt_draw_title, :opt_use_midi, :opt_transparent # RGSS3: 标题图1/2, 绘制标题?, 使用MIDI?, 窗口透明?
    attr_accessor :opt_followers, :opt_slip_death, :opt_floor_death, :opt_display_tp, :opt_extra_exp # RGSS3: 允许队员跟随?, 中毒致死?, 地形伤害致死?, 显示TP?, 额外经验?
    attr_accessor :window_tone, :battleback1_name, :battleback2_name # RGSS3: 窗口色调, 默认战斗背景1/2
    attr_accessor :passages # RGSS2 (可能存在，但通常在 Tilesets 中处理?) - 通常为 nil
    attr_accessor :game_title, :version_id, :party_members, :elements, :switches, :variables # 共用: 游戏标题, 版本ID, 初始队伍, 元素/开关/变量列表
    attr_accessor :boat, :ship, :airship, :title_bgm, :battle_bgm, :battle_end_me, :gameover_me # 共用: 交通工具对象, 标题/战斗BGM, 战斗结束/游戏结束ME
    attr_accessor :sounds, :test_battlers, :test_troop_id, :start_map_id, :start_x, :start_y # 共用: 系统音效列表, 战斗测试角色列表, 测试队伍ID, 初始地图/坐标
    attr_accessor :terms, :battler_name, :battler_hue, :edit_map_id, :magic_number # 共用: 术语对象, 默认战斗图文件名/色相, 编辑器地图ID, 魔术数字(内部版本号?)

    # 解包系统内的字符串 (由 JsonExporter 调用)
    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :game_title) # 解包游戏标题
      # boat, ship, airship, bgm, etc., terms, sounds, test_battlers 由 JsonExporter 递归处理

      # 根据版本解包特定数组/字符串
      if rgss_version == "RGSS3"
        Utils.unpack_names_for(self, :currency_unit, :title1_name, :title2_name,
                               :battleback1_name, :battleback2_name, :battler_name) # 解包 RGSS3 特有字符串
        # 解包 RGSS3 的各种类型列表 (元素, 技能类型, 武器类型, 防具类型, 开关名, 变量名)
        [:@elements, :@skill_types, :@weapon_types, :@armor_types, :@switches, :@variables].each do |ivar|
          array = instance_variable_get(ivar)
          # 对数组中的每个字符串元素进行解包
          array.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item } if array.is_a?(Array)
        end
        # 解包 RGSS3 的术语
        @terms&.unpack_names(rgss_version)
      else # RGSS2
        Utils.unpack_names_for(self, :battler_name) # 解包 RGSS2 战斗图文件名
        # 解包 RGSS2 的元素/开关/变量列表
        [:@elements, :@switches, :@variables].each do |ivar|
          array = instance_variable_get(ivar)
          array.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item } if array.is_a?(Array)
        end
        # 解包 RGSS2 的术语
        @terms&.unpack_names(rgss_version)
      end
    end

    # 初始化 System 对象
    # rgss_version: RGSS 版本号，用于确定初始化哪些属性
    def initialize(rgss_version = "RGSS3")
      # 通用默认值
      @game_title = ""; @version_id = 0; @party_members = [1] # 初始队伍只包含 ID 为 1 的角色
      @switches = [nil, ""]; @variables = [nil, ""] # 开关/变量列表，索引0为nil，索引1为空字符串
      @boat = RPG::System::Vehicle.new; @ship = RPG::System::Vehicle.new; @airship = RPG::System::Vehicle.new # 初始化交通工具
      @title_bgm = RPG::BGM.new; @battle_bgm = RPG::BGM.new # 初始化 BGM
      @battle_end_me = RPG::ME.new; @gameover_me = RPG::ME.new # 初始化 ME
      @test_battlers = []; @test_troop_id = 1 # 初始化战斗测试
      @start_map_id = 1; @start_x = 0; @start_y = 0 # 初始化玩家初始位置
      @edit_map_id = 1; @magic_number = 0 # 编辑器相关，魔术数字默认为 0

      # 根据版本设置特定默认值
      if rgss_version == "RGSS3"
        @japanese = true; @currency_unit = "" # RGSS3 特有选项
        @skill_types = [nil, ""]; @weapon_types = [nil, ""]; @armor_types = [nil, ""] # 初始化类型列表
        @elements = [nil, ""] # 元素列表
        @title1_name = ""; @title2_name = "" # 标题图
        @opt_draw_title = true; @opt_use_midi = false; @opt_transparent = false # 选项默认值
        @opt_followers = true; @opt_slip_death = false; @opt_floor_death = false # 选项默认值
        @opt_display_tp = true; @opt_extra_exp = false # 选项默认值
        @window_tone = Tone.new([0.0, 0.0, 0.0, 0.0]) # 默认窗口色调 (黑色)
        @sounds = Array.new(24) { RPG::SE.new } # RGSS3 有 24 个系统音效
        @terms = RPG::System::Terms.new(rgss_version) # 初始化 RGSS3 术语对象
        @battleback1_name = ""; @battleback2_name = "" # 默认战斗背景
        @battler_name = ""; @battler_hue = 0 # 默认战斗图
        @magic_number = 1 # RGSS3 的魔术数字通常是 1 或其他非零值
        @passages = nil # 确保 RGSS3 没有 passages 属性
      else # RGSS2
        @elements = [nil, ""] # RGSS2 元素列表
        @passages = nil # 通常为 nil
        @sounds = Array.new(20) { RPG::SE.new } # RGSS2 有 20 个系统音效
        @terms = RPG::System::Terms.new(rgss_version) # 初始化 RGSS2 术语对象
        @battler_name = ""; @battler_hue = 0 # 默认战斗图
        # 确保 RGSS3 属性为 nil
        @japanese = @currency_unit = @skill_types = @weapon_types = @armor_types = nil
        @title1_name = @title2_name = @opt_draw_title = @opt_use_midi = @opt_transparent = nil
        @opt_followers = @opt_slip_death = @opt_floor_death = @opt_display_tp = @opt_extra_exp = nil
        @window_tone = @battleback1_name = @battleback2_name = nil
      end
    end

    # 嵌套类：交通工具
    class Vehicle
      include Jsonable
      attr_accessor :character_name, :character_index, :bgm, :start_map_id, :start_x, :start_y # 行走图文件名/索引, BGM, 起始地图/坐标

      # 解包交通工具的行走图文件名
      def unpack_names(rgss_version)
        Utils.unpack_names_for(self, :character_name)
        # bgm 由 JsonExporter 递归处理
      end

      # 初始化 Vehicle 对象
      def initialize # 此处初始化不需要版本号
        @character_name = ""; @character_index = 0; @bgm = RPG::BGM.new
        @start_map_id = 0; @start_x = 0; @start_y = 0
      end
    end # Vehicle

    # 嵌套类：术语
    class Terms
      include Jsonable
      # 定义所有可能的术语属性
      attr_accessor :basic, :params, :etypes, :commands # RGSS3: 基本状态, 能力值, 装备类型, 指令名称 (都是数组)
      attr_accessor :level, :level_a, :hp, :hp_a, :mp, :mp_a, :atk, :def, :spi, :agi # RGSS2: 等级(缩写), HP(缩写), MP(缩写), 攻击, 防御, 精神, 敏捷
      attr_accessor :weapon, :armor1, :armor2, :armor3, :armor4, :weapon1, :weapon2 # RGSS2: 武器, 盾, 头, 身体, 饰品, 武器1/2 (双刀流?)
      attr_accessor :attack, :skill, :guard, :item, :equip, :status, :save, :game_end # RGSS2: 攻击, 技能, 防御, 物品, 装备, 状态, 保存, 游戏结束
      attr_accessor :fight, :escape, :new_game, :continue, :shutdown, :to_title, :cancel, :gold # RGSS2: 战斗, 逃跑, 新游戏, 继续, 退出, 回到标题, 取消, 货币单位

      # 解包术语字符串
      def unpack_names(rgss_version)
        if rgss_version == "RGSS3"
          # 解包 RGSS3 的术语数组
          [:@basic, :@params, :@etypes, :@commands].each do |ivar|
            array = instance_variable_get(ivar)
            array.map! { |item| item.is_a?(String) ? RPG.unpack_str(item) : item } if array.is_a?(Array)
          end
        else # RGSS2
          # 解包 RGSS2 的所有实例变量（如果是字符串）
          instance_variables.each do |ivar|
            # 跳过 RGSS3 特有的数组属性
            next if [:@basic, :@params, :@etypes, :@commands].include?(ivar)
            value = instance_variable_get(ivar)
            instance_variable_set(ivar, RPG.unpack_str(value)) if value.is_a?(String)
          end
        end
      end

      # 初始化 Terms 对象
      def initialize(rgss_version = "RGSS3")
        if rgss_version == "RGSS3"
          @basic = Array.new(8) { "" }  # 等级, HP, MP, TP, 经验值, 下一级经验
          @params = Array.new(8) { "" } # MHP, MMP, ATK, DEF, MAT, MDF, AGI, LUK
          @etypes = Array.new(5) { "" } # 武器, 盾, 头, 身体, 饰品
          @commands = Array.new(23) { "" } # 战斗指令, 菜单指令等
          # 确保 RGSS2 属性为 nil
          @level = @level_a = @hp = @hp_a = @mp = @mp_a = @atk = @def = @spi = @agi = nil
          @weapon = @armor1 = @armor2 = @armor3 = @armor4 = @weapon1 = @weapon2 = nil
          @attack = @skill = @guard = @item = @equip = @status = @save = @game_end = nil
          @fight = @escape = @new_game = @continue = @shutdown = @to_title = @cancel = @gold = nil
        else # RGSS2
          # 初始化 RGSS2 的术语字符串
          @level = ""; @level_a = ""; @hp = ""; @hp_a = ""; @mp = ""; @mp_a = ""
          @atk = ""; @def = ""; @spi = ""; @agi = ""
          @weapon = ""; @armor1 = ""; @armor2 = ""; @armor3 = ""; @armor4 = ""
          @weapon1 = ""; @weapon2 = "" # VX Ace 中移除，VX 中存在
          @attack = ""; @skill = ""; @guard = ""; @item = ""
          @equip = ""; @status = ""; @save = ""; @game_end = ""
          @fight = ""; @escape = ""
          @new_game = ""; @continue = ""; @shutdown = ""
          @to_title = ""; @cancel = ""; @gold = ""
          # 确保 RGSS3 属性为 nil
          @basic = @params = @etypes = @commands = nil
        end
      end
    end # Terms

    # 嵌套类：战斗测试角色
    class TestBattler
      include Jsonable
      attr_accessor :actor_id, :level # 角色ID, 等级
      attr_accessor :equips # RGSS3: 装备ID列表 [武器, 盾, 头, 身体, 饰品]
      attr_accessor :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id # RGSS2: 各部位装备ID

      # 初始化 TestBattler 对象
      # rgss_version: 用于确定初始化 RGSS3 的 equips 还是 RGSS2 的独立装备ID
      def initialize(rgss_version = "RGSS3") # RvdataRestorer 在恢复时会传递正确的版本
        @actor_id = 1; @level = 1
        if rgss_version == "RGSS3"
          @equips = [0, 0, 0, 0, 0] # 初始化 RGSS3 装备数组
          # 确保 RGSS2 属性为 nil
          @weapon_id = @armor1_id = @armor2_id = @armor3_id = @armor4_id = nil
        else # RGSS2
          @weapon_id = 0; @armor1_id = 0; @armor2_id = 0; @armor3_id = 0; @armor4_id = 0 # 初始化 RGSS2 装备ID
          # 确保 RGSS3 属性为 nil
          @equips = nil
        end
      end
    end # TestBattler
  end # System

  # 动画类 (Animations.rvdata2)
  class Animation
    include Jsonable
    attr_accessor :id, :name, :animation1_name, :animation1_hue, :animation2_name, :animation2_hue # ID, 名称, 动画图像1/2文件名及色相
    attr_accessor :position, :frame_max, :frames, :timings # 播放位置, 最大帧数, 帧数据列表, 时间设定列表

    # 解包动画相关的字符串
    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name, :animation1_name, :animation2_name) # 解包名称和文件名
      # frames 和 timings 由 JsonExporter 递归处理
    end

    # 初始化 Animation 对象
    def initialize # Frame 的初始化依赖版本，由 RvdataRestorer 处理
      @id = 0; @name = ""; @animation1_name = ""; @animation1_hue = 0
      @animation2_name = ""; @animation2_hue = 0; @position = 1; @frame_max = 1
      @frames = []; @timings = [] # 帧和时间列表由 RvdataRestorer 填充
    end

    # 嵌套类：动画帧
    class Frame
      include Jsonable
      attr_accessor :cell_max, :cell_data # 最大单元格数, 单元格数据 (RGSS2 为 Table, RGSS3 为 Array)

      # 初始化 Frame 对象
      # rgss_version: 用于确定 cell_data 的类型
      def initialize(rgss_version = "RGSS3") # RvdataRestorer 在恢复时会传递正确的版本
        @cell_max = 0
        # 根据版本初始化 cell_data
        @cell_data = (rgss_version == "RGSS3") ? nil : Table.new([2, 0, 0, 1, 0]) # RGSS3 为 nil (由恢复器填充数组), RGSS2 为空 Table
      end
    end # Frame

    # 嵌套类：动画时间设定 (控制音效和闪烁)
    class Timing
      include Jsonable
      attr_accessor :frame, :se, :flash_scope, :flash_color, :flash_duration # 发生帧, 音效(SE), 闪烁范围, 闪烁颜色(Color), 闪烁持续时间

      # 解包时间设定中的字符串 (目前只有 SE 文件名需要)
      def unpack_names(rgss_version)
        # se (RPG::SE 对象) 由 JsonExporter 递归处理
      end

      # 初始化 Timing 对象
      def initialize # 此处初始化不需要版本号
        @frame = 0; @se = RPG::SE.new("", 80) # 默认空 SE, 音量 80
        @flash_scope = 0; @flash_color = Color.new([255.0, 255.0, 255.0, 255.0]); @flash_duration = 5 # 默认白色闪烁
      end
    end # Timing
  end # Animation

  # 公共事件类 (CommonEvents.rvdata2)
  class CommonEvent
    include Jsonable
    attr_accessor :id, :name, :trigger, :switch_id, :list # ID, 名称, 触发方式, 触发开关ID, 事件指令列表

    # 解包公共事件名称
    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name) # 解包 @name
      # list 由 JsonExporter 递归处理
    end

    # 初始化 CommonEvent 对象
    def initialize # 此处初始化不需要版本号
      @id = 0; @name = ""; @trigger = 0; @switch_id = 1 # 默认无触发, 开关ID为1
      @list = [RPG::EventCommand.new] # 默认包含一个空指令
    end

    # 判断是否自动执行
    def autorun?; @trigger == 1; end

    # 判断是否并行处理
    def parallel?; @trigger == 2; end
  end # CommonEvent

  # 队伍类 (Troops.rvdata2)
  class Troop
    include Jsonable
    attr_accessor :id, :name, :members, :pages # ID, 名称, 敌人成员列表, 事件页面列表

    # 解包队伍名称
    def unpack_names(rgss_version)
      Utils.unpack_names_for(self, :name) # 解包 @name
      # members 和 pages 由 JsonExporter 递归处理
    end

    # 初始化 Troop 对象
    def initialize # Member 的初始化依赖版本，由 RvdataRestorer 处理
      @id = 0; @name = ""
      @members = []; @pages = [] # 成员和页面列表由 RvdataRestorer 填充
    end

    # 嵌套类：队伍成员 (敌人)
    class Member
      include Jsonable
      attr_accessor :enemy_id, :x, :y, :hidden # 敌人ID, X坐标, Y坐标, 是否隐藏
      attr_accessor :immortal # RGSS2: 是否不死

      # 初始化 Member 对象
      # rgss_version: 用于确定是否初始化 RGSS2 的 immortal 属性
      def initialize(rgss_version = "RGSS3") # RvdataRestorer 在恢复时会传递正确的版本
        @enemy_id = 1; @x = 0; @y = 0; @hidden = false
        # 根据版本初始化 immortal
        @immortal = (rgss_version == "RGSS2") ? false : nil # RGSS2 有 immortal，RGSS3 没有
      end
    end # Member

    # 嵌套类：队伍事件页面
    class Page
      include Jsonable
      attr_accessor :condition, :span, :list # 页面条件, 执行时机, 事件指令列表

      # 解包页面内的字符串 (目前为空，list 由 JsonExporter 递归处理)
      def unpack_names(rgss_version)
        # list 由 JsonExporter 递归处理
      end

      # 初始化 Page 对象
      def initialize # 此处初始化不需要版本号
        @condition = RPG::Troop::Page::Condition.new # 初始化条件
        @span = 0 # 默认只执行一次
        @list = [RPG::EventCommand.new] # 默认包含一个空指令
      end

      # 嵌套类：队伍事件页面条件
      class Condition
        include Jsonable
        # 定义条件属性
        attr_accessor :turn_ending, :turn_valid, :enemy_valid, :actor_valid, :switch_valid # 回合结束?, 回合有效?, 敌人有效?, 角色有效?, 开关有效?
        attr_accessor :turn_a, :turn_b, :enemy_index, :enemy_hp, :actor_id, :actor_hp, :switch_id # 回合数A/B, 敌人索引/HP, 角色ID/HP, 开关ID

        # 初始化 Condition 对象
        def initialize # 此处初始化不需要版本号
          # 默认所有条件无效
          @turn_ending = false; @turn_valid = false; @enemy_valid = false
          @actor_valid = false; @switch_valid = false
          # 条件参数默认值
          @turn_a = 0; @turn_b = 0; @enemy_index = 0; @enemy_hp = 50
          @actor_id = 1; @actor_hp = 50; @switch_id = 1
        end
      end # Condition
    end # Page
  end # Troop
end # RPG

# 矩形类 (用于表示坐标和范围)
class Rect
  include Jsonable
  attr_accessor :x, :y, :width, :height # X坐标, Y坐标, 宽度, 高度

  # 初始化 Rect 对象
  def initialize(x = 0, y = 0, width = 0, height = 0)
    set(x, y, width, height) # 调用 set 方法进行赋值
  end

  # 自定义 Marshal dump 方法
  # 返回: 打包后的二进制字符串 (4个有符号32位整数)
  def _dump(_limit)
    [@x.to_i, @y.to_i, @width.to_i, @height.to_i].pack("iiii") # 确保是整数
  end

  # 自定义 Marshal load 方法
  # obj: 从 Marshal 加载的二进制字符串
  # 返回: 新的 Rect 对象
  def self._load(obj)
    new(*obj.unpack("iiii")) # 解包二进制数据并创建新对象
  end

  # 设置矩形的属性
  def set(x, y, width, height); @x = x.to_i; @y = y.to_i; @width = width.to_i; @height = height.to_i; self; end

  # 将矩形置空 (所有属性设为0)
  def empty; set(0, 0, 0, 0); end

  # 返回矩形的字符串表示
  def to_s; "(#{@x}, #{@y}, #{@width}, #{@height})"; end
end
