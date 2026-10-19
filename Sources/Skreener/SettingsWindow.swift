import AppKit

/// Settings window (⌘, or the menu bar icon or the editor's gear button): what happens after a capture, selection and window-capture
/// options, the global shortcuts, and the version / build that is running.
final class SettingsWindowController: NSWindowController {
    @MainActor static let shared = SettingsWindowController()
    /// Whether the Settings window is on screen (without creating it).
    @MainActor static var isOpen: Bool { created?.window?.isVisible == true }
    @MainActor private static weak var created: SettingsWindowController?

    /// "0.1.0 (48db438)": marketing version plus the git commit stamped in by build_app.sh.
    nonisolated static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    private static let shortcuts = [("⌃⇧4", "Capture Area"), ("⌃⇧1", "Capture Previous Area"), ("⌃⇧6", "Capture Area & Pin"),
                                    ("⌃⇧3", "Capture Fullscreen"), ("⌃⇧5", "Capture Window"), ("⌃⇧2", "Capture Text (OCR)"),
                                    ("⌃⇧H", "Capture History")]

    /// Target objects for the controls' closures (controls hold their targets weakly).
    private var actions: [ControlAction] = []
    private let folderLabel = NSTextField(labelWithString: "")

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "Skreener Settings"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        Self.created = self
        w.contentView = buildContent()
        w.setContentSize(w.contentView?.fittingSize ?? w.frame.size)
        w.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            Task { @MainActor in DockPresence.update() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        refreshFolder()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        DockPresence.update()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Layout

    private func buildContent() -> NSView {
        var rows: [[NSView]] = []
        var headers: [Int] = []
        func section(_ title: String) {
            let l = NSTextField(labelWithString: title)
            l.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            headers.append(rows.count)
            rows.append([l, NSGridCell.emptyContentView])
        }
        func row(_ label: String, _ control: NSView) { rows.append([NSTextField(labelWithString: label), control]) }

        section("After Capture")
        row("Output:", checkbox("Copy to clipboard", Preferences.copyToClipboard) { Preferences.copyToClipboard = $0 })
        row("", checkbox("Save to folder", Preferences.autoSave) { Preferences.autoSave = $0 })
        let choose = NSButton(title: "Choose…", target: nil, action: nil)
        bind(choose) { [weak self] _ in self?.chooseFolder() }
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.translatesAutoresizingMaskIntoConstraints = false
        folderLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        row("Save folder:", NSStackView(views: [folderLabel, choose]))

        section("History")
        row("Captures:", checkbox("Keep capture history (last \(CaptureHistory.limit))", Preferences.keepHistory) {
            Preferences.keepHistory = $0
        })

        section("Editor")
        row("Annotations:", checkbox("Drop shadow", Preferences.annotationShadow) {
            Preferences.annotationShadow = $0
            NotificationCenter.default.post(name: .skreenerPreferencesChanged, object: nil)
        })

        section("Selection")
        row("Screen:", checkbox("Freeze screen while selecting", Preferences.freezeScreen) { Preferences.freezeScreen = $0 })
        row("", checkbox("Show cursor in screenshots", Preferences.showCursor) { Preferences.showCursor = $0 })
        row("", checkbox("Hide desktop icons while capturing", Preferences.hideIconsWhileCapturing) {
            Preferences.hideIconsWhileCapturing = $0
        })

        section("Window Capture")
        row("Style:", checkbox("Shadow", Preferences.windowShadow) { Preferences.windowShadow = $0 })
        row("", checkbox("Transparent background (white when off)", Preferences.windowTransparentBackground) {
            Preferences.windowTransparentBackground = $0
        })
        let padding = NSPopUpButton(frame: .zero, pullsDown: false)
        for pts in [0, 16, 32, 64] { padding.addItem(withTitle: pts == 0 ? "None" : "\(pts) pt"); padding.lastItem?.tag = pts }
        padding.selectItem(withTag: Preferences.windowPadding)
        bind(padding) { Preferences.windowPadding = ($0 as? NSPopUpButton)?.selectedTag() ?? 0 }
        row("Padding:", padding)

        section("Shortcuts")
        for (keys, title) in Self.shortcuts {
            let k = NSTextField(labelWithString: keys)
            k.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            row(title + ":", k)
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        for h in headers {
            let r = grid.row(at: h)
            r.mergeCells(in: NSRange(location: 0, length: 2))
            r.cell(at: 0).xPlacement = .leading
            if h > 0 { r.topPadding = 10 }
        }

        let version = NSTextField(labelWithString: "Skreener \(Self.version)")
        version.textColor = .secondaryLabelColor
        version.isSelectable = true

        let stack = NSStackView(views: [grid, version])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        return stack
    }

    private func checkbox(_ title: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.state = on ? .on : .off
        bind(b) { set(($0 as? NSButton)?.state == .on) }
        return b
    }

    private func bind(_ control: NSControl, _ run: @escaping (NSControl) -> Void) {
        let a = ControlAction(run)
        actions.append(a)
        control.target = a; control.action = #selector(ControlAction.fire(_:))
    }

    // MARK: Save folder

    private func refreshFolder() {
        folderLabel.stringValue = (Preferences.saveDirectory.path as NSString).abbreviatingWithTildeInPath
        folderLabel.toolTip = Preferences.saveDirectory.path
    }

    private func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        p.directoryURL = Preferences.saveDirectory
        guard let w = window else { return }
        p.beginSheetModal(for: w) { [weak self] r in
            if r == .OK, let u = p.url { Preferences.saveDirectory = u; self?.refreshFolder() }
        }
    }
}

@MainActor private final class ControlAction: NSObject {
    let run: (NSControl) -> Void
    init(_ run: @escaping (NSControl) -> Void) { self.run = run }
    @objc func fire(_ sender: NSControl) { run(sender) }
}
