import SwiftUI
import AppKit

/// 启动页（PCL 式布局）：左侧实例列表 + 右侧启动区 / 运行状态 / 启动日志 / 最近启动。
/// 实例管理（重命名 / 复制 / 校验 / 删除）、日志跳转、导入整合包入口全部走真实文件操作与全局路由。
public struct LaunchPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(AccountStore.self) private var accountStore
    @Environment(LauncherRouter.self) private var router
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    @State private var selectedVersionID: String?
    @State private var filter = ""
    @State private var instanceSizeText: String?
    @State private var isBusyAction = false

    public init() {}

    public var body: some View {
        LauncherPageLayout(sideWidth: 300) {
            sidePanel
        } main: {
            LauncherMainPanel {
                mainHeader
                launchCard
                statusCard
                quickRow
                recentLaunchesCard
            }
        }
        .task {
            if engine.installedVersions.isEmpty {
                await engine.refreshEnvironment()
            }
            if selectedVersionID == nil {
                selectedVersionID = engine.settings.lastLaunchedVersionID ?? engine.installedVersions.first?.id
            }
        }
        .task(id: selectedVersion?.id) {
            await loadInstanceSize()
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
            width: 300,
            searchText: $filter,
            searchPlaceholder: "搜索实例",
            toolbar: AnyView(
                HStack(spacing: LauncherSpace.xxs) {
                    LauncherIconButton(
                        systemImage: "arrow.clockwise",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: "刷新实例",
                        isDisabled: isBusyAction
                    ) {
                        refreshInstances()
                    }
                    LauncherIconButton(
                        systemImage: "plus",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: "安装新实例"
                    ) {
                        openDownload()
                    }
                }
            ),
            content: {
                if versions.isEmpty {
                    LauncherEmptyState(
                        systemImage: "cube.transparent",
                        title: "没有实例",
                        message: "去「下载」安装一个版本。",
                        actionTitle: "去下载",
                        onAction: openDownload
                    )
                } else {
                    LauncherSidePanelGroup("已安装", trailing: "\(filteredVersions.count)")
                    ForEach(filteredVersions) { version in
                        instanceRow(version)
                            .launcherContextMenu(instanceMenuGroups(for: version))
                    }
                }
            },
            footer: {
                VStack(spacing: LauncherSpace.sm) {
                    Rectangle()
                        .fill(theme.colors.stroke)
                        .frame(height: 1)

                    if engine.isBusy {
                        LauncherButton(
                            "正在处理…",
                            systemImage: "hourglass",
                            variant: .primary,
                            size: .large,
                            isLoading: true,
                            isFullWidth: true
                        ) {}
                    } else if case .running = engine.phase {
                        LauncherButton("停止游戏", systemImage: "stop.fill", variant: .danger, size: .large, isFullWidth: true) {
                            engine.stop()
                            router.showToast("已请求停止游戏", tone: .warning)
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
                                LauncherMenuItem(
                                    version.id,
                                    systemImage: version.id == selectedVersion?.id ? "checkmark" : "cube.fill"
                                ) {
                                    selectedVersionID = version.id
                                }
                            })
                        ]
                    )

                    Button {
                        router.go(.settings, settingsSection: "account")
                    } label: {
                        HStack(spacing: LauncherSpace.xs) {
                            if accountStore.selectedAccount.isMicrosoft {
                                MinecraftAvatarView(
                                    uuid: accountStore.selectedAccount.uuid,
                                    name: accountStore.selectedAccount.name,
                                    size: 22
                                )
                            } else {
                                LauncherAvatar(
                                    name: accountStore.selectedAccount.name,
                                    systemImage: "person.fill",
                                    size: 22,
                                    isOnline: false
                                )
                            }
                            Text(accountStore.selectedAccount.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            LauncherBadge(
                                accountStore.selectedAccount.isMicrosoft ? "正版" : "离线",
                                tone: accountStore.selectedAccount.isMicrosoft ? .accent : .neutral
                            )
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        .padding(.horizontal, LauncherSpace.xxs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .launcherPointer()
                    .help("管理账户（离线 / 正版）")
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
            subtitle: version.jarExists ? version.versionType : "缺少客户端 jar",
            systemImage: "cube.fill",
            badge: version.id == engine.settings.lastLaunchedVersionID ? "最近" : nil,
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
            subtitle: selectedVersion.map {
                "\($0.versionType) · \($0.jarExists ? "客户端就绪" : "缺少客户端 jar") · \(engine.settings.gameDirectory(for: $0.id).lastPathComponent)"
            }
        ) {
            HStack(spacing: LauncherSpace.xs) {
                if let version = selectedVersion {
                    LauncherMenuButton(
                        "实例操作",
                        systemImage: "ellipsis.circle",
                        variant: .ghost,
                        size: .small,
                        groups: instanceMenuGroups(for: version)
                    )
                }
                LauncherIconButton(
                    systemImage: "folder",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: "打开游戏目录"
                ) {
                    openGameDirectory()
                }
            }
        }
    }

    /// 实例操作菜单：真实文件动作 + 路由跳转。
    private func instanceMenuGroups(for version: InstalledVersion) -> [LauncherMenuGroup] {
        [
            LauncherMenuGroup(items: [
                LauncherMenuItem("打开版本目录", systemImage: "folder", action: {
                    InstanceActions.open(engine.installation.versionDirectory(version.id))
                }),
                LauncherMenuItem("在访达中显示", systemImage: "arrow.up.forward.app", action: {
                    InstanceActions.reveal(engine.installation.versionDirectory(version.id))
                }),
                LauncherMenuItem("打开模组目录", systemImage: "puzzlepiece.extension", action: {
                    openModsDirectory(for: version.id)
                })
            ]),
            LauncherMenuGroup(items: [
                LauncherMenuItem("重命名实例", systemImage: "pencil", action: {
                    promptRename(version)
                }),
                LauncherMenuItem("复制实例", systemImage: "doc.on.doc", action: {
                    promptDuplicate(version)
                }),
                LauncherMenuItem("校验文件完整性", systemImage: "checkmark.shield", action: {
                    verifyInstance(version)
                })
            ]),
            LauncherMenuGroup(items: [
                LauncherMenuItem("查看启动日志", systemImage: "text.alignleft", action: {
                    router.go(.more, moreSection: "logs")
                }),
                LauncherMenuItem("复制启动命令", systemImage: "terminal", action: {
                    copyLastCommand()
                }),
                LauncherMenuItem("安装新版本", systemImage: "plus", action: openDownload)
            ]),
            LauncherMenuGroup(items: [
                LauncherMenuItem("删除实例", systemImage: "trash", tone: .danger, action: {
                    confirmDelete(version)
                })
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
                            LauncherBadge(
                                accountStore.selectedAccount.name,
                                tone: .neutral,
                                systemImage: accountStore.selectedAccount.isMicrosoft ? "checkmark.seal.fill" : "person.fill"
                            )
                            LauncherBadge(javaLabel(for: version), tone: .neutral, systemImage: "cup.and.saucer.fill")
                            LauncherBadge(
                                version.jarExists ? "客户端就绪" : "缺少 jar",
                                tone: version.jarExists ? .success : .danger
                            )
                        }
                        Spacer(minLength: 0)
                        if let version = selectedVersion {
                            LauncherMenuButton(
                                "实例操作",
                                systemImage: "ellipsis",
                                variant: .ghost,
                                size: .small,
                                groups: instanceMenuGroups(for: version)
                            )
                        }
                    }

                    if let version = selectedVersion {
                        HStack(spacing: LauncherSpace.lg) {
                            LauncherInlineStat("上次修改", value: version.lastModified.formatted(date: .abbreviated, time: .omitted))
                            LauncherInlineStat("内存", value: "\(engine.settings.maxMemoryMB) MB")
                            LauncherInlineStat("实例占用", value: instanceSizeText ?? (snapshotMode ? "—" : "统计中…"), isMono: true)
                        }
                    }

                    HStack(spacing: LauncherSpace.sm) {
                        LauncherStatusDot(tone: statusTone)
                        Text(engine.statusText)
                            .font(LauncherTextStyle.caption.font)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if engine.lastCommandLine != nil {
                            LauncherButton("复制启动命令", systemImage: "doc.on.doc", variant: .ghost, size: .small) {
                                copyLastCommand()
                            }
                        }
                        LauncherButton("完整日志", systemImage: "text.alignleft", variant: .ghost, size: .small) {
                            router.go(.more, moreSection: "logs")
                        }
                    }

                    if case .downloading(let versionID, let progress) = engine.phase {
                        LauncherProgressBar(
                            value: progress.fraction,
                            label: "\(versionID) · \(progress.phase) · \(progress.completed)/\(progress.total)",
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
                            openDownload()
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
                                LauncherMenuItem("复制启动命令", systemImage: "doc.on.doc", action: copyLastCommand),
                                LauncherMenuItem("清空日志", systemImage: "trash", tone: .danger, action: {
                                    confirmClearLog()
                                }),
                                LauncherMenuItem("在更多页查看", systemImage: "arrow.up.right", action: {
                                    router.go(.more, moreSection: "logs")
                                })
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
                            Text(verbatim: line)
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
            quickAction("新建实例", icon: "plus.square.on.square", detail: "选择版本并安装", action: openDownload)
            quickAction("导入整合包", icon: "shippingbox.fill", detail: "支持 .mrpack / .zip", action: importModpack)
            quickAction("刷新实例", icon: "arrow.clockwise", detail: "重新扫描本地版本", action: refreshInstances)
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

    // MARK: - 最近启动（真实历史）

    private var recentLaunchesCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                LauncherSectionHeader(
                    title: "最近启动",
                    subtitle: "由真实启动记录生成，最多显示 3 条",
                    accessory: AnyView(
                        LauncherBadge("\(engine.settings.launchRecords.count) 条", tone: .neutral)
                    )
                )

                let records = engine.settings.recentLaunches(limit: 3)
                if records.isEmpty {
                    Text("还没有启动记录，点「启动游戏」后会在这里留下真实运行结果。")
                        .textStyle(.micro, tone: .tertiary)
                        .padding(.vertical, LauncherSpace.xs)
                } else {
                    ForEach(records) { record in
                        launchRecordRow(record)
                    }
                }

                HStack(spacing: LauncherSpace.xs) {
                    LauncherHintIcon(accountStore.selectedAccount.isMicrosoft
                        ? "当前使用正版账户启动，需要联网验证；令牌过期会自动刷新。"
                        : "启动器当前为离线账户模式，启动无需联网验证。")
                    Text("\(accountStore.selectedAccount.isMicrosoft ? "正版账户" : "离线账户模式") · 游戏目录 \(engine.settings.resolvedGameDirectory.lastPathComponent) · \(engine.javaRuntimes.count) 个 Java")
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func launchRecordRow(_ record: LaunchRecord) -> some View {
        HStack(alignment: .center, spacing: LauncherSpace.sm) {
            Image(systemName: "cube.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 18, height: 18)
                .background {
                    RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                        .fill(theme.colors.surfaceSubtle)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(record.versionID)
                    .font(LauncherTextStyle.bodyStrong.font)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(LauncherTextStyle.micro.font)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let duration = record.durationText {
                LauncherMonoText(duration, tone: .tertiary, size: 9)
            }
            LauncherBadge(
                record.resultText,
                tone: record.exitCode == nil ? .neutral : (record.exitCode == 0 ? .success : .danger)
            )        }
    }

    // MARK: - 行动

    /// 清空日志（危险操作，先确认）。
    private func confirmClearLog() {
        router.showDialog(
            LauncherDialogRequest(
                title: "清空启动日志？",
                message: "当前会话的 \(engine.logLines.count) 行日志会被清空，已导出的日志文件不受影响。",
                confirmTitle: "清空",
                isDestructive: true,
                onConfirm: {
                    engine.clearLog()
                    router.showToast("日志已清空", tone: .info)
                }
            )
        )
    }

    private func launchSelected() {
        guard let version = selectedVersion else {
            router.showToast("还没有可启动的实例，先去下载页安装", tone: .warning)
            return
        }
        guard !engine.isBusy else {
            router.showToast("当前有任务在进行，请稍候", tone: .warning)
            return
        }
        Task { await engine.launch(versionID: version.id) }
    }

    private func openDownload() {
        router.go(.download)
    }

    private func importModpack() {
        router.pendingDownloadAction = "import-modpack"
        router.go(.download)
    }

    private func refreshInstances() {
        guard !isBusyAction else { return }
        isBusyAction = true
        Task {
            await engine.refreshEnvironment()
            isBusyAction = false
            router.showToast("已刷新：\(engine.installedVersions.count) 个实例 · \(engine.javaRuntimes.count) 个 Java")
        }
    }

    private func openGameDirectory() {
        let directory = selectedVersion.map { engine.settings.gameDirectory(for: $0.id) }
            ?? engine.settings.resolvedGameDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if InstanceActions.open(directory) {
            router.showToast("已打开游戏目录", tone: .info)
        } else {
            router.showToast("无法打开目录：\(directory.path)", tone: .danger)
        }
    }

    private func openModsDirectory(for versionID: String) {
        let directory = engine.settings.gameDirectory(for: versionID)
            .appendingPathComponent("mods", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        InstanceActions.open(directory)
    }

    private func copyLastCommand() {
        guard let command = engine.lastCommandLine else {
            router.showToast("还没有启动命令，先启动一次游戏", tone: .warning)
            return
        }
        InstanceActions.copy(command)
        router.showToast("启动命令已复制到剪贴板")
    }

    private func verifyInstance(_ version: InstalledVersion) {
        Task {
            if let result = await engine.verifyInstalled(versionID: version.id) {
                router.showToast(result.summary, tone: result.isHealthy ? .success : .warning)
            } else {
                router.showToast("校验失败，请查看日志", tone: .danger)
            }
        }
    }

    private func promptRename(_ version: InstalledVersion) {
        router.showPrompt(
            LauncherPromptRequest(
                title: "重命名实例",
                message: "会同时重命名版本目录与 json/jar 文件，已启动过的记录不受影响。",
                placeholder: "实例名",
                initialValue: version.id,
                confirmTitle: "重命名",
                validate: { name in
                    if InstanceActions.normalizedInstanceName(name) == nil { return "名称不合法（不能包含 / \\ : * ? \" < > |）" }
                    if name != version.id, versions.contains(where: { $0.id == name }) { return "实例 \(name) 已存在" }
                    return nil
                },
                onConfirm: { name in
                    guard name != version.id else { return }
                    do {
                        let newID = try InstanceActions.rename(
                            versionID: version.id,
                            to: name,
                            installation: engine.installation
                        )
                        selectedVersionID = newID
                        Task {
                            await engine.refreshEnvironment()
                            router.showToast("已重命名为 \(newID)")
                        }
                    } catch {
                        router.showToast(error.localizedDescription, tone: .danger)
                    }
                }
            )
        )
    }

    private func promptDuplicate(_ version: InstalledVersion) {
        let baseName = "\(version.id)-副本"
        router.showPrompt(
            LauncherPromptRequest(
                title: "复制实例",
                message: "会复制整个版本目录（含模组与配置），并改写新目录的版本 JSON id。",
                placeholder: "新实例名",
                initialValue: baseName,
                confirmTitle: "复制",
                validate: { name in
                    if InstanceActions.normalizedInstanceName(name) == nil { return "名称不合法" }
                    if versions.contains(where: { $0.id == name }) { return "实例 \(name) 已存在" }
                    return nil
                },
                onConfirm: { name in
                    do {
                        let newID = try InstanceActions.duplicate(
                            versionID: version.id,
                            as: name,
                            installation: engine.installation
                        )
                        selectedVersionID = newID
                        Task {
                            await engine.refreshEnvironment()
                            router.showToast("已复制为 \(newID)")
                        }
                    } catch {
                        router.showToast(error.localizedDescription, tone: .danger)
                    }
                }
            )
        )
    }

    private func confirmDelete(_ version: InstalledVersion) {
        router.showDialog(
            LauncherDialogRequest(
                title: "删除实例 \(version.id)？",
                message: "版本目录会被移到废纸篓（可从废纸篓恢复），模组、存档与配置都会一起删除。",
                confirmTitle: "移到废纸篓",
                isDestructive: true,
                onConfirm: {
                    do {
                        try engine.deleteVersion(version.id)
                        if selectedVersionID == version.id {
                            selectedVersionID = engine.installedVersions.first?.id
                        }
                        router.showToast("已删除实例 \(version.id)", tone: .warning)
                    } catch {
                        router.showToast(error.localizedDescription, tone: .danger)
                    }
                }
            )
        )
    }

    // MARK: - 派生信息

    /// 实例真实需要的 Java 标签：读版本 JSON 的 javaVersion。
    private func javaLabel(for version: InstalledVersion) -> String {
        if let major = engine.requiredJavaMajor(for: version.id) {
            if let runtime = engine.resolvedJava(for: major) {
                return "Java \(runtime.majorVersion)"
            }
            return "需要 Java \(major)"
        }
        if let runtime = engine.javaRuntimes.max(by: { $0.majorVersion < $1.majorVersion }) {
            return "Java \(runtime.majorVersion)"
        }
        return "自动 Java"
    }

    private func loadInstanceSize() async {
        guard !snapshotMode, let version = selectedVersion else {
            instanceSizeText = nil
            return
        }
        let directory = engine.settings.gameDirectory(for: version.id)
        instanceSizeText = await Task.detached(priority: .utility) {
            InstanceActions.sizeText(of: directory)
        }.value
    }
}
