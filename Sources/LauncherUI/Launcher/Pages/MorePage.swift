import SwiftUI
import AppKit

/// 更多页（PCL 式布局）：左侧工具 / 快捷操作 / 关于列表，右侧对应内容区。
public struct MorePage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    /// 打开既有设计系统画廊（由 App 壳注入，通常以 sheet 呈现）。
    private let onOpenGallery: () -> Void

    @State private var selection = "logs"
    @State private var sideHint: String?
    @State private var favoriteToolIDs: Set<String> = []
    @State private var exportHint: String?
    @State private var logFeedback: String?
    @State private var logFeedbackTone: LauncherBadgeTone = .success
    @State private var actionMessage = "所有操作都在本地完成，不会上传任何数据。"
    @State private var backupMessage: String?
    @State private var isCheckingUpdates = false
    @State private var updateMessage = "上次检查：今天 09:20"

    /// 日志视口高度：固定值保证最小窗口下右栏首屏不滚动。
    private let logViewportHeight: CGFloat = LauncherSpace.xxxl * 6 + LauncherSpace.xl * 2

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
    }

    // MARK: - 左侧工具列表

    /// 左面板：工具列表 / 快捷操作 / 关于，底部放设计系统入口与版本。
    private var sidePanel: some View {
        LauncherSidePanel(
            title: "更多",
            width: 272,
            toolbar: AnyView(sideToolbar),
            content: {
                LauncherSidePanelGroup("工具", trailing: "\(LauncherDemoData.tools.count)")
                ForEach(LauncherDemoData.tools) { tool in
                    toolRow(tool)
                }

                LauncherSidePanelGroup("快捷操作")
                sideLinkRow("打开游戏目录", systemImage: "folder", action: openGameDirectory)
                sideLinkRow("导出日志", systemImage: "square.and.arrow.up", action: exportLogs)
                sideLinkRow("重置窗口布局", systemImage: "rectangle.3.group", action: resetWindowLayout)

                LauncherSidePanelGroup("关于")
                sideLinkRow("快捷键说明", systemImage: "keyboard", isSelected: selection == "shortcuts") {
                    selection = "shortcuts"
                }
                sideLinkRow("关于", systemImage: "info.circle.fill", isSelected: selection == "about-doc") {
                    selection = "about-doc"
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
                        LauncherMonoText("v0.2.0 · 构建 \(MorePage.buildDateText)", tone: .tertiary, size: 10)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, LauncherSpace.xxs)
                }
            }
        )
    }

    /// 左面板标题栏右侧的短暂操作反馈。
    @ViewBuilder
    private var sideToolbar: some View {
        if let sideHint {
            LauncherBadge(sideHint, tone: .success, systemImage: "checkmark.circle.fill")
        }
    }

    /// 工具列表行：选中高亮 + 图标 + 「打开工具」语义 + 右键菜单。
    private func toolRow(_ tool: LauncherToolCard) -> some View {
        let isFavorite = favoriteToolIDs.contains(tool.id)

        return LauncherListRow(
            title: tool.title,
            subtitle: tool.subtitle,
            systemImage: tool.systemImage,
            badge: tool.badge,
            accessory: AnyView(
                HStack(spacing: LauncherSpace.xs) {
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .textStyle(.caption, tone: .warning)
                    }
                    Image(systemName: "chevron.right")
                        .textStyle(.caption, tone: .tertiary)
                }
            ),
            isSelected: selection == tool.id,
            action: {
                withAnimation(LauncherMotion.smooth) {
                    selection = tool.id
                }
            }
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

    /// 工具行右键菜单：打开 / 复制路径 / 标记收藏。
    private func toolContextMenu(_ tool: LauncherToolCard) -> [LauncherMenuGroup] {
        let isFavorite = favoriteToolIDs.contains(tool.id)
        return [
            LauncherMenuGroup(items: [
                LauncherMenuItem("打开", systemImage: "arrow.up.right", action: {
                    selection = tool.id
                }),
                LauncherMenuItem("复制路径", systemImage: "doc.on.doc", action: {
                    copyToPasteboard(engine.settings.resolvedGameDirectory.path)
                    flashSideHint("游戏目录已复制")
                }),
                LauncherMenuItem(
                    isFavorite ? "取消收藏" : "标记收藏",
                    systemImage: isFavorite ? "star.slash" : "star",
                    action: { toggleFavorite(tool.id) }
                )
            ])
        ]
    }

    // MARK: - 右侧标题

    /// 右侧面板标题：选中项标题 + 说明 + 「更多」下拉菜单。
    private var mainHeader: some View {
        LauncherPanelHeader(selectedTitle, subtitle: selectedSubtitle) {
            HStack(spacing: LauncherSpace.xs) {
                LauncherIconMenu(groups: headerMenuGroups, accessibilityLabel: "更多操作")
            }
        }
    }

    /// 头部「更多」菜单：复制日志 / 打开目录 / 设计系统。
    private var headerMenuGroups: [LauncherMenuGroup] {
        [
            LauncherMenuGroup(items: [
                LauncherMenuItem("复制日志", systemImage: "doc.on.doc", isDisabled: engine.logLines.isEmpty, action: copyLog),
                LauncherMenuItem("打开游戏目录", systemImage: "folder", action: openGameDirectory),
                LauncherMenuItem("设计系统画廊", systemImage: "square.grid.2x2", action: onOpenGallery)
            ])
        ]
    }

    /// 右侧当前页内容。
    @ViewBuilder
    private var pageContent: some View {
        switch selection {
        case "backup": backupPage
        case "mods": modsPage
        case "screenshots": screenshotsPage
        case "community": communityPage
        case "shortcuts": shortcutsPage
        case "about", "about-doc": aboutPage
        case "quick": quickActionsPage
        default: logsPage
        }
    }

    // MARK: - 日志与诊断

    /// 真实启动日志：状态、启动命令、实时输出、清空 / 复制 / 导出。
    private var logsPage: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            logStatusCard
            logConsoleCard
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

                    LauncherIconButton(
                        systemImage: "trash",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: "清空日志",
                        isDisabled: engine.logLines.isEmpty
                    ) {
                        clearLog()
                    }

                    LauncherIconButton(
                        systemImage: "doc.on.doc",
                        variant: .secondary,
                        size: .small,
                        accessibilityLabel: "复制日志",
                        isDisabled: engine.logLines.isEmpty
                    ) {
                        copyLog()
                    }

                    LauncherButton("导出日志", systemImage: "square.and.arrow.up", variant: .secondary, size: .small) {
                        exportLogFromConsole()
                    }
                }

                commandPreview
            }
        }
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
                    subtitle: "共 \(engine.logLines.count) 行 · 最多保留 600 行 · 实时追加",
                    accessory: AnyView(logHeaderAccessory)
                )

                if engine.logLines.isEmpty {
                    LauncherEmptyState(
                        systemImage: "terminal",
                        title: "还没有日志",
                        message: "启动一次游戏后，这里会显示实时输出。"
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

    /// 日志卡右上角：操作反馈徽标。
    @ViewBuilder
    private var logHeaderAccessory: some View {
        if let logFeedback {
            LauncherBadge(logFeedback, tone: logFeedbackTone, systemImage: "checkmark.circle.fill")
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

    /// 实例备份页：备份说明 + 两个真实反馈按钮。
    private var backupPage: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(title: "实例备份", subtitle: "把世界存档、模组配置与启动设置打包到本地")

                LauncherSettingRow(
                    "备份内容",
                    subtitle: "世界存档 · 模组配置 · 启动设置",
                    tooltip: "备份文件保存在实例目录的 backups 文件夹"
                ) {
                    LauncherMonoText("3 项", tone: .tertiary)
                }

                LauncherSettingRow(
                    "备份位置",
                    subtitle: engine.settings.resolvedGameDirectory.path,
                    showsDivider: false
                ) {
                    LauncherMonoText("/backups", tone: .tertiary)
                }

                HStack(spacing: LauncherSpace.sm) {
                    LauncherButton("立即备份", systemImage: "externaldrive.badge.plus", variant: .primary, size: .medium) {
                        backupMessage = "已创建备份：1.21.4 · 模组 214 个"
                    }
                    LauncherButton("恢复最近备份", systemImage: "arrow.counterclockwise", variant: .secondary, size: .medium) {
                        backupMessage = "已恢复最近备份：1.21.4 · 今天 14:20"
                    }
                    Spacer(minLength: 0)
                }

                if let backupMessage {
                    LauncherBadge(backupMessage, tone: .success, systemImage: "checkmark.circle.fill")
                }
            }
        }
    }

    // MARK: - 模组 / 截图

    /// 模组管理页：待接入空态 + 打开真实目录。
    private var modsPage: some View {
        LauncherEmptyState(
            systemImage: "puzzlepiece.extension.fill",
            title: "模组管理待接入",
            message: "安装版本后可在这里启用、更新与检测冲突，目前可先打开模组目录。",
            actionTitle: "打开模组目录",
            onAction: openModsDirectory
        )
    }

    /// 截图相册页：待接入空态 + 打开真实截图目录。
    private var screenshotsPage: some View {
        LauncherEmptyState(
            systemImage: "photo.on.rectangle.angled",
            title: "截图相册待接入",
            message: "游戏内截图会保存到 screenshots 文件夹，目前先在访达中打开。",
            actionTitle: "打开截图目录",
            onAction: openScreenshotsDirectory
        )
    }

    // MARK: - 社区与资源

    /// 社区页：三个真实外链。
    private var communityPage: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                LauncherSectionHeader(
                    title: "社区与资源",
                    subtitle: "整合包、模组与材质站外链",
                    accessory: AnyView(LauncherBadge("外链", tone: .neutral))
                )
                .padding(.bottom, LauncherSpace.xs)

                ForEach(externalLinks) { link in
                    LauncherListRow(
                        title: link.title,
                        subtitle: link.detail,
                        systemImage: link.systemImage,
                        accessory: AnyView(
                            Image(systemName: "arrow.up.right")
                                .textStyle(.caption, tone: .tertiary)
                        ),
                        action: {
                            NSWorkspace.shared.open(link.url)
                        }
                    )
                }
            }
        }
    }

    // MARK: - 快捷键

    /// 快捷键页：六条按键，两列三行。
    private var shortcutsPage: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "快捷键说明",
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

    private func shortcutColumn(_ items: [LauncherShortcut]) -> some View {
        VStack(spacing: LauncherSpace.sm) {
            ForEach(items) { shortcut in
                LauncherKeyValueRow(key: shortcut.title, value: shortcut.keys, isMono: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 关于

    /// 关于页：真实版本信息 + 检查更新 + 设计系统入口。
    private var aboutPage: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "关于",
                    subtitle: "方块启动器",
                    accessory: AnyView(LauncherBadge("v0.2.0", tone: .accent))
                )

                LauncherSettingRow("版本", subtitle: "当前启动器版本") {
                    LauncherMonoText("v0.2.0", tone: .primary)
                }
                LauncherSettingRow("构建日期", subtitle: "本次构建") {
                    LauncherMonoText(MorePage.buildDateText, tone: .primary)
                }
                LauncherSettingRow("已安装版本", subtitle: "本地 versions 目录") {
                    LauncherMonoText("\(engine.installedVersions.count) 个", tone: .primary)
                }
                LauncherSettingRow("Java 运行时", subtitle: "自动检测到的运行时", showsDivider: false) {
                    LauncherMonoText("\(engine.javaRuntimes.count) 个", tone: .primary)
                }

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
                    LauncherButton("设计系统画廊", systemImage: "square.grid.2x2", variant: .secondary, size: .small) {
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
                    Text("基于 SwiftUI 构建 · 设计系统 v0.2")
                        .textStyle(.micro, tone: .tertiary)
                }
            }
        }
    }

    // MARK: - 快捷操作页

    /// 快捷操作页：三个大按钮 + 执行说明（由左栏动作直接跳转到这里）。
    private var quickActionsPage: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "快捷操作",
                    subtitle: "打开真实目录、导出真实日志，全部在本地执行",
                    accessory: AnyView(LauncherMonoText("本机", tone: .tertiary))
                )

                HStack(spacing: LauncherSpace.md) {
                    LauncherButton(
                        "打开游戏目录",
                        systemImage: "folder",
                        variant: .secondary,
                        size: .large,
                        isFullWidth: true
                    ) {
                        openGameDirectory()
                    }
                    LauncherButton(
                        "导出日志",
                        systemImage: "square.and.arrow.up",
                        variant: .primary,
                        size: .large,
                        isFullWidth: true
                    ) {
                        exportLogs()
                    }
                    LauncherButton(
                        "重置窗口布局",
                        systemImage: "rectangle.3.group",
                        variant: .ghost,
                        size: .large,
                        isFullWidth: true
                    ) {
                        resetWindowLayout()
                    }
                }

                HStack(spacing: LauncherSpace.sm) {
                    if let exportHint {
                        LauncherBadge(
                            exportHint,
                            tone: exportHint.hasPrefix("日志") ? .success : .danger,
                            systemImage: exportHint.hasPrefix("日志") ? "checkmark.circle.fill" : "xmark.octagon.fill"
                        )
                    } else {
                        Image(systemName: "info.circle")
                            .textStyle(.micro, tone: .tertiary)
                        Text(actionMessage)
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: LauncherSpace.md)
                    LauncherMonoText(engine.settings.resolvedGameDirectory.path, tone: .tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - 文案与状态

    /// 当前选中项标题。
    private var selectedTitle: String {
        switch selection {
        case "backup": return "实例备份"
        case "mods": return "模组管理"
        case "screenshots": return "截图相册"
        case "community": return "社区与资源"
        case "shortcuts": return "快捷键说明"
        case "about", "about-doc": return "关于"
        case "quick": return "快捷操作"
        default: return "日志与诊断"
        }
    }

    /// 当前选中项说明。
    private var selectedSubtitle: String {
        switch selection {
        case "backup": return "备份世界、模组配置与启动设置到本地"
        case "mods": return "启用、更新与冲突检测（待接入）"
        case "screenshots": return "浏览游戏内截图并快速分享（待接入）"
        case "community": return "整合包、模组与材质站外链"
        case "shortcuts": return "高频操作的键盘入口"
        case "about", "about-doc": return "v0.2.0 · \(MorePage.buildDateText) · 已安装 \(engine.installedVersions.count) 个版本"
        case "quick": return "常用维护动作，全部在本地执行"
        default: return "\(engine.statusText) · 共 \(engine.logLines.count) 行输出"
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

    /// 构建日期（当天格式化）。
    private static let buildDateText: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }()

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

    /// 日志行语义色调。
    private func logTone(for line: String) -> LauncherTextTone {
        let lowered = line.lowercased()
        let errorKeywords = ["error", "exception", "fatal", "失败", "错误", "崩溃", "cannot"]
        if errorKeywords.contains(where: { lowered.contains($0) }) { return .danger }
        let warningKeywords = ["warn", "警告", "deprecated", "重试"]
        if warningKeywords.contains(where: { lowered.contains($0) }) { return .warning }
        return .secondary
    }

    // MARK: - 真实操作

    /// 打开真实游戏目录。
    private func openGameDirectory() {
        let url = engine.settings.resolvedGameDirectory
        if NSWorkspace.shared.open(url) {
            actionMessage = "已在访达中打开游戏目录：\(url.path)"
            flashSideHint("已打开游戏目录")
        } else {
            actionMessage = "无法打开游戏目录：\(url.path)"
        }
        selection = "quick"
    }

    /// 打开模组目录（不存在时退回到游戏目录）。
    private func openModsDirectory() {
        let mods = engine.settings.resolvedGameDirectory.appendingPathComponent("mods", isDirectory: true)
        _ = NSWorkspace.shared.open(FileManager.default.fileExists(atPath: mods.path) ? mods : engine.settings.resolvedGameDirectory)
    }

    /// 打开截图目录（不存在时退回到游戏目录）。
    private func openScreenshotsDirectory() {
        let screenshots = engine.settings.resolvedGameDirectory.appendingPathComponent("screenshots", isDirectory: true)
        _ = NSWorkspace.shared.open(FileManager.default.fileExists(atPath: screenshots.path) ? screenshots : engine.settings.resolvedGameDirectory)
    }

    /// 左栏「导出日志」：真实写入桌面并回到快捷操作页展示结果。
    private func exportLogs() {
        let message = writeLogFile()
        exportHint = message
        actionMessage = message
        selection = "quick"
        flashSideHint(message.hasPrefix("日志") ? "日志已导出" : "导出失败")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if exportHint != nil {
                exportHint = nil
            }
        }
    }

    /// 日志页里的导出：写入桌面并在日志卡头部显示反馈。
    private func exportLogFromConsole() {
        let message = writeLogFile()
        flashLogFeedback(message, tone: message.hasPrefix("日志") ? .success : .danger)
        flashSideHint(message)
    }

    /// 重置窗口布局（UI 模拟）并展示说明。
    private func resetWindowLayout() {
        actionMessage = "窗口布局已重置为默认尺寸。"
        selection = "quick"
        flashSideHint("窗口已重置")
    }

    /// 复制全部日志到剪贴板。
    private func copyLog() {
        copyToPasteboard(engine.logLines.joined(separator: "\n"))
        flashLogFeedback("已复制 \(engine.logLines.count) 行日志", tone: .success)
        flashSideHint("日志已复制")
    }

    /// 清空运行时日志。
    private func clearLog() {
        engine.clearLog()
        flashLogFeedback("日志已清空", tone: .neutral)
    }

    /// 标记 / 取消收藏工具。
    private func toggleFavorite(_ toolID: String) {
        if favoriteToolIDs.contains(toolID) {
            favoriteToolIDs.remove(toolID)
            flashSideHint("已取消收藏")
        } else {
            favoriteToolIDs.insert(toolID)
            flashSideHint("已收藏")
        }
    }

    /// 写入剪贴板。
    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 真实写日志文件到桌面。
    private func writeLogFile() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let now = Date()
        let timestamp = formatter.string(from: now)
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop", isDirectory: true)
        let url = desktop.appendingPathComponent("blocklauncher-log-\(timestamp).log")

        let header = """
        方块启动器日志
        导出时间：\(DateFormatter.localizedString(from: now, dateStyle: .medium, timeStyle: .medium))
        启动命令：\(engine.lastCommandLine ?? "（尚未启动过游戏）")
        退出码：\(engine.lastExitCode.map { String($0) } ?? "—")

        """
        let content = header + engine.logLines.joined(separator: "\n")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "日志已导出到桌面"
        } catch {
            return "导出失败：\(error.localizedDescription)"
        }
    }

    /// 日志卡头部的短暂反馈（2 秒）。
    private func flashLogFeedback(_ message: String, tone: LauncherBadgeTone) {
        logFeedback = message
        logFeedbackTone = tone
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if logFeedback == message {
                logFeedback = nil
            }
        }
    }

    /// 左栏标题栏的短暂反馈（2 秒）。
    private func flashSideHint(_ message: String) {
        sideHint = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if sideHint == message {
                sideHint = nil
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

    /// 检查更新（UI 模拟）。
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

// MARK: - 文件内私有组件

/// 外链模型。
private struct MoreExternalLink: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let url: URL
}

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
