import AppKit

/// Capture Table's scratch pad (#248): the table as read, in a grid whose cells can be fixed (double-click one, or
/// select it and press Return), and below it what will be copied in the chosen format (CSV, TSV or Markdown). Copy to
/// Clipboard (⌘Return) copies it and closes the pad; Esc or the close button closes it without copying. The format
/// picked here becomes the default for the next table.
final class TableScratchPad: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    @MainActor private static var current: TableScratchPad?

    /// Shows `grid` in the pad, centered on `screen`, replacing any table it held.
    @MainActor static func show(_ grid: TableText.Grid, on screen: NSScreen?) {
        let pad = current ?? TableScratchPad()
        current = pad
        pad.load(grid)
        if pad.window?.isVisible != true, let window = pad.window {
            let area = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
            window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        pad.showWindow(nil)
        pad.window?.makeKeyAndOrderFront(nil)
        pad.window?.makeFirstResponder(pad.table)
    }

    private var grid: TableText.Grid = []
    private let table = PadTableView()
    private let preview = NSTextView()
    private let count = RetroUI.hint()
    private let formatMenu = RetroUI.menuKey(tip: "What the table is copied as", target: nil, action: nil)

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Captured Table"
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 480, height: 320)
        super.init(window: w)
        w.delegate = self

        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnReordering = false
        table.onCancel = { [weak self] in self?.close() }
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true
        tableScroll.borderType = .bezelBorder

        preview.isEditable = false
        preview.isSelectable = true
        preview.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        preview.textContainerInset = NSSize(width: 6, height: 6)
        preview.isVerticallyResizable = true
        preview.isHorizontallyResizable = true
        preview.textContainer?.widthTracksTextView = false
        preview.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        preview.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let previewScroll = NSScrollView()
        previewScroll.documentView = preview
        previewScroll.hasVerticalScroller = true
        previewScroll.hasHorizontalScroller = true
        previewScroll.borderType = .bezelBorder

        for format in TableText.Format.allCases {
            formatMenu.addItem(withTitle: format.title)
            formatMenu.lastItem?.representedObject = format.rawValue
        }
        formatMenu.selectItem(at: TableText.Format.allCases.firstIndex(of: Preferences.tableFormat) ?? 0)
        formatMenu.target = self
        formatMenu.action = #selector(formatChanged)

        let copy = RetroUI.key("Copy to Clipboard", variant: .orange, height: 28, target: self, action: #selector(copyAndClose))
        copy.keyEquivalent = "\r"
        copy.keyEquivalentModifierMask = [.command]
        copy.toolTip = "Copy the table in the chosen format and close (⌘Return)"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: [RetroUI.hint("Copy as"), formatMenu, count, spacer, copy])
        bar.spacing = 10
        bar.alignment = .centerY

        let column = NSStackView(views: [tableScroll, previewScroll, bar])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.distribution = .fill
        tableScroll.setContentHuggingPriority(.init(1), for: .vertical)
        tableScroll.setContentCompressionResistancePriority(.init(1), for: .vertical)

        let content = RetroUI.useChassis(w)
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: RetroUI.contentTop(of: w, in: content), constant: 8),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            tableScroll.widthAnchor.constraint(equalTo: column.widthAnchor),
            previewScroll.widthAnchor.constraint(equalTo: column.widthAnchor),
            previewScroll.heightAnchor.constraint(equalToConstant: 130),
            bar.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private var format: TableText.Format {
        (formatMenu.selectedItem?.representedObject as? String).flatMap(TableText.Format.init(rawValue:)) ?? .csv
    }

    /// One column per column of `grid`, headed A, B, C… like a spreadsheet; the first row is the header in Markdown.
    private func load(_ grid: TableText.Grid) {
        self.grid = grid
        for column in table.tableColumns { table.removeTableColumn(column) }
        let width = grid.first?.count ?? 0
        for c in 0..<width {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(c)"))
            column.title = Self.columnName(c)
            let longest = grid.map { $0[c].count }.max() ?? 0
            column.width = min(260, max(60, CGFloat(longest) * 7.5 + 16))
            table.addTableColumn(column)
        }
        table.reloadData()
        refresh()
    }

    /// A, B, … Z, AA, AB, …
    private static func columnName(_ index: Int) -> String {
        var n = index + 1, name = ""
        while n > 0 {
            let r = (n - 1) % 26
            name = String(Character(Unicode.Scalar(UInt8(65 + r)))) + name
            n = (n - 1) / 26
        }
        return name
    }

    /// The preview and the size after a change.
    private func refresh() {
        preview.string = TableText.text(grid, as: format)
        let rows = grid.count, columns = grid.first?.count ?? 0
        count.stringValue = "\(rows) \(rows == 1 ? "row" : "rows") × \(columns) \(columns == 1 ? "column" : "columns")"
    }

    @objc private func formatChanged() {
        Preferences.tableFormat = format
        refresh()
    }

    @objc private func copyAndClose() {
        // A cell still being edited counts.
        window?.makeFirstResponder(nil)
        guard !grid.isEmpty else { NSSound.beep(); return }
        let format = self.format
        TextRecognizer.copyTable(grid, as: format)
        Sound.play("Pop")
        let rows = grid.count
        close()
        Notifier.confirm("Copied a table as \(format.title)", detail: rows == 1 ? "1 row" : "\(rows) rows")
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { grid.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, let c = Int(id.rawValue), grid.indices.contains(row), c < grid[row].count
        else { return nil }
        let field = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? {
            let f = NSTextField()
            f.identifier = id
            f.isBordered = false
            f.drawsBackground = false
            f.isEditable = true
            f.lineBreakMode = .byTruncatingTail
            f.delegate = self
            return f
        }()
        field.stringValue = grid[row][c]
        // The header row Markdown uses is bold.
        field.font = row == 0 ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 12)
        return field
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let id = field.identifier, let c = Int(id.rawValue) else { return }
        let row = table.row(for: field)
        guard grid.indices.contains(row), c < grid[row].count else { return }
        grid[row][c] = field.stringValue
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        grid = []
        if Self.current === self { Self.current = nil }
    }
}

/// The pad's grid: Esc closes the pad.
private final class PadTableView: NSTableView {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
