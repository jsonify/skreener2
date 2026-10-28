import CoreGraphics
import Foundation

/// The options of a Watch This Area watch (#240), remembered between watches.
struct WatchSettings: Equatable {
    /// How often the area is checked.
    enum Interval: Int, CaseIterable {
        case fiveSeconds = 5, thirtySeconds = 30, oneMinute = 60, fiveMinutes = 300

        var title: String {
            switch self {
            case .fiveSeconds: return "5 seconds"
            case .thirtySeconds: return "30 seconds"
            case .oneMinute: return "1 minute"
            case .fiveMinutes: return "5 minutes"
            }
        }
    }

    /// How big a change counts, for the change trigger.
    enum Sensitivity: String, CaseIterable {
        case low, medium, high

        var title: String { rawValue.capitalized }

        /// The smallest mean pixel difference (0…1, see `WatchMath.meanDifference`) that counts as a change. High
        /// notices a few changed words in a large area; Low needs a good part of it to change.
        var threshold: Double {
            switch self {
            case .low: return 0.04
            case .medium: return 0.012
            case .high: return 0.004
            }
        }
    }

    /// What makes the watch notify.
    enum Trigger: String, CaseIterable {
        case change, textAppears, textDisappears

        var title: String {
            switch self {
            case .change: return "It changes"
            case .textAppears: return "This text appears"
            case .textDisappears: return "This text disappears"
            }
        }

        var usesText: Bool { self != .change }
    }

    var interval = Interval.thirtySeconds
    var trigger = Trigger.change
    var sensitivity = Sensitivity.medium
    var text = ""
    /// Keep watching after a notification (the area as it is then becomes the new "before"); otherwise the watch ends.
    var keepWatching = false

    /// The text to look for, trimmed.
    var needle: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A text trigger needs text to look for.
    var isValid: Bool { !trigger.usesText || !needle.isEmpty }

    static func load(from defaults: UserDefaults = .standard) -> WatchSettings {
        var s = WatchSettings()
        if let i = Interval(rawValue: defaults.integer(forKey: "watch.interval")) { s.interval = i }
        if let t = defaults.string(forKey: "watch.trigger").flatMap(Trigger.init(rawValue:)) { s.trigger = t }
        if let v = defaults.string(forKey: "watch.sensitivity").flatMap(Sensitivity.init(rawValue:)) { s.sensitivity = v }
        s.text = defaults.string(forKey: "watch.text") ?? ""
        s.keepWatching = defaults.bool(forKey: "watch.keepWatching")
        return s
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(interval.rawValue, forKey: "watch.interval")
        defaults.set(trigger.rawValue, forKey: "watch.trigger")
        defaults.set(sensitivity.rawValue, forKey: "watch.sensitivity")
        defaults.set(text, forKey: "watch.text")
        defaults.set(keepWatching, forKey: "watch.keepWatching")
    }

    /// The notification's title when the watch of `what` ("area" or "window") fires.
    func notificationTitle(watching what: String) -> String {
        switch trigger {
        case .change: return "The watched \(what) changed"
        case .textAppears: return "“\(needle)” appeared in the watched \(what)"
        case .textDisappears: return "“\(needle)” is gone from the watched \(what)"
        }
    }
}

/// The screen-free part of Watch This Area (#240): frame comparison and the decisions on when to notify.
enum WatchMath {
    /// Frames are compared as `side` × `side` grayscale thumbnails: small enough to be cheap, and the downscale
    /// averages away noise such as a blinking text cursor.
    static let side = 64

    /// `image` as `side` × `side` gray pixels (0 black … 255 white), drawn over white so transparent parts (a window's
    /// rounded corners) are stable. The aspect ratio isn't kept: both frames are squeezed the same way.
    static func grayscale(_ image: CGImage, side: Int = side) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: side * side)
        pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return pixels
    }

    /// The mean absolute difference of two thumbnails, from 0 (the same) to 1 (black turned white everywhere).
    /// Thumbnails of different sizes count as completely different.
    static func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var total = 0
        for i in a.indices { total += abs(Int(a[i]) - Int(b[i])) }
        return Double(total) / Double(a.count * 255)
    }

    /// Whether a mean difference counts as a change at `sensitivity`.
    static func changed(_ difference: Double, sensitivity: WatchSettings.Sensitivity) -> Bool {
        difference >= sensitivity.threshold
    }

    /// Whether `needle` is in the OCR'd `text`: case, spacing, line breaks and look-alike characters (0/O, l/1, rn/m)
    /// don't matter, but it has to be whole words ("Pass" doesn't match "Password").
    static func textFound(_ needle: String, in text: String) -> Bool {
        let term = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return false }
        let lines = text.components(separatedBy: "\n")
        let options = TextMatcher.Options(caseSensitive: false, wholeWord: true, regex: false, fuzzy: true)
        return !TextMatcher.matches(of: [term], in: lines, options: options).isEmpty
    }

    /// Whether a text trigger fires: on the check where the text turns up (`.textAppears`) or goes away
    /// (`.textDisappears`). `wasPresent` is nil on the first check, which only sets the starting point.
    static func textFires(_ trigger: WatchSettings.Trigger, wasPresent: Bool?, isPresent: Bool) -> Bool {
        guard let wasPresent else { return false }
        switch trigger {
        case .change: return false
        case .textAppears: return !wasPresent && isPresent
        case .textDisappears: return wasPresent && !isPresent
        }
    }

    /// Before and after side by side, `height` pixels tall with a gap between, for the notification's thumbnail.
    static func sideBySide(_ before: CGImage, _ after: CGImage, height: Int = 240, gap: Int = 12) -> CGImage? {
        func width(_ image: CGImage) -> Int {
            image.height > 0 ? max(1, Int((Double(image.width) * Double(height) / Double(image.height)).rounded())) : 1
        }
        let wb = width(before), wa = width(after)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: wb + gap + wa, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: height))
        ctx.interpolationQuality = .high
        ctx.draw(before, in: CGRect(x: 0, y: 0, width: wb, height: height))
        ctx.draw(after, in: CGRect(x: wb + gap, y: 0, width: wa, height: height))
        return ctx.makeImage()
    }
}
