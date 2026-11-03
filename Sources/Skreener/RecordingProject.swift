import CoreGraphics
import Foundation

/// A recording made with Record for editing (#380): a `<UUID>.skreenerrec` folder in Application Support/Skreener/
/// Recordings holding the clean video (no cursor, click rings, keystrokes or spotlight), the event track that says
/// where those go (`RecordingEvents`), the cursor images it refers to, and this description of the recording.
/// The effects are drawn back in when the finished MP4 is made (`RecordingRenderer`), so they stay editable.
struct RecordingProject: Codable, Equatable {
    static let currentVersion = 1
    static let fileExtension = "skreenerrec"
    static let videoFile = "video.mp4"
    static let eventsFile = "events.json"
    static let projectFile = "project.json"
    static let cursorsFolder = "cursors"

    var version = RecordingProject.currentVersion
    var created: Date
    /// The recorded area in global screen points, bottom-left origin (as AppKit has it).
    var area: CGRect
    /// The screen's backing scale (2 on Retina) when recording started.
    var screenScale: Double
    /// The video's size in pixels; smaller than area × scale when a big area was scaled down to fit H.264.
    var videoWidth: Int
    var videoHeight: Int
    var fps: Int
    /// How the effects looked in the recording options when recording started.
    var style: EffectsStyle
    /// Where the finished MP4 (effects drawn in) was saved, once it was.
    var exported: String?

    var videoSize: CGSize { CGSize(width: videoWidth, height: videoHeight) }
    /// Video pixels per screen point.
    var pixelScale: CGFloat { RecordingGeometry.pixelsPerPoint(area: area.size, videoSize: videoSize) }

    /// Where recording projects live.
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Skreener/Recordings", isDirectory: true)
    }

    /// A new, empty project folder (with its cursors folder).
    static func makeFolder(in parent: URL = folder) throws -> URL {
        let dir = parent.appendingPathComponent("\(UUID().uuidString).\(fileExtension)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(cursorsFolder, isDirectory: true),
                                                withIntermediateDirectories: true)
        return dir
    }

    func encoded() throws -> Data { try RecordingFile.encoder.encode(self) }

    /// Reads a project file; refuses one written by a newer Skreener.
    static func decode(_ data: Data) throws -> RecordingProject {
        try RecordingFile.check(data, supported: currentVersion)
        return try RecordingFile.decoder.decode(RecordingProject.self, from: data)
    }
}

/// The effect settings a recording was made with. Colors are sRGB components, sizes are in screen points.
struct EffectsStyle: Codable, Equatable {
    var cursor = true
    var clicks = false
    var clickColor = RGBA(red: 1, green: 0.8, blue: 0, alpha: 1)
    var clickSize: Double = 48
    var keystrokes = false
    var keystrokeSize: Double = 24
    var keystrokesAtTop = false
    var spotlightRadius: Double = 120
    /// 0...1
    var spotlightDim: Double = 0.5
}

struct RGBA: Codable, Equatable {
    var red: Double, green: Double, blue: Double, alpha: Double

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

/// What happened while recording, timed in seconds on the video's own timeline: 0 is the first video frame and time
/// spent paused is left out (see `RecordingClock`). Positions are in the video's pixels, top-left origin.
struct RecordingEvents: Codable, Equatable {
    static let currentVersion = 1

    /// The pointer, sampled about once per video frame; also off the recorded area (`visible` false there), so the
    /// spotlight can follow it out.
    struct CursorSample: Codable, Equatable {
        var t: Double
        var x: Double
        var y: Double
        var visible: Bool

        init(t: Double, x: Double, y: Double, visible: Bool) {
            self.t = t; self.x = x; self.y = y; self.visible = visible
        }

        // Short keys: there is one of these per frame.
        private enum CodingKeys: String, CodingKey { case t, x, y, visible = "v" }
    }

    /// A cursor image, stored once as `cursors/<file>`; size and hotspot in screen points (hotspot from the top left).
    struct CursorImage: Codable, Equatable {
        var file: String
        var width: Double
        var height: Double
        var hotspotX: Double
        var hotspotY: Double
    }

    /// From `t` on, the pointer looks like `cursorImages[image]`.
    struct CursorChange: Codable, Equatable {
        var t: Double
        var image: Int
    }

    struct Click: Codable, Equatable {
        enum Button: String, Codable { case left, right, other }
        var t: Double
        var x: Double
        var y: Double
        var button: Button
        /// Pressed (true) or released.
        var down: Bool
    }

    /// A key press as the keystroke display shows it: `text` replaces what is showing, or with `append` is added to it
    /// (plain typing runs together until a pause).
    struct Keystroke: Codable, Equatable {
        var t: Double
        var text: String
        var append: Bool
    }

    struct SpotlightToggle: Codable, Equatable {
        var t: Double
        var on: Bool
    }

    var version = RecordingEvents.currentVersion
    var cursor: [CursorSample] = []
    var cursorImages: [CursorImage] = []
    var cursorChanges: [CursorChange] = []
    var clicks: [Click] = []
    var keys: [Keystroke] = []
    var spotlightAtStart = false
    var spotlight: [SpotlightToggle] = []

    /// Every list in time order (events from different threads can arrive slightly out of order), with cursor
    /// samples less than half a millisecond apart merged.
    func sorted() -> RecordingEvents {
        var e = self
        e.cursor.sort { $0.t < $1.t }
        var merged: [CursorSample] = []
        for s in e.cursor {
            if let last = merged.last, s.t - last.t < 0.0005 { merged[merged.count - 1] = s } else { merged.append(s) }
        }
        e.cursor = merged
        e.cursorChanges.sort { $0.t < $1.t }
        e.clicks.sort { $0.t < $1.t }
        e.keys.sort { $0.t < $1.t }
        e.spotlight.sort { $0.t < $1.t }
        return e
    }

    func encoded() throws -> Data { try RecordingFile.encoder.encode(self) }

    /// Reads an events file; refuses one written by a newer Skreener.
    static func decode(_ data: Data) throws -> RecordingEvents {
        try RecordingFile.check(data, supported: currentVersion)
        return try RecordingFile.decoder.decode(RecordingEvents.self, from: data)
    }
}

enum RecordingFileError: Error, Equatable {
    /// Written by a newer Skreener, in a format this one doesn't know.
    case newerVersion(Int)
    /// No format version: not a recording file.
    case notARecordingFile
}

/// The JSON coding shared by the project and events files.
enum RecordingFile {
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private struct Probe: Decodable { var version: Int? }

    /// Throws unless `data` has a format version this build reads.
    static func check(_ data: Data, supported: Int) throws {
        guard let version = try decoder.decode(Probe.self, from: data).version else { throw RecordingFileError.notARecordingFile }
        if version > supported { throw RecordingFileError.newerVersion(version) }
    }
}
