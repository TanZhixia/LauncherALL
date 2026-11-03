import Foundation
import AppKit
import SwiftUI

// MARK: - 设置分区

/// DSH 设置页的左侧分类。
public enum DSHSettingsSection: String, CaseIterable, Identifiable, Sendable {
    case launch
    case plugins
    case environment
    case about

    public var id: String { rawValue }

    /// 分类标题。
    public var title: String {
        switch self {
        case .launch: return "启动"
        case .plugins: return "下载与插件"
        case .environment: return "环境与目录"
        case .about: return "关于"
        }
    }

    /// 分类说明（右侧页头副标题）。
    public var subtitle: String {
        switch self {
        case .launch: return "Web UI 端口、自动打开浏览器与默认实例"
        case .plugins: return "npm 源、插件加载源与本地缓存"
        case .environment: return "Node / 包管理器检测、实例 DSH_HOME 与数据目录"
        case .about: return "版本信息与数据管理"
        }
    }

    /// 分类图标（仅 SF Symbols）。
    public var systemImage: String {
        switch self {
        case .launch: return "play.rectangle.fill"
        case .plugins: return "puzzlepiece.extension.fill"
        case .environment: return "externaldrive.fill"
        case .about: return "info.circle.fill"
        }
    }

    /// 解析路由 / 外部传入的分类字符串。
    public static func resolve(_ raw: String?) -> DSHSettingsSection? {
        guard let raw else { return nil }
        return DSHSettingsSection(rawValue: raw)
    }
}

// MARK: - 更多分区

/// DSH 更多页的左侧分区。
public enum DSHMoreSection: String, CaseIterable, Identifiable, Sendable {
    case logs
    case directories
    case process
    case about

    public var id: String { rawValue }

    /// 分区标题。
    public var title: String {
        switch self {
        case .logs: return "运行日志"
        case .directories: return "数据目录"
        case .process: return "进程"
        case .about: return "关于"
        }
    }

    /// 分区说明。
    public var subtitle: String {
        switch self {
        case .logs: return "DSH Web UI 的输出与日志文件"
        case .directories: return "版本、用户数据、缓存与工具目录"
        case .process: return "Web UI 进程状态与地址"
        case .about: return "版本说明与快捷键"
        }
    }

    /// 分区图标。
    public var systemImage: String {
        switch self {
        case .logs: return "text.alignleft"
        case .directories: return "folder.fill"
        case .process: return "bolt.horizontal.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    /// 左侧分组名。
    public var groupTitle: String {
        switch self {
        case .logs, .directories, .process: return "DSH 运行状态"
        case .about: return "关于"
        }
    }
}

// MARK: - 格式化

/// DSH 页面统一使用的格式化工具（大小 / 时间 / 端口 / 地址）。
public enum DSHFormatting {

    /// 字节数的人读文本（如 "412 MB"）；0 字节固定显示 "0 KB"。
    public static func byteCount(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "yyyy-MM-dd HH:mm:ss"；nil 显示 "—"。
    public static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// "HH:mm:ss"；nil 显示 "—"。
    public static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// 端口展示文本：0 = 自动。
    public static func portText(_ port: Int) -> String {
        port == 0 ? "自动" : "\(port)"
    }

    /// 把带一次性 token 的启动地址做脱敏展示：`http://127.0.0.1:3080/?token=***`。
    public static func redactedURL(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, var components = URLComponents(string: raw) else { return nil }
        if let items = components.queryItems, !items.isEmpty {
            components.queryItems = items.map { item in
                URLQueryItem(name: item.name, value: item.name.lowercased().contains("token") ? "***" : item.value)
            }
        }
        return components.string
    }

    /// 实例数量文案："2 个实例 · 1 个整合包"（没有整合包时省略后半段）。
    public static func instanceCountText(_ instances: [DSHInstalledVersion]) -> String {
        guard !instances.isEmpty else { return "还没有安装实例" }
        let packs = instances.filter { $0.isPack }.count
        let base = "\(instances.count) 个实例"
        return packs > 0 ? "\(base) · \(packs) 个整合包" : base
    }

    /// 实例汇总："2 个实例 · 1 个整合包 · 共 412 MB"；没有实例时给出引导文案。
    public static func installedSummary(_ instances: [DSHInstalledVersion]) -> String {
        guard !instances.isEmpty else { return "还没有安装实例" }
        let total = instances.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
        return "\(instanceCountText(instances)) · 共 \(byteCount(total))"
    }

    /// 实例展示名："我的整合包 · DSH 0.2.1"。
    public static func instanceLabel(_ instance: DSHInstalledVersion) -> String {
        "\(instance.name) · DSH \(instance.dshVersion)"
    }

    /// 实例补充说明：整合包实例带上来源包名 / 版本。
    public static func instanceDetail(_ instance: DSHInstalledVersion) -> String {
        guard instance.isPack else { return "DSH \(instance.dshVersion)" }
        let pack = instance.packName ?? "整合包"
        let version = instance.packVersion.map { " v\($0)" } ?? ""
        return "\(pack)\(version) · DSH \(instance.dshVersion)"
    }
}

// MARK: - 输入校验

/// DSH 设置输入的校验错误。
public enum DSHInputError: LocalizedError, Equatable {
    case emptyPort
    case invalidPort(String)
    case invalidPluginSource(String)
    case invalidRegistry(String)

    public var errorDescription: String? {
        switch self {
        case .emptyPort:
            return "端口不能为空：填 0 表示自动选择，或填 1–65535"
        case .invalidPort(let text):
            return "端口必须是 0–65535 的整数（0 = 自动），当前为「\(text)」"
        case .invalidPluginSource(let text):
            return "插件加载源必须是 http(s) 地址，当前为「\(text)」"
        case .invalidRegistry(let text):
            return "npm registry 必须是 http(s) 地址，或留空使用官方源，当前为「\(text)」"
        }
    }
}

/// DSH 设置页的输入校验（纯函数，便于单测）。
public enum DSHInputValidation {

    /// 端口：0 = 自动，1–65535 = 固定端口。
    public static func port(from text: String) -> Result<Int, DSHInputError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyPort) }
        guard let value = Int(trimmed), (0...65535).contains(value) else {
            return .failure(.invalidPort(trimmed))
        }
        return .success(value)
    }

    /// 插件加载源：必须是 http(s) 地址。
    public static func pluginSource(from text: String) -> Result<String, DSHInputError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidHTTPURL(trimmed) else { return .failure(.invalidPluginSource(trimmed)) }
        return .success(trimmed)
    }

    /// npm registry：空串合法（= 官方），否则必须是 http(s) 地址。
    public static func registry(from text: String) -> Result<String, DSHInputError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success("") }
        guard isValidHTTPURL(trimmed) else { return .failure(.invalidRegistry(trimmed)) }
        return .success(trimmed)
    }

    /// 是否是可用的 http(s) URL。
    public static func isValidHTTPURL(_ text: String) -> Bool {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              !host.isEmpty else { return false }
        return true
    }

    /// registry 的展示文本：空串表示官方源。
    public static func registryDisplayText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(DSHRegistryClient.defaultRegistry)（官方）" : trimmed
    }
}

// MARK: - 环境检测

/// 一条运行时检测结果。
public struct DSHEnvironmentRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let value: String
    public let isMissing: Bool

    public init(id: String, title: String, value: String, isMissing: Bool) {
        self.id = id
        self.title = title
        self.value = value
        self.isMissing = isMissing
    }
}

/// Node / pnpm / npm 运行时的真实检测快照（检测会启动 shell，页面在后台线程调用）。
public struct DSHRuntimeEnvironment: Equatable, Sendable {
    public let node: String?
    public let pnpm: String?
    public let npm: String?
    public let bundledNode: String?
    public let packageManager: String?

    public init(
        node: String?,
        pnpm: String?,
        npm: String?,
        bundledNode: String?,
        packageManager: String?
    ) {
        self.node = node
        self.pnpm = pnpm
        self.npm = npm
        self.bundledNode = bundledNode
        self.packageManager = packageManager
    }

    /// 真实检测本机运行时（可能启动登录 shell 查询 PATH，不要在快照模式或主线程频繁调用）。
    public static func detect() -> DSHRuntimeEnvironment {
        let manager = DSHExecutables.packageManager(paths: .default)
        return DSHRuntimeEnvironment(
            node: DSHExecutables.node()?.path,
            pnpm: DSHExecutables.systemPnpm()?.path,
            npm: DSHExecutables.npm()?.path,
            bundledNode: DSHExecutables.bundledNode()?.path,
            packageManager: manager?.displayName
        )
    }

    /// 单行摘要。
    public var summary: String {
        guard let node else { return "未找到 Node.js 运行时" }
        guard let packageManager else { return "Node \(node) · 未找到 pnpm / npm" }
        return "Node \(node) · 包管理器 \(packageManager)"
    }

    /// 详情行（Node / pnpm / npm / DSH 自带 Node）。
    public var rows: [DSHEnvironmentRow] {
        [
            DSHEnvironmentRow(id: "node", title: "Node.js", value: node ?? "未找到", isMissing: node == nil),
            DSHEnvironmentRow(id: "pnpm", title: "系统 pnpm", value: pnpm ?? "未找到（可用 DSH 自带 pnpm）", isMissing: pnpm == nil),
            DSHEnvironmentRow(id: "npm", title: "npm", value: npm ?? "未找到", isMissing: npm == nil),
            DSHEnvironmentRow(
                id: "bundled-node",
                title: "DSH 自带 Node",
                value: bundledNode ?? "未找到 DeepSeek Harness 桌面端",
                isMissing: bundledNode == nil
            ),
            DSHEnvironmentRow(
                id: "manager",
                title: "实际使用",
                value: packageManager ?? "不可用（安装 / 插件命令会失败）",
                isMissing: packageManager == nil
            )
        ]
    }
}

// MARK: - 数据目录

/// DSH 数据目录的种类。
public enum DSHDataDirectoryKind: String, CaseIterable, Identifiable, Sendable {
    case versions
    case homes
    case logs
    case cache
    case bin

    public var id: String { rawValue }

    /// 目录标题。
    public var title: String {
        switch self {
        case .versions: return "实例目录"
        case .homes: return "实例数据目录（homes）"
        case .logs: return "日志目录"
        case .cache: return "缓存目录"
        case .bin: return "工具目录"
        }
    }

    /// 目录说明。
    public var detail: String {
        switch self {
        case .versions: return "每个实例的 node_modules（同一版本可安装多份）"
        case .homes: return "每个实例独立的 DSH_HOME（插件 / 会话）；登录凭据软链复用 ~/.dsh"
        case .logs: return "Web UI 进程日志"
        case .cache: return "版本列表与插件市场缓存"
        case .bin: return "生成的 pnpm shim 等工具"
        }
    }

    /// 真实路径。
    public func url(paths: DSHPaths) -> URL {
        switch self {
        case .versions: return paths.versionsDirectory
        case .homes: return paths.homesDirectory
        case .logs: return paths.logsDirectory
        case .cache: return paths.cacheDirectory
        case .bin: return paths.binDirectory
        }
    }
}

/// 一个 DSH 数据目录的真实信息。
public struct DSHDataDirectory: Identifiable, Equatable, Sendable {
    public let kind: DSHDataDirectoryKind
    public let path: String
    public let bytes: Int64
    public let exists: Bool

    public var id: String { kind.rawValue }
    public var title: String { kind.title }
    public var detail: String { kind.detail }
    public var sizeText: String { exists ? DSHFormatting.byteCount(bytes) : "不存在" }

    public init(kind: DSHDataDirectoryKind, path: String, bytes: Int64, exists: Bool) {
        self.kind = kind
        self.path = path
        self.bytes = bytes
        self.exists = exists
    }
}

/// 数据目录统计。
public enum DSHDataTools {

    /// 统计各数据目录的真实大小。
    public static func directories(
        paths: DSHPaths,
        kinds: [DSHDataDirectoryKind] = DSHDataDirectoryKind.allCases
    ) -> [DSHDataDirectory] {
        let fileManager = FileManager.default
        return kinds.map { kind in
            let url = kind.url(paths: paths)
            let exists = fileManager.fileExists(atPath: url.path)
            return DSHDataDirectory(
                kind: kind,
                path: url.path,
                bytes: exists ? paths.directorySize(url) : 0,
                exists: exists
            )
        }
    }

    /// 已安装版本的磁盘占用合计。
    public static func totalInstalledBytes(_ versions: [DSHInstalledVersion]) -> Int64 {
        versions.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
    }

    /// 实例 profile 目录（未启动过 Web UI 时可能不存在）。
    /// - Parameter version: 实例 id（实例模型里日志 / profile 都按实例 id 定位）。
    public static func profilePath(paths: DSHPaths, version: String?) -> String? {
        guard let version, !version.isEmpty else { return nil }
        return paths.profileDirectory(for: version).path
    }

    /// 实例自己的 DSH_HOME（无实例时返回 nil）。
    public static func instanceHomePath(paths: DSHPaths, instanceID: String?) -> String? {
        guard let instanceID, !instanceID.isEmpty else { return nil }
        return paths.homeDirectory(for: instanceID).path
    }
}

// MARK: - 缓存清理

/// 一次缓存清理的结果。
public struct DSHCacheClearReport: Equatable, Sendable {
    public let removedFiles: Int
    public let removedBytes: Int64
    public let failedFiles: [String]

    public init(removedFiles: Int, removedBytes: Int64, failedFiles: [String]) {
        self.removedFiles = removedFiles
        self.removedBytes = removedBytes
        self.failedFiles = failedFiles
    }

    /// 结果摘要文案。
    public var summary: String {
        if failedFiles.isEmpty {
            return "已清理 \(removedFiles) 个缓存文件（\(DSHFormatting.byteCount(removedBytes))）"
        }
        return "已清理 \(removedFiles) 个缓存文件，\(failedFiles.count) 个删除失败"
    }
}

/// 缓存维护：列出 / 真实删除 `cache/` 下的缓存文件。
public enum DSHCacheMaintenance {

    /// 缓存目录下的文件（不递归子目录，缓存只放扁平文件）。
    public static func cacheFiles(paths: DSHPaths) -> [URL] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: paths.cacheDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    /// 真实删除缓存文件。
    public static func clearCache(paths: DSHPaths) -> DSHCacheClearReport {
        let fileManager = FileManager.default
        var removed = 0
        var bytes: Int64 = 0
        var failed: [String] = []
        for url in cacheFiles(paths: paths) {
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            do {
                try fileManager.removeItem(at: url)
                removed += 1
                bytes += size
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        return DSHCacheClearReport(removedFiles: removed, removedBytes: bytes, failedFiles: failed)
    }
}

// MARK: - 删除所有数据

/// 危险区里会被删除的一个启动器数据目录。
public struct DSHDataDeletionTarget: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let path: String

    public init(id: String, title: String, path: String) {
        self.id = id
        self.title = title
        self.path = path
    }
}

/// 一次「删除所有 DSH 实例数据」的结果。
public struct DSHDataDeletionReport: Equatable, Sendable {
    public let removed: [String]
    public let failures: [String]
    /// 删除后又重建的空壳目录（如 homes/）。
    public let recreated: [String]

    public init(removed: [String], failures: [String], recreated: [String] = []) {
        self.removed = removed
        self.failures = failures
        self.recreated = recreated
    }

    /// 结果摘要文案。
    public var summary: String {
        if failures.isEmpty {
            return removed.isEmpty ? "没有需要删除的实例数据" : "已删除 \(removed.count) 个实例数据目录：\(removed.joined(separator: "、"))"
        }
        return "已删除 \(removed.count) 个目录，\(failures.count) 个删除失败"
    }
}

/// 危险区：删除启动器里的所有 DSH 实例数据。
///
/// 删除 `versions / homes / logs / cache`（以及迁移前的旧共享 home）；
/// **不会删除 `~/.dsh`**：登录凭据（API Key / 账号）来自那里，必须保留。
public enum DSHDataDeletion {

    /// 会被删除的目录（供确认框明确列出）。旧共享 `homeRoot` 只在存在时才会被列进去。
    public static func targets(paths: DSHPaths) -> [DSHDataDeletionTarget] {
        var targets = [
            DSHDataDeletionTarget(id: "versions", title: "实例目录", path: paths.versionsDirectory.path),
            DSHDataDeletionTarget(id: "homes", title: "实例数据目录", path: paths.homesDirectory.path),
            DSHDataDeletionTarget(id: "logs", title: "日志目录", path: paths.logsDirectory.path),
            DSHDataDeletionTarget(id: "cache", title: "缓存目录", path: paths.cacheDirectory.path)
        ]
        // 迁移前的旧共享 home（如果还在），属于启动器自己的数据
        let legacyHome = paths.homeRoot
        if FileManager.default.fileExists(atPath: legacyHome.path) {
            targets.append(
                DSHDataDeletionTarget(id: "legacy-home", title: "历史共享 home", path: legacyHome.path)
            )
        }
        return targets
    }

    /// 真实删除上述目录，并重建 `homes/` 空壳；不会碰 `~/.dsh`。
    public static func deleteAll(paths: DSHPaths) -> DSHDataDeletionReport {
        let fileManager = FileManager.default
        var removed: [String] = []
        var failures: [String] = []
        var recreated: [String] = []
        for target in targets(paths: paths) {
            guard fileManager.fileExists(atPath: target.path) else { continue }
            // 空的 homes/ 空壳已经等同于清理完成，保留它避免重复删除
            if target.id == "homes", isEmptyDirectory(target.path) { continue }
            do {
                try fileManager.removeItem(at: URL(fileURLWithPath: target.path))
                removed.append(target.title)
            } catch {
                failures.append("\(target.title)（\(error.localizedDescription)）")
            }
        }
        // 保留目录空壳，方便下次安装 / 启动直接写入
        do {
            try fileManager.createDirectory(at: paths.homesDirectory, withIntermediateDirectories: true)
            recreated.append("实例数据目录")
        } catch {
            failures.append("重建实例数据目录失败（\(error.localizedDescription)）")
        }
        do {
            try fileManager.createDirectory(at: paths.root, withIntermediateDirectories: true)
        } catch {
            // 根目录通常已存在，失败不影响结果
        }
        return DSHDataDeletionReport(removed: removed, failures: failures, recreated: recreated)
    }

    /// 目录是否为空。
    private static func isEmptyDirectory(_ path: String) -> Bool {
        let contents = try? FileManager.default.contentsOfDirectory(atPath: path)
        return (contents?.isEmpty ?? false)
    }
}

// MARK: - 日志文件

/// 一个版本日志文件的真实信息。
public struct DSHLogFileInfo: Equatable, Sendable {
    public let url: URL
    public let exists: Bool
    public let bytes: Int64
    public let modifiedAt: Date?

    public var sizeText: String { exists ? DSHFormatting.byteCount(bytes) : "不存在" }
    public var modifiedText: String { DSHFormatting.dateTime(modifiedAt) }
}

/// 日志文件的读取 / 截断工具。
public enum DSHLogTools {

    /// 读取日志文件信息。
    public static func info(paths: DSHPaths, version: String?) -> DSHLogFileInfo {
        guard let version, !version.isEmpty else {
            return DSHLogFileInfo(
                url: paths.logsDirectory.appendingPathComponent("unknown.log"),
                exists: false,
                bytes: 0,
                modifiedAt: nil
            )
        }
        let url = paths.logFile(for: version)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return DSHLogFileInfo(url: url, exists: false, bytes: 0, modifiedAt: nil)
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return DSHLogFileInfo(
            url: url,
            exists: true,
            bytes: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate
        )
    }

    /// 读取日志文件最后 `maxLines` 行（文件不存在返回空数组；超大文件只读尾部 512KB）。
    public static func readTail(paths: DSHPaths, version: String?, maxLines: Int = 200) -> [String] {
        guard let version, !version.isEmpty else { return [] }
        let url = paths.logFile(for: version)
        guard let data = readTailData(url, maxBytes: 512 * 1024), !data.isEmpty else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        // 先剔除空行（文件末尾的换行会产生空串），再取最后 maxLines 行
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return Array(lines.suffix(max(1, maxLines)))
    }

    /// 真实清空日志文件（截断为 0 字节）；文件不存在返回 false。
    @discardableResult
    public static func truncate(paths: DSHPaths, version: String?) throws -> Bool {
        guard let version, !version.isEmpty else { return false }
        let url = paths.logFile(for: version)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return false }
        try Data().write(to: url, options: .atomic)
        return true
    }

    /// 展示用的日志版本：优先当前运行版本，其次已选版本。
    public static func displayVersion(selected: DSHInstalledVersion?, active: String?) -> String? {
        if let active, !active.isEmpty { return active }
        return selected?.version
    }

    /// 读取文件尾部数据（大文件只读最后 maxBytes）。
    private static func readTailData(_ url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size <= UInt64(maxBytes) {
            try? handle.seek(toOffset: 0)
            return try? handle.readToEnd()
        }
        let offset = size - UInt64(maxBytes)
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        // 丢掉被截断的首行，避免出现半行日志
        if let firstNewline = data.firstIndex(of: 0x0A) {
            return data.subdata(in: data.index(after: firstNewline)..<data.endIndex)
        }
        return data
    }
}

// MARK: - 进程状态文案

/// 进程状态在 UI 上的展示文案。
public struct DSHProcessStatusText: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let isRunning: Bool
    public let isError: Bool

    public init(title: String, detail: String, isRunning: Bool, isError: Bool) {
        self.title = title
        self.detail = detail
        self.isRunning = isRunning
        self.isError = isError
    }
}

/// 把 `DSHProcessState` 转成页面文案（纯函数，便于单测）。
public enum DSHProcessStatusFormatter {

    /// 生成状态文案。
    public static func text(
        for state: DSHProcessState,
        port: Int? = nil,
        startedAt: Date? = nil
    ) -> DSHProcessStatusText {
        switch state {
        case .idle:
            return DSHProcessStatusText(
                title: "未运行",
                detail: "在「启动」页选择版本后启动 DSH Web UI",
                isRunning: false,
                isError: false
            )
        case .starting:
            return DSHProcessStatusText(
                title: "启动中",
                detail: "正在启动 DSH Web UI，等待输出启动地址…",
                isRunning: false,
                isError: false
            )
        case .running(let url):
            let redacted = DSHFormatting.redactedURL(url) ?? url
            let portText = port.map { "端口 \($0)" } ?? "端口未知"
            let timeText = startedAt.map { "启动于 \(DSHFormatting.time($0))" } ?? ""
            return DSHProcessStatusText(
                title: "运行中",
                detail: [portText, timeText, redacted].filter { !$0.isEmpty }.joined(separator: " · "),
                isRunning: true,
                isError: false
            )
        case .stopping:
            return DSHProcessStatusText(
                title: "正在停止",
                detail: "正在结束 DSH Web UI 进程…",
                isRunning: false,
                isError: false
            )
        case .failed(let message):
            return DSHProcessStatusText(
                title: "启动失败",
                detail: message,
                isRunning: false,
                isError: true
            )
        }
    }
}

// MARK: - 共享行组件

/// DSH 设置页 / 更多页共用的布尔设置行：`LauncherToggle` + 可选提示 + 分隔线。
struct DSHBooleanRow: View {
    @Environment(\.launcherTheme) private var theme

    let title: String
    let subtitle: String?
    let tooltip: String?
    @Binding var isOn: Bool
    var showsDivider: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: LauncherSpace.md) {
                LauncherToggle(title, isOn: $isOn, subtitle: subtitle)
                if let tooltip {
                    LauncherHintIcon(tooltip)
                }
            }
            if showsDivider {
                Rectangle()
                    .fill(theme.colors.stroke.opacity(0.6))
                    .frame(height: 1)
            }
        }
        .padding(.vertical, LauncherSpace.xxs)
    }
}

/// 等宽路径文本：中间截断，避免长路径撑宽布局。
struct DSHPathText: View {
    let text: String
    var tone: LauncherTextTone = .tertiary
    var size: CGFloat = 10
    var maxWidth: CGFloat = 320

    var body: some View {
        LauncherMonoText(text, tone: tone, size: size)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: maxWidth, alignment: .trailing)
    }
}

/// 信息行：左侧标题 + 右侧等宽值（用于运行时 / 目录详情）。
struct DSHInfoRow: View {
    @Environment(\.launcherTheme) private var theme

    let title: String
    let value: String
    var isMissing: Bool = false
    var systemImage: String?

    var body: some View {
        HStack(spacing: LauncherSpace.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .textStyle(.micro, tone: isMissing ? .tertiary : .secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
            Text(title)
                .textStyle(.caption, tone: .secondary)
                .lineLimit(1)
            Spacer(minLength: LauncherSpace.sm)
            LauncherMonoText(value, tone: isMissing ? .tertiary : .primary, size: 10)
                .lineLimit(1)
                .truncationMode(.middle)
            if isMissing {
                LauncherBadge("未找到", tone: .warning)
            }
        }
        .frame(minHeight: LauncherSpace.xl)
    }
}

/// 数据目录行：标题 / 路径 / 大小 / 打开按钮。
struct DSHDataDirectoryRow: View {
    @Environment(\.launcherTheme) private var theme

    let title: String
    let subtitle: String
    let path: String
    let sizeText: String
    let exists: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: LauncherSpace.md) {
            VStack(alignment: .leading, spacing: LauncherSpace.xxs) {
                HStack(spacing: LauncherSpace.xs) {
                    Text(title)
                        .textStyle(.bodyStrong)
                        .lineLimit(1)
                    LauncherBadge(sizeText, tone: exists ? .neutral : .warning)
                }
                Text(subtitle)
                    .textStyle(.micro, tone: .tertiary)
                    .lineLimit(1)
                LauncherMonoText(path, tone: .tertiary, size: 10)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: LauncherSpace.sm)
            LauncherIconButton(
                systemImage: "folder",
                variant: .ghost,
                size: .small,
                accessibilityLabel: "在访达中打开\(title)",
                isDisabled: !exists
            ) {
                onOpen()
            }
        }
        .padding(.vertical, LauncherSpace.xs)
    }
}
