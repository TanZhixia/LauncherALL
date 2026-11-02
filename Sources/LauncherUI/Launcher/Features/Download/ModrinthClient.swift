import Foundation

// MARK: - 项目类型

/// Modrinth 项目类型：与搜索接口的 `project_type` 取值一一对应。
/// 下载页左侧六个「社区资源」分类各对应一种类型。
public enum ModrinthProjectType: String, CaseIterable, Sendable, Equatable {
    case modpack
    case mod
    case resourcepack
    case shader
    case world
    case datapack

    /// 分类标题（左侧分类 / 详情面板）。
    public var title: String {
        switch self {
        case .modpack: return "整合包"
        case .mod: return "模组"
        case .resourcepack: return "资源包"
        case .shader: return "光影包"
        case .world: return "世界"
        case .datapack: return "数据包"
        }
    }

    /// 分类图标（左侧分类、结果行与详情面板共用）。
    public var systemImage: String {
        switch self {
        case .modpack: return "shippingbox"
        case .mod: return "puzzlepiece.extension.fill"
        case .resourcepack: return "paintpalette.fill"
        case .shader: return "sparkles"
        case .world: return "globe"
        case .datapack: return "doc.zipper"
        }
    }

    /// 安装后落到实例目录的哪个子目录；`nil` 表示需要解压到 `saves/<世界名>`。
    public var installSubdirectory: String? {
        switch self {
        case .modpack: return nil
        case .mod: return "mods"
        case .resourcepack: return "resourcepacks"
        case .shader: return "shaderpacks"
        case .world: return nil
        case .datapack: return "datapacks"
        }
    }

    /// 是否是「下载单个文件到实例目录」的资源（整合包与世界另有安装流程）。
    public var isSingleFileResource: Bool {
        switch self {
        case .mod, .resourcepack, .shader, .datapack: return true
        case .modpack, .world: return false
        }
    }

    /// 安装位置说明（详情面板一行提示）。
    public var destinationHint: String {
        switch self {
        case .modpack: return "将新建实例：基础版本 + 加载器 + 整合包文件"
        case .world: return "下载后解压到实例 saves/ 目录"
        case .mod, .resourcepack, .shader, .datapack:
            return "下载到实例 \(installSubdirectory ?? "")/ 目录"
        }
    }
}

// MARK: - 搜索

/// Modrinth 搜索接口返回的一个项目摘要（只解码启动器用得到的字段）。
public struct ModrinthSearchHit: Decodable, Identifiable, Sendable, Equatable {
    /// 项目 id（详情与版本接口都用它）。
    public let projectID: String
    /// 项目 slug（人类可读 id）。
    public let slug: String
    public let title: String
    /// 一句话简介（接口字段名是 `description`，这里改名避免与 CustomStringConvertible 混淆）。
    public let summary: String
    public let projectType: String
    public let author: String?
    public let categories: [String]
    public let versions: [String]
    public let downloads: Int
    public let follows: Int
    public let dateModified: String?
    public let latestVersionID: String?

    public var id: String { projectID }

    /// 作者名（缺失时给明确兜底，避免详情面板出现空白）。
    public var authorText: String {
        guard let author, !author.isEmpty else { return "未知作者" }
        return author
    }

    /// 下载量人读文本。
    public var downloadsText: String { ModrinthFormat.downloads(downloads) }

    /// 最近更新时间（只取日期部分）。
    public var updatedText: String { ModrinthFormat.date(dateModified) }

    private enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case slug
        case title
        case summary = "description"
        case projectType = "project_type"
        case author
        case categories
        case versions
        case downloads
        case follows
        case dateModified = "date_modified"
        case latestVersionID = "latest_version"
    }
}

/// Modrinth 搜索接口的一页结果。
public struct ModrinthSearchPage: Decodable, Sendable, Equatable {
    public let hits: [ModrinthSearchHit]
    public let offset: Int
    public let limit: Int
    public let totalHits: Int

    /// 是否还有下一页。
    public var hasMore: Bool {
        offset + hits.count < totalHits && !hits.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case hits
        case offset
        case limit
        case totalHits = "total_hits"
    }
}

// MARK: - 版本与文件

/// Modrinth 的一个版本（含可下载文件）。
public struct ModrinthVersion: Decodable, Identifiable, Sendable, Equatable {
    /// 版本附带的文件。
    public struct File: Decodable, Sendable, Equatable {
        public let url: URL
        public let filename: String
        public let size: Int64
        public let primary: Bool
        public let hashes: [String: String]

        public var sha1: String? { hashes["sha1"] }
        public var sha512: String? { hashes["sha512"] }

        /// 文件大小人读文本。
        public var sizeText: String { ModrinthFormat.fileSize(size) }
    }

    public let id: String
    public let projectID: String
    public let name: String
    public let versionNumber: String
    public let versionType: String
    public let gameVersions: [String]
    public let loaders: [String]
    public let datePublished: String
    public let downloads: Int
    public let files: [File]

    /// 主文件（多个文件时安装主文件）。
    public var primaryFile: File? {
        files.first { $0.primary } ?? files.first
    }

    /// 版本 + 支持的游戏版本，用于详情面板一行说明。
    public var detailText: String {
        var parts = [versionNumber]
        if let game = gameVersions.first { parts.append("MC \(game)") }
        if !loaders.isEmpty { parts.append(loaders.prefix(2).joined(separator: " / ")) }
        return parts.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case name
        case versionNumber = "version_number"
        case versionType = "version_type"
        case gameVersions = "game_versions"
        case loaders
        case datePublished = "date_published"
        case downloads
        case files
    }
}

// MARK: - 错误

/// Modrinth 请求错误：网络 / HTTP / 解码。
public enum ModrinthError: LocalizedError, Equatable {
    case invalidURL
    case http(Int)
    case transport(String)
    case decoding(String)
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Modrinth 请求地址无效"
        case .http(let code): return "Modrinth 请求失败（HTTP \(code)）"
        case .transport(let message): return "Modrinth 网络错误：\(message)"
        case .decoding(let message): return "Modrinth 数据解析失败：\(message)"
        case .emptyResult: return "Modrinth 没有返回可安装的文件"
        }
    }
}

// MARK: - 地址构造（纯函数，便于测试）

/// Modrinth 公开 API 的地址构造。
/// 全部是纯函数：不读网络、不读全局状态，单元测试可以直接断言。
public enum ModrinthEndpoint {
    /// Modrinth 公开 API 根地址。
    public static let baseURL = URL(string: "https://api.modrinth.com/v2")!

    /// Fabric 加载器版本清单（profile/json 直接就是一份可写入 versions 的版本 JSON）。
    public static let fabricMetaBase = URL(string: "https://meta.fabricmc.net/v2")!
    /// Quilt 加载器版本清单。
    public static let quiltMetaBase = URL(string: "https://meta.quiltmc.org/v3")!

    /// 搜索接口地址。
    /// - Parameters:
    ///   - projectType: 项目类型（作为 `project_type:` 分面）。
    ///   - gameVersion: Minecraft 版本（作为 `versions:` 分面）；传 nil 表示按最新正式版之外的全量搜索。
    ///   - query: 搜索词，空串表示按排序浏览。
    ///   - index: 排序方式（relevance / downloads / follows / newest / updated）。
    public static func search(
        projectType: ModrinthProjectType,
        gameVersion: String?,
        query: String,
        limit: Int,
        offset: Int,
        index: String = "relevance"
    ) -> URL? {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items: [URLQueryItem] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "query", value: trimmed))
        }
        items.append(URLQueryItem(name: "facets", value: facets(projectType: projectType, gameVersion: gameVersion)))
        items.append(URLQueryItem(name: "limit", value: String(max(1, min(limit, 100)))))
        items.append(URLQueryItem(name: "offset", value: String(max(0, offset))))
        items.append(URLQueryItem(name: "index", value: index))
        components.queryItems = items
        return components.url
    }

    /// 搜索分面 JSON：`[["project_type:mod"],["versions:1.21.4"]]`。
    public static func facets(projectType: ModrinthProjectType, gameVersion: String?) -> String {
        var groups: [String] = ["[\"project_type:\(projectType.rawValue)\"]"]
        if let gameVersion, !gameVersion.isEmpty {
            groups.append("[\"versions:\(gameVersion)\"]")
        }
        return "[" + groups.joined(separator: ",") + "]"
    }

    /// 某个项目的版本列表地址（按游戏版本 / 加载器过滤）。
    public static func projectVersions(
        projectID: String,
        gameVersion: String?,
        loaders: [String] = []
    ) -> URL? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("project/\(projectID)/version"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        var items: [URLQueryItem] = []
        if let gameVersion, !gameVersion.isEmpty {
            items.append(URLQueryItem(name: "game_versions", value: jsonArray([gameVersion])))
        }
        if !loaders.isEmpty {
            items.append(URLQueryItem(name: "loaders", value: jsonArray(loaders)))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    /// Fabric 加载器 profile JSON 地址：返回的内容可以直接作为版本 JSON 写入 `versions/<id>/`。
    public static func fabricLoaderProfile(minecraft: String, loader: String) -> URL? {
        fabricMetaBase
            .appendingPathComponent("versions/loader/\(minecraft)/\(loader)/profile/json")
    }

    /// Quilt 加载器 profile JSON 地址。
    public static func quiltLoaderProfile(minecraft: String, loader: String) -> URL? {
        quiltMetaBase
            .appendingPathComponent("versions/loader/\(minecraft)/\(loader)/profile/json")
    }

    /// `["a","b"]` 形式的 JSON 数组字符串（查询参数里 Modrinth 要求 JSON 数组）。
    public static func jsonArray(_ values: [String]) -> String {
        let escaped = values.map { value -> String in
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return "[" + escaped.joined(separator: ",") + "]"
    }
}

// MARK: - 客户端

/// Modrinth 公开 API 客户端：带 User-Agent、统一错误处理，可直接注入自定义 URLSession 做测试。
public struct ModrinthClient: Sendable {
    /// Modrinth 要求每个请求都带可识别的 User-Agent。
    public static var userAgent: String {
        "BlockLauncher/\(LauncherBuildInfo.current.version) (local)"
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// 搜索项目。
    public func search(
        projectType: ModrinthProjectType,
        gameVersion: String?,
        query: String,
        limit: Int = 20,
        offset: Int = 0,
        index: String = "relevance"
    ) async throws -> ModrinthSearchPage {
        guard let url = ModrinthEndpoint.search(
            projectType: projectType,
            gameVersion: gameVersion,
            query: query,
            limit: limit,
            offset: offset,
            index: index
        ) else {
            throw ModrinthError.invalidURL
        }
        return try await get(url)
    }

    /// 拉取某个项目在当前游戏版本下可用的版本列表（接口按发布时间倒序，第一个即最新）。
    public func versions(
        projectID: String,
        gameVersion: String?,
        loaders: [String] = []
    ) async throws -> [ModrinthVersion] {
        guard let url = ModrinthEndpoint.projectVersions(
            projectID: projectID,
            gameVersion: gameVersion,
            loaders: loaders
        ) else {
            throw ModrinthError.invalidURL
        }
        return try await get(url)
    }

    /// 下载任意二进制数据（加载器 profile / .mrpack 由各自的下载器处理，这里只给解析用的小文件）。
    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ModrinthError.http(http.statusCode)
            }
            return data
        } catch let error as ModrinthError {
            throw error
        } catch {
            throw ModrinthError.transport(error.localizedDescription)
        }
    }

    // MARK: 内部

    /// 统一的 GET + 解码。
    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ModrinthError.http(http.statusCode)
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw ModrinthError.decoding(error.localizedDescription)
            }
        } catch let error as ModrinthError {
            throw error
        } catch {
            throw ModrinthError.transport(error.localizedDescription)
        }
    }
}

// MARK: - 人读格式

/// 社区资源相关的人读格式（下载量 / 文件大小 / 日期）。
public enum ModrinthFormat {
    /// 下载量：一万以上用「万」，一亿以上用「亿」，保留一位小数。
    public static func downloads(_ value: Int) -> String {
        if value >= 100_000_000 {
            return String(format: "%.1f 亿", Double(value) / 100_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.1f 万", Double(value) / 10_000)
        }
        return "\(value)"
    }

    /// 文件大小：0 值统一显示 "0 B"（ByteCountFormatter 会输出英文 "Zero KB"），其余交给系统格式化。
    public static func fileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// ISO8601 时间串 → 日期（解析失败时原样截取前 10 位）。
    public static func date(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        return String(raw.prefix(10))
    }
}
