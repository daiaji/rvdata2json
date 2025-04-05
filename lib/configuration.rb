# 负责加载和管理配置文件

require "yaml"
require "pathname"
require_relative "application" #<--- 修改: 引入 Application 以访问 RGSS_VERSIONS

class Configuration
  DEFAULT_CONFIG_FILENAME = "config.yaml".freeze
  DEFAULT_CONFIG = {
    "rgss_version" => "RGSS3", # 默认保持 RGSS3
    "input_dir_rvdata" => "Data_O", # 适用于所有 .rxdata/.rvdata/.rvdata2
    "input_dir_json" => "Json",
    "output_dir_json" => "Json",
    "output_dir_rvdata" => "Data", # 适用于所有 .rxdata/.rvdata/.rvdata2
    "files" => [
      "Actors", "Animations", "Armors", "Classes", "CommonEvents",
      "Enemies", "Items", "MapInfos", "Skills", "States", "System",
      "Tilesets", # RGSS3 only, harmless for RGSS1/2
      "Troops", "Weapons", "Map\\d{3}",
    ],
    "exclude_files" => ["Areas", "Scripts", "Main"], # Areas is RGSS2, Scripts usually separate
  }.freeze

  attr_reader :path, :data

  def initialize(config_path_arg = nil)
    if config_path_arg
      @path = File.absolute_path?(config_path_arg) ? config_path_arg : File.expand_path(config_path_arg, Dir.pwd)
    else
      # 默认配置文件路径相对于 lib 目录的上层目录
      project_root = File.expand_path("..", __dir__) # lib 目录的上层
      @path = File.join(project_root, DEFAULT_CONFIG_FILENAME)
    end
    @data = {}
  end

  def load
    puts "加载配置文件: #{@path}"
    if File.exist?(@path)
      begin
        loaded_data = YAML.load_file(@path) || {}
        # 使用深合并，但数组采用覆盖策略
        @data = deep_merge(DEFAULT_CONFIG.dup, loaded_data)
      rescue Psych::SyntaxError => e
        raise "配置文件 YAML 语法错误: #{e.message}"
      rescue => e
        raise "加载配置文件 '#{@path}' 时出错: #{e.class}: #{e.message}"
      end
    else
      puts "警告: 配置文件未找到: #{@path}。将使用默认配置。"
      @data = DEFAULT_CONFIG.dup
    end
    validate_config # 加载或使用默认配置后进行验证
    @data
  end

  def [](key)
    @data[key]
  end

  private

  # 深合并哈希，数组使用覆盖策略 (保持不变)
  def deep_merge(hash1, hash2)
    hash2.each do |key, value|
      if hash1.key?(key) && hash1[key].is_a?(Hash) && value.is_a?(Hash)
        deep_merge(hash1[key], value)
      elsif hash1.key?(key) && hash1[key].is_a?(Array) && value.is_a?(Array)
        hash1[key] = value # 数组使用覆盖策略
      else
        hash1[key] = value
      end
    end
    hash1
  end

  # 验证配置项
  def validate_config
    # --- 修改: 检查 rgss_version 是否在 Application::RGSS_VERSIONS 中 ---
    unless @data["rgss_version"].is_a?(String) && Application::RGSS_VERSIONS.include?(@data["rgss_version"])
      raise "配置错误: 'rgss_version' 必须是 #{Application::RGSS_VERSIONS.join(" 或 ")} 之一 (当前值: #{@data["rgss_version"].inspect})"
    end
    # -------------------------------------------------------------
    # 验证目录键 (保持不变)
    %w[input_dir_rvdata input_dir_json output_dir_json output_dir_rvdata].each do |key|
      unless @data[key].is_a?(String) && !@data[key].empty?
        raise "配置错误: 缺少或无效的目录键 '#{key}' (值: #{@data[key].inspect})"
      end
    end
    # 验证文件列表键 (保持不变)
    raise "配置错误: 'files' 必须是一个数组" unless @data["files"].is_a?(Array)
    raise "配置错误: 'exclude_files' 必须是一个数组" unless @data["exclude_files"].is_a?(Array)
  end
end
