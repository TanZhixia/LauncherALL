import Foundation

// MARK: - 按分类恢复默认

/// 每个设置分类的「恢复默认」映射：只重置本分类的设置项，
/// 其它分类、实例、启动历史与账户数据都保留。
///
/// 单独抽成类型是为了可测试：`SettingsPage` 的「恢复默认」按钮调用 `apply(_:)`，
/// 单元测试可以逐分类断言"只动本页、其它页不变"。
@MainActor
public enum SettingsSectionReset {

    /// 该分类是否有可重置的设置项（日志与诊断没有）。
    public static func hasResettableSettings(_ section: SettingsSection) -> Bool {
        section != .log
    }

    /// 把某个分类的设置项恢复为默认值。
    /// - Parameters:
    ///   - section: 要重置的设置分类。
    ///   - settings: 启动器持久化设置。
    ///   - themeManager: 外观参数（主题 / 边框强度 / 圆角缩放）宿主。
    public static func apply(
        _ section: SettingsSection,
        settings: LauncherSettings,
        themeManager: LauncherThemeManager
    ) {
        switch section {
        case .launch:
            settings.gameDirectory = LauncherSettings.defaultGameDirectory
            settings.versionIsolation = true
            settings.minimizeAfterLaunch = true
            settings.checkUpdatesOnStart = true
        case .java:
            settings.javaAutoDetect = true
            settings.javaRuntimePath = ""
        case .performance:
            settings.maxMemoryMB = 4096
            settings.renderThreads = 4
            settings.jvmArguments = ""
        case .update:
            settings.updateChannel = "release"
            settings.downloadSource = "official"
            settings.autoCleanOldVersions = false
            settings.language = "zh-Hans"
        case .appearance:
            themeManager.select(LauncherThemes.default.id)
            themeManager.borderStrength = 1.0
            themeManager.cornerScale = 1.0
        case .account:
            settings.playerName = "Steve"
            settings.savedPlayerNames = ["Steve"]
            settings.selectedAuthAccountID = AuthAccountRecord.offlineID
        case .about:
            settings.updateFeedURL = ""
        case .log:
            break
        }
    }
}
