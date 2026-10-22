import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Valet's settings: the palette shortcut and Open at Login, plus a plain word on privacy.
struct SettingsView: View {
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
                Toggle("Open Valet at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in setOpensAtLogin(enabled) }
            }
            Section("Privacy") {
                Text("Valet reads and presses menu bar items using Accessibility. It never records your screen, "
                    + "and nothing you search or run leaves this Mac.")
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
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Valet Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
