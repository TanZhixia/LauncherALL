import Foundation

// MARK: - 备份条目

/// 一个真实的实例备份文件（`<游戏目录>/backups/*.zip`）。
public struct MoreBackupItem: Identifiable, Equatable, Sendable {
    /// 备份 zip 的真实路径。
    public let url: URL
    /// 文件名（含 `.zip` 后缀）。
    public let name: String
    /// 真实字节大小。
    public let byteSize: Int64
    /// 创建时间（读不到时回退为修改时间）。
    public let createdAt: Date
    /// 从文件名解析出的实例名（旧备份可能解析失败）。
    public let instanceGuess: String?

    public var id: URL { url }

    public init(url: URL, name: String, byteSize: Int64, createdAt: Date, instanceGuess: String?) {
        self.url = url
        self.name = name
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.instanceGuess = instanceGuess
    }

    /// 人读大小，例如 "12.4 MB"。
    public var sizeText: String {
        MoreFormatting.byteCountText(byteSize)
    }

    /// 备份日期，例如 "2026-11-01 18:40"。
    public var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: createdAt)
    }
}

// MARK: - 备份内容

/// 一次备份会包含的实例条目。
public struct MoreBackupEntry: Identifiable, Equatable, Sendable {
    /// 相对实例目录的路径（文件或目录名）。
    public let relativePath: String
    /// 展示名。
    public let title: String
    /// 该条目当前是否真实存在。
    public let exists: Bool

    public var id: String { relativePath }

    public init(relativePath: String, title: String, exists: Bool) {
        self.relativePath = relativePath
        self.title = title
        self.exists = exists
    }
}

// MARK: - 错误

/// 备份 / 恢复过程中的真实错误。
public enum MoreBackupError: LocalizedError {
    case emptyInstance
    case dittoMissing
    case makeDirectoryFailed(String)
    case archiveFailed(String)
    case restoreFailed(String)
    case missingBackup(String)
    case outsideGameDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInstance:
            return "该实例没有可备份的内容（saves / mods / config / options.txt / servers.dat 都不存在）"
        case .dittoMissing:
            return "系统缺少 /usr/bin/ditto，无法打包备份"
        case .makeDirectoryFailed(let path):
            return "无法创建备份目录：\(path)"
        case .archiveFailed(let message):
            return "打包备份失败：\(message)"
        case .restoreFailed(let message):
            return "恢复备份失败：\(message)"
        case .missingBackup(let name):
            return "备份文件不存在：\(name)"
        case .outsideGameDirectory(let path):
            return "路径不在游戏目录内，已拒绝操作：\(path)"
        }
    }
}

// MARK: - 备份服务

/// 实例备份服务：真实调用 `/usr/bin/ditto` 打包与解压，所有路径操作都做存在性与归属校验。
public enum MoreBackupService {
    /// 备份根目录名（位于游戏目录下）。
    public static let backupsFolderName = "backups"

    /// 备份内容清单：世界存档、模组（含 .disabled）、配置、游戏设置、服务器列表。
    public static let entryTitles: [(path: String, title: String)] = [
        ("saves", "世界存档"),
        ("mods", "模组"),
        ("config", "配置"),
        ("options.txt", "游戏设置"),
        ("servers.dat", "服务器列表")
    ]

    // MARK: 路径

    /// 备份目录：`<游戏目录>/backups`。
    public static func backupsDirectory(gameDirectory: URL) -> URL {
        gameDirectory.appendingPathComponent(backupsFolderName, isDirectory: true)
    }

    /// 备份文件是否位于备份目录内（防止误删 / 误解压其它位置）。
    public static func isInsideBackups(_ url: URL, gameDirectory: URL) -> Bool {
        let base = backupsDirectory(gameDirectory: gameDirectory).standardizedFileURL.path
        let target = url.standardizedFileURL.path
        return target.hasPrefix(base + "/")
    }

    /// 某个实例目录里真实存在的备份条目。
    public static func entries(instanceDirectory: URL) -> [MoreBackupEntry] {
        let fileManager = FileManager.default
        return entryTitles.map { item in
            let url = instanceDirectory.appendingPathComponent(item.path)
            return MoreBackupEntry(
                relativePath: item.path,
                title: item.title,
                exists: fileManager.fileExists(atPath: url.path)
            )
        }
    }

    // MARK: 命名

    /// 生成备份文件名：`<实例名>-<yyyyMMdd-HHmmss>.zip`。
    public static func makeFileName(versionID: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeName = sanitizedInstanceName(versionID)
        return "\(safeName)-\(formatter.string(from: date)).zip"
    }

    /// 把实例名里的路径分隔符等替换成 `-`，保证可作文件名。
    public static func sanitizedInstanceName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|\u{0}")
        let cleaned = String(trimmed.unicodeScalars.map { banned.contains($0) ? "-" : Character($0) })
        return cleaned.isEmpty ? "instance" : cleaned
    }

    /// 从备份文件名反推实例名（找不到明确时间戳时返回 nil）。
    public static func instanceName(fromFileName fileName: String) -> String? {
        let core = fileName.hasSuffix(".zip") ? String(fileName.dropLast(4)) : fileName
        // 去掉结尾的 -yyyyMMdd-HHmmss
        let pattern = #"^(.*)-(\d{8})-(\d{6})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: core, range: NSRange(core.startIndex..<core.endIndex, in: core)),
              let range = Range(match.range(at: 1), in: core) else {
            return nil
        }
        let name = String(core[range])
        return name.isEmpty ? nil : name
    }

    // MARK: 列表

    /// 扫描真实备份列表（按创建时间倒序）。
    public static func list(gameDirectory: URL) -> [MoreBackupItem] {
        let fileManager = FileManager.default
        let directory = backupsDirectory(gameDirectory: gameDirectory)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .filter { $0.pathExtension.lowercased() == "zip" }
            .compactMap { item(at: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 读取单个备份文件的真实元信息。
    public static func item(at url: URL) -> MoreBackupItem? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isRegularFileKey
        ])
        guard values?.isRegularFile != false else { return nil }
        let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        let created = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
        return MoreBackupItem(
            url: url,
            name: url.lastPathComponent,
            byteSize: size,
            createdAt: created,
            instanceGuess: instanceName(fromFileName: url.lastPathComponent)
        )
    }

    /// 备份总占用字节数。
    public static func totalSize(gameDirectory: URL) -> Int64 {
        list(gameDirectory: gameDirectory).reduce(0) { $0 + $1.byteSize }
    }

    /// 人读总占用。
    public static func totalSizeText(gameDirectory: URL) -> String {
        MoreFormatting.byteCountText(totalSize(gameDirectory: gameDirectory))
    }

    /// 确保备份目录存在（返回目录 URL）。
    @discardableResult
    public static func ensureBackupsDirectory(gameDirectory: URL) throws -> URL {
        let directory = backupsDirectory(gameDirectory: gameDirectory)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return directory
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw MoreBackupError.makeDirectoryFailed(directory.path)
        }
        return directory
    }

    // MARK: 创建

    /// 把实例里真实存在的条目打包成 zip，返回新的备份条目。
    @discardableResult
    public static func createBackup(
        versionID: String,
        instanceDirectory: URL,
        gameDirectory: URL,
        date: Date = Date()
    ) throws -> MoreBackupItem {
        let fileManager = FileManager.default
        try validate(instanceDirectory: instanceDirectory, gameDirectory: gameDirectory)

        let existing = entries(instanceDirectory: instanceDirectory).filter(\.exists)
        guard !existing.isEmpty else { throw MoreBackupError.emptyInstance }

        let backupDirectory = try ensureBackupsDirectory(gameDirectory: gameDirectory)
        removeStaleStagingDirectories(in: backupDirectory)
        let target = uniqueBackupURL(
            directory: backupDirectory,
            fileName: makeFileName(versionID: versionID, date: date)
        )

        // 用硬链接把条目“排练”进同卷暂存目录，避免多拷一份大文件。
        let staging = backupDirectory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        for entry in existing {
            let source = instanceDirectory.appendingPathComponent(entry.relativePath)
            let destination = staging.appendingPathComponent(entry.relativePath)
            try linkTree(from: source, to: destination)
        }

        do {
            try runDitto(arguments: ["-c", "-k", "--sequesterRsrc", staging.path, target.path], failure: MoreBackupError.archiveFailed)
        } catch {
            try? fileManager.removeItem(at: target)
            throw error
        }

        guard let item = item(at: target) else { throw MoreBackupError.archiveFailed("生成的 zip 无法读取") }
        return item
    }

    // MARK: 恢复

    /// 把备份解压回实例目录（同名文件会被覆盖；调用方必须先做二次确认）。
    public static func restore(
        _ item: MoreBackupItem,
        instanceDirectory: URL,
        gameDirectory: URL
    ) throws {
        let fileManager = FileManager.default
        try validate(instanceDirectory: instanceDirectory, gameDirectory: gameDirectory)
        guard isInsideBackups(item.url, gameDirectory: gameDirectory),
              fileManager.fileExists(atPath: item.url.path) else {
            throw MoreBackupError.missingBackup(item.name)
        }
        if !fileManager.fileExists(atPath: instanceDirectory.path) {
            try fileManager.createDirectory(at: instanceDirectory, withIntermediateDirectories: true)
        }
        try runDitto(arguments: ["-x", "-k", item.url.path, instanceDirectory.path], failure: MoreBackupError.restoreFailed)
    }

    // MARK: 删除

    /// 删除一个备份到废纸篓（不可恢复地清空废纸篓才会真正删除）。
    public static func delete(_ item: MoreBackupItem, gameDirectory: URL) throws {
        guard isInsideBackups(item.url, gameDirectory: gameDirectory) else {
            throw MoreBackupError.outsideGameDirectory(item.url.path)
        }
        try InstanceActions.trash(item.url)
    }

    // MARK: 内部

    /// 校验实例目录位于游戏目录内，避免对用户其它文件动手。
    private static func validate(instanceDirectory: URL, gameDirectory: URL) throws {
        let root = gameDirectory.standardizedFileURL.path
        let instance = instanceDirectory.standardizedFileURL.path
        guard instance == root || instance.hasPrefix(root + "/") else {
            throw MoreBackupError.outsideGameDirectory(instance)
        }
    }

    /// 清理异常退出（崩溃 / 强制结束）残留的暂存目录。
    /// 只删除 1 小时前的 `.staging-*`，避免误删其它进程正在进行的备份。
    private static func removeStaleStagingDirectories(in directory: URL) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: []
        ) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-3600)
        for entry in entries where entry.lastPathComponent.hasPrefix(".staging-") {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true else { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            if modified < cutoff {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    /// 同秒导出/备份时自动追加序号，避免覆盖已有文件。
    private static func uniqueBackupURL(directory: URL, fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    /// 递归建立硬链接（同一卷时几乎零拷贝）；链接失败则退回真实拷贝。
    private static func linkTree(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            try fileManager.copyItem(at: source, to: destination)
            return
        }
        if values.isDirectory == true {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            for child in children {
                try linkTree(from: child, to: destination.appendingPathComponent(child.lastPathComponent))
            }
            return
        }
        do {
            try fileManager.linkItem(at: source, to: destination)
        } catch {
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    /// 运行系统 ditto 并等待结束；非 0 退出时抛错（错误文案取 stderr）。
    private static func runDitto(arguments: [String], failure: (String) -> MoreBackupError) throws {
        let executable = URL(fileURLWithPath: "/usr/bin/ditto")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw MoreBackupError.dittoMissing
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            throw failure(error.localizedDescription)
        }
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "ditto 退出码 \(process.terminationStatus)"
            throw failure(message.isEmpty ? "ditto 退出码 \(process.terminationStatus)" : message)
        }
    }
}
