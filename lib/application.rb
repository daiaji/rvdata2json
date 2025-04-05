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
      to_json: false,
      to_rvdata: false,
      game_dir: Dir.pwd, # 默认为当前工作目录
    }
    @config = nil
    @input_dir = nil
    @output_dir = nil
    @file_patterns = [] # 存储加载的正则表达式
    @exclude_patterns = [] # 存储加载的正则表达式
  end

  # 运行应用
  def run
    begin
      parse_options
      load_configuration # 使用命令行传入的 config 路径（或默认）
      parse_config_patterns # 解析配置中的文件模式
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

  # 解析命令行选项 (保持不变)
  def parse_options
    OptionParser.new do |opts|
      opts.banner = "用法: rvdata2json.rb [选项]"
      opts.separator ""
      opts.separator "选项:"

      opts.on("-c", "--config FILE", "指定配置文件路径 (默认为项目根目录下的 config.yaml)") do |file|
        @options[:config] = file
      end
      opts.on("--rgss1", "强制使用 RGSS1 (RPG Maker XP)") { @options[:rgss_version] = "RGSS1" }
      opts.on("--rgss2", "强制使用 RGSS2 (RPG Maker VX)") { @options[:rgss_version] = "RGSS2" }
      opts.on("--rgss3", "强制使用 RGSS3 (RPG Maker VX Ace)") { @options[:rgss_version] = "RGSS3" }
      opts.on("--to-json", "将 RVData/RXData 文件转换为 JSON 或脚本文件") { @options[:to_json] = true }
      opts.on("--to-rvdata", "将 JSON 或脚本文件转换为 RVData/RXData") { @options[:to_rvdata] = true }
      opts.on("-g", "--game-dir DIR", "指定游戏根目录 (默认为当前工作目录)") do |dir|
        @options[:game_dir] = dir
      end
      opts.on_tail("-h", "--help", "显示此帮助信息") { puts opts; exit }
    end.parse!(@argv)
  end

  # 加载配置 (保持不变)
  def load_configuration
    config_loader = Configuration.new(@options[:config])
    @config = config_loader.load
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

  # 确定 RGSS 版本 (命令行优先 > 自动检测 > 配置 > 默认) (保持不变)
  def determine_rgss_version
    return if @options[:rgss_version] # 如果命令行已指定，则跳过

    begin
      detected_version = detect_rgss_version_from_game_ini
      if detected_version && RGSS_VERSIONS.include?(detected_version)
        @options[:rgss_version] = detected_version
        puts "从 Game.ini 自动检测到 RGSS 版本: #{@options[:rgss_version]}"
      else
        raise "无法从 Game.ini 推断有效的 RGSS 版本。" # 触发下面的 rescue
      end
    rescue => e
      puts "警告: 自动检测 RGSS 版本失败: #{e.message}"
      # 从配置中获取版本 (Configuration 类在加载时已处理默认值)
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

    # 调用修改后的 detect_file_encoding 获取编码名称字符串
    encoding = detect_file_encoding(game_ini_path) # 返回 String 或 "UTF-8" (回退)
    puts "尝试使用检测到的编码 '#{encoding}' 加载 Game.ini"

    begin
      # 使用获取到的编码名称加载 IniFile
      ini_file = IniFile.load(game_ini_path, encoding: encoding)
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError => e
      # 如果使用检测到的编码失败，尝试 UTF-8 作为备选
      puts "警告: 使用编码 '#{encoding}' 加载 Game.ini 失败: #{e.message}。尝试使用 UTF-8..."
      begin
        ini_file = IniFile.load(game_ini_path, encoding: "UTF-8")
      rescue => e_utf8
        # 如果 UTF-8 也失败，则抛出原始错误（或组合错误）
        raise "加载或解析 Game.ini (尝试了 '#{encoding}' 和 UTF-8) 失败: 初始错误 (#{e.message}), UTF-8 尝试错误 (#{e_utf8.message})"
      end
    rescue ArgumentError => e
      # 捕获 IniFile 可能抛出的与编码相关的 ArgumentError
      if e.message.include?("invalid byte sequence") || e.message.include?("incompatible character encodings")
        raise "加载或解析 Game.ini 时编码 '#{encoding}' 不兼容或包含无效序列: #{e.message}"
      else
        raise # 重新抛出其他 ArgumentError
      end
    rescue => e
      # 捕获其他加载错误
      raise "加载或解析 Game.ini 失败 (使用编码: #{encoding}): #{e.class} - #{e.message}"
    end

    # --- 版本推断逻辑 (保持不变) ---
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

    # 如果所有检查都失败
    raise "无法从 Game.ini 中的 Library, RTP 或 RTP1 推断 RGSS 版本。"
  end

  # 检测文件编码 (保持不变)
  def detect_file_encoding(file_path)
    begin
      # 读取文件开头的样本（二进制模式）
      content_sample = File.binread(file_path, 4096) || ""
      # 调用修改后的 Utils.detect_encoding_safe，它返回 String 或 nil
      detected_encoding_name = Utils.send(:detect_encoding_safe, content_sample)

      if detected_encoding_name
        puts "Utils.detect_encoding_safe 为 '#{File.basename(file_path)}' 返回编码: #{detected_encoding_name}"
        # 直接返回检测到的编码名称
        return detected_encoding_name
      else
        # 如果 detect_encoding_safe 返回 nil (检测失败)
        puts "[警告] 未能可靠检测 '#{File.basename(file_path)}' 的编码。假定为 UTF-8。"
        return "UTF-8" # 使用 UTF-8 作为最终的回退
      end
    rescue SystemCallError => e # 例如文件不存在或无权限
      puts "[错误] 读取文件 '#{file_path}' 进行编码检测时出错: #{e.message}。假定为 UTF-8。"
      return "UTF-8"
    rescue => e
      puts "[警告] 检测文件编码 '#{file_path}' 时发生意外错误: #{e.class} - #{e.message}。假定为 UTF-8。"
      # puts e.backtrace.first(5).join("\n") # Debug 时可以取消注释
      return "UTF-8"
    end
  end

  # 验证选项有效性 (保持不变)
  def validate_options
    unless @options[:to_json] ^ @options[:to_rvdata]
      raise "必须指定 --to-json 或 --to-rvdata 中的一个。"
    end
    unless RGSS_VERSIONS.include?(@options[:rgss_version])
      raise "无效的 RGSS 版本: '#{@options[:rgss_version]}'. 支持: #{RGSS_VERSIONS.join(", ")}"
    end
    puts "确认使用的 RGSS 版本: #{@options[:rgss_version]}"
  end

  # 加载对应的 RGSS 定义模块 (保持不变)
  def load_rgss_module
    begin
      rgss_lib_file = "lib/#{@options[:rgss_version].downcase}.rb"
      # 使用 require_relative 和小写版本号
      require_relative @options[:rgss_version].downcase
      puts "已加载 RGSS 定义: #{rgss_lib_file}"
    rescue LoadError => e
      raise "加载 RGSS 定义文件 '#{rgss_lib_file}' 失败: #{e.message}"
    end
  end

  # 设置输入输出目录路径 (保持不变)
  def setup_directories
    input_dir_key = @options[:to_json] ? "input_dir_rvdata" : "input_dir_json"
    output_dir_key = @options[:to_json] ? "output_dir_json" : "output_dir_rvdata"

    @input_dir = File.expand_path(@config[input_dir_key], @options[:game_dir])
    @output_dir = File.expand_path(@config[output_dir_key], @options[:game_dir])

    puts "输入目录: #{@input_dir}"
    puts "输出目录: #{@output_dir}"

    raise "输入目录不存在: #{@input_dir}" unless Dir.exist?(@input_dir)
    # 输出目录会自动创建，无需检查存在性
  end

  # --- 修改: 处理文件转换流程 ---
  def process_files
    scripts_processed = false # 标记脚本目录是否已处理 (用于封包)

    # --- 处理脚本封包 (如果 --to-rvdata 且输入目录存在) ---
    if @options[:to_rvdata]
      scripts_input_dir = File.join(@input_dir, Converter::Scripts::SCRIPTS_SUBDIR)
      if Dir.exist?(scripts_input_dir)
        begin
          # 确定输出扩展名
          rvdata_extension = case @options[:rgss_version]
            when "RGSS1" then ".rxdata"
            when "RGSS2" then ".rvdata"
            when "RGSS3" then ".rvdata2"
            else raise "内部错误：未知的 RGSS 版本 #{@options[:rgss_version]} for scripts output"
            end
          scripts_output_file = File.join(@output_dir, SCRIPTS_BASENAME.capitalize + rvdata_extension) # e.g. Data/Scripts.rvdata2

          puts "检测到脚本输入目录，开始封包: #{scripts_input_dir} -> #{File.basename(scripts_output_file)}"
          FileUtils.mkdir_p(File.dirname(scripts_output_file))

          restored_scripts_array = Converter::Scripts.pack(scripts_input_dir)

          if restored_scripts_array.nil?
            $stderr.puts "[警告] 脚本封包返回 nil，跳过写入 #{File.basename(scripts_output_file)}。"
          else
            Converter::IO.write_marshal_data(scripts_output_file, restored_scripts_array)
            puts "  输出: #{scripts_output_file}"
            scripts_processed = true # 标记 Scripts 已处理
          end
        rescue => e
          $stderr.puts "[错误] 处理脚本封包失败 (目录: #{scripts_input_dir}):"
          $stderr.puts "  错误: #{e.class}: #{e.message}"
          e.backtrace.first(10).each { |line| $stderr.puts "    #{line}" }
          raise # 继续抛出原始错误
        end
      else
        puts "未找到脚本输入目录 #{scripts_input_dir}，跳过脚本封包。"
      end
    end

    # --- 获取普通文件列表 (会跳过 Scripts 目录) ---
    file_list, input_extension, output_extension = get_file_list(skip_scripts_dir: @options[:to_rvdata])

    # 如果没有普通文件且脚本也没处理，则退出
    if file_list.empty? && !scripts_processed
      puts "未找到需要处理的文件或脚本目录。"
      exit 0
    end

    exporter = Converter::JsonExporter.new(@options[:rgss_version]) if @options[:to_json]
    restorer = Converter::RvdataRestorer.new(@options[:rgss_version]) if @options[:to_rvdata]

    # --- 处理文件列表 (现在只包含普通文件) ---
    file_list.each do |input_file|
      relative_path = Pathname.new(input_file).relative_path_from(Pathname.new(@input_dir)).to_s
      basename_no_ext = relative_path.chomp(input_extension)
      output_file = File.join(@output_dir, basename_no_ext + output_extension)

      begin
        # 确保输出目录存在
        FileUtils.mkdir_p(File.dirname(output_file))

        # --- 特殊处理 Scripts 文件解包 ---
        if basename_no_ext.downcase == SCRIPTS_BASENAME && @options[:to_json]
          puts "转换 #{File.basename(input_file)} -> 脚本文件..."
          input_object = Converter::IO.load_marshal_data(input_file)
          if input_object.nil?
            $stderr.puts "[警告] 文件 '#{File.basename(input_file)}' 加载结果为 nil，跳过脚本解包。"
            next
          end
          # 调用脚本解包器，输出目录是 JSON 的根目录
          Converter::Scripts.unpack(input_object, @output_dir)
          # Scripts 文件不生成单独的 .json 文件，所以这里就结束了
          next # 处理下一个文件
        end

        # --- 普通文件处理逻辑 ---
        if @options[:to_json]
          # 这个分支现在不会处理 Scripts 文件了
          puts "转换 #{File.basename(input_file)} -> JSON..."
          input_object = Converter::IO.load_marshal_data(input_file)
          if input_object.nil?
            $stderr.puts "[警告] 文件 '#{File.basename(input_file)}' 加载结果为 nil，跳过导出。"
            next
          end
          cleaned_data = exporter.export(input_object)
          Converter::IO.write_json_data(output_file, cleaned_data)
          puts "  输出: #{output_file}"
        else # to_rvdata (普通 JSON 文件)
          puts "转换 #{File.basename(input_file)} -> RVData/RXData..."
          input_data = Converter::IO.load_json_data(input_file)
          if input_data.nil?
            $stderr.puts "[警告] JSON 文件 '#{File.basename(input_file)}' 加载结果为 nil，跳过恢复。"
            next
          end
          restored_object = restorer.restore(input_data)
          if restored_object.nil?
            $stderr.puts "[警告] 从 JSON 文件 '#{File.basename(input_file)}' 恢复的对象为 nil，跳过写入 Marshal。"
            next
          end
          Converter::IO.write_marshal_data(output_file, restored_object)
          puts "  输出: #{output_file}"
        end
      rescue NameError => e # Marshal 加载时类未定义的错误
        $stderr.puts "[错误] 处理文件 '#{File.basename(input_file)}' 时出错 (可能是 RGSS 版本不匹配):"
        $stderr.puts "  错误: #{e.class}: #{e.message}."
        $stderr.puts "  提示: 请确保指定的 RGSS 版本 (--rgss1/2/3 或自动检测) 与数据文件匹配。"
        $stderr.puts "  当前使用的 RGSS 版本: #{@options[:rgss_version]}"
        raise # 重新抛出以便主程序捕获
      rescue => e
        $stderr.puts "[错误] 处理文件 '#{File.basename(input_file)}' 失败:"
        $stderr.puts "  RGSS 版本: #{@options[:rgss_version]}"
        $stderr.puts "  错误: #{e.class}: #{e.message}"
        e.backtrace.first(10).each { |line| $stderr.puts "    #{line}" }
        raise # 继续抛出原始错误
      end
    end
  end

  # --- 修改结束 ---

  # --- 修改: 获取待处理文件列表 ---
  # 添加 skip_scripts_dir 参数
  def get_file_list(skip_scripts_dir: false)
    rvdata_extension = case @options[:rgss_version]
      when "RGSS1" then ".rxdata"
      when "RGSS2" then ".rvdata"
      when "RGSS3" then ".rvdata2"
      else raise "内部错误：未知的 RGSS 版本 #{@options[:rgss_version]}"
      end
    json_extension = ".json"

    input_extension = @options[:to_json] ? rvdata_extension : json_extension
    output_extension = @options[:to_json] ? json_extension : rvdata_extension

    puts "查找输入文件扩展名: #{input_extension}"
    scripts_dir_to_skip = File.join(@input_dir, Converter::Scripts::SCRIPTS_SUBDIR)

    all_files = []
    begin
      Find.find(@input_dir) do |path|
        # --- 新增: 跳过 Scripts 目录 ---
        if skip_scripts_dir && File.directory?(path) && path == scripts_dir_to_skip
          Find.prune # 跳过此目录及其内容
          next
        end
        # ------------------------------

        # 只添加匹配扩展名的文件 (并且不是目录)
        all_files << path if File.file?(path) && File.extname(path).downcase == input_extension.downcase
      end
    rescue SystemCallError => e
      raise "访问输入目录 '#{@input_dir}' 时出错: #{e.message}"
    end

    # 文件过滤逻辑 (使用预先编译好的正则表达式)
    filtered_files = all_files.select do |file_path|
      relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(@input_dir)).to_s
      basename = relative_path.chomp(File.extname(relative_path))

      # 使用 @file_patterns 和 @exclude_patterns (它们已经是 Regexp 对象)
      included = @file_patterns.empty? || @file_patterns.any? { |regex| basename.match?(regex) }
      excluded = !@exclude_patterns.empty? && @exclude_patterns.any? { |regex| basename.match?(regex) }

      included && !excluded
    end

    filtered_files.uniq!
    filtered_files.sort!

    # 仅在没有找到 *普通* 文件时报告 (脚本目录单独处理)
    if filtered_files.empty?
      puts "在目录 '#{@input_dir}' 中未找到符合条件的文件 (扩展名: #{input_extension}，已排除 Scripts 目录)。"
    else
      puts "找到 #{filtered_files.length} 个待处理的普通文件。"
    end

    return filtered_files, input_extension, output_extension
  end

  # --- 修改结束 ---
end
