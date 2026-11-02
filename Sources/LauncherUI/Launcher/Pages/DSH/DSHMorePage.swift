import SwiftUI
import AppKit

// MARK: - DSH 更多页

/// DSH 启动器的「更多」页：与 Minecraft 更多页同构（左侧分区 + 右侧内容）。
///
/// 分区：运行日志（真实进程输出 / 日志文件）、数据目录（真实大小 / 打开）、
/// 进程（Web UI 状态 / 打开 / 复制地址 / 停止）、关于（版本说明与快捷键）。
public struct DSHMorePage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherRouter.self) private var router
    @Environment(DSHVersionStore.self) private var versions
    @Environment(DSHProcessController.self) private var dshProcess
    @Environment(DSHPluginStore.self) private var plugins
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    // MARK: 页面状态

    /// 当前分区
    @State private var section: DSHMoreSection = .logs
    /// 从日志文件读到的行（进程未运行时展示历史日志）
    @State private var fileLogLines: [String] = []
    /// 日志文件信息（大小 / 修改时间）
    @State private var logInfo: DSHLogFileInfo?
    /// 数据目录统计
    @State private var directoryRows: [DSHDataDirectory] = []
    /// 刷新日志 / 目录中
    @State private var isRefreshing = false
    /// 是否已经加载过磁盘数据（避免重复读盘）
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
            // 进程状态变化后刷新日志文件信息（真实文件增长 / 停止写入）
            guard !snapshotMode else { return }
            refreshLogInfo()
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

    /// 分区行右侧徽标。
    private func sectionSideBadge(_ item: DSHMoreSection) -> String? {
        switch item {
        case .logs:
            let lines = displayLines.count
            return lines == 0 ? nil : "\(lines) 行"
        case .directories:
            return nil
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
            return logDisplayVersion
        case .directories:
            return DSHFormatting.byteCount(directoryDisplayRows.reduce(Int64(0)) { $0 + $1.bytes })
        case .process:
            return processStatus.title
        case .about:
            return LauncherBuildInfo.current.versionText
        }
    }

    // MARK: - 1. 运行日志

    /// 展示中的日志版本。
    private var logDisplayVersion: String? {
        DSHLogTools.displayVersion(selected: versions.selectedInstalledVersion, active: dshProcess.activeVersion)
    }

    /// 实际展示的日志行：进程内存日志优先，其次磁盘日志文件。
    private var displayLines: [String] {
        if !dshProcess.logLines.isEmpty {
            return Array(dshProcess.logLines.suffix(200))
        }
        return fileLogLines
    }

    /// 当前日志文件信息（进程未启动时也要显示历史文件）。
    private var currentLogInfo: DSHLogFileInfo {
        if let logInfo { return logInfo }
        return DSHLogTools.info(paths: versions.paths, version: logDisplayVersion)
    }

    /// 运行日志分区：真实日志控制台 + 复制 / 刷新 / 访达 / 清空。
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
                    if let logDisplayVersion {
                        LauncherBadge(logDisplayVersion, tone: .info)
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
                        isDisabled: !currentLogInfo.exists
                    ) {
                        revealLogFile()
                    }
                    .fixedSize()
                    LauncherButton(
                        "清空日志",
                        systemImage: "trash",
                        variant: .secondary,
                        size: .small,
                        isDisabled: !currentLogInfo.exists || currentLogInfo.bytes == 0
                    ) {
                        confirmClearLog()
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                }

                logConsole

                HStack(spacing: LauncherSpace.xs) {
                    if logDisplayVersion == nil {
                        Text("还没有选中 DSH 版本：选择并启动一次后这里会显示日志文件路径")
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    } else {
                        LauncherMonoText(currentLogInfo.url.path, tone: .tertiary, size: 10)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: LauncherSpace.sm)
                        Text("\(currentLogInfo.sizeText) · \(currentLogInfo.modifiedText)")
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    /// 日志卡说明。
    private var logSubtitle: String {
        if dshProcess.isRunning {
            return "DSH Web UI 正在运行，实时输出会持续追加"
        }
        return "显示最近一次 Web UI 运行的输出；文件日志保留在 logs/ 目录"
    }

    /// 日志控制台（固定高度 + 内部滚动，不撑高页面）。
    /// 空态直接用 `LauncherEmptyState`（自带面板底），有日志时才是等宽滚动区。
    private var logConsole: some View {
        Group {
            if displayLines.isEmpty {
                LauncherEmptyState(
                    systemImage: "text.alignleft",
                    title: "还没有日志",
                    message: "启动一次 DSH Web UI 后，进程输出会写到这里；也可以先看 logs/ 里的历史日志。"
                )
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
                        guard !snapshotMode else { return }
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

    /// 刷新日志：重新读文件信息与文件尾部。
    private func refreshLogs() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let version = logDisplayVersion
        let paths = versions.paths
        Task { @MainActor in
            let info = DSHLogTools.info(paths: paths, version: version)
            let lines = snapshotMode ? [] : DSHLogTools.readTail(paths: paths, version: version)
            logInfo = info
            if dshProcess.logLines.isEmpty { fileLogLines = lines }
            isRefreshing = false
            let count = dshProcess.logLines.isEmpty ? lines.count : dshProcess.logLines.count
            router.showToast("日志已刷新（\(count) 行）")
        }
    }

    /// 在访达中显示日志文件。
    private func revealLogFile() {
        guard currentLogInfo.exists else {
            router.showToast("日志文件还不存在，先启动一次 DSH Web UI", tone: .warning)
            return
        }
        InstanceActions.reveal(currentLogInfo.url)
    }

    /// 清空日志前确认（真实截断文件）。
    private func confirmClearLog() {
        let info = currentLogInfo
        guard info.exists else {
            router.showToast("日志文件还不存在", tone: .info)
            return
        }
        router.showDialog(
            LauncherDialogRequest(
                title: "清空 DSH 日志？",
                message: "将把 \(info.url.lastPathComponent)（\(info.sizeText)）截断为 0 字节。\(dshProcess.isRunning ? "DSH Web UI 仍在运行，后续输出会继续写入。" : "此操作不可撤销。")",
                confirmTitle: "清空",
                isDestructive: true,
                onConfirm: {
                    do {
                        _ = try DSHLogTools.truncate(paths: versions.paths, version: logDisplayVersion)
                        fileLogLines = []
                        logInfo = DSHLogTools.info(paths: versions.paths, version: logDisplayVersion)
                        router.showToast(
                            dshProcess.isRunning
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

    /// 数据目录分区：真实大小 + 在访达中打开 + 当前 profile。
    private var directoriesContent: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherCardHeader(
                        title: "数据目录",
                        subtitle: "版本 / 缓存 / 工具 / 日志位于启动器目录；DSH_HOME 由所有版本共享",
                        systemImage: "folder.fill"
                    )
                    Spacer(minLength: LauncherSpace.sm)
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
                        DSHDataDirectoryRow(
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
    private var directoryDisplayRows: [DSHDataDirectory] {
        if !directoryRows.isEmpty { return directoryRows }
        if snapshotMode {
            return DSHDataTools.directories(paths: versions.paths)
        }
        return DSHDataDirectoryKind.allCases.map { kind in
            DSHDataDirectory(kind: kind, path: kind.url(paths: versions.paths).path, bytes: 0, exists: false)
        }
    }

    /// 当前版本 profile 行。
    private var profileRow: some View {
        let version = dshProcess.activeVersion ?? versions.selectedInstalledVersion?.version
        let path = DSHDataTools.profilePath(paths: versions.paths, version: version)
        return HStack(spacing: LauncherSpace.sm) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text("当前版本 Profile")
                    .textStyle(.bodyStrong)
                    .lineLimit(1)
                Text(path == nil ? "还没有选中版本：先在「启动」页选择并启动一次" : "DSH_HOME 下的 profiles/web（插件 / 会话；登录凭据复用 ~/.dsh）")
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
                accessibilityLabel: "打开当前版本 Profile",
                isDisabled: !(path.map { FileManager.default.fileExists(atPath: $0) } ?? false)
            ) {
                if let path {
                    let url = URL(fileURLWithPath: path)
                    if InstanceActions.open(url) {
                        router.showToast("已在访达中打开当前版本 Profile")
                    } else {
                        router.showToast("目录不存在：启动一次后会自动创建", tone: .warning)
                    }
                }
            }
        }
        .padding(.top, LauncherSpace.xs)
    }

    /// 打开数据目录。
    private func openDirectory(_ row: DSHDataDirectory) {
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
        Task { @MainActor in
            let rows = await Task.detached(priority: .userInitiated) {
                DSHDataTools.directories(paths: paths)
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

    /// 进程状态文案。
    private var processStatus: DSHProcessStatusText {
        DSHProcessStatusFormatter.text(
            for: dshProcess.state,
            port: dshProcess.activePort,
            startedAt: dshProcess.startedAt
        )
    }

    /// 进程分区：状态、端口、启动时间、打开 / 复制 / 停止。
    private var processContent: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherCardHeader(
                        title: "DSH Web UI 进程",
                        subtitle: "校验状态来自真实子进程输出",
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
                        message: "在「启动」页选择版本并启动后，这里会显示端口、启动时间与带一次性 token 的地址。"
                    )
                } else {
                    VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        DSHInfoRow(title: "状态", value: processStatus.title, isMissing: processStatus.isError)
                        DSHInfoRow(title: "端口", value: dshProcess.activePort.map { "\($0)" } ?? "—", isMissing: dshProcess.activePort == nil)
                        DSHInfoRow(title: "启动时间", value: DSHFormatting.dateTime(dshProcess.startedAt), isMissing: dshProcess.startedAt == nil)
                        DSHInfoRow(title: "运行版本", value: dshProcess.activeVersion ?? "—", isMissing: dshProcess.activeVersion == nil)
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
                        stopProcess()
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

    /// 停止进程（真实 terminate）。
    private func stopProcess() {
        Task { @MainActor in
            await dshProcess.stop()
            refreshLogInfo()
            router.showToast("DSH Web UI 已停止", tone: .warning)
        }
    }

    // MARK: - 4. 关于

    /// 关于分区：版本说明 + 快捷键。
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
                    DSHInfoRow(title: "DSH_HOME（所有版本共享）", value: versions.paths.homeRoot.path)
                    DSHInfoRow(
                        title: "已安装版本",
                        value: DSHFormatting.installedSummary(versions.installed),
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

    // MARK: - 数据加载

    /// 消费路由分区跳转（设置页「进程状态」按钮会传 "process"）。
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
        guard !snapshotMode else { return }
        refreshLogInfo()
        reloadDirectories(showsToast: false)
    }

    /// 读取日志文件信息与尾部日志。
    private func refreshLogInfo() {
        let version = logDisplayVersion
        let paths = versions.paths
        logInfo = DSHLogTools.info(paths: paths, version: version)
        if dshProcess.logLines.isEmpty {
            fileLogLines = DSHLogTools.readTail(paths: paths, version: version)
        }
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
