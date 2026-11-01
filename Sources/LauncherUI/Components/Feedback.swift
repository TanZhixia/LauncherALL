import SwiftUI

// MARK: - 公开类型

/// 进度语义色调：accent 使用强调色，其余为对应语义色。
public enum LauncherProgressTone {
    case accent
    case success
    case warning
    case danger
}

/// 提示语义色调（Banner 与 Toast 共用）。
public enum LauncherBannerTone {
    case info
    case success
    case warning
    case danger
}

// MARK: - 循环动效时长

/// 循环类动画（扫光 / 呼吸 / 旋转）不属于 120–320ms 的交互过渡刻度，故单独定义。
private enum LauncherFeedbackTiming {
    static let sweep: Double = 1.4
    static let shimmer: Double = 1.6
    static let spin: Double = 0.9
}

/// Banner / Toast 左侧状态竖条宽度（契约 2.3 规定 3pt）。
private let launcherAccentBarWidth: CGFloat = 3

// MARK: - 色调 / 图标映射

private extension LauncherProgressTone {
    /// 该进度色调对应的主题色。
    func color(in theme: LauncherTheme) -> Color {
        switch self {
        case .accent: return theme.colors.accent
        case .success: return theme.colors.success
        case .warning: return theme.colors.warning
        case .danger: return theme.colors.danger
        }
    }
}

private extension LauncherBannerTone {
    /// 该提示色调对应的主题色。
    func color(in theme: LauncherTheme) -> Color {
        switch self {
        case .info: return theme.colors.accentAlt
        case .success: return theme.colors.success
        case .warning: return theme.colors.warning
        case .danger: return theme.colors.danger
        }
    }

    /// 契约 2.3 规定的 SF Symbol。
    var systemImage: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        }
    }
}

// MARK: - 进度条

/// 进度条：值驱动或不确定（循环光带），支持标签与百分比。
public struct LauncherProgressBar: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeping = false

    private let value: Double?
    private let label: String?
    private let tone: LauncherProgressTone
    private let height: CGFloat

    public init(
        value: Double? = nil,
        label: String? = nil,
        tone: LauncherProgressTone = .accent,
        height: CGFloat = 6
    ) {
        self.value = value
        self.label = label
        self.tone = tone
        self.height = height
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            if label != nil || value != nil {
                header
            }
            track
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label ?? "进度"))
        .accessibilityValue(Text(accessibilityValueText))
    }

    /// 进度归一化到 0...1，未提供值时按 0 处理。
    private var clamped: Double {
        guard let value else { return 0 }
        return min(1, max(0, value))
    }

    private var accessibilityValueText: String {
        guard value != nil else { return "进行中" }
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// 标签行：左侧 caption 文案，右侧等宽百分比。
    private var header: some View {
        HStack(spacing: LauncherSpace.sm) {
            if let label {
                Text(label).textStyle(.caption, tone: .secondary)
            }
            Spacer(minLength: LauncherSpace.sm)
            LauncherMonoText(value == nil ? "—" : "\(Int((clamped * 100).rounded()))%", tone: .secondary)
        }
    }

    /// 轨道 + 填充，整体裁成胶囊端。
    private var track: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 0)
            ZStack(alignment: .leading) {
                Capsule().fill(theme.colors.surfaceSubtle)
                if value != nil {
                    Capsule()
                        .fill(fillStyle)
                        .frame(width: max(0, width * clamped))
                        .launcherAnimation(LauncherMotion.smooth, value: clamped)
                } else if reduceMotion {
                    // 减弱动效：静态降级为一段固定长度的进度示意。
                    Capsule()
                        .fill(fillStyle)
                        .frame(width: max(0, width * 0.32))
                        .opacity(0.65)
                } else {
                    sweepingBand(width: width)
                }
            }
            // 光带条带比轨道宽，用固定尺寸 + 胶囊裁切把它限制在轨道内。
            .frame(width: width, height: height, alignment: .leading)
            .clipShape(Capsule())
        }
        .frame(height: height)
    }

    /// 填充样式：accent 用强调色，其余用语义色。
    private var fillStyle: AnyShapeStyle {
        switch tone {
        case .accent: return AnyShapeStyle(theme.colors.accent)
        case .success, .warning, .danger: return AnyShapeStyle(tone.color(in: theme))
        }
    }

    /// 不确定进度：循环光带从左向右扫过。
    /// 用「以轨道宽度为周期」的两条光带做首尾相接的循环：offset 在 0 与 -period 之间滑动，
    /// 两端视觉完全一致，因此离屏截图/静止帧里也始终能看到一条光带。
    private func sweepingBand(width: CGFloat) -> some View {
        let bandWidth = max(width * 0.32, height * 4)
        let gap = max(width - bandWidth, 0)
        let period = bandWidth + gap
        return HStack(spacing: gap) {
            bandShape(width: bandWidth)
            bandShape(width: bandWidth)
        }
        .frame(width: period * 2, alignment: .leading)
        .offset(x: sweeping ? -period : 0)
        .onAppear(perform: startSweepIfNeeded)
    }

    private func bandShape(width: CGFloat) -> some View {
        Capsule()
            .fill(bandGradient)
            .frame(width: width, height: height)
    }

    private var bandGradient: LinearGradient {
        switch tone {
        case .accent:
            return LinearGradient(
                colors: [
                    theme.colors.accent.opacity(0),
                    theme.colors.accent,
                    theme.colors.accentAlt,
                    theme.colors.accentAlt.opacity(0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .success, .warning, .danger:
            let color = tone.color(in: theme)
            return LinearGradient(
                colors: [color.opacity(0), color, color.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private func startSweepIfNeeded() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: LauncherFeedbackTiming.sweep).repeatForever(autoreverses: false)) {
            sweeping = true
        }
    }
}

// MARK: - Spinner

/// 环形加载指示器：单色渐变环旋转（同色相透明度过渡），减弱动效时降级为静态环。
public struct LauncherSpinner: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    private let size: CGFloat
    private let tone: LauncherProgressTone

    public init(size: CGFloat = 16, tone: LauncherProgressTone = .accent) {
        self.size = size
        self.tone = tone
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(theme.colors.surfaceActive, lineWidth: lineWidth)
            Circle()
                .trim(from: 0.06, to: 0.86)
                .stroke(spinGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(rotating ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear(perform: startRotationIfNeeded)
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                stopRotation()
            } else {
                startRotationIfNeeded()
            }
        }
        .accessibilityLabel(Text("加载中"))
    }

    private var lineWidth: CGFloat {
        max(LauncherSpace.xxs, size * 0.12)
    }

    private var spinGradient: AngularGradient {
        switch tone {
        case .accent:
            return AngularGradient(
                colors: [theme.colors.accent.opacity(0.06), theme.colors.accent, theme.colors.accentAlt],
                center: .center
            )
        case .success, .warning, .danger:
            let color = tone.color(in: theme)
            return AngularGradient(colors: [color.opacity(0.06), color], center: .center)
        }
    }

    private func startRotationIfNeeded() {
        guard !reduceMotion, !rotating else { return }
        withAnimation(.linear(duration: LauncherFeedbackTiming.spin).repeatForever(autoreverses: false)) {
            rotating = true
        }
    }

    private func stopRotation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { rotating = false }
    }
}

// MARK: - Skeleton

/// 骨架占位：表面底 + 从左到右的扫光，减弱动效时保持静态。
public struct LauncherSkeleton: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmering = false

    private let width: CGFloat?
    private let height: CGFloat
    private let cornerRadius: CGFloat

    public init(width: CGFloat? = nil, height: CGFloat = 12, cornerRadius: CGFloat = LauncherRadius.sm) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        shape
            .fill(theme.colors.surfaceActive)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        shimmerLayer(in: proxy.size)
                    }
                }
            }
            .clipShape(shape)
            .frame(maxWidth: .infinity)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// 扫光色取自 textPrimary：深色主题近白、浅色主题近黑，两种主题下都清晰可见。
    private var sheenColor: Color {
        theme.colors.textPrimary.opacity(theme.isDark ? 0.16 : 0.07)
    }

    private func shimmerLayer(in container: CGSize) -> some View {
        let bandWidth = max(container.width * 0.55, height * 3)
        return LinearGradient(
            colors: [.clear, sheenColor, .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: bandWidth, height: container.height)
        .offset(x: shimmering ? container.width : -bandWidth)
        .onAppear(perform: startShimmerIfNeeded)
    }

    private func startShimmerIfNeeded() {
        guard !reduceMotion, !shimmering else { return }
        withAnimation(.linear(duration: LauncherFeedbackTiming.shimmer).repeatForever(autoreverses: false)) {
            shimmering = true
        }
    }
}

// MARK: - Banner

/// 行内提示条：面板底 + 左侧语义色竖条 + 状态图标 + 可选操作按钮。
public struct LauncherBanner: View {
    @Environment(\.launcherTheme) private var theme

    private let title: String
    private let message: String
    private let tone: LauncherBannerTone
    private let actionTitle: String?
    private let onAction: (() -> Void)?

    public init(
        title: String,
        message: String,
        tone: LauncherBannerTone = .info,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.tone = tone
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    public var body: some View {
        HStack(alignment: .top, spacing: LauncherSpace.md) {
            Image(systemName: tone.systemImage)
                // 先定色再套 textStyle：textStyle 内置语义色会盖掉外层颜色。
                .foregroundStyle(tone.color(in: theme))
                .textStyle(.sectionTitle)
                .padding(.top, LauncherSpace.xxs)

            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text(title).textStyle(.bodyStrong)
                if !message.isEmpty {
                    Text(message)
                        .textStyle(.caption, tone: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: LauncherSpace.md)

            if let actionTitle, let onAction {
                LauncherButton(actionTitle, variant: .secondary, size: .small, action: onAction)
            }
        }
        .padding(.leading, LauncherSpace.md + launcherAccentBarWidth + LauncherSpace.sm)
        .padding(.vertical, LauncherSpace.md)
        .padding(.trailing, LauncherSpace.md)
        .glassBackground(level: .regular, cornerRadius: LauncherRadius.md)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tone.color(in: theme))
                .frame(width: launcherAccentBarWidth)
                .padding(.leading, LauncherSpace.sm)
                .padding(.vertical, LauncherSpace.sm)
        }
    }
}

// MARK: - Toast

/// 浮层轻提示：浮层面板 + 状态图标 + 标题正文 + 关闭按钮。
public struct LauncherToast: View {
    @Environment(\.launcherTheme) private var theme

    private let title: String
    private let message: String
    private let tone: LauncherBannerTone
    private let onDismiss: (() -> Void)?

    public init(
        title: String,
        message: String,
        tone: LauncherBannerTone = .success,
        onDismiss: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.tone = tone
        self.onDismiss = onDismiss
    }

    public var body: some View {
        GlassPanel(level: .strong, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.lg) {
            HStack(alignment: .top, spacing: LauncherSpace.md) {
                Image(systemName: tone.systemImage)
                    .foregroundStyle(tone.color(in: theme))
                    .textStyle(.sectionTitle)
                    .padding(.top, LauncherSpace.xxs)

                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    Text(title).textStyle(.bodyStrong)
                    if !message.isEmpty {
                        Text(message)
                            .textStyle(.caption, tone: .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: LauncherSpace.sm)

                if let onDismiss {
                    LauncherIconButton(
                        systemImage: "xmark",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: "关闭",
                        action: onDismiss
                    )
                }
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
    }
}
