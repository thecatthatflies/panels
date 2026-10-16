import SwiftUI
import AppKit

struct TopBar: View {
    @Environment(\.theme) private var theme
    private let ws = Workspace.shared
    private let appearance = Appearance.shared
    private let templates = TemplateStore.shared

    @State private var renamingID: UUID?
    @FocusState private var renameFocused: Bool
    @Namespace private var pillNamespace

    var body: some View {
        ZStack {
            WindowDragRegion()

            HStack(spacing: 4) {
                Spacer().frame(width: WindowChrome.barLeadingGap)

                ForEach(ws.spaces) { space in
                    spacePill(space)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                newSpaceMenu

                Spacer(minLength: 12)

                UpdatePill()
                    .padding(.trailing, 6)
                    .animation(.snappy(duration: 0.25), value: Updater.shared.state)

                rightCluster
            }
            .padding(.trailing, 14)
            .animation(.snappy(duration: 0.3), value: ws.spaces.map(\.id))
        }
        .frame(height: WindowChrome.barHeight)
    }

    // MARK: new workspace

    private var newSpaceMenu: some View {
        Menu {
            Section("New Workspace") {
                ForEach(templates.all) { t in
                    Button { ws.newSpace(from: t) } label: { Label(t.name, systemImage: t.symbol) }
                }
            }
            if !templates.saved.isEmpty {
                Divider()
                Menu("Delete Template") {
                    ForEach(templates.saved) { t in
                        Button(t.name, role: .destructive) { templates.remove(t.id) }
                    }
                }
            }
            Divider()
            Button { promptSaveTemplate() } label: { Label("Save Current Layout as Template...", systemImage: "square.and.arrow.down") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.mutedC)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        } primaryAction: {
            ws.newSpace()
        }
        .menuStyle(.button)
        .buttonStyle(PressStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("New workspace")
    }

    func promptSaveTemplate() {
        if let name = Prompt.text(title: "Save Layout as Template",
                                  message: "Name this layout. New workspaces can start from it.",
                                  defaultValue: ws.space.name) {
            ws.saveTemplate(named: name)
        }
    }

    // MARK: workspace pills

    @ViewBuilder
    private func spacePill(_ space: Space) -> some View {
        let active = space.id == ws.activeSpaceID
        let tint = theme.accent(space.tint)

        HStack(spacing: 7) {
            Image(systemName: space.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? tint : theme.faintC)
                .symbolEffect(.bounce, value: active)

            if renamingID == space.id {
                TextField("Name", text: Binding(get: { space.name }, set: { space.name = $0 }))
                    .textFieldStyle(.plain)
                    .font(Typo.ui(12.5, bold: true))
                    .foregroundStyle(theme.textC)
                    .focused($renameFocused)
                    .onSubmit { renamingID = nil }
                    .onExitCommand { renamingID = nil }
                    .frame(width: 92)
            } else {
                Text(space.name)
                    .font(Typo.ui(12.5, bold: active))
                    .foregroundStyle(active ? theme.textC : theme.mutedC)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background {
            if active {
                Capsule()
                    .fill(theme.raisedC)
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    .matchedGeometryEffect(id: "activePill", in: pillNamespace)
            }
        }
        .contentShape(Capsule())
        .onTapGesture(count: 2) {
            renamingID = space.id
            DispatchQueue.main.async { renameFocused = true }
        }
        .onTapGesture { ws.selectSpace(space.id) }
        .contextMenu { spaceMenu(space) }
        .animation(.snappy(duration: 0.28), value: active)
    }

    @ViewBuilder
    private func spaceMenu(_ space: Space) -> some View {
        Button("Rename") { renamingID = space.id; DispatchQueue.main.async { renameFocused = true } }
        Menu("Icon") {
            ForEach(WorkspaceSymbols.all, id: \.self) { sym in
                Button { space.symbol = sym } label: { Label(sym, systemImage: sym) }
            }
        }
        Menu("Accent") {
            ForEach(AccentID.allCases) { a in
                Button(a.label) { space.tint = a }
            }
        }
        Menu("Theme") {
            Button("Follow App") { space.themeID = nil }
            Divider()
            ForEach(Theme.all) { t in Button(t.name) { space.themeID = t.id } }
        }
        Divider()
        Button("Duplicate") { ws.duplicateSpace(space.id) }
        Button("Move Left") { ws.moveSpace(space.id, by: -1) }
        Button("Move Right") { ws.moveSpace(space.id, by: 1) }
        Divider()
        Button("New Workspace") { ws.newSpace() }
        if ws.spaces.count > 1 {
            Button("Close", role: .destructive) { ws.closeSpace(space.id) }
        }
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
                Menu("Sites") {
                    ForEach(SiteLibrary.shared.sites) { site in
                        Button { ws.openSite(site) } label: { Label(site.name, systemImage: site.symbol) }
                    }
                    Divider()
                    Button("Manage Sites...") { SettingsRouter.shared.show(.sites) }
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

            IconButton(symbol: "scope", help: "Lock in (Cmd Shift L)", size: 12, box: 24) { ws.toggleFocusMode() }

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

enum WorkspaceSymbols {
    static let all: [String] = [
        "square.grid.2x2", "house", "pencil.and.outline", "text.book.closed", "chevron.left.forwardslash.chevron.right",
        "terminal", "globe", "sun.max", "moon", "bolt", "leaf", "flame", "briefcase", "graduationcap",
        "paintbrush", "music.note", "camera", "heart", "star", "lightbulb", "brain", "flag"
    ]
}
