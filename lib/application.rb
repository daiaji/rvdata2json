# 应用主流程控制

require "optparse"   # 用于解析命令行参数
require "pathname"   # 用于处理文件路径
require "find"       # 用于递归查找文件
require "fileutils"  # 用于文件操作，如创建目录
require "inifile"    # 用于解析 Game.ini 文件
require "set"        # 用于高效处理集合

# --- 尽早加载日志模块 ---
require_relative "logging"
# -----------------------

require_relative "configuration" # 加载配置管理模块
require_relative "converter"     # 加载核心转换模块
require_relative "utils"         # 加载通用工具模块

# --- 主应用程序类 ---
class Application
  # 支持的 RGSS 版本列表
  RGSS_VERSIONS = %w[RGSS1 RGSS2 RGSS3].freeze
  # Scripts 文件的基础名 (用于特殊处理)
  SCRIPTS_BASENAME = "scripts".freeze

  # 初始化应用程序
  # @param argv [Array<String>] 命令行参数数组
  def initialize(argv)
    @argv = argv
    # --- 默认选项 ---
    @options = {
      config: nil,          # 配置文件路径
      rgss_version: nil,    # RGSS 版本 (nil 表示自动检测)
      unpack: false,        # 解包模式标志
      pack: false,          # 封包模式标志
      game_dir: Dir.pwd,    # 游戏根目录 (默认为当前工作目录)
      log_level: nil,       # 命令行指定的日志级别 (覆盖配置)
      log_dir: nil,          # 命令行指定的日志目录 (覆盖配置)
    }
    # -----------------
    @config = nil           # 加载后的配置数据
    @input_dir = nil        # 输入目录路径
    @output_dir = nil       # 输出目录路径
    @file_patterns = []     # 要包含的文件名模式 (正则表达式)
    @exclude_patterns = []  # 要排除的文件名模式 (正则表达式)
  end

  # 运行应用程序主流程
  def run
    begin
      # 1. 解析命令行选项
      parse_options
      # 2. 加载配置文件
      load_configuration
      # 3. 确定游戏根目录
      determine_game_directory
      # 4. 设置日志记录器 (传递命令行覆盖选项)
      Logging.setup_logger(
        @config,
        @options[:game_dir],
        @options[:log_level],
        @options[:log_dir]
      )
      # --- 主流程开始 ---
      Logging::Log.info "应用程序启动..."
      # 5. 解析配置文件中的文件匹配模式
      parse_config_patterns
      # 6. 确定要使用的 RGSS 版本 (自动检测或强制指定)
      determine_rgss_version
      # 7. 验证选项的有效性 (如 unpack/pack 必须二选一)
      validate_options
      # 8. 加载对应 RGSS 版本的类定义文件 (rgss1/2/3.rb)
      load_rgss_module
      # 9. 根据模式设置输入/输出目录
      setup_directories
      # 10. 处理文件转换
      process_files
      Logging::Log.info "处理完成。"
      # --- 主流程结束 ---
    rescue => e
      # 捕获所有未处理的异常
      begin
        # 尝试使用日志记录器记录致命错误
        Logging::Log.fatal "执行失败: #{e.message}"
        Logging::Log.error "调用栈:\n#{e.backtrace.join("\n")}"
      rescue
        # 如果日志记录器本身失败，则回退到 STDERR
        STDERR.puts "[致命错误] 执行失败: #{e.message}"
        STDERR.puts "[错误] 调用栈:\n#{e.backtrace.join("\n")}"
      end
      exit 1 # 以错误状态退出
    end
  end

  private

  # 解析命令行选项
  def parse_options
    OptionParser.new do |opts|
      opts.banner = "用法: rvdata2json.rb [选项]"
      opts.separator ""
      opts.separator "基本选项:"
      opts.on("-c", "--config FILE", "指定配置文件路径") { |file| @options[:config] = file }
      opts.on("-g", "--game-dir DIR", "指定游戏根目录 (默认: 当前目录)") { |dir| @options[:game_dir] = dir }
      opts.on("--unpack", "解包: 将 RVData/RXData 文件转换为 JSON/脚本") { @options[:unpack] = true }
      opts.on("--pack", "封包: 将 JSON/脚本 文件打包为 RVData/RXData") { @options[:pack] = true }

      opts.separator ""
      opts.separator "RGSS 版本选项 (默认自动检测):"
      opts.on("--rgss1", "强制使用 RGSS1 (RPG Maker XP)") { @options[:rgss_version] = "RGSS1" }
      opts.on("--rgss2", "强制使用 RGSS2 (RPG Maker VX)") { @options[:rgss_version] = "RGSS2" }
      opts.on("--rgss3", "强制使用 RGSS3 (RPG Maker VX Ace)") { @options[:rgss_version] = "RGSS3" }

      opts.separator ""
      opts.separator "日志选项:"
      # 允许的日志级别 (从 Logging 模块获取)
      valid_levels_help = Logging::VALID_LOG_LEVELS.join(", ")
      opts.on("--log-level LEVEL", Logging::VALID_LOG_LEVELS, "设置日志级别 (#{valid_levels_help})", "  (覆盖配置文件)") do |level|
        @options[:log_level] = level.upcase # 确保是大写以匹配常量
      end
      opts.on("--log-dir DIR", "指定日志文件目录并启用文件日志", "  (相对路径相对于游戏目录，绝对路径按原样使用)", "  (覆盖配置文件)") do |dir|
        @options[:log_dir] = dir
      end

      opts.separator ""
      opts.separator "其他:"
      opts.on_tail("-h", "--help", "显示此帮助信息") { puts opts; exit }
    end.parse!(@argv) # 解析参数，会修改 @argv
  end

  # 加载配置文件
  def load_configuration
    config_loader = Configuration.new(@options[:config])
    @config = config_loader.load
    # 日志记录配置文件加载情况已移至 Configuration 类内部或由后续的 Logging.setup_logger 处理
  end

  # 解析配置文件中的文件和排除模式
  def parse_config_patterns
    @file_patterns = (@config["files"] || []).map do |pattern|
      begin
        # 将字符串模式编译为不区分大小写的正则表达式
        Regexp.new(pattern, Regexp::IGNORECASE)
      rescue RegexpError => e
        # 处理无效的正则表达式
        raise "配置错误: 'files' 中的模式 '#{pattern}' 不是有效的正则表达式: #{e.message}"
      end
    end
    @exclude_patterns = (@config["exclude_files"] || []).map do |pattern|
      begin
        # 将字符串模式编译为不区分大小写的正则表达式
        Regexp.new(pattern, Regexp::IGNORECASE)
      rescue RegexpError => e
        # 处理无效的正则表达式
        raise "配置错误: 'exclude_files' 中的模式 '#{pattern}' 不是有效的正则表达式: #{e.message}"
      end
    end
    Logging::Log.debug "文件包含模式已加载: #{@file_patterns.inspect}" if Logging::Log.debug?
    Logging::Log.debug "文件排除模式已加载: #{@exclude_patterns.inspect}" if Logging::Log.debug?
  end

  # 确定并验证游戏根目录
  def determine_game_directory
    # 将路径转换为绝对路径
    @options[:game_dir] = File.expand_path(@options[:game_dir])
    # 检查目录是否存在
    unless Dir.exist?(@options[:game_dir])
      raise "指定的游戏目录不存在: #{@options[:game_dir]}"
    end
    # 日志记录目录信息将在 Logging.setup_logger 中处理
  end

  # 确定要使用的 RGSS 版本
  def determine_rgss_version
    Logging::Log.debug "确定 RGSS 版本..." if Logging::Log.debug?

    # 如果命令行已强制指定版本，则直接使用
    if @options[:rgss_version]
      Logging::Log.info "RGSS 版本由命令行强制指定: #{@options[:rgss_version]}"
      return
    end

    # 尝试从 Game.ini 文件自动检测
    begin
      detected_version = detect_rgss_version_from_game_ini
      if detected_version && RGSS_VERSIONS.include?(detected_version)
        @options[:rgss_version] = detected_version
        Logging::Log.info "从 Game.ini 自动检测到 RGSS 版本: #{@options[:rgss_version]}"
      else
        # 检测到了但不是支持的版本 (理论上不太可能发生)
        raise "无法从 Game.ini 推断出有效的 RGSS 版本。"
      end
    rescue => e
      # 自动检测失败，记录警告并回退到配置文件中的设置
      Logging::Log.warn "自动检测 RGSS 版本失败: #{e.message}"
      fallback_version = @config["rgss_version"]
      # 验证配置文件中的版本是否有效
      unless RGSS_VERSIONS.include?(fallback_version)
        raise "配置文件中的 rgss_version '#{fallback_version}' 无效。支持的版本: #{RGSS_VERSIONS.join(", ")}"
      end
      @options[:rgss_version] = fallback_version
      Logging::Log.info "回退到配置文件中的 RGSS 版本: #{@options[:rgss_version]}"
    end

    Logging::Log.debug "最终确定的 RGSS 版本: #{@options[:rgss_version]}" if Logging::Log.debug?
  end

  # 从 Game.ini 文件检测 RGSS 版本
  # @return [String, nil] 检测到的 RGSS 版本 ("RGSS1", "RGSS2", "RGSS3") 或 nil
  # @raise [RuntimeError] 如果 Game.ini 未找到或无法解析/推断版本
  def detect_rgss_version_from_game_ini
    game_ini_path = File.join(@options[:game_dir], "Game.ini")
    # 检查 Game.ini 文件是否存在
    raise "在游戏目录中未找到 Game.ini" unless File.exist?(game_ini_path)

    # 检测文件编码 (优先使用 BOM 或 rchardet)
    encoding = detect_file_encoding(game_ini_path)
    Logging::Log.debug "尝试使用检测到的编码 '#{encoding}' 加载 Game.ini" if Logging::Log.debug?

    ini_file = nil
    begin
      # 加载 INI 文件
      ini_file = IniFile.load(game_ini_path, encoding: encoding)
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError => e
      # 如果使用检测到的编码失败，记录警告并尝试使用 UTF-8
      Logging::Log.warn "使用编码 '#{encoding}' 加载 Game.ini 失败: #{e.message}。尝试使用 UTF-8..."
      begin
        ini_file = IniFile.load(game_ini_path, encoding: "UTF-8")
      rescue => e_utf8
        # 如果 UTF-8 也失败，则抛出错误
        raise "无法加载或解析 Game.ini (尝试了 '#{encoding}' 和 UTF-8): 初始错误 (#{e.message}), UTF-8 尝试错误 (#{e_utf8.message})"
      end
    rescue ArgumentError => e
      # 处理编码不兼容或无效字节序列错误
      if e.message.include?("invalid byte sequence") || e.message.include?("incompatible character encodings")
        raise "加载 Game.ini 时发现不兼容的编码 '#{encoding}' 或无效序列: #{e.message}"
      else
        raise # 重新抛出其他 ArgumentError
      end
    rescue => e
      # 捕获其他加载/解析错误
      raise "加载或解析 Game.ini 失败 (使用编码: #{encoding}): #{e.class} - #{e.message}"
    end

    # --- 根据 RTP 键推断 RGSS 版本 ---
    rtp_key = ini_file["Game"]["RTP"] rescue nil    # VX Ace 和 VX 使用
    rtp1_key = ini_file["Game"]["RTP1"] rescue nil # XP 使用

    if rtp_key
      rtp_value = rtp_key&.strip&.downcase
      Logging::Log.debug "Game.ini RTP 值: #{rtp_value.inspect}" if Logging::Log.debug?
      case rtp_value
      when /rpgvxace/ then return "RGSS3" # 包含 "rpgvxace" 字符串 -> RGSS3
      when /rpgvx/ then return "RGSS2"    # 包含 "rpgvx" 字符串 -> RGSS2
      end
      # 如果 RTP 值无法识别，记录警告并继续检查 RTP1
      Logging::Log.warn "无法从 RTP 值 '#{rtp_value}' 推断 RGSS 版本。检查 RTP1..."
    end

    if rtp1_key
      rtp1_value = rtp1_key&.strip&.downcase
      Logging::Log.debug "Game.ini RTP1 值: #{rtp1_value.inspect}" if Logging::Log.debug?
      # 如果 RTP1 值为 "standard" -> RGSS1
      return "RGSS1" if rtp1_value == "standard"
      # 如果 RTP1 值无法识别
      Logging::Log.warn "无法从 RTP1 值 '#{rtp1_value}' 推断 RGSS 版本 (预期为 'Standard')..."
    end

    # 如果两个键都无法推断出版本
    raise "无法从 Game.ini 中的 RTP 或 RTP1 推断 RGSS 版本。"
  end

  # 检测文件编码 (优先使用 BOM 或 rchardet)
  # @param file_path [String] 文件路径
  # @return [String] 检测到的编码名称 (如 "UTF-8", "Shift_JIS") 或默认 "UTF-8"
  def detect_file_encoding(file_path)
    begin
      # 读取文件开头的一小部分进行检测 (最多 4KB)
      content_sample = File.binread(file_path, 4096) || ""
      # 调用 Utils 中的安全编码检测方法
      detected_encoding_name = Utils.send(:detect_encoding_safe, content_sample)

      if detected_encoding_name
        Logging::Log.debug "Utils.detect_encoding_safe 为 '#{File.basename(file_path)}' 返回编码 '#{detected_encoding_name}'" if Logging::Log.debug?
        return detected_encoding_name
      else
        # 如果无法可靠检测，则默认使用 UTF-8
        Logging::Log.warn "无法可靠检测 '#{File.basename(file_path)}' 的编码。假定为 UTF-8。"
        return "UTF-8"
      end
    rescue SystemCallError => e
      # 处理文件读取错误
      Logging::Log.error "读取文件 '#{file_path}' 进行编码检测时出错: #{e.message}。假定为 UTF-8。"
      return "UTF-8"
    rescue => e
      # 处理其他意外错误
      Logging::Log.warn "检测文件 '#{file_path}' 编码时发生意外错误: #{e.class} - #{e.message}。假定为 UTF-8。"
      return "UTF-8"
    end
  end

  # 验证命令行选项和配置
  def validate_options
    Logging::Log.debug "验证选项..." if Logging::Log.debug?
    # 必须指定 --unpack 或 --pack 中的一个，且只能指定一个
    unless @options[:unpack] ^ @options[:pack]
      raise "必须指定 --unpack 或 --pack 中的一个。"
    end
    # 验证 RGSS 版本是否有效
    unless RGSS_VERSIONS.include?(@options[:rgss_version])
      raise "无效的 RGSS 版本: '#{@options[:rgss_version]}'. 支持的版本: #{RGSS_VERSIONS.join(", ")}"
    end
    Logging::Log.info "操作模式: #{@options[:unpack] ? "解包 (UNPACK)" : "封包 (PACK)"}"
    Logging::Log.info "确认的 RGSS 版本: #{@options[:rgss_version]}"
  end

  # 加载对应 RGSS 版本的库文件
  def load_rgss_module
    begin
      # 根据版本号构造文件名 (e.g., "rgss3")
      rgss_lib_file = @options[:rgss_version].downcase
      # 加载对应的库文件
      require_relative rgss_lib_file
      Logging::Log.info "已加载 RGSS 定义: lib/#{rgss_lib_file}.rb"
    rescue LoadError => e
      # 处理加载失败错误
      raise "加载 RGSS 定义文件 'lib/#{rgss_lib_file}.rb' 失败: #{e.message}"
    end
  end

  # 设置输入和输出目录路径
  def setup_directories
    # 根据操作模式确定配置文件中使用的键名
    input_dir_key = @options[:unpack] ? "input_dir_marshal" : "input_dir_source"
    output_dir_key = @options[:unpack] ? "output_dir_source" : "output_dir_marshal"

    # 从配置中读取目录名，并转换为相对于游戏根目录的绝对路径
    @input_dir = File.expand_path(@config[input_dir_key], @options[:game_dir])
    @output_dir = File.expand_path(@config[output_dir_key], @options[:game_dir])

    Logging::Log.info "输入目录: #{@input_dir}"
    Logging::Log.info "输出目录: #{@output_dir}"

    # 验证输入目录是否存在
    raise "输入目录不存在: #{@input_dir}" unless Dir.exist?(@input_dir)
    # 输出目录将在写入时由 FileUtils.mkdir_p 自动创建，无需在此检查
  end

  # 处理文件转换的核心逻辑
  def process_files
    scripts_processed = false # 标记是否处理了 Scripts 文件

    # 获取要处理的文件列表、输入扩展名、输出扩展名
    file_list, input_extension, output_extension = get_file_list

    # --- 特殊处理：打包模式下的脚本目录 ---
    if @options[:pack]
      scripts_input_dir = File.join(@input_dir, Converter::Scripts::SCRIPTS_SUBDIR)
      if Dir.exist?(scripts_input_dir)
        begin
          # 根据 RGSS 版本确定输出的 Scripts 文件扩展名
          rvdata_extension = case @options[:rgss_version]
            when "RGSS1" then ".rxdata"
            when "RGSS2" then ".rvdata"
            when "RGSS3" then ".rvdata2"
            else raise "内部错误: 打包脚本时未知的 RGSS 版本 #{@options[:rgss_version]}"
            end
          # 构造输出文件路径 (首字母大写)
          scripts_output_file = File.join(@output_dir, SCRIPTS_BASENAME.capitalize + rvdata_extension)
          Logging::Log.info "检测到脚本输入目录，开始打包脚本: #{scripts_input_dir} -> #{File.basename(scripts_output_file)}"
          FileUtils.mkdir_p(File.dirname(scripts_output_file)) # 确保输出目录存在

          # 调用 Converter::Scripts.pack 进行打包
          packed_scripts_array = Converter::Scripts.pack(scripts_input_dir)

          if packed_scripts_array.nil?
            Logging::Log.warn "脚本打包返回 nil，跳过写入 #{File.basename(scripts_output_file)}。"
          else
            # 将打包后的数组写入 Marshal 文件
            Converter::IO.write_marshal_data(scripts_output_file, packed_scripts_array)
            Logging::Log.info "  打包脚本输出: #{scripts_output_file}"
            scripts_processed = true
          end
        rescue => e
          # 记录脚本打包过程中的错误
          Logging::Log.error "处理脚本打包失败 (目录: #{scripts_input_dir}):"
          Logging::Log.error "  错误: #{e.class}: #{e.message}"
          e.backtrace.first(10).each { |line| Logging::Log.error "    #{line}" }
          raise # 重新抛出异常，中断执行
        end
      else
        # 如果脚本输入目录不存在，则跳过打包
        Logging::Log.info "脚本输入目录未找到: #{scripts_input_dir}。跳过脚本打包。"
      end

      # 从待处理文件列表中移除脚本目录下的所有文件 (JSON 等)
      scripts_dir_rel_path = Pathname.new(scripts_input_dir).relative_path_from(Pathname.new(@input_dir)).to_s
      file_list.reject! do |f|
        Pathname.new(f).relative_path_from(Pathname.new(@input_dir)).to_s.downcase.start_with?(scripts_dir_rel_path.downcase)
      end
    end
    # --- 脚本打包处理结束 ---

    # 如果没有文件需要处理 (且未处理脚本)，则提前返回
    if file_list.empty? && !scripts_processed
      Logging::Log.info "未找到匹配条件的文件进行处理。"
      return
    end

    # --- 初始化转换器 ---
    exporter = Converter::JsonExporter.new(@options[:rgss_version]) if @options[:unpack]
    restorer = Converter::RvdataRestorer.new(@options[:rgss_version]) if @options[:pack]

    # --- 遍历文件列表进行转换 ---
    file_list.each do |input_file|
      # 获取相对于输入目录的路径 (用于构造输出路径)
      relative_path = Pathname.new(input_file).relative_path_from(Pathname.new(@input_dir)).to_s
      # 获取不带扩展名的基础名
      basename_no_ext = relative_path.chomp(input_extension)
      file_basename_for_log = File.basename(input_file) # 用于日志记录的文件名

      begin
        # --- 特殊处理：解包模式下的 Scripts 文件 ---
        if @options[:unpack] && basename_no_ext.downcase == SCRIPTS_BASENAME
          Logging::Log.info "解包 #{file_basename_for_log} -> 脚本文件..."
          input_object = Converter::IO.load_marshal_data(input_file)
          if input_object.nil?
            Logging::Log.warn "从 '#{file_basename_for_log}' 加载的对象为 nil。跳过脚本解包。"
            next
          end
          # 调用 Converter::Scripts.unpack 进行解包
          Converter::Scripts.unpack(input_object, @output_dir)
          scripts_processed = true
          next # 处理完脚本文件，继续下一个文件
        end
        # --- 脚本解包处理结束 ---

        # --- 通用文件处理 ---
        if @options[:unpack]
          # --- 解包模式 ---
          Logging::Log.info "解包 #{file_basename_for_log} -> JSON..."
          # 1. 加载 Marshal 数据
          input_object = Converter::IO.load_marshal_data(input_file)
          if input_object.nil?
            Logging::Log.warn "从 '#{file_basename_for_log}' 加载的对象为 nil。跳过解包。"
            next
          end
          # 2. 导出为 JSON 兼容结构
          cleaned_data = exporter.export(input_object)
          # 3. 构造 JSON 输出文件路径
          json_output_file = File.join(@output_dir, basename_no_ext + ".json")
          FileUtils.mkdir_p(File.dirname(json_output_file)) # 确保目录存在
          # 4. 写入 JSON 文件
          Converter::IO.write_json_data(json_output_file, cleaned_data)
          Logging::Log.info "  解包输出: #{json_output_file}"
        else
          # --- 封包模式 ---
          Logging::Log.info "封包 #{file_basename_for_log} -> RVData/RXData..."
          # 1. 加载 JSON 数据
          input_data = Converter::IO.load_json_data(input_file)
          if input_data.nil?
            Logging::Log.warn "从 JSON 文件 '#{file_basename_for_log}' 加载的数据为 nil。跳过封包。"
            next
          end
          # 2. 恢复为 Ruby 对象
          restored_object = restorer.restore(input_data)
          if restored_object.nil?
            Logging::Log.warn "从 JSON 文件 '#{file_basename_for_log}' 恢复的对象为 nil。跳过 Marshal 写入。"
            next
          end
          # 3. 构造 Marshal 输出文件路径
          rvdata_output_file = File.join(@output_dir, basename_no_ext + output_extension)
          FileUtils.mkdir_p(File.dirname(rvdata_output_file)) # 确保目录存在
          # 4. 写入 Marshal 文件
          Converter::IO.write_marshal_data(rvdata_output_file, restored_object)
          Logging::Log.info "  封包输出: #{rvdata_output_file}"
        end
      rescue NameError => e
        # 捕获因 RGSS 版本不匹配导致的 NameError
        Logging::Log.error "处理文件 '#{file_basename_for_log}' 时出错 (可能是 RGSS 版本不匹配):"
        Logging::Log.error "  错误: #{e.class}: #{e.message}."
        Logging::Log.error "  提示: 请确保指定的 RGSS 版本 (--rgss1/2/3 或自动检测) 与数据文件匹配。"
        Logging::Log.error "  当前使用的 RGSS 版本: #{@options[:rgss_version]}"
        raise # 重新抛出异常，中断执行
      rescue => e
        # 捕获处理单个文件时的其他所有错误
        Logging::Log.error "处理文件 '#{file_basename_for_log}' 失败:"
        Logging::Log.error "  RGSS 版本: #{@options[:rgss_version]}"
        Logging::Log.error "  错误: #{e.class}: #{e.message}"
        e.backtrace.first(10).each { |line| Logging::Log.error "    #{line}" }
        raise # 重新抛出异常，中断执行
      end
    end # file_list.each end
  end # def process_files end

  # 获取要处理的文件列表
  # @return [Array<String>, String, String] 文件路径列表, 输入扩展名, 输出扩展名
  def get_file_list
    # 根据 RGSS 版本确定 Marshal 文件扩展名
    rvdata_extension = case @options[:rgss_version]
      when "RGSS1" then ".rxdata"
      when "RGSS2" then ".rvdata"
      when "RGSS3" then ".rvdata2"
      else raise "内部错误: 未知的 RGSS 版本 #{@options[:rgss_version]}"
      end
    source_extension = ".json" # JSON 文件扩展名固定

    # 根据操作模式确定输入和输出扩展名
    input_extension = @options[:unpack] ? rvdata_extension : source_extension
    output_extension = @options[:unpack] ? source_extension : rvdata_extension

    Logging::Log.info "在 #{@input_dir} 中搜索扩展名为 #{input_extension} 的输入文件"

    all_files = []
    begin
      # 递归查找输入目录下的所有文件
      Find.find(@input_dir) do |path|
        next unless File.file?(path) # 只处理文件
        # 检查文件扩展名是否匹配 (不区分大小写)
        if File.extname(path).downcase == input_extension.downcase
          all_files << path
        end
      end
    rescue SystemCallError => e
      # 处理访问输入目录时的错误
      raise "访问输入目录 '#{@input_dir}' 时出错: #{e.message}"
    end

    # --- 应用文件过滤规则 ---
    filtered_files = all_files.select do |file_path|
      begin
        # 获取相对于输入目录的路径
        relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(@input_dir)).to_s
        # 获取不带扩展名的基础名
        basename = relative_path.chomp(File.extname(relative_path))

        # 检查是否匹配包含规则 (如果规则列表为空，则默认包含)
        included = @file_patterns.empty? || @file_patterns.any? { |regex| basename.match?(regex) }
        # 检查是否匹配排除规则
        excluded = !@exclude_patterns.empty? && @exclude_patterns.any? { |regex| basename.match?(regex) }

        if Logging::Log.debug?
          match_log = "检查 '#{relative_path}': included=#{included}, excluded=#{excluded}"
          Logging::Log.debug match_log
        end

        # 只有当包含且不排除时，才选择此文件
        included && !excluded
      rescue => e
        # 记录处理路径时的错误
        Logging::Log.warn "在过滤期间处理路径 '#{file_path}' 时出错: #{e.message}。跳过此文件。"
        false # 出错则不选择
      end
    end
    # --- 过滤结束 ---

    filtered_files.uniq! # 去重
    filtered_files.sort! # 排序

    if filtered_files.empty?
      Logging::Log.info "在 '#{@input_dir}' 中未找到匹配条件的文件 (扩展名: #{input_extension}, 应用模式后)。"
    else
      Logging::Log.info "找到 #{filtered_files.length} 个文件进行处理。"
      # 如果是 Debug 级别，列出找到的文件
      if Logging::Log.debug?
        filtered_files.each { |f| Logging::Log.debug "  - #{Pathname.new(f).relative_path_from(Pathname.new(@input_dir))}" }
      end
    end

    return filtered_files, input_extension, output_extension
  end # def get_file_list end
end # class Application
