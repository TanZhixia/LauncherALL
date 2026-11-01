import SwiftUI
import AppKit

// MARK: - 设置页

/// 设置页：页内七个分区（启动 / Java / 性能 / 更新 / 外观 / 账户 / 关于），
/// 一次只渲染一个分区，最小窗口（1080×720）下无需纵向滚动。
/// 全部设置项绑定真实的 `LauncherEngine.settings`（自动持久化），Java 运行时来自真实检测。
public struct SettingsPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherThemeManager.self) private var themeManager
    @Environment(LauncherEngine.self) private var engine

    // MARK: 页面状态（仅 UI 反馈，不属于设置项）

    /// 当前分区 id
    @State private var section = "general"
    /// Java 重新检测中
    @State private var isRefreshingJava = false
    /// 关于分区：检查更新提示
    @State private var updateStatus = "已是最新版本 v0.2.0"
    /// 关于分区：日志提示
    @State private var logHint = ""
    /// 保存条提示
    @State private var saveHint = "所有修改会自动保存"
    @State private var saveHintIsSuccess = false
    /// 外观对比样品的输入内容
    @State private var sampleText = "Steve"

    /// 二级导航分区（rail 顺序）
    private let sections: [LauncherSectionItem] = [
        LauncherSectionItem(id: "general", title: "启动", systemImage: "play.rectangle.fill"),
        LauncherSectionItem(id: "java", title: "Java 运行时", systemImage: "cup.and.saucer.fill"),
        LauncherSectionItem(id: "performance", title: "性能", systemImage: "speedometer"),
        LauncherSectionItem(id: "update", title: "更新与语言", systemImage: "arrow.triangle.2.circlepath"),
        LauncherSectionItem(id: "appearance", title: "外观", systemImage: "paintpalette.fill"),
        LauncherSectionItem(id: "account", title: "账户", systemImage: "person.crop.circle.fill"),
        LauncherSectionItem(id: "about", title: "关于", systemImage: "info.circle.fill")
    ]

    /// 创建设置页。
    public init() {}

    public var body: some View {
        LauncherAppPage {
            LauncherPageHeader(title: "设置", subtitle: "启动行为、Java 运行时、性能与外观")

            LauncherSectionLayout {
                LauncherSectionRail(items: sections, selection: $section, header: nil)
            } content: {
                VStack(alignment: .leading, spacing: LauncherSpace.md) {
                    sectionContent
                    // 单分区内容较短时把保存条压到内容区底部常驻（滚动模式下自然贴在内容下方）
                    Spacer(minLength: LauncherSpace.md)
                    saveBar
                }
            }
        }
    }

    /// 当前分区的内容卡片。
    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case "java": javaSection
        case "performance": performanceSection
        case "update": updateSection
        case "appearance": appearanceSection
        case "account": accountSection
        case "about": aboutSection
        default: generalSection
        }
    }

    // MARK: - 1. 启动

    /// 启动分区：游戏目录、版本隔离、启动后最小化、启动前检查更新（全部为真实设置项）。
    private var generalSection: some View {
        settingsCard(
            "启动",
            subtitle: "游戏目录与启动时的默认行为",
            accessory: AnyView(LauncherBadge("本地", tone: .neutral, systemImage: "internaldrive"))
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                settingRow(
                    title: "游戏目录",
                    subtitle: "versions / mods / saves 的根目录"
                ) {
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherTextField("游戏目录", text: bind(\.gameDirectory), systemImage: "folder")
                            .frame(maxWidth: 440)
                        LauncherButton(
                            "浏览…",
                            systemImage: "folder.badge.plus",
                            variant: .secondary,
                            size: .small
                        ) {
                            chooseGameDirectory()
                        }
                        .fixedSize()
                    }
                }

                LauncherDivider()

                LauncherToggle(
                    "版本隔离",
                    isOn: bind(\.versionIsolation),
                    subtitle: "每个游戏版本使用独立的 mods 与配置目录"
                )

                LauncherDivider()

                LauncherToggle(
                    "启动后最小化",
                    isOn: bind(\.minimizeAfterLaunch),
                    subtitle: "进入游戏后把启动器窗口收进 Dock"
                )

                LauncherDivider()

                LauncherCheckbox("启动前检查版本与模组更新", isOn: bind(\.checkUpdatesOnStart))
            }
        }
    }

    // MARK: - 2. Java 运行时

    /// Java 分区：真实检测结果列表、自动检测开关、自定义路径与重新检测。
    private var javaSection: some View {
        settingsCard(
            "Java 运行时",
            subtitle: javaSubtitle,
            accessory: AnyView(LauncherBadge(
                engine.settings.javaAutoDetect ? "自动检测" : "手动指定",
                tone: engine.settings.javaAutoDetect ? .neutral : .accent,
                systemImage: engine.settings.javaAutoDetect ? "wand.and.stars" : "hand.point.up.left"
            ))
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                LauncherToggle(
                    "自动检测",
                    isOn: bind(\.javaAutoDetect),
                    subtitle: "开启后按版本要求自动挑选最合适的 Java；关闭后使用下方指定的路径"
                )

                if engine.javaRuntimes.isEmpty {
                    javaEmptyRow
                } else {
                    VStack(spacing: LauncherSpace.xxs) {
                        ForEach(Array(engine.javaRuntimes.prefix(3))) { runtime in
                            javaRuntimeRow(runtime)
                        }
                        if engine.javaRuntimes.count > 3 {
                            Text("另有 \(engine.javaRuntimes.count - 3) 个运行时未列出，可手动指定路径")
                                .textStyle(.micro, tone: .tertiary)
                                .padding(.leading, LauncherSpace.sm)
                        }
                    }
                }

                LauncherDivider()

                settingRow(
                    title: "自定义路径",
                    subtitle: engine.settings.javaAutoDetect
                        ? "自动检测开启时此项不生效"
                        : "手动指定 java 可执行文件（留空则回退到自动检测）"
                ) {
                    LauncherTextField("java 可执行文件路径", text: bind(\.javaRuntimePath), systemImage: "terminal")
                        .frame(maxWidth: 360)
                }

                HStack(spacing: LauncherSpace.md) {
                    LauncherButton(
                        "重新检测",
                        systemImage: "arrow.clockwise",
                        variant: .secondary,
                        size: .small,
                        isLoading: isRefreshingJava
                    ) {
                        refreshJava()
                    }
                    .fixedSize()
                    Text("扫描 /Library/Java/JavaVirtualMachines、Homebrew 与 JAVA_HOME")
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Java 卡片副标题：随真实检测结果变化。
    private var javaSubtitle: String {
        if engine.javaRuntimes.isEmpty {
            return "尚未检测到 Java，安装 JDK 后点「重新检测」"
        }
        return "检测到 \(engine.javaRuntimes.count) 个运行时，点一行即可手动指定"
    }

    /// 单个真实运行时行：标题 + 版本/厂商，副标题为可执行路径。
    private func javaRuntimeRow(_ runtime: JavaRuntime) -> some View {
        let isSelected = engine.settings.javaRuntimePath == runtime.executable.path
        return LauncherListRow(
            title: runtime.displayName,
            subtitle: "\(runtime.version) · \(runtime.executable.path)",
            systemImage: "cup.and.saucer.fill",
            badge: "Java \(runtime.majorVersion)",
            accessory: isSelected
                ? AnyView(Image(systemName: "checkmark")
                    .textStyle(.caption, tone: .accent))
                : nil,
            isSelected: isSelected,
            action: {
                // 手动点选即切换到手动模式，选择立刻生效
                engine.settings.javaRuntimePath = runtime.executable.path
                engine.settings.javaAutoDetect = false
            }
        )
    }

    /// 未检测到 Java 时的紧凑空状态（含重新检测按钮）。
    private var javaEmptyRow: some View {
        HStack(spacing: LauncherSpace.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .textStyle(.body, tone: .warning)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                        .fill(theme.colors.surfaceSubtle)
                }

            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text("未检测到 Java")
                    .textStyle(.bodyStrong)
                Text("安装 JDK（推荐 Temurin 21）后重新检测，或在下方手动指定路径")
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: LauncherSpace.sm)

            LauncherButton(
                "重新检测",
                systemImage: "arrow.clockwise",
                variant: .secondary,
                size: .small,
                isLoading: isRefreshingJava
            ) {
                refreshJava()
            }
            .fixedSize()
        }
        .padding(.horizontal, LauncherSpace.md)
        .padding(.vertical, LauncherSpace.sm)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .strokeBorder(theme.colors.stroke, lineWidth: 1)
        }
    }

    // MARK: - 3. 性能

    /// 性能分区：最大内存、渲染线程、JVM 参数（写入真实设置）。
    private var performanceSection: some View {
        settingsCard(
            "性能",
            subtitle: "修改后下次启动生效",
            accessory: AnyView(LauncherMonoText("建议 4096 MB", tone: .tertiary, size: 11))
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                settingRow(title: "最大内存", subtitle: memoryHint) {
                    LauncherSlider(
                        value: memoryBinding,
                        range: 1024...8192,
                        valueText: "\(engine.settings.maxMemoryMB) MB"
                    )
                    .frame(width: 300)
                }

                LauncherDivider()

                settingRow(
                    title: "渲染线程",
                    subtitle: "建议 2 ~ 4 个，数量过多反而增加调度开销"
                ) {
                    LauncherStepper(value: bind(\.renderThreads), range: 1...16, unit: "线程")
                        .frame(width: 200)
                }

                LauncherDivider()

                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: LauncherSpace.sm) {
                        Text("JVM 参数")
                            .textStyle(.bodyStrong)
                        Spacer(minLength: LauncherSpace.sm)
                        LauncherMonoText("\(engine.settings.extraJVMArguments.count) 行", tone: .tertiary, size: 10)
                    }
                    LauncherTextArea(
                        "每行一个 JVM 参数，例如 -XX:+UseG1GC",
                        text: bind(\.jvmArguments),
                        minHeight: 88
                    )
                    Text("每行一个参数，以 # 开头为注释；留空则使用启动器默认参数")
                        .textStyle(.micro, tone: .tertiary)
                }
            }
        }
    }

    // MARK: - 4. 更新与语言

    /// 更新与语言分区：更新通道、下载源、自动清理旧版本、界面语言。
    private var updateSection: some View {
        settingsCard(
            "更新与语言",
            subtitle: "更新通道与下载来源",
            accessory: AnyView(LauncherBadge(updateChannelTitle, tone: .accent))
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                settingRow(title: "更新通道", subtitle: "快照与预览通道可能包含未完成的功能") {
                    LauncherSegmentedControl(
                        options: updateChannelOptions,
                        selection: bind(\.updateChannel)
                    )
                    .frame(width: 330)
                }

                LauncherDivider()

                settingRow(title: "下载源", subtitle: "安装游戏与资源时使用") {
                    LauncherDropdown(
                        options: downloadSourceOptions,
                        selection: bind(\.downloadSource),
                        placeholder: "请选择下载源"
                    )
                    .frame(width: 210)
                }

                LauncherDivider()

                LauncherToggle(
                    "自动清理旧版本",
                    isOn: bind(\.autoCleanOldVersions),
                    subtitle: "安装新版本后提示删除不再使用的旧版本文件"
                )

                LauncherDivider()

                settingRow(title: "界面语言", subtitle: "切换语言后需要重启启动器") {
                    LauncherDropdown(
                        options: languageOptions,
                        selection: bind(\.language),
                        placeholder: "请选择语言"
                    )
                    .frame(width: 210)
                }
            }
        }
    }

    // MARK: - 5. 外观

    /// 外观分区：主题选择、边框强度、圆角缩放 +「当前 vs 默认」实时对比。
    private var appearanceSection: some View {
        settingsCard(
            "外观",
            subtitle: "主题与全局外观参数，修改立即生效",
            accessory: AnyView(LauncherBadge(currentThemeName, tone: .accent))
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                HStack(spacing: LauncherSpace.md) {
                    ForEach(themeManager.presets) { preset in
                        themeOption(preset)
                    }
                }

                LauncherDivider()

                VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                    LauncherSlider(
                        value: borderStrengthBinding,
                        range: 0.4...1.6,
                        label: "边框强度",
                        valueText: "\(borderStrengthText)×"
                    )
                    LauncherSlider(
                        value: cornerScaleBinding,
                        range: 0.6...1.4,
                        label: "圆角缩放",
                        valueText: "\(cornerScaleText)×"
                    )
                }

                LauncherDivider()

                appearanceComparison
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
                        .lineLimit(1)
                    Text(preset.tagline)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
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

    /// 「当前 vs 默认」实时对比：左栏跟随当前主题与边框/圆角乘数，右栏固定为石墨默认值。
    private var appearanceComparison: some View {
        HStack(alignment: .top, spacing: LauncherSpace.md) {
            comparisonColumn(
                title: "当前",
                caption: "\(Int(themeManager.radius(LauncherRadius.lg)))pt · \(borderStrengthText)×",
                cornerRadius: themeManager.radius(LauncherRadius.lg),
                themeOverride: nil
            )
            comparisonColumn(
                title: "默认",
                caption: "\(Int(LauncherRadius.lg))pt · 1.0×",
                cornerRadius: LauncherRadius.lg,
                themeOverride: LauncherThemes.graphite
            )
        }
    }

    /// 对比栏：标题 + 同构小样；默认栏整体覆盖为石墨主题，不随当前设置变化。
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

    /// 对比小样：玻璃面板 + 徽标 + 按钮 + 输入框，覆盖面板 / 控件两层圆角与描边。
    private func comparisonSample(cornerRadius: CGFloat) -> some View {
        GlassPanel(level: .regular, cornerRadius: cornerRadius, padding: LauncherSpace.sm) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                HStack(spacing: LauncherSpace.xs) {
                    LauncherBadge("示例", tone: .accent)
                    Spacer(minLength: 0)
                    LauncherButton("按钮", variant: .secondary, size: .small) {}
                        .fixedSize()
                }
                LauncherTextField("玩家名", text: $sampleText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 6. 账户

    /// 账户分区：离线账户的玩家名（写入真实设置，供启动命令使用）。
    private var accountSection: some View {
        settingsCard(
            "账户",
            subtitle: "离线账户的玩家名会写入启动命令",
            accessory: AnyView(LauncherBadge("离线账户", tone: .neutral, systemImage: "person.fill"))
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                HStack(spacing: LauncherSpace.md) {
                    LauncherAvatar(
                        name: displayPlayerName,
                        systemImage: "person.fill",
                        size: 40,
                        isOnline: true
                    )

                    VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        Text(displayPlayerName)
                            .textStyle(.bodyStrong)
                            .lineLimit(1)
                        Text("离线模式 · 无需登录即可进入单人游戏")
                            .textStyle(.micro, tone: .tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                LauncherDivider()

                settingRow(title: "玩家名", subtitle: "游戏内显示名称，最多 16 个字符") {
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherTextField("玩家名", text: bind(\.playerName), systemImage: "person.text.rectangle")
                            .frame(maxWidth: 240)
                        LauncherButton(
                            "恢复默认",
                            systemImage: "arrow.counterclockwise",
                            variant: .secondary,
                            size: .small
                        ) {
                            engine.settings.playerName = "Steve"
                        }
                        .fixedSize()
                    }
                }

                VStack(spacing: LauncherSpace.xs) {
                    LauncherKeyValueRow(key: "账户类型", value: "离线账户", isMono: false)
                    LauncherKeyValueRow(
                        key: "离线 UUID",
                        value: LaunchCommandBuilder.offlineUUID(for: displayPlayerName),
                        isMono: true
                    )
                }
            }
        }
    }

    // MARK: - 7. 关于

    /// 关于分区：版本 / 构建 / 提交 + 检查更新与日志入口。
    private var aboutSection: some View {
        settingsCard(
            "关于",
            subtitle: "方块启动器 · 原生 SwiftUI 启动器",
            accessory: AnyView(LauncherMonoText("v0.2.0", tone: .tertiary, size: 10))
        ) {
            VStack(alignment: .leading, spacing: LauncherSpace.md) {
                VStack(spacing: LauncherSpace.xs) {
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
                    .fixedSize()
                    LauncherButton(
                        "打开日志",
                        systemImage: "doc.text.magnifyingglass",
                        variant: .secondary,
                        size: .small
                    ) {
                        openLog()
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                    Text(updateStatus)
                        .textStyle(.micro, tone: .tertiary)
                        .lineLimit(1)
                }

                if !logHint.isEmpty {
                    Text(logHint)
                        .textStyle(.micro, tone: .success)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - 保存条（右列常驻）

    /// 保存条：设置本身会自动持久化，保存按钮只给出可见反馈。
    private var saveBar: some View {
        LauncherCard(level: .regular, padding: LauncherSpace.md) {
            HStack(spacing: LauncherSpace.md) {
                LauncherButton("保存设置", systemImage: "checkmark", variant: .primary) {
                    saveSettings()
                }
                .fixedSize()
                LauncherButton("恢复默认", systemImage: "arrow.counterclockwise", variant: .secondary) {
                    resetSettings()
                }
                .fixedSize()
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

    /// 分区卡片：面板 + 区块标题 + 内容，保证各分区节奏一致。
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
                        .lineLimit(1)
                }
            }
            Spacer(minLength: LauncherSpace.md)
            control()
        }
        .frame(minHeight: LauncherControl.large)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 设置绑定

    /// 把 `LauncherSettings` 的字段包装成 Binding（等价于 `@Bindable` 的动态成员绑定）。
    private func bind<T>(_ keyPath: ReferenceWritableKeyPath<LauncherSettings, T>) -> Binding<T> {
        Binding(
            get: { engine.settings[keyPath: keyPath] },
            set: { engine.settings[keyPath: keyPath] = $0 }
        )
    }

    /// 最大内存绑定：Int 设置项 ↔ Double 滑杆，吸附到 128 MB 步长。
    private var memoryBinding: Binding<Double> {
        Binding(
            get: { Double(engine.settings.maxMemoryMB) },
            set: { engine.settings.maxMemoryMB = Int(($0 / 128).rounded() * 128) }
        )
    }

    /// 边框强度绑定（ThemeManager）。
    private var borderStrengthBinding: Binding<Double> {
        Binding(
            get: { themeManager.borderStrength },
            set: { themeManager.borderStrength = $0 }
        )
    }

    /// 圆角缩放绑定（ThemeManager）。
    private var cornerScaleBinding: Binding<Double> {
        Binding(
            get: { themeManager.cornerScale },
            set: { themeManager.cornerScale = $0 }
        )
    }

    // MARK: - 状态派生

    /// 内存行说明：随当前设置给出建议。
    private var memoryHint: String {
        let value = engine.settings.maxMemoryMB
        if value < 2048 {
            return "低于推荐值 2048 MB，启动大整合包时可能频繁卡顿"
        }
        if value > 6144 {
            return "超过 6144 MB 对 1.21.4 的收益有限，建议回到 4096 MB"
        }
        return "推荐 4096 MB，适合 1.21.4 + 214 个模组的实例"
    }

    /// 更新通道标题。
    private var updateChannelTitle: String {
        switch engine.settings.updateChannel {
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

    /// 下载源选项。
    private var downloadSourceOptions: [LauncherSegment<String>] {
        [
            LauncherSegment(id: "official", title: "官方源（Mojang）"),
            LauncherSegment(id: "mirror", title: "镜像源（加速）")
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

    /// 玩家名：空值时回退到默认名，避免头像与启动命令出现空字符串。
    private var displayPlayerName: String {
        let name = engine.settings.playerName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Steve" : name
    }

    // MARK: - 交互

    /// 选择游戏目录：真实打开系统文件夹选择器。
    private func chooseGameDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择 Minecraft 游戏目录"
        panel.directoryURL = engine.settings.resolvedGameDirectory
        if panel.runModal() == .OK, let url = panel.url {
            engine.settings.gameDirectory = url.path
        }
    }

    /// 真实重新扫描 Java 运行时。
    private func refreshJava() {
        guard !isRefreshingJava else { return }
        isRefreshingJava = true
        Task { @MainActor in
            await engine.refreshEnvironment()
            isRefreshingJava = false
        }
    }

    /// 保存：设置已自动持久化，这里只给可见反馈。
    private func saveSettings() {
        saveHint = "已保存"
        saveHintIsSuccess = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            saveHint = "所有修改会自动保存"
            saveHintIsSuccess = false
        }
    }

    /// 恢复默认：真实重置全部设置项。
    private func resetSettings() {
        engine.settings.resetToDefaults()
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
}
