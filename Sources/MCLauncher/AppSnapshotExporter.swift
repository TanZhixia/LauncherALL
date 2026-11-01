import SwiftUI
import AppKit
import LauncherUI

/// 启动器主界面截图导出：2 套主题 × 4 个导航页。
@MainActor
enum AppSnapshotExporter {
    static func run(outputDir: String) -> Int32 {
        let directory = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let suite = "launcher.app.snapshot.export"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let manager = LauncherThemeManager(presets: LauncherThemes.all, defaults: defaults)

        var failures = 0
        var exported = 0
        for theme in LauncherThemes.all {
            manager.themeID = theme.id
            manager.borderStrength = 1.0
            manager.cornerScale = 1.0

            for tab in LauncherTab.allCases {
                let view = LauncherAppShell(initialTab: tab)
                    .launcherThemeEnvironment(manager)
                    .environment(\.colorScheme, theme.scheme)
                    .environment(\.launcherSnapshotMode, true)
                    .frame(width: 1440, height: 900, alignment: .topLeading)
                    .clipped()
                    .background(theme.colors.canvas)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 1.5
                renderer.proposedSize = ProposedViewSize(width: 1440, height: 900)
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    print("✗ 渲染失败：\(theme.id)-\(tab.rawValue)")
                    failures += 1
                    continue
                }
                let url = directory.appendingPathComponent("app-\(theme.id)-\(tab.rawValue).png")
                do {
                    try png.write(to: url)
                    exported += 1
                } catch {
                    print("✗ 写入失败：\(url.lastPathComponent)")
                    failures += 1
                }
            }
        }
        defaults.removePersistentDomain(forName: suite)
        print("启动器界面导出完成：\(exported) 张，失败 \(failures) 张，目录 \(directory.path)")
        return failures == 0 ? 0 : 1
    }
}
