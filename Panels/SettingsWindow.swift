import SwiftUI
import AppKit

struct SettingsView: View {
    private let appearance = Appearance.shared
    private let router = SettingsRouter.shared

    var body: some View {
        let theme = appearance.theme
        @Bindable var r = router

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(Typo.ui(15, bold: true))
                    .foregroundStyle(theme.textC)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                ForEach(SettingsRouter.Tab.allCases) { tab in
                    let on = r.tab == tab
                    Button { withAnimation(.snappy(duration: 0.22)) { r.tab = tab } } label: {
                        HStack(spacing: 9) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 18)
                                .foregroundStyle(on ? theme.accentC : theme.mutedC)
                            Text(tab.label).font(Typo.ui(13, bold: on))
                                .foregroundStyle(on ? theme.textC : theme.mutedC)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? theme.hover : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
                Spacer()
            }
            .padding(14)
            .frame(width: 178)
            .background(theme.windowC.opacity(0.5))

            Rectangle().fill(theme.hairline).frame(width: 1)

            Group {
                switch r.tab {
                case .general: GeneralSettings()
                case .themes: ThemesSettings()
                case .writing: WritingSettings()
                case .about: AboutSettingsView()
                case .dictation: DictationSettingsView()
                case .sound: SoundSettingsView()
                case .sites: SitesSettings()
                case .updates: ScrollView { UpdateSettingsSection().padding(26) }
                case .shortcuts: ShortcutsSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .frame(minWidth: 780, idealWidth: 860, maxWidth: .infinity, minHeight: 560, idealHeight: 620, maxHeight: .infinity)
        .background(theme.surfaceC)
        .background(SettingsWindowSizer())
        .environment(\.theme, theme)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Environment(\.theme) private var theme
    private let appearance = Appearance.shared
    private let ws = Workspace.shared

    var body: some View {
        @Bindable var a = appearance
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Appearance")
                    .font(Typo.ui(20, bold: true))
                    .foregroundStyle(theme.textC)

                SettingsSection(title: "Theme") {
                    FlowLayout(spacing: 8) {
                        ForEach(["auto"] + appearance.allThemes.map(\.id), id: \.self) { id in
                            let name = id == "auto" ? "Auto" : (appearance.allThemes.first { $0.id == id }?.name ?? id)
                            let on = appearance.isSelected(themeID: id)
                            Button { withAnimation(.snappy(duration: 0.3)) { appearance.select(themeID: id) } } label: {
                                Text(name)
                                    .font(Typo.ui(12, bold: on))
                                    .foregroundStyle(on ? theme.textC : theme.mutedC)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Capsule().fill(on ? theme.accentC.opacity(0.18) : theme.hover))
                                    .overlay(Capsule().strokeBorder(on ? theme.accentC.opacity(0.6) : .clear, lineWidth: 1))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    Button { SettingsRouter.shared.show(.themes) } label: { Label("Edit Themes...", systemImage: "paintpalette") }
                }

                SettingsSection(title: "Density") {
                    SegmentedChips(options: Appearance.Density.allCases,
                                   selection: Binding(get: { appearance.density }, set: { d in withAnimation(Motion.layout) { appearance.apply(density: d) } }),
                                   label: { $0.label })
                    Text("Sets the gap between panels, corner radius and header height in one go. Fine tune them below.")
                        .font(Typo.ui(11.5)).foregroundStyle(theme.faintC)
                }

                SettingsSection(title: "Window") {
                    SliderRow(label: "Translucency", value: $a.translucency, range: 0.5...1, step: 0.01,
                              format: { String(format: "%.0f%%", $0 * 100) })
                    SliderRow(label: "Panel gap", value: $a.gap, range: 2...20, step: 1,
                              format: { String(format: "%.0f pt", $0) })
                    SliderRow(label: "Corner radius", value: $a.cornerRadius, range: 0...28, step: 1,
                              format: { String(format: "%.0f pt", $0) })
                    ToggleRow(label: "Float above other windows", isOn: Binding(get: { ws.floating }, set: { ws.setFloating($0) }))
                }

                SettingsSection(title: "Data") {
                    HStack(spacing: 8) {
                        Button { FileOps.revealDataFolder() } label: { Label("Show Data in Finder", systemImage: "folder") }
                    }
                    Text("Workspaces, notes, sites and templates are stored as plain JSON in Application Support.")
                        .font(Typo.ui(11.5)).foregroundStyle(theme.faintC)
                }
            }
            .padding(28)
        }
    }
}

// MARK: - Sites

struct SitesSettings: View {
    @Environment(\.theme) private var theme
    private let library = SiteLibrary.shared
    private let router = SettingsRouter.shared

    var body: some View {
        @Bindable var r = router
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Sites").font(Typo.ui(15, bold: true)).foregroundStyle(theme.textC)
                    Spacer()
                    IconButton(symbol: "plus", help: "Add a site", size: 12, box: 26) {
                        let s = library.add()
                        withAnimation(.snappy) { r.selectedSite = s.id }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(library.sites) { site in
                            let on = r.selectedSite == site.id
                            HStack(spacing: 10) {
                                Image(systemName: site.symbol)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(on ? theme.accentC : theme.mutedC)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(site.name).font(Typo.ui(13, bold: true)).foregroundStyle(theme.textC).lineLimit(1)
                                    Text(site.url.replacingOccurrences(of: "https://", with: ""))
                                        .font(Typo.ui(11)).foregroundStyle(theme.faintC).lineLimit(1)
                                }
                                Spacer()
                                if site.settings.appMode {
                                    Image(systemName: "macwindow").font(.system(size: 10)).foregroundStyle(theme.faintC)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? theme.hover : .clear))
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(.snappy(duration: 0.2)) { r.selectedSite = site.id } }
                            .contextMenu {
                                Button("Open as Panel") { Workspace.shared.openSite(site) }
                                Button("Duplicate") { _ = library.duplicate(site.id) }
                                Button("Move Up") { library.move(site.id, by: -1) }
                                Button("Move Down") { library.move(site.id, by: 1) }
                                Divider()
                                Button("Delete", role: .destructive) { library.remove(site.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(width: 250)

            Rectangle().fill(theme.hairline).frame(width: 1)

            Group {
                if let id = r.selectedSite, library.index(of: id) != nil {
                    SiteEditor(site: Binding(
                        get: { library.sites.first { $0.id == id } ?? Site(name: "", url: "") },
                        set: { new in if let i = library.index(of: id) { library.sites[i] = new } }
                    ))
                    .id(id)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "globe").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(theme.faintC)
                        Text("Pick a site to edit").font(Typo.ui(13)).foregroundStyle(theme.mutedC)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { if r.selectedSite == nil { r.selectedSite = library.sites.first?.id } }
    }
}

// MARK: - Shortcuts

struct ShortcutsSettings: View {
    @Environment(\.theme) private var theme

    private let groups: [(String, [(String, String)])] = [
        ("Panels", [
            ("Command palette", "Cmd K"), ("New note", "Cmd N"), ("New terminal", "Cmd T"), ("New web panel", "Cmd Shift B"),
            ("Split right", "Cmd D"), ("Split down", "Cmd Shift D"), ("Duplicate", "Cmd Option D"),
            ("Close panel", "Cmd W"), ("Zoom panel", "Cmd Shift Return"), ("Panel settings", "Cmd Option I"),
            ("Rename panel", "Cmd Shift R"), ("Next or previous panel", "Cmd ] and Cmd ["),
            ("Focus by direction", "Cmd Option Arrows"), ("Even out sizes", "Cmd Option =")
        ]),
        ("Workspaces", [
            ("Go to workspace 1 to 9", "Cmd 1 to 9"), ("New workspace", "Cmd Shift N"), ("Close workspace", "Cmd Shift W"),
            ("Previous or next", "Ctrl Cmd [ and ]")
        ]),
        ("Writing", [
            ("Lock in", "Cmd Shift L"), ("Bold", "Cmd B"), ("Italic", "Cmd I"), ("Inline code", "Cmd E"),
            ("Dictate", "Cmd Shift M"), ("Link", "Cmd Shift K"), ("Open wiki link", "Cmd click"), ("Find", "Cmd F"), ("Find and replace", "Cmd Option F"),
            ("Find next or previous", "Cmd G and Cmd Shift G"), ("Bigger, smaller, actual size", "Cmd + and Cmd - and Cmd 0"), ("Save as markdown", "Cmd S")
        ]),
        ("Web", [
            ("Go to address", "Cmd L"), ("Reload", "Cmd R"), ("Back and forward", "Ctrl Option Cmd [ and ]")
        ])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Shortcuts").font(Typo.ui(20, bold: true)).foregroundStyle(theme.textC)
                ForEach(groups, id: \.0) { group in
                    SettingsSection(title: group.0) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.1.enumerated()), id: \.offset) { i, row in
                                HStack {
                                    Text(row.0).font(Typo.ui(13)).foregroundStyle(theme.textC)
                                    Spacer()
                                    KeyCap(text: row.1)
                                }
                                .padding(.vertical, 7)
                                if i < group.1.count - 1 { Rectangle().fill(theme.hairline).frame(height: 1) }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}


/// Settings windows restore their last frame; make sure an old, smaller frame never clips the content.
struct SettingsWindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.contentMinSize = NSSize(width: 780, height: 560)
            let size = w.contentLayoutRect.size
            if size.width < 860 || size.height < 620 {
                w.setContentSize(NSSize(width: max(size.width, 860), height: max(size.height, 620)))
                w.center()
            }
        }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {}
}
