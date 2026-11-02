import SwiftUI
import AppKit
import LauncherUI

/// 启动器主界面截图导出：2 套主题 × 4 个导航页。
@MainActor
enum AppSnapshotExporter {
    static func run(outputDir: String) async -> Int32 {
        let directory = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let suite = "launcher.app.snapshot.export"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let manager = LauncherThemeManager(presets: LauncherThemes.all, defaults: defaults)

        let settings = LauncherSettings(defaults: defaults)
        let engine = LauncherEngine(settings: settings, accountStore: AccountStore(settings: settings, tokenStore: InMemoryAuthTokenStore()))
        let dshPaths = DSHPaths(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("launcher-snapshot-dsh", isDirectory: true))
        let dshVersions = DSHVersionStore(settings: settings, paths: dshPaths)
        let dshProcess = DSHProcessController(settings: settings, paths: dshPaths)
        let dshPlugins = DSHPluginStore(settings: settings, paths: dshPaths)
        await engine.refreshEnvironment()

        var failures = 0
        var exported = 0
        for theme in LauncherThemes.all {
            manager.themeID = theme.id
            manager.borderStrength = 1.0
            manager.cornerScale = 1.0

            let sizes: [(width: CGFloat, height: CGFloat, prefix: String)] = [
                (1440, 900, "app-"),
                (1080, 720, "app-min-")   // 最小窗口验收：不应出现纵向滚动
            ]
            for tab in LauncherTab.allCases {
              for size in sizes {
                let view = LauncherAppShell(initialTab: tab)
                    .environment(engine)
                    .environment(engine.accountStore)
                    .environment(dshVersions)
                    .environment(dshProcess)
                    .environment(dshPlugins)
                    .launcherThemeEnvironment(manager)
                    .environment(\.colorScheme, theme.scheme)
                    .environment(\.launcherSnapshotMode, true)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                    .background(theme.colors.canvas)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 1.5
                renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    print("✗ 渲染失败：\(theme.id)-\(tab.rawValue)")
                    failures += 1
                    continue
                }
                let url = directory.appendingPathComponent("\(size.prefix)\(theme.id)-\(tab.rawValue).png")
                do {
                    try png.write(to: url)
                    exported += 1
                } catch {
                    print("✗ 写入失败：\(url.lastPathComponent)")
                    failures += 1
                }
              }
            }

            // DSH 启动器的四个页面（与 Minecraft 同尺寸/同主题）
            for tab in LauncherTab.allCases {
              for size in sizes {
                let view = LauncherAppShell(initialTab: tab, initialProduct: .dsh)
                    .environment(engine)
                    .environment(engine.accountStore)
                    .environment(dshVersions)
                    .environment(dshProcess)
                    .environment(dshPlugins)
                    .launcherThemeEnvironment(manager)
                    .environment(\.colorScheme, theme.scheme)
                    .environment(\.launcherSnapshotMode, true)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                    .background(theme.colors.canvas)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 1.5
                renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    print("✗ 渲染失败：\(theme.id)-dsh-\(tab.rawValue)")
                    failures += 1
                    continue
                }
                let filename = "\(size.prefix)\(theme.id)-dsh-\(tab.rawValue).png"
                let url = directory.appendingPathComponent(filename)
                do {
                    try png.write(to: url)
                    exported += 1
                } catch {
                    print("✗ 写入失败：\(filename)")
                    failures += 1
                }
              }
            }
        }
        defaults.removePersistentDomain(forName: suite)
        print("启动器界面导出完成：\(exported) 张，失败 \(failures) 张，目录 \(directory.path)")
        return failures == 0 ? 0 : 1
    }
}
