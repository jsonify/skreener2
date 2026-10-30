import AppKit

/// The one-time tips (#301).
enum TipID: String, CaseIterable {
    case counterTool, filledRect, moveSelection, repeatSimilar

    var title: String {
        switch self {
        case .counterTool: return "Number your steps"
        case .filledRect: return "Filled rectangles"
        case .moveSelection: return "Move the selection"
        case .repeatSimilar: return "Same box on similar items?"
        }
    }

    /// The tip's line; a word in braces is drawn as a key (`TipText`).
    var line: String {
        switch self {
        case .counterTool: return "Press {N} for numbered counters"
        case .filledRect: return "Press {F} for a filled rectangle"
        case .moveSelection: return "Hold {Space} to move the selection"
        case .repeatSimilar: return "Try Repeat on Similar Objects"
        }
    }
}

/// What the tips count (#301).
enum TipEvent: String, CaseIterable {
    case editorOpened, rectangleDrawn, areaCaptured
}

/// "Show tip X after event Y reaches N".
struct TipRule: Equatable {
    let tip: TipID
    let event: TipEvent
    let count: Int
}

/// Features that wear a "New" dot (or a menu item's "New" badge) until they are first used (#303).
enum NewFeature: String, CaseIterable {
    case removeBackground, cutOut, repeatOnSimilarObjects, combineScreenshots

    /// The feature a menu item with `action` runs, if any. Combine Screenshots has an editor action without a sender
    /// and a window action with one.
    static func running(_ action: Selector) -> NewFeature? {
        switch NSStringFromSelector(action) {
        case "removeBackground:": return .removeBackground
        case "cutOut:": return .cutOut
        case "repeatOnSimilarObjects:": return .repeatOnSimilarObjects
        case "combineScreenshots", "combineScreenshots:": return .combineScreenshots
        default: return nil
        }
    }
}

/// A tip's line split into plain text and keys: "Press {N} for…" → "Press", key "N", "for…".
enum TipText {
    static func segments(_ line: String) -> [(text: String, isKey: Bool)] {
        var out: [(text: String, isKey: Bool)] = []
        var rest = Substring(line)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            let before = rest[..<open].trimmingCharacters(in: .whitespaces)
            if !before.isEmpty { out.append((before, false)) }
            let key = rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { out.append((key, true)) }
            rest = rest[rest.index(after: close)...]
        }
        let tail = rest.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { out.append((tail, false)) }
        return out
    }

    /// The line without the braces.
    static func plain(_ line: String) -> String { segments(line).map(\.text).joined(separator: " ") }
}

/// What the tips remember between launches: how often each event happened, the tips already shown, and the features
/// already used. Pure, so it is unit tested; `Tips` keeps it in user defaults.
struct TipBook: Equatable {
    var counts: [String: Int] = [:]
    var seen: Set<String> = []
    var used: Set<String> = []

    static let rules: [TipRule] = [
        TipRule(tip: .counterTool, event: .editorOpened, count: 1),
        TipRule(tip: .filledRect, event: .rectangleDrawn, count: 3),
        TipRule(tip: .moveSelection, event: .areaCaptured, count: 2),
    ]

    func count(_ e: TipEvent) -> Int { counts[e.rawValue] ?? 0 }
    mutating func record(_ e: TipEvent) { counts[e.rawValue, default: 0] += 1 }

    func hasSeen(_ t: TipID) -> Bool { seen.contains(t.rawValue) }
    mutating func markSeen(_ t: TipID) { seen.insert(t.rawValue) }

    func isNew(_ f: NewFeature) -> Bool { !used.contains(f.rawValue) }
    mutating func markUsed(_ f: NewFeature) { used.insert(f.rawValue) }

    /// The tip has never been shown and its event has reached its count (a tip without a rule, like the Repeat on
    /// Similar Objects nudge, has its own condition and is due until shown).
    func isDue(_ t: TipID) -> Bool {
        guard !hasSeen(t) else { return false }
        guard let rule = Self.rules.first(where: { $0.tip == t }) else { return true }
        return count(rule.event) >= rule.count
    }

    /// Whether `t` may be shown now: tips are on, none was shown yet this session, nothing is being dragged or drawn,
    /// and the tip is due.
    func shouldShow(_ t: TipID, enabled: Bool, shownThisSession: Bool, busy: Bool) -> Bool {
        enabled && !shownThisSession && !busy && isDue(t)
    }

    var plist: [String: Any] { ["counts": counts, "seen": Array(seen).sorted(), "used": Array(used).sorted()] }

    init() {}

    init(plist d: [String: Any]) {
        counts = d["counts"] as? [String: Int] ?? [:]
        seen = Set(d["seen"] as? [String] ?? [])
        used = Set(d["used"] as? [String] ?? [])
    }
}

/// One-time tips and usage nudges, shown while `Preferences.showTipsAndHints` is on.
@MainActor enum Tips {
    /// Posted when a tip is shown, a feature is first used, or everything is reset: "New" dots and badges follow it.
    static let didChange = Notification.Name("SkreenerTipsDidChange")
    private static let key = "tips"
    private static var book: TipBook {
        get { TipBook(plist: UserDefaults.standard.dictionary(forKey: key) ?? [:]) }
        set { UserDefaults.standard.set(newValue.plist, forKey: key) }
    }
    /// At most one tip per app session.
    private(set) static var shownThisSession = false
    static var enabled: Bool { Preferences.showTipsAndHints }

    /// Counts `e` toward the tips waiting on it (not while tips are off).
    static func record(_ e: TipEvent) {
        guard enabled else { return }
        book.record(e)
    }

    /// Whether `t` may be shown now; `busy` is true during a drag, while drawing or typing.
    static func canShow(_ t: TipID, busy: Bool) -> Bool {
        book.shouldShow(t, enabled: enabled, shownThisSession: shownThisSession, busy: busy)
    }

    /// `t` is on screen: it never shows again, and no other tip shows this session.
    static func markShown(_ t: TipID) {
        shownThisSession = true
        book.markSeen(t)
    }

    /// Whether `f` still wears its "New" dot.
    static func isNew(_ f: NewFeature) -> Bool { enabled && book.isNew(f) }

    static func markUsed(_ f: NewFeature) {
        guard book.isNew(f) else { return }
        book.markUsed(f)
        changed()
    }

    /// Settings → General → Reset Tips: every tip and "New" dot shows again.
    static func resetAll() {
        book = TipBook()
        shownThisSession = false
        changed()
    }

    private static func changed() {
        refreshBadges(in: NSApp.mainMenu)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: "New" badges in menus (#303)

    private static var watching = false

    /// Clears a feature's dot whenever a menu runs it, wherever that menu is, and keeps menu badges up to date.
    static func startWatching() {
        guard !watching else { return }
        watching = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSMenu.didSendActionNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let item = note.userInfo?["MenuItem"] as? NSMenuItem, let action = item.action,
                      let f = NewFeature.running(action) else { return }
                markUsed(f)
            }
        }
        nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { refreshBadges(in: note.object as? NSMenu) }
        }
        nc.addObserver(forName: .skreenerPreferencesChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { changed() }
        }
        refreshBadges(in: NSApp.mainMenu)
    }

    /// Gives every item in `menu` (and its submenus) that runs a new feature a "New" badge, and takes it off used ones.
    static func refreshBadges(in menu: NSMenu?) {
        guard let menu else { return }
        for item in menu.items {
            if let action = item.action, let f = NewFeature.running(action) {
                let new = isNew(f)
                if new != (item.badge != nil) { item.badge = new ? NSMenuItemBadge(string: "New") : nil }
            }
            refreshBadges(in: item.submenu)
        }
    }
}

// MARK: The tip popover (#301)

/// A small key cap, like the ones on the keyboard, for a tip's line.
final class KeycapView: NSView {
    private let label: NSTextField

    init(_ key: String) {
        label = NSTextField(labelWithString: key)
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            heightAnchor.constraint(equalToConstant: 20),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
        ])
        refreshInk()
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(key)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func refreshInk() { label.textColor = Retro.color(Retro.palette(for: self).keyInk) }

    /// A small cream key (the SK-1 keys), 18 pt of face on a 2 pt skirt.
    override func draw(_ dirtyRect: NSRect) {
        Retro.drawKey(in: bounds, radius: 4, colors: Retro.keyColors(.cream, Retro.palette(for: self)), down: false, flipped: isFlipped)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshInk()
        needsDisplay = true
    }
}

/// A tip in a popover beside the control it is about: a title, one line (keys drawn as key caps), Got it and ×.
/// Closing it any way (Got it, ×, Esc or a click elsewhere) is the same: the tip has been seen.
@MainActor final class TipPopover: NSObject, NSPopoverDelegate {
    private static var current: TipPopover?
    private let popover = NSPopover()
    private let action: (() -> Void)?

    /// Shows `tip` pointing at `rect` in `view` and marks it shown. `actionTitle` adds a button that runs `action`.
    static func show(_ tip: TipID, relativeTo rect: NSRect, of view: NSView, edge: NSRectEdge,
                     actionTitle: String? = nil, action: (() -> Void)? = nil) {
        guard view.window?.isVisible == true else { return }
        current?.popover.close()
        let p = TipPopover(tip, actionTitle: actionTitle, action: action)
        current = p
        Tips.markShown(tip)
        p.popover.show(relativeTo: rect, of: view, preferredEdge: edge)
    }

    private init(_ tip: TipID, actionTitle: String?, action: (() -> Void)?) {
        self.action = action
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let vc = NSViewController()
        vc.view = content(tip, actionTitle: actionTitle)
        vc.preferredContentSize = vc.view.fittingSize
        popover.contentViewController = vc
    }

    private func content(_ tip: TipID, actionTitle: String?) -> NSView {
        let title = RetroLabel(text: tip.title, tone: .ink, size: 13)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let close = PillButton(title: nil, symbol: "xmark", style: .round, height: 20)
        close.target = self
        close.action = #selector(closePressed)
        close.toolTip = "Close"
        close.setAccessibilityLabel("Close")
        let head = NSStackView()
        head.addView(title, in: .leading)
        head.addView(close, in: .trailing)
        head.spacing = 8

        let line = NSStackView(views: TipText.segments(tip.line).map { seg -> NSView in
            if seg.isKey { return KeycapView(seg.text) }
            return RetroLabel(text: seg.text, tone: .soft, size: 12)
        })
        line.spacing = 4
        line.alignment = .centerY

        var buttons: [NSView] = []
        // Got it is the orange key when it is the only choice; with an action, that is the orange one.
        let gotIt = RetroUI.key(actionTitle == nil ? "Got it" : "Not Now", variant: actionTitle == nil ? .orange : .cream,
                                target: self, action: #selector(closePressed))
        buttons.append(gotIt)
        if let actionTitle {
            let run = RetroUI.key(actionTitle, variant: .orange, target: self, action: #selector(actionPressed))
            run.keyEquivalent = "\r"
            buttons.append(run)
        } else {
            gotIt.keyEquivalent = "\r"
        }
        let foot = NSStackView()
        for b in buttons { foot.addView(b, in: .trailing) }
        foot.spacing = 8

        let stack = NSStackView(views: [head, line, foot])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 10)
        for v in [head, foot] { v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true }
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        return stack
    }

    @objc private func closePressed() { popover.performClose(nil) }

    @objc private func actionPressed() {
        popover.performClose(nil)
        action?()
    }

    func popoverDidClose(_ notification: Notification) {
        if Self.current === self { Self.current = nil }
    }
}
