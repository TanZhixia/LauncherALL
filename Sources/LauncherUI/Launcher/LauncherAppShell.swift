import SwiftUI
import AppKit

/// 启动器主壳：顶部导航栏（启动 / 下载 / 设置 / 更多）+ 内容区。
/// 全局路由（页面切换 / 轻提示 / 确认框 / 画廊）通过 `LauncherRouter` 注入，页面里任何按钮都能真正生效。
public struct LauncherAppShell: View {
    @Environment(LauncherThemeManager.self) private var themeManager
    @Environment(LauncherEngine.self) private var engine
    @Environment(AccountStore.self) private var accountStore
    @Environment(DSHProcessController.self) private var dshProcess
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    @State private var router: LauncherRouter
    @State private var updateChecker = UpdateChecker()

    public init(initialTab: LauncherTab = .launch, initialProduct: LauncherProduct = .minecraft) {
        _router = State(initialValue: LauncherRouter(initialTab: initialTab, initialProduct: initialProduct))
    }

    private var theme: LauncherTheme { themeManager.theme }

    public var body: some View {
        ZStack {
            theme.colors.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar(theme: theme)
                Rectangle()
                    .fill(theme.colors.stroke)
                    .frame(height: 1)
                content
            }

            LauncherOverlayHost()
        }
        .launcherRouterEnvironment(router)
        .environment(\.colorScheme, theme.scheme)
        // 在壳层再注入一次主题值：主题切换时确保页面也立刻拿到新令牌（不依赖根视图重算）
        .environment(\.launcherTheme, theme)
        .animation(LauncherMotion.spring, value: router.selectedTab)
        .background { shortcutButtons }
        .sheet(isPresented: galleryBinding) {
            LauncherShellView()
                .launcherThemeEnvironment(themeManager)
                .frame(minWidth: 1180, minHeight: 840)
        }
        .sheet(isPresented: loginSheetBinding) {
            MicrosoftLoginSheet()
                .launcherThemeEnvironment(themeManager)
                .environment(accountStore)
                .environment(\.colorScheme, theme.scheme)
        }
        .onChange(of: accountStore.successMessage) { _, message in
            guard let message, !snapshotMode else { return }
            _ = accountStore.consumeSuccessMessage()
            router.showToast(message, tone: .success)
        }
        .task { await checkUpdatesOnStartIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            dshProcess.stopSynchronously()
        }
        .onChange(of: isGameRunning) { _, running in
            // 「启动后最小化」：真实隐藏启动器窗口
            guard running, engine.settings.minimizeAfterLaunch, !snapshotMode else { return }
            LauncherWindowActions.hideLauncher()
        }
    }

    // MARK: - 顶部导航栏

    private func topBar(theme: LauncherTheme) -> some View {
        HStack(spacing: LauncherSpace.sm) {
            productSwitcher(theme: theme)
                .padding(.leading, 78) // 让出 macOS 红绿灯

            Rectangle()
                .fill(theme.colors.stroke)
                .frame(width: 1, height: 16)
                .padding(.horizontal, LauncherSpace.xs)

            HStack(spacing: LauncherSpace.xxs) {
                ForEach(LauncherTab.allCases) { tab in
                    LauncherTabButton(tab: tab, isSelected: router.selectedTab == tab) {
                        router.go(tab)
                    }
                    .help("\(tab.title)（\(tab.shortcut)）")
                }
            }

            Spacer(minLength: LauncherSpace.md)

            themeToggle(theme: theme)

            if router.activeProduct == .minecraft {
                accountChip
            }

            LauncherIconButton(
                systemImage: "gearshape.fill",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "打开设置"
            ) {
                router.go(.settings)
            }
        }
        .padding(.horizontal, LauncherSpace.lg)
        .frame(height: 48)
        .background(theme.colors.surfaceElevated)
    }

    /// 标题栏产品切换：LauncherALL 旗下 Minecraft / DSH 两个启动器入口。
    private func productSwitcher(theme: LauncherTheme) -> some View {
        LauncherMenu(groups: productMenuGroups, width: 272) {
            HStack(spacing: LauncherSpace.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                        .fill(theme.colors.accent)
                        .frame(width: 26, height: 26)
                    Image(systemName: router.activeProduct.systemImage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.colors.onAccent)
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: LauncherSpace.xxs) {
                        Text("LauncherALL")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    Text("\(router.activeProduct.title) · \(LauncherBuildInfo.current.versionText)")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, LauncherSpace.xs)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .help("切换启动器：Minecraft / DSH")
        .accessibilityLabel("LauncherALL，当前 \(router.activeProduct.title)，点击切换启动器")
    }

    /// 产品下拉菜单：勾选当前启动器，点击切换到另一个。
    private var productMenuGroups: [LauncherMenuGroup] {
        let items = LauncherProduct.allCases.map { product in
            LauncherMenuItem(
                product.title,
                id: product.id,
                systemImage: router.activeProduct == product ? "checkmark" : product.systemImage,
                detail: product.subtitle
            ) {
                router.switchProduct(product)
                if product == .dsh {
                    router.showToast("已切换到 DSH 启动器", tone: .info)
                }
            }
        }
        return [LauncherMenuGroup(title: "启动器", items: items)]
    }

    /// 深色 / 浅色主题切换（按钮与 ⌘⇧T 共用）。
    private func toggleTheme() {
        themeManager.select(themeManager.theme.isDark ? "porcelain" : "graphite")
    }

    /// 主题切换：深色 → 浅色、浅色 → 深色。
    private func themeToggle(theme: LauncherTheme) -> some View {
        LauncherIconButton(
            systemImage: theme.isDark ? "sun.max.fill" : "moon.fill",
            variant: .ghost,
            size: .small,
            accessibilityLabel: theme.isDark ? "切换到浅色主题" : "切换到深色主题"
        ) {
            // 直接读当前主题状态再切换，避免闭包捕获到旧主题导致点了没反应
            toggleTheme()
        }
    }

    /// 账户胶囊：显示当前账户（离线 / 正版），点击跳到「设置 → 账户」。
    private var accountChip: some View {
        let record = accountStore.selectedAccount
        let account = LauncherAccount(
            name: record.name,
            type: record.isMicrosoft ? "正版账户" : "离线账户",
            lastLogin: lastLaunchText,
            isOnline: record.isMicrosoft
        )
        return Button {
            router.go(.settings, settingsSection: "account")
        } label: {
            LauncherAccountChip(
                account: account,
                avatar: chipAvatar
            )
        }
        .buttonStyle(.plain)
        .launcherPointer()
        .help("当前账户：\(account.name)（\(account.type)） · 点击管理账户")
        .accessibilityLabel("当前账户 \(account.name)，点击打开账户设置")
    }

    /// 顶栏账户胶囊头像：正版账户显示 crafatar 皮肤头像，离线账户走默认首字母头像。
    private var chipAvatar: AnyView? {
        guard accountStore.selectedAccount.isMicrosoft else { return nil }
        return AnyView(
            MinecraftAvatarView(
                uuid: accountStore.selectedAccount.uuid,
                name: accountStore.selectedAccount.name,
                size: 26
            )
        )
    }

    /// 登录面板绑定。
    private var loginSheetBinding: Binding<Bool> {
        Binding(
            get: { accountStore.isLoginSheetPresented },
            set: { accountStore.isLoginSheetPresented = $0 }
        )
    }

    private var lastLaunchText: String {
        guard let record = engine.settings.launchRecords.first else { return "尚未启动过游戏" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return "上次启动 \(record.versionID) · \(formatter.string(from: record.startedAt))"
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        ZStack {
            switch router.activeProduct {
            case .minecraft:
                page(for: router.selectedTab)
                    .id(router.selectedTab)
                    .transition(.opacity)
            case .dsh:
                dshPage(for: router.selectedTab)
                    .id("dsh-\(router.selectedTab.rawValue)")
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(LauncherMotion.spring, value: router.activeProduct)
    }

    @ViewBuilder
    private func page(for tab: LauncherTab) -> some View {
        switch tab {
        case .launch: LaunchPage()
        case .download: DownloadPage()
        case .settings: SettingsPage()
        case .more: MorePage(onOpenGallery: { router.openGallery() })
        }
    }

    /// DSH 启动器的四个页面（与 Minecraft 同构：启动 / 下载 / 设置 / 更多）。
    @ViewBuilder
    private func dshPage(for tab: LauncherTab) -> some View {
        switch tab {
        case .launch: DSHLaunchPage()
        case .download: DSHDownloadPage()
        case .settings: DSHSettingsPage()
        case .more: DSHMorePage(onOpenGallery: { router.openGallery() })
        }
    }

    // MARK: - 快捷键

    /// 隐形快捷键按钮：⌘1–⌘4 切页（自动回 Minecraft 启动器）、⌘⇧D 设计系统、⌘⇧T 主题、⌘R 刷新环境、⌘, 设置。
    private var shortcutButtons: some View {
        ZStack {
            ForEach(LauncherTab.allCases) { tab in
                Button("") { router.go(tab) }
                    .keyboardShortcut(tab.keyEquivalent, modifiers: .command)
            }
            Button("") { router.openGallery() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("") { toggleTheme() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("") {
                Task { await engine.refreshEnvironment() }
                router.showToast("已刷新 Java 与实例列表")
            }
            .keyboardShortcut("r", modifiers: .command)
            Button("") { router.go(.settings) }
                .keyboardShortcut(",", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - 状态派生

    private var isGameRunning: Bool {
        if case .running = engine.phase { return true }
        return false
    }

    private var galleryBinding: Binding<Bool> {
        Binding(
            get: { router.showGallery },
            set: { router.showGallery = $0 }
        )
    }

    // MARK: - 启动时检查更新

    /// 启动前检查更新：配置了更新源才真正发请求，发现新版本用轻提示告知。
    private func checkUpdatesOnStartIfNeeded() async {
        guard !snapshotMode, engine.settings.checkUpdatesOnStart else { return }
        await updateChecker.check(feedURL: engine.settings.updateFeedURL)
        switch updateChecker.status {
        case .available(_, let latest):
            router.showToast("发现新版本 v\(latest.version)，可在「设置 → 关于」查看", tone: .info)
        case .failed(let message):
            router.showToast("检查更新失败：\(message)", tone: .warning)
        default:
            break
        }
    }
}

/// 窗口外观配置：透明标题栏 + 常规激活策略。
public struct LauncherWindowConfigurator: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}
