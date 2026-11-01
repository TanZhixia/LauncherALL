import SwiftUI

// MARK: - 输入框公共底板

/// 输入类控件共用底板：内凹槽底 + 1px 描边 + 聚焦 2pt 外环 + 错误态危险描边。
/// 所有颜色/圆角/间距均取自主题令牌，保证深浅主题下都清晰可读。
private struct LauncherInputChrome<Content: View>: View {
    @Environment(\.launcherTheme) private var theme

    private let isFocused: Bool
    private let hasError: Bool
    private let cornerRadius: CGFloat
    private let content: () -> Content

    init(
        isFocused: Bool,
        hasError: Bool,
        cornerRadius: CGFloat = LauncherRadius.md,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isFocused = isFocused
        self.hasError = hasError
        self.cornerRadius = cornerRadius
        self.content = content
    }

    /// 描边语义色：错误 > 聚焦 > 常规，三者互斥。
    private var borderColor: Color {
        if hasError { return theme.colors.danger }
        return isFocused ? theme.colors.focusRing : theme.colors.stroke
    }

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .overlay {
                // 聚焦外环：比底板大 4pt 的圆角矩形，2pt 环、35% 透明度
                RoundedRectangle(cornerRadius: cornerRadius + LauncherSpace.xs, style: .continuous)
                    .strokeBorder(theme.colors.focusRing.opacity(0.35), lineWidth: 2)
                    .padding(-LauncherSpace.xs)
                    .opacity(isFocused ? 1 : 0)
                    .allowsHitTesting(false)
            }
            // 原生输入控件（TextField/SecureField/TextEditor）按主题明暗绘制文字与光标
            .environment(\.colorScheme, theme.scheme)
            .launcherAnimation(LauncherMotion.smooth, value: isFocused)
            .launcherAnimation(LauncherMotion.smooth, value: hasError)
    }
}

// MARK: - 辅助 / 错误文案

/// 输入框下方文案：错误优先显示，与 helper 二选一，绝不同时出现。
private struct LauncherFieldMessage: View {
    let helper: String?
    let error: String?

    var body: some View {
        if let message = error, !message.isEmpty {
            HStack(spacing: LauncherSpace.xs) {
                Image(systemName: "exclamationmark.circle.fill")
                    .textStyle(.micro, tone: .danger)
                Text(message)
                    .textStyle(.micro, tone: .danger)
            }
        } else if let helperText = helper, !helperText.isEmpty {
            Text(helperText)
                .textStyle(.micro, tone: .tertiary)
        }
    }
}

// MARK: - 离屏渲染替代文本

/// 离屏渲染（ImageRenderer）下替代 AppKit 输入控件的静态文本。
/// 字体、配色、对齐与原生控件一致，保证导出的截图中输入框内容可读。
private struct LauncherSnapshotText: View {
    let value: String
    let placeholder: String
    /// 密码类：用圆点遮蔽真实内容。
    var isMasked: Bool = false

    /// 实际展示的文案：空值显示 placeholder，否则显示值（密码已遮蔽）。
    private var displayText: String {
        if value.isEmpty { return placeholder }
        if isMasked { return String(repeating: "•", count: max(1, value.count)) }
        return value
    }

    var body: some View {
        Text(displayText)
            .textStyle(.body, tone: value.isEmpty ? .tertiary : .primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 单行输入框

/// 单行文本输入框：内凹底、聚焦外环、错误态与辅助文案。
public struct LauncherTextField: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode
    @FocusState private var isFocused: Bool

    private let placeholder: String
    @Binding private var text: String
    private let systemImage: String?
    private let helper: String?
    private let error: String?
    private let isDisabled: Bool
    private let onSubmit: (() -> Void)?

    /// 创建单行输入框，可带前置图标、helper、错误态与回车回调。
    public init(
        _ placeholder: String,
        text: Binding<String>,
        systemImage: String? = nil,
        helper: String? = nil,
        error: String? = nil,
        isDisabled: Bool = false,
        onSubmit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.systemImage = systemImage
        self.helper = helper
        self.error = error
        self.isDisabled = isDisabled
        self.onSubmit = onSubmit
    }

    /// 是否处于错误态（空字符串视为无错误）。
    private var hasError: Bool {
        !(error ?? "").isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            LauncherInputChrome(isFocused: isFocused, hasError: hasError) {
                HStack(spacing: LauncherSpace.sm) {
                    leadingIcon
                    input
                }
                .padding(.horizontal, LauncherSpace.md)
                .frame(height: LauncherControl.medium)
            }
            LauncherFieldMessage(helper: helper, error: error)
        }
        .opacity(isDisabled ? 0.5 : 1)
    }

    /// 可选前置图标：聚焦时用强调色提示当前焦点。
    @ViewBuilder
    private var leadingIcon: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .textStyle(.body, tone: isFocused ? .accent : .tertiary)
                .frame(width: LauncherSpace.lg)
        }
    }

    /// 输入区：离屏渲染时用静态文本替代 AppKit TextField（外框与布局不变）。
    @ViewBuilder
    private var input: some View {
        if snapshotMode {
            LauncherSnapshotText(value: text, placeholder: placeholder)
        } else {
            nativeInput
        }
    }

    /// 自绘 placeholder（系统 placeholder 无法跟随主题色）+ 系统 TextField。
    private var nativeInput: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .textStyle(.body, tone: .tertiary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .textStyle(.body)
                .focused($isFocused)
                .disabled(isDisabled)
                .onSubmit { onSubmit?() }
        }
    }
}

// MARK: - 搜索框

/// 搜索框：左侧放大镜、有内容时右侧清除按钮，回车触发提交。
public struct LauncherSearchField: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    @Binding private var text: String
    private let placeholder: String
    private let onSubmit: (() -> Void)?

    /// 创建搜索框，默认占位文案面向版本/整合包/服务器搜索。
    public init(
        text: Binding<String>,
        placeholder: String = "搜索版本、整合包或服务器",
        onSubmit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    public var body: some View {
        LauncherInputChrome(isFocused: isFocused, hasError: false) {
            HStack(spacing: LauncherSpace.sm) {
                Image(systemName: "magnifyingglass")
                    .textStyle(.body, tone: isFocused ? .accent : .tertiary)
                    .frame(width: LauncherSpace.lg)
                input
                if !text.isEmpty {
                    clearButton
                }
            }
            .padding(.horizontal, LauncherSpace.md)
            .frame(height: LauncherControl.medium)
        }
    }

    /// 搜索输入区：离屏渲染时用静态文本替代 AppKit TextField（放大镜与清除按钮照旧）。
    @ViewBuilder
    private var input: some View {
        if snapshotMode {
            LauncherSnapshotText(value: text, placeholder: placeholder)
        } else {
            nativeInput
        }
    }

    /// 自绘 placeholder（系统 placeholder 无法跟随主题色）+ 系统 TextField。
    private var nativeInput: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .textStyle(.body, tone: .tertiary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .textStyle(.body)
                .focused($isFocused)
                .onSubmit { onSubmit?() }
        }
    }

    /// 清除按钮：仅在有内容时出现。
    private var clearButton: some View {
        Button(action: clear) {
            Image(systemName: "xmark.circle.fill")
                .textStyle(.caption, tone: .tertiary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .launcherPointer()
        .accessibilityLabel("清除搜索内容")
        .help("清除")
    }

    /// 清空搜索内容，并尊重“减弱动效”设置。
    private func clear() {
        if reduceMotion {
            text = ""
        } else {
            withAnimation(.easeOut(duration: LauncherMotion.fast)) { text = "" }
        }
    }
}

// MARK: - 密码框

/// 密码输入框：内容以安全方式遮蔽，视觉与普通输入框一致。
public struct LauncherSecureField: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode
    @FocusState private var isFocused: Bool

    private let placeholder: String
    @Binding private var text: String
    private let systemImage: String?

    /// 创建密码输入框，可选前置图标。
    public init(_ placeholder: String, text: Binding<String>, systemImage: String? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.systemImage = systemImage
    }

    public var body: some View {
        LauncherInputChrome(isFocused: isFocused, hasError: false) {
            HStack(spacing: LauncherSpace.sm) {
                leadingIcon
                input
            }
            .padding(.horizontal, LauncherSpace.md)
            .frame(height: LauncherControl.medium)
        }
    }

    /// 可选前置图标。
    @ViewBuilder
    private var leadingIcon: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .textStyle(.body, tone: isFocused ? .accent : .tertiary)
                .frame(width: LauncherSpace.lg)
        }
    }

    /// 安全输入区：离屏渲染时用圆点遮蔽文本替代 AppKit SecureField。
    @ViewBuilder
    private var input: some View {
        if snapshotMode {
            LauncherSnapshotText(value: text, placeholder: placeholder, isMasked: true)
        } else {
            nativeInput
        }
    }

    /// 自绘 placeholder（系统 placeholder 无法跟随主题色）+ 系统 SecureField。
    private var nativeInput: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .textStyle(.body, tone: .tertiary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
            SecureField("", text: $text)
                .textFieldStyle(.plain)
                .textStyle(.body)
                .focused($isFocused)
        }
    }
}

// MARK: - 多行输入框

/// 多行文本输入框：去系统背景的 TextEditor + 自绘 placeholder。
public struct LauncherTextArea: View {
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode
    @FocusState private var isFocused: Bool

    private let placeholder: String
    @Binding private var text: String
    private let minHeight: CGFloat

    /// 创建多行输入框，默认最小高度 90pt。
    public init(_ placeholder: String, text: Binding<String>, minHeight: CGFloat = 90) {
        self.placeholder = placeholder
        self._text = text
        self.minHeight = minHeight
    }

    public var body: some View {
        LauncherInputChrome(isFocused: isFocused, hasError: false) {
            Group {
                if snapshotMode {
                    snapshotContent
                } else {
                    editorContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: minHeight)
        }
    }

    /// 离屏渲染替代：顶部对齐的静态文本，padding 与 TextEditor 内容一致。
    private var snapshotContent: some View {
        Text(text.isEmpty ? placeholder : text)
            .textStyle(.body, tone: text.isEmpty ? .tertiary : .primary)
            .padding(.horizontal, LauncherSpace.md + LauncherSpace.xs)
            .padding(.vertical, LauncherSpace.sm + LauncherSpace.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
    }

    /// 真实编辑器：去系统背景的 TextEditor + 自绘 placeholder。
    private var editorContent: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                placeholderView
            }
            TextEditor(text: $text)
                .textStyle(.body)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(.horizontal, LauncherSpace.md)
                .padding(.vertical, LauncherSpace.sm)
        }
    }

    /// 自绘 placeholder，与首行文字基线近似对齐（TextEditor 自带约 5pt 内边距，用 xs 近似）。
    private var placeholderView: some View {
        Text(placeholder)
            .textStyle(.body, tone: .tertiary)
            .lineLimit(1)
            .padding(.leading, LauncherSpace.md + LauncherSpace.xs)
            .padding(.top, LauncherSpace.sm + LauncherSpace.xs)
            .allowsHitTesting(false)
    }
}
