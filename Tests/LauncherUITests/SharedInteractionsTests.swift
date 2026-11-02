import XCTest
import Foundation
@testable import LauncherUI

/// 共享交互层测试：下载源改写、版本比较、实例文件操作、启动记录、账户名校验。
final class SharedInteractionsTests: XCTestCase {

    // MARK: - 下载源

    func testOfficialSourceDoesNotRewrite() {
        let url = URL(string: "https://piston-meta.mojang.com/v1/packages/abc/1.21.4.json")!
        XCTAssertEqual(DownloadSource.official.rewrite(url), url)
    }

    func testMirrorRewritesMojangHosts() {
        let mirror = DownloadSource.mirror

        let meta = mirror.rewrite(URL(string: "https://piston-meta.mojang.com/v1/packages/abc/1.21.4.json")!)
        XCTAssertEqual(meta.host, "bmclapi2.bangbang93.com")
        XCTAssertEqual(meta.path, "/v1/packages/abc/1.21.4.json")

        let client = mirror.rewrite(URL(string: "https://piston-data.mojang.com/v1/objects/def/client.jar")!)
        XCTAssertEqual(client.host, "bmclapi2.bangbang93.com")
        XCTAssertEqual(client.path, "/v1/objects/def/client.jar")
    }

    func testMirrorRewritesAssetsAndLibraries() {
        let mirror = DownloadSource.mirror

        let asset = mirror.rewrite(URL(string: "https://resources.download.minecraft.net/ab/abcdef")!)
        XCTAssertEqual(asset.host, "bmclapi2.bangbang93.com")
        XCTAssertEqual(asset.path, "/assets/ab/abcdef")

        let library = mirror.rewrite(URL(string: "https://libraries.minecraft.net/org/ow2/asm/9.6/asm-9.6.jar")!)
        XCTAssertEqual(library.host, "bmclapi2.bangbang93.com")
        XCTAssertEqual(library.path, "/maven/org/ow2/asm/9.6/asm-9.6.jar")
    }

    func testMirrorLeavesUnknownHostsAlone() {
        let url = URL(string: "https://api.modrinth.com/v2/search")!
        XCTAssertEqual(DownloadSource.mirror.rewrite(url), url)
    }

    // MARK: - 版本比较

    func testVersionComparison() {
        XCTAssertTrue(LauncherVersion.isNewer("0.3.0", than: "0.2.0"))
        XCTAssertTrue(LauncherVersion.isNewer("0.2.10", than: "0.2.9"))
        XCTAssertTrue(LauncherVersion.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(LauncherVersion.isNewer("0.2.0", than: "0.2.0"))
        XCTAssertFalse(LauncherVersion.isNewer("0.2.0", than: "0.2.1"))
        XCTAssertTrue(LauncherVersion.isNewer("0.2.1-beta.3", than: "0.2.0"))
    }

    // MARK: - 实例名 / 文件操作

    func testNormalizedNameValidation() {
        XCTAssertEqual(InstanceActions.normalizedInstanceName("  1.21.4-Fabric "), "1.21.4-Fabric")
        XCTAssertNil(InstanceActions.normalizedInstanceName("   "))
        XCTAssertNil(InstanceActions.normalizedInstanceName("a/b"))
        XCTAssertNil(InstanceActions.normalizedInstanceName("a:b"))
        XCTAssertNotNil(InstanceActions.normalizedInstanceName("副本 2"))
    }

    func testRenameAndDuplicateInstance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let installation = MinecraftInstallation(root: root)
        let versionID = "1.21.4"
        let directory = installation.versionDirectory(versionID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"id":"1.21.4","type":"release","mainClass":"m","libraries":[]}
        """
        try Data(json.utf8).write(to: installation.versionJSONURL(versionID))
        try Data().write(to: installation.versionJarURL(versionID))

        let renamed = try InstanceActions.rename(versionID: versionID, to: "1.21.4-Fabric", installation: installation)
        XCTAssertEqual(renamed, "1.21.4-Fabric")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installation.versionJSONURL("1.21.4-Fabric").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installation.versionJarURL("1.21.4-Fabric").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installation.versionDirectory(versionID).path))

        // JSON id 已回写
        let data = try Data(contentsOf: installation.versionJSONURL("1.21.4-Fabric"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["id"] as? String, "1.21.4-Fabric")

        let duplicated = try InstanceActions.duplicate(versionID: "1.21.4-Fabric", as: "副本", installation: installation)
        XCTAssertEqual(duplicated, "副本")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installation.versionJSONURL("副本").path))

        // 非法名 / 重名要报错
        XCTAssertThrowsError(try InstanceActions.rename(versionID: "副本", to: "a/b", installation: installation))
        XCTAssertThrowsError(try InstanceActions.duplicate(versionID: "副本", as: "1.21.4-Fabric", installation: installation))

        // 删除不存在的实例：抛错且不会产生副作用（不在测试里真的把文件移进用户废纸篓）
        XCTAssertThrowsError(try InstanceActions.delete(versionID: "never-existed", installation: installation))
        XCTAssertThrowsError(try InstanceActions.delete(versionID: "../escape", installation: installation))
    }

    func testInstanceSizeCountsFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: root.appendingPathComponent("a.bin"))
        XCTAssertGreaterThan(InstanceActions.size(of: root), 0)
        // 人读文本必须包含数字（不依赖具体语言/单位）
        let text = InstanceActions.sizeText(of: root)
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains(where: { $0.isNumber }))
    }

    // MARK: - 账户名

    func testPlayerNameValidation() {
        XCTAssertNil(LauncherSettings.validatePlayerName("Steve"))
        XCTAssertNil(LauncherSettings.validatePlayerName("Steve_2026"))
        XCTAssertNil(LauncherSettings.validatePlayerName("史蒂夫"))          // 中文名在离线服务器可用
        XCTAssertNotNil(LauncherSettings.validatePlayerName(""))
        XCTAssertNotNil(LauncherSettings.validatePlayerName("abcdefghijklmnopq"))   // 17 字符
        XCTAssertNotNil(LauncherSettings.validatePlayerName("a b"))
        XCTAssertNotNil(LauncherSettings.validatePlayerName("name!"))
    }

    // MARK: - 设置持久化 / 启动记录

    @MainActor
    func testLaunchRecordsPersistAndSummarize() {
        let suite = "launcher.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = LauncherSettings(defaults: defaults)
        let id = settings.recordLaunchStart(versionID: "1.21.4")
        XCTAssertEqual(settings.launchRecords.count, 1)
        XCTAssertNil(settings.launchRecords[0].exitCode)
        XCTAssertNotNil(settings.lastSavedAt)

        settings.recordLaunchEnd(id: id, exitCode: 0)
        XCTAssertEqual(settings.launchRecords[0].exitCode, 0)
        XCTAssertEqual(settings.launchRecords[0].resultText, "正常退出")
        XCTAssertNotNil(settings.launchRecords[0].durationText)
        XCTAssertEqual(settings.lastLaunchDate(for: "1.21.4") != nil, true)

        // 重新读取应保留
        let reloaded = LauncherSettings(defaults: defaults)
        XCTAssertEqual(reloaded.launchRecords.count, 1)
        XCTAssertEqual(reloaded.launchRecords[0].versionID, "1.21.4")
    }

    @MainActor
    func testSavedPlayerNamesAndUpdateFeedPersist() {
        let suite = "launcher.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = LauncherSettings(defaults: defaults)
        settings.playerName = "Alex"
        settings.rememberPlayerName("Alex")
        settings.rememberPlayerName("Alex")   // 去重
        XCTAssertEqual(settings.savedPlayerNames.first, "Alex")
        XCTAssertEqual(settings.savedPlayerNames.filter { $0 == "Alex" }.count, 1)

        settings.updateFeedURL = "https://example.com/feed.json"
        let reloaded = LauncherSettings(defaults: defaults)
        XCTAssertEqual(reloaded.updateFeedURL, "https://example.com/feed.json")
        XCTAssertEqual(reloaded.downloadSourceValue, .official)
        reloaded.downloadSource = "mirror"
        XCTAssertEqual(reloaded.downloadSourceValue, .mirror)
    }

    // MARK: - 安装选项 / 更新源

    func testInstallOptionsSummary() {
        let options = InstallOptions(includeAssets: false, verifyExisting: true)
        XCTAssertTrue(options.summary.contains("仅核心文件"))
        XCTAssertTrue(options.summary.contains("校验已有文件"))
        XCTAssertEqual(InstallOptions.default.summary, "含资源文件 · 跳过已有文件校验")
    }

    func testUpdateFeedDecoding() throws {
        let json = """
        {"version":"0.3.0","url":"https://example.com/download","notes":"修复若干问题"}
        """
        let feed = try JSONDecoder().decode(UpdateFeed.self, from: Data(json.utf8))
        XCTAssertEqual(feed.version, "0.3.0")
        XCTAssertEqual(feed.url, "https://example.com/download")
        XCTAssertEqual(feed.notes, "修复若干问题")
    }

    @MainActor
    func testUpdateCheckerWithoutFeedReportsNoFeed() async {
        let checker = UpdateChecker()
        await checker.check(feedURL: "   ")
        XCTAssertEqual(checker.status, .noFeed)
        XCTAssertEqual(checker.status.message, "未配置更新源（本地构建）")
    }

    // MARK: - 构建信息

    func testBuildInfoIsConsistent() {
        let info = LauncherBuildInfo.current
        XCTAssertFalse(info.version.isEmpty)
        XCTAssertTrue(info.versionText.hasPrefix("v"))
        XCTAssertFalse(info.buildNumber.isEmpty)
        XCTAssertEqual(info.buildDateText.count, 10)
        XCTAssertTrue(info.summary.contains(info.versionText))
    }
}

// MARK: - 启动参数清理

extension SharedInteractionsTests {
    /// 离线模式下 `--clientId ${clientid}` 会变成 `--clientId ""`，旗标必须一起清掉。
    func testSanitizeDropsEmptyValueFlag() {
        let cleaned = LaunchCommandBuilder.sanitize([
            "--username", "Steve",
            "--clientId", "",
            "--accessToken", "0",
            "--versionType", "release"
        ])
        XCTAssertEqual(cleaned, ["--username", "Steve", "--accessToken", "0", "--versionType", "release"])
    }

    func testExpandKeepsEmptyValueForSanitize() {
        let args = [
            VersionDetail.Argument(rules: nil, values: ["--clientId", "${clientid}"]),
            VersionDetail.Argument(rules: nil, values: ["--username", "${auth_player_name}"])
        ]
        let expanded = LaunchCommandBuilder.expand(args, values: [
            "clientid": "",
            "auth_player_name": "Steve"
        ])
        XCTAssertEqual(expanded, ["--clientId", "", "--username", "Steve"])
        XCTAssertEqual(
            LaunchCommandBuilder.sanitize(expanded),
            ["--username", "Steve"]
        )
    }
}

// MARK: - 引擎：取消判定 / 依赖保护 / 清理候选

extension SharedInteractionsTests {
    func testCancellationClassification() {
        XCTAssertTrue(LauncherEngine.isCancellation(CancellationError()))
        XCTAssertTrue(LauncherEngine.isCancellation(URLError(.cancelled)))
        XCTAssertFalse(LauncherEngine.isCancellation(URLError(.timedOut)))
        XCTAssertFalse(LauncherEngine.isCancellation(DownloadError.http(500, URL(string: "https://example.com")!)))
    }

    func testStoppedLaunchRecordShowsStopped() {
        var record = LaunchRecord(versionID: "1.21.4")
        XCTAssertEqual(record.resultText, "运行中")
        record.finishedAt = Date()
        XCTAssertEqual(record.resultText, "已停止")
        record.exitCode = 0
        XCTAssertEqual(record.resultText, "正常退出")
    }

    /// 被其它实例 `inheritsFrom` 的父版本不能被清理 / 删除；无启动记录时按目录修改时间判龄。
    @MainActor
    func testUnusedVersionsRespectsInheritanceAndModificationDate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "launcher.tests.engine.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let installation = MinecraftInstallation(root: root)
        try FileManager.default.createDirectory(at: installation.versionsDirectory, withIntermediateDirectories: true)

        func makeVersion(_ id: String, inheritsFrom: String? = nil, modified: Date = Date()) throws {
            let directory = installation.versionDirectory(id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var object: [String: Any] = ["id": id, "type": "release", "mainClass": "m", "libraries": []]
            if let inheritsFrom { object["inheritsFrom"] = inheritsFrom }
            let data = try JSONSerialization.data(withJSONObject: object)
            try data.write(to: installation.versionJSONURL(id))
            try Data().write(to: installation.versionJarURL(id))
            // InstalledVersion.lastModified 读的是版本 JSON 的修改时间，不是目录的
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: installation.versionJSONURL(id).path)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: directory.path)
        }

        // base 被 loader 依赖；old 40 天没改过；loader 刚刚创建
        try makeVersion("base", modified: Date().addingTimeInterval(-100 * 86_400))
        try makeVersion("loader", inheritsFrom: "base")
        try makeVersion("old", modified: Date().addingTimeInterval(-40 * 86_400))

        let settings = LauncherSettings(defaults: defaults)
        settings.gameDirectory = root.path
        let engine = LauncherEngine(settings: settings)
        await engine.refreshEnvironment()

        XCTAssertEqual(Set(engine.installedVersions.map(\.id)), ["base", "loader", "old"])
        XCTAssertEqual(engine.dependents(of: "base"), ["loader"])
        XCTAssertEqual(engine.dependents(of: "loader"), [])

        let candidates = Set(engine.unusedVersions(olderThanDays: 30).map(\.id))
        XCTAssertTrue(candidates.contains("old"))
        XCTAssertFalse(candidates.contains("base"), "被依赖的父版本不能进入清理候选")
        XCTAssertFalse(candidates.contains("loader"), "刚安装的版本不应被当成 30 天未用")

        XCTAssertThrowsError(try engine.deleteVersion("base")) { error in
            XCTAssertTrue(error.localizedDescription.contains("loader"))
        }
    }
}
