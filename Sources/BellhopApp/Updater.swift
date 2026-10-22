import AppKit
import os
import Sparkle

/// Bellhop keeps itself up to date with Sparkle. It reads the appcast attached to the latest GitHub release and
/// installs only an archive signed with Bellhop's EdDSA key (the public half is `SUPublicEDKey` in Info.plist; the
/// private half lives in the login keychain of the Mac that releases). Sparkle also refuses a new copy whose code
/// signature doesn't match this one. It checks shortly after launch and once a day; Settings can turn that off.
///
/// Bellhop is usually in the background, so a scheduled check that finds something doesn't throw Sparkle's window
/// over your work: the Bellhop panel's footer offers the update instead, and choosing it opens that window.
@MainActor
@Observable
final class Updater: NSObject {
    /// A version a scheduled check found that hasn't been looked at yet.
    private(set) var available: String?
    /// Mirrors Sparkle's setting so the Settings switch redraws when it changes.
    private(set) var checksAutomatically = true
    /// Called when `available` changes.
    @ObservationIgnored var onAvailableChange: ((String?) -> Void)?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private let log = Logger(subsystem: "com.tommymassaro.bellhop", category: "update")

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }

    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: self
        )
        checksAutomatically = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    /// Check for Updates…: always answers with a window: the update, "You're up to date", or what went wrong.
    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    var lastChecked: Date? { controller?.updater.lastUpdateCheckDate }

    func setChecksAutomatically(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
        checksAutomatically = enabled
    }

    private func setAvailable(_ version: String?) {
        available = version
        onAvailableChange?(version)
    }
}

extension Updater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        log.notice("found \(item.displayVersionString, privacy: .public) (\(item.versionString, privacy: .public))")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // "No update" arrives here too (SUNoUpdateError, 1001); only real failures are worth a log line.
        guard (error as NSError).code != 1001 else { return }
        log.error("\(error.localizedDescription, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        log.notice("installing \(item.displayVersionString, privacy: .public)")
    }
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle's window only when Bellhop is the active app. It usually starts at login in the background, where the
    /// window would open behind everything else; then the panel's footer offers the update.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus && NSApp.isActive
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        setAvailable(update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        setAvailable(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        setAvailable(nil)
    }
}
