import Foundation

/// A named look (#441).
struct LookPreset: Codable, Equatable, Identifiable {
    var name: String
    var look: Look
    var id: String { name }
}

extension Look {
    /// Whether two looks draw the same picture. The drawing size is no part of a preset, so it is ignored; so are
    /// the sliders when there is no background, and Dark for no frame, as they change nothing then.
    func sameStyle(as other: Look) -> Bool {
        guard frame == other.frame, background == other.background, cleanBar == other.cleanBar else { return false }
        if frame != "plain", dark != other.dark { return false }
        if background != nil {
            return padding == other.padding && cornerRadius == other.cornerRadius && shadow == other.shadow
        }
        return true
    }
}

/// The saved looks, in the order they were saved (#441). The app and the Share Extension share them through the same
/// App Group defaults as `Look`. Names are unique, ignoring case and surrounding spaces.
///
/// Foundation only. Decoding never fails: bad data gives no presets, and a bad entry is skipped.
struct LookPresets: Equatable {
    private(set) var items: [LookPreset] = []

    /// The most presets kept.
    static let limit = 12
    /// The longest name kept; a longer one is cut.
    static let nameLength = 30
    static let key = "lookPresets"

    enum Outcome: Equatable {
        case added, replaced, renamed, updated
        /// Already `limit` presets, and the name is a new one.
        case full
        /// The name is empty.
        case invalidName
        /// A rename to the name of another preset.
        case nameTaken
        /// No preset has that name.
        case missing
    }

    /// `name` trimmed and cut to `nameLength`; nil when nothing is left.
    static func clean(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(trimmed.prefix(nameLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut.isEmpty ? nil : cut
    }

    var isFull: Bool { items.count >= Self.limit }

    private func index(of name: String) -> Int? {
        guard let name = Self.clean(name) else { return nil }
        return items.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func contains(name: String) -> Bool { index(of: name) != nil }

    /// Saves `look` as `name`, replacing the preset with that name (it keeps its place and takes the new spelling).
    @discardableResult
    mutating func add(_ look: Look, as name: String) -> Outcome {
        guard let name = Self.clean(name) else { return .invalidName }
        if let i = index(of: name) {
            items[i] = LookPreset(name: name, look: look)
            return .replaced
        }
        guard !isFull else { return .full }
        items.append(LookPreset(name: name, look: look))
        return .added
    }

    /// Gives the preset `name` the new name `newName`; a name another preset has is refused.
    @discardableResult
    mutating func rename(_ name: String, to newName: String) -> Outcome {
        guard let newName = Self.clean(newName) else { return .invalidName }
        guard let i = index(of: name) else { return .missing }
        if let j = index(of: newName), j != i { return .nameTaken }
        items[i].name = newName
        return .renamed
    }

    /// Makes the preset `name` hold `look`.
    @discardableResult
    mutating func update(_ name: String, to look: Look) -> Outcome {
        guard let i = index(of: name) else { return .missing }
        items[i].look = look
        return .updated
    }

    mutating func delete(_ name: String) {
        if let i = index(of: name) { items.remove(at: i) }
    }

    /// The first preset that draws the same as `look`.
    func match(_ look: Look) -> LookPreset? {
        items.first { $0.look.sameStyle(as: look) }
    }

    /// `base`, or `base 2`, `base 3`... when a preset has that name already: a name Save can offer.
    func freeName(_ base: String) -> String {
        guard let base = Self.clean(base) else { return "Look" }
        guard contains(name: base) else { return base }
        var n = 2
        while contains(name: "\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: Storage

    /// The presets in `data`; none when there is no data or it is not what `encoded()` writes. Entries that cannot
    /// be read, have no name or repeat a name are dropped, and no more than `limit` are kept.
    static func decode(_ data: Data?) -> LookPresets {
        guard let data, let list = try? JSONDecoder().decode(Lossy.self, from: data) else { return LookPresets() }
        var presets = LookPresets()
        for item in list.items { presets.add(item.look, as: item.name) }
        return presets
    }

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(items)
    }

    /// An array whose unreadable entries are skipped instead of failing the whole read.
    private struct Lossy: Decodable {
        var items: [LookPreset] = []

        private struct Skip: Decodable {}

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            while !c.isAtEnd {
                if let item = try? c.decode(LookPreset.self) {
                    items.append(item)
                } else {
                    _ = try? c.decode(Skip.self)  // step past the bad entry
                }
            }
        }
    }

    static func load(from defaults: UserDefaults = Look.defaults) -> LookPresets {
        decode(defaults.data(forKey: key))
    }

    func save(to defaults: UserDefaults = Look.defaults) {
        if let data = encoded() { defaults.set(data, forKey: Self.key) }
    }
}
