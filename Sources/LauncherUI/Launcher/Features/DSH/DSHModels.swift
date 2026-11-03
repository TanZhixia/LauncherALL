import Foundation

// MARK: - DSH 版本 / 插件模型

/// npm 上的一个 `@deepseek-ai/dsh` 版本。
public struct DSHVersionInfo: Identifiable, Hashable, Sendable {
    public let version: String
    public let publishedAt: Date?
    public let tarballURL: String?
    public let unpackedSize: Int64?
    public let distTags: [String]

    public var id: String { version }

    public init(
        version: String,
        publishedAt: Date? = nil,
        tarballURL: String? = nil,
        unpackedSize: Int64? = nil,
        distTags: [String] = []
    ) {
        self.version = version
        self.publishedAt = publishedAt
        self.tarballURL = tarballURL
        self.unpackedSize = unpackedSize
        self.distTags = distTags
    }

    /// 是否预发布版本（含 `-rc` / `-alpha` / `-beta`）。
    public var isPrerelease: Bool { version.contains("-") }

    /// 主版本标签（latest / next / alpha…），没有则为空。
    public var tagText: String? { distTags.first }
}

/// 实例类型：普通安装 / 从整合包导入。
public enum DSHInstanceKind: String, Codable, Sendable, Hashable {
    case vanilla
    case pack
}

/// 已安装到本机的一个 DSH 实例：
/// - `id` 是实例唯一标识（目录名 / 选中标识），允许同一 DSH 版本重复安装；
/// - `name` 是用户可见的自定义名字；
/// - `dshVersion` 是实际的 npm 版本（如 `0.2.1-rc.5`）。
public struct DSHInstalledVersion: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public let dshVersion: String
    public let installedAt: Date
    public let path: String
    public var sizeBytes: Int64?
    public var kind: DSHInstanceKind
    /// 来源整合包名（`kind == .pack` 时）。
    public var packName: String?
    /// 来源整合包版本。
    public var packVersion: String?
    /// 旧版本（按 npm 版本号建目录）迁移过来的实例。
    public var legacy: Bool

    /// 兼容旧 UI：显示时与 DSH 版本号相同。
    public var version: String { dshVersion }

    public var isPack: Bool { kind == .pack }

    public init(
        id: String,
        name: String,
        dshVersion: String,
        installedAt: Date,
        path: String,
        sizeBytes: Int64? = nil,
        kind: DSHInstanceKind = .vanilla,
        packName: String? = nil,
        packVersion: String? = nil,
        legacy: Bool = false
    ) {
        self.id = id
        self.name = name
        self.dshVersion = dshVersion
        self.installedAt = installedAt
        self.path = path
        self.sizeBytes = sizeBytes
        self.kind = kind
        self.packName = packName
        self.packVersion = packVersion
        self.legacy = legacy
    }

    /// 兼容旧调用：以 npm 版本号同时作为实例 ID。
    public init(version: String, installedAt: Date, path: String, sizeBytes: Int64? = nil) {
        self.init(
            id: version,
            name: "DSH \(version)",
            dshVersion: version,
            installedAt: installedAt,
            path: path,
            sizeBytes: sizeBytes,
            kind: .vanilla,
            legacy: false
        )
    }

    /// 旧目录（目录名 = npm 版本号）迁移成实例。
    public init(legacyVersion: String, installedAt: Date, path: String, sizeBytes: Int64? = nil) {
        self.init(
            id: legacyVersion,
            name: "DSH \(legacyVersion)",
            dshVersion: legacyVersion,
            installedAt: installedAt,
            path: path,
            sizeBytes: sizeBytes,
            kind: .vanilla,
            legacy: true
        )
    }
}

// MARK: - 目录状态

/// 网络目录（版本列表 / 插件市场）的加载状态。
public enum DSHCatalogState: Equatable, Sendable {
    case idle
    case loading
    case loaded(Date)
    case failed(String)

    public var isLoading: Bool { self == .loading }

    public var errorText: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// 版本安装进度。
public enum DSHInstallPhase: Equatable, Sendable {
    case preparing
    case downloading
    case installing
    case finishing

    public var title: String {
        switch self {
        case .preparing: return "准备安装环境…"
        case .downloading: return "下载 DSH 依赖包…"
        case .installing: return "安装依赖…"
        case .finishing: return "写入安装信息…"
        }
    }
}

/// 安装状态机。
public enum DSHInstallState: Equatable, Sendable {
    case idle
    case installing(version: String, phase: DSHInstallPhase)
    case failed(version: String, message: String)

    public var isInstalling: Bool {
        if case .installing = self { return true }
        return false
    }

    public var installingVersion: String? {
        if case .installing(let version, _) = self { return version }
        return nil
    }
}

/// DSH Web UI 进程状态。
public enum DSHProcessState: Equatable, Sendable {
    case idle
    case starting
    case running(url: String)
    case stopping
    case failed(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var isBusy: Bool {
        switch self {
        case .starting, .stopping: return true
        default: return false
        }
    }

    public var url: String? {
        if case .running(let url) = self { return url }
        return nil
    }
}

// MARK: - 插件市场

/// 插件市场分类。
public struct DSHPluginCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let titleEN: String
    public let titleZH: String

    public init(id: String, titleEN: String, titleZH: String) {
        self.id = id
        self.titleEN = titleEN
        self.titleZH = titleZH
    }

    public var title: String { titleZH.isEmpty ? titleEN : titleZH }
}

/// dshmarket 加载源里的一个插件条目。
public struct DSHPluginEntry: Identifiable, Hashable, Decodable, Sendable {
    public let name: String
    public let owner: String
    public let url: String
    public let page: String?
    public let category: String?
    public let descriptionEN: String?
    public let descriptionZH: String?
    public let npm: String?
    public let version: String?
    public let stars: Int?
    public let downloads: Int?
    public let capabilities: [String]
    public let install: String?
    public let added: String?
    public let icon: String?

    public var id: String { "\(owner)/\(name)" }
    public var title: String { name }
    public var subtitle: String { owner }
    public var descriptionText: String { (descriptionZH?.isEmpty == false ? descriptionZH : descriptionEN) ?? "" }
    public var categoryID: String? { category }

    /// 用于 `dsh plugin add` 的安装标识（npm 包名 / github: 规格）。
    public var installSpec: String? {
        if let npm, !npm.isEmpty { return npm }
        guard let install else { return nil }
        let parts = install.split(separator: " ").map(String.init)
        guard let addIndex = parts.firstIndex(of: "add"), addIndex + 1 < parts.count else { return nil }
        return parts[addIndex + 1]
    }

    /// 用于 `dsh plugin remove` 的依赖名（通常与 installSpec 相同）。
    public var removeSpec: String? { installSpec }

    private enum CodingKeys: String, CodingKey {
        case name, owner, url, page, category, npm, version, stars, downloads
        case capabilities, install, added, icon
        case description
    }

    private struct LocalizedDescription: Decodable {
        let en: String?
        let zh: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        owner = try container.decode(String.self, forKey: .owner)
        url = try container.decode(String.self, forKey: .url)
        page = try container.decodeIfPresent(String.self, forKey: .page)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        npm = try container.decodeIfPresent(String.self, forKey: .npm)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        stars = try container.decodeIfPresent(Int.self, forKey: .stars)
        downloads = try container.decodeIfPresent(Int.self, forKey: .downloads)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        install = try container.decodeIfPresent(String.self, forKey: .install)
        added = try container.decodeIfPresent(String.self, forKey: .added)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        let localized = try container.decodeIfPresent(LocalizedDescription.self, forKey: .description)
        descriptionEN = localized?.en
        descriptionZH = localized?.zh
    }

    public init(
        name: String,
        owner: String,
        url: String,
        page: String? = nil,
        category: String? = nil,
        descriptionEN: String? = nil,
        descriptionZH: String? = nil,
        npm: String? = nil,
        version: String? = nil,
        stars: Int? = nil,
        downloads: Int? = nil,
        capabilities: [String] = [],
        install: String? = nil,
        added: String? = nil,
        icon: String? = nil
    ) {
        self.name = name
        self.owner = owner
        self.url = url
        self.page = page
        self.category = category
        self.descriptionEN = descriptionEN
        self.descriptionZH = descriptionZH
        self.npm = npm
        self.version = version
        self.stars = stars
        self.downloads = downloads
        self.capabilities = capabilities
        self.install = install
        self.added = added
        self.icon = icon
    }
}

/// dshmarket 加载源文件（`plugins.json`）的顶层结构。
public struct DSHPluginCatalogFile: Decodable, Sendable {
    public let name: String?
    public let url: String?
    public let source: String?
    public let updated: String?
    public let count: Int?
    public let categories: [String: DSHPluginCategoryPayload]
    public let plugins: [DSHPluginEntry]

    public struct DSHPluginCategoryPayload: Decodable, Sendable {
        public let en: String?
        public let zh: String?
    }
}

/// 已安装到某个 DSH 版本 profile 的插件（来自 profile/package.json 依赖）。
public struct DSHInstalledPlugin: Identifiable, Hashable, Sendable {
    public let dependencyKey: String
    public let version: String

    public var id: String { dependencyKey }
    public var name: String { dependencyKey }
}

// MARK: - 错误

public enum DSHError: LocalizedError, Equatable {
    case nodeNotFound
    case packageManagerNotFound
    case invalidVersion(String)
    case alreadyInstalled(String)
    case notInstalled(String)
    case installFailed(String)
    case launchFailed(String)
    case processExited(code: Int32, tail: String)
    case network(String)
    case invalidResponse(String)
    case pluginInstallFailed(String)
    case pluginRemoveFailed(String)
    case noProfile(String)

    public var errorDescription: String? {
        switch self {
        case .nodeNotFound:
            return "没有找到可用的 Node.js 运行时：请安装 Node 20+，或先安装 DeepSeek Harness 桌面端（自带 Node 运行时）"
        case .packageManagerNotFound:
            return "没有找到可用的包管理器（pnpm / npm）：请安装 pnpm 或 npm 后重试"
        case .invalidVersion(let version):
            return "无效的 DSH 版本号：\(version)"
        case .alreadyInstalled(let version):
            return "DSH \(version) 已经安装"
        case .notInstalled(let version):
            return "DSH \(version) 尚未安装"
        case .installFailed(let message):
            return "DSH 安装失败：\(message)"
        case .launchFailed(let message):
            return "DSH 启动失败：\(message)"
        case .processExited(let code, let tail):
            return "DSH 进程已退出（退出码 \(code)）\(tail.isEmpty ? "" : "：\(tail)")"
        case .network(let message):
            return "网络请求失败：\(message)"
        case .invalidResponse(let message):
            return "响应格式不正确：\(message)"
        case .pluginInstallFailed(let message):
            return "插件安装失败：\(message)"
        case .pluginRemoveFailed(let message):
            return "插件卸载失败：\(message)"
        case .noProfile(let version):
            return "DSH \(version) 还没有初始化 web profile，请先启动一次"
        }
    }
}

// MARK: - 版本号比较

/// DSH 版本号比较：完整 semver（含 prerelease 优先级）。
public enum DSHVersionComparator {
    /// `a > b` 返回 true。
    public static func isNewer(_ a: String, than b: String) -> Bool {
        compare(a, b) == .orderedDescending
    }

    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let left = parse(a)
        let right = parse(b)
        let count = max(left.numbers.count, right.numbers.count)
        for index in 0..<count {
            let lhs = index < left.numbers.count ? left.numbers[index] : 0
            let rhs = index < right.numbers.count ? right.numbers[index] : 0
            if lhs != rhs { return lhs > rhs ? .orderedDescending : .orderedAscending }
        }
        // 主版本相同时：release > prerelease
        if left.prerelease.isEmpty && right.prerelease.isEmpty { return .orderedSame }
        if left.prerelease.isEmpty { return .orderedDescending }
        if right.prerelease.isEmpty { return .orderedAscending }
        let length = max(left.prerelease.count, right.prerelease.count)
        for index in 0..<length {
            guard index < left.prerelease.count else { return .orderedAscending }
            guard index < right.prerelease.count else { return .orderedDescending }
            let lhs = left.prerelease[index]
            let rhs = right.prerelease[index]
            if lhs == rhs { continue }
            switch (Int(lhs), Int(rhs)) {
            case let (lhsNumber?, rhsNumber?):
                return lhsNumber > rhsNumber ? .orderedDescending : .orderedAscending
            case (_?, nil):
                return .orderedAscending
            case (nil, _?):
                return .orderedDescending
            default:
                return lhs > rhs ? .orderedDescending : .orderedAscending
            }
        }
        return .orderedSame
    }

    private struct Parsed {
        let numbers: [Int]
        let prerelease: [String]
    }

    private static func parse(_ text: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let split = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = String(split.first ?? "")
        let prerelease = split.count > 1
            ? String(split[1]).split(separator: ".").map(String.init)
            : []
        let numbers = core.split(separator: ".").map { Int($0) ?? 0 }
        return Parsed(numbers: numbers, prerelease: prerelease)
    }
}
