import SwiftUI
import AppKit
import LauncherUI

/// 方块启动器 UI 模板 —— 可执行 App。
@MainActor
struct MCLauncherApp: App {
    @State private var themeManager = LauncherThemeManager()

    var body: some Scene {
        WindowGroup("方块启动器") {
            LauncherShellView()
                .launcherThemeEnvironment(themeManager)
                .frame(minWidth: 1120, minHeight: 720)
                .background { WindowConfigurator() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1380, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// MARK: - 入口：GUI 或离屏截图

let arguments = CommandLine.arguments
let exitCode: Int32 = MainActor.assumeIsolated {
    if let index = arguments.firstIndex(of: "--export-snapshots") {
        let output = index + 1 < arguments.count ? arguments[index + 1] : "Snapshots"
        return SnapshotExporter.run(outputDir: output)
    }
    MCLauncherApp.main()
    return 0
}
exit(exitCode)
