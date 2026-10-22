import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Bellhop's settings: the palette shortcut, appearance, Open at Login and updates, plus a plain word on privacy.
struct SettingsView: View {
    let updater: Updater
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var appearance = Appearance.current

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open the palette:", name: .togglePalette)
                Picker("Appearance:", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _, chosen in Appearance.apply(chosen) }
                Toggle("Open Bellhop at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in setOpensAtLogin(enabled) }
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.checksAutomatically }, set: { updater.setChecksAutomatically($0) }
                ))
                LabeledContent("Bellhop \(Updater.version)") {
                    Button("Check Now") { updater.checkForUpdates() }
                }
            }
            Section("Privacy") {
                Text("Bellhop reads and presses menu bar items using Accessibility. It never records your screen, "
                    + "and nothing you search or run leaves this Mac. "
                    + "The only thing it fetches is the update list from GitHub, once a day.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            opensAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

@MainActor
final class SettingsWindow {
    private let updater: Updater
    private var window: NSWindow?

    init(updater: Updater) {
        self.updater = updater
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(updater: updater)))
            window.title = "Bellhop Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
