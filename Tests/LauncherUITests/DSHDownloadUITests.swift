import Foundation
import XCTest
@testable import LauncherUI

/// DSH 下载页测试：大小 / 日期 / 星数格式化、版本分区与标签、插件分类与能力标签、
/// 运行环境快照，以及「真实目录数据 → 页面列表」的排序与过滤。
/// 全部是纯逻辑 / 本地 fixture，不访问网络、不启动子进程。
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
        // 其它页面的动作（如 Minecraft 的 import-modpack）不消费
        XCTAssertNil(DSHDownloadDeepLink.destination(for: "import-modpack"))
        XCTAssertNil(DSHDownloadDeepLink.destination(for: ""))
        XCTAssertNil(DSHDownloadDeepLink.destination(for: nil))
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
