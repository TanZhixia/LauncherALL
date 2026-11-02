import Foundation

// MARK: - LauncherALL 的启动器产品

/// 标题栏下拉菜单里的「启动器」：LauncherALL 是一个启动器集合，Minecraft 与 DSH 共用同一个壳。
public enum LauncherProduct: String, CaseIterable, Identifiable, Sendable {
    /// Minecraft 启动器（当前完整实现）。
    case minecraft
    /// DSH（DeepSeek Harness）Web UI 启动器。
    case dsh

    public var id: String { rawValue }

    /// 产品名（下拉菜单标题 / 标题栏副标题）。
    public var title: String {
        switch self {
        case .minecraft: return "Minecraft 启动器"
        case .dsh: return "DSH 启动器"
        }
    }

    /// 下拉菜单里的补充说明。
    public var subtitle: String {
        switch self {
        case .minecraft: return "版本 · 实例 · 资源 · 账户"
        case .dsh: return "DeepSeek Harness · Web UI"
        }
    }

    /// 标题栏图标 / 菜单图标。
    public var systemImage: String {
        switch self {
        case .minecraft: return "cube.fill"
        case .dsh: return "sparkles"
        }
    }
}
