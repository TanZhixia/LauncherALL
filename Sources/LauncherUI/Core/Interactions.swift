import SwiftUI
import AppKit

// MARK: - 指针 / 悬停 / 按压

/// 可点击元素统一的手型光标。
public struct LauncherPointerOnHover: ViewModifier {
    @State private var inside = false

    public func body(content: Content) -> some View {
        content
            .onHover { hovering in
                inside = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .onDisappear { NSCursor.arrow.set() }
    }
}

/// 卡片/列表项统一 hover 反馈：轻微提亮 + 上浮。
public struct LauncherHoverEffect: ViewModifier {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private let scale: CGFloat
    private let applyCursor: Bool

    public init(scale: CGFloat = 1.008, applyCursor: Bool = true) {
        self.scale = scale
        self.applyCursor = applyCursor
    }

    public func body(content: Content) -> some View {
        content
            .brightness(hovering ? 0.035 : 0)
            .scaleEffect(hovering && !reduceMotion ? scale : 1)
            .animation(LauncherMotion.smooth, value: hovering)
            .onHover { value in
                hovering = value
                if applyCursor {
                    if value { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
            }
            .onDisappear { if applyCursor { NSCursor.arrow.set() } }
    }
}

/// 点击缩放（服从“减弱动效”设置）。
public struct LauncherPressEffect: ButtonStyle {
    private let scale: CGFloat

    public init(scale: CGFloat = 0.975) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: LauncherMotion.fast), value: configuration.isPressed)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
    }
}

public extension View {
    func launcherPointer() -> some View { modifier(LauncherPointerOnHover()) }
    func launcherHoverEffect(scale: CGFloat = 1.008, applyCursor: Bool = true) -> some View {
        modifier(LauncherHoverEffect(scale: scale, applyCursor: applyCursor))
    }
    /// 监听“减弱动效”后自动置空的动画。
    func launcherAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(LauncherReducedMotionAnimation(animation: animation, value: value))
    }
}

private struct LauncherReducedMotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
