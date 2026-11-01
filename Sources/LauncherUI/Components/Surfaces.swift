import SwiftUI

// MARK: - 玻璃卡片

/// 玻璃卡片：统一玻璃层级（subtle / regular / strong）、圆角与内边距的内容容器。
public struct LauncherCard<Content: View>: View {
    private let level: GlassLevel
    private let padding: CGFloat
    private let content: () -> Content

    /// 创建一张玻璃卡片，内容默认左对齐并撑满可用宽度。
    public init(
        level: GlassLevel = .regular,
        padding: CGFloat = LauncherSpace.lg,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.level = level
        self.padding = padding
        self.content = content
    }

    public var body: some View {
        GlassPanel(level: level, cornerRadius: LauncherRadius.lg, padding: padding) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 卡片头部：图标 + 标题/说明 + 右侧附件槽位，保证同一行内垂直居中稳定。
public struct LauncherCardHeader: View {
    @Environment(\.launcherTheme) private var theme

    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let accessory: AnyView?

    /// 创建卡片头部。
    public init(title: String, subtitle: String? = nil, systemImage: String? = nil, accessory: AnyView? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = accessory
    }

    public var body: some View {
        HStack(alignment: .center, spacing: LauncherSpace.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(LauncherTextStyle.headline.font)
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                            .fill(theme.colors.accentSoft)
                    )
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text(title)
                    .textStyle(.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: LauncherSpace.sm)
            if let accessory {
                accessory
            }
        }
        .frame(minHeight: LauncherControl.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 列表行

/// 通用列表行：44pt 高，支持图标、副标题、徽标、尾部附件与选中态。
public struct LauncherListRow: View {
    @Environment(\.launcherTheme) private var theme
    @State private var hovering = false

    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let badge: String?
    private let accessory: AnyView?
    private let isSelected: Bool
    private let action: (() -> Void)?

    /// 创建一行列表项；传入 action 后整行可点击并带手型光标。
    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        badge: String? = nil,
        accessory: AnyView? = nil,
        isSelected: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.badge = badge
        self.accessory = accessory
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) {
                rowBody
            }
            .buttonStyle(.plain)
            .launcherPointer()
        } else {
            rowBody
        }
    }

    // MARK: 内部布局

    private var rowBody: some View {
        HStack(spacing: LauncherSpace.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(LauncherTextStyle.body.font)
                    .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                            .fill(isSelected ? theme.colors.accentSoft : theme.colors.surfaceSubtle)
                    )
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text(title)
                    .textStyle(.bodyStrong)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: LauncherSpace.sm)

            if let badge {
                LauncherBadge(badge, tone: isSelected ? .accent : .neutral)
            }

            if let accessory {
                accessory
            }
        }
        .padding(.horizontal, LauncherSpace.md)
        .frame(minHeight: LauncherControl.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .strokeBorder(theme.colors.accent.opacity(0.3), lineWidth: 1)
            }
        }
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(theme.colors.accent)
                .frame(width: 3)
                .padding(.vertical, LauncherSpace.sm)
                .opacity(isSelected ? 1 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous))
        .onHover { inside in
            hovering = inside
        }
        .launcherAnimation(LauncherMotion.smooth, value: hovering)
        .launcherAnimation(LauncherMotion.smooth, value: isSelected)
    }

    /// 行底色：选中 > hover > 透明。
    private var backgroundColor: Color {
        if isSelected { return theme.colors.accentSoft }
        if hovering { return theme.colors.surfaceHover }
        return .clear
    }
}

// MARK: - 区块标题

/// 区块标题：主标题 + 可选说明 + 右侧附件槽位，用于列表/卡片分组。
public struct LauncherSectionHeader: View {
    private let title: String
    private let subtitle: String?
    private let accessory: AnyView?

    /// 创建区块标题。
    public init(title: String, subtitle: String? = nil, accessory: AnyView? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
    }

    public var body: some View {
        HStack(alignment: .center, spacing: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text(title)
                    .textStyle(.sectionTitle)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: LauncherSpace.sm)
            if let accessory {
                accessory
            }
        }
        .frame(minHeight: LauncherControl.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 空状态

/// 空状态：内嵌玻璃底 + 居中图标 + 标题/说明 + 可选主操作。
public struct LauncherEmptyState: View {
    @Environment(\.launcherTheme) private var theme

    private let systemImage: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let onAction: (() -> Void)?

    /// 创建空状态；同时提供 actionTitle 与 onAction 时才显示按钮。
    public init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    public var body: some View {
        GlassPanel(level: .subtle, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
            VStack(spacing: LauncherSpace.md) {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .foregroundStyle(theme.colors.accent.opacity(0.7))
                    .accessibilityHidden(true)

                VStack(spacing: LauncherSpace.xs) {
                    Text(title)
                        .textStyle(.sectionTitle)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .textStyle(.caption, tone: .tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle, let onAction {
                    LauncherButton(actionTitle, variant: .primary, action: onAction)
                        .padding(.top, LauncherSpace.xs)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LauncherSpace.lg)
        }
    }
}

// MARK: - 头像

/// 头像：圆形低饱和渐变底 + 首字/图标，右下角可选在线状态点。
public struct LauncherAvatar: View {
    @Environment(\.launcherTheme) private var theme

    private let name: String
    private let systemImage: String?
    private let size: CGFloat
    private let isOnline: Bool

    /// 创建头像；中文名取第一个字，英文名取首字母。
    public init(name: String, systemImage: String? = nil, size: CGFloat = 32, isOnline: Bool = false) {
        self.name = name
        self.systemImage = systemImage
        self.size = size
        self.isOnline = isOnline
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(theme.colors.surfaceElevated)
                .overlay(
                    Circle()
                        .fill(theme.primaryGradient)
                        .opacity(0.38)
                )
                .overlay(
                    Circle()
                        .strokeBorder(theme.colors.stroke, lineWidth: 1)
                )
                .overlay { avatarContent }
                .frame(width: size, height: size)

            if isOnline {
                Circle()
                    .fill(theme.colors.success)
                    .overlay(
                        Circle()
                            .strokeBorder(theme.colors.canvas, lineWidth: 2)
                    )
                    .frame(width: max(7, size * 0.3), height: max(7, size * 0.3))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(isOnline ? "\(name)，在线" : name))
    }

    // MARK: 内部布局

    @ViewBuilder
    private var avatarContent: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(avatarFont)
                .foregroundStyle(theme.colors.textPrimary)
        } else {
            Text(initial)
                .font(avatarFont)
                .foregroundStyle(theme.colors.textPrimary)
        }
    }

    /// 首字：空名字用问号兜底。
    private var initial: String {
        guard let first = name.first else { return "?" }
        return String(first).uppercased()
    }

    /// 头像字号随尺寸档位变化，保证小头像不糊、大头像不空。
    private var avatarFont: Font {
        if size >= 44 { return LauncherTextStyle.headline.font }
        if size >= 28 { return LauncherTextStyle.caption.font }
        return LauncherTextStyle.micro.font
    }
}

// MARK: - 键值行

/// 键值行：左侧说明 + 右侧值（默认等宽），单行稳定对齐。
public struct LauncherKeyValueRow: View {
    private let key: String
    private let value: String
    private let isMono: Bool

    /// 创建键值行。
    public init(key: String, value: String, isMono: Bool = true) {
        self.key = key
        self.value = value
        self.isMono = isMono
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LauncherSpace.md) {
            Text(key)
                .textStyle(.caption, tone: .secondary)
                .lineLimit(1)
            Spacer(minLength: LauncherSpace.sm)
            if isMono {
                LauncherMonoText(value, tone: .primary)
                    .lineLimit(1)
            } else {
                Text(value)
                    .textStyle(.bodyStrong)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: LauncherSpace.xl)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 统计磁贴

/// 统计磁贴：数值用 title、标签用 micro tertiary 的玻璃小卡。
public struct LauncherStatTile: View {
    @Environment(\.launcherTheme) private var theme

    private let value: String
    private let label: String
    private let systemImage: String?

    /// 创建统计磁贴。
    public init(value: String, label: String, systemImage: String? = nil) {
        self.value = value
        self.label = label
        self.systemImage = systemImage
    }

    public var body: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                HStack(alignment: .firstTextBaseline, spacing: LauncherSpace.sm) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(LauncherTextStyle.caption.font)
                            .foregroundStyle(theme.colors.accent)
                            .accessibilityHidden(true)
                    }
                    Text(value)
                        .textStyle(.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(label)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 分割线

/// 分割线：1px 主题描边色横线。
public struct LauncherDivider: View {
    @Environment(\.launcherTheme) private var theme

    /// 创建一条分割线。
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(theme.colors.stroke)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
