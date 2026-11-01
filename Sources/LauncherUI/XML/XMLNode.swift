import Foundation

// MARK: - 节点模型

/// XML 解析后的一棵不可变元素树。
public struct XMLNode: Equatable {
    public let name: String
    public let attributes: [String: String]
    public let children: [XMLNode]
    public let text: String?
    /// 诊断用路径，例如 `ui/vstack/listrow[2]`
    public let path: String

    public init(name: String, attributes: [String: String] = [:], children: [XMLNode] = [], text: String? = nil, path: String = "") {
        self.name = name
        self.attributes = attributes
        self.children = children
        self.text = text
        self.path = path
    }

    public func attribute(_ key: String) -> String? {
        attributes[key]
    }

    public func child(named name: String) -> XMLNode? {
        children.first { $0.name == name }
    }

    public var hasChildren: Bool { !children.isEmpty }
}

// MARK: - 解析器

/// 轻量 XML 解析器：把源码解析为 `XMLNode` 树，并把语法错误收集成诊断。
public final class XMLTreeParser: NSObject, XMLParserDelegate {
    private final class Builder {
        let name: String
        let attributes: [String: String]
        let path: String
        var children: [XMLNode] = []
        var text: String = ""

        init(name: String, attributes: [String: String], path: String) {
            self.name = name
            self.attributes = attributes
            self.path = path
        }
    }

    private var stack: [Builder] = []
    private var root: XMLNode?
    private var diagnostics: [XMLDiagnostic] = []
    private var nameCounters: [String: Int] = [:]

    /// 解析 XML 字符串。
    public static func parse(_ source: String) -> (root: XMLNode?, diagnostics: [XMLDiagnostic]) {
        let delegate = XMLTreeParser()
        let parser = XMLParser(data: Data(source.utf8))
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        let success = parser.parse()
        if !success, delegate.diagnostics.isEmpty {
            let message = parser.parserError?.localizedDescription ?? "XML 解析失败"
            delegate.diagnostics.append(XMLDiagnostic(severity: .error, message: message, path: nil))
        }
        return (delegate.root, delegate.diagnostics)
    }

    // MARK: XMLParserDelegate

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let parent = stack.last
        let indexKey = "\(parent?.path ?? "ui")/\(elementName)"
        let index = (nameCounters[indexKey] ?? 0) + 1
        nameCounters[indexKey] = index
        let path = parent.map { "\($0.path)/\(elementName)[\(index)]" } ?? "\(elementName)[\(index)]"
        var attributes: [String: String] = [:]
        for (key, value) in attributeDict {
            attributes[key] = value
        }
        stack.append(Builder(name: elementName, attributes: attributes, path: path))
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let chunk = String(data: CDATABlock, encoding: .utf8) {
            stack.last?.text += chunk
        }
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let builder = stack.popLast() else { return }
        let trimmedText = builder.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let node = XMLNode(
            name: builder.name,
            attributes: builder.attributes,
            children: builder.children,
            text: trimmedText.isEmpty ? nil : trimmedText,
            path: builder.path
        )
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            root = node
        }
    }

    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        let message = parseError.localizedDescription
        if !diagnostics.contains(where: { $0.message == message }) {
            diagnostics.append(XMLDiagnostic(severity: .error, message: message, path: nil))
        }
    }
}
