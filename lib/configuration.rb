# encoding: utf-8
# rvdata2json/lib/configuration.rb
# 负责加载和管理配置文件

require "yaml"
require "pathname"

class Configuration
  # 默认配置文件名
  DEFAULT_CONFIG_FILENAME = "config.yaml".freeze
  # 默认配置值
  DEFAULT_CONFIG = {
    "rgss_version" => "RGSS3",
    "input_dir_rvdata" => "Data_O",
    "input_dir_json" => "Json",
    "output_dir_json" => "Json",
    "output_dir_rvdata" => "Data",
    "files" => [
      "Actors", "Animations", "Armors", "Classes", "CommonEvents",
      "Enemies", "Items", "MapInfos", "Skills", "States", "System",
      "Tilesets", "Troops", "Weapons", "Map\\d{3}",
    ],
    "exclude_files" => ["Areas", "Scripts", "Main"],
  }.freeze

  attr_reader :path, :data

  # @param config_path_arg [String, nil] 命令行传入的配置文件路径
  def initialize(config_path_arg = nil)
    # 优先使用命令行参数指定的路径
    # 如果未指定，则在脚本所在的目录的父目录（通常是项目根目录）查找默认文件名
    if config_path_arg
      # 如果命令行指定的是相对路径，相对于当前工作目录解析
      @path = File.absolute_path?(config_path_arg) ? config_path_arg : File.expand_path(config_path_arg, Dir.pwd)
    else
      # 默认在脚本所在的目录的父目录查找 config.yaml
      # __dir__ 是 lib 目录, '..' 指向项目根目录
      project_root = File.expand_path("..", __dir__)
      @path = File.join(project_root, DEFAULT_CONFIG_FILENAME)
    end
    @data = {}
  end

  # 加载配置文件
  # @return [Hash] 加载并合并了默认值的配置数据
  def load
    puts "加载配置文件: #{@path}"
    if File.exist?(@path)
      begin
        loaded_data = YAML.load_file(@path) || {}
        # 使用深合并，避免覆盖嵌套结构（例如 files 列表）
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
    validate_config
    @data
  end

  # 提供方便的访问器
  def [](key)
    @data[key]
  end

  private

  # 递归合并两个哈希
  def deep_merge(hash1, hash2)
    hash2.each do |key, value|
      if hash1.key?(key) && hash1[key].is_a?(Hash) && value.is_a?(Hash)
        deep_merge(hash1[key], value)
      elsif hash1.key?(key) && hash1[key].is_a?(Array) && value.is_a?(Array)
        # 对于数组，通常选择覆盖而不是合并，但可以根据需要修改
        hash1[key] = value
      else
        hash1[key] = value
      end
    end
    hash1
  end

  # 验证配置数据的基本有效性
  def validate_config
    unless @data["rgss_version"].is_a?(String) && ["RGSS2", "RGSS3"].include?(@data["rgss_version"])
      raise "配置错误: 'rgss_version' 必须是 'RGSS2' 或 'RGSS3'"
    end
    %w[input_dir_rvdata input_dir_json output_dir_json output_dir_rvdata].each do |key|
      raise "配置错误: 缺少或无效的目录键 '#{key}' (值: #{@data[key].inspect})" unless @data[key].is_a?(String) && !@data[key].empty?
    end
    raise "配置错误: 'files' 必须是一个数组" unless @data["files"].is_a?(Array)
    raise "配置错误: 'exclude_files' 必须是一个数组" unless @data["exclude_files"].is_a?(Array)
  end
end
