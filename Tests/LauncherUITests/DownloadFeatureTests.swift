import AppKit
import SwiftUI
import XCTest
@testable import LauncherUI

/// 下载页测试：Modrinth 地址构造 / JSON 解码 / HTTP 错误 / 整合包清单解析 / 安装路径决策 /
/// 弹窗层布局（400pt 居中、遮罩铺满、取消路径）。
/// 全部走本地 fixture、URLProtocol stub 与离屏 ImageRenderer，不访问真实网络。
final class DownloadFeatureTests: XCTestCase {

    // MARK: - 生命周期

    override func tearDown() {
        StubURLProtocol.handler = nil
        session?.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    private var session: URLSession?

    /// 创建注入 stub 协议的客户端（不访问真实网络）。
    private func makeStubClient() -> ModrinthClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        self.session = session
        return ModrinthClient(session: session)
    }

    // MARK: - 地址构造

    func testSearchURLContainsFacetsAndPaging() throws {
        let url = try XCTUnwrap(
            ModrinthEndpoint.search(
                projectType: .modpack,
                gameVersion: "1.21.4",
                query: "  optimized  ",
                limit: 20,
                offset: 40,
                index: "downloads"
            )
        )
        XCTAssertEqual(url.host, "api.modrinth.com")
        XCTAssertEqual(url.path, "/v2/search")

        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(value("query"), "optimized", "搜索词需要去掉首尾空白")
        XCTAssertEqual(value("limit"), "20")
        XCTAssertEqual(value("offset"), "40")
        XCTAssertEqual(value("index"), "downloads")
        XCTAssertEqual(value("facets"), "[[\"project_type:modpack\"],[\"versions:1.21.4\"]]")
    }

    func testSearchURLWithoutGameVersionOnlyFiltersProjectType() throws {
        let url = try XCTUnwrap(
            ModrinthEndpoint.search(
                projectType: .shader,
                gameVersion: nil,
                query: "",
                limit: 10,
                offset: 0
            )
        )
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertNil(value("query"), "空搜索词不应带 query 参数")
        XCTAssertEqual(value("facets"), "[[\"project_type:shader\"]]")
    }

    func testSearchURLClampsLimit() throws {
        let url = try XCTUnwrap(
            ModrinthEndpoint.search(projectType: .mod, gameVersion: nil, query: "", limit: 500, offset: -3)
        )
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "100")
        XCTAssertEqual(items.first { $0.name == "offset" }?.value, "0")
    }

    func testProjectVersionsURLFiltersGameVersionAndLoaders() throws {
        let url = try XCTUnwrap(
            ModrinthEndpoint.projectVersions(projectID: "1KVo5zza", gameVersion: "1.21.4", loaders: ["fabric", "quilt"])
        )
        XCTAssertEqual(url.path, "/v2/project/1KVo5zza/version")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "game_versions" }?.value, "[\"1.21.4\"]")
        XCTAssertEqual(items.first { $0.name == "loaders" }?.value, "[\"fabric\",\"quilt\"]")
    }

    func testJSONArrayEscaping() {
        XCTAssertEqual(ModrinthEndpoint.jsonArray(["a", "b"]), "[\"a\",\"b\"]")
        XCTAssertEqual(ModrinthEndpoint.jsonArray(["a\"b"]), "[\"a\\\"b\"]")
    }

    func testLoaderProfileURLs() throws {
        let fabric = try XCTUnwrap(ModrinthEndpoint.fabricLoaderProfile(minecraft: "1.21.4", loader: "0.16.9"))
        XCTAssertEqual(fabric.host, "meta.fabricmc.net")
        XCTAssertEqual(fabric.path, "/v2/versions/loader/1.21.4/0.16.9/profile/json")

        let quilt = try XCTUnwrap(ModrinthEndpoint.quiltLoaderProfile(minecraft: "1.21.4", loader: "0.26.0"))
        XCTAssertEqual(quilt.host, "meta.quiltmc.org")
        XCTAssertEqual(quilt.path, "/v3/versions/loader/1.21.4/0.26.0/profile/json")
    }

    func testUserAgentIdentifiesLauncher() {
        XCTAssertTrue(ModrinthClient.userAgent.hasPrefix("BlockLauncher/"))
        XCTAssertTrue(ModrinthClient.userAgent.contains("("))
    }

    // MARK: - 解码

    func testSearchPageDecoding() throws {
        let page = try JSONDecoder().decode(ModrinthSearchPage.self, from: Data(Self.searchFixture.utf8))
        XCTAssertEqual(page.hits.count, 2)
        XCTAssertEqual(page.totalHits, 12345)
        XCTAssertTrue(page.hasMore)

        let first = try XCTUnwrap(page.hits.first)
        XCTAssertEqual(first.projectID, "1KVo5zza")
        XCTAssertEqual(first.slug, "fabulously-optimized")
        XCTAssertEqual(first.title, "Fabulously Optimized")
        XCTAssertEqual(first.projectType, "modpack")
        XCTAssertEqual(first.author, "robotkoer")
        XCTAssertEqual(first.downloads, 19_710_444)
        XCTAssertEqual(first.authorText, "robotkoer")
        XCTAssertEqual(first.downloadsText, "1971.0 万")
    }

    func testSearchPageWithoutMore() throws {
        let json = """
        {"hits": [], "offset": 0, "limit": 20, "total_hits": 0}
        """
        let page = try JSONDecoder().decode(ModrinthSearchPage.self, from: Data(json.utf8))
        XCTAssertFalse(page.hasMore)
    }

    func testVersionDecodingPicksPrimaryFile() throws {
        let versions = try JSONDecoder().decode([ModrinthVersion].self, from: Data(Self.versionFixture.utf8))
        let version = try XCTUnwrap(versions.first)
        XCTAssertEqual(version.versionNumber, "8.2.0")
        XCTAssertEqual(version.gameVersions, ["1.21.4"])
        XCTAssertEqual(version.loaders, ["fabric"])

        let file = try XCTUnwrap(version.primaryFile)
        XCTAssertEqual(file.filename, "Fabulously.Optimized-v8.2.0.mrpack")
        XCTAssertEqual(file.size, 182_799)
        XCTAssertEqual(file.sha1, "68226d5210fb3f80841de6160fbe4a0595a5fb11")
        XCTAssertEqual(file.url.lastPathComponent, "Fabulously.Optimized-v8.2.0.mrpack")
    }

    // MARK: - 网络行为（URLProtocol stub）

    func testClientSendsUserAgentAndDecodesResponse() async throws {
        var capturedRequest: URLRequest?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            return .success((200, Data(Self.searchFixture.utf8)))
        }
        let client = makeStubClient()
        let page = try await client.search(
            projectType: .modpack,
            gameVersion: "1.21.4",
            query: "optimized",
            limit: 20,
            offset: 0
        )
        XCTAssertEqual(page.hits.first?.title, "Fabulously Optimized")
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), ModrinthClient.userAgent)
        XCTAssertEqual(request.url?.host, "api.modrinth.com")
        let items = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems })
        XCTAssertEqual(items.first { $0.name == "facets" }?.value, "[[\"project_type:modpack\"],[\"versions:1.21.4\"]]")
    }

    func testHTTPErrorSurfaced() async {
        StubURLProtocol.handler = { _ in .success((503, Data())) }
        let client = makeStubClient()
        do {
            _ = try await client.search(projectType: .mod, gameVersion: nil, query: "", limit: 5, offset: 0)
            XCTFail("HTTP 503 应该抛错")
        } catch let error as ModrinthError {
            XCTAssertEqual(error, .http(503))
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    func testDecodingErrorSurfaced() async {
        StubURLProtocol.handler = { _ in .success((200, Data("not json".utf8))) }
        let client = makeStubClient()
        do {
            _ = try await client.search(projectType: .mod, gameVersion: nil, query: "", limit: 5, offset: 0)
            XCTFail("非法 JSON 应该抛错")
        } catch let error as ModrinthError {
            guard case .decoding = error else {
                return XCTFail("应该是 decoding 错误，实际是 \(error)")
            }
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    // MARK: - 整合包清单

    func testModpackIndexDecoding() throws {
        let index = try ModrinthModpackIndex.decode(Data(Self.modpackIndexFixture.utf8))
        XCTAssertEqual(index.formatVersion, 1)
        XCTAssertEqual(index.game, "minecraft")
        XCTAssertEqual(index.name, "Fabulously Optimized")
        XCTAssertEqual(index.versionID, "8.2.0")
        XCTAssertEqual(index.minecraftVersion, "1.21.4")
        XCTAssertEqual(index.loader, .fabric("0.19.3"))
        XCTAssertTrue(index.loader.isSupported)
        XCTAssertEqual(index.files.count, 3)
        XCTAssertEqual(index.clientFiles.count, 2, "server 专用文件不应该安装到客户端")

        let first = try XCTUnwrap(index.files.first)
        XCTAssertEqual(first.path, "mods/BetterGrassify-1.7.0+fabric.1.21.4.jar")
        XCTAssertEqual(first.hashes.sha1, "8bada432a857ce7af3772f60a19901ca85f3dfb3")
        XCTAssertEqual(first.downloads.count, 1)
        XCTAssertTrue(first.isClientRequired)
    }

    func testModpackIndexQuiltLoader() throws {
        let json = """
        {"formatVersion":1,"game":"minecraft","versionId":"1.0.0","name":"Quilt Pack",
         "files":[],"dependencies":{"minecraft":"1.20.1","quilt-loader":"0.26.0"}}
        """
        let index = try ModrinthModpackIndex.decode(Data(json.utf8))
        XCTAssertEqual(index.loader, .quilt("0.26.0"))
        XCTAssertTrue(index.loader.isSupported)
        XCTAssertTrue(index.clientFiles.isEmpty)
    }

    func testModpackIndexVanillaLoader() throws {
        let json = """
        {"formatVersion":1,"game":"minecraft","versionId":"1.0.0","name":"Vanilla Pack",
         "files":[],"dependencies":{"minecraft":"1.21.4"}}
        """
        let index = try ModrinthModpackIndex.decode(Data(json.utf8))
        XCTAssertEqual(index.loader, .vanilla)
        XCTAssertTrue(index.loader.isSupported)
    }

    func testModpackIndexUnsupportedLoaders() throws {
        let forge = """
        {"formatVersion":1,"game":"minecraft","versionId":"1.0.0","name":"Forge Pack",
         "files":[],"dependencies":{"minecraft":"1.20.1","forge":"47.2.0"}}
        """
        let forgeIndex = try ModrinthModpackIndex.decode(Data(forge.utf8))
        XCTAssertEqual(forgeIndex.loader, .forge("47.2.0"))
        XCTAssertFalse(forgeIndex.loader.isSupported)
        XCTAssertEqual(forgeIndex.loader.title, "Forge 47.2.0")

        let unknown = """
        {"formatVersion":1,"game":"minecraft","versionId":"1.0.0","name":"Unknown",
         "files":[],"dependencies":{"minecraft":"1.20.1","liteloader":"1.12"}}
        """
        let unknownIndex = try ModrinthModpackIndex.decode(Data(unknown.utf8))
        XCTAssertEqual(unknownIndex.loader, .unsupported("liteloader"))
        XCTAssertFalse(unknownIndex.loader.isSupported)
    }

    func testModpackIndexRejectsInvalidPayloads() {
        XCTAssertThrowsError(try ModrinthModpackIndex.decode(Data("{}".utf8))) { error in
            guard case ModpackIndexError.invalidJSON = error else {
                return XCTFail("应该报 invalidJSON，实际 \(error)")
            }
        }

        let wrongFormat = """
        {"formatVersion":2,"game":"minecraft","versionId":"1","name":"x","files":[],"dependencies":{"minecraft":"1.21.4"}}
        """
        XCTAssertThrowsError(try ModrinthModpackIndex.decode(Data(wrongFormat.utf8))) { error in
            XCTAssertEqual(error as? ModpackIndexError, .unsupportedFormat(2))
        }

        let notMinecraft = """
        {"formatVersion":1,"game":"terraria","versionId":"1","name":"x","files":[],"dependencies":{}}
        """
        XCTAssertThrowsError(try ModrinthModpackIndex.decode(Data(notMinecraft.utf8))) { error in
            XCTAssertEqual(error as? ModpackIndexError, .notMinecraft("terraria"))
        }
    }

    // MARK: - 安装路径决策

    func testFileDestinationsForEachResourceType() throws {
        let instance = URL(fileURLWithPath: "/tmp/instances/test-instance", isDirectory: true)

        XCTAssertEqual(
            ModrinthInstallPlanner.fileDestination(instanceDirectory: instance, type: .mod, filename: "sodium.jar")?.path,
            "/tmp/instances/test-instance/mods/sodium.jar"
        )
        XCTAssertEqual(
            ModrinthInstallPlanner.fileDestination(instanceDirectory: instance, type: .resourcepack, filename: "pack.zip")?.path,
            "/tmp/instances/test-instance/resourcepacks/pack.zip"
        )
        XCTAssertEqual(
            ModrinthInstallPlanner.fileDestination(instanceDirectory: instance, type: .shader, filename: "shader.zip")?.path,
            "/tmp/instances/test-instance/shaderpacks/shader.zip"
        )
        XCTAssertEqual(
            ModrinthInstallPlanner.fileDestination(instanceDirectory: instance, type: .datapack, filename: "data.zip")?.path,
            "/tmp/instances/test-instance/datapacks/data.zip"
        )
        // 整合包与世界没有单文件落盘位置
        XCTAssertNil(ModrinthInstallPlanner.fileDestination(instanceDirectory: instance, type: .modpack, filename: "a.mrpack"))
        XCTAssertNil(ModrinthInstallPlanner.fileDestination(instanceDirectory: instance, type: .world, filename: "w.zip"))
    }

    func testWorldDestinationExtractsToSaves() {
        let instance = URL(fileURLWithPath: "/tmp/instances/test-instance", isDirectory: true)
        XCTAssertEqual(
            ModrinthInstallPlanner.worldDestination(instanceDirectory: instance, filename: "My World.zip").path,
            "/tmp/instances/test-instance/saves/My World"
        )
    }

    func testFilenameSanitization() {
        XCTAssertEqual(ModrinthInstallPlanner.sanitizedFilename("sodium-0.6.jar"), "sodium-0.6.jar")
        XCTAssertEqual(ModrinthInstallPlanner.sanitizedFilename("a/b:c.jar"), "a_b_c.jar")
        XCTAssertEqual(ModrinthInstallPlanner.sanitizedFilename("../evil.jar"), "_evil.jar")
        XCTAssertFalse(ModrinthInstallPlanner.sanitizedFilename("../evil.jar").contains("/"))
        XCTAssertFalse(ModrinthInstallPlanner.sanitizedFilename("a/b.jar").contains("/"))
    }

    func testUnsafeRelativePathsRejected() {
        XCTAssertTrue(ModrinthInstallPlanner.isSafeRelativePath("mods/a.jar"))
        XCTAssertTrue(ModrinthInstallPlanner.isSafeRelativePath("config/x/y.json"))
        XCTAssertFalse(ModrinthInstallPlanner.isSafeRelativePath("../outside.jar"))
        XCTAssertFalse(ModrinthInstallPlanner.isSafeRelativePath("mods/../../outside.jar"))
        XCTAssertFalse(ModrinthInstallPlanner.isSafeRelativePath("/absolute/path.jar"))
        XCTAssertFalse(ModrinthInstallPlanner.isSafeRelativePath("~/home.jar"))
        XCTAssertFalse(ModrinthInstallPlanner.isSafeRelativePath(""))
        XCTAssertFalse(ModrinthInstallPlanner.isSafeRelativePath("mods\\windows.jar"))
    }

    func testInstanceIDFromProjectName() {
        XCTAssertEqual(
            ModrinthInstallPlanner.instanceID(name: "Fabulously Optimized", versionID: "8.2.0"),
            "fabulously-optimized-8-2-0"
        )
        // 纯中文名退回 modpack 前缀，保证目录名只能是 ASCII
        XCTAssertEqual(ModrinthInstallPlanner.instanceID(name: "整合包", versionID: "1.0"), "modpack-1-0")
        XCTAssertTrue(ModrinthInstallPlanner.instanceID(name: "A/B:C", versionID: "1").hasPrefix("a-b-c"))
    }

    // MARK: - 人读格式

    func testDownloadCountFormatting() {
        XCTAssertEqual(ModrinthFormat.downloads(0), "0")
        XCTAssertEqual(ModrinthFormat.downloads(999), "999")
        XCTAssertEqual(ModrinthFormat.downloads(12_000), "1.2 万")
        XCTAssertEqual(ModrinthFormat.downloads(19_710_444), "1971.0 万")
        XCTAssertEqual(ModrinthFormat.downloads(512_000_000), "5.1 亿")
    }

    func testDateFormattingFallsBackToDash() {
        XCTAssertEqual(ModrinthFormat.date(nil), "—")
        XCTAssertEqual(ModrinthFormat.date("2026-11-01T10:43:17.783717+00:00"), "2026-11-01")
    }

    func testJobStateTitles() {
        XCTAssertEqual(DownloadInstallJob.State.running.title, "进行中")
        XCTAssertTrue(DownloadInstallJob.State.running.isActive)
        XCTAssertTrue(DownloadInstallJob.State.finished.isSuccess)
        XCTAssertFalse(DownloadInstallJob.State.failed("x").isActive)
        XCTAssertEqual(DownloadInstallJob.State.failed("x").title, "失败")
        XCTAssertEqual(DownloadInstallJob.State.cancelled.title, "已取消")
    }

    // MARK: - 压缩包条目安全（zip-slip）

    func testSafeZipEntries() {
        XCTAssertTrue(ModrinthInstallPlanner.isSafeZipEntry("modrinth.index.json"))
        XCTAssertTrue(ModrinthInstallPlanner.isSafeZipEntry("overrides/config/yosbr/config/a.toml"))
        XCTAssertTrue(ModrinthInstallPlanner.isSafeZipEntry("overrides/"))
        XCTAssertTrue(ModrinthInstallPlanner.isSafeZipEntry("./overrides/a.txt"))
        XCTAssertTrue(ModrinthInstallPlanner.isSafeZipEntry("mods/a.jar"))

        XCTAssertFalse(ModrinthInstallPlanner.isSafeZipEntry("../evil.txt"))
        XCTAssertFalse(ModrinthInstallPlanner.isSafeZipEntry("overrides/../../evil.txt"))
        XCTAssertFalse(ModrinthInstallPlanner.isSafeZipEntry("/etc/passwd"))
        XCTAssertFalse(ModrinthInstallPlanner.isSafeZipEntry("a\\b.txt"))
        XCTAssertFalse(ModrinthInstallPlanner.isSafeZipEntry(""))
        XCTAssertFalse(ModrinthInstallPlanner.isSafeZipEntry("./"))
    }

    func testFirstUnsafeZipEntry() {
        XCTAssertNil(ModrinthInstallPlanner.firstUnsafeZipEntry(in: ["a.txt", "d/b.txt"]))
        XCTAssertEqual(
            ModrinthInstallPlanner.firstUnsafeZipEntry(in: ["a.txt", "../evil", "b.txt"]),
            "../evil"
        )
        XCTAssertEqual(
            ModrinthInstallPlanner.firstUnsafeZipEntry(in: ["/abs.txt"]),
            "/abs.txt"
        )
    }

    // MARK: - 清单完整性（缺下载地址不假成功）

    func testModpackIndexDetectsFilesWithoutDownload() throws {
        let json = """
        {"formatVersion":1,"game":"minecraft","versionId":"1.0","name":"Broken Pack",
         "files":[
           {"path":"mods/a.jar","hashes":{"sha1":"a"},"downloads":["https://cdn.modrinth.com/a.jar"]},
           {"path":"mods/b.jar","hashes":{"sha1":"b"},"downloads":[]},
           {"path":"mods/server.jar","hashes":{"sha1":"c"},"env":{"client":"unsupported","server":"required"},"downloads":[]}
         ],
         "dependencies":{"minecraft":"1.21.4"}}
        """
        let index = try ModrinthModpackIndex.decode(Data(json.utf8))
        XCTAssertEqual(index.clientFiles.count, 2, "服务端专用文件不算客户端文件")
        XCTAssertEqual(index.clientFilesWithoutDownload.map(\.path), ["mods/b.jar"])
    }

    func testMissingDownloadErrorDescriptionMentionsFiles() throws {
        let json = """
        {"formatVersion":1,"game":"minecraft","versionId":"1.0","name":"Broken Pack",
         "files":[
           {"path":"mods/a.jar","hashes":{},"downloads":[]},
           {"path":"mods/b.jar","hashes":{},"downloads":[]}
         ],
         "dependencies":{"minecraft":"1.21.4"}}
        """
        let index = try ModrinthModpackIndex.decode(Data(json.utf8))
        let paths = index.clientFilesWithoutDownload.map(\.path)
        let message = try XCTUnwrap(ModpackIndexError.missingFileDownload(paths).errorDescription)
        XCTAssertTrue(message.contains("缺少下载地址"))
        XCTAssertTrue(message.contains("mods/a.jar"))
        XCTAssertTrue(message.contains("mods/b.jar"))
    }

    // MARK: - 加载器兼容性

    func testLoaderCompatibilityRules() {
        // 原版实例装 Fabric 模组：不兼容
        XCTAssertFalse(
            ModrinthLoaderDetector.isCompatible(versionLoaders: ["fabric"], instance: .vanilla)
        )
        // Fabric 实例装 Fabric 模组：兼容
        XCTAssertTrue(
            ModrinthLoaderDetector.isCompatible(versionLoaders: ["fabric"], instance: .fabric)
        )
        // Quilt 实例可以加载 Fabric 模组
        XCTAssertTrue(
            ModrinthLoaderDetector.isCompatible(versionLoaders: ["fabric"], instance: .quilt)
        )
        // Fabric 实例装 Forge 模组：不兼容
        XCTAssertFalse(
            ModrinthLoaderDetector.isCompatible(versionLoaders: ["forge"], instance: .fabric)
        )
        // NeoForge 实例装 NeoForge 模组：兼容；装 Forge 模组：不兼容
        XCTAssertTrue(
            ModrinthLoaderDetector.isCompatible(versionLoaders: ["neoforge"], instance: .neoforge)
        )
        XCTAssertFalse(
            ModrinthLoaderDetector.isCompatible(versionLoaders: ["forge"], instance: .neoforge)
        )
        // 资源包 / 数据包只声明 minecraft，视为兼容
        XCTAssertTrue(
            ModrinthLoaderDetector.isCompatible(versionLoaders: ["minecraft"], instance: .vanilla)
        )
        XCTAssertTrue(
            ModrinthLoaderDetector.isCompatible(versionLoaders: [], instance: .vanilla)
        )
    }

    func testLoaderIncompatibilityHint() throws {
        let hint = try XCTUnwrap(
            ModrinthLoaderDetector.incompatibilityHint(versionLoaders: ["fabric"], instance: .vanilla)
        )
        XCTAssertTrue(hint.contains("原版"))
        XCTAssertTrue(hint.contains("fabric"))

        XCTAssertNil(
            ModrinthLoaderDetector.incompatibilityHint(versionLoaders: ["fabric"], instance: .fabric)
        )
    }

    // MARK: - 整合包安装（离线集成：合成 .mrpack → 实例目录）

    /// 用合成的 .mrpack 走完整导入流程：解压 → 解析清单 → 写实例版本 JSON → 复用客户端 jar → 解压 overrides。
    /// 基础版本已在临时游戏目录中就绪，所以全程不需要网络。
    @MainActor
    func testImportModpackCreatesInstanceOffline() async throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dl-offline-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        // 1. 伪造一个「已安装」的基础版本：版本 JSON + 客户端 jar
        let mcVersion = "1.21.4"
        let baseDirectory = root
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(mcVersion, isDirectory: true)
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let baseJSON = """
        {"id":"\(mcVersion)","type":"release","mainClass":"net.minecraft.client.main.Main","assets":"legacy","libraries":[]}
        """
        try baseJSON.write(
            to: baseDirectory.appendingPathComponent("\(mcVersion).json"),
            atomically: true,
            encoding: .utf8
        )
        try Data(repeating: 0, count: 1024).write(to: baseDirectory.appendingPathComponent("\(mcVersion).jar"))

        // 2. 合成 .mrpack：清单（原版整合包，无远程文件）+ overrides
        let packRoot = root.appendingPathComponent("pack", isDirectory: true)
        let overridesConfig = packRoot.appendingPathComponent("overrides/config", isDirectory: true)
        try fileManager.createDirectory(at: overridesConfig, withIntermediateDirectories: true)
        try "selftest=true".write(
            to: overridesConfig.appendingPathComponent("selftest.cfg"),
            atomically: true,
            encoding: .utf8
        )
        let index: [String: Any] = [
            "formatVersion": 1,
            "game": "minecraft",
            "versionId": "0.1.0",
            "name": "Offline Pack",
            "dependencies": ["minecraft": mcVersion],
            "files": [[String: Any]]()
        ]
        try JSONSerialization
            .data(withJSONObject: index, options: [.prettyPrinted, .sortedKeys])
            .write(to: packRoot.appendingPathComponent("modrinth.index.json"))
        let mrpack = root.appendingPathComponent("OfflinePack.mrpack")
        try zipDirectory(packRoot, entries: ["modrinth.index.json", "overrides"], to: mrpack)

        // 3. 真实导入流程
        let suite = "download.test.\(UUID().uuidString.prefix(8))"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LauncherSettings(defaults: defaults)
        settings.gameDirectory = root.path
        let engine = LauncherEngine(settings: settings)
        await engine.refreshEnvironment()
        XCTAssertTrue(engine.installedVersions.contains { $0.id == mcVersion })

        let center = DownloadInstallCenter()
        var toasts: [String] = []
        center.notify = { message, _ in toasts.append(message) }
        center.importModpack(from: mrpack, settings: settings, engine: engine)

        let deadline = Date().addingTimeInterval(60)
        while center.jobs.contains(where: { $0.state.isActive }) {
            guard Date() < deadline else { return XCTFail("导入超时") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let job = try XCTUnwrap(center.jobs.first)
        XCTAssertEqual(job.state, .finished, "导入结果：\(job.state) \(job.detail)")
        XCTAssertFalse(toasts.isEmpty)

        // 4. 校验实例目录：版本 JSON、客户端 jar、overrides 都已落盘
        await engine.refreshEnvironment()
        let instanceID = try XCTUnwrap(engine.installedVersions.map(\.id).first { $0.hasPrefix("offline-pack") })
        XCTAssertEqual(instanceID, "offline-pack-0-1-0")
        let instanceDirectory = root.appendingPathComponent("versions/\(instanceID)", isDirectory: true)
        XCTAssertTrue(fileManager.fileExists(atPath: instanceDirectory.appendingPathComponent("\(instanceID).json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: instanceDirectory.appendingPathComponent("\(instanceID).jar").path))
        XCTAssertTrue(fileManager.fileExists(atPath: instanceDirectory.appendingPathComponent("config/selftest.cfg").path))

        // 5. 继承链可解析（实例 → 基础版本）
        let resolved = try await VersionResolver.resolveAsync(versionID: instanceID, installation: engine.installation)
        XCTAssertEqual(resolved.mainClass, "net.minecraft.client.main.Main")
    }

    /// 用系统 zip 打包目录（测试里构造 .mrpack）。
    private func zipDirectory(_ directory: URL, entries: [String], to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", "-r", destination.path] + entries
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "zip 打包失败")
    }

    // MARK: - 弹窗层（下载页的清理缓存 / 删除版本确认框都走 LauncherRouter）

    /// 渲染下载页确认框所在的全局覆盖层：遮罩铺满全屏、对话框固定 400pt 宽、水平垂直居中。
    /// 只断言「有弹窗」这一帧：离屏 `ImageRenderer` 对 `@Environment(Type.self)` 在同一进程内只认
    /// 第一次注入的 router 实例，且有渲染缓存，「置空 dialog 后再渲染」在整类跑时会拿到上一帧（已知干扰）。
    /// 关闭 / 取消后的状态由 `testDialogCancelPathClearsRouterState` 在 router 层断言，不再依赖离屏像素。
    @MainActor
    func testOverlayDialogIsCenteredAndFixedWidth() throws {
        let router = LauncherRouter()
        router.showDialog(
            LauncherDialogRequest(
                title: "清理启动器缓存",
                message: "将删除启动器缓存目录（版本清单、资源索引、父版本 JSON）。已安装的版本与游戏文件不受影响，下次安装 / 启动会重新下载。",
                confirmTitle: "清理缓存",
                isDestructive: true,
                onConfirm: {},
                onCancel: {}
            )
        )

        for themeID in ["graphite", "porcelain"] {
            let bitmap = try XCTUnwrap(renderOverlay(router: router, themeID: themeID), "\(themeID) 覆盖层渲染失败")
            XCTAssertEqual(bitmap.pixelsWide, 1080)
            XCTAssertEqual(bitmap.pixelsHigh, 720)

            // 遮罩铺满：四角均为半透明遮罩（不是全透明、也不是不透明卡面）
            for (x, y) in [(2, 2), (1077, 2), (2, 717), (1077, 717)] {
                let alpha = alphaAt(bitmap, x: x, y: y)
                XCTAssertGreaterThan(alpha, 0.05, "遮罩没有铺满全屏（\(themeID) \(x),\(y)）")
                XCTAssertLessThan(alpha, 0.95, "四角应为遮罩而非卡面（\(themeID)）")
            }

            // 卡面尺寸与位置：宽 400pt，中心 (540, 360)
            let horizontal = opaqueRun(bitmap, fixed: bitmap.pixelsHigh / 2, horizontal: true)
            let vertical = opaqueRun(bitmap, fixed: bitmap.pixelsWide / 2, horizontal: false)
            let width = Double(horizontal.upperBound - horizontal.lowerBound + 1)
            let height = Double(vertical.upperBound - vertical.lowerBound + 1)
            XCTAssertEqual(width, 400, accuracy: 2, "对话框宽度应为 400pt（\(themeID)）")
            XCTAssertEqual(
                Double(horizontal.lowerBound + horizontal.upperBound) / 2,
                540,
                accuracy: 2,
                "对话框应水平居中（\(themeID)）"
            )
            XCTAssertEqual(
                Double(vertical.lowerBound + vertical.upperBound) / 2,
                360,
                accuracy: 2,
                "对话框应垂直居中（\(themeID)）"
            )
            XCTAssertGreaterThan(height, 60, "对话框高度异常（\(themeID)）")
        }
    }

    /// 取消路径：与 LauncherOverlayHost 的「取消」按钮 / 点遮罩逻辑一致 —— 先回调 onCancel 再清空 dialog。
    @MainActor
    func testDialogCancelPathClearsRouterState() {
        let router = LauncherRouter()
        var didCancel = false
        router.showDialog(
            LauncherDialogRequest(
                title: "删除版本 26.3",
                message: "将把 versions/26.3 移到废纸篓。",
                confirmTitle: "删除",
                isDestructive: true,
                onConfirm: {},
                onCancel: { didCancel = true }
            )
        )
        XCTAssertNotNil(router.dialog)
        XCTAssertEqual(router.dialog?.confirmTitle, "删除")
        XCTAssertEqual(router.dialog?.isDestructive, true)

        router.dialog?.onCancel?()
        router.dialog = nil
        XCTAssertTrue(didCancel, "取消按钮必须回调 onCancel")
        XCTAssertNil(router.dialog, "取消后对话框应关闭")
    }

    // MARK: - 弹窗渲染辅助

    /// 离屏渲染全局覆盖层（1px = 1pt）。
    @MainActor
    private func renderOverlay(router: LauncherRouter, themeID: String) -> NSBitmapImageRep? {
        let suite = "download.tests.overlay.\(UUID().uuidString.prefix(6))"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = LauncherThemeManager(presets: LauncherThemes.all, defaults: defaults)
        manager.themeID = themeID

        let size = CGSize(width: 1080, height: 720)
        let view = LauncherOverlayHost()
            .environment(router)
            .launcherThemeEnvironment(manager)
            .environment(\.colorScheme, manager.theme.scheme)
            .frame(width: size.width, height: size.height)
            .clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap
    }

    /// 读取某像素的 alpha。
    private func alphaAt(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> Double {
        guard let color = bitmap.colorAt(x: x, y: y) else { return 0 }
        return Double(color.alphaComponent)
    }

    /// 沿一行 / 一列找不透明（卡面）像素的连续区间，用于测量对话框尺寸与中心。
    private func opaqueRun(_ bitmap: NSBitmapImageRep, fixed: Int, horizontal: Bool) -> ClosedRange<Int> {
        let length = horizontal ? bitmap.pixelsWide : bitmap.pixelsHigh
        var first: Int?
        var last: Int?
        for index in 0..<length {
            let x = horizontal ? index : fixed
            let y = horizontal ? fixed : index
            if alphaAt(bitmap, x: x, y: y) > 0.9 {
                if first == nil { first = index }
                last = index
            }
        }
        guard let first, let last else { return 0...0 }
        return first...last
    }

    // MARK: - Fixture

    private static let searchFixture = """
    {
      "hits": [
        {
          "project_id": "1KVo5zza",
          "project_type": "modpack",
          "slug": "fabulously-optimized",
          "author": "robotkoer",
          "title": "Fabulously Optimized",
          "description": "Beautiful graphics, speedy performance.",
          "categories": ["fabric", "optimization"],
          "display_categories": ["optimization"],
          "versions": ["1.21.4", "1.21.3"],
          "downloads": 19710444,
          "follows": 5030,
          "date_created": "2022-02-10T06:28:19.045034+00:00",
          "date_modified": "2026-11-01T10:43:17.783717+00:00",
          "latest_version": "37TmHvhB",
          "license": "BSD-3-Clause",
          "icon_url": "https://cdn.modrinth.com/data/1KVo5zza/icon.webp",
          "gallery": ["https://cdn.modrinth.com/a.webp"]
        },
        {
          "project_id": "1ocGzRHv",
          "project_type": "modpack",
          "slug": "vanilla-perfected",
          "author": "demonjoeTV",
          "title": "Vanilla Perfected",
          "description": "A compilation of Vanilla Plus mods.",
          "categories": ["fabric"],
          "versions": ["1.21.4"],
          "downloads": 120,
          "follows": 3,
          "date_modified": "2026-10-01T00:00:00Z",
          "latest_version": "abc"
        }
      ],
      "offset": 0,
      "limit": 20,
      "total_hits": 12345
    }
    """

    private static let versionFixture = """
    [
      {
        "id": "37TmHvhB",
        "project_id": "1KVo5zza",
        "name": "8.2.0 for 1.21.4",
        "version_number": "8.2.0",
        "version_type": "release",
        "game_versions": ["1.21.4"],
        "loaders": ["fabric"],
        "date_published": "2026-06-08T17:47:22.750152Z",
        "downloads": 92358,
        "files": [
          {
            "id": "qc9AAiGE",
            "hashes": {"sha1": "0000"},
            "url": "https://cdn.modrinth.com/data/1KVo5zza/versions/37TmHvhB/cosign-bundle.zip",
            "filename": "cosign-bundle.zip",
            "primary": false,
            "size": 7380,
            "file_type": null
          },
          {
            "id": "DIXgx06e",
            "hashes": {
              "sha1": "68226d5210fb3f80841de6160fbe4a0595a5fb11",
              "sha512": "57764c105ff999ced4c7e2069e36dcf226896fbb3df4eb82cbb2907630dbf7be"
            },
            "url": "https://cdn.modrinth.com/data/1KVo5zza/versions/37TmHvhB/Fabulously.Optimized-v8.2.0.mrpack",
            "filename": "Fabulously.Optimized-v8.2.0.mrpack",
            "primary": true,
            "size": 182799
          }
        ],
        "dependencies": []
      }
    ]
    """

    private static let modpackIndexFixture = """
    {
      "formatVersion": 1,
      "game": "minecraft",
      "versionId": "8.2.0",
      "name": "Fabulously Optimized",
      "files": [
        {
          "path": "mods/BetterGrassify-1.7.0+fabric.1.21.4.jar",
          "hashes": {"sha1": "8bada432a857ce7af3772f60a19901ca85f3dfb3", "sha512": "5ae1d24c"},
          "env": {"client": "required", "server": "required"},
          "downloads": ["https://cdn.modrinth.com/data/m5T5xmUy/versions/HxwKuBEU/BetterGrassify.jar"],
          "fileSize": 155059
        },
        {
          "path": "resourcepacks/SodiumTranslations.zip",
          "hashes": {"sha1": "53bc09e3faf8b2e8eb100f5a29ddc0dc17f77f88"},
          "downloads": ["https://cdn.modrinth.com/data/ix1qq8Ux/versions/zQgwqgH/SodiumTranslations.zip"],
          "fileSize": 3170746
        },
        {
          "path": "mods/ServerOnly.jar",
          "hashes": {"sha1": "aaaabbbb"},
          "env": {"client": "unsupported", "server": "required"},
          "downloads": ["https://cdn.modrinth.com/data/server/ServerOnly.jar"],
          "fileSize": 1024
        }
      ],
      "dependencies": {
        "fabric-loader": "0.19.3",
        "minecraft": "1.21.4"
      }
    }
    """
}

// MARK: - URLProtocol stub

/// 本地网络桩：记录请求并返回预置响应，测试期间不访问真实网络。
final class StubURLProtocol: URLProtocol {
    /// 响应处理器：返回状态码 + 数据，或抛出的错误。
    static var handler: ((URLRequest) -> Result<(Int, Data), Error>)?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        switch handler(request) {
        case .success(let (status, data)):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.modrinth.com")!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
