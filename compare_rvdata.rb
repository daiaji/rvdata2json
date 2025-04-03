#!/usr/bin/env ruby
# compare_rvdata_folders.rb - 对比两个文件夹下匹配的 RVData 文件的数据差异 (完全动态类定义, 带日志聚合)

require "pp" # PrettyPrint for better output
require "set" # Need Set for defined_classes and file list processing
require "logger" # Required for logging to file
require "fileutils" # Required for creating log directory
require "pathname" # For path manipulation

# --- Configuration ---
MAX_RETRIES = 100 # Increased retry limit for complex files
LOG_DIR = "logs" # Directory to store log files
LOG_FILENAME = "rvdata_comparison_#{Time.now.strftime("%Y%m%d_%H%M%S")}.log" # Log filename with timestamp
MAX_DIFF_EXAMPLES = 3 # Maximum number of specific examples to show for a summarized difference
DIFF_SUMMARY_THRESHOLD = 5 # If more than this many items have the *exact* same difference pattern, summarize them.

# List of file basenames or patterns to compare. '.rvdata' will be added automatically.
# Use Strings for exact names and Regexp for patterns.
FILES_TO_COMPARE = [
  "Actors",
  "Animations",
  "Armors",
  "Classes",
  "CommonEvents",
  "Enemies",
  "Items",
  "MapInfos",
  "Skills",
  "States",
  "System",
  "Tilesets", # Will be skipped if not found, safe to include
  "Troops",
  "Weapons",
  /Map\d{3}/,   # Matches Map001, Map002, etc.
].freeze # Freeze to prevent accidental modification

# --- Global Variables ---
# Store dynamically defined classes globally (shared between all loads)
$dynamically_defined_classes = Set.new
# Flag to track if any differences were found across *all* comparisons
$global_comparison_found_differences = false
# Logger instance (initialized later)
$logger = nil
$log_file_handle = nil

# --- Logger Setup ---
def setup_logger
  begin
    log_dir_path = Pathname.new(LOG_DIR)
    log_dir_path.mkpath unless log_dir_path.directory?
    log_path = log_dir_path.join(LOG_FILENAME)
    $log_file_handle = File.open(log_path, "w") # 'w' to overwrite for each run
    # Configure logger to write to the file AND console (STDERR for progress/errors)
    # $logger = Logger.new(MultiIO.new(STDERR, $log_file_handle)) # If you want progress on console too
    $logger = Logger.new($log_file_handle) # Log only to file by default for comparison details
    $logger.level = Logger::INFO
    $logger.formatter = proc do |severity, datetime, progname, msg|
      # Simple format for log file
      "#{msg}\n"
    end
    # Inform user via STDOUT where the log is
    puts "日志文件已创建: #{log_path.expand_path}"
    $logger.info("--- RVData 对比脚本开始 ---")
    $logger.info("日志时间: #{Time.now}")
  rescue => e
    STDERR.puts "[致命错误] 无法设置或写入日志文件 '#{log_path || LOG_FILENAME}': #{e.message}"
    STDERR.puts e.backtrace.first(5).join("\n")
    exit(1) # Exit if logging cannot be set up
  end
end

# Ensure log file is closed on exit
at_exit do
  if $log_file_handle && !$log_file_handle.closed?
    $logger&.info("--- RVData 对比脚本结束 ---")
    $log_file_handle.close
    # Don't print "Log file closed" to STDOUT, keep console clean for summary
  end
end

# --- Helper to check if an object is one of our placeholders ---
def is_placeholder?(obj)
  (obj.instance_variable_defined?(:@_placeholder_klass_name) && !obj.instance_variable_get(:@_placeholder_klass_name).nil?) ||
  (obj.class.respond_to?(:instance_variable_defined?) && obj.class.instance_variable_defined?(:@_placeholder_name)) rescue false
end

# --- Helper function to dynamically define classes/modules recursively ---
# (define_placeholder_entity and create_placeholder remain largely the same,
#  just ensure logging uses $logger.info/warn/error)
def define_placeholder_entity(full_name)
  # ... (Code is identical to previous version, using $logger) ...
  parts = full_name.split("::")
  current_scope = Object
  defined_path = []

  parts.each_with_index do |part, index|
    const_sym = part.to_sym
    is_last_part = (index == parts.size - 1)
    full_entity_path_str = (defined_path + [part]).join("::") # Correct full path at this step

    begin
      # Check if constant exists in the current scope *without* triggering autoload
      if current_scope.const_defined?(const_sym, false)
        entity = current_scope.const_get(const_sym)
        is_our_placeholder = entity.is_a?(Class) && entity.instance_variable_defined?(:@_placeholder_name) && entity.instance_variable_get(:@_placeholder_name) == full_entity_path_str
        is_valid_container = entity.is_a?(Module) # Includes Class

        if is_our_placeholder || is_valid_container
          current_scope = entity
          defined_path << part # Add to path *after* successfully getting it
        else
          # It exists but isn't what we expect (not Module/Class or not our placeholder)
          $logger.warn("常量 #{part} 在 #{defined_path.join("::")} 中已存在，但不是预期的模块/类类型 (#{entity.class})。尝试覆盖...")
          current_scope = create_placeholder(current_scope, const_sym, full_entity_path_str, is_last_part)
          defined_path << part
        end
      else
        # Constant does not exist, create placeholder
        current_scope = create_placeholder(current_scope, const_sym, full_entity_path_str, is_last_part)
        defined_path << part
      end
      # Ensure the current scope is suitable for nesting the next part
      unless is_last_part || current_scope.is_a?(Module)
        raise TypeError, "#{defined_path.join("::")} is not a Module or Class, cannot define #{parts[index + 1]} within it."
      end
    rescue NameError => e
      # This might happen with complex autoload scenarios or edge cases
      $logger.warn("获取常量 #{part} 在 #{defined_path.join("::")} 时遇到 NameError: #{e.message}. 可能存在 Autoload 问题或命名冲突。")
      $logger.info("动态定义: 尝试创建或覆盖 #{full_entity_path_str} 作为占位符...")
      begin
        current_scope = create_placeholder(current_scope, const_sym, full_entity_path_str, is_last_part)
        defined_path << part
      rescue => inner_e
        $logger.error("尝试为 #{full_entity_path_str} 创建占位符失败: #{inner_e.message}. 无法继续定义此路径。")
        raise # Re-raise the error to stop the definition chain for this name
      end
    rescue TypeError => e
      $logger.error("在 #{defined_path.join("::")} 中定义 #{part} 时发生类型错误: #{e.message}")
      $logger.info("动态定义: 尝试覆盖 #{full_entity_path_str} 作为占位符...")
      begin
        current_scope = create_placeholder(current_scope, const_sym, full_entity_path_str, is_last_part)
        defined_path << part
      rescue => inner_e
        $logger.error("尝试为 #{full_entity_path_str} 覆盖占位符失败: #{inner_e.message}.")
        raise
      end
    rescue => e # Catch other potential errors during const_get/const_defined
      $logger.error("处理 #{full_entity_path_str} 时发生意外错误: #{e.class}: #{e.message}")
      $logger.error(e.backtrace.first(5).join("\n"))
      raise # Stop processing this specific undefined class
    end
  end
end

def create_placeholder(parent_scope, const_sym, full_entity_path_str, is_class)
  # ... (Code is identical to previous version, using $logger) ...
  new_entity = nil
  if is_class
    # Only log definition message if it's truly new globally
    unless $dynamically_defined_classes.include?(full_entity_path_str)
      $logger.info("动态定义: 检测到缺失类并创建占位符: #{full_entity_path_str}")
    end
    # Check if it's already defined, potentially by another thread or recursive load
    if parent_scope.const_defined?(const_sym, false)
      existing = parent_scope.const_get(const_sym)
      # If existing is already our placeholder for the same name, reuse it
      if existing.is_a?(Class) && existing.instance_variable_defined?(:@_placeholder_name) && existing.instance_variable_get(:@_placeholder_name) == full_entity_path_str
        return existing
      end
      # If it exists but isn't our placeholder, we might overwrite (warning logged before calling this function)
    end

    new_entity = Class.new do
      @_placeholder_name = full_entity_path_str # Store the intended name

      def self.name
        @_placeholder_name || super || "(Anonymous Placeholder Class)"
      end
      def self.to_s
        name
      end

      # Needed for Marshal to load data into the placeholder
      def self._load(data)
        obj = allocate
        # We don't store raw data, we expect Marshal to populate ivars.
        obj
      end

      # Capture initialize args if Marshal uses it (less likely for standard RVData)
      def initialize(*args, &block)
        @_init_args = args if args.any?
        @_init_block = block if block
        # Attempt to mimic basic attribute setting if args look like a hash
        if args.length == 1 && args[0].is_a?(Hash)
          args[0].each do |key, value|
            ivar_name = "@#{key}".to_sym
            instance_variable_set(ivar_name, value) unless key.to_s.start_with?("_")
          end
        end
        # Store placeholder name on instance too, for inspect
        @_placeholder_klass_name = self.class.instance_variable_get(:@_placeholder_name) rescue self.class.name
      end

      def inspect
        klass_name = @_placeholder_klass_name || self.class.name rescue "(Unknown Placeholder)"
        ivars = instance_variables.map do |ivar|
          next if ivar.to_s.start_with?("@_") # Hide internal vars

          begin
            val = instance_variable_get(ivar)
            val_str = val.inspect rescue "[Inspect Error]"
            # Simple truncation for binary-like strings in inspect
            if val.is_a?(String) && val.bytesize > 50 && (!val.valid_encoding? || val.bytes.any? { |b| b < 32 && ![9, 10, 13].include?(b) } || val.bytes.include?(0))
              val_str = "[Binary-like String (len=#{val.bytesize})]"
            elsif val_str.length > 100
              val_str = val_str[0, 100] + "..."
            end
            "#{ivar}=#{val_str}"
          rescue => e
            "#{ivar}=[Error: #{e.message}]"
          end
        end.compact.join(", ")
        ivars_str = ivars.empty? ? "" : " #{ivars}"
        "<Placeholder #{klass_name}#{ivars_str}>"
      end

      # Allow reading attributes set by Marshal
      def method_missing(method_name, *args, &block)
        ivar_name = "@#{method_name}".to_sym
        # Check for reader method (no args)
        if args.empty? && block.nil? && instance_variable_defined?(ivar_name)
          return instance_variable_get(ivar_name)
        end
        # Raise error clearly stating it's a placeholder
        klass_name = @_placeholder_klass_name || self.class.name
        raise NoMethodError, "undefined method `#{method_name}' for #{self.inspect} (Placeholder for #{klass_name})"
      end

      def respond_to_missing?(method_name, include_private = false)
        ivar_name = "@#{method_name}".to_sym
        # Respond true only for potential readers matching existing ivars
        if !method_name.to_s.end_with?("=") && instance_variable_defined?(ivar_name)
          true
        else
          super
        end
      end
    end
  else
    # Only log definition message if it's truly new globally
    unless $dynamically_defined_classes.include?(full_entity_path_str)
      $logger.info("动态定义: 检测到缺失模块并创建占位符: #{full_entity_path_str}")
    end
    # Check if it's already defined
    if parent_scope.const_defined?(const_sym, false)
      existing = parent_scope.const_get(const_sym)
      # If existing is already a Module, reuse it (can't store name easily)
      return existing if existing.is_a?(Module)
      # If it exists but isn't a Module, we might overwrite
    end
    new_entity = Module.new
  end

  # Use const_set carefully, avoid warnings if already set to the same thing
  parent_scope.const_set(const_sym, new_entity)

  $dynamically_defined_classes.add(full_entity_path_str) # Add to the shared set
  return new_entity
end

# --- Function to load a single RVData file ---
# (load_rvdata_file remains largely the same, using $logger)
def load_rvdata_file(filepath)
  # ... (Code is identical to previous version, using $logger) ...
  $logger.info("--- 开始加载 Marshal 文件: #{filepath} ---")
  loaded_data = nil
  retries = 0

  loop do
    begin
      file_content = File.binread(filepath)
      loaded_data = Marshal.load(file_content)
      $logger.info("Marshal.load 完成: #{filepath}")
      break # Success
    rescue ArgumentError => e
      match_data = e.message.match(/undefined class\/module (\S+)/)
      if match_data && retries < MAX_RETRIES
        undefined_entity_name = match_data[1]
        # Avoid infinite loops for core classes - indicates corruption
        if ["Object", "Module", "Class", "String", "Array", "Hash", "NilClass", "TrueClass", "FalseClass", "Numeric", "Integer", "Float", "Symbol", "Encoding"].include?(undefined_entity_name) || undefined_entity_name.start_with?("Marshal::")
          $logger.error("Marshal 文件尝试引用基础 Ruby/Marshal 类 '#{undefined_entity_name}' 但加载失败。文件 #{filepath} 可能已损坏或不兼容。")
          return nil # Indicate failure
        end

        $logger.warn("尝试定义: 遇到未定义实体: #{undefined_entity_name} (尝试次数 #{retries + 1}/#{MAX_RETRIES})")
        begin
          define_placeholder_entity(undefined_entity_name)
          retries += 1
        rescue => define_error
          $logger.error("动态定义 #{undefined_entity_name} 失败: #{define_error.class}: #{define_error.message}")
          $logger.error(define_error.backtrace.first(5).join("\n"))
          $logger.error("无法继续加载 #{filepath}.")
          return nil # Indicate failure
        end
      else
        $logger.error("Marshal.load 失败 (#{filepath})。原因: #{e.message}")
        if match_data && retries >= MAX_RETRIES
          $logger.error("已达到最大重试次数 (#{MAX_RETRIES})，仍然无法加载类 '#{match_data[1]}'")
        elsif e.message.include?("marshal data too short") || e.message.include?("invalid marshal format")
          $logger.error("提示：文件 #{filepath} 可能已损坏或不是有效的 Marshal 文件。")
        elsif e.message.include?("incompatible marshal file format")
          $logger.error("提示：文件 #{filepath} 的 Marshal 版本与当前 Ruby 版本不兼容 (需要 Ruby #{e.message.scan(/\d+\.\d+/).join(".")})。")
        end
        return nil # Indicate failure
      end
    rescue TypeError => e
      $logger.error("Marshal.load 失败 (类型错误) (#{filepath}): #{e.message}")
      if e.message.include?("needs to have method `_load'")
        missing_class_match = e.message.match(/class (\S+) needs to have method `_load'/)
        missing_class = missing_class_match ? missing_class_match[1] : "[未知类]"
        $logger.error("提示: 类 '#{missing_class}' 可能使用了自定义 Marshal 格式，但其占位符类缺少兼容的 `_load` 实现。")
      end
      return nil # Indicate failure
    rescue EncodingError => e
      $logger.error("Marshal.load 时遇到编码错误 (#{filepath}): #{e.message}")
      return nil # Indicate failure
    rescue => e
      $logger.error("读取或解析 Marshal 文件 #{filepath} 时发生未知错误: #{e.class}: #{e.message}")
      $logger.error(e.backtrace.first(5).join("\n"))
      return nil # Indicate failure
    end
  end # end loop

  loaded_data
end

# --- Comparison Logic (Returns Array of Difference Hashes) ---
def compare_data(path, obj_a, obj_b)
  diffs = []
  return diffs if obj_a.object_id == obj_b.object_id # Same object instance
  return diffs if obj_a == obj_b # Covers simple types and some complex cases if `==` is well-defined

  # Helper for inspect with truncation
  inspect_val = ->(obj) {
    str = obj.inspect rescue "[Inspect Error]"
    # Simple truncation for binary-like strings in inspect
    if obj.is_a?(String) && obj.bytesize > 50 && (!obj.valid_encoding? || obj.bytes.any? { |b| b < 32 && ![9, 10, 13].include?(b) } || obj.bytes.include?(0))
      str = "[Binary-like String (len=#{obj.bytesize})]"
    elsif str.length > 150
      str = str[0, 150] + "..."
    end
    str.gsub(/\n/, "\\n") # Avoid multi-line inspects in single log line
  }

  if obj_a.nil? && obj_b.nil?
    return diffs # Both nil, already covered by obj_a == obj_b technically
  elsif obj_a.nil?
    diffs << { path: path, type: :nil_vs_value, details: { a: "nil", b_class: obj_b.class.name, b_val: inspect_val.call(obj_b) } }
    return diffs
  elsif obj_b.nil?
    diffs << { path: path, type: :value_vs_nil, details: { a_class: obj_a.class.name, a_val: inspect_val.call(obj_a), b: "nil" } }
    return diffs
  end

  # Determine class name, preferring placeholder name if available
  get_class_name = ->(obj) {
    (is_placeholder?(obj) ? (obj.instance_variable_get(:@_placeholder_klass_name) || obj.class.name) : obj.class.name) rescue obj.class.name
  }
  class_a_name = get_class_name.call(obj_a)
  class_b_name = get_class_name.call(obj_b)

  class_name_str = class_a_name # Default report name

  if class_a_name != class_b_name
    is_a_placeholder = is_placeholder?(obj_a)
    is_b_placeholder = is_placeholder?(obj_b)
    placeholder_name_a = is_a_placeholder ? obj_a.instance_variable_get(:@_placeholder_klass_name) : nil
    placeholder_name_b = is_b_placeholder ? obj_b.instance_variable_get(:@_placeholder_klass_name) : nil

    can_compare_placeholders = (is_a_placeholder && !is_b_placeholder && placeholder_name_a == obj_b.class.name) ||
                               (!is_a_placeholder && is_b_placeholder && obj_a.class.name == placeholder_name_b) ||
                               (is_a_placeholder && is_b_placeholder && placeholder_name_a == placeholder_name_b && !placeholder_name_a.nil?)

    unless can_compare_placeholders
      diffs << { path: path, type: :type_mismatch, details: { a_class: class_a_name, b_class: class_b_name, a_val: inspect_val.call(obj_a), b_val: inspect_val.call(obj_b) } }
      return diffs # Stop comparison if types fundamentally differ and aren't equivalent placeholders
    end
    # If types are deemed equivalent (placeholder vs real), use the consistent name for reporting
    class_name_str = placeholder_name_a || placeholder_name_b || class_a_name
  end

  # --- Compare based on Type ---
  case obj_a
  when Array
    if obj_a.length != obj_b.length
      diffs << { path: path, type: :array_length, details: { a_len: obj_a.length, b_len: obj_b.length } }
    end
    max_len = [obj_a.length, obj_b.length].max
    max_len.times do |i|
      new_path = "#{path}[#{i}]"
      item_a = obj_a[i] rescue "[Error reading A index #{i}]"
      item_b = obj_b[i] rescue "[Error reading B index #{i}]"
      # Only compare elements if both indices are valid for the *shorter* array, length diff covers the rest
      # Correction: Compare up to max_len, rely on nil checks inside compare_data
      diffs.concat(compare_data(new_path, item_a, item_b))
    end
  when Hash
    keys_a = obj_a.keys.to_set rescue Set.new # Handle potential errors getting keys
    keys_b = obj_b.keys.to_set rescue Set.new

    missing_in_b = keys_a - keys_b
    missing_in_a = keys_b - keys_a

    if missing_in_b.any?
      diffs << { path: path, type: :missing_key, details: { in_a_not_b: missing_in_b.to_a.map(&:inspect) } }
    end
    if missing_in_a.any?
      diffs << { path: path, type: :missing_key, details: { in_b_not_a: missing_in_a.to_a.map(&:inspect) } }
    end

    # Compare common keys
    (keys_a & keys_b).each do |key|
      val_a = obj_a[key] rescue "[Error reading A key #{key.inspect}]"
      val_b = obj_b[key] rescue "[Error reading B key #{key.inspect}]"
      diffs.concat(compare_data("#{path}[#{key.inspect}]", val_a, val_b))
    end
  when ->(o) { o.respond_to?(:instance_variables) }
    # Generic object comparison using instance variables
    get_ivars = ->(obj) {
      (obj.instance_variables.reject { |v| v.to_s.start_with?("@_") }.to_set) rescue Set.new
    }
    ivars_a = get_ivars.call(obj_a)
    ivars_b = get_ivars.call(obj_b)

    missing_in_b = ivars_a - ivars_b
    missing_in_a = ivars_b - ivars_a

    obj_class_name_for_report = class_name_str

    if missing_in_b.any?
      diffs << { path: path, type: :missing_ivar, details: { class_name: obj_class_name_for_report, in_a_not_b: missing_in_b.map(&:to_s) } }
    end
    if missing_in_a.any?
      diffs << { path: path, type: :missing_ivar, details: { class_name: obj_class_name_for_report, in_b_not_a: missing_in_a.map(&:to_s) } }
    end

    # Compare common instance variables
    (ivars_a & ivars_b).each do |ivar|
      begin
        val_a = obj_a.instance_variable_get(ivar)
      rescue => e
        $logger.warn("无法获取实例变量 #{ivar} 从 A (#{path}): #{e.message}")
        val_a = "[读取错误 A]"
      end
      begin
        val_b = obj_b.instance_variable_get(ivar)
      rescue => e
        $logger.warn("无法获取实例变量 #{ivar} 从 B (#{path}): #{e.message}")
        val_b = "[读取错误 B]"
      end

      diffs.concat(compare_data("#{path}.#{ivar.to_s.sub(/^@/, "")}", val_a, val_b))
    end

    # Basic types comparison (already handled by initial obj_a == obj_b check)
    # when String, Numeric, TrueClass, FalseClass, Symbol
    #   if obj_a != obj_b (covered by initial check)

  else
    # Fallback for other object types - if initial `==` was false
    # This might catch custom classes where `==` isn't defined well,
    # or if the inspection strings differ significantly but `==` is true (less likely).
    # We rely on the initial checks mostly. If we reach here and `==` was false,
    # it implies a value difference not caught by specific type handlers.
    diffs << { path: path, type: :value_mismatch, details: { a_class: class_a_name, b_class: class_b_name, a_val: inspect_val.call(obj_a), b_val: inspect_val.call(obj_b) } }
  end

  diffs
end

# --- Difference Summarization and Logging ---
def summarize_and_log_differences(filename, all_diffs)
  if all_diffs.empty?
    $logger.info("[结果] #{filename}: 未检测到显著差异。")
    return false # No differences found
  end

  $global_comparison_found_differences = true # Mark that differences were found globally
  $logger.info("[结果] #{filename}: 检测到差异，详情如下：")

  grouped_diffs = {}

  all_diffs.each do |diff|
    # Generate a key for grouping similar diffs
    # Pattern: GeneralizedPath::DifferenceType::SpecificDetailsKey
    # Example: root[].name::value_mismatch
    # Example: root[]::missing_ivar::in_a_not_b::@name,@id
    path = diff[:path]
    type = diff[:type]
    details = diff[:details]

    # Generalize path: Replace specific indices/keys with placeholders
    # This is a simple generalization, might need refinement for complex paths
    generalized_path = path.gsub(/\[\d+\]/, "[]").gsub(/\[".*?"\]/, '["key"]').gsub(/\[:'.*?'\]/, "[:key]")
    # Try to remove trailing attribute if it's part of the variation
    generalized_path = generalized_path.sub(/\.\w+$/, "") if type == :value_mismatch || type == :type_mismatch

    details_key_parts = []
    case type
    when :missing_key
      details_key_parts << "in_a_not_b" if details[:in_a_not_b]
      details_key_parts << "in_b_not_a" if details[:in_b_not_a]
      # Include the keys themselves for finer grouping
      details_key_parts << (details[:in_a_not_b]&.sort || []).join(",")
      details_key_parts << (details[:in_b_not_a]&.sort || []).join(",")
    when :missing_ivar
      details_key_parts << "in_a_not_b" if details[:in_a_not_b]
      details_key_parts << "in_b_not_a" if details[:in_b_not_a]
      # Include the ivars themselves for finer grouping
      details_key_parts << (details[:in_a_not_b]&.sort || []).join(",")
      details_key_parts << (details[:in_b_not_a]&.sort || []).join(",")
    when :array_length, :type_mismatch, :value_mismatch, :nil_vs_value, :value_vs_nil
      # Type itself is enough detail for grouping key
      details_key_parts << "" # No extra key needed
    end
    details_key = details_key_parts.join("::")

    group_key = "#{generalized_path}::#{type}::#{details_key}"

    grouped_diffs[group_key] ||= { type: type, generalized_path: generalized_path, details_pattern: details, examples: [] }
    # Store the original path and specific details for examples
    grouped_diffs[group_key][:examples] << { path: path, details: details }
  end

  # Log the summarized differences
  grouped_diffs.each do |key, group|
    example_count = group[:examples].length
    first_example = group[:examples].first

    # Format the summary message
    summary_msg = ""
    path_prefix = first_example[:path].match?(/\.|\[/) ? first_example[:path].split(/[\.\[]/).first + "..." : first_example[:path] # Simplified prefix
    path_info = group[:generalized_path] # Use generalized path for summary

    case group[:type]
    when :nil_vs_value
      summary_msg = "[差异] #{path_info}: A 中为 nil, B 中为 #{first_example[:details][:b_class]}"
    when :value_vs_nil
      summary_msg = "[差异] #{path_info}: A 中为 #{first_example[:details][:a_class]}, B 中为 nil"
    when :type_mismatch
      summary_msg = "[差异] #{path_info}: 类型不匹配 A(#{first_example[:details][:a_class]}) vs B(#{first_example[:details][:b_class]})"
    when :array_length
      summary_msg = "[差异] #{path_info}: 数组长度不匹配 A(#{first_example[:details][:a_len]}) vs B(#{first_example[:details][:b_len]})"
    when :missing_key
      if first_example[:details][:in_a_not_b]
        summary_msg = "[差异] #{path_info}: A 中存在 B 中没有的键: #{first_example[:details][:in_a_not_b].join(", ")}"
      else
        summary_msg = "[差异] #{path_info}: B 中存在 A 中没有的键: #{first_example[:details][:in_b_not_a].join(", ")}"
      end
    when :missing_ivar
      class_name = first_example[:details][:class_name] ? "(#{first_example[:details][:class_name]})" : ""
      if first_example[:details][:in_a_not_b]
        summary_msg = "[差异] #{path_info} #{class_name}: A 中存在 B 中没有的实例变量: #{first_example[:details][:in_a_not_b].join(", ")}"
      else
        summary_msg = "[差异] #{path_info} #{class_name}: B 中存在 A 中没有的实例变量: #{first_example[:details][:in_b_not_a].join(", ")}"
      end
    when :value_mismatch
      summary_msg = "[差异] #{path_info}: 值不匹配"
    else
      summary_msg = "[差异] #{path_info}: 未知类型的差异"
    end

    # Add count and examples
    if example_count == 1
      $logger.info("  #{summary_msg}")
      # Show specific values for single occurrences if value/type mismatch
      if [:value_mismatch, :type_mismatch, :nil_vs_value, :value_vs_nil].include?(group[:type])
        $logger.info("      A: #{first_example[:details][:a_val] || first_example[:details][:a] || "N/A"}")
        $logger.info("      B: #{first_example[:details][:b_val] || first_example[:details][:b] || "N/A"}")
      end
    else
      $logger.info("  #{summary_msg} (共 #{example_count} 处)")
      # Show limited examples
      group[:examples].first(MAX_DIFF_EXAMPLES).each_with_index do |ex, i|
        # Only show values for value/type mismatch examples for brevity
        if [:value_mismatch, :type_mismatch, :nil_vs_value, :value_vs_nil].include?(group[:type])
          $logger.info("      示例 #{i + 1} (#{ex[:path]}): A: #{ex[:details][:a_val] || ex[:details][:a] || "N/A"}, B: #{ex[:details][:b_val] || ex[:details][:b] || "N/A"}")
        elsif i == 0 # For structural diffs, just show path of first example
          $logger.info("      (例如发生在路径: #{ex[:path]})")
        end
      end
      if example_count > MAX_DIFF_EXAMPLES
        $logger.info("      ...")
      end
    end
  end

  return true # Differences found and logged
end

# --- Main Program Logic ---

# Check arguments BEFORE setting up the logger
if ARGV.length != 2
  STDERR.puts "用法: ruby compare_rvdata_folders.rb <目录A路径> <目录B路径>"
  STDERR.puts "       比较在两个目录中根据预定义列表找到的对应 RVData 文件。"
  STDERR.puts "       详细输出和差异总结将被写入 #{LOG_DIR}/#{LOG_FILENAME} 格式的日志文件中。"
  exit 1
end

dir_a = Pathname.new(ARGV[0])
dir_b = Pathname.new(ARGV[1])

unless dir_a.directory?
  STDERR.puts "错误: 目录A未找到或不是一个目录 - #{dir_a}"
  exit 1
end
unless dir_b.directory?
  STDERR.puts "错误: 目录B未找到或不是一个目录 - #{dir_b}"
  exit 1
end

# Now setup the logger
setup_logger

$logger.info("比较目录 A: #{dir_a.expand_path}")
$logger.info("比较目录 B: #{dir_b.expand_path}")
$logger.info("比较规则: #{FILES_TO_COMPARE.inspect}")
$logger.info("=======================================")

comparison_performed = false # Track if any comparison was actually done

FILES_TO_COMPARE.each do |rule|
  $logger.info("\n--- 处理规则: #{rule.inspect} ---")

  files_to_process = []

  if rule.is_a?(String) # Literal filename base
    base_name = rule
    file_a_path = dir_a.join("#{base_name}.rvdata")
    file_b_path = dir_b.join("#{base_name}.rvdata")

    exists_a = file_a_path.file?
    exists_b = file_b_path.file?

    if exists_a && exists_b
      files_to_process << { base: base_name, path_a: file_a_path, path_b: file_b_path, source_rule: rule }
    elsif exists_a
      $logger.info("[信息] 文件仅存在于目录 A: #{file_a_path}")
    elsif exists_b
      $logger.info("[信息] 文件仅存在于目录 B: #{file_b_path}")
    else
      $logger.info("[信息] 在两个目录中均未找到文件: #{base_name}.rvdata")
    end
  elsif rule.is_a?(Regexp) # Pattern
    pattern = rule
    # Find files in both directories matching the pattern
    begin
      files_a = Dir.entries(dir_a).select { |entry| entry.end_with?(".rvdata") && pattern.match?(entry.chomp(".rvdata")) && dir_a.join(entry).file? }
      files_b = Dir.entries(dir_b).select { |entry| entry.end_with?(".rvdata") && pattern.match?(entry.chomp(".rvdata")) && dir_b.join(entry).file? }
    rescue Errno::ENOENT => e
      $logger.error("访问目录时出错: #{e.message}")
      next # Skip this rule if directory access fails
    end

    bases_a = files_a.map { |f| f.chomp(".rvdata") }.to_set
    bases_b = files_b.map { |f| f.chomp(".rvdata") }.to_set

    all_bases = bases_a | bases_b # Union of basenames

    if all_bases.empty?
      $logger.info("[信息] 未找到匹配模式 #{pattern.inspect} 的 .rvdata 文件。")
      next # Skip to the next rule
    end

    all_bases.sort.each do |base_name|
      file_a_path = dir_a.join("#{base_name}.rvdata")
      file_b_path = dir_b.join("#{base_name}.rvdata")

      exists_a = bases_a.include?(base_name)
      exists_b = bases_b.include?(base_name)

      if exists_a && exists_b
        files_to_process << { base: base_name, path_a: file_a_path, path_b: file_b_path, source_rule: rule }
      elsif exists_a
        $logger.info("[信息] 文件仅存在于目录 A (匹配模式): #{file_a_path}")
      elsif exists_b
        $logger.info("[信息] 文件仅存在于目录 B (匹配模式): #{file_b_path}")
      end
    end
  else
    $logger.warn("[警告] 未知的比较规则类型: #{rule.inspect}。已跳过。")
  end

  # Process the collected file pairs for this rule
  files_to_process.each do |file_info|
    base_name = file_info[:base]
    file_a_path = file_info[:path_a]
    file_b_path = file_info[:path_b]
    source_rule = file_info[:source_rule]

    rule_info = source_rule.is_a?(Regexp) ? "(匹配模式 #{source_rule.inspect})" : ""
    $logger.info("[比较] #{base_name}.rvdata #{rule_info}")
    comparison_performed = true

    data_a = load_rvdata_file(file_a_path.to_s) # load_rvdata_file expects string path
    unless data_a
      $logger.error("[跳过比较] 文件 A 加载失败: #{file_a_path}")
      next
    end
    data_b = load_rvdata_file(file_b_path.to_s)
    unless data_b
      $logger.error("[跳过比较] 文件 B 加载失败: #{file_b_path}")
      next
    end

    # Perform comparison and get raw diffs
    raw_diffs = compare_data("root", data_a, data_b)

    # Summarize and log the differences
    summarize_and_log_differences("#{base_name}.rvdata", raw_diffs)
  end # end files_to_process.each
end # End of the FILES_TO_COMPARE.each block

$logger.info("\n=======================================")
$logger.info("--- 动态定义的类/模块列表 (累积) ---")
if $dynamically_defined_classes.empty?
  $logger.info("(无)")
else
  # Log sorted list to the file
  $dynamically_defined_classes.to_a.sort.each do |klass_name|
    $logger.info(klass_name)
  end
end

$logger.info("\n--- 所有文件比较结束 ---")
final_message = ""
exit_code = 0

if !comparison_performed
  final_message = "没有执行任何文件比较（可能没有找到匹配的文件对）。"
  exit_code = 0
elsif $global_comparison_found_differences
  final_message = "在比较过程中检测到差异。详细信息请查看日志文件。"
  exit_code = 1
else
  final_message = "在比较的文件中未检测到显著差异。"
  exit_code = 0
end

$logger.info(final_message)
puts final_message # Also print the final summary to console
exit(exit_code)
