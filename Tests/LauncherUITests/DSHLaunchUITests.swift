import XCTest
import SwiftUI
import AppKit

@testable import LauncherUI

/// DSH 启动页测试：实例模型纯逻辑 + 两主题 1080×720 离屏渲染。
/// 渲染验证「多实例同名版本 / 整合包实例 / 空态」不崩溃、不溢出；需要人工看图时可设置环境变量
/// `DSH_LAUNCH_SNAPSHOT_DIR=/tmp/dsh-launch-snap` 再跑本文件，会把 PNG 写到该目录。
final class DSHLaunchUITests: XCTestCase {

    // MARK: - Fixture

    /// 构造一个已安装实例（完整 init）。
    private func makeInstance(
        id: String,
        name: String,
        dshVersion: String,
        size: Int64 = 1_234_567,
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
            sizeBytes: size,
            kind: kind,
            packName: packName,
            packVersion: packVersion,
            legacy: false
        )
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

    // MARK: - URL 脱敏

    func testSanitizedURLHidesTokenButKeepsAddress() {
        let raw = "http://127.0.0.1:3080/?token=secret-token&theme=dark"
        let sanitized = DSHLaunchPresentation.sanitizedURL(raw)
        XCTAssertTrue(sanitized.contains("127.0.0.1:3080"), "应保留主机与端口：\(sanitized)")
        XCTAssertTrue(sanitized.contains("token=****"), "token 应被掩码：\(sanitized)")
        XCTAssertFalse(sanitized.contains("secret-token"), "不能泄露 token：\(sanitized)")
        XCTAssertTrue(sanitized.contains("theme=dark"), "普通 query 应保留：\(sanitized)")
        XCTAssertEqual(DSHLaunchPresentation.sanitizedURL(""), "—")
        XCTAssertEqual(DSHLaunchPresentation.sanitizedURL("   "), "—")
        XCTAssertFalse(DSHLaunchPresentation.sanitizedURL("not-a-url?token=abc").contains("abc"))
    }

    // MARK: - 状态展示

    func testStatusPresentationCoversAllStates() {
        XCTAssertEqual(DSHLaunchPresentation.statusTitle(.idle), "未运行")
        XCTAssertEqual(DSHLaunchPresentation.statusTitle(.starting), "启动中")
        XCTAssertEqual(DSHLaunchPresentation.statusTitle(.stopping), "停止中")
        XCTAssertEqual(DSHLaunchPresentation.statusTitle(.failed("boom")), "启动失败")
        XCTAssertEqual(DSHLaunchPresentation.statusTitle(.running(url: "http://127.0.0.1:3080/?token=x")), "运行中")

        XCTAssertEqual(DSHLaunchPresentation.statusDetail(.idle), "启动后会在默认浏览器打开 DSH Web UI（带一次性 token）。")
        XCTAssertEqual(
            DSHLaunchPresentation.statusDetail(.running(url: "http://127.0.0.1:3080/?token=x")),
            "http://127.0.0.1:3080/?token=****"
        )
        XCTAssertEqual(DSHLaunchPresentation.statusDetail(.failed("启动失败原因")), "启动失败原因")

        if case .danger = DSHLaunchPresentation.statusTone(.failed("x")) {} else {
            XCTFail("失败状态应为 danger 色调")
        }
        if case .success = DSHLaunchPresentation.statusTone(.running(url: "u")) {} else {
            XCTFail("运行状态应为 success 色调")
        }
        if case .neutral = DSHLaunchPresentation.statusTone(.idle) {} else {
            XCTFail("空闲状态应为 neutral 色调")
        }
        XCTAssertEqual(DSHLaunchPresentation.statusIcon(.running(url: "u")), "checkmark.circle.fill")
    }

    // MARK: - 端口 / 时间

    func testPortAndTimeText() {
        XCTAssertEqual(DSHLaunchPresentation.portText(activePort: 3099, fallback: 3080), "3099")
        XCTAssertEqual(DSHLaunchPresentation.portText(activePort: nil, fallback: 3081), "3081")
        XCTAssertEqual(DSHLaunchPresentation.startedAtText(nil), "尚未启动")
        XCTAssertTrue(DSHLaunchPresentation.startedAtText(Date()).hasPrefix("启动于 "))
    }

    // MARK: - 实例模型

    func testInstanceModelFieldsAndConvenienceInit() {
        let instance = makeInstance(
            id: "ins-1", name: "我的实例", dshVersion: "1.1.0",
            kind: .pack, packName: "Starter Kit", packVersion: "1.2.0"
        )
        XCTAssertEqual(instance.id, "ins-1")
        XCTAssertEqual(instance.name, "我的实例")
        XCTAssertEqual(instance.dshVersion, "1.1.0")
        XCTAssertEqual(instance.version, "1.1.0", "version 兼容属性应等于 dshVersion")
        XCTAssertTrue(instance.isPack)
        XCTAssertEqual(instance.packName, "Starter Kit")
        XCTAssertEqual(instance.packVersion, "1.2.0")

        // 兼容构造器（旧测试 / 旧目录迁移）。
        let legacy = DSHInstalledVersion(version: "1.0.0", installedAt: Date(), path: "/tmp/v1", sizeBytes: 10)
        XCTAssertEqual(legacy.id, "1.0.0")
        XCTAssertEqual(legacy.dshVersion, "1.0.0")
        XCTAssertFalse(legacy.isPack)
    }

    func testFilteredInstancesSupportsSameDSHVersionWithDifferentNames() {
        let instances = [
            makeInstance(id: "ins-1", name: "PVP 整合", dshVersion: "1.1.0"),
            makeInstance(id: "ins-2", name: "PVP 整合 副本", dshVersion: "1.1.0"),
            makeInstance(id: "ins-3", name: "建筑服", dshVersion: "1.0.0")
        ]
        XCTAssertEqual(DSHLaunchPresentation.filteredInstances(instances, query: "PVP").map(\.id), ["ins-1", "ins-2"])
        XCTAssertEqual(DSHLaunchPresentation.filteredInstances(instances, query: "1.0.0").map(\.id), ["ins-3"])
        XCTAssertEqual(DSHLaunchPresentation.filteredInstances(instances, query: "INS-2").map(\.id), ["ins-2"])
        XCTAssertEqual(DSHLaunchPresentation.filteredInstances(instances, query: "  ").count, 3)
        XCTAssertEqual(DSHLaunchPresentation.filteredInstances(instances, query: "不存在").count, 0)
    }

    func testInstanceSubtitlesAndPackBadge() {
        let vanilla = makeInstance(id: "ins-1", name: "实例 A", dshVersion: "1.1.0", size: 2_400_000)
        XCTAssertEqual(DSHLaunchPresentation.listSubtitle(vanilla), "DSH 1.1.0")
        let detail = DSHLaunchPresentation.detailSubtitle(vanilla)
        XCTAssertTrue(detail.hasPrefix("DSH 1.1.0"), "副标题应包含 DSH 版本：\(detail)")
        XCTAssertTrue(detail.contains("安装"), "副标题应包含安装时间：\(detail)")
        XCTAssertTrue(detail.contains("MB"), "副标题应包含体积：\(detail)")

        XCTAssertNil(DSHLaunchPresentation.packInfoText(vanilla))
        let pack = makeInstance(
            id: "ins-pack", name: "Starter", dshVersion: "1.0.0",
            kind: .pack, packName: "Starter Kit", packVersion: "1.2.0"
        )
        XCTAssertEqual(DSHLaunchPresentation.packInfoText(pack), "整合包：Starter Kit 1.2.0")
        XCTAssertEqual(DSHLaunchPresentation.instanceBadge(pack, isRunning: false), "整合包")
        XCTAssertEqual(DSHLaunchPresentation.instanceBadge(pack, isRunning: true), "运行中")
        XCTAssertNil(DSHLaunchPresentation.instanceBadge(vanilla, isRunning: false))
    }

    func testRunningInstanceMatchesByIDNotVersion() {
        let first = makeInstance(id: "ins-1", name: "实例 1", dshVersion: "1.1.0")
        let second = makeInstance(id: "ins-2", name: "实例 2", dshVersion: "1.1.0")

        XCTAssertTrue(DSHLaunchPresentation.isRunning(first, activeInstanceID: "ins-1"))
        XCTAssertFalse(DSHLaunchPresentation.isRunning(second, activeInstanceID: "ins-1"))
        XCTAssertFalse(DSHLaunchPresentation.isRunning(first, activeInstanceID: nil))
        XCTAssertFalse(DSHLaunchPresentation.isRunning(first, activeInstanceID: ""))

        let running = DSHLaunchPresentation.runningInstance(in: [first, second], activeInstanceID: "ins-2")
        XCTAssertEqual(running?.id, "ins-2")
        XCTAssertNil(DSHLaunchPresentation.runningInstance(in: [first, second], activeInstanceID: "missing"))
    }

    // MARK: - 整合包导出入口

    func testExportMenuTitlesAndFileName() {
        XCTAssertTrue(DSHLaunchPresentation.exportMenuTitle(runtime: .bundled).contains("整合包"))
        XCTAssertTrue(DSHLaunchPresentation.exportMenuTitle(runtime: .bundled).contains("完整包"))
        XCTAssertTrue(DSHLaunchPresentation.exportMenuTitle(runtime: .online).contains("轻量包"))

        XCTAssertEqual(DSHLaunchPresentation.exportFileName(instanceName: "Starter Kit"), "Starter Kit.dshpack")
        XCTAssertEqual(DSHLaunchPresentation.exportFileName(instanceName: "a/b:c"), "a-b-c.dshpack")
        XCTAssertEqual(DSHLaunchPresentation.exportFileName(instanceName: "   "), "dsh-instance.dshpack")
        XCTAssertTrue(DSHLaunchPresentation.exportFileName(instanceName: "x").hasSuffix(".dshpack"))

        let instance = makeInstance(
            id: "ins-pack", name: "Starter", dshVersion: "1.0.0",
            kind: .pack, packName: "Starter Kit", packVersion: "1.2.0"
        )
        XCTAssertEqual(DSHLaunchPresentation.exportPackName(instance: instance), "Starter")
        XCTAssertEqual(DSHLaunchPresentation.exportPackVersion(instance: instance), "1.2.0")
        XCTAssertNotNil(DSHLaunchPresentation.exportDisabledReason(snapshotMode: true, isBusy: false))
        XCTAssertNotNil(DSHLaunchPresentation.exportDisabledReason(snapshotMode: false, isBusy: true))
        XCTAssertNil(DSHLaunchPresentation.exportDisabledReason(snapshotMode: false, isBusy: false))
    }

    func testUninstallDisabledReasonPriority() {
        let instance = makeInstance(id: "ins-1", name: "实例", dshVersion: "1.1.0")
        XCTAssertTrue(
            DSHLaunchPresentation.uninstallDisabledReason(
                instance: instance, activeInstanceID: nil, isBusy: false, isInstalling: true
            )?.contains("安装") == true
        )
        XCTAssertTrue(
            DSHLaunchPresentation.uninstallDisabledReason(
                instance: instance, activeInstanceID: nil, isBusy: true, isInstalling: false
            )?.contains("停止") == true
        )
        XCTAssertTrue(
            DSHLaunchPresentation.uninstallDisabledReason(
                instance: instance, activeInstanceID: "ins-1", isBusy: false, isInstalling: false
            )?.contains("正在运行") == true
        )
        XCTAssertNil(
            DSHLaunchPresentation.uninstallDisabledReason(
                instance: instance, activeInstanceID: "other", isBusy: false, isInstalling: false
            )
        )
    }

    // MARK: - 启停 / 安装条件

    func testStartDisabledReasonPriority() {
        XCTAssertEqual(
            DSHLaunchPresentation.startDisabledReason(hasSelection: false, hasNode: false, isInstalling: true, isBusy: false),
            "正在安装 DSH，安装完成后才能启动"
        )
        XCTAssertEqual(
            DSHLaunchPresentation.startDisabledReason(hasSelection: true, hasNode: true, isInstalling: false, isBusy: true),
            "正在启动或停止 DSH，请稍候"
        )
        XCTAssertEqual(
            DSHLaunchPresentation.startDisabledReason(hasSelection: false, hasNode: true, isInstalling: false, isBusy: false),
            "请先在左侧选择已安装的 DSH 实例"
        )
        XCTAssertEqual(
            DSHLaunchPresentation.startDisabledReason(hasSelection: true, hasNode: false, isInstalling: false, isBusy: false),
            DSHError.nodeNotFound.localizedDescription
        )
        XCTAssertNil(
            DSHLaunchPresentation.startDisabledReason(hasSelection: true, hasNode: true, isInstalling: false, isBusy: false)
        )
    }

    func testInstallPhaseText() {
        XCTAssertNil(DSHLaunchPresentation.installPhaseText(.idle))
        XCTAssertEqual(
            DSHLaunchPresentation.installPhaseText(.installing(version: "1.1.0", phase: .downloading)),
            "正在安装 DSH 1.1.0 · 下载 DSH 依赖包…"
        )
        XCTAssertEqual(DSHLaunchPresentation.installPhaseText(.failed(version: "1.1.0", message: "网络失败")), "网络失败")
        XCTAssertTrue(DSHLaunchPresentation.isInstallFailed(.failed(version: "1.1.0", message: "x")))
        XCTAssertFalse(DSHLaunchPresentation.isInstallFailed(.idle))
    }

    // MARK: - 日志 / 环境

    func testLogTailAndTone() {
        let logs = (0..<20).map { "line-\($0)" }
        let tail = DSHLaunchPresentation.logTail(logs, limit: 12)
        XCTAssertEqual(tail.count, 12)
        XCTAssertEqual(tail.first, "line-8")
        XCTAssertEqual(tail.last, "line-19")
        XCTAssertEqual(DSHLaunchPresentation.logTail(logs, limit: 0).count, 0)

        if case .danger = DSHLaunchPresentation.logTone("ERROR: failed to bind") {} else {
            XCTFail("error 日志应为 danger")
        }
        if case .warning = DSHLaunchPresentation.logTone("warn: port in use") {} else {
            XCTFail("warn 日志应为 warning")
        }
        if case .success = DSHLaunchPresentation.logTone("✓ dsh web 已启动") {} else {
            XCTFail("成功日志应为 success")
        }
    }

    func testEnvironmentText() {
        XCTAssertEqual(DSHLaunchEnvironment(nodePath: nil, packageManager: nil).environmentText, "未找到 Node.js 运行时")
        XCTAssertEqual(
            DSHLaunchEnvironment(nodePath: "/usr/local/bin/node", packageManager: "pnpm").environmentText,
            "Node /usr/local/bin/node · pnpm"
        )
        XCTAssertFalse(DSHLaunchEnvironment(nodePath: nil, packageManager: "pnpm").hasNode)
        XCTAssertTrue(DSHLaunchEnvironment.placeholder.isPlaceholder)
    }

    // MARK: - 两主题 1080×720 离屏渲染

    /// 真实渲染 DSH 启动页（整壳，DSH 产品）：多实例同名版本 + 整合包实例 + 空态，两主题 1080×720。
    /// 设置 `DSH_LAUNCH_SNAPSHOT_DIR` 时把 PNG 写盘，便于人工检查是否溢出。
    @MainActor
    func testOffscreenRenderDSHLaunchPageAtMinimumWindow() async throws {
        let suite = "dsh.launch.ui.tests.\(UUID().uuidString.prefix(8))"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removePersistentDomain(forName: suite)

        let manager = LauncherThemeManager(presets: LauncherThemes.all, defaults: defaults)
        let settings = LauncherSettings(defaults: defaults)
        let accountStore = AccountStore(settings: settings, tokenStore: InMemoryAuthTokenStore())
        let engine = LauncherEngine(settings: settings, accountStore: accountStore)

        // 临时 DSH 目录：三个实例（同 DSH 版本两个 + 一个整合包实例），不碰用户真实目录。
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DSHLaunchUITests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = DSHPaths(root: root, homeRoot: root.appendingPathComponent("homes", isDirectory: true))
        try paths.ensureDirectories()

        let instances = [
            makeInstance(id: "ins-a", name: "PVP 整合", dshVersion: "1.1.0", size: 2_400_000),
            makeInstance(id: "ins-b", name: "PVP 整合 副本", dshVersion: "1.1.0", size: 2_100_000),
            makeInstance(
                id: "ins-pack", name: "Starter Kit", dshVersion: "1.0.0", size: 3_600_000,
                kind: .pack, packName: "Starter Kit", packVersion: "1.2.0"
            )
        ]
        for instance in instances {
            try seedInstance(instance, paths: paths)
        }
        settings.dshSelectedInstanceID = "ins-a"

        let versions = DSHVersionStore(settings: settings, paths: paths)
        versions.setCatalogForTesting(
            DSHVersionCatalog(
                versions: [DSHVersionInfo(version: "1.1.0"), DSHVersionInfo(version: "1.0.0")],
                distTags: ["latest": "1.1.0"],
                fetchedAt: Date()
            )
        )
        let process = DSHProcessController(settings: settings, paths: paths)
        let plugins = DSHPluginStore(settings: settings, paths: paths)
        let packs = DSHPackService(paths: paths, versions: versions, plugins: plugins, settings: settings)

        // 模型侧断言：同版本多实例都保留、选中按实例 ID、整合包实例识别正确。
        XCTAssertEqual(versions.installed.count, 3)
        XCTAssertEqual(versions.installed.filter { $0.dshVersion == "1.1.0" }.count, 2)
        XCTAssertEqual(versions.selectedInstalledVersion?.id, "ins-a")
        XCTAssertEqual(versions.installed.filter(\.isPack).count, 1)

        let exportDirectory = ProcessInfo.processInfo.environment["DSH_LAUNCH_SNAPSHOT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }

        let size = CGSize(width: 1080, height: 720)
        for theme in LauncherThemes.all {
            manager.themeID = theme.id
            let view = LauncherAppShell(initialTab: .launch, initialProduct: .dsh)
                .environment(engine)
                .environment(accountStore)
                .environment(versions)
                .environment(process)
                .environment(plugins)
                .environment(packs)
                .launcherThemeEnvironment(manager)
                .environment(\.colorScheme, theme.scheme)
                .environment(\.launcherSnapshotMode, true)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
                .background(theme.colors.canvas)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.5
            renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
            let image = try XCTUnwrap(renderer.nsImage, "DSH 启动页渲染失败：\(theme.id)")
            XCTAssertGreaterThan(image.size.width, 0, "渲染尺寸异常：\(theme.id)")
            XCTAssertGreaterThan(image.size.height, 0, "渲染尺寸异常：\(theme.id)")

            if let exportDirectory {
                try savePNG(image, to: exportDirectory.appendingPathComponent("dsh-launch-instances-\(theme.id)-min.png"))
            }
        }

        // 空态（没有任何实例）：侧栏空态 + 当前实例卡提示同样不能溢出。
        let emptyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DSHLaunchUITests-empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        let emptyPaths = DSHPaths(root: emptyRoot, homeRoot: emptyRoot.appendingPathComponent("homes", isDirectory: true))
        try emptyPaths.ensureDirectories()
        let emptySuite = "dsh.launch.ui.empty.\(UUID().uuidString.prefix(8))"
        let emptyDefaults = UserDefaults(suiteName: emptySuite) ?? .standard
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        let emptyVersions = DSHVersionStore(settings: LauncherSettings(defaults: emptyDefaults), paths: emptyPaths)
        let emptyProcess = DSHProcessController(settings: settings, paths: emptyPaths)
        let emptyPlugins = DSHPluginStore(settings: settings, paths: emptyPaths)
        let emptyPacks = DSHPackService(paths: emptyPaths, versions: emptyVersions, plugins: emptyPlugins, settings: settings)

        for theme in LauncherThemes.all {
            manager.themeID = theme.id
            let view = LauncherAppShell(initialTab: .launch, initialProduct: .dsh)
                .environment(engine)
                .environment(accountStore)
                .environment(emptyVersions)
                .environment(emptyProcess)
                .environment(emptyPlugins)
                .environment(emptyPacks)
                .launcherThemeEnvironment(manager)
                .environment(\.colorScheme, theme.scheme)
                .environment(\.launcherSnapshotMode, true)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
                .background(theme.colors.canvas)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.5
            renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
            let image = try XCTUnwrap(renderer.nsImage, "DSH 启动页空态渲染失败：\(theme.id)")

            if let exportDirectory {
                try savePNG(image, to: exportDirectory.appendingPathComponent("dsh-launch-empty-\(theme.id)-min.png"))
            }
        }
    }

    // MARK: - 渲染辅助

    @MainActor
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
