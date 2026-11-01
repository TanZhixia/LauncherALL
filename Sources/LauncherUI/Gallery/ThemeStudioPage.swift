import SwiftUI

/// 主题工作台：主题切换、全局外观参数、跨主题一致性对照与令牌总览。
public struct ThemeStudioPage: View {
    @Environment(LauncherThemeManager.self) private var themeManager
    @Environment(\.launcherTheme) private var theme

    public init() {}

    public var body: some View {
        LauncherPageScaffold(
            title: "主题工作台",
            subtitle: "一套语义令牌驱动一深一浅两套主题：换主题只换色，不换结构、不换间距，控件始终保持同一套层级与对比度"
        ) {
            LauncherSection("主题预设", subtitle: "点击切换 · 全局语义色、面板层级与边框同步切换") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 420), spacing: LauncherSpace.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: LauncherSpace.md
                ) {
                    ForEach(themeManager.presets) { preset in
                        ThemeCard(preset: preset, isSelected: preset.id == themeManager.themeID) {
                            withAnimation(LauncherMotion.spring) {
                                themeManager.select(preset.id)
                            }
                        }
                    }
                }
            }

            LauncherSection("跨主题一致性", subtitle: "完全相同的组件代码，分别在深色 / 浅色主题下渲染——这是本模板的核心验收项") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 420), spacing: LauncherSpace.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: LauncherSpace.md
                ) {
                    ForEach(themeManager.presets) { preset in
                        CrossThemeCard(preset: preset)
                    }
                }
            }

            LauncherSection("全局外观参数", subtitle: "两个乘数作用于所有组件，验证令牌系统是否真正贯通") {
                GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.lg) {
                    VStack(spacing: LauncherSpace.md) {
                        LauncherSlider(
                            value: Binding(
                                get: { themeManager.borderStrength },
                                set: { themeManager.borderStrength = $0 }
                            ),
                            range: 0.4...1.6,
                            label: "边框强度",
                            valueText: String(format: "%.2f×", themeManager.borderStrength)
                        )
                        .frame(maxWidth: 560, alignment: .leading)
                        LauncherSlider(
                            value: Binding(
                                get: { themeManager.cornerScale },
                                set: { themeManager.cornerScale = $0 }
                            ),
                            range: 0.6...1.4,
                            label: "圆角缩放",
                            valueText: String(format: "%.2f×", themeManager.cornerScale)
                        )
                        .frame(maxWidth: 560, alignment: .leading)
                        HStack(spacing: LauncherSpace.sm) {
                            Text("当前主题：\(theme.name) · \(theme.tagline)")
                                .textStyle(.micro, tone: .tertiary)
                            Spacer(minLength: LauncherSpace.sm)
                            LauncherButton("恢复默认", variant: .secondary, size: .small) {
                                withAnimation(LauncherMotion.spring) {
                                    themeManager.borderStrength = 1.0
                                    themeManager.cornerScale = 1.0
                                }
                            }
                        }
                    }
                }
            }

            LauncherSection("设计令牌", subtitle: "中性色阶 / 圆角 / 间距 / 字阶——组件只能消费这些令牌") {
                GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.lg) {
                    VStack(alignment: .leading, spacing: LauncherSpace.xl) {
                        colorTokenGrid
                        radiusScale
                        spacingScale
                        typeScale
                    }
                }
            }
        }
    }

    // MARK: - 令牌总览

    private var colorTokenGrid: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
            LauncherLabel("语义色")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: LauncherSpace.sm, alignment: .leading)],
                alignment: .leading,
                spacing: LauncherSpace.sm
            ) {
                ForEach(colorTokenList, id: \.0) { name, color in
                    HStack(spacing: LauncherSpace.sm) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(color)
                            .frame(width: 22, height: 22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(theme.colors.stroke, lineWidth: 1)
                            )
                        LauncherMonoText(name, tone: .secondary, size: 10)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var colorTokenList: [(String, Color)] {
        let c = theme.colors
        return [
            ("accent", c.accent),
            ("accentAlt", c.accentAlt),
            ("onAccent", c.onAccent),
            ("accentSoft", c.accentSoft),
            ("surface", c.surface),
            ("surfaceElevated", c.surfaceElevated),
            ("surfaceSubtle", c.surfaceSubtle),
            ("surfaceHover", c.surfaceHover),
            ("stroke", c.stroke),
            ("strokeStrong", c.strokeStrong),
            ("textPrimary", c.textPrimary),
            ("textSecondary", c.textSecondary),
            ("textTertiary", c.textTertiary),
            ("success", c.success),
            ("warning", c.warning),
            ("danger", c.danger),
            ("focusRing", c.focusRing),
            ("canvas", c.canvas)
        ]
    }

    private var radiusScale: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
            LauncherLabel("圆角刻度")
            HStack(alignment: .bottom, spacing: LauncherSpace.md) {
                ForEach(radiusSamples, id: \.0) { name, value in
                    VStack(spacing: LauncherSpace.xs) {
                        RoundedRectangle(cornerRadius: min(value, 14), style: .continuous)
                            .fill(theme.colors.surfaceHover)
                            .overlay(
                                RoundedRectangle(cornerRadius: min(value, 14), style: .continuous)
                                    .strokeBorder(theme.colors.strokeStrong, lineWidth: 1)
                            )
                            .frame(width: 46, height: 32)
                        LauncherMonoText(name, tone: .tertiary, size: 9)
                    }
                }
            }
        }
    }

    private var radiusSamples: [(String, CGFloat)] {
        [("sm 8", LauncherRadius.sm), ("md 12", LauncherRadius.md), ("lg 16", LauncherRadius.lg), ("xl 22", LauncherRadius.xl), ("pill", LauncherRadius.pill)]
    }

    private var spacingScale: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
            LauncherLabel("间距刻度")
            HStack(alignment: .center, spacing: LauncherSpace.md) {
                ForEach(spacingSamples, id: \.0) { name, value in
                    VStack(spacing: LauncherSpace.xxs) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.colors.accent.opacity(0.55))
                            .frame(width: max(value, 2), height: 10)
                        LauncherMonoText(name, tone: .tertiary, size: 9)
                    }
                }
            }
        }
    }

    private var spacingSamples: [(String, CGFloat)] {
        [("xs 4", LauncherSpace.xs), ("sm 8", LauncherSpace.sm), ("md 12", LauncherSpace.md), ("lg 16", LauncherSpace.lg), ("xl 24", LauncherSpace.xl), ("xxl 32", LauncherSpace.xxl)]
    }

    private var typeScale: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
            LauncherLabel("字阶")
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                Text("Display · 开始游戏").textStyle(.display)
                Text("Title · 1.21.4 Fabric").textStyle(.title)
                Text("Section Title · 已安装实例").textStyle(.sectionTitle)
                Text("Headline · 模组同步完成").textStyle(.headline)
                Text("Body · 正在校验游戏资源文件，共 1,284 个文件。").textStyle(.body, tone: .secondary)
                Text("Caption · 上次游玩于 2 小时前").textStyle(.caption, tone: .tertiary)
                LauncherMonoText("Mono · 4096 MB / Java 21.0.4 / mc.hypixel.net", tone: .secondary)
                LauncherLabel("Label · 分组标题")
            }
        }
    }
}

// MARK: - 主题卡片

private struct ThemeCard: View {
    let preset: LauncherTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                preview
                HStack(alignment: .center, spacing: LauncherSpace.sm) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preset.name)
                            .font(LauncherTextStyle.bodyStrong.font)
                            .foregroundStyle(preset.colors.textPrimary)
                        Text(preset.tagline)
                            .font(LauncherTextStyle.micro.font)
                            .foregroundStyle(preset.colors.textTertiary)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(preset.colors.accent)
                    }
                }
                .padding(.horizontal, LauncherSpace.md)
                .padding(.vertical, LauncherSpace.sm)
            }
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: LauncherRadius.lg,
                    bottomLeadingRadius: LauncherRadius.lg,
                    bottomTrailingRadius: LauncherRadius.lg,
                    topTrailingRadius: LauncherRadius.lg,
                    style: .continuous
                )
                .fill(preset.colors.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: LauncherRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.lg, style: .continuous)
                .strokeBorder(
                    isSelected ? preset.colors.accent : preset.colors.stroke,
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .launcherHoverEffect(scale: 1.01)
        .accessibilityLabel("主题 \(preset.name)")
    }

    private var preview: some View {
        ZStack {
            preset.colors.canvas

            HStack(spacing: LauncherSpace.sm) {
                miniSidebar
                VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                    HStack(spacing: LauncherSpace.xs) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(preset.colors.textPrimary.opacity(0.55))
                            .frame(width: 46, height: 4)
                        Spacer(minLength: 0)
                        Circle()
                            .fill(preset.colors.accent)
                            .frame(width: 4, height: 4)
                    }
                    miniCard
                    HStack(spacing: LauncherSpace.xs) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(preset.colors.accent)
                            .frame(width: 44, height: 12)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(preset.colors.surfaceHover)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(preset.colors.stroke, lineWidth: 1)
                            )
                            .frame(width: 26, height: 12)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, LauncherSpace.sm)
                .padding(.trailing, LauncherSpace.sm)
            }
        }
        .frame(height: 104)
        .clipped()
    }

    /// 迷你侧栏：亮色主题也能靠 1px 边框与选中条看出结构。
    private var miniSidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index == 0 ? preset.colors.accent : preset.colors.textTertiary.opacity(0.4))
                    .frame(width: index == 0 ? 14 : 10, height: 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, LauncherSpace.md)
        .padding(.leading, 6)
        .frame(width: 28)
        .frame(maxHeight: .infinity)
        .background(preset.colors.surfaceElevated)
        .overlay(alignment: .trailing) {
            Rectangle().fill(preset.colors.stroke).frame(width: 1)
        }
    }

    /// 迷你卡片：底色 + 1px 边框 + 一行标题与状态点。
    private var miniCard: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(preset.colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(preset.colors.stroke, lineWidth: 1)
            )
            .frame(height: 34)
            .overlay(alignment: .leading) {
                HStack(spacing: LauncherSpace.xs) {
                    Circle()
                        .fill(preset.colors.accent)
                        .frame(width: 5, height: 5)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(preset.colors.textSecondary.opacity(0.55))
                        .frame(width: 38, height: 3)
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(preset.colors.textTertiary.opacity(0.35))
                        .frame(width: 18, height: 3)
                }
                .padding(.horizontal, 7)
            }
    }
}

// MARK: - 跨主题一致性对照

private struct CrossThemeCard: View {
    let preset: LauncherTheme
    @State private var onlyInstalled = true

    var body: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
            HStack(spacing: LauncherSpace.xs) {
                Circle()
                    .fill(preset.swatch.last ?? preset.colors.accent)
                    .frame(width: 8, height: 8)
                Text(preset.name)
                    .textStyle(.micro, tone: .secondary)
                Spacer(minLength: 0)
                LauncherMonoText(preset.id, tone: .tertiary, size: 9)
            }

            GlassPanel(level: .regular, cornerRadius: LauncherRadius.md, padding: LauncherSpace.sm) {
                VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                    HStack(spacing: LauncherSpace.xs) {
                        LauncherBadge("1.21.4", tone: .accent)
                        LauncherBadge("Fabric", tone: .neutral)
                        LauncherStatusDot(tone: .success)
                        Spacer(minLength: 0)
                    }
                    Text("生存 · 群岛")
                        .textStyle(.bodyStrong)
                    Text("上次游玩 2 小时前")
                        .textStyle(.micro, tone: .tertiary)
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherButton("开始游戏", systemImage: "play.fill", variant: .primary, size: .small) {}
                        LauncherButton("设置", variant: .secondary, size: .small) {}
                    }
                    LauncherToggle("仅显示已安装", isOn: $onlyInstalled)
                }
            }
        }
        .padding(LauncherSpace.md)
        .background(preset.colors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: LauncherRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.lg, style: .continuous)
                .strokeBorder(preset.colors.stroke, lineWidth: 1)
        }
        .environment(\.launcherTheme, preset)
        .environment(\.colorScheme, preset.scheme)
    }
}
