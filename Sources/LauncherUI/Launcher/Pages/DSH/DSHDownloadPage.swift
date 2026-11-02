import AppKit
import SwiftUI

// MARK: - 下载页分类

/// DSH 下载页的两个一级入口。
private enum DSHDownloadCategory: String, CaseIterable, Identifiable {
    case versions
    case plugins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .versions: return "DSH 版本"
        case .plugins: return "插件市场"
        }
    }

    var systemImage: String {
        switch self {
        case .versions: return "shippingbox.fill"
        case .plugins: return "puzzlepiece.extension.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .versions: return "npm · @deepseek-ai/dsh"
        case .plugins: return "dshmarket 加载源"
        }
    }
}

// MARK: - 下载页

/// DSH 启动器的「下载」页：安装 `@deepseek-ai/dsh` 的各个版本，并从 dshmarket 加载源浏览 / 安装社区插件。
///
/// 结构与 Minecraft 下载页同构：左侧 300pt 分类 + 右侧主面板。
/// 安装 / 卸载全部调用 `DSHVersionStore` / `DSHPluginStore` 的真实实现，进度与日志来自 store；
/// 没有伪造进度或演示数据，快照模式下不发起网络请求。
public struct DSHDownloadPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherRouter.self) private var router
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    @Environment(DSHVersionStore.self) private var versions
    @Environment(DSHPluginStore.self) private var plugins
    @Environment(DSHProcessController.self) private var dshProcess

    @State private var category: DSHDownloadCategory = .versions
    /// 运行环境检测结果（task / 手动刷新时更新，避免每帧 spawn 子进程）。
    @State private var environment: DSHEnvironmentSnapshot?
    /// 展开详情的插件 id。
    @State private var expandedPluginID: String?
    /// 是否正在刷新全部（左侧底部按钮的加载态）。
    @State private var isRefreshingAll = false

    /// 快照模式下列表最多静态渲染的条数（离屏渲染没有滚动，超出会溢出；取整行/整卡，避免裁切一半）。
    private let snapshotVersionRowLimit = 5
    private let snapshotPluginRowLimit = 2
    /// 交互模式下列表滚动区高度（保证 1080×720 首屏不需要滚动整个页面）。
    private let versionListHeight = (LauncherControl.large + LauncherSpace.xs) * 5 + LauncherSpace.xxs * 4
    private let pluginListHeight = LauncherControl.large * 6 + LauncherSpace.lg * 2

    public init() {}

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
            guard newValue == .plugins, !snapshotMode else { return }
            plugins.loadCachedCatalogIfNeeded()
            if plugins.catalog == nil {
                Task { await refreshPlugins(force: false, notify: false) }
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

    /// 消费跨页动作（启动页空态「去下载 DSH」/「管理插件」）：
    /// `dsh-versions` → 版本分类，`dsh-plugins` → 插件市场分类；消费后立即清空，避免重复触发。
    private func consumePendingDownloadAction() {
        guard let destination = DSHDownloadDeepLink.destination(for: router.pendingDownloadAction) else {
            return
        }
        router.pendingDownloadAction = nil
        let target: DSHDownloadCategory = destination == .versions ? .versions : .plugins
        guard category != target else { return }
        withAnimation(LauncherMotion.spring) {
            category = target
        }
    }

    /// 展示用环境快照：交互模式用 task 结果；快照模式做一次性同步探测（只读本机、不联网）。
    private var environmentSnapshot: DSHEnvironmentSnapshot {
        if let environment { return environment }
        if snapshotMode { return .notProbed }
        return .notProbed
    }

    // MARK: - 左面板

    private var sidePanel: some View {
        LauncherSidePanel(
            title: "下载",
            count: "\(versions.catalog?.versions.count ?? 0)",
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
            accessibilityLabel: "刷新 DSH 版本与插件源",
            isDisabled: snapshotMode || isRefreshingAll
        ) {
            refreshAll()
        }
        .launcherTooltip(
            snapshotMode
                ? "快照模式不发起网络请求"
                : (isRefreshingAll ? "正在刷新版本目录与插件源…" : "刷新版本目录与插件源")
        )
    }

    @ViewBuilder
    private var sideContent: some View {
        LauncherSidePanelGroup("DSH", trailing: "\(plugins.pluginCount) 插件")
        categoryRow(.versions)
        categoryRow(.plugins)

        LauncherSidePanelGroup("当前版本")
        currentVersionCard

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
            return total > 0 ? "npm · \(total) 个版本" : item.subtitle
        case .plugins:
            return plugins.pluginCount > 0
                ? "dshmarket · \(plugins.pluginCount) 个插件"
                : item.subtitle
        }
    }

    private var currentVersionCard: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
            if let selected = versions.selectedInstalledVersion {
                HStack(spacing: LauncherSpace.xs) {
                    LauncherMonoText(selected.version, tone: .primary, size: 12)
                        .lineLimit(1)
                    LauncherBadge("使用中", tone: .accent)
                    Spacer(minLength: 0)
                }
                Text("安装于 \(DSHDownloadFormat.date(selected.installedAt)) · \(DSHDownloadFormat.size(selected.sizeBytes))")
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
                Text("共享 DSH_HOME · \(snapshotMode ? "~/Library/Application Support/BlockLauncher/DSH/home" : DSHDownloadFormat.shortHomePath(versions.paths.homeDirectory(for: selected.version).path))")
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("未安装任何版本")
                    .textStyle(.micro, tone: .tertiary)
                Text("插件安装到 launcher 共享的 web profile；先安装一个 DSH 版本用于执行 dsh plugin 命令。")
                    .textStyle(.micro, tone: .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
                .launcherTooltip(snapshotMode ? "快照模式不发起网络请求" : "刷新版本目录、插件源与运行环境")
                LauncherIconButton(
                    systemImage: "folder",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: "打开 DSH 数据目录",
                    isDisabled: snapshotMode
                ) {
                    openDSHDirectory()
                }
                .launcherTooltip("打开 BlockLauncher/DSH 数据目录（版本、home、缓存）")
            }
            HStack(spacing: LauncherSpace.xs) {
                Text("已安装 \(versions.installed.count) 个版本")
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
        }
    }

    // MARK: - DSH 版本面板

    @ViewBuilder
    private var versionsPanel: some View {
        LauncherPanelHeader("DSH 版本", subtitle: versionsPanelSubtitle) {
            HStack(spacing: LauncherSpace.xs) {
                LauncherBadge(
                    "\(versions.installed.count) 已安装",
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
        parts.append("\(versions.installed.count) 个已安装")
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
                onAction: snapshotMode ? nil : { installVersion(version) }
            )
        case .idle:
            EmptyView()
        }
    }

    /// 版本列表。
    @ViewBuilder
    private var versionCatalogSection: some View {
        if let catalog = versions.catalog {
            let installedIDs = Set(versions.installed.map(\.version))
            let partition = DSHDownloadList.partition(catalog.versions, installedIDs: installedIDs)
            let ordered = partition.displayOrder
            LauncherCard(level: .regular, padding: LauncherSpace.md) {
                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    LauncherSectionHeader(
                        title: "版本列表",
                        subtitle: "共 \(partition.total) 个版本 · 已安装 \(partition.installed.count) 个",
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
                        LauncherHintIcon("安装只下载该版本的 node_modules；所有 DSH 版本共享 launcher 的 DSH_HOME（~/Library/Application Support/BlockLauncher/DSH/home），并自动复用 ~/.dsh 的登录凭据，无需重新输入密钥。")
                        Text("版本隔离 node_modules · 共享 launcher DSH_HOME（自动复用 ~/.dsh 登录凭据）")
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
            installedAt: versions.installed.first { $0.version == info.version }?.installedAt,
            isInstalled: installedIDs.contains(info.version),
            isSelected: versions.settings.dshSelectedVersion == info.version,
            isInstalling: versions.installState.installingVersion == info.version,
            isBusy: versions.installState.isInstalling,
            isReadOnly: snapshotMode,
            canInstall: !snapshotMode && environmentSnapshot.isReady,
            installDisabledReason: installDisabledReason,
            onInstall: { installVersion(info.version) },
            onUse: { useVersion(info.version) },
            onUninstall: { confirmUninstall(info.version) }
        )
    }

    private var installedIDs: Set<String> {
        Set(versions.installed.map(\.version))
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
        var parts = ["dshmarket 加载源"]
        if let updated = plugins.updatedText {
            parts.append("更新于 \(String(updated.prefix(10)))")
        }
        parts.append("\(plugins.pluginCount) 个插件")
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
                    ? "执行 dsh plugin --profile web add（web profile）"
                    : "执行 dsh plugin --profile web remove（web profile）",
                logLines: Array(plugins.operationLog.suffix(4)),
                onCancel: {
                    plugins.cancelOperation()
                    router.showToast("已请求取消插件操作", tone: .info)
                }
            )
        }
    }

    /// 插件主体：没有安装版本时给引导，否则展示已安装插件 + 插件列表。
    @ViewBuilder
    private var pluginsBody: some View {
        if versions.selectedInstalledVersion == nil {
            LauncherCard(level: .regular, padding: LauncherSpace.lg) {
                LauncherEmptyState(
                    systemImage: "puzzlepiece.extension",
                    title: "还没有可安装的 DSH 版本",
                    message: "插件通过 dsh plugin --profile web add 安装到 launcher 共享 web profile。先安装一个 DSH 版本用于执行命令。",
                    actionTitle: "去安装 DSH 版本",
                    onAction: {
                        withAnimation(LauncherMotion.spring) {
                            category = .versions
                        }
                    }
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            installedPluginsCard
            pluginCatalogSection
        }
    }

    private var installedPluginsCard: some View {
        let installedPlugins = plugins.installedPlugins(for: versionBindingTarget)
        return LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "已安装插件",
                    subtitle: "共享 web profile（launcher DSH_HOME）· 所有 DSH 版本共用",
                    accessory: AnyView(
                        HStack(spacing: LauncherSpace.xs) {
                            LauncherBadge("\(installedPlugins.count) 个", tone: installedPlugins.isEmpty ? .neutral : .success)
                            LauncherDropdown(
                                options: installedVersionOptions,
                                selection: targetVersionBinding,
                                placeholder: "选择命令版本"
                            )
                            .frame(width: 132)
                        }
                    )
                )

                if installedPlugins.isEmpty {
                    Text("共享 web profile 里还没有安装插件；在下方插件市场里点「安装」即可。")
                        .textStyle(.micro, tone: .tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(DSHDownloadList.visible(installedPlugins, limit: 2)) { plugin in
                        installedPluginRow(plugin)
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

    /// 当前插件安装目标版本（插件安装 / 卸载都针对它）。
    private var versionBindingTarget: DSHInstalledVersion {
        versions.selectedInstalledVersion ?? versions.installed[0]
    }

    private var installedVersionOptions: [LauncherSegment<String>] {
        versions.installed.map { LauncherSegment(id: $0.version, title: $0.version, systemImage: "shippingbox.fill") }
    }

    private var targetVersionBinding: Binding<String> {
        Binding(
            get: { versionBindingTarget.version },
            set: { versions.select($0) }
        )
    }

    private func installedPluginRow(_ plugin: DSHInstalledPlugin) -> some View {
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
                confirmRemovePlugin(plugin)
            }
            .launcherTooltip(
                snapshotMode
                    ? "快照模式不执行卸载"
                    : (plugins.isBusy ? "插件操作进行中" : "从共享 web profile 卸载该插件")
            )
        }
        .frame(minHeight: LauncherControl.small)
    }

    @ViewBuilder
    private var pluginCatalogSection: some View {
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
                        pluginList(filtered)
                    }

                    HStack(spacing: LauncherSpace.xs) {
                        LauncherHintIcon("安装走 dsh plugin --profile web add <包名>，与官方插件管理一致。")
                        Text("插件安装在 launcher 共享 web profile 内，所有 DSH 版本共用")
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
    private func pluginList(_ filtered: [DSHPluginEntry]) -> some View {
        let target = versions.selectedInstalledVersion
        let installedPlugins = target.map { plugins.installedPlugins(for: $0) } ?? []
        if snapshotMode {
            VStack(spacing: LauncherSpace.xs) {
                ForEach(DSHDownloadList.visible(filtered, limit: snapshotPluginRowLimit)) { entry in
                    pluginCard(entry, installedPlugins: installedPlugins)
                }
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: LauncherSpace.xs) {
                    ForEach(filtered) { entry in
                        pluginCard(entry, installedPlugins: installedPlugins)
                    }
                }
            }
            .frame(height: pluginListHeight)
        }
    }

    private func pluginCard(_ entry: DSHPluginEntry, installedPlugins: [DSHInstalledPlugin]) -> some View {
        let plugin = installedPlugin(for: entry, in: installedPlugins)
        return DSHPluginCardView(
            entry: entry,
            categoryTitle: DSHDownloadList.categoryTitle(entry.categoryID, categories: plugins.categories),
            isInstalled: plugin != nil,
            isExpanded: expandedPluginID == entry.id,
            isBusy: plugins.isBusy,
            isReadOnly: snapshotMode,
            canInstall: pluginInstallAllowed(for: entry),
            installDisabledReason: pluginInstallDisabledReason(for: entry),
            onToggle: {
                withAnimation(LauncherMotion.spring) {
                    expandedPluginID = expandedPluginID == entry.id ? nil : entry.id
                }
            },
            onInstall: { installPlugin(entry) },
            onRemove: {
                if let plugin {
                    confirmRemovePlugin(plugin)
                }
            },
            onOpen: { openPluginPage(entry) }
        )
    }

    private func installedPlugin(for entry: DSHPluginEntry, in installedPlugins: [DSHInstalledPlugin]) -> DSHInstalledPlugin? {
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

    private func pluginInstallAllowed(for entry: DSHPluginEntry) -> Bool {
        !snapshotMode
            && environmentSnapshot.isReady
            && versions.selectedInstalledVersion != nil
            && entry.installSpec != nil
            && !plugins.isBusy
    }

    private func pluginInstallDisabledReason(for entry: DSHPluginEntry) -> String? {
        if snapshotMode { return "快照模式不执行安装" }
        if !environmentSnapshot.isReady { return "缺少 Node.js / 包管理器" }
        if versions.selectedInstalledVersion == nil { return "请先安装并选择一个 DSH 版本" }
        if entry.installSpec == nil { return "该插件没有 npm 包名，需要按项目页手动安装" }
        if plugins.isBusy { return "已有插件操作在进行" }
        return nil
    }

    // MARK: - 行为：版本

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

    private func installVersion(_ version: String) {
        guard !snapshotMode, !versions.installState.isInstalling else { return }
        Task {
            await versions.install(version)
            switch versions.installState {
            case .failed(_, let message):
                router.showToast("安装失败：\(message)", tone: .danger)
            case .idle:
                if versions.installed.contains(where: { $0.version == version }) {
                    router.showToast("DSH \(version) 已安装并设为当前版本", tone: .success)
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

    private func useVersion(_ version: String) {
        guard !snapshotMode else { return }
        versions.select(version)
        router.showToast("当前版本：DSH \(version)", tone: .success)
    }

    private func confirmUninstall(_ version: String) {
        guard !snapshotMode, !versions.installState.isInstalling else { return }
        if dshProcess.isRunning && dshProcess.activeVersion == version {
            router.showToast("DSH \(version) 正在运行，请先在启动页停止后再卸载", tone: .warning)
            return
        }
        router.showDialog(
            LauncherDialogRequest(
                title: "卸载 DSH \(version)",
                message: "只删除该版本的安装目录与日志；共享的 DSH_HOME（插件 / 会话 / 配置）保留，其它 DSH 版本不受影响。",
                confirmTitle: "卸载",
                isDestructive: true,
                onConfirm: {
                    if dshProcess.isRunning && dshProcess.activeVersion == version {
                        router.showToast("DSH \(version) 正在运行，请先停止后再卸载", tone: .warning)
                        return
                    }
                    if versions.uninstall(version) {
                        router.showToast("已卸载 DSH \(version)", tone: .success)
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

    private func installPlugin(_ entry: DSHPluginEntry) {
        guard !snapshotMode, !plugins.isBusy else { return }
        guard let target = versions.selectedInstalledVersion else {
            router.showToast("请先安装并选择一个 DSH 版本", tone: .warning)
            return
        }
        guard entry.installSpec != nil else {
            router.showToast("该插件没有 npm 包名 / 安装标识，需要按项目页说明手动安装", tone: .warning)
            return
        }
        Task {
            let ok = await plugins.install(entry, into: target)
            if ok {
                router.showToast("已安装插件 \(entry.name)", tone: .success)
            } else {
                router.showToast(
                    plugins.lastError?.localizedDescription ?? "插件安装失败",
                    tone: .danger
                )
            }
        }
    }

    private func confirmRemovePlugin(_ plugin: DSHInstalledPlugin) {
        guard !snapshotMode, !plugins.isBusy else { return }
        let target = versionBindingTarget
        router.showDialog(
            LauncherDialogRequest(
                title: "卸载插件 \(plugin.name)",
                message: "将从 DSH \(target.version) 的 web profile 移除 \(plugin.dependencyKey)@\(plugin.version)。不会影响其它版本。",
                confirmTitle: "卸载插件",
                isDestructive: true,
                onConfirm: {
                    Task {
                        let ok = await plugins.remove(plugin, from: target)
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

    // MARK: - 行为：其它

    private func refreshAll() {
        guard !snapshotMode, !isRefreshingAll else { return }
        isRefreshingAll = true
        Task {
            await versions.refreshCatalog(force: true)
            await plugins.refresh(force: true)
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
                    "已刷新：\(versionCount) 个版本 · \(pluginCount) 个插件 · 环境\(env.isReady ? "就绪" : "缺少依赖")",
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
