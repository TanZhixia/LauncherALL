import SwiftUI

/// 启动页：页内三个分区（概览 / 实例 / 社区），最小窗口下无需滚动。
public struct LaunchPage: View {
    @Environment(\.launcherTheme) private var theme

    @State private var section = "overview"
    @State private var current: LauncherInstance = LauncherDemoData.currentInstance
    @State private var isLaunching = false
    @State private var launchStatus = "已就绪 · 上次退出正常"

    private let sections: [LauncherSectionItem] = [
        LauncherSectionItem(id: "overview", title: "概览", systemImage: "play.rectangle.fill"),
        LauncherSectionItem(id: "instances", title: "实例", systemImage: "cube.fill", badge: "\(LauncherDemoData.instances.count)"),
        LauncherSectionItem(id: "community", title: "账户与社区", systemImage: "person.2.fill")
    ]

    public init() {}

    public var body: some View {
        LauncherAppPage {
            LauncherPageHeader(title: "启动", subtitle: "选择实例，然后开始游戏")

            LauncherSectionLayout {
                LauncherSectionRail(items: sections, selection: $section, header: nil)
            } content: {
                switch section {
                case "instances": instancesSection
                case "community": communitySection
                default: overviewSection
                }
            }
        }
        .background {
            Button("") { startGame() }
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    // MARK: - 概览

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            heroCard
            quickActions
            recentInstances
        }
    }

    private var heroCard: some View {
        GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.lg) {
            HStack(alignment: .center, spacing: LauncherSpace.lg) {
                LauncherBlockArt(seed: current.name, label: current.version)
                    .frame(width: 168, height: 104)

                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherLabel("当前实例")
                        LauncherBadge(current.loader, tone: .neutral)
                        LauncherBadge(current.java, tone: .neutral, systemImage: "cup.and.saucer.fill")
                        Spacer(minLength: 0)
                    }

                    Text(current.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: LauncherSpace.lg) {
                        LauncherInlineStat("游戏版本", value: current.version, isMono: true)
                        LauncherInlineStat("模组", value: "\(current.modCount) 个")
                        LauncherInlineStat("占用空间", value: current.size, isMono: true)
                        LauncherInlineStat("上次游玩", value: current.lastPlayed)
                        LauncherInlineStat("Java", value: current.java, isMono: true)
                    }

                    HStack(spacing: LauncherSpace.sm) {
                        LauncherButton(
                            isLaunching ? "正在启动…" : "启动游戏",
                            systemImage: "play.fill",
                            variant: .primary,
                            size: .large,
                            isLoading: isLaunching,
                            shortcut: "⌘↩"
                        ) {
                            startGame()
                        }
                        LauncherButton("选择版本", systemImage: "list.bullet.rectangle", variant: .secondary, size: .large) {}
                        LauncherIconButton(systemImage: "ellipsis", variant: .ghost, size: .medium, accessibilityLabel: "更多实例操作") {}
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: LauncherSpace.xs) {
                        LauncherStatusDot(tone: isLaunching ? .warning : .success)
                        Text(launchStatus)
                            .font(LauncherTextStyle.micro.font)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        LauncherMonoText("版本隔离 已开启", tone: .tertiary, size: 10)
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: LauncherSpace.md) {
            quickAction("新建实例", icon: "plus.square.on.square", detail: "选择版本并创建")
            quickAction("导入整合包", icon: "shippingbox.fill", detail: "支持 .zip 或链接")
            quickAction("浏览服务器", icon: "network", detail: "12 个收藏服务器")
        }
    }

    private func quickAction(_ title: String, icon: String, detail: String) -> some View {
        LauncherCard(level: .regular, padding: LauncherSpace.sm) {
            HStack(spacing: LauncherSpace.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                            .fill(theme.colors.surfaceSubtle)
                    }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(LauncherTextStyle.bodyStrong.font)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .launcherHoverEffect(scale: 1.01)
    }

    private var recentInstances: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                LauncherSectionHeader(
                    title: "最近游玩",
                    subtitle: "点击切换当前实例",
                    accessory: AnyView(LauncherButton("全部实例", variant: .ghost, size: .small) {
                        withAnimation(LauncherMotion.spring) { section = "instances" }
                    })
                )
                ForEach(LauncherDemoData.instances.prefix(3)) { instance in
                    instanceRow(instance)
                }
            }
        }
    }

    // MARK: - 实例

    private var instancesSection: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "已安装实例",
                    subtitle: "共 \(LauncherDemoData.instances.count) 个 · 当前：\(current.name)",
                    accessory: AnyView(LauncherButton("新建", systemImage: "plus", variant: .secondary, size: .small) {})
                )
                ForEach(LauncherDemoData.instances) { instance in
                    instanceRow(instance)
                }
                HStack(spacing: LauncherSpace.sm) {
                    LauncherMonoText("共 4 个实例 · 占用 14.9 GB · 2 个版本可更新", tone: .tertiary, size: 10)
                    Spacer(minLength: 0)
                    LauncherButton("导入实例", systemImage: "square.and.arrow.down", variant: .ghost, size: .small) {}
                }
                .padding(.top, LauncherSpace.xxs)
            }
        }
    }

    private func instanceRow(_ instance: LauncherInstance) -> some View {
        LauncherListRow(
            title: instance.name,
            subtitle: "模组 \(instance.modCount) 个 · 上次游玩 \(instance.lastPlayed)",
            systemImage: "cube.fill",
            badge: instance.loader,
            accessory: AnyView(LauncherMonoText(instance.size, tone: .tertiary, size: 10)),
            isSelected: instance.id == current.id,
            action: {
                withAnimation(LauncherMotion.spring) {
                    current = instance
                    launchStatus = "已就绪 · 上次退出正常"
                }
            }
        )
    }

    // MARK: - 账户与社区

    private var communitySection: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            HStack(alignment: .top, spacing: LauncherSpace.md) {
                accountCard
                serverCard
            }
            newsCard
            LauncherBanner(
                title: "Java 21 已就绪",
                message: "检测到 2 个可更新模组，建议启动前完成更新。",
                tone: .info,
                actionTitle: "查看详情"
            ) {}
        }
    }

    private var accountCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(title: "账户", subtitle: LauncherDemoData.account.type)
                HStack(spacing: LauncherSpace.sm) {
                    LauncherAvatar(name: LauncherDemoData.account.name, systemImage: "person.fill", size: 34, isOnline: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(LauncherDemoData.account.name)
                            .font(LauncherTextStyle.bodyStrong.font)
                            .foregroundStyle(theme.colors.textPrimary)
                        Text("上次登录 \(LauncherDemoData.account.lastLogin)")
                            .font(LauncherTextStyle.micro.font)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: LauncherSpace.sm) {
                    LauncherButton("切换账户", systemImage: "arrow.triangle.2.circlepath", variant: .secondary, size: .small, isFullWidth: true) {}
                    LauncherButton("退出", variant: .ghost, size: .small) {}
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var serverCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "服务器状态",
                    subtitle: "2 个收藏 · 1 个离线",
                    accessory: AnyView(LauncherBadge("全部在线", tone: .success))
                )
                ForEach(LauncherDemoData.servers) { server in
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherStatusDot(tone: server.isOnline ? .success : .neutral)
                        LauncherMonoText(server.name, tone: .primary, size: 11)
                        Text(server.region)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.colors.textTertiary)
                        Spacer(minLength: 0)
                        Text(server.players)
                            .font(LauncherTextStyle.micro.font)
                            .foregroundStyle(theme.colors.textSecondary)
                        LauncherMonoText(server.isOnline ? "\(server.ping) ms" : "离线", tone: .tertiary, size: 10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var newsCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "新闻与公告",
                    subtitle: "来自 Minecraft 官网",
                    accessory: AnyView(LauncherIconButton(systemImage: "arrow.up.right", variant: .ghost, size: .small, accessibilityLabel: "打开官网") {})
                )
                ForEach(LauncherDemoData.news) { item in
                    HStack(alignment: .top, spacing: LauncherSpace.sm) {
                        LauncherBadge(item.category, tone: .neutral)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(LauncherTextStyle.bodyStrong.font)
                                .foregroundStyle(theme.colors.textPrimary)
                                .lineLimit(1)
                            Text(item.summary)
                                .font(LauncherTextStyle.micro.font)
                                .foregroundStyle(theme.colors.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        LauncherMonoText(item.date, tone: .tertiary, size: 9)
                    }
                }
            }
        }
    }

    // MARK: - 交互

    private func startGame() {
        guard !isLaunching else { return }
        isLaunching = true
        launchStatus = "正在启动 \(current.name)…"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            isLaunching = false
            launchStatus = "运行中 · 已启动 0 分钟"
        }
    }
}
