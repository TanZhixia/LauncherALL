import SwiftUI

/// 内置主题注册表：一深一浅两套中性主题，只换色不换结构。
/// 每套主题只有一个高对比强调色（近白或近黑），其余全部为中性灰阶。
public enum LauncherThemes {
    /// 石墨：中性冷灰深色，最常用的默认主题
    public static let graphite = LauncherTheme.dark(
        id: "graphite",
        name: "石墨",
        tagline: "深色 · 中性灰",
        canvas: Color(hex: 0x0F1012),
        surface: Color(hex: 0x17181B),
        surfaceElevated: Color(hex: 0x1E2024),
        surfaceSubtle: Color(hex: 0x0A0B0C),
        stroke: Color(hex: 0x2A2D32),
        strokeStrong: Color(hex: 0x3E424A),
        textPrimary: Color(hex: 0xF2F3F5),
        textSecondary: Color(hex: 0xA8AEB8),
        textTertiary: Color(hex: 0x717883),
        accent: Color(hex: 0xF2F3F5),
        onAccent: Color(hex: 0x16171A)
    )

    /// 瓷白：纯白冷灰浅色，像一张干净的纸
    public static let porcelain = LauncherTheme.light(
        id: "porcelain",
        name: "瓷白",
        tagline: "浅色 · 冷灰",
        canvas: Color(hex: 0xF5F5F6),
        surface: Color(hex: 0xFFFFFF),
        surfaceElevated: Color(hex: 0xFAFAFB),
        surfaceSubtle: Color(hex: 0xEFEFF1),
        stroke: Color(hex: 0xE2E2E5),
        strokeStrong: Color(hex: 0xC9C9CE),
        textPrimary: Color(hex: 0x18181B),
        textSecondary: Color(hex: 0x57575F),
        textTertiary: Color(hex: 0x8A8A93),
        accent: Color(hex: 0x18181B),
        onAccent: Color(hex: 0xFAFAFA)
    )

    /// 全量主题（顺序即画廊展示顺序）
    public static let all: [LauncherTheme] = [graphite, porcelain]

    public static let `default` = graphite

    public static func theme(withID id: String) -> LauncherTheme {
        all.first { $0.id == id } ?? `default`
    }
}
