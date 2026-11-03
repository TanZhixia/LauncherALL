import Foundation
import Observation

// MARK: - DSH 整合包导入 / 导出

/// LauncherALL 私有 DSH 整合包（`.dshpack`）的导入 / 导出：
/// - 导出的包可携带 DSH 本体（bundled，离线可用）或只记录版本号（online）；
/// - 可附带插件 npm tarball 作为离线载荷；
/// - 导入时创建独立实例（可自定义名字），插件装进该实例自己的 web profile。
@MainActor
@Observable
public final class DSHPackService {
    public let paths: DSHPaths
    public let versions: DSHVersionStore
    public let plugins: DSHPluginStore
    public let settings: LauncherSettings

    public private(set) var state: DSHPackState = .idle
    public private(set) var logLines: [String] = []
    public private(set) var lastError: DSHPackError?

    private var exportTask: Task<URL?, Never>?
    private var importTask: Task<DSHInstalledVersion?, Never>?
    private var isCancelled = false

    public init(
        paths: DSHPaths = .default,
        versions: DSHVersionStore,
        plugins: DSHPluginStore,
        settings: LauncherSettings = .shared
    ) {
        self.paths = paths
        self.versions = versions
        self.plugins = plugins
        self.settings = settings
    }

    public var isBusy: Bool { state.isBusy }

    public func cancel() {
        isCancelled = true
        exportTask?.cancel()
        importTask?.cancel()
    }

    public func reset() {
        state = .idle
        logLines = []
        lastError = nil
    }

    // MARK: 导出

    /// 把一个已安装实例导出成 `.dshpack`。
    @discardableResult
    public func exportPack(
        instance: DSHInstalledVersion,
        name: String,
        version: String,
        description: String,
        author: String,
        runtime: DSHPackRuntimeMode,
        includePluginPayloads: Bool,
        to destination: URL
    ) async -> URL? {
        guard !state.isBusy else { return nil }
        isCancelled = false
        logLines = []
        lastError = nil
        state = .exporting(name: name, phase: .preparing, progress: 0)

        let work = Task { [weak self] () -> URL? in
            guard let self else { return nil }
            return await self.performExport(
                instance: instance,
                name: name,
                version: version,
                description: description,
                author: author,
                runtime: runtime,
                includePluginPayloads: includePluginPayloads,
                destination: destination
            )
        }
        exportTask = work
        let result = await work.value
        exportTask = nil
        return result
    }

    private func performExport(
        instance: DSHInstalledVersion,
        name: String,
        version: String,
        description: String,
        author: String,
        runtime: DSHPackRuntimeMode,
        includePluginPayloads: Bool,
        destination: URL
    ) async -> URL? {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("DSHPackExport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        do {
            try paths.ensureDirectories()
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            let isBundled = runtime == .bundled

            if isBundled {
                update(phase: .packingRuntime, progress: 0.05)
                let runtimeSource = paths.versionDirectory(instance.id)
                guard fileManager.fileExists(atPath: paths.cliScript(for: instance.id).path) else {
                    throw DSHPackError.exportFailed("实例的 DSH 运行时文件不完整")
                }
                let runtimeTarget = staging.appendingPathComponent(DSHPackFormat.runtimePath, isDirectory: true)
                try fileManager.createDirectory(
                    at: runtimeTarget.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                log("复制 DSH 本体（约 \(sizeText(instance.sizeBytes ?? 0))）…")
                try copyDirectory(from: runtimeSource, to: runtimeTarget)
                // 导入后会生成新的实例元数据
                try? fileManager.removeItem(at: runtimeTarget.appendingPathComponent("launcher-install.json"))
                update(phase: .packingRuntime, progress: 0.35)
            }

            update(phase: .packingPlugins, progress: isBundled ? 0.4 : 0.1)
            var packPlugins = profilePlugins(instanceID: instance.id)
            let localPayloads = readPluginPayloadIndex(instanceID: instance.id)
            if includePluginPayloads, !packPlugins.isEmpty {
                let payloadDirectory = staging.appendingPathComponent(DSHPackFormat.pluginsPath, isDirectory: true)
                try fileManager.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
                var updated: [DSHPackPlugin] = []
                for plugin in packPlugins {
                    try Task.checkCancellation()
                    if let filename = localPayloads[plugin.name] {
                        let source = pluginPayloadsDirectory(instanceID: instance.id).appendingPathComponent(filename)
                        if fileManager.fileExists(atPath: source.path) {
                            let target = payloadDirectory.appendingPathComponent(filename)
                            try? fileManager.removeItem(at: target)
                            try? fileManager.copyItem(at: source, to: target)
                            if fileManager.fileExists(atPath: target.path) {
                                updated.append(
                                    DSHPackPlugin(
                                        name: plugin.name,
                                        spec: plugin.spec,
                                        version: plugin.version,
                                        payload: "\(DSHPackFormat.pluginsPath)/\(filename)"
                                    )
                                )
                                continue
                            }
                        }
                    }
                    if let payload = await packPluginTarball(plugin, into: payloadDirectory) {
                        updated.append(
                            DSHPackPlugin(
                                name: plugin.name,
                                spec: plugin.spec,
                                version: plugin.version,
                                payload: "\(DSHPackFormat.pluginsPath)/\(payload.lastPathComponent)"
                            )
                        )
                    } else {
                        updated.append(plugin)
                    }
                }
                packPlugins = updated
            }
            update(phase: .packingPlugins, progress: isBundled ? 0.55 : 0.25)

            let manifest = DSHPackManifest(
                name: name,
                version: version,
                description: description,
                author: author,
                dshVersion: instance.dshVersion,
                runtime: runtime,
                plugins: packPlugins
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(
                to: staging.appendingPathComponent(DSHPackFormat.manifestName),
                options: .atomic
            )

            update(phase: .compressing, progress: isBundled ? 0.6 : 0.3)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // 先写临时文件，成功后再原子替换，避免压缩失败毁掉旧整合包
            let temporaryZip = destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
            defer { try? fileManager.removeItem(at: temporaryZip) }
            try await runTool(
                executable: "/usr/bin/zip",
                arguments: ["-r", "-q", "-y", "-1", temporaryZip.path, "."],
                workingDirectory: staging,
                progressBase: isBundled ? 0.6 : 0.3,
                progressSpan: 0.35
            )
            guard fileManager.fileExists(atPath: temporaryZip.path) else {
                throw DSHPackError.exportFailed("压缩后没有找到整合包文件")
            }
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryZip)
            } else {
                try fileManager.moveItem(at: temporaryZip, to: destination)
            }
            update(phase: .finishing, progress: 1)
            log("✓ 已导出整合包：\(destination.lastPathComponent)")
            state = .idle
            return destination
        } catch is CancellationError {
            lastError = .cancelled
            state = .failed(DSHPackError.cancelled.localizedDescription)
            return nil
        } catch {
            let message = (error as? DSHPackError)?.localizedDescription ?? error.localizedDescription
            lastError = error as? DSHPackError ?? .exportFailed(message)
            state = .failed(message)
            return nil
        }
    }

    // MARK: 导入

    /// 导入 `.dshpack` 为新的 DSH 实例（可自定义名字）。
    @discardableResult
    public func importPack(from archive: URL, customName: String? = nil) async -> DSHInstalledVersion? {
        guard !state.isBusy else { return nil }
        isCancelled = false
        logLines = []
        lastError = nil
        state = .importing(name: archive.lastPathComponent, phase: .reading, progress: 0)

        let work = Task { [weak self] () -> DSHInstalledVersion? in
            guard let self else { return nil }
            return await self.performImport(archive: archive, customName: customName)
        }
        importTask = work
        let result = await work.value
        importTask = nil
        return result
    }

    private func performImport(archive: URL, customName: String?) async -> DSHInstalledVersion? {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("DSHPackImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        let previousSelection = settings.dshSelectedInstanceID
        let existingIDs = Set(versions.installed.map(\.id))
        var createdInstanceIDs: [String] = []
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            log("解压整合包…")
            try validateArchiveEntries(archive)
            try await runTool(
                executable: "/usr/bin/unzip",
                arguments: ["-q", "-o", archive.path, "-d", staging.path],
                workingDirectory: nil,
                progressBase: 0,
                progressSpan: 0.2
            )
            try validateExtractedTree(staging)

            let manifestURL = staging.appendingPathComponent(DSHPackFormat.manifestName)
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                throw DSHPackError.missingManifest
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest: DSHPackManifest
            do {
                manifest = try decoder.decode(DSHPackManifest.self, from: Data(contentsOf: manifestURL))
            } catch {
                throw DSHPackError.invalidPackage("manifest.json 解析失败：\(error.localizedDescription)")
            }
            guard manifest.format == DSHPackFormat.identifier else {
                throw DSHPackError.invalidPackage("未知格式标识 \(manifest.format)")
            }
            guard manifest.formatVersion <= DSHPackFormat.formatVersion else {
                throw DSHPackError.unsupportedVersion(manifest.formatVersion)
            }
            guard DSHPaths.isSafeVersion(manifest.dshVersion) else {
                throw DSHPackError.invalidPackage("DSH 版本号不合法：\(manifest.dshVersion)")
            }

            let instanceName = DSHVersionStore.normalizedInstanceName(customName, fallback: manifest.name)
            update(phase: .reading, progress: 0.25)

            // 1) DSH 运行时
            let instanceID = UUID().uuidString.lowercased()
            let targetDirectory = paths.versionDirectory(instanceID)
            switch manifest.runtime {
            case .bundled:
                update(phase: .extractingRuntime, progress: 0.3)
                let runtimeSource = staging.appendingPathComponent(DSHPackFormat.runtimePath, isDirectory: true)
                guard fileManager.fileExists(atPath: runtimeSource.path) else {
                    throw DSHPackError.missingRuntime
                }
                try? fileManager.removeItem(at: targetDirectory)
                try fileManager.createDirectory(
                    at: paths.versionsDirectory,
                    withIntermediateDirectories: true
                )
                try copyDirectory(from: runtimeSource, to: targetDirectory)
                guard fileManager.fileExists(atPath: paths.cliScript(for: instanceID).path) else {
                    throw DSHPackError.invalidPackage("integrated runtime 缺少 @deepseek-ai/dsh 入口")
                }
            case .online:
                update(phase: .installingRuntime, progress: 0.3)
                await versions.install(manifest.dshVersion, name: instanceName)
                if case .failed(_, let message) = versions.installState {
                    throw DSHPackError.importFailed("从 npm 安装 DSH \(manifest.dshVersion) 失败：\(message)")
                }
                // 只接受本次调用新建的实例，不能误命中已有的同名同版本实例
                let newInstances = versions.installed.filter { !existingIDs.contains($0.id) }
                guard newInstances.count == 1,
                      let installed = newInstances.first,
                      installed.dshVersion == manifest.dshVersion,
                      installed.name == instanceName else {
                    for extra in newInstances {
                        removeInstanceFiles(extra.id)
                    }
                    throw DSHPackError.importFailed("从 npm 安装 DSH \(manifest.dshVersion) 失败")
                }
                createdInstanceIDs.append(installed.id)
                log("已安装 DSH \(manifest.dshVersion)（在线模式）")
                update(phase: .installingPlugins, progress: 0.55)
                return try await finishImport(
                    manifest: manifest,
                    instance: installed,
                    instanceName: instanceName,
                    staging: staging
                )
            }

            createdInstanceIDs.append(instanceID)
            let size = paths.directorySize(targetDirectory)
            update(phase: .installingPlugins, progress: 0.55)
            return try await finishImport(
                manifest: manifest,
                instanceID: instanceID,
                instanceName: instanceName,
                size: size,
                staging: staging
            )
        } catch is CancellationError {
            rollbackImport(createdInstanceIDs, previousSelection: previousSelection)
            lastError = .cancelled
            state = .failed(DSHPackError.cancelled.localizedDescription)
            return nil
        } catch {
            rollbackImport(createdInstanceIDs, previousSelection: previousSelection)
            let message = (error as? DSHPackError)?.localizedDescription ?? error.localizedDescription
            lastError = error as? DSHPackError ?? .importFailed(message)
            state = .failed(message)
            return nil
        }
    }

    /// 导入失败 / 取消时回滚半成品实例，避免留下“脏实例”。
    private func rollbackImport(_ instanceIDs: [String], previousSelection: String) {
        guard !instanceIDs.isEmpty else { return }
        let fileManager = FileManager.default
        for id in instanceIDs {
            try? fileManager.removeItem(at: paths.versionDirectory(id))
            try? fileManager.removeItem(at: paths.homeDirectory(for: id))
            try? fileManager.removeItem(at: paths.logFile(for: id))
        }
        versions.refreshInstalled()
        if !previousSelection.isEmpty,
           versions.installed.contains(where: { $0.id == previousSelection }) {
            settings.dshSelectedInstanceID = previousSelection
        }
        log("已回滚未完成的导入（\(instanceIDs.count) 个实例）")
    }

    private func removeInstanceFiles(_ instanceID: String) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: paths.versionDirectory(instanceID))
        try? fileManager.removeItem(at: paths.homeDirectory(for: instanceID))
        try? fileManager.removeItem(at: paths.logFile(for: instanceID))
    }

    private func finishImport(
        manifest: DSHPackManifest,
        instanceID: String,
        instanceName: String,
        size: Int64,
        staging: URL
    ) async throws -> DSHInstalledVersion {
        versions.adoptImportedInstance(
            instanceID: instanceID,
            name: instanceName,
            dshVersion: manifest.dshVersion,
            size: size,
            packName: manifest.name,
            packVersion: manifest.version
        )
        guard let instance = versions.installed.first(where: { $0.id == instanceID }) else {
            throw DSHPackError.importFailed("创建实例失败")
        }
        return try await installPackPlugins(manifest: manifest, instance: instance, staging: staging)
    }

    private func finishImport(
        manifest: DSHPackManifest,
        instance: DSHInstalledVersion,
        instanceName: String,
        staging: URL
    ) async throws -> DSHInstalledVersion {
        versions.adoptImportedInstance(
            instanceID: instance.id,
            name: instanceName,
            dshVersion: instance.dshVersion,
            size: instance.sizeBytes ?? 0,
            packName: manifest.name,
            packVersion: manifest.version
        )
        guard let adopted = versions.installed.first(where: { $0.id == instance.id }) else {
            throw DSHPackError.importFailed("创建实例失败")
        }
        return try await installPackPlugins(manifest: manifest, instance: adopted, staging: staging)
    }

    private func installPackPlugins(
        manifest: DSHPackManifest,
        instance: DSHInstalledVersion,
        staging: URL
    ) async throws -> DSHInstalledVersion {
        log("安装整合包插件（\(manifest.plugins.count) 个）…")
        let fileManager = FileManager.default
        var failures: [String] = []
        for (index, plugin) in manifest.plugins.enumerated() {
            try Task.checkCancellation()
            let progress = 0.55 + 0.4 * (Double(index) / Double(max(1, manifest.plugins.count)))
            update(phase: .installingPlugins, progress: progress)
            var spec = plugin.spec
            if let payload = plugin.payload {
                guard !payload.contains(".."), !payload.hasPrefix("/") else {
                    throw DSHPackError.unsafePath(payload)
                }
                let payloadURL = staging.appendingPathComponent(payload)
                if fileManager.fileExists(atPath: payloadURL.path) {
                    // 持久化到实例 home，避免 staging 删除后依赖指向不存在的临时文件
                    let payloads = pluginPayloadsDirectory(instanceID: instance.id)
                    try? fileManager.createDirectory(at: payloads, withIntermediateDirectories: true)
                    let filename = "\(safePayloadStem(plugin.name))-\(payloadURL.lastPathComponent)"
                    let stableURL = payloads.appendingPathComponent(filename)
                    try? fileManager.removeItem(at: stableURL)
                    try? fileManager.copyItem(at: payloadURL, to: stableURL)
                    if fileManager.fileExists(atPath: stableURL.path) {
                        recordPluginPayload(instanceID: instance.id, name: plugin.name, filename: filename)
                        spec = "file:\(stableURL.path)"
                    } else {
                        spec = "file:\(payloadURL.path)"
                    }
                } else {
                    log("⚠︎ 缺少离线载荷 \(payload)，改为在线安装 \(plugin.spec)")
                }
            }
            log("安装插件 \(plugin.name) …")
            let ok = await plugins.installRawSpec(spec, into: instance)
            if !ok {
                failures.append("\(plugin.name)：\(plugins.lastError?.localizedDescription ?? "安装失败")")
            }
        }
        if !failures.isEmpty {
            throw DSHPackError.importFailed(failures.joined(separator: "\n"))
        }
        update(phase: .finishing, progress: 1)
        settings.dshSelectedInstanceID = instance.id
        log("✓ 整合包导入完成：\(instance.name)")
        state = .idle
        return instance
    }

    // MARK: 插件清单

    /// 从实例的 web profile 读取已安装插件，解析成整合包清单。
    private func profilePlugins(instanceID: String) -> [DSHPackPlugin] {
        let profile = paths.profileDirectory(for: instanceID)
        let manifestURL = profile.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        struct Manifest: Decodable { let dependencies: [String: String]? }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              let dependencies = manifest.dependencies else { return [] }
        let payloadIndex = readPluginPayloadIndex(instanceID: instanceID)
        var result: [DSHPackPlugin] = []
        for (name, value) in dependencies.sorted(by: { $0.key < $1.key }) {
            let installedVersion = readInstalledPackageVersion(profile: profile, name: name)
            if value.hasPrefix("file:") || value.hasPrefix("link:") {
                // 本地 tarball 插件：manifest 记录安装版本；离线载荷由 payload index 在导出时找回
                let spec = installedVersion.map { "\(name)@\($0)" } ?? name
                result.append(DSHPackPlugin(name: name, spec: spec, version: installedVersion))
                _ = payloadIndex
                continue
            }
            let spec: String
            if value.hasPrefix("github:") || value.hasPrefix("git+") || value.hasPrefix("git:") || value.hasPrefix("https://") {
                spec = value
            } else if let installedVersion {
                spec = "\(name)@\(installedVersion)"
            } else if value.first?.isNumber == true || value.hasPrefix("^") || value.hasPrefix("~") {
                spec = "\(name)@\(value.trimmingCharacters(in: CharacterSet(charactersIn: "^~")))"
            } else {
                spec = "\(name)@\(value)"
            }
            result.append(DSHPackPlugin(name: name, spec: spec, version: installedVersion))
        }
        return result
    }

    private func readInstalledPackageVersion(profile: URL, name: String) -> String? {
        let packageURL = profile.appendingPathComponent("node_modules/\(name)/package.json")
        guard let data = try? Data(contentsOf: packageURL) else { return nil }
        struct Package: Decodable { let version: String? }
        return (try? JSONDecoder().decode(Package.self, from: data))?.version
    }

    /// 用 `npm pack` 下载插件 tarball（仅 npm 规格）。
    private func packPluginTarball(_ plugin: DSHPackPlugin, into directory: URL) async -> URL? {
        guard isNpmSpec(plugin.spec) else { return nil }
        guard let node = DSHExecutables.node(), let npmCLI = DSHExecutables.npmCLI(node: node) else {
            return nil
        }
        do {
            let result = try await DSHCommandRunner.run(
                executable: node,
                arguments: [npmCLI.path, "pack", plugin.spec, "--pack-destination", directory.path, "--json"],
                environment: DSHExecutables.augmentedEnvironment(node: node)
            )
            guard result.exitCode == 0 else { return nil }
            struct PackEntry: Decodable { let filename: String? }
            let jsonLine = result.output
                .split(separator: "\n")
                .last(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") })
            if let jsonLine,
               let entries = try? JSONDecoder().decode([PackEntry].self, from: Data(jsonLine.utf8)),
               let filename = entries.first?.filename {
                let url = directory.appendingPathComponent(filename)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
            let candidates = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "tgz" }
            return candidates?.last
        } catch {
            return nil
        }
    }

    private func isNpmSpec(_ spec: String) -> Bool {
        let lower = spec.lowercased()
        let prefixes = ["file:", "link:", "github:", "git:", "git+", "http://", "https://"]
        return !prefixes.contains { lower.hasPrefix($0) }
    }

    // MARK: 文件 / 命令

    private func copyDirectory(from source: URL, to target: URL) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: target)
        // APFS 上用 clonefile 快速复制，失败时回退普通复制
        let clone = Process()
        clone.executableURL = URL(fileURLWithPath: "/bin/cp")
        clone.arguments = ["-cR", source.path, target.path]
        clone.standardOutput = FileHandle.nullDevice
        clone.standardError = FileHandle.nullDevice
        do {
            try clone.run()
            clone.waitUntilExit()
            if clone.terminationStatus == 0 { return }
        } catch {}
        try fileManager.copyItem(at: source, to: target)
    }

    private func validateArchiveEntries(_ archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", archive.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw DSHPackError.invalidPackage("无法读取 zip：\(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DSHPackError.invalidPackage("不是有效的 zip 文件")
        }
        let entries = String(decoding: data, as: UTF8.self).split(separator: "\n")
        if entries.count > 200_000 {
            throw DSHPackError.invalidPackage("条目数量过多（\(entries.count)）")
        }
        for entry in entries {
            let path = String(entry)
            if path.hasPrefix("/") || path.contains("..") {
                throw DSHPackError.unsafePath(path)
            }
        }
        // 限制解压体积，避免 zip bomb
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        listing.arguments = ["-l", archive.path]
        let listingPipe = Pipe()
        listing.standardOutput = listingPipe
        listing.standardError = FileHandle.nullDevice
        try? listing.run()
        let listingData = listingPipe.fileHandleForReading.readDataToEndOfFile()
        listing.waitUntilExit()
        let listingLines = String(decoding: listingData, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let last = listingLines.last {
            let fields = last.split(separator: " ")
            if fields.count >= 2, let totalBytes = Int64(fields[0]), totalBytes > 8_000_000_000 {
                throw DSHPackError.invalidPackage("解压体积过大（\(totalBytes) bytes）")
            }
        }
    }

    /// 解压后校验软链接：只允许指向载荷内部，拒绝绝对路径 / 逃逸链接。
    private func validateExtractedTree(_ root: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [],
            errorHandler: nil
        ) else { return }
        let rootPath = root.standardizedFileURL.path
        while let item = enumerator.nextObject() as? URL {
            let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values?.isSymbolicLink == true else { continue }
            guard let target = try? fileManager.destinationOfSymbolicLink(atPath: item.path) else {
                throw DSHPackError.unsafePath(item.lastPathComponent)
            }
            if target.hasPrefix("/") {
                throw DSHPackError.unsafePath("符号链接指向绝对路径：\(target)")
            }
            let resolved = item.deletingLastPathComponent().appendingPathComponent(target).standardizedFileURL.path
            guard resolved == rootPath || resolved.hasPrefix(rootPath + "/") else {
                throw DSHPackError.unsafePath("符号链接逃逸：\(target)")
            }
        }
    }

    // MARK: 插件离线载荷索引

    private func pluginPayloadsDirectory(instanceID: String) -> URL {
        paths.homeDirectory(for: instanceID).appendingPathComponent("plugin-payloads", isDirectory: true)
    }

    private func payloadIndexURL(instanceID: String) -> URL {
        pluginPayloadsDirectory(instanceID: instanceID).appendingPathComponent("index.json")
    }

    private func readPluginPayloadIndex(instanceID: String) -> [String: String] {
        let url = payloadIndexURL(instanceID: instanceID)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return decoded
    }

    private func recordPluginPayload(instanceID: String, name: String, filename: String) {
        var index = readPluginPayloadIndex(instanceID: instanceID)
        index[name] = filename
        let url = payloadIndexURL(instanceID: instanceID)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func safePayloadStem(_ name: String) -> String {
        let replaced = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "@", with: "")
        return replaced.isEmpty ? "plugin" : replaced
    }

    private func runTool(
        executable: String,
        arguments: [String],
        workingDirectory: URL?,
        progressBase: Double,
        progressSpan: Double
    ) async throws {
        let result = try await DSHCommandRunner.run(
            executable: URL(fileURLWithPath: executable),
            arguments: arguments,
            environment: DSHExecutables.augmentedEnvironment(),
            workingDirectory: workingDirectory
        ) { [weak self] line in
            Task { @MainActor in
                self?.log(line)
            }
        }
        guard result.exitCode == 0 else {
            let tail = result.output.split(separator: "\n").suffix(3).joined(separator: "\n")
            throw DSHPackError.importFailed(tail.isEmpty ? "命令退出码 \(result.exitCode)" : tail)
        }
        if case .exporting(let name, let phase, _) = state {
            update(phase: phase, progress: min(0.99, progressBase + progressSpan))
            _ = name
        } else if case .importing(let name, let phase, _) = state {
            update(phase: phase, progress: min(0.99, progressBase + progressSpan))
            _ = name
        }
    }

    private func update(phase: DSHPackPhase, progress: Double) {
        switch state {
        case .exporting(let name, _, _):
            state = .exporting(name: name, phase: phase, progress: progress)
        case .importing(let name, _, _):
            state = .importing(name: name, phase: phase, progress: progress)
        default:
            break
        }
    }

    private func log(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logLines.append(trimmed)
        if logLines.count > 400 { logLines.removeFirst(logLines.count - 400) }
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
