import AppKit
import ApplicationServices
import Vision

extension Notification.Name {
    /// Posted when Step Recorder turns on or off (#242).
    static let skreenerStepRecorderChanged = Notification.Name("SkreenerStepRecorderChanged")
}

/// One step of the guide, as kept in `steps.json` (#242).
struct RecordedStep: Codable, Equatable {
    var id = UUID()
    /// Markdown-lite (see `StepText`).
    var text: String
    /// The counter annotation that marks the click; it is renumbered when steps move.
    var marker: UUID?
}

/// The guide's steps on disk (#242), so only thumbnails stay in memory. The folder holds `steps.json` (the order and
/// text) and, per step, the screenshot as it looks (`<id>.png`) with its editor document beside it, laid out like a
/// history capture's: the editor keeps editing a step the way it does a capture.
@MainActor final class StepStore {
    static let shared = StepStore(directory: StepStore.defaultDirectory)

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Skreener/Step Recorder", isDirectory: true)
    }

    let directory: URL
    private(set) var steps: [RecordedStep] = []
    /// Steps were added, moved, deleted or renumbered (not called for text edits).
    var onChange: (() -> Void)?
    private var renumbering: Task<Void, Never>?

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: listFile), let list = try? JSONDecoder().decode([RecordedStep].self, from: data) {
            steps = list.filter { FileManager.default.fileExists(atPath: png(for: $0).path) }
        }
    }

    private var listFile: URL { directory.appendingPathComponent("steps.json") }

    /// The step's screenshot as it looks now, marker and annotations included.
    func png(for step: RecordedStep) -> URL { directory.appendingPathComponent(step.id.uuidString + ".png") }

    /// Adds a step: `image` with a numbered marker at `click` (image points, bottom-left origin).
    func add(_ image: NSImage, click: CGPoint, text: String) {
        var style = Style()
        style.fontSize = 24
        var marker = Annotation(tool: .counter, start: click, end: click, style: style)
        marker.text = String(steps.count + 1)
        let step = RecordedStep(text: text, marker: marker.id)
        let doc = EditorDocument(items: [marker])
        let file = png(for: step)
        do {
            try doc.write(to: CaptureHistory.documentFolder(for: file), base: image)
            try Self.pngData(Self.render(image, doc)).write(to: file)
        } catch {
            NSLog("Step save failed: \(error)")
            return
        }
        steps.append(step)
        save()
        onChange?()
    }

    /// Text edits don't call `onChange`: the field that changed already shows them.
    func setText(_ text: String, for id: UUID) {
        guard let i = steps.firstIndex(where: { $0.id == id }), steps[i].text != text else { return }
        steps[i].text = text
        save()
    }

    func move(_ id: UUID, by delta: Int) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        steps = StepClicks.moved(steps, from: i, by: delta)
        save()
        onChange?()
        renumber()
    }

    func delete(_ id: UUID) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        CaptureHistory.remove(png(for: steps.remove(at: i)))
        save()
        onChange?()
        renumber()
    }

    func clear() {
        renumbering?.cancel()
        for step in steps { CaptureHistory.remove(png(for: step)) }
        steps = []
        save()
        onChange?()
    }

    /// Gives each step's marker its place in the list, one step at a time so the app stays responsive. Only steps whose
    /// number changed are redrawn.
    private func renumber() {
        renumbering?.cancel()
        renumbering = Task { @MainActor in
            var i = 0
            while i < steps.count, !Task.isCancelled {
                let step = steps[i]
                i += 1
                let file = png(for: step)
                guard let marker = step.marker, let saved = CaptureHistory.document(for: file),
                      let m = saved.document.items.firstIndex(where: { $0.id == marker }),
                      saved.document.items[m].text != String(i) else { continue }
                var doc = saved.document
                doc.items[m].text = String(i)
                CaptureHistory.saveDocument(doc, base: nil, flattened: Self.render(saved.base, doc), for: file)
                await Task.yield()
            }
            if !Task.isCancelled { onChange?() }
        }
    }

    private func save() {
        do { try JSONEncoder().encode(steps).write(to: listFile, options: .atomic) } catch { NSLog("Steps save failed: \(error)") }
    }

    /// The screenshot with the document drawn on it, as the editor would export it.
    static func render(_ base: NSImage, _ doc: EditorDocument) -> NSImage {
        let canvas = CanvasView(image: base)
        canvas.load(doc)
        return canvas.flattened()
    }

    static func pngData(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}

/// Step Recorder (#242): while it is on, each click in another app becomes a step of a guide: a screenshot of the window
/// under the pointer (or the screen) with a numbered marker where the click was, and text naming what was clicked,
/// from its accessibility title or OCR. Skreener's own windows don't get the clicks, so they never make steps.
@MainActor final class StepRecorder {
    static let shared = StepRecorder()

    private(set) var isOn = false
    var onStateChange: ((Bool) -> Void)?
    private var monitor: Any?
    private var lastClick: TimeInterval?
    /// The step being made last; the next one waits for it, so steps keep the order of the clicks.
    private var lastStep: Task<Void, Never>?

    func toggle() { if isOn { stop() } else { start() } }

    func start() {
        guard !isOn else { return }
        // Clicks need no permission; naming the clicked button by its title needs Accessibility (OCR is the fallback).
        if !AccessibilityAccess.granted { AccessibilityAccess.request() }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let point = NSEvent.mouseLocation, time = event.timestamp
            MainActor.assumeIsolated { self?.clicked(at: point, time: time) }
        }
        isOn = true
        lastClick = nil
        changed()
        MessageHUD.show("Step Recorder is on",
                        detail: "Each click becomes a step. Choose Stop Step Recorder in Skreener's menu to finish.",
                        symbol: "cursorarrow.click.2", placement: .top)
    }

    func stop() {
        guard isOn else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isOn = false
        changed()
        StepGuideWindow.show()
    }

    private func changed() {
        onStateChange?(isOn)
        NotificationCenter.default.post(name: .skreenerStepRecorderChanged, object: nil)
    }

    private func clicked(at point: CGPoint, time: TimeInterval) {
        guard StepClicks.accepts(time, after: lastClick) else { return }
        lastClick = time
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let target = Self.window(at: point)
        var rect = (target?.frame ?? screen.frame).intersection(screen.frame).integral
        if rect.width < 1 || rect.height < 1 { rect = screen.frame }
        // Read now: by the time the capture is back, the click may have changed what is under the pointer.
        let ax = Self.accessibilityName(at: point)
        let app = target?.app ?? NSWorkspace.shared.frontmostApplication?.localizedName
        let previous = lastStep
        lastStep = Task { @MainActor in
            let image: NSImage
            do {
                let cg = try await CaptureService.captureScreenImage(screen, globalRect: rect, showsCursor: false, excludingSelf: true)
                image = NSImage(cgImage: cg, size: rect.size)
            } catch {
                await previous?.value
                Notifier.captureFailed(error, what: "Step Recorder")
                return
            }
            let p = StepClicks.imagePoint(point, in: rect)
            var line: String?
            if ax == nil {
                let lines = await TextRecognizer.lines(in: image, area: StepClicks.ocrArea(around: p, imageSize: image.size))
                line = StepText.bestLine(lines.map { (text: $0.text, box: $0.box) }, near: p)
            }
            let text = StepText.make(axName: ax?.name, axRole: ax?.role, ocrLine: line, app: app)
            await previous?.value
            StepStore.shared.add(image, click: p, text: text)
        }
    }

    /// The frontmost normal window under `point` (global, bottom-left origin) that isn't Skreener's: its frame in the
    /// same coordinates and its app's name.
    private static func window(at point: CGPoint) -> (frame: CGRect, app: String?)? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let flipped = CGPoint(x: point.x, y: primaryH - point.y)   // window bounds are top-left origin
        for w in info {
            guard (w[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != getpid(),
                  ((w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.01,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  b.width > 40, b.height > 40, b.contains(flipped) else { continue }
            return (CGRect(x: b.minX, y: primaryH - b.maxY, width: b.width, height: b.height),
                    w[kCGWindowOwnerName as String] as? String)
        }
        return nil
    }

    /// Roles whose title says nothing about what was clicked (a window's title, a list's name).
    private static let containerRoles: Set<String> = [
        "AXWindow", "AXApplication", "AXScrollArea", "AXGroup", "AXSplitGroup", "AXLayoutArea", "AXWebArea", "AXList",
        "AXTable", "AXOutline", "AXBrowser", "AXUnknown", "AXSheet", "AXDrawer", "AXSplitter",
    ]

    /// The accessibility name of the element under `point` (global, bottom-left origin) and its role: its title,
    /// description or placeholder, a label's text, or its parent's when it is only a label or icon inside a control.
    /// Nil without the Accessibility permission or when nothing useful is found.
    private static func accessibilityName(at point: CGPoint) -> (name: String, role: String?)? {
        guard AccessibilityAccess.granted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(primaryH - point.y), &found) == .success,
              var element = found else { return nil }
        var label: String?   // a label's own text, used when no control around it has a name
        for _ in 0..<3 {
            let role = string(element, "AXRole")
            if let role, containerRoles.contains(role) { break }
            for attribute in ["AXTitle", "AXDescription", "AXPlaceholderValue"] {
                if let s = string(element, attribute), StepText.clean(s) != nil { return (s, role) }
            }
            if role == "AXStaticText", label == nil, let s = string(element, "AXValue"), StepText.clean(s) != nil { label = s }
            // Only a label or an icon: the control around it (a button, a cell) may have the name.
            guard role == "AXStaticText" || role == "AXImage", let parent = parent(of: element) else { break }
            element = parent
        }
        return label.map { ($0, "AXStaticText") }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXParent" as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}

extension TextRecognizer {
    struct Line: Sendable {
        let text: String
        /// Image points, bottom-left origin.
        let box: CGRect
    }

    /// Each line of text inside `area` (image points) with its box, for naming a Step Recorder step (#242). Only that
    /// part of the image is read, so small text still counts.
    static func lines(in image: NSImage, area: CGRect) async -> [Line] {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              image.size.width > 0, image.size.height > 0 else { return [] }
        let area = area.intersection(CGRect(origin: .zero, size: image.size))
        let sx = CGFloat(cg.width) / image.size.width, sy = CGFloat(cg.height) / image.size.height
        let pixels = CGRect(x: area.minX * sx, y: (image.size.height - area.maxY) * sy,
                            width: area.width * sx, height: area.height * sy).integral
        guard !area.isEmpty, let crop = cg.cropping(to: pixels) else { return [] }
        let frame = CGRect(x: pixels.minX / sx, y: image.size.height - pixels.maxY / sy,
                           width: CGFloat(crop.width) / sx, height: CGFloat(crop.height) / sy)
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: crop, options: [:])
            do { try handler.perform([request]) } catch { NSLog("OCR failed: \(error)"); return [] }
            return (request.results ?? []).compactMap { obs -> Line? in
                guard let text = obs.topCandidates(1).first?.string else { return nil }
                let b = obs.boundingBox
                return Line(text: text, box: CGRect(x: frame.minX + b.minX * frame.width, y: frame.minY + b.minY * frame.height,
                                                    width: b.width * frame.width, height: b.height * frame.height))
            }
        }.value
    }
}
