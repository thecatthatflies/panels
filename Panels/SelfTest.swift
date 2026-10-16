import SwiftUI
import AppKit

/// Headless self test. Launch with PANELS_SELFTEST=1 (and PANELS_DATA_DIR pointing at a scratch folder).
/// It exercises the real model, runtime and views in-process, writes PASS or FAIL lines to
/// PANELS_SELFTEST_LOG (default /tmp/panels-selftest.log) and then quits. It never runs in normal use.
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
        let a = ws.addPanel(.note, title: "A")
        let b = ws.addPanel(.terminal)
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
        let p = ws.addPanel(.note, title: "ReopenMe", text: "keep this text")
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
        let p = ws.addPanel(.tasks, title: "PopMe")
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
              && WebController.normalize("two words")?.host == "duckduckgo.com")
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
