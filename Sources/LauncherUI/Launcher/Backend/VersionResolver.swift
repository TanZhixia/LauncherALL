import Foundation

/// 合并了 `inheritsFrom` 父版本之后的完整版本信息（Fabric / Forge 等加载器必需）。
public struct ResolvedVersion: Sendable {
    public let id: String
    public let type: String
    public let mainClass: String
    public let assets: String?
    public let assetIndex: VersionDetail.AssetIndex?
    public let clientDownload: VersionDetail.DownloadArtifact?
    public let libraries: [VersionDetail.Library]
    public let arguments: VersionDetail.Arguments?
    public let minecraftArguments: String?
    public let javaVersion: VersionDetail.JavaVersion?
    public let logging: VersionDetail.Logging?

    public var requiredJavaMajor: Int { javaVersion?.majorVersion ?? 21 }
}

public enum VersionResolveError: LocalizedError {
    case missingJSON(String)
    case tooDeep

    public var errorDescription: String? {
        switch self {
        case .missingJSON(let id): return "缺少版本 JSON：\(id)"
        case .tooDeep: return "版本继承层级过深（可能存在循环依赖）"
        }
    }
}

/// 解析版本 JSON，并沿 `inheritsFrom` 合并父版本（客户端 jar / 依赖库 / 参数 / 资源）。
public enum VersionResolver {
    public static func resolve(versionID: String, installation: MinecraftInstallation) throws -> ResolvedVersion {
        try resolve(versionID: versionID, installation: installation, depth: 0)
    }

    /// 异步解析：父版本 JSON 本地缺失时自动从 Mojang 拉取并落盘（加载器版本常见）。
    public static func resolveAsync(
        versionID: String,
        installation: MinecraftInstallation,
        manifestService: MojangManifestService? = nil,
        depth: Int = 0
    ) async throws -> ResolvedVersion {
        guard depth < 6 else { throw VersionResolveError.tooDeep }
        guard let url = jsonURL(for: versionID, installation: installation) else {
            throw VersionResolveError.missingJSON(versionID)
        }
        let detail = try MinecraftInstallation.VersionDetailLoader.load(from: url)
        if let parentID = detail.inheritsFrom {
            if jsonURL(for: parentID, installation: installation) == nil {
                let service = manifestService ?? MojangManifestService(installation: installation)
                let fetched = try await service.fetchVersionDetailData(parentID)
                // 父版本只缓存到 launcher-cache，避免污染用户的 versions 目录
                let parentsDirectory = installation.cacheDirectory.appendingPathComponent("parents", isDirectory: true)
                try FileManager.default.createDirectory(at: parentsDirectory, withIntermediateDirectories: true)
                try fetched.data.write(
                    to: parentsDirectory.appendingPathComponent("\(parentID).json"),
                    options: .atomic
                )
            }
            let parent = try await resolveAsync(
                versionID: parentID,
                installation: installation,
                manifestService: manifestService,
                depth: depth + 1
            )
            return ResolvedVersion(
                id: detail.id,
                type: detail.type ?? parent.type,
                mainClass: detail.mainClass ?? parent.mainClass,
                assets: detail.assets ?? parent.assets,
                assetIndex: detail.assetIndex ?? parent.assetIndex,
                clientDownload: detail.clientDownload ?? parent.clientDownload,
                libraries: parent.libraries + (detail.libraries ?? []),
                arguments: mergeArguments(parent: parent.arguments, child: detail.arguments),
                minecraftArguments: detail.minecraftArguments ?? parent.minecraftArguments,
                javaVersion: detail.javaVersion ?? parent.javaVersion,
                logging: detail.logging ?? parent.logging
            )
        }
        return try resolve(detail: detail, installation: installation, depth: depth)
    }

    /// 版本 JSON 位置：优先用户安装目录，其次 launcher-cache/parents 里的父版本缓存。
    public static func jsonURL(for versionID: String, installation: MinecraftInstallation) -> URL? {
        let installed = installation.versionJSONURL(versionID)
        if FileManager.default.fileExists(atPath: installed.path) { return installed }
        let cached = installation.cacheDirectory
            .appendingPathComponent("parents", isDirectory: true)
            .appendingPathComponent("\(versionID).json")
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        return nil
    }

    private static func resolve(versionID: String, installation: MinecraftInstallation, depth: Int) throws -> ResolvedVersion {
        guard depth < 6 else { throw VersionResolveError.tooDeep }
        guard let url = jsonURL(for: versionID, installation: installation) else {
            throw VersionResolveError.missingJSON(versionID)
        }
        let detail = try MinecraftInstallation.VersionDetailLoader.load(from: url)
        return try resolve(detail: detail, installation: installation, depth: depth)
    }

    private static func resolve(detail: VersionDetail, installation: MinecraftInstallation, depth: Int) throws -> ResolvedVersion {
        if let parentID = detail.inheritsFrom {
            let parent = try resolve(versionID: parentID, installation: installation, depth: depth + 1)
            return ResolvedVersion(
                id: detail.id,
                type: detail.type ?? parent.type,
                mainClass: detail.mainClass ?? parent.mainClass,
                assets: detail.assets ?? parent.assets,
                assetIndex: detail.assetIndex ?? parent.assetIndex,
                clientDownload: detail.clientDownload ?? parent.clientDownload,
                libraries: parent.libraries + (detail.libraries ?? []),
                arguments: mergeArguments(parent: parent.arguments, child: detail.arguments),
                minecraftArguments: detail.minecraftArguments ?? parent.minecraftArguments,
                javaVersion: detail.javaVersion ?? parent.javaVersion,
                logging: detail.logging ?? parent.logging
            )
        }
        return ResolvedVersion(
            id: detail.id,
            type: detail.type ?? "release",
            mainClass: detail.mainClass ?? "net.minecraft.client.main.Main",
            assets: detail.assets,
            assetIndex: detail.assetIndex,
            clientDownload: detail.clientDownload,
            libraries: detail.libraries ?? [],
            arguments: detail.arguments,
            minecraftArguments: detail.minecraftArguments,
            javaVersion: detail.javaVersion,
            logging: detail.logging
        )
    }

    /// 子版本参数追加在父版本之后（jvm 与 game 都保留）。
    static func mergeArguments(
        parent: VersionDetail.Arguments?,
        child: VersionDetail.Arguments?
    ) -> VersionDetail.Arguments? {
        switch (parent, child) {
        case (nil, nil): return nil
        case (let parent?, nil): return parent
        case (nil, let child?): return child
        case (let parent?, let child?):
            return VersionDetail.Arguments(
                game: parent.game + child.game,
                jvm: parent.jvm + child.jvm
            )
        }
    }
}
