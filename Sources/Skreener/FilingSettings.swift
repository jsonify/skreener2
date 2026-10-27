import AppKit

/// Settings → After Capture: the filing rules (#277), which can be added, edited, reordered, switched off and deleted,
/// and the switches for the Finder tag and the Spotlight text. Built with the Settings window's own pieces.
@MainActor final class FilingPane: NSObject {
    private var tools: SendToPane.Tools!
    /// The Filing Rules group, rebuilt whenever the list changes.
    private let rulesHost = NSStackView()

    func build(_ tools: SendToPane.Tools) -> [NSView] {
        self.tools = tools
        rulesHost.orientation = .vertical
        rulesHost.alignment = .leading
        rulesHost.spacing = 0
        reloadRules()
        let finder = tools.group("Finder and Spotlight", [
            tools.toggle("Tag with the app's name", "Saved captures get a Finder tag such as “Safari”, so Finder can list them by app.",
                         Preferences.tagWithApp) { Preferences.tagWithApp = $0 },
            tools.toggle("Make the text searchable in Spotlight",
                         "The text read in a saved screenshot goes in its Spotlight comment, so Spotlight finds it by any word in it.",
                         Preferences.spotlightText) { Preferences.spotlightText = $0 },
        ], nil)
        return [rulesHost, finder]
    }

    private func reloadRules() {
        for v in rulesHost.arrangedSubviews {
            rulesHost.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        let rules = Preferences.filingRules
        var rows = rules.enumerated().map { ruleRow($0.element, at: $0.offset, of: rules.count) }
        let add = NSButton(title: "Add Rule…", target: nil, action: nil)
        tools.bind(add) { [weak self] _ in self?.edit(nil) }
        rows.append(tools.row("Add a rule", "Files saved captures from an app, or with some text in them, into a folder.", add))
        let group = tools.group("Filing Rules", rows,
                                "Saved screenshots and recordings move to the folder of the first rule that matches. Both "
                                + "conditions ignore case; text rules wait until the screenshot's text is read, a moment "
                                + "after saving. A file is never replaced: a taken name gets a number. Saved Files keeps "
                                + "showing moved captures.")
        rulesHost.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: rulesHost.widthAnchor).isActive = true
    }

    private func ruleRow(_ rule: FilingRule, at index: Int, of count: Int) -> NSView {
        let on = NSSwitch()
        on.controlSize = .small
        on.state = rule.enabled ? .on : .off
        on.toolTip = "Use this rule"
        tools.bind(on) { [weak self] control in self?.setEnabled(rule, (control as? NSSwitch)?.state == .on) }
        let buttons = NSStackView(views: [
            on,
            iconButton("chevron.up", "Move Up", enabled: index > 0) { [weak self] in self?.move(index, by: -1) },
            iconButton("chevron.down", "Move Down", enabled: index < count - 1) { [weak self] in self?.move(index, by: 1) },
            iconButton("pencil", "Edit") { [weak self] in self?.edit(rule) },
            iconButton("trash", "Delete") { [weak self] in self?.delete(rule) },
        ])
        buttons.spacing = 6
        return tools.row(rule.summary, "→ " + (rule.folder as NSString).abbreviatingWithTildeInPath, buttons)
    }

    private func iconButton(_ symbol: String, _ tip: String, enabled: Bool = true, _ run: @escaping () -> Void) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(),
                         target: nil, action: nil)
        b.isBordered = false
        b.contentTintColor = .secondaryLabelColor
        b.toolTip = tip
        b.isEnabled = enabled
        tools.bind(b) { _ in run() }
        return b
    }

    private func setEnabled(_ rule: FilingRule, _ on: Bool) {
        var rules = Preferences.filingRules
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[i].enabled = on
        Preferences.filingRules = rules
    }

    private func move(_ index: Int, by offset: Int) {
        var rules = Preferences.filingRules
        let target = index + offset
        guard rules.indices.contains(index), rules.indices.contains(target) else { return }
        rules.swapAt(index, target)
        Preferences.filingRules = rules
        reloadRules()
    }

    private func delete(_ rule: FilingRule) {
        Preferences.filingRules.removeAll { $0.id == rule.id }
        reloadRules()
    }

    /// The sheet for a new rule (`existing` nil) or an existing one.
    private func edit(_ existing: FilingRule?) {
        guard let window = tools.window() else { return }
        let kind = NSPopUpButton()
        for c in FilingRule.Condition.allCases {
            kind.addItem(withTitle: c.title)
            kind.lastItem?.representedObject = c.rawValue
        }
        kind.selectItem(at: FilingRule.Condition.allCases.firstIndex(of: existing?.condition ?? .appIs) ?? 0)
        let value = NSTextField(string: existing?.value ?? "")
        value.placeholderString = "e.g. Figma, or Invoice"
        let folder = Choice(existing?.folder ?? "")
        let folderLabel = NSTextField(labelWithString: "")
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = .secondaryLabelColor
        let showFolder = {
            folderLabel.stringValue = folder.path.isEmpty ? "No folder chosen" : (folder.path as NSString).abbreviatingWithTildeInPath
            folderLabel.toolTip = folder.path
        }
        showFolder()
        let choose = NSButton(title: "Choose…", target: nil, action: nil)
        let enabled = NSButton(checkboxWithTitle: "Use this rule", target: nil, action: nil)
        enabled.state = existing?.enabled == false ? .off : .on

        tools.bind(choose) { _ in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Choose"
            panel.message = "Choose the folder these captures go to."
            if !folder.path.isEmpty { panel.directoryURL = URL(fileURLWithPath: (folder.path as NSString).expandingTildeInPath) }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            folder.path = url.path
            showFolder()
        }
        let folderRow = NSStackView(views: [folderLabel, choose])
        folderRow.spacing = 10
        let fields = NSStackView(views: [NSTextField(labelWithString: "When"), kind, value,
                                         NSTextField(labelWithString: "Move to"), folderRow, enabled])
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 6
        for view in [value, folderRow] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: 360).isActive = true
        }
        fields.setFrameSize(fields.fittingSize)

        let alert = NSAlert()
        alert.messageText = existing == nil ? "New Filing Rule" : "Edit Filing Rule"
        alert.informativeText = "Saved captures that match move to the folder. The app's name and the text are matched ignoring case."
        alert.accessoryView = fields
        alert.addButton(withTitle: existing == nil ? "Add" : "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = value
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let text = value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !folder.path.isEmpty else { NSSound.beep(); return }
            var rules = Preferences.filingRules
            var rule = existing ?? FilingRule()
            rule.condition = (kind.selectedItem?.representedObject as? String).flatMap(FilingRule.Condition.init(rawValue:)) ?? .appIs
            rule.value = text
            rule.folder = folder.path
            rule.enabled = enabled.state == .on
            if let i = rules.firstIndex(where: { $0.id == rule.id }) { rules[i] = rule } else { rules.append(rule) }
            Preferences.filingRules = rules
            self?.reloadRules()
        }
    }
}

/// The folder picked in a rule's sheet, shared by its Choose… button and the sheet's end.
private final class Choice {
    var path: String
    init(_ path: String) { self.path = path }
}
