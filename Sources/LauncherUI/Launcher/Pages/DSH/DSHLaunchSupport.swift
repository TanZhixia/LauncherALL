import Foundation
import SwiftUI

// MARK: - 环境探测缓存

/// 一次 Node / 包管理器探测结果。
/// 探测本身可能启动登录 shell、生成 pnpm shim，开销较大，启动页只探测一次并缓存复用。
struct DSHLaunchEnvironment: Equatable, Sendable {
    /// Node 可执行文件路径；nil 表示未找到。
    let nodePath: String?
    /// 包管理器显示名（pnpm / npm）；nil 表示未找到。
    let packageManager: String?
    /// 快照模式下不探测环境，用确定性占位（避免离屏渲染起子进程 / 泄漏本机路径）。
    var isPlaceholder: Bool = false

    var hasNode: Bool { nodePath != nil }

    /// 快照模式的确定性占位。
    static let placeholder = DSHLaunchEnvironment(nodePath: nil, packageManager: nil, isPlaceholder: true)

    /// 与 `DSHVersionStore.environmentText` 同口径的环境摘要。
    var environmentText: String {
        if isPlaceholder { return "快照模式：未检测运行时" }
        guard let nodePath else { return "未找到 Node.js 运行时" }
        if let packageManager { return "Node \(nodePath) · \(packageManager)" }
        return "Node \(nodePath) · 未找到 pnpm / npm"
    }
}

/// 环境探测缓存：页面每次重绘都调用 `environmentText` 不会重复探测 / 重复生成 shim。
@MainActor
enum DSHLaunchEnvironmentCache {
    private static var cached: DSHLaunchEnvironment?

    /// 取缓存；首次调用会真实探测 Node 与包管理器。
    static func snapshot(paths: DSHPaths, refresh: Bool = false) -> DSHLaunchEnvironment {
        if !refresh, let cached { return cached }
        let node = DSHExecutables.node()
        let manager = DSHExecutables.packageManager(paths: paths)
        let value = DSHLaunchEnvironment(nodePath: node?.path, packageManager: manager?.displayName)
        cached = value
        return value
    }

    /// 清空缓存（刷新环境时调用）。
    static func reset() {
        cached = nil
    }
}

// MARK: - 启动页展示逻辑

/// DSH 启动页的纯展示逻辑：状态文案、URL token 脱敏、实例过滤、整包导出命名、启动 / 卸载禁用原因、日志截取。
/// 拆成纯函数便于单元测试，不依赖进程 / 网络 / 渲染。
enum DSHLaunchPresentation {

    // MARK: 进程状态

    /// 状态标题（页头徽标 / 运行状态卡）。
    static func statusTitle(_ state: DSHProcessState) -> String {
        switch state {
        case .idle: return "未运行"
        case .starting: return "启动中"
        case .running: return "运行中"
        case .stopping: return "停止中"
        case .failed: return "启动失败"
        }
    }

    /// 状态图标。
    static func statusIcon(_ state: DSHProcessState) -> String {
        switch state {
        case .idle: return "circle.dashed"
        case .starting: return "arrow.triangle.2.circlepath"
        case .running: return "checkmark.circle.fill"
        case .stopping: return "stop.circle"
        case .failed: return "xmark.octagon.fill"
        }
    }

    /// 状态色调。
    static func statusTone(_ state: DSHProcessState) -> LauncherBadgeTone {
        switch state {
        case .idle: return .neutral
        case .starting, .stopping: return .warning
        case .running: return .success
        case .failed: return .danger
        }
    }

    /// 状态说明：运行中显示脱敏 URL，失败显示错误文案，其余给出真实说明。
    static func statusDetail(_ state: DSHProcessState) -> String {
        switch state {
        case .idle:
            return "启动后会在默认浏览器打开 DSH Web UI（带一次性 token）。"
        case .starting:
            return "正在启动 dsh web，等待输出启动地址…"
        case .running(let url):
            return sanitizedURL(url)
        case .stopping:
            return "正在终止 DSH Web UI 进程…"
        case .failed(let message):
            return message
        }
    }

    /// 启动地址脱敏：隐藏 query 中的 token / key 等敏感值，保留可读的协议、主机、端口与路径。
    static func sanitizedURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        guard var components = URLComponents(string: trimmed) else {
            if let index = trimmed.firstIndex(of: "?") {
                return String(trimmed[..<index]) + "?…"
            }
            return trimmed
        }
        let sensitiveKeys: Set<String> = [
            "token", "access_token", "auth", "auth_token", "key", "apikey", "password", "secret"
        ]
        if let items = components.queryItems, !items.isEmpty {
            components.queryItems = items.map { item in
                sensitiveKeys.contains(item.name.lowercased())
                    ? URLQueryItem(name: item.name, value: "****")
                    : item
            }
        }
        return components.string ?? trimmed
    }

    // MARK: 端口 / 时间

    /// 端口文案：优先当前进程实际端口，其次设置里的默认端口。
    static func portText(activePort: Int?, fallback: Int) -> String {
        String(activePort ?? fallback)
    }

    /// 启动时间文案。
    static func startedAtText(_ date: Date?) -> String {
        guard let date else { return "尚未启动" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm:ss"
        return "启动于 \(formatter.string(from: date))"
    }

    /// 安装时间（紧凑），例如 "11-03 21:10"。
    static func compactInstalledDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 安装体积文案；读不到时返回 "—"。
    static func sizeText(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: 实例列表

    /// 搜索过滤实例（匹配实例名 + DSH 版本号）。
    static func filteredInstances(_ instances: [DSHInstalledVersion], query: String) -> [DSHInstalledVersion] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return instances }
        return instances.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.dshVersion.localizedCaseInsensitiveContains(keyword)
                || $0.id.localizedCaseInsensitiveContains(keyword)
        }
    }

    /// 左侧实例行副标题："DSH <dshVersion>"（任务约定格式）。
    static func listSubtitle(_ instance: DSHInstalledVersion) -> String {
        "DSH \(instance.dshVersion)"
    }

    /// 右侧当前实例卡副标题：DSH 版本 + 安装时间 + 体积。
    static func detailSubtitle(_ instance: DSHInstalledVersion) -> String {
        "DSH \(instance.dshVersion) · 安装 \(compactInstalledDateText(instance.installedAt)) · \(sizeText(instance.sizeBytes))"
    }

    /// 实例是否就是当前运行中的实例（按实例 ID 匹配，不比较版本号）。
    static func isRunning(_ instance: DSHInstalledVersion, activeInstanceID: String?) -> Bool {
        guard let activeInstanceID, !activeInstanceID.isEmpty else { return false }
        return instance.id == activeInstanceID
    }

    /// 正在运行的实例（按 ID 从已安装实例里找；找不到时返回 nil）。
    static func runningInstance(in instances: [DSHInstalledVersion], activeInstanceID: String?) -> DSHInstalledVersion? {
        guard let activeInstanceID, !activeInstanceID.isEmpty else { return nil }
        return instances.first { $0.id == activeInstanceID }
    }

    /// 实例行徽标：运行中 > 整合包；其余为 nil（latest 不再用于实例列表）。
    static func instanceBadge(_ instance: DSHInstalledVersion, isRunning: Bool) -> String? {
        if isRunning { return "运行中" }
        if instance.isPack { return "整合包" }
        return nil
    }

    /// 整合包来源信息行；非整合包返回 nil。
    static func packInfoText(_ instance: DSHInstalledVersion) -> String? {
        guard instance.isPack else { return nil }
        let name = instance.packName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未知整合包"
        let version = instance.packVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return version.isEmpty ? "整合包：\(name)" : "整合包：\(name) \(version)"
    }

    /// 是否为 npm 上 latest 版本（仅用于当前实例卡的小徽标）。
    static func isLatest(_ instance: DSHInstalledVersion, latestVersion: String?) -> Bool {
        guard let latestVersion, !latestVersion.isEmpty else { return false }
        return instance.dshVersion == latestVersion
    }

    // MARK: 导出整合包

    /// 导出模式菜单标题（菜单里直接给出完整包 / 轻量包两个入口）。
    static func exportMenuTitle(runtime: DSHPackRuntimeMode) -> String {
        switch runtime {
        case .bundled: return "导出为整合包…（完整包，含 DSH 本体）"
        case .online: return "导出为整合包…（轻量包，导入时联网）"
        }
    }

    /// 导出默认文件名：`<实例名>.dshpack`（替换路径非法字符，空名回退）。
    static func exportFileName(instanceName: String) -> String {
        let trimmed = instanceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|\u{0}")
        let cleaned = String(trimmed.unicodeScalars.map { banned.contains($0) ? "-" : Character($0) })
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let base = cleaned.isEmpty ? "dsh-instance" : String(cleaned.prefix(80))
        return "\(base).\(DSHPackFormat.fileExtension)"
    }

    /// 导出整合包默认展示名（manifest.name）。
    static func exportPackName(instance: DSHInstalledVersion) -> String {
        let name = instance.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return instance.isPack ? (instance.packName ?? "DSH 整合包") : "DSH \(instance.dshVersion) 实例"
    }

    /// 导出整合包默认版本（manifest.version）：优先沿用来源包版本，否则 1.0.0。
    static func exportPackVersion(instance: DSHInstalledVersion) -> String {
        if let packVersion = instance.packVersion, !packVersion.isEmpty { return packVersion }
        return "1.0.0"
    }

    /// 导出按钮禁用原因；nil 表示可以导出。
    static func exportDisabledReason(snapshotMode: Bool, isBusy: Bool) -> String? {
        if snapshotMode { return "快照模式不执行导出（不会弹出保存面板）" }
        if isBusy { return "正在导出 / 导入整合包，请稍候" }
        return nil
    }

    // MARK: 卸载

    /// 卸载按钮禁用原因；nil 表示可以卸载。
    static func uninstallDisabledReason(
        instance: DSHInstalledVersion,
        activeInstanceID: String?,
        isBusy: Bool,
        isInstalling: Bool
    ) -> String? {
        if isInstalling { return "正在安装 DSH，请安装完成后再卸载" }
        if isBusy { return "DSH 正在启动 / 停止，请先停止" }
        if isRunning(instance, activeInstanceID: activeInstanceID) {
            return "实例正在运行，请先在启动卡停止 Web UI"
        }
        return nil
    }

    // MARK: 启动条件

    /// 启动按钮禁用原因；nil 表示可以启动。
    static func startDisabledReason(
        hasSelection: Bool,
        hasNode: Bool,
        isInstalling: Bool,
        isBusy: Bool
    ) -> String? {
        if isInstalling { return "正在安装 DSH，安装完成后才能启动" }
        if isBusy { return "正在启动或停止 DSH，请稍候" }
        if !hasSelection { return "请先在左侧选择已安装的 DSH 实例" }
        if !hasNode { return DSHError.nodeNotFound.localizedDescription }
        return nil
    }

    /// 安装状态文案；非安装中 / 失败时返回 nil。
    static func installPhaseText(_ state: DSHInstallState) -> String? {
        switch state {
        case .idle:
            return nil
        case .installing(let version, let phase):
            return "正在安装 DSH \(version) · \(phase.title)"
        case .failed(_, let message):
            return message
        }
    }

    /// 安装是否处于失败态（失败文案已在启动卡内联展示）。
    static func isInstallFailed(_ state: DSHInstallState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    // MARK: 日志

    /// 取最后 N 行日志（顺序保持不变）。
    static func logTail(_ lines: [String], limit: Int = 12) -> [String] {
        guard limit > 0 else { return [] }
        return Array(lines.suffix(limit))
    }

    /// 日志行语义色调：错误 / 警告 / 成功 / 普通。
    static func logTone(_ line: String) -> LauncherTextTone {
        let lowered = line.lowercased()
        if lowered.contains("error") || lowered.contains("✗") || lowered.contains("failed")
            || lowered.contains("exception") || lowered.contains("失败") {
            return .danger
        }
        if lowered.contains("warn") || lowered.contains("⚠") || lowered.contains("警告") {
            return .warning
        }
        if lowered.contains("✓") || lowered.contains("ready") || lowered.contains("listening") {
            return .success
        }
        return .secondary
    }

    // MARK: 整合包导出阶段

    /// 导出进度文案；非导出中返回 nil。
    static func exportPhaseText(_ state: DSHPackState) -> String? {
        switch state {
        case .exporting(let name, let phase, _):
            return "\(name) · \(phase.title)"
        case .failed(let message):
            return message
        case .idle, .importing:
            return nil
        }
    }
}
