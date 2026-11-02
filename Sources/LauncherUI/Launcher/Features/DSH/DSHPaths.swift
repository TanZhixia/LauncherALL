import Foundation

// MARK: - DSH 目录布局

/// LauncherALL 管理 DSH 时使用的目录：
/// ```
/// ~/Library/Application Support/BlockLauncher/DSH/
///   versions/<version>/         # 每个版本独立的 node_modules
///   logs/<version>.log          # Web UI 进程日志
///   cache/                      # 插件市场 / 版本列表缓存
///   bin/                        # 生成的 pnpm shim 等
/// ```
/// 用户数据（`DSH_HOME`：profiles / 插件 / 会话）默认放在 `DSH/home`，所有版本共享；
/// 首次启动会把 `~/.dsh` 的登录凭据（`.credentials.yaml`）软链接进来，
/// 因此不会要求重新输入 API Key / 重新登录。
public struct DSHPaths: Sendable {
    public static let `default` = DSHPaths()

    public let root: URL
    /// 所有版本共享的 DSH_HOME（固定在 launcher 数据目录下，避免继承 DSH 会话的 DSH_HOME）。
    public let homeRoot: URL

    public init(root: URL? = nil, homeRoot: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.root = base
                .appendingPathComponent("BlockLauncher", isDirectory: true)
                .appendingPathComponent("DSH", isDirectory: true)
        }
        self.homeRoot = homeRoot ?? self.root.appendingPathComponent("home", isDirectory: true)
    }

    /// 用户已有的 DSH 目录（用于复用登录凭据；显式 DSH_HOME 时就是它自己）。
    public var userDSHHome: URL {
        if let env = ProcessInfo.processInfo.environment["DSH_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".dsh", isDirectory: true)
    }

    /// 首次启动时把系统 DSH 的登录凭据软链进 launcher 的 DSH_HOME：
    /// 复用 `~/.dsh/.credentials.yaml`（DEEPSEEK_API_KEY 等 refs），避免 Web UI 要求重新输入密钥。
    public func seedSharedHomeIfNeeded() {
        let fileManager = FileManager.default
        let userHome = userDSHHome
        guard homeRoot.resolvingSymlinksInPath() != userHome.resolvingSymlinksInPath() else { return }
        try? fileManager.createDirectory(at: homeRoot, withIntermediateDirectories: true)
        let names = [".credentials.yaml", ".anonymous-user-id", "settings.yaml"]
        for name in names {
            let source = userHome.appendingPathComponent(name)
            let destination = homeRoot.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
        }
    }

    public var versionsDirectory: URL { root.appendingPathComponent("versions", isDirectory: true) }
    public var homesDirectory: URL { root.appendingPathComponent("homes", isDirectory: true) }
    public var logsDirectory: URL { root.appendingPathComponent("logs", isDirectory: true) }
    public var cacheDirectory: URL { root.appendingPathComponent("cache", isDirectory: true) }
    public var binDirectory: URL { root.appendingPathComponent("bin", isDirectory: true) }

    /// 版本号是否安全（只允许 semver 字符，防止路径穿越）。
    public static func isSafeVersion(_ version: String) -> Bool {
        guard !version.isEmpty, version.count <= 64 else { return false }
        return version.range(of: #"^[0-9A-Za-z][0-9A-Za-z.+-]*$"#, options: .regularExpression) != nil
    }

    public func versionDirectory(_ version: String) -> URL {
        versionsDirectory.appendingPathComponent(version, isDirectory: true)
    }

    /// 所有版本共享的 DSH_HOME（与用户已有的 DSH / dsh CLI 一致）。
    public func homeDirectory(for version: String) -> URL {
        _ = version
        return homeRoot
    }

    /// 旧的「每个版本独立 DSH_HOME」目录（仅用于清理历史数据）。
    public func isolatedHomeDirectory(for version: String) -> URL {
        homesDirectory.appendingPathComponent(version, isDirectory: true)
    }

    public func logFile(for version: String) -> URL {
        logsDirectory.appendingPathComponent("\(version).log")
    }

    public func profileDirectory(for version: String) -> URL {
        homeDirectory(for: version).appendingPathComponent("profiles/web", isDirectory: true)
    }

    /// 版本入口脚本（npm 安装后的 `@deepseek-ai/dsh/lib/bin.js`）。
    public func cliScript(for version: String) -> URL {
        versionDirectory(version)
            .appendingPathComponent("node_modules/@deepseek-ai/dsh/lib/bin.js")
    }

    /// 确保基础目录存在。
    public func ensureDirectories() throws {
        let fileManager = FileManager.default
        for directory in [root, versionsDirectory, homesDirectory, logsDirectory, cacheDirectory, binDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// 统计目录占用（字节）。
    public func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}

// MARK: - 可执行文件定位

/// 包管理器种类。
public enum DSHPackageManagerKind: String, Sendable {
    case pnpm
    case npm
}

/// 可用的包管理器命令。
public struct DSHPackageManager: Sendable, Equatable {
    public let kind: DSHPackageManagerKind
    /// 直接执行的二进制（pnpm / npm）。
    public let executable: URL
    /// 需要先用 Node 执行的脚本（bundled pnpm.mjs）；为 nil 表示直接执行。
    public let nodeScript: URL?
    public let node: URL

    public init(kind: DSHPackageManagerKind, executable: URL, nodeScript: URL?, node: URL) {
        self.kind = kind
        self.executable = executable
        self.nodeScript = nodeScript
        self.node = node
    }

    public var displayName: String { kind.rawValue }
}

/// 在 GUI（launchd）环境里定位 Node / pnpm / npm：
/// 优先使用 DeepSeek Harness 桌面端自带的运行时，其次登录 shell 里的 nvm / Homebrew。
public enum DSHExecutables: Sendable {
    /// DSH 桌面端 App 路径（可用环境变量覆盖）。
    public static func desktopAppURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["DSH_DESKTOP_APP"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let candidates = [
            "/Applications/DeepSeek Harness.app",
            NSHomeDirectory() + "/Applications/DeepSeek Harness.app"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    /// DeepSeek Harness 自带的 Node 可执行文件。
    public static func bundledNode() -> URL? {
        if let override = ProcessInfo.processInfo.environment["DSH_DESKTOP_NODE_EXECUTABLE"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        guard let app = desktopAppURL() else { return nil }
        let url = app.appendingPathComponent(
            "Contents/Resources/runtime/primary-runtime/dependencies/node/bin/node"
        )
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// DeepSeek Harness 自带的 pnpm（需要 Node 执行）。
    public static func bundledPnpmScript() -> URL? {
        guard let app = desktopAppURL() else { return nil }
        let url = app.appendingPathComponent(
            "Contents/Resources/runtime/primary-runtime/dependencies/pnpm/bin/pnpm.mjs"
        )
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 登录 shell 的 PATH（GUI 进程默认 PATH 很窄）。
    public static func loginShellPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "printenv PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// 定位 Node：
    /// 1. 登录 shell 的 `command -v node`（标准 Node 运行时）
    /// 2. 常见路径 / nvm 目录
    /// 3. DSH 桌面端自带运行时（它的内部构建不保证支持 `node-addon-require-builtin`，仅作兜底）
    public static func node() -> URL? {
        if let fromShell = loginShellLookup("node") { return fromShell }
        var candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node"
        ]
        let nvmRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(
            at: nvmRoot,
            includingPropertiesForKeys: nil
        ) {
            for version in versions.sorted(by: { DSHVersionComparator.isNewer($0.lastPathComponent, than: $1.lastPathComponent) }) {
                candidates.append(version.appendingPathComponent("bin/node").path)
            }
        }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return bundledNode()
    }

    /// npm 的 JS 入口（`<node 前缀>/lib/node_modules/npm/bin/npm-cli.js`）。
    /// 用 `node npm-cli.js` 执行，避免 GUI 进程 PATH 里没有 node 时 shebang 失败。
    public static func npmCLI(node: URL?) -> URL? {
        guard let node else { return nil }
        let prefix = node.deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [
            prefix.appendingPathComponent("lib/node_modules/npm/bin/npm-cli.js"),
            prefix.appendingPathComponent("node_modules/npm/bin/npm-cli.js")
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path.path) {
            return path
        }
        return nil
    }

    /// 定位 npm。
    public static func npm() -> URL? {
        if let node = node() {
            let derived = node.deletingLastPathComponent().appendingPathComponent("npm")
            if FileManager.default.isExecutableFile(atPath: derived.path) { return derived }
        }
        if let fromShell = loginShellLookup("npm") { return fromShell }
        var candidates = [
            "/opt/homebrew/bin/npm",
            "/usr/local/bin/npm",
            "/usr/bin/npm"
        ]
        let fhs = "/usr/local/lib/node_modules/npm/bin/npm-cli.js"
        if FileManager.default.fileExists(atPath: fhs) { candidates.append(fhs) }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// 定位系统 pnpm（直接可执行）。
    public static func systemPnpm() -> URL? {
        if let fromShell = loginShellLookup("pnpm") { return fromShell }
        let candidates = [
            "/opt/homebrew/bin/pnpm",
            "/usr/local/bin/pnpm",
            NSHomeDirectory() + "/Library/pnpm/pnpm",
            NSHomeDirectory() + "/.local/share/pnpm/pnpm",
            NSHomeDirectory() + "/.local/bin/pnpm"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// 选择可用的包管理器：优先系统 pnpm，其次“自带 pnpm + 生成的 shim”，最后 npm。
    public static func packageManager(paths: DSHPaths = .default) -> DSHPackageManager? {
        guard let node = node() else { return nil }
        if let pnpm = systemPnpm() {
            return DSHPackageManager(kind: .pnpm, executable: pnpm, nodeScript: nil, node: node)
        }
        if let script = bundledPnpmScript(), let shim = try? makePnpmShim(paths: paths, node: node, script: script) {
            return DSHPackageManager(kind: .pnpm, executable: shim, nodeScript: script, node: node)
        }
        if let npm = npm() {
            return DSHPackageManager(kind: .npm, executable: npm, nodeScript: nil, node: node)
        }
        return nil
    }

    /// 生成一个 pnpm shim（`#!/bin/sh exec <node> <pnpm.mjs> "$@"`），让 dsh 转发给 pnpm 的插件命令可用。
    public static func makePnpmShim(paths: DSHPaths, node: URL, script: URL) throws -> URL {
        try paths.ensureDirectories()
        let shim = paths.binDirectory.appendingPathComponent("pnpm")
        let content = """
        #!/bin/sh
        exec "\(node.path)" "\(script.path)" "$@"
        """
        try content.write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        return shim
    }

    /// 登录 shell 里 `command -v <name>`。
    public static func loginShellLookup(_ name: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(name)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }

    /// 给子进程用的 PATH：注入 node / pnpm / npm 所在目录。
    public static func augmentedEnvironment(
        node: URL? = nil,
        extraDirectories: [URL] = [],
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        var directories: [String] = extraDirectories.map(\.path)
        if let node, !node.path.isEmpty {
            directories.append(node.deletingLastPathComponent().path)
        }
        if let npm = npm() {
            directories.append(npm.deletingLastPathComponent().path)
        }
        if let pnpm = systemPnpm() {
            directories.append(pnpm.deletingLastPathComponent().path)
        }
        if let shellPath = loginShellPath() {
            directories.append(contentsOf: shellPath.split(separator: ":").map(String.init))
        }
        let existing = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        var seen = Set<String>()
        let merged = (directories + existing + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        environment["PATH"] = merged.joined(separator: ":")
        return environment
    }
}
