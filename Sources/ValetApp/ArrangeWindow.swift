import AppKit
import SwiftUI
import ValetCore

/// Arrange Menu Bar…: drag icons between "In your menu bar" (kept, as keepers) and "Tucked away", and along the
/// bar to reorder. Every change applies right away.
@MainActor
@Observable
final class ArrangeModel {
    var kept: [String] = []
    /// Icons that can be kept: everything tucked, plus what's already kept. Left to right in the real bar.
    var candidates: [MenuBarIcon] = []
    /// Icons right of Valet, which are always in the bar. Shown for context only.
    var alwaysInBar: [String] = []
    @ObservationIgnored var onChange: (([String]) -> Void)?

    var keptIcons: [MenuBarIcon] { kept.compactMap { id in candidates.first { $0.id == id } } }
    var tuckedIcons: [MenuBarIcon] { candidates.filter { !kept.contains($0.id) } }

    func update(snapshot: MenuBarSnapshot, kept: [String]) {
        let sections = MenuBarSections(snapshot)
        candidates = sections.tucked + sections.inBar.filter { kept.contains($0.id) }
        alwaysInBar = sections.inBar.filter { !kept.contains($0.id) }.map(\.name)
        self.kept = kept
    }

    func keep(_ id: String, before target: String? = nil) {
        var next = kept.filter { $0 != id }
        let index = target.flatMap { next.firstIndex(of: $0) } ?? next.count
        next.insert(id, at: index)
        apply(next)
    }

    func tuck(_ id: String) {
        apply(kept.filter { $0 != id })
    }

    func toggle(_ id: String) {
        if kept.contains(id) { tuck(id) } else { keep(id) }
    }

    private func apply(_ next: [String]) {
        guard next != kept else { return }
        kept = next
        onChange?(next)
    }
}

struct ArrangeView: View {
    @Bindable var model: ArrangeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose what stays in the menu bar")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 6)

            zoneLabel("In your menu bar", detail: "\(model.kept.count) kept · drag to reorder")
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if model.keptIcons.isEmpty {
                            Text("Drag icons here to keep them in the menu bar.")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                        }
                        ForEach(model.keptIcons, id: \.id) { icon in
                            KeptTile(icon: icon)
                                .draggable(icon.id)
                                .dropDestination(for: String.self) { ids, _ in
                                    ids.first.map { model.keep($0, before: icon.id) }
                                    return true
                                }
                                .onTapGesture { model.tuck(icon.id) }
                        }
                    }
                    .padding(8)
                }
                Text(alwaysInBarCaption)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.trailing, 10)
            }
            .frame(minHeight: 52)
            .background(.bar, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
            .dropDestination(for: String.self) { ids, _ in
                ids.first.map { model.keep($0) }
                return true
            }
            .padding(.bottom, 10)

            zoneLabel("Tucked away", detail: "\(model.tuckedIcons.count) · in the Valet menu")
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 4)], spacing: 4) {
                    ForEach(model.tuckedIcons, id: \.id) { icon in
                        TuckedTile(icon: icon)
                            .draggable(icon.id)
                            .onTapGesture { model.keep(icon.id) }
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 150, maxHeight: 280)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .dropDestination(for: String.self) { ids, _ in
                ids.first.map { model.tuck($0) }
                return true
            }

            Text("Kept icons are Valet’s own items, so they can go in any order. The real icons stay tucked.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 660)
    }

    private var alwaysInBarCaption: String {
        model.alwaysInBar.isEmpty ? "Then Valet" : "Then Valet, \(model.alwaysInBar.joined(separator: ", "))"
    }

    private func zoneLabel(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).fontWeight(.semibold)
            Spacer()
            Text(detail)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }
}

private struct KeptTile: View {
    let icon: MenuBarIcon

    var body: some View {
        HStack(spacing: 6) {
            AppIconView(icon: icon, size: 16)
            Text(icon.name).lineLimit(1)
            if let status = icon.statusText {
                Text(status).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
        .contentShape(Rectangle())
        .help("Drag down, or click, to tuck \(icon.name) away")
    }
}

private struct TuckedTile: View {
    let icon: MenuBarIcon

    var body: some View {
        VStack(spacing: 4) {
            AppIconView(icon: icon, size: 28)
            Text(icon.name).font(.caption).lineLimit(1).truncationMode(.tail)
            Text(icon.statusText ?? " ").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .help("Drag up, or click, to keep \(icon.name) in the menu bar")
    }
}

private struct AppIconView: View {
    let icon: MenuBarIcon
    let size: CGFloat

    var body: some View {
        if let image = AppIcons.image(for: icon) {
            Image(nsImage: image).resizable().frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size / 4).fill(.quaternary).frame(width: size, height: size)
        }
    }
}

/// The window that hosts `ArrangeView`. Valet is a menu bar app, so it activates itself to bring this forward.
@MainActor
final class ArrangeWindow {
    let model = ArrangeModel()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ArrangeView(model: model)))
            window.title = "Arrange Menu Bar"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
