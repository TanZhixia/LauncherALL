import SwiftUI

// MARK: - 设置页

/// 设置页：启动 / Java 运行时 / 性能 / 更新与语言 / 外观 / 账户 / 关于 + 底部保存条。
/// 只做 UI：交互全部由页面内 `@State` 模拟，外观参数直接绑定 `LauncherThemeManager`。
public struct SettingsPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherThemeManager.self) private var themeManager

    // MARK: 启动

    @State private var gameDirectory: String = LauncherDemoData.versionDirectory
    @State private var directoryPickIndex = 0
    @State private var versionIsolation = true
    @State private var minimizeAfterLaunch = true
    @State private var checkUpdatesOnStart = true

    // MARK: Java 运行时

    @State private var selectedJavaID: String = LauncherDemoData.javaRuntimes.first?.id ?? "21"
    @State private var javaStatus = "上次检测：今天 09:12 · 3 个运行时可用"
    @State private var isDetectingJava = false

    // MARK: 性能

    @State private var memory: Double = 4096
    @State private var renderThreads = 4
    @State private var jvmArguments = "-XX:+UseG1GC\n-XX:MaxGCPauseMillis=50\n-Xms2048m"

    // MARK: 更新与语言

    @State private var updateChannel = "release"
    @State private var autoCheckUpdates = true
    @State private var language = "zh-Hans"

    // MARK: 账户

    @State private var isSignedIn = true
    @State private var accountSlot = 0

    // MARK: 关于

    @State private var updateStatus = "已是最新版本 v0.2.0"
    @State private var logHint = ""

    // MARK: 底部保存条

    @State private var saveHint = "所有修改会自动保存"
    @State private var saveHintIsSuccess = false

    /// 创建设置页。
    public init() {}

    public var body: some View {
        LauncherAppPage {
            LauncherPageHeader(title: "设置", subtitle: "启动行为、Java 运行时、性能与外观")
                .padding(.bottom, LauncherSpace.xxs)

            HStack(alignment: .top, spacing: LauncherSpace.lg) {
                // 主栏：启动 / Java / 性能 / 更新与语言
                VStack(spacing: LauncherSpace.lg) {
                    launchCard
                    javaCard
                    performanceCard
                    updateCard
                }
                .frame(maxWidth: .infinity)

                // 侧栏：外观 / 账户 / 关于
                VStack(spacing: LauncherSpace.lg) {
                    appearanceCard
                    accountCard
                    aboutCard
                }
                .frame(width: 380)
            }

            saveBar
        }
    }

    // MARK: - 1. 启动

    /// 启动区块：游戏目录、版本隔离、启动后行为、启动前检查。
    private var launchCard: some View {
        settingsCard(
            "启动",
            subtitle: "游戏目录与启动时的默认行为",
            accessory: AnyView(LauncherBadge("本地", tone: .neutral, systemImage: "internaldrive"))
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                settingRow(
                    title: "游戏目录",
                    subtitle: "启动时在此目录读写 versions / mods / saves"
                ) {
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherTextField("游戏目录", text: $gameDirectory, systemImage: "folder")
                            .frame(maxWidth: 440)
                        LauncherButton(
                            "浏览…",
                            systemImage: "folder.badge.plus",
                            variant: .secondary,
                            size: .small
                        ) {
                            browseDirectory()
                        }
                    }
                }

                LauncherDivider()

                LauncherToggle(
                    "版本隔离",
                    isOn: $versionIsolation,
                    subtitle: "每个游戏版本使用独立的 mods 与配置目录"
                )

                LauncherDivider()

                LauncherToggle(
                    "启动后最小化",
                    isOn: $minimizeAfterLaunch,
                    subtitle: "进入游戏后把启动器窗口收进 Dock"
                )

                LauncherDivider()

                LauncherCheckbox("启动前检查版本与模组更新", isOn: $checkUpdatesOnStart)
            }
        }
    }

    // MARK: - 2. Java 运行时

    /// Java 区块：运行时三选一、安装路径、重新检测。
    private var javaCard: some View {
        settingsCard(
            "Java 运行时",
            subtitle: "一个实例只绑定一个运行时，切换后会在下次启动时生效",
            accessory: AnyView(javaAccessory)
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                HStack(spacing: LauncherSpace.md) {
                    ForEach(LauncherDemoData.javaRuntimes) { runtime in
                        LauncherRadioCard(
                            runtime.name,
                            subtitle: javaSubtitle(runtime),
                            systemImage: "cup.and.saucer.fill",
                            isSelected: runtime.id == selectedJavaID
                        ) {
                            selectedJavaID = runtime.id
                            javaStatus = "已选择 \(runtime.name) · 下次启动生效"
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                LauncherDivider()

                settingRow(title: "运行时路径", subtitle: "由启动器自动检测，也可手动指定其他 JDK") {
                    LauncherMonoText(selectedJava?.path ?? "—", tone: .secondary, size: 11)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: LauncherSpace.md) {
                    LauncherButton(
                        "重新检测",
                        systemImage: "arrow.clockwise",
                        variant: .secondary,
                        size: .small,
                        isLoading: isDetectingJava
                    ) {
                        detectJava()
                    }
                    Text(javaStatus)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Java 区块右上角状态：检测中 / 可用数量。
    private var javaAccessory: some View {
        HStack(spacing: LauncherSpace.sm) {
            if isDetectingJava {
                LauncherSpinner(size: 12)
            }
            LauncherBadge(
                isDetectingJava ? "检测中" : "3 个可用",
                tone: isDetectingJava ? .warning : .success,
                systemImage: isDetectingJava ? "arrow.triangle.2.circlepath" : "checkmark"
            )
        }
    }

    // MARK: - 3. 性能

    /// 性能区块：最大内存、渲染线程、JVM 参数。
    private var performanceCard: some View {
        settingsCard(
            "性能",
            subtitle: "内存、渲染线程与 JVM 参数，修改后下次启动生效"
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                settingRow(title: "最大内存", subtitle: memoryHint) {
                    LauncherSlider(
                        value: memoryBinding,
                        range: 1024...8192,
                        valueText: "\(Int(memory)) MB"
                    )
                    .frame(width: 340)
                }

                LauncherDivider()

                settingRow(
                    title: "渲染线程",
                    subtitle: "建议 2 ~ 4 个，数量过多反而增加调度开销"
                ) {
                    LauncherStepper(value: $renderThreads, range: 1...16, unit: "线程")
                        .frame(width: 220)
                }

                LauncherDivider()

                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: LauncherSpace.sm) {
                        Text("JVM 参数")
                            .textStyle(.bodyStrong)
                        Spacer(minLength: LauncherSpace.sm)
                        LauncherMonoText("\(jvmArgumentLines) 行", tone: .tertiary, size: 10)
                    }
                    LauncherTextArea("每行一个 JVM 参数，例如 -XX:+UseG1GC", text: $jvmArguments, minHeight: 88)
                    Text("每行一个参数，留空则使用启动器默认参数")
                        .textStyle(.micro, tone: .tertiary)
                }
            }
        }
    }

    // MARK: - 4. 更新与语言

    /// 更新与语言区块：更新通道、自动检查、界面语言。
    private var updateCard: some View {
        settingsCard(
            "更新与语言",
            subtitle: "更新通道决定接收到的版本类型",
            accessory: AnyView(LauncherBadge(updateChannelTitle, tone: .accent))
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                settingRow(title: "更新通道", subtitle: "快照与预览通道可能包含未完成的功能") {
                    LauncherSegmentedControl(
                        options: updateChannelOptions,
                        selection: $updateChannel
                    )
                    .frame(width: 330)
                }

                LauncherDivider()

                LauncherToggle(
                    "自动检查更新",
                    isOn: $autoCheckUpdates,
                    subtitle: "在后台检查新版本，发现后在顶部提示"
                )

                LauncherDivider()

                settingRow(title: "界面语言", subtitle: "切换语言后需要重启启动器") {
                    LauncherDropdown(
                        options: languageOptions,
                        selection: $language,
                        placeholder: "请选择语言"
                    )
                    .frame(width: 210)
                }
            }
        }
    }

    // MARK: - 5. 外观

    /// 外观区块：主题选择 + 边框强度 + 圆角缩放 + 实时预览（全部绑定 ThemeManager）。
    private var appearanceCard: some View {
        settingsCard(
            "外观",
            subtitle: "主题与全局外观参数，修改立即生效",
            accessory: AnyView(LauncherBadge(currentThemeName, tone: .accent))
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                VStack(spacing: LauncherSpace.sm) {
                    ForEach(themeManager.presets) { preset in
                        themeOption(preset)
                    }
                }

                LauncherDivider()

                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    LauncherSlider(
                        value: borderStrengthBinding,
                        range: 0.4...1.6,
                        label: "边框强度",
                        valueText: "\(borderStrengthText)×"
                    )
                    Text("调节面板与分割线的描边可见度")
                        .textStyle(.micro, tone: .tertiary)
                }

                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    LauncherSlider(
                        value: cornerScaleBinding,
                        range: 0.6...1.4,
                        label: "圆角缩放",
                        valueText: "\(cornerScaleText)×"
                    )
                    Text("按比例缩放全站圆角")
                        .textStyle(.micro, tone: .tertiary)
                }

                LauncherDivider()

                appearancePreview
            }
        }
    }

    /// 单个主题选项：三色色板 + 名称/气质 + 当前标记，点击即切换主题。
    private func themeOption(_ preset: LauncherTheme) -> some View {
        let isCurrent = preset.id == themeManager.themeID
        return Button {
            themeManager.select(preset.id)
        } label: {
            HStack(spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.xxs) {
                    ForEach(preset.swatch.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                            .fill(preset.swatch[index])
                            .frame(width: LauncherSpace.lg, height: LauncherSpace.lg)
                            .overlay {
                                RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                                    .strokeBorder(preset.colors.stroke, lineWidth: 1)
                            }
                    }
                }

                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    Text(preset.name)
                        .textStyle(.bodyStrong)
                    Text(preset.tagline)
                        .textStyle(.micro, tone: .tertiary)
                }

                Spacer(minLength: LauncherSpace.sm)

                if isCurrent {
                    LauncherBadge("当前", tone: .accent, systemImage: "checkmark")
                }
            }
            .padding(.horizontal, LauncherSpace.md)
            .padding(.vertical, LauncherSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .fill(isCurrent ? theme.colors.surfaceActive : theme.colors.surfaceSubtle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .strokeBorder(isCurrent ? theme.colors.accent : theme.colors.stroke, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .launcherPointer()
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// 外观实时预览：圆角与描边直接读取 ThemeManager 的乘数，拖动滑块即可看到变化。
    private var appearancePreview: some View {
        let radius = themeManager.radius(LauncherRadius.md)
        return VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            Text("实时预览")
                .textStyle(.micro, tone: .tertiary)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(theme.colors.stroke, lineWidth: 1)
                }
                .overlay {
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherStatusDot(tone: .success)
                        Text("面板描边与圆角")
                            .textStyle(.caption, tone: .secondary)
                        Spacer(minLength: 0)
                        LauncherMonoText(
                            "\(Int(radius))pt · \(borderStrengthText)×",
                            tone: .tertiary,
                            size: 10
                        )
                    }
                    .padding(.horizontal, LauncherSpace.md)
                }
                .frame(height: LauncherControl.large)
        }
    }

    // MARK: - 6. 账户

    /// 账户区块：头像、名称 / 类型 / 上次登录 + 切换与登出。
    private var accountCard: some View {
        settingsCard(
            "账户",
            subtitle: "账户信息仅保存在本机钥匙串",
            accessory: AnyView(
                LauncherBadge(
                    isSignedIn ? "在线" : "未登录",
                    tone: isSignedIn ? .success : .neutral,
                    systemImage: isSignedIn ? "circle.fill" : "person.crop.circle.badge.xmark"
                )
            )
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                HStack(spacing: LauncherSpace.md) {
                    LauncherAvatar(
                        name: accountDisplayName,
                        systemImage: "person.fill",
                        size: 40,
                        isOnline: isSignedIn
                    )

                    VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        Text(accountDisplayName)
                            .textStyle(.bodyStrong)
                            .lineLimit(1)
                        Text(accountDisplayType)
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                        Text(accountLastLogin)
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: LauncherSpace.sm) {
                    if isSignedIn {
                        LauncherButton(
                            "切换账户",
                            systemImage: "arrow.triangle.2.circlepath",
                            variant: .secondary,
                            size: .small
                        ) {
                            switchAccount()
                        }
                        LauncherButton(
                            "退出登录",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            variant: .secondary,
                            size: .small
                        ) {
                            signOut()
                        }
                    } else {
                        LauncherButton(
                            "登录",
                            systemImage: "person.badge.key.fill",
                            variant: .primary,
                            size: .small
                        ) {
                            signIn()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - 7. 关于

    /// 关于区块：版本 / 构建 / 提交 + 检查更新与日志入口。
    private var aboutCard: some View {
        settingsCard(
            "关于",
            subtitle: "方块启动器 · 开源 UI 模板",
            accessory: AnyView(LauncherMonoText("v0.2.0", tone: .tertiary, size: 10))
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                VStack(spacing: LauncherSpace.sm) {
                    LauncherKeyValueRow(key: "版本", value: "v0.2.0")
                    LauncherKeyValueRow(key: "构建", value: "2026.11.01.1380")
                    LauncherKeyValueRow(key: "提交", value: "8f3c2a1")
                }

                LauncherDivider()

                HStack(spacing: LauncherSpace.sm) {
                    LauncherButton(
                        "检查更新",
                        systemImage: "arrow.triangle.2.circlepath",
                        variant: .secondary,
                        size: .small
                    ) {
                        checkForUpdate()
                    }
                    LauncherButton(
                        "打开日志",
                        systemImage: "doc.text.magnifyingglass",
                        variant: .secondary,
                        size: .small
                    ) {
                        openLog()
                    }
                    Spacer(minLength: 0)
                }

                Text(updateStatus)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)

                if !logHint.isEmpty {
                    Text(logHint)
                        .textStyle(.micro, tone: .success)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - 8. 底部保存条

    /// 底部操作条：保存 / 恢复默认 + 右侧自动保存提示。
    private var saveBar: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            HStack(spacing: LauncherSpace.md) {
                LauncherButton("保存设置", systemImage: "checkmark", variant: .primary) {
                    saveSettings()
                }
                LauncherButton("恢复默认", systemImage: "arrow.counterclockwise", variant: .secondary) {
                    resetSettings()
                }
                Spacer(minLength: LauncherSpace.md)
                HStack(spacing: LauncherSpace.xs) {
                    LauncherStatusDot(tone: saveHintIsSuccess ? .success : .neutral)
                    Text(saveHint)
                        .textStyle(.monoSmall, tone: saveHintIsSuccess ? .success : .tertiary)
                }
            }
        }
    }

    // MARK: - 通用布局

    /// 设置卡片：面板 + 区块标题 + 内容，保证所有区块节奏一致。
    private func settingsCard<Content: View>(
        _ title: String,
        subtitle: String,
        accessory: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        LauncherCard(level: .regular, padding: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherSectionHeader(title: title, subtitle: subtitle, accessory: accessory)
                content()
            }
        }
    }

    /// 设置行：左侧标题 / 说明，右侧控件，统一最小行高保证跨行对齐。
    private func settingRow<Control: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text(title)
                    .textStyle(.bodyStrong)
                if let subtitle {
                    Text(subtitle)
                        .textStyle(.micro, tone: .tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: LauncherSpace.md)
            control()
        }
        .frame(minHeight: LauncherControl.large)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 状态派生

    /// Java 卡片副标题：只取 detail 的版本部分，避免三列窄卡片里被截断。
    private func javaSubtitle(_ runtime: LauncherJavaRuntime) -> String {
        runtime.detail.components(separatedBy: " · ").first ?? runtime.detail
    }

    /// 当前选中的 Java 运行时。
    private var selectedJava: LauncherJavaRuntime? {
        LauncherDemoData.javaRuntimes.first { $0.id == selectedJavaID }
    }

    /// 内存行说明：随滑杆值给出不同建议。
    private var memoryHint: String {
        if Int(memory) < 2048 {
            return "低于推荐值 2048 MB，启动大整合包时可能频繁卡顿"
        }
        if Int(memory) > 6144 {
            return "超过 6144 MB 对 1.21.4 的收益有限，建议回到 4096 MB"
        }
        return "推荐 4096 MB，适合 1.21.4 + 214 个模组的实例"
    }

    /// JVM 参数行数（参与渲染，避免出现无反馈的输入区）。
    private var jvmArgumentLines: Int {
        jvmArguments
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    /// 更新通道标题。
    private var updateChannelTitle: String {
        switch updateChannel {
        case "snapshot": return "快照"
        case "preview": return "预览"
        default: return "正式版"
        }
    }

    /// 更新通道选项。
    private var updateChannelOptions: [LauncherSegment<String>] {
        [
            LauncherSegment(id: "release", title: "正式版", systemImage: "checkmark.seal"),
            LauncherSegment(id: "snapshot", title: "快照", systemImage: "bolt"),
            LauncherSegment(id: "preview", title: "预览", systemImage: "sparkles")
        ]
    }

    /// 界面语言选项。
    private var languageOptions: [LauncherSegment<String>] {
        [
            LauncherSegment(id: "zh-Hans", title: "简体中文"),
            LauncherSegment(id: "en", title: "English"),
            LauncherSegment(id: "ja", title: "日本語")
        ]
    }

    /// 边框强度显示（保留一位小数）。
    private var borderStrengthText: String {
        String((themeManager.borderStrength * 10).rounded() / 10)
    }

    /// 圆角缩放显示（保留一位小数）。
    private var cornerScaleText: String {
        String((themeManager.cornerScale * 10).rounded() / 10)
    }

    /// 当前主题名字。
    private var currentThemeName: String {
        themeManager.presets.first { $0.id == themeManager.themeID }?.name ?? theme.name
    }

    /// 账户显示名（演示：在两个账户之间切换）。
    private var accountDisplayName: String {
        guard isSignedIn else { return "未登录" }
        return accountSlot == 0 ? "Steve_2026" : "Alex_2027"
    }

    /// 账户类型说明。
    private var accountDisplayType: String {
        isSignedIn ? "微软账户 · 正版" : "点击「登录」使用微软账户验证"
    }

    /// 上次登录时间。
    private var accountLastLogin: String {
        guard isSignedIn else { return "尚未登录" }
        return accountSlot == 0 ? "上次登录 今天 09:12" : "上次登录 昨天 21:40"
    }

    // MARK: - 绑定

    /// 最大内存绑定：吸附到 128 MB 步长，拖动时数值稳定不抖动。
    private var memoryBinding: Binding<Double> {
        Binding(
            get: { memory },
            set: { memory = ($0 / 128).rounded() * 128 }
        )
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

    // MARK: - 交互（仅 UI 模拟）

    /// 模拟选择目录：在两个演示路径之间切换。
    private func browseDirectory() {
        directoryPickIndex = (directoryPickIndex + 1) % 2
        gameDirectory = directoryPickIndex == 0
            ? LauncherDemoData.versionDirectory
            : "~/Documents/Minecraft/instances"
    }

    /// 模拟重新扫描 Java 运行时。
    private func detectJava() {
        guard !isDetectingJava else { return }
        isDetectingJava = true
        javaStatus = "正在扫描 Java 运行时…"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            isDetectingJava = false
            javaStatus = "检测完成 · 3 个运行时可用"
        }
    }

    /// 保存：只改提示文案（演示模式不写盘）。
    private func saveSettings() {
        saveHint = "已保存于 刚刚"
        saveHintIsSuccess = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            saveHint = "所有修改会自动保存"
            saveHintIsSuccess = false
        }
    }

    /// 恢复默认：把所有设置与外观参数复位。
    private func resetSettings() {
        gameDirectory = LauncherDemoData.versionDirectory
        versionIsolation = true
        minimizeAfterLaunch = true
        checkUpdatesOnStart = true
        selectedJavaID = LauncherDemoData.javaRuntimes.first?.id ?? "21"
        javaStatus = "上次检测：今天 09:12 · 3 个运行时可用"
        memory = 4096
        renderThreads = 4
        jvmArguments = "-XX:+UseG1GC\n-XX:MaxGCPauseMillis=50\n-Xms2048m"
        updateChannel = "release"
        autoCheckUpdates = true
        language = "zh-Hans"
        themeManager.borderStrength = 1.0
        themeManager.cornerScale = 1.0
        themeManager.select(LauncherThemes.default.id)
        saveHint = "已恢复默认设置"
        saveHintIsSuccess = true
    }

    /// 模拟检查更新。
    private func checkForUpdate() {
        updateStatus = "正在检查更新…"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            updateStatus = "已是最新版本 v0.2.0"
        }
    }

    /// 模拟打开日志。
    private func openLog() {
        logHint = "已打开日志：~/Library/Logs/MCLauncher/launcher.log"
    }

    /// 模拟切换账户。
    private func switchAccount() {
        accountSlot = accountSlot == 0 ? 1 : 0
    }

    /// 模拟退出登录。
    private func signOut() {
        isSignedIn = false
    }

    /// 模拟重新登录。
    private func signIn() {
        isSignedIn = true
    }
}
