import SwiftUI

// MARK: - 数据模型（仅用于 UI 演示，不含真实启动逻辑）

/// 一个游戏实例。
public struct LauncherInstance: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let loader: String
    public let modCount: Int
    public let size: String
    public let java: String
    public let lastPlayed: String
    public let isInstalled: Bool
}

/// 版本列表里的一行。
public struct LauncherVersionItem: Identifiable, Equatable {
    public enum Kind: String, CaseIterable, Equatable {
        case release = "正式版"
        case snapshot = "快照"
        case loader = "加载器"
        case modpack = "整合包"
    }

    public enum InstallState: Equatable {
        case available
        case installing(Double)
        case installed
    }

    public let id: String
    public let version: String
    public let kind: Kind
    public let released: String
    public let size: String
    public let note: String
    public var state: InstallState
}

/// 下载队列中的任务。
public struct LauncherDownloadTask: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let progress: Double?
    public let speed: String
    public let total: String
}

/// 公告 / 新闻。
public struct LauncherNewsItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let date: String
    public let category: String
    public let summary: String
}

/// 服务器状态。
public struct LauncherServerInfo: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let address: String
    public let players: String
    public let ping: Int
    public let isOnline: Bool
    public let region: String
}

/// 更多页的工具卡。
public struct LauncherToolCard: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let badge: String?
}

/// 快捷键条目。
public struct LauncherShortcut: Identifiable, Equatable {
    public let id: String
    public let keys: String
    public let title: String
}

/// Java 运行时选项。
public struct LauncherJavaRuntime: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let detail: String
    public let path: String
    public let isRecommended: Bool
}

/// 账户信息。
public struct LauncherAccount: Equatable {
    public let name: String
    public let type: String
    public let lastLogin: String
    public let isOnline: Bool
}

// MARK: - 演示数据

/// 启动器界面使用的静态演示数据，保证四个页面数据口径一致。
public enum LauncherDemoData {
    public static let account = LauncherAccount(
        name: "Steve_2026",
        type: "微软账户 · 正版",
        lastLogin: "今天 09:12",
        isOnline: true
    )

    public static let currentInstance: LauncherInstance = instances[0]

    public static let instances: [LauncherInstance] = [
        LauncherInstance(id: "fabric-1.21.4", name: "1.21.4 · Fabric 0.16.9", version: "1.21.4",
                         loader: "Fabric", modCount: 214, size: "6.2 GB", java: "Java 21",
                         lastPlayed: "今天 14:32", isInstalled: true),
        LauncherInstance(id: "forge-1.20.1", name: "1.20.1 · Forge 47.2.0", version: "1.20.1",
                         loader: "Forge", modCount: 96, size: "5.4 GB", java: "Java 17",
                         lastPlayed: "3 天前", isInstalled: true),
        LauncherInstance(id: "pvp-1.8.9", name: "1.8.9 · PvP 整合", version: "1.8.9",
                         loader: "PvP", modCount: 12, size: "2.1 GB", java: "Java 8",
                         lastPlayed: "2 周前", isInstalled: true),
        LauncherInstance(id: "vanilla-1.21.4", name: "1.21.4 · 正式版", version: "1.21.4",
                         loader: "正式版", modCount: 0, size: "1.2 GB", java: "Java 21",
                         lastPlayed: "1 个月前", isInstalled: true)
    ]

    public static let versions: [LauncherVersionItem] = [
        LauncherVersionItem(id: "1.21.4", version: "1.21.4", kind: .release, released: "2026-10-22",
                            size: "1.2 GB", note: "最新正式版 · 加入试炼密室奖励调整", state: .installed),
        LauncherVersionItem(id: "1.21.4-pre1", version: "1.21.4-pre1", kind: .snapshot, released: "2026-10-15",
                            size: "1.2 GB", note: "预发布版 · 仅供测试", state: .available),
        LauncherVersionItem(id: "1.20.1", version: "1.20.1", kind: .release, released: "2026-06-12",
                            size: "1.1 GB", note: "长期稳定版本 · 模组生态成熟", state: .installed),
        LauncherVersionItem(id: "fabric-0.16.9", version: "Fabric 0.16.9", kind: .loader, released: "2026-09-30",
                            size: "18 MB", note: "需要先选择对应的游戏版本", state: .available),
        LauncherVersionItem(id: "neoforge-21.1", version: "NeoForge 21.1.72", kind: .loader, released: "2026-10-02",
                            size: "24 MB", note: "面向 1.21 的新一代 Forge 分支", state: .available),
        LauncherVersionItem(id: "better-mc", version: "Better MC · 群岛", kind: .modpack, released: "2026-09-18",
                            size: "2.4 GB", note: "轻量生存整合包 · 128 个模组", state: .installing(0.42))
    ]

    public static let downloadTasks: [LauncherDownloadTask] = [
        LauncherDownloadTask(id: "fabric-api", title: "Fabric API 0.100.1", detail: "模组前置 · 1.21.4",
                             progress: 0.68, speed: "2.4 MB/s", total: "12.8 MB"),
        LauncherDownloadTask(id: "sodium", title: "Sodium 0.6.9", detail: "渲染优化 · 1.21.4",
                             progress: 0.31, speed: "1.1 MB/s", total: "4.6 MB"),
        LauncherDownloadTask(id: "resource", title: "资源索引校验", detail: "1,284 个文件",
                             progress: nil, speed: "—", total: "—")
    ]

    public static let news: [LauncherNewsItem] = [
        LauncherNewsItem(id: "news-1", title: "1.21.5 快照 26w44a 发布", date: "2026-10-28",
                         category: "新", summary: "铜傀儡机制与试炼密室奖励调整。"),
        LauncherNewsItem(id: "news-2", title: "Minecraft Live 2026 回顾", date: "2026-10-24",
                         category: "活动", summary: "生物投票结果与 2027 年更新路线图。"),
        LauncherNewsItem(id: "news-3", title: "模组平台迁移公告", date: "2026-10-18",
                         category: "公告", summary: "部分旧版整合包需要重新校验依赖。")
    ]

    public static let servers: [LauncherServerInfo] = [
        LauncherServerInfo(id: "hypixel", name: "mc.hypixel.net", address: "mc.hypixel.net",
                           players: "48.2k", ping: 32, isOnline: true, region: "新加坡 · 亚洲"),
        LauncherServerInfo(id: "2b2t", name: "mc.2b2t.org", address: "mc.2b2t.org",
                           players: "1.1k", ping: 148, isOnline: true, region: "法兰克福 · 欧洲"),
        LauncherServerInfo(id: "local", name: "本地服务器", address: "127.0.0.1:25565",
                           players: "—", ping: 0, isOnline: false, region: "本机")
    ]

    public static let tools: [LauncherToolCard] = [
        LauncherToolCard(id: "logs", title: "日志与诊断", subtitle: "查看启动日志、导出崩溃报告",
                         systemImage: "doc.text.magnifyingglass", badge: nil),
        LauncherToolCard(id: "backup", title: "实例备份", subtitle: "一键备份世界与模组配置",
                         systemImage: "externaldrive.badge.timemachine", badge: "2 个"),
        LauncherToolCard(id: "mods", title: "模组管理", subtitle: "启用、更新与冲突检测",
                         systemImage: "puzzlepiece.extension.fill", badge: "214"),
        LauncherToolCard(id: "screenshots", title: "截图相册", subtitle: "浏览游戏内截图并快速分享",
                         systemImage: "photo.on.rectangle.angled", badge: nil),
        LauncherToolCard(id: "community", title: "社区与资源", subtitle: "整合包、模组与材质站外链",
                         systemImage: "globe.asia.australia.fill", badge: nil),
        LauncherToolCard(id: "about", title: "关于启动器", subtitle: "版本信息、开源许可与反馈",
                         systemImage: "info.circle.fill", badge: nil)
    ]

    public static let shortcuts: [LauncherShortcut] = [
        LauncherShortcut(id: "play", keys: "⌘↩", title: "启动当前实例"),
        LauncherShortcut(id: "gallery", keys: "⌘⇧D", title: "打开设计系统画廊"),
        LauncherShortcut(id: "settings", keys: "⌘,", title: "打开设置"),
        LauncherShortcut(id: "download", keys: "⌘2", title: "切换到下载"),
        LauncherShortcut(id: "search", keys: "⌘F", title: "搜索版本或实例"),
        LauncherShortcut(id: "logs", keys: "⌘L", title: "打开日志")
    ]

    public static let javaRuntimes: [LauncherJavaRuntime] = [
        LauncherJavaRuntime(id: "21", name: "Java 21（推荐）", detail: "Temurin 21.0.5 · 支持 1.21.4 及以上",
                            path: "/Library/Java/JavaVirtualMachines/temurin-21.jdk", isRecommended: true),
        LauncherJavaRuntime(id: "17", name: "Java 17", detail: "Temurin 17.0.12 · 兼容 1.18 ~ 1.20.6",
                            path: "/Library/Java/JavaVirtualMachines/temurin-17.jdk", isRecommended: false),
        LauncherJavaRuntime(id: "8", name: "Java 8", detail: "Zulu 8.82 · 1.12.2 及更早",
                            path: "/Library/Java/JavaVirtualMachines/zulu-8.jdk", isRecommended: false)
    ]

    public static let versionDirectory = "~/Library/Application Support/minecraft"
}
