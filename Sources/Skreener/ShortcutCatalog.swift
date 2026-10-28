import AppKit

/// One line of the keyboard shortcut sheet: what it does and the keys that do it, one keycap each ("⇧", "⌘", "Z").
struct ShortcutEntry: Equatable {
    let title: String
    let keys: [String]
    /// When it applies, e.g. "hold while dragging"; shown after the title and searched too.
    let note: String

    init(_ title: String, keys: [String], note: String = "") {
        self.title = title
        self.keys = keys
        self.note = note
    }
}

struct ShortcutSection: Equatable {
    let title: String
    let entries: [ShortcutEntry]
}

/// The single source of truth for the shortcut sheet (Help → Keyboard Shortcuts…, and ? in the editor). The editor's
/// tools come from `Tool.shortcuts`, the global shortcuts from the user's own settings, so neither can go stale.
enum ShortcutCatalog {
    /// Every section, in the order the sheet shows them. `bindings` are the user's global shortcuts.
    @MainActor static func sections(bindings: [HotKeyAction: KeyCombo] = ShortcutStore.bindings()) -> [ShortcutSection] {
        [toolSection(), editorCommands(), areaSelection()] + globalSections(bindings: bindings)
    }

    // MARK: Editor

    static func toolSection() -> ShortcutSection {
        let entries = Tool.allCases.compactMap { tool -> ShortcutEntry? in
            guard let key = Tool.shortcuts.first(where: { $0.value == tool })?.key else { return nil }
            return ShortcutEntry(tool.name, keys: [String(key).uppercased()], note: tool.modifierTip ?? "")
        }
        return ShortcutSection(title: "Editor Tools", entries: entries)
    }

    /// Checked against CanvasView.keyDown, its mouse handling and its menus.
    @MainActor static func editorCommands() -> ShortcutSection {
        var entries = [
            ShortcutEntry("Undo", keys: ["⌘", "Z"]),
            ShortcutEntry("Redo", keys: ["⇧", "⌘", "Z"]),
            ShortcutEntry("Cut", keys: ["⌘", "X"]),
            ShortcutEntry("Copy", keys: ["⌘", "C"], note: "with nothing selected, the whole image"),
            ShortcutEntry("Paste", keys: ["⌘", "V"]),
            ShortcutEntry("Duplicate", keys: ["⌘", "D"]),
            ShortcutEntry("Crop", keys: ["C"], note: "↩ applies, esc cancels"),
            ShortcutEntry("Delete", keys: ["⌫"], note: "the selected annotation"),
            ShortcutEntry("Edit Text", keys: ["↩"], note: "with a text annotation selected"),
            ShortcutEntry("Nudge", keys: ["← ↑ → ↓"], note: "the selected annotation, 1 pt"),
            ShortcutEntry("Nudge by 10", keys: ["⇧", "← ↑ → ↓"], note: "the selected annotation"),
            ShortcutEntry("Deselect", keys: ["⎋"]),
            ShortcutEntry("Measure Across", keys: ["1"], note: "hold; also ← → with nothing selected; click to keep"),
            ShortcutEntry("Measure Up and Down", keys: ["2"], note: "hold; also ↑ ↓ with nothing selected; click to keep"),
            ShortcutEntry("Measure Outer Size", keys: ["⇧"], note: "hold while measuring"),
            ShortcutEntry("Copy Color Under Pointer", keys: ["⇥"]),
            ShortcutEntry("Copy Darkest Color Nearby", keys: ["⇧", "⇥"], note: "the color of thin text"),
            ShortcutEntry("Copy Average Color of Area", keys: ["⇧", "C"]),
            ShortcutEntry("Check Contrast", keys: ["⇧", "K"]),
            ShortcutEntry("Duplicate by Dragging", keys: ["⌥"], note: "hold while dragging an annotation"),
            ShortcutEntry("Draw Without Snapping", keys: ["⌘"], note: "hold while drawing a box"),
            ShortcutEntry("Straight Pen Line", keys: ["⇧"], note: "hold while drawing with the pen or highlighter"),
        ]
        for (title, _, key, mods) in CanvasView.arrangeCommands {
            entries.append(ShortcutEntry(title, keys: modifierSymbols(mods) + [key.uppercased()]))
        }
        entries.append(ShortcutEntry("Show This List", keys: ["?"]))
        return ShortcutSection(title: "Editor Commands", entries: entries)
    }

    // MARK: Capture

    /// Checked against SelectionOverlay and SelectionGeometry.
    static func areaSelection() -> ShortcutSection {
        ShortcutSection(title: "Selecting an Area", entries: [
            ShortcutEntry("Switch Area, Window, Scrolling", keys: ["Space"], note: "before dragging"),
            ShortcutEntry("Move the Selection", keys: ["Space"], note: "hold while dragging"),
            ShortcutEntry("Square Selection", keys: ["⇧"], note: "hold while dragging"),
            ShortcutEntry("Drag From the Center", keys: ["⌥"], note: "hold while dragging"),
            ShortcutEntry("Nudge", keys: ["← ↑ → ↓"], note: "1 pt: the pointer, or the selection after the drag"),
            ShortcutEntry("Nudge by 10", keys: ["⇧", "← ↑ → ↓"]),
            ShortcutEntry("Resize the Selection", keys: ["⌘", "← ↑ → ↓"], note: "after the drag; add ⇧ for 10 pt"),
            ShortcutEntry("Capture", keys: ["↩"], note: "after the drag"),
            ShortcutEntry("Cancel", keys: ["⎋"]),
        ])
    }

    /// One section per group of Settings → Shortcuts, listing the actions that have a shortcut right now.
    static func globalSections(bindings: [HotKeyAction: KeyCombo]) -> [ShortcutSection] {
        HotKeyAction.Section.allCases.compactMap { section in
            let entries = HotKeyAction.allCases.compactMap { action -> ShortcutEntry? in
                guard action.section == section, let combo = bindings[action] else { return nil }
                return ShortcutEntry(action.title, keys: keys(for: combo))
            }
            return entries.isEmpty ? nil : ShortcutSection(title: "Global: " + section.title, entries: entries)
        }
    }

    // MARK: Keys

    /// A combination as keycaps: each modifier on its own, then the key ("⌃", "⇧", "4").
    static func keys(for combo: KeyCombo) -> [String] {
        KeyCombo.symbols(for: combo.modifiers).map { String($0) } + [combo.keyName]
    }

    /// ⌃ ⌥ ⇧ ⌘ in the standard order.
    static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> [String] {
        var s: [String] = []
        if flags.contains(.control) { s.append("⌃") }
        if flags.contains(.option) { s.append("⌥") }
        if flags.contains(.shift) { s.append("⇧") }
        if flags.contains(.command) { s.append("⌘") }
        return s
    }

    // MARK: Search

    /// Plain-language names for symbols, so "shift" finds ⇧ and "escape" finds ⎋.
    private static let keyWords: [Character: String] = [
        "⇧": "shift", "⌘": "command cmd", "⌥": "option alt", "⌃": "control ctrl", "⎋": "escape esc",
        "↩": "return enter", "⇥": "tab", "⌫": "delete backspace", "←": "left", "→": "right", "↑": "up", "↓": "down",
    ]

    /// Lowercased text a query is matched against: the title, note, section and every key by symbol and by name.
    static func searchText(_ entry: ShortcutEntry, in section: ShortcutSection) -> String {
        var words = [entry.title, entry.note, section.title]
        for key in entry.keys {
            words.append(key)
            for ch in key { if let w = keyWords[ch] { words.append(w) } }
        }
        return words.joined(separator: " ").lowercased()
    }

    /// Entries matching every word of `query`; sections left empty are dropped. A blank query keeps everything.
    static func filter(_ sections: [ShortcutSection], matching query: String) -> [ShortcutSection] {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map { String($0) }
        guard !terms.isEmpty else { return sections }
        return sections.compactMap { section in
            let hits = section.entries.filter { entry in
                let text = searchText(entry, in: section)
                return terms.allSatisfy { text.contains($0) }
            }
            return hits.isEmpty ? nil : ShortcutSection(title: section.title, entries: hits)
        }
    }

    /// Deals sections into two columns of about the same height, keeping their order (a section is never split).
    static func columns(_ sections: [ShortcutSection]) -> (left: [ShortcutSection], right: [ShortcutSection]) {
        func height(_ s: ShortcutSection) -> Int { s.entries.count + 2 }
        let total = sections.reduce(0) { $0 + height($1) }
        var used = 0
        var left: [ShortcutSection] = [], right: [ShortcutSection] = []
        for s in sections {
            if used * 2 < total { left.append(s) } else { right.append(s) }
            used += height(s)
        }
        return (left, right)
    }
}

extension Tool {
    /// One short tip for a real modifier in the drawing code, or nil: shown after the name in tooltips and the sheet.
    var modifierTip: String? {
        switch self {
        case .select: return "⌥-drag duplicates"
        case .pen, .highlighter: return "⇧ for a straight line"
        case .rect, .filledRect, .pixelate, .blur, .spotlight, .erase, .magnifier: return "⌘ skips snapping"
        default: return nil
        }
    }

    /// "Pen (P) · ⇧ for a straight line"; `variants` swaps the tip for the hint about the button's variants menu.
    func tooltip(variants: Bool = false) -> String {
        if self == .redactText { return "Redact Text: find words and redact every match" }
        var s = name
        if let key = Tool.shortcuts.first(where: { $0.value == self })?.key { s += " (\(String(key).uppercased()))" }
        if variants { s += " · hold for variants" } else if let tip = modifierTip { s += " · " + tip }
        return s
    }
}
