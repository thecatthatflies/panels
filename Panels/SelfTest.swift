import SwiftUI
import AppKit
import WebKit

/// Headless self test. Launch with PANELS_SELFTEST=1 (and PANELS_DATA_DIR pointing at a scratch folder).
/// It exercises the real model, runtime and views in-process, writes PASS or FAIL lines to
/// PANELS_SELFTEST_LOG (default /tmp/panels-selftest.log) and then quits. It never runs in normal use.
import Network

/// One-shot HTTP server on loopback that serves a body as an attachment.
final class LoopbackServer {
    private let listener: NWListener
    private let port: UInt16

    var url: URL { URL(string: "http://127.0.0.1:\(port)/file")! }

    init(body: String, filename: String) {
        var chosen: NWListener?
        var p: UInt16 = 0
        while chosen == nil {
            p = UInt16.random(in: 20000...40000)
            chosen = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: p)!)
        }
        listener = chosen!
        port = p
        listener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"\(filename)\"\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                conn.send(content: head.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
            }
        }
        listener.start(queue: .global())
    }

    func stop() { listener.cancel() }
}

enum SelfTest {
    static var enabled: Bool { ProcessInfo.processInfo.environment["PANELS_SELFTEST"] == "1" }

    private static var lines: [String] = []
    private static var failures = 0

    private static func log(_ s: String) {
        lines.append(s)
        let path = ProcessInfo.processInfo.environment["PANELS_SELFTEST_LOG"] ?? "/tmp/panels-selftest.log"
        try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if !ok { failures += 1 }
        log("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  [\(detail)]")")
    }

    private static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func waitUntil(_ timeout: Double, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return true }
            await sleep(0.05)
        }
        return cond()
    }

    // MARK: entry

    static func runIfRequested() {
        guard enabled else { return }
        Task { @MainActor in
            await runAll()
            log("")
            log(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
            await sleep(0.3)
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private static func runAll() async {
        log("Panels self test, \(Date())")
        testVersionsAndFeed()
        testDictationCleaner()
        testSnippetsOutlineExport()
        testModelInvariants()
        testPersistenceRoundTrip()
        await testReopenStack()
        await testPopouts()
        testThemes()
        await testTimer()
        await testTerminal()
        await testWeb()
        testEditor()
        await testSound()
        testSettingsCodable()
        testDataSafety()
        testSizeClasses()
        testTaskRemoval()
        testOnboarding()
        testDictationGate()
        testSiteZoom()
        testTiling()
        testNoteEditing()
        testHardMinimums()
        testDividerDrag()
    }

    // MARK: helpers

    private static func validate(_ node: Node, _ ids: inout [UUID]) -> Bool {
        if let p = node.panel { ids.append(p.id); return node.children.isEmpty }
        if node.children.isEmpty { return node.isEmpty }
        if node.weights.count != node.children.count { return false }
        if node.weights.contains(where: { $0 <= 0 }) { return false }
        if node.children.count < 2 { return false }
        return node.children.allSatisfy { validate($0, &ids) }
    }

    private static func treeOK(_ ws: Workspace) -> Bool {
        var ids: [UUID] = []
        for s in ws.spaces { if !validate(s.root, &ids) { return false } }
        ids.append(contentsOf: ws.popouts.map { $0.panel.id })
        return Set(ids).count == ids.count
    }

    // MARK: tests

    @MainActor
    private static func testVersionsAndFeed() {
        check("version compare 1.0.12 > 1.0.9", Version.compare("1.0.12", "1.0.9") == .orderedDescending)
        check("version compare v2 > 1.9.9", Version.compare("v2", "1.9.9") == .orderedDescending)
        check("version compare equal", Version.compare("1.0", "1.0.0") == .orderedSame)
        let json = #"{"tag_name":"v9.1.2","body":"x","html_url":"https://x","assets":[{"name":"Panels.zip","browser_download_url":"https://x/Panels.zip"}]}"#
        let rel = Updater.parse(Data(json.utf8))
        check("updater parses a release feed", rel?.version == "9.1.2" && rel?.assetURL.lastPathComponent == "Panels.zip")
        check("updater rejects a feed without a zip", Updater.parse(Data(#"{"tag_name":"v1","assets":[]}"#.utf8)) == nil)
    }

    @MainActor
    private static func testDictationCleaner() {
        let p = DictationPrefs()
        func c(_ s: String, _ before: String = "") -> String { DictationCleaner.clean(s, before: before, prefs: p) }
        check("cleaner removes fillers", c("hello um this is uh a test") == "Hello this is a test", c("hello um this is uh a test"))
        check("cleaner capitalizes after a sentence", c("next one", "Done. ") == "Next one")
        check("cleaner adds a space against existing text", c("world", "hello") == " world")
        check("cleaner makes a paragraph break", c("one new paragraph two") == "One\n\nTwo", c("one new paragraph two").replacingOccurrences(of: "\n", with: "|"))
        check("cleaner bullets", c("bullet buy milk") == "- Buy milk", c("bullet buy milk"))
        check("cleaner to do", c("to do call mum") == "- [ ] Call mum", c("to do call mum"))
        check("cleaner terminal lowercases", DictationCleaner.clean("Git Status.", before: " ", prefs: p, terminal: true) == "git status")
    }

    @MainActor
    private static func testSnippetsOutlineExport() {
        let d = SnippetStore.shared.expand("date")
        check("snippet date expands to ISO", d?.text.count == 10 && d?.text.contains("-") == true, d?.text ?? "nil")
        let code = SnippetStore.shared.expand("code")
        check("snippet code places caret", code?.caret == 4, "\(String(describing: code?.caret))")
        check("snippet unknown is nil", SnippetStore.shared.expand("zzzz") == nil)

        let md = "# Title\n\nText\n\n```\n# not a heading\n```\n\n## Second [[Link]]\n\n- [x] done\n- item\n\n| a | b |\n| - | - |\n| 1 | 2 |\n"
        let items = Outline.items(in: md)
        check("outline skips fenced code", items.map(\.title) == ["Title", "Second [[Link]]"], items.map(\.title).joined(separator: "|"))
        let html = HTMLExporter.document(title: "T", markdown: md, font: .instrument)
        check("html export has headings", html.contains("<h1>Title</h1>") && html.contains("<h2>"))
        check("html export has checked task", html.contains("checked"))
        check("html export has table", html.contains("<table>"))
        check("html escapes angle brackets", HTMLExporter.inline("a <b> c").contains("&lt;b&gt;"))
    }

    @MainActor
    private static func testModelInvariants() {
        let ws = Workspace.shared
        check("starts with welcome workspace", ws.spaces.count >= 1 && treeOK(ws))
        let before = ws.space.panels.count
        let a = ws.addPanel(.note, title: "A")!
        let b = ws.addPanel(.terminal)!
        ws.split(a.id, axis: .vertical, kind: .tasks)
        check("add and split keep the tree valid", ws.space.panels.count == before + 3 && treeOK(ws))
        ws.equalize()
        ws.apply(.quad)
        check("layout preset keeps all panels", ws.space.panels.count >= before + 3 && treeOK(ws))
        ws.apply(.writerTerminal)
        check("second preset keeps tree valid", treeOK(ws))
        ws.move(a.id, onto: b.id, zone: .left)
        check("drag move keeps tree valid", treeOK(ws))
        ws.move(a.id, onto: b.id, zone: .center)
        check("swap keeps tree valid", treeOK(ws))
        ws.newSpace()
        let second = ws.activeSpaceID
        ws.selectSpace(ws.spaces[0].id)
        ws.move(panel: a.id, toSpace: second)
        check("move panel to another workspace", ws.spaces.first { $0.id == second }?.panels.contains { $0.id == a.id } == true && treeOK(ws))
        ws.duplicateSpace(second)
        check("duplicate workspace deep copies", ws.spaces.count >= 3 && treeOK(ws))
        ws.saveTemplate(named: "SelfTest layout")
        check("template saved", TemplateStore.shared.saved.contains { $0.name == "SelfTest layout" })
        ws.newSpace(from: TemplateStore.builtins[1])
        check("new workspace from template", treeOK(ws) && ws.space.panels.count >= 2)
    }

    @MainActor
    private static func testPersistenceRoundTrip() {
        let ws = Workspace.shared
        let snap = WorkspaceSnapshot(spaces: ws.spaces, active: ws.activeSpaceID, popouts: ws.popouts)
        guard let data = try? JSONEncoder().encode(snap), let back = try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data) else {
            check("snapshot round trip", false, "encode or decode failed"); return
        }
        check("snapshot round trip keeps workspaces and panels",
              back.spaces.count == ws.spaces.count && back.spaces.map { $0.panels.count } == ws.spaces.map { $0.panels.count })
    }

    @MainActor
    private static func testReopenStack() async {
        let ws = Workspace.shared
        let p = ws.addPanel(.note, title: "ReopenMe", text: "keep this text")!
        let before = ws.space.panels.count
        ws.close(p.id)
        check("close removes the panel", ws.space.panels.count == before - 1 && ws.closedStack.count >= 1)
        ws.reopenLast()
        let back = ws.space.panels.first { $0.id == p.id }
        check("reopen restores the panel with its text", back?.text == "keep this text" && treeOK(ws))

        ws.newSpace()
        let sid = ws.activeSpaceID
        let count = ws.spaces.count
        ws.closeSpace(sid)
        check("close workspace", ws.spaces.count == count - 1)
        ws.reopenLast()
        check("reopen restores the workspace", ws.spaces.count == count && ws.activeSpaceID == sid)
    }

    @MainActor
    private static func testPopouts() async {
        let ws = Workspace.shared
        let p = ws.addPanel(.tasks, title: "PopMe")!
        ws.popOut(p.id)
        check("pop out moves the panel to a window", ws.popouts.contains { $0.panel.id == p.id } && !ws.space.panels.contains { $0.id == p.id } && treeOK(ws))
        await sleep(0.3)
        let frame = ws.popout(for: p.id)?.frame
        check("pop out records a window frame", frame != nil && !(frame ?? "").isEmpty, frame ?? "nil")
        // persistence of popouts
        let snap = WorkspaceSnapshot(spaces: ws.spaces, active: ws.activeSpaceID, popouts: ws.popouts)
        let back = (try? JSONEncoder().encode(snap)).flatMap { try? JSONDecoder().decode(WorkspaceSnapshot.self, from: $0) }
        check("popouts survive a save and load", back?.popouts?.contains { $0.panel.id == p.id } == true && back?.popouts?.first?.frame == frame)
        ws.dock(p.id)
        check("dock returns the panel to the layout", ws.space.panels.contains { $0.id == p.id } && ws.popouts.isEmpty && treeOK(ws))
        let beforeStack = ws.closedStack.count
        ws.popOut(p.id)
        log("      second pop out: popouts \(ws.popouts.count), in layout \(ws.space.panels.contains { $0.id == p.id })")
        ws.closePopout(p.id)
        check("closing a pop-out is undoable", ws.popouts.isEmpty && ws.closedStack.count == beforeStack + 1, "stack \(beforeStack) -> \(ws.closedStack.count)")
        ws.reopenLast()
        check("reopen restores the pop-out window", ws.popouts.contains { $0.panel.id == p.id })
        ws.dock(p.id)
    }

    @MainActor
    private static func testThemes() {
        let store = ThemeStore.shared
        let appearance = Appearance.shared
        let spec = store.add(from: .granite, name: "SelfTest")
        appearance.select(themeID: spec.id)
        check("custom theme can be selected", appearance.theme.id == spec.id && appearance.allThemes.contains { $0.id == spec.id })
        let ws = Workspace.shared
        ws.space.themeID = spec.id
        store.remove(spec.id)
        check("deleting a theme clears selection and workspace override",
              appearance.customID == nil && ws.space.themeID == nil && !appearance.allThemes.contains { $0.id == spec.id })
        check("theme editor index lookup after delete is safe", store.index(of: spec.id) == nil)
        appearance.select(themeID: "auto")
    }

    @MainActor
    private static func testTimer() async {
        var st = PanelSettings()
        st.focusMinutes = 1; st.breakMinutes = 1; st.longBreakMinutes = 2; st.sessionsBeforeLong = 2; st.timerSound = false
        let panel = Panel(kind: .timer, settings: st)
        let m = Runtime.shared.timer(for: panel)
        let speed = ProcessInfo.processInfo.environment["PANELS_TIMER_SPEED"] ?? "1"
        log("      timer speed multiplier: \(speed)")

        check("timer starts idle at the chosen length", m.display == .idle && m.remaining == 60)
        m.set(minutes: 3); check("set minutes updates length", m.chosenMinutes == 3 && m.remaining == 180)
        m.adjust(by: -1); check("adjust by one", m.chosenMinutes == 2)
        m.adjust(by: -50); check("adjust clamps at one minute", m.chosenMinutes == 1)
        m.selectPhase(.rest); check("select break phase", m.phase == .rest && m.display == .restReady)
        m.selectPhase(.focus); check("back to focus", m.phase == .focus)

        // fast cycle: focus -> done -> break -> focus ready, twice, second break is long
        guard speed != "1" else { log("      skipping cycle checks (no speed multiplier)"); return }
        m.start()
        check("start runs", m.display == .running)
        m.extend(minutes: 1)
        check("extend adds time while running", m.total == 120 && m.remaining > 60, "total \(m.total) remaining \(m.remaining)")
        m.reset()
        check("reset clears extra time", m.total == 60 && m.display == .idle)

        m.start()
        let done = await waitUntil(8) { m.display == .done }
        check("focus session ends on Done", done && m.sessions == 1)
        let resting = await waitUntil(8) { m.display == .resting }
        check("break starts automatically", resting && m.phase == .rest && !m.isLongBreak, "total \(m.total)")
        let ready = await waitUntil(8) { m.display == .idle }
        check("after the break the timer waits in focus", ready && m.phase == .focus)

        m.start()
        _ = await waitUntil(8) { m.display == .done }
        let longBreak = await waitUntil(8) { m.display == .resting }
        check("second session earns a long break", longBreak && m.isLongBreak && m.total == 120, "total \(m.total) long \(m.isLongBreak)")
        m.skip()
        check("skip leaves the break", m.phase == .focus && !m.running)
    }

    @MainActor
    private static func screenText(_ e: TerminalEmulator) -> String {
        var out = ""
        for r in 0..<e.rows {
            guard let line = e.line(at: e.usingAlt ? r : e.scrollback.count + r) else { continue }
            for c in line where c.wide != 2 { out.unicodeScalars.append(Unicode.Scalar(c.ch == 0 ? 32 : c.ch) ?? " ") }
            out += "\n"
        }
        return out
    }

    @MainActor
    private static func testTerminal() async {
        var st = PanelSettings()
        st.startCommand = "echo STARTUP_$((4+4))"
        st.startDirectory = "/tmp"
        st.termFont = "Menlo"
        let panel = Panel(kind: .terminal, settings: st)
        let tc = Runtime.shared.terminal(for: panel)
        let win = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 820, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        let container = HostContainer(frame: NSRect(x: 0, y: 0, width: 820, height: 520))
        win.contentView = container
        container.attach(tc.view, steal: true)
        tc.apply(settings: st, theme: .granite)
        container.layoutSubtreeIfNeeded()
        tc.view.layoutSubtreeIfNeeded()
        tc.startIfNeeded()
        check("terminal computes a grid", tc.view.cols > 20 && tc.view.rows > 5, "\(tc.view.cols)x\(tc.view.rows)")
        let started = await waitUntil(8) { screenText(tc.emulator).contains("STARTUP_8") }
        check("shell starts and runs the startup command", started)
        tc.send("pwd\r")
        let inTmp = await waitUntil(5) { screenText(tc.emulator).contains("/tmp") || screenText(tc.emulator).contains("/private/tmp") }
        check("startup folder is respected", inTmp)
        tc.send("printf '\\033[31mRED\\033[0m %s\\n' $((6*7))\r")
        let sgr = await waitUntil(5) { screenText(tc.emulator).contains("RED 42") }
        check("terminal renders command output and colors", sgr)
        tc.send("exit\r")
        let exited = await waitUntil(5) { tc.exited }
        check("shell exit is detected", exited)
        Runtime.shared.release(panel.id)
    }

    @MainActor
    private static func testWeb() async {
        var st = PanelSettings()
        st.customCSS = "h1 { color: rgb(255, 0, 0); }"
        st.forceDark = true
        let panel = Panel(kind: .web, settings: st)
        let wc = Runtime.shared.web(for: panel)
        let win = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 700, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = wc.webView
        wc.apply(settings: st)
        wc.webView.loadHTMLString("<html><body><h1 id='t'>hello</h1></body></html>", baseURL: nil)
        _ = await waitUntil(8) { !wc.webView.isLoading && wc.webView.url != nil }
        await sleep(0.5)
        func js(_ s: String) async -> String {
            await withCheckedContinuation { cont in
                wc.webView.evaluateJavaScript(s) { v, _ in cont.resume(returning: "\(v ?? "nil")") }
            }
        }
        let css = await js("(document.getElementById('panels-css')||{}).textContent || ''")
        check("custom CSS and force dark are injected", css.contains("rgb(255, 0, 0)") && css.contains("invert"), String(css.prefix(60)))
        let color = await js("getComputedStyle(document.getElementById('t')).color")
        check("injected CSS takes effect on the page", color.contains("255, 0, 0"), color)
        st.customCSS = ""; st.forceDark = false
        wc.apply(settings: st)
        await sleep(0.4)
        let removed = await js("document.getElementById('panels-css') ? 'present' : 'gone'")
        check("clearing tweaks removes the style", removed == "gone", removed)
        check("address normalization", WebController.normalize("example.com")?.absoluteString == "https://example.com"
              && WebController.normalize("two words")?.host == "www.google.com")

        // find in page
        wc.webView.loadHTMLString("<html><body><p>alpha beta gamma</p></body></html>", baseURL: nil)
        _ = await waitUntil(8) { !wc.webView.isLoading }
        await sleep(0.3)
        wc.findText = "beta"; wc.find()
        _ = await waitUntil(3) { wc.findFound != nil }
        check("find in page finds a match", wc.findFound == true)
        wc.findText = "zzzz"; wc.find()
        _ = await waitUntil(3) { wc.findFound == false }
        check("find in page reports no match", wc.findFound == false)
        wc.findOpen = true; wc.closeFind()
        check("closing find resets state", !wc.findOpen && wc.findFound == nil)

        // pdf export
        let pdf: Data? = await withCheckedContinuation { cont in
            wc.webView.createPDF { r in cont.resume(returning: try? r.get()) }
        }
        check("page can be exported to PDF", (pdf?.count ?? 0) > 100 && pdf?.prefix(4) == Data("%PDF".utf8))

        // user agent carries a Safari token
        let ua = await js("navigator.userAgent")
        check("user agent has a Safari token", ua.contains("Safari/605.1.15") && ua.contains("Version/"), ua)

        // popups become new web panels built from WebKit's configuration
        let before = Workspace.shared.space.panels.count
        let knownIDs = Set(Workspace.shared.space.panels.map(\.id))
        let popupView = wc.makePopup(configuration: WKWebViewConfiguration())
        let popupPanel = Workspace.shared.space.panels.first { !knownIDs.contains($0.id) }
        check("popup opens a new web panel", Workspace.shared.space.panels.count == before + 1 && popupPanel?.kind == .web, "before \(before) after \(Workspace.shared.space.panels.count) kind \(String(describing: popupPanel?.kind))")
        if let pp = popupPanel {
            check("popup uses the web view WebKit asked for", Runtime.shared.web(for: pp).webView === popupView)
            Workspace.shared.close(pp.id)
            Runtime.shared.release(pp.id)
        }

        // downloads go to the download folder with unique names
        let dlDir = FileManager.default.temporaryDirectory.appendingPathComponent("panels-dl-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dlDir, withIntermediateDirectories: true)
        DownloadFolder.override = dlDir
                var started: DownloadItem?
        let server = LoopbackServer(body: "hello", filename: "served.txt")
        wc.startDownload(URLRequest(url: server.url)) { started = $0 }
        _ = await waitUntil(8) { started?.finished == true }
        check("download finishes and lands in the folder", started?.finished == true
              && (started?.destination.map { FileManager.default.fileExists(atPath: $0.path) } ?? false),
              started?.destination?.lastPathComponent ?? "no item")
        check("download uses the server filename and unique names", started?.destination?.lastPathComponent == "served.txt"
              && DownloadFolder.uniqueURL(for: "served.txt").lastPathComponent == "served 2.txt")
        server.stop()
        DownloadFolder.override = nil
        try? FileManager.default.removeItem(at: dlDir)

        // remembered permissions
        SitePermissions.shared.remember(host: "selftest.example", .camera, allow: true)
        check("permission answer is remembered", SitePermissions.shared.answer(host: "selftest.example", .camera) == true)
        SitePermissions.shared.reset(host: "selftest.example")
        check("permission reset clears it", SitePermissions.shared.answer(host: "selftest.example", .camera) == nil)

        // error page copy
        let page = WebDialogs.errorPage(for: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost), url: URL(string: "https://nope.example"))
        check("error page names the host", page.contains("nope.example") && !page.contains("\u{2014}"))

        // passkey probe (information only; real sign in needs the Apple browser entitlement)
        wc.webView.loadHTMLString("<html><body>probe</body></html>", baseURL: URL(string: "https://example.com"))
        _ = await waitUntil(8) { !wc.webView.isLoading }
        let probe = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            wc.webView.callAsyncJavaScript("""
            if (!window.PublicKeyCredential) { return 'no PublicKeyCredential'; }
            const p = await Promise.race([PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable().then(String).catch(e => 'error ' + e.name), new Promise(r => setTimeout(() => r('timeout'), 3000))]);
            return 'PublicKeyCredential present, platform authenticator: ' + p;
            """, arguments: [:], in: nil, in: .page) { r in
                switch r { case .success(let v): cont.resume(returning: "\(v ?? "nil")"); case .failure(let e): cont.resume(returning: "js error \(e.localizedDescription)") }
            }
        }
        log("INFO  passkey probe: \(probe)")
        Runtime.shared.release(panel.id)
    }

    @MainActor
    private static func testEditor() {
        let panel = Panel(kind: .note, text: "See [[Welcome]] and **bold** text\n- [ ] task\n\nnext\n")
        let host = Runtime.shared.noteHost(for: panel)
        host.apply(settings: panel.settings, theme: .granite)
        let tv = host.textView
        let ns = tv.string as NSString
        let linkIdx = ns.range(of: "Welcome").location
        let boldIdx = ns.range(of: "bold").location
        let base = tv.textStorage?.attribute(.foregroundColor, at: ns.range(of: "text").location, effectiveRange: nil) as? NSColor
        let linkColor = tv.textStorage?.attribute(.foregroundColor, at: linkIdx, effectiveRange: nil) as? NSColor
        check("wiki link is styled", linkColor != nil && linkColor != base)
        let boldFont = tv.textStorage?.attribute(.font, at: boldIdx, effectiveRange: nil) as? NSFont
        check("bold text uses a bold face", boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        // custom family from the font picker
        var st = panel.settings
        st.fontFamily = "Georgia"
        host.apply(settings: st, theme: .granite)
        let f = tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        check("custom font family is applied", f?.familyName == "Georgia", f?.familyName ?? "nil")

        // live dictation: ghost text then final
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        host.dictation("hello um wor", final: false, prefs: DictationPrefs())
        let ghost = tv.string.contains("Hello wor")
        host.dictation("hello um world new paragraph second", final: true, prefs: DictationPrefs())
        host.endDictation()
        check("dictation shows partial text then replaces it with the final", ghost && tv.string.contains("Hello world\n\nSecond") && !tv.string.contains("wor\n"),
              tv.string.suffix(40).replacingOccurrences(of: "\n", with: "|"))
        check("dictated text syncs to the panel", panel.text.contains("Hello world"))

        // typing snippet through the real text view
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        tv.insertText("\n;todo", replacementRange: NSRange(location: NSNotFound, length: 0))
        tv.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        check("typing a snippet expands it", tv.string.hasSuffix("- [ ] "), String(tv.string.suffix(12)))

        // auto title
        let p2 = Panel(kind: .note, title: "Untitled")
        let h2 = Runtime.shared.noteHost(for: p2)
        h2.apply(settings: p2.settings, theme: .granite)
        h2.textView.insertText("# My Heading\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        check("note takes its first heading as the title", p2.title == "My Heading", p2.title)
        Runtime.shared.release(panel.id); Runtime.shared.release(p2.id)
    }

    @MainActor
    private static func testSound() async {
        let settings = SoundSettings.shared
        let saved = settings.prefs
        var p = SoundPrefs()
        p.masterEnabled = true
        p.ambientEnabled = true
        p.layers = [AmbientLayer.rain.rawValue: 0.5, AmbientLayer.ocean.rawValue: 0.3]
        settings.prefs = p
        Sound.play(.open)
        Sound.type(.key)
        Sound.lockIn(true)
        await sleep(0.8)
        Sound.type(.space); Sound.type(.enter); Sound.play(.success); Sound.dictating(true)
        await sleep(0.5)
        log("      audio engine running: \(SoundEngine.shared.isEngineRunning)")
        check("sound engine starts without crashing", true)
        for pack in UIPack.allCases { p.uiPack = pack; settings.prefs = p; Sound.play(.toast) }
        for pack in TypingPack.allCases { p.typingPack = pack; settings.prefs = p; Sound.type(.key) }
        Sound.dictating(false); Sound.lockIn(false)
        p.masterEnabled = false
        settings.prefs = p
        await sleep(0.3)
        check("switching every pack and turning sound off is safe", true)
        settings.prefs = saved
    }

    @MainActor
    private static func testTiling() {
        let min = CGSize(width: 180, height: 110)
        check("balanced grid: 6 panels in a wide window make 3 by 2", TileEngine.gridRows(count: 6, size: CGSize(width: 900, height: 600), gap: 8, minimum: min) == [3, 3])
        check("balanced grid: 6 panels with terminals in a small window still make 3 by 2",
              TileEngine.gridRows(count: 6, size: CGSize(width: 884, height: 584), gap: 8, minimum: CGSize(width: 200, height: 110)) == [3, 3])
        check("balanced grid: 2 panels in a wide window sit side by side", TileEngine.gridRows(count: 2, size: CGSize(width: 1000, height: 500), gap: 8, minimum: min) == [2])
        check("balanced grid: 2 panels in a tall window stack", TileEngine.gridRows(count: 2, size: CGSize(width: 400, height: 900), gap: 8, minimum: min) == [1, 1])
        check("balanced grid: 5 panels never use more columns than fit", (TileEngine.gridRows(count: 5, size: CGSize(width: 760, height: 500), gap: 8, minimum: min).max() ?? 9) <= 3)

        for layout in TileLayout.allCases {
            for n in [1, 2, 3, 5, 8] {
                let ps = (0..<n).map { _ in Panel(kind: .note) }
                let root = TileEngine.build(panels: ps, layout: layout, size: CGSize(width: 1000, height: 650), gap: 8)
                root.normalize()
                let got = root.leaves().compactMap { $0.panel?.id }
                var ids: [UUID] = []
                check("tile \(layout.rawValue) with \(n): every panel once, in order, valid tree",
                      got == ps.map(\.id) && validate(root, &ids))
            }
        }

        let ws = Workspace.shared
        let before = ws.spaces.count
        ws.newSpace()
        check("new workspaces start with auto tiling", ws.space.tiling == .balanced && ws.spaces.count == before + 1)
        for _ in 0..<4 { ws.addPanel(.note) }
        check("auto tile keeps a valid tree while adding panels", ws.space.panels.count == 5 && treeOK(ws))
        ws.close(ws.space.panels[2].id)
        check("auto tile re-arranges after a close", ws.space.panels.count == 4 && treeOK(ws) && ws.space.tiling == .balanced)

        ws.setTiling(.columns)
        check("columns layout puts everything in one row", ws.space.root.axis == .horizontal && ws.space.root.children.count == 4)
        let order = ws.space.panels.map(\.id)
        ws.space.focusedID = order[0]
        ws.frames = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, CGRect(x: CGFloat($0) * 100, y: 0, width: 90, height: 100)) })
        ws.swapFocused(.right)
        let swapped = ws.space.panels.map(\.id)
        check("swap moves the focused panel one place", swapped[0] == order[1] && swapped[1] == order[0] && swapped.count == order.count)

        ws.contentSize = CGSize(width: 3000, height: 900)
        let w0 = ws.space.root.weights
        ws.space.focusedID = swapped[0]
        ws.resizeFocused(.horizontal, grow: true)
        check("resize grows the focused panel and shrinks a neighbour", ws.space.root.weights[0] > w0[0] && ws.space.root.weights[1] < w0[1]
              && abs(ws.space.root.weights.reduce(0, +) - w0.reduce(0, +)) < 0.0001)

        for _ in 0..<40 { ws.resizeFocused(.horizontal, grow: false) }
        let rw = ws.space.root.weights, rs = rw.reduce(0, +)
        let rGap = CGFloat(Appearance.shared.gap)
        let rTotal = ws.layoutArea(ws.contentSize).width - rGap * CGFloat(rw.count - 1)
        let rMin = ws.space.root.children[0].minExtent(along: .horizontal, gap: rGap)
        check("keyboard resize stops at the panel minimum", CGFloat(rw[0] / rs) * rTotal >= rMin - 1, "\(CGFloat(rw[0] / rs) * rTotal) vs \(rMin)")

        let edgeTarget = ws.space.panels[2]
        ws.move(ws.space.panels[0].id, onto: edgeTarget.id, zone: .right)
        check("docking to an edge switches auto tiling off", ws.space.tiling == nil && treeOK(ws))

        let space = Space(name: "T", root: Node(panel: Panel(kind: .note)))
        space.tiling = .spiral
        let data = try! JSONEncoder().encode(space)
        let back = try! JSONDecoder().decode(Space.self, from: data)
        check("tiling layout survives save and load", back.tiling == .spiral)
        var obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "tiling")
        let legacy = try! JSONDecoder().decode(Space.self, from: JSONSerialization.data(withJSONObject: obj))
        check("old workspaces without a tiling field stay manual", legacy.tiling == nil)
    }

    @MainActor
    private static func testDividerDrag() {
        let sizes: [CGFloat] = [500, 300, 200]
        let a = SplitFit.drag(sizes: sizes, index: 0, translation: 100, minLeft: 280, minRight: 240)
        check("divider follows the cursor", a == [600, 200, 200] || a == [560, 240, 200], "\(a)")
        let b = SplitFit.drag(sizes: sizes, index: 0, translation: -400, minLeft: 280, minRight: 240)
        check("divider stops when the left panel reaches its minimum", b[0] == 280 && b[1] == 520 && b.reduce(0, +) == 1000, "\(b)")
        let c = SplitFit.drag(sizes: sizes, index: 1, translation: 400, minLeft: 240, minRight: 200)
        check("divider stops when the right panel reaches its minimum", c[2] == 200 && c[1] == 300 && b.reduce(0, +) == c.reduce(0, +), "\(c)")
        let d = SplitFit.drag(sizes: [250, 300], index: 0, translation: -50, minLeft: 280, minRight: 240)
        check("a panel already under its minimum cannot be squashed further", d[0] == 250, "\(d)")
        let e = SplitFit.drag(sizes: [250, 300], index: 0, translation: 40, minLeft: 280, minRight: 240)
        check("a panel under its minimum can be pulled back up", e[0] == 290 && e[1] == 260, "\(e)")
    }

    @MainActor
    private static func testHardMinimums() {
        for k in PanelKind.allCases {
            let m = PanelSize.minimum(for: k)
            check("\(k.rawValue) panel minimum is at least 300 by 220", m.width >= 300 && m.height >= 220, "\(m)")
        }
        let ws = Workspace.shared
        ws.newSpace()
        let s = ws.space
        ws.maxContentOverride = CGSize(width: 1400, height: 900)
        for _ in 0..<3 { ws.addPanel(.note) }
        ws.contentSize = CGSize(width: 900, height: 600)
        let a = ws.requiredContentSize(for: s)
        ws.contentSize = CGSize(width: 30000, height: 600)
        let b = ws.requiredContentSize(for: s)
        check("required window size does not depend on the current window size", a == b, "\(a) vs \(b)")
        check("required window size stays within the screen when it fits", a.width <= 1400 && a.height <= 900 && ws.fits(s))
        check("required window size is not a thin strip", a.width / a.height < 3 && a.height / a.width < 3, "\(a)")

        // small screen: keep adding until refused, never past the screen
        ws.maxContentOverride = CGSize(width: 1000, height: 700)
        var added = 0
        while ws.addPanel(.note) != nil, added < 20 { added += 1 }
        check("adding stops when panels would drop under their minimum", added < 20 && ws.space.panels.count >= 1 && ws.fits(ws.space), "added \(added)")
        let need = ws.requiredContentSize(for: ws.space)
        check("after a refusal the layout still fits the screen", need.width <= 1000.5 && need.height <= 700.5 && treeOK(ws), "\(need)")

        // with room, the balanced grid keeps every cell at its minimum
        let ps = (0..<5).map { _ in Panel(kind: .note) }
        let area = CGSize(width: 1000, height: 700)
        let rows = TileEngine.gridRows(count: 5, size: area, gap: 8, minimum: TileEngine.minimum(for: ps))
        let cols = rows.max() ?? 1
        let cellW = (area.width - 8 * CGFloat(cols - 1)) / CGFloat(cols)
        let cellH = (area.height - 8 * CGFloat(rows.count - 1)) / CGFloat(rows.count)
        check("balanced grid keeps cells above the minimum when it can", cellW >= 280 && cellH >= 200, "\(rows) \(cellW)x\(cellH)")
        ws.maxContentOverride = nil
    }

    @MainActor
    private static func testNoteEditing() {
        func makeHost(_ text: String, _ mutate: (inout PanelSettings) -> Void = { _ in }) -> (Panel, NoteEditorHost, NSWindow) {
            var st = PanelSettings()
            st.lineHeight = 1.9
            mutate(&st)
            let panel = Panel(kind: .note, text: text, settings: st)
            let host = Runtime.shared.noteHost(for: panel)
            let win = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 500, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
            host.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
            win.contentView = host.scrollView
            host.apply(settings: st, theme: .granite)
            host.scrollView.layoutSubtreeIfNeeded()
            win.makeFirstResponder(host.textView)
            return (panel, host, win)
        }

        // caret is sized to the font, not the tall line box
        let (p1, h1, w1) = makeHost("Hello world")
        h1.textView.setSelectedRange(NSRange(location: 5, length: 0))
        let font = h1.textView.baseFont
        let rect = h1.textView.caretRect()
        let lineRect = h1.textView.layoutManager!.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        check("caret height matches the font, not the line box",
              rect != nil && abs(rect!.height - (font.ascender - font.descender)) < 1 && rect!.height < lineRect.height - 4,
              "caret \(rect?.height ?? 0) font \(font.ascender - font.descender) line \(lineRect.height)")
        let glyphLoc = h1.textView.layoutManager!.location(forGlyphAt: 0)
        check("extra line spacing sits above the text (caret placement assumption)",
              abs(glyphLoc.y - (lineRect.height - abs(font.descender))) < 2, "baseline \(glyphLoc.y) expected \(lineRect.height - abs(font.descender))")
        if let r = rect {
            let top = h1.textView.textContainerOrigin.y + lineRect.minY + glyphLoc.y - font.ascender
            check("caret sits on the text baseline", abs(r.minY - top) < 1)
        }
        h1.apply(settings: { var s = p1.settings; s.noteCaret = .block; return s }(), theme: .granite)
        h1.textView.setSelectedRange(NSRange(location: 1, length: 0))
        check("block caret is as wide as a character", (h1.textView.caretRect()?.width ?? 0) > 4)
        h1.apply(settings: { var s = p1.settings; s.noteCaret = .underline; return s }(), theme: .granite)
        check("underline caret is thin", (h1.textView.caretRect()?.height ?? 99) <= 3)
        let (_, hEmpty, wEmpty) = makeHost("")
        check("caret can be placed in an empty note", hEmpty.textView.caretRect() != nil)
        check("empty note has a placeholder", !hEmpty.textView.placeholder.isEmpty)
        Runtime.shared.release(p1.id); w1.contentView = nil; wEmpty.contentView = nil

        // alignment reaches every paragraph, headings included
        let (p2, h2, w2) = makeHost("# Title\n\nbody text") { $0.textAlign = .center }
        let st2 = h2.textView.textStorage!
        let a0 = (st2.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment
        let a1 = (st2.attribute(.paragraphStyle, at: st2.length - 1, effectiveRange: nil) as? NSParagraphStyle)?.alignment
        check("text alignment applies to headings and body", a0 == .center && a1 == .center)
        Runtime.shared.release(p2.id); w2.contentView = nil

        // markdown symbols hide off the active line and show on it
        let (p3, h3, w3) = makeHost("# Title\nsome **bold** text")
        h3.textView.setSelectedRange(NSRange(location: 2, length: 0))
        let ns3 = h3.textView.string as NSString
        let hashSize = (h3.textView.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 99
        let starIdx = ns3.range(of: "**").location
        let starSize = (h3.textView.textStorage!.attribute(.font, at: starIdx, effectiveRange: nil) as? NSFont)?.pointSize ?? 99
        check("symbols stay visible on the active line", hashSize > 4, "\(hashSize)")
        check("symbols hide on other lines", starSize < 1, "\(starSize)")
        h3.textView.setSelectedRange(NSRange(location: starIdx + 4, length: 0))
        let hashAfter = (h3.textView.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 99
        let starAfter = (h3.textView.textStorage!.attribute(.font, at: starIdx, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
        check("symbols swap when the caret moves lines", hashAfter < 1 && starAfter > 4, "hash \(hashAfter) star \(starAfter)")
        check("hidden symbols do not change the text", h3.textView.string == "# Title\nsome **bold** text" && p3.text == "# Title\nsome **bold** text")
        Runtime.shared.release(p3.id); w3.contentView = nil

        // toolbar formatting
        let (p4, h4, w4) = makeHost("one\ntwo\nthree") { $0.hideMarks = false }
        let tv = h4.textView
        tv.setSelectedRange(NSRange(location: 0, length: 3))
        tv.apply(.bold)
        check("bold wraps the selection", tv.string.hasPrefix("**one**"), tv.string)
        tv.apply(.bold)
        check("bold again takes it off", tv.string.hasPrefix("one\n"), tv.string)
        tv.setSelectedRange(NSRange(location: 0, length: (tv.string as NSString).length))
        tv.apply(.bullet)
        check("bullet list on every selected line", tv.string == "- one\n- two\n- three", tv.string)
        tv.apply(.bullet)
        check("bullet again takes it off", tv.string == "one\ntwo\nthree", tv.string)
        tv.apply(.numbered)
        check("numbered list counts up", tv.string == "1. one\n2. two\n3. three", tv.string)
        tv.apply(.heading(2))
        check("heading replaces the list prefix", tv.string == "## one\n## two\n## three", tv.string)
        tv.apply(.heading(0))
        check("normal text removes the heading", tv.string == "one\ntwo\nthree", tv.string)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.apply(.checklist)
        check("checklist on one line", tv.string.hasPrefix("- [ ] one\ntwo"), tv.string)
        Runtime.shared.release(p4.id); w4.contentView = nil
    }

    @MainActor
    private static func testSiteZoom() {
        let z = SiteZoom.shared
        z.remember(host: "Example.COM", zoom: 1.5)
        check("site zoom is remembered per host, ignoring case", z.zoom(host: "example.com") == 1.5 && z.zoom(host: "other.com") == nil)
        z.remember(host: "example.com", zoom: 1)
        check("zoom back to 100 percent clears the entry", z.zoom(host: "example.com") == nil)
    }

    @MainActor
    private static func testDictationGate() {
        typealias G = DictationController
        check("mic gate: authorized goes straight through", G.gate(for: .authorized, primed: false) == .proceed)
        check("mic gate: first time shows the priming card", G.gate(for: .notDetermined, primed: false) == .prime)
        check("mic gate: after priming the system prompt may run", G.gate(for: .notDetermined, primed: true) == .proceed)
        check("mic gate: denied shows the recovery card", G.gate(for: .denied, primed: true) == .denied && G.gate(for: .restricted, primed: false) == .denied)
    }

    @MainActor
    private static func testOnboarding() {
        check("onboarding stays closed during the self test", !Onboarding.shouldShow && !Workspace.shared.onboardingOpen)
        let ids = TemplateStore.builtins.map(\.id)
        check("builtin templates have stable ids", ids == TemplateStore.builtins.map(\.id) && Set(ids).count == ids.count)
        let before = Workspace.shared.spaces.count
        Workspace.shared.newSpace(from: TemplateStore.builtins[1])
        check("a starting template adds one workspace", Workspace.shared.spaces.count == before + 1 && treeOK(Workspace.shared))
    }

    @MainActor
    private static func testTaskRemoval() {
        let p = Panel(kind: .tasks, title: "T", text: "", tasks: [TaskItem(title: "a"), TaskItem(title: "b")])
        let id = p.tasks[0].id
        p.removeTask(id)
        check("removing a task by id leaves the others", p.tasks.count == 1 && p.tasks[0].title == "b")
    }

    @MainActor
    private static func testSizeClasses() {
        check("size class tiny", PanelSize.classify(CGSize(width: 120, height: 80)) == .tiny)
        check("size class small", PanelSize.classify(CGSize(width: 240, height: 150)) == .small)
        check("size class regular", PanelSize.classify(CGSize(width: 320, height: 300)) == .regular)
        check("size class roomy", PanelSize.classify(CGSize(width: 800, height: 600)) == .roomy)
        let even = SplitFit.sizes(weights: [1, 1], mins: [100, 100], total: 600)
        check("split fit keeps even weights", even == [300, 300])
        let squeezed = SplitFit.sizes(weights: [9, 1], mins: [100, 200], total: 600)
        check("split fit lifts a small child to its minimum", squeezed[1] == 200 && abs(squeezed.reduce(0, +) - 600) < 0.01, "\(squeezed)")
        let cramped = SplitFit.sizes(weights: [1, 1], mins: [400, 400], total: 600)
        check("split fit degrades evenly when minimums cannot fit", abs(cramped.reduce(0, +) - 600) < 0.01 && cramped[0] == cramped[1])
    }

    @MainActor
    private static func testDataSafety() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("panels-safety-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("workspace.json")
        check("load with no file returns nil and no notice", Persistence.load(from: file) == nil && Persistence.loadNotice == nil)
        try? Data("{ not json".utf8).write(to: file)
        let snap = Persistence.load(from: file)
        let kept = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("workspace.corrupt-") }
        check("unreadable workspace is moved aside, not lost", snap == nil && kept.count == 1 && !fm.fileExists(atPath: file.path))
        check("unreadable workspace sets a notice", Persistence.loadNotice != nil)
        Persistence.loadNotice = nil
        let old = WorkspaceSnapshot(spaces: Workspace.shared.spaces, active: Workspace.shared.activeSpaceID, popouts: nil)
        try? JSONEncoder().encode(old).write(to: file)
        check("old file without schemaVersion still loads", Persistence.load(from: file) != nil)
        let bdir = dir.appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: bdir, withIntermediateDirectories: true)
        let t0 = Date()
        check("first backup is written", Persistence.backupIfDue(file: file, into: bdir, now: t0))
        check("second backup within interval is skipped", !Persistence.backupIfDue(file: file, into: bdir, now: t0.addingTimeInterval(5)))
        for i in 1...4 { Persistence.backupIfDue(file: file, into: bdir, interval: 0, keep: 3, now: t0.addingTimeInterval(Double(i) * 1000)) }
        let n = ((try? fm.contentsOfDirectory(atPath: bdir.path)) ?? []).count
        check("backups are pruned to the keep count", n == 3, "\(n)")
    }

    @MainActor
    private static func testSettingsCodable() {
        var st = PanelSettings()
        st.fontFamily = "Georgia"; st.customCSS = "a{}"; st.startCommand = "ls"; st.termFont = "Menlo"; st.sessionsBeforeLong = 3
        let data = try! JSONEncoder().encode(st)
        let back = try! JSONDecoder().decode(PanelSettings.self, from: data)
        check("panel settings round trip", back == st)
        let legacy = try? JSONDecoder().decode(PanelSettings.self, from: Data(#"{"fontSize":17}"#.utf8))
        check("old saved settings still load with defaults", legacy?.fontSize == 17 && legacy?.focusMinutes == 25)
    }
}
