import Foundation

// MARK: - LauncherALL DSH 整合包（.dshpack）

/// LauncherALL 私有 DSH 整合包格式（v1，zip 容器）：
/// ```
/// manifest.json
/// payload/runtime/...        # bundled 模式：DSH 本体的 node_modules
/// payload/plugins/*.tgz      # 可选：插件 npm tarball（离线安装用）
/// ```
public enum DSHPackFormat {
    /// 文件扩展名（不包含点）。
    public static let fileExtension = "dshpack"
    /// manifest 里的格式标识。
    public static let identifier = "launcherall.dshpack"
    public static let formatVersion = 1
    /// manifest 文件名。
    public static let manifestName = "manifest.json"
    /// 运行时载荷目录。
    public static let runtimePath = "payload/runtime"
    /// 插件载荷目录。
    public static let pluginsPath = "payload/plugins"
}

/// 整合包内记录的一个插件。
public struct DSHPackPlugin: Codable, Hashable, Sendable, Identifiable {
    /// 依赖名（pnpm dependency key）。
    public let name: String
    /// 安装标识：npm 包名+版本（`pkg@1.2.3`）或 github/git spec。
    public let spec: String
    /// 精确安装版本（能从 profile 读到才有）。
    public let version: String?
    /// 包内离线载荷相对路径（如 `payload/plugins/pkg-1.2.3.tgz`）。
    public let payload: String?

    public var id: String { name }

    public init(name: String, spec: String, version: String? = nil, payload: String? = nil) {
        self.name = name
        self.spec = spec
        self.version = version
        self.payload = payload
    }
}

/// 运行时打包方式。
public enum DSHPackRuntimeMode: String, Codable, Sendable, CaseIterable {
    /// 把 DSH 本体一起打进包（离线可用，体积大）。
    case bundled
    /// 只记录版本号，导入时从 npm 安装（体积小，需要网络）。
    case online

    public var title: String {
        switch self {
        case .bundled: return "完整包（包含 DSH 本体，离线可用）"
        case .online: return "轻量包（导入时从 npm 下载 DSH）"
        }
    }
}

/// `manifest.json` 结构。
public struct DSHPackManifest: Codable, Hashable, Sendable {
    public let format: String
    public let formatVersion: Int
    public let name: String
    public let version: String
    public let description: String
    public let author: String
    public let createdAt: Date
    /// 打包时使用的 `@deepseek-ai/dsh` 版本。
    public let dshVersion: String
    public let runtime: DSHPackRuntimeMode
    public let plugins: [DSHPackPlugin]
    /// 可选：启动端口等偏好（导入时空的字段忽略）。
    public let settings: [String: String]?

    public init(
        name: String,
        version: String,
        description: String = "",
        author: String = "",
        createdAt: Date = Date(),
        dshVersion: String,
        runtime: DSHPackRuntimeMode,
        plugins: [DSHPackPlugin],
        settings: [String: String]? = nil
    ) {
        self.format = DSHPackFormat.identifier
        self.formatVersion = DSHPackFormat.formatVersion
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.createdAt = createdAt
        self.dshVersion = dshVersion
        self.runtime = runtime
        self.plugins = plugins
        self.settings = settings
    }
}

/// 整合包操作阶段。
public enum DSHPackPhase: Equatable, Sendable {
    case preparing
    case packingRuntime
    case packingPlugins
    case compressing
    case reading
    case extractingRuntime
    case installingRuntime
    case installingPlugins
    case finishing

    public var title: String {
        switch self {
        case .preparing: return "准备整合包…"
        case .packingRuntime: return "打包 DSH 本体…"
        case .packingPlugins: return "打包插件…"
        case .compressing: return "压缩整合包…"
        case .reading: return "读取整合包…"
        case .extractingRuntime: return "解压 DSH 本体…"
        case .installingRuntime: return "安装 DSH 运行时…"
        case .installingPlugins: return "安装插件…"
        case .finishing: return "完成…"
        }
    }
}

/// 整合包操作状态。
public enum DSHPackState: Equatable, Sendable {
    case idle
    case exporting(name: String, phase: DSHPackPhase, progress: Double)
    case importing(name: String, phase: DSHPackPhase, progress: Double)
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .exporting, .importing: return true
        default: return false
        }
    }
}

// MARK: - 错误

public enum DSHPackError: LocalizedError, Equatable {
    case invalidPackage(String)
    case unsupportedVersion(Int)
    case missingManifest
    case missingRuntime
    case unsafePath(String)
    case exportFailed(String)
    case importFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidPackage(let detail): return "不是有效的 DSH 整合包：\(detail)"
        case .unsupportedVersion(let version): return "整合包格式版本 \(version) 不受支持"
        case .missingManifest: return "整合包缺少 manifest.json"
        case .missingRuntime: return "整合包缺少 DSH 运行时，且未提供可下载的版本号"
        case .unsafePath(let path): return "整合包内包含不安全的路径：\(path)"
        case .exportFailed(let detail): return "导出整合包失败：\(detail)"
        case .importFailed(let detail): return "导入整合包失败：\(detail)"
        case .cancelled: return "操作已取消"
        }
    }
}
