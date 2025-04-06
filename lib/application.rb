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
  RGSS_VERSIONS = %w[RGSS1 RGSS2 RGSS3].freeze
  SCRIPTS_BASENAME = "scripts".freeze # 小写用于比较

  def initialize(argv)
    @argv = argv
    @options = {
      config: nil,
      rgss_version: nil,
      unpack: false,
      pack: false,
      game_dir: Dir.pwd,
    }
    @config = nil
    @input_dir = nil
    @output_dir = nil
    @file_patterns = []
    @exclude_patterns = []
  end

  # 运行应用
  def run
    begin
      parse_options
      load_configuration
      parse_config_patterns
      determine_game_directory
      determine_rgss_version
      validate_options
      load_rgss_module
      setup_directories # <--- 内部逻辑现在使用新的配置键
      process_files
      puts "处理完成。"
    rescue => e
      $stderr.puts "[致命错误] 执行失败: #{e.message}"
      $stderr.puts e.backtrace.join("\n")
      exit 1
    end
  end

  private

  # 解析命令行选项 (保持不变，使用 --unpack / --pack)
  def parse_options
    OptionParser.new do |opts|
      opts.banner = "用法: rvdata2json.rb [选项]"
      opts.separator ""
      opts.separator "选项:"
      opts.on("-c", "--config FILE", "指定配置文件路径") { |file| @options[:config] = file }
      opts.on("--rgss1", "强制使用 RGSS1") { @options[:rgss_version] = "RGSS1" }
      opts.on("--rgss2", "强制使用 RGSS2") { @options[:rgss_version] = "RGSS2" }
      opts.on("--rgss3", "强制使用 RGSS3") { @options[:rgss_version] = "RGSS3" }
      opts.on("--unpack", "解包: 将 RVData/RXData 文件转换为 JSON/脚本 (源) 文件") { @options[:unpack] = true }
      opts.on("--pack", "封包: 将 JSON/脚本 (源) 文件打包为 RVData/RXData 文件") { @options[:pack] = true }
      opts.on("-g", "--game-dir DIR", "指定游戏根目录") { |dir| @options[:game_dir] = dir }
      opts.on_tail("-h", "--help", "显示此帮助信息") { puts opts; exit }
    end.parse!(@argv)
  end

  # 加载配置 (保持不变)
  def load_configuration
    config_loader = Configuration.new(@options[:config])
    @config = config_loader.load # @config 现在包含新的键名
  end

  # 解析配置文件中的模式为正则表达式 (保持不变)
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
  end

  # 确定并验证游戏目录 (保持不变)
  def determine_game_directory
    @options[:game_dir] = File.expand_path(@options[:game_dir])
    unless Dir.exist?(@options[:game_dir])
      raise "指定的游戏目录不存在: #{@options[:game_dir]}"
    end
    puts "游戏目录设置为: #{@options[:game_dir]}"
  end

  # 确定 RGSS 版本 (保持不变)
  def determine_rgss_version
    return if @options[:rgss_version]
    begin
      detected_version = detect_rgss_version_from_game_ini
      if detected_version && RGSS_VERSIONS.include?(detected_version)
        @options[:rgss_version] = detected_version
        puts "从 Game.ini 自动检测到 RGSS 版本: #{@options[:rgss_version]}"
      else
        raise "无法从 Game.ini 推断有效的 RGSS 版本。"
      end
    rescue => e
      puts "警告: 自动检测 RGSS 版本失败: #{e.message}"
      fallback_version = @config["rgss_version"]
      unless RGSS_VERSIONS.include?(fallback_version)
        raise "配置中的 rgss_version '#{fallback_version}' 无效。支持: #{RGSS_VERSIONS.join(", ")}"
      end
      @options[:rgss_version] = fallback_version
      puts "回退到配置指定的 RGSS 版本: #{@options[:rgss_version]}"
    end
  end

  # 从 Game.ini 检测 RGSS 版本 (保持不变)
  def detect_rgss_version_from_game_ini
    game_ini_path = File.join(@options[:game_dir], "Game.ini")
    raise "未在游戏目录中找到 Game.ini" unless File.exist?(game_ini_path)
    encoding = detect_file_encoding(game_ini_path)
    puts "尝试使用检测到的编码 '#{encoding}' 加载 Game.ini"
    begin
      ini_file = IniFile.load(game_ini_path, encoding: encoding)
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError => e
      puts "警告: 使用编码 '#{encoding}' 加载 Game.ini 失败: #{e.message}。尝试使用 UTF-8..."
      begin
        ini_file = IniFile.load(game_ini_path, encoding: "UTF-8")
      rescue => e_utf8
        raise "加载或解析 Game.ini (尝试了 '#{encoding}' 和 UTF-8) 失败: 初始错误 (#{e.message}), UTF-8 尝试错误 (#{e_utf8.message})"
      end
    rescue ArgumentError => e
      if e.message.include?("invalid byte sequence") || e.message.include?("incompatible character encodings")
        raise "加载或解析 Game.ini 时编码 '#{encoding}' 不兼容或包含无效序列: #{e.message}"
      else
        raise
      end
    rescue => e
      raise "加载或解析 Game.ini 失败 (使用编码: #{encoding}): #{e.class} - #{e.message}"
    end
    rtp_key = ini_file["Game"]["RTP"] rescue nil
    rtp1_key = ini_file["Game"]["RTP1"] rescue nil
    if rtp_key
      rtp_value = rtp_key&.strip&.downcase
      puts "Game.ini RTP 值为: #{rtp_value.inspect}"
      case rtp_value
      when /rpgvxace/ then return "RGSS3"
      when /rpgvx/ then return "RGSS2"
      end
      puts "警告: 无法从 RTP 值 '#{rtp_value}' 推断 RGSS 版本，尝试检查 RTP1..."
    end
    if rtp1_key
      rtp1_value = rtp1_key&.strip&.downcase
      puts "Game.ini RTP1 值为: #{rtp1_value.inspect}"
      return "RGSS1" if rtp1_value == "standard"
      puts "警告: 无法从 RTP1 值 '#{rtp1_value}' 推断 RGSS 版本 (预期 'Standard')..."
    end
    raise "无法从 Game.ini 中的 RTP 或 RTP1 推断 RGSS 版本。"
  end

  # 检测文件编码 (保持不变)
  def detect_file_encoding(file_path)
    begin
      content_sample = File.binread(file_path, 4096) || ""
      detected_encoding_name = Utils.send(:detect_encoding_safe, content_sample)
      if detected_encoding_name
        puts "Utils.detect_encoding_safe 为 '#{File.basename(file_path)}' 返回编码: #{detected_encoding_name}"
        return detected_encoding_name
      else
        puts "[警告] 未能可靠检测 '#{File.basename(file_path)}' 的编码。假定为 UTF-8。"
        return "UTF-8"
      end
    rescue SystemCallError => e
      puts "[错误] 读取文件 '#{file_path}' 进行编码检测时出错: #{e.message}。假定为 UTF-8。"
      return "UTF-8"
    rescue => e
      puts "[警告] 检测文件编码 '#{file_path}' 时发生意外错误: #{e.class} - #{e.message}。假定为 UTF-8。"
      return "UTF-8"
    end
  end

  # 验证选项有效性 (保持不变，检查 :unpack / :pack)
  def validate_options
    unless @options[:unpack] ^ @options[:pack]
      raise "必须指定 --unpack 或 --pack 中的一个。"
    end
    unless RGSS_VERSIONS.include?(@options[:rgss_version])
      raise "无效的 RGSS 版本: '#{@options[:rgss_version]}'. 支持: #{RGSS_VERSIONS.join(", ")}"
    end
    puts "确认使用的 RGSS 版本: #{@options[:rgss_version]}"
  end

  # 加载对应的 RGSS 定义模块 (保持不变)
  def load_rgss_module
    begin
      rgss_lib_file = @options[:rgss_version].downcase
      require_relative rgss_lib_file
      puts "已加载 RGSS 定义: lib/#{rgss_lib_file}.rb"
    rescue LoadError => e
      raise "加载 RGSS 定义文件 'lib/#{rgss_lib_file}.rb' 失败: #{e.message}"
    end
  end

  # 设置输入输出目录路径 (***修改点***)
  def setup_directories
    # 根据转换方向选择正确的配置键 (已更新为 marshal / source)
    input_dir_key = @options[:unpack] ? "input_dir_marshal" : "input_dir_source"
    output_dir_key = @options[:unpack] ? "output_dir_source" : "output_dir_marshal"

    # --- 从 @config 中读取路径时使用新的键名 ---
    @input_dir = File.expand_path(@config[input_dir_key], @options[:game_dir])
    @output_dir = File.expand_path(@config[output_dir_key], @options[:game_dir])
    # --------------------------------------

    puts "输入目录: #{@input_dir}"
    puts "输出目录: #{@output_dir}"

    raise "输入目录不存在: #{@input_dir}" unless Dir.exist?(@input_dir)
  end

  # 处理文件转换流程 (保持不变，因为内部逻辑依赖 :unpack/:pack)
  def process_files
    scripts_processed = false
    if @options[:pack]
      scripts_input_dir = File.join(@input_dir, Converter::Scripts::SCRIPTS_SUBDIR)
      if Dir.exist?(scripts_input_dir)
        begin
          rvdata_extension = case @options[:rgss_version]
            when "RGSS1" then ".rxdata"
            when "RGSS2" then ".rvdata"
            when "RGSS3" then ".rvdata2"
            else raise "内部错误：未知的 RGSS 版本 #{@options[:rgss_version]} for scripts output"
            end
          scripts_output_file = File.join(@output_dir, SCRIPTS_BASENAME.capitalize + rvdata_extension)
          puts "检测到脚本输入目录，开始封包脚本: #{scripts_input_dir} -> #{File.basename(scripts_output_file)}"
          FileUtils.mkdir_p(File.dirname(scripts_output_file))
          packed_scripts_array = Converter::Scripts.pack(scripts_input_dir)
          if packed_scripts_array.nil?
            $stderr.puts "[警告] 脚本封包返回 nil，跳过写入 #{File.basename(scripts_output_file)}。"
          else
            Converter::IO.write_marshal_data(scripts_output_file, packed_scripts_array)
            puts "  输出: #{scripts_output_file}"
            scripts_processed = true
          end
        rescue => e
          $stderr.puts "[错误] 处理脚本封包失败 (目录: #{scripts_input_dir}):"
          $stderr.puts "  错误: #{e.class}: #{e.message}"
          e.backtrace.first(10).each { |line| $stderr.puts "    #{line}" }
          raise
        end
      else
        puts "未找到脚本输入目录 #{scripts_input_dir}，跳过脚本封包。"
      end
    end
    file_list, input_extension, output_extension = get_file_list(skip_scripts_dir: @options[:pack])
    if file_list.empty? && !scripts_processed
      puts "未找到需要处理的文件或脚本目录。"
      exit 0
    end
    exporter = Converter::JsonExporter.new(@options[:rgss_version]) if @options[:unpack]
    restorer = Converter::RvdataRestorer.new(@options[:rgss_version]) if @options[:pack]
    file_list.each do |input_file|
      relative_path = Pathname.new(input_file).relative_path_from(Pathname.new(@input_dir)).to_s
      basename_no_ext = relative_path.chomp(input_extension)
      output_file = File.join(@output_dir, basename_no_ext + output_extension) # 初始 output_file
      begin
        FileUtils.mkdir_p(File.dirname(output_file)) # 确保父目录存在
        if basename_no_ext.downcase == SCRIPTS_BASENAME && @options[:unpack]
          puts "解包 #{File.basename(input_file)} -> 脚本文件..."
          input_object = Converter::IO.load_marshal_data(input_file)
          if input_object.nil?
            $stderr.puts "[警告] 文件 '#{File.basename(input_file)}' 加载结果为 nil，跳过脚本解包。"
            next
          end
          Converter::Scripts.unpack(input_object, @output_dir)
          next
        end
        if @options[:unpack]
          puts "解包 #{File.basename(input_file)} -> JSON..."
          input_object = Converter::IO.load_marshal_data(input_file)
          if input_object.nil?
            $stderr.puts "[警告] 文件 '#{File.basename(input_file)}' 加载结果为 nil，跳过解包。"
            next
          end
          cleaned_data = exporter.export(input_object)
          json_output_file = File.join(@output_dir, basename_no_ext + ".json")
          Converter::IO.write_json_data(json_output_file, cleaned_data)
          puts "  输出: #{json_output_file}"
        else # pack
          puts "封包 #{File.basename(input_file)} -> RVData/RXData..."
          input_data = Converter::IO.load_json_data(input_file)
          if input_data.nil?
            $stderr.puts "[警告] JSON 文件 '#{File.basename(input_file)}' 加载结果为 nil，跳过封包。"
            next
          end
          restored_object = restorer.restore(input_data)
          if restored_object.nil?
            $stderr.puts "[警告] 从 JSON 文件 '#{File.basename(input_file)}' 恢复的对象为 nil，跳过写入 Marshal。"
            next
          end
          rvdata_output_file = File.join(@output_dir, basename_no_ext + output_extension)
          Converter::IO.write_marshal_data(rvdata_output_file, restored_object)
          puts "  输出: #{rvdata_output_file}"
        end
      rescue NameError => e
        $stderr.puts "[错误] 处理文件 '#{File.basename(input_file)}' 时出错 (可能是 RGSS 版本不匹配):"
        $stderr.puts "  错误: #{e.class}: #{e.message}."
        $stderr.puts "  提示: 请确保指定的 RGSS 版本 (--rgss1/2/3 或自动检测) 与数据文件匹配。"
        $stderr.puts "  当前使用的 RGSS 版本: #{@options[:rgss_version]}"
        raise
      rescue => e
        $stderr.puts "[错误] 处理文件 '#{File.basename(input_file)}' 失败:"
        $stderr.puts "  RGSS 版本: #{@options[:rgss_version]}"
        $stderr.puts "  错误: #{e.class}: #{e.message}"
        e.backtrace.first(10).each { |line| $stderr.puts "    #{line}" }
        raise
      end
    end
  end

  # 获取待处理文件列表 (保持不变，因为内部逻辑依赖 :unpack/:pack)
  def get_file_list(skip_scripts_dir: false)
    rvdata_extension = case @options[:rgss_version]
      when "RGSS1" then ".rxdata"
      when "RGSS2" then ".rvdata"
      when "RGSS3" then ".rvdata2"
      else raise "内部错误：未知的 RGSS 版本 #{@options[:rgss_version]}"
      end
    source_extension = ".json"
    input_extension = @options[:unpack] ? rvdata_extension : source_extension
    output_extension = @options[:unpack] ? source_extension : rvdata_extension
    puts "查找输入文件扩展名: #{input_extension}"
    scripts_dir_to_skip = File.join(@input_dir, Converter::Scripts::SCRIPTS_SUBDIR)
    all_files = []
    begin
      Find.find(@input_dir) do |path|
        if skip_scripts_dir && File.directory?(path) && path.downcase == scripts_dir_to_skip.downcase
          Find.prune
          next
        end
        all_files << path if File.file?(path) && File.extname(path).downcase == input_extension.downcase
      end
    rescue SystemCallError => e
      raise "访问输入目录 '#{@input_dir}' 时出错: #{e.message}"
    end
    filtered_files = all_files.select do |file_path|
      relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(@input_dir)).to_s
      basename = relative_path.chomp(File.extname(relative_path))
      included = @file_patterns.empty? || @file_patterns.any? { |regex| basename.match?(regex) }
      excluded = !@exclude_patterns.empty? && @exclude_patterns.any? { |regex| basename.match?(regex) }
      included && !excluded
    end
    filtered_files.uniq!
    filtered_files.sort!
    skip_info = skip_scripts_dir ? " (已排除 Scripts 目录)" : ""
    if filtered_files.empty?
      puts "在目录 '#{@input_dir}' 中未找到符合条件的文件 (扩展名: #{input_extension}#{skip_info})。"
    else
      puts "找到 #{filtered_files.length} 个待处理的普通文件#{skip_info}。"
    end
    return filtered_files, input_extension, output_extension
  end
end
