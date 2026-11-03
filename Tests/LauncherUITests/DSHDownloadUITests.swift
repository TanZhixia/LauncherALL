import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import LauncherUI

/// DSH 下载页测试：格式化、版本分区与标签、插件分类与能力标签、实例分组 / 整合包展示逻辑、
/// 跨页动作映射，以及真实 store（临时 DSHPaths，不联网）上的「同版本多实例」与 snapshot 渲染。
final class DSHDownloadUITests: XCTestCase {

    // MARK: - 大小格式化

    func testSizeFormatting() {
        XCTAssertEqual(DSHDownloadFormat.size(nil), "—")
        XCTAssertEqual(DSHDownloadFormat.size(0), "0 B")
        XCTAssertEqual(DSHDownloadFormat.size(-1024), "0 B")
        XCTAssertEqual(DSHDownloadFormat.size(512), "512 B")
        XCTAssertEqual(DSHDownloadFormat.size(1024), "1.0 KB")
        XCTAssertEqual(DSHDownloadFormat.size(1536), "1.5 KB")
        XCTAssertEqual(DSHDownloadFormat.size(1_048_576), "1.0 MB")
        XCTAssertEqual(DSHDownloadFormat.size(1_073_741_824), "1.00 GB")
        XCTAssertEqual(DSHDownloadFormat.size(1_234_567_890), "1.15 GB")
        XCTAssertEqual(DSHDownloadFormat.size(2 * 1024 * 1024 * 1024 * 1024), "2.00 TB")
    }

    // MARK: - 日期格式化

    func testDateFormatting() {
        XCTAssertEqual(DSHDownloadFormat.date(nil), "—")
        XCTAssertEqual(DSHDownloadFormat.date(Date(timeIntervalSince1970: 0)), "1970-01-01")
        XCTAssertEqual(DSHDownloadFormat.rawDate("2026-11-01"), "2026-11-01")
        XCTAssertEqual(DSHDownloadFormat.rawDate("2026-11-01T10:00:00Z"), "2026-11-01")
        XCTAssertEqual(DSHDownloadFormat.rawDate(nil), "—")
        XCTAssertEqual(DSHDownloadFormat.rawDate(""), "—")
    }

    // MARK: - 星数 / 路径 / 计数

    func testStarsFormatting() {
        XCTAssertEqual(DSHDownloadFormat.stars(nil), "—")
        XCTAssertEqual(DSHDownloadFormat.stars(0), "0")
        XCTAssertEqual(DSHDownloadFormat.stars(42), "42")
        XCTAssertEqual(DSHDownloadFormat.stars(999), "999")
        XCTAssertEqual(DSHDownloadFormat.stars(1000), "1.0k")
        XCTAssertEqual(DSHDownloadFormat.stars(1234), "1.2k")
        XCTAssertEqual(DSHDownloadFormat.stars(1_500_000), "1.5m")
    }

    func testShortHomePathAndCount() {
        let home = NSHomeDirectory()
        XCTAssertEqual(DSHDownloadFormat.shortHomePath("\(home)/Library/DSH"), "~/Library/DSH")
        XCTAssertEqual(DSHDownloadFormat.shortHomePath("/tmp/dsh"), "/tmp/dsh")
        XCTAssertEqual(DSHDownloadFormat.count(12), "12 个")
        XCTAssertEqual(DSHDownloadFormat.count(8281, unit: "个"), "8281 个")
    }

    // MARK: - 版本标签

    func testVersionTagsPreferInfoDistTags() {
        let info = DSHVersionInfo(version: "0.2.1-rc.5", distTags: ["latest", "next"])
        XCTAssertEqual(DSHDownloadList.versionTags(info, catalog: nil), ["latest", "next"])
    }

    func testVersionTagsFallBackToCatalogDistTags() {
        let catalog = DSHVersionCatalog(
            versions: [
                DSHVersionInfo(version: "0.2.1-rc.5"),
                DSHVersionInfo(version: "0.2.2-alpha.2")
            ],
            distTags: ["latest": "0.2.1-rc.5", "alpha": "0.2.2-alpha.2"],
            fetchedAt: Date()
        )
        XCTAssertEqual(
            DSHDownloadList.versionTags(catalog.versions[0], catalog: catalog),
            ["latest"]
        )
        XCTAssertEqual(
            DSHDownloadList.versionTags(catalog.versions[1], catalog: catalog),
            ["alpha"]
        )
        let unknown = DSHVersionInfo(version: "9.9.9")
        XCTAssertEqual(DSHDownloadList.versionTags(unknown, catalog: catalog), [])
    }

    // MARK: - 版本分区

    func testVersionPartitionPutsInstalledFirstAndSortsDescending() {
        let versions = [
            DSHVersionInfo(version: "0.1.0"),
            DSHVersionInfo(version: "0.2.0"),
            DSHVersionInfo(version: "0.3.0")
        ]
        let partition = DSHDownloadList.partition(versions, installedIDs: ["0.1.0"])

        XCTAssertEqual(partition.total, 3)
        XCTAssertEqual(partition.installed.map(\.version), ["0.1.0"])
        XCTAssertEqual(partition.available.map(\.version), ["0.3.0", "0.2.0"])
        XCTAssertEqual(partition.displayOrder.map(\.version), ["0.1.0", "0.3.0", "0.2.0"])
        XCTAssertTrue(partition.hasAvailable)
    }

    func testVersionPartitionAllInstalledHasNoAvailable() {
        let versions = [
            DSHVersionInfo(version: "0.2.1-rc.4"),
            DSHVersionInfo(version: "0.2.1-rc.5")
        ]
        let partition = DSHDownloadList.partition(
            versions,
            installedIDs: ["0.2.1-rc.4", "0.2.1-rc.5"]
        )
        XCTAssertEqual(partition.installed.map(\.version), ["0.2.1-rc.5", "0.2.1-rc.4"])
        XCTAssertTrue(partition.available.isEmpty)
        XCTAssertFalse(partition.hasAvailable)
    }

    func testVisibleLimit() {
        let items = (1...5).map { DSHVersionInfo(version: "0.\($0).0") }
        XCTAssertEqual(DSHDownloadList.visible(items, limit: 2).count, 2)
        XCTAssertEqual(DSHDownloadList.visible(items, limit: 0).count, 5, "limit 0 视为不截断")
        XCTAssertEqual(DSHDownloadList.visible(items, limit: -3).count, 5, "负数视为不截断")
        XCTAssertEqual(DSHDownloadList.visible(items, limit: 99).count, 5)
    }

    // MARK: - 插件分类 / 能力标签

    func testPluginCategoryTitle() {
        let categories = [
            DSHPluginCategory(id: "ui", titleEN: "UI Enhancements", titleZH: "界面增强"),
            DSHPluginCategory(id: "model", titleEN: "Models", titleZH: "模型与账号接入")
        ]
        XCTAssertEqual(DSHDownloadList.categoryTitle("ui", categories: categories), "界面增强")
        XCTAssertEqual(DSHDownloadList.categoryTitle("model", categories: categories), "模型与账号接入")
        XCTAssertEqual(DSHDownloadList.categoryTitle("unknown", categories: categories), "unknown")
        XCTAssertNil(DSHDownloadList.categoryTitle(nil, categories: categories))
        XCTAssertNil(DSHDownloadList.categoryTitle("", categories: categories))
    }

    func testCapabilityLimiting() {
        let entry = DSHPluginEntry(
            name: "dsh-agint",
            owner: "Anmulzhao",
            url: "https://github.com/Anmulzhao/DSH-AGINT",
            capabilities: ["shell", "fs-write", "fs-read", "network", "subagent"]
        )
        XCTAssertEqual(DSHDownloadList.capabilities(entry), ["shell", "fs-write", "fs-read"])
        XCTAssertEqual(DSHDownloadList.capabilityCount(entry), 5)
        XCTAssertEqual(DSHDownloadList.capabilities(entry, limit: 0), [])
        XCTAssertEqual(DSHDownloadList.capabilities(entry, limit: 99).count, 5)
    }

    // MARK: - 跨页动作（启动页空态 → 下载页分类）

    func testDeepLinkDestinationMapping() {
        XCTAssertEqual(DSHDownloadDeepLink.destination(for: "dsh-versions"), .versions)
        XCTAssertEqual(DSHDownloadDeepLink.destination(for: "dsh-plugins"), .plugins)
        XCTAssertEqual(DSHDownloadDeepLink.destination(for: "dsh-packs"), .packs)
        // 其它页面的动作（如 Minecraft 的 import-modpack）不消费
        XCTAssertNil(DSHDownloadDeepLink.destination(for: "import-modpack"))
        XCTAssertNil(DSHDownloadDeepLink.destination(for: ""))
        XCTAssertNil(DSHDownloadDeepLink.destination(for: nil))
    }

    // MARK: - 实例分组（同版本多开）

    func testInstancesByVersionGroupsSameDshVersion() {
        let instances = [
            makeInstanceModel(id: "b", name: "beta", dshVersion: "0.2.1", installedAt: 200),
            makeInstanceModel(id: "a", name: "alpha", dshVersion: "0.2.1", installedAt: 100),
            makeInstanceModel(id: "c", name: "DSH 0.2.0", dshVersion: "0.2.0", installedAt: 300)
        ]
        let grouped = DSHDownloadList.instancesByVersion(instances)

        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped["0.2.1"]?.count, 2, "同一个 DSH 版本可以有多个实例")
        XCTAssertEqual(grouped["0.2.1"]?.map(\.name), ["alpha", "beta"], "组内按名字排序")
        XCTAssertEqual(grouped["0.2.0"]?.map(\.id), ["c"])
    }

    func testInstancesByVersionEmpty() {
        XCTAssertTrue(DSHDownloadList.instancesByVersion([]).isEmpty)
    }

    // MARK: - 整合包实例

    func testPackInstancesFiltersAndSortsByInstalledAtDescending() {
        let instances = [
            makeInstanceModel(id: "pack-old", name: "旧包", dshVersion: "0.2.0", installedAt: 100, kind: .pack, packName: "旧包"),
            makeInstanceModel(id: "vanilla", name: "普通", dshVersion: "0.2.1", installedAt: 200),
            makeInstanceModel(id: "pack-new", name: "新包", dshVersion: "0.2.1", installedAt: 300, kind: .pack, packName: "新包")
        ]
        let packs = DSHDownloadList.packInstances(instances)

        XCTAssertEqual(packs.map(\.id), ["pack-new", "pack-old"])
        XCTAssertTrue(packs.allSatisfy(\.isPack))
    }

    func testInstanceSummaryAndPackSubtitle() {
        let vanilla = makeInstanceModel(id: "a", name: "工作区", dshVersion: "0.2.1", installedAt: 0, size: 1_048_576)
        XCTAssertEqual(
            DSHDownloadList.instanceSummary(vanilla),
            "DSH 0.2.1 · 1.0 MB"
        )

        let pack = makeInstanceModel(
            id: "b",
            name: "团队包",
            dshVersion: "0.2.1-rc.5",
            installedAt: 0,
            size: 1_073_741_824,
            kind: .pack,
            packName: "团队环境",
            packVersion: "1.0.0",
            installedDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(
            DSHDownloadList.instanceSummary(pack),
            "DSH 0.2.1-rc.5 · 整合包 团队环境 v1.0.0 · 1.00 GB"
        )
        XCTAssertEqual(
            DSHDownloadPackUI.packSubtitle(pack),
            "DSH 0.2.1-rc.5 · 整合包 团队环境 v1.0.0 · 1.00 GB · 安装于 1970-01-01"
        )

        let legacy = makeInstanceModel(id: "c", name: "旧实例", dshVersion: "0.1.0", installedAt: 0, legacy: true)
        XCTAssertTrue(DSHDownloadList.instanceSummary(legacy).contains("旧版实例"))
    }

    // MARK: - 整合包文件 / 模式 / 可用性

    func testPackExportFileNameSanitization() {
        XCTAssertEqual(DSHDownloadPackUI.exportFileName("我的 实例"), "我的 实例.dshpack")
        XCTAssertEqual(DSHDownloadPackUI.exportFileName("a/b:c*?"), "a-b-c--.dshpack")
        XCTAssertEqual(DSHDownloadPackUI.exportFileName("  "), "DSH Pack.dshpack")
        XCTAssertEqual(DSHDownloadPackUI.exportFileName("team.dshpack"), "team.dshpack", "不会重复加扩展名")
        XCTAssertEqual(DSHDownloadPackUI.fileExtension, "dshpack")
    }

    func testPackFileTypeDetection() {
        XCTAssertTrue(DSHDownloadPackUI.isPackFile(URL(fileURLWithPath: "/tmp/demo.dshpack")))
        XCTAssertTrue(DSHDownloadPackUI.isPackFile(URL(fileURLWithPath: "/tmp/DEMO.DSHPACK")))
        XCTAssertFalse(DSHDownloadPackUI.isPackFile(URL(fileURLWithPath: "/tmp/demo.zip")))
        XCTAssertFalse(DSHDownloadPackUI.isPackFile(URL(fileURLWithPath: "/tmp/dshpack")))
    }

    func testPackDefaultImportName() {
        XCTAssertEqual(
            DSHDownloadPackUI.defaultImportName(for: URL(fileURLWithPath: "/tmp/团队整合包.dshpack")),
            "团队整合包"
        )
        XCTAssertEqual(
            DSHDownloadPackUI.defaultImportName(for: URL(fileURLWithPath: "/tmp/")),
            "tmp"
        )
    }

    func testPackUIStateMapping() {
        XCTAssertNil(DSHDownloadPackUI.busyTitle(.idle))
        XCTAssertNil(DSHDownloadPackUI.busyPhaseText(.idle))
        XCTAssertNil(DSHDownloadPackUI.busyProgress(.idle))

        let exporting = DSHPackState.exporting(name: "demo", phase: .packingRuntime, progress: 0.42)
        XCTAssertEqual(DSHDownloadPackUI.busyTitle(exporting), "正在导出「demo」")
        XCTAssertEqual(DSHDownloadPackUI.busyPhaseText(exporting), DSHPackPhase.packingRuntime.title)
        XCTAssertEqual(DSHDownloadPackUI.busyProgress(exporting), 0.42)

        let importing = DSHPackState.importing(name: "team.dshpack", phase: .reading, progress: 0.25)
        XCTAssertEqual(DSHDownloadPackUI.busyTitle(importing), "正在导入「team.dshpack」")
        XCTAssertEqual(DSHDownloadPackUI.busyPhaseText(importing), DSHPackPhase.reading.title)
        XCTAssertEqual(DSHDownloadPackUI.busyProgress(importing), 0.25)

        let failed = DSHPackState.failed("fail")
        XCTAssertNil(DSHDownloadPackUI.busyTitle(failed))
        XCTAssertNil(DSHDownloadPackUI.busyProgress(failed))
    }

    func testPackUIBlockedReasons() {
        let instance = makeInstanceModel(id: "a", name: "工作区", dshVersion: "0.2.1", installedAt: 0)
        let ready = DSHEnvironmentSnapshot(
            isProbed: true, hasNode: true, packageManagerName: "pnpm", detailText: "ready"
        )

        XCTAssertEqual(
            DSHDownloadPackUI.exportBlockedReason(
                instance: instance, state: .idle, environmentReady: true, isReadOnly: true
            ),
            "快照模式不执行导出"
        )
        XCTAssertEqual(
            DSHDownloadPackUI.exportBlockedReason(
                instance: instance,
                state: .exporting(name: "x", phase: .preparing, progress: 0),
                environmentReady: true,
                isReadOnly: false
            ),
            "已有整合包任务在进行"
        )
        XCTAssertEqual(
            DSHDownloadPackUI.exportBlockedReason(
                instance: nil, state: .idle, environmentReady: true, isReadOnly: false
            ),
            "请先安装并选择一个 DSH 实例"
        )
        XCTAssertEqual(
            DSHDownloadPackUI.exportBlockedReason(
                instance: instance, state: .idle, environmentReady: false, isReadOnly: false
            ),
            "缺少 Node.js / 包管理器"
        )
        XCTAssertNil(
            DSHDownloadPackUI.exportBlockedReason(
                instance: instance, state: .idle, environmentReady: true, isReadOnly: false
            )
        )

        XCTAssertEqual(
            DSHDownloadPackUI.importBlockedReason(
                state: .idle, environmentReady: ready.isReady, isReadOnly: true
            ),
            "快照模式不执行导入"
        )
        XCTAssertNil(
            DSHDownloadPackUI.importBlockedReason(
                state: .idle, environmentReady: ready.isReady, isReadOnly: false
            )
        )
        XCTAssertFalse(DSHDownloadPackUI.runtimeDescription(.bundled).isEmpty)
        XCTAssertFalse(DSHDownloadPackUI.runtimeDescription(.online).isEmpty)
    }

    // MARK: - 真实 store：同版本多实例（临时 DSHPaths，不联网）

    @MainActor
    func testSameVersionMultipleNamedInstancesInStore() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        try makeInstanceDirectory(harness.paths, id: "inst-alpha", name: "alpha", dshVersion: "0.2.1")
        try makeInstanceDirectory(harness.paths, id: "inst-beta", name: "beta", dshVersion: "0.2.1")
        harness.versions.refreshInstalled()

        XCTAssertEqual(harness.versions.installed.count, 2)
        XCTAssertEqual(harness.versions.instances(of: "0.2.1").map(\.name), ["alpha", "beta"])
        XCTAssertTrue(harness.versions.hasInstance(of: "0.2.1"))
        XCTAssertFalse(harness.versions.hasInstance(of: "9.9.9"))
        XCTAssertEqual(DSHVersionStore.defaultName(for: "0.2.1"), "DSH 0.2.1")

        // 默认选中第一个实例
        XCTAssertEqual(harness.versions.settings.dshSelectedInstanceID, "inst-alpha")
        harness.versions.select("inst-beta")
        XCTAssertEqual(harness.versions.settings.dshSelectedInstanceID, "inst-beta")
        XCTAssertEqual(harness.versions.selectedInstalledVersion?.name, "beta")

        // 每个实例有独立 DSH_HOME（homes/<id>）
        XCTAssertEqual(
            harness.paths.homeDirectory(for: "inst-alpha").lastPathComponent,
            "inst-alpha"
        )
        XCTAssertNotEqual(
            harness.paths.homeDirectory(for: "inst-alpha"),
            harness.paths.homeDirectory(for: "inst-beta")
        )

        // 卸载一个实例不影响同版本的另一个
        XCTAssertTrue(harness.versions.uninstall("inst-alpha"))
        XCTAssertEqual(harness.versions.instances(of: "0.2.1").map(\.name), ["beta"])
        XCTAssertTrue(harness.versions.hasInstance(of: "0.2.1"))

        XCTAssertTrue(harness.versions.uninstall("inst-beta"))
        XCTAssertFalse(harness.versions.hasInstance(of: "0.2.1"))
        XCTAssertTrue(harness.versions.installed.isEmpty)
    }

    @MainActor
    func testPackInstanceAdoptionAndListing() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        try makeInstanceDirectory(harness.paths, id: "pack-a", name: "团队包", dshVersion: "0.2.1", kind: .pack, packName: "团队环境")

        harness.versions.adoptImportedInstance(
            instanceID: "pack-a",
            name: "团队包",
            dshVersion: "0.2.1",
            size: 2_048,
            packName: "团队环境",
            packVersion: "1.0.0"
        )

        XCTAssertEqual(harness.versions.installed.count, 1)
        let pack = try XCTUnwrap(harness.versions.installed.first)
        XCTAssertTrue(pack.isPack)
        XCTAssertEqual(pack.packName, "团队环境")
        XCTAssertEqual(pack.packVersion, "1.0.0")
        XCTAssertEqual(harness.versions.settings.dshSelectedInstanceID, "pack-a")
        XCTAssertEqual(DSHDownloadList.packInstances(harness.versions.installed).map(\.id), ["pack-a"])
        XCTAssertEqual(DSHDownloadList.instanceSummary(pack), "DSH 0.2.1 · 整合包 团队环境 v1.0.0 · 2.0 KB")
    }

    // MARK: - 运行环境快照

    func testEnvironmentSnapshotReadiness() {
        XCTAssertFalse(DSHEnvironmentSnapshot.notProbed.isProbed)
        XCTAssertFalse(DSHEnvironmentSnapshot.notProbed.isReady)

        let ready = DSHEnvironmentSnapshot(
            isProbed: true,
            hasNode: true,
            packageManagerName: "pnpm",
            detailText: "Node /opt/homebrew/bin/node · pnpm"
        )
        XCTAssertTrue(ready.isReady)

        let noManager = DSHEnvironmentSnapshot(
            isProbed: true,
            hasNode: true,
            packageManagerName: nil,
            detailText: "Node /usr/local/bin/node · 未找到 pnpm / npm"
        )
        XCTAssertFalse(noManager.isReady)

        let noNode = DSHEnvironmentSnapshot(
            isProbed: true,
            hasNode: false,
            packageManagerName: "npm",
            detailText: "未找到 Node.js 运行时"
        )
        XCTAssertFalse(noNode.isReady)
    }

    // MARK: - 快照模式：整合包分类渲染 + 不启动任何任务

    @MainActor
    func testSnapshotModeRendersAllCategoriesWithoutStartingWork() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        try makeInstanceDirectory(harness.paths, id: "inst-a", name: "alpha", dshVersion: "0.2.1")
        try makeInstanceDirectory(
            harness.paths, id: "pack-a", name: "团队包", dshVersion: "0.2.1",
            kind: .pack, packName: "团队环境"
        )
        harness.versions.refreshInstalled()
        harness.versions.setCatalogForTesting(makeVersionCatalog())
        harness.plugins.setCatalogForTesting(makePluginCatalog())

        for category in DSHDownloadCategory.allCases {
            let bitmap = try XCTUnwrap(
                renderPage(category, harness: harness),
                "\(category.title) 快照渲染失败"
            )
            XCTAssertGreaterThan(bitmap.pixelsWide, 0)
            XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        }

        // 渲染过程中不能启动安装 / 导入 / 导出，也不能把加载状态改动（不联网）
        XCTAssertEqual(harness.packs.state, .idle)
        XCTAssertEqual(harness.versions.installState, .idle)
        XCTAssertFalse(harness.versions.catalogState.isLoading)
        XCTAssertFalse(harness.plugins.catalogState.isLoading)
        XCTAssertNil(harness.versions.installLog.first)
        XCTAssertTrue(harness.packs.logLines.isEmpty)
    }

    @MainActor
    func testProgressCardRendersWithDeterminateProgress() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        harness.manager.themeID = LauncherThemes.all[0].id

        let card = DSHProgressCard(
            title: "正在导出「团队包」",
            phase: DSHPackPhase.packingPlugins.title,
            progress: 0.42,
            logLines: ["打包 12 个插件…", "写入 manifest.json…"],
            onCancel: {}
        )
        .launcherThemeEnvironment(harness.manager)
        .frame(width: 560)
        .padding()
        .background(harness.manager.theme.colors.canvas)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage, "进度卡渲染失败")
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) })
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }

    // MARK: - 真实 npm 目录 → 页面列表

    func testPartitionAndTagsFromNpmCatalogFixture() throws {
        let json = """
        {
          "name": "@deepseek-ai/dsh",
          "dist-tags": {"latest": "0.2.1-rc.5", "alpha": "0.2.2-alpha.2"},
          "versions": {
            "0.2.0": {"version": "0.2.0", "dist": {"tarball": "https://example.com/a.tgz", "unpackedSize": 1024}},
            "0.2.1-rc.5": {"version": "0.2.1-rc.5", "dist": {"tarball": "https://example.com/b.tgz", "unpackedSize": 2048}},
            "0.2.2-alpha.2": {"version": "0.2.2-alpha.2", "dist": {"tarball": "https://example.com/c.tgz"}}
          },
          "time": {
            "0.2.0": "2026-10-01T00:00:00.000Z",
            "0.2.1-rc.5": "2026-10-29T13:55:07.029Z"
          }
        }
        """
        let catalog = try DSHRegistryClient.decodeVersionCatalog(Data(json.utf8))
        let partition = DSHDownloadList.partition(catalog.versions, installedIDs: ["0.2.1-rc.5"])

        XCTAssertEqual(partition.installed.map(\.version), ["0.2.1-rc.5"])
        XCTAssertEqual(partition.available.map(\.version), ["0.2.2-alpha.2", "0.2.0"])
        XCTAssertEqual(
            DSHDownloadList.versionTags(partition.installed[0], catalog: catalog),
            ["latest"]
        )
        XCTAssertEqual(
            DSHDownloadList.versionTags(partition.available[0], catalog: catalog),
            ["alpha"]
        )
        XCTAssertEqual(
            DSHDownloadFormat.size(catalog.versions.first { $0.version == "0.2.1-rc.5" }?.unpackedSize),
            "2.0 KB"
        )
        XCTAssertEqual(
            DSHDownloadFormat.date(catalog.versions.first { $0.version == "0.2.0" }?.publishedAt),
            "2026-10-01"
        )
    }
}

// MARK: - 测试辅助

extension DSHDownloadUITests {

    /// 内存里的实例模型（不落盘）。
    private func makeInstanceModel(
        id: String,
        name: String,
        dshVersion: String,
        installedAt: TimeInterval,
        size: Int64? = nil,
        kind: DSHInstanceKind = .vanilla,
        packName: String? = nil,
        packVersion: String? = nil,
        legacy: Bool = false,
        installedDate: Date? = nil
    ) -> DSHInstalledVersion {
        DSHInstalledVersion(
            id: id,
            name: name,
            dshVersion: dshVersion,
            installedAt: installedDate ?? Date(timeIntervalSince1970: installedAt),
            path: "/tmp/dsh-tests/\(id)",
            sizeBytes: size,
            kind: kind,
            packName: packName,
            packVersion: packVersion,
            legacy: legacy
        )
    }

    /// 在临时 DSHPaths 里造一个可被 `refreshInstalled()` 扫描到的实例目录。
    private func makeInstanceDirectory(
        _ paths: DSHPaths,
        id: String,
        name: String,
        dshVersion: String,
        kind: DSHInstanceKind = .vanilla,
        packName: String? = nil
    ) throws {
        let fileManager = FileManager.default
        let directory = paths.versionDirectory(id)
        let script = paths.cliScript(for: id)
        try fileManager.createDirectory(
            at: script.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "// dsh cli".write(to: script, atomically: true, encoding: .utf8)
        let instance = DSHInstalledVersion(
            id: id,
            name: name,
            dshVersion: dshVersion,
            installedAt: Date(),
            path: directory.path,
            sizeBytes: 1_024,
            kind: kind,
            packName: packName,
            packVersion: packName == nil ? nil : "1.0.0"
        )
        try JSONEncoder().encode(instance).write(
            to: directory.appendingPathComponent("launcher-install.json"),
            options: .atomic
        )
    }

    /// 渲染用 harness：临时 DSHPaths + 各 store + 主题 / 路由。
    struct Harness {
        let root: URL
        let defaults: UserDefaults
        let paths: DSHPaths
        let versions: DSHVersionStore
        let plugins: DSHPluginStore
        let process: DSHProcessController
        let packs: DSHPackService
        let manager: LauncherThemeManager
        let router: LauncherRouter

        @MainActor
        func cleanup() {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let defaultsSuiteName: String
    }

    @MainActor
    private func makeHarness() throws -> Harness {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dsh-download-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let paths = DSHPaths(
            root: root.appendingPathComponent("DSH", isDirectory: true),
            homeRoot: root.appendingPathComponent("DSH/home", isDirectory: true)
        )
        try paths.ensureDirectories()

        let suite = "launcher.tests.dsh.download.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let settings = LauncherSettings(defaults: defaults)
        let versions = DSHVersionStore(settings: settings, paths: paths)
        let plugins = DSHPluginStore(settings: settings, paths: paths)
        let process = DSHProcessController(settings: settings, paths: paths)
        let packs = DSHPackService(paths: paths, versions: versions, plugins: plugins, settings: settings)
        let manager = LauncherThemeManager(presets: LauncherThemes.all, defaults: defaults)

        return Harness(
            root: root,
            defaults: defaults,
            paths: paths,
            versions: versions,
            plugins: plugins,
            process: process,
            packs: packs,
            manager: manager,
            router: LauncherRouter(),
            defaultsSuiteName: suite
        )
    }

    /// 1080×720、两主题之一、快照模式渲染整页。
    @MainActor
    private func renderPage(
        _ category: DSHDownloadCategory,
        harness: Harness,
        theme: LauncherTheme? = nil
    ) -> NSBitmapImageRep? {
        let resolvedTheme = theme ?? harness.manager.theme
        harness.manager.themeID = resolvedTheme.id
        let view = DSHDownloadPage(initialCategory: category)
            .environment(harness.router)
            .environment(harness.versions)
            .environment(harness.plugins)
            .environment(harness.process)
            .environment(harness.packs)
            .launcherThemeEnvironment(harness.manager)
            .environment(\.colorScheme, resolvedTheme.scheme)
            .environment(\.launcherSnapshotMode, true)
            .frame(width: 1080, height: 720, alignment: .topLeading)
            .clipped()
            .background(resolvedTheme.colors.canvas)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 720)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    /// 最小可用的远端版本目录（真实版本号形状，不联网）。
    private func makeVersionCatalog() -> DSHVersionCatalog {
        let versions = [
            "0.1.8", "0.2.0", "0.2.1-rc.4", "0.2.1-rc.5", "0.2.2-alpha.2"
        ].map { version in
            DSHVersionInfo(
                version: version,
                publishedAt: Date(timeIntervalSince1970: 1_760_000_000 - Double(version.count) * 86_400),
                unpackedSize: version.contains("-") ? 3_200_000 : 4_150_000
            )
        }
        return DSHVersionCatalog(
            versions: versions,
            distTags: ["latest": "0.2.1-rc.5", "alpha": "0.2.2-alpha.2"],
            fetchedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    /// 最小可用的插件目录（分类 + 2 个插件）。
    private func makePluginCatalog() -> DSHPluginCatalog {
        DSHPluginCatalog(
            plugins: [
                DSHPluginEntry(
                    name: "dsh-ui-enhancer",
                    owner: "mistivia",
                    url: "https://github.com/mistivia/dsh-ui-enhancer",
                    category: "ui",
                    descriptionZH: "为 DSH Web 界面提供更紧凑的布局与更清晰的信息栏。",
                    npm: "dsh-ui-enhancer",
                    version: "1.4.2",
                    stars: 2_180,
                    capabilities: ["fs-read", "ui"],
                    install: "dsh plugin --profile web add dsh-ui-enhancer"
                ),
                DSHPluginEntry(
                    name: "dsh-model-bridge",
                    owner: "dsh-community",
                    url: "https://github.com/dsh-community/dsh-model-bridge",
                    category: "model",
                    descriptionZH: "把第三方模型服务接入 DSH 的模型选择器。",
                    npm: "dsh-model-bridge",
                    version: "2.0.1",
                    stars: 940,
                    capabilities: ["network"],
                    install: "dsh plugin --profile web add dsh-model-bridge"
                )
            ],
            categories: [
                DSHPluginCategory(id: "ui", titleEN: "UI", titleZH: "界面增强"),
                DSHPluginCategory(id: "model", titleEN: "Models", titleZH: "模型与账号接入")
            ],
            updated: "2026-11-01",
            sourceURL: DSHRegistryClient.defaultPluginSource,
            fetchedAt: Date()
        )
    }
}
