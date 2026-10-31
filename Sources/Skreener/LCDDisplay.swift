import AppKit

// The SK-1 kit's LCDs (#344; see `Retro`): the editor's status display, the recording bar's elapsed time, a one-line
// readout and a small chip, all olive glass in the LCD's ink.

/// The editor's status display, drawn like the SK-1's LCD: olive glass in a sunken bezel, with the tool or mode and
/// its key at the left, the tool's usage or the live hint in mono, the zoom in seven-segment digits and a status lamp.
final class LCDDisplay: NSView {
    /// Top left: what is in use ("FILLED RECTANGLE").
    var title = "" { didSet { if title != oldValue { needsDisplay = true } } }
    /// Under the title: the tool's key ("KEY R"), or empty.
    var detail = "" { didSet { if detail != oldValue { needsDisplay = true } } }
    /// The main line: how to use the tool, or what the pointer is doing right now.
    var message = "" { didSet { if message != oldValue { needsDisplay = true } } }
    /// The lamp: lit, with "LIVE", while `message` is a live hint; "IDLE" otherwise.
    var isLive = false { didSet { if isLive != oldValue { needsDisplay = true } } }
    /// The zoom in percent, in seven-segment digits; nil shows none.
    var zoomPercent: Int? { didSet { if zoomPercent != oldValue { needsDisplay = true } } }

    static let ink = Retro.color(Retro.lcdInk)

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
        let p = Retro.palette(for: self)
        // The bezel, with a light lip along its bottom.
        let outer = NSRect(x: bounds.minX, y: bounds.minY + (isFlipped ? 0 : 1), width: bounds.width, height: bounds.height - 1)
        let glassRect = Retro.drawLCD(in: outer, palette: p, flipped: isFlipped)

        // The segments' faint shadow on the glass behind them.
        let ghost = NSShadow()
        ghost.shadowColor = Self.ink.withAlphaComponent(0.15)
        ghost.shadowOffset = NSSize(width: 1, height: -1)
        ghost.shadowBlurRadius = 0
        let heading = Self.attributes(.systemFont(ofSize: 9.5, weight: .heavy), kern: 1.1, shadow: ghost)
        let small = Self.attributes(.systemFont(ofSize: 9, weight: .semibold), kern: 1, shadow: ghost, alpha: 0.75)
        let lampType = Self.attributes(.systemFont(ofSize: 9, weight: .heavy), kern: 1, shadow: ghost)
        let main = Self.attributes(Retro.mono(11.5, weight: .semibold), kern: 0.2, shadow: ghost)

        let text = glassRect.insetBy(dx: 12, dy: 0)
        /// The y that centres something `height` tall on the glass, moved `down` points down on screen.
        func centered(_ height: CGFloat, down: CGFloat = 0) -> CGFloat {
            text.midY - height / 2 + (isFlipped ? down : -down)
        }

        // Right to left: the lamp, the zoom digits, then the message after the title column.
        let status = NSAttributedString(string: isLive ? "LIVE" : "IDLE", attributes: lampType)
        let statusSize = status.size()
        let statusX = text.maxX - statusSize.width
        status.draw(at: NSPoint(x: statusX, y: centered(statusSize.height)))
        let lamp = NSRect(x: statusX - 9, y: text.midY - 2.5, width: 5, height: 5)
        Retro.drawLamp(in: lamp, color: Self.ink, lit: isLive, unlit: Self.ink.withAlphaComponent(0.15), glow: 0)
        var right = lamp.minX - 16

        if let zoom = zoomPercent {
            let digitHeight = max(min(22, glassRect.height - 14), 8), spacing: CGFloat = 2
            let percent = NSAttributedString(string: "%", attributes: Self.attributes(.systemFont(ofSize: 10, weight: .heavy),
                                                                                      kern: 0, shadow: ghost))
            let percentSize = percent.size()
            // The sign sits on the digits' baseline.
            percent.draw(at: NSPoint(x: right - percentSize.width, y: centered(percentSize.height, down: (digitHeight - percentSize.height) / 2)))
            let digits = SevenSegment.cells(zoom, count: 3)
            let width = SevenSegment.textWidth(digits, digitHeight: digitHeight, spacing: spacing)
            let x = right - percentSize.width - 3 - width
            SevenSegment.draw(digits, in: NSRect(x: x, y: text.midY - digitHeight / 2, width: width, height: digitHeight),
                              color: Self.ink, spacing: spacing, flipped: isFlipped)
            right = x - 16
        }

        // The title column: at least 150 pt, more for a long title, up to a third of the display.
        let titleString = NSAttributedString(string: title.uppercased(), attributes: heading)
        let detailString = NSAttributedString(string: detail.uppercased(), attributes: small)
        let column = min(max(150, max(titleString.size().width, detailString.size().width) + 4), text.width / 3)
        let titleH = titleString.size().height, detailH = detailString.size().height, lineGap: CGFloat = 2
        if detail.isEmpty {
            Self.draw(titleString, in: NSRect(x: text.minX, y: centered(titleH), width: column, height: titleH))
        } else {
            let block = titleH + lineGap + detailH
            Self.draw(titleString, in: NSRect(x: text.minX, y: centered(titleH, down: -(block - titleH) / 2), width: column, height: titleH))
            Self.draw(detailString, in: NSRect(x: text.minX, y: centered(detailH, down: (block - detailH) / 2), width: column, height: detailH))
        }

        let messageString = NSAttributedString(string: message, attributes: main)
        let mh = messageString.size().height
        let mx = text.minX + column + 16
        Self.draw(messageString, in: NSRect(x: mx, y: centered(mh), width: right - mx, height: mh))
    }

    private static func attributes(_ font: NSFont, kern: CGFloat, shadow: NSShadow, alpha: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        return [.font: font, .foregroundColor: ink.withAlphaComponent(alpha), .kern: kern, .shadow: shadow, .paragraphStyle: para]
    }

    private static func draw(_ s: NSAttributedString, in rect: NSRect) {
        guard rect.width > 0 else { return }
        s.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// The recording bar's LCD, after the timer's: a REC lamp that blinks (steady and "PAUSED" while paused) and what is
/// recorded ("MP4 60") along the top, the elapsed time in seven-segment digits under them.
final class ElapsedLCD: NSView {
    var time = "00:00" { didSet { if time != oldValue { needsDisplay = true } } }
    var detail = "" { didSet { if detail != oldValue { needsDisplay = true } } }
    var isPaused = false { didSet { if isPaused != oldValue { needsDisplay = true } } }
    /// The blink: lit or dimmed (ignored while paused); see `Retro.blinkLit`.
    var lampLit = true { didSet { if lampLit != oldValue { needsDisplay = true } } }

    /// The elapsed time, "MM:SS" (minutes go past 99 rather than wrap).
    static func elapsed(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// What the LCD says is recorded: "GIF", or "MP4" and the frame rate.
    static func formatLabel(gif: Bool, fps: Int) -> String { gif ? "GIF" : "MP4 \(fps)" }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Elapsed time")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 142, height: 62) }
    override func accessibilityValue() -> Any? { isPaused ? "\(time), paused" : time }
    /// Clicks go through to the chassis, which drags the bar.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let outer = NSRect(x: bounds.minX, y: bounds.minY + (isFlipped ? 0 : 1), width: bounds.width, height: bounds.height - 1)
        let glass = Retro.drawLCD(in: outer, palette: p, flipped: isFlipped)
        let ink = Retro.color(Retro.lcdInk)
        let inner = glass.insetBy(dx: 9, dy: 5)
        let rowHeight: CGFloat = 10
        let row = NSRect(x: inner.minX, y: isFlipped ? inner.minY : inner.maxY - rowHeight, width: inner.width, height: rowHeight)

        let type: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8, weight: .heavy), .foregroundColor: ink, .kern: 1]
        let lamp = NSRect(x: row.minX, y: row.midY - 3, width: 6, height: 6)
        if isPaused {
            Retro.drawLamp(in: lamp, color: ink, lit: false, unlit: ink.withAlphaComponent(0.4))
        } else {
            let red = Retro.color(Retro.recRed)
            Retro.drawLamp(in: lamp, color: red, lit: lampLit, unlit: red.withAlphaComponent(Retro.lampDimmed))
        }
        let state = NSAttributedString(string: isPaused ? "PAUSED" : "REC", attributes: type)
        state.draw(at: NSPoint(x: lamp.maxX + 4, y: row.midY - state.size().height / 2))
        var soft = type
        soft[.foregroundColor] = ink.withAlphaComponent(0.75)
        soft[.font] = NSFont.systemFont(ofSize: 8, weight: .semibold)
        let format = NSAttributedString(string: detail.uppercased(), attributes: soft)
        let formatSize = format.size()
        format.draw(at: NSPoint(x: row.maxX - formatSize.width, y: row.midY - formatSize.height / 2))

        // The digits fill what is left under the top row.
        let gap: CGFloat = 3
        let digitsArea = NSRect(x: inner.minX, y: isFlipped ? row.maxY + gap : inner.minY, width: inner.width,
                                height: inner.height - rowHeight - gap)
        let digitHeight = max(min(26, digitsArea.height), 8), spacing: CGFloat = 3
        let width = SevenSegment.textWidth(time, digitHeight: digitHeight, spacing: spacing)
        SevenSegment.draw(time, in: NSRect(x: digitsArea.midX - width / 2, y: digitsArea.midY - digitHeight / 2, width: width,
                                           height: digitHeight), color: ink, spacing: spacing, flipped: isFlipped)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// One line of mono text on LCD glass in a small bezel, cut short at the end when it doesn't fit (a status line).
final class LCDReadout: NSView {
    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }

    init(height: CGFloat = 30) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func accessibilityValue() -> Any? { text }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let outer = NSRect(x: bounds.minX, y: bounds.minY + (isFlipped ? 0 : 1), width: bounds.width, height: bounds.height - 1)
        let glass = Retro.drawLCD(in: outer, radius: 7, inset: 3, palette: p, flipped: isFlipped)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        var attrs = Retro.chipAttributes(size: 11)
        attrs[.paragraphStyle] = para
        let s = NSAttributedString(string: text, attributes: attrs)
        let h = s.size().height
        let rect = NSRect(x: glass.minX + 8, y: glass.midY - h / 2, width: max(glass.width - 16, 0), height: h)
        guard rect.width > 0 else { return }
        s.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A small olive LCD chip with mono text that only shows (a pin's zoom): `PillButton`'s `.lcd` look without the
/// button. `text` is spoken as its value.
final class LCDChip: NSView {
    private let label = NSTextField(labelWithString: "")
    var text: String {
        get { label.stringValue }
        set {
            label.attributedStringValue = NSAttributedString(string: newValue, attributes: [
                .font: Retro.mono(10, weight: .bold), .foregroundColor: Retro.color(Retro.lcdInk), .kern: 0.5,
            ])
            setAccessibilityValue(newValue)
        }
    }

    init(minWidth: CGFloat = 44, height: CGFloat = 20) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        Retro.drawChipGlass(bounds, radius: 3, brightness: Retro.palette(for: self).lcdBrightness, flipped: isFlipped)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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

    /// The tool's key in capitals ("R"), for its key's legend; nil when it has none.
    var shortcutLetter: String? {
        Tool.shortcuts.first(where: { $0.value == self }).map { String($0.key).uppercased() }
    }

    /// "KEY R" for the status display, or empty when the tool has no key.
    var keyLabel: String { shortcutLetter.map { "KEY " + $0 } ?? "" }
}
