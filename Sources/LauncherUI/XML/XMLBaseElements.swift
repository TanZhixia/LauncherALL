import SwiftUI

// MARK: - 基础元素

/// 注册基础标签：text / label / mono / icon / divider。
@MainActor
func registerBaseElements(in registry: XMLElementRegistry) {
    registry.register("text") { node, ctx in
        let style = LauncherTextStyle.fromXML(node.string("style") ?? "body")
        let tone = LauncherTextTone.fromXML(node.string("tone") ?? "primary")
        let content = node.interpolated("content", ctx) ?? node.interpolatedText(ctx) ?? ""
        let lineLimit = node.attribute("line-limit").flatMap(Int.init)
        var view: AnyView = AnyView(
            Text(content)
                .font(style.font)
                .tracking(style.tracking)
                .foregroundStyle(tone.color(in: ctx.theme))
                .multilineTextAlignment(.leading)
        )
        if let lineLimit {
            view = AnyView(view.lineLimit(lineLimit))
        }
        return view
    }

    registry.register("label") { node, ctx in
        let tone = LauncherTextTone.fromXML(node.string("tone") ?? "tertiary")
        let content = node.interpolated("content", ctx) ?? node.interpolatedText(ctx) ?? ""
        return AnyView(LauncherLabel(content, tone: tone))
    }

    registry.register("mono") { node, ctx in
        let tone = LauncherTextTone.fromXML(node.string("tone") ?? "secondary")
        let size = node.doubleAttribute("size", ctx, default: 12)
        let content = node.interpolated("content", ctx) ?? node.interpolatedText(ctx) ?? ""
        return AnyView(LauncherMonoText(content, tone: tone, size: size))
    }

    registry.register("icon") { node, ctx in
        let name = node.required("name", ctx)
        let size = node.doubleAttribute("size", ctx, default: 14)
        let tone = LauncherTextTone.fromXML(node.string("tone") ?? "secondary")
        return AnyView(
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tone.color(in: ctx.theme))
                .accessibilityLabel(node.string("label") ?? name)
        )
    }

    registry.register("divider") { node, ctx in
        let fullWidth = node.string("full-width") == "true"
        return AnyView(LauncherDivider().frame(maxWidth: fullWidth ? .infinity : nil))
    }
}
