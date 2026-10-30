import AppKit

/// Help → Keyboard Shortcuts…, and ? in the editor: a searchable list of every tool and shortcut.
@MainActor enum ShortcutSheet {
    private static var current: ShortcutSheetController?

    /// From the menu: a window of its own. Opening it again brings the open one forward.
    static func show() {
        if let open = current, open.parent == nil {
            NSApp.activate(ignoringOtherApps: true)
            open.window.makeKeyAndOrderFront(nil)
            return
        }
        let controller = ShortcutSheetController(parent: nil)
        current = controller
        NSApp.activate(ignoringOtherApps: true)   // an accessory app is not frontmost when a menu item is chosen
        controller.window.center()
        controller.window.makeKeyAndOrderFront(nil)
        controller.focusSearch()
    }

    /// From the editor: a sheet on its window.
    static func show(from parent: NSWindow) {
        guard parent.attachedSheet == nil else { return }
        let controller = ShortcutSheetController(parent: parent)
        current = controller
        parent.beginSheet(controller.window)
        controller.focusSearch()
    }

    fileprivate static func closed(_ controller: ShortcutSheetController) {
        if current === controller { current = nil }
    }
}

/// Esc closes the panel.
private final class ShortcutWindow: NSWindow {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override var canBecomeKey: Bool { true }
}

@MainActor private final class ShortcutSheetController: NSObject, NSSearchFieldDelegate, NSWindowDelegate {
    let window: ShortcutWindow
    let parent: NSWindow?
    private let search = NSSearchField()
    private let columns = NSStackView()
    private let sections = ShortcutCatalog.sections()

    init(parent: NSWindow?) {
        self.parent = parent
        window = ShortcutWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                                styleMask: parent == nil ? [.titled, .closable] : [.titled],
                                backing: .buffered, defer: false)
        super.init()
        window.title = "Keyboard Shortcuts"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.onCancel = { [weak self] in self?.close() }
        window.setContentSize(NSSize(width: 760, height: 600))
        window.contentMinSize = NSSize(width: 560, height: 360)
        build()
        reload()
    }

    func focusSearch() { window.makeFirstResponder(search) }

    func close() {
        if let parent { parent.endSheet(window) } else { window.close() }
        ShortcutSheet.closed(self)
    }

    func windowWillClose(_ notification: Notification) { ShortcutSheet.closed(self) }

    // MARK: Layout

    private func build() {
        search.placeholderString = "Search shortcuts"
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false
        search.setAccessibilityLabel("Search shortcuts")

        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = 36
        columns.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(columns)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let done = RetroUI.key("Done", variant: .orange, height: 28, target: self, action: #selector(doneClicked))
        done.translatesAutoresizingMaskIntoConstraints = false

        let header = RetroLabel(caption: "Keyboard Shortcuts")

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        // The chassis behind the header, the search field and the Done key; the list stays on it, as plain text.
        let content: NSView
        let top: NSLayoutYAxisAnchor
        if parent == nil {
            let chassis = RetroUI.useChassis(window)
            content = chassis
            top = RetroUI.contentTop(of: window, in: chassis)
        } else {
            content = ChassisView()
            window.contentView = content
            top = content.topAnchor
        }
        [header, search, scroll, divider, done].forEach(content.addSubview)
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: top, constant: 14),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            search.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: divider.topAnchor),
            divider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: done.topAnchor, constant: -12),
            done.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            done.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            columns.topAnchor.constraint(equalTo: document.topAnchor, constant: 8),
            columns.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            columns.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            columns.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
        ])
    }

    @objc private func doneClicked() { close() }

    private func reload() {
        columns.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let shown = ShortcutCatalog.filter(sections, matching: search.stringValue)
        guard !shown.isEmpty else {
            let none = RetroUI.hint("No shortcuts match “\(search.stringValue)”.", size: 13)
            columns.addArrangedSubview(none)
            return
        }
        let (left, right) = ShortcutCatalog.columns(shown)
        for group in [left, right] { columns.addArrangedSubview(makeColumn(group)) }
    }

    private func makeColumn(_ sections: [ShortcutSection]) -> NSStackView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 7
        for (n, section) in sections.enumerated() {
            let header = RetroLabel(caption: section.title)
            column.addArrangedSubview(header)
            column.setCustomSpacing(8, after: header)
            for entry in section.entries {
                let row = makeRow(entry)
                column.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
            }
            if n < sections.count - 1, let last = column.arrangedSubviews.last { column.setCustomSpacing(22, after: last) }
        }
        return column
    }

    private func makeRow(_ entry: ShortcutEntry) -> NSView {
        let text = NSMutableAttributedString(string: entry.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        if !entry.note.isEmpty {
            text.append(NSAttributedString(string: "  " + entry.note, attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        let title = NSTextField(labelWithAttributedString: text)
        title.lineBreakMode = .byTruncatingTail
        title.toolTip = entry.note.isEmpty ? entry.title : entry.title + ": " + entry.note
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let caps = NSStackView(views: entry.keys.map { KeyCap($0) })
        caps.orientation = .horizontal
        caps.spacing = 3
        caps.setContentHuggingPriority(.required, for: .horizontal)
        caps.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [title, caps])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.setAccessibilityLabel("\(entry.title): \(entry.keys.joined(separator: " "))")
        return row
    }

    // MARK: Search

    func controlTextDidChange(_ obj: Notification) { reload() }

    /// Esc clears the search first, and closes the panel when it is already empty.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        if search.stringValue.isEmpty { close() } else { search.stringValue = ""; reload() }
        return true
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// One key drawn as a small cream key cap, like the keys on the toolbars.
private final class KeyCap: NSView {
    private let label: NSTextField

    init(_ key: String) {
        label = NSTextField(labelWithString: key)
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        translatesAutoresizingMaskIntoConstraints = false
        // The face is the top 22 pt; the 2 pt skirt is under it.
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            heightAnchor.constraint(equalToConstant: 24),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 26),
        ])
        refreshInk()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refreshInk() { label.textColor = Retro.color(Retro.palette(for: self).keyInk) }

    override func draw(_ dirtyRect: NSRect) {
        let colors = Retro.keyColors(.cream, Retro.palette(for: self))
        Retro.drawKey(in: bounds, radius: 5, colors: colors, down: false, flipped: isFlipped)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshInk()
        needsDisplay = true
    }
}
