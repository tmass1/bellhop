import Testing
@testable import ValetCore

private func engine(
    _ customize: @escaping FixtureAccessibility.Customize = { _, _, _, _ in }
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
    // The fake logs the raw fixture title; Valet trims it to "52%" for display.
    #expect(system.log.entries == [" 52%:AXPress"])
}

/// Dev Server Manager only builds its menu when opened: pressing the icon adds an AXMenu child.
private let onDemandMenu: FixtureAccessibility.Customize = { app, icon, _, log in
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

/// Google Drive opens a panel: pressing its icon adds a window to the app, and pressing again removes it.
private let panelApp: FixtureAccessibility.Customize = { app, icon, appElement, log in
    guard app == "Google Drive" else { return }
    icon.onPerform = { _, action in
        guard action == AXName.press else { return nil }
        let open = appElement.values[AXName.windows]?.elements.isEmpty == false
        appElement.values[AXName.windows] = .elements(open ? [] : [FakeElement([:], log: log)])
        return nil
    }
}

@Test func iconsThatOpenAWindowArePanelsAndGetClosedRightAway() async throws {
    let (engine, system) = try engine(panelApp)
    let clock = ContinuousClock()
    let start = clock.now
    let icon = try await engine.loadMenu("Google Drive", env: system.file.system)
    #expect(clock.now - start < .milliseconds(400))
    #expect(icon.menuAvailability == .panel)
    #expect(system.log.entries == ["Google Drive:AXPress", "Google Drive:AXPress"])
    await #expect(throws: ValetError.panelApp("Google Drive")) {
        try await engine.run("Google Drive › Settings", confirm: false, env: system.file.system)
    }
}

@Test func iconsThatIgnoreThePressArentPressedAgain() async throws {
    let (engine, system) = try engine()
    let icon = try await engine.loadMenu("Claude", env: system.file.system)
    #expect(icon.menuAvailability == .noResponse)
    // Claude's icon has no title or description, so the fake logs its role.
    #expect(system.log.entries == ["AXMenuBarItem:AXPress"])
    await #expect(throws: ValetError.noResponse("Claude")) {
        try await engine.run("Claude › Settings", confirm: false, env: system.file.system)
    }
}
