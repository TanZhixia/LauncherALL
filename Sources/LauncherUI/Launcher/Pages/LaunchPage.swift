import SwiftUI

/// 启动页：当前实例、快速开始、实例列表、账户 / 服务器 / 公告。
public struct LaunchPage: View {
    @Environment(\.launcherTheme) private var theme
    @State private var current: LauncherInstance = LauncherDemoData.currentInstance
    @State private var isLaunching = false
    @State private var launchStatus = "已就绪 · 上次退出正常"

    public init() {}

    public var body: some View {
        LauncherAppPage {
            LauncherPageHeader(title: "启动", subtitle: "选择实例，然后开始游戏")
                .padding(.bottom, LauncherSpace.xxs)

            heroCard

            HStack(alignment: .top, spacing: LauncherSpace.lg) {
                VStack(spacing: LauncherSpace.lg) {
                    quickActions
                    instanceList
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: LauncherSpace.md) {
                    accountCard
                    serverCard
                    newsCard
                    banner
                }
                .frame(width: 318)
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

    // MARK: - 当前实例

    private var heroCard: some View {
        GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.lg) {
            HStack(alignment: .center, spacing: LauncherSpace.lg) {
                LauncherBlockArt(seed: current.name, label: current.version)
                    .frame(width: 208, height: 128)

                VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherLabel("当前实例")
                        LauncherBadge(current.loader, tone: .neutral)
                        LauncherBadge(current.java, tone: .neutral, systemImage: "cup.and.saucer.fill")
                        Spacer(minLength: 0)
                    }

                    Text(current.name)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.colors.textPrimary)

                    HStack(spacing: LauncherSpace.lg) {
                        LauncherInlineStat("游戏版本", value: current.version, isMono: true)
                        LauncherInlineStat("模组", value: "\(current.modCount) 个")
                        LauncherInlineStat("占用空间", value: current.size, isMono: true)
                        LauncherInlineStat("上次游玩", value: current.lastPlayed)
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

                        Spacer(minLength: LauncherSpace.sm)

                        HStack(spacing: LauncherSpace.xs) {
                            LauncherStatusDot(tone: isLaunching ? .warning : .success)
                            Text(launchStatus)
                                .font(LauncherTextStyle.micro.font)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                    .padding(.top, LauncherSpace.xxs)
                }

                Spacer(minLength: LauncherSpace.lg)

                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    LauncherLabel("运行环境")
                    LauncherKeyValueRow(key: "Java", value: "\(current.java) · 4096 MB", isMono: true)
                    LauncherKeyValueRow(key: "版本隔离", value: "已开启")
                    LauncherKeyValueRow(key: "上次退出", value: "正常")
                }
                .frame(width: 196)
            }
        }
    }

    // MARK: - 快速开始

    private var quickActions: some View {
        HStack(spacing: LauncherSpace.md) {
            quickAction("新建实例", icon: "plus.square.on.square", detail: "选择版本并创建")
            quickAction("导入整合包", icon: "shippingbox.fill", detail: "支持 .zip / 整合包链接")
            quickAction("浏览服务器", icon: "network", detail: "12 个收藏服务器")
        }
    }

    private func quickAction(_ title: String, icon: String, detail: String) -> some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            HStack(spacing: LauncherSpace.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 30, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                            .fill(theme.colors.surfaceSubtle)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(LauncherTextStyle.bodyStrong.font)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(detail)
                        .font(LauncherTextStyle.micro.font)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .launcherHoverEffect(scale: 1.01)
    }

    // MARK: - 实例列表

    private var instanceList: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "已安装实例",
                    subtitle: "共 \(LauncherDemoData.instances.count) 个 · 点击切换当前实例",
                    accessory: AnyView(LauncherButton("新建", systemImage: "plus", variant: .secondary, size: .small) {})
                )

                VStack(spacing: LauncherSpace.xxs) {
                    ForEach(LauncherDemoData.instances) { instance in
                        LauncherListRow(
                            title: instance.name,
                            subtitle: "模组 \(instance.modCount) 个 · 上次游玩 \(instance.lastPlayed)",
                            systemImage: "cube.fill",
                            badge: instance.loader,
                            accessory: AnyView(
                                LauncherMonoText(instance.size, tone: .tertiary, size: 10)
                            ),
                            isSelected: instance.id == current.id,
                            action: {
                                withAnimation(LauncherMotion.spring) {
                                    current = instance
                                    launchStatus = "已就绪 · 上次退出正常"
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - 右栏

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
                LauncherButton("切换账户", systemImage: "arrow.triangle.2.circlepath", variant: .secondary, size: .small, isFullWidth: true) {}
            }
        }
    }

    private var serverCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "服务器状态",
                    subtitle: "2 个收藏 · 1 个离线",
                    accessory: AnyView(LauncherBadge("全部在线", tone: .success))
                )
                ForEach(LauncherDemoData.servers) { server in
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherStatusDot(tone: server.isOnline ? .success : .neutral)
                        VStack(alignment: .leading, spacing: 1) {
                            LauncherMonoText(server.name, tone: .primary, size: 11)
                            Text(server.region)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Text(server.players)
                            .font(LauncherTextStyle.micro.font)
                            .foregroundStyle(theme.colors.textSecondary)
                        LauncherMonoText(server.isOnline ? "\(server.ping) ms" : "离线", tone: .tertiary, size: 10)
                    }
                }
            }
        }
    }

    private var newsCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "新闻与公告",
                    subtitle: "来自 Minecraft 官网",
                    accessory: AnyView(
                        LauncherIconButton(systemImage: "arrow.up.right", variant: .ghost, size: .small, accessibilityLabel: "打开官网") {}
                    )
                )
                ForEach(LauncherDemoData.news.prefix(2)) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: LauncherSpace.xs) {
                            LauncherBadge(item.category, tone: .neutral)
                            Spacer(minLength: 0)
                            LauncherMonoText(item.date, tone: .tertiary, size: 9)
                        }
                        Text(item.title)
                            .font(LauncherTextStyle.bodyStrong.font)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                        Text(item.summary)
                            .font(LauncherTextStyle.micro.font)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var banner: some View {
        LauncherBanner(
            title: "Java 21 已就绪",
            message: "检测到 2 个可更新模组，建议启动前完成更新。",
            tone: .info,
            actionTitle: "查看详情"
        ) {}
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
