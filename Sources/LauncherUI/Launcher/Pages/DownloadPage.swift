import AppKit
import Foundation
import SwiftUI

/// 下载页（PCL 式布局）：左侧分类与版本列表，右侧版本详情 / 安装选项 / 安装进度。
public struct DownloadPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine

    // 左面板：分类、搜索、排序
    @State private var category: DownloadCategory = .release
    @State private var searchText = ""
    @State private var sortMode: VersionSort = .newest
    @State private var selectedVersionID: String?

    // 真实清单
    @State private var manifest: VersionManifest? = DownloadPage.launchManifestCache
    @State private var isLoadingManifest = DownloadPage.launchManifestCache == nil
    @State private var manifestError: String?
    @State private var lastInstallID: String?

    // 安装选项（后端当前始终完整安装，选项仅作界面演示）
    @State private var installDependencies = true
    @State private var installAssets = true

    // 整合包演示
    @State private var modpacks: [LauncherVersionItem] = DemoModpacks.items
    @State private var importHint: String?

    // 磁盘
    @State private var isRefreshingInstalled = false

    /// 首帧快速展示：读取与 MojangManifestService 相同位置的清单缓存，随后仍异步刷新。
    private static let launchManifestCache: VersionManifest? = readCachedManifest()

    /// 左面板一次最多展示的版本行数，保证最小窗口下左面板不溢出。
    private let maxVisibleVersions = 5

    public init() {}

    public var body: some View {
        LauncherPageLayout(sideWidth: 272) {
            sidePanel
        } main: {
            LauncherMainPanel {
                mainContent
            }
        }
        .task {
            if engine.installedVersions.isEmpty {
                await engine.refreshEnvironment()
            }
            await loadManifest()
        }
    }

    // MARK: - 左面板

    private var sidePanel: some View {
        LauncherSidePanel(
            title: "下载",
            count: manifest.map { "\($0.versions.count)" },
            width: 272,
            searchText: $searchText,
            searchPlaceholder: "搜索版本号",
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
                isDisabled: isLoadingManifest
            ) {
                refreshAll()
            }
        }
    }

    @ViewBuilder
    private var sideContent: some View {
        if manifest == nil {
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
        } else {
            LauncherSidePanelGroup("Minecraft", trailing: "\(typeVersions.count)")
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
                }
            }

            LauncherSidePanelGroup("社区资源", trailing: "6")
            communityGrid
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
                Text(item == .modpack ? "页面内演示" : "暂未接入")
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
            Rectangle()
                .fill(theme.colors.stroke)
                .frame(height: 1)

            LauncherButton(
                "刷新列表",
                systemImage: "arrow.clockwise",
                variant: .secondary,
                size: .small,
                isLoading: isLoadingManifest,
                isFullWidth: true
            ) {
                refreshAll()
            }

            HStack(spacing: LauncherSpace.xs) {
                Text("已安装 \(engine.installedVersions.count) 个版本")
                    .textStyle(.micro, tone: .tertiary)
                Spacer(minLength: 0)
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
        } else if category == .modpack {
            modpackMain
        } else if !category.isMinecraft {
            unsupportedMain
        } else {
            versionMain
        }
    }

    @ViewBuilder
    private var manifestPlaceholder: some View {
        LauncherPanelHeader("下载 Minecraft", subtitle: "版本清单来自 Mojang 官方接口")
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

    @ViewBuilder
    private var versionMain: some View {
        if let version = selectedVersion {
            LauncherPanelHeader(
                version.id,
                subtitle: "发布于 \(releaseDate(version.releaseTime)) · \(typeLabel(version.type))"
            ) {
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

    private func versionInfoCard(_ version: VersionSummary) -> some View {
        GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.lg) {
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
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: LauncherSpace.xl) {
                        LauncherInlineStat("发布时间", value: releaseDate(version.releaseTime))
                        LauncherInlineStat("版本类型", value: typeLabel(version.type))
                        LauncherInlineStat("Java 要求", value: "21+", isMono: true)
                    }

                    HStack(spacing: LauncherSpace.xs) {
                        LauncherHintIcon("真实安装器会按版本清单要求检测 Java 运行时。")
                        Text("启动器要求 Java 21+ · 安装前会自动检查运行时")
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: LauncherSpace.sm)

                VStack(alignment: .trailing, spacing: LauncherSpace.xs) {
                    actionButtons(for: version)
                    Text("Mojang 官方清单")
                        .textStyle(.micro, tone: .tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButtons(for version: VersionSummary) -> some View {
        if installedIDs.contains(version.id) {
            LauncherButton(
                "已安装",
                systemImage: "checkmark",
                variant: .secondary,
                size: .medium,
                isDisabled: true
            ) {}
        } else if isDownloading(version.id) {
            LauncherButton(
                "取消",
                systemImage: "xmark",
                variant: .secondary,
                size: .medium,
                isDisabled: true
            ) {}
            .launcherTooltip("真实安装任务暂不支持中断，请等待完成")
        } else {
            LauncherButton(
                "安装",
                systemImage: "arrow.down.circle",
                variant: .primary,
                size: .medium,
                isDisabled: engine.isBusy
            ) {
                startInstall(version.id)
            }
        }
    }

    private func installCard(_ version: VersionSummary) -> some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: isDownloading(version.id) ? "安装进度" : "安装选项",
                    subtitle: isDownloading(version.id)
                        ? "真实下载中 · 离开本页不会中断"
                        : "安装前可选择下载内容",
                    accessory: AnyView(
                        LauncherBadge(
                            isDownloading(version.id) ? "下载中" : (installedIDs.contains(version.id) ? "已完成" : "待安装"),
                            tone: isDownloading(version.id) ? .accent : (installedIDs.contains(version.id) ? .success : .neutral)
                        )
                    )
                )

                if let progress = downloadingProgress(version.id) {
                    LauncherProgressBar(value: progress.fraction, label: progress.phase)
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherMonoText(
                            "\(progress.completed) / \(progress.total) 个文件",
                            tone: .tertiary,
                            size: 10
                        )
                        Spacer(minLength: LauncherSpace.sm)
                        LauncherStatusDot(tone: .warning)
                        Text("在后台继续：离开本页不会中断安装")
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }
                } else if let lastInstallID, case .failed(let message) = engine.phase, lastInstallID == version.id {
                    LauncherBanner(
                        title: "安装失败",
                        message: message,
                        tone: .danger,
                        actionTitle: "重试",
                        onAction: { startInstall(version.id) }
                    )
                } else {
                    HStack(spacing: LauncherSpace.xxl) {
                        LauncherCheckbox("安装依赖库", isOn: $installDependencies)
                        LauncherCheckbox("安装资源文件", isOn: $installAssets)
                        Spacer(minLength: LauncherSpace.sm)
                        LauncherButton(
                            installedIDs.contains(version.id) ? "重新安装" : "开始安装",
                            systemImage: "arrow.down.circle",
                            variant: .primary,
                            size: .large,
                            isDisabled: engine.isBusy
                        ) {
                            startInstall(version.id)
                        }
                    }

                    HStack(spacing: LauncherSpace.xs) {
                        LauncherHintIcon("真实安装器始终下载完整依赖与资源；两个选项目前仅作界面演示。")
                        Text("真实安装器始终完整安装依赖与资源，选项仅作演示")
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bottomCards: some View {
        HStack(alignment: .top, spacing: LauncherSpace.md) {
            diskCard
                .frame(maxWidth: .infinity)
            sourceCard
                .frame(maxWidth: .infinity)
        }
    }

    private var diskCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "磁盘占用",
                    subtitle: "游戏目录所在卷",
                    accessory: AnyView(
                        LauncherBadge("\(engine.installedVersions.count) 个版本", tone: .neutral)
                    )
                )
                LauncherProgressBar(value: volumeUsedFraction, label: "可用 \(volumeFreeText)", height: 4)
                HStack(spacing: LauncherSpace.md) {
                    LauncherInlineStat("卷容量", value: volumeTotalText, isMono: true)
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherButton(
                        isRefreshingInstalled ? "刷新中" : "刷新",
                        systemImage: "arrow.clockwise",
                        variant: .ghost,
                        size: .small,
                        isLoading: isRefreshingInstalled
                    ) {
                        refreshInstalled()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(title: "下载源", subtitle: sourceDetail)
                LauncherDropdown(
                    options: sourceOptions,
                    selection: sourceBinding,
                    placeholder: "选择下载源"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 整合包 / 未接入分区

    private var modpackMain: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            LauncherPanelHeader(
                "整合包",
                subtitle: "\(modpacks.count) 个演示整合包 · 真实安装暂未接入"
            ) {
                LauncherButton(
                    "导入整合包",
                    systemImage: "shippingbox",
                    variant: .secondary,
                    size: .small
                ) {
                    showImportHint()
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: LauncherSpace.md), count: 3),
                spacing: LauncherSpace.md
            ) {
                ForEach(modpacks) { item in
                    modpackCard(item)
                }
            }
            .launcherAnimation(LauncherMotion.spring, value: modpacks)

            if let importHint {
                Text(importHint)
                    .textStyle(.micro, tone: .tertiary)
            }
        }
    }

    private func modpackCard(_ item: LauncherVersionItem) -> some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherBlockArt(seed: item.id, cornerRadius: LauncherRadius.md, label: item.size)
                    .frame(height: 76)

                HStack(spacing: LauncherSpace.xs) {
                    Text(item.version)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    LauncherBadge("整合包", tone: .neutral)
                }

                Text(item.note)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                modpackStatus(for: item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 整合包卡片三态（页面内演示，不触发真实安装）。
    @ViewBuilder
    private func modpackStatus(for item: LauncherVersionItem) -> some View {
        switch item.state {
        case .available:
            LauncherButton(
                "安装",
                systemImage: "arrow.down.circle",
                variant: .primary,
                size: .small,
                isFullWidth: true
            ) {
                startModpackDemoInstall(item.id)
            }
        case .installing(let progress):
            LauncherProgressBar(value: progress)
        case .installed:
            LauncherButton(
                "已安装",
                systemImage: "checkmark",
                variant: .secondary,
                size: .small,
                isFullWidth: true,
                isDisabled: true
            ) {}
        }
    }

    private var unsupportedMain: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            LauncherPanelHeader(
                category.title,
                subtitle: "社区资源 · 当前版本暂未接入"
            )
            LauncherCard(level: .regular, padding: LauncherSpace.lg) {
                LauncherEmptyState(
                    systemImage: category.systemImage,
                    title: "\(category.title)暂未接入",
                    message: "当前启动器只支持安装 Minecraft 原版版本，社区资源下载仍在开发中。",
                    actionTitle: "浏览正式版",
                    onAction: { selectCategory(.release) }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 清单数据

    private var installedIDs: Set<String> {
        Set(engine.installedVersions.map(\.id))
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

    /// 左面板截断展示（最小窗口不溢出）。
    private var displayedVersions: [VersionSummary] {
        Array(typeVersions.prefix(maxVisibleVersions))
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
        [
            LauncherMenuGroup(items: [
                LauncherMenuItem("复制版本号", systemImage: "doc.on.doc", action: {
                    copyVersionID(version.id)
                }),
                LauncherMenuItem("打开版本列表", systemImage: "folder", action: {
                    NSWorkspace.shared.open(engine.settings.resolvedGameDirectory)
                }),
                LauncherMenuItem("刷新清单", systemImage: "arrow.clockwise", action: {
                    refreshAll()
                })
            ])
        ]
    }

    private func contextMenuGroups(for version: VersionSummary) -> [LauncherMenuGroup] {
        [
            LauncherMenuGroup(items: [
                LauncherMenuItem(
                    installedIDs.contains(version.id) ? "已安装" : "安装此版本",
                    systemImage: "arrow.down.circle",
                    isDisabled: engine.isBusy || installedIDs.contains(version.id),
                    action: { startInstall(version.id) }
                )
            ]),
            LauncherMenuGroup(items: [
                LauncherMenuItem("复制版本号", systemImage: "doc.on.doc", action: {
                    copyVersionID(version.id)
                }),
                LauncherMenuItem("打开文件夹", systemImage: "folder", action: {
                    NSWorkspace.shared.open(engine.settings.resolvedGameDirectory)
                })
            ])
        ]
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

    // MARK: - 安装状态

    private func isDownloading(_ versionID: String) -> Bool {
        if case .downloading(let current, _) = engine.phase { return current == versionID }
        return false
    }

    private func downloadingProgress(_ versionID: String) -> InstallProgress? {
        if case .downloading(let current, let progress) = engine.phase, current == versionID {
            return progress
        }
        return nil
    }

    // MARK: - 下载源与磁盘

    private var sourceOptions: [LauncherSegment<String>] {
        [
            LauncherSegment(id: "official", title: "官方源 · 自动选择", systemImage: "globe"),
            LauncherSegment(id: "mirror", title: "镜像源 · 加速", systemImage: "bolt.fill")
        ]
    }

    private var sourceBinding: Binding<String> {
        Binding(
            get: { engine.settings.downloadSource },
            set: { engine.settings.downloadSource = $0 }
        )
    }

    private var sourceDetail: String {
        engine.settings.downloadSource == "mirror"
            ? "镜像源 · 已写入启动器设置"
            : "官方源 · 已写入启动器设置"
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
        withAnimation(LauncherMotion.spring) {
            category = newCategory
            selectedVersionID = nil
        }
    }

    private func copyVersionID(_ versionID: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(versionID, forType: .string)
    }

    /// 读取版本清单（优先 12 小时磁盘缓存，forceRefresh 时强制联网）。
    private func loadManifest(forceRefresh: Bool = false) async {
        isLoadingManifest = true
        do {
            let service = MojangManifestService(installation: engine.installation)
            manifest = try await service.fetchManifest(forceRefresh: forceRefresh)
            manifestError = nil
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
        }
    }

    private func refreshInstalled() {
        guard !isRefreshingInstalled else { return }
        isRefreshingInstalled = true
        Task { @MainActor in
            await engine.refreshEnvironment()
            isRefreshingInstalled = false
        }
    }

    /// 调用真实安装：进度由 engine.phase 驱动，安装完成后 engine 自动刷新已安装列表。
    private func startInstall(_ versionID: String) {
        guard !engine.isBusy else { return }
        lastInstallID = versionID
        Task { @MainActor in
            await engine.install(versionID: versionID)
        }
    }

    private func showImportHint() {
        withAnimation(LauncherMotion.smooth) {
            importHint = "演示：把 .zip 整合包拖入窗口，或从模组站一键导入"
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(LauncherMotion.smooth) {
                importHint = nil
            }
        }
    }

    /// 整合包安装演示：不触发真实下载，仅做行内进度反馈。
    private func startModpackDemoInstall(_ id: String) {
        guard let index = modpacks.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(LauncherMotion.spring) {
            modpacks[index].state = .installing(0)
        }
        Task { @MainActor in
            var progress = 0.0
            while progress < 1 {
                try? await Task.sleep(nanoseconds: 600_000_000)
                progress = min(1, progress + 0.15)
                guard let current = modpacks.firstIndex(where: { $0.id == id }) else { return }
                withAnimation(LauncherMotion.smooth) {
                    modpacks[current].state = progress >= 1 ? .installed : .installing(progress)
                }
            }
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

// MARK: - 页面内演示数据（整合包，后端暂不支持）

/// 整合包演示数据：真实后端只处理 Mojang 官方版本，整合包安装仅做 UI 演示。
private enum DemoModpacks {
    static let items: [LauncherVersionItem] = [
        LauncherVersionItem(
            id: "modpack-bettermc",
            version: "Better MC · 群岛",
            kind: .modpack,
            released: "2026-09-18",
            size: "2.4 GB",
            note: "轻量生存整合包 · 128 个模组",
            state: .installing(0.42)
        ),
        LauncherVersionItem(
            id: "modpack-atm10",
            version: "All the Mods 10",
            kind: .modpack,
            released: "2026-09-05",
            size: "6.8 GB",
            note: "科技整合 · 412 个模组 · 建议 8 GB 内存",
            state: .available
        ),
        LauncherVersionItem(
            id: "modpack-rlcraft",
            version: "RLCraft · 硬核生存",
            kind: .modpack,
            released: "2026-08-21",
            size: "4.2 GB",
            note: "生存挑战 · 210 个模组 · 极高难度",
            state: .installed
        )
    ]
}
