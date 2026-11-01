import Foundation
import Observation
import SwiftUI

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
    }

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

    /// JVM 附加参数（按行拆分，忽略空行与注释）。
    public var extraJVMArguments: [String] {
        jvmArguments
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// 恢复全部默认值。
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
    }

    private func persist(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
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
