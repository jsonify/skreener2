import Foundation

/// The style the user used last (#408): frame, dark, background, the three sliders, Clean bar and the drawings' size
/// (#440). The app and the Share Extension share it through the App Group, so styling in one carries to the other.
/// Not part of it: redactions, drawings, the browser URL and the mode.
///
/// Foundation only. Decoding never fails on old or partial data: a missing or unusable field takes its default.
struct Look: Codable, Equatable {
    var frame: String
    var dark: Bool
    /// An index into `Background.presets`; nil is no background.
    var background: Int?
    var padding: Double
    var cornerRadius: Double
    var shadow: Double
    /// Clean bar; it only takes effect on screenshots whose status bar Skreener knows.
    var cleanBar: Bool
    /// The size slider's width for new drawings and text, a `Markup.width` multiplier (1 is the default line).
    var markupWidth: Double

    /// What a fresh editor starts with.
    static let standard = Look(frame: "iPhone", dark: false, background: 0, padding: 48, cornerRadius: 10, shadow: 0.5,
                                cleanBar: false, markupWidth: 1)

    /// `Markup.widthRange`, kept here as Doubles so this file stays Foundation only.
    static let markupWidthRange: ClosedRange<Double> = 0.5...4

    /// The frame names `ShareModel.FrameChoice` maps to and from.
    static let frames = ["plain", "iPhone", "browser", "macWindow"]

    /// The app group both targets list in their entitlements.
    static let suiteName = "group.com.skreener.ios"
    static let key = "look"

    init(frame: String, dark: Bool, background: Int?, padding: Double, cornerRadius: Double, shadow: Double,
         cleanBar: Bool, markupWidth: Double) {
        self.frame = frame
        self.dark = dark
        self.background = background
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.cleanBar = cleanBar
        self.markupWidth = markupWidth
    }

    private enum CodingKeys: String, CodingKey {
        case frame, dark, background, padding, cornerRadius, shadow, cleanBar, markupWidth
    }

    /// A missing or unusable field takes the default; a missing background key means the default, an explicit null
    /// means no background.
    init(from decoder: Decoder) throws {
        let d = Look.standard
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let frame = (try? c.decodeIfPresent(String.self, forKey: .frame)) ?? d.frame
        self.frame = Look.frames.contains(frame) ? frame : d.frame
        dark = (try? c.decodeIfPresent(Bool.self, forKey: .dark)) ?? d.dark
        if c.contains(.background), (try? c.decodeNil(forKey: .background)) == true {
            background = nil
        } else {
            background = (try? c.decodeIfPresent(Int.self, forKey: .background)) ?? d.background
        }
        padding = Look.clamped((try? c.decodeIfPresent(Double.self, forKey: .padding)) ?? d.padding, 0...160, d.padding)
        cornerRadius = Look.clamped((try? c.decodeIfPresent(Double.self, forKey: .cornerRadius)) ?? d.cornerRadius,
                                    0...40, d.cornerRadius)
        shadow = Look.clamped((try? c.decodeIfPresent(Double.self, forKey: .shadow)) ?? d.shadow, 0...1, d.shadow)
        cleanBar = (try? c.decodeIfPresent(Bool.self, forKey: .cleanBar)) ?? d.cleanBar
        // Missing from looks saved before the size slider: the default.
        markupWidth = Look.clamped((try? c.decodeIfPresent(Double.self, forKey: .markupWidth)) ?? d.markupWidth,
                                   Look.markupWidthRange, d.markupWidth)
    }

    private static func clamped(_ v: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        v.isFinite ? min(max(v, range.lowerBound), range.upperBound) : fallback
    }

    /// The look in `data`, or `standard` when there is none or it is not JSON. A background that `offered` lacks
    /// (a preset no longer on offer) becomes the default.
    static func decode(_ data: Data?, offered: [Int?]) -> Look {
        guard let data, var look = try? JSONDecoder().decode(Look.self, from: data) else { return .standard }
        if !offered.contains(look.background) { look.background = standard.background }
        return look
    }

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /// The shared defaults; `.standard` if the suite is not available.
    static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

    static func load(from defaults: UserDefaults = Look.defaults, offered: [Int?]) -> Look {
        decode(defaults.data(forKey: key), offered: offered)
    }

    func save(to defaults: UserDefaults = Look.defaults) {
        if let data = encoded() { defaults.set(data, forKey: Look.key) }
    }
}
