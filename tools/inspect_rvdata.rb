#!/usr/bin/env ruby
# inspect_rvdata.rb - 通用 RVData 文件检查器 (完全动态类定义)

require "pp" # PrettyPrint for better output
require "set" # Need Set for defined_classes

# --- Lazy Class/Module Definition ---
# Define top-level RPG module if it doesn't exist, needed as a namespace container
module RPG; end unless defined?(RPG)

# Store dynamically defined classes globally
$dynamically_defined_classes = Set.new

# Helper function to dynamically define classes/modules recursively
def define_placeholder_entity(full_name)
  parts = full_name.split("::")
  current_scope = Object
  defined_path = []

  parts.each_with_index do |part, index|
    const_sym = part.to_sym
    is_last_part = (index == parts.size - 1)

    if current_scope.const_defined?(const_sym, false)
      begin
        entity = current_scope.const_get(const_sym)
        if entity.is_a?(Class) && entity.instance_variable_defined?(:@_placeholder_name) && entity.instance_variable_get(:@_placeholder_name) == full_name
          current_scope = entity
        elsif entity.is_a?(Module) # Includes Class
          current_scope = entity
        else
          raise TypeError, "Constant #{part} in #{defined_path.join("::")} exists but is not a Module/Class."
        end
      rescue NameError => e
        puts "[警告] 无法获取已定义的常量 #{part} 在 #{defined_path.join("::")}: #{e.message}. 可能存在 Autoload 问题。"
        puts "[动态定义] 尝试创建或覆盖 #{full_name} 作为占位符..."
        current_scope = create_placeholder(current_scope, const_sym, full_name, is_last_part)
      rescue TypeError => e
        puts "[错误] #{e.message}"
        puts "[动态定义] 尝试覆盖 #{full_name} 作为占位符..."
        current_scope = create_placeholder(current_scope, const_sym, full_name, is_last_part)
      end
      defined_path << part
      unless is_last_part || current_scope.is_a?(Module)
        raise TypeError, "#{defined_path.join("::")} is not a Module or Class, cannot define #{part} within it."
      end
    else
      current_scope = create_placeholder(current_scope, const_sym, (defined_path + [part]).join("::"), is_last_part)
      defined_path << part
    end
  end
end

# Helper to actually create the placeholder entity
def create_placeholder(parent_scope, const_sym, full_entity_path_str, is_class)
  new_entity = nil
  if is_class
    puts "[动态定义] 检测到缺失类并创建占位符: #{full_entity_path_str}"
    new_entity = Class.new do
      @_placeholder_name = full_entity_path_str

      def self._load(data)
        obj = allocate
        obj.instance_variable_set(:@_marshal_data, data)
        obj
      end

      def initialize(*args, &block)
        @_init_args = args if args.any?
        @_init_block = block if block
        if args.length == 1 && args[0].is_a?(Hash)
          args[0].each do |key, value|
            ivar_name = "@#{key}".to_sym
            instance_variable_set(ivar_name, value) unless key.to_s.start_with?("_")
          end
        end
      end

      def inspect
        klass_name = self.class.instance_variable_get(:@_placeholder_name) rescue self.class.name rescue "(Anonymous Placeholder)"
        ivars = instance_variables.map do |ivar|
          next if ivar == :@_init_args && (!defined?(@_init_args) || @_init_args.nil? || @_init_args.empty?)
          next if ivar == :@_init_block && (!defined?(@_init_block) || @_init_block.nil?)

          begin
            val = instance_variable_get(ivar)
            val_str = val.inspect rescue "[Inspect Error]"
            if val.is_a?(String)
              if !val.valid_encoding?
                val_str = "[Invalid Encoding String]"
              elsif ivar != :@_marshal_data && val.bytesize > 0 && (val.bytes.any? { |b| b < 32 && ![9, 10, 13].include?(b) } || val.bytes.include?(0))
                val_str = "[Binary-like String (len=#{val.bytesize})]"
              end
            end
            if ivar == :@_marshal_data
              val_str = "[Captured Marshal Data (size=#{val.bytesize})]"
            elsif ivar == :@_init_args
              val_str = "[Init Args: #{val.inspect}]"
            elsif ivar == :@_init_block
              val_str = "[Init Block Provided]"
            end
            "#{ivar}=#{val_str}"
          rescue => e
            "#{ivar}=[Error: #{e.message}]"
          end
        end.compact.join(", ")
        marshal_info = instance_variable_defined?(:@_marshal_data) ? " @_marshal_data=[Data size=#{instance_variable_get(:@_marshal_data).bytesize}]" : ""
        ivars_str = ivars.empty? ? "" : " #{ivars}"
        "<Placeholder #{klass_name}#{ivars_str}#{marshal_info}>"
      end

      def method_missing(method_name, *args, &block)
        ivar_name = "@#{method_name}".to_sym
        if args.empty? && block.nil? && instance_variable_defined?(ivar_name)
          return instance_variable_get(ivar_name)
        elsif method_name.to_s.end_with?("=") && args.length == 1 && block.nil?
          ivar_name_for_setter = "@#{method_name.to_s.chomp("=")}".to_sym
          return instance_variable_set(ivar_name_for_setter, args[0])
        end
        raise NoMethodError, "undefined method `#{method_name}' for #{self.inspect}"
      end

      def respond_to_missing?(method_name, include_private = false)
        ivar_name = "@#{method_name}".to_sym
        instance_variable_defined?(ivar_name) || super
      end
    end
  else
    puts "[动态定义] 检测到缺失模块并创建占位符: #{full_entity_path_str}"
    new_entity = Module.new
  end

  parent_scope.const_set(const_sym, new_entity)
  $dynamically_defined_classes.add(full_entity_path_str)
  return new_entity
end

# Function to list dynamically defined classes
def list_dynamically_defined_classes
  $dynamically_defined_classes.to_a.sort
end

# --- Main Program Logic ---
if ARGV.empty?
  puts "用法: ruby inspect_rvdata.rb <RVData文件路径>"
  puts "例如: ruby inspect_rvdata.rb Data/System.rvdata"
  exit 1
end

rvdata_file_path = ARGV[0]

unless File.exist?(rvdata_file_path)
  puts "错误: 文件未找到 - #{rvdata_file_path}"
  exit 1
end

puts "--- 开始加载 Marshal 文件: #{rvdata_file_path} ---"
puts "(将动态定义所有遇到的未知类/模块)"

loaded_data = nil
MAX_RETRIES = 50
retries = 0

loop do
  begin
    file_content = File.binread(rvdata_file_path)
    loaded_data = Marshal.load(file_content)

    puts "Marshal.load 完成。"
    puts "动态定义的类/模块: #{list_dynamically_defined_classes.join(", ")}"
    break
  rescue ArgumentError => e
    match_data = e.message.match(/undefined class\/module (\S+)/)
    if match_data && retries < MAX_RETRIES
      undefined_entity_name = match_data[1]
      if ["Object", "Module", "Class", "String", "Array", "Hash", "NilClass", "TrueClass", "FalseClass", "Numeric", "Integer", "Float", "Symbol"].include?(undefined_entity_name)
        puts "错误: Marshal 文件尝试引用基础 Ruby 类 '#{undefined_entity_name}' 但加载失败，文件可能已损坏。"
        exit 1
      end
      unless $dynamically_defined_classes.include?(undefined_entity_name)
        puts "检测到未定义: #{undefined_entity_name}。尝试动态定义..."
      end
      begin
        define_placeholder_entity(undefined_entity_name)
        retries += 1
      rescue => define_error
        puts "错误：动态定义 #{undefined_entity_name} 失败: #{define_error.class}: #{define_error.message}"
        puts define_error.backtrace.first(5).join("\n")
        puts "无法继续加载。"
        exit 1
      end
    else
      puts "错误：Marshal.load 失败。原因: #{e.message}"
      if match_data && retries >= MAX_RETRIES
        puts "已达到最大重试次数 (#{MAX_RETRIES})，仍然无法加载类 '#{match_data[1]}'"
      elsif e.message.include?("marshal data too short") || e.message.include?("invalid marshal format")
        puts "提示：文件可能已损坏或不是有效的 Marshal 文件。"
      elsif e.message.include?("incompatible marshal file format")
        puts "提示：文件的 Marshal 版本与当前 Ruby 版本不兼容 (需要 Ruby #{e.message.scan(/\d+\.\d+/).join(".")})。"
      end
      exit 1
    end
  rescue TypeError => e
    puts "错误：Marshal.load 失败 (类型错误): #{e.message}"
    if e.message.include?("needs to have method `_load'")
      missing_class_match = e.message.match(/class (\S+) needs to have method `_load'/)
      missing_class = missing_class_match ? missing_class_match[1] : "[未知类]"
      puts "提示: 类 '#{missing_class}' 可能使用了自定义 Marshal 格式，但其占位符类缺少必要的 `_load` 实现。"
    end
    exit 1
  rescue EncodingError => e
    puts "错误: Marshal.load 时遇到编码错误: #{e.message}"
    exit 1
  rescue => e
    puts "错误：读取或解析 Marshal 文件时发生未知错误: #{e.class}: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end
end

# --- 文件顶层对象检查 ---
puts "\n--- 文件顶层对象检查 ---"

if loaded_data.nil?
  puts "加载的数据为 nil。"
  puts "\n--- 检查结束 ---"
  exit 0
end

puts "加载的数据类型: #{loaded_data.class.name || "(匿名/占位符类)"}" # Placeholder classes might be anonymous
puts "对象内容 (使用标准 PrettyPrint 或 Inspect):"

begin
  PP.pp(loaded_data)
rescue => pp_error
  puts "[PrettyPrint 错误]: #{pp_error.class}: #{pp_error.message}"
  puts pp_error.backtrace.first(5).join("\n")
  puts "尝试使用基本 inspect:"
  begin
    inspect_str = loaded_data.inspect
    puts inspect_str[0, 5000] + (inspect_str.length > 5000 ? "... (truncated)" : "")
  rescue => inspect_error
    puts "[基本 inspect 也失败]: #{inspect_error.class}: #{inspect_error.message}"
  end
end

# --- 特定 RPG::System 属性检查 已移除 ---

puts "\n--- 检查结束 ---"
