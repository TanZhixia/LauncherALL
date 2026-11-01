import SwiftUI
import AppKit
import LauncherUI

/// XML UI 工具链：命令行校验与离屏渲染，方便 CI 或设计稿比对。
@MainActor
enum XMLTool {
    /// `--validate-xml <file>`：打印诊断并以退出码表示是否通过。
    static func validate(path: String) -> Int32 {
        guard let source = readSource(path) else { return 2 }
        let document = LauncherXMLDocument.parse(source)
        if document.diagnostics.isEmpty {
            print("✓ \(path) 解析通过")
        } else {
            for diagnostic in document.diagnostics {
                let flag = diagnostic.severity == .error ? "✗" : "!"
                print("\(flag) \(diagnostic.displayText)")
            }
        }
        let output = XMLRenderer().render(
            document: document,
            actions: XMLActionRegistry.demo(themeManager: nil),
            data: XMLSampleLibrary.data(for: "launcher"),
            theme: LauncherThemes.default
        )
        for diagnostic in output.diagnostics where document.diagnostics.isEmpty {
            print("! \(diagnostic.displayText)")
        }
        let failed = output.diagnostics.contains { $0.severity == .error }
        return failed ? 1 : 0
    }

    /// `--render-xml <file> <out.png> [--theme graphite|porcelain] [--width N] [--height N]`
    static func render(arguments: [String], startIndex: Int) -> Int32 {
        guard startIndex + 1 < arguments.count else {
            print("用法：--render-xml <input.xml> <output.png> [--theme graphite|porcelain] [--width 1280] [--height 900]")
            return 2
        }
        let input = arguments[startIndex]
        let outputPath = arguments[startIndex + 1]
        guard let source = readSource(input) else { return 2 }

        var themeID = LauncherThemes.default.id
        var width: CGFloat = 1280
        var height: CGFloat = 900
        var index = startIndex + 2
        while index < arguments.count {
            switch arguments[index] {
            case "--theme" where index + 1 < arguments.count:
                themeID = arguments[index + 1]
                index += 2
            case "--width" where index + 1 < arguments.count:
                width = CGFloat(Double(arguments[index + 1]) ?? 1280)
                index += 2
            case "--height" where index + 1 < arguments.count:
                height = CGFloat(Double(arguments[index + 1]) ?? 900)
                index += 2
            default:
                index += 1
            }
        }
        let theme = LauncherThemes.theme(withID: themeID)
        let document = LauncherXMLDocument.parse(source)
        let view = LauncherXMLView(
            source: source,
            actions: XMLActionRegistry.demo(themeManager: nil),
            data: XMLSampleLibrary.data(for: "launcher")
        )
        .environment(\.launcherTheme, theme)
        .environment(\.colorScheme, theme.scheme)
        .environment(\.launcherSnapshotMode, true)
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .background(theme.colors.canvas)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.5
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            print("✗ 渲染失败")
            return 3
        }
        let url = URL(fileURLWithPath: outputPath)
        do {
            try png.write(to: url)
        } catch {
            print("✗ 写文件失败：\(error.localizedDescription)")
            return 3
        }
        print("✓ 已渲染 \(input) -> \(outputPath)（\(Int(width))x\(Int(height)) · \(theme.name) · 诊断 \(document.diagnostics.count) 条）")
        return document.isValid ? 0 : 1
    }

    /// `--export-xml-snapshots <dir>`：把全部内置示例 × 主题渲染成 PNG（交付配图用）。
    static func exportSnapshots(directory: String) -> Int32 {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var failures = 0
        var exported = 0
        for theme in LauncherThemes.all {
            for sample in XMLSampleLibrary.all {
                let view = LauncherXMLView(
                    source: sample.source,
                    actions: XMLActionRegistry.demo(themeManager: nil),
                    data: sample.data
                )
                .environment(\.launcherTheme, theme)
                .environment(\.colorScheme, theme.scheme)
                .environment(\.launcherSnapshotMode, true)
                .frame(width: 1280, height: 1200, alignment: .topLeading)
                .clipped()
                .background(theme.colors.canvas)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 1.5
                renderer.proposedSize = ProposedViewSize(width: 1280, height: 1200)
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    print("✗ 渲染失败：\(theme.id)-\(sample.id)")
                    failures += 1
                    continue
                }
                let url = folder.appendingPathComponent("\(theme.id)-\(sample.id).png")
                do {
                    try png.write(to: url)
                    exported += 1
                } catch {
                    print("✗ 写入失败：\(url.lastPathComponent)")
                    failures += 1
                }
            }
        }
        print("XML 示例导出完成：\(exported) 张，失败 \(failures) 张，目录 \(folder.path)")
        return failures == 0 ? 0 : 1
    }

    /// `--list-xml-samples`：列出内置示例。
    static func listSamples() -> Int32 {
        for sample in XMLSampleLibrary.all {
            print("- \(sample.id)  \(sample.title)  （\(sample.summary)）  \(sample.source.count) 字符")
        }
        return 0
    }

    private static func readSource(_ path: String) -> String? {
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("✗ 读取失败：\(path)")
            return nil
        }
        return source
    }
}
