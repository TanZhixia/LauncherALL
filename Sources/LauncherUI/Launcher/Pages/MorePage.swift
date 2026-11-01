import SwiftUI

/// 更多页：页内四个分区（工具 / 快捷操作 / 快捷键 / 关于），一次只显示一个，最小窗口免滚动。
public struct MorePage: View {
    @Environment(\.launcherTheme) private var theme

    /// 打开既有设计系统画廊（由 App 壳注入，通常以 sheet 呈现）。
    private let onOpenGallery: () -> Void

    @State private var section = "tools"
    @State private var selectedToolID: String?
    @State private var exportHint: String?
    @State private var actionMessage = "所有操作都在本地完成，不会上传任何数据。"
    @State private var isCheckingUpdates = false
    @State private var updateMessage = "上次检查：今天 09:20"

    /// 二级竖排导航的四个分区。
    private let sections: [LauncherSectionItem] = [
        LauncherSectionItem(
            id: "tools",
            title: "工具",
            systemImage: "square.grid.2x2.fill",
            badge: "\(LauncherDemoData.tools.count)"
        ),
        LauncherSectionItem(id: "actions", title: "快捷操作", systemImage: "bolt.fill"),
        LauncherSectionItem(id: "shortcuts", title: "快捷键", systemImage: "keyboard"),
        LauncherSectionItem(id: "about", title: "关于", systemImage: "info.circle.fill", badge: "v0.2.0")
    ]

    public init(onOpenGallery: @escaping () -> Void = {}) {
        self.onOpenGallery = onOpenGallery
    }

    public var body: some View {
        LauncherAppPage {
            LauncherPageHeader(title: "更多", subtitle: "工具、备份、日志与设计资源") {
                LauncherButton(
                    "打开设计系统",
                    systemImage: "square.grid.2x2.fill",
                    variant: .secondary,
                    size: .small,
                    shortcut: "⌘⇧D"
                ) {
                    onOpenGallery()
                }
            }

            LauncherSectionLayout {
                LauncherSectionRail(items: sections, selection: $section, header: nil)
            } content: {
                switch section {
                case "actions": quickActionsSection
                case "shortcuts": shortcutsSection
                case "about": aboutSection
                default: toolsSection
                }
            }
        }
    }

    // MARK: - 工具

    /// 六个工具入口：三列两行，点击高亮并在底部同步所选工具。
    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            LauncherSectionHeader(
                title: "工具",
                subtitle: "维护、备份与本地资源",
                accessory: AnyView(
                    LauncherBadge(
                        selectedToolName ?? "\(LauncherDemoData.tools.count) 个工具",
                        tone: selectedToolName == nil ? .neutral : .accent
                    )
                )
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: LauncherSpace.md, alignment: .leading),
                    GridItem(.flexible(), spacing: LauncherSpace.md, alignment: .leading),
                    GridItem(.flexible(), spacing: LauncherSpace.md, alignment: .leading)
                ],
                alignment: .leading,
                spacing: LauncherSpace.md
            ) {
                ForEach(LauncherDemoData.tools) { tool in
                    toolCard(tool)
                }
            }

            HStack(spacing: LauncherSpace.xs) {
                Image(systemName: "hand.tap")
                    .textStyle(.micro, tone: .tertiary)
                if let selectedToolName {
                    Text("已选择「\(selectedToolName)」")
                        .textStyle(.micro, tone: .accent)
                } else {
                    Text("点击任意工具卡查看入口")
                        .textStyle(.micro, tone: .tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, LauncherSpace.xxs)
        }
    }

    /// 单个工具卡：图标方块 + 标题/说明 + 计数徽标，底部一行给出打开/已选反馈。
    private func toolCard(_ tool: LauncherToolCard) -> some View {
        let isSelected = selectedToolID == tool.id

        return Button {
            selectedToolID = tool.id
        } label: {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.sm) {
                    Image(systemName: tool.systemImage)
                        .textStyle(.headline, tone: isSelected ? .accent : .secondary)
                        .frame(width: 30, height: 30)
                        .background {
                            RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                                .fill(theme.colors.surfaceSubtle)
                        }

                    Spacer(minLength: 0)

                    if let badge = tool.badge {
                        LauncherBadge(badge, tone: .neutral)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.title)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    Text(tool.subtitle)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: LauncherSpace.xs) {
                    Text(isSelected ? "已选中" : "打开工具")
                        .textStyle(.micro, tone: isSelected ? .accent : .tertiary)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                        .textStyle(.caption, tone: isSelected ? .accent : .tertiary)
                }
            }
            .padding(LauncherSpace.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LauncherGlassBackground(level: .regular, cornerRadius: LauncherRadius.lg)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: LauncherRadius.lg, style: .continuous)
                        .strokeBorder(theme.colors.accent, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: LauncherRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .launcherHoverEffect(scale: 1.008)
        .accessibilityLabel("\(tool.title)：\(tool.subtitle)")
    }

    // MARK: - 快捷操作

    /// 三个本机动作 + 说明/日志路径行；导出日志时显示 2 秒成功徽标。
    private var quickActionsSection: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "快捷操作",
                    subtitle: "常用维护动作，全部在本地执行",
                    accessory: AnyView(LauncherMonoText("仅演示", tone: .tertiary))
                )

                HStack(spacing: LauncherSpace.md) {
                    LauncherButton(
                        "打开 .minecraft 文件夹",
                        systemImage: "folder",
                        variant: .secondary,
                        size: .medium,
                        isFullWidth: true
                    ) {
                        actionMessage = "已在访达中定位 .minecraft 文件夹。"
                    }

                    LauncherButton(
                        "导出日志",
                        systemImage: "square.and.arrow.up",
                        variant: .primary,
                        size: .medium,
                        isFullWidth: true
                    ) {
                        exportLogs()
                    }

                    LauncherButton(
                        "重置窗口布局",
                        systemImage: "rectangle.3.group",
                        variant: .ghost,
                        size: .medium,
                        isFullWidth: true
                    ) {
                        actionMessage = "窗口布局已重置为默认尺寸。"
                    }
                }

                HStack(spacing: LauncherSpace.sm) {
                    if let exportHint {
                        LauncherBadge(exportHint, tone: .success, systemImage: "checkmark.circle.fill")
                    } else {
                        Image(systemName: "info.circle")
                            .textStyle(.micro, tone: .tertiary)
                        Text(actionMessage)
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: LauncherSpace.md)

                    LauncherMonoText("~/Library/Logs/BlockLauncher", tone: .tertiary)
                }
            }
        }
    }

    // MARK: - 快捷键

    /// 六条快捷键，两列三行排布。
    private var shortcutsSection: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "快捷键",
                    subtitle: "高频操作少一次点击",
                    accessory: AnyView(LauncherBadge("\(LauncherDemoData.shortcuts.count) 个", tone: .neutral))
                )

                HStack(alignment: .top, spacing: LauncherSpace.xl) {
                    shortcutColumn(Array(LauncherDemoData.shortcuts.prefix(3)))
                    shortcutColumn(Array(LauncherDemoData.shortcuts.dropFirst(3)))
                }
            }
        }
    }

    /// 单列快捷键：左标题右按键的等宽键值行。
    private func shortcutColumn(_ items: [LauncherShortcut]) -> some View {
        VStack(spacing: LauncherSpace.sm) {
            ForEach(items) { shortcut in
                LauncherKeyValueRow(key: shortcut.title, value: shortcut.keys, isMono: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 关于

    /// 版本信息 + 检查更新 + 设计系统入口，左右两列排布。
    private var aboutSection: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "关于",
                    subtitle: "方块启动器",
                    accessory: AnyView(LauncherBadge("v0.2.0", tone: .accent))
                )

                HStack(alignment: .top, spacing: LauncherSpace.xl) {
                    VStack(spacing: LauncherSpace.sm) {
                        LauncherKeyValueRow(key: "版本", value: "v0.2.0", isMono: true)
                        LauncherKeyValueRow(key: "构建", value: "2026.11.01 · 1842", isMono: true)
                        LauncherKeyValueRow(key: "提交", value: "7f3c9a2", isMono: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                        HStack(spacing: LauncherSpace.sm) {
                            LauncherButton(
                                "检查更新",
                                systemImage: "arrow.triangle.2.circlepath",
                                variant: .secondary,
                                size: .small,
                                isLoading: isCheckingUpdates
                            ) {
                                checkForUpdates()
                            }

                            LauncherButton(
                                "设计系统画廊",
                                systemImage: "square.grid.2x2",
                                variant: .secondary,
                                size: .small
                            ) {
                                onOpenGallery()
                            }

                            Spacer(minLength: 0)
                        }

                        HStack(spacing: LauncherSpace.xs) {
                            LauncherStatusDot(tone: isCheckingUpdates ? .warning : .success)
                            Text(updateMessage)
                                .textStyle(.micro, tone: .tertiary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }

                        Text("基于 SwiftUI 构建 · 设计系统 v0.2")
                            .textStyle(.micro, tone: .tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 状态与交互

    /// 当前选中的工具名称（未选中时为 nil）。
    private var selectedToolName: String? {
        guard let selectedToolID else { return nil }
        return LauncherDemoData.tools.first { $0.id == selectedToolID }?.title
    }

    /// 导出日志：成功徽标显示 2 秒后回到常规说明。
    private func exportLogs() {
        exportHint = "日志已导出到桌面"
        actionMessage = "日志已导出到桌面 · BlockLauncher-2026-11-01.log。"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if exportHint != nil {
                exportHint = nil
            }
        }
    }

    /// 检查更新：先进入加载态，1.2 秒后给出结果（纯 UI 模拟）。
    private func checkForUpdates() {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        updateMessage = "正在检查更新…"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isCheckingUpdates = false
            updateMessage = "已是最新版本 v0.2.0 · 刚刚检查"
        }
    }
}
