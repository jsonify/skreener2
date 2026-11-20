import AppKit
import AVFoundation
import UniformTypeIdentifiers

// Audio added to a recording in the editor: a voiceover recorded afterwards, music, a sound effect. Each file is copied
// into the project's `audio` folder and placed on the recording's own timeline (so cuts and speed changes apply to it
// as to the recorded sound). At export it is mixed in at its volume; with `cleanup`, it gets the voice preset and
// noise removal first, like the recorded microphone (`AudioFinisher`).

/// One added audio file, saved in `studio.json` with the audio settings.
struct AudioClip: Codable, Equatable {
    var id = UUID()
    /// The copy's file name in the project's `audio` folder.
    var file: String
    /// The original file's name, for the editor.
    var name: String
    /// Where it starts on the recording's timeline, in seconds.
    var start: Double
    /// How long this piece plays, in seconds.
    var length: Double
    /// Where in the file this piece begins, in seconds (more than 0 after a split or trimming the start).
    var offset = 0.0
    /// How long the whole file is, in seconds.
    var fileLength: Double
    /// Linear gain, 0…2.
    var volume = 1.0
    /// Gets the voice preset and noise removal, like the recorded microphone.
    var cleanup = true

    init(file: String, name: String, start: Double, length: Double, offset: Double = 0, fileLength: Double? = nil,
         volume: Double = 1, cleanup: Bool = true) {
        self.file = file
        self.name = name
        self.start = start
        self.length = length
        self.offset = offset
        self.fileLength = fileLength ?? offset + length
        self.volume = volume
        self.cleanup = cleanup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? file
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        length = try c.decodeIfPresent(Double.self, forKey: .length) ?? 0
        offset = try c.decodeIfPresent(Double.self, forKey: .offset) ?? 0
        fileLength = try c.decodeIfPresent(Double.self, forKey: .fileLength) ?? offset + length
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1
        cleanup = try c.decodeIfPresent(Bool.self, forKey: .cleanup) ?? true
    }

    var end: Double { start + length }
}

enum AudioClips {
    /// The project folder's subfolder the added files are copied to.
    static let folder = "audio"
    /// What Add Audio… opens.
    static let types: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav, .aiff]

    /// The shortest piece a split or a trim leaves.
    static let minLength = 0.1

    /// In time order, without ones that have no file or no length, with starts at 0 or later, pieces inside their
    /// file and volumes in range.
    static func tidy(_ clips: [AudioClip]) -> [AudioClip] {
        clips.compactMap { c -> AudioClip? in
            guard !c.file.isEmpty, c.length.isFinite, c.length > 0 else { return nil }
            var c = c
            c.start = c.start.isFinite ? max(0, c.start) : 0
            c.fileLength = c.fileLength.isFinite ? max(c.fileLength, c.length) : c.length
            c.offset = c.offset.isFinite ? min(max(c.offset, 0), c.fileLength - c.length) : 0
            c.volume = AudioSettings.clamped(c.volume)
            return c
        }.sorted { $0.start < $1.start }
    }

    /// `clip` moved to start at `start`, kept so it starts within the recording (`duration` seconds).
    static func moved(_ clip: AudioClip, to start: Double, duration: Double) -> AudioClip {
        var c = clip
        let latest = max(0, duration - 0.1)
        c.start = start.isFinite ? min(max(start, 0), latest) : 0
        return c
    }

    /// `clip` cut in two at `t` on the recording's timeline: the piece before and the piece after (a new id), or nil
    /// when `t` isn't inside it by at least `minLength`.
    static func split(_ clip: AudioClip, at t: Double) -> (AudioClip, AudioClip)? {
        let cut = t - clip.start
        guard cut >= minLength, clip.length - cut >= minLength else { return nil }
        var before = clip, after = clip
        before.length = cut
        after.id = UUID()
        after.start = t
        after.offset = clip.offset + cut
        after.length = clip.length - cut
        return (before, after)
    }

    /// `clip` with its start (`start` true) or end edge dragged to `t` on the recording's timeline: trims it, or brings
    /// back sound trimmed off, never past the ends of its file or shorter than `minLength`.
    static func trimmed(_ clip: AudioClip, start: Bool, to t: Double) -> AudioClip {
        var c = clip
        guard t.isFinite else { return c }
        if start {
            // The start can move back as far as the file's beginning (and not before the recording's).
            let earliest = max(clip.start - clip.offset, 0)
            let edge = min(max(t, earliest), clip.end - minLength)
            let d = edge - clip.start
            c.start = edge
            c.offset = clip.offset + d
            c.length = clip.length - d
        } else {
            let latest = clip.start + (clip.fileLength - clip.offset)
            c.length = min(max(t, clip.start + minLength), latest) - clip.start
        }
        return c
    }

    /// `samples` placed at `start` seconds in silence `frames` long (cut off at the end).
    static func placed(_ samples: [Float], at start: Double, frames: Int, sampleRate: Double) -> [Float] {
        var out = [Float](repeating: 0, count: max(0, frames))
        let offset = Int((max(0, start) * sampleRate).rounded())
        guard offset < out.count else { return out }
        let n = min(samples.count, out.count - offset)
        if n > 0 { out.replaceSubrange(offset..<(offset + n), with: samples[0..<n]) }
        return out
    }

    /// Where an added file is kept in the project `folder`.
    static func url(of clip: AudioClip, in folder: URL) -> URL {
        folder.appendingPathComponent(Self.folder, isDirectory: true).appendingPathComponent(clip.file)
    }

    /// Copies `source` into the project `folder` and makes a clip of it starting at `start`; throws when it has no
    /// sound that can be read.
    static func add(_ source: URL, to folder: URL, at start: Double) async throws -> AudioClip {
        let asset = AVURLAsset(url: source)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else { throw AudioClipError.noSound }
        let length = try await asset.load(.duration).seconds
        guard length.isFinite, length > 0 else { throw AudioClipError.noSound }
        let dir = folder.appendingPathComponent(Self.folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let file = "\(UUID().uuidString).\(ext)"
        try FileManager.default.copyItem(at: source, to: dir.appendingPathComponent(file))
        return AudioClip(file: file, name: source.lastPathComponent, start: start, length: length)
    }
}

enum AudioClipError: LocalizedError {
    case noSound

    var errorDescription: String? { "That file has no sound Skreener can read." }
}

/// The recording editor's track for added audio, under the callout track and on the scrubber's time scale: a bar per
/// clip (overlapping ones in rows). Click a bar to select it, drag it to move it, drag its ends to trim it, and Delete
/// removes it. The track only reports what is done; the editor changes the clips.
@MainActor final class AudioClipTrackView: NSView {
    enum Drag {
        case move(grab: Double)
        case trim(start: Bool)
    }

    var clips: [AudioClip] = [] { didSet { if clips != oldValue { changed() } } }
    var selected: UUID? { didSet { if selected != oldValue { needsDisplay = true } } }
    var duration: Double = 0 { didSet { if duration != oldValue { changed() } } }
    var time: Double = 0 { didSet { if time != oldValue { needsDisplay = true } } }
    var isEnabled = true { didSet { if isEnabled != oldValue { needsDisplay = true } } }
    /// Space left and right of the time scale, to line up with the scrubber's track.
    var inset: CGFloat = 0 { didSet { if inset != oldValue { changed() } } }

    var onSelect: ((UUID?) -> Void)?
    var onDragBegan: ((UUID) -> Void)?
    /// The clip was dragged: moved so it starts at the time, or its edge dragged to the time.
    var onDrag: ((UUID, Drag, Double) -> Void)?
    var onDragEnded: (() -> Void)?
    var onDelete: (() -> Void)?

    private var dragging: (id: UUID, kind: Drag)?
    private static let handle: CGFloat = 6

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Added audio")
        toolTip = "Added audio: drag to move, drag an end to trim, Delete removes"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { isEnabled }

    private func changed() {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private var track: CGRect { bounds.insetBy(dx: inset, dy: 0) }

    private func x(_ t: Double) -> CGFloat {
        guard duration > 0 else { return track.minX }
        return track.minX + CGFloat(t / duration) * track.width
    }

    private func timeAt(_ x: CGFloat) -> Double {
        guard track.width > 0 else { return 0 }
        return Double((x - track.minX) / track.width) * duration
    }

    /// Each clip's row: the first one free when it starts (at most two rows).
    nonisolated static func rows(_ clips: [AudioClip]) -> [Int] {
        var ends: [Double] = [-.infinity, -.infinity]
        var rows = [Int](repeating: 0, count: clips.count)
        for i in clips.indices.sorted(by: { clips[$0].start < clips[$1].start }) {
            let row = ends.firstIndex { $0 <= clips[i].start } ?? ends.count - 1
            rows[i] = row
            ends[row] = max(ends[row], clips[i].end)
        }
        return rows
    }

    private func barRects() -> [CGRect] {
        let rows = Self.rows(clips)
        let used = (rows.max() ?? 0) + 1
        let height = (bounds.height - 4) / CGFloat(used)
        return clips.indices.map { i in
            let a = x(clips[i].start), b = x(min(clips[i].end, max(duration, clips[i].start)))
            let y = bounds.maxY - 2 - height * CGFloat(rows[i] + 1)
            return CGRect(x: a, y: y + 1, width: max(b - a, 2), height: height - 2)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        Retro.color(p.track).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let alpha: CGFloat = isEnabled ? 1 : 0.35
        let rects = barRects()
        for (i, c) in clips.enumerated() {
            let r = rects[i]
            let bar = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            NSColor.systemTeal.withAlphaComponent(alpha * (c.id == selected ? 1 : 0.7)).setFill()
            bar.fill()
            if c.id == selected {
                Retro.color(p.ink, alpha: alpha).setStroke()
                bar.lineWidth = 2
                bar.stroke()
            }
            let label: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            ]
            let size = (c.name as NSString).size(withAttributes: label)
            if size.height <= r.height + 2, r.width > 24 {
                (c.name as NSString).draw(with: CGRect(x: r.minX + 4, y: r.midY - size.height / 2, width: r.width - 8, height: size.height),
                                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: label)
            }
        }
        if duration > 0 {
            let px = x(min(max(time, 0), duration)).rounded() + 0.5
            Retro.color(p.ink).setStroke()
            let line = NSBezierPath()
            line.move(to: CGPoint(x: px, y: bounds.minY))
            line.line(to: CGPoint(x: px, y: bounds.maxY))
            line.lineWidth = 1
            line.stroke()
        }
    }

    override func resetCursorRects() {
        guard isEnabled else { return }
        for r in barRects() {
            let handle = min(Self.handle, r.width / 3)
            addCursorRect(CGRect(x: r.minX - 2, y: r.minY, width: handle + 2, height: r.height), cursor: .resizeLeftRight)
            addCursorRect(CGRect(x: r.maxX - handle, y: r.minY, width: handle + 2, height: r.height), cursor: .resizeLeftRight)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        let rects = barRects()
        guard let i = rects.indices.reversed().first(where: { rects[$0].insetBy(dx: -2, dy: 0).contains(p) }) else {
            onSelect?(nil)
            return
        }
        let c = clips[i], r = rects[i]
        onSelect?(c.id)
        let handle = min(Self.handle, r.width / 3)
        let kind: Drag
        if p.x <= r.minX + handle { kind = .trim(start: true) } else if p.x >= r.maxX - handle { kind = .trim(start: false) } else {
            kind = .move(grab: timeAt(p.x) - c.start)
        }
        dragging = (c.id, kind)
        onDragBegan?(c.id)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = dragging else { return }
        let t = timeAt(convert(event.locationInWindow, from: nil).x)
        switch d.kind {
        case .move(let grab): onDrag?(d.id, d.kind, t - grab)
        case .trim: onDrag?(d.id, d.kind, t)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging != nil else { return }
        dragging = nil
        onDragEnded?()
    }

    override func keyDown(with event: NSEvent) {
        if isEnabled, event.keyCode == 51 || event.keyCode == 117, selected != nil {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}
