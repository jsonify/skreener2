import AppKit

/// Ask Claude's window (#252), opened from the sparkles button in the editor's footer: pick Explain, Summarize,
/// Alt Text or a question of your own, press Ask (⌘Return), and the answer shows below with a Copy button. Nothing is
/// sent until Ask is pressed. One panel at a time: opening it for another screenshot starts over with that one.
final class AskClaudePanel: NSWindowController, NSWindowDelegate {
    @MainActor private static var current: AskClaudePanel?

    /// Shows the panel for `image` (the screenshot with its annotations), next to `parent` when given.
    @MainActor static func show(_ image: NSImage, from parent: NSWindow?) {
        let panel = current ?? AskClaudePanel()
        current = panel
        panel.image = image
        panel.reset()
        if panel.window?.isVisible != true, let window = panel.window {
            let area = (parent?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            let anchor = parent?.frame ?? area
            window.setFrameOrigin(NSPoint(x: anchor.midX - window.frame.width / 2, y: anchor.midY - window.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.showWindow(nil)
        panel.window?.makeKeyAndOrderFront(nil)
    }

    private var image: NSImage?
    /// Bumped by every Ask and reset, so an answer for an earlier question or screenshot is dropped.
    private var generation = 0
    /// Whether a question is on its way, and whether the text below is an answer (not a message) that can be copied.
    private var busy = false
    private var hasAnswer = false
    private let presets = NSSegmentedControl()
    private let questionField = NSTextField()
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let askButton = NSButton(title: "Ask Claude", target: nil, action: nil)
    private let settingsButton = NSButton(title: "Add API Key…", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let answerView = NSTextView()
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Ask Claude"
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 420, height: 320)
        super.init(window: w)
        w.delegate = self

        presets.segmentCount = AskClaude.Preset.allCases.count
        for p in AskClaude.Preset.allCases { presets.setLabel(p.title, forSegment: p.rawValue) }
        presets.trackingMode = .selectOne
        presets.selectedSegment = AskClaude.Preset.explain.rawValue
        presets.target = self
        presets.action = #selector(presetChanged)

        questionField.placeholderString = "Your question about the screenshot"
        questionField.target = self
        questionField.action = #selector(ask)

        notice.font = .systemFont(ofSize: 11)
        notice.textColor = .secondaryLabelColor

        askButton.target = self
        askButton.action = #selector(ask)
        askButton.bezelColor = .controlAccentColor
        askButton.keyEquivalent = "\r"
        askButton.keyEquivalentModifierMask = [.command]
        askButton.toolTip = "Send the screenshot and the question to Claude (⌘Return)"
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        answerView.isEditable = false
        answerView.isSelectable = true
        answerView.isRichText = false
        answerView.font = .systemFont(ofSize: 13)
        answerView.textContainerInset = NSSize(width: 6, height: 8)
        answerView.isVerticallyResizable = true
        answerView.autoresizingMask = [.width]
        answerView.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView()
        scroll.documentView = answerView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        copyButton.target = self
        copyButton.action = #selector(copyAnswer)
        copyButton.toolTip = "Copy the answer"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let askBar = NSStackView(views: [settingsButton, spinner, spacer, askButton])
        askBar.spacing = 10
        let copySpacer = NSView()
        copySpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let copyBar = NSStackView(views: [copySpacer, copyButton])

        let content = NSView()
        let views: [NSView] = [presets, questionField, notice, askBar, scroll, copyBar]
        views.forEach { $0.translatesAutoresizingMaskIntoConstraints = false; content.addSubview($0) }
        var constraints = [
            presets.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            presets.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            questionField.topAnchor.constraint(equalTo: presets.bottomAnchor, constant: 12),
            notice.topAnchor.constraint(equalTo: questionField.bottomAnchor, constant: 8),
            askBar.topAnchor.constraint(equalTo: notice.bottomAnchor, constant: 10),
            scroll.topAnchor.constraint(equalTo: askBar.bottomAnchor, constant: 12),
            copyBar.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            copyBar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ]
        for v in [questionField, notice, askBar, scroll, copyBar] {
            constraints += [v.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
                            v.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14)]
        }
        NSLayoutConstraint.activate(constraints)
        w.contentView = content

        // The key may be added or removed in Settings while the panel is open.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshKey() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private var preset: AskClaude.Preset { AskClaude.Preset(rawValue: presets.selectedSegment) ?? .explain }

    private func reset() {
        generation += 1
        busy = false
        hasAnswer = false
        spinner.stopAnimation(nil)
        answerView.string = ""
        refreshKey()
        presetChanged()
    }

    @objc private func presetChanged() {
        questionField.isEnabled = preset == .custom
        if preset == .custom { window?.makeFirstResponder(questionField) }
        refreshButtons()
    }

    private func refreshKey() {
        let hasKey = APIKeyStore.key != nil
        settingsButton.isHidden = hasKey
        notice.stringValue = hasKey
            ? "Ask sends this screenshot, with its annotations, and the question to Anthropic, using your API key. "
                + "Nothing is sent until you press it."
            : "Ask Claude needs your own Anthropic API key. Add it in Settings → Ask Claude; it's kept in your Keychain."
        refreshButtons()
    }

    private func refreshButtons() {
        askButton.isEnabled = APIKeyStore.key != nil && !busy
        copyButton.isEnabled = hasAnswer
    }

    @objc private func ask() {
        guard let image, let key = APIKeyStore.key else { refreshKey(); NSSound.beep(); return }
        guard let question = AskClaude.question(preset, custom: questionField.stringValue) else {
            window?.makeFirstResponder(questionField)
            NSSound.beep()
            return
        }
        guard let prepared = AskClaude.imageData(image) else { show("Couldn't read the screenshot."); return }
        let request = AskClaude.request(image: prepared.data, mediaType: prepared.mediaType, question: question, apiKey: key)
        generation += 1
        let asked = generation
        busy = true
        hasAnswer = false
        answerView.textColor = .secondaryLabelColor
        answerView.string = "Asking Claude…"
        spinner.startAnimation(nil)
        refreshButtons()
        Task { [weak self] in
            let result = await AskClaude.send(request)
            guard let self, self.generation == asked else { return }
            switch result {
            case .success(let text): self.show(text, failed: false)
            case .failure(let failure): self.show(failure.message)
            }
        }
    }

    private func show(_ text: String, failed: Bool = true) {
        busy = false
        hasAnswer = !failed
        spinner.stopAnimation(nil)
        answerView.textColor = failed ? .systemRed : .labelColor
        answerView.string = text
        answerView.scrollToBeginningOfDocument(nil)
        refreshButtons()
    }

    @objc private func copyAnswer() {
        let text = answerView.string
        guard hasAnswer, !text.isEmpty else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Sound.play("Pop")
        Notifier.confirm("Copied Claude's answer")
    }

    @objc private func openSettings() { SettingsWindowController.shared.present(askClaude: true) }

    func windowWillClose(_ notification: Notification) {
        // Closing drops the screenshot and any answer still on its way.
        generation += 1
        image = nil
        if Self.current === self { Self.current = nil }
    }
}
