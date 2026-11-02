import Foundation

// MARK: - 子进程执行

/// DSH 相关命令的统一执行器：流式读取 stdout/stderr，支持任务取消时终止进程。
public enum DSHCommandRunner {
    /// 执行结果。
    public struct Result: Sendable {
        public let exitCode: Int32
        public let output: String
    }

    /// 执行命令并逐行回调输出（stdout + stderr 合并）。
    public static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let collector = OutputCollector()
        let termination = TerminationSignal()
        process.terminationHandler = { _ in termination.signal() }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try process.run()
            let handle = pipe.fileHandleForReading
            let readTask = Task {
                do {
                    for try await line in handle.bytes.lines {
                        collector.append(line)
                        onLine?(line)
                    }
                } catch {
                    // 进程结束/取消时读取中断是正常现象
                }
            }

            await termination.wait()
            try? await Task.sleep(nanoseconds: 80_000_000)
            readTask.cancel()
            _ = await readTask.value
            return Result(exitCode: process.terminationStatus, output: collector.text)
        } onCancel: {
            if process.isRunning {
                process.terminate()
                // 宽限 2 秒仍不退则强杀
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
    }

    /// 进程结束信号（terminationHandler 可能早于等待注册，需要记住已结束状态）。
    final class TerminationSignal: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private var continuation: CheckedContinuation<Void, Never>?

        func signal() {
            lock.lock()
            finished = true
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume()
        }

        func wait() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                if finished {
                    lock.unlock()
                    continuation.resume()
                } else {
                    self.continuation = continuation
                    lock.unlock()
                }
            }
        }
    }

    /// 输出收集器（行缓冲 + 上限）。
    final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        private let limit = 4000

        func append(_ line: String) {
            lock.lock()
            lines.append(line)
            if lines.count > limit { lines.removeFirst(lines.count - limit) }
            lock.unlock()
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return lines.joined(separator: "\n")
        }
    }
}

// MARK: - 端口

/// 端口工具：检查端口是否可用、挑一个空闲端口。
public enum DSHPortFinder {
    public static func isAvailable(_ port: Int) -> Bool {
        guard port > 0 && port < 65_536 else { return false }
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var value: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                bind(descriptor, addressPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bound == 0
    }

    /// 从 `preferred` 开始找一个可用端口（最多试 30 个）。
    public static func findPort(preferred: Int = 3080) -> Int {
        let base = preferred > 0 ? preferred : 3080
        for offset in 0..<30 where isAvailable(base + offset) {
            return base + offset
        }
        return base
    }
}
