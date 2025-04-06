#!/usr/bin/env ruby
# rvdata2json 主脚本
# 在 RVData (Marshal) 和 JSON 格式之间转换 RPG Maker VX/Ace 数据文件。

# 设置 Ruby 加载路径，确保能找到 lib 目录下的文件
# __dir__ 是当前脚本文件所在的目录
lib_path = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

# --- 新增: 将 C 扩展目录添加到加载路径 ---
# extconf.rb 指定了 "rgssad_extractor"，所以编译后的文件
# (rgssad_extractor.so 或 .bundle) 会在 ext/rgssad_extractor 目录下。
# 我们需要将 ext/rgssad_extractor 这个 *目录* 加入 $LOAD_PATH。
ext_dir_path = File.expand_path("ext", __dir__)
$LOAD_PATH.unshift(ext_dir_path) unless $LOAD_PATH.include?(ext_dir_path)
# ------------------------------------------

# 加载应用核心类
require "application" # Application.rb 现在可以通过 require 加载 C 扩展了

# 创建 Application 实例并运行
# ARGV 是命令行参数数组
Application.new(ARGV).run
