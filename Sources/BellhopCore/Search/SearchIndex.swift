import Foundation

/// Fuzzy search over menu bar icons and the items in their mirrored menus, as the palette and `bellhop search` use it.
public struct SearchIndex: Sendable {
    public enum Kind: String, Sendable { case icon, item }

    /// One thing the palette can run: an icon, or an item in its menu.
    public struct Candidate: Sendable, Equatable {
        public var kind: Kind
        public var icon: MenuBarIcon
        /// Menu titles below the icon, empty for the icon itself.
        public var titles: [String]
        public var entry: MenuEntry?
        /// What's matched against: "Dropbox › Snooze Notifications › For the next hour".
        public var text: String
        /// Stable key for history: "icon|<icon id>" or "<icon id>|<titles joined by ›>".
        public var key: String

        public var path: String { MenuPaths.join([icon.name] + titles) }

        public static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    }

    public struct Result: Sendable {
        public var candidate: Candidate
        public var score: Double
        /// Character offsets into `candidate.text` that matched, for bold highlighting.
        public var hits: Set<Int>
    }

    /// Apps whose menus aren't indexed by default: their menus are history (CopyClip's is your clipboard).
    /// They can still be opened by name.
    public static let privateByDefault: Set<String> = ["com.fiplab.clipboard"]

    public private(set) var candidates: [Candidate] = []
    private let excluded: Set<String>

    public init(icons: [MenuBarIcon], excluded: Set<String> = SearchIndex.privateByDefault) {
        self.excluded = excluded
        for icon in icons {
            candidates.append(Candidate(
                kind: .icon, icon: icon, titles: [], entry: nil, text: icon.name, key: Self.iconKey(icon.id)
            ))
            guard !isPrivate(icon) else { continue }
            for (titles, entry) in MenuPaths.entries(for: icon) {
                candidates.append(Candidate(
                    kind: .item, icon: icon, titles: titles, entry: entry,
                    text: MenuPaths.join([icon.name] + titles), key: Self.itemKey(icon.id, titles)
                ))
            }
        }
    }

    public func isPrivate(_ icon: MenuBarIcon) -> Bool {
        icon.app.bundleID.map(excluded.contains) ?? false
    }

    public static func iconKey(_ id: String) -> String { "icon|\(id)" }
    public static func itemKey(_ id: String, _ titles: [String]) -> String { "\(id)|\(MenuPaths.join(titles))" }

    public func candidate(forKey key: String) -> Candidate? {
        candidates.first { $0.key == key }
    }

    /// Ranked matches. `boosts` (by key) lifts pinned and frequently used results.
    public func search(_ query: String, boosts: [String: Double] = [:], limit: Int = 40) -> [Result] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()
        var results: [Result] = []
        for candidate in candidates {
            guard let match = FuzzyMatch.match(candidate.text, query) else { continue }
            var score = match.score + (boosts[candidate.key] ?? 0)
            switch candidate.kind {
            case .icon:
                // Typing an app's name lands on the app, ahead of its pinned or recent items.
                score += candidate.icon.name.lowercased().hasPrefix(lowered) ? 20 : 2
            case .item:
                if candidate.entry?.enabled == false { score -= 4 }
            }
            results.append(Result(candidate: candidate, score: score, hits: match.hits))
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }
}

/// Every typed word must appear: word starts beat substrings, which beat scattered letters.
public enum FuzzyMatch {
    public static func match(_ text: String, _ query: String) -> (score: Double, hits: Set<Int>)? {
        let chars = Array(text.lowercased())
        var hits = Set<Int>()
        var score = 0.0
        for token in query.lowercased().split(whereSeparator: \.isWhitespace).map(Array.init) {
            if let start = wordStart(token, in: chars) {
                score += 3 * Double(token.count)
                hits.formUnion(start..<(start + token.count))
            } else if let start = substring(token, in: chars) {
                score += 2 * Double(token.count)
                hits.formUnion(start..<(start + token.count))
            } else if let scattered = subsequence(token, in: chars) {
                score += 0.6 * Double(token.count)
                hits.formUnion(scattered)
            } else {
                return nil
            }
        }
        return (score, hits)
    }

    private static func substring(_ token: [Character], in chars: [Character], wordStartOnly: Bool = false) -> Int? {
        guard !token.isEmpty, token.count <= chars.count else { return nil }
        for start in 0...(chars.count - token.count) where Array(chars[start..<(start + token.count)]) == token {
            if !wordStartOnly || start == 0 || isBoundary(chars[start - 1]) { return start }
        }
        return nil
    }

    private static func wordStart(_ token: [Character], in chars: [Character]) -> Int? {
        substring(token, in: chars, wordStartOnly: true)
    }

    private static func isBoundary(_ char: Character) -> Bool {
        char.isWhitespace || "›(·-–—/".contains(char)
    }

    private static func subsequence(_ token: [Character], in chars: [Character]) -> [Int]? {
        var found: [Int] = []
        var from = 0
        for char in token {
            guard let index = chars[from...].firstIndex(of: char) else { return nil }
            found.append(index)
            from = index + 1
        }
        return found
    }
}
