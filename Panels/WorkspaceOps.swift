import SwiftUI
import AppKit
import Observation

// MARK: - Deep copy

extension Node {
    func deepCopy() -> Node {
        if let p = panel {
            let copy = Panel(kind: p.kind, title: p.title, text: p.text, url: p.url,
                             tasks: p.tasks.map { TaskItem(title: $0.title, done: $0.done) }, settings: p.settings)
            return Node(panel: copy)
        }
        return Node(axis: axis, children: children.map { $0.deepCopy() }, weights: weights)
    }
}

// MARK: - Templates

struct TemplateNode: Codable {
    var kind: PanelKind?
    var title: String?
    var text: String?
    var url: String?
    var settings: PanelSettings?
    var axis: SplitAxis?
    var children: [TemplateNode]?
    var weights: [Double]?

    static func leaf(_ kind: PanelKind, _ title: String? = nil, text: String = "", url: String = "",
                     settings: PanelSettings? = nil) -> TemplateNode {
        TemplateNode(kind: kind, title: title, text: text, url: url, settings: settings)
    }

    static func split(_ axis: SplitAxis, _ children: [TemplateNode], _ weights: [Double]) -> TemplateNode {
        TemplateNode(axis: axis, children: children, weights: weights)
    }

    func build() -> Node {
        if let kind {
            let p = Panel(kind: kind, title: title, text: text ?? "", url: url ?? "", settings: settings ?? PanelSettings())
            return Node(panel: p)
        }
        let kids = (children ?? []).map { $0.build() }
        return Node(axis: axis ?? .horizontal, children: kids, weights: weights)
    }

    static func capture(_ node: Node, includeText: Bool) -> TemplateNode {
        if let p = node.panel {
            return TemplateNode(kind: p.kind, title: p.title, text: includeText ? p.text : "", url: p.url, settings: p.settings)
        }
        return TemplateNode(axis: node.axis, children: node.children.map { capture($0, includeText: includeText) },
                            weights: node.weights)
    }
}

struct LayoutTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var symbol: String
    var root: TemplateNode
    var builtin = false
}

@Observable
final class TemplateStore {
    static let shared = TemplateStore()

    var saved: [LayoutTemplate] {
        didSet { persist() }
    }

    private static var fileURL: URL {
        let dir = AppPaths.dir
        return dir.appendingPathComponent("templates.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([LayoutTemplate].self, from: data) {
            saved = decoded
        } else {
            saved = []
        }
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(saved) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    static let builtins: [LayoutTemplate] = {
        var pad0 = PanelSettings(); pad0.padding = 0
        var serif = PanelSettings(); serif.font = .serif; serif.fontSize = 17; serif.measure = 680; serif.padding = 34
        var tasks = PanelSettings(); tasks.padding = 16; tasks.accent = .wood
        var term = PanelSettings(); term.padding = 14; term.accent = .granite
        return [
            LayoutTemplate(name: "Blank", symbol: "square.dashed", root: .leaf(.note, "Untitled"), builtin: true),
            LayoutTemplate(name: "Writer", symbol: "pencil.and.outline",
                           root: .split(.horizontal, [
                            .leaf(.note, "Draft", settings: serif),
                            .split(.vertical, [.leaf(.note, "Notes"), .leaf(.tasks, "To do", settings: tasks)], [1.3, 1])
                           ], [2, 1]), builtin: true),
            LayoutTemplate(name: "Research", symbol: "text.book.closed",
                           root: .split(.horizontal, [.leaf(.web, "Source"), .leaf(.note, "Notes")], [1.4, 1]), builtin: true),
            LayoutTemplate(name: "Developer", symbol: "chevron.left.forwardslash.chevron.right",
                           root: .split(.horizontal, [
                            .leaf(.terminal, "Shell", settings: term),
                            .split(.vertical, [.leaf(.note, "Scratch"), .leaf(.tasks, "Tasks", settings: tasks)], [1.4, 1])
                           ], [1.5, 1]), builtin: true),
            LayoutTemplate(name: "Daily", symbol: "sun.max",
                           root: .split(.horizontal, [
                            .leaf(.tasks, "Today", settings: tasks),
                            .leaf(.note, "Journal", settings: serif),
                            .leaf(.timer, "Focus")
                           ], [1, 1.6, 0.9]), builtin: true)
        ]
    }()

    var all: [LayoutTemplate] { Self.builtins + saved }

    func remove(_ id: UUID) { saved.removeAll { $0.id == id } }
}

// MARK: - Workspace operations

extension Workspace {
    // MARK: files

    func wordCount(of p: Panel?) -> Int {
        guard let t = p?.text else { return 0 }
        var words = 0
        var inWord = false
        for u in t.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(u) { inWord = false }
            else if !inWord { inWord = true; words += 1 }
        }
        return words
    }

    // MARK: focus mode (lock in)

    func toggleFocusMode() {
        if focusMode { exitFocusMode() } else { enterFocusMode() }
    }

    func enterFocusMode() {
        guard !focusMode, let f = focused else { return }
        paletteOpen = false
        preFocusZoom = space.zoomedID
        focusStart = Date()
        focusStartWords = wordCount(of: f)
        withAnimation(.smooth(duration: 0.55)) {
            space.zoomedID = f.id
            focusMode = true
        }
        WindowChrome.refresh(animated: true)
        WindowChrome.setTrafficLights(hidden: true)
        Sound.play(.lockIn)
        Sound.lockIn(true)
        Runtime.shared.makeFirstResponder(for: f.id)
    }

    func exitFocusMode() {
        guard focusMode else { return }
        withAnimation(.smooth(duration: 0.5)) {
            focusMode = false
            space.zoomedID = preFocusZoom
        }
        WindowChrome.refresh(animated: true)
        WindowChrome.setTrafficLights(hidden: false)
        Sound.play(.lockOut)
        Sound.lockIn(false)
        preFocusZoom = nil
        if let f = space.focusedID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Runtime.shared.makeFirstResponder(for: f) }
        }
    }

    // MARK: workspaces

    func renameSpace(_ id: UUID, to name: String) {
        guard let s = spaces.first(where: { $0.id == id }) else { return }
        s.name = name
    }

    func duplicateSpace(_ id: UUID) {
        guard let src = spaces.first(where: { $0.id == id }) else { return }
        let copy = Space(name: src.name + " copy", root: src.root.deepCopy(), symbol: src.symbol, tint: src.tint, themeID: src.themeID)
        guard let idx = spaces.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Motion.swap) {
            spaces.insert(copy, at: idx + 1)
            activeSpaceID = copy.id
        }
        Persistence.markDirty()
        showToast("Duplicated \(src.name)")
    }

    func moveSpace(_ id: UUID, by delta: Int) {
        guard let i = spaces.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0, j < spaces.count else { return }
        withAnimation(Motion.layout) { spaces.swapAt(i, j) }
        Persistence.markDirty()
    }

    func cycleSpace(_ delta: Int) {
        guard spaces.count > 1, let i = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        selectSpace(spaces[(i + delta + spaces.count) % spaces.count].id)
    }

    func newSpace(from template: LayoutTemplate) {
        let root = template.root.build()
        let s = Space(name: template.name, root: root, symbol: template.symbol)
        withAnimation(Motion.swap) {
            spaces.append(s)
            activeSpaceID = s.id
        }
        Persistence.markDirty()
        if let f = s.focusedID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Runtime.shared.makeFirstResponder(for: f) }
        }
    }

    func saveTemplate(named name: String, includeText: Bool = false) {
        let s = space
        let t = LayoutTemplate(name: name.isEmpty ? s.name : name, symbol: s.symbol,
                               root: TemplateNode.capture(s.root, includeText: includeText))
        TemplateStore.shared.saved.append(t)
        showToast("Saved template \(t.name)")
    }

    func move(panel panelID: UUID, toSpace targetID: UUID) {
        guard targetID != activeSpaceID,
              let target = spaces.first(where: { $0.id == targetID }),
              let leaf = space.root.leaf(for: panelID), let panel = leaf.panel else { return }
        let source = space
        withAnimation(Motion.layout) {
            if source.root === leaf {
                source.root = Node.empty()
            } else if let (parent, i) = source.root.parent(of: leaf) {
                parent.children.remove(at: i)
                parent.weights.remove(at: i)
                source.root.normalize()
            }
            if source.zoomedID == panelID { source.zoomedID = nil }
            if source.focusedID == panelID { source.focusedID = source.panels.first?.id }
        }
        if target.root.isEmpty {
            target.root = Node(panel: panel)
        } else if let last = target.root.leaves().last {
            insert(panel, beside: last, axis: .horizontal, before: false, in: target)
        }
        target.focusedID = panel.id
        Persistence.markDirty()
        showToast("Moved to \(target.name)")
    }

    // MARK: size shortcuts

    func adjustSize(_ delta: Int) {
        guard let p = focused else { return }
        switch p.kind {
        case .note: p.settings.fontSize = min(max(p.settings.fontSize + Double(delta), 11), 36)
        case .terminal: p.settings.termFontSize = min(max(p.settings.termFontSize + Double(delta) * 0.5, 8), 28)
        case .web: p.settings.zoom = min(max(p.settings.zoom + Double(delta) * 0.1, 0.4), 3)
        default: break
        }
    }

    func resetSize() {
        guard let p = focused else { return }
        let d = PanelSettings()
        switch p.kind {
        case .note: p.settings.fontSize = d.fontSize
        case .terminal: p.settings.termFontSize = d.termFontSize
        case .web: p.settings.zoom = 1
        default: break
        }
    }

    func setFloating(_ on: Bool) {
        floating = on
        NSApp.windows.filter { $0.canBecomeMain }.forEach { $0.level = on ? .floating : .normal }
    }
}

// MARK: - File import and export

enum FileOps {
    static func openMarkdown() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .init(filenameExtension: "md") ?? .plainText,
                                     .init(filenameExtension: "markdown") ?? .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose markdown or text files to open as notes"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let title = url.deletingPathExtension().lastPathComponent
            let p = Workspace.shared.addPanel(.note, title: title, text: text)
            p.settings.autoTitle = false
        }
    }

    static func saveMarkdown(_ panel: Panel) {
        let sp = NSSavePanel()
        sp.nameFieldStringValue = (panel.title.isEmpty ? "Untitled" : panel.title) + ".md"
        sp.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        sp.canCreateDirectories = true
        guard sp.runModal() == .OK, let url = sp.url else { return }
        do {
            try panel.text.write(to: url, atomically: true, encoding: .utf8)
            Workspace.shared.showToast("Saved \(url.lastPathComponent)")
        } catch {
            Workspace.shared.showToast("Could not save the file")
        }
    }

    static func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.dir])
    }
}


// MARK: - Reopen the last closed panel, workspace or window

extension Workspace {
    var reopenLabel: String {
        guard let last = closedStack.last else { return "Reopen Closed" }
        return "Reopen \(last.label)"
    }

    func reopenLast() {
        guard let item = closedStack.popLast() else { return }
        switch item {
        case .space(let sp, let index):
            let idx = min(index, spaces.count)
            withAnimation(Motion.swap) {
                spaces.insert(sp, at: idx)
                activeSpaceID = sp.id
            }
            Sound.play(.open)
            showToast("Reopened \(sp.name)")

        case .panel(let panel, let spaceID, let siblingID, let axis):
            let target = spaces.first { $0.id == spaceID } ?? space
            if target.id != activeSpaceID { selectSpace(target.id) }
            withAnimation(Motion.layout) {
                if target.root.isEmpty {
                    target.root = Node(panel: panel)
                } else if let sid = siblingID, let sibling = target.root.leaf(for: sid) {
                    insert(panel, beside: sibling, axis: axis, before: false, in: target)
                } else if let last = target.root.leaves().last {
                    insert(panel, beside: last, axis: .horizontal, before: false, in: target)
                }
            }
            target.focusedID = panel.id
            Sound.play(.open)
            showToast("Reopened \(panel.title)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Runtime.shared.makeFirstResponder(for: panel.id) }

        case .popout(let po):
            popouts.append(po)
            PopoutManager.shared.open(po, near: nil)
            Sound.play(.open)
            showToast("Reopened \(po.panel.title)")
        }
        Persistence.markDirty()
    }
}
