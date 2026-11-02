import XCTest
import Foundation
@testable import LauncherUI

/// 正版登录测试：请求构造、响应解码、错误映射、账户状态机、启动参数注入。
/// 全部离线：网络层用 stub，密钥用内存存储。
final class AuthFeatureTests: XCTestCase {

    // MARK: - 请求构造

    func testDeviceCodeRequest() throws {
        let request = MicrosoftAuthService.deviceCodeRequest(clientID: "client-123")
        XCTAssertEqual(request.url, MicrosoftAuthEndpoints.deviceCode)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("client_id=client-123"))
        XCTAssertTrue(body.contains("scope=XboxLive.signin%20offline_access"))
    }

    func testDeviceTokenAndRefreshRequests() {
        let poll = MicrosoftAuthService.deviceTokenRequest(clientID: "c", deviceCode: "dev-code")
        let pollBody = String(data: poll.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(pollBody.contains("grant_type=urn:ietf:params:oauth:grant-type:device_code"))
        XCTAssertTrue(pollBody.contains("device_code=dev-code"))

        let refresh = MicrosoftAuthService.refreshTokenRequest(clientID: "c", refreshToken: "refresh-token")
        let refreshBody = String(data: refresh.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(refreshBody.contains("grant_type=refresh_token"))
        XCTAssertTrue(refreshBody.contains("refresh_token=refresh-token"))
    }

    func testXboxAndXSTSRequests() throws {
        let xbl = MicrosoftAuthService.xboxAuthRequest(microsoftAccessToken: "msa-token")
        XCTAssertEqual(xbl.url, MicrosoftAuthEndpoints.xboxUserAuth)
        XCTAssertEqual(xbl.value(forHTTPHeaderField: "x-xbl-contract-version"), "1")
        let xblBody = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(xbl.httpBody)) as? [String: Any]
        )
        let properties = try XCTUnwrap(xblBody["Properties"] as? [String: Any])
        XCTAssertEqual(properties["RpsTicket"] as? String, "d=msa-token")
        XCTAssertEqual(properties["AuthMethod"] as? String, "RPS")
        XCTAssertEqual(xblBody["RelyingParty"] as? String, "http://auth.xboxlive.com")

        let xsts = MicrosoftAuthService.xstsRequest(xblToken: "xbl-token")
        XCTAssertEqual(xsts.url, MicrosoftAuthEndpoints.xstsAuthorize)
        XCTAssertEqual(xsts.value(forHTTPHeaderField: "x-xbl-contract-version"), "1")
        let xstsBody = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(xsts.httpBody)) as? [String: Any]
        )
        let xstsProperties = try XCTUnwrap(xstsBody["Properties"] as? [String: Any])
        XCTAssertEqual(xstsProperties["SandboxId"] as? String, "RETAIL")
        XCTAssertEqual(xstsProperties["UserTokens"] as? [String], ["xbl-token"])
        XCTAssertEqual(xstsBody["RelyingParty"] as? String, "rp://api.minecraftservices.com/")
    }

    func testMinecraftLoginAndProfileRequests() throws {
        let login = MicrosoftAuthService.minecraftLoginRequest(identityToken: "XBL3.0 x=uhs;token")
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(login.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(body["identityToken"] as? String, "XBL3.0 x=uhs;token")

        let profile = MicrosoftAuthService.profileRequest(accessToken: "mc-token")
        XCTAssertEqual(profile.url, MicrosoftAuthEndpoints.minecraftProfile)
        XCTAssertEqual(profile.value(forHTTPHeaderField: "Authorization"), "Bearer mc-token")
    }

    // MARK: - 解码

    func testDeviceCodeDecoding() throws {
        let json = """
        {
          "device_code": "dev",
          "user_code": "ABCD-1234",
          "verification_uri": "https://microsoft.com/link",
          "expires_in": 900,
          "interval": 5,
          "message": "请访问…"
        }
        """
        let code = try JSONDecoder().decode(MicrosoftDeviceCode.self, from: Data(json.utf8))
        XCTAssertEqual(code.userCode, "ABCD-1234")
        XCTAssertEqual(code.pollInterval, 5)
        XCTAssertEqual(code.verificationURL.absoluteString, "https://microsoft.com/link")
        XCTAssertEqual(code.expiresAt(from: Date(timeIntervalSince1970: 0)), Date(timeIntervalSince1970: 900))
    }

    func testDeviceCodeVerificationURLFallback() throws {
        let json = """
        {"device_code":"d","user_code":"u","verification_uri":"not a url","expires_in":600,"interval":0}
        """
        let code = try JSONDecoder().decode(MicrosoftDeviceCode.self, from: Data(json.utf8))
        XCTAssertEqual(code.verificationURL, MicrosoftAuthEndpoints.verificationURL)
        XCTAssertEqual(code.pollInterval, 1, "interval 为 0 时至少 1 秒，避免忙轮询")
    }

    func testTokenAndProfileDecoding() throws {
        let tokenJSON = """
        {"access_token":"msa","refresh_token":"refresh","expires_in":3600,"token_type":"Bearer","scope":"x"}
        """
        let token = try JSONDecoder().decode(MicrosoftToken.self, from: Data(tokenJSON.utf8))
        XCTAssertEqual(token.accessToken, "msa")
        XCTAssertEqual(token.refreshToken, "refresh")

        let profileJSON = """
        {
          "id": "069a79f4-44e9-4726-a5be-fca90e38aaf5",
          "name": "Notch",
          "skins": [
            {"id":"x","state":"ACTIVE","url":"https://textures.minecraft.net/texture/abc"}
          ],
          "capes": []
        }
        """
        var profile = try JSONDecoder().decode(MinecraftProfile.self, from: Data(profileJSON.utf8))
        XCTAssertEqual(profile.name, "Notch")
        XCTAssertEqual(profile.skinURL, "https://textures.minecraft.net/texture/abc")
        XCTAssertEqual(profile.formattedUUID, "069a79f4-44e9-4726-a5be-fca90e38aaf5")

        // 官方接口返回的 id 可能没有连字符
        profile = try JSONDecoder().decode(
            MinecraftProfile.self,
            from: Data("""
            {"id":"069a79f444e94726a5befca90e38aaf5","name":"Notch"}
            """.utf8)
        )
        XCTAssertEqual(profile.formattedUUID, "069a79f4-44e9-4726-a5be-fca90e38aaf5")
    }

    func testXboxTokenParsing() throws {
        let json = """
        {
          "Token": "xsts-token",
          "DisplayClaims": {"xui": [{"uhs": "user-hash", "xid": "2535400000000001"}]}
        }
        """
        let token = try MicrosoftAuthService.parseXboxToken(Data(json.utf8), context: "测试")
        XCTAssertEqual(token.token, "xsts-token")
        XCTAssertEqual(token.userHash, "user-hash")
        XCTAssertEqual(token.xuid, "2535400000000001")
        XCTAssertEqual(token.identityToken, "XBL3.0 x=user-hash;xsts-token")

        XCTAssertThrowsError(try MicrosoftAuthService.parseXboxToken(Data("{}".utf8), context: "测试"))
    }

    func testXboxErrorCodeMapping() throws {
        func errorCode(_ code: UInt32) -> MicrosoftAuthError? {
            let data = Data("{\"XErr\":\(code),\"Message\":\"\",\"Redirect\":\"\"}".utf8)
            return MicrosoftAuthService.xboxError(from: data)
        }
        XCTAssertEqual(errorCode(2148916233), .noXboxAccount)
        XCTAssertEqual(errorCode(2148916235), .regionUnavailable)
        XCTAssertEqual(errorCode(2148916238), .childAccount)
        XCTAssertEqual(errorCode(2148916227), .xboxError(2148916227))
        XCTAssertNil(MicrosoftAuthService.xboxError(from: Data("{}".utf8)))
        XCTAssertNotNil(MicrosoftAuthError.noXboxAccount.helpURL)
        XCTAssertNil(MicrosoftAuthError.network("x").helpURL)
        XCTAssertTrue(MicrosoftAuthError.noMinecraftOwnership.localizedDescription.contains("所有权"))
    }

    // MARK: - 会话与启动账户

    func testSessionRefreshWindow() {
        let now = Date()
        var session = makeSession(microsoftExpiresAt: now.addingTimeInterval(3600), minecraftExpiresAt: now.addingTimeInterval(3600))
        XCTAssertFalse(session.needsRefresh(at: now))

        session.minecraftExpiresAt = now.addingTimeInterval(60)
        XCTAssertTrue(session.needsRefresh(at: now), "Minecraft 令牌 5 分钟内过期应刷新")

        session = makeSession(microsoftExpiresAt: now.addingTimeInterval(-10), minecraftExpiresAt: now.addingTimeInterval(3600))
        XCTAssertTrue(session.needsRefresh(at: now), "微软令牌过期也应刷新")
    }

    func testLaunchAccountKinds() {
        let offline = LaunchAccount.offline(name: " Steve ")
        XCTAssertEqual(offline.kind, .offline)
        XCTAssertEqual(offline.name, "Steve")
        XCTAssertEqual(offline.accessToken, "0")
        XCTAssertEqual(offline.userType, "legacy")
        XCTAssertEqual(offline.commandUUID, LaunchCommandBuilder.offlineUUID(for: "Steve"))
        XCTAssertNil(offline.xuid)

        let session = makeSession()
        let online = LaunchAccount.microsoft(session: session)
        XCTAssertEqual(online.kind, .microsoft)
        XCTAssertEqual(online.name, "Notch")
        XCTAssertEqual(online.accessToken, "minecraft-token")
        XCTAssertEqual(online.userType, "msa")
        XCTAssertEqual(online.xuid, "2535400000000001")
        XCTAssertEqual(online.commandUUID, "069a79f444e94726a5befca90e38aaf5")
    }

    func testLaunchCommandUsesPremiumIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installation = MinecraftInstallation(root: root)
        let versionID = "1.21.4"
        try FileManager.default.createDirectory(at: installation.versionDirectory(versionID), withIntermediateDirectories: true)
        try Data().write(to: installation.versionJarURL(versionID))
        let json = """
        {
          "id": "\(versionID)",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "libraries": [],
          "arguments": {
            "game": ["--username", "${auth_player_name}", "--uuid", "${auth_uuid}",
                     "--accessToken", "${auth_access_token}", "--userType", "${user_type}",
                     "--xuid", "${auth_xuid}"],
            "jvm": ["-Djava.library.path=${natives_directory}"]
          }
        }
        """
        try Data(json.utf8).write(to: installation.versionJSONURL(versionID))
        let resolved = try VersionResolver.resolve(versionID: versionID, installation: installation)
        let java = JavaRuntime(
            id: "/tmp/java",
            executable: URL(fileURLWithPath: "/tmp/java"),
            version: "21.0.5",
            majorVersion: 21,
            vendor: "Temurin"
        )
        let session = makeSession()

        let options = LaunchOptions(
            versionID: versionID,
            playerName: "Steve",
            java: java,
            memoryMB: 4096,
            renderThreads: 4,
            extraJVMArguments: [],
            gameDirectory: root,
            account: .microsoft(session: session)
        )
        let command = try LaunchCommandBuilder.build(detail: resolved, installation: installation, options: options)
        let joined = command.arguments.joined(separator: " ")
        XCTAssertTrue(joined.contains("--username Notch"))
        XCTAssertTrue(joined.contains("--uuid 069a79f444e94726a5befca90e38aaf5"))
        XCTAssertTrue(joined.contains("--accessToken minecraft-token"))
        XCTAssertTrue(joined.contains("--userType msa"))
        XCTAssertTrue(joined.contains("--xuid 2535400000000001"), "1.20.5+ 用 ${auth_xuid} 占位符")
        XCTAssertFalse(joined.contains(LaunchCommandBuilder.offlineUUID(for: "Steve")))

        // 日志脱敏：令牌不能出现在可复制的命令行里
        let redacted = LaunchCommandBuilder.redacted(command.commandLine, hiding: "minecraft-token")
        XCTAssertFalse(redacted.contains("minecraft-token"))
        XCTAssertTrue(redacted.contains("***"))
        // 离线令牌 "0" 不应被脱敏
        XCTAssertEqual(LaunchCommandBuilder.redacted("--accessToken 0", hiding: "0"), "--accessToken 0")
    }

    // MARK: - 账户状态机

    @MainActor
    func testLoginFlowAddsAccountAndPersistsToken() async {
        let harness = makeHarness()
        let store = harness.store
        store.beginLogin()

        await waitUntil(timeout: 3) { !store.loginState.isBusy }
        XCTAssertEqual(store.loginState, .idle)
        XCTAssertEqual(store.microsoftAccounts.count, 1)
        XCTAssertEqual(store.microsoftAccounts.first?.name, "Notch")
        XCTAssertEqual(store.selectedAccountID, harness.session.uuid)
        XCTAssertEqual(store.selectedAccount.kind, .microsoft)
        XCTAssertEqual(harness.tokenStore.load(accountID: harness.session.uuid)?.playerName, "Notch")
        XCTAssertNotNil(store.consumeSuccessMessage())
        XCTAssertEqual(store.consumeSuccessMessage(), nil, "成功提示只消费一次")
    }

    @MainActor
    func testLoginFailureKeepsNoAccount() async {
        let harness = makeHarness()
        harness.service.error = .noXboxAccount
        harness.store.beginLogin()

        await waitUntil(timeout: 3) { !harness.store.loginState.isBusy }
        if case .failed(let error) = harness.store.loginState {
            XCTAssertEqual(error, .noXboxAccount)
        } else {
            XCTFail("应进入失败态：\(harness.store.loginState)")
        }
        XCTAssertTrue(harness.store.microsoftAccounts.isEmpty)
        XCTAssertEqual(harness.store.selectedAccountID, AuthAccountRecord.offlineID)
    }

    @MainActor
    func testCancelLoginStopsFlow() async {
        let harness = makeHarness()
        harness.service.suspendPoll = true
        harness.store.beginLogin()
        await waitUntil(timeout: 2) { if case .waitingForUser = harness.store.loginState { return true }; return false }
        harness.store.cancelLogin()
        XCTAssertFalse(harness.store.loginState.isBusy)
        XCTAssertFalse(harness.store.isLoginSheetPresented)
    }

    @MainActor
    func testLogoutRemovesAccountAndFallsBackOffline() async {
        let harness = makeHarness()
        harness.store.beginLogin()
        await waitUntil(timeout: 3) { !harness.store.loginState.isBusy }
        let accountID = harness.session.uuid

        harness.store.logout(accountID)
        XCTAssertTrue(harness.store.microsoftAccounts.isEmpty)
        XCTAssertEqual(harness.store.selectedAccountID, AuthAccountRecord.offlineID)
        XCTAssertNil(harness.tokenStore.load(accountID: accountID))
        XCTAssertEqual(harness.store.selectedAccount.kind, .offline)
    }

    @MainActor
    func testLaunchAccountRefreshesExpiredMicrosoftSession() async throws {
        let harness = makeHarness()
        let expired = makeSession(
            microsoftExpiresAt: Date().addingTimeInterval(-60),
            minecraftExpiresAt: Date().addingTimeInterval(-60)
        )
        try harness.tokenStore.save(expired, for: expired.uuid)
        harness.settings.authAccounts = [
            AuthAccountRecord(
                id: expired.uuid,
                kind: .microsoft,
                name: expired.playerName,
                uuid: expired.formattedUUID
            )
        ]
        harness.settings.selectedAuthAccountID = expired.uuid
        harness.service.refreshedSession = makeSession(
            minecraftToken: "refreshed-token",
            microsoftExpiresAt: Date().addingTimeInterval(3600),
            minecraftExpiresAt: Date().addingTimeInterval(3600)
        )

        let launchAccount = try await harness.store.launchAccount()
        XCTAssertEqual(launchAccount.kind, .microsoft)
        XCTAssertEqual(launchAccount.accessToken, "refreshed-token")
        XCTAssertEqual(harness.tokenStore.load(accountID: expired.uuid)?.minecraftAccessToken, "refreshed-token")
    }

    @MainActor
    func testSelectSwitchesBetweenPremiumAndOffline() async throws {
        let harness = makeHarness()
        let session = harness.session
        try harness.tokenStore.save(session, for: session.uuid)
        harness.settings.authAccounts = [
            AuthAccountRecord(id: session.uuid, kind: .microsoft, name: session.playerName, uuid: session.formattedUUID)
        ]
        harness.settings.selectedAuthAccountID = session.uuid

        XCTAssertTrue(harness.store.selectedAccount.isMicrosoft)
        harness.store.select(AuthAccountRecord.offlineID)
        XCTAssertEqual(harness.store.selectedAccountID, AuthAccountRecord.offlineID)
        XCTAssertFalse(harness.store.selectedAccount.isMicrosoft)

        harness.store.select(session.uuid)
        XCTAssertTrue(harness.store.selectedAccount.isMicrosoft)
        let account = try await harness.store.launchAccount()
        XCTAssertEqual(account.kind, .microsoft)
    }

    @MainActor
    func testOfflineLaunchAccountWhenOfflineSelected() async throws {
        let harness = makeHarness()
        harness.settings.playerName = "Alex"
        harness.settings.selectedAuthAccountID = AuthAccountRecord.offlineID
        let account = try await harness.store.launchAccount()
        XCTAssertEqual(account.kind, .offline)
        XCTAssertEqual(account.name, "Alex")
        XCTAssertEqual(account.uuid, LaunchCommandBuilder.offlineUUID(for: "Alex"))
    }


    // MARK: - 轮询状态机（URLProtocol stub）

    func testPollDeviceTokenStateMapping() async throws {
        let cases: [(String, Int)] = [
            ("{\"error\":\"authorization_pending\"}", 400),
            ("{\"error\":\"slow_down\"}", 400),
            ("{\"error\":\"expired_token\"}", 400),
            ("{\"error\":\"access_denied\"}", 400),
            ("{\"access_token\":\"a\",\"refresh_token\":\"r\",\"expires_in\":3600}", 200)
        ]
        for (body, status) in cases {
            AuthStubURLProtocol.handler = { _ in (status, Data(body.utf8)) }
            let service = MicrosoftAuthService(session: AuthStubURLProtocol.makeSession())
            let result = try await service.pollDeviceTokenOnce(deviceCode: "d")
            switch (body, result) {
            case (_, .pending) where body.contains("authorization_pending"):
                break
            case (_, .slowDown) where body.contains("slow_down"):
                break
            case (_, .expired) where body.contains("expired_token"):
                break
            case (_, .denied) where body.contains("access_denied"):
                break
            case (_, .token(let token)) where token.accessToken == "a":
                XCTAssertEqual(token.refreshToken, "r")
            default:
                XCTFail("响应映射不符：\(body) -> \(result)")
            }
        }
    }

    // MARK: - 刷新并发合并

    @MainActor
    func testConcurrentRefreshIsMergedIntoOneRequest() async throws {
        let harness = makeHarness()
        let expired = makeSession(
            microsoftExpiresAt: Date().addingTimeInterval(-60),
            minecraftExpiresAt: Date().addingTimeInterval(-60)
        )
        try harness.tokenStore.save(expired, for: expired.uuid)
        harness.settings.authAccounts = [
            AuthAccountRecord(id: expired.uuid, kind: .microsoft, name: expired.playerName, uuid: expired.formattedUUID)
        ]
        harness.settings.selectedAuthAccountID = expired.uuid
        harness.service.refreshDelay = 0.2

        async let first = harness.store.refresh(expired.uuid)
        async let second = harness.store.refresh(expired.uuid)
        let results = await (first, second)
        XCTAssertEqual(harness.service.refreshCount, 1, "同一账户的并发刷新应合并为一次")
        XCTAssertTrue(results.0 && results.1)
    }

    // MARK: - 测试替身

    private struct Harness {
        let store: AccountStore
        let service: StubAuthService
        let tokenStore: InMemoryAuthTokenStore
        let settings: LauncherSettings
        let session: MinecraftAuthSession
    }

    @MainActor
    private func makeHarness() -> Harness {
        let suite = "launcher.tests.auth.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = LauncherSettings(defaults: defaults)
        settings.selectedAuthAccountID = AuthAccountRecord.offlineID
        let tokenStore = InMemoryAuthTokenStore()
        let session = makeSession()
        let service = StubAuthService(session: session)
        let store = AccountStore(settings: settings, service: service, tokenStore: tokenStore)
        return Harness(store: store, service: service, tokenStore: tokenStore, settings: settings, session: session)
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func makeSession(
        minecraftToken: String = "minecraft-token",
        microsoftExpiresAt: Date = Date().addingTimeInterval(3600),
        minecraftExpiresAt: Date = Date().addingTimeInterval(3600)
    ) -> MinecraftAuthSession {
        MinecraftAuthSession(
            playerName: "Notch",
            uuid: "069a79f444e94726a5befca90e38aaf5",
            minecraftAccessToken: minecraftToken,
            minecraftExpiresAt: minecraftExpiresAt,
            microsoftAccessToken: "microsoft-token",
            microsoftExpiresAt: microsoftExpiresAt,
            microsoftRefreshToken: "refresh-token",
            xuid: "2535400000000001",
            skinURL: "https://textures.minecraft.net/texture/abc"
        )
    }
}

// MARK: - 认证服务桩

private final class StubAuthService: MicrosoftAuthenticating, @unchecked Sendable {
    let session: MinecraftAuthSession
    var error: MicrosoftAuthError?
    var suspendPoll = false
    var refreshedSession: MinecraftAuthSession?
    var refreshDelay: TimeInterval = 0
    private let lock = NSLock()
    private var _refreshCount = 0
    var refreshCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _refreshCount
    }

    init(session: MinecraftAuthSession) {
        self.session = session
    }

    func requestDeviceCode() async throws -> MicrosoftDeviceCode {
        if let error { throw error }
        return MicrosoftDeviceCode(
            deviceCode: "device-code",
            userCode: "ABCD-1234",
            verificationURI: "https://microsoft.com/link",
            expiresIn: 900,
            interval: 1
        )
    }

    func pollDeviceToken(_ code: MicrosoftDeviceCode) async throws -> MicrosoftToken {
        if suspendPoll {
            // 一直挂起，直到调用方取消
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        if let error { throw error }
        return MicrosoftToken(accessToken: "microsoft-token", refreshToken: "refresh-token", expiresIn: 3600)
    }

    func completeLogin(with token: MicrosoftToken) async throws -> MinecraftAuthSession {
        if let error { throw error }
        return session
    }

    func refresh(session: MinecraftAuthSession) async throws -> MinecraftAuthSession {
        lock.lock()
        _refreshCount += 1
        lock.unlock()
        if refreshDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(refreshDelay * 1_000_000_000)) }
        if let error { throw error }
        return refreshedSession ?? session
    }
}

// MARK: - URLProtocol 桩

final class AuthStubURLProtocol: URLProtocol {
    static let lock = NSLock()
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        AuthStubURLProtocol.lock.lock()
        let handler = AuthStubURLProtocol.handler
        AuthStubURLProtocol.lock.unlock()
        let (status, data) = handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
