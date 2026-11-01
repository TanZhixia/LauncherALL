import SwiftUI

// MARK: - 公开类型

/// 徽标 / 状态色调：语义化映射到主题色，组件内部不出现任何具体色值。
public enum LauncherBadgeTone {
    case neutral
    case accent
    case success
    case warning
    case danger
    case info
}

// MARK: - 色调映射

private extension LauncherBadgeTone {
    /// 该色调对应的主题前景色。
    func color(in theme: LauncherTheme) -> Color {
        switch self {
        case .neutral: return theme.colors.textSecondary
        case .accent: return theme.colors.accent
        case .success: return theme.colors.success
        case .warning: return theme.colors.warning
        case .danger: return theme.colors.danger
        case .info: return theme.colors.accentAlt
        }
    }

    /// 该色调对应的柔和底色：neutral 用表面色，其余用 14% 透明度的同色底。
    func backgroundColor(in theme: LauncherTheme) -> Color {
        switch self {
        case .neutral: return theme.colors.surfaceHover
        case .accent, .success, .warning, .danger, .info:
            return color(in: theme).opacity(0.14)
        }
    }
}

/// 过滤器 Chip 的固定高度（契约 2.2 规定 26pt）。
private let launcherChipHeight: CGFloat = LauncherControl.small - LauncherSpace.xxs

/// 状态点直径（契约 2.2 规定 6pt）。
private let launcherStatusDotSize: CGFloat = LauncherSpace.xs + LauncherSpace.xxs

/// 循环呼吸动画时长（循环动画不属于 120–320ms 交互过渡刻度，故单独定义）。
private enum LauncherStatusTiming {
    static let pulse: Double = 1.8
}

// MARK: - Chip

/// 可点选的胶囊过滤标签：选中态用主题强调色，未选中保持中性。
public struct LauncherChip: View {
    @Environment(\.launcherTheme) private var theme
    @State private var isHovering = false

    private let title: String
    private let isSelected: Bool
    private let systemImage: String?
    private let action: () -> Void

    public init(
        _ title: String,
        isSelected: Bool = false,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: LauncherSpace.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        // 先定色再套 textStyle：textStyle 内置语义色会盖掉外层颜色。
                        .foregroundStyle(foregroundColor)
                        .textStyle(.caption)
                }
                Text(title)
                    .foregroundStyle(foregroundColor)
                    .textStyle(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, LauncherSpace.md)
            .frame(height: launcherChipHeight)
            .background {
                Capsule().fill(backgroundColor)
            }
            .overlay {
                Capsule().strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(LauncherPressEffect(scale: 0.975))
        .onHover { isHovering = $0 }
        .launcherAnimation(LauncherMotion.smooth, value: isHovering)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foregroundColor: Color {
        if isSelected { return theme.colors.accent }
        return isHovering ? theme.colors.textPrimary : theme.colors.textSecondary
    }

    private var backgroundColor: Color {
        if isSelected { return theme.colors.accentSoft }
        return isHovering ? theme.colors.surfaceHover : theme.colors.surface
    }

    /// 选中态用强调描边；未选中态保留 1px 细描边，保证浅色主题下胶囊边界清晰。
    private var borderColor: Color {
        if isSelected { return theme.colors.accent }
        return isHovering ? theme.colors.strokeStrong : theme.colors.stroke
    }
}

// MARK: - Badge

/// 只读徽标：胶囊底 + 同色文字，用于版本号、实例标签等短信息。
public struct LauncherBadge: View {
    @Environment(\.launcherTheme) private var theme

    private let text: String
    private let tone: LauncherBadgeTone
    private let systemImage: String?

    public init(
        _ text: String,
        tone: LauncherBadgeTone = .neutral,
        systemImage: String? = nil
    ) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: LauncherSpace.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(tone.color(in: theme))
                    .textStyle(.micro)
            }
            Text(text)
                .foregroundStyle(tone.color(in: theme))
                .textStyle(.micro)
                .lineLimit(1)
        }
        .padding(.horizontal, LauncherSpace.sm)
        .padding(.vertical, LauncherSpace.xxs)
        .background {
            Capsule().fill(tone.backgroundColor(in: theme))
        }
        .accessibilityLabel(Text(text))
    }
}

// MARK: - StatusDot

/// 状态圆点：可呼吸脉冲（减弱动效时自动降级为静态圆点）。
public struct LauncherStatusDot: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private let tone: LauncherBadgeTone
    private let isPulsing: Bool

    public init(tone: LauncherBadgeTone = .success, isPulsing: Bool = false) {
        self.tone = tone
        self.isPulsing = isPulsing
    }

    public var body: some View {
        ZStack {
            if isPulsing && !reduceMotion {
                Circle()
                    .fill(tone.color(in: theme).opacity(0.45))
                    .frame(width: launcherStatusDotSize, height: launcherStatusDotSize)
                    .scaleEffect(pulsing ? 2.6 : 1)
                    .opacity(pulsing ? 0 : 0.9)
            }
            Circle()
                .fill(tone.color(in: theme))
                .frame(width: launcherStatusDotSize, height: launcherStatusDotSize)
                .shadow(color: tone.color(in: theme).opacity(0.45), radius: LauncherSpace.xxs, x: 0, y: 0)
        }
        .frame(width: launcherStatusDotSize, height: launcherStatusDotSize)
        .onAppear(perform: startPulseIfNeeded)
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                // 关闭呼吸动画时把状态复位，避免下次开启动画时停在不可见帧。
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { pulsing = false }
            } else {
                startPulseIfNeeded()
            }
        }
        .accessibilityHidden(true)
    }

    private func startPulseIfNeeded() {
        guard isPulsing, !reduceMotion, !pulsing else { return }
        withAnimation(.easeOut(duration: LauncherStatusTiming.pulse).repeatForever(autoreverses: false)) {
            pulsing = true
        }
    }
}
