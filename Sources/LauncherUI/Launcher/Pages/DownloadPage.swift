import AppKit
import Foundation
import SwiftUI

/// 下载页（PCL 式布局）：左侧版本 / 社区资源分类，右侧版本详情、真实安装选项与队列、
/// 磁盘占用、下载源，以及 Modrinth 社区资源浏览与整合包安装。
///
/// 页面里没有演示数据：安装走 `LauncherEngine` 的真实队列，社区资源走 Modrinth 公开接口，
/// 整合包走真实的 `.mrpack` 解析 + 文件下载 + overrides 解压。
public struct DownloadPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(LauncherRouter.self) private var router
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    // MARK: 左面板

    @State private var category: DownloadCategory = .release
    @State private var searchText = ""
    @State private var sortMode: VersionSort = .newest
    @State private var selectedVersionID: String?

    // MARK: 版本清单

    /// 真实拉取到的版本清单（磁盘缓存首帧直出）；快照冷缓存的确定性兜底见 `manifest`。
    @State private var loadedManifest: VersionManifest? = DownloadPage.launchManifestCache
    @State private var isLoadingManifest = DownloadPage.launchManifestCache == nil
    @State private var manifestError: String?

    // MARK: 安装选项（真实传给安装器）

    /// 是否下载全部资源文件（assets/objects）。
    @State private var installAssets = true
    /// 是否重新校验已存在文件（SHA1）。
    @State private var verifyExisting = false
    /// 最近一次在本页触发的安装（失败提示用）。
    @State private var lastInstallVersionID: String?

    // MARK: 版本详情（真实异步拉取版本 JSON）

    @State private var versionDetails: [String: VersionDetail] = [:]
    @State private var detailLoadingIDs: Set<String> = []
    @State private var detailErrors: [String: String] = [:]

    // MARK: 磁盘

    @State private var diskUsage: DownloadDiskUsage?
    @State private var isRefreshingDisk = false
    @State private var isClearingCache = false

    // MARK: 社区资源

    /// 社区资源搜索使用的 MC 版本过滤（默认最新正式版）。
    @State private var communityGameVersion = ""
    /// 社区资源安装的目标实例。
    @State private var selectedInstanceID: String?
    /// 社区资源安装任务中心（真实下载 / 解压）。
    @State private var installCenter = DownloadInstallCenter()

    /// 首帧快速展示：读取与 `MojangManifestService` 相同位置的清单缓存，随后仍异步刷新。
    private static let launchManifestCache: VersionManifest? = readCachedManifest()

    /// 当前生效的版本清单：
    /// - 交互模式：磁盘缓存 / 网络拉取结果；
    /// - 离屏快照 + 冷缓存：`ImageRenderer` 不执行 `.task`，用本机已安装版本构造确定性清单，
    ///   避免导出图里出现永不结束的加载态（没有已安装版本时渲染静态说明）。
    private var manifest: VersionManifest? {
        if let loadedManifest { return loadedManifest }
        guard snapshotMode else { return nil }
        return Self.makeSnapshotManifest(from: engine.installedVersions)
    }

    /// 用本机已安装版本构造快照兜底清单（仅离屏快照使用，不参与真实安装 / 启动流程）。
    private static func makeSnapshotManifest(from installed: [InstalledVersion]) -> VersionManifest? {
        guard !installed.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        let versions = installed.map { version in
            VersionSummary(
                id: version.id,
                type: version.versionType,
                url: "",
                time: formatter.string(from: version.lastModified),
                releaseTime: formatter.string(from: version.lastModified)
            )
        }
        let latestID = versions.first?.id ?? ""
        return VersionManifest(
            latest: VersionManifest.Latest(release: latestID, snapshot: latestID),
            versions: versions
        )
    }

    /// 左面板默认展示的版本行数，保证最小窗口下社区资源入口始终可见。
    private let defaultVisibleVersions = 5
    /// 交互模式下是否展开全部版本（左面板「显示全部」开关）。
    @State private var showsAllVersions = false
    /// 「自动清理旧版本」提示：记录已提示过的安装完成次数，保证每次安装完成只提示一次。
    @State private var hintedCleanupFinishedCount = 0

    public init() {}

    public var body: some View {
        LauncherPageLayout(sideWidth: 272) {
            sidePanel
        } main: {
            LauncherMainPanel {
                mainContent
                if !installCenter.jobs.isEmpty {
                    DownloadInstallJobsCard(center: installCenter)
                }
            }
        }
        .task {
            guard !snapshotMode else { return }
            installCenter.notify = { [router] message, tone in
                router.showToast(message, tone: tone)
            }
            if engine.installedVersions.isEmpty {
                await engine.refreshEnvironment()
            }
            await loadManifest()
            await refreshDiskUsage()
            consumePendingDownloadAction()
        }
        .onAppear { consumePendingDownloadAction() }
        .onChange(of: router.pendingDownloadAction) { _, _ in
            consumePendingDownloadAction()
        }
        .task(id: selectedVersion?.id) {
            if let versionID = selectedVersion?.id {
                await loadVersionDetail(for: versionID)
            }
        }
        .onChange(of: finishedInstallCount) { oldValue, newValue in
            // 安装完成后提示可清理的旧版本（每次安装完成只提示一次，避免每帧弹 toast）
            guard newValue > oldValue, newValue > hintedCleanupFinishedCount else { return }
            hintedCleanupFinishedCount = newValue
            hintCleanupIfNeeded()
        }
    }

    /// 已完成的安装任务数量（自动清理提示的触发信号）。
    private var finishedInstallCount: Int {
        engine.installQueue.filter { $0.state == .finished }.count
    }

    /// 「自动清理旧版本」开启时，安装完成后提示可清理的旧版本（与设置页开关文案对齐）。
    private func hintCleanupIfNeeded() {
        guard engine.settings.autoCleanOldVersions else { return }
        let unused = engine.unusedVersions(olderThanDays: 30)
        guard !unused.isEmpty else { return }
        router.showToast(
            "有 \(unused.count) 个 30 天未启动的版本可清理（设置 → 更新与语言）",
            tone: .info
        )
    }

    // MARK: - 左面板

    private var sidePanel: some View {
        LauncherSidePanel(
            title: "下载",
            count: manifest.map { "\($0.versions.count)" },
            width: 272,
            searchText: $searchText,
            searchPlaceholder: "搜索版本 / 社区资源",
            toolbar: AnyView(sideToolbar)
        ) {
            sideContent
        } footer: {
            sideFooter
        }
    }

    private var sideToolbar: some View {
        HStack(spacing: LauncherSpace.xxs) {
            LauncherIconMenu(
                groups: sortMenuGroups,
                systemImage: "arrow.up.arrow.down",
                accessibilityLabel: "排序方式"
            )
            LauncherIconButton(
                systemImage: "arrow.clockwise",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "刷新版本清单",
                isDisabled: isLoadingManifest && manifest == nil
            ) {
                refreshAll()
            }
            .launcherTooltip(
                isLoadingManifest && manifest == nil
                    ? "正在加载版本清单，完成后可刷新"
                    : "强制刷新版本清单与已安装列表"
            )
        }
    }

    @ViewBuilder
    private var sideContent: some View {
        if manifest == nil {
            manifestSidePlaceholder
        } else {
            LauncherSidePanelGroup("Minecraft", trailing: "\(minecraftCountText)")
            typeChips

            if category.isMinecraft {
                if displayedVersions.isEmpty {
                    Text("没有匹配的版本")
                        .textStyle(.micro, tone: .tertiary)
                        .padding(.horizontal, LauncherSpace.xs)
                        .padding(.vertical, LauncherSpace.sm)
                } else {
                    ForEach(displayedVersions) { version in
                        versionRow(version)
                    }
                    if typeVersions.count > displayedVersions.count {
                        Text("共 \(typeVersions.count) 个，当前显示前 \(displayedVersions.count) 个；可用搜索查找其他版本")
                            .textStyle(.micro, tone: .tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, LauncherSpace.xs)
                            .padding(.vertical, LauncherSpace.xxs)
                    }
                    if !snapshotMode && typeVersions.count > defaultVisibleVersions {
                        LauncherButton(
                            showsAllVersions ? "收起列表" : "显示全部 \(typeVersions.count) 个",
                            systemImage: showsAllVersions ? "chevron.up" : "chevron.down",
                            variant: .ghost,
                            size: .small,
                            isFullWidth: true
                        ) {
                            withAnimation(LauncherMotion.spring) {
                                showsAllVersions.toggle()
                            }
                        }
                        .padding(.horizontal, LauncherSpace.xxs)
                    }
                }
            }

            LauncherSidePanelGroup("社区资源", trailing: "6")
            communityGrid
        }
    }

    @ViewBuilder
    private var manifestSidePlaceholder: some View {
        if let manifestError {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                Text("版本清单加载失败")
                    .textStyle(.bodyStrong)
                Text(manifestError)
                    .textStyle(.micro, tone: .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                LauncherButton(
                    "重试",
                    systemImage: "arrow.clockwise",
                    variant: .secondary,
                    size: .small,
                    isFullWidth: true
                ) {
                    refreshManifest(forceRefresh: true)
                }
            }
            .padding(.horizontal, LauncherSpace.xs)
        } else if snapshotMode {
            // 离屏快照 + 冷缓存：给确定性说明，绝不出现骨架 / 转圈
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                Text("版本清单未缓存")
                    .textStyle(.bodyStrong)
                Text("离屏快照不会联网；启动启动器后会自动拉取并缓存 12 小时。")
                    .textStyle(.micro, tone: .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, LauncherSpace.xs)
        } else {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                ForEach(0..<3, id: \.self) { _ in
                    LauncherSkeleton(
                        height: LauncherControl.large,
                        cornerRadius: LauncherRadius.md
                    )
                }
            }
        }
    }

    private var typeChips: some View {
        HStack(spacing: LauncherSpace.xs) {
            ForEach(DownloadCategory.minecraftTypes) { type in
                LauncherChip(type.title, isSelected: category == type) {
                    selectCategory(type)
                }
            }
        }
        .padding(.horizontal, LauncherSpace.xxs)
    }

    private func versionRow(_ version: VersionSummary) -> some View {
        LauncherListRow(
            title: version.id,
            subtitle: releaseDate(version.releaseTime),
            systemImage: icon(for: version.type),
            badge: typeLabel(version.type),
            accessory: AnyView(
                HStack(spacing: LauncherSpace.xs) {
                    if installedIDs.contains(version.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .textStyle(.micro, tone: .success)
                            .accessibilityLabel("已安装")
                    }
                    if let item = engine.queueItem(for: version.id), item.state.isActive {
                        LauncherStatusDot(tone: .accent, isPulsing: true)
                    }
                    Image(systemName: "chevron.right")
                        .textStyle(.micro, tone: .tertiary)
                }
            ),
            isSelected: version.id == selectedVersion?.id,
            action: {
                withAnimation(LauncherMotion.spring) {
                    selectedVersionID = version.id
                }
            }
        )
        .launcherContextMenu(contextMenuGroups(for: version))
    }

    private var communityGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: LauncherSpace.xs),
                GridItem(.flexible(), spacing: LauncherSpace.xs)
            ],
            spacing: LauncherSpace.xs
        ) {
            ForEach(DownloadCategory.communityResources) { item in
                communityTile(item)
            }
        }
        .padding(.horizontal, LauncherSpace.xxs)
    }

    private func communityTile(_ item: DownloadCategory) -> some View {
        let isSelected = category == item
        return Button {
            selectCategory(item)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: LauncherSpace.xs) {
                    Image(systemName: item.systemImage)
                        .textStyle(.micro, tone: isSelected ? .accent : .secondary)
                    Text(item.title)
                        .textStyle(.caption, tone: isSelected ? .accent : .primary)
                        .lineLimit(1)
                }
                Text(item.tileHint)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, LauncherSpace.sm)
            .padding(.vertical, LauncherSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                    .fill(isSelected ? theme.colors.accentSoft : theme.colors.surfaceSubtle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.colors.accent.opacity(0.45) : theme.colors.stroke,
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous))
        }
        .buttonStyle(LauncherPressEffect(scale: 0.98))
        .launcherPointer()
        .accessibilityLabel(item.title)
    }

    private var sideFooter: some View {
        VStack(spacing: LauncherSpace.xs) {
            LauncherDivider()

            LauncherButton(
                "刷新列表",
                systemImage: "arrow.clockwise",
                variant: .secondary,
                size: .small,
                isLoading: isLoadingManifest && !snapshotMode,
                isFullWidth: true
            ) {
                refreshAll()
            }

            HStack(spacing: LauncherSpace.xs) {
                Text("已安装 \(engine.installedVersions.count) 个版本")
                    .textStyle(.micro, tone: .tertiary)
                Spacer(minLength: 0)
                if engine.installQueue.contains(where: { $0.state.isActive }) {
                    Text("队列 \(engine.installQueue.filter { $0.state.isActive }.count)")
                        .textStyle(.micro, tone: .accent)
                }
                LauncherMonoText(
                    "\(displayedVersions.count) / \(typeVersions.count)",
                    tone: .tertiary,
                    size: 10
                )
            }
        }
    }

    // MARK: - 右内容

    @ViewBuilder
    private var mainContent: some View {
        if manifest == nil {
            manifestPlaceholder
        } else if let projectType = category.projectType {
            communityContent(projectType)
        } else {
            versionContent
        }
    }

    @ViewBuilder
    private var manifestPlaceholder: some View {
        LauncherPanelHeader("下载 Minecraft", subtitle: "版本清单来自 Mojang 官方接口") {
            EmptyView()
        }
        if let manifestError {
            LauncherBanner(
                title: "无法获取版本清单",
                message: manifestError,
                tone: .danger,
                actionTitle: "重试",
                onAction: { refreshManifest(forceRefresh: true) }
            )
            Text("首次加载需要联网；加载成功后会在本地缓存 12 小时。")
                .textStyle(.micro, tone: .tertiary)
        } else if snapshotMode {
            // 离屏快照 + 冷缓存：静态说明，不出现 spinner / skeleton
            LauncherCard(level: .regular, padding: LauncherSpace.lg) {
                LauncherEmptyState(
                    systemImage: "wifi.slash",
                    title: "版本清单未缓存",
                    message: "离屏快照模式不会发起网络请求。启动启动器后会自动从 Mojang 拉取版本清单并缓存 12 小时。"
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: LauncherSpace.sm) {
                LauncherSpinner(size: 16)
                Text("正在获取 Mojang 版本清单…")
                    .textStyle(.micro, tone: .secondary)
            }
            LauncherSkeleton(height: 96, cornerRadius: LauncherRadius.lg)
            LauncherSkeleton(height: 96, cornerRadius: LauncherRadius.lg)
        }
    }

    // MARK: - 版本分区

    @ViewBuilder
    private var versionContent: some View {
        if let version = selectedVersion {
            LauncherPanelHeader(version.id, subtitle: versionSubtitle(version)) {
                LauncherIconMenu(
                    groups: moreMenuGroups(for: version),
                    accessibilityLabel: "更多版本操作"
                )
            }

            if let manifestError {
                LauncherBanner(
                    title: "清单刷新失败，正在使用本地缓存",
                    message: manifestError,
                    tone: .warning,
                    actionTitle: "重试",
                    onAction: { refreshManifest(forceRefresh: true) }
                )
            }

            versionInfoCard(version)
            installCard(version)
            if !engine.installQueue.isEmpty {
                installQueueCard
            }
            bottomCards
        } else {
            LauncherEmptyState(
                systemImage: "magnifyingglass",
                title: "没有匹配的版本",
                message: "换个搜索词，或者切换到其他分类看看。",
                actionTitle: "重置搜索",
                onAction: { searchText = "" }
            )
        }
    }

    private func versionSubtitle(_ version: VersionSummary) -> String {
        var parts = ["发布于 \(releaseDate(version.releaseTime))", typeLabel(version.type)]
        if let detail = displayVersionDetail(for: version),
           let java = detail.javaVersion {
            parts.append("Java \(java.majorVersion)+")
        }
        return parts.joined(separator: " · ")
    }

    private func versionInfoCard(_ version: VersionSummary) -> some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            HStack(alignment: .top, spacing: LauncherSpace.lg) {
                LauncherBlockArt(
                    seed: version.id,
                    cornerRadius: LauncherRadius.md,
                    label: typeLabel(version.type)
                )
                .frame(width: 108, height: 72)

                VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                    HStack(spacing: LauncherSpace.xs) {
                        Text(version.id)
                            .textStyle(.title)
                        LauncherBadge(typeLabel(version.type), tone: .accent)
                        LauncherBadge(
                            installedIDs.contains(version.id) ? "已安装" : "未安装",
                            tone: installedIDs.contains(version.id) ? .success : .neutral
                        )
                        if let item = engine.queueItem(for: version.id) {
                            LauncherBadge(item.state.title, tone: queueTone(for: item.state))
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: LauncherSpace.lg) {
                        LauncherInlineStat("发布时间", value: releaseDate(version.releaseTime))
                        LauncherInlineStat("版本类型", value: typeLabel(version.type))
                        LauncherInlineStat("Java 要求", value: javaRequirementText(version), isMono: true)
                        LauncherInlineStat("资源文件", value: assetRequirementText(version))
                    }

                    detailHintRow(version)
                }

                Spacer(minLength: LauncherSpace.sm)

                VStack(alignment: .trailing, spacing: LauncherSpace.xs) {
                    actionButtons(for: version)
                    Text(engine.settings.downloadSourceValue.title)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// Java 要求：已安装版本直接读本地版本 JSON（同步、无网络），未安装版本异步拉取。
    private func javaRequirementText(_ version: VersionSummary) -> String {
        if let detail = displayVersionDetail(for: version) {
            return "\(detail.javaVersion?.majorVersion ?? 21)+"
        }
        if !snapshotMode, detailLoadingIDs.contains(version.id) { return "读取中" }
        if detailErrors[version.id] != nil { return "未知" }
        return "—"
    }

    /// 资源文件要求：来自版本 JSON 的 assetIndex。
    private func assetRequirementText(_ version: VersionSummary) -> String {
        guard let detail = displayVersionDetail(for: version) else { return "—" }
        guard let index = detail.assetIndex else { return "不需要" }
        return "需要（\(index.id)）"
    }

    /// 展示用版本详情：内存缓存 → 已安装版本的本地 JSON（同步）。
    private func displayVersionDetail(for version: VersionSummary) -> VersionDetail? {
        if let cached = versionDetails[version.id] { return cached }
        guard installedIDs.contains(version.id) else { return nil }
        return localVersionDetail(version.id)
    }

    /// 同步读取本地版本 JSON（沿 `inheritsFrom` 最多追 3 层，加载器版本从父版本拿 Java 要求）。
    private func localVersionDetail(_ versionID: String, depth: Int = 0) -> VersionDetail? {
        guard depth < 3 else { return nil }
        let installation = engine.installation
        let candidates = [
            installation.versionJSONURL(versionID),
            installation.cacheDirectory.appendingPathComponent("parents/\(versionID).json")
        ]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: url),
              let detail = try? JSONDecoder().decode(VersionDetail.self, from: data) else {
            return nil
        }
        if detail.javaVersion == nil, detail.assetIndex == nil, let parent = detail.inheritsFrom {
            return localVersionDetail(parent, depth: depth + 1)
        }
        return detail
    }

    @ViewBuilder
    private func detailHintRow(_ version: VersionSummary) -> some View {
        if let message = detailErrors[version.id] {
            HStack(spacing: LauncherSpace.xs) {
                LauncherHintIcon("版本 JSON 拉取失败：\(message)")
                Text("版本详情加载失败：\(message)")
                    .textStyle(.micro, tone: .warning)
                    .lineLimit(1)
                LauncherButton("重试", variant: .ghost, size: .small) {
                    detailErrors[version.id] = nil
                    Task { await loadVersionDetail(for: version.id) }
                }
            }
        } else if let detail = displayVersionDetail(for: version) {
            HStack(spacing: LauncherSpace.xs) {
                LauncherHintIcon(javaAvailabilityText(for: detail))
                Text(javaAvailabilityText(for: detail))
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
            }
        } else if !snapshotMode, detailLoadingIDs.contains(version.id) {
            HStack(spacing: LauncherSpace.sm) {
                LauncherSpinner(size: 12)
                Text("正在读取版本 JSON（Java 要求 / 资源索引）…")
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: LauncherSpace.xs) {
                LauncherHintIcon("选中版本后会自动拉取版本 JSON 检测 Java 要求。")
                Text("安装前会按版本要求检测本机 Java 运行时")
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
            }
        }
    }

    /// 本机 Java 是否满足该版本要求（真实读取已检测的运行时）。
    private func javaAvailabilityText(for detail: VersionDetail) -> String {
        let required = detail.javaVersion?.majorVersion ?? 21
        guard let java = engine.resolvedJava(for: required) else {
            return "需要 Java \(required)+ · 本机未检测到 Java，启动前请在「设置」中指定"
        }
        if java.majorVersion >= required {
            return "需要 Java \(required)+ · 本机 \(java.displayName) 满足要求"
        }
        return "需要 Java \(required)+ · 本机 Java \(java.majorVersion) 低于要求，启动前请安装"
    }

    @ViewBuilder
    private func actionButtons(for version: VersionSummary) -> some View {
        if let item = engine.queueItem(for: version.id), item.state.isActive {
            LauncherButton(
                item.state == .queued ? "排队中" : "安装中",
                systemImage: "clock",
                variant: .secondary,
                size: .medium,
                isDisabled: true
            ) {}
            .launcherTooltip("正在安装，可在下方安装队列中取消")
        } else if installedIDs.contains(version.id) {
            LauncherButton(
                "已安装",
                systemImage: "checkmark",
                variant: .secondary,
                size: .medium,
                isDisabled: true
            ) {}
            .launcherTooltip("该版本已安装；重装或校验请在右上角「…」菜单中操作")
        } else {
            LauncherButton(
                "安装",
                systemImage: "arrow.down.circle",
                variant: .primary,
                size: .medium
            ) {
                startInstall(version.id)
            }
        }
    }

    // MARK: - 安装卡

    private func installCard(_ version: VersionSummary) -> some View {
        let item = queueItem(for: version)
        let isActive = item?.state.isActive == true
        return LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: isActive ? "安装进度" : "安装选项",
                    subtitle: installCardSubtitle(version),
                    accessory: AnyView(
                        LauncherBadge(
                            installCardBadgeTitle(version),
                            tone: installCardBadgeTone(version)
                        )
                    )
                )

                if let item, isActive {
                    queueProgressRow(item, version: version)
                } else if let item {
                    // 已结束（完成 / 失败 / 取消）：保留安装选项，允许改选项直接重装
                    finishedQueueStatusRow(item, version: version)
                    installOptionsRow(version)
                } else if let message = installFailureMessage(for: version) {
                    LauncherBanner(
                        title: "安装失败",
                        message: message,
                        tone: .danger,
                        actionTitle: "重试",
                        onAction: { startInstall(version.id) }
                    )
                } else {
                    installOptionsRow(version)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func queueItem(for version: VersionSummary) -> InstallQueueItem? {
        engine.queueItem(for: version.id)
    }

    private func installCardSubtitle(_ version: VersionSummary) -> String {
        if let item = queueItem(for: version) {
            switch item.state {
            case .queued: return "排队中 · 前一个任务结束后自动开始"
            case .installing: return item.progress?.phase ?? "真实下载中"
            case .finished: return "安装完成 · 可重新安装或校验文件"
            case .cancelled: return "已取消 · 可重新开始"
            case .failed: return "安装失败 · 查看下面的原因后重试"
            }
        }
        if installedIDs.contains(version.id) {
            return "已安装 · 重新安装会覆盖缺失文件"
        }
        return "选项会真实传给安装器，不做假进度"
    }

    private func installCardBadgeTitle(_ version: VersionSummary) -> String {
        if let item = queueItem(for: version) { return item.state.title }
        return installedIDs.contains(version.id) ? "已完成" : "待安装"
    }

    private func installCardBadgeTone(_ version: VersionSummary) -> LauncherBadgeTone {
        guard let item = queueItem(for: version) else {
            return installedIDs.contains(version.id) ? .success : .neutral
        }
        return queueTone(for: item.state)
    }

    /// 进行中队列项的真实进度（队列项进度优先，当前任务读 `engine.phase` 兜底）。
    @ViewBuilder
    private func queueProgressRow(_ item: InstallQueueItem, version: VersionSummary) -> some View {
        let progress = item.progress ?? currentPhaseProgress(for: version)
        LauncherProgressBar(value: progress?.fraction, label: progress?.phase ?? item.state.title)
        HStack(spacing: LauncherSpace.sm) {
            LauncherMonoText(
                "\(progress?.completed ?? 0) / \(progress?.total ?? 0) 个文件",
                tone: .tertiary,
                size: 10
            )
            Text("· \(item.options.summary)")
                .textStyle(.micro, tone: .tertiary)
                .lineLimit(1)
            Spacer(minLength: LauncherSpace.sm)
            LauncherStatusDot(tone: .accent, isPulsing: true)
            LauncherButton(
                "取消安装",
                systemImage: "xmark",
                variant: .secondary,
                size: .small
            ) {
                engine.cancelInstall(versionID: version.id)
            }
            .launcherTooltip("取消后会中断当前下载")
        }
    }

    /// 已结束队列项的状态行：保留安装选项行（可改选项重装），只展示结果与校验 / 移除入口。
    private func finishedQueueStatusRow(_ item: InstallQueueItem, version: VersionSummary) -> some View {
        HStack(spacing: LauncherSpace.sm) {
            LauncherBadge(item.state.title, tone: queueTone(for: item.state))
            if case .failed(let message) = item.state {
                Text(message)
                    .textStyle(.micro, tone: .danger)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(completedSummary(item))
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if item.state == .finished {
                LauncherButton(
                    "校验文件",
                    systemImage: "checkmark.shield",
                    variant: .ghost,
                    size: .small
                ) {
                    verifyVersion(version.id)
                }
                .launcherTooltip("重新校验该版本已安装文件的 SHA1")
            }
            LauncherIconButton(
                systemImage: "xmark",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "从队列移除这条记录"
            ) {
                engine.removeQueueItem(item.id)
            }
            .launcherTooltip("从安装队列移除这条已结束的记录")
        }
    }

    /// 已结束任务的摘要（阶段 + 文件数 + 当时的安装选项）。
    private func completedSummary(_ item: InstallQueueItem) -> String {
        var parts: [String] = []
        if let progress = item.progress {
            parts.append("\(progress.phase) · \(progress.completed) / \(progress.total) 个文件")
        }
        parts.append(item.options.summary)
        return parts.joined(separator: " · ")
    }

    private func currentPhaseProgress(for version: VersionSummary) -> InstallProgress? {
        if case .downloading(let versionID, let progress) = engine.phase, versionID == version.id {
            return progress
        }
        return nil
    }

    private func installFailureMessage(for version: VersionSummary) -> String? {
        guard lastInstallVersionID == version.id else { return nil }
        if case .failed(let message) = engine.phase {
            return message
        }
        if let item = engine.queueItem(for: version.id), case .failed(let message) = item.state {
            return message
        }
        return nil
    }

    private func installOptionsRow(_ version: VersionSummary) -> some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            HStack(spacing: LauncherSpace.xl) {
                LauncherCheckbox("安装资源文件", isOn: $installAssets)
                LauncherCheckbox("校验已存在文件", isOn: $verifyExisting)
                Spacer(minLength: LauncherSpace.sm)
                LauncherButton(
                    installedIDs.contains(version.id) ? "重新安装" : "开始安装",
                    systemImage: "arrow.down.circle",
                    variant: .primary,
                    size: .large
                ) {
                    startInstall(version.id)
                }
            }

            HStack(spacing: LauncherSpace.xs) {
                LauncherHintIcon(optionsHint)
                Text(optionsHint)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
            }
        }
    }

    /// 当前安装选项的真实摘要（直接复用安装器的 `InstallOptions.summary`）。
    private var currentOptions: InstallOptions {
        InstallOptions(includeAssets: installAssets, verifyExisting: verifyExisting)
    }

    private var optionsHint: String {
        "当前选项：\(currentOptions.summary) · 下载源：\(engine.settings.downloadSourceValue.title)"
    }

    // MARK: - 安装队列卡

    private var installQueueCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "安装队列",
                    subtitle: "\(activeQueueCount) 个进行中 · 串行执行，可随时取消",
                    accessory: AnyView(
                        HStack(spacing: LauncherSpace.xs) {
                            if activeQueueCount > 0 {
                                LauncherStatusDot(tone: .accent, isPulsing: true)
                            }
                            LauncherButton(
                                "清空已完成",
                                variant: .ghost,
                                size: .small,
                                isDisabled: finishedQueueCount == 0
                            ) {
                                engine.clearFinishedInstalls()
                            }
                            .launcherTooltip(
                                finishedQueueCount == 0
                                    ? "没有已结束的任务可清空"
                                    : "清空已完成 / 失败 / 已取消的队列记录"
                            )
                        }
                    )
                )

                ForEach(Array(engine.installQueue.prefix(3))) { item in
                    installQueueRow(item)
                }

                if engine.installQueue.count > 3 {
                    Text("另有 \(engine.installQueue.count - 3) 个任务在队列中")
                        .textStyle(.micro, tone: .tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var activeQueueCount: Int {
        engine.installQueue.filter { $0.state.isActive }.count
    }

    private var finishedQueueCount: Int {
        engine.installQueue.filter { !$0.state.isActive }.count
    }

    private func installQueueRow(_ item: InstallQueueItem) -> some View {
        HStack(alignment: .center, spacing: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                HStack(spacing: LauncherSpace.xs) {
                    Text(item.versionID)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    LauncherBadge(item.state.title, tone: queueTone(for: item.state))
                    if let progress = item.progress, item.state.isActive {
                        LauncherMonoText("\(Int(progress.fraction * 100))%", tone: .tertiary, size: 10)
                    }
                    Spacer(minLength: 0)
                }

                if item.state.isActive {
                    LauncherProgressBar(value: item.progress?.fraction, label: item.progress?.phase, height: 4)
                } else if case .failed(let message) = item.state {
                    Text(message)
                        .textStyle(.micro, tone: .danger)
                        .lineLimit(1)
                } else {
                    Text(item.options.summary)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                }
            }

            if item.state.isActive {
                LauncherButton("取消", systemImage: "xmark", variant: .ghost, size: .small) {
                    engine.cancelInstall(versionID: item.versionID)
                }
            } else {
                LauncherIconButton(
                    systemImage: "xmark",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: "从队列移除"
                ) {
                    engine.removeQueueItem(item.id)
                }
            }
        }
    }

    private func queueTone(for state: InstallQueueItem.State) -> LauncherBadgeTone {
        switch state {
        case .queued: return .neutral
        case .installing: return .accent
        case .finished: return .success
        case .cancelled: return .neutral
        case .failed: return .danger
        }
    }

    // MARK: - 底部卡片（磁盘 / 下载源）

    private var bottomCards: some View {
        HStack(alignment: .top, spacing: LauncherSpace.md) {
            diskCard
                .frame(maxWidth: .infinity)
            sourceCard
                .frame(maxWidth: .infinity)
        }
    }

    /// 展示用磁盘统计：快照模式同步算一次（APFS 上几十毫秒），交互模式用后台刷新的结果。
    private var displayedDiskUsage: DownloadDiskUsage? {
        if let diskUsage { return diskUsage }
        return snapshotMode ? DownloadPage.snapshotDiskUsage : nil
    }

    /// 离屏快照用的一次性磁盘统计（进程内只算一次，避免每帧遍历）。
    private static let snapshotDiskUsage: DownloadDiskUsage? = {
        let root = LauncherSettings.shared.resolvedGameDirectory
        let installation = MinecraftInstallation(root: root)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        return DownloadDiskUsage(
            versions: InstanceActions.size(of: installation.versionsDirectory),
            libraries: InstanceActions.size(of: installation.librariesDirectory),
            assets: InstanceActions.size(of: installation.assetsDirectory),
            cache: InstanceActions.size(of: installation.cacheDirectory),
            computedAt: Date()
        )
    }()

    private var diskCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "磁盘占用",
                    subtitle: diskSubtitle,
                    accessory: AnyView(
                        LauncherBadge(
                            displayedDiskUsage.map { "共 \(ModrinthFormat.fileSize($0.total))" } ?? "—",
                            tone: .neutral
                        )
                    )
                )

                LauncherProgressBar(
                    value: volumeUsedFraction,
                    label: "卷可用 \(volumeFreeText) / \(volumeTotalText)",
                    height: 4
                )

                HStack(spacing: LauncherSpace.md) {
                    LauncherInlineStat("版本", value: displayedDiskUsage?.versionsText ?? "—", isMono: true)
                    LauncherInlineStat("依赖库", value: displayedDiskUsage?.librariesText ?? "—", isMono: true)
                    LauncherInlineStat("资源", value: displayedDiskUsage?.assetsText ?? "—", isMono: true)
                    LauncherInlineStat("缓存", value: displayedDiskUsage?.cacheText ?? "—", isMono: true)
                    Spacer(minLength: 0)
                }

                HStack(spacing: LauncherSpace.sm) {
                    LauncherButton(
                        "刷新",
                        systemImage: "arrow.clockwise",
                        variant: .ghost,
                        size: .small,
                        isLoading: isRefreshingDisk
                    ) {
                        Task { await refreshDiskUsage() }
                    }
                    LauncherButton(
                        "清理缓存",
                        systemImage: "trash",
                        variant: .secondary,
                        size: .small,
                        isLoading: isClearingCache,
                        isDisabled: isClearingCache
                    ) {
                        confirmClearCache()
                    }
                    .launcherTooltip(
                        isClearingCache
                            ? "正在清理缓存，请稍候"
                            : "删除启动器缓存目录（版本清单、资源索引、父版本 JSON）"
                    )
                    Spacer(minLength: 0)
                    LauncherIconButton(
                        systemImage: "folder",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: "打开游戏目录"
                    ) {
                        openGameDirectory()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var diskSubtitle: String {
        shortGameDirectory
    }

    private var shortGameDirectory: String {
        let path = engine.settings.resolvedGameDirectory.path
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private var sourceCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "下载源",
                    subtitle: engine.settings.downloadSourceValue.title
                )

                LauncherDropdown(
                    options: sourceOptions,
                    selection: sourceBinding,
                    placeholder: "选择下载源"
                )

                HStack(spacing: LauncherSpace.xs) {
                    LauncherHintIcon(engine.settings.downloadSourceValue.detail)
                    Text(engine.settings.downloadSourceValue.detail)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("切换后立即生效：清单、版本 JSON、依赖库与资源文件下载都会走所选源。")
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 社区资源

    private func communityContent(_ projectType: ModrinthProjectType) -> some View {
        DownloadCommunityPane(
            category: projectType,
            searchText: searchText,
            versionOptions: communityVersionOptions,
            gameVersion: $communityGameVersion,
            selectedInstanceID: $selectedInstanceID,
            installCenter: installCenter,
            onImportModpack: {
                importLocalModpack()
            }
        )
        .id(projectType)
    }

    /// 社区资源过滤用的 MC 版本选项（Mojang 正式版中最近 12 个）。
    private var communityVersionOptions: [LauncherSegment<String>] {
        guard let manifest else { return [] }
        let releases = manifest.versions.filter { $0.type == "release" }.prefix(12)
        var options = releases.map { version in
            LauncherSegment(
                id: version.id,
                title: version.id == manifest.latest.release ? "\(version.id)（最新）" : version.id,
                systemImage: "cube.fill"
            )
        }
        if !communityGameVersion.isEmpty,
           !options.contains(where: { $0.id == communityGameVersion }) {
            options.insert(
                LauncherSegment(id: communityGameVersion, title: communityGameVersion, systemImage: "flask"),
                at: 0
            )
        }
        return options
    }

    // MARK: - 清单数据

    private var installedIDs: Set<String> {
        Set(engine.installedVersions.map(\.id))
    }

    /// 左面板 Minecraft 分组右侧计数：社区分类下显示正式版总数，避免出现 0。
    private var minecraftCountText: String {
        guard let manifest else { return "0" }
        if category.isMinecraft { return "\(typeVersions.count)" }
        return "\(manifest.versions.filter { $0.type == "release" }.count)"
    }

    /// 当前分类的版本（按 type 过滤 → 搜索 → 排序）。
    private var typeVersions: [VersionSummary] {
        guard let manifest, category.isMinecraft else { return [] }
        var items = manifest.versions.filter { version in
            switch category {
            case .release: return version.type == "release"
            case .snapshot: return version.type == "snapshot"
            case .legacy: return version.type.hasPrefix("old_")
            default: return false
            }
        }

        if !searchText.isEmpty {
            items = items.filter { $0.id.localizedCaseInsensitiveContains(searchText) }
        }

        switch sortMode {
        case .newest:
            items.sort { $0.releaseTime > $1.releaseTime }
        case .version:
            items.sort { $0.id.compare($1.id, options: .numeric) == .orderedDescending }
        case .installedFirst:
            items.sort { lhs, rhs in
                let lhsInstalled = installedIDs.contains(lhs.id)
                let rhsInstalled = installedIDs.contains(rhs.id)
                if lhsInstalled != rhsInstalled { return lhsInstalled }
                return lhs.releaseTime > rhs.releaseTime
            }
        }
        return items
    }

    /// 左面板展示的版本：快照固定前 5 条（静态图不溢出），交互模式可展开全部。
    private var displayedVersions: [VersionSummary] {
        if snapshotMode || !showsAllVersions {
            return Array(typeVersions.prefix(defaultVisibleVersions))
        }
        return typeVersions
    }

    private var selectedVersion: VersionSummary? {
        guard category.isMinecraft else { return nil }
        if let selectedVersionID,
           let match = typeVersions.first(where: { $0.id == selectedVersionID }) {
            return match
        }
        return typeVersions.first
    }

    private var sortMenuGroups: [LauncherMenuGroup] {
        [
            LauncherMenuGroup(items: VersionSort.allCases.map { sort in
                LauncherMenuItem(
                    sort.rawValue,
                    systemImage: sortMode == sort ? "checkmark" : "arrow.up.arrow.down",
                    action: { sortMode = sort }
                )
            })
        ]
    }

    private func moreMenuGroups(for version: VersionSummary) -> [LauncherMenuGroup] {
        var items: [LauncherMenuItem] = []
        if let item = engine.queueItem(for: version.id), item.state.isActive {
            items.append(
                LauncherMenuItem("取消安装", systemImage: "xmark", action: {
                    engine.cancelInstall(versionID: version.id)
                })
            )
        } else {
            items.append(
                LauncherMenuItem(
                    installedIDs.contains(version.id) ? "重新安装" : "安装此版本",
                    systemImage: "arrow.down.circle",
                    action: { startInstall(version.id) }
                )
            )
        }
        items.append(LauncherMenuItem("复制版本号", systemImage: "doc.on.doc", action: {
            InstanceActions.copy(version.id)
            router.showToast("已复制版本号 \(version.id)", tone: .info)
        }))
        if installedIDs.contains(version.id) {
            items.append(LauncherMenuItem("校验已安装文件", systemImage: "checkmark.shield", action: {
                verifyVersion(version.id)
            }))
            items.append(LauncherMenuItem("打开实例目录", systemImage: "folder", action: {
                openInstanceDirectory(for: version.id)
            }))
            items.append(
                LauncherMenuItem(
                    "删除此版本",
                    systemImage: "trash",
                    tone: .danger,
                    action: { promptDeleteVersion(version.id) }
                )
            )
        }
        return [LauncherMenuGroup(items: items)]
    }

    private func contextMenuGroups(for version: VersionSummary) -> [LauncherMenuGroup] {
        moreMenuGroups(for: version)
    }

    private func releaseDate(_ text: String) -> String {
        String(text.prefix(10))
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "release": return "正式版"
        case "snapshot": return "快照"
        case "old_beta": return "远古 Beta"
        case "old_alpha": return "远古 Alpha"
        default: return type
        }
    }

    private func icon(for type: String) -> String {
        switch type {
        case "release": return "cube.fill"
        case "snapshot": return "flask"
        default: return "shippingbox.fill"
        }
    }

    // MARK: - 磁盘与下载源

    private var sourceOptions: [LauncherSegment<String>] {
        DownloadSource.allCases.map { source in
            LauncherSegment(
                id: source.rawValue,
                title: source.title,
                systemImage: source == .mirror ? "bolt.fill" : "globe"
            )
        }
    }

    private var sourceBinding: Binding<String> {
        Binding(
            get: { engine.settings.downloadSourceValue.rawValue },
            set: { engine.settings.downloadSource = $0 }
        )
    }

    private var volumeInfo: (free: String, total: String, usedFraction: Double) {
        let directory = engine.settings.resolvedGameDirectory
        guard
            let values = try? directory.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
            ),
            let totalBytes = values.volumeTotalCapacity, totalBytes > 0
        else {
            return ("—", "—", 0)
        }
        let freeBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        let usedFraction = min(1, max(0, 1 - Double(freeBytes) / Double(totalBytes)))
        return (
            ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file),
            ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file),
            usedFraction
        )
    }

    private var volumeFreeText: String { volumeInfo.free }
    private var volumeTotalText: String { volumeInfo.total }
    private var volumeUsedFraction: Double { volumeInfo.usedFraction }

    // MARK: - 交互

    private func selectCategory(_ newCategory: DownloadCategory) {
        // 先记住当前选中的 MC 版本，切到社区资源分类后作为过滤条件
        let previousVersionID = selectedVersion?.id
        let wasMinecraft = category.isMinecraft
        if wasMinecraft != newCategory.isMinecraft {
            // 版本号搜索与社区资源搜索目标不同，跨大类切换时清空搜索词
            searchText = ""
        }
        withAnimation(LauncherMotion.spring) {
            category = newCategory
            selectedVersionID = nil
        }
        guard newCategory.projectType != nil else { return }
        if let previousVersionID {
            communityGameVersion = previousVersionID
        } else if communityGameVersion.isEmpty {
            communityGameVersion = manifest?.latest.release ?? ""
        }
    }

    /// 读取版本清单（优先 12 小时磁盘缓存，forceRefresh 时强制联网）。
    private func loadManifest(forceRefresh: Bool = false) async {
        isLoadingManifest = true
        do {
            let service = MojangManifestService(
                installation: engine.installation,
                source: engine.settings.downloadSourceValue
            )
            loadedManifest = try await service.fetchManifest(forceRefresh: forceRefresh)
            manifestError = nil
            if communityGameVersion.isEmpty {
                communityGameVersion = manifest?.latest.release ?? ""
            }
        } catch {
            manifestError = error.localizedDescription
        }
        isLoadingManifest = false
    }

    private func refreshManifest(forceRefresh: Bool) {
        Task { @MainActor in
            await loadManifest(forceRefresh: forceRefresh)
        }
    }

    private func refreshAll() {
        Task { @MainActor in
            await engine.refreshEnvironment()
            await loadManifest(forceRefresh: true)
            await refreshDiskUsage()
        }
    }

    /// 拉取选中版本的版本 JSON（真实网络请求，失败只在详情卡提示，不阻塞列表）。
    private func loadVersionDetail(for versionID: String) async {
        guard versionDetails[versionID] == nil, !detailLoadingIDs.contains(versionID) else { return }
        // 已安装版本：先用本地 JSON 填充详情（无网络也能显示 Java 要求 / 资源索引）
        if installedIDs.contains(versionID), let local = localVersionDetail(versionID) {
            versionDetails[versionID] = local
            return
        }
        detailErrors[versionID] = nil
        detailLoadingIDs.insert(versionID)
        do {
            let service = MojangManifestService(
                installation: engine.installation,
                source: engine.settings.downloadSourceValue
            )
            let detail = try await service.fetchVersionDetail(versionID)
            guard !Task.isCancelled else { return }
            versionDetails[versionID] = detail
        } catch {
            guard !Task.isCancelled else { return }
            detailErrors[versionID] = error.localizedDescription
        }
        detailLoadingIDs.remove(versionID)
    }

    /// 触发真实安装：入队后由引擎串行执行，进度写回队列与 `engine.phase`。
    private func startInstall(_ versionID: String) {
        lastInstallVersionID = versionID
        let options = currentOptions
        engine.enqueueInstall(versionID: versionID, options: options)
        router.showToast("已加入安装队列：\(versionID)", tone: .info)
    }

    /// 校验已安装版本的文件完整性（真实读取文件并比对 SHA1）。
    private func verifyVersion(_ versionID: String) {
        Task { @MainActor in
            if let result = await engine.verifyInstalled(versionID: versionID) {
                router.showToast(result.summary, tone: result.isHealthy ? .success : .warning)
            } else {
                router.showToast("校验失败，请查看日志", tone: .danger)
            }
        }
    }

    private func openGameDirectory() {
        let directory = engine.settings.resolvedGameDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if InstanceActions.open(directory) {
            router.showToast("已打开游戏目录", tone: .info)
        } else {
            router.showToast("无法打开目录：\(directory.path)", tone: .danger)
        }
    }

    private func openInstanceDirectory(for versionID: String) {
        let directory = engine.settings.gameDirectory(for: versionID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        InstanceActions.open(directory)
    }

    private func promptDeleteVersion(_ versionID: String) {
        let dependents = dependentInstanceIDs(of: versionID)
        var message = "将把 versions/\(versionID) 移到废纸篓（可在访达中恢复），"
            + "并取消该版本正在进行的安装任务、移除队列里这条版本的历史记录。"
        if !dependents.isEmpty {
            let preview = dependents.prefix(3).joined(separator: "、")
            message += "\n\n注意：有 \(dependents.count) 个实例依赖它（\(preview)），无法删除；请先删除这些依赖实例。"
        }
        router.showDialog(
            LauncherDialogRequest(
                title: "删除版本 \(versionID)",
                message: message,
                confirmTitle: "删除",
                isDestructive: true,
                onConfirm: {
                    engine.cancelInstall(versionID: versionID)
                    for item in engine.installQueue where item.versionID == versionID {
                        engine.removeQueueItem(item.id)
                    }
                    do {
                        try engine.deleteVersion(versionID)
                        router.showToast("已删除 \(versionID)", tone: .success)
                    } catch {
                        router.showToast("删除失败：\(error.localizedDescription)", tone: .danger)
                    }
                }
            )
        )
    }

    /// 通过 `inheritsFrom` 依赖该版本的其它实例 id（只读本地版本 JSON，删除前提示用）。
    private func dependentInstanceIDs(of versionID: String) -> [String] {
        let installation = engine.installation
        return engine.installedVersions.compactMap { version in
            guard version.id != versionID,
                  let data = try? Data(contentsOf: installation.versionJSONURL(version.id)),
                  let detail = try? JSONDecoder().decode(VersionDetail.self, from: data) else {
                return nil
            }
            return detail.inheritsFrom == versionID ? version.id : nil
        }
    }

    // MARK: - 磁盘统计

    /// 重新统计游戏目录占用（后台线程遍历文件，不卡 UI）。
    private func refreshDiskUsage() async {
        guard !isRefreshingDisk else { return }
        isRefreshingDisk = true
        let installation = engine.installation
        let usage = await Task.detached(priority: .utility) { () -> DownloadDiskUsage in
            DownloadDiskUsage(
                versions: InstanceActions.size(of: installation.versionsDirectory),
                libraries: InstanceActions.size(of: installation.librariesDirectory),
                assets: InstanceActions.size(of: installation.assetsDirectory),
                cache: InstanceActions.size(of: installation.cacheDirectory),
                computedAt: Date()
            )
        }.value
        diskUsage = usage
        isRefreshingDisk = false
    }

    /// 清理缓存：真实删除启动器缓存目录（确认对话框 + 提示）。
    private func confirmClearCache() {
        let directory = engine.installation.cacheDirectory
        let sizeText = displayedDiskUsage.map { ModrinthFormat.fileSize($0.cache) } ?? "未知"
        router.showDialog(
            LauncherDialogRequest(
                title: "清理启动器缓存",
                message: "将删除 \(directory.path)（约 \(sizeText)）：版本清单、资源索引、父版本 JSON 与 log4j 配置缓存。已安装的版本与游戏文件不受影响，下次安装 / 启动会重新下载。",
                confirmTitle: "清理缓存",
                isDestructive: true,
                onConfirm: {
                    Task { await clearCache() }
                }
            )
        )
    }

    private func clearCache() async {
        guard !isClearingCache else { return }
        isClearingCache = true
        let directory = engine.installation.cacheDirectory
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            router.showToast("缓存已清理（\(directory.lastPathComponent)）", tone: .success)
        } catch {
            router.showToast("清理缓存失败：\(error.localizedDescription)", tone: .danger)
        }
        await refreshDiskUsage()
        isClearingCache = false
    }

    // MARK: - 社区资源导入

    /// 导入本地整合包（系统文件选择器，走与在线安装相同的真实流程）。
    private func importLocalModpack() {
        guard let url = InstanceActions.pickFile(
            message: "选择 Modrinth 整合包（.mrpack / .zip）",
            prompt: "导入",
            allowedExtensions: ["mrpack", "zip"]
        ) else { return }
        installCenter.importModpack(from: url, settings: engine.settings, engine: engine)
    }

    /// 消费「启动页 / 更多页」发来的一次性动作（导入整合包）。
    private func consumePendingDownloadAction() {
        guard router.pendingDownloadAction == "import-modpack" else { return }
        router.pendingDownloadAction = nil
        selectCategory(.modpack)
        Task { @MainActor in
            importLocalModpack()
        }
    }

    /// 读取与 `MojangManifestService` 相同位置的清单缓存，用于首帧快速展示。
    private static func readCachedManifest() -> VersionManifest? {
        let installation = MinecraftInstallation(root: LauncherSettings.shared.resolvedGameDirectory)
        let service = MojangManifestService(installation: installation)
        let cacheURL = service.cacheDirectory.appendingPathComponent("version_manifest_v2.json")
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(VersionManifest.self, from: data)
    }
}

// MARK: - 磁盘占用

/// 游戏目录的真实占用统计（versions / libraries / assets / 启动器缓存）。
private struct DownloadDiskUsage: Equatable, Sendable {
    let versions: Int64
    let libraries: Int64
    let assets: Int64
    let cache: Int64
    let computedAt: Date

    /// 游戏目录本体占用（不含缓存）。
    var total: Int64 { versions + libraries + assets }

    var versionsText: String { ModrinthFormat.fileSize(versions) }
    var librariesText: String { ModrinthFormat.fileSize(libraries) }
    var assetsText: String { ModrinthFormat.fileSize(assets) }
    var cacheText: String { ModrinthFormat.fileSize(cache) }
}

// MARK: - 分类与排序

/// 下载页左侧分类：Minecraft 三类 + 社区资源六类。
private enum DownloadCategory: String, CaseIterable, Identifiable {
    case release
    case snapshot
    case legacy
    case modpack
    case mod
    case resourcepack
    case shader
    case world
    case datapack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .release: return "正式版"
        case .snapshot: return "快照"
        case .legacy: return "远古版"
        case .modpack: return "整合包"
        case .mod: return "模组"
        case .resourcepack: return "资源包"
        case .shader: return "光影包"
        case .world: return "世界"
        case .datapack: return "数据包"
        }
    }

    var systemImage: String {
        switch self {
        case .release: return "cube.fill"
        case .snapshot: return "flask"
        case .legacy: return "shippingbox.fill"
        case .modpack: return "shippingbox"
        case .mod: return "puzzlepiece.extension.fill"
        case .resourcepack: return "paintpalette.fill"
        case .shader: return "sparkles"
        case .world: return "globe"
        case .datapack: return "doc.zipper"
        }
    }

    var isMinecraft: Bool {
        switch self {
        case .release, .snapshot, .legacy: return true
        default: return false
        }
    }

    /// 社区资源分类对应的 Modrinth 项目类型（Minecraft 分类为 nil）。
    var projectType: ModrinthProjectType? {
        switch self {
        case .modpack: return .modpack
        case .mod: return .mod
        case .resourcepack: return .resourcepack
        case .shader: return .shader
        case .world: return .world
        case .datapack: return .datapack
        case .release, .snapshot, .legacy: return nil
        }
    }

    /// 左面板小卡第二行：真实安装位置。
    var tileHint: String {
        switch self {
        case .modpack: return "新建实例"
        case .mod: return "mods/"
        case .resourcepack: return "resourcepacks/"
        case .shader: return "shaderpacks/"
        case .world: return "saves/"
        case .datapack: return "datapacks/"
        case .release, .snapshot, .legacy: return "Mojang 清单"
        }
    }

    static let minecraftTypes: [DownloadCategory] = [.release, .snapshot, .legacy]
    static let communityResources: [DownloadCategory] = [
        .modpack, .mod, .resourcepack, .shader, .world, .datapack
    ]
}

/// 版本列表排序方式。
private enum VersionSort: String, CaseIterable, Hashable {
    case newest = "按发布时间"
    case version = "按版本号"
    case installedFirst = "已安装优先"
}
