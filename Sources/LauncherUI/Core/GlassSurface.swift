import SwiftUI
import AppKit

// MARK: - 背景

/// 全窗口背景：纯色画布。平面化风格不做氛围光、网格与暗角。
public struct LauncherAppBackground: View {
    @Environment(\.launcherTheme) private var theme

    public init() {}

    public var body: some View {
        theme.colors.canvas.ignoresSafeArea()
    }
}

// MARK: - 面板

/// 面板容器：靠「分层底色 + 1px 边框」表达层级，不使用模糊/投影/发光。
public struct GlassPanel<Content: View>: View {
    @Environment(\.launcherTheme) private var theme
    private let level: GlassLevel
    private let cornerRadius: CGFloat
    private let padding: CGFloat?
    private let content: () -> Content

    public init(
        level: GlassLevel = .regular,
        cornerRadius: CGFloat = LauncherRadius.lg,
        padding: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.level = level
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding ?? 0)
            .background { LauncherGlassBackground(level: level, cornerRadius: cornerRadius) }
    }
}

/// 面板底：平面化实现（纯色填充 + 1px 边框），离屏渲染与真机完全一致。
/// 名称保留 `LauncherGlassBackground` 以兼容既有组件调用。
public struct LauncherGlassBackground: View {
    @Environment(\.launcherTheme) private var theme

    private let level: GlassLevel
    private let cornerRadius: CGFloat

    public init(level: GlassLevel = .regular, cornerRadius: CGFloat = LauncherRadius.lg) {
        self.level = level
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(fill)
            .overlay(shape.strokeBorder(border, lineWidth: 1))
    }

    private var fill: Color {
        switch level {
        case .subtle: return theme.colors.surfaceSubtle
        case .regular: return theme.colors.surface
        case .strong: return theme.colors.surfaceElevated
        }
    }

    private var border: Color {
        switch level {
        case .subtle: return theme.colors.stroke
        case .regular: return theme.colors.stroke
        case .strong: return theme.colors.strokeStrong
        }
    }
}

public extension View {
    /// 给任意视图加面板底（平面化：纯色 + 1px 边框）。
    func glassBackground(
        level: GlassLevel = .regular,
        cornerRadius: CGFloat = LauncherRadius.lg
    ) -> some View {
        background { LauncherGlassBackground(level: level, cornerRadius: cornerRadius) }
    }

    /// 焦点环（键盘导航可见性）。
    func launcherFocusRing(_ isFocused: Bool, cornerRadius: CGFloat = LauncherRadius.md) -> some View {
        modifier(LauncherFocusRingModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}

private struct LauncherFocusRingModifier: ViewModifier {
    @Environment(\.launcherTheme) private var theme
    let isFocused: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(theme.colors.focusRing, lineWidth: isFocused ? 2 : 0)
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}
