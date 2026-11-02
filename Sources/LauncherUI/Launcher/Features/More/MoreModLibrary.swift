import Foundation

// MARK: - 模组条目

/// `mods/` 目录里的一个真实模组文件（`.jar` 或 `.jar.disabled`）。
public struct MoreModItem: Identifiable, Equatable, Sendable {
    /// 实际文件路径（禁用状态带 `.disabled` 后缀）。
    public let url: URL
    /// 实际文件名。
    public let fileName: String
    /// 展示名：去掉 `.disabled` 后缀。
    public let displayName: String
    /// 真实字节大小。
    public let byteSize: Int64
    /// 文件修改时间。
    public let modifiedAt: Date
    /// 是否启用（没有 `.disabled` 后缀即启用）。
    public let isEnabled: Bool

    public var id: URL { url }

    public init(url: URL, fileName: String, displayName: String, byteSize: Int64, modifiedAt: Date, isEnabled: Bool) {
        self.url = url
        self.fileName = fileName
        self.displayName = displayName
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
        self.isEnabled = isEnabled
    }

    /// 人读大小，例如 "2.4 MB"。
    public var sizeText: String {
        MoreFormatting.byteCountText(byteSize)
    }

    /// 修改日期，例如 "10-28 14:20"。
    public var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: modifiedAt)
    }
}

// MARK: - 错误

/// 模组启停 / 删除中的真实错误。
public enum MoreModError: LocalizedError {
    case targetExists(String)
    case missingFile(String)
    case renameFailed(String)

    public var errorDescription: String? {
        switch self {
        case .targetExists(let name):
            return "同名文件已存在：\(name)"
        case .missingFile(let name):
            return "模组文件不存在：\(name)"
        case .renameFailed(let message):
            return "重命名失败：\(message)"
        }
    }
}

// MARK: - 模组库

/// 模组管理：真实扫描 `mods/`、通过重命名 `.jar` ↔ `.jar.disabled` 启停、删除到废纸篓。
public enum MoreModLibrary {
    /// 模组目录名。
    public static let modsFolderName = "mods"
    /// `mods/` 内会被列出的文件后缀（含禁用态）。
    public static let enabledSuffix = ".jar"
    /// 禁用态后缀。
    public static let disabledSuffix = ".jar.disabled"

    /// 实例下的模组目录。
    public static func modsDirectory(in instanceDirectory: URL) -> URL {
        instanceDirectory.appendingPathComponent(modsFolderName, isDirectory: true)
    }

    /// 是否是需要展示的模组文件名。
    public static func isModFileName(_ fileName: String) -> Bool {
        let lowered = fileName.lowercased()
        return lowered.hasSuffix(enabledSuffix) || lowered.hasSuffix(disabledSuffix)
    }

    /// 展示名（去掉 `.disabled` 后缀）。
    public static func displayName(for fileName: String) -> String {
        guard fileName.lowercased().hasSuffix(".disabled") else { return fileName }
        return String(fileName.dropLast(".disabled".count))
    }

    /// 扫描真实的模组列表（目录不存在时返回空数组）。
    public static func scan(in modsDirectory: URL) -> [MoreModItem] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: modsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let items: [MoreModItem] = entries.compactMap { url in
            guard isModFileName(url.lastPathComponent) else { return nil }
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .contentModificationDateKey,
                .isRegularFileKey
            ])
            guard values?.isRegularFile != false else { return nil }
            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            let modified = values?.contentModificationDate ?? .distantPast
            let enabled = !url.lastPathComponent.lowercased().hasSuffix(".disabled")
            return MoreModItem(
                url: url,
                fileName: url.lastPathComponent,
                displayName: displayName(for: url.lastPathComponent),
                byteSize: size,
                modifiedAt: modified,
                isEnabled: enabled
            )
        }
        return sorted(items, ascending: true)
    }

    /// 启用 / 禁用：真实重命名 `.jar` ↔ `.jar.disabled`，返回新文件路径。
    @discardableResult
    public static func setEnabled(_ item: MoreModItem, enabled: Bool) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: item.url.path) else {
            throw MoreModError.missingFile(item.fileName)
        }
        guard enabled != item.isEnabled else { return item.url }

        let targetName: String
        if enabled {
            targetName = displayName(for: item.fileName)
        } else {
            targetName = item.fileName + ".disabled"
        }
        let target = item.url.deletingLastPathComponent().appendingPathComponent(targetName)
        guard target.standardizedFileURL.path != item.url.standardizedFileURL.path else { return item.url }
        guard !fileManager.fileExists(atPath: target.path) else {
            throw MoreModError.targetExists(targetName)
        }
        do {
            try fileManager.moveItem(at: item.url, to: target)
        } catch {
            throw MoreModError.renameFailed(error.localizedDescription)
        }
        return target
    }

    /// 删除到废纸篓（调用方负责二次确认）。
    public static func delete(_ item: MoreModItem) throws {
        try InstanceActions.trash(item.url)
    }

    /// 按关键词过滤（文件展示名，忽略大小写）。
    public static func filtered(_ items: [MoreModItem], query: String) -> [MoreModItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    /// 按展示名排序（自然排序，`ascending` 控制升降）。
    public static func sorted(_ items: [MoreModItem], ascending: Bool) -> [MoreModItem] {
        items.sorted { lhs, rhs in
            let result = lhs.displayName.localizedStandardCompare(rhs.displayName)
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    /// 启用 / 禁用数量。
    public static func counts(_ items: [MoreModItem]) -> (enabled: Int, disabled: Int) {
        let enabled = items.reduce(0) { $0 + ($1.isEnabled ? 1 : 0) }
        return (enabled, items.count - enabled)
    }

    /// 启用 / 禁用总占用。
    public static func totalSizeText(_ items: [MoreModItem]) -> String {
        MoreFormatting.byteCountText(items.reduce(0) { $0 + $1.byteSize })
    }
}
