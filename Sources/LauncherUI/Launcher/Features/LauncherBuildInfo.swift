import Foundation

// MARK: - 构建信息

/// 启动器当前构建的真实信息：版本号（写死）、可执行文件修改时间（构建时间）、
/// 运行环境里能读到的 git 提交。关于页 / 更多页 / 检查更新都读这里，避免各处硬编码不一致。
public struct LauncherBuildInfo: Sendable, Equatable {
    /// 语义版本（与 Package.swift / README 保持一致）。
    public let version: String
    /// 构建时间（可执行文件修改时间，读不到时回退为编译期日期）。
    public let buildDate: Date
    /// git 短提交；从仓库目录启动时能读到，否则为 "—"。
    public let commit: String

    public init(version: String, buildDate: Date, commit: String) {
        self.version = version
        self.buildDate = buildDate
        self.commit = commit
    }

    /// 进程内构建信息（只探测一次）。
    public static let current = LauncherBuildInfo.detect()

    /// "v0.2.0"
    public var versionText: String { "v\(version)" }

    /// "2026.11.01.1380"：年月日 + 当天第几分钟，短且可排序。
    public var buildNumber: String {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: buildDate)
        let year = parts.year ?? 1970
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return String(format: "%04d.%02d.%02d.%04d", year, month, day, minutes)
    }

    /// "2026-11-01"
    public var buildDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: buildDate)
    }

    /// "2026-11-01 18:40"
    public var buildDateTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: buildDate)
    }

    /// 关于页展示用的两行说明。
    public var summary: String {
        "\(versionText) · 构建 \(buildDateText) · 提交 \(commit)"
    }

    // MARK: 探测

    private static func detect() -> LauncherBuildInfo {
        let bundle = Bundle.main
        let version = sanitizeVersion(
            bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        ) ?? Self.fallbackVersion

        let executable = bundle.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        let buildDate = (try? executable.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()

        return LauncherBuildInfo(version: version, buildDate: buildDate, commit: detectCommit(executable: executable))
    }

    /// 兜底版本号：与 README / 包版本一致。
    private static let fallbackVersion = "0.2.0"

    /// 允许 "0.2.0" 这种直接给出的版本；"1" 这类无意义的 bundle 值忽略。
    private static func sanitizeVersion(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains(".") else { return nil }
        return trimmed
    }

    /// 读取 git 短提交：优先环境变量（CI），其次在可执行文件目录 / 当前目录跑 `git rev-parse`。
    private static func detectCommit(executable: URL?) -> String {
        if let injected = ProcessInfo.processInfo.environment["LAUNCHER_BUILD_COMMIT"],
           !injected.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(injected.prefix(12))
        }

        var candidates: [String] = []
        if let executable {
            candidates.append(executable.deletingLastPathComponent().path)
        }
        candidates.append(FileManager.default.currentDirectoryPath)
        candidates.append(Bundle.main.bundlePath)

        for directory in candidates {
            guard let output = runGit(["rev-parse", "--short", "HEAD"], in: directory) else { continue }
            let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hash.isEmpty { return hash }
        }
        return "—"
    }

    private static func runGit(_ arguments: [String], in directory: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
