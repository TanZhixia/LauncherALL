import SwiftUI

/// 导航组件画廊页：侧边栏、标签栏、对话框，以及一个「设置页」分栏缩略。
public struct NavigationPage: View {
    @State private var sidebarSelection = "instances"
    @State private var previewSelection = "general"
    @State private var tabSelection = "instances"
    @State private var autoCheckUpdates = true
    @State private var keepInBackground = false

    public init() {}

    public var body: some View {
        LauncherPageScaffold(
            title: "导航与结构",
            subtitle: "侧边栏、标签栏、对话框，以及侧边栏 + 内容区组合成的设置页缩略"
        ) {
            sidebarSection
            tabBarSection
            dialogSection
            settingsPreviewSection
        }
    }

    // MARK: - 侧边栏

    private var sidebarSection: some View {
        LauncherSection(
            "侧边栏",
            subtitle: "完整导航结构：分组标题 / 选中态 / 角标 / 页脚，绑定页面内 @State"
        ) {
            HStack(alignment: .top, spacing: LauncherSpace.md) {
                LauncherCard(level: .regular, padding: LauncherSpace.sm) {
                    LauncherSidebar(
                        items: sidebarItems,
                        selection: $sidebarSelection,
                        header: AnyView(LauncherLabel("启动器")),
                        footer: AnyView(
                            LauncherButton(
                                "管理账户",
                                systemImage: "person.crop.circle",
                                variant: .ghost,
                                size: .small,
                                isFullWidth: true
                            ) {}
                        )
                    )
                }
                LauncherCard(level: .subtle) {
                    VStack(alignment: .leading, spacing: LauncherSpace.md) {
                        LauncherSectionHeader(
                            title: "当前选中项",
                            subtitle: "点击左侧导航即可切换"
                        )
                        LauncherKeyValueRow(key: "导航 id", value: sidebarSelection)
                        LauncherKeyValueRow(key: "会话状态", value: "已登录 · 正版")
                        LauncherDivider()
                        Text("侧边栏的选中态会同步反馈到这里；真实产品中右侧会切换成对应页面内容。")
                            .textStyle(.micro, tone: .tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 标签栏

    private var tabBarSection: some View {
        LauncherSection(
            "标签栏",
            subtitle: "同层级的页面切换，一次只选中一项"
        ) {
            LauncherCard(level: .regular) {
                VStack(alignment: .leading, spacing: LauncherSpace.md) {
                    LauncherTabBar(
                        tabs: [
                            LauncherTabBar.Tab(
                                id: "instances",
                                title: "实例",
                                systemImage: "square.stack.3d.up.fill"
                            ),
                            LauncherTabBar.Tab(
                                id: "versions",
                                title: "版本",
                                systemImage: "cube.fill"
                            ),
                            LauncherTabBar.Tab(
                                id: "mods",
                                title: "模组",
                                systemImage: "puzzlepiece.extension.fill"
                            ),
                            LauncherTabBar.Tab(
                                id: "servers",
                                title: "服务器",
                                systemImage: "server.rack"
                            )
                        ],
                        selection: $tabSelection
                    )
                    LauncherDivider()
                    Text("当前标签：\(tabSelection)")
                        .textStyle(.caption, tone: .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 对话框

    private var dialogSection: some View {
        LauncherSection(
            "对话框",
            subtitle: "常规确认与危险操作两种语义，均为浮层面板卡"
        ) {
            HStack(alignment: .top, spacing: LauncherSpace.md) {
                LauncherDialog(
                    title: "切换游戏账户？",
                    message: "切换账户后会重新校验登录状态，当前实例的存档不受影响。",
                    primaryTitle: "切换账户",
                    secondaryTitle: "取消",
                    onPrimary: {},
                    onSecondary: {}
                )
                LauncherDialog(
                    title: "删除实例「1.8.9 · PvP 整合」？",
                    message: "实例文件与 12 个模组将被移入废纸篓，此操作不可撤销。",
                    primaryTitle: "删除",
                    secondaryTitle: "保留",
                    tone: .danger,
                    onPrimary: {},
                    onSecondary: {}
                )
            }
        }
    }

    // MARK: - 设置页分栏缩略

    private var settingsPreviewSection: some View {
        LauncherSection(
            "设置页分栏缩略",
            subtitle: "侧边栏 + 内容区组合成真实设置页，控件使用页面内 @State"
        ) {
            LauncherCard(level: .regular, padding: LauncherSpace.sm) {
                HStack(alignment: .top, spacing: LauncherSpace.md) {
                    LauncherSidebar(
                        items: previewItems,
                        selection: $previewSelection,
                        header: AnyView(LauncherLabel("设置"))
                    )
                    VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                        LauncherSectionHeader(
                            title: "常规",
                            subtitle: "启动器行为与更新策略"
                        )
                        LauncherToggle(
                            "启动时自动检查更新",
                            isOn: $autoCheckUpdates,
                            subtitle: "检查启动器与模组版本，有新版本时提示"
                        )
                        LauncherToggle(
                            "关闭窗口后保留后台运行",
                            isOn: $keepInBackground
                        )
                        LauncherDivider()
                        LauncherKeyValueRow(key: "界面语言", value: "简体中文")
                        LauncherKeyValueRow(
                            key: "数据目录",
                            value: "~/Library/Application Support/MCLauncher"
                        )
                        HStack(spacing: LauncherSpace.md) {
                            LauncherButton(
                                "打开数据目录",
                                systemImage: "folder",
                                variant: .secondary
                            ) {}
                            Spacer(minLength: LauncherSpace.sm)
                            LauncherButton("保存设置") {}
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 示例数据

    private var sidebarItems: [LauncherNavItem] {
        [
            LauncherNavItem(
                id: "instances",
                title: "实例",
                systemImage: "square.stack.3d.up.fill",
                badge: "4"
            ),
            LauncherNavItem(
                id: "versions",
                title: "版本",
                systemImage: "cube.fill"
            ),
            LauncherNavItem(
                id: "mods",
                title: "模组",
                systemImage: "puzzlepiece.extension.fill",
                badge: "12"
            ),
            LauncherNavItem(
                id: "servers",
                title: "服务器",
                systemImage: "server.rack"
            ),
            LauncherNavItem(
                id: "settings",
                title: "设置",
                systemImage: "gearshape.fill"
            )
        ]
    }

    private var previewItems: [LauncherNavItem] {
        [
            LauncherNavItem(
                id: "general",
                title: "常规",
                systemImage: "gearshape.fill"
            ),
            LauncherNavItem(
                id: "java",
                title: "Java 运行时",
                systemImage: "cup.and.saucer.fill"
            ),
            LauncherNavItem(
                id: "downloads",
                title: "下载",
                systemImage: "arrow.down.circle.fill",
                badge: "2"
            ),
            LauncherNavItem(
                id: "appearance",
                title: "外观",
                systemImage: "paintpalette.fill"
            ),
            LauncherNavItem(
                id: "account",
                title: "账户",
                systemImage: "person.crop.circle.fill"
            )
        ]
    }
}
