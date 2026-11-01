import SwiftUI
import AppKit

// MARK: - 基础工具

public extension Color {
    /// 从 0xRRGGBB 生成颜色，可附带透明度。
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// 与另一颜色按比例混合：用于从少量基色推导 hover / active / soft 态，保证多主题一致。
    func mixed(with other: Color, amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? NSColor.black
        let t = max(0, min(1, amount))
        return Color(
            .sRGB,
            red: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
            opacity: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t
        )
    }
}

/// 间距刻度：4pt 基准，全项目只允许使用这些值。
public enum LauncherSpace {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

/// 圆角刻度。
public enum LauncherRadius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 14
    public static let xl: CGFloat = 18
    public static let xxl: CGFloat = 24
    public static let pill: CGFloat = 999
}

/// 控件高度刻度。
public enum LauncherControl {
    public static let small: CGFloat = 28
    public static let medium: CGFloat = 34
    public static let large: CGFloat = 44
    public static let icon: CGFloat = 34
}

/// 动效刻度：平面化后只保留状态切换的短促过渡。
public enum LauncherMotion {
    public static let fast: Double = 0.10
    public static let base: Double = 0.16
    public static let slow: Double = 0.24
    public static var spring: Animation { .easeOut(duration: base) }
    public static var smooth: Animation { .easeInOut(duration: base) }
}

/// 面板层级：平面化风格下，层级只由「底色 + 1px 边框」表达，不使用模糊/投影/发光。
public enum GlassLevel: String, CaseIterable {
    /// 内嵌：输入框容器、列表底、代码块（比页面底色再深/浅一档）
    case subtle
    /// 常规面板：卡片、分组
    case regular
    /// 浮层：侧栏、弹窗、Toast
    case strong
}

// MARK: - 语义色令牌

/// 一套主题的全部语义色。组件不得直接使用十六进制色值。
public struct LauncherColors: Equatable {
    /// 页面底色
    public var canvas: Color
    /// 常规面板底
    public var surface: Color
    /// 浮层底（侧栏、弹窗）
    public var surfaceElevated: Color
    /// 内嵌凹槽底（输入框、进度轨、segmented 容器）
    public var surfaceSubtle: Color
    /// hover 态
    public var surfaceHover: Color
    /// pressed / 选中态
    public var surfaceActive: Color
    /// 1px 细描边
    public var stroke: Color
    /// 强调描边（选中、hover 边界）
    public var strokeStrong: Color
    public var textPrimary: Color
    public var textSecondary: Color
    public var textTertiary: Color
    /// 唯一强调色：按钮、选中、焦点，全站只允许这一处彩色（默认中性高对比）
    public var accent: Color
    /// 强调色的次级表现（平面化后与 accent 同色，保留令牌位）
    public var accentAlt: Color
    /// 强调底上的前景色
    public var onAccent: Color
    /// 强调色的极淡底（选中行背景）
    public var accentSoft: Color
    public var success: Color
    public var warning: Color
    public var danger: Color
    public var onDanger: Color
    public var focusRing: Color

    public init(
        canvas: Color,
        surface: Color,
        surfaceElevated: Color,
        surfaceSubtle: Color,
        surfaceHover: Color,
        surfaceActive: Color,
        stroke: Color,
        strokeStrong: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        accent: Color,
        accentAlt: Color,
        onAccent: Color,
        accentSoft: Color,
        success: Color,
        warning: Color,
        danger: Color,
        onDanger: Color,
        focusRing: Color
    ) {
        self.canvas = canvas
        self.surface = surface
        self.surfaceElevated = surfaceElevated
        self.surfaceSubtle = surfaceSubtle
        self.surfaceHover = surfaceHover
        self.surfaceActive = surfaceActive
        self.stroke = stroke
        self.strokeStrong = strokeStrong
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.accent = accent
        self.accentAlt = accentAlt
        self.onAccent = onAccent
        self.accentSoft = accentSoft
        self.success = success
        self.warning = warning
        self.danger = danger
        self.onDanger = onDanger
        self.focusRing = focusRing
    }
}

// MARK: - 主题

public struct LauncherTheme: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var tagline: String
    public var scheme: ColorScheme
    public var colors: LauncherColors
    /// 主题卡片用的色板（底色 / 面板 / 强调）
    public var swatch: [Color]

    public var isDark: Bool { scheme == .dark }

    public init(
        id: String,
        name: String,
        tagline: String,
        scheme: ColorScheme,
        colors: LauncherColors,
        swatch: [Color]
    ) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.scheme = scheme
        self.colors = colors
        self.swatch = swatch
    }
}

// MARK: - 主题工厂

public extension LauncherTheme {
    /// 深色主题：中性色骨架 + 单一高对比强调色（默认近白），hover/选中态由基色自动推导。
    static func dark(
        id: String,
        name: String,
        tagline: String,
        canvas: Color,
        surface: Color,
        surfaceElevated: Color,
        surfaceSubtle: Color,
        stroke: Color,
        strokeStrong: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        accent: Color,
        onAccent: Color,
        success: Color = Color(hex: 0x3FB950),
        warning: Color = Color(hex: 0xD29922),
        danger: Color = Color(hex: 0xF85149)
    ) -> LauncherTheme {
        let colors = LauncherColors(
            canvas: canvas,
            surface: surface,
            surfaceElevated: surfaceElevated,
            surfaceSubtle: surfaceSubtle,
            surfaceHover: surface.mixed(with: .white, amount: 0.06),
            surfaceActive: surface.mixed(with: .white, amount: 0.12),
            stroke: stroke,
            strokeStrong: strokeStrong,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textTertiary: textTertiary,
            accent: accent,
            accentAlt: accent,
            onAccent: onAccent,
            accentSoft: accent.mixed(with: canvas, amount: 0.88),
            success: success,
            warning: warning,
            danger: danger,
            onDanger: canvas,
            focusRing: accent
        )
        return LauncherTheme(
            id: id, name: name, tagline: tagline, scheme: .dark,
            colors: colors,
            swatch: [canvas, surfaceElevated, accent]
        )
    }

    /// 浅色主题。
    static func light(
        id: String,
        name: String,
        tagline: String,
        canvas: Color,
        surface: Color,
        surfaceElevated: Color,
        surfaceSubtle: Color,
        stroke: Color,
        strokeStrong: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        accent: Color,
        onAccent: Color,
        success: Color = Color(hex: 0x1A7F37),
        warning: Color = Color(hex: 0x9A6700),
        danger: Color = Color(hex: 0xCF222E)
    ) -> LauncherTheme {
        let colors = LauncherColors(
            canvas: canvas,
            surface: surface,
            surfaceElevated: surfaceElevated,
            surfaceSubtle: surfaceSubtle,
            surfaceHover: surface.mixed(with: .black, amount: 0.04),
            surfaceActive: surface.mixed(with: .black, amount: 0.08),
            stroke: stroke,
            strokeStrong: strokeStrong,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textTertiary: textTertiary,
            accent: accent,
            accentAlt: accent,
            onAccent: onAccent,
            accentSoft: accent.mixed(with: canvas, amount: 0.92),
            success: success,
            warning: warning,
            danger: danger,
            onDanger: .white,
            focusRing: accent
        )
        return LauncherTheme(
            id: id, name: name, tagline: tagline, scheme: .light,
            colors: colors,
            swatch: [canvas, surfaceElevated, accent]
        )
    }
}
