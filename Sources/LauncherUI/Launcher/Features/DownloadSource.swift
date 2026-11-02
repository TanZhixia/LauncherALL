import Foundation

// MARK: - 下载源

/// 下载源：官方源直连 Mojang / 镜像源把 Mojang 域名重写到 BMCLAPI。
/// 安装器与版本清单都通过这里改写 URL，设置页里的「下载源」不再只是界面开关。
public enum DownloadSource: String, CaseIterable, Sendable {
    case official
    case mirror

    public var title: String {
        switch self {
        case .official: return "官方源（Mojang）"
        case .mirror: return "镜像源（BMCLAPI 加速）"
        }
    }

    public var detail: String {
        switch self {
        case .official: return "直连 Mojang，最稳妥，国内可能较慢"
        case .mirror: return "把 Mojang 下载域名重写到 BMCLAPI，国内通常更快"
        }
    }

    /// 当前设置里的下载源（读 LauncherSettings，设置页改动即时生效）。
    public static var active: DownloadSource {
        DownloadSource(rawValue: LauncherSettings.shared.downloadSource) ?? .official
    }

    /// BMCLAPI 镜像根地址。
    public static let mirrorRoot = "https://bmclapi2.bangbang93.com"

    /// 按当前下载源改写 URL（纯函数，便于测试）。
    public func rewrite(_ url: URL) -> URL {
        guard self == .mirror, let host = url.host?.lowercased() else { return url }

        // 版本清单 / 版本详情 / 资源索引 / 日志配置：只改写明确的下载域名，
        // 不用 hasSuffix("mojang.com") 以免误伤账户 / 其他服务域名。
        let mojangDownloadHosts: Set<String> = [
            "piston-meta.mojang.com",
            "launchermeta.mojang.com",
            "piston-data.mojang.com",
            "launcher.mojang.com",
            "files.mojang.com"
        ]
        if mojangDownloadHosts.contains(host) {
            return Self.replace(url, host: Self.mirrorRoot, pathPrefix: "")
        }

        // 资源文件：resources.download.minecraft.net/<ab>/<hash> → mirror/assets/<ab>/<hash>
        if host == "resources.download.minecraft.net" {
            return Self.replace(url, host: Self.mirrorRoot, pathPrefix: "/assets")
        }

        // 依赖库：libraries.minecraft.net/<maven path> → mirror/maven/<maven path>
        if host == "libraries.minecraft.net" {
            return Self.replace(url, host: Self.mirrorRoot, pathPrefix: "/maven")
        }

        return url
    }

    /// 组合镜像地址：保留原路径（可选加前缀）。
    public static func mirrorURL(for url: URL, pathPrefix: String = "") -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "https"
        components.host = URL(string: mirrorRoot)?.host
        components.path = pathPrefix + components.path
        return components.url
    }

    private static func replace(_ url: URL, host: String, pathPrefix: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let mirror = URL(string: host) else { return url }
        components.scheme = mirror.scheme
        components.host = mirror.host
        components.port = mirror.port
        components.path = pathPrefix + components.path
        return components.url ?? url
    }
}
