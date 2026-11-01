import SwiftUI

// MARK: - 页面容器

/// 启动器页面容器：统一滚动、最大宽度、内边距与快照渲染兼容。
public struct LauncherAppPage<Content: View>: View {
    @Environment(\.launcherSnapshotMode) private var snapshotMode
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        Group {
            if snapshotMode {
                pageBody
            } else {
                ScrollView { pageBody }
                    .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var pageBody: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xl) {
            content()
        }
        .frame(maxWidth: 1240, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, LauncherSpace.xxl)
        .padding(.top, LauncherSpace.lg)
        .padding(.bottom, LauncherSpace.lg)
    }
}

// MARK: - 方块占位图

/// 实例封面占位：用方块网格 + 中心图标表达"我的世界"，纯中性色，不依赖任何图片资源。
public struct LauncherBlockArt: View {
    @Environment(\.launcherTheme) private var theme
    private let seed: String
    private let cornerRadius: CGFloat
    private let label: String?

    public init(seed: String, cornerRadius: CGFloat = LauncherRadius.lg, label: String? = nil) {
        self.seed = seed
        self.cornerRadius = cornerRadius
        self.label = label
    }

    public var body: some View {
        GeometryReader { proxy in
            let columns = 12
            let rows = 7
            let cellWidth = proxy.size.width / CGFloat(columns)
            let cellHeight = proxy.size.height / CGFloat(rows)
            ZStack {
                theme.colors.surfaceSubtle
                Canvas { context, size in
                    var generator = SeededGenerator(seed: seed)
                    for row in 0..<rows {
                        for column in 0..<columns {
                            let value = Double.random(in: 0...1, using: &generator)
                            guard value > 0.42 else { continue }
                            let rect = CGRect(
                                x: CGFloat(column) * cellWidth + 1,
                                y: CGFloat(row) * cellHeight + 1,
                                width: cellWidth - 2,
                                height: cellHeight - 2
                            )
                            let alpha = 0.03 + value * 0.10
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: 2),
                                with: .color(theme.colors.textPrimary.opacity(alpha))
                            )
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                VStack(spacing: LauncherSpace.sm) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(theme.colors.textSecondary)
                    if let label {
                        LauncherMonoText(label, tone: .tertiary, size: 10)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(theme.colors.stroke, lineWidth: 1)
            }
        }
    }
}

/// 可复现的伪随机数：同一实例名总是得到同一张封面。
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        state = 0x9E3779B97F4A7C15
        for byte in seed.utf8 {
            state = state &* 31 &+ UInt64(byte) &+ 0x9E3779B9
        }
        if state == 0 { state = 0x123456789 }
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - 小组件

/// 启动器里常用的键值信息（不占整行）：小标签 + 数值。
public struct LauncherInlineStat: View {
    @Environment(\.launcherTheme) private var theme
    private let label: String
    private let value: String
    private let isMono: Bool

    public init(_ label: String, value: String, isMono: Bool = false) {
        self.label = label
        self.value = value
        self.isMono = isMono
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(LauncherTextStyle.micro.font)
                .foregroundStyle(theme.colors.textTertiary)
            if isMono {
                LauncherMonoText(value, tone: .primary, size: 12)
            } else {
                Text(value)
                    .font(LauncherTextStyle.bodyStrong.font)
                    .foregroundStyle(theme.colors.textPrimary)
            }
        }
    }
}

/// 账户胶囊：头像 + 名字 + 在线点。
public struct LauncherAccountChip: View {
    @Environment(\.launcherTheme) private var theme
    private let account: LauncherAccount
    private let showsChevron: Bool

    public init(account: LauncherAccount = LauncherDemoData.account, showsChevron: Bool = true) {
        self.account = account
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(spacing: LauncherSpace.sm) {
            LauncherAvatar(name: account.name, systemImage: "person.fill", size: 26, isOnline: account.isOnline)
            VStack(alignment: .leading, spacing: 0) {
                Text(account.name)
                    .font(LauncherTextStyle.caption.font.weight(.medium))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                Text(account.type)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .padding(.horizontal, LauncherSpace.sm)
        .padding(.vertical, LauncherSpace.xs)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                        .strokeBorder(theme.colors.stroke, lineWidth: 1)
                )
        }
    }
}

/// 启动器顶部导航项。
public struct LauncherTabButton: View {
    @Environment(\.launcherTheme) private var theme
    @State private var hovering = false

    private let tab: LauncherTab
    private let isSelected: Bool
    private let action: () -> Void

    public init(tab: LauncherTab, isSelected: Bool, action: @escaping () -> Void) {
        self.tab = tab
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .fill(background)
            }
            .contentShape(RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .launcherPointer()
        .onHover { hovering = $0 }
        .launcherAnimation(LauncherMotion.smooth, value: hovering)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return theme.colors.accentSoft }
        if hovering { return theme.colors.surfaceHover }
        return .clear
    }
}

// MARK: - 页面内二级导航

/// 页面内二级导航的一项。
public struct LauncherSectionItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let badge: String?

    public init(id: String, title: String, systemImage: String, badge: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.badge = badge
    }
}

/// 竖排分区导航：每个一级页面内部再分几个分区，一次只显示一个，保证最小窗口下无需滚动。
public struct LauncherSectionRail: View {
    @Environment(\.launcherTheme) private var theme
    private let items: [LauncherSectionItem]
    private let selection: Binding<String>
    private let header: String?
    private let width: CGFloat

    public init(
        items: [LauncherSectionItem],
        selection: Binding<String>,
        header: String? = nil,
        width: CGFloat = 168
    ) {
        self.items = items
        self.selection = selection
        self.header = header
        self.width = width
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
            if let header {
                LauncherLabel(header)
                    .padding(.horizontal, LauncherSpace.sm)
                    .padding(.bottom, LauncherSpace.xs)
            }
            ForEach(items) { item in
                row(for: item)
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
    }

    private func row(for item: LauncherSectionItem) -> some View {
        let isSelected = selection.wrappedValue == item.id
        return Button {
            withAnimation(LauncherMotion.spring) {
                selection.wrappedValue = item.id
            }
        } label: {
            HStack(spacing: LauncherSpace.sm) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.textTertiary)
                    .frame(width: 16)
                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let badge = item.badge {
                    LauncherBadge(badge, tone: isSelected ? .accent : .neutral)
                }
            }
            .padding(.horizontal, LauncherSpace.sm)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                    .fill(isSelected ? theme.colors.surfaceActive : .clear)
            }
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(theme.colors.accent)
                    .frame(width: 2)
                    .padding(.vertical, 6)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .launcherPointer()
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 二级导航 + 竖向分割线 + 内容区，页面统一用这个布局。
public struct LauncherSectionLayout<Content: View>: View {
    @Environment(\.launcherTheme) private var theme
    private let rail: AnyView
    private let content: () -> Content

    public init<Rail: View>(@ViewBuilder rail: () -> Rail, @ViewBuilder content: @escaping () -> Content) {
        self.rail = AnyView(rail())
        self.content = content
    }

    public var body: some View {
        HStack(alignment: .top, spacing: LauncherSpace.lg) {
            rail
            Rectangle()
                .fill(theme.colors.stroke)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
