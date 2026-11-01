import Foundation
import CryptoKit

// MARK: - 版本清单（Mojang piston-meta）

public struct VersionSummary: Identifiable, Decodable, Sendable {
    public let id: String
    public let type: String
    public let url: String
    public let time: String
    public let releaseTime: String
}

public struct VersionManifest: Decodable, Sendable {
    public struct Latest: Decodable, Sendable {
        public let release: String
        public let snapshot: String
    }
    public let latest: Latest
    public let versions: [VersionSummary]
}

/// 版本详情（<version>.json）。
public struct VersionDetail: Decodable, Sendable {
    public struct AssetIndex: Decodable, Sendable {
        public let id: String
        public let url: String
        public let sha1: String?
        public let size: Int64?
        public let totalSize: Int64?
    }

    public struct DownloadArtifact: Decodable, Sendable {
        public let path: String?
        public let sha1: String?
        public let size: Int64?
        public let url: String
    }

    public struct LibraryDownloads: Decodable, Sendable {
        public let artifact: DownloadArtifact?
        public let classifiers: [String: DownloadArtifact]?
    }

    public struct Library: Decodable, Sendable {
        public let name: String
        public let downloads: LibraryDownloads?
        public let rules: [Rule]?
        public let natives: [String: String]?
        public let url: String?

        /// Maven 坐标转相对路径（Fabric/Forge 等 launcher 常只给 name + url，没有 downloads 字段）。
        public var mavenPath: String? {
            if let path = downloads?.artifact?.path { return path }
            let parts = name.split(separator: ":").map(String.init)
            guard parts.count >= 3 else { return nil }
            let group = parts[0].replacingOccurrences(of: ".", with: "/")
            let artifact = parts[1]
            let version = parts[2]
            let classifier = parts.count >= 4 ? "-\(parts[3])" : ""
            return "\(group)/\(artifact)/\(version)/\(artifact)-\(version)\(classifier).jar"
        }

        /// 依赖下载地址：优先 downloads.artifact.url，其次 name 对应 maven 仓库。
        public func downloadURL(type: String? = nil) -> URL? {
            if let artifact = downloads?.artifact, type == nil, let url = URL(string: artifact.url) {
                return url
            }
            guard let mavenPath, let base = url ?? "https://libraries.minecraft.net/" as String? else { return nil }
            return URL(string: base.hasSuffix("/") ? base + mavenPath : base + "/" + mavenPath)
        }
    }

    public struct Argument: Decodable, Sendable {
        public let rules: [Rule]?
        public let values: [String]

        private enum CodingKeys: String, CodingKey {
            case rules
            case value
        }

        public init(rules: [Rule]?, values: [String]) {
            self.rules = rules
            self.values = values
        }

        public init(from decoder: Decoder) throws {
            // 既支持纯字符串，也支持 { rules, value } 对象；value 可为字符串或字符串数组
            if let single = try? decoder.singleValueContainer(),
               let string = try? single.decode(String.self) {
                self.rules = nil
                self.values = [string]
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.rules = try container.decodeIfPresent([Rule].self, forKey: .rules)
            if let many = try? container.decode([String].self, forKey: .value) {
                self.values = many
            } else if let one = try? container.decode(String.self, forKey: .value) {
                self.values = [one]
            } else {
                self.values = []
            }
        }
    }

    public struct Arguments: Decodable, Sendable {
        public let game: [Argument]
        public let jvm: [Argument]
    }

    public struct JavaVersion: Decodable, Sendable {
        public let component: String
        public let majorVersion: Int
    }

    public struct Logging: Decodable, Sendable {
        public struct Client: Decodable, Sendable {
            public struct File: Decodable, Sendable {
                public let id: String
                public let sha1: String?
                public let size: Int64?
                public let url: String
            }
            public let argument: String
            public let file: File
            public let type: String?
        }
        public let client: Client?
    }

    public let inheritsFrom: String?
    public let id: String
    public let type: String?
    public let mainClass: String?
    public let assets: String?
    public let assetIndex: AssetIndex?
    public let downloads: [String: DownloadArtifact]?
    public let libraries: [Library]?
    public let arguments: Arguments?
    public let minecraftArguments: String?
    public let javaVersion: JavaVersion?
    public let logging: Logging?

    public var clientDownload: DownloadArtifact? { downloads?["client"] }
}

/// 规则（操作系统 / 特性）。
public struct Rule: Decodable, Sendable {
    public struct OS: Decodable, Sendable {
        public let name: String?
        public let arch: String?
        public let version: String?
    }

    public struct Features: Decodable, Sendable {
        public let has_custom_resolution: Bool?
        public let is_demo_user: Bool?
        public let has_quick_plays_support: Bool?
    }

    public enum Action: String, Decodable, Sendable {
        case allow
        case disallow
    }

    public let action: Action
    public let os: OS?
    public let features: Features?
}

// MARK: - 规则求值

public enum RuleEvaluator {
    /// 当前机器信息（macOS / arm64 或 x86_64）。
    public static var currentOSName: String? { "osx" }
    public static var currentArch: String {
        ProcessInfo.processInfo.machineArchitecture == "arm64" ? "arm64" : "x86_64"
    }

    /// 未满足任何 allow 规则 / 命中 disallow → 该条目不可用。
    public static func isAllowed(_ rules: [Rule]?) -> Bool {
        guard let rules, !rules.isEmpty else { return true }
        var allowed = false
        for rule in rules {
            guard matches(rule) else { continue }
            switch rule.action {
            case .allow: allowed = true
            case .disallow: return false
            }
        }
        return allowed
    }

    static func matches(_ rule: Rule) -> Bool {
        if let os = rule.os {
            if let name = os.name, name != currentOSName { return false }
            if let arch = os.arch, arch != currentArch { return false }
        }
        if let features = rule.features {
            // 启动器只支持基础特性，自定义分辨率 / 演示模式均关闭
            if features.has_custom_resolution == true { return false }
            if features.is_demo_user == true { return false }
            if features.has_quick_plays_support == true { return false }
        }
        return true
    }
}

// MARK: - Mojang 服务

public enum MojangServiceError: LocalizedError {
    case http(Int)
    case decode(String)
    case versionNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .http(let code): return "请求失败（HTTP \(code)）"
        case .decode(let message): return "解析失败：\(message)"
        case .versionNotFound(let id): return "未找到版本 \(id)"
        }
    }
}

/// 拉取 Mojang 版本清单与版本详情，并做本地缓存。
public final class MojangManifestService {
    public static let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!

    private let installation: MinecraftInstallation
    private let session: URLSession

    public init(installation: MinecraftInstallation, session: URLSession = .shared) {
        self.installation = installation
        self.session = session
    }

    public var cacheDirectory: URL {
        installation.cacheDirectory.appendingPathComponent("manifest", isDirectory: true)
    }

    /// 获取版本清单（带 12 小时磁盘缓存）。
    public func fetchManifest(forceRefresh: Bool = false) async throws -> VersionManifest {
        let cacheFile = cacheDirectory.appendingPathComponent("version_manifest_v2.json")
        if !forceRefresh,
           let attributes = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 12 * 3600,
           let data = try? Data(contentsOf: cacheFile),
           let manifest = try? JSONDecoder().decode(VersionManifest.self, from: data) {
            return manifest
        }
        let (data, response) = try await session.data(from: Self.manifestURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MojangServiceError.http(http.statusCode)
        }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: cacheFile, options: .atomic)
            return try JSONDecoder().decode(VersionManifest.self, from: data)
        } catch {
            throw MojangServiceError.decode(error.localizedDescription)
        }
    }

    /// 获取某个版本的详情 JSON。
    public func fetchVersionDetail(_ versionID: String) async throws -> VersionDetail {
        try await fetchVersionDetailData(versionID).detail
    }

    /// 获取版本详情原始数据 + 解析结果（安装器需要原样落盘）。
    public func fetchVersionDetailData(_ versionID: String) async throws -> (data: Data, detail: VersionDetail) {
        let manifest = try await fetchManifest()
        guard let summary = manifest.versions.first(where: { $0.id == versionID }) else {
            throw MojangServiceError.versionNotFound(versionID)
        }
        guard let url = URL(string: summary.url) else {
            throw MojangServiceError.decode("非法版本 URL")
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MojangServiceError.http(http.statusCode)
        }
        do {
            let detail = try JSONDecoder().decode(VersionDetail.self, from: data)
            return (data, detail)
        } catch {
            throw MojangServiceError.decode(error.localizedDescription)
        }
    }
}

// MARK: - 文件下载（带进度与 sha1 校验）

public struct FileDownloadTask: Sendable {
    public let url: URL
    public let destination: URL
    public let sha1: String?
    public let expectedSize: Int64?

    public init(url: URL, destination: URL, sha1: String? = nil, expectedSize: Int64? = nil) {
        self.url = url
        self.destination = destination
        self.sha1 = sha1
        self.expectedSize = expectedSize
    }
}

public enum DownloadError: LocalizedError {
    case http(Int, URL)
    case checksum(URL)

    public var errorDescription: String? {
        switch self {
        case .http(let code, let url): return "下载失败 HTTP \(code)：\(url.lastPathComponent)"
        case .checksum(let url): return "文件校验失败：\(url.lastPathComponent)"
        }
    }
}

/// 真实网络下载：流式写盘 + 进度回调 + SHA1 校验。
public final class FileDownloader {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(
        _ task: FileDownloadTask,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: task.destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        // 已存在且校验通过则跳过
        if fileManager.fileExists(atPath: task.destination.path), let sha1 = task.sha1,
           let existing = try? Data(contentsOf: task.destination),
           Self.sha1Hex(existing) == sha1 {
            progress(1)
            return
        }

        let (bytes, response) = try await session.bytes(from: task.url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw DownloadError.http(http.statusCode, task.url)
        }
        let total = task.expectedSize ?? Int64(response.expectedContentLength)
        var buffer = Data()
        var written: Int64 = 0
        var lastReported = Date.distantPast

        let temporary = task.destination.appendingPathExtension("part")
        fileManager.createFile(atPath: temporary.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                let now = Date()
                if now.timeIntervalSince(lastReported) > 0.08 || (total > 0 && written >= total) {
                    lastReported = now
                    progress(total > 0 ? min(1, Double(written) / Double(total)) : 0)
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }
        try handle.close()

        if let sha1 = task.sha1 {
            let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
            guard Self.sha1Hex(data) == sha1 else {
                try? fileManager.removeItem(at: temporary)
                throw DownloadError.checksum(task.destination)
            }
        }
        if fileManager.fileExists(atPath: task.destination.path) {
            try? fileManager.removeItem(at: task.destination)
        }
        try fileManager.moveItem(at: temporary, to: task.destination)
        progress(1)
    }

    public static func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension ProcessInfo {
    /// 当前机器架构（用于规则匹配）。
    var machineArchitecture: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { pointer in
                String(cString: pointer)
            }
        }
        return machine
    }
}
