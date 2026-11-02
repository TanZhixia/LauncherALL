import Foundation
import Observation

// MARK: - 更新源响应

/// 更新源 JSON（GET 返回）：
/// ```json
/// { "version": "0.3.0", "url": "https://…/download", "notes": "修复了…" }
/// ```
public struct UpdateFeed: Decodable, Sendable, Equatable {
    public let version: String
    public let url: String?
    public let notes: String?

    public init(version: String, url: String? = nil, notes: String? = nil) {
        self.version = version
        self.url = url
        self.notes = notes
    }
}

// MARK: - 版本号比较

/// 语义版本工具：比较 / 解析 "0.2.0" 这类版本串。
public enum LauncherVersion: Sendable {
    /// 拆出数字段，"0.2.0-beta.1" → [0, 2, 0]。
    public static func numbers(_ text: String) -> [Int] {
        let core = text.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? text
        let pieces = core.split(whereSeparator: { !$0.isNumber }).map(String.init)
        return pieces.compactMap { Int($0) }
    }

    /// 版本比较：`a > b` 返回 true（缺失段按 0 处理）。
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let left = numbers(a)
        let right = numbers(b)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }
}

// MARK: - 检查更新

/// 真实的更新检查：请求用户配置的更新源 JSON，按版本号比较。
/// 没配置更新源时给出明确状态，不再用假的 `sleep` 假装检查。
@MainActor
@Observable
public final class UpdateChecker {
    public enum Status: Equatable, Sendable {
        /// 还没检查过
        case idle
        case checking
        /// 已是最新
        case upToDate(current: String)
        /// 发现新版本
        case available(current: String, latest: UpdateFeed)
        /// 未配置更新源
        case noFeed
        /// 网络 / 解析失败
        case failed(message: String)

        public var isChecking: Bool { self == .checking }

        public var message: String {
            switch self {
            case .idle: return "尚未检查更新"
            case .checking: return "正在检查更新…"
            case .upToDate(let current): return "已是最新版本 v\(current)"
            case .available(_, let latest): return "发现新版本 v\(latest.version)"
            case .noFeed: return "未配置更新源（本地构建）"
            case .failed(let message): return "检查失败：\(message)"
            }
        }

        /// 供徽标使用的色调名（页面自行映射到 LauncherBadgeTone）。
        public var toneName: String {
            switch self {
            case .available: return "accent"
            case .upToDate: return "success"
            case .failed: return "danger"
            case .noFeed: return "neutral"
            case .idle, .checking: return "neutral"
            }
        }
    }

    public private(set) var status: Status = .idle
    public private(set) var lastCheckedAt: Date?

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// 友好的上次检查时间；没检查过返回 nil。
    public var lastCheckedText: String? {
        guard let lastCheckedAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: lastCheckedAt)
    }

    /// 执行检查：`feedURL` 为空 → `.noFeed`；网络失败 → `.failed`。
    public func check(feedURL: String, currentVersion: String = LauncherBuildInfo.current.version) async {
        guard status != .checking else { return }
        let trimmed = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = .noFeed
            lastCheckedAt = Date()
            return
        }
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http" else {
            status = .failed(message: "更新源地址不是有效的 http(s) URL")
            lastCheckedAt = Date()
            return
        }

        status = .checking
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                status = .failed(message: "更新源返回 HTTP \(http.statusCode)")
                lastCheckedAt = Date()
                return
            }
            let feed = try JSONDecoder().decode(UpdateFeed.self, from: data)
            lastCheckedAt = Date()
            if LauncherVersion.isNewer(feed.version, than: currentVersion) {
                status = .available(current: currentVersion, latest: feed)
            } else {
                status = .upToDate(current: currentVersion)
            }
        } catch is CancellationError {
            status = .idle
        } catch {
            status = .failed(message: error.localizedDescription)
            lastCheckedAt = Date()
        }
    }

    /// 有可用更新时返回下载页地址。
    public var downloadURL: URL? {
        guard case .available(_, let latest) = status, let raw = latest.url else { return nil }
        return URL(string: raw)
    }
}
