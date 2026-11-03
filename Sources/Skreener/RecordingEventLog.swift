import AppKit
import CoreMedia

/// Collects a Record for editing recording's event track (#380) while it runs: the pointer about once per video frame
/// (from the recorder's frame hook and a timer at the frame rate, since an unchanging screen gives no frames), the
/// cursor image when it changes (saved once each as `cursors/<n>.png`), clicks, keystrokes (only with keystroke
/// display on) and spotlight toggles. Host times are mapped to the video's timeline by the recorder; events while
/// paused are dropped. Main thread, except `sampleCursor`, which any thread may call.
final class RecordingEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events = RecordingEvents()
    private let area: CGRect
    private let videoSize: CGSize
    private let mainHeight: CGFloat
    private let folder: URL
    private weak var recorder: ScreenRecorder?
    private var timer: DispatchSourceTimer?
    private var monitors: [Any] = []
    /// Cursor images seen so far (main thread), by their TIFF data and hotspot.
    private var cursorIndex: [Data: Int] = [:]
    private var lastCursor: Int?

    /// `area` is the recorded area (global points), `folder` the project folder the cursor images go in.
    init(area: CGRect, videoSize: CGSize, folder: URL, spotlightAtStart: Bool) {
        self.area = area
        self.videoSize = videoSize
        self.folder = folder
        mainHeight = NSScreen.screens.first?.frame.height ?? 0
        events.spotlightAtStart = spotlightAtStart
    }

    /// Starts listening: clicks always, key presses when `keys`; the pointer at `fps` from the recorder's clock.
    func start(recorder: ScreenRecorder, fps: Int, keys: Bool) {
        self.recorder = recorder
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                            .otherMouseDown, .otherMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mouse, handler: { [weak self] e in self?.click(e) }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mouse, handler: { [weak self] e in self?.click(e); return e }) { monitors.append(m) }
        if keys {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in self?.key(e) }) { monitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in self?.key(e); return e }) { monitors.append(m) }
        }
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.skreener.cursor-sampler", qos: .userInteractive))
        t.schedule(deadline: .now(), repeating: 1 / Double(max(1, fps)), leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in
            guard let self, let time = self.recorder?.videoTime(hostTime: Self.now) else { return }
            self.sampleCursor(at: time)
            DispatchQueue.main.async { self.checkCursorImage(at: time) }
        }
        t.resume()
        timer = t
    }

    /// Stops listening and returns the event track, in time order.
    func finish() -> RecordingEvents {
        timer?.cancel(); timer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        lock.lock()
        defer { lock.unlock() }
        return events.sorted()
    }

    private static var now: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    /// Where the pointer is now, at video time `t`. Any thread.
    func sampleCursor(at t: Double) {
        guard let q = CGEvent(source: nil)?.location else { return }
        let p = RecordingGeometry.videoPoint(global: RecordingGeometry.appKitPoint(quartz: q, mainHeight: mainHeight),
                                             area: area, videoSize: videoSize)
        let sample = RecordingEvents.CursorSample(t: t, x: Double(p.x), y: Double(p.y),
                                                  visible: RecordingGeometry.contains(p, videoSize: videoSize))
        append { $0.cursor.append(sample) }
    }

    /// Notes the system cursor's image when it changed, saving a new one as a PNG.
    private func checkCursorImage(at t: Double) {
        guard let cursor = NSCursor.currentSystem, let tiff = cursor.image.tiffRepresentation else { return }
        var key = tiff
        withUnsafeBytes(of: (Double(cursor.hotSpot.x), Double(cursor.hotSpot.y))) { key.append(contentsOf: $0) }
        let index: Int
        if let known = cursorIndex[key] {
            index = known
        } else {
            guard let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            index = cursorIndex.count
            let file = "\(index).png"
            do { try png.write(to: folder.appendingPathComponent(RecordingProject.cursorsFolder).appendingPathComponent(file)) } catch {
                NSLog("Couldn't save a cursor image: \(error)")
                return
            }
            cursorIndex[key] = index
            let image = RecordingEvents.CursorImage(file: file, width: Double(cursor.image.size.width),
                                                    height: Double(cursor.image.size.height),
                                                    hotspotX: Double(cursor.hotSpot.x), hotspotY: Double(cursor.hotSpot.y))
            append { $0.cursorImages.append(image) }
        }
        guard index != lastCursor else { return }
        lastCursor = index
        append { $0.cursorChanges.append(RecordingEvents.CursorChange(t: t, image: index)) }
    }

    private func click(_ e: NSEvent) {
        guard let t = recorder?.videoTime(hostTime: Self.now) else { return }
        let p = RecordingGeometry.videoPoint(global: NSEvent.mouseLocation, area: area, videoSize: videoSize)
        let button: RecordingEvents.Click.Button, down: Bool
        switch e.type {
        case .leftMouseDown: (button, down) = (.left, true)
        case .leftMouseUp: (button, down) = (.left, false)
        case .rightMouseDown: (button, down) = (.right, true)
        case .rightMouseUp: (button, down) = (.right, false)
        case .otherMouseDown: (button, down) = (.other, true)
        default: (button, down) = (.other, false)
        }
        append { $0.clicks.append(RecordingEvents.Click(t: t, x: Double(p.x), y: Double(p.y), button: button, down: down)) }
    }

    private func key(_ e: NSEvent) {
        guard let k = RecordingEffects.keystroke(e), let t = recorder?.videoTime(hostTime: Self.now) else { return }
        append { $0.keys.append(RecordingEvents.Keystroke(t: t, text: k.text, append: k.append)) }
    }

    /// The spotlight was turned on or off. Before the first frame that sets how it starts; while paused it counts
    /// from where the pause began.
    func spotlight(_ on: Bool) {
        guard let recorder else { return }
        let t = recorder.videoTime(hostTime: Self.now, holdWhilePaused: true)
        append { e in
            if let t { e.spotlight.append(RecordingEvents.SpotlightToggle(t: t, on: on)) } else { e.spotlightAtStart = on }
        }
    }

    private func append(_ change: (inout RecordingEvents) -> Void) {
        lock.lock()
        change(&events)
        lock.unlock()
    }
}
