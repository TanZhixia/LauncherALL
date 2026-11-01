import Foundation

/// 一份 XML UI 文档：源码、语法树、诊断与初始状态。
public struct LauncherXMLDocument {
    public let source: String
    public let root: XMLNode?
    public let diagnostics: [XMLDiagnostic]

    public var isValid: Bool {
        root != nil && !diagnostics.contains { $0.severity == .error }
    }

    public var title: String? {
        root?.attribute("title")
    }

    /// `<state>` 里声明的初始变量。
    public var initialValues: [String: XMLValue] {
        guard let state = root?.child(named: "state") else { return [:] }
        var values: [String: XMLValue] = [:]
        for node in state.children {
            guard let kind = XMLValue.Kind(rawValue: node.name) else { continue }
            guard let name = node.attribute("name") else { continue }
            guard let raw = node.attribute("value"), let value = XMLValue(raw, kind: kind) else { continue }
            values[name] = value
        }
        return values
    }

    /// `<actions>` 里声明的动作名（宿主需要注册同名闭包）。
    public var declaredActionNames: [String] {
        guard let actions = root?.child(named: "actions") else { return [] }
        return actions.children.compactMap { $0.attribute("name") }
    }

    /// 解析并把结构性错误（根节点名称、state 语法）转成诊断。
    public static func parse(_ source: String) -> LauncherXMLDocument {
        let parsed = XMLTreeParser.parse(source)
        var diagnostics = parsed.diagnostics
        if let root = parsed.root, root.name != "ui" {
            diagnostics.append(
                XMLDiagnostic(severity: .error, message: "根元素必须是 <ui>，当前是 <\(root.name)>", path: root.path)
            )
        }
        if parsed.root == nil && diagnostics.isEmpty {
            diagnostics.append(XMLDiagnostic(severity: .error, message: "XML 文档为空或缺少根元素", path: nil))
        }
        if let state = parsed.root?.child(named: "state") {
            for node in state.children {
                if XMLValue.Kind(rawValue: node.name) == nil {
                    diagnostics.append(
                        XMLDiagnostic(severity: .error, message: "未知状态类型 <\(node.name)>，可用 string / bool / int / double", path: node.path)
                    )
                    continue
                }
                if node.attribute("name") == nil {
                    diagnostics.append(XMLDiagnostic(severity: .error, message: "状态缺少 name 属性", path: node.path))
                }
            }
        }
        return LauncherXMLDocument(source: source, root: parsed.root, diagnostics: diagnostics)
    }

    public func makeStore() -> XMLStateStore {
        XMLStateStore(values: initialValues)
    }

    /// 从资源包加载示例（`Sources/LauncherUI/Resources/XML`）。
    public static func load(named fileName: String) -> LauncherXMLDocument? {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: fileName, withExtension: "xml"),
            Bundle.module.url(forResource: fileName, withExtension: "xml", subdirectory: "XML"),
            Bundle.module.url(forResource: fileName, withExtension: "xml", subdirectory: "Resources/XML")
        ]
        for case let url? in candidates {
            if let source = try? String(contentsOf: url, encoding: .utf8) {
                return parse(source)
            }
        }
        return nil
    }
}
