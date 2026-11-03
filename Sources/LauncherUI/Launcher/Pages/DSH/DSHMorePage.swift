import SwiftUI
import AppKit

// MARK: - DSH 更多页

/// DSH 启动器的「更多」页：与 Minecraft 更多页同构（左侧分区 + 右侧内容）。
///
/// 分区：运行日志（所有实例的 `logs/<实例ID>.log`，展示时映射实例名）、数据目录（versions / homes / cache / logs）、
/// 进程（Web UI 状态 / 端口 / 打开 / 复制地址 / 停止）、关于（版本说明与快捷键）。
/// 实例化后日志与目录都按「实例 ID」组织，进程状态以 `activeInstanceID` 为准。
public struct DSHMorePage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherRouter.self) private var router
    @Environment(DSHVersionStore.self) private var versions
    @Environment(DSHProcessController.self) private var dshProcess
    @Environment(DSHPluginStore.self) private var plugins
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    // MARK: 页面状态

    /// 当前分区。
    @State private var section: DSHMoreSection = .logs
    /// 所有实例的日志文件（含未运行的实例与孤立日志）。
    @State private var logFiles: [DSHMoreLogFile] = []
    /// 当前查看的日志实例 ID。
    @State private var selectedLogInstanceID: String?
    /// 从磁盘日志文件读到的行（进程未运行或查看其它实例时展示）。
    @State private var fileLogLines: [String] = []
    /// 数据目录统计（versions / homes / cache / logs）。
    @State private var directoryRows: [DSHMoreDirectory] = []
    /// 刷新日志 / 目录中。
    @State private var isRefreshing = false
    /// 是否已经加载过磁盘数据（避免重复读盘）。
    @State private var didLoad = false

    /// 画廊入口（与 Minecraft 更多页一致）。
    private let onOpenGallery: () -> Void

    /// 日志视口高度：固定值保证 1080×720 下右栏首屏不出现纵向滚动。
    private let logViewportHeight: CGFloat = LauncherSpace.xxxl * 6

    /// 创建 DSH 更多页。
    /// - Parameters:
    ///   - initialSection: 初始分区（默认「运行日志」，供路由预览与离屏截图使用）。
    ///   - onOpenGallery: 打开设计系统画廊。
    public init(initialSection: DSHMoreSection = .logs, onOpenGallery: @escaping () -> Void = {}) {
        self.onOpenGallery = onOpenGallery
        _section = State(initialValue: initialSection)
    }

    public var body: some View {
        LauncherPageLayout(sideWidth: 300) {
            sidePanel
        } main: {
            LauncherMainPanel {
                VStack(alignment: .leading, spacing: LauncherSpace.md) {
                    mainHeader
                    if dshProcess.state != .idle {
                        runningInstanceCard
                    }
                    switch section {
                    case .logs: logsContent
                    case .directories: directoriesContent
                    case .process: processContent
                    case .about: aboutContent
                    }
                    Spacer(minLength: LauncherSpace.md)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            consumePendingSection()
            loadDataIfNeeded()
        }
        .onChange(of: router.pendingMoreSection) { _, _ in
            consumePendingSection()
        }
        .onChange(of: dshProcess.state) { _, _ in
            // 进程状态变化后刷新日志文件信息（真实文件增长 / 停止写入）。
            guard !snapshotMode else { return }
            refreshLogInfo()
        }
        .onChange(of: versions.installed.count) { _, _ in
            guard !snapshotMode else { return }
            refreshLogInfo()
            reloadDirectories(showsToast: false)
        }
    }

    // MARK: - 左侧分区面板

    /// 左面板：分区列表 + 底部画廊入口与版本信息。
    private var sidePanel: some View {
        LauncherSidePanel(
            title: "更多",
            count: nil,
            width: 300,
            content: {
                LauncherSidePanelGroup("DSH 运行状态")
                ForEach(DSHMoreSection.allCases.filter { $0 != .about }) { item in
                    sideRow(item)
                }
                LauncherSidePanelGroup("关于")
                sideRow(.about)
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
                            "\(LauncherBuildInfo.current.versionText) · DSH 启动器",
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

    /// 分区行。
    private func sideRow(_ item: DSHMoreSection) -> some View {
        LauncherListRow(
            title: item.title,
            systemImage: item.systemImage,
            badge: sectionSideBadge(item),
            isSelected: section == item,
            action: {
                withAnimation(LauncherMotion.spring) {
                    section = item
                }
            }
        )
    }

    /// 分区行右侧徽标（实例化后按实例 / 日志数量显示）。
    private func sectionSideBadge(_ item: DSHMoreSection) -> String? {
        switch item {
        case .logs:
            let existing = logFiles.filter(\.exists).count
            guard existing > 0 else { return nil }
            return "\(existing) 个日志"
        case .directories:
            return instanceStatsText
        case .process:
            return processStatus.title
        case .about:
            return nil
        }
    }

    // MARK: - 右侧页头

    /// 页头：分区标题 + 说明 + 状态徽标。
    private var mainHeader: some View {
        LauncherPanelHeader(section.title, subtitle: section.subtitle) {
            HStack(spacing: LauncherSpace.xs) {
                if let badge = headerBadge {
                    LauncherBadge(badge, tone: .neutral)
                }
            }
        }
    }

    /// 页头徽标。
    private var headerBadge: String? {
        switch section {
        case .logs:
            return selectedLogFile?.displayName ?? "还没有日志"
        case .directories:
            return instanceStatsText
        case .process:
            return processStatus.title
        case .about:
            return LauncherBuildInfo.current.versionText
        }
    }

    // MARK: - 运行中实例卡片

    /// 运行中实例卡：实例名 + DSH 版本 + 端口 / 启动时间 + 打开 / 复制 / 停止。
    private var runningInstanceCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            HStack(alignment: .center, spacing: LauncherSpace.md) {
                LauncherStatusDot(
                    tone: DSHLaunchPresentation.statusTone(dshProcess.state),
                    isPulsing: dshProcess.isBusy
                )

                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    HStack(spacing: LauncherSpace.xs) {
                        Text(runningInstanceName ?? "DSH Web UI")
                            .textStyle(.bodyStrong)
                            .lineLimit(1)
                        if let activeVersion = dshProcess.activeVersion {
                            LauncherBadge("DSH \(activeVersion)", tone: .neutral)
                        }
                        if runningInstanceIsPack {
                            LauncherBadge("整合包", tone: .accent)
                        }
                    }
                    Text(runningInstanceDetail)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: LauncherSpace.sm)

                LauncherButton("打开", systemImage: "safari", variant: .secondary, size: .small, isDisabled: !dshProcess.isRunning) {
                    dshProcess.openWebUI()
                }
                LauncherButton("复制地址", systemImage: "doc.on.doc", variant: .ghost, size: .small, isDisabled: !dshProcess.isRunning) {
                    dshProcess.copyWebURL()
                    router.showToast("已复制 DSH Web UI 地址（含一次性 token）")
                }
                LauncherButton("停止", systemImage: "stop.fill", variant: .danger, size: .small, isLoading: dshProcess.state == .stopping) {
                    confirmStopProcess()
                }
            }
        }
    }

    // MARK: - 1. 运行日志

    /// 当前查看日志的实例 ID：手动选择优先，其次运行中实例，最后设置里选中的实例。
    private var displayLogInstanceID: String? {
        if let selectedLogInstanceID, logFiles.contains(where: { $0.instanceID == selectedLogInstanceID }) {
            return selectedLogInstanceID
        }
        if let active = dshProcess.activeInstanceID {
            return active
        }
        return versions.settings.dshSelectedInstanceID.isEmpty ? versions.installed.first?.id : versions.settings.dshSelectedInstanceID
    }

    /// 当前查看的日志文件。
    private var selectedLogFile: DSHMoreLogFile? {
        if let id = displayLogInstanceID, let exact = logFiles.first(where: { $0.instanceID == id }) {
            return exact
        }
        return logFiles.first
    }

    /// 实际展示的日志行：查看运行中实例时用内存日志，否则读磁盘文件。
    private var displayLines: [String] {
        if let file = selectedLogFile,
           file.instanceID == dshProcess.activeInstanceID,
           !dshProcess.logLines.isEmpty {
            return Array(dshProcess.logLines.suffix(200))
        }
        return fileLogLines
    }

    /// 运行日志分区：实例日志选择 + 真实日志控制台 + 复制 / 刷新 / 访达 / 清空。
    private var logsContent: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherCardHeader(
                        title: "运行日志",
                        subtitle: logSubtitle,
                        systemImage: "text.alignleft"
                    )
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherBadge("\(displayLines.count) 行", tone: .neutral)
                    if logFiles.isEmpty {
                        LauncherBadge("还没有日志", tone: .neutral)
                    } else {
                        logFileMenu
                    }
                }

                HStack(spacing: LauncherSpace.sm) {
                    LauncherButton(
                        "复制日志",
                        systemImage: "doc.on.doc",
                        variant: .secondary,
                        size: .small,
                        isDisabled: displayLines.isEmpty
                    ) {
                        copyLogs()
                    }
                    .fixedSize()
                    LauncherButton(
                        "刷新",
                        systemImage: "arrow.clockwise",
                        variant: .secondary,
                        size: .small,
                        isLoading: isRefreshing
                    ) {
                        refreshLogs()
                    }
                    .fixedSize()
                    LauncherButton(
                        "在访达中显示",
                        systemImage: "folder",
                        variant: .secondary,
                        size: .small,
                        isDisabled: !(selectedLogFile?.exists ?? false)
                    ) {
                        revealLogFile()
                    }
                    .fixedSize()
                    LauncherButton(
                        "清空日志",
                        systemImage: "trash",
                        variant: .secondary,
                        size: .small,
                        isDisabled: !(selectedLogFile?.exists ?? false) || (selectedLogFile?.bytes ?? 0) == 0
                    ) {
                        confirmClearLog()
                    }
                    .fixedSize()
                    LauncherButton(
                        "打开 logs 目录",
                        systemImage: "folder.badge.gearshape",
                        variant: .ghost,
                        size: .small
                    ) {
                        openLogsDirectory()
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                }

                logConsole

                HStack(spacing: LauncherSpace.xs) {
                    if let file = selectedLogFile {
                        LauncherMonoText(file.url.path, tone: .tertiary, size: 10)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: LauncherSpace.sm)
                        Text("\(file.sizeText) · \(file.modifiedText)")
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    } else {
                        Text(logFiles.isEmpty
                             ? "还没有可查看的实例日志：安装实例并启动一次 Web UI 后会写入 logs/<实例ID>.log"
                             : "选择左上角实例查看日志")
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    /// 实例日志选择菜单（文件名 = 实例 ID，优先展示实例名）。
    private var logFileMenu: some View {
        LauncherMenuButton(
            selectedLogFile?.displayName ?? "选择日志",
            systemImage: "list.bullet",
            variant: .secondary,
            size: .small,
            groups: [
                LauncherMenuGroup(title: "实例日志（\(logFiles.count)）", items: logFiles.map { file in
                    LauncherMenuItem(
                        "\(file.displayName) · \(file.exists ? file.sizeText : "还没有日志")",
                        systemImage: file.instanceID == dshProcess.activeInstanceID ? "play.circle.fill" : "doc.text",
                        action: { selectLog(file) }
                    )
                })
            ]
        )
    }

    /// 日志卡说明。
    private var logSubtitle: String {
        if dshProcess.isRunning {
            return "\(runningInstanceName ?? "DSH Web UI") 正在运行；实时输出会持续追加"
        }
        if let file = selectedLogFile {
            return "实例「\(file.displayName)」的最近一次输出（logs/\(file.instanceID).log）"
        }
        return "每个实例独立日志文件；启动 Web UI 后写入 logs/<实例ID>.log"
    }

    /// 日志控制台（固定高度 + 内部滚动，不撑高页面）。
    private var logConsole: some View {
        Group {
            if displayLines.isEmpty {
                LauncherEmptyState(
                    systemImage: "text.alignleft",
                    title: "还没有日志",
                    message: "启动一次 DSH Web UI 后，进程输出会写到实例自己的 logs/<实例ID>.log；也可以查看其它实例的历史日志。"
                )
            } else if snapshotMode {
                // 离屏渲染：ScrollView 不可绘制，改用同尺寸的静态尾部日志。
                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    ForEach(Array(displayLines.suffix(18).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .textStyle(.monoSmall, tone: logTone(for: line))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(LauncherSpace.sm)
                .background {
                    RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                        .fill(theme.colors.surfaceSubtle)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                        .strokeBorder(theme.colors.stroke, lineWidth: 1)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                            ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .textStyle(.monoSmall, tone: logTone(for: line))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(LauncherSpace.sm)
                    }
                    .background {
                        RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                            .fill(theme.colors.surfaceSubtle)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                            .strokeBorder(theme.colors.stroke, lineWidth: 1)
                    }
                    .onChange(of: displayLines.count) { _, _ in
                        scrollLogToBottom(proxy, animated: true)
                    }
                    .onAppear {
                        scrollLogToBottom(proxy, animated: false)
                    }
                }
            }
        }
        .frame(height: logViewportHeight)
    }

    /// 日志行色调：错误 / 警告行用语义色，其余中性。
    private func logTone(for line: String) -> LauncherTextTone {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("failed") || lower.contains("✗") {
            return .danger
        }
        if lower.contains("warn") || lower.contains("⚠") {
            return .warning
        }
        return .secondary
    }

    /// 切换查看的实例日志。
    private func selectLog(_ file: DSHMoreLogFile) {
        selectedLogInstanceID = file.instanceID
        refreshLogInfo()
    }

    /// 复制当前展示的日志。
    private func copyLogs() {
        let lines = displayLines
        guard !lines.isEmpty else {
            router.showToast("没有可复制的日志", tone: .info)
            return
        }
        InstanceActions.copy(lines.joined(separator: "\n"))
        router.showToast("已复制 \(lines.count) 行日志")
    }

    /// 刷新日志：重新扫描所有实例日志并读取选中文件尾部。
    private func refreshLogs() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { @MainActor in
            refreshLogInfo()
            isRefreshing = false
            let count = displayLines.count
            router.showToast("日志已刷新（\(count) 行）")
        }
    }

    /// 在访达中显示日志文件。
    private func revealLogFile() {
        guard let file = selectedLogFile, file.exists else {
            router.showToast("日志文件还不存在，先启动一次 DSH Web UI", tone: .warning)
            return
        }
        InstanceActions.reveal(file.url)
    }

    /// 打开 logs 目录。
    private func openLogsDirectory() {
        let directory = versions.paths.logsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !InstanceActions.open(directory) {
            router.showToast("无法打开 logs 目录", tone: .danger)
        }
    }

    /// 清空日志前确认（真实截断文件；实例名 + ID 写进文案）。
    private func confirmClearLog() {
        guard let file = selectedLogFile, file.exists else {
            router.showToast("日志文件还不存在", tone: .info)
            return
        }
        router.showDialog(
            LauncherDialogRequest(
                title: "清空 DSH 日志？",
                message: "将把实例「\(file.displayName)」的日志 \(file.url.lastPathComponent)（\(file.sizeText)）截断为 0 字节。\(dshProcess.isRunning && file.instanceID == dshProcess.activeInstanceID ? "实例仍在运行，后续输出会继续写入。" : "此操作不可撤销。")",
                confirmTitle: "清空",
                isDestructive: true,
                onConfirm: {
                    do {
                        _ = try DSHMoreLogTools.truncate(paths: versions.paths, instanceID: file.instanceID)
                        fileLogLines = []
                        refreshLogInfo()
                        router.showToast(
                            dshProcess.isRunning && file.instanceID == dshProcess.activeInstanceID
                                ? "日志文件已清空；运行中的进程会继续写入"
                                : "日志文件已清空",
                            tone: .warning
                        )
                    } catch {
                        router.showToast("清空失败：\(error.localizedDescription)", tone: .danger)
                    }
                }
            )
        )
    }

    // MARK: - 2. 数据目录

    /// 数据目录分区：versions / homes / cache / logs 真实大小 + 实例统计。
    private var directoriesContent: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherCardHeader(
                        title: "数据目录",
                        subtitle: "实例运行时（versions）与实例数据（homes）互相隔离；凭据复用 ~/.dsh",
                        systemImage: "folder.fill"
                    )
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherBadge(instanceStatsText, tone: .neutral)
                    LauncherButton(
                        "重新统计",
                        systemImage: "arrow.clockwise",
                        variant: .secondary,
                        size: .small,
                        isLoading: isRefreshing
                    ) {
                        reloadDirectories(showsToast: true)
                    }
                    .fixedSize()
                }

                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    ForEach(directoryDisplayRows) { row in
                        DSHMoreDirectoryRow(
                            title: row.title,
                            subtitle: row.detail,
                            path: row.path,
                            sizeText: row.sizeText,
                            exists: row.exists
                        ) {
                            openDirectory(row)
                        }
                    }
                }

                LauncherDivider()

                profileRow
            }
        }
    }

    /// 目录行：交互模式首帧给确定性占位，快照模式直接同步统计（磁盘统计允许一次性同步执行）。
    private var directoryDisplayRows: [DSHMoreDirectory] {
        if !directoryRows.isEmpty { return directoryRows }
        if snapshotMode {
            return DSHMoreDirectoryTools.directories(paths: versions.paths, instances: versions.installed)
        }
        return DSHMoreDirectoryKind.allCases.map { kind in
            DSHMoreDirectory(kind: kind, path: kind.url(paths: versions.paths).path, bytes: 0, exists: false)
        }
    }

    /// 当前实例 profile 行（每实例独立 DSH_HOME）。
    private var profileRow: some View {
        let instance = runningInstance ?? selectedInstance
        let path = instance.map { versions.paths.profileDirectory(for: $0.id).path }
        return HStack(spacing: LauncherSpace.sm) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text("当前实例 Profile")
                    .textStyle(.bodyStrong)
                    .lineLimit(1)
                Text(instance.map { "实例「\($0.name)」的 web profile（插件 / 会话；登录凭据复用 ~/.dsh）" }
                     ?? "还没有选中实例：先在「启动」页选择并启动一次")
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
                LauncherMonoText(path ?? "—", tone: .tertiary, size: 10)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: LauncherSpace.sm)
            LauncherIconButton(
                systemImage: "folder",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "打开当前实例 Profile",
                isDisabled: !(path.map { FileManager.default.fileExists(atPath: $0) } ?? false)
            ) {
                if let path {
                    let url = URL(fileURLWithPath: path)
                    if InstanceActions.open(url) {
                        router.showToast("已在访达中打开当前实例 Profile")
                    } else {
                        router.showToast("目录不存在：启动一次后会自动创建", tone: .warning)
                    }
                }
            }
        }
        .padding(.top, LauncherSpace.xs)
    }

    /// 打开数据目录。
    private func openDirectory(_ row: DSHMoreDirectory) {
        let url = URL(fileURLWithPath: row.path)
        guard row.exists else {
            router.showToast("\(row.title)还不存在：启动或安装一次后会自动创建", tone: .warning)
            return
        }
        if InstanceActions.open(url) {
            router.showToast("已在访达中打开\(row.title)")
        } else {
            router.showToast("无法打开\(row.title)", tone: .warning)
        }
    }

    /// 重新统计目录大小（后台读盘）。
    private func reloadDirectories(showsToast: Bool) {
        guard !isRefreshing else { return }
        isRefreshing = true
        let paths = versions.paths
        let instances = versions.installed
        Task { @MainActor in
            let rows = await Task.detached(priority: .userInitiated) {
                DSHMoreDirectoryTools.directories(paths: paths, instances: instances)
            }.value
            directoryRows = rows
            isRefreshing = false
            if showsToast {
                let total = rows.reduce(Int64(0)) { $0 + $1.bytes }
                router.showToast("目录统计已刷新：\(DSHFormatting.byteCount(total))")
            }
        }
    }

    // MARK: - 3. 进程

    /// 运行中的实例（按 activeInstanceID 精确匹配）。
    private var runningInstance: DSHInstalledVersion? {
        DSHLaunchPresentation.runningInstance(in: versions.installed, activeInstanceID: dshProcess.activeInstanceID)
    }

    private var runningInstanceName: String? {
        runningInstance?.name
    }

    private var runningInstanceIsPack: Bool {
        runningInstance?.isPack ?? false
    }

    /// 运行中实例摘要（实例名 + DSH 版本 + 端口 / 启动时间）。
    private var runningInstanceDetail: String {
        var parts: [String] = []
        if let activeVersion = dshProcess.activeVersion {
            parts.append("DSH \(activeVersion)")
        }
        if let port = dshProcess.activePort {
            parts.append("端口 \(port)")
        }
        if let startedAt = dshProcess.startedAt {
            parts.append("启动于 \(DSHFormatting.time(startedAt))")
        }
        if let file = selectedLogFile, file.instanceID == dshProcess.activeInstanceID, file.exists {
            parts.append("日志 \(file.sizeText)")
        }
        return parts.isEmpty ? "正在读取进程状态…" : parts.joined(separator: " · ")
    }

    /// 进程状态文案。
    private var processStatus: DSHProcessStatusText {
        DSHProcessStatusFormatter.text(
            for: dshProcess.state,
            port: dshProcess.activePort,
            startedAt: dshProcess.startedAt
        )
    }

    /// 进程分区：状态、运行实例、端口、启动时间、打开 / 复制 / 停止。
    private var processContent: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherCardHeader(
                        title: "DSH Web UI 进程",
                        subtitle: "状态来自真实子进程输出、按实例 ID 匹配",
                        systemImage: "bolt.horizontal.circle.fill"
                    )
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherBadge(processStatus.title, tone: processStatusTone)
                }

                if case .failed(let message) = dshProcess.state {
                    LauncherBanner(
                        title: "启动失败",
                        message: message,
                        tone: .warning
                    )
                }

                if dshProcess.state == .idle {
                    LauncherEmptyState(
                        systemImage: "bolt.horizontal.circle",
                        title: "DSH Web UI 未运行",
                        message: "在「启动」页选择实例并启动后，这里会显示实例名、端口、启动时间与带一次性 token 的地址。"
                    )
                } else {
                    VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        DSHInfoRow(title: "状态", value: processStatus.title, isMissing: processStatus.isError)
                        DSHInfoRow(
                            title: "运行实例",
                            value: runningInstanceName ?? "—",
                            isMissing: runningInstanceName == nil,
                            systemImage: "shippingbox"
                        )
                        DSHInfoRow(
                            title: "DSH 版本",
                            value: dshProcess.activeVersion ?? "—",
                            isMissing: dshProcess.activeVersion == nil
                        )
                        DSHInfoRow(title: "端口", value: dshProcess.activePort.map { "\($0)" } ?? "—", isMissing: dshProcess.activePort == nil)
                        DSHInfoRow(title: "启动时间", value: DSHFormatting.dateTime(dshProcess.startedAt), isMissing: dshProcess.startedAt == nil)
                        DSHInfoRow(title: "启动地址", value: processURLText, isMissing: dshProcess.webURL == nil)
                    }
                    .padding(.vertical, LauncherSpace.xs)

                    Text(processStatus.detail)
                        .textStyle(.micro, tone: processStatus.isError ? .danger : .tertiary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: LauncherSpace.sm) {
                    LauncherButton(
                        "打开 Web UI",
                        systemImage: "safari",
                        variant: .primary,
                        size: .small,
                        isDisabled: !dshProcess.isRunning
                    ) {
                        dshProcess.openWebUI()
                    }
                    .fixedSize()
                    LauncherButton(
                        "复制地址",
                        systemImage: "doc.on.doc",
                        variant: .secondary,
                        size: .small,
                        isDisabled: !dshProcess.isRunning
                    ) {
                        dshProcess.copyWebURL()
                        router.showToast("已复制 DSH Web UI 地址（含一次性 token）")
                    }
                    .fixedSize()
                    LauncherButton(
                        "停止",
                        systemImage: "stop.fill",
                        variant: dshProcess.isRunning || dshProcess.isBusy ? .danger : .secondary,
                        size: .small,
                        isLoading: dshProcess.state == .stopping,
                        isDisabled: !(dshProcess.isRunning || dshProcess.isBusy)
                    ) {
                        confirmStopProcess()
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                    LauncherButton(
                        "去启动页",
                        systemImage: "play.rectangle",
                        variant: .ghost,
                        size: .small
                    ) {
                        router.go(.launch)
                    }
                    .fixedSize()
                }
            }
        }
    }

    /// 进程状态徽标色调。
    private var processStatusTone: LauncherBadgeTone {
        switch dshProcess.state {
        case .idle: return .neutral
        case .starting, .stopping: return .info
        case .running: return .success
        case .failed: return .warning
        }
    }

    /// 启动地址（脱敏展示一次性 token）。
    private var processURLText: String {
        DSHFormatting.redactedURL(dshProcess.state.url) ?? "—"
    }

    /// 停止进程前二次确认（文案带运行中实例名）。
    private func confirmStopProcess() {
        let name = runningInstanceName ?? "DSH Web UI"
        router.showDialog(
            LauncherDialogRequest(
                title: "停止 DSH Web UI？",
                message: "将终止实例「\(name)」的 Web UI 进程，正在进行的会话会中断。可以稍后重新启动。",
                confirmTitle: "停止进程",
                isDestructive: true,
                onConfirm: {
                    Task { @MainActor in
                        await dshProcess.stop()
                        refreshLogInfo()
                        router.showToast("DSH Web UI 已停止", tone: .warning)
                    }
                }
            )
        )
    }

    // MARK: - 4. 关于

    /// 关于分区：版本说明 + 实例统计 + 快捷键。
    private var aboutContent: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherCardHeader(
                    title: "关于 DSH 启动器",
                    subtitle: "DSH 启动器使用官方 @deepseek-ai/dsh Web UI",
                    systemImage: "info.circle.fill"
                )

                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    DSHInfoRow(title: "LauncherALL 版本", value: LauncherBuildInfo.current.versionText)
                    DSHInfoRow(title: "构建时间", value: LauncherBuildInfo.current.buildDateTimeText)
                    DSHInfoRow(title: "DSH 数据目录", value: versions.paths.root.path)
                    DSHInfoRow(
                        title: "实例 DSH_HOME",
                        value: selectedInstance.map { versions.paths.homeDirectory(for: $0.id).path }
                            ?? versions.paths.homesDirectory.path,
                        isMissing: selectedInstance.map {
                            !FileManager.default.fileExists(atPath: versions.paths.homeDirectory(for: $0.id).path)
                        } ?? false,
                        systemImage: "house"
                    )
                    DSHInfoRow(
                        title: "已安装实例",
                        value: instanceStatsText,
                        isMissing: versions.installed.isEmpty,
                        systemImage: "shippingbox"
                    )
                    DSHInfoRow(
                        title: "插件加载源",
                        value: plugins.sourceText,
                        systemImage: "puzzlepiece.extension"
                    )
                }

                LauncherDivider()

                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    Text("快捷键")
                        .textStyle(.bodyStrong)
                    shortcutRow("⌘1 – ⌘4", "切换一级页面（启动 / 下载 / 设置 / 更多）")
                    shortcutRow("⌘⇧T", "切换深色 / 浅色主题")
                    shortcutRow("⌘⇧D", "打开设计系统画廊")
                }

                Text("DSH 与 Minecraft 共用同一个壳；切换启动器后四个 tab 会显示对应产品的页面。")
                    .textStyle(.micro, tone: .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 快捷键行。
    private func shortcutRow(_ keys: String, _ title: String) -> some View {
        HStack(spacing: LauncherSpace.sm) {
            LauncherMonoText(keys, tone: .secondary, size: 11)
                .frame(width: 72, alignment: .leading)
            Text(title)
                .textStyle(.caption, tone: .secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 派生数据

    /// 设置里选中的实例（严格按实例 ID）。
    private var selectedInstance: DSHInstalledVersion? {
        versions.selectedInstalledVersion
    }

    /// 实例统计："N 个实例 · M 个整合包"。
    private var instanceStatsText: String {
        let total = versions.installed.count
        let packs = versions.installed.filter(\.isPack).count
        guard total > 0 else { return "还没有实例" }
        return "\(total) 个实例 · \(packs) 个整合包"
    }

    // MARK: - 数据加载

    /// 消费路由分区跳转（设置页 / 启动页跳「更多 → 日志」时传 "logs"）。
    private func consumePendingSection() {
        guard let raw = router.pendingMoreSection else { return }
        router.pendingMoreSection = nil
        guard let parsed = DSHMoreSection(rawValue: raw) else { return }
        section = parsed
    }

    /// 首屏加载日志文件与目录统计（快照模式跳过异步读盘）。
    private func loadDataIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        // 首帧先给一次同步的日志文件清单，保证交互模式不会出现"空列表闪一下"。
        logFiles = DSHMoreLogTools.scan(paths: versions.paths, instances: versions.installed)
        guard !snapshotMode else {
            // 快照模式：日志扫描 / 尾部读取都是小文件同步操作，保持截图内容确定。
            if let file = selectedLogFile {
                fileLogLines = DSHMoreLogTools.readTail(paths: versions.paths, instanceID: file.instanceID)
            }
            return
        }
        refreshLogInfo()
        reloadDirectories(showsToast: false)
    }

    /// 重新扫描所有实例日志 + 读取当前选中日志尾部。
    private func refreshLogInfo() {
        logFiles = DSHMoreLogTools.scan(paths: versions.paths, instances: versions.installed)
        if selectedLogInstanceID == nil {
            selectedLogInstanceID = dshProcess.activeInstanceID
                ?? (versions.settings.dshSelectedInstanceID.isEmpty ? nil : versions.settings.dshSelectedInstanceID)
        }
        guard let file = selectedLogFile else {
            fileLogLines = []
            return
        }
        if file.instanceID == dshProcess.activeInstanceID, !dshProcess.logLines.isEmpty {
            fileLogLines = []
            return
        }
        fileLogLines = DSHMoreLogTools.readTail(paths: versions.paths, instanceID: file.instanceID)
    }

    /// 日志滚动到底部。
    private func scrollLogToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = displayLines.indices.last else { return }
        if animated, !snapshotMode {
            withAnimation(LauncherMotion.smooth) {
                proxy.scrollTo(last, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }
}

// MARK: - 实例日志文件

/// 一个实例的日志文件（文件名 = 实例 ID；展示时优先映射实例名）。
private struct DSHMoreLogFile: Identifiable, Equatable {
    let instanceID: String
    let instanceName: String
    let url: URL
    let exists: Bool
    let bytes: Int64
    let modifiedAt: Date?

    var id: String { instanceID }

    /// 展示名：优先实例名，其次实例 ID。
    var displayName: String {
        instanceName.isEmpty ? instanceID : instanceName
    }

    var sizeText: String {
        exists ? DSHFormatting.byteCount(bytes) : "不存在"
    }

    var modifiedText: String {
        DSHFormatting.dateTime(modifiedAt)
    }
}

/// 实例日志文件工具：扫描所有实例 + 读取尾部 + 截断。
private enum DSHMoreLogTools {

    /// 扫描所有实例的 logs/<实例ID>.log；同时把已卸载实例留下的孤立日志也列出来（用实例 ID 展示）。
    static func scan(paths: DSHPaths, instances: [DSHInstalledVersion]) -> [DSHMoreLogFile] {
        let fileManager = FileManager.default
        var files: [DSHMoreLogFile] = instances.map { instance in
            let url = paths.logFile(for: instance.id)
            return file(
                instanceID: instance.id,
                instanceName: instance.name,
                url: url
            )
        }
        // 孤立日志（实例已删除但日志还在）：文件名即实例 ID。
        let known = Set(instances.map(\.id))
        if let entries = try? fileManager.contentsOfDirectory(
            at: paths.logsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in entries where url.pathExtension.lowercased() == "log" {
                let instanceID = url.deletingPathExtension().lastPathComponent
                guard !instanceID.isEmpty, !known.contains(instanceID) else { continue }
                files.append(file(instanceID: instanceID, instanceName: "", url: url))
            }
        }
        return files
    }

    /// 读取单个日志文件信息。
    static func file(instanceID: String, instanceName: String, url: URL) -> DSHMoreLogFile {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return DSHMoreLogFile(
                instanceID: instanceID,
                instanceName: instanceName,
                url: url,
                exists: false,
                bytes: 0,
                modifiedAt: nil
            )
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return DSHMoreLogFile(
            instanceID: instanceID,
            instanceName: instanceName,
            url: url,
            exists: true,
            bytes: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate
        )
    }

    /// 读取日志尾部（复用公共工具；参数是实例 ID）。
    static func readTail(paths: DSHPaths, instanceID: String, maxLines: Int = 200) -> [String] {
        DSHLogTools.readTail(paths: paths, version: instanceID, maxLines: maxLines)
    }

    /// 真实清空日志文件（截断为 0 字节）。
    @discardableResult
    static func truncate(paths: DSHPaths, instanceID: String) throws -> Bool {
        try DSHLogTools.truncate(paths: paths, version: instanceID)
    }
}

// MARK: - 数据目录

/// DSH 数据目录种类（实例化后：versions / homes / cache / logs）。
private enum DSHMoreDirectoryKind: String, CaseIterable, Identifiable {
    case versions
    case homes
    case cache
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .versions: return "实例运行目录（versions）"
        case .homes: return "实例数据目录（homes）"
        case .cache: return "缓存目录"
        case .logs: return "日志目录"
        }
    }

    var detail: String {
        switch self {
        case .versions: return "每个实例独立的 node_modules（同一 DSH 版本可装多个实例）"
        case .homes: return "每个实例独立的 DSH_HOME（插件 / 会话；登录凭据复用 ~/.dsh）"
        case .cache: return "版本列表与插件市场缓存"
        case .logs: return "每个实例的 Web UI 日志（<实例ID>.log）"
        }
    }

    func url(paths: DSHPaths) -> URL {
        switch self {
        case .versions: return paths.versionsDirectory
        case .homes: return paths.homesDirectory
        case .cache: return paths.cacheDirectory
        case .logs: return paths.logsDirectory
        }
    }
}

/// 一个数据目录的真实信息。
private struct DSHMoreDirectory: Identifiable, Equatable {
    let kind: DSHMoreDirectoryKind
    let path: String
    let bytes: Int64
    let exists: Bool

    var id: String { kind.rawValue }
    var title: String { kind.title }
    var detail: String { kind.detail }
    var sizeText: String { exists ? DSHFormatting.byteCount(bytes) : "不存在" }
}

/// 数据目录统计。
private enum DSHMoreDirectoryTools {
    static func directories(paths: DSHPaths, instances: [DSHInstalledVersion]) -> [DSHMoreDirectory] {
        let fileManager = FileManager.default
        return DSHMoreDirectoryKind.allCases.map { kind in
            let url = kind.url(paths: paths)
            let exists = fileManager.fileExists(atPath: url.path)
            let bytes: Int64
            switch kind {
            case .versions:
                // 实例目录占用：优先用已扫描的实例体积，避免重复深扫。
                bytes = instances.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
            case .homes:
                bytes = exists ? paths.directorySize(paths.homesDirectory) : 0
            case .cache, .logs:
                bytes = exists ? paths.directorySize(url) : 0
            }
            return DSHMoreDirectory(kind: kind, path: url.path, bytes: bytes, exists: exists)
        }
    }
}

/// 数据目录行：标题 / 路径 / 大小 / 打开按钮。
private struct DSHMoreDirectoryRow: View {
    @Environment(\.launcherTheme) private var theme

    let title: String
    let subtitle: String
    let path: String
    let sizeText: String
    let exists: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                HStack(spacing: LauncherSpace.xs) {
                    Text(title)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    LauncherBadge(sizeText, tone: exists ? .neutral : .warning)
                }
                Text(subtitle)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
                LauncherMonoText(path, tone: .tertiary, size: 10)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: LauncherSpace.sm)
            LauncherIconButton(
                systemImage: "folder",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "在访达中打开\(title)",
                isDisabled: !exists
            ) {
                onOpen()
            }
        }
        .padding(.vertical, LauncherSpace.xs)
    }
}
