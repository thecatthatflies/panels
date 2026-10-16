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
    private var keyMonitor: Any?
    private var moveMonitor: Any?
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

        // Reveal the traffic lights when the pointer visits the top-left corner during Lock In.
        moveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            WindowChrome.updateLockHover(for: event)
            return event
        }

        // Escape leaves Lock In unless a terminal or web page needs the key.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let ws = Workspace.shared
            guard ws.focusMode, !ws.paletteOpen, event.keyCode == 53 else { return event }
            let responder = event.window?.firstResponder
            if responder is TerminalNSView || responder is PanelWebView { return event }
            ws.exitFocusMode()
            return nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        Persistence.saveNow()
        Runtime.shared.terminateAll()
    }
}
