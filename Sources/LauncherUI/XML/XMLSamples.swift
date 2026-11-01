import Foundation

/// 一个 XML 示例：标题 + 源码 + 列表数据。
public struct XMLSample: Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let source: String
    public let data: XMLDataSources

    public init(id: String, title: String, summary: String, source: String, data: XMLDataSources = .empty) {
        self.id = id
        self.title = title
        self.summary = summary
        self.source = source
        self.data = data
    }
}

/// 示例库：优先读取资源包里的 XML 文件，缺失时回退到内置最小示例。
public enum XMLSampleLibrary {
    public static let definitions: [(id: String, title: String, summary: String, file: String)] = [
        ("launcher", "启动器首屏", "版本卡 / 实例列表 / 下载进度 / 新闻", "launcher-home"),
        ("components", "控件总览", "按钮、输入、选择、反馈在 XML 里的写法", "components"),
        ("settings", "设置页", "表单、开关、分段控件与弹窗", "settings")
    ]

    public static var all: [XMLSample] {
        definitions.map { definition in
            let document = LauncherXMLDocument.load(named: definition.file)
            return XMLSample(
                id: definition.id,
                title: definition.title,
                summary: definition.summary,
                source: document?.source ?? fallbackSource,
                data: data(for: definition.id)
            )
        }
    }

    public static func sample(id: String) -> XMLSample? {
        all.first { $0.id == id }
    }

    // MARK: 示例数据源

    public static func data(for sampleID: String) -> XMLDataSources {
        XMLDataSources(lists: [
            "instances": instances,
            "servers": servers,
            "news": news,
            "mods": mods
        ])
    }

    private static func item(_ id: String, _ vars: [String: XMLValue]) -> XMLListItem {
        XMLListItem(id: id, vars: vars)
    }

    public static let instances: [XMLListItem] = [
        item("1.21.4", [
            "title": .string("1.21.4 · Fabric"), "subtitle": .string("模组 214 个 · 上次游玩 今天 14:32"),
            "tag": .string("Fabric"), "size": .string("6.2 GB"), "installed": .bool(true), "selected": .bool(true)
        ]),
        item("1.20.1", [
            "title": .string("1.20.1 · Forge"), "subtitle": .string("模组 96 个 · 上次游玩 3 天前"),
            "tag": .string("Forge"), "size": .string("5.4 GB"), "installed": .bool(true), "selected": .bool(false)
        ]),
        item("1.8.9", [
            "title": .string("1.8.9 · PvP 整合"), "subtitle": .string("模组 12 个 · 上次游玩 2 周前"),
            "tag": .string("PvP"), "size": .string("2.1 GB"), "installed": .bool(false), "selected": .bool(false)
        ]),
        item("1.21.4-vanilla", [
            "title": .string("1.21.4 · 正式版"), "subtitle": .string("模组 0 个 · 上次游玩 1 个月前"),
            "tag": .string("正式版"), "size": .string("1.2 GB"), "installed": .bool(true), "selected": .bool(false)
        ])
    ]

    public static let servers: [XMLListItem] = [
        item("hypixel", [
            "name": .string("mc.hypixel.net"), "players": .string("48.2k"),
            "ping": .int(32), "online": .bool(true), "region": .string("新加坡 · 亚洲")
        ]),
        item("2b2t", [
            "name": .string("mc.2b2t.org"), "players": .string("1.1k"),
            "ping": .int(148), "online": .bool(true), "region": .string("法兰克福 · 欧洲")
        ])
    ]

    public static let news: [XMLListItem] = [
        item("news-1", [
            "title": .string("1.21.5 快照 26w44a 发布"), "date": .string("2026-10-28"),
            "tag": .string("新"), "summary": .string("铜傀儡机制与试炼密室奖励调整。")
        ]),
        item("news-2", [
            "title": .string("Minecraft Live 2026 回顾"), "date": .string("2026-10-24"),
            "tag": .string("活动"), "summary": .string("生物投票结果与 2027 年更新路线图。")
        ])
    ]

    public static let mods: [XMLListItem] = [
        item("fabric-api", ["name": .string("Fabric API"), "version": .string("0.100.1"), "progress": .int(68)]),
        item("sodium", ["name": .string("Sodium"), "version": .string("0.6.9"), "progress": .int(31)])
    ]

    /// 资源缺失时的兜底示例，保证设计器永远有东西可渲染。
    public static let fallbackSource: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <ui title="兜底示例">
      <state>
        <bool name="isLaunching" value="false"/>
        <string name="launchStatus" value="就绪"/>
      </state>
      <vstack spacing="12" padding="16">
        <text style="title">XML 示例未找到</text>
        <text style="caption" tone="secondary">请检查 Sources/LauncherUI/Resources/XML 下的示例文件。</text>
      </vstack>
    </ui>
    """
}
