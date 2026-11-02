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
        XCTAssertTrue(summary.contains("2 个版本"))
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
        // 共享 DSH_HOME 下放一个 1KB 的用户数据文件
        try FileManager.default.createDirectory(at: paths.homeRoot, withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 1024).write(to: paths.homeRoot.appendingPathComponent("key.json"))

        let rows = DSHDataTools.directories(paths: paths)
        XCTAssertEqual(rows.count, DSHDataDirectoryKind.allCases.count)
        let versionsRow = try XCTUnwrap(rows.first { $0.kind == .versions })
        XCTAssertTrue(versionsRow.exists)
        XCTAssertGreaterThanOrEqual(versionsRow.bytes, 3 * 1024)
        XCTAssertFalse(versionsRow.sizeText.isEmpty)

        // homes 项展示的是所有版本共享的 launcher DSH_HOME，而不是历史 homes/
        let homeRow = try XCTUnwrap(rows.first { $0.kind == .home })
        XCTAssertEqual(homeRow.path, paths.homeRoot.path)
        XCTAssertTrue(homeRow.title.contains("DSH_HOME"))
        XCTAssertGreaterThanOrEqual(homeRow.bytes, 1024)
        XCTAssertTrue(DSHDataDirectoryKind.home.title.contains("DSH_HOME"))
        XCTAssertFalse(DSHDataDirectoryKind.home.isInsideLauncherRoot)
        XCTAssertTrue(DSHDataDirectoryKind.versions.isInsideLauncherRoot)

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

    func testDeleteAllRemovesLauncherDataButKeepsHomeAndUserDSH() throws {
        let paths = try makeTemporaryPaths()
        try paths.ensureDirectories()
        // 启动器自己的数据：versions / logs / cache / 历史遗留 homes
        for target in DSHDataDeletion.targets(paths: paths) {
            try FileManager.default.createDirectory(atPath: target.path, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: URL(fileURLWithPath: target.path).appendingPathComponent("dummy.txt"))
        }
        // launcher 的 DSH_HOME：插件 / 会话 / 登录凭据软链，绝不能删
        try FileManager.default.createDirectory(at: paths.homeRoot, withIntermediateDirectories: true)
        let sharedFiles = ["profiles/web/package.json", "plugins.json", "keychain.json"]
        for file in sharedFiles {
            let url = paths.homeRoot.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("keep-me".utf8).write(to: url)
        }

        let targets = DSHDataDeletion.targets(paths: paths)
        XCTAssertEqual(targets.count, 4)
        XCTAssertFalse(
            targets.contains { $0.path == paths.homeRoot.path },
            "删除目标不能包含共享 DSH_HOME"
        )

        let report = DSHDataDeletion.deleteAll(paths: paths)
        XCTAssertEqual(report.removed.count, 4)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertTrue(report.summary.contains("已删除 4 个数据目录"))
        for target in targets {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: target.path),
                "\(target.title) 应被删除"
            )
        }
        // 根目录保留（其余目录可重建）
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.root.path))
        // launcher home 及其内容必须原样保留（~/.dsh 的凭据同理不在删除范围）
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.homeRoot.path))
        for file in sharedFiles {
            let url = paths.homeRoot.appendingPathComponent(file)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(file) 不应被删除")
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "keep-me")
        }

        let second = DSHDataDeletion.deleteAll(paths: paths)
        XCTAssertTrue(second.removed.isEmpty)
        XCTAssertTrue(second.summary.contains("没有需要删除"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.homeRoot.path))
    }

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
        XCTAssertEqual(store.installed.map(\.version), ["0.42.0"])
        XCTAssertEqual(store.settings.dshSelectedVersion, "0.42.0", "首次扫描应自动选中已安装版本")
        XCTAssertEqual(store.selectedInstalledVersion?.version, "0.42.0")

        store.select("0.42.0")
        XCTAssertEqual(settings.dshSelectedVersion, "0.42.0")

        // 共享 DSH_HOME 里放一份用户数据，卸载版本后必须保留
        try FileManager.default.createDirectory(at: paths.homeRoot, withIntermediateDirectories: true)
        let sharedMarker = paths.homeRoot.appendingPathComponent("session.json")
        try Data("shared".utf8).write(to: sharedMarker)

        XCTAssertTrue(store.uninstall("0.42.0"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedMarker.path), "共享 DSH_HOME 不应随版本卸载被删")
        XCTAssertTrue(store.installed.isEmpty)
        XCTAssertTrue(settings.dshSelectedVersion.isEmpty)
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
