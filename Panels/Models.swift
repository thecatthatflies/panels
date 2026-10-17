import SwiftUI
import Observation

// MARK: - Basic enums

enum PanelKind: String, Codable, CaseIterable, Identifiable {
    case note, terminal, web, tasks, timer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .note: return "Note"
        case .terminal: return "Terminal"
        case .web: return "Web App"
        case .tasks: return "Tasks"
        case .timer: return "Focus Timer"
        }
    }

    var symbol: String {
        switch self {
        case .note: return "text.alignleft"
        case .terminal: return "terminal"
        case .web: return "globe"
        case .tasks: return "checklist"
        case .timer: return "timer"
        }
    }

    var blurb: String {
        switch self {
        case .note: return "Markdown writing with live styling"
        case .terminal: return "A real shell, right in the panel"
        case .web: return "Any website or web app, pinned in place"
        case .tasks: return "A checklist that lives beside your notes"
        case .timer: return "Focus and break rhythm with a ring"
        }
    }

    var defaultTitle: String {
        switch self {
        case .note: return "Untitled"
        case .terminal: return "Terminal"
        case .web: return "Web"
        case .tasks: return "Tasks"
        case .timer: return "Focus"
        }
    }
}

enum SplitAxis: String, Codable {
    case horizontal   // children sit side by side
    case vertical     // children are stacked
}

enum NoteMode: String, Codable, CaseIterable, Identifiable {
    case edit, split, preview
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .edit: return "pencil.line"
        case .split: return "rectangle.split.2x1"
        case .preview: return "eye"
        }
    }
}

enum SurfaceStyle: String, Codable, CaseIterable, Identifiable {
    case solid, glass, clear
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum CursorStyle: String, Codable, CaseIterable, Identifiable {
    case block, bar, underline
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum DropZone: Equatable {
    case left, right, top, bottom, center
}

enum Direction {
    case left, right, up, down
}

// MARK: - Per-panel settings

struct PanelSettings: Codable, Equatable {
    var accent: AccentID = .theme
    var surface: SurfaceStyle = .solid
    var padding: Double = 22
    var font: EditorFont = .instrument
    var fontFamily: String = ""
    var fontSize: Double = 15
    var lineHeight: Double = 1.5
    var measure: Double = 0
    var wrap: Bool = true
    var richStyling: Bool = true
    var spellcheck: Bool = false
    var showStats: Bool = true
    var noteMode: NoteMode = .edit
    var typewriter: Bool = false
    var dimParagraphs: Bool = false
    var autoTitle: Bool = true
    var paragraphSpacing: Double = 0.2
    var headingScale: Double = 1.0
    var codeScale: Double = 0.88
    var termFontSize: Double = 12.5
    var cursor: CursorStyle = .block
    var shell: String = ""
    var termOpacity: Double = 1.0
    var termFont: String = ""
    var termLineHeight: Double = 1.14
    var startDirectory: String = ""
    var startCommand: String = ""
    var optionAsMeta: Bool = true
    var cursorBlink: Bool = true
    var scrollbackLines: Int = 5000
    var zoom: Double = 1.0
    var mobileUA: Bool = false
    var showAddressBar: Bool = true
    var customCSS: String = ""
    var forceDark: Bool = false
    var blockTrackers: Bool = false
    var appMode: Bool = false
    var isolatedSession: Bool = false
    var refreshMinutes: Int = 0
    var siteID: UUID? = nil
    var hideDone: Bool = false
    var focusMinutes: Int = 25
    var breakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var sessionsBeforeLong: Int = 4
    var timerSound: Bool = true

    enum CodingKeys: String, CodingKey {
        case accent, surface, padding, font, fontFamily, fontSize, lineHeight, measure, wrap, richStyling, spellcheck, showStats, noteMode, typewriter, dimParagraphs, autoTitle, paragraphSpacing, headingScale, codeScale, termFontSize, cursor, shell, termOpacity, termFont, termLineHeight, startDirectory, startCommand, optionAsMeta, cursorBlink, scrollbackLines, zoom, mobileUA, showAddressBar, customCSS, forceDark, blockTrackers, appMode, isolatedSession, refreshMinutes, siteID, hideDone, focusMinutes, breakMinutes, longBreakMinutes, sessionsBeforeLong, timerSound
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        accent = v(.accent, accent)
        surface = v(.surface, surface)
        padding = v(.padding, padding)
        font = v(.font, font)
        fontFamily = v(.fontFamily, fontFamily)
        fontSize = v(.fontSize, fontSize)
        lineHeight = v(.lineHeight, lineHeight)
        measure = v(.measure, measure)
        wrap = v(.wrap, wrap)
        richStyling = v(.richStyling, richStyling)
        spellcheck = v(.spellcheck, spellcheck)
        showStats = v(.showStats, showStats)
        noteMode = v(.noteMode, noteMode)
        typewriter = v(.typewriter, typewriter)
        dimParagraphs = v(.dimParagraphs, dimParagraphs)
        autoTitle = v(.autoTitle, autoTitle)
        paragraphSpacing = v(.paragraphSpacing, paragraphSpacing)
        headingScale = v(.headingScale, headingScale)
        codeScale = v(.codeScale, codeScale)
        termFontSize = v(.termFontSize, termFontSize)
        cursor = v(.cursor, cursor)
        shell = v(.shell, shell)
        termOpacity = v(.termOpacity, termOpacity)
        termFont = v(.termFont, termFont)
        termLineHeight = v(.termLineHeight, termLineHeight)
        startDirectory = v(.startDirectory, startDirectory)
        startCommand = v(.startCommand, startCommand)
        optionAsMeta = v(.optionAsMeta, optionAsMeta)
        cursorBlink = v(.cursorBlink, cursorBlink)
        scrollbackLines = v(.scrollbackLines, scrollbackLines)
        zoom = v(.zoom, zoom)
        mobileUA = v(.mobileUA, mobileUA)
        showAddressBar = v(.showAddressBar, showAddressBar)
        customCSS = v(.customCSS, customCSS)
        forceDark = v(.forceDark, forceDark)
        blockTrackers = v(.blockTrackers, blockTrackers)
        appMode = v(.appMode, appMode)
        isolatedSession = v(.isolatedSession, isolatedSession)
        refreshMinutes = v(.refreshMinutes, refreshMinutes)
        siteID = (try? c.decodeIfPresent(UUID.self, forKey: .siteID)) ?? nil
        hideDone = v(.hideDone, hideDone)
        focusMinutes = v(.focusMinutes, focusMinutes)
        breakMinutes = v(.breakMinutes, breakMinutes)
        longBreakMinutes = v(.longBreakMinutes, longBreakMinutes)
        sessionsBeforeLong = v(.sessionsBeforeLong, sessionsBeforeLong)
        timerSound = v(.timerSound, timerSound)
    }
}

struct TaskItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var done: Bool = false
}

// MARK: - Panel

@Observable
final class Panel: Identifiable, Codable {
    func removeTask(_ id: UUID) { tasks.removeAll { $0.id == id } }

    let id: UUID
    var kind: PanelKind
    var title: String { didSet { Persistence.markDirty() } }
    var settings: PanelSettings { didSet { Persistence.markDirty() } }
    var text: String { didSet { Persistence.markDirty() } }
    var url: String { didSet { Persistence.markDirty() } }
    var tasks: [TaskItem] { didSet { Persistence.markDirty() } }

    init(kind: PanelKind, title: String? = nil, text: String = "", url: String = "", tasks: [TaskItem] = [],
         settings: PanelSettings = PanelSettings()) {
        self.id = UUID()
        self.kind = kind
        self.title = title ?? kind.defaultTitle
        self.text = text
        self.url = url
        self.tasks = tasks
        var st = settings
        if kind == .terminal && settings == PanelSettings() { st.padding = 14 }
        if kind == .tasks && settings == PanelSettings() { st.padding = 16 }
        if kind == .web && settings == PanelSettings() { st.padding = 18 }
        self.settings = st
    }

    enum CodingKeys: String, CodingKey { case id, kind, title, settings, text, url, tasks }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let decodedKind = try c.decode(PanelKind.self, forKey: .kind)
        kind = decodedKind
        title = (try? c.decode(String.self, forKey: .title)) ?? decodedKind.defaultTitle
        settings = (try? c.decode(PanelSettings.self, forKey: .settings)) ?? PanelSettings()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        tasks = (try? c.decode([TaskItem].self, forKey: .tasks)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(settings, forKey: .settings)
        try c.encode(text, forKey: .text)
        try c.encode(url, forKey: .url)
        try c.encode(tasks, forKey: .tasks)
    }
}

// MARK: - Layout tree

@Observable
final class Node: Identifiable, Codable {
    let id: UUID
    var panel: Panel?
    var axis: SplitAxis
    var children: [Node]
    var weights: [Double]

    init(panel: Panel) {
        id = UUID()
        self.panel = panel
        axis = .horizontal
        children = []
        weights = []
    }

    init(axis: SplitAxis, children: [Node], weights: [Double]? = nil) {
        id = UUID()
        panel = nil
        self.axis = axis
        self.children = children
        self.weights = weights ?? Array(repeating: 1, count: children.count)
    }

    static func empty() -> Node { Node(axis: .horizontal, children: []) }

    var isLeaf: Bool { panel != nil }
    var isEmpty: Bool { panel == nil && children.isEmpty }

    enum CodingKeys: String, CodingKey { case id, panel, axis, children, weights }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        panel = try? c.decodeIfPresent(Panel.self, forKey: .panel)
        axis = (try? c.decode(SplitAxis.self, forKey: .axis)) ?? .horizontal
        children = (try? c.decode([Node].self, forKey: .children)) ?? []
        weights = (try? c.decode([Double].self, forKey: .weights)) ?? []
        if weights.count != children.count { weights = Array(repeating: 1, count: children.count) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(panel, forKey: .panel)
        try c.encode(axis, forKey: .axis)
        try c.encode(children, forKey: .children)
        try c.encode(weights, forKey: .weights)
    }

    // MARK: queries

    func leaves() -> [Node] {
        if panel != nil { return [self] }
        return children.flatMap { $0.leaves() }
    }

    func leaf(for panelID: UUID) -> Node? {
        leaves().first { $0.panel?.id == panelID }
    }

    func parent(of target: Node) -> (node: Node, index: Int)? {
        for (i, c) in children.enumerated() {
            if c === target { return (self, i) }
            if let found = c.parent(of: target) { return found }
        }
        return nil
    }

    // MARK: cleanup

    /// Flattens same-axis nesting, drops empty branches and collapses single-child splits.
    func normalize() {
        guard panel == nil else { return }
        for c in children { c.normalize() }

        var newChildren: [Node] = []
        var newWeights: [Double] = []
        for (i, c) in children.enumerated() {
            let w = i < weights.count ? weights[i] : 1
            if c.isEmpty { continue }
            if c.panel == nil, c.axis == axis, c.children.count > 1 {
                let total = max(c.weights.reduce(0, +), 0.0001)
                for (j, cc) in c.children.enumerated() {
                    newChildren.append(cc)
                    newWeights.append(w * c.weights[j] / total)
                }
            } else {
                newChildren.append(c)
                newWeights.append(w)
            }
        }
        children = newChildren
        weights = newWeights

        if children.count == 1 {
            let only = children[0]
            panel = only.panel
            axis = only.axis
            children = only.children
            weights = only.weights
        }
    }
}

// MARK: - Space

@Observable
final class Space: Identifiable, Codable {
    let id: UUID
    var name: String { didSet { Persistence.markDirty() } }
    var root: Node
    var zoomedID: UUID?
    var focusedID: UUID?
    var symbol: String { didSet { Persistence.markDirty() } }
    var tint: AccentID { didSet { Persistence.markDirty() } }
    var themeID: String? { didSet { Persistence.markDirty() } }

    init(name: String, root: Node, symbol: String = "square.grid.2x2", tint: AccentID = .theme, themeID: String? = nil) {
        id = UUID()
        self.name = name
        self.root = root
        self.symbol = symbol
        self.tint = tint
        self.themeID = themeID
        focusedID = root.leaves().first?.panel?.id
    }

    enum CodingKeys: String, CodingKey { case id, name, root, focusedID, symbol, tint, themeID }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        root = try c.decode(Node.self, forKey: .root)
        focusedID = try? c.decodeIfPresent(UUID.self, forKey: .focusedID)
        symbol = (try? c.decode(String.self, forKey: .symbol)) ?? "square.grid.2x2"
        tint = (try? c.decode(AccentID.self, forKey: .tint)) ?? .theme
        themeID = try? c.decodeIfPresent(String.self, forKey: .themeID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(root, forKey: .root)
        try c.encodeIfPresent(focusedID, forKey: .focusedID)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(tint, forKey: .tint)
        try c.encodeIfPresent(themeID, forKey: .themeID)
    }

    var panels: [Panel] { root.leaves().compactMap { $0.panel } }
}

// MARK: - Layout presets

indirect enum Shape {
    case slot(PanelKind)
    case split(SplitAxis, [Shape], [Double])
}

enum LayoutPreset: String, CaseIterable, Identifiable {
    case focus, sideBySide, writerTerminal, triptych, editorStack, quad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focus: return "Focus"
        case .sideBySide: return "Side by Side"
        case .writerTerminal: return "Writer and Terminal"
        case .triptych: return "Triptych"
        case .editorStack: return "Editor and Stack"
        case .quad: return "Quad"
        }
    }

    var symbol: String {
        switch self {
        case .focus: return "square"
        case .sideBySide: return "rectangle.split.2x1"
        case .writerTerminal: return "rectangle.split.2x1.fill"
        case .triptych: return "rectangle.split.3x1"
        case .editorStack: return "rectangle.righthalf.inset.filled"
        case .quad: return "square.grid.2x2"
        }
    }

    var shape: Shape {
        switch self {
        case .focus:
            return .slot(.note)
        case .sideBySide:
            return .split(.horizontal, [.slot(.note), .slot(.note)], [1, 1])
        case .writerTerminal:
            return .split(.horizontal, [.slot(.note), .slot(.terminal)], [1.7, 1])
        case .triptych:
            return .split(.horizontal, [.slot(.note), .slot(.note), .slot(.note)], [1, 1, 1])
        case .editorStack:
            return .split(.horizontal, [
                .slot(.note),
                .split(.vertical, [.slot(.tasks), .slot(.terminal)], [1, 1.2])
            ], [1.6, 1])
        case .quad:
            return .split(.vertical, [
                .split(.horizontal, [.slot(.note), .slot(.note)], [1, 1]),
                .split(.horizontal, [.slot(.terminal), .slot(.web)], [1, 1])
            ], [1, 1])
        }
    }
}

// MARK: - Undo for closing things

/// Anything closed in the window can be brought back with Cmd Shift T, most recent first.
enum ClosedItem {
    case panel(Panel, spaceID: UUID, siblingID: UUID?, axis: SplitAxis)
    case space(Space, index: Int)
    case popout(Popout)

    var label: String {
        switch self {
        case .panel(let p, _, _, _): return "Panel \"\(p.title)\""
        case .space(let s, _): return "Workspace \"\(s.name)\""
        case .popout(let po): return "Window \"\(po.panel.title)\""
        }
    }
}

// MARK: - Workspace

@Observable
final class Workspace {
    static let shared = Workspace()

    var spaces: [Space]
    var activeSpaceID: UUID
    var paletteOpen = false
    var onboardingOpen = false
    var toast: String?
    var draggingID: UUID?
    var popouts: [Popout] = []
    var focusMode = false
    var focusStart: Date?
    var focusStartWords = 0
    var settingsRequest: UUID?
    var renameRequest: UUID?
    var webEpoch: [UUID: Int] = [:]
    var floating = false
    @ObservationIgnored var preFocusZoom: UUID?
    var closedStack: [ClosedItem] = []

    @ObservationIgnored var frames: [UUID: CGRect] = [:]
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init() {
        if let snap = Persistence.load(), !snap.spaces.isEmpty {
            spaces = snap.spaces
            activeSpaceID = snap.spaces.contains { $0.id == snap.active } ? snap.active : snap.spaces[0].id
            popouts = snap.popouts ?? []
        } else {
            let s = Workspace.makeWelcomeSpace()
            spaces = [s]
            activeSpaceID = s.id
        }
        if let notice = Persistence.loadNotice {
            Persistence.loadNotice = nil
            showToast(notice)
        }
        if Onboarding.shouldShow { onboardingOpen = true }
    }

    var space: Space { spaces.first { $0.id == activeSpaceID } ?? spaces[0] }

    var focused: Panel? {
        let s = space
        if let id = s.focusedID, let p = s.panels.first(where: { $0.id == id }) { return p }
        return s.panels.first
    }

    // MARK: toast

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled { withAnimation(.snappy) { self.toast = nil } }
        }
    }

    // MARK: focus

    func focus(_ id: UUID, grabFirstResponder: Bool = true) {
        let s = space
        guard s.focusedID != id else {
            if grabFirstResponder { Runtime.shared.makeFirstResponder(for: id) }
            return
        }
        s.focusedID = id
        Persistence.markDirty()
        if grabFirstResponder { Runtime.shared.makeFirstResponder(for: id) }
    }

    func cycleFocus(_ delta: Int) {
        let ps = space.panels
        guard !ps.isEmpty else { return }
        let cur = ps.firstIndex { $0.id == space.focusedID } ?? 0
        let next = (cur + delta + ps.count) % ps.count
        focus(ps[next].id)
    }

    func focusIndex(_ index: Int) {
        let ps = space.panels
        guard index >= 0, index < ps.count else { return }
        focus(ps[index].id)
    }

    func focusDirection(_ dir: Direction) {
        guard let cur = focused, let from = frames[cur.id] else { return }
        let c0 = CGPoint(x: from.midX, y: from.midY)
        var best: (Panel, CGFloat)?
        for p in space.panels where p.id != cur.id {
            guard let f = frames[p.id] else { continue }
            let c1 = CGPoint(x: f.midX, y: f.midY)
            let along: CGFloat
            let across: CGFloat
            switch dir {
            case .left:  along = c0.x - c1.x; across = abs(c0.y - c1.y)
            case .right: along = c1.x - c0.x; across = abs(c0.y - c1.y)
            case .up:    along = c0.y - c1.y; across = abs(c0.x - c1.x)
            case .down:  along = c1.y - c0.y; across = abs(c0.x - c1.x)
            }
            if along <= 1 { continue }
            let score = along + across * 2
            if best == nil || score < best!.1 { best = (p, score) }
        }
        if let b = best { focus(b.0.id) }
    }

    // MARK: structure

    @discardableResult
    func addPanel(_ kind: PanelKind, url: String = "", title: String? = nil, text: String = "",
                  settings: PanelSettings? = nil) -> Panel {
        let s = space
        let panel = Panel(kind: kind, title: title, text: text, url: url, settings: settings ?? PanelSettings())
        if kind == .web && url.isEmpty { panel.url = "" }
        withAnimation(Motion.layout) {
            if s.root.isEmpty {
                s.root = Node(panel: panel)
            } else if let target = focused.flatMap({ s.root.leaf(for: $0.id) }) ?? s.root.leaves().last {
                insert(panel, beside: target, axis: autoAxis(for: target), before: false, in: s)
            }
            s.zoomedID = nil
        }
        focus(panel.id, grabFirstResponder: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Runtime.shared.makeFirstResponder(for: panel.id) }
        Persistence.markDirty()
        Sound.play(.open)
        return panel
    }

    func split(_ panelID: UUID, axis: SplitAxis, kind: PanelKind) {
        let s = space
        guard let target = s.root.leaf(for: panelID) else { return }
        let panel = Panel(kind: kind)
        withAnimation(Motion.layout) {
            insert(panel, beside: target, axis: axis, before: false, in: s)
            s.zoomedID = nil
        }
        focus(panel.id, grabFirstResponder: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Runtime.shared.makeFirstResponder(for: panel.id) }
        Persistence.markDirty()
        Sound.play(.split)
    }

    func duplicate(_ panelID: UUID) {
        let s = space
        guard let target = s.root.leaf(for: panelID), let src = target.panel else { return }
        let copy = Panel(kind: src.kind, title: src.title + " copy", text: src.text, url: src.url,
                         tasks: src.tasks.map { TaskItem(title: $0.title, done: $0.done) }, settings: src.settings)
        withAnimation(Motion.layout) {
            insert(copy, beside: target, axis: autoAxis(for: target), before: false, in: s)
        }
        focus(copy.id, grabFirstResponder: false)
        Persistence.markDirty()
    }

    private func autoAxis(for node: Node) -> SplitAxis {
        if let f = node.panel.flatMap({ frames[$0.id] }) { return f.width >= f.height * 1.15 ? .horizontal : .vertical }
        return .horizontal
    }

    func insert(_ panel: Panel, beside target: Node, axis: SplitAxis, before: Bool, in s: Space) {
        let newLeaf = Node(panel: panel)
        if let (parent, idx) = s.root.parent(of: target), parent.axis == axis {
            let w = parent.weights[idx]
            parent.weights[idx] = w / 2
            let at = before ? idx : idx + 1
            parent.children.insert(newLeaf, at: at)
            parent.weights.insert(w / 2, at: at)
        } else {
            let old = Node(panel: target.panel!)
            target.panel = nil
            target.axis = axis
            target.children = before ? [newLeaf, old] : [old, newLeaf]
            target.weights = [1, 1]
        }
    }

    func close(_ panelID: UUID) {
        let s = space
        guard let leaf = s.root.leaf(for: panelID) else { return }
        let order = s.panels.map { $0.id }
        let idx = order.firstIndex(of: panelID) ?? 0
        if let closing = leaf.panel {
            var sibling: UUID?
            var axis: SplitAxis = .horizontal
            if let (parent, i) = s.root.parent(of: leaf) {
                axis = parent.axis
                let neighbor = i > 0 ? parent.children[i - 1] : (i + 1 < parent.children.count ? parent.children[i + 1] : nil)
                sibling = neighbor?.leaves().first?.panel?.id
            }
            pushClosed(.panel(closing, spaceID: s.id, siblingID: sibling, axis: axis))
            showToast("Closed \(closing.title). Cmd Shift T to undo")
        }
        withAnimation(Motion.layout) {
            if s.root === leaf {
                s.root = Node.empty()
            } else if let (parent, i) = s.root.parent(of: leaf) {
                parent.children.remove(at: i)
                parent.weights.remove(at: i)
                s.root.normalize()
            }
            if s.zoomedID == panelID { s.zoomedID = nil }
        }
        Runtime.shared.release(panelID)
        Sound.play(.close)
        let remaining = s.panels
        if s.focusedID == panelID {
            let nextIdx = min(max(idx - 1, 0), max(remaining.count - 1, 0))
            s.focusedID = remaining.isEmpty ? nil : remaining[nextIdx].id
            if let f = s.focusedID { Runtime.shared.makeFirstResponder(for: f) }
        }
        Persistence.markDirty()
    }

    func move(_ sourceID: UUID, onto targetID: UUID, zone: DropZone) {
        guard sourceID != targetID else { return }
        let s = space
        guard let srcLeaf = s.root.leaf(for: sourceID), let tgtLeaf = s.root.leaf(for: targetID),
              let src = srcLeaf.panel, let tgt = tgtLeaf.panel else { return }
        withAnimation(Motion.layout) {
            if zone == .center {
                srcLeaf.panel = tgt
                tgtLeaf.panel = src
            } else {
                if let (parent, i) = s.root.parent(of: srcLeaf) {
                    parent.children.remove(at: i)
                    parent.weights.remove(at: i)
                    s.root.normalize()
                } else {
                    return
                }
                guard let newTarget = s.root.leaf(for: targetID) else { return }
                let axis: SplitAxis = (zone == .left || zone == .right) ? .horizontal : .vertical
                let before = (zone == .left || zone == .top)
                insert(src, beside: newTarget, axis: axis, before: before, in: s)
                s.root.normalize()
            }
        }
        s.focusedID = sourceID
        Persistence.markDirty()
        Sound.play(.drop)
    }

    func equalize() {
        func walk(_ n: Node) {
            n.weights = Array(repeating: 1, count: n.children.count)
            n.children.forEach(walk)
        }
        withAnimation(Motion.layout) { walk(space.root) }
        Persistence.markDirty()
    }

    func toggleZoom(_ panelID: UUID? = nil) {
        let s = space
        let target = panelID ?? s.focusedID
        withAnimation(Motion.layout) {
            if s.zoomedID != nil { s.zoomedID = nil } else { s.zoomedID = target }
        }
    }

    func apply(_ preset: LayoutPreset) {
        let s = space
        var pool = s.panels
        func build(_ shape: Shape) -> Node {
            switch shape {
            case .slot(let kind):
                let p = pool.isEmpty ? Panel(kind: kind) : pool.removeFirst()
                return Node(panel: p)
            case .split(let axis, let items, let weights):
                return Node(axis: axis, children: items.map(build), weights: weights)
            }
        }
        var root = build(preset.shape)
        if !pool.isEmpty {
            let extras = pool.map { Node(panel: $0) }
            root = Node(axis: .horizontal, children: [root] + extras)
        }
        withAnimation(Motion.layout) {
            root.normalize()
            s.root = root
            s.zoomedID = nil
        }
        if s.focusedID == nil || s.panels.first(where: { $0.id == s.focusedID }) == nil {
            s.focusedID = s.panels.first?.id
        }
        Persistence.markDirty()
        showToast(preset.label)
    }

    // MARK: spaces

    func newSpace() {
        let n = spaces.count + 1
        let panel = Panel(kind: .note, title: "Untitled")
        let s = Space(name: "Space \(n)", root: Node(panel: panel))
        withAnimation(Motion.swap) {
            spaces.append(s)
            activeSpaceID = s.id
        }
        Persistence.markDirty()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Runtime.shared.makeFirstResponder(for: panel.id) }
    }

    func closeSpace(_ id: UUID) {
        guard spaces.count > 1, let idx = spaces.firstIndex(where: { $0.id == id }) else { return }
        let removed = spaces[idx]
        pushClosed(.space(removed, index: idx))
        withAnimation(Motion.swap) {
            spaces.remove(at: idx)
            if activeSpaceID == id { activeSpaceID = spaces[max(0, idx - 1)].id }
        }
        removed.panels.forEach { Runtime.shared.release($0.id) }
        Persistence.markDirty()
        showToast("Closed \(removed.name). Cmd Shift T brings it back")
    }

    func pushClosed(_ item: ClosedItem) {
        closedStack.append(item)
        if closedStack.count > 20 { closedStack.removeFirst() }
    }

    func selectSpace(_ id: UUID) {
        guard id != activeSpaceID else { return }
        Sound.play(.swap)
        withAnimation(Motion.swap) { activeSpaceID = id }
        Persistence.markDirty()
        if let f = space.focusedID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { Runtime.shared.makeFirstResponder(for: f) }
        }
    }

    func selectSpace(index: Int) {
        guard index >= 0, index < spaces.count else { return }
        selectSpace(spaces[index].id)
    }

    // MARK: welcome

    static func makeWelcomeSpace() -> Space {
        let welcome = Panel(kind: .note, title: "Welcome", text: welcomeText)
        let scratch = Panel(kind: .note, title: "Scratch", text: scratchText)
        welcome.settings.autoTitle = false
        scratch.settings.autoTitle = false
        scratch.settings.accent = .lavender
        scratch.settings.font = .serif
        scratch.settings.fontSize = 16
        let term = Panel(kind: .terminal, title: "Shell")
        term.settings.accent = .granite
        let tasks = Panel(kind: .tasks, title: "Today", tasks: [
            TaskItem(title: "Drag a panel header onto another panel", done: false),
            TaskItem(title: "Open the settings of this panel", done: false),
            TaskItem(title: "Press Command K", done: false),
            TaskItem(title: "Install Panels", done: true)
        ])
        tasks.settings.accent = .wood

        let right = Node(axis: .vertical, children: [Node(panel: scratch), Node(panel: tasks), Node(panel: term)],
                         weights: [1.1, 0.8, 1])
        let root = Node(axis: .horizontal, children: [Node(panel: welcome), right], weights: [1.5, 1])
        let space = Space(name: "Home", root: root)
        space.focusedID = welcome.id
        return space
    }

    static let welcomeText = """
    # Panels

    A quiet place to write, run things and keep tabs open. Everything here is a **panel**, and every panel is yours to shape.

    ## Move around

    - Drag the thin lines between panels to resize them. Double click a line to even things out.
    - Drag a panel by its header and drop it on the edge of another panel to dock it there. Drop in the middle to swap.
    - Press `Cmd D` to split right, `Cmd Shift D` to split down, `Cmd W` to close.
    - Press `Cmd Shift Return` to zoom the focused panel to the full window.
    - Press `Cmd K` for the command palette: new panels, layouts, themes.

    ## Make it yours

    Every panel has its own settings behind the slider icon in its header. Change the typeface, size, line height, text width, accent and surface for just that panel.

    ## Markdown

    Write in **bold**, *italic*, ~~strikethrough~~ and `inline code`. Lists, quotes and links all style as you type.

    > Good tools disappear. The words stay.

    - [x] Task lists work
    - [ ] Click the box in preview mode to tick it

    ```swift
    struct Panel {
        var title: String
        var accent: Color
    }
    ```

    Switch a note between Edit, Split and Preview from its header. [Panels](https://example.com) can hold terminals, web apps, tasks and a focus timer too.

    ---

    Start typing anywhere.
    """

    static let scratchText = """
    # Scratch

    This panel uses a serif face and a lavender accent. Its neighbours do not care.

    Try narrowing the text width in its settings for a calm, book-like column.
    """
}
