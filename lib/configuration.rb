# lib/configuration.rb
# 负责加载和管理 YAML 配置文件

require "yaml"
require "pathname"
require_relative "logging"
# 不直接 require application 以避免循环依赖

class Configuration
  DEFAULT_CONFIG_FILENAME = "config.yaml".freeze

  # 默认配置项
  DEFAULT_CONFIG = {
    "rgss_version" => "RGSS3",
    # --- 注意: 这些路径是相对于 --base-dir (基准目录) 的 ---
    "input_dir_marshal" => "Data",
    "input_dir_source" => "Source",
    "output_dir_source" => "Source",
    "output_dir_marshal" => "Data",
    # ----------------------------------------------------
    "files" => [
      "Actors", "Animations", "Armors", "Classes", "CommonEvents",
      "Enemies", "Items", "MapInfos", "Scripts", "Skills", "States", "System",
      "Tilesets", "Troops", "Weapons", "Map\\d{3}",
    ],
    "exclude_files" => ["Areas"],
    "archive_processing" => {
      "enabled" => true,
      "archive_filenames" => {
        "RGSS1" => "Game.rgssad",
        "RGSS2" => "Game.rgss2a",
        "RGSS3" => "Game.rgss3a",
      },
      "delete_archive_after_extraction" => false,
    },
    "logging" => {
      "log_level" => "INFO",
      "log_to_file" => false,
      # --- 注意: log_directory 也是相对于 --base-dir (基准目录) 的 ---
      "log_directory" => "logs",
      # ----------------------------------------------------------
      "log_filename_format" => "rvdata2json_{timestamp}.log",
      "enable_colors" => true,
    },
  }.freeze

  attr_reader :path
  attr_reader :data

  # 初始化 Configuration 对象
  # @param config_path_arg [String, nil] 命令行指定的配置文件路径，或 nil 使用默认路径
  def initialize(config_path_arg = nil)
    if config_path_arg
      # 如果指定了路径，根据是绝对路径还是相对路径进行处理
      # 注意：这里的相对路径是相对于当前工作目录
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
    validate_config # 验证合并后的配置
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
    # 延迟加载 Application 常量以避免循环依赖
    unless defined?(Application::RGSS_VERSIONS)
      begin
        require_relative "application" unless defined?(Application) # 只有未定义时才加载
      rescue LoadError
        raise "无法加载 Application 类来验证 RGSS 版本。"
      end
    end

    # --- 验证 RGSS 版本 ---
    rgss_version = @data["rgss_version"]
    unless rgss_version.is_a?(String) && Application::RGSS_VERSIONS.include?(rgss_version)
      raise "配置错误: 'rgss_version' 必须是 #{Application::RGSS_VERSIONS.join(" 或 ")} 之一 (当前值: #{rgss_version.inspect})"
    end

    # --- 验证目录路径 ---
    %w[input_dir_marshal input_dir_source output_dir_source output_dir_marshal].each do |key|
      dir_path = @data[key]
      unless dir_path.is_a?(String) && !dir_path.empty?
        raise "配置错误: 缺少或无效的目录键 '#{key}' (值: #{dir_path.inspect})"
      end
    end

    # --- 验证文件列表 ---
    files_list = @data["files"]
    exclude_files_list = @data["exclude_files"]
    raise "配置错误: 'files' 必须是一个数组" unless files_list.is_a?(Array)
    raise "配置错误: 'exclude_files' 必须是一个数组" unless exclude_files_list.is_a?(Array)

    # --- 验证存档处理配置 ---
    archive_config = @data["archive_processing"] || {}
    raise "配置错误: 'archive_processing' 部分必须是一个哈希" unless archive_config.is_a?(Hash)

    enabled_flag = archive_config["enabled"]
    raise "配置错误: 'archive_processing.enabled' 必须是 true 或 false (当前值: #{enabled_flag.inspect})" unless [true, false].include?(enabled_flag)

    filenames_hash = archive_config["archive_filenames"]
    raise "配置错误: 'archive_processing.archive_filenames' 必须是一个哈希" unless filenames_hash.is_a?(Hash)
    Application::RGSS_VERSIONS.each do |version|
      filename = filenames_hash[version]
      unless filename.is_a?(String) && !filename.empty?
        raise "配置错误: 'archive_processing.archive_filenames' 中缺少或无效的版本 '#{version}' 条目 (值: #{filename.inspect})"
      end
    end

    # --- 验证 delete_archive_after_extraction ---
    delete_flag = archive_config["delete_archive_after_extraction"]
    raise "配置错误: 'archive_processing.delete_archive_after_extraction' 必须是 true 或 false (当前值: #{delete_flag.inspect})" unless [true, false].include?(delete_flag)
    # -----------------------------------------------

    # --- 验证日志配置 ---
    log_config = @data["logging"] || {}
    raise "配置错误: 'logging' 部分必须是一个哈希" unless log_config.is_a?(Hash)

    log_level = log_config["log_level"]
    # 延迟加载 Logging 常量
    unless defined?(Logging::VALID_LOG_LEVELS)
      begin
        require_relative "logging" unless defined?(Logging) # 只有未定义时才加载
      rescue LoadError
        raise "无法加载 Logging 模块来验证日志级别。"
      end
    end
    unless log_level.nil? || (log_level.is_a?(String) && Logging::VALID_LOG_LEVELS.include?(log_level.upcase))
      raise "配置错误: 'logging.log_level' 必须是字符串且为 #{Logging::VALID_LOG_LEVELS.join(", ")} 之一 (当前: #{log_level.inspect})"
    end

    log_to_file = log_config["log_to_file"]
    raise "配置错误: 'logging.log_to_file' 必须是 true 或 false (当前: #{log_to_file.inspect})" unless [true, false].include?(log_to_file)

    log_directory = log_config["log_directory"]
    raise "配置错误: 'logging.log_directory' 必须是一个字符串 (当前: #{log_directory.inspect})" unless log_directory.is_a?(String)

    log_filename_format = log_config["log_filename_format"]
    raise "配置错误: 'logging.log_filename_format' 必须是一个字符串 (当前: #{log_filename_format.inspect})" unless log_filename_format.is_a?(String)

    enable_colors = log_config["enable_colors"]
    raise "配置错误: 'logging.enable_colors' 必须是 true 或 false (当前: #{enable_colors.inspect})" unless [true, false].include?(enable_colors)
  end
end
