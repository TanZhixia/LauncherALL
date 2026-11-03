import XCTest
import SwiftUI
import AppKit
@testable import LauncherUI

/// LauncherALL 标题栏产品切换（Minecraft / DSH）与 DSH 预留空白页。
final class ProductSwitcherTests: XCTestCase {

    func testProductMetadata() {
        XCTAssertEqual(LauncherProduct.allCases, [.minecraft, .dsh])
        XCTAssertEqual(LauncherProduct.minecraft.title, "Minecraft 启动器")
        XCTAssertEqual(LauncherProduct.dsh.title, "DSH 启动器")
        XCTAssertEqual(LauncherProduct.minecraft.systemImage, "cube.fill")
        XCTAssertEqual(LauncherProduct.dsh.systemImage, "sparkles")
        XCTAssertFalse(LauncherProduct.dsh.subtitle.isEmpty)
        XCTAssertTrue(LauncherProduct.dsh.subtitle.contains("Web UI"))
    }

    @MainActor
    func testRouterSwitchesProductsAndKeepsTabsPerProduct() {
        let router = LauncherRouter()
        XCTAssertEqual(router.activeProduct, .minecraft)

        router.switchProduct(.dsh)
        XCTAssertEqual(router.activeProduct, .dsh)

        // 切页只在当前启动器内生效，不再强制跳回 Minecraft
        router.go(.download)
        XCTAssertEqual(router.activeProduct, .dsh)
        XCTAssertEqual(router.selectedTab, .download)

        router.switchProduct(.minecraft)
        XCTAssertEqual(router.activeProduct, .minecraft)
        XCTAssertEqual(router.selectedTab, .download)
    }

    @MainActor
    func testInitialProductIsRespected() {
        let router = LauncherRouter(initialProduct: .dsh)
        XCTAssertEqual(router.activeProduct, .dsh)
        XCTAssertEqual(router.selectedTab, .launch)
    }

    @MainActor
    func testDSHLaunchPageRendersInBothThemes() throws {
        for theme in LauncherThemes.all {
            let suite = "launcher.tests.product.dsh.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
            let settings = LauncherSettings(defaults: defaults)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("product-dsh-\(UUID().uuidString)")
            addTeardownBlock { try? FileManager.default.removeItem(at: root) }
            let paths = DSHPaths(root: root)
            let manager = LauncherThemeManager(presets: LauncherThemes.all, defaults: defaults)
            manager.themeID = theme.id

            let versions = DSHVersionStore(settings: settings, paths: paths)
            let plugins = DSHPluginStore(settings: settings, paths: paths)
            let view = DSHLaunchPage()
                .environment(versions)
                .environment(DSHProcessController(settings: settings, paths: paths))
                .environment(plugins)
                .environment(DSHPackService(paths: paths, versions: versions, plugins: plugins, settings: settings))
                .environment(LauncherRouter())
                .launcherThemeEnvironment(manager)
                .environment(\.launcherSnapshotMode, true)
                .environment(\.colorScheme, theme.scheme)
                .frame(width: 1080, height: 720)
            let bitmap = try render(view, width: 1080, height: 720)
            XCTAssertEqual(bitmap.pixelsWide, 1080)
            XCTAssertEqual(bitmap.pixelsHigh, 720)
            // 页面不是纯空白：至少存在若干不同颜色（标题 / 卡片 / 空态）
            var colors = Set<String>()
            for x in stride(from: 8, to: 1070, by: 60) {
                for y in stride(from: 8, to: 710, by: 60) {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                        colors.insert(String(format: "%.2f-%.2f-%.2f", color.redComponent, color.greenComponent, color.blueComponent))
                    }
                }
            }
            XCTAssertGreaterThan(colors.count, 3, "DSH 启动页应渲染出真实内容（\(theme.id)）")
        }
    }

    @MainActor
    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff))
    }
}
