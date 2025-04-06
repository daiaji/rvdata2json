# 为应用程序设置全局日志记录器接口

require "logger"     # Ruby 标准日志库
require "fileutils"  # 用于创建日志目录
require "pathname"   # 用于处理日志文件路径

# --- 日志模块 ---
module Logging
  # ANSI 颜色代码，用于在支持的终端中彩色输出
  COLORS = {
    DEBUG: "\e[36m", # 青色
    INFO: "\e[32m",  # 绿色
    WARN: "\e[33m",  # 黄色
    ERROR: "\e[31m", # 红色
    FATAL: "\e[35m", # 紫色
    UNKNOWN: "\e[37m", # 白色/灰色
    RESET: "\e[0m",  # 重置颜色
  }.freeze

  # 有效的日志级别字符串常量
  VALID_LOG_LEVELS = %w[DEBUG INFO WARN ERROR FATAL UNKNOWN].freeze

  # --- 内部状态变量 ---
  @console_logger = nil  # 控制台 Logger 实例
  @file_logger = nil     # 文件 Logger 实例
  @log_file_handle = nil # 打开的日志文件句柄
  @log_level_int = Logger::INFO # 当前生效的日志级别 (整数形式)，默认为 INFO

  # --- 日志记录接口模块 Log ---
  # 提供统一的日志记录方法，如 Log.info, Log.warn 等
  module Log
    # 核心日志记录方法
    # 同时记录到控制台和文件（如果它们已初始化且级别允许）
    # @param level [Integer] Logger::Severity 常量 (如 Logger::INFO)
    # @param message [String, nil] 要记录的消息，或 nil 如果使用块
    # @param block [Proc, nil] 用于生成消息的块 (惰性计算)
    def self.log(level, message = nil, &block)
      # 记录到控制台 (如果已创建且级别允许)
      Logging.instance_variable_get(:@console_logger)&.add(level, message, nil, &block)
      # 记录到文件 (如果已创建且级别允许)
      Logging.instance_variable_get(:@file_logger)&.add(level, message, nil, &block)
    end

    # --- 定义便捷方法: debug, info, warn, error, fatal ---
    Logger::Severity.constants.each do |severity_name|
      # 跳过 UNKNOWN 级别
      next if severity_name == :UNKNOWN

      level_int = Logger::Severity.const_get(severity_name) # 获取对应的整数级别
      method_name = severity_name.downcase # 方法名 (e.g., :info)

      # 定义日志记录方法，如 Log.info(message)
      define_singleton_method(method_name) do |message = nil, &block|
        # 只有当消息级别高于或等于当前设置的日志级别时才记录
        if level_int >= Logging.instance_variable_get(:@log_level_int)
          log(level_int, message, &block)
        end
      end

      # 定义检查级别的方法，如 Log.info?
      define_singleton_method("#{method_name}?") do
        level_int >= Logging.instance_variable_get(:@log_level_int)
      end
    end
    # --- 便捷方法定义结束 ---

    # 获取当前生效的日志级别 (整数形式)
    def self.level
      Logging.instance_variable_get(:@log_level_int)
    end
  end # --- 结束 Log 模块 ---

  # --- 设置日志记录器 ---
  # 根据配置和命令行参数初始化控制台和文件记录器
  # @param config_data [Hash] 从 config.yaml 加载的哈希
  # @param game_dir [String] 游戏根目录的绝对路径 (用于解析相对日志目录)
  # @param cli_log_level [String, nil] 命令行指定的日志级别 (覆盖配置)
  # @param cli_log_dir [String, nil] 命令行指定的日志目录 (覆盖配置)
  def self.setup_logger(config_data, game_dir, cli_log_level = nil, cli_log_dir = nil)
    config_logging = config_data["logging"] || {} # 获取配置中的 logging 部分，不存在则为空哈希

    # --- 确定最终的日志设置 (优先级: 命令行 > 配置文件 > 默认值) ---

    # 1. 确定日志级别
    log_level_str = "INFO" # 默认级别
    # 从配置文件加载 (如果存在)
    log_level_str = config_logging["log_level"]&.upcase if config_logging["log_level"] && !config_logging["log_level"].empty?
    # 从命令行覆盖 (如果提供)
    log_level_str = cli_log_level.upcase if cli_log_level && !cli_log_level.empty?

    # 验证日志级别字符串是否有效
    unless VALID_LOG_LEVELS.include?(log_level_str)
      $stderr.puts "[警告] 无效的日志级别 '#{log_level_str}'。将使用默认级别 INFO。"
      log_level_str = "INFO"
    end

    # 将字符串级别转换为 Logger 库使用的整数级别
    begin
      @log_level_int = Logger.const_get(log_level_str)
    rescue NameError
      @log_level_int = Logger::INFO # 再次确保有默认值
    end

    # 2. 确定是否启用文件日志和日志目录
    log_to_file = false       # 默认不写入文件
    log_directory = "logs"    # 默认日志目录名

    # 从配置加载 (仅当 log_to_file 为 true 时才关心目录)
    if config_logging["log_to_file"] == true # 显式检查 true
      log_to_file = true
      # 使用配置中的目录名，如果存在且非空
      log_directory = config_logging["log_directory"] || log_directory if config_logging["log_directory"] && !config_logging["log_directory"].empty?
    end

    # 命令行覆盖：如果指定了 --log-dir，则强制启用文件日志并使用该目录
    if cli_log_dir && !cli_log_dir.empty?
      log_to_file = true
      log_directory = cli_log_dir
    end

    # 3. 确定日志文件名格式
    log_filename_format = config_logging["log_filename_format"] || "rvdata2json_{timestamp}.log"
    log_filename_format = "rvdata2json_{timestamp}.log" if log_filename_format.empty? # 防止空格式

    # 4. 确定是否启用控制台颜色
    enable_colors = true # 默认启用
    # 从配置加载 (显式检查布尔值)
    enable_colors = config_logging["enable_colors"] if [true, false].include?(config_logging["enable_colors"])
    # (未来可以添加命令行覆盖颜色的选项)

    # --- 创建控制台 Logger ---
    console_is_tty = STDERR.tty? # 检查 STDERR 是否连接到终端
    use_colors_on_console = enable_colors && console_is_tty # 仅在启用颜色且连接到终端时使用
    @console_logger = Logger.new(STDERR) # 日志输出到标准错误流
    @console_logger.level = @log_level_int # 设置级别
    @console_logger.formatter = proc do |severity, datetime, progname, msg|
      # 获取严重性级别的名称 (兼容不同 Logger 版本)
      severity_name = if severity.is_a?(Integer)
          Logger::SEV_LABEL[severity] || "UNKNOWN"
        else
          severity.to_s # Logger 1.3+ 直接传递名称
        end
      severity_sym = severity_name.to_sym rescue :UNKNOWN

      # 确保消息是 UTF-8 字符串，替换无效字符
      formatted_msg = begin
          String(msg).encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        rescue => e
          "[编码错误: #{e.message}] #{msg.inspect rescue "无法检查的对象"}"
        end
      timestamp = datetime.strftime("%H:%M:%S") # 控制台使用简洁时间戳

      # 根据是否启用颜色选择格式
      if use_colors_on_console
        color = COLORS[severity_sym] || COLORS[:UNKNOWN]
        reset = COLORS[:RESET]
        "#{timestamp} #{color}[#{severity_name.ljust(5)}]#{reset} #{formatted_msg}\n"
      else
        "#{timestamp} [#{severity_name.ljust(5)}] #{formatted_msg}\n"
      end
    end
    # --- 控制台 Logger 创建结束 ---

    # --- 创建文件 Logger (如果启用) ---
    log_file_path = nil
    if log_to_file
      log_dir_path = nil
      begin
        # --- 处理日志目录路径 ---
        log_dir_path = Pathname.new(log_directory)
        # 如果是相对路径，则基于 game_dir 解析
        unless log_dir_path.absolute?
          log_dir_path = Pathname.new(File.expand_path(log_directory, game_dir))
        end
        # --- 路径处理结束 ---

        # 创建日志目录 (如果不存在)
        log_dir_path.mkpath unless log_dir_path.directory?

        # 生成带时间戳的文件名
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        log_filename = log_filename_format.gsub("{timestamp}", timestamp)
        log_file_path = log_dir_path.join(log_filename)

        # --- 打开日志文件 ---
        # 关闭可能存在的旧文件句柄
        @log_file_handle&.close unless @log_file_handle&.closed?
        # 以追加模式 ('a') 打开新文件，确保 UTF-8 编码
        @log_file_handle = File.open(log_file_path, "a:UTF-8")
        @log_file_handle.sync = true # 强制立即写入，避免缓冲丢失日志
        # --- 文件打开结束 ---

        # 创建文件 Logger 实例
        @file_logger = Logger.new(@log_file_handle)
        @file_logger.level = @log_level_int
        # 文件 Logger 的格式化程序 - *从不*使用颜色
        @file_logger.formatter = proc do |severity, datetime, progname, msg|
          severity_name = if severity.is_a?(Integer)
              Logger::SEV_LABEL[severity] || "UNKNOWN"
            else
              severity.to_s
            end
          formatted_msg = begin
              String(msg).encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
            rescue => e
              "[编码错误: #{e.message}] #{msg.inspect rescue "无法检查的对象"}"
            end
          timestamp = datetime.strftime("%Y-%m-%d %H:%M:%S") # 文件日志使用更详细的时间戳
          "#{timestamp} [#{severity_name.ljust(5)}] #{formatted_msg}\n" # 无颜色
        end

        # 在控制台报告日志文件路径 (使用 @console_logger 确保输出)
        @console_logger.info("日志已启用并写入文件: #{log_file_path.expand_path}")
      rescue SystemCallError => e
        # 处理创建目录或打开文件时的系统错误
        log_dir_desc = log_dir_path ? "'#{log_dir_path}'" : "'#{log_directory}'"
        @console_logger&.error("无法创建或打开日志目录 #{log_dir_desc}: #{e.message}。将仅记录到 STDERR。")
        @file_logger = nil
        @log_file_handle = nil # 确保句柄也置空
      rescue => e
        # 处理其他设置文件日志时的意外错误
        @console_logger&.error("设置日志文件时发生意外错误: #{e.class}: #{e.message}。将仅记录到 STDERR。")
        @file_logger = nil
        @log_file_handle = nil
      end
    else
      # 如果未启用文件日志，则明确将文件记录器置为 nil
      @file_logger = nil
      @log_file_handle = nil
    end
    # --- 文件 Logger 创建结束 ---

    # --- 记录初始化完成消息 ---
    # 描述日志目标
    log_target_desc = if @file_logger && log_file_path
        "STDERR 和文件 (#{log_file_path.expand_path})"
      else
        "仅 STDERR"
      end
    # 使用控制台记录器报告初始化状态 (因为它总是可用)
    @console_logger.info("日志接口已初始化。级别: #{log_level_str}。控制台颜色: #{use_colors_on_console}。日志目标: #{log_target_desc}")
    # --- 初始化消息结束 ---

  end # def setup_logger end

  # --- 程序退出时自动清理 ---
  at_exit do
    # 确保关闭文件句柄
    if @log_file_handle && !@log_file_handle.closed?
      begin
        # 尝试通过文件记录器写入关闭消息
        @file_logger&.info("关闭日志文件。")
      rescue => e
        # 忽略退出时写入日志可能发生的错误
      end
      begin
        # 关闭文件句柄
        @log_file_handle.close
      rescue => e
        # 忽略关闭文件句柄时可能发生的错误
      end
    end
  end
  # --- 清理结束 ---

end # module Logging
