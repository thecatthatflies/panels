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
            // The web shots wait on WebKit, whose replies arrive on the main queue, so they run as async steps.
            renderSiteWeb(into: dir) { NSApp.terminate(nil) }
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

        for (w, h) in [(900, 600), (760, 500)] as [(CGFloat, CGFloat)] {
            let kinds: [PanelKind] = [.note, .tasks, .terminal, .note, .tasks, .terminal]
            let leaves = kinds.map { Node(panel: Panel(kind: $0, title: $0.defaultTitle, text: "# Heading\n\nSome body text that should wrap and stay readable.\n")) }
            let tree = TileEngine.build(panels: leaves.compactMap(\.panel), layout: .balanced, size: CGSize(width: w - 16, height: h - 16), gap: 8)
            let root = NodeView(node: tree)
                .environment(\.theme, theme).padding(8).frame(width: w, height: h).background(theme.windowC)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: w, height: h)
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host
            win.setFrameOrigin(NSPoint(x: -6000, y: -6000))
            win.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/tiling-6col-\(Int(w))x\(Int(h)).png"))
            }
            for l in tree.leaves() { if let p = l.panel { Runtime.shared.release(p.id) } }
            win.contentView = nil
        }

        do {
            let note = Panel(kind: .note, title: "Trip plan", text: "# Trip plan\n\nWe leave on **Friday** and come back *Sunday*.\n\n- Book the hotel\n- Pack bags\n\nSee [the map](https://example.com) for details.\n")
            let root = PanelView(panel: note).environment(\.theme, theme).frame(width: 620, height: 420).background(theme.windowC)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: 620, height: 420)
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host
            win.setFrameOrigin(NSPoint(x: -6000, y: -6000))
            win.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/note-docs-mode.png"))
            }
            Runtime.shared.release(note.id)
            win.contentView = nil
        }

        // Marketing shots for the website: one populated workspace per built-in theme, rendered at 1600 by 1000.
        for t in Theme.all {
            let w: CGFloat = 1600, h: CGFloat = 1000
            let note = Panel(kind: .note, title: "Launch notes",
                             text: "# Launch notes\n\nThe site goes live **Friday**. Everything else can wait until *Monday*.\n\n## Before then\n\n- Write the release notes\n- Record the short demo\n- Check the download link\n\nSee [the checklist](https://example.com) for the full list.\n")
            let tasks = Panel(kind: .tasks, title: "Today",
                              tasks: [TaskItem(title: "Reply to the design review", done: true), TaskItem(title: "Finish the release notes"),
                                      TaskItem(title: "Record the demo"), TaskItem(title: "Test the download on a clean Mac"),
                                      TaskItem(title: "Book the dentist", done: true)])
            let timer = Panel(kind: .timer, title: "Focus")
            let tree = TileEngine.build(panels: [note, tasks, timer], layout: .main, size: CGSize(width: w - 32, height: h - 32), gap: 12)
            let root = NodeView(node: tree)
                .environment(\.theme, t).padding(16).frame(width: w, height: h).background(t.windowC)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: w, height: h)
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host
            win.setFrameOrigin(NSPoint(x: -6000, y: -6000))
            win.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/site-\(t.id).png"))
            }
            for l in tree.leaves() { if let p = l.panel { Runtime.shared.release(p.id) } }
            win.contentView = nil
        }

        renderSitePanels(into: dir)

        for kind in PanelKind.allCases {
            let m = PanelSize.minimum(for: kind)
            let panel = Panel(kind: kind, title: kind == .note ? "A fairly long note title" : kind.defaultTitle,
                              text: "# Heading\n\nSome body text that should wrap and stay readable.\n\n- one\n- two\n",
                              tasks: [TaskItem(title: "Buy milk"), TaskItem(title: "Call mum", done: true), TaskItem(title: "A much longer task title that wraps")])
            let root = PanelView(panel: panel).environment(\.theme, theme).frame(width: m.width, height: m.height).background(theme.windowC)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: m.width, height: m.height)
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host
            win.setFrameOrigin(NSPoint(x: -6000, y: -6000))
            win.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/minsize-\(kind.rawValue).png"))
            }
            Runtime.shared.release(panel.id)
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

    /// Website shots of a terminal panel, one per built-in theme.
    /// The terminal runs /bin/cat (silent, no prompt) and gets a scripted session fed straight to the emulator,
    /// so no real shell, user name or host name ends up in the picture.
    private static func renderSitePanels(into dir: String) {
        var settings = PanelSettings()
        settings.padding = 14
        settings.shell = "/bin/cat"
        let term = Panel(kind: .terminal, title: "site", settings: settings)
        var fed = false
        for t in Theme.all {
            let w: CGFloat = 664, h: CGFloat = 480
            let root = PanelView(panel: term).environment(\.theme, t).frame(width: w, height: h).background(t.windowC)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: w, height: h)
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host
            win.setFrameOrigin(NSPoint(x: -6000, y: -6000))
            win.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            host.layoutSubtreeIfNeeded()
            let tc = Runtime.shared.terminal(for: term)
            if !fed {
                tc.emulator.feed(Array(terminalSession().utf8))
                fed = true
            }
            tc.view.contentChanged()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/site-panel-terminal-\(t.id).png"))
            }
            win.contentView = nil
        }
        Runtime.shared.release(term.id)
    }

    /// Website shots of a web panel (the owner's portfolio), one per built-in theme. Loads once, then
    /// re-renders the panel chrome per theme. WKWebView draws out of process, so cacheDisplay leaves the page
    /// blank; WebKit's own snapshot is painted into the frame on top.
    private static func renderSiteWeb(into dir: String, done: @escaping () -> Void) {
        let w: CGFloat = 960, h: CGFloat = 640
        let web = Panel(kind: .web, title: "aiyan.tech", url: "https://aiyan.tech")
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.frame = NSRect(x: 0, y: 0, width: w, height: h)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        win.orderBack(nil)
        let wc = Runtime.shared.web(for: web)
        // The capture window sits off screen, which can make WebKit pause the page. This developer-only
        // switch (WebKit SPI, checked before use) keeps it painting. Never used outside snapshots.
        let occlusion = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        if wc.webView.responds(to: occlusion), let imp = wc.webView.method(for: occlusion) {
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(imp, to: Setter.self)(wc.webView, occlusion, false)
        }
        let themes = Theme.all
        let deadline = Date().addingTimeInterval(30)

        func finish() {
            win.contentView = nil
            Runtime.shared.release(web.id)
            done()
        }

        func shoot(_ index: Int) {
            guard index < themes.count else { return finish() }
            let t = themes[index]
            host.rootView = AnyView(PanelView(panel: web).environment(\.theme, t).frame(width: w, height: h).background(t.windowC))
            host.layoutSubtreeIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                host.layoutSubtreeIfNeeded()
                wc.webView.takeSnapshot(with: nil) { img, _ in
                    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: rep)
                        if let img, let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                            NSGraphicsContext.saveGraphicsState()
                            NSGraphicsContext.current = ctx
                            img.draw(in: wc.webView.convert(wc.webView.bounds, to: nil))
                            NSGraphicsContext.restoreGraphicsState()
                        }
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/site-panel-web-\(t.id).png"))
                    }
                    shoot(index + 1)
                }
            }
        }

        func waitForLoad() {
            if (wc.isLoading || wc.webView.url == nil) && Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { waitForLoad() }
            } else {
                // let late fonts and images settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { shoot(0) }
            }
        }

        host.rootView = AnyView(PanelView(panel: web).environment(\.theme, themes[0]).frame(width: w, height: h).background(themes[0].windowC))
        host.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { waitForLoad() }
    }

    /// A short, believable build session with prompt colors, in plain ANSI.
    private static func terminalSession() -> String {
        let dim = "\u{1B}[2m", bold = "\u{1B}[1m", green = "\u{1B}[32m", cyan = "\u{1B}[36m", yellow = "\u{1B}[33m", reset = "\u{1B}[0m"
        let prompt = "\(cyan)~/Projects/site\(reset) \(yellow)main\(reset) $ "
        let lines = [
            "\(prompt)git pull",
            "Already up to date.",
            "\(prompt)npm run build",
            "",
            "\(dim)> site@1.0.0 build\(reset)",
            "\(dim)> tsc -b && vite build\(reset)",
            "",
            "\(cyan)vite v7.1.3\(reset) \(green)building for production...\(reset)",
            "\(green)✓\(reset) 48 modules transformed.",
            "\(dim)dist/\(reset)index.html                 \(bold)1.75 kB\(reset)",
            "\(dim)dist/assets/\(reset)index.css         \(bold)20.71 kB\(reset)",
            "\(dim)dist/assets/\(reset)index.js         \(bold)436.32 kB\(reset)",
            "\(green)✓ built in 2.06s\(reset)",
            "\(prompt)git commit -am \"launch page\"",
            "[main 4f2c1d8] launch page",
            " 3 files changed, 41 insertions(+), 12 deletions(-)",
            prompt,
        ]
        return lines.joined(separator: "\r\n")
    }
}
