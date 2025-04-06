# 负责加载和管理 YAML 配置文件

require "yaml"         # 用于解析 YAML 文件
require "pathname"     # 用于处理文件路径
require_relative "logging" # 加载日志模块以访问常量和进行验证 (虽然主要日志记录在 Application 中)
require_relative "application" # 引入 Application 以访问 RGSS_VERSIONS 常量

class Configuration
  # 默认配置文件名
  DEFAULT_CONFIG_FILENAME = "config.yaml".freeze

  # 默认配置项
  # 如果配置文件不存在或缺少某些键，将使用这些默认值
  DEFAULT_CONFIG = {
    # 默认 RGSS 版本 (在自动检测失败且命令行未指定时使用)
    "rgss_version" => "RGSS3", # 可选: "RGSS1", "RGSS2", "RGSS3"

    # 输入目录 (相对于游戏根目录)
    "input_dir_marshal" => "Data_原始", # 存放原始 RVData/RXData 文件的目录
    "input_dir_source" => "Source",    # 存放 JSON 和 Scripts 子目录的目录

    # 输出目录 (相对于游戏根目录)
    "output_dir_source" => "Source",    # 输出 JSON 和 Scripts 子目录的目录
    "output_dir_marshal" => "Data",     # 输出 RVData/RXData 文件的目录

    # 要处理的文件基础名列表 (作为不区分大小写的正则表达式处理)
    "files" => [
      "Actors", "Animations", "Armors", "Classes", "CommonEvents",
      "Enemies", "Items", "MapInfos", "Scripts", "Skills", "States", "System",
      "Tilesets", "Troops", "Weapons", "Map\\d{3}", # 匹配 Map001, Map002 等
    ],

    # 要排除的文件基础名列表 (作为不区分大小写的正则表达式处理)
    "exclude_files" => ["Areas", "Main"], # 例如，排除 RGSS2 特有的 Areas 文件

    # --- 日志配置 ---
    "logging" => {
      # 日志级别 (DEBUG, INFO, WARN, ERROR, FATAL, UNKNOWN)
      "log_level" => "INFO",
      # 是否启用文件日志
      "log_to_file" => false,
      # 日志文件存放目录 (相对于游戏根目录)
      "log_directory" => "logs",
      # 日志文件名格式 ({timestamp} 会被替换)
      "log_filename_format" => "rvdata2json_{timestamp}.log",
      # 是否在控制台启用彩色输出
      "enable_colors" => true,
    },
  # -----------------------
  }.freeze

  # 配置文件的路径
  attr_reader :path
  # 加载并合并后的配置数据
  attr_reader :data

  # 初始化 Configuration 对象
  # @param config_path_arg [String, nil] 命令行指定的配置文件路径，或 nil 使用默认路径
  def initialize(config_path_arg = nil)
    if config_path_arg
      # 如果指定了路径，根据是绝对路径还是相对路径进行处理
      @path = File.absolute_path?(config_path_arg) ? config_path_arg : File.expand_path(config_path_arg, Dir.pwd)
    else
      # 如果未指定路径，使用项目根目录下的默认文件名
      project_root = File.expand_path("..", __dir__) # 获取 lib 目录的上级目录
      @path = File.join(project_root, DEFAULT_CONFIG_FILENAME)
    end
    @data = {} # 初始化为空哈希
  end

  # 加载配置文件并与默认配置合并
  # @return [Hash] 合并后的配置数据
  # @raise [RuntimeError] 如果 YAML 文件语法错误或加载失败
  # @raise [RuntimeError] 如果配置项验证失败
  def load
    loaded_data = {}
    if File.exist?(@path)
      begin
        # 从 YAML 文件加载数据
        loaded_data = YAML.load_file(@path) || {} # 如果文件为空，返回空哈希
      rescue Psych::SyntaxError => e
        # 处理 YAML 语法错误
        raise "配置文件 YAML 语法错误: #{e.message}"
      rescue => e
        # 处理其他加载错误
        raise "加载配置文件 '#{@path}' 时出错: #{e.class}: #{e.message}"
      end
    else
      # 配置文件不存在的情况将在 Application 中记录日志，这里无需处理
    end

    # 将加载的数据深度合并到默认配置上 (配置文件中的值覆盖默认值)
    @data = deep_merge(DEFAULT_CONFIG.dup, loaded_data) # 使用 dup 避免修改 DEFAULT_CONFIG
    # 验证合并后的配置
    validate_config
    @data
  end

  # 提供便捷的访问配置项的方法 (例: config["rgss_version"])
  def [](key)
    @data[key]
  end

  private

  # 深度合并两个哈希
  # @param hash1 [Hash] 基础哈希 (通常是默认配置)
  # @param hash2 [Hash] 要合并进来的哈希 (通常是加载的配置)
  # @return [Hash] 合并后的哈希 (hash1 会被修改)
  def deep_merge(hash1, hash2)
    hash2.each do |key, value|
      if hash1.key?(key) && hash1[key].is_a?(Hash) && value.is_a?(Hash)
        # 如果键在两个哈希中都存在且值都是哈希，则递归合并
        deep_merge(hash1[key], value)
      elsif hash1.key?(key) && hash1[key].is_a?(Array) && value.is_a?(Array)
        # 如果键在两个哈希中都存在且值都是数组，则使用 hash2 的数组覆盖 hash1 的数组
        hash1[key] = value
      else
        # 其他情况，直接用 hash2 的值覆盖 hash1 的值
        hash1[key] = value
      end
    end
    hash1
  end

  # 验证合并后的配置数据是否有效
  # @raise [RuntimeError] 如果验证失败
  def validate_config
    # --- 验证 RGSS 版本 ---
    rgss_version_valid = @data["rgss_version"].is_a?(String) && Application::RGSS_VERSIONS.include?(@data["rgss_version"])
    unless rgss_version_valid
      raise "配置错误: 'rgss_version' 必须是 #{Application::RGSS_VERSIONS.join(" 或 ")} 之一 (当前值: #{@data["rgss_version"].inspect})"
    end

    # --- 验证目录路径 ---
    %w[input_dir_marshal input_dir_source output_dir_source output_dir_marshal].each do |key|
      unless @data[key].is_a?(String) && !@data[key].empty?
        raise "配置错误: 缺少或无效的目录键 '#{key}' (值: #{@data[key].inspect})"
      end
    end

    # --- 验证文件列表 ---
    raise "配置错误: 'files' 必须是一个数组" unless @data["files"].is_a?(Array)
    raise "配置错误: 'exclude_files' 必须是一个数组" unless @data["exclude_files"].is_a?(Array)

    # --- 验证日志配置 ---
    log_config = @data["logging"] || {}
    unless log_config.is_a?(Hash)
      raise "配置错误: 'logging' 部分必须是一个哈希 (字典/映射)。"
    end

    log_level = log_config["log_level"]
    # 检查日志级别是否有效 (允许为 nil，表示使用默认或命令行覆盖)
    unless log_level.nil? || (log_level.is_a?(String) && Logging::VALID_LOG_LEVELS.include?(log_level.upcase))
      raise "配置错误: 'logging.log_level' 必须是字符串且为 #{Logging::VALID_LOG_LEVELS.join(", ")} 之一 (当前: #{log_level.inspect})"
    end

    # 对 log_to_file, log_directory, log_filename_format, enable_colors 的类型验证可以在 Logging.setup_logger 中进行，
    # 这里只做基本检查，确保 logging 部分是 Hash 并且 log_level (如果存在) 是有效的。
  end
end
