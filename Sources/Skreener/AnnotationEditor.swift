import AppKit

enum Tool: Int, CaseIterable {
    case arrow, rect, ellipse, pen, text, pixelate
    var title: String { ["Arrow", "Rect", "Ellipse", "Pen", "Text", "Pixelate"][rawValue] }
}

struct Annotation {
    var tool: Tool
    var start: NSPoint
    var end: NSPoint
    var points: [NSPoint] = []
    var text: String = ""
    var color: NSColor
}

final class CanvasView: NSView {
    let base: NSImage
    var items: [Annotation] = []
    var tool: Tool = .arrow
    var color: NSColor = .systemRed
    private var draft: Annotation?

    init(image: NSImage) {
        base = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if tool == .text {
            let alert = NSAlert(); alert.messageText = "Text"
            let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); alert.accessoryView = tf
            alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn, !tf.stringValue.isEmpty {
                items.append(Annotation(tool: .text, start: p, end: p, text: tf.stringValue, color: color))
                needsDisplay = true
            }
            return
        }
        draft = Annotation(tool: tool, start: p, end: p, points: [p], color: color)
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        draft?.end = p; draft?.points.append(p); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let d = draft { items.append(d) }
        draft = nil; needsDisplay = true
    }

    func undo() { if !items.isEmpty { items.removeLast(); needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        base.draw(in: bounds)
        for a in items + (draft.map { [$0] } ?? []) { render(a) }
    }

    private func rect(_ a: Annotation) -> NSRect {
        NSRect(x: min(a.start.x, a.end.x), y: min(a.start.y, a.end.y),
               width: abs(a.start.x - a.end.x), height: abs(a.start.y - a.end.y))
    }

    private func render(_ a: Annotation) {
        a.color.setStroke(); a.color.setFill()
        let lw: CGFloat = 3
        switch a.tool {
        case .rect:
            let p = NSBezierPath(roundedRect: rect(a), xRadius: 2, yRadius: 2); p.lineWidth = lw; p.stroke()
        case .ellipse:
            let p = NSBezierPath(ovalIn: rect(a)); p.lineWidth = lw; p.stroke()
        case .pen:
            guard let f = a.points.first else { return }
            let p = NSBezierPath(); p.lineWidth = lw; p.lineCapStyle = .round; p.lineJoinStyle = .round
            p.move(to: f); a.points.dropFirst().forEach { p.line(to: $0) }; p.stroke()
        case .arrow:
            let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y
            let len = hypot(dx, dy); guard len > 2 else { return }
            let ang = atan2(dy, dx), head: CGFloat = max(12, lw * 5)
            let line = NSBezierPath(); line.lineWidth = lw; line.lineCapStyle = .round
            line.move(to: a.start)
            line.line(to: NSPoint(x: a.end.x - cos(ang) * head * 0.6, y: a.end.y - sin(ang) * head * 0.6)); line.stroke()
            let tri = NSBezierPath(); tri.move(to: a.end)
            tri.line(to: NSPoint(x: a.end.x - head * cos(ang - .pi / 7), y: a.end.y - head * sin(ang - .pi / 7)))
            tri.line(to: NSPoint(x: a.end.x - head * cos(ang + .pi / 7), y: a.end.y - head * sin(ang + .pi / 7)))
            tri.close(); tri.fill()
        case .text:
            (a.text as NSString).draw(at: a.start, withAttributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: a.color])
        case .pixelate:
            drawPixelated(rect(a))
        }
    }

    /// Blocky mosaic of the underlying base image inside `r`.
    private func drawPixelated(_ r: NSRect) {
        guard r.width > 2, r.height > 2 else { return }
        let block: CGFloat = 10
        let scaleX = base.size.width / bounds.width, scaleY = base.size.height / bounds.height
        var y = r.minY
        while y < r.maxY {
            var x = r.minX
            while x < r.maxX {
                let cell = NSRect(x: x, y: y, width: min(block, r.maxX - x), height: min(block, r.maxY - y))
                let src = NSRect(x: cell.midX * scaleX, y: cell.midY * scaleY, width: 1, height: 1)
                if let rep = base.bestRepresentation(for: .zero, context: nil, hints: nil) as? NSBitmapImageRep ?? bitmap(),
                   let c = rep.colorAt(x: Int(src.minX * CGFloat(rep.pixelsWide) / base.size.width),
                                       y: Int((base.size.height - src.minY) * CGFloat(rep.pixelsHigh) / base.size.height)) {
                    c.setFill(); cell.fill()
                }
                x += block
            }
            y += block
        }
    }
    private lazy var cachedRep: NSBitmapImageRep? = base.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
    private func bitmap() -> NSBitmapImageRep? { cachedRep }

    func flattened() -> NSImage {
        let img = NSImage(size: base.size)
        img.lockFocus(); draw(bounds); img.unlockFocus()
        return img
    }
}

final class EditorWindowController: NSWindowController {
    private let canvas: CanvasView
    static var live: [EditorWindowController] = []

    init(image: NSImage) {
        canvas = CanvasView(image: image)
        let maxW: CGFloat = 1200, maxH: CGFloat = 800
        let size = NSSize(width: min(image.size.width, maxW), height: min(image.size.height, maxH) + 44)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Skreener Editor"
        super.init(window: w)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height - 44))
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true

        let bar = NSView(frame: NSRect(x: 0, y: size.height - 44, width: size.width, height: 44))
        bar.autoresizingMask = [.width, .minYMargin]
        let seg = NSSegmentedControl(labels: Tool.allCases.map(\.title), trackingMode: .selectOne,
                                     target: self, action: #selector(toolChanged(_:)))
        seg.selectedSegment = 0; seg.frame.origin = NSPoint(x: 10, y: 8)
        let well = NSColorWell(frame: NSRect(x: seg.frame.maxX + 12, y: 8, width: 40, height: 28))
        well.color = .systemRed; well.target = self; well.action = #selector(colorChanged(_:))
        func btn(_ t: String, _ s: Selector, _ x: CGFloat) -> NSButton {
            let b = NSButton(title: t, target: self, action: s); b.bezelStyle = .rounded
            b.frame = NSRect(x: x, y: 8, width: 64, height: 28); return b
        }
        let undo = btn("Undo", #selector(undoIt), well.frame.maxX + 12)
        let copy = btn("Copy", #selector(copyIt), undo.frame.maxX + 6)
        let save = btn("Save…", #selector(saveIt), copy.frame.maxX + 6)
        [seg, well, undo, copy, save].forEach(bar.addSubview)

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.addSubview(scroll); content.addSubview(bar)
        w.contentView = content
        w.center()
        EditorWindowController.live.append(self)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            EditorWindowController.live.removeAll { $0 === self }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func present() { showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func toolChanged(_ s: NSSegmentedControl) { canvas.tool = Tool(rawValue: s.selectedSegment) ?? .arrow }
    @objc private func colorChanged(_ w: NSColorWell) { canvas.color = w.color }
    @objc private func undoIt() { canvas.undo() }
    @objc private func copyIt() { Output.copy(canvas.flattened()) }
    @objc private func saveIt() { Output.saveAs(canvas.flattened()) }
}
