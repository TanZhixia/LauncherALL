import SwiftUI
import AppKit

// MARK: - DSH 启动页

/// DSH 启动页（与 Minecraft 启动页同构）：左侧「DSH 版本」列表，右侧启动 Web UI / 运行状态 / 实时日志 / 环境与插件。
/// 全部交互走真实 `DSHVersionStore` / `DSHProcessController` / `DSHPluginStore`：
/// 启动即真实拉起 `dsh --profile web --no-open --port …`，停止前二次确认，没有任何假 sleep / 假成功。
public struct DSHLaunchPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(DSHVersionStore.self) private var versions
    @Environment(DSHProcessController.self) private var dshProcess
    @Environment(DSHPluginStore.self) private var plugins
    @Environment(LauncherRouter.self) private var router
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    @State private var searchText = ""

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
                statusCard
                logCard
                environmentAndPluginRow
            }
        }
        .task { await prepare() }
        .onChange(of: dshProcess.state) { _, newState in
            guard !snapshotMode else { return }
            switch newState {
            case .running:
                router.showToast("DSH Web UI 已启动")
            case .failed(let message):
                router.showToast("DSH 启动失败：\(message)", tone: .danger)
            case .idle, .starting, .stopping:
                break
            }
        }
    }

    // MARK: - 生命周期

    /// 首次进入：扫描已安装版本；交互模式下拉取 npm 版本目录（用于 latest 徽标）。
    /// 离屏快照模式不联网、不启动进程，保证渲染结果确定。
    private func prepare() async {
        versions.refreshInstalled()
        guard !snapshotMode else { return }
        if versions.catalog == nil {
            await versions.refreshCatalog()
        }
    }

    // MARK: - 左侧 DSH 版本面板

    private var sidePanel: some View {
        LauncherSidePanel(
            title: "DSH 版本",
            count: "\(versions.installed.count)",
            width: 300,
            searchText: $searchText,
            searchPlaceholder: "搜索版本",
            toolbar: AnyView(sideToolbar),
            content: { sideContent },
            footer: { sideFooter }
        )
    }

    /// 左面板工具栏：刷新已安装版本 / 去下载安装新版本。
    private var sideToolbar: some View {
        HStack(spacing: LauncherSpace.xxs) {
            LauncherIconButton(
                systemImage: "arrow.clockwise",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "刷新已安装 DSH 版本",
                isDisabled: versions.isInstalling
            ) {
                refreshInstalledVersions()
            }
            LauncherIconButton(
                systemImage: "plus",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "安装新版本"
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
                title: "还没有 DSH 版本",
                message: "去「下载」安装官方 @deepseek-ai/dsh 后即可启动 Web UI。",
                actionTitle: "去下载 DSH",
                onAction: openDownload
            )
        } else if filteredVersions.isEmpty {
            LauncherEmptyState(
                systemImage: "magnifyingglass",
                title: "没有匹配的版本",
                message: "换个关键词试试，当前已安装 \(versions.installed.count) 个版本。",
                actionTitle: "清除搜索",
                onAction: { searchText = "" }
            )
        } else {
            LauncherSidePanelGroup("已安装", trailing: "\(filteredVersions.count)")
            ForEach(filteredVersions) { version in
                versionRow(version)
            }
        }
    }

    /// 单个已安装版本行：版本号 + 安装时间/体积 + latest / 运行中徽标。
    private func versionRow(_ version: DSHInstalledVersion) -> some View {
        let isRunning = dshProcess.isRunning && dshProcess.activeVersion == version.version
        let isSelected = selectedVersion?.version == version.version
        let isLatest = DSHLaunchPresentation.isLatest(version, latestVersion: latestVersionText)

        return LauncherListRow(
            title: "DSH \(version.version)",
            subtitle: DSHLaunchPresentation.versionSubtitle(version),
            systemImage: "shippingbox.fill",
            badge: isRunning ? "运行中" : (isLatest ? "latest" : nil),
            accessory: AnyView(
                HStack(spacing: LauncherSpace.xs) {
                    if isRunning {
                        LauncherStatusDot(tone: .success)
                    }
                    Image(systemName: "chevron.right")
                        .textStyle(.caption, tone: .tertiary)
                }
            ),
            isSelected: isSelected,
            action: {
                withAnimation(LauncherMotion.smooth) {
                    versions.select(version.version)
                }
            }
        )
        .launcherContextMenu(versionMenu(version))
    }

    /// 版本右键菜单：设为当前 / 启动 / 打开目录 / 复制信息。
    private func versionMenu(_ version: DSHInstalledVersion) -> [LauncherMenuGroup] {
        let processBlocked = dshProcess.isRunning || dshProcess.isBusy
        return [
            LauncherMenuGroup(items: [
                LauncherMenuItem("设为当前版本", systemImage: "checkmark.circle", action: {
                    versions.select(version.version)
                    router.showToast("已选择 DSH \(version.version)")
                }),
                LauncherMenuItem(
                    "启动此版本 Web UI",
                    systemImage: "play.fill",
                    detail: processBlocked ? "DSH 正在运行 / 处理中，请先停止" : nil,
                    isDisabled: processBlocked,
                    action: { start(version) }
                ),
                LauncherMenuItem("在访达中显示版本目录", systemImage: "folder", action: {
                    InstanceActions.reveal(URL(fileURLWithPath: version.path))
                }),
                LauncherMenuItem("复制版本号", systemImage: "doc.on.doc", action: {
                    InstanceActions.copy(version.version)
                    router.showToast("已复制版本号")
                }),
                LauncherMenuItem("复制 DSH_HOME 路径", systemImage: "doc.on.doc", action: {
                    InstanceActions.copy(versions.paths.homeDirectory(for: version.version).path)
                    router.showToast("已复制 DSH_HOME 路径")
                })
            ])
        ]
    }

    /// 左面板底部：当前选中版本 + 真实环境摘要。
    private var sideFooter: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            Rectangle()
                .fill(theme.colors.stroke)
                .frame(height: 1)

            HStack(spacing: LauncherSpace.xs) {
                LauncherLabel("当前版本")
                Spacer(minLength: LauncherSpace.xs)
                if let version = selectedVersion {
                    LauncherMonoText("DSH \(version.version)", tone: .primary)
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
                    accessibilityLabel: "打开 DSH 目录"
                ) {
                    openDSHRoot()
                }
            }
        }
    }

    /// 页头副标题：当前版本 / 未选择版本（运行版本与选中不一致时标注）。
    private var headerSubtitle: String {
        guard let version = selectedVersion else {
            return "未选择版本 · 先在左侧安装或选择 DSH 版本"
        }
        var parts = ["DSH \(version.version)"]
        if DSHLaunchPresentation.isLatest(version, latestVersion: latestVersionText) {
            parts.append("最新版本")
        }
        if dshProcess.isRunning, let active = dshProcess.activeVersion, active != version.version {
            parts.append("运行中 \(active)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 启动卡片

    /// 启动卡：当前版本、端口、Node 状态 + 启动 / 打开 / 复制地址 / 停止。
    private var launchCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(alignment: .center, spacing: LauncherSpace.md) {
                    VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        HStack(spacing: LauncherSpace.sm) {
                            Text(selectedVersion.map { "DSH \($0.version)" } ?? "未选择 DSH 版本")
                                .textStyle(.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            LauncherBadge(
                                DSHLaunchPresentation.statusTitle(dshProcess.state),
                                tone: DSHLaunchPresentation.statusTone(dshProcess.state),
                                systemImage: DSHLaunchPresentation.statusIcon(dshProcess.state)
                            )
                        }

                        HStack(spacing: LauncherSpace.xs) {
                            LauncherBadge("端口 \(portText)", tone: .neutral, systemImage: "number")
                            if let version = selectedVersion,
                               DSHLaunchPresentation.isLatest(version, latestVersion: latestVersionText) {
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
                } else if let reason = startDisabledReason,
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

                if selectedVersion == nil {
                    LauncherButton("去下载", systemImage: "arrow.down.circle", variant: .secondary, size: .medium) {
                        openDownload()
                    }
                }
            }
        }
    }

    // MARK: - 运行状态卡片

    /// 运行状态卡：运行中显示脱敏 URL / 端口 / 启动时间；未运行显示行为说明。
    private var statusCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            HStack(alignment: .center, spacing: LauncherSpace.md) {
                LauncherStatusDot(
                    tone: DSHLaunchPresentation.statusTone(dshProcess.state),
                    isPulsing: dshProcess.isBusy
                )

                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    Text(DSHLaunchPresentation.statusTitle(dshProcess.state))
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
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
                        refreshInstalledVersions()
                    }
                }
            }
        }
    }

    // MARK: - 实时日志卡片

    /// 实时日志卡：最后 12 行等宽输出，自动滚到底部；空态说明。
    private var logCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.sm) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "实时日志",
                    subtitle: "最后 12 行 · 共 \(dshProcess.logLines.count) 行 · dsh web 输出",
                    accessory: AnyView(
                        LauncherButton("打开完整日志", systemImage: "text.alignleft", variant: .ghost, size: .small) {
                            router.go(.more, moreSection: "logs")
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

    /// 环境与路径卡：Node / 包管理器 / DSH_HOME + 在访达打开。
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
                    LauncherBadge("所有版本共享", tone: .neutral)
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
                    Text("插件 / 会话保存在这里；自动复用 ~/.dsh 登录凭据，不会要求重新输入 API Key。")
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

    /// 插件入口卡：当前版本已装插件数 + 管理入口。
    private var pluginCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "插件",
                    subtitle: "当前 DSH_HOME 的 web profile 插件",
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

    /// 当前选中版本（设置里选中但已卸载时退回第一个已安装版本）。
    private var selectedVersion: DSHInstalledVersion? {
        versions.selectedInstalledVersion ?? versions.installed.first
    }

    private var filteredVersions: [DSHInstalledVersion] {
        DSHLaunchPresentation.filteredVersions(versions.installed, query: searchText)
    }

    /// Node / 包管理器探测结果（缓存，避免每次重绘都启动登录 shell）。
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
            hasSelection: selectedVersion != nil,
            hasNode: environment.hasNode,
            isInstalling: versions.isInstalling,
            isBusy: dshProcess.isBusy
        )
    }

    /// launcher 管理的共享 DSH_HOME 路径（所有版本共用，与选中版本无关）。
    private var homePathText: String {
        if snapshotMode { return "~/Library/Application Support/BlockLauncher/DSH/home" }
        return versions.paths.homeDirectory(for: selectedVersion?.version ?? "").path
    }

    private var installedPlugins: [DSHInstalledPlugin] {
        guard let version = selectedVersion else { return [] }
        return plugins.installedPlugins(for: version)
    }

    // MARK: - 真实操作

    /// 启动选中版本：真实拉起 `dsh --profile web --no-open --port …`。
    private func startSelected() {
        guard let version = selectedVersion else {
            router.showToast("请先在左侧选择已安装的 DSH 版本", tone: .warning)
            return
        }
        start(version)
    }

    private func start(_ version: DSHInstalledVersion) {
        guard !dshProcess.isRunning, !dshProcess.isBusy else {
            router.showToast("DSH 正在运行或处理中，请先停止", tone: .warning)
            return
        }
        versions.select(version.version)
        Task {
            await dshProcess.start(version: version)
        }
    }

    /// 停止前二次确认（会终止进程，属于破坏性操作）。
    private func confirmStop() {
        router.showDialog(
            LauncherDialogRequest(
                title: "停止 DSH Web UI？",
                message: "将终止当前 DSH Web UI 进程，正在进行的会话会中断。可以稍后重新启动。",
                confirmTitle: "停止进程",
                isDestructive: true,
                onConfirm: {
                    Task { await dshProcess.stop() }
                }
            )
        )
    }

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

    /// 刷新已安装版本 + 清空环境探测缓存。
    private func refreshInstalledVersions() {
        DSHLaunchEnvironmentCache.reset()
        versions.refreshInstalled()
        router.showToast("已刷新 DSH 版本（\(versions.installed.count) 个）")
    }

    /// 打开 DSH 根目录。
    private func openDSHRoot() {
        try? versions.paths.ensureDirectories()
        if !InstanceActions.open(versions.paths.root) {
            router.showToast("无法打开 DSH 目录", tone: .danger)
        }
    }

    /// 打开 launcher 共享 DSH_HOME（`DSH/home`，所有版本共用）。
    /// 目录由启动流程创建并软链 `~/.dsh` 登录凭据；启动页只读访问，不创建、不删除。
    private func openHomeDirectory() {
        let home = versions.paths.homeDirectory(for: selectedVersion?.version ?? "")
        guard FileManager.default.fileExists(atPath: home.path) else {
            router.showToast("DSH_HOME 尚未创建（首次启动 DSH 会自动创建并复用登录凭据）：\(home.path)", tone: .info)
            return
        }
        if !InstanceActions.open(home) {
            router.showToast("无法打开 DSH_HOME", tone: .danger)
        }
    }

    /// 去下载页安装 DSH 版本（带一次性动作，供下载页识别）。
    private func openDownload() {
        router.pendingDownloadAction = "dsh-versions"
        router.go(.download)
        router.showToast("已切到下载页：请选择「DSH 版本」分类安装", tone: .info)
    }

    /// 去下载页管理 DSH 插件（带一次性动作，供下载页识别）。
    private func openPlugins() {
        router.pendingDownloadAction = "dsh-plugins"
        router.go(.download)
        router.showToast("已切到下载页：DSH 插件管理", tone: .info)
    }
}
