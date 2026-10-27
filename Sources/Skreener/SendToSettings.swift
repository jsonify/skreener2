import AppKit

/// Settings → Send To: the user's custom actions (#276), which can be added, edited, reordered and deleted. They show
/// in the Send To menu, and the ones set to run after every capture run once a screenshot is saved.
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

    func build(_ tools: Tools) -> [NSView] {
        self.tools = tools
        actionsHost.orientation = .vertical
        actionsHost.alignment = .leading
        actionsHost.spacing = 0
        reloadActions()
        return [actionsHost]
    }

    // MARK: Actions

    private func reloadActions() {
        for v in actionsHost.arrangedSubviews {
            actionsHost.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        let actions = Preferences.customActions
        var rows = actions.enumerated().map { actionRow($0.element, at: $0.offset, of: actions.count) }
        let add = NSButton(title: "Add Action…", target: nil, action: nil)
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
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(),
                         target: nil, action: nil)
        b.isBordered = false
        b.contentTintColor = .secondaryLabelColor
        b.toolTip = tip
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
