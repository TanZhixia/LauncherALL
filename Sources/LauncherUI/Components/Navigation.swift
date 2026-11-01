import SwiftUI

// MARK: - 导航数据模型

/// 侧栏导航项：id 用于选中态绑定，badge 为右侧数字胶囊文案。
public struct LauncherNavItem: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let badge: String?

    /// 创建一个导航项。
    public init(id: String, title: String, systemImage: String, badge: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.badge = badge
    }
}

// MARK: - 侧栏单项

/// 侧栏导航项：34pt 高，选中时 accentSoft 底 + accent 图标文字 + 左侧 3pt 高亮条。
public struct LauncherSidebarItem: View {
    @Environment(\.launcherTheme) private var theme
    @State private var hovering = false

    private let item: LauncherNavItem
    private let isSelected: Bool
    private let action: () -> Void

    /// 创建一个侧栏项。
    public init(_ item: LauncherNavItem, isSelected: Bool, action: @escaping () -> Void) {
        self.item = item
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            rowBody
        }
        .buttonStyle(.plain)
        .launcherPointer()
    }

    // MARK: 内部布局

    private var rowBody: some View {
        HStack(spacing: LauncherSpace.sm) {
            Image(systemName: item.systemImage)
                .font(LauncherTextStyle.body.font)
                .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.textSecondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(item.title)
                .textStyle(.bodyStrong, tone: isSelected ? .accent : .secondary)
                .lineLimit(1)

            Spacer(minLength: LauncherSpace.sm)

            if let badge = item.badge {
                LauncherBadge(badge, tone: isSelected ? .accent : .neutral)
            }
        }
        .padding(.horizontal, LauncherSpace.sm)
        .frame(height: LauncherControl.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(backgroundColor)
        )
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

    /// 项底色：选中 > hover > 透明。
    private var backgroundColor: Color {
        if isSelected { return theme.colors.accentSoft }
        if hovering { return theme.colors.surfaceHover }
        return .clear
    }
}

// MARK: - 侧栏容器

/// 侧栏：玻璃底 + 右侧 1px 分割线，顶部/底部为任意内容槽位（账户、设置等）。
public struct LauncherSidebar: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let items: [LauncherNavItem]
    private let selection: Binding<String>
    private let header: AnyView?
    private let footer: AnyView?

    /// 创建侧栏。
    public init(
        items: [LauncherNavItem],
        selection: Binding<String>,
        header: AnyView? = nil,
        footer: AnyView? = nil
    ) {
        self.items = items
        self.selection = selection
        self.header = header
        self.footer = footer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.lg) {
            if let header {
                header
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                ForEach(items) { item in
                    LauncherSidebarItem(item, isSelected: item.id == selection.wrappedValue) {
                        select(item.id)
                    }
                }
            }

            Spacer(minLength: LauncherSpace.lg)

            if let footer {
                VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                    LauncherDivider()
                    footer
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(LauncherSpace.md)
        .frame(minWidth: 200, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack(alignment: .trailing) {
                LauncherGlassBackground(level: .regular, cornerRadius: LauncherRadius.xl)
                RoundedRectangle(cornerRadius: LauncherRadius.xl, style: .continuous)
                    .fill(theme.colors.surfaceElevated)
                Rectangle()
                    .fill(theme.colors.stroke)
                    .frame(width: 1)
                    .padding(.vertical, LauncherRadius.xl)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: 内部逻辑

    /// 切换选中项；减弱动效时不做过渡动画。
    private func select(_ id: String) {
        guard selection.wrappedValue != id else { return }
        withAnimation(reduceMotion ? nil : LauncherMotion.smooth) {
            selection.wrappedValue = id
        }
    }
}

// MARK: - 标签栏

/// 标签栏：一行胶囊标签，选中项 accentSoft 填充 + accent 文字。
public struct LauncherTabBar: View {
    /// 标签数据：id 用于选中态绑定。
    public struct Tab: Identifiable {
        public let id: String
        public let title: String
        public let systemImage: String?

        /// 创建一个标签。
        public init(id: String, title: String, systemImage: String? = nil) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
        }
    }

    @Environment(\.launcherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveringID: String?

    private let tabs: [Tab]
    private let selection: Binding<String>

    /// 创建标签栏。
    public init(tabs: [Tab], selection: Binding<String>) {
        self.tabs = tabs
        self.selection = selection
    }

    public var body: some View {
        GlassPanel(level: .subtle, cornerRadius: LauncherRadius.pill, padding: LauncherSpace.xs) {
            HStack(spacing: LauncherSpace.xxs) {
                ForEach(tabs) { tab in
                    tabButton(tab)
                }
            }
        }
    }

    // MARK: 内部布局

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = tab.id == selection.wrappedValue
        return Button {
            guard selection.wrappedValue != tab.id else { return }
            withAnimation(reduceMotion ? nil : LauncherMotion.smooth) {
                selection.wrappedValue = tab.id
            }
        } label: {
            HStack(spacing: LauncherSpace.sm) {
                if let systemImage = tab.systemImage {
                    Image(systemName: systemImage)
                        .font(LauncherTextStyle.caption.font)
                        .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(tab.title)
                    .textStyle(.bodyStrong, tone: isSelected ? .accent : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, LauncherSpace.md)
            .frame(height: LauncherControl.small)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundColor(for: tab, isSelected: isSelected))
            }
            .overlay {
                if isSelected {
                    Capsule(style: .continuous)
                        .strokeBorder(theme.colors.accent.opacity(0.35), lineWidth: 1)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .launcherPointer()
        .onHover { inside in
            if inside {
                hoveringID = tab.id
            } else if hoveringID == tab.id {
                hoveringID = nil
            }
        }
        .launcherAnimation(LauncherMotion.smooth, value: hoveringID)
        .launcherAnimation(LauncherMotion.smooth, value: isSelected)
    }

    /// 标签底色：选中 > hover > 透明。
    private func backgroundColor(for tab: Tab, isSelected: Bool) -> Color {
        if isSelected { return theme.colors.accentSoft }
        if hoveringID == tab.id { return theme.colors.surfaceHover }
        return .clear
    }
}

// MARK: - 对话框

/// 对话框卡片：.strong 玻璃、380pt 宽；遮罩层由页面自行叠加，组件只画卡片本身。
public struct LauncherDialog: View {
    /// 对话框语气：primary 常规，danger 危险操作（主按钮用 danger 变体）。
    public enum Tone {
        case primary
        case danger
    }

    @Environment(\.launcherTheme) private var theme

    private let title: String
    private let message: String
    private let primaryTitle: String
    private let secondaryTitle: String?
    private let tone: Tone
    private let onPrimary: () -> Void
    private let onSecondary: (() -> Void)?

    /// 创建对话框。
    public init(
        title: String,
        message: String,
        primaryTitle: String,
        secondaryTitle: String? = nil,
        tone: Tone = .primary,
        onPrimary: @escaping () -> Void,
        onSecondary: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.tone = tone
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
    }

    public var body: some View {
        GlassPanel(level: .strong, cornerRadius: LauncherRadius.xl, padding: LauncherSpace.xl) {
            VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                HStack(alignment: .top, spacing: LauncherSpace.md) {
                    Image(systemName: toneSymbol)
                        .font(LauncherTextStyle.headline.font)
                        .foregroundStyle(toneColor)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                                .fill(toneColor.opacity(0.16))
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                        Text(title)
                            .textStyle(.title)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(message)
                            .textStyle(.body, tone: .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: LauncherSpace.md) {
                    if let secondaryTitle, let onSecondary {
                        LauncherButton(
                            secondaryTitle,
                            variant: .secondary,
                            isFullWidth: true,
                            action: onSecondary
                        )
                    }
                    LauncherButton(
                        primaryTitle,
                        variant: primaryVariant,
                        isFullWidth: true,
                        action: onPrimary
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 380)
        .accessibilityElement(children: .contain)
    }

    // MARK: 语气映射

    /// 语气主色：danger 用危险色，其余用强调色。
    private var toneColor: Color {
        switch tone {
        case .primary: return theme.colors.accent
        case .danger: return theme.colors.danger
        }
    }

    /// 语气图标：危险操作给警示三角，常规操作给信息图标。
    private var toneSymbol: String {
        switch tone {
        case .primary: return "info.circle.fill"
        case .danger: return "exclamationmark.triangle.fill"
        }
    }

    /// 主按钮变体：danger 语义必须走 danger 变体。
    private var primaryVariant: LauncherButtonVariant {
        switch tone {
        case .primary: return .primary
        case .danger: return .danger
        }
    }
}
