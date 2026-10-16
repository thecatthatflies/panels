import SwiftUI
import AppKit

@main
struct PanelsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        Typo.registerBundledFonts()
    }

    var body: some Scene {
        Window("Panels", id: "main") {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1380, height: 880)
        .commands { PanelsCommands() }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mouseMonitor: Any?
    private var appearanceObserver: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Persistence.startAutosave()
        Updater.shared.start()
        Appearance.shared.refreshSystem()
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            DispatchQueue.main.async { Appearance.shared.refreshSystem() }
        }

        // Clicking anywhere inside a panel focuses it, even when the click lands on a native view.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            guard let window = event.window, let content = window.contentView else { return event }
            let h = content.bounds.height
            let p = CGPoint(x: event.locationInWindow.x, y: h - event.locationInWindow.y)
            let ws = Workspace.shared
            if let hit = ws.space.panels.first(where: { ws.frames[$0.id]?.contains(p) ?? false }),
               ws.space.focusedID != hit.id {
                ws.focus(hit.id, grabFirstResponder: false)
            }
            return event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        Persistence.saveNow()
        Runtime.shared.terminateAll()
    }
}

// MARK: - Menu commands

struct PanelsCommands: Commands {
    private let ws = Workspace.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") { Updater.shared.check(userInitiated: true) }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Note") { ws.addPanel(.note) }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Terminal") { ws.addPanel(.terminal) }
                .keyboardShortcut("t", modifiers: .command)
            Button("New Web Panel") { ws.addPanel(.web) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Menu("New Panel") {
                ForEach(PanelKind.allCases) { kind in
                    Button(kind.label) { ws.addPanel(kind) }
                }
            }
            Divider()
            Button("New Space") { ws.newSpace() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Close Panel") { if let f = ws.focused { ws.close(f.id) } }
                .keyboardShortcut("w", modifiers: .command)
            Button("Close Space") { ws.closeSpace(ws.activeSpaceID) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }

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
            Button("Zoom Panel") { ws.toggleZoom() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Button("Even Out Sizes") { ws.equalize() }
                .keyboardShortcut("=", modifiers: .command)
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
            Divider()
            Menu("Layout") {
                ForEach(LayoutPreset.allCases) { preset in
                    Button(preset.label) { ws.apply(preset) }
                }
            }
        }

        CommandMenu("Space") {
            ForEach(1...9, id: \.self) { i in
                Button("Space \(i)") { ws.selectSpace(index: i - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i)")), modifiers: .command)
            }
        }
    }
}

// MARK: - Settings window

struct SettingsView: View {
    private let appearance = Appearance.shared

    var body: some View {
        let theme = appearance.theme
        @Bindable var a = appearance

        VStack(alignment: .leading, spacing: 24) {
            Text("Appearance")
                .font(Typo.ui(18, bold: true))
                .foregroundStyle(theme.textC)

            SettingsSection(title: "Theme") {
                SegmentedChips(options: ThemeChoice.allCases, selection: $a.choice, label: { $0.label })
                HStack(spacing: 10) {
                    ForEach(Theme.all) { t in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(t.surfaceC)
                                .frame(height: 44)
                                .overlay(alignment: .bottomLeading) {
                                    HStack(spacing: 3) {
                                        Circle().fill(t.accentC).frame(width: 8, height: 8)
                                        Capsule().fill(t.textC.opacity(0.5)).frame(width: 22, height: 3)
                                    }
                                    .padding(7)
                                }
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(t.hairlineStrong, lineWidth: 1))
                            Text(t.name).font(Typo.ui(11)).foregroundStyle(theme.mutedC)
                        }
                    }
                }
            }

            SettingsSection(title: "Window") {
                SliderRow(label: "Translucency", value: $a.translucency, range: 0.5...1, step: 0.01,
                          format: { String(format: "%.0f%%", $0 * 100) })
                SliderRow(label: "Panel gap", value: $a.gap, range: 2...20, step: 1,
                          format: { String(format: "%.0f pt", $0) })
                SliderRow(label: "Corner radius", value: $a.cornerRadius, range: 0...28, step: 1,
                          format: { String(format: "%.0f pt", $0) })
            }
            UpdateSettingsSection()
            Spacer()
        }
        .padding(26)
        .frame(width: 460, height: 640)
        .background(theme.surfaceC)
        .environment(\.theme, theme)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}
