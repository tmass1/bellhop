import Testing
@testable import ValetCore

private func engine(
    _ customize: @escaping @Sendable (String, FakeElement, ActionLog) -> Void = { _, _, _ in }
) throws -> (MenuBarEngine, FixtureAccessibility) {
    var system = try FixtureAccessibility("macos27-laptop-overflow")
    system.customize = customize
    return (MenuBarEngine(system: system), system)
}

@Test func runPressesAnItemInAMenuReadWhileClosed() async throws {
    let (engine, system) = try engine()
    let result = try await engine.run("mark > settings", confirm: false, env: system.file.system)
    #expect(result == RunResult(path: "Mark › Settings…", openedMenu: false))
    #expect(system.log.entries == ["Settings…:AXPress"])
}

@Test func destructiveItemsWaitForConfirm() async throws {
    let (engine, system) = try engine()
    await #expect(throws: ValetError.needsConfirmation("ChatGPT › Quit ChatGPT")) {
        try await engine.run("ChatGPT › Quit ChatGPT", confirm: false, env: system.file.system)
    }
    #expect(system.log.entries.isEmpty)
    _ = try await engine.run("ChatGPT › Quit ChatGPT", confirm: true, env: system.file.system)
    #expect(system.log.entries == ["Quit ChatGPT:AXPress"])
}

@Test func disabledItemsSubmenusAndTyposAreRefused() async throws {
    let (engine, system) = try engine()
    let env = system.file.system
    await #expect(throws: ValetError.disabled("ChatGPT › Pinned")) {
        try await engine.run("ChatGPT › Pinned", confirm: false, env: env)
    }
    await #expect(throws: ValetError.submenu("ChatGPT › Computer Use")) {
        try await engine.run("ChatGPT › Computer Use", confirm: false, env: env)
    }
    do {
        _ = try await engine.run("Fritter › Close Fritter", confirm: false, env: env)
        Issue.record("expected itemNotFound")
    } catch let ValetError.itemNotFound(path, available) {
        #expect(path == "Fritter › Close Fritter")
        #expect(available == ["Open Fritter", "Quit Fritter"])
    }
    #expect(system.log.entries.isEmpty)
}

@Test func aBareIconNamePressesTheIcon() async throws {
    let (engine, system) = try engine()
    let result = try await engine.run("Burn", confirm: false, env: system.file.system)
    #expect(result.path == "Burn")
    #expect(system.log.entries == [" 52%:AXPress"])
}

/// Dev Server Manager only builds its menu when opened: pressing the icon adds an AXMenu child.
private let onDemandMenu: @Sendable (String, FakeElement, ActionLog) -> Void = { app, icon, log in
    guard app == "Dev Server Manager" else { return }
    icon.onPerform = { element, action in
        guard action == AXName.press else { return nil }
        let menu = FixtureAccessibility.menu(
            [.item("Start All"), .item("Stop All", enabled: false), .item("Quit")], log: log
        )
        menu.onPerform = { _, action in
            if action == AXName.cancel { element.values[AXName.children] = .elements([]) }
            return nil
        }
        element.values[AXName.children] = .elements([menu])
        return nil
    }
}

@Test func onDemandMenusAreOpenedReadAndClosed() async throws {
    let (engine, system) = try engine(onDemandMenu)
    let icon = try await engine.loadMenu("Dev Server Manager", env: system.file.system)
    #expect(icon.menuAvailability == .onDemand)
    #expect(icon.menu?.map(\.title) == ["Start All", "Stop All", "Quit"])
    #expect(system.log.entries == ["⚡:AXPress", "AXMenu:AXCancel"])
}

@Test func runningAnOnDemandItemOpensTheMenuFirst() async throws {
    let (engine, system) = try engine(onDemandMenu)
    let result = try await engine.run("Dev Server Manager › Start All", confirm: false, env: system.file.system)
    #expect(result == RunResult(path: "Dev Server Manager › Start All", openedMenu: true))
    #expect(system.log.entries == ["⚡:AXPress", "Start All:AXPress"])
}

@Test func refusedOnDemandItemsCloseTheMenuAgain() async throws {
    let (engine, system) = try engine(onDemandMenu)
    await #expect(throws: ValetError.disabled("Dev Server Manager › Stop All")) {
        try await engine.run("Dev Server Manager › Stop All", confirm: false, env: system.file.system)
    }
    #expect(system.log.entries == ["⚡:AXPress", "AXMenu:AXCancel"])
}

@Test func iconsThatShowNoMenuArePanelsAndGetClosedAgain() async throws {
    let (engine, system) = try engine()
    let icon = try await engine.loadMenu("Google Drive", env: system.file.system)
    #expect(icon.menuAvailability == .panel)
    #expect(system.log.entries == ["Google Drive:AXPress", "Google Drive:AXPress"])
    await #expect(throws: ValetError.panelApp("Google Drive")) {
        try await engine.run("Google Drive › Settings", confirm: false, env: system.file.system)
    }
}
