import SwiftUI

// MARK: - 左侧面板（PCL 风格：标题 + 搜索 + 列表 + 底部操作）

/// 主页面左侧面板：顶部标题/工具槽、可选搜索框、可滚动列表区、底部固定区。
/// 桌面端（PCL 系启动器）常见的"左列表 + 右内容"布局基础组件。
public struct LauncherSidePanel<Content: View, Footer: View>: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    private let title: String?
    private let count: String?
    private let width: CGFloat
    private let toolbar: AnyView?
    private let searchText: Binding<String>?
    private let searchPlaceholder: String
    private let footer: () -> Footer
    private let content: () -> Content

    public init(
        title: String? = nil,
        count: String? = nil,
        width: CGFloat = 252,
        searchText: Binding<String>? = nil,
        searchPlaceholder: String = "搜索",
        toolbar: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.count = count
        self.width = width
        self.searchText = searchText
        self.searchPlaceholder = searchPlaceholder
        self.toolbar = toolbar
        self.content = content
        self.footer = footer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.sm) {
            if title != nil || toolbar != nil {
                HStack(spacing: LauncherSpace.sm) {
                    if let title {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                    if let count {
                        LauncherBadge(count, tone: .neutral)
                    }
                    Spacer(minLength: 0)
                    if let toolbar { toolbar }
                }
                .padding(.horizontal, LauncherSpace.xxs)
            }

            if let searchText {
                LauncherSearchField(text: searchText, placeholder: searchPlaceholder)
            }

            if snapshotMode {
                VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                    content()
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                        content()
                    }
                }
            }

            footer()
        }
        .padding(LauncherSpace.sm)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.lg, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LauncherRadius.lg, style: .continuous)
                .strokeBorder(theme.colors.stroke, lineWidth: 1)
        }
    }
}

public extension LauncherSidePanel where Footer == EmptyView {
    /// 无底部区域的便捷构造。
    init(
        title: String? = nil,
        count: String? = nil,
        width: CGFloat = 252,
        searchText: Binding<String>? = nil,
        searchPlaceholder: String = "搜索",
        toolbar: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            count: count,
            width: width,
            searchText: searchText,
            searchPlaceholder: searchPlaceholder,
            toolbar: toolbar,
            content: content,
            footer: { EmptyView() }
        )
    }
}

/// 左面板分组小标题（"已安装 / 收藏 / 最近"）。
public struct LauncherSidePanelGroup: View {
    @Environment(\.launcherTheme) private var theme
    private let title: String
    private let trailing: String?

    public init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: LauncherSpace.xxs) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(theme.colors.textTertiary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .padding(.horizontal, LauncherSpace.xs)
        .padding(.top, LauncherSpace.xs)
        .padding(.bottom, LauncherSpace.xxs)
    }
}

// MARK: - 主内容区（右侧）

/// 右内容区容器：统一内边距、可滚动（离屏渲染时自动改为静态堆叠）。
public struct LauncherMainPanel<Content: View>: View {
    @Environment(\.launcherSnapshotMode) private var snapshotMode
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        Group {
            if snapshotMode {
                VStack(alignment: .leading, spacing: LauncherSpace.md) { content() }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: LauncherSpace.md) { content() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 页面骨架（左面板 + 右内容）

/// PCL 式主页面骨架：左侧固定宽面板 + 右侧内容区（含统一页面内边距）。
public struct LauncherPageLayout<Side: View, Main: View>: View {
    @Environment(\.launcherTheme) private var theme
    private let sideWidth: CGFloat
    private let side: () -> Side
    private let main: () -> Main

    public init(
        sideWidth: CGFloat = 252,
        @ViewBuilder side: @escaping () -> Side,
        @ViewBuilder main: @escaping () -> Main
    ) {
        self.sideWidth = sideWidth
        self.side = side
        self.main = main
    }

    public var body: some View {
        HStack(alignment: .top, spacing: LauncherSpace.lg) {
            side()
                .frame(width: sideWidth)
            main()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, LauncherSpace.xxl)
        .padding(.vertical, LauncherSpace.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
