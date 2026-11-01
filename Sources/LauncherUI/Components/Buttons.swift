import SwiftUI

// MARK: - 公开类型

/// 按钮视觉变体：primary 用强调色承担主操作，secondary / ghost 保持克制，danger 表示破坏性操作。
public enum LauncherButtonVariant {
    case primary
    case secondary
    case ghost
    case danger
}

/// 按钮尺寸：高度、内边距、字号、圆角全部取自契约 2.1 的固定刻度。
public enum LauncherButtonSize {
    case small
    case medium
    case large
}

// MARK: - 刻度映射（契约 2.1）

private extension LauncherButtonSize {
    /// 控件高度：28 / 34 / 44。
    var height: CGFloat {
        switch self {
        case .small: return LauncherControl.small
        case .medium: return LauncherControl.medium
        case .large: return LauncherControl.large
        }
    }

    /// 水平内边距：10 / 16 / 22（10 与 22 由间距刻度组合得到，保持全部来源于令牌）。
    var horizontalPadding: CGFloat {
        switch self {
        case .small: return LauncherSpace.sm + LauncherSpace.xxs                       // 8 + 2 = 10
        case .medium: return LauncherSpace.lg                                          // 16
        case .large: return LauncherSpace.lg + LauncherSpace.sm - LauncherSpace.xxs     // 16 + 8 - 2 = 22
        }
    }

    /// 文字角色：caption / bodyStrong / headline。
    var textRole: LauncherTextStyle {
        switch self {
        case .small: return .caption
        case .medium: return .bodyStrong
        case .large: return .headline
        }
    }

    /// 纯图标按钮的字形角色：图标随尺寸略放大，保证方形点击目标内的视觉重量。
    var iconRole: LauncherTextStyle {
        switch self {
        case .small: return .caption
        case .medium: return .sectionTitle
        case .large: return .title
        }
    }

    /// 圆角：small 用 sm，medium / large 用 md。
    var cornerRadius: CGFloat {
        switch self {
        case .small: return LauncherRadius.sm
        case .medium, .large: return LauncherRadius.md
        }
    }

    /// 图标与文字之间的间距。
    var contentSpacing: CGFloat {
        switch self {
        case .small: return LauncherSpace.xs
        case .medium, .large: return LauncherSpace.sm
        }
    }
}

// MARK: - 按钮底层

/// 按钮底层：按变体绘制纯色填充 / 表面 / 描边，平面化不做高光与投影。
private struct LauncherButtonSurface: View {
    @Environment(\.launcherTheme) private var theme

    let variant: LauncherButtonVariant
    let cornerRadius: CGFloat
    let isHovering: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            fill
            border
        }
        .compositingGroup()
    }

    @ViewBuilder
    private var fill: some View {
        switch variant {
        case .primary:
            shape.fill(theme.colors.accent)
                .brightness(isHovering ? 0.05 : 0)
        case .secondary:
            shape.fill(isHovering ? theme.colors.surfaceHover : theme.colors.surface)
        case .ghost:
            shape.fill(isHovering ? theme.colors.surfaceHover : Color.clear)
        case .danger:
            shape.fill(theme.colors.danger)
                .brightness(isHovering ? 0.05 : 0)
        }
    }

    @ViewBuilder
    private var border: some View {
        switch variant {
        case .secondary:
            shape.strokeBorder(
                isHovering ? theme.colors.strokeStrong : theme.colors.stroke,
                lineWidth: 1
            )
        case .primary, .ghost, .danger:
            EmptyView()
        }
    }

}

// MARK: - 文字按钮

/// 主按钮：支持四种变体、三种尺寸、加载 / 禁用 / 全宽 / 快捷键提示。
public struct LauncherButton: View {
    @Environment(\.launcherTheme) private var theme
    @State private var isHovering = false

    private let title: String
    private let systemImage: String?
    private let variant: LauncherButtonVariant
    private let size: LauncherButtonSize
    private let isLoading: Bool
    private let isFullWidth: Bool
    private let isDisabled: Bool
    private let shortcut: String?
    private let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        variant: LauncherButtonVariant = .primary,
        size: LauncherButtonSize = .medium,
        isLoading: Bool = false,
        isFullWidth: Bool = false,
        isDisabled: Bool = false,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.size = size
        self.isLoading = isLoading
        self.isFullWidth = isFullWidth
        self.isDisabled = isDisabled
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: performAction) {
            labelContent
        }
        .buttonStyle(LauncherPressEffect(scale: 0.975))
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.45 : 1)
        .onHover { hovering in
            guard !isDisabled, !isLoading else {
                isHovering = false
                return
            }
            isHovering = hovering
        }
        .launcherAnimation(LauncherMotion.smooth, value: isHovering)
        .launcherAnimation(LauncherMotion.smooth, value: isDisabled)
        .accessibilityLabel(Text(title))
    }

    // MARK: 内容

    private var labelContent: some View {
        HStack(spacing: size.contentSpacing) {
            if isFullWidth {
                Spacer(minLength: 0)
            }
            leadingGlyph
            Text(title)
                // 先定色再套 textStyle：textStyle 内置的语义色作用于最内层，会盖掉外层颜色。
                .foregroundStyle(foregroundColor)
                .textStyle(size.textRole)
                .lineLimit(1)
            if let shortcut {
                if isFullWidth {
                    Spacer(minLength: 0)
                }
                shortcutLabel(shortcut)
            } else if isFullWidth {
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, size.horizontalPadding)
        .padding(.trailing, trailingPadding)
        .frame(height: size.height)
        .frame(maxWidth: isFullWidth ? CGFloat.infinity : nil)
        // 非全宽按钮保持自身理想宽度：避免放在 HStack + Spacer 里被压窄导致标题截断
        .fixedSize(horizontal: !isFullWidth, vertical: false)
        .background {
            LauncherButtonSurface(variant: variant, cornerRadius: size.cornerRadius, isHovering: isHovering)
        }
        .contentShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
    }

    /// 占位字形：加载中显示自绘小圆环，否则显示图标。
    @ViewBuilder
    private var leadingGlyph: some View {
        if isLoading {
            LauncherButtonLoadingIndicator(color: foregroundColor)
        } else if let systemImage {
            Image(systemName: systemImage)
                .foregroundStyle(foregroundColor)
                .textStyle(size.textRole)
        }
    }

    /// 右侧快捷键提示：垂直居中跟在标题之后，与标题至少隔 LauncherSpace.sm，不改变按钮高度。
    private func shortcutLabel(_ shortcut: String) -> some View {
        Text(shortcut)
            .foregroundStyle(foregroundColor.opacity(0.7))
            .textStyle(.monoSmall)
            .padding(.leading, LauncherSpace.sm)
            .allowsHitTesting(false)
    }

    /// 全宽按钮带快捷键时右侧只留 LauncherSpace.md，让提示贴近最右侧且不压到标题。
    private var trailingPadding: CGFloat {
        if isFullWidth && shortcut != nil {
            return LauncherSpace.md
        }
        return size.horizontalPadding
    }

    /// 各变体的前景色：均来自主题语义色，浅色主题下也不会出现白字白底。
    private var foregroundColor: Color {
        switch variant {
        case .primary: return theme.colors.onAccent
        case .secondary: return theme.colors.textPrimary
        case .ghost: return isHovering ? theme.colors.textPrimary : theme.colors.textSecondary
        case .danger: return theme.colors.onDanger
        }
    }

    private func performAction() {
        guard !isDisabled, !isLoading else { return }
        action()
    }
}

// MARK: - 图标按钮

/// 纯图标按钮：方形点击目标，必须提供无障碍标签（同时用作 tooltip）。
public struct LauncherIconButton: View {
    @Environment(\.launcherTheme) private var theme
    @State private var isHovering = false

    private let systemImage: String
    private let variant: LauncherButtonVariant
    private let size: LauncherButtonSize
    private let accessibilityLabel: String
    private let isDisabled: Bool
    private let action: () -> Void

    public init(
        systemImage: String,
        variant: LauncherButtonVariant = .ghost,
        size: LauncherButtonSize = .medium,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.variant = variant
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: performAction) {
            Image(systemName: systemImage)
                .foregroundStyle(foregroundColor)
                .textStyle(size.iconRole)
                .frame(width: side, height: side)
                .background {
                    LauncherButtonSurface(variant: variant, cornerRadius: size.cornerRadius, isHovering: isHovering)
                }
                .contentShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
        }
        .buttonStyle(LauncherPressEffect(scale: 0.975))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .onHover { hovering in
            guard !isDisabled else {
                isHovering = false
                return
            }
            isHovering = hovering
        }
        .launcherAnimation(LauncherMotion.smooth, value: isHovering)
        .launcherAnimation(LauncherMotion.smooth, value: isDisabled)
        .accessibilityLabel(Text(accessibilityLabel))
        .help(accessibilityLabel)
    }

    private var side: CGFloat { size.height }

    private var foregroundColor: Color {
        switch variant {
        case .primary: return theme.colors.onAccent
        case .secondary: return theme.colors.textPrimary
        case .ghost: return isHovering ? theme.colors.textPrimary : theme.colors.textSecondary
        case .danger: return theme.colors.onDanger
        }
    }

    private func performAction() {
        guard !isDisabled else { return }
        action()
    }
}

// MARK: - 加载指示器

/// 加载指示器的旋转周期（循环动画，不属于 120–320ms 的交互过渡刻度）。
private enum LauncherButtonTiming {
    static let spin: Double = 0.9
}

/// 按钮内加载指示器：自绘小圆环，颜色跟随当前变体前景色。
/// 不使用系统 ProgressView —— 它在离屏渲染与深浅主题下颜色不可控。
private struct LauncherButtonLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    private let color: Color
    private let size: CGFloat

    init(color: Color, size: CGFloat = 12) {
        self.color = color
        self.size = size
    }

    private var lineWidth: CGFloat {
        max(LauncherSpace.xxs, size * 0.14)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0.08, to: 0.82)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.05), color], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(rotating ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear(perform: startRotationIfNeeded)
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { rotating = false }
            } else {
                startRotationIfNeeded()
            }
        }
        .accessibilityHidden(true)
    }

    private func startRotationIfNeeded() {
        guard !reduceMotion, !rotating else { return }
        withAnimation(.linear(duration: LauncherButtonTiming.spin).repeatForever(autoreverses: false)) {
            rotating = true
        }
    }
}
