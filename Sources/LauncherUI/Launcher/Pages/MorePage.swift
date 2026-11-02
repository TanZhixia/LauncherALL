import SwiftUI
import AppKit

// MARK: - 更多页

/// 更多页（PCL 式布局）：左侧「工具 / 快捷操作 / 关于」列表，右侧对应真实功能面板。
/// 所有工具都接真实文件系统与运行时数据：备份用 `ditto` 打包、模组启停即重命名、截图读真实图片、
/// 日志导出写真实文件、窗口重置调用 NSWindow，不再有任何假 sleep 或"待接入"文案。
public struct MorePage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(LauncherRouter.self) private var router
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    /// 打开既有设计系统画廊（由 App 壳注入，通常以 sheet 呈现）。
    private let onOpenGallery: () -> Void

    // MARK: 分区与收藏

    @State private var selection: MoreSection = .logs
    /// 工具收藏（逗号分隔持久化到 UserDefaults，收藏的工具在列表中置顶）。
    @AppStorage("launcher.more.favoriteTools") private var favoriteTools = ""

    // MARK: 实例选择

    @State private var selectedVersionID = ""
    @State private var lastLoadedVersionID = ""

    // MARK: 备份

    @State private var backupItems: [MoreBackupItem] = []
    @State private var isLoadingBackups = false
    @State private var isCreatingBackup = false
    @State private var restoringBackupID: URL?

    // MARK: 模组

    @State private var modItems: [MoreModItem] = []
    @State private var isLoadingMods = false
    @State private var modQuery = ""
    @State private var modSortAscending = true
    @State private var busyModURLs: Set<URL> = []

    // MARK: 截图

    @State private var screenshotItems: [MoreScreenshotItem] = []
    @State private var isLoadingScreenshots = false

    // MARK: 日志

    @State private var lastLogExport: MoreLogExport?
    @State private var logFeedbackMessage: String?
    @State private var logFeedbackTone: LauncherBadgeTone = .success

    // MARK: 快捷操作

    @State private var actionMessage = "所有操作都在本地完成，不会上传任何数据。"
    @State private var actionTone: LauncherBadgeTone = .neutral
    @State private var windowSizeText = "—"

    // MARK: 关于 / 更新

    @State private var updateChecker = UpdateChecker()

    /// 日志视口高度：固定值保证最小窗口（1080×720）下右栏首屏不出现纵向滚动。
    private let logViewportHeight: CGFloat = LauncherSpace.xxxl * 6 + LauncherSpace.xl * 2
    /// 备份列表视口高度。
    private let backupListHeight: CGFloat = LauncherSpace.xxxl * 5
    /// 模组列表视口高度。
    private let modListHeight: CGFloat = LauncherSpace.xxxl * 5 + LauncherSpace.lg
    /// 截图网格视口高度。
    private let screenshotViewportHeight: CGFloat = LauncherSpace.xxxl * 6 + LauncherSpace.xl

    public init(onOpenGallery: @escaping () -> Void = {}) {
        self.onOpenGallery = onOpenGallery
    }

    public var body: some View {
        LauncherPageLayout(sideWidth: 272) {
            sidePanel
        } main: {
            LauncherMainPanel {
                mainHeader
                pageContent
            }
        }
        .onAppear { handleAppear() }
        .onChange(of: router.pendingMoreSection) { _, _ in consumePendingSection() }
        .onChange(of: engine.installedVersions.count) { _, _ in
            synchronizeSelection()
            reloadInstanceLibraries()
        }
    }

    // MARK: - 左侧面板

    /// 左面板：工具列表（收藏置顶）/ 快捷操作 / 关于，底部放设计系统入口与真实构建信息。
    private var sidePanel: some View {
        LauncherSidePanel(
            title: "更多",
            width: 272,
            toolbar: AnyView(sideToolbar),
            content: {
                LauncherSidePanelGroup("工具", trailing: "\(Self.tools.count)")
                ForEach(orderedTools) { tool in
                    toolRow(tool)
                }

                LauncherSidePanelGroup("快捷操作")
                sideLinkRow("打开游戏目录", systemImage: "folder") {
                    openGameDirectory(showsQuickPage: true)
                }
                sideLinkRow("导出日志", systemImage: "square.and.arrow.up") {
                    exportLogs(showsQuickPage: true)
                }
                .launcherTooltip("导出到 ~/Library/Logs/BlockLauncher/")
                sideLinkRow("重置窗口布局", systemImage: "rectangle.3.group") {
                    resetWindowLayout(showsQuickPage: true)
                }

                LauncherSidePanelGroup("关于")
                sideLinkRow("快捷键说明", systemImage: "keyboard", isSelected: selection == .shortcuts) {
                    select(.shortcuts)
                }
                sideLinkRow("关于", systemImage: "info.circle.fill", isSelected: selection == .about) {
                    select(.about)
                }
            },
            footer: {
                VStack(spacing: LauncherSpace.xs) {
                    Rectangle()
                        .fill(theme.colors.stroke)
                        .frame(height: 1)
                    LauncherButton(
                        "设计系统画廊",
                        systemImage: "square.grid.2x2",
                        variant: .secondary,
                        isFullWidth: true
                    ) {
                        onOpenGallery()
                    }
                    HStack(spacing: LauncherSpace.xxs) {
                        LauncherMonoText(
                            "\(LauncherBuildInfo.current.versionText) · 构建 \(LauncherBuildInfo.current.buildDateText)",
                            tone: .tertiary,
                            size: 10
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, LauncherSpace.xxs)
                }
            }
        )
    }

    /// 左面板标题栏右侧：收藏数量徽标（没有收藏时不占位）。
    @ViewBuilder
    private var sideToolbar: some View {
        if !favoriteToolIDs.isEmpty {
            LauncherBadge("\(favoriteToolIDs.count) 收藏", tone: .neutral, systemImage: "star.fill")
        }
    }

    /// 工具列表行：收藏置顶 + 动态真实徽标 + 选中高亮 + 右键菜单。
    private func toolRow(_ tool: MoreToolDefinition) -> some View {
        let isFavorite = favoriteToolIDs.contains(tool.id)
        return LauncherListRow(
            title: tool.title,
            subtitle: tool.subtitle,
            systemImage: tool.systemImage,
            badge: toolBadge(for: tool.section),
            accessory: AnyView(
                HStack(spacing: LauncherSpace.xs) {
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .textStyle(.caption, tone: .warning)
                            .accessibilityLabel("已收藏")
                    }
                    Image(systemName: "chevron.right")
                        .textStyle(.caption, tone: .tertiary)
                }
            ),
            isSelected: selection == tool.section,
            action: { select(tool.section) }
        )
        .launcherContextMenu(toolContextMenu(tool))
    }

    /// 紧凑动作 / 链接行：高度比工具行更小，保证最小窗口下左栏不滚动。
    private func sideLinkRow(
        _ title: String,
        systemImage: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        MoreSideLinkRow(
            title: title,
            systemImage: systemImage,
            isSelected: isSelected,
            action: action
        )
    }

    /// 工具行右键菜单：打开 / 在访达中显示 / 复制目录路径 / 收藏。
    private func toolContextMenu(_ tool: MoreToolDefinition) -> [LauncherMenuGroup] {
        let isFavorite = favoriteToolIDs.contains(tool.id)
        let directory = toolDirectoryURL(tool.section)
        return [
            LauncherMenuGroup(items: [
                LauncherMenuItem("打开", systemImage: "arrow.up.right", action: { select(tool.section) }),
                LauncherMenuItem(
                    directory == nil ? "在访达中显示（无对应目录）" : "在访达中显示",
                    systemImage: "folder",
                    detail: directory == nil ? "社区 / 快捷键 / 关于分区没有本地目录" : nil,
                    isDisabled: directory == nil,
                    action: { if let directory { InstanceActions.reveal(directory) } }
                ),
                LauncherMenuItem(
                    directory == nil ? "复制目录路径（无对应目录）" : "复制目录路径",
                    systemImage: "doc.on.doc",
                    detail: directory == nil ? "社区 / 快捷键 / 关于分区没有本地目录" : nil,
                    isDisabled: directory == nil,
                    action: {
                        if let directory {
                            InstanceActions.copy(directory.path)
                            router.showToast("已复制路径")
                        }
                    }
                ),
                LauncherMenuItem(
                    isFavorite ? "取消收藏" : "标记收藏",
                    systemImage: isFavorite ? "star.slash" : "star",
                    action: { toggleFavorite(tool.id) }
                )
            ])
        ]
    }

    // MARK: - 右侧标题

    /// 右侧面板标题：选中分区标题 + 真实状态说明 + 「更多」菜单。
    private var mainHeader: some View {
        LauncherPanelHeader(selectedTitle, subtitle: selectedSubtitle) {
            HStack(spacing: LauncherSpace.xs) {
                LauncherIconMenu(groups: headerMenuGroups, accessibilityLabel: "更多操作")
            }
        }
    }

    /// 头部「更多」菜单：全部真实动作。
    private var headerMenuGroups: [LauncherMenuGroup] {
        [
            LauncherMenuGroup(items: [
                LauncherMenuItem("刷新环境", systemImage: "arrow.clockwise", action: refreshEnvironment),
                LauncherMenuItem("复制诊断信息", systemImage: "stethoscope", action: copyDiagnostics),
                LauncherMenuItem("打开游戏目录", systemImage: "folder", action: { openGameDirectory(showsQuickPage: false) }),
                LauncherMenuItem("导出日志", systemImage: "square.and.arrow.up", action: { exportLogs(showsQuickPage: false) })
            ]),
            LauncherMenuGroup(items: [
                LauncherMenuItem("设计系统画廊", systemImage: "square.grid.2x2", action: onOpenGallery)
            ])
        ]
    }

    /// 右侧当前分区内容。
    @ViewBuilder
    private var pageContent: some View {
        switch selection {
        case .backup: backupPage
        case .mods: modsPage
        case .screenshots: screenshotsPage
        case .community: communityPage
        case .shortcuts: shortcutsPage
        case .about: aboutPage
        case .quick: quickActionsPage
        case .logs: logsPage
        }
    }

    // MARK: - 日志与诊断

    /// 真实启动日志：状态、启动命令、实时输出、清空 / 复制 / 导出 / 打开日志目录。
    private var logsPage: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            logStatusCard
            logConsoleCard
            if let lastLogExport {
                LauncherBanner(
                    title: "日志已导出：\(lastLogExport.url.lastPathComponent)",
                    message: "\(lastLogExport.sizeText) · \(lastLogExport.url.deletingLastPathComponent().path)",
                    tone: .success,
                    actionTitle: "在访达显示",
                    onAction: { InstanceActions.reveal(lastLogExport.url) }
                )
            }
        }
    }

    private var logStatusCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherBadge(engine.statusText, tone: logStatusTone, systemImage: logStatusIcon)

                    if let exitCode = engine.lastExitCode {
                        LauncherBadge(
                            "退出码 \(exitCode)",
                            tone: exitCode == 0 ? .success : .danger,
                            systemImage: exitCode == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill"
                        )
                    }

                    if let versionID = engine.activeVersionID {
                        LauncherBadge("版本 \(versionID)", tone: .neutral)
                    }

                    Spacer(minLength: LauncherSpace.md)

                    LauncherMonoText(
                        "\(engine.logLines.count) 行 · \(MoreLogExporter.sizeText(engine.logLines))",
                        tone: .tertiary,
                        size: 10
                    )

                    LauncherIconButton(
                        systemImage: "trash",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: engine.logLines.isEmpty ? "清空日志（当前没有日志）" : "清空日志",
                        isDisabled: engine.logLines.isEmpty
                    ) {
                        confirmClearLog()
                    }

                    LauncherIconButton(
                        systemImage: "doc.on.doc",
                        variant: .secondary,
                        size: .small,
                        accessibilityLabel: engine.logLines.isEmpty ? "复制全部日志（当前没有日志可复制）" : "复制全部日志",
                        isDisabled: engine.logLines.isEmpty
                    ) {
                        copyLog()
                    }

                    LauncherIconMenu(groups: logMenuGroups, accessibilityLabel: "日志操作")

                    LauncherButton("导出日志", systemImage: "square.and.arrow.up", variant: .secondary, size: .small) {
                        exportLogs(showsQuickPage: false)
                    }
                    .launcherTooltip("导出到 ~/Library/Logs/BlockLauncher/，导出后可在访达显示")
                }

                commandPreview
            }
        }
    }

    /// 日志操作菜单：真实复制 / 打开目录 / 显示导出文件。
    private var logMenuGroups: [LauncherMenuGroup] {
        [
            LauncherMenuGroup(items: [
                LauncherMenuItem(
                    "复制最近 100 行",
                    systemImage: "doc.on.doc",
                    detail: engine.logLines.isEmpty ? "当前没有日志可复制" : "最近 100 行运行时输出",
                    isDisabled: engine.logLines.isEmpty,
                    action: { copyRecentLog(100) }
                ),
                LauncherMenuItem("复制诊断信息", systemImage: "stethoscope", action: copyDiagnostics),
                LauncherMenuItem(
                    "打开日志文件夹",
                    systemImage: "folder",
                    detail: "~/Library/Logs/BlockLauncher/",
                    action: { openLogsFolder(showsQuickPage: false) }
                ),
                LauncherMenuItem(
                    "在访达中显示导出文件",
                    systemImage: "magnifyingglass",
                    detail: lastLogExport == nil ? "还没有导出过日志" : (lastLogExport?.url.lastPathComponent ?? ""),
                    isDisabled: lastLogExport == nil,
                    action: { if let lastLogExport { InstanceActions.reveal(lastLogExport.url) } }
                )
            ])
        ]
    }

    /// 启动命令预览：等宽两行，过长时省略中段。
    @ViewBuilder
    private var commandPreview: some View {
        if let command = engine.lastCommandLine {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                HStack(spacing: LauncherSpace.xs) {
                    LauncherLabel("启动命令")
                    Spacer(minLength: 0)
                    LauncherMonoText("\(command.count) 字符", tone: .tertiary)
                }
                Text(verbatim: command)
                    .font(LauncherTextStyle.monoSmall.font)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(LauncherSpace.sm)
            .glassBackground(level: .subtle, cornerRadius: LauncherRadius.sm)
        } else {
            HStack(spacing: LauncherSpace.xs) {
                Image(systemName: "command")
                    .textStyle(.micro, tone: .tertiary)
                Text("尚未启动过游戏，暂无启动命令。")
                    .textStyle(.micro, tone: .tertiary)
                Spacer(minLength: 0)
                LauncherButton("打开日志文件夹", systemImage: "folder", variant: .ghost, size: .small) {
                    openLogsFolder(showsQuickPage: false)
                }
            }
            .padding(LauncherSpace.sm)
            .glassBackground(level: .subtle, cornerRadius: LauncherRadius.sm)
        }
    }

    /// 日志卡：固定高度视口，交互模式滚动并自动跟到底部，离屏模式静态裁切。
    private var logConsoleCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "输出日志",
                    subtitle: "共 \(engine.logLines.count) 行 · 最多保留 600 行 · 导出到 ~/Library/Logs/BlockLauncher/",
                    accessory: AnyView(logHeaderAccessory)
                )

                if engine.logLines.isEmpty {
                    LauncherEmptyState(
                        systemImage: "terminal",
                        title: "还没有日志",
                        message: "启动一次游戏后，这里会显示真实输出；也可以先导出当前诊断信息。",
                        actionTitle: "复制诊断信息",
                        onAction: copyDiagnostics
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: logViewportHeight)
                } else {
                    logConsole
                        .frame(maxWidth: .infinity)
                        .frame(height: logViewportHeight)
                        .clipShape(RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous))
                        .glassBackground(level: .subtle, cornerRadius: LauncherRadius.md)
                }
            }
        }
    }

    /// 日志卡右上角：真实操作反馈徽标 / 运行状态。
    @ViewBuilder
    private var logHeaderAccessory: some View {
        if let logFeedbackMessage {
            LauncherBadge(logFeedbackMessage, tone: logFeedbackTone, systemImage: "checkmark.circle.fill")
        } else if engine.isBusy {
            LauncherBadge("运行中", tone: .warning, systemImage: "arrow.triangle.2.circlepath")
        } else {
            LauncherBadge("实时", tone: .neutral, systemImage: "dot.radiowaves.left.and.right")
        }
    }

    /// 日志区本体：离屏静态列表 / 交互滚动列表。
    @ViewBuilder
    private var logConsole: some View {
        if snapshotMode {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                ForEach(Array(engine.logLines.suffix(18).enumerated()), id: \.offset) { _, line in
                    logLine(line)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(LauncherSpace.sm)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        ForEach(Array(engine.logLines.enumerated()), id: \.offset) { index, line in
                            logLine(line)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LauncherSpace.sm)
                }
                .scrollIndicators(.hidden)
                .onAppear { scrollLogToBottom(proxy, animated: false) }
                .onChange(of: engine.logLines.count) { _, _ in
                    scrollLogToBottom(proxy, animated: true)
                }
            }
        }
    }

    /// 单行日志：mono 11pt，按关键词着色。
    private func logLine(_ line: String) -> some View {
        Text(verbatim: line.isEmpty ? " " : line)
            .font(LauncherTextStyle.monoSmall.font)
            .foregroundStyle(logTone(for: line).color(in: theme))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 实例备份

    /// 实例备份页：真实 zip 打包 / 恢复 / 删除，列表来自 `backups/` 目录。
    private var backupPage: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "实例备份",
                    subtitle: "把世界存档、模组、配置与启动设置打包为 zip 保存到本地",
                    accessory: AnyView(
                        HStack(spacing: LauncherSpace.xs) {
                            LauncherBadge("\(backupItems.count) 个备份", tone: backupItems.isEmpty ? .neutral : .success)
                            LauncherMonoText(backupTotalSizeText, tone: .tertiary, size: 10)
                        }
                    )
                )

                if engine.installedVersions.isEmpty {
                    LauncherEmptyState(
                        systemImage: "externaldrive.badge.timemachine",
                        title: "还没有可备份的实例",
                        message: "先在「下载」页安装一个版本，之后就能在这里备份世界与模组配置。",
                        actionTitle: "前往下载页",
                        onAction: { router.go(.download) }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: LauncherSpace.xxxl * 6)
                } else {
                    backupControls
                    backupContentsRow
                    backupListPanel
                    backupFooter
                }
            }
        }
    }

    /// 目标实例 + 立即备份 + 打开备份目录。
    private var backupControls: some View {
        HStack(spacing: LauncherSpace.sm) {
            LauncherLabel("目标实例")
            LauncherDropdown(
                options: instanceOptions,
                selection: instanceSelectionBinding,
                placeholder: "选择实例"
            )
            .frame(width: 240)

            LauncherButton(
                isCreatingBackup ? "正在备份…" : "立即备份",
                systemImage: "externaldrive.badge.plus",
                variant: .primary,
                size: .medium,
                isLoading: isCreatingBackup,
                isDisabled: !hasBackupContent
            ) {
                startBackup()
            }
            .launcherTooltip(
                hasBackupContent
                    ? "把 saves / mods / config / options.txt / servers.dat 打包为 zip 到 backups/"
                    : "当前实例没有可备份的内容（saves / mods / config / options.txt / servers.dat 都不存在）"
            )

            LauncherIconButton(
                systemImage: "folder",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "打开备份目录"
            ) {
                openBackupsDirectory(showsQuickPage: false)
            }

            Spacer(minLength: 0)
        }
    }

    /// 备份内容说明：真实存在哪些条目。
    private var backupContentsRow: some View {
        HStack(spacing: LauncherSpace.xs) {
            LauncherLabel("包含")
            ForEach(MoreBackupService.entries(instanceDirectory: selectedInstanceDirectory)) { entry in
                LauncherBadge(
                    entry.title,
                    tone: entry.exists ? .success : .neutral,
                    systemImage: entry.exists ? "checkmark.circle.fill" : "minus.circle"
                )
                .opacity(entry.exists ? 1 : 0.55)
            }
            Spacer(minLength: 0)
            if !hasBackupContent {
                Text("实例里没有可备份的内容")
                    .textStyle(.micro, tone: .warning)
                    .lineLimit(1)
            }
        }
    }

    /// 真实备份列表：固定视口内部滚动，离屏模式静态堆叠。
    private var backupListPanel: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            HStack(spacing: LauncherSpace.xs) {
                LauncherLabel("已有备份")
                Spacer(minLength: 0)
                if isLoadingBackups {
                    LauncherSpinner(size: 12)
                }
                if let restoringBackupID {
                    LauncherMonoText("正在恢复 \(restoringBackupID.lastPathComponent)", tone: .tertiary, size: 10)
                }
                LauncherButton("刷新", systemImage: "arrow.clockwise", variant: .ghost, size: .small) {
                    reloadBackups()
                }
            }

            Group {
                if isLoadingBackups && backupItems.isEmpty {
                    VStack(spacing: LauncherSpace.xs) {
                        LauncherSkeleton(height: LauncherControl.large)
                        LauncherSkeleton(height: LauncherControl.large)
                        LauncherSkeleton(height: LauncherControl.large)
                    }
                    .frame(height: backupListHeight, alignment: .top)
                } else if backupItems.isEmpty {
                    LauncherEmptyState(
                        systemImage: "archivebox",
                        title: "还没有备份",
                        message: "点「立即备份」把当前实例的存档与模组配置打包到 \(MoreBackupService.backupsFolderName)/ 目录。",
                        actionTitle: "立即备份",
                        onAction: startBackup
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: backupListHeight)
                } else {
                    backupScrollList
                        .frame(maxWidth: .infinity)
                        .frame(height: backupListHeight, alignment: .top)
                }
            }
        }
    }

    private var backupScrollList: some View {
        Group {
            if snapshotMode {
                VStack(spacing: LauncherSpace.xs) {
                    ForEach(backupItems.prefix(4)) { item in
                        backupRow(item)
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: LauncherSpace.xs) {
                        ForEach(backupItems) { item in
                            backupRow(item)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// 单条备份：恢复 / 在访达显示 / 复制路径 / 删除（均需真实执行）。
    private func backupRow(_ item: MoreBackupItem) -> some View {
        LauncherListRow(
            title: item.name,
            subtitle: "\(item.sizeText) · \(item.dateText)" + (item.instanceGuess.map { " · 实例 \($0)" } ?? ""),
            systemImage: "archivebox",
            accessory: AnyView(
                HStack(spacing: LauncherSpace.xs) {
                    LauncherButton(
                        "恢复",
                        systemImage: "arrow.counterclockwise",
                        variant: .secondary,
                        size: .small,
                        isLoading: restoringBackupID == item.url,
                        isDisabled: restoringBackupID != nil
                    ) {
                        confirmRestore(item)
                    }
                    .launcherTooltip(
                        restoringBackupID == nil
                            ? "把该备份解压回当前实例（会覆盖同名文件）"
                            : "正在恢复另一个备份，请稍候"
                    )
                    LauncherIconMenu(groups: backupRowMenu(item))
                }
            ),
            action: { InstanceActions.reveal(item.url) }
        )
        .launcherContextMenu(backupRowMenu(item))
    }

    /// 单条备份的右键 / 「…」菜单。
    private func backupRowMenu(_ item: MoreBackupItem) -> [LauncherMenuGroup] {
        [
            LauncherMenuGroup(items: [
                LauncherMenuItem("恢复到当前实例", systemImage: "arrow.counterclockwise", action: { confirmRestore(item) }),
                LauncherMenuItem("在访达中显示", systemImage: "folder", action: { InstanceActions.reveal(item.url) }),
                LauncherMenuItem("复制路径", systemImage: "doc.on.doc", action: {
                    InstanceActions.copy(item.url.path)
                    router.showToast("已复制备份路径")
                }),
                LauncherMenuItem("删除到废纸篓", systemImage: "trash", tone: .danger, action: { confirmDeleteBackup(item) })
            ])
        ]
    }

    /// 备份页底部：真实路径 + 打开目录。
    private var backupFooter: some View {
        HStack(spacing: LauncherSpace.sm) {
            Image(systemName: "folder")
                .textStyle(.micro, tone: .tertiary)
            LauncherMonoText(MoreBackupService.backupsDirectory(gameDirectory: gameDirectoryRoot).path, tone: .tertiary, size: 10)
                .lineLimit(1)
            Spacer(minLength: LauncherSpace.sm)
            LauncherButton("复制路径", systemImage: "doc.on.doc", variant: .ghost, size: .small) {
                InstanceActions.copy(MoreBackupService.backupsDirectory(gameDirectory: gameDirectoryRoot).path)
                router.showToast("已复制备份目录路径")
            }
            LauncherButton("打开备份目录", systemImage: "folder", variant: .ghost, size: .small) {
                openBackupsDirectory(showsQuickPage: false)
            }
        }
    }

    // MARK: - 模组管理

    /// 模组管理页：真实扫描 `mods/`，启用 / 禁用就是重命名 `.jar` ↔ `.jar.disabled`。
    private var modsPage: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "模组管理",
                    subtitle: "真实扫描实例 mods/ 目录 · 启用 / 禁用会重命名文件",
                    accessory: AnyView(
                        HStack(spacing: LauncherSpace.xs) {
                            LauncherBadge("启用 \(modCounts.enabled)", tone: .success)
                            LauncherBadge("禁用 \(modCounts.disabled)", tone: .neutral)
                            LauncherMonoText(MoreModLibrary.totalSizeText(modItems), tone: .tertiary, size: 10)
                        }
                    )
                )

                if engine.installedVersions.isEmpty {
                    LauncherEmptyState(
                        systemImage: "puzzlepiece.extension.fill",
                        title: "还没有可管理模组的实例",
                        message: "先在「下载」页安装一个版本，再往实例的 mods/ 目录里放 .jar 模组。",
                        actionTitle: "前往下载页",
                        onAction: { router.go(.download) }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: LauncherSpace.xxxl * 6)
                } else {
                    modsControls
                    modsListPanel
                    modsFooter
                }
            }
        }
    }

    /// 实例选择 + 搜索 + 排序 + 打开模组目录。
    private var modsControls: some View {
        HStack(spacing: LauncherSpace.sm) {
            instancePicker

            LauncherSearchField(text: $modQuery, placeholder: "搜索模组文件名")
                .frame(maxWidth: .infinity)

            LauncherIconButton(
                systemImage: modSortAscending ? "arrow.up.arrow.down" : "arrow.down.arrow.up",
                variant: .secondary,
                size: .small,
                accessibilityLabel: modSortAscending ? "当前按名称升序，点击切换" : "当前按名称降序，点击切换"
            ) {
                modSortAscending.toggle()
            }

            LauncherIconButton(
                systemImage: "folder",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "打开模组目录"
            ) {
                openModsDirectory(showsQuickPage: false)
            }
        }
    }

    /// 模组列表：固定视口 + 内部滚动 / 空态 / 加载态。
    private var modsListPanel: some View {
        Group {
            if isLoadingMods && modItems.isEmpty {
                VStack(spacing: LauncherSpace.xs) {
                    LauncherSkeleton(height: LauncherControl.large)
                    LauncherSkeleton(height: LauncherControl.large)
                    LauncherSkeleton(height: LauncherControl.large)
                }
                .frame(height: modListHeight, alignment: .top)
            } else if modItems.isEmpty {
                LauncherEmptyState(
                    systemImage: "puzzlepiece.extension.fill",
                    title: modsDirectoryExists ? "mods/ 里还没有模组" : "还没有 mods 目录",
                    message: "把模组 .jar 放进 \(modsDirectoryPath)，或到「下载 → 社区资源」安装模组与整合包。",
                    actionTitle: "前往下载页",
                    onAction: { router.go(.download) }
                )
                .frame(maxWidth: .infinity)
                .frame(height: modListHeight)
            } else if visibleModItems.isEmpty {
                LauncherEmptyState(
                    systemImage: "magnifyingglass",
                    title: "没有匹配的模组",
                    message: "换个关键词试试，当前共有 \(modItems.count) 个模组文件。",
                    actionTitle: "清除搜索",
                    onAction: { modQuery = "" }
                )
                .frame(maxWidth: .infinity)
                .frame(height: modListHeight)
            } else {
                modScrollList
                    .frame(maxWidth: .infinity)
                    .frame(height: modListHeight, alignment: .top)
            }
        }
    }

    private var modScrollList: some View {
        Group {
            if snapshotMode {
                VStack(spacing: LauncherSpace.xs) {
                    ForEach(visibleModItems.prefix(5)) { item in
                        modRow(item)
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: LauncherSpace.xs) {
                        ForEach(visibleModItems) { item in
                            modRow(item)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// 单个模组：状态徽标 + 启用/禁用按钮 + 菜单。
    private func modRow(_ item: MoreModItem) -> some View {
        LauncherListRow(
            title: item.displayName,
            subtitle: "\(item.sizeText) · \(item.dateText)",
            systemImage: item.isEnabled ? "puzzlepiece.extension.fill" : "puzzlepiece.extension",
            accessory: AnyView(
                HStack(spacing: LauncherSpace.xs) {
                    LauncherBadge(item.isEnabled ? "已启用" : "已禁用", tone: item.isEnabled ? .success : .neutral)
                    LauncherButton(
                        item.isEnabled ? "禁用" : "启用",
                        systemImage: item.isEnabled ? "pause.circle" : "play.circle",
                        variant: .secondary,
                        size: .small,
                        isDisabled: busyModURLs.contains(item.url),
                        action: { toggleMod(item) }
                    )
                    .launcherTooltip(
                        busyModURLs.contains(item.url)
                            ? "正在重命名模组文件，请稍候"
                            : (item.isEnabled ? "重命名为 .jar.disabled 以禁用" : "去掉 .disabled 后缀以启用")
                    )
                    LauncherIconMenu(groups: modRowMenu(item))
                }
            )
        )
        .launcherContextMenu(modRowMenu(item))
    }

    /// 单个模组的右键 / 「…」菜单。
    private func modRowMenu(_ item: MoreModItem) -> [LauncherMenuGroup] {
        [
            LauncherMenuGroup(items: [
                LauncherMenuItem(
                    item.isEnabled ? "禁用此模组" : "启用此模组",
                    systemImage: item.isEnabled ? "pause.circle" : "play.circle",
                    action: { toggleMod(item) }
                ),
                LauncherMenuItem("在访达中显示", systemImage: "folder", action: { InstanceActions.reveal(item.url) }),
                LauncherMenuItem("复制文件名", systemImage: "doc.on.doc", action: {
                    InstanceActions.copy(item.fileName)
                    router.showToast("已复制文件名")
                }),
                LauncherMenuItem("删除到废纸篓", systemImage: "trash", tone: .danger, action: { confirmDeleteMod(item) })
            ])
        ]
    }

    /// 模组页底部：真实 mods 路径与统计。
    private var modsFooter: some View {
        HStack(spacing: LauncherSpace.sm) {
            Image(systemName: "folder")
                .textStyle(.micro, tone: .tertiary)
            LauncherMonoText(modsDirectoryPath, tone: .tertiary, size: 10)
                .lineLimit(1)
            Spacer(minLength: LauncherSpace.sm)
            LauncherMonoText("共 \(modItems.count) 个文件", tone: .tertiary, size: 10)
            LauncherButton("打开模组目录", systemImage: "folder", variant: .ghost, size: .small) {
                openModsDirectory(showsQuickPage: false)
            }
        }
    }

    // MARK: - 截图相册

    /// 截图相册页：真实扫描 `screenshots/`，缩略图受限解码，点击用系统预览打开。
    private var screenshotsPage: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "截图相册",
                    subtitle: "真实读取实例 screenshots/ 目录 · 点击用系统预览打开",
                    accessory: AnyView(
                        HStack(spacing: LauncherSpace.xs) {
                            LauncherBadge("\(screenshotItems.count) 张", tone: screenshotItems.isEmpty ? .neutral : .success)
                            LauncherMonoText(MoreScreenshotLibrary.totalSizeText(screenshotItems), tone: .tertiary, size: 10)
                        }
                    )
                )

                if engine.installedVersions.isEmpty {
                    LauncherEmptyState(
                        systemImage: "photo.on.rectangle.angled",
                        title: "还没有可浏览截图的实例",
                        message: "先在「下载」页安装一个版本，游戏内按 F2 的截图会保存在实例的 screenshots/ 目录。",
                        actionTitle: "前往下载页",
                        onAction: { router.go(.download) }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: LauncherSpace.xxxl * 6)
                } else {
                    screenshotsControls
                    screenshotsGrid
                    screenshotsFooter
                }
            }
        }
    }

    /// 实例选择 + 打开目录 + 刷新。
    private var screenshotsControls: some View {
        HStack(spacing: LauncherSpace.sm) {
            instancePicker

            Spacer(minLength: 0)

            if isLoadingScreenshots {
                LauncherSpinner(size: 12)
            }

            LauncherButton("刷新", systemImage: "arrow.clockwise", variant: .ghost, size: .small) {
                reloadScreenshots()
            }

            LauncherButton("打开截图目录", systemImage: "folder", variant: .secondary, size: .small) {
                openScreenshotsDirectory(showsQuickPage: false)
            }
        }
    }

    /// 截图网格：固定视口，离屏模式用方块占位、不触发异步解码。
    private var screenshotsGrid: some View {
        Group {
            if isLoadingScreenshots && screenshotItems.isEmpty {
                VStack(spacing: LauncherSpace.md) {
                    LauncherSkeleton(height: LauncherSpace.xxxl + LauncherSpace.xl)
                    LauncherSkeleton(height: LauncherSpace.xxxl + LauncherSpace.xl)
                }
                .frame(height: screenshotViewportHeight, alignment: .top)
            } else if screenshotItems.isEmpty {
                LauncherEmptyState(
                    systemImage: "photo.on.rectangle.angled",
                    title: "还没有截图",
                    message: "游戏内按 F2 截的图会出现在 \(screenshotsDirectoryPath)。",
                    actionTitle: "打开截图目录",
                    onAction: { openScreenshotsDirectory(showsQuickPage: false) }
                )
                .frame(maxWidth: .infinity)
                .frame(height: screenshotViewportHeight)
            } else {
                screenshotScrollGrid
                    .frame(maxWidth: .infinity)
                    .frame(height: screenshotViewportHeight, alignment: .top)
            }
        }
    }

    private var screenshotScrollGrid: some View {
        Group {
            if snapshotMode {
                screenshotGridContent(limit: 8)
            } else {
                ScrollView {
                    screenshotGridContent(limit: nil)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func screenshotGridContent(limit: Int?) -> some View {
        let items = limit.map { Array(screenshotItems.prefix($0)) } ?? screenshotItems
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: LauncherSpace.md)],
            spacing: LauncherSpace.md
        ) {
            ForEach(items) { item in
                MoreScreenshotTile(
                    item: item,
                    onOpen: { openScreenshot(item) },
                    onReveal: { InstanceActions.reveal(item.url) },
                    onCopyPath: {
                        InstanceActions.copy(item.url.path)
                        router.showToast("已复制截图路径")
                    },
                    onDelete: { confirmDeleteScreenshot(item) }
                )
            }
        }
    }

    /// 截图页底部：真实路径与总大小。
    private var screenshotsFooter: some View {
        HStack(spacing: LauncherSpace.sm) {
            Image(systemName: "folder")
                .textStyle(.micro, tone: .tertiary)
            LauncherMonoText(screenshotsDirectoryPath, tone: .tertiary, size: 10)
                .lineLimit(1)
            Spacer(minLength: LauncherSpace.sm)
            LauncherMonoText("\(screenshotItems.count) 张 · \(MoreScreenshotLibrary.totalSizeText(screenshotItems))", tone: .tertiary, size: 10)
        }
    }

    // MARK: - 社区与资源

    /// 社区页：真实外链（点击由系统浏览器打开）。
    private var communityPage: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                LauncherSectionHeader(
                    title: "社区与资源",
                    subtitle: "整合包、模组与材质站外链，点击由系统浏览器打开",
                    accessory: AnyView(LauncherBadge("\(externalLinks.count) 个外链", tone: .neutral))
                )
                .padding(.bottom, LauncherSpace.xs)

                ForEach(externalLinks) { link in
                    LauncherListRow(
                        title: link.title,
                        subtitle: link.detail,
                        systemImage: link.systemImage,
                        accessory: AnyView(
                            HStack(spacing: LauncherSpace.xs) {
                                LauncherMonoText(link.url.host() ?? link.url.absoluteString, tone: .tertiary, size: 10)
                                Image(systemName: "arrow.up.right")
                                    .textStyle(.caption, tone: .tertiary)
                            }
                        ),
                        action: {
                            if NSWorkspace.shared.open(link.url) {
                                router.showToast("已在浏览器打开 \(link.title)")
                            } else {
                                router.showToast("无法打开 \(link.title) 链接", tone: .danger)
                            }
                        }
                    )
                    .launcherContextMenu([
                        LauncherMenuGroup(items: [
                            LauncherMenuItem("在浏览器中打开", systemImage: "arrow.up.right", action: {
                                NSWorkspace.shared.open(link.url)
                            }),
                            LauncherMenuItem("复制链接", systemImage: "doc.on.doc", action: {
                                InstanceActions.copy(link.url.absoluteString)
                                router.showToast("已复制链接")
                            })
                        ])
                    ])
                }

                HStack(spacing: LauncherSpace.xs) {
                    LauncherHintIcon("外链只做跳转，启动器不会上传任何本地数据。")
                    Text("外链由系统浏览器打开，本地数据不会上传。")
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.top, LauncherSpace.xs)
            }
        }
    }

    // MARK: - 快捷键

    /// 快捷键页：只列出 App 壳真实注册的组合键，并标注作用范围。
    private var shortcutsPage: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "快捷键说明",
                    subtitle: "只列出当前构建里真实注册的快捷键",
                    accessory: AnyView(LauncherBadge("\(shortcutEntries.count) 个", tone: .neutral))
                )

                HStack(alignment: .top, spacing: LauncherSpace.xl) {
                    shortcutColumn(Array(shortcutEntries.prefix(3)))
                    shortcutColumn(Array(shortcutEntries.dropFirst(3)))
                }

                LauncherBanner(
                    title: "快捷键由 App 壳统一注册",
                    message: "未列出的组合键当前没有绑定；macOS 系统级快捷键（如 ⌘Q）由系统接管。",
                    tone: .info
                )
            }
        }
    }

    private func shortcutColumn(_ items: [MoreShortcutEntry]) -> some View {
        VStack(spacing: LauncherSpace.xs) {
            ForEach(items) { shortcut in
                shortcutRow(shortcut)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortcutRow(_ shortcut: MoreShortcutEntry) -> some View {
        HStack(spacing: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text(shortcut.title)
                    .textStyle(.bodyStrong)
                    .lineLimit(1)
                Text(shortcut.scope)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: LauncherSpace.sm)
            Text(shortcut.keys)
                .font(LauncherTextStyle.mono.font)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.horizontal, LauncherSpace.sm)
                .frame(height: LauncherControl.small - LauncherSpace.xs)
                .background {
                    RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                        .fill(theme.colors.surfaceSubtle)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                        .strokeBorder(theme.colors.stroke, lineWidth: 1)
                }
                .accessibilityLabel(shortcut.keys)
        }
        .frame(minHeight: LauncherSpace.xxxl - LauncherSpace.sm)
    }

    // MARK: - 关于

    /// 关于页：真实构建信息、真实环境统计、真实更新检查与设计系统入口。
    private var aboutPage: some View {
        let build = LauncherBuildInfo.current
        return LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "关于",
                    subtitle: "方块启动器 · SwiftUI 构建",
                    accessory: AnyView(LauncherBadge(build.versionText, tone: .accent))
                )

                LauncherSettingRow("版本", subtitle: "可执行文件构建信息（Bundle 版本 / 内置兜底）") {
                    LauncherMonoText(build.versionText, tone: .primary)
                }
                LauncherSettingRow("构建号", subtitle: "构建日期 + 当日分钟数") {
                    LauncherMonoText(build.buildNumber, tone: .primary)
                }
                LauncherSettingRow("构建时间", subtitle: "可执行文件的真实修改时间") {
                    LauncherMonoText(build.buildDateTimeText, tone: .primary)
                }
                LauncherSettingRow("提交", subtitle: "从仓库目录启动时读取 git 短提交") {
                    LauncherMonoText(build.commit, tone: .primary)
                }
                LauncherSettingRow("已安装版本", subtitle: "本地 versions 目录真实扫描") {
                    LauncherMonoText("\(engine.installedVersions.count) 个", tone: .primary)
                }
                LauncherSettingRow("Java 运行时", subtitle: "本机真实检测到的运行时") {
                    LauncherMonoText("\(engine.javaRuntimes.count) 个", tone: .primary)
                }
                LauncherSettingRow("更新源", subtitle: engine.settings.updateFeedURL.isEmpty ? "未配置更新源（本地构建）" : engine.settings.updateFeedURL) {
                    LauncherButton("配置", systemImage: "gearshape", variant: .ghost, size: .small) {
                        router.go(.settings, settingsSection: "about")
                    }
                }

                HStack(spacing: LauncherSpace.sm) {
                    LauncherButton(
                        "检查更新",
                        systemImage: "arrow.triangle.2.circlepath",
                        variant: .secondary,
                        size: .small,
                        isLoading: updateChecker.status.isChecking
                    ) {
                        checkForUpdates()
                    }

                    if let downloadURL = updateChecker.downloadURL {
                        LauncherButton("打开下载页", systemImage: "arrow.down.circle", variant: .primary, size: .small) {
                            NSWorkspace.shared.open(downloadURL)
                        }
                    }

                    LauncherButton("设计系统画廊", systemImage: "square.grid.2x2", variant: .secondary, size: .small) {
                        onOpenGallery()
                    }

                    LauncherButton("复制诊断信息", systemImage: "doc.on.doc", variant: .ghost, size: .small) {
                        copyDiagnostics()
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: LauncherSpace.xs) {
                    LauncherStatusDot(tone: updateStatusTone)
                    Text(updateChecker.status.message)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                    if let lastCheckedText = updateChecker.lastCheckedText {
                        LauncherMonoText("上次检查 \(lastCheckedText)", tone: .tertiary, size: 10)
                    }
                    Spacer(minLength: LauncherSpace.sm)
                    Text("数据全部保存在本机")
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - 快捷操作页

    /// 快捷操作页：全部真实目录动作 + 真实窗口重置 + 真实日志导出。
    private var quickActionsPage: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "快捷操作",
                    subtitle: "打开真实目录、导出真实日志、重置真实窗口，全部在本地执行",
                    accessory: AnyView(LauncherMonoText("本机", tone: .tertiary))
                )

                VStack(spacing: LauncherSpace.md) {
                    quickActionRow(
                        ("打开游戏目录", "folder", { openGameDirectory(showsQuickPage: false) }),
                        ("打开实例目录", "cube", { openInstanceDirectory(showsQuickPage: false) }),
                        ("打开 versions 目录", "square.stack.3d.up", { openVersionsDirectory(showsQuickPage: false) })
                    )
                    quickActionRow(
                        ("打开备份目录", "externaldrive.badge.timemachine", { openBackupsDirectory(showsQuickPage: false) }),
                        ("打开模组目录", "puzzlepiece.extension", { openModsDirectory(showsQuickPage: false) }),
                        ("打开截图目录", "photo.on.rectangle.angled", { openScreenshotsDirectory(showsQuickPage: false) })
                    )
                    quickActionRow(
                        ("打开日志文件夹", "doc.text.magnifyingglass", { openLogsFolder(showsQuickPage: false) }),
                        ("打开启动器缓存", "shippingbox", { openCacheDirectory(showsQuickPage: false) }),
                        ("导出日志", "square.and.arrow.up", { exportLogs(showsQuickPage: false) })
                    )
                    quickActionRow(
                        ("重置窗口布局", "rectangle.3.group", { resetWindowLayout(showsQuickPage: false) }),
                        ("复制诊断信息", "stethoscope", copyDiagnostics),
                        ("刷新环境", "arrow.clockwise", refreshEnvironment)
                    )
                }

                HStack(spacing: LauncherSpace.xs) {
                    LauncherHintIcon("日志与诊断的导出目录固定为 ~/Library/Logs/BlockLauncher/，与设置页使用同一落点。")
                    Text("日志导出到 ~/Library/Logs/BlockLauncher/（与设置页一致）")
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                HStack(spacing: LauncherSpace.sm) {
                    LauncherStatusDot(tone: actionTone)
                    Text(actionMessage)
                        .textStyle(.micro, tone: .secondary)
                        .lineLimit(2)
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherMonoText("窗口 \(windowSizeText)", tone: .tertiary, size: 10)
                    LauncherMonoText("默认 \(Int(LauncherWindowActions.defaultSize.width)) × \(Int(LauncherWindowActions.defaultSize.height))", tone: .tertiary, size: 10)
                }
            }
        }
    }

    /// 三个一组的真实动作按钮。
    private func quickActionRow(
        _ first: (String, String, () -> Void),
        _ second: (String, String, () -> Void),
        _ third: (String, String, () -> Void)
    ) -> some View {
        HStack(spacing: LauncherSpace.md) {
            quickActionButton(first)
            quickActionButton(second)
            quickActionButton(third)
        }
    }

    private func quickActionButton(_ item: (String, String, () -> Void)) -> some View {
        LauncherButton(
            item.0,
            systemImage: item.1,
            variant: .secondary,
            size: .medium,
            isFullWidth: true,
            action: item.2
        )
    }

    // MARK: - 文案与状态

    /// 当前分区标题。
    private var selectedTitle: String {
        selection.title
    }

    /// 当前分区说明：全部来自真实状态，不写死演示数据。
    private var selectedSubtitle: String {
        switch selection {
        case .logs:
            return "\(engine.statusText) · 共 \(engine.logLines.count) 行输出"
        case .backup:
            return "\(backupItems.count) 个备份 · 占用 \(backupTotalSizeText) · \(MoreBackupService.backupsFolderName)/ 目录"
        case .mods:
            return "启用 \(modCounts.enabled) · 禁用 \(modCounts.disabled) · \(modItems.count) 个文件"
        case .screenshots:
            return "\(screenshotItems.count) 张截图 · 占用 \(MoreScreenshotLibrary.totalSizeText(screenshotItems))"
        case .community:
            return "整合包、模组与材质站外链"
        case .shortcuts:
            return "高频操作的键盘入口（与真实注册一致）"
        case .about:
            return "\(LauncherBuildInfo.current.summary) · 已安装 \(engine.installedVersions.count) 个版本"
        case .quick:
            return "常用维护动作，全部在本地执行"
        }
    }

    /// 外部链接。
    private var externalLinks: [MoreExternalLink] {
        [
            MoreExternalLink(
                id: "modrinth",
                title: "Modrinth",
                detail: "开源模组与整合包托管平台",
                systemImage: "shippingbox.fill",
                url: URL(string: "https://modrinth.com")!
            ),
            MoreExternalLink(
                id: "curseforge",
                title: "CurseForge",
                detail: "模组、整合包与材质资源",
                systemImage: "square.stack.3d.up.fill",
                url: URL(string: "https://www.curseforge.com/minecraft")!
            ),
            MoreExternalLink(
                id: "minecraft",
                title: "Minecraft 官网",
                detail: "版本公告与官方新闻",
                systemImage: "globe.asia.australia.fill",
                url: URL(string: "https://www.minecraft.net")!
            )
        ]
    }

    /// 运行状态色调。
    private var logStatusTone: LauncherBadgeTone {
        if case .failed = engine.phase { return .danger }
        if engine.isBusy { return .warning }
        if engine.installedVersions.isEmpty { return .neutral }
        return .success
    }

    /// 运行状态图标。
    private var logStatusIcon: String {
        if case .failed = engine.phase { return "xmark.octagon.fill" }
        if engine.isBusy { return "arrow.triangle.2.circlepath" }
        if case .running = engine.phase { return "play.circle.fill" }
        if engine.installedVersions.isEmpty { return "tray" }
        return "checkmark.circle.fill"
    }

    /// 更新状态色调。
    private var updateStatusTone: LauncherBadgeTone {
        switch updateChecker.status {
        case .available: return .accent
        case .upToDate: return .success
        case .failed: return .danger
        case .noFeed, .idle, .checking: return .neutral
        }
    }

    /// 日志行语义色调。
    private func logTone(for line: String) -> LauncherTextTone {
        let lowered = line.lowercased()
        let errorKeywords = ["error", "exception", "fatal", "失败", "错误", "崩溃", "cannot"]
        if errorKeywords.contains(where: { lowered.contains($0) }) { return .danger }
        let warningKeywords = ["warn", "警告", "deprecated", "重试"]
        if warningKeywords.contains(where: { lowered.contains($0) }) { return .warning }
        return .secondary
    }

    // MARK: - 派生数据

    /// 真实游戏根目录。
    private var gameDirectoryRoot: URL {
        engine.settings.resolvedGameDirectory
    }

    /// 实际生效的实例 id：交互模式下用用户选择；离屏快照模式下退回到第一个已安装实例，
    /// 保证快照内容确定、不依赖点击或异步扫描。
    private var effectiveVersionID: String {
        if !selectedVersionID.isEmpty { return selectedVersionID }
        guard snapshotMode else { return "" }
        return engine.installedVersions.first?.id ?? ""
    }

    /// 当前选中实例的真实目录（关闭版本隔离时为游戏根目录）。
    private var selectedInstanceDirectory: URL {
        guard !effectiveVersionID.isEmpty else { return gameDirectoryRoot }
        return engine.settings.gameDirectory(for: effectiveVersionID)
    }

    private var modsDirectoryPath: String {
        MoreModLibrary.modsDirectory(in: selectedInstanceDirectory).path
    }

    private var modsDirectoryExists: Bool {
        FileManager.default.fileExists(atPath: modsDirectoryPath)
    }

    private var screenshotsDirectoryPath: String {
        MoreScreenshotLibrary.screenshotsDirectory(in: selectedInstanceDirectory).path
    }

    private var backupTotalSizeText: String {
        MoreBackupService.totalSizeText(gameDirectory: gameDirectoryRoot)
    }

    private var hasBackupContent: Bool {
        engine.installedVersions.isEmpty ? false : MoreBackupService.entries(instanceDirectory: selectedInstanceDirectory).contains(where: \.exists)
    }

    private var modCounts: (enabled: Int, disabled: Int) {
        MoreModLibrary.counts(modItems)
    }

    /// 过滤 + 排序后的模组列表。
    private var visibleModItems: [MoreModItem] {
        MoreModLibrary.sorted(MoreModLibrary.filtered(modItems, query: modQuery), ascending: modSortAscending)
    }

    /// 实例下拉选项。
    private var instanceOptions: [LauncherSegment<String>] {
        engine.installedVersions.map {
            LauncherSegment(id: $0.id, title: $0.id, systemImage: "cube")
        }
    }

    /// 实例选择器（带真实目录提示）。
    private var instancePicker: some View {
        HStack(spacing: LauncherSpace.sm) {
            LauncherLabel("实例")
            LauncherDropdown(
                options: instanceOptions,
                selection: instanceSelectionBinding,
                placeholder: "选择实例"
            )
            .frame(width: 220)
        }
    }

    /// 实例下拉绑定：快照模式下读取 `effectiveVersionID`，交互模式写回真实选择并重新扫描。
    private var instanceSelectionBinding: Binding<String> {
        Binding(
            get: { effectiveVersionID },
            set: { newValue in
                selectedVersionID = newValue
                reloadMods()
                reloadScreenshots()
            }
        )
    }

    /// 工具收藏集合（持久化格式：逗号分隔的 id）。
    private var favoriteToolIDs: Set<String> {
        Set(favoriteTools.split(separator: ",").map(String.init))
    }

    /// 收藏置顶后的工具顺序。
    private var orderedTools: [MoreToolDefinition] {
        let favorites = Self.tools.filter { favoriteToolIDs.contains($0.id) }
        let others = Self.tools.filter { !favoriteToolIDs.contains($0.id) }
        return favorites + others
    }

    /// 工具真实徽标：日志行数 / 备份数量 / 模组启停 / 截图张数。
    private func toolBadge(for section: MoreSection) -> String? {
        switch section {
        case .logs:
            return engine.logLines.isEmpty ? nil : "\(engine.logLines.count) 行"
        case .backup:
            return backupItems.isEmpty ? nil : "\(backupItems.count) 个"
        case .mods:
            guard !modItems.isEmpty else { return nil }
            return "\(modCounts.enabled)/\(modItems.count)"
        case .screenshots:
            return screenshotItems.isEmpty ? nil : "\(screenshotItems.count) 张"
        case .community, .shortcuts, .about, .quick:
            return nil
        }
    }

    /// 工具对应的真实目录（用于右键「在访达中显示」/ 复制路径）。
    private func toolDirectoryURL(_ section: MoreSection) -> URL? {
        switch section {
        case .logs:
            return MoreLogExporter.logsDirectory()
        case .backup:
            return MoreBackupService.backupsDirectory(gameDirectory: gameDirectoryRoot)
        case .mods:
            return MoreModLibrary.modsDirectory(in: selectedInstanceDirectory)
        case .screenshots:
            return MoreScreenshotLibrary.screenshotsDirectory(in: selectedInstanceDirectory)
        case .quick:
            return gameDirectoryRoot
        case .community, .shortcuts, .about:
            return nil
        }
    }

    // MARK: - 生命周期

    /// 页面出现：消费路由跳转、同步实例、加载真实数据。
    /// 离屏快照模式只做同步状态初始化，不读盘、不启动异步任务，保证快照确定。
    private func handleAppear() {
        consumePendingSection()
        synchronizeSelection()
        refreshWindowSize()
        guard !snapshotMode else {
            backupItems = []
            modItems = []
            screenshotItems = []
            isLoadingBackups = false
            isLoadingMods = false
            isLoadingScreenshots = false
            return
        }
        reloadBackups()
        reloadInstanceLibraries()
    }

    /// 消费 `router.pendingMoreSection`（消费后置 nil）。
    private func consumePendingSection() {
        guard let pending = router.pendingMoreSection else { return }
        router.pendingMoreSection = nil
        guard let section = MoreSection.from(pending: pending) else { return }
        select(section)
        switch section {
        case .backup: reloadBackups()
        case .mods: reloadMods()
        case .screenshots: reloadScreenshots()
        case .quick: refreshWindowSize()
        default: break
        }
    }

    /// 切换分区。
    private func select(_ section: MoreSection) {
        guard selection != section else { return }
        withAnimation(LauncherMotion.smooth) {
            selection = section
        }
    }

    /// 让选中实例始终指向真实已安装版本。
    private func synchronizeSelection() {
        let ids = engine.installedVersions.map(\.id)
        guard !ids.isEmpty else {
            selectedVersionID = ""
            lastLoadedVersionID = ""
            return
        }
        if !ids.contains(selectedVersionID) {
            if let active = engine.activeVersionID, ids.contains(active) {
                selectedVersionID = active
            } else {
                selectedVersionID = ids[0]
            }
        }
    }

    /// 切换实例后加载对应模组与截图（同一个实例不重复扫描）。
    private func reloadInstanceLibraries() {
        guard !selectedVersionID.isEmpty else {
            modItems = []
            screenshotItems = []
            lastLoadedVersionID = ""
            return
        }
        guard selectedVersionID != lastLoadedVersionID else { return }
        lastLoadedVersionID = selectedVersionID
        reloadMods()
        reloadScreenshots()
    }

    // MARK: - 真实数据加载

    /// 后台扫描真实备份列表（离屏快照模式不读盘）。
    private func reloadBackups() {
        guard !snapshotMode else {
            isLoadingBackups = false
            return
        }
        let gameDirectory = gameDirectoryRoot
        isLoadingBackups = true
        Task {
            let items = await Task.detached(priority: .userInitiated) {
                MoreBackupService.list(gameDirectory: gameDirectory)
            }.value
            backupItems = items
            isLoadingBackups = false
        }
    }

    /// 后台扫描真实模组列表（离屏快照模式不读盘）。
    private func reloadMods() {
        guard !snapshotMode else {
            isLoadingMods = false
            return
        }
        let versionID = effectiveVersionID
        guard !versionID.isEmpty else {
            modItems = []
            isLoadingMods = false
            return
        }
        let directory = MoreModLibrary.modsDirectory(in: engine.settings.gameDirectory(for: versionID))
        isLoadingMods = true
        Task {
            let items = await Task.detached(priority: .userInitiated) {
                MoreModLibrary.scan(in: directory)
            }.value
            guard effectiveVersionID == versionID else { return }
            modItems = items
            isLoadingMods = false
        }
    }

    /// 后台扫描真实截图列表（离屏快照模式不读盘）。
    private func reloadScreenshots() {
        guard !snapshotMode else {
            isLoadingScreenshots = false
            return
        }
        let versionID = effectiveVersionID
        guard !versionID.isEmpty else {
            screenshotItems = []
            isLoadingScreenshots = false
            return
        }
        let directory = MoreScreenshotLibrary.screenshotsDirectory(in: engine.settings.gameDirectory(for: versionID))
        isLoadingScreenshots = true
        Task {
            let items = await Task.detached(priority: .userInitiated) {
                MoreScreenshotLibrary.scan(in: directory)
            }.value
            guard effectiveVersionID == versionID else { return }
            screenshotItems = items
            isLoadingScreenshots = false
        }
    }

    /// 刷新窗口尺寸文本（真实主窗口）。
    private func refreshWindowSize() {
        windowSizeText = LauncherWindowActions.mainWindowSizeText
    }

    // MARK: - 备份动作

    /// 立即备份：`ditto` 真实打包，完成后刷新列表。
    private func startBackup() {
        guard !isCreatingBackup else { return }
        let versionID = selectedVersionID
        guard !versionID.isEmpty else {
            router.showToast("请先选择要备份的实例", tone: .warning)
            return
        }
        let gameDirectory = gameDirectoryRoot
        let instanceDirectory = engine.settings.gameDirectory(for: versionID)
        let entries = MoreBackupService.entries(instanceDirectory: instanceDirectory).filter(\.exists)
        guard !entries.isEmpty else {
            router.showToast("实例没有可备份的内容", tone: .warning)
            return
        }
        isCreatingBackup = true
        Task {
            do {
                let item = try await Task.detached(priority: .userInitiated) {
                    try MoreBackupService.createBackup(
                        versionID: versionID,
                        instanceDirectory: instanceDirectory,
                        gameDirectory: gameDirectory
                    )
                }.value
                let items = await Task.detached(priority: .userInitiated) {
                    MoreBackupService.list(gameDirectory: gameDirectory)
                }.value
                backupItems = items
                isCreatingBackup = false
                router.showToast("备份完成：\(item.name) · \(item.sizeText)", tone: .success)
            } catch {
                isCreatingBackup = false
                router.showToast("备份失败：\(error.localizedDescription)", tone: .danger)
            }
        }
    }

    /// 恢复前二次确认（覆盖提示）。
    private func confirmRestore(_ item: MoreBackupItem) {
        let targetID = selectedVersionID
        guard !targetID.isEmpty else {
            router.showToast("请先选择要恢复到的实例", tone: .warning)
            return
        }
        router.showDialog(
            LauncherDialogRequest(
                title: "恢复备份？",
                message: "将把「\(item.name)」解压到实例「\(targetID)」的目录，同名文件会被覆盖。建议先对当前状态做一次备份。",
                confirmTitle: "覆盖并恢复",
                isDestructive: true,
                onConfirm: { performRestore(item, targetID: targetID) }
            )
        )
    }

    /// 真实解压恢复。
    private func performRestore(_ item: MoreBackupItem, targetID: String) {
        let gameDirectory = gameDirectoryRoot
        let instanceDirectory = engine.settings.gameDirectory(for: targetID)
        restoringBackupID = item.url
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try MoreBackupService.restore(item, instanceDirectory: instanceDirectory, gameDirectory: gameDirectory)
                }.value
                restoringBackupID = nil
                router.showToast("已恢复到实例 \(targetID)", tone: .success)
                reloadBackups()
                reloadMods()
                reloadScreenshots()
            } catch {
                restoringBackupID = nil
                router.showToast("恢复失败：\(error.localizedDescription)", tone: .danger)
            }
        }
    }

    /// 删除备份前二次确认，确认后移到废纸篓。
    private func confirmDeleteBackup(_ item: MoreBackupItem) {
        router.showDialog(
            LauncherDialogRequest(
                title: "删除备份？",
                message: "「\(item.name)」会被移到废纸篓，可在废纸篓中恢复。",
                confirmTitle: "移到废纸篓",
                isDestructive: true,
                onConfirm: {
                    do {
                        try MoreBackupService.delete(item, gameDirectory: gameDirectoryRoot)
                        router.showToast("备份已移到废纸篓", tone: .success)
                        reloadBackups()
                    } catch {
                        router.showToast("删除失败：\(error.localizedDescription)", tone: .danger)
                    }
                }
            )
        )
    }

    // MARK: - 模组动作

    /// 启用 / 禁用：真实重命名后重新扫描。
    private func toggleMod(_ item: MoreModItem) {
        guard !busyModURLs.contains(item.url) else { return }
        busyModURLs.insert(item.url)
        let enabling = !item.isEnabled
        do {
            _ = try MoreModLibrary.setEnabled(item, enabled: enabling)
            router.showToast(enabling ? "已启用 \(item.displayName)" : "已禁用 \(item.displayName)", tone: .success)
            reloadMods()
        } catch {
            router.showToast("操作失败：\(error.localizedDescription)", tone: .danger)
        }
        busyModURLs.remove(item.url)
    }

    /// 删除模组前二次确认。
    private func confirmDeleteMod(_ item: MoreModItem) {
        router.showDialog(
            LauncherDialogRequest(
                title: "删除模组？",
                message: "「\(item.displayName)」会被移到废纸篓，可在废纸篓中恢复。",
                confirmTitle: "移到废纸篓",
                isDestructive: true,
                onConfirm: {
                    do {
                        try MoreModLibrary.delete(item)
                        router.showToast("模组已移到废纸篓", tone: .success)
                        reloadMods()
                    } catch {
                        router.showToast("删除失败：\(error.localizedDescription)", tone: .danger)
                    }
                }
            )
        )
    }

    // MARK: - 截图动作

    /// 用系统默认预览打开截图。
    private func openScreenshot(_ item: MoreScreenshotItem) {
        if NSWorkspace.shared.open(item.url) {
            router.showToast("已用系统预览打开截图")
        } else {
            router.showToast("无法打开截图：\(item.fileName)", tone: .danger)
        }
    }

    /// 删除截图前二次确认。
    private func confirmDeleteScreenshot(_ item: MoreScreenshotItem) {
        router.showDialog(
            LauncherDialogRequest(
                title: "删除截图？",
                message: "「\(item.fileName)」会被移到废纸篓，可在废纸篓中恢复。",
                confirmTitle: "移到废纸篓",
                isDestructive: true,
                onConfirm: {
                    do {
                        try MoreScreenshotLibrary.delete(item)
                        router.showToast("截图已移到废纸篓", tone: .success)
                        reloadScreenshots()
                    } catch {
                        router.showToast("删除失败：\(error.localizedDescription)", tone: .danger)
                    }
                }
            )
        )
    }

    // MARK: - 日志动作

    /// 导出日志：真实写入日志目录，成功后内联给出「在访达显示」。
    private func exportLogs(showsQuickPage: Bool) {
        do {
            let export = try MoreLogExporter.export(
                logs: engine.logLines,
                commandLine: engine.lastCommandLine,
                exitCode: engine.lastExitCode,
                installedVersionCount: engine.installedVersions.count,
                javaRuntimeCount: engine.javaRuntimes.count,
                gameDirectoryPath: gameDirectoryRoot.path
            )
            lastLogExport = export
            flashLogFeedback("日志已导出", tone: .success)
            actionMessage = "日志已导出：\(export.url.path)（\(export.sizeText)）"
            actionTone = .success
            router.showToast("日志已导出到 \(export.url.deletingLastPathComponent().path)", tone: .success)
        } catch {
            flashLogFeedback("导出失败", tone: .danger)
            actionMessage = "日志导出失败：\(error.localizedDescription)"
            actionTone = .danger
            router.showToast("日志导出失败：\(error.localizedDescription)", tone: .danger)
        }
        if showsQuickPage {
            select(.quick)
        }
    }

    /// 打开真实日志文件夹。
    private func openLogsFolder(showsQuickPage: Bool) {
        do {
            let directory = try MoreLogExporter.ensureLogsDirectory()
            if InstanceActions.open(directory) {
                actionMessage = "已打开日志文件夹：\(directory.path)"
                actionTone = .success
                router.showToast("已打开日志文件夹")
            } else {
                actionMessage = "无法打开日志文件夹：\(directory.path)"
                actionTone = .danger
                router.showToast("无法打开日志文件夹", tone: .danger)
            }
        } catch {
            actionMessage = "无法创建日志文件夹：\(error.localizedDescription)"
            actionTone = .danger
            router.showToast("无法创建日志文件夹", tone: .danger)
        }
        if showsQuickPage {
            select(.quick)
        }
    }

    /// 复制全部日志。
    private func copyLog() {
        InstanceActions.copy(engine.logLines.joined(separator: "\n"))
        flashLogFeedback("已复制 \(engine.logLines.count) 行", tone: .success)
        router.showToast("已复制全部日志")
    }

    /// 复制最近 N 行日志。
    private func copyRecentLog(_ count: Int) {
        let lines = engine.logLines.suffix(count)
        InstanceActions.copy(lines.joined(separator: "\n"))
        flashLogFeedback("已复制最近 \(lines.count) 行", tone: .success)
        router.showToast("已复制最近 \(lines.count) 行日志")
    }

    /// 复制诊断信息（构建 + 环境 + 最近日志）。
    private func copyDiagnostics() {
        let text = MoreLogExporter.diagnosticsText(
            logs: engine.logLines,
            commandLine: engine.lastCommandLine,
            exitCode: engine.lastExitCode,
            installedVersionCount: engine.installedVersions.count,
            javaRuntimeCount: engine.javaRuntimes.count,
            gameDirectoryPath: gameDirectoryRoot.path
        )
        InstanceActions.copy(text)
        flashLogFeedback("诊断信息已复制", tone: .success)
        actionMessage = "已复制诊断信息（\(text.count) 字符）"
        actionTone = .success
        router.showToast("诊断信息已复制")
    }

    /// 清空日志前二次确认。
    private func confirmClearLog() {
        guard !engine.logLines.isEmpty else { return }
        router.showDialog(
            LauncherDialogRequest(
                title: "清空日志？",
                message: "将清空当前 \(engine.logLines.count) 行运行时日志，已导出的文件不受影响。",
                confirmTitle: "清空",
                isDestructive: true,
                onConfirm: {
                    engine.clearLog()
                    flashLogFeedback("日志已清空", tone: .neutral)
                    router.showToast("日志已清空", tone: .info)
                }
            )
        )
    }

    // MARK: - 快捷目录动作

    /// 打开游戏目录。
    private func openGameDirectory(showsQuickPage: Bool) {
        openDirectory(gameDirectoryRoot, label: "游戏目录", ensure: true, showsQuickPage: showsQuickPage)
    }

    /// 打开当前实例目录。
    private func openInstanceDirectory(showsQuickPage: Bool) {
        openDirectory(selectedInstanceDirectory, label: "实例目录", ensure: true, showsQuickPage: showsQuickPage)
    }

    /// 打开 versions 目录。
    private func openVersionsDirectory(showsQuickPage: Bool) {
        openDirectory(engine.installation.versionsDirectory, label: "versions 目录", ensure: true, showsQuickPage: showsQuickPage)
    }

    /// 打开备份目录（不存在时真实创建）。
    private func openBackupsDirectory(showsQuickPage: Bool) {
        openDirectory(
            MoreBackupService.backupsDirectory(gameDirectory: gameDirectoryRoot),
            label: "备份目录",
            ensure: true,
            showsQuickPage: showsQuickPage
        )
    }

    /// 打开模组目录（不存在时真实创建）。
    private func openModsDirectory(showsQuickPage: Bool) {
        openDirectory(MoreModLibrary.modsDirectory(in: selectedInstanceDirectory), label: "模组目录", ensure: true, showsQuickPage: showsQuickPage)
    }

    /// 打开截图目录（不存在时真实创建）。
    private func openScreenshotsDirectory(showsQuickPage: Bool) {
        openDirectory(
            MoreScreenshotLibrary.screenshotsDirectory(in: selectedInstanceDirectory),
            label: "截图目录",
            ensure: true,
            showsQuickPage: showsQuickPage
        )
    }

    /// 打开启动器缓存目录。
    private func openCacheDirectory(showsQuickPage: Bool) {
        openDirectory(engine.installation.cacheDirectory, label: "启动器缓存目录", ensure: true, showsQuickPage: showsQuickPage)
    }

    /// 重置窗口布局：调用真实 `LauncherWindowActions.resetLayout()` 并反馈前后尺寸。
    private func resetWindowLayout(showsQuickPage: Bool) {
        refreshWindowSize()
        guard !snapshotMode else {
            actionMessage = "离屏截图模式不执行窗口操作。"
            actionTone = .warning
            router.showToast("离屏截图模式不执行窗口操作", tone: .warning)
            if showsQuickPage { select(.quick) }
            return
        }
        let before = LauncherWindowActions.mainWindowSizeText
        let success = LauncherWindowActions.resetLayout()
        refreshWindowSize()
        if success {
            actionMessage = "窗口布局已重置：\(before) → \(windowSizeText)"
            actionTone = .success
            router.showToast("窗口布局已重置为 \(Int(LauncherWindowActions.defaultSize.width)) × \(Int(LauncherWindowActions.defaultSize.height))")
        } else {
            actionMessage = "未找到主窗口，无法重置窗口布局。"
            actionTone = .danger
            router.showToast("未找到主窗口", tone: .danger)
        }
        if showsQuickPage { select(.quick) }
    }

    /// 刷新 Java 与实例列表。
    private func refreshEnvironment() {
        Task {
            await engine.refreshEnvironment()
            synchronizeSelection()
            reloadBackups()
            reloadInstanceLibraries()
            refreshWindowSize()
            actionMessage = "已刷新环境：\(engine.installedVersions.count) 个版本 · \(engine.javaRuntimes.count) 个 Java"
            actionTone = .success
            router.showToast("已刷新 Java 与实例列表")
        }
    }

    /// 通用打开目录：存在性检查 + 必要时创建 + 真实反馈。
    private func openDirectory(_ url: URL, label: String, ensure: Bool, showsQuickPage: Bool) {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path), ensure {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                actionMessage = "无法创建\(label)：\(url.path)"
                actionTone = .danger
                router.showToast("无法创建\(label)", tone: .danger)
                if showsQuickPage { select(.quick) }
                return
            }
        }
        guard fileManager.fileExists(atPath: url.path) else {
            actionMessage = "\(label)不存在：\(url.path)"
            actionTone = .warning
            router.showToast("\(label)不存在", tone: .warning)
            if showsQuickPage { select(.quick) }
            return
        }
        if InstanceActions.open(url) {
            actionMessage = "已打开\(label)：\(url.path)"
            actionTone = .success
            router.showToast("已打开\(label)")
        } else {
            actionMessage = "无法打开\(label)：\(url.path)"
            actionTone = .danger
            router.showToast("无法打开\(label)", tone: .danger)
        }
        if showsQuickPage { select(.quick) }
    }

    // MARK: - 其他动作

    /// 检查更新：走真实 `UpdateChecker`，未配置更新源时明确提示。
    private func checkForUpdates() {
        guard !updateChecker.status.isChecking else { return }
        Task {
            await updateChecker.check(feedURL: engine.settings.updateFeedURL)
            switch updateChecker.status {
            case .available(_, let latest):
                router.showToast("发现新版本 v\(latest.version)", tone: .info)
            case .upToDate(let current):
                router.showToast("已是最新版本 v\(current)", tone: .success)
            case .failed(let message):
                router.showToast("检查更新失败：\(message)", tone: .warning)
            case .noFeed:
                router.showToast("未配置更新源，可在「设置 → 关于」填写", tone: .info)
            case .idle, .checking:
                break
            }
        }
    }

    /// 标记 / 取消收藏工具（收藏会置顶）。
    private func toggleFavorite(_ toolID: String) {
        var ids = favoriteToolIDs
        let isFavorite = ids.contains(toolID)
        if isFavorite {
            ids.remove(toolID)
        } else {
            ids.insert(toolID)
        }
        favoriteTools = ids.sorted().joined(separator: ",")
        router.showToast(isFavorite ? "已取消收藏" : "已收藏并置顶", tone: isFavorite ? .info : .success)
    }

    /// 日志卡头部的短暂反馈（2 秒后自动消失，纯 UI 状态）。
    private func flashLogFeedback(_ message: String, tone: LauncherBadgeTone) {
        logFeedbackMessage = message
        logFeedbackTone = tone
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if logFeedbackMessage == message {
                logFeedbackMessage = nil
            }
        }
    }

    /// 日志自动滚到底部。
    private func scrollLogToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = engine.logLines.indices.last else { return }
        if animated {
            withAnimation(LauncherMotion.smooth) {
                proxy.scrollTo(last, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    // MARK: - 静态数据

    /// 工具列表定义：与页内分区一一对应。
    private static let tools: [MoreToolDefinition] = [
        MoreToolDefinition(
            id: MoreSection.logs.rawValue,
            title: "日志与诊断",
            subtitle: "真实启动日志、导出与诊断信息",
            systemImage: "doc.text.magnifyingglass",
            section: .logs
        ),
        MoreToolDefinition(
            id: MoreSection.backup.rawValue,
            title: "实例备份",
            subtitle: "把世界与模组配置打包成 zip",
            systemImage: "externaldrive.badge.timemachine",
            section: .backup
        ),
        MoreToolDefinition(
            id: MoreSection.mods.rawValue,
            title: "模组管理",
            subtitle: "扫描、启用 / 禁用与删除模组",
            systemImage: "puzzlepiece.extension.fill",
            section: .mods
        ),
        MoreToolDefinition(
            id: MoreSection.screenshots.rawValue,
            title: "截图相册",
            subtitle: "浏览、预览与清理游戏截图",
            systemImage: "photo.on.rectangle.angled",
            section: .screenshots
        ),
        MoreToolDefinition(
            id: MoreSection.community.rawValue,
            title: "社区与资源",
            subtitle: "整合包、模组与材质站外链",
            systemImage: "globe.asia.australia.fill",
            section: .community
        ),
        MoreToolDefinition(
            id: MoreSection.about.rawValue,
            title: "关于启动器",
            subtitle: "真实构建信息与更新检查",
            systemImage: "info.circle.fill",
            section: .about
        )
    ]

    /// 快捷键说明：只列 App 壳真实注册的组合键（见 `LauncherAppShell.shortcutButtons`）。
    private var shortcutEntries: [MoreShortcutEntry] {
        [
            MoreShortcutEntry(id: "tabs", keys: "⌘1 – ⌘4", title: "切换一级页面", scope: "启动 / 下载 / 设置 / 更多"),
            MoreShortcutEntry(id: "gallery", keys: "⌘⇧D", title: "打开设计系统画廊", scope: "全局"),
            MoreShortcutEntry(id: "refresh", keys: "⌘R", title: "刷新 Java 与实例列表", scope: "全局"),
            MoreShortcutEntry(id: "theme", keys: "⌘⇧T", title: "切换深 / 浅主题", scope: "全局"),
            MoreShortcutEntry(id: "settings", keys: "⌘,", title: "打开设置", scope: "全局"),
            MoreShortcutEntry(id: "launch", keys: "⌘↩", title: "启动当前选中实例", scope: "启动页")
        ]
    }
}

// MARK: - 分区

/// 更多页的 8 个分区；原始值即路由 `pendingMoreSection` 的取值。
private enum MoreSection: String, CaseIterable, Identifiable {
    case logs
    case backup
    case mods
    case screenshots
    case community
    case shortcuts
    case about
    case quick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logs: return "日志与诊断"
        case .backup: return "实例备份"
        case .mods: return "模组管理"
        case .screenshots: return "截图相册"
        case .community: return "社区与资源"
        case .shortcuts: return "快捷键说明"
        case .about: return "关于"
        case .quick: return "快捷操作"
        }
    }

    /// 路由别名映射（兼容旧 id 与单数写法）。
    static func from(pending: String) -> MoreSection? {
        switch pending {
        case "screenshot": return .screenshots
        case "about-doc": return .about
        default: return MoreSection(rawValue: pending)
        }
    }
}

// MARK: - 工具定义

/// 左面板工具项：标题、说明、图标与对应分区。
private struct MoreToolDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let section: MoreSection
}

// MARK: - 快捷键条目

/// 快捷键说明条目：组合键 + 动作 + 作用范围。
private struct MoreShortcutEntry: Identifiable, Equatable {
    let id: String
    let keys: String
    let title: String
    let scope: String
}

// MARK: - 外链模型

/// 外链模型。
private struct MoreExternalLink: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let url: URL
}

// MARK: - 左面板紧凑行

/// 左面板紧凑动作 / 链接行：比工具行更矮，保证最小窗口下左栏不出现滚动。
private struct MoreSideLinkRow: View {
    @Environment(\.launcherTheme) private var theme
    @State private var hovering = false

    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LauncherSpace.sm) {
                Image(systemName: systemImage)
                    .textStyle(.caption, tone: isSelected ? .accent : .secondary)
                    .frame(width: 22, height: 22)
                    .background {
                        RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                            .fill(isSelected ? theme.colors.accentSoft : theme.colors.surfaceSubtle)
                    }
                Text(title)
                    .textStyle(.bodyStrong, tone: isSelected ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .textStyle(.caption, tone: .tertiary)
            }
            .padding(.horizontal, LauncherSpace.sm)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                    .fill(isSelected ? theme.colors.accentSoft : (hovering ? theme.colors.surfaceHover : .clear))
            }
            .contentShape(RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .launcherPointer()
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 截图缩略图

/// 截图网格单元：受限像素尺寸的缩略图 + 文件名；点击用系统预览打开，右键菜单包含访达 / 复制 / 删除。
/// 离屏快照模式下不触发异步解码，直接用 `LauncherBlockArt` 占位，避免 ImageRenderer 卡住。
private struct MoreScreenshotTile: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    let item: MoreScreenshotItem
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onCopyPath: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                thumbnailView
                    .frame(maxWidth: .infinity)
                    .frame(height: LauncherSpace.xxxl + LauncherSpace.xl)
                    .clipShape(RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    Text(item.fileName)
                        .textStyle(.caption, tone: .primary)
                        .lineLimit(1)
                    HStack(spacing: LauncherSpace.xs) {
                        LauncherMonoText(item.sizeText, tone: .tertiary, size: 10)
                        Spacer(minLength: LauncherSpace.xs)
                        LauncherMonoText(item.dateText, tone: .tertiary, size: 10)
                    }
                }
            }
            .padding(LauncherSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .fill(theme.colors.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .strokeBorder(theme.colors.stroke, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .launcherPointer()
        .help(item.fileName)
        .launcherContextMenu([
            LauncherMenuGroup(items: [
                LauncherMenuItem("在预览中打开", systemImage: "eye", action: onOpen),
                LauncherMenuItem("在访达中显示", systemImage: "folder", action: onReveal),
                LauncherMenuItem("复制路径", systemImage: "doc.on.doc", action: onCopyPath),
                LauncherMenuItem("删除到废纸篓", systemImage: "trash", tone: .danger, action: onDelete)
            ])
        ])
        .task(id: item.url) { await loadThumbnail() }
        .accessibilityLabel(item.fileName)
    }

    /// 缩略图 / 离屏占位。
    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LauncherBlockArt(seed: item.fileName, cornerRadius: LauncherRadius.md, label: nil)
        }
    }

    /// 异步生成缩略图（ImageIO 受限解码，最长边 320px）。
    private func loadThumbnail() async {
        guard !snapshotMode, thumbnail == nil else { return }
        let url = item.url
        let image = await Task.detached(priority: .utility) {
            MoreScreenshotLibrary.thumbnail(for: url, maxPixelSize: 320)
        }.value
        guard !Task.isCancelled else { return }
        if let image {
            thumbnail = image
        }
    }
}
