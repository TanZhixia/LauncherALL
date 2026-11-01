import SwiftUI

/// 画廊页面骨架：统一滚动、页头与内容宽度，保证每一页的版式节奏一致。
public struct LauncherPageScaffold<Content: View>: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    private let title: String
    private let subtitle: String?
    private let content: () -> Content

    public init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    public var body: some View {
        Group {
            if snapshotMode {
                pageContent
            } else {
                ScrollView { pageContent }
                    .scrollIndicators(.hidden)
            }
        }
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xl) {
            VStack(alignment: .leading, spacing: LauncherSpace.xs) {
                Text(title).textStyle(.display)
                if let subtitle {
                    Text(subtitle).textStyle(.caption, tone: .secondary)
                }
            }
            content()
        }
        .frame(maxWidth: 1040, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, LauncherSpace.xxl)
        .padding(.top, LauncherSpace.xl)
        .padding(.bottom, LauncherSpace.xxxl)
    }
}

/// 分组区块：小标签 + 说明 + 内容。
public struct LauncherSection<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let content: () -> Content

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                LauncherLabel(title)
                if let subtitle {
                    Text(subtitle).textStyle(.micro, tone: .tertiary)
                }
            }
            content()
        }
    }
}

/// 单行样例：左侧说明 + 右侧控件，用于控件集合页。
public struct LauncherDemoRow<Content: View>: View {
    private let label: String
    private let content: () -> Content

    public init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    public var body: some View {
        HStack(alignment: .center, spacing: LauncherSpace.lg) {
            Text(label)
                .textStyle(.caption, tone: .secondary)
                .frame(width: 96, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 自适应网格：控件矩阵展示。
public struct LauncherDemoGrid<Content: View>: View {
    private let minWidth: CGFloat
    private let content: () -> Content

    public init(minWidth: CGFloat = 200, @ViewBuilder content: @escaping () -> Content) {
        self.minWidth = minWidth
        self.content = content
    }

    public var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minWidth), spacing: LauncherSpace.md, alignment: .leading)],
            alignment: .leading,
            spacing: LauncherSpace.md
        ) {
            content()
        }
    }
}

/// 页面顶部的操作条（右侧放主题切换等全局操作）。
public struct LauncherPageHeader<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: () -> Content

    public init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .center, spacing: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text(title).textStyle(.title)
                if let subtitle {
                    Text(subtitle).textStyle(.micro, tone: .tertiary)
                }
            }
            Spacer(minLength: LauncherSpace.md)
            trailing()
        }
    }
}
