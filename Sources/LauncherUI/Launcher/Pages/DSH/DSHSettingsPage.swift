import SwiftUI
import AppKit

// MARK: - DSH 设置页

/// DSH 启动器的设置页：左侧分类 + 右侧卡片，全部读写真实设置 / 真实文件 / 真实网络。
///
/// 分类：启动（端口 / 自动打开浏览器 / 默认版本）、下载与插件（npm 源 / 插件加载源 / 缓存）、
/// 环境与目录（Node / pnpm / npm 检测与数据目录）、关于（版本与危险区）。
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
        .task { await detectEnvironmentIfNeeded() }
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
            return versions.installed.isEmpty ? nil : "\(versions.installed.count)"
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
            return versions.installed.isEmpty ? "未安装版本" : "\(versions.installed.count) 个版本"
        case .about:
            return versions.settings.dshSelectedVersion.isEmpty ? "未选择版本" : nil
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
                "默认版本",
                subtitle: selectedVersionSubtitle,
                tooltip: "启动 DSH 启动器时默认使用这个版本",
                showsDivider: false
            ) {
                if versions.installed.isEmpty {
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherBadge("未安装", tone: .warning)
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
                        versions.selectedInstalledVersion?.version ?? "未选择",
                        systemImage: "chevron.down",
                        variant: .secondary,
                        size: .small,
                        groups: versionMenuGroups
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

    /// 已选版本的说明。
    private var selectedVersionSubtitle: String {
        guard let selected = versions.selectedInstalledVersion else {
            return versions.installed.isEmpty
                ? "还没有安装 DSH 版本，先去「下载」页安装"
                : "选择一个已安装版本作为默认启动版本"
        }
        let installedAt = "安装于 \(DSHFormatting.dateTime(selected.installedAt))"
        let size = selected.sizeBytes.map { DSHFormatting.byteCount($0) } ?? "大小未知"
        return "\(selected.version) · \(size) · \(installedAt)"
    }

    /// 版本菜单：已安装版本列表（当前项带勾）。
    private var versionMenuGroups: [LauncherMenuGroup] {
        [LauncherMenuGroup(title: "已安装版本", items: versions.installed.map { version in
            LauncherMenuItem(
                version.version,
                id: version.version,
                systemImage: versions.settings.dshSelectedVersion == version.version
                    ? "checkmark"
                    : "shippingbox",
                detail: version.sizeBytes.map { DSHFormatting.byteCount($0) } ?? "大小未知"
            ) {
                versions.select(version.version)
                router.showToast("默认版本已设为 \(version.version)")
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

            LauncherExpander(
                "运行时详情",
                subtitle: "Node / pnpm / npm 的真实路径与包管理器选择",
                systemImage: "terminal"
            ) {
                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    Text(environmentDetailText)
                        .textStyle(.micro, tone: .tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(environment?.rows ?? []) { row in
                        DSHInfoRow(title: row.title, value: row.value, isMissing: row.isMissing)
                    }
                }
                .padding(.top, LauncherSpace.xs)
            }

            LauncherDivider()

            ForEach(Array(environmentDirectories.enumerated()), id: \.offset) { index, entry in
                LauncherSettingRow(
                    entry.title,
                    subtitle: entry.detail,
                    showsDivider: index < environmentDirectories.count - 1
                ) {
                    HStack(spacing: LauncherSpace.sm) {
                        DSHPathText(text: entry.path, tone: .tertiary, maxWidth: 300)
                        LauncherIconButton(
                            systemImage: "folder",
                            variant: .ghost,
                            size: .small,
                            accessibilityLabel: "打开\(entry.title)",
                            action: { openDirectory(entry.path, title: entry.title) }
                        )
                    }
                }
            }

            LauncherSettingRow(
                "已安装版本与占用",
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
                        router.showToast("已重新扫描已安装的 DSH 版本")
                    }
                    .fixedSize()
                }
            }
        }
    }

    /// 运行时环境说明。
    private var environmentSubtitle: String {
        if let environment {
            return environment.summary
        }
        return snapshotMode ? "快照模式：未检测运行时" : "尚未检测运行时，点「重新检测」"
    }

    /// 运行时详情说明。
    private var environmentDetailText: String {
        if environment != nil {
            return "检测完成 · 启动 DSH 时使用「实际使用」那一行的包管理器"
        }
        return snapshotMode
            ? "快照模式不启动子进程，运行时路径未检测"
            : "尚未检测；点页头或本行的「重新检测」"
    }

    /// 设置页展示的数据目录。
    private var environmentDirectories: [(title: String, detail: String, path: String)] {
        let paths = versions.paths
        return [
            ("DSH 根目录", "所有 DSH 数据文件的根目录", paths.root.path),
            ("版本目录", "每个版本的 node_modules（版本之间互相隔离）", paths.versionsDirectory.path),
            (
                "用户数据目录（DSH_HOME）",
                "所有 DSH 版本共享；自动复用 ~/.dsh 的登录凭据（API Key / 账号），插件与会话存放在这里",
                paths.homeRoot.path
            ),
            ("日志目录", "DSH Web UI 进程日志", paths.logsDirectory.path)
        ]
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
                subtitle: "使用官方 @deepseek-ai/dsh，通过 npm 安装到本地并隔离运行"
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherBadge(
                        versions.settings.dshSelectedVersion.isEmpty
                            ? "未选择版本"
                            : versions.settings.dshSelectedVersion,
                        tone: versions.settings.dshSelectedVersion.isEmpty ? .warning : .neutral
                    )
                    LauncherBadge(DSHFormatting.installedSummary(versions.installed), tone: .neutral)
                }
            }

            LauncherSettingRow(
                "DSH 数据目录",
                subtitle: "启动器的 versions / logs / cache 与共享 DSH_HOME 都保存在这里；登录凭据自动复用 ~/.dsh"
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

            // 危险区：删除所有 DSH 数据（明确路径 + 二次确认）
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherBanner(
                    title: "删除启动器的 DSH 数据",
                    message: "只删除启动器自己的 versions / logs / cache 与历史遗留的 homes 目录：已安装 DSH 版本与日志会丢失。不会删除启动器 home（插件 / 会话）里的用户数据，也不会删除 ~/.dsh 的登录凭据（API Key / 账号）。",
                    tone: .danger
                )
                HStack(spacing: LauncherSpace.sm) {
                    Spacer(minLength: 0)
                    LauncherButton(
                        "删除启动器 DSH 数据",
                        systemImage: "trash",
                        variant: .danger,
                        size: .small
                    ) {
                        confirmDeleteAllData()
                    }
                    .fixedSize()
                }
            }
            .padding(.top, LauncherSpace.sm)
        }
    }

    /// 删除启动器自己的 DSH 数据前确认（共享 DSH_HOME 不动）。
    private func confirmDeleteAllData() {
        if dshProcess.isRunning || dshProcess.isBusy {
            router.showToast("DSH Web UI 正在运行，请先在启动页停止后再清理数据", tone: .warning)
            return
        }
        let paths = versions.paths
        let targets = DSHDataDeletion.targets(paths: paths)
        let titles = targets.map(\.title).joined(separator: " / ")
        let exists = targets.contains { target in
            FileManager.default.fileExists(atPath: target.path)
        }
        guard exists else {
            router.showToast("没有可删除的启动器 DSH 数据", tone: .info)
            return
        }
        router.showDialog(
            LauncherDialogRequest(
                title: "删除启动器的 DSH 数据？",
                message: "将真实删除：\(titles)\n路径：\(paths.root.path)\n已安装 DSH 版本与日志会丢失，且无法恢复。\n不会删除启动器 home（\(paths.homeRoot.path) 里的插件 / 会话），也不会删除 ~/.dsh 的登录凭据。",
                confirmTitle: "删除启动器数据",
                isDestructive: true,
                onConfirm: {
                    let report = DSHDataDeletion.deleteAll(paths: paths)
                    versions.refreshInstalled()
                    versions.settings.dshSelectedVersion = ""
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
