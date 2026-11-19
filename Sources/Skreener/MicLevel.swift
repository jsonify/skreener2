import Foundation

/// The microphone's level while recording, for the meter in the recording HUD (#469): the loudest sample of each
/// buffer goes in (`MicLevelTap`, on the recorder's queue), and `MicMeter` turns it into what the meter shows, on the
/// main queue. Levels are in dBFS: 0 is the loudest a sample can be, `MicMeter.floor` the quietest the meter shows.
enum MicLevel {
    /// The loudest sample, as an amplitude from 0 to 1.
    static func peak(_ samples: UnsafeBufferPointer<Float>) -> Float {
        var peak: Float = 0
        for s in samples { peak = max(peak, abs(s)) }
        return peak
    }

    /// The loudest sample of 16-bit audio, as an amplitude from 0 to 1.
    static func peak(_ samples: UnsafeBufferPointer<Int16>) -> Float {
        var peak: Int32 = 0
        for s in samples { peak = max(peak, abs(Int32(s))) }
        return min(1, Float(peak) / Float(Int16.max))
    }

    /// `amplitude` in dBFS, never below `MicMeter.floor` (silence would be minus infinity).
    static func decibels(_ amplitude: Float) -> Double {
        guard amplitude > 0 else { return MicMeter.floor }
        return min(0, max(MicMeter.floor, 20 * log10(Double(amplitude))))
    }
}

/// Collects the loudest microphone sample between two reads: the recorder writes from its queue, the HUD reads about
/// 30 times a second on the main queue.
final class MicLevelTap: @unchecked Sendable {
    private let lock = NSLock()
    private var loudest: Float?

    func record(_ peak: Float) {
        lock.lock()
        loudest = max(loudest ?? 0, peak)
        lock.unlock()
    }

    /// The loudest sample since the last call, or nil when no microphone audio arrived in between.
    func take() -> Float? {
        lock.lock()
        defer { lock.unlock() }
        let value = loudest
        loudest = nil
        return value
    }
}

/// What the HUD's mic meter shows: the bar (jumps up at once, falls back slowly so it can be read), a peak marker
/// that stays put for a moment, a clip light that stays on for two seconds, and a word of advice for the tooltip and
/// VoiceOver. Fed with the loudest sample since the last update and the time, so it can be tested without a clock.
struct MicMeter: Equatable {
    static let floor = -60.0
    /// How fast the bar and the peak marker fall, in dB per second.
    static let fallRate = 24.0
    /// How long the peak marker stays before it falls.
    static let holdSeconds = 1.5
    /// A sample this loud (or louder) is counted as clipping.
    static let clipLevel = -0.5
    static let clipSeconds = 2.0
    /// No sound at all for this long means the microphone isn't delivering anything (muted, or the wrong device).
    static let silenceSeconds = 3.0
    /// The meter's segments: each lights at its level in dBFS.
    static let segments: [Double] = [-54, -48, -42, -36, -30, -24, -18, -12, -9, -6, -3, -1]
    /// How slowly the level behind the advice falls, in dB per second, so a pause between sentences isn't "quiet".
    static let adviceFallRate = 4.0
    /// Below this the advice is "quiet".
    static let quietLevel = -40.0

    enum Zone: Equatable { case good, hot, clipping }

    enum Advice: Equatable {
        case good, quiet, tooLoud, noSound

        var text: String {
            switch self {
            case .good: return "Microphone level is good"
            case .quiet: return "Microphone is quiet: speak closer to it, or raise its input volume in System Settings › Sound"
            case .tooLoud: return "Microphone is too loud and clipping: lower its input volume in System Settings › Sound, or move back"
            case .noSound: return "No sound from the microphone: check that it isn't muted and that the right one is selected"
            }
        }
    }

    /// The bar's level, in dBFS.
    private(set) var level = MicMeter.floor
    /// The peak marker's level, in dBFS.
    private(set) var held = MicMeter.floor
    private var heldAt = -Double.infinity
    private var clippedAt = -Double.infinity
    /// The loudest recent level, falling slowly (see `adviceFallRate`).
    private var recent = MicMeter.floor
    private var startedAt: Double?
    private var soundAt: Double?
    private var now: Double?

    /// Moves the meter to time `t` (seconds, any clock) with `peak`, the loudest sample since the last update as an
    /// amplitude from 0 to 1, or nil when no audio arrived since.
    mutating func update(peak: Float?, at t: Double) {
        let elapsed = now.map { max(0, t - $0) } ?? 0
        if startedAt == nil { startedAt = t }
        now = t
        level = max(Self.floor, level - Self.fallRate * elapsed)
        recent = max(Self.floor, recent - Self.adviceFallRate * elapsed)
        if t - heldAt > Self.holdSeconds { held = max(Self.floor, held - Self.fallRate * elapsed) }
        guard let peak else { return }
        let db = MicLevel.decibels(peak)
        level = max(level, db)
        recent = max(recent, db)
        if db >= held { held = db; heldAt = t }
        if db >= Self.clipLevel { clippedAt = t }
        // Anything above digital silence counts as sound, even a quiet room.
        if peak > 0.000_01 { soundAt = t }
    }

    var isClipping: Bool { (now ?? -.infinity) - clippedAt < Self.clipSeconds }

    /// How many segments the bar lights.
    var litSegments: Int { Self.lit(level) }
    /// The segment the peak marker lights (0-based), or nil when it is below the first.
    var heldSegment: Int? { Self.lit(held) > 0 ? Self.lit(held) - 1 : nil }

    static func lit(_ db: Double) -> Int { segments.filter { db >= $0 }.count }

    /// The colour of segment `index`: green up to -9 dBFS, amber at -6 and -3, red at -1.
    static func zone(ofSegment index: Int) -> Zone {
        let db = segments[index]
        if db >= -1 { return .clipping }
        if db >= -6 { return .hot }
        return .good
    }

    var advice: Advice {
        guard let now, let startedAt else { return .good }
        if now - (soundAt ?? startedAt) >= Self.silenceSeconds { return .noSound }
        if isClipping { return .tooLoud }
        // Only once there was time to say something.
        if recent < Self.quietLevel && now - startedAt >= Self.silenceSeconds { return .quiet }
        return .good
    }
}
