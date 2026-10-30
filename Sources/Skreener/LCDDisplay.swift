import AppKit

/// The editor's status display, drawn like a retro LCD: a dark bezel around greenish glass, with a small title (the
/// tool or mode) and key at the top, the tool's usage or the live hint below them, and a status lamp on the right.
final class LCDDisplay: NSView {
    /// Top left: what is in use ("FILLED RECTANGLE").
    var title = "" { didSet { if title != oldValue { needsDisplay = true } } }
    /// Top right: the tool's key ("KEY R"), or empty.
    var detail = "" { didSet { if detail != oldValue { needsDisplay = true } } }
    /// The main line: how to use the tool, or what the pointer is doing right now.
    var message = "" { didSet { if message != oldValue { needsDisplay = true } } }
    /// The lamp: lit, with "LIVE", while `message` is a live hint; "IDLE" otherwise.
    var isLive = false { didSet { if isLive != oldValue { needsDisplay = true } } }

    static let ink = NSColor(srgbRed: 0.13, green: 0.16, blue: 0.10, alpha: 0.9)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func accessibilityValue() -> Any? { [title, message].filter { !$0.isEmpty }.joined(separator: ": ") }
    /// Clicks go through: it only shows.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // The bezel, with a light lip along its bottom.
        let outer = bounds.insetBy(dx: 0.5, dy: 0.5)
        let bezel = NSBezierPath(roundedRect: outer, xRadius: 7, yRadius: 7)
        NSGradient(starting: NSColor(white: dark ? 0.14 : 0.62, alpha: 1), ending: NSColor(white: dark ? 0.04 : 0.48, alpha: 1))?
            .draw(in: bezel, angle: isFlipped ? -90 : 90)
        NSColor.black.withAlphaComponent(dark ? 0.7 : 0.3).setStroke()
        bezel.lineWidth = 1
        bezel.stroke()

        // The glass: pale olive, a little darker at the top, with an inner shadow under the bezel.
        let glassRect = outer.insetBy(dx: 3, dy: 3)
        let glass = NSBezierPath(roundedRect: glassRect, xRadius: 4, yRadius: 4)
        NSGradient(starting: NSColor(srgbRed: 0.80, green: 0.83, blue: 0.72, alpha: 1),
                   ending: NSColor(srgbRed: 0.72, green: 0.76, blue: 0.64, alpha: 1))?.draw(in: glass, angle: isFlipped ? -90 : 90)
        NSGraphicsContext.saveGraphicsState()
        glass.addClip()
        let inner = NSShadow()
        inner.shadowColor = NSColor.black.withAlphaComponent(0.45)
        inner.shadowBlurRadius = 3
        inner.shadowOffset = NSSize(width: 0, height: -1)
        inner.set()
        let ring = NSBezierPath(rect: glassRect.insetBy(dx: -10, dy: -10))
        ring.append(glass.reversed)
        ring.windingRule = .evenOdd
        NSColor.black.setFill()
        ring.fill()
        NSGraphicsContext.restoreGraphicsState()

        // The segments' faint shadow on the glass behind them.
        let ghost = NSShadow()
        ghost.shadowColor = Self.ink.withAlphaComponent(0.18)
        ghost.shadowOffset = NSSize(width: 1, height: -1)
        ghost.shadowBlurRadius = 0
        let small = Self.attributes(size: 8.5, weight: .bold, kern: 1, shadow: ghost)
        let big = Self.attributes(size: 13, weight: .medium, kern: 0.3, shadow: ghost)

        let text = glassRect.insetBy(dx: 10, dy: 3)
        let topLine = NSRect(x: text.minX, y: isFlipped ? text.minY : text.maxY - 11, width: text.width, height: 11)
        let mainLine = NSRect(x: text.minX, y: isFlipped ? text.maxY - 17 : text.minY, width: text.width, height: 17)

        let status = (isLive ? "LIVE" : "IDLE") as NSString
        let statusSize = status.size(withAttributes: small)
        let detailSize = (detail as NSString).size(withAttributes: small)
        Self.draw(title.uppercased(), in: NSRect(x: topLine.minX, y: topLine.minY, width: topLine.width - detailSize.width - 16, height: topLine.height),
                  small)
        (detail as NSString).draw(at: NSPoint(x: topLine.maxX - detailSize.width, y: topLine.minY), withAttributes: small)

        // The lamp and its status at the right of the main line.
        let statusX = mainLine.maxX - statusSize.width
        let lamp = NSRect(x: statusX - 9, y: mainLine.midY - 2.5, width: 5, height: 5)
        (isLive ? Self.ink : Self.ink.withAlphaComponent(0.15)).setFill()
        NSBezierPath(ovalIn: lamp).fill()
        status.draw(at: NSPoint(x: statusX, y: mainLine.midY - statusSize.height / 2), withAttributes: small)
        Self.draw(message, in: NSRect(x: mainLine.minX, y: mainLine.minY, width: lamp.minX - 16 - mainLine.minX, height: mainLine.height), big)
    }

    private static func attributes(size: CGFloat, weight: NSFont.Weight, kern: CGFloat, shadow: NSShadow) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        return [.font: NSFont.monospacedSystemFont(ofSize: size, weight: weight), .foregroundColor: ink, .kern: kern,
                .shadow: shadow, .paragraphStyle: para]
    }

    private static func draw(_ s: String, in rect: NSRect, _ attrs: [NSAttributedString.Key: Any]) {
        guard rect.width > 0 else { return }
        (s as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }
}

extension Tool {
    /// How to use the tool, for the editor's status display: what a drag or click does, then a modifier tip and, for
    /// tools with variants, how to reach them.
    var usage: String {
        let base: String
        switch self {
        case .select: base = "Click an annotation to select it · drag to move it"
        case .rect, .filledRect, .ellipse: base = "Drag to draw"
        case .line, .arrow: base = "Drag from where it starts to where it ends"
        case .text: base = "Click to place text, then type"
        case .counter: base = "Click to drop the next number"
        case .pen, .highlighter: base = "Drag to draw freehand"
        case .pixelate, .blur: base = "Drag over what to hide"
        case .erase: base = "Drag over what to erase"
        case .redactText: base = "Type the words to find, then redact the matches"
        case .spotlight: base = "Drag over what to keep lit; the rest dims"
        case .magnifier: base = "Drag over the detail to enlarge"
        case .image: base = "Drag to move the image"
        case .ruler: base = "Drag to measure"
        }
        var parts = [base]
        if let tip = modifierTip { parts.append(tip) }
        if self == .rect || self == .arrow { parts.append("press and hold its button for variants") }
        return parts.joined(separator: " · ")
    }

    /// "KEY R" for the status display, or empty when the tool has no key.
    var keyLabel: String {
        Tool.shortcuts.first(where: { $0.value == self }).map { "KEY " + String($0.key).uppercased() } ?? ""
    }
}
