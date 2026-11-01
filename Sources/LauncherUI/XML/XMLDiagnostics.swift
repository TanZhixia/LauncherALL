import Foundation

/// 解析 / 渲染诊断：错误会阻止渲染，警告只提示。
public struct XMLDiagnostic: Identifiable, Equatable {
    public enum Severity: String, Equatable {
        case error
        case warning
        case info
    }

    public let id: UUID
    public let severity: Severity
    public let message: String
    /// 出问题的节点路径，例如 `ui/vstack/button[2]`
    public let path: String?

    public init(severity: Severity, message: String, path: String? = nil) {
        self.id = UUID()
        self.severity = severity
        self.message = message
        self.path = path
    }

    public var displayText: String {
        if let path { return "\(path)：\(message)" }
        return message
    }
}

/// 渲染期诊断收集器（渲染函数通过它上报缺失属性、未知枚举值等）。
@MainActor
public final class XMLDiagnosticsCollector {
    private(set) public var items: [XMLDiagnostic] = []

    public init() {}

    public func error(_ message: String, path: String? = nil) {
        items.append(XMLDiagnostic(severity: .error, message: message, path: path))
    }

    public func warning(_ message: String, path: String? = nil) {
        items.append(XMLDiagnostic(severity: .warning, message: message, path: path))
    }

    public var hasErrors: Bool { items.contains { $0.severity == .error } }
}
