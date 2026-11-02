import Foundation

// MARK: - 导出结果

/// 一次日志导出的结果：真实文件路径与字节数。
public struct MoreLogExport: Equatable, Sendable {
    /// 导出的日志文件路径。
    public let url: URL
    /// 文件真实字节数。
    public let byteCount: Int

    public init(url: URL, byteCount: Int) {
        self.url = url
        self.byteCount = byteCount
    }

    /// 人读大小，例如 "12 KB"。
    public var sizeText: String {
        MoreFormatting.byteCountText(byteCount)
    }
}

// MARK: - 日志导出

/// 日志与诊断：拼装真实诊断文本、写到 `~/Library/Logs/BlockLauncher/`，不依赖任何假数据。
public enum MoreLogExporter {
    /// 日志文件夹名（位于 `~/Library/Logs`）。
    public static let folderName = "BlockLauncher"
    /// 诊断文本里附带的最大日志行数（避免复制的诊断信息过长）。
    public static let diagnosticsLogLineLimit = 200

    // MARK: 路径

    /// 日志目录：`~/Library/Logs/BlockLauncher`（读不到 Library 时退回临时目录）。
    public static func logsDirectory() -> URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// 确保日志目录存在并返回。
    @discardableResult
    public static func ensureLogsDirectory() throws -> URL {
        let directory = logsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 日志文件名：`blocklauncher-log-<yyyyMMdd-HHmmss>.log`。
    public static func makeFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "blocklauncher-log-\(formatter.string(from: date)).log"
    }

    // MARK: 文本

    /// 拼装可导出的日志正文（含构建信息、启动命令、退出码与环境摘要）。
    public static func content(
        logs: [String],
        commandLine: String?,
        exitCode: Int32?,
        installedVersionCount: Int,
        javaRuntimeCount: Int,
        gameDirectoryPath: String?,
        buildInfo: LauncherBuildInfo = .current,
        generatedAt: Date = Date(),
        includeLogs: Bool = true
    ) -> String {
        var lines: [String] = [
            "方块启动器日志",
            "版本：\(buildInfo.versionText) · 构建 \(buildInfo.buildNumber) · 提交 \(buildInfo.commit)",
            "导出时间：\(dateTimeText(generatedAt))",
            "启动命令：\(commandLine ?? "（尚未启动过游戏）")",
            "退出码：\(exitCode.map(String.init) ?? "—")",
            "环境：已安装 \(installedVersionCount) 个版本 · 检测到 \(javaRuntimeCount) 个 Java"
        ]
        if let gameDirectoryPath {
            lines.append("游戏目录：\(gameDirectoryPath)")
        }
        lines.append("日志行数：\(logs.count)")
        lines.append(String(repeating: "-", count: 48))
        if includeLogs {
            lines.append(contentsOf: logs)
        }
        return lines.joined(separator: "\n")
    }

    /// 拼装「复制诊断信息」文本：构建信息 + 环境 + 最近日志。
    public static func diagnosticsText(
        logs: [String],
        commandLine: String?,
        exitCode: Int32?,
        installedVersionCount: Int,
        javaRuntimeCount: Int,
        gameDirectoryPath: String?,
        buildInfo: LauncherBuildInfo = .current,
        generatedAt: Date = Date()
    ) -> String {
        content(
            logs: Array(logs.suffix(diagnosticsLogLineLimit)),
            commandLine: commandLine,
            exitCode: exitCode,
            installedVersionCount: installedVersionCount,
            javaRuntimeCount: javaRuntimeCount,
            gameDirectoryPath: gameDirectoryPath,
            buildInfo: buildInfo,
            generatedAt: generatedAt,
            includeLogs: true
        )
    }

    // MARK: 写入

    /// 把日志真实写入日志目录（或指定目录），同名文件自动追加序号。
    @discardableResult
    public static func export(
        logs: [String],
        commandLine: String?,
        exitCode: Int32?,
        installedVersionCount: Int,
        javaRuntimeCount: Int,
        gameDirectoryPath: String?,
        buildInfo: LauncherBuildInfo = .current,
        generatedAt: Date = Date(),
        to directory: URL? = nil
    ) throws -> MoreLogExport {
        let fileManager = FileManager.default
        let targetDirectory = try directory ?? ensureLogsDirectory()
        if !fileManager.fileExists(atPath: targetDirectory.path) {
            try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        }
        let text = content(
            logs: logs,
            commandLine: commandLine,
            exitCode: exitCode,
            installedVersionCount: installedVersionCount,
            javaRuntimeCount: javaRuntimeCount,
            gameDirectoryPath: gameDirectoryPath,
            buildInfo: buildInfo,
            generatedAt: generatedAt
        )
        let data = Data(text.utf8)
        let base = (makeFileName(date: generatedAt) as NSString).deletingPathExtension
        var candidate = targetDirectory.appendingPathComponent("\(base).log")
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = targetDirectory.appendingPathComponent("\(base)-\(counter).log")
            counter += 1
        }
        try data.write(to: candidate, options: .atomic)
        return MoreLogExport(url: candidate, byteCount: data.count)
    }

    // MARK: 大小

    /// 日志总字节数（按 UTF-8 计）。
    public static func totalByteCount(_ lines: [String]) -> Int {
        lines.reduce(0) { $0 + $1.utf8.count + 1 }
    }

    /// 日志规模人读文本，例如 "12 KB"。
    public static func sizeText(_ lines: [String]) -> String {
        MoreFormatting.byteCountText(totalByteCount(lines))
    }

    // MARK: 内部

    private static func dateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
