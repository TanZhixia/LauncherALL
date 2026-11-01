import XCTest
import SwiftUI
@testable import LauncherUI

/// 启动链路后端测试：规则、UUID、参数替换、JSON 兼容、版本扫描、命令构建。
final class LauncherBackendTests: XCTestCase {

    // MARK: 离线 UUID

    func testOfflineUUIDMatchesMinecraftAlgorithm() {
        XCTAssertEqual(
            LaunchCommandBuilder.offlineUUID(for: "Steve"),
            "5627dd98-e6be-3c21-b8a8-e92344183641"
        )
    }

    // MARK: 规则求值

    func testRulesAllowDisallow() throws {
        let json = """
        [
          {"action":"allow"},
          {"action":"disallow","os":{"name":"windows"}}
        ]
        """
        let rules = try JSONDecoder().decode([Rule].self, from: Data(json.utf8))
        XCTAssertTrue(RuleEvaluator.isAllowed(rules))
    }

    func testRulesDisallowCurrentOS() throws {
        let json = """
        [{"action":"allow"},{"action":"disallow","os":{"name":"osx"}}]
        """
        let rules = try JSONDecoder().decode([Rule].self, from: Data(json.utf8))
        XCTAssertFalse(RuleEvaluator.isAllowed(rules))
    }

    func testRulesRequireFeatureAreFiltered() throws {
        let json = """
        [{"action":"allow","features":{"has_quick_plays_support":true}}]
        """
        let rules = try JSONDecoder().decode([Rule].self, from: Data(json.utf8))
        XCTAssertFalse(RuleEvaluator.isAllowed(rules))
    }

    // MARK: 参数替换

    func testSubstitution() {
        XCTAssertEqual(
            LaunchCommandBuilder.substitute("--username ${auth_player_name} --gameDir ${game_directory}", values: [
                "auth_player_name": "Steve",
                "game_directory": "/tmp/game"
            ]),
            "--username Steve --gameDir /tmp/game"
        )
    }

    func testSanitizeDropsUnresolvedPlaceholders() {
        let cleaned = LaunchCommandBuilder.sanitize([
            "--username", "Steve",
            "--quickPlaySingleplayer", "${quickPlaySingleplayer}",
            "--demo"
        ])
        XCTAssertEqual(cleaned, ["--username", "Steve", "--demo"])
    }

    // MARK: Java 版本解析

    func testParseJavaVersionTemurin() {
        let output = """
        openjdk version "21.0.5" 2024-10-15
        OpenJDK Runtime Environment Temurin-21.0.5+11 (build 21.0.5+11-LTS)
        OpenJDK 64-Bit Server VM Temurin-21.0.5+11 (build 21.0.5+11-LTS, mixed mode)
        """
        let runtime = JavaLocator.parseVersionOutput(output, executable: URL(fileURLWithPath: "/tmp/java"))
        XCTAssertEqual(runtime?.version, "21.0.5")
        XCTAssertEqual(runtime?.majorVersion, 21)
        XCTAssertEqual(runtime?.vendor, "Temurin")
    }

    func testParseJavaVersionLegacy8() {
        let output = """
        java version "1.8.0_402"
        Java(TM) SE Runtime Environment (build 1.8.0_402-b06)
        """
        let runtime = JavaLocator.parseVersionOutput(output, executable: URL(fileURLWithPath: "/tmp/java"))
        XCTAssertEqual(runtime?.majorVersion, 8)
    }

    // MARK: JSON 兼容性

    func testVersionDetailDecodesStringAndObjectArguments() throws {
        let json = """
        {
          "id": "1.21.4",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "libraries": [],
          "arguments": {
            "game": ["--username", "${auth_player_name}"],
            "jvm": ["-XstartOnFirstThread", {"rules": [{"action":"allow"}], "value": ["-Dfoo=bar"]}]
          },
          "javaVersion": {"component": "jre", "majorVersion": 21}
        }
        """
        let detail = try JSONDecoder().decode(VersionDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.arguments?.game.count, 2)
        XCTAssertEqual(detail.arguments?.jvm.count, 2)
        XCTAssertEqual(detail.arguments?.jvm[1].values, ["-Dfoo=bar"])
        XCTAssertEqual(detail.arguments?.jvm[0].values, ["-XstartOnFirstThread"])
    }

    func testVersionDetailAllowsMissingLoggingClient() throws {
        let json = """
        {"id":"x","type":"release","mainClass":"m","libraries":[],
         "logging":{"client":null}}
        """
        // client 为 null 也应能解码（部分整合包作者的 JSON 不标准）
        XCTAssertNoThrow(try JSONDecoder().decode(VersionDetail.self, from: Data(json.utf8)))
    }

    // MARK: 版本扫描

    func testInstalledVersionsRequiresJar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let versions = root.appendingPathComponent("versions")
        let fakeJSON = """
        {"id":"1.0","type":"release","mainClass":"m","libraries":[]}
        """
        let withJar = versions.appendingPathComponent("with-jar")
        try FileManager.default.createDirectory(at: withJar, withIntermediateDirectories: true)
        try Data(fakeJSON.utf8).write(to: withJar.appendingPathComponent("with-jar.json"))
        try Data().write(to: withJar.appendingPathComponent("with-jar.jar"))

        let jsonOnly = versions.appendingPathComponent("json-only")
        try FileManager.default.createDirectory(at: jsonOnly, withIntermediateDirectories: true)
        try Data(fakeJSON.utf8).write(to: jsonOnly.appendingPathComponent("json-only.json"))

        let installation = MinecraftInstallation(root: root)
        let installed = installation.installedVersions()
        XCTAssertEqual(installed.map(\.id), ["with-jar"])
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: 启动命令构建

    func testLaunchCommandBuildsClasspathAndArgs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let installation = MinecraftInstallation(root: root)
        let versionID = "1.21.4"
        let versionDir = installation.versionDirectory(versionID)
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)

        let libraryPath = "org/example/lib/1.0/lib-1.0.jar"
        let libraryFile = installation.librariesDirectory.appendingPathComponent(libraryPath)
        try FileManager.default.createDirectory(at: libraryFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: libraryFile)
        try Data().write(to: installation.versionJarURL(versionID))

        let json = """
        {
          "id": "\(versionID)",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "assetIndex": {"id": "17", "url": "https://example.com/index.json"},
          "libraries": [
            {"name": "org.example:lib:1.0",
             "downloads": {"artifact": {"path": "\(libraryPath)", "url": "https://example.com/lib.jar"}}}
          ],
          "arguments": {
            "game": ["--username", "${auth_player_name}", "--version", "${version_name}", "--uuid", "${auth_uuid}"],
            "jvm": ["-Djava.library.path=${natives_directory}"]
          },
          "javaVersion": {"component": "jre", "majorVersion": 21}
        }
        """
        try Data(json.utf8).write(to: installation.versionJSONURL(versionID))
        let resolved = try VersionResolver.resolve(versionID: versionID, installation: installation)
        XCTAssertEqual(resolved.requiredJavaMajor, 21)

        let java = JavaRuntime(
            id: "/tmp/java",
            executable: URL(fileURLWithPath: "/tmp/java"),
            version: "21.0.5",
            majorVersion: 21,
            vendor: "Temurin"
        )
        let options = LaunchOptions(
            versionID: versionID,
            playerName: "Steve",
            java: java,
            memoryMB: 4096,
            renderThreads: 4,
            extraJVMArguments: ["-Dtest=1"],
            gameDirectory: root
        )
        let command = try LaunchCommandBuilder.build(detail: resolved, installation: installation, options: options)

        XCTAssertEqual(command.executable.path, "/tmp/java")
        let joined = command.arguments.joined(separator: " ")
        XCTAssertTrue(joined.contains("-Xmx4096M"))
        XCTAssertTrue(joined.contains("-XX:ActiveProcessorCount=4"))
        XCTAssertTrue(joined.contains(installation.versionJarURL(versionID).path))
        XCTAssertTrue(joined.contains(libraryFile.path))
        XCTAssertTrue(joined.contains("-Dtest=1"))
        XCTAssertTrue(joined.contains("net.minecraft.client.main.Main"))
        XCTAssertTrue(joined.contains("--username Steve"))
        XCTAssertTrue(joined.contains("--version \(versionID)"))
        XCTAssertTrue(joined.contains(LaunchCommandBuilder.offlineUUID(for: "Steve")))
        try? FileManager.default.removeItem(at: root)
    }
}
