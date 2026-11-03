import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 下载页分类

/// DSH 下载页的三个一级入口：官方版本、插件市场、本地整合包。
public enum DSHDownloadCategory: String, CaseIterable, Identifiable, Sendable {
    case versions
    case plugins
    case packs

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .versions: return "DSH 版本"
        case .plugins: return "插件市场"
        case .packs: return "整合包"
        }
    }

    public var systemImage: String {
        switch self {
        case .versions: return "shippingbox.fill"
        case .plugins: return "puzzlepiece.extension.fill"
        case .packs: return "archivebox.fill"
        }
    }

    public var subtitle: String {
        switch self {
        case .versions: return "npm · @deepseek-ai/dsh"
        case .plugins: return "dshmarket 加载源"
        case .packs: return ".dshpack · 本体 + 插件"
        }
    }
}

// MARK: - 下载页

/// DSH 启动器的「下载」页：安装 `@deepseek-ai/dsh`（可自定义实例名、同版本多开）、
/// 从 dshmarket 加载源浏览 / 安装社区插件，以及导入 / 导出 `.dshpack` 整合包。
///
/// 结构与 Minecraft 下载页同构：左侧 300pt 分类 + 右侧主面板。
/// 安装 / 卸载 / 打包全部调用 store 与 `DSHPackService` 的真实实现，进度与日志来自后端；
/// 快照模式（`launcherSnapshotMode`）下不弹面板、不发网络请求、不启动任务。
public struct DSHDownloadPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherRouter.self) private var router
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    @Environment(DSHVersionStore.self) private var versions
    @Environment(DSHPluginStore.self) private var plugins
    @Environment(DSHProcessController.self) private var dshProcess
    @Environment(DSHPackService.self) private var dshPacks

    @State private var category: DSHDownloadCategory
    /// 运行环境检测结果（task / 手动刷新时更新，避免每帧 spawn 子进程）。
    @State private var environment: DSHEnvironmentSnapshot?
    /// 展开详情的插件 id。
    @State private var expandedPluginID: String?
    /// 是否正在刷新全部（左侧底部按钮的加载态）。
    @State private var isRefreshingAll = false

    /// 快照模式下列表最多静态渲染的条数（离屏渲染没有滚动，超出会溢出；取整行/整卡，避免裁切一半）。
    private let snapshotVersionRowLimit = 4
    private let snapshotPluginRowLimit = 2
    private let snapshotPackRowLimit = 3
    /// 版本行高度约 76pt（标题 + 副标题 + 实例 chips），滚动区显示 4 行。
    private var versionListHeight: CGFloat {
        (LauncherControl.large + LauncherSpace.xl + LauncherSpace.sm) * 4
    }
    /// 插件卡高度约 130pt，滚动区显示 2 张 + 间距。
    private var pluginListHeight: CGFloat {
        LauncherControl.large * 6 + LauncherSpace.lg * 2
    }
    /// 整合包实例行高度约 56pt，滚动区显示 3 行。
    private var packListHeight: CGFloat {
        (LauncherControl.large + LauncherSpace.md) * 3 + LauncherSpace.sm
    }

    /// 允许注入初始分类（深链 / 测试渲染用）；壳层直接使用默认值。
    public init(initialCategory: DSHDownloadCategory = .versions) {
        _category = State(initialValue: initialCategory)
    }

    // MARK: - 页面骨架

    public var body: some View {
        LauncherPageLayout(sideWidth: 300) {
            sidePanel
        } main: {
            LauncherMainPanel {
                mainContent
            }
        }
        .task {
            await loadIfNeeded()
        }
        .onAppear {
            // 动作可能在页面出现前就已设置（LaunchPage 先 go 再设 / 先设再 go 两种情况都要覆盖）
            consumePendingDownloadAction()
        }
        .onChange(of: router.pendingDownloadAction) { _, _ in
            consumePendingDownloadAction()
        }
        .onChange(of: category) { _, newValue in
            guard !snapshotMode else { return }
            switch newValue {
            case .plugins:
                plugins.loadCachedCatalogIfNeeded()
                if plugins.catalog == nil {
                    Task { await refreshPlugins(force: false, notify: false) }
                }
            case .packs:
                versions.refreshInstalled()
            case .versions:
                break
            }
        }
    }

    /// 首次进入：检测环境、拉版本目录；插件源按需加载（有本地缓存时先渲染缓存）。
    private func loadIfNeeded() async {
        guard !snapshotMode else { return }
        environment = .capture(store: versions)
        plugins.loadCachedCatalogIfNeeded()
        await versions.refreshCatalog(force: false)
        if category == .plugins {
            await refreshPlugins(force: false, notify: false)
        }
    }

    /// 消费跨页动作（启动页空态「去下载 DSH」/「管理插件」等）：
    /// `dsh-versions` → 版本分类，`dsh-plugins` → 插件市场，`dsh-packs` → 整合包；消费后立即清空。
    private func consumePendingDownloadAction() {
        guard let destination = DSHDownloadDeepLink.destination(for: router.pendingDownloadAction) else {
            return
        }
        router.pendingDownloadAction = nil
        let target: DSHDownloadCategory
        switch destination {
        case .versions: target = .versions
        case .plugins: target = .plugins
        case .packs: target = .packs
        }
        guard category != target else { return }
        withAnimation(LauncherMotion.spring) {
            category = target
        }
    }

    /// 展示用环境快照：交互模式用 task 结果；快照模式做一次性同步探测（只读本机、不联网）。
    private var environmentSnapshot: DSHEnvironmentSnapshot {
        if let environment { return environment }
        if snapshotMode { return DSHEnvironmentProbe.cached(store: versions) }
        return .notProbed
    }

    // MARK: - 当前实例

    /// 当前选中的实例。
    private var selectedInstance: DSHInstalledVersion? {
        versions.selectedInstalledVersion
    }

    /// 按 DSH 版本聚合的实例。
    private var instancesByVersion: [String: [DSHInstalledVersion]] {
        DSHDownloadList.instancesByVersion(versions.installed)
    }

    /// 本地整合包实例。
    private var packInstances: [DSHInstalledVersion] {
        DSHDownloadList.packInstances(versions.installed)
    }

    /// 该实例是否正在运行。
    private func isRunning(_ instance: DSHInstalledVersion) -> Bool {
        dshProcess.isRunning && dshProcess.activeInstanceID == instance.id
    }

    // MARK: - 左面板

    private var sidePanel: some View {
        LauncherSidePanel(
            title: "下载",
            count: "\(versions.installed.count)",
            width: 300,
            toolbar: AnyView(sideToolbar)
        ) {
            sideContent
        } footer: {
            sideFooter
        }
    }

    private var sideToolbar: some View {
        LauncherIconButton(
            systemImage: "arrow.clockwise",
            variant: .ghost,
            size: .small,
            accessibilityLabel: "刷新 DSH 版本、插件源与实例",
            isDisabled: snapshotMode || isRefreshingAll
        ) {
            refreshAll()
        }
        .launcherTooltip(
            snapshotMode
                ? "快照模式不发起网络请求"
                : (isRefreshingAll ? "正在刷新版本目录与插件源…" : "刷新版本目录、插件源与实例")
        )
    }

    @ViewBuilder
    private var sideContent: some View {
        LauncherSidePanelGroup("DSH", trailing: "\(packInstances.count) 整合包")
        categoryRow(.versions)
        categoryRow(.plugins)
        categoryRow(.packs)

        LauncherSidePanelGroup("实例", trailing: "\(versions.installed.count)")
        instanceSelector
        selectedInstanceCard

        LauncherSidePanelGroup("运行环境")
        environmentMiniCard
    }

    private func categoryRow(_ item: DSHDownloadCategory) -> some View {
        LauncherListRow(
            title: item.title,
            subtitle: categorySubtitle(item),
            systemImage: item.systemImage,
            accessory: AnyView(
                Image(systemName: "chevron.right")
                    .textStyle(.micro, tone: .tertiary)
            ),
            isSelected: category == item,
            action: {
                withAnimation(LauncherMotion.spring) {
                    category = item
                }
            }
        )
    }

    private func categorySubtitle(_ item: DSHDownloadCategory) -> String {
        switch item {
        case .versions:
            let total = versions.catalog?.versions.count ?? 0
            let installed = instancesByVersion.count
            return total > 0 ? "npm · \(total) 个版本 · \(installed) 个已安装" : item.subtitle
        case .plugins:
            return plugins.pluginCount > 0
                ? "dshmarket · \(plugins.pluginCount) 个插件"
                : item.subtitle
        case .packs:
            return packInstances.isEmpty ? item.subtitle : "\(packInstances.count) 个本地整合包"
        }
    }

    /// 实例选择器（菜单里按 name 列出，副标题带 DSH 版本与整合包标识）。
    @ViewBuilder
    private var instanceSelector: some View {
        if versions.installed.isEmpty {
            Text("还没有安装实例：先到「DSH 版本」安装，或导入整合包。")
                .textStyle(.micro, tone: .tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, LauncherSpace.xs)
                .padding(.vertical, LauncherSpace.xxs)
        } else {
            LauncherMenuButton(
                selectedInstance?.name ?? "选择实例",
                systemImage: "chevron.down",
                variant: .secondary,
                size: .small,
                isFullWidth: true,
                groups: instanceMenuGroups
            )
            .launcherTooltip("切换当前实例（插件 / 启动都针对当前实例）")
            .padding(.horizontal, LauncherSpace.xxs)
        }
    }

    private var instanceMenuGroups: [LauncherMenuGroup] {
        guard !versions.installed.isEmpty else { return [] }
        let items = versions.installed.map { instance in
            LauncherMenuItem(
                instance.name,
                id: instance.id,
                systemImage: instance.id == selectedInstance?.id
                    ? "checkmark"
                    : (instance.isPack ? "shippingbox" : "cube"),
                detail: instanceDetail(instance),
                action: { selectInstance(instance) }
            )
        }
        return [LauncherMenuGroup(title: "已安装实例", items: items)]
    }

    private func instanceDetail(_ instance: DSHInstalledVersion) -> String {
        var parts: [String] = ["DSH \(instance.dshVersion)"]
        if instance.isPack {
            if let name = instance.packName, !name.isEmpty {
                parts.append("整合包 \(name)")
            } else {
                parts.append("整合包")
            }
        }
        if let size = instance.sizeBytes, size > 0 {
            parts.append(DSHDownloadFormat.size(size))
        }
        if isRunning(instance) {
            parts.append("运行中")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var selectedInstanceCard: some View {
        if let instance = selectedInstance {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                HStack(spacing: LauncherSpace.xs) {
                    Text(instance.name)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    if instance.isPack {
                        LauncherBadge("整合包", tone: .info)
                    }
                    if isRunning(instance) {
                        LauncherBadge("运行中", tone: .accent)
                    }
                    Spacer(minLength: 0)
                }
                Text(DSHDownloadList.instanceSummary(instance))
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
                Text("实例 home · \(DSHDownloadFormat.shortHomePath(pathsHomePath(for: instance)))")
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: LauncherSpace.xs) {
                    LauncherIconMenu(
                        groups: exportModeMenuGroups(instance: instance),
                        systemImage: "square.and.arrow.up",
                        accessibilityLabel: "导出该实例为整合包"
                    )
                    .launcherTooltip("导出为 .dshpack（完整包 / 轻量包）")
                    LauncherIconButton(
                        systemImage: "folder",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: "在访达中显示实例目录",
                        isDisabled: snapshotMode
                    ) {
                        InstanceActions.reveal(URL(fileURLWithPath: instance.path))
                    }
                    .launcherTooltip(snapshotMode ? "快照模式不打开目录" : "在访达中显示实例目录")
                    Spacer(minLength: 0)
                    LauncherIconButton(
                        systemImage: "trash",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: "卸载实例 \(instance.name)",
                        isDisabled: snapshotMode || versions.installState.isInstalling
                    ) {
                        confirmUninstall(instance)
                    }
                    .launcherTooltip(
                        snapshotMode
                            ? "快照模式不执行卸载"
                            : (versions.installState.isInstalling ? "安装任务进行中，暂时不能卸载" : "卸载该实例")
                    )
                }
            }
            .padding(LauncherSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .strokeBorder(theme.colors.stroke, lineWidth: 1)
            }
            .padding(.horizontal, LauncherSpace.xxs)
        }
    }

    private func pathsHomePath(for instance: DSHInstalledVersion) -> String {
        versions.paths.homeDirectory(for: instance.id).path
    }

    private var environmentMiniCard: some View {
        let env = environmentSnapshot
        return HStack(spacing: LauncherSpace.xs) {
            LauncherStatusDot(tone: env.isProbed ? (env.isReady ? .success : .warning) : .neutral)
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text(env.isProbed ? (env.isReady ? "已就绪" : "缺少依赖") : "等待检测")
                    .textStyle(.micro, tone: env.isProbed ? (env.isReady ? .success : .warning) : .tertiary)
                Text(env.detailText)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(LauncherSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .strokeBorder(theme.colors.stroke, lineWidth: 1)
        }
        .padding(.horizontal, LauncherSpace.xxs)
    }

    private var sideFooter: some View {
        VStack(spacing: LauncherSpace.xs) {
            LauncherDivider()
            HStack(spacing: LauncherSpace.xs) {
                LauncherButton(
                    "刷新全部",
                    systemImage: "arrow.clockwise",
                    variant: .secondary,
                    size: .small,
                    isLoading: isRefreshingAll,
                    isFullWidth: true,
                    isDisabled: snapshotMode || isRefreshingAll
                ) {
                    refreshAll()
                }
                .launcherTooltip(snapshotMode ? "快照模式不发起网络请求" : "刷新版本目录、插件源与实例列表")
                LauncherIconButton(
                    systemImage: "folder",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: "打开 DSH 数据目录",
                    isDisabled: snapshotMode
                ) {
                    openDSHDirectory()
                }
                .launcherTooltip("打开 BlockLauncher/DSH 数据目录（实例、home、cache）")
            }
            HStack(spacing: LauncherSpace.xs) {
                Text("\(versions.installed.count) 个实例 · \(packInstances.count) 个整合包")
                    .textStyle(.micro, tone: .tertiary)
                Spacer(minLength: 0)
                LauncherMonoText(
                    plugins.updatedText.map { "源 \(String($0.prefix(10)))" } ?? "未加载插件源",
                    tone: .tertiary,
                    size: 10
                )
                .lineLimit(1)
            }
        }
    }

    // MARK: - 右内容

    @ViewBuilder
    private var mainContent: some View {
        switch category {
        case .versions:
            versionsPanel
        case .plugins:
            pluginsPanel
        case .packs:
            packsPanel
        }
    }

    // MARK: - DSH 版本面板

    @ViewBuilder
    private var versionsPanel: some View {
        LauncherPanelHeader("DSH 版本", subtitle: versionsPanelSubtitle) {
            HStack(spacing: LauncherSpace.xs) {
                LauncherBadge(
                    "\(versions.installed.count) 个实例",
                    tone: versions.installed.isEmpty ? .neutral : .success
                )
                LauncherIconButton(
                    systemImage: "arrow.clockwise",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: "刷新 DSH 版本列表",
                    isDisabled: snapshotMode || versions.catalogState.isLoading
                ) {
                    refreshVersions(force: true)
                }
                .launcherTooltip(
                    snapshotMode
                        ? "快照模式不发起网络请求"
                        : (versions.catalogState.isLoading ? "正在拉取版本列表…" : "从 npm 重新拉取版本列表")
                )
            }
        }

        environmentCard

        if let message = versions.catalogState.errorText {
            LauncherBanner(
                title: versions.catalog == nil ? "版本列表加载失败" : "版本列表刷新失败（正在使用上次结果）",
                message: message,
                tone: versions.catalog == nil ? .danger : .warning,
                actionTitle: snapshotMode ? nil : "重试",
                onAction: snapshotMode ? nil : { refreshVersions(force: true) }
            )
        }

        installStatusSection
        versionCatalogSection
    }

    private var versionsPanelSubtitle: String {
        var parts = ["npm · @deepseek-ai/dsh"]
        if let latest = versions.latestVersion {
            parts.append("latest \(latest.version)")
        }
        parts.append("\(versions.installed.count) 个实例 / \(instancesByVersion.count) 个版本")
        return parts.joined(separator: " · ")
    }

    /// 运行环境卡：Node / 包管理器检测结果 + 缺失时的修复提示。
    private var environmentCard: some View {
        let env = environmentSnapshot
        return LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "运行环境",
                    subtitle: env.isProbed ? env.detailText : "安装 DSH 需要 Node.js 20+ 与 pnpm / npm",
                    accessory: AnyView(
                        LauncherBadge(
                            env.isProbed ? (env.isReady ? "就绪" : "缺少依赖") : "未检测",
                            tone: env.isProbed ? (env.isReady ? .success : .warning) : .neutral
                        )
                    )
                )

                HStack(spacing: LauncherSpace.lg) {
                    environmentChip(
                        title: "Node.js",
                        value: env.isProbed ? (env.hasNode ? "已找到" : "未找到") : "—",
                        isOK: env.hasNode
                    )
                    environmentChip(
                        title: "包管理器",
                        value: env.isProbed ? (env.packageManagerName ?? "未找到") : "—",
                        isOK: env.packageManagerName != nil
                    )
                    Spacer(minLength: LauncherSpace.sm)
                    if !snapshotMode {
                        LauncherButton(
                            "重新检测",
                            systemImage: "arrow.clockwise",
                            variant: .ghost,
                            size: .small
                        ) {
                            environment = .capture(store: versions)
                        }
                        .launcherTooltip("重新探测 Node.js 与 pnpm / npm")
                    }
                }

                if env.isProbed && !env.isReady {
                    LauncherBanner(
                        title: "当前环境无法安装 DSH",
                        message: missingEnvironmentHint(env),
                        tone: .warning
                    )
                } else if !env.isProbed {
                    Text("首次进入本页时会自动检测 Node.js 与包管理器；也可以点「重新检测」。")
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func environmentChip(title: String, value: String, isOK: Bool) -> some View {
        HStack(spacing: LauncherSpace.xs) {
            LauncherStatusDot(tone: isOK ? .success : .danger)
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text(title)
                    .textStyle(.micro, tone: .tertiary)
                LauncherMonoText(value, tone: isOK ? .primary : .danger, size: 11)
                    .lineLimit(1)
            }
        }
    }

    private func missingEnvironmentHint(_ env: DSHEnvironmentSnapshot) -> String {
        if !env.hasNode {
            return "没有找到可用的 Node.js：请安装 Node 20+，或安装 DeepSeek Harness 桌面端（自带 Node 运行时）后重试。"
        }
        return "没有找到 pnpm / npm：请执行 `npm i -g pnpm`，或安装 DeepSeek Harness 桌面端（自带 pnpm）后重试。"
    }

    /// 安装中 / 安装失败状态。
    @ViewBuilder
    private var installStatusSection: some View {
        switch versions.installState {
        case .installing(let version, let phase):
            DSHProgressCard(
                title: "正在安装 DSH \(version)",
                phase: phase.title,
                logLines: Array(versions.installLog.suffix(5)),
                onCancel: { cancelInstall() }
            )
        case .failed(let version, let message):
            LauncherBanner(
                title: "DSH \(version) 安装失败",
                message: message,
                tone: .danger,
                actionTitle: snapshotMode ? nil : "重试",
                onAction: snapshotMode ? nil : { promptInstall(version) }
            )
        case .idle:
            EmptyView()
        }
    }

    /// 版本列表。
    @ViewBuilder
    private var versionCatalogSection: some View {
        if let catalog = versions.catalog {
            let partition = DSHDownloadList.partition(
                catalog.versions,
                installedIDs: Set(instancesByVersion.keys)
            )
            let ordered = partition.displayOrder
            LauncherCard(level: .regular, padding: LauncherSpace.md) {
                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    LauncherSectionHeader(
                        title: "版本列表",
                        subtitle: "共 \(partition.total) 个版本 · \(partition.installed.count) 个版本已有实例",
                        accessory: AnyView(
                            HStack(spacing: LauncherSpace.xs) {
                                if !partition.hasAvailable {
                                    LauncherBadge("全部已安装", tone: .success)
                                }
                                LauncherMonoText(
                                    "更新于 \(DSHDownloadFormat.date(catalog.fetchedAt))",
                                    tone: .tertiary,
                                    size: 10
                                )
                                .lineLimit(1)
                            }
                        )
                    )

                    versionList(ordered)

                    HStack(spacing: LauncherSpace.xs) {
                        LauncherHintIcon("每个实例有独立的 DSH_HOME（插件 / 会话）；登录凭据自动复用 ~/.dsh，无需重新输入密钥。")
                        Text("同名 / 同版本可以重复安装，实例之间互不影响")
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if snapshotMode && ordered.count > snapshotVersionRowLimit {
                            Text("快照仅展示前 \(snapshotVersionRowLimit) 个")
                                .textStyle(.micro, tone: .tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if versions.catalogState.isLoading {
            LauncherCard(level: .regular, padding: LauncherSpace.md) {
                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    LauncherSkeleton(height: LauncherControl.large, cornerRadius: LauncherRadius.md)
                    LauncherSkeleton(height: LauncherControl.large, cornerRadius: LauncherRadius.md)
                    LauncherSkeleton(height: LauncherControl.large, cornerRadius: LauncherRadius.md)
                }
            }
        } else {
            LauncherCard(level: .regular, padding: LauncherSpace.lg) {
                LauncherEmptyState(
                    systemImage: "shippingbox",
                    title: "还没有加载 DSH 版本列表",
                    message: snapshotMode
                        ? "快照模式不会联网。启动启动器后会自动从 npm 拉取 @deepseek-ai/dsh 的版本列表。"
                        : "从 npm registry 拉取 @deepseek-ai/dsh 的版本列表，然后选择要安装的版本。",
                    actionTitle: snapshotMode ? nil : "刷新版本列表",
                    onAction: snapshotMode ? nil : { refreshVersions(force: true) }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func versionList(_ ordered: [DSHVersionInfo]) -> some View {
        if snapshotMode {
            // 离屏渲染无法滚动：只静态画前几行，避免溢出
            VStack(spacing: LauncherSpace.xxs) {
                ForEach(DSHDownloadList.visible(ordered, limit: snapshotVersionRowLimit)) { info in
                    versionRow(info)
                }
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: LauncherSpace.xxs) {
                    ForEach(ordered) { info in
                        versionRow(info)
                    }
                }
            }
            .frame(height: versionListHeight)
        }
    }

    private func versionRow(_ info: DSHVersionInfo) -> some View {
        DSHVersionRowView(
            info: info,
            tags: DSHDownloadList.versionTags(info, catalog: versions.catalog),
            instances: instancesByVersion[info.version] ?? [],
            selectedInstanceID: versions.settings.dshSelectedInstanceID,
            runningInstanceID: dshProcess.isRunning ? dshProcess.activeInstanceID : nil,
            isInstalling: versions.installState.installingVersion == info.version,
            isBusy: versions.installState.isInstalling,
            isReadOnly: snapshotMode,
            canInstall: !snapshotMode && environmentSnapshot.isReady,
            installDisabledReason: installDisabledReason,
            menuGroups: versionRowMenuGroups(for: info.version),
            onInstall: { promptInstall(info.version) },
            onSelectInstance: { selectInstance($0) }
        )
    }

    private func versionRowMenuGroups(for dshVersion: String) -> [LauncherMenuGroup] {
        var items: [LauncherMenuItem] = [
            LauncherMenuItem(
                "安装新实例…",
                systemImage: "plus",
                isDisabled: snapshotMode || versions.installState.isInstalling
            ) {
                promptInstall(dshVersion)
            }
        ]
        for instance in instancesByVersion[dshVersion] ?? [] {
            let isSelected = instance.id == selectedInstance?.id
            items.append(
                LauncherMenuItem(
                    "设为当前：\(instance.name)",
                    id: "select-\(instance.id)",
                    systemImage: isSelected ? "checkmark" : "circle",
                    detail: instance.isPack ? "整合包实例" : nil,
                    isDisabled: snapshotMode || isSelected
                ) {
                    selectInstance(instance)
                }
            )
            items.append(
                LauncherMenuItem(
                    "卸载：\(instance.name)",
                    id: "uninstall-\(instance.id)",
                    systemImage: "trash",
                    tone: .danger,
                    isDisabled: snapshotMode || versions.installState.isInstalling
                ) {
                    confirmUninstall(instance)
                }
            )
        }
        return [LauncherMenuGroup(title: "\(dshVersion) 的实例", items: items)]
    }

    private var installDisabledReason: String? {
        if snapshotMode { return "快照模式不执行安装" }
        let env = environmentSnapshot
        if !env.isProbed { return "正在检测运行环境…" }
        if !env.hasNode { return "缺少 Node.js 运行时" }
        if env.packageManagerName == nil { return "缺少 pnpm / npm" }
        return nil
    }

    // MARK: - 插件市场面板

    @ViewBuilder
    private var pluginsPanel: some View {
        LauncherPanelHeader("插件市场", subtitle: pluginsPanelSubtitle) {
            HStack(spacing: LauncherSpace.xs) {
                LauncherBadge("\(plugins.filteredPlugins.count) 个匹配", tone: .neutral)
                LauncherIconButton(
                    systemImage: "arrow.clockwise",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: "刷新插件加载源",
                    isDisabled: snapshotMode || plugins.catalogState.isLoading
                ) {
                    Task { await refreshPlugins(force: true) }
                }
                .launcherTooltip(
                    snapshotMode
                        ? "快照模式不发起网络请求"
                        : (plugins.catalogState.isLoading ? "正在加载插件源…" : "重新加载 dshmarket 插件源")
                )
            }
        }

        pluginToolbar
        pluginSourceRow

        if let message = plugins.catalogState.errorText {
            LauncherBanner(
                title: plugins.catalog == nil ? "插件加载源加载失败" : "插件源刷新失败（正在使用本地缓存）",
                message: message,
                tone: plugins.catalog == nil ? .danger : .warning,
                actionTitle: snapshotMode ? nil : "重试",
                onAction: snapshotMode ? nil : { Task { await refreshPlugins(force: true) } }
            )
        }

        pluginOperationSection
        pluginsBody
    }

    private var pluginsPanelSubtitle: String {
        var parts: [String] = []
        if let instance = selectedInstance {
            parts.append("实例「\(instance.name)」· DSH \(instance.dshVersion)")
        } else {
            parts.append("尚未选择实例")
        }
        parts.append("dshmarket 加载源 · \(plugins.pluginCount) 个插件")
        return parts.joined(separator: " · ")
    }

    /// 搜索 / 分类 / 排序工具栏。
    private var pluginToolbar: some View {
        HStack(spacing: LauncherSpace.sm) {
            LauncherTextField(
                "搜索插件名称、作者或 npm 包名",
                text: Binding(
                    get: { plugins.searchText },
                    set: { plugins.searchText = $0 }
                ),
                systemImage: "magnifyingglass"
            )
            LauncherDropdown(
                options: categoryOptions,
                selection: categoryBinding,
                placeholder: "全部分类"
            )
            .frame(width: 156)

            LauncherMenuButton(
                plugins.sortMode.title,
                systemImage: "arrow.up.arrow.down",
                variant: .secondary,
                size: .small,
                groups: sortMenuGroups
            )
        }
    }

    private var categoryOptions: [LauncherSegment<String>] {
        [LauncherSegment(id: "", title: "全部分类", systemImage: "square.grid.2x2")]
            + plugins.categories.map { category in
                LauncherSegment(id: category.id, title: category.title)
            }
    }

    private var categoryBinding: Binding<String> {
        Binding(
            get: { plugins.selectedCategoryID ?? "" },
            set: { plugins.selectedCategoryID = $0.isEmpty ? nil : $0 }
        )
    }

    private var sortMenuGroups: [LauncherMenuGroup] {
        [
            LauncherMenuGroup(items: DSHPluginSort.allCases.map { sort in
                LauncherMenuItem(
                    sort.title,
                    systemImage: plugins.sortMode == sort ? "checkmark" : "arrow.up.arrow.down",
                    action: { plugins.sortMode = sort }
                )
            })
        ]
    }

    /// 加载源信息行：源地址 + 更新时间 + 打开源。
    private var pluginSourceRow: some View {
        HStack(spacing: LauncherSpace.xs) {
            LauncherHintIcon("插件来源：dshmarket 使用的公开加载源（awesome-dsh-plugin）")
            LauncherMonoText(plugins.sourceText, tone: .tertiary, size: 10)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: LauncherSpace.sm)
            if let updated = plugins.updatedText {
                Text("更新于 \(String(updated.prefix(10)))")
                    .textStyle(.micro, tone: .tertiary)
            }
            LauncherIconButton(
                systemImage: "safari",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "在浏览器打开插件加载源"
            ) {
                if let url = URL(string: plugins.sourceText) {
                    NSWorkspace.shared.open(url)
                }
            }
            .launcherTooltip("在浏览器打开插件加载源")
        }
    }

    /// 插件安装 / 卸载中的进度卡。
    @ViewBuilder
    private var pluginOperationSection: some View {
        if let operation = plugins.operation {
            let isInstalling = operation.isInstalling
            DSHProgressCard(
                title: isInstalling ? "正在安装插件 \(operation.pluginID)" : "正在卸载插件 \(operation.pluginID)",
                phase: isInstalling
                    ? "执行 dsh plugin --profile web add（当前实例）"
                    : "执行 dsh plugin --profile web remove（当前实例）",
                logLines: Array(plugins.operationLog.suffix(4)),
                onCancel: {
                    plugins.cancelOperation()
                    router.showToast("已请求取消插件操作", tone: .info)
                }
            )
        }
    }

    /// 插件主体：没有实例时给引导，否则展示已安装插件 + 插件列表。
    @ViewBuilder
    private var pluginsBody: some View {
        if let instance = selectedInstance {
            installedPluginsCard(instance: instance)
            pluginCatalogSection(instance: instance)
        } else {
            LauncherCard(level: .regular, padding: LauncherSpace.lg) {
                LauncherEmptyState(
                    systemImage: "puzzlepiece.extension",
                    title: "还没有可安装插件的 DSH 实例",
                    message: "插件安装到某个实例的独立 web profile（dsh plugin --profile web add）。先在「DSH 版本」安装一个实例，或导入整合包。",
                    actionTitle: "去安装 DSH 版本",
                    onAction: {
                        withAnimation(LauncherMotion.spring) {
                            category = .versions
                        }
                    }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func installedPluginsCard(instance: DSHInstalledVersion) -> some View {
        let installedPlugins = plugins.installedPlugins(for: instance)
        return LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "已安装插件",
                    subtitle: "实例「\(instance.name)」· DSH \(instance.dshVersion) · 独立 web profile（凭据复用 ~/.dsh）",
                    accessory: AnyView(
                        HStack(spacing: LauncherSpace.xs) {
                            LauncherBadge("\(installedPlugins.count) 个", tone: installedPlugins.isEmpty ? .neutral : .success)
                            LauncherMenuButton(
                                instance.name,
                                systemImage: "chevron.down",
                                variant: .secondary,
                                size: .small,
                                groups: instanceMenuGroups
                            )
                            .frame(width: 160)
                            .launcherTooltip("切换当前实例；插件安装在当前实例的 web profile 内")
                        }
                    )
                )

                if installedPlugins.isEmpty {
                    Text("当前实例还没有安装插件；在下方插件市场里点「安装」即可。")
                        .textStyle(.micro, tone: .tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(DSHDownloadList.visible(installedPlugins, limit: 2)) { plugin in
                        installedPluginRow(plugin, instance: instance)
                    }
                    if installedPlugins.count > 2 {
                        Text("另有 \(installedPlugins.count - 2) 个插件已安装")
                            .textStyle(.micro, tone: .tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func installedPluginRow(_ plugin: DSHInstalledPlugin, instance: DSHInstalledVersion) -> some View {
        HStack(spacing: LauncherSpace.sm) {
            Image(systemName: "puzzlepiece.extension.fill")
                .textStyle(.micro, tone: .secondary)
                .frame(width: LauncherSpace.lg)
            LauncherMonoText(plugin.dependencyKey, tone: .primary, size: 10)
                .lineLimit(1)
            Spacer(minLength: LauncherSpace.sm)
            LauncherMonoText(plugin.version, tone: .tertiary, size: 10)
                .lineLimit(1)
            LauncherIconButton(
                systemImage: "trash",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "卸载插件 \(plugin.dependencyKey)",
                isDisabled: snapshotMode || plugins.isBusy
            ) {
                confirmRemovePlugin(plugin, instance: instance)
            }
            .launcherTooltip(
                snapshotMode
                    ? "快照模式不执行卸载"
                    : (plugins.isBusy ? "插件操作进行中" : "从当前实例卸载该插件")
            )
        }
        .frame(minHeight: LauncherControl.small)
    }

    @ViewBuilder
    private func pluginCatalogSection(instance: DSHInstalledVersion) -> some View {
        if let catalog = plugins.catalog {
            let filtered = plugins.filteredPlugins
            LauncherCard(level: .regular, padding: LauncherSpace.md) {
                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    LauncherSectionHeader(
                        title: "插件列表",
                        subtitle: "\(filtered.count) 个匹配 / 共 \(catalog.plugins.count) 个插件 · \(plugins.sortMode.title)",
                        accessory: AnyView(
                            HStack(spacing: LauncherSpace.xs) {
                                if hasActiveFilter {
                                    LauncherButton(
                                        "清空筛选",
                                        systemImage: "line.3.horizontal.decrease.circle",
                                        variant: .ghost,
                                        size: .small
                                    ) {
                                        clearFilters()
                                    }
                                    .launcherTooltip("清空搜索词与分类过滤")
                                }
                            }
                        )
                    )

                    if filtered.isEmpty {
                        pluginEmptyState
                    } else {
                        pluginList(filtered, instance: instance)
                    }

                    HStack(spacing: LauncherSpace.xs) {
                        LauncherHintIcon("安装走 dsh plugin --profile web add <包名>，与官方插件管理一致。")
                        Text("插件安装在实例「\(instance.name)」的 web profile 内")
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if snapshotMode && filtered.count > snapshotPluginRowLimit {
                            Text("快照仅展示前 \(snapshotPluginRowLimit) 个")
                                .textStyle(.micro, tone: .tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if plugins.catalogState.isLoading {
            LauncherCard(level: .regular, padding: LauncherSpace.md) {
                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    LauncherSkeleton(height: LauncherControl.large + LauncherSpace.xl, cornerRadius: LauncherRadius.md)
                    LauncherSkeleton(height: LauncherControl.large + LauncherSpace.xl, cornerRadius: LauncherRadius.md)
                    LauncherSkeleton(height: LauncherControl.large + LauncherSpace.xl, cornerRadius: LauncherRadius.md)
                }
            }
        } else {
            LauncherCard(level: .regular, padding: LauncherSpace.lg) {
                LauncherEmptyState(
                    systemImage: "puzzlepiece.extension",
                    title: "插件加载源尚未加载",
                    message: snapshotMode
                        ? "快照模式不会联网。启动启动器后会自动从 dshmarket 加载源拉取插件列表。"
                        : "从 dshmarket 公开加载源拉取插件列表（约 8000+ 个社区插件）。",
                    actionTitle: snapshotMode ? nil : "加载插件源",
                    onAction: snapshotMode ? nil : { Task { await refreshPlugins(force: true) } }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var pluginEmptyState: some View {
        LauncherEmptyState(
            systemImage: "magnifyingglass",
            title: "没有匹配的插件",
            message: hasActiveFilter
                ? "换个关键词或分类试试，也可以清空筛选看全部插件。"
                : "当前加载源里没有插件。",
            actionTitle: hasActiveFilter ? "清空筛选" : nil,
            onAction: hasActiveFilter ? { clearFilters() } : nil
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func pluginList(_ filtered: [DSHPluginEntry], instance: DSHInstalledVersion) -> some View {
        let installedPlugins = plugins.installedPlugins(for: instance)
        if snapshotMode {
            VStack(spacing: LauncherSpace.xs) {
                ForEach(DSHDownloadList.visible(filtered, limit: snapshotPluginRowLimit)) { entry in
                    pluginCard(entry, instance: instance, installedPlugins: installedPlugins)
                }
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: LauncherSpace.xs) {
                    ForEach(filtered) { entry in
                        pluginCard(entry, instance: instance, installedPlugins: installedPlugins)
                    }
                }
            }
            .frame(height: pluginListHeight)
        }
    }

    private func pluginCard(
        _ entry: DSHPluginEntry,
        instance: DSHInstalledVersion,
        installedPlugins: [DSHInstalledPlugin]
    ) -> some View {
        let plugin = installedPlugin(for: entry, in: installedPlugins)
        return DSHPluginCardView(
            entry: entry,
            categoryTitle: DSHDownloadList.categoryTitle(entry.categoryID, categories: plugins.categories),
            isInstalled: plugin != nil,
            isExpanded: expandedPluginID == entry.id,
            isBusy: plugins.isBusy,
            isReadOnly: snapshotMode,
            canInstall: pluginInstallAllowed(for: entry, instance: instance),
            installDisabledReason: pluginInstallDisabledReason(for: entry, instance: instance),
            onToggle: {
                withAnimation(LauncherMotion.spring) {
                    expandedPluginID = expandedPluginID == entry.id ? nil : entry.id
                }
            },
            onInstall: { installPlugin(entry, instance: instance) },
            onRemove: {
                if let plugin {
                    confirmRemovePlugin(plugin, instance: instance)
                }
            },
            onOpen: { openPluginPage(entry) }
        )
    }

    private func installedPlugin(
        for entry: DSHPluginEntry,
        in installedPlugins: [DSHInstalledPlugin]
    ) -> DSHInstalledPlugin? {
        installedPlugins.first { plugin in
            guard let spec = entry.installSpec else { return plugin.dependencyKey == entry.name }
            return plugin.dependencyKey == spec || plugin.dependencyKey == entry.name
        }
    }

    private var hasActiveFilter: Bool {
        !plugins.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || plugins.selectedCategoryID != nil
    }

    private func clearFilters() {
        plugins.searchText = ""
        plugins.selectedCategoryID = nil
    }

    private func pluginInstallAllowed(for entry: DSHPluginEntry, instance: DSHInstalledVersion) -> Bool {
        !snapshotMode
            && environmentSnapshot.isReady
            && entry.installSpec != nil
            && !plugins.isBusy
    }

    private func pluginInstallDisabledReason(for entry: DSHPluginEntry, instance: DSHInstalledVersion) -> String? {
        if snapshotMode { return "快照模式不执行安装" }
        if !environmentSnapshot.isReady { return "缺少 Node.js / 包管理器" }
        if entry.installSpec == nil { return "该插件没有 npm 包名，需要按项目页手动安装" }
        if plugins.isBusy { return "已有插件操作在进行" }
        return nil
    }

    // MARK: - 整合包面板

    @ViewBuilder
    private var packsPanel: some View {
        LauncherPanelHeader("DSH 整合包", subtitle: packsPanelSubtitle) {
            HStack(spacing: LauncherSpace.xs) {
                LauncherBadge("\(packInstances.count) 个本地整合包", tone: packInstances.isEmpty ? .neutral : .info)
                LauncherIconButton(
                    systemImage: "arrow.clockwise",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: "刷新本地实例列表",
                    isDisabled: snapshotMode || versions.installState.isInstalling
                ) {
                    versions.refreshInstalled()
                    router.showToast("已刷新本地实例：\(versions.installed.count) 个", tone: .info)
                }
                .launcherTooltip(snapshotMode ? "快照模式不刷新磁盘实例" : "重新扫描本地实例目录")
            }
        }

        packActionsCard
        packProgressSection

        if case .failed(let message) = dshPacks.state {
            LauncherBanner(
                title: "整合包操作失败",
                message: message,
                tone: .danger
            )
            packFailureLog
        }

        packInstanceListSection
    }

    private var packsPanelSubtitle: String {
        "私有格式 .dshpack · DSH 本体 + 插件 + manifest · 可在其它机器还原同一实例"
    }

    /// 导入 / 导出操作卡。
    private var packActionsCard: some View {
        let env = environmentSnapshot
        let importBlocked = DSHDownloadPackUI.importBlockedReason(
            state: dshPacks.state,
            environmentReady: env.isReady,
            isReadOnly: snapshotMode
        )
        let exportBlocked = DSHDownloadPackUI.exportBlockedReason(
            instance: selectedInstance,
            state: dshPacks.state,
            environmentReady: env.isReady,
            isReadOnly: snapshotMode
        )
        return LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "导入 / 导出",
                    subtitle: "整合包可以在其它机器还原出同样的 DSH 实例（含插件清单）"
                )

                HStack(alignment: .top, spacing: LauncherSpace.lg) {
                    // 导入
                    VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        LauncherButton(
                            "导入整合包…",
                            systemImage: "tray.and.arrow.down",
                            variant: .primary,
                            size: .medium,
                            isDisabled: importBlocked != nil
                        ) {
                            beginImport()
                        }
                        .launcherTooltip(importBlocked ?? "选择 .dshpack 文件导入为新实例（可自定义实例名）")
                        Text("选择 .dshpack 文件；导入后成为新的本地实例")
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }

                    // 导出
                    VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        HStack(spacing: LauncherSpace.xs) {
                            LauncherButton(
                                "导出完整包…",
                                systemImage: "shippingbox",
                                variant: .secondary,
                                size: .medium,
                                isDisabled: exportBlocked != nil
                            ) {
                                beginExport(instance: selectedInstance, mode: .bundled)
                            }
                            .launcherTooltip(exportBlocked ?? DSHDownloadPackUI.runtimeDescription(.bundled))
                            LauncherButton(
                                "导出轻量包…",
                                systemImage: "square.and.arrow.up",
                                variant: .secondary,
                                size: .medium,
                                isDisabled: exportBlocked != nil
                            ) {
                                beginExport(instance: selectedInstance, mode: .online)
                            }
                            .launcherTooltip(exportBlocked ?? DSHDownloadPackUI.runtimeDescription(.online))
                        }
                        Text(exportHint)
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var exportHint: String {
        guard let instance = selectedInstance else {
            return "先安装或选择一个实例后才能导出"
        }
        return "当前实例：「\(instance.name)」· DSH \(instance.dshVersion)"
    }

    /// 整合包进度卡（导入 / 导出）。
    @ViewBuilder
    private var packProgressSection: some View {
        if let title = DSHDownloadPackUI.busyTitle(dshPacks.state) {
            DSHProgressCard(
                title: title,
                phase: DSHDownloadPackUI.busyPhaseText(dshPacks.state) ?? "处理中…",
                progress: DSHDownloadPackUI.busyProgress(dshPacks.state),
                logLines: Array(dshPacks.logLines.suffix(5)),
                onCancel: {
                    dshPacks.cancel()
                    router.showToast("已请求取消整合包操作", tone: .info)
                }
            )
        }
    }

    /// 失败时的日志尾部（帮助定位是打包、解压还是安装插件阶段失败）。
    private var packFailureLog: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(dshPacks.logLines.suffix(4).enumerated()), id: \.offset) { _, line in
                LauncherMonoText(line, tone: .tertiary, size: 10)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(LauncherSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .strokeBorder(theme.colors.stroke, lineWidth: 1)
        }
    }

    /// 本地整合包实例列表。
    private var packInstanceListSection: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "本地整合包",
                    subtitle: "\(packInstances.count) 个 · 每个整合包实例有独立的插件与会话",
                    accessory: AnyView(
                        HStack(spacing: LauncherSpace.xs) {
                            if !packInstances.isEmpty {
                                LauncherMonoText(
                                    "DSH \(selectedInstance?.dshVersion ?? "—")",
                                    tone: .tertiary,
                                    size: 10
                                )
                                .lineLimit(1)
                            }
                        }
                    )
                )

                if packInstances.isEmpty {
                    LauncherEmptyState(
                        systemImage: "archivebox",
                        title: "还没有本地整合包",
                        message: snapshotMode
                            ? "快照模式不会读取磁盘整合包；启动启动器后会自动扫描本地实例。"
                            : "把同事分享的 .dshpack 导入进来，或在上面导出当前实例为整合包。",
                        actionTitle: snapshotMode ? nil : "导入整合包…",
                        onAction: snapshotMode ? nil : { beginImport() }
                    )
                    .frame(maxWidth: .infinity)
                } else if snapshotMode {
                    VStack(spacing: LauncherSpace.xs) {
                        ForEach(DSHDownloadList.visible(packInstances, limit: snapshotPackRowLimit)) { instance in
                            packInstanceRow(instance)
                        }
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: LauncherSpace.xs) {
                            ForEach(packInstances) { instance in
                                packInstanceRow(instance)
                            }
                        }
                    }
                    .frame(height: packListHeight)
                }

                HStack(spacing: LauncherSpace.xs) {
                    LauncherHintIcon("整合包格式：manifest.json + payload/runtime（完整包）或版本号（轻量包）+ payload/plugins。")
                    Text("完整包离线可用；轻量包导入时从 npm 安装 DSH")
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func packInstanceRow(_ instance: DSHInstalledVersion) -> some View {
        DSHPackInstanceRowView(
            instance: instance,
            isSelected: instance.id == selectedInstance?.id,
            isRunning: isRunning(instance),
            isBusy: dshPacks.isBusy || versions.installState.isInstalling,
            isReadOnly: snapshotMode,
            exportMenuGroups: exportModeMenuGroups(instance: instance),
            onSelect: { selectInstance(instance) },
            onUninstall: { confirmUninstall(instance) },
            onReveal: { InstanceActions.reveal(URL(fileURLWithPath: instance.path)) }
        )
    }

    /// 导出的两种模式菜单（完整包 / 轻量包）。
    private func exportModeMenuGroups(instance: DSHInstalledVersion) -> [LauncherMenuGroup] {
        [
            LauncherMenuGroup(title: "导出为整合包", items: [
                LauncherMenuItem(
                    "完整包（含 DSH 本体）…",
                    id: "export-bundled-\(instance.id)",
                    systemImage: "shippingbox",
                    detail: "离线可用，文件较大",
                    isDisabled: snapshotMode || dshPacks.isBusy
                ) {
                    beginExport(instance: instance, mode: .bundled)
                },
                LauncherMenuItem(
                    "轻量包（从 npm 安装）…",
                    id: "export-online-\(instance.id)",
                    systemImage: "square.and.arrow.up",
                    detail: "文件较小，导入时需要网络",
                    isDisabled: snapshotMode || dshPacks.isBusy
                ) {
                    beginExport(instance: instance, mode: .online)
                }
            ])
        ]
    }

    // MARK: - 行为：实例

    private func selectInstance(_ instance: DSHInstalledVersion) {
        guard !snapshotMode else { return }
        versions.select(instance.id)
        router.showToast("当前实例：「\(instance.name)」· DSH \(instance.dshVersion)", tone: .success)
    }

    /// 安装按钮：先弹 prompt 让用户自定义实例名（同版本可重复安装）。
    private func promptInstall(_ dshVersion: String) {
        guard !snapshotMode, !dshPacks.isBusy else { return }
        guard !versions.installState.isInstalling else {
            router.showToast("已有安装任务在进行", tone: .warning)
            return
        }
        if let reason = installDisabledReason {
            router.showToast(reason, tone: .warning)
            return
        }
        router.showPrompt(
            LauncherPromptRequest(
                title: "安装 DSH \(dshVersion)",
                message: "可以自定义实例名，例如「工作区」「实验」「插件测试」。同一个 DSH 版本可以安装多份：实例之间插件与会话隔离，登录凭据自动复用 ~/.dsh。",
                placeholder: "实例名",
                initialValue: DSHVersionStore.defaultName(for: dshVersion),
                confirmTitle: "开始安装",
                validate: { Self.validateInstanceName($0) },
                onConfirm: { name in
                    install(dshVersion, name: name)
                }
            )
        )
    }

    private func install(_ dshVersion: String, name: String) {
        guard !snapshotMode, !dshPacks.isBusy else { return }
        Task {
            await versions.install(dshVersion, name: name)
            switch versions.installState {
            case .failed(_, let message):
                router.showToast("安装失败：\(message)", tone: .danger)
            case .idle:
                if let instance = versions.selectedInstalledVersion, instance.dshVersion == dshVersion {
                    router.showToast("已安装实例「\(instance.name)」（DSH \(dshVersion)）", tone: .success)
                }
            case .installing:
                break
            }
        }
    }

    private func cancelInstall() {
        versions.cancelInstall()
        router.showToast("已请求取消安装", tone: .info)
    }

    /// 卸载实例：运行中的实例先拦住；确认框说明只删实例目录与本实例 home。
    private func confirmUninstall(_ instance: DSHInstalledVersion) {
        guard !snapshotMode, !versions.installState.isInstalling, !dshPacks.isBusy else { return }
        if isRunning(instance) {
            router.showToast("实例「\(instance.name)」正在运行，请先在启动页停止后再卸载", tone: .warning)
            return
        }
        router.showDialog(
            LauncherDialogRequest(
                title: "卸载实例「\(instance.name)」",
                message: "将删除该实例的安装目录、独立的 DSH_HOME（插件 / 会话 / 配置）与日志；登录凭据仍复用 ~/.dsh，其它实例不受影响。",
                confirmTitle: "卸载",
                isDestructive: true,
                onConfirm: {
                    if isRunning(instance) {
                        router.showToast("实例正在运行，请先停止后再卸载", tone: .warning)
                        return
                    }
                    if versions.uninstall(instance.id) {
                        router.showToast("已卸载实例「\(instance.name)」", tone: .success)
                    } else {
                        router.showToast(
                            versions.lastError?.localizedDescription ?? "卸载失败",
                            tone: .danger
                        )
                    }
                }
            )
        )
    }

    private static func validateInstanceName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 60 { return "实例名最多 60 个字符" }
        return nil
    }

    // MARK: - 行为：插件

    private func refreshPlugins(force: Bool, notify: Bool = true) async {
        guard !snapshotMode else { return }
        await plugins.refresh(force: force)
        if let message = plugins.catalogState.errorText {
            router.showToast(
                "插件源刷新失败：\(message)",
                tone: plugins.catalog == nil ? .danger : .warning
            )
        } else if notify, let catalog = plugins.catalog {
            router.showToast("插件源已更新：\(catalog.plugins.count) 个插件", tone: .success)
        }
    }

    private func installPlugin(_ entry: DSHPluginEntry, instance: DSHInstalledVersion) {
        guard !snapshotMode, !plugins.isBusy, !dshPacks.isBusy else { return }
        guard entry.installSpec != nil else {
            router.showToast("该插件没有 npm 包名 / 安装标识，需要按项目页说明手动安装", tone: .warning)
            return
        }
        Task {
            let ok = await plugins.install(entry, into: instance)
            if ok {
                router.showToast("已安装插件 \(entry.name)（实例「\(instance.name)」）", tone: .success)
            } else {
                router.showToast(
                    plugins.lastError?.localizedDescription ?? "插件安装失败",
                    tone: .danger
                )
            }
        }
    }

    private func confirmRemovePlugin(_ plugin: DSHInstalledPlugin, instance: DSHInstalledVersion) {
        guard !snapshotMode, !plugins.isBusy, !dshPacks.isBusy else { return }
        router.showDialog(
            LauncherDialogRequest(
                title: "卸载插件 \(plugin.name)",
                message: "将从实例「\(instance.name)」（DSH \(instance.dshVersion)）的 web profile 移除 \(plugin.dependencyKey)@\(plugin.version)。不会影响其它实例。",
                confirmTitle: "卸载插件",
                isDestructive: true,
                onConfirm: {
                    Task {
                        let ok = await plugins.remove(plugin, from: instance)
                        if ok {
                            router.showToast("已卸载插件 \(plugin.dependencyKey)", tone: .success)
                        } else {
                            router.showToast(
                                plugins.lastError?.localizedDescription ?? "插件卸载失败",
                                tone: .danger
                            )
                        }
                    }
                }
            )
        )
    }

    private func openPluginPage(_ entry: DSHPluginEntry) {
        guard let url = URL(string: entry.page ?? entry.url) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 行为：整合包

    /// 导入流程：选文件 → prompt 实例名 → 交给 DSHPackService。
    private func beginImport() {
        guard !snapshotMode, !dshPacks.isBusy else { return }
        guard let url = pickPackFile() else { return }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let sizeText = DSHDownloadFormat.size(Int64(fileSize))
        router.showPrompt(
            LauncherPromptRequest(
                title: "导入 DSH 整合包",
                message: "文件：\(url.lastPathComponent)（\(sizeText)）。\n可以为导入的实例自定义名字；导入后会成为新的本地实例（插件 / 会话独立，登录凭据复用 ~/.dsh）。",
                placeholder: "实例名",
                initialValue: DSHDownloadPackUI.defaultImportName(for: url),
                confirmTitle: "开始导入",
                validate: { Self.validateInstanceName($0) },
                onConfirm: { name in
                    performImport(url: url, name: name)
                }
            )
        )
    }

    private func performImport(url: URL, name: String) {
        guard !snapshotMode else { return }
        Task {
            let instance = await dshPacks.importPack(from: url, customName: name)
            if let instance {
                versions.select(instance.id)
                router.showToast("已导入整合包实例「\(instance.name)」", tone: .success)
            } else {
                router.showToast(
                    dshPacks.lastError?.localizedDescription ?? "导入整合包失败",
                    tone: .danger
                )
            }
        }
    }

    /// 导出流程：选保存位置 → 交给 DSHPackService（完整包 / 轻量包）。
    private func beginExport(instance: DSHInstalledVersion?, mode: DSHPackRuntimeMode) {
        guard !snapshotMode, !dshPacks.isBusy else { return }
        guard let instance else {
            router.showToast("请先安装并选择一个 DSH 实例", tone: .warning)
            return
        }
        if dshProcess.isRunning, dshProcess.activeInstanceID == instance.id {
            router.showToast("实例「\(instance.name)」正在运行，请先停止再导出整合包", tone: .warning)
            return
        }
        guard let destination = pickPackDestination(defaultName: instance.name) else { return }
        performExport(instance: instance, mode: mode, destination: destination)
    }

    private func performExport(instance: DSHInstalledVersion, mode: DSHPackRuntimeMode, destination: URL) {
        guard !snapshotMode else { return }
        let name = instance.name
        let version = "1.0.0"
        let description = "从实例「\(name)」导出的 DSH 整合包（DSH \(instance.dshVersion)）"
        Task {
            let url = await dshPacks.exportPack(
                instance: instance,
                name: name,
                version: version,
                description: description,
                author: "",
                runtime: mode,
                includePluginPayloads: true,
                to: destination
            )
            if let url {
                router.showToast(
                    "已导出整合包：\(DSHDownloadFormat.shortHomePath(url.path))",
                    tone: .success
                )
                InstanceActions.reveal(url)
            } else {
                router.showToast(
                    dshPacks.lastError?.localizedDescription ?? "导出整合包失败",
                    tone: .danger
                )
            }
        }
    }

    /// 选择 `.dshpack` 文件（非快照模式）。
    private func pickPackFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择 DSH 整合包"
        panel.message = "选择 .dshpack 文件（LauncherALL 私有 DSH 整合包）"
        panel.prompt = "导入"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        applyPackContentType(to: panel)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard DSHDownloadPackUI.isPackFile(url) else {
            router.showToast("请选择 .\(DSHDownloadPackUI.fileExtension) 文件", tone: .warning)
            return nil
        }
        return url
    }

    /// 选择导出位置（非快照模式）。
    private func pickPackDestination(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "导出 DSH 整合包"
        panel.prompt = "导出"
        panel.nameFieldStringValue = DSHDownloadPackUI.exportFileName(defaultName)
        panel.canCreateDirectories = true
        applyPackContentType(to: panel)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if DSHDownloadPackUI.isPackFile(url) { return url }
        return url.appendingPathExtension(DSHDownloadPackUI.fileExtension)
    }

    /// 面板只允许 `.dshpack`（未注册扩展名时回退为动态 UTType）。
    private func applyPackContentType(to panel: NSSavePanel) {
        if let type = UTType(filenameExtension: DSHDownloadPackUI.fileExtension) {
            panel.allowedContentTypes = [type]
        }
    }

    // MARK: - 行为：其它

    private func refreshVersions(force: Bool, notify: Bool = true) {
        guard !snapshotMode else { return }
        Task {
            await versions.refreshCatalog(force: force)
            environment = .capture(store: versions)
            if let message = versions.catalogState.errorText, versions.catalog == nil {
                router.showToast("版本列表刷新失败：\(message)", tone: .danger)
            } else if notify, let catalog = versions.catalog {
                router.showToast("版本列表已更新：\(catalog.versions.count) 个版本", tone: .success)
            }
        }
    }

    private func refreshAll() {
        guard !snapshotMode, !isRefreshingAll else { return }
        isRefreshingAll = true
        Task {
            await versions.refreshCatalog(force: true)
            await plugins.refresh(force: true)
            versions.refreshInstalled()
            let env = DSHEnvironmentSnapshot.capture(store: versions)
            environment = env
            isRefreshingAll = false
            let versionCount = versions.catalog?.versions.count ?? 0
            let pluginCount = plugins.catalog?.plugins.count ?? 0
            if versions.catalog == nil && plugins.catalog == nil {
                router.showToast(
                    versions.catalogState.errorText ?? plugins.catalogState.errorText ?? "刷新失败",
                    tone: .danger
                )
            } else {
                router.showToast(
                    "已刷新：\(versionCount) 个版本 · \(pluginCount) 个插件 · \(versions.installed.count) 个实例",
                    tone: env.isReady ? .success : .warning
                )
            }
        }
    }

    private func openDSHDirectory() {
        let directory = versions.paths.root
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if InstanceActions.open(directory) {
            router.showToast("已打开 DSH 数据目录", tone: .info)
        } else {
            router.showToast("无法打开目录：\(directory.path)", tone: .danger)
        }
    }
}
