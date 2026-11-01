import SwiftUI

// MARK: - 菜单模型

/// 菜单项：图标 + 标题 + 说明 + 快捷键，可标危险色、可禁用。
public struct LauncherMenuItem: Identifiable {
    public enum Tone {
        case normal
        case danger
    }

    public let id: String
    public let title: String
    public let systemImage: String?
    public let detail: String?
    public let shortcut: String?
    public let tone: Tone
    public let isDisabled: Bool
    public let action: () -> Void

    public init(
        _ title: String,
        id: String? = nil,
        systemImage: String? = nil,
        detail: String? = nil,
        shortcut: String? = nil,
        tone: Tone = .normal,
        isDisabled: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.id = id ?? title
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.shortcut = shortcut
        self.tone = tone
        self.isDisabled = isDisabled
        self.action = action
    }
}

/// 菜单分组：可带小标题，组间自动插入分隔线。
public struct LauncherMenuGroup: Identifiable {
    public let id: String
    public let title: String?
    public let items: [LauncherMenuItem]

    public init(title: String? = nil, items: [LauncherMenuItem]) {
        self.id = title ?? items.first?.id ?? UUID().uuidString
        self.title = title
        self.items = items
    }
}

// MARK: - 弹出菜单（点击展开）

/// 下拉菜单：任意触发器 + 弹出菜单面板。
/// 打开后点击外部或菜单项自动收起，支持图标、说明、快捷键、危险色与禁用项。
public struct LauncherMenu<Label: View>: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    private let groups: [LauncherMenuGroup]
    private let width: CGFloat
    private let arrowEdge: Edge
    private let label: () -> Label

    @State private var isPresented = false
    @State private var hoveredItemID: String?

    public init(
        groups: [LauncherMenuGroup],
        width: CGFloat = 232,
        arrowEdge: Edge = .bottom,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.groups = groups
        self.width = width
        self.arrowEdge = arrowEdge
        self.label = label
    }

    public var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
            panel
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                // 打开时让菜单获得焦点，方便点外部收起
                NSApp.activate()
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Rectangle()
                        .fill(theme.colors.stroke)
                        .frame(height: 1)
                        .padding(.vertical, LauncherSpace.xxs)
                }
                if let title = group.title {
                    LauncherLabel(title)
                        .padding(.horizontal, LauncherSpace.sm)
                        .padding(.top, LauncherSpace.xxs)
                        .padding(.bottom, LauncherSpace.xxs)
                }
                ForEach(group.items) { item in
                    row(for: item)
                }
            }
        }
        .padding(LauncherSpace.xxs)
        .frame(width: width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(theme.colors.surfaceElevated)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .strokeBorder(theme.colors.strokeStrong, lineWidth: 1)
        }
    }

    private func row(for item: LauncherMenuItem) -> some View {
        Button {
            guard !item.isDisabled else { return }
            isPresented = false
            item.action()
        } label: {
            HStack(spacing: LauncherSpace.sm) {
                if let systemImage = item.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(iconColor(for: item))
                        .frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textColor(for: item))
                        .lineLimit(1)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: LauncherSpace.sm)
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .padding(.horizontal, LauncherSpace.sm)
            .frame(height: item.detail == nil ? 28 : 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .center) {
                RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                    .fill(hoveredItemID == item.id ? theme.colors.surfaceHover : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.isDisabled)
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
        }
        .launcherPointer()
        .accessibilityLabel(item.title)
    }

    private func textColor(for item: LauncherMenuItem) -> Color {
        if item.isDisabled { return theme.colors.textTertiary }
        return item.tone == .danger ? theme.colors.danger : theme.colors.textPrimary
    }

    private func iconColor(for item: LauncherMenuItem) -> Color {
        if item.isDisabled { return theme.colors.textTertiary }
        return item.tone == .danger ? theme.colors.danger : theme.colors.textSecondary
    }
}

// MARK: - 便捷触发器

/// 「…」图标按钮触发的下拉菜单（列表行右侧常用）。
public struct LauncherIconMenu: View {
    private let groups: [LauncherMenuGroup]
    private let systemImage: String
    private let accessibilityLabel: String

    public init(
        groups: [LauncherMenuGroup],
        systemImage: String = "ellipsis",
        accessibilityLabel: String = "更多操作"
    ) {
        self.groups = groups
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        LauncherMenu(groups: groups) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

/// 带文字的菜单触发器（按钮外观可定制）。
public struct LauncherMenuButton: View {
    private let title: String
    private let systemImage: String?
    private let variant: LauncherButtonVariant
    private let size: LauncherButtonSize
    private let isFullWidth: Bool
    private let groups: [LauncherMenuGroup]

    public init(
        _ title: String,
        systemImage: String? = "chevron.down",
        variant: LauncherButtonVariant = .secondary,
        size: LauncherButtonSize = .small,
        isFullWidth: Bool = false,
        groups: [LauncherMenuGroup]
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.size = size
        self.isFullWidth = isFullWidth
        self.groups = groups
    }

    public var body: some View {
        LauncherMenu(groups: groups) {
            LauncherButton(
                title,
                systemImage: systemImage,
                variant: variant,
                size: size,
                isFullWidth: isFullWidth
            ) {}
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 右键上下文菜单

public extension View {
    /// 右键菜单：`.launcherContextMenu(groups)`，组间自动分隔。
    func launcherContextMenu(_ groups: [LauncherMenuGroup]) -> some View {
        contextMenu {
            ForEach(groups) { group in
                if let title = group.title {
                    Section(title) {
                        ForEach(group.items) { item in
                            item.contextMenuButton
                        }
                    }
                } else {
                    ForEach(group.items) { item in
                        item.contextMenuButton
                    }
                }
            }
        }
    }
}

extension LauncherMenuItem {
    @ViewBuilder
    var contextMenuButton: some View {
        Button(role: tone == .danger ? .destructive : nil) {
            action()
        } label: {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .disabled(isDisabled)
    }
}
