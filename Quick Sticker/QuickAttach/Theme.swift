import UIKit

private func rgb(_ value: UInt32, _ alpha: CGFloat = 1.0) -> UIColor {
    UIColor(red: CGFloat((value >> 16) & 0xff) / 255.0,
            green: CGFloat((value >> 8) & 0xff) / 255.0,
            blue: CGFloat(value & 0xff) / 255.0,
            alpha: alpha)
}

/// Palette copied verbatim from Telegram-iOS DefaultDayPresentationTheme.swift
/// (default .builtin(.dayClassic) theme), line references from HEAD 6ad963e.
enum Theme {
    static let accent = rgb(0x0088FF)                       // :56 defaultDayAccentColor
    static let navPrimaryText = rgb(0x000000)               // :415
    static let navSecondaryText = rgb(0x787878)             // :416 (offline subtitle)
    static let navAccentText = rgb(0x0088FF)                // :418 ("online" subtitle)
    static let panelControl = rgb(0x000000)                 // :945 — attach/mic/back tint
    static let inputPlaceholder = rgb(0x000000, 0.4)        // :951
    static let inputText = rgb(0x000000)                    // :952
    static let inputControl = rgb(0x000000)                 // :953 (rendered at alpha 0.5)
    static let sendPill = rgb(0x0088FF)                     // :944 panelControlAccentColor
    static let sendIcon = rgb(0xFFFFFF)                     // :955
    static let incomingBubble = rgb(0xFFFFFF)               // :588
    static let outgoingBubble = rgb(0xE1FFC7)               // :643 (flat — no gradient in dayClassic)
    static let bubbleStroke = UIColor(white: 0.0, alpha: 0.2) // :580-585
    static let incomingText = rgb(0x000000)
    static let outgoingText = rgb(0x000000)
    static let incomingTime = rgb(0x525252, 0.6)            // :623
    static let outgoingTime = rgb(0x008C09, 0.8)            // :678
    static let checkmark = rgb(0x19C700)                    // :737
    static let mediaTimePillFill = UIColor(white: 0.0, alpha: 0.3) // :738
    static let mediaTimeText = rgb(0xFFFFFF)                // :739
    /// Telegram's "Pink with Blue" day-classic wallpaper preset, paired with
    /// SoftwareGradientBackground anchor positions in ChatViewController.
    static let wallpaperColors: [UIColor] = [
        rgb(0x8DC0EB), rgb(0xB9D1EA), rgb(0xC6B1EF), rgb(0xEBD7EF),
    ]
}
