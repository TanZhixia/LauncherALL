import SwiftUI

// MARK: - 组件枚举与 XML 字符串的映射（大小写不敏感，非法值回退默认）

public extension LauncherTextStyle {
    static func fromXML(_ raw: String) -> LauncherTextStyle {
        switch raw.lowercased() {
        case "display": return .display
        case "title": return .title
        case "sectiontitle", "section": return .sectionTitle
        case "headline": return .headline
        case "body": return .body
        case "bodystrong", "strong": return .bodyStrong
        case "caption": return .caption
        case "micro": return .micro
        case "label": return .label
        case "mono": return .mono
        case "monosmall": return .monoSmall
        default: return .body
        }
    }
}

public extension LauncherTextTone {
    static func fromXML(_ raw: String) -> LauncherTextTone {
        switch raw.lowercased() {
        case "primary": return .primary
        case "secondary": return .secondary
        case "tertiary": return .tertiary
        case "accent": return .accent
        case "onaccent": return .onAccent
        case "success": return .success
        case "warning": return .warning
        case "danger": return .danger
        default: return .primary
        }
    }
}

public extension LauncherButtonVariant {
    static func fromXML(_ raw: String) -> LauncherButtonVariant {
        switch raw.lowercased() {
        case "primary", "main": return .primary
        case "secondary", "default": return .secondary
        case "ghost", "plain": return .ghost
        case "danger", "destructive": return .danger
        default: return .secondary
        }
    }
}

public extension LauncherButtonSize {
    static func fromXML(_ raw: String) -> LauncherButtonSize {
        switch raw.lowercased() {
        case "small", "sm": return .small
        case "medium", "md", "default": return .medium
        case "large", "lg": return .large
        default: return .medium
        }
    }
}

public extension LauncherBadgeTone {
    static func fromXML(_ raw: String) -> LauncherBadgeTone {
        switch raw.lowercased() {
        case "neutral", "default": return .neutral
        case "accent": return .accent
        case "success": return .success
        case "warning": return .warning
        case "danger": return .danger
        case "info": return .info
        default: return .neutral
        }
    }
}

public extension LauncherProgressTone {
    static func fromXML(_ raw: String) -> LauncherProgressTone {
        switch raw.lowercased() {
        case "accent", "primary": return .accent
        case "success": return .success
        case "warning": return .warning
        case "danger": return .danger
        default: return .accent
        }
    }
}

public extension LauncherBannerTone {
    static func fromXML(_ raw: String) -> LauncherBannerTone {
        switch raw.lowercased() {
        case "info": return .info
        case "success": return .success
        case "warning": return .warning
        case "danger": return .danger
        default: return .info
        }
    }
}

public extension GlassLevel {
    static func fromXML(_ raw: String) -> GlassLevel {
        switch raw.lowercased() {
        case "subtle": return .subtle
        case "regular", "default": return .regular
        case "strong": return .strong
        default: return .regular
        }
    }
}
