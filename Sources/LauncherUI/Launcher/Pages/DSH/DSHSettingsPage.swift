import SwiftUI
import AppKit

// MARK: - DSH 设置页

/// DSH 启动器的设置页：左侧分类 + 右侧卡片，全部读写真实设置 / 真实文件 / 真实网络。
///
/// 分类：启动（端口 / 自动打开浏览器 / 默认实例）、下载与插件（npm 源 / 插件加载源 / 缓存）、
/// 环境与目录（运行时检测 / 实例 DSH_HOME / 实例数据目录）、关于（版本与危险区）。
public struct DSHSettingsPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherRouter.self) private var router
    @Environment(DSHVersionStore.self) private var versions
    @Environment(DSHPluginStore.self) private var plugins
    @Environment(DSHProcessController.self) private var dshProcess
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    // MARK: 页面状态（仅 UI 反馈）

    /// 当前分类
    @State private var section: DSHSettingsSection = .launch
    /// 端口输入草稿（nil = 直接显示设置里的真实值）
    @State private var portDraft: String?
    /// npm registry 输入草稿
    @State private var registryDraft: String?
    /// 插件加载源输入草稿
    @State private var pluginSourceDraft: String?
    /// 插件目录刷新中
    @State private var isRefreshingCatalog = false
    /// 运行时检测结果（后台检测，快照模式不检测）
    @State private var environment: DSHRuntimeEnvironment?
    /// 运行时检测中
    @State private var isDetectingEnvironment = false
    /// 数据目录统计（真实大小，交互模式后台计算）
    @State private var directoryRows: [DSHDataDirectory] = []

    /// 创建设置页。
    public init() {}

    /// 创建并直接打开某个分类（供路由预览与离屏截图使用）。
    public init(initialSection: DSHSettingsSection) {
        _section = State(initialValue: initialSection)
    }

    public var body: some View {
        LauncherPageLayout(sideWidth: 236) {
            sidePanel
        } main: {
            LauncherMainPanel {
                VStack(alignment: .leading, spacing: LauncherSpace.md) {
                    mainHeader
                    GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.md) {
                        categoryContent
                    }
                    Spacer(minLength: LauncherSpace.md)
                    saveBar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task {
            await detectEnvironmentIfNeeded()
            await loadDirectoriesIfNeeded()
        }
    }

    // MARK: - 左侧分类面板

    /// 左面板：DSH 设置分类列表 + 底部真实版本信息。
    private var sidePanel: some View {
        LauncherSidePanel(
            title: "设置",
            count: nil,
            width: 236,
            content: {
                LauncherSidePanelGroup("DSH 启动器")
                ForEach(DSHSettingsSection.allCases) { item in
                    sideRow(item)
                }
            },
            footer: { sidePanelFooter }
        )
    }

    /// 分类行。
    private func sideRow(_ item: DSHSettingsSection) -> some View {
        LauncherListRow(
            title: item.title,
            systemImage: item.systemImage,
            badge: sectionBadge(item),
            isSelected: section == item,
            action: {
                withAnimation(LauncherMotion.spring) {
                    section = item
                }
            }
        )
    }

    /// 分类行右侧徽标。
    private func sectionBadge(_ item: DSHSettingsSection) -> String? {
        switch item {
        case .launch:
            return DSHFormatting.portText(versions.settings.dshPort)
        case .plugins:
            if plugins.catalogState.isLoading { return "加载中" }
            return plugins.catalog == nil ? nil : "\(plugins.pluginCount)"
        case .environment:
            return versions.installed.isEmpty ? nil : "\(versions.installed.count) 实例"
        case .about:
            return nil
        }
    }

    /// 左面板底部：LauncherALL 版本 + 自动保存标识。
    private var sidePanelFooter: some View {
        VStack(spacing: LauncherSpace.xs) {
            Rectangle()
                .fill(theme.colors.stroke)
                .frame(height: 1)
            HStack(spacing: LauncherSpace.xs) {
                LauncherMonoText(LauncherBuildInfo.current.versionText, tone: .tertiary, size: 10)
                Spacer(minLength: 0)
                LauncherBadge("自动保存", tone: .neutral)
            }
            .padding(.horizontal, LauncherSpace.xxs)
        }
    }

    // MARK: - 右侧页头

    /// 右侧标题：分类名 + 说明 + 状态徽标。
    private var mainHeader: some View {
        LauncherPanelHeader(section.title, subtitle: section.subtitle) {
            HStack(spacing: LauncherSpace.xs) {
                if let badge = headerBadge {
                    LauncherBadge(badge, tone: headerBadgeTone)
                }
                if section == .environment {
                    LauncherIconButton(
                        systemImage: "arrow.clockwise",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: "重新检测运行时",
                        isDisabled: isDetectingEnvironment,
                        action: { refreshEnvironment() }
                    )
                }
            }
        }
    }

    /// 页头徽标文案。
    private var headerBadge: String? {
        switch section {
        case .launch:
            return versions.settings.dshPort == 0
                ? "端口自动"
                : "端口 \(versions.settings.dshPort)"
        case .plugins:
            switch plugins.catalogState {
            case .idle: return "未加载"
            case .loading: return "加载中"
            case .loaded: return "\(plugins.pluginCount) 个插件"
            case .failed: return "加载失败"
            }
        case .environment:
            return DSHFormatting.instanceCountText(versions.installed)
        case .about:
            return versions.settings.dshSelectedInstanceID.isEmpty ? "未选择实例" : nil
        }
    }

    /// 页头徽标色调。
    private var headerBadgeTone: LauncherBadgeTone {
        switch section {
        case .plugins:
            if case .failed = plugins.catalogState { return .warning }
            if case .loaded = plugins.catalogState { return .success }
            return .neutral
        default:
            return .neutral
        }
    }

    // MARK: - 右侧分类内容

    @ViewBuilder
    private var categoryContent: some View {
        switch section {
        case .launch: launchContent
        case .plugins: pluginsContent
        case .environment: environmentContent
        case .about: aboutContent
        }
    }

    // MARK: - 1. 启动

    /// 启动分类：端口、启动后自动打开浏览器、默认版本。
    private var launchContent: some View {
        @Bindable var settings = versions.settings
        return VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                "Web UI 端口",
                subtitle: "默认 3080；0 = 自动选择空闲端口，端口被占用会自动顺延",
                tooltip: "端口只在下次启动 DSH Web UI 时生效；已运行的进程不受影响"
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherTextField(
                        "端口",
                        text: portBinding,
                        systemImage: "number",
                        helper: portHelper,
                        error: portError,
                        onSubmit: applyPort
                    )
                    .frame(maxWidth: 160)
                    LauncherButton(
                        "应用",
                        systemImage: "checkmark",
                        variant: .secondary,
                        size: .small,
                        isDisabled: portError != nil
                    ) {
                        applyPort()
                    }
                    .fixedSize()
                    LauncherButton(
                        "默认 3080",
                        systemImage: "arrow.counterclockwise",
                        variant: .secondary,
                        size: .small
                    ) {
                        portDraft = nil
                        settings.dshPort = 3080
                        router.showToast("端口已恢复默认：3080")
                    }
                    .fixedSize()
                }
            }

            DSHBooleanRow(
                title: "启动后自动打开浏览器",
                subtitle: "Web UI 就绪后自动用默认浏览器打开带 token 的地址",
                tooltip: "关闭后仍可在「更多 → 进程」里手动打开",
                isOn: $settings.dshAutoOpenBrowser
            )

            LauncherSettingRow(
                "默认实例",
                subtitle: selectedInstanceSubtitle,
                tooltip: "启动 DSH 启动器时默认使用这个实例；同一 DSH 版本可以安装成多个实例",
                showsDivider: false
            ) {
                if versions.installed.isEmpty {
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherBadge("未安装实例", tone: .warning)
                        LauncherButton(
                            "去下载",
                            systemImage: "arrow.down.circle",
                            variant: .secondary,
                            size: .small
                        ) {
                            router.go(.download)
                        }
                        .fixedSize()
                    }
                } else {
                    LauncherMenuButton(
                        versions.selectedInstalledVersion?.name ?? "未选择",
                        systemImage: "chevron.down",
                        variant: .secondary,
                        size: .small,
                        groups: instanceMenuGroups
                    )
                }
            }
        }
        .onChange(of: versions.settings.dshPort) { _, _ in
            // 外部修改端口后清掉草稿，保证输入框显示真实值
            portDraft = nil
        }
    }

    /// 端口输入绑定。
    private var portBinding: Binding<String> {
        Binding(
            get: { portDraft ?? String(versions.settings.dshPort) },
            set: { portDraft = $0 }
        )
    }

    /// 端口输入下方的辅助说明。
    private var portHelper: String? {
        guard portError == nil else { return nil }
        if let portDraft, !portDraft.trimmingCharacters(in: .whitespaces).isEmpty {
            return nil
        }
        return versions.settings.dshPort == 0 ? "当前：自动" : "当前：固定 \(versions.settings.dshPort)"
    }

    /// 端口输入错误（不合法时显示在输入框下方）。
    private var portError: String? {
        guard let portDraft else { return nil }
        if case .failure(let error) = DSHInputValidation.port(from: portDraft) {
            return error.errorDescription
        }
        return nil
    }

    /// 已选实例的说明。
    private var selectedInstanceSubtitle: String {
        guard let selected = versions.selectedInstalledVersion else {
            return versions.installed.isEmpty
                ? "还没有安装实例，先去「下载」页安装或导入整合包"
                : "选择一个实例作为默认启动实例"
        }
        let installedAt = "安装于 \(DSHFormatting.dateTime(selected.installedAt))"
        let size = selected.sizeBytes.map { DSHFormatting.byteCount($0) } ?? "大小未知"
        return "\(DSHFormatting.instanceDetail(selected)) · \(size) · \(installedAt)"
    }

    /// 实例菜单：所有已安装实例（同一版本可多实例，按 id 选择，当前项带勾）。
    private var instanceMenuGroups: [LauncherMenuGroup] {
        [LauncherMenuGroup(title: "已安装实例", items: versions.installed.map { instance in
            LauncherMenuItem(
                instance.name,
                id: instance.id,
                systemImage: versions.settings.dshSelectedInstanceID == instance.id
                    ? "checkmark"
                    : (instance.isPack ? "shippingbox.fill" : "shippingbox"),
                detail: DSHFormatting.instanceDetail(instance)
            ) {
                versions.select(instance.id)
                router.showToast("默认实例已设为 \(instance.name)")
            }
        })]
    }

    /// 应用端口输入。
    private func applyPort() {
        switch DSHInputValidation.port(from: portBinding.wrappedValue) {
        case .success(let port):
            versions.settings.dshPort = port
            portDraft = nil
            router.showToast("端口已保存：\(DSHFormatting.portText(port))（下次启动生效）")
        case .failure(let error):
            router.showToast(error.errorDescription ?? "端口不合法", tone: .warning)
        }
    }

    // MARK: - 2. 下载与插件

    /// 下载与插件分类：npm registry、插件加载源、缓存清理。
    private var pluginsContent: some View {
        @Bindable var settings = versions.settings
        return VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                "npm registry",
                subtitle: "留空使用官方源（\(DSHRegistryClient.defaultRegistry)）；安装与刷新版本列表生效",
                tooltip: "企业镜像或淘宝源可以加速 npm 安装"
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherTextField(
                        "https://registry.npmjs.org",
                        text: registryBinding,
                        systemImage: "network",
                        helper: registryHelper,
                        error: registryError,
                        onSubmit: applyRegistry
                    )
                    .frame(maxWidth: 280)
                    LauncherButton(
                        "应用",
                        systemImage: "checkmark",
                        variant: .secondary,
                        size: .small,
                        isDisabled: registryError != nil
                    ) {
                        applyRegistry()
                    }
                    .fixedSize()
                    LauncherButton(
                        "恢复默认",
                        systemImage: "arrow.counterclockwise",
                        variant: .secondary,
                        size: .small
                    ) {
                        registryDraft = nil
                        settings.dshRegistry = ""
                        router.showToast("npm registry 已恢复官方源")
                    }
                    .fixedSize()
                }
            }

            LauncherSettingRow(
                "插件加载源",
                subtitle: "dshmarket 的 plugins.json 地址；默认 \(DSHRegistryClient.defaultPluginSource)",
                tooltip: "修改后点「立即刷新」重新拉取插件目录"
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherTextField(
                        "插件加载源 URL",
                        text: pluginSourceBinding,
                        systemImage: "antenna.radiowaves.left.and.right",
                        helper: pluginSourceHelper,
                        error: pluginSourceError,
                        onSubmit: applyPluginSource
                    )
                    .frame(maxWidth: 280)
                    LauncherButton(
                        "应用",
                        systemImage: "checkmark",
                        variant: .secondary,
                        size: .small,
                        isDisabled: pluginSourceError != nil
                    ) {
                        applyPluginSource()
                    }
                    .fixedSize()
                    LauncherButton(
                        "恢复默认",
                        systemImage: "arrow.counterclockwise",
                        variant: .secondary,
                        size: .small
                    ) {
                        pluginSourceDraft = nil
                        settings.dshPluginSource = DSHRegistryClient.defaultPluginSource
                        router.showToast("插件加载源已恢复默认")
                    }
                    .fixedSize()
                }
            }

            pluginCatalogStatusRow

            LauncherSettingRow(
                "缓存清理",
                subtitle: "删除 cache/ 下的版本列表与插件市场缓存文件，下次加载会重新下载",
                showsDivider: false
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherBadge(cacheSummary.text, tone: cacheSummary.count == 0 ? .neutral : .warning)
                    LauncherButton(
                        "清理缓存",
                        systemImage: "trash",
                        variant: .secondary,
                        size: .small,
                        isDisabled: cacheSummary.count == 0
                    ) {
                        confirmClearCache()
                    }
                    .fixedSize()
                }
            }
        }
        .onChange(of: versions.settings.dshRegistry) { _, _ in registryDraft = nil }
        .onChange(of: versions.settings.dshPluginSource) { _, _ in pluginSourceDraft = nil }
    }

    /// registry 输入绑定。
    private var registryBinding: Binding<String> {
        Binding(
            get: { registryDraft ?? versions.settings.dshRegistry },
            set: { registryDraft = $0 }
        )
    }

    /// registry 辅助说明（展示实际生效地址）。
    private var registryHelper: String? {
        guard registryError == nil else { return nil }
        return "生效：\(DSHInputValidation.registryDisplayText(versions.settings.dshRegistry))"
    }

    /// registry 输入错误。
    private var registryError: String? {
        guard let registryDraft else { return nil }
        if case .failure(let error) = DSHInputValidation.registry(from: registryDraft) {
            return error.errorDescription
        }
        return nil
    }

    /// 插件加载源输入绑定。
    private var pluginSourceBinding: Binding<String> {
        Binding(
            get: { pluginSourceDraft ?? versions.settings.dshPluginSource },
            set: { pluginSourceDraft = $0 }
        )
    }

    /// 插件加载源辅助说明。
    private var pluginSourceHelper: String? {
        guard pluginSourceError == nil else { return nil }
        return "生效：\(versions.settings.dshPluginSource)"
    }

    /// 插件加载源输入错误。
    private var pluginSourceError: String? {
        guard let pluginSourceDraft else { return nil }
        if case .failure(let error) = DSHInputValidation.pluginSource(from: pluginSourceDraft) {
            return error.errorDescription
        }
        return nil
    }

    /// 插件目录状态行：来源 / 更新时间 / 立即刷新。
    private var pluginCatalogStatusRow: some View {
        HStack(alignment: .center, spacing: LauncherSpace.sm) {
            LauncherBadge(catalogStatusTitle, tone: catalogStatusTone, systemImage: catalogStatusIcon)
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text(catalogStatusDetail)
                    .textStyle(.micro, tone: .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                LauncherMonoText(plugins.sourceText, tone: .tertiary, size: 10)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: LauncherSpace.sm)
            LauncherButton(
                "立即刷新",
                systemImage: "arrow.clockwise",
                variant: .secondary,
                size: .small,
                isLoading: isRefreshingCatalog
            ) {
                refreshPluginCatalog()
            }
            .fixedSize()
        }
        .padding(.vertical, LauncherSpace.xs)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.colors.stroke.opacity(0.6))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.colors.stroke.opacity(0.6))
                .frame(height: 1)
        }
    }

    /// 插件目录状态徽标标题。
    private var catalogStatusTitle: String {
        switch plugins.catalogState {
        case .idle: return "未加载"
        case .loading: return "加载中"
        case .loaded: return "已加载"
        case .failed: return "加载失败"
        }
    }

    /// 插件目录状态色调。
    private var catalogStatusTone: LauncherBadgeTone {
        switch plugins.catalogState {
        case .idle: return .neutral
        case .loading: return .info
        case .loaded: return .success
        case .failed: return .warning
        }
    }

    /// 插件目录状态图标。
    private var catalogStatusIcon: String {
        switch plugins.catalogState {
        case .idle: return "questionmark.circle"
        case .loading: return "arrow.triangle.2.circlepath"
        case .loaded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    /// 插件目录状态说明。
    private var catalogStatusDetail: String {
        switch plugins.catalogState {
        case .idle:
            return snapshotMode ? "快照模式：不发起网络请求" : "尚未加载插件目录，点「立即刷新」拉取"
        case .loading:
            return "正在加载插件目录…"
        case .loaded(let date):
            let updated = plugins.updatedText.map { " · 源更新于 \($0)" } ?? ""
            return "\(plugins.pluginCount) 个插件 · \(DSHFormatting.time(date))\(updated)"
        case .failed(let message):
            return "加载失败：\(message)"
        }
    }

    /// 缓存概况。
    private var cacheSummary: (count: Int, bytes: Int64, text: String) {
        let files = DSHCacheMaintenance.cacheFiles(paths: versions.paths)
        let bytes = files.reduce(Int64(0)) { partial, url in
            partial + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return (files.count, bytes, "\(files.count) 个文件 · \(DSHFormatting.byteCount(bytes))")
    }

    /// 应用 registry。
    private func applyRegistry() {
        switch DSHInputValidation.registry(from: registryBinding.wrappedValue) {
        case .success(let value):
            versions.settings.dshRegistry = value
            registryDraft = nil
            router.showToast("npm registry 已保存：\(DSHInputValidation.registryDisplayText(value))")
        case .failure(let error):
            router.showToast(error.errorDescription ?? "registry 不合法", tone: .warning)
        }
    }

    /// 应用插件加载源。
    private func applyPluginSource() {
        switch DSHInputValidation.pluginSource(from: pluginSourceBinding.wrappedValue) {
        case .success(let value):
            versions.settings.dshPluginSource = value
            pluginSourceDraft = nil
            router.showToast("插件加载源已保存，点「立即刷新」重新拉取")
        case .failure(let error):
            router.showToast(error.errorDescription ?? "插件加载源不合法", tone: .warning)
        }
    }

    /// 真实刷新插件目录（网络请求）。
    private func refreshPluginCatalog() {
        guard !isRefreshingCatalog else { return }
        isRefreshingCatalog = true
        Task { @MainActor in
            await plugins.refresh(force: true)
            isRefreshingCatalog = false
            switch plugins.catalogState {
            case .loaded:
                router.showToast("插件目录已刷新：\(plugins.pluginCount) 个插件")
            case .failed(let message):
                router.showToast("刷新失败：\(message)", tone: .warning)
            default:
                router.showToast("已请求刷新插件目录", tone: .info)
            }
        }
    }

    /// 清理缓存前确认（明确文件数量与影响）。
    private func confirmClearCache() {
        let summary = cacheSummary
        guard summary.count > 0 else {
            router.showToast("没有可清理的缓存文件", tone: .info)
            return
        }
        router.showDialog(
            LauncherDialogRequest(
                title: "清理 DSH 缓存？",
                message: "将删除 cache/ 下的 \(summary.count) 个缓存文件（\(DSHFormatting.byteCount(summary.bytes))）：版本列表与插件市场缓存。下次加载会重新下载。",
                confirmTitle: "清理",
                isDestructive: true,
                onConfirm: {
                    let report = DSHCacheMaintenance.clearCache(paths: versions.paths)
                    if report.failedFiles.isEmpty {
                        router.showToast(report.summary)
                    } else {
                        router.showToast(report.summary, tone: .warning)
                    }
                }
            )
        )
    }

    // MARK: - 3. 环境与目录

    /// 环境与目录分类：运行时检测、数据目录、已安装版本统计。
    private var environmentContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                "运行时环境",
                subtitle: environmentSubtitle,
                tooltip: "DSH 需要 Node 20+ 与 pnpm / npm；桌面端自带的 Node 会被优先使用"
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherBadge(
                        environment == nil
                            ? (snapshotMode ? "未检测" : "检测中")
                            : (environment?.node == nil ? "缺少 Node" : "可用"),
                        tone: environment?.node == nil && environment != nil ? .warning : .neutral
                    )
                    LauncherButton(
                        "重新检测",
                        systemImage: "arrow.clockwise",
                        variant: .secondary,
                        size: .small,
                        isLoading: isDetectingEnvironment
                    ) {
                        refreshEnvironment()
                    }
                    .fixedSize()
                }
            }

            // 运行时详情：紧凑内联行（1080×720 下不展开折叠区也能看全）
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                DSHInfoRow(
                    title: "Node.js",
                    value: environment?.node ?? (snapshotMode ? "快照模式未检测" : "未检测"),
                    isMissing: environment != nil && environment?.node == nil,
                    systemImage: "terminal"
                )
                DSHInfoRow(
                    title: "包管理器",
                    value: environment?.packageManager ?? (snapshotMode ? "快照模式未检测" : "未检测"),
                    isMissing: environment != nil && environment?.packageManager == nil,
                    systemImage: "shippingbox"
                )
                DSHInfoRow(
                    title: "登录凭据",
                    value: "复用 ~/.dsh/.credentials.yaml",
                    systemImage: "key"
                )
            }
            .padding(.vertical, LauncherSpace.xs)

            LauncherDivider()

            // 实例 DSH_HOME：每个实例独立，凭据从 ~/.dsh 软链
            LauncherSettingRow(
                "实例 DSH_HOME",
                subtitle: instanceHomeSubtitle
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherBadge(
                        versions.selectedInstalledVersion?.name ?? "未选择实例",
                        tone: versions.selectedInstalledVersion == nil ? .warning : .accent
                    )
                    DSHPathText(text: instanceHomePath, tone: .tertiary, maxWidth: 300)
                    LauncherIconButton(
                        systemImage: "folder",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: "打开实例 DSH_HOME"
                    ) {
                        openDirectory(instanceHomePath, title: "实例 DSH_HOME")
                    }
                }
            }

            // versions / homes / logs / cache 真实路径与大小
            ForEach(Array(directoryDisplayRows.enumerated()), id: \.offset) { index, row in
                LauncherSettingRow(
                    row.title,
                    subtitle: row.kind == .homes
                        ? "\(row.detail)；当前共 \(versions.installed.count) 个实例"
                        : row.detail,
                    showsDivider: index < directoryDisplayRows.count - 1
                ) {
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherBadge(row.sizeText, tone: row.exists ? .neutral : .warning)
                        DSHPathText(text: row.path, tone: .tertiary, maxWidth: 260)
                        LauncherIconButton(
                            systemImage: "folder",
                            variant: .ghost,
                            size: .small,
                            accessibilityLabel: "打开\(row.title)",
                            isDisabled: !row.exists,
                            action: { openDirectory(row.path, title: row.title) }
                        )
                    }
                }
            }

            LauncherSettingRow(
                "已安装实例与占用",
                subtitle: DSHFormatting.installedSummary(versions.installed),
                showsDivider: false
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    if let latest = versions.latestVersion {
                        LauncherBadge("最新 \(latest.version)", tone: .neutral)
                    }
                    LauncherButton(
                        "重新扫描",
                        systemImage: "arrow.clockwise",
                        variant: .secondary,
                        size: .small
                    ) {
                        versions.refreshInstalled()
                        router.showToast("已重新扫描已安装的 DSH 实例")
                        Task { @MainActor in
                            await reloadDirectories(showsToast: true)
                        }
                    }
                    .fixedSize()
                }
            }
        }
    }

    /// 实例 DSH_HOME 的说明文案。
    private var instanceHomeSubtitle: String {
        guard let selected = versions.selectedInstalledVersion else {
            return "还没有选中实例：安装或选择实例后，这里显示它独立的 DSH_HOME（\(versions.paths.homesDirectory.path)）"
        }
        return "\(selected.name) 独享：插件 / 会话隔离；登录凭据仍从 ~/.dsh 软链复用"
    }

    /// 当前选中实例的 DSH_HOME；没有实例时显示 homes 根目录。
    private var instanceHomePath: String {
        DSHDataTools.instanceHomePath(paths: versions.paths, instanceID: versions.settings.dshSelectedInstanceID)
            ?? versions.paths.homesDirectory.path
    }

    /// 数据目录展示行：交互模式等后台统计，快照模式同步统计（确定性）。
    private var directoryDisplayRows: [DSHDataDirectory] {
        if !directoryRows.isEmpty { return directoryRows }
        if snapshotMode {
            return DSHDataTools.directories(
                paths: versions.paths,
                kinds: [.versions, .homes, .logs, .cache]
            )
        }
        return [.versions, .homes, .logs, .cache].map { kind in
            DSHDataDirectory(kind: kind, path: kind.url(paths: versions.paths).path, bytes: 0, exists: false)
        }
    }

    /// 后台统计数据目录大小。
    private func loadDirectoriesIfNeeded() async {
        guard !snapshotMode, directoryRows.isEmpty else { return }
        await reloadDirectories()
    }

    /// 重新统计目录大小（后台读盘）。
    private func reloadDirectories(showsToast: Bool = false) async {
        let paths = versions.paths
        let rows = await Task.detached(priority: .userInitiated) {
            DSHDataTools.directories(paths: paths, kinds: [.versions, .homes, .logs, .cache])
        }.value
        directoryRows = rows
        if showsToast {
            let total = rows.reduce(Int64(0)) { $0 + $1.bytes }
            router.showToast("目录统计已刷新：\(DSHFormatting.byteCount(total))")
        }
    }

    /// 运行时环境说明。
    private var environmentSubtitle: String {
        if let environment {
            return environment.summary
        }
        return snapshotMode ? "快照模式：未检测运行时" : "尚未检测运行时，点「重新检测」"
    }

    /// 在访达中打开目录。
    private func openDirectory(_ path: String, title: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            router.showToast("\(title)还不存在：启动或安装一次后会自动创建", tone: .warning)
            return
        }
        if InstanceActions.open(url) {
            router.showToast("已在访达中打开\(title)")
        } else {
            router.showToast("无法打开\(title)", tone: .warning)
        }
    }

    /// 首次进入时检测运行时（快照模式跳过）。
    private func detectEnvironmentIfNeeded() async {
        guard !snapshotMode, environment == nil, !isDetectingEnvironment else { return }
        await detectEnvironment()
    }

    /// 后台检测运行时并写入状态。
    private func detectEnvironment() async {
        isDetectingEnvironment = true
        let snapshot = await Task.detached(priority: .userInitiated) {
            DSHRuntimeEnvironment.detect()
        }.value
        environment = snapshot
        isDetectingEnvironment = false
    }

    /// 页头 / 行内的「重新检测」。
    private func refreshEnvironment() {
        guard !isDetectingEnvironment else { return }
        if snapshotMode {
            router.showToast("快照模式不启动子进程检测运行时", tone: .info)
            return
        }
        Task { @MainActor in
            await detectEnvironment()
            router.showToast("运行时已重新检测")
        }
    }

    // MARK: - 4. 关于

    /// 关于分类：版本信息、数据目录、危险区。
    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                "LauncherALL 版本",
                subtitle: "DSH 启动器与 Minecraft 启动器共用同一个壳"
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherBadge(LauncherBuildInfo.current.versionText, tone: .accent)
                    LauncherMonoText(LauncherBuildInfo.current.buildDateText, tone: .tertiary, size: 10)
                }
            }

            LauncherSettingRow(
                "DSH Web UI",
                subtitle: "使用官方 @deepseek-ai/dsh，每个实例独立 node_modules 与 DSH_HOME"
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherBadge(
                        versions.selectedInstalledVersion?.name ?? "未选择实例",
                        tone: versions.selectedInstalledVersion == nil ? .warning : .neutral
                    )
                    LauncherBadge(DSHFormatting.instanceCountText(versions.installed), tone: .neutral)
                }
            }

            LauncherSettingRow(
                "DSH 数据目录",
                subtitle: "实例目录 / 实例 DSH_HOME / 日志 / 缓存都在这里；登录凭据自动复用 ~/.dsh"
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    DSHPathText(text: versions.paths.root.path, tone: .tertiary, maxWidth: 320)
                    LauncherIconButton(
                        systemImage: "folder",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: "打开 DSH 数据目录"
                    ) {
                        openDirectory(versions.paths.root.path, title: "DSH 数据目录")
                    }
                }
            }

            LauncherDivider()

            // 危险区：删除所有实例数据（明确范围 + 二次确认，运行中禁止）
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherBanner(
                    title: "删除所有 DSH 实例数据",
                    message: "会删除启动器里的所有实例（\(DSHFormatting.instanceCountText(versions.installed))）：实例目录、实例 DSH_HOME（插件 / 会话）、日志与缓存。不会删除 ~/.dsh 的登录凭据（API Key / 账号）。运行中的实例请先在启动页停止。",
                    tone: .danger
                )
                HStack(spacing: LauncherSpace.sm) {
                    Spacer(minLength: 0)
                    LauncherButton(
                        "删除所有实例数据",
                        systemImage: "trash",
                        variant: .danger,
                        size: .small,
                        isDisabled: dshProcess.isRunning || dshProcess.isBusy
                    ) {
                        confirmDeleteAllData()
                    }
                    .fixedSize()
                }
            }
            .padding(.top, LauncherSpace.sm)
        }
    }

    /// 删除所有实例数据前确认（~/.dsh 的登录凭据不动）。
    private func confirmDeleteAllData() {
        if dshProcess.isRunning || dshProcess.isBusy {
            router.showToast("DSH Web UI 正在运行，请先在启动页停止后再删除数据", tone: .warning)
            return
        }
        let paths = versions.paths
        let targets = DSHDataDeletion.targets(paths: paths)
        let titles = targets.map(\.title).joined(separator: " / ")
        let exists = targets.contains { target in
            FileManager.default.fileExists(atPath: target.path)
        }
        guard exists else {
            router.showToast("没有可删除的实例数据", tone: .info)
            return
        }
        let instanceText = DSHFormatting.instanceCountText(versions.installed)
        router.showDialog(
            LauncherDialogRequest(
                title: "删除所有 DSH 实例数据？",
                message: "将真实删除全部 \(instanceText) 的数据：\(titles)\n路径：\(paths.root.path)\n实例目录、每个实例的 DSH_HOME（插件 / 会话）、日志与缓存都会丢失，且无法恢复。\n不会删除 ~/.dsh 的登录凭据（API Key / 账号）。",
                confirmTitle: "删除所有实例数据",
                isDestructive: true,
                onConfirm: {
                    let report = DSHDataDeletion.deleteAll(paths: paths)
                    versions.refreshInstalled()
                    versions.settings.dshSelectedInstanceID = ""
                    directoryRows = []
                    Task { @MainActor in
                        await reloadDirectories()
                    }
                    if report.failures.isEmpty {
                        router.showToast(report.summary)
                    } else {
                        router.showToast(report.summary, tone: .danger)
                    }
                }
            )
        )
    }

    // MARK: - 保存条

    /// 保存条：DSH 设置直接写 `LauncherSettings`（自动持久化），这里显示真实写入时间。
    private var saveBar: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            HStack(spacing: LauncherSpace.md) {
                LauncherButton("打开数据目录", systemImage: "folder", variant: .secondary) {
                    openDirectory(versions.paths.root.path, title: "DSH 数据目录")
                }
                .fixedSize()
                LauncherButton("进程状态", systemImage: "bolt.horizontal.circle", variant: .secondary) {
                    router.go(.more, moreSection: "process")
                }
                .fixedSize()
                Spacer(minLength: LauncherSpace.md)
                HStack(spacing: LauncherSpace.xs) {
                    LauncherStatusDot(tone: versions.settings.lastSavedAt == nil ? .neutral : .success)
                    Text(saveStateText)
                        .textStyle(.monoSmall, tone: versions.settings.lastSavedAt == nil ? .tertiary : .success)
                        .lineLimit(1)
                }
            }
        }
    }

    /// 保存条状态文案。
    private var saveStateText: String {
        guard let lastSavedAt = versions.settings.lastSavedAt else {
            return "本次运行尚未写入设置"
        }
        return "已保存于 \(DSHFormatting.time(lastSavedAt))"
    }
}
