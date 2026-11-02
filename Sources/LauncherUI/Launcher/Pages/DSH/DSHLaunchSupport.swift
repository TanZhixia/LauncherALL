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

/// DSH 启动页的纯展示逻辑：状态文案、URL token 脱敏、版本过滤、启动禁用原因、日志截取。
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

    // MARK: 版本列表

    /// 搜索过滤已安装版本（按版本号忽略大小写）。
    static func filteredVersions(_ versions: [DSHInstalledVersion], query: String) -> [DSHInstalledVersion] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return versions }
        return versions.filter { $0.version.localizedCaseInsensitiveContains(keyword) }
    }

    /// 是否为最新版本（与 npm `latest` dist-tag 对比）。
    static func isLatest(_ version: DSHInstalledVersion, latestVersion: String?) -> Bool {
        guard let latestVersion, !latestVersion.isEmpty else { return false }
        return version.version == latestVersion
    }

    /// 安装日期文案，例如 "2026-11-02 20:10"（用于详情/提示）。
    static func installedDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 版本行里的紧凑安装时间，例如 "11-02 20:10"（300pt 侧栏放得下完整时间 + 体积）。
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

    /// 版本行副标题："11-02 20:10 · 123 MB"（紧凑格式，保证带 latest 徽标时也不被截断）。
    static func versionSubtitle(_ version: DSHInstalledVersion) -> String {
        "\(compactInstalledDateText(version.installedAt)) · \(sizeText(version.sizeBytes))"
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
        if !hasSelection { return "请先在左侧选择已安装的 DSH 版本" }
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
}
