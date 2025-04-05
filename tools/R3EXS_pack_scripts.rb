#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "zlib"
require "oj"
require "optparse"

# --- 开始: 从 R3EXS/error.rb 复制 ---
class ScriptsDirError < IOError
  attr_reader :scripts_dir

  def initialize(msg = "", scripts_dir)
    super(msg)
    @scripts_dir = scripts_dir
  end
end

class ScriptsInfoPathError < IOError
  attr_reader :scripts_info_path

  def initialize(msg = "", scripts_info_path)
    super(msg)
    @scripts_info_path = scripts_info_path
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

  # 将 object 序列化为 rvdata2 文件
  def self.object_rvdata2(object, output_file)
    File.write(output_file, Marshal.dump(object), mode: "wb")
  end
end

# --- 结束: 从 R3EXS/utils.rb 复制 (部分) ---

# --- 开始: 从 R3EXS/json_rvdata2.rb 复制并修改 ---
# 将 Ruby 源码读取压缩后序列化到输出文件
#
# @param scripts_dir [String] 包含 .rb 文件和 Scripts_info.json 的目录
# @param output_file [String] 输出的 Scripts.rvdata2 文件路径
# @param verbose [Boolean] 是否显示详细信息
#
# @raise [ScriptsDirError] Scripts 目录不存在
# @raise [ScriptsInfoPathError] Scripts_info.json 文件不存在
#
# @return [void]
def rb_scripts(scripts_dir, output_file, verbose)
  Dir.exist?(scripts_dir) or raise ScriptsDirError.new(scripts_dir), "Scripts directory not found: #{scripts_dir}"
  script_info_file_path = File.join(scripts_dir, "Scripts_info.json")
  File.exist?(script_info_file_path) or raise ScriptsInfoPathError.new(script_info_file_path), "Scripts_info.json not found: #{script_info_file_path}"

  print "#{ScriptUtils::ESCAPE}#{ScriptUtils::BLUE_COLOR}Reading info from #{ScriptUtils::RESET_COLOR}#{script_info_file_path}...\r" if verbose
  scripts_info_array = Oj.load_file(script_info_file_path)

  # 确定最终数组的大小，以填充 nil
  max_index = scripts_info_array.map { |info| info["index"] || info[:index] }.max || -1 # Oj 可能返回字符串键
  scripts_array = Array.new(max_index + 1)

  scripts_info_array.each do |script_info|
    index = script_info["index"] || script_info[:index] # 兼容符号或字符串键
    name = script_info["name"] || script_info[:name]
    script_file_path = File.join(scripts_dir, "#{format("%03d", index)}.rb")

    unless File.exist?(script_file_path)
      warn "#{ScriptUtils::YELLOW_COLOR}Warning: Script file not found for index #{index} (#{name}): #{script_file_path}. Skipping.#{ScriptUtils::RESET_COLOR}"
      # 保持 scripts_array[index] 为 nil
      next
    end

    print "#{ScriptUtils::ESCAPE}#{ScriptUtils::YELLOW_COLOR}Reading and Compressing #{ScriptUtils::RESET_COLOR}#{script_file_path}...\r" if verbose
    # 使用二进制读取模式 'rb' 以避免编码问题和 Windows 换行符问题
    script_content = File.read(script_file_path, mode: "rb")
    # R3EXS 用了一个固定的数字，这里保留它，虽然它的意义不明
    # 注意：确保脚本内容是 UTF-8 或与游戏引擎兼容的编码
    scripts_array[index] = [114514, name.encode("UTF-8"), Zlib::Deflate.deflate(script_content)]
  end

  print "#{ScriptUtils::ESCAPE}#{ScriptUtils::MAGENTA_COLOR}Serializing to #{ScriptUtils::RESET_COLOR}#{output_file}...\r" if verbose
  ScriptUtils.object_rvdata2(scripts_array, output_file)
  print "#{ScriptUtils::ESCAPE}#{ScriptUtils::GREEN_COLOR}Finished packing scripts to #{output_file}.#{ScriptUtils::RESET_COLOR}\n" if verbose
end

# --- 结束: 从 R3EXS/json_rvdata2.rb 复制并修改 ---

# --- 主程序 ---
options = { verbose: false }
OptionParser.new do |opts|
  opts.banner = "Usage: pack_scripts.rb [options] <input_scripts_directory> <output_scripts.rvdata2>"

  opts.on("-v", "--verbose", "Run verbosely") do |v|
    options[:verbose] = v
  end
  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end.parse!

input_dir = ARGV[0]
output_file = ARGV[1]

unless input_dir && output_file
  puts "Error: Input directory and output file are required."
  puts "Use -h for help."
  exit 1
end

begin
  rb_scripts(input_dir, output_file, options[:verbose])
rescue ScriptsDirError => e
  puts "#{ScriptUtils::RED_COLOR}Error: #{e.message} (#{e.scripts_dir})#{ScriptUtils::RESET_COLOR}"
  exit 1
rescue ScriptsInfoPathError => e
  puts "#{ScriptUtils::RED_COLOR}Error: #{e.message} (#{e.scripts_info_path})#{ScriptUtils::RESET_COLOR}"
  exit 1
rescue => e
  puts "#{ScriptUtils::RED_COLOR}An unexpected error occurred: #{e.message}#{ScriptUtils::RESET_COLOR}"
  puts e.backtrace if options[:verbose]
  exit 1
end
