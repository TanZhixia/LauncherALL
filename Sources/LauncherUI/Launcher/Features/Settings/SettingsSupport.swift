import Foundation
import AppKit

// MARK: - 设置分区

/// 设置页的分组（左侧面板的三段标题）。
public enum SettingsSectionGroup: String, CaseIterable, Sendable {
    case game
    case launcher
    case about
}

/// 设置页的八个分类：左侧面板顺序即 `allCases` 顺序，路由跳转用 `rawValue`。
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case launch
    case java
    case performance
    case update
    case appearance
    case account
    case about
    case log

    public var id: String { rawValue }

    /// 左侧分类行图标（仅 SF Symbols）。
    public var systemImage: String {
        switch self {
        case .launch: return "play.rectangle.fill"
        case .java: return "cup.and.saucer.fill"
        case .performance: return "speedometer"
        case .update: return "arrow.triangle.2.circlepath"
        case .appearance: return "paintpalette.fill"
        case .account: return "person.crop.circle.fill"
        case .about: return "info.circle.fill"
        case .log: return "text.alignleft"
        }
    }

    /// 所属分组。
    public var group: SettingsSectionGroup {
        switch self {
        case .launch, .java, .performance: return .game
        case .update, .appearance, .account: return .launcher
        case .about, .log: return .about
        }
    }

    /// 把路由里传来的字符串解析成分区；无法识别时返回 nil。
    public static func resolve(_ raw: String?) -> SettingsSection? {
        guard let raw else { return nil }
        return SettingsSection(rawValue: raw)
    }
}

// MARK: - 内存方案

/// 最大内存滑杆的取值范围与推荐值：全部按本机真实物理内存计算。
public struct SettingsMemoryPlan: Equatable, Sendable {
    /// 滑杆步长（128 MB）。
    public static let stepMB = 128
    /// 滑杆下限（1 GB）。
    public static let minimumMB = 1024
    /// 滑杆硬上限（32 GB），避免滑杆范围大得没法用。
    public static let hardMaximumMB = 32768
    /// 推荐值上限（8 GB）：再大对 Minecraft 收益很小。
    public static let recommendedCeilingMB = 8192

    /// 本机物理内存字节数（测试可注入）。
    public let physicalMemoryBytes: UInt64
    /// 本机物理内存（MB）。
    public let totalMemoryMB: Int
    /// 滑杆上限：物理内存的 3/4，夹在 [2048, 32768]。
    public let sliderUpperBoundMB: Int
    /// 推荐值：物理内存一半，夹在 [2048, 8192]，且不超过滑杆上限，按 128 MB 对齐。
    public let recommendedMB: Int

    /// 按物理内存字节数生成方案。
    public init(physicalMemoryBytes: UInt64) {
        let totalMB = max(1, Int(physicalMemoryBytes / 1_048_576))
        let upper = max(2048, min(SettingsMemoryPlan.hardMaximumMB, totalMB * 3 / 4))
        var recommended = min(max(totalMB / 2, 2048), min(SettingsMemoryPlan.recommendedCeilingMB, upper))
        recommended = max(SettingsMemoryPlan.minimumMB, recommended / SettingsMemoryPlan.stepMB * SettingsMemoryPlan.stepMB)
        self.physicalMemoryBytes = physicalMemoryBytes
        self.totalMemoryMB = totalMB
        self.sliderUpperBoundMB = upper
        self.recommendedMB = recommended
    }

    /// 当前进程的方案。
    public static var current: SettingsMemoryPlan {
        SettingsMemoryPlan(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
    }

    /// SwiftUI 滑杆用的范围。
    public var sliderRange: ClosedRange<Double> {
        Double(SettingsMemoryPlan.minimumMB)...Double(sliderUpperBoundMB)
    }

    /// 把任意值夹到滑杆范围并按 128 MB 对齐。
    public func snappedMB(_ raw: Double) -> Int {
        let snapped = (raw / Double(SettingsMemoryPlan.stepMB)).rounded() * Double(SettingsMemoryPlan.stepMB)
        return min(max(Int(snapped), SettingsMemoryPlan.minimumMB), sliderUpperBoundMB)
    }

    /// 本机物理内存的展示文本（"16 GB" / "6144 MB"）。
    public var totalMemoryText: String {
        if totalMemoryMB % 1024 == 0 {
            return "\(totalMemoryMB / 1024) GB"
        }
        return "\(totalMemoryMB) MB"
    }

    /// 当前设置值与推荐值/上限的关系，供页面给出真实提示。
    public enum Verdict: Equatable, Sendable {
        /// 低于推荐值
        case belowRecommended
        /// 推荐区间内
        case optimal
        /// 高于推荐值但没超上限
        case aboveRecommended
        /// 超过本机安全上限
        case overLimit
    }

    /// 判定当前内存设置。
    public func verdict(for valueMB: Int) -> Verdict {
        if valueMB > sliderUpperBoundMB { return .overLimit }
        if valueMB < recommendedMB { return .belowRecommended }
        if valueMB > recommendedMB + SettingsMemoryPlan.stepMB * 8 { return .aboveRecommended }
        return .optimal
    }
}

// MARK: - JVM 内存参数

/// JVM 参数里的一个堆内存参数（-Xmx / -Xms）。
public struct SettingsJVMMemoryArgument: Equatable, Sendable {
    /// 原始参数文本，例如 "-Xmx4G"。
    public let raw: String
    /// 折算成 MB 的大小。
    public let megabytes: Int
    /// 是否是最大堆（-Xmx），否则是最小堆（-Xms）。
    public let isMaximum: Bool
}

/// 解析 JVM 附加参数里的 -Xmx / -Xms，并检测与「最大内存」滑杆的冲突。
public enum SettingsJVMArguments {

    /// 从参数列表里解析出所有内存参数（保持原始顺序）。
    public static func memoryArguments(in arguments: [String]) -> [SettingsJVMMemoryArgument] {
        arguments.compactMap { argument in
            let isMaximum: Bool
            let body: Substring
            if argument.hasPrefix("-Xmx") {
                isMaximum = true
                body = argument.dropFirst(4)
            } else if argument.hasPrefix("-Xms") {
                isMaximum = false
                body = argument.dropFirst(4)
            } else {
                return nil
            }
            guard !body.isEmpty else { return nil }
            let suffix = body.last.map { String($0).lowercased() } ?? ""
            let numeric = suffix == "k" || suffix == "m" || suffix == "g"
                ? String(body.dropLast())
                : String(body)
            guard let value = Int(numeric), value > 0 else { return nil }
            let megabytes: Int
            switch suffix {
            case "k": megabytes = value / 1024
            case "g": megabytes = value * 1024
            default: megabytes = value
            }
            return SettingsJVMMemoryArgument(raw: argument, megabytes: max(1, megabytes), isMaximum: isMaximum)
        }
    }

    /// 第一个与「最大内存」设置冲突的 -Xmx（启动命令里附加参数排在设置值之后，会覆盖设置）。
    public static func conflictingMaximum(
        arguments: [String],
        memoryMB: Int
    ) -> SettingsJVMMemoryArgument? {
        memoryArguments(in: arguments).first { argument in
            guard argument.isMaximum else { return false }
            return argument.megabytes != memoryMB
        }
    }
}

// MARK: - 玩家名

/// 玩家名不合法的原因分类（合法性仍由 `LauncherSettings.validatePlayerName` 判定，这里只做归类便于本地化）。
public enum SettingsPlayerNameIssue: String, Equatable, Sendable {
    case empty
    case tooLong
    case invalidCharacters
}

/// 玩家名校验与归一化。
public enum SettingsPlayerName {
    /// 返回不合格原因；合格返回 nil。
    public static func issue(for raw: String) -> SettingsPlayerNameIssue? {
        guard LauncherSettings.validatePlayerName(raw) != nil else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.count > 16 { return .tooLong }
        return .invalidCharacters
    }

    /// 合法时返回去掉首尾空白的名字，否则 nil。
    public static func normalized(_ raw: String) -> String? {
        guard issue(for: raw) == nil else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Java 路径校验

/// 手动 Java 路径校验失败的原因。
public enum SettingsJavaValidationFailure: Equatable, Sendable {
    /// 文件不存在
    case missing(String)
    /// 文件存在但不可执行
    case notExecutable(String)
    /// 可执行但 `java -version` 无法解析
    case probeFailed(String, detail: String)
}

/// 手动 Java 路径的校验结果。
public enum SettingsJavaValidation: Equatable, Sendable {
    /// 留空：回退到自动检测
    case empty
    case valid(JavaRuntime)
    case invalid(SettingsJavaValidationFailure)
}

/// 真实校验用户填写的 java 可执行文件（存在 → 可执行 → `java -version` 可解析）。
public enum SettingsJavaProbe {
    /// 同步校验；`runner` 可注入以便测试，默认真实执行 `java -version`。
    public static func validate(
        path raw: String,
        runner: (String, [String]) -> String? = { path, arguments in
            try? JavaLocator.runCommand(path, arguments: arguments)
        }
    ) -> SettingsJavaValidation {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let path = (trimmed as NSString).expandingTildeInPath
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            return .invalid(.missing(path))
        }
        guard fileManager.isExecutableFile(atPath: path) else {
            return .invalid(.notExecutable(path))
        }
        guard let output = runner(path, ["-version"]) else {
            return .invalid(.probeFailed(path, detail: "无法执行 java -version"))
        }
        guard let runtime = JavaLocator.parseVersionOutput(output, executable: URL(fileURLWithPath: path)) else {
            return .invalid(.probeFailed(path, detail: output.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .valid(runtime)
    }

    /// 异步版本：把可能阻塞的 `java -version` 放到后台线程。
    public static func validateAsync(_ raw: String) async -> SettingsJavaValidation {
        await Task.detached(priority: .userInitiated) { validate(path: raw) }.value
    }

    /// 运行时是否满足某个主版本要求（nil 表示无要求）。
    public static func satisfies(_ runtime: JavaRuntime, requiredMajor: Int?) -> Bool {
        guard let requiredMajor else { return true }
        return runtime.majorVersion >= requiredMajor
    }
}

// MARK: - 旧版本清理

/// 可清理旧版本的一行：版本 id + 真实占用字节数 + 上次启动时间。
public struct SettingsCleanupRow: Identifiable, Equatable, Sendable {
    public let versionID: String
    public let sizeBytes: Int64
    public let lastUsedAt: Date?
    /// 版本 JSON 的最后修改时间（没有启动记录时的判龄依据）。
    public let modifiedAt: Date

    public var id: String { versionID }

    public init(versionID: String, sizeBytes: Int64, lastUsedAt: Date?, modifiedAt: Date) {
        self.versionID = versionID
        self.sizeBytes = sizeBytes
        self.lastUsedAt = lastUsedAt
        self.modifiedAt = modifiedAt
    }

    /// 占用大小的可读文本。
    public var sizeText: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

/// 把「未使用的版本」整理成页面可直接展示的行（大小与时间都来自真实数据）。
public enum SettingsCleanupPlanner {
    /// 默认判定天数（与引擎 `unusedVersions(olderThanDays:)` 一致）。
    public static let defaultDays = 30

    /// 生成清理列表。
    public static func rows(
        versions: [InstalledVersion],
        lastLaunch: (String) -> Date?,
        sizeProvider: (String) -> Int64
    ) -> [SettingsCleanupRow] {
        versions.map { version in
            SettingsCleanupRow(
                versionID: version.id,
                sizeBytes: sizeProvider(version.id),
                lastUsedAt: lastLaunch(version.id),
                modifiedAt: version.lastModified
            )
        }
    }

    /// 合计占用文本。
    public static func totalSizeText(_ rows: [SettingsCleanupRow]) -> String {
        ByteCountFormatter.string(fromByteCount: rows.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file)
    }
}

// MARK: - 日志导出

/// 日志导出文件头部的字段名（跟随界面语言）。
public struct SettingsLogExportLabels: Sendable, Equatable {
    public let title: String
    public let version: String
    public let generated: String
    public let command: String
    public let exitCode: String
    public let lineCount: String

    public init(
        title: String,
        version: String,
        generated: String,
        command: String,
        exitCode: String,
        lineCount: String
    ) {
        self.title = title
        self.version = version
        self.generated = generated
        self.command = command
        self.exitCode = exitCode
        self.lineCount = lineCount
    }

    /// 默认（中文）字段名。
    public static let chinese = SettingsLogExportLabels(
        title: "方块启动器日志",
        version: "启动器版本",
        generated: "导出时间",
        command: "启动命令",
        exitCode: "退出码",
        lineCount: "日志行数"
    )
}

/// 一次日志导出的结果。
public struct SettingsLogExport: Equatable, Sendable {
    public let url: URL
    public let lineCount: Int
    public let byteCount: Int
}

/// 日志导出失败原因。
public enum SettingsLogExportError: LocalizedError {
    case emptyLog
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyLog: return "当前没有日志可导出"
        case .writeFailed(let message): return message
        }
    }
}

/// 真实把日志写成文件：与「更多 → 日志与诊断」统一落到 `~/Library/Logs/BlockLauncher/`。
public enum SettingsLogExporter {

    /// 日志目录名（与更多页 `MoreLogExporter` 保持一致）。
    public static let folderName = "BlockLauncher"

    /// 生成导出内容（头部含版本 / 启动命令 / 退出码 / 行数）。
    public static func content(
        lines: [String],
        buildInfo: LauncherBuildInfo,
        commandLine: String?,
        exitCode: Int32?,
        labels: SettingsLogExportLabels = .chinese,
        generatedAt: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let headerLines: [String] = [
            labels.title,
            "\(labels.version)：\(buildInfo.summary)",
            "\(labels.generated)：\(formatter.string(from: generatedAt))",
            "\(labels.command)：\(commandLine ?? "—")",
            "\(labels.exitCode)：\(exitCode.map(String.init) ?? "—")",
            "\(labels.lineCount)：\(lines.count)",
            ""
        ]
        return (headerLines + lines).joined(separator: "\n")
    }

    /// 默认导出目录：`~/Library/Logs/BlockLauncher`（与更多页一致，读不到 Library 时退回临时目录）。
    public static func logsDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// 导出文件名（带时间戳；与更多页 `MoreLogExporter.makeFileName` 完全一致）。
    public static func fileName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "blocklauncher-log-\(formatter.string(from: date)).log"
    }

    /// 真实写文件；空日志抛 `emptyLog`，目录不存在时自动创建，同名文件追加序号避免覆盖。
    public static func export(
        lines: [String],
        buildInfo: LauncherBuildInfo,
        commandLine: String?,
        exitCode: Int32?,
        labels: SettingsLogExportLabels = .chinese,
        directory: URL? = nil,
        now: Date = Date()
    ) throws -> SettingsLogExport {
        guard !lines.isEmpty else { throw SettingsLogExportError.emptyLog }
        let fileManager = FileManager.default
        let targetDirectory = directory ?? logsDirectory()
        let text = content(
            lines: lines,
            buildInfo: buildInfo,
            commandLine: commandLine,
            exitCode: exitCode,
            labels: labels,
            generatedAt: now
        )
        do {
            if !fileManager.fileExists(atPath: targetDirectory.path) {
                try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            }
            let base = (fileName(at: now) as NSString).deletingPathExtension
            var url = targetDirectory.appendingPathComponent("\(base).log")
            var counter = 2
            while fileManager.fileExists(atPath: url.path) {
                url = targetDirectory.appendingPathComponent("\(base)-\(counter).log")
                counter += 1
            }
            try text.write(to: url, atomically: true, encoding: .utf8)
            return SettingsLogExport(url: url, lineCount: lines.count, byteCount: text.utf8.count)
        } catch {
            throw SettingsLogExportError.writeFailed(error.localizedDescription)
        }
    }
}

// MARK: - 界面语言

/// 界面语言选项。
public enum SettingsLanguage: String, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"

    public var id: String { rawValue }

    /// 语言的自称（语言菜单与状态里显示）。
    public var nativeName: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        case .japanese: return "日本語"
        }
    }

    /// 系统语言偏好里的匹配标记（用于显示"当前系统语言"）。
    public var systemCode: String {
        switch self {
        case .simplifiedChinese: return "zh"
        case .english: return "en"
        case .japanese: return "ja"
        }
    }

    /// 把设置里的字符串解析成语言（未知值回退简体中文）。
    public static func resolve(_ raw: String) -> SettingsLanguage {
        SettingsLanguage(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .simplifiedChinese
    }
}

/// 语言生效状态与真实重启。
public enum SettingsAppRestart {

    /// 本进程启动时生效的语言（进程内只读快照；重启后新进程会读到新的设置值）。
    public static let launchedLanguage: SettingsLanguage = {
        SettingsLanguage.resolve(LauncherSettings.shared.language)
    }()

    /// 选择值是否需要重启才能生效。
    public static func needsRestart(selected: SettingsLanguage, applied: SettingsLanguage) -> Bool {
        selected != applied
    }

    /// 真实重启：用当前可执行文件拉起新进程，成功后再退出当前进程。
    /// - Returns: 是否成功拉起新进程（失败时当前进程保持运行，由页面提示错误）。
    @MainActor
    @discardableResult
    public static func relaunch() -> Bool {
        guard let executable = currentExecutableURL else { return false }
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.arguments = []
        do {
            try process.run()
        } catch {
            return false
        }
        NSApp.terminate(nil)
        return true
    }

    /// 当前进程的可执行文件：优先 Bundle，其次第一个启动参数。
    public static var currentExecutableURL: URL? {
        if let url = Bundle.main.executableURL,
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        guard let first = CommandLine.arguments.first, !first.isEmpty else { return nil }
        let url = URL(fileURLWithPath: first)
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }
}

// MARK: - 持久化

/// 设置持久化的真实动作（保存按钮用）。
public enum SettingsPersistence {
    /// 立即把偏好写入磁盘。
    @discardableResult
    public static func flush() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }
}
