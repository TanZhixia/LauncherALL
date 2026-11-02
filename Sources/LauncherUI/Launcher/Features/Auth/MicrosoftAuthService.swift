import Foundation

// MARK: - 认证协议

/// 认证服务抽象：便于账户中心注入测试替身，不依赖真实网络。
public protocol MicrosoftAuthenticating: Sendable {
    func requestDeviceCode() async throws -> MicrosoftDeviceCode
    func pollDeviceToken(_ code: MicrosoftDeviceCode) async throws -> MicrosoftToken
    func completeLogin(with token: MicrosoftToken) async throws -> MinecraftAuthSession
    func refresh(session: MinecraftAuthSession) async throws -> MinecraftAuthSession
}

// MARK: - 微软正版认证服务

/// 设备码流（device code）完整认证链路：
/// 申请验证码 → 轮询 OAuth 令牌 → Xbox Live 用户认证 → XSTS 授权 →
/// Minecraft services 登录 → 拉取正版档案。
/// 流程与 PCL.Swift 的 `MicrosoftAuthService` 一致，纯 Foundation 实现，网络层可注入便于测试。
public final class MicrosoftAuthService: MicrosoftAuthenticating, @unchecked Sendable {
    private let session: URLSession
    private let clientID: String

    public init(session: URLSession = .shared, clientID: String = MicrosoftAuthEndpoints.defaultClientID) {
        self.session = session
        self.clientID = clientID
    }

    // MARK: 1. 设备码

    /// 申请设备码（用户看到 `userCode`，去浏览器输入）。
    public func requestDeviceCode() async throws -> MicrosoftDeviceCode {
        let request = Self.deviceCodeRequest(clientID: clientID)
        let (data, response) = try await send(request)
        try Self.ensureSuccess(response, data: data, context: "申请验证码")
        do {
            return try JSONDecoder().decode(MicrosoftDeviceCode.self, from: data)
        } catch {
            throw MicrosoftAuthError.invalidResponse("无法解析设备码响应：\(error.localizedDescription)")
        }
    }

    // MARK: 2. 轮询令牌

    /// 轮询设备码直到用户完成授权 / 过期 / 被拒绝。
    /// - Note: 每次轮询间隔按服务端返回的 `interval`，`slow_down` 时自动加 5 秒。
    public func pollDeviceToken(_ code: MicrosoftDeviceCode) async throws -> MicrosoftToken {
        let deadline = code.expiresAt()
        var interval = code.pollInterval
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            try Task.checkCancellation()

            switch try await pollDeviceTokenOnce(deviceCode: code.deviceCode) {
            case .token(let token):
                return token
            case .pending:
                continue
            case .slowDown:
                interval += 5
                continue
            case .denied:
                throw MicrosoftAuthError.authorizationDenied
            case .expired:
                throw MicrosoftAuthError.codeExpired
            }
        }
        throw MicrosoftAuthError.codeExpired
    }

    /// 单次轮询（测试用）。
    public func pollDeviceTokenOnce(deviceCode: String) async throws -> MicrosoftDevicePollResult {
        let request = Self.deviceTokenRequest(clientID: clientID, deviceCode: deviceCode)
        let (data, response) = try await send(request)
        if let token = try? JSONDecoder().decode(MicrosoftToken.self, from: data), token.accessToken.isEmpty == false {
            return .token(token)
        }
        if let failure = try? JSONDecoder().decode(MicrosoftOAuthFailure.self, from: data) {
            switch failure.error {
            case "authorization_pending": return .pending
            case "slow_down": return .slowDown
            case "expired_token": return .expired
            case "authorization_declined", "access_denied": return .denied
            case "bad_verification_code":
                throw MicrosoftAuthError.invalidResponse("验证码无效")
            default:
                throw MicrosoftAuthError.unexpected(failure.errorDescription ?? failure.error)
            }
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MicrosoftAuthError.network("HTTP \(http.statusCode)")
        }
        throw MicrosoftAuthError.invalidResponse("无法解析令牌响应")
    }

    // MARK: 3. 后续链路

    /// 用 OAuth 令牌完成 Xbox / XSTS / Minecraft 登录并拉取档案。
    public func completeLogin(with token: MicrosoftToken) async throws -> MinecraftAuthSession {
        let xbl = try await authenticateXboxLive(microsoftAccessToken: token.accessToken)
        let xsts = try await authorizeXSTS(xblToken: xbl.token)
        let login = try await loginMinecraft(identityToken: xsts.identityToken)
        let profile = try await fetchProfile(accessToken: login.accessToken)
        guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
            throw MicrosoftAuthError.invalidResponse("响应中没有 refresh_token")
        }

        return MinecraftAuthSession(
            playerName: profile.name,
            uuid: profile.id.lowercased(),
            minecraftAccessToken: login.accessToken,
            minecraftExpiresAt: login.expiresAt(),
            microsoftAccessToken: token.accessToken,
            microsoftExpiresAt: token.expiresAt(),
            microsoftRefreshToken: refreshToken,
            xuid: xsts.xuid ?? xbl.xuid,
            skinURL: profile.skinURL,
            updatedAt: Date()
        )
    }

    /// 用刷新令牌续期（不改账户身份，只换新令牌）。
    public func refresh(session: MinecraftAuthSession) async throws -> MinecraftAuthSession {
        let request = Self.refreshTokenRequest(clientID: clientID, refreshToken: session.microsoftRefreshToken)
        let (data, response) = try await send(request)
        if let failure = try? JSONDecoder().decode(MicrosoftOAuthFailure.self, from: data),
           failure.error == "invalid_grant" || failure.error == "interaction_required" {
            throw MicrosoftAuthError.invalidRefreshToken
        }
        try Self.ensureSuccess(response, data: data, context: "刷新登录")
        guard let token = try? JSONDecoder().decode(MicrosoftToken.self, from: data) else {
            throw MicrosoftAuthError.invalidResponse("无法解析刷新响应")
        }
        // completeLogin 已要求响应里带 refresh_token（offline_access），这里直接返回新会话
        return try await completeLogin(with: token)
    }

    /// Xbox Live 用户认证。
    public func authenticateXboxLive(microsoftAccessToken: String) async throws -> XboxLiveToken {
        let request = Self.xboxAuthRequest(microsoftAccessToken: microsoftAccessToken)
        let (data, response) = try await send(request)
        if let error = Self.xboxError(from: data) {
            throw error
        }
        try Self.ensureSuccess(response, data: data, context: "Xbox Live 认证")
        return try Self.parseXboxToken(data, context: "Xbox Live 认证")
    }

    /// XSTS 授权（拿 Minecraft 的 RelyingParty 令牌）。
    public func authorizeXSTS(xblToken: String) async throws -> XboxLiveToken {
        let request = Self.xstsRequest(xblToken: xblToken)
        let (data, response) = try await send(request)
        if let error = Self.xboxError(from: data) {
            throw error
        }
        try Self.ensureSuccess(response, data: data, context: "XSTS 授权")
        return try Self.parseXboxToken(data, context: "XSTS 授权")
    }

    /// Minecraft services 登录（拿 Minecraft access_token）。
    public func loginMinecraft(identityToken: String) async throws -> MinecraftLoginResult {
        let request = Self.minecraftLoginRequest(identityToken: identityToken)
        let (data, response) = try await send(request)
        try Self.ensureSuccess(response, data: data, context: "Minecraft 登录")
        do {
            return try JSONDecoder().decode(MinecraftLoginResult.self, from: data)
        } catch {
            throw MicrosoftAuthError.invalidResponse("无法解析 Minecraft 登录响应：\(error.localizedDescription)")
        }
    }

    /// 拉取正版档案（404 = 没有游戏所有权）。
    public func fetchProfile(accessToken: String) async throws -> MinecraftProfile {
        let request = Self.profileRequest(accessToken: accessToken)
        let (data, response) = try await send(request)
        if let profile = try? JSONDecoder().decode(MinecraftProfile.self, from: data),
           profile.id.isEmpty == false {
            return profile
        }
        struct ProfileError: Decodable {
            let error: String?
            let errorType: String?
            let errorMessage: String?
        }
        if let payload = try? JSONDecoder().decode(ProfileError.self, from: data) {
            let code = (payload.error ?? payload.errorType ?? "").uppercased()
            if code.contains("NOT_FOUND") || (payload.errorMessage ?? "").localizedCaseInsensitiveContains("not found") {
                throw MicrosoftAuthError.noMinecraftOwnership
            }
        }
        let message = String(data: data, encoding: .utf8) ?? ""
        if message.contains("NOT_FOUND") || message.contains("not found") {
            throw MicrosoftAuthError.noMinecraftOwnership
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw MicrosoftAuthError.invalidRefreshToken
        }
        try Self.ensureSuccess(response, data: data, context: "获取正版档案")
        throw MicrosoftAuthError.invalidResponse("无法解析正版档案")
    }

    // MARK: - 请求构造（纯函数，便于单测）

    static func deviceCodeRequest(clientID: String) -> URLRequest {
        formRequest(
            url: MicrosoftAuthEndpoints.deviceCode,
            fields: ["client_id": clientID, "scope": MicrosoftAuthEndpoints.scope]
        )
    }

    static func deviceTokenRequest(clientID: String, deviceCode: String) -> URLRequest {
        formRequest(
            url: MicrosoftAuthEndpoints.token,
            fields: [
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": clientID,
                "device_code": deviceCode
            ]
        )
    }

    static func refreshTokenRequest(clientID: String, refreshToken: String) -> URLRequest {
        formRequest(
            url: MicrosoftAuthEndpoints.token,
            fields: [
                "grant_type": "refresh_token",
                "client_id": clientID,
                "refresh_token": refreshToken,
                "scope": MicrosoftAuthEndpoints.scope
            ]
        )
    }

    static func xboxAuthRequest(microsoftAccessToken: String) -> URLRequest {
        jsonRequest(
            url: MicrosoftAuthEndpoints.xboxUserAuth,
            body: [
                "Properties": [
                    "AuthMethod": "RPS",
                    "SiteName": "user.auth.xboxlive.com",
                    "RpsTicket": "d=\(microsoftAccessToken)"
                ],
                "RelyingParty": "http://auth.xboxlive.com",
                "TokenType": "JWT"
            ]
        )
    }

    static func xstsRequest(xblToken: String) -> URLRequest {
        jsonRequest(
            url: MicrosoftAuthEndpoints.xstsAuthorize,
            body: [
                "Properties": [
                    "SandboxId": "RETAIL",
                    "UserTokens": [xblToken]
                ],
                "RelyingParty": "rp://api.minecraftservices.com/",
                "TokenType": "JWT"
            ]
        )
    }

    static func minecraftLoginRequest(identityToken: String) -> URLRequest {
        jsonRequest(
            url: MicrosoftAuthEndpoints.minecraftLogin,
            body: ["identityToken": identityToken]
        )
    }

    static func profileRequest(accessToken: String) -> URLRequest {
        var request = URLRequest(url: MicrosoftAuthEndpoints.minecraftProfile)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        return request
    }

    // MARK: - 解析辅助

    private struct XboxTokenPayload: Decodable {
        struct DisplayClaims: Decodable {
            struct XUI: Decodable {
                let uhs: String
                let xid: String?
            }
            let xui: [XUI]
        }
        let token: String
        let displayClaims: DisplayClaims

        private enum CodingKeys: String, CodingKey {
            case token = "Token"
            case displayClaims = "DisplayClaims"
        }
    }

    static func parseXboxToken(_ data: Data, context: String) throws -> XboxLiveToken {
        guard let payload = try? JSONDecoder().decode(XboxTokenPayload.self, from: data),
              let first = payload.displayClaims.xui.first else {
            throw MicrosoftAuthError.invalidResponse("\(context)响应中没有 DisplayClaims.xui")
        }
        return XboxLiveToken(token: payload.token, userHash: first.uhs, xuid: first.xid)
    }

    /// XSTS 失败时返回 HTTP 401 + `XErr`，这里优先解析错误码。
    static func xboxError(from data: Data) -> MicrosoftAuthError? {
        struct Payload: Decodable {
            let xerr: UInt32?
            let message: String?
            private enum CodingKeys: String, CodingKey {
                case xerr = "XErr"
                case message = "Message"
            }
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data), let code = payload.xerr else {
            return nil
        }
        return MicrosoftAuthError.fromXboxErrorCode(code)
    }

    // MARK: - HTTP

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw MicrosoftAuthError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw MicrosoftAuthError.cancelled
        } catch {
            throw MicrosoftAuthError.network(error.localizedDescription)
        }
    }

    static func ensureSuccess(_ response: URLResponse, data: Data, context: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MicrosoftAuthError.invalidResponse("\(context)：没有 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            if message.contains("invalid_grant") {
                throw MicrosoftAuthError.invalidRefreshToken
            }
            throw MicrosoftAuthError.network("\(context)失败（HTTP \(http.statusCode)）")
        }
    }

    private static func formRequest(url: URL, fields: [String: String]) -> URLRequest {
        var components = URLComponents()
        components.queryItems = fields
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        let body = components.percentEncodedQuery ?? ""
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        return request
    }

    private static func jsonRequest(url: URL, body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Xbox Live / XSTS 要求携带契约版本，部分账号缺省会 400
        request.setValue("1", forHTTPHeaderField: "x-xbl-contract-version")
        request.timeoutInterval = 20
        return request
    }
}
