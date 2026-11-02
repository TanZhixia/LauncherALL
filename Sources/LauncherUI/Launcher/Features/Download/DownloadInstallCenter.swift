import Foundation
import Observation

// MARK: - 安装任务

/// 一次社区资源安装任务（模组 / 资源包 / 光影 / 数据包 / 世界 / 整合包）。
/// 进度全部来自真实下载与解压，不用定时器伪造。
public struct DownloadInstallJob: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case running
        case finished
        case cancelled
        case failed(String)

        /// 是否仍在进行。
        public var isActive: Bool { self == .running }

        /// 状态标题。
        public var title: String {
            switch self {
            case .running: return "进行中"
            case .finished: return "已完成"
            case .cancelled: return "已取消"
            case .failed: return "失败"
            }
        }

        /// 成功类状态（决定提示色调）。
        public var isSuccess: Bool {
            if case .finished = self { return true }
            return false
        }
    }

    public let id: UUID
    /// 对应的 Modrinth 项目 id（本地导入为 nil）。
    public let projectID: String?
    /// 任务标题（项目名 + 版本）。
    public var title: String
    /// 副标题（资源类型 · 目标实例）。
    public var subtitle: String
    /// 当前阶段说明（来自真实步骤）。
    public var phase: String
    /// 当前阶段进度；nil 表示该阶段无法估算（如安装基础版本）。
    public var fraction: Double?
    /// 附加说明（文件数 / 大小 / 步骤）。
    public var detail: String
    public var state: State
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        projectID: String? = nil,
        title: String,
        subtitle: String,
        phase: String,
        fraction: Double? = nil,
        detail: String = "",
        state: State = .running,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.subtitle = subtitle
        self.phase = phase
        self.fraction = fraction
        self.detail = detail
        self.state = state
        self.createdAt = createdAt
    }
}

// MARK: - 安装中心

/// 社区资源安装中心：真实下载文件、解析 `.mrpack`、写入加载器版本、解压 overrides。
/// 页面只负责触发与展示，安装逻辑都在这里，便于测试与复用。
@MainActor
@Observable
public final class DownloadInstallCenter {
    /// 全部任务（最新在前）。
    public private(set) var jobs: [DownloadInstallJob] = []
    /// 轻提示回调：由页面注入 `router.showToast`。
    public var notify: ((String, LauncherBannerTone) -> Void)?

    private let client: ModrinthClient
    private let downloader: FileDownloader
    /// 进行中的任务句柄（支持真实取消）。
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// 整合包任务正在安装的基础版本（取消任务时一并取消，避免等待循环空转）。
    private var baseVersions: [UUID: String] = [:]
    /// 整合包任务对应的引擎（取消时用）。
    private weak var modpackEngine: LauncherEngine?
    /// 任务最多保留条数。
    private let jobLimit = 8

    public init(client: ModrinthClient = ModrinthClient(), downloader: FileDownloader = FileDownloader()) {
        self.client = client
        self.downloader = downloader
    }

    /// 是否还有进行中的任务。
    public var hasRunningJobs: Bool { jobs.contains { $0.state.isActive } }

    /// 进行中任务数量。
    public var runningCount: Int { jobs.filter { $0.state.isActive }.count }

    /// 右栏展示用：最近 3 条任务（最小窗口下不溢出）。
    public var recentJobs: [DownloadInstallJob] { Array(jobs.prefix(3)) }

    /// 某个项目的进行中任务（详情面板显示进度 / 取消按钮用）。
    public func activeJob(for projectID: String) -> DownloadInstallJob? {
        jobs.first { $0.projectID == projectID && $0.state.isActive }
    }

    /// 清空已结束的任务。
    public func clearFinished() {
        jobs.removeAll { !$0.state.isActive }
    }

    /// 取消单个任务（真实取消下载）。
    public func cancel(jobID: UUID) {
        tasks[jobID]?.cancel()
        tasks[jobID] = nil
        if let baseVersion = baseVersions[jobID], let engine = modpackEngine {
            engine.cancelInstall(versionID: baseVersion)
        }
        update(jobID) { job in
            job.state = .cancelled
            job.phase = "已取消"
            job.fraction = nil
        }
    }

    /// 取消全部进行中的任务。
    public func cancelAll() {
        for jobID in Array(tasks.keys) {
            cancel(jobID: jobID)
        }
    }

    // MARK: - 单个资源文件

    /// 安装单个资源文件（模组 / 资源包 / 光影 / 数据包 / 世界）。
    /// - Parameters:
    ///   - projectTitle: 项目标题（展示用）。
    ///   - file: 真实下载文件（来自 Modrinth 版本接口）。
    ///   - type: 资源类型，决定落盘目录。
    ///   - instanceID: 目标实例 id。
    ///   - settings: 启动器设置（决定游戏目录与版本隔离规则）。
    public func installResource(
        projectID: String,
        projectTitle: String,
        file: ModrinthVersion.File,
        type: ModrinthProjectType,
        instanceID: String,
        settings: LauncherSettings
    ) {
        let jobID = UUID()
        insert(
            DownloadInstallJob(
                id: jobID,
                projectID: projectID,
                title: projectTitle,
                subtitle: "\(type.title) · 实例 \(instanceID)",
                phase: "准备下载",
                fraction: nil,
                detail: file.sizeText
            )
        )

        let gameDirectory = settings.gameDirectory(for: instanceID)
        let cacheDirectory = MinecraftInstallation(root: settings.resolvedGameDirectory).cacheDirectory
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Self.performResourceInstall(
                    jobID: jobID,
                    file: file,
                    type: type,
                    gameDirectory: gameDirectory,
                    cacheDirectory: cacheDirectory,
                    center: self
                )
                self.finish(jobID, state: .finished, toast: "已安装到 \(type.title)目录：\(file.filename)")
            } catch {
                if self.isCancellation(error) {
                    self.finish(jobID, state: .cancelled, toast: nil)
                } else {
                    self.finish(jobID, state: .failed(error.localizedDescription), toast: "安装失败：\(error.localizedDescription)")
                }
            }
            self.tasks[jobID] = nil
        }
        tasks[jobID] = task
    }

    /// 单个资源文件的真实下载（world 为下载后解压到 saves）。
    private static func performResourceInstall(
        jobID: UUID,
        file: ModrinthVersion.File,
        type: ModrinthProjectType,
        gameDirectory: URL,
        cacheDirectory: URL,
        center: DownloadInstallCenter
    ) async throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)

        if type == .world {
            // 世界是压缩包：先下载到缓存，再解压到 saves/<世界名>
            let archiveURL = cacheDirectory
                .appendingPathComponent("downloads", isDirectory: true)
                .appendingPathComponent(ModrinthInstallPlanner.sanitizedFilename(file.filename))
            center.update(jobID) { job in
                job.phase = "下载世界压缩包"
                job.fraction = 0
                job.detail = file.sizeText
            }
            try await center.download(file: file, to: archiveURL) { fraction, completed, total in
                center.reportProgress(
                    jobID: jobID,
                    fraction: fraction,
                    detail: "\(ModrinthFormat.fileSize(Int64(completed))) / \(ModrinthFormat.fileSize(Int64(total)))"
                )
            }
            try Task.checkCancellation()
            let destination = ModrinthInstallPlanner.worldDestination(
                instanceDirectory: gameDirectory,
                filename: file.filename
            )
            center.update(jobID) { job in
                job.phase = "解压世界"
                job.fraction = nil
                job.detail = destination.lastPathComponent
            }
            try await Self.unzip(archive: archiveURL, to: destination)
            try? FileManager.default.removeItem(at: archiveURL)
            center.update(jobID) { job in
                job.fraction = 1
            }
            return
        }

        guard let destination = ModrinthInstallPlanner.fileDestination(
            instanceDirectory: gameDirectory,
            type: type,
            filename: file.filename
        ) else {
            throw ModpackIndexError.extraction("无法确定 \(type.title) 的安装目录")
        }
        center.update(jobID) { job in
            job.phase = "下载 \(type.title)"
            job.fraction = 0
        }
        try await center.download(file: file, to: destination) { fraction, completed, total in
            center.reportProgress(
                jobID: jobID,
                fraction: fraction,
                detail: "\(ModrinthFormat.fileSize(Int64(completed))) / \(ModrinthFormat.fileSize(Int64(total)))"
            )
        }
        center.update(jobID) { job in
            job.fraction = 1
        }
    }

    // MARK: - 整合包

    /// 从 Modrinth 安装整合包：下载 `.mrpack` → 确保基础版本 → 加载器版本 → 实例 + 文件 + overrides。
    public func installModpack(
        projectID: String,
        projectTitle: String,
        version: ModrinthVersion,
        mcVersion: String?,
        settings: LauncherSettings,
        engine: LauncherEngine
    ) {
        guard let file = version.primaryFile else {
            notify?("该整合包版本没有可下载文件", .danger)
            return
        }
        let jobID = UUID()
        insert(
            DownloadInstallJob(
                id: jobID,
                projectID: projectID,
                title: projectTitle,
                subtitle: "整合包 · \(version.versionNumber)",
                phase: "准备下载整合包",
                fraction: nil,
                detail: ModrinthFormat.fileSize(file.size)
            )
        )
        modpackEngine = engine
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performModpackInstall(
                    jobID: jobID,
                    projectTitle: projectTitle,
                    remoteFile: file,
                    localFile: nil,
                    fallbackMCVersion: mcVersion,
                    settings: settings,
                    engine: engine
                )
            } catch {
                self.finishModpackError(jobID: jobID, error: error)
            }
            self.tasks[jobID] = nil
            self.baseVersions[jobID] = nil
        }
        tasks[jobID] = task
    }

    /// 从本地文件导入整合包（`.mrpack` / `.zip`），走与在线安装完全相同的流程。
    public func importModpack(
        from url: URL,
        settings: LauncherSettings,
        engine: LauncherEngine
    ) {
        let jobID = UUID()
        insert(
            DownloadInstallJob(
                id: jobID,
                projectID: nil,
                title: url.lastPathComponent,
                subtitle: "整合包 · 本地导入",
                phase: "读取本地整合包",
                fraction: nil
            )
        )
        modpackEngine = engine
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performModpackInstall(
                    jobID: jobID,
                    projectTitle: url.deletingPathExtension().lastPathComponent,
                    remoteFile: nil,
                    localFile: url,
                    fallbackMCVersion: nil,
                    settings: settings,
                    engine: engine
                )
            } catch {
                self.finishModpackError(jobID: jobID, error: error)
            }
            self.tasks[jobID] = nil
            self.baseVersions[jobID] = nil
        }
        tasks[jobID] = task
    }

    /// 整合包安装主流程（在线 / 本地共用）。
    private func performModpackInstall(
        jobID: UUID,
        projectTitle: String,
        remoteFile: ModrinthVersion.File?,
        localFile: URL?,
        fallbackMCVersion: String?,
        settings: LauncherSettings,
        engine: LauncherEngine
    ) async throws {
        let fileManager = FileManager.default
        let installation = MinecraftInstallation(root: settings.resolvedGameDirectory)
        let workRoot = installation.cacheDirectory.appendingPathComponent("modpacks", isDirectory: true)
        let staging = workRoot.appendingPathComponent("staging-\(jobID.uuidString.prefix(8))", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        // 1. 拿到 .mrpack 文件
        let archive: URL
        if let localFile {
            archive = localFile
        } else if let remoteFile {
            let destination = workRoot.appendingPathComponent(
                ModrinthInstallPlanner.sanitizedFilename(remoteFile.filename),
                isDirectory: false
            )
            update(jobID) { job in
                job.phase = "下载整合包文件"
                job.fraction = 0
                job.detail = ModrinthFormat.fileSize(remoteFile.size)
            }
            try await download(file: remoteFile, to: destination) { [weak self] fraction, completed, total in
                self?.reportProgress(
                    jobID: jobID,
                    fraction: fraction,
                    detail: "\(ModrinthFormat.fileSize(Int64(completed))) / \(ModrinthFormat.fileSize(Int64(total)))"
                )
            }
            archive = destination
        } else {
            throw ModpackIndexError.missingIndex
        }

        // 2. 解压到临时目录并读取 modrinth.index.json
        update(jobID) { job in
            job.phase = "解析整合包清单"
            job.fraction = nil
            job.detail = archive.lastPathComponent
        }
        try await Self.unzip(archive: archive, to: staging)
        try Task.checkCancellation()
        let indexURL = staging.appendingPathComponent("modrinth.index.json")
        guard let indexData = try? Data(contentsOf: indexURL) else {
            throw ModpackIndexError.missingIndex
        }
        let index = try ModrinthModpackIndex.decode(indexData)
        guard let mcVersion = index.minecraftVersion ?? fallbackMCVersion else {
            throw ModpackIndexError.missingDependencies
        }
        guard index.loader.isSupported else {
            throw ModpackIndexError.unsupportedLoader(index.loader.title)
        }
        let modpackTitle = index.name.isEmpty ? projectTitle : index.name
        update(jobID) { job in
            job.title = "\(modpackTitle) \(index.versionID)"
            job.detail = "\(index.clientFiles.count) 个文件 · \(index.loader.title) · MC \(mcVersion)"
        }

        // 3. 基础版本：未安装时进入安装队列并等待（真实进度由引擎提供）
        if !engine.installedVersions.contains(where: { $0.id == mcVersion })
            || !fileManager.fileExists(atPath: installation.versionJarURL(mcVersion).path) {
            baseVersions[jobID] = mcVersion
            update(jobID) { job in
                job.phase = "安装基础版本 \(mcVersion)"
                job.fraction = nil
                job.detail = "基础版本未安装，已加入安装队列"
            }
            try await engine.ensureInstalled(versionID: mcVersion, options: InstallOptions(includeAssets: true))
            baseVersions[jobID] = nil
        }
        try Task.checkCancellation()

        // 4. 加载器版本（Fabric / Quilt）：写入版本 JSON + 复用基础版本客户端 jar + 下载依赖库
        var baseInstanceID = mcVersion
        switch index.loader {
        case .fabric(let loaderVersion):
            baseInstanceID = try await installLoader(
                jobID: jobID,
                kind: .fabric,
                minecraft: mcVersion,
                loaderVersion: loaderVersion,
                installation: installation
            )
        case .quilt(let loaderVersion):
            baseInstanceID = try await installLoader(
                jobID: jobID,
                kind: .quilt,
                minecraft: mcVersion,
                loaderVersion: loaderVersion,
                installation: installation
            )
        case .vanilla:
            baseInstanceID = mcVersion
        case .forge, .neoforge, .unsupported:
            throw ModpackIndexError.unsupportedLoader(index.loader.title)
        }
        try Task.checkCancellation()

        // 5. 建立整合包实例：版本 JSON（inheritsFrom 加载器 / 基础版本）+ 复用客户端 jar
        let desiredInstanceID = ModrinthInstallPlanner.instanceID(name: modpackTitle, versionID: index.versionID)
        let instanceID = uniqueInstanceID(
            desiredInstanceID,
            installation: installation,
            reserved: [baseInstanceID, mcVersion]
        )
        let instanceDirectory = installation.versionDirectory(instanceID)
        try fileManager.createDirectory(at: instanceDirectory, withIntermediateDirectories: true)
        try writeInstanceVersionJSON(instanceID: instanceID, inheritsFrom: baseInstanceID, installation: installation)
        try Self.linkOrCopy(
            from: installation.versionJarURL(baseInstanceID),
            to: installation.versionJarURL(instanceID)
        )
        update(jobID) { job in
            job.subtitle = "整合包 · 新建实例 \(instanceID)"
            job.phase = "创建实例 \(instanceID)"
            job.fraction = nil
        }

        // 6. 解压 overrides / client-overrides（客户端覆盖优先）
        let gameDirectory = settings.gameDirectory(for: instanceID)
        try fileManager.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        update(jobID) { job in
            job.phase = "解压 overrides"
            job.fraction = nil
            job.detail = "配置与资源文件"
        }
        for folder in ["overrides", "client-overrides"] {
            let source = staging.appendingPathComponent(folder, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try Self.copyContents(of: source, into: gameDirectory)
        }
        try Task.checkCancellation()

        // 7. 下载清单里的文件（模组 / 资源包等）到实例目录
        // 先做完整性校验：缺下载地址 / 不安全路径都直接报错，不假装安装成功
        let allFiles = index.clientFiles
        let missingDownloads = index.clientFilesWithoutDownload
        guard missingDownloads.isEmpty else {
            throw ModpackIndexError.missingFileDownload(missingDownloads.map(\.path))
        }
        let files = allFiles.filter { ModrinthInstallPlanner.isSafeRelativePath($0.path) }
        guard files.count == allFiles.count else {
            throw ModpackIndexError.extraction("整合包清单包含不安全路径（可能试图写出实例目录）")
        }
        var completed = 0
        for file in files {
            try Task.checkCancellation()
            guard let url = file.downloads.first else {
                // 前面已校验过，这里只做防御：仍然不允许静默跳过
                throw ModpackIndexError.missingFileDownload([file.path])
            }
            let destination = gameDirectory.appendingPathComponent(file.path)
            if let expectedSize = file.fileSize, fileManager.fileExists(atPath: destination.path) {
                // 已存在且大小一致：跳过重复下载（与 PCL / HMCL 行为一致）
                let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                if Int64(size) == expectedSize {
                    completed += 1
                    update(jobID) { job in
                        job.fraction = Double(completed) / Double(max(files.count, 1))
                        job.detail = "\(completed) / \(files.count) 个文件"
                    }
                    continue
                }
            }
            try await downloader.download(
                FileDownloadTask(url: url, destination: destination, sha1: file.hashes.sha1, expectedSize: file.fileSize)
            ) { _ in }
            completed += 1
            update(jobID) { job in
                job.phase = "下载整合包文件"
                job.fraction = Double(completed) / Double(max(files.count, 1))
                job.detail = "\(completed) / \(files.count) 个文件"
            }
        }

        // 8. 收尾：刷新引擎环境
        update(jobID) { job in
            job.phase = "完成"
            job.fraction = 1
        }
        await engine.refreshEnvironment()
        finish(jobID, state: .finished, toast: "整合包已安装：\(instanceID)")
    }

    // MARK: - 加载器

    /// 加载器类型。
    private enum LoaderKind {
        case fabric
        case quilt
    }

    /// 写入加载器版本（profile JSON + 复用基础客户端 jar + 下载加载器依赖库），返回加载器实例 id。
    private func installLoader(
        jobID: UUID,
        kind: LoaderKind,
        minecraft: String,
        loaderVersion: String,
        installation: MinecraftInstallation
    ) async throws -> String {
        update(jobID) { job in
            job.phase = "获取 \(kind == .fabric ? "Fabric" : "Quilt") 加载器配置"
            job.fraction = nil
            job.detail = "\(loaderVersion) / MC \(minecraft)"
        }
        let profileURL: URL?
        switch kind {
        case .fabric:
            profileURL = ModrinthEndpoint.fabricLoaderProfile(minecraft: minecraft, loader: loaderVersion)
        case .quilt:
            profileURL = ModrinthEndpoint.quiltLoaderProfile(minecraft: minecraft, loader: loaderVersion)
        }
        guard let profileURL else { throw ModrinthError.invalidURL }
        let data = try await client.data(from: profileURL)
        let profile = try JSONDecoder().decode(VersionDetail.self, from: data)
        let loaderID = profile.id

        let fileManager = FileManager.default
        let loaderDirectory = installation.versionDirectory(loaderID)
        try fileManager.createDirectory(at: loaderDirectory, withIntermediateDirectories: true)
        try data.write(to: installation.versionJSONURL(loaderID), options: .atomic)
        try Self.linkOrCopy(
            from: installation.versionJarURL(minecraft),
            to: installation.versionJarURL(loaderID)
        )

        // 加载器依赖库：只补缺失文件，避免重复下载
        let libraries = (profile.libraries ?? []).filter { RuleEvaluator.isAllowed($0.rules) }
        var pending: [(url: URL, destination: URL)] = []
        for library in libraries {
            guard let mavenPath = library.mavenPath, let url = library.downloadURL() else { continue }
            let destination = installation.librariesDirectory.appendingPathComponent(mavenPath)
            if fileManager.fileExists(atPath: destination.path) { continue }
            pending.append((url, destination))
        }
        var completed = 0
        let total = pending.count
        for item in pending {
            try Task.checkCancellation()
            try await downloader.download(
                FileDownloadTask(url: item.url, destination: item.destination)
            ) { _ in }
            completed += 1
            update(jobID) { job in
                job.phase = "下载加载器依赖"
                job.fraction = total > 0 ? Double(completed) / Double(total) : 1
                job.detail = "\(completed) / \(total) 个依赖库"
            }
        }
        return loaderID
    }

    // MARK: - 下载

    /// 带真实进度回调的文件下载（sha1 校验由 FileDownloader 负责）。
    private func download(
        file: ModrinthVersion.File,
        to destination: URL,
        progress: @escaping @Sendable (_ fraction: Double, _ completed: Int64, _ total: Int64) -> Void
    ) async throws {
        let total = file.size
        try await downloader.download(
            FileDownloadTask(url: file.url, destination: destination, sha1: file.sha1, expectedSize: file.size)
        ) { fraction in
            progress(fraction, Int64(Double(total) * fraction), total)
        }
    }

    // MARK: - 任务状态

    /// 从后台线程安全地汇报进度（下载回调是非主线程的 @Sendable 闭包）。
    private nonisolated func reportProgress(
        jobID: UUID,
        fraction: Double?,
        phase: String? = nil,
        detail: String? = nil
    ) {
        Task { @MainActor in
            self.update(jobID) { job in
                if let phase { job.phase = phase }
                if let fraction { job.fraction = fraction }
                if let detail { job.detail = detail }
            }
        }
    }

    private func insert(_ job: DownloadInstallJob) {
        jobs.insert(job, at: 0)
        if jobs.count > jobLimit {
            jobs.removeLast(jobs.count - jobLimit)
        }
    }

    private func update(_ jobID: UUID, _ mutate: (inout DownloadInstallJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        mutate(&jobs[index])
    }

    private func finish(_ jobID: UUID, state: DownloadInstallJob.State, toast: String?) {
        update(jobID) { job in
            job.state = state
            job.fraction = nil
            switch state {
            case .finished:
                job.phase = "已完成"
            case .cancelled:
                job.phase = "已取消"
            case .failed(let message):
                job.phase = "失败"
                job.detail = message
            case .running:
                break
            }
        }
        if let toast {
            notify?(toast, state.isSuccess ? .success : .warning)
        }
    }

    /// 整合包任务失败 / 取消的统一收尾。
    private func finishModpackError(jobID: UUID, error: Error) {
        if isCancellation(error) {
            finish(jobID, state: .cancelled, toast: nil)
            return
        }
        finish(
            jobID,
            state: .failed(error.localizedDescription),
            toast: "整合包安装失败：\(error.localizedDescription)"
        )
    }

    /// 是否是因为任务被取消而中断（URLSession 抛 URLError.cancelled）。
    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return Task.isCancelled
    }

    // MARK: - 文件系统

    /// 生成不冲突的实例 id（已存在时追加序号）。
    private func uniqueInstanceID(_ desired: String, installation: MinecraftInstallation, reserved: [String]) -> String {
        let fileManager = FileManager.default
        func isFree(_ id: String) -> Bool {
            !reserved.contains(id)
                && !fileManager.fileExists(atPath: installation.versionDirectory(id).path)
        }
        guard !isFree(desired) else { return desired }
        for index in 2...99 {
            let candidate = "\(desired)-\(index)"
            if isFree(candidate) { return candidate }
        }
        return "\(desired)-\(Int(Date().timeIntervalSince1970))"
    }

    /// 写入整合包实例的最小版本 JSON（id + inheritsFrom），父版本提供其余全部信息。
    private func writeInstanceVersionJSON(instanceID: String, inheritsFrom: String, installation: MinecraftInstallation) throws {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        let payload: [String: Any] = [
            "id": instanceID,
            "inheritsFrom": inheritsFrom,
            "type": "release",
            "time": now,
            "releaseTime": now
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: installation.versionJSONURL(instanceID), options: .atomic)
    }

    /// 硬链接（同卷）或复制（跨卷）：复用客户端 jar 时不额外占空间。
    private nonisolated static func linkOrCopy(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else {
            throw ModpackIndexError.extraction("缺少基础版本客户端 jar：\(source.lastPathComponent)")
        }
        if fileManager.fileExists(atPath: destination.path) { return }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try fileManager.linkItem(at: source, to: destination)
        } catch {
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    /// 把目录内容合并复制到目标目录（同名文件覆盖）。
    private nonisolated static func copyContents(of source: URL, into destination: URL) throws {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for entry in entries {
            let target = destination.appendingPathComponent(entry.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                try? fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: entry, to: target)
        }
    }

    /// 列出压缩包内所有条目名（zip-slip 校验用）。
    private nonisolated static func archiveEntries(_ archive: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", archive.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ModpackIndexError.extraction("无法读取压缩包目录：\(archive.lastPathComponent)")
        }
        let output = String(data: data, encoding: .utf8) ?? ""
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// 解压压缩包到目标目录（后台线程执行，避免阻塞主线程）。
    /// 解压前先列条目做 zip-slip 校验：`..`、绝对路径、反斜杠路径一律拒绝。
    private nonisolated static func unzip(archive: URL, to destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let entries = try Self.archiveEntries(archive)
            if let unsafeEntry = ModrinthInstallPlanner.firstUnsafeZipEntry(in: entries) {
                throw ModpackIndexError.unsafeArchiveEntry(unsafeEntry)
            }
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-oq", archive.path, "-d", destination.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw ModpackIndexError.extraction(
                    output.isEmpty ? "unzip 退出码 \(process.terminationStatus)" : output.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }.value
    }
}
