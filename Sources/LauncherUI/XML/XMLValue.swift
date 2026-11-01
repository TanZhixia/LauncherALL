import Foundation

/// XML 运行时值：状态变量、列表项字段、表达式结果统一用它表示。
public enum XMLValue: Equatable, Hashable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    /// 状态声明里允许的类型名。
    public enum Kind: String, CaseIterable {
        case string, bool, int, double
    }

    public init?(_ raw: String, kind: Kind) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .string:
            self = .string(raw)
        case .bool:
            switch trimmed.lowercased() {
            case "true", "yes", "1": self = .bool(true)
            case "false", "no", "0": self = .bool(false)
            default: return nil
            }
        case .int:
            guard let value = Int(trimmed) else { return nil }
            self = .int(value)
        case .double:
            guard let value = Double(trimmed) else { return nil }
            self = .double(value)
        }
    }

    public var stringValue: String {
        switch self {
        case .string(let value): return value
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .double(let value):
            if value == value.rounded() && abs(value) < 1e15 {
                return String(Int(value))
            }
            return String(value)
        }
    }

    public var boolValue: Bool {
        switch self {
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !(trimmed.isEmpty || trimmed == "false" || trimmed == "0" || trimmed == "no")
        case .bool(let value): return value
        case .int(let value): return value != 0
        case .double(let value): return value != 0
        }
    }

    public var doubleValue: Double {
        switch self {
        case .string(let value): return Double(value) ?? 0
        case .bool(let value): return value ? 1 : 0
        case .int(let value): return Double(value)
        case .double(let value): return value
        }
    }

    public var intValue: Int {
        switch self {
        case .string(let value): return Int(value) ?? 0
        case .bool(let value): return value ? 1 : 0
        case .int(let value): return value
        case .double(let value): return Int(value)
        }
    }
}

/// `<foreach>` 的单个条目：一组命名变量，供 `{item.xxx}` 取值。
public struct XMLListItem: Identifiable, Equatable {
    public let id: String
    public let vars: [String: XMLValue]

    public init(id: String, vars: [String: XMLValue]) {
        self.id = id
        self.vars = vars
    }

    public func value(for field: String) -> XMLValue? { vars[field] }
}

/// 供 `<foreach in="instances">` 使用的数据源集合。
public struct XMLDataSources: Equatable {
    public var lists: [String: [XMLListItem]]

    public init(lists: [String: [XMLListItem]] = [:]) {
        self.lists = lists
    }

    public static let empty = XMLDataSources()
}

// MARK: - 表达式作用域

/// 属性与文本里的 `{expr}` 求值作用域：支持 `{state.name}`、`{item.field}`、`{name}`。
@MainActor
public struct XMLScope {
    public let store: XMLStateStore
    public let item: XMLListItem?
    /// `<foreach as="inst">` 的别名，默认 "item"
    public let itemAlias: String

    public init(store: XMLStateStore, item: XMLListItem? = nil, itemAlias: String? = nil) {
        self.store = store
        self.item = item
        self.itemAlias = itemAlias ?? "item"
    }

    /// 解析单个表达式（不含花括号）。
    public func value(for expression: String) -> XMLValue? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let head = parts.first.map(String.init) ?? ""
        switch head {
        case "state":
            guard parts.count == 2 else { return nil }
            return store.value(String(parts[1]))
        case itemAlias, "item":
            guard parts.count == 2 else { return nil }
            return item?.value(for: String(parts[1]))
        default:
            if let direct = store.value(trimmed) { return direct }
            return item?.value(for: trimmed)
        }
    }

    /// 字符串插值：把 `{...}` 全部替换成当前值；无值则替换为空串。
    public func interpolate(_ raw: String) -> String {
        guard raw.contains("{") else { return raw }
        var result = ""
        var cursor = raw.startIndex
        while let open = raw[cursor...].firstIndex(of: "{") {
            guard let close = raw[open...].firstIndex(of: "}") else { break }
            result += raw[cursor..<open]
            let expression = String(raw[raw.index(after: open)..<close])
            result += value(for: expression)?.stringValue ?? ""
            cursor = raw.index(after: close)
        }
        result += raw[cursor...]
        return result
    }

    /// 条件求值：`true` / `{state.flag}` / `{item.installed}` / 非空字符串。
    public func bool(for raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return value(for: String(trimmed.dropFirst().dropLast()))?.boolValue ?? false
        }
        switch trimmed.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0", "": return false
        default: return true
        }
    }
}
