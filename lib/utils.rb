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

  # --- detect_encoding_safe 保持不变 (私有类方法，用于检测文件编码) ---
  class << self
    private

    # 安全地检测字符串的编码
    # str: 需要检测编码的字符串
    # 返回: Encoding 对象或 nil
    def detect_encoding_safe(str)
      return nil if str.nil? || str.empty? # 处理空或nil输入
      begin
        sample = str.byteslice(0, 4096) || "" # 取前 4KB 作为样本
        # 优先检查常见的 UTF-8 和 UTF-16LE
        return Encoding::UTF_8 if sample.dup.force_encoding("UTF-8").valid_encoding?
        return Encoding::UTF_16LE if sample.dup.force_encoding("UTF-16LE").valid_encoding?

        # 使用 rchardet 进行检测
        cd = CharDet.detect(sample)
        if cd && cd["confidence"] > 0.5 # 如果检测结果置信度较高
          encoding_name = cd["encoding"].upcase # 获取编码名称并转大写
          case encoding_name # 根据常见的编码名称返回对应的 Encoding 对象
          when "GB18030", "GBK", "GB2312"
            return Encoding.find("GBK") rescue nil # 优先使用 GBK 处理 GB 系列编码
          when "SHIFT_JIS", "EUC-JP"
            return Encoding.find(encoding_name) rescue nil # 处理日文编码
          when "UTF-8"
            return Encoding::UTF_8
          when "ASCII"
            return Encoding::ASCII
          when "WINDOWS-1252"
            return Encoding.find("Windows-1252") rescue nil # 处理西欧语系编码
          else
            return Encoding.find(encoding_name) rescue nil # 尝试查找其他编码
          end
        end
      rescue LoadError
        puts "[警告] 未找到 rchardet gem，Game.ini 编码检测可能不准确。"
      rescue => e
        puts "[警告] Utils.detect_encoding_safe: 检测编码时出错: #{e.message}"
      end
      nil # 检测失败或置信度低时返回 nil
    end
  end
end
