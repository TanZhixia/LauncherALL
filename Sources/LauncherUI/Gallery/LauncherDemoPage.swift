import SwiftUI

/// 启动器实战样张：用玻璃卡与控件组合出 Minecraft 启动器的真实首屏。
public struct LauncherDemoPage: View {
    @Environment(\.launcherTheme) private var theme

    @State private var selectedInstanceID = "fabric-1.21.4"
    @State private var isLaunching = false

    /// 右侧信息栏固定窄宽，保证主区（实例 / 下载）始终占据约 2/3。
    private let railWidth: CGFloat = 300

    public init() {}

    private var currentInstance: DemoInstance {
        DemoData.instances.first { $0.id == selectedInstanceID } ?? DemoData.instances[0]
    }

    public var body: some View {
        LauncherPageScaffold(
            title: "启动器实战样张",
            subtitle: "Minecraft 启动器首屏：账户条、当前实例、版本列表、下载任务、账户 / 服务器 / 公告"
        ) {
            LauncherSection(
                "首屏预览",
                subtitle: "顶部账户条 + 左侧实例与下载（约 2/3） + 右侧账户、服务器与公告（约 1/3）"
            ) {
                VStack(spacing: LauncherSpace.lg) {
                    topBar
                    HStack(alignment: .top, spacing: LauncherSpace.lg) {
                        VStack(spacing: LauncherSpace.lg) {
                            currentInstanceCard
                            instanceListCard
                            downloadCard
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: LauncherSpace.lg) {
                            accountCard
                            serverCard
                            newsCard
                            reminderBanner
                        }
                        .frame(width: railWidth, alignment: .leading)
                    }
                }
            }

            LauncherSection(
                "已安装实例",
                subtitle: "完整版本清单：加载器、模组数量、占用空间与最近游玩记录"
            ) {
                archiveCard
            }
        }
    }

    // MARK: - 顶部账户条

    private var topBar: some View {
        GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.md) {
            HStack(spacing: LauncherSpace.md) {
                LauncherAvatar(
                    name: "Steve_2026",
                    size: LauncherControl.medium,
                    isOnline: true
                )
                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    Text("Steve_2026")
                        .textStyle(.headline)
                    HStack(spacing: LauncherSpace.xs) {
                        LauncherStatusDot(tone: .success)
                        Text("微软账户 · 正版 · 在线")
                            .textStyle(.micro, tone: .secondary)
                    }
                }
                Spacer(minLength: LauncherSpace.md)
                LauncherBadge("2 个任务下载中", tone: .info, systemImage: "arrow.down.circle")
                LauncherIconButton(systemImage: "gearshape.fill", accessibilityLabel: "设置") {}
                LauncherIconButton(systemImage: "bell.fill", accessibilityLabel: "通知") {}
                LauncherIconButton(
                    systemImage: "questionmark.circle.fill",
                    accessibilityLabel: "帮助"
                ) {}
            }
        }
    }

    // MARK: - 当前实例（主卡）

    private var currentInstanceCard: some View {
        LauncherCard(level: .regular) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                HStack(spacing: LauncherSpace.sm) {
                    Capsule()
                        .fill(theme.primaryGradient)
                        .frame(width: LauncherSpace.xs, height: LauncherSpace.lg)
                    LauncherLabel("CURRENT INSTANCE")
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherBadge(currentInstance.badgeText, tone: currentInstance.badgeTone)
                    LauncherBadge("Java 21", tone: .neutral, systemImage: "cup.and.saucer.fill")
                }
                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    Text(currentInstance.name)
                        .textStyle(.title)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("上次游玩 \(currentInstance.lastPlayed) · \(currentInstance.mods) 个模组 · 已游玩 128 小时")
                        .textStyle(.micro, tone: .tertiary)
                }
                LauncherDivider()
                LauncherDemoGrid(minWidth: 150) {
                    LauncherKeyValueRow(key: "游戏版本", value: currentInstance.gameVersion)
                    LauncherKeyValueRow(key: "加载器", value: currentInstance.loader)
                    LauncherKeyValueRow(key: "内存分配", value: "4.0 GB / 16.0 GB")
                    LauncherKeyValueRow(key: "存档数量", value: "7 个世界")
                }
                HStack(spacing: LauncherSpace.md) {
                    LauncherButton(
                        "开始游戏",
                        systemImage: "play.fill",
                        variant: .primary,
                        size: .large,
                        isLoading: isLaunching,
                        shortcut: "⌘↩"
                    ) {
                        isLaunching.toggle()
                    }
                    LauncherButton(
                        "选择版本",
                        systemImage: "list.bullet.rectangle",
                        variant: .secondary,
                        size: .large
                    ) {}
                    Spacer(minLength: LauncherSpace.sm)
                    VStack(alignment: .trailing, spacing: LauncherSpace.xxs) {
                        Text(isLaunching ? "正在启动…" : "已就绪")
                            .textStyle(.caption, tone: isLaunching ? .accent : .secondary)
                        Text("上次退出：正常")
                            .textStyle(.micro, tone: .tertiary)
                    }
                }
            }
        }
    }

    // MARK: - 版本 / 实例列表

    private var instanceListCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.sm) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherCardHeader(
                    title: "版本 / 实例列表",
                    subtitle: "按最近游玩排序 · 点击可切换当前实例",
                    systemImage: "square.stack.3d.up.fill",
                    accessory: AnyView(
                        LauncherBadge("\(DemoData.instances.count) 个", tone: .neutral)
                    )
                )
                .padding(.horizontal, LauncherSpace.sm)
                .padding(.top, LauncherSpace.xs)

                ForEach(DemoData.instances) { item in
                    LauncherListRow(
                        title: item.name,
                        subtitle: "模组 \(item.mods) 个 · 最后游玩 \(item.lastPlayed)",
                        systemImage: item.icon,
                        badge: item.badgeText,
                        accessory: AnyView(LauncherMonoText(item.size, tone: .tertiary)),
                        isSelected: item.id == selectedInstanceID,
                        action: { selectedInstanceID = item.id }
                    )
                }
            }
        }
    }

    // MARK: - 下载任务

    private var downloadCard: some View {
        LauncherCard(level: .regular) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherCardHeader(
                    title: "下载任务",
                    subtitle: "2 个进行中 · 1 个排队",
                    systemImage: "arrow.down.circle.fill",
                    accessory: AnyView(LauncherBadge("Fabric API", tone: .info))
                )
                LauncherProgressBar(value: 0.68, label: "Fabric API 0.100.1 · 下载中")
                LauncherProgressBar(value: 0.31, label: "Sodium 0.6.9 · 下载中", tone: .accent)
                LauncherProgressBar(label: "正在校验资源索引 · 预计 3 分钟")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 账户卡

    private var accountCard: some View {
        LauncherCard(level: .regular) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherCardHeader(
                    title: "账户",
                    subtitle: "2 个已登录账户",
                    systemImage: "person.crop.circle.fill"
                )
                HStack(spacing: LauncherSpace.md) {
                    LauncherAvatar(
                        name: "Steve_2026",
                        size: LauncherControl.large,
                        isOnline: true
                    )
                    VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                        Text("Steve_2026")
                            .textStyle(.bodyStrong)
                        HStack(spacing: LauncherSpace.xs) {
                            LauncherBadge("正版", tone: .success)
                            Text("Microsoft 账户")
                                .textStyle(.micro, tone: .secondary)
                        }
                    }
                    Spacer(minLength: LauncherSpace.xs)
                    LauncherStatusDot(tone: .success, isPulsing: true)
                }
                LauncherKeyValueRow(key: "上次登录", value: "今天 09:12")
                LauncherKeyValueRow(key: "皮肤", value: "Steve 经典")
                LauncherButton(
                    "切换账户",
                    systemImage: "arrow.triangle.2.circlepath",
                    variant: .secondary,
                    isFullWidth: true
                ) {}
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 服务器状态卡

    private var serverCard: some View {
        LauncherCard(level: .regular) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherCardHeader(
                    title: "服务器状态",
                    subtitle: "mc.hypixel.net",
                    systemImage: "server.rack",
                    accessory: AnyView(LauncherStatusDot(tone: .success, isPulsing: true))
                )
                HStack(spacing: LauncherSpace.md) {
                    LauncherStatTile(
                        value: "48.2k",
                        label: "在线玩家",
                        systemImage: "person.3.fill"
                    )
                    .frame(maxWidth: .infinity)
                    LauncherStatTile(
                        value: "32 ms",
                        label: "延迟",
                        systemImage: "wifi"
                    )
                    .frame(maxWidth: .infinity)
                }
                LauncherKeyValueRow(key: "游戏版本", value: "1.21.4")
                LauncherKeyValueRow(key: "节点", value: "新加坡 · 亚洲")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 新闻 / 公告卡

    private var newsCard: some View {
        LauncherCard(level: .regular) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherCardHeader(
                    title: "新闻与公告",
                    subtitle: "来自 Minecraft 官网",
                    systemImage: "newspaper.fill"
                )
                newsItem(
                    badge: "新",
                    tone: .accent,
                    date: "2026-10-28",
                    title: "1.21.5 快照 26w44a 发布",
                    excerpt: "铜傀儡机制与试炼密室奖励调整。"
                )
                LauncherDivider()
                newsItem(
                    badge: "活动",
                    tone: .info,
                    date: "2026-10-24",
                    title: "Minecraft Live 2026 回顾",
                    excerpt: "生物投票结果与 2027 年更新路线图。"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func newsItem(
        badge: String,
        tone: LauncherBadgeTone,
        date: String,
        title: String,
        excerpt: String
    ) -> some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            HStack(spacing: LauncherSpace.sm) {
                LauncherBadge(badge, tone: tone)
                Spacer(minLength: LauncherSpace.xs)
                LauncherMonoText(date, tone: .tertiary)
            }
            Text(title)
                .textStyle(.bodyStrong)
                .fixedSize(horizontal: false, vertical: true)
            Text(excerpt)
                .textStyle(.micro, tone: .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 底部提示横幅

    private var reminderBanner: some View {
        LauncherBanner(
            title: "Java 21 已就绪",
            message: "检测到 2 个可更新模组，建议启动前完成更新。",
            tone: .info,
            actionTitle: "查看",
            onAction: {}
        )
    }

    // MARK: - 已安装实例（完整清单）

    private var archiveCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.sm) {
            VStack(spacing: LauncherSpace.xxs) {
                ForEach(DemoData.archive) { item in
                    LauncherListRow(
                        title: item.name,
                        subtitle: "\(item.loader) · \(item.mods) 个模组 · 最后游玩 \(item.lastPlayed)",
                        systemImage: "shippingbox.fill",
                        badge: item.badgeText,
                        accessory: AnyView(LauncherMonoText(item.size, tone: .tertiary))
                    )
                }
            }
        }
    }
}

// MARK: - 页面内示例数据（自包含，不跨文件引用）

/// 演示用实例数据。
private struct DemoInstance: Identifiable {
    let id: String
    /// 显示名，例如 "1.21.4 · Fabric 0.16.9"
    let name: String
    let gameVersion: String
    let loader: String
    let badgeText: String
    let badgeTone: LauncherBadgeTone
    let mods: String
    let lastPlayed: String
    let size: String
    let icon: String
}

private enum DemoData {
    static let instances: [DemoInstance] = [
        DemoInstance(
            id: "fabric-1.21.4",
            name: "1.21.4 · Fabric 0.16.9",
            gameVersion: "1.21.4",
            loader: "Fabric 0.16.9",
            badgeText: "Fabric",
            badgeTone: .info,
            mods: "214",
            lastPlayed: "今天 14:32",
            size: "6.2 GB",
            icon: "cube.fill"
        ),
        DemoInstance(
            id: "forge-1.20.1",
            name: "1.20.1 · Forge 47.2.0",
            gameVersion: "1.20.1",
            loader: "Forge 47.2.0",
            badgeText: "Forge",
            badgeTone: .warning,
            mods: "96",
            lastPlayed: "3 天前",
            size: "5.4 GB",
            icon: "cube.fill"
        ),
        DemoInstance(
            id: "pvp-1.8.9",
            name: "1.8.9 · PvP 整合",
            gameVersion: "1.8.9",
            loader: "原版 + 模组",
            badgeText: "PvP",
            badgeTone: .danger,
            mods: "12",
            lastPlayed: "2 周前",
            size: "2.1 GB",
            icon: "bolt.fill"
        ),
        DemoInstance(
            id: "vanilla-1.21.4",
            name: "1.21.4 · 正式版",
            gameVersion: "1.21.4",
            loader: "原版",
            badgeText: "正式版",
            badgeTone: .success,
            mods: "0",
            lastPlayed: "1 个月前",
            size: "1.2 GB",
            icon: "cube.transparent.fill"
        )
    ]

    static let archive: [DemoInstance] = [
        DemoInstance(
            id: "optifine-1.20.6",
            name: "1.20.6 · OptiFine 1.20.6_HD_U_I7",
            gameVersion: "1.20.6",
            loader: "OptiFine",
            badgeText: "OptiFine",
            badgeTone: .neutral,
            mods: "8",
            lastPlayed: "2 个月前",
            size: "3.1 GB",
            icon: "shippingbox.fill"
        ),
        DemoInstance(
            id: "forge-1.16.5",
            name: "1.16.5 · Forge 36.2.39",
            gameVersion: "1.16.5",
            loader: "Forge 36.2.39",
            badgeText: "Forge",
            badgeTone: .warning,
            mods: "62",
            lastPlayed: "4 个月前",
            size: "7.8 GB",
            icon: "shippingbox.fill"
        ),
        DemoInstance(
            id: "forge-1.12.2",
            name: "1.12.2 · Forge 14.23.5",
            gameVersion: "1.12.2",
            loader: "Forge 14.23.5",
            badgeText: "Forge",
            badgeTone: .warning,
            mods: "134",
            lastPlayed: "去年",
            size: "4.6 GB",
            icon: "shippingbox.fill"
        ),
        DemoInstance(
            id: "snapshot-23w45a",
            name: "23w45a · 快照版本",
            gameVersion: "23w45a",
            loader: "原版快照",
            badgeText: "快照",
            badgeTone: .info,
            mods: "0",
            lastPlayed: "去年",
            size: "1.0 GB",
            icon: "shippingbox.fill"
        )
    ]
}
