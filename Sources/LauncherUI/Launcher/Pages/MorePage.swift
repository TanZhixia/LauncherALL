import SwiftUI
import AppKit

/// 更多页：工具 / 快捷操作 / 快捷键 / 日志与诊断 / 关于，五个分区一次只显示一个。
public struct MorePage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    /// 打开既有设计系统画廊（由 App 壳注入，通常以 sheet 呈现）。
    private let onOpenGallery: () -> Void

    @State private var section = "tools"
    @State private var selectedToolID: String?
    @State private var exportHint: String?
    @State private var logFeedback: String?
    @State private var logFeedbackTone: LauncherBadgeTone = .success
    @State private var actionMessage = "所有操作都在本地完成，不会上传任何数据。"
    @State private var isCheckingUpdates = false
    @State private var updateMessage = "上次检查：今天 09:20"

    /// 日志视口高度：固定值保证最小窗口下整页不滚动。
    private let logViewportHeight: CGFloat = LauncherSpace.xxxl * 6 + LauncherSpace.xl

    public init(onOpenGallery: @escaping () -> Void = {}) {
        self.onOpenGallery = onOpenGallery
    }

    // MARK: - 分区

    /// 五个分区；日志条数实时同步到 rail 徽标。
    private var sections: [LauncherSectionItem] {
        [
            LauncherSectionItem(
                id: "tools",
                title: "工具",
                systemImage: "square.grid.2x2.fill",
                badge: "\(LauncherDemoData.tools.count)"
            ),
            LauncherSectionItem(id: "actions", title: "快捷操作", systemImage: "bolt.fill"),
            LauncherSectionItem(id: "shortcuts", title: "快捷键", systemImage: "keyboard"),
            LauncherSectionItem(
                id: "logs",
                title: "日志与诊断",
                systemImage: "doc.text.magnifyingglass",
                badge: engine.logLines.isEmpty ? nil : "\(engine.logLines.count)"
            ),
            LauncherSectionItem(id: "about", title: "关于", systemImage: "info.circle.fill", badge: "v0.2.0")
        ]
    }

    public var body: some View {
        LauncherAppPage {
            LauncherPageHeader(title: "更多", subtitle: "工具、备份、日志与设计资源") {
                LauncherButton(
                    "打开设计系统",
                    systemImage: "square.grid.2x2.fill",
                    variant: .secondary,
                    size: .small,
                    shortcut: "⌘⇧D"
                ) {
                    onOpenGallery()
                }
            }

            LauncherSectionLayout {
                LauncherSectionRail(items: sections, selection: $section, header: "更多")
            } content: {
                switch section {
                case "actions": quickActionsSection
                case "shortcuts": shortcutsSection
                case "logs": logsSection
                case "about": aboutSection
                default: toolsSection
                }
            }
        }
    }

    // MARK: - 工具

    /// 六个工具入口：三列两行；「日志与诊断」点击后切换到日志分区，其余显示选中态。
    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            LauncherSectionHeader(
                title: "工具",
                subtitle: "维护、备份与本地资源",
                accessory: AnyView(
                    LauncherBadge(
                        selectedToolName ?? "\(LauncherDemoData.tools.count) 个工具",
                        tone: selectedToolName == nil ? .neutral : .accent
                    )
                )
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: LauncherSpace.md, alignment: .leading),
                    GridItem(.flexible(), spacing: LauncherSpace.md, alignment: .leading),
                    GridItem(.flexible(), spacing: LauncherSpace.md, alignment: .leading)
                ],
                alignment: .leading,
                spacing: LauncherSpace.md
            ) {
                ForEach(LauncherDemoData.tools) { tool in
                    toolCard(tool)
                }
            }

            HStack(spacing: LauncherSpace.xs) {
                Image(systemName: "hand.tap")
                    .textStyle(.micro, tone: .tertiary)
                if let selectedToolName {
                    Text("已选择「\(selectedToolName)」")
                        .textStyle(.micro, tone: .accent)
                } else if engine.logLines.isEmpty {
                    Text("日志与诊断会打开真实启动日志")
                        .textStyle(.micro, tone: .tertiary)
                } else {
                    Text("日志与诊断已记录 \(engine.logLines.count) 行输出")
                        .textStyle(.micro, tone: .tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, LauncherSpace.xxs)
        }
    }

    /// 单个工具卡：图标方块 + 标题/说明 + 计数徽标，底部一行给出打开/已选反馈。
    private func toolCard(_ tool: LauncherToolCard) -> some View {
        let isLogTool = tool.id == "logs"
        let isSelected = selectedToolID == tool.id

        return Button {
            if isLogTool {
                withAnimation(LauncherMotion.spring) {
                    section = "logs"
                }
            } else {
                selectedToolID = tool.id
            }
        } label: {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.sm) {
                    Image(systemName: tool.systemImage)
                        .textStyle(.headline, tone: isSelected ? .accent : .secondary)
                        .frame(width: 30, height: 30)
                        .background {
                            RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                                .fill(theme.colors.surfaceSubtle)
                        }

                    Spacer(minLength: 0)

                    if let badge = tool.badge {
                        LauncherBadge(badge, tone: .neutral)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.title)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    Text(tool.subtitle)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: LauncherSpace.xs) {
                    Text(toolFooterTitle(tool, isSelected: isSelected))
                        .textStyle(.micro, tone: isSelected || isLogTool ? .accent : .tertiary)
                    Spacer(minLength: 0)
                    Image(
                        systemName: isSelected
                            ? "checkmark.circle.fill"
                            : (isLogTool ? "arrow.up.right" : "chevron.right")
                    )
                    .textStyle(.caption, tone: isSelected || isLogTool ? .accent : .tertiary)
                }
            }
            .padding(LauncherSpace.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LauncherGlassBackground(level: .regular, cornerRadius: LauncherRadius.lg)
            }
            .overlay {
                if isSelected || isLogTool {
                    RoundedRectangle(cornerRadius: LauncherRadius.lg, style: .continuous)
                        .strokeBorder(theme.colors.accent.opacity(isSelected ? 1 : 0.45), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: LauncherRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .launcherHoverEffect(scale: 1.008)
        .accessibilityLabel("\(tool.title)：\(tool.subtitle)")
    }

    /// 工具卡底部状态文案。
    private func toolFooterTitle(_ tool: LauncherToolCard, isSelected: Bool) -> String {
        if tool.id == "logs" { return "查看实时日志" }
        return isSelected ? "已选中" : "打开工具"
    }

    // MARK: - 快捷操作

    /// 三个本机动作：打开真实游戏目录、导出真实日志、重置窗口布局（UI 模拟）。
    private var quickActionsSection: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "快捷操作",
                    subtitle: "打开真实目录、导出真实日志，全部在本地执行",
                    accessory: AnyView(LauncherMonoText("本机", tone: .tertiary))
                )

                HStack(spacing: LauncherSpace.md) {
                    LauncherButton(
                        "打开 .minecraft 文件夹",
                        systemImage: "folder",
                        variant: .secondary,
                        size: .medium,
                        isFullWidth: true
                    ) {
                        openGameDirectory()
                    }

                    LauncherButton(
                        "导出日志",
                        systemImage: "square.and.arrow.up",
                        variant: .primary,
                        size: .medium,
                        isFullWidth: true
                    ) {
                        exportLogs()
                    }

                    LauncherButton(
                        "重置窗口布局",
                        systemImage: "rectangle.3.group",
                        variant: .ghost,
                        size: .medium,
                        isFullWidth: true
                    ) {
                        actionMessage = "窗口布局已重置为默认尺寸。"
                    }
                }

                HStack(spacing: LauncherSpace.sm) {
                    if let exportHint {
                        LauncherBadge(
                            exportHint,
                            tone: exportHint.hasPrefix("日志") ? .success : .danger,
                            systemImage: exportHint.hasPrefix("日志") ? "checkmark.circle.fill" : "xmark.octagon.fill"
                        )
                    } else {
                        Image(systemName: "info.circle")
                            .textStyle(.micro, tone: .tertiary)
                        Text(actionMessage)
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: LauncherSpace.md)

                    LauncherMonoText(engine.settings.resolvedGameDirectory.path, tone: .tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - 快捷键

    /// 六条快捷键，两列三行排布。
    private var shortcutsSection: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "快捷键",
                    subtitle: "高频操作少一次点击",
                    accessory: AnyView(LauncherBadge("\(LauncherDemoData.shortcuts.count) 个", tone: .neutral))
                )

                HStack(alignment: .top, spacing: LauncherSpace.xl) {
                    shortcutColumn(Array(LauncherDemoData.shortcuts.prefix(3)))
                    shortcutColumn(Array(LauncherDemoData.shortcuts.dropFirst(3)))
                }
            }
        }
    }

    /// 单列快捷键：左标题右按键的等宽键值行。
    private func shortcutColumn(_ items: [LauncherShortcut]) -> some View {
        VStack(spacing: LauncherSpace.sm) {
            ForEach(items) { shortcut in
                LauncherKeyValueRow(key: shortcut.title, value: shortcut.keys, isMono: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 日志与诊断

    /// 真实启动日志：状态、启动命令、实时输出、复制 / 导出 / 清空。
    private var logsSection: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            logStatusCard
            logConsoleCard
        }
    }

    /// 状态卡：运行状态、退出码、当前版本与三个日志操作。
    private var logStatusCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherBadge(
                        engine.statusText,
                        tone: logStatusTone,
                        systemImage: logStatusIcon
                    )

                    if let exitCode = engine.lastExitCode {
                        LauncherBadge(
                            "退出码 \(exitCode)",
                            tone: exitCode == 0 ? .success : .danger,
                            systemImage: exitCode == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill"
                        )
                    }

                    if let versionID = engine.activeVersionID {
                        LauncherBadge("版本 \(versionID)", tone: .neutral)
                    }

                    Spacer(minLength: LauncherSpace.md)

                    LauncherButton(
                        "清空",
                        systemImage: "trash",
                        variant: .ghost,
                        size: .small,
                        isDisabled: engine.logLines.isEmpty
                    ) {
                        clearLog()
                    }

                    LauncherButton(
                        "复制",
                        systemImage: "doc.on.doc",
                        variant: .secondary,
                        size: .small,
                        isDisabled: engine.logLines.isEmpty
                    ) {
                        copyLog()
                    }

                    LauncherButton(
                        "导出日志",
                        systemImage: "square.and.arrow.up",
                        variant: .secondary,
                        size: .small
                    ) {
                        exportLogFromConsole()
                    }
                }

                commandPreview
            }
        }
    }

    /// 启动命令预览：等宽两行，最长命令省略中段。
    @ViewBuilder
    private var commandPreview: some View {
        if let command = engine.lastCommandLine {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                HStack(spacing: LauncherSpace.xs) {
                    LauncherLabel("启动命令")
                    Spacer(minLength: 0)
                    LauncherMonoText("\(command.count) 字符", tone: .tertiary)
                }
                Text(verbatim: command)
                    .font(LauncherTextStyle.monoSmall.font)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(LauncherSpace.sm)
            .glassBackground(level: .subtle, cornerRadius: LauncherRadius.sm)
        } else {
            HStack(spacing: LauncherSpace.xs) {
                Image(systemName: "command")
                    .textStyle(.micro, tone: .tertiary)
                Text("尚未启动过游戏，暂无启动命令。")
                    .textStyle(.micro, tone: .tertiary)
                Spacer(minLength: 0)
            }
            .padding(LauncherSpace.sm)
            .glassBackground(level: .subtle, cornerRadius: LauncherRadius.sm)
        }
    }

    /// 日志卡：固定高度视口，交互模式滚动并自动跟到底部，离屏模式静态裁切。
    private var logConsoleCard: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherSectionHeader(
                    title: "输出日志",
                    subtitle: "共 \(engine.logLines.count) 行 · 最多保留 600 行 · 实时追加",
                    accessory: AnyView(logHeaderAccessory)
                )

                if engine.logLines.isEmpty {
                    LauncherEmptyState(
                        systemImage: "terminal",
                        title: "还没有日志",
                        message: "启动一次游戏后，这里会显示实时输出。"
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: logViewportHeight)
                } else {
                    logConsole
                        .frame(maxWidth: .infinity)
                        .frame(height: logViewportHeight)
                        .clipShape(RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous))
                        .glassBackground(level: .subtle, cornerRadius: LauncherRadius.md)
                }
            }
        }
    }

    /// 日志卡右上角：操作反馈徽标。
    @ViewBuilder
    private var logHeaderAccessory: some View {
        if let logFeedback {
            LauncherBadge(logFeedback, tone: logFeedbackTone, systemImage: "checkmark.circle.fill")
        } else if engine.isBusy {
            LauncherBadge("运行中", tone: .warning, systemImage: "arrow.triangle.2.circlepath")
        } else {
            LauncherBadge("实时", tone: .neutral, systemImage: "dot.radiowaves.left.and.right")
        }
    }

    /// 日志区本体：离屏静态列表 / 交互滚动列表（空态在卡片里单独处理）。
    @ViewBuilder
    private var logConsole: some View {
        if snapshotMode {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                ForEach(Array(engine.logLines.suffix(18).enumerated()), id: \.offset) { _, line in
                    logLine(line)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(LauncherSpace.sm)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        ForEach(Array(engine.logLines.enumerated()), id: \.offset) { index, line in
                            logLine(line)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LauncherSpace.sm)
                }
                .scrollIndicators(.hidden)
                .onAppear { scrollLogToBottom(proxy, animated: false) }
                .onChange(of: engine.logLines.count) { _, _ in
                    scrollLogToBottom(proxy, animated: true)
                }
            }
        }
    }

    /// 单行日志：mono 11pt，按关键词着色（错误 danger / 警告 warning / 其余 secondary）。
    private func logLine(_ line: String) -> some View {
        Text(verbatim: line.isEmpty ? " " : line)
            .font(LauncherTextStyle.monoSmall.font)
            .foregroundStyle(logTone(for: line).color(in: theme))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 关于

    /// 真实版本信息 + 检查更新 + 设计系统入口。
    private var aboutSection: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(
                    title: "关于",
                    subtitle: "方块启动器",
                    accessory: AnyView(LauncherBadge("v0.2.0", tone: .accent))
                )

                HStack(alignment: .top, spacing: LauncherSpace.xl) {
                    VStack(spacing: LauncherSpace.sm) {
                        LauncherKeyValueRow(key: "版本", value: "v0.2.0", isMono: true)
                        LauncherKeyValueRow(key: "构建日期", value: MorePage.buildDateText, isMono: true)
                        LauncherKeyValueRow(key: "已安装版本", value: "\(engine.installedVersions.count) 个", isMono: true)
                        LauncherKeyValueRow(key: "Java 运行时", value: "\(engine.javaRuntimes.count) 个", isMono: true)
                    }
                    .frame(width: 320, alignment: .leading)

                    VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                        HStack(spacing: LauncherSpace.sm) {
                            LauncherButton(
                                "检查更新",
                                systemImage: "arrow.triangle.2.circlepath",
                                variant: .secondary,
                                size: .small,
                                isLoading: isCheckingUpdates
                            ) {
                                checkForUpdates()
                            }

                            LauncherButton(
                                "设计系统画廊",
                                systemImage: "square.grid.2x2",
                                variant: .secondary,
                                size: .small
                            ) {
                                onOpenGallery()
                            }

                            Spacer(minLength: 0)
                        }

                        HStack(spacing: LauncherSpace.xs) {
                            LauncherStatusDot(tone: isCheckingUpdates ? .warning : .success)
                            Text(updateMessage)
                                .textStyle(.micro, tone: .tertiary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }

                        Text("基于 SwiftUI 构建 · 设计系统 v0.2")
                            .textStyle(.micro, tone: .tertiary)
                    }
                }
            }
        }
    }

    // MARK: - 状态与文案

    /// 构建日期（当天格式化，用于关于卡）。
    private static let buildDateText: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }()

    /// 当前选中的工具名称（未选中时为 nil）。
    private var selectedToolName: String? {
        guard let selectedToolID else { return nil }
        return LauncherDemoData.tools.first { $0.id == selectedToolID }?.title
    }

    /// 运行状态徽标色调。
    private var logStatusTone: LauncherBadgeTone {
        if case .failed = engine.phase { return .danger }
        if engine.isBusy { return .warning }
        if engine.installedVersions.isEmpty { return .neutral }
        return .success
    }

    /// 运行状态徽标图标。
    private var logStatusIcon: String {
        if case .failed = engine.phase { return "xmark.octagon.fill" }
        if engine.isBusy { return "arrow.triangle.2.circlepath" }
        if case .running = engine.phase { return "play.circle.fill" }
        if engine.installedVersions.isEmpty { return "tray" }
        return "checkmark.circle.fill"
    }

    /// 日志行的语义色调。
    private func logTone(for line: String) -> LauncherTextTone {
        let lowered = line.lowercased()
        let errorKeywords = ["error", "exception", "fatal", "失败", "错误", "崩溃", "cannot"]
        if errorKeywords.contains(where: { lowered.contains($0) }) { return .danger }
        let warningKeywords = ["warn", "警告", "deprecated", "重试"]
        if warningKeywords.contains(where: { lowered.contains($0) }) { return .warning }
        return .secondary
    }

    // MARK: - 真实操作

    /// 打开真实游戏目录（配置里解析后的路径）。
    private func openGameDirectory() {
        let url = engine.settings.resolvedGameDirectory
        if NSWorkspace.shared.open(url) {
            actionMessage = "已在访达中打开游戏目录：\(url.path)"
        } else {
            actionMessage = "无法打开游戏目录：\(url.path)"
        }
    }

    /// 快捷操作卡里的导出日志：真实写入桌面并显示 2 秒提示。
    private func exportLogs() {
        let message = writeLogFile()
        exportHint = message
        actionMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if exportHint != nil {
                exportHint = nil
            }
        }
    }

    /// 日志分区里的导出：写入桌面并在日志卡头部显示反馈。
    private func exportLogFromConsole() {
        let message = writeLogFile()
        flashLogFeedback(message, tone: message.hasPrefix("日志") ? .success : .danger)
    }

    /// 复制全部日志到剪贴板。
    private func copyLog() {
        let text = engine.logLines.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        flashLogFeedback("已复制 \(engine.logLines.count) 行日志", tone: .success)
    }

    /// 清空运行时日志缓冲。
    private func clearLog() {
        engine.clearLog()
        flashLogFeedback("日志已清空", tone: .neutral)
    }

    /// 真实写日志文件到桌面，返回结果文案。
    private func writeLogFile() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let now = Date()
        let timestamp = formatter.string(from: now)
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop", isDirectory: true)
        let url = desktop.appendingPathComponent("blocklauncher-log-\(timestamp).log")

        let header = """
        方块启动器日志
        导出时间：\(DateFormatter.localizedString(from: now, dateStyle: .medium, timeStyle: .medium))
        启动命令：\(engine.lastCommandLine ?? "（尚未启动过游戏）")
        退出码：\(engine.lastExitCode.map { String($0) } ?? "—")

        """
        let content = header + engine.logLines.joined(separator: "\n")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "日志已导出到桌面"
        } catch {
            return "导出失败：\(error.localizedDescription)"
        }
    }

    /// 日志卡头部的短暂反馈（2 秒后自动消失）。
    private func flashLogFeedback(_ message: String, tone: LauncherBadgeTone) {
        logFeedback = message
        logFeedbackTone = tone
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if logFeedback == message {
                logFeedback = nil
            }
        }
    }

    /// 自动滚动到最新一行。
    private func scrollLogToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = engine.logLines.indices.last else { return }
        if animated {
            withAnimation(LauncherMotion.smooth) {
                proxy.scrollTo(last, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    /// 检查更新：先进入加载态，1.2 秒后给出结果（纯 UI 模拟）。
    private func checkForUpdates() {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        updateMessage = "正在检查更新…"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isCheckingUpdates = false
            updateMessage = "已是最新版本 v0.2.0 · 刚刚检查"
        }
    }
}
