import Foundation

// MARK: - 设置页文案键

/// 设置页所有可见文案的键：三种语言共用同一套键，缺失由中文兜底（测试会校验）。
public enum SettingsTextKey: String, CaseIterable, Sendable {
    // 页面骨架
    case pageTitle
    case groupGame
    case groupLauncher
    case groupAbout
    case sectionLaunch
    case sectionJava
    case sectionPerformance
    case sectionUpdate
    case sectionAppearance
    case sectionAccount
    case sectionAbout
    case sectionLog
    case subtitleLaunch
    case subtitleJava
    case subtitlePerformance
    case subtitleUpdate
    case subtitleAppearance
    case subtitleAccount
    case subtitleAbout
    case subtitleLog
    case autoSave
    case badgeJavaNone
    case badgeJavaCount
    case badgeOffline
    case saveBarSavedAt
    case saveBarNever
    case saveButton
    case resetButton
    case savedToast
    case saveNoChanges
    case resetToast
    case resetDialogTitle
    case resetDialogMessage
    case resetSectionTitle
    case resetSectionMessage
    case resetSectionToast
    case resetSectionNoop
    case resetDialogConfirm

    // 启动
    case gameDirTitle
    case gameDirSubtitle
    case gameDirTooltip
    case gameDirPlaceholder
    case gameDirSetToast
    case browse
    case openInFinder
    case openGameDirToast
    case pickGameDirMessage
    case gameDirMissingToast
    case isolationTitle
    case isolationSubtitle
    case isolationTooltip
    case previewTitle
    case previewSubtitle
    case previewNoVersion
    case previewIsolated
    case previewShared
    case minimizeTitle
    case minimizeSubtitle
    case checkUpdatesOnStartTitle
    case checkUpdatesOnStartSubtitle

    // Java
    case javaAutoTitle
    case javaAutoSubtitle
    case javaAutoTooltip
    case javaRuntimeTitle
    case javaRuntimeEmpty
    case javaRuntimeCount
    case javaRuntimeTooltipEmpty
    case javaDetectNow
    case javaRedetect
    case javaRedetectSubtitle
    case javaManualTitle
    case javaManualSubtitleAuto
    case javaManualSubtitleManual
    case javaManualTooltip
    case javaPathPlaceholder
    case javaValidate
    case javaValidating
    case javaPathValid
    case javaIssueMissing
    case javaIssueNotExecutable
    case javaIssueProbeFailed
    case javaRequiredTitle
    case javaRequiredValue
    case javaRequiredNone
    case javaRequiredBadge
    case javaUsing
    case javaRequiredTooltip
    case javaListTitle
    case javaListSubtitle
    case javaOpenDirectory
    case javaOpenDirectoryToast
    case javaNoDirectoryToast
    case javaBadgeSatisfied
    case javaBadgeLow
    case javaBadgeInUse
    case javaAutoLabel
    case javaAutoDetail
    case javaRefreshToast
    case javaListEmpty
    case javaMenuGroup

    // 性能
    case memoryTitle
    case memoryTooltip
    case memorySubtitleOptimal
    case memorySubtitleBelow
    case memorySubtitleAbove
    case memorySubtitleOver
    case memoryApplyRecommended
    case memoryLimitBadge
    case memoryAppliedToast
    case jvmConflictTitle
    case jvmConflictMessage
    case jvmConflictHint
    case advancedTitle
    case advancedSubtitle
    case renderThreadsTitle
    case renderThreadsSubtitle
    case renderThreadsTooltip
    case renderThreadsHint
    case renderThreadsUnit
    case jvmArgsTitle
    case jvmArgsSubtitle
    case jvmArgsCount
    case jvmArgsTooltip
    case jvmArgsPlaceholder

    // 更新与语言
    case channelTitle
    case channelSubtitle
    case channelTooltip
    case channelGroup
    case channelRelease
    case channelSnapshot
    case channelPreview
    case channelReleaseDetail
    case channelSnapshotDetail
    case channelPreviewDetail
    case sourceTitle
    case sourceSubtitle
    case sourceTooltip
    case sourceOfficial
    case sourceMirror
    case sourceOfficialDetail
    case sourceMirrorDetail
    case autoCleanTitle
    case autoCleanSubtitle
    case cleanupTitle
    case cleanupSubtitle
    case cleanupScan
    case cleanupScanning
    case cleanupNotScanned
    case cleanupEmpty
    case cleanupLastUsed
    case cleanupNeverUsed
    /// 没有启动记录时展示版本文件的最后修改时间
    case cleanupFileModified
    case cleanupDelete
    case cleanupDeleteAll
    case cleanupTotal
    case cleanupDialogTitle
    case cleanupDialogMessage
    case cleanupDialogConfirm
    case cleanupToast
    case cleanupFailed
    case languageTitle
    case languageSubtitle
    case languageTooltip
    case languageMenuGroup
    case languageApplied
    case languageAppliedBadge
    case languagePendingBadge
    case languageBannerTitle
    case languageBannerMessage
    case languageRestart
    case languageRestartFailed

    // 外观
    case themeTitle
    case themeSubtitle
    case themeTooltip
    case themeGroup
    case borderTitle
    case borderSubtitle
    case borderTooltip
    case cornerTitle
    case cornerSubtitle
    case cornerTooltip
    case compareTitle
    case compareHint
    case compareCurrent
    case compareDefault
    case compareBadge
    case compareButton
    case compareButtonHint
    case comparePlaceholder

    // 账户
    case premiumTitle
    case premiumSubtitle
    case premiumAdd
    case premiumEmpty
    case premiumBadge
    case premiumCurrent
    case premiumSwitch
    case premiumRefresh
    case premiumLogout
    case premiumLogoutTitle
    case premiumLogoutMessage
    case premiumLogoutConfirm
    case premiumOfflineNote
    case currentAccountTitle
    case currentAccountSubtitle
    case playerNameTitle
    case playerNameSubtitle
    case playerNameTooltip
    case playerNamePlaceholder
    case playerNameApply
    case playerNameReset
    case playerNameAppliedToast
    case playerNameEmpty
    case playerNameTooLong
    case playerNameInvalidChars
    case savedNamesTitle
    case savedNamesSubtitle
    case savedNamesEmpty
    case savedNamesCount
    case savedNameSwitchedToast
    case savedNameRemove
    case savedNameRemovedToast
    case uuidTitle
    case uuidSubtitle
    case uuidTooltip
    case uuidCopy
    case uuidCopiedToast

    // 关于
    case versionTitle
    case versionSubtitle
    case buildTitle
    case commitTitle
    case buildDetailsTitle
    case buildDateLabel
    case buildChannelLabel
    case updateSourceTitle
    case updateSourceSubtitleEmpty
    case updateSourceSubtitleConfigured
    case updateSourcePlaceholder
    case updateSourceTooltip
    case updateCheck
    case updateChecking
    case updateIdle
    case updateIdleBadge
    case updateCheckingBadge
    case updateUpToDateBadge
    case updateNoFeedBadge
    case updateFailedBadge
    case updateUpToDate
    case updateAvailable
    case updateNoFeed
    case updateFailed
    case updateLastChecked
    case updateDownload
    case updateDownloadFailed

    // 日志
    case logTitle
    case logSubtitle
    case logTooltip
    case logLinesBadge
    case logExitCode
    case logExitNone
    case logCopyRecent
    case logExport
    case logExportTooltip
    case logOpenMore
    case logClear
    case logEmpty
    case logCopiedToast
    case logExportedToast
    case logExportFailedToast
    case logClearedToast
    case logClearDialogTitle
    case logClearDialogMessage
    case logClearDialogConfirm
    case logReveal
    case logExportLabelsTitle
    case logExportLabelsVersion
    case logExportLabelsGenerated
    case logExportLabelsCommand
    case logExportLabelsExitCode
    case logExportLabelsLineCount
}

// MARK: - 设置页文案

/// 设置页文案表：`settings.language` 决定当前语言，设置页内即时切换。
public struct SettingsStrings: Sendable {
    /// 当前语言。
    public let language: SettingsLanguage
    private let table: [SettingsTextKey: String]

    /// 按语言创建文案表（缺失键回退简体中文）。
    public init(language: SettingsLanguage) {
        self.language = language
        self.table = SettingsStrings.table(for: language)
    }

    /// 取文案。
    public subscript(_ key: SettingsTextKey) -> String {
        table[key] ?? SettingsStrings.chineseTable[key] ?? key.rawValue
    }

    /// 带占位符的文案（%d / %@）。
    public func format(_ key: SettingsTextKey, _ arguments: CVarArg...) -> String {
        String(format: self[key], arguments: arguments)
    }

    /// 分组标题。
    public func groupTitle(_ group: SettingsSectionGroup) -> String {
        switch group {
        case .game: return self[.groupGame]
        case .launcher: return self[.groupLauncher]
        case .about: return self[.groupAbout]
        }
    }

    /// 分区标题。
    public func sectionTitle(_ section: SettingsSection) -> String {
        switch section {
        case .launch: return self[.sectionLaunch]
        case .java: return self[.sectionJava]
        case .performance: return self[.sectionPerformance]
        case .update: return self[.sectionUpdate]
        case .appearance: return self[.sectionAppearance]
        case .account: return self[.sectionAccount]
        case .about: return self[.sectionAbout]
        case .log: return self[.sectionLog]
        }
    }

    /// 分区说明。
    public func sectionSubtitle(_ section: SettingsSection) -> String {
        switch section {
        case .launch: return self[.subtitleLaunch]
        case .java: return self[.subtitleJava]
        case .performance: return self[.subtitlePerformance]
        case .update: return self[.subtitleUpdate]
        case .appearance: return self[.subtitleAppearance]
        case .account: return self[.subtitleAccount]
        case .about: return self[.subtitleAbout]
        case .log: return self[.subtitleLog]
        }
    }

    /// 日志导出文件头使用的字段名。
    public var logExportLabels: SettingsLogExportLabels {
        SettingsLogExportLabels(
            title: self[.logExportLabelsTitle],
            version: self[.logExportLabelsVersion],
            generated: self[.logExportLabelsGenerated],
            command: self[.logExportLabelsCommand],
            exitCode: self[.logExportLabelsExitCode],
            lineCount: self[.logExportLabelsLineCount]
        )
    }

    /// 当前语言缺失的键（正常为空，供测试校验翻译完整度）。
    public func missingKeys() -> [SettingsTextKey] {
        SettingsTextKey.allCases.filter { table[$0] == nil }
    }

    /// 某语言的全部文案。
    public static func table(for language: SettingsLanguage) -> [SettingsTextKey: String] {
        switch language {
        case .simplifiedChinese: return chineseTable
        case .english: return englishTable
        case .japanese: return japaneseTable
        }
    }

    // MARK: 简体中文

    /// 简体中文文案。
    static let chineseTable: [SettingsTextKey: String] = [
        .pageTitle: "设置",
        .groupGame: "游戏",
        .groupLauncher: "启动器",
        .groupAbout: "关于",
        .sectionLaunch: "启动",
        .sectionJava: "Java 运行时",
        .sectionPerformance: "性能",
        .sectionUpdate: "更新与语言",
        .sectionAppearance: "外观",
        .sectionAccount: "账户",
        .sectionAbout: "关于",
        .sectionLog: "日志与诊断",
        .subtitleLaunch: "游戏目录与启动时的默认行为",
        .subtitleJava: "检测本机 JDK，按游戏版本要求选择",
        .subtitlePerformance: "内存与 JVM 参数，修改后下次启动生效",
        .subtitleUpdate: "更新通道、下载来源与界面语言",
        .subtitleAppearance: "主题与全局外观参数，修改立即生效",
        .subtitleAccount: "离线账户的玩家名会写入启动命令",
        .subtitleAbout: "版本信息、更新检查与反馈入口",
        .subtitleLog: "启动日志与崩溃诊断集中管理",
        .autoSave: "自动保存",
        .badgeJavaNone: "未检测到",
        .badgeJavaCount: "%d 个",
        .badgeOffline: "离线账户",
        .saveBarSavedAt: "已保存于 %@",
        .saveBarNever: "本次运行尚未写入设置",
        .saveButton: "保存设置",
        .resetButton: "恢复默认",
        .savedToast: "所有修改已写入磁盘",
        .saveNoChanges: "没有新的修改需要保存",
        .resetToast: "已恢复默认设置",
        .resetDialogTitle: "恢复默认设置？",
        .resetDialogMessage: "将把游戏目录、Java、内存、JVM 参数、语言等全部恢复为默认值；启动历史与更新源会保留。",
        .resetSectionTitle: "恢复「%@」的默认设置？",
        .resetSectionMessage: "只会重置本页的设置项；其它页面、实例与账户数据都会保留。",
        .resetSectionToast: "已恢复「%@」的默认设置",
        .resetSectionNoop: "本页没有可重置的设置",
        .resetDialogConfirm: "恢复",

        .gameDirTitle: "游戏目录",
        .gameDirSubtitle: "versions / mods / saves 的根目录",
        .gameDirTooltip: "启动器会在此目录读写游戏文件；修改后立即生效",
        .gameDirPlaceholder: "游戏目录",
        .gameDirSetToast: "游戏目录已更新：%@",
        .browse: "浏览…",
        .openInFinder: "在访达中打开",
        .openGameDirToast: "已在访达中打开游戏目录",
        .pickGameDirMessage: "选择 Minecraft 游戏目录",
        .gameDirMissingToast: "目录不存在：%@",
        .isolationTitle: "版本隔离",
        .isolationSubtitle: "每个游戏版本使用独立的 mods 与配置目录",
        .isolationTooltip: "关闭后所有版本共用同一个 mods 目录",
        .previewTitle: "隔离目录预览",
        .previewSubtitle: "当前设置下该版本实际使用的目录",
        .previewNoVersion: "还没有安装任何版本，安装后这里显示真实目录",
        .previewIsolated: "已开启：versions/<版本 id>",
        .previewShared: "已关闭：直接使用游戏根目录",
        .minimizeTitle: "启动后最小化",
        .minimizeSubtitle: "进入游戏后把启动器窗口收进 Dock",
        .checkUpdatesOnStartTitle: "启动前检查更新",
        .checkUpdatesOnStartSubtitle: "启动时向更新源发一次真实请求，发现新版本会提示",

        .javaAutoTitle: "自动选择",
        .javaAutoSubtitle: "按游戏版本要求自动挑选 Java；关闭后使用下方指定的路径",
        .javaAutoTooltip: "启动时会从检测到的运行时中挑出满足版本要求的最高版本",
        .javaRuntimeTitle: "Java 运行时",
        .javaRuntimeEmpty: "未检测到 Java，安装 JDK 后点「重新检测」",
        .javaRuntimeCount: "检测到 %d 个运行时 · 点开可直接指定",
        .javaRuntimeTooltipEmpty: "未找到可执行的 java；可安装 Temurin 21 或在下方手动填写路径",
        .javaDetectNow: "立即检测",
        .javaRedetect: "重新检测",
        .javaRedetectSubtitle: "扫描 /Library/Java/JavaVirtualMachines、Homebrew 与 JAVA_HOME",
        .javaManualTitle: "自定义路径",
        .javaManualSubtitleAuto: "自动选择开启时此项不生效",
        .javaManualSubtitleManual: "手动指定 java 可执行文件（留空则回退到自动检测）",
        .javaManualTooltip: "例如 /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java",
        .javaPathPlaceholder: "java 可执行文件路径",
        .javaValidate: "校验",
        .javaValidating: "校验中…",
        .javaPathValid: "路径有效：Java %d（%@）",
        .javaIssueMissing: "文件不存在：%@",
        .javaIssueNotExecutable: "文件不可执行：%@",
        .javaIssueProbeFailed: "无法执行 java -version：%@",
        .javaRequiredTitle: "当前版本要求",
        .javaRequiredValue: "需要 Java %d 及以上",
        .javaRequiredNone: "当前没有选中的游戏版本",
        .javaRequiredBadge: "Java %d+",
        .javaUsing: "将使用：%@",
        .javaRequiredTooltip: "由本地版本 JSON 的 javaVersion 字段决定（含 inheritsFrom 回退）",
        .javaListTitle: "检测到的运行时",
        .javaListSubtitle: "展开查看每个运行时的版本、厂商与路径",
        .javaOpenDirectory: "打开 Java 目录",
        .javaOpenDirectoryToast: "已在访达中打开 %@",
        .javaNoDirectoryToast: "找不到可打开的 Java 目录",
        .javaBadgeSatisfied: "满足要求",
        .javaBadgeLow: "版本偏低",
        .javaBadgeInUse: "当前使用",
        .javaAutoLabel: "自动检测",
        .javaAutoDetail: "按版本要求自动挑选",
        .javaRefreshToast: "已重新检测 Java 运行时",
        .javaListEmpty: "未检测到任何 Java 运行时",
        .javaMenuGroup: "运行时",

        .memoryTitle: "最大内存",
        .memoryTooltip: "分配给游戏 JVM 的最大堆内存，过大反而会拖慢系统",
        .memorySubtitleOptimal: "推荐 %d MB（本机 %@ 内存）",
        .memorySubtitleBelow: "低于推荐值 %d MB，整合包可能频繁卡顿",
        .memorySubtitleAbove: "超过推荐值 %d MB，收益有限且会挤占系统内存",
        .memorySubtitleOver: "超过本机安全上限 %d MB，可能拖慢系统",
        .memoryApplyRecommended: "应用推荐值",
        .memoryLimitBadge: "本机 %@ · 上限 %d MB",
        .memoryAppliedToast: "最大内存已设为推荐值 %d MB",
        .jvmConflictTitle: "JVM 参数冲突",
        .jvmConflictMessage: "附加参数 %@ 会覆盖「最大内存 %d MB」，游戏实际堆上限为 %d MB",
        .jvmConflictHint: "建议删除该参数，或改用上方滑杆统一设置",
        .advancedTitle: "高级启动选项",
        .advancedSubtitle: "渲染线程与 JVM 参数，非必要无需修改",
        .renderThreadsTitle: "渲染线程",
        .renderThreadsSubtitle: "建议 2 ~ 4 个，数量过多反而增加调度开销",
        .renderThreadsTooltip: "对应 JVM 的 -XX:ActiveProcessorCount 参数",
        .renderThreadsHint: "本机 %d 核 CPU，建议 %d 个线程",
        .renderThreadsUnit: "线程",
        .jvmArgsTitle: "JVM 参数",
        .jvmArgsSubtitle: "每行一个参数，以 # 开头为注释；留空使用默认参数",
        .jvmArgsCount: "%d 个参数",
        .jvmArgsTooltip: "已解析 %d 个有效参数",
        .jvmArgsPlaceholder: "每行一个 JVM 参数，例如 -XX:+UseG1GC",

        .channelTitle: "更新通道",
        .channelSubtitle: "仅记录偏好：当前更新源不支持通道，检查更新结果与通道无关",
        .channelTooltip: "通道只写入设置；UpdateChecker 始终检查更新源里的版本，不会因通道改变检查结果",
        .channelGroup: "更新通道",
        .channelRelease: "正式版",
        .channelSnapshot: "快照",
        .channelPreview: "预览",
        .channelReleaseDetail: "偏好：希望只接收稳定版本（当前更新源未提供通道区分）",
        .channelSnapshotDetail: "偏好：愿意接收未完成的实验性内容（当前更新源未提供通道区分）",
        .channelPreviewDetail: "偏好：愿意接收最新构建（当前更新源未提供通道区分）",
        .sourceTitle: "下载源",
        .sourceSubtitle: "安装游戏与资源时使用",
        .sourceTooltip: "官方源直连 Mojang；镜像源把 Mojang 域名重写到 BMCLAPI",
        .sourceOfficial: "官方源（Mojang）",
        .sourceMirror: "镜像源（BMCLAPI 加速）",
        .sourceOfficialDetail: "直连 Mojang，最稳妥，国内可能较慢",
        .sourceMirrorDetail: "把 Mojang 下载域名重写到 BMCLAPI，国内通常更快",
        .autoCleanTitle: "安装后提示可清理的旧版本",
        .autoCleanSubtitle: "安装完成后检查 30 天未启动的版本并给出提示，不会自动删除",
        .cleanupTitle: "可清理的旧版本",
        .cleanupSubtitle: "展开后可扫描并删除未使用的版本",
        .cleanupScan: "扫描",
        .cleanupScanning: "扫描中…",
        .cleanupNotScanned: "点「扫描」列出 %d 天未启动的版本",
        .cleanupEmpty: "没有 %d 天以上未启动的版本",
        .cleanupLastUsed: "上次启动：%@",
        .cleanupNeverUsed: "从未通过本启动器启动",
        .cleanupFileModified: "最后修改：%@",
        .cleanupDelete: "删除",
        .cleanupDeleteAll: "全部清理",
        .cleanupTotal: "共 %d 个 · 约 %@",
        .cleanupDialogTitle: "清理旧版本？",
        .cleanupDialogMessage: "将把 %d 个版本（约 %@）删除到废纸篓，可从废纸篓恢复。",
        .cleanupDialogConfirm: "清理",
        .cleanupToast: "已清理 %d 个旧版本（可在废纸篓恢复）",
        .cleanupFailed: "%@ 清理失败：%@",
        .languageTitle: "界面语言",
        .languageSubtitle: "切换后设置页立即生效；其余页面暂未本地化，仍显示中文",
        .languageTooltip: "语言写入设置；目前只有设置页使用所选语言，重启后设置页仍以该语言启动",
        .languageMenuGroup: "界面语言",
        .languageApplied: "当前语言环境：%@",
        .languageAppliedBadge: "已生效",
        .languagePendingBadge: "重启后本页生效",
        .languageBannerTitle: "设置页已切换为 %@",
        .languageBannerMessage: "启动、下载、更多等页面暂未本地化，仍显示中文；重启后设置页将以所选语言启动。",
        .languageRestart: "立即重启启动器",
        .languageRestartFailed: "重启失败：无法重新拉起当前可执行文件",

        .themeTitle: "主题",
        .themeSubtitle: "深色与浅色两套中性主题，切换立即生效",
        .themeTooltip: "主题只换色值，结构、间距与控件形态完全一致",
        .themeGroup: "主题",
        .borderTitle: "边框强度",
        .borderSubtitle: "调节面板与分割线的描边可见度",
        .borderTooltip: "范围 0.4× ~ 1.6×，默认 1.0×",
        .cornerTitle: "圆角缩放",
        .cornerSubtitle: "按比例缩放全站圆角",
        .cornerTooltip: "范围 0.6× ~ 1.4×，默认 1.0×",
        .compareTitle: "实时对比",
        .compareHint: "当前值变化时右侧保持默认，便于比较",
        .compareCurrent: "当前",
        .compareDefault: "默认",
        .compareBadge: "对比样",
        .compareButton: "按钮",
        .compareButtonHint: "示例区域，仅作外观对比；按钮不可操作",
        .comparePlaceholder: "玩家名",

        .currentAccountTitle: "当前账户",
        .currentAccountSubtitle: "离线模式 · 无需登录即可进入单人游戏",
        .premiumTitle: "正版账户",
        .premiumSubtitle: "微软账户登录后，启动游戏将使用正版身份与皮肤",
        .premiumAdd: "添加微软账户",
        .premiumEmpty: "还没有正版账户，添加后可使用正版身份启动游戏",
        .premiumBadge: "正版",
        .premiumCurrent: "当前",
        .premiumSwitch: "切换",
        .premiumRefresh: "刷新登录",
        .premiumLogout: "退出登录",
        .premiumLogoutTitle: "退出正版账户？",
        .premiumLogoutMessage: "将清除本地登录信息并切回离线账户；云端数据与游戏存档不受影响。",
        .premiumLogoutConfirm: "退出登录",
        .premiumOfflineNote: "离线账户玩家名只在离线启动时生效",
        .playerNameTitle: "玩家名",
        .playerNameSubtitle: "游戏内显示名称，最多 16 个字符",
        .playerNameTooltip: "启动命令中的 auth_player_name 使用此名称",
        .playerNamePlaceholder: "玩家名",
        .playerNameApply: "应用",
        .playerNameReset: "恢复默认",
        .playerNameAppliedToast: "玩家名已保存为 %@",
        .playerNameEmpty: "玩家名不能为空",
        .playerNameTooLong: "玩家名最多 16 个字符",
        .playerNameInvalidChars: "玩家名只能包含字母、数字与下划线",
        .savedNamesTitle: "保存过的玩家名",
        .savedNamesSubtitle: "点击切换，删除不需要的名字",
        .savedNamesEmpty: "还没有保存过其他玩家名",
        .savedNamesCount: "已保存 %d 个",
        .savedNameSwitchedToast: "已切换到 %@",
        .savedNameRemove: "删除 %@",
        .savedNameRemovedToast: "已移除 %@",
        .uuidTitle: "离线 UUID",
        .uuidSubtitle: "由玩家名推导，用于离线服务器识别",
        .uuidTooltip: "离线 UUID = md5(\"OfflinePlayer:\" + 玩家名) 的 v3 格式，仅本机使用",
        .uuidCopy: "复制",
        .uuidCopiedToast: "离线 UUID 已复制",

        .versionTitle: "版本",
        .versionSubtitle: "当前发布的启动器版本",
        .buildTitle: "构建",
        .commitTitle: "提交",
        .buildDetailsTitle: "构建详情",
        .buildDateLabel: "构建时间",
        .buildChannelLabel: "更新通道",
        .updateSourceTitle: "更新源",
        .updateSourceSubtitleEmpty: "未配置更新源（本地构建）",
        .updateSourceSubtitleConfigured: "检查更新会向此地址发起真实 HTTP 请求",
        .updateSourcePlaceholder: "https://example.com/launcher-update.json",
        .updateSourceTooltip: "更新源是一个返回 {version, url, notes} 的 JSON 地址",
        .updateCheck: "检查更新",
        .updateChecking: "检查中…",
        .updateIdle: "尚未检查更新",
        .updateIdleBadge: "未检查",
        .updateCheckingBadge: "检查中",
        .updateUpToDateBadge: "已是最新",
        .updateNoFeedBadge: "未配置更新源",
        .updateFailedBadge: "检查失败",
        .updateUpToDate: "已是最新版本 v%@",
        .updateAvailable: "发现新版本 v%@",
        .updateNoFeed: "未配置更新源（本地构建）",
        .updateFailed: "检查失败：%@",
        .updateLastChecked: "上次检查：%@",
        .updateDownload: "打开下载页",
        .updateDownloadFailed: "下载地址无效",

        .logTitle: "日志与诊断",
        .logSubtitle: "完整诊断与崩溃报告在「更多 → 日志与诊断」",
        .logTooltip: "这里展示最近一次启动输出的最后几行",
        .logLinesBadge: "%d 行",
        .logExitCode: "退出码 %@",
        .logExitNone: "尚未运行过游戏",
        .logCopyRecent: "复制最近日志",
        .logExport: "导出日志",
        .logExportTooltip: "导出到 ~/Library/Logs/BlockLauncher/，导出后可在访达显示",
        .logOpenMore: "打开完整日志",
        .logClear: "清空日志",
        .logEmpty: "还没有日志，启动一次游戏后这里会显示实时输出。",
        .logCopiedToast: "已复制最近 %d 行日志到剪贴板",
        .logExportedToast: "日志已导出：%@",
        .logExportFailedToast: "导出失败：%@",
        .logClearedToast: "日志已清空",
        .logClearDialogTitle: "清空日志？",
        .logClearDialogMessage: "将清空当前 %d 行日志，此操作不可撤销。",
        .logClearDialogConfirm: "清空",
        .logReveal: "在访达中显示",
        .logExportLabelsTitle: "方块启动器日志",
        .logExportLabelsVersion: "启动器版本",
        .logExportLabelsGenerated: "导出时间",
        .logExportLabelsCommand: "启动命令",
        .logExportLabelsExitCode: "退出码",
        .logExportLabelsLineCount: "日志行数"
    ]

    // MARK: English

    /// 英文文案。
    static let englishTable: [SettingsTextKey: String] = [
        .pageTitle: "Settings",
        .groupGame: "Game",
        .groupLauncher: "Launcher",
        .groupAbout: "About",
        .sectionLaunch: "Launch",
        .sectionJava: "Java Runtime",
        .sectionPerformance: "Performance",
        .sectionUpdate: "Update & Language",
        .sectionAppearance: "Appearance",
        .sectionAccount: "Account",
        .sectionAbout: "About",
        .sectionLog: "Logs & Diagnostics",
        .subtitleLaunch: "Game directory and default launch behaviour",
        .subtitleJava: "Detected JDKs, picked by the selected version's requirement",
        .subtitlePerformance: "Memory and JVM arguments, applied on the next launch",
        .subtitleUpdate: "Update channel, download source and UI language",
        .subtitleAppearance: "Theme and global appearance, applied immediately",
        .subtitleAccount: "The offline player name is written into the launch command",
        .subtitleAbout: "Build information, update checks and feedback",
        .subtitleLog: "Launch logs and crash diagnostics in one place",
        .autoSave: "Auto-save",
        .badgeJavaNone: "None found",
        .badgeJavaCount: "%d found",
        .badgeOffline: "Offline account",
        .saveBarSavedAt: "Saved at %@",
        .saveBarNever: "Nothing written yet this session",
        .saveButton: "Save settings",
        .resetButton: "Restore defaults",
        .savedToast: "All changes written to disk",
        .saveNoChanges: "No new changes to save",
        .resetToast: "Default settings restored",
        .resetDialogTitle: "Restore default settings?",
        .resetDialogMessage: "Game directory, Java, memory, JVM arguments and language will be reset. Launch history and the update source are kept.",
        .resetSectionTitle: "Reset \"%@\" to defaults?",
        .resetSectionMessage: "Only settings on this page are reset; other pages, instances and accounts are kept.",
        .resetSectionToast: "\"%@\" has been reset to defaults",
        .resetSectionNoop: "This page has no settings to reset",
        .resetDialogConfirm: "Restore",

        .gameDirTitle: "Game directory",
        .gameDirSubtitle: "Root of versions / mods / saves",
        .gameDirTooltip: "The launcher reads and writes game files here; changes apply immediately",
        .gameDirPlaceholder: "Game directory",
        .gameDirSetToast: "Game directory updated: %@",
        .browse: "Browse…",
        .openInFinder: "Reveal in Finder",
        .openGameDirToast: "Opened the game directory in Finder",
        .pickGameDirMessage: "Choose the Minecraft game directory",
        .gameDirMissingToast: "Directory does not exist: %@",
        .isolationTitle: "Version isolation",
        .isolationSubtitle: "Each version gets its own mods and config directory",
        .isolationTooltip: "When off, all versions share one mods directory",
        .previewTitle: "Isolated directory preview",
        .previewSubtitle: "The directory actually used with the current setting",
        .previewNoVersion: "No version installed yet; the real directory appears here after installing",
        .previewIsolated: "On: versions/<version id>",
        .previewShared: "Off: the game root directory is used",
        .minimizeTitle: "Minimize after launch",
        .minimizeSubtitle: "Hide the launcher window to the Dock once the game starts",
        .checkUpdatesOnStartTitle: "Check for updates on launch",
        .checkUpdatesOnStartSubtitle: "Sends one real request to the update feed; new versions are announced",

        .javaAutoTitle: "Auto select",
        .javaAutoSubtitle: "Pick Java by the version requirement; when off the path below is used",
        .javaAutoTooltip: "The launcher picks the highest runtime that satisfies the requirement",
        .javaRuntimeTitle: "Java runtime",
        .javaRuntimeEmpty: "No Java detected; install a JDK then press Re-detect",
        .javaRuntimeCount: "%d runtimes detected · pick one from the menu",
        .javaRuntimeTooltipEmpty: "No executable java found; install Temurin 21 or fill in a path below",
        .javaDetectNow: "Detect now",
        .javaRedetect: "Re-detect",
        .javaRedetectSubtitle: "Scans /Library/Java/JavaVirtualMachines, Homebrew and JAVA_HOME",
        .javaManualTitle: "Custom path",
        .javaManualSubtitleAuto: "Ignored while auto select is on",
        .javaManualSubtitleManual: "Path to a java executable (empty falls back to auto detection)",
        .javaManualTooltip: "For example /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java",
        .javaPathPlaceholder: "java executable path",
        .javaValidate: "Validate",
        .javaValidating: "Validating…",
        .javaPathValid: "Valid path: Java %d (%@)",
        .javaIssueMissing: "File does not exist: %@",
        .javaIssueNotExecutable: "File is not executable: %@",
        .javaIssueProbeFailed: "java -version failed: %@",
        .javaRequiredTitle: "Current version requirement",
        .javaRequiredValue: "Requires Java %d or newer",
        .javaRequiredNone: "No game version is selected",
        .javaRequiredBadge: "Java %d+",
        .javaUsing: "Will use: %@",
        .javaRequiredTooltip: "Read from the local version JSON javaVersion field (with inheritsFrom fallback)",
        .javaListTitle: "Detected runtimes",
        .javaListSubtitle: "Expand to see version, vendor and path of every runtime",
        .javaOpenDirectory: "Open Java directory",
        .javaOpenDirectoryToast: "Opened %@ in Finder",
        .javaNoDirectoryToast: "No Java directory to open",
        .javaBadgeSatisfied: "Satisfies",
        .javaBadgeLow: "Too old",
        .javaBadgeInUse: "In use",
        .javaAutoLabel: "Auto detect",
        .javaAutoDetail: "Pick by version requirement",
        .javaRefreshToast: "Java runtimes re-detected",
        .javaListEmpty: "No Java runtime detected",
        .javaMenuGroup: "Runtimes",

        .memoryTitle: "Maximum memory",
        .memoryTooltip: "Maximum heap for the game JVM; too much memory slows the whole system",
        .memorySubtitleOptimal: "Recommended %d MB (this machine has %@ RAM)",
        .memorySubtitleBelow: "Below the recommended %d MB; large modpacks may stutter",
        .memorySubtitleAbove: "Above the recommended %d MB; little gain and it squeezes the system",
        .memorySubtitleOver: "Above this machine's safe limit of %d MB",
        .memoryApplyRecommended: "Apply recommended",
        .memoryLimitBadge: "%@ RAM · limit %d MB",
        .memoryAppliedToast: "Maximum memory set to the recommended %d MB",
        .jvmConflictTitle: "JVM argument conflict",
        .jvmConflictMessage: "Extra argument %@ overrides the %d MB limit; the game actually gets %d MB",
        .jvmConflictHint: "Remove that argument or use the slider above instead",
        .advancedTitle: "Advanced launch options",
        .advancedSubtitle: "Render threads and JVM arguments; usually no need to touch",
        .renderThreadsTitle: "Render threads",
        .renderThreadsSubtitle: "2 to 4 is recommended; more just adds scheduling overhead",
        .renderThreadsTooltip: "Maps to the -XX:ActiveProcessorCount JVM option",
        .renderThreadsHint: "This machine has %d CPU cores; %d threads recommended",
        .renderThreadsUnit: "threads",
        .jvmArgsTitle: "JVM arguments",
        .jvmArgsSubtitle: "One per line, lines starting with # are comments; empty uses defaults",
        .jvmArgsCount: "%d arguments",
        .jvmArgsTooltip: "%d valid arguments parsed",
        .jvmArgsPlaceholder: "One JVM argument per line, e.g. -XX:+UseG1GC",

        .channelTitle: "Update channel",
        .channelSubtitle: "Preference only: the current update source has no channels, check results are unaffected",
        .channelTooltip: "The channel is just stored in settings; UpdateChecker always checks the feed version regardless of channel",
        .channelGroup: "Update channel",
        .channelRelease: "Release",
        .channelSnapshot: "Snapshot",
        .channelPreview: "Preview",
        .channelReleaseDetail: "Preference: stable versions only (the feed does not distinguish channels)",
        .channelSnapshotDetail: "Preference: accept experimental content (the feed does not distinguish channels)",
        .channelPreviewDetail: "Preference: accept newest builds (the feed does not distinguish channels)",
        .sourceTitle: "Download source",
        .sourceSubtitle: "Used when installing the game and its assets",
        .sourceTooltip: "Official connects to Mojang directly; mirror rewrites Mojang hosts to BMCLAPI",
        .sourceOfficial: "Official (Mojang)",
        .sourceMirror: "Mirror (BMCLAPI)",
        .sourceOfficialDetail: "Direct Mojang connection; safest, may be slow in some regions",
        .sourceMirrorDetail: "Rewrites Mojang download hosts to BMCLAPI, usually faster locally",
        .autoCleanTitle: "Hint about cleanable versions after install",
        .autoCleanSubtitle: "After an install, reports versions unused for 30 days; nothing is deleted automatically",
        .cleanupTitle: "Old versions to clean",
        .cleanupSubtitle: "Expand to scan and delete unused versions",
        .cleanupScan: "Scan",
        .cleanupScanning: "Scanning…",
        .cleanupNotScanned: "Press Scan to list versions unused for %d days",
        .cleanupEmpty: "No version unused for more than %d days",
        .cleanupLastUsed: "Last launched: %@",
        .cleanupNeverUsed: "Never launched by this launcher",
        .cleanupFileModified: "Last modified: %@",
        .cleanupDelete: "Delete",
        .cleanupDeleteAll: "Clean all",
        .cleanupTotal: "%d versions · about %@",
        .cleanupDialogTitle: "Clean old versions?",
        .cleanupDialogMessage: "%d versions (about %@) will be moved to the Trash. They can be restored from there.",
        .cleanupDialogConfirm: "Clean",
        .cleanupToast: "Cleaned %d old versions (restorable from the Trash)",
        .cleanupFailed: "Failed to clean %@: %@",
        .languageTitle: "Interface language",
        .languageSubtitle: "This page switches immediately; other pages are not localized yet and stay in Chinese",
        .languageTooltip: "The language is stored in settings; only this settings page uses it and keeps it after a restart",
        .languageMenuGroup: "Interface language",
        .languageApplied: "Current language: %@",
        .languageAppliedBadge: "Active",
        .languagePendingBadge: "Applies to this page",
        .languageBannerTitle: "Settings page switched to %@",
        .languageBannerMessage: "Launch, Download and More are not localized yet and stay in Chinese; after a restart this settings page starts in the selected language.",
        .languageRestart: "Restart launcher now",
        .languageRestartFailed: "Restart failed: could not relaunch the current executable",

        .themeTitle: "Theme",
        .themeSubtitle: "A dark and a light neutral theme, applied immediately",
        .themeTooltip: "Themes only swap colours; structure, spacing and controls stay identical",
        .themeGroup: "Theme",
        .borderTitle: "Border strength",
        .borderSubtitle: "Controls stroke visibility on panels and dividers",
        .borderTooltip: "Range 0.4× to 1.6×, default 1.0×",
        .cornerTitle: "Corner scale",
        .cornerSubtitle: "Scales the corner radius across the app",
        .cornerTooltip: "Range 0.6× to 1.4×, default 1.0×",
        .compareTitle: "Live comparison",
        .compareHint: "The right side stays at defaults while the current values change",
        .compareCurrent: "Current",
        .compareDefault: "Default",
        .compareBadge: "Sample",
        .compareButton: "Button",
        .compareButtonHint: "Sample area for appearance comparison only; the button is not interactive",
        .comparePlaceholder: "Player name",

        .currentAccountTitle: "Current account",
        .currentAccountSubtitle: "Offline mode · no sign-in needed for single player",
        .premiumTitle: "Premium account",
        .premiumSubtitle: "Sign in with a Microsoft account to launch as a premium player",
        .premiumAdd: "Add Microsoft account",
        .premiumEmpty: "No premium account yet. Add one to launch with a premium identity.",
        .premiumBadge: "Premium",
        .premiumCurrent: "Current",
        .premiumSwitch: "Switch",
        .premiumRefresh: "Refresh sign-in",
        .premiumLogout: "Sign out",
        .premiumLogoutTitle: "Sign out of the premium account?",
        .premiumLogoutMessage: "Local sign-in data will be removed and the offline account selected. Cloud data and saves are unaffected.",
        .premiumLogoutConfirm: "Sign out",
        .premiumOfflineNote: "The offline player name only applies to offline launches",
        .playerNameTitle: "Player name",
        .playerNameSubtitle: "Shown in game, up to 16 characters",
        .playerNameTooltip: "Used as auth_player_name in the launch command",
        .playerNamePlaceholder: "Player name",
        .playerNameApply: "Apply",
        .playerNameReset: "Reset",
        .playerNameAppliedToast: "Player name saved as %@",
        .playerNameEmpty: "Player name cannot be empty",
        .playerNameTooLong: "Player name is limited to 16 characters",
        .playerNameInvalidChars: "Only letters, digits and underscores are allowed",
        .savedNamesTitle: "Saved player names",
        .savedNamesSubtitle: "Click to switch, delete names you no longer need",
        .savedNamesEmpty: "No other player name saved yet",
        .savedNamesCount: "%d saved",
        .savedNameSwitchedToast: "Switched to %@",
        .savedNameRemove: "Delete %@",
        .savedNameRemovedToast: "Removed %@",
        .uuidTitle: "Offline UUID",
        .uuidSubtitle: "Derived from the player name for offline servers",
        .uuidTooltip: "Offline UUID = v3-format md5(\"OfflinePlayer:\" + name), local only",
        .uuidCopy: "Copy",
        .uuidCopiedToast: "Offline UUID copied",

        .versionTitle: "Version",
        .versionSubtitle: "Currently released launcher version",
        .buildTitle: "Build",
        .commitTitle: "Commit",
        .buildDetailsTitle: "Build details",
        .buildDateLabel: "Build time",
        .buildChannelLabel: "Update channel",
        .updateSourceTitle: "Update source",
        .updateSourceSubtitleEmpty: "No update source configured (local build)",
        .updateSourceSubtitleConfigured: "Check for updates sends a real HTTP request to this address",
        .updateSourcePlaceholder: "https://example.com/launcher-update.json",
        .updateSourceTooltip: "The update source is a JSON endpoint returning {version, url, notes}",
        .updateCheck: "Check for updates",
        .updateChecking: "Checking…",
        .updateIdle: "Not checked yet",
        .updateIdleBadge: "Unchecked",
        .updateCheckingBadge: "Checking",
        .updateUpToDateBadge: "Up to date",
        .updateNoFeedBadge: "No update source",
        .updateFailedBadge: "Check failed",
        .updateUpToDate: "Up to date (v%@)",
        .updateAvailable: "New version available: v%@",
        .updateNoFeed: "No update source configured (local build)",
        .updateFailed: "Check failed: %@",
        .updateLastChecked: "Last checked: %@",
        .updateDownload: "Open download page",
        .updateDownloadFailed: "Invalid download address",

        .logTitle: "Logs & diagnostics",
        .logSubtitle: "Full diagnostics and crash reports live in More → Logs & Diagnostics",
        .logTooltip: "Shows the last lines of the most recent launch output",
        .logLinesBadge: "%d lines",
        .logExitCode: "Exit code %@",
        .logExitNone: "No game launched yet",
        .logCopyRecent: "Copy recent log",
        .logExport: "Export log",
        .logExportTooltip: "Exported to ~/Library/Logs/BlockLauncher/; reveal it in Finder afterwards",
        .logOpenMore: "Open full log",
        .logClear: "Clear log",
        .logEmpty: "No log yet; launch the game once and live output appears here.",
        .logCopiedToast: "Copied the last %d log lines",
        .logExportedToast: "Log exported: %@",
        .logExportFailedToast: "Export failed: %@",
        .logClearedToast: "Log cleared",
        .logClearDialogTitle: "Clear the log?",
        .logClearDialogMessage: "The current %d log lines will be cleared. This cannot be undone.",
        .logClearDialogConfirm: "Clear",
        .logReveal: "Reveal in Finder",
        .logExportLabelsTitle: "BlockLauncher log",
        .logExportLabelsVersion: "Launcher version",
        .logExportLabelsGenerated: "Generated",
        .logExportLabelsCommand: "Launch command",
        .logExportLabelsExitCode: "Exit code",
        .logExportLabelsLineCount: "Log lines"
    ]

    // MARK: 日本語

    /// 日文文案。
    static let japaneseTable: [SettingsTextKey: String] = [
        .pageTitle: "設定",
        .groupGame: "ゲーム",
        .groupLauncher: "ランチャー",
        .groupAbout: "情報",
        .sectionLaunch: "起動",
        .sectionJava: "Java ランタイム",
        .sectionPerformance: "パフォーマンス",
        .sectionUpdate: "更新と言語",
        .sectionAppearance: "外観",
        .sectionAccount: "アカウント",
        .sectionAbout: "情報",
        .sectionLog: "ログと診断",
        .subtitleLaunch: "ゲームディレクトリと起動時の既定動作",
        .subtitleJava: "検出した JDK から、選択中バージョンの要件に合わせて選びます",
        .subtitlePerformance: "メモリと JVM 引数。次回起動時に反映されます",
        .subtitleUpdate: "更新チャンネル、ダウンロード元、表示言語",
        .subtitleAppearance: "テーマと外観設定。変更はすぐに反映されます",
        .subtitleAccount: "オフラインのプレイヤー名は起動コマンドに書き込まれます",
        .subtitleAbout: "ビルド情報、更新確認、フィードバック",
        .subtitleLog: "起動ログとクラッシュ診断をまとめて管理",
        .autoSave: "自動保存",
        .badgeJavaNone: "未検出",
        .badgeJavaCount: "%d 個",
        .badgeOffline: "オフライン",
        .saveBarSavedAt: "%@ に保存",
        .saveBarNever: "今回の起動ではまだ書き込んでいません",
        .saveButton: "設定を保存",
        .resetButton: "既定値に戻す",
        .savedToast: "すべての変更をディスクに書き込みました",
        .saveNoChanges: "保存する新しい変更はありません",
        .resetToast: "既定値に戻しました",
        .resetDialogTitle: "既定値に戻しますか？",
        .resetDialogMessage: "ゲームディレクトリ、Java、メモリ、JVM 引数、言語などを既定値に戻します。起動履歴と更新元は保持されます。",
        .resetSectionTitle: "「%@」を既定値に戻しますか？",
        .resetSectionMessage: "このページの設定のみをリセットします。他のページ・インスタンス・アカウントは保持されます。",
        .resetSectionToast: "「%@」を既定値に戻しました",
        .resetSectionNoop: "このページにリセットできる設定はありません",
        .resetDialogConfirm: "戻す",

        .gameDirTitle: "ゲームディレクトリ",
        .gameDirSubtitle: "versions / mods / saves のルート",
        .gameDirTooltip: "ランチャーはここでゲームファイルを読み書きします。変更はすぐに反映されます",
        .gameDirPlaceholder: "ゲームディレクトリ",
        .gameDirSetToast: "ゲームディレクトリを更新：%@",
        .browse: "参照…",
        .openInFinder: "Finder で開く",
        .openGameDirToast: "Finder でゲームディレクトリを開きました",
        .pickGameDirMessage: "Minecraft のゲームディレクトリを選択",
        .gameDirMissingToast: "ディレクトリがありません：%@",
        .isolationTitle: "バージョン分離",
        .isolationSubtitle: "バージョンごとに mods と設定ディレクトリを分けます",
        .isolationTooltip: "オフにするとすべてのバージョンが同じ mods を共有します",
        .previewTitle: "分離ディレクトリのプレビュー",
        .previewSubtitle: "現在の設定で実際に使われるディレクトリ",
        .previewNoVersion: "バージョンが未インストールです。インストール後に実際のパスが表示されます",
        .previewIsolated: "オン：versions/<バージョン id>",
        .previewShared: "オフ：ゲームのルートディレクトリを使用",
        .minimizeTitle: "起動後に最小化",
        .minimizeSubtitle: "ゲーム開始後にランチャーを Dock に収納します",
        .checkUpdatesOnStartTitle: "起動時に更新を確認",
        .checkUpdatesOnStartSubtitle: "起動時に更新元へ実際にリクエストし、新バージョンを通知します",

        .javaAutoTitle: "自動選択",
        .javaAutoSubtitle: "バージョンの要件に合わせて Java を選びます。オフの場合は下のパスを使用",
        .javaAutoTooltip: "要件を満たす最も新しいランタイムを起動時に選びます",
        .javaRuntimeTitle: "Java ランタイム",
        .javaRuntimeEmpty: "Java が見つかりません。JDK を入れて「再検出」を押してください",
        .javaRuntimeCount: "%d 個のランタイム · メニューから指定できます",
        .javaRuntimeTooltipEmpty: "実行可能な java が見つかりません。Temurin 21 を入れるか下にパスを入力してください",
        .javaDetectNow: "今すぐ検出",
        .javaRedetect: "再検出",
        .javaRedetectSubtitle: "/Library/Java/JavaVirtualMachines、Homebrew、JAVA_HOME を走査",
        .javaManualTitle: "カスタムパス",
        .javaManualSubtitleAuto: "自動選択がオンの間は無効です",
        .javaManualSubtitleManual: "java 実行ファイルのパス（空なら自動検出に戻ります）",
        .javaManualTooltip: "例：/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java",
        .javaPathPlaceholder: "java 実行ファイルのパス",
        .javaValidate: "検証",
        .javaValidating: "検証中…",
        .javaPathValid: "有効なパス：Java %d（%@）",
        .javaIssueMissing: "ファイルがありません：%@",
        .javaIssueNotExecutable: "実行できません：%@",
        .javaIssueProbeFailed: "java -version を実行できません：%@",
        .javaRequiredTitle: "現在のバージョンの要件",
        .javaRequiredValue: "Java %d 以上が必要",
        .javaRequiredNone: "選択中のゲームバージョンはありません",
        .javaRequiredBadge: "Java %d+",
        .javaUsing: "使用予定：%@",
        .javaRequiredTooltip: "ローカルのバージョン JSON の javaVersion から判定（inheritsFrom も遡ります）",
        .javaListTitle: "検出したランタイム",
        .javaListSubtitle: "展開すると各ランタイムのバージョン・ベンダー・パスを表示",
        .javaOpenDirectory: "Java ディレクトリを開く",
        .javaOpenDirectoryToast: "Finder で %@ を開きました",
        .javaNoDirectoryToast: "開ける Java ディレクトリがありません",
        .javaBadgeSatisfied: "要件を満たす",
        .javaBadgeLow: "バージョン不足",
        .javaBadgeInUse: "使用中",
        .javaAutoLabel: "自動検出",
        .javaAutoDetail: "要件に合わせて選択",
        .javaRefreshToast: "Java ランタイムを再検出しました",
        .javaListEmpty: "Java ランタイムが検出されません",
        .javaMenuGroup: "ランタイム",

        .memoryTitle: "最大メモリ",
        .memoryTooltip: "ゲーム JVM の最大ヒープ。増やしすぎるとシステム全体が遅くなります",
        .memorySubtitleOptimal: "推奨 %d MB（この PC のメモリ %@）",
        .memorySubtitleBelow: "推奨値 %d MB を下回っています。大きな MOD 構成では重くなる可能性があります",
        .memorySubtitleAbove: "推奨値 %d MB を超えています。効果は限定的でシステムを圧迫します",
        .memorySubtitleOver: "この PC の安全上限 %d MB を超えています",
        .memoryApplyRecommended: "推奨値を適用",
        .memoryLimitBadge: "PC メモリ %@ · 上限 %d MB",
        .memoryAppliedToast: "最大メモリを推奨値 %d MB に設定しました",
        .jvmConflictTitle: "JVM 引数の競合",
        .jvmConflictMessage: "追加引数 %@ が「最大メモリ %d MB」を上書きし、実際の上限は %d MB になります",
        .jvmConflictHint: "その引数を削除するか、上のスライダーで設定してください",
        .advancedTitle: "詳細な起動オプション",
        .advancedSubtitle: "レンダリングスレッドと JVM 引数。通常は変更不要です",
        .renderThreadsTitle: "レンダリングスレッド",
        .renderThreadsSubtitle: "2〜4 を推奨。増やしすぎるとスケジューリングの負荷が増えます",
        .renderThreadsTooltip: "JVM の -XX:ActiveProcessorCount に対応します",
        .renderThreadsHint: "この PC は %d コア。%d スレッドを推奨",
        .renderThreadsUnit: "スレッド",
        .jvmArgsTitle: "JVM 引数",
        .jvmArgsSubtitle: "1 行に 1 つ。# で始まる行はコメント。空欄なら既定値を使用",
        .jvmArgsCount: "%d 個の引数",
        .jvmArgsTooltip: "有効な引数を %d 個解析しました",
        .jvmArgsPlaceholder: "1 行に 1 つの JVM 引数（例：-XX:+UseG1GC）",

        .channelTitle: "更新チャンネル",
        .channelSubtitle: "設定のみ：現在の更新元はチャンネル非対応で、更新確認の結果は変わりません",
        .channelTooltip: "チャンネルは設定に保存されるだけです。UpdateChecker は常に更新元のバージョンを確認します",
        .channelGroup: "更新チャンネル",
        .channelRelease: "リリース",
        .channelSnapshot: "スナップショット",
        .channelPreview: "プレビュー",
        .channelReleaseDetail: "設定のみ：安定版のみを希望（更新元はチャンネル非対応）",
        .channelSnapshotDetail: "設定のみ：実験的な内容も許容（更新元はチャンネル非対応）",
        .channelPreviewDetail: "設定のみ：最新ビルドも許容（更新元はチャンネル非対応）",
        .sourceTitle: "ダウンロード元",
        .sourceSubtitle: "ゲームとアセットのインストール時に使用",
        .sourceTooltip: "公式は Mojang に直接接続。ミラーは Mojang のホストを BMCLAPI に書き換えます",
        .sourceOfficial: "公式（Mojang）",
        .sourceMirror: "ミラー（BMCLAPI 高速化）",
        .sourceOfficialDetail: "Mojang に直接接続。最も確実だが地域によっては遅い",
        .sourceMirrorDetail: "Mojang のダウンロードホストを BMCLAPI に書き換え、通常は高速",
        .autoCleanTitle: "インストール後に整理可能な旧バージョンを通知",
        .autoCleanSubtitle: "インストール後、30 日間未起動のバージョンをログで通知します（自動削除はしません）",
        .cleanupTitle: "整理できる古いバージョン",
        .cleanupSubtitle: "展開して未使用バージョンを走査・削除できます",
        .cleanupScan: "走査",
        .cleanupScanning: "走査中…",
        .cleanupNotScanned: "「走査」で %d 日間未起動のバージョンを一覧表示",
        .cleanupEmpty: "%d 日以上未起動のバージョンはありません",
        .cleanupLastUsed: "最終起動：%@",
        .cleanupNeverUsed: "このランチャーからは起動されていません",
        .cleanupFileModified: "最終更新：%@",
        .cleanupDelete: "削除",
        .cleanupDeleteAll: "すべて整理",
        .cleanupTotal: "%d 個 · 約 %@",
        .cleanupDialogTitle: "古いバージョンを整理しますか？",
        .cleanupDialogMessage: "%d 個（約 %@）をゴミ箱に移動します。ゴミ箱から復元できます。",
        .cleanupDialogConfirm: "整理",
        .cleanupToast: "%d 個の古いバージョンを整理しました（ゴミ箱から復元可能）",
        .cleanupFailed: "%@ の整理に失敗：%@",
        .languageTitle: "表示言語",
        .languageSubtitle: "このページはすぐに切り替わります。他のページは未対応のため中国語のままです",
        .languageTooltip: "言語は設定に保存されます。現在は設定ページのみ反映され、再起動後もこのページで維持されます",
        .languageMenuGroup: "表示言語",
        .languageApplied: "現在の言語環境：%@",
        .languageAppliedBadge: "反映済み",
        .languagePendingBadge: "再起動後このページに反映",
        .languageBannerTitle: "設定ページを %@ に切り替えました",
        .languageBannerMessage: "起動・ダウンロード・その他のページは未対応のため中国語のままです。再起動後、この設定ページは選択した言語で表示されます。",
        .languageRestart: "ランチャーを再起動",
        .languageRestartFailed: "再起動に失敗：現在の実行ファイルを起動できませんでした",

        .themeTitle: "テーマ",
        .themeSubtitle: "ダークとライトの 2 種類。切り替えはすぐに反映されます",
        .themeTooltip: "テーマは色のみを変更し、構造・余白・コントロールは同一です",
        .themeGroup: "テーマ",
        .borderTitle: "境界線の強さ",
        .borderSubtitle: "パネルと区切り線の描画の見え方を調整",
        .borderTooltip: "範囲 0.4×〜1.6×、既定 1.0×",
        .cornerTitle: "角丸スケール",
        .cornerSubtitle: "アプリ全体の角丸をまとめて拡大縮小",
        .cornerTooltip: "範囲 0.6×〜1.4×、既定 1.0×",
        .compareTitle: "リアルタイム比較",
        .compareHint: "現在値を変えても右側は既定値のままなので比較できます",
        .compareCurrent: "現在",
        .compareDefault: "既定",
        .compareBadge: "サンプル",
        .compareButton: "ボタン",
        .compareButtonHint: "外観比較用のサンプルです。ボタンは操作できません",
        .comparePlaceholder: "プレイヤー名",

        .currentAccountTitle: "現在のアカウント",
        .currentAccountSubtitle: "オフラインモード · シングルならログイン不要",
        .premiumTitle: "正規アカウント",
        .premiumSubtitle: "Microsoft アカウントでログインすると、正規の身分とスキンで起動します",
        .premiumAdd: "Microsoft アカウントを追加",
        .premiumEmpty: "正規アカウントがありません。追加すると正規の身分で起動できます",
        .premiumBadge: "正規",
        .premiumCurrent: "使用中",
        .premiumSwitch: "切り替え",
        .premiumRefresh: "ログインを更新",
        .premiumLogout: "ログアウト",
        .premiumLogoutTitle: "正規アカウントからログアウトしますか？",
        .premiumLogoutMessage: "ローカルのログイン情報を削除し、オフラインアカウントに戻します。クラウドデータとセーブは影響を受けません。",
        .premiumLogoutConfirm: "ログアウト",
        .premiumOfflineNote: "オフラインのプレイヤー名はオフライン起動時のみ有効です",
        .playerNameTitle: "プレイヤー名",
        .playerNameSubtitle: "ゲーム内の表示名。最大 16 文字",
        .playerNameTooltip: "起動コマンドの auth_player_name に使われます",
        .playerNamePlaceholder: "プレイヤー名",
        .playerNameApply: "適用",
        .playerNameReset: "既定に戻す",
        .playerNameAppliedToast: "プレイヤー名を %@ として保存しました",
        .playerNameEmpty: "プレイヤー名は空にできません",
        .playerNameTooLong: "プレイヤー名は最大 16 文字です",
        .playerNameInvalidChars: "使用できるのは英数字とアンダースコアのみです",
        .savedNamesTitle: "保存済みのプレイヤー名",
        .savedNamesSubtitle: "クリックで切り替え、不要な名前は削除できます",
        .savedNamesEmpty: "保存された他のプレイヤー名はまだありません",
        .savedNamesCount: "%d 件保存済み",
        .savedNameSwitchedToast: "%@ に切り替えました",
        .savedNameRemove: "%@ を削除",
        .savedNameRemovedToast: "%@ を削除しました",
        .uuidTitle: "オフライン UUID",
        .uuidSubtitle: "プレイヤー名から生成し、オフラインサーバーで使用",
        .uuidTooltip: "オフライン UUID = md5(\"OfflinePlayer:\" + 名前) の v3 形式。ローカル専用",
        .uuidCopy: "コピー",
        .uuidCopiedToast: "オフライン UUID をコピーしました",

        .versionTitle: "バージョン",
        .versionSubtitle: "現在リリースされているランチャーのバージョン",
        .buildTitle: "ビルド",
        .commitTitle: "コミット",
        .buildDetailsTitle: "ビルド詳細",
        .buildDateLabel: "ビルド日時",
        .buildChannelLabel: "更新チャンネル",
        .updateSourceTitle: "更新元",
        .updateSourceSubtitleEmpty: "更新元が未設定です（ローカルビルド）",
        .updateSourceSubtitleConfigured: "更新確認はこのアドレスへ実際に HTTP リクエストを送ります",
        .updateSourcePlaceholder: "https://example.com/launcher-update.json",
        .updateSourceTooltip: "更新元は {version, url, notes} を返す JSON の URL です",
        .updateCheck: "更新を確認",
        .updateChecking: "確認中…",
        .updateIdle: "まだ確認していません",
        .updateIdleBadge: "未確認",
        .updateCheckingBadge: "確認中",
        .updateUpToDateBadge: "最新",
        .updateNoFeedBadge: "更新元なし",
        .updateFailedBadge: "確認失敗",
        .updateUpToDate: "最新バージョンです（v%@）",
        .updateAvailable: "新しいバージョン v%@ があります",
        .updateNoFeed: "更新元が未設定です（ローカルビルド）",
        .updateFailed: "確認に失敗：%@",
        .updateLastChecked: "前回の確認：%@",
        .updateDownload: "ダウンロードページを開く",
        .updateDownloadFailed: "ダウンロード先が無効です",

        .logTitle: "ログと診断",
        .logSubtitle: "詳細な診断とクラッシュレポートは「その他 → ログと診断」にあります",
        .logTooltip: "直近の起動出力の最後の数行を表示します",
        .logLinesBadge: "%d 行",
        .logExitCode: "終了コード %@",
        .logExitNone: "まだゲームを起動していません",
        .logCopyRecent: "最近のログをコピー",
        .logExport: "ログを書き出す",
        .logExportTooltip: "~/Library/Logs/BlockLauncher/ に書き出します。書き出し後は Finder で表示できます",
        .logOpenMore: "完全なログを開く",
        .logClear: "ログを消去",
        .logEmpty: "ログはまだありません。ゲームを起動するとここに出力が表示されます。",
        .logCopiedToast: "最近のログ %d 行をコピーしました",
        .logExportedToast: "ログを書き出しました：%@",
        .logExportFailedToast: "書き出しに失敗：%@",
        .logClearedToast: "ログを消去しました",
        .logClearDialogTitle: "ログを消去しますか？",
        .logClearDialogMessage: "現在の %d 行のログを消去します。この操作は取り消せません。",
        .logClearDialogConfirm: "消去",
        .logReveal: "Finder で表示",
        .logExportLabelsTitle: "BlockLauncher ログ",
        .logExportLabelsVersion: "ランチャーのバージョン",
        .logExportLabelsGenerated: "書き出し日時",
        .logExportLabelsCommand: "起動コマンド",
        .logExportLabelsExitCode: "終了コード",
        .logExportLabelsLineCount: "ログ行数"
    ]
}
