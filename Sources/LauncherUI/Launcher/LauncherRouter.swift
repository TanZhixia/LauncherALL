import SwiftUI

// MARK: - 全局提示 / 对话框 / 导航

/// 一条轻提示。
public struct LauncherToastMessage: Identifiable, Equatable {
    public let id = UUID()
    public let message: String
    public let tone: LauncherBannerTone

    public init(message: String, tone: LauncherBannerTone) {
        self.message = message
        self.tone = tone
    }

    public static func == (lhs: LauncherToastMessage, rhs: LauncherToastMessage) -> Bool {
        lhs.id == rhs.id && lhs.message == rhs.message
    }
}

/// 一次确认对话框请求。
public struct LauncherDialogRequest: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let confirmTitle: String
    public let isDestructive: Bool
    public let onConfirm: () -> Void
    public let onCancel: (() -> Void)?

    public init(
        title: String,
        message: String,
        confirmTitle: String = "确定",
        isDestructive: Bool = false,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.isDestructive = isDestructive
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
}

/// 一次文本输入对话框请求（重命名实例、修改玩家名等）。
public struct LauncherPromptRequest: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let placeholder: String
    public let initialValue: String
    public let confirmTitle: String
    /// 返回 nil 表示合法；返回文案表示错误。
    public let validate: ((String) -> String?)?
    public let onConfirm: (String) -> Void
    public let onCancel: (() -> Void)?

    public init(
        title: String,
        message: String,
        placeholder: String = "",
        initialValue: String = "",
        confirmTitle: String = "确定",
        validate: ((String) -> String?)? = nil,
        onConfirm: @escaping (String) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.placeholder = placeholder
        self.initialValue = initialValue
        self.confirmTitle = confirmTitle
        self.validate = validate
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
}

/// 全局路由：一级页面切换、跨页跳转、轻提示与确认对话框。
/// 页面里通过 `@Environment(LauncherRouter.self)` 使用，任何按钮都能真正生效。
@MainActor
@Observable
public final class LauncherRouter {
    /// 当前激活的启动器（LauncherALL 集合里的 Minecraft / DSH）。
    public var activeProduct: LauncherProduct = .minecraft
    public var selectedTab: LauncherTab = .launch
    /// 跳转到「更多」页时要打开的分区（如 "logs" / "backup" / "mods" / "screenshot"）。
    public var pendingMoreSection: String?
    /// 跳转到「设置」页时要打开的分类（如 "java" / "appearance"）。
    public var pendingSettingsSection: String?
    /// 跳到「下载」页后要执行的一次性动作（如 "import-modpack"）。
    public var pendingDownloadAction: String?
    public var toast: LauncherToastMessage?
    public var dialog: LauncherDialogRequest?
    public var prompt: LauncherPromptRequest?
    public var showGallery = false

    public init(initialTab: LauncherTab = .launch, initialProduct: LauncherProduct = .minecraft) {
        self.selectedTab = initialTab
        self.activeProduct = initialProduct
    }

    /// 切换一级页面，可同时指定目标页内的分区。
    public func go(_ tab: LauncherTab, moreSection: String? = nil, settingsSection: String? = nil) {
        pendingMoreSection = moreSection
        pendingSettingsSection = settingsSection
        withAnimation(LauncherMotion.spring) {
            selectedTab = tab
        }
    }

    /// 切换启动器（Minecraft / DSH）；切换后保持当前主题与窗口状态。
    public func switchProduct(_ product: LauncherProduct) {
        guard activeProduct != product else { return }
        withAnimation(LauncherMotion.spring) {
            activeProduct = product
        }
    }

    /// 弹一条 2 秒自动消失的轻提示。
    public func showToast(_ message: String, tone: LauncherBannerTone = .success) {
        let toast = LauncherToastMessage(message: message, tone: tone)
        self.toast = toast
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if self?.toast?.id == toast.id {
                self?.toast = nil
            }
        }
    }

    public func showDialog(_ request: LauncherDialogRequest) {
        dialog = request
    }

    /// 弹一个文本输入对话框（重命名 / 修改玩家名等）。
    public func showPrompt(_ request: LauncherPromptRequest) {
        prompt = request
    }

    public func openGallery() {
        showGallery = true
    }
}

// MARK: - 环境注入

private struct LauncherRouterKey: EnvironmentKey {
    static let defaultValue: LauncherRouter? = nil
}

public extension EnvironmentValues {
    var launcherRouter: LauncherRouter? {
        get { self[LauncherRouterKey.self] }
        set { self[LauncherRouterKey.self] = newValue }
    }
}

public extension View {
    /// 注入全局路由（同时作为可观察对象与 EnvironmentValue，两种取法都可用）。
    func launcherRouterEnvironment(_ router: LauncherRouter) -> some View {
        self
            .environment(router)
            .environment(\.launcherRouter, router)
    }
}

// MARK: - 宿主：轻提示 + 对话框

/// 提示与对话框宿主：挂在主壳上，页面通过 Router 触发即可。
public struct LauncherOverlayHost: View {
    @Environment(LauncherRouter.self) private var router
    @Environment(\.launcherTheme) private var theme

    public init() {}

    public var body: some View {
        ZStack {
            if let toast = router.toast {
                VStack {
                    Spacer()
                    LauncherToast(title: toast.message, message: "", tone: toast.tone)
                        .padding(.bottom, LauncherSpace.xxxl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(false)
                .animation(LauncherMotion.spring, value: router.toast?.id)
            }

            if let dialog = router.dialog {
                ZStack {
                    theme.colors.scrim
                        .ignoresSafeArea()
                        .onTapGesture { router.dialog = nil }
                    LauncherCard(level: .strong, padding: LauncherSpace.lg) {
                        VStack(alignment: .leading, spacing: LauncherSpace.md) {
                            Text(dialog.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.colors.textPrimary)
                            Text(dialog.message)
                                .font(LauncherTextStyle.caption.font)
                                .foregroundStyle(theme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: LauncherSpace.sm) {
                                Spacer(minLength: 0)
                                LauncherButton("取消", variant: .ghost, size: .small) {
                                    dialog.onCancel?()
                                    router.dialog = nil
                                }
                                LauncherButton(
                                    dialog.confirmTitle,
                                    variant: dialog.isDestructive ? .danger : .primary,
                                    size: .small
                                ) {
                                    dialog.onConfirm()
                                    router.dialog = nil
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 400)
                }
                .transition(.opacity)
            }
            if let prompt = router.prompt {
                LauncherPromptHost(request: prompt)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - 文本输入对话框

/// 文本输入对话框：校验失败时禁用确认按钮并显示错误。
private struct LauncherPromptHost: View {
    @Environment(LauncherRouter.self) private var router
    @Environment(\.launcherTheme) private var theme

    let request: LauncherPromptRequest
    @State private var text: String
    @State private var error: String?

    init(request: LauncherPromptRequest) {
        self.request = request
        _text = State(initialValue: request.initialValue)
        _error = State(initialValue: request.validate?(request.initialValue))
    }

    public var body: some View {
        ZStack {
            theme.colors.scrim
                .ignoresSafeArea()
                .onTapGesture { cancel() }
            LauncherCard(level: .strong, padding: LauncherSpace.lg) {
                VStack(alignment: .leading, spacing: LauncherSpace.md) {
                    Text(request.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(request.message)
                        .font(LauncherTextStyle.caption.font)
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LauncherTextField(request.placeholder, text: $text)
                        .onChange(of: text) { _, newValue in
                            error = request.validate?(newValue)
                        }
                    if let error {
                        Text(error)
                            .textStyle(.micro, tone: .danger)
                            .lineLimit(1)
                    }
                    HStack(spacing: LauncherSpace.sm) {
                        Spacer(minLength: 0)
                        LauncherButton("取消", variant: .ghost, size: .small) {
                            cancel()
                        }
                        LauncherButton(request.confirmTitle, variant: .primary, size: .small) {
                            guard error == nil else { return }
                            let value = text
                            router.prompt = nil
                            request.onConfirm(value)
                        }
                        .disabled(error != nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 440)
        }
    }

    private func cancel() {
        let onCancel = request.onCancel
        router.prompt = nil
        onCancel?()
    }
}
