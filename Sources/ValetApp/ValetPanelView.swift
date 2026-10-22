import SwiftUI
import ValetCore

/// The Valet panel's content: styled like a menu, but rows can be dragged between "In the Menu Bar" and
/// "Tucked Away", and along the keepers to reorder them.
struct ValetPanelView: View {
    @Bindable var model: ValetPanelModel
    @FocusState private var focused: Bool

    static let width: CGFloat = 272
    static let space = "valet-panel"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.trusted {
                // Teaches the palette and its shortcut to people who only use the mouse.
                FooterRow(title: "Search Menu Bar…", symbol: "magnifyingglass", shortcut: model.paletteShortcut) {
                    model.onSearch?()
                }
                separator
                rows
            } else {
                onboarding
            }
            separator
            FooterRow(title: "Settings…", shortcut: "⌘,") { model.onSettings?() }
            FooterRow(title: "Quit Valet", shortcut: "⌘Q") { NSApp.terminate(nil) }
        }
        .padding(5)
        .frame(width: Self.width)
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) { dragOverlay }
        .onPreferenceChange(RowFrameKey.self) { frames in
            MainActor.assumeIsolated { model.rowFrames = frames }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.upArrow) { model.moveHighlight(by: -1); return .handled }
        .onKeyPress(.downArrow) { model.moveHighlight(by: 1); return .handled }
        .onKeyPress(.rightArrow) { model.activateHighlighted(); return .handled }
        .onKeyPress(.return) { model.activateHighlighted(); return .handled }
        .onKeyPress(.space) { model.toggleKeepHighlighted(); return .handled }
        .onKeyPress(.escape) { model.onClose?(); return .handled }
    }

    // MARK: Sections

    @ViewBuilder private var rows: some View {
        SectionHeader(title: "In the Menu Bar", hint: "Drag to reorder")
            .background(frameReader { model.keepersHeaderMaxY = $0.maxY })
        if model.keepers.isEmpty {
            PlaceholderRow(text: model.loaded ? "Drag icons here to keep them" : "Reading the menu bar…")
        }
        ForEach(model.keepers, id: \.id) { icon in iconRow(icon, draggable: true) }
        ForEach(model.fixed, id: \.id) { icon in iconRow(icon, draggable: false) }
        separator
        SectionHeader(title: "Tucked Away", hint: "Drag up to keep")
            .background(frameReader { model.tuckedHeaderMinY = $0.minY })
        if model.loaded, model.tucked.isEmpty {
            PlaceholderRow(text: "Nothing tucked away")
        }
        ForEach(model.tucked, id: \.id) { icon in iconRow(icon, draggable: true) }
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Valet needs Accessibility access").font(.system(size: 13, weight: .semibold))
            Text("It reads and presses menu bar items. Nothing else.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Open Privacy Settings…") { model.onOpenPrivacySettings?() }
                .padding(.top, 6)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
    }

    private var separator: some View {
        Divider().padding(.horizontal, 9).padding(.vertical, 5)
    }

    private func iconRow(_ icon: MenuBarIcon, draggable: Bool) -> some View {
        let lifted = model.drag?.id == icon.id
        return IconRow(
            icon: icon,
            highlighted: model.highlighted == icon.id && model.drag == nil,
            dimmed: !draggable
        )
        .opacity(lifted ? 0.25 : 1)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: RowFrameKey.self, value: [icon.id: geometry.frame(in: .named(Self.space))])
        })
        .onHover { inside in if inside { model.hover(icon.id) } }
        .gesture(pressGesture(for: icon, draggable: draggable))
        .help(draggable ? "" : "Always in the menu bar, right of Valet")
    }

    /// One gesture per row, decided on release: barely moved is a click (open), moved is a drag. A separate tap
    /// gesture would swallow the press before the drag could start.
    private func pressGesture(for icon: MenuBarIcon, draggable: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard draggable else { return }
                let moved = hypot(value.translation.width, value.translation.height)
                if model.drag?.id == icon.id || moved >= 4 { model.dragChanged(icon.id, to: value.location) }
            }
            .onEnded { _ in
                if model.drag?.id == icon.id { model.dragEnded() } else { model.onActivate?(icon) }
            }
    }

    // MARK: Drag feedback

    @ViewBuilder private var dragOverlay: some View {
        if let drag = model.drag, let icon = model.icon(drag.id) {
            ZStack(alignment: .topLeading) {
                switch drag.target {
                case .keepers(let index):
                    InsertionLine()
                        .offset(x: 12, y: model.insertionLineY(for: index, excluding: drag.id) - 1)
                case .tucked:
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.accentColor.opacity(0.12))
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                        .frame(width: Self.width - 8, height: tuckedSectionHeight)
                        .offset(x: 4, y: model.tuckedHeaderMinY)
                case nil:
                    EmptyView()
                }
                IconRow(icon: icon, highlighted: false, dimmed: false)
                    .frame(width: Self.width - 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .rotationEffect(.degrees(-1))
                    .offset(x: drag.location.x - 28, y: drag.location.y + 9)
            }
            .allowsHitTesting(false)
        }
    }

    private var tuckedSectionHeight: CGFloat {
        let bottom = model.tucked.compactMap { model.rowFrames[$0.id]?.maxY }.max() ?? model.tuckedHeaderMinY + 40
        return bottom - model.tuckedHeaderMinY + 2
    }

    private func frameReader(_ report: @escaping (CGRect) -> Void) -> some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { report(geometry.frame(in: .named(Self.space))) }
                .onChange(of: geometry.frame(in: .named(Self.space))) { _, frame in report(frame) }
        }
    }
}

// MARK: Rows

private struct IconRow: View {
    let icon: MenuBarIcon
    let highlighted: Bool
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 7) {
            if let image = AppIcons.image(for: icon) {
                Image(nsImage: image).resizable().frame(width: 16, height: 16)
            } else {
                Color.clear.frame(width: 16, height: 16)
            }
            Text(icon.name)
                .lineLimit(1)
                .foregroundStyle(highlighted ? .white : dimmed ? .secondary : .primary)
            Spacer(minLength: 8)
            if let status = icon.statusText {
                Text(status)
                    .monospacedDigit()
                    .foregroundStyle(highlighted ? .white.opacity(0.85) : .secondary)
            }
            if icon.menu != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(highlighted ? .white.opacity(0.85) : .secondary)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5).fill(highlighted ? Color.accentColor : .clear)
        )
        .contentShape(Rectangle())
    }
}

private struct SectionHeader: View {
    let title: String
    let hint: String

    var body: some View {
        HStack {
            Text(title).fontWeight(.semibold).foregroundStyle(.secondary)
            Spacer()
            Text(hint).foregroundStyle(.tertiary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}

private struct PlaceholderRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 32)
            .frame(height: 22)
    }
}

private struct FooterRow: View {
    let title: String
    var symbol: String?
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol ?? "circle")
                .font(.system(size: 12, weight: .medium))
                .opacity(symbol == nil ? 0 : 1)
                .frame(width: 16)
            Text(title)
            Spacer()
            if let shortcut {
                Text(shortcut).foregroundStyle(hovering ? .white.opacity(0.85) : .secondary)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(hovering ? .white : .primary)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}

private struct InsertionLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: ValetPanelView.width - 30, height: 2)
        }
        .offset(x: -3, y: -2.5)
    }
}

private struct RowFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
