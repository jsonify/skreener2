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
        // Every other row is compared above, so a neighbouring shift can tie (solid areas); settle it on every row.
        if bestShift > 0 {
            var fine = Double.greatestFiniteMagnitude
            for shift in max(1, bestShift - 2)...min(band - minOverlap, bestShift + 2) {
                let c = Self.cost(lastRows, rows, from: top, to: h - bottom - shift, shift: shift, limit: fine, rowStep: 1)
                if c < fine { fine = c; best = c; bestShift = shift }
            }
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
    /// `y` in `from..<to` (every `rowStep`th row). Stops early, returning a value ≥ `limit`, once it can't beat `limit`.
    private static func cost(_ p: [UInt8], _ n: [UInt8], from: Int, to: Int, shift: Int, limit: Double, rowStep: Int = 2) -> Double {
        let count = (to - from + rowStep - 1) / rowStep
        guard count > 0 else { return .greatestFiniteMagnitude }
        let budget = limit * Double(count * bins)
        var sum = 0
        var y = from
        while y < to {
            sum += rowDiff(p, y + shift, n, y)
            if Double(sum) >= budget { return limit }
            y += rowStep
        }
        return Double(sum) / Double(count * bins)
    }
}

/// Scrolling capture: after an area is picked, a dashed frame marks it and a small control panel sits beside it.
/// Scroll the content inside the area yourself, or click Auto-Scroll; Skreener grabs it several times a second and
/// stitches the frames. Auto-scroll keeps scrolling down until the content stops moving (the end), then finishes,
/// or until Stop Scrolling. Done (or ⌃⇧8 again) finishes, Esc or Cancel throws it away.
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

    // Auto-scroll: a steady stream of small scroll events (about 60 a second) sent straight to the app under the
    // area, so the pointer stays free. The speed is set from how far the content really moves per point scrolled.
    private var autoScrolling = false
    private var autoButton: NSButton?
    private var scrollTimer: Timer?
    /// The app and window under the middle of the area.
    private var targetPID: pid_t?
    private var targetWindow: CGWindowID = 0
    /// Fallback when the app ignores events sent to it directly: scroll at the pointer (which must be over the area).
    private var viaPointer = false
    /// Scroll speed in points per second, and the part of it not posted yet (events carry whole points).
    private var velocity: CGFloat = 0
    private var unposted: CGFloat = 0
    /// Points posted since the last frame that moved: measures the speed, and is what an overshoot takes back.
    private var postedSinceMove: CGFloat = 0
    private var measured = false
    /// Whether the content has moved since auto-scroll started, and for how many frames it hasn't moved.
    private var autoMoved = false
    private var stillFrames = 0
    /// Frames spent waiting for a taken-back overshoot to settle (0 = not recovering), and the speed before it.
    private var recovering = 0
    private var speedBeforeOvershoot: CGFloat = 0
    /// Time between captured frames (smoothed), to keep each frame's movement within what the stitcher matches.
    private var frameInterval: TimeInterval = 0.2
    private var lastFrameTime: Date?

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
        lastFrameTime = nil
        // Esc stops auto-scroll first; otherwise it cancels the capture.
        escHotKey = HotKeys.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in
            guard let self else { return }
            if self.autoScrolling {
                self.stopAutoScroll()
                self.setStatus("Stopped. Scroll by hand, Auto-Scroll again, or click Done.")
            } else {
                self.cancel()
            }
        }
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
        stopAutoScroll()
        isRunning = false
        completion = nil
        stitcher = nil
        frameWindow?.orderOut(nil); frameWindow = nil
        controls?.orderOut(nil); controls = nil
        autoButton = nil
        if let id = escHotKey { HotKeys.shared.unregister(id); escHotKey = nil }
        actions.removeAll()
    }

    private func add(_ frame: CGImage) {
        guard let screen else { return }
        let now = Date()
        if let last = lastFrameTime { frameInterval = frameInterval * 0.7 + now.timeIntervalSince(last) * 0.3 }
        lastFrameTime = now
        guard let stitcher else {
            stitcher = ScrollStitcher(first: frame)
            return
        }
        let step = stitcher.add(frame)
        let length = "\(Int((CGFloat(stitcher.height) / screen.backingScaleFactor).rounded())) pt tall"
        if autoScrolling {
            autoScrollStep(step, length: length, scale: CGFloat(stitcher.frameHeight) / max(rect.height, 1))
            return
        }
        switch step {
        case .added: setStatus("\(length). Keep scrolling, or click Done.")
        case .unchanged: break
        case .lost: setStatus("\(length). Lost track: scroll back a little and go slower.")
        case .full: setStatus("\(length). That's the maximum length: click Done.")
        }
    }

    // MARK: Auto-scroll

    private func toggleAutoScroll() {
        if autoScrolling {
            stopAutoScroll()
            setStatus("Stopped. Scroll by hand, Auto-Scroll again, or click Done.")
            return
        }
        // Scroll events posted into another app need Accessibility access.
        guard AccessibilityAccess.granted else {
            AccessibilityAccess.request()
            setStatus("Allow Skreener in Privacy & Security → Accessibility, then click Auto-Scroll again.")
            return
        }
        guard let target = Self.window(at: scrollPoint) else {
            setStatus("Couldn't find the window under the area. Scroll by hand instead.")
            return
        }
        targetPID = target.pid
        targetWindow = target.window
        viaPointer = false
        autoScrolling = true
        autoMoved = false
        stillFrames = 0
        measured = false
        recovering = 0
        unposted = 0
        postedSinceMove = 0
        velocity = max(rect.height * 0.25, 40)   // a slow start; measured and sped up over the first frames
        autoButton?.title = "Stop Scrolling"
        setStatus("Scrolling…")
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.scrollTick() }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }

    private func stopAutoScroll() {
        autoScrolling = false
        scrollTimer?.invalidate()
        scrollTimer = nil
        autoButton?.title = "Auto-Scroll"
    }

    /// Posts the next bit of the steady scroll (at least 2 points at a time, so apps that scale events down still move).
    private func scrollTick() {
        guard autoScrolling, recovering == 0 else { return }
        unposted += velocity / 60
        let whole = unposted.rounded(.down)
        guard whole >= 2 else { return }
        unposted -= whole
        postedSinceMove += whole
        post(scrollPoints: whole)
    }

    /// After each frame: tune the speed; finish once the content has moved and then stopped (the end). Never scrolls
    /// up, except to take back what was scrolled since the last match when it went further than can be matched.
    private func autoScrollStep(_ step: ScrollStitcher.Step, length: String, scale: CGFloat) {
        switch step {
        case .added, .unchanged:
            if recovering > 0 {
                // The take-back worked: carry on at half the speed.
                recovering = 0
                velocity = speedBeforeOvershoot / 2
                postedSinceMove = 0
            }
        case .lost, .full:
            break
        }
        switch step {
        case .added(let pixels):
            // Aim for a fifth of the area per frame and at most one area height a second, from how far the scrolled
            // points really moved (apps scale and animate scroll events differently). Speed up gradually.
            if postedSinceMove > 0 {
                let ratio = CGFloat(pixels) / scale / postedSinceMove
                if ratio > 0.05 {
                    let target = min(rect.height, rect.height * 0.2 / CGFloat(max(frameInterval, 0.05))) / ratio
                    velocity = min(target, velocity * (measured ? 1.5 : 3))
                    measured = true
                }
            }
            postedSinceMove = 0
            autoMoved = true
            stillFrames = 0
            setStatus("\(length). Scrolling…")
        case .unchanged:
            stillFrames += 1
            if autoMoved && stillFrames >= 8 {
                finish()   // scrolled and then stopped moving: the end
            } else if !autoMoved && stillFrames == 6 && !viaPointer {
                // The app didn't react to events sent to it: scroll at the pointer instead (it isn't moved).
                viaPointer = true
                setStatus("Rest the pointer on the content (below this bar) to keep scrolling.")
            } else if !autoMoved && stillFrames >= 15 {
                stopAutoScroll()
                setStatus("Auto-Scroll couldn't move this content. Scroll it by hand instead.")
            }
        case .lost:
            if recovering > 0 {
                // Give a take-back a few frames to settle (apps animate scrolling) before handing over.
                recovering += 1
                if recovering > 5 { handOverLost(length) }
                return
            }
            guard postedSinceMove > 0 else { handOverLost(length); return }
            recovering = 1
            speedBeforeOvershoot = velocity
            post(scrollPoints: -postedSinceMove)
            postedSinceMove = 0
            unposted = 0
            setStatus("\(length). Slowing down…")
        case .full:
            stopAutoScroll()
            setStatus("\(length). That's the maximum length: click Done.")
        }
    }

    private func handOverLost(_ length: String) {
        stopAutoScroll()
        recovering = 0
        setStatus("\(length). Lost track: scroll back up a little by hand, then Auto-Scroll again.")
    }

    /// The middle of the area in Core Graphics' global coordinates (top-left origin).
    private var scrollPoint: CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: rect.midX, y: primaryHeight - rect.midY)
    }

    /// The app and window ID of the frontmost normal window at `point` (Core Graphics coordinates), other than Skreener's.
    private static func window(at point: CGPoint) -> (pid: pid_t, window: CGWindowID)? {
        let me = getpid()
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in info {   // front to back
            guard (w[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != me,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.contains(point),
                  let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { continue }
            return (pid: pid, window: id)
        }
        return nil
    }

    /// Sends a pixel scroll (positive moves further down the content) straight to the app under the area, aimed at
    /// the middle of the area. Posting to the app, not the system event stream, leaves the pointer where the user
    /// has it. In the `viaPointer` fallback it goes into the system stream at the pointer's current position.
    private func post(scrollPoints points: CGFloat) {
        let delta = Int32((-points).rounded())
        guard delta != 0, let pid = targetPID,
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)
        else { return }
        if viaPointer {
            if let pointer = CGEvent(source: nil)?.location { event.location = pointer }   // never move the pointer
            event.post(tap: .cghidEventTap)
            return
        }
        event.location = scrollPoint
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(targetWindow))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(targetWindow))
        event.postToPid(pid)
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

    /// Status, Auto-Scroll and Done / Cancel: inside the top of the area, or next to it when the area is small.
    private func showControls() {
        guard let screen else { return }
        let visible = screen.visibleFrame
        var size = NSSize(width: 540, height: 44)
        var origin: NSPoint
        if rect.width >= 316 && rect.height >= size.height * 4 {
            // Inside the area, about a tenth of the way down: clicking Auto-Scroll leaves the pointer over the content.
            // (Skreener's windows are left out of the frames, so the panel never shows up in the capture.)
            size.width = min(size.width, rect.width - 16)
            let y = min(rect.maxY - rect.height * 0.1 - size.height / 2, rect.maxY - size.height - 8)
            origin = NSPoint(x: rect.midX - size.width / 2, y: y)
        } else {
            // Too small to share: under the area, or above it, or inside its bottom edge when there's no room.
            var y = rect.minY - size.height - 12
            if y < visible.minY { y = rect.maxY + 12 }
            if y + size.height > visible.maxY { y = rect.minY + 12 }
            origin = NSPoint(x: rect.midX - size.width / 2, y: y)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        let x = origin.x, y = origin.y
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
        let auto = button("Auto-Scroll") { [weak self] in self?.toggleAutoScroll() }
        auto.toolTip = "Scroll automatically until the end of the content"
        autoButton = auto
        let cancel = button("Cancel") { [weak self] in self?.cancel() }
        let done = button("Done") { [weak self] in self?.finish() }
        done.bezelColor = .controlAccentColor
        let row = NSStackView(views: [status, auto, cancel, done])
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
