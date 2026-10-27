import AppKit

/// A frame around the screenshot (#271): a macOS window, a browser with an address bar, a MacBook, an iPhone or an
/// iPad, light or dark, drawn as vector paths. It sits inside the Background's padding and shadow.
///
/// The screenshot is never scaled, so annotations keep their coordinates. Window and browser chrome simply wraps the
/// screenshot's size; a device's screen has a fixed shape, so the screenshot is letterboxed inside the smallest screen
/// that holds it. `layout(around:)` is the pure geometry; drawing is further down.
struct DeviceFrame: Equatable {
    enum Kind: Int, CaseIterable {
        case none, macWindow, browser, macBook, iPhone, iPad

        var name: String {
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
        var portraitAspect: CGFloat? {
            switch self {
            case .iPhone: return 9 / 19.5
            case .iPad: return 3 / 4
            default: return nil
            }
        }
    }

    static let defaultURL = "example.com"

    var kind = Kind.none
    var dark = false
    /// The address shown in the browser frame's bar.
    var url = DeviceFrame.defaultURL

    var isNone: Bool { kind == .none }

    /// Where everything goes for one screenshot area. Rects are in the canvas's coordinates (y up).
    struct Layout: Equatable {
        /// Everything the frame covers, including a MacBook's base.
        var outer: CGRect
        /// Where the screenshot shows; it contains the screenshot area.
        var screen: CGRect
        /// The main chrome shape: `outer`, or a MacBook's lid without its base.
        var body: CGRect
        /// A MacBook's base under the lid.
        var base: CGRect?
        /// Corners of `outer`'s body, and of the screen (square for window chrome, which only rounds the outside).
        var outerRadius: CGFloat
        var screenRadius: CGFloat
        /// The title or tool bar above the screen of a window or browser; zero height for devices.
        var bar: CGRect
        /// The address field inside a browser's bar; nil when the image is too narrow for one.
        var urlField: CGRect?
        /// The black margin between a device's body and its screen.
        var bezel: CGFloat
        /// How much the chrome is enlarged for big screenshots.
        var unit: CGFloat
    }

    /// Chrome sizes are in points for a normal window, and grow with very wide screenshots so they keep their look.
    static func unit(forWidth width: CGFloat) -> CGFloat { min(max(width / 1200, 1), 3) }

    func layout(around content: CGRect) -> Layout {
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
    static func screen(holding content: CGRect, ratio: CGFloat) -> CGRect {
        guard content.width > 0, content.height > 0, ratio > 0 else { return content }
        var w = content.width, h = content.height
        if w / h > ratio { h = w / ratio } else { w = h * ratio }
        w = ceil(w - 1e-6); h = ceil(h - 1e-6)
        let x = (content.midX - w / 2).rounded(.down), y = (content.midY - h / 2).rounded(.down)
        // Rounding must never leave the screenshot sticking out.
        return CGRect(x: x, y: y, width: max(w, ceil(content.maxX - x)), height: max(h, ceil(content.maxY - y)))
    }

    // MARK: Saving (with the editor document)

    var plist: [String: Any] { ["kind": kind.rawValue, "dark": dark, "url": url] }

    init() {}

    /// A frame read back from `plist`; unknown or missing values keep their defaults.
    init(plist d: [String: Any]) {
        if let k = d["kind"] as? Int, let kind = Kind(rawValue: k) { self.kind = kind }
        dark = d["dark"] as? Bool ?? dark
        url = d["url"] as? String ?? url
    }

    // MARK: Drawing

    private func hex(_ v: Int) -> NSColor { Background.hex(v) }

    /// The color of the frame's body, which the canvas also uses under the Background's shadow and inset.
    var bodyColor: NSColor {
        switch kind {
        case .macWindow: return dark ? hex(0x323234) : hex(0xE9E9EB)
        case .browser: return dark ? hex(0x2B2B2D) : hex(0xF2F2F4)
        default: return dark ? hex(0x1D1D1F) : hex(0xD9DADD)
        }
    }

    /// The outline the canvas clips the screenshot to, along with `screenPath`.
    func outerPath(_ l: Layout) -> NSBezierPath {
        NSBezierPath(roundedRect: l.outer, xRadius: l.outerRadius, yRadius: l.outerRadius)
    }

    func screenPath(_ l: Layout) -> NSBezierPath {
        l.screenRadius > 0 ? NSBezierPath(roundedRect: l.screen, xRadius: l.screenRadius, yRadius: l.screenRadius)
                           : NSBezierPath(rect: l.screen)
    }

    /// Draws the frame's body, bar and details; the screenshot goes on top of its screen afterwards.
    func drawChrome(_ l: Layout) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let u = l.unit
        let edge = (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.16 : 0.2)
        switch kind {
        case .none:
            return
        case .macWindow, .browser:
            let shape = outerPath(l)
            bodyColor.setFill(); shape.fill()
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            // A hairline between the bar and the screenshot.
            edge.setFill(); NSRect(x: l.bar.minX, y: l.bar.minY, width: l.bar.width, height: 1).fill()
            NSGraphicsContext.restoreGraphicsState()
            for (i, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
                let d = 12 * u
                let cx = l.bar.minX + (20 + 20 * CGFloat(i)) * u
                let dot = NSBezierPath(ovalIn: NSRect(x: cx - d / 2, y: l.bar.midY - d / 2, width: d, height: d))
                hex(color).setFill(); dot.fill()
                NSColor.black.withAlphaComponent(0.12).setStroke(); dot.lineWidth = 0.5; dot.stroke()
            }
            if let field = l.urlField { drawURLField(field, unit: u) }
            let border = NSBezierPath(roundedRect: l.outer.insetBy(dx: 0.5, dy: 0.5),
                                      xRadius: l.outerRadius, yRadius: l.outerRadius)
            edge.setStroke(); border.lineWidth = 1; border.stroke()
        case .iPhone, .iPad, .macBook:
            // A MacBook's lid reaches down under its base, which covers the lid's bottom corners.
            let body = l.base == nil ? outerPath(l)
                : NSBezierPath(roundedRect: CGRect(x: l.body.minX, y: l.body.minY - l.outerRadius, width: l.body.width,
                                                   height: l.body.height + l.outerRadius),
                               xRadius: l.outerRadius, yRadius: l.outerRadius)
            bodyColor.setFill(); body.fill()
            // The black glass around the screen.
            let glass = l.screen.insetBy(dx: -l.bezel * 0.8, dy: -l.bezel * 0.8)
            NSColor.black.setFill()
            if let base = l.base {
                let r = 0.01 * l.screen.width
                NSBezierPath(roundedRect: glass, xRadius: r, yRadius: r).fill()
                // Camera.
                let c = 0.004 * l.screen.width
                hex(0x2A2A2E).setFill()
                NSBezierPath(ovalIn: NSRect(x: l.screen.midX - c, y: (l.body.maxY + l.screen.maxY) / 2 - c,
                                            width: 2 * c, height: 2 * c)).fill()
                // The base, a little darker than the lid, with the notch for lifting it.
                let baseShape = NSBezierPath(roundedRect: base, xRadius: base.height * 0.45, yRadius: base.height * 0.45)
                (dark ? hex(0x2A2A2D) : hex(0xC6C7CB)).setFill(); baseShape.fill()
                edge.setStroke(); baseShape.lineWidth = 1; baseShape.stroke()
                let nw = 0.14 * l.screen.width, nh = base.height * 0.4
                (dark ? hex(0x1D1D1F) : hex(0xAEAFB3)).setFill()
                NSBezierPath(roundedRect: NSRect(x: base.midX - nw / 2, y: base.maxY - nh, width: nw, height: nh),
                             xRadius: nh / 2, yRadius: nh / 2).fill()
            } else {
                let r = l.screenRadius + l.bezel * 0.8
                NSBezierPath(roundedRect: glass, xRadius: r, yRadius: r).fill()
                edge.setStroke(); body.lineWidth = 1; body.stroke()
            }
        }
    }

    private func drawURLField(_ field: CGRect, unit u: CGFloat) {
        let pill = NSBezierPath(roundedRect: field, xRadius: 6 * u, yRadius: 6 * u)
        (dark ? hex(0x1B1B1D) : hex(0xE3E3E6)).setFill(); pill.fill()
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: url, attributes: [
            .font: NSFont.systemFont(ofSize: 12.5 * u),
            .foregroundColor: dark ? hex(0xB4B4B8) : hex(0x5C5C60),
            .paragraphStyle: style,
        ])
        let h = text.size().height
        text.draw(in: NSRect(x: field.minX + 8 * u, y: field.midY - h / 2, width: max(field.width - 16 * u, 0), height: h))
    }
}
