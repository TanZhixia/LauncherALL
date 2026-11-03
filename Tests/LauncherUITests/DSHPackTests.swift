import XCTest
import Foundation
@testable import LauncherUI

/// DSH 整合包（`.dshpack`）格式与导入 / 导出测试。
///
/// 全部使用临时 `DSHPaths` + 手工构造的假实例目录（假 `node_modules/@deepseek-ai/dsh/lib/bin.js`、
/// `package.json`、profile），不访问 npm / 网络，也不写用户主目录。
final class DSHPackTests: XCTestCase {

    // MARK: - 格式常量

    func testPackFormatConstants() {
        XCTAssertEqual(DSHPackFormat.fileExtension, "dshpack")
        XCTAssertEqual(DSHPackFormat.identifier, "launcherall.dshpack")
        XCTAssertEqual(DSHPackFormat.formatVersion, 1)
        XCTAssertEqual(DSHPackFormat.manifestName, "manifest.json")
        XCTAssertEqual(DSHPackFormat.runtimePath, "payload/runtime")
        XCTAssertEqual(DSHPackFormat.pluginsPath, "payload/plugins")

        XCTAssertEqual(DSHPackRuntimeMode.allCases, [.bundled, .online])
        XCTAssertEqual(DSHPackRuntimeMode.bundled.rawValue, "bundled")
        XCTAssertEqual(DSHPackRuntimeMode.online.rawValue, "online")
        XCTAssertTrue(DSHPackRuntimeMode.bundled.title.contains("完整包"))
        XCTAssertTrue(DSHPackRuntimeMode.online.title.contains("轻量包"))

        XCTAssertEqual(DSHPackPlugin(name: "@scope/p", spec: "@scope/p@1.0.0").id, "@scope/p")
    }

    func testPackStateAndErrorHelpers() {
        XCTAssertFalse(DSHPackState.idle.isBusy)
        XCTAssertTrue(DSHPackState.exporting(name: "a", phase: .preparing, progress: 0).isBusy)
        XCTAssertTrue(DSHPackState.importing(name: "a", phase: .reading, progress: 0.5).isBusy)
        XCTAssertFalse(DSHPackState.failed("x").isBusy)

        XCTAssertEqual(DSHPackPhase.preparing.title, "准备整合包…")
        XCTAssertEqual(DSHPackPhase.packingRuntime.title, "打包 DSH 本体…")
        XCTAssertEqual(DSHPackPhase.reading.title, "读取整合包…")
        XCTAssertEqual(DSHPackPhase.installingPlugins.title, "安装插件…")
        XCTAssertEqual(DSHPackPhase.finishing.title, "完成…")

        XCTAssertTrue(DSHPackError.missingManifest.errorDescription?.contains("manifest.json") ?? false)
        XCTAssertTrue(DSHPackError.unsafePath("../evil").errorDescription?.contains("../evil") ?? false)
        XCTAssertTrue(DSHPackError.unsupportedVersion(99).errorDescription?.contains("99") ?? false)
        XCTAssertTrue(DSHPackError.missingRuntime.errorDescription?.contains("运行时") ?? false)
        XCTAssertEqual(DSHPackError.cancelled.localizedDescription, "操作已取消")
    }

    // MARK: - manifest.json 编解码

    func testManifestRoundTripWithISODateAndPluginPayload() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let manifest = DSHPackManifest(
            name: "团队整合包",
            version: "1.2.0",
            description: "带离线插件载荷",
            author: "pack-tests",
            createdAt: createdAt,
            dshVersion: "0.2.1-rc.5",
            runtime: .bundled,
            plugins: [
                DSHPackPlugin(
                    name: "@scope/plugin-a",
                    spec: "@scope/plugin-a@1.2.3",
                    version: "1.2.3",
                    payload: "payload/plugins/plugin-a-1.2.3.tgz"
                ),
                DSHPackPlugin(name: "plugin-b", spec: "github:owner/plugin-b")
            ],
            settings: ["dshPort": "3080"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains(DSHPackFormat.identifier))
        XCTAssertTrue(json.contains("\"createdAt\""))
        XCTAssertTrue(json.contains("2023-11-14T22:13:20Z"), "createdAt 应按 ISO8601 编码：\(json)")
        XCTAssertTrue(json.contains("payload/plugins/plugin-a-1.2.3.tgz"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DSHPackManifest.self, from: data)
        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(decoded.format, DSHPackFormat.identifier)
        XCTAssertEqual(decoded.formatVersion, DSHPackFormat.formatVersion)
        XCTAssertEqual(decoded.runtime, .bundled)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.settings?["dshPort"], "3080")
        XCTAssertEqual(decoded.plugins.count, 2)
        XCTAssertEqual(decoded.plugins[0].payload, "payload/plugins/plugin-a-1.2.3.tgz")
        XCTAssertNil(decoded.plugins[1].payload)
        XCTAssertNil(decoded.plugins[1].version)
    }

    func testManifestDecodingIgnoresUnknownFieldsAndOptionalSettings() throws {
        let json = """
        {
          "format": "launcherall.dshpack",
          "formatVersion": 1,
          "name": "外部整合包",
          "version": "0.1.0",
          "description": "",
          "author": "someone",
          "createdAt": "2026-11-03T12:00:00Z",
          "dshVersion": "0.2.2-alpha.2",
          "runtime": "online",
          "plugins": [
            {"name": "p", "spec": "p@1.0.0", "futurePluginField": 42}
          ],
          "futureTopLevelField": {"nested": [1, 2, 3]}
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(DSHPackManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.format, DSHPackFormat.identifier)
        XCTAssertEqual(manifest.formatVersion, 1)
        XCTAssertEqual(manifest.name, "外部整合包")
        XCTAssertEqual(manifest.runtime, .online)
        XCTAssertEqual(manifest.dshVersion, "0.2.2-alpha.2")
        XCTAssertNil(manifest.settings, "缺失的可选 settings 应为 nil")
        XCTAssertEqual(manifest.plugins.map(\.name), ["p"])
        XCTAssertNil(manifest.plugins.first?.version)
        XCTAssertEqual(manifest.plugins.first?.id, "p")
    }

    func testManifestDecodingRejectsUnknownRuntimeMode() {
        let json = """
        {
          "format": "launcherall.dshpack",
          "formatVersion": 1,
          "name": "包",
          "version": "1.0.0",
          "description": "",
          "author": "",
          "createdAt": "2026-11-03T12:00:00Z",
          "dshVersion": "0.2.1-rc.5",
          "runtime": "hybrid",
          "plugins": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(DSHPackManifest.self, from: Data(json.utf8)),
                             "未知 runtime 枚举值不应被静默接受")
    }

    // MARK: - 实例名规范化

    @MainActor
    func testNormalizedInstanceName() {
        XCTAssertEqual(DSHVersionStore.normalizedInstanceName(nil, fallback: "DSH 0.2.1-rc.5"), "DSH 0.2.1-rc.5")
        XCTAssertEqual(DSHVersionStore.normalizedInstanceName("", fallback: "fallback"), "fallback")
        XCTAssertEqual(DSHVersionStore.normalizedInstanceName("   \n\t ", fallback: "fallback"), "fallback")
        XCTAssertEqual(DSHVersionStore.normalizedInstanceName("  我的   实例  ", fallback: "fallback"), "我的 实例")
        XCTAssertEqual(DSHVersionStore.normalizedInstanceName("测试实例", fallback: "fallback"), "测试实例")

        let long = String(repeating: "长", count: 100)
        let normalized = DSHVersionStore.normalizedInstanceName(long, fallback: "fallback")
        XCTAssertEqual(normalized.count, 60, "实例名应限制在 60 个字符以内")

        XCTAssertEqual(DSHVersionStore.defaultName(for: "0.2.1-rc.5"), "DSH 0.2.1-rc.5")
    }

    // MARK: - 导出

    @MainActor
    func testExportBundledPackContainsRuntimeAndManifest() async throws {
        let fixture = try makeFixture(withPlugins: true)
        let destination = fixture.root.appendingPathComponent("team.dshpack")

        let exported = await fixture.service.exportPack(
            instance: fixture.instance,
            name: "团队整合包",
            version: "2.0.0",
            description: "离线可用",
            author: "pack-tests",
            runtime: .bundled,
            includePluginPayloads: false,
            to: destination
        )

        XCTAssertEqual(exported?.standardizedFileURL.path, destination.standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(fixture.service.state, .idle)
        XCTAssertNil(fixture.service.lastError)

        let entries = try zipEntries(destination)
        XCTAssertTrue(entries.contains(DSHPackFormat.manifestName), "zip 应包含 manifest.json：\(entries)")
        XCTAssertTrue(
            entries.contains("payload/runtime/node_modules/@deepseek-ai/dsh/lib/bin.js"),
            "bundled 包应包含 DSH 运行时入口：\(entries)"
        )
        XCTAssertTrue(entries.contains("payload/runtime/package.json"))
        XCTAssertFalse(
            entries.contains { $0.hasSuffix("launcher-install.json") },
            "实例安装元数据不应打进整合包"
        )

        let manifest = try readManifest(from: destination)
        XCTAssertEqual(manifest.format, DSHPackFormat.identifier)
        XCTAssertEqual(manifest.name, "团队整合包")
        XCTAssertEqual(manifest.version, "2.0.0")
        XCTAssertEqual(manifest.description, "离线可用")
        XCTAssertEqual(manifest.author, "pack-tests")
        XCTAssertEqual(manifest.dshVersion, "0.2.1-rc.5")
        XCTAssertEqual(manifest.runtime, .bundled)
        // 从实例 web profile 读取的插件清单（includePluginPayloads=false 时不带离线载荷）。
        XCTAssertEqual(manifest.plugins.map(\.name), ["@test/plugin-a"])
        XCTAssertEqual(manifest.plugins.first?.spec, "@test/plugin-a@1.2.3")
        XCTAssertEqual(manifest.plugins.first?.version, "1.2.3")
        XCTAssertNil(manifest.plugins.first?.payload)
    }

    @MainActor
    func testExportOnlinePackOmitsRuntimePayload() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let destination = fixture.root.appendingPathComponent("light.dshpack")

        let exported = await fixture.service.exportPack(
            instance: fixture.instance,
            name: "轻量整合包",
            version: "1.0.0",
            description: "",
            author: "",
            runtime: .online,
            includePluginPayloads: false,
            to: destination
        )

        XCTAssertNotNil(exported)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(fixture.service.state, .idle)

        let entries = try zipEntries(destination)
        XCTAssertTrue(entries.contains(DSHPackFormat.manifestName))
        XCTAssertFalse(entries.contains { $0.hasPrefix("payload/runtime") }, "online 包不应包含 DSH 本体：\(entries)")
        XCTAssertFalse(entries.contains { $0.hasPrefix("payload/plugins") })

        let manifest = try readManifest(from: destination)
        XCTAssertEqual(manifest.runtime, .online)
        XCTAssertEqual(manifest.name, "轻量整合包")
        XCTAssertEqual(manifest.dshVersion, "0.2.1-rc.5")
        XCTAssertTrue(manifest.plugins.isEmpty)
    }

    @MainActor
    func testExportBundledPackFailsWithoutRuntime() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let broken = DSHInstalledVersion(
            id: "broken-instance",
            name: "坏实例",
            dshVersion: "0.2.1-rc.5",
            installedAt: Date(),
            path: fixture.paths.versionDirectory("broken-instance").path,
            kind: .vanilla
        )
        let destination = fixture.root.appendingPathComponent("broken.dshpack")

        let exported = await fixture.service.exportPack(
            instance: broken,
            name: "坏包",
            version: "1.0.0",
            description: "",
            author: "",
            runtime: .bundled,
            includePluginPayloads: false,
            to: destination
        )

        XCTAssertNil(exported)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(fixture.service.lastError, .exportFailed("实例的 DSH 运行时文件不完整"))
        guard case .failed(let message) = fixture.service.state else {
            return XCTFail("导出失败应进入 failed 态：\(fixture.service.state)")
        }
        XCTAssertTrue(message.contains("运行时"))
    }

    // MARK: - 导入

    @MainActor
    func testImportBundledPackCreatesPackInstance() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let pack = try await exportBundledPack(from: fixture, name: "团队整合包", version: "1.0.0")

        let imported = await fixture.service.importPack(from: pack, customName: "  导入的实例  ")
        let instance = try XCTUnwrap(imported, "导入 bundled 整合包失败：\(String(describing: fixture.service.lastError))")

        XCTAssertEqual(instance.name, "导入的实例", "自定义名字应去首尾空白并覆盖 manifest.name")
        XCTAssertEqual(instance.kind, .pack)
        XCTAssertEqual(instance.packName, "团队整合包")
        XCTAssertEqual(instance.packVersion, "1.0.0")
        XCTAssertEqual(instance.dshVersion, "0.2.1-rc.5")
        XCTAssertNotEqual(instance.id, fixture.instance.id, "导入必须生成新的实例 ID")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.paths.cliScript(for: instance.id).path),
            "导入后实例应有 DSH 入口脚本"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.paths.versionDirectory(instance.id).appendingPathComponent("package.json").path
            )
        )
        XCTAssertEqual(fixture.settings.dshSelectedInstanceID, instance.id, "导入后应自动选中新实例")
        XCTAssertEqual(fixture.service.state, .idle)
        XCTAssertNil(fixture.service.lastError)
        XCTAssertEqual(fixture.versions.installed.first(where: { $0.id == instance.id })?.kind, .pack)
        XCTAssertEqual(fixture.versions.selectedInstalledVersion?.id, instance.id)
    }

    @MainActor
    func testImportWithoutCustomNameFallsBackToManifestName() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let pack = try await exportBundledPack(from: fixture, name: "manifest 里的名字", version: "1.0.0")

        let imported = await fixture.service.importPack(from: pack, customName: "   ")
        let instance = try XCTUnwrap(imported)
        XCTAssertEqual(instance.name, "manifest 里的名字", "空白自定义名应回退到 manifest.name")
        XCTAssertEqual(instance.kind, .pack)
    }

    @MainActor
    func testImportSamePackTwiceCreatesTwoDistinctInstances() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let pack = try await exportBundledPack(from: fixture)

        let importedA = await fixture.service.importPack(from: pack, customName: "实例 A")
        let importedB = await fixture.service.importPack(from: pack, customName: "实例 B")
        let first = try XCTUnwrap(importedA)
        let second = try XCTUnwrap(importedB)

        XCTAssertNotEqual(first.id, second.id, "同一版本 / 同一整合包可以重复导入成多个实例")
        XCTAssertEqual(first.dshVersion, second.dshVersion)
        XCTAssertEqual(first.kind, .pack)
        XCTAssertEqual(second.kind, .pack)
        XCTAssertEqual(first.packName, "可导入包")
        XCTAssertEqual(second.packName, "可导入包")

        let packInstances = fixture.versions.installed.filter(\.isPack)
        XCTAssertEqual(packInstances.count, 2, "重复导入应生成两个实例")
        XCTAssertEqual(Set(packInstances.map(\.id)), Set([first.id, second.id]))
        XCTAssertEqual(Set(packInstances.map(\.name)), Set(["实例 A", "实例 B"]))
        XCTAssertEqual(
            fixture.versions.instances(of: first.dshVersion).filter(\.isPack).count,
            2,
            "同一 DSH 版本下应有两个实例"
        )
        XCTAssertEqual(fixture.settings.dshSelectedInstanceID, second.id, "最后一次导入的实例被选中")
    }

    @MainActor
    func testUninstallImportedInstanceCleansDirectories() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let pack = try await exportBundledPack(from: fixture)
        let importedResult = await fixture.service.importPack(from: pack, customName: "待卸载实例")
        let imported = try XCTUnwrap(importedResult)

        let home = fixture.paths.homeDirectory(for: imported.id)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("profiles/web"),
            withIntermediateDirectories: true
        )
        try Data("session".utf8).write(to: home.appendingPathComponent("profiles/web/session.json"))

        XCTAssertTrue(fixture.versions.uninstall(imported.id))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.paths.versionDirectory(imported.id).path),
            "卸载后实例目录应被删除"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: home.path),
            "卸载后实例独立 DSH_HOME 应被清理"
        )
        XCTAssertFalse(fixture.versions.installed.contains { $0.id == imported.id })
    }

    // MARK: - 非法整合包

    @MainActor
    func testImportEmptyArchiveFails() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let archive = fixture.root.appendingPathComponent("empty.dshpack")
        try makeEmptyZip(at: archive)

        let result = await fixture.service.importPack(from: archive)
        XCTAssertNil(result)
        guard case .failed(let message) = fixture.service.state else {
            return XCTFail("空 zip 导入应进入 failed 态：\(fixture.service.state)")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertNotNil(fixture.service.lastError)
        XCTAssertFalse(fixture.service.state.isBusy)
        XCTAssertTrue(fixture.versions.installed.allSatisfy { !$0.isPack }, "失败导入不应创建实例")
    }

    @MainActor
    func testImportArchiveWithoutManifestFails() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let archive = fixture.root.appendingPathComponent("no-manifest.dshpack")
        try makeZip(files: ["readme.txt": Data("not a pack".utf8)], at: archive)

        let result = await fixture.service.importPack(from: archive)
        XCTAssertNil(result)
        XCTAssertEqual(fixture.service.lastError, .missingManifest)
        guard case .failed = fixture.service.state else {
            return XCTFail("缺少 manifest 应进入 failed 态：\(fixture.service.state)")
        }
        XCTAssertTrue(fixture.versions.installed.allSatisfy { !$0.isPack })
    }

    @MainActor
    func testImportBundledPackWithoutRuntimeFails() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let archive = fixture.root.appendingPathComponent("no-runtime.dshpack")
        try makeZip(files: [DSHPackFormat.manifestName: manifestJSON()], at: archive)

        let result = await fixture.service.importPack(from: archive)
        XCTAssertNil(result)
        XCTAssertEqual(fixture.service.lastError, .missingRuntime)
        guard case .failed = fixture.service.state else {
            return XCTFail("缺少运行时应进入 failed 态：\(fixture.service.state)")
        }
    }

    @MainActor
    func testImportRejectsUnsafePluginPayloadPath() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let manifest = DSHPackManifest(
            name: "恶意包",
            version: "1.0.0",
            dshVersion: "0.2.1-rc.5",
            runtime: .bundled,
            plugins: [
                DSHPackPlugin(name: "evil", spec: "evil@1.0.0", version: "1.0.0", payload: "../evil.tgz")
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let archive = fixture.root.appendingPathComponent("unsafe.dshpack")
        try makeZip(
            files: [
                DSHPackFormat.manifestName: try encoder.encode(manifest),
                "payload/runtime/node_modules/@deepseek-ai/dsh/lib/bin.js": Data("// bin".utf8),
                "payload/runtime/package.json": Data("{}".utf8)
            ],
            at: archive
        )

        let result = await fixture.service.importPack(from: archive)
        XCTAssertNil(result)
        XCTAssertEqual(fixture.service.lastError, .unsafePath("../evil.tgz"))
        guard case .failed = fixture.service.state else {
            return XCTFail("不安全路径应进入 failed 态：\(fixture.service.state)")
        }
    }

    @MainActor
    func testImportRejectsWrongFormatIdentifier() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let archive = fixture.root.appendingPathComponent("wrong-format.dshpack")
        try makeZip(files: [DSHPackFormat.manifestName: manifestJSON(format: "other.vendor.pack")], at: archive)

        let result = await fixture.service.importPack(from: archive)
        XCTAssertNil(result)
        XCTAssertEqual(fixture.service.lastError, .invalidPackage("未知格式标识 other.vendor.pack"))
    }

    @MainActor
    func testImportRejectsUnsupportedFormatVersion() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let archive = fixture.root.appendingPathComponent("future.dshpack")
        try makeZip(files: [DSHPackFormat.manifestName: manifestJSON(formatVersion: 99)], at: archive)

        let result = await fixture.service.importPack(from: archive)
        XCTAssertNil(result)
        XCTAssertEqual(fixture.service.lastError, .unsupportedVersion(99))
    }

    @MainActor
    func testImportRejectsUnsafeDSHVersion() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let archive = fixture.root.appendingPathComponent("unsafe-version.dshpack")
        try makeZip(
            files: [DSHPackFormat.manifestName: manifestJSON(dshVersion: "../../evil")],
            at: archive
        )

        let result = await fixture.service.importPack(from: archive)
        XCTAssertNil(result)
        guard case .failed = fixture.service.state else {
            return XCTFail("非法 DSH 版本号应进入 failed 态：\(fixture.service.state)")
        }
        XCTAssertNotNil(fixture.service.lastError)
    }

    // MARK: - P1 回归：导入回滚 / 离线载荷 / 取消 / symlink / 原子导出

    /// P1 回归：导入中途失败（插件安装失败）必须回滚半成品实例，不能留下脏实例、
    /// 不能改变原选中项，versions/home/logs 下不能有残留。
    @MainActor
    func testImportFailureRollsBackPartialInstance() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let existingIDs = Set(fixture.versions.installed.map(\.id))
        let previousSelection = fixture.settings.dshSelectedInstanceID
        XCTAssertFalse(previousSelection.isEmpty, "夹具应已自动选中源实例")
        XCTAssertTrue(existingIDs.contains(previousSelection))

        // bundled 小包：合法假 runtime + 一个非法插件 spec（"-evil" 在安装前即被拒绝，不联网）。
        let archive = try makeBundledArchiveWithInvalidPlugin(in: fixture, fileName: "rollback.dshpack")
        let result = await fixture.service.importPack(from: archive, customName: "半成品实例")

        XCTAssertNil(result)
        XCTAssertFalse(fixture.service.state.isBusy)
        guard case .failed(let message) = fixture.service.state else {
            return XCTFail("导入失败应进入 failed 态：\(fixture.service.state)")
        }
        XCTAssertTrue(message.contains("-evil") || message.contains("插件"), "失败信息应指出插件安装问题：\(message)")
        XCTAssertTrue(
            fixture.service.logLines.contains { $0.contains("已回滚未完成的导入") },
            "应记录回滚日志：\(fixture.service.logLines)"
        )

        // 不新增实例、原实例目录仍存在、没有 .pack 脏实例。
        XCTAssertEqual(Set(fixture.versions.installed.map(\.id)), existingIDs)
        XCTAssertTrue(fixture.versions.installed.allSatisfy { !$0.isPack })
        XCTAssertEqual(contentsNames(fixture.paths.versionsDirectory), existingIDs)
        XCTAssertTrue(contentsNames(fixture.paths.homesDirectory).isEmpty, "回滚后不应残留实例 home")
        XCTAssertTrue(contentsNames(fixture.paths.logsDirectory).isEmpty, "回滚后不应残留实例日志")
        // 选中项恢复到导入前。
        XCTAssertEqual(fixture.settings.dshSelectedInstanceID, previousSelection)
    }

    /// P1 回归：导入已经创建半成品实例后调用 `cancel()`，必须回滚该实例（版本目录 / home / 日志），
    /// 恢复原选中项，最终状态收敛为 failed("操作已取消") 而不是留在 importing。
    ///
    /// 构造：包内第一个插件带离线载荷（安装时执行假入口脚本，脚本故意 sleep 800ms），
    /// 第二个插件 spec 非法；测试等到「安装插件」日志出现（此时导入已 adopt 实例并挂在插件子进程上）
    /// 再 cancel → 下一个插件循环的 `Task.checkCancellation()` 抛出 CancellationError → rollbackImport。
    @MainActor
    func testCancelDuringImportRollsBackCreatedInstance() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let existingIDs = Set(fixture.versions.installed.map(\.id))
        let previousSelection = fixture.settings.dshSelectedInstanceID
        let slowEntry = "setTimeout(() => process.exit(0), 800);"
        let payloadName = "plugin-a-1.2.3.tgz"
        let archive = try makeBundledArchive(
            in: fixture,
            fileName: "cancel.dshpack",
            plugins: [
                DSHPackPlugin(
                    name: "@test/plugin-a",
                    spec: "@test/plugin-a@1.2.3",
                    version: "1.2.3",
                    payload: "payload/plugins/\(payloadName)"
                ),
                DSHPackPlugin(name: "@test/evil", spec: "-evil")
            ],
            additionalFiles: ["payload/plugins/\(payloadName)": Data("payload".utf8)],
            entryScript: slowEntry
        )

        let task = Task { await fixture.service.importPack(from: archive, customName: "取消实例") }
        // 等到半成品实例已创建、插件子进程已启动（假入口脚本会 sleep 800ms，窗口充足）。
        var waited = 0
        while !fixture.service.logLines.contains(where: { $0.contains("安装插件 @test/plugin-a") }), waited < 300 {
            try? await Task.sleep(nanoseconds: 5_000_000)
            waited += 1
        }
        XCTAssertTrue(
            fixture.service.logLines.contains { $0.contains("安装插件 @test/plugin-a") },
            "取消前应已开始安装插件（导入已创建实例）：\(fixture.service.logLines)"
        )
        fixture.service.cancel()
        let result = await task.value

        XCTAssertNil(result)
        XCTAssertFalse(fixture.service.state.isBusy, "取消后不能停留在 importing / exporting 态")
        guard case .failed = fixture.service.state else {
            return XCTFail("取消后应进入 failed 态：\(fixture.service.state)")
        }
        XCTAssertEqual(fixture.service.lastError, .cancelled, "取消命中 Task.checkCancellation 后应记为 cancelled")
        // 已按 CancellationError 回滚：不能留下半成品实例 / home / 日志。
        XCTAssertEqual(Set(fixture.versions.installed.map(\.id)), existingIDs)
        XCTAssertTrue(fixture.versions.installed.allSatisfy { !$0.isPack })
        XCTAssertEqual(contentsNames(fixture.paths.versionsDirectory), existingIDs)
        XCTAssertTrue(contentsNames(fixture.paths.homesDirectory).isEmpty, "取消回滚不应残留实例 home")
        XCTAssertTrue(contentsNames(fixture.paths.logsDirectory).isEmpty)
        XCTAssertEqual(fixture.settings.dshSelectedInstanceID, previousSelection)
        XCTAssertTrue(
            fixture.service.logLines.contains { $0.contains("已回滚未完成的导入") },
            "取消后应记录回滚日志：\(fixture.service.logLines)"
        )
    }

    /// P1 回归：导入插件 payload 时必须把它持久化到 `homes/<实例ID>/plugin-payloads/` 并写 index.json，
    /// 且用该稳定路径安装（staging 删除后不失效）；随后再次导出可复用该本地载荷。
    @MainActor
    func testImportPersistsOfflinePluginPayload() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let payloadName = "plugin-a-1.2.3.tgz"
        let payloadBytes = Data("offline-plugin-tarball".utf8)
        let payloadRelPath = "payload/plugins/\(payloadName)"
        let archive = try makeBundledArchive(
            in: fixture,
            fileName: "import-payload.dshpack",
            plugins: [
                DSHPackPlugin(
                    name: "@test/plugin-a",
                    spec: "@test/plugin-a@1.2.3",
                    version: "1.2.3",
                    payload: payloadRelPath
                )
            ],
            additionalFiles: [payloadRelPath: payloadBytes]
        )

        let imported = await fixture.service.importPack(from: archive, customName: "载荷实例")
        let instance = try XCTUnwrap(imported, "带离线载荷的 bundled 包应导入成功：\(String(describing: fixture.service.lastError))")
        XCTAssertEqual(instance.kind, .pack)
        XCTAssertEqual(fixture.service.state, .idle)

        // 载荷被复制到实例 home 的稳定目录 + index.json 记录 name→filename。
        let payloads = fixture.paths.homeDirectory(for: instance.id)
            .appendingPathComponent("plugin-payloads", isDirectory: true)
        let expectedFilename = "test-plugin-a-\(payloadName)"  // safePayloadStem: 去掉 @、/→-
        XCTAssertTrue(
            contentsNames(payloads).contains(expectedFilename),
            "实例 home 应持久化离线载荷：\(contentsNames(payloads))"
        )
        XCTAssertEqual(
            try Data(contentsOf: payloads.appendingPathComponent(expectedFilename)),
            payloadBytes
        )
        let indexData = try Data(contentsOf: payloads.appendingPathComponent("index.json"))
        let index = try JSONDecoder().decode([String: String].self, from: indexData)
        XCTAssertEqual(index["@test/plugin-a"], expectedFilename)

        // 模拟真实 dsh 装完插件后写入 web profile 的 file: 依赖（指向持久化载荷）。
        let profile = fixture.paths.profileDirectory(for: instance.id)
        let pluginPackage = profile.appendingPathComponent("node_modules/@test/plugin-a")
        try FileManager.default.createDirectory(at: pluginPackage, withIntermediateDirectories: true)
        try Data(#"{"name":"@test/plugin-a","version":"1.2.3"}"#.utf8)
            .write(to: pluginPackage.appendingPathComponent("package.json"))
        let stablePayload = payloads.appendingPathComponent(expectedFilename)
        let profileManifest = try JSONSerialization.data(withJSONObject: [
            "name": "dsh-profile-web",
            "private": true,
            "dependencies": ["@test/plugin-a": "file:\(stablePayload.path)"]
        ])
        try profileManifest.write(to: profile.appendingPathComponent("package.json"))

        // 用该实例再导出（online + 离线载荷）：应直接复用 home 里持久化的 tgz。
        let reexport = fixture.root.appendingPathComponent("reexport.dshpack")
        let exported = await fixture.service.exportPack(
            instance: instance,
            name: "再导出",
            version: "2.0.0",
            description: "",
            author: "",
            runtime: .online,
            includePluginPayloads: true,
            to: reexport
        )
        XCTAssertNotNil(exported)
        let manifest = try readManifest(from: reexport)
        let plugin = try XCTUnwrap(manifest.plugins.first)
        XCTAssertEqual(plugin.name, "@test/plugin-a")
        XCTAssertEqual(plugin.payload, "payload/plugins/\(expectedFilename)")
        XCTAssertTrue(try zipEntries(reexport).contains("payload/plugins/\(expectedFilename)"))
    }

    /// P1 回归：导入时持久化到 `homes/<id>/plugin-payloads/` 的离线 tgz（含 index.json）
    /// 必须能在再次导出时被找回并打进新包的 `payload/plugins/`，且 `file:` 依赖不再被跳过。
    @MainActor
    func testOfflinePluginPayloadIndexIsReexported() async throws {
        let fixture = try makeFixture(withPlugins: true)
        let instanceID = fixture.instance.id
        let profile = fixture.paths.profileDirectory(for: instanceID)

        // 导入插件后 pnpm 在 profile 里记录的是 file: 本地 tarball。
        try Data(
            #"{"name":"dsh-profile-web","private":true,"dependencies":{"@test/plugin-a":"file:/tmp/dsh-plugin-a-1.2.3.tgz"}}"#.utf8
        ).write(to: profile.appendingPathComponent("package.json"))

        // DSHPackService 导入时持久化的离线载荷目录 + 索引。
        let payloads = fixture.paths.homeDirectory(for: instanceID)
            .appendingPathComponent("plugin-payloads", isDirectory: true)
        try FileManager.default.createDirectory(at: payloads, withIntermediateDirectories: true)
        let tgzName = "@test-plugin-a-1.2.3.tgz"
        let tgzBytes = Data("fake-plugin-tarball-bytes".utf8)
        try tgzBytes.write(to: payloads.appendingPathComponent(tgzName))
        try Data(#"{"@test/plugin-a":"@test-plugin-a-1.2.3.tgz"}"#.utf8)
            .write(to: payloads.appendingPathComponent("index.json"))

        let destination = fixture.root.appendingPathComponent("offline-payload.dshpack")
        let exported = await fixture.service.exportPack(
            instance: fixture.instance,
            name: "带离线载荷的实例",
            version: "1.0.0",
            description: "",
            author: "",
            runtime: .online,
            includePluginPayloads: true,
            to: destination
        )

        XCTAssertNotNil(exported)
        XCTAssertEqual(fixture.service.state, .idle)
        XCTAssertNil(fixture.service.lastError)

        let payloadPath = "\(DSHPackFormat.pluginsPath)/\(tgzName)"
        let entries = try zipEntries(destination)
        XCTAssertTrue(entries.contains(payloadPath), "新包应包含复用的离线载荷：\(entries)")

        let manifest = try readManifest(from: destination)
        XCTAssertEqual(manifest.plugins.count, 1)
        let plugin = try XCTUnwrap(manifest.plugins.first)
        XCTAssertEqual(plugin.name, "@test/plugin-a", "file: 依赖不应被 profilePlugins 跳过")
        XCTAssertEqual(plugin.version, "1.2.3")
        XCTAssertEqual(plugin.spec, "@test/plugin-a@1.2.3")
        XCTAssertEqual(plugin.payload, payloadPath, "离线载荷应来自 plugin-payloads/index.json")

        // 复用的 tgz 内容与实例 home 内持久化的文件一致。
        let extracted = try runTool("/usr/bin/unzip", ["-p", destination.path, payloadPath])
        XCTAssertEqual(extracted.status, 0)
        XCTAssertEqual(Data(extracted.output.utf8), tgzBytes)
    }

    /// 安全回归：解压后若载荷内含指向绝对路径 / 逃逸出包目录的符号链接，必须拒绝导入且无实例残留。
    @MainActor
    func testImportRejectsSymlinkEscapeInRuntime() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let existingIDs = Set(fixture.versions.installed.map(\.id))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(
            DSHPackManifest(
                name: "symlink 包",
                version: "1.0.0",
                dshVersion: "0.2.1-rc.5",
                runtime: .bundled,
                plugins: []
            )
        )
        let runtimeFiles: [String: Data] = [
            DSHPackFormat.manifestName: manifestData,
            "payload/runtime/node_modules/@deepseek-ai/dsh/lib/bin.js": Data("// bin".utf8),
            "payload/runtime/package.json": Data("{}".utf8)
        ]

        // 1) 绝对路径符号链接
        let absoluteArchive = fixture.root.appendingPathComponent("symlink-absolute.dshpack")
        try makeZip(
            files: runtimeFiles,
            symlinks: ["payload/runtime/escape": "/etc/passwd"],
            at: absoluteArchive
        )
        let absoluteResult = await fixture.service.importPack(from: absoluteArchive)
        XCTAssertNil(absoluteResult)
        guard case .unsafePath(let absoluteTarget)? = fixture.service.lastError else {
            return XCTFail("绝对路径符号链接应被拒绝：\(String(describing: fixture.service.lastError))")
        }
        XCTAssertTrue(absoluteTarget.contains("/etc/passwd"), "错误信息应包含链接目标：\(absoluteTarget)")
        guard case .failed = fixture.service.state else {
            return XCTFail("symlink 包导入应进入 failed 态：\(fixture.service.state)")
        }

        // 2) 相对路径逃逸符号链接
        let relativeArchive = fixture.root.appendingPathComponent("symlink-relative.dshpack")
        try makeZip(
            files: runtimeFiles,
            symlinks: ["payload/runtime/escape": "../../../etc/passwd"],
            at: relativeArchive
        )
        let relativeResult = await fixture.service.importPack(from: relativeArchive)
        XCTAssertNil(relativeResult)
        guard case .unsafePath(let relativeTarget)? = fixture.service.lastError else {
            return XCTFail("逃逸符号链接应被拒绝：\(String(describing: fixture.service.lastError))")
        }
        XCTAssertTrue(relativeTarget.contains("逃逸"), "错误信息应说明链接逃逸：\(relativeTarget)")

        // 两次失败都不应留下实例 / 目录。
        XCTAssertEqual(Set(fixture.versions.installed.map(\.id)), existingIDs)
        XCTAssertEqual(contentsNames(fixture.paths.versionsDirectory), existingIDs)
        XCTAssertTrue(contentsNames(fixture.paths.homesDirectory).isEmpty)
        XCTAssertTrue(contentsNames(fixture.paths.logsDirectory).isEmpty)
    }

    /// 原子导出回归：目标位置已有旧包（非法字节）时，导出应替换成可读的新包，且不残留临时 zip。
    @MainActor
    func testExportAtomicallyReplacesExistingArchive() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let destination = fixture.root.appendingPathComponent("atomic.dshpack")
        try Data("not-a-zip-old-content".utf8).write(to: destination)

        let exported = await fixture.service.exportPack(
            instance: fixture.instance,
            name: "原子导出",
            version: "1.0.0",
            description: "",
            author: "",
            runtime: .online,
            includePluginPayloads: false,
            to: destination
        )

        XCTAssertEqual(exported?.standardizedFileURL.path, destination.standardizedFileURL.path)
        XCTAssertEqual(fixture.service.state, .idle)
        // 旧字节已被完整替换成合法 zip。
        let entries = try zipEntries(destination)
        XCTAssertTrue(entries.contains(DSHPackFormat.manifestName), "替换后应是合法整合包：\(entries)")
        let manifest = try readManifest(from: destination)
        XCTAssertEqual(manifest.name, "原子导出")
        XCTAssertNotEqual(try Data(contentsOf: destination), Data("not-a-zip-old-content".utf8))

        // 临时 zip（.<name>.tmp-<uuid>）不应残留。
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: fixture.root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".\(destination.lastPathComponent).tmp-") }
        XCTAssertTrue(leftovers.isEmpty, "导出后不应残留临时文件：\(leftovers.map(\.lastPathComponent))")
    }

    /// P1 回归：online 导入安装失败时不得把「同名 / 同版本」的既有 vanillla 实例误 adopt 成 pack，
    /// 也不得新增或替换实例。npm 用 offline + 临时 cache/logs，失败快且不访问网络 / 不写用户主目录。
    @MainActor
    func testOnlineImportFailureKeepsExistingInstanceUntouched() async throws {
        let fixture = try makeFixture(withPlugins: false)
        let existing = fixture.instance
        let existingIDs = Set(fixture.versions.installed.map(\.id))
        let previousSelection = fixture.settings.dshSelectedInstanceID
        XCTAssertEqual(fixture.versions.installed.first(where: { $0.id == existing.id })?.kind, .vanilla)

        // 让 npm 只做本地缓存查找（offline），且 cache/logs 落在临时目录里。
        let npmSandbox = fixture.root.appendingPathComponent("npm-sandbox", isDirectory: true)
        try FileManager.default.createDirectory(at: npmSandbox, withIntermediateDirectories: true)
        let npmEnvironment: [(String, String)] = [
            ("npm_config_offline", "true"),
            ("npm_config_registry", "http://127.0.0.1:1"),
            ("npm_config_cache", npmSandbox.appendingPathComponent("cache").path),
            ("npm_config_logs_dir", npmSandbox.appendingPathComponent("logs").path),
            ("npm_config_update_notifier", "false")
        ]
        let savedEnvironment = npmEnvironment.map { ($0.0, ProcessInfo.processInfo.environment[$0.0]) }
        for (key, value) in npmEnvironment { setenv(key, value, 1) }
        defer {
            for (key, old) in savedEnvironment {
                if let old { setenv(key, old, 1) } else { unsetenv(key) }
            }
        }

        // online 包：引用不存在的 npm 版本，安装必然失败；manifest name 与既有实例同名（旧实现会误命中它）。
        let archive = fixture.root.appendingPathComponent("online-guard.dshpack")
        try makeZip(
            files: [
                DSHPackFormat.manifestName: manifestJSON(
                    name: existing.name,
                    dshVersion: "99.99.99",
                    runtime: "online"
                )
            ],
            at: archive
        )

        let result = await fixture.service.importPack(from: archive, customName: existing.name)
        XCTAssertNil(result, "不存在版本 99.99.99 的在线导入应失败")
        guard case .failed = fixture.service.state else {
            return XCTFail("在线导入失败应进入 failed 态：\(fixture.service.state)")
        }

        // 既有实例原样保留：kind 仍是 vanilla、未被改成 pack、版本/名字不变。
        let after = try XCTUnwrap(fixture.versions.installed.first(where: { $0.id == existing.id }))
        XCTAssertEqual(after.kind, .vanilla, "既有 vanilla 实例不能被在线导入改成 pack")
        XCTAssertNil(after.packName)
        XCTAssertEqual(after.dshVersion, existing.dshVersion)
        XCTAssertEqual(after.name, existing.name)
        XCTAssertEqual(Set(fixture.versions.installed.map(\.id)), existingIDs, "失败的在线导入不能新增/替换实例")
        XCTAssertEqual(fixture.settings.dshSelectedInstanceID, previousSelection)
        XCTAssertTrue(contentsNames(fixture.paths.homesDirectory).isEmpty)
        XCTAssertTrue(contentsNames(fixture.paths.logsDirectory).isEmpty)
    }

    // MARK: - 测试环境

    /// 临时 DSH 目录 + 假实例，所有路径都在系统临时目录下（tearDown 自动清理）。
    private struct Fixture {
        let root: URL
        let paths: DSHPaths
        let settings: LauncherSettings
        let versions: DSHVersionStore
        let plugins: DSHPluginStore
        let service: DSHPackService
        let instance: DSHInstalledVersion
    }

    @MainActor
    private func makeFixture(withPlugins: Bool) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dshpack-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let paths = DSHPaths(root: root)
        try paths.ensureDirectories()

        // 假实例目录：versions/<实例 ID>/node_modules/@deepseek-ai/dsh/lib/bin.js + package.json
        let instanceID = "instance-\(UUID().uuidString.lowercased())"
        let versionDirectory = paths.versionDirectory(instanceID)
        try FileManager.default.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
        try Data(#"{"name":"dsh-instance","private":true}"#.utf8)
            .write(to: versionDirectory.appendingPathComponent("package.json"))
        let bin = paths.cliScript(for: instanceID)
        try FileManager.default.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/usr/bin/env node\n// fake dsh entry\n".utf8).write(to: bin)

        if withPlugins {
            // 假 profile：web profile 的 package.json 记录了已安装插件。
            let profile = paths.profileDirectory(for: instanceID)
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            try Data(
                #"{"name":"dsh-profile-web","private":true,"dependencies":{"@test/plugin-a":"1.2.3"}}"#.utf8
            ).write(to: profile.appendingPathComponent("package.json"))
            let pluginDirectory = profile.appendingPathComponent("node_modules/@test/plugin-a")
            try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
            try Data(#"{"name":"@test/plugin-a","version":"1.2.3"}"#.utf8)
                .write(to: pluginDirectory.appendingPathComponent("package.json"))
        }

        let settings = makeTemporarySettings()
        let versions = DSHVersionStore(settings: settings, paths: paths)
        let plugins = DSHPluginStore(settings: settings, paths: paths)
        let service = DSHPackService(paths: paths, versions: versions, plugins: plugins, settings: settings)
        let instance = DSHInstalledVersion(
            id: instanceID,
            name: "源实例",
            dshVersion: "0.2.1-rc.5",
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            path: versionDirectory.path,
            sizeBytes: 4096,
            kind: .vanilla
        )
        try JSONEncoder().encode(instance)
            .write(to: versionDirectory.appendingPathComponent("launcher-install.json"))
        versions.refreshInstalled()

        return Fixture(
            root: root,
            paths: paths,
            settings: settings,
            versions: versions,
            plugins: plugins,
            service: service,
            instance: instance
        )
    }

    @MainActor
    private func makeTemporarySettings() -> LauncherSettings {
        let suite = "launcher.dshpack.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return LauncherSettings(defaults: defaults)
    }

    @MainActor
    private func exportBundledPack(
        from fixture: Fixture,
        name: String = "可导入包",
        version: String = "1.0.0"
    ) async throws -> URL {
        let destination = fixture.root.appendingPathComponent("\(UUID().uuidString).dshpack")
        let exported = await fixture.service.exportPack(
            instance: fixture.instance,
            name: name,
            version: version,
            description: "",
            author: "",
            runtime: .bundled,
            includePluginPayloads: false,
            to: destination
        )
        return try XCTUnwrap(
            exported,
            "导出 bundled 整合包失败：\(String(describing: fixture.service.lastError))"
        )
    }

    // MARK: - zip / 命令辅助

    private struct ToolResult {
        let status: Int32
        let output: String
    }

    /// 运行系统命令并收集 stdout（stderr 丢弃），仅用于测试里的 zip / unzip。
    private func runTool(
        _ executable: String,
        _ arguments: [String],
        workingDirectory: URL? = nil
    ) throws -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ToolResult(
            status: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
        )
    }

    /// 列出 zip 内条目（`unzip -Z1`）。
    private func zipEntries(_ archive: URL) throws -> [String] {
        let result = try runTool("/usr/bin/unzip", ["-Z1", archive.path])
        XCTAssertEqual(result.status, 0, "读取 zip 条目失败：\(result.output)")
        return result.output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// 读取 zip 里的 manifest.json。
    private func readManifest(from archive: URL) throws -> DSHPackManifest {
        let result = try runTool("/usr/bin/unzip", ["-p", archive.path, DSHPackFormat.manifestName])
        XCTAssertEqual(result.status, 0, "读取 manifest.json 失败：\(result.output)")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DSHPackManifest.self, from: Data(result.output.utf8))
    }

    /// 把给定文件 / 符号链接写进一个临时目录再压缩成 zip（`-y` 保留符号链接）。
    private func makeZip(
        files: [String: Data],
        symlinks: [String: String] = [:],
        at destination: URL
    ) throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("DSHPackTestZip-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for (relativePath, data) in files {
            let url = staging.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        for (relativePath, target) in symlinks {
            let url = staging.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let result = try runTool(
            "/usr/bin/zip",
            ["-q", "-r", "-y", "-1", destination.path, "."],
            workingDirectory: staging
        )
        XCTAssertEqual(result.status, 0, "构造测试 zip 失败：\(result.output)")
    }

    /// 压缩一个空目录（得到不含 manifest 的空 zip）。
    private func makeEmptyZip(at destination: URL) throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("DSHPackTestEmptyZip-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        // `zip -r dest . -i .` 是唯一能生成「空 zip」的调用方式（普通 zip 空目录会报 Nothing to do）。
        let result = try runTool(
            "/usr/bin/zip",
            ["-q", "-r", destination.path, ".", "-i", "."],
            workingDirectory: staging
        )
        XCTAssertEqual(result.status, 0, "构造空 zip 失败：\(result.output)")
    }

    /// 目录下的直接子项名字（目录不存在时返回空集合）。
    private func contentsNames(_ directory: URL) -> Set<String> {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return Set(urls.map(\.lastPathComponent))
    }

    /// 构造一个 bundled 整合包：合法假 runtime + 一个非法插件 spec（安装前即被拒绝，不联网）。
    /// 构造 bundled 整合包：假 runtime（入口脚本内容可定制）+ manifest 插件清单 + 可选附加文件。
    @MainActor
    private func makeBundledArchive(
        in fixture: Fixture,
        fileName: String,
        name: String = "测试整合包",
        version: String = "1.0.0",
        plugins: [DSHPackPlugin],
        additionalFiles: [String: Data] = [:],
        entryScript: String = "// bin"
    ) throws -> URL {
        var files = additionalFiles
        files["payload/runtime/node_modules/@deepseek-ai/dsh/lib/bin.js"] = Data(entryScript.utf8)
        files["payload/runtime/package.json"] = Data("{}".utf8)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifest = DSHPackManifest(
            name: name,
            version: version,
            dshVersion: fixture.instance.dshVersion,
            runtime: .bundled,
            plugins: plugins
        )
        files[DSHPackFormat.manifestName] = try encoder.encode(manifest)
        let archive = fixture.root.appendingPathComponent(fileName)
        try makeZip(files: files, at: archive)
        return archive
    }

    /// 用于验证导入失败时 `rollbackImport` 的回滚不变量。
    @MainActor
    private func makeBundledArchiveWithInvalidPlugin(
        in fixture: Fixture,
        fileName: String,
        pluginName: String = "@test/evil",
        spec: String = "-evil"
    ) throws -> URL {
        try makeBundledArchive(
            in: fixture,
            fileName: fileName,
            name: "回滚测试包",
            plugins: [DSHPackPlugin(name: pluginName, spec: spec)]
        )
    }

    /// 手写一份合法的 manifest JSON（用于非法路径 / 缺运行时等场景）。
    private func manifestJSON(
        format: String = DSHPackFormat.identifier,
        formatVersion: Int = DSHPackFormat.formatVersion,
        name: String = "手工构造包",
        version: String = "1.0.0",
        dshVersion: String = "0.2.1-rc.5",
        runtime: String = "bundled",
        pluginsJSON: String = "[]"
    ) -> Data {
        Data(
            """
            {
              "format": "\(format)",
              "formatVersion": \(formatVersion),
              "name": "\(name)",
              "version": "\(version)",
              "description": "",
              "author": "",
              "createdAt": "2026-11-03T12:00:00Z",
              "dshVersion": "\(dshVersion)",
              "runtime": "\(runtime)",
              "plugins": \(pluginsJSON)
            }
            """.utf8
        )
    }
}
