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
    case packs

    /// 动作字符串 → 目标分类；未知动作返回 nil（不消费，留给别的页面处理）。
    public static func destination(for action: String?) -> DSHDownloadDeepLink? {
        switch action {
        case "dsh-versions": return .versions
        case "dsh-plugins": return .plugins
        case "dsh-packs": return .packs
        default: return nil
        }
    }
}

// MARK: - 版本分组

/// DSH 版本列表的分组结果：已安装的排前面，其余按版本号倒序。
public struct DSHVersionPartition: Equatable, Sendable {
    /// 已有实例的远端版本（按版本号倒序）。
    public let installed: [DSHVersionInfo]
    /// 还没有实例的远端版本（按版本号倒序）。
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

/// DSH 下载页的列表逻辑（分区 / 实例分组 / 标签 / 分类名），全部是纯函数。
public enum DSHDownloadList {
    /// 版本分区：已有实例的版本优先，同组内按版本号倒序。
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

    /// 按 DSH 版本号聚合实例（同一版本可以安装多次）。
    public static func instancesByVersion(
        _ instances: [DSHInstalledVersion]
    ) -> [String: [DSHInstalledVersion]] {
        var result: [String: [DSHInstalledVersion]] = [:]
        for instance in instances {
            result[instance.dshVersion, default: []].append(instance)
        }
        for key in result.keys {
            result[key]?.sort { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
        return result
    }

    /// 本地整合包实例（按安装时间倒序）。
    public static func packInstances(_ instances: [DSHInstalledVersion]) -> [DSHInstalledVersion] {
        instances
            .filter(\.isPack)
            .sorted { $0.installedAt > $1.installedAt }
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

    /// 实例的一行描述：`DSH 0.2.1 · 整合包 Foo v1 · 1.2 GB`。
    public static func instanceSummary(_ instance: DSHInstalledVersion) -> String {
        var parts: [String] = ["DSH \(instance.dshVersion)"]
        if instance.isPack {
            var pack = "整合包"
            if let name = instance.packName, !name.isEmpty { pack += " \(name)" }
            if let version = instance.packVersion, !version.isEmpty { pack += " v\(version)" }
            parts.append(pack)
        }
        if let size = instance.sizeBytes, size > 0 {
            parts.append(DSHDownloadFormat.size(size))
        }
        if instance.legacy {
            parts.append("旧版实例")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 整合包 UI 辅助

/// `.dshpack` 整合包相关的展示 / 校验逻辑（纯函数，便于单测）。
public enum DSHDownloadPackUI {
    /// 私有整合包扩展名。
    public static var fileExtension: String { DSHPackFormat.fileExtension }

    /// 导出时默认文件名：`<实例名>.dshpack`，非法文件名字符替换为 `-`。
    public static func exportFileName(_ instanceName: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = instanceName
            .components(separatedBy: banned)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "DSH Pack" : String(cleaned.prefix(80))
        let ext = ".\(fileExtension)"
        return base.lowercased().hasSuffix(ext) ? base : base + ext
    }

    /// 是否是 `.dshpack` 文件。
    public static func isPackFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == fileExtension
    }

    /// 导入时默认实例名（取文件名去掉扩展名）。
    public static func defaultImportName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "DSH 整合包" : String(base.prefix(60))
    }

    /// 整合包操作卡片标题（非进行中返回 nil）。
    public static func busyTitle(_ state: DSHPackState) -> String? {
        switch state {
        case .exporting(let name, _, _): return "正在导出「\(name)」"
        case .importing(let name, _, _): return "正在导入「\(name)」"
        case .idle, .failed: return nil
        }
    }

    /// 整合包操作阶段文案。
    public static func busyPhaseText(_ state: DSHPackState) -> String? {
        switch state {
        case .exporting(_, let phase, _), .importing(_, let phase, _): return phase.title
        case .idle, .failed: return nil
        }
    }

    /// 整合包操作进度（0...1）。
    public static func busyProgress(_ state: DSHPackState) -> Double? {
        switch state {
        case .exporting(_, _, let progress), .importing(_, _, let progress): return progress
        case .idle, .failed: return nil
        }
    }

    /// 打包模式说明（导出按钮的 subtitle / tooltip）。
    public static func runtimeDescription(_ mode: DSHPackRuntimeMode) -> String {
        switch mode {
        case .bundled: return "包含 DSH 本体与插件载荷，离线可用，文件较大"
        case .online: return "只记录版本与插件清单，导入时从 npm 安装，文件较小"
        }
    }

    /// 导出被阻止的原因（可用表示 nil）。
    public static func exportBlockedReason(
        instance: DSHInstalledVersion?,
        state: DSHPackState,
        environmentReady: Bool,
        isReadOnly: Bool
    ) -> String? {
        if isReadOnly { return "快照模式不执行导出" }
        if state.isBusy { return "已有整合包任务在进行" }
        guard instance != nil else { return "请先安装并选择一个 DSH 实例" }
        if !environmentReady { return "缺少 Node.js / 包管理器" }
        return nil
    }

    /// 导入被阻止的原因（可用表示 nil）。
    public static func importBlockedReason(
        state: DSHPackState,
        environmentReady: Bool,
        isReadOnly: Bool
    ) -> String? {
        if isReadOnly { return "快照模式不执行导入" }
        if state.isBusy { return "已有整合包任务在进行" }
        if !environmentReady { return "缺少 Node.js / 包管理器" }
        return nil
    }

    /// 整合包实例一行描述：`DSH 0.2.1 · 整合包 Foo v1 · 1.2 GB · 安装于 2026-11-03`。
    public static func packSubtitle(_ instance: DSHInstalledVersion) -> String {
        var parts: [String] = ["DSH \(instance.dshVersion)"]
        var pack = "整合包"
        if let name = instance.packName, !name.isEmpty { pack += " \(name)" }
        if let version = instance.packVersion, !version.isEmpty { pack += " v\(version)" }
        parts.append(pack)
        if let size = instance.sizeBytes, size > 0 {
            parts.append(DSHDownloadFormat.size(size))
        }
        parts.append("安装于 \(DSHDownloadFormat.date(instance.installedAt))")
        return parts.joined(separator: " · ")
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

/// 版本列表的一行：版本号 + 标签 + 实例列表（同名/同版本多开）+ 安装 / 管理操作。
struct DSHVersionRowView: View {
    @Environment(\.launcherTheme) private var theme

    let info: DSHVersionInfo
    let tags: [String]
    /// 该 DSH 版本已安装的实例（可能 0 个、也可能同版本多开）。
    let instances: [DSHInstalledVersion]
    let selectedInstanceID: String?
    let runningInstanceID: String?
    let isInstalling: Bool
    let isBusy: Bool
    let isReadOnly: Bool
    let canInstall: Bool
    let installDisabledReason: String?
    /// 实例管理菜单（设为当前 / 卸载 / 导出…），没有实例时可为空。
    let menuGroups: [LauncherMenuGroup]

    let onInstall: () -> Void
    let onSelectInstance: (DSHInstalledVersion) -> Void

    /// 行内最多展示的实例 chip 数。
    private let maxChips = 3

    var body: some View {
        HStack(alignment: .top, spacing: LauncherSpace.md) {
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
                    if !instances.isEmpty {
                        LauncherBadge("已安装 \(instances.count) 个实例", tone: .success)
                    }
                    Spacer(minLength: 0)
                }

                Text(subtitle)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)

                if !instances.isEmpty {
                    instanceChips
                }
            }

            trailing
        }
        .padding(.horizontal, LauncherSpace.md)
        .padding(.vertical, LauncherSpace.xs)
        .frame(minHeight: LauncherControl.large + LauncherSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(hasSelectedInstance ? theme.colors.accentSoft : theme.colors.surfaceSubtle)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .strokeBorder(
                    hasSelectedInstance ? theme.colors.accent.opacity(0.3) : theme.colors.stroke,
                    lineWidth: 1
                )
        }
    }

    // MARK: 内部

    private var hasSelectedInstance: Bool {
        guard let selectedInstanceID else { return false }
        return instances.contains { $0.id == selectedInstanceID }
    }

    private var subtitle: String {
        var parts: [String] = ["发布于 \(DSHDownloadFormat.date(info.publishedAt))"]
        if let size = info.unpackedSize, size > 0 {
            parts.append("解包 \(DSHDownloadFormat.size(size))")
        }
        if instances.isEmpty {
            parts.append("尚未安装实例")
        } else {
            parts.append(DSHVersionStore.defaultName(for: info.version))
        }
        return parts.joined(separator: " · ")
    }

    private var instanceChips: some View {
        HStack(spacing: LauncherSpace.xxs) {
            Text("实例")
                .textStyle(.micro, tone: .tertiary)
            ForEach(DSHDownloadList.visible(instances, limit: maxChips)) { instance in
                LauncherChip(
                    chipTitle(instance),
                    isSelected: instance.id == selectedInstanceID,
                    systemImage: chipIcon(instance)
                ) {
                    onSelectInstance(instance)
                }
            }
            if instances.count > maxChips {
                Text("+\(instances.count - maxChips)")
                    .textStyle(.micro, tone: .tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private func chipTitle(_ instance: DSHInstalledVersion) -> String {
        instance.id == runningInstanceID ? "\(instance.name) · 运行中" : instance.name
    }

    private func chipIcon(_ instance: DSHInstalledVersion) -> String? {
        if instance.id == runningInstanceID { return "play.circle.fill" }
        if instance.isPack { return "shippingbox" }
        return nil
    }

    private var icon: some View {
        Image(systemName: info.isPrerelease ? "flask.fill" : "shippingbox.fill")
            .textStyle(.caption, tone: instances.isEmpty ? .secondary : .accent)
            .frame(width: LauncherControl.small, height: LauncherControl.small)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                    .fill(theme.colors.surfaceHover)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: LauncherSpace.xs) {
            if isInstalling {
                HStack(spacing: LauncherSpace.xs) {
                    LauncherSpinner(size: 14)
                    Text("安装中")
                        .textStyle(.micro, tone: .secondary)
                }
            } else {
                LauncherButton(
                    instances.isEmpty ? "安装" : "再装一个",
                    systemImage: "arrow.down.circle",
                    variant: instances.isEmpty ? .primary : .secondary,
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
                            : (canInstall ? "安装 DSH \(info.version)（可自定义实例名，可重复安装）" : (installDisabledReason ?? "当前环境不可安装")))
                )
            }

            if !menuGroups.isEmpty {
                LauncherIconMenu(
                    groups: menuGroups,
                    accessibilityLabel: "\(info.version) 的实例操作"
                )
                .launcherTooltip("实例操作：设为当前 / 卸载 / 导出整合包")
            }
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

// MARK: - 整合包实例行

/// 本地整合包实例的一行：名字 / DSH 版本 / 包信息 / 大小 + 设为当前 / 导出 / 卸载 / Finder。
struct DSHPackInstanceRowView: View {
    @Environment(\.launcherTheme) private var theme

    let instance: DSHInstalledVersion
    let isSelected: Bool
    let isRunning: Bool
    let isBusy: Bool
    let isReadOnly: Bool
    let exportMenuGroups: [LauncherMenuGroup]

    let onSelect: () -> Void
    let onUninstall: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: LauncherSpace.md) {
            Image(systemName: "shippingbox.fill")
                .textStyle(.caption, tone: isSelected ? .accent : .secondary)
                .frame(width: LauncherControl.small, height: LauncherControl.small)
                .background {
                    RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                        .fill(theme.colors.surfaceHover)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                HStack(spacing: LauncherSpace.xs) {
                    Text(instance.name)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    LauncherBadge("整合包", tone: .info)
                    if isSelected {
                        LauncherBadge("使用中", tone: .accent)
                    }
                    if isRunning {
                        LauncherBadge("运行中", tone: .accent)
                    }
                    Spacer(minLength: 0)
                }
                Text(DSHDownloadPackUI.packSubtitle(instance))
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
            }

            HStack(spacing: LauncherSpace.xs) {
                if !isSelected {
                    LauncherButton(
                        "设为当前",
                        systemImage: "checkmark.circle",
                        variant: .secondary,
                        size: .small,
                        isDisabled: isBusy || isReadOnly
                    ) {
                        onSelect()
                    }
                    .launcherTooltip(isReadOnly ? "快照模式不切换实例" : "把该整合包实例设为当前实例")
                }
                if !exportMenuGroups.isEmpty {
                    LauncherIconMenu(
                        groups: exportMenuGroups,
                        systemImage: "square.and.arrow.up",
                        accessibilityLabel: "导出该整合包实例"
                    )
                    .launcherTooltip("导出为 .dshpack（完整包 / 轻量包）")
                }
                LauncherIconButton(
                    systemImage: "folder",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: "在访达中显示 \(instance.name)",
                    isDisabled: isReadOnly
                ) {
                    onReveal()
                }
                .launcherTooltip(isReadOnly ? "快照模式不打开目录" : "在访达中显示该实例目录")
                LauncherIconButton(
                    systemImage: "trash",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: "卸载整合包实例 \(instance.name)",
                    isDisabled: isBusy || isReadOnly
                ) {
                    onUninstall()
                }
                .launcherTooltip(isReadOnly ? "快照模式不执行卸载" : "卸载该实例（只删除实例目录与日志，凭据仍复用 ~/.dsh）")
            }
        }
        .padding(.horizontal, LauncherSpace.md)
        .padding(.vertical, LauncherSpace.xs)
        .frame(minHeight: LauncherControl.large + LauncherSpace.md)
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
            .launcherTooltip(isReadOnly ? "快照模式不执行卸载" : "从当前实例的 web profile 卸载该插件")
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
                isReadOnly ? "快照模式不执行安装" : (installDisabledReason ?? "安装到当前实例的 web profile")
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
                    isInstalled ? "卸载插件" : "安装到当前实例",
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
                            : (isInstalled ? "从当前实例卸载" : (installDisabledReason ?? "安装到当前实例的 web profile")))
                )
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 进度卡

/// 安装 / 插件 / 整合包操作中的进度卡：阶段 + 进度条 + 日志尾部 + 取消按钮。
struct DSHProgressCard: View {
    @Environment(\.launcherTheme) private var theme

    let title: String
    let phase: String
    /// 进度（0...1）；nil 表示不确定进度（安装 / 插件命令）。
    var progress: Double? = nil
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

                LauncherProgressBar(value: progress, label: phase, height: 4)

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
