import CoreGraphics
import Foundation

/// What the recording editor's Export makes (#386): the recording at its own size (saved over it), a fixed frame for
/// a video site or social media (saved next to it), or a GIF.
enum ExportPreset: String, Codable, CaseIterable {
    case original, hd1080, uhd4k, square, vertical, gif

    var name: String {
        switch self {
        case .original: return "Original Size"
        case .hd1080: return "1080p (16:9)"
        case .uhd4k: return "4K (16:9)"
        case .square: return "Square (1:1)"
        case .vertical: return "Vertical (9:16)"
        case .gif: return "GIF"
        }
    }

    /// The output frame in pixels; nil keeps the recording's own layout. The recording is fitted inside it, with the
    /// background (or black, without one) around it.
    var frame: CGSize? {
        switch self {
        case .original, .gif: return nil
        case .hd1080: return CGSize(width: 1920, height: 1080)
        case .uhd4k: return CGSize(width: 3840, height: 2160)
        case .square: return CGSize(width: 1080, height: 1080)
        case .vertical: return CGSize(width: 1080, height: 1920)
        }
    }

    /// Whether the export replaces the recording; the others are saved next to it.
    var replacesRecording: Bool { self == .original }

    /// Where an export with this preset of the recording at `recording` goes: the recording itself, or a file next to
    /// it named after it ("Demo (Vertical).mp4", "Demo.gif").
    func destination(for recording: URL) -> URL {
        let base = recording.deletingPathExtension()
        let name = base.lastPathComponent
        let folder = base.deletingLastPathComponent()
        switch self {
        case .original: return recording
        case .gif: return folder.appendingPathComponent(name + ".gif")
        case .hd1080: return folder.appendingPathComponent(name + " (1080p).mp4")
        case .uhd4k: return folder.appendingPathComponent(name + " (4K).mp4")
        case .square: return folder.appendingPathComponent(name + " (Square).mp4")
        case .vertical: return folder.appendingPathComponent(name + " (Vertical).mp4")
        }
    }
}
