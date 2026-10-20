import AppKit
import Carbon.HIToolbox

/// Joins successive frames of a scrolling area into one tall image. Each frame is matched against the last accepted
/// one to find how far the content moved up, and only the rows that scrolled into view are appended. Rows that stay
/// put at the top or bottom of the area (a sticky header or footer) are detected on the first scroll, left out of
/// the matching, and kept once: the header from the first frame, the footer from the last.
final class ScrollStitcher {
    enum Step {
        /// Content moved up by this many pixels; that many new rows were added.
        case added(Int)
        /// Nothing moved (or it moved too little to tell).
        case unchanged
        /// No good match: scrolled too fast, scrolled up, or the content changed.
        case lost
        /// The image reached `maxHeight`; further frames are ignored.
        case full
    }

    static let maxHeight = 30_000

    let width: Int
    let frameHeight: Int
    private(set) var height: Int
    /// Copies of the strips that make up the result, top to bottom (the first frame, then each newly scrolled-in band).
    private var strips: [CGImage]
    private var lastFrame: CGImage
    private var lastRows: [UInt8]
    private var fixedTop = 0, fixedBottom = 0
    private var fixedKnown = false
    private let space: CGColorSpace

    /// Columns per row signature: each row is reduced to this many averaged gray values.
    private static let bins = 96

    init(first: CGImage) {
        width = first.width
        frameHeight = first.height
        height = first.height
        space = first.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        lastFrame = first
        lastRows = Self.signature(first)
        strips = []
        if let copy = slice(first, top: 0, rows: first.height) { strips.append(copy) }
    }

    func add(_ frame: CGImage) -> Step {
        guard frame.width == width, frame.height == frameHeight else { return .lost }
        if height >= Self.maxHeight { return .full }
        let rows = Self.signature(frame)
        let h = frameHeight, bins = Self.bins

        // Rows that did not change at all, from the top and from the bottom.
        var top = fixedTop, bottom = fixedBottom
        if !fixedKnown {
            top = 0
            while top < h && Self.rowDiff(lastRows, top, rows, top) < 2 * bins { top += 1 }
            if top == h { return .unchanged }
            bottom = 0
            while bottom < h - top && Self.rowDiff(lastRows, h - 1 - bottom, rows, h - 1 - bottom) < 2 * bins { bottom += 1 }
            top = min(top, h / 3)
            bottom = min(bottom, h / 3)
        }
        let band = h - top - bottom
        let minOverlap = max(24, band / 6)
        guard band > minOverlap + 1 else { return .unchanged }

        // Average per-value difference with no movement, then the best upward shift.
        let still = Self.cost(lastRows, rows, from: top, to: h - bottom, shift: 0, limit: .greatestFiniteMagnitude)
        if still < 0.5 { return .unchanged }
        var best = Double.greatestFiniteMagnitude, bestShift = 0
        for shift in 1...(band - minOverlap) {
            let c = Self.cost(lastRows, rows, from: top, to: h - bottom - shift, shift: shift, limit: best)
            if c < best { best = c; bestShift = shift }
        }
        guard bestShift > 0, best < 4, best < still * 0.5 else { return .lost }

        if !fixedKnown {
            fixedKnown = true
            fixedTop = top
            fixedBottom = bottom
            // The first frame's footer comes off; the last frame's footer is added at the end.
            if bottom > 0, let first = strips.first, let trimmed = first.cropping(to: CGRect(x: 0, y: 0, width: width, height: h - bottom)) {
                strips[0] = trimmed
                height -= bottom
            }
        }
        let added = min(bestShift, Self.maxHeight - height)
        guard let strip = slice(frame, top: h - fixedBottom - bestShift, rows: added) else { return .lost }
        strips.append(strip)
        height += added
        lastFrame = frame
        lastRows = rows
        return height >= Self.maxHeight ? .full : .added(added)
    }

    /// The stitched image, with the latest footer under it.
    func makeImage() -> CGImage? {
        var parts = strips
        if fixedBottom > 0, let footer = slice(lastFrame, top: frameHeight - fixedBottom, rows: fixedBottom) { parts.append(footer) }
        let total = parts.reduce(0) { $0 + $1.height }
        guard total > 0, let ctx = context(height: total) else { return nil }
        var y = total
        for p in parts {
            y -= p.height
            ctx.draw(p, in: CGRect(x: 0, y: y, width: width, height: p.height))
        }
        return ctx.makeImage()
    }

    // MARK: Pixels

    /// An independent copy of `rows` rows starting at `top` (so the full frame can be released).
    private func slice(_ image: CGImage, top: Int, rows: Int) -> CGImage? {
        guard rows > 0, let part = image.cropping(to: CGRect(x: 0, y: top, width: width, height: rows)),
              let ctx = context(height: rows) else { return nil }
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: width, height: rows))
        return ctx.makeImage()
    }

    private func context(height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Each row squeezed into `bins` gray values (row 0 = top), for comparing rows quickly.
    private static func signature(_ image: CGImage) -> [UInt8] {
        let h = image.height
        var data = [UInt8](repeating: 0, count: bins * h)
        data.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: bins, height: h, bitsPerComponent: 8, bytesPerRow: bins,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: bins, height: h))
        }
        return data
    }

    /// Sum of absolute differences between row `a` of `p` and row `b` of `n`.
    private static func rowDiff(_ p: [UInt8], _ a: Int, _ n: [UInt8], _ b: Int) -> Int {
        var sum = 0
        let pa = a * bins, nb = b * bins
        for i in 0..<bins { sum += abs(Int(p[pa + i]) - Int(n[nb + i])) }
        return sum
    }

    /// Mean difference per value between rows `y + shift` of the previous frame and rows `y` of the new one, for
    /// `y` in `from..<to` (every other row). Stops early, returning a value ≥ `limit`, once it can't beat `limit`.
    private static func cost(_ p: [UInt8], _ n: [UInt8], from: Int, to: Int, shift: Int, limit: Double) -> Double {
        let count = (to - from + 1) / 2
        guard count > 0 else { return .greatestFiniteMagnitude }
        let budget = limit * Double(count * bins)
        var sum = 0
        var y = from
        while y < to {
            sum += rowDiff(p, y + shift, n, y)
            if Double(sum) >= budget { return limit }
            y += 2
        }
        return Double(sum) / Double(count * bins)
    }
}

/// Scrolling capture: after an area is picked, a dashed frame marks it and a small control panel sits beside it.
/// Scroll the content inside the area (any speed up to about half the area per frame); Skreener grabs it several
/// times a second and stitches the frames. Done (or ⌃⇧8 again) finishes, Esc or Cancel throws it away.
final class ScrollCaptureController {
    private(set) var isRunning = false
    private var screen: NSScreen?
    private var rect: CGRect = .zero
    private var stitcher: ScrollStitcher?
    private var frameWindow: NSPanel?
    private var controls: NSPanel?
    private let status = NSTextField(labelWithString: "")
    private var escHotKey: UInt32?
    private var completion: ((NSImage?) -> Void)?
    private var actions: [ScrollAction] = []
    /// Bumped on every start, so a previous capture's frame loop stops even if a new one has begun.
    private var session = 0

    func start(screen: NSScreen, rect: CGRect, completion: @escaping (NSImage?) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.screen = screen
        self.rect = rect.integral
        self.completion = completion
        stitcher = nil
        session += 1
        let current = session
        showFrame()
        showControls()
        setStatus("Scroll down slowly inside the frame…")
        escHotKey = HotKeys.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in self?.cancel() }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)   // let the selection overlay leave the screen
            while true {
                guard let self, self.isRunning, self.session == current, let screen = self.screen else { return }
                let frame = try? await CaptureService.captureScreenImage(screen, globalRect: self.rect, showsCursor: false,
                                                                         excludingSelf: true)
                if let frame, self.isRunning, self.session == current { self.add(frame) }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    func finish() {
        guard isRunning else { return }
        let image = stitcher?.makeImage().flatMap { cg -> NSImage? in
            let scale = screen?.backingScaleFactor ?? 2
            return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
        }
        let done = completion
        stop()
        if image == nil { NSSound.beep() }
        done?(image)
    }

    func cancel() {
        guard isRunning else { return }
        let done = completion
        stop()
        NSSound(named: "Funk")?.play()
        done?(nil)
    }

    private func stop() {
        isRunning = false
        completion = nil
        stitcher = nil
        frameWindow?.orderOut(nil); frameWindow = nil
        controls?.orderOut(nil); controls = nil
        if let id = escHotKey { HotKeys.shared.unregister(id); escHotKey = nil }
        actions.removeAll()
    }

    private func add(_ frame: CGImage) {
        guard let screen else { return }
        guard let stitcher else {
            stitcher = ScrollStitcher(first: frame)
            return
        }
        let step = stitcher.add(frame)
        let length = "\(Int((CGFloat(stitcher.height) / screen.backingScaleFactor).rounded())) pt tall"
        switch step {
        case .added: setStatus("\(length). Keep scrolling, or click Done.")
        case .unchanged: break
        case .lost: setStatus("\(length). Lost track: scroll back a little and go slower.")
        case .full: setStatus("\(length). That's the maximum length: click Done.")
        }
    }

    private func setStatus(_ text: String) { status.stringValue = text }

    // MARK: Windows

    /// Dashed outline just outside the area (left out of the capture anyway), click-through.
    private func showFrame() {
        let p = NSPanel(contentRect: rect.insetBy(dx: -4, dy: -4), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = DashedFrameView()
        p.orderFrontRegardless()
        frameWindow = p
    }

    /// Status and Done / Cancel, under the area (or above it, or inside its bottom edge when there's no room).
    private func showControls() {
        guard let screen else { return }
        let size = NSSize(width: 420, height: 44)
        let visible = screen.visibleFrame
        var y = rect.minY - size.height - 12
        if y < visible.minY { y = rect.maxY + 12 }
        if y + size.height > visible.maxY { y = rect.minY + 12 }
        let x = min(max(rect.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let p = NSPanel(contentRect: NSRect(origin: NSPoint(x: x, y: y), size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true
        bg.layer?.cornerRadius = 10; bg.layer?.masksToBounds = true

        status.font = .systemFont(ofSize: 12)
        status.lineBreakMode = .byTruncatingTail
        let cancel = button("Cancel") { [weak self] in self?.cancel() }
        let done = button("Done") { [weak self] in self?.finish() }
        done.bezelColor = .controlAccentColor
        let row = NSStackView(views: [status, cancel, done])
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 10)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.frame = bg.bounds
        row.autoresizingMask = [.width, .height]
        bg.addSubview(row)
        p.contentView = bg
        p.orderFrontRegardless()
        controls = p
    }

    private func button(_ title: String, _ run: @escaping () -> Void) -> NSButton {
        let a = ScrollAction(run)
        actions.append(a)
        let b = NSButton(title: title, target: a, action: #selector(ScrollAction.fire))
        b.bezelStyle = .rounded
        b.controlSize = .small
        return b
    }
}

private final class ScrollAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

private final class DashedFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.stroke()
        path.setLineDash([6, 4], count: 2, phase: 5)
        NSColor.black.withAlphaComponent(0.6).setStroke()
        path.stroke()
    }
}
