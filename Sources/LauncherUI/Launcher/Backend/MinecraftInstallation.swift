import Foundation

/// 版本目录里已安装的一个版本。
public struct InstalledVersion: Identifiable, Equatable, Sendable {
    public let id: String
    public let jsonURL: URL
    public let jarURL: URL?
    public let versionType: String
    public let lastModified: Date

    public var jarExists: Bool {
        guard let jarURL else { return false }
        return FileManager.default.fileExists(atPath: jarURL.path)
    }

    public var sizeDescription: String {
        guard let values = try? jsonURL.deletingLastPathComponent().resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
              let size = values.totalFileAllocatedSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

/// 本地 Minecraft 安装目录（真实文件系统）。
public struct MinecraftInstallation {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var versionsDirectory: URL { root.appendingPathComponent("versions", isDirectory: true) }
    public var librariesDirectory: URL { root.appendingPathComponent("libraries", isDirectory: true) }
    public var assetsDirectory: URL { root.appendingPathComponent("assets", isDirectory: true) }
    /// 启动器缓存（父版本 JSON / 资源清单 / 日志配置）放在用户缓存目录，不污染游戏目录。
    public var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? root
        return base
            .appendingPathComponent("BlockLauncher", isDirectory: true)
            .appendingPathComponent("minecraft", isDirectory: true)
    }

    public func versionDirectory(_ versionID: String) -> URL {
        versionsDirectory.appendingPathComponent(versionID, isDirectory: true)
    }

    public func versionJSONURL(_ versionID: String) -> URL {
        versionDirectory(versionID).appendingPathComponent("\(versionID).json")
    }

    public func versionJarURL(_ versionID: String) -> URL {
        versionDirectory(versionID).appendingPathComponent("\(versionID).jar")
    }

    public func nativesDirectory(_ versionID: String) -> URL {
        versionDirectory(versionID).appendingPathComponent("natives", isDirectory: true)
    }

    /// 扫描 `versions/` 目录。
    public func installedVersions() -> [InstalledVersion] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: versionsDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var versions: [InstalledVersion] = []
        for directory in entries {
            let id = directory.lastPathComponent
            let jsonURL = directory.appendingPathComponent("\(id).json")
            guard fileManager.fileExists(atPath: jsonURL.path) else { continue }
            let jarURL = directory.appendingPathComponent("\(id).jar")
            guard fileManager.fileExists(atPath: jarURL.path) else { continue }
            let modified = (try? jsonURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let type = (try? VersionDetailLoader.load(from: jsonURL).type) ?? "release"
            versions.append(
                InstalledVersion(
                    id: id,
                    jsonURL: jsonURL,
                    jarURL: fileManager.fileExists(atPath: jarURL.path) ? jarURL : nil,
                    versionType: type,
                    lastModified: modified
                )
            )
        }
        return versions.sorted { $0.lastModified > $1.lastModified }
    }

    /// 简单读取版本 JSON（用于列表展示）。
    public enum VersionDetailLoader {
        public static func load(from url: URL) throws -> VersionDetail {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(VersionDetail.self, from: data)
        }
    }
}
