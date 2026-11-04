import CoreGraphics
import CoreText
import Foundation

/// A frame around the screenshot (#271): a macOS window, a browser with an address bar, a MacBook, an iPhone or an
/// iPad, light or dark, drawn as vector paths. It sits inside the Background's padding and shadow.
///
/// The screenshot is never scaled, so annotations keep their coordinates. Window and browser chrome simply wraps the
/// screenshot's size; a device's screen has a fixed shape, so the screenshot is letterboxed inside the smallest screen
/// that holds it. `layout(around:)` is the pure geometry; drawing is further down.
public struct DeviceFrame: Equatable, Sendable {
    public enum Kind: Int, CaseIterable, Sendable {
        case none, macWindow, browser, macBook, iPhone, iPad

        public var name: String {
            switch self {
            case .none: return "None"
            case .macWindow: return "macOS Window"
            case .browser: return "Browser"
            case .macBook: return "MacBook"
            case .iPhone: return "iPhone"
            case .iPad: return "iPad"
            }
        }

        /// Width over height of the screen in portrait, for devices; nil for window chrome.
        public var portraitAspect: CGFloat? {
            switch self {
            case .iPhone: return 9 / 19.5
            case .iPad: return 3 / 4
            default: return nil
            }
        }
    }

    public static let defaultURL = "example.com"

    public var kind = Kind.none
    public var dark = false
    /// The address shown in the browser frame's bar.
    public var url = DeviceFrame.defaultURL

    public var isNone: Bool { kind == .none }

    /// Where everything goes for one screenshot area. Rects are in the canvas's coordinates (y up).
    public struct Layout: Equatable, Sendable {
        /// Everything the frame covers, including a MacBook's base.
        public var outer: CGRect
        /// Where the screenshot shows; it contains the screenshot area.
        public var screen: CGRect
        /// The main chrome shape: `outer`, or a MacBook's lid without its base.
        public var body: CGRect
        /// A MacBook's base under the lid.
        public var base: CGRect?
        /// Corners of `outer`'s body, and of the screen (square for window chrome, which only rounds the outside).
        public var outerRadius: CGFloat
        public var screenRadius: CGFloat
        /// The title or tool bar above the screen of a window or browser; zero height for devices.
        public var bar: CGRect
        /// The address field inside a browser's bar; nil when the image is too narrow for one.
        public var urlField: CGRect?
        /// The black margin between a device's body and its screen.
        public var bezel: CGFloat
        /// How much the chrome is enlarged for big screenshots.
        public var unit: CGFloat
    }

    /// Chrome sizes are in points for a normal window, and grow with very wide screenshots so they keep their look.
    public static func unit(forWidth width: CGFloat) -> CGFloat { min(max(width / 1200, 1), 3) }

    public func layout(around content: CGRect) -> Layout {
        let u = Self.unit(forWidth: content.width)
        var l = Layout(outer: content, screen: content, body: content, base: nil, outerRadius: 0, screenRadius: 0,
                       bar: .zero, urlField: nil, bezel: 0, unit: u)
        switch kind {
        case .none:
            break
        case .macWindow, .browser:
            let h = (kind == .macWindow ? 28 : 44) * u
            l.bar = CGRect(x: content.minX, y: content.maxY, width: content.width, height: h)
            l.outer = CGRect(x: content.minX, y: content.minY, width: content.width, height: content.height + h)
            l.body = l.outer
            l.outerRadius = 10 * u
            if kind == .browser {
                // Room on the left for the traffic lights, and the same on the right to keep the field centered.
                let width = min(l.bar.width * 0.5, l.bar.width - 2 * 80 * u)
                if width >= 60 * u {
                    let fh = 26 * u
                    l.urlField = CGRect(x: l.bar.midX - width / 2, y: l.bar.midY - fh / 2, width: width, height: fh)
                }
            }
        case .macBook, .iPhone, .iPad:
            let landscape = content.width >= content.height
            let ratio: CGFloat
            if let portrait = kind.portraitAspect { ratio = landscape ? 1 / portrait : portrait } else { ratio = 16 / 10 }
            l.screen = Self.screen(holding: content, ratio: ratio)
            let s = l.screen
            let m = min(s.width, s.height)
            switch kind {
            case .iPhone:
                l.bezel = 0.04 * m; l.screenRadius = 0.12 * m
                l.outer = s.insetBy(dx: -l.bezel, dy: -l.bezel); l.body = l.outer
                l.outerRadius = l.screenRadius + l.bezel
            case .iPad:
                l.bezel = 0.05 * m; l.screenRadius = 0.03 * m
                l.outer = s.insetBy(dx: -l.bezel, dy: -l.bezel); l.body = l.outer
                l.outerRadius = l.screenRadius + l.bezel
            default:
                let side = 0.028 * s.width, chin = 0.035 * s.width
                l.bezel = side; l.screenRadius = 0.004 * s.width
                l.body = CGRect(x: s.minX - side, y: s.minY - chin, width: s.width + 2 * side, height: s.height + side + chin)
                l.outerRadius = 0.02 * s.width
                let baseHeight = 0.03 * s.width, overhang = 0.04 * s.width
                let base = CGRect(x: l.body.minX - overhang, y: l.body.minY - baseHeight,
                                  width: l.body.width + 2 * overhang, height: baseHeight)
                l.base = base
                l.outer = l.body.union(base)
            }
        }
        return l
    }

    /// The smallest rect of width over height `ratio` that holds `content`, with the same center, in whole points.
    public static func screen(holding content: CGRect, ratio: CGFloat) -> CGRect {
        guard content.width > 0, content.height > 0, ratio > 0 else { return content }
        var w = content.width, h = content.height
        if w / h > ratio { h = w / ratio } else { w = h * ratio }
        w = ceil(w - 1e-6); h = ceil(h - 1e-6)
        let x = (content.midX - w / 2).rounded(.down), y = (content.midY - h / 2).rounded(.down)
        // Rounding must never leave the screenshot sticking out.
        return CGRect(x: x, y: y, width: max(w, ceil(content.maxX - x)), height: max(h, ceil(content.maxY - y)))
    }

    // MARK: Saving (with the editor document)

    public var plist: [String: Any] { ["kind": kind.rawValue, "dark": dark, "url": url] }

    public init() {}

    /// A frame read back from `plist`; unknown or missing values keep their defaults.
    public init(plist d: [String: Any]) {
        if let k = d["kind"] as? Int, let kind = Kind(rawValue: k) { self.kind = kind }
        dark = d["dark"] as? Bool ?? dark
        url = d["url"] as? String ?? url
    }

    // MARK: Drawing

    // Contexts are y-up, like the Mac canvas: an iOS caller must flip its context (UIKit's are y-down) first.

    private func hex(_ v: Int) -> CGColor { Draw.srgb(v) }

    /// The color of the frame's body, which the canvas also uses under the Background's shadow and inset.
    public var bodyColor: CGColor {
        switch kind {
        case .macWindow: return dark ? hex(0x323234) : hex(0xE9E9EB)
        case .browser: return dark ? hex(0x2B2B2D) : hex(0xF2F2F4)
        default: return dark ? hex(0x1D1D1F) : hex(0xD9DADD)
        }
    }

    /// The outline the canvas clips the screenshot to, along with `screenPath`.
    public func outerPath(_ l: Layout) -> CGPath { Draw.roundedRect(l.outer, radius: l.outerRadius) }

    public func screenPath(_ l: Layout) -> CGPath {
        l.screenRadius > 0 ? Draw.roundedRect(l.screen, radius: l.screenRadius) : CGPath(rect: l.screen, transform: nil)
    }

    /// Draws the frame's body, bar and details; the screenshot goes on top of its screen afterwards.
    public func drawChrome(_ l: Layout, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let u = l.unit
        let edge = CGColor(gray: dark ? 1 : 0, alpha: dark ? 0.16 : 0.2)
        switch kind {
        case .none:
            return
        case .macWindow, .browser:
            let shape = outerPath(l)
            Draw.fill(shape, bodyColor, in: ctx)
            ctx.saveGState()
            Draw.clip(to: shape, in: ctx)
            // A hairline between the bar and the screenshot.
            ctx.setFillColor(edge); ctx.fill(CGRect(x: l.bar.minX, y: l.bar.minY, width: l.bar.width, height: 1))
            ctx.restoreGState()
            for (i, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
                let d = 12 * u
                let cx = l.bar.minX + (20 + 20 * CGFloat(i)) * u
                let dot = Draw.oval(in: CGRect(x: cx - d / 2, y: l.bar.midY - d / 2, width: d, height: d))
                Draw.fill(dot, hex(color), in: ctx)
                Draw.stroke(dot, CGColor(gray: 0, alpha: 0.12), width: 0.5, in: ctx)
            }
            if let field = l.urlField { drawURLField(field, unit: u, in: ctx) }
            let border = Draw.roundedRect(l.outer.insetBy(dx: 0.5, dy: 0.5), radius: l.outerRadius)
            Draw.stroke(border, edge, width: 1, in: ctx)
        case .iPhone, .iPad, .macBook:
            // A MacBook's lid reaches down under its base, which covers the lid's bottom corners.
            let body = l.base == nil ? outerPath(l)
                : Draw.roundedRect(CGRect(x: l.body.minX, y: l.body.minY - l.outerRadius, width: l.body.width,
                                          height: l.body.height + l.outerRadius), radius: l.outerRadius)
            Draw.fill(body, bodyColor, in: ctx)
            // The black glass around the screen.
            let glass = l.screen.insetBy(dx: -l.bezel * 0.8, dy: -l.bezel * 0.8)
            let black = CGColor(gray: 0, alpha: 1)
            if let base = l.base {
                Draw.fill(Draw.roundedRect(glass, radius: 0.01 * l.screen.width), black, in: ctx)
                // Camera.
                let c = 0.004 * l.screen.width
                Draw.fill(Draw.oval(in: CGRect(x: l.screen.midX - c, y: (l.body.maxY + l.screen.maxY) / 2 - c,
                                               width: 2 * c, height: 2 * c)), hex(0x2A2A2E), in: ctx)
                // The base, a little darker than the lid, with the notch for lifting it.
                let baseShape = Draw.roundedRect(base, radius: base.height * 0.45)
                Draw.fill(baseShape, dark ? hex(0x2A2A2D) : hex(0xC6C7CB), in: ctx)
                Draw.stroke(baseShape, edge, width: 1, in: ctx)
                let nw = 0.14 * l.screen.width, nh = base.height * 0.4
                Draw.fill(Draw.roundedRect(CGRect(x: base.midX - nw / 2, y: base.maxY - nh, width: nw, height: nh), radius: nh / 2),
                          dark ? hex(0x1D1D1F) : hex(0xAEAFB3), in: ctx)
            } else {
                Draw.fill(Draw.roundedRect(glass, radius: l.screenRadius + l.bezel * 0.8), black, in: ctx)
                Draw.stroke(body, edge, width: 1, in: ctx)
            }
        }
    }

    /// The address pill and its text: the system font, centered, cut off with an ellipsis when it doesn't fit.
    private func drawURLField(_ field: CGRect, unit u: CGFloat, in ctx: CGContext) {
        Draw.fill(Draw.roundedRect(field, radius: 6 * u), dark ? hex(0x1B1B1D) : hex(0xE3E3E6), in: ctx)
        let font = CTFontCreateUIFontForLanguage(.system, 12.5 * u, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 12.5 * u, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font,
                                      kCTForegroundColorAttributeName: dark ? hex(0xB4B4B8) : hex(0x5C5C60)]
        func line(_ s: String) -> CTLine {
            CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary))
        }
        let width = max(field.width - 16 * u, 0)
        var text = line(url)
        if CTLineGetTypographicBounds(text, nil, nil, nil) > Double(width) {
            text = CTLineCreateTruncatedLine(text, Double(width), .end, line("\u{2026}")) ?? text
        }
        // One line's height centered on the field, the baseline an ascent below its top (as AppKit lays it out).
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font), leading = CTFontGetLeading(font)
        let h = ascent + descent + leading
        let textWidth = CGFloat(CTLineGetTypographicBounds(text, nil, nil, nil))
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: field.minX + 8 * u + (width - textWidth) / 2, y: field.midY + h / 2 - ascent)
        CTLineDraw(text, ctx)
        ctx.restoreGState()
    }
}
