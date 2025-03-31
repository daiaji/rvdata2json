#!/usr/bin/env ruby
# 验证 Marshal.load 是否从 .rvdata2 文件本身加载非标准属性，
# 不依赖项目中的 shared.rb 或 rgss3.rb 的 RPG::State 定义。
# 添加 RPG::BaseItem::Feature 占位符以允许加载。

# --- 最小化类定义 ---
# 只需要定义模块和类名即可。
module RPG
  # --- 添加 BaseItem 占位符 ---
  class BaseItem
    # 嵌套 Feature 占位符
    class Feature
      # 这个类也是空的
    end
  end

  # --- 结束 BaseItem 占位符 ---

  class State
    # 这个类仍然是空的！
  end
end

# --- 结束最小化定义 ---

# 指定要加载的文件路径
rvdata_file_path = "/home/daiaji/下载/新建文件夹/Data/States.rvdata2" # 请确保此路径正确

puts "\n--- 开始加载 Marshal 文件 (使用最小化占位符类): #{File.basename(rvdata_file_path)} ---"

# 检查文件是否存在
unless File.exist?(rvdata_file_path)
  puts "错误：文件未找到 - #{rvdata_file_path}"
  exit 1
end

loaded_data = nil
begin
  # 以二进制模式读取并加载 Marshal 数据
  File.open(rvdata_file_path, "rb") do |file|
    loaded_data = Marshal.load(file)
  end
  puts "Marshal.load 完成。"
rescue ArgumentError => e
  if e.message.include?("undefined class/module")
    puts "错误：Marshal.load 失败 - #{e.message}"
    puts "检查是否还有其他依赖的类未定义占位符？"
  else
    puts "错误：Marshal.load 失败 (可能是版本不匹配或文件损坏): #{e.message}"
  end
  exit 1
rescue TypeError => e
  puts "错误：Marshal.load 失败 (类型错误): #{e.message}"
  exit 1
rescue => e
  puts "错误：读取或解析 Marshal 文件时发生未知错误: #{e.class}: #{e.message}"
  exit 1
end

puts "\n--- 检查加载后的对象 (使用最小化 RPG::State 和 RPG::BaseItem::Feature) ---"

# 检查加载的数据结构和第一个 RPG::State 对象
if loaded_data.is_a?(Array)
  puts "加载的数据是一个数组，大小: #{loaded_data.size}"

  # 查找第一个 RPG::State 对象
  first_state_index = loaded_data.find_index { |item| item.is_a?(RPG::State) }

  if first_state_index
    state_obj = loaded_data[first_state_index]
    puts "在索引 #{first_state_index} 找到第一个 RPG::State 对象:"
    puts "  对象的实际类 (应为我们定义的占位符): #{state_obj.class}"
    puts "  对象的实例变量列表 (由 Marshal.load 从文件附加):"
    state_obj.instance_variables.sort.each do |ivar|
      begin
        value = state_obj.instance_variable_get(ivar)
        # 对可能包含非UTF8数据的字符串进行安全检查
        if value.is_a?(String) && !value.valid_encoding?
          display_value = "[非UTF8字符串, bytes: #{value.bytes.first(10).inspect}...]"
        elsif ivar == :@features && value.is_a?(Array) # 特别处理 features 数组
          display_value = "[#{value.map { |f| f.class }.join(", ")}]" # 显示数组内对象的类名
        else
          display_value = value.inspect
        end
        puts "    #{ivar}: #{display_value}"
      rescue => e
        puts "    #{ivar}: [无法获取值: #{e.message}]"
      end
    end

    # --- 关键检查 ---
    puts "\n  --- 特定变量检查 ---"
    release_defined = state_obj.instance_variable_defined?(:@release_by_damage)
    remove_defined = state_obj.instance_variable_defined?(:@remove_by_damage)

    puts "  @release_by_damage 是否存在? #{release_defined}"
    if release_defined
      puts "    (值已在上面列表中显示)"
    end
    puts "  @remove_by_damage 是否存在? #{remove_defined}"
    if remove_defined
      puts "    (值已在上面列表中显示)"
    end
    puts "  ---------------------"
  else
    puts "在加载的数据中未找到 RPG::State 对象。"
  end
else
  puts "加载的数据不是预期的数组结构，类型为: #{loaded_data.class}"
end

puts "\n--- 最小化 DEMO 结束 ---"
