import SwiftUI

// MARK: - 容器 / 反馈 / 导航类标签

/// 容器 / 反馈 / 导航类标签注册（listrow / progress / banner / tabs / dialog 等）。
/// 所有颜色与尺寸均来自设计系统 / 主题，XML 只负责结构、文案与状态绑定。
@MainActor
func registerSurfaceElements(in registry: XMLElementRegistry) {
    // MARK: 列表行

    /// `<listrow>`：title（必填）· subtitle · icon · badge · selected · onTap
    registry.register("listrow") { node, ctx in
        AnyView(
            LauncherListRow(
                title: node.required("title", ctx),
                subtitle: node.interpolated("subtitle", ctx),
                systemImage: node.interpolated("icon", ctx),
                badge: node.interpolated("badge", ctx),
                // 契约里 listrow 没有附件槽位，固定传 nil。
                accessory: nil,
                isSelected: node.boolAttribute("selected", ctx),
                action: node.tapHandler(ctx)
            )
        )
    }

    // MARK: 区块标题

    /// `<sectionheader>`：title（必填）· subtitle
    registry.register("sectionheader") { node, ctx in
        AnyView(
            LauncherSectionHeader(
                title: node.required("title", ctx),
                subtitle: node.interpolated("subtitle", ctx),
                accessory: nil
            )
        )
    }

    // MARK: 空状态

    /// `<empty>`：icon（默认 tray）· title（必填）· message · action-title · onTap
    registry.register("empty") { node, ctx in
        AnyView(
            LauncherEmptyState(
                systemImage: node.interpolated("icon", ctx) ?? "tray",
                title: node.required("title", ctx),
                message: node.interpolated("message", ctx) ?? "",
                actionTitle: node.interpolated("action-title", ctx),
                onAction: node.tapHandler(ctx)
            )
        )
    }

    // MARK: 头像

    /// `<avatar>`：name（首字回退，可空）· icon · size（默认 32）· online
    registry.register("avatar") { node, ctx in
        AnyView(
            LauncherAvatar(
                name: node.interpolated("name", ctx) ?? "",
                systemImage: node.interpolated("icon", ctx),
                size: CGFloat(node.doubleAttribute("size", ctx, default: 32)),
                isOnline: node.boolAttribute("online", ctx)
            )
        )
    }

    // MARK: 键值行

    /// `<keyvalue>`：key（必填）· value（必填）· mono（默认 true）
    registry.register("keyvalue") { node, ctx in
        AnyView(
            LauncherKeyValueRow(
                key: node.required("key", ctx),
                value: node.required("value", ctx),
                isMono: node.boolAttribute("mono", ctx, default: true)
            )
        )
    }

    // MARK: 统计磁贴

    /// `<stattile>`：value（必填）· label（必填）· icon
    registry.register("stattile") { node, ctx in
        AnyView(
            LauncherStatTile(
                value: node.required("value", ctx),
                label: node.required("label", ctx),
                systemImage: node.interpolated("icon", ctx)
            )
        )
    }

    // MARK: 进度条

    /// `<progress>`：value（省略 = 不确定态）· max（默认 100）· label · tone · height（默认 6）
    registry.register("progress") { node, ctx in
        let tone = LauncherProgressTone.fromXML(node.string("tone") ?? "accent")
        let maxValue = node.doubleAttribute("max", ctx, default: 100)
        let height = CGFloat(node.doubleAttribute("height", ctx, default: 6))
        let label = node.interpolated("label", ctx)

        // 组件入参是 0...1 的归一化值，这里把 value / max 折算后传入；缺省 value 走不确定态。
        var normalized: Double?
        if let raw = node.interpolated("value", ctx), !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            if let parsed = Double(raw) {
                if maxValue > 0 {
                    normalized = parsed / maxValue
                } else {
                    ctx.diagnostics.warning("`max` 必须大于 0，已回退为 100", path: node.path)
                    normalized = parsed / 100
                }
            } else {
                ctx.diagnostics.warning("`value` 不是数字（\(raw)），按不确定态渲染", path: node.path)
            }
        }

        return AnyView(
            LauncherProgressBar(value: normalized, label: label, tone: tone, height: height)
        )
    }

    // MARK: 加载指示器

    /// `<spinner>`：size（默认 16）· tone
    registry.register("spinner") { node, ctx in
        AnyView(
            LauncherSpinner(
                size: CGFloat(node.doubleAttribute("size", ctx, default: 16)),
                tone: LauncherProgressTone.fromXML(node.string("tone") ?? "accent")
            )
        )
    }

    // MARK: 骨架占位

    /// `<skeleton>`：width（省略 = 撑满）· height（默认 12）· radius（默认 sm）
    registry.register("skeleton") { node, ctx in
        // width 用可选值：不写时让占位条撑满父容器宽度。
        let width = node.interpolated("width", ctx).flatMap(Double.init).map { CGFloat($0) }
        return AnyView(
            LauncherSkeleton(
                width: width,
                height: CGFloat(node.doubleAttribute("height", ctx, default: 12)),
                cornerRadius: node.radiusAttribute("radius", ctx, default: LauncherRadius.sm)
            )
        )
    }

    // MARK: 提示条

    /// `<banner>`：title（必填）· message · tone（info/success/warning/danger）· action-title · onTap
    registry.register("banner") { node, ctx in
        AnyView(
            LauncherBanner(
                title: node.required("title", ctx),
                message: node.interpolated("message", ctx) ?? "",
                tone: LauncherBannerTone.fromXML(node.string("tone") ?? "info"),
                actionTitle: node.interpolated("action-title", ctx),
                onAction: node.tapHandler(ctx)
            )
        )
    }

    // MARK: 浮层轻提示

    /// `<toast>`：title（必填）· message · tone（info/success/warning/danger）· onClose
    registry.register("toast") { node, ctx in
        AnyView(
            LauncherToast(
                title: node.required("title", ctx),
                message: node.interpolated("message", ctx) ?? "",
                tone: LauncherBannerTone.fromXML(node.string("tone") ?? "info"),
                onDismiss: actionHandler(node, "onClose", ctx)
            )
        )
    }

    // MARK: 侧栏导航项

    /// `<sidebaritem>`：title（必填）· icon（默认 circle）· badge · selected · onTap
    registry.register("sidebaritem") { node, ctx in
        // 组件需要完整导航项数据模型：id 用节点路径保证唯一，便于选中态比较。
        let item = LauncherNavItem(
            id: node.path,
            title: node.required("title", ctx),
            systemImage: node.interpolated("icon", ctx) ?? "circle",
            badge: node.interpolated("badge", ctx)
        )
        return AnyView(
            LauncherSidebarItem(
                item,
                isSelected: node.boolAttribute("selected", ctx),
                action: node.tapHandler(ctx) ?? {}
            )
        )
    }

    // MARK: 标签栏

    /// `<tabs>`：bind（必填，绑定字符串状态）+ 子标签 `<option value title icon/>`
    registry.register("tabs") { node, ctx in
        var tabs: [LauncherTabBar.Tab] = []
        for child in node.children where child.name == "option" {
            let title = child.required("title", ctx)
            var id = child.interpolated("value", ctx)
            if id == nil {
                ctx.diagnostics.warning("`<option>` 缺少 value，已回退为 title", path: child.path)
                id = title
            }
            tabs.append(
                LauncherTabBar.Tab(
                    id: id ?? title,
                    title: title,
                    systemImage: child.interpolated("icon", ctx)
                )
            )
        }
        if tabs.isEmpty {
            ctx.diagnostics.warning("`<tabs>` 至少需要一个 `<option>` 子标签", path: node.path)
        }

        // 选中值双向绑定到状态变量；缺失 bind 时降级为常量绑定，避免运行时崩溃。
        let bindName = node.bindName(ctx)
        if bindName == nil {
            ctx.diagnostics.error("缺少必填属性 `bind`", path: node.path)
        }
        let selection: Binding<String> = bindName.map { ctx.store.bindingString($0) }
            ?? .constant(tabs.first?.id ?? "")
        return AnyView(LauncherTabBar(tabs: tabs, selection: selection))
    }

    // MARK: 对话框

    /// `<dialog>`：title（必填）· message · primary（必填，主按钮文案）· secondary ·
    /// tone（primary/danger）· onPrimary · onSecondary
    registry.register("dialog") { node, ctx in
        // 动作在构建期校验：主按钮文案必填但没有动作 = 死按钮，记一条警告。
        let primaryName = node.interpolated("onPrimary", ctx)
        if primaryName == nil {
            ctx.diagnostics.warning("`<dialog>` 缺少 onPrimary，主按钮无动作", path: node.path)
        }
        let onPrimary: () -> Void = primaryName.map { name in
            { ctx.runTap(name, path: node.path) }
        } ?? {}

        // 次要按钮：没有动作时组件不会渲染，这里提示文案与动作不一致。
        let secondaryTitle = node.interpolated("secondary", ctx)
        let secondaryName = node.interpolated("onSecondary", ctx)
        if secondaryTitle != nil, secondaryName == nil {
            ctx.diagnostics.warning("`<dialog>` 有 secondary 文案但缺少 onSecondary，次要按钮不会渲染", path: node.path)
        }
        let onSecondary: (() -> Void)? = secondaryName.map { name in
            { ctx.runTap(name, path: node.path) }
        }

        return AnyView(
            LauncherDialog(
                title: node.required("title", ctx),
                message: node.interpolated("message", ctx) ?? "",
                primaryTitle: node.required("primary", ctx),
                secondaryTitle: secondaryTitle,
                tone: dialogTone(node, ctx),
                onPrimary: onPrimary,
                onSecondary: onSecondary
            )
        )
    }
}

// MARK: - 内部工具

/// 读取任意属性名的动作（如 `onClose`），语义与 `onTap` 一致，支持 `set:` / `toggle:` / `inc:` 简写。
@MainActor
private func actionHandler(_ node: XMLNode, _ key: String, _ ctx: XMLBuildContext) -> (() -> Void)? {
    guard let raw = node.attribute(key), !raw.isEmpty else { return nil }
    let expression = ctx.scope.interpolate(raw)
    return { ctx.runTap(expression, path: node.path) }
}

/// `<dialog tone="primary|danger">` 映射；非法值记警告并回退 primary。
@MainActor
private func dialogTone(_ node: XMLNode, _ ctx: XMLBuildContext) -> LauncherDialog.Tone {
    guard let raw = node.string("tone") else { return .primary }
    switch raw.lowercased() {
    case "primary", "default":
        return .primary
    case "danger", "destructive":
        return .danger
    default:
        ctx.diagnostics.warning("未知取值 `\(raw)`，回退为 `primary`", path: node.path)
        return .primary
    }
}
