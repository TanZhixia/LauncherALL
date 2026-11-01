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
        .frame(maxWidth: 1220, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, LauncherSpace.xxl)
        .padding(.top, LauncherSpace.xl)
        .padding(.bottom, LauncherSpace.xxxl)
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
    @State private var isHovering = false
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
            HStack(spacing: LauncherSpace.xs + 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
            .padding(.horizontal, LauncherSpace.md)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                    .fill(isSelected ? theme.colors.surfaceActive : (isHovering ? theme.colors.surfaceHover : .clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(tab.keyEquivalent, modifiers: .command)
        .launcherPointer()
        .onHover { isHovering = $0 }
        .help("\(tab.title)（\(tab.shortcut)）")
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
