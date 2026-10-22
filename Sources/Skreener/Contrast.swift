import Foundation

/// Contrast between two colors (#109), the way accessibility guidelines measure it.
enum Contrast {
    enum Method: String, CaseIterable {
        /// WCAG 2: a ratio from 1:1 to 21:1.
        case wcag
        /// APCA (the candidate for WCAG 3): a lightness contrast Lc from about -108 to 106; negative for light text
        /// on a dark background.
        case apca
    }

    /// The WCAG 2 contrast ratio, 1 to 21 (the order of the colors does not matter).
    static func wcag(_ a: RGBColor, _ b: RGBColor) -> Double {
        let la = a.luminance, lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// What a WCAG 2 ratio passes: AAA (7), AA (4.5) or AA for large text and UI (3).
    static func wcagRating(_ ratio: Double) -> String {
        // Rounded down to two decimals, so 4.499 doesn't show as 4.50 and pass.
        let r = (ratio * 100).rounded(.down) / 100
        if r >= 7 { return "AAA" }
        if r >= 4.5 { return "AA" }
        if r >= 3 { return "AA Large" }
        return "Fail"
    }

    /// APCA's Lc for `text` on `background` (SAPC-APCA 0.0.98G-4g constants). Black on white is about 106, white on
    /// black about -108.
    static func apca(text: RGBColor, background: RGBColor) -> Double {
        func y(_ c: RGBColor) -> Double {
            0.2126729 * pow(c.r, 2.4) + 0.7151522 * pow(c.g, 2.4) + 0.0721750 * pow(c.b, 2.4)
        }
        // Soft-clamps near-black, where screens and eyes stop telling shades apart.
        func clamped(_ v: Double) -> Double { v > 0.022 ? v : v + pow(0.022 - v, 1.414) }
        let yt = clamped(y(text)), yb = clamped(y(background))
        guard abs(yb - yt) >= 0.0005 else { return 0 }
        if yb > yt {
            let sapc = (pow(yb, 0.56) - pow(yt, 0.57)) * 1.14
            return sapc < 0.1 ? 0 : (sapc - 0.027) * 100
        }
        let sapc = (pow(yb, 0.65) - pow(yt, 0.62)) * 1.14
        return sapc > -0.1 ? 0 : (sapc + 0.027) * 100
    }

    /// What an APCA Lc is enough for (by its size, whichever polarity), after APCA's bronze-level guidance.
    static func apcaRating(_ lc: Double) -> String {
        let v = abs(lc)
        if v >= 90 { return "Any text" }
        if v >= 75 { return "Body text" }
        if v >= 60 { return "Content text" }
        if v >= 45 { return "Large text" }
        if v >= 30 { return "Spot text" }
        if v >= 15 { return "Non-text" }
        return "Fail"
    }

    /// One line for the editor: `4.48:1 · AA Large` or `Lc 71 · Content text`.
    static func summary(text: RGBColor, background: RGBColor, method: Method) -> String {
        switch method {
        case .wcag:
            let ratio = wcag(text, background)
            return String(format: "%.2f:1", (ratio * 100).rounded(.down) / 100) + " · " + wcagRating(ratio)
        case .apca:
            let lc = apca(text: text, background: background)
            return String(format: "Lc %.0f", lc) + " · " + apcaRating(lc)
        }
    }
}
