import Foundation
import AppKit
import Observation

// MARK: - DSH Web UI 进程

/// 启动 / 停止 DSH 的 Web UI（`dsh --profile web --no-open --port …`），
/// 从 stdout 解析带 token 的启动 URL，并把日志写入 `logs/<version>.log`。
@MainActor
@Observable
public final class DSHProcessController {
    public let settings: LauncherSettings
    public let paths: DSHPaths

    public private(set) var state: DSHProcessState = .idle
    /// 最近日志行（最多 500 行）。
    public private(set) var logLines: [String] = []
    /// 当前运行 / 最近一次运行的实例 ID。
    public private(set) var activeInstanceID: String?
    /// 当前运行实例的 DSH 版本号（展示用）。
    public private(set) var activeVersion: String?
    public private(set) var activePort: Int?
    public private(set) var startedAt: Date?

    private var process: Process?
    private var readTask: Task<Void, Never>?
    private var exitMonitor: Task<Void, Never>?
    private var startupURL: String?
    private var isStopping = false
    private var lineCount = 0

    public init(settings: LauncherSettings = .shared, paths: DSHPaths = .default) {
        self.settings = settings
        self.paths = paths
    }

    // MARK: 派生

    public var isRunning: Bool { state.isRunning }
    public var isBusy: Bool { state.isBusy }

    /// 启动 URL（带一次性 token，不要长期展示）。
    public var webURL: URL? {
        guard let url = state.url else { return nil }
        return URL(string: url)
    }

    public var logText: String { logLines.joined(separator: "\n") }

    /// 日志文件路径。
    public func logFileURL(instanceID: String) -> URL { paths.logFile(for: instanceID) }

    // MARK: 启动

    /// 启动指定版本的 Web UI。
    @discardableResult
    public func start(version: DSHInstalledVersion) async -> Bool {
        let instanceID = version.id
        guard !isRunning && !isBusy else { return false }
        let script = paths.cliScript(for: instanceID)
        guard FileManager.default.fileExists(atPath: script.path) else {
            state = .failed(DSHError.notInstalled(version.version).localizedDescription)
            return false
        }
        guard let node = DSHExecutables.node() else {
            state = .failed(DSHError.nodeNotFound.localizedDescription)
            return false
        }

        // 0 = 交给 dsh 自己分配（避免先探测端口再被占用的 TOCTOU）
        let port = settings.dshPort > 0 ? DSHPortFinder.findPort(preferred: settings.dshPort) : 0
        activePort = port
        activeInstanceID = instanceID
        activeVersion = version.dshVersion
        startupURL = nil
        lineCount = 0
        logLines = []
        isStopping = false
        startedAt = Date()
        state = .starting

        let home = paths.homeDirectory(for: instanceID)
        do {
            try paths.ensureDirectories()
            sanitizeExistingLogFile(instanceID: instanceID)
            paths.seedHomeIfNeeded(home)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        } catch {
            state = .failed(DSHError.launchFailed(error.localizedDescription).localizedDescription)
            return false
        }

        let process = Process()
        process.executableURL = node
        process.arguments = [script.path, "--profile", "web", "--no-open", "--port", String(port)]
        process.currentDirectoryURL = paths.versionDirectory(instanceID)
        var environment = DSHExecutables.augmentedEnvironment(node: node)
        environment["DSH_HOME"] = home.path
        environment["NODE_ENV"] = "production"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        self.process = process

        let handle = pipe.fileHandleForReading
        readTask = Task { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    await self?.appendOutput(line, instanceID: instanceID)
                }
            } catch {
                // 进程退出后读取中断属于正常路径
            }
        }

        do {
            try process.run()
        } catch {
            state = .failed(DSHError.launchFailed(error.localizedDescription).localizedDescription)
            return false
        }

        // 等待启动 URL（最多 90 秒）
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if !process.isRunning {
                let tail = logLines.suffix(6).joined(separator: "\n")
                state = .failed(DSHError.processExited(code: process.terminationStatus, tail: tail).localizedDescription)
                readTask?.cancel()
                return false
            }
            if let url = startupURL {
                if let components = URLComponents(string: url), let resolvedPort = components.port {
                    activePort = resolvedPort
                }
                state = .running(url: url)
                if settings.dshAutoOpenBrowser {
                    open(url)
                }
                appendLogFile(Self.sanitizedTokenLine("✓ DSH web 已启动：\(url)"), instanceID: instanceID)
                monitorExit(process, instanceID: instanceID)
                return true
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        appendLogFile("✗ 启动超时，已终止进程", instanceID: instanceID)
        stopProcess()
        state = .failed(DSHError.launchFailed("启动超时（90 秒内没有等到 dsh web 的启动地址）").localizedDescription)
        return false
    }

    private func monitorExit(_ process: Process, instanceID: String) {
        exitMonitor?.cancel()
        exitMonitor = Task { [weak self] in
            while process.isRunning {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
            }
            await MainActor.run {
                guard let self, !self.isStopping, self.state.isRunning else { return }
                let tail = self.logLines.suffix(6).joined(separator: "\n")
                self.state = .failed(
                    DSHError.processExited(code: process.terminationStatus, tail: tail).localizedDescription
                )
                self.appendLogFile("✗ DSH web 已退出（退出码 \(process.terminationStatus)）", instanceID: instanceID)
            }
        }
    }

    // MARK: 停止

    /// 停止 Web UI 进程。
    public func stop() async {
        guard let process, isRunning || state.isBusy else {
            state = .idle
            return
        }
        isStopping = true
        state = .stopping
        appendLogFile("… 正在停止 DSH web", instanceID: activeInstanceID ?? "unknown")
        process.terminate()
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        cleanupAfterStop()
        state = .idle
        isStopping = false
    }

    /// 同步停止（退出 App 时用）。
    public func stopSynchronously() {
        isStopping = true
        stopProcess()
        cleanupAfterStop()
        state = .idle
        isStopping = false
    }

    private func stopProcess() {
        exitMonitor?.cancel()
        readTask?.cancel()
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline {
                usleep(80_000)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        self.process = nil
    }

    private func cleanupAfterStop() {
        exitMonitor?.cancel()
        readTask?.cancel()
        exitMonitor = nil
        readTask = nil
        process = nil
        startupURL = nil
        startedAt = nil
        appendLogFile("✓ DSH web 已停止", instanceID: activeInstanceID ?? "unknown")
    }

    // MARK: 浏览器 / 复制

    /// 用默认浏览器打开带 token 的启动地址。
    public func openWebUI() {
        guard let url = state.url else { return }
        open(url)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    public func copyWebURL() {
        guard let url = state.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    // MARK: 输出

    private func appendOutput(_ line: String, instanceID: String) async {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lineCount += 1
        // token 只保留在内存里的 startupURL；日志（内存 + 文件）一律脱敏
        if startupURL == nil, let range = trimmed.range(of: "dsh web: ") {
            let candidate = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if candidate.hasPrefix("http") { startupURL = candidate }
        }
        let sanitized = Self.sanitizedTokenLine(trimmed)
        logLines.append(sanitized)
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
        appendLogFile(sanitized, instanceID: instanceID)
    }

    /// 把日志行里的 `token=…` 替换成 `token=***`（供日志展示 / 落盘）。
    nonisolated public static func sanitizedTokenLine(_ line: String) -> String {
        guard line.contains("token=") else { return line }
        return line.replacingOccurrences(
            of: #"token=[^&\s"']+"#,
            with: "token=***",
            options: .regularExpression
        )
    }

    private func appendLogFile(_ line: String, instanceID: String) {
        let fileURL = paths.logFile(for: instanceID)
        try? paths.ensureDirectories()
        let timestamp = Self.logDateFormatter.string(from: Date())
        let payload = "[\(timestamp)] \(line)\n"
        guard let data = payload.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
        if lineCount % 50 == 0 {
            trimLogFile(fileURL)
        }
    }

    /// 历史日志里可能残留旧版本写入的 token：启动前先脱敏重写一遍。
    private func sanitizeExistingLogFile(instanceID: String) {
        let url = paths.logFile(for: instanceID)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }
        let text = String(decoding: data, as: UTF8.self)
        guard text.contains("token=") else {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return
        }
        let sanitized = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { Self.sanitizedTokenLine(String($0)) }
            .joined(separator: "\n")
        try? sanitized.data(using: .utf8)?.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func trimLogFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url), data.count > 2_000_000 else { return }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n").suffix(1500).joined(separator: "\n")
        try? lines.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
