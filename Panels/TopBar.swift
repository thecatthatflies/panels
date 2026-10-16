import SwiftUI
import AppKit

struct TopBar: View {
    @Environment(\.theme) private var theme
    private let ws = Workspace.shared
    private let appearance = Appearance.shared

    @State private var renamingID: UUID?
    @FocusState private var renameFocused: Bool

    var body: some View {
        ZStack {
            WindowDragRegion()

            HStack(spacing: 6) {
                Spacer().frame(width: 86)

                ForEach(ws.spaces) { space in
                    spacePill(space)
                }

                IconButton(symbol: "plus", help: "New space (Cmd Shift N)", size: 11, box: 26) { ws.newSpace() }

                Spacer(minLength: 12)

                UpdatePill()
                    .padding(.trailing, 6)
                    .animation(.snappy(duration: 0.25), value: Updater.shared.state)

                rightCluster
            }
            .padding(.trailing, 14)
        }
        .frame(height: 46)
    }

    // MARK: spaces

    @ViewBuilder
    private func spacePill(_ space: Space) -> some View {
        let active = space.id == ws.activeSpaceID
        Group {
            if renamingID == space.id {
                TextField("Name", text: Binding(get: { space.name }, set: { space.name = $0 }))
                    .textFieldStyle(.plain)
                    .font(Typo.ui(12.5, bold: true))
                    .foregroundStyle(theme.textC)
                    .focused($renameFocused)
                    .onSubmit { renamingID = nil }
                    .onExitCommand { renamingID = nil }
                    .frame(width: 96)
            } else {
                Text(space.name)
                    .font(Typo.ui(12.5, bold: active))
                    .foregroundStyle(active ? theme.textC : theme.mutedC)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(
            Capsule().fill(active ? theme.raisedC : .clear)
        )
        .overlay(Capsule().strokeBorder(active ? theme.hairlineStrong : .clear, lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture(count: 2) {
            renamingID = space.id
            DispatchQueue.main.async { renameFocused = true }
        }
        .onTapGesture { ws.selectSpace(space.id) }
        .contextMenu {
            Button("Rename") { renamingID = space.id; DispatchQueue.main.async { renameFocused = true } }
            Button("New Space") { ws.newSpace() }
            if ws.spaces.count > 1 {
                Divider()
                Button("Close Space", role: .destructive) { ws.closeSpace(space.id) }
            }
        }
        .animation(.snappy(duration: 0.2), value: active)
    }

    // MARK: right side

    private var rightCluster: some View {
        HStack(spacing: 2) {
            IconMenu(symbol: "rectangle.3.group", help: "Layouts") {
                ForEach(LayoutPreset.allCases) { preset in
                    Button { ws.apply(preset) } label: { Label(preset.label, systemImage: preset.symbol) }
                }
                Divider()
                Button { ws.equalize() } label: { Label("Even Out Sizes", systemImage: "equal.square") }
            }

            IconMenu(symbol: "plus.square.on.square", help: "Add a panel") {
                ForEach(PanelKind.allCases) { kind in
                    Button { ws.addPanel(kind) } label: { Label(kind.label, systemImage: kind.symbol) }
                }
                Divider()
                Menu("Web Apps") {
                    ForEach(WebPreset.all) { preset in
                        Button { ws.addPanel(.web, url: preset.url, title: preset.name) } label: {
                            Label(preset.name, systemImage: preset.symbol)
                        }
                    }
                }
            }

            IconMenu(symbol: "circle.lefthalf.filled", help: "Theme") {
                ForEach(ThemeChoice.allCases) { choice in
                    Button {
                        withAnimation(.snappy(duration: 0.3)) { appearance.choice = choice }
                    } label: {
                        if appearance.choice == choice { Label(choice.label, systemImage: "checkmark") }
                        else { Text(choice.label) }
                    }
                }
            }

            Button { ws.paletteOpen = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                    Text("Search").font(Typo.ui(12))
                    KeyCap(text: "Cmd K")
                }
                .foregroundStyle(theme.mutedC)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .padding(.leading, 4)
        }
        .padding(.horizontal, 5)
        .frame(height: 32)
        .glassEffect(.regular, in: Capsule())
    }
}
