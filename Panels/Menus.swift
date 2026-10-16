import SwiftUI
import AppKit

struct PanelsCommands: Commands {
    private let ws = Workspace.shared
    private let appearance = Appearance.shared
    private let sites = SiteLibrary.shared
    private let templates = TemplateStore.shared

    private var focusedKind: PanelKind? { ws.focused?.kind }

    var body: some Commands {
        // MARK: app menu
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") { Updater.shared.check(userInitiated: true) }
        }

        // MARK: File
        CommandGroup(replacing: .newItem) {
            Button("New Note") { ws.addPanel(.note) }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Terminal") { ws.addPanel(.terminal) }
                .keyboardShortcut("t", modifiers: .command)
            Button("New Web Panel") { ws.addPanel(.web) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Menu("New Panel") {
                ForEach(PanelKind.allCases) { kind in
                    Button { ws.addPanel(kind) } label: { Label(kind.label, systemImage: kind.symbol) }
                }
            }
            Menu("Open Site") {
                ForEach(sites.sites) { site in
                    Button { ws.openSite(site) } label: { Label(site.name, systemImage: site.symbol) }
                }
                Divider()
                Button("Manage Sites...") { SettingsRouter.shared.show(.sites) }
            }
            Divider()
            Button("Open File...") { FileOps.openMarkdown() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Note as Markdown...") { if let p = ws.focused, p.kind == .note { FileOps.saveMarkdown(p) } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(focusedKind != .note)
            Menu("Export Note") {
                Button("HTML...") { if let p = ws.focused, p.kind == .note { ExportOps.saveHTML(p) } }
                Button("PDF...") { if let p = ws.focused, p.kind == .note { ExportOps.savePDF(p) } }
                Button("Copy as HTML") { if let p = ws.focused, p.kind == .note { ExportOps.copyHTML(p) } }
            }
            .disabled(focusedKind != .note)
            Divider()
            Button("Close Panel") { if let f = ws.focused { ws.close(f.id) } }
                .keyboardShortcut("w", modifiers: .command)
            Button("Close Workspace") { ws.closeSpace(ws.activeSpaceID) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(ws.spaces.count < 2)
            Divider()
            Button("Show Data in Finder") { FileOps.revealDataFolder() }
        }

        // MARK: Edit
        CommandGroup(after: .textEditing) {
            Menu("Find") {
                Button("Find...") { FindOps.perform(1) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find and Replace...") { FindOps.perform(12) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Find Next") { FindOps.perform(2) }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { FindOps.perform(3) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Use Selection for Find") { FindOps.perform(7) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            Menu("Go to Heading") {
                if let p = ws.focused, p.kind == .note {
                    ForEach(Outline.items(in: p.text).prefix(40)) { item in
                        Button(String(repeating: "\u{2003}", count: max(item.level - 1, 0)) + item.title) {
                            Runtime.shared.noteHost(for: p).jump(to: item.location)
                        }
                    }
                }
            }
            .disabled(focusedKind != .note)
        }

        // MARK: View
        CommandGroup(after: .sidebar) {
            Button(ws.focusMode ? "Leave Lock In" : "Lock In") { ws.toggleFocusMode() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Zoom Panel") { ws.toggleZoom() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Button("Even Out Sizes") { ws.equalize() }
                .keyboardShortcut("=", modifiers: [.command, .option])
            Divider()
            Button("Bigger") { ws.adjustSize(1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller") { ws.adjustSize(-1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { ws.resetSize() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Menu("Layout") {
                ForEach(LayoutPreset.allCases) { preset in
                    Button { ws.apply(preset) } label: { Label(preset.label, systemImage: preset.symbol) }
                }
            }
            Menu("Theme") {
                ForEach(ThemeChoice.allCases) { choice in
                    Button {
                        withAnimation(.snappy(duration: 0.3)) { appearance.choice = choice }
                    } label: {
                        if appearance.choice == choice { Label(choice.label, systemImage: "checkmark") }
                        else { Text(choice.label) }
                    }
                }
            }
            Button(ws.floating ? "Stop Floating on Top" : "Float on Top") { ws.setFloating(!ws.floating) }
                .keyboardShortcut("f", modifiers: [.command, .control])
            Divider()
        }

        // MARK: Panel
        CommandMenu("Panel") {
            Button("Command Palette") { ws.paletteOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Split Right") { if let f = ws.focused { ws.split(f.id, axis: .horizontal, kind: .note) } }
                .keyboardShortcut("d", modifiers: .command)
            Button("Split Down") { if let f = ws.focused { ws.split(f.id, axis: .vertical, kind: .note) } }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Duplicate Panel") { if let f = ws.focused { ws.duplicate(f.id) } }
                .keyboardShortcut("d", modifiers: [.command, .option])
            Button("Rename Panel") { ws.renameRequest = ws.focused?.id }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Panel Settings") { ws.settingsRequest = ws.focused?.id }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            Menu("Note View") {
                ForEach(NoteMode.allCases) { mode in
                    Button { ws.focused?.settings.noteMode = mode } label: {
                        if ws.focused?.settings.noteMode == mode { Label(mode.label, systemImage: "checkmark") }
                        else { Text(mode.label) }
                    }
                }
            }
            .disabled(focusedKind != .note)
            Menu("Move to Workspace") {
                ForEach(ws.spaces.filter { $0.id != ws.activeSpaceID }) { sp in
                    Button { if let f = ws.focused { ws.move(panel: f.id, toSpace: sp.id) } } label: {
                        Label(sp.name, systemImage: sp.symbol)
                    }
                }
            }
            .disabled(ws.spaces.count < 2)
            Divider()
            Button("Next Panel") { ws.cycleFocus(1) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Previous Panel") { ws.cycleFocus(-1) }
                .keyboardShortcut("[", modifiers: .command)
            Button("Focus Left") { ws.focusDirection(.left) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Focus Right") { ws.focusDirection(.right) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Focus Up") { ws.focusDirection(.up) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Focus Down") { ws.focusDirection(.down) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }

        // MARK: Workspace
        CommandMenu("Workspace") {
            ForEach(Array(ws.spaces.enumerated()), id: \.element.id) { i, space in
                if i < 9 {
                    Button {
                        ws.selectSpace(space.id)
                    } label: {
                        if space.id == ws.activeSpaceID { Label(space.name, systemImage: "checkmark") }
                        else { Text(space.name) }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                } else {
                    Button(space.name) { ws.selectSpace(space.id) }
                }
            }
            Divider()
            Button("New Workspace") { ws.newSpace() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Menu("New from Template") {
                ForEach(templates.all) { t in
                    Button { ws.newSpace(from: t) } label: { Label(t.name, systemImage: t.symbol) }
                }
            }
            Button("Duplicate Workspace") { ws.duplicateSpace(ws.activeSpaceID) }
            Button("Rename Workspace...") {
                if let name = Prompt.text(title: "Rename Workspace", message: "Choose a new name.",
                                          defaultValue: ws.space.name, confirm: "Rename"), !name.isEmpty {
                    ws.renameSpace(ws.activeSpaceID, to: name)
                }
            }
            Button("Save Layout as Template...") {
                if let name = Prompt.text(title: "Save Layout as Template",
                                          message: "Name this layout. New workspaces can start from it.",
                                          defaultValue: ws.space.name) {
                    ws.saveTemplate(named: name)
                }
            }
            Divider()
            Button("Previous Workspace") { ws.cycleSpace(-1) }
                .keyboardShortcut("[", modifiers: [.command, .control])
            Button("Next Workspace") { ws.cycleSpace(1) }
                .keyboardShortcut("]", modifiers: [.command, .control])
            Button("Move Workspace Left") { ws.moveSpace(ws.activeSpaceID, by: -1) }
            Button("Move Workspace Right") { ws.moveSpace(ws.activeSpaceID, by: 1) }
            Divider()
            Menu("Workspace Theme") {
                Button { ws.space.themeID = nil } label: {
                    if ws.space.themeID == nil { Label("Follow App", systemImage: "checkmark") } else { Text("Follow App") }
                }
                Divider()
                ForEach(Theme.all) { t in
                    Button { ws.space.themeID = t.id } label: {
                        if ws.space.themeID == t.id { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                    }
                }
            }
        }

        // MARK: Web
        CommandMenu("Web") {
            Button("Back") { if let p = ws.focused, p.kind == .web { Runtime.shared.web(for: p).goBack() } }
                .keyboardShortcut("[", modifiers: [.command, .option, .control])
                .disabled(focusedKind != .web)
            Button("Forward") { if let p = ws.focused, p.kind == .web { Runtime.shared.web(for: p).goForward() } }
                .keyboardShortcut("]", modifiers: [.command, .option, .control])
                .disabled(focusedKind != .web)
            Button("Reload Page") { if let p = ws.focused, p.kind == .web { Runtime.shared.web(for: p).reload() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(focusedKind != .web)
            Button("Go to Address") {
                if let p = ws.focused, p.kind == .web {
                    NotificationCenter.default.post(name: .panelsFocusAddressBar, object: p.id)
                }
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(focusedKind != .web)
            Divider()
            Button("Save Page as Site") { if let p = ws.focused, p.kind == .web { let s = sites.saveSite(from: p); ws.showToast("Saved \(s.name)") } }
                .disabled(focusedKind != .web)
            Button("Open in Browser") {
                if let p = ws.focused, p.kind == .web, let u = URL(string: p.url) { NSWorkspace.shared.open(u) }
            }
            .disabled(focusedKind != .web)
            Divider()
            Button("Manage Sites...") { SettingsRouter.shared.show(.sites) }
        }
    }
}
