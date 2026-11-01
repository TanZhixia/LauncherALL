import SwiftUI

/// 容器与信息展示画廊页：三层玻璃、列表行、区块标题、空态、头像、键值对与统计块。
public struct SurfacesPage: View {
    public init() {}

    public var body: some View {
        LauncherPageScaffold(
            title: "容器与列表",
            subtitle: "玻璃层级、列表行、空态与基础信息组件，深浅主题下保持同一套结构与节奏"
        ) {
            glassSection
            listRowSection
            headerEmptySection
            avatarSection
            keyValueSection
            statSection
        }
    }

    // MARK: - 玻璃层级

    private var glassSection: some View {
        LauncherSection(
            "玻璃层级",
            subtitle: "subtle 内嵌 / regular 常规 / strong 浮层，越强越实、阴影越重"
        ) {
            HStack(alignment: .top, spacing: LauncherSpace.md) {
                glassSample(
                    level: .subtle,
                    name: "SUBTLE",
                    detail: "内嵌槽位，用于输入框、进度轨道与代码块"
                )
                glassSample(
                    level: .regular,
                    name: "REGULAR",
                    detail: "常规卡片，承载实例、账户与新闻等主体内容"
                )
                glassSample(
                    level: .strong,
                    name: "STRONG",
                    detail: "最实的一层，用于弹窗、Toast 与悬浮操作条"
                )
            }
        }
    }

    private func glassSample(level: GlassLevel, name: String, detail: String) -> some View {
        LauncherCard(level: level) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                LauncherLabel(name)
                Text(detail)
                    .textStyle(.micro, tone: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LauncherMonoText("level: \(level.rawValue)", tone: .tertiary)
                Text("内嵌示例内容")
                    .textStyle(.caption, tone: .tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LauncherSpace.sm)
                    .glassBackground(level: .subtle, cornerRadius: LauncherRadius.sm)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 列表行

    private var listRowSection: some View {
        LauncherSection(
            "列表行",
            subtitle: "普通 / 选中 / 带徽标 / 带操作区，行高 44pt，hover 提亮"
        ) {
            LauncherCard(level: .regular, padding: LauncherSpace.sm) {
                VStack(spacing: LauncherSpace.xxs) {
                    LauncherListRow(
                        title: "1.21.4 · Fabric",
                        subtitle: "214 个模组 · 上次游玩 今天 14:32",
                        systemImage: "cube.fill",
                        badge: "Fabric"
                    )
                    LauncherListRow(
                        title: "1.20.1 · Forge",
                        subtitle: "上次游玩 3 天前 · Forge 47.2.0",
                        systemImage: "cube.fill",
                        badge: "Forge",
                        isSelected: true
                    )
                    LauncherListRow(
                        title: "2B2T 生存服",
                        subtitle: "mc.2b2t.org · 无政府服务器",
                        systemImage: "server.rack",
                        badge: "在线",
                        accessory: AnyView(LauncherStatusDot(tone: .success, isPulsing: true))
                    )
                    LauncherListRow(
                        title: "1.8.9 · PvP",
                        subtitle: "上次游玩 2 周前 · 12 个模组",
                        systemImage: "bolt.fill",
                        accessory: AnyView(LauncherButton("启动", variant: .secondary, size: .small) {}),
                        action: {}
                    )
                }
            }
        }
    }

    // MARK: - 区块标题与空态

    private var headerEmptySection: some View {
        LauncherSection(
            "区块标题与空态",
            subtitle: "SectionHeader 用于卡片内部；EmptyState 用于零数据场景"
        ) {
            LauncherCard(level: .regular) {
                VStack(alignment: .leading, spacing: LauncherSpace.md) {
                    LauncherSectionHeader(
                        title: "已安装整合包",
                        subtitle: "3 个整合包 · 共 12.4 GB",
                        accessory: AnyView(
                            LauncherButton(
                                "导入整合包",
                                systemImage: "square.and.arrow.down",
                                variant: .ghost,
                                size: .small
                            ) {}
                        )
                    )
                    LauncherDivider()
                    LauncherEmptyState(
                        systemImage: "shippingbox",
                        title: "还没有安装整合包",
                        message: "把 .zip 整合包拖进窗口，或从模组站一键导入。",
                        actionTitle: "浏览整合包",
                        onAction: {}
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - 头像

    private var avatarSection: some View {
        LauncherSection(
            "头像",
            subtitle: "在线 / 离线 / 自定义图标，尺寸走 LauncherControl 刻度"
        ) {
            LauncherCard(level: .regular) {
                HStack(alignment: .top, spacing: LauncherSpace.xl) {
                    avatarSample(name: "Steve_2026", caption: "在线 · 正版", isOnline: true)
                    avatarSample(name: "Alex", caption: "离线 · 本地", isOnline: false)
                    avatarSample(
                        name: "Herobrine",
                        caption: "自定义图标",
                        isOnline: false,
                        systemImage: "person.fill.questionmark"
                    )
                    Spacer(minLength: LauncherSpace.sm)
                }
            }
        }
    }

    private func avatarSample(
        name: String,
        caption: String,
        isOnline: Bool,
        systemImage: String? = nil
    ) -> some View {
        VStack(spacing: LauncherSpace.sm) {
            LauncherAvatar(
                name: name,
                systemImage: systemImage,
                size: LauncherControl.large,
                isOnline: isOnline
            )
            Text(name)
                .textStyle(.caption, tone: .primary)
            Text(caption)
                .textStyle(.micro, tone: .tertiary)
        }
    }

    // MARK: - 键值对

    private var keyValueSection: some View {
        LauncherSection(
            "键值对",
            subtitle: "实例详情、账户与运行时信息等结构化文本"
        ) {
            LauncherCard(level: .regular) {
                VStack(alignment: .leading, spacing: LauncherSpace.md) {
                    LauncherCardHeader(
                        title: "实例详情",
                        subtitle: "1.21.4 · Fabric 0.16.9",
                        systemImage: "cube.fill",
                        accessory: AnyView(LauncherBadge("已就绪", tone: .success))
                    )
                    LauncherDivider()
                    LauncherKeyValueRow(key: "游戏版本", value: "1.21.4")
                    LauncherKeyValueRow(key: "加载器", value: "Fabric 0.16.9")
                    LauncherKeyValueRow(key: "Java 运行时", value: "21.0.4 · Microsoft OpenJDK")
                    LauncherKeyValueRow(key: "内存分配", value: "4.0 GB / 16.0 GB")
                    LauncherKeyValueRow(key: "上次游玩", value: "今天 14:32 · 6 小时 12 分")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 统计块与分割线

    private var statSection: some View {
        LauncherSection(
            "统计块与分割线",
            subtitle: "首页数据概览；Divider 用于卡片内分组"
        ) {
            VStack(spacing: LauncherSpace.md) {
                HStack(spacing: LauncherSpace.md) {
                    statTile(value: "4", label: "已安装实例", systemImage: "square.stack.3d.up.fill")
                    statTile(value: "214", label: "模组总数", systemImage: "puzzlepiece.extension.fill")
                    statTile(value: "26.4 GB", label: "磁盘占用", systemImage: "internaldrive.fill")
                }
                LauncherCard(level: .subtle) {
                    VStack(alignment: .leading, spacing: LauncherSpace.md) {
                        Text("下载队列")
                            .textStyle(.bodyStrong)
                        LauncherDivider()
                        Text("共 2 个任务进行中，预计剩余 3 分 20 秒。")
                            .textStyle(.micro, tone: .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func statTile(value: String, label: String, systemImage: String) -> some View {
        LauncherStatTile(value: value, label: label, systemImage: systemImage)
            .frame(maxWidth: .infinity)
    }
}
