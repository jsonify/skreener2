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
    /// `mine`: the fine-tuning saved with Save as My Voice (`Preferences.myVoice`).
    case off, level, voice, podcast, mine

    var name: String {
        switch self {
        case .off: return "Off"
        case .level: return "Level Only"
        case .voice: return "Voice"
        case .podcast: return "Podcast"
        case .mine: return "My Voice"
        }
    }

    var detail: String {
        switch self {
        case .off: return "The microphone as recorded."
        case .level: return "Evens out loud and quiet passages and brings the voice to a standard loudness."
        case .voice: return "Removes rumble, adds clarity, softens harsh \"s\" sounds and brings the voice to podcast loudness: a clear voice for tutorials."
        case .podcast: return "Warmer and more present, with firmer levelling and softer \"s\" sounds: a broadcast-style voice."
        case .mine: return "Your own fine-tuning, saved with Save as My Voice."
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

/// What the voice chain does, in terms a person can tune: each preset and noise removal level is one of these, and
/// the editor's fine-tune controls change it. Gains are in dB.
struct VoiceTuning: Codable, Equatable {
    /// Spectral noise reduction, 0 (off) to `maxNoiseReduction`.
    var noiseReduction: Double = 0
    /// How far the pauses between words are turned down (the noise gate), 0 (off) to `maxPauseSilence`.
    var pauseSilence: Double = 0
    /// The rumble filter's frequency in Hz; nil for none.
    var highPass: Double?
    /// Low shelf at 150 Hz: a fuller, warmer voice.
    var warmth: Double = 0
    /// A bell around 420 Hz, usually a small cut: less boxy.
    var mud: Double = 0
    /// Presence at 3.2 kHz (and two thirds of it at 1.4 kHz): a clearer voice.
    var clarity: Double = 0
    /// How far harsh "s" sounds are cut, around 5.2 kHz (0 or more).
    var deEss: Double = 0
    /// High shelf at 11 kHz: more air and sparkle.
    var air: Double = 0
    /// The compressor's ratio; 1 is no compression.
    var compression: Double = 1
    /// The loudness the voice is brought to, in LUFS; nil leaves its level alone.
    var loudness: Double?

    static let maxNoiseReduction = 30.0
    static let maxPauseSilence = 48.0
    static let warmthRange = -6.0...6.0
    static let clarityRange = -6.0...9.0
    static let deEssRange = 0.0...12.0
    static let airRange = -4.0...6.0
    static let compressionRatios = [1.0, 2, 3, 4, 6]
    /// The loudness targets offered: louder for video sites, quieter for broadcast.
    static let loudnessTargets: [(name: String, value: Double)] = [
        ("-14 LUFS (YouTube, loud)", -14), ("-16 LUFS (podcasts, standard)", -16),
        ("-19 LUFS (quieter)", -19), ("-23 LUFS (broadcast)", -23),
    ]

    init() {}

    /// Missing values keep their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        noiseReduction = try c.decodeIfPresent(Double.self, forKey: .noiseReduction) ?? 0
        pauseSilence = try c.decodeIfPresent(Double.self, forKey: .pauseSilence) ?? 0
        highPass = try c.decodeIfPresent(Double.self, forKey: .highPass)
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
        mud = try c.decodeIfPresent(Double.self, forKey: .mud) ?? 0
        clarity = try c.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        deEss = try c.decodeIfPresent(Double.self, forKey: .deEss) ?? 0
        air = try c.decodeIfPresent(Double.self, forKey: .air) ?? 0
        compression = try c.decodeIfPresent(Double.self, forKey: .compression) ?? 1
        loudness = try c.decodeIfPresent(Double.self, forKey: .loudness)
    }

    /// What a preset and noise removal level do.
    init(preset: AudioPreset, noiseRemoval: NoiseRemoval) {
        switch noiseRemoval {
        case .off: break
        case .low: noiseReduction = 10; pauseSilence = 20
        case .high: noiseReduction = 15; pauseSilence = 40
        }
        switch preset {
        case .off:
            highPass = noiseRemoval == .off ? nil : 70
        case .level:
            highPass = noiseRemoval == .off ? nil : 70
            compression = 2
            loudness = Loudness.target
        case .voice, .mine:
            highPass = 80
            mud = -1.5
            clarity = 3
            deEss = 8
            air = 3
            compression = 2
            loudness = Loudness.target
        case .podcast:
            highPass = 90
            warmth = 2
            mud = -2.5
            clarity = 3.5
            deEss = 8
            air = 3
            compression = 3
            loudness = Loudness.target
        }
    }

    /// The noise removal level's part of this tuning set for `level`.
    mutating func setNoise(_ level: NoiseRemoval) {
        let n = VoiceTuning(preset: .off, noiseRemoval: level)
        noiseReduction = n.noiseReduction
        pauseSilence = n.pauseSilence
        if level != .off, highPass == nil { highPass = 70 }
    }

    /// Every value inside its range (a file from elsewhere may have anything).
    var clamped: VoiceTuning {
        func c(_ v: Double, _ r: ClosedRange<Double>) -> Double { v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : 0 }
        var t = self
        t.noiseReduction = c(noiseReduction, 0...Self.maxNoiseReduction)
        t.pauseSilence = c(pauseSilence, 0...Self.maxPauseSilence)
        t.highPass = highPass.map { c($0, 20...300) }
        t.warmth = c(warmth, Self.warmthRange)
        t.mud = c(mud, -6...3)
        t.clarity = c(clarity, Self.clarityRange)
        t.deEss = c(deEss, Self.deEssRange)
        t.air = c(air, Self.airRange)
        t.compression = compression.isFinite ? min(max(compression, 1), 10) : 1
        t.loudness = loudness.map { c($0, -30...(-10)) }
        return t
    }

    /// The compressor's threshold for its ratio, in dB after the voice is levelled to `VoiceChain.preLevelTarget`:
    /// firmer compression starts a little lower.
    static func threshold(ratio: Double) -> Double { -14 - 3 * ratio }

    /// "+3 dB", "0 dB", "-1.5 dB".
    static func decibels(_ v: Double) -> String {
        let r = (v * 2).rounded() / 2
        let text = r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
        return (r > 0 ? "+" : "") + text + " dB"
    }

    /// "Off", "2:1".
    static func ratioText(_ ratio: Double) -> String { ratio <= 1 ? "Off" : "\(Int(ratio.rounded())):1" }
}

/// The recording editor's audio settings, saved in `studio.json`.
struct AudioSettings: Codable, Equatable {
    var preset: AudioPreset = .off
    var noiseRemoval: NoiseRemoval = .off
    /// The fine-tune controls' changes to the preset; nil uses the preset as it is.
    var tuning: VoiceTuning?
    /// Linear gain, 0…2 (1 is as recorded).
    var micVolume: Double = 1
    var systemVolume: Double = 1
    /// Audio files added in the editor (a voiceover, music), mixed in at export.
    var clips: [AudioClip] = []

    static let maxVolume = 2.0

    init() {}

    /// Nothing to do but mix the tracks.
    var isNeutral: Bool {
        effectiveTuning == VoiceTuning() && noiseRemoval == .off && micVolume == 1 && systemVolume == 1 && clips.isEmpty
    }

    /// What is done to the voice: the fine-tuning, or the preset's.
    var effectiveTuning: VoiceTuning { tuning ?? VoiceTuning(preset: preset, noiseRemoval: noiseRemoval) }

    /// Missing values keep their defaults; an unknown preset (from a newer Skreener) reads as off.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = (try? c.decodeIfPresent(AudioPreset.self, forKey: .preset)) ?? .off
        noiseRemoval = (try? c.decodeIfPresent(NoiseRemoval.self, forKey: .noiseRemoval)) ?? .off
        tuning = (try? c.decodeIfPresent(VoiceTuning.self, forKey: .tuning))?.clamped
        micVolume = Self.clamped(try c.decodeIfPresent(Double.self, forKey: .micVolume) ?? 1)
        systemVolume = Self.clamped(try c.decodeIfPresent(Double.self, forKey: .systemVolume) ?? 1)
        clips = AudioClips.tidy(try c.decodeIfPresent([AudioClip].self, forKey: .clips) ?? [])
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
struct VoiceCompressor: Equatable {
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

/// A radix-2 fast Fourier transform of a fixed size (a power of two), for `SpectralDenoiser`.
struct FFT {
    let size: Int
    private let cosines: [Double], sines: [Double]
    private let reversed: [Int]

    init(size: Int) {
        var bits = 0
        while 1 << bits < size { bits += 1 }
        self.size = 1 << bits
        let n = self.size
        cosines = (0..<max(1, n / 2)).map { cos(2 * Double.pi * Double($0) / Double(n)) }
        sines = (0..<max(1, n / 2)).map { sin(2 * Double.pi * Double($0) / Double(n)) }
        reversed = (0..<n).map { i in
            var r = 0, v = i
            for _ in 0..<bits { r = (r << 1) | (v & 1); v >>= 1 }
            return r
        }
    }

    /// Transforms `re` and `im` (each `size` long) in place. The inverse isn't divided by `size`.
    func transform(_ re: inout [Double], _ im: inout [Double], inverse: Bool = false) {
        let n = size
        for i in 0..<n {
            let j = reversed[i]
            if j > i { re.swapAt(i, j); im.swapAt(i, j) }
        }
        let sign = inverse ? 1.0 : -1.0
        var length = 2
        while length <= n {
            let half = length / 2, step = n / length
            var start = 0
            while start < n {
                for k in 0..<half {
                    let wr = cosines[k * step], wi = sign * sines[k * step]
                    let a = start + k, b = a + half
                    let tr = re[b] * wr - im[b] * wi, ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr
                    im[b] = im[a] - ti
                    re[a] += tr
                    im[a] += ti
                }
                start += length
            }
            length *= 2
        }
    }
}

/// Takes the steady background noise (hiss, fans, room tone) out of the voice: the noise's spectrum is measured in the
/// quietest tenth of the track and subtracted from every moment of it, by up to `reduction` dB. Works in overlapping
/// 2048-sample frames, like Auphonic's and Audacity's noise reduction.
struct SpectralDenoiser: Equatable {
    /// The most any frequency is turned down, in dB.
    var reduction: Double
    /// How many times the noise's power is subtracted: more than 1 so that noise varying around its average still goes.
    var oversubtraction = 2.0

    static let frameSize = 2048
    static let hop = 512

    func process(_ x: inout [Float]) {
        let n = Self.frameSize, hop = Self.hop, bins = n / 2 + 1
        guard !x.isEmpty else { return }
        let fft = FFT(size: n)
        let window = (0..<n).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n)) }
        // Frames start every `hop` samples from `-n`, as if the track had `n` zeros on each side, so every sample is
        // covered by the same number of frames.
        let frames = (x.count + n) / hop + 1
        func start(_ k: Int) -> Int { k * hop - n }
        var re = [Double](repeating: 0, count: n), im = re

        func load(_ k: Int) {
            let s = start(k)
            for i in 0..<n {
                let j = s + i
                re[i] = j >= 0 && j < x.count ? Double(x[j]) * window[i] : 0
                im[i] = 0
            }
        }

        // The noise: the average spectrum of the quietest tenth of the frames that have any sound.
        var energies: [(frame: Int, energy: Double)] = []
        for k in 0..<frames {
            let s = start(k)
            var e = 0.0
            for i in 0..<n {
                let j = s + i
                if j >= 0 && j < x.count { let v = Double(x[j]) * window[i]; e += v * v }
            }
            if e > 0 { energies.append((k, e)) }
        }
        guard !energies.isEmpty else { return }
        energies.sort { $0.energy < $1.energy }
        let quiet = energies.prefix(max(1, energies.count / 10))
        var noise = [Double](repeating: 0, count: bins)
        for (k, _) in quiet {
            load(k)
            fft.transform(&re, &im)
            for b in 0..<bins { noise[b] += re[b] * re[b] + im[b] * im[b] }
        }
        for b in 0..<bins { noise[b] /= Double(quiet.count) }

        // Overlap-add of the cleaned frames: a sample is final once no later frame covers it, so it is written back
        // into `x` (which later frames no longer read) a hop at a time.
        var weight = [Double](repeating: 0, count: hop)
        for p in 0..<hop {
            for m in 0..<(n / hop) { weight[p] += window[p + m * hop] * window[p + m * hop] }
        }
        let floor = pow(10, -reduction / 20)
        var pending = [Double](repeating: 0, count: n)
        var smoothed = [Double](repeating: 0, count: bins)
        var gain = [Double](repeating: 1, count: bins)
        for k in 0..<frames {
            load(k)
            fft.transform(&re, &im)
            for b in 0..<bins {
                let power = re[b] * re[b] + im[b] * im[b]
                // Smoothed a little over time so the gain doesn't flutter.
                smoothed[b] = k == 0 ? power : 0.5 * power + 0.5 * smoothed[b]
                let clean = min(max(1 - oversubtraction * noise[b] / max(smoothed[b], 1e-20), 0), 1)
                gain[b] = max(clean.squareRoot(), floor)
            }
            for b in 0..<bins {
                // Averaged with the neighbouring frequencies, so single bins don't ring ("musical noise").
                let g = (gain[max(0, b - 1)] + gain[b] + gain[min(bins - 1, b + 1)]) / 3
                re[b] *= g
                im[b] *= g
                if b > 0 && b < n / 2 {
                    re[n - b] *= g
                    im[n - b] *= g
                }
            }
            fft.transform(&re, &im, inverse: true)
            for i in 0..<n { pending[i] += re[i] / Double(n) * window[i] }
            let s = start(k)
            for i in 0..<hop {
                let j = s + i
                if j >= 0 && j < x.count { x[j] = Float(pending[i] / weight[j % hop]) }
            }
            for i in 0..<(n - hop) { pending[i] = pending[i + hop] }
            for i in (n - hop)..<n { pending[i] = 0 }
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
    static func normalizingGain(loudness: Double, peak: Float, target: Double = Loudness.target,
                                maxGain: Double = Loudness.maxGain) -> Double {
        var gain = min(target - loudness, maxGain)
        if peak > 0 {
            let peakDB = 20 * log10(Double(peak))
            let ceilingDB = 20 * log10(Double(Limiter.ceiling))
            gain = min(gain, ceilingDB + 6 - peakDB)
        }
        return gain
    }

    static func normalize(_ x: inout [Float], sampleRate: Double, target: Double = Loudness.target,
                          maxGain: Double = Loudness.maxGain) {
        guard let loudness = integrated(x, sampleRate: sampleRate) else { return }
        let g = Float(pow(10, normalizingGain(loudness: loudness, peak: peak(x), target: target, maxGain: maxGain) / 20))
        for i in x.indices { x[i] *= g }
    }
}

// MARK: The voice chain

/// What is done to the microphone track for a preset and noise removal setting, in order: noise reduction, the rumble
/// filter, the noise gate, the EQ, levelling to `preLevel` (so the compressor works the same on quiet and loud
/// recordings), the compressor and the final levelling. (Voice Isolation, for High noise removal, runs before this:
/// it needs Apple's audio unit, see `VoiceIsolation`.)
///
/// Tuned against Auphonic's processing of a real tutorial recording: -16 LUFS, silent pauses, gentle compression, a
/// little less boxiness around 450 Hz, more clarity at 1–4 kHz, softer "s" sounds at 4–6 kHz and a little more air.
struct VoiceChain: Equatable {
    var denoiser: SpectralDenoiser?
    var highPass: Double?
    var gate: NoiseGate?
    var eq: [Biquad]
    /// The level, in dB (`Loudness`), the voice is brought to before the compressor.
    var preLevel: Double?
    var compressor: VoiceCompressor?
    var normalizes: Bool
    /// The loudness `normalizes` brings the voice to.
    var target: Double

    /// The level the voice is brought to before the compressor, whose thresholds are set for it.
    static let preLevelTarget = -23.0
    /// Before the compressor a near-silent voice may be turned up further than at the end.
    static let preLevelMaxGain = 40.0

    init(preset: AudioPreset, noiseRemoval: NoiseRemoval, sampleRate: Double) {
        self.init(tuning: VoiceTuning(preset: preset, noiseRemoval: noiseRemoval), sampleRate: sampleRate)
    }

    init(tuning t: VoiceTuning, sampleRate sr: Double) {
        denoiser = t.noiseReduction > 0 ? SpectralDenoiser(reduction: t.noiseReduction) : nil
        gate = t.pauseSilence > 0 ? NoiseGate(reduction: t.pauseSilence) : nil
        highPass = t.highPass
        var eq: [Biquad] = []
        if t.warmth != 0 { eq.append(Biquad.lowShelf(150, gain: t.warmth, sampleRate: sr)) }
        if t.mud != 0 { eq.append(Biquad.peaking(420, gain: t.mud, q: 1.1, sampleRate: sr)) }
        if t.clarity != 0 {
            eq.append(Biquad.peaking(1400, gain: t.clarity * 2 / 3, q: 1.2, sampleRate: sr))
            eq.append(Biquad.peaking(3200, gain: t.clarity, q: 1.2, sampleRate: sr))
        }
        if t.deEss > 0 { eq.append(Biquad.peaking(5200, gain: -t.deEss, q: 1, sampleRate: sr)) }
        if t.air != 0 { eq.append(Biquad.highShelf(11000, gain: t.air, sampleRate: sr)) }
        self.eq = eq
        if t.compression > 1 {
            preLevel = Self.preLevelTarget
            compressor = VoiceCompressor(threshold: VoiceTuning.threshold(ratio: t.compression), ratio: t.compression)
        } else {
            preLevel = nil
            compressor = nil
        }
        target = t.loudness ?? Loudness.target
        normalizes = t.loudness != nil
    }

    var doesAnything: Bool {
        denoiser != nil || highPass != nil || gate != nil || !eq.isEmpty || compressor != nil || normalizes
    }

    func process(_ x: inout [Float], sampleRate: Double) {
        denoiser?.process(&x)
        if let highPass { Biquad.highPass(highPass, sampleRate: sampleRate).process(&x) }
        gate?.process(&x, sampleRate: sampleRate)
        for filter in eq { filter.process(&x) }
        if let preLevel { Loudness.normalize(&x, sampleRate: sampleRate, target: preLevel, maxGain: Self.preLevelMaxGain) }
        compressor?.process(&x, sampleRate: sampleRate)
        if normalizes { Loudness.normalize(&x, sampleRate: sampleRate, target: target) }
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
