import SwiftUI
import AppKit

// MARK: - 设置页（PCL 式：左分类 + 右内容）

/// 设置页：左侧分类面板（游戏 / 启动器 / 关于）+ 右侧单分类的真实设置内容。
/// 所有控件都直接读写 `LauncherEngine.settings` 或触发真实动作（网络检查、文件删除、
/// 剪贴板、目录选择、进程重启），不含任何"假成功"。
public struct SettingsPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherThemeManager.self) private var themeManager
    @Environment(LauncherEngine.self) private var engine
    @Environment(AccountStore.self) private var accountStore
    @Environment(LauncherRouter.self) private var router
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    // MARK: 页面状态（仅 UI 反馈，不属于设置项）

    /// 当前分类
    @State private var section: SettingsSection = .launch
    /// 真实更新检查器（关于分类用；状态跨分区保留）
    @State private var updateChecker = UpdateChecker()
    /// Java 重新检测中（页头快捷按钮用）
    @State private var isRefreshingJava = false

    /// 创建设置页。
    public init() {}

    /// 创建并直接打开某个分类（供路由预览与离屏截图使用）。
    public init(initialSection: SettingsSection) {
        _section = State(initialValue: initialSection)
    }

    public var body: some View {
        LauncherPageLayout(sideWidth: 236) {
            sidePanel
        } main: {
            LauncherMainPanel {
                VStack(alignment: .leading, spacing: LauncherSpace.md) {
                    mainHeader
                    // 与 PCL 一致的卡片流：分类内容装进卡片，避免设置行直接浮在背景上
                    GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.md) {
                        categoryContent
                    }
                    // 内容较短时把保存条压到内容区底部常驻
                    Spacer(minLength: LauncherSpace.md)
                    saveBar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear(perform: consumePendingSection)
        .onChange(of: router.pendingSettingsSection) { _, _ in
            consumePendingSection()
        }
        .task { await refreshEnvironmentIfNeeded() }
    }

    // MARK: - 文案

    /// 当前语言下的设置页文案（`settings.language` 一变，本页立即切换）。
    private var strings: SettingsStrings {
        SettingsStrings(language: SettingsLanguage.resolve(engine.settings.language))
    }

    // MARK: - 左侧分类面板

    /// 左面板：三组分类，每行 44pt 列表行（选中高亮），Java 行挂运行时数量徽标。
    private var sidePanel: some View {
        LauncherSidePanel(
            title: strings[.pageTitle],
            count: nil,
            width: 236,
            content: {
                ForEach(SettingsSectionGroup.allCases, id: \.self) { group in
                    LauncherSidePanelGroup(strings.groupTitle(group))
                    ForEach(SettingsSection.allCases.filter { $0.group == group }) { item in
                        sideRow(item)
                    }
                }
            },
            footer: { sidePanelFooter }
        )
    }

    /// 分类行。
    private func sideRow(_ item: SettingsSection) -> some View {
        LauncherListRow(
            title: strings.sectionTitle(item),
            systemImage: item.systemImage,
            badge: item == .java && !engine.javaRuntimes.isEmpty
                ? strings.format(.badgeJavaCount, engine.javaRuntimes.count)
                : nil,
            isSelected: section == item,
            action: {
                withAnimation(LauncherMotion.spring) {
                    section = item
                }
            }
        )
    }

    /// 左面板底部：真实构建版本 + 自动保存标识。
    private var sidePanelFooter: some View {
        VStack(spacing: LauncherSpace.xs) {
            Rectangle()
                .fill(theme.colors.stroke)
                .frame(height: 1)
            HStack(spacing: LauncherSpace.xs) {
                LauncherMonoText(LauncherBuildInfo.current.versionText, tone: .tertiary, size: 10)
                Spacer(minLength: 0)
                LauncherBadge(strings[.autoSave], tone: .neutral)
            }
            .padding(.horizontal, LauncherSpace.xxs)
        }
    }

    // MARK: - 右侧页头

    /// 右侧标题：随分类变化，右侧挂分类状态徽标 / Java 重新检测按钮。
    private var mainHeader: some View {
        LauncherPanelHeader(strings.sectionTitle(section), subtitle: headerSubtitle) {
            HStack(spacing: LauncherSpace.xs) {
                if let badge = categoryBadge {
                    LauncherBadge(badge, tone: .neutral)
                }
                if section == .java {
                    LauncherIconButton(
                        systemImage: "arrow.clockwise",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: strings[.javaRedetect],
                        isDisabled: isRefreshingJava
                    ) {
                        refreshJava()
                    }
                }
            }
        }
    }

    /// 分类副标题：账户分类跟随当前账户类型（离线 / 正版）。
    private var headerSubtitle: String {
        guard section == .account else { return strings.sectionSubtitle(section) }
        return accountStore.selectedAccount.isMicrosoft
            ? strings[.premiumSubtitle]
            : strings[.subtitleAccount]
    }

    /// 当前分类右上角徽标。
    private var categoryBadge: String? {
        switch section {
        case .java:
            return engine.javaRuntimes.isEmpty
                ? strings[.badgeJavaNone]
                : strings.format(.badgeJavaCount, engine.javaRuntimes.count)
        case .appearance:
            return themeManager.theme.name
        case .account:
            return accountStore.selectedAccount.isMicrosoft ? strings[.premiumBadge] : strings[.badgeOffline]
        case .update:
            return channelTitle
        default:
            return nil
        }
    }

    /// 更新通道标题（跟随语言）。
    private var channelTitle: String {
        switch engine.settings.updateChannel {
        case "snapshot": return strings[.channelSnapshot]
        case "preview": return strings[.channelPreview]
        default: return strings[.channelRelease]
        }
    }

    // MARK: - 右侧分类内容

    @ViewBuilder
    private var categoryContent: some View {
        switch section {
        case .launch:
            SettingsLaunchSection(strings: strings)
        case .java:
            SettingsJavaSection(strings: strings)
        case .performance:
            SettingsPerformanceSection(strings: strings)
        case .update:
            SettingsUpdateSection(strings: strings)
        case .appearance:
            SettingsAppearanceSection(strings: strings)
        case .account:
            SettingsAccountSection(strings: strings)
        case .about:
            SettingsAboutSection(strings: strings, checker: updateChecker)
        case .log:
            SettingsLogSection(strings: strings)
        }
    }

    // MARK: - 保存条（右列常驻）

    /// 保存条：显示真实 `settings.lastSavedAt`；恢复默认前用全局确认框确认。
    private var saveBar: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            HStack(spacing: LauncherSpace.md) {
                LauncherButton(strings[.saveButton], systemImage: "checkmark", variant: .primary) {
                    saveSettings()
                }
                .fixedSize()
                LauncherButton(strings[.resetButton], systemImage: "arrow.counterclockwise", variant: .secondary) {
                    confirmResetSettings()
                }
                .fixedSize()
                Spacer(minLength: LauncherSpace.md)
                HStack(spacing: LauncherSpace.xs) {
                    LauncherStatusDot(tone: engine.settings.lastSavedAt == nil ? .neutral : .success)
                    Text(saveStateText)
                        .textStyle(.monoSmall, tone: engine.settings.lastSavedAt == nil ? .tertiary : .success)
                        .lineLimit(1)
                }
            }
        }
    }

    /// 保存条状态文案：真实写入时间，或"本次运行尚未写入"。
    private var saveStateText: String {
        guard let lastSavedAt = engine.settings.lastSavedAt else {
            return strings[.saveBarNever]
        }
        return strings.format(.saveBarSavedAt, SettingsDateFormat.clock.string(from: lastSavedAt))
    }

    // MARK: - 动作

    /// 消费路由带来的分区跳转（如账户胶囊 → 账户分类）。
    /// 无论能否解析出有效分区，都要把路由上的待办清空，避免非法值永久残留。
    private func consumePendingSection() {
        guard let raw = router.pendingSettingsSection else { return }
        router.pendingSettingsSection = nil
        guard let pending = SettingsSection.resolve(raw) else { return }
        section = pending
    }

    /// 首次进入设置页时补一次环境检测（Java / 已安装版本），已有数据就不重复扫描。
    private func refreshEnvironmentIfNeeded() async {
        guard !snapshotMode, engine.javaRuntimes.isEmpty, !isRefreshingJava else { return }
        isRefreshingJava = true
        await engine.refreshEnvironment()
        isRefreshingJava = false
    }

    /// 页头快捷重新检测 Java。
    private func refreshJava() {
        guard !isRefreshingJava else { return }
        isRefreshingJava = true
        Task { @MainActor in
            await engine.refreshEnvironment()
            isRefreshingJava = false
            router.showToast(strings[.javaRefreshToast])
        }
    }

    /// 保存：设置本身实时写盘，这里把偏好立即刷新到磁盘并给出真实反馈。
    private func saveSettings() {
        SettingsPersistence.flush()
        if engine.settings.lastSavedAt == nil {
            router.showToast(strings[.saveNoChanges], tone: .info)
        } else {
            router.showToast(strings[.savedToast])
        }
    }

    /// 恢复默认：只重置**当前分类**的设置项（其它页面、实例与账户数据保留），先确认再执行。
    private func confirmResetSettings() {
        guard SettingsSectionReset.hasResettableSettings(section) else {
            router.showToast(strings[.resetSectionNoop], tone: .info)
            return
        }
        let sectionTitle = strings.sectionTitle(section)
        router.showDialog(
            LauncherDialogRequest(
                title: strings.format(.resetSectionTitle, sectionTitle),
                message: strings[.resetSectionMessage],
                confirmTitle: strings[.resetDialogConfirm],
                isDestructive: true,
                onConfirm: {
                    SettingsSectionReset.apply(section, settings: engine.settings, themeManager: themeManager)
                    router.showToast(strings.format(.resetSectionToast, sectionTitle))
                }
            )
        )
    }
}
