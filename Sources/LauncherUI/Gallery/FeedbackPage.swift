import SwiftUI

/// 反馈组件画廊页：进度条、加载指示、骨架屏、横幅与 Toast 提示。
public struct FeedbackPage: View {
    public init() {}

    public var body: some View {
        LauncherPageScaffold(
            title: "反馈与状态",
            subtitle: "进度、加载、占位骨架、横幅与 Toast，覆盖下载与运行时的各种状态"
        ) {
            progressSection
            spinnerSection
            skeletonSection
            bannerSection
            toastSection
        }
    }

    // MARK: - 进度条

    private var progressSection: some View {
        LauncherSection(
            "进度条",
            subtitle: "4 种语义 tone；value 为 nil 时显示不确定进度循环光带"
        ) {
            LauncherCard(level: .regular) {
                VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                    LauncherProgressBar(value: 0.68, label: "Fabric API 0.100.1 · 下载中")
                    LauncherProgressBar(value: 1.0, label: "资源索引已校验完成", tone: .success)
                    LauncherProgressBar(value: 0.42, label: "正在校验 12 个模组资源", tone: .warning)
                    LauncherProgressBar(value: 0.15, label: "磁盘剩余空间不足 2 GB", tone: .danger)
                    LauncherProgressBar(label: "正在解析版本清单…")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 加载指示

    private var spinnerSection: some View {
        LauncherSection(
            "加载指示",
            subtitle: "Spinner 三种尺寸，配色跟随语义 tone"
        ) {
            LauncherCard(level: .regular) {
                HStack(alignment: .center, spacing: LauncherSpace.xxl) {
                    spinnerSample(size: 14, title: "小 14")
                    spinnerSample(size: 20, title: "中 20")
                    spinnerSample(size: 28, title: "大 28")
                    Spacer(minLength: LauncherSpace.md)
                    HStack(spacing: LauncherSpace.sm) {
                        LauncherSpinner(size: 16, tone: .success)
                        Text("正在连接 mc.hypixel.net…")
                            .textStyle(.caption, tone: .secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func spinnerSample(size: CGFloat, title: String) -> some View {
        VStack(spacing: LauncherSpace.sm) {
            LauncherSpinner(size: size)
            LauncherMonoText(title, tone: .tertiary)
        }
    }

    // MARK: - 骨架屏

    private var skeletonSection: some View {
        LauncherSection(
            "骨架屏",
            subtitle: "加载中的数据占位，避免内容出现时页面跳动"
        ) {
            LauncherCard(level: .regular) {
                VStack(alignment: .leading, spacing: LauncherSpace.lg) {
                    HStack(alignment: .top, spacing: LauncherSpace.md) {
                        LauncherSkeleton(
                            width: LauncherControl.large,
                            height: LauncherControl.large,
                            cornerRadius: LauncherRadius.md
                        )
                        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                            LauncherSkeleton(width: 180, height: 14)
                            LauncherSkeleton(height: 10)
                            LauncherSkeleton(width: 120, height: 10)
                        }
                    }
                    LauncherDivider()
                    LauncherSkeleton(height: 120, cornerRadius: LauncherRadius.lg)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 横幅

    private var bannerSection: some View {
        LauncherSection(
            "横幅",
            subtitle: "info / success / warning / danger，可带一个行动按钮"
        ) {
            VStack(spacing: LauncherSpace.md) {
                LauncherBanner(
                    title: "Java 21 已就绪",
                    message: "当前实例使用系统已安装的 Microsoft OpenJDK 21.0.4，可以直接启动。",
                    tone: .info
                )
                LauncherBanner(
                    title: "实例已准备完成",
                    message: "1.21.4 · Fabric 的 214 个模组全部校验通过。",
                    tone: .success
                )
                LauncherBanner(
                    title: "2 个模组需要更新",
                    message: "Sodium 与 Iris 有新版本可用，建议启动前更新以避免渲染异常。",
                    tone: .warning,
                    actionTitle: "全部更新",
                    onAction: {}
                )
                LauncherBanner(
                    title: "下载失败",
                    message: "连接模组镜像超时，已自动切换备用节点，可手动重试。",
                    tone: .danger,
                    actionTitle: "重试",
                    onAction: {}
                )
            }
        }
    }

    // MARK: - Toast

    private var toastSection: some View {
        LauncherSection(
            "Toast",
            subtitle: "浮层提示：成功与警告两条，带关闭按钮"
        ) {
            HStack(alignment: .top, spacing: LauncherSpace.md) {
                LauncherToast(
                    title: "模组更新完成",
                    message: "12 个模组已更新到最新版本，可以启动游戏了。",
                    tone: .success,
                    onDismiss: {}
                )
                LauncherToast(
                    title: "服务器连接不稳定",
                    message: "延迟 240 ms，已自动切换到备用节点。",
                    tone: .warning,
                    onDismiss: {}
                )
            }
        }
    }
}
