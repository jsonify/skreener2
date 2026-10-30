import AppKit

/// Builders shared by the windows that take the SK-1 look beyond the editor (#344): the scratch pad, Step Guide,
/// history panel, Combine, Ask Claude, Watch This Area, the shortcut list and the tip popovers. They only wrap the kit
/// (`PillButton`, `KeycapTray`, `RetroLabel`, `ChassisView`); nothing here draws.
enum RetroUI {
    /// A symbol-only key: a 28 pt face on its 2 pt skirt.
    static let iconKeyHeight: CGFloat = 30
    /// A key with a title.
    static let textKeyHeight: CGFloat = 24

    /// A cream key (`variant`: orange for the main action, charcoal for a secondary one) with a title and/or a symbol.
    /// A symbol-only key is spoken as `tip`.
    static func key(_ title: String? = nil, symbol: String? = nil, tip: String? = nil,
                    variant: Retro.KeyVariant = .cream, height: CGFloat? = nil,
                    target: AnyObject? = nil, action: Selector? = nil) -> PillButton {
        let b = PillButton(title: title, symbol: symbol, style: .keycap, height: height ?? (title == nil ? iconKeyHeight : textKeyHeight))
        b.keyVariant = variant
        b.target = target
        b.action = action
        if let tip {
            b.toolTip = tip
            if title == nil { b.setAccessibilityLabel(tip) }
        }
        return b
    }

    /// An orange-square toggle; the handler flips `isOn` (a toggle doesn't flip itself).
    static func toggle(_ title: String, tip: String? = nil, isOn: Bool = false, height: CGFloat = 20,
                       target: AnyObject?, action: Selector?) -> PillButton {
        let b = PillButton(title: title, symbol: nil, style: .toggle, height: height)
        b.isOn = isOn
        b.target = target
        b.action = action
        if let tip { b.toolTip = tip }
        return b
    }

    /// Keys in a sunken tray with a caption under it.
    static func tray(_ caption: String?, _ keys: [NSView]) -> KeycapTray { KeycapTray(keys, caption: caption) }

    /// A pop-up as a cream key with a ▾, for a menu of choices that is too long for a segmented control.
    static func menuKey(tip: String, caption: String? = nil, target: AnyObject?, action: Selector?) -> PillPopUp {
        let p = PillPopUp(pullsDown: false, height: textKeyHeight, style: .keycap)
        p.caption = caption
        p.toolTip = tip
        p.target = target
        p.action = action
        return p
    }

    /// An LCD chip between ◀ ▶ that steps through its items, with an optional caption to its left.
    static func stepper(caption: String? = nil, tip: String? = nil, target: AnyObject?, action: Selector?) -> PillPopUp {
        let p = PillPopUp(pullsDown: false, height: textKeyHeight, style: .lcd, stepper: true)
        p.caption = caption
        p.toolTip = tip
        p.target = target
        p.action = action
        return p
    }

    /// Makes `window`'s content the chassis, with the title bar transparent over it. Returns the chassis, which the
    /// caller fills. The title stays in the title bar; lay content out from `contentTop(of:in:)`.
    static func useChassis(_ window: NSWindow) -> ChassisView {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        let chassis = ChassisView()
        window.contentView = chassis
        return chassis
    }

    /// The top of the area below the title bar (the content's top for a window without one, e.g. a sheet).
    static func contentTop(of window: NSWindow, in content: NSView) -> NSLayoutYAxisAnchor {
        (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? content.topAnchor
    }

    /// Plain secondary text (a hint, a count) in the soft ink.
    static func hint(_ text: String = "", size: CGFloat = 11, wraps: Bool = false) -> RetroLabel {
        let l = RetroLabel(text: text, tone: .soft, size: size)
        if wraps {
            l.lineBreakMode = .byWordWrapping
            l.maximumNumberOfLines = 0
            l.cell?.wraps = true
        }
        return l
    }
}

extension PillPopUp {
    /// `NSPopUpButton.addItems(withTitles:)`.
    func addItems(withTitles titles: [String]) { titles.forEach { addItem(withTitle: $0) } }

    /// `NSPopUpButton.removeAllItems()`.
    func removeAllItems() {
        menu?.removeAllItems()
        selectItem(at: -1)
    }
}

/// Esc cancels; a borderless-looking window can still become key.
private final class DialogWindow: NSWindow {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override var canBecomeKey: Bool { true }
}

/// A small dialog in the SK-1 look, for what used to be an `NSAlert` with an accessory view: a heading, a line of text,
/// the form, and a Cancel key with an orange main key. Run it modally or as a sheet; the main key is
/// `primaryKey` (disable it while the form is invalid) and `validate` can refuse it with a message.
final class RetroDialog: NSObject {
    let primaryKey: PillButton
    private let cancelKey: PillButton
    private let window: DialogWindow
    private let message = RetroLabel(text: "", tone: .soft, size: 12)
    /// Returns a problem to show instead of closing, or nil when the form is fine.
    var validate: (() -> String?)?

    /// `width` is the content's width; `body` is laid out at `width` minus the margins.
    init(title: String, message text: String, body: NSView, primary: String, secondary: String = "Cancel", width: CGFloat = 380) {
        primaryKey = RetroUI.key(primary, variant: .orange, height: 28)
        cancelKey = RetroUI.key(secondary, height: 28)
        window = DialogWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.title = title
        window.isReleasedWhenClosed = false
        window.onCancel = { [weak self] in self?.finish(.cancel) }
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(b)?.isHidden = true }
        let content = RetroUI.useChassis(window)

        let margin: CGFloat = 20
        let inner = width - margin * 2
        let heading = RetroLabel(text: title, tone: .ink, size: 14)
        heading.font = .systemFont(ofSize: 14, weight: .bold)
        message.stringValue = text
        message.lineBreakMode = .byWordWrapping
        message.maximumNumberOfLines = 0
        message.cell?.wraps = true
        message.preferredMaxLayoutWidth = inner

        primaryKey.target = self
        primaryKey.action = #selector(primaryPressed)
        primaryKey.keyEquivalent = "\r"
        cancelKey.target = self
        cancelKey.action = #selector(cancelPressed)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancelKey, primaryKey])
        buttons.spacing = 10

        let stack = NSStackView(views: [heading, message, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: RetroUI.contentTop(of: window, in: content), constant: 10),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            stack.widthAnchor.constraint(equalToConstant: inner),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        content.layoutSubtreeIfNeeded()
        let titleBar = window.frame.height - window.contentLayoutRect.height
        window.setContentSize(NSSize(width: width, height: ceil(stack.fittingSize.height) + 10 + margin + max(titleBar, 0)))
    }

    /// Text above the form (e.g. what is wrong).
    func setMessage(_ text: String) { message.stringValue = text }

    /// Runs as a modal window; true if the main key was pressed.
    func runModal() -> Bool {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        let response = NSApp.runModal(for: window)
        window.orderOut(nil)
        return response == .OK
    }

    /// Runs as a sheet on `parent`; `done` gets true if the main key was pressed.
    func beginSheet(on parent: NSWindow, done: @escaping (Bool) -> Void) {
        // The sheet's completion keeps the dialog alive: its keys only hold it weakly.
        parent.beginSheet(window) { [self] response in
            withExtendedLifetime(self) { done(response == .OK) }
        }
    }

    private func finish(_ response: NSApplication.ModalResponse) {
        if let parent = window.sheetParent {
            parent.endSheet(window, returnCode: response)
        } else {
            NSApp.stopModal(withCode: response)
        }
    }

    @objc private func primaryPressed() {
        if let problem = validate?() {
            NSSound.beep()
            message.stringValue = problem
            return
        }
        finish(.OK)
    }

    @objc private func cancelPressed() { finish(.cancel) }
}
