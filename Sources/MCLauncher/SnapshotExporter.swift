import SwiftUI
import AppKit
import LauncherUI

/// 离屏渲染：把每个主题 × 每个画廊页导出为 PNG，用于视觉验收与文档配图。
@MainActor
enum SnapshotExporter {
    static func run(outputDir: String) -> Int32 {
        let directory = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let suite = "launcher.snapshot.export"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)

        let manager = LauncherThemeManager(presets: LauncherThemes.all, defaults: defaults)
        var failures = 0
        var exported = 0

        for theme in LauncherThemes.all {
            manager.themeID = theme.id
            manager.glassIntensity = 1.0
            manager.cornerScale = 1.0

            for section in LauncherGallerySection.allCases {
                let view = LauncherShellView(initialSection: section)
                    .launcherThemeEnvironment(manager)
                    .environment(\.colorScheme, theme.scheme)
                    .environment(\.launcherSnapshotMode, true)
                    .frame(width: 1440, height: 900)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 1.5
                renderer.proposedSize = ProposedViewSize(width: 1440, height: 900)

                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    print("✗ render failed: \(theme.id)-\(section.rawValue)")
                    failures += 1
                    continue
                }

                let url = directory.appendingPathComponent("\(theme.id)-\(section.rawValue).png")
                do {
                    try png.write(to: url)
                    exported += 1
                } catch {
                    print("✗ write failed: \(url.lastPathComponent) \(error)")
                    failures += 1
                }
            }
        }

        defaults.removePersistentDomain(forName: suite)
        print("导出完成：\(exported) 张，失败 \(failures) 张，目录 \(directory.path)")
        return failures == 0 ? 0 : 1
    }
}
