import SwiftUI
import AppKit

/// 启动页：真实读取已安装版本，启动/停止游戏，展示运行状态与日志入口。
public struct LaunchPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine

    private let onOpenDownload: () -> Void
    @State private var section = "overview"
    @State private var selectedVersionID: String?

    private let sections: [LauncherSectionItem] = [
        LauncherSectionItem(id: "overview", title: "概览", systemImage: "play.rectangle.fill"),
        LauncherSectionItem(id: "instances", title: "实例", systemImage: "cube.fill"),
        LauncherSectionItem(id: "community", title: "账户与社区", systemImage: "person.2.fill")
    ]

    public init(onOpenDownload: @escaping () -> Void = {}) {
        self.onOpenDownload = onOpenDownload
    }

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
        .task {
            if engine.installedVersions.isEmpty {
                await engine.refreshEnvironment()
            }
        }
        .background {
            Button("") { launchSelected() }
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    // MARK: - 选中的版本

    private var versions: [InstalledVersion] { engine.installedVersions }

    private var selectedVersion: InstalledVersion? {
        let id = selectedVersionID ?? engine.activeVersionID
        if let id, let match = versions.first(where: { $0.id == id }) { return match }
        return versions.first
    }

    // MARK: - 概览

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            heroCard
            quickActions
            recentVersions
        }
    }

    private var heroCard: some View {
        GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.lg) {
            HStack(alignment: .center, spacing: LauncherSpace.lg) {
                LauncherBlockArt(seed: selectedVersion?.id ?? "none", label: selectedVersion?.versionType)
                    .frame(width: 168, height: 104)

                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherLabel("当前实例")
                        if let version = selectedVersion {
                            LauncherBadge(version.versionType, tone: .neutral)
                            LauncherBadge("离线账户 · \(engine.settings.playerName)", tone: .neutral)
                        }
                        Spacer(minLength: 0)
                    }

                    Text(selectedVersion?.id ?? "尚未安装版本")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)

                    if let version = selectedVersion {
                        HStack(spacing: LauncherSpace.lg) {
                            LauncherInlineStat("版本类型", value: version.versionType)
                            LauncherInlineStat("客户端", value: version.jarExists ? "jar 就绪" : "缺少 jar")
                            LauncherInlineStat("上次修改", value: version.lastModified.formatted(date: .abbreviated, time: .omitted))
                            LauncherInlineStat("Java", value: engine.resolvedJavaLabel ?? "自动")
                        }
                    } else {
                        Text("去「下载」安装一个游戏版本，这里会显示启动入口。")
                            .font(LauncherTextStyle.caption.font)
                            .foregroundStyle(theme.colors.textSecondary)
                    }

                    HStack(spacing: LauncherSpace.sm) {
                        if engine.isBusy {
                            LauncherButton("正在处理…", systemImage: "hourglass", variant: .primary, size: .large, isLoading: true) {}
                        } else if case .running = engine.phase {
                            LauncherButton("停止游戏", systemImage: "stop.fill", variant: .danger, size: .large) {
                                engine.stop()
                            }
                        } else {
                            LauncherButton(
                                "启动游戏",
                                systemImage: "play.fill",
                                variant: .primary,
                                size: .large,
                                shortcut: "⌘↩"
                            ) {
                                launchSelected()
                            }
                        }

                        LauncherButton("选择实例", systemImage: "list.bullet.rectangle", variant: .secondary, size: .large) {
                            withAnimation(LauncherMotion.spring) { section = "instances" }
                        }
                        LauncherIconButton(systemImage: "folder", variant: .ghost, size: .medium, accessibilityLabel: "打开游戏目录") {
                            NSWorkspace.shared.open(engine.settings.resolvedGameDirectory)
                        }

                        Spacer(minLength: LauncherSpace.sm)

                        HStack(spacing: LauncherSpace.xs) {
                            LauncherStatusDot(tone: statusTone)
                            Text(engine.statusText)
                                .font(LauncherTextStyle.micro.font)
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    if case .downloading(_, let progress) = engine.phase {
                        LauncherProgressBar(
                            value: progress.fraction,
                            label: "\(progress.phase) · \(progress.completed)/\(progress.total)",
                            tone: .accent,
                            height: 4
                        )
                        .frame(maxWidth: 420)
                    }
                }
            }
        }
    }

    private var statusTone: LauncherBadgeTone {
        switch engine.phase {
        case .failed: return .danger
        case .running: return .success
        case .downloading, .preparing, .launching: return .warning
        case .idle: return engine.installedVersions.isEmpty ? .neutral : .success
        }
    }

    private var quickActions: some View {
        HStack(spacing: LauncherSpace.md) {
            quickAction("新建实例", icon: "plus.square.on.square", detail: "选择版本并安装", action: onOpenDownload)
            quickAction("导入整合包", icon: "shippingbox.fill", detail: "支持 .zip 或链接", action: onOpenDownload)
            quickAction("刷新实例", icon: "arrow.clockwise", detail: "重新扫描本地版本", action: {
                Task { await engine.refreshEnvironment() }
            })
        }
    }

    private func quickAction(_ title: String, icon: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        }
        .buttonStyle(.plain)
        .launcherHoverEffect(scale: 1.01)
    }

    private var recentVersions: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                LauncherSectionHeader(
                    title: "最近游玩",
                    subtitle: engine.installedVersions.isEmpty ? "本地还没有安装任何版本" : "点击切换当前实例",
                    accessory: AnyView(LauncherButton("全部实例", variant: .ghost, size: .small) {
                        withAnimation(LauncherMotion.spring) { section = "instances" }
                    })
                )
                if versions.isEmpty {
                    emptyState
                } else {
                    ForEach(versions.prefix(3)) { version in
                        versionRow(version)
                    }
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
                    subtitle: "共 \(versions.count) 个 · 游戏目录：\(engine.settings.resolvedGameDirectory.path)",
                    accessory: AnyView(LauncherButton("刷新", systemImage: "arrow.clockwise", variant: .secondary, size: .small) {
                        Task { await engine.refreshEnvironment() }
                    })
                )
                if versions.isEmpty {
                    emptyState
                } else {
                    ForEach(versions) { version in
                        versionRow(version)
                    }
                }
                HStack(spacing: LauncherSpace.sm) {
                    LauncherMonoText(
                        "检测到 \(engine.javaRuntimes.count) 个 Java · \(engine.installedVersions.count) 个版本",
                        tone: .tertiary,
                        size: 10
                    )
                    Spacer(minLength: 0)
                    LauncherButton("打开游戏目录", systemImage: "folder", variant: .ghost, size: .small) {
                        NSWorkspace.shared.open(engine.settings.resolvedGameDirectory)
                    }
                    LauncherButton("安装新版本", systemImage: "plus", variant: .secondary, size: .small) {
                        onOpenDownload()
                    }
                }
                .padding(.top, LauncherSpace.xxs)
            }
        }
    }

    private var emptyState: some View {
        LauncherEmptyState(
            systemImage: "cube.transparent",
            title: "还没有安装任何版本",
            message: "前往「下载」选择一个游戏版本或整合包，安装后即可在这里启动。",
            actionTitle: "去下载",
            onAction: onOpenDownload
        )
    }

    private func versionRow(_ version: InstalledVersion) -> some View {
        LauncherListRow(
            title: version.id,
            subtitle: "\(version.versionType) · \(version.jarExists ? "客户端就绪" : "缺少客户端 jar")",
            systemImage: "cube.fill",
            badge: version.versionType,
            accessory: AnyView(
                LauncherMonoText(
                    version.lastModified.formatted(date: .abbreviated, time: .omitted),
                    tone: .tertiary,
                    size: 10
                )
            ),
            isSelected: version.id == selectedVersion?.id,
            action: {
                withAnimation(LauncherMotion.spring) {
                    selectedVersionID = version.id
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
                title: engine.installedVersions.isEmpty ? "尚未安装版本" : "离线启动已就绪",
                message: engine.installedVersions.isEmpty
                    ? "去「下载」安装一个版本后即可启动；账户为离线模式。"
                    : "当前使用离线账户「\(engine.settings.playerName)」，启动无需联网验证。",
                tone: engine.installedVersions.isEmpty ? .warning : .info,
                actionTitle: engine.installedVersions.isEmpty ? "去下载" : nil
            ) {
                onOpenDownload()
            }
        }
    }

    private var accountCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(title: "账户", subtitle: "离线模式 · 正版登录待接入")
                HStack(spacing: LauncherSpace.sm) {
                    LauncherAvatar(name: engine.settings.playerName, systemImage: "person.fill", size: 34, isOnline: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(engine.settings.playerName)
                            .font(LauncherTextStyle.bodyStrong.font)
                            .foregroundStyle(theme.colors.textPrimary)
                        Text("离线 UUID 由用户名生成")
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
                    accessory: AnyView(LauncherBadge("示例数据", tone: .neutral))
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
                    subtitle: "示例数据 · 未接真实资讯",
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

    // MARK: - 行动

    private func launchSelected() {
        guard let version = selectedVersion, !engine.isBusy else { return }
        Task { await engine.launch(versionID: version.id) }
    }
}
