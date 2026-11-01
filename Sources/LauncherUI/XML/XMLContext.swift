import SwiftUI

// MARK: - 元素构建器

/// 单个 XML 标签 -> SwiftUI 视图。所有构建器都在主线程执行。
public typealias XMLElementBuilder = @MainActor (XMLNode, XMLBuildContext) -> AnyView

/// 标签注册表：把 `<button>`、`<vstack>` 等标签映射到构建器。
@MainActor
public final class XMLElementRegistry {
    private var builders: [String: XMLElementBuilder] = [:]

    public init() {}

    public func register(_ tag: String, _ builder: @escaping XMLElementBuilder) {
        builders[tag] = builder
    }

    public func builder(for tag: String) -> XMLElementBuilder? {
        builders[tag]
    }

    public var registeredTags: [String] { builders.keys.sorted() }

    /// 全量注册（布局 + 基础 + 控件 + 容器类组件）。
    public static func makeDefault() -> XMLElementRegistry {
        let registry = XMLElementRegistry()
        registerLayoutElements(in: registry)
        registerBaseElements(in: registry)
        registerControlElements(in: registry)
        registerSurfaceElements(in: registry)
        return registry
    }

    /// 默认注册表（首次使用时装好）。
    public static let shared: XMLElementRegistry = makeDefault()
}

// MARK: - 构建上下文

/// 传给每个构建器的上下文：状态、动作、数据源、诊断，以及递归构建子节点的方法。
@MainActor
public struct XMLBuildContext {
    public let store: XMLStateStore
    public let actions: XMLActionRegistry
    public let data: XMLDataSources
    public let theme: LauncherTheme
    public let scope: XMLScope
    public let diagnostics: XMLDiagnosticsCollector
    public let build: (XMLNode, XMLBuildContext) -> AnyView

    public init(
        store: XMLStateStore,
        actions: XMLActionRegistry,
        data: XMLDataSources = .empty,
        theme: LauncherTheme,
        scope: XMLScope,
        diagnostics: XMLDiagnosticsCollector,
        build: @escaping (XMLNode, XMLBuildContext) -> AnyView
    ) {
        self.store = store
        self.actions = actions
        self.data = data
        self.theme = theme
        self.scope = scope
        self.diagnostics = diagnostics
        self.build = build
    }

    /// 派生到列表项作用域的上下文。
    public func withItem(_ item: XMLListItem, alias: String? = nil) -> XMLBuildContext {
        XMLBuildContext(
            store: store,
            actions: actions,
            data: data,
            theme: theme,
            scope: XMLScope(store: store, item: item, itemAlias: alias),
            diagnostics: diagnostics,
            build: build
        )
    }

    /// 构建单个子节点。
    public func buildChild(_ node: XMLNode) -> AnyView {
        build(node, self)
    }

    /// 构建一组子节点。
    public func buildChildren(_ node: XMLNode) -> [AnyView] {
        node.children
            .filter { $0.name != "state" && $0.name != "actions" }
            .map { build($0, self) }
    }

    /// 执行动作（若已注册），未注册时记一条警告。
    public func perform(_ actionName: String, item: XMLListItem? = nil) {
        guard actions.hasAction(actionName) else {
            diagnostics.warning("动作 \"\(actionName)\" 未注册", path: nil)
            return
        }
        actions.perform(actionName, context: XMLActionContext(store: store, item: item ?? scope.item, data: data))
    }
}

// MARK: - 属性读取工具

@MainActor
public extension XMLNode {
    /// 原始字符串属性。
    func string(_ key: String) -> String? {
        attributes[key]
    }

    /// 插值后的字符串属性。
    func interpolated(_ key: String, _ ctx: XMLBuildContext) -> String? {
        guard let raw = attributes[key] else { return nil }
        return ctx.scope.interpolate(raw)
    }

    /// 必填属性：缺失或为空时记错误并返回占位文案。
    func required(_ key: String, _ ctx: XMLBuildContext) -> String {
        guard let value = interpolated(key, ctx), !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            ctx.diagnostics.error("缺少必填属性 `\(key)`", path: path)
            return "（缺失 \(key)）"
        }
        return value
    }

    /// 节点文本（插值后）。
    func interpolatedText(_ ctx: XMLBuildContext) -> String? {
        guard let text else { return nil }
        return ctx.scope.interpolate(text)
    }

    func boolAttribute(_ key: String, _ ctx: XMLBuildContext, default fallback: Bool = false) -> Bool {
        guard let raw = attributes[key] else { return fallback }
        return ctx.scope.bool(for: raw)
    }

    func intAttribute(_ key: String, _ ctx: XMLBuildContext, default fallback: Int) -> Int {
        guard let raw = interpolated(key, ctx), let value = Int(raw) else { return fallback }
        return value
    }

    func doubleAttribute(_ key: String, _ ctx: XMLBuildContext, default fallback: Double) -> Double {
        guard let raw = interpolated(key, ctx), let value = Double(raw) else { return fallback }
        return value
    }

    /// 枚举属性：大小写不敏感，非法值记警告并回退默认值。
    func enumAttribute<T>(
        _ key: String,
        _ ctx: XMLBuildContext,
        default fallback: T
    ) -> T where T: RawRepresentable, T: CaseIterable, T.RawValue == String {
        guard let raw = attributes[key] else { return fallback }
        let lowered = raw.lowercased()
        for candidate in T.allCases where candidate.rawValue.lowercased() == lowered {
            return candidate
        }
        ctx.diagnostics.warning("未知取值 `\(raw)`，回退为 `\(fallback.rawValue)`", path: path)
        return fallback
    }

    /// 间距类属性：支持令牌名（xs/sm/md/lg/xl/xxl）或数字。
    func spaceAttribute(_ key: String, _ ctx: XMLBuildContext, default fallback: CGFloat) -> CGFloat {
        guard let raw = interpolated(key, ctx) else { return fallback }
        return XMLLayout.space(from: raw) ?? fallback
    }

    /// 圆角属性：支持令牌名（sm/md/lg/xl/pill）或数字。
    func radiusAttribute(_ key: String, _ ctx: XMLBuildContext, default fallback: CGFloat) -> CGFloat {
        guard let raw = interpolated(key, ctx) else { return fallback }
        return XMLLayout.radius(from: raw) ?? fallback
    }
}

// MARK: - 布局工具

public enum XMLLayout {
    public static func space(from raw: String) -> CGFloat? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "xxs": return LauncherSpace.xxs
        case "xs": return LauncherSpace.xs
        case "sm": return LauncherSpace.sm
        case "md": return LauncherSpace.md
        case "lg": return LauncherSpace.lg
        case "xl": return LauncherSpace.xl
        case "xxl": return LauncherSpace.xxl
        case "xxxl": return LauncherSpace.xxxl
        default: return Double(raw).map { CGFloat($0) }
        }
    }

    public static func radius(from raw: String) -> CGFloat? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "sm": return LauncherRadius.sm
        case "md": return LauncherRadius.md
        case "lg": return LauncherRadius.lg
        case "xl": return LauncherRadius.xl
        case "xxl": return LauncherRadius.xxl
        case "pill": return LauncherRadius.pill
        default: return Double(raw).map { CGFloat($0) }
        }
    }

    /// 通用布局修饰：padding / width / height / max-width / min-height。
    public static func apply(_ view: AnyView, node: XMLNode, ctx: XMLBuildContext) -> AnyView {
        // 这些标签的 width / height 由标签自身消费，通用层不再套 frame，避免尺寸被压扁
        let selfSizing: Set<String> = ["progress", "skeleton"]
        let skipSize = selfSizing.contains(node.name)
        var result = view
        if let padding = node.attribute("padding") {
            let value = space(from: padding) ?? 0
            result = AnyView(result.padding(value))
        }
        if !skipSize, let width = node.attribute("width"), let value = Double(width) {
            result = AnyView(result.frame(width: CGFloat(value)))
        }
        if let maxWidth = node.attribute("max-width"), let value = Double(maxWidth) {
            result = AnyView(result.frame(maxWidth: CGFloat(value)))
        }
        if !skipSize, let height = node.attribute("height"), let value = Double(height) {
            result = AnyView(result.frame(height: CGFloat(value)))
        }
        if let minHeight = node.attribute("min-height"), let value = Double(minHeight) {
            result = AnyView(result.frame(minHeight: CGFloat(value)))
        }
        if let opacity = node.attribute("opacity"), let value = Double(opacity) {
            result = AnyView(result.opacity(value))
        }
        return result
    }
}
