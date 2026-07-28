import SwiftUI

/// Palette sampled from the WeMendAI app icon, so the app and the icon read as one
/// product. The icon is a deep navy tile with a teal→cyan→violet gradient running
/// left-to-right across the two silhouettes, a mint heart, and a teal waveform.
enum Brand {
    // Backdrop — the icon's tile, darkened slightly so foreground text keeps
    // contrast over it.
    static let navyDeep  = Color(hex: 0x0B0F26)   // near-black navy, screen edges
    static let navy      = Color(hex: 0x141A3C)   // icon tile centre
    static let navyLift  = Color(hex: 0x1E2551)   // raised panels

    // Accents, in the order they appear across the icon (left → right).
    static let mint      = Color(hex: 0x3DE0B0)   // heart, male silhouette top
    static let teal      = Color(hex: 0x2ED9C3)   // waveform bars
    static let cyan      = Color(hex: 0x35A8E8)   // silhouette midpoint
    static let blue      = Color(hex: 0x4F8FF0)
    static let violet    = Color(hex: 0x8B6FE8)   // female silhouette
    static let violetLit = Color(hex: 0xA07BF5)

    /// The icon's signature sweep. Used for the orb and the "AI" in the wordmark.
    static let sweep = Gradient(colors: [mint, teal, cyan, blue, violet])

    /// Per-state accent. Kept inside the icon's palette rather than inventing new
    /// hues, so no state looks foreign to the brand.
    static func accent(_ state: OrbState) -> Color {
        switch state {
        case .idle:      return cyan.opacity(0.85)
        case .listening: return teal          // "listening" = the icon's waveform
        case .thinking:  return violetLit     // = the female silhouette
        case .speaking:  return mint          // = the heart
        }
    }
}

extension Color {
    /// 0xRRGGBB literal — easier to keep in sync with the icon than decimal triples.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
