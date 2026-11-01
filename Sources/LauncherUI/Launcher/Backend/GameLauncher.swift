import Foundation

/// 真实启动游戏进程，并把输出按行回调。
public final class GameLauncher: @unchecked Sendable {
    public struct LaunchResult: Sendable {
        public let processIdentifier: Int32
    }

    private var process: Process?
    private var outputPipe: Pipe?

    public init() {}

    public var isRunning: Bool { process?.isRunning ?? false }
    public var processIdentifier: Int32? { process.map { $0.processIdentifier } }

    /// 启动命令；`onLine` 会在后台队列逐行回调 stdout/stderr。
    @discardableResult
    public func launch(
        _ command: LaunchCommand,
        workingDirectory: URL,
        environment: [String: String]? = nil,
        onLine: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> Int32 {
        terminate()

        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.currentDirectoryURL = workingDirectory
        if let environment {
            process.environment = environment
        } else {
            var env = ProcessInfo.processInfo.environment
            env["JAVA_TOOL_OPTIONS"] = nil
            process.environment = env
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = String(line)
                if !trimmed.isEmpty { onLine(trimmed) }
            }
        }

        process.terminationHandler = { finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            onExit(finished.terminationStatus)
        }

        try process.run()
        self.process = process
        self.outputPipe = pipe
        return process.processIdentifier
    }

    public func terminate() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }
}
