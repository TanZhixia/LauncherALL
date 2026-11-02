import Foundation
import Observation

// MARK: - DSH 版本管理

/// 管理本机安装的 DSH 版本：从 npm 拉版本列表、安装 / 卸载、选择当前版本。
@MainActor
@Observable
public final class DSHVersionStore {
    public let settings: LauncherSettings
    public let paths: DSHPaths
    private let client: DSHRegistryClient

    /// 远端版本目录（拉取成功后缓存到内存 + 磁盘）。
    public private(set) var catalog: DSHVersionCatalog?
    /// 本机已安装版本（按版本号倒序）。
    public private(set) var installed: [DSHInstalledVersion] = []
    public private(set) var catalogState: DSHCatalogState = .idle
    public private(set) var installState: DSHInstallState = .idle
    /// 安装日志（最近若干行，面板展示）。
    public private(set) var installLog: [String] = []
    public private(set) var lastError: DSHError?

    private var installTask: Task<Void, Never>?

    public init(
        settings: LauncherSettings = .shared,
        paths: DSHPaths = .default,
        client: DSHRegistryClient = DSHRegistryClient()
    ) {
        self.settings = settings
        self.paths = paths
        self.client = client
        refreshInstalled()
        loadCachedCatalog()
    }

    // MARK: 派生

    /// 当前选中的版本（未安装或未选择返回 nil）。
    public var selectedInstalledVersion: DSHInstalledVersion? {
        installed.first { $0.version == settings.dshSelectedVersion }
    }

    public var latestVersion: DSHVersionInfo? {
        catalog?.latest()
    }

    public var isInstalling: Bool { installState.isInstalling }

    /// 当前环境是否具备 Node / 包管理器。
    public var hasNode: Bool { DSHExecutables.node() != nil }
    public var packageManager: DSHPackageManager? { DSHExecutables.packageManager(paths: paths) }

    public var environmentText: String {
        guard let node = DSHExecutables.node() else { return "未找到 Node.js 运行时" }
        guard let manager = DSHExecutables.packageManager(paths: paths) else {
            return "Node \(node.path) · 未找到 pnpm / npm"
        }
        return "Node \(node.path) · \(manager.displayName)"
    }

    // MARK: 已安装版本

    /// 重新扫描磁盘上的已安装版本。
    public func refreshInstalled() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: paths.versionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            installed = []
            return
        }
        var result: [DSHInstalledVersion] = []
        for directory in entries {
            let version = directory.lastPathComponent
            let script = paths.cliScript(for: version)
            guard fileManager.fileExists(atPath: script.path) else { continue }
            let meta = readInstallMetadata(version: version)
            let size = meta?.sizeBytes ?? paths.directorySize(directory)
            result.append(
                DSHInstalledVersion(
                    version: version,
                    installedAt: meta?.installedAt
                        ?? (try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate)
                        ?? Date(),
                    path: directory.path,
                    sizeBytes: size
                )
            )
        }
        installed = result.sorted { DSHVersionComparator.isNewer($0.version, than: $1.version) }
        if !settings.dshSelectedVersion.isEmpty,
           !installed.contains(where: { $0.version == settings.dshSelectedVersion }) {
            settings.dshSelectedVersion = installed.first?.version ?? ""
        }
        if settings.dshSelectedVersion.isEmpty {
            settings.dshSelectedVersion = installed.first?.version ?? ""
        }
    }

    /// 选中某个已安装版本。
    public func select(_ version: String) {
        guard DSHPaths.isSafeVersion(version) else { return }
        guard installed.contains(where: { $0.version == version }) else { return }
        settings.dshSelectedVersion = version
    }

    // MARK: 版本目录

    /// 拉取 npm 上的 DSH 版本列表（失败时保留旧目录并记录状态）。
    public func refreshCatalog(force: Bool = false) async {
        if !force, catalog != nil, catalogState.isLoading == false {
            return
        }
        catalogState = .loading
        do {
            let fetched = try await client.fetchVersions(registry: settings.dshRegistry)
            catalog = fetched
            catalogState = .loaded(Date())
            lastError = nil
            saveCachedCatalog(fetched)
        } catch {
            catalogState = .failed((error as? DSHError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func loadCachedCatalog() {
        let url = paths.cacheDirectory.appendingPathComponent("versions.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? DSHRegistryClient.decodeVersionCatalog(data) else { return }
        if catalog == nil { catalog = decoded }
    }

    private func saveCachedCatalog(_ value: DSHVersionCatalog) {
        try? paths.ensureDirectories()
        let url = paths.cacheDirectory.appendingPathComponent("versions.json")
        var versionsPayload: [String: Any] = [:]
        var timePayload: [String: Any] = [:]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for entry in value.versions {
            versionsPayload[entry.version] = [
                "version": entry.version,
                "dist": [
                    "tarball": entry.tarballURL ?? "",
                    "unpackedSize": entry.unpackedSize ?? 0
                ] as [String: Any]
            ] as [String: Any]
            if let published = entry.publishedAt {
                timePayload[entry.version] = formatter.string(from: published)
            }
        }
        let payload: [String: Any] = [
            "dist-tags": value.distTags,
            "versions": versionsPayload,
            "time": timePayload
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: 安装

    /// 安装指定版本（下载 + 安装依赖 + 校验入口脚本）。
    public func install(_ version: String) async {
        guard DSHPaths.isSafeVersion(version) else {
            installState = .failed(version: version, message: DSHError.invalidVersion(version).localizedDescription)
            return
        }
        guard !isInstalling else { return }
        guard !installed.contains(where: { $0.version == version }) else {
            installState = .failed(version: version, message: "该版本已经安装")
            return
        }
        guard let node = DSHExecutables.node() else {
            installState = .failed(version: version, message: DSHError.nodeNotFound.localizedDescription)
            return
        }
        guard let manager = DSHExecutables.packageManager(paths: paths) else {
            installState = .failed(version: version, message: DSHError.packageManagerNotFound.localizedDescription)
            return
        }

        lastError = nil
        installLog = []
        installState = .installing(version: version, phase: .preparing)

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performInstall(version: version, node: node, manager: manager)
        }
        installTask = task
        await task.value
    }

    /// 取消正在进行的安装（终止子进程并清理半成品目录）。
    public func cancelInstall() {
        installTask?.cancel()
        installTask = nil
    }

    private func performInstall(version: String, node: URL, manager: DSHPackageManager) async {
        let fileManager = FileManager.default
        let directory = paths.versionDirectory(version)
        do {
            try paths.ensureDirectories()
            try? fileManager.removeItem(at: directory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let manifest = """
            {
              "name": "dsh-version-\(version)",
              "private": true
            }
            """
            try manifest.write(
                to: directory.appendingPathComponent("package.json"),
                atomically: true,
                encoding: .utf8
            )

            let environment = DSHExecutables.augmentedEnvironment(
                node: node,
                extraDirectories: manager.nodeScript == nil ? [manager.executable.deletingLastPathComponent()] : []
            )
            var lineCount = 0
            let lineHandler: @Sendable (String) -> Void = { [weak self] line in
                Task { @MainActor in
                    guard let self else { return }
                    lineCount += 1
                    if self.installLog.count < 400 { self.installLog.append(line) }
                    if case .installing(let currentVersion, let phase) = self.installState,
                       currentVersion == version {
                        let next: DSHInstallPhase = lineCount < 4 ? .downloading : .installing
                        if phase != next {
                            self.installState = .installing(version: version, phase: next)
                        }
                    }
                }
            }

            // 版本安装优先用 npm：pnpm 10+ 默认阻止依赖的构建脚本（ERR_PNPM_IGNORED_BUILDS），
            // 而 DSH 依赖 koffi / node-pty 等需要 postinstall 的原生模块。
            var result: DSHCommandRunner.Result
            if let npmCLI = DSHExecutables.npmCLI(node: node) {
                result = try await DSHCommandRunner.run(
                    executable: node,
                    arguments: [
                        npmCLI.path, "install", "@deepseek-ai/dsh@\(version)",
                        "--omit=dev", "--no-audit", "--no-fund", "--no-progress"
                    ],
                    environment: environment,
                    workingDirectory: directory,
                    onLine: lineHandler
                )
            } else if manager.kind == .npm {
                result = try await DSHCommandRunner.run(
                    executable: manager.executable,
                    arguments: [
                        "install", "@deepseek-ai/dsh@\(version)",
                        "--omit=dev", "--no-audit", "--no-fund", "--no-progress"
                    ],
                    environment: environment,
                    workingDirectory: directory,
                    onLine: lineHandler
                )
            } else {
                // 只有 pnpm 可用：先普通安装；若因构建脚本被忽略而失败，解析被忽略的包名后带 --allow-build 重试。
                result = try await DSHCommandRunner.run(
                    executable: manager.executable,
                    arguments: ["add", "@deepseek-ai/dsh@\(version)", "--reporter=append-only", "--config.strictDepBuilds=false"],
                    environment: environment,
                    workingDirectory: directory,
                    onLine: lineHandler
                )
                if result.exitCode != 0 {
                    let ignored = Self.ignoredBuildPackages(in: result.output)
                    if !ignored.isEmpty {
                        appendInstallLog("pnpm 默认阻止了构建脚本，允许 \(ignored.joined(separator: ", ")) 后重试")
                        var arguments = ["add", "@deepseek-ai/dsh@\(version)", "--reporter=append-only"]
                        for package in ignored {
                            arguments.append("--allow-build")
                            arguments.append(package)
                        }
                        result = try await DSHCommandRunner.run(
                            executable: manager.executable,
                            arguments: arguments,
                            environment: environment,
                            workingDirectory: directory,
                            onLine: lineHandler
                        )
                    }
                }
            }

            try Task.checkCancellation()
            guard result.exitCode == 0 else {
                let tail = result.output.split(separator: "\n").suffix(8).joined(separator: "\n")
                throw DSHError.installFailed(tail.isEmpty ? "包管理器退出码 \(result.exitCode)" : tail)
            }
            guard fileManager.fileExists(atPath: paths.cliScript(for: version).path) else {
                throw DSHError.installFailed("安装完成后没有找到 @deepseek-ai/dsh 入口脚本")
            }

            installState = .installing(version: version, phase: .finishing)
            let size = paths.directorySize(directory)
            writeInstallMetadata(version: version, size: size)
            refreshInstalled()
            settings.dshSelectedVersion = version
            installState = .idle
            installTask = nil
        } catch is CancellationError {
            try? fileManager.removeItem(at: directory)
            installLog.append("已取消安装，已清理半成品目录")
            installState = .idle
            installTask = nil
        } catch {
            try? fileManager.removeItem(at: directory)
            let message = (error as? DSHError)?.localizedDescription ?? error.localizedDescription
            installState = .failed(version: version, message: message)
            lastError = error as? DSHError
            installTask = nil
        }
    }

    /// 卸载版本（只删除该版本的 node_modules 与日志；共享的 DSH_HOME 不动）。
    @discardableResult
    public func uninstall(_ version: String) -> Bool {
        guard DSHPaths.isSafeVersion(version) else { return false }
        guard !isInstalling else { return false }
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: paths.versionDirectory(version))
            try? fileManager.removeItem(at: paths.isolatedHomeDirectory(for: version))
            try? fileManager.removeItem(at: paths.logFile(for: version))
            refreshInstalled()
            if settings.dshSelectedVersion == version {
                settings.dshSelectedVersion = installed.first?.version ?? ""
            }
            return true
        } catch {
            lastError = DSHError.installFailed("卸载失败：\(error.localizedDescription)")
            return false
        }
    }

    // MARK: 测试入口

    /// 测试注入版本目录（不访问网络）。
    func setCatalogForTesting(_ value: DSHVersionCatalog?) {
        catalog = value
    }

    // MARK: 安装辅助

    /// 从 pnpm 的 `ERR_PNPM_IGNORED_BUILDS` 输出里解析包名：
    /// `Ignored build scripts: a@1.0.0, @scope/b@2.0.0, ...`
    nonisolated static func ignoredBuildPackages(in output: String) -> [String] {
        guard let range = output.range(of: "Ignored build scripts:") else { return [] }
        let tail = output[range.upperBound...]
        let stop = tail.range(of: "help:")?.lowerBound ?? tail.endIndex
        let listing = tail[..<stop]
        var packages: [String] = []
        for raw in listing.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let token = raw.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }
            // 去掉结尾的 @version（scoped 包要在第一个字符之后再找 @）
            let name: String
            if token.hasPrefix("@"), let at = token.dropFirst().lastIndex(of: "@") {
                name = String(token[..<at])
            } else if let at = token.lastIndex(of: "@") {
                name = String(token[..<at])
            } else {
                name = token
            }
            if !name.isEmpty, !packages.contains(name) { packages.append(name) }
        }
        return packages
    }

    private func appendInstallLog(_ line: String) {
        if installLog.count < 400 { installLog.append(line) }
    }

    // MARK: 安装元数据

    private struct InstallMetadata: Codable {
        let version: String
        let installedAt: Date
        let sizeBytes: Int64?
    }

    private func metadataURL(_ version: String) -> URL {
        paths.versionDirectory(version).appendingPathComponent("launcher-install.json")
    }

    private func readInstallMetadata(version: String) -> InstallMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(version)) else { return nil }
        return try? JSONDecoder().decode(InstallMetadata.self, from: data)
    }

    private func writeInstallMetadata(version: String, size: Int64) {
        let metadata = InstallMetadata(version: version, installedAt: Date(), sizeBytes: size)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL(version), options: .atomic)
    }
}
