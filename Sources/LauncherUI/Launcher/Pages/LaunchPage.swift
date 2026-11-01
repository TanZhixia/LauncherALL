import SwiftUI
import AppKit

/// 启动页（PCL 式布局）：左侧实例列表 + 右侧启动区 / 运行状态 / 启动日志。
public struct LaunchPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine

    private let onOpenDownload: () -> Void
    @State private var selectedVersionID: String?
    @State private var filter = ""

    public init(onOpenDownload: @escaping () -> Void = {}) {
        self.onOpenDownload = onOpenDownload
    }

    public var body: some View {
        LauncherPageLayout(sideWidth: 300) {
            sidePanel
        } main: {
            LauncherMainPanel {
                mainHeader
                launchCard
                statusCard
                quickRow
                homepageCard
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

    // MARK: - 左侧实例列表

    private var sidePanel: some View {
        LauncherSidePanel(
            title: "游戏实例",
            count: "\(versions.count)",
            searchText: $filter,
            searchPlaceholder: "搜索实例",
            toolbar: AnyView(
                LauncherIconButton(systemImage: "arrow.clockwise", variant: .ghost, size: .small, accessibilityLabel: "刷新实例") {
                    Task { await engine.refreshEnvironment() }
                }
            ),
            content: {
                if versions.isEmpty {
                    VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                        LauncherEmptyState(
                            systemImage: "cube.transparent",
                            title: "没有实例",
                            message: "去「下载」安装一个版本。",
                            actionTitle: "去下载",
                            onAction: onOpenDownload
                        )
                    }
                } else {
                    LauncherSidePanelGroup("已安装", trailing: "\(filteredVersions.count)")
                    ForEach(filteredVersions) { version in
                        instanceRow(version)
                    }
                }
            },
            footer: {
                VStack(spacing: LauncherSpace.sm) {
                    Rectangle()
                        .fill(theme.colors.stroke)
                        .frame(height: 1)

                    if engine.isBusy {
                        LauncherButton("正在处理…", systemImage: "hourglass", variant: .primary, size: .large, isLoading: true, isFullWidth: true) {}
                    } else if case .running = engine.phase {
                        LauncherButton("停止游戏", systemImage: "stop.fill", variant: .danger, size: .large, isFullWidth: true) {
                            engine.stop()
                        }
                    } else {
                        LauncherButton("启动游戏", systemImage: "play.fill", variant: .primary, size: .large, isFullWidth: true) {
                            launchSelected()
                        }
                    }

                    LauncherMenuButton(
                        selectedVersion?.id ?? "选择版本",
                        systemImage: "chevron.up.chevron.down",
                        variant: .secondary,
                        size: .small,
                        isFullWidth: true,
                        groups: [
                            LauncherMenuGroup(title: "已安装实例", items: versions.map { version in
                                LauncherMenuItem(version.id, systemImage: "cube.fill") {
                                    selectedVersionID = version.id
                                }
                            })
                        ]
                    )

                    HStack(spacing: LauncherSpace.xs) {
                        LauncherAvatar(name: engine.settings.playerName, systemImage: "person.fill", size: 22, isOnline: true)
                        Text(engine.settings.playerName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.colors.textSecondary)
                        Spacer(minLength: 0)
                        LauncherBadge("离线", tone: .neutral)
                        LauncherIconButton(systemImage: "plus", variant: .ghost, size: .small, accessibilityLabel: "新建实例") {
                            onOpenDownload()
                        }
                    }
                    .padding(.horizontal, LauncherSpace.xxs)
                }
            }
        )
    }

    private var versions: [InstalledVersion] { engine.installedVersions }

    private var filteredVersions: [InstalledVersion] {
        guard !filter.isEmpty else { return versions }
        return versions.filter { $0.id.localizedCaseInsensitiveContains(filter) }
    }

    private var selectedVersion: InstalledVersion? {
        let id = selectedVersionID ?? engine.activeVersionID
        if let id, let match = versions.first(where: { $0.id == id }) { return match }
        return versions.first
    }

    private func instanceRow(_ version: InstalledVersion) -> some View {
        LauncherListRow(
            title: version.id,
            subtitle: version.jarExists ? version.versionType : "缺少 jar",
            systemImage: "cube.fill",
            badge: nil,
            accessory: AnyView(
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.colors.textTertiary)
            ),
            isSelected: version.id == selectedVersion?.id,
            action: {
                withAnimation(LauncherMotion.spring) {
                    selectedVersionID = version.id
                }
            }
        )
    }

    // MARK: - 右侧启动区

    private var mainHeader: some View {
        LauncherPanelHeader(
            selectedVersion?.id ?? "启动游戏",
            subtitle: selectedVersion.map { "\($0.versionType) · \($0.jarExists ? "客户端就绪" : "缺少客户端 jar") · \(engine.settings.resolvedGameDirectory.lastPathComponent)" }
        ) {
            HStack(spacing: LauncherSpace.xs) {
                LauncherMenuButton("实例操作", systemImage: "ellipsis.circle", variant: .ghost, size: .small, groups: instanceMenuGroups)
                LauncherIconButton(systemImage: "folder", variant: .ghost, size: .small, accessibilityLabel: "打开游戏目录") {
                    NSWorkspace.shared.open(engine.settings.gameDirectory(for: selectedVersion?.id ?? ""))
                }
            }
        }
    }

    private var instanceMenuGroups: [LauncherMenuGroup] {
        [
            LauncherMenuGroup(items: [
                LauncherMenuItem("打开版本目录", systemImage: "folder", action: {
                    guard let id = selectedVersion?.id else { return }
                    NSWorkspace.shared.open(engine.settings.gameDirectory(for: id))
                }),
                LauncherMenuItem("复制启动命令", systemImage: "doc.on.doc", action: {
                    if let command = engine.lastCommandLine {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                })
            ]),
            LauncherMenuGroup(items: [
                LauncherMenuItem("查看启动日志", systemImage: "text.alignleft"),
                LauncherMenuItem("安装新版本", systemImage: "plus", action: onOpenDownload)
            ])
        ]
    }

    private var launchCard: some View {
        GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.lg) {
            HStack(alignment: .center, spacing: LauncherSpace.lg) {
                LauncherBlockArt(seed: selectedVersion?.id ?? "none", label: selectedVersion?.versionType)
                    .frame(width: 148, height: 92)

                VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                    HStack(spacing: LauncherSpace.sm) {
                        if let version = selectedVersion {
                            LauncherBadge(version.versionType, tone: .neutral)
                            LauncherBadge(engine.settings.playerName, tone: .neutral, systemImage: "person.fill")
                            LauncherBadge(engine.resolvedJavaLabel ?? "自动 Java", tone: .neutral, systemImage: "cup.and.saucer.fill")
                            LauncherBadge(version.jarExists ? "客户端就绪" : "缺少 jar", tone: version.jarExists ? .success : .danger)
                        }
                        Spacer(minLength: 0)
                        LauncherMenuButton("实例操作", systemImage: "ellipsis", variant: .ghost, size: .small, groups: instanceMenuGroups)
                    }

                    if let version = selectedVersion {
                        HStack(spacing: LauncherSpace.lg) {
                            LauncherInlineStat("上次修改", value: version.lastModified.formatted(date: .abbreviated, time: .omitted))
                            LauncherInlineStat("内存", value: "\(engine.settings.maxMemoryMB) MB")
                            LauncherInlineStat("版本类型", value: version.versionType)
                        }
                    }

                    HStack(spacing: LauncherSpace.sm) {
                        LauncherStatusDot(tone: statusTone)
                        Text(engine.statusText)
                            .font(LauncherTextStyle.caption.font)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let command = engine.lastCommandLine {
                            LauncherButton("复制启动命令", systemImage: "doc.on.doc", variant: .ghost, size: .small) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(command, forType: .string)
                            }
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

                    if versions.isEmpty {
                        LauncherBanner(
                            title: "还没有安装版本",
                            message: "去「下载」安装一个版本后即可启动。",
                            tone: .warning,
                            actionTitle: "去下载"
                        ) {
                            onOpenDownload()
                        }
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

    // MARK: - 运行状态 / 日志

    private var statusCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "启动日志",
                    subtitle: engine.lastExitCode.map { "上次退出码 \($0)" } ?? "实时输出最后几行",
                    accessory: AnyView(
                        LauncherMenuButton("更多", variant: .ghost, size: .small, groups: [
                            LauncherMenuGroup(items: [
                                LauncherMenuItem("复制命令", systemImage: "doc.on.doc", action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(engine.lastCommandLine ?? "（还没有启动命令）", forType: .string)
                                }),
                                LauncherMenuItem("清空日志", systemImage: "trash", tone: .danger, action: { engine.clearLog() })
                            ])
                        ])
                    )
                )

                if engine.logLines.isEmpty {
                    Text("还没有日志，启动一次游戏后这里会显示实时输出。")
                        .font(LauncherTextStyle.micro.font)
                        .foregroundStyle(theme.colors.textTertiary)
                        .padding(.vertical, LauncherSpace.xs)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(engine.logLines.suffix(4).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(logTone(line))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(LauncherSpace.sm)
                    .background {
                        RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                            .fill(theme.colors.surfaceSubtle)
                    }
                }
            }
        }
    }

    private func logTone(_ line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("错误") || lower.contains("exception") {
            return theme.colors.danger
        }
        if lower.contains("warn") || lower.contains("警告") {
            return theme.colors.warning
        }
        return theme.colors.textSecondary
    }

    // MARK: - 快捷入口

    private var quickRow: some View {
        HStack(spacing: LauncherSpace.md) {
            quickAction("新建实例", icon: "plus.square.on.square", detail: "选择版本并安装", action: onOpenDownload)
            quickAction("导入整合包", icon: "shippingbox.fill", detail: "支持 .zip", action: onOpenDownload)
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
                        .frame(width: 26, height: 26)
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

    // MARK: - 主页（PCL 右侧公告位）

    private var homepageCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "主页",
                    subtitle: "启动器动态与使用提示",
                    accessory: AnyView(LauncherBadge("示例", tone: .neutral))
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
                HStack(spacing: LauncherSpace.xs) {
                    LauncherHintIcon("启动器当前为离线账户模式，启动无需联网验证。")
                    Text("离线账户模式 · 游戏目录 \(engine.settings.resolvedGameDirectory.lastPathComponent)")
                        .font(LauncherTextStyle.micro.font)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
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
