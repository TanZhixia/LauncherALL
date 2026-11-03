import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - DSH 启动页

/// DSH 启动页（与 Minecraft 启动页同构）：左侧「DSH 实例」列表，右侧当前实例 / 启动 Web UI / 运行状态 / 实时日志 / 环境与插件。
/// 全部交互走真实 `DSHVersionStore` / `DSHProcessController` / `DSHPluginStore` / `DSHPackService`：
/// 启动即真实拉起 `dsh --profile web --no-open --port …`，停止 / 卸载前二次确认，导出整合包走保存面板 + 真实 zip。
public struct DSHLaunchPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(DSHVersionStore.self) private var versions
    @Environment(DSHProcessController.self) private var dshProcess
    @Environment(DSHPluginStore.self) private var plugins
    @Environment(DSHPackService.self) private var packs
    @Environment(LauncherRouter.self) private var router
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    @State private var searchText = ""
    /// 本页是否发起过导出（用于区分下载页的导入 / 导出失败状态）。
    @State private var exportAttempted = false

    /// 实时日志视口高度：固定值保证 1080×720 下首屏不出现纵向滚动。
    private let logViewportHeight: CGFloat = LauncherSpace.xxxl * 2 + LauncherSpace.xl

    public init() {}

    public var body: some View {
        LauncherPageLayout(sideWidth: 300) {
            sidePanel
        } main: {
            LauncherMainPanel {
                mainHeader
                launchCard
                if isExporting || (isExportFailed && exportAttempted) {
                    exportProgressCard
                }
                statusCard
                logCard
                environmentAndPluginRow
            }
        }
        .task { await prepare() }
        .onChange(of: dshProcess.state) { _, newState in
            guard !snapshotMode else { return }
            let instanceName = DSHLaunchPresentation.runningInstance(
                in: versions.installed,
                activeInstanceID: dshProcess.activeInstanceID
            )?.name
            switch newState {
            case .running:
                router.showToast("DSH Web UI 已启动\(instanceName.map { "：\($0)" } ?? "")")
            case .failed(let message):
                router.showToast("DSH 启动失败：\(message)", tone: .danger)
            case .idle, .starting, .stopping:
                break
            }
        }
    }

    // MARK: - 生命周期

    /// 首次进入：扫描已安装实例；交互模式下拉取 npm 版本目录（用于 latest 徽标）。
    /// 离屏快照模式不联网、不启动进程、不弹面板，保证渲染结果确定。
    private func prepare() async {
        versions.refreshInstalled()
        guard !snapshotMode else { return }
        if versions.catalog == nil {
            await versions.refreshCatalog()
        }
    }

    // MARK: - 左侧 DSH 实例面板

    private var sidePanel: some View {
        LauncherSidePanel(
            title: "DSH 实例",
            count: "\(versions.installed.count)",
            width: 300,
            searchText: $searchText,
            searchPlaceholder: "搜索实例或版本",
            toolbar: AnyView(sideToolbar),
            content: { sideContent },
            footer: { sideFooter }
        )
    }

    /// 左面板工具栏：刷新已安装实例 / 去下载安装新实例。
    private var sideToolbar: some View {
        HStack(spacing: LauncherSpace.xxs) {
            LauncherIconButton(
                systemImage: "arrow.clockwise",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "刷新已安装 DSH 实例",
                isDisabled: versions.isInstalling
            ) {
                refreshInstalledInstances()
            }
            LauncherIconButton(
                systemImage: "plus",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "安装新实例"
            ) {
                openDownload()
            }
        }
    }

    @ViewBuilder
    private var sideContent: some View {
        if versions.installed.isEmpty {
            LauncherEmptyState(
                systemImage: "shippingbox",
                title: "还没有 DSH 实例",
                message: "去「下载」安装官方 @deepseek-ai/dsh，或导入 .dshpack 整合包后即可启动 Web UI。",
                actionTitle: "去下载 DSH",
                onAction: openDownload
            )
        } else if filteredInstances.isEmpty {
            LauncherEmptyState(
                systemImage: "magnifyingglass",
                title: "没有匹配的实例",
                message: "换个关键词试试，当前已安装 \(versions.installed.count) 个实例。",
                actionTitle: "清除搜索",
                onAction: { searchText = "" }
            )
        } else {
            LauncherSidePanelGroup("已安装", trailing: "\(filteredInstances.count)")
            ForEach(filteredInstances) { instance in
                instanceRow(instance)
            }
        }
    }

    /// 单个实例行：实例名 + `DSH <dshVersion>` + 运行中 / 整合包徽标。
    private func instanceRow(_ instance: DSHInstalledVersion) -> some View {
        let isRunning = DSHLaunchPresentation.isRunning(instance, activeInstanceID: dshProcess.activeInstanceID)
        let isSelected = versions.selectedInstalledVersion?.id == instance.id

        return LauncherListRow(
            title: instance.name,
            subtitle: DSHLaunchPresentation.listSubtitle(instance),
            systemImage: instance.isPack ? "shippingbox.fill" : "cube.fill",
            badge: DSHLaunchPresentation.instanceBadge(instance, isRunning: isRunning),
            accessory: AnyView(
                HStack(spacing: LauncherSpace.xs) {
                    if isRunning {
                        LauncherStatusDot(tone: .success)
                    }
                    LauncherIconMenu(groups: instanceMenu(instance), accessibilityLabel: "实例操作")
                    Image(systemName: "chevron.right")
                        .textStyle(.caption, tone: .tertiary)
                }
            ),
            isSelected: isSelected,
            action: {
                withAnimation(LauncherMotion.smooth) {
                    versions.select(instance.id)
                }
            }
        )
        .launcherContextMenu(instanceMenu(instance))
    }

    /// 实例右键菜单：设为当前 / 启动 / 目录 / 复制 / 导出整合包 / 卸载。
    private func instanceMenu(_ instance: DSHInstalledVersion) -> [LauncherMenuGroup] {
        let isRunning = DSHLaunchPresentation.isRunning(instance, activeInstanceID: dshProcess.activeInstanceID)
        let processBlocked = dshProcess.isRunning || dshProcess.isBusy
        let exportBlocked = DSHLaunchPresentation.exportDisabledReason(snapshotMode: snapshotMode, isBusy: packs.isBusy)
        let uninstallBlocked = DSHLaunchPresentation.uninstallDisabledReason(
            instance: instance,
            activeInstanceID: dshProcess.activeInstanceID,
            isBusy: dshProcess.isBusy,
            isInstalling: versions.isInstalling
        )

        return [
            LauncherMenuGroup(items: [
                LauncherMenuItem("设为当前实例", systemImage: "checkmark.circle", action: {
                    versions.select(instance.id)
                    router.showToast("已选择实例「\(instance.name)」")
                }),
                LauncherMenuItem(
                    "启动此实例 Web UI",
                    systemImage: "play.fill",
                    detail: processBlocked ? "DSH 正在运行 / 处理中，请先停止" : nil,
                    isDisabled: processBlocked,
                    action: { start(instance) }
                ),
                LauncherMenuItem("在 Finder 中显示实例目录", systemImage: "folder", action: {
                    InstanceActions.reveal(URL(fileURLWithPath: instance.path))
                }),
                LauncherMenuItem("打开实例 DSH_HOME", systemImage: "house", action: {
                    openHomeDirectory(for: instance)
                }),
                LauncherMenuItem("复制实例名", systemImage: "doc.on.doc", action: {
                    InstanceActions.copy(instance.name)
                    router.showToast("已复制实例名")
                })
            ]),
            LauncherMenuGroup(title: "整合包", items: [
                LauncherMenuItem(
                    DSHLaunchPresentation.exportMenuTitle(runtime: .bundled),
                    systemImage: "shippingbox.and.arrow.backward",
                    detail: exportBlocked,
                    isDisabled: exportBlocked != nil,
                    action: { chooseExport(instance: instance, runtime: .bundled) }
                ),
                LauncherMenuItem(
                    DSHLaunchPresentation.exportMenuTitle(runtime: .online),
                    systemImage: "shippingbox",
                    detail: exportBlocked,
                    isDisabled: exportBlocked != nil,
                    action: { chooseExport(instance: instance, runtime: .online) }
                )
            ]),
            LauncherMenuGroup(items: [
                LauncherMenuItem(
                    isRunning ? "卸载实例…（请先停止）" : "卸载实例…",
                    systemImage: "trash",
                    tone: .danger,
                    isDisabled: uninstallBlocked != nil,
                    action: { confirmUninstall(instance) }
                )
            ])
        ]
    }

    /// 左面板底部：当前选中实例 + 真实环境摘要。
    private var sideFooter: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            Rectangle()
                .fill(theme.colors.stroke)
                .frame(height: 1)

            HStack(spacing: LauncherSpace.xs) {
                LauncherLabel("当前实例")
                Spacer(minLength: LauncherSpace.xs)
                if let instance = selectedInstance {
                    LauncherMonoText(instance.name, tone: .primary)
                        .lineLimit(1)
                } else {
                    Text("未选择")
                        .textStyle(.micro, tone: .tertiary)
                }
            }

            HStack(alignment: .top, spacing: LauncherSpace.xs) {
                Image(systemName: "cpu")
                    .textStyle(.micro, tone: .tertiary)
                Text(environment.environmentText)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, LauncherSpace.xxs)
    }

    // MARK: - 右侧页头

    private var mainHeader: some View {
        LauncherPanelHeader("DSH 启动器", subtitle: headerSubtitle) {
            HStack(spacing: LauncherSpace.xs) {
                LauncherBadge(
                    DSHLaunchPresentation.statusTitle(dshProcess.state),
                    tone: DSHLaunchPresentation.statusTone(dshProcess.state),
                    systemImage: DSHLaunchPresentation.statusIcon(dshProcess.state)
                )
                LauncherIconButton(
                    systemImage: "folder",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: "打开 DSH 数据目录"
                ) {
                    openDSHRoot()
                }
            }
        }
    }

    /// 页头副标题：当前实例名 + DSH 版本 + 整合包 / 运行中标注。
    private var headerSubtitle: String {
        guard let instance = displayInstance else {
            return "未选择实例 · 先在左侧安装或选择 DSH 实例"
        }
        var parts = [instance.name, "DSH \(instance.dshVersion)"]
        if instance.isPack { parts.append("整合包") }
        if DSHLaunchPresentation.isRunning(instance, activeInstanceID: dshProcess.activeInstanceID) {
            parts.append("运行中")
        } else if let running = DSHLaunchPresentation.runningInstance(in: versions.installed, activeInstanceID: dshProcess.activeInstanceID) {
            parts.append("运行中：\(running.name)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 当前实例启动卡

    /// 当前实例卡：实例名、DSH 版本 + 安装时间/体积、整合包来源、端口、Node 状态 + 启动 / 打开 / 复制地址 / 停止。
    private var launchCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                HStack(alignment: .top, spacing: LauncherSpace.md) {
                    VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        HStack(spacing: LauncherSpace.sm) {
                            Text(displayInstance?.name ?? "未选择 DSH 实例")
                                .textStyle(.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            LauncherBadge(
                                DSHLaunchPresentation.statusTitle(dshProcess.state),
                                tone: DSHLaunchPresentation.statusTone(dshProcess.state),
                                systemImage: DSHLaunchPresentation.statusIcon(dshProcess.state)
                            )
                            if displayInstance?.isPack == true {
                                LauncherBadge("整合包", tone: .accent, systemImage: "shippingbox.fill")
                            }
                        }

                        if let instance = displayInstance {
                            Text(DSHLaunchPresentation.detailSubtitle(instance))
                                .textStyle(.micro, tone: .tertiary)
                                .lineLimit(1)
                            if let packInfo = DSHLaunchPresentation.packInfoText(instance) {
                                HStack(spacing: LauncherSpace.xs) {
                                    Image(systemName: "shippingbox")
                                        .textStyle(.micro, tone: .tertiary)
                                    Text(packInfo)
                                        .textStyle(.micro, tone: .secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        HStack(spacing: LauncherSpace.xs) {
                            LauncherBadge("端口 \(portText)", tone: .neutral, systemImage: "number")
                            if let instance = displayInstance,
                               DSHLaunchPresentation.isLatest(instance, latestVersion: latestVersionText) {
                                LauncherBadge("latest", tone: .accent)
                            }
                            if environment.isPlaceholder {
                                LauncherBadge("快照模式", tone: .neutral, systemImage: "camera")
                            } else {
                                LauncherBadge(
                                    environment.hasNode ? "Node 就绪" : "缺少 Node",
                                    tone: environment.hasNode ? .success : .danger,
                                    systemImage: environment.hasNode ? "checkmark.circle.fill" : "xmark.octagon.fill"
                                )
                            }
                        }
                    }

                    Spacer(minLength: LauncherSpace.sm)

                    launchActions
                }

                if let installText = DSHLaunchPresentation.installPhaseText(versions.installState) {
                    HStack(spacing: LauncherSpace.xs) {
                        if versions.isInstalling {
                            LauncherSpinner(size: 12)
                        } else if DSHLaunchPresentation.isInstallFailed(versions.installState) {
                            Image(systemName: "xmark.octagon.fill")
                                .textStyle(.micro, tone: .danger)
                        }
                        Text(installText)
                            .textStyle(.micro, tone: DSHLaunchPresentation.isInstallFailed(versions.installState) ? .danger : .secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }

                if case .failed(let message) = dshProcess.state {
                    // 内联错误（不额外撑高首屏）：失败文案 + 重试，全部来自真实 state。
                    HStack(spacing: LauncherSpace.xs) {
                        Image(systemName: "xmark.octagon.fill")
                            .textStyle(.micro, tone: .danger)
                        Text(message)
                            .textStyle(.micro, tone: .danger)
                            .lineLimit(2)
                        Spacer(minLength: LauncherSpace.xs)
                        LauncherButton("重试", systemImage: "arrow.clockwise", variant: .secondary, size: .small) {
                            startSelected()
                        }
                    }
                    .padding(.horizontal, LauncherSpace.sm)
                    .padding(.vertical, LauncherSpace.xs)
                    .glassBackground(level: .subtle, cornerRadius: LauncherRadius.sm)
                } else if !snapshotMode,
                          let reason = startDisabledReason,
                          !dshProcess.isRunning,
                          !dshProcess.isBusy,
                          !versions.isInstalling {
                    HStack(spacing: LauncherSpace.xs) {
                        Image(systemName: "info.circle")
                            .textStyle(.micro, tone: .warning)
                        Text(reason)
                            .textStyle(.micro, tone: .warning)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// 启动卡按钮组：按进程状态切换 启动 / 打开 / 复制地址 / 停止。
    @ViewBuilder
    private var launchActions: some View {
        if dshProcess.isBusy {
            LauncherButton(
                dshProcess.state.isRunning ? "停止中…" : "启动中…",
                systemImage: "hourglass",
                variant: .secondary,
                size: .medium,
                isLoading: true
            ) {}
        } else if dshProcess.isRunning {
            HStack(spacing: LauncherSpace.xs) {
                LauncherButton("打开 DSH Web UI", systemImage: "safari", variant: .primary, size: .medium) {
                    openWebUI()
                }
                LauncherButton("复制启动地址", systemImage: "doc.on.doc", variant: .secondary, size: .medium) {
                    copyWebURL()
                }
                LauncherButton("停止", systemImage: "stop.fill", variant: .danger, size: .medium) {
                    confirmStop()
                }
            }
        } else {
            HStack(spacing: LauncherSpace.xs) {
                LauncherButton(
                    "启动 DSH Web UI",
                    systemImage: "play.fill",
                    variant: .primary,
                    size: .medium,
                    isDisabled: startDisabledReason != nil
                ) {
                    startSelected()
                }
                .launcherTooltip(startDisabledReason ?? "真实启动 dsh web 进程，并在默认浏览器打开带一次性 token 的地址")

                if displayInstance == nil {
                    LauncherButton("去下载", systemImage: "arrow.down.circle", variant: .secondary, size: .medium) {
                        openDownload()
                    }
                }
            }
        }
    }

    // MARK: - 整合包导出进度

    /// 是否正在导出整合包。
    private var isExporting: Bool {
        if case .exporting = packs.state { return true }
        return false
    }

    /// 导出失败态（仅本页发起导出后展示，避免误显示下载页的导入失败）。
    private var isExportFailed: Bool {
        if case .failed = packs.state { return true }
        return false
    }

    /// 导出进度卡：阶段 + 进度条 + 最后一行日志 + 取消；失败时显示错误并允许关闭。
    @ViewBuilder
    private var exportProgressCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: isExportFailed ? "整合包导出失败" : "正在导出整合包",
                    subtitle: exportProgressSubtitle,
                    accessory: AnyView(
                        HStack(spacing: LauncherSpace.xs) {
                            if packs.isBusy {
                                LauncherButton("取消", systemImage: "xmark", variant: .secondary, size: .small) {
                                    packs.cancel()
                                    router.showToast("已请求取消导出", tone: .warning)
                                }
                            } else {
                                LauncherButton("关闭", systemImage: "xmark", variant: .ghost, size: .small) {
                                    packs.reset()
                                    exportAttempted = false
                                }
                            }
                        }
                    )
                )

                if case .exporting(_, _, let progress) = packs.state {
                    LauncherProgressBar(
                        value: progress,
                        label: "\(Int((progress * 100).rounded()))%",
                        tone: .accent,
                        height: 4
                    )
                }

                if let lastLine = packs.logLines.last {
                    LauncherMonoText(lastLine, tone: .tertiary, size: 10)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var exportProgressSubtitle: String {
        DSHLaunchPresentation.exportPhaseText(packs.state) ?? "准备导出…"
    }

    // MARK: - 运行状态卡片

    /// 运行状态卡：运行中显示实例 / 脱敏 URL / 端口 / 启动时间；未运行显示行为说明。
    private var statusCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            HStack(alignment: .center, spacing: LauncherSpace.md) {
                LauncherStatusDot(
                    tone: DSHLaunchPresentation.statusTone(dshProcess.state),
                    isPulsing: dshProcess.isBusy
                )

                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    HStack(spacing: LauncherSpace.xs) {
                        Text(DSHLaunchPresentation.statusTitle(dshProcess.state))
                            .textStyle(.bodyStrong)
                            .lineLimit(1)
                        if let runningName {
                            LauncherBadge(runningName, tone: .neutral, systemImage: "play.circle.fill")
                        }
                    }
                    Text(DSHLaunchPresentation.statusDetail(dshProcess.state))
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: LauncherSpace.sm)

                if dshProcess.isRunning {
                    LauncherMonoText("端口 \(portText)", tone: .secondary, size: 10)
                    LauncherMonoText(DSHLaunchPresentation.startedAtText(dshProcess.startedAt), tone: .tertiary, size: 10)
                    LauncherButton("在浏览器中打开", systemImage: "safari", variant: .secondary, size: .small) {
                        openInBrowser()
                    }
                    LauncherButton("复制地址", systemImage: "doc.on.doc", variant: .ghost, size: .small) {
                        copyWebURL()
                    }
                } else {
                    LauncherBadge(
                        versions.settings.dshAutoOpenBrowser ? "启动后自动打开浏览器" : "启动后不自动打开浏览器",
                        tone: .neutral,
                        systemImage: "safari"
                    )
                    LauncherButton("刷新环境", systemImage: "arrow.clockwise", variant: .ghost, size: .small) {
                        refreshInstalledInstances()
                    }
                }
            }
        }
    }

    // MARK: - 实时日志卡片

    /// 实时日志卡：按 activeInstanceID 过滤的最后 12 行输出，自动滚到底部；空态说明。
    private var logCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.sm) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "实时日志",
                    subtitle: logCardSubtitle,
                    accessory: AnyView(
                        HStack(spacing: LauncherSpace.xs) {
                            LauncherButton("打开完整日志", systemImage: "text.alignleft", variant: .ghost, size: .small) {
                                openFullLog()
                            }
                            LauncherIconMenu(groups: [
                                LauncherMenuGroup(items: [
                                    LauncherMenuItem("在访达中显示日志文件", systemImage: "folder", action: openFullLog),
                                    LauncherMenuItem("在更多页查看全部日志", systemImage: "arrow.up.right", action: {
                                        router.go(.more, moreSection: "logs")
                                    })
                                ])
                            ], accessibilityLabel: "日志操作")
                        }
                    )
                )

                if dshProcess.logLines.isEmpty {
                    HStack(spacing: LauncherSpace.xs) {
                        Image(systemName: "terminal")
                            .textStyle(.micro, tone: .tertiary)
                        Text("启动后这里显示 dsh web 输出")
                            .textStyle(.micro, tone: .tertiary)
                        Spacer(minLength: 0)
                    }
                    .padding(LauncherSpace.sm)
                    .frame(maxWidth: .infinity, minHeight: logViewportHeight, alignment: .center)
                    .glassBackground(level: .subtle, cornerRadius: LauncherRadius.md)
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

    private var logCardSubtitle: String {
        if let runningName {
            return "运行实例：\(runningName) · 最后 12 行 · 共 \(dshProcess.logLines.count) 行"
        }
        return "最后 12 行 · 共 \(dshProcess.logLines.count) 行 · dsh web 输出"
    }

    /// 日志本体：离屏模式静态取尾部；交互模式内部滚动并自动跟到底部。
    @ViewBuilder
    private var logConsole: some View {
        if snapshotMode {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                ForEach(Array(DSHLaunchPresentation.logTail(dshProcess.logLines).enumerated()), id: \.offset) { _, line in
                    logLine(line)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(LauncherSpace.sm)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        ForEach(Array(dshProcess.logLines.enumerated()), id: \.offset) { index, line in
                            logLine(line)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LauncherSpace.sm)
                }
                .scrollIndicators(.hidden)
                .onAppear { scrollLogToBottom(proxy, animated: false) }
                .onChange(of: dshProcess.logLines.count) { _, _ in
                    scrollLogToBottom(proxy, animated: true)
                }
            }
        }
    }

    /// 单行日志：mono 11pt，按关键词着色。
    private func logLine(_ line: String) -> some View {
        Text(verbatim: line.isEmpty ? " " : line)
            .font(LauncherTextStyle.monoSmall.font)
            .foregroundStyle(DSHLaunchPresentation.logTone(line).color(in: theme))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollLogToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = dshProcess.logLines.indices.last else { return }
        if animated {
            withAnimation(LauncherMotion.smooth) {
                proxy.scrollTo(last, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    // MARK: - 环境与插件卡片

    private var environmentAndPluginRow: some View {
        HStack(alignment: .top, spacing: LauncherSpace.md) {
            environmentCard
                .frame(maxWidth: .infinity)
            pluginCard
                .frame(maxWidth: .infinity)
        }
    }

    /// 环境与路径卡：Node / 包管理器 / 当前实例的 DSH_HOME + 在访达打开。
    private var environmentCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "环境与路径",
                    subtitle: environment.isPlaceholder
                        ? "快照模式：未检测运行时"
                        : (environment.hasNode ? "Node 运行时已就绪" : "缺少 Node 运行时"),
                    accessory: AnyView(
                        LauncherBadge(
                            environment.isPlaceholder ? "未检测" : (environment.packageManager ?? "无包管理器"),
                            tone: environment.isPlaceholder
                                ? .neutral
                                : (environment.packageManager == nil ? .warning : .neutral)
                        )
                    )
                )

                HStack(spacing: LauncherSpace.xs) {
                    LauncherLabel("DSH_HOME")
                    LauncherBadge("实例独立", tone: .neutral)
                    Spacer(minLength: LauncherSpace.xs)
                    LauncherButton("在访达中打开", systemImage: "folder", variant: .ghost, size: .small) {
                        openHomeDirectory()
                    }
                }

                HStack(spacing: LauncherSpace.xs) {
                    LauncherMonoText(homePathText, tone: .tertiary, size: 10)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: LauncherSpace.xs) {
                    Image(systemName: "key")
                        .textStyle(.micro, tone: .tertiary)
                    Text("每个实例独立的插件 / 会话；登录凭据自动复用 ~/.dsh，不会要求重新输入 API Key。")
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }

                HStack(spacing: LauncherSpace.xs) {
                    Image(systemName: "terminal")
                        .textStyle(.micro, tone: .tertiary)
                    LauncherMonoText(environment.environmentText, tone: .tertiary, size: 10)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 插件入口卡：当前实例的已装插件数 + 管理入口。
    private var pluginCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "插件",
                    subtitle: "当前实例 web profile 的插件",
                    accessory: AnyView(
                        LauncherBadge("\(installedPlugins.count) 个已装", tone: installedPlugins.isEmpty ? .neutral : .success)
                    )
                )

                HStack(alignment: .center, spacing: LauncherSpace.sm) {
                    Text("\(installedPlugins.count)")
                        .textStyle(.title)
                        .lineLimit(1)
                    VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        Text("个已安装插件")
                            .textStyle(.micro, tone: .tertiary)
                        if !installedPlugins.isEmpty {
                            Text(installedPlugins.prefix(2).map(\.name).joined(separator: " · "))
                                .textStyle(.micro, tone: .tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherButton("管理插件", systemImage: "puzzlepiece.extension", variant: .secondary, size: .small) {
                        openPlugins()
                    }
                }
            }
        }
    }

    // MARK: - 派生数据

    /// 严格按 `settings.dshSelectedInstanceID` 选中的实例。
    private var selectedInstance: DSHInstalledVersion? {
        versions.selectedInstalledVersion
    }

    /// 右侧展示用实例：selection 为空（迁移/删除竞态）时退回第一个已安装实例。
    private var displayInstance: DSHInstalledVersion? {
        selectedInstance ?? versions.installed.first
    }

    private var filteredInstances: [DSHInstalledVersion] {
        DSHLaunchPresentation.filteredInstances(versions.installed, query: searchText)
    }

    /// 正在运行的实例名（来自 activeInstanceID，而不是版本号比较）。
    private var runningName: String? {
        DSHLaunchPresentation.runningInstance(in: versions.installed, activeInstanceID: dshProcess.activeInstanceID)?.name
    }

    /// Node / 包管理器探测结果（缓存，避免每次重绘都启动登录 shell；快照模式不探测）。
    private var environment: DSHLaunchEnvironment {
        if snapshotMode { return .placeholder }
        return DSHLaunchEnvironmentCache.snapshot(paths: versions.paths)
    }

    /// npm latest 版本号；目录未加载时为 nil（不显示 latest 徽标）。
    private var latestVersionText: String? {
        versions.latestVersion?.version
    }

    /// 端口：优先当前进程实际端口，其次设置里的默认端口。
    private var portText: String {
        DSHLaunchPresentation.portText(activePort: dshProcess.activePort, fallback: versions.settings.dshPort)
    }

    /// 启动按钮禁用原因；nil 表示可启动。
    private var startDisabledReason: String? {
        DSHLaunchPresentation.startDisabledReason(
            hasSelection: displayInstance != nil,
            hasNode: environment.hasNode,
            isInstalling: versions.isInstalling,
            isBusy: dshProcess.isBusy
        )
    }

    /// 当前实例的 DSH_HOME 路径（每个实例独立；快照模式回退到字面路径）。
    private var homePathText: String {
        if snapshotMode {
            if let instance = displayInstance {
                return "~/Library/Application Support/BlockLauncher/DSH/homes/\(instance.id)"
            }
            return "~/Library/Application Support/BlockLauncher/DSH/homes"
        }
        guard let instance = displayInstance else {
            return versions.paths.homesDirectory.path
        }
        return versions.paths.homeDirectory(for: instance.id).path
    }

    private var installedPlugins: [DSHInstalledPlugin] {
        guard let instance = displayInstance else { return [] }
        return plugins.installedPlugins(for: instance)
    }

    // MARK: - 真实操作

    /// 启动当前展示实例：真实拉起 `dsh --profile web --no-open --port …`。
    private func startSelected() {
        guard let instance = displayInstance else {
            router.showToast("请先在左侧选择已安装的 DSH 实例", tone: .warning)
            return
        }
        start(instance)
    }

    private func start(_ instance: DSHInstalledVersion) {
        guard !dshProcess.isRunning, !dshProcess.isBusy else {
            router.showToast("DSH 正在运行或处理中，请先停止", tone: .warning)
            return
        }
        versions.select(instance.id)
        Task {
            await dshProcess.start(version: instance)
        }
    }

    /// 停止前二次确认（带运行中实例名，会终止进程）。
    private func confirmStop() {
        let name = runningName ?? "DSH Web UI"
        router.showDialog(
            LauncherDialogRequest(
                title: "停止 DSH Web UI？",
                message: "将终止实例「\(name)」的 Web UI 进程，正在进行的会话会中断。可以稍后重新启动。",
                confirmTitle: "停止进程",
                isDestructive: true,
                onConfirm: {
                    Task { await dshProcess.stop() }
                }
            )
        )
    }

    /// 卸载实例前二次确认（删除实例目录与独立 DSH_HOME，不动 ~/.dsh 登录凭据）。
    private func confirmUninstall(_ instance: DSHInstalledVersion) {
        if let reason = DSHLaunchPresentation.uninstallDisabledReason(
            instance: instance,
            activeInstanceID: dshProcess.activeInstanceID,
            isBusy: dshProcess.isBusy,
            isInstalling: versions.isInstalling
        ) {
            router.showToast(reason, tone: .warning)
            return
        }
        router.showDialog(
            LauncherDialogRequest(
                title: "卸载 DSH 实例？",
                message: "将删除实例「\(instance.name)」的版本目录与独立 DSH_HOME（DSH 本体 / 插件 / 会话）。~/.dsh 里的登录凭据不会被删除。",
                confirmTitle: "卸载实例",
                isDestructive: true,
                onConfirm: {
                    if versions.uninstall(instance.id) {
                        router.showToast("已卸载实例「\(instance.name)」")
                    } else {
                        router.showToast("卸载失败：\(versions.lastError?.localizedDescription ?? "未知错误")", tone: .danger)
                    }
                }
            )
        )
    }

    // MARK: 整合包导出

    /// 选择保存位置后真实导出（快照模式不弹面板）。
    private func chooseExport(instance: DSHInstalledVersion, runtime: DSHPackRuntimeMode) {
        if let reason = DSHLaunchPresentation.exportDisabledReason(snapshotMode: snapshotMode, isBusy: packs.isBusy) {
            router.showToast(reason, tone: .info)
            return
        }
        if dshProcess.isRunning, dshProcess.activeInstanceID == instance.id {
            router.showToast("实例「\(instance.name)」正在运行，请先停止再导出整合包", tone: .warning)
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出 DSH 整合包"
        panel.message = runtime.title
        panel.nameFieldStringValue = DSHLaunchPresentation.exportFileName(instanceName: instance.name)
        panel.canCreateDirectories = true
        if let contentType = UTType(filenameExtension: DSHPackFormat.fileExtension) {
            panel.allowedContentTypes = [contentType]
        }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task { await performExport(instance: instance, runtime: runtime, destination: destination) }
    }

    /// 调用 `DSHPackService.exportPack`，成功 toast 路径，失败保留错误卡。
    private func performExport(instance: DSHInstalledVersion, runtime: DSHPackRuntimeMode, destination: URL) async {
        exportAttempted = true
        let exported = await packs.exportPack(
            instance: instance,
            name: DSHLaunchPresentation.exportPackName(instance: instance),
            version: DSHLaunchPresentation.exportPackVersion(instance: instance),
            description: "由 LauncherALL 从实例「\(instance.name)」导出（DSH \(instance.dshVersion)）",
            author: "",
            runtime: runtime,
            includePluginPayloads: true,
            to: destination
        )
        if let exported {
            exportAttempted = false
            router.showToast("整合包已导出：\(exported.path)")
        } else {
            let message = packs.lastError?.localizedDescription ?? "导出失败"
            router.showToast(message, tone: .danger)
        }
    }

    // MARK: 日志

    /// 打开完整日志：使用 `dshProcess.logFileURL(instanceID:)`（运行中实例优先，其次当前实例）。
    private func openFullLog() {
        guard let instanceID = dshProcess.activeInstanceID ?? displayInstance?.id else {
            router.showToast("还没有实例日志：先在左侧选择实例并启动一次", tone: .info)
            return
        }
        let url = dshProcess.logFileURL(instanceID: instanceID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            router.showToast("日志文件还不存在：\(url.lastPathComponent)", tone: .info)
            return
        }
        InstanceActions.reveal(url)
    }

    // MARK: 目录 / 浏览器

    /// 用默认浏览器打开带一次性 token 的启动地址。
    private func openWebUI() {
        guard dshProcess.isRunning else {
            router.showToast("DSH Web UI 尚未运行", tone: .warning)
            return
        }
        dshProcess.openWebUI()
    }

    /// 在浏览器中打开（与「打开 DSH Web UI」同一地址，保留独立入口便于状态卡直接打开）。
    private func openInBrowser() {
        guard let url = dshProcess.webURL else {
            router.showToast("还没有可用的启动地址，请先启动 DSH Web UI", tone: .warning)
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 复制完整启动地址（含一次性 token）。
    private func copyWebURL() {
        guard dshProcess.isRunning else {
            router.showToast("DSH Web UI 尚未运行，暂无启动地址", tone: .warning)
            return
        }
        dshProcess.copyWebURL()
        router.showToast("启动地址已复制（含一次性 token）")
    }

    /// 刷新已安装实例 + 清空环境探测缓存。
    private func refreshInstalledInstances() {
        DSHLaunchEnvironmentCache.reset()
        versions.refreshInstalled()
        let packCount = versions.installed.filter(\.isPack).count
        router.showToast("已刷新 DSH 实例：\(versions.installed.count) 个（整合包 \(packCount) 个）")
    }

    /// 打开 DSH 数据根目录。
    private func openDSHRoot() {
        try? versions.paths.ensureDirectories()
        if !InstanceActions.open(versions.paths.root) {
            router.showToast("无法打开 DSH 目录", tone: .danger)
        }
    }

    /// 打开当前实例的独立 DSH_HOME（只读访问：不创建、不删除；缺失时给出说明）。
    private func openHomeDirectory() {
        guard let instance = displayInstance else {
            let homes = versions.paths.homesDirectory
            try? FileManager.default.createDirectory(at: homes, withIntermediateDirectories: true)
            if !InstanceActions.open(homes) {
                router.showToast("无法打开 DSH homes 目录", tone: .danger)
            }
            return
        }
        openHomeDirectory(for: instance)
    }

    /// 打开指定实例的 DSH_HOME（不创建目录）。
    private func openHomeDirectory(for instance: DSHInstalledVersion) {
        let home = versions.paths.homeDirectory(for: instance.id)
        guard FileManager.default.fileExists(atPath: home.path) else {
            router.showToast("实例 DSH_HOME 尚未创建（首次启动会自动创建并复用登录凭据）：\(home.path)", tone: .info)
            return
        }
        if !InstanceActions.open(home) {
            router.showToast("无法打开 DSH_HOME", tone: .danger)
        }
    }

    /// 去下载页安装 DSH 实例 / 导入整合包（带一次性动作，供下载页识别）。
    private func openDownload() {
        router.pendingDownloadAction = "dsh-versions"
        router.go(.download)
        router.showToast("已切到下载页：可安装 DSH 版本或导入整合包", tone: .info)
    }

    /// 去下载页管理 DSH 插件（带一次性动作，供下载页识别）。
    private func openPlugins() {
        router.pendingDownloadAction = "dsh-plugins"
        router.go(.download)
        router.showToast("已切到下载页：DSH 插件管理", tone: .info)
    }
}
