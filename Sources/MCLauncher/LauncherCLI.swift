import Foundation
import LauncherUI

/// 启动器后端命令行工具：环境检测、版本列表、安装、启动命令预演。
@MainActor
enum LauncherCLI {
    /// `--auth-check`：向微软申请一次设备码，验证正版登录端点与客户端 ID 可用（不轮询、不落盘）。
    static func authCheck() async -> Int32 {
        let service = MicrosoftAuthService()
        do {
            let code = try await service.requestDeviceCode()
            print("✓ 设备码申请成功")
            print("  验证码：\(code.userCode)")
            print("  浏览地址：\(code.verificationURL.absoluteString)")
            print("  有效期：\(code.expiresIn) 秒 · 轮询间隔：\(code.pollInterval) 秒")
            print("  （本次只验证申请流程，未轮询授权，也不会写入任何账户）")
            return 0
        } catch {
            print("✗ 设备码申请失败：\(error.localizedDescription)")
            return 1
        }
    }

    /// `--dsh-check`：检查 DSH 环境、已安装版本，并真实启动一次 Web UI（不打开浏览器）后停止。
    static func dshCheck() async -> Int32 {
        let settings = LauncherSettings(defaults: UserDefaults(suiteName: "launcher.cli.dsh") ?? .standard)
        let paths = DSHPaths.default
        let versions = DSHVersionStore(settings: settings, paths: paths)
        versions.refreshInstalled()

        print("DSH 环境：\(versions.environmentText)")
        print("DSH 目录：\(paths.root.path)")
        await versions.refreshCatalog()
        if let catalog = versions.catalog {
            print("远程版本：\(catalog.versions.count) 个（latest \(catalog.latest()?.version ?? "?")）")
        } else {
            print("远程版本：拉取失败（\(versions.catalogState.errorText ?? "未知错误")）")
        }
        if versions.installed.isEmpty {
            print("✗ 还没有安装任何 DSH 版本（可在启动器 DSH → 下载 里安装）")
            return 1
        }
        for version in versions.installed {
            let size = ByteCountFormatter.string(fromByteCount: version.sizeBytes ?? 0, countStyle: .file)
            print("  - \(version.version)  \(size)  \(version.path)")
        }
        guard let selected = versions.selectedInstalledVersion ?? versions.installed.first else {
            return 1
        }

        let previousAutoOpen = settings.dshAutoOpenBrowser
        settings.dshAutoOpenBrowser = false
        defer { settings.dshAutoOpenBrowser = previousAutoOpen }
        let controller = DSHProcessController(settings: settings, paths: paths)
        print("… 启动 DSH \(selected.version) Web UI")
        let started = await controller.start(version: selected)
        defer { controller.stopSynchronously() }
        guard started, let url = controller.state.url else {
            print("✗ 启动失败：\(controller.state)")
            let tail = controller.logLines.suffix(8).joined(separator: "\n")
            if !tail.isEmpty { print(tail) }
            return 1
        }
        print("✓ DSH Web UI 已启动：\(url)")
        print("  端口：\(controller.activePort ?? 0) · 日志：\(paths.logFile(for: selected.version).path)")
        print("  已停止（本次只验证启动链路，不保留进程）")
        return 0
    }

    /// `--detect-java`：列出本机 Java 运行时。
    static func detectJava() -> Int32 {
        let runtimes = JavaLocator.detectAll()
        if runtimes.isEmpty {
            print("✗ 未检测到 Java 运行时")
            return 1
        }
        print("检测到 \(runtimes.count) 个 Java 运行时：")
        for runtime in runtimes {
            print("  - Java \(runtime.version)（\(runtime.vendor)）\(runtime.executable.path)")
        }
        return 0
    }

    /// `--list-installed [--dir path]`：列出本地已安装版本。
    static func listInstalled(arguments: [String], startIndex: Int) -> Int32 {
        let directory = stringOption("--dir", arguments: arguments, startIndex: startIndex)
            ?? LauncherSettings.defaultGameDirectory
        let installation = MinecraftInstallation(root: URL(fileURLWithPath: (directory as NSString).expandingTildeInPath, isDirectory: true))
        print("游戏目录：\(installation.root.path)")
        let versions = installation.installedVersions()
        if versions.isEmpty {
            print("没有已安装版本（versions/ 目录为空）")
            return 0
        }
        print("已安装 \(versions.count) 个版本：")
        for version in versions {
            let jar = version.jarURL == nil ? "缺少 jar" : "jar 就绪"
            print("  - \(version.id)  [\(version.versionType)]  \(jar)")
        }
        return 0
    }

    /// `--launch-dry-run <version>`：解析 Java、合并继承版本、打印最终启动命令（不启动）。
    static func dryRun(arguments: [String], startIndex: Int) async -> Int32 {
        guard startIndex < arguments.count else {
            print("用法：--launch-dry-run <versionID> [--dir path] [--name Steve] [--memory 4096] [--java path]")
            return 2
        }
        let versionID = arguments[startIndex]
        let directory = stringOption("--dir", arguments: arguments, startIndex: startIndex)
            ?? LauncherSettings.defaultGameDirectory
        let playerName = stringOption("--name", arguments: arguments, startIndex: startIndex) ?? "Steve"
        let memory = Int(stringOption("--memory", arguments: arguments, startIndex: startIndex) ?? "") ?? 4096
        let javaPath = stringOption("--java", arguments: arguments, startIndex: startIndex)

        let installation = MinecraftInstallation(root: URL(fileURLWithPath: (directory as NSString).expandingTildeInPath, isDirectory: true))
        let detail: ResolvedVersion
        do {
            detail = try await VersionResolver.resolveAsync(versionID: versionID, installation: installation)
        } catch {
            print("✗ 版本解析失败：\(error)")
            return 1
        }

        let runtimes = JavaLocator.detectAll()
        let java: JavaRuntime?
        if let javaPath {
            let url = URL(fileURLWithPath: javaPath)
            if let output = try? JavaLocator.runCommand(url.path, arguments: ["-version"]),
               let runtime = JavaLocator.parseVersionOutput(output, executable: url) {
                java = runtime
            } else {
                java = nil
            }
        } else {
            java = JavaLocator.bestRuntime(for: detail.requiredJavaMajor, in: runtimes)
        }
        guard let java else {
            print("✗ 未找到可用的 Java（版本要求 \(detail.requiredJavaMajor)）")
            return 1
        }

        let settings = LauncherSettings(defaults: UserDefaults(suiteName: "launcher.cli") ?? .standard)
        let gameDirectory = settings.gameDirectory(for: versionID)
        let options = LaunchOptions(
            versionID: versionID,
            playerName: playerName,
            java: java,
            memoryMB: memory,
            renderThreads: 4,
            extraJVMArguments: [],
            gameDirectory: gameDirectory
        )
        do {
            let command = try LaunchCommandBuilder.build(detail: detail, installation: installation, options: options)
            let missing = detail.libraries.filter { RuleEvaluator.isAllowed($0.rules) }.filter { library in
                guard let path = library.downloads?.artifact?.path else { return false }
                return !FileManager.default.fileExists(
                    atPath: installation.librariesDirectory.appendingPathComponent(path).path
                )
            }
            print("✓ Java：Java \(java.version)（\(java.vendor)）")
            print("✓ 版本：\(detail.id) · \(detail.type) · 主类 \(detail.mainClass)")
            print("✓ 继承：\(detail.libraries.count) 个依赖 · 缺失 \(missing.count) 个")
            print("✓ 游戏目录：\(gameDirectory.path)")
            print("✓ 离线 UUID：\(LaunchCommandBuilder.offlineUUID(for: playerName))")
            print("✓ 命令长度：\(command.arguments.count) 个参数")
            if !missing.isEmpty {
                print("! 有 \(missing.count) 个依赖库未安装，真实启动前请先安装该版本")
            }
            print("")
            print(command.commandLine)
            return missing.isEmpty ? 0 : 3
        } catch {
            print("✗ 构建启动命令失败：\(error.localizedDescription)")
            return 1
        }
    }

    /// `--install <version>`：真实下载安装（客户端 + 依赖库 + 原生库 + 资源）。
    static func install(arguments: [String], startIndex: Int) async -> Int32 {
        guard startIndex < arguments.count else {
            print("用法：--install <versionID> [--dir path]")
            return 2
        }
        let versionID = arguments[startIndex]
        let directory = stringOption("--dir", arguments: arguments, startIndex: startIndex)
            ?? LauncherSettings.defaultGameDirectory
        let installation = MinecraftInstallation(root: URL(fileURLWithPath: (directory as NSString).expandingTildeInPath, isDirectory: true))
        print("安装 \(versionID) → \(installation.root.path)")
        print("（真实网络下载：客户端 / 依赖库 / 原生库 / 资源文件，可能需要数分钟）")

        let installer = VersionInstaller(installation: installation)
        var lastPhase = ""
        var lastPercent = -1
        do {
            let version = try await installer.install(versionID: versionID, includeAssets: true) { progress in
                let percent = Int(progress.fraction * 100)
                guard progress.phase != lastPhase || percent - lastPercent >= 10 else { return }
                lastPhase = progress.phase
                lastPercent = percent
                print("  \(progress.phase) … \(percent)%（\(progress.completed)/\(progress.total)）")
            }
            print("✓ 安装完成：\(version.id)")
            return 0
        } catch {
            print("✗ 安装失败：\(error.localizedDescription)")
            return 1
        }
    }

    /// `--launch <version>`：真实启动并流式输出日志（默认运行 20 秒后停止）。
    static func launch(arguments: [String], startIndex: Int) async -> Int32 {
        guard startIndex < arguments.count else {
            print("用法：--launch <versionID> [--dir path] [--name Steve] [--timeout 20]")
            return 2
        }
        let versionID = arguments[startIndex]
        let runSeconds = Int(stringOption("--timeout", arguments: arguments, startIndex: startIndex) ?? "") ?? 20
        let directory = stringOption("--dir", arguments: arguments, startIndex: startIndex)
        let playerName = stringOption("--name", arguments: arguments, startIndex: startIndex)

        let settings = LauncherSettings(defaults: UserDefaults(suiteName: "launcher.cli") ?? .standard)
        if let directory { settings.gameDirectory = directory }
        if let playerName { settings.playerName = playerName }

        let engine = LauncherEngine(settings: settings)
        await engine.refreshEnvironment()
        print("已安装版本：\(engine.installedVersions.map(\.id).joined(separator: ", "))")
        print("可用 Java：\(engine.javaRuntimes.map { "Java \($0.majorVersion)" }.joined(separator: ", "))")
        print("启动 \(versionID)…")

        await engine.launch(versionID: versionID)

        var waited = 0.0
        while engine.phase.isBusy, waited < 180 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            waited += 0.5
        }
        let phase = engine.phase
        let startupLogs = engine.logLines
        for line in startupLogs { print("  \(line)") }

        var exitCode: Int32 = 1
        if case .running = phase {
            print("✓ 进程已启动，观察 \(runSeconds) 秒日志…")
            exitCode = 0
            try? await Task.sleep(nanoseconds: UInt64(max(1, runSeconds)) * 1_000_000_000)
        } else if case .failed(let message) = phase {
            print("✗ 启动失败：\(message)")
        }
        let finalLogs = engine.logLines
        for line in finalLogs.dropFirst(startupLogs.count) { print("  \(line)") }
        engine.stop()
        print("已停止，退出码 \(exitCode)")
        return exitCode
    }

    static func stringOption(_ name: String, arguments: [String], startIndex: Int) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
