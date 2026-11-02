import Foundation

/// 账户信息（启动器当前只支持离线账户，`type` 用于展示账户类型）。
public struct LauncherAccount: Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let lastLogin: String
    public let isOnline: Bool

    public init(name: String, type: String, lastLogin: String, isOnline: Bool) {
        self.name = name
        self.type = type
        self.lastLogin = lastLogin
        self.isOnline = isOnline
    }
}
