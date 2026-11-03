import XCTest
import SwiftUI
import AppKit

@testable import LauncherUI

/// DSH 更多页测试：实例日志文件映射 + 四个分区两主题 1080×720 离屏渲染。
/// 渲染验证「实例化后日志 / 数据目录 / 进程 / 关于」不崩溃、不溢出；需要人工看图时设置
/// `DSH_MORE_SNAPSHOT_DIR=/tmp/dsh-more-snap` 再跑本文件，会把 PNG 写到该目录。
@MainActor
final class DSHMoreUITests: XCTestCase {

    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    // MARK: - Fixture

    private func makeTemporaryPaths() throws -> DSHPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DSHMoreUITests-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        let paths = DSHPaths(root: root, homeRoot: root.appendingPathComponent("homes", isDirectory: true))
        try paths.ensureDirectories()
        return paths
    }

    /// 在临时 DSH 目录里"真实安装"一个实例（入口脚本 + launcher-install.json 元数据）。
    private func seedInstance(_ instance: DSHInstalledVersion, paths: DSHPaths) throws {
        let script = paths.cliScript(for: instance.id)
        try FileManager.default.createDirectory(
            at: script.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "// fake dsh cli for offscreen tests\n".write(to: script, atomically: true, encoding: .utf8)
        let metadata = DSHInstalledVersion(
            id: instance.id,
            name: instance.name,
            dshVersion: instance.dshVersion,
            installedAt: instance.installedAt,
            path: paths.versionDirectory(instance.id).path,
            sizeBytes: instance.sizeBytes,
            kind: instance.kind,
            packName: instance.packName,
            packVersion: instance.packVersion,
            legacy: false
        )
        try JSONEncoder().encode(metadata).write(
            to: paths.versionDirectory(instance.id).appendingPathComponent("launcher-install.json"),
            options: .atomic
        )
    }

    private func seedLog(instanceID: String, lines: [String], paths: DSHPaths) throws {
        let url = paths.logFile(for: instanceID)
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeInstance(
        id: String,
        name: String,
        dshVersion: String,
        kind: DSHInstanceKind = .vanilla,
        packName: String? = nil,
        packVersion: String? = nil
    ) -> DSHInstalledVersion {
        DSHInstalledVersion(
            id: id,
            name: name,
            dshVersion: dshVersion,
            installedAt: Date(timeIntervalSince1970: 1_800_000_000),
            path: "/tmp/dsh/versions/\(id)",
            sizeBytes: 2_400_000,
            kind: kind,
            packName: packName,
            packVersion: packVersion,
            legacy: false
        )
    }

    // MARK: - 实例日志文件映射

    func testLogFilesAreKeyedByInstanceID() throws {
        let paths = try makeTemporaryPaths()
        try seedInstance(makeInstance(id: "ins-a", name: "PVP 整合", dshVersion: "1.1.0"), paths: paths)
        try seedInstance(makeInstance(id: "ins-b", name: "PVP 整合 副本", dshVersion: "1.1.0"), paths: paths)
        try seedLog(instanceID: "ins-a", lines: ["✓ dsh web 已启动", "listening on 3080", "ERROR: 示例错误"], paths: paths)

        XCTAssertEqual(paths.logFile(for: "ins-a").lastPathComponent, "ins-a.log")
        XCTAssertEqual(paths.logFile(for: "ins-b").lastPathComponent, "ins-b.log")

        let lines = DSHLogTools.readTail(paths: paths, version: "ins-a")
        XCTAssertEqual(lines.count, 3, "日志文件应按实例 ID 读取：\(lines)")
        XCTAssertTrue(lines.first?.contains("dsh web") == true)

        // 另一个实例没有日志文件 → 空数组，不串到 ins-a。
        XCTAssertTrue(DSHLogTools.readTail(paths: paths, version: "ins-b").isEmpty)

        // 真实清空 ins-a 日志（截断为 0 字节），不碰 ins-b。
        XCTAssertTrue(try DSHLogTools.truncate(paths: paths, version: "ins-a"))
        XCTAssertEqual(try Data(contentsOf: paths.logFile(for: "ins-a")).count, 0)
    }

    func testInstancesKeepSameDSHVersionSeparate() throws {
        let paths = try makeTemporaryPaths()
        try seedInstance(makeInstance(id: "ins-a", name: "PVP 整合", dshVersion: "1.1.0"), paths: paths)
        try seedInstance(makeInstance(id: "ins-b", name: "PVP 整合 副本", dshVersion: "1.1.0"), paths: paths)
        try seedInstance(
            makeInstance(id: "ins-pack", name: "Starter Kit", dshVersion: "1.0.0", kind: .pack, packName: "Starter Kit", packVersion: "1.2.0"),
            paths: paths
        )

        let suite = "dsh.more.ui.tests.\(UUID().uuidString.prefix(8))"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LauncherSettings(defaults: defaults)
        settings.dshSelectedInstanceID = "ins-b"
        let store = DSHVersionStore(settings: settings, paths: paths)

        XCTAssertEqual(store.installed.count, 3)
        XCTAssertEqual(store.installed.filter { $0.dshVersion == "1.1.0" }.count, 2)
        XCTAssertEqual(store.selectedInstalledVersion?.id, "ins-b")
        XCTAssertEqual(store.installed.filter(\.isPack).count, 1)
    }

    // MARK: - 四分区两主题离屏渲染

    func testOffscreenRenderAllSectionsBothThemes() throws {
        let paths = try makeTemporaryPaths()
        try seedInstance(makeInstance(id: "ins-a", name: "PVP 整合", dshVersion: "1.1.0"), paths: paths)
        try seedInstance(makeInstance(id: "ins-b", name: "PVP 整合 副本", dshVersion: "1.1.0"), paths: paths)
        try seedInstance(
            makeInstance(id: "ins-pack", name: "Starter Kit", dshVersion: "1.0.0", kind: .pack, packName: "Starter Kit", packVersion: "1.2.0"),
            paths: paths
        )
        try seedLog(instanceID: "ins-a", lines: ["✓ dsh web 已启动", "listening on 3080"], paths: paths)

        let suite = "dsh.more.ui.render.\(UUID().uuidString.prefix(8))"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removePersistentDomain(forName: suite)

        let manager = LauncherThemeManager(presets: LauncherThemes.all, defaults: defaults)
        let settings = LauncherSettings(defaults: defaults)
        settings.dshSelectedInstanceID = "ins-a"
        let versions = DSHVersionStore(settings: settings, paths: paths)
        let process = DSHProcessController(settings: settings, paths: paths)
        let plugins = DSHPluginStore(settings: settings, paths: paths)
        let router = LauncherRouter(initialProduct: .dsh)

        let exportDirectory = ProcessInfo.processInfo.environment["DSH_MORE_SNAPSHOT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }

        let size = CGSize(width: 1080, height: 720)
        for theme in LauncherThemes.all {
            manager.themeID = theme.id
            for section in DSHMoreSection.allCases {
                let page = DSHMorePage(initialSection: section, onOpenGallery: {})
                    .launcherRouterEnvironment(router)
                    .environment(versions)
                    .environment(process)
                    .environment(plugins)
                    .launcherThemeEnvironment(manager)
                    .environment(\.colorScheme, theme.scheme)
                    .environment(\.launcherSnapshotMode, true)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                    .background(theme.colors.canvas)

                let renderer = ImageRenderer(content: page)
                renderer.scale = 1.5
                renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
                let image = try XCTUnwrap(renderer.nsImage, "DSH 更多页渲染失败：\(theme.id)-\(section.rawValue)")
                XCTAssertGreaterThan(image.size.width, 0)
                XCTAssertGreaterThan(image.size.height, 0)

                if let exportDirectory {
                    try savePNG(image, to: exportDirectory.appendingPathComponent("dsh-more-\(section.rawValue)-\(theme.id)-min.png"))
                }
            }
        }
    }

    // MARK: - 渲染辅助

    private func savePNG(_ image: NSImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let tiff = try XCTUnwrap(image.tiffRepresentation, "无法导出 TIFF")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff), "无法解码位图")
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]), "无法编码 PNG")
        try png.write(to: url)
    }
}
