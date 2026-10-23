import AppKit

/// Capture Text's scratch pad (#134): a small floating window with the recognized text, to fix it up before copying.
/// Copy to Clipboard (⌘Return) copies the whole text and closes it; Esc or the close button closes it without copying.
/// Closing forgets the text: the next Capture Text starts a fresh one.
final class TextScratchPad: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    @MainActor private static var current: TextScratchPad?

    /// Shows `text` in the scratch pad, centered on `screen`; a pad that is already open takes the new text.
    @MainActor static func show(_ text: String, on screen: NSScreen?) {
        let pad = current ?? TextScratchPad()
        current = pad
        pad.textView.string = text
        pad.textView.undoManager?.removeAllActions()
        pad.textView.selectAll(nil)
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

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let join = NSButton(title: "Join Lines", target: self, action: #selector(joinLines))
        join.toolTip = "Turn the selected lines (or all of them) into one line"
        let copy = NSButton(title: "Copy to Clipboard", target: self, action: #selector(copyAndClose))
        copy.bezelColor = .controlAccentColor
        copy.keyEquivalent = "\r"
        copy.keyEquivalentModifierMask = [.command]
        copy.toolTip = "Copy all the text and close (⌘Return)"
        count.textColor = .secondaryLabelColor
        count.font = .systemFont(ofSize: 11)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: [join, count, spacer, copy])
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

    @objc private func copyAndClose() {
        let text = textView.string
        guard !text.isEmpty else { NSSound.beep(); return }
        TextRecognizer.copyText(text)
        Sound.play("Pop")
        close()
        let lines = text.split(separator: "\n").count
        Notifier.confirm(lines == 1 ? "Copied 1 line of text" : "Copied \(lines) lines of text")
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
        textView.string = ""
        if Self.current === self { Self.current = nil }
    }
}

/// The scratch pad's text view: Esc closes the pad instead of offering completions.
private final class ScratchTextView: NSTextView {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
