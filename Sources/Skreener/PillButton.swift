import AppKit

/// A capsule button in the style of iOS: filled with the accent colour, or a translucent tint over the dark bar; an
/// SF Symbol with an optional title (no title makes it a circle). Dims while pressed.
final class PillButton: NSButton {
    enum Style { case filled, tinted }

    /// Space between the symbol and the title, the same on every pill button. The symbol and title are laid out
    /// here rather than by the button cell, whose own spacing is wider and varies with the content.
    static let iconGap: CGFloat = 5
    /// The dark capsule the buttons sit on (the scrolling-capture bar, the editor's tab row).
    static let barColor = NSColor(white: 0.12, alpha: 0.94)
    static let barBorderColor = NSColor.white.withAlphaComponent(0.15)
    /// The `.tinted` fill: a translucent white over the dark bar.
    static let tintColor = NSColor.white.withAlphaComponent(0.16)

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let content = NSStackView()
    private let run: () -> Void
    private let style: Style
    private var pressed = false { didSet { applyColors() } }
    private var widthConstraint: NSLayoutConstraint?

    init(title: String?, symbol: String, style: Style, run: @escaping () -> Void) {
        self.run = run
        self.style = style
        super.init(frame: .zero)
        isBordered = false
        self.title = ""
        wantsLayer = true
        layer?.cornerCurve = .continuous
        icon.contentTintColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        content.addArrangedSubview(icon)
        content.addArrangedSubview(label)
        content.spacing = Self.iconGap
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        content.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        content.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        setContent(title: title, symbol: symbol)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setContent(title: String?, symbol: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(config)
        label.stringValue = title ?? ""
        label.isHidden = title == nil   // the stack leaves hidden views out, gap included
        setAccessibilityLabel(title ?? toolTip)
        widthConstraint?.isActive = false
        // Room either side of the content, or a circle when there is only a symbol.
        widthConstraint = title == nil ? widthAnchor.constraint(equalToConstant: 30)
                                       : widthAnchor.constraint(equalToConstant: content.fittingSize.width + 28)
        widthConstraint?.isActive = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Clicks on the symbol or title belong to the button.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        super.mouseDown(with: event)   // tracks the click until the button is released
        pressed = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        let base: NSColor = style == .filled ? .controlAccentColor : Self.tintColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (pressed ? base.blended(withFraction: 0.3, of: .black) ?? base : base).cgColor
        }
    }

    @objc private func fire() { run() }
}
