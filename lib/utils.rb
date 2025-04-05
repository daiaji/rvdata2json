# 提供通用的辅助函数

require "rchardet" unless defined?(CharDet) # 除非已经定义，否则加载 rchardet (供内部 detect_encoding_safe 使用)

# 工具模块
module Utils
  # 将 Ruby 内部字符串解包为 UTF-8 编码的字符串
  # 严格假设: 输入要么是有效的 UTF-8，要么是标记为 ASCII-8BIT 但内容是 UTF-8
  def self.unpack_string(str)
    return "" if str.nil?

    # 1. 检查是否已是有效的 UTF-8 (最常见情况)
    if str.encoding == Encoding::UTF_8 && str.valid_encoding?
      return str.dup
    end

    # 2. 根据假设，此时必然是 "ASCII-8BIT 标记 + UTF-8 内容"
    #    直接修改副本的编码标记为 UTF-8。
    return str.dup.force_encoding("UTF-8")

    # 捕获所有可能的意外错误 (如 nil 对象、dup 失败、极罕见的 force_encoding 失败等)
  rescue => e
    puts "[错误] Utils.unpack_string 发生意外错误: #{e.message} for string: #{str.inspect[0..100]}..."
    # 发生任何未预料的错误时，返回原始二进制标记作为后备
    begin
      return str.dup.force_encoding("ASCII-8BIT")
    rescue # 如果连 dup 或 force_encoding("ASCII-8BIT") 都失败，返回空字符串
      puts "[严重错误] Utils.unpack_string: 连返回 ASCII-8BIT 都失败！返回空字符串。"
      return ""
    end
  end

  # 对指定对象的特定属性值（如果是字符串）进行解包 (unpack_string)
  # object: 目标对象
  # attributes: 一个或多个属性名 (Symbol)
  def self.unpack_names_for(object, *attributes)
    attributes.each do |attr|
      ivar_name = "@#{attr}".to_sym # 构造实例变量名符号
      if object.instance_variable_defined?(ivar_name) # 检查对象是否有此实例变量
        value = object.instance_variable_get(ivar_name) # 获取实例变量的值
        if value.is_a?(String) # 如果值是字符串
          unpacked_value = Utils.unpack_string(value) # 调用 unpack_string 进行解包
          object.instance_variable_set(ivar_name, unpacked_value) # 将解包后的值设置回实例变量
        end
      end
    end
  end

  # --- detect_encoding_safe ---
  class << self
    private

    # 安全地检测字符串的编码，优先BOM，然后rchardet
    # str: 需要检测编码的字符串 (二进制模式读取的样本)
    # 返回: 编码名称字符串 (例如 "UTF-8", "Shift_JIS", "GBK") 或 nil
    def detect_encoding_safe(str)
      return nil if str.nil? || str.empty?

      begin
        # 1. BOM (Byte Order Mark) 检测
        #    确保使用 byteslice，因为输入可能是任意字节序列
        if str.bytesize >= 3 && str.start_with?("\xEF\xBB\xBF".b)
          puts "[调试] 检测到 UTF-8 BOM" if $DEBUG
          return "UTF-8"
          # 可以根据需要添加其他 BOM 检测 (例如 UTF-32)
        end

        # 2. Rchardet 检测 (如果没有 BOM)
        #    使用较大的样本进行检测
        sample = str.byteslice(0, 4096) || "" # 确保样本不为 nil
        cd = CharDet.detect(sample)

        if cd && cd["encoding"] && cd["confidence"] > 0.5 # 检查 encoding 是否存在且置信度足够
          encoding_name = cd["encoding"]
          puts "[调试] rchardet 检测到: #{encoding_name} (置信度: #{cd["confidence"]})" if $DEBUG
          # 直接返回 rchardet 检测到的名称，不做映射
          # IniFile 通常能处理 rchardet 返回的标准名称
          return encoding_name unless encoding_name.strip.empty? # 防止返回空字符串
          puts "[警告] rchardet 返回有效置信度但编码名称为空。" if $DEBUG
        else
          puts "[调试] rchardet 检测失败或置信度低 (结果: #{cd.inspect})" if $DEBUG
        end

        # 3. 如果 BOM 和 rchardet 都失败，返回 nil
        return nil
      rescue LoadError
        # 保持原始警告，因为 rchardet 确实是可选的依赖
        puts "[警告] 未找到 rchardet gem，Game.ini 编码检测可能不准确。"
        return nil # 返回 nil 表示无法检测
      rescue => e
        # 记录通用检测错误
        puts "[警告] Utils.detect_encoding_safe: 检测编码时发生错误: #{e.class}: #{e.message}"
        # puts e.backtrace.first(5).join("\n") # Debug 时可以取消注释
        return nil # 返回 nil 表示检测失败
      end
    end
  end
end
