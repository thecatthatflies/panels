import SwiftUI
import AppKit

/// Developer tool: PANELS_SNAPSHOTS=/some/dir renders every panel kind at a range of small sizes to PNG files, then quits.
/// Used to find layout problems in cramped panels without needing the screen. Never runs in normal use.
enum SnapshotTool {
    static var directory: String? {
        let v = ProcessInfo.processInfo.environment["PANELS_SNAPSHOTS"]
        return (v?.isEmpty ?? true) ? nil : v
    }

    static func runIfRequested() {
        guard let dir = directory else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            render(into: dir)
            NSApp.terminate(nil)
        }
    }

    private static func render(into dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let theme = Appearance.shared.theme
        let sizes: [(CGFloat, CGFloat)] = [(120, 80), (180, 110), (240, 150), (320, 200), (420, 280), (200, 420)]

        for s in 0..<3 {
            let root = OnboardingView(startStep: s).environment(\.theme, theme).frame(width: 640, height: 520).background(theme.windowC)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 520)
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host
            win.setFrameOrigin(NSPoint(x: -6000, y: -6000))
            win.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/onboarding-\(s + 1).png"))
            }
            win.contentView = nil
        }

        for (name, gate) in [("mic-prime", DictationController.Gate.prime), ("mic-denied", .denied)] {
            let root = DictationPermissionCard(gate: gate).environment(\.theme, theme).frame(width: 560, height: 360).background(theme.windowC)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: 560, height: 360)
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host
            win.setFrameOrigin(NSPoint(x: -6000, y: -6000))
            win.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
            win.contentView = nil
        }

        for kind in [PanelKind.note, .terminal, .tasks, .timer, .web] {
            for (w, h) in sizes {
                let panel = Panel(kind: kind, title: kind == .note ? "A long note title here" : kind.defaultTitle,
                                  text: "# Heading\n\nSome body text that should wrap and stay readable.\n\n- one\n- two\n",
                                  tasks: [TaskItem(title: "Buy milk"), TaskItem(title: "Call mum", done: true), TaskItem(title: "A much longer task title that wraps")])
                let root = PanelView(panel: panel)
                    .environment(\.theme, theme)
                    .frame(width: w, height: h)
                    .background(theme.windowC)
                let host = NSHostingView(rootView: root)
                host.frame = NSRect(x: 0, y: 0, width: w, height: h)
                let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                win.contentView = host
                win.setFrameOrigin(NSPoint(x: -6000, y: -6000))
                win.orderBack(nil)
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: "\(dir)/\(kind.rawValue)-\(Int(w))x\(Int(h)).png"))
                }
                Runtime.shared.release(panel.id)
                win.contentView = nil
            }
        }
    }
}
