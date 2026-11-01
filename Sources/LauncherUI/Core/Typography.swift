import SwiftUI

/// 文字角色：全项目只允许使用这些角色，禁止临时字号。
public enum LauncherTextStyle: String, CaseIterable {
    case display
    case title
    case sectionTitle
    case headline
    case body
    case bodyStrong
    case caption
    case micro
    case label
    case mono
    case monoSmall

    public var font: Font {
        switch self {
        case .display: return .system(size: 30, weight: .bold, design: .rounded)
        case .title: return .system(size: 22, weight: .semibold, design: .rounded)
        case .sectionTitle: return .system(size: 15, weight: .semibold)
        case .headline: return .system(size: 14, weight: .semibold)
        case .body: return .system(size: 13, weight: .regular)
        case .bodyStrong: return .system(size: 13, weight: .medium)
        case .caption: return .system(size: 12, weight: .regular)
        case .micro: return .system(size: 11, weight: .regular)
        case .label: return .system(size: 10, weight: .semibold)
        case .mono: return .system(size: 12, weight: .regular, design: .monospaced)
        case .monoSmall: return .system(size: 11, weight: .regular, design: .monospaced)
        }
    }

    public var tracking: CGFloat {
        switch self {
        case .display: return -0.4
        case .title: return -0.2
        case .label: return 1.1
        case .mono, .monoSmall: return 0.2
        default: return 0
        }
    }
}

/// 文字语义色。
public enum LauncherTextTone: String, CaseIterable {
    case primary, secondary, tertiary, accent, onAccent, success, warning, danger

    public func color(in theme: LauncherTheme) -> Color {
        let c = theme.colors
        switch self {
        case .primary: return c.textPrimary
        case .secondary: return c.textSecondary
        case .tertiary: return c.textTertiary
        case .accent: return c.accent
        case .onAccent: return c.onAccent
        case .success: return c.success
        case .warning: return c.warning
        case .danger: return c.danger
        }
    }
}

private struct LauncherTextStyleModifier: ViewModifier {
    @Environment(\.launcherTheme) private var theme
    let style: LauncherTextStyle
    let tone: LauncherTextTone

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .tracking(style.tracking)
            .foregroundStyle(tone.color(in: theme))
    }
}

public extension View {
    /// 统一文字样式：字号 + 字距 + 语义色。
    func textStyle(_ style: LauncherTextStyle, tone: LauncherTextTone = .primary) -> some View {
        modifier(LauncherTextStyleModifier(style: style, tone: tone))
    }
}

/// 等宽/强调组合：用于版本号、路径、日志。
public struct LauncherMonoText: View {
    @Environment(\.launcherTheme) private var theme
    private let text: String
    private let tone: LauncherTextTone
    private let size: CGFloat

    public init(_ text: String, tone: LauncherTextTone = .secondary, size: CGFloat = 12) {
        self.text = text
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        Text(text)
            .font(.system(size: size, weight: .regular, design: .monospaced))
            .foregroundStyle(tone.color(in: theme))
    }
}

/// 全大写小标签（分组标题、状态标签）。
public struct LauncherLabel: View {
    @Environment(\.launcherTheme) private var theme
    private let text: String
    private let tone: LauncherTextTone

    public init(_ text: String, tone: LauncherTextTone = .tertiary) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text.uppercased())
            .font(LauncherTextStyle.label.font)
            .tracking(LauncherTextStyle.label.tracking)
            .foregroundStyle(tone.color(in: theme))
    }
}
