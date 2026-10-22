import Foundation

/// How the editor's color picker writes a color (#108): the format is a setting, used for copying, the live pixel
/// readout and Tab while typing a label.
enum ColorFormat: String, CaseIterable {
    case hex, hexNoHash, css, rgbUnit, android, uiColor, csharp, oklch

    var title: String {
        switch self {
        case .hex: return "HEX"
        case .hexNoHash: return "HEX without #"
        case .css: return "CSS rgba()"
        case .rgbUnit: return "RGB 0–1"
        case .android: return "Android"
        case .uiColor: return "UIColor"
        case .csharp: return "C#"
        case .oklch: return "OKLCH"
        }
    }

    /// The text copied for `c`: `#FFC200`, `FFC200`, `rgba(255, 194, 0, 1)`, `(1.00, 0.76, 0.00)`, `0xFFFFC200`,
    /// `UIColor(red: 1.00, green: 0.76, blue: 0.00, alpha: 1.00)`, `Color.FromArgb(255, 194, 0)` or
    /// `oklch(84.60% 0.173 85.6)`.
    func string(for c: RGBColor) -> String {
        let r = RGBColor.byte(c.r), g = RGBColor.byte(c.g), b = RGBColor.byte(c.b), a = RGBColor.byte(c.a)
        let hex = String(format: "%02lX%02lX%02lX", r, g, b)
        func unit(_ v: Double) -> String { String(format: "%.2f", min(max(v, 0), 1)) }
        switch self {
        case .hex: return "#" + hex
        case .hexNoHash: return hex
        case .css: return "rgba(\(r), \(g), \(b), \(Self.trimmed(c.a)))"
        case .rgbUnit: return "(\(unit(c.r)), \(unit(c.g)), \(unit(c.b)))"
        case .android: return String(format: "0x%02lX", a) + hex
        case .uiColor: return "UIColor(red: \(unit(c.r)), green: \(unit(c.g)), blue: \(unit(c.b)), alpha: \(unit(c.a)))"
        case .csharp: return a == 255 ? "Color.FromArgb(\(r), \(g), \(b))" : "Color.FromArgb(\(a), \(r), \(g), \(b))"
        case .oklch: return "oklch(\(Self.oklchValues(c)))"
        }
    }

    /// The text shown in the editor's pixel readout: like `string(for:)`, but OKLCH without the `oklch()` around it.
    func display(for c: RGBColor) -> String {
        self == .oklch ? Self.oklchValues(c) : string(for: c)
    }

    /// `L% C H`, e.g. `84.60% 0.173 85.6`; grays (no chroma) get hue 0.
    private static func oklchValues(_ c: RGBColor) -> String {
        let (l, chroma, hue) = oklchComponents(c)
        let h = chroma < 0.0005 ? 0 : hue
        return String(format: "%.2f%% %.3f %.1f", l * 100, chroma, h)
    }

    /// OKLCH (Björn Ottosson's OKLab in polar form): lightness 0–1, chroma, hue in degrees 0–360.
    static func oklchComponents(_ c: RGBColor) -> (l: Double, c: Double, h: Double) {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = lin(c.r), g = lin(c.g), b = lin(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        var hue = atan2(bb, a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return (lightness, hypot(a, bb), hue)
    }

    /// An alpha without trailing zeros: 1, 0.5, 0.25.
    private static func trimmed(_ v: Double) -> String {
        var s = String(format: "%.2f", min(max(v, 0), 1))
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
