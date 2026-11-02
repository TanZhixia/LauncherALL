import XCTest
import Foundation
@testable import LauncherUI

/// DSH 启动器后端测试：版本比较、目录解析、插件加载源、安装/扫描、进程状态、命令执行。
final class DSHBackendTests: XCTestCase {

    // MARK: - 版本号

    func testSemanticVersionOrdering() {
        XCTAssertTrue(DSHVersionComparator.isNewer("0.2.1-rc.5", than: "0.2.1-rc.4"))
        XCTAssertTrue(DSHVersionComparator.isNewer("0.2.1", than: "0.2.1-rc.5"))
        XCTAssertTrue(DSHVersionComparator.isNewer("0.2.2-alpha.2", than: "0.2.1-rc.5"))
        XCTAssertTrue(DSHVersionComparator.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertFalse(DSHVersionComparator.isNewer("0.2.1-rc.5", than: "0.2.1-rc.5"))
        XCTAssertEqual(DSHVersionComparator.compare("0.2.1", "0.2.1"), .orderedSame)
        XCTAssertEqual(DSHVersionComparator.compare("0.2.1-alpha.1", "0.2.1-alpha.2"), .orderedAscending)

        let sorted = ["0.2.1-rc.5", "0.2.2-alpha.2", "0.2.0", "0.2.1-rc.4"]
            .sorted { DSHVersionComparator.isNewer($0, than: $1) }
        XCTAssertEqual(sorted, ["0.2.2-alpha.2", "0.2.1-rc.5", "0.2.1-rc.4", "0.2.0"])
    }

    // MARK: - npm 版本目录

    func testVersionCatalogDecoding() throws {
        let json = """
        {
          "name": "@deepseek-ai/dsh",
          "dist-tags": {"latest": "0.2.1-rc.5", "alpha": "0.2.2-alpha.2"},
          "versions": {
            "0.2.1-rc.5": {"version": "0.2.1-rc.5", "dist": {"tarball": "https://example.com/a.tgz", "unpackedSize": 1024}},
            "0.2.2-alpha.2": {"version": "0.2.2-alpha.2", "dist": {"tarball": "https://example.com/b.tgz", "unpackedSize": 2048}},
            "0.2.0": {"version": "0.2.0", "dist": {"tarball": "https://example.com/c.tgz"}}
          },
          "time": {
            "0.2.1-rc.5": "2026-10-29T13:55:07.029Z",
            "0.2.2-alpha.2": "2026-11-01T00:00:00.000Z"
          }
        }
        """
        let catalog = try DSHRegistryClient.decodeVersionCatalog(Data(json.utf8))
        XCTAssertEqual(catalog.versions.map(\.version), ["0.2.2-alpha.2", "0.2.1-rc.5", "0.2.0"])
        XCTAssertEqual(catalog.latest()?.version, "0.2.1-rc.5")
        XCTAssertEqual(catalog.latest(tag: "alpha")?.version, "0.2.2-alpha.2")
        XCTAssertEqual(catalog.versions[0].distTags, ["alpha"])
        XCTAssertEqual(catalog.versions[1].distTags, ["latest"])
        XCTAssertEqual(catalog.versions[2].distTags, [])
        XCTAssertEqual(catalog.versions[0].unpackedSize, 2048)
        XCTAssertNotNil(catalog.versions[0].publishedAt)
        XCTAssertTrue(catalog.versions[0].isPrerelease)
        XCTAssertFalse(catalog.versions[2].isPrerelease)
    }

    func testVersionsURLAvoidsDoubleEncoding() throws {
        let url = try DSHRegistryClient.versionsURL(registry: "https://registry.npmjs.org")
        XCTAssertEqual(url.absoluteString, "https://registry.npmjs.org/@deepseek-ai%2fdsh")
        XCTAssertFalse(url.absoluteString.contains("%252f"), "包名斜杠不能被二次编码")

        let withPath = try DSHRegistryClient.versionsURL(registry: "https://example.com/mirror/")
        XCTAssertEqual(withPath.absoluteString, "https://example.com/mirror/@deepseek-ai%2fdsh")
    }

    // MARK: - 插件加载源

    func testPluginCatalogDecodingAndInstallSpec() throws {
        let json = """
        {
          "name": "awesome-dsh-plugin",
          "url": "https://awesome-dsh-plugin.com",
          "source": "https://github.com/awesome-dsh-plugin/awesome-dsh-plugin",
          "updated": "2026-11-01",
          "count": 2,
          "categories": {
            "ui": {"en": "UI Enhancements", "zh": "界面增强"},
            "model": {"en": "Models", "zh": "模型"}
          },
          "plugins": [
            {
              "name": "dsh-tui",
              "owner": "ccch1mneyyy",
              "url": "https://github.com/ccch1mneyyy/dsh-TUI",
              "page": "https://awesome-dsh-plugin.com/p/ccch1mneyyy/dsh-tui/",
              "category": "ui",
              "description": {"en": "Terminal UI", "zh": "终端界面"},
              "npm": "@deepseek-harness-tui/dsh-tui",
              "version": "0.13.0",
              "stars": 100,
              "capabilities": ["shell"],
              "install": "dsh plugin --profile web add @deepseek-harness-tui/dsh-tui"
            },
            {
              "name": "DSH-AGINT",
              "owner": "Anmulzhao",
              "url": "https://github.com/Anmulzhao/DSH-AGINT",
              "category": "model",
              "description": {"zh": "自进化智能体框架"},
              "stars": 3,
              "install": "dsh plugin --profile web add github:Anmulzhao/DSH-AGINT"
            }
          ]
        }
        """
        let file = try JSONDecoder().decode(DSHPluginCatalogFile.self, from: Data(json.utf8))
        XCTAssertEqual(file.plugins.count, 2)
        XCTAssertEqual(file.count, 2)
        XCTAssertEqual(file.plugins[0].installSpec, "@deepseek-harness-tui/dsh-tui")
        XCTAssertEqual(file.plugins[1].installSpec, "github:Anmulzhao/DSH-AGINT")
        XCTAssertEqual(file.plugins[1].removeSpec, "github:Anmulzhao/DSH-AGINT")
        XCTAssertEqual(file.plugins[1].descriptionText, "自进化智能体框架")
        XCTAssertEqual(file.plugins[0].capabilities, ["shell"])
        XCTAssertEqual(file.plugins[0].categoryID, "ui")
        XCTAssertNil(file.plugins[0].page.flatMap { $0.isEmpty ? nil : $0 }.flatMap { _ in Optional<String>.none })
    }

    @MainActor
    func testPluginFilteringAndSorting() {
        let settings = makeSettings()
        let store = DSHPluginStore(settings: settings, paths: DSHPaths(root: tempRoot()))
        let ui = DSHPluginEntry(
            name: "dsh-ui", owner: "a", url: "https://github.com/a/dsh-ui",
            category: "ui", descriptionEN: "pretty interface", descriptionZH: "界面美化",
            npm: "dsh-ui", version: "1.0.0", stars: 5, install: "dsh plugin --profile web add dsh-ui"
        )
        let model = DSHPluginEntry(
            name: "dsh-model", owner: "b", url: "https://github.com/b/dsh-model",
            category: "model", descriptionEN: "model bridge", descriptionZH: "模型桥接",
            npm: "dsh-model", version: "2.0.0", stars: 50, install: "dsh plugin --profile web add dsh-model"
        )
        store.setCatalogForTesting(DSHPluginCatalog(
            plugins: [ui, model],
            categories: [
                DSHPluginCategory(id: "ui", titleEN: "UI", titleZH: "界面增强"),
                DSHPluginCategory(id: "model", titleEN: "Models", titleZH: "模型")
            ],
            updated: "2026-11-01",
            sourceURL: DSHRegistryClient.defaultPluginSource,
            fetchedAt: Date()
        ))

        XCTAssertEqual(store.filteredPlugins.map(\.name), ["dsh-model", "dsh-ui"], "默认按热度排序")
        store.sortMode = .name
        XCTAssertEqual(store.filteredPlugins.map(\.name), ["dsh-model", "dsh-ui"])

        store.searchText = "界面美化"
        XCTAssertEqual(store.filteredPlugins.map(\.name), ["dsh-ui"])
        store.searchText = "model bridge"
        XCTAssertEqual(store.filteredPlugins.map(\.name), ["dsh-model"])
        store.searchText = ""
        store.selectedCategoryID = "ui"
        XCTAssertEqual(store.filteredPlugins.map(\.name), ["dsh-ui"])
        store.selectedCategoryID = nil
        XCTAssertEqual(store.pluginCount, 2)
        XCTAssertEqual(store.categories.count, 2)
    }

    // MARK: - 目录布局

    func testPathsLayout() {
        let root = tempRoot()
        let paths = DSHPaths(root: root)
        XCTAssertEqual(paths.versionDirectory("0.2.1-rc.5").path, root.appendingPathComponent("versions/0.2.1-rc.5").path)
        XCTAssertEqual(paths.homeDirectory(for: "0.2.1-rc.5").path, root.appendingPathComponent("home").path, "所有版本共享 launcher 的 DSH_HOME")
        XCTAssertEqual(paths.homeDirectory(for: "0.9.9").path, paths.homeDirectory(for: "0.2.1-rc.5").path)
        XCTAssertEqual(paths.isolatedHomeDirectory(for: "0.2.1-rc.5").path, root.appendingPathComponent("homes/0.2.1-rc.5").path)
        XCTAssertEqual(paths.profileDirectory(for: "0.2.1-rc.5").path, root.appendingPathComponent("home/profiles/web").path)
        XCTAssertEqual(paths.logFile(for: "0.2.1-rc.5").lastPathComponent, "0.2.1-rc.5.log")
        XCTAssertTrue(paths.cliScript(for: "1.0.0").path.hasSuffix("node_modules/@deepseek-ai/dsh/lib/bin.js"))
        XCTAssertNoThrow(try paths.ensureDirectories())
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.versionsDirectory.path))
    }

    func testPortFinder() {
        XCTAssertFalse(DSHPortFinder.isAvailable(0))
        let port = DSHPortFinder.findPort(preferred: 0)
        XCTAssertGreaterThanOrEqual(port, 3080)
        XCTAssertLessThan(port, 3110)
    }

    func testIgnoredBuildPackagesParsing() {
        let output = """
        Progress: resolved 599, reused 595, downloaded 0, added 599, done
        Error: ERR_PNPM_IGNORED_BUILDS

          × adding a new package
          ╰─▶ Ignored build scripts: @deepseek-ai/dsh-subprocess-local@0.2.2-alpha.2,
              @google/genai@2.21.0, koffi@3.1.1, node-pty@1.2.0-beta.15,
              protobufjs@7.6.6
          help: Run "pnpm approve-builds" to pick which dependencies should be allowed
        """
        let packages = DSHVersionStore.ignoredBuildPackages(in: output)
        XCTAssertEqual(packages, [
            "@deepseek-ai/dsh-subprocess-local", "@google/genai", "koffi",
            "node-pty", "protobufjs"
        ])
        XCTAssertTrue(DSHVersionStore.ignoredBuildPackages(in: "no error here").isEmpty)
    }

    // MARK: - 已安装版本扫描

    @MainActor
    func testInstalledVersionScan() throws {
        let root = tempRoot()
        let paths = DSHPaths(root: root)
        try paths.ensureDirectories()
        let version = "0.2.1-rc.5"
        let bin = paths.cliScript(for: version)
        try FileManager.default.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: bin)
        let metadata = try JSONEncoder().encode(
            InstallMetadataFixture(version: version, installedAt: Date(timeIntervalSince1970: 1_700_000_000), sizeBytes: 123)
        )
        try metadata.write(to: paths.versionDirectory(version).appendingPathComponent("launcher-install.json"))

        let settings = makeSettings()
        let store = DSHVersionStore(settings: settings, paths: paths)
        XCTAssertEqual(store.installed.map(\.version), [version])
        XCTAssertEqual(store.installed.first?.sizeBytes, 123)
        XCTAssertEqual(settings.dshSelectedVersion, version, "首次扫描没有选中版本时自动选择")
        XCTAssertEqual(store.selectedInstalledVersion?.version, version)

        store.select("9.9.9")
        XCTAssertEqual(store.selectedInstalledVersion?.version, version, "未安装版本不能被选中")
        XCTAssertTrue(store.uninstall(version))
        XCTAssertTrue(store.installed.isEmpty)
        XCTAssertEqual(settings.dshSelectedVersion, "")
    }

    private struct InstallMetadataFixture: Codable {
        let version: String
        let installedAt: Date
        let sizeBytes: Int64?
    }

    // MARK: - 已安装插件

    @MainActor
    func testInstalledPluginsReadProfileManifest() throws {
        let root = tempRoot()
        let paths = DSHPaths(root: root)
        let profile = paths.profileDirectory(for: "0.2.1-rc.5")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let manifest = """
        {
          "name": "dsh-profile-web",
          "private": true,
          "dependencies": {
            "@deepseek-harness-tui/dsh-tui": "0.13.0",
            "github:Anmulzhao/DSH-AGINT": "github:Anmulzhao/DSH-AGINT"
          }
        }
        """
        try manifest.write(to: profile.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let store = DSHPluginStore(settings: makeSettings(), paths: paths)
        let installed = DSHInstalledVersion(version: "0.2.1-rc.5", installedAt: Date(), path: paths.versionDirectory("0.2.1-rc.5").path)
        let plugins = store.installedPlugins(for: installed)
        XCTAssertEqual(plugins.map(\.dependencyKey), ["@deepseek-harness-tui/dsh-tui", "github:Anmulzhao/DSH-AGINT"])
        XCTAssertEqual(plugins.first?.version, "0.13.0")
        XCTAssertTrue(store.isInstalled(
            DSHPluginEntry(
                name: "dsh-tui", owner: "x", url: "https://example.com",
                npm: "@deepseek-harness-tui/dsh-tui", install: "dsh plugin --profile web add @deepseek-harness-tui/dsh-tui"
            ),
            in: installed
        ))
    }

    // MARK: - 安全

    func testTokenSanitization() {
        let line = "dsh web: http://127.0.0.1:3080/?token=AbC-123_xyz&foo=1"
        let sanitized = DSHProcessController.sanitizedTokenLine(line)
        XCTAssertTrue(sanitized.contains("token=***"))
        XCTAssertFalse(sanitized.contains("AbC-123_xyz"))
        XCTAssertTrue(sanitized.contains("foo=1"))
        XCTAssertEqual(DSHProcessController.sanitizedTokenLine("普通日志"), "普通日志")
    }

    @MainActor
    func testUnsafeVersionRejected() async {
        XCTAssertFalse(DSHPaths.isSafeVersion("../etc/passwd"))
        XCTAssertFalse(DSHPaths.isSafeVersion("a/b"))
        XCTAssertFalse(DSHPaths.isSafeVersion(""))
        XCTAssertTrue(DSHPaths.isSafeVersion("0.2.1-rc.5"))

        let store = DSHVersionStore(settings: makeSettings(), paths: DSHPaths(root: tempRoot()))
        await store.install("../evil")
        if case .failed(_, let message) = store.installState {
            XCTAssertTrue(message.contains("无效") || message.contains("版本"))
        } else {
            XCTFail("非法版本号应被拒绝：\(store.installState)")
        }
        XCTAssertFalse(store.uninstall("../evil"))
    }

    @MainActor
    func testIsInstalledMatchesGitDependencyValue() throws {
        let root = tempRoot()
        let paths = DSHPaths(root: root)
        let profile = paths.profileDirectory(for: "0.2.1-rc.5")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        // pnpm 对 github 依赖：key=包名，value=spec
        try """
        {"name":"dsh-profile-web","private":true,"dependencies":{"dsh-agint":"github:Anmulzhao/DSH-AGINT"}}
        """.write(to: profile.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let store = DSHPluginStore(settings: makeSettings(), paths: paths)
        let version = DSHInstalledVersion(version: "0.2.1-rc.5", installedAt: Date(), path: paths.versionDirectory("0.2.1-rc.5").path)
        let entry = DSHPluginEntry(
            name: "DSH-AGINT", owner: "Anmulzhao", url: "https://github.com/Anmulzhao/DSH-AGINT",
            install: "dsh plugin --profile web add github:Anmulzhao/DSH-AGINT"
        )
        XCTAssertTrue(store.isInstalled(entry, in: version), "github 依赖的 value 是 spec，应判定为已安装")
    }

    // MARK: - 进程控制器

    @MainActor
    func testStartMissingVersionFailsClearly() async {
        let store = DSHVersionStore(settings: makeSettings(), paths: DSHPaths(root: tempRoot()))
        let controller = DSHProcessController(settings: makeSettings(), paths: DSHPaths(root: tempRoot()))
        let version = DSHInstalledVersion(version: "0.2.1-rc.5", installedAt: Date(), path: store.paths.versionDirectory("0.2.1-rc.5").path)
        let started = await controller.start(version: version)
        XCTAssertFalse(started)
        guard case .failed(let message) = controller.state else {
            return XCTFail("应进入失败态：\(controller.state)")
        }
        XCTAssertTrue(message.contains("尚未安装") || message.contains("DSH"))

        await controller.stop()
        XCTAssertEqual(controller.state, .idle)
        controller.stopSynchronously()
        XCTAssertEqual(controller.state, .idle)
    }

    func testProcessStateHelpers() {
        XCTAssertTrue(DSHProcessState.running(url: "http://x").isRunning)
        XCTAssertEqual(DSHProcessState.running(url: "http://x").url, "http://x")
        XCTAssertTrue(DSHProcessState.starting.isBusy)
        XCTAssertTrue(DSHProcessState.stopping.isBusy)
        XCTAssertFalse(DSHProcessState.idle.isBusy)
        XCTAssertFalse(DSHProcessState.failed("x").isRunning)
    }

    // MARK: - 命令执行

    func testCommandRunnerStreamsAndReturnsExitCode() async throws {
        let collected = OutputBox()
        let result = try await DSHCommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo hello; echo world >&2; exit 3"],
            environment: ProcessInfo.processInfo.environment
        ) { line in
            collected.append(line)
        }
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertTrue(result.output.contains("hello"))
        XCTAssertTrue(result.output.contains("world"))
        XCTAssertTrue(collected.text.contains("hello"))
    }

    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }
    }

    // MARK: - pnpm shim

    func testPnpmShimIsExecutableScript() throws {
        let paths = DSHPaths(root: tempRoot())
        let node = URL(fileURLWithPath: "/bin/sh")
        let script = URL(fileURLWithPath: "/tmp/pnpm.mjs")
        let shim = try DSHExecutables.makePnpmShim(paths: paths, node: node, script: script)
        let content = try String(contentsOf: shim, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("#!/bin/sh"))
        XCTAssertTrue(content.contains(script.path))
        XCTAssertTrue(content.contains(node.path))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: shim.path)[.posixPermissions] as? Int, 0o755)
    }

    // MARK: - 设置

    func testDSHSettingsDefaultsAndPersistence() {
        let suite = "launcher.tests.dsh.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = LauncherSettings(defaults: defaults)
        XCTAssertEqual(settings.dshPort, 3080)
        XCTAssertTrue(settings.dshAutoOpenBrowser)
        XCTAssertEqual(settings.dshSelectedVersion, "")
        XCTAssertEqual(settings.dshPluginSource, DSHRegistryClient.defaultPluginSource)
        XCTAssertEqual(settings.dshRegistry, "")

        settings.dshPort = 4090
        settings.dshSelectedVersion = "0.2.1-rc.5"
        settings.dshAutoOpenBrowser = false
        settings.dshPluginSource = "https://example.com/plugins.json"
        settings.dshRegistry = "https://registry.example.com"

        let reloaded = LauncherSettings(defaults: defaults)
        XCTAssertEqual(reloaded.dshPort, 4090)
        XCTAssertEqual(reloaded.dshSelectedVersion, "0.2.1-rc.5")
        XCTAssertFalse(reloaded.dshAutoOpenBrowser)
        XCTAssertEqual(reloaded.dshPluginSource, "https://example.com/plugins.json")
        XCTAssertEqual(reloaded.dshRegistry, "https://registry.example.com")
    }

    // MARK: - 辅助

    private func tempRoot() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-tests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    @MainActor
    private func makeSettings() -> LauncherSettings {
        let suite = "launcher.tests.dsh.store.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return LauncherSettings(defaults: defaults)
    }
}
