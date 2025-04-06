# lib/application.rb

# 应用主流程控制

require "optparse"
require "pathname"
require "find"
require "fileutils"
require "inifile"
require "set"

# --- 尽早加载日志模块 ---
require_relative "logging"
# -----------------------

# --- 尝试加载 C 扩展 ---
begin
  require "rgssad_extractor/rgssad_extractor"
  RGSSAD_EXTRACTOR_LOADED = true
rescue LoadError => e
  RGSSAD_EXTRACTOR_LOADED = false
end
# -----------------------

require_relative "configuration"
require_relative "converter" # Converter 模块包含了 Scripts 子模块
require_relative "utils"

class Application
  RGSS_VERSIONS = %w[RGSS1 RGSS2 RGSS3].freeze
  SCRIPTS_BASENAME = "scripts".freeze
  DEFAULT_STANDALONE_EXTRACT_DIR = "extracted_archive".freeze

  def initialize(argv)
    @argv = argv
    @options = {
      config: nil,
      rgss_version: nil,
      unpack: false,
      pack: false,
      base_dir: nil, # <-- 重命名并初始化为 nil
      log_level: nil,
      log_dir: nil,
      extract_archive_path: nil,
      extract_output_path: nil,
    }
    @config = nil
    @input_dir = nil
    @output_dir = nil
    @file_patterns = []
    @exclude_patterns = []
    @archive_extracted_successfully = false
  end

  def run
    begin
      # --- 步骤 1: 解析选项 ---
      parse_options

      # --- 步骤 2: 确定基准目录 ---
      determine_base_directory # <-- 新方法调用

      # --- 步骤 3: 设置日志 (需要基准目录来解析相对日志路径) ---
      load_configuration # 加载配置以获取日志设置
      Logging.setup_logger(
        @config,
        @options[:base_dir], # <-- 使用 base_dir
        @options[:log_level],
        @options[:log_dir]
      )
      Logging::Log.info "基准目录已确定: #{@options[:base_dir]}"

      # --- 步骤 4: 检查是否为独立提取模式 ---
      if @options[:extract_archive_path]
        # === Standalone Extraction Mode ===
        # 检查 C 扩展
        Logging::Log.info "检测到独立存档提取模式 (-e)..."
        log_rgssad_status(check_needed: true)
        # 执行提取 (不再需要加载配置或设置目录)
        handle_standalone_extraction
        Logging::Log.info "独立存档提取操作完成。"
        exit 0
        # === End Standalone Mode ===
      end

      # --- 如果不是独立提取模式，则继续执行常规流程 ---
      # === Regular Unpack/Pack Mode ===
      Logging::Log.info "进入常规解包/封包模式..."
      # 常规模式需要完整配置和设置
      # (load_configuration 已在上面日志设置前调用)
      determine_rgss_version # 检测 RGSS 版本
      setup_directories      # 设置常规输入/输出目录 (相对于 base_dir)
      log_rgssad_status(check_needed: false) # 检查 C 扩展状态 (非必需)

      # 处理常规解包模式下的隐式提取
      process_archive_extraction_if_needed

      # 执行核心的解包/封包文件处理
      parse_config_patterns
      validate_options
      load_rgss_module
      adjust_input_directory_for_unpack # 调整输入目录
      process_files
      Logging::Log.info "常规处理完成。"
      # === End Regular Mode ===

    rescue SystemExit
      # Normal exit
    rescue => e
      begin
        Logging::Log.fatal "执行失败: #{e.message}"
        Logging::Log.error "调用栈:\n#{e.backtrace.join("\n")}"
      rescue
        STDERR.puts "[致命错误] 执行失败: #{e.message}"
        STDERR.puts "[错误] 调用栈:\n#{e.backtrace.join("\n")}"
      end
      exit 1
    end
  end

  private

  # 解析命令行选项 (修改后)
  def parse_options
    OptionParser.new do |opts|
      opts.banner = "用法: rvdata2json.rb [选项]"
      opts.separator ""
      opts.separator "常规选项:"
      opts.on("-c", "--config FILE", "指定配置文件路径") { |file| @options[:config] = file }
      # --- 修改参数 ---
      opts.on("-b", "--base-dir DIR", "指定基准目录 (用于解析相对路径, 默认: 当前工作目录)") { |dir| @options[:base_dir] = dir }
      # --- 修改结束 ---
      opts.on("--unpack", "解包: 将 RVData/RXData 文件转换为 JSON/脚本") { @options[:unpack] = true }
      opts.on("--pack", "封包: 将 JSON/脚本 文件打包为 RVData/RXData") { @options[:pack] = true }

      opts.separator ""
      opts.separator "RGSS 版本选项 (常规模式下默认自动检测):"
      opts.on("--rgss1", "强制使用 RGSS1 (RPG Maker XP)") { @options[:rgss_version] = "RGSS1" }
      opts.on("--rgss2", "强制使用 RGSS2 (RPG Maker VX)") { @options[:rgss_version] = "RGSS2" }
      opts.on("--rgss3", "强制使用 RGSS3 (RPG Maker VX Ace)") { @options[:rgss_version] = "RGSS3" }

      opts.separator ""
      opts.separator "独立存档提取选项:"
      opts.on("-e", "--extract-archive FILE", "仅提取指定的存档文件 (rgssad/rgss2a/rgss3a)，然后退出。",
              "  路径可以是绝对路径，或相对于 --base-dir 的相对路径。", # <-- 修改提示
              "  C 扩展将自动检测存档版本进行解密。",
              "  (此选项优先于 --unpack 和 --pack)") do |file|
        @options[:extract_archive_path] = file
      end
      opts.on("-o", "--extract-output-dir DIR", "指定独立存档提取的输出目录。",
              "  路径可以是绝对路径，或相对于 *当前工作目录* 的相对路径。", # <-- 保持不变，独立输出仍基于 pwd
              "  (如果省略，则在 *当前工作目录* 下创建 '#{DEFAULT_STANDALONE_EXTRACT_DIR}' 目录)") do |dir|
        @options[:extract_output_path] = dir
      end

      opts.separator ""
      opts.separator "日志选项:"
      valid_levels_help = Logging::VALID_LOG_LEVELS.join(", ")
      opts.on("--log-level LEVEL", Logging::VALID_LOG_LEVELS, "设置日志级别 (#{valid_levels_help})", "  (覆盖配置文件)") do |level|
        @options[:log_level] = level.upcase
      end
      opts.on("--log-dir DIR", "指定日志文件目录并启用文件日志", "  (路径可以是绝对路径，或相对于 --base-dir 的相对路径)", "  (覆盖配置文件)") do |dir| # <-- 修改提示
        @options[:log_dir] = dir
      end

      opts.separator ""
      opts.separator "其他:"
      opts.on_tail("-h", "--help", "显示此帮助信息") { puts opts; exit }
    end.parse!(@argv)
  end

  # 加载配置文件
  def load_configuration
    config_loader = Configuration.new(@options[:config])
    @config = config_loader.load
    if config_loader.path && File.exist?(config_loader.path)
      Logging::Log.debug "配置文件已加载: #{config_loader.path}" if Logging::Log.debug?
    else
      Logging::Log.info "未找到配置文件，使用默认配置。"
    end
  end

  # 确定并验证基准目录 (新方法)
  def determine_base_directory
    if @options[:base_dir].nil?
      # 如果命令行未指定 -b/--base-dir，则使用当前工作目录
      @options[:base_dir] = Dir.pwd
      Logging::Log.debug "未指定 --base-dir，使用当前工作目录作为基准目录: #{@options[:base_dir]}"
    else
      # 如果指定了，则解析为绝对路径
      @options[:base_dir] = File.expand_path(@options[:base_dir])
      Logging::Log.debug "使用指定的基准目录: #{@options[:base_dir]}"
    end

    # 验证基准目录是否存在
    unless Dir.exist?(@options[:base_dir])
      raise "错误：指定的基准目录不存在: #{@options[:base_dir]}"
    end
    # 最终的基准目录日志记录移到 run 方法中 setup_logger 之后
  end

  # 记录 C 扩展加载状态并检查是否必需
  def log_rgssad_status(check_needed: false)
    unless RGSSAD_EXTRACTOR_LOADED
      Logging::Log.warn "未找到或无法加载 RGSSAD C 扩展 ('rgssad_extractor')。"
      Logging::Log.warn "存档提取功能将不可用。请确保已编译 C 扩展。"
      if check_needed
        Logging::Log.error "错误：当前操作需要存档提取功能，但 C 扩展不可用。请先编译 C 扩展。"
        raise "存档提取功能不可用，无法继续。"
      end
    else
      Logging::Log.debug "RGSSAD C 扩展已加载。"
    end
  end

  # 确定要使用的 RGSS 版本 (常规模式需要)
  # 注意：Game.ini 的检测现在基于 base_dir
  def determine_rgss_version
    Logging::Log.debug "确定 RGSS 版本..." if Logging::Log.debug?
    if @options[:rgss_version]
      Logging::Log.info "RGSS 版本由命令行强制指定: #{@options[:rgss_version]}"
      return
    end
    begin
      detected_version = detect_rgss_version_from_game_ini # 检测逻辑不变，但路径基于 base_dir
      if detected_version && RGSS_VERSIONS.include?(detected_version)
        @options[:rgss_version] = detected_version
        Logging::Log.info "从 Game.ini (位于基准目录) 自动检测到 RGSS 版本: #{@options[:rgss_version]}"
      else
        raise "无法从 Game.ini (位于基准目录) 推断出有效的 RGSS 版本。"
      end
    rescue => e
      Logging::Log.warn "自动检测 RGSS 版本失败: #{e.message}"
      fallback_version = @config["rgss_version"]
      unless RGSS_VERSIONS.include?(fallback_version)
        raise "配置文件中的 rgss_version '#{fallback_version}' 无效。支持: #{RGSS_VERSIONS.join(", ")}"
      end
      @options[:rgss_version] = fallback_version
      Logging::Log.info "回退到配置文件中的 RGSS 版本: #{@options[:rgss_version]}"
    end
    Logging::Log.debug "最终 RGSS 版本: #{@options[:rgss_version]}" if Logging::Log.debug?
  end

  # 从 Game.ini 文件检测 RGSS 版本 (修改后 - 基于 base_dir)
  def detect_rgss_version_from_game_ini
    game_ini_path = File.join(@options[:base_dir], "Game.ini") # <-- 使用 base_dir
    raise "在基准目录中未找到 Game.ini 用于版本检测" unless File.exist?(game_ini_path) # <-- 更新错误消息
    encoding = detect_file_encoding(game_ini_path)
    Logging::Log.debug "尝试使用编码 '#{encoding}' 加载 Game.ini" if Logging::Log.debug?
    ini_file = nil
    begin
      ini_file = IniFile.load(game_ini_path, encoding: encoding)
    rescue => e
      Logging::Log.warn "使用编码 '#{encoding}' 加载 Game.ini 失败: #{e.message}。尝试 UTF-8..."
      begin; ini_file = IniFile.load(game_ini_path, encoding: "UTF-8");       rescue => e_utf8; raise "无法加载或解析 Game.ini: #{e.message} / #{e_utf8.message}"; end
    end
    rtp_key = ini_file["Game"]["RTP"] rescue nil
    rtp1_key = ini_file["Game"]["RTP1"] rescue nil
    if rtp_key; rtp_value = rtp_key.strip.downcase; case rtp_value
    when /rpgvxace/; return "RGSS3"
    when /rpgvx/; return "RGSS2"
    end; Logging::Log.warn "未知 RTP 值 '#{rtp_value}'";     end
    if rtp1_key; rtp1_value = rtp1_key.strip.downcase; return "RGSS1" if rtp1_value == "standard"; Logging::Log.warn "未知 RTP1 值 '#{rtp1_value}'"; end
    raise "无法从 Game.ini 推断 RGSS 版本。"
  end

  # 检测文件编码
  def detect_file_encoding(file_path)
    begin; content_sample = File.binread(file_path, 4096) || ""; detected = Utils.send(:detect_encoding_safe, content_sample); return detected || "UTF-8";     rescue => e; Logging::Log.warn "检测 '#{File.basename(file_path)}' 编码出错: #{e.message}. 假定 UTF-8."; return "UTF-8"; end
  end

  # 设置常规模式的目录 (修改后 - 基于 base_dir)
  def setup_directories
    input_dir_key = @options[:unpack] ? "input_dir_marshal" : "input_dir_source"
    output_dir_key = @options[:unpack] ? "output_dir_source" : "output_dir_marshal"

    # 解析常规输入输出目录 (相对于 base_dir)
    @input_dir = File.expand_path(@config[input_dir_key], @options[:base_dir]) # <-- 使用 base_dir
    @output_dir = File.expand_path(@config[output_dir_key], @options[:base_dir]) # <-- 使用 base_dir

    Logging::Log.info "常规输入目录 (初始): #{@input_dir}"
    Logging::Log.info "常规输出目录: #{@output_dir}"
  end

  # 统一处理存档提取的入口方法 (只处理隐式提取)
  def process_archive_extraction_if_needed
    # Standalone extraction is handled earlier in run method.
    # This method now only handles implicit extraction for unpack mode.

    return unless @options[:unpack] # Only run in unpack mode

    archive_config = @config["archive_processing"]
    # Only run if enabled and C extension loaded
    return unless archive_config["enabled"] && RGSSAD_EXTRACTOR_LOADED

    # Implicit extraction logic (calls perform_implicit_unpack_extraction)
    perform_implicit_unpack_extraction
  end

  # 处理独立存档提取逻辑 (修改后 - 输入路径基于 base_dir)
  def handle_standalone_extraction
    Logging::Log.info "进入独立存档提取模式。"
    Logging::Log.info "C 扩展将自动检测存档版本并进行解密。"

    # --- 修改点：输入路径基于 base_dir ---
    input_archive_path = File.expand_path(@options[:extract_archive_path], @options[:base_dir])
    Logging::Log.debug "独立提取：解析输入存档路径为: #{input_archive_path}"
    # --- 修改结束 ---

    # 输出目录逻辑不变 (基于 pwd 或绝对路径)
    output_dir_path = nil
    if @options[:extract_output_path] && !@options[:extract_output_path].empty?
      user_path = @options[:extract_output_path]
      path_obj = Pathname.new(user_path)
      if path_obj.absolute?
        output_dir_path = user_path
        Logging::Log.debug "独立提取：使用命令行指定的绝对输出目录: #{output_dir_path}"
      else
        output_dir_path = File.expand_path(user_path, Dir.pwd)
        Logging::Log.debug "独立提取：使用命令行指定的相对输出目录 '#{user_path}'，解析为: #{output_dir_path}"
      end
    else
      output_dir_path = File.expand_path(DEFAULT_STANDALONE_EXTRACT_DIR, Dir.pwd)
      Logging::Log.debug "独立提取：未指定输出目录，使用默认名称 '#{DEFAULT_STANDALONE_EXTRACT_DIR}'，解析为: #{output_dir_path}"
    end
    Logging::Log.info "独立提取：最终输出目录: #{output_dir_path}"

    # --- REMOVED: 不再需要调用 find_archive_filename 或发出警告 ---

    # 调用核心提取逻辑
    extraction_successful = perform_extraction_core(input_archive_path, output_dir_path, File.basename(input_archive_path), "独立提取")

    unless extraction_successful
      raise "独立存档提取失败。"
    end

    Logging::Log.info "独立提取模式：成功提取存档 '#{File.basename(input_archive_path)}'。"
    Logging::Log.info "注意：在独立提取模式下，即使配置中设置为 true，也不会删除原始存档文件。"
  end

  # 执行常规解包流程中的隐式提取 (修改后 - 路径基于 base_dir)
  def perform_implicit_unpack_extraction
    archive_filename = find_archive_filename
    return Logging::Log.warn "常规解包流程：无法根据 RGSS 版本 (#{@options[:rgss_version]}) 确定存档文件名，跳过提取。" unless archive_filename

    archive_path = File.join(@options[:base_dir], archive_filename) # <-- 基于 base_dir
    return Logging::Log.info "常规解包流程：未找到预期的存档文件 '#{archive_filename}' (在基准目录中)，跳过提取。" unless File.exist?(archive_path)

    target_extract_dir = @options[:base_dir] # <-- 提取到 base_dir
    Logging::Log.info "常规解包流程：找到存档文件 '#{archive_filename}'，开始提取到基准目录 '#{target_extract_dir}' (C扩展将自动检测版本)..."

    # 调用核心提取逻辑
    @archive_extracted_successfully = perform_extraction_core(archive_path, target_extract_dir, archive_filename, "常规解包提取")

    # 记录结果并处理删除
    if @archive_extracted_successfully
      Logging::Log.info "常规解包流程：存档提取成功完成。"

      # --- 新增: 创建项目文件 ---
      begin
        project_filename = nil
        project_content = nil
        case @options[:rgss_version]
        when "RGSS1"
          project_filename = "Game.rxproj"
          project_content = "RPGXP 1.03"
        when "RGSS2"
          project_filename = "Game.rvproj"
          project_content = "RPGVX 1.02"
        when "RGSS3"
          project_filename = "Game.rvproj2"
          project_content = "RPGVXAce 1.02"
        end

        if project_filename && project_content
          project_filepath = File.join(@options[:base_dir], project_filename)
          Logging::Log.info "创建项目文件: #{project_filepath}"
          # 使用 UTF-8 编码写入， File.write 默认使用 LF 或系统默认，但对单行无换行符的内容影响不大
          File.write(project_filepath, project_content, encoding: "UTF-8")
          Logging::Log.info "成功创建项目文件: #{project_filename}"
        else
          Logging::Log.warn "无法确定要创建的项目文件 (未知 RGSS 版本: #{@options[:rgss_version]})"
        end
      rescue SystemCallError, IOError => e
        # 在错误日志中包含基准目录信息以便调试
        Logging::Log.error "创建项目文件 '#{project_filename || "未知"}' (位于基准目录 '#{@options[:base_dir]}') 失败: #{e.message}"
      rescue => e
        Logging::Log.error "创建项目文件时发生意外错误: #{e.class}: #{e.message}"
      end
      # --- 项目文件创建结束 ---

      # --- 原有的存档删除逻辑 ---
      if @config["archive_processing"]["delete_archive_after_extraction"]
        Logging::Log.info "配置要求删除存档，尝试删除: #{archive_path}"
        begin
          FileUtils.rm(archive_path)
          Logging::Log.info "成功删除原始存档文件: #{archive_filename}"
        rescue SystemCallError => e
          Logging::Log.error "删除存档文件 '#{archive_path}' 失败: #{e.message}"
        rescue => e
          Logging::Log.error "删除存档文件 '#{archive_path}' 时发生意外错误: #{e.class}: #{e.message}"
        end
      else
        Logging::Log.info "配置未要求删除存档，保留文件: #{archive_filename}"
      end
    else
      Logging::Log.error "常规解包流程：存档提取失败，后续将尝试使用原始输入目录。"
    end
  end

  # 根据 RGSS 版本查找存档文件名
  # 常规模式仍然需要这个来定位文件
  def find_archive_filename
    archive_config = @config["archive_processing"]
    filename = archive_config["archive_filenames"][@options[:rgss_version]]
    return filename if filename && !filename.empty?
    nil
  end

  # 核心提取逻辑
  # 调用 C 扩展，由 C 扩展负责内部版本检测
  def perform_extraction_core(input_path, output_path, log_filename, context_str)
    unless File.exist?(input_path)
      Logging::Log.error "#{context_str}：错误：输入存档文件不存在: '#{input_path}'"
      return false
    end
    if Dir.exist?(output_path)
      Logging::Log.info "#{context_str}：目标提取目录 '#{output_path}' 已存在。"
    else
      Logging::Log.info "#{context_str}：目标提取目录 '#{output_path}' 不存在，将由提取器创建。"
    end
    begin
      verbose_extraction = Logging::Log.debug?
      # 调用 C 扩展，它会自己检测版本
      RgssadExtractor.extract_archive(input_path, output_path, verbose_extraction)
      return true # 成功
    rescue => e
      log_extraction_error(e, log_filename) # 记录具体错误
      return false # 失败
    end
  end

  # 解析配置文件中的文件和排除模式
  def parse_config_patterns
    @file_patterns = (@config["files"] || []).map do |pattern|
      begin
        Regexp.new(pattern, Regexp::IGNORECASE)
      rescue RegexpError => e
        raise "配置错误: 'files' 中的模式 '#{pattern}' 不是有效的正则表达式: #{e.message}"
      end
    end
    @exclude_patterns = (@config["exclude_files"] || []).map do |pattern|
      begin
        Regexp.new(pattern, Regexp::IGNORECASE)
      rescue RegexpError => e
        raise "配置错误: 'exclude_files' 中的模式 '#{pattern}' 不是有效的正则表达式: #{e.message}"
      end
    end
    Logging::Log.debug "文件包含模式: #{@file_patterns.inspect}" if Logging::Log.debug?
    Logging::Log.debug "文件排除模式: #{@exclude_patterns.inspect}" if Logging::Log.debug?
  end

  # 验证常规模式选项
  def validate_options
    Logging::Log.debug "验证常规模式选项..." if Logging::Log.debug?
    unless @options[:unpack] ^ @options[:pack]
      raise "错误：常规模式下必须指定 --unpack 或 --pack 中的一个。"
    end
    unless RGSS_VERSIONS.include?(@options[:rgss_version])
      raise "错误：无效的 RGSS 版本: '#{@options[:rgss_version]}'."
    end
    Logging::Log.info "操作模式: #{@options[:unpack] ? "解包 (UNPACK)" : "封包 (PACK)"}"
    Logging::Log.info "确认的 RGSS 版本: #{@options[:rgss_version]}"
  end

  # 加载对应 RGSS 版本的库文件
  def load_rgss_module
    begin; require_relative @options[:rgss_version].downcase; Logging::Log.info "已加载 RGSS 定义: lib/#{@options[:rgss_version].downcase}.rb";     rescue LoadError => e; raise "加载 RGSS 定义失败: #{e.message}"; end
  end

  # 常规流程中调整解包输入目录 (在提取之后调用) (修改后 - 基于 base_dir)
  def adjust_input_directory_for_unpack
    return unless @options[:unpack]
    return unless @config["archive_processing"]["enabled"]

    if @archive_extracted_successfully
      # --- 修改点：检查 base_dir 是否存在 ---
      unless Dir.exist?(@options[:base_dir])
        Logging::Log.error "错误：存档提取成功但基准目录 '#{@options[:base_dir]}' 不存在！"
        original_input_dir = File.expand_path(@config["input_dir_marshal"], @options[:base_dir]) # 解析仍基于 base_dir
        raise "关键目录丢失，无法继续。" unless Dir.exist?(original_input_dir)
        Logging::Log.warn "将回退到原始输入目录 '#{original_input_dir}'。"
        @input_dir = original_input_dir
        return
      end
      # --- 修改点：使用 base_dir 作为输入源 ---
      Logging::Log.info "解包模式：将使用基准目录 '#{@options[:base_dir]}' 作为存档提取后的输入源。"
      @input_dir = @options[:base_dir]
    else
      # 提取失败或未执行，使用配置的 input_dir_marshal (相对于 base_dir 解析)
      original_input_dir = File.expand_path(@config["input_dir_marshal"], @options[:base_dir]) # 解析基于 base_dir
      Logging::Log.warn "解包模式：存档提取未成功/未执行，将使用原始输入目录 '#{original_input_dir}'。"
      raise "错误：存档提取失败/未执行，且原始输入目录 '#{original_input_dir}' 也不存在。" unless Dir.exist?(original_input_dir)
      @input_dir = original_input_dir
    end
    Logging::Log.info "最终确定的输入目录 (解包): #{@input_dir}"
  end

  # 处理文件转换的核心逻辑 (修改后 - 路径基于 base_dir)
  def process_files
    scripts_processed = false
    file_list, input_extension, output_extension = get_file_list # get_file_list 内部已基于 @input_dir

    # --- 脚本打包 ---
    if @options[:pack]
      # 源目录: config["input_dir_source"] 相对于 base_dir
      source_scripts_dir = File.expand_path(File.join(@config["input_dir_source"], Converter::Scripts::SCRIPTS_SUBDIR), @options[:base_dir]) # <-- 使用 base_dir
      if Dir.exist?(source_scripts_dir)
        begin
          rvdata_ext = case @options[:rgss_version]
            when "RGSS1"; ".rxdata"
            when "RGSS2"; ".rvdata"
            when "RGSS3"; ".rvdata2"
            else raise "打包脚本时未知版本"
            end
          # 输出文件: 在 @output_dir (已基于 base_dir 解析) 下
          scripts_output_file = File.join(@output_dir, SCRIPTS_BASENAME.capitalize + rvdata_ext)
          Logging::Log.info "检测到脚本源目录，打包: #{source_scripts_dir} -> #{File.basename(scripts_output_file)}"
          FileUtils.mkdir_p(File.dirname(scripts_output_file))
          packed_array = Converter::Scripts.pack(source_scripts_dir)
          raise "脚本打包返回 nil" if packed_array.nil?
          Converter::IO.write_marshal_data(scripts_output_file, packed_array)
          Logging::Log.info "  打包脚本输出: #{scripts_output_file}"
          scripts_processed = true
        rescue => e; log_processing_error(e, "脚本打包", source_scripts_dir); raise;         end
      else
        Logging::Log.info "脚本源目录未找到: #{source_scripts_dir}。跳过脚本打包。"
      end
      # 从待处理列表移除脚本源文件 (逻辑不变)
      scripts_rel_path = Pathname.new(Converter::Scripts::SCRIPTS_SUBDIR).to_s.downcase
      file_list.reject! { |f| begin; Pathname.new(f).relative_path_from(@input_dir).to_s.downcase.start_with?(scripts_rel_path);       rescue; false; end }
    end

    return Logging::Log.info "未找到匹配条件的文件进行处理。" if file_list.empty? && !scripts_processed

    exporter = Converter::JsonExporter.new(@options[:rgss_version]) if @options[:unpack]
    restorer = Converter::RvdataRestorer.new(@options[:rgss_version]) if @options[:pack]

    # --- 文件遍历处理 (路径逻辑不变，因为基于 @input_dir 和 @output_dir) ---
    file_list.each do |input_file|
      begin
        relative_path = Pathname.new(input_file).relative_path_from(@input_dir).to_s
        basename_no_ext = relative_path.chomp(input_extension)
        log_basename = File.basename(input_file)

        # --- 脚本解包 ---
        if @options[:unpack] && File.basename(basename_no_ext).downcase == SCRIPTS_BASENAME.downcase
          Logging::Log.info "解包 #{log_basename} -> 脚本文件..."
          input_obj = Converter::IO.load_marshal_data(input_file)
          raise "从 '#{log_basename}' 加载的对象为 nil" if input_obj.nil?
          # 输出目录: @output_dir 下的 Scripts 子目录
          scripts_output_directory = File.join(@output_dir, Converter::Scripts::SCRIPTS_SUBDIR)
          Converter::Scripts.unpack(input_obj, scripts_output_directory)
          scripts_processed = true
          next
        end

        # --- 常规文件处理 ---
        if @options[:unpack]
          Logging::Log.info "解包 #{log_basename} -> JSON..."
          input_obj = Converter::IO.load_marshal_data(input_file)
          raise "从 '#{log_basename}' 加载的对象为 nil" if input_obj.nil?
          cleaned_data = exporter.export(input_obj)
          output_basename = File.basename(basename_no_ext)
          json_output_file = File.join(@output_dir, output_basename + ".json")
          FileUtils.mkdir_p(File.dirname(json_output_file))
          Converter::IO.write_json_data(json_output_file, cleaned_data)
          Logging::Log.info "  解包输出: #{json_output_file}"
        else # pack
          Logging::Log.info "封包 #{log_basename} -> RVData/RXData..."
          input_data = Converter::IO.load_json_data(input_file)
          raise "从 JSON 文件 '#{log_basename}' 加载的数据为 nil" if input_data.nil?
          restored_obj = restorer.restore(input_data)
          raise "从 JSON 文件 '#{log_basename}' 恢复的对象为 nil" if restored_obj.nil?
          output_basename = File.basename(basename_no_ext)
          rvdata_output_file = File.join(@output_dir, output_basename + output_extension)
          FileUtils.mkdir_p(File.dirname(rvdata_output_file))
          Converter::IO.write_marshal_data(rvdata_output_file, restored_obj)
          Logging::Log.info "  封包输出: #{rvdata_output_file}"
        end
      rescue => e; log_processing_error(e, "文件 '#{log_basename}'", @options[:rgss_version]); raise;       end
    end
  end

  # 获取最终要处理的文件列表
  def get_file_list
    rvdata_ext = case @options[:rgss_version]
      when "RGSS1"; ".rxdata"
      when "RGSS2"; ".rvdata"
      when "RGSS3"; ".rvdata2"
      else raise "内部错误"
      end
    source_ext = ".json"
    input_extension = @options[:unpack] ? rvdata_ext : source_ext
    output_extension = @options[:unpack] ? source_ext : rvdata_ext

    Logging::Log.info "在最终输入目录 #{@input_dir} 中搜索 *#{input_extension} 文件"

    all_files = []
    begin
      raise "最终输入目录 '#{@input_dir}' 不存在" unless Dir.exist?(@input_dir)
      Find.find(@input_dir) { |p| all_files << p if File.file?(p) && File.extname(p).downcase == input_extension.downcase }
    rescue SystemCallError => e; raise "访问输入目录 '#{@input_dir}' 时出错: #{e.message}";     end

    # 文件过滤
    filtered = all_files.select do |f|
      begin
        rel_path = Pathname.new(f).relative_path_from(@input_dir).to_s
        base = rel_path.chomp(File.extname(rel_path))
        included = @file_patterns.empty? || @file_patterns.any? { |re| base.match?(re) }
        excluded = !@exclude_patterns.empty? && @exclude_patterns.any? { |re| base.match?(re) }
        included && !excluded
      rescue ArgumentError
        Logging::Log.warn "过滤期间无法计算相对路径: '#{f}' 相对于 '#{@input_dir}'。跳过此文件。"
        false
      rescue => e
        Logging::Log.warn "过滤路径 '#{f}' 出错: #{e.message}. 跳过."; false
      end
    end.uniq.sort

    Logging::Log.info(filtered.empty? ? "未找到匹配条件的文件。" : "找到 #{filtered.size} 个文件进行处理。")
    filtered.each { |f| Logging::Log.debug "  - #{Pathname.new(f).relative_path_from(@input_dir) rescue File.basename(f)}" } if Logging::Log.debug?
    return filtered, input_extension, output_extension
  end

  # --- 辅助方法：记录处理错误 ---
  def log_processing_error(error, context, rgss_version = nil)
    Logging::Log.error "处理 #{context} 失败:"
    Logging::Log.error "  RGSS 版本: #{rgss_version || @options[:rgss_version]}" if rgss_version || @options[:rgss_version]
    Logging::Log.error "  错误: #{error.class}: #{error.message}"
    error.backtrace.first(10).each { |line| Logging::Log.error "    #{line}" }
    if error.is_a?(NameError)
      Logging::Log.error "  提示: NameError 通常表示 RGSS 版本不匹配或所需类未定义。"
    end
  end

  # --- 辅助方法：记录提取错误 ---
  def log_extraction_error(error, filename)
    rgssad_error_class = defined?(RgssadExtractor::RGSSADFileError) ? RgssadExtractor::RGSSADFileError : nil
    case error
    when rgssad_error_class
      Logging::Log.error "存档文件 '#{filename}' 处理失败 (C 扩展报告): #{error.message}"
    when SystemCallError
      Logging::Log.error "存档提取期间发生 I/O 错误 (C 扩展报告): #{error.message}"
    else
      Logging::Log.error "存档提取过程中发生未知错误: #{error.class}: #{error.message}"
      Logging::Log.error "调用栈:\n#{error.backtrace.first(10).join("\n")}"
    end
  end
end # class Application
