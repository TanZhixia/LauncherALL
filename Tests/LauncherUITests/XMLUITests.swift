import XCTest
import SwiftUI
@testable import LauncherUI

/// XML UI 工具链的核心行为测试：解析、诊断、状态、插值、内置动作、渲染分发。
final class XMLUITests: XCTestCase {

    // MARK: 解析

    func testParseValidDocument() {
        let xml = """
        <ui title="测试">
          <state><bool name="flag" value="true"/></state>
          <vstack spacing="md"><text style="title">你好</text></vstack>
        </ui>
        """
        let document = LauncherXMLDocument.parse(xml)
        XCTAssertTrue(document.isValid)
        XCTAssertEqual(document.title, "测试")
        XCTAssertEqual(document.initialValues["flag"], .bool(true))
    }

    func testRootMustBeUI() {
        let document = LauncherXMLDocument.parse("<page></page>")
        XCTAssertFalse(document.isValid)
        XCTAssertTrue(document.diagnostics.contains { $0.message.contains("根元素必须是 <ui>") })
    }

    func testMalformedXMLProducesDiagnostic() {
        let document = LauncherXMLDocument.parse("<ui><vstack></ui>")
        XCTAssertFalse(document.isValid)
        XCTAssertFalse(document.diagnostics.isEmpty)
    }

    func testUnknownStateTypeProducesDiagnostic() {
        let document = LauncherXMLDocument.parse("""
        <ui><state><color name="c" value="#fff"/></state></ui>
        """)
        XCTAssertTrue(document.diagnostics.contains { $0.message.contains("未知状态类型") })
    }

    func testInvalidValueProducesNoValue() {
        let document = LauncherXMLDocument.parse("""
        <ui><state><int name="n" value="abc"/></state></ui>
        """)
        XCTAssertNil(document.initialValues["n"])
    }

    func testDeclaredActions() {
        let document = LauncherXMLDocument.parse("""
        <ui><actions><action name="launch"/><action name="install"/></actions></ui>
        """)
        XCTAssertEqual(document.declaredActionNames, ["launch", "install"])
    }

    // MARK: 状态与插值

    @MainActor
    func testInterpolation() {
        let store = XMLStateStore(values: ["name": .string("Steve"), "count": .int(3)])
        let scope = XMLScope(store: store)
        XCTAssertEqual(scope.interpolate("你好 {state.name}"), "你好 Steve")
        XCTAssertEqual(scope.interpolate("{name} 有 {count} 个实例"), "Steve 有 3 个实例")
        XCTAssertEqual(scope.interpolate("无变量"), "无变量")
    }

    @MainActor
    func testItemAliasInterpolation() {
        let store = XMLStateStore()
        let item = XMLListItem(id: "1", vars: ["title": .string("1.21.4"), "size": .string("6.2 GB")])
        let scope = XMLScope(store: store, item: item, itemAlias: "inst")
        XCTAssertEqual(scope.interpolate("{inst.title} · {inst.size}"), "1.21.4 · 6.2 GB")
        XCTAssertEqual(scope.interpolate("{item.title}"), "1.21.4")
    }

    @MainActor
    func testConditionEvaluation() {
        let store = XMLStateStore(values: ["on": .bool(true), "off": .bool(false)])
        let scope = XMLScope(store: store)
        XCTAssertTrue(scope.bool(for: "{state.on}"))
        XCTAssertFalse(scope.bool(for: "{state.off}"))
        XCTAssertTrue(scope.bool(for: "true"))
        XCTAssertFalse(scope.bool(for: "false"))
        XCTAssertFalse(scope.bool(for: ""))
    }

    @MainActor
    func testBindingsWriteBack() {
        let store = XMLStateStore(values: ["text": .string("a"), "flag": .bool(false)])
        store.bindingString("text").wrappedValue = "b"
        store.bindingBool("flag").wrappedValue = true
        XCTAssertEqual(store.value("text"), .string("b"))
        XCTAssertEqual(store.value("flag"), .bool(true))
    }

    // MARK: 动作

    @MainActor
    func testActionRegistry() {
        let registry = XMLActionRegistry()
        var received = ""
        registry.register("hello") { context in
            received = context.string("name")
        }
        let store = XMLStateStore(values: ["name": .string("Steve")])
        registry.perform("hello", context: XMLActionContext(store: store))
        XCTAssertEqual(received, "Steve")
        XCTAssertTrue(registry.hasAction("hello"))
        XCTAssertEqual(registry.actionNames, ["hello"])
    }

    @MainActor
    func testBuiltinTapActions() {
        let store = XMLStateStore(values: ["flag": .bool(false), "progress": .int(10), "channel": .string("release")])
        let rendered = XMLRenderer().render(
            document: LauncherXMLDocument.parse("""
            <ui>
              <state>
                <bool name="flag" value="false"/>
                <int name="progress" value="10"/>
                <string name="channel" value="release"/>
              </state>
              <vstack>
                <text content="{state.channel}"/>
              </vstack>
            </ui>
            """),
            store: store,
            actions: XMLActionRegistry(),
            theme: LauncherThemes.default
        )
        XCTAssertFalse(rendered.diagnostics.contains { $0.severity == .error })

        // 内置简写
        store.set("flag", .bool(false))
        let collector = XMLDiagnosticsCollector()
        let context = XMLBuildContext(
            store: store,
            actions: XMLActionRegistry(),
            theme: LauncherThemes.default,
            scope: XMLScope(store: store),
            diagnostics: collector,
            build: { _, _ in AnyView(EmptyView()) }
        )
        context.runTap("toggle:flag")
        XCTAssertEqual(store.value("flag"), .bool(true))
        context.runTap("inc:progress=25")
        XCTAssertEqual(store.value("progress"), .int(35))
        context.runTap("set:channel=beta")
        XCTAssertEqual(store.value("channel"), .string("beta"))
    }

    // MARK: 渲染

    @MainActor
    func testUnknownElementProducesErrorDiagnostic() {
        let rendered = XMLRenderer().render(
            document: LauncherXMLDocument.parse("<ui><nonsense/></ui>"),
            actions: XMLActionRegistry(),
            theme: LauncherThemes.default
        )
        XCTAssertTrue(rendered.diagnostics.contains { $0.message.contains("未知元素") })
    }

    @MainActor
    func testLayoutAndBaseElementsRender() {
        let rendered = XMLRenderer().render(
            document: LauncherXMLDocument.parse("""
            <ui>
              <vstack spacing="lg" padding="xl">
                <text style="title">标题</text>
                <hstack spacing="sm"><label>标签</label><spacer/><mono content="1.21.4"/></hstack>
                <grid columns="2"><text>a</text><text>b</text></grid>
                <panel level="subtle"><text>面板</text></panel>
                <divider full-width="true"/>
              </vstack>
            </ui>
            """),
            actions: XMLActionRegistry(),
            theme: LauncherThemes.default
        )
        XCTAssertFalse(rendered.diagnostics.contains { $0.severity == .error })
    }

    @MainActor
    func testForeachUsesDataSources() {
        let data = XMLDataSources(lists: [
            "items": [
                XMLListItem(id: "a", vars: ["title": .string("A")]),
                XMLListItem(id: "b", vars: ["title": .string("B")])
            ]
        ])
        let rendered = XMLRenderer().render(
            document: LauncherXMLDocument.parse("""
            <ui><vstack><foreach in="items" as="it"><text content="{it.title}"/></foreach></vstack></ui>
            """),
            actions: XMLActionRegistry(),
            data: data,
            theme: LauncherThemes.default
        )
        XCTAssertFalse(rendered.diagnostics.contains { $0.severity == .error })
    }

    @MainActor
    func testMissingDataSourceIsWarning() {
        let rendered = XMLRenderer().render(
            document: LauncherXMLDocument.parse("<ui><foreach in=\"nope\"><text>x</text></foreach></ui>"),
            actions: XMLActionRegistry(),
            theme: LauncherThemes.default
        )
        XCTAssertTrue(rendered.diagnostics.contains { $0.severity == .warning })
        XCTAssertFalse(rendered.diagnostics.contains { $0.severity == .error })
    }
}
