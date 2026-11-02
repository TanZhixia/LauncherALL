import Foundation
import Security

// MARK: - 令牌存储协议

/// 正版登录令牌的存储（默认 Keychain，失败回退到受保护本地文件；测试可注入内存实现）。
public protocol AuthTokenStoring: Sendable {
    func save(_ session: MinecraftAuthSession, for accountID: String) throws
    func load(accountID: String) -> MinecraftAuthSession?
    func delete(accountID: String)
}

// MARK: - Keychain 实现

/// Keychain 存储：service + accountID 作为键；Keychain 不可用时回退到
/// `~/Library/Application Support/BlockLauncher/auth/` 下的 0600 权限 JSON 文件。
public struct KeychainAuthTokenStore: AuthTokenStoring {
    public let service: String
    public let fallbackDirectory: URL

    public init(service: String = "com.blocklauncher.auth", fallbackDirectory: URL? = nil) {
        self.service = service
        if let fallbackDirectory {
            self.fallbackDirectory = fallbackDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory())
            self.fallbackDirectory = base
                .appendingPathComponent("BlockLauncher", isDirectory: true)
                .appendingPathComponent("auth", isDirectory: true)
        }
    }

    public func save(_ session: MinecraftAuthSession, for accountID: String) throws {
        let data = try JSONEncoder().encode(session)
        if saveToKeychain(data, accountID: accountID) {
            // Keychain 成功后清掉可能残留的文件回退
            try? FileManager.default.removeItem(at: fileURL(for: accountID))
            return
        }
        try saveToFile(data, accountID: accountID)
    }

    public func load(accountID: String) -> MinecraftAuthSession? {
        if let data = loadFromKeychain(accountID: accountID),
           let session = try? JSONDecoder().decode(MinecraftAuthSession.self, from: data) {
            return session
        }
        guard let data = try? Data(contentsOf: fileURL(for: accountID)) else { return nil }
        return try? JSONDecoder().decode(MinecraftAuthSession.self, from: data)
    }

    public func delete(accountID: String) {
        deleteFromKeychain(accountID: accountID)
        try? FileManager.default.removeItem(at: fileURL(for: accountID))
    }

    // MARK: Keychain

    private func baseQuery(accountID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID
        ]
    }

    private func saveToKeychain(_ data: Data, accountID: String) -> Bool {
        var query = baseQuery(accountID: accountID)
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func loadFromKeychain(accountID: String) -> Data? {
        var query = baseQuery(accountID: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private func deleteFromKeychain(accountID: String) {
        SecItemDelete(baseQuery(accountID: accountID) as CFDictionary)
    }

    // MARK: 文件回退

    private func fileURL(for accountID: String) -> URL {
        let safe = accountID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return fallbackDirectory.appendingPathComponent("\(safe).json")
    }

    private func saveToFile(_ data: Data, accountID: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
        // 回退目录只允许当前用户访问
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fallbackDirectory.path)
        let url = fileURL(for: accountID)
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

// MARK: - 内存实现（测试用）

/// 内存令牌存储：单元测试 / 预览用，不落盘。
public final class InMemoryAuthTokenStore: AuthTokenStoring, @unchecked Sendable {
    private var storage: [String: MinecraftAuthSession] = [:]
    private let lock = NSLock()

    public init(seed: [String: MinecraftAuthSession] = [:]) {
        storage = seed
    }

    public func save(_ session: MinecraftAuthSession, for accountID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[accountID] = session
    }

    public func load(accountID: String) -> MinecraftAuthSession? {
        lock.lock()
        defer { lock.unlock() }
        return storage[accountID]
    }

    public func delete(accountID: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: accountID)
    }
}
