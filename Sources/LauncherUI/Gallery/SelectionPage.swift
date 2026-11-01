import SwiftUI

/// 选择控件画廊页：开关、复选、Java 运行时单选卡、滑杆、分段控件、下拉与步进器。
public struct SelectionPage: View {
    @State private var autoUpdateMods = false
    @State private var smartMemory = true
    @State private var minimizeAfterLaunch = false
    @State private var backupSaves = true
    @State private var backupMods = true
    @State private var backupScreenshots = false
    @State private var javaRuntime = "java21"
    @State private var glassIntensity: Double = 1.0
    @State private var renderDistance: Double = 12
    @State private var performanceProfile = "平衡"
    @State private var loaderID = "fabric"
    @State private var maxFPS = 120

    private let profileOptions: [LauncherSegment<String>] = [
        LauncherSegment(id: "性能", title: "性能", systemImage: "speedometer"),
        LauncherSegment(id: "平衡", title: "平衡", systemImage: "leaf.fill"),
        LauncherSegment(id: "画质", title: "画质", systemImage: "sparkles")
    ]

    private let loaderOptions: [LauncherSegment<String>] = [
        LauncherSegment(id: "fabric", title: "Fabric 0.16.9", systemImage: "square.stack.3d.up.fill"),
        LauncherSegment(id: "forge", title: "Forge 47.2.20", systemImage: "hammer.fill"),
        LauncherSegment(id: "neoforge", title: "NeoForge 21.0.167", systemImage: "flame.fill"),
        LauncherSegment(id: "quilt", title: "Quilt 0.26.0", systemImage: "square.stack.fill")
    ]

    public init() {}

    public var body: some View {
        LauncherPageScaffold(
            title: "选择",
            subtitle: "Toggle · Checkbox · RadioCard · Slider · Segmented · Dropdown · Stepper。"
        ) {
            toggleSection
            checkboxSection
            javaSection
            sliderSection
            compositeSection
        }
    }

    // MARK: - 开关

    /// 三个开关，均带影响说明。
    private var toggleSection: some View {
        LauncherSection("开关", subtitle: "带副标题的开关解释实际影响；开启项会立刻作用于下一次启动。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                    LauncherToggle(
                        "启动前检查模组更新",
                        isOn: $autoUpdateMods,
                        subtitle: "检查 128 个模组是否有新版本，不会自动下载。"
                    )
                    LauncherToggle(
                        "智能内存分配",
                        isOn: $smartMemory,
                        subtitle: "按模组数量在 2048 – 8192 MB 之间调整 Java 21 堆内存。"
                    )
                    LauncherToggle(
                        "启动后最小化启动器",
                        isOn: $minimizeAfterLaunch,
                        subtitle: "进入游戏后把启动器收进 Dock，减少窗口遮挡。"
                    )
                }
            }
        }
    }

    // MARK: - 复选

    /// 三个复选框：启动前自动备份的内容，右上角实时显示已选数量。
    private var checkboxSection: some View {
        LauncherSection("复选", subtitle: "启动前自动备份的内容；未勾选的项不会写入备份目录。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                VStack(alignment: .leading, spacing: LauncherSpace.md) {
                    HStack(spacing: LauncherSpace.lg) {
                        LauncherCheckbox("世界存档", isOn: $backupSaves)
                            .frame(maxWidth: 140, alignment: .leading)
                        LauncherCheckbox("模组配置", isOn: $backupMods)
                            .frame(maxWidth: 140, alignment: .leading)
                        LauncherCheckbox("截图", isOn: $backupScreenshots)
                            .frame(maxWidth: 120, alignment: .leading)
                        Spacer(minLength: LauncherSpace.md)
                        LauncherBadge(
                            backupCount == 0 ? "未启用备份" : "已选 \(backupCount) 项",
                            tone: backupCount == 0 ? .neutral : .success,
                            systemImage: "checkmark.circle"
                        )
                    }
                    Text(
                        backupCount == 0
                            ? "建议至少备份世界存档，避免模组崩溃丢档。"
                            : "启动 1.21.4 前将自动备份到 .minecraft/backups/1.21.4。"
                    )
                    .textStyle(.micro, tone: .tertiary)
                }
            }
        }
    }

    // MARK: - Java 运行时

    /// 三选一单选卡：Java 21 / 17 / 8，底部显示当前绑定路径。
    private var javaSection: some View {
        LauncherSection("Java 运行时", subtitle: "一个实例只绑定一个运行时；切换后会在下次启动时生效。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                    LauncherDemoGrid(minWidth: 250) {
                        LauncherRadioCard(
                            "Java 21",
                            subtitle: "Temurin 21.0.5 · 1.20.5+",
                            systemImage: "cpu",
                            isSelected: javaRuntime == "java21"
                        ) {
                            javaRuntime = "java21"
                        }
                        LauncherRadioCard(
                            "Java 17",
                            subtitle: "Temurin 17.0.13 · 1.17–1.20.4",
                            systemImage: "cpu",
                            isSelected: javaRuntime == "java17"
                        ) {
                            javaRuntime = "java17"
                        }
                        LauncherRadioCard(
                            "Java 8",
                            subtitle: "Zulu 8.82 · 1.12.2 及更早",
                            systemImage: "cpu",
                            isSelected: javaRuntime == "java8"
                        ) {
                            javaRuntime = "java8"
                        }
                    }

                    HStack(spacing: LauncherSpace.sm) {
                        LauncherStatusDot(tone: .success)
                        Text("运行时已就绪 · 1.21.4 + Fabric 将使用 \(runtimeName)")
                            .textStyle(.micro, tone: .tertiary)
                        Spacer(minLength: LauncherSpace.md)
                        LauncherMonoText(runtimePath, tone: .tertiary)
                    }
                }
            }
        }
    }

    // MARK: - 滑杆

    /// 两个滑杆：玻璃浓度（实时百分比）与视距（区块数）。
    private var sliderSection: some View {
        LauncherSection("滑杆", subtitle: "自绘轨道与拇指；右侧数值用等宽字体，拖动时数字不抖。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                VStack(alignment: .leading, spacing: LauncherSpace.xl) {
                    LauncherSlider(
                        value: $glassIntensity,
                        range: 0.4...1.6,
                        label: "玻璃浓度",
                        valueText: "\(Int(glassIntensity * 100))%"
                    )
                    LauncherSlider(
                        value: $renderDistance,
                        range: 2...32,
                        label: "视距",
                        valueText: "\(Int(renderDistance)) 区块"
                    )
                }
            }
        }
    }

    // MARK: - 分段 / 下拉 / 步进

    /// 小集合用分段控件，长列表用下拉菜单，精确数值用步进器。
    private var compositeSection: some View {
        LauncherSection("分段 · 下拉 · 步进", subtitle: "小集合用分段控件，长列表用下拉菜单，精确数值用步进器。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                    LauncherDemoRow("性能配置") {
                        LauncherSegmentedControl(options: profileOptions, selection: $performanceProfile)
                            .frame(maxWidth: 360, alignment: .leading)
                    }

                    LauncherDemoRow("模组加载器") {
                        HStack(spacing: LauncherSpace.sm) {
                            LauncherDropdown(options: loaderOptions, selection: $loaderID, placeholder: "选择模组加载器")
                                .frame(maxWidth: 280, alignment: .leading)
                            LauncherBadge(
                                loaderID == "fabric" ? "推荐" : "已安装",
                                tone: loaderID == "fabric" ? .accent : .neutral
                            )
                        }
                    }

                    LauncherDemoRow("最大帧率") {
                        HStack(spacing: LauncherSpace.md) {
                            LauncherStepper(value: $maxFPS, range: 30...240, label: "上限", unit: "FPS")
                                .frame(maxWidth: 260, alignment: .leading)
                            Spacer(minLength: LauncherSpace.md)
                            Text("与显示器刷新率对齐可减少画面撕裂。")
                                .textStyle(.micro, tone: .tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 辅助

    /// 复选框已选数量。
    private var backupCount: Int {
        [backupSaves, backupMods, backupScreenshots].filter { $0 }.count
    }

    /// 当前选中的 Java 运行时名称。
    private var runtimeName: String {
        switch javaRuntime {
        case "java17": return "Java 17"
        case "java8": return "Java 8"
        default: return "Java 21"
        }
    }

    /// 当前选中的 Java 运行时安装路径。
    private var runtimePath: String {
        switch javaRuntime {
        case "java17": return "/Library/Java/Temurin-17.jdk"
        case "java8": return "/Library/Java/Zulu-8.jdk"
        default: return "/Library/Java/Temurin-21.jdk"
        }
    }
}
