import SwiftUI

// MARK: - 布局容器

/// 注册布局类标签：vstack / hstack / zstack / scroll / grid / spacer，
/// 以及容器组件 panel / card / section / page。
@MainActor
func registerLayoutElements(in registry: XMLElementRegistry) {
    registry.register("vstack") { node, ctx in
        let spacing = node.spaceAttribute("spacing", ctx, default: LauncherSpace.sm)
        let alignment = XMLLayout.horizontalAlignment(node.string("align"))
        let views = ctx.buildChildren(node)
        return AnyView(
            VStack(alignment: alignment, spacing: spacing) {
                ForEach(Array(views.enumerated()), id: \.offset) { item in item.element }
            }
            .frame(maxWidth: XMLLayout.isFullWidth(node) ? .infinity : nil, alignment: alignment == .leading ? .leading : .center)
        )
    }

    registry.register("hstack") { node, ctx in
        let spacing = node.spaceAttribute("spacing", ctx, default: LauncherSpace.sm)
        let alignment = XMLLayout.verticalAlignment(node.string("align"))
        let views = ctx.buildChildren(node)
        return AnyView(
            HStack(alignment: alignment, spacing: spacing) {
                ForEach(Array(views.enumerated()), id: \.offset) { item in item.element }
            }
        )
    }

    registry.register("zstack") { node, ctx in
        let views = ctx.buildChildren(node)
        return AnyView(
            ZStack {
                ForEach(Array(views.enumerated()), id: \.offset) { item in item.element }
            }
        )
    }

    registry.register("scroll") { node, ctx in
        let spacing = node.spaceAttribute("spacing", ctx, default: LauncherSpace.md)
        let alignment = XMLLayout.horizontalAlignment(node.string("align"))
        let views = ctx.buildChildren(node)
        return AnyView(
            ScrollView {
                VStack(alignment: alignment, spacing: spacing) {
                    ForEach(Array(views.enumerated()), id: \.offset) { item in item.element }
                }
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
            }
            .scrollIndicators(.hidden)
        )
    }

    registry.register("grid") { node, ctx in
        let columns = max(1, node.intAttribute("columns", ctx, default: 2))
        let spacing = node.spaceAttribute("spacing", ctx, default: LauncherSpace.md)
        var cells: [AnyView] = []
        for child in node.children where child.name != "state" && child.name != "actions" {
            // 便捷写法：网格里直接放 foreach 时，把每个条目展开成一个格子
            if child.name == "foreach" {
                let listName = child.attribute("in") ?? ""
                let alias = child.attribute("as") ?? "item"
                let itemSpacing = child.spaceAttribute("item-spacing", ctx, default: LauncherSpace.xs)
                for item in ctx.data.lists[listName] ?? [] {
                    let itemCtx = ctx.withItem(item, alias: alias)
                    let views = child.children.map { ctx.build($0, itemCtx) }
                    cells.append(AnyView(
                        VStack(alignment: .leading, spacing: itemSpacing) {
                            ForEach(Array(views.enumerated()), id: \.offset) { cell in cell.element }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ))
                }
            } else {
                cells.append(ctx.build(child, ctx))
            }
        }
        let items = Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .leading), count: columns)
        return AnyView(
            LazyVGrid(columns: items, alignment: .leading, spacing: spacing) {
                ForEach(Array(cells.enumerated()), id: \.offset) { cell in cell.element }
            }
        )
    }

    registry.register("spacer") { node, ctx in
        let minLength = node.spaceAttribute("min-length", ctx, default: LauncherSpace.sm)
        return AnyView(Spacer(minLength: minLength))
    }

    // MARK: 容器组件

    registry.register("panel") { node, ctx in
        let level = GlassLevel.fromXML(node.string("level") ?? "regular")
        let radius = node.radiusAttribute("radius", ctx, default: LauncherRadius.lg)
        let spacing = node.spaceAttribute("spacing", ctx, default: LauncherSpace.md)
        let views = ctx.buildChildren(node)
        return AnyView(
            GlassPanel(level: level, cornerRadius: radius, padding: LauncherSpace.lg) {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(Array(views.enumerated()), id: \.offset) { item in item.element }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    registry.register("card") { node, ctx in
        let level = GlassLevel.fromXML(node.string("level") ?? "regular")
        let spacing = node.spaceAttribute("spacing", ctx, default: LauncherSpace.sm)
        let views = ctx.buildChildren(node)
        return AnyView(
            LauncherCard(level: level, padding: LauncherSpace.md) {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(Array(views.enumerated()), id: \.offset) { item in item.element }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    registry.register("section") { node, ctx in
        let spacing = node.spaceAttribute("spacing", ctx, default: LauncherSpace.md)
        let views = ctx.buildChildren(node)
        return AnyView(
            LauncherSection(node.required("title", ctx), subtitle: node.interpolated("subtitle", ctx)) {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(Array(views.enumerated()), id: \.offset) { item in item.element }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    registry.register("page") { node, ctx in
        let spacing = node.spaceAttribute("spacing", ctx, default: LauncherSpace.lg)
        let views = ctx.buildChildren(node)
        return AnyView(
            LauncherPageScaffold(title: node.required("title", ctx), subtitle: node.interpolated("subtitle", ctx)) {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(Array(views.enumerated()), id: \.offset) { item in item.element }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }
}

// MARK: - 布局工具扩展

public extension XMLLayout {
    static func horizontalAlignment(_ raw: String?) -> HorizontalAlignment {
        switch (raw ?? "leading").lowercased() {
        case "center": return .center
        case "trailing", "right": return .trailing
        default: return .leading
        }
    }

    static func verticalAlignment(_ raw: String?) -> VerticalAlignment {
        switch (raw ?? "center").lowercased() {
        case "top": return .top
        case "bottom": return .bottom
        default: return .center
        }
    }

    static func isFullWidth(_ node: XMLNode) -> Bool {
        guard let raw = node.attribute("full-width") else { return false }
        return ["true", "1", "yes"].contains(raw.lowercased())
    }
}
