# encoding: utf-8
# rvdata2json/lib/utils.rb
# 提供通用的辅助函数 (最终简化版: 假设输入为 UTF-8 或标记错误的 UTF-8)

require "rchardet" unless defined?(CharDet) # 保留，供内部 detect_encoding_safe 使用

# 工具模块
module Utils
  # 将 Ruby 内部字符串解包为 UTF-8 编码的字符串
  # 假设输入要么是 UTF-8，要么是标记错误的 UTF-8
  def self.unpack_string(str)
    return "" if str.nil?

    # 1. 检查是否已是有效的 UTF-8
    if str.encoding == Encoding::UTF_8 && str.valid_encoding?
      return str.dup
    end

    # 2. 尝试将标记强制为 UTF-8 并验证字节内容
    begin
      utf8_forced_str = str.dup.force_encoding("UTF-8")
      if utf8_forced_str.valid_encoding?
        # 这是处理 "ASCII-8BIT 标记 + UTF-8 内容" 的情况
        return utf8_forced_str
      else
        # 如果强制为 UTF-8 后仍然无效，说明底层字节本身就有问题
        # 这超出了我们的假设范围
        puts "[错误] Utils.unpack_string: 字符串标记为非 UTF-8，且强制为 UTF-8 后内容无效！"
        puts "  原始编码标记: #{str.encoding.name}"
        puts "  原始字节 (前 100): #{str.bytes.inspect[0..150]}..."
        # 返回原始字符串，标记为二进制，让后续处理决定如何应对
        return str.dup.force_encoding("ASCII-8BIT")
      end
    rescue => e
      # 捕获 force_encoding 可能的罕见错误
      puts "[错误] Utils.unpack_string: force_encoding('UTF-8') 失败: #{e.message}"
      return str.dup.force_encoding("ASCII-8BIT")
    end

    # 移除 unpack("U*") 和最终 encode 回退
    # 如果代码执行到这里，说明发生了意料之外的情况
    # (理论上基于我们的假设，不应该到这里)
  rescue => e
    puts "[错误] Utils.unpack_string 发生顶层意外错误: #{e.message} for string: #{str.inspect[0..100]}..."
    str.dup.force_encoding("ASCII-8BIT")
  end

  # --- pack_string 保持不变 ---
  def self.pack_string(str)
    str.encode("UTF-16LE")
  rescue Encoding::ConverterNotFoundError
    puts "[错误] Utils.pack_string: 无法将字符串编码为 UTF-16LE。"
    raise
  end

  # --- unpack_names_for 保持不变 ---
  def self.unpack_names_for(object, *attributes)
    attributes.each do |attr|
      ivar_name = "@#{attr}".to_sym
      if object.instance_variable_defined?(ivar_name)
        value = object.instance_variable_get(ivar_name)
        if value.is_a?(String)
          unpacked_value = Utils.unpack_string(value)
          object.instance_variable_set(ivar_name, unpacked_value)
        end
      end
    end
  end

  # --- detect_encoding_safe 保持不变 (私有类方法) ---
  class << self
    private

    def detect_encoding_safe(str)
      return nil if str.nil? || str.empty?
      begin
        sample = str.byteslice(0, 4096) || ""
        # Keep UTF-8/UTF-16LE check first for common cases
        return Encoding::UTF_8 if sample.dup.force_encoding("UTF-8").valid_encoding?
        return Encoding::UTF_16LE if sample.dup.force_encoding("UTF-16LE").valid_encoding?

        cd = CharDet.detect(sample)
        if cd && cd["confidence"] > 0.5
          encoding_name = cd["encoding"].upcase
          case encoding_name
          when "GB18030", "GBK", "GB2312"
            return Encoding.find("GBK") rescue nil # Prefer GBK
          when "SHIFT_JIS", "EUC-JP"
            return Encoding.find(encoding_name) rescue nil
          when "UTF-8"
            return Encoding::UTF_8
          when "ASCII"
            return Encoding::ASCII
          when "WINDOWS-1252"
            return Encoding.find("Windows-1252") rescue nil
          else
            return Encoding.find(encoding_name) rescue nil
          end
        end
      rescue LoadError
        puts "[警告] 未找到 rchardet gem，Game.ini 编码检测可能不准确。"
      rescue => e
        puts "[警告] Utils.detect_encoding_safe: 检测编码时出错: #{e.message}"
      end
      nil
    end
  end
end
