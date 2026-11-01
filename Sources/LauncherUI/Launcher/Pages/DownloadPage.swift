import Foundation
import SwiftUI

/// 下载页：搜索筛选、版本列表（安装状态模拟）、右侧下载队列 / 磁盘占用 / 下载源。
public struct DownloadPage: View {
    @State private var searchText = ""
    @State private var filter: VersionFilter = .all
    @State private var sortMode: SortMode = .newest
    @State private var versions: [LauncherVersionItem] = LauncherDemoData.versions

    @State private var pausedTaskIDs: Set<String> = []
    @State private var cancelledTaskIDs: Set<String> = []

    @State private var usedGB: Double = 14.9
    @State private var isCleaning = false
    @State private var didClean = false
    @State private var downloadSource = "official"
    @State private var autoCleanOldVersions = true

    @State private var refreshed = false
    @State private var actionHint: String?

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
                        showHint("演示：这里会用访达打开 \(LauncherDemoData.versionDirectory)")
                    }
                    LauncherButton(
                        "刷新列表",
                        systemImage: "arrow.clockwise",
                        variant: .secondary,
                        size: .small
                    ) {
                        refreshList()
                    }
                }
            }
            .padding(.bottom, LauncherSpace.xxs)

            toolbar

            HStack(alignment: .top, spacing: LauncherSpace.lg) {
                versionList
                    .frame(maxWidth: .infinity)

                rightRail
            }
        }
    }

    // MARK: - 搜索 / 筛选 / 排序

    private var toolbar: some View {
        HStack(spacing: LauncherSpace.md) {
            LauncherSearchField(text: $searchText, placeholder: "搜索版本号、加载器或整合包")
                .frame(width: 250)

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
                .frame(width: 168)
        }
    }

    // MARK: - 版本列表

    private var versionList: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "版本列表",
                    subtitle: listSubtitle,
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

                if let actionHint {
                    Text(actionHint)
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

    /// 状态区：未安装 → 安装按钮；安装中 → 进度条；已安装 → 次要按钮。
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

    // MARK: - 右栏

    private var rightRail: some View {
        VStack(spacing: LauncherSpace.md) {
            downloadQueueCard
            diskCard
            sourceCard
        }
        .frame(width: 318)
    }

    private var downloadQueueCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "下载队列",
                    subtitle: queueSubtitle,
                    accessory: AnyView(
                        LauncherBadge(queueBadgeText, tone: queueBadgeTone)
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
                    subtitle: "游戏目录 · 版本与资源",
                    accessory: AnyView(
                        LauncherBadge(
                            didClean ? "已释放 1.2 GB" : "空间充足",
                            tone: didClean ? .success : .neutral
                        )
                    )
                )

                LauncherProgressBar(
                    value: usedGB / 99.1,
                    label: "已用 \(usedSpaceText) / 共 99.1 GB"
                )

                VStack(spacing: LauncherSpace.xs) {
                    LauncherKeyValueRow(key: "已用空间", value: usedSpaceText)
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

    // MARK: - 过滤 / 排序

    /// 当前可见版本：筛选 → 搜索 → 排序。
    private var visibleVersions: [LauncherVersionItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = versions.filter { item in
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

    private var listSubtitle: String {
        let installedCount = versions.filter { $0.state == .installed }.count
        let shown = visibleVersions.count
        if shown != versions.count {
            return "筛选出 \(shown) 个 / 共 \(versions.count) 个 · 已安装 \(installedCount) 个"
        }
        return "共 \(versions.count) 个 · 已安装 \(installedCount) 个 · \(sortMode.rawValue)"
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

    // MARK: - 队列

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
        showHint("已刷新版本列表 · 当前 \(visibleVersions.count) 个版本可安装")
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

    private func resetFilters() {
        withAnimation(LauncherMotion.spring) {
            searchText = ""
            filter = .all
        }
        showHint("筛选已重置")
    }

    /// 短暂操作提示：只在实际点击后出现，离屏截图默认不占位。
    private func showHint(_ text: String) {
        withAnimation(LauncherMotion.smooth) {
            actionHint = text
        }
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 2_600_000_000)
            } catch {
                return
            }
            withAnimation(LauncherMotion.smooth) {
                if actionHint == text { actionHint = nil }
            }
        }
    }
}

// MARK: - 页面内选项枚举

/// 版本类型筛选（全部 / 正式版 / 快照 / 加载器 / 整合包）。
private enum VersionFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case release = "正式版"
    case snapshot = "快照"
    case loader = "加载器"
    case modpack = "整合包"

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
