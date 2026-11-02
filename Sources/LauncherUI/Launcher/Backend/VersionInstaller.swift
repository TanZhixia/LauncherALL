import Foundation

/// 安装进度（阶段 + 已完成 / 总数）。
public struct InstallProgress: Sendable, Equatable {
    public let phase: String
    public let completed: Int
    public let total: Int

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    public init(phase: String, completed: Int, total: Int) {
        self.phase = phase
        self.completed = completed
        self.total = total
    }
}

// MARK: - 安装选项

/// 真实安装选项：控制是否下载全部资源、是否校验已有文件。
public struct InstallOptions: Sendable, Equatable {
    /// 是否下载全部资源对象（assets/objects）。关闭时只装核心文件，可稍后补全。
    public var includeAssets: Bool
    /// 是否重新校验已存在的文件（SHA1）。关闭时信任已有文件，安装更快。
    public var verifyExisting: Bool

    public init(includeAssets: Bool = true, verifyExisting: Bool = false) {
        self.includeAssets = includeAssets
        self.verifyExisting = verifyExisting
    }

    public static let `default` = InstallOptions()

    /// 选项摘要（队列 / 日志展示）。
    public var summary: String {
        var parts: [String] = []
        parts.append(includeAssets ? "含资源文件" : "仅核心文件")
        parts.append(verifyExisting ? "校验已有文件" : "跳过已有文件校验")
        return parts.joined(separator: " · ")
    }
}

// MARK: - 安装校验

/// 安装完整性校验结果。
public struct InstallVerification: Sendable, Equatable {
    public let checked: Int
    public let missing: Int
    public let corrupt: Int

    public var isHealthy: Bool { missing == 0 && corrupt == 0 }

    public var summary: String {
        if isHealthy { return "已校验 \(checked) 个文件，全部正常" }
        return "已校验 \(checked) 个文件：缺失 \(missing) 个，损坏 \(corrupt) 个"
    }

    public init(checked: Int, missing: Int, corrupt: Int) {
        self.checked = checked
        self.missing = missing
        self.corrupt = corrupt
    }
}

public enum InstallError: LocalizedError {
    case missingVersionJSON(String)
    case missingClientURL(String)
    case extractionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingVersionJSON(let id): return "缺少版本 JSON：\(id)"
        case .missingClientURL(let id): return "版本 \(id) 没有客户端下载地址"
        case .extractionFailed(let name): return "解压失败：\(name)"
        }
    }
}

/// 真实安装：下载版本 JSON / 客户端 jar / 依赖库 / 原生库 / 资源索引（可选资源对象）。
public final class VersionInstaller {
    private let installation: MinecraftInstallation
    private let downloader: FileDownloader
    private let manifestService: MojangManifestService
    private let session: URLSession
    private let source: DownloadSource

    public init(
        installation: MinecraftInstallation,
        downloader: FileDownloader = FileDownloader(),
        manifestService: MojangManifestService? = nil,
        session: URLSession = .shared,
        source: DownloadSource = .active
    ) {
        self.installation = installation
        self.downloader = downloader
        self.manifestService = manifestService ?? MojangManifestService(installation: installation, session: session, source: source)
        self.session = session
        self.source = source
    }

    /// 兼容旧调用：只指定是否安装资源文件。
    @discardableResult
    public func install(
        versionID: String,
        includeAssets: Bool,
        progress: @escaping @Sendable (InstallProgress) -> Void
    ) async throws -> InstalledVersion {
        try await install(
            versionID: versionID,
            options: InstallOptions(includeAssets: includeAssets),
            progress: progress
        )
    }

    /// 安装指定版本。
    public func install(
        versionID: String,
        options: InstallOptions = .default,
        progress: @escaping @Sendable (InstallProgress) -> Void
    ) async throws -> InstalledVersion {
        let fileManager = FileManager.default
        try Task.checkCancellation()
        let versionDirectory = installation.versionDirectory(versionID)
        try fileManager.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: installation.librariesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: installation.nativesDirectory(versionID), withIntermediateDirectories: true)

        // 1. 版本 JSON
        progress(InstallProgress(phase: "获取版本信息", completed: 0, total: 1))
        let fetched = try await manifestService.fetchVersionDetailData(versionID)
        try fetched.data.write(to: installation.versionJSONURL(versionID), options: .atomic)
        // 处理 inheritsFrom：合并父版本的客户端 / 依赖 / 资源
        let resolved = try await VersionResolver.resolveAsync(
            versionID: versionID,
            installation: installation,
            manifestService: manifestService
        )
        progress(InstallProgress(phase: "获取版本信息", completed: 1, total: 1))
        try Task.checkCancellation()

        // 2. 客户端 jar（加载器版本会复用父版本客户端）
        guard let client = resolved.clientDownload else {
            throw InstallError.missingClientURL(versionID)
        }
        progress(InstallProgress(phase: "下载客户端", completed: 0, total: 1))
        try await downloader.download(
            FileDownloadTask(
                url: source.rewrite(URL(string: client.url)!),
                destination: installation.versionJarURL(versionID),
                sha1: client.sha1,
                expectedSize: client.size
            ),
            verifyExisting: options.verifyExisting
        ) { _ in }
        progress(InstallProgress(phase: "下载客户端", completed: 1, total: 1))
        try Task.checkCancellation()

        // 3. 依赖库（含原生库）
        let libraries = resolved.libraries.filter { RuleEvaluator.isAllowed($0.rules) }
        var tasks: [FileDownloadTask] = []
        var nativeTasks: [(task: FileDownloadTask, name: String)] = []
        for library in libraries {
            if let artifact = library.downloads?.artifact, let path = artifact.path, let url = URL(string: artifact.url) {
                tasks.append(
                    FileDownloadTask(
                        url: source.rewrite(url),
                        destination: installation.librariesDirectory.appendingPathComponent(path),
                        sha1: artifact.sha1,
                        expectedSize: artifact.size
                    )
                )
            } else if let mavenPath = library.mavenPath, let url = library.downloadURL() {
                // Fabric / Forge 等版本 JSON 只有 name + url，没有 downloads
                tasks.append(
                    FileDownloadTask(
                        url: source.rewrite(url),
                        destination: installation.librariesDirectory.appendingPathComponent(mavenPath)
                    )
                )
            }
            if let natives = library.natives,
               let classifierKey = natives[RuleEvaluator.currentOSName ?? "osx"],
               let classifier = library.downloads?.classifiers?[classifierKey],
               let path = classifier.path {
                nativeTasks.append((
                    FileDownloadTask(
                        url: source.rewrite(URL(string: classifier.url)!),
                        destination: installation.librariesDirectory.appendingPathComponent(path),
                        sha1: classifier.sha1,
                        expectedSize: classifier.size
                    ),
                    library.name
                ))
            }
        }

        let libraryTaskCount = tasks.count
        try await runConcurrently(tasks, limit: 6, verifyExisting: options.verifyExisting) { completed in
            progress(InstallProgress(phase: "下载依赖库", completed: completed, total: libraryTaskCount))
        } work: { task in
            try await self.downloader.download(task, verifyExisting: options.verifyExisting) { _ in }
        }
        try Task.checkCancellation()

        // 原生库解压
        try fileManager.createDirectory(at: installation.nativesDirectory(versionID), withIntermediateDirectories: true)
        var extracted = 0
        for (task, name) in nativeTasks {
            if fileManager.fileExists(atPath: task.destination.path) {
                try extractNatives(jar: task.destination, to: installation.nativesDirectory(versionID))
            } else {
                do {
                    try await downloader.download(task, verifyExisting: options.verifyExisting) { _ in }
                    try extractNatives(jar: task.destination, to: installation.nativesDirectory(versionID))
                } catch {
                    throw InstallError.extractionFailed(name)
                }
            }
            extracted += 1
            progress(InstallProgress(phase: "解压原生库", completed: extracted, total: nativeTasks.count))
        }
        try Task.checkCancellation()

        // 4. 资源索引
        if let assetIndex = resolved.assetIndex {
            let indexDirectory = installation.assetsDirectory.appendingPathComponent("indexes", isDirectory: true)
            let indexURL = indexDirectory.appendingPathComponent("\(assetIndex.id).json")
            try await downloader.download(
                FileDownloadTask(
                    url: source.rewrite(URL(string: assetIndex.url)!),
                    destination: indexURL,
                    sha1: assetIndex.sha1,
                    expectedSize: assetIndex.size
                ),
                verifyExisting: options.verifyExisting
            ) { _ in }

            if options.includeAssets {
                let objects = try decodeAssetObjects(indexURL)
                let entries = Array(objects)
                let objectsRoot = installation.assetsDirectory.appendingPathComponent("objects", isDirectory: true)
                var completed = 0
                let chunkSize = 8
                var index = 0
                while index < entries.count {
                    try Task.checkCancellation()
                    let chunk = Array(entries[index..<min(index + chunkSize, entries.count)])
                    index += chunkSize
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for (_, object) in chunk {
                            let prefix = String(object.hash.prefix(2))
                            let destination = objectsRoot
                                .appendingPathComponent(prefix, isDirectory: true)
                                .appendingPathComponent(object.hash)
                            if fileManager.fileExists(atPath: destination.path) {
                                // 已存在的文件不计入 completed：本 chunk 结束时统一按 chunk.count 计数
                                continue
                            }
                            group.addTask {
                                let url = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(object.hash)")!
                                try await self.downloader.download(
                                    FileDownloadTask(
                                        url: self.source.rewrite(url),
                                        destination: destination,
                                        sha1: object.hash,
                                        expectedSize: object.size
                                    ),
                                    verifyExisting: options.verifyExisting
                                ) { _ in }
                            }
                        }
                        try await group.waitForAll()
                    }
                    completed += chunk.count
                    progress(InstallProgress(phase: "下载资源文件", completed: completed, total: entries.count))
                }
            }
        }
        try Task.checkCancellation()

        // 5. 日志配置
        if let logging = resolved.logging?.client {
            let destination = installation.cacheDirectory
                .appendingPathComponent("logging", isDirectory: true)
                .appendingPathComponent(logging.file.id)
            try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await downloader.download(
                FileDownloadTask(
                    url: source.rewrite(URL(string: logging.file.url)!),
                    destination: destination,
                    sha1: logging.file.sha1,
                    expectedSize: logging.file.size
                ),
                verifyExisting: options.verifyExisting
            ) { _ in }
        }

        let jarURL = installation.versionJarURL(versionID)
        return InstalledVersion(
            id: versionID,
            jsonURL: installation.versionJSONURL(versionID),
            jarURL: fileManager.fileExists(atPath: jarURL.path) ? jarURL : nil,
            versionType: resolved.type,
            lastModified: Date()
        )
    }

    // MARK: - 完整性校验

    /// 校验客户端 jar、依赖库、资源索引与日志配置是否齐全且 SHA1 正确。
    public func verify(versionID: String) async throws -> InstallVerification {
        let fileManager = FileManager.default
        let resolved = try await VersionResolver.resolveAsync(
            versionID: versionID,
            installation: installation,
            manifestService: manifestService
        )

        var checks: [(url: URL, sha1: String?)] = []
        if let client = resolved.clientDownload {
            checks.append((installation.versionJarURL(versionID), client.sha1))
        }
        for library in resolved.libraries where RuleEvaluator.isAllowed(library.rules) {
            guard let artifact = library.downloads?.artifact, let path = artifact.path else { continue }
            checks.append((installation.librariesDirectory.appendingPathComponent(path), artifact.sha1))
        }
        if let assetIndex = resolved.assetIndex {
            let indexURL = installation.assetsDirectory
                .appendingPathComponent("indexes", isDirectory: true)
                .appendingPathComponent("\(assetIndex.id).json")
            checks.append((indexURL, assetIndex.sha1))
        }
        if let logging = resolved.logging?.client {
            let url = installation.cacheDirectory
                .appendingPathComponent("logging", isDirectory: true)
                .appendingPathComponent(logging.file.id)
            checks.append((url, logging.file.sha1))
        }

        var missing = 0
        var corrupt = 0
        for check in checks {
            try Task.checkCancellation()
            guard fileManager.fileExists(atPath: check.url.path) else {
                missing += 1
                continue
            }
            if let sha1 = check.sha1, let data = try? Data(contentsOf: check.url, options: .mappedIfSafe),
               FileDownloader.sha1Hex(data) != sha1 {
                corrupt += 1
            }
        }
        return InstallVerification(checked: checks.count, missing: missing, corrupt: corrupt)
    }

    // MARK: - 资源索引

    private struct AssetIndexFile: Decodable {
        struct Object: Decodable {
            let hash: String
            let size: Int64
        }
        let objects: [String: Object]
    }

    private func decodeAssetObjects(_ url: URL) throws -> [(String, AssetIndexFile.Object)] {
        let data = try Data(contentsOf: url)
        let index = try JSONDecoder().decode(AssetIndexFile.self, from: data)
        return Array(index.objects).map { ($0.key, $0.value) }
    }

    // MARK: - 原生库解压

    private func extractNatives(jar: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-oq", jar.path, "-d", directory.path, "-x", "META-INF/*"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            // 有的原生 jar 里只有 META-INF，视为无内容
            return
        }
    }

    // MARK: - 并发执行

    private func runConcurrently(
        _ tasks: [FileDownloadTask],
        limit: Int,
        verifyExisting: Bool,
        progress: @escaping @Sendable (Int) -> Void,
        work: @escaping @Sendable (FileDownloadTask) async throws -> Void
    ) async throws {
        guard !tasks.isEmpty else { return }
        var completed = 0
        var index = 0
        while index < tasks.count {
            try Task.checkCancellation()
            let chunk = Array(tasks[index..<min(index + limit, tasks.count)])
            index += limit
            try await withThrowingTaskGroup(of: Void.self) { group in
                for task in chunk {
                    group.addTask { try await work(task) }
                }
                try await group.waitForAll()
            }
            completed += chunk.count
            progress(completed)
        }
        _ = verifyExisting
    }
}
