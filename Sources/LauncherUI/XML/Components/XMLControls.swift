import SwiftUI

// MARK: - 控件标签公共工具

/// 控件绑定键：优先 `bind`，缺省时用节点路径作为稳定键，保证同一文档里多个无 bind 控件互不覆盖。
@MainActor
private func controlBindKey(_ node: XMLNode, _ ctx: XMLBuildContext) -> String {
    node.bindName(ctx) ?? node.path
}

/// `onSubmit` 动作：按动作名调用宿主注册的闭包；未注册时由 `perform` 记一条警告。
@MainActor
private func controlSubmitHandler(_ node: XMLNode, _ ctx: XMLBuildContext) -> (() -> Void)? {
    guard let raw = node.interpolated("onSubmit", ctx),
          !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return { ctx.perform(raw) }
}

/// 解析 `<option value title icon/>` 子标签为分段 / 下拉选项；value 必填，title 缺省回退 value。
@MainActor
private func controlSegments(_ node: XMLNode, _ ctx: XMLBuildContext) -> [LauncherSegment<String>] {
    node.children
        .filter { $0.name == "option" }
        .map { option in
            let value = option.required("value", ctx)
            let title = option.interpolated("title", ctx) ?? value
            let icon = option.interpolated("icon", ctx)
            return LauncherSegment(id: value, title: title, systemImage: icon)
        }
}

/// `<segmented>` 的绑定：state 未声明、值为空或不在选项内时回退首项，避免"无选中"空态。
@MainActor
private func controlSelectionBinding(
    store: XMLStateStore,
    key: String,
    options: [LauncherSegment<String>]
) -> Binding<String> {
    let fallback = options.first?.id ?? ""
    return Binding(
        get: {
            let current = store.string(key, default: fallback)
            return options.contains { $0.id == current } ? current : fallback
        },
        set: { store.set(key, .string($0)) }
    )
}

/// 闭区间回退：`min` 大于 `max` 时记警告并返回默认区间，保证控件不会因非法区间崩溃。
@MainActor
private func controlRange<T: Comparable>(
    _ lower: T,
    _ upper: T,
    fallback: ClosedRange<T>,
    node: XMLNode,
    ctx: XMLBuildContext
) -> ClosedRange<T> {
    guard lower <= upper else {
        ctx.diagnostics.warning(
            "`min` 大于 `max`，已回退为 \(fallback.lowerBound)...\(fallback.upperBound)",
            path: node.path
        )
        return fallback
    }
    return lower...upper
}

// MARK: - 控件标签注册

/// 控件类标签注册（契约 docs/XML-UI.md 第 7 节）。
///
/// 16 个标签：button / iconbutton / chip / badge / statusdot / textfield / searchfield /
/// securefield / textarea / toggle / checkbox / radiocard / slider / stepper / segmented / dropdown。
@MainActor
func registerControlElements(in registry: XMLElementRegistry) {

    // MARK: 按钮

    /// `<button>`：`title`（必填）`icon` `variant` `size` `loading` `disabled` `full-width` `shortcut` `onTap`。
    registry.register("button") { node, ctx in
        let title = node.required("title", ctx)
        let tap = node.tapHandler(ctx)
        return AnyView(
            LauncherButton(
                title,
                systemImage: node.interpolated("icon", ctx),
                variant: LauncherButtonVariant.fromXML(node.interpolated("variant", ctx) ?? "primary"),
                size: LauncherButtonSize.fromXML(node.interpolated("size", ctx) ?? "medium"),
                isLoading: node.boolAttribute("loading", ctx, default: false),
                isFullWidth: node.boolAttribute("full-width", ctx, default: false),
                isDisabled: node.boolAttribute("disabled", ctx, default: false),
                shortcut: node.interpolated("shortcut", ctx),
                action: { tap?() }
            )
        )
    }

    /// `<iconbutton>`：`icon`（必填）`variant`（默认 ghost）`size` `label`（无障碍标签，缺省用 icon）`onTap`。
    registry.register("iconbutton") { node, ctx in
        let icon = node.required("icon", ctx)
        let tap = node.tapHandler(ctx)
        return AnyView(
            LauncherIconButton(
                systemImage: icon,
                variant: LauncherButtonVariant.fromXML(node.interpolated("variant", ctx) ?? "ghost"),
                size: LauncherButtonSize.fromXML(node.interpolated("size", ctx) ?? "medium"),
                accessibilityLabel: node.interpolated("label", ctx) ?? icon,
                action: { tap?() }
            )
        )
    }

    // MARK: 标签 / 状态

    /// `<chip>`：`title`（必填）`selected` `icon` `onTap`。
    registry.register("chip") { node, ctx in
        let title = node.required("title", ctx)
        let tap = node.tapHandler(ctx)
        return AnyView(
            LauncherChip(
                title,
                isSelected: node.boolAttribute("selected", ctx, default: false),
                systemImage: node.interpolated("icon", ctx),
                action: { tap?() }
            )
        )
    }

    /// `<badge>`：`text`（必填）`tone="neutral|accent|success|warning|danger|info"` `icon`。
    registry.register("badge") { node, ctx in
        let text = node.required("text", ctx)
        return AnyView(
            LauncherBadge(
                text,
                tone: LauncherBadgeTone.fromXML(node.interpolated("tone", ctx) ?? "neutral"),
                systemImage: node.interpolated("icon", ctx)
            )
        )
    }

    /// `<statusdot>`：`tone`（默认 success）`pulsing`。
    registry.register("statusdot") { node, ctx in
        return AnyView(
            LauncherStatusDot(
                tone: LauncherBadgeTone.fromXML(node.interpolated("tone", ctx) ?? "success"),
                isPulsing: node.boolAttribute("pulsing", ctx, default: false)
            )
        )
    }

    // MARK: 输入

    /// `<textfield>`：`placeholder` `bind` `icon` `helper` `error` `disabled` `onSubmit`。
    registry.register("textfield") { node, ctx in
        let bind = controlBindKey(node, ctx)
        return AnyView(
            LauncherTextField(
                node.interpolated("placeholder", ctx) ?? "",
                text: ctx.store.bindingString(bind),
                systemImage: node.interpolated("icon", ctx),
                helper: node.interpolated("helper", ctx),
                error: node.interpolated("error", ctx),
                isDisabled: node.boolAttribute("disabled", ctx, default: false),
                onSubmit: controlSubmitHandler(node, ctx)
            )
        )
    }

    /// `<searchfield>`：`bind` `placeholder` `onSubmit`。
    registry.register("searchfield") { node, ctx in
        let bind = controlBindKey(node, ctx)
        let placeholder = node.interpolated("placeholder", ctx) ?? "搜索版本、整合包或服务器"
        return AnyView(
            LauncherSearchField(
                text: ctx.store.bindingString(bind),
                placeholder: placeholder,
                onSubmit: controlSubmitHandler(node, ctx)
            )
        )
    }

    /// `<securefield>`：`placeholder` `bind` `icon`。
    registry.register("securefield") { node, ctx in
        let bind = controlBindKey(node, ctx)
        return AnyView(
            LauncherSecureField(
                node.interpolated("placeholder", ctx) ?? "",
                text: ctx.store.bindingString(bind),
                systemImage: node.interpolated("icon", ctx)
            )
        )
    }

    /// `<textarea>`：`placeholder` `bind` `min-height`（默认 90，支持间距令牌）。
    registry.register("textarea") { node, ctx in
        let bind = controlBindKey(node, ctx)
        return AnyView(
            LauncherTextArea(
                node.interpolated("placeholder", ctx) ?? "",
                text: ctx.store.bindingString(bind),
                minHeight: node.spaceAttribute("min-height", ctx, default: 90)
            )
        )
    }

    // MARK: 选择

    /// `<toggle>`：`title`（必填）`bind` `subtitle`。
    registry.register("toggle") { node, ctx in
        let title = node.required("title", ctx)
        let bind = controlBindKey(node, ctx)
        return AnyView(
            LauncherToggle(
                title,
                isOn: ctx.store.bindingBool(bind),
                subtitle: node.interpolated("subtitle", ctx)
            )
        )
    }

    /// `<checkbox>`：`title`（必填）`bind`。
    registry.register("checkbox") { node, ctx in
        let title = node.required("title", ctx)
        let bind = controlBindKey(node, ctx)
        return AnyView(
            LauncherCheckbox(title, isOn: ctx.store.bindingBool(bind))
        )
    }

    /// `<radiocard>`：`title`（必填）`subtitle` `icon` `selected` `onTap`。
    registry.register("radiocard") { node, ctx in
        let title = node.required("title", ctx)
        let tap = node.tapHandler(ctx)
        return AnyView(
            LauncherRadioCard(
                title,
                subtitle: node.interpolated("subtitle", ctx),
                systemImage: node.interpolated("icon", ctx),
                isSelected: node.boolAttribute("selected", ctx, default: false),
                action: { tap?() }
            )
        )
    }

    /// `<slider>`：`bind` `min`（默认 0）`max`（默认 1）`label` `value-text`。
    registry.register("slider") { node, ctx in
        let bind = controlBindKey(node, ctx)
        let range = controlRange(
            node.doubleAttribute("min", ctx, default: 0),
            node.doubleAttribute("max", ctx, default: 1),
            fallback: 0...1,
            node: node,
            ctx: ctx
        )
        return AnyView(
            LauncherSlider(
                value: ctx.store.bindingDouble(bind),
                range: range,
                label: node.interpolated("label", ctx),
                valueText: node.interpolated("value-text", ctx)
            )
        )
    }

    /// `<stepper>`：`bind` `min`（默认 1）`max`（默认 64）`label` `unit`。
    registry.register("stepper") { node, ctx in
        let bind = controlBindKey(node, ctx)
        let range = controlRange(
            node.intAttribute("min", ctx, default: 1),
            node.intAttribute("max", ctx, default: 64),
            fallback: 1...64,
            node: node,
            ctx: ctx
        )
        return AnyView(
            LauncherStepper(
                value: ctx.store.bindingInt(bind),
                range: range,
                label: node.interpolated("label", ctx),
                unit: node.interpolated("unit", ctx)
            )
        )
    }

    // MARK: 分段 / 下拉

    /// `<segmented>`：`bind` + 子标签 `<option value title icon/>`（至少一个，否则记错误）。
    registry.register("segmented") { node, ctx in
        let options = controlSegments(node, ctx)
        guard !options.isEmpty else {
            ctx.diagnostics.error("<segmented> 至少需要一个 <option> 子标签", path: node.path)
            return AnyView(EmptyView())
        }
        let selection = controlSelectionBinding(
            store: ctx.store,
            key: controlBindKey(node, ctx),
            options: options
        )
        return AnyView(LauncherSegmentedControl(options: options, selection: selection))
    }

    /// `<dropdown>`：`bind` `placeholder`（默认「请选择」）+ 子标签 `<option value title icon/>`（至少一个）。
    /// 绑定保留原始值（不回退首项），未匹配到选项时由组件显示 placeholder。
    registry.register("dropdown") { node, ctx in
        let options = controlSegments(node, ctx)
        guard !options.isEmpty else {
            ctx.diagnostics.error("<dropdown> 至少需要一个 <option> 子标签", path: node.path)
            return AnyView(EmptyView())
        }
        let bind = controlBindKey(node, ctx)
        return AnyView(
            LauncherDropdown(
                options: options,
                selection: ctx.store.bindingString(bind),
                placeholder: node.interpolated("placeholder", ctx) ?? "请选择"
            )
        )
    }
}
