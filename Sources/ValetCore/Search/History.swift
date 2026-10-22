import Foundation

/// What you've run and pinned, for the palette's Pinned and Recent sections and its ranking. Stays on this Mac,
/// in `~/Library/Application Support/Valet/history.json`.
public struct History: Codable, Sendable, Equatable {
    public struct Use: Codable, Sendable, Equatable {
        public var count: Int
        public var last: Date
    }

    public var pins: [String] = []
    public var uses: [String: Use] = [:]

    public init() {}

    public mutating func recordUse(_ key: String, at date: Date = .now) {
        var use = uses[key] ?? Use(count: 0, last: date)
        use.count += 1
        use.last = date
        uses[key] = use
    }

    public mutating func togglePin(_ key: String) {
        if let index = pins.firstIndex(of: key) { pins.remove(at: index) } else { pins.append(key) }
    }

    public func isPinned(_ key: String) -> Bool { pins.contains(key) }

    /// Most recent first.
    public func recent(limit: Int = 3) -> [String] {
        uses.sorted { $0.value.last > $1.value.last }.prefix(limit).map(\.key)
    }

    /// Uses, weighted toward recent ones: a use today counts fully, one a day ago about half.
    public func frecency(_ key: String, now: Date = .now) -> Double {
        guard let use = uses[key] else { return 0 }
        let days = max(0, now.timeIntervalSince(use.last)) / 86_400
        return Double(use.count) / (1 + days)
    }

    /// Search boosts: pins and frecency, capped so a strong text match still wins.
    public func boosts(now: Date = .now) -> [String: Double] {
        var boosts: [String: Double] = [:]
        for key in uses.keys { boosts[key] = min(6, 2 * frecency(key, now: now)) }
        for key in pins { boosts[key, default: 0] += 6 }
        return boosts
    }

    /// Drops entries for apps you no longer have, so the file doesn't grow forever.
    public mutating func prune(keepingIconIDs ids: Set<String>) {
        let keep = { (key: String) in ids.contains { key.hasPrefix("icon|\($0)") || key.hasPrefix("\($0)|") } }
        uses = uses.filter { keep($0.key) }
        pins = pins.filter(keep)
    }
}

/// Loads and saves `History` as JSON.
public struct HistoryStore: Sendable {
    public let url: URL

    public init(url: URL = HistoryStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Valet/history.json")
    }

    public func load() -> History {
        guard let data = try? Data(contentsOf: url) else { return History() }
        return (try? JSONDecoder().decode(History.self, from: data)) ?? History()
    }

    public func save(_ history: History) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // Plain numeric dates: ISO 8601 would drop the sub-second part.
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: url, options: .atomic) }
    }
}
