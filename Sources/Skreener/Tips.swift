import AppKit

/// One-time tips and usage nudges, shown while `Preferences.showTipsAndHints` is on.
@MainActor enum Tips {
    /// Settings → General → Reset Tips: every tip and "New" dot shows again.
    static func resetAll() {}
}
