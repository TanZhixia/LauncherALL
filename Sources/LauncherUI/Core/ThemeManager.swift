import SwiftUI
import Observation

/// 主题运行时：负责切换、持久化与全局可调的外观参数。
@MainActor
@Observable
public final class LauncherThemeManager {
    public static let shared = LauncherThemeManager()

    public let presets: [LauncherTheme]

    /// 当前主题 id
    public var themeID: String {
        didSet { defaults.set(themeID, forKey: Keys.themeID) }
    }

    /// 全局边框强度倍数（0.4 - 1.6）：平面化风格下用它调节面板/分割线的可见度
    public var borderStrength: Double {
        didSet { defaults.set(borderStrength, forKey: Keys.borderStrength) }
    }

    /// 全局圆角倍数（0.6 - 1.4）
    public var cornerScale: Double {
        didSet { defaults.set(cornerScale, forKey: Keys.cornerScale) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let themeID = "launcher.themeID"
        static let borderStrength = "launcher.borderStrength"
        static let cornerScale = "launcher.cornerScale"
    }

    public init(presets: [LauncherTheme] = LauncherThemes.all, defaults: UserDefaults = .standard) {
        self.presets = presets
        self.defaults = defaults
        let storedID = defaults.string(forKey: Keys.themeID) ?? LauncherThemes.default.id
        self.themeID = presets.contains(where: { $0.id == storedID }) ? storedID : LauncherThemes.default.id
        let storedBorder = defaults.object(forKey: Keys.borderStrength) as? Double
        self.borderStrength = storedBorder ?? 1.0
        let storedCorners = defaults.object(forKey: Keys.cornerScale) as? Double
        self.cornerScale = storedCorners ?? 1.0
    }

    /// 当前主题（已叠加全局微调）
    public var theme: LauncherTheme {
        var base = presets.first { $0.id == themeID } ?? LauncherThemes.default
        let g = max(0.4, min(1.6, borderStrength))
        if g >= 1 {
            let t = (g - 1) / 0.6 * 0.35
            base.colors.stroke = base.colors.stroke.mixed(with: base.colors.textPrimary, amount: t)
            base.colors.strokeStrong = base.colors.strokeStrong.mixed(with: base.colors.textPrimary, amount: t * 0.8)
        } else {
            let t = (1 - g) / 0.6 * 0.8
            base.colors.stroke = base.colors.stroke.mixed(with: base.colors.surface, amount: t)
            base.colors.strokeStrong = base.colors.strokeStrong.mixed(with: base.colors.surface, amount: t * 0.8)
        }
        return base
    }

    /// 圆角缩放
    public func radius(_ value: CGFloat) -> CGFloat {
        value * max(0.6, min(1.4, cornerScale))
    }

    public func select(_ id: String) {
        guard themeID != id else { return }
        withAnimation(LauncherMotion.spring) {
            themeID = id
        }
    }

    public func next() {
        guard let index = presets.firstIndex(where: { $0.id == themeID }) else { return }
        select(presets[(index + 1) % presets.count].id)
    }
}

// MARK: - 环境注入

private struct LauncherThemeKey: EnvironmentKey {
    static let defaultValue: LauncherTheme = LauncherThemes.default
}

private struct LauncherSnapshotModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    var launcherTheme: LauncherTheme {
        get { self[LauncherThemeKey.self] }
        set { self[LauncherThemeKey.self] = newValue }
    }

    /// 离屏渲染模式：ImageRenderer 无法渲染 AppKit 背书的控件（TextField/Menu）与 ScrollView，
    /// 打开后组件改用同布局的静态等价物（布局尺寸不变），用于导出验收截图。
    var launcherSnapshotMode: Bool {
        get { self[LauncherSnapshotModeKey.self] }
        set { self[LauncherSnapshotModeKey.self] = newValue }
    }
}

public extension View {
    /// 注入主题 + 主题管理器（根视图调用一次）。
    func launcherThemeEnvironment(_ manager: LauncherThemeManager) -> some View {
        self
            .environment(\.launcherTheme, manager.theme)
            .environment(manager)
    }
}
