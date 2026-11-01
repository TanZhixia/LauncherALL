import SwiftUI

/// 设置行（PCL 风格）：左侧标题 + 说明，右侧控件槽位；可带信息提示与分页底边。
public struct LauncherSettingRow<Control: View>: View {
    @Environment(\.launcherTheme) private var theme

    private let title: String
    private let subtitle: String?
    private let tooltip: String?
    private let showsDivider: Bool
    private let control: () -> Control

    public init(
        _ title: String,
        subtitle: String? = nil,
        tooltip: String? = nil,
        showsDivider: Bool = true,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tooltip = tooltip
        self.showsDivider = showsDivider
        self.control = control
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: LauncherSpace.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(theme.colors.textPrimary)
                        if let tooltip {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.colors.textTertiary)
                                .launcherTooltip(tooltip)
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                }
                Spacer(minLength: LauncherSpace.sm)
                control()
            }
            .padding(.vertical, LauncherSpace.xs)

            if showsDivider {
                Rectangle()
                    .fill(theme.colors.stroke.opacity(0.6))
                    .frame(height: 1)
            }
        }
    }
}

/// 信息提示小图标（悬停显示说明）。
public struct LauncherHintIcon: View {
    @Environment(\.launcherTheme) private var theme
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.system(size: 10))
            .foregroundStyle(theme.colors.textTertiary)
            .launcherTooltip(text)
    }
}

/// 页面标题行（PCL 右侧面板顶部）：大标题 + 说明 + 右侧操作按钮槽。
public struct LauncherPanelHeader<Trailing: View>: View {
    @Environment(\.launcherTheme) private var theme

    private let title: String
    private let subtitle: String?
    private let trailing: () -> Trailing

    public init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension LauncherPanelHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() })
    }
}
