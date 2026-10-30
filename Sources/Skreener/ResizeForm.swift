import AppKit

/// The fields of the editor's Resize Image sheet (#122): width and height in pixels or points, Keep proportions, and
/// percent presets. `pixels` is the size picked; `onValidityChange` says whether it can be used.
final class ResizeForm: NSView, NSTextFieldDelegate {
    let widthField = NSTextField()
    private let heightField = NSTextField()
    private let unitPopup = RetroSegmented()
    private let keepProportions = RetroUI.toggle("Keep proportions", isOn: true, target: nil, action: nil)
    private let presets = PillPopUp(pullsDown: true, height: RetroUI.textKeyHeight, style: .keycap)
    private let problem = NSTextField(labelWithString: "")
    private let original: (width: Int, height: Int)
    /// Pixels per point (2 for a Retina screenshot).
    private let density: CGFloat
    private(set) var pixels: (width: Int, height: Int)
    var onValidityChange: ((Bool) -> Void)?

    private var inPoints: Bool { unitPopup.selectedTag() == 1 }

    init(original: (width: Int, height: Int), density: CGFloat) {
        self.original = original
        self.density = max(density, 0.01)
        pixels = original
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 96))

        for f in [widthField, heightField] {
            f.delegate = self
            f.alignment = .right
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 72).isActive = true
        }
        unitPopup.addItem("px", tag: 0, help: "Pixels")
        unitPopup.addItem("pt", tag: 1, help: "Points")
        unitPopup.isEnabled = abs(density - 1) > 0.01   // points and pixels are the same at 1×
        unitPopup.target = self; unitPopup.action = #selector(unitChanged)
        keepProportions.target = self; keepProportions.action = #selector(proportionsToggled(_:))
        presets.toolTip = "Scale the image by a percentage"
        presets.addItem(withTitle: "Scale")
        for pct in [25, 50, 75, 200] {
            presets.addItem(withTitle: "\(pct)%")
            presets.lastItem?.tag = pct
            presets.lastItem?.target = self
            presets.lastItem?.action = #selector(presetPicked(_:))
        }
        problem.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        problem.textColor = .systemRed

        let times = RetroLabel(text: "×", tone: .ink, size: 13)
        let sizeRow = NSStackView(views: [widthField, times, heightField, unitPopup])
        sizeRow.spacing = 6
        sizeRow.alignment = .centerY
        let optionsRow = NSStackView(views: [keepProportions, presets])
        optionsRow.spacing = 12
        optionsRow.alignment = .centerY
        let stack = NSStackView(views: [sizeRow, optionsRow, problem])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
        ])
        showPixels()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func text(_ px: Int) -> String {
        guard inPoints else { return "\(px)" }
        let pt = CGFloat(px) / density
        return pt == pt.rounded() ? "\(Int(pt))" : String(format: "%.1f", pt)
    }

    private func showPixels() {
        widthField.stringValue = text(pixels.width)
        heightField.stringValue = text(pixels.height)
        validate()
    }

    private func validate() {
        let message = ImageOps.resizeProblem(width: pixels.width, height: pixels.height)
        problem.stringValue = message ?? (inPoints ? "\(pixels.width) × \(pixels.height) px" : "")
        problem.textColor = message == nil ? .secondaryLabelColor : .systemRed
        onValidityChange?(message == nil)
    }

    /// The pixels a typed value stands for (0 when it isn't a number).
    private func pixels(from field: NSTextField) -> Int {
        let v = Double(field.stringValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
        return max(0, Int((inPoints ? v * Double(density) : v).rounded()))
    }

    func controlTextDidChange(_ note: Notification) {
        guard let field = note.object as? NSTextField else { return }
        let isWidth = field === widthField
        let v = pixels(from: field)
        if isWidth { pixels.width = v } else { pixels.height = v }
        if keepProportions.isOn {
            let other = ImageOps.proportional(v, isWidth: isWidth, original: original)
            if isWidth { pixels.height = other; heightField.stringValue = text(other) } else {
                pixels.width = other; widthField.stringValue = text(other)
            }
        }
        validate()
    }

    @objc private func unitChanged() { showPixels() }

    @objc private func proportionsToggled(_ sender: PillButton) {
        sender.isOn.toggle()
        guard keepProportions.isOn else { return }
        pixels.height = ImageOps.proportional(pixels.width, isWidth: true, original: original)
        showPixels()
    }

    @objc private func presetPicked(_ item: NSMenuItem) {
        let f = Double(item.tag) / 100
        pixels = (max(1, Int((Double(original.width) * f).rounded())), max(1, Int((Double(original.height) * f).rounded())))
        keepProportions.isOn = true
        showPixels()
    }
}
