import SwiftUI

/// Central design token repository for SPECTRAL.
/// All color constants live here — never use raw Color(hex:) literals in views.
enum Theme {

    // MARK: - Background Elevation (surfaces get lighter as they approach the user)

    /// Deepest background — metadata bar, empty state backdrop
    static let bg0 = Color(hex: 0x080808)
    /// Page background
    static let bg1 = Color(hex: 0x0F0F0F)
    /// Card / panel surface
    static let bg2 = Color(hex: 0x161620)
    /// Elevated element — inactive pills, tag backgrounds
    static let bg3 = Color(hex: 0x1C1C2A)
    /// Active / hover state — card top highlight
    static let bg4 = Color(hex: 0x242438)

    // MARK: - Text

    static let textPrimary   = Color(hex: 0xE8E8E8)
    static let textSecondary = Color(hex: 0x7A7A8E)
    static let textTertiary  = Color(hex: 0x4A4A5A)

    // MARK: - Semantic Accents

    static let accent  = Color(hex: 0x4ECDC4)   // teal-cyan, primary
    static let pass    = Color(hex: 0x2ECC71)   // green
    static let warning = Color(hex: 0xE6A817)   // amber
    static let error   = Color(hex: 0xE74C6F)   // rose red

    // MARK: - Chart

    static let chartGrid       = Color(hex: 0x1E1E2E)
    static let chartAxis       = Color(hex: 0x5A5A6E)
    static let chartMomentary  = Color(hex: 0x4ECDC4, alpha: 0.4)
    static let chartShortTerm  = Color(hex: 0x2ECC71)
    static let chartIntegrated = Color(hex: 0x4ECDC4)
    static let chartSpecAvg    = Color(hex: 0x4ECDC4)
    static let chartSpecPeak   = Color(hex: 0xE74C6F, alpha: 0.6)
    static let chartCrest      = Color(hex: 0x4ECDC4)
    static let chartThreshold  = Color(hex: 0xE6A817, alpha: 0.6)

    // MARK: - File Comparison Series

    static let fileColorHex: [UInt] = [0xE8E8E8, 0x4ECDC4, 0xE74C6F, 0xE6A817]

    static func fileColor(_ index: Int) -> Color {
        Color(hex: fileColorHex[min(index, fileColorHex.count - 1)])
    }

    // MARK: - Heat Gradient (waterfall / stereograph intensity mapping)

    /// -100 dBFS / silence: transparent
    static let heatTransparent = Color.clear
    /// -60 dBFS: deep blue
    static let heatDeepBlue  = Color(hex: 0x0A1628)
    /// -40 dBFS: teal
    static let heatTeal      = Color(hex: 0x1A6B5A)
    /// -20 dBFS: green
    static let heatGreen     = Color(hex: 0x2ECC71)
    /// -10 dBFS: yellow
    static let heatYellow    = Color(hex: 0xE6A817)
    ///   0 dBFS: red
    static let heatRed       = Color(hex: 0xE74C6F)

    // MARK: - Canvas Chart Background

    /// Radial gradient center — slightly lighter
    static let chartBgCenter = Color(hex: 0x12121E)
    /// Radial gradient edge — darker
    static let chartBgEdge   = Color(hex: 0x08080C)
    /// 1pt chart border
    static let chartBorder   = Color(hex: 0x1E1E2E)

    // MARK: - Stereograph Axis

    /// Dashed reference lines inside the goniometer
    static let stereographAxisColor = Color(hex: 0x2A2A3A)
}
