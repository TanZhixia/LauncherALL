import Foundation

// MARK: - 认证端点与常量

/// 微软正版登录用到的端点与常量（设备码流，公开客户端，无需 client secret）。
/// 与 PCL.Swift 的 MicrosoftAuthService 保持同一套流程：device code → OAuth token →
/// Xbox Live → XSTS → Minecraft services → profile。
public enum MicrosoftAuthEndpoints {
    /// OAuth 设备码申请（consumers 租户：支持个人微软账户）。
    public static let deviceCode = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")!
    /// OAuth 令牌端点（设备码轮询 / 刷新令牌共用）。
    public static let token = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!
    public static let xboxUserAuth = URL(string: "https://user.auth.xboxlive.com/user/authenticate")!
    public static let xstsAuthorize = URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!
    public static let minecraftLogin = URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!
    public static let minecraftProfile = URL(string: "https://api.minecraftservices.com/minecraft/profile")!

    /// Xbox Live + 离线刷新令牌。
    public static let scope = "XboxLive.signin offline_access"
    /// 公开客户端 ID（设备码流不需要 secret）。
    public static let defaultClientID = "dd28b3f2-1db5-49b7-9228-99fdb46dfaca"

    /// 用户在浏览器中输入验证码的地址。
    public static let verificationURL = URL(string: "https://www.microsoft.com/link")!
    /// 没有 Xbox 账户时的帮助链接。
    public static let noXboxAccountHelp = URL(string: "https://www.minecraft.net/msaprofile/mygames/editprofile")!
    /// 未成年账户帮助链接。
    public static let childAccountHelp = URL(
        string: "https://support.microsoft.com/account-billing/837badbc-999e-54d2-2617-d19206b9540a"
    )!
}

// MARK: - 设备码

/// 设备码申请响应。
public struct MicrosoftDeviceCode: Decodable, Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: String
    public let expiresIn: Int
    public let interval: Int
    public let message: String?

    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
        case message
    }

    public init(deviceCode: String, userCode: String, verificationURI: String, expiresIn: Int, interval: Int, message: String? = nil) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.expiresIn = expiresIn
        self.interval = interval
        self.message = message
    }

    /// 浏览器地址（必须是绝对 http(s) 地址，否则回退官方入口）。
    public var verificationURL: URL {
        guard let url = URL(string: verificationURI),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else {
            return MicrosoftAuthEndpoints.verificationURL
        }
        return url
    }

    /// 轮询间隔（秒），至少 1 秒。
    public var pollInterval: Int { max(1, interval) }

    public func expiresAt(from date: Date = Date()) -> Date {
        date.addingTimeInterval(TimeInterval(max(60, expiresIn)))
    }
}

// MARK: - OAuth 令牌

/// OAuth 令牌响应（设备码轮询成功 / 刷新成功）。
public struct MicrosoftToken: Decodable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    public let scope: String?
    public let tokenType: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }

    public init(accessToken: String, refreshToken: String?, expiresIn: Int, scope: String? = nil, tokenType: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.scope = scope
        self.tokenType = tokenType
    }

    public func expiresAt(from date: Date = Date()) -> Date {
        date.addingTimeInterval(TimeInterval(max(60, expiresIn)))
    }
}

/// OAuth 错误响应（设备码轮询的 pending / 取消 / 过期等也走这里）。
struct MicrosoftOAuthFailure: Decodable, Sendable, Equatable {
    let error: String
    let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

/// 设备码轮询的单次结果。
public enum MicrosoftDevicePollResult: Sendable, Equatable {
    /// 用户还没完成授权，继续等。
    case pending
    /// 轮询太快，需要降速。
    case slowDown
    /// 用户拒绝授权。
    case denied
    /// 设备码过期。
    case expired
    /// 拿到令牌。
    case token(MicrosoftToken)
}

// MARK: - Xbox / Minecraft

/// Xbox Live / XSTS 返回的令牌与用户哈希。
public struct XboxLiveToken: Sendable, Equatable {
    public let token: String
    public let userHash: String
    public let xuid: String?

    public init(token: String, userHash: String, xuid: String? = nil) {
        self.token = token
        self.userHash = userHash
        self.xuid = xuid
    }

    /// XSTS 授权后用于 Minecraft 登录的 identityToken。
    public var identityToken: String { "XBL3.0 x=\(userHash);\(token)" }
}

/// Minecraft services 登录响应。
public struct MinecraftLoginResult: Decodable, Sendable, Equatable {
    public let accessToken: String
    public let expiresIn: Int
    public let username: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case username
    }

    public init(accessToken: String, expiresIn: Int, username: String? = nil) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.username = username
    }

    public func expiresAt(from date: Date = Date()) -> Date {
        date.addingTimeInterval(TimeInterval(max(60, expiresIn)))
    }
}

/// Minecraft 档案（正版玩家名 / UUID / 皮肤）。
public struct MinecraftProfile: Decodable, Sendable, Equatable {
    public struct Texture: Decodable, Sendable, Equatable {
        public let id: String?
        public let state: String?
        public let url: String?
        public let alias: String?
    }

    public let id: String
    public let name: String
    public let skins: [Texture]?
    public let capes: [Texture]?

    public init(id: String, name: String, skins: [Texture]? = nil, capes: [Texture]? = nil) {
        self.id = id
        self.name = name
        self.skins = skins
        self.capes = capes
    }

    /// 当前皮肤地址（优先 ACTIVE）。
    public var skinURL: String? {
        let active = skins?.first { $0.state == "ACTIVE" && $0.url != nil }
        return active?.url ?? skins?.first { $0.url != nil }?.url
    }

    /// 带连字符的 UUID 展示形式。
    public var formattedUUID: String {
        guard id.count == 32 else { return id }
        let text = id
        func slice(_ start: Int, _ end: Int) -> String {
            let lower = text.index(text.startIndex, offsetBy: start)
            let upper = text.index(text.startIndex, offsetBy: end)
            return String(text[lower..<upper])
        }
        return [slice(0, 8), slice(8, 12), slice(12, 16), slice(16, 20), slice(20, 32)].joined(separator: "-")
    }
}

// MARK: - 错误

/// 正版登录错误：都带可直接展示给用户的中文文案。
public enum MicrosoftAuthError: LocalizedError, Equatable {
    case network(String)
    case invalidResponse(String)
    case codeExpired
    case authorizationDenied
    /// 微软账户没有关联 Xbox 账户（XErr 2148916233）。
    case noXboxAccount
    /// 未成年账户（XErr 2148916238）。
    case childAccount
    /// Xbox Live 在账户所在地区不可用（XErr 2148916235）。
    case regionUnavailable
    /// 其他 Xbox 错误码。
    case xboxError(UInt32)
    /// 账户没有 Minecraft: Java 版所有权（profile 404）。
    case noMinecraftOwnership
    /// 刷新令牌失效，需要重新登录。
    case invalidRefreshToken
    case cancelled
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .network(let message):
            return "网络错误：\(message)"
        case .invalidResponse(let message):
            return "认证响应无效：\(message)"
        case .codeExpired:
            return "验证码已过期，请重新发起登录"
        case .authorizationDenied:
            return "授权被拒绝，登录已取消"
        case .noXboxAccount:
            return "该微软账户没有关联 Xbox 账户，请先关联 Xbox 账户后重试"
        case .childAccount:
            return "当前账户为未成年账户，无法通过 Xbox Live 认证；请由家庭管理员调整账户年龄后重试"
        case .regionUnavailable:
            return "Xbox Live 在账户所在地区不可用"
        case .xboxError(let code):
            return "Xbox Live 认证失败（错误码 \(code)）"
        case .noMinecraftOwnership:
            return "该微软账户没有 Minecraft: Java 版所有权，无法用于正版登录"
        case .invalidRefreshToken:
            return "登录状态已过期，请重新登录正版账户"
        case .cancelled:
            return "登录已取消"
        case .unexpected(let message):
            return "登录失败：\(message)"
        }
    }

    /// 相关帮助链接（展示在登录失败提示里）。
    public var helpURL: URL? {
        switch self {
        case .noXboxAccount: return MicrosoftAuthEndpoints.noXboxAccountHelp
        case .childAccount: return MicrosoftAuthEndpoints.childAccountHelp
        default: return nil
        }
    }

    /// XErr → 语义化错误。
    public static func fromXboxErrorCode(_ code: UInt32) -> MicrosoftAuthError {
        switch code {
        case 2148916233: return .noXboxAccount
        case 2148916235: return .regionUnavailable
        case 2148916238: return .childAccount
        default: return .xboxError(code)
        }
    }
}

// MARK: - 会话

/// 一次完整的正版登录会话（持久化到 Keychain / 文件回退）。
public struct MinecraftAuthSession: Codable, Sendable, Equatable {
    public var playerName: String
    /// 无连字符的 32 位 UUID。
    public var uuid: String
    public var minecraftAccessToken: String
    public var minecraftExpiresAt: Date
    public var microsoftAccessToken: String
    public var microsoftExpiresAt: Date
    public var microsoftRefreshToken: String
    public var xuid: String?
    public var skinURL: String?
    public var updatedAt: Date

    public init(
        playerName: String,
        uuid: String,
        minecraftAccessToken: String,
        minecraftExpiresAt: Date,
        microsoftAccessToken: String,
        microsoftExpiresAt: Date,
        microsoftRefreshToken: String,
        xuid: String? = nil,
        skinURL: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.playerName = playerName
        self.uuid = uuid
        self.minecraftAccessToken = minecraftAccessToken
        self.minecraftExpiresAt = minecraftExpiresAt
        self.microsoftAccessToken = microsoftAccessToken
        self.microsoftExpiresAt = microsoftExpiresAt
        self.microsoftRefreshToken = microsoftRefreshToken
        self.xuid = xuid
        self.skinURL = skinURL
        self.updatedAt = updatedAt
    }

    /// 提前 5 分钟视为需要刷新，避免启动时刚好过期。
    public static let refreshLeeway: TimeInterval = 5 * 60

    /// 是否需要刷新（Minecraft 或微软令牌临近过期）。
    public func needsRefresh(at date: Date = Date()) -> Bool {
        date >= minecraftExpiresAt.addingTimeInterval(-Self.refreshLeeway)
            || date >= microsoftExpiresAt.addingTimeInterval(-Self.refreshLeeway)
    }

    /// 带连字符的 UUID。
    public var formattedUUID: String {
        MinecraftProfile(id: uuid, name: playerName).formattedUUID
    }
}

// MARK: - 账户记录

/// 账户元数据（可持久化到 UserDefaults；令牌不在这里）。
public struct AuthAccountRecord: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case offline
        case microsoft
    }

    public let id: String
    public var kind: Kind
    public var name: String
    /// 带连字符的 UUID（离线账户为离线算法推导值）。
    public var uuid: String
    public var addedAt: Date
    public var lastUsedAt: Date?
    public var skinURL: String?

    public init(
        id: String,
        kind: Kind,
        name: String,
        uuid: String,
        addedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        skinURL: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.uuid = uuid
        self.addedAt = addedAt
        self.lastUsedAt = lastUsedAt
        self.skinURL = skinURL
    }

    /// 离线账户的固定 id。
    public static let offlineID = "offline"

    public var isMicrosoft: Bool { kind == .microsoft }
}

// MARK: - 启动用账户

/// 传给启动命令的账户快照（离线 / 正版统一结构）。
public struct LaunchAccount: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case offline
        case microsoft
    }

    public let kind: Kind
    public let name: String
    /// 带连字符的 UUID。
    public let uuid: String
    public let accessToken: String
    public let xuid: String?
    public let userType: String
    public let userProperties: String

    public init(
        kind: Kind,
        name: String,
        uuid: String,
        accessToken: String,
        xuid: String? = nil,
        userType: String,
        userProperties: String = "{}"
    ) {
        self.kind = kind
        self.name = name
        self.uuid = uuid
        self.accessToken = accessToken
        self.xuid = xuid
        self.userType = userType
        self.userProperties = userProperties
    }

    /// 离线账户：UUID 由玩家名按离线算法推导，accessToken 为 "0"。
    public static func offline(name: String) -> LaunchAccount {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playerName = trimmed.isEmpty ? "Steve" : trimmed
        return LaunchAccount(
            kind: .offline,
            name: playerName,
            uuid: LaunchCommandBuilder.offlineUUID(for: playerName),
            accessToken: "0",
            xuid: nil,
            userType: "legacy"
        )
    }

    /// 正版账户：使用微软登录得到的 Minecraft 令牌与档案 UUID。
    public static func microsoft(session: MinecraftAuthSession) -> LaunchAccount {
        LaunchAccount(
            kind: .microsoft,
            name: session.playerName,
            uuid: session.formattedUUID,
            accessToken: session.minecraftAccessToken,
            xuid: session.xuid,
            userType: "msa"
        )
    }

    /// 传给启动命令的 UUID（正版使用无连字符形式）。
    public var commandUUID: String {
        kind == .microsoft ? uuid.replacingOccurrences(of: "-", with: "").lowercased() : uuid
    }
}
