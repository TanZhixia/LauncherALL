import Foundation
import Observation

/// 启动器运行时：Java 检测、版本安装、启动/停止游戏的真实编排。
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
    public private(set) var phase: Phase = .idle
    public private(set) var installedVersions: [InstalledVersion] = []
    public private(set) var javaRuntimes: [JavaRuntime] = []
    public private(set) var logLines: [String] = []
    public private(set) var lastCommandLine: String?
    public private(set) var activeVersionID: String?
    public private(set) var lastExitCode: Int32?

    private let gameLauncher = GameLauncher()
    private var logLimit = 600

    public init(settings: LauncherSettings = .shared) {
        self.settings = settings
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

    public func install(versionID: String) async {
        guard !isBusy else { return }
        phase = .downloading(versionID: versionID, progress: InstallProgress(phase: "准备安装", completed: 0, total: 1))
        appendLog("开始安装版本 \(versionID)")

        let installation = self.installation
        let installer = VersionInstaller(installation: installation)
        let settingsSnapshot = settings
        do {
            _ = try await installer.install(versionID: versionID, includeAssets: true) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .downloading(_, let current) = self.phase,
                       current.phase == progress.phase,
                       progress.fraction - current.fraction < 0.02 {
                        return
                    }
                    self.phase = .downloading(versionID: versionID, progress: progress)
                }
            }
            appendLog("版本 \(versionID) 安装完成")
            phase = .idle
            await refreshEnvironment()
            _ = settingsSnapshot
        } catch {
            appendLog("安装失败：\(error.localizedDescription)")
            phase = .failed("安装失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 启动

    public func launch(versionID: String) async {
        guard !isBusy else { return }
        activeVersionID = versionID
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

        let gameDirectory = settings.gameDirectory(for: versionID)
        let options = LaunchOptions(
            versionID: versionID,
            playerName: settings.playerName,
            java: java,
            memoryMB: settings.maxMemoryMB,
            renderThreads: settings.renderThreads,
            extraJVMArguments: settings.extraJVMArguments,
            gameDirectory: gameDirectory
        )

        do {
            let command = try LaunchCommandBuilder.build(detail: detail, installation: installation, options: options)
            lastCommandLine = command.commandLine
            phase = .launching
            appendLog("启动命令：\(command.commandLine)")

            let pid = try gameLauncher.launch(
                command,
                workingDirectory: gameDirectory,
                onLine: { line in
                    Task { @MainActor [weak self] in self?.appendLog(line) }
                },
                onExit: { status in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.lastExitCode = status
                        self.phase = status == 0 ? .idle : .failed("游戏退出，代码 \(status)")
                        self.appendLog("游戏进程退出，代码 \(status)")
                    }
                }
            )
            phase = .running(startedAt: Date())
            appendLog("游戏已启动（pid \(pid)）")
        } catch {
            appendLog("启动失败：\(error.localizedDescription)")
            phase = .failed("启动失败：\(error.localizedDescription)")
        }
    }

    public func stop() {
        gameLauncher.terminate()
        phase = .idle
        appendLog("已请求停止游戏")
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
