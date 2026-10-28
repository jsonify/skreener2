import AppKit
import UniformTypeIdentifiers

/// Step Recorder's guide (#242): the recorded steps in order, each with its screenshot and editable text. Steps move up
/// and down, get deleted, or open in the editor (Annotate), whose edits show up here; the guide exports to Markdown with
/// an images folder, one HTML file, or a PDF with a page per step.
final class StepGuideWindow: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate,
                             NSTextFieldDelegate {
    @MainActor private static var current: StepGuideWindow?

    @MainActor static func show() {
        let guide = current ?? StepGuideWindow()
        current = guide
        guide.reload()
        if guide.window?.isVisible != true { guide.window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        guide.showWindow(nil)
        guide.window?.makeKeyAndOrderFront(nil)
    }

    private struct WeakEditor { weak var editor: EditorWindowController? }

    private let table = NSTableView()
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString:
        "No steps yet. Choose Start Step Recorder in Skreener's menu, then click through the task: each click becomes a step.")
    private let recordButton = NSButton(title: "", target: nil, action: nil)
    private let exportButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let newButton = NSButton(title: "New Guide…", target: nil, action: nil)
    /// Small copies of the step screenshots, by step and the file's modification date.
    private var thumbnails: [UUID: (date: Date, image: NSImage)] = [:]
    private var editors: [UUID: WeakEditor] = [:]
    private var store: StepStore { StepStore.shared }

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Step Guide"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 540, height: 320)
        super.init(window: w)
        w.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("step"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 120
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let hint = NSTextField(wrappingLabelWithString:
            "Edit a step's text (**bold** marks a name; Return finishes, ⌥Return adds a line), move it, annotate its "
                + "screenshot or delete it, then export the guide.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor

        newButton.target = self
        newButton.action = #selector(newGuide)
        newButton.toolTip = "Delete every step and start over"
        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        exportButton.addItem(withTitle: "Export")
        for (title, action) in [("Markdown and Images…", #selector(exportMarkdown)), ("HTML…", #selector(exportHTML)),
                                ("PDF…", #selector(exportPDF))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            exportButton.menu?.addItem(item)
        }
        countLabel.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: 12)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: [newButton, countLabel, spacer, recordButton, exportButton])
        bar.spacing = 10

        let content = NSView()
        [hint, scroll, emptyLabel, bar].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; content.addSubview($0) }
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -40),
            bar.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        w.contentView = content

        store.onChange = { [weak self] in self?.reload() }
        let nc = NotificationCenter.default
        // The editor saved a step's screenshot (it saves like a history capture).
        nc.addObserver(forName: .skreenerHistoryChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        nc.addObserver(forName: .skreenerStepRecorderChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshControls() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func reload() {
        // Finish a text edit first, so it isn't lost.
        if window?.firstResponder is NSTextView { window?.makeFirstResponder(nil) }
        let ids = Set(store.steps.map(\.id))
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        table.reloadData()
        refreshControls()
    }

    private func refreshControls() {
        let n = store.steps.count
        countLabel.stringValue = n == 1 ? "1 step" : "\(n) steps"
        emptyLabel.isHidden = n > 0
        exportButton.isEnabled = n > 0
        newButton.isEnabled = n > 0
        recordButton.title = StepRecorder.shared.isOn ? "Stop Recording" : "Record Steps"
    }

    private func thumbnail(for step: RecordedStep) -> NSImage? {
        let url = store.png(for: step)
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if let t = thumbnails[step.id], t.date == date { return t.image }
        guard let image = CaptureHistory.thumbnail(url, maxPixels: 400) else { return nil }
        thumbnails[step.id] = (date, image)
        return image
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { store.steps.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard store.steps.indices.contains(row) else { return nil }
        let step = store.steps[row]
        let view = tableView.makeView(withIdentifier: StepRow.identifier, owner: self) as? StepRow ?? StepRow(target: self)
        view.show(number: row + 1, count: store.steps.count, text: step.text, image: thumbnail(for: step))
        return view
    }

    /// The step whose row holds `view`.
    private func step(of view: NSView) -> (index: Int, step: RecordedStep)? {
        let row = table.row(for: view)
        guard store.steps.indices.contains(row) else { return nil }
        return (row, store.steps[row])
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let found = step(of: field) else { return }
        store.setText(field.stringValue, for: found.step.id)
    }

    @objc fileprivate func moveStepUp(_ sender: NSButton) { if let s = step(of: sender) { store.move(s.step.id, by: -1) } }
    @objc fileprivate func moveStepDown(_ sender: NSButton) { if let s = step(of: sender) { store.move(s.step.id, by: 1) } }

    @objc fileprivate func deleteStep(_ sender: NSButton) {
        guard let s = step(of: sender) else { return }
        editors[s.step.id]?.editor?.close()
        editors[s.step.id] = nil
        store.delete(s.step.id)
    }

    /// Opens the step's screenshot in the editor, marker and earlier annotations still editable; edits save back into
    /// the step as they are made.
    @objc fileprivate func annotate(_ sender: NSButton) {
        guard let s = step(of: sender) else { return }
        if let open = editors[s.step.id]?.editor { open.reveal(); return }
        let png = store.png(for: s.step)
        let saved = CaptureHistory.document(for: png)
        guard let image = saved?.base ?? NSImage(contentsOf: png) else { NSSound.beep(); return }
        let editor = EditorWindowController(image: image, title: "Step \(s.index + 1)")
        editor.attachHistory(png, document: saved?.document)
        editors[s.step.id] = WeakEditor(editor: editor)
        editor.present(on: window?.screen)
    }

    @MainActor @objc private func toggleRecording() { StepRecorder.shared.toggle() }

    @objc private func newGuide() {
        let alert = NSAlert()
        alert.messageText = "Delete all \(store.steps.count) steps?"
        alert.informativeText = "Their screenshots are deleted too. Export the guide first to keep it."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for (_, open) in editors { open.editor?.close() }
        editors = [:]
        store.clear()
    }

    // MARK: Export

    /// Where to export: a save panel for `type`, named "Step Guide" to start with.
    private func exportURL(_ type: UTType, ext: String) -> URL? {
        if window?.firstResponder is NSTextView { window?.makeFirstResponder(nil) }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "Step Guide." + ext
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func exported(_ url: URL, _ ok: Bool) {
        if ok {
            Notifier.confirm("Guide exported", detail: url.lastPathComponent, file: url)
        } else {
            Notifier.problem("Couldn't export the guide", detail: "Check that the folder can be written to.")
        }
    }

    @objc private func exportMarkdown() {
        guard let url = exportURL(UTType(filenameExtension: "md") ?? .plainText, ext: "md") else { return }
        let title = url.deletingPathExtension().lastPathComponent
        let folderName = title + " images"
        let folder = url.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
        let fm = FileManager.default
        var steps: [StepGuideExport.Step] = []
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for (i, step) in store.steps.enumerated() {
                let name = StepGuideExport.imageName(i + 1, of: store.steps.count)
                let target = folder.appendingPathComponent(name)
                try? fm.removeItem(at: target)
                try fm.copyItem(at: store.png(for: step), to: target)
                steps.append(StepGuideExport.Step(text: step.text, image: folderName + "/" + name))
            }
            try StepGuideExport.markdown(title: title, steps: steps).write(to: url, atomically: true, encoding: .utf8)
            exported(url, true)
        } catch {
            NSLog("Guide export failed: \(error)")
            exported(url, false)
        }
    }

    @objc private func exportHTML() {
        guard let url = exportURL(.html, ext: "html") else { return }
        let steps = store.steps.map { step in
            let data = (try? Data(contentsOf: store.png(for: step))) ?? Data()
            return StepGuideExport.Step(text: step.text, image: "data:image/png;base64," + data.base64EncodedString())
        }
        let html = StepGuideExport.html(title: url.deletingPathExtension().lastPathComponent, steps: steps)
        exported(url, (try? html.write(to: url, atomically: true, encoding: .utf8)) != nil)
    }

    @objc private func exportPDF() {
        guard let url = exportURL(.pdf, ext: "pdf") else { return }
        let steps = store.steps.map { (text: $0.text, png: store.png(for: $0)) }
        exported(url, Self.writePDF(title: url.deletingPathExtension().lastPathComponent, steps: steps, to: url))
    }

    /// A US Letter page per step: its number and text, then its screenshot scaled to fit. The title heads the first page.
    private static func writePDF(title: String, steps: [(text: String, png: URL)], to url: URL) -> Bool {
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(url as CFURL, mediaBox: &page, nil) else { return false }
        let margin: CGFloat = 48, width = page.width - margin * 2
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        func draw(_ text: NSAttributedString, top: CGFloat) -> CGFloat {
            let h = ceil(text.boundingRect(with: NSSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin]).height)
            text.draw(with: NSRect(x: margin, y: top - h, width: width, height: h), options: [.usesLineFragmentOrigin])
            return top - h
        }
        for (i, step) in steps.enumerated() {
            ctx.beginPDFPage(nil)
            var top = page.height - margin
            if i == 0 {
                top = draw(NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 24),
                                                                          .foregroundColor: NSColor.black]), top: top) - 18
            }
            top = draw(attributed(step.text, number: i + 1), top: top) - 14
            if let image = NSImage(contentsOf: step.png) {
                image.draw(in: StepGuideExport.fit(image.size, in: CGRect(x: margin, y: margin, width: width, height: top - margin)))
            }
            ctx.endPDFPage()
        }
        NSGraphicsContext.restoreGraphicsState()
        ctx.closePDF()
        return true
    }

    /// "3. Click **Save**" with the number and the bold parts in bold.
    private static func attributed(_ text: String, number: Int) -> NSAttributedString {
        let size: CGFloat = 15
        let plain: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black]
        var bold = plain
        bold[.font] = NSFont.boldSystemFont(ofSize: size)
        let out = NSMutableAttributedString(string: "\(number). ", attributes: bold)
        for seg in StepText.segments(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            out.append(NSAttributedString(string: seg.text, attributes: seg.bold ? bold : plain))
        }
        return out
    }
}

/// One step in the guide: number, screenshot, text, and its buttons.
private final class StepRow: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("StepRow")

    private let number = NSTextField(labelWithString: "")
    private let thumb = NSImageView()
    private let field = NSTextField(string: "")
    private let up: NSButton
    private let down: NSButton

    init(target: StepGuideWindow) {
        func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(),
                             target: target, action: action)
            b.bezelStyle = .texturedRounded
            b.toolTip = tip
            return b
        }
        up = button("chevron.up", "Move Up", #selector(StepGuideWindow.moveStepUp(_:)))
        down = button("chevron.down", "Move Down", #selector(StepGuideWindow.moveStepDown(_:)))
        let annotate = NSButton(title: "Annotate", target: target, action: #selector(StepGuideWindow.annotate(_:)))
        annotate.bezelStyle = .texturedRounded
        annotate.toolTip = "Open the screenshot in the editor"
        let delete = button("trash", "Delete Step", #selector(StepGuideWindow.deleteStep(_:)))
        super.init(frame: .zero)
        identifier = Self.identifier

        number.font = .boldSystemFont(ofSize: 15)
        number.alignment = .right
        thumb.imageScaling = .scaleProportionallyDown
        thumb.wantsLayer = true
        thumb.layer?.borderWidth = 1
        thumb.layer?.borderColor = NSColor.separatorColor.cgColor
        field.font = .systemFont(ofSize: 14)
        field.usesSingleLineMode = false
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.delegate = target
        field.placeholderString = "What to do in this step"

        let moves = NSStackView(views: [up, down])
        moves.spacing = 4
        let actions = NSStackView(views: [annotate, delete])
        actions.spacing = 4
        let buttons = NSStackView(views: [moves, actions])
        buttons.orientation = .vertical
        buttons.alignment = .trailing
        buttons.spacing = 6
        [number, thumb, field, buttons].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        NSLayoutConstraint.activate([
            number.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            number.widthAnchor.constraint(equalToConstant: 28),
            number.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            thumb.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 8),
            thumb.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            thumb.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            thumb.widthAnchor.constraint(equalToConstant: 160),
            field.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 12),
            field.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            field.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            buttons.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            buttons.topAnchor.constraint(equalTo: topAnchor, constant: 10),
        ])
        buttons.setContentHuggingPriority(.required, for: .horizontal)
        buttons.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(number n: Int, count: Int, text: String, image: NSImage?) {
        number.stringValue = "\(n)."
        field.stringValue = text
        thumb.image = image
        up.isEnabled = n > 1
        down.isEnabled = n < count
    }
}
