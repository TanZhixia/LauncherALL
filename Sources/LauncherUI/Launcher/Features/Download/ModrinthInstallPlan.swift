import Foundation

// MARK: - 安装路径决策

/// 社区资源的安装路径决策（纯函数，便于单元测试）：
/// 哪类资源落到实例目录的哪个子目录、文件名如何清洗、实例 id 如何生成。
public enum ModrinthInstallPlanner {
    /// 单个资源文件的落盘路径；`world` 需要解压，返回 nil。
    public static func fileDestination(
        instanceDirectory: URL,
        type: ModrinthProjectType,
        filename: String
    ) -> URL? {
        guard let subdirectory = type.installSubdirectory else { return nil }
        let safeName = sanitizedFilename(filename)
        guard !safeName.isEmpty else { return nil }
        return instanceDirectory
            .appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent(safeName)
    }

    /// 世界压缩包的解压目标目录：`saves/<世界名>`。
    public static func worldDestination(instanceDirectory: URL, filename: String) -> URL {
        instanceDirectory
            .appendingPathComponent("saves", isDirectory: true)
            .appendingPathComponent(worldName(from: filename), isDirectory: true)
    }

    /// 清洗文件名：去掉路径分隔符与首尾空白，防止写出实例目录。
    public static func sanitizedFilename(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let banned = CharacterSet(charactersIn: "/\\:\u{0}")
        let cleaned = trimmed
            .components(separatedBy: banned)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return cleaned
    }

    /// 世界名：去掉 .zip 扩展名并清洗非法字符。
    public static func worldName(from filename: String) -> String {
        let base = (filename as NSString).deletingPathExtension
        let cleaned = sanitizedFilename(base)
        return cleaned.isEmpty ? "world" : cleaned
    }

    /// 由整合包名与版本生成实例 id：只保留字母数字、`-`、`_`、`.`，避免中文名带来的路径问题。
    public static func instanceID(name: String, versionID: String) -> String {
        func slug(_ raw: String) -> String {
            let lowered = raw.lowercased()
            var output = ""
            var lastWasDash = false
            for character in lowered {
                if character.isASCII, character.isLetter || character.isNumber {
                    output.append(character)
                    lastWasDash = false
                } else if !lastWasDash, !output.isEmpty {
                    output.append("-")
                    lastWasDash = true
                }
            }
            return output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        // 中文名拼音化太复杂：拿不到 ASCII 名时退回 modpack 前缀，保证目录名可用
        let namePart = slug(name).isEmpty ? "modpack" : slug(name)
        let versionPart = slug(versionID)
        let joined = [namePart, versionPart].filter { !$0.isEmpty }.joined(separator: "-")
        return String(joined.prefix(64))
    }

    /// 校验压缩包内的一条条目名（zip-slip 防护）：
    /// 允许目录条目（以 `/` 结尾）与 `./` 前缀，拒绝绝对路径、`..` 与反斜杠路径分隔符。
    public static func isSafeZipEntry(_ entry: String) -> Bool {
        var name = entry
        if name.hasSuffix("/") { name.removeLast() }
        while name.hasPrefix("./") { name.removeFirst(2) }
        guard !name.isEmpty else { return false }
        return isSafeRelativePath(name)
    }

    /// 第一批不安全的压缩包条目（没有则 nil）；供解压前统一校验，避免 zip-slip 写出目标目录。
    public static func firstUnsafeZipEntry(in entries: [String]) -> String? {
        entries.first { !isSafeZipEntry($0) }
    }

    /// 校验 mrpack 内的相对路径：不允许绝对路径与 `..` 逃逸。
    public static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty else { return false }
        for component in components {
            if component == ".." || component == "." { return false }
            if component.contains("\\") { return false }
        }
        return true
    }
}

// MARK: - .mrpack 清单

/// Modrinth 整合包（`.mrpack`）里的 `modrinth.index.json`。
public struct ModrinthModpackIndex: Decodable, Sendable, Equatable {
    /// 文件哈希（sha1 / sha512 均为可选，但 Modrinth 至少给一个）。
    public struct Hashes: Decodable, Sendable, Equatable {
        public let sha1: String?
        public let sha512: String?
    }

    /// 文件的环境标记（client / server / unsupported）。
    public struct Environment: Decodable, Sendable, Equatable {
        public let client: String?
        public let server: String?
    }

    /// 整合包内需要下载的一个文件。
    public struct File: Decodable, Sendable, Equatable {
        public let path: String
        public let hashes: Hashes
        public let env: Environment?
        public let downloads: [URL]
        public let fileSize: Int64?

        /// 客户端是否需要这个文件（`unsupported` 表示服务端专用）。
        public var isClientRequired: Bool {
            guard let env else { return true }
            return env.client != "unsupported"
        }
    }

    /// 整合包声明使用的加载器。
    public enum Loader: Equatable, Sendable {
        case vanilla
        case fabric(String)
        case quilt(String)
        case forge(String)
        case neoforge(String)
        /// 启动器不认识的加载器（原样带出依赖名，给出真实错误说明）。
        case unsupported(String)

        /// 加载器版本。
        public var version: String? {
            switch self {
            case .fabric(let version), .quilt(let version), .forge(let version), .neoforge(let version):
                return version
            case .vanilla, .unsupported:
                return nil
            }
        }

        /// 是否可以用当前启动器安装（Fabric / Quilt / 原版）。
        public var isSupported: Bool {
            switch self {
            case .vanilla, .fabric, .quilt: return true
            case .forge, .neoforge, .unsupported: return false
            }
        }

        /// 展示名（详情面板 / 安装进度）。
        public var title: String {
            switch self {
            case .vanilla: return "原版"
            case .fabric(let version): return "Fabric \(version)"
            case .quilt(let version): return "Quilt \(version)"
            case .forge(let version): return "Forge \(version)"
            case .neoforge(let version): return "NeoForge \(version)"
            case .unsupported(let name): return name
            }
        }
    }

    public let formatVersion: Int
    public let game: String
    public let versionID: String
    public let name: String
    public let files: [File]
    /// 依赖：`minecraft` / `fabric-loader` / `quilt-loader` / `forge` / `neoforge`。
    public let dependencies: [String: String]

    /// 基础 Minecraft 版本。
    public var minecraftVersion: String? { dependencies["minecraft"] }

    /// 声明的加载器（未声明时为原版）。
    public var loader: Loader {
        if let fabric = dependencies["fabric-loader"] { return .fabric(fabric) }
        if let quilt = dependencies["quilt-loader"] { return .quilt(quilt) }
        if let forge = dependencies["forge"] { return .forge(forge) }
        if let neoforge = dependencies["neoforge"] { return .neoforge(neoforge) }
        let known = Set(["minecraft", "fabric-loader", "quilt-loader", "forge", "neoforge"])
        if let unknown = dependencies.keys.first(where: { !known.contains($0) }) {
            return .unsupported(unknown)
        }
        return .vanilla
    }

    /// 需要下载（客户端）的文件。
    public var clientFiles: [File] {
        files.filter { $0.isClientRequired }
    }

    /// 解析 `.mrpack` 内的清单；格式不合法时给出明确错误。
    public static func decode(_ data: Data) throws -> ModrinthModpackIndex {
        do {
            let index = try JSONDecoder().decode(ModrinthModpackIndex.self, from: data)
            guard index.formatVersion == 1 else {
                throw ModpackIndexError.unsupportedFormat(index.formatVersion)
            }
            guard !index.game.isEmpty, index.game == "minecraft" else {
                throw ModpackIndexError.notMinecraft(index.game)
            }
            return index
        } catch let error as ModpackIndexError {
            throw error
        } catch {
            throw ModpackIndexError.invalidJSON(error.localizedDescription)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case game
        case versionID = "versionId"
        case name
        case files
        case dependencies
    }
}

// MARK: - 清单完整性

public extension ModrinthModpackIndex {
    /// 缺少下载地址的客户端文件：Modrinth 规范要求 `downloads` 非空，
    /// 出现空值说明整合包不完整，安装流程必须报错而不是静默跳过。
    var clientFilesWithoutDownload: [File] {
        clientFiles.filter { $0.downloads.isEmpty }
    }
}

// MARK: - 加载器兼容性

/// 实例的加载器类型（用于社区资源安装前的兼容性提示）。
public enum ModrinthLoaderKind: String, Sendable, Equatable {
    case vanilla
    case fabric
    case quilt
    case forge
    case neoforge

    /// 展示名。
    public var title: String {
        switch self {
        case .vanilla: return "原版"
        case .fabric: return "Fabric"
        case .quilt: return "Quilt"
        case .forge: return "Forge"
        case .neoforge: return "NeoForge"
        }
    }
}

/// 加载器判定与兼容性判断：安装社区资源前提示「Fabric 模组装进原版实例」这类不匹配。
public enum ModrinthLoaderDetector {
    /// 已知的模组加载器标记（Modrinth 版本接口的 `loaders` 字段）。
    private static let modLoaderNames: Set<String> = [
        "fabric", "quilt", "forge", "neoforge", "liteloader", "modloader", "rift", "sponge"
    ]

    /// 从实例 id / 主类 / `inheritsFrom` 继承链判断加载器类型（只读本地版本 JSON）。
    public static func kind(forInstance instanceID: String, installation: MinecraftInstallation) -> ModrinthLoaderKind {
        let fileManager = FileManager.default
        var current = instanceID
        var depth = 0
        while depth < 4 {
            if let matched = kindFromName(current) { return matched }
            let candidates = [
                installation.versionJSONURL(current),
                installation.cacheDirectory.appendingPathComponent("parents/\(current).json")
            ]
            guard let url = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }),
                  let data = try? Data(contentsOf: url),
                  let detail = try? JSONDecoder().decode(VersionDetail.self, from: data) else {
                return .vanilla
            }
            if let matched = kindFromMainClass(detail.mainClass) { return matched }
            if let matched = kindFromName(detail.id) { return matched }
            guard let parent = detail.inheritsFrom else { return .vanilla }
            current = parent
            depth += 1
        }
        return .vanilla
    }

    /// 该 Modrinth 版本声明的加载器能否在目标实例加载器下加载（纯函数）。
    /// 资源包 / 数据包等不声明模组加载器的一律视为兼容。
    public static func isCompatible(versionLoaders: [String], instance: ModrinthLoaderKind) -> Bool {
        let loaders = Set(versionLoaders.map { $0.lowercased() })
        guard !loaders.isEmpty else { return true }
        let declared = loaders.intersection(modLoaderNames)
        guard !declared.isEmpty else { return true }
        switch instance {
        case .fabric: return loaders.contains("fabric")
        case .quilt: return loaders.contains("quilt") || loaders.contains("fabric")
        case .forge: return loaders.contains("forge")
        case .neoforge: return loaders.contains("neoforge")
        case .vanilla: return false
        }
    }

    /// 不兼容时的人读说明（兼容则 nil）。
    public static func incompatibilityHint(versionLoaders: [String], instance: ModrinthLoaderKind) -> String? {
        guard !isCompatible(versionLoaders: versionLoaders, instance: instance) else { return nil }
        let loaders = Set(versionLoaders.map { $0.lowercased() }).intersection(modLoaderNames)
        let declared = loaders.sorted().joined(separator: " / ")
        if instance == .vanilla {
            return "该文件需要 \(declared) 加载器，目标实例是原版，游戏内不会加载。请先安装对应加载器的实例。"
        }
        return "该文件声明的加载器（\(declared)）与目标实例（\(instance.title)）不匹配，装进去也可能无法加载。"
    }

    /// 从实例 id 判断（fabric-loader-… / quilt-loader-… / neoforge-…）。
    private static func kindFromName(_ name: String) -> ModrinthLoaderKind? {
        let lower = name.lowercased()
        if lower.contains("neoforge") { return .neoforge }
        if lower.contains("fabric") { return .fabric }
        if lower.contains("quilt") { return .quilt }
        if lower.contains("forge") { return .forge }
        return nil
    }

    /// 从主类判断（Fabric 用 KnotClient、Quilt 用 QuiltLauncher、Forge 用 bootstrap）。
    private static func kindFromMainClass(_ mainClass: String?) -> ModrinthLoaderKind? {
        guard let mainClass else { return nil }
        let lower = mainClass.lowercased()
        if lower.contains("neoforge") { return .neoforge }
        if lower.contains("fabric") || lower.contains("knot") { return .fabric }
        if lower.contains("quilt") { return .quilt }
        if lower.contains("forge") { return .forge }
        return nil
    }
}

// MARK: - 整合包清单错误

/// `.mrpack` 清单错误：给出真实原因，不假装安装成功。
public enum ModpackIndexError: LocalizedError, Equatable {
    case invalidJSON(String)
    case unsupportedFormat(Int)
    case notMinecraft(String)
    case missingIndex
    case missingDependencies
    case unsupportedLoader(String)
    case emptyFiles
    case missingFileDownload([String])
    case unsafeArchiveEntry(String)
    case extraction(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let message): return "整合包清单解析失败：\(message)"
        case .unsupportedFormat(let version): return "不支持的整合包格式版本：\(version)"
        case .notMinecraft(let game): return "不是 Minecraft 整合包（game = \(game)）"
        case .missingIndex: return "压缩包里没有 modrinth.index.json，不是 Modrinth 整合包"
        case .missingDependencies: return "整合包清单缺少 dependencies（无法确定基础版本）"
        case .unsupportedLoader(let name): return "该整合包使用 \(name) 加载器，当前启动器只支持 Fabric / Quilt / 原版整合包"
        case .emptyFiles: return "整合包清单里没有任何文件"
        case .missingFileDownload(let paths):
            let preview = paths.prefix(3).joined(separator: "、")
            let suffix = paths.count > 3 ? " 等 \(paths.count) 个文件" : ""
            return "整合包里有文件缺少下载地址（\(preview)\(suffix)），安装会不完整，已停止。"
        case .unsafeArchiveEntry(let entry): return "压缩包内包含不安全路径：\(entry)（已阻止 zip-slip）"
        case .extraction(let message): return "解压整合包失败：\(message)"
        }
    }
}
