import SwiftUI

/// 渲染结果：视图 + 诊断 + 运行时状态。
@MainActor
public struct XMLRenderOutput {
    public let view: AnyView
    public let diagnostics: [XMLDiagnostic]
    public let store: XMLStateStore
}

/// XML -> SwiftUI 渲染器：分发标签、处理 if / foreach，并收集诊断。
@MainActor
public final class XMLRenderer {
    private let registry: XMLElementRegistry

    public init(registry: XMLElementRegistry = .shared) {
        self.registry = registry
    }

    public func render(
        document: LauncherXMLDocument,
        store: XMLStateStore? = nil,
        actions: XMLActionRegistry,
        data: XMLDataSources = .empty,
        theme: LauncherTheme
    ) -> XMLRenderOutput {
        let collector = XMLDiagnosticsCollector()
        let resolvedStore = store ?? document.makeStore()

        guard document.isValid, let root = document.root else {
            return XMLRenderOutput(
                view: AnyView(XMLDiagnosticsView(diagnostics: document.diagnostics)),
                diagnostics: document.diagnostics,
                store: resolvedStore
            )
        }

        let context = XMLBuildContext(
            store: resolvedStore,
            actions: actions,
            data: data,
            theme: theme,
            scope: XMLScope(store: resolvedStore),
            diagnostics: collector,
            build: { node, ctx in self.build(node, ctx) }
        )

        let children = root.children.filter { $0.name != "state" && $0.name != "actions" }
        let views = children.map { build($0, context) }
        let content = VStack(alignment: .leading, spacing: LauncherSpace.lg) {
            ForEach(Array(views.enumerated()), id: \.offset) { item in
                item.element
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        let diagnostics = document.diagnostics + collector.items
        let hasErrors = diagnostics.contains { $0.severity == .error }
        let view = hasErrors
            ? AnyView(
                VStack(alignment: .leading, spacing: LauncherSpace.md) {
                    XMLDiagnosticsView(diagnostics: diagnostics)
                    content
                }
            )
            : AnyView(content)

        return XMLRenderOutput(view: view, diagnostics: diagnostics, store: resolvedStore)
    }

    // MARK: - 分发

    func build(_ node: XMLNode, _ ctx: XMLBuildContext) -> AnyView {
        if node.name == "state" || node.name == "actions" {
            return AnyView(EmptyView())
        }
        if let condition = node.attribute("if"), !ctx.scope.bool(for: condition) {
            return AnyView(EmptyView())
        }
        switch node.name {
        case "if":
            return buildIf(node, ctx)
        case "foreach":
            return buildForeach(node, ctx)
        default:
            guard let builder = registry.builder(for: node.name) else {
                ctx.diagnostics.error("未知元素 <\(node.name)>", path: node.path)
                return AnyView(XMLUnknownElementView(tag: node.name))
            }
            let view = builder(node, ctx)
            return XMLLayout.apply(view, node: node, ctx: ctx)
        }
    }

    /// `<if test="{state.flag}"> … </if>`
    private func buildIf(_ node: XMLNode, _ ctx: XMLBuildContext) -> AnyView {
        guard let test = node.attribute("test") else {
            ctx.diagnostics.error("`<if>` 缺少 test 属性", path: node.path)
            return AnyView(EmptyView())
        }
        guard ctx.scope.bool(for: test) else { return AnyView(EmptyView()) }
        let views = ctx.buildChildren(node)
        return AnyView(
            VStack(alignment: .leading, spacing: LauncherSpace.sm) {
                ForEach(Array(views.enumerated()), id: \.offset) { item in item.element }
            }
        )
    }

    /// `<foreach in="instances" as="inst" layout="vstack" spacing="sm"> … </foreach>`
    private func buildForeach(_ node: XMLNode, _ ctx: XMLBuildContext) -> AnyView {
        guard let listName = node.attribute("in") else {
            ctx.diagnostics.error("`<foreach>` 缺少 in 属性", path: node.path)
            return AnyView(EmptyView())
        }
        guard let items = ctx.data.lists[listName] else {
            ctx.diagnostics.warning("数据源 \"\(listName)\" 不存在", path: node.path)
            return AnyView(EmptyView())
        }
        let spacing = node.spaceAttribute("spacing", ctx, default: LauncherSpace.sm)
        let itemSpacing = node.spaceAttribute("item-spacing", ctx, default: LauncherSpace.xs)
        let isHorizontal = (node.attribute("layout") ?? "vstack").lowercased() == "hstack"
        let alias = node.attribute("as") ?? "item"

        let groups: [AnyView] = items.map { item in
            let itemCtx = ctx.withItem(item, alias: alias)
            let children = node.children.map { self.build($0, itemCtx) }
            return AnyView(
                VStack(alignment: .leading, spacing: itemSpacing) {
                    ForEach(Array(children.enumerated()), id: \.offset) { child in child.element }
                }
            )
        }

        if isHorizontal {
            return AnyView(
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { group in group.element }
                }
            )
        }
        return AnyView(
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(groups.enumerated()), id: \.offset) { group in group.element }
            }
        )
    }
}
