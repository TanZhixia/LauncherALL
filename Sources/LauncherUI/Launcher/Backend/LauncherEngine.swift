import Foundation
import Observation

// MARK: - 安装队列

/// 队列里的一个安装任务。
public struct InstallQueueItem: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case queued
        case installing
        case finished
        case cancelled
        case failed(String)

        public var isActive: Bool {
            switch self {
            case .queued, .installing: return true
            case .finished, .cancelled, .failed: return false
            }
        }

        public var title: String {
            switch self {
            case .queued: return "排队中"
            case .installing: return "安装中"
            case .finished: return "已完成"
            case .cancelled: return "已取消"
            case .failed: return "失败"
            }
        }
    }

    public let id: UUID
    public let versionID: String
    public let options: InstallOptions
    public var state: State
    public var progress: InstallProgress?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        versionID: String,
        options: InstallOptions = .default,
        state: State = .queued,
        progress: InstallProgress? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.versionID = versionID
        self.options = options
        self.state = state
        self.progress = progress
        self.createdAt = createdAt
    }
}

// MARK: - 启动器运行时

/// 队列错误：安装失败 / 被取消。
public enum InstallQueueError: LocalizedError {
    case failed(String, String)
    case cancelled(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let versionID, let message): return "安装 \(versionID) 失败：\(message)"
        case .cancelled(let versionID): return "安装 \(versionID) 已取消"
        }
    }
}

/// 启动器运行时：Java 检测、版本安装（队列 / 取消 / 校验）、启动/停止游戏的真实编排。
@MainActor
@Observable
public final class LauncherEngine {
    public enum Phase: Equatable {
        case idle
        case preparing(String)
        case downloading(versionID: String, progress: InstallProgress)
        case launching
        case running(startedAt: Date)
        case failed(String)

        public var isBusy: Bool {
            switch self {
            case .idle, .failed, .running: return false
            case .preparing, .downloading, .launching: return true
            }
        }
    }

    public let settings: LauncherSettings
    /// 账户中心：正版登录 / 多账户切换 / 启动身份解析。
    public let accountStore: AccountStore
    public private(set) var phase: Phase = .idle
    public private(set) var installedVersions: [InstalledVersion] = []
    public private(set) var javaRuntimes: [JavaRuntime] = []
    public private(set) var logLines: [String] = []
    public private(set) var lastCommandLine: String?
    public private(set) var activeVersionID: String?
    public private(set) var lastExitCode: Int32?
    /// 真实安装队列（串行执行，可取消）。
    public private(set) var installQueue: [InstallQueueItem] = []

    private let gameLauncher = GameLauncher()
    private var logLimit = 600
    private var installTask: Task<Void, Never>?
    /// 当前启动记录 id（用于退出时回填退出码）。
    private var activeLaunchRecordID: UUID?
    /// 是否由用户主动停止：主动停止导致的退出码（SIGTERM 15）不应显示成"启动失败"。
    private var stopRequested = false
    /// 启动代号：每次启动 +1，旧进程的退出回调不能改写新进程的状态。
    private var launchGeneration = 0

    public init(settings: LauncherSettings = .shared, accountStore: AccountStore? = nil) {
        self.settings = settings
        self.accountStore = accountStore ?? AccountStore(settings: settings)
    }

    // MARK: - 环境

    public var installation: MinecraftInstallation {
        MinecraftInstallation(root: settings.resolvedGameDirectory)
    }

    /// 启动时调用：扫描 Java 与已安装版本。
    public func refreshEnvironment() async {
        let root = settings.resolvedGameDirectory
        let (runtimes, versions) = await Task.detached(priority: .userInitiated) { () -> ([JavaRuntime], [InstalledVersion]) in
            let java = JavaLocator.detectAll()
            let installation = MinecraftInstallation(root: root)
            return (java, installation.installedVersions())
        }.value
        javaRuntimes = runtimes
        installedVersions = versions
    }

    /// 选中的 Java：优先设置里手动指定，其次按版本要求挑最合适的。
    public func resolvedJava(for versionDetail: ResolvedVersion?) -> JavaRuntime? {
        if !settings.javaAutoDetect {
            let url = URL(fileURLWithPath: (settings.javaRuntimePath as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: url.path),
               let output = try? JavaLocator.runCommand(url.path, arguments: ["-version"]),
               let runtime = JavaLocator.parseVersionOutput(output, executable: url) {
                return runtime
            }
        }
        let required = versionDetail?.javaVersion?.majorVersion ?? 21
        if let best = JavaLocator.bestRuntime(for: required, in: javaRuntimes) {
            return best
        }
        return javaRuntimes.max { $0.majorVersion < $1.majorVersion }
    }

    /// 当前选中版本将使用的 Java（用于 UI 显示）。
    public var resolvedJavaLabel: String? {
        if let versionID = activeVersionID,
           let data = try? Data(contentsOf: installation.versionJSONURL(versionID)),
           let detail = try? JSONDecoder().decode(VersionDetail.self, from: data),
           let java = resolvedJava(for: detail.javaVersion?.majorVersion) {
            return "Java \(java.majorVersion)"
        }
        return javaRuntimes.first.map { "Java \($0.majorVersion)" }
    }

    /// 按主版本要求挑选运行时（供 UI 显示用）。
    public func resolvedJava(for requiredMajor: Int?) -> JavaRuntime? {
        let required = requiredMajor ?? 21
        if let best = JavaLocator.bestRuntime(for: required, in: javaRuntimes) {
            return best
        }
        return javaRuntimes.max { $0.majorVersion < $1.majorVersion }
    }

    /// 某个已安装版本要求的 Java 主版本（读本地版本 JSON；加载器版本回退到父版本）。
    public func requiredJavaMajor(for versionID: String) -> Int? {
        let jsonURL = installation.versionJSONURL(versionID)
        guard let data = try? Data(contentsOf: jsonURL),
              let detail = try? JSONDecoder().decode(VersionDetail.self, from: data) else { return nil }
        if let major = detail.javaVersion?.majorVersion { return major }
        if let parent = detail.inheritsFrom {
            return requiredJavaMajor(for: parent)
        }
        return nil
    }

    public var statusText: String {
        switch phase {
        case .idle:
            if installedVersions.isEmpty { return "尚未安装任何版本 · 先去「下载」安装一个" }
            return "就绪 · 已安装 \(installedVersions.count) 个版本 · 检测到 \(javaRuntimes.count) 个 Java"
        case .preparing(let message): return message
        case .downloading(_, let progress):
            return "\(progress.phase) · \(Int(progress.fraction * 100))%"
        case .launching: return "正在启动游戏…"
        case .running: return "游戏运行中"
        case .failed(let message): return message
        }
    }

    public var isBusy: Bool { phase.isBusy }

    // MARK: - 安装

    /// 立即安装并等待完成（内部会加入队列，便于统一取消与进度展示）。
    @discardableResult
    public func install(versionID: String, options: InstallOptions = .default) async -> InstallQueueItem? {
        let item = enqueueInstall(versionID: versionID, options: options)
        await waitForInstall(itemID: item.id)
        return installQueue.first { $0.id == item.id }
    }

    /// 确保某版本已安装：已装则直接返回；否则排队安装并等待，失败 / 取消时抛错。
    /// 供「整合包安装前先确保基础版本」这类串行流程使用。
    public func ensureInstalled(versionID: String, options: InstallOptions = .default) async throws {
        if !options.verifyExisting,
           installedVersions.contains(where: { $0.id == versionID }),
           FileManager.default.fileExists(atPath: installation.versionJarURL(versionID).path) {
            return
        }
        let item = enqueueInstall(versionID: versionID, options: options)
        await waitForInstall(itemID: item.id)
        switch installQueue.first(where: { $0.id == item.id })?.state {
        case .finished:
            return
        case .cancelled:
            throw InstallQueueError.cancelled(versionID)
        case .failed(let message):
            throw InstallQueueError.failed(versionID, message)
        case .installing, .queued, .none:
            throw InstallQueueError.cancelled(versionID)
        }
    }

    /// 等待某个队列项结束。
    private func waitForInstall(itemID: UUID) async {
        while installQueue.contains(where: { $0.id == itemID && $0.state.isActive }) {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// 加入安装队列；空闲时立即执行。
    @discardableResult
    public func enqueueInstall(versionID: String, options: InstallOptions = .default) -> InstallQueueItem {
        let item = InstallQueueItem(versionID: versionID, options: options)
        installQueue.append(item)
        appendLog("已加入安装队列：\(versionID)（\(options.summary)）")
        startNextInstallIfIdle()
        return item
    }

    /// 取消安装：`versionID == nil` 时取消当前正在执行的任务。
    public func cancelInstall(versionID: String? = nil) {
        let targetID = versionID
            ?? installQueue.first(where: { $0.state == .installing })?.versionID
        guard let targetID else { return }

        // 取消正在执行的任务（不立即清空 installTask，等任务收尾，避免同时跑两个安装）
        if let index = installQueue.firstIndex(where: { $0.versionID == targetID && $0.state == .installing }) {
            installQueue[index].state = .cancelled
            installTask?.cancel()
            if case .downloading(let current, _) = phase, current == targetID {
                phase = .idle
            }
            appendLog("已取消安装：\(targetID)")
        }
        // 取消排队中的同版本任务
        for index in installQueue.indices where installQueue[index].versionID == targetID && installQueue[index].state == .queued {
            installQueue[index].state = .cancelled
            appendLog("已取消排队：\(targetID)")
        }
        startNextInstallIfIdle()
    }

    /// 清空已经结束的队列项。
    public func clearFinishedInstalls() {
        installQueue.removeAll { !$0.state.isActive }
    }

    /// 移除单个已结束的队列项。
    public func removeQueueItem(_ id: UUID) {
        installQueue.removeAll { $0.id == id && !$0.state.isActive }
    }

    /// 队列里某版本的进度（没有则 nil）。
    public func queueItem(for versionID: String) -> InstallQueueItem? {
        installQueue.last { $0.versionID == versionID }
    }

    /// 校验一个已安装版本的文件完整性。
    public func verifyInstalled(versionID: String) async -> InstallVerification? {
        let installer = VersionInstaller(installation: installation, source: settings.downloadSourceValue)
        do {
            let result = try await installer.verify(versionID: versionID)
            appendLog("校验 \(versionID)：\(result.summary)")
            return result
        } catch {
            appendLog("校验失败：\(error.localizedDescription)")
            return nil
        }
    }

    private func startNextInstallIfIdle() {
        guard installTask == nil else { return }
        guard let index = installQueue.firstIndex(where: { $0.state == .queued }) else { return }
        let item = installQueue[index]
        installQueue[index].state = .installing
        phase = .downloading(versionID: item.versionID, progress: InstallProgress(phase: "准备安装", completed: 0, total: 1))
        installTask = Task { [weak self] in
            await self?.performInstall(itemID: item.id)
        }
    }

    private func performInstall(itemID: UUID) async {
        guard let index = installQueue.firstIndex(where: { $0.id == itemID }) else {
            installTask = nil
            return
        }
        let item = installQueue[index]
        let versionID = item.versionID
        let options = item.options
        appendLog("开始安装版本 \(versionID)（\(options.summary)）")

        let installation = self.installation
        let installer = VersionInstaller(installation: installation, source: settings.downloadSourceValue)
        do {
            _ = try await installer.install(versionID: versionID, options: options) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.applyInstallProgress(itemID: itemID, versionID: versionID, progress: progress)
                }
            }
            markInstallFinished(itemID: itemID, state: .finished)
            appendLog("版本 \(versionID) 安装完成")
            phase = .idle
            await refreshEnvironment()
            suggestCleanupIfNeeded()
        } catch {
            if Self.isCancellation(error) {
                markInstallFinished(itemID: itemID, state: .cancelled)
                appendLog("安装已取消：\(versionID)")
                phase = .idle
            } else {
                markInstallFinished(itemID: itemID, state: .failed(error.localizedDescription))
                appendLog("安装失败：\(error.localizedDescription)")
                phase = .failed("安装失败：\(error.localizedDescription)")
            }
        }
        installTask = nil
        startNextInstallIfIdle()
    }

    /// 取消判定：Task 取消、`URLError.cancelled`（URLSession 在 IO 等待时抛的是这个）都算取消，
    /// 不能把用户主动取消上报成"安装失败"。
    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return Task.isCancelled
    }

    private func applyInstallProgress(itemID: UUID, versionID: String, progress: InstallProgress) {
        guard let index = installQueue.firstIndex(where: { $0.id == itemID }) else { return }
        let current = installQueue[index].progress
        // 同一阶段进度变化小于 2% 时不刷新，避免 UI 抖动
        if let current,
           current.phase == progress.phase,
           progress.fraction - current.fraction < 0.02,
           progress.fraction < 1 {
            return
        }
        installQueue[index].progress = progress
        if case .downloading(let currentID, _) = phase, currentID == versionID {
            phase = .downloading(versionID: versionID, progress: progress)
        }
    }

    private func markInstallFinished(itemID: UUID, state: InstallQueueItem.State) {
        guard let index = installQueue.firstIndex(where: { $0.id == itemID }) else { return }
        installQueue[index].state = state
        if let progress = installQueue[index].progress {
            installQueue[index].progress = InstallProgress(phase: progress.phase, completed: progress.total, total: progress.total)
        }
    }

    /// 自动清理：安装完成后给出可清理的旧版本提示（写入日志，页面自行展示）。
    private func suggestCleanupIfNeeded() {
        guard settings.autoCleanOldVersions else { return }
        let candidates = unusedVersions(olderThanDays: 30)
        guard !candidates.isEmpty else { return }
        appendLog("可清理 \(candidates.count) 个 30 天未使用的版本：\(candidates.map(\.id).joined(separator: ", "))")
    }

    // MARK: - 清理旧版本

    /// 未被其它实例 `inheritsFrom` 依赖的版本（依赖父版本删除不得）。
    private func referencedParentIDs() -> Set<String> {
        var ids: Set<String> = []
        for version in installedVersions {
            guard let data = try? Data(contentsOf: version.jsonURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parent = object["inheritsFrom"] as? String else { continue }
            ids.insert(parent)
        }
        return ids
    }

    /// 被删除后会破坏的依赖实例（`inheritsFrom` 指向该版本的实例）。
    public func dependents(of versionID: String) -> [String] {
        installedVersions.compactMap { version -> String? in
            guard version.id != versionID,
                  let data = try? Data(contentsOf: version.jsonURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parent = object["inheritsFrom"] as? String,
                  parent == versionID else { return nil }
            return version.id
        }
    }

    /// 30 天（默认）未启动过的已安装版本：没有启动记录时用目录修改时间判龄，
    /// 并排除被其它实例依赖的父版本（加载器 / 整合包基础版本）。
    public func unusedVersions(olderThanDays days: Int = 30) -> [InstalledVersion] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let referenced = referencedParentIDs()
        return installedVersions.filter { version in
            guard !referenced.contains(version.id) else { return false }
            guard dependents(of: version.id).isEmpty else { return false }
            let lastUsed = settings.lastLaunchDate(for: version.id) ?? version.lastModified
            return lastUsed < cutoff
        }
    }

    /// 把某个版本目录删除到废纸篓并刷新列表；被其它实例依赖时拒绝删除。
    public func deleteVersion(_ versionID: String) throws {
        let users = dependents(of: versionID)
        guard users.isEmpty else {
            throw InstanceActionError.referencedBy(users)
        }
        try InstanceActions.delete(versionID: versionID, installation: installation)
        appendLog("已删除实例 \(versionID)")
        if activeVersionID == versionID { activeVersionID = nil }
        installedVersions.removeAll { $0.id == versionID }
    }

    // MARK: - 启动

    public func launch(versionID: String) async {
        guard !isBusy else { return }
        activeVersionID = versionID
        stopRequested = false
        phase = .preparing("检查运行环境…")
        appendLog("准备启动 \(versionID)")

        if installedVersions.isEmpty {
            await refreshEnvironment()
        }

        let installation = self.installation
        let jsonURL = installation.versionJSONURL(versionID)
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            appendLog("缺少版本文件：\(jsonURL.path)")
            phase = .failed("该版本尚未安装，请先在「下载」页安装")
            return
        }

        let detail: ResolvedVersion
        do {
            detail = try await VersionResolver.resolveAsync(versionID: versionID, installation: installation)
        } catch {
            appendLog("版本解析失败：\(error.localizedDescription)")
            phase = .failed("版本解析失败：\(error.localizedDescription)")
            return
        }

        guard let java = resolvedJava(for: detail) else {
            appendLog("未找到 Java 运行时")
            phase = .failed("未找到 Java 运行时，请在「设置 → Java 运行时」中指定")
            return
        }
        appendLog("使用 \(java.displayName)（\(java.executable.path)）")

        // 解析启动身份：离线账户 → 离线 UUID；正版账户 → 必要时刷新令牌后取 Minecraft 令牌
        let launchAccount: LaunchAccount
        do {
            launchAccount = try await accountStore.launchAccount()
        } catch let error as MicrosoftAuthError {
            appendLog("正版账户不可用：\(error.localizedDescription)")
            phase = .failed("\(error.localizedDescription)（可在「设置 → 账户」重新登录，或切回离线账户）")
            return
        } catch {
            appendLog("账户解析失败：\(error.localizedDescription)")
            phase = .failed("账户解析失败：\(error.localizedDescription)")
            return
        }
        appendLog("使用账户：\(launchAccount.name)（\(launchAccount.kind == .microsoft ? "正版" : "离线")）")

        let gameDirectory = settings.gameDirectory(for: versionID)
        let options = LaunchOptions(
            versionID: versionID,
            playerName: launchAccount.name,
            java: java,
            memoryMB: settings.maxMemoryMB,
            renderThreads: settings.renderThreads,
            extraJVMArguments: settings.extraJVMArguments,
            gameDirectory: gameDirectory,
            account: launchAccount
        )

        do {
            let command = try LaunchCommandBuilder.build(detail: detail, installation: installation, options: options)
            // 日志 / 界面里的启动命令要脱敏：正版 accessToken 不能出现在日志与剪贴板里
            let redactedCommandLine = LaunchCommandBuilder.redacted(
                command.commandLine,
                hiding: launchAccount.accessToken
            )
            lastCommandLine = redactedCommandLine
            phase = .launching
            appendLog("启动命令：\(redactedCommandLine)")

            let recordID = settings.recordLaunchStart(versionID: versionID)
            settings.rememberPlayerName(settings.playerName)
            activeLaunchRecordID = recordID

            launchGeneration += 1
            let generation = launchGeneration
            let pid = try gameLauncher.launch(
                command,
                workingDirectory: gameDirectory,
                onLine: { [weak self] line in
                    Task { @MainActor [weak self] in
                        guard let self, generation == self.launchGeneration else { return }
                        self.appendLog(line)
                    }
                },
                onExit: { [weak self] status in
                    Task { @MainActor [weak self] in
                        guard let self, generation == self.launchGeneration else { return }
                        if self.stopRequested {
                            // 用户主动停止：不记录退出码、不报失败
                            self.stopRequested = false
                            self.lastExitCode = nil
                            self.phase = .idle
                            self.appendLog("游戏进程已结束（用户停止）")
                            return
                        }
                        self.lastExitCode = status
                        self.phase = status == 0 ? .idle : .failed("游戏退出，代码 \(status)")
                        if let recordID = self.activeLaunchRecordID {
                            self.settings.recordLaunchEnd(id: recordID, exitCode: status)
                            self.activeLaunchRecordID = nil
                        }
                        self.appendLog("游戏进程退出，代码 \(status)")
                    }
                }
            )
            phase = .running(startedAt: Date())
            appendLog("游戏已启动（pid \(pid)）")
        } catch {
            appendLog("启动失败：\(error.localizedDescription)")
            phase = .failed("启动失败：\(error.localizedDescription)")
            if let recordID = activeLaunchRecordID {
                settings.recordLaunchEnd(id: recordID, exitCode: nil)
                activeLaunchRecordID = nil
            }
        }
    }

    public func stop() {
        // 先标记主动停止，再 terminate：进程退出回调里据此不再报"启动失败"
        stopRequested = true
        gameLauncher.terminate()
        phase = .idle
        appendLog("已请求停止游戏")
        if let recordID = activeLaunchRecordID {
            settings.recordLaunchEnd(id: recordID, exitCode: nil)
            activeLaunchRecordID = nil
        }
    }

    // MARK: - 日志

    public func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > logLimit {
            logLines.removeFirst(logLines.count - logLimit)
        }
    }

    public func clearLog() {
        logLines.removeAll()
    }
}
