import AppKit

/// Capture Text's scratch pad (#134): a small floating window with the recognized text, to fix it up before copying.
/// Copy to Clipboard (⌘Return) copies the whole text and closes it; Esc or the close button closes it without copying.
/// Closing forgets the text: the next Capture Text starts a fresh one. While it is open, another Capture Text adds its
/// text on its own line at the cursor (#261); the cursor starts at the end, so by default each capture adds a new line.
/// Speak (⌥⌘S) reads the selection, or all the text, aloud; it turns into Stop until the speech ends (#268).
/// With formatting kept, the text is rich (#326): headings, lists, bold, italic, code and colors, with a toolbar above
/// it, and copying turns what is shown back into Markdown, clean text and HTML.
/// Split into Lines (⇧⌥I) turns the selection into one selection per line (#334); ⌘C then copies each line as its own
/// clipboard entry, first line on top.
final class TextScratchPad: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSMenuItemValidation {
    @MainActor private static var current: TextScratchPad?

    /// Shows `text` in the scratch pad, centered on `screen`; a pad that is already open adds it at the cursor.
    /// With `blocks` (formatting kept) the pad shows them as rich text; `text` is then their Markdown, used only by a
    /// pad already open without formatting.
    @MainActor static func show(_ text: String, blocks: [FormattedText.Block]? = nil, on screen: NSScreen?) {
        let pad = current ?? TextScratchPad()
        current = pad
        if pad.window?.isVisible == true, !pad.textView.string.isEmpty {
            if !pad.formatted {
                pad.insert(NSAttributedString(string: text))
            } else if let blocks {
                pad.insert(FormattedText.attributed(blocks))
            } else {
                pad.insert(NSAttributedString(string: text, attributes: FormattedText.attributes(.init(), in: .body)))
            }
        } else {
            pad.setFormatted(blocks != nil)
            if let blocks {
                pad.textView.textStorage?.setAttributedString(FormattedText.attributed(blocks))
                pad.textView.typingAttributes = FormattedText.attributes(.init(), in: .body)
            } else {
                pad.textView.string = text
            }
            pad.textView.undoManager?.removeAllActions()
            pad.textView.setSelectedRange(NSRange(location: (pad.textView.string as NSString).length, length: 0))
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
    private let toolbar = NSStackView()
    private let paragraphMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private var formatted = false
    /// The running one-entry-per-line copy (#334); cancelled by another copy or by closing the pad.
    private var separateCopy: Task<Void, Never>?

    /// The pause between one-entry-per-line writes. Clipboard managers poll the pasteboard (most about twice a second),
    /// so writes closer together than that are merged into one history entry or missed.
    private static let separateCopyInterval = 0.6

    /// The toolbar's colors: red, blue, green.
    private static let palette = [FormattedText.RGB(r: 0.86, g: 0.15, b: 0.15), FormattedText.RGB(r: 0.12, g: 0.4, b: 0.9),
                                  FormattedText.RGB(r: 0.1, g: 0.6, b: 0.25)]
    /// The paragraph menu's kinds, in order.
    private static let kinds: [FormattedText.Paragraph] = [.heading(1), .heading(2), .body]

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 360),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Captured Text"
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 460, height: 260)
        super.init(window: w)
        w.delegate = self

        textView.isRichText = false
        textView.importsGraphics = false
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
        // The shortcuts also work while typing, which the combo button doesn't see. ⌘Return always copies.
        textView.onCopyKind = { [weak self] kind in
            guard let self, kind == .standard || self.formatted else { return false }
            self.copy(kind)
            return true
        }
        // ⌘B and ⌘I: the app has no Format menu.
        textView.onSplit = { [weak self] in self?.splitIntoLines() }
        textView.onCopySeparately = { [weak self] in self?.copySeparately() }
        textView.onSingleCopy = { [weak self] in self?.separateCopy?.cancel() }
        textView.onStyleKey = { [weak self] key in
            guard let self, self.formatted else { return false }
            switch key {
            case "b": self.toggleBold()
            case "i": self.toggleItalic()
            default: return false
            }
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
        let markdown = NSMenuItem(title: "Copy as Markdown", action: #selector(copyMarkdownAndClose), keyEquivalent: "\r")
        markdown.keyEquivalentModifierMask = [.command, .shift]
        markdown.toolTip = "Copy with the Markdown as the plain text, for GitHub (⇧⌘Return)"
        let plainOnly = NSMenuItem(title: "Copy Plain Text Only", action: #selector(copyPlainOnlyAndClose), keyEquivalent: "\r")
        plainOnly.keyEquivalentModifierMask = [.command, .option]
        plainOnly.toolTip = "Copy clean text and nothing else (⌥⌘Return)"
        let copyMenu = NSMenu()
        [markdown, plainOnly].forEach { $0.target = self; copyMenu.addItem($0) }
        let copy = NSComboButton(title: "Copy to Clipboard", menu: copyMenu, target: self, action: #selector(copyAndClose))
        copy.style = .split
        copy.toolTip = "Copy all the text and close (⌘Return). The arrow has Copy as Markdown and Copy Plain Text Only."
        count.textColor = .secondaryLabelColor
        count.font = .systemFont(ofSize: 11)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: [join, speakButton, count, spacer, copy])
        bar.spacing = 10

        buildToolbar()
        // The toolbar shows only with formatting; a hidden view leaves no gap in the stack.
        let column = NSStackView(views: [toolbar, scroll, bar])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.distribution = .fill
        column.setCustomSpacing(10, after: scroll)
        scroll.setContentHuggingPriority(.init(1), for: .vertical)
        scroll.setContentCompressionResistancePriority(.init(1), for: .vertical)

        let content = NSView()
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            scroll.widthAnchor.constraint(equalTo: column.widthAnchor),
            bar.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        w.contentView = content
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Title / Heading / Body, Bold, Italic, Code, the two lists, Outdent / Indent, the colors and Clear formatting.
    private func buildToolbar() {
        paragraphMenu.addItems(withTitles: ["Title", "Heading", "Body"])
        paragraphMenu.selectItem(at: 2)
        paragraphMenu.controlSize = .small
        paragraphMenu.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        paragraphMenu.target = self
        paragraphMenu.action = #selector(changeParagraph(_:))
        paragraphMenu.toolTip = "Make the paragraph a title, a heading or body text"

        func button(_ image: NSImage?, _ tip: String, _ action: Selector, tag: Int = 0) -> NSButton {
            let b = NSButton(image: image ?? NSImage(), target: self, action: action)
            b.controlSize = .small
            b.toolTip = tip
            b.tag = tag
            b.widthAnchor.constraint(equalToConstant: 28).isActive = true
            return b
        }
        func symbol(_ name: String, _ tip: String, _ action: Selector) -> NSButton {
            button(NSImage(systemSymbolName: name, accessibilityDescription: tip), tip, action)
        }
        let dots = zip(Self.palette, ["Red", "Blue", "Green"]).enumerated().map { i, color in
            button(Self.dot(color.0), "\(color.1) text; again to take it off", #selector(applyColor(_:)), tag: i)
        }
        let groups: [[NSView]] = [
            [paragraphMenu],
            [symbol("bold", "Bold (⌘B)", #selector(toggleBold)),
             symbol("italic", "Italic (⌘I)", #selector(toggleItalic)),
             symbol("chevron.left.forwardslash.chevron.right", "Code", #selector(toggleCode))],
            [symbol("list.bullet", "Bulleted list", #selector(toggleBullets)),
             symbol("list.number", "Numbered list", #selector(toggleNumbers)),
             symbol("decrease.indent", "Outdent (⇧Tab in a list)", #selector(outdentItems)),
             symbol("increase.indent", "Indent (Tab in a list)", #selector(indentItems))],
            dots + [symbol("eraser", "Clear formatting: plain text, keeping headings and lists", #selector(clearFormatting))],
            [symbol("text.line.first.and.arrowtriangle.forward", "Split into Lines (⇧⌥I)", #selector(splitIntoLines))],
        ]
        toolbar.spacing = 0
        for group in groups {
            group.forEach { toolbar.addArrangedSubview($0) }
            if let last = group.last { toolbar.setCustomSpacing(10, after: last) }
        }
        toolbar.isHidden = true
    }

    /// A colored dot for a color button.
    private static func dot(_ color: FormattedText.RGB) -> NSImage {
        let (r, g, b) = (color.r, color.g, color.b)
        return NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor(srgbRed: r, green: g, blue: b, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    /// Rich text and the toolbar with formatting; otherwise plain text as before #326.
    private func setFormatted(_ on: Bool) {
        formatted = on
        textView.isRichText = on
        toolbar.isHidden = !on
        if !on { textView.font = .systemFont(ofSize: 13) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copyMarkdownAndClose), #selector(copyPlainOnlyAndClose): return formatted
        default: return true
        }
    }

    // MARK: Copy, speak, join

    @objc private func copyAndClose() { copy(.standard) }
    @objc private func copyMarkdownAndClose() { copy(.markdown) }
    @objc private func copyPlainOnlyAndClose() { copy(.plainOnly) }

    private func copy(_ kind: TextRecognizer.CopyKind) {
        separateCopy?.cancel()
        let formatted = self.formatted   // closing forgets it
        var text = textView.string
        if formatted, let storage = textView.textStorage {
            // What is shown, as the blocks the Markdown, clean text and HTML are written from.
            let blocks = FormattedText.blocks(from: storage)
            let out = TextRecognizer.TextCopy(markdown: FormattedText.markdown(blocks), colors: FormattedText.colors(blocks))
            text = out.clean
            guard !out.markdown.isEmpty else { NSSound.beep(); return }
            TextRecognizer.copyFormatted(out, as: kind)
        } else {
            guard !text.isEmpty else { NSSound.beep(); return }
            TextRecognizer.copyText(text)
        }
        Sound.play("Pop")
        close()
        let lines = text.split(separator: "\n").count
        let what = lines == 1 ? "1 line of text" : "\(lines) lines of text"
        Notifier.confirm(formatted && kind == .markdown ? "Copied as Markdown" : "Copied \(what)")
    }

    /// The text without list markers.
    private var plainText: String {
        guard formatted, let storage = textView.textStorage else { return textView.string }
        return FormattedText.plainText(storage)
    }

    @objc private func toggleSpeech() {
        if speaker.isSpeaking { speaker.stop(); return }
        var spoken: String?
        let selection = textView.selectedRange()
        if formatted, let storage = textView.textStorage {
            if selection.length > 0 {
                spoken = TextSpeaker.textToSpeak(FormattedText.plainText(storage.attributedSubstring(from: selection)), selection: NSRange())
            }
            spoken = spoken ?? TextSpeaker.textToSpeak(plainText, selection: NSRange())
        } else {
            spoken = TextSpeaker.textToSpeak(textView.string, selection: selection)
        }
        guard let spoken else { NSSound.beep(); return }
        speakButton.title = "Stop"
        speaker.speak(spoken)
    }

    /// Selects each line of the selection (or of all the text) on its own, leaving out list markers, blank lines and
    /// the spaces around a line; ⌘C then copies the lines separately.
    @objc private func splitIntoLines() {
        let all = NSRange(location: 0, length: (textView.string as NSString).length)
        let ranges = textView.selectedRanges.map(\.rangeValue).flatMap {
            Self.lineRanges(in: textView.string, selection: $0.length == 0 ? all : $0, listMarkers: formatted)
        }
        guard !ranges.isEmpty else { NSSound.beep(); return }
        textView.selectedRanges = ranges.map { NSValue(range: $0) }
        textView.scrollRangeToVisible(ranges[0])
        window?.makeFirstResponder(textView)
    }

    /// Copies each selected range as its own clipboard entry, from the last to the first, so the newest entry in a
    /// clipboard manager is the first line and the clipboard ends up holding it. The pad stays open.
    private func copySeparately() {
        separateCopy?.cancel()
        let ns = textView.string as NSString
        let lines = textView.selectedRanges.map(\.rangeValue).sorted { $0.location < $1.location }
            .filter { $0.length > 0 }.map { ns.substring(with: $0) }
        guard !lines.isEmpty else { NSSound.beep(); return }
        PasteWatcher.shared.disarm()
        let order = Array(lines.reversed())
        separateCopy = Task { @MainActor [weak self] in
            for (i, text) in order.enumerated() {
                guard let self, !Task.isCancelled else { return }
                TextRecognizer.copyText(text)
                if i + 1 == order.count { break }
                MessageHUD.show("Copying \(i + 1) of \(order.count)…", symbol: "doc.on.doc", placement: .top)
                try? await Task.sleep(for: .seconds(Self.separateCopyInterval))
            }
            guard !Task.isCancelled else { return }
            Sound.play("Pop")
            Notifier.confirm("Copied \(order.count) lines separately")
        }
    }

    /// One range per line of `text` that `selection` touches (all the text when it is only a cursor), clipped to the
    /// selection, without the line break, the spaces around it or, with `listMarkers`, the rich pad's list marker
    /// (a tab, the marker, a tab). Blank lines are left out.
    nonisolated static func lineRanges(in text: String, selection: NSRange, listMarkers: Bool = true) -> [NSRange] {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        let range = selection.length == 0 ? whole : NSIntersectionRange(selection, whole)
        guard range.length > 0 else { return [] }
        func blank(_ i: Int) -> Bool {
            UnicodeScalar(ns.character(at: i)).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
        }
        var out: [NSRange] = []
        ns.enumerateSubstrings(in: ns.lineRange(for: range), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            let clipped = NSIntersectionRange(line, range)
            guard clipped.length > 0 else { return }
            var start = clipped.location, end = NSMaxRange(clipped)
            if listMarkers { start = max(start, line.location + FormattedText.markerLength(ns.substring(with: line))) }
            while start < end, blank(start) { start += 1 }
            while end > start, blank(end - 1) { end -= 1 }
            if end > start { out.append(NSRange(location: start, length: end - start)) }
        }
        return out
    }

    @objc private func joinLines() {
        let all = NSRange(location: 0, length: (textView.string as NSString).length)
        let range = textView.selectedRange().length > 0 ? textView.selectedRange() : all
        guard let storage = textView.textStorage else { return }
        let joined = formatted ? TextScratchPad.joined(storage.attributedSubstring(from: range))
            : NSAttributedString(string: TextScratchPad.joined((textView.string as NSString).substring(with: range)))
        replace(range, with: joined)
        textView.setSelectedRange(NSRange(location: range.location, length: joined.length))
        if formatted { renumber() }
    }

    /// Adds a later capture at the cursor (replacing any selection) on its own line(s), through the text view so it
    /// can be undone.
    private func insert(_ new: NSAttributedString) {
        guard let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        let ns = storage.string as NSString
        let newline = UInt16(UInt8(ascii: "\n"))
        let piece = NSMutableAttributedString(attributedString: new)
        let base = { (at: Int) -> [NSAttributedString.Key: Any] in self.formatted ? FormattedText.baseAttributes(storage.attributes(at: at, effectiveRange: nil)) : [:] }
        if range.location > 0, ns.character(at: range.location - 1) != newline {
            piece.insert(NSAttributedString(string: "\n", attributes: base(range.location - 1)), at: 0)
        }
        if NSMaxRange(range) < ns.length, ns.character(at: NSMaxRange(range)) != newline {
            let attributes = formatted && piece.length > 0 ? FormattedText.baseAttributes(piece.attributes(at: piece.length - 1, effectiveRange: nil)) : [:]
            piece.append(NSAttributedString(string: "\n", attributes: attributes))
        }
        replace(range, with: piece)
        // The cursor goes after the new text, so the next capture follows it.
        let end = range.location + piece.length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.scrollRangeToVisible(NSRange(location: end, length: 0))
        if formatted { renumber() }
    }

    /// Replaces `range` with `text` through the text view, so it can be undone.
    private func replace(_ range: NSRange, with text: NSAttributedString) {
        guard let storage = textView.textStorage, textView.shouldChangeText(in: range, replacementString: text.string) else { return }
        if formatted {
            storage.replaceCharacters(in: range, with: text)
        } else {
            storage.replaceCharacters(in: range, with: text.string)
        }
        textView.didChangeText()
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

    /// Rich `text` on one line, as `joined(_:)` does, keeping its styles. Later lines lose their list markers; the
    /// first keeps its own.
    nonisolated static func joined(_ text: NSAttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let ns = text.string as NSString
        func blank(_ i: Int) -> Bool { CharacterSet.whitespaces.contains(UnicodeScalar(ns.character(at: i)) ?? "x") }
        var first = true
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            defer { first = false }
            let style = range.length > 0 ? text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle : nil
            let mark = style?.textLists.isEmpty == false ? FormattedText.markerLength(ns.substring(with: range)) : 0
            var start = range.location + mark, end = NSMaxRange(range)
            while start < end, blank(start) { start += 1 }
            while end > start, blank(end - 1) { end -= 1 }
            guard end > start else { return }
            let piece = text.attributedSubstring(from: NSRange(location: start, length: end - start))
            if out.length == 0 {
                if first, mark > 0 { out.append(text.attributedSubstring(from: NSRange(location: range.location, length: mark))) }
            } else {
                let s = out.string
                if s.hasSuffix("-"), s.dropLast().last?.isLetter == true, piece.string.first?.isLowercase == true {
                    out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1))
                } else {
                    out.append(NSAttributedString(string: " ", attributes: out.attributes(at: out.length - 1, effectiveRange: nil)))
                }
            }
            out.append(piece)
        }
        return out
    }

    // MARK: Styles

    /// The selected text's pieces outside list markers, or nothing when only the cursor is placed.
    private func styledRanges() -> [NSRange] {
        guard let storage = textView.textStorage else { return [] }
        let selection = textView.selectedRange()
        guard selection.length > 0 else { return [] }
        let ns = storage.string as NSString
        var out: [NSRange] = []
        ns.enumerateSubstrings(in: ns.paragraphRange(for: selection), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let style = range.length > 0 ? storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle : nil
            let mark = style?.textLists.isEmpty == false ? FormattedText.markerLength(ns.substring(with: range)) : 0
            let piece = NSIntersectionRange(NSRange(location: range.location + mark, length: range.length - mark), selection)
            if piece.length > 0 { out.append(piece) }
        }
        return out
    }

    /// Whether every letter of the selection (or the typing style) is `test`.
    private func allStyled(_ test: (FormattedText.Style) -> Bool) -> Bool {
        let ranges = styledRanges()
        guard let storage = textView.textStorage, !ranges.isEmpty else {
            let typing = textView.typingAttributes
            return test(FormattedText.style(typing, in: FormattedText.paragraph(typing)))
        }
        let ns = storage.string as NSString
        var all = true
        for range in ranges {
            storage.enumerateAttributes(in: range) { attributes, piece, stop in
                guard ns.substring(with: piece).contains(where: { !$0.isWhitespace }) else { return }
                if !test(FormattedText.style(attributes, in: FormattedText.paragraph(attributes))) { all = false; stop.pointee = true }
            }
        }
        return all
    }

    /// Changes the selection's style (or, with only the cursor placed, the style of what is typed next).
    private func restyle(_ change: @escaping (inout FormattedText.Style) -> Void) {
        func changed(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            let kind = FormattedText.paragraph(attributes)
            var style = FormattedText.style(attributes, in: kind)
            change(&style)
            var out = FormattedText.attributes(style, in: kind)
            if let p = attributes[.paragraphStyle] { out[.paragraphStyle] = p }
            return out
        }
        let ranges = styledRanges()
        guard let storage = textView.textStorage, !ranges.isEmpty else {
            textView.typingAttributes = changed(textView.typingAttributes)
            return
        }
        let selection = textView.selectedRange()
        guard textView.shouldChangeText(in: selection, replacementString: nil) else { return }
        storage.beginEditing()
        for range in ranges {
            storage.enumerateAttributes(in: range) { attributes, piece, _ in storage.setAttributes(changed(attributes), range: piece) }
        }
        storage.endEditing()
        textView.didChangeText()
    }

    @objc private func toggleBold() {
        let on = !allStyled(\.bold)
        restyle { $0.bold = on }
    }

    @objc private func toggleItalic() {
        let on = !allStyled(\.italic)
        restyle { $0.italic = on }
    }

    @objc private func toggleCode() {
        let on = !allStyled(\.code)
        restyle { $0.code = on }
    }

    @objc private func applyColor(_ sender: NSButton) {
        guard Self.palette.indices.contains(sender.tag) else { return }
        let color = Self.palette[sender.tag]
        let on = !allStyled({ $0.color == color })
        restyle { $0.color = on ? color : nil }
    }

    @objc private func clearFormatting() { restyle { $0 = .init() } }

    // MARK: Paragraphs and lists

    /// A paragraph taken apart to change its kind or lists: its lists, its text after the marker, its line break.
    private struct Parts {
        var lists: [NSTextList]
        var kind: FormattedText.Paragraph
        var content: NSMutableAttributedString
        var newline: Bool
    }

    /// The paragraphs the selection touches, with their range (line breaks included).
    private func paragraphs() -> (range: NSRange, paragraphs: [Parts], starts: [Int]) {
        guard let storage = textView.textStorage else { return (NSRange(), [], []) }
        let ns = storage.string as NSString
        let whole = ns.paragraphRange(for: textView.selectedRange())
        var out: [Parts] = [], starts: [Int] = []
        ns.enumerateSubstrings(in: whole, options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
            let attributes = enclosing.length > 0 ? storage.attributes(at: enclosing.location, effectiveRange: nil) : self.textView.typingAttributes
            let lists = (attributes[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
            let mark = lists.isEmpty ? 0 : FormattedText.markerLength(ns.substring(with: range))
            let content = storage.attributedSubstring(from: NSRange(location: range.location + mark, length: range.length - mark))
            out.append(Parts(lists: lists, kind: lists.isEmpty ? FormattedText.paragraph(attributes) : .body,
                                 content: NSMutableAttributedString(attributedString: content), newline: enclosing.length > range.length))
            starts.append(range.location + mark)
        }
        if out.isEmpty {   // the cursor on the empty line after a final line break
            out = [Parts(lists: [], kind: FormattedText.paragraph(textView.typingAttributes), content: .init(), newline: false)]
            starts = [whole.location]
        }
        return (whole, out, starts)
    }

    /// Puts `new` in place of the paragraphs `paragraphs()` took apart, keeping the cursor in its place in the text
    /// (or selecting them all), then numbers the lists again.
    private func replaceParagraphs(_ old: (range: NSRange, paragraphs: [Parts], starts: [Int]), with new: [Parts]) {
        let selection = textView.selectedRange()
        let out = NSMutableAttributedString()
        var starts: [Int] = []
        var typing: [NSAttributedString.Key: Any]?
        for p in new {
            let style = p.lists.isEmpty ? FormattedText.paragraphStyle(p.kind) : FormattedText.listStyle(p.lists)
            var base = FormattedText.attributes(.init(), in: p.lists.isEmpty ? p.kind : .body)
            base[.paragraphStyle] = style
            if let list = p.lists.last { out.append(NSAttributedString(string: FormattedText.marker(list, number: 1), attributes: base)) }
            starts.append(old.range.location + out.length)
            let content = NSMutableAttributedString(attributedString: p.content)
            content.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: content.length))
            out.append(content)
            if p.newline { out.append(NSAttributedString(string: "\n", attributes: base)) }
            if p.content.length == 0 { typing = base }
        }
        replace(old.range, with: out)
        if selection.length == 0, let i = old.starts.lastIndex(where: { $0 <= selection.location }) ?? old.starts.indices.first {
            let offset = min(max(selection.location - old.starts[i], 0), new[i].content.length)
            textView.setSelectedRange(NSRange(location: starts[i] + offset, length: 0))
            if new[i].content.length == 0, let typing { textView.typingAttributes = typing }
        } else if let first = starts.first, let last = new.last, let lastStart = starts.last {
            textView.setSelectedRange(NSRange(location: first, length: lastStart + last.content.length - first))
        }
        renumber()
        updateParagraphMenu()
    }

    /// Writes every list item's marker for its place in its list, after items moved, came or went.
    private func renumber() {
        guard let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        var next: [ObjectIdentifier: Int] = [:]
        var fixes: [(range: NSRange, marker: NSAttributedString)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
            guard enclosing.length > 0, let style = storage.attribute(.paragraphStyle, at: enclosing.location, effectiveRange: nil) as? NSParagraphStyle,
                  let list = style.textLists.last else { return }
            let number = next[ObjectIdentifier(list)] ?? list.startingItemNumber
            next[ObjectIdentifier(list)] = number + 1
            let mark = NSRange(location: range.location, length: FormattedText.markerLength(ns.substring(with: range)))
            let wanted = FormattedText.marker(list, number: number)
            guard ns.substring(with: mark) != wanted else { return }
            var base = FormattedText.attributes(.init(), in: .body)
            base[.paragraphStyle] = style
            fixes.append((mark, NSAttributedString(string: wanted, attributes: base)))
        }
        guard !fixes.isEmpty else { return }
        var selection = textView.selectedRange()
        for fix in fixes.reversed() {
            replace(fix.range, with: fix.marker)
            let change = fix.marker.length - fix.range.length
            if fix.range.location < selection.location {
                selection.location = max(selection.location + change, fix.range.location + fix.marker.length)
            } else if fix.range.location < NSMaxRange(selection) {
                selection.length += change
            }
        }
        textView.setSelectedRange(selection)
    }

    /// The lists of the paragraph just before `location`'s.
    private func lists(before location: Int) -> [NSTextList] {
        guard location > 0, let storage = textView.textStorage else { return [] }
        return (storage.attribute(.paragraphStyle, at: location - 1, effectiveRange: nil) as? NSParagraphStyle)?.textLists ?? []
    }

    /// Makes the selected paragraphs bulleted or numbered items, or plain paragraphs when they all are already.
    private func toggleList(ordered: Bool) {
        let old = paragraphs()
        var new = old.paragraphs
        let all = new.allSatisfy { $0.lists.last.map { FormattedText.isOrdered($0) == ordered } ?? false }
        // New items join a list of the same kind just above.
        var top = lists(before: old.range.location).first.flatMap { FormattedText.isOrdered($0) == ordered ? $0 : nil }
        var swapped: [ObjectIdentifier: NSTextList] = [:]
        for i in new.indices {
            if all {
                new[i].lists = []
                new[i].kind = .body
            } else if let last = new[i].lists.last {
                guard FormattedText.isOrdered(last) != ordered else { continue }
                let list = swapped[ObjectIdentifier(last)] ?? FormattedText.list(depth: new[i].lists.count - 1, ordered: ordered)
                swapped[ObjectIdentifier(last)] = list
                new[i].lists[new[i].lists.count - 1] = list
            } else {
                let list = top ?? FormattedText.list(depth: 0, ordered: ordered)
                top = list
                new[i].lists = [list]
                new[i].content = FormattedText.restyled(new[i].content, to: .body)
                new[i].kind = .body
            }
        }
        replaceParagraphs(old, with: new)
    }

    @objc private func toggleBullets() { toggleList(ordered: false) }
    @objc private func toggleNumbers() { toggleList(ordered: true) }
    @objc private func indentItems() { shiftLists(by: 1) }
    @objc private func outdentItems() { shiftLists(by: -1) }

    /// Moves the selected list items a level in or out; out of the top level they are plain paragraphs. An item moved
    /// in joins the list of the item above at that level, if there is one.
    private func shiftLists(by step: Int) {
        let old = paragraphs()
        var new = old.paragraphs
        var above = lists(before: old.range.location)
        for i in new.indices {
            let lists = new[i].lists
            if let last = lists.last {
                if step < 0 {
                    new[i].lists.removeLast()
                } else if above.count > lists.count, zip(above, lists).allSatisfy({ $0 === $1 }) {
                    new[i].lists.append(above[lists.count])
                } else {
                    new[i].lists.append(FormattedText.list(depth: lists.count, ordered: FormattedText.isOrdered(last)))
                }
            }
            above = new[i].lists
        }
        replaceParagraphs(old, with: new)
    }

    @objc private func changeParagraph(_ sender: NSPopUpButton) {
        guard Self.kinds.indices.contains(sender.indexOfSelectedItem) else { return }
        let kind = Self.kinds[sender.indexOfSelectedItem]
        let old = paragraphs()
        let new = old.paragraphs.map { p in
            Parts(lists: [], kind: kind, content: FormattedText.restyled(p.content, to: kind), newline: p.newline)
        }
        replaceParagraphs(old, with: new)
        window?.makeFirstResponder(textView)
    }

    /// The paragraph menu shows the kind of the cursor's paragraph.
    private func updateParagraphMenu() {
        guard formatted, let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        let paragraph = ns.paragraphRange(for: textView.selectedRange())
        let attributes = paragraph.length > 0 ? storage.attributes(at: paragraph.location, effectiveRange: nil) : textView.typingAttributes
        let lists = (attributes[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        let kind = lists.isEmpty ? FormattedText.paragraph(attributes) : .body
        paragraphMenu.selectItem(at: Self.kinds.firstIndex(of: kind) ?? 2)
    }

    /// The list item the cursor is in: its range (without the line break), marker length and whether it has text.
    private func listItemAtCursor() -> (range: NSRange, marker: Int, empty: Bool)? {
        guard let storage = textView.textStorage, textView.selectedRange().length == 0 else { return nil }
        let ns = storage.string as NSString
        let enclosing = ns.paragraphRange(for: textView.selectedRange())
        guard enclosing.length > 0,
              let style = storage.attribute(.paragraphStyle, at: enclosing.location, effectiveRange: nil) as? NSParagraphStyle,
              !style.textLists.isEmpty else { return nil }
        var range = enclosing
        while range.length > 0, ns.character(at: NSMaxRange(range) - 1) == UInt16(UInt8(ascii: "\n")) { range.length -= 1 }
        let mark = FormattedText.markerLength(ns.substring(with: range))
        let empty = ns.substring(with: NSRange(location: range.location + mark, length: range.length - mark)).allSatisfy(\.isWhitespace)
        return (range, mark, empty)
    }

    /// Return in a list item starts the next item (an empty item leaves the list instead); Return at the end of a
    /// heading carries on in body text.
    private func richNewline() -> Bool {
        guard let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        if let item = listItemAtCursor() {
            if item.empty { shiftLists(by: -1); return true }
            guard let style = storage.attribute(.paragraphStyle, at: item.range.location, effectiveRange: nil) as? NSParagraphStyle,
                  let list = style.textLists.last else { return false }
            let at = max(selection.location, item.range.location + item.marker)
            var base = FormattedText.attributes(.init(), in: .body)
            base[.paragraphStyle] = style
            let piece = NSAttributedString(string: "\n" + FormattedText.marker(list, number: 1), attributes: base)
            replace(NSRange(location: at, length: 0), with: piece)
            textView.setSelectedRange(NSRange(location: at + piece.length, length: 0))
            renumber()
            return true
        }
        let ns = storage.string as NSString
        let enclosing = ns.paragraphRange(for: selection)
        guard selection.length == 0, enclosing.length > 0 else { return false }
        let attributes = storage.attributes(at: enclosing.location, effectiveRange: nil)
        guard case .heading = FormattedText.paragraph(attributes) else { return false }
        let end = NSMaxRange(enclosing) - (ns.character(at: NSMaxRange(enclosing) - 1) == UInt16(UInt8(ascii: "\n")) ? 1 : 0)
        guard selection.location == end else { return false }
        replace(selection, with: NSAttributedString(string: "\n", attributes: FormattedText.baseAttributes(attributes)))
        textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
        textView.typingAttributes = FormattedText.attributes(.init(), in: .body)
        updateParagraphMenu()
        return true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // The list and heading handling follows one cursor; with several selections the text view does its own thing.
        guard formatted, textView.selectedRanges.count == 1 else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            return richNewline()
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            // Tab and ⇧Tab move list items; elsewhere Tab types a tab.
            guard listItemAtCursor() != nil || (textView.selectedRange().length > 0 && !paragraphs().paragraphs.allSatisfy(\.lists.isEmpty))
            else { return false }
            shiftLists(by: commandSelector == #selector(NSResponder.insertTab(_:)) ? 1 : -1)
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            // Delete right after an item's marker takes the item out a level, as in TextEdit.
            guard let item = listItemAtCursor(), textView.selectedRange().location == item.range.location + item.marker else { return false }
            shiftLists(by: -1)
            return true
        default:
            return false
        }
    }

    func textDidChange(_ notification: Notification) { updateCount() }

    func textViewDidChangeSelection(_ notification: Notification) { updateParagraphMenu() }

    private func updateCount() {
        let text = plainText
        let lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
        count.stringValue = "\(lines) line\(lines == 1 ? "" : "s"), \(text.count) character\(text.count == 1 ? "" : "s")"
    }

    func windowWillClose(_ notification: Notification) {
        // Closing ends this text session.
        speaker.stop()
        separateCopy?.cancel()
        textView.string = ""
        setFormatted(false)
        if Self.current === self { Self.current = nil }
    }
}

/// The scratch pad's text view: Esc closes the pad instead of offering completions.
private final class ScratchTextView: NSTextView {
    var onCancel: (() -> Void)?

    /// Copies as the given kind for ⌘Return (standard), ⇧⌘Return (Markdown) and ⌥⌘Return (plain text only); false when it isn't handled.
    var onCopyKind: ((TextRecognizer.CopyKind) -> Bool)?

    /// Styles the text for ⌘B ("b") and ⌘I ("i"); false when it isn't handled.
    var onStyleKey: ((String) -> Bool)?

    /// Splits the selection into one selection per line, for ⇧⌥I and the context menu.
    var onSplit: (() -> Void)?

    /// Copies the several selections as separate clipboard entries (⌘C with more than one selection).
    var onCopySeparately: (() -> Void)?

    /// Called for an ordinary ⌘C, to stop a one-entry-per-line copy still running.
    var onSingleCopy: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func copy(_ sender: Any?) {
        if selectedRanges.count > 1 {
            onCopySeparately?()
        } else {
            onSingleCopy?()
            super.copy(sender)
        }
    }

    @objc func splitIntoLines(_ sender: Any?) { onSplit?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        if !menu.items.contains(where: { $0.action == #selector(splitIntoLines(_:)) }) {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Split into Lines", action: #selector(splitIntoLines(_:)), keyEquivalent: "i")
            item.keyEquivalentModifierMask = [.shift, .option]
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 36 || event.keyCode == 76 {   // Return, keypad Enter
            if mods == .command, onCopyKind?(.standard) == true { return true }
            if mods == [.command, .shift], onCopyKind?(.markdown) == true { return true }
            if mods == [.command, .option], onCopyKind?(.plainOnly) == true { return true }
        }
        if event.keyCode == 34, mods == [.shift, .option] {   // I: matched by key, as ⌥ changes the character
            onSplit?()
            return true
        }
        if mods == .command, let key = event.charactersIgnoringModifiers?.lowercased(), onStyleKey?(key) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}
