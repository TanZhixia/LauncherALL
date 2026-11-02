import Foundation

// MARK: - 目录数据

/// npm 上的 DSH 版本目录。
public struct DSHVersionCatalog: Sendable, Equatable {
    public let versions: [DSHVersionInfo]
    public let distTags: [String: String]
    public let fetchedAt: Date

    public init(versions: [DSHVersionInfo], distTags: [String: String], fetchedAt: Date) {
        self.versions = versions
        self.distTags = distTags
        self.fetchedAt = fetchedAt
    }

    public func latest(tag: String = "latest") -> DSHVersionInfo? {
        guard let version = distTags[tag] else { return nil }
        return versions.first { $0.version == version }
    }
}

/// dshmarket 加载源（`plugins.json`）解析后的目录。
public struct DSHPluginCatalog: Sendable, Equatable {
    public let plugins: [DSHPluginEntry]
    public let categories: [DSHPluginCategory]
    public let updated: String?
    public let sourceURL: String
    public let fetchedAt: Date

    public init(
        plugins: [DSHPluginEntry],
        categories: [DSHPluginCategory],
        updated: String?,
        sourceURL: String,
        fetchedAt: Date
    ) {
        self.plugins = plugins
        self.categories = categories
        self.updated = updated
        self.sourceURL = sourceURL
        self.fetchedAt = fetchedAt
    }
}

// MARK: - 网络客户端

/// DSH 相关网络请求：npm 版本列表 + dshmarket 插件加载源。
public struct DSHRegistryClient: Sendable {
    public static let defaultRegistry = "https://registry.npmjs.org"
    /// 默认插件加载源：dshmarket 自己使用的数据源（awesome-dsh-plugin 的 plugins.json）。
    public static let defaultPluginSource = "https://awesome-dsh-plugin.com/plugins.json"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: 版本

    /// 拉取 `@deepseek-ai/dsh` 的全部版本。
    public func fetchVersions(
        registry: String = DSHRegistryClient.defaultRegistry
    ) async throws -> DSHVersionCatalog {
        let url = try Self.versionsURL(registry: registry)

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(response, data: data)
        return try Self.decodeVersionCatalog(data)
    }

    /// 构造 npm 版本目录 URL：包名里的 `/` 必须编码成 `%2f`，且不能重复编码。
    static func versionsURL(registry: String = DSHRegistryClient.defaultRegistry) throws -> URL {
        let trimmed = registry.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? Self.defaultRegistry : trimmed
        guard var components = URLComponents(string: base),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil else {
            throw DSHError.network("版本源地址无效：\(registry)")
        }
        let encodedPath = components.percentEncodedPath
        let path = encodedPath.hasSuffix("/") ? encodedPath : encodedPath + "/"
        components.percentEncodedPath = path + "@deepseek-ai%2fdsh"
        guard let url = components.url else {
            throw DSHError.network("版本源地址无效：\(registry)")
        }
        return url
    }

    static func decodeVersionCatalog(_ data: Data) throws -> DSHVersionCatalog {
        struct Document: Decodable {
            let versions: [String: Entry]
            let distTags: [String: String]
            let time: [String: String]?

            enum CodingKeys: String, CodingKey {
                case versions
                case distTags = "dist-tags"
                case time
            }

            struct Entry: Decodable {
                let version: String
                let dist: Distribution

                struct Distribution: Decodable {
                    let tarball: String?
                    let unpackedSize: Int64?
                }
            }
        }

        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw DSHError.invalidResponse("DSH 版本列表解析失败：\(error.localizedDescription)")
        }

        var tagsByVersion: [String: [String]] = [:]
        for (tag, version) in document.distTags {
            tagsByVersion[version, default: []].append(tag)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        var versions: [DSHVersionInfo] = []
        for (version, entry) in document.versions {
            let published = document.time?[version].flatMap { text in
                formatter.date(from: text) ?? fallbackFormatter.date(from: text)
            }
            let tags = (tagsByVersion[version] ?? []).sorted()
            versions.append(
                DSHVersionInfo(
                    version: entry.version.isEmpty ? version : entry.version,
                    publishedAt: published,
                    tarballURL: entry.dist.tarball,
                    unpackedSize: entry.dist.unpackedSize,
                    distTags: tags
                )
            )
        }
        versions.sort { DSHVersionComparator.isNewer($0.version, than: $1.version) }
        return DSHVersionCatalog(versions: versions, distTags: document.distTags, fetchedAt: Date())
    }

    // MARK: 插件市场

    /// 拉取 dshmarket 使用的插件加载源。
    public func fetchPluginCatalog(source: String = DSHRegistryClient.defaultPluginSource) async throws -> DSHPluginCatalog {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else {
            throw DSHError.network("插件加载源地址无效：\(source)")
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(response, data: data)

        let file: DSHPluginCatalogFile
        do {
            file = try JSONDecoder().decode(DSHPluginCatalogFile.self, from: data)
        } catch {
            throw DSHError.invalidResponse("插件加载源解析失败：\(error.localizedDescription)")
        }
        let categories = file.categories
            .map { key, payload in
                DSHPluginCategory(id: key, titleEN: payload.en ?? key, titleZH: payload.zh ?? key)
            }
            .sorted { $0.id < $1.id }
        return DSHPluginCatalog(
            plugins: file.plugins,
            categories: categories,
            updated: file.updated,
            sourceURL: trimmed,
            fetchedAt: Date()
        )
    }

    // MARK: 通用

    static func ensureSuccess(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DSHError.invalidResponse("不是 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw DSHError.network("HTTP \(http.statusCode)\(body.isEmpty ? "" : "：\(body)")")
        }
    }
}
