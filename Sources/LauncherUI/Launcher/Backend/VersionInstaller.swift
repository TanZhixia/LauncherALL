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

    public init(
        installation: MinecraftInstallation,
        downloader: FileDownloader = FileDownloader(),
        manifestService: MojangManifestService? = nil,
        session: URLSession = .shared
    ) {
        self.installation = installation
        self.downloader = downloader
        self.manifestService = manifestService ?? MojangManifestService(installation: installation, session: session)
        self.session = session
    }

    /// 安装指定版本；`includeAssets` 为 true 时会下载全部资源对象（文件很多，耗时长）。
    public func install(
        versionID: String,
        includeAssets: Bool = true,
        progress: @escaping @Sendable (InstallProgress) -> Void
    ) async throws -> InstalledVersion {
        let fileManager = FileManager.default
        let versionDirectory = installation.versionDirectory(versionID)
        try fileManager.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: installation.librariesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: installation.nativesDirectory(versionID), withIntermediateDirectories: true)

        // 1. 版本 JSON
        progress(InstallProgress(phase: "获取版本信息", completed: 0, total: 1))
        let fetched = try await manifestService.fetchVersionDetailData(versionID)
        try fetched.data.write(to: installation.versionJSONURL(versionID), options: .atomic)
        // 处理 inheritsFrom：合并父版本的客户端 / 依赖 / 资源
        let resolved = try await VersionResolver.resolveAsync(versionID: versionID, installation: installation, manifestService: manifestService)
        progress(InstallProgress(phase: "获取版本信息", completed: 1, total: 1))

        // 2. 客户端 jar（加载器版本会复用父版本客户端）
        guard let client = resolved.clientDownload else {
            throw InstallError.missingClientURL(versionID)
        }
        progress(InstallProgress(phase: "下载客户端", completed: 0, total: 1))
        try await downloader.download(
            FileDownloadTask(
                url: URL(string: client.url)!,
                destination: installation.versionJarURL(versionID),
                sha1: client.sha1,
                expectedSize: client.size
            )
        ) { _ in }
        progress(InstallProgress(phase: "下载客户端", completed: 1, total: 1))

        // 3. 依赖库（含原生库）
        let libraries = resolved.libraries.filter { RuleEvaluator.isAllowed($0.rules) }
        var tasks: [FileDownloadTask] = []
        var nativeTasks: [(task: FileDownloadTask, name: String)] = []
        for library in libraries {
            if let artifact = library.downloads?.artifact, let path = artifact.path, let url = URL(string: artifact.url) {
                tasks.append(
                    FileDownloadTask(
                        url: url,
                        destination: installation.librariesDirectory.appendingPathComponent(path),
                        sha1: artifact.sha1,
                        expectedSize: artifact.size
                    )
                )
            } else if let mavenPath = library.mavenPath, let url = library.downloadURL() {
                // Fabric / Forge 等版本 JSON 只有 name + url，没有 downloads
                tasks.append(
                    FileDownloadTask(
                        url: url,
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
                        url: URL(string: classifier.url)!,
                        destination: installation.librariesDirectory.appendingPathComponent(path),
                        sha1: classifier.sha1,
                        expectedSize: classifier.size
                    ),
                    library.name
                ))
            }
        }

        try await runConcurrently(tasks, limit: 6) { completed in
            progress(InstallProgress(phase: "下载依赖库", completed: completed, total: tasks.count))
        } work: { task in
            try await self.downloader.download(task) { _ in }
        }

        // 原生库解压
        try fileManager.createDirectory(at: installation.nativesDirectory(versionID), withIntermediateDirectories: true)
        var extracted = 0
        for (task, name) in nativeTasks {
            if fileManager.fileExists(atPath: task.destination.path) {
                try extractNatives(jar: task.destination, to: installation.nativesDirectory(versionID))
            } else {
                do {
                    try await downloader.download(task) { _ in }
                    try extractNatives(jar: task.destination, to: installation.nativesDirectory(versionID))
                } catch {
                    throw InstallError.extractionFailed(name)
                }
            }
            extracted += 1
            progress(InstallProgress(phase: "解压原生库", completed: extracted, total: nativeTasks.count))
        }

        // 4. 资源索引
        if let assetIndex = resolved.assetIndex {
            let indexDirectory = installation.assetsDirectory.appendingPathComponent("indexes", isDirectory: true)
            let indexURL = indexDirectory.appendingPathComponent("\(assetIndex.id).json")
            try await downloader.download(
                FileDownloadTask(
                    url: URL(string: assetIndex.url)!,
                    destination: indexURL,
                    sha1: assetIndex.sha1,
                    expectedSize: assetIndex.size
                )
            ) { _ in }

            if includeAssets {
                let objects = try decodeAssetObjects(indexURL)
                let entries = Array(objects)
                let objectsRoot = installation.assetsDirectory.appendingPathComponent("objects", isDirectory: true)
                var completed = 0
                let chunkSize = 8
                var index = 0
                while index < entries.count {
                    let chunk = Array(entries[index..<min(index + chunkSize, entries.count)])
                    index += chunkSize
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for (_, object) in chunk {
                            let prefix = String(object.hash.prefix(2))
                            let destination = objectsRoot
                                .appendingPathComponent(prefix, isDirectory: true)
                                .appendingPathComponent(object.hash)
                            if fileManager.fileExists(atPath: destination.path) {
                                completed += 1
                                continue
                            }
                            group.addTask {
                                let url = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(object.hash)")!
                                try await self.downloader.download(
                                    FileDownloadTask(url: url, destination: destination, sha1: object.hash, expectedSize: object.size)
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

        // 5. 日志配置
        if let logging = resolved.logging?.client {
            let destination = installation.cacheDirectory
                .appendingPathComponent("logging", isDirectory: true)
                .appendingPathComponent(logging.file.id)
            try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await downloader.download(
                FileDownloadTask(
                    url: URL(string: logging.file.url)!,
                    destination: destination,
                    sha1: logging.file.sha1,
                    expectedSize: logging.file.size
                )
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
        progress: @escaping @Sendable (Int) -> Void,
        work: @escaping @Sendable (FileDownloadTask) async throws -> Void
    ) async throws {
        guard !tasks.isEmpty else { return }
        var completed = 0
        var index = 0
        while index < tasks.count {
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
    }
}
