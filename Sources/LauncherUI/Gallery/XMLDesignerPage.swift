import SwiftUI

/// 预览内容高度测量：用于缩放画布后得到真实内容高度。
private struct XMLPreviewContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// XML 设计器：左侧 XML 源码（行号 / 编辑），右侧缩放画布实时预览，顶部切换示例。
public struct XMLDesignerPage: View {
    @Environment(LauncherThemeManager.self) private var themeManager
    @Environment(\.launcherTheme) private var theme
    @Environment(\.launcherSnapshotMode) private var snapshotMode

    @State private var sampleID: String = XMLDesignerPage.initialSample.id
    @State private var source: String = XMLDesignerPage.initialSource
    @State private var store: XMLStateStore = XMLStateStore(
        values: LauncherXMLDocument.parse(XMLDesignerPage.initialSource).initialValues
    )
    @State private var isEditing = false
    /// 缩放画布内 XML 内容在 1180pt 设计宽度下的真实高度。
    @State private var canvasContentHeight: CGFloat = 0

    // 预览画布按启动器真实窗口宽度设计，再等比缩放进面板。
    private static let designCanvasWidth: CGFloat = 1180
    // 示例库只加载一次：切换示例时直接取用，避免每次重读资源。
    private static let samples: [XMLSample] = XMLSampleLibrary.all
    private static let initialSample: XMLSample = samples.first
        ?? XMLSample(id: "launcher", title: "启动器首屏", summary: "", source: XMLSampleLibrary.fallbackSource)
    private static let initialSource: String = initialSample.source

    public init() {}

    public var body: some View {
        let diagnostics = currentDiagnostics
        let sample = currentSample

        VStack(alignment: .leading, spacing: LauncherSpace.lg) {
            header

            GeometryReader { proxy in
                let gap = LauncherSpace.lg
                let editorWidth = max(360, (proxy.size.width - gap) * 0.44)
                let previewWidth = max(320, proxy.size.width - editorWidth - gap)
                HStack(alignment: .top, spacing: gap) {
                    editorPanel(width: editorWidth, height: proxy.size.height)
                    previewPanel(
                        sample: sample,
                        diagnostics: diagnostics,
                        width: previewWidth,
                        height: proxy.size.height
                    )
                }
            }

            footer
        }
        .frame(maxWidth: 1040, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, LauncherSpace.xxl)
        .padding(.vertical, LauncherSpace.xl)
    }

    // MARK: - 顶部操作条

    /// 标题 + 说明在左，示例切换、编辑开关与重置在右。
    private var header: some View {
        HStack(alignment: .center, spacing: LauncherSpace.lg) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                Text("XML 设计器").textStyle(.display)
                Text("用 XML 描述界面，右侧实时渲染 SwiftUI。")
                    .textStyle(.caption, tone: .secondary)
            }

            Spacer(minLength: LauncherSpace.md)

            HStack(spacing: LauncherSpace.sm) {
                LauncherSegmentedControl(options: sampleOptions, selection: sampleBinding)
                    .frame(maxWidth: 420, alignment: .trailing)

                LauncherButton(
                    isEditing ? "完成编辑" : "编辑 XML",
                    systemImage: isEditing ? "checkmark" : "pencil",
                    variant: isEditing ? .primary : .secondary,
                    size: .medium,
                    shortcut: "⌘E"
                ) {
                    toggleEditing()
                }

                LauncherButton("重置", systemImage: "arrow.counterclockwise", variant: .ghost, size: .medium) {
                    resetSource()
                }
            }
        }
    }

    // MARK: - 左侧源码面板

    /// 源码面板：文件 chip + 行数/字符数 + 代码区（编辑态换 TextEditor）。
    /// 高度全部显式下传，避免离屏渲染时嵌套弹性布局撑破面板。
    private func editorPanel(width: CGFloat, height: CGFloat) -> some View {
        let contentWidth = max(0, width - 2 * LauncherSpace.md)
        let codeHeight = max(LauncherControl.large,
                            height - 2 * LauncherSpace.md - LauncherControl.small - LauncherSpace.sm)

        return GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherChip(
                        currentFileName,
                        isSelected: isEditing,
                        systemImage: "doc.plaintext"
                    ) {
                        toggleEditing()
                    }
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherMonoText("\(lines.count) 行 · \(source.count) 字符", tone: .tertiary)
                }
                .frame(width: contentWidth, height: LauncherControl.small)

                codePane(width: contentWidth, height: codeHeight)
            }
        }
        .frame(width: width, height: height)
    }

    /// 代码区：内凹玻璃底；行号列固定，代码列可横向滚动。
    private func codePane(width: CGFloat, height: CGFloat) -> some View {
        let innerWidth = max(0, width - 2 * LauncherSpace.sm)
        let innerHeight = max(0, height - 2 * LauncherSpace.sm)

        return GlassPanel(level: .subtle, cornerRadius: LauncherRadius.md, padding: LauncherSpace.sm) {
            Group {
                if isEditing && !snapshotMode {
                    editor(height: innerHeight)
                        .frame(width: innerWidth, height: innerHeight, alignment: .topLeading)
                } else if snapshotMode {
                    // 离屏渲染：ImageRenderer 画不出 TextEditor / ScrollView，用静态行硬裁切。
                    readOnlySnapshot(width: innerWidth, height: innerHeight)
                } else {
                    readOnlyInteractive(width: innerWidth, height: innerHeight)
                }
            }
        }
        .frame(width: width, height: height)
    }

    /// 编辑态：去背景的 TextEditor，等宽 11pt。
    private func editor(height: CGFloat) -> some View {
        TextEditor(text: $source)
            .font(LauncherTextStyle.monoSmall.font)
            .foregroundStyle(theme.colors.textSecondary)
            .tint(theme.colors.accent)
            .scrollContentBackground(.hidden)
            .padding(LauncherSpace.xxs)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
    }

    /// 只读（离屏）：长行软换行，行号与代码同排，截图里不会出现半截代码。
    private func readOnlySnapshot(width: CGFloat, height: CGFloat) -> some View {
        let numberWidth = LauncherSpace.xxl

        return VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: LauncherSpace.md) {
                    Text("\(index + 1)")
                        .textStyle(.monoSmall, tone: .tertiary)
                        .frame(width: numberWidth, alignment: .trailing)
                    Text(attributedLine(line))
                        .font(LauncherTextStyle.monoSmall.font)
                        .tracking(LauncherTextStyle.monoSmall.tracking)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
    }

    /// 只读（交互）：竖向滚动 + 代码列横向滚动，行号列固定在左侧。
    private func readOnlyInteractive(width: CGFloat, height: CGFloat) -> some View {
        let numberWidth = LauncherSpace.xxl
        let codeWidth = max(1, width - numberWidth - LauncherSpace.md)

        return ScrollView(.vertical) {
            HStack(alignment: .top, spacing: LauncherSpace.md) {
                lineNumberColumn(width: numberWidth)

                ScrollView(.horizontal) {
                    codeRowColumn()
                }
                .frame(width: codeWidth)
                .scrollIndicators(.hidden)
            }
            .frame(width: width, alignment: .leading)
        }
        .frame(width: width, height: height)
        .scrollIndicators(.hidden)
    }

    /// 行号列：右对齐、等宽、与代码行共用同一行距。
    private func lineNumberColumn(width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: LauncherSpace.xxs) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                Text("\(index + 1)")
                    .textStyle(.monoSmall, tone: .tertiary)
                    .frame(width: width, alignment: .trailing)
            }
        }
    }

    /// 代码列：保留缩进，标签名用 textPrimary 轻度区分。
    private func codeRowColumn() -> some View {
        VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(highlightSegments(displayLine(line)).enumerated()), id: \.offset) { _, segment in
                        Text(verbatim: segment.text)
                            .textStyle(.monoSmall, tone: segment.isTag ? .primary : .secondary)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    // MARK: - 右侧预览面板

    /// 预览面板：标题 + 诊断 + 设计画布信息 + 缩放预览。
    private func previewPanel(sample: XMLSample, diagnostics: [XMLDiagnostic], width: CGFloat, height: CGFloat) -> some View {
        let contentWidth = max(0, width - 2 * LauncherSpace.md)
        let diagnosticsHeight = diagnosticsHeight(diagnostics)
        let childCount = diagnostics.isEmpty ? 3 : 4
        let spacings = LauncherSpace.sm * CGFloat(childCount - 1)
        let previewHeight = max(
            LauncherControl.large,
            height - 2 * LauncherSpace.md - LauncherControl.small - LauncherSpace.lg
                - diagnosticsHeight - spacings
        )
        let scale = min(1, contentWidth / Self.designCanvasWidth)
        let percent = Int((scale * 100).rounded())

        return GlassPanel(level: .regular, cornerRadius: LauncherRadius.lg, padding: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                HStack(spacing: LauncherSpace.sm) {
                    LauncherLabel("实时预览")
                    Text(sample.title).textStyle(.micro, tone: .tertiary)
                    Spacer(minLength: LauncherSpace.sm)
                    LauncherBadge(
                        diagnosticSummary(diagnostics),
                        tone: diagnosticTone(diagnostics),
                        systemImage: diagnosticIcon(diagnostics)
                    )
                }
                .frame(width: contentWidth, height: LauncherControl.small)

                HStack(spacing: LauncherSpace.xs) {
                    LauncherMonoText(
                        "设计画布 \(Int(Self.designCanvasWidth)) × auto · 当前 \(percent)%",
                        tone: .tertiary
                    )
                    Spacer(minLength: 0)
                    if isEditing {
                        Text("输入即重渲染").textStyle(.micro, tone: .tertiary)
                    }
                }
                .frame(width: contentWidth, height: LauncherSpace.lg)

                if diagnosticsHeight > 0 {
                    XMLDiagnosticsView(diagnostics: diagnostics)
                        .frame(width: contentWidth, height: diagnosticsHeight, alignment: .topLeading)
                        .clipped()
                }

                previewContent(sample: sample, width: contentWidth, height: previewHeight)
            }
        }
        .frame(width: width, height: height)
    }

    /// 缩放画布：内容先按 1180pt 设计宽度排版，再等比缩放到可用宽度。
    private func previewContent(sample: XMLSample, width: CGFloat, height: CGFloat) -> some View {
        let canvasWidth = Self.designCanvasWidth
        let scale = min(1, width / canvasWidth)
        let scaledWidth = canvasWidth * scale

        let rendered = LauncherXMLView(
            source: source,
            store: store,
            actions: demoActions,
            data: sample.data
        )
        .frame(width: canvasWidth, alignment: .topLeading)

        return Group {
            if snapshotMode {
                rendered
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: width, height: height, alignment: .topLeading)
                    .clipped()
            } else {
                ScrollView {
                    rendered
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: XMLPreviewContentHeightKey.self, value: proxy.size.height)
                            }
                        }
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(
                            width: scaledWidth,
                            height: max(0, canvasContentHeight * scale),
                            alignment: .topLeading
                        )
                        .onPreferenceChange(XMLPreviewContentHeightKey.self) { measured in
                            canvasContentHeight = measured
                        }
                }
                .frame(width: width, height: height)
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - 底部提示

    /// 底部一行：XML 文档入口与常用语法速查。
    private var footer: some View {
        HStack(spacing: LauncherSpace.sm) {
            Image(systemName: "book.closed")
                .textStyle(.caption, tone: .tertiary)
            Text("参考 docs/XML-UI.md：布局 vstack / hstack / grid，表达式 {state.x} / {item.x}，事件 onTap。")
                .textStyle(.micro, tone: .tertiary)
            Spacer(minLength: LauncherSpace.md)
            if isEditing {
                Text("编辑模式 · 每次输入都会重新解析并渲染")
                    .textStyle(.micro, tone: .warning)
            }
        }
    }

    // MARK: - 示例 / 状态

    /// 顶部示例切换的分段选项（id + 标题来自示例库）。
    private var sampleOptions: [LauncherSegment<String>] {
        XMLSampleLibrary.definitions.map { LauncherSegment(id: $0.id, title: $0.title) }
    }

    /// 示例切换绑定：切换时载入源码与初始状态。
    private var sampleBinding: Binding<String> {
        Binding(
            get: { sampleID },
            set: { newID in
                guard newID != sampleID else { return }
                switchSample(to: newID)
            }
        )
    }

    private var currentSample: XMLSample {
        XMLDesignerPage.samples.first { $0.id == sampleID }
            ?? XMLDesignerPage.samples.first
            ?? XMLDesignerPage.initialSample
    }

    private var currentFileName: String {
        let file = XMLSampleLibrary.definitions.first { $0.id == sampleID }?.file
        return "\(file ?? sampleID).xml"
    }

    /// 示例动作注册表（启动、切换主题、进度等演示动作）。
    private var demoActions: XMLActionRegistry {
        XMLActionRegistry.demo(themeManager: themeManager)
    }

    /// 解析 + 渲染诊断：先取文档结构错误，再取渲染期错误/警告。
    private var currentDiagnostics: [XMLDiagnostic] {
        let document = LauncherXMLDocument.parse(source)
        guard document.isValid, document.root != nil else {
            return document.diagnostics
        }
        return XMLRenderer()
            .render(
                document: document,
                store: store,
                actions: demoActions,
                data: currentSample.data,
                theme: theme
            )
            .diagnostics
    }

    /// 源码按行拆分（去掉 CRLF 的 \r）。
    private var lines: [String] {
        source
            .components(separatedBy: "\n")
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }

    /// 行内展示：空行占位、Tab 转 4 空格，保证等宽对齐。
    private func displayLine(_ line: String) -> String {
        let expanded = line.replacingOccurrences(of: "\t", with: "    ")
        return expanded.isEmpty ? " " : expanded
    }

    /// 一行代码的带色文本：标签名用主文字色，其余用次要色（离屏软换行用）。
    private func attributedLine(_ line: String) -> AttributedString {
        var result = AttributedString()
        for segment in highlightSegments(displayLine(line)) {
            var piece = AttributedString(segment.text)
            piece.foregroundColor = segment.isTag ? theme.colors.textPrimary : theme.colors.textSecondary
            result.append(piece)
        }
        return result
    }

    /// 一行代码分段：标签名用主文字色，其余用次要色（轻度语法区分）。
    private func highlightSegments(_ line: String) -> [(text: String, isTag: Bool)] {
        var segments: [(text: String, isTag: Bool)] = []
        var plain = ""
        var index = line.startIndex

        while index < line.endIndex {
            guard line[index] == "<" else {
                plain.append(line[index])
                index = line.index(after: index)
                continue
            }

            var cursor = line.index(after: index)
            var tag = "<"
            while cursor < line.endIndex {
                let character = line[cursor]
                guard character.isLetter || character.isNumber || character == "-" || character == "/"
                        || character == "!" || character == "?" || character == "_" else { break }
                tag.append(character)
                cursor = line.index(after: cursor)
            }

            if tag.count > 1 {
                if !plain.isEmpty {
                    segments.append((plain, false))
                    plain = ""
                }
                segments.append((tag, true))
                index = cursor
            } else {
                plain.append(line[index])
                index = line.index(after: index)
            }
        }

        if !plain.isEmpty { segments.append((plain, false)) }
        return segments.isEmpty ? [(line, false)] : segments
    }

    // MARK: - 诊断展示

    /// 诊断面板高度：无诊断时为 0，最多展示 5 条于固定高度内。
    private func diagnosticsHeight(_ diagnostics: [XMLDiagnostic]) -> CGFloat {
        diagnostics.isEmpty ? 0 : LauncherSpace.xxxl + LauncherSpace.xl * CGFloat(min(diagnostics.count, 5))
    }

    private func diagnosticSummary(_ diagnostics: [XMLDiagnostic]) -> String {
        diagnostics.isEmpty ? "无诊断" : "\(diagnostics.count) 条诊断"
    }

    private func diagnosticTone(_ diagnostics: [XMLDiagnostic]) -> LauncherBadgeTone {
        if diagnostics.contains(where: { $0.severity == .error }) { return .danger }
        if diagnostics.contains(where: { $0.severity == .warning }) { return .warning }
        return .success
    }

    private func diagnosticIcon(_ diagnostics: [XMLDiagnostic]) -> String {
        if diagnostics.contains(where: { $0.severity == .error }) { return "xmark.octagon.fill" }
        if diagnostics.contains(where: { $0.severity == .warning }) { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    // MARK: - 操作

    /// 切换示例：载入示例源码，并用 `<state>` 重建状态仓库。
    private func switchSample(to id: String) {
        guard let sample = XMLDesignerPage.samples.first(where: { $0.id == id }) else { return }
        sampleID = id
        source = sample.source
        store = XMLStateStore(values: LauncherXMLDocument.parse(source).initialValues)
        canvasContentHeight = 0
    }

    /// 重置：回到当前示例的原始源码与初始状态。
    private func resetSource() {
        let sample = currentSample
        source = sample.source
        store = XMLStateStore(values: LauncherXMLDocument.parse(source).initialValues)
        canvasContentHeight = 0
    }

    /// 在「编辑 XML / 完成编辑」之间切换。
    private func toggleEditing() {
        isEditing.toggle()
    }
}
