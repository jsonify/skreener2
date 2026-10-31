import AppKit

/// Settings → Send To: the user's custom actions (#276), which can be added, edited, reordered and deleted, and the
/// notes apps to list (#275). Actions show in the Send To menu, and the ones set to run after every capture run once a
/// screenshot is saved.
@MainActor final class SendToPane: NSObject {
    /// The pieces of the Settings window's own layout this pane builds with.
    struct Tools {
        let group: (String, [NSView], String?) -> NSView
        let row: (String, String?, NSView) -> NSView
        let toggle: (String, String?, Bool, @escaping (Bool) -> Void) -> NSView
        let bind: (NSControl, @escaping (NSControl) -> Void) -> Void
        let window: () -> NSWindow?
    }

    private var tools: Tools!
    /// The Actions group, rebuilt whenever the list changes.
    private let actionsHost = NSStackView()
    private let vaultLabel = NSTextField(labelWithString: "")

    func build(_ tools: Tools) -> [NSView] {
        self.tools = tools
        actionsHost.orientation = .vertical
        actionsHost.alignment = .leading
        actionsHost.spacing = 0
        reloadActions()
        var views: [NSView] = [actionsHost, notesGroup()]
        if NotesApp.obsidian.isInstalled { views.append(obsidianGroup()) }
        return views
    }

    // MARK: Notes apps

    private func blurb(_ app: NotesApp) -> String {
        switch app {
        case .obsidian: return "The picture is copied into your vault and linked from a note."
        case .bear: return "A new note with the picture inside."
        case .drafts: return "A new draft with the text. The picture goes on the clipboard."
        case .things: return "A new to-do with the text as its notes. The picture goes on the clipboard."
        case .appleNotes: return "A new note with the picture inside. Asks for permission the first time."
        case .reminders: return "A new reminder with the text. The picture goes on the clipboard. Asks for permission the first time."
        }
    }

    private func notesGroup() -> NSView {
        var rows: [NSView] = NotesApp.allCases.filter(\.isInstalled).map { app in
            let id = NotesDestination(app: app).id
            return tools.toggle(app.title, blurb(app), !Preferences.sendToHidden.contains(id)) { on in
                var hidden = Preferences.sendToHidden
                if on { hidden.remove(id) } else { hidden.insert(id) }
                Preferences.sendToHidden = hidden
            }
        }
        if rows.isEmpty {
            rows = [tools.row("No notes apps found", "Obsidian, Bear, Drafts, Things, Apple Notes and Reminders show up here when installed.",
                              NSView())]
        } else {
            rows.append(tools.toggle("Include the text in the screenshot",
                                     "Read on your Mac when you send. Drafts, Things and Reminders only hold text, so they always get it.",
                                     Preferences.sendToIncludeText) { Preferences.sendToIncludeText = $0 })
        }
        return tools.group("Notes Apps", rows, "Only installed apps are listed in Send To.")
    }

    private func obsidianGroup() -> NSView {
        let choose = RetroUI.key("Choose…")
        tools.bind(choose) { [weak self] _ in self?.chooseVault() }
        vaultLabel.lineBreakMode = .byTruncatingMiddle
        refreshVault()
        let folder = NSStackView(views: [LCDTextBox(vaultLabel, width: 220), choose])
        folder.spacing = 10
        return tools.group("Obsidian", [
            tools.row("Vault folder", "The vault's folder on your Mac. Pictures are copied into its Skreener folder.", folder),
            tools.toggle("Append to the daily note", "Needs the Advanced URI plugin. Off: a note called Skreener/Captures.",
                         Preferences.obsidianDailyNote) { Preferences.obsidianDailyNote = $0 },
        ], nil)
    }

    private func refreshVault() {
        let path = Preferences.obsidianVaultPath
        vaultLabel.stringValue = path.isEmpty ? "Not chosen" : (path as NSString).abbreviatingWithTildeInPath
        vaultLabel.toolTip = path
    }

    private func chooseVault() {
        guard let window = tools.window() else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose the folder of your Obsidian vault."
        if !Preferences.obsidianVaultPath.isEmpty { panel.directoryURL = URL(fileURLWithPath: Preferences.obsidianVaultPath) }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Preferences.obsidianVaultPath = url.path
            self?.refreshVault()
        }
    }

    // MARK: Actions

    private func reloadActions() {
        for v in actionsHost.arrangedSubviews {
            actionsHost.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        let actions = Preferences.customActions
        var rows = actions.enumerated().map { actionRow($0.element, at: $0.offset, of: actions.count) }
        let add = RetroUI.key("Add Action…")
        tools.bind(add) { [weak self] _ in self?.edit(nil) }
        rows.append(tools.row("Add an action", "A shell command to run on a capture.", add))
        let group = tools.group("Actions", rows,
                                "Commands run with /bin/zsh -lc, for up to 60 seconds, and never hold up a capture. "
                                + "The capture's path is $1 and $SKREENER_FILE; $SKREENER_APP is the app it came from, and "
                                + "$SKREENER_TEXT the text in it (only read when the command mentions it). Example: "
                                + "rsync \"$SKREENER_FILE\" server:/shots/")
        actionsHost.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: actionsHost.widthAnchor).isActive = true
    }

    private func actionRow(_ action: CustomAction, at index: Int, of count: Int) -> NSView {
        var detail = CustomActions.excerpt(action.command.components(separatedBy: .newlines).first ?? "", limit: 70)
        var tags: [String] = []
        if action.runAfterCapture { tags.append("after every capture") }
        if action.copyOutput { tags.append("copies the output") }
        if !tags.isEmpty { detail += "\n" + tags.joined(separator: " · ") }

        let buttons = NSStackView(views: [
            iconButton("chevron.up", "Move Up", enabled: index > 0) { [weak self] in self?.move(index, by: -1) },
            iconButton("chevron.down", "Move Down", enabled: index < count - 1) { [weak self] in self?.move(index, by: 1) },
            iconButton("pencil", "Edit") { [weak self] in self?.edit(action) },
            iconButton("trash", "Delete") { [weak self] in self?.confirmDelete(action) },
        ])
        buttons.spacing = 6
        return tools.row(action.name, detail.isEmpty ? nil : detail, buttons)
    }

    private func iconButton(_ symbol: String, _ tip: String, enabled: Bool = true, _ run: @escaping () -> Void) -> NSButton {
        let b = RetroUI.key(symbol: symbol, tip: tip, height: RetroUI.textKeyHeight)
        b.isEnabled = enabled
        tools.bind(b) { _ in run() }
        return b
    }

    private func move(_ index: Int, by offset: Int) {
        var actions = Preferences.customActions
        let target = index + offset
        guard actions.indices.contains(index), actions.indices.contains(target) else { return }
        actions.swapAt(index, target)
        Preferences.customActions = actions
        reloadActions()
    }

    private func confirmDelete(_ action: CustomAction) {
        guard let window = tools.window() else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \"\(action.name)\"?"
        alert.informativeText = "The action goes away from Send To. Its command isn't kept."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            Preferences.customActions.removeAll { $0.id == action.id }
            self?.reloadActions()
        }
    }

    /// The sheet for a new action (`existing` nil) or an existing one.
    private func edit(_ existing: CustomAction?) {
        guard let window = tools.window() else { return }
        let name = NSTextField(string: existing?.name ?? "")
        name.placeholderString = "Name, e.g. Upload to my server"
        let command = NSTextField(string: existing?.command ?? "")
        command.placeholderString = "Shell command, e.g. rsync \"$SKREENER_FILE\" server:/shots/"
        command.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        command.usesSingleLineMode = false
        command.cell?.wraps = true
        command.cell?.isScrollable = false
        command.lineBreakMode = .byWordWrapping
        let after = NSButton(checkboxWithTitle: "Run after every capture", target: nil, action: nil)
        after.state = existing?.runAfterCapture == true ? .on : .off
        let copy = NSButton(checkboxWithTitle: "Copy the output to the clipboard", target: nil, action: nil)
        copy.state = existing?.copyOutput == true ? .on : .off

        let fields = NSStackView(views: [NSTextField(labelWithString: "Name"), name,
                                         NSTextField(labelWithString: "Command"), command, after, copy])
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 6
        for field in [name, command] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 400).isActive = true
        }
        command.heightAnchor.constraint(equalToConstant: 64).isActive = true
        fields.setFrameSize(fields.fittingSize)

        let alert = NSAlert()
        alert.messageText = existing == nil ? "New Action" : "Edit Action"
        alert.informativeText = "The command gets the capture as $1 and $SKREENER_FILE."
        alert.accessoryView = fields
        alert.addButton(withTitle: existing == nil ? "Add" : "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = name
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let title = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let shell = command.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !shell.isEmpty else { NSSound.beep(); return }
            var actions = Preferences.customActions
            var action = existing ?? CustomAction(name: title, command: shell)
            action.name = title
            action.command = shell
            action.runAfterCapture = after.state == .on
            action.copyOutput = copy.state == .on
            if let i = actions.firstIndex(where: { $0.id == action.id }) { actions[i] = action } else { actions.append(action) }
            Preferences.customActions = actions
            self?.reloadActions()
        }
    }
}
