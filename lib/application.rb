# 应用主流程控制

require "optparse"
require "pathname"
require "find"
require "fileutils"
require "inifile"
require "set"

require_relative "configuration"
require_relative "converter"
require_relative "utils"

class Application
  # 支持的 RGSS 版本
  RGSS_VERSIONS = %w[RGSS2 RGSS3].freeze

  def initialize(argv)
    @argv = argv
    @options = {
      config: nil,
      rgss_version: nil,
      to_json: false,
      to_rvdata: false,
      game_dir: Dir.pwd, # 默认为当前工作目录
    }
    @config = nil
    @input_dir = nil
    @output_dir = nil
  end

  # 运行应用
  def run
    begin
      parse_options
      load_configuration # 使用命令行传入的 config 路径（或默认）
      determine_game_directory
      determine_rgss_version
      validate_options
      load_rgss_module
      setup_directories
      process_files
      puts "转换完成。"
    rescue => e
      $stderr.puts "[致命错误] 执行失败: #{e.message}"
      $stderr.puts e.backtrace.join("\n")
      exit 1
    end
  end

  private

  # 解析命令行选项
  def parse_options
    OptionParser.new do |opts|
      opts.banner = "用法: rvdata2json.rb [选项]"
      opts.separator ""
      opts.separator "选项:"

      opts.on("-c", "--config FILE", "指定配置文件路径 (默认为项目根目录下的 config.yaml)") do |file|
        @options[:config] = file
      end
      opts.on("--rgss2", "强制使用 RGSS2 (RPG Maker VX)") { @options[:rgss_version] = "RGSS2" }
      opts.on("--rgss3", "强制使用 RGSS3 (RPG Maker VX Ace)") { @options[:rgss_version] = "RGSS3" }
      opts.on("--to-json", "将 RVData 文件转换为 JSON") { @options[:to_json] = true }
      opts.on("--to-rvdata", "将 JSON 文件转换为 RVData") { @options[:to_rvdata] = true }
      opts.on("-g", "--game-dir DIR", "指定游戏根目录 (默认为当前工作目录)") do |dir|
        @options[:game_dir] = dir
      end
      opts.on_tail("-h", "--help", "显示此帮助信息") { puts opts; exit }
    end.parse!(@argv)
  end

  # 加载配置
  def load_configuration
    config_loader = Configuration.new(@options[:config])
    @config = config_loader.load
  end

  # 确定并验证游戏目录
  def determine_game_directory
    @options[:game_dir] = File.expand_path(@options[:game_dir])
    unless Dir.exist?(@options[:game_dir])
      raise "指定的游戏目录不存在: #{@options[:game_dir]}"
    end
    puts "游戏目录设置为: #{@options[:game_dir]}"
  end

  # 确定 RGSS 版本 (命令行优先 > 自动检测 > 配置 > 默认)
  def determine_rgss_version
    return if @options[:rgss_version]

    begin
      detected_version = detect_rgss_version_from_game_ini
      @options[:rgss_version] = detected_version
      puts "从 Game.ini 自动检测到 RGSS 版本: #{@options[:rgss_version]}"
    rescue => e
      puts "警告: 自动检测 RGSS 版本失败: #{e.message}"
      fallback_version = @config["rgss_version"] # 配置加载时已处理默认值
      @options[:rgss_version] = fallback_version
      puts "回退到配置指定的 RGSS 版本: #{@options[:rgss_version]}"
    end
  end

  # 从 Game.ini 检测 RGSS 版本
  def detect_rgss_version_from_game_ini
    game_ini_path = File.join(@options[:game_dir], "Game.ini")
    raise "未在游戏目录中找到 Game.ini" unless File.exist?(game_ini_path)

    encoding = detect_file_encoding(game_ini_path)
    puts "检测到 Game.ini 编码: #{encoding}"

    begin
      ini_file = IniFile.load(game_ini_path, encoding: encoding)
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError => e
      puts "警告: 使用编码 #{encoding} 加载 Game.ini 失败: #{e.message}。尝试使用 UTF-8..."
      begin
        ini_file = IniFile.load(game_ini_path, encoding: "UTF-8")
      rescue => e_utf8
        raise "加载或解析 Game.ini (尝试了 #{encoding} 和 UTF-8) 失败: #{e_utf8.message}"
      end
    rescue => e
      raise "加载或解析 Game.ini 失败 (编码: #{encoding}): #{e.message}"
    end

    unless ini_file && ini_file.has_section?("Game") && ini_file["Game"].has_key?("RTP")
      raise "Game.ini 格式不正确或缺少 [Game] -> RTP 信息。"
    end
    rtp_value = ini_file["Game"]["RTP"]&.strip

    raise "Game.ini RTP 值为空。" if rtp_value.nil? || rtp_value.empty?

    puts "Game.ini RTP 值为: #{rtp_value.inspect}"
    case rtp_value
    when /RPGVXAce/i then "RGSS3"
    when /RPGVX/i then "RGSS2"
    else raise "无法从 RTP 值 '#{rtp_value}' 推断 RGSS 版本"
    end
  end

  # 检测文件编码
  def detect_file_encoding(file_path)
    content_sample = File.binread(file_path, 4096) || ""
    detected_encoding_obj = Utils.send(:detect_encoding_safe, content_sample)
    detected_encoding_name = detected_encoding_obj ? detected_encoding_obj.name : "UTF-8"

    case detected_encoding_name.upcase
    when "GB2312" then "GBK"
    when "WINDOWS-1252", "ASCII-8BIT" then "UTF-8"
    else detected_encoding_name
    end
  rescue => e
    puts "[警告] 检测文件编码 '#{file_path}' 时出错: #{e.message}。假定为 UTF-8。"
    "UTF-8"
  end

  # 验证选项有效性
  def validate_options
    unless @options[:to_json] ^ @options[:to_rvdata]
      raise "必须指定 --to-json 或 --to-rvdata 中的一个。"
    end
    unless RGSS_VERSIONS.include?(@options[:rgss_version])
      raise "无效的 RGSS 版本: '#{@options[:rgss_version]}'. 支持: #{RGSS_VERSIONS.join(", ")}"
    end
  end

  # 加载对应的 RGSS 定义模块
  def load_rgss_module
    begin
      rgss_lib_file = "lib/#{@options[:rgss_version].downcase}.rb"
      require_relative @options[:rgss_version].downcase
      puts "已加载 RGSS 定义: #{rgss_lib_file}"
    rescue LoadError => e
      raise "加载 RGSS 定义文件 '#{rgss_lib_file}' 失败: #{e.message}"
    end
  end

  # 设置输入输出目录路径
  def setup_directories
    input_dir_key = @options[:to_json] ? "input_dir_rvdata" : "input_dir_json"
    output_dir_key = @options[:to_json] ? "output_dir_json" : "output_dir_rvdata"

    @input_dir = File.expand_path(@config[input_dir_key], @options[:game_dir])
    @output_dir = File.expand_path(@config[output_dir_key], @options[:game_dir])

    puts "输入目录: #{@input_dir}"
    puts "输出目录: #{@output_dir}"

    raise "输入目录不存在: #{@input_dir}" unless Dir.exist?(@input_dir)
  end

  # 处理文件转换流程
  def process_files
    file_list, input_extension, output_extension = get_file_list

    exporter = Converter::JsonExporter.new(@options[:rgss_version]) if @options[:to_json]
    restorer = Converter::RvdataRestorer.new(@options[:rgss_version]) if @options[:to_rvdata]

    file_list.each do |input_file|
      relative_path = Pathname.new(input_file).relative_path_from(Pathname.new(@input_dir)).to_s
      output_file = File.join(@output_dir, relative_path.chomp(input_extension) + output_extension)

      begin
        if @options[:to_json]
          puts "转换 #{File.basename(input_file)} -> JSON..."
          input_object = Converter::IO.load_marshal_data(input_file)
          # ******** 修改点 ********
          # 捕获 exporter.export 返回的清理后的数据结构
          cleaned_data = exporter.export(input_object)
          # 将清理后的数据结构写入 JSON 文件
          Converter::IO.write_json_data(output_file, cleaned_data)
          # ******** 结束修改 ********
        else # to_rvdata
          puts "转换 #{File.basename(input_file)} -> RVData..."
          input_data = Converter::IO.load_json_data(input_file)
          restored_object = restorer.restore(input_data)
          Converter::IO.write_marshal_data(output_file, restored_object)
        end
        puts "  输出: #{output_file}"
      rescue => e
        $stderr.puts "[错误] 处理文件 '#{File.basename(input_file)}' 失败:"
        $stderr.puts "  RGSS 版本: #{@options[:rgss_version]}"
        $stderr.puts "  错误: #{e.class}: #{e.message}"
        e.backtrace.first(10).each { |line| $stderr.puts "    #{line}" }
        raise
      end
    end
  end

  # 获取待处理文件列表
  def get_file_list
    rvdata_extension = (@options[:rgss_version] == "RGSS2") ? ".rvdata" : ".rvdata2"
    json_extension = ".json"

    input_extension = @options[:to_json] ? rvdata_extension : json_extension
    output_extension = @options[:to_json] ? json_extension : rvdata_extension

    puts "查找输入文件扩展名: #{input_extension}"

    all_files = []
    Find.find(@input_dir) do |path|
      all_files << path if File.file?(path) && File.extname(path).downcase == input_extension.downcase
    end

    file_patterns = @config["files"]&.map { |pattern| Regexp.new(pattern, Regexp::IGNORECASE) } || []
    exclude_patterns = @config["exclude_files"]&.map { |pattern| Regexp.new(pattern, Regexp::IGNORECASE) } || []

    filtered_files = all_files.select do |file_path|
      relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(@input_dir)).to_s
      basename = relative_path.chomp(File.extname(relative_path))

      included = file_patterns.empty? || file_patterns.any? { |regex| basename.match?(regex) }
      excluded = !exclude_patterns.empty? && exclude_patterns.any? { |regex| basename.match?(regex) }

      included && !excluded
    end

    filtered_files.uniq!
    filtered_files.sort!

    if filtered_files.empty?
      puts "在目录 '#{@input_dir}' 中未找到符合条件的文件 (扩展名: #{input_extension})。"
      exit
    end

    puts "找到 #{filtered_files.length} 个待处理文件。"
    return filtered_files, input_extension, output_extension
  end
end
