import SwiftUI

// MARK: - onTap 动作：支持 `动作名` 与内置简写

/// 支持的写法：
/// - `onTap="launch"`              调用宿主注册的动作
/// - `onTap="set:theme=dark"`      设置状态
/// - `onTap="toggle:showAdvanced"` 切换布尔状态
/// - `onTap="inc:progress=25"`     数值自增 / `dec:` 自减
@MainActor
public extension XMLNode {
    /// 读取 onTap 属性并生成闭包；没有 onTap 时返回 nil。
    func tapHandler(_ ctx: XMLBuildContext) -> (() -> Void)? {
        guard let raw = attributes["onTap"], !raw.isEmpty else { return nil }
        let expression = ctx.scope.interpolate(raw)
        return { ctx.runTap(expression, path: path) }
    }
}

@MainActor
extension XMLBuildContext {
    /// 执行 onTap 表达式。
    func runTap(_ expression: String, path: String? = nil) {
        guard let separator = expression.firstIndex(of: ":") else {
            perform(expression)
            return
        }
        let verb = String(expression[..<separator]).trimmingCharacters(in: .whitespaces)
        let payload = String(expression[expression.index(after: separator)...])
        switch verb {
        case "set":
            let parts = payload.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                diagnostics.error("内置动作 set 需要 `name=value`", path: path)
                return
            }
            let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let existing = store.value(name)
            switch existing {
            case .bool: store.set(name, .bool(rawValue == "true"))
            case .int: store.set(name, .int(Int(rawValue) ?? 0))
            case .double: store.set(name, .double(Double(rawValue) ?? 0))
            case .string, .none: store.set(name, .string(rawValue))
            }
        case "toggle":
            let name = payload.trimmingCharacters(in: .whitespaces)
            store.set(name, .bool(!store.bool(name)))
        case "inc", "dec":
            let parts = payload.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let delta = parts.count == 2 ? (Int(parts[1]) ?? 1) : 1
            let current = store.int(name)
            store.set(name, .int(verb == "inc" ? current + delta : current - delta))
        default:
            perform(expression)
        }
    }
}

// MARK: - 绑定工具

@MainActor
public extension XMLNode {
    /// `bind="stateName"` 的插值结果（无则 nil）。
    func bindName(_ ctx: XMLBuildContext) -> String? {
        guard let raw = attributes["bind"] ?? attributes["bind-value"],
              !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return ctx.scope.interpolate(raw)
    }
}
