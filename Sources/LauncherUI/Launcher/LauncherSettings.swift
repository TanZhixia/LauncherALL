import Foundation
import Observation
import SwiftUI

// MARK: - 启动记录

/// 一次真实启动的记录：用于启动页「最近启动」与设置页清理旧版本。
public struct LaunchRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let versionID: String
    public let startedAt: Date
    public var finishedAt: Date?
    public var exitCode: Int32?

    public init(id: UUID = UUID(), versionID: String, startedAt: Date = Date(), finishedAt: Date? = nil, exitCode: Int32? = nil) {
        self.id = id
        self.versionID = versionID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
    }

    /// 运行时长描述；未结束时为 nil。
    public var durationText: String? {
        guard let finishedAt else { return nil }
        let seconds = max(0, Int(finishedAt.timeIntervalSince(startedAt)))
        if seconds < 60 { return "\(seconds) 秒" }
        return "\(seconds / 60) 分 \(seconds % 60) 秒"
    }

    /// 结果描述：未结束 = 运行中；已结束但没有退出码（手动停止 / 启动失败）= 已停止。
    public var resultText: String {
        guard let exitCode else {
            return finishedAt == nil ? "运行中" : "已停止"
        }
        return exitCode == 0 ? "正常退出" : "退出码 \(exitCode)"
    }
}

// MARK: - 持久化设置

/// 启动器设置：真实读写 UserDefaults，重启后保留。
@Observable
public final class LauncherSettings {
    public static let shared = LauncherSettings()

    private let defaults: UserDefaults
    private enum Keys {
        static let gameDirectory = "launcher.settings.gameDirectory"
        static let versionIsolation = "launcher.settings.versionIsolation"
        static let minimizeAfterLaunch = "launcher.settings.minimizeAfterLaunch"
        static let checkUpdatesOnStart = "launcher.settings.checkUpdatesOnStart"
        static let javaRuntimePath = "launcher.settings.javaRuntimePath"
        static let javaAutoDetect = "launcher.settings.javaAutoDetect"
        static let maxMemoryMB = "launcher.settings.maxMemoryMB"
        static let renderThreads = "launcher.settings.renderThreads"
        static let jvmArguments = "launcher.settings.jvmArguments"
        static let updateChannel = "launcher.settings.updateChannel"
        static let language = "launcher.settings.language"
        static let downloadSource = "launcher.settings.downloadSource"
        static let autoCleanOldVersions = "launcher.settings.autoCleanOldVersions"
        static let playerName = "launcher.settings.playerName"
        static let updateFeedURL = "launcher.settings.updateFeedURL"
        static let savedPlayerNames = "launcher.settings.savedPlayerNames"
        static let launchRecords = "launcher.settings.launchRecords"
        static let authAccounts = "launcher.settings.authAccounts"
        static let selectedAuthAccountID = "launcher.settings.selectedAuthAccountID"
        static let dshSelectedVersion = "launcher.settings.dshSelectedVersion"
        static let dshSelectedInstanceID = "launcher.settings.dshSelectedInstanceID"
        static let dshPort = "launcher.settings.dshPort"
        static let dshAutoOpenBrowser = "launcher.settings.dshAutoOpenBrowser"
        static let dshPluginSource = "launcher.settings.dshPluginSource"
        static let dshRegistry = "launcher.settings.dshRegistry"
    }

    /// 最近一次任意设置被写入的时间（保存条 / 自动保存提示用）。
    public private(set) var lastSavedAt: Date?

    /// 游戏目录（真实路径，展开 ~）。
    public var gameDirectory: String { didSet { persist(gameDirectory, Keys.gameDirectory) } }
    public var versionIsolation: Bool { didSet { persist(versionIsolation, Keys.versionIsolation) } }
    public var minimizeAfterLaunch: Bool { didSet { persist(minimizeAfterLaunch, Keys.minimizeAfterLaunch) } }
    public var checkUpdatesOnStart: Bool { didSet { persist(checkUpdatesOnStart, Keys.checkUpdatesOnStart) } }
    /// 手动指定的 Java 路径；空串表示自动检测。
    public var javaRuntimePath: String { didSet { persist(javaRuntimePath, Keys.javaRuntimePath) } }
    public var javaAutoDetect: Bool { didSet { persist(javaAutoDetect, Keys.javaAutoDetect) } }
    public var maxMemoryMB: Int { didSet { persist(maxMemoryMB, Keys.maxMemoryMB) } }
    public var renderThreads: Int { didSet { persist(renderThreads, Keys.renderThreads) } }
    public var jvmArguments: String { didSet { persist(jvmArguments, Keys.jvmArguments) } }
    public var updateChannel: String { didSet { persist(updateChannel, Keys.updateChannel) } }
    public var language: String { didSet { persist(language, Keys.language) } }
    public var downloadSource: String { didSet { persist(downloadSource, Keys.downloadSource) } }
    public var autoCleanOldVersions: Bool { didSet { persist(autoCleanOldVersions, Keys.autoCleanOldVersions) } }
    public var playerName: String { didSet { persist(playerName, Keys.playerName) } }
    /// 更新源 JSON 地址（空串 = 未配置，检查更新给出明确提示）。
    public var updateFeedURL: String { didSet { persist(updateFeedURL, Keys.updateFeedURL) } }
    /// 保存过的离线玩家名（账户切换用）。
    public var savedPlayerNames: [String] { didSet { persist(savedPlayerNames, Keys.savedPlayerNames) } }
    /// 真实启动历史（最多保留 50 条）。
    public var launchRecords: [LaunchRecord] { didSet { persist(records: launchRecords, Keys.launchRecords) } }
    /// 已添加的正版（微软）账户元数据；令牌存在 Keychain，不在这里。
    public var authAccounts: [AuthAccountRecord] { didSet { persist(accounts: authAccounts, Keys.authAccounts) } }
    /// 当前选中的账户 id（`"offline"` 或正版账户的 UUID）。
    public var selectedAuthAccountID: String { didSet { persist(selectedAuthAccountID, Keys.selectedAuthAccountID) } }

    // MARK: DSH（LauncherALL 的第二个启动器）

    /// 旧字段：当前选中的 DSH 版本（仅用于迁移）。
    public var dshSelectedVersion: String { didSet { persist(dshSelectedVersion, Keys.dshSelectedVersion) } }
    /// 当前选中的 DSH 实例 ID；空串表示未选择。
    public var dshSelectedInstanceID: String { didSet { persist(dshSelectedInstanceID, Keys.dshSelectedInstanceID) } }
    /// DSH Web UI 监听端口（0 = 自动挑一个空闲端口）。
    public var dshPort: Int { didSet { persist(dshPort, Keys.dshPort) } }
    /// 启动后自动用默认浏览器打开 DSH Web UI。
    public var dshAutoOpenBrowser: Bool { didSet { persist(dshAutoOpenBrowser, Keys.dshAutoOpenBrowser) } }
    /// 插件加载源（默认使用 dshmarket 的加载源）。
    public var dshPluginSource: String { didSet { persist(dshPluginSource, Keys.dshPluginSource) } }
    /// npm registry（空串 = 官方 registry）。
    public var dshRegistry: String { didSet { persist(dshRegistry, Keys.dshRegistry) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallbackDir = LauncherSettings.defaultGameDirectory
        self.gameDirectory = defaults.string(forKey: Keys.gameDirectory) ?? fallbackDir
        self.versionIsolation = defaults.object(forKey: Keys.versionIsolation) as? Bool ?? true
        self.minimizeAfterLaunch = defaults.object(forKey: Keys.minimizeAfterLaunch) as? Bool ?? true
        self.checkUpdatesOnStart = defaults.object(forKey: Keys.checkUpdatesOnStart) as? Bool ?? true
        self.javaRuntimePath = defaults.string(forKey: Keys.javaRuntimePath) ?? ""
        self.javaAutoDetect = defaults.object(forKey: Keys.javaAutoDetect) as? Bool ?? true
        self.maxMemoryMB = defaults.object(forKey: Keys.maxMemoryMB) as? Int ?? 4096
        self.renderThreads = defaults.object(forKey: Keys.renderThreads) as? Int ?? 4
        self.jvmArguments = defaults.string(forKey: Keys.jvmArguments) ?? ""
        self.updateChannel = defaults.string(forKey: Keys.updateChannel) ?? "release"
        self.language = defaults.string(forKey: Keys.language) ?? "zh-Hans"
        self.downloadSource = defaults.string(forKey: Keys.downloadSource) ?? "official"
        self.autoCleanOldVersions = defaults.object(forKey: Keys.autoCleanOldVersions) as? Bool ?? false
        self.playerName = defaults.string(forKey: Keys.playerName) ?? "Steve"
        self.updateFeedURL = defaults.string(forKey: Keys.updateFeedURL) ?? ""
        self.savedPlayerNames = defaults.stringArray(forKey: Keys.savedPlayerNames) ?? ["Steve"]
        self.launchRecords = LauncherSettings.decodeRecords(defaults.data(forKey: Keys.launchRecords))
        self.authAccounts = LauncherSettings.decodeAccounts(defaults.data(forKey: Keys.authAccounts))
        self.selectedAuthAccountID = defaults.string(forKey: Keys.selectedAuthAccountID) ?? AuthAccountRecord.offlineID
        self.dshSelectedVersion = defaults.string(forKey: Keys.dshSelectedVersion) ?? ""
        self.dshSelectedInstanceID = defaults.string(forKey: Keys.dshSelectedInstanceID) ?? ""
        self.dshPort = defaults.object(forKey: Keys.dshPort) as? Int ?? 3080
        self.dshAutoOpenBrowser = defaults.object(forKey: Keys.dshAutoOpenBrowser) as? Bool ?? true
        self.dshPluginSource = defaults.string(forKey: Keys.dshPluginSource) ?? DSHRegistryClient.defaultPluginSource
        self.dshRegistry = defaults.string(forKey: Keys.dshRegistry) ?? ""
    }

    /// 默认游戏目录：`~/Library/Application Support/minecraft`。
    public static var defaultGameDirectory: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("minecraft", isDirectory: true).path
    }

    /// 展开 `~` 并标准化。
    public var resolvedGameDirectory: URL {
        URL(fileURLWithPath: (gameDirectory as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// 下载源的强类型视图（页面 / 安装器用，避免各处字符串比较）。
    public var downloadSourceValue: DownloadSource {
        DownloadSource(rawValue: downloadSource) ?? .official
    }

    /// JVM 附加参数（按行拆分，忽略空行与注释）。
    public var extraJVMArguments: [String] {
        jvmArguments
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// 恢复全部默认值（启动历史与更新源保留，避免清掉用户数据）。
    public func resetToDefaults() {
        gameDirectory = LauncherSettings.defaultGameDirectory
        versionIsolation = true
        minimizeAfterLaunch = true
        checkUpdatesOnStart = true
        javaRuntimePath = ""
        javaAutoDetect = true
        maxMemoryMB = 4096
        renderThreads = 4
        jvmArguments = ""
        updateChannel = "release"
        language = "zh-Hans"
        downloadSource = "official"
        autoCleanOldVersions = false
        playerName = "Steve"
        savedPlayerNames = ["Steve"]
        // 账户列表属于用户数据，恢复默认时保留，只把当前账户切回离线
        selectedAuthAccountID = AuthAccountRecord.offlineID
    }

    private func persist(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        lastSavedAt = Date()
    }

    /// 编码启动历史（数组不能直接塞给 UserDefaults）。
    private func persist(records: [LaunchRecord], _ key: String) {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: key)
        }
        lastSavedAt = Date()
    }

    private static func decodeRecords(_ data: Data?) -> [LaunchRecord] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([LaunchRecord].self, from: data)) ?? []
    }

    /// 编码正版账户元数据。
    private func persist(accounts: [AuthAccountRecord], _ key: String) {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: key)
        }
        lastSavedAt = Date()
    }

    private static func decodeAccounts(_ data: Data?) -> [AuthAccountRecord] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([AuthAccountRecord].self, from: data)) ?? []
    }
}

// MARK: - 启动历史

public extension LauncherSettings {
    /// 记录一次启动开始，返回记录 id（退出时回填）。
    @discardableResult
    func recordLaunchStart(versionID: String) -> UUID {
        let record = LaunchRecord(versionID: versionID, startedAt: Date())
        var records = launchRecords
        records.insert(record, at: 0)
        if records.count > 50 { records.removeLast(records.count - 50) }
        launchRecords = records
        return record.id
    }

    /// 记录一次启动结束（退出码 / 强制停止）。
    func recordLaunchEnd(id: UUID, exitCode: Int32?) {
        guard let index = launchRecords.firstIndex(where: { $0.id == id }) else { return }
        var records = launchRecords
        records[index].finishedAt = Date()
        records[index].exitCode = exitCode
        launchRecords = records
    }

    /// 最近 N 条启动记录。
    func recentLaunches(limit: Int = 5) -> [LaunchRecord] {
        Array(launchRecords.prefix(limit))
    }

    /// 某个版本最后一次启动时间（清理旧版本用）。
    func lastLaunchDate(for versionID: String) -> Date? {
        launchRecords.first { $0.versionID == versionID }?.startedAt
    }

    /// 最近一次启动的版本 id。
    var lastLaunchedVersionID: String? {
        launchRecords.first?.versionID
    }
}

// MARK: - 账户名

public extension LauncherSettings {
    /// 合法的离线玩家名：1–16 个字符，只允许字母数字与下划线（Minecraft 规则）。
    static func validatePlayerName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "玩家名不能为空" }
        guard trimmed.count <= 16 else { return "玩家名最多 16 个字符" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "玩家名只能包含字母、数字与下划线"
        }
        return nil
    }

    /// 记录一个用过的玩家名（去重、最多 8 个）。
    func rememberPlayerName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Self.validatePlayerName(trimmed) == nil else { return }
        var names = savedPlayerNames.filter { $0 != trimmed }
        names.insert(trimmed, at: 0)
        if names.count > 8 { names.removeLast(names.count - 8) }
        savedPlayerNames = names
    }
}

// MARK: - 版本隔离目录

public extension LauncherSettings {
    /// 某个版本实际使用的游戏目录。
    /// 开启版本隔离时直接用 `versions/<id>`（与 PCL / HMCL 一致，mods / config / saves 都在该目录内），
    /// 关闭时使用根目录。
    func gameDirectory(for versionID: String) -> URL {
        let base = resolvedGameDirectory
        guard versionIsolation else { return base }
        return base
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(versionID, isDirectory: true)
    }
}
