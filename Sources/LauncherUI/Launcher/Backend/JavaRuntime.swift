import Foundation

/// 本机检测到的一个 Java 运行时。
public struct JavaRuntime: Identifiable, Equatable, Sendable {
    public let id: String
    public let executable: URL
    public let version: String
    public let majorVersion: Int
    public let vendor: String

    public var displayName: String {
        "Java \(majorVersion) · \(vendor)"
    }
}

/// 扫描并解析本机 Java 运行时（真实执行 `java -version`）。
public enum JavaLocator {
    /// 常见 JDK 安装位置。
    public static func candidateExecutables() -> [URL] {
        var paths: [String] = []

        let home = NSHomeDirectory()
        let fileManager = FileManager.default

        let roots = [
            "/Library/Java/JavaVirtualMachines",
            "/System/Library/Java/JavaVirtualMachines",
            "\(home)/Library/Java/JavaVirtualMachines",
            "/opt/homebrew/opt",
            "/opt/homebrew/Cellar",
            "/usr/local/opt",
            "/Users/Shared/Java"
        ]

        for root in roots {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries.sorted() {
                let base = "\(root)/\(entry)"
                for relative in ["Contents/Home/bin/java", "bin/java", "libexec/openjdk.jdk/Contents/Home/bin/java"] {
                    let candidate = "\(base)/\(relative)"
                    if fileManager.isExecutableFile(atPath: candidate) {
                        paths.append(candidate)
                    }
                }
            }
        }

        if let javaHome = ProcessInfo.processInfo.environment["JAVA_HOME"], !javaHome.isEmpty {
            paths.append("\(javaHome)/bin/java")
        }
        paths.append("/usr/bin/java")
        if let javaHome = try? runCommand("/usr/libexec/java_home", arguments: []),
           let path = javaHome.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first {
            paths.append("\(path)/bin/java")
        }

        var seen = Set<String>()
        return paths
            .map { URL(fileURLWithPath: $0) }
            .filter { fileManager.isExecutableFile(atPath: $0.path) }
            .filter { url in
                let resolved = url.resolvingSymlinksInPath().path
                guard !seen.contains(resolved) else { return false }
                seen.insert(resolved)
                return true
            }
    }

    /// 扫描全部可用运行时（去重、按主版本倒序）。
    public static func detectAll() -> [JavaRuntime] {
        var runtimes: [JavaRuntime] = []
        var seenPaths = Set<String>()
        for executable in candidateExecutables() {
            guard let output = try? runCommand(executable.path, arguments: ["-version"]) else { continue }
            guard let runtime = parseVersionOutput(output, executable: executable) else { continue }
            let key = runtime.executable.resolvingSymlinksInPath().path
            guard !seenPaths.contains(key) else { continue }
            seenPaths.insert(key)
            runtimes.append(runtime)
        }
        // /usr/bin/java 是系统壳，若已有同主版本的 JDK 条目则丢弃它
        let filtered = runtimes.filter { runtime in
            guard runtime.executable.path == "/usr/bin/java" else { return true }
            return !runtimes.contains {
                $0.executable.path != "/usr/bin/java" && $0.majorVersion == runtime.majorVersion
            }
        }
        return filtered.sorted { $0.majorVersion > $1.majorVersion }
    }

    /// 解析 `java -version` 输出；单独抽出来便于测试。
    public static func parseVersionOutput(_ output: String, executable: URL) -> JavaRuntime? {
        let lines = output.split(separator: "\n").map(String.init)
        guard let versionLine = lines.first(where: { $0.contains("version") }) ?? lines.first else { return nil }
        guard let quoted = versionLine.split(separator: "\"").dropFirst().first else { return nil }
        let version = String(quoted)
        var parts = version.split(separator: ".").map(String.init)
        if parts.first == "1" && parts.count > 1 {
            parts.removeFirst()
        }
        guard let major = Int(parts.first ?? "") else { return nil }

        let haystack = output.lowercased()
        let vendor: String
        if haystack.contains("temurin") { vendor = "Temurin" }
        else if haystack.contains("zulu") { vendor = "Zulu" }
        else if haystack.contains("microsoft") { vendor = "Microsoft" }
        else if haystack.contains("corretto") { vendor = "Corretto" }
        else if haystack.contains("graalvm") { vendor = "GraalVM" }
        else if haystack.contains("openjdk") { vendor = "OpenJDK" }
        else { vendor = "Java" }

        return JavaRuntime(
            id: executable.path,
            executable: executable,
            version: version,
            majorVersion: major,
            vendor: vendor
        )
    }

    /// 按主版本要求挑选最合适的运行时：优先精确匹配，其次满足要求的最低版本。
    public static func bestRuntime(for majorAtLeast: Int, in runtimes: [JavaRuntime]) -> JavaRuntime? {
        if let exact = runtimes.first(where: { $0.majorVersion == majorAtLeast }) {
            return exact
        }
        let candidates = runtimes.filter { $0.majorVersion > majorAtLeast }
        return candidates.min { $0.majorVersion < $1.majorVersion }
    }

    /// 同步执行命令并返回 stdout+stderr。
    public static func runCommand(_ path: String, arguments: [String], timeout: TimeInterval = 6) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            throw NSError(domain: "JavaLocator", code: 1, userInfo: [NSLocalizedDescriptionKey: "命令超时：\(path) \(arguments.joined(separator: " "))"])
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
