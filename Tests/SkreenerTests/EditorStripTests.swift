import AppKit
import XCTest
@testable import Skreener

/// The editor's options row (colour, stroke, style…) under the status display: a click on any of its controls must
/// reach that control, before and after something is drawn, and a colour picked there must change what is selected.
@MainActor final class EditorStripTests: XCTestCase {
    private var savedTool: Tool = .select
    private var savedStyle: Style?

    override func setUp() async throws {
        _ = NSApplication.shared
        savedTool = Preferences.editorTool
        savedStyle = Preferences.editorStyle
    }

    override func tearDown() async throws {
        Preferences.editorTool = savedTool
        if let savedStyle { Preferences.editorStyle = savedStyle }
    }

    private func makeEditor() -> (EditorWindowController, NSWindow, CanvasView) {
        let image = NSImage(size: NSSize(width: 800, height: 500), flipped: false) { r in
            NSColor.white.setFill(); r.fill(); return true
        }
        let editor = EditorWindowController(image: image)
        guard let window = editor.window, let canvas = Self.find(CanvasView.self, in: window.contentView) else {
            XCTFail("no editor window or canvas")
            fatalError()
        }
        canvas.tool = .arrow
        window.contentView?.layoutSubtreeIfNeeded()
        return (editor, window, canvas)
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let v = view as? T { return v }
        for sub in view.subviews { if let v = find(type, in: sub) { return v } }
        return nil
    }

    private static func all(in view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + all(in: $0) } }

    private static func visible(_ v: NSView) -> Bool {
        var view: NSView? = v
        while let current = view {
            if current.isHidden { return false }
            view = current.superview
        }
        return v.bounds.width > 0 && v.bounds.height > 0
    }

    /// The options row: the stack that holds the colour swatches.
    private func optionsRow(in window: NSWindow) -> NSStackView? {
        guard let content = window.contentView, let swatches = Self.find(SwatchRow.self, in: content) else { return nil }
        return swatches.superview as? NSStackView
    }

    /// Every visible control in the options row whose middle a click doesn't reach, with what gets it instead.
    private func unreachable(in window: NSWindow) -> [String] {
        guard let row = optionsRow(in: window), let frameView = window.contentView?.superview else { return ["no options row"] }
        var problems: [String] = []
        for control in row.arrangedSubviews where Self.visible(control) && !(control is NSTextField) {
            let middle = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
            let hit = frameView.hitTest(frameView.convert(middle, from: nil))
            if hit == nil || !(hit!.isDescendant(of: control)) {
                problems.append("\(type(of: control)) at \(middle): hit \(hit.map { String(describing: type(of: $0)) } ?? "nothing")")
            }
        }
        return problems
    }

    private func mouse(_ type: NSEvent.EventType, at p: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// Draws an arrow across the middle of the canvas with the mouse.
    private func drawArrow(on canvas: CanvasView, in window: NSWindow) {
        let visible = canvas.visibleRect
        let a = canvas.convert(NSPoint(x: visible.midX - 80, y: visible.midY), to: nil)
        let b = canvas.convert(NSPoint(x: visible.midX + 80, y: visible.midY + 40), to: nil)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: a, in: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), in: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: b, in: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: b, in: window))
    }

    func testOptionsTakeClicksWhenTheEditorOpens() {
        let (editor, window, _) = makeEditor()
        defer { window.close(); _ = editor }
        XCTAssertNotNil(optionsRow(in: window))
        XCTAssertEqual(unreachable(in: window), [])
    }

    func testOptionsTakeClicksAfterDrawing() {
        let (editor, window, canvas) = makeEditor()
        defer { window.close(); _ = editor }
        drawArrow(on: canvas, in: window)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(canvas.hasSelection, "the arrow just drawn is selected")
        XCTAssertEqual(unreachable(in: window), [])
    }

    func testAColourPickedChangesTheArrowJustDrawn() throws {
        let (editor, window, canvas) = makeEditor()
        defer { window.close(); _ = editor }
        drawArrow(on: canvas, in: window)
        window.contentView?.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap(Self.find(SwatchRow.self, in: window.contentView))
        let before = canvas.contextStyle.color
        let swatch = try XCTUnwrap(Self.all(in: row).compactMap { $0 as? RoundSwatch }
            .first { !$0.isMore && $0.color.map { !Retro.sameColor($0, before) } == true })
        // Click it where it is on screen, as a person would: what the window hands the click to must be the swatch.
        let middle = swatch.convert(NSPoint(x: swatch.bounds.midX, y: swatch.bounds.midY), to: nil)
        let frameView = try XCTUnwrap(window.contentView?.superview)
        let hit = try XCTUnwrap(frameView.hitTest(frameView.convert(middle, from: nil)) as? RoundSwatch)
        hit.performClick(nil)
        XCTAssertTrue(Retro.sameColor(canvas.contextStyle.color, try XCTUnwrap(swatch.color)),
                      "the selected arrow takes the colour picked")
    }

    /// The options row's segmented control captioned `caption` (Fill, Style, Box).
    private func segmented(_ caption: String, in window: NSWindow) -> RetroSegmented? {
        guard let row = optionsRow(in: window) else { return nil }
        return row.arrangedSubviews.compactMap { $0 as? RetroSegmented }.first { $0.accessibilityLabel() == caption && Self.visible($0) }
    }

    /// How dark the control looks at `point` (its own coordinates): 0 black, 1 white.
    private static func brightness(of view: NSView, at point: NSPoint) -> CGFloat? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let x = Int(point.x * CGFloat(rep.pixelsWide) / view.bounds.width)
        let yUp = Int(point.y * CGFloat(rep.pixelsHigh) / view.bounds.height)
        let y = view.isFlipped ? yUp : rep.pixelsHigh - 1 - yUp
        return rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)?.brightnessComponent
    }

    /// Picks every Fill choice for the rectangle just drawn, as a click on screen would (the press tracked by the
    /// button, then released), and checks the choice shows as the dark key and the rectangle takes it.
    func testFillChoicesChangeTheRectangleJustDrawn() throws {
        let (editor, window, canvas) = makeEditor()
        defer { window.close(); _ = editor }
        canvas.tool = .rect
        window.makeKeyAndOrderFront(nil)
        drawArrow(on: canvas, in: window)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(canvas.hasSelection, "the rectangle just drawn is selected")
        XCTAssertEqual(canvas.contextTool, .rect)
        let fill = try XCTUnwrap(segmented("Fill", in: window), "a visible Fill control")
        let frameView = try XCTUnwrap(window.contentView?.superview)
        let segments = Self.all(in: fill).compactMap { $0 as? NSButton }
        XCTAssertEqual(segments.count, 3)
        var problems: [String] = []
        for (n, segment) in segments.enumerated().reversed() {
            let middle = segment.convert(NSPoint(x: segment.bounds.midX, y: segment.bounds.midY), to: nil)
            let hit = frameView.hitTest(frameView.convert(middle, from: nil))
            guard let hit, hit === segment else {
                problems.append("segment \(n): a click at \(middle) hits \(hit.map { String(describing: type(of: $0)) } ?? "nothing")")
                continue
            }
            NSApp.postEvent(mouse(.leftMouseUp, at: middle, in: window), atStart: false)
            window.sendEvent(mouse(.leftMouseDown, at: middle, in: window))
            if fill.indexOfSelectedItem != n { problems.append("segment \(n): the control shows \(fill.indexOfSelectedItem) chosen") }
            if canvas.contextStyle.fill.rawValue != fill.selectedTag() {
                problems.append("segment \(n): the rectangle's fill is \(canvas.contextStyle.fill) for tag \(fill.selectedTag())")
            }
            fill.layoutSubtreeIfNeeded()
            let edge = segment.convert(NSPoint(x: 3, y: segment.bounds.midY), to: fill)
            if let b = Self.brightness(of: fill, at: edge), b > 0.5 {
                problems.append("segment \(n): the chosen key isn't dark (brightness \(b), segment \(segment.frame))")
            }
        }
        XCTAssertEqual(problems, [])
    }
}
