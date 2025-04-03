#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'optparse' # 用于解析命令行参数

# --- Define the Module and Error Class (Namespace) ---
module RgssadExtractor
  class RGSSADFileError < StandardError; end
end

# --- Require the Compiled C Extension ---
begin
  # 假设 C 扩展文件位于与此脚本同级的 rgssad_extractor 目录中
  require_relative 'rgssad_extractor/rgssad_extractor'
rescue LoadError => e
  warn <<~ERROR # 使用 warn 而不是 puts，错误信息输出到 stderr
    Error: Failed to load the C extension 'rgssad_extractor'.
    Ensure that the extension has been compiled correctly by running:
      cd rgssad_extractor
      ruby extconf.rb
      make # or nmake / mingw32-make
      cd ..
    Details: #{e.message}
  ERROR
  exit(1)
end

# --- Main Application Logic ---

options = {
  input: nil,
  output: 'extracted_output', # 默认输出目录
  verbose: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.separator ""
  opts.separator "Extracts files from RGSSAD v1/v3/Fux2Pack2 archives."
  opts.separator ""
  opts.separator "Options:"

  opts.on("-i", "--input FILE", "Path to the RGSSAD archive file (e.g., Game.rgss3a). (Required)") do |file|
    options[:input] = file
  end

  opts.on("-o", "--output DIR", "Directory to extract files into. (Default: #{options[:output]})") do |dir|
    options[:output] = dir
  end

  opts.on("-v", "--verbose", "Enable detailed output during extraction.") do
    options[:verbose] = true
  end

  opts.on_tail("-h", "--help", "Show this help message.") do
    puts opts
    exit
  end
end

begin
  parser.parse!(ARGV) # 解析命令行参数，会移除已解析的选项
rescue OptionParser::MissingArgument => e
  warn "Error: Missing argument for #{e.option_name}" # 使用 warn
  warn parser # 显示帮助信息
  exit(1)
rescue OptionParser::InvalidOption => e
  warn "Error: Invalid option: #{e.option_name}" # 使用 warn
  warn parser # 显示帮助信息
  exit(1)
end

# --- Validate Input ---
unless options[:input]
  warn "Error: Input file (--input) is required." # 使用 warn
  warn parser
  exit(1)
end

unless File.exist?(options[:input])
  warn "Error: Input file not found: #{options[:input]}" # 使用 warn
  exit(1)
end

unless File.file?(options[:input])
  warn "Error: Input path is not a file: #{options[:input]}" # 使用 warn
  exit(1)
end

# 检查输出路径是否是一个已存在的文件
if File.exist?(options[:output]) && !File.directory?(options[:output])
  warn "Error: Output path exists but is not a directory: #{options[:output]}" # 使用 warn
  exit(1)
end

# --- Prepare Output Directory ---
begin
  FileUtils.mkdir_p(options[:output])
rescue SystemCallError => e
  warn "Error: Could not create output directory '#{options[:output]}': #{e.message}" # 使用 warn
  exit(1)
end

# --- Execute Extraction ---
puts "Starting extraction..."
puts "  Input Archive: #{options[:input]}"
puts "  Output Directory: #{options[:output]}"
puts "  Verbose Output: #{options[:verbose] ? 'Enabled' : 'Disabled'}"
puts "-" * 20

start_time = Time.now

begin
  # 调用 C 扩展进行解密和提取
  RgssadExtractor.extract_archive(
    File.expand_path(options[:input]),  # 传递绝对路径以避免潜在问题
    File.expand_path(options[:output]), # 传递绝对路径
    options[:verbose]
  )

  end_time = Time.now
  duration = end_time - start_time

  puts "-" * 20
  puts "Extraction completed successfully in %.2f seconds." % duration

rescue RgssadExtractor::RGSSADFileError => e
  warn "\nExtraction Error: #{e.message}" # 使用 warn
  exit(1)
rescue SystemCallError => e
  # C 扩展内部可能触发的系统调用错误 (文件读写、内存分配等)
  warn "\nSystem Error during extraction: #{e.message}" # 使用 warn
  exit(1)
rescue => e
  warn "\nAn unexpected error occurred during extraction:" # 使用 warn
  warn "  Error Type: #{e.class}"
  warn "  Message: #{e.message}"
  warn "  Backtrace:"
  e.backtrace.first(5).each { |line| warn "    #{line}" } # 使用 warn 输出 backtrace
  exit(1)
end

exit(0) # 明确表示成功退出