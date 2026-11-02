import Foundation
import SwiftUI

// MARK: - 展示格式化

/// DSH 下载页的展示格式化：版本大小 / 日期 / 星数 / 路径等。
/// 全部是纯函数（固定 locale 与时区），便于单元测试且不受系统语言影响。
public enum DSHDownloadFormat {
    /// 字节大小：B / KB / MB / GB，保留一位小数（GB 两位）。
    public static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        guard bytes > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 { return "\(bytes) B" }
        let format = index >= 3 ? "%.2f %@" : "%.1f %@"
        return String(format: format, value, units[index])
    }

    /// 日期：`yyyy-MM-dd`（UTC，固定 locale，避免测试与展示受系统时区影响）。
    public static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dateFormatter.string(from: date)
    }

    /// 加载源里 `added` / `updated` 这类字符串日期（`2026-11-01`）。
    public static func rawDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        return String(raw.prefix(10))
    }

    /// 星数：1.2k / 3.4m，未知返回「—」。
    public static func stars(_ count: Int?) -> String {
        guard let count else { return "—" }
        guard count > 0 else { return "0" }
        if count >= 1_000_000 { return String(format: "%.1fm", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        return "\(count)"
    }

    /// 把主目录前缀换成 `~`，避免面板里出现过长的绝对路径。
    public static func shortHomePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// 计数文案：`12 个`。
    public static func count(_ value: Int, unit: String = "个") -> String {
        "\(value) \(unit)"
    }

    /// 固定 UTC 的日期格式化器（每次创建开销可接受，且避免静态可变状态）。
    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

// MARK: - 跨页动作

/// 其它页面（启动页空态 / 插件入口）跳到下载页时携带的一次性动作。
/// 纯映射，便于单测；页面只负责应用并清空 `pendingDownloadAction`。
public enum DSHDownloadDeepLink: Equatable, Sendable {
    case versions
    case plugins

    /// 动作字符串 → 目标分类；未知动作返回 nil（不消费，留给别的页面处理）。
    public static func destination(for action: String?) -> DSHDownloadDeepLink? {
        switch action {
        case "dsh-versions": return .versions
        case "dsh-plugins": return .plugins
        default: return nil
        }
    }
}

// MARK: - 版本分组

/// DSH 版本列表的分组结果：已安装的排前面，其余按版本号倒序。
public struct DSHVersionPartition: Equatable, Sendable {
    /// 已安装的远端版本（按版本号倒序）。
    public let installed: [DSHVersionInfo]
    /// 未安装的远端版本（按版本号倒序）。
    public let available: [DSHVersionInfo]
    /// 远端版本总数。
    public let total: Int

    public init(installed: [DSHVersionInfo], available: [DSHVersionInfo], total: Int) {
        self.installed = installed
        self.available = available
        self.total = total
    }

    /// 展示顺序：已安装在前，其后是未安装版本。
    public var displayOrder: [DSHVersionInfo] { installed + available }

    /// 是否还有未安装的版本。
    public var hasAvailable: Bool { !available.isEmpty }
}

/// DSH 下载页的列表逻辑（分页 / 标签 / 分类名），全部是纯函数。
public enum DSHDownloadList {
    /// 版本分区：已安装优先，同组内按版本号倒序。
    public static func partition(
        _ versions: [DSHVersionInfo],
        installedIDs: Set<String>
    ) -> DSHVersionPartition {
        let installedVersions = versions
            .filter { installedIDs.contains($0.version) }
            .sorted { DSHVersionComparator.isNewer($0.version, than: $1.version) }
        let availableVersions = versions
            .filter { !installedIDs.contains($0.version) }
            .sorted { DSHVersionComparator.isNewer($0.version, than: $1.version) }
        return DSHVersionPartition(
            installed: installedVersions,
            available: availableVersions,
            total: versions.count
        )
    }

    /// 版本标签：优先用版本自带的 distTags，其次从目录的 dist-tags 反查（latest / next / alpha…）。
    public static func versionTags(_ info: DSHVersionInfo, catalog: DSHVersionCatalog?) -> [String] {
        if !info.distTags.isEmpty { return info.distTags }
        guard let catalog else { return [] }
        return catalog.distTags
            .filter { $0.value == info.version }
            .map(\.key)
            .sorted()
    }

    /// 截断展示（快照模式 / 首屏），`limit <= 0` 视为不截断。
    public static func visible<T>(_ items: [T], limit: Int) -> [T] {
        guard limit > 0 else { return items }
        return Array(items.prefix(limit))
    }

    /// 插件分类名：命中分类表用中文名，未知分类原样返回。
    public static func categoryTitle(_ id: String?, categories: [DSHPluginCategory]) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return categories.first { $0.id == id }?.title ?? id
    }

    /// 能力标签展示（最多 `limit` 个，其余由页面显示 +N）。
    public static func capabilities(_ entry: DSHPluginEntry, limit: Int = 3) -> [String] {
        guard limit > 0 else { return [] }
        return Array(entry.capabilities.prefix(limit))
    }

    /// 能力标签总数。
    public static func capabilityCount(_ entry: DSHPluginEntry) -> Int {
        entry.capabilities.count
    }
}

// MARK: - 运行环境

/// Node / 包管理器检测结果的展示快照。
public struct DSHEnvironmentSnapshot: Equatable, Sendable {
    /// 是否真正执行过检测（快照模式 / 首帧为 false）。
    public let isProbed: Bool
    public let hasNode: Bool
    public let packageManagerName: String?
    /// 一行环境摘要（来自 `DSHVersionStore.environmentText`）。
    public let detailText: String

    public init(isProbed: Bool, hasNode: Bool, packageManagerName: String?, detailText: String) {
        self.isProbed = isProbed
        self.hasNode = hasNode
        self.packageManagerName = packageManagerName
        self.detailText = detailText
    }

    /// 是否具备安装 DSH 的完整环境。
    public var isReady: Bool { hasNode && packageManagerName != nil }

    /// 未检测时的兜底说明（不是错误，只是还没探测）。
    public static let notProbed = DSHEnvironmentSnapshot(
        isProbed: false,
        hasNode: false,
        packageManagerName: nil,
        detailText: "启动器运行时会检测 Node.js 与包管理器"
    )

    /// 从版本 store 读取真实环境（会 spawn 一次登录 shell 探测，只在 task / 手动刷新时调用）。
    @MainActor
    public static func capture(store: DSHVersionStore) -> DSHEnvironmentSnapshot {
        DSHEnvironmentSnapshot(
            isProbed: true,
            hasNode: store.hasNode,
            packageManagerName: store.packageManager?.displayName,
            detailText: store.environmentText
        )
    }
}

/// 环境探测的一次性缓存：离屏快照会反复求值 body，避免每帧 spawn 子进程。
@MainActor
public enum DSHEnvironmentProbe {
    private static var cache: DSHEnvironmentSnapshot?

    /// 进程内只检测一次（快照模式使用；交互模式走页面 task 里的真实刷新）。
    public static func cached(store: DSHVersionStore) -> DSHEnvironmentSnapshot {
        if let cache { return cache }
        let snapshot = DSHEnvironmentSnapshot.capture(store: store)
        cache = snapshot
        return snapshot
    }

    /// 清空缓存（测试 / 环境变化后重测）。
    public static func reset() {
        cache = nil
    }
}

// MARK: - 版本行

/// 版本列表的一行：版本号 + 标签 + 发布时间 / 大小 + 安装 / 卸载 / 使用操作。
struct DSHVersionRowView: View {
    @Environment(\.launcherTheme) private var theme

    let info: DSHVersionInfo
    let tags: [String]
    let installedAt: Date?
    let isInstalled: Bool
    let isSelected: Bool
    let isInstalling: Bool
    let isBusy: Bool
    let isReadOnly: Bool
    let canInstall: Bool
    let installDisabledReason: String?

    let onInstall: () -> Void
    let onUse: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: LauncherSpace.md) {
            icon

            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                HStack(spacing: LauncherSpace.xs) {
                    LauncherMonoText(info.version, tone: .primary, size: 12)
                        .lineLimit(1)
                    ForEach(tags, id: \.self) { tag in
                        LauncherBadge(tag, tone: tagTone(tag))
                    }
                    if info.isPrerelease && tags.isEmpty {
                        LauncherBadge("预发布", tone: .warning)
                    }
                    if isSelected {
                        LauncherBadge("使用中", tone: .accent)
                    } else if isInstalled {
                        LauncherBadge("已安装", tone: .success)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: LauncherSpace.xs) {
                    Text(subtitle)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }

            trailing
        }
        .padding(.horizontal, LauncherSpace.md)
        .frame(minHeight: LauncherControl.large + LauncherSpace.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(isSelected ? theme.colors.accentSoft : theme.colors.surfaceSubtle)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .strokeBorder(
                    isSelected ? theme.colors.accent.opacity(0.3) : theme.colors.stroke,
                    lineWidth: 1
                )
        }
    }

    // MARK: 内部

    private var subtitle: String {
        var parts: [String] = ["发布于 \(DSHDownloadFormat.date(info.publishedAt))"]
        if let size = info.unpackedSize, size > 0 {
            parts.append("解包 \(DSHDownloadFormat.size(size))")
        }
        if let installedAt {
            parts.append("安装于 \(DSHDownloadFormat.date(installedAt))")
        }
        return parts.joined(separator: " · ")
    }

    private var icon: some View {
        Image(systemName: info.isPrerelease ? "flask.fill" : "shippingbox.fill")
            .textStyle(.caption, tone: isInstalled ? .accent : .secondary)
            .frame(width: LauncherControl.small, height: LauncherControl.small)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                    .fill(theme.colors.surfaceHover)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailing: some View {
        if isInstalling {
            HStack(spacing: LauncherSpace.xs) {
                LauncherSpinner(size: 14)
                Text("安装中")
                    .textStyle(.micro, tone: .secondary)
            }
        } else if isInstalled {
            HStack(spacing: LauncherSpace.xs) {
                if !isSelected {
                    LauncherButton(
                        "使用",
                        systemImage: "checkmark.circle",
                        variant: .secondary,
                        size: .small,
                        isDisabled: isBusy || isReadOnly
                    ) {
                        onUse()
                    }
                    .launcherTooltip(
                        isReadOnly
                            ? "快照模式不切换版本"
                            : "把这个版本设为当前版本（插件安装到它的 web profile）"
                    )
                }
                LauncherIconButton(
                    systemImage: "trash",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: "卸载 DSH \(info.version)",
                    isDisabled: isBusy || isReadOnly
                ) {
                    onUninstall()
                }
                .launcherTooltip(
                    isReadOnly
                        ? "快照模式不执行卸载"
                        : (isBusy ? "安装任务进行中，暂时不能卸载" : "卸载该版本（只删除安装目录与日志，共享 DSH_HOME 保留）")
                )
            }
        } else {
            LauncherButton(
                "安装",
                systemImage: "arrow.down.circle",
                variant: .primary,
                size: .small,
                isDisabled: isBusy || isReadOnly || !canInstall
            ) {
                onInstall()
            }
            .launcherTooltip(
                isReadOnly
                    ? "快照模式不执行安装"
                    : (isBusy
                        ? "已有安装任务在进行"
                        : (canInstall ? "安装 DSH \(info.version) 到本地" : (installDisabledReason ?? "当前环境不可安装")))
            )
        }
    }

    private func tagTone(_ tag: String) -> LauncherBadgeTone {
        switch tag.lowercased() {
        case "latest": return .accent
        case "next": return .info
        case "alpha", "beta", "rc": return .warning
        default: return .neutral
        }
    }
}

// MARK: - 插件卡片

/// 插件市场的一条插件：标题 / 作者 / 分类 / 中文描述 / 星数 / npm 包名 / 能力标签，
/// 点击展开完整描述与链接。
struct DSHPluginCardView: View {
    @Environment(\.launcherTheme) private var theme

    let entry: DSHPluginEntry
    let categoryTitle: String?
    let isInstalled: Bool
    let isExpanded: Bool
    let isBusy: Bool
    let isReadOnly: Bool
    let canInstall: Bool
    let installDisabledReason: String?

    let onToggle: () -> Void
    let onInstall: () -> Void
    let onRemove: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            header
            metaRow
            if !entry.descriptionText.isEmpty {
                Text(entry.descriptionText)
                    .textStyle(.micro, tone: .secondary)
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isExpanded {
                expandedDetail
            } else if !entry.capabilities.isEmpty {
                capabilityRow
            }
        }
        .padding(LauncherSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(isExpanded ? theme.colors.surfaceHover : theme.colors.surfaceSubtle)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .strokeBorder(
                    isExpanded ? theme.colors.strokeStrong : theme.colors.stroke,
                    lineWidth: 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous))
        .onTapGesture(perform: onToggle)
    }

    // MARK: 内部

    private var header: some View {
        HStack(spacing: LauncherSpace.xs) {
            Text(entry.name)
                .textStyle(.bodyStrong)
                .lineLimit(1)
            if let categoryTitle {
                LauncherBadge(categoryTitle, tone: .neutral)
            }
            if isInstalled {
                LauncherBadge("已安装", tone: .success)
            }
            Spacer(minLength: LauncherSpace.xs)
            if let stars = entry.stars {
                HStack(spacing: LauncherSpace.xxs) {
                    Image(systemName: "star.fill")
                        .textStyle(.micro, tone: .warning)
                    LauncherMonoText(DSHDownloadFormat.stars(stars), tone: .tertiary, size: 10)
                }
                .accessibilityLabel("\(stars) 星")
            }
            installButton
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .textStyle(.micro, tone: .tertiary)
                .frame(width: LauncherSpace.lg)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var installButton: some View {
        if isBusy {
            LauncherSpinner(size: 12)
        } else if isInstalled {
            LauncherButton(
                "卸载",
                systemImage: "trash",
                variant: .ghost,
                size: .small,
                isDisabled: isReadOnly
            ) {
                onRemove()
            }
            .launcherTooltip(isReadOnly ? "快照模式不执行卸载" : "从 launcher 共享 web profile 卸载该插件")
        } else {
            LauncherButton(
                "安装",
                systemImage: "arrow.down.circle",
                variant: .secondary,
                size: .small,
                isDisabled: !canInstall || isReadOnly
            ) {
                onInstall()
            }
            .launcherTooltip(
                isReadOnly ? "快照模式不执行安装" : (installDisabledReason ?? "安装到 launcher 共享 web profile")
            )
        }
    }

    private var metaRow: some View {
        HStack(spacing: LauncherSpace.xs) {
            Text(entry.owner)
                .textStyle(.micro, tone: .tertiary)
                .lineLimit(1)
            if let npm = entry.npm ?? entry.installSpec {
                Text("·")
                    .textStyle(.micro, tone: .tertiary)
                LauncherMonoText(npm, tone: .tertiary, size: 10)
                    .lineLimit(1)
            }
            if let version = entry.version {
                Text("·")
                    .textStyle(.micro, tone: .tertiary)
                Text(version)
                    .textStyle(.micro, tone: .tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private var capabilityRow: some View {
        HStack(spacing: LauncherSpace.xxs) {
            ForEach(DSHDownloadList.capabilities(entry), id: \.self) { capability in
                LauncherBadge(capability, tone: .info)
            }
            if DSHDownloadList.capabilityCount(entry) > DSHDownloadList.capabilities(entry).count {
                Text("+\(DSHDownloadList.capabilityCount(entry) - DSHDownloadList.capabilities(entry).count)")
                    .textStyle(.micro, tone: .tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            LauncherDivider()
            HStack(spacing: LauncherSpace.lg) {
                LauncherInlineStat("收录", value: DSHDownloadFormat.rawDate(entry.added))
                LauncherInlineStat("星数", value: DSHDownloadFormat.stars(entry.stars), isMono: true)
                LauncherInlineStat("分类", value: categoryTitle ?? "未分类")
                Spacer(minLength: 0)
            }
            if !entry.capabilities.isEmpty {
                capabilityRow
            }
            if let spec = entry.installSpec {
                HStack(spacing: LauncherSpace.xs) {
                    Text("安装标识")
                        .textStyle(.micro, tone: .tertiary)
                    LauncherMonoText(spec, tone: .secondary, size: 10)
                        .lineLimit(1)
                }
            } else {
                Text("该插件没有 npm 包名 / 安装标识，需要按项目页说明手动安装。")
                    .textStyle(.micro, tone: .warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: LauncherSpace.sm) {
                LauncherButton(
                    "打开项目页",
                    systemImage: "safari",
                    variant: .ghost,
                    size: .small
                ) {
                    onOpen()
                }
                LauncherButton(
                    isInstalled ? "卸载插件" : "安装到共享 profile",
                    systemImage: isInstalled ? "trash" : "arrow.down.circle",
                    variant: isInstalled ? .ghost : .secondary,
                    size: .small,
                    isDisabled: isBusy || isReadOnly || (!isInstalled && !canInstall)
                ) {
                    if isInstalled {
                        onRemove()
                    } else {
                        onInstall()
                    }
                }
                .launcherTooltip(
                    isReadOnly
                        ? "快照模式不执行插件操作"
                        : (isBusy
                            ? "插件操作进行中"
                            : (isInstalled ? "从共享 web profile 卸载" : (installDisabledReason ?? "安装到 launcher 共享 web profile")))
                )
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 安装进度卡

/// 安装 / 插件操作中的进度卡：阶段 + 不确定进度条 + 日志尾部 + 取消按钮。
struct DSHProgressCard: View {
    @Environment(\.launcherTheme) private var theme

    let title: String
    let phase: String
    let logLines: [String]
    let onCancel: () -> Void

    var body: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherSpinner(size: 14)
                    Text(title)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherButton(
                        "取消",
                        systemImage: "xmark",
                        variant: .secondary,
                        size: .small
                    ) {
                        onCancel()
                    }
                    .launcherTooltip("终止当前命令并清理半成品")
                }

                LauncherProgressBar(value: nil, label: phase, height: 4)

                if !logLines.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                            LauncherMonoText(line, tone: .tertiary, size: 10)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(LauncherSpace.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                            .fill(theme.colors.surfaceSubtle)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                            .strokeBorder(theme.colors.stroke, lineWidth: 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
