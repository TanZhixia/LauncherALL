import SwiftUI
import AppKit

/// 启动器外壳：左侧面板侧栏 + 右侧页面区，全窗口共用同一套氛围背景。
public struct LauncherShellView: View {
    @Environment(LauncherThemeManager.self) private var themeManager
    @State private var selection: LauncherGallerySection

    public init(initialSection: LauncherGallerySection = .studio) {
        _selection = State(initialValue: initialSection)
    }

    public var body: some View {
        let theme = themeManager.theme
        ZStack {
            LauncherAppBackground()

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    sidebar(theme: theme, height: proxy.size.height)
                    Rectangle()
                        .fill(theme.colors.stroke)
                        .frame(width: 1, height: proxy.size.height)
                    detail(height: proxy.size.height)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
            }
        }
        .environment(\.colorScheme, theme.scheme)
        .background(theme.colors.canvas)
        .animation(LauncherMotion.spring, value: themeManager.themeID)
    }

    // MARK: - 侧栏

    private func sidebar(theme: LauncherTheme, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: LauncherSpace.lg) {
            brand(theme: theme)

            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                ForEach(LauncherGallerySection.groupOrder, id: \.0) { group, sections in
                    LauncherLabel(group)
                        .padding(.horizontal, LauncherSpace.sm)
                        .padding(.top, group == LauncherGallerySection.groupOrder.first?.0 ? 0 : LauncherSpace.sm)
                        .padding(.bottom, LauncherSpace.xxs)
                    ForEach(sections) { section in
                        LauncherSidebarItem(navItem(for: section), isSelected: selection == section) {
                            withAnimation(LauncherMotion.spring) {
                                selection = section
                            }
                        }
                    }
                }
            }

            Spacer(minLength: LauncherSpace.lg)

            sidebarFooter(theme: theme)
        }
        .padding(.horizontal, LauncherSpace.md)
        .padding(.bottom, LauncherSpace.md)
        .padding(.top, 40)
        .frame(width: 252, height: height, alignment: .top)
        .background { LauncherGlassBackground(level: .strong, cornerRadius: 0) }
    }

    private func brand(theme: LauncherTheme) -> some View {
        HStack(spacing: LauncherSpace.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .fill(theme.colors.accent)
                    .frame(width: 34, height: 34)
                Image(systemName: "cube.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.colors.onAccent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("方块启动器")
                    .textStyle(.headline)
                LauncherMonoText("v0.1.0 · UI Kit", tone: .tertiary, size: 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LauncherSpace.xs)
        .padding(.bottom, LauncherSpace.xxs)
    }

    private func navItem(for section: LauncherGallerySection) -> LauncherNavItem {
        LauncherNavItem(id: section.rawValue, title: section.title, systemImage: section.systemImage)
    }

    private func sidebarFooter(theme: LauncherTheme) -> some View {
        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
            HStack(spacing: LauncherSpace.xs) {
                ForEach(themeManager.presets) { preset in
                    themeDot(preset: preset, isSelected: preset.id == themeManager.themeID)
                }
                Spacer(minLength: 0)
                LauncherMonoText("\(themeManager.presets.count) 主题", tone: .tertiary, size: 10)
            }
            .padding(.horizontal, LauncherSpace.xxs)

            HStack(spacing: LauncherSpace.sm) {
                LauncherAvatar(name: "Steve", systemImage: "person.fill", size: 28, isOnline: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Steve")
                        .textStyle(.bodyStrong)
                    Text("离线账户")
                        .textStyle(.micro, tone: .tertiary)
                }
                Spacer(minLength: 0)
                LauncherIconButton(systemImage: "gearshape.fill", variant: .ghost, size: .small, accessibilityLabel: "设置") {}
            }
            .padding(.horizontal, LauncherSpace.sm)
            .padding(.vertical, LauncherSpace.sm)
            .background {
                RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                            .strokeBorder(theme.colors.stroke, lineWidth: 1)
                    )
            }
        }
    }

    private func themeDot(preset: LauncherTheme, isSelected: Bool) -> some View {
        Button {
            withAnimation(LauncherMotion.spring) {
                themeManager.select(preset.id)
            }
        } label: {
            Circle()
                .fill(preset.colors.surfaceElevated)
                .overlay(
                    Circle().strokeBorder(preset.colors.accent.opacity(0.85), lineWidth: 1)
                )
                .frame(width: 18, height: 18)
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(themeManager.theme.colors.textSecondary, lineWidth: 1.5)
                            .padding(-3)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(preset.name)
        .accessibilityLabel("切换到主题 \(preset.name)")
    }

    // MARK: - 页面区

    private func detail(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            selection.page
                .id(themeManager.themeID)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
        .clipped()
    }
}

/// 窗口外观配置：透明标题栏 + 常规激活策略（SPM 可执行程序也能正常出现在 Dock）。
public struct WindowConfigurator: NSViewRepresentable {
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
