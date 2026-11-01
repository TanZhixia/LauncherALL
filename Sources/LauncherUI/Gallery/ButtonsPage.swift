import SwiftUI

/// 按钮画廊页：主操作 CTA、变体 × 尺寸矩阵、加载/禁用/全宽状态、图标按钮与 Chip / Badge / 状态点。
public struct ButtonsPage: View {
    @State private var selectedChannel = "正式版 1.21.4"
    @State private var selectedLoader = "Fabric 0.16.9"
    @State private var isLaunching = false
    @State private var isFavorite = false

    public init() {}

    public var body: some View {
        LauncherPageScaffold(
            title: "按钮",
            subtitle: "Button · Chip · Badge：启动、切换与状态反馈的基本动作单元。"
        ) {
            mainCTA
            variantMatrix
            stateSection
            fullWidthSection
            chipSection
            badgeSection
        }
    }

    // MARK: - 主操作

    /// 全页唯一的主 CTA：一个 large primary“开始游戏”，其余动作降级为 secondary / ghost。
    private var mainCTA: some View {
        LauncherSection("主操作", subtitle: "一屏只保留一个 large primary 按钮，其余动作降级为次要或幽灵按钮。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.xl, padding: LauncherSpace.xl) {
                VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                    HStack(alignment: .center, spacing: LauncherSpace.lg) {
                        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                            LauncherLabel("当前实例")
                            Text("1.21.4 · Fabric 0.16.9").textStyle(.sectionTitle)
                            HStack(spacing: LauncherSpace.sm) {
                                LauncherMonoText("mc.hypixel.net", tone: .tertiary)
                                LauncherBadge(
                                    isLaunching ? "启动中" : "已就绪",
                                    tone: isLaunching ? .warning : .success,
                                    systemImage: isLaunching ? "hourglass" : "checkmark.circle.fill"
                                )
                            }
                        }

                        Spacer(minLength: LauncherSpace.lg)

                        HStack(spacing: LauncherSpace.md) {
                            LauncherButton("选择版本", systemImage: "square.stack.3d.up", variant: .secondary, size: .large, shortcut: "⌘D") {
                                isLaunching = false
                            }
                            LauncherButton("开始游戏", systemImage: "play.fill", variant: .primary, size: .large, isLoading: isLaunching, shortcut: "⌘↩") {
                                isLaunching = true
                            }
                        }
                    }

                    HStack(spacing: LauncherSpace.sm) {
                        LauncherStatusDot(tone: isLaunching ? .warning : .success, isPulsing: isLaunching)
                        Text(isLaunching ? "正在校验 Java 21 运行时与 128 个模组…" : "上次启动 2 分钟前 · 已加载 128 个模组")
                            .textStyle(.micro, tone: .tertiary)
                        Spacer(minLength: LauncherSpace.md)
                        if isLaunching {
                            LauncherButton("取消启动", systemImage: "stop.fill", variant: .ghost, size: .small) {
                                isLaunching = false
                            }
                        } else {
                            LauncherButton(
                                isFavorite ? "已收藏" : "收藏实例",
                                systemImage: isFavorite ? "star.fill" : "star",
                                variant: .ghost,
                                size: .small
                            ) {
                                isFavorite.toggle()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 变体 × 尺寸

    /// 4 种变体 × 3 种尺寸矩阵，每行共享中心基线。
    private var variantMatrix: some View {
        LauncherSection("变体 × 尺寸", subtitle: "primary / secondary / ghost / danger 四种变体，各提供 small · medium · large 三档高度。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                VStack(alignment: .leading, spacing: LauncherSpace.md) {
                    LauncherDemoRow("主要") {
                        HStack(spacing: LauncherSpace.md) {
                            LauncherButton("开始游戏", variant: .primary, size: .small) {}
                            LauncherButton("开始游戏", variant: .primary, size: .medium) {}
                            LauncherButton("开始游戏", variant: .primary, size: .large) {}
                        }
                    }
                    LauncherDemoRow("次要") {
                        HStack(spacing: LauncherSpace.md) {
                            LauncherButton("选择版本", variant: .secondary, size: .small) {}
                            LauncherButton("选择版本", variant: .secondary, size: .medium) {}
                            LauncherButton("选择版本", variant: .secondary, size: .large) {}
                        }
                    }
                    LauncherDemoRow("幽灵") {
                        HStack(spacing: LauncherSpace.md) {
                            LauncherButton("查看日志", variant: .ghost, size: .small) {}
                            LauncherButton("查看日志", variant: .ghost, size: .medium) {}
                            LauncherButton("查看日志", variant: .ghost, size: .large) {}
                        }
                    }
                    LauncherDemoRow("危险") {
                        HStack(spacing: LauncherSpace.md) {
                            LauncherButton("删除实例", variant: .danger, size: .small) {}
                            LauncherButton("删除实例", variant: .danger, size: .medium) {}
                            LauncherButton("删除实例", variant: .danger, size: .large) {}
                        }
                    }
                }
            }
        }
    }

    // MARK: - 状态与图标

    /// 加载 / 禁用 / 快捷键 / 图标按钮四种状态行，同尺寸控件保持同一基线。
    private var stateSection: some View {
        LauncherSection("状态与图标", subtitle: "加载中、禁用、快捷键提示与图标按钮；同一行控件保持同一中心基线。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                    LauncherDemoRow("加载中") {
                        HStack(spacing: LauncherSpace.md) {
                            LauncherButton("正在启动", variant: .primary, size: .medium, isLoading: true) {}
                            LauncherButton("同步 128 个模组", systemImage: "arrow.triangle.2.circlepath", variant: .secondary, size: .medium, isLoading: true) {}
                        }
                    }
                    LauncherDemoRow("禁用") {
                        HStack(spacing: LauncherSpace.md) {
                            LauncherButton("开始游戏", variant: .primary, size: .medium, isDisabled: true) {}
                            LauncherButton("选择版本", variant: .secondary, size: .medium, isDisabled: true) {}
                            LauncherButton("删除实例", systemImage: "trash", variant: .danger, size: .medium, isDisabled: true) {}
                        }
                    }
                    LauncherDemoRow("快捷键") {
                        HStack(spacing: LauncherSpace.md) {
                            LauncherButton("开始游戏", systemImage: "play.fill", variant: .primary, size: .medium, shortcut: "⌘↩") {}
                            LauncherButton("打开实例目录", systemImage: "folder", variant: .secondary, size: .medium, shortcut: "⌘O") {}
                        }
                    }
                    LauncherDemoRow("图标按钮") {
                        HStack(spacing: LauncherSpace.md) {
                            LauncherIconButton(systemImage: "ellipsis", variant: .ghost, size: .small, accessibilityLabel: "更多操作") {}
                            LauncherIconButton(systemImage: "arrow.clockwise", variant: .secondary, size: .medium, accessibilityLabel: "刷新版本列表") {}
                            LauncherIconButton(systemImage: "play.fill", variant: .primary, size: .large, accessibilityLabel: "启动游戏") {}
                            LauncherIconButton(
                                systemImage: isFavorite ? "star.fill" : "star",
                                variant: isFavorite ? .primary : .ghost,
                                size: .medium,
                                accessibilityLabel: isFavorite ? "取消收藏" : "收藏实例"
                            ) {
                                isFavorite.toggle()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 全宽

    /// 全宽按钮：表单主操作与成对确认操作。
    private var fullWidthSection: some View {
        LauncherSection("全宽按钮", subtitle: "在启动横幅与表单里撑满一行，保证点击目标足够大。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                VStack(spacing: LauncherSpace.md) {
                    LauncherButton("一键安装 128 个模组", systemImage: "square.and.arrow.down.fill", variant: .primary, size: .medium, isFullWidth: true, shortcut: "⌘I") {}
                    HStack(spacing: LauncherSpace.md) {
                        LauncherButton("取消", variant: .secondary, size: .medium, isFullWidth: true) {}
                        LauncherButton("保存并启动", systemImage: "play.fill", variant: .primary, size: .medium, isFullWidth: true, shortcut: "⌘↩") {}
                    }
                }
            }
        }
    }

    // MARK: - Chip

    /// Chip 两组各三枚：版本频道与模组加载器，均含选中态。
    private var chipSection: some View {
        LauncherSection("Chip 选择", subtitle: "轻量单选：切换版本频道与模组加载器，选中态用 accentSoft 底 + accent 描边。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                    LauncherDemoRow("版本频道") {
                        HStack(spacing: LauncherSpace.sm) {
                            LauncherChip("正式版 1.21.4", isSelected: selectedChannel == "正式版 1.21.4") {
                                selectedChannel = "正式版 1.21.4"
                            }
                            LauncherChip("快照 25w01a", isSelected: selectedChannel == "快照 25w01a") {
                                selectedChannel = "快照 25w01a"
                            }
                            LauncherChip("预览 1.21.5-pre2", isSelected: selectedChannel == "预览 1.21.5-pre2") {
                                selectedChannel = "预览 1.21.5-pre2"
                            }
                        }
                    }
                    LauncherDemoRow("模组加载器") {
                        HStack(spacing: LauncherSpace.sm) {
                            LauncherChip("Fabric 0.16.9", isSelected: selectedLoader == "Fabric 0.16.9") {
                                selectedLoader = "Fabric 0.16.9"
                            }
                            LauncherChip("Forge 47.2.20", isSelected: selectedLoader == "Forge 47.2.20") {
                                selectedLoader = "Forge 47.2.20"
                            }
                            LauncherChip("NeoForge 21.0.167", isSelected: selectedLoader == "NeoForge 21.0.167") {
                                selectedLoader = "NeoForge 21.0.167"
                            }
                        }
                    }
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherLabel("当前组合")
                        LauncherMonoText("\(selectedChannel) · \(selectedLoader)", tone: .accent)
                    }
                }
            }
        }
    }

    // MARK: - Badge / 状态点

    /// Badge 六种语义色 + StatusDot 三种状态。
    private var badgeSection: some View {
        LauncherSection("Badge 与状态点", subtitle: "六种语义色覆盖缓存、推荐、安装与失败；状态点标识服务器与后台任务。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                    LauncherDemoRow("Badge") {
                        HStack(spacing: LauncherSpace.sm) {
                            LauncherBadge("已缓存", tone: .neutral, systemImage: "internaldrive")
                            LauncherBadge("推荐", tone: .accent, systemImage: "sparkles")
                            LauncherBadge("已安装", tone: .success, systemImage: "checkmark.circle.fill")
                            LauncherBadge("可更新", tone: .warning, systemImage: "arrow.up.circle.fill")
                            LauncherBadge("启动失败", tone: .danger, systemImage: "xmark.octagon.fill")
                            LauncherBadge("Java 21", tone: .info, systemImage: "cup.and.saucer.fill")
                        }
                    }
                    LauncherDemoRow("服务器") {
                        HStack(spacing: LauncherSpace.xl) {
                            statusLine("mc.hypixel.net · 在线 42 ms", tone: .success, pulsing: true)
                            statusLine("mc.example.net · 延迟 380 ms", tone: .warning, pulsing: false)
                            statusLine("modpack.example.org · 维护中", tone: .danger, pulsing: false)
                        }
                    }
                }
            }
        }
    }

    /// 状态点 + 说明文字的一行示例。
    private func statusLine(_ text: String, tone: LauncherBadgeTone, pulsing: Bool) -> some View {
        HStack(spacing: LauncherSpace.sm) {
            LauncherStatusDot(tone: tone, isPulsing: pulsing)
            Text(text).textStyle(.micro, tone: .secondary)
        }
    }
}
