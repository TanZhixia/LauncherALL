import SwiftUI

// MARK: - 基础工具

public extension Color {
    /// 从 0xRRGGBB 生成颜色，可附带透明度。
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
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
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 22
    public static let xxl: CGFloat = 28
    public static let pill: CGFloat = 999
}

/// 控件高度刻度。
public enum LauncherControl {
    public static let small: CGFloat = 28
    public static let medium: CGFloat = 34
    public static let large: CGFloat = 44
    public static let icon: CGFloat = 34
}

/// 动效刻度。
public enum LauncherMotion {
    public static let fast: Double = 0.12
    public static let base: Double = 0.2
    public static let slow: Double = 0.32
    public static var spring: Animation { .spring(response: 0.34, dampingFraction: 0.82) }
    public static var smooth: Animation { .easeInOut(duration: base) }
}

/// 玻璃材质等级（不直接暴露 Material，保证主题可比较/可持久化）。
public enum LauncherMaterial: String, CaseIterable, Equatable {
    case ultraThin, thin, regular, thick

    public var material: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        }
    }
}

/// 玻璃面板层级：subtle 内嵌、regular 常规卡片、strong 浮层/弹窗。
public enum GlassLevel: String, CaseIterable {
    case subtle, regular, strong

    public var tintMultiplier: Double {
        switch self {
        case .subtle: return 0.5
        case .regular: return 1.0
        case .strong: return 1.55
        }
    }

    public var strokeMultiplier: Double {
        switch self {
        case .subtle: return 0.6
        case .regular: return 1.0
        case .strong: return 1.4
        }
    }

    public var shadowMultiplier: Double {
        switch self {
        case .subtle: return 0.2
        case .regular: return 1.0
        case .strong: return 1.6
        }
    }
}

// MARK: - 语义色令牌

/// 一套主题的全部语义色，组件不得直接使用十六进制色值。
public struct LauncherColors: Equatable {
    /// 窗口/画布底色（不透明，材质之下的兜底色）
    public var canvas: Color
    /// 玻璃面板填充色（已烘焙透明度）
    public var surface: Color
    /// 更实一层的表面（浮层/侧栏）
    public var surfaceElevated: Color
    /// 内嵌凹槽（输入框、轨道、代码块）
    public var surfaceSubtle: Color
    /// hover 态表面
    public var surfaceHover: Color
    /// pressed / 选中态表面
    public var surfaceActive: Color
    /// 1px 细描边
    public var stroke: Color
    /// 强调描边（hover、分割线、选中边框）
    public var strokeStrong: Color
    public var textPrimary: Color
    public var textSecondary: Color
    public var textTertiary: Color
    public var accent: Color
    public var accentAlt: Color
    /// 强调色底上的前景色
    public var onAccent: Color
    /// 强调色的柔和底（选中行背景）
    public var accentSoft: Color
    public var success: Color
    public var warning: Color
    public var danger: Color
    public var onDanger: Color
    public var focusRing: Color
    public var shadow: Color

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
        focusRing: Color,
        shadow: Color
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
        self.shadow = shadow
    }
}

// MARK: - 玻璃 & 氛围令牌

public struct LauncherGlass: Equatable {
    public var material: LauncherMaterial
    /// 玻璃本身的着色倾向（深色主题用白，浅色主题用白/黑混合）
    public var tint: Color
    public var tintOpacity: Double
    /// 顶部高光强度（0 = 不画高光）
    public var highlightOpacity: Double
    public var shadowRadius: CGFloat
    public var shadowY: CGFloat
}

public struct LauncherAmbient: Equatable {
    /// 背景主渐变（自上而下）
    public var gradient: [Color]
    /// 左上氛围光
    public var glowPrimary: Color
    /// 右下氛围光
    public var glowSecondary: Color
    /// 像素网格透明度（Minecraft 的方块暗示，0 = 关闭）
    public var gridOpacity: Double
    /// 暗角强度
    public var vignetteOpacity: Double
}

// MARK: - 主题

public struct LauncherTheme: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var tagline: String
    public var scheme: ColorScheme
    public var colors: LauncherColors
    public var glass: LauncherGlass
    public var ambient: LauncherAmbient
    /// 主题卡片用的三色色板
    public var swatch: [Color]

    public var isDark: Bool { scheme == .dark }

    public var primaryGradient: LinearGradient {
        LinearGradient(colors: [colors.accent, colors.accentAlt], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public init(
        id: String,
        name: String,
        tagline: String,
        scheme: ColorScheme,
        colors: LauncherColors,
        glass: LauncherGlass,
        ambient: LauncherAmbient,
        swatch: [Color]
    ) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.scheme = scheme
        self.colors = colors
        self.glass = glass
        self.ambient = ambient
        self.swatch = swatch
    }
}

// MARK: - 主题工厂

public extension LauncherTheme {
    /// 深色主题工厂：统一推导 surface / stroke / 阴影，保证多主题视觉一致。
    static func dark(
        id: String,
        name: String,
        tagline: String,
        backdrop: [Color],
        glowPrimary: Color,
        glowSecondary: Color,
        accent: Color,
        accentAlt: Color,
        onAccent: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        success: Color = Color(hex: 0x4ADE80),
        warning: Color = Color(hex: 0xFBBF24),
        danger: Color = Color(hex: 0xF87171),
        glassMaterial: LauncherMaterial = .regular,
        gridOpacity: Double = 0.045
    ) -> LauncherTheme {
        let colors = LauncherColors(
            canvas: backdrop.first ?? Color(hex: 0x0B1210),
            surface: Color.white.opacity(0.065),
            surfaceElevated: Color.white.opacity(0.1),
            surfaceSubtle: Color.black.opacity(0.22),
            surfaceHover: Color.white.opacity(0.1),
            surfaceActive: Color.white.opacity(0.14),
            stroke: Color.white.opacity(0.1),
            strokeStrong: Color.white.opacity(0.2),
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textTertiary: textTertiary,
            accent: accent,
            accentAlt: accentAlt,
            onAccent: onAccent,
            accentSoft: accent.opacity(0.16),
            success: success,
            warning: warning,
            danger: danger,
            onDanger: Color(hex: 0x2A0A0A),
            focusRing: accent.opacity(0.85),
            shadow: Color.black.opacity(0.45)
        )
        let glass = LauncherGlass(
            material: glassMaterial,
            tint: Color.white,
            tintOpacity: 0.05,
            highlightOpacity: 0.16,
            shadowRadius: 22,
            shadowY: 12
        )
        let ambient = LauncherAmbient(
            gradient: backdrop,
            glowPrimary: glowPrimary,
            glowSecondary: glowSecondary,
            gridOpacity: gridOpacity,
            vignetteOpacity: 0.5
        )
        return LauncherTheme(
            id: id, name: name, tagline: tagline, scheme: .dark,
            colors: colors, glass: glass, ambient: ambient,
            swatch: [backdrop.last ?? .black, accent, accentAlt]
        )
    }

    /// 浅色主题工厂。
    static func light(
        id: String,
        name: String,
        tagline: String,
        backdrop: [Color],
        glowPrimary: Color,
        glowSecondary: Color,
        accent: Color,
        accentAlt: Color,
        onAccent: Color = .white,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        success: Color = Color(hex: 0x059669),
        warning: Color = Color(hex: 0xB45309),
        danger: Color = Color(hex: 0xDC2626),
        glassMaterial: LauncherMaterial = .regular,
        gridOpacity: Double = 0.03
    ) -> LauncherTheme {
        let colors = LauncherColors(
            canvas: backdrop.first ?? Color(hex: 0xF5F8FF),
            surface: Color.white.opacity(0.55),
            surfaceElevated: Color.white.opacity(0.72),
            surfaceSubtle: Color.black.opacity(0.045),
            surfaceHover: Color.white.opacity(0.8),
            surfaceActive: Color.white.opacity(0.9),
            stroke: Color.black.opacity(0.08),
            strokeStrong: Color.black.opacity(0.16),
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textTertiary: textTertiary,
            accent: accent,
            accentAlt: accentAlt,
            onAccent: onAccent,
            accentSoft: accent.opacity(0.12),
            success: success,
            warning: warning,
            danger: danger,
            onDanger: Color.white,
            focusRing: accent.opacity(0.8),
            shadow: Color.black.opacity(0.12)
        )
        let glass = LauncherGlass(
            material: glassMaterial,
            tint: Color.white,
            tintOpacity: 0.32,
            highlightOpacity: 0.6,
            shadowRadius: 18,
            shadowY: 10
        )
        let ambient = LauncherAmbient(
            gradient: backdrop,
            glowPrimary: glowPrimary,
            glowSecondary: glowSecondary,
            gridOpacity: gridOpacity,
            vignetteOpacity: 0.12
        )
        return LauncherTheme(
            id: id, name: name, tagline: tagline, scheme: .light,
            colors: colors, glass: glass, ambient: ambient,
            swatch: [accent, accentAlt, backdrop.last ?? .white]
        )
    }
}
