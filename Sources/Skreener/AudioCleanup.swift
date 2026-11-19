import Foundation

// Audio cleanup in the recording editor (#385): presets that make a voice sound better (a rumble filter, EQ, a
// compressor and loudness levelling), noise removal for the microphone, and a volume for each track. The settings are
// saved with the editor's settings and applied when exporting (`AudioFinisher`). Everything here works on plain
// sample arrays, so it is unit-tested without AVFoundation.

/// What a recording's audio track holds, in the order of the tracks in its video file.
enum AudioSource: String, Codable, Equatable {
    case system, microphone
    /// System audio and the microphone mixed into one track (recordings made before #385).
    case mixed
}

/// A preset for the voice: what is done to the microphone track at export.
enum AudioPreset: String, Codable, CaseIterable, Equatable {
    case off, level, voice, podcast

    var name: String {
        switch self {
        case .off: return "Off"
        case .level: return "Level Only"
        case .voice: return "Voice"
        case .podcast: return "Podcast"
        }
    }

    var detail: String {
        switch self {
        case .off: return "The microphone as recorded."
        case .level: return "Evens out loud and quiet passages and brings the voice to a standard loudness."
        case .voice: return "Removes rumble, adds clarity and evens out the level: a clear voice for tutorials."
        case .podcast: return "Warmer and more present, with firmer levelling: a broadcast-style voice."
        }
    }
}

/// How much background noise is taken out of the microphone track.
enum NoiseRemoval: String, Codable, CaseIterable, Equatable {
    case off, low, high

    var name: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .high: return "High"
        }
    }
}

/// The recording editor's audio settings, saved in `studio.json`.
struct AudioSettings: Codable, Equatable {
    var preset: AudioPreset = .off
    var noiseRemoval: NoiseRemoval = .off
    /// Linear gain, 0…2 (1 is as recorded).
    var micVolume: Double = 1
    var systemVolume: Double = 1

    static let maxVolume = 2.0

    init() {}

    /// Nothing to do but mix the tracks.
    var isNeutral: Bool { preset == .off && noiseRemoval == .off && micVolume == 1 && systemVolume == 1 }

    /// Missing values keep their defaults; an unknown preset (from a newer Skreener) reads as off.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = (try? c.decodeIfPresent(AudioPreset.self, forKey: .preset)) ?? .off
        noiseRemoval = (try? c.decodeIfPresent(NoiseRemoval.self, forKey: .noiseRemoval)) ?? .off
        micVolume = Self.clamped(try c.decodeIfPresent(Double.self, forKey: .micVolume) ?? 1)
        systemVolume = Self.clamped(try c.decodeIfPresent(Double.self, forKey: .systemVolume) ?? 1)
    }

    static func clamped(_ volume: Double) -> Double { volume.isFinite ? min(max(volume, 0), maxVolume) : 1 }

    /// A volume as the editor shows it, e.g. "100%".
    static func percent(_ volume: Double) -> String { "\(Int((volume * 100).rounded()))%" }
}

// MARK: Filters

/// A second-order filter (the Audio EQ Cookbook's formulas), run over a whole track at once.
struct Biquad: Equatable {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    private static func normalized(_ b0: Double, _ b1: Double, _ b2: Double, _ a0: Double, _ a1: Double, _ a2: Double) -> Biquad {
        Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// Takes out everything below `frequency`: rumble, desk thumps, air conditioning hum.
    static func highPass(_ frequency: Double, q: Double = 0.707, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * frequency / sampleRate, cw = cos(w), alpha = sin(w) / (2 * q)
        return normalized((1 + cw) / 2, -(1 + cw), (1 + cw) / 2, 1 + alpha, -2 * cw, 1 - alpha)
    }

    /// A bell around `frequency`, `gain` dB up or down.
    static func peaking(_ frequency: Double, gain: Double, q: Double, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * frequency / sampleRate, cw = cos(w), alpha = sin(w) / (2 * q)
        let a = pow(10, gain / 40)
        return normalized(1 + alpha * a, -2 * cw, 1 - alpha * a, 1 + alpha / a, -2 * cw, 1 - alpha / a)
    }

    /// Everything below `frequency` `gain` dB up or down.
    static func lowShelf(_ frequency: Double, gain: Double, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * frequency / sampleRate, cw = cos(w)
        let a = pow(10, gain / 40), alpha = sin(w) / 2 * sqrt(2), s = 2 * sqrt(a) * alpha
        return normalized(a * ((a + 1) - (a - 1) * cw + s), 2 * a * ((a - 1) - (a + 1) * cw), a * ((a + 1) - (a - 1) * cw - s),
                          (a + 1) + (a - 1) * cw + s, -2 * ((a - 1) + (a + 1) * cw), (a + 1) + (a - 1) * cw - s)
    }

    /// Everything above `frequency` `gain` dB up or down.
    static func highShelf(_ frequency: Double, gain: Double, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * frequency / sampleRate, cw = cos(w)
        let a = pow(10, gain / 40), alpha = sin(w) / 2 * sqrt(2), s = 2 * sqrt(a) * alpha
        return normalized(a * ((a + 1) + (a - 1) * cw + s), -2 * a * ((a - 1) + (a + 1) * cw), a * ((a + 1) + (a - 1) * cw - s),
                          (a + 1) - (a - 1) * cw + s, 2 * ((a - 1) - (a + 1) * cw), (a + 1) - (a - 1) * cw - s)
    }

    /// The filter's gain at `frequency`, in dB.
    func response(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        // H(e^jw) = (b0 + b1 e^-jw + b2 e^-2jw) / (1 + a1 e^-jw + a2 e^-2jw)
        let nr = b0 + b1 * cos(w) + b2 * cos(2 * w), ni = -(b1 * sin(w) + b2 * sin(2 * w))
        let dr = 1 + a1 * cos(w) + a2 * cos(2 * w), di = -(a1 * sin(w) + a2 * sin(2 * w))
        return 10 * log10((nr * nr + ni * ni) / (dr * dr + di * di))
    }

    func process(_ x: inout [Float]) {
        var z1 = 0.0, z2 = 0.0
        for i in x.indices {
            let input = Double(x[i])
            let y = b0 * input + z1
            z1 = b1 * input - a1 * y + z2
            z2 = b2 * input - a2 * y
            x[i] = Float(y)
        }
    }
}

// MARK: Dynamics

/// Turns the level down between words, where only the background noise is: a downward expander with a threshold a
/// little above the noise floor it measures in the track.
struct NoiseGate: Equatable {
    /// How far the noise is turned down, in dB.
    var reduction: Double
    var attack = 0.003, hold = 0.12, release = 0.1

    /// The background noise's level in dBFS: the quietest tenth of 50 ms blocks, leaving out digital silence. Nil for a
    /// track with no sound.
    static func noiseFloor(_ x: [Float], sampleRate: Double) -> Double? {
        let block = max(1, Int(sampleRate * 0.05))
        var levels: [Double] = []
        var i = 0
        while i + block <= x.count {
            var sum = 0.0
            for j in i..<(i + block) { sum += Double(x[j]) * Double(x[j]) }
            let ms = sum / Double(block)
            if ms > 1e-12 { levels.append(10 * log10(ms)) }
            i += block
        }
        guard !levels.isEmpty else { return nil }
        levels.sort()
        return levels[levels.count / 10]
    }

    /// Where the gate opens: 10 dB above the noise floor, but never above -25 dBFS so speech always gets through.
    static func threshold(noiseFloor: Double) -> Double { min(noiseFloor + 10, -25) }

    func process(_ x: inout [Float], sampleRate: Double) {
        guard let floor = Self.noiseFloor(x, sampleRate: sampleRate) else { return }
        let threshold = pow(10, Self.threshold(noiseFloor: floor) / 10) // as a mean square
        let closed = pow(10, -reduction / 20)
        let detect = 1 - exp(-1 / (0.01 * sampleRate))
        let open = 1 - exp(-1 / (attack * sampleRate)), close = 1 - exp(-1 / (release * sampleRate))
        let holdSamples = Int(hold * sampleRate)
        var env = 0.0, gain = 1.0, held = 0
        for i in x.indices {
            let s = Double(x[i])
            env += detect * (s * s - env)
            if env > threshold { held = holdSamples } else if held > 0 { held -= 1 }
            let target = held > 0 ? 1 : closed
            gain += (target > gain ? open : close) * (target - gain)
            x[i] = Float(s * gain)
        }
    }
}

/// Evens out the voice: turns down whatever goes over the threshold, by the ratio, with a soft knee.
struct Compressor: Equatable {
    var threshold: Double
    var ratio: Double
    var knee = 6.0
    var attack = 0.005, release = 0.12

    /// How many dB a signal at `level` dBFS is turned down (0 or less).
    static func gainChange(level: Double, threshold: Double, ratio: Double, knee: Double) -> Double {
        let over = level - threshold
        if 2 * over <= -knee { return 0 }
        if 2 * over >= knee { return over / ratio - over }
        let x = over + knee / 2
        return (1 / ratio - 1) * x * x / (2 * knee)
    }

    func process(_ x: inout [Float], sampleRate: Double) {
        let up = 1 - exp(-1 / (attack * sampleRate)), down = 1 - exp(-1 / (release * sampleRate))
        var env = 0.0
        for i in x.indices {
            let a = abs(Double(x[i]))
            env += (a > env ? up : down) * (a - env)
            guard env > 1e-6 else { continue }
            let change = Self.gainChange(level: 20 * log10(env), threshold: threshold, ratio: ratio, knee: knee)
            if change < 0 { x[i] = Float(Double(x[i]) * pow(10, change / 20)) }
        }
    }
}

/// Keeps the mix under `ceiling`: turns down at once wherever a sample would go over, and back up slowly.
enum Limiter {
    static let ceiling: Float = 0.891 // -1 dBFS

    static func process(_ channels: inout [[Float]], ceiling: Float = Limiter.ceiling, sampleRate: Double) {
        guard let count = channels.first?.count else { return }
        let recover = Float(1 - exp(-1 / (0.08 * sampleRate)))
        var gain: Float = 1
        for i in 0..<count {
            var peak: Float = 0
            for c in channels.indices { peak = max(peak, abs(channels[c][i])) }
            let needed = peak > ceiling ? ceiling / peak : 1
            gain = min(gain + recover * (1 - gain), needed)
            if gain < 1 { for c in channels.indices { channels[c][i] *= gain } }
        }
    }
}

// MARK: Loudness

/// Loudness for levelling: the mean square over 400 ms blocks, gated as in ITU-R BS.1770 (blocks under -70 dB, then
/// those more than 10 dB under the average, are left out), without its K-weighting filter. Good enough to bring a
/// voice to a standard level; it isn't a certified LUFS meter.
enum Loudness {
    /// The level presets bring the voice to (-16 is what Apple Podcasts and most platforms aim at).
    static let target = -16.0
    /// The most a quiet recording is turned up, so a near-silent track doesn't become loud noise.
    static let maxGain = 24.0

    static func integrated(_ x: [Float], sampleRate: Double) -> Double? {
        let block = max(1, Int(sampleRate * 0.4)), hop = max(1, block / 4)
        guard x.count >= block else { return nil }
        // Running sums of squares, so each block costs nothing.
        var squares = [Double](repeating: 0, count: x.count + 1)
        for i in x.indices { squares[i + 1] = squares[i] + Double(x[i]) * Double(x[i]) }
        var blocks: [Double] = []
        var start = 0
        while start + block <= x.count {
            blocks.append((squares[start + block] - squares[start]) / Double(block))
            start += hop
        }
        func level(_ ms: Double) -> Double { 10 * log10(ms) }
        let loud = blocks.filter { $0 > 0 && level($0) > -70 }
        guard !loud.isEmpty else { return nil }
        let relative = level(loud.reduce(0, +) / Double(loud.count)) - 10
        let gated = loud.filter { level($0) > relative }
        guard !gated.isEmpty else { return nil }
        return level(gated.reduce(0, +) / Double(gated.count))
    }

    static func peak(_ x: [Float]) -> Float { x.reduce(0) { max($0, abs($1)) } }

    /// The gain in dB that brings `loudness` to `target`, at most `maxGain`. Peaks over the ceiling are left to the
    /// limiter, but never by more than 6 dB, so it doesn't have to squash the voice.
    static func normalizingGain(loudness: Double, peak: Float, target: Double = Loudness.target) -> Double {
        var gain = min(target - loudness, maxGain)
        if peak > 0 {
            let peakDB = 20 * log10(Double(peak))
            let ceilingDB = 20 * log10(Double(Limiter.ceiling))
            gain = min(gain, ceilingDB + 6 - peakDB)
        }
        return gain
    }

    static func normalize(_ x: inout [Float], sampleRate: Double) {
        guard let loudness = integrated(x, sampleRate: sampleRate) else { return }
        let g = Float(pow(10, normalizingGain(loudness: loudness, peak: peak(x)) / 20))
        for i in x.indices { x[i] *= g }
    }
}

// MARK: The voice chain

/// What is done to the microphone track for a preset and noise removal setting, in order: the rumble filter, the
/// noise gate, the EQ, the compressor and the levelling. (Voice Isolation, for High noise removal, runs before this:
/// it needs Apple's audio unit, see `VoiceIsolation`.)
struct VoiceChain: Equatable {
    var highPass: Double?
    var gate: NoiseGate?
    var eq: [Biquad]
    var compressor: Compressor?
    var normalizes: Bool

    init(preset: AudioPreset, noiseRemoval: NoiseRemoval, sampleRate: Double) {
        let sr = sampleRate
        switch noiseRemoval {
        case .off: gate = nil
        case .low: gate = NoiseGate(reduction: 10)
        case .high: gate = NoiseGate(reduction: 18)
        }
        switch preset {
        case .off:
            highPass = noiseRemoval == .off ? nil : 70
            eq = []
            compressor = nil
            normalizes = false
        case .level:
            highPass = noiseRemoval == .off ? nil : 70
            eq = []
            compressor = Compressor(threshold: -24, ratio: 2)
            normalizes = true
        case .voice:
            highPass = 80
            eq = [Biquad.peaking(250, gain: -2, q: 1, sampleRate: sr),
                  Biquad.peaking(3500, gain: 3, q: 1, sampleRate: sr),
                  Biquad.highShelf(10000, gain: 1.5, sampleRate: sr)]
            compressor = Compressor(threshold: -22, ratio: 3)
            normalizes = true
        case .podcast:
            highPass = 90
            eq = [Biquad.lowShelf(150, gain: 2.5, sampleRate: sr),
                  Biquad.peaking(350, gain: -3, q: 1.2, sampleRate: sr),
                  Biquad.peaking(4000, gain: 4, q: 0.9, sampleRate: sr),
                  Biquad.highShelf(10000, gain: 2, sampleRate: sr)]
            compressor = Compressor(threshold: -26, ratio: 4)
            normalizes = true
        }
    }

    var doesAnything: Bool { highPass != nil || gate != nil || !eq.isEmpty || compressor != nil || normalizes }

    func process(_ x: inout [Float], sampleRate: Double) {
        if let highPass { Biquad.highPass(highPass, sampleRate: sampleRate).process(&x) }
        gate?.process(&x, sampleRate: sampleRate)
        for filter in eq { filter.process(&x) }
        compressor?.process(&x, sampleRate: sampleRate)
        if normalizes { Loudness.normalize(&x, sampleRate: sampleRate) }
    }
}

// MARK: Mixing

enum AudioMix {
    /// Mixes mono voice tracks (on both sides) and stereo tracks into one stereo track of `frames` frames, each with
    /// its gain, and limits the result.
    static func stereo(mono: [(samples: [Float], gain: Float)], stereo: [(samples: [[Float]], gain: Float)],
                       frames: Int, sampleRate: Double) -> [[Float]] {
        var left = [Float](repeating: 0, count: frames), right = left
        for (samples, gain) in mono where gain != 0 {
            for i in 0..<min(frames, samples.count) {
                let s = samples[i] * gain
                left[i] += s
                right[i] += s
            }
        }
        for (samples, gain) in stereo where gain != 0 && samples.count == 2 {
            for i in 0..<min(frames, samples[0].count, samples[1].count) {
                left[i] += samples[0][i] * gain
                right[i] += samples[1][i] * gain
            }
        }
        var out = [left, right]
        Limiter.process(&out, sampleRate: sampleRate)
        return out
    }
}
