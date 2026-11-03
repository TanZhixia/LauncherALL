import SwiftUI
import AppKit
import LauncherUI

/// LauncherALL App：Minecraft 启动器 + DSH 启动器共用一个壳。
@MainActor
struct MCLauncherApp: App {
    @State private var themeManager = LauncherThemeManager()
    @State private var engine: LauncherEngine
    @State private var accountStore: AccountStore
    @State private var dshVersions: DSHVersionStore
    @State private var dshProcess: DSHProcessController
    @State private var dshPlugins: DSHPluginStore
    @State private var dshPacks: DSHPackService

    init() {
        let store = AccountStore()
        _accountStore = State(initialValue: store)
        _engine = State(initialValue: LauncherEngine(accountStore: store))
        let versions = DSHVersionStore()
        let plugins = DSHPluginStore()
        _dshVersions = State(initialValue: versions)
        _dshProcess = State(initialValue: DSHProcessController())
        _dshPlugins = State(initialValue: plugins)
        _dshPacks = State(initialValue: DSHPackService(versions: versions, plugins: plugins))
    }

    var body: some Scene {
        WindowGroup("LauncherALL") {
            LauncherAppShell()
                .environment(engine)
                .environment(accountStore)
                .environment(dshVersions)
                .environment(dshProcess)
                .environment(dshPlugins)
                .environment(dshPacks)
                .launcherThemeEnvironment(themeManager)
                .frame(minWidth: 1080, minHeight: 720)
                .background { LauncherWindowConfigurator() }
                .task {
                    await engine.refreshEnvironment()
                    await accountStore.refreshSelectedIfNeeded()
                    dshVersions.refreshInstalled()
                    dshPlugins.loadCachedCatalogIfNeeded()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1380, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// MARK: - 入口：GUI / 截图导出 / 命令行工具

@MainActor
func runMain(arguments: [String]) async -> Int32 {
    if let index = arguments.firstIndex(of: "--export-snapshots") {
        let output = index + 1 < arguments.count ? arguments[index + 1] : "Snapshots"
        return SnapshotExporter.run(outputDir: output)
    }
    if let index = arguments.firstIndex(of: "--export-app-snapshots") {
        let output = index + 1 < arguments.count ? arguments[index + 1] : "Snapshots/App"
        return await AppSnapshotExporter.run(outputDir: output)
    }
    if let index = arguments.firstIndex(of: "--export-xml-snapshots") {
        let output = index + 1 < arguments.count ? arguments[index + 1] : "Snapshots/XML"
        return XMLTool.exportSnapshots(directory: output)
    }
    if let index = arguments.firstIndex(of: "--dsh-install") {
        return await LauncherCLI.dshInstall(arguments: arguments, startIndex: index + 1)
    }
    if let index = arguments.firstIndex(of: "--dsh-pack-export") {
        return await LauncherCLI.dshPackExport(arguments: arguments, startIndex: index + 1)
    }
    if let index = arguments.firstIndex(of: "--dsh-pack-import") {
        return await LauncherCLI.dshPackImport(arguments: arguments, startIndex: index + 1)
    }
    if let index = arguments.firstIndex(of: "--dsh-remove") {
        return LauncherCLI.dshRemove(arguments: arguments, startIndex: index + 1)
    }
    if let index = arguments.firstIndex(of: "--dsh-pack-inspect") {
        return LauncherCLI.dshPackInspect(arguments: arguments, startIndex: index + 1)
    }
    if arguments.contains("--dsh-check") {
        return await LauncherCLI.dshCheck()
    }
    if arguments.contains("--auth-check") {
        return await LauncherCLI.authCheck()
    }
    if arguments.contains("--detect-java") {
        return LauncherCLI.detectJava()
    }
    if let index = arguments.firstIndex(of: "--list-installed") {
        return LauncherCLI.listInstalled(arguments: arguments, startIndex: index + 1)
    }
    if let index = arguments.firstIndex(of: "--launch-dry-run") {
        return await LauncherCLI.dryRun(arguments: arguments, startIndex: index + 1)
    }
    if let index = arguments.firstIndex(of: "--install") {
        return await LauncherCLI.install(arguments: arguments, startIndex: index + 1)
    }
    if let index = arguments.firstIndex(of: "--launch") {
        return await LauncherCLI.launch(arguments: arguments, startIndex: index + 1)
    }
    if arguments.contains("--list-xml-samples") {
        return XMLTool.listSamples()
    }
    if let index = arguments.firstIndex(of: "--validate-xml") {
        guard index + 1 < arguments.count else {
            print("用法：--validate-xml <file>")
            return 2
        }
        return XMLTool.validate(path: arguments[index + 1])
    }
    if let index = arguments.firstIndex(of: "--render-xml") {
        return XMLTool.render(arguments: arguments, startIndex: index + 1)
    }
    MCLauncherApp.main()
    return 0
}

let exitCode = await runMain(arguments: CommandLine.arguments)
exit(exitCode)
