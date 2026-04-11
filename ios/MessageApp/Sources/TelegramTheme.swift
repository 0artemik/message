import Combine
import SwiftUI

/// Палитра как у веб-клиента (`index.css` — светлая / тёмная).
struct TelegramPalette {
    let isDark: Bool

    var blue: Color { Color(hex: isDark ? 0x5EB5FF : 0x3390EC) }
    var blueHover: Color { Color(hex: isDark ? 0x7AC3FF : 0x2B7FD4) }
    var bg: Color { Color(hex: isDark ? 0x212121 : 0xFFFFFF) }
    var sidebar: Color { Color(hex: isDark ? 0x212121 : 0xFFFFFF) }
    var border: Color { Color(hex: isDark ? 0x2D2D2D : 0xDFE3E6) }
    var chatBg: Color { Color(hex: isDark ? 0x0E1621 : 0xE6EBEE) }
    var text: Color { Color(hex: isDark ? 0xE8E8E8 : 0x000000) }
    var textSecondary: Color { Color(hex: isDark ? 0x8A8A8E : 0x707579) }
    var bubbleIn: Color { Color(hex: isDark ? 0x182533 : 0xFFFFFF) }
    var bubbleOut: Color { Color(hex: isDark ? 0x2B5278 : 0xEFFDDE) }
    var inputBg: Color { Color(hex: isDark ? 0x17212B : 0xFFFFFF) }
    var header: Color { Color(hex: isDark ? 0x212121 : 0xFFFFFF) }
    var searchBg: Color { Color(hex: isDark ? 0x17212B : 0xF4F4F5) }
    var rowHover: Color { Color(hex: isDark ? 0x2A2A2A : 0xF4F4F5) }
    var rowActive: Color { Color(hex: isDark ? 0x1A3D5C : 0xE8F4FC) }
    var online: Color { Color(hex: 0x4DCD5E) }
    var authGradientTop: Color { Color(hex: isDark ? 0x1E3F66 : 0x6AB7FF) }
    var authGradientMid: Color { Color(hex: isDark ? 0x0E1621 : 0x3390EC) }
    var authGradientBot: Color { Color(hex: isDark ? 0x0A1219 : 0x2A6FC4) }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    private let key = "ui-theme"

    @Published var isDark: Bool {
        didSet {
            UserDefaults.standard.set(isDark ? "dark" : "light", forKey: key)
        }
    }

    var palette: TelegramPalette { TelegramPalette(isDark: isDark) }

    init() {
        let raw = UserDefaults.standard.string(forKey: key)
        isDark = (raw == "dark")
    }

    func setLight() { isDark = false }
    func setDark() { isDark = true }
    func toggle() { isDark.toggle() }
}

private struct TelegramPaletteKey: EnvironmentKey {
    static let defaultValue = TelegramPalette(isDark: false)
}

extension EnvironmentValues {
    var telegramPalette: TelegramPalette {
        get { self[TelegramPaletteKey.self] }
        set { self[TelegramPaletteKey.self] = newValue }
    }
}
