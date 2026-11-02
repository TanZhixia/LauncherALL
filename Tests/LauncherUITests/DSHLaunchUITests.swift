import XCTest
import SwiftUI
import AppKit

@testable import LauncherUI

/// DSH 启动页测试：纯展示逻辑 + 两主题 1080×720 离屏渲染。
/// 渲染只为验证「不崩溃 / 不溢出」，需要人工看图时可设置环境变量
/// `DSH_LAUNCH_SNAPSHOT_DIR=/tmp/dsh-launch-snap` 再跑本文件，会把两张 PNG 写到该目录。
final class DSHLaunchUITests: XCTestCase {

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
    }

    func testSanitizedURLHandlesMalformedURL() {
        let sanitized = DSHLaunchPresentation.sanitizedURL("not-a-url?token=abc")
        XCTAssertFalse(sanitized.contains("abc"))
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

    func testPortTextPrefersActivePort() {
        XCTAssertEqual(DSHLaunchPresentation.portText(activePort: 3099, fallback: 3080), "3099")
        XCTAssertEqual(DSHLaunchPresentation.portText(activePort: nil, fallback: 3081), "3081")
    }

    func testStartedAtText() {
        XCTAssertEqual(DSHLaunchPresentation.startedAtText(nil), "尚未启动")
        XCTAssertTrue(DSHLaunchPresentation.startedAtText(Date()).hasPrefix("启动于 "))
    }

    // MARK: - 版本列表

    func testFilteredVersionsAndLatest() {
        let versions = [
            DSHInstalledVersion(version: "1.1.0", installedAt: Date(), path: "/tmp/v/1.1.0", sizeBytes: 1_234_567),
            DSHInstalledVersion(version: "1.0.0", installedAt: Date(), path: "/tmp/v/1.0.0", sizeBytes: 100)
        ]
        XCTAssertEqual(DSHLaunchPresentation.filteredVersions(versions, query: "1.1").map(\.version), ["1.1.0"])
        XCTAssertEqual(DSHLaunchPresentation.filteredVersions(versions, query: "  ").count, 2)
        XCTAssertEqual(DSHLaunchPresentation.filteredVersions(versions, query: "9.9").count, 0)

        XCTAssertTrue(DSHLaunchPresentation.isLatest(versions[0], latestVersion: "1.1.0"))
        XCTAssertFalse(DSHLaunchPresentation.isLatest(versions[1], latestVersion: "1.1.0"))
        XCTAssertFalse(DSHLaunchPresentation.isLatest(versions[0], latestVersion: nil))
    }

    func testVersionSubtitleShowsDateAndSize() {
        let version = DSHInstalledVersion(
            version: "1.1.0",
            installedAt: Date(timeIntervalSince1970: 1_800_000_000),
            path: "/tmp/v/1.1.0",
            sizeBytes: 2_400_000
        )
        let subtitle = DSHLaunchPresentation.versionSubtitle(version)
        XCTAssertTrue(subtitle.contains(":"), "应显示安装时间：\(subtitle)")
        XCTAssertTrue(subtitle.contains("·"), "日期与体积应分隔：\(subtitle)")
        XCTAssertTrue(subtitle.contains("MB"), "应显示真实体积：\(subtitle)")
        XCTAssertEqual(DSHLaunchPresentation.sizeText(nil), "—")
        XCTAssertEqual(DSHLaunchPresentation.sizeText(0), "—")
    }

    // MARK: - 启动条件

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
            "请先在左侧选择已安装的 DSH 版本"
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

    // MARK: - 日志

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

    // MARK: - 环境摘要

    func testEnvironmentText() {
        XCTAssertEqual(DSHLaunchEnvironment(nodePath: nil, packageManager: nil).environmentText, "未找到 Node.js 运行时")
        XCTAssertEqual(
            DSHLaunchEnvironment(nodePath: "/usr/local/bin/node", packageManager: "pnpm").environmentText,
            "Node /usr/local/bin/node · pnpm"
        )
        XCTAssertEqual(
            DSHLaunchEnvironment(nodePath: "/usr/local/bin/node", packageManager: nil).environmentText,
            "Node /usr/local/bin/node · 未找到 pnpm / npm"
        )
        XCTAssertFalse(DSHLaunchEnvironment(nodePath: nil, packageManager: "pnpm").hasNode)
    }

    // MARK: - 两主题 1080×720 离屏渲染

    /// 真实渲染 DSH 启动页（整壳，DSH 产品）：两主题 1080×720，任一渲染失败 / 崩溃即测试失败。
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

        // 临时 DSH 目录：预置两个"已安装版本"（含入口脚本与安装元数据），不碰用户真实目录。
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DSHLaunchUITests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = DSHPaths(root: root, homeRoot: root.appendingPathComponent("home", isDirectory: true))
        try paths.ensureDirectories()

        struct InstallMetadata: Encodable {
            let version: String
            let installedAt: Date
            let sizeBytes: Int64?
        }
        for (version, size) in [("1.1.0", Int64(2_400_000)), ("1.0.0", Int64(1_800_000))] {
            let script = paths.cliScript(for: version)
            try FileManager.default.createDirectory(
                at: script.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "// fake dsh cli for offscreen tests\n".write(to: script, atomically: true, encoding: .utf8)
            let metadata = InstallMetadata(version: version, installedAt: Date(), sizeBytes: size)
            try JSONEncoder().encode(metadata).write(
                to: paths.versionDirectory(version).appendingPathComponent("launcher-install.json"),
                options: .atomic
            )
        }

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
                try? FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
                let tiff = try XCTUnwrap(image.tiffRepresentation, "无法导出 TIFF：\(theme.id)")
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff), "无法解码位图：\(theme.id)")
                let png = try XCTUnwrap(
                    bitmap.representation(using: .png, properties: [:]),
                    "无法编码 PNG：\(theme.id)"
                )
                try png.write(to: exportDirectory.appendingPathComponent("dsh-launch-\(theme.id)-min.png"))
            }
        }

        // 空态（没有任何已安装版本）：验证侧栏空态 + 启动卡"暂时无法启动"提示同样不溢出。
        let emptyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DSHLaunchUITests-empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        let emptyPaths = DSHPaths(root: emptyRoot, homeRoot: emptyRoot.appendingPathComponent("home", isDirectory: true))
        try emptyPaths.ensureDirectories()
        let emptySuite = "dsh.launch.ui.empty.\(UUID().uuidString.prefix(8))"
        let emptyDefaults = UserDefaults(suiteName: emptySuite) ?? .standard
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        let emptyVersions = DSHVersionStore(
            settings: LauncherSettings(defaults: emptyDefaults),
            paths: emptyPaths
        )
        let emptyProcess = DSHProcessController(settings: settings, paths: emptyPaths)
        let emptyPlugins = DSHPluginStore(settings: settings, paths: emptyPaths)

        for theme in LauncherThemes.all {
            manager.themeID = theme.id
            let view = LauncherAppShell(initialTab: .launch, initialProduct: .dsh)
                .environment(engine)
                .environment(accountStore)
                .environment(emptyVersions)
                .environment(emptyProcess)
                .environment(emptyPlugins)
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
                let tiff = try XCTUnwrap(image.tiffRepresentation, "无法导出 TIFF：\(theme.id)")
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff), "无法解码位图：\(theme.id)")
                let png = try XCTUnwrap(
                    bitmap.representation(using: .png, properties: [:]),
                    "无法编码 PNG：\(theme.id)"
                )
                try png.write(to: exportDirectory.appendingPathComponent("dsh-launch-empty-\(theme.id)-min.png"))
            }
        }
    }
}
