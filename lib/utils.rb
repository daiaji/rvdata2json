# encoding: utf-8
# rvdata2json/lib/utils.rb
# 提供通用的辅助函数

require "rchardet" unless defined?(CharDet) # 条件加载，避免重复

# 工具模块
module Utils
  # 将 Ruby 内部字符串 (可能非 UTF-8) 解包为 UTF-8 编码的字符串
  # Marshal 加载后的 String 对象可能需要此操作
  # @param str [String, nil] 输入字符串
  # @return [String] UTF-8 编码的字符串，如果输入为 nil 则返回空字符串
  def self.unpack_string(str)
    return "" if str.nil?
    # U* 适用于 UCS-2/UTF-16LE 等，但有时不可靠
    begin
      # 优先尝试明确的 unpack
      unpacked = str.unpack("U*")
      # 检查解包结果是否合理（避免超大码点）
      if unpacked.all? { |c| c >= 0 && c <= 0x10FFFF }
        return unpacked.map { |c| c.chr("UTF-8") }.join
      else
        raise ArgumentError, "Unpack resulted in invalid codepoints."
      end
    rescue ArgumentError, Encoding::UndefinedConversionError => e
      # 如果解包失败，尝试检测编码或强制转换
      puts "[警告] Utils.unpack_string 解包失败 ('#{str.inspect}'): #{e.message}。尝试编码检测/强制转换。"
      original_encoding = str.encoding
      detected_encoding = detect_encoding_safe(str) || original_encoding

      begin
        # 尝试转换为 UTF-8
        utf8_str = str.encode("UTF-8", detected_encoding, invalid: :replace, undef: :replace)
        # 验证转换后的字符串
        if utf8_str.valid_encoding?
          puts "[调试] Utils.unpack_string: 使用 #{detected_encoding} -> UTF-8 转换成功。"
          return utf8_str
        else
          puts "[警告] Utils.unpack_string: #{detected_encoding} -> UTF-8 转换后仍无效。"
          # 最后回退，尝试强制设为 UTF-8 (如果它看起来像 UTF-8)
          if str.dup.force_encoding("UTF-8").valid_encoding?
            puts "[调试] Utils.unpack_string: 强制设为 UTF-8 有效。"
            return str.dup.force_encoding("UTF-8")
          end
        end
      rescue Encoding::ConverterNotFoundError, Encoding::InvalidByteSequenceError => enc_e
        puts "[警告] Utils.unpack_string: 从 #{detected_encoding} 转换为 UTF-8 失败: #{enc_e.message}。"
      end
      # 所有尝试失败后返回原始字符串，但标记为二进制可能更安全
      puts "[警告] Utils.unpack_string: 所有解包/转换尝试失败，返回原始（可能标记为二进制）字符串。"
      str.dup.force_encoding("ASCII-8BIT")
    end
  end

  # 将 UTF-8 编码的字符串打包回 Ruby 内部表示 (RGSS3 需要，通常是 UTF-16LE)
  # @param str [String] UTF-8 编码的字符串
  # @return [String] 打包后的字符串 (二进制)
  def self.pack_string(str)
    # 明确转换为 UTF-16LE 并返回二进制字符串
    str.encode("UTF-16LE")
  rescue Encoding::ConverterNotFoundError
    # 如果系统不支持 UTF-16LE，尝试备选方案或报错
    puts "[错误] Utils.pack_string: 无法将字符串编码为 UTF-16LE。"
    raise
  end

  # 辅助方法：为对象的指定属性应用字符串解包 (unpack_string)
  # @param object [Object] 目标对象
  # @param attributes [Array<Symbol>] 需要解包的属性名 (Symbol 形式)
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

  private

  # 安全地检测字符串编码
  # @param str [String]
  # @return [Encoding, nil] 检测到的编码或 nil
  def self.detect_encoding_safe(str)
    return nil if str.nil? || str.empty?
    begin
      # 使用字符串片段进行检测，提高效率和准确性
      sample = str.byteslice(0, 4096) || ""
      cd = CharDet.detect(sample)
      # 提高置信度门槛，并优先考虑常见的中文/日文编码
      if cd && cd["confidence"] > 0.6
        encoding_name = cd["encoding"].upcase
        case encoding_name
        when "GB18030", "GBK", "GB2312"
          # 可能需要映射到 Ruby 的 Encoding 名称
          return Encoding.find("GB18030") rescue Encoding.find("GBK")
        when "SHIFT_JIS", "EUC-JP"
          return Encoding.find(encoding_name) rescue nil
        when "UTF-8"
          return Encoding::UTF_8
        when "ASCII"
          return Encoding::ASCII
          # 可以添加其他编码处理
        else
          puts "[调试] Utils.detect_encoding_safe: 检测到编码 #{encoding_name} (置信度 #{cd["confidence"]})，尝试查找。"
          return Encoding.find(encoding_name) rescue nil
        end
      end
    rescue => e
      puts "[警告] Utils.detect_encoding_safe: 检测编码时出错: #{e.message}"
    end
    nil # 检测失败或置信度低
  end
end
