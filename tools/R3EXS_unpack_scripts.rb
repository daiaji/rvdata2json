#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "zlib"
require "oj"
require "optparse"

# --- 开始: 从 R3EXS/error.rb 复制 ---
class Rvdata2FileError < StandardError
  attr_reader :rvdata2_path

  def initialize(msg = "", rvdata2_path)
    super(msg)
    @rvdata2_path = rvdata2_path
  end
end

# --- 结束: 从 R3EXS/error.rb 复制 ---

# --- 开始: 从 R3EXS/utils.rb 复制 (部分) ---
module ScriptUtils
  # 红色
  RED_COLOR = "\e[31m"
  # 绿色
  GREEN_COLOR = "\e[32m"
  # 黄色
  YELLOW_COLOR = "\e[33m"
  # 蓝色
  BLUE_COLOR = "\e[34m"
  # 紫色
  MAGENTA_COLOR = "\e[35m"
  # 青色
  CYAN_COLOR = "\e[36m"
  # 重置颜色
  RESET_COLOR = "\e[0m"
  # 清除行
  ESCAPE = "\e[2K"

  # 将 object 序列化为 json 文件
  def self.object_json(object, output_file)
    File.write(output_file, Oj.dump(object, indent: 2), mode: "w")
  end
end

# --- 结束: 从 R3EXS/utils.rb 复制 (部分) ---

# --- 开始: 从 R3EXS/rvdata2_json.rb 复制并修改 ---
# 将 Script 对象数组序列化为 Ruby 源码
# @param scripts [Array<Array>] 待转换的 Script 对象数组
# @param output_dir [String] 输出目录 (Scripts 文件夹将在此目录下创建)
# @param verbose [Boolean] 是否显示详细信息
# @return [void]
def scripts_rb(scripts, output_dir, verbose)
  FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)
  full_dir = File.join(output_dir, "Scripts")
  FileUtils.mkdir_p(full_dir) unless Dir.exist?(full_dir)

  scripts_info_array = []
  scripts.each_with_index do |script, index|
    next if script.nil? || script.empty? || script[1].nil? || script[2].nil?

    unless script.is_a?(Array) && script.size >= 3 && script[1].is_a?(String) && script[2].is_a?(String)
      warn "#{ScriptUtils::YELLOW_COLOR}Warning: Skipping invalid script entry at index #{index}. Content: #{script.inspect}#{ScriptUtils::RESET_COLOR}"
      next
    end

    # --- 处理脚本名称的编码 ---
    script_name_raw = script[1]
    script_name_utf8 = script_name_raw.dup
    unless script_name_utf8.force_encoding("UTF-8").valid_encoding?
      script_name_utf8 = script_name_raw.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      warn "#{ScriptUtils::YELLOW_COLOR}Warning: Script name at index #{index} contains non-UTF-8 bytes. Replaced invalid bytes for Scripts_info.json. Original bytes preserved in Marshal data. Name: '#{script_name_utf8}'#{ScriptUtils::RESET_COLOR}" if verbose && script_name_utf8 != script_name_raw
    end
    # --- 结束处理脚本名称 ---

    scripts_info_array << { index: index, name: script_name_utf8 }
    script_file_path = File.join(full_dir, "#{format("%03d", index)}.rb")
    print "#{ScriptUtils::ESCAPE}#{ScriptUtils::MAGENTA_COLOR}Writing #{ScriptUtils::RESET_COLOR}#{File.basename(script_file_path)}...\r" if verbose
    begin
      decompressed_script = Zlib::Inflate.inflate(script[2])

      unless decompressed_script.is_a?(String)
        raise Zlib::DataError, "Decompressed data at index #{index} is not a String."
      end

      File.write(script_file_path, decompressed_script, mode: "wb")
    rescue Zlib::Error => e
      warn "\n#{ScriptUtils::RED_COLOR}Error processing script at index #{index} ('#{script_name_utf8}'): #{e.message}. Skipping.#{ScriptUtils::RESET_COLOR}"
      next
    rescue TypeError => e
      warn "\n#{ScriptUtils::RED_COLOR}Error (TypeError) processing script data at index #{index} ('#{script_name_utf8}'): #{e.message}. Expected compressed string. Got: #{script[2].class}. Skipping.#{ScriptUtils::RESET_COLOR}"
      next
    end
  end

  script_info_file_path = File.join(full_dir, "Scripts_info.json")
  print "#{ScriptUtils::ESCAPE}#{ScriptUtils::MAGENTA_COLOR}Writing #{ScriptUtils::RESET_COLOR}#{File.basename(script_info_file_path)}...\r" if verbose
  begin
    ScriptUtils.object_json(scripts_info_array, script_info_file_path)
  rescue Encoding::UndefinedConversionError => e
    warn "\n#{ScriptUtils::RED_COLOR}Error: Failed to write Scripts_info.json due to encoding issues in script names: #{e.message}. Check script names in the original game data.#{ScriptUtils::RESET_COLOR}"
    File.write(script_info_file_path, "[]") # 写入空数组作为后备
  end
  print "#{ScriptUtils::ESCAPE}#{ScriptUtils::GREEN_COLOR}Finished unpacking scripts.#{ScriptUtils::RESET_COLOR}\n" if verbose
end

# --- 结束: 从 R3EXS/rvdata2_json.rb 复制并修改 ---

# --- 主程序 ---
options = { verbose: false }
OptionParser.new do |opts|
  opts.banner = "Usage: unpack_scripts.rb [options] <input_scripts.rvdata2> <output_directory>"

  opts.on("-v", "--verbose", "Run verbosely") do |v|
    options[:verbose] = v
  end
  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end.parse!

input_file = ARGV[0]
output_dir = ARGV[1]

unless input_file && output_dir
  puts "Error: Input file and output directory are required."
  puts "Use -h for help."
  exit 1
end

unless File.exist?(input_file)
  puts "Error: Input file not found: #{input_file}"
  exit 1
end

begin
  print "#{ScriptUtils::ESCAPE}#{ScriptUtils::BLUE_COLOR}Reading and Deserializing #{ScriptUtils::RESET_COLOR}#{input_file}...\r" if options[:verbose]

  # --- 已移除的部分 ---
  # 不再尝试加载 RGSS3 定义或发出警告
  # -------------------

  # 直接尝试加载 Marshal 数据
  scripts_object = File.open(input_file, "rb") { |file| Marshal.load(file) }

  unless scripts_object.is_a?(Array)
    raise Rvdata2FileError.new(input_file), "Invalid Scripts.rvdata2 file: Root object is not an Array."
  end

  scripts_rb(scripts_object, output_dir, options[:verbose])
rescue Rvdata2FileError => e
  puts "#{ScriptUtils::RED_COLOR}Error: #{e.message} (#{e.rvdata2_path})#{ScriptUtils::RESET_COLOR}"
  exit 1
rescue Zlib::Error => e
  puts "#{ScriptUtils::RED_COLOR}Error during decompression: #{e.message} - Check if #{input_file} is a valid Scripts.rvdata2 file.#{ScriptUtils::RESET_COLOR}"
  exit 1
  # 捕获 Marshal 加载时可能出现的类未定义错误
rescue ArgumentError => e
  if e.message.include?("undefined class/module")
    puts "#{ScriptUtils::RED_COLOR}Error: Failed to load Marshal data. #{e.message}."
    puts "#{ScriptUtils::YELLOW_COLOR}This usually means the Scripts.rvdata2 file contains complex RPG Maker objects, but their class definitions are not available in this Ruby environment.#{ScriptUtils::RESET_COLOR}"
  else
    # 其他类型的 ArgumentError
    puts "#{ScriptUtils::RED_COLOR}An ArgumentError occurred: #{e.message}#{ScriptUtils::RESET_COLOR}"
    puts e.backtrace if options[:verbose]
  end
  exit 1
  # 捕获其他可能的 Marshal 加载错误
rescue Marshal::LoadError => e
  puts "#{ScriptUtils::RED_COLOR}Error: Failed to load Marshal data from #{input_file}."
  puts "This might mean the file is corrupt, not a valid Marshal file, or contains classes unknown to this Ruby environment."
  puts "Error details: #{e.message}#{ScriptUtils::RESET_COLOR}"
  exit 1
rescue => e
  puts "#{ScriptUtils::RED_COLOR}An unexpected error occurred: #{e.message}#{ScriptUtils::RESET_COLOR}"
  puts e.backtrace if options[:verbose]
  exit 1
end
