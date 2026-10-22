// Exports installed apps' icons for the mocks to design/mocks/icons/<bundle id>.png (128 px).
// The folder is git-ignored: third-party icons stay on this Mac. Missing apps fall back to monogram tiles.
//   swift design/mocks/extract-icons.swift
import AppKit

let bundleIDs = [
    "com.tommymassaro.burn", "com.tommymassaro.dev-server-manager", "com.adobe.acc.AdobeCreativeCloud",
    "com.electron.ollama", "com.openai.codex", "com.privateinternetaccess.vpn", "com.tommymassaro.tidy",
    "com.getdropbox.dropbox", "com.anthropic.claudefordesktop", "com.google.drivefs", "com.apple.Passwords",
    "com.markapp.Mark", "com.fiplab.clipboard", "com.google.Chrome", "com.fritter.app", "com.canon.EOS-Utility",
    "com.meta.endo", "com.apple.finder", "com.apple.systempreferences",
]
let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("icons")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for id in bundleIDs {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
        print("missing \(id)")
        continue
    }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    let size = NSSize(width: 128, height: 128)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(id).png"))
    print("ok \(id)")
}
