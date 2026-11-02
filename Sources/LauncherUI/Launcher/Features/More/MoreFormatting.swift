import Foundation

// MARK: - 更多页格式化

/// 更多页统一的格式化工具：避免 `ByteCountFormatter` 对 0 字节输出英文 "Zero KB"。
public enum MoreFormatting {
    /// 字节数的人读文本；0 字节显示 "0 B"。
    public static func byteCountText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 字节数的人读文本（Int 版本）。
    public static func byteCountText(_ bytes: Int) -> String {
        byteCountText(Int64(bytes))
    }
}
