import Foundation
import SwiftUI

/// 下载页：页内三个分区（版本库 / 整合包 / 下载任务），最小窗口下无需滚动。
public struct DownloadPage: View {
    @State private var section = "versions"

    @State private var searchText = ""
    @State private var filter: VersionFilter = .all
    @State private var sortMode: SortMode = .newest
    @State private var versions: [LauncherVersionItem] = LauncherDemoData.versions + DemoModpacks.items

    @State private var pausedTaskIDs: Set<String> = []
    @State private var cancelledTaskIDs: Set<String> = []

    @State private var usedGB: Double = 14.9
    @State private var isCleaning = false
    @State private var didClean = false
    @State private var downloadSource = "official"
    @State private var autoCleanOldVersions = true

    @State private var refreshed = false
    @State private var folderOpened = false
    @State private var filterHint: String?
    @State private var importHint: String?

    public init() {}

    public var body: some View {
        LauncherAppPage {
            LauncherPageHeader(title: "下载", subtitle: "安装游戏版本、加载器与整合包") {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherButton(
                        folderOpened ? "已定位" : "打开文件夹",
                        systemImage: folderOpened ? "checkmark" : "folder",
                        variant: .secondary,
                        size: .small
                    ) {
                        openFolder()
                    }
                    LauncherButton(
                        refreshed ? "已刷新" : "刷新列表",
                        systemImage: refreshed ? "checkmark" : "arrow.clockwise",
                        variant: .secondary,
                        size: .small
                    ) {
                        refreshList()
                    }
                }
            }
            .padding(.bottom, LauncherSpace.xxs)

            LauncherSectionLayout {
                LauncherSectionRail(items: sections, selection: $section, header: nil)
            } content: {
                sectionContent
            }
        }
    }

    // MARK: - 分区

    private var sections: [LauncherSectionItem] {
        [
            LauncherSectionItem(
                id: "versions",
                title: "版本库",
                systemImage: "square.stack.3d.up.fill",
                badge: "\(versionItems.count)"
            ),
            LauncherSectionItem(
                id: "modpacks",
                title: "整合包",
                systemImage: "shippingbox.fill",
                badge: "\(modpackItems.count)"
            ),
            LauncherSectionItem(
                id: "tasks",
                title: "下载任务",
                systemImage: "arrow.down.circle.fill",
                badge: "\(visibleTasks.count)"
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

    // MARK: - 分区一：版本库

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            versionToolbar
            versionList
        }
    }

    /// 搜索 / 类型筛选 / 排序：只在版本库分区出现一次。
    private var versionToolbar: some View {
        HStack(spacing: LauncherSpace.md) {
            LauncherSearchField(text: $searchText, placeholder: "搜索版本号或加载器")
                .frame(width: 220)

            HStack(spacing: LauncherSpace.sm) {
                ForEach(VersionFilter.allCases) { option in
                    LauncherChip(option.rawValue, isSelected: filter == option) {
                        withAnimation(LauncherMotion.spring) {
                            filter = option
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
                        LauncherBadge(
                            refreshed ? "已刷新" : "\(visibleVersions.count) 个",
                            tone: refreshed ? .success : .neutral
                        )
                    )
                )

                if visibleVersions.isEmpty {
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
                        ForEach(visibleVersions) { item in
                            versionRow(item)
                        }
                    }
                    .launcherAnimation(LauncherMotion.spring, value: versions)
                }

                if let filterHint {
                    Text(filterHint)
                        .textStyle(.micro, tone: .tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LauncherDivider()

                HStack(spacing: LauncherSpace.sm) {
                    LauncherStatusDot(tone: .success)
                    Text("版本清单已同步 · 最近检查 今天 10:32")
                        .textStyle(.micro, tone: .tertiary)
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherMonoText(LauncherDemoData.versionDirectory, tone: .tertiary, size: 10)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func versionRow(_ item: LauncherVersionItem) -> some View {
        LauncherListRow(
            title: item.version,
            subtitle: "\(item.released) · \(item.size) · \(item.note)",
            systemImage: icon(for: item.kind),
            badge: item.kind.rawValue,
            accessory: AnyView(statusAccessory(for: item))
        )
    }

    /// 行内三态：未安装 → 安装按钮；安装中 → 进度条；已安装 → 次要按钮。
    @ViewBuilder
    private func statusAccessory(for item: LauncherVersionItem) -> some View {
        switch item.state {
        case .available:
            LauncherButton(
                "安装",
                systemImage: "arrow.down.circle",
                variant: .primary,
                size: .small
            ) {
                startInstall(item.id)
            }
        case .installing(let progress):
            LauncherProgressBar(value: progress)
                .frame(width: 90)
        case .installed:
            LauncherButton(
                "已安装",
                systemImage: "checkmark",
                variant: .secondary,
                size: .small,
                isDisabled: true
            ) {}
        }
    }

    // MARK: - 分区二：整合包

    private var modpackSection: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            LauncherSectionHeader(
                title: "整合包",
                subtitle: "\(modpackItems.count) 个整合包 · 安装过程为本地演示",
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
                ForEach(modpackItems) { item in
                    modpackCard(item)
                }
            }
            .launcherAnimation(LauncherMotion.spring, value: versions)

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

    /// 整合包卡片的三态：安装 / 进度 / 已安装。
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
                startInstall(item.id)
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

    // MARK: - 分区三：下载任务

    private var taskSection: some View {
        HStack(alignment: .top, spacing: LauncherSpace.md) {
            downloadQueueCard
                .frame(maxWidth: .infinity)

            VStack(spacing: LauncherSpace.md) {
                diskCard
                sourceCard
            }
            .frame(width: 280)
        }
    }

    private var downloadQueueCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "下载队列",
                    subtitle: queueSubtitle,
                    accessory: AnyView(
                        HStack(spacing: LauncherSpace.sm) {
                            LauncherBadge(queueBadgeText, tone: queueBadgeTone)
                            LauncherButton(
                                "清空",
                                variant: .ghost,
                                size: .small,
                                isDisabled: visibleTasks.isEmpty
                            ) {
                                clearQueue()
                            }
                        }
                    )
                )

                if visibleTasks.isEmpty {
                    LauncherEmptyState(
                        systemImage: "checkmark.circle",
                        title: "下载队列为空",
                        message: "所有任务都已完成或被取消。",
                        actionTitle: "恢复演示任务",
                        onAction: {
                            withAnimation(LauncherMotion.spring) {
                                cancelledTaskIDs.removeAll()
                                pausedTaskIDs.removeAll()
                            }
                        }
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: LauncherSpace.md) {
                        ForEach(visibleTasks) { task in
                            queueRow(task)
                        }
                    }

                    LauncherDivider()

                    HStack(spacing: LauncherSpace.sm) {
                        LauncherMonoText(queueFooter, tone: .tertiary, size: 10)
                        Spacer(minLength: LauncherSpace.sm)
                        LauncherStatusDot(tone: .success)
                        Text("网络稳定")
                            .textStyle(.micro, tone: .tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func queueRow(_ task: LauncherDownloadTask) -> some View {
        let isPaused = pausedTaskIDs.contains(task.id)
        return VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            HStack(spacing: LauncherSpace.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    Text(task.detail)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: LauncherSpace.sm)

                VStack(alignment: .trailing, spacing: 1) {
                    LauncherMonoText(
                        isPaused ? "已暂停" : task.speed,
                        tone: isPaused ? .warning : .tertiary,
                        size: 10
                    )
                    LauncherMonoText(task.total, tone: .tertiary, size: 10)
                }

                if task.progress != nil {
                    LauncherIconButton(
                        systemImage: isPaused ? "play.fill" : "pause.fill",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: isPaused ? "继续 \(task.title)" : "暂停 \(task.title)"
                    ) {
                        togglePause(task.id)
                    }
                }

                LauncherIconButton(
                    systemImage: "xmark",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: "取消 \(task.title)"
                ) {
                    cancel(task)
                }
            }

            LauncherProgressBar(value: task.progress, tone: isPaused ? .warning : .accent)
        }
    }

    private var diskCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "磁盘占用",
                    subtitle: "版本与资源",
                    accessory: AnyView(
                        LauncherBadge(
                            didClean ? "已释放 1.2 GB" : "空间充足",
                            tone: didClean ? .success : .neutral
                        )
                    )
                )

                LauncherProgressBar(
                    value: usedGB / 99.1,
                    label: "已用 \(usedSpaceText) / 99.1 GB"
                )

                VStack(spacing: LauncherSpace.xs) {
                    LauncherKeyValueRow(key: "可用空间", value: availableSpaceText)
                    LauncherKeyValueRow(key: "已安装实例", value: "\(LauncherDemoData.instances.count) 个")
                }

                LauncherButton(
                    isCleaning ? "正在清理…" : "清理缓存",
                    systemImage: "trash",
                    variant: .secondary,
                    size: .small,
                    isLoading: isCleaning,
                    isFullWidth: true
                ) {
                    cleanCache()
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
                    selection: $downloadSource,
                    placeholder: "选择下载源"
                )

                LauncherToggle(
                    "自动清理旧版本",
                    isOn: $autoCleanOldVersions,
                    subtitle: "只保留最近两个版本文件"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 版本数据

    /// 版本库条目：排除整合包。
    private var versionItems: [LauncherVersionItem] {
        versions.filter { $0.kind != .modpack }
    }

    /// 整合包条目：由现有演示数据与页面内演示数据组成。
    private var modpackItems: [LauncherVersionItem] {
        versions.filter { $0.kind == .modpack }
    }

    /// 当前可见版本：类型 → 搜索 → 排序。
    private var visibleVersions: [LauncherVersionItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = versionItems.filter { item in
            guard filter.matches(item.kind) else { return false }
            guard !query.isEmpty else { return true }
            return item.version.lowercased().contains(query)
                || item.note.lowercased().contains(query)
                || item.kind.rawValue.contains(query)
        }

        switch sortMode {
        case .newest:
            return filtered.sorted { $0.released > $1.released }
        case .version:
            return filtered.sorted {
                $0.version.compare($1.version, options: .numeric) == .orderedDescending
            }
        case .size:
            return filtered.sorted { sizeInMB($0.size) > sizeInMB($1.size) }
        }
    }

    private var versionListSubtitle: String {
        let installedCount = versionItems.filter { $0.state == .installed }.count
        let shown = visibleVersions.count
        if shown != versionItems.count {
            return "筛选出 \(shown) 个 / 共 \(versionItems.count) 个 · 已安装 \(installedCount) 个"
        }
        return "共 \(versionItems.count) 个 · 已安装 \(installedCount) 个 · \(sortMode.rawValue)"
    }

    private var sortOptions: [LauncherSegment<SortMode>] {
        SortMode.allCases.map { LauncherSegment(id: $0, title: $0.rawValue) }
    }

    private var sourceOptions: [LauncherSegment<String>] {
        [
            LauncherSegment(id: "official", title: "官方源 · 上海", systemImage: "globe"),
            LauncherSegment(id: "mirror", title: "镜像源 · 新加坡", systemImage: "bolt.fill")
        ]
    }

    private var sourceDetail: String {
        downloadSource == "mirror"
            ? "镜像源 · 新加坡节点 · 64 ms"
            : "官方源 · 上海节点 · 32 ms"
    }

    /// 把 "1.2 GB" / "18 MB" 归一化成 MB，用于大小排序。
    private func sizeInMB(_ text: String) -> Double {
        let parts = text.split(separator: " ")
        guard let value = Double(parts.first ?? "") else { return 0 }
        let isGB = parts.count > 1 && parts[1].uppercased() == "GB"
        return isGB ? value * 1024 : value
    }

    private func icon(for kind: LauncherVersionItem.Kind) -> String {
        switch kind {
        case .release: return "globe"
        case .snapshot: return "flask"
        case .loader: return "wrench.and.screwdriver"
        case .modpack: return "shippingbox"
        }
    }

    // MARK: - 队列数据

    private var visibleTasks: [LauncherDownloadTask] {
        LauncherDemoData.downloadTasks.filter { !cancelledTaskIDs.contains($0.id) }
    }

    private var pausedCount: Int {
        visibleTasks.filter { pausedTaskIDs.contains($0.id) }.count
    }

    private var queueSubtitle: String {
        if visibleTasks.isEmpty { return "暂无任务" }
        if pausedCount > 0 { return "\(visibleTasks.count) 个任务 · \(pausedCount) 个已暂停" }
        return "\(visibleTasks.count) 个任务进行中"
    }

    private var queueBadgeText: String {
        if visibleTasks.isEmpty { return "空闲" }
        return pausedCount > 0 ? "已暂停 \(pausedCount)" : "进行中"
    }

    private var queueBadgeTone: LauncherBadgeTone {
        if visibleTasks.isEmpty { return .neutral }
        return pausedCount > 0 ? .warning : .accent
    }

    private var queueFooter: String {
        let values = visibleTasks.compactMap { $0.progress }
        guard !values.isEmpty else { return "等待任务开始" }
        let average = Int((values.reduce(0, +) / Double(values.count) * 100).rounded())
        return "平均进度 \(average)% · 剩余 2 分 12 秒"
    }

    // MARK: - 磁盘文案

    private var usedSpaceText: String {
        String(format: "%.1f GB", usedGB)
    }

    private var availableSpaceText: String {
        String(format: "%.1f GB", max(0, 99.1 - usedGB))
    }

    // MARK: - 交互

    /// 点击安装：本地演示状态机，每 0.6s 推进 15%，到 100% 变已安装。
    private func startInstall(_ id: String) {
        guard let index = versions.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(LauncherMotion.spring) {
            versions[index].state = .installing(0)
        }

        Task { @MainActor in
            var progress = 0.0
            while progress < 1 {
                do {
                    try await Task.sleep(nanoseconds: 600_000_000)
                } catch {
                    return
                }
                progress = min(1, progress + 0.15)
                guard let current = versions.firstIndex(where: { $0.id == id }) else { return }
                withAnimation(LauncherMotion.smooth) {
                    versions[current].state = progress >= 1 ? .installed : .installing(progress)
                }
            }
        }
    }

    private func togglePause(_ id: String) {
        withAnimation(LauncherMotion.smooth) {
            if pausedTaskIDs.contains(id) {
                pausedTaskIDs.remove(id)
            } else {
                pausedTaskIDs.insert(id)
            }
        }
    }

    private func cancel(_ task: LauncherDownloadTask) {
        withAnimation(LauncherMotion.spring) {
            cancelledTaskIDs.insert(task.id)
            pausedTaskIDs.remove(task.id)
        }
    }

    private func clearQueue() {
        withAnimation(LauncherMotion.spring) {
            for task in visibleTasks {
                cancelledTaskIDs.insert(task.id)
            }
            pausedTaskIDs.removeAll()
        }
    }

    private func cleanCache() {
        guard !isCleaning else { return }
        isCleaning = true
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_200_000_000)
            } catch {
                return
            }
            withAnimation(LauncherMotion.spring) {
                usedGB = 13.7
                didClean = true
                isCleaning = false
            }
        }
    }

    private func refreshList() {
        withAnimation(LauncherMotion.spring) {
            refreshed = true
        }
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_800_000_000)
            } catch {
                return
            }
            withAnimation(LauncherMotion.smooth) {
                refreshed = false
            }
        }
    }

    private func openFolder() {
        withAnimation(LauncherMotion.spring) {
            folderOpened = true
        }
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_800_000_000)
            } catch {
                return
            }
            withAnimation(LauncherMotion.smooth) {
                folderOpened = false
            }
        }
    }

    private func showImportHint() {
        withAnimation(LauncherMotion.smooth) {
            importHint = "演示：把 .zip 整合包拖入窗口，或从模组站一键导入"
        }
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 2_600_000_000)
            } catch {
                return
            }
            withAnimation(LauncherMotion.smooth) {
                importHint = nil
            }
        }
    }

    private func resetFilters() {
        withAnimation(LauncherMotion.spring) {
            searchText = ""
            filter = .all
        }
        withAnimation(LauncherMotion.smooth) {
            filterHint = "筛选已重置"
        }
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 2_600_000_000)
            } catch {
                return
            }
            withAnimation(LauncherMotion.smooth) {
                filterHint = nil
            }
        }
    }
}

// MARK: - 页面内选项枚举

/// 版本库筛选（全部 / 正式版 / 快照 / 加载器）；整合包单独成区。
private enum VersionFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case release = "正式版"
    case snapshot = "快照"
    case loader = "加载器"

    var id: String { rawValue }

    func matches(_ kind: LauncherVersionItem.Kind) -> Bool {
        self == .all || rawValue == kind.rawValue
    }
}

/// 版本列表排序方式。
private enum SortMode: String, CaseIterable, Hashable {
    case newest = "按发布时间"
    case version = "按版本号"
    case size = "按大小"
}

// MARK: - 页面内演示数据（不改动 LauncherDemoData）

/// 额外两条整合包演示数据，与现有 Better MC 一起构成整合包分区。
private enum DemoModpacks {
    static let items: [LauncherVersionItem] = [
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
