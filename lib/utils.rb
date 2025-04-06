# lib/utils.rb
# 提供通用的辅助函数

# Logging 模块应已加载 (通过 application.rb 或直接 require)
# require_relative "logging"

module Utils
  # 将 Ruby 内部字符串 (可能来自 Marshal.load) 解包为 UTF-8 编码的字符串
  # 会尝试保留原始 UTF-8 字符串，强制转换其他编码为 UTF-8，并替换无效字节。
  # @param str [String, nil] 输入字符串
  # @return [String] 转换为 UTF-8 的字符串，如果输入为 nil 则返回空字符串
  def self.unpack_string(str)
    return "" if str.nil? # 处理 nil 输入
    begin
      # 如果已经是有效的 UTF-8，直接复制返回
      if str.encoding == Encoding::UTF_8 && str.valid_encoding?
        return str.dup # 返回副本以防原始字符串被意外修改
      end

      # 尝试强制编码为 UTF-8
      # 使用 dup 避免修改原始字符串对象
      unpacked = str.dup.force_encoding("UTF-8")

      # 检查强制转换后是否有效
      unless unpacked.valid_encoding?
        # 如果无效，记录警告并替换无效字节
        Logging::Log.warn "字符串强制转换为 UTF-8 后包含无效编码。将替换无效字节。原始 inspect: #{str.inspect[0..100]}..."
        # 使用 encode! 进行原地替换
        unpacked.encode!("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      end
      return unpacked
    rescue => e
      # 捕获强制转换或编码检查期间的意外错误
      Logging::Log.error "Utils.unpack_string 中发生意外错误: #{e.message} (字符串: #{str.inspect[0..100]}...)"
      begin
        # 作为最终回退，尝试返回 ASCII-8BIT (二进制) 编码的副本
        # 这至少保留了原始字节序列，虽然可能不是可读文本
        return str.dup.force_encoding("ASCII-8BIT")
      rescue
        # 如果连 ASCII-8BIT 都失败，记录致命错误并返回空字符串
        Logging::Log.fatal "Utils.unpack_string: 连返回 ASCII-8BIT 都失败！将返回空字符串。"
        return ""
      end
    end
  end

  # 对指定对象的特定实例变量 (如果它们是字符串) 进行 UTF-8 解包
  # @param object [Object] 要操作的对象
  # @param attributes [Symbol, String] 一个或多个属性名 (不需要加 @)
  def self.unpack_names_for(object, *attributes)
    attributes.each do |attr|
      # 构造实例变量符号 (e.g., :@name)
      ivar_name = "@#{attr}".to_sym
      # 检查对象是否有此实例变量
      if object.instance_variable_defined?(ivar_name)
        # 获取实例变量的值
        value = object.instance_variable_get(ivar_name)
        # 如果值是字符串，则进行解包
        if value.is_a?(String)
          unpacked_value = Utils.unpack_string(value)
          # 将解包后的值设置回实例变量
          object.instance_variable_set(ivar_name, unpacked_value)
        end
      end
    end
  end

  # --- 安全地检测字符串编码 (内部辅助方法) ---
  # 优先使用 UTF-8 BOM，其次尝试 rchardet gem (如果可用)，失败则返回 nil。
  # @param str [String] 要检测的字符串 (通常是文件开头的字节)
  # @return [String, nil] 检测到的编码名称 (如 "UTF-8", "Shift_JIS")，或 nil 如果无法确定
  class << self
    private

    def detect_encoding_safe(str)
      return nil if str.nil? || str.empty?

      begin
        # 1. 检查 UTF-8 BOM (Byte Order Mark)
        # BOM 是文件开头的特定字节序列 (EF BB BF)
        if str.bytesize >= 3 && str.start_with?("\xEF\xBB\xBF".b) # .b 表示二进制字符串
          Logging::Log.debug "检测到 UTF-8 BOM" if Logging::Log.debug?
          return "UTF-8"
        end

        # 2. 尝试使用 rchardet gem 进行检测 (如果已安装)
        begin
          # 延迟加载 rchardet，避免不必要的依赖
          require "rchardet" unless defined?(CharDet)
          # 只检测字符串开头的一部分以提高效率
          sample = str.byteslice(0, 4096) || "" # 取最多 4KB
          # 调用 rchardet 进行检测
          cd = CharDet.detect(sample)
          # 检查结果是否有效且置信度足够高
          if cd && cd["encoding"] && cd["confidence"] > 0.5
            encoding_name = cd["encoding"]
            # 记录检测结果
            Logging::Log.debug "rchardet 检测到: #{encoding_name} (置信度: #{cd["confidence"]})" if Logging::Log.debug?
            # 确保编码名称非空
            return encoding_name unless encoding_name.strip.empty?
            # 如果编码名称为空但置信度高，记录警告
            Logging::Log.warn "rchardet 返回了高置信度但编码名称为空。"
          else
            # 记录检测失败或置信度低的情况
            Logging::Log.debug "rchardet 检测失败或置信度低 (结果: #{cd.inspect})" if Logging::Log.debug?
          end
        rescue LoadError
          # 如果 rchardet gem 未安装，只警告一次
          @rchardet_warned ||= begin
              Logging::Log.warn "未找到 rchardet gem。Game.ini 等文件的编码检测可能不太准确。建议运行 `gem install rchardet` 以获得更好结果。"
              true # 标记已警告
            end
        rescue => e_chardet
          # 记录 rchardet 检测过程中的其他错误
          Logging::Log.warn "rchardet 检测期间出错: #{e_chardet.class}: #{e_chardet.message}"
        end

        # 3. 如果以上方法都失败，返回 nil
        return nil
      rescue => e
        # 捕获编码检测过程中的任何意外错误
        Logging::Log.warn "Utils.detect_encoding_safe: 编码检测期间出错: #{e.class}: #{e.message}"
        Logging::Log.debug e.backtrace.first(5).join("\n") if Logging::Log.debug?
        return nil # 出错则返回 nil
      end
    end
  end # class << self (使 detect_encoding_safe 成为私有类方法)
end # module Utils
