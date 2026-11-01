import Foundation

/// 动作回调上下文：动作可以读写状态、读取当前列表项字段。
public struct XMLActionContext {
    public let store: XMLStateStore
    public let item: XMLListItem?
    public let data: XMLDataSources

    public init(store: XMLStateStore, item: XMLListItem? = nil, data: XMLDataSources = .empty) {
        self.store = store
        self.item = item
        self.data = data
    }

    public func set(_ name: String, _ value: XMLValue) { store.set(name, value) }
    public func string(_ name: String) -> String { store.string(name) }
    public func bool(_ name: String) -> Bool { store.bool(name) }
    public func int(_ name: String) -> Int { store.int(name) }
    public func double(_ name: String) -> Double { store.double(name) }
}

/// 动作注册表：XML 里写 `onTap="launch"`，宿主代码注册同名闭包。
public final class XMLActionRegistry {
    public typealias Handler = (XMLActionContext) -> Void

    private var handlers: [String: Handler] = [:]

    public init() {}

    public func register(_ name: String, _ handler: @escaping Handler) {
        handlers[name] = handler
    }

    public func perform(_ name: String, context: XMLActionContext) {
        handlers[name]?(context)
    }

    public func hasAction(_ name: String) -> Bool { handlers[name] != nil }

    public var actionNames: [String] { handlers.keys.sorted() }

    /// 示例动作：启动、切换主题、关闭启动器。
    public static func demo(themeManager: LauncherThemeManager?) -> XMLActionRegistry {
        let registry = XMLActionRegistry()
        registry.register("launch") { context in
            context.set("isLaunching", .bool(true))
            let name = context.string("instanceName")
            context.set("launchStatus", .string("正在启动 \(name)…"))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                context.set("isLaunching", .bool(false))
                context.set("launchStatus", .string("已在运行 · 上次启动 0 分钟前"))
            }
        }
        registry.register("stop") { context in
            context.set("isLaunching", .bool(false))
            context.set("launchStatus", .string("已停止"))
        }
        registry.register("toggleTheme") { _ in
            Task { @MainActor in
                themeManager?.next()
            }
        }
        registry.register("toggleAdvanced") { context in
            let current = context.bool("showAdvanced")
            context.set("showAdvanced", .bool(!current))
        }
        registry.register("showToast") { context in
            context.set("showToast", .bool(true))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                context.set("showToast", .bool(false))
            }
        }
        registry.register("install") { context in
            let current = context.int("progress")
            context.set("progress", .int(min(100, current + 25)))
        }
        return registry
    }
}
