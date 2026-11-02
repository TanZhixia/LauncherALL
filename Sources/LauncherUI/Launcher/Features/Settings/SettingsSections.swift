import SwiftUI
import AppKit

// MARK: - 共享行组件

/// 设置行之间的分隔线（与 `LauncherSettingRow` 内部节奏一致）。
struct SettingsRowDivider: View {
    @Environment(\.launcherTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.colors.stroke.opacity(0.6))
            .frame(height: 1)
    }
}

/// 布尔设置行：`LauncherToggle` + 可选提示图标 + 分隔线。
struct SettingsBooleanRow: View {
    let title: String
    let subtitle: String?
    let tooltip: String?
    @Binding var isOn: Bool
    var showsDivider: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: LauncherSpace.md) {
                LauncherToggle(title, isOn: $isOn, subtitle: subtitle)
                if let tooltip {
                    LauncherHintIcon(tooltip)
                }
            }
            if showsDivider {
                SettingsRowDivider()
            }
        }
        .padding(.vertical, LauncherSpace.xxs)
    }
}

/// 行内单行反馈文字（成功 / 警告 / 错误 / 说明）。
struct SettingsInlineText: View {
    let text: String
    let tone: LauncherTextTone

    var body: some View {
        Text(text)
            .textStyle(.micro, tone: tone)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 等宽路径文本：中间截断，避免长路径撑宽布局。
struct SettingsPathText: View {
    let text: String
    var tone: LauncherTextTone = .tertiary
    var size: CGFloat = 10

    var body: some View {
        LauncherMonoText(text, tone: tone, size: size)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 320, alignment: .trailing)
    }
}

/// 设置页统一的时间格式化（等宽、与语言无关）。
enum SettingsDateFormat {
    /// "yyyy-MM-dd HH:mm"
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// "HH:mm:ss"
    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - 1. 启动

/// 启动分类：真实游戏目录、版本隔离预览、启动后最小化与启动前检查更新。
struct SettingsLaunchSection: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(LauncherRouter.self) private var router

    let strings: SettingsStrings

    var body: some View {
        @Bindable var settings = engine.settings
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                strings[.gameDirTitle],
                subtitle: strings[.gameDirSubtitle],
                tooltip: strings[.gameDirTooltip]
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherTextField(
                        strings[.gameDirPlaceholder],
                        text: $settings.gameDirectory,
                        systemImage: "folder"
                    )
                    .frame(maxWidth: 360)
                    LauncherButton(
                        strings[.browse],
                        systemImage: "folder.badge.plus",
                        variant: .secondary,
                        size: .small
                    ) {
                        chooseDirectory()
                    }
                    .fixedSize()
                    LauncherIconButton(
                        systemImage: "arrow.up.forward.app",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: strings[.openInFinder]
                    ) {
                        openGameDirectory()
                    }
                }
            }

            SettingsBooleanRow(
                title: strings[.isolationTitle],
                subtitle: strings[.isolationSubtitle],
                tooltip: strings[.isolationTooltip],
                isOn: $settings.versionIsolation
            )

            LauncherSettingRow(
                strings[.previewTitle],
                subtitle: strings[.previewSubtitle]
            ) {
                if let versionID = previewVersionID {
                    HStack(spacing: LauncherSpace.sm) {
                        Text(settings.versionIsolation ? strings[.previewIsolated] : strings[.previewShared])
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                        SettingsPathText(text: settings.gameDirectory(for: versionID).path, tone: .secondary)
                    }
                } else {
                    Text(strings[.previewNoVersion])
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(2)
                }
            }

            SettingsBooleanRow(
                title: strings[.minimizeTitle],
                subtitle: strings[.minimizeSubtitle],
                tooltip: nil,
                isOn: $settings.minimizeAfterLaunch
            )

            SettingsBooleanRow(
                title: strings[.checkUpdatesOnStartTitle],
                subtitle: strings[.checkUpdatesOnStartSubtitle],
                tooltip: nil,
                isOn: $settings.checkUpdatesOnStart,
                showsDivider: false
            )
        }
    }

    /// 预览用的版本 id：优先真正选中/最近启动的版本，其次第一个已安装版本。
    private var previewVersionID: String? {
        engine.activeVersionID
            ?? engine.settings.lastLaunchedVersionID
            ?? engine.installedVersions.first?.id
    }

    /// 真实打开系统文件夹选择器，选中后写入设置。
    private func chooseDirectory() {
        guard let url = InstanceActions.pickDirectory(
            message: strings[.pickGameDirMessage],
            startingAt: engine.settings.resolvedGameDirectory
        ) else { return }
        engine.settings.gameDirectory = url.path
        router.showToast(strings.format(.gameDirSetToast, url.path))
    }

    /// 在访达中打开真实游戏目录；目录不存在时给出明确提示。
    private func openGameDirectory() {
        let url = engine.settings.resolvedGameDirectory
        let opened = FileManager.default.fileExists(atPath: url.path)
            ? InstanceActions.open(url)
            : false
        if opened {
            router.showToast(strings[.openGameDirToast])
        } else {
            router.showToast(strings.format(.gameDirMissingToast, url.path), tone: .warning)
        }
    }
}

// MARK: - 2. Java 运行时

/// Java 分类：自动/手动选择、真实路径校验、扫描结果列表与版本要求对照。
struct SettingsJavaSection: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(LauncherRouter.self) private var router

    let strings: SettingsStrings

    /// 重新检测中
    @State private var isDetecting = false
    /// 手动路径的校验结果
    @State private var manualValidation: SettingsJavaValidation?
    /// 校验进行中
    @State private var isValidatingPath = false
    /// 当前版本要求的 Java 主版本（按本地版本 JSON 计算）
    @State private var requiredMajor: Int?
    /// 当前实际会使用的运行时
    @State private var resolvedRuntime: JavaRuntime?

    var body: some View {
        @Bindable var settings = engine.settings
        VStack(alignment: .leading, spacing: 0) {
            SettingsBooleanRow(
                title: strings[.javaAutoTitle],
                subtitle: strings[.javaAutoSubtitle],
                tooltip: strings[.javaAutoTooltip],
                isOn: $settings.javaAutoDetect
            )

            LauncherSettingRow(
                strings[.javaRuntimeTitle],
                subtitle: runtimeRowSubtitle,
                tooltip: runtimeRowTooltip
            ) {
                if engine.javaRuntimes.isEmpty {
                    LauncherButton(
                        strings[.javaRedetect],
                        systemImage: "arrow.clockwise",
                        variant: .secondary,
                        size: .small,
                        isLoading: isDetecting
                    ) {
                        refreshJava()
                    }
                    .fixedSize()
                } else {
                    LauncherMenuButton(
                        runtimeMenuTitle,
                        systemImage: "chevron.down",
                        variant: .secondary,
                        size: .small,
                        groups: runtimeMenuGroups
                    )
                }
            }

            LauncherSettingRow(
                strings[.javaManualTitle],
                subtitle: settings.javaAutoDetect ? strings[.javaManualSubtitleAuto] : strings[.javaManualSubtitleManual],
                tooltip: strings[.javaManualTooltip]
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherTextField(
                        strings[.javaPathPlaceholder],
                        text: $settings.javaRuntimePath,
                        systemImage: "terminal",
                        helper: manualPathHelper,
                        error: manualPathError,
                        onSubmit: validateManualPath
                    )
                    .frame(maxWidth: 320)
                    LauncherButton(
                        strings[.javaValidate],
                        systemImage: "checkmark.seal",
                        variant: .secondary,
                        size: .small,
                        isLoading: isValidatingPath,
                        isDisabled: settings.javaRuntimePath.trimmingCharacters(in: .whitespaces).isEmpty
                    ) {
                        validateManualPath()
                    }
                    .fixedSize()
                }
            }

            LauncherSettingRow(
                strings[.javaRequiredTitle],
                subtitle: requiredMajor.map { strings.format(.javaRequiredValue, $0) } ?? strings[.javaRequiredNone],
                tooltip: strings[.javaRequiredTooltip]
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    if let requiredMajor {
                        LauncherBadge(strings.format(.javaRequiredBadge, requiredMajor), tone: .neutral)
                    }
                    if let resolvedRuntime {
                        SettingsPathText(
                            text: strings.format(.javaUsing, resolvedRuntime.displayName),
                            tone: .secondary,
                            size: 10
                        )
                    }
                }
            }

            LauncherSettingRow(
                strings[.javaRedetect],
                subtitle: strings[.javaRedetectSubtitle]
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherButton(
                        strings[.javaOpenDirectory],
                        systemImage: "folder",
                        variant: .secondary,
                        size: .small
                    ) {
                        openJavaDirectory()
                    }
                    .fixedSize()
                    LauncherButton(
                        isDetecting ? strings[.javaValidating] : strings[.javaDetectNow],
                        systemImage: "arrow.clockwise",
                        variant: .secondary,
                        size: .small,
                        isLoading: isDetecting
                    ) {
                        refreshJava()
                    }
                    .fixedSize()
                }
            }

            LauncherDivider()

            LauncherExpander(
                strings[.javaListTitle],
                subtitle: strings[.javaListSubtitle],
                systemImage: "cup.and.saucer.fill",
                trailing: AnyView(
                    LauncherBadge(
                        engine.javaRuntimes.isEmpty
                            ? strings[.badgeJavaNone]
                            : strings.format(.badgeJavaCount, engine.javaRuntimes.count),
                        tone: .neutral
                    )
                )
            ) {
                if engine.javaRuntimes.isEmpty {
                    LauncherEmptyState(
                        systemImage: "cup.and.saucer",
                        title: strings[.javaListEmpty],
                        message: strings[.javaRuntimeTooltipEmpty]
                    )
                } else {
                    VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        ForEach(engine.javaRuntimes) { runtime in
                            runtimeRow(runtime)
                        }
                    }
                }
            }
        }
        .onAppear(perform: refreshDerivedState)
        .onChange(of: engine.javaRuntimes) { _, _ in refreshDerivedState() }
        .onChange(of: engine.activeVersionID) { _, _ in refreshDerivedState() }
        .onChange(of: engine.installedVersions.map(\.id)) { _, _ in refreshDerivedState() }
        .onChange(of: engine.settings.javaAutoDetect) { _, _ in refreshDerivedState() }
        .onChange(of: engine.settings.javaRuntimePath) { _, _ in
            // 路径变化后旧的校验结论不再可靠；等用户点「校验」或提交时再真实探测
            manualValidation = nil
        }
    }

    // MARK: 派生信息

    /// 当前参考的版本 id。
    private var referenceVersionID: String? {
        engine.activeVersionID
            ?? engine.settings.lastLaunchedVersionID
            ?? engine.installedVersions.first?.id
    }

    /// Java 行说明：随检测结果变化。
    private var runtimeRowSubtitle: String {
        if engine.javaRuntimes.isEmpty {
            return strings[.javaRuntimeEmpty]
        }
        return strings.format(.javaRuntimeCount, engine.javaRuntimes.count)
    }

    /// Java 行提示：列出全部真实运行时路径。
    private var runtimeRowTooltip: String {
        if engine.javaRuntimes.isEmpty {
            return strings[.javaRuntimeTooltipEmpty]
        }
        return engine.javaRuntimes
            .map { "\($0.displayName) · \($0.executable.path)" }
            .joined(separator: "\n")
    }

    /// 下拉按钮标题。
    private var runtimeMenuTitle: String {
        if engine.settings.javaAutoDetect { return strings[.javaAutoLabel] }
        let path = engine.settings.javaRuntimePath
        if let runtime = engine.javaRuntimes.first(where: { $0.executable.path == path }) {
            return runtime.displayName
        }
        if path.isEmpty { return strings[.javaAutoLabel] }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// 运行时下拉菜单：自动检测 + 每个真实运行时。
    private var runtimeMenuGroups: [LauncherMenuGroup] {
        var items: [LauncherMenuItem] = [
            LauncherMenuItem(
                strings[.javaAutoLabel],
                id: "auto",
                systemImage: engine.settings.javaAutoDetect ? "checkmark" : "wand.and.stars",
                detail: strings[.javaAutoDetail]
            ) {
                engine.settings.javaAutoDetect = true
            }
        ]
        for runtime in engine.javaRuntimes {
            let isCurrent = !engine.settings.javaAutoDetect
                && engine.settings.javaRuntimePath == runtime.executable.path
            items.append(
                LauncherMenuItem(
                    runtime.displayName,
                    id: runtime.executable.path,
                    systemImage: isCurrent ? "checkmark" : "cup.and.saucer.fill",
                    detail: runtime.executable.path
                ) {
                    engine.settings.javaRuntimePath = runtime.executable.path
                    engine.settings.javaAutoDetect = false
                }
            )
        }
        return [LauncherMenuGroup(title: strings[.javaMenuGroup], items: items)]
    }

    /// 单个运行时的列表行：版本 / 厂商 / 路径 / 是否满足要求。
    private func runtimeRow(_ runtime: JavaRuntime) -> some View {
        let satisfies = SettingsJavaProbe.satisfies(runtime, requiredMajor: requiredMajor)
        let isInUse = resolvedRuntime?.id == runtime.id
        let accessory = HStack(spacing: LauncherSpace.xxs) {
            LauncherBadge(
                satisfies ? strings[.javaBadgeSatisfied] : strings[.javaBadgeLow],
                tone: satisfies ? .success : .warning
            )
            if isInUse {
                LauncherBadge(strings[.javaBadgeInUse], tone: .accent)
            }
        }
        return LauncherListRow(
            title: runtime.displayName,
            subtitle: runtime.executable.path,
            systemImage: "cup.and.saucer.fill",
            accessory: AnyView(accessory),
            isSelected: !engine.settings.javaAutoDetect
                && engine.settings.javaRuntimePath == runtime.executable.path,
            action: {
                engine.settings.javaRuntimePath = runtime.executable.path
                engine.settings.javaAutoDetect = false
                router.showToast(strings.format(.javaUsing, runtime.displayName))
            }
        )
    }

    // MARK: 手动路径校验

    /// 校验失败时输入框下方的错误文案。
    private var manualPathError: String? {
        guard case .invalid(let failure) = manualValidation else { return nil }
        switch failure {
        case .missing(let path): return strings.format(.javaIssueMissing, path)
        case .notExecutable(let path): return strings.format(.javaIssueNotExecutable, path)
        case .probeFailed(_, let detail): return strings.format(.javaIssueProbeFailed, detail)
        }
    }

    /// 校验成功时输入框下方的说明文案。
    private var manualPathHelper: String? {
        guard case .valid(let runtime) = manualValidation else { return nil }
        return strings.format(.javaPathValid, runtime.majorVersion, runtime.vendor)
    }

    /// 真实执行路径校验（后台线程跑 java -version）。
    private func validateManualPath() {
        guard !isValidatingPath else { return }
        let raw = engine.settings.javaRuntimePath
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            manualValidation = .empty
            return
        }
        isValidatingPath = true
        Task { @MainActor in
            let result = await SettingsJavaProbe.validateAsync(raw)
            manualValidation = result
            isValidatingPath = false
            if case .valid(let runtime) = result {
                refreshDerivedState()
                router.showToast(strings.format(.javaPathValid, runtime.majorVersion, runtime.vendor))
            }
        }
    }

    // MARK: 动作

    /// 重新检测 Java 运行时与已安装版本。
    private func refreshJava() {
        guard !isDetecting else { return }
        isDetecting = true
        Task { @MainActor in
            await engine.refreshEnvironment()
            isDetecting = false
            refreshDerivedState()
            router.showToast(strings[.javaRefreshToast])
        }
    }

    /// 重新计算版本要求与实际选中的运行时。
    private func refreshDerivedState() {
        requiredMajor = referenceVersionID.flatMap { engine.requiredJavaMajor(for: $0) }
        resolvedRuntime = engine.resolvedJava(for: requiredMajor)
    }

    /// 在访达中打开 Java 目录（优先当前运行时所在目录）。
    private func openJavaDirectory() {
        let candidates: [URL] = [
            resolvedRuntime?.executable,
            engine.javaRuntimes.first?.executable
        ].compactMap { $0 }.map { $0.deletingLastPathComponent().deletingLastPathComponent() }
        if let directory = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
           InstanceActions.open(directory) {
            router.showToast(strings.format(.javaOpenDirectoryToast, directory.path))
        } else {
            router.showToast(strings[.javaNoDirectoryToast], tone: .warning)
        }
    }
}

// MARK: - 3. 性能

/// 性能分类：按真实物理内存计算的内存滑杆、-Xmx 冲突提示与高级启动选项。
struct SettingsPerformanceSection: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(LauncherRouter.self) private var router

    let strings: SettingsStrings

    var body: some View {
        @Bindable var settings = engine.settings
        let plan = memoryPlan
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                strings[.memoryTitle],
                subtitle: memorySubtitle(plan),
                tooltip: strings[.memoryTooltip]
            ) {
                LauncherSlider(
                    value: memoryBinding(plan),
                    range: plan.sliderRange,
                    valueText: "\(engine.settings.maxMemoryMB) MB"
                )
                .frame(width: 260)
            }

            // 本机内存与推荐值：数据全部来自 ProcessInfo，可一键应用
            HStack(spacing: LauncherSpace.sm) {
                LauncherBadge(
                    strings.format(.memoryLimitBadge, plan.totalMemoryText, plan.sliderUpperBoundMB),
                    tone: .neutral
                )
                Spacer(minLength: LauncherSpace.sm)
                LauncherButton(
                    strings[.memoryApplyRecommended],
                    systemImage: "wand.and.stars",
                    variant: .secondary,
                    size: .small,
                    isDisabled: engine.settings.maxMemoryMB == plan.recommendedMB
                ) {
                    engine.settings.maxMemoryMB = plan.recommendedMB
                    router.showToast(strings.format(.memoryAppliedToast, plan.recommendedMB))
                }
                .fixedSize()
            }
            .padding(.vertical, LauncherSpace.xs)

            SettingsRowDivider()

            // -Xmx 与滑杆冲突：JVM 参数排在设置值之后会覆盖它
            if let conflict = jvmConflict {
                LauncherBanner(
                    title: strings[.jvmConflictTitle],
                    message: strings.format(
                        .jvmConflictMessage,
                        conflict.raw,
                        engine.settings.maxMemoryMB,
                        conflict.megabytes
                    ) + "\n" + strings[.jvmConflictHint],
                    tone: .warning
                )
                .padding(.vertical, LauncherSpace.sm)
                SettingsRowDivider()
            }

            LauncherExpander(
                strings[.advancedTitle],
                subtitle: strings[.advancedSubtitle],
                systemImage: "slider.horizontal.3"
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    LauncherSettingRow(
                        strings[.renderThreadsTitle],
                        subtitle: strings[.renderThreadsSubtitle],
                        tooltip: strings[.renderThreadsTooltip]
                    ) {
                        VStack(alignment: .trailing, spacing: LauncherSpace.xxs) {
                            LauncherNumberField(
                                nil,
                                value: $settings.renderThreads,
                                range: 1...16,
                                step: 1,
                                unit: strings[.renderThreadsUnit]
                            )
                            Text(strings.format(.renderThreadsHint, processorCount, recommendedThreads))
                                .textStyle(.micro, tone: .tertiary)
                        }
                    }

                    LauncherSettingRow(
                        strings[.jvmArgsTitle],
                        subtitle: strings[.jvmArgsSubtitle],
                        tooltip: strings.format(.jvmArgsTooltip, engine.settings.extraJVMArguments.count),
                        showsDivider: false
                    ) {
                        LauncherMonoText(
                            strings.format(.jvmArgsCount, engine.settings.extraJVMArguments.count),
                            tone: .tertiary,
                            size: 10
                        )
                    }

                    LauncherTextArea(
                        strings[.jvmArgsPlaceholder],
                        text: $settings.jvmArguments,
                        minHeight: 68
                    )
                    .frame(maxWidth: 460)
                    .padding(.top, LauncherSpace.xs)
                    .padding(.bottom, LauncherSpace.xs)
                }
            }
        }
    }

    // MARK: 派生数据

    /// 本机内存方案。
    private var memoryPlan: SettingsMemoryPlan {
        SettingsMemoryPlan.current
    }

    /// 本机逻辑核心数。
    private var processorCount: Int {
        ProcessInfo.processInfo.processorCount
    }

    /// 建议的渲染线程数：核心数的一半，夹在 2…4。
    private var recommendedThreads: Int {
        min(4, max(2, processorCount / 2))
    }

    /// JVM 附加参数里会覆盖内存设置的 -Xmx。
    private var jvmConflict: SettingsJVMMemoryArgument? {
        SettingsJVMArguments.conflictingMaximum(
            arguments: engine.settings.extraJVMArguments,
            memoryMB: engine.settings.maxMemoryMB
        )
    }

    /// 内存滑杆：Int 设置 ↔ Double 滑杆，按 128 MB 吸附并夹到本机上限。
    private func memoryBinding(_ plan: SettingsMemoryPlan) -> Binding<Double> {
        Binding(
            get: { Double(min(max(engine.settings.maxMemoryMB, SettingsMemoryPlan.minimumMB), plan.sliderUpperBoundMB)) },
            set: { engine.settings.maxMemoryMB = plan.snappedMB($0) }
        )
    }

    /// 内存行说明：按真实判定给出差异提示。
    private func memorySubtitle(_ plan: SettingsMemoryPlan) -> String {
        switch plan.verdict(for: engine.settings.maxMemoryMB) {
        case .belowRecommended:
            return strings.format(.memorySubtitleBelow, plan.recommendedMB)
        case .optimal:
            return strings.format(.memorySubtitleOptimal, plan.recommendedMB, plan.totalMemoryText)
        case .aboveRecommended:
            return strings.format(.memorySubtitleAbove, plan.recommendedMB)
        case .overLimit:
            return strings.format(.memorySubtitleOver, plan.sliderUpperBoundMB)
        }
    }
}

// MARK: - 4. 更新与语言

/// 更新与语言分类：更新通道、下载源、旧版本清理（真实扫描 + 删除）与界面语言。
struct SettingsUpdateSection: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(LauncherRouter.self) private var router

    let strings: SettingsStrings

    /// 是否已经扫描过可清理版本
    @State private var hasScannedCleanup = false
    /// 扫描中
    @State private var isScanningCleanup = false
    /// 可清理版本
    @State private var cleanupRows: [SettingsCleanupRow] = []

    var body: some View {
        @Bindable var settings = engine.settings
        let selectedLanguage = SettingsLanguage.resolve(engine.settings.language)
        let appliedLanguage = SettingsAppRestart.launchedLanguage
        let needsRestart = SettingsAppRestart.needsRestart(selected: selectedLanguage, applied: appliedLanguage)
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                strings[.channelTitle],
                subtitle: strings[.channelSubtitle],
                tooltip: strings[.channelTooltip]
            ) {
                LauncherMenuButton(
                    channelTitle,
                    systemImage: "chevron.down",
                    variant: .secondary,
                    size: .small,
                    groups: channelMenuGroups
                )
            }

            LauncherSettingRow(
                strings[.sourceTitle],
                subtitle: strings[.sourceSubtitle],
                tooltip: strings[.sourceTooltip]
            ) {
                LauncherMenuButton(
                    sourceTitle,
                    systemImage: "chevron.down",
                    variant: .secondary,
                    size: .small,
                    groups: sourceMenuGroups
                )
            }

            SettingsBooleanRow(
                title: strings[.autoCleanTitle],
                subtitle: strings[.autoCleanSubtitle],
                tooltip: nil,
                isOn: $settings.autoCleanOldVersions
            )

            LauncherExpander(
                strings[.cleanupTitle],
                subtitle: strings[.cleanupSubtitle],
                systemImage: "trash",
                trailing: AnyView(cleanupTrailingBadge)
            ) {
                cleanupContent
            }

            LauncherDivider()

            LauncherSettingRow(
                strings[.languageTitle],
                subtitle: strings[.languageSubtitle],
                tooltip: strings[.languageTooltip]
            ) {
                LauncherMenuButton(
                    selectedLanguage.nativeName,
                    systemImage: "chevron.down",
                    variant: .secondary,
                    size: .small,
                    groups: languageMenuGroups
                )
            }

            // 当前语言环境：明确标注已生效 / 待重启
            HStack(spacing: LauncherSpace.sm) {
                LauncherStatusDot(tone: needsRestart ? .warning : .success)
                Text(strings.format(.languageApplied, appliedLanguage.nativeName))
                    .textStyle(.micro, tone: .secondary)
                LauncherBadge(
                    needsRestart ? strings[.languagePendingBadge] : strings[.languageAppliedBadge],
                    tone: needsRestart ? .warning : .success
                )
                Spacer(minLength: LauncherSpace.sm)
            }
            .padding(.vertical, LauncherSpace.xs)

            if needsRestart {
                LauncherBanner(
                    title: strings.format(.languageBannerTitle, selectedLanguage.nativeName),
                    message: strings[.languageBannerMessage],
                    tone: .info,
                    actionTitle: strings[.languageRestart],
                    onAction: restartLauncher
                )
                .padding(.top, LauncherSpace.xs)
            }
        }
    }

    // MARK: 更新通道 / 下载源

    /// 更新通道标题（跟随语言）。
    private var channelTitle: String {
        switch engine.settings.updateChannel {
        case "snapshot": return strings[.channelSnapshot]
        case "preview": return strings[.channelPreview]
        default: return strings[.channelRelease]
        }
    }

    /// 更新通道菜单。
    private var channelMenuGroups: [LauncherMenuGroup] {
        let options: [(id: String, title: String, detail: String)] = [
            ("release", strings[.channelRelease], strings[.channelReleaseDetail]),
            ("snapshot", strings[.channelSnapshot], strings[.channelSnapshotDetail]),
            ("preview", strings[.channelPreview], strings[.channelPreviewDetail])
        ]
        return [LauncherMenuGroup(title: strings[.channelGroup], items: options.map { option in
            LauncherMenuItem(
                option.title,
                id: option.id,
                systemImage: engine.settings.updateChannel == option.id
                    ? "checkmark"
                    : "arrow.triangle.2.circlepath",
                detail: option.detail
            ) {
                engine.settings.updateChannel = option.id
            }
        })]
    }

    /// 下载源标题。
    private var sourceTitle: String {
        engine.settings.downloadSourceValue == .mirror ? strings[.sourceMirror] : strings[.sourceOfficial]
    }

    /// 下载源菜单。
    private var sourceMenuGroups: [LauncherMenuGroup] {
        [LauncherMenuGroup(title: strings[.sourceTitle], items: DownloadSource.allCases.map { source in
            LauncherMenuItem(
                source == .mirror ? strings[.sourceMirror] : strings[.sourceOfficial],
                id: source.rawValue,
                systemImage: engine.settings.downloadSourceValue == source ? "checkmark" : "globe",
                detail: source == .mirror ? strings[.sourceMirrorDetail] : strings[.sourceOfficialDetail]
            ) {
                engine.settings.downloadSource = source.rawValue
            }
        })]
    }

    // MARK: 旧版本清理

    /// 展开区尾部徽标：扫描后显示数量与总大小。
    @ViewBuilder
    private var cleanupTrailingBadge: some View {
        if hasScannedCleanup && !cleanupRows.isEmpty {
            LauncherBadge(
                strings.format(
                    .cleanupTotal,
                    cleanupRows.count,
                    SettingsCleanupPlanner.totalSizeText(cleanupRows)
                ),
                tone: .warning
            )
        } else {
            LauncherMonoText("\(SettingsCleanupPlanner.defaultDays)d", tone: .tertiary, size: 10)
        }
    }

    /// 清理区内容：扫描 → 列表 → 单个删除 / 全部清理。
    @ViewBuilder
    private var cleanupContent: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            HStack(spacing: LauncherSpace.sm) {
                LauncherButton(
                    strings[.cleanupScan],
                    systemImage: "magnifyingglass",
                    variant: .secondary,
                    size: .small,
                    isLoading: isScanningCleanup
                ) {
                    scanCleanup()
                }
                .fixedSize()
                if !cleanupRows.isEmpty {
                    LauncherButton(
                        strings[.cleanupDeleteAll],
                        systemImage: "trash",
                        variant: .danger,
                        size: .small
                    ) {
                        confirmDeleteAll()
                    }
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }

            if isScanningCleanup {
                LauncherProgressBar(value: nil, label: strings[.cleanupScanning])
            } else if !hasScannedCleanup {
                SettingsInlineText(
                    text: strings.format(.cleanupNotScanned, SettingsCleanupPlanner.defaultDays),
                    tone: .tertiary
                )
            } else if cleanupRows.isEmpty {
                SettingsInlineText(
                    text: strings.format(.cleanupEmpty, SettingsCleanupPlanner.defaultDays),
                    tone: .tertiary
                )
            } else {
                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    ForEach(cleanupRows) { row in
                        cleanupRowView(row)
                    }
                }
            }
        }
        .padding(.top, LauncherSpace.xs)
    }

    /// 单个可清理版本行。
    private func cleanupRowView(_ row: SettingsCleanupRow) -> some View {
        let lastUsed: String
        if let date = row.lastUsedAt {
            lastUsed = strings.format(.cleanupLastUsed, SettingsDateFormat.dateTime.string(from: date))
        } else {
            // 没有启动记录时，引擎按版本文件修改时间判龄，这里展示同一个依据
            lastUsed = strings.format(.cleanupFileModified, SettingsDateFormat.dateTime.string(from: row.modifiedAt))
        }
        return LauncherListRow(
            title: row.versionID,
            subtitle: "\(row.sizeText) · \(lastUsed)",
            systemImage: "shippingbox",
            accessory: AnyView(
                LauncherIconButton(
                    systemImage: "trash",
                    variant: .ghost,
                    size: .small,
                    accessibilityLabel: strings[.cleanupDelete]
                ) {
                    confirmDelete(row)
                }
            )
        )
    }

    /// 真实扫描未使用的版本（大小来自文件系统，时间来自真实启动记录）。
    private func scanCleanup() {
        guard !isScanningCleanup else { return }
        let versions = engine.unusedVersions(olderThanDays: SettingsCleanupPlanner.defaultDays)
        let gameRoot = engine.settings.resolvedGameDirectory
        // 主线程先取值，后台只处理值类型，避免跨 actor 持有设置对象
        var lastLaunchDates: [String: Date] = [:]
        for record in engine.settings.launchRecords where lastLaunchDates[record.versionID] == nil {
            lastLaunchDates[record.versionID] = record.startedAt
        }
        isScanningCleanup = true
        Task { @MainActor in
            let rows = await Task.detached(priority: .userInitiated) {
                let installation = MinecraftInstallation(root: gameRoot)
                return SettingsCleanupPlanner.rows(
                    versions: versions,
                    lastLaunch: { lastLaunchDates[$0] },
                    sizeProvider: { InstanceActions.size(of: installation.versionDirectory($0)) }
                )
            }.value
            cleanupRows = rows
            hasScannedCleanup = true
            isScanningCleanup = false
        }
    }

    /// 删除单个版本（确认后真实删除到废纸篓）。
    private func confirmDelete(_ row: SettingsCleanupRow) {
        router.showDialog(
            LauncherDialogRequest(
                title: strings[.cleanupDialogTitle],
                message: strings.format(.cleanupDialogMessage, 1, row.sizeText),
                confirmTitle: strings[.cleanupDialogConfirm],
                isDestructive: true,
                onConfirm: {
                    deleteVersions([row])
                }
            )
        )
    }

    /// 一次清理全部可清理版本（确认后逐个真实删除）。
    private func confirmDeleteAll() {
        guard !cleanupRows.isEmpty else { return }
        let rows = cleanupRows
        router.showDialog(
            LauncherDialogRequest(
                title: strings[.cleanupDialogTitle],
                message: strings.format(
                    .cleanupDialogMessage,
                    rows.count,
                    SettingsCleanupPlanner.totalSizeText(rows)
                ),
                confirmTitle: strings[.cleanupDialogConfirm],
                isDestructive: true,
                onConfirm: {
                    deleteVersions(rows)
                }
            )
        )
    }

    /// 真实调用引擎删除版本并刷新列表。
    private func deleteVersions(_ rows: [SettingsCleanupRow]) {
        var deleted = 0
        for row in rows {
            do {
                try engine.deleteVersion(row.versionID)
                deleted += 1
                cleanupRows.removeAll { $0.versionID == row.versionID }
            } catch {
                router.showToast(
                    strings.format(.cleanupFailed, row.versionID, error.localizedDescription),
                    tone: .danger
                )
            }
        }
        if deleted > 0 {
            router.showToast(strings.format(.cleanupToast, deleted))
        }
        if cleanupRows.isEmpty {
            hasScannedCleanup = true
        }
    }

    // MARK: 语言

    /// 界面语言菜单：三种语言，选中项带勾。
    private var languageMenuGroups: [LauncherMenuGroup] {
        let current = SettingsLanguage.resolve(engine.settings.language)
        return [LauncherMenuGroup(title: strings[.languageMenuGroup], items: SettingsLanguage.allCases.map { language in
            LauncherMenuItem(
                language.nativeName,
                id: language.rawValue,
                systemImage: language == current ? "checkmark" : "character.bubble"
            ) {
                engine.settings.language = language.rawValue
            }
        })]
    }

    /// 真实重启：拉起当前可执行文件后退出本进程。
    private func restartLauncher() {
        if !SettingsAppRestart.relaunch() {
            router.showToast(strings[.languageRestartFailed], tone: .danger)
        }
    }
}

// MARK: - 5. 外观

/// 外观分类：主题、边框强度、圆角缩放与「当前 vs 默认」实时对比。
struct SettingsAppearanceSection: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherThemeManager.self) private var themeManager

    let strings: SettingsStrings

    /// 对比样例里的输入内容
    @State private var sampleText = "Steve"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                strings[.themeTitle],
                subtitle: strings[.themeSubtitle],
                tooltip: strings[.themeTooltip]
            ) {
                // 两套主题直接分段切换：点一下就生效，不藏在二级菜单里
                LauncherSegmentedControl(
                    options: themeManager.presets.map { preset in
                        LauncherSegment(
                            id: preset.id,
                            title: preset.name,
                            systemImage: preset.isDark ? "moon.fill" : "sun.max.fill"
                        )
                    },
                    selection: Binding(
                        get: { themeManager.themeID },
                        set: { themeManager.select($0) }
                    )
                )
                .frame(width: 240)
            }

            LauncherSettingRow(
                strings[.borderTitle],
                subtitle: strings[.borderSubtitle],
                tooltip: strings[.borderTooltip]
            ) {
                LauncherSlider(
                    value: borderStrengthBinding,
                    range: 0.4...1.6,
                    valueText: "\(borderStrengthText)×"
                )
                .frame(width: 240)
            }

            LauncherSettingRow(
                strings[.cornerTitle],
                subtitle: strings[.cornerSubtitle],
                tooltip: strings[.cornerTooltip],
                showsDivider: false
            ) {
                LauncherSlider(
                    value: cornerScaleBinding,
                    range: 0.6...1.4,
                    valueText: "\(cornerScaleText)×"
                )
                .frame(width: 240)
            }

            LauncherDivider()

            appearanceComparison
        }
    }

    /// 边框强度绑定。
    private var borderStrengthBinding: Binding<Double> {
        Binding(
            get: { themeManager.borderStrength },
            set: { themeManager.borderStrength = $0 }
        )
    }

    /// 圆角缩放绑定。
    private var cornerScaleBinding: Binding<Double> {
        Binding(
            get: { themeManager.cornerScale },
            set: { themeManager.cornerScale = $0 }
        )
    }

    /// 「当前 vs 默认」对比：左栏跟随当前主题与乘数，右栏固定石墨默认值。
    private var appearanceComparison: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            HStack(spacing: LauncherSpace.sm) {
                LauncherLabel(strings[.compareTitle])
                Spacer(minLength: 0)
                Text(strings[.compareHint])
                    .textStyle(.micro, tone: .tertiary)
            }
            .padding(.top, LauncherSpace.xs)
            HStack(alignment: .top, spacing: LauncherSpace.md) {
                comparisonColumn(
                    title: strings[.compareCurrent],
                    caption: "\(Int(themeManager.radius(LauncherRadius.lg)))pt · \(borderStrengthText)×",
                    cornerRadius: themeManager.radius(LauncherRadius.lg),
                    themeOverride: nil
                )
                comparisonColumn(
                    title: strings[.compareDefault],
                    caption: "\(Int(LauncherRadius.lg))pt · 1.0×",
                    cornerRadius: LauncherRadius.lg,
                    themeOverride: LauncherThemes.graphite
                )
            }
        }
    }

    /// 对比栏：标题 + 数值 + 同构小样。
    private func comparisonColumn(
        title: String,
        caption: String,
        cornerRadius: CGFloat,
        themeOverride: LauncherTheme?
    ) -> some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            HStack(spacing: LauncherSpace.sm) {
                Text(title)
                    .textStyle(.micro, tone: .tertiary)
                Text(caption)
                    .textStyle(.monoSmall, tone: .tertiary)
                Spacer(minLength: 0)
            }
            if let themeOverride {
                comparisonSample(cornerRadius: cornerRadius)
                    .environment(\.launcherTheme, themeOverride)
            } else {
                comparisonSample(cornerRadius: cornerRadius)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 对比小样：面板 + 徽标 + 按钮 + 输入框。
    private func comparisonSample(cornerRadius: CGFloat) -> some View {
        GlassPanel(level: .regular, cornerRadius: cornerRadius, padding: LauncherSpace.sm) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                HStack(spacing: LauncherSpace.xs) {
                    LauncherBadge(strings[.compareBadge], tone: .accent)
                    Spacer(minLength: 0)
                    LauncherButton(
                        strings[.compareButton],
                        variant: .secondary,
                        size: .small,
                        isDisabled: true
                    ) {}
                        .fixedSize()
                }
                LauncherTextField(strings[.comparePlaceholder], text: $sampleText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .launcherTooltip(strings[.compareButtonHint])
    }

    /// 边框强度显示（保留一位小数）。
    private var borderStrengthText: String {
        String((themeManager.borderStrength * 10).rounded() / 10)
    }

    /// 圆角缩放显示（保留一位小数）。
    private var cornerScaleText: String {
        String((themeManager.cornerScale * 10).rounded() / 10)
    }
}

// MARK: - 6. 账户

/// 账户分类：真实玩家名校验、保存过的玩家名切换/删除、离线 UUID 复制。
struct SettingsAccountSection: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(LauncherRouter.self) private var router
    @Environment(AccountStore.self) private var accountStore

    let strings: SettingsStrings

    /// 正在编辑的玩家名（nil 表示尚未编辑，直接显示设置里的真实值；只有合法时才写回设置）
    @State private var draft: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PremiumAccountSection(strings: strings)

            LauncherSettingRow(
                strings[.currentAccountTitle],
                subtitle: currentAccountSubtitle
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    if selectedAccount.isMicrosoft {
                        MinecraftAvatarView(uuid: selectedAccount.uuid, name: selectedAccount.name, size: 26)
                    } else {
                        LauncherAvatar(name: effectiveName, systemImage: "person.fill", size: 26)
                    }
                    Text(selectedAccount.name)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    LauncherBadge(
                        selectedAccount.isMicrosoft ? strings[.premiumBadge] : strings[.badgeOffline],
                        tone: selectedAccount.isMicrosoft ? .accent : .neutral
                    )
                    if accountStore.allAccounts.count > 1 {
                        LauncherMenuButton(
                            strings[.premiumSwitch],
                            variant: .ghost,
                            size: .small,
                            groups: accountSwitchGroups
                        )
                        .fixedSize()
                    }
                }
            }

            LauncherSettingRow(
                strings[.playerNameTitle],
                subtitle: selectedAccount.isMicrosoft ? strings[.premiumOfflineNote] : strings[.playerNameSubtitle],
                tooltip: strings[.playerNameTooltip]
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherTextField(
                        strings[.playerNamePlaceholder],
                        text: draftBinding,
                        systemImage: "person.text.rectangle",
                        error: playerNameError,
                        onSubmit: applyPlayerName
                    )
                    .frame(maxWidth: 220)
                    LauncherButton(
                        strings[.playerNameApply],
                        systemImage: "checkmark",
                        variant: .secondary,
                        size: .small,
                        isDisabled: SettingsPlayerName.normalized(draftText) == nil
                    ) {
                        applyPlayerName()
                    }
                    .fixedSize()
                    LauncherButton(
                        strings[.playerNameReset],
                        systemImage: "arrow.counterclockwise",
                        variant: .secondary,
                        size: .small
                    ) {
                        applyPlayerName("Steve", toastKey: .playerNameAppliedToast, argument: "Steve")
                    }
                    .fixedSize()
                }
            }

            LauncherSettingRow(
                strings[.savedNamesTitle],
                subtitle: strings[.savedNamesSubtitle]
            ) {
                savedNamesControl
            }

            LauncherSettingRow(
                strings[.uuidTitle],
                subtitle: strings[.uuidSubtitle],
                tooltip: strings[.uuidTooltip],
                showsDivider: false
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherMonoText(LaunchCommandBuilder.offlineUUID(for: effectiveName), tone: .secondary, size: 11)
                        .lineLimit(1)
                    LauncherIconButton(
                        systemImage: "doc.on.doc",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: strings[.uuidCopy]
                    ) {
                        InstanceActions.copy(LaunchCommandBuilder.offlineUUID(for: effectiveName))
                        router.showToast(strings[.uuidCopiedToast])
                    }
                }
            }
        }
    }

    // MARK: 派生

    /// 当前选中的账户（离线 / 正版）。
    private var selectedAccount: AuthAccountRecord { accountStore.selectedAccount }

    /// 账户切换菜单：离线账户 + 所有正版账户（含当前项勾选）。
    private var accountSwitchGroups: [LauncherMenuGroup] {
        let items = accountStore.allAccounts.map { record in
            let isCurrent = record.id == selectedAccount.id
            return LauncherMenuItem(
                record.name,
                id: record.id,
                systemImage: isCurrent
                    ? "checkmark"
                    : (record.isMicrosoft ? "person.badge.key.fill" : "person.fill"),
                detail: record.isMicrosoft ? strings[.premiumSubtitle] : strings[.currentAccountSubtitle]
            ) {
                accountStore.select(record.id)
                router.showToast("\(strings[.premiumSwitch])：\(record.name)", tone: .info)
            }
        }
        return [LauncherMenuGroup(title: strings[.currentAccountTitle], items: items)]
    }

    /// 当前账户行说明：正版账户显示厂商信息，离线账户显示离线模式说明。
    private var currentAccountSubtitle: String {
        selectedAccount.isMicrosoft ? strings[.premiumSubtitle] : strings[.currentAccountSubtitle]
    }

    /// 输入框当前文本：未编辑时显示设置里的真实值。
    private var draftText: String {
        draft ?? engine.settings.playerName
    }

    /// 输入框绑定：编辑只改草稿，合法应用后才写回设置。
    private var draftBinding: Binding<String> {
        Binding(
            get: { draftText },
            set: { draft = $0 }
        )
    }

    /// 当前生效的玩家名（编辑中合法时实时联动头像与 UUID）。
    private var effectiveName: String {
        if let normalized = SettingsPlayerName.normalized(draftText) {
            return normalized
        }
        let applied = engine.settings.playerName.trimmingCharacters(in: .whitespaces)
        return applied.isEmpty ? "Steve" : applied
    }

    /// 玩家名错误提示（不合法时显示在输入框下方，且不写回设置）。
    private var playerNameError: String? {
        switch SettingsPlayerName.issue(for: draftText) {
        case .some(.empty): return strings[.playerNameEmpty]
        case .some(.tooLong): return strings[.playerNameTooLong]
        case .some(.invalidCharacters): return strings[.playerNameInvalidChars]
        case .none: return nil
        }
    }

    /// 保存过的玩家名菜单（可切换、可删除）。
    @ViewBuilder
    private var savedNamesControl: some View {
        let names = engine.settings.savedPlayerNames
        if names.isEmpty {
            Text(strings[.savedNamesEmpty])
                .textStyle(.micro, tone: .tertiary)
                .lineLimit(1)
        } else {
            LauncherMenuButton(
                strings.format(.savedNamesCount, names.count),
                systemImage: "chevron.down",
                variant: .secondary,
                size: .small,
                groups: savedNamesMenu(names)
            )
        }
    }

    /// 玩家名菜单分组：切换 + 删除。
    private func savedNamesMenu(_ names: [String]) -> [LauncherMenuGroup] {
        let current = engine.settings.playerName
        let switchItems = names.map { name in
            LauncherMenuItem(
                name,
                id: "switch-\(name)",
                systemImage: name == current ? "checkmark" : "person.crop.circle"
            ) {
                switchPlayerName(to: name)
            }
        }
        let removeItems = names.map { name in
            LauncherMenuItem(
                strings.format(.savedNameRemove, name),
                id: "remove-\(name)",
                systemImage: "trash",
                tone: .danger
            ) {
                removePlayerName(name)
            }
        }
        return [
            LauncherMenuGroup(title: strings[.savedNamesTitle], items: switchItems),
            LauncherMenuGroup(title: nil, items: removeItems)
        ]
    }

    // MARK: 动作

    /// 应用当前草稿：合法才写回设置并记住这个名字。
    private func applyPlayerName() {
        guard let name = SettingsPlayerName.normalized(draftText) else { return }
        engine.settings.playerName = name
        engine.settings.rememberPlayerName(name)
        draft = name
        router.showToast(strings.format(.playerNameAppliedToast, name))
    }

    /// 恢复到给定的名字（重置按钮用）。
    private func applyPlayerName(
        _ name: String,
        toastKey: SettingsTextKey,
        argument: String
    ) {
        engine.settings.playerName = name
        engine.settings.rememberPlayerName(name)
        draft = name
        router.showToast(strings.format(toastKey, argument))
    }

    /// 切换到已保存的玩家名。
    private func switchPlayerName(to name: String) {
        guard SettingsPlayerName.normalized(name) != nil else { return }
        engine.settings.playerName = name
        engine.settings.rememberPlayerName(name)
        draft = name
        router.showToast(strings.format(.savedNameSwitchedToast, name))
    }

    /// 从保存列表移除玩家名（不动当前设置）。
    private func removePlayerName(_ name: String) {
        guard engine.settings.savedPlayerNames.contains(name) else { return }
        engine.settings.savedPlayerNames = engine.settings.savedPlayerNames.filter { $0 != name }
        router.showToast(strings.format(.savedNameRemovedToast, name), tone: .warning)
    }
}

// MARK: - 7. 关于

/// 关于分类：真实构建信息、可编辑更新源、真实 HTTP 更新检查与下载链接。
struct SettingsAboutSection: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(LauncherRouter.self) private var router

    let strings: SettingsStrings
    /// 与页面共享的真实更新检查器
    let checker: UpdateChecker

    var body: some View {
        @Bindable var settings = engine.settings
        let buildInfo = LauncherBuildInfo.current
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                strings[.versionTitle],
                subtitle: strings[.versionSubtitle]
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherBadge(buildInfo.versionText, tone: .accent)
                    LauncherMonoText(buildInfo.buildNumber, tone: .tertiary, size: 10)
                }
            }

            LauncherExpander(
                strings[.buildDetailsTitle],
                subtitle: buildInfo.summary,
                systemImage: "hammer"
            ) {
                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    LauncherKeyValueRow(key: strings[.versionTitle], value: buildInfo.versionText)
                    LauncherKeyValueRow(key: strings[.buildTitle], value: buildInfo.buildNumber)
                    LauncherKeyValueRow(key: strings[.buildDateLabel], value: buildInfo.buildDateTimeText)
                    LauncherKeyValueRow(key: strings[.commitTitle], value: buildInfo.commit)
                    LauncherKeyValueRow(key: strings[.buildChannelLabel], value: channelTitle)
                }
                .padding(.top, LauncherSpace.xs)
            }

            LauncherSettingRow(
                strings[.updateSourceTitle],
                subtitle: settings.updateFeedURL.trimmingCharacters(in: .whitespaces).isEmpty
                    ? strings[.updateSourceSubtitleEmpty]
                    : strings[.updateSourceSubtitleConfigured],
                tooltip: strings[.updateSourceTooltip]
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherTextField(
                        strings[.updateSourcePlaceholder],
                        text: $settings.updateFeedURL,
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                    .frame(maxWidth: 300)
                    LauncherButton(
                        checker.status.isChecking ? strings[.updateChecking] : strings[.updateCheck],
                        systemImage: "arrow.triangle.2.circlepath",
                        variant: .secondary,
                        size: .small,
                        isLoading: checker.status.isChecking
                    ) {
                        checkForUpdates()
                    }
                    .fixedSize()
                }
            }

            updateStatusRow

            if let downloadURL = checker.downloadURL {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherButton(
                        strings[.updateDownload],
                        systemImage: "arrow.down.circle",
                        variant: .primary,
                        size: .small
                    ) {
                        if !NSWorkspace.shared.open(downloadURL) {
                            router.showToast(strings[.updateDownloadFailed], tone: .warning)
                        }
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                .padding(.top, LauncherSpace.xs)
            }
        }
    }

    /// 当前更新通道标题（跟随语言）。
    private var channelTitle: String {
        switch engine.settings.updateChannel {
        case "snapshot": return strings[.channelSnapshot]
        case "preview": return strings[.channelPreview]
        default: return strings[.channelRelease]
        }
    }

    /// 检查状态行：状态徽标 + 说明 + 上次检查时间。
    private var updateStatusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: LauncherSpace.sm) {
            LauncherBadge(statusTitle, tone: statusTone, systemImage: statusIcon)
            Text(statusMessage)
                .textStyle(.micro, tone: .secondary)
                .lineLimit(2)
            Spacer(minLength: LauncherSpace.sm)
            if let lastChecked = checker.lastCheckedText {
                Text(strings.format(.updateLastChecked, lastChecked))
                    .textStyle(.monoSmall, tone: .tertiary)
            }
        }
        .padding(.vertical, LauncherSpace.xs)
    }

    /// 状态徽标文字（短标签，详细说明在下一行）。
    private var statusTitle: String {
        switch checker.status {
        case .idle: return strings[.updateIdleBadge]
        case .checking: return strings[.updateCheckingBadge]
        case .upToDate: return strings[.updateUpToDateBadge]
        case .available(_, let latest): return "v\(latest.version)"
        case .noFeed: return strings[.updateNoFeedBadge]
        case .failed: return strings[.updateFailedBadge]
        }
    }

    /// 状态说明（含更新说明或失败原因）。
    private var statusMessage: String {
        switch checker.status {
        case .idle: return strings[.updateIdle]
        case .checking: return strings[.updateChecking]
        case .upToDate(let current): return strings.format(.updateUpToDate, current)
        case .available(_, let latest):
            let notes = latest.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return strings.format(.updateAvailable, latest.version)
                + (notes.isEmpty ? "" : " · \(notes)")
        case .noFeed: return strings[.updateNoFeed]
        case .failed(let message): return strings.format(.updateFailed, message)
        }
    }

    /// 状态徽标色调。
    private var statusTone: LauncherBadgeTone {
        switch checker.status {
        case .available: return .accent
        case .upToDate: return .success
        case .failed: return .danger
        case .noFeed: return .neutral
        case .idle, .checking: return .neutral
        }
    }

    /// 状态徽标图标。
    private var statusIcon: String {
        switch checker.status {
        case .available: return "arrow.down.circle.fill"
        case .upToDate: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .noFeed: return "antenna.radiowaves.left.and.right.slash"
        case .idle: return "questionmark.circle"
        case .checking: return "arrow.triangle.2.circlepath"
        }
    }

    /// 真实检查更新：走 UpdateChecker 的 HTTP 请求，不伪造结果。
    private func checkForUpdates() {
        guard !checker.status.isChecking else { return }
        Task { @MainActor in
            await checker.check(
                feedURL: engine.settings.updateFeedURL,
                currentVersion: LauncherBuildInfo.current.version
            )
        }
    }
}

// MARK: - 8. 日志与诊断

/// 日志分类：真实行数 / 退出码、复制、导出成文件、清空（确认）与跳转完整日志。
struct SettingsLogSection: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherEngine.self) private var engine
    @Environment(LauncherRouter.self) private var router

    let strings: SettingsStrings

    /// 最近一次导出到文件的 URL（用于「在访达中显示」）
    @State private var exportedURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                strings[.logTitle],
                subtitle: strings[.logSubtitle],
                tooltip: strings[.logTooltip]
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherBadge(strings.format(.logLinesBadge, engine.logLines.count), tone: .neutral)
                    LauncherBadge(exitCodeText, tone: exitCodeTone)
                }
            }

            HStack(spacing: LauncherSpace.sm) {
                LauncherButton(
                    strings[.logCopyRecent],
                    systemImage: "doc.on.doc",
                    variant: .secondary,
                    size: .small,
                    isDisabled: engine.logLines.isEmpty
                ) {
                    copyRecentLogs()
                }
                .fixedSize()
                LauncherButton(
                    strings[.logExport],
                    systemImage: "square.and.arrow.down",
                    variant: .secondary,
                    size: .small,
                    isDisabled: engine.logLines.isEmpty
                ) {
                    exportLogs()
                }
                .fixedSize()
                .launcherTooltip(strings[.logExportTooltip])
                LauncherButton(
                    strings[.logOpenMore],
                    systemImage: "arrow.up.forward.app",
                    variant: .secondary,
                    size: .small
                ) {
                    router.go(.more, moreSection: "logs")
                }
                .fixedSize()
                LauncherButton(
                    strings[.logClear],
                    systemImage: "trash",
                    variant: .secondary,
                    size: .small,
                    isDisabled: engine.logLines.isEmpty
                ) {
                    confirmClearLog()
                }
                .fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.vertical, LauncherSpace.sm)

            logPreview

            if let exportedURL {
                HStack(spacing: LauncherSpace.sm) {
                    Text(strings.format(.logExportedToast, shortenedPath(exportedURL)))
                        .textStyle(.micro, tone: .success)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    LauncherButton(
                        strings[.logReveal],
                        systemImage: "magnifyingglass",
                        variant: .ghost,
                        size: .small
                    ) {
                        InstanceActions.reveal(exportedURL)
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                .padding(.top, LauncherSpace.xs)
            }
        }
    }

    /// 最后退出码徽标文案。
    private var exitCodeText: String {
        if let code = engine.lastExitCode {
            return strings.format(.logExitCode, String(code))
        }
        return strings[.logExitNone]
    }

    /// 退出码徽标色调：0 成功，其它为警告。
    private var exitCodeTone: LauncherBadgeTone {
        guard let code = engine.lastExitCode else { return .neutral }
        return code == 0 ? .success : .warning
    }

    /// 最近日志预览框（最后 6 行）。
    private var logPreview: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
            if engine.logLines.isEmpty {
                Text(strings[.logEmpty])
                    .textStyle(.micro, tone: .tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(engine.logLines.suffix(6).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .textStyle(.monoSmall, tone: .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(LauncherSpace.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 116, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .strokeBorder(theme.colors.stroke, lineWidth: 1)
        }
    }

    /// 展示用路径：把 home 目录缩写成 `~`。
    private func shortenedPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// 复制最近 50 行日志到剪贴板（真实剪贴板写入）。
    private func copyRecentLogs() {
        let lines = Array(engine.logLines.suffix(50))
        guard !lines.isEmpty else { return }
        InstanceActions.copy(lines.joined(separator: "\n"))
        router.showToast(strings.format(.logCopiedToast, lines.count))
    }

    /// 真实导出日志到 `~/Library/Logs/BlockLauncher/`（与更多页同一落点），
    /// 头部含版本 / 启动命令 / 退出码。
    private func exportLogs() {
        do {
            let result = try SettingsLogExporter.export(
                lines: engine.logLines,
                buildInfo: LauncherBuildInfo.current,
                commandLine: engine.lastCommandLine,
                exitCode: engine.lastExitCode,
                labels: strings.logExportLabels
            )
            exportedURL = result.url
            router.showToast(strings.format(.logExportedToast, result.url.lastPathComponent))
        } catch {
            router.showToast(
                strings.format(.logExportFailedToast, error.localizedDescription),
                tone: .danger
            )
        }
    }

    /// 清空日志前先用全局确认框确认。
    private func confirmClearLog() {
        router.showDialog(
            LauncherDialogRequest(
                title: strings[.logClearDialogTitle],
                message: strings.format(.logClearDialogMessage, engine.logLines.count),
                confirmTitle: strings[.logClearDialogConfirm],
                isDestructive: true,
                onConfirm: {
                    engine.clearLog()
                    exportedURL = nil
                    router.showToast(strings[.logClearedToast], tone: .warning)
                }
            )
        )
    }
}
