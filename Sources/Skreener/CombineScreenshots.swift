import AppKit

/// Combine Screenshots (#273): 2 to 9 captures, from the editor's tabs or the capture history, laid out in a row,
/// column or grid on a new canvas. Each capture becomes an Add Image layer, so it can still be moved, and the
/// Background tool works on the result like on any other screenshot.
enum CombineScreenshots {
    /// A capture the sheet offers. `image` loads the full picture, and only for the ones picked.
    struct Candidate {
        let title: String
        let thumbnail: NSImage?
        let image: () -> NSImage?
        var selected = false
    }

    /// The blank canvas and where each picture goes on it (bottom-left origin, like the editor's canvas).
    struct Composition {
        let base: NSImage
        let layers: [(image: NSImage, frame: NSRect)]
    }

    /// Shows the sheet on `window`, or as its own dialog when there is no editor window (the history panel).
    static func present(_ candidates: [Candidate], from window: NSWindow?) {
        guard candidates.count >= CombineLayout.countRange.lowerBound else {
            Notifier.problem("Nothing to combine", detail: "Combine Screenshots needs at least two captures: open more tabs or take more captures.")
            return
        }
        let form = CombineForm(candidates: candidates)
        let alert = NSAlert()
        alert.messageText = "Combine Screenshots"
        alert.informativeText = "Pick \(CombineLayout.countRange.lowerBound) to \(CombineLayout.countRange.upperBound) captures. They open as movable images on a new canvas."
        alert.accessoryView = form
        let combine = alert.addButton(withTitle: "Combine")
        alert.addButton(withTitle: "Cancel")
        form.onValidityChange = { combine.isEnabled = $0 }
        combine.isEnabled = form.isValid
        if let window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { openCombined(form.picked, form.options) }
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { openCombined(form.picked, form.options) }
        }
    }

    /// Candidates for the capture history's newest `count` captures.
    static func historyCandidates(count: Int) -> [Candidate] {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return CaptureHistory.entries().prefix(count).map { e in
            candidate(url: e.url, title: f.localizedString(for: e.date, relativeTo: Date()))
        }
    }

    /// A candidate for a capture saved as a file (a history capture is saved flattened, annotations included).
    static func candidate(url: URL, title: String) -> Candidate {
        Candidate(title: title, thumbnail: CaptureHistory.thumbnail(url, maxPixels: 120), image: { NSImage(contentsOf: url) })
    }

    /// Lays `images` out and opens the result as a new editor tab, saved to the capture history like other editor docs.
    static func openCombined(_ picked: [Candidate], _ options: CombineLayout.Options) {
        let images = picked.compactMap { $0.image() }.filter { $0.size.width > 0 && $0.size.height > 0 }
        guard images.count == picked.count, CombineLayout.countRange.contains(images.count) else {
            Notifier.problem("Couldn't read every capture", detail: "A picked capture is missing or empty.")
            return
        }
        guard let composition = compose(images, options) else {
            Notifier.problem("The combined image is too large",
                             detail: "Each side can be at most \(CombineLayout.maxSide) pixels: use a smaller gutter or margin, or fewer captures.")
            return
        }
        let editor = EditorWindowController(image: composition.base, title: "Combined")
        // Attached before the layers go on, so adding them is an edit that gets saved with the capture.
        if let entry = CaptureHistory.add(composition.base) { editor.attachHistory(entry) }
        editor.addImageLayers(composition.layers)
        editor.present()
    }

    /// Pixels per point of `img` (2 for a Retina screenshot).
    static func pixelDensity(of img: NSImage) -> CGFloat {
        var r = CGRect(origin: .zero, size: img.size)
        guard img.size.width > 0, let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil) else { return 1 }
        return max(1, CGFloat(cg.width) / img.size.width)
    }

    /// The transparent canvas, as dense as the densest capture so none of them loses pixels, and the layers. Gutter and
    /// margin are in pixels. Nil if the canvas would be past `CombineLayout.maxSide`.
    static func compose(_ images: [NSImage], _ options: CombineLayout.Options) -> Composition? {
        let density = images.map(pixelDensity(of:)).max() ?? 1
        var points = options
        points.gutter /= density
        points.margin /= density
        let layout = CombineLayout.layout(sizes: images.map(\.size), options: points)
        let width = Int((layout.size.width * density).rounded(.up)), height = Int((layout.size.height * density).rounded(.up))
        let limit = CombineLayout.maxSide
        guard width > 0, height > 0, width <= limit, height <= limit,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cg = ctx.makeImage() else { return nil }
        let base = NSImage(cgImage: cg, size: NSSize(width: CGFloat(width) / density, height: CGFloat(height) / density))
        // The layout counts from the top; the canvas from the bottom.
        let layers: [(image: NSImage, frame: NSRect)] = zip(images, layout.frames).map { img, f in
            (image: img, frame: NSRect(x: f.minX, y: base.size.height - f.maxY, width: f.width, height: f.height))
        }
        return Composition(base: base, layers: layers)
    }
}

/// The body of the Combine Screenshots sheet: a checkbox per capture (with a thumbnail), then the layout, alignment,
/// gutter and margin. `isValid` says whether 2 to 9 are ticked; `onValidityChange` follows it.
final class CombineForm: NSView, NSTextFieldDelegate {
    private let candidates: [CombineScreenshots.Candidate]
    private var boxes: [NSButton] = []
    private let arrangement = NSSegmentedControl(labels: CombineLayout.Arrangement.allCases.map(\.title),
                                                 trackingMode: .selectOne, target: nil, action: nil)
    private let alignment = NSPopUpButton(frame: .zero, pullsDown: false)
    private let gutterField = NSTextField()
    private let marginField = NSTextField()
    private let status = NSTextField(labelWithString: "")
    var onValidityChange: ((Bool) -> Void)?

    init(candidates: [CombineScreenshots.Candidate]) {
        self.candidates = candidates
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 330))

        // At most nine start ticked.
        var ticked = 0
        let rows = candidates.map { c -> NSStackView in
            let box = NSButton(checkboxWithTitle: c.title, target: self, action: #selector(selectionChanged))
            let on = c.selected && ticked < CombineLayout.countRange.upperBound
            if on { ticked += 1 }
            box.state = on ? .on : .off
            boxes.append(box)
            let thumb = NSImageView(image: c.thumbnail ?? NSImage())
            thumb.imageScaling = .scaleProportionallyUpOrDown
            thumb.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([thumb.widthAnchor.constraint(equalToConstant: 56),
                                         thumb.heightAnchor.constraint(equalToConstant: 36)])
            let row = NSStackView(views: [box, thumb])
            row.distribution = .fill
            row.spacing = 8
            return row
        }
        let list = NSStackView(views: rows)
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 6
        list.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .bezelBorder
        scroll.documentView = list
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: scroll.contentView.topAnchor, constant: 6),
            list.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor, constant: 8),
            list.trailingAnchor.constraint(lessThanOrEqualTo: scroll.contentView.trailingAnchor, constant: -8),
        ])

        arrangement.selectedSegment = CombineLayout.Arrangement.row.rawValue
        for a in CombineLayout.Alignment.allCases { alignment.addItem(withTitle: a.title) }
        alignment.selectItem(at: CombineLayout.Alignment.center.rawValue)
        let defaults = CombineLayout.Options()
        for (field, value) in [(gutterField, defaults.gutter), (marginField, defaults.margin)] {
            field.stringValue = String(Int(value))
            field.alignment = .right
            field.delegate = self
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 56).isActive = true
        }
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor

        func labeled(_ title: String, _ views: [NSView]) -> NSStackView {
            let label = NSTextField(labelWithString: title)
            label.alignment = .right
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 64).isActive = true
            let row = NSStackView(views: [label] + views)
            row.spacing = 8
            return row
        }
        let spacing = labeled("Spacing", [NSTextField(labelWithString: "Gutter"), gutterField, NSTextField(labelWithString: "Margin"),
                                          marginField, NSTextField(labelWithString: "px")])
        let stack = NSStackView(views: [scroll, labeled("Layout", [arrangement]), labeled("Align", [alignment]), spacing, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 190),
            widthAnchor.constraint(equalToConstant: 360),
        ])
        refreshStatus()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// The ticked captures, in the order listed.
    var picked: [CombineScreenshots.Candidate] {
        zip(candidates, boxes).filter { $0.1.state == .on }.map { $0.0 }
    }

    var isValid: Bool { CombineLayout.countRange.contains(picked.count) }

    var options: CombineLayout.Options {
        CombineLayout.Options(arrangement: CombineLayout.Arrangement(rawValue: arrangement.selectedSegment) ?? .row,
                              gutter: CGFloat(max(0, gutterField.integerValue)), margin: CGFloat(max(0, marginField.integerValue)),
                              alignment: CombineLayout.Alignment(rawValue: alignment.indexOfSelectedItem) ?? .center)
    }

    @objc private func selectionChanged() { refreshStatus() }

    func controlTextDidChange(_ obj: Notification) { refreshStatus() }

    /// Counts the ticked captures, and stops a tenth being ticked.
    private func refreshStatus() {
        let n = picked.count
        let full = n >= CombineLayout.countRange.upperBound
        for b in boxes { b.isEnabled = !full || b.state == .on }
        status.stringValue = n < CombineLayout.countRange.lowerBound ? "\(n) picked: pick at least \(CombineLayout.countRange.lowerBound)."
            : "\(n) picked."
        onValidityChange?(isValid)
    }
}
