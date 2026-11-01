import SwiftUI

/// 内置主题注册表。新增主题遵循同一工厂方法即可自动获得一致的层级与质感。
public enum LauncherThemes {
    public static let overworld = LauncherTheme.dark(
        id: "overworld",
        name: "翡翠原野",
        tagline: "Overworld · 草方块与晨雾",
        backdrop: [Color(hex: 0x05150F), Color(hex: 0x082018), Color(hex: 0x0B2C20)],
        glowPrimary: Color(hex: 0x34D399),
        glowSecondary: Color(hex: 0x0EA5E9),
        accent: Color(hex: 0x34D399),
        accentAlt: Color(hex: 0x10B981),
        onAccent: Color(hex: 0x04261C),
        textPrimary: Color(hex: 0xEAFBF3),
        textSecondary: Color(hex: 0xA8C8B9),
        textTertiary: Color(hex: 0x6F9083)
    )

    public static let nether = LauncherTheme.dark(
        id: "nether",
        name: "下界熔岩",
        tagline: "Nether · 岩浆与荧石",
        backdrop: [Color(hex: 0x190805), Color(hex: 0x280E07), Color(hex: 0x33130A)],
        glowPrimary: Color(hex: 0xF97316),
        glowSecondary: Color(hex: 0xEF4444),
        accent: Color(hex: 0xF97316),
        accentAlt: Color(hex: 0xFB923C),
        onAccent: Color(hex: 0x1E0A04),
        textPrimary: Color(hex: 0xFFF0E5),
        textSecondary: Color(hex: 0xDCB6A1),
        textTertiary: Color(hex: 0xA37D6A),
        gridOpacity: 0.05
    )

    public static let theEnd = LauncherTheme.dark(
        id: "end",
        name: "末地虚空",
        tagline: "The End · 紫颂与星尘",
        backdrop: [Color(hex: 0x080514), Color(hex: 0x120B22), Color(hex: 0x1B1132)],
        glowPrimary: Color(hex: 0xA78BFA),
        glowSecondary: Color(hex: 0xE879F9),
        accent: Color(hex: 0xA78BFA),
        accentAlt: Color(hex: 0xC4B5FD),
        onAccent: Color(hex: 0x120B22),
        textPrimary: Color(hex: 0xF2EEFF),
        textSecondary: Color(hex: 0xB9AECF),
        textTertiary: Color(hex: 0x8B7FA8),
        gridOpacity: 0.04
    )

    public static let sculk = LauncherTheme.dark(
        id: "sculk",
        name: "深暗之域",
        tagline: "Deep Dark · 幽匿与监守者",
        backdrop: [Color(hex: 0x030E14), Color(hex: 0x061A22), Color(hex: 0x08242E)],
        glowPrimary: Color(hex: 0x22D3EE),
        glowSecondary: Color(hex: 0x2DD4BF),
        accent: Color(hex: 0x22D3EE),
        accentAlt: Color(hex: 0x2DD4BF),
        onAccent: Color(hex: 0x041218),
        textPrimary: Color(hex: 0xE6FBFF),
        textSecondary: Color(hex: 0x9BC3CE),
        textTertiary: Color(hex: 0x6B8E99),
        glassMaterial: .regular,
        gridOpacity: 0.06
    )

    public static let aurora = LauncherTheme.light(
        id: "aurora",
        name: "极光晨曦",
        tagline: "Aurora · 雪原上的晨光",
        backdrop: [Color(hex: 0xF8FAFF), Color(hex: 0xEFF4FF), Color(hex: 0xE6EDFF)],
        glowPrimary: Color(hex: 0x6366F1),
        glowSecondary: Color(hex: 0x06B6D4),
        accent: Color(hex: 0x2563EB),
        accentAlt: Color(hex: 0x4F46E5),
        textPrimary: Color(hex: 0x0F172A),
        textSecondary: Color(hex: 0x46556B),
        textTertiary: Color(hex: 0x7C8AA0),
        glassMaterial: .thin
    )

    public static let cherry = LauncherTheme.light(
        id: "cherry",
        name: "樱花原野",
        tagline: "Cherry Grove · 粉色花瓣",
        backdrop: [Color(hex: 0xFFF8FA), Color(hex: 0xFFEFF4), Color(hex: 0xFFE4EC)],
        glowPrimary: Color(hex: 0xF472B6),
        glowSecondary: Color(hex: 0xFB7185),
        accent: Color(hex: 0xDB2777),
        accentAlt: Color(hex: 0xF43F5E),
        textPrimary: Color(hex: 0x2B0F1B),
        textSecondary: Color(hex: 0x6B4453),
        textTertiary: Color(hex: 0x96707E),
        success: Color(hex: 0x15803D),
        warning: Color(hex: 0xB45309),
        danger: Color(hex: 0xBE123C),
        glassMaterial: .thin
    )

    /// 全量主题（顺序即画廊展示顺序）
    public static let all: [LauncherTheme] = [overworld, nether, theEnd, sculk, aurora, cherry]

    public static let `default` = overworld

    public static func theme(withID id: String) -> LauncherTheme {
        all.first { $0.id == id } ?? `default`
    }
}
