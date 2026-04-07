import AppKit

// MARK: - 设计令牌（暖色调设计系统）
enum DT {
    // ── 品牌色 ──
    static let primary = NSColor(red: 0xFF/255, green: 0x6B/255, blue: 0x4A/255, alpha: 1)       // #FF6B4A
    static let primaryLight = NSColor(red: 0xFF/255, green: 0x8A/255, blue: 0x6E/255, alpha: 1)   // #FF8A6E
    static let primaryDark = NSColor(red: 0xE5/255, green: 0x55/255, blue: 0x3A/255, alpha: 1)    // #E5553A
    static let secondary = NSColor(red: 0x4A/255, green: 0x9E/255, blue: 0xFF/255, alpha: 1)      // #4A9EFF
    static let secondaryLight = NSColor(red: 0x6C/255, green: 0xB3/255, blue: 0xFF/255, alpha: 1) // #6CB3FF
    static let success = NSColor(red: 0x34/255, green: 0xC7/255, blue: 0x59/255, alpha: 1)        // #34C759
    static let warning = NSColor(red: 0xFF/255, green: 0xB9/255, blue: 0x4A/255, alpha: 1)        // #FFB94A
    static let error = NSColor(red: 0xFF/255, green: 0x45/255, blue: 0x45/255, alpha: 1)          // #FF4545

    // ── 中性色（暖色调） ──
    static let bgCanvas = NSColor(red: 0xFA/255, green: 0xF8/255, blue: 0xF5/255, alpha: 1)       // #FAF8F5
    static let bgSurface = NSColor.white
    static let bgMuted = NSColor(red: 0xF5/255, green: 0xF2/255, blue: 0xEE/255, alpha: 1)        // #F5F2EE
    static let bgSubtle = NSColor(red: 0xED/255, green: 0xE9/255, blue: 0xE3/255, alpha: 1)       // #EDE9E3
    static let borderDefault = NSColor(red: 0xE8/255, green: 0xE2/255, blue: 0xDA/255, alpha: 1)  // #E8E2DA
    static let borderLight = NSColor(red: 0xF0/255, green: 0xEB/255, blue: 0xE5/255, alpha: 1)    // #F0EBE5

    // ── 文字色 ──
    static let textPrimary = NSColor(red: 0x2D/255, green: 0x2A/255, blue: 0x26/255, alpha: 1)    // #2D2A26
    static let textSecondary = NSColor(red: 0x7A/255, green: 0x74/255, blue: 0x6C/255, alpha: 1)  // #7A746C
    static let textTertiary = NSColor(red: 0xA9/255, green: 0xA2/255, blue: 0x9A/255, alpha: 1)   // #A9A29A

    // ── 圆角 ──
    static let radiusSm: CGFloat = 6
    static let radiusMd: CGFloat = 10
    static let radiusLg: CGFloat = 14
    static let radiusXl: CGFloat = 20

    // ── 阴影 ──
    static func applyShadowMd(to layer: CALayer) {
        layer.shadowColor = NSColor(red: 0.18, green: 0.16, blue: 0.15, alpha: 1).cgColor
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.1
    }

    static func applyShadowLg(to layer: CALayer) {
        layer.shadowColor = NSColor(red: 0.18, green: 0.16, blue: 0.15, alpha: 1).cgColor
        layer.shadowOffset = CGSize(width: 0, height: -4)
        layer.shadowRadius = 16
        layer.shadowOpacity = 0.12
    }
}
