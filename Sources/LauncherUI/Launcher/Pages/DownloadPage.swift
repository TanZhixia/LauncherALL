import AppKit
import Foundation
import SwiftUI

/// 下载页：真实 Mojang 版本清单 + 真实安装进度；页内三个分区，最小窗口下无需滚动。
public struct DownloadPage: View {
    @Environment(LauncherEngine.self) private var engine

    @State private var section = "versions"

    // 版本库：真实清单、筛选与排序
    @State private var searchText = ""
    @State private var typeFilter: VersionTypeFilter = DownloadPage.defaultTypeFilter
    @State private var sortMode: VersionSort = .newest
    @State private var manifest: VersionManifest? = DownloadPage.launchManifestCache
    @State private var isLoadingManifest = DownloadPage.launchManifestCache == nil
    @State private var manifestError: String?
    @State private var lastInstallID: String?

    // 整合包：仍为页面内演示数据（后端暂不支持整合包安装）
    @State private var modpacks: [LauncherVersionItem] = DemoModpacks.items
    @State private var importHint: String?

    // 下载任务分区
    @State private var isRefreshingInstalled = false

    /// 首帧快速展示：读取与 MojangManifestService 相同位置的清单缓存，随后仍异步刷新。
    private static let launchManifestCache: VersionManifest? = readCachedManifest()

    /// 默认筛选跟随设置里的更新渠道：快照渠道默认看快照，其余渠道默认看正式版。
    private static let defaultTypeFilter: VersionTypeFilter =
        LauncherSettings.shared.updateChannel == "snapshot" ? .snapshot : .release

    /// 列表一次最多展示的行数，保证最小窗口不出现纵向滚动。
    private let maxVisibleVersions = 6

    public init() {}

    public var body: some View {
        LauncherAppPage {
            LauncherPageHeader(title: "下载", subtitle: "安装游戏版本、加载器与整合包") {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherButton(
                        "打开文件夹",
                        systemImage: "folder",
                        variant: .secondary,
                        size: .small
                    ) {
                        NSWorkspace.shared.open(engine.settings.resolvedGameDirectory)
                    }
                    LauncherButton(
                        "刷新列表",
                        systemImage: "arrow.clockwise",
                        variant: .secondary,
                        size: .small,
                        isLoading: isLoadingManifest
                    ) {
                        refreshAll()
                    }
                }
            }
            .padding(.bottom, LauncherSpace.xxs)

            LauncherSectionLayout {
                LauncherSectionRail(items: sections, selection: $section, header: "下载")
            } content: {
                sectionContent
            }
        }
        .task {
            if engine.installedVersions.isEmpty {
                await engine.refreshEnvironment()
            }
            await loadManifest()
        }
    }

    // MARK: - 分区

    private var sections: [LauncherSectionItem] {
        [
            LauncherSectionItem(
                id: "versions",
                title: "版本库",
                systemImage: "square.stack.3d.up.fill",
                badge: manifest.map { "\($0.versions.count)" }
            ),
            LauncherSectionItem(
                id: "modpacks",
                title: "整合包",
                systemImage: "shippingbox.fill",
                badge: "\(modpacks.count)"
            ),
            LauncherSectionItem(
                id: "tasks",
                title: "下载任务",
                systemImage: "arrow.down.circle.fill",
                badge: engine.isBusy ? "1" : nil
            )
        ]
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case "modpacks":
            modpackSection
        case "tasks":
            taskSection
        default:
            versionSection
        }
    }

    // MARK: - 分区一：版本库（真实清单）

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            if manifest == nil {
                manifestPlaceholder
            } else {
                versionToolbar
                versionList
                if let manifestError {
                    LauncherBanner(
                        title: "清单刷新失败，正在使用本地缓存",
                        message: manifestError,
                        tone: .warning,
                        actionTitle: "重试",
                        onAction: { refreshManifest(forceRefresh: true) }
                    )
                }
            }

            if case .failed(let message) = engine.phase, let lastInstallID {
                LauncherBanner(
                    title: "安装失败：\(lastInstallID)",
                    message: message,
                    tone: .danger,
                    actionTitle: "重试",
                    onAction: { install(lastInstallID) }
                )
            }
        }
    }

    /// 加载中 / 首次失败：骨架占位或错误横幅。
    @ViewBuilder
    private var manifestPlaceholder: some View {
        if let manifestError {
            VStack(spacing: LauncherSpace.md) {
                LauncherBanner(
                    title: "无法获取版本清单",
                    message: manifestError,
                    tone: .danger,
                    actionTitle: "重试",
                    onAction: { refreshManifest(forceRefresh: true) }
                )
                Text("版本清单来自 Mojang 官方接口，首次加载需要联网。")
                    .textStyle(.micro, tone: .tertiary)
            }
        } else {
            LauncherCard(level: .regular, padding: LauncherSpace.lg) {
                VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherSpinner(size: 16)
                        Text("正在从 Mojang 获取版本清单…")
                            .textStyle(.micro, tone: .secondary)
                        Spacer(minLength: LauncherSpace.sm)
                        LauncherBadge("12 小时缓存", tone: .neutral)
                    }
                    ForEach(0..<5, id: \.self) { _ in
                        LauncherSkeleton(
                            height: LauncherControl.large,
                            cornerRadius: LauncherRadius.md
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 搜索 / 类型筛选 / 排序：只在版本库分区出现一次。
    private var versionToolbar: some View {
        HStack(spacing: LauncherSpace.md) {
            LauncherSearchField(text: $searchText, placeholder: "搜索版本号")
                .frame(width: 200)

            HStack(spacing: LauncherSpace.sm) {
                ForEach(VersionTypeFilter.allCases) { option in
                    LauncherChip(option.rawValue, isSelected: typeFilter == option) {
                        withAnimation(LauncherMotion.spring) {
                            typeFilter = option
                        }
                    }
                }
            }

            Spacer(minLength: LauncherSpace.sm)

            LauncherDropdown(options: sortOptions, selection: $sortMode, placeholder: "排序")
                .frame(width: 150)
        }
    }

    private var versionList: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "版本列表",
                    subtitle: versionListSubtitle,
                    accessory: AnyView(
                        LauncherBadge("\(displayedVersions.count) 个", tone: .neutral)
                    )
                )

                if displayedVersions.isEmpty {
                    LauncherEmptyState(
                        systemImage: "magnifyingglass",
                        title: "没有匹配的版本",
                        message: "换个关键词，或者把筛选切回「全部」。",
                        actionTitle: "重置筛选",
                        onAction: { resetFilters() }
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: LauncherSpace.xxs) {
                        ForEach(displayedVersions) { version in
                            versionRow(version)
                        }
                    }
                    .launcherAnimation(LauncherMotion.spring, value: engine.phase)
                }

                LauncherDivider()

                HStack(spacing: LauncherSpace.sm) {
                    LauncherMonoText(
                        "显示 \(displayedVersions.count) / 筛选后 \(filteredVersions.count) 个 · 已安装 \(installedIDs.count) 个",
                        tone: .tertiary,
                        size: 10
                    )
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherMonoText("来源：Mojang 官方清单", tone: .tertiary, size: 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func versionRow(_ version: VersionSummary) -> some View {
        LauncherListRow(
            title: version.id,
            subtitle: "发布于 \(releaseDate(version.releaseTime))",
            systemImage: icon(for: version.type),
            badge: typeLabel(version.type),
            accessory: AnyView(statusAccessory(for: version))
        )
    }

    /// 行内状态：安装中显示真实进度；已安装显示禁用按钮；其余显示安装按钮。
    @ViewBuilder
    private func statusAccessory(for version: VersionSummary) -> some View {
        if case .downloading(let versionID, let progress) = engine.phase, versionID == version.id {
            VStack(alignment: .trailing, spacing: LauncherSpace.xxs) {
                Text(progress.phase)
                    .textStyle(.micro, tone: .secondary)
                    .lineLimit(1)
                LauncherProgressBar(value: progress.fraction)
                    .frame(width: 120)
            }
        } else if installedIDs.contains(version.id) {
            LauncherButton(
                "已安装",
                systemImage: "checkmark",
                variant: .secondary,
                size: .small,
                isDisabled: true
            ) {}
        } else {
            LauncherButton(
                "安装",
                systemImage: "arrow.down.circle",
                variant: .primary,
                size: .small,
                isDisabled: engine.isBusy
            ) {
                install(version.id)
            }
        }
    }

    // MARK: - 分区二：整合包

    private var modpackSection: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            LauncherSectionHeader(
                title: "整合包",
                subtitle: "\(modpacks.count) 个整合包 · 安装过程为页面内演示",
                accessory: AnyView(
                    LauncherButton(
                        "导入整合包",
                        systemImage: "shippingbox",
                        variant: .secondary,
                        size: .small
                    ) {
                        showImportHint()
                    }
                )
            )

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

    // MARK: - 分区三：下载任务（真实安装进度）

    private var taskSection: some View {
        HStack(alignment: .top, spacing: LauncherSpace.md) {
            currentTaskCard
                .frame(maxWidth: .infinity)

            VStack(spacing: LauncherSpace.md) {
                diskCard
                sourceCard
            }
            .frame(width: 280)
        }
    }

    private var currentTaskCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "当前安装任务",
                    subtitle: taskSubtitle,
                    accessory: AnyView(LauncherBadge(taskBadgeText, tone: taskBadgeTone))
                )

                taskBody
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var taskBody: some View {
        switch engine.phase {
        case .downloading(let versionID, let progress):
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherMonoText(versionID, tone: .primary, size: 12)
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherMonoText(
                        "\(progress.completed) / \(progress.total) 个文件",
                        tone: .tertiary,
                        size: 10
                    )
                }
                LauncherProgressBar(value: progress.fraction, label: progress.phase)
                HStack(spacing: LauncherSpace.xs) {
                    LauncherStatusDot(tone: .warning)
                    Text("真实下载中 · 耗时取决于网络，请勿退出启动器")
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(2)
                }
            }
        case .preparing(let message):
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                Text(message)
                    .textStyle(.body, tone: .secondary)
                LauncherProgressBar(label: "准备中…")
            }
        case .failed(let message):
            LauncherBanner(
                title: "安装任务失败",
                message: message,
                tone: .danger,
                actionTitle: lastInstallID == nil ? nil : "重试",
                onAction: {
                    if let lastInstallID { install(lastInstallID) }
                }
            )
        default:
            LauncherEmptyState(
                systemImage: "arrow.down.circle",
                title: "当前没有安装任务",
                message: engine.installedVersions.isEmpty
                    ? "去版本库挑选一个版本开始安装。"
                    : "已安装 \(engine.installedVersions.count) 个版本，可以继续安装其他版本。",
                actionTitle: "去版本库",
                onAction: {
                    withAnimation(LauncherMotion.spring) { section = "versions" }
                }
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var diskCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "磁盘占用",
                    subtitle: "游戏目录所在卷",
                    accessory: AnyView(
                        LauncherBadge("\(engine.installedVersions.count) 个版本", tone: .neutral)
                    )
                )

                LauncherProgressBar(value: volumeUsedFraction, label: "可用 \(volumeFreeText)")

                LauncherKeyValueRow(key: "卷容量", value: volumeTotalText)
                LauncherKeyValueRow(key: "游戏目录", value: gameDirectorySummary)

                LauncherButton(
                    isRefreshingInstalled ? "刷新中…" : "刷新已安装",
                    systemImage: "arrow.clockwise",
                    variant: .secondary,
                    size: .small,
                    isLoading: isRefreshingInstalled,
                    isFullWidth: true
                ) {
                    refreshInstalled()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(title: "下载源", subtitle: sourceDetail)

                LauncherDropdown(
                    options: sourceOptions,
                    selection: sourceBinding,
                    placeholder: "选择下载源"
                )

                LauncherToggle(
                    "自动清理旧版本",
                    isOn: autoCleanBinding,
                    subtitle: "安装完成后清理旧版本文件"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 版本数据

    private var installedIDs: Set<String> {
        Set(engine.installedVersions.map(\.id))
    }

    /// 筛选 + 搜索 + 排序后的版本。
    private var filteredVersions: [VersionSummary] {
        guard let manifest else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var items = manifest.versions.filter { version in
            guard typeFilter.matches(version.type) else { return false }
            guard !query.isEmpty else { return true }
            return version.id.lowercased().contains(query)
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

    /// 截断后的展示列表，保证最小窗口不滚动。
    private var displayedVersions: [VersionSummary] {
        Array(filteredVersions.prefix(maxVisibleVersions))
    }

    private var versionListSubtitle: String {
        guard let manifest else { return "正在加载清单" }
        if displayedVersions.count < filteredVersions.count {
            return "Mojang 清单 \(manifest.versions.count) 个 · 当前筛选 \(filteredVersions.count) 个 · 已安装 \(installedIDs.count) 个"
        }
        return "当前筛选 \(filteredVersions.count) 个 · 已安装 \(installedIDs.count) 个"
    }

    private var sortOptions: [LauncherSegment<VersionSort>] {
        VersionSort.allCases.map { LauncherSegment(id: $0, title: $0.rawValue) }
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

    // MARK: - 下载源与磁盘数据

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

    private var autoCleanBinding: Binding<Bool> {
        Binding(
            get: { engine.settings.autoCleanOldVersions },
            set: { engine.settings.autoCleanOldVersions = $0 }
        )
    }

    private var sourceDetail: String {
        engine.settings.downloadSource == "mirror"
            ? "镜像源 · 已写入启动器设置"
            : "官方源 · 已写入启动器设置"
    }

    private var gameDirectorySummary: String {
        let name = engine.settings.resolvedGameDirectory.lastPathComponent
        return name.isEmpty ? engine.settings.resolvedGameDirectory.path : "…/\(name)"
    }

    /// 磁盘卷信息（真实文件系统，同步读取很快）。
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

    // MARK: - 任务状态文案

    private var taskSubtitle: String {
        switch engine.phase {
        case .downloading: return "真实下载 · 文件进度实时更新"
        case .preparing: return "正在准备安装环境"
        case .failed: return "上次任务失败"
        default: return engine.installedVersions.isEmpty ? "尚未安装任何版本" : "空闲"
        }
    }

    private var taskBadgeText: String {
        switch engine.phase {
        case .downloading: return "下载中"
        case .preparing: return "准备中"
        case .failed: return "失败"
        default: return "空闲"
        }
    }

    private var taskBadgeTone: LauncherBadgeTone {
        switch engine.phase {
        case .downloading: return .accent
        case .preparing: return .warning
        case .failed: return .danger
        default: return .neutral
        }
    }

    // MARK: - 交互

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

    /// 调用真实安装：进度由 engine.phase 驱动，安装完成后 engine 会自动刷新已安装列表。
    private func install(_ versionID: String) {
        guard !engine.isBusy else { return }
        lastInstallID = versionID
        Task { @MainActor in
            await engine.install(versionID: versionID)
        }
    }

    private func resetFilters() {
        withAnimation(LauncherMotion.spring) {
            searchText = ""
            typeFilter = .all
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

// MARK: - 页面内选项枚举

/// 版本类型筛选：全部 / 正式版 / 快照 / 远古版本。
private enum VersionTypeFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case release = "正式版"
    case snapshot = "快照"
    case legacy = "远古版"

    var id: String { rawValue }

    func matches(_ type: String) -> Bool {
        switch self {
        case .all: return true
        case .release: return type == "release"
        case .snapshot: return type == "snapshot"
        case .legacy: return type.hasPrefix("old_")
        }
    }
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
