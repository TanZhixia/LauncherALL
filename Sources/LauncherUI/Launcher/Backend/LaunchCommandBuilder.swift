import Foundation
import CryptoKit

/// 启动参数选项。
public struct LaunchOptions: Sendable {
    public let versionID: String
    public let playerName: String
    public let java: JavaRuntime
    public let memoryMB: Int
    public let renderThreads: Int
    public let extraJVMArguments: [String]
    public let gameDirectory: URL
    /// 启动身份：离线 / 正版（为 nil 时按 `playerName` 走离线逻辑，兼容 CLI 与旧调用）。
    public let account: LaunchAccount?

    public init(
        versionID: String,
        playerName: String,
        java: JavaRuntime,
        memoryMB: Int,
        renderThreads: Int,
        extraJVMArguments: [String],
        gameDirectory: URL,
        account: LaunchAccount? = nil
    ) {
        self.versionID = versionID
        self.playerName = playerName
        self.java = java
        self.memoryMB = memoryMB
        self.renderThreads = renderThreads
        self.extraJVMArguments = extraJVMArguments
        self.gameDirectory = gameDirectory
        self.account = account
    }
}

/// 组装好的启动命令。
public struct LaunchCommand: Sendable {
    public let executable: URL
    public let arguments: [String]

    public init(executable: URL, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    /// 便于日志 / 诊断展示的完整命令行。
    public var commandLine: String {
        ([executable.path] + arguments)
            .map { $0.contains(" ") ? "'\($0)'" : $0 }
            .joined(separator: " ")
    }
}

public enum LaunchBuildError: LocalizedError {
    case missingClientJar(String)
    case missingVersionJSON(String)
    case emptyClasspath

    public var errorDescription: String? {
        switch self {
        case .missingClientJar(let id): return "缺少客户端 jar：\(id)"
        case .missingVersionJSON(let id): return "缺少版本 JSON：\(id)"
        case .emptyClasspath: return "classpath 为空"
        }
    }
}

/// 真实的启动命令构建：规则过滤、classpath、变量替换、离线 UUID。
public enum LaunchCommandBuilder {
    public static let launcherName = "BlockLauncher"
    public static let launcherVersion = "0.2.0"

    public static func build(
        detail: ResolvedVersion,
        installation: MinecraftInstallation,
        options: LaunchOptions
    ) throws -> LaunchCommand {
        let fileManager = FileManager.default
        let jarURL = installation.versionJarURL(detail.id)
        guard fileManager.fileExists(atPath: jarURL.path) else {
            throw LaunchBuildError.missingClientJar(detail.id)
        }

        // classpath：客户端 jar + 通过规则的依赖库
        var classpathEntries = [jarURL.path]
        for library in detail.libraries where RuleEvaluator.isAllowed(library.rules) {
            guard let path = library.mavenPath else { continue }
            let url = installation.librariesDirectory.appendingPathComponent(path)
            if fileManager.fileExists(atPath: url.path) {
                classpathEntries.append(url.path)
            }
        }
        guard !classpathEntries.isEmpty else { throw LaunchBuildError.emptyClasspath }
        let classpath = classpathEntries.joined(separator: ":")

        let nativesDirectory = installation.nativesDirectory(detail.id)
        try? fileManager.createDirectory(at: nativesDirectory, withIntermediateDirectories: true)

        let assetsIndexName = detail.assetIndex?.id ?? detail.assets ?? "legacy"
        let loggingPath = loggingConfigurationPath(detail: detail, installation: installation)

        // 账户身份：正版用档案 UUID / Minecraft 令牌，离线用离线 UUID / accessToken=0
        let account = options.account ?? .offline(name: options.playerName)
        var values: [String: String] = [
            "auth_player_name": account.name,
            "version_name": detail.id,
            "game_directory": options.gameDirectory.path,
            "assets_root": installation.assetsDirectory.path,
            "assets_index_name": assetsIndexName,
            "auth_uuid": account.commandUUID,
            "auth_access_token": account.accessToken,
            "auth_session": account.accessToken,
            "clientid": "",
            // 1.20.5+ 的版本 JSON 使用 ${auth_xuid}，旧版本用 ${xuid}：两个都提供
            "auth_xuid": account.xuid ?? "",
            "xuid": account.xuid ?? "",
            "user_type": account.userType,
            "version_type": detail.type,
            "user_properties": account.userProperties,
            "natives_directory": nativesDirectory.path,
            "launcher_name": launcherName,
            "launcher_version": launcherVersion,
            "classpath": classpath,
            "classpath_separator": ":",
            "library_directory": installation.librariesDirectory.path
        ]
        if let loggingPath {
            values["path"] = loggingPath
        }

        // JVM 参数
        var jvmArguments: [String] = []
        let hasMemoryArgument = (detail.arguments?.jvm ?? []).contains {
            RuleEvaluator.isAllowed($0.rules) && $0.values.contains { $0.hasPrefix("-Xmx") }
        }
        if !hasMemoryArgument {
            jvmArguments.append("-Xmx\(max(512, options.memoryMB))M")
            jvmArguments.append("-Xms\(min(max(512, options.memoryMB / 2), 2048))M")
        }
        if options.renderThreads > 0 {
            jvmArguments.append("-XX:ActiveProcessorCount=\(options.renderThreads)")
        }
        if let arguments = detail.arguments?.jvm {
            jvmArguments.append(contentsOf: expand(arguments, values: values))
        } else {
            jvmArguments.append("-Djava.library.path=\(nativesDirectory.path)")
        }
        if !jvmArguments.contains(where: { $0.hasPrefix("-Djava.library.path=") }) {
            jvmArguments.append("-Djava.library.path=\(nativesDirectory.path)")
        }
        let hasClassPathArgument = jvmArguments.contains("-cp") || jvmArguments.contains("-classpath")
        if !hasClassPathArgument {
            jvmArguments.append(contentsOf: ["-cp", classpath])
        }
        jvmArguments.append(contentsOf: options.extraJVMArguments)

        // 游戏参数
        let gameArguments: [String]
        if let arguments = detail.arguments?.game {
            gameArguments = expand(arguments, values: values)
        } else if let legacy = detail.minecraftArguments {
            gameArguments = legacy
                .split(separator: " ")
                .map { substitute(String($0), values: values) }
                .filter { !$0.isEmpty }
        } else {
            gameArguments = []
        }

        let arguments = sanitize(jvmArguments + [detail.mainClass] + gameArguments)
        return LaunchCommand(executable: options.java.executable, arguments: arguments)
    }

    /// 版本自带日志配置路径（安装器已下载到缓存目录）。
    public static func loggingConfigurationPath(detail: ResolvedVersion, installation: MinecraftInstallation) -> String? {
        guard let file = detail.logging?.client?.file else { return nil }
        let url = installation.cacheDirectory
            .appendingPathComponent("logging", isDirectory: true)
            .appendingPathComponent(file.id)
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    /// 过滤规则并替换变量（空值留给 `sanitize` 连同旗标一起清理）。
    static func expand(_ arguments: [VersionDetail.Argument], values: [String: String]) -> [String] {
        arguments
            .filter { RuleEvaluator.isAllowed($0.rules) }
            .flatMap { $0.values }
            .map { substitute($0, values: values) }
    }

    /// 清理未能替换的占位参数与空值参数：
    /// - `--flag ${placeholder}`：占位符未替换 → 连同旗标一起丢掉；
    /// - `--flag ""`：变量被替换为空串 → 连同旗标一起丢掉。
    /// 避免把字面量或孤立的旗标传给游戏（例如离线模式下的 `--clientId`）。
    static func sanitize(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.contains("${") || argument.isEmpty {
                // 形如 --flag ${placeholder} / --flag ""：把前面的旗标一起丢掉
                if index > 0, arguments[index - 1].hasPrefix("-"), !result.isEmpty {
                    result.removeLast()
                }
                index += 1
                continue
            }
            result.append(argument)
            index += 1
        }
        return result
    }

    /// 把命令里的敏感值（正版 accessToken）替换成掩码，用于日志 / 界面展示。
    public static func redacted(_ commandLine: String, hiding secret: String) -> String {
        guard !secret.isEmpty, secret != "0" else { return commandLine }
        return commandLine.replacingOccurrences(of: secret, with: "***")
    }

    /// `${var}` 变量替换；未知变量保留原样，便于排查。
    public static func substitute(_ template: String, values: [String: String]) -> String {
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
        }
        return result
    }

    /// 离线模式 UUID：`md5("OfflinePlayer:<name>")` 并设置版本 3 / 变体位。
    public static func offlineUUID(for playerName: String) -> String {
        let digest = Insecure.MD5.hash(data: Data("OfflinePlayer:\(playerName)".utf8)).map { $0 }
        var bytes = digest
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let parts = [
            hex.prefix(8),
            hex.dropFirst(8).prefix(4),
            hex.dropFirst(12).prefix(4),
            hex.dropFirst(16).prefix(4),
            hex.dropFirst(20).prefix(12)
        ]
        return parts.joined(separator: "-")
    }
}
