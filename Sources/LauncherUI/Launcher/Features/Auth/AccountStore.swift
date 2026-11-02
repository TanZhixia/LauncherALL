import Foundation
import Observation

// MARK: - 账户中心

/// 账户中心：正版（微软）登录状态机、多账户管理、令牌刷新与启动账户解析。
/// UI 通过 `@Environment(AccountStore.self)` 使用；`LauncherEngine` 通过 `launchAccount()` 取启动身份。
@MainActor
@Observable
public final class AccountStore {
    // MARK: 登录状态

    /// 正版登录流程的显式状态机（供登录面板渲染）。
    public enum LoginState: Equatable {
        case idle
        case requestingCode
        case waitingForUser(MicrosoftDeviceCode)
        case authenticating
        case failed(MicrosoftAuthError)

        public var isBusy: Bool {
            switch self {
            case .idle, .failed: return false
            case .requestingCode, .waitingForUser, .authenticating: return true
            }
        }

        /// 登录面板的步骤（1 打开网页 / 2 输入验证码 / 3 完成授权）。
        public var step: Int {
            switch self {
            case .requestingCode: return 1
            case .waitingForUser: return 2
            case .authenticating: return 3
            case .idle, .failed: return 1
            }
        }
    }

    // MARK: 公开状态

    /// 登录面板是否展示。
    public var isLoginSheetPresented = false {
        didSet {
            if !isLoginSheetPresented, loginState.isBusy {
                cancelLogin()
            }
        }
    }
    public private(set) var loginState: LoginState = .idle
    /// 最近一次失败（用于页面内联提示）。
    public private(set) var lastError: MicrosoftAuthError?
    /// 最近一次成功的提示文案（由壳层消费后清空）。
    public private(set) var successMessage: String?

    // MARK: 依赖

    private let settings: LauncherSettings
    private let service: MicrosoftAuthenticating
    private let tokenStore: AuthTokenStoring
    private var loginTask: Task<Void, Never>?
    /// 每个账户同一时间只允许一个刷新请求（微软 refresh_token 会轮换，并发刷新会互相作废）。
    private var inFlightRefreshes: [String: Task<MinecraftAuthSession, Error>] = [:]

    public init(
        settings: LauncherSettings = .shared,
        service: MicrosoftAuthenticating = MicrosoftAuthService(),
        tokenStore: AuthTokenStoring = KeychainAuthTokenStore()
    ) {
        self.settings = settings
        self.service = service
        self.tokenStore = tokenStore
    }

    // MARK: 账户列表

    /// 已添加的正版账户。
    public var microsoftAccounts: [AuthAccountRecord] { settings.authAccounts }

    /// 离线账户（玩家名实时来自设置）。
    public var offlineAccount: AuthAccountRecord {
        let name = settings.playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let playerName = name.isEmpty ? "Steve" : name
        return AuthAccountRecord(
            id: AuthAccountRecord.offlineID,
            kind: .offline,
            name: playerName,
            uuid: LaunchCommandBuilder.offlineUUID(for: playerName)
        )
    }

    /// 页面展示用：离线账户 + 所有正版账户。
    public var allAccounts: [AuthAccountRecord] {
        [offlineAccount] + microsoftAccounts
    }

    /// 当前选中的账户 id。
    public var selectedAccountID: String {
        get { settings.selectedAuthAccountID }
        set { settings.selectedAuthAccountID = newValue }
    }

    /// 当前选中的账户（失效时回退离线账户）。
    public var selectedAccount: AuthAccountRecord {
        if settings.selectedAuthAccountID == AuthAccountRecord.offlineID {
            return offlineAccount
        }
        return microsoftAccounts.first { $0.id == settings.selectedAuthAccountID } ?? offlineAccount
    }

    /// 当前账户是否是正版。
    public var isOnline: Bool { selectedAccount.kind == .microsoft }

    // MARK: 选择 / 删除

    /// 切换当前账户。
    public func select(_ accountID: String) {
        guard allAccounts.contains(where: { $0.id == accountID }) else { return }
        settings.selectedAuthAccountID = accountID
        if accountID != AuthAccountRecord.offlineID {
            touch(accountID)
        }
    }

    /// 退出登录 / 删除正版账户：清掉令牌并移出列表；若正在使用则切回离线账户。
    public func logout(_ accountID: String) {
        guard accountID != AuthAccountRecord.offlineID else { return }
        tokenStore.delete(accountID: accountID)
        settings.authAccounts = settings.authAccounts.filter { $0.id != accountID }
        if settings.selectedAuthAccountID == accountID {
            settings.selectedAuthAccountID = AuthAccountRecord.offlineID
        }
        successMessage = "已移除正版账户"
    }

    /// 手动刷新某个正版账户的令牌。
    @discardableResult
    public func refresh(_ accountID: String) async -> Bool {
        guard let record = microsoftAccounts.first(where: { $0.id == accountID }),
              let session = tokenStore.load(accountID: record.id) else {
            lastError = .invalidRefreshToken
            return false
        }
        do {
            _ = try await refreshSession(session)
            // 刷新期间账户可能已被退出登录：此时不应再提示「刷新成功」
            guard settings.authAccounts.contains(where: { $0.id == accountID }) else {
                lastError = nil
                return false
            }
            successMessage = "登录状态已刷新"
            lastError = nil
            return true
        } catch let error as MicrosoftAuthError {
            lastError = error
            return false
        } catch {
            lastError = .unexpected(error.localizedDescription)
            return false
        }
    }

    // MARK: 登录

    /// 打开登录面板并开始设备码流程。
    public func beginLogin() {
        guard !loginState.isBusy else { return }
        lastError = nil
        isLoginSheetPresented = true
        loginState = .requestingCode
        loginTask = Task { [weak self] in
            await self?.performLogin()
        }
    }

    /// 取消登录：终止轮询并关闭面板。
    public func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        if loginState.isBusy {
            loginState = .idle
        }
        isLoginSheetPresented = false
    }

    /// 失败后重试（重新申请验证码）。
    public func retryLogin() {
        loginTask?.cancel()
        loginTask = nil
        loginState = .idle
        beginLogin()
    }

    private func performLogin() async {
        do {
            let code = try await service.requestDeviceCode()
            try Task.checkCancellation()
            loginState = .waitingForUser(code)

            let token = try await service.pollDeviceToken(code)
            try Task.checkCancellation()
            loginState = .authenticating

            let session = try await service.completeLogin(with: token)
            try Task.checkCancellation()
            finishLogin(with: session)
        } catch is CancellationError {
            loginState = .idle
        } catch let error as MicrosoftAuthError {
            if case .cancelled = error {
                loginState = .idle
            } else {
                lastError = error
                loginState = .failed(error)
            }
        } catch {
            let wrapped = MicrosoftAuthError.unexpected(error.localizedDescription)
            lastError = wrapped
            loginState = .failed(wrapped)
        }
        loginTask = nil
    }

    /// 登录成功：写入令牌、追加/更新账户、切换为当前账户并关闭面板。
    private func finishLogin(with session: MinecraftAuthSession) {
        let accountID = session.uuid
        do {
            try tokenStore.save(session, for: accountID)
        } catch {
            lastError = .unexpected("保存登录令牌失败：\(error.localizedDescription)")
            loginState = .failed(lastError ?? .unexpected("保存登录令牌失败"))
            return
        }

        var accounts = settings.authAccounts
        if let index = accounts.firstIndex(where: { $0.id == accountID }) {
            accounts[index].name = session.playerName
            accounts[index].uuid = session.formattedUUID
            accounts[index].skinURL = session.skinURL
            accounts[index].lastUsedAt = Date()
        } else {
            accounts.append(
                AuthAccountRecord(
                    id: accountID,
                    kind: .microsoft,
                    name: session.playerName,
                    uuid: session.formattedUUID,
                    addedAt: Date(),
                    lastUsedAt: Date(),
                    skinURL: session.skinURL
                )
            )
        }
        settings.authAccounts = accounts
        settings.selectedAuthAccountID = accountID
        successMessage = "已添加正版账户 \(session.playerName)"
        lastError = nil
        loginState = .idle
        isLoginSheetPresented = false
    }

    // MARK: 启动用账户

    /// 启动游戏前解析账户身份：离线 → 离线 UUID；正版 → 必要时刷新令牌后返回 Minecraft 令牌。
    public func launchAccount() async throws -> LaunchAccount {
        let record = selectedAccount
        guard record.kind == .microsoft else {
            return .offline(name: settings.playerName)
        }
        guard var session = tokenStore.load(accountID: record.id) else {
            throw MicrosoftAuthError.invalidRefreshToken
        }
        if session.needsRefresh() {
            session = try await refreshSession(session)
        }
        return .microsoft(session: session)
    }

    /// 启动器启动时静默刷新当前正版账户（失败只记录，不阻塞界面）。
    public func refreshSelectedIfNeeded() async {
        guard selectedAccount.kind == .microsoft,
              let session = tokenStore.load(accountID: selectedAccount.id),
              session.needsRefresh() else { return }
        _ = try? await refreshSession(session)
    }

    /// 消费成功提示（壳层 toast 后调用）。
    public func consumeSuccessMessage() -> String? {
        defer { successMessage = nil }
        return successMessage
    }

    // MARK: 内部

    /// 刷新会话：同一账户的并发刷新会合并到同一个 Task（single-flight），避免 refresh_token 轮换竞态。
    private func refreshSession(_ session: MinecraftAuthSession) async throws -> MinecraftAuthSession {
        let accountID = session.uuid
        if let existing = inFlightRefreshes[accountID] {
            return try await existing.value
        }
        let service = self.service
        // 登记项由内部任务完成时清理：即使等待方被取消，也不会让后续刷新并发执行
        let task = Task<MinecraftAuthSession, Error> { [weak self] in
            do {
                let refreshed = try await service.refresh(session: session)
                self?.inFlightRefreshes[accountID] = nil
                return refreshed
            } catch {
                self?.inFlightRefreshes[accountID] = nil
                throw error
            }
        }
        inFlightRefreshes[accountID] = task

        let refreshed = try await task.value
        // 刷新期间账户可能已被退出登录：只有账户仍存在时才回写令牌与元数据
        guard settings.authAccounts.contains(where: { $0.id == accountID }) else {
            return refreshed
        }
        do {
            try tokenStore.save(refreshed, for: refreshed.uuid)
        } catch {
            throw MicrosoftAuthError.unexpected("保存刷新后的登录信息失败：\(error.localizedDescription)")
        }
        updateRecord(with: refreshed)
        return refreshed
    }

    private func updateRecord(with session: MinecraftAuthSession) {
        var accounts = settings.authAccounts
        guard let index = accounts.firstIndex(where: { $0.id == session.uuid }) else { return }
        accounts[index].name = session.playerName
        accounts[index].uuid = session.formattedUUID
        accounts[index].skinURL = session.skinURL
        accounts[index].lastUsedAt = Date()
        settings.authAccounts = accounts
    }

    private func touch(_ accountID: String) {
        var accounts = settings.authAccounts
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].lastUsedAt = Date()
        settings.authAccounts = accounts
    }
}
