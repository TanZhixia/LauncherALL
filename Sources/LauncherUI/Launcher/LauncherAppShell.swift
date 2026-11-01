import SwiftUI
import AppKit

/// 启动器主壳：顶部导航栏（启动 / 下载 / 设置 / 更多）+ 内容区。
public struct LauncherAppShell: View {
    @Environment(LauncherThemeManager.self) private var themeManager
    @State private var selectedTab: LauncherTab
    @State private var showDesignGallery = false

    public init(initialTab: LauncherTab = .launch) {
        _selectedTab = State(initialValue: initialTab)
    }

    public var body: some View {
        let theme = themeManager.theme
        ZStack {
            theme.colors.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar(theme: theme)
                Rectangle()
                    .fill(theme.colors.stroke)
                    .frame(height: 1)
                content
            }
        }
        .environment(\.colorScheme, theme.scheme)
        .animation(LauncherMotion.spring, value: selectedTab)
        .background {
            // 隐形快捷键按钮：⌘⇧D 打开设计系统
            Button("") { showDesignGallery = true }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .sheet(isPresented: $showDesignGallery) {
            LauncherShellView()
                .launcherThemeEnvironment(themeManager)
                .frame(minWidth: 1180, minHeight: 840)
        }
    }

    // MARK: - 顶部导航栏

    private func topBar(theme: LauncherTheme) -> some View {
        HStack(spacing: LauncherSpace.md) {
            brand(theme: theme)
                .padding(.leading, 78) // 让出 macOS 红绿灯

            Rectangle()
                .fill(theme.colors.stroke)
                .frame(width: 1, height: 18)
                .padding(.horizontal, LauncherSpace.xxs)

            HStack(spacing: LauncherSpace.xxs) {
                ForEach(LauncherTab.allCases) { tab in
                    LauncherTabButton(tab: tab, isSelected: selectedTab == tab) {
                        withAnimation(LauncherMotion.spring) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(3)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                            .strokeBorder(theme.colors.stroke, lineWidth: 1)
                    )
            }

            Spacer(minLength: LauncherSpace.md)

            themeToggle(theme: theme)

            LauncherAccountChip()
                .help("当前账户：\(LauncherDemoData.account.name)")

            LauncherIconButton(
                systemImage: "gearshape.fill",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "打开设置"
            ) {
                withAnimation(LauncherMotion.spring) {
                    selectedTab = .settings
                }
            }
        }
        .padding(.horizontal, LauncherSpace.lg)
        .frame(height: 56)
        .background(theme.colors.surfaceElevated)
    }

    private func brand(theme: LauncherTheme) -> some View {
        HStack(spacing: LauncherSpace.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                    .fill(theme.colors.accent)
                    .frame(width: 26, height: 26)
                Image(systemName: "cube.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.colors.onAccent)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("方块启动器")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                LauncherMonoText("v0.2.0", tone: .tertiary, size: 9)
            }
        }
    }

    private func themeToggle(theme: LauncherTheme) -> some View {
        LauncherIconButton(
            systemImage: theme.isDark ? "sun.max.fill" : "moon.fill",
            variant: .ghost,
            size: .small,
            accessibilityLabel: theme.isDark ? "切换到浅色主题" : "切换到深色主题"
        ) {
            withAnimation(LauncherMotion.spring) {
                themeManager.select(theme.isDark ? "porcelain" : "graphite")
            }
        }
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        ZStack {
            page(for: selectedTab)
                .id(selectedTab)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func page(for tab: LauncherTab) -> some View {
        switch tab {
        case .launch: LaunchPage()
        case .download: DownloadPage()
        case .settings: SettingsPage()
        case .more: MorePage(onOpenGallery: { showDesignGallery = true })
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
