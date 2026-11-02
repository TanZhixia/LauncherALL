import Foundation
import Observation

// MARK: - DSH 插件市场

/// 插件排序方式。
public enum DSHPluginSort: String, CaseIterable, Identifiable, Sendable {
    case stars
    case name
    case updated

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .stars: return "按热度"
        case .name: return "按名称"
        case .updated: return "按收录时间"
        }
    }
}

/// 当前正在进行的插件操作。
public enum DSHPluginOperation: Equatable, Sendable {
    case installing(String)
    case removing(String)

    public var pluginID: String {
        switch self {
        case .installing(let id), .removing(let id): return id
        }
    }

    public var isInstalling: Bool {
        if case .installing = self { return true }
        return false
    }
}

/// dshmarket 加载源驱动的插件市场：搜索 / 分类 / 安装 / 卸载。
/// 安装走当前 DSH 版本的 `dsh plugin --profile web add <spec>`（与官方插件管理一致）。
@MainActor
@Observable
public final class DSHPluginStore {
    public let settings: LauncherSettings
    public let paths: DSHPaths
    private let client: DSHRegistryClient

    public private(set) var catalog: DSHPluginCatalog?
    public private(set) var catalogState: DSHCatalogState = .idle
    public private(set) var operation: DSHPluginOperation?
    public private(set) var lastError: DSHError?
    public private(set) var operationLog: [String] = []

    /// 搜索文本（名称 / 作者 / 描述 / 包名）。
    public var searchText: String = ""
    /// 分类过滤（nil = 全部）。
    public var selectedCategoryID: String?
    /// 排序。
    public var sortMode: DSHPluginSort = .stars

    private var loadTask: Task<Void, Never>?
    private var operationTask: Task<Bool, Never>?

    public init(
        settings: LauncherSettings = .shared,
        paths: DSHPaths = .default,
        client: DSHRegistryClient = DSHRegistryClient()
    ) {
        self.settings = settings
        self.paths = paths
        self.client = client
    }

    // MARK: 派生

    public var categories: [DSHPluginCategory] { catalog?.categories ?? [] }
    public var pluginCount: Int { catalog?.plugins.count ?? 0 }
    public var sourceText: String { catalog?.sourceURL ?? settings.dshPluginSource }
    public var updatedText: String? { catalog?.updated }
    public var isBusy: Bool { operation != nil }

    /// 根据搜索 / 分类 / 排序过滤后的插件列表。
    public var filteredPlugins: [DSHPluginEntry] {
        guard let catalog else { return [] }
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result: [DSHPluginEntry]
        if keyword.isEmpty {
            result = catalog.plugins
        } else {
            result = catalog.plugins.filter { entry in
                let haystack = [
                    entry.name,
                    entry.owner,
                    entry.npm ?? "",
                    entry.category ?? "",
                    entry.descriptionZH ?? "",
                    entry.descriptionEN ?? ""
                ].joined(separator: " ").lowercased()
                return haystack.contains(keyword)
            }
        }
        if let category = selectedCategoryID {
            result = result.filter { $0.category == category }
        }
        switch sortMode {
        case .stars:
            result.sort { ($0.stars ?? 0, $0.name) > ($1.stars ?? 0, $1.name) }
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .updated:
            result.sort { ($0.added ?? "", $0.name) > ($1.added ?? "", $1.name) }
        }
        return result
    }

    // MARK: 目录

    /// 加载插件加载源：优先网络，失败回退磁盘缓存。
    public func refresh(force: Bool = false) async {
        guard !catalogState.isLoading else { return }
        if !force, catalog != nil { return }
        catalogState = .loading
        lastError = nil
        do {
            let fetched = try await client.fetchPluginCatalog(source: settings.dshPluginSource)
            catalog = fetched
            catalogState = .loaded(Date())
            saveCachedCatalog(fetched)
        } catch {
            if let cached = loadCachedCatalog() {
                catalog = cached
                catalogState = .failed("刷新失败，已使用本地缓存（\(error.localizedDescription)）")
            } else {
                catalogState = .failed((error as? DSHError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    /// App 启动时先用本地缓存渲染，再按需刷新。
    public func loadCachedCatalogIfNeeded() {
        guard catalog == nil else { return }
        if let cached = loadCachedCatalog() {
            catalog = cached
            if case .idle = catalogState { catalogState = .loaded(cached.fetchedAt) }
        }
    }

    private var cacheURL: URL { paths.cacheDirectory.appendingPathComponent("plugins.json") }

    private func loadCachedCatalog() -> DSHPluginCatalog? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        do {
            return try Self.decodeCatalog(data, sourceURL: settings.dshPluginSource)
        } catch {
            return nil
        }
    }

    private func saveCachedCatalog(_ value: DSHPluginCatalog) {
        try? paths.ensureDirectories()
        let payload: [String: Any] = [
            "name": "LauncherALL cached plugin catalog",
            "url": value.sourceURL,
            "updated": value.updated ?? "",
            "categories": Dictionary(uniqueKeysWithValues: value.categories.map { category in
                (category.id, ["en": category.titleEN, "zh": category.titleZH])
            }),
            "plugins": value.plugins.map(Self.encodeEntry)
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private static func decodeCatalog(_ data: Data, sourceURL: String) throws -> DSHPluginCatalog {
        let file = try JSONDecoder().decode(DSHPluginCatalogFile.self, from: data)
        let categories = file.categories
            .map { DSHPluginCategory(id: $0.key, titleEN: $0.value.en ?? $0.key, titleZH: $0.value.zh ?? $0.key) }
            .sorted { $0.id < $1.id }
        return DSHPluginCatalog(
            plugins: file.plugins,
            categories: categories,
            updated: file.updated,
            sourceURL: sourceURL,
            fetchedAt: Date()
        )
    }

    private static func encodeEntry(_ entry: DSHPluginEntry) -> [String: Any] {
        var payload: [String: Any] = [
            "name": entry.name,
            "owner": entry.owner,
            "url": entry.url,
            "capabilities": entry.capabilities
        ]
        payload["page"] = entry.page
        payload["category"] = entry.category
        payload["npm"] = entry.npm
        payload["version"] = entry.version
        payload["stars"] = entry.stars
        payload["downloads"] = entry.downloads
        payload["install"] = entry.install
        payload["added"] = entry.added
        payload["icon"] = entry.icon
        payload["description"] = ["en": entry.descriptionEN ?? "", "zh": entry.descriptionZH ?? ""]
        return payload
    }

    // MARK: 已安装

    /// 读取某版本 profile 的已安装插件（profile/package.json 的 dependencies）。
    public func installedPlugins(for version: DSHInstalledVersion) -> [DSHInstalledPlugin] {
        let manifestURL = paths.profileDirectory(for: version.version).appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        struct Manifest: Decodable {
            let dependencies: [String: String]?
        }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              let dependencies = manifest.dependencies else { return [] }
        return dependencies
            .map { DSHInstalledPlugin(dependencyKey: $0.key, version: $0.value) }
            .sorted { $0.dependencyKey < $1.dependencyKey }
    }

    public func isInstalled(_ entry: DSHPluginEntry, in version: DSHInstalledVersion) -> Bool {
        guard let spec = entry.installSpec else { return false }
        let installed = installedPlugins(for: version)
        return installed.contains { plugin in
            // pnpm 对 npm 包写 key=包名 value=版本号；对 github/git 依赖写 key=包名 value=spec
            plugin.dependencyKey == spec
                || plugin.version == spec
                || plugin.dependencyKey == entry.name
                || (entry.npm.map { plugin.dependencyKey == $0 } ?? false)
        }
    }

    // MARK: 测试入口

    /// 测试注入插件目录（不访问网络）。
    func setCatalogForTesting(_ value: DSHPluginCatalog?) {
        catalog = value
        if case .idle = catalogState, value != nil { catalogState = .loaded(Date()) }
    }

    // MARK: 安装 / 卸载

    /// 安装插件到指定版本的 web profile。
    @discardableResult
    public func install(_ entry: DSHPluginEntry, into version: DSHInstalledVersion) async -> Bool {
        guard operation == nil else { return false }
        guard let rawSpec = entry.installSpec else {
            lastError = .pluginInstallFailed("该插件没有可用的安装标识（npm 包名 / install 命令）")
            return false
        }
        let spec = rawSpec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spec.isEmpty, !spec.hasPrefix("-"), !spec.contains(" ") else {
            lastError = .pluginInstallFailed("插件安装标识不合法：\(rawSpec)")
            return false
        }
        return await runPluginCommand(
            operation: .installing(entry.id),
            arguments: ["plugin", "--profile", "web", "add", spec],
            version: version,
            failure: { DSHError.pluginInstallFailed($0) }
        )
    }

    /// 从指定版本卸载插件。
    @discardableResult
    public func remove(_ plugin: DSHInstalledPlugin, from version: DSHInstalledVersion) async -> Bool {
        guard operation == nil else { return false }
        return await runPluginCommand(
            operation: .removing(plugin.id),
            arguments: ["plugin", "--profile", "web", "remove", plugin.dependencyKey],
            version: version,
            failure: { DSHError.pluginRemoveFailed($0) }
        )
    }

    public func cancelOperation() {
        operationTask?.cancel()
        operationTask = nil
    }

    private func runPluginCommand(
        operation nextOperation: DSHPluginOperation,
        arguments: [String],
        version: DSHInstalledVersion,
        failure: @escaping (String) -> DSHError
    ) async -> Bool {
        guard let node = DSHExecutables.node() else {
            lastError = .nodeNotFound
            return false
        }
        let script = paths.cliScript(for: version.version)
        guard FileManager.default.fileExists(atPath: script.path) else {
            lastError = .notInstalled(version.version)
            return false
        }
        // dsh 的 plugin 命令转发给 pnpm：没有系统 pnpm 时用 DSH 桌面端自带的 pnpm 生成 shim
        if DSHExecutables.systemPnpm() == nil, let bundled = DSHExecutables.bundledPnpmScript() {
            if let shim = try? DSHExecutables.makePnpmShim(paths: paths, node: node, script: bundled) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
            }
        }
        let home = paths.homeDirectory(for: version.version)
        try? paths.ensureDirectories()
        paths.seedSharedHomeIfNeeded()
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        // 只有没有系统 pnpm 时才把 launcher 生成的 shim 目录前置，避免旧 shim 遮蔽系统 pnpm
        let extraDirectories = DSHExecutables.systemPnpm() == nil ? [paths.binDirectory] : []
        var environment = DSHExecutables.augmentedEnvironment(
            node: node,
            extraDirectories: extraDirectories
        )
        environment["DSH_HOME"] = home.path

        lastError = nil
        operationLog = []
        operation = nextOperation
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            do {
                let result = try await DSHCommandRunner.run(
                    executable: node,
                    arguments: [script.path] + arguments,
                    environment: environment,
                    workingDirectory: home
                ) { [weak self] line in
                    Task { @MainActor in
                        guard let self else { return }
                        if self.operationLog.count < 300 { self.operationLog.append(line) }
                    }
                }
                try Task.checkCancellation()
                guard result.exitCode == 0 else {
                    let tail = result.output.split(separator: "\n").suffix(6).joined(separator: "\n")
                    throw failure(tail.isEmpty ? "命令退出码 \(result.exitCode)" : tail)
                }
                return true
            } catch is CancellationError {
                return false
            } catch {
                lastError = error as? DSHError ?? failure(error.localizedDescription)
                return false
            }
        }
        operationTask = task
        let success = await task.value
        operation = nil
        operationTask = nil
        return success
    }
}
