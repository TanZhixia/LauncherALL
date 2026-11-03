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

    /// 当前选中的实例（未安装或未选择返回 nil）。
    public var selectedInstalledVersion: DSHInstalledVersion? {
        installed.first { $0.id == settings.dshSelectedInstanceID }
    }

    /// 同一 DSH 版本的实例（允许一个版本装多份，每份不同名字）。
    public func instances(of dshVersion: String) -> [DSHInstalledVersion] {
        installed.filter { $0.dshVersion == dshVersion }
    }

    /// 某个 DSH 版本是否已有至少一个实例。
    public func hasInstance(of dshVersion: String) -> Bool {
        installed.contains { $0.dshVersion == dshVersion }
    }

    /// 默认实例名。
    public static func defaultName(for dshVersion: String) -> String { "DSH \(dshVersion)" }

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

    /// 重新扫描磁盘上的已安装实例（含旧版本目录迁移）。
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
            let directoryName = directory.lastPathComponent
            guard DSHPaths.isSafeInstanceID(directoryName) else { continue }
            let script = paths.cliScript(for: directoryName)
            guard fileManager.fileExists(atPath: script.path) else { continue }
            if let metadata = readInstallMetadata(instanceID: directoryName) {
                var instance = metadata
                instance = DSHInstalledVersion(
                    id: instance.id,
                    name: instance.name.isEmpty ? Self.defaultName(for: instance.dshVersion) : instance.name,
                    dshVersion: instance.dshVersion,
                    installedAt: instance.installedAt,
                    path: directory.path,
                    sizeBytes: instance.sizeBytes ?? paths.directorySize(directory),
                    kind: instance.kind,
                    packName: instance.packName,
                    packVersion: instance.packVersion,
                    legacy: instance.legacy
                )
                result.append(instance)
            } else {
                // 旧版布局：目录名就是 npm 版本号
                let installedAt = (try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                result.append(
                    DSHInstalledVersion(
                        legacyVersion: directoryName,
                        installedAt: installedAt,
                        path: directory.path,
                        sizeBytes: paths.directorySize(directory)
                    )
                )
            }
        }
        installed = result.sorted { lhs, rhs in
            if lhs.dshVersion != rhs.dshVersion {
                return DSHVersionComparator.isNewer(lhs.dshVersion, than: rhs.dshVersion)
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        migrateLegacyDataIfNeeded()
        migrateSelectionIfNeeded()
    }

    /// 旧的共享 DSH_HOME（`DSH/home`）迁移到某个旧实例独立 home，避免升级后插件/会话丢失。
    private func migrateLegacyDataIfNeeded() {
        let fileManager = FileManager.default
        let legacyHome = paths.homeRoot
        guard fileManager.fileExists(atPath: legacyHome.path),
              let legacyInstance = installed.first(where: { $0.legacy }) else { return }
        let target = paths.homeDirectory(for: legacyInstance.id)
        guard !fileManager.fileExists(atPath: target.path) else { return }
        do {
            try fileManager.createDirectory(at: paths.homesDirectory, withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacyHome, to: target)
        } catch {
            // 迁移失败不阻塞启动：启动时会重新种子凭据
        }
    }

    private func migrateSelectionIfNeeded() {
        if settings.dshSelectedInstanceID.isEmpty,
           let legacySelected = installed.first(where: { $0.version == settings.dshSelectedVersion }) {
            settings.dshSelectedInstanceID = legacySelected.id
        }
        if !settings.dshSelectedInstanceID.isEmpty,
           !installed.contains(where: { $0.id == settings.dshSelectedInstanceID }) {
            settings.dshSelectedInstanceID = installed.first?.id ?? ""
        }
        if settings.dshSelectedInstanceID.isEmpty {
            settings.dshSelectedInstanceID = installed.first?.id ?? ""
        }
    }

    /// 选中某个实例。
    public func select(_ instanceID: String) {
        guard DSHPaths.isSafeInstanceID(instanceID) else { return }
        guard installed.contains(where: { $0.id == instanceID }) else { return }
        settings.dshSelectedInstanceID = instanceID
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

    /// 安装指定 DSH 版本（可自定义实例名；同名 / 同版本都允许多开）。
    ///
    /// - Parameters:
    ///   - dshVersion: npm 上的 `@deepseek-ai/dsh` 版本号。
    ///   - name: 实例显示名；nil 时使用「DSH <版本号>」。
    public func install(_ dshVersion: String, name: String? = nil) async {
        guard DSHPaths.isSafeVersion(dshVersion) else {
            installState = .failed(version: dshVersion, message: DSHError.invalidVersion(dshVersion).localizedDescription)
            return
        }
        guard !isInstalling else { return }
        guard let node = DSHExecutables.node() else {
            installState = .failed(version: dshVersion, message: DSHError.nodeNotFound.localizedDescription)
            return
        }
        guard let manager = DSHExecutables.packageManager(paths: paths) else {
            installState = .failed(version: dshVersion, message: DSHError.packageManagerNotFound.localizedDescription)
            return
        }

        let instanceID = UUID().uuidString.lowercased()
        let instanceName = Self.normalizedInstanceName(name, fallback: Self.defaultName(for: dshVersion))
        lastError = nil
        installLog = []
        installState = .installing(version: dshVersion, phase: .preparing)

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performInstall(
                instanceID: instanceID,
                dshVersion: dshVersion,
                name: instanceName,
                node: node,
                manager: manager
            )
        }
        installTask = task
        await task.value
    }

    /// 规范化实例名：去首尾空白、压缩连续空白、限制长度；空名回退默认名。
    static func normalizedInstanceName(_ name: String?, fallback: String) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        let collapsed = trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(60))
    }

    /// 取消正在进行的安装（终止子进程并清理半成品目录）。
    public func cancelInstall() {
        installTask?.cancel()
        installTask = nil
    }

    private func performInstall(
        instanceID: String,
        dshVersion: String,
        name: String,
        node: URL,
        manager: DSHPackageManager
    ) async {
        let fileManager = FileManager.default
        let directory = paths.versionDirectory(instanceID)
        do {
            try paths.ensureDirectories()
            try? fileManager.removeItem(at: directory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let manifest = """
            {
              "name": "dsh-instance-\(instanceID)",
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
                       currentVersion == dshVersion {
                        let next: DSHInstallPhase = lineCount < 4 ? .downloading : .installing
                        if phase != next {
                            self.installState = .installing(version: dshVersion, phase: next)
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
                        npmCLI.path, "install", "@deepseek-ai/dsh@\(dshVersion)",
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
                        "install", "@deepseek-ai/dsh@\(dshVersion)",
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
                    arguments: ["add", "@deepseek-ai/dsh@\(dshVersion)", "--reporter=append-only", "--config.strictDepBuilds=false"],
                    environment: environment,
                    workingDirectory: directory,
                    onLine: lineHandler
                )
                if result.exitCode != 0 {
                    let ignored = Self.ignoredBuildPackages(in: result.output)
                    if !ignored.isEmpty {
                        appendInstallLog("pnpm 默认阻止了构建脚本，允许 \(ignored.joined(separator: ", ")) 后重试")
                        var arguments = ["add", "@deepseek-ai/dsh@\(dshVersion)", "--reporter=append-only"]
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
            guard fileManager.fileExists(atPath: paths.cliScript(for: instanceID).path) else {
                throw DSHError.installFailed("安装完成后没有找到 @deepseek-ai/dsh 入口脚本")
            }

            installState = .installing(version: dshVersion, phase: .finishing)
            let size = paths.directorySize(directory)
            writeInstallMetadata(
                instanceID: instanceID,
                dshVersion: dshVersion,
                name: name,
                size: size,
                kind: .vanilla
            )
            refreshInstalled()
            settings.dshSelectedInstanceID = instanceID
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
            installState = .failed(version: dshVersion, message: message)
            lastError = error as? DSHError
            installTask = nil
        }
    }

    /// 卸载实例（只删除该实例的 node_modules、独立 DSH_HOME 与日志）。
    @discardableResult
    public func uninstall(_ instanceID: String) -> Bool {
        guard DSHPaths.isSafeInstanceID(instanceID) else { return false }
        guard !isInstalling else { return false }
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: paths.versionDirectory(instanceID))
            try? fileManager.removeItem(at: paths.homeDirectory(for: instanceID))
            try? fileManager.removeItem(at: paths.logFile(for: instanceID))
            refreshInstalled()
            if settings.dshSelectedInstanceID == instanceID {
                settings.dshSelectedInstanceID = installed.first?.id ?? ""
            }
            return true
        } catch {
            lastError = DSHError.installFailed("卸载失败：\(error.localizedDescription)")
            return false
        }
    }

    /// 创建一个「从整合包导入」的实例元数据（运行时由整合包服务写入后调用）。
    public func adoptImportedInstance(
        instanceID: String,
        name: String,
        dshVersion: String,
        size: Int64,
        packName: String,
        packVersion: String?
    ) {
        writeInstallMetadata(
            instanceID: instanceID,
            dshVersion: dshVersion,
            name: name,
            size: size,
            kind: .pack,
            packName: packName,
            packVersion: packVersion
        )
        refreshInstalled()
        settings.dshSelectedInstanceID = instanceID
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

    private func metadataURL(_ instanceID: String) -> URL {
        paths.versionDirectory(instanceID).appendingPathComponent("launcher-install.json")
    }

    private func readInstallMetadata(instanceID: String) -> DSHInstalledVersion? {
        guard let data = try? Data(contentsOf: metadataURL(instanceID)) else { return nil }
        return try? JSONDecoder().decode(DSHInstalledVersion.self, from: data)
    }

    private func writeInstallMetadata(
        instanceID: String,
        dshVersion: String,
        name: String,
        size: Int64,
        kind: DSHInstanceKind,
        packName: String? = nil,
        packVersion: String? = nil
    ) {
        let metadata = DSHInstalledVersion(
            id: instanceID,
            name: name,
            dshVersion: dshVersion,
            installedAt: Date(),
            path: paths.versionDirectory(instanceID).path,
            sizeBytes: size,
            kind: kind,
            packName: packName,
            packVersion: packVersion,
            legacy: false
        )
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL(instanceID), options: .atomic)
    }
}
