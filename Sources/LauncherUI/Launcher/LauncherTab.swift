import SwiftUI

/// 启动器主界面的四个一级导航。
public enum LauncherTab: String, CaseIterable, Identifiable {
    case launch
    case download
    case settings
    case more

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .launch: return "启动"
        case .download: return "下载"
        case .settings: return "设置"
        case .more: return "更多"
        }
    }

    public var systemImage: String {
        switch self {
        case .launch: return "play.fill"
        case .download: return "arrow.down.circle.fill"
        case .settings: return "slider.horizontal.3"
        case .more: return "ellipsis.circle.fill"
        }
    }

    public var shortcut: String {
        switch self {
        case .launch: return "⌘1"
        case .download: return "⌘2"
        case .settings: return "⌘3"
        case .more: return "⌘4"
        }
    }

    /// 键盘快捷键（⌘1…⌘4）。
    public var keyEquivalent: KeyEquivalent {
        switch self {
        case .launch: return "1"
        case .download: return "2"
        case .settings: return "3"
        case .more: return "4"
        }
    }
}
