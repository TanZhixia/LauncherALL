import SwiftUI

/// 可折叠分组：标题行点击展开/收起，内容缩进显示。
public struct LauncherExpander<Content: View>: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let trailing: AnyView?
    private let content: () -> Content

    @State private var isExpanded: Bool

    public init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        isExpanded: Bool = false,
        trailing: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing
        self.content = content
        _isExpanded = State(initialValue: isExpanded)
    }

    private var expanded: Bool { snapshotMode ? true : isExpanded }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : LauncherMotion.spring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: LauncherSpace.sm) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.colors.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(width: 16)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(LauncherTextStyle.bodyStrong.font)
                            .foregroundStyle(theme.colors.textPrimary)
                        if let subtitle {
                            Text(subtitle)
                                .font(LauncherTextStyle.micro.font)
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let trailing { trailing }
                }
                .padding(.vertical, LauncherSpace.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .launcherPointer()

            if expanded {
                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    content()
                }
                .padding(.leading, 22)
                .padding(.top, LauncherSpace.xxs)
                .padding(.bottom, LauncherSpace.xs)
            }
        }
    }
}

/// 数字输入：中间等宽数字 + 两侧步进按钮，支持单位与范围。
public struct LauncherNumberField: View {
    @Environment(\.launcherTheme) private var theme

    private let label: String?
    private let unit: String?
    private let range: ClosedRange<Int>
    private let step: Int
    @Binding private var value: Int

    public init(
        _ label: String? = nil,
        value: Binding<Int>,
        range: ClosedRange<Int> = 0...Int.max,
        step: Int = 1,
        unit: String? = nil
    ) {
        self.label = label
        self.range = range
        self.step = step
        self.unit = unit
        _value = value
    }

    public var body: some View {
        HStack(spacing: LauncherSpace.xxs) {
            if let label {
                Text(label)
                    .font(LauncherTextStyle.caption.font)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            HStack(spacing: 0) {
                stepButton(systemImage: "minus") { value = max(range.lowerBound, value - step) }
                Text("\(value)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(minWidth: 44)
                    .multilineTextAlignment(.center)
                stepButton(systemImage: "plus") { value = min(range.upperBound, value + step) }
            }
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                    .strokeBorder(theme.colors.stroke, lineWidth: 1)
            }
            if let unit {
                Text(unit)
                    .font(LauncherTextStyle.micro.font)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }

    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .launcherPointer()
    }
}

public extension View {
    /// 悬停提示（原生 tooltip，离屏渲染时自动忽略）。
    func launcherTooltip(_ text: String) -> some View {
        help(text)
    }
}

// MARK: - 可折叠卡片（PCL MyCard 的折叠形态）

/// 整卡可折叠：收起时仅 40pt 标题条，展开后才渲染内容（懒加载）。
public struct LauncherCollapsibleCard<Content: View>: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let trailing: AnyView?
    private let content: () -> Content

    @State private var isExpanded: Bool
    @State private var hasRenderedContent = false

    public init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        isExpanded: Bool = true,
        trailing: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing
        self.content = content
        _isExpanded = State(initialValue: isExpanded)
        _hasRenderedContent = State(initialValue: isExpanded)
    }

    private var expanded: Bool { snapshotMode ? true : isExpanded }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : LauncherMotion.spring) {
                    isExpanded.toggle()
                    if isExpanded { hasRenderedContent = true }
                }
            } label: {
                HStack(spacing: LauncherSpace.sm) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(width: 16)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let trailing { trailing }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.colors.textTertiary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .padding(.horizontal, LauncherSpace.md)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .launcherPointer()

            if expanded, hasRenderedContent || snapshotMode {
                Rectangle()
                    .fill(theme.colors.stroke)
                    .frame(height: 1)
                content()
                    .padding(LauncherSpace.md)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.lg, style: .continuous)
                .fill(theme.colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.lg, style: .continuous)
                .strokeBorder(theme.colors.stroke, lineWidth: 1)
        }
    }
}

// MARK: - 行尾悬停操作组

/// 悬停才出现的紧凑图标操作组（PCL 行内 hover 按钮）。
public struct LauncherHoverActions: View {
    @Environment(\.launcherTheme) private var theme
    @State private var hovering = false

    public struct Action: Identifiable {
        public let id: String
        public let systemImage: String
        public let accessibilityLabel: String
        public let tone: LauncherMenuItem.Tone
        public let handler: () -> Void

        public init(
            _ systemImage: String,
            label: String,
            tone: LauncherMenuItem.Tone = .normal,
            action: @escaping () -> Void
        ) {
            self.id = systemImage + label
            self.systemImage = systemImage
            self.accessibilityLabel = label
            self.tone = tone
            self.handler = action
        }
    }

    private let actions: [Action]

    public init(_ actions: [Action]) {
        self.actions = actions
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(actions) { action in
                Button(action: action.handler) {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(action.tone == .danger ? theme.colors.danger : theme.colors.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .launcherPointer()
                .accessibilityLabel(action.accessibilityLabel)
                .launcherTooltip(action.accessibilityLabel)
            }
        }
        .opacity(hovering ? 1 : 0)
        .onHover { hovering = $0 }
        .animation(LauncherMotion.smooth, value: hovering)
    }
}

// MARK: - 多段比例条

/// 多段比例条（4pt 高），用于内存 / 磁盘用量等可视化。
public struct LauncherSegmentedBar: View {
    @Environment(\.launcherTheme) private var theme

    public struct Segment: Identifiable {
        public let id: String
        public let fraction: Double
        public let color: Color
        public let label: String

        public init(_ id: String, fraction: Double, color: Color, label: String) {
            self.id = id
            self.fraction = fraction
            self.color = color
            self.label = label
        }
    }

    private let segments: [Segment]
    private let height: CGFloat

    public init(_ segments: [Segment], height: CGFloat = 4) {
        self.segments = segments
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(segment.color)
                        .frame(width: max(0, proxy.size.width * segment.fraction - 2))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background {
            Capsule(style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        }
        .clipShape(Capsule(style: .continuous))
        .accessibilityHidden(true)
    }
}
