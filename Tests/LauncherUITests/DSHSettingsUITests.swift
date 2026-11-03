import XCTest
import SwiftUI
@testable import LauncherUI

/// DSH 设置页 / 更多页的逻辑测试：分区、输入校验、格式化、数据目录、缓存清理、
/// 数据删除、日志文件工具与进程状态文案。
final class DSHSettingsUITests: XCTestCase {

    // MARK: - 分区

    func testSettingsSectionsCoverAllCategories() {
        XCTAssertEqual(DSHSettingsSection.allCases.count, 4)
        XCTAssertEqual(DSHSettingsSection.allCases.map(\.title), ["启动", "下载与插件", "环境与目录", "关于"])
        for section in DSHSettingsSection.allCases {
            XCTAssertFalse(section.subtitle.isEmpty, "\(section) 缺少说明")
            XCTAssertFalse(section.systemImage.isEmpty, "\(section) 缺少图标")
        }
        XCTAssertEqual(DSHSettingsSection.resolve("plugins"), .plugins)
        XCTAssertEqual(DSHSettingsSection.resolve("environment"), .environment)
        XCTAssertNil(DSHSettingsSection.resolve("logs"))
        XCTAssertNil(DSHSettingsSection.resolve(nil))
    }

    func testMoreSectionsMatchSidePanel() {
        XCTAssertEqual(DSHMoreSection.allCases.count, 4)
        XCTAssertEqual(DSHMoreSection.allCases.map(\.title), ["运行日志", "数据目录", "进程", "关于"])
        for section in DSHMoreSection.allCases {
            XCTAssertFalse(section.subtitle.isEmpty)
            XCTAssertFalse(section.systemImage.isEmpty)
            XCTAssertFalse(section.groupTitle.isEmpty)
        }
        // 设置页「进程状态」按钮通过 rawValue 跳转
        XCTAssertEqual(DSHMoreSection(rawValue: "process"), .process)
        XCTAssertEqual(DSHMoreSection(rawValue: "logs"), .logs)
    }

    // MARK: - 输入校验

    func testPortValidation() {
        func value(_ text: String) -> Int? {
            if case .success(let port) = DSHInputValidation.port(from: text) { return port }
            return nil
        }
        XCTAssertEqual(value("0"), 0)
        XCTAssertEqual(value("3080"), 3080)
        XCTAssertEqual(value(" 8080 "), 8080)
        XCTAssertEqual(value("65535"), 65535)
        XCTAssertNil(value(""))
        XCTAssertNil(value("   "))
        XCTAssertNil(value("-1"))
        XCTAssertNil(value("65536"))
        XCTAssertNil(value("abc"))
        XCTAssertNil(value("30.80"))

        guard case .failure(.emptyPort) = DSHInputValidation.port(from: "") else {
            return XCTFail("空端口应报 emptyPort")
        }
        guard case .failure(.invalidPort) = DSHInputValidation.port(from: "99999") else {
            return XCTFail("越界端口应报 invalidPort")
        }
    }

    func testRegistryValidation() {
        XCTAssertEqual(try? DSHInputValidation.registry(from: "").get(), "")
        XCTAssertEqual(try? DSHInputValidation.registry(from: "  ").get(), "")
        XCTAssertEqual(
            try? DSHInputValidation.registry(from: "https://registry.npmmirror.com").get(),
            "https://registry.npmmirror.com"
        )
        XCTAssertNil(try? DSHInputValidation.registry(from: "registry.npmjs.org").get())
        XCTAssertNil(try? DSHInputValidation.registry(from: "ftp://example.com").get())

        XCTAssertTrue(DSHInputValidation.registryDisplayText("").contains(DSHRegistryClient.defaultRegistry))
        XCTAssertTrue(DSHInputValidation.registryDisplayText("").contains("官方"))
        XCTAssertEqual(
            DSHInputValidation.registryDisplayText("https://registry.npmmirror.com"),
            "https://registry.npmmirror.com"
        )
    }

    func testPluginSourceValidation() {
        XCTAssertEqual(
            try? DSHInputValidation.pluginSource(from: " https://awesome-dsh-plugin.com/plugins.json ").get(),
            "https://awesome-dsh-plugin.com/plugins.json"
        )
        XCTAssertNil(try? DSHInputValidation.pluginSource(from: "").get())
        XCTAssertNil(try? DSHInputValidation.pluginSource(from: "awesome-dsh-plugin.com").get())
        XCTAssertNil(try? DSHInputValidation.pluginSource(from: "file:///tmp/plugins.json").get())

        // 默认插件加载源必须与 dshmarket 使用的地址一致
        XCTAssertEqual(
            DSHRegistryClient.defaultPluginSource,
            "https://awesome-dsh-plugin.com/plugins.json"
        )
    }

    // MARK: - 格式化

    func testFormattingHelpers() {
        XCTAssertEqual(DSHFormatting.portText(0), "自动")
        XCTAssertEqual(DSHFormatting.portText(3080), "3080")
        let empty = DSHFormatting.installedSummary([])
        XCTAssertTrue(empty.contains("还没有安装"))

        let versions = [
            DSHInstalledVersion(version: "0.42.0", installedAt: Date(), path: "/tmp/a", sizeBytes: 1024 * 1024),
            DSHInstalledVersion(version: "0.41.0", installedAt: Date(), path: "/tmp/b", sizeBytes: 2 * 1024 * 1024)
        ]
        let summary = DSHFormatting.installedSummary(versions)
        XCTAssertTrue(summary.contains("2 个实例"))
        XCTAssertTrue(summary.contains("共"))
    }

    func testRedactedURLHidesToken() {
        let raw = "http://127.0.0.1:3080/?token=super-secret-token"
        let redacted = DSHFormatting.redactedURL(raw)
        XCTAssertNotNil(redacted)
        XCTAssertFalse(redacted?.contains("super-secret-token") ?? true, "token 不应明文展示")
        XCTAssertTrue(redacted?.contains("token=***") ?? false)
        XCTAssertTrue(redacted?.contains("3080") ?? false)

        XCTAssertEqual(
            DSHFormatting.redactedURL("http://127.0.0.1:3080/"),
            "http://127.0.0.1:3080/"
        )
        XCTAssertNil(DSHFormatting.redactedURL(nil))
        XCTAssertNil(DSHFormatting.redactedURL(""))
    }

    // MARK: - 运行时环境

    func testRuntimeEnvironmentSummaryAndRows() {
        let ready = DSHRuntimeEnvironment(
            node: "/opt/homebrew/bin/node",
            pnpm: "/opt/homebrew/bin/pnpm",
            npm: "/opt/homebrew/bin/npm",
            bundledNode: nil,
            packageManager: "pnpm"
        )
        XCTAssertTrue(ready.summary.contains("Node"))
        XCTAssertTrue(ready.summary.contains("pnpm"))
        XCTAssertEqual(ready.rows.count, 5)
        XCTAssertEqual(ready.rows.first?.id, "node")
        XCTAssertFalse(ready.rows[0].isMissing)
        XCTAssertTrue(ready.rows[3].isMissing, "没有桌面端时 DSH 自带 Node 应标记未找到")

        let missing = DSHRuntimeEnvironment(
            node: nil,
            pnpm: nil,
            npm: nil,
            bundledNode: nil,
            packageManager: nil
        )
        XCTAssertTrue(missing.summary.contains("未找到 Node.js"))
        XCTAssertTrue(missing.rows.allSatisfy { $0.isMissing })
    }

    // MARK: - 数据目录

    func testDataDirectoriesReportRealSizes() throws {
        let paths = try makeTemporaryPaths()
        try paths.ensureDirectories()
        // versions 下放一个 3KB 的假版本文件
        let versionFile = paths.versionsDirectory.appendingPathComponent("0.42.0/data.bin")
        try FileManager.default.createDirectory(
            at: versionFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0xAB, count: 3 * 1024).write(to: versionFile)
        // 某个实例的独立 DSH_HOME 下放一个 1KB 的用户数据文件
        let instanceHome = paths.homeDirectory(for: "0.42.0")
        try FileManager.default.createDirectory(at: instanceHome, withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 1024).write(to: instanceHome.appendingPathComponent("key.json"))

        let rows = DSHDataTools.directories(paths: paths)
        XCTAssertEqual(rows.count, DSHDataDirectoryKind.allCases.count)
        let versionsRow = try XCTUnwrap(rows.first { $0.kind == .versions })
        XCTAssertTrue(versionsRow.exists)
        XCTAssertGreaterThanOrEqual(versionsRow.bytes, 3 * 1024)
        XCTAssertFalse(versionsRow.sizeText.isEmpty)

        // homes 项是所有实例 home 的根目录（每个实例一个子目录）
        let homeRow = try XCTUnwrap(rows.first { $0.kind == .homes })
        XCTAssertEqual(homeRow.path, paths.homesDirectory.path)
        XCTAssertTrue(homeRow.title.contains("homes"))
        XCTAssertGreaterThanOrEqual(homeRow.bytes, 1024)
        XCTAssertTrue(DSHDataDirectoryKind.homes.title.contains("homes"))
        // 每个实例的 DSH_HOME 相互独立，但都位于 homes/ 下
        XCTAssertEqual(
            DSHDataTools.instanceHomePath(paths: paths, instanceID: "0.42.0"),
            instanceHome.path
        )
        XCTAssertNotEqual(
            paths.homeDirectory(for: "a"),
            paths.homeDirectory(for: "b")
        )
        XCTAssertEqual(paths.homeDirectory(for: "a").deletingLastPathComponent().path, paths.homesDirectory.path)
        XCTAssertNil(DSHDataTools.instanceHomePath(paths: paths, instanceID: nil))

        let notExisting = DSHDataDirectory(kind: .bin, path: "/nonexistent", bytes: 0, exists: false)
        XCTAssertEqual(notExisting.sizeText, "不存在")

        let installed = [
            DSHInstalledVersion(version: "a", installedAt: Date(), path: "/tmp/a", sizeBytes: 1024),
            DSHInstalledVersion(version: "b", installedAt: Date(), path: "/tmp/b", sizeBytes: nil)
        ]
        XCTAssertEqual(DSHDataTools.totalInstalledBytes(installed), 1024)
        XCTAssertEqual(
            DSHDataTools.profilePath(paths: paths, version: "0.42.0"),
            paths.profileDirectory(for: "0.42.0").path
        )
        XCTAssertNil(DSHDataTools.profilePath(paths: paths, version: nil))
        XCTAssertNil(DSHDataTools.profilePath(paths: paths, version: ""))
    }

    // MARK: - 缓存清理

    func testCacheMaintenanceReallyDeletesFiles() throws {
        let paths = try makeTemporaryPaths()
        try paths.ensureDirectories()
        let pluginsCache = paths.cacheDirectory.appendingPathComponent("plugins.json")
        let versionsCache = paths.cacheDirectory.appendingPathComponent("versions.json")
        try Data("{}".utf8).write(to: pluginsCache)
        try Data(repeating: 0x01, count: 512).write(to: versionsCache)

        XCTAssertEqual(DSHCacheMaintenance.cacheFiles(paths: paths).count, 2)
        let report = DSHCacheMaintenance.clearCache(paths: paths)
        XCTAssertEqual(report.removedFiles, 2)
        XCTAssertGreaterThanOrEqual(report.removedBytes, 512)
        XCTAssertTrue(report.failedFiles.isEmpty)
        XCTAssertTrue(report.summary.contains("已清理 2 个缓存文件"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pluginsCache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: versionsCache.path))
        // 目录本身保留，方便下次重新写入缓存
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.cacheDirectory.path))

        // 再次清理：没有文件，不报错
        let second = DSHCacheMaintenance.clearCache(paths: paths)
        XCTAssertEqual(second.removedFiles, 0)
        XCTAssertTrue(second.failedFiles.isEmpty)
    }

    // MARK: - 删除所有数据

    func testDeleteAllRemovesAllInstanceDataButKeepsUserDSH() throws {
        let paths = try makeTemporaryPaths()
        try paths.ensureDirectories()
        // 两个实例：versions/<id> + homes/<id> + logs/<id>.log
        for id in ["inst-a", "inst-b"] {
            let versionDir = paths.versionDirectory(id)
            try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: versionDir.appendingPathComponent("dummy.txt"))
            let home = paths.homeDirectory(for: id)
            try FileManager.default.createDirectory(at: home.appendingPathComponent("profiles/web"), withIntermediateDirectories: true)
            try Data("plugin".utf8).write(to: home.appendingPathComponent("plugins.json"))
            try Data("log".utf8).write(to: paths.logFile(for: id))
        }
        try Data(repeating: 0x01, count: 256).write(to: paths.cacheDirectory.appendingPathComponent("plugins.json"))
        // 迁移前的旧共享 home（属于启动器数据，也应清理）
        try FileManager.default.createDirectory(at: paths.homeRoot, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: paths.homeRoot.appendingPathComponent("old.json"))

        let targets = DSHDataDeletion.targets(paths: paths)
        XCTAssertGreaterThanOrEqual(targets.count, 4)
        XCTAssertFalse(
            targets.contains { $0.path == paths.userDSHHome.path },
            "删除目标绝不能包含 ~/.dsh（登录凭据来源）"
        )
        XCTAssertTrue(targets.contains { $0.id == "homes" })
        XCTAssertTrue(targets.contains { $0.id == "versions" })

        let report = DSHDataDeletion.deleteAll(paths: paths)
        XCTAssertGreaterThanOrEqual(report.removed.count, 4)
        XCTAssertTrue(report.failures.isEmpty, "删除失败：\(report.failures)")
        XCTAssertTrue(report.summary.contains("已删除"))
        // 实例目录 / home / 日志 / 缓存 / 旧共享 home 都被清掉
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.versionDirectory("inst-a").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.homeDirectory(for: "inst-a").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.logFile(for: "inst-a").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.homeRoot.path))
        // homes/ 保留空壳，便于下次安装直接写入
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.homesDirectory.path))
        XCTAssertTrue(report.recreated.contains("实例数据目录"))
        let remainingHomes = try FileManager.default.contentsOfDirectory(atPath: paths.homesDirectory.path)
        XCTAssertTrue(remainingHomes.isEmpty, "homes/ 应只剩空壳")

        // 再删一次：没有可删内容，空壳 homes 不会重复计入
        let second = DSHDataDeletion.deleteAll(paths: paths)
        XCTAssertTrue(second.removed.isEmpty)
        XCTAssertTrue(second.failures.isEmpty)
        XCTAssertTrue(second.summary.contains("没有需要删除"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.homesDirectory.path))
    }

    // MARK: - 实例选择 / 持久化 / 整合包计数

    /// 多实例同版本时按实例 id 选择（不是按版本号）。
    @MainActor
    func testMultipleInstancesOfSameVersionSelectedByID() throws {
        let paths = try makeTemporaryPaths()
        let settings = makeTemporarySettings()
        try makeInstance(paths: paths, id: "alpha", name: "测试实例 A", dshVersion: "0.42.0")
        try makeInstance(
            paths: paths, id: "beta", name: "整合包实例 B", dshVersion: "0.42.0",
            kind: .pack, packName: "示例整合包", packVersion: "1.2.3"
        )

        let store = DSHVersionStore(settings: settings, paths: paths)
        store.refreshInstalled()
        XCTAssertEqual(Set(store.installed.map(\.id)), ["alpha", "beta"])
        XCTAssertEqual(store.instances(of: "0.42.0").count, 2, "同一 DSH 版本可以装多个实例")

        store.select("beta")
        XCTAssertEqual(settings.dshSelectedInstanceID, "beta")
        XCTAssertEqual(store.selectedInstalledVersion?.id, "beta")
        XCTAssertEqual(store.selectedInstalledVersion?.name, "整合包实例 B")
        XCTAssertTrue(store.selectedInstalledVersion?.isPack == true)
        XCTAssertEqual(store.selectedInstalledVersion?.dshVersion, "0.42.0")

        store.select("alpha")
        XCTAssertEqual(settings.dshSelectedInstanceID, "alpha")
        XCTAssertEqual(store.selectedInstalledVersion?.id, "alpha")
        XCTAssertFalse(store.selectedInstalledVersion?.isPack == true)
    }

    /// 默认实例写进设置后能持久化（同一个 defaults 重新加载仍保留）。
    @MainActor
    func testDefaultInstancePersistsAcrossSettingsReload() throws {
        let paths = try makeTemporaryPaths()
        let suite = "launcher.dsh.tests.instance.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("无法创建临时 UserDefaults")
        }
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        try makeInstance(paths: paths, id: "alpha", name: "A", dshVersion: "0.42.0")
        try makeInstance(paths: paths, id: "beta", name: "B", dshVersion: "0.43.0")

        let settings = LauncherSettings(defaults: defaults)
        let store = DSHVersionStore(settings: settings, paths: paths)
        store.refreshInstalled()
        store.select("beta")
        XCTAssertEqual(settings.dshSelectedInstanceID, "beta")

        let reloaded = LauncherSettings(defaults: defaults)
        XCTAssertEqual(reloaded.dshSelectedInstanceID, "beta", "默认实例应持久化到 UserDefaults")
        XCTAssertEqual(reloaded.dshSelectedVersion, "", "旧字段不再被写入")
    }

    /// 实例计数包含整合包数量。
    func testInstanceCountAndSummaryIncludePacks() {
        let vanillaA = DSHInstalledVersion(
            id: "a", name: "A", dshVersion: "0.42.0", installedAt: Date(), path: "/tmp/a", sizeBytes: 1024
        )
        let vanillaB = DSHInstalledVersion(
            id: "b", name: "B", dshVersion: "0.42.0", installedAt: Date(), path: "/tmp/b", sizeBytes: 2048
        )
        let pack = DSHInstalledVersion(
            id: "c", name: "整合包 C", dshVersion: "0.42.0", installedAt: Date(), path: "/tmp/c",
            sizeBytes: 4096, kind: .pack, packName: "示例整合包", packVersion: "1.0.0"
        )

        XCTAssertEqual(DSHFormatting.instanceCountText([]), "还没有安装实例")
        XCTAssertEqual(DSHFormatting.instanceCountText([vanillaA, vanillaB]), "2 个实例")
        XCTAssertEqual(DSHFormatting.instanceCountText([vanillaA, vanillaB, pack]), "3 个实例 · 1 个整合包")

        let summary = DSHFormatting.installedSummary([vanillaA, vanillaB, pack])
        XCTAssertTrue(summary.contains("3 个实例 · 1 个整合包"))
        XCTAssertTrue(summary.contains("共"))
        XCTAssertTrue(summary.contains("7 KB"))

        XCTAssertEqual(DSHFormatting.instanceLabel(pack), "整合包 C · DSH 0.42.0")
        XCTAssertEqual(DSHFormatting.instanceDetail(pack), "示例整合包 v1.0.0 · DSH 0.42.0")
        XCTAssertEqual(DSHFormatting.instanceDetail(vanillaA), "DSH 0.42.0")
    }

    // MARK: - 快照安全

    /// 快照模式渲染设置页：不发网络 / 不探测运行时 / 不创建磁盘目录，且能出图。
    @MainActor
    func testSettingsPageRendersInSnapshotModeWithoutDiskIO() throws {
        let paths = try makeTemporaryPaths()
        let suite = "launcher.dsh.tests.snapshot.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("无法创建临时 UserDefaults")
        }
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = LauncherSettings(defaults: defaults)
        settings.dshSelectedInstanceID = "snapshot-instance"
        let versions = DSHVersionStore(settings: settings, paths: paths)
        let process = DSHProcessController(settings: settings, paths: paths)
        let plugins = DSHPluginStore(settings: settings, paths: paths)
        let manager = LauncherThemeManager(presets: LauncherThemes.all, defaults: defaults)
        let router = LauncherRouter(initialTab: .settings, initialProduct: .dsh)

        let view = DSHSettingsPage(initialSection: .environment)
            .environment(versions)
            .environment(process)
            .environment(plugins)
            .launcherRouterEnvironment(router)
            .launcherThemeEnvironment(manager)
            .environment(\.launcherSnapshotMode, true)
            .frame(width: 1080, height: 720)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 720)
        XCTAssertNotNil(renderer.nsImage, "快照模式应能渲染设置页")

        // 快照模式不应创建 / 探测数据目录
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.versionsDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.homesDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.logsDirectory.path))
        // 不产生网络目录
        XCTAssertEqual(plugins.catalogState, .idle)
        XCTAssertEqual(versions.catalogState, .idle)
    }

    // MARK: - 日志文件工具
    // MARK: - 日志文件工具

    func testLogTailInfoAndTruncate() throws {
        let paths = try makeTemporaryPaths()
        try paths.ensureDirectories()
        let logURL = paths.logFile(for: "0.42.0")
        let lines = (1...50).map { "[12:00:00] 第 \($0) 行日志" }
        try lines.joined(separator: "\n").appending("\n").write(to: logURL, atomically: true, encoding: .utf8)

        let info = DSHLogTools.info(paths: paths, version: "0.42.0")
        XCTAssertTrue(info.exists)
        XCTAssertGreaterThan(info.bytes, 0)
        XCTAssertNotNil(info.modifiedAt)
        XCTAssertFalse(info.sizeText.isEmpty)

        let tail = DSHLogTools.readTail(paths: paths, version: "0.42.0", maxLines: 10)
        XCTAssertEqual(tail.count, 10)
        XCTAssertTrue(tail.last?.contains("第 50 行") ?? false)

        XCTAssertTrue(try DSHLogTools.truncate(paths: paths, version: "0.42.0"))
        let truncated = DSHLogTools.info(paths: paths, version: "0.42.0")
        XCTAssertTrue(truncated.exists)
        XCTAssertEqual(truncated.bytes, 0)
        XCTAssertTrue(DSHLogTools.readTail(paths: paths, version: "0.42.0").isEmpty)

        // 版本为空 / 文件不存在
        XCTAssertFalse(try DSHLogTools.truncate(paths: paths, version: nil))
        XCTAssertTrue(DSHLogTools.readTail(paths: paths, version: nil).isEmpty)
        XCTAssertFalse(DSHLogTools.info(paths: paths, version: "9.9.9").exists)
    }

    func testLogReadTailHandlesLargeFileWithoutPartialFirstLine() throws {
        let paths = try makeTemporaryPaths()
        try paths.ensureDirectories()
        let logURL = paths.logFile(for: "1.0.0")
        // 约 700KB：超过 readTail 的 512KB 尾部窗口，验证不会返回半行
        var text = ""
        for index in 1...20_000 {
            text += "[10:00:00] line-\(index)-padding-padding-padding-padding\n"
        }
        try text.write(to: logURL, atomically: true, encoding: .utf8)

        let tail = DSHLogTools.readTail(paths: paths, version: "1.0.0", maxLines: 5)
        XCTAssertEqual(tail.count, 5)
        XCTAssertTrue(tail.allSatisfy { $0.hasPrefix("[10:00:00] line-") })
        XCTAssertTrue(tail.last?.contains("line-20000") ?? false)
    }

    // MARK: - 进程状态文案

    func testProcessStatusFormatterCoversAllStates() {
        let idle = DSHProcessStatusFormatter.text(for: .idle)
        XCTAssertEqual(idle.title, "未运行")
        XCTAssertFalse(idle.isRunning)
        XCTAssertFalse(idle.isError)

        XCTAssertEqual(DSHProcessStatusFormatter.text(for: .starting).title, "启动中")
        XCTAssertEqual(DSHProcessStatusFormatter.text(for: .stopping).title, "正在停止")

        let running = DSHProcessStatusFormatter.text(
            for: .running(url: "http://127.0.0.1:3080/?token=abc123"),
            port: 3080,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(running.title, "运行中")
        XCTAssertTrue(running.isRunning)
        XCTAssertFalse(running.isError)
        XCTAssertTrue(running.detail.contains("端口 3080"))
        XCTAssertTrue(running.detail.contains("启动于"))
        XCTAssertFalse(running.detail.contains("abc123"), "一次性 token 不应出现在状态文案里")

        let failed = DSHProcessStatusFormatter.text(for: .failed("没有找到 Node.js 运行时"))
        XCTAssertTrue(failed.isError)
        XCTAssertEqual(failed.title, "启动失败")
        XCTAssertTrue(failed.detail.contains("Node.js"))
    }

    // MARK: - 与真实 store 的联动

    @MainActor
    func testVersionStoreSelectsAndUninstallsRealVersionDirectory() throws {
        let paths = try makeTemporaryPaths()
        let settings = makeTemporarySettings()
        // 造一个已安装版本：只要入口脚本存在即会被识别
        let script = paths.cliScript(for: "0.42.0")
        try FileManager.default.createDirectory(
            at: script.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("// dsh bin".utf8).write(to: script)

        let store = DSHVersionStore(settings: settings, paths: paths)
        store.refreshInstalled()
        XCTAssertEqual(store.installed.map(\.id), ["0.42.0"])
        XCTAssertEqual(store.installed.first?.dshVersion, "0.42.0")
        // 旧目录名被当作实例 ID，选中状态存在 dshSelectedInstanceID。
        XCTAssertEqual(store.settings.dshSelectedInstanceID, "0.42.0", "首次扫描应自动选中已安装实例")
        XCTAssertEqual(store.selectedInstalledVersion?.id, "0.42.0")

        store.select("0.42.0")
        XCTAssertEqual(settings.dshSelectedInstanceID, "0.42.0")

        // 实例自己的 DSH_HOME 会随实例卸载删除；旧共享 home（凭据来源缓存）不动
        try FileManager.default.createDirectory(
            at: paths.homeDirectory(for: "0.42.0"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: paths.homeRoot, withIntermediateDirectories: true)
        let legacyMarker = paths.homeRoot.appendingPathComponent("session.json")
        try Data("shared".utf8).write(to: legacyMarker)

        XCTAssertTrue(store.uninstall("0.42.0"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyMarker.path), "旧共享 home 不应随实例卸载被删")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.homeDirectory(for: "0.42.0").path))
        XCTAssertTrue(store.installed.isEmpty)
        XCTAssertTrue(settings.dshSelectedInstanceID.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.versionDirectory("0.42.0").path))
    }

    @MainActor
    func testPluginStoreSourceTextFallsBackToSetting() throws {
        let settings = makeTemporarySettings()
        let paths = try makeTemporaryPaths()
        let store = DSHPluginStore(settings: settings, paths: paths)
        XCTAssertEqual(store.sourceText, DSHRegistryClient.defaultPluginSource)
        XCTAssertEqual(store.catalogState, .idle)
        XCTAssertEqual(store.pluginCount, 0)

        settings.dshPluginSource = "https://example.com/plugins.json"
        XCTAssertEqual(store.sourceText, "https://example.com/plugins.json")
    }

    // MARK: - 工具

    /// 建一个临时 DSH 目录（测试结束自动清理）。
    private func makeTemporaryPaths() throws -> DSHPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        // homeRoot 也放在临时目录里，测试绝不触碰真实 ~/.dsh
        return DSHPaths(root: root, homeRoot: root.appendingPathComponent("shared-home", isDirectory: true))
    }

    /// 造一个实例：目录 + 入口脚本 + 安装元数据。
    private func makeInstance(
        paths: DSHPaths,
        id: String,
        name: String,
        dshVersion: String,
        size: Int64 = 1024,
        kind: DSHInstanceKind = .vanilla,
        packName: String? = nil,
        packVersion: String? = nil
    ) throws {
        let script = paths.cliScript(for: id)
        try FileManager.default.createDirectory(
            at: script.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("// dsh bin".utf8).write(to: script)
        let metadata = DSHInstalledVersion(
            id: id,
            name: name,
            dshVersion: dshVersion,
            installedAt: Date(),
            path: paths.versionDirectory(id).path,
            sizeBytes: size,
            kind: kind,
            packName: packName,
            packVersion: packVersion
        )
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: paths.versionDirectory(id).appendingPathComponent("launcher-install.json"))
    }

    /// 建一个临时 UserDefaults 设置对象。
    private func makeTemporarySettings() -> LauncherSettings {
        let suite = "launcher.dsh.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
        }
        return LauncherSettings(defaults: defaults)
    }
}
