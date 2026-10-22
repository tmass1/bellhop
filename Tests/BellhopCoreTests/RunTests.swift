import CoreGraphics
import Testing
@testable import BellhopCore

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
    await #expect(throws: BellhopError.needsConfirmation("ChatGPT › Quit ChatGPT")) {
        try await engine.run("ChatGPT › Quit ChatGPT", confirm: false, env: system.file.system)
    }
    #expect(system.log.entries.isEmpty)
    _ = try await engine.run("ChatGPT › Quit ChatGPT", confirm: true, env: system.file.system)
    #expect(system.log.entries == ["Quit ChatGPT:AXPress"])
}

@Test func disabledItemsSubmenusAndTyposAreRefused() async throws {
    let (engine, system) = try engine()
    let env = system.file.system
    await #expect(throws: BellhopError.disabled("ChatGPT › Pinned")) {
        try await engine.run("ChatGPT › Pinned", confirm: false, env: env)
    }
    await #expect(throws: BellhopError.submenu("ChatGPT › Computer Use")) {
        try await engine.run("ChatGPT › Computer Use", confirm: false, env: env)
    }
    do {
        _ = try await engine.run("Fritter › Close Fritter", confirm: false, env: env)
        Issue.record("expected itemNotFound")
    } catch let BellhopError.itemNotFound(path, available) {
        #expect(path == "Fritter › Close Fritter")
        #expect(available == ["Open Fritter", "Quit Fritter"])
    }
    #expect(system.log.entries.isEmpty)
}

@Test func aBareIconNamePressesTheIcon() async throws {
    let (engine, system) = try engine()
    let result = try await engine.run("Burn", confirm: false, env: system.file.system)
    #expect(result.path == "Burn")
    // The fake logs the raw fixture title; Bellhop trims it to "52%" for display.
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
    await #expect(throws: BellhopError.disabled("Dev Server Manager › Stop All")) {
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
    await #expect(throws: BellhopError.panelApp("Google Drive")) {
        try await engine.run("Google Drive › Settings", confirm: false, env: system.file.system)
    }
}

@Test func iconsThatIgnoreThePressArentPressedAgain() async throws {
    let (engine, system) = try engine()
    let icon = try await engine.loadMenu("Claude", env: system.file.system)
    #expect(icon.menuAvailability == .noResponse)
    // Claude's icon has no title or description, so the fake logs its role.
    #expect(system.log.entries == ["AXMenuBarItem:AXPress"])
    await #expect(throws: BellhopError.noResponse("Claude")) {
        try await engine.run("Claude › Settings", confirm: false, env: system.file.system)
    }
}

/// Google Drive as a real panel app: pressing opens a 420 pt panel at x 777 (where the tucked icon is), pressing
/// again closes it.
private let drivePanel: FixtureAccessibility.Customize = { app, icon, appElement, log in
    guard app == "Google Drive" else { return }
    icon.onPerform = { _, action in
        guard action == AXName.press else { return nil }
        let open = appElement.values[AXName.windows]?.elements.isEmpty == false
        let panel = FakeElement([
            AXName.role: .string("AXWindow"), AXName.subrole: .string(AXName.systemDialogSubrole),
            AXName.position: .point(CGPoint(x: 777, y: 33)), AXName.size: .size(CGSize(width: 420, height: 439)),
        ], log: log)
        appElement.values[AXName.windows] = .elements(open ? [] : [panel])
        return nil
    }
}

@Test func panelsOpenedForKeepersMoveUnderThem() async throws {
    let (engine, system) = try engine(drivePanel)
    let env = system.file.system
    let icon = try await engine.open("Google Drive", alignTo: 1236, screenMaxX: 1728, env: env)
    #expect(icon.menuAvailability == .panel)
    #expect(system.log.entries.last == "AXWindow:setPosition(1236,33)")
}

@Test func movedPanelsStayOnScreen() async throws {
    let (engine, system) = try engine(drivePanel)
    _ = try await engine.open("Google Drive", alignTo: 1500, screenMaxX: 1728, env: system.file.system)
    // 1728 − 420 − 8 = 1300.
    #expect(system.log.entries.last == "AXWindow:setPosition(1300,33)")
}

@Test func menusReadOnDemandAreRememberedAcrossScans() async throws {
    let (engine, system) = try engine(onDemandMenu)
    let env = system.file.system
    let first = try await engine.open("Dev Server Manager", alignTo: 1236, screenMaxX: 1728, env: env)
    #expect(first.menu?.map(\.title) == ["Start All", "Stop All", "Quit"])
    let pressesAfterReading = system.log.entries.count
    let rescanned = try await engine.scan(env).icons.first { $0.name == "Dev Server Manager" }
    #expect(rescanned?.menu?.count == 3)
    _ = try await engine.open("Dev Server Manager", alignTo: 1236, screenMaxX: 1728, env: env)
    #expect(system.log.entries.count == pressesAfterReading)
}

@Test func clickingAKeeperAgainClosesItsPanel() async throws {
    let (engine, system) = try engine(drivePanel)
    let env = system.file.system
    _ = try await engine.open("Google Drive", alignTo: 1236, screenMaxX: 1728, env: env)
    let closed = try await engine.open("Google Drive", alignTo: 1236, screenMaxX: 1728, env: env)
    #expect(closed.menuAvailability == .panel)
    #expect(system.log.entries.filter { $0.hasSuffix("AXPress") }.count == 2)
}
