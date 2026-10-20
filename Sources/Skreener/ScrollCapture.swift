import AppKit
import Carbon.HIToolbox

/// Joins successive frames of a scrolling area into one tall image. Each frame is matched against the last one that
/// moved (see `ScrollMatcher`) and only the rows that scrolled into view are appended. Rows that stay put at the top or
/// bottom of the area (a sticky header or footer) are worked out again for every frame and kept once: the header from
/// the first frame, the footer from the latest. Positions are counted in content rows: `offset` is how far the latest
/// frame has scrolled from the first one, `contentEnd` is the first content row not appended yet.
///
/// Not thread-safe: the capture feeds it from one serial queue, off the main thread.
final class ScrollStitcher: @unchecked Sendable {
    enum Step {
        /// Content moved up by this many pixels (negative: back down, after scrolling up).
        case moved(Int)
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
    /// Copies of the content strips, top to bottom: the first frame above its footer, then each newly scrolled-in band.
    private var pieces: [CGImage] = []
    /// What goes under the pieces: the rows below the latest frame's content (a sticky footer, or blank space).
    private var tail: CGImage?
    /// The first frame, until something moves.
    private var first: CGImage?
    private var lastRows: ScrollRows
    private var lastShift: Int?
    private var lastFooter = 0
    /// Whether the last frame reached the end of what has been stitched (not after scrolling back up).
    private var caughtUp = true
    private var offset = 0, contentEnd = 0
    /// Columns matched, from the left: an overlay scroll bar at the right edge fades in and moves against the content.
    private let matchWidth: Int
    private let space: CGColorSpace

    init(first frame: CGImage, ignoreRight: Int) {
        width = frame.width
        frameHeight = frame.height
        height = frame.height
        let matched = ignoreRight < frame.width / 2 ? frame.width - ignoreRight : frame.width
        matchWidth = matched
        space = frame.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        first = frame
        lastRows = Self.rows(frame, width: matched)
    }

    func add(_ frame: CGImage) -> Step {
        guard frame.width == width, frame.height == frameHeight else { return .lost }
        if height >= Self.maxHeight { return .full }
        let rows = Self.rows(frame, width: matchWidth)
        let h = frameHeight
        switch ScrollMatcher.match(lastRows, rows, hint: lastShift, bridgeBlank: caughtUp) {
        case .unchanged:
            return .unchanged
        case .lost:
            return .lost
        case .moved(let shift, let header, let footer):
            lastRows = rows
            guard shift > 0 else {
                // Scrolled back up: nothing new to add; just follow along until the view is past the end again.
                offset += shift
                caughtUp = false
                return .moved(shift)
            }
            if let firstFrame = first {
                // First movement: the first frame above its footer is the top of the content.
                if let piece = slice(firstFrame, top: 0, rows: h - footer) { pieces.append(piece) }
                tail = slice(firstFrame, top: h - footer, rows: footer)
                contentEnd = h - footer
                first = nil
            } else if footer > lastFooter && contentEnd - offset == h - lastFooter {
                // A footer appeared or grew (a cookie bar, a toolbar). The rows it covers went in as content with the
                // last frame; take them out again, and this frame adds back what was underneath.
                dropLast(footer - lastFooter)
                contentEnd -= footer - lastFooter
            }
            offset += shift
            lastShift = shift
            let start = max(header, contentEnd - offset), end = h - footer
            // Still above the end of what was added (after scrolling back up): the tail stays as it was.
            guard start <= end else { return .moved(shift) }
            caughtUp = true
            if end > start, let strip = slice(frame, top: start, rows: end - start) {
                pieces.append(strip)
                contentEnd = offset + end
            }
            // The tail starts where the appended content ends, so rows already appended aren't repeated under it.
            let tailStart = max(end, contentEnd - offset)
            tail = slice(frame, top: tailStart, rows: h - tailStart)
            height = contentEnd + h - tailStart
            lastFooter = footer
            return height >= Self.maxHeight ? .full : .moved(shift)
        }
    }

    /// The stitched image, with the latest footer under it (the first frame alone if nothing moved).
    func makeImage() -> CGImage? {
        let parts = pieces.isEmpty ? [first].compactMap { $0 } : pieces + [tail].compactMap { $0 }
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

    /// Removes `rows` rows from the bottom of the pieces.
    private func dropLast(_ rows: Int) {
        var left = rows
        while left > 0, let last = pieces.last {
            if last.height <= left {
                pieces.removeLast()
                left -= last.height
            } else {
                if let cut = last.cropping(to: CGRect(x: 0, y: 0, width: width, height: last.height - left)) { pieces[pieces.count - 1] = cut }
                left = 0
            }
        }
    }

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

    /// The leftmost `width` columns of each row squeezed into `ScrollRows.bins` gray values (row 0 = top).
    private static func rows(_ image: CGImage, width: Int) -> ScrollRows {
        let h = image.height, bins = ScrollRows.bins
        let source = width < image.width ? image.cropping(to: CGRect(x: 0, y: 0, width: width, height: h)) ?? image : image
        var data = [UInt8](repeating: 0, count: bins * h)
        data.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: bins, height: h, bitsPerComponent: 8, bytesPerRow: bins,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: bins, height: h))
        }
        return ScrollRows(gray: data)
    }
}

/// Scrolling capture: after an area is picked, a dashed frame marks it and a small control panel sits inside its top.
/// Scroll the content inside the area yourself, or click Auto-Scroll; Skreener grabs it about eight times a second
/// and stitches the frames (off the main thread). Auto-scroll keeps scrolling down until the content stops moving
/// (the end), then finishes, or until Stop Scrolling. Done (or ⌃⇧8 again) finishes, Esc or Cancel throws it away.
final class ScrollCaptureController {
    private(set) var isRunning = false
    private var screen: NSScreen?
    private var rect: CGRect = .zero
    private var stitcher: ScrollStitcher?
    /// Stitching runs here, one frame at a time; finishing queues up behind the frame in progress.
    private let work = DispatchQueue(label: "skreener.scroll-stitch", qos: .userInitiated)
    private var frameWindow: NSPanel?
    private var controls: NSPanel?
    private let status = NSTextField(labelWithString: "")
    private var escHotKey: UInt32?
    private var completion: ((NSImage?) -> Void)?
    /// Bumped on every start, so a previous capture's frame loop stops even if a new one has begun.
    private var session = 0

    // Auto-scroll: a steady stream of small scroll events (about 60 a second) sent straight to the app under the
    // area, so the pointer stays free. The speed is set from how far the content really moves per point scrolled.
    private var autoScrolling = false
    private var autoButton: PillButton?
    private var scrollTimer: Timer?
    private var lastTick: Date?
    /// The app and window under the middle of the area.
    private var targetPID: pid_t?
    private var targetWindow: CGWindowID = 0
    /// Fallback when the app ignores events sent to it directly: scroll at the pointer (which must be over the area).
    private var viaPointer = false
    /// Scroll speed in points per second, and the part of it not posted yet (events carry whole points).
    private var velocity: CGFloat = 0
    private var unposted: CGFloat = 0
    /// Points posted so far (a take-back counts as negative), and the total when the frame the stitcher last matched
    /// was grabbed. The difference is how far the view was asked to move since that frame, which is what a moved frame
    /// is measured against and what an overshoot takes back.
    private var postedTotal: CGFloat = 0
    private var postedAtMatch: CGFloat = 0
    private var measured = false
    /// When auto-scroll started, whether the content has moved since, and when it last moved.
    private var autoStarted = Date()
    private var autoMoved = false
    private var lastMove = Date()
    /// Scrolling paused for a frame after one that didn't match: often the next one does (an image loading in, an
    /// animation), and then nothing needs taking back.
    private var paused = false
    /// Frames spent waiting for a taken-back overshoot to settle (0 = not recovering), and the speed before it.
    private var recovering = 0
    private var speedBeforeOvershoot: CGFloat = 0
    /// The stitched height at the last take-back, and how many take-backs in a row added nothing since the one before:
    /// a few of those mean it is stuck (often the end of the page with something animating), not going too fast.
    private var heightAtTakeBack = -1
    private var fruitlessTakeBacks = 0
    /// Time between captured frames (smoothed), to keep each frame's movement within what the stitcher matches.
    private var frameInterval: TimeInterval = 0.15
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
        setStatus("Scroll down slowly to capture")
        lastFrameTime = nil
        // Esc stops auto-scroll first; otherwise it cancels the capture.
        escHotKey = HotKeys.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in
            guard let self else { return }
            if self.autoScrolling {
                self.stopAutoScroll()
                self.setStatus("Stopped. Scroll or click Done.")
            } else {
                self.cancel()
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)   // let the selection overlay leave the screen
            var grabber: CaptureService.AreaGrabber?
            while true {
                guard let self, self.isRunning, self.session == current, let screen = self.screen else { return }
                let began = Date()
                if grabber == nil { grabber = try? await CaptureService.AreaGrabber(screen: screen, globalRect: self.rect) }
                let posted = self.postedTotal
                if let frame = try? await grabber?.grab() {
                    guard self.isRunning, self.session == current else { return }
                    if let stitcher = self.stitcher {
                        let step = await self.onWorkQueue { stitcher.add(frame) }
                        guard self.isRunning, self.session == current else { return }
                        self.handle(step, posted: posted)
                    } else {
                        let edge = Int(16 * screen.backingScaleFactor)
                        let started = await self.onWorkQueue { ScrollStitcher(first: frame, ignoreRight: edge) }
                        guard self.isRunning, self.session == current else { return }
                        self.stitcher = started
                    }
                } else {
                    grabber = nil   // set up again next time (the display may have changed)
                }
                // About eight frames a second, counting the time the grab and the stitching took.
                let wait = max(0.02, 0.12 - Date().timeIntervalSince(began))
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    func finish() {
        guard isRunning else { return }
        let stitcher = self.stitcher, done = completion
        let scale = screen?.backingScaleFactor ?? 2
        stop()
        // On the stitching queue, after any frame still being added.
        work.async {
            let cg = stitcher?.makeImage()
            DispatchQueue.main.async {
                let image = cg.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale)) }
                if image == nil { NSSound.beep() }
                done?(image)
            }
        }
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
    }

    /// Runs `job` on the stitching queue and hands back its result.
    private func onWorkQueue<T>(_ job: @escaping () -> T) async -> T {
        await withCheckedContinuation { done in work.async { done.resume(returning: job()) } }
    }

    /// One frame's result. `posted` is `postedTotal` when the frame was grabbed.
    private func handle(_ step: ScrollStitcher.Step, posted: CGFloat) {
        guard let stitcher else { return }
        let now = Date()
        if let last = lastFrameTime { frameInterval = frameInterval * 0.7 + now.timeIntervalSince(last) * 0.3 }
        lastFrameTime = now
        if autoScrolling {
            autoScrollStep(step, posted: posted, scale: CGFloat(stitcher.frameHeight) / max(rect.height, 1))
            return
        }
        switch step {
        case .moved: setStatus("Keep scrolling or click Done")
        case .unchanged, .lost: break
        case .full: setStatus("Maximum length: click Done")
        }
    }

    // MARK: Auto-scroll

    private func toggleAutoScroll() {
        if autoScrolling {
            stopAutoScroll()
            setStatus("Stopped. Scroll or click Done.")
            return
        }
        // Scroll events posted into another app need Accessibility access.
        guard AccessibilityAccess.granted else {
            AccessibilityAccess.request()
            setStatus("Allow Accessibility, then retry")
            return
        }
        guard let target = Self.window(at: scrollPoint) else {
            setStatus("No window found: scroll by hand")
            return
        }
        targetPID = target.pid
        targetWindow = target.window
        viaPointer = false
        autoScrolling = true
        autoMoved = false
        autoStarted = Date()
        measured = false
        paused = false
        recovering = 0
        heightAtTakeBack = -1
        fruitlessTakeBacks = 0
        unposted = 0
        postedAtMatch = postedTotal
        lastTick = nil
        velocity = max(rect.height * 0.25, 40)   // a slow start; measured and sped up over the first frames
        autoButton?.setContent(title: "Stop", symbol: "stop.fill")
        setStatus("Scrolling…")
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.scrollTick() }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }

    private func stopAutoScroll() {
        autoScrolling = false
        scrollTimer?.invalidate()
        scrollTimer = nil
        autoButton?.setContent(title: "Auto-Scroll", symbol: "arrow.down")
    }

    /// Posts the next bit of the steady scroll, from the time since the last tick (ticks run late while the main thread
    /// is busy). At least 2 points at a time, so apps that scale events down still move.
    private func scrollTick() {
        let now = Date()
        defer { lastTick = now }
        guard autoScrolling, recovering == 0, !paused, let last = lastTick else { return }
        unposted += velocity * CGFloat(min(now.timeIntervalSince(last), 0.1))
        let whole = unposted.rounded(.down)
        guard whole >= 2 else { return }
        unposted -= whole
        post(scrollPoints: whole)
    }

    /// After each frame: tune the speed; finish once the content has moved and then stopped (the end). Never scrolls
    /// up, except to take back what was scrolled since the last match when it went further than can be matched.
    private func autoScrollStep(_ step: ScrollStitcher.Step, posted: CGFloat, scale: CGFloat) {
        var recovered = false
        switch step {
        case .moved, .unchanged:
            paused = false
            if recovering > 0 {
                // The take-back worked: carry on at half the speed, but not so slowly that the end seems reached.
                recovering = 0
                recovered = true
                velocity = max(speedBeforeOvershoot / 2, rect.height * 0.15, 40)
            }
        case .lost, .full:
            break
        }
        switch step {
        case .moved(let pixels):
            // Aim for a fifth of the area per frame and at most one area height a second, from how far the scrolled
            // points really moved (apps scale and animate scroll events differently). Speed up gradually. Only points
            // posted before this frame was grabbed count; right after a take-back the numbers are too small to trust.
            let asked = posted - postedAtMatch
            if asked > 0 && !recovered {
                let ratio = CGFloat(pixels) / scale / asked
                if ratio > 0.05 {
                    let target = min(rect.height, rect.height * 0.2 / CGFloat(max(frameInterval, 0.05))) / ratio
                    velocity = min(target, velocity * (measured ? 1.5 : 3))
                    measured = true
                }
            }
            postedAtMatch = posted
            autoMoved = true
            lastMove = Date()
            setStatus("Scrolling…")
        case .unchanged:
            let still = Date().timeIntervalSince(autoMoved ? lastMove : autoStarted)
            if autoMoved && still >= 2 {
                finish()   // scrolled and then stopped moving: the end
            } else if !autoMoved && still >= 1 && !viaPointer {
                // The app didn't react to events sent to it: scroll at the pointer instead (it isn't moved).
                viaPointer = true
                setStatus("Rest the pointer on the content")
            } else if !autoMoved && still >= 3 {
                stopAutoScroll()
                setStatus("Can't auto-scroll: scroll by hand")
            }
        case .lost:
            if recovering > 0 {
                // Give a take-back a moment to settle (apps animate scrolling) before handing over.
                recovering += 1
                if recovering > 8 { handOverLost() }
                return
            }
            guard paused else {
                paused = true
                return
            }
            paused = false
            // Everything posted since the matched frame was grabbed, including what went out after this frame.
            let overshoot = postedTotal - postedAtMatch
            guard overshoot > 0 else { handOverLost(); return }
            let height = stitcher?.height ?? 0
            fruitlessTakeBacks = height <= heightAtTakeBack ? fruitlessTakeBacks + 1 : 0
            heightAtTakeBack = height
            if fruitlessTakeBacks >= 2 {
                stopAutoScroll()
                setStatus("Stuck: click Done if at the end")
                return
            }
            recovering = 1
            speedBeforeOvershoot = velocity
            unposted = 0
            post(scrollPoints: -overshoot)
            setStatus("Slowing down…")
        case .full:
            stopAutoScroll()
            setStatus("Maximum length: click Done")
        }
    }

    private func handOverLost() {
        stopAutoScroll()
        recovering = 0
        setStatus("Stopped. Scroll or click Done.")
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
        postedTotal -= CGFloat(delta)
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

    private func setStatus(_ text: String) {
        status.stringValue = text
        status.toolTip = text   // the whole text, should the bar cut it short
    }

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
        p.appearance = NSAppearance(named: .darkAqua)

        // A dark capsule, like an iOS floating toolbar. Solid rather than a blur: over a light page a blur turns pale
        // grey and the white text on it is hard to read.
        let bg = NSView(frame: NSRect(origin: .zero, size: size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.94).cgColor
        bg.layer?.cornerRadius = size.height / 2; bg.layer?.cornerCurve = .continuous; bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 0.5; bg.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.textColor = NSColor.white.withAlphaComponent(0.9)
        status.lineBreakMode = .byTruncatingTail
        status.maximumNumberOfLines = 1
        let auto = PillButton(title: "Auto-Scroll", symbol: "arrow.down", style: .tinted) { [weak self] in self?.toggleAutoScroll() }
        auto.toolTip = "Scroll automatically until the end of the content"
        autoButton = auto
        let cancel = PillButton(title: nil, symbol: "xmark", style: .tinted) { [weak self] in self?.cancel() }
        cancel.toolTip = "Cancel (Esc)"
        let done = PillButton(title: "Done", symbol: "checkmark", style: .filled) { [weak self] in self?.finish() }
        // The buttons are pinned to the right; the text gets whatever is left and is cut short rather than pushing
        // them off the end of the bar.
        let buttons = NSStackView(views: [auto, cancel, done])
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.setHuggingPriority(.required, for: .horizontal)
        status.translatesAutoresizingMaskIntoConstraints = false
        status.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bg.addSubview(status)
        bg.addSubview(buttons)
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 18),
            status.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -14),
            status.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            buttons.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -7),
            buttons.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
        ])
        p.contentView = bg
        p.orderFrontRegardless()
        controls = p
    }
}

/// A capsule button in the style of iOS: filled with the accent colour, or a translucent tint over the dark bar; an
/// SF Symbol with an optional title (no title makes it a circle). Dims while pressed.
private final class PillButton: NSButton {
    enum Style { case filled, tinted }

    /// Space between the symbol and the title, the same on every pill button. The symbol and title are laid out
    /// here rather than by the button cell, whose own spacing is wider and varies with the content.
    static let iconGap: CGFloat = 5

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let content = NSStackView()
    private let run: () -> Void
    private let style: Style
    private var pressed = false { didSet { applyColors() } }
    private var widthConstraint: NSLayoutConstraint?

    init(title: String?, symbol: String, style: Style, run: @escaping () -> Void) {
        self.run = run
        self.style = style
        super.init(frame: .zero)
        isBordered = false
        self.title = ""
        wantsLayer = true
        layer?.cornerCurve = .continuous
        icon.contentTintColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        content.addArrangedSubview(icon)
        content.addArrangedSubview(label)
        content.spacing = Self.iconGap
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        content.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        content.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        setContent(title: title, symbol: symbol)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setContent(title: String?, symbol: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(config)
        label.stringValue = title ?? ""
        label.isHidden = title == nil   // the stack leaves hidden views out, gap included
        setAccessibilityLabel(title ?? toolTip)
        widthConstraint?.isActive = false
        // Room either side of the content, or a circle when there is only a symbol.
        widthConstraint = title == nil ? widthAnchor.constraint(equalToConstant: 30)
                                       : widthAnchor.constraint(equalToConstant: content.fittingSize.width + 28)
        widthConstraint?.isActive = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Clicks on the symbol or title belong to the button.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        super.mouseDown(with: event)   // tracks the click until the button is released
        pressed = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        let base: NSColor = style == .filled ? .controlAccentColor : NSColor.white.withAlphaComponent(0.16)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (pressed ? base.blended(withFraction: 0.3, of: .black) ?? base : base).cgColor
        }
    }

    @objc private func fire() { run() }
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
