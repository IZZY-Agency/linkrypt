import SwiftUI

enum LK {
    // Surfaces
    static let bg = Color(hex: 0x0a0b10)
    static let bgElev = Color(hex: 0x0e1018)
    static let surface2 = Color(hex: 0x1a1d2c)
    static let border = Color(hex: 0x2a2e44)
    static let borderSoft = Color(hex: 0x1f2233)
    static let borderHi = Color(hex: 0x3b4061)
    // Text
    static let fg = Color(hex: 0xe6e3d6)
    static let fgBody = Color(hex: 0xbcc1cb)
    static let fgMuted = Color(hex: 0x8b92a5)
    static let fgDim = Color(hex: 0x5a607a)
    // Brand + status
    static let amber = Color(hex: 0xf5c542)
    static let ok = Color(hex: 0x4ade80)
    static let err = Color(hex: 0xf87171)
    static let burn = Color(hex: 0xff7a2a)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}
