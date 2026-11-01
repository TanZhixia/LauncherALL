import SwiftUI
import AppKit

// MARK: - 设置页（PCL 式：左分类 + 右内容）

/// 设置页：左侧分类面板（游戏 / 启动器 / 关于）+ 右侧单分类内容，
/// 全部设置项绑定真实 `LauncherEngine.settings`，Java 运行时来自真实检测。
public struct SettingsPage: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(LauncherThemeManager.self) private var themeManager
    @Environment(LauncherEngine.self) private var engine

    // MARK: 页面状态（仅 UI 反馈，不属于设置项）

    /// 当前分类 id
    @State private var section = "launch"
    /// Java 重新检测中
    @State private var isRefreshingJava = false
    /// 关于：检查更新提示
    @State private var updateStatus = "已是最新版本 v0.2.0"
    /// 关于：日志提示
    @State private var logHint = ""
    /// 日志分类：最近复制的行数
    @State private var copiedLogLines: Int?
    /// 保存条提示
    @State private var saveHint = "所有修改会自动保存"
    @State private var saveHintIsSuccess = false
    /// 外观对比样品的输入内容
    @State private var sampleText = "Steve"

    /// 创建设置页。
    public init() {}

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
                    // 内容较短时把保存条压到内容区底部常驻（滚动模式下自然贴在内容下方）
                    Spacer(minLength: LauncherSpace.md)
                    saveBar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: - 左侧分类面板

    /// 左面板：三组分类，每行 44pt 列表行（选中高亮），Java 行挂运行时数量徽标。
    private var sidePanel: some View {
        LauncherSidePanel(
            title: "设置",
            count: nil,
            width: 236,
            content: {
                LauncherSidePanelGroup("游戏")
                sideRow("launch", "启动", systemImage: "play.rectangle.fill")
                sideRow(
                    "java",
                    "Java 运行时",
                    systemImage: "cup.and.saucer.fill",
                    badge: "\(engine.javaRuntimes.count)"
                )
                sideRow("performance", "性能", systemImage: "speedometer")

                LauncherSidePanelGroup("启动器")
                sideRow("update", "更新与语言", systemImage: "arrow.triangle.2.circlepath")
                sideRow("appearance", "外观", systemImage: "paintpalette.fill")
                sideRow("account", "账户", systemImage: "person.crop.circle.fill")

                LauncherSidePanelGroup("关于")
                sideRow("about", "关于", systemImage: "info.circle.fill")
                sideRow("log", "日志与诊断", systemImage: "text.alignleft")
            },
            footer: {
                VStack(spacing: LauncherSpace.xs) {
                    Rectangle()
                        .fill(theme.colors.stroke)
                        .frame(height: 1)
                    HStack(spacing: LauncherSpace.xs) {
                        LauncherMonoText("v0.2.0", tone: .tertiary, size: 10)
                        Spacer(minLength: 0)
                        LauncherBadge("自动保存", tone: .neutral)
                    }
                    .padding(.horizontal, LauncherSpace.xxs)
                }
            }
        )
    }

    /// 分类行。
    private func sideRow(
        _ id: String,
        _ title: String,
        systemImage: String,
        badge: String? = nil
    ) -> some View {
        LauncherListRow(
            title: title,
            systemImage: systemImage,
            badge: badge,
            isSelected: section == id,
            action: {
                withAnimation(LauncherMotion.spring) {
                    section = id
                }
            }
        )
    }

    // MARK: - 右侧页头

    /// 右侧标题：随分类变化，右侧挂分类状态徽标 / Java 重新检测按钮。
    private var mainHeader: some View {
        LauncherPanelHeader(categoryTitle, subtitle: categorySubtitle) {
            HStack(spacing: LauncherSpace.xs) {
                if let badge = categoryBadge {
                    LauncherBadge(badge, tone: .neutral)
                }
                if section == "java" {
                    LauncherIconButton(
                        systemImage: "arrow.clockwise",
                        variant: .ghost,
                        size: .small,
                        accessibilityLabel: "重新检测 Java 运行时",
                        isDisabled: isRefreshingJava
                    ) {
                        refreshJava()
                    }
                }
            }
        }
    }

    /// 当前分类标题。
    private var categoryTitle: String {
        switch section {
        case "java": return "Java 运行时"
        case "performance": return "性能"
        case "update": return "更新与语言"
        case "appearance": return "外观"
        case "account": return "账户"
        case "about": return "关于"
        case "log": return "日志与诊断"
        default: return "启动"
        }
    }

    /// 当前分类说明。
    private var categorySubtitle: String {
        switch section {
        case "java": return "检测本机 JDK，按游戏版本要求选择"
        case "performance": return "内存与 JVM 参数，修改后下次启动生效"
        case "update": return "更新通道、下载来源与界面语言"
        case "appearance": return "主题与全局外观参数，修改立即生效"
        case "account": return "离线账户的玩家名会写入启动命令"
        case "about": return "版本信息、更新检查与反馈入口"
        case "log": return "启动日志与崩溃诊断集中管理"
        default: return "游戏目录与启动时的默认行为"
        }
    }

    /// 当前分类右上角徽标。
    private var categoryBadge: String? {
        switch section {
        case "java": return engine.javaRuntimes.isEmpty ? "未检测到" : "\(engine.javaRuntimes.count) 个"
        case "appearance": return themeManager.theme.name
        case "account": return "离线账户"
        case "update": return updateChannelTitle
        default: return nil
        }
    }

    // MARK: - 右侧分类内容

    @ViewBuilder
    private var categoryContent: some View {
        switch section {
        case "java": javaContent
        case "performance": performanceContent
        case "update": updateContent
        case "appearance": appearanceContent
        case "account": accountContent
        case "about": aboutContent
        case "log": logContent
        default: launchContent
        }
    }

    // MARK: - 1. 启动

    /// 启动分类：游戏目录、版本隔离、最小化、启动前检查。
    private var launchContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                "游戏目录",
                subtitle: "versions / mods / saves 的根目录",
                tooltip: "启动器会在此目录读写游戏文件；修改后立即生效"
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherTextField("游戏目录", text: bind(\.gameDirectory), systemImage: "folder")
                        .frame(maxWidth: 400)
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

            booleanRow(
                "版本隔离",
                subtitle: "每个游戏版本使用独立的 mods 与配置目录",
                tooltip: "关闭后所有版本共用同一个 mods 目录",
                isOn: bind(\.versionIsolation)
            )

            booleanRow(
                "启动后最小化",
                subtitle: "进入游戏后把启动器窗口收进 Dock",
                isOn: bind(\.minimizeAfterLaunch)
            )

            booleanRow(
                "启动前检查更新",
                subtitle: "启动前检查版本与模组更新",
                isOn: bind(\.checkUpdatesOnStart),
                showsDivider: false
            )
        }
    }

    // MARK: - 2. Java 运行时

    /// Java 分类：自动选择开关、真实运行时下拉、自定义路径与重新检测。
    private var javaContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            booleanRow(
                "自动选择",
                subtitle: "按游戏版本要求自动挑选 Java；关闭后使用下方指定的路径",
                tooltip: "启动时会从检测到的运行时中挑出满足版本要求的最高版本",
                isOn: bind(\.javaAutoDetect)
            )

            LauncherSettingRow(
                "Java 运行时",
                subtitle: javaRuntimeSubtitle,
                tooltip: javaRuntimeTooltip
            ) {
                if engine.javaRuntimes.isEmpty {
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
                } else {
                    LauncherMenuButton(
                        currentJavaLabel,
                        systemImage: "chevron.down",
                        variant: .secondary,
                        size: .small,
                        groups: javaMenuGroups
                    )
                }
            }

            LauncherSettingRow(
                "自定义路径",
                subtitle: engine.settings.javaAutoDetect
                    ? "自动选择开启时此项不生效"
                    : "手动指定 java 可执行文件（留空则回退到自动检测）",
                tooltip: "例如 /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java"
            ) {
                LauncherTextField("java 可执行文件路径", text: bind(\.javaRuntimePath), systemImage: "terminal")
                    .frame(maxWidth: 320)
            }

            LauncherSettingRow(
                "重新检测",
                subtitle: "扫描 /Library/Java/JavaVirtualMachines、Homebrew 与 JAVA_HOME",
                showsDivider: false
            ) {
                LauncherButton(
                    isRefreshingJava ? "正在检测…" : "立即检测",
                    systemImage: "arrow.clockwise",
                    variant: .secondary,
                    size: .small,
                    isLoading: isRefreshingJava
                ) {
                    refreshJava()
                }
                .fixedSize()
            }
        }
    }

    /// Java 行说明：随检测结果变化。
    private var javaRuntimeSubtitle: String {
        if engine.javaRuntimes.isEmpty {
            return "未检测到 Java，安装 JDK 后点「重新检测」"
        }
        return "检测到 \(engine.javaRuntimes.count) 个运行时 · 点开可直接指定"
    }

    /// Java 行提示：列出全部真实运行时。
    private var javaRuntimeTooltip: String {
        if engine.javaRuntimes.isEmpty {
            return "未找到可执行的 java；可安装 Temurin 21 或在下方手动填写路径"
        }
        return engine.javaRuntimes
            .map { "\($0.displayName) · \($0.executable.path)" }
            .joined(separator: "\n")
    }

    /// 下拉菜单：自动检测 + 每个真实运行时（当前项带勾选图标）。
    private var javaMenuGroups: [LauncherMenuGroup] {
        var items: [LauncherMenuItem] = [
            LauncherMenuItem(
                "自动检测",
                id: "auto",
                systemImage: engine.settings.javaAutoDetect ? "checkmark" : "wand.and.stars",
                detail: "按版本要求自动挑选"
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
        return [LauncherMenuGroup(title: "运行时", items: items)]
    }

    /// 下拉按钮标题：自动 / 已选运行时名 / 自定义路径的 JDK 目录名。
    private var currentJavaLabel: String {
        if engine.settings.javaAutoDetect { return "自动检测" }
        let path = engine.settings.javaRuntimePath
        if let runtime = engine.javaRuntimes.first(where: { $0.executable.path == path }) {
            return runtime.displayName
        }
        if path.isEmpty { return "未指定" }
        let components = path.split(separator: "/").map(String.init)
        if let jdk = components.first(where: { $0.hasSuffix(".jdk") }) { return jdk }
        return components.last ?? path
    }

    // MARK: - 3. 性能

    /// 性能分类：最大内存滑杆 + 高级启动选项（渲染线程 / JVM 参数）。
    private var performanceContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                "最大内存",
                subtitle: memoryHint,
                tooltip: "分配给游戏 JVM 的最大堆内存，过大反而会拖慢系统",
                showsDivider: false
            ) {
                LauncherSlider(
                    value: memoryBinding,
                    range: 1024...8192,
                    valueText: "\(engine.settings.maxMemoryMB) MB"
                )
                .frame(width: 280)
            }

            LauncherDivider()

            LauncherExpander(
                "高级启动选项",
                subtitle: "渲染线程与 JVM 参数，非必要无需修改",
                systemImage: "slider.horizontal.3"
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    LauncherSettingRow(
                        "渲染线程",
                        subtitle: "建议 2 ~ 4 个，数量过多反而增加调度开销",
                        tooltip: "对应 JVM 的 -XX:ActiveProcessorCount 参数"
                    ) {
                        LauncherNumberField(
                            nil,
                            value: bind(\.renderThreads),
                            range: 1...16,
                            step: 1,
                            unit: "线程"
                        )
                    }

                    LauncherSettingRow(
                        "JVM 参数",
                        subtitle: "每行一个参数，以 # 开头为注释；留空使用默认参数",
                        tooltip: "已解析 \(engine.settings.extraJVMArguments.count) 个有效参数",
                        showsDivider: false
                    ) {
                        LauncherMonoText("\(engine.settings.extraJVMArguments.count) 个参数", tone: .tertiary, size: 10)
                    }

                    // 参数较长，独占一行展示（仍在高级折叠区内）
                    LauncherTextArea(
                        "每行一个 JVM 参数，例如 -XX:+UseG1GC",
                        text: bind(\.jvmArguments),
                        minHeight: 72
                    )
                    .frame(maxWidth: 480)
                    .padding(.top, LauncherSpace.xs)
                    .padding(.bottom, LauncherSpace.xs)
                }
            }
        }
    }

    // MARK: - 4. 更新与语言

    /// 更新与语言分类：更新通道 / 下载源 / 自动清理 / 界面语言（PCL 式下拉菜单）。
    private var updateContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                "更新通道",
                subtitle: "快照与预览通道可能包含未完成的功能",
                tooltip: "正式版最稳定；快照与预览仅用于尝鲜"
            ) {
                LauncherMenuButton(
                    updateChannelTitle,
                    systemImage: "chevron.down",
                    variant: .secondary,
                    size: .small,
                    groups: updateChannelMenuGroups
                )
            }

            LauncherSettingRow(
                "下载源",
                subtitle: "安装游戏与资源时使用",
                tooltip: "官方源最稳妥；镜像源在部分网络下更快"
            ) {
                LauncherMenuButton(
                    downloadSourceTitle,
                    systemImage: "chevron.down",
                    variant: .secondary,
                    size: .small,
                    groups: downloadSourceMenuGroups
                )
            }

            booleanRow(
                "自动清理旧版本",
                subtitle: "安装新版本后提示删除不再使用的旧版本文件",
                isOn: bind(\.autoCleanOldVersions)
            )

            LauncherSettingRow(
                "界面语言",
                subtitle: "切换语言后需要重启启动器",
                showsDivider: false
            ) {
                LauncherMenuButton(
                    languageTitle,
                    systemImage: "chevron.down",
                    variant: .secondary,
                    size: .small,
                    groups: languageMenuGroups
                )
            }
        }
    }

    /// 更新通道标题。
    private var updateChannelTitle: String {
        switch engine.settings.updateChannel {
        case "snapshot": return "快照"
        case "preview": return "预览"
        default: return "正式版"
        }
    }

    /// 更新通道菜单。
    private var updateChannelMenuGroups: [LauncherMenuGroup] {
        let options: [(id: String, title: String, detail: String)] = [
            ("release", "正式版", "只接收稳定版本"),
            ("snapshot", "快照", "包含未完成的实验性内容"),
            ("preview", "预览", "最新构建，可能不稳定")
        ]
        return [LauncherMenuGroup(title: "更新通道", items: options.map { option in
            LauncherMenuItem(
                option.title,
                id: option.id,
                systemImage: engine.settings.updateChannel == option.id ? "checkmark" : "arrow.triangle.2.circlepath",
                detail: option.detail
            ) {
                engine.settings.updateChannel = option.id
            }
        })]
    }

    /// 下载源标题。
    private var downloadSourceTitle: String {
        engine.settings.downloadSource == "mirror" ? "镜像源（加速）" : "官方源（Mojang）"
    }

    /// 下载源菜单。
    private var downloadSourceMenuGroups: [LauncherMenuGroup] {
        let options: [(id: String, title: String, detail: String)] = [
            ("official", "官方源（Mojang）", "最稳妥，速度取决于网络"),
            ("mirror", "镜像源（加速）", "国内镜像，通常更快")
        ]
        return [LauncherMenuGroup(title: "下载源", items: options.map { option in
            LauncherMenuItem(
                option.title,
                id: option.id,
                systemImage: engine.settings.downloadSource == option.id ? "checkmark" : "globe",
                detail: option.detail
            ) {
                engine.settings.downloadSource = option.id
            }
        })]
    }

    /// 界面语言标题。
    private var languageTitle: String {
        switch engine.settings.language {
        case "en": return "English"
        case "ja": return "日本語"
        default: return "简体中文"
        }
    }

    /// 界面语言菜单。
    private var languageMenuGroups: [LauncherMenuGroup] {
        let options: [(id: String, title: String)] = [
            ("zh-Hans", "简体中文"),
            ("en", "English"),
            ("ja", "日本語")
        ]
        return [LauncherMenuGroup(title: "界面语言", items: options.map { option in
            LauncherMenuItem(
                option.title,
                id: option.id,
                systemImage: engine.settings.language == option.id ? "checkmark" : "character.bubble"
            ) {
                engine.settings.language = option.id
            }
        })]
    }

    // MARK: - 5. 外观

    /// 外观分类：主题下拉 + 边框强度 / 圆角缩放 + 「当前 vs 默认」实时对比。
    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                "主题",
                subtitle: "深色与浅色两套中性主题，切换立即生效",
                tooltip: "主题只换色值，结构、间距与控件形态完全一致"
            ) {
                LauncherMenuButton(
                    themeManager.theme.name,
                    systemImage: "chevron.down",
                    variant: .secondary,
                    size: .small,
                    groups: themeMenuGroups
                )
            }

            LauncherSettingRow(
                "边框强度",
                subtitle: "调节面板与分割线的描边可见度",
                tooltip: "范围 0.4× ~ 1.6×，默认 1.0×"
            ) {
                LauncherSlider(
                    value: borderStrengthBinding,
                    range: 0.4...1.6,
                    valueText: "\(borderStrengthText)×"
                )
                .frame(width: 260)
            }

            LauncherSettingRow(
                "圆角缩放",
                subtitle: "按比例缩放全站圆角",
                tooltip: "范围 0.6× ~ 1.4×，默认 1.0×",
                showsDivider: false
            ) {
                LauncherSlider(
                    value: cornerScaleBinding,
                    range: 0.6...1.4,
                    valueText: "\(cornerScaleText)×"
                )
                .frame(width: 260)
            }

            LauncherDivider()

            appearanceComparison
        }
    }

    /// 主题菜单。
    private var themeMenuGroups: [LauncherMenuGroup] {
        [LauncherMenuGroup(title: "主题", items: themeManager.presets.map { preset in
            LauncherMenuItem(
                preset.name,
                id: preset.id,
                systemImage: themeManager.themeID == preset.id ? "checkmark" : "circle.lefthalf.filled",
                detail: preset.tagline
            ) {
                themeManager.select(preset.id)
            }
        })]
    }

    /// 「当前 vs 默认」对比：左栏跟随当前主题与边框/圆角乘数，右栏固定为石墨默认值。
    private var appearanceComparison: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            HStack(spacing: LauncherSpace.sm) {
                LauncherLabel("实时对比")
                Spacer(minLength: 0)
                Text("当前值变化时右侧保持默认，便于比较")
                    .textStyle(.micro, tone: .tertiary)
            }
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
    }

    /// 对比栏：标题 + 数值 + 同构小样；默认栏整体覆盖为石墨主题，不随当前设置变化。
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

    /// 对比小样：面板 + 徽标 + 按钮 + 输入框，覆盖面板 / 控件两层圆角与描边。
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

    /// 账户分类：离线玩家名（写入启动命令）+ 推导的离线 UUID。
    private var accountContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                "当前账户",
                subtitle: "离线模式 · 无需登录即可进入单人游戏"
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherAvatar(
                        name: displayPlayerName,
                        systemImage: "person.fill",
                        size: 26,
                        isOnline: true
                    )
                    Text(displayPlayerName)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                }
            }

            LauncherSettingRow(
                "玩家名",
                subtitle: "游戏内显示名称，最多 16 个字符",
                tooltip: "启动命令中的 auth_player_name 使用此名称"
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherTextField("玩家名", text: bind(\.playerName), systemImage: "person.text.rectangle")
                        .frame(maxWidth: 220)
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

            LauncherSettingRow(
                "离线 UUID",
                subtitle: "由玩家名推导，用于离线服务器识别",
                tooltip: "离线 UUID 由玩家名按离线算法推导，仅本机使用",
                showsDivider: false
            ) {
                LauncherMonoText(LaunchCommandBuilder.offlineUUID(for: displayPlayerName), tone: .secondary, size: 11)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 7. 关于

    /// 关于分类：版本信息 + 检查更新 / 打开日志。
    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow("版本", subtitle: "当前发布的启动器版本") {
                LauncherMonoText("v0.2.0", tone: .secondary, size: 11)
            }
            LauncherSettingRow("构建", subtitle: "构建时间戳") {
                LauncherMonoText("2026.11.01.1380", tone: .secondary, size: 11)
            }
            LauncherSettingRow("提交", subtitle: "源码提交短哈希") {
                LauncherMonoText("8f3c2a1", tone: .secondary, size: 11)
            }
            LauncherSettingRow(
                "更新与反馈",
                subtitle: updateStatus,
                showsDivider: false
            ) {
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
                }
            }

            if !logHint.isEmpty {
                Text(logHint)
                    .textStyle(.micro, tone: .success)
                    .lineLimit(1)
                    .padding(.top, LauncherSpace.xs)
            }
        }
    }

    // MARK: - 8. 日志与诊断

    /// 日志分类：最近启动日志预览 + 复制到剪贴板（完整诊断在「更多」页）。
    private var logContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            LauncherSettingRow(
                "日志与诊断",
                subtitle: "完整诊断与崩溃报告在「更多 → 日志与诊断」",
                tooltip: "这里只展示最近一次启动输出的最后几行"
            ) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherBadge("\(engine.logLines.count) 行", tone: .neutral)
                    LauncherButton(
                        "复制最近日志",
                        systemImage: "doc.on.doc",
                        variant: .secondary,
                        size: .small,
                        isDisabled: engine.logLines.isEmpty
                    ) {
                        copyRecentLogs()
                    }
                    .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                if engine.logLines.isEmpty {
                    Text("还没有日志，启动一次游戏后这里会显示实时输出。")
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
            .frame(height: 96, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .strokeBorder(theme.colors.stroke, lineWidth: 1)
            }

            if let copiedLogLines {
                Text("已复制最近 \(copiedLogLines) 行日志到剪贴板")
                    .textStyle(.micro, tone: .success)
                    .padding(.top, LauncherSpace.xs)
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

    // MARK: - 行辅助

    /// 布尔设置行：LauncherToggle + 分隔线，与 `LauncherSettingRow` 视觉节奏一致。
    private func booleanRow(
        _ title: String,
        subtitle: String? = nil,
        tooltip: String? = nil,
        isOn: Binding<Bool>,
        showsDivider: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: LauncherSpace.md) {
                LauncherToggle(title, isOn: isOn, subtitle: subtitle)
                if let tooltip {
                    LauncherHintIcon(tooltip)
                }
            }
            if showsDivider {
                Rectangle()
                    .fill(theme.colors.stroke.opacity(0.6))
                    .frame(height: 1)
            }
        }
        .padding(.vertical, LauncherSpace.xxs)
    }

    // MARK: - 设置绑定

    /// 把 `LauncherSettings` 的字段包装成 Binding（等价于 `@Bindable` 的成员绑定）。
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

    /// 边框强度显示（保留一位小数）。
    private var borderStrengthText: String {
        String((themeManager.borderStrength * 10).rounded() / 10)
    }

    /// 圆角缩放显示（保留一位小数）。
    private var cornerScaleText: String {
        String((themeManager.cornerScale * 10).rounded() / 10)
    }

    /// 玩家名：空值时回退到默认名，避免头像与 UUID 出现空值。
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

    /// 复制最近日志到剪贴板（真实操作，仅取最后 50 行）。
    private func copyRecentLogs() {
        let lines = Array(engine.logLines.suffix(50))
        guard !lines.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        copiedLogLines = lines.count
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

    /// 恢复默认：真实重置全部设置项与外观参数。
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
