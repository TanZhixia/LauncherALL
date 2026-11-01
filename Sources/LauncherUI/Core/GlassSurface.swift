import SwiftUI
import AppKit

// MARK: - 氛围背景

/// 全窗口背景：主题渐变 + 双氛围光 + 像素网格 + 暗角。
/// 所有页面共用，保证切主题时整体氛围一致。
public struct LauncherAmbientBackground: View {
    @Environment(\.launcherTheme) private var theme

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: theme.ambient.gradient, startPoint: .top, endPoint: .bottom)

                RadialGradient(
                    colors: [theme.ambient.glowPrimary.opacity(theme.isDark ? 0.34 : 0.22), .clear],
                    center: UnitPoint(x: 0.1, y: 0.02),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.72
                )

                RadialGradient(
                    colors: [theme.ambient.glowSecondary.opacity(theme.isDark ? 0.26 : 0.16), .clear],
                    center: UnitPoint(x: 0.92, y: 0.94),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.8
                )

                if theme.ambient.gridOpacity > 0 {
                    LauncherPixelGrid(opacity: theme.ambient.gridOpacity, isDark: theme.isDark)
                        .blendMode(.plusLighter)
                }

                RadialGradient(
                    colors: [.clear, Color.black.opacity(theme.ambient.vignetteOpacity)],
                    center: .center,
                    startRadius: min(size.width, size.height) * 0.35,
                    endRadius: max(size.width, size.height) * 0.92
                )
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
    }
}

/// 44pt 方块网格，向 Minecraft 的方块世界致意（很淡）。
public struct LauncherPixelGrid: View {
    private let opacity: Double
    private let isDark: Bool

    public init(opacity: Double, isDark: Bool) {
        self.opacity = opacity
        self.isDark = isDark
    }

    public var body: some View {
        Canvas { context, size in
            let step: CGFloat = 44
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(
                path,
                with: .color((isDark ? Color.white : Color.black).opacity(opacity)),
                lineWidth: 0.6
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 玻璃面板

/// 玻璃容器：全局统一层级（subtle / regular / strong）。
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

/// 玻璃底层：材质 + 主题着色 + 高光 + 描边 + 阴影。
public struct LauncherGlassBackground: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    private let level: GlassLevel
    private let cornerRadius: CGFloat

    public init(level: GlassLevel = .regular, cornerRadius: CGFloat = LauncherRadius.lg) {
        self.level = level
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let tintAlpha = theme.glass.tintOpacity * level.tintMultiplier
        let highlight = theme.glass.highlightOpacity * level.strokeMultiplier * 0.5

        ZStack {
            shape
                .fill(snapshotMode ? AnyShapeStyle(snapshotFill) : AnyShapeStyle(theme.glass.material.material))
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [
                                theme.glass.tint.opacity(tintAlpha * 1.5),
                                theme.glass.tint.opacity(tintAlpha * 0.55)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                theme.colors.stroke.opacity(1.25 * level.strokeMultiplier),
                                theme.colors.stroke.opacity(0.55)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(highlight), .clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: theme.colors.shadow.opacity(level.shadowMultiplier * 0.9),
                    radius: theme.glass.shadowRadius * level.shadowMultiplier,
                    x: 0,
                    y: theme.glass.shadowY * level.shadowMultiplier
                )
        }
    }

    /// 近似 Material 的令牌色（离屏渲染用，避免出现写死灰白）
    private var snapshotFill: Color {
        let base: Color = theme.isDark ? Color.white : Color.white
        let alpha: Double = theme.isDark
            ? 0.055 * level.tintMultiplier + theme.glass.tintOpacity * 0.5
            : 0.30 * level.tintMultiplier + 0.14
        return base.opacity(min(alpha, 0.92))
    }
}

public extension View {
    /// 给任意视图加玻璃底。
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
