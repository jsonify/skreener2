import CoreGraphics
import CoreText
import Foundation

/// Clean status bar (#408): replaces an iPhone screenshot's status bar with a tidy one (9:41, full signal, full Wi-Fi,
/// full battery, nothing else), so the battery level, carrier, real time and notification icons aren't shared.
public enum StatusBar {
    /// Where iOS puts the status bar items.
    public enum Style: Sendable {
        /// Dynamic Island: the time centred in the left ear, signal, Wi-Fi and battery in the right one.
        case island
        /// A notch: laid out like `.island`, around the notch.
        case notch
        /// Home-button phones: signal and Wi-Fi left, the time centred, the battery right.
        case classic
    }

    /// A screenshot's status bar, in pixels (top-left origin, like `CGImage.cropping`).
    public struct Layout: Equatable, Sendable {
        /// The area that is repainted.
        public var bar: CGRect
        /// Pixels per point (2 or 3).
        public var scale: CGFloat
        public var style: Style
        /// The Dynamic Island or notch, which the items keep clear of; nil for `.classic`.
        public var cutout: CGRect?
        /// The height (from the top) the items are centred on.
        public var midY: CGFloat

        public init(bar: CGRect, scale: CGFloat, style: Style, cutout: CGRect?, midY: CGFloat) {
            self.bar = bar
            self.scale = scale
            self.style = style
            self.cutout = cutout
            self.midY = midY
        }
    }

    /// Where each item goes, in pixels (top-left origin). `time` is the box the digits' outlines are centred in.
    public struct Glyphs: Equatable, Sendable {
        public var time: CGRect
        public var signal: CGRect
        public var wifi: CGRect
        public var battery: CGRect
    }

    /// One portrait screenshot size. Lengths in points.
    struct Model: Sendable {
        let width: Int, height: Int, scale: CGFloat, style: Style
        /// The status bar's height.
        let bar: CGFloat
        /// The items' centre line, from the top.
        let midY: CGFloat
        /// The island's or notch's size and top edge (centred across the screen).
        let cutout: CGSize?
        let cutoutTop: CGFloat
    }

    // Sources: status bar heights from Apple Developer Forums threads 662466 and 715417 (44 pt on X/XS/11 Pro,
    // 47 on 12–14, 48 on XR/11, 54 on the Dynamic Island phones up to the 16, 20 on home-button phones) and
    // useyourloaf.com's "iPhone 14/16 Screen Sizes" (54 pt bar, 59 pt top inset on the 14 Pro–16 family). The
    // 14 Pro island (126 × 37.33 pt, 11.33 pt from the top) is from Apple's iOS 16 design templates as commonly quoted.
    // Values marked [verify] are estimates (scaled from the physical cutout size or guessed from screenshots) to be
    // checked against a real screenshot.
    static let table: [Model] = [
        // iPhone SE 2/3, 6–8.
        Model(width: 750, height: 1334, scale: 2, style: .classic, bar: 20, midY: 10, cutout: nil, cutoutTop: 0),
        // 6–8 Plus.
        Model(width: 1242, height: 2208, scale: 3, style: .classic, bar: 20, midY: 10, cutout: nil, cutoutTop: 0),
        // X, XS, 11 Pro. Notch 209 × 30 [verify]; midY [verify].
        Model(width: 1125, height: 2436, scale: 3, style: .notch, bar: 44, midY: 18,
              cutout: CGSize(width: 209, height: 30), cutoutTop: 0),
        // XR, 11. Notch [verify] (the X's, scaled to 2x's 326 ppi); midY [verify].
        Model(width: 828, height: 1792, scale: 2, style: .notch, bar: 48, midY: 19,
              cutout: CGSize(width: 224, height: 32), cutoutTop: 0),
        // XS Max, 11 Pro Max. Notch as the X [verify]; midY [verify].
        Model(width: 1242, height: 2688, scale: 3, style: .notch, bar: 44, midY: 18,
              cutout: CGSize(width: 209, height: 30), cutoutTop: 0),
        // 12 mini, 13 mini. Bar is the 50 pt top inset (the status bar reports 44) [verify]; notch [verify]; midY [verify].
        Model(width: 1080, height: 2340, scale: 3, style: .notch, bar: 50, midY: 21,
              cutout: CGSize(width: 218, height: 32), cutoutTop: 0),
        // 12, 12 Pro, 13, 13 Pro, 14, 16e. The 12's notch (the 13's is narrower) [verify]; midY [verify].
        Model(width: 1170, height: 2532, scale: 3, style: .notch, bar: 47, midY: 20,
              cutout: CGSize(width: 210, height: 32), cutoutTop: 0),
        // 12 Pro Max, 13 Pro Max, 14 Plus. Notch [verify]; midY [verify].
        Model(width: 1284, height: 2778, scale: 3, style: .notch, bar: 47, midY: 20,
              cutout: CGSize(width: 210, height: 32), cutoutTop: 0),
        // 14 Pro, 15, 15 Pro, 16. Items centred on the island.
        Model(width: 1179, height: 2556, scale: 3, style: .island, bar: 54, midY: 30,
              cutout: CGSize(width: 126, height: 37.33), cutoutTop: 11.33),
        // 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus.
        Model(width: 1290, height: 2796, scale: 3, style: .island, bar: 54, midY: 30,
              cutout: CGSize(width: 126, height: 37.33), cutoutTop: 11.33),
        // 16 Pro, 17, 17 Pro. Bar 62 [verify]; island position [verify].
        Model(width: 1206, height: 2622, scale: 3, style: .island, bar: 62, midY: 32.5,
              cutout: CGSize(width: 125, height: 37), cutoutTop: 14),
        // 16 Pro Max, 17 Pro Max. Bar 62 [verify]; island position [verify].
        Model(width: 1320, height: 2868, scale: 3, style: .island, bar: 62, midY: 32.5,
              cutout: CGSize(width: 125, height: 37), cutoutTop: 14),
        // iPhone Air. Bar [verify]; island position [verify].
        Model(width: 1260, height: 2736, scale: 3, style: .island, bar: 68, midY: 38.5,
              cutout: CGSize(width: 125, height: 37), cutoutTop: 20),
    ]

    /// The status bar of a full, portrait iPhone screenshot `w` × `h` pixels; nil for any other size (landscape,
    /// iPad, photos, cropped images).
    public static func layout(forPixelWidth w: Int, height h: Int) -> Layout? {
        guard let m = table.first(where: { $0.width == w && $0.height == h }) else { return nil }
        let s = m.scale
        let cutout = m.cutout.map { c in
            CGRect(x: (CGFloat(w) - c.width * s) / 2, y: m.cutoutTop * s, width: c.width * s, height: c.height * s)
        }
        return Layout(bar: CGRect(x: 0, y: 0, width: CGFloat(w), height: (m.bar * s).rounded()), scale: s,
                      style: m.style, cutout: cutout, midY: m.midY * s)
    }

    // Item sizes in points, after iOS 16's status bar.
    static let timeFont: CGFloat = 17, classicTimeFont: CGFloat = 12
    /// "9:41" in 17 pt SF semibold: about 37 pt wide; the digits are 12 pt tall (cap height).
    static let timeSize = CGSize(width: 37, height: 12)
    static let signalSize = CGSize(width: 17, height: 11)
    static let wifiSize = CGSize(width: 15.5, height: 11)
    static let batterySize = CGSize(width: 27.33, height: 13)
    static let iconGap: CGFloat = 5
    /// Classic phones' icons, a little smaller than in the taller bars [verify].
    static let classicIconScale: CGFloat = 0.85
    /// How far the items keep from the screen's side [verify].
    static func sideInset(_ style: Style) -> CGFloat {
        switch style {
        case .island: return 6
        case .notch: return 12
        case .classic: return 6
        }
    }

    /// Where `layout`'s items go: island and notch phones centre the time in the left ear and the icons in the right
    /// one (smaller when an ear is too narrow); classic phones put the icons at the sides and the time in the middle.
    public static func glyphs(for layout: Layout) -> Glyphs {
        let s = layout.scale, bar = layout.bar, mid = layout.midY
        let inset = sideInset(layout.style) * s
        func box(_ size: CGSize, _ k: CGFloat, centerX: CGFloat) -> CGRect {
            CGRect(x: centerX - size.width * s * k / 2, y: mid - size.height * s * k / 2,
                   width: size.width * s * k, height: size.height * s * k)
        }
        func row(_ k: CGFloat, from x: CGFloat) -> (signal: CGRect, wifi: CGRect, battery: CGRect) {
            let signal = box(signalSize, k, centerX: x + signalSize.width * s * k / 2)
            let wifi = box(wifiSize, k, centerX: signal.maxX + iconGap * s * k + wifiSize.width * s * k / 2)
            let battery = box(batterySize, k, centerX: wifi.maxX + iconGap * s * k + batterySize.width * s * k / 2)
            return (signal, wifi, battery)
        }

        guard layout.style != .classic, let cutout = layout.cutout else {
            let k = classicIconScale
            let left = row(k, from: bar.minX + inset)
            let battery = box(batterySize, k, centerX: bar.maxX - inset - batterySize.width * s * k / 2)
            let time = box(timeSize, classicTimeFont / timeFont, centerX: bar.midX)
            return Glyphs(time: time, signal: left.signal, wifi: left.wifi, battery: battery)
        }
        let leftEar = (bar.minX + inset)...max(bar.minX + inset, cutout.minX)
        let rightEar = min(cutout.maxX, bar.maxX - inset)...(bar.maxX - inset)
        func width(_ ear: ClosedRange<CGFloat>) -> CGFloat { ear.upperBound - ear.lowerBound }
        func center(_ ear: ClosedRange<CGFloat>) -> CGFloat { (ear.upperBound + ear.lowerBound) / 2 }

        let timeK = min(1, width(leftEar) / (timeSize.width * s))
        let time = box(timeSize, timeK, centerX: center(leftEar))
        let rowWidth = (signalSize.width + wifiSize.width + batterySize.width + 2 * iconGap) * s
        let k = min(1, width(rightEar) / rowWidth)
        let icons = row(k, from: center(rightEar) - rowWidth * k / 2)
        return Glyphs(time: time, signal: icons.signal, wifi: icons.wifi, battery: icons.battery)
    }
}
