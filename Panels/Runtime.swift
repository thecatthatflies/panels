import SwiftUI
import AppKit

/// Keeps live, non-serializable objects (shells, web views, editors, timers) alive
/// independently of SwiftUI view identity so layout changes never kill a session.
final class Runtime {
    static let shared = Runtime()

    private var terminals: [UUID: TerminalController] = [:]
    private var webs: [UUID: WebController] = [:]
    private var notes: [UUID: NoteEditorHost] = [:]
    private var timers: [UUID: TimerModel] = [:]

    // MARK: factories

    func terminal(for panel: Panel) -> TerminalController {
        if let t = terminals[panel.id] { return t }
        let t = TerminalController(panel: panel)
        let id = panel.id
        t.view.onFocus = { Workspace.shared.focus(id, grabFirstResponder: false) }
        terminals[id] = t
        return t
    }

    func web(for panel: Panel) -> WebController {
        if let w = webs[panel.id] { return w }
        let w = WebController(panel: panel)
        let id = panel.id
        w.webView.onFocus = { Workspace.shared.focus(id, grabFirstResponder: false) }
        webs[id] = w
        return w
    }

    func noteHost(for panel: Panel) -> NoteEditorHost {
        if let h = notes[panel.id] { return h }
        let h = NoteEditorHost(panel: panel)
        notes[panel.id] = h
        return h
    }

    func timer(for panel: Panel) -> TimerModel {
        if let t = timers[panel.id] { return t }
        let t = TimerModel(panel: panel)
        timers[panel.id] = t
        return t
    }

    // MARK: lifecycle

    func release(_ id: UUID) {
        terminals[id]?.terminate()
        terminals[id] = nil
        webs[id]?.webView.stopLoading()
        webs[id] = nil
        notes[id] = nil
        timers[id]?.pause()
        timers[id] = nil
    }

    func releaseWeb(_ id: UUID) {
        webs[id]?.webView.stopLoading()
        webs[id] = nil
    }

    func terminateAll() {
        terminals.values.forEach { $0.terminate() }
    }

    func makeFirstResponder(for id: UUID) {
        let view: NSView?
        if let t = terminals[id] { view = t.view }
        else if let w = webs[id] { view = w.webView }
        else if let n = notes[id] { view = n.textView }
        else { view = nil }
        guard let v = view, let window = v.window else { return }
        window.makeFirstResponder(v)
    }

    /// Native views swallow drag sessions, so hide them while a panel is being dragged.
    func setDragging(_ on: Bool) {
        terminals.values.forEach { $0.view.isHidden = on }
        webs.values.forEach { $0.webView.isHidden = on }
        notes.values.forEach { $0.scrollView.isHidden = on }
    }
}
