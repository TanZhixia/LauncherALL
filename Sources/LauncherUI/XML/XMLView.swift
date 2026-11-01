import SwiftUI

/// 把一段 XML 直接渲染成 SwiftUI 视图（内含状态、动作与诊断展示）。
public struct LauncherXMLView: View {
    @Environment(\.launcherTheme) private var theme
    private let source: String
    private let actions: XMLActionRegistry
    private let data: XMLDataSources
    private let externalStore: XMLStateStore?
    @State private var store: XMLStateStore

    /// 创建 XML 视图。`store` 传入时复用其状态（适合边编辑边预览）。
    public init(
        source: String,
        store: XMLStateStore? = nil,
        actions: XMLActionRegistry? = nil,
        data: XMLDataSources = .empty
    ) {
        self.source = source
        self.actions = actions ?? XMLActionRegistry.demo(themeManager: nil)
        self.data = data
        self.externalStore = store
        let parsed = LauncherXMLDocument.parse(source)
        _store = State(initialValue: store ?? XMLStateStore(values: parsed.initialValues))
    }

    public var body: some View {
        let document = LauncherXMLDocument.parse(source)
        let output = XMLRenderer().render(
            document: document,
            store: externalStore ?? store,
            actions: actions,
            data: data,
            theme: theme
        )
        output.view
    }
}

// MARK: - 诊断 / 兜底视图

/// 诊断面板：列出解析与渲染错误，阻止"静默出错"。
public struct XMLDiagnosticsView: View {
    @Environment(\.launcherTheme) private var theme
    public let diagnostics: [XMLDiagnostic]

    public init(diagnostics: [XMLDiagnostic]) {
        self.diagnostics = diagnostics
    }

    public var body: some View {
        let errors = diagnostics.filter { $0.severity == .error }
        let warnings = diagnostics.filter { $0.severity == .warning }
        let rows = (errors.isEmpty ? warnings : errors).prefix(6)

        VStack(alignment: .leading, spacing: LauncherSpace.xs) {
            HStack(spacing: LauncherSpace.xs) {
                Image(systemName: errors.isEmpty ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(errors.isEmpty ? theme.colors.warning : theme.colors.danger)
                Text(errors.isEmpty ? "XML 警告" : "XML 错误")
                    .font(LauncherTextStyle.bodyStrong.font)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer(minLength: 0)
                Text("\(diagnostics.count) 条")
                    .font(LauncherTextStyle.micro.font)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { item in
                Text(item.element.displayText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(item.element.severity == .error ? theme.colors.danger : theme.colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(LauncherSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: LauncherRadius.md, style: .continuous)
                        .strokeBorder(errors.isEmpty ? theme.colors.stroke : theme.colors.danger.opacity(0.6), lineWidth: 1)
                )
        }
    }
}

/// 未知标签兜底：画一个虚线占位，提示 XML 写错了标签名。
public struct XMLUnknownElementView: View {
    @Environment(\.launcherTheme) private var theme
    public let tag: String

    public init(tag: String) {
        self.tag = tag
    }

    public var body: some View {
        HStack(spacing: LauncherSpace.xs) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 12))
            Text("<\(tag)> 未知元素")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(theme.colors.danger)
        .padding(.horizontal, LauncherSpace.sm)
        .padding(.vertical, LauncherSpace.xs)
        .background {
            RoundedRectangle(cornerRadius: LauncherRadius.sm, style: .continuous)
                .strokeBorder(theme.colors.danger.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }
}
