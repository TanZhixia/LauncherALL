import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - 实例文件操作

/// 实例（版本目录）的真实文件操作：打开 / 拷贝 / 重命名 / 复制 / 删除到废纸篓。
/// 启动页的「实例操作」菜单、更多页的备份/清理都走这一层，保证行为一致可测。
public enum InstanceActions {

    // MARK: 基础动作

    /// 在访达中打开目录（不存在时返回 false）。
    @discardableResult
    public static func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    /// 在访达中选中并显示。
    public static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 写入系统剪贴板。
    public static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 删除到废纸篓（可恢复；目录不存在视为成功）。
    public static func trash(_ url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
    }

    /// 用系统文件夹选择器选一个目录（返回 nil 表示用户取消）。
    @MainActor
    public static func pickDirectory(message: String, prompt: String = "选择", startingAt: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        panel.message = message
        if let startingAt { panel.directoryURL = startingAt }
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 用系统文件选择器选一个文件（可限定类型）。
    @MainActor
    public static func pickFile(message: String, prompt: String = "选择", allowedExtensions: [String] = []) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        if !allowedExtensions.isEmpty {
            panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: 实例管理

    /// 实例名规则：非空、去掉首尾空白、不能包含路径分隔符与冒号。
    public static func normalizedInstanceName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != ".", trimmed != ".." else { return nil }
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|\u{0}")
        guard trimmed.rangeOfCharacter(from: banned) == nil else { return nil }
        guard trimmed.count <= 64 else { return nil }
        return trimmed
    }

    /// 重命名实例：移动目录并把 `<id>.json` / `<id>.jar` 一起改名、回写 JSON 的 `id` 字段。
    /// 返回新的实例 id。
    @discardableResult
    public static func rename(
        versionID: String,
        to rawName: String,
        installation: MinecraftInstallation
    ) throws -> String {
        guard let newID = normalizedInstanceName(rawName) else {
            throw InstanceActionError.invalidName(rawName)
        }
        guard newID != versionID else { return versionID }

        let fileManager = FileManager.default
        let sourceDirectory = installation.versionDirectory(versionID)
        let targetDirectory = installation.versionDirectory(newID)
        try validateInsideVersions(sourceDirectory, installation: installation)
        try validateInsideVersions(targetDirectory, installation: installation)
        guard fileManager.fileExists(atPath: sourceDirectory.path) else {
            throw InstanceActionError.missingInstance(versionID)
        }
        guard !fileManager.fileExists(atPath: targetDirectory.path) else {
            throw InstanceActionError.nameInUse(newID)
        }

        // 1. 目录改名
        try fileManager.moveItem(at: sourceDirectory, to: targetDirectory)

        // 2. 目录内 json / jar 跟着改名
        try renameVersionFiles(in: targetDirectory, from: versionID, to: newID)

        // 3. 回写 JSON 的 id（只改 id，保留其它字段原样）
        try rewriteVersionJSONID(at: installation.versionJSONURL(newID), id: newID)
        return newID
    }

    /// 复制实例：递归复制目录 → 改名内部文件 → 回写 id。返回新实例 id。
    @discardableResult
    public static func duplicate(
        versionID: String,
        as rawName: String,
        installation: MinecraftInstallation
    ) throws -> String {
        guard let newID = normalizedInstanceName(rawName) else {
            throw InstanceActionError.invalidName(rawName)
        }
        let fileManager = FileManager.default
        let sourceDirectory = installation.versionDirectory(versionID)
        let targetDirectory = installation.versionDirectory(newID)
        try validateInsideVersions(sourceDirectory, installation: installation)
        try validateInsideVersions(targetDirectory, installation: installation)
        guard fileManager.fileExists(atPath: sourceDirectory.path) else {
            throw InstanceActionError.missingInstance(versionID)
        }
        guard !fileManager.fileExists(atPath: targetDirectory.path) else {
            throw InstanceActionError.nameInUse(newID)
        }

        try fileManager.copyItem(at: sourceDirectory, to: targetDirectory)
        try renameVersionFiles(in: targetDirectory, from: versionID, to: newID)
        try rewriteVersionJSONID(at: installation.versionJSONURL(newID), id: newID)
        return newID
    }

    /// 删除实例到废纸篓。
    public static func delete(versionID: String, installation: MinecraftInstallation) throws {
        let directory = installation.versionDirectory(versionID)
        try validateInsideVersions(directory, installation: installation)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw InstanceActionError.missingInstance(versionID)
        }
        try trash(directory)
    }

    /// 实例目录占用的真实字节数。
    public static func size(of directory: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// 目录大小的人读文本。
    public static func sizeText(of directory: URL) -> String {
        ByteCountFormatter.string(fromByteCount: size(of: directory), countStyle: .file)
    }

    // MARK: 内部

    /// 防御：所有实例文件操作必须发生在 `versions/` 内，避免被传入任意路径。
    private static func validateInsideVersions(_ directory: URL, installation: MinecraftInstallation) throws {
        let root = installation.versionsDirectory.standardizedFileURL.path
        let target = directory.standardizedFileURL.path
        guard target == root || target.hasPrefix(root + "/") else {
            throw InstanceActionError.outsideVersions(target)
        }
    }

    private static func renameVersionFiles(in directory: URL, from oldID: String, to newID: String) throws {
        let fileManager = FileManager.default
        for ext in ["json", "jar"] {
            let oldURL = directory.appendingPathComponent("\(oldID).\(ext)")
            let newURL = directory.appendingPathComponent("\(newID).\(ext)")
            if fileManager.fileExists(atPath: oldURL.path) {
                try fileManager.moveItem(at: oldURL, to: newURL)
            }
        }
    }

    /// 只改 JSON 里的 `id` 字段，其余保持原样（避免解码再编码丢字段）。
    private static func rewriteVersionJSONID(at url: URL, id: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        object["id"] = id
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try updated.write(to: url, options: .atomic)
    }
}

// MARK: - 错误

public enum InstanceActionError: LocalizedError {
    case invalidName(String)
    case nameInUse(String)
    case missingInstance(String)
    case outsideVersions(String)
    case referencedBy([String])

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "实例名不合法：\(name)（不能为空，不能包含 / \\ : * ? \" < > |，最多 64 个字符）"
        case .nameInUse(let name):
            return "实例 \(name) 已存在"
        case .missingInstance(let id):
            return "实例 \(id) 不存在或已被删除"
        case .outsideVersions(let path):
            return "路径不在 versions 目录内，已拒绝操作：\(path)"
        case .referencedBy(let ids):
            return "该版本被其它实例依赖（\(ids.joined(separator: "、"))），请先删除依赖它的实例"
        }
    }
}
