import AppKit

/// Capture Text's scratch pad (#134): a small floating window with the recognized text, to fix it up before copying.
/// Copy to Clipboard (⌘Return) copies the whole text and closes it; Esc or the close button closes it without copying.
/// Closing forgets the text: the next Capture Text starts a fresh one. While it is open, another Capture Text adds its
/// text on its own line at the cursor (#261); the cursor starts at the end, so by default each capture adds a new line.
/// Speak (⌥⌘S) reads the selection, or all the text, aloud; it turns into Stop until the speech ends (#268).
final class TextScratchPad: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    @MainActor private static var current: TextScratchPad?

    /// Shows `text` in the scratch pad, centered on `screen`; a pad that is already open adds it at the cursor.
    /// `formatted` text is Markdown, copied with rich text beside it, where `colors` paint their words.
    @MainActor static func show(_ text: String, colors: [FormattedText.Painted] = [], formatted: Bool = false,
                                on screen: NSScreen?) {
        let pad = current ?? TextScratchPad()
        current = pad
        if pad.window?.isVisible == true, !pad.textView.string.isEmpty {
            pad.insert(text)
            pad.colors += colors
            pad.formatted = pad.formatted || formatted
        } else {
            pad.colors = colors
            pad.formatted = formatted
            pad.textView.string = text
            pad.textView.undoManager?.removeAllActions()
            pad.textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        pad.updateCount()
        if pad.window?.isVisible != true, let window = pad.window {
            let area = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
            window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        pad.showWindow(nil)
        pad.window?.makeKeyAndOrderFront(nil)
        pad.window?.makeFirstResponder(pad.textView)
    }

    private let textView = ScratchTextView()
    private let count = NSTextField(labelWithString: "")
    private let speakButton = NSButton(title: "Speak", target: nil, action: nil)
    private let speaker = TextSpeaker()
    private var colors: [FormattedText.Painted] = []
    private let copyMenu = NSPopUpButton(frame: .zero, pullsDown: true)
    private var formatted = false {
        didSet { copyMenu.isHidden = !formatted }
    }

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Captured Text"
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 340, height: 200)
        super.init(window: w)
        w.delegate = self

        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.onCancel = { [weak self] in self?.close() }
        // The menu's shortcuts also work while typing, which the pop-up button's menu doesn't see.
        textView.onCopyKind = { [weak self] kind in
            guard let self, self.formatted else { return false }
            self.copy(kind)
            return true
        }

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let join = NSButton(title: "Join Lines", target: self, action: #selector(joinLines))
        join.toolTip = "Turn the selected lines (or all of them) into one line"
        speakButton.target = self
        speakButton.action = #selector(toggleSpeech)
        speakButton.keyEquivalent = "s"
        speakButton.keyEquivalentModifierMask = [.command, .option]
        speakButton.toolTip = "Read the selection, or all the text, aloud (⌥⌘S)"
        speaker.onFinish = { [weak self] in self?.speakButton.title = "Speak" }
        let copy = NSButton(title: "Copy to Clipboard", target: self, action: #selector(copyAndClose))
        copy.bezelColor = .controlAccentColor
        copy.keyEquivalent = "\r"
        copy.keyEquivalentModifierMask = [.command]
        copy.toolTip = "Copy all the text and close (⌘Return). Formatted text pastes as rich text, or clean text in plain fields"
        copyMenu.isHidden = true
        copyMenu.toolTip = "Other ways to copy"
        copyMenu.addItem(withTitle: "")   // a pull-down shows its first item as the title
        copyMenu.item(at: 0)?.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "More copy options")
        let markdown = NSMenuItem(title: "Copy as Markdown", action: #selector(copyMarkdownAndClose), keyEquivalent: "\r")
        markdown.keyEquivalentModifierMask = [.command, .shift]
        markdown.toolTip = "Copy with the Markdown as the plain text, for GitHub (⇧⌘Return)"
        let plainOnly = NSMenuItem(title: "Copy Plain Text Only", action: #selector(copyPlainOnlyAndClose), keyEquivalent: "\r")
        plainOnly.keyEquivalentModifierMask = [.command, .option]
        plainOnly.toolTip = "Copy clean text and nothing else (⌥⌘Return)"
        [markdown, plainOnly].forEach { $0.target = self; copyMenu.menu?.addItem($0) }
        count.textColor = .secondaryLabelColor
        count.font = .systemFont(ofSize: 11)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: [join, speakButton, count, spacer, copyMenu, copy])
        bar.spacing = 10

        let content = NSView()
        [scroll, bar].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; content.addSubview($0) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bar.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        w.contentView = content
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func copyAndClose() { copy(.standard) }
    @objc private func copyMarkdownAndClose() { copy(.markdown) }
    @objc private func copyPlainOnlyAndClose() { copy(.plainOnly) }

    private func copy(_ kind: TextRecognizer.CopyKind) {
        let text = textView.string
        guard !text.isEmpty else { NSSound.beep(); return }
        let formatted = self.formatted   // closing forgets it
        if formatted { TextRecognizer.copyFormatted(text, colors: colors, as: kind) } else { TextRecognizer.copyText(text) }
        Sound.play("Pop")
        close()
        let lines = text.split(separator: "\n").count
        let what = lines == 1 ? "1 line of text" : "\(lines) lines of text"
        Notifier.confirm(formatted && kind == .markdown ? "Copied as Markdown" : "Copied \(what)")
    }

    @objc private func toggleSpeech() {
        if speaker.isSpeaking { speaker.stop(); return }
        guard let text = TextSpeaker.textToSpeak(textView.string, selection: textView.selectedRange()) else {
            NSSound.beep()
            return
        }
        speakButton.title = "Stop"
        speaker.speak(text)
    }

    @objc private func joinLines() {
        let all = NSRange(location: 0, length: (textView.string as NSString).length)
        let range = textView.selectedRange().length > 0 ? textView.selectedRange() : all
        let joined = TextScratchPad.joined((textView.string as NSString).substring(with: range))
        // Through the text view so the change can be undone.
        guard textView.shouldChangeText(in: range, replacementString: joined) else { return }
        textView.replaceCharacters(in: range, with: joined)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location, length: (joined as NSString).length))
    }

    /// Adds a later capture at the cursor (replacing any selection), through the text view so it can be undone.
    private func insert(_ text: String) {
        let range = textView.selectedRange()
        let piece = TextScratchPad.lineInsertion(text, into: textView.string, replacing: range)
        guard textView.shouldChangeText(in: range, replacementString: piece) else { return }
        textView.replaceCharacters(in: range, with: piece)
        textView.didChangeText()
        // The cursor goes after the new text, so the next capture follows it.
        let end = range.location + (piece as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.scrollRangeToVisible(NSRange(location: end, length: 0))
    }

    /// `new` padded with line breaks so it sits on its own line(s) when it replaces `range` of `text`.
    nonisolated static func lineInsertion(_ new: String, into text: String, replacing range: NSRange) -> String {
        let ns = text as NSString
        let before = range.location > 0 ? ns.character(at: range.location - 1) : nil
        let after = NSMaxRange(range) < ns.length ? ns.character(at: NSMaxRange(range)) : nil
        let newline = UInt16(UInt8(ascii: "\n"))
        var piece = new
        if let before, before != newline { piece = "\n" + piece }
        if let after, after != newline { piece += "\n" }
        return piece
    }

    /// `text` on one line: line breaks become single spaces, and a word hyphenated across a line break is mended.
    nonisolated static func joined(_ text: String) -> String {
        var out = ""
        for line in text.split(whereSeparator: \.isNewline) {
            let piece = line.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }
            if out.hasSuffix("-"), out.dropLast().last?.isLetter == true, piece.first?.isLowercase == true {
                out.removeLast()
            } else if !out.isEmpty {
                out += " "
            }
            out += piece
        }
        return out
    }

    func textDidChange(_ notification: Notification) { updateCount() }

    private func updateCount() {
        let text = textView.string
        let lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
        count.stringValue = "\(lines) line\(lines == 1 ? "" : "s"), \(text.count) character\(text.count == 1 ? "" : "s")"
    }

    func windowWillClose(_ notification: Notification) {
        // Closing ends this text session.
        speaker.stop()
        textView.string = ""
        colors = []
        formatted = false
        if Self.current === self { Self.current = nil }
    }
}

/// The scratch pad's text view: Esc closes the pad instead of offering completions.
private final class ScratchTextView: NSTextView {
    var onCancel: (() -> Void)?

    /// Copies as the given kind for ⇧⌘Return (Markdown) and ⌥⌘Return (plain text only); false when it isn't handled.
    var onCopyKind: ((TextRecognizer.CopyKind) -> Bool)?

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 36 || event.keyCode == 76 {   // Return, keypad Enter
            if mods == [.command, .shift], onCopyKind?(.markdown) == true { return true }
            if mods == [.command, .option], onCopyKind?(.plainOnly) == true { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}
