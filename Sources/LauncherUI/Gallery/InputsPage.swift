import SwiftUI

/// 输入控件画廊页：文本 / 搜索 / 密码 / 多行文本，以及一组可直接照抄的实例设置表单。
public struct InputsPage: View {
    @State private var accountName = "Steve"
    @State private var serverAddress = "mc.hypixel.net"
    @State private var instanceName = "生存服 · 1.21.4"
    @State private var invalidName = "steve!"
    @State private var lockedVersion = "1.21.4"
    @State private var versionQuery = "1.21.4"
    @State private var accountPassword = "hunter2"
    @State private var packDescription = "轻量生存整合包：Sodium + Lithium + Iris。\n包含 128 个模组，推荐 Java 21 与 4096 MB 内存。"
    @State private var gameDirectory = "/Users/steve/Library/Application Support/minecraft"
    @State private var memoryAllocation = 4096
    @State private var autoBackupSaves = true
    @State private var keepLauncherOpen = false

    public init() {}

    public var body: some View {
        LauncherPageScaffold(
            title: "输入",
            subtitle: "TextField · SearchField · SecureField · TextArea：统一的凹槽表面与聚焦焦点环。"
        ) {
            textFieldsSection
            searchAndPasswordSection
            textAreaSection
            instanceFormSection
        }
    }

    // MARK: - 文本输入

    /// 五种文本输入状态：普通 / 带图标 / 带 helper / 错误态 / 禁用。
    private var textFieldsSection: some View {
        LauncherSection("文本输入", subtitle: "普通、图标、helper、错误与禁用五种状态；helper 与 error 互斥显示。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                HStack(alignment: .top, spacing: LauncherSpace.xl) {
                    VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                        fieldBlock("普通") {
                            LauncherTextField("输入玩家名", text: $accountName)
                        }
                        fieldBlock("带图标") {
                            LauncherTextField("服务器地址", text: $serverAddress, systemImage: "network")
                        }
                        fieldBlock("禁用") {
                            LauncherTextField(
                                "版本已锁定",
                                text: $lockedVersion,
                                systemImage: "lock.fill",
                                helper: "1.21.4 由服务器强制指定",
                                isDisabled: true
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                        fieldBlock("带 helper") {
                            LauncherTextField(
                                "实例名称",
                                text: $instanceName,
                                systemImage: "square.stack.3d.up",
                                helper: "仅本地显示，不影响游戏内名称。"
                            )
                        }
                        fieldBlock("错误态") {
                            LauncherTextField(
                                "玩家名",
                                text: $invalidName,
                                systemImage: "person.fill",
                                error: "只能使用 3-16 位字母、数字或下划线。"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 搜索与密码

    /// 搜索框（已输入内容）+ 密码框，右侧各带一句结果 / 安全说明。
    private var searchAndPasswordSection: some View {
        LauncherSection("搜索与密码", subtitle: "搜索框自带清除按钮；密码框只做遮蔽，凭据落本机钥匙串。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                HStack(alignment: .top, spacing: LauncherSpace.xl) {
                    VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                        Text("搜索").textStyle(.micro, tone: .tertiary)
                        LauncherSearchField(text: $versionQuery, placeholder: "搜索版本、整合包或服务器")
                        Text(
                            versionQuery.isEmpty
                                ? "输入关键词开始搜索。"
                                : "正在检索 “\(versionQuery)” 的版本与整合包，共找到 3 条结果。"
                        )
                        .textStyle(.micro, tone: .tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                        Text("密码").textStyle(.micro, tone: .tertiary)
                        LauncherSecureField("账户密码", text: $accountPassword, systemImage: "lock.shield")
                        Text("凭据只保存在本机钥匙串，不会上传服务器。")
                            .textStyle(.micro, tone: .tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 多行文本

    /// 多行文本：整合包简介 + 实时字数统计。
    private var textAreaSection: some View {
        LauncherSection("多行文本", subtitle: "整合包简介用 TextEditor 自绘凹槽背景，最小高度 110。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.xl) {
                VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                    LauncherLabel("整合包简介")
                    LauncherTextArea("描述这个整合包适合谁玩…", text: $packDescription, minHeight: 110)
                    HStack(spacing: LauncherSpace.sm) {
                        Text("\(packDescription.count) 个字符").textStyle(.micro, tone: .tertiary)
                        Spacer(minLength: LauncherSpace.md)
                        LauncherBadge("自动保存", tone: .success, systemImage: "checkmark.circle")
                    }
                }
            }
        }
    }

    // MARK: - 实例设置表单

    /// 真实表单：版本目录 + 内存分配步进器 + 启动选项 + 底部主次按钮。
    private var instanceFormSection: some View {
        LauncherSection("实例设置表单", subtitle: "真实表单组合：版本目录、内存分配与启动选项，按钮统一靠右收尾。") {
            GlassPanel(level: .regular, cornerRadius: LauncherRadius.xl, padding: LauncherSpace.xl) {
                VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                    HStack(alignment: .center, spacing: LauncherSpace.sm) {
                        VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                            LauncherLabel("实例")
                            Text("1.21.4 · Fabric 0.16.9").textStyle(.sectionTitle)
                        }
                        Spacer(minLength: LauncherSpace.md)
                        LauncherBadge("128 个模组", tone: .accent, systemImage: "shippingbox.fill")
                        LauncherBadge("Java 21", tone: .info, systemImage: "cup.and.saucer.fill")
                    }

                    LauncherDemoRow("版本目录") {
                        HStack(spacing: LauncherSpace.sm) {
                            LauncherTextField(
                                "版本文件夹路径",
                                text: $gameDirectory,
                                systemImage: "folder",
                                helper: "启动时会在此目录读写 versions / mods / saves。"
                            )
                            .frame(maxWidth: .infinity)
                            LauncherIconButton(
                                systemImage: "folder.badge.plus",
                                variant: .secondary,
                                size: .medium,
                                accessibilityLabel: "选择版本文件夹"
                            ) {}
                        }
                    }

                    LauncherDemoRow("内存分配") {
                        HStack(spacing: LauncherSpace.md) {
                            LauncherStepper(value: $memoryAllocation, range: 1024...16384, label: "上限", unit: "MB")
                                .frame(maxWidth: 280, alignment: .leading)
                            Spacer(minLength: LauncherSpace.md)
                            Text(memoryHint)
                                .textStyle(.micro, tone: memoryAllocation < 4096 ? .warning : .tertiary)
                        }
                    }

                    LauncherDemoRow("启动选项") {
                        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                            LauncherCheckbox("启动前备份存档", isOn: $autoBackupSaves)
                            LauncherCheckbox("关闭启动器后保持游戏运行", isOn: $keepLauncherOpen)
                        }
                    }

                    HStack(spacing: LauncherSpace.md) {
                        Spacer(minLength: LauncherSpace.md)
                        LauncherButton("还原默认", variant: .ghost, size: .medium) {}
                        LauncherButton("保存设置", systemImage: "checkmark", variant: .primary, size: .medium, shortcut: "⌘S") {}
                    }
                }
            }
        }
    }

    // MARK: - 辅助

    /// 字段上方的微标签 + 控件本体。
    private func fieldBlock<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
            Text(label).textStyle(.micro, tone: .tertiary)
            content()
        }
    }

    /// 按当前内存分配给出的建议文案。
    private var memoryHint: String {
        if memoryAllocation < 4096 {
            return "内存偏低，128 个模组可能频繁卡顿。"
        } else if memoryAllocation >= 8192 {
            return "内存充裕，可同时加载高清材质包。"
        } else {
            return "当前分配 \(memoryAllocation) MB，适合 1.21.4 + 128 个模组。"
        }
    }
}
