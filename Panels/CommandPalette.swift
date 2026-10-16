import SwiftUI
import AppKit

struct PaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let keywords: String
    let shortcut: String?
    let action: () -> Void
}

struct CommandPalette: View {
    @Environment(\.theme) private var theme
    private let ws = Workspace.shared
    private let appearance = Appearance.shared

    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    private func close() {
        withAnimation(.snappy(duration: 0.2)) { ws.paletteOpen = false }
        restoreFocus()
    }

    private func restoreFocus() {
        guard let id = ws.space.focusedID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Runtime.shared.makeFirstResponder(for: id) }
    }

    private var items: [PaletteItem] {
        var out: [PaletteItem] = []

        for kind in PanelKind.allCases {
            out.append(PaletteItem(id: "new-\(kind.rawValue)", title: "New \(kind.label)", subtitle: kind.blurb,
                                   symbol: kind.symbol, keywords: "add create panel \(kind.rawValue)",
                                   shortcut: kind == .note ? "Cmd N" : (kind == .terminal ? "Cmd T" : nil)) { ws.addPanel(kind) })
        }
        for site in SiteLibrary.shared.sites {
            out.append(PaletteItem(id: "site-\(site.id)", title: "Open \(site.name)", subtitle: site.url,
                                   symbol: site.symbol, keywords: "web app browser site open", shortcut: nil) {
                ws.openSite(site)
            })
        }
        out.append(PaletteItem(id: "add-site", title: "Add Website...", subtitle: "Save a site to your library",
                               symbol: "plus.circle", keywords: "new site bookmark web app", shortcut: nil) {
            SettingsRouter.shared.show(.sites, site: SiteLibrary.shared.add().id)
        })
        out.append(PaletteItem(id: "lock-in", title: ws.focusMode ? "Leave Lock In" : "Lock In", subtitle: "Hide everything but the work",
                               symbol: "scope", keywords: "focus zen distraction typewriter", shortcut: "Cmd Shift L") { ws.toggleFocusMode() })
        if let f = ws.focused {
            out.append(PaletteItem(id: "split-right", title: "Split Right", subtitle: "Add a note beside \(f.title)",
                                   symbol: "rectangle.split.2x1", keywords: "divide horizontal", shortcut: "Cmd D") {
                ws.split(f.id, axis: .horizontal, kind: .note)
            })
            out.append(PaletteItem(id: "split-down", title: "Split Down", subtitle: "Add a note below \(f.title)",
                                   symbol: "rectangle.split.1x2", keywords: "divide vertical", shortcut: "Cmd Shift D") {
                ws.split(f.id, axis: .vertical, kind: .note)
            })
            out.append(PaletteItem(id: "zoom", title: "Zoom Panel", subtitle: "Fill the window with \(f.title)",
                                   symbol: "arrow.up.left.and.arrow.down.right", keywords: "maximize fullscreen focus", shortcut: "Cmd Shift Return") {
                ws.toggleZoom(f.id)
            })
            if f.kind == .note || f.kind == .terminal {
                out.append(PaletteItem(id: "dictate", title: DictationController.shared.isActive ? "Stop Dictation" : "Dictate",
                                       subtitle: "Speak into \(f.title)", symbol: "mic", keywords: "voice speech talk transcribe",
                                       shortcut: "Cmd Shift M") { DictationController.shared.toggle(for: f) })
            }
            out.append(PaletteItem(id: "popout", title: "Pop Out into Window", subtitle: "Float \(f.title) above everything",
                                   symbol: "arrow.up.forward.square", keywords: "detach pin float separate window", shortcut: "Cmd Option O") { ws.popOut(f.id) })
            out.append(PaletteItem(id: "duplicate", title: "Duplicate Panel", subtitle: f.title,
                                   symbol: "plus.square.on.square", keywords: "copy clone", shortcut: nil) { ws.duplicate(f.id) })
            out.append(PaletteItem(id: "close", title: "Close Panel", subtitle: f.title,
                                   symbol: "xmark", keywords: "remove delete", shortcut: "Cmd W") { ws.close(f.id) })
            if f.kind == .note {
                for item in Outline.items(in: f.text).prefix(40) {
                    out.append(PaletteItem(id: "heading-\(item.id)", title: "Go to: \(item.title)", subtitle: "Heading in \(f.title)",
                                           symbol: "number", keywords: "outline jump section heading", shortcut: nil) {
                        Runtime.shared.noteHost(for: f).jump(to: item.location)
                    })
                }
                out.append(PaletteItem(id: "export-html", title: "Export as HTML...", subtitle: f.title,
                                       symbol: "chevron.left.forwardslash.chevron.right", keywords: "save web page", shortcut: nil) { ExportOps.saveHTML(f) })
                out.append(PaletteItem(id: "export-pdf", title: "Export as PDF...", subtitle: f.title,
                                       symbol: "doc.richtext", keywords: "save print document", shortcut: nil) { ExportOps.savePDF(f) })
                out.append(PaletteItem(id: "copy-html", title: "Copy as HTML", subtitle: f.title,
                                       symbol: "doc.on.clipboard", keywords: "clipboard rich", shortcut: nil) { ExportOps.copyHTML(f) })
                out.append(PaletteItem(id: "save-md", title: "Save as Markdown...", subtitle: f.title,
                                       symbol: "square.and.arrow.down", keywords: "export file md", shortcut: "Cmd S") { FileOps.saveMarkdown(f) })
            }
            for mode in NoteMode.allCases where f.kind == .note {
                out.append(PaletteItem(id: "mode-\(mode.rawValue)", title: "Note view: \(mode.label)", subtitle: f.title,
                                       symbol: mode.symbol, keywords: "markdown preview edit split", shortcut: nil) {
                    f.settings.noteMode = mode
                })
            }
        }
        for sp in ws.spaces {
            for np in sp.panels where np.kind == .note && np.id != ws.focused?.id {
                out.append(PaletteItem(id: "note-\(np.id)", title: "Go to note: \(np.title)", subtitle: sp.name,
                                       symbol: "text.alignleft", keywords: "open find switch note", shortcut: nil) {
                    ws.openNote(titled: np.title)
                })
            }
        }
        for po in ws.popouts {
            out.append(PaletteItem(id: "dock-\(po.panel.id)", title: "Return to App: \(po.panel.title)", subtitle: "Pop-out window",
                                   symbol: "arrow.uturn.backward.square", keywords: "dock window popout", shortcut: nil) { ws.dock(po.panel.id) })
        }
        out.append(PaletteItem(id: "equalize", title: "Even Out Sizes", subtitle: "Give every panel equal room",
                               symbol: "equal.square", keywords: "balance resize reset", shortcut: "Cmd Option =") { ws.equalize() })
        for preset in LayoutPreset.allCases {
            out.append(PaletteItem(id: "layout-\(preset.rawValue)", title: "Layout: \(preset.label)", subtitle: "Rearrange the current space",
                                   symbol: preset.symbol, keywords: "arrange preset grid", shortcut: nil) { ws.apply(preset) })
        }
        out.append(PaletteItem(id: "new-space", title: "New Workspace", subtitle: "A fresh canvas of panels",
                               symbol: "plus.rectangle.on.rectangle", keywords: "space page tab", shortcut: "Cmd Shift N") { ws.newSpace() })
        out.append(PaletteItem(id: "dup-space", title: "Duplicate Workspace", subtitle: ws.space.name,
                               symbol: "plus.square.on.square", keywords: "copy clone space", shortcut: nil) { ws.duplicateSpace(ws.activeSpaceID) })
        for t in TemplateStore.shared.all {
            out.append(PaletteItem(id: "tpl-\(t.id)", title: "New Workspace: \(t.name)", subtitle: "From template",
                                   symbol: t.symbol, keywords: "template layout start", shortcut: nil) { ws.newSpace(from: t) })
        }
        out.append(PaletteItem(id: "save-tpl", title: "Save Layout as Template...", subtitle: "Reuse this arrangement",
                               symbol: "square.and.arrow.down", keywords: "template store", shortcut: nil) {
            if let name = Prompt.text(title: "Save Layout as Template", message: "Name this layout.", defaultValue: ws.space.name) {
                ws.saveTemplate(named: name)
            }
        })
        out.append(PaletteItem(id: "open-file", title: "Open Markdown File...", subtitle: "Open a file as a note",
                               symbol: "doc.text", keywords: "import md", shortcut: "Cmd O") { FileOps.openMarkdown() })
        out.append(PaletteItem(id: "support", title: "Support Panels", subtitle: "Say thanks with a donation",
                               symbol: "heart", keywords: "donate tip sponsor stripe", shortcut: nil) { AboutLinks.open(AboutLinks.support) })
        out.append(PaletteItem(id: "portfolio", title: "Visit aiyan.tech", subtitle: "The maker's portfolio",
                               symbol: "globe", keywords: "portfolio website about maker", shortcut: nil) { AboutLinks.open(AboutLinks.portfolio) })
        out.append(PaletteItem(id: "settings", title: "Settings", subtitle: "Appearance, sites, updates",
                               symbol: "gearshape", keywords: "preferences options", shortcut: "Cmd ,") { SettingsRouter.shared.show(.general) })
        for (i, s) in ws.spaces.enumerated() where s.id != ws.activeSpaceID {
            out.append(PaletteItem(id: "space-\(s.id)", title: "Go to \(s.name)", subtitle: "Workspace \(i + 1)",
                                   symbol: "rectangle.on.rectangle", keywords: "switch workspace", shortcut: i < 9 ? "Cmd \(i + 1)" : nil) {
                ws.selectSpace(s.id)
            })
        }
        for entry in [("auto", "Auto")] + appearance.allThemes.map({ ($0.id, $0.name) }) {
            out.append(PaletteItem(id: "theme-\(entry.0)", title: "Theme: \(entry.1)", subtitle: "Change the look of the whole app",
                                   symbol: "circle.lefthalf.filled", keywords: "appearance color dark light", shortcut: nil) {
                withAnimation(.snappy(duration: 0.3)) { appearance.select(themeID: entry.0) }
            })
        }
        return out
    }

    private var filtered: [PaletteItem] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        if words.isEmpty { return Array(items.prefix(14)) }
        return items.filter { item in
            let hay = (item.title + " " + item.subtitle + " " + item.keywords).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(theme.isDark ? 0.45 : 0.22)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .transition(.opacity)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.mutedC)
                    TextField("Type a command or search", text: $query)
                        .textFieldStyle(.plain)
                        .font(Typo.ui(16))
                        .foregroundStyle(theme.textC)
                        .focused($focused)
                        .onSubmit { run(at: index) }
                        .onKeyPress(.upArrow) { move(-1); return .handled }
                        .onKeyPress(.downArrow) { move(1); return .handled }
                        .onKeyPress(.escape) { close(); return .handled }
                        .onChange(of: query) { _, _ in index = 0 }
                }
                .padding(.horizontal, 18)
                .frame(height: 54)

                Rectangle().fill(theme.hairline).frame(height: 1)

                let list = filtered
                if list.isEmpty {
                    Text("No matches")
                        .font(Typo.ui(13))
                        .foregroundStyle(theme.faintC)
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                                    row(item, selected: i == index)
                                        .id(item.id)
                                        .onTapGesture { run(at: i) }
                                        .onHover { h in if h { index = i } }
                                }
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 380)
                        .onChange(of: index) { _, new in
                            if new < list.count { proxy.scrollTo(list[new].id) }
                        }
                    }
                }
            }
            .frame(width: 580)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.surfaceC)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
            .shadow(color: theme.shadow, radius: 40, y: 18)
            .padding(.top, 110)
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        }
        .onAppear {
            query = ""
            index = 0
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
                focused = true
            }
        }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? theme.accentC : theme.mutedC)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.hover))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(Typo.ui(13.5, bold: true)).foregroundStyle(theme.textC)
                Text(item.subtitle).font(Typo.ui(11.5)).foregroundStyle(theme.faintC).lineLimit(1)
            }
            Spacer()
            if let s = item.shortcut { KeyCap(text: s) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? theme.hover : .clear))
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        index = (index + delta + count) % count
    }

    private func run(at i: Int) {
        let list = filtered
        guard i >= 0, i < list.count else { return }
        let action = list[i].action
        withAnimation(.snappy(duration: 0.2)) { ws.paletteOpen = false }
        restoreFocus()
        DispatchQueue.main.async { action() }
    }
}
