import SwiftUI

/// 画廊分区：侧栏导航与页面注册表。
public enum LauncherGallerySection: String, CaseIterable, Identifiable {
    case studio
    case buttons
    case inputs
    case selection
    case surfaces
    case feedback
    case navigation
    case demo
    case xml

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .studio: return "主题工作台"
        case .buttons: return "按钮"
        case .inputs: return "输入"
        case .selection: return "选择"
        case .surfaces: return "容器"
        case .feedback: return "反馈"
        case .navigation: return "导航"
        case .demo: return "实战样张"
        case .xml: return "XML 设计器"
        }
    }

    public var systemImage: String {
        switch self {
        case .studio: return "paintpalette.fill"
        case .buttons: return "square.grid.2x2.fill"
        case .inputs: return "text.cursor"
        case .selection: return "slider.horizontal.3"
        case .surfaces: return "square.stack.3d.up.fill"
        case .feedback: return "bell.badge.fill"
        case .navigation: return "sidebar.left"
        case .demo: return "play.rectangle.fill"
        case .xml: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// 侧栏分组
    public var group: String {
        switch self {
        case .studio: return "设计系统"
        case .buttons, .inputs, .selection: return "控件"
        case .surfaces, .feedback, .navigation: return "容器与页面"
        case .demo: return "实战"
        case .xml: return "工具"
        }
    }

    public var page: AnyView {
        switch self {
        case .studio: return AnyView(ThemeStudioPage())
        case .buttons: return AnyView(ButtonsPage())
        case .inputs: return AnyView(InputsPage())
        case .selection: return AnyView(SelectionPage())
        case .surfaces: return AnyView(SurfacesPage())
        case .feedback: return AnyView(FeedbackPage())
        case .navigation: return AnyView(NavigationPage())
        case .demo: return AnyView(LauncherDemoPage())
        case .xml: return AnyView(XMLDesignerPage())
        }
    }

    /// 分组顺序（侧栏渲染用）
    public static let groupOrder: [(String, [LauncherGallerySection])] = [
        ("设计系统", [.studio]),
        ("控件", [.buttons, .inputs, .selection]),
        ("容器与页面", [.surfaces, .feedback, .navigation]),
        ("实战", [.demo]),
        ("工具", [.xml])
    ]
}
