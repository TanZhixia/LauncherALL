import AppKit
import SwiftUI

// MARK: - 社区资源浏览面板

/// 下载页「社区资源」右栏：Modrinth 真实搜索 + 项目详情 + 真实安装。
/// 安装动作交给 `DownloadInstallCenter`，进度全部来自真实下载。
public struct DownloadCommunityPane: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(LauncherRouter.self) private var router
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    private let category: ModrinthProjectType
    /// 左侧搜索框内容（与版本搜索共用）。
    private let searchText: String
    /// 可选的 MC 版本过滤项（来自 Mojang 清单里的正式版）。
    private let versionOptions: [LauncherSegment<String>]
    @Binding private var gameVersion: String
    @Binding private var selectedInstanceID: String?
    private let installCenter: DownloadInstallCenter
    /// 导入本地整合包（由页面弹出系统文件选择器）。
    private let onImportModpack: () -> Void

    @State private var client = ModrinthClient()
    @State private var hits: [ModrinthSearchHit] = []
    @State private var totalHits = 0
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var selectedProjectID: String?
    @State private var detailVersions: [String: ModrinthVersion] = [:]
    @State private var detailLoading = false
    @State private var detailError: String?
    @State private var sortIndex = "relevance"
    @State private var reloadToken = 0

    /// 每页结果数（最小窗口下一屏能看全）。
    private let pageSize = 20

    public init(
        category: ModrinthProjectType,
        searchText: String,
        versionOptions: [LauncherSegment<String>],
        gameVersion: Binding<String>,
        selectedInstanceID: Binding<String?>,
        installCenter: DownloadInstallCenter,
        onImportModpack: @escaping () -> Void
    ) {
        self.category = category
        self.searchText = searchText
        self.versionOptions = versionOptions
        self._gameVersion = gameVersion
        self._selectedInstanceID = selectedInstanceID
        self.installCenter = installCenter
        self.onImportModpack = onImportModpack
    }

    public var body: some View {
        LauncherPanelHeader(
            category.title,
            subtitle: "Modrinth 公开接口 · \(filterDescription)"
        ) {
            headerActions
        }

        content
            .task(id: searchKey) {
                await runSearch()
            }
    }

    // MARK: - 头部

    private var headerActions: some View {
        HStack(spacing: LauncherSpace.xs) {
            if category == .modpack {
                LauncherButton(
                    "导入整合包",
                    systemImage: "shippingbox",
                    variant: .secondary,
                    size: .small
                ) {
                    onImportModpack()
                }
                .launcherTooltip("选择本地的 .mrpack / .zip 整合包，走与在线安装相同的流程")
            }

            LauncherDropdown(
                options: versionOptions,
                selection: $gameVersion,
                placeholder: gameVersion.isEmpty ? "最新正式版" : "选择 MC 版本"
            )
            .frame(width: 168)

            LauncherIconMenu(
                groups: sortGroups,
                systemImage: "arrow.up.arrow.down",
                accessibilityLabel: "排序方式"
            )
            LauncherIconButton(
                systemImage: "arrow.clockwise",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "重新搜索",
                isDisabled: isLoading || isLoadingMore
            ) {
                reload()
            }
            .launcherTooltip(
                isLoading || isLoadingMore
                    ? "正在请求 Modrinth，稍候可重新搜索"
                    : "按当前关键词重新搜索 Modrinth"
            )
        }
    }

    private var filterDescription: String {
        let version = gameVersion.isEmpty ? "最新正式版" : gameVersion
        return "按 MC \(version) 过滤"
    }

    private var sortGroups: [LauncherMenuGroup] {
        let options: [(id: String, title: String)] = [
            ("relevance", "按相关度"),
            ("downloads", "按下载量"),
            ("updated", "按更新时间")
        ]
        return [
            LauncherMenuGroup(items: options.map { option in
                LauncherMenuItem(
                    option.title,
                    systemImage: sortIndex == option.id ? "checkmark" : "arrow.up.arrow.down",
                    action: {
                        sortIndex = option.id
                        reload()
                    }
                )
            })
        ]
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if let errorMessage, hits.isEmpty {
            LauncherBanner(
                title: "搜索失败",
                message: errorMessage,
                tone: .danger,
                actionTitle: "重试",
                onAction: reload
            )
        }

        if !snapshotMode && isLoading && hits.isEmpty {
            HStack(alignment: .top, spacing: LauncherSpace.md) {
                resultsColumn(skeletonRows)
                detailCard
                    .frame(width: 320)
            }
        } else if hits.isEmpty {
            LauncherCard(level: .regular, padding: LauncherSpace.lg) {
                LauncherEmptyState(
                    systemImage: category.systemImage,
                    title: isEmptyQuery ? "搜索 Modrinth \(category.title)" : "没有匹配的\(category.title)",
                    message: isEmptyQuery
                        ? "输入关键词（左侧搜索框），按 MC \(gameVersion.isEmpty ? "最新正式版" : gameVersion) 实时过滤。"
                        : "换个关键词，或在右上角切换 MC 版本后重试。",
                    actionTitle: "重新搜索",
                    onAction: reload
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(alignment: .top, spacing: LauncherSpace.md) {
                resultsColumn(resultRows)
                detailCard
                    .frame(minWidth: 300, maxWidth: .infinity)
            }
        }

    }

    private var isEmptyQuery: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 结果列表列：固定高度滚动区 + 结果计数 / 加载更多。
    private func resultsColumn(_ rows: some View) -> some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            if snapshotMode {
                // 离屏渲染无法绘制 ScrollView 内容，截图时退回静态堆叠
                VStack(spacing: LauncherSpace.xxs) {
                    rows
                }
                .frame(height: LauncherControl.large * 8 + LauncherSpace.xxs * 7, alignment: .top)
                .clipped()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: LauncherSpace.xxs) {
                        rows
                    }
                }
                .frame(height: LauncherControl.large * 8 + LauncherSpace.xxs * 7)
            }

            HStack(spacing: LauncherSpace.sm) {
                Text(hits.isEmpty ? "—" : "共 \(totalHits) 个结果 · 已加载 \(hits.count) 个")
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
                Spacer(minLength: LauncherSpace.sm)
                if hasMore {
                    LauncherButton(
                        "加载更多",
                        systemImage: "arrow.down.circle",
                        variant: .secondary,
                        size: .small,
                        isLoading: isLoadingMore
                    ) {
                        loadMore()
                    }
                }
            }
        }
        .frame(width: 408)
    }

    private var hasMore: Bool {
        hits.count < totalHits
    }

    @ViewBuilder
    private var resultRows: some View {
        ForEach(hits) { hit in
            resultRow(hit)
        }
    }

    private var skeletonRows: some View {
        ForEach(0..<5, id: \.self) { _ in
            LauncherSkeleton(height: LauncherControl.large, cornerRadius: LauncherRadius.md)
        }
    }

    private func resultRow(_ hit: ModrinthSearchHit) -> some View {
        let job = installCenter.activeJob(for: hit.projectID)
        return LauncherListRow(
            title: hit.title,
            subtitle: "\(hit.authorText) · \(hit.downloadsText) 次下载",
            systemImage: category.systemImage,
            badge: job == nil ? nil : "安装中",
            accessory: AnyView(
                HStack(spacing: LauncherSpace.xs) {
                    if job == nil {
                        Image(systemName: "chevron.right")
                            .textStyle(.micro, tone: .tertiary)
                    }
                }
            ),
            isSelected: hit.projectID == selectedProjectID,
            action: {
                withAnimation(LauncherMotion.spring) {
                    selectedProjectID = hit.projectID
                }
            }
        )
    }

    // MARK: - 详情

    private var selectedHit: ModrinthSearchHit? {
        hits.first { $0.projectID == selectedProjectID }
    }

    private var detailKey: String {
        "\(selectedProjectID ?? "none")|\(gameVersion)"
    }

    private var selectedVersion: ModrinthVersion? {
        guard let projectID = selectedProjectID else { return nil }
        return detailVersions["\(projectID)|\(gameVersion)"]
    }

    @ViewBuilder
    private var detailCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            if let hit = selectedHit {
                VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                    detailHeader(hit)
                    detailStats(hit)
                    Text(hit.summary)
                        .textStyle(.micro, tone: .secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    LauncherDivider()
                    installSection(hit)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if isLoading {
                VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                    LauncherSkeleton(height: 60, cornerRadius: LauncherRadius.md)
                    LauncherSkeleton(height: 14)
                    LauncherSkeleton(height: 14)
                }
            } else {
                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    Text("从左侧选择一个\(category.title)")
                        .textStyle(.bodyStrong)
                    Text("这里会显示作者、下载量、最新版本与文件大小，并可直接安装到实例。")
                        .textStyle(.micro, tone: .tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detailHeader(_ hit: ModrinthSearchHit) -> some View {
        HStack(alignment: .top, spacing: LauncherSpace.md) {
            LauncherBlockArt(
                seed: hit.projectID,
                cornerRadius: LauncherRadius.md,
                label: category.title
            )
            .frame(width: 84, height: 60)

            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text(hit.title)
                    .textStyle(.bodyStrong)
                    .lineLimit(2)
                Text(hit.authorText)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
                HStack(spacing: LauncherSpace.xxs) {
                    LauncherBadge(category.title, tone: .neutral)
                    if !hit.versions.isEmpty {
                        LauncherBadge("\(hit.versions.count) 个 MC 版本", tone: .info)
                    }
                }
            }
            Spacer(minLength: 0)
            LauncherIconButton(
                systemImage: "safari",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "在浏览器打开 Modrinth 项目页"
            ) {
                openProjectPage(hit)
            }
        }
    }

    private func detailStats(_ hit: ModrinthSearchHit) -> some View {
        HStack(spacing: LauncherSpace.lg) {
            LauncherInlineStat("下载量", value: hit.downloadsText)
            LauncherInlineStat("关注", value: ModrinthFormat.downloads(hit.follows))
            LauncherInlineStat("更新时间", value: hit.updatedText, isMono: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 安装区

    @ViewBuilder
    private func installSection(_ hit: ModrinthSearchHit) -> some View {
        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
            if let job = installCenter.activeJob(for: hit.projectID) {
                LauncherProgressBar(value: job.fraction, label: "\(job.phase) · \(job.title)")
                HStack(spacing: LauncherSpace.sm) {
                    LauncherMonoText(job.detail, tone: .tertiary, size: 10)
                        .lineLimit(1)
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherButton(
                        "取消",
                        systemImage: "xmark",
                        variant: .ghost,
                        size: .small
                    ) {
                        installCenter.cancel(jobID: job.id)
                    }
                }
            } else if detailLoading && !snapshotMode {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherSpinner(size: 14)
                    Text("正在获取 MC \(filterDescriptionVersion) 的可用版本…")
                        .textStyle(.micro, tone: .secondary)
                        .lineLimit(1)
                }
            } else if let detailError {
                LauncherBanner(
                    title: "无法安装",
                    message: detailError,
                    tone: .warning,
                    actionTitle: "重试",
                    onAction: retrySelectedVersion
                )
            } else if let version = selectedVersion {
                versionStats(version)
                instanceSection
                loaderCompatibilityHint(for: version)
                installControls(hit: hit, version: version)
            } else {
                Text("暂未获取到可用版本，稍后重试。")
                    .textStyle(.micro, tone: .tertiary)
            }
        }
        .task(id: detailKey) {
            await loadSelectedVersionAsync()
        }
    }

    private var filterDescriptionVersion: String {
        gameVersion.isEmpty ? "最新正式版" : gameVersion
    }

    private func versionStats(_ version: ModrinthVersion) -> some View {
        HStack(spacing: LauncherSpace.lg) {
            LauncherInlineStat("版本", value: version.versionNumber)
            LauncherInlineStat(
                "文件大小",
                value: version.primaryFile?.sizeText ?? "—",
                isMono: true
            )
            LauncherInlineStat(
                "加载器",
                value: version.loaders.first ?? "—"
            )
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var instanceSection: some View {
        if category == .modpack {
            HStack(spacing: LauncherSpace.xs) {
                LauncherHintIcon("安装时会先确保基础版本已安装，再写入加载器与整合包文件。")
                Text(category.destinationHint)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
            }
        } else if engine.installedVersions.isEmpty {
            HStack(spacing: LauncherSpace.xs) {
                LauncherHintIcon("需要先安装一个 Minecraft 版本才能放资源文件。")
                Text("还没有已安装实例，请先在左侧安装一个版本")
                    .textStyle(.micro, tone: .warning)
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: LauncherSpace.sm) {
                Text("目标实例")
                    .textStyle(.caption, tone: .secondary)
                    .lineLimit(1)
                Spacer(minLength: LauncherSpace.sm)
                LauncherDropdown(
                    options: instanceOptions,
                    selection: instanceBinding,
                    placeholder: "选择实例"
                )
                .frame(width: 168)
            }
        }
    }

    /// 目标实例加载器与资源声明不匹配时的提示（资源包 / 数据包等不受影响）。
    @ViewBuilder
    private func loaderCompatibilityHint(for version: ModrinthVersion) -> some View {
        if let hint = loaderWarning(for: version) {
            HStack(alignment: .top, spacing: LauncherSpace.xs) {
                LauncherHintIcon(hint)
                Text(hint)
                    .textStyle(.micro, tone: .warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 社区资源与目标实例加载器不兼容的说明（仅模组需要判断）。
    private func loaderWarning(for version: ModrinthVersion) -> String? {
        guard category == .mod, let instanceID = resolvedInstanceID else { return nil }
        let kind = ModrinthLoaderDetector.kind(forInstance: instanceID, installation: engine.installation)
        return ModrinthLoaderDetector.incompatibilityHint(versionLoaders: version.loaders, instance: kind)
    }

    private func installControls(hit: ModrinthSearchHit, version: ModrinthVersion) -> some View {
        let isDisabled = category != .modpack && engine.installedVersions.isEmpty
        let warning = loaderWarning(for: version)
        let installTooltip: String
        if isDisabled {
            installTooltip = "请先安装一个 Minecraft 版本"
        } else if let warning {
            installTooltip = warning
        } else {
            installTooltip = "真实下载到实例目录"
        }
        return VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            HStack(spacing: LauncherSpace.sm) {
                LauncherButton(
                    category == .modpack ? "安装整合包" : "安装到实例",
                    systemImage: "arrow.down.circle",
                    variant: .primary,
                    size: .medium,
                    isDisabled: isDisabled
                ) {
                    install(hit: hit, version: version)
                }
                .launcherTooltip(installTooltip)
                if let file = version.primaryFile {
                    LauncherButton(
                        "复制下载地址",
                        systemImage: "doc.on.doc",
                        variant: .ghost,
                        size: .small
                    ) {
                        copyDownloadURL(file)
                    }
                    .launcherTooltip("复制主文件下载地址到剪贴板")
                } else {
                    HStack(spacing: LauncherSpace.xs) {
                        LauncherHintIcon("该版本没有可下载的主文件")
                        Text("该版本没有可下载的主文件")
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if category != .modpack {
                HStack(spacing: LauncherSpace.xs) {
                    LauncherHintIcon(category.destinationHint)
                    Text(category.destinationHint)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var instanceOptions: [LauncherSegment<String>] {
        engine.installedVersions.map { version in
            LauncherSegment(
                id: version.id,
                title: version.id,
                systemImage: installedVersionIcon(version)
            )
        }
    }

    /// 加载器 / 原版图标区分（实例下拉里一眼看出类型）。
    private func installedVersionIcon(_ version: InstalledVersion) -> String {
        let lower = version.id.lowercased()
        if lower.contains("fabric") { return "square.stack.3d.up.fill" }
        if lower.contains("quilt") { return "square.stack.3d.up" }
        return "cube.fill"
    }

    private var instanceBinding: Binding<String> {
        Binding(
            get: {
                if let selectedInstanceID,
                   engine.installedVersions.contains(where: { $0.id == selectedInstanceID }) {
                    return selectedInstanceID
                }
                return engine.installedVersions.first?.id ?? ""
            },
            set: { selectedInstanceID = $0 }
        )
    }

    private var resolvedInstanceID: String? {
        if let selectedInstanceID,
           engine.installedVersions.contains(where: { $0.id == selectedInstanceID }) {
            return selectedInstanceID
        }
        return engine.installedVersions.first?.id
    }

    // MARK: - 行为

    private var searchKey: String {
        "\(category.rawValue)|\(gameVersion)|\(searchText)|\(sortIndex)|\(reloadToken)"
    }

    /// 触发一次新的搜索（带输入防抖，减少无谓请求）。
    private func reload() {
        reloadToken &+= 1
    }

    private func loadMore() {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        Task { await fetch(offset: hits.count, append: true) }
    }

    /// 搜索当前分类（真实网络请求）。
    private func runSearch() async {
        isLoading = true
        errorMessage = nil
        // 输入防抖：停顿 300ms 再请求（只是减少请求次数，不是伪造进度）
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        await fetch(offset: 0, append: false)
    }

    private func fetch(offset: Int, append: Bool) async {
        do {
            let page = try await client.search(
                projectType: category,
                gameVersion: gameVersion.isEmpty ? nil : gameVersion,
                query: searchText,
                limit: pageSize,
                offset: offset,
                index: sortIndex
            )
            guard !Task.isCancelled else { return }
            if append {
                hits.append(contentsOf: page.hits)
            } else {
                hits = page.hits
                if selectedProjectID == nil || !hits.contains(where: { $0.projectID == selectedProjectID }) {
                    selectedProjectID = hits.first?.projectID
                }
            }
            totalHits = page.totalHits
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            if !append {
                hits = []
                selectedProjectID = nil
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
        isLoadingMore = false
    }

    /// 拉取选中项目在当前 MC 版本下的可用版本。
    private func loadSelectedVersionAsync() async {
        guard let projectID = selectedProjectID else { return }
        let key = "\(projectID)|\(gameVersion)"
        if detailVersions[key] != nil { return }
        detailLoading = true
        detailError = nil
        do {
            let versions = try await client.versions(
                projectID: projectID,
                gameVersion: gameVersion.isEmpty ? nil : gameVersion
            )
            guard !Task.isCancelled else { return }
            guard let version = versions.first(where: { $0.primaryFile != nil }) else {
                detailError = gameVersion.isEmpty
                    ? "该项目没有可下载的文件"
                    : "该项目没有适配 MC \(gameVersion) 的版本，换一个 MC 版本再试。"
                detailLoading = false
                return
            }
            detailVersions[key] = version
        } catch {
            guard !Task.isCancelled else { return }
            detailError = error.localizedDescription
        }
        detailLoading = false
    }

    /// 重新拉取选中项目的版本（失败后重试）。
    private func retrySelectedVersion() {
        guard let projectID = selectedProjectID else { return }
        detailVersions.removeValue(forKey: "\(projectID)|\(gameVersion)")
        detailError = nil
        Task { await loadSelectedVersionAsync() }
    }

    private func install(hit: ModrinthSearchHit, version: ModrinthVersion) {
        if category == .modpack {
            installCenter.installModpack(
                projectID: hit.projectID,
                projectTitle: hit.title,
                version: version,
                mcVersion: gameVersion.isEmpty ? nil : gameVersion,
                settings: engine.settings,
                engine: engine
            )
            return
        }
        guard let instanceID = resolvedInstanceID else {
            router.showToast("请先安装一个 Minecraft 实例", tone: .warning)
            return
        }
        guard let file = version.primaryFile else {
            router.showToast("该版本没有可下载文件", tone: .warning)
            return
        }
        installCenter.installResource(
            projectID: hit.projectID,
            projectTitle: hit.title,
            file: file,
            type: category,
            instanceID: instanceID,
            settings: engine.settings
        )
    }

    private func openProjectPage(_ hit: ModrinthSearchHit) {
        guard let url = URL(string: "https://modrinth.com/\(category.rawValue)/\(hit.slug)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyDownloadURL(_ file: ModrinthVersion.File) {
        InstanceActions.copy(file.url.absoluteString)
        router.showToast("已复制下载地址：\(file.filename)", tone: .info)
    }
}

// MARK: - 安装任务卡

/// 社区资源安装任务卡：进度来自真实下载 / 解压，可取消、可清空已结束任务。
public struct DownloadInstallJobsCard: View {
    @Environment(\.launcherTheme) private var theme

    private let center: DownloadInstallCenter

    public init(center: DownloadInstallCenter) {
        self.center = center
    }

    public var body: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "安装任务",
                    subtitle: center.hasRunningJobs
                        ? "\(center.runningCount) 个进行中 · 进度来自真实下载"
                        : "全部任务已结束",
                    accessory: AnyView(
                        HStack(spacing: LauncherSpace.xs) {
                            if center.hasRunningJobs {
                                LauncherStatusDot(tone: .accent, isPulsing: true)
                            }
                            LauncherButton(
                                "清空已结束",
                                variant: .ghost,
                                size: .small,
                                isDisabled: center.jobs.allSatisfy { $0.state.isActive }
                            ) {
                                center.clearFinished()
                            }
                        }
                    )
                )

                ForEach(center.recentJobs) { job in
                    jobRow(job)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func jobRow(_ job: DownloadInstallJob) -> some View {
        HStack(alignment: .center, spacing: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                HStack(spacing: LauncherSpace.xs) {
                    Text(job.title)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    LauncherBadge(job.state.title, tone: tone(for: job.state))
                    Spacer(minLength: 0)
                }
                Text(job.subtitle)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
                if job.state.isActive {
                    LauncherProgressBar(value: job.fraction, label: job.phase, height: 4)
                    if !job.detail.isEmpty {
                        LauncherMonoText(job.detail, tone: .tertiary, size: 10)
                            .lineLimit(1)
                    }
                } else if case .failed(let message) = job.state {
                    Text(message)
                        .textStyle(.micro, tone: .danger)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if job.state.isActive {
                LauncherButton(
                    "取消",
                    systemImage: "xmark",
                    variant: .ghost,
                    size: .small
                ) {
                    center.cancel(jobID: job.id)
                }
            }
        }
    }

    private func tone(for state: DownloadInstallJob.State) -> LauncherBadgeTone {
        switch state {
        case .running: return .accent
        case .finished: return .success
        case .cancelled: return .neutral
        case .failed: return .danger
        }
    }
}
