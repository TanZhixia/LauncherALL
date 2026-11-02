import Foundation
import AppKit

// MARK: - 窗口动作

/// 窗口级真实动作：重置布局、最小化、聚焦。供「更多 → 重置窗口布局」这类别按钮使用。
@MainActor
public enum LauncherWindowActions {
    /// 默认窗口尺寸（与 App 启动尺寸一致）。
    public static let defaultSize = CGSize(width: 1380, height: 880)

    /// 把主窗口恢复成默认尺寸并居中。
    @discardableResult
    public static func resetLayout() -> Bool {
        guard let window = mainWindow else { return false }
        let size = defaultSize
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        let frame = CGRect(origin: origin, size: size)
        window.setFrame(frame, display: true, animate: true)
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// 最小化主窗口（启动游戏后的「启动后最小化」也走这里）。
    @discardableResult
    public static func minimize() -> Bool {
        guard let window = mainWindow else { return false }
        window.miniaturize(nil)
        return true
    }

    /// 把启动器收进 Dock（隐藏应用）。
    public static func hideLauncher() {
        NSApp.hide(nil)
    }

    /// 主窗口尺寸描述，例如 "1380 × 880"。
    public static var mainWindowSizeText: String {
        guard let size = mainWindow?.frame.size else { return "—" }
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    /// 当前主窗口（排除面板 / sheet）。
    public static var mainWindow: NSWindow? {
        NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
    }
}
