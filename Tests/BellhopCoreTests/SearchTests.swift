import Foundation
import Testing
@testable import BellhopCore

private func index() async throws -> SearchIndex {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    return SearchIndex(icons: try await MenuBarEngine(system: system).scan(system.file.system).icons)
}

@Test func wordStartsBeatSubstringsBeatScatteredLetters() throws {
    let word = try #require(FuzzyMatch.match("Mark › Settings…", "set"))
    let inside = try #require(FuzzyMatch.match("Mark › Reset Window", "set"))
    let scattered = try #require(FuzzyMatch.match("Mark › Show Editor", "set"))
    #expect(word.score > inside.score)
    #expect(inside.score > scattered.score)
    #expect(word.hits == [7, 8, 9])
    #expect(FuzzyMatch.match("Mark › Settings…", "set zz") == nil)
}

@Test func searchFindsMenuPaths() async throws {
    let results = try await index().search("capture region")
    #expect(results.first?.candidate.path == "Mark › Capture Region")
    #expect(results.first?.candidate.kind == .item)
}

@Test func typingAnAppsNameLandsOnTheApp() async throws {
    let results = try await index().search("mark")
    #expect(results.first?.candidate.kind == .icon)
    #expect(results.first?.candidate.icon.name == "Mark")
}

@Test func destructiveAndDisabledItemsStillMatchButDisabledRankLower() async throws {
    let results = try await index().search("chatgpt")
    let paths = results.map(\.candidate.path)
    #expect(paths.contains("ChatGPT › Quit ChatGPT"))
    let disabled = try #require(results.firstIndex {
        $0.candidate.path == "ChatGPT › Computer Use › No Active Sessions"
    })
    let enabled = try #require(results.firstIndex { $0.candidate.path == "ChatGPT › Quit ChatGPT" })
    #expect(enabled < disabled)
}

@Test func privateAppsCanBeOpenedButTheirMenusArentSearched() async throws {
    let index = try await index()
    #expect(index.search("copyclip").map(\.candidate.kind) == [.icon])
    #expect(index.search("delete all history").isEmpty)
}

@Test func boostsLiftPinnedAndFrequentResults() async throws {
    let index = try await index()
    let ollama = try #require(index.candidates.first { $0.path == "Ollama › Settings" }?.key)
    let mark = try #require(index.candidates.first { $0.path == "Mark › Settings…" }?.key)
    #expect(index.search("settings", boosts: [ollama: 6]).first?.candidate.path == "Ollama › Settings")
    #expect(index.search("settings", boosts: [mark: 6]).first?.candidate.path == "Mark › Settings…")
}

@Test func historyRanksRecentUseAndPins() throws {
    var history = History()
    let now = Date(timeIntervalSince1970: 1_000_000)
    history.recordUse("a", at: now.addingTimeInterval(-86_400 * 3))
    history.recordUse("a", at: now.addingTimeInterval(-86_400 * 3))
    history.recordUse("b", at: now)
    #expect(history.recent() == ["b", "a"])
    #expect(history.frecency("b", now: now) == 1)
    #expect(history.frecency("a", now: now) == 0.5)
    history.togglePin("a")
    #expect(history.boosts(now: now)["a"] == 7)
    history.togglePin("a")
    #expect(!history.isPinned("a"))
}

@Test func historyRoundTripsAndPrunes() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("bellhop-history-\(UUID()).json")
    let store = HistoryStore(url: url)
    var history = History()
    history.recordUse("icon|com.markapp.Mark#0")
    history.recordUse("com.gone.app#0|Quit")
    history.togglePin("com.markapp.Mark#0|Settings…")
    store.save(history)
    var loaded = store.load()
    #expect(loaded == history)
    loaded.prune(keepingIconIDs: ["com.markapp.Mark#0"])
    #expect(loaded.uses.keys.sorted() == ["icon|com.markapp.Mark#0"])
    #expect(loaded.pins == ["com.markapp.Mark#0|Settings…"])
}
