import SwiftUI
import AppKit
import Observation

// MARK: - Model

/// A panel living in its own floating window, separate from the main window.
@Observable
final class Popout: Identifiable, Codable {
    var id: UUID { panel.id }
    let panel: Panel
    var frame: String?
    var pinned: Bool { didSet { Persistence.markDirty() } }

    init(panel: Panel, frame: String? = nil, pinned: Bool = true) {
        self.panel = panel
        self.frame = frame
        self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey { case panel, frame, pinned }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        panel = try c.decode(Panel.self, forKey: .panel)
        frame = try? c.decodeIfPresent(String.self, forKey: .frame)
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(panel, forKey: .panel)
        try c.encodeIfPresent(frame, forKey: .frame)
        try c.encode(pinned, forKey: .pinned)
    }
}

// MARK: - Workspace operations

extension Workspace {
    func popout(for panelID: UUID) -> Popout? { popouts.first { $0.panel.id == panelID } }

    /// Pulls a panel out of the layout into its own always-on-top window.
    func popOut(_ panelID: UUID) {
        let s = space
        guard let leaf = s.root.leaf(for: panelID), let panel = leaf.panel else { return }
        if focusMode { exitFocusMode() }
        withAnimation(Motion.layout) {
            if s.root === leaf {
                s.root = Node.empty()
            } else if let (parent, i) = s.root.parent(of: leaf) {
                parent.children.remove(at: i)
                parent.weights.remove(at: i)
                s.root.normalize()
            }
            if s.zoomedID == panelID { s.zoomedID = nil }
            if s.focusedID == panelID { s.focusedID = s.panels.first?.id }
        }
        let po = Popout(panel: panel)
        popouts.append(po)
        PopoutManager.shared.open(po, near: NSApp.mainWindow)
        Persistence.markDirty()
        Sound.play(.open)
    }

    /// Returns a popped-out panel to the current workspace.
    func dock(_ panelID: UUID) {
        guard let po = popout(for: panelID) else { return }
        PopoutManager.shared.closeWindow(panelID)
        popouts.removeAll { $0.panel.id == panelID }
        let s = space
        withAnimation(Motion.layout) {
            if s.root.isEmpty {
                s.root = Node(panel: po.panel)
            } else if let last = s.root.leaves().last {
                insert(po.panel, beside: last, axis: .horizontal, before: false, in: s)
            }
        }
        s.focusedID = po.panel.id
        Persistence.markDirty()
        Sound.play(.drop)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Runtime.shared.makeFirstResponder(for: po.panel.id) }
    }

    func closePopout(_ panelID: UUID) {
        if let po = popout(for: panelID) { pushClosed(.popout(po)) }
        PopoutManager.shared.closeWindow(panelID)
        popouts.removeAll { $0.panel.id == panelID }
        Runtime.shared.release(panelID)
        Persistence.markDirty()
        Sound.play(.close)
    }

    func dockAll() {
        for po in popouts { dock(po.panel.id) }
    }
}

// MARK: - Window

final class PopoutWindow: NSPanel {
    let panelID: UUID
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(panelID: UUID, frame: NSRect) {
        self.panelID = panelID
        super.init(contentRect: frame,
                   styleMask: [.titled, .resizable, .fullSizeContentView, .closable],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        minSize = NSSize(width: 240, height: 170)
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { standardWindowButton(b)?.isHidden = true }
    }
}

final class PopoutManager {
    static let shared = PopoutManager()
    private var windows: [UUID: PopoutWindow] = [:]
    private var observers: [UUID: [NSObjectProtocol]] = [:]
    private var cascade: CGFloat = 0

    func restoreAll() {
        for po in Workspace.shared.popouts where windows[po.panel.id] == nil { open(po, near: nil) }
    }

    private func defaultSize(for kind: PanelKind) -> NSSize {
        switch kind {
        case .note: return NSSize(width: 520, height: 420)
        case .terminal: return NSSize(width: 660, height: 390)
        case .web: return NSSize(width: 620, height: 460)
        case .tasks: return NSSize(width: 330, height: 420)
        case .timer: return NSSize(width: 330, height: 400)
        }
    }

    func open(_ po: Popout, near host: NSWindow?) {
        let panel = po.panel
        var frame: NSRect
        if let s = po.frame, !s.isEmpty { frame = NSRectFromString(s) }
        else {
            let size = defaultSize(for: panel.kind)
            let base = host?.frame ?? (NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800))
            cascade = (cascade + 26).truncatingRemainder(dividingBy: 156)
            frame = NSRect(x: base.midX - size.width / 2 + cascade, y: base.midY - size.height / 2 - cascade,
                           width: size.width, height: size.height)
        }
        let win = PopoutWindow(panelID: panel.id, frame: frame)
        let host = NSHostingView(rootView: PopoutRoot(popout: po))
        host.sizingOptions = []
        win.contentView = host
        apply(po, to: win)
        windows[panel.id] = win
        win.makeKeyAndOrderFront(nil)

        let nc = NotificationCenter.default
        let update: (Notification) -> Void = { [weak win] _ in
            guard let win else { return }
            po.frame = NSStringFromRect(win.frame)
            Persistence.markDirty()
        }
        observers[panel.id] = [
            nc.addObserver(forName: NSWindow.didMoveNotification, object: win, queue: .main, using: update),
            nc.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: win, queue: .main, using: update)
        ]
        po.frame = NSStringFromRect(win.frame)
    }

    func apply(_ po: Popout, to win: PopoutWindow) {
        win.level = po.pinned ? .floating : .normal
        if po.pinned { win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] }
        else { win.collectionBehavior = [.fullScreenAuxiliary] }
    }

    func setPinned(_ id: UUID, _ pinned: Bool) {
        guard let po = Workspace.shared.popout(for: id), let win = windows[id] else { return }
        po.pinned = pinned
        apply(po, to: win)
    }

    func closeWindow(_ id: UUID) {
        if let obs = observers.removeValue(forKey: id) { obs.forEach { NotificationCenter.default.removeObserver($0) } }
        if let win = windows.removeValue(forKey: id) {
            win.contentView = nil
            win.orderOut(nil)
        }
    }
}

// MARK: - Popout content

struct PopoutRoot: View {
    @Bindable var popout: Popout
    private let appearance = Appearance.shared
    private let ws = Workspace.shared
    @State private var showSettings = false

    var body: some View {
        let theme = appearance.theme
        let panel = popout.panel
        let accent = theme.accent(panel.settings.accent)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let surface: Color = panel.kind == .terminal ? Color(hex: theme.termBackground) : theme.surfaceC

        VStack(spacing: 0) {
            header(panel: panel, theme: theme, accent: accent)
            PanelBodyView(panel: panel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(shape.fill(surface))
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.hairlineStrong, lineWidth: 1))
        .environment(\.theme, theme)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private func header(panel: Panel, theme: Theme, accent: Color) -> some View {
        ZStack {
            WindowDragRegion()
            HStack(spacing: 8) {
                Image(systemName: panel.kind.symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 16)
                Text(panel.title.isEmpty ? panel.kind.defaultTitle : panel.title)
                    .font(Typo.ui(12.5, bold: true))
                    .foregroundStyle(theme.textC)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if panel.kind == .note { NoteModePicker(panel: panel, accent: accent) }
                IconButton(symbol: popout.pinned ? "pin.fill" : "pin", help: popout.pinned ? "Unpin from top" : "Keep on top",
                           active: popout.pinned, tint: accent) {
                    PopoutManager.shared.setPinned(panel.id, !popout.pinned)
                }
                IconButton(symbol: "slider.horizontal.3", help: "Panel settings", active: showSettings, tint: accent) { showSettings.toggle() }
                    .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                        PanelSettingsView(panel: panel).environment(\.theme, theme)
                    }
                IconButton(symbol: "arrow.uturn.backward.square", help: "Return to the main window") { ws.dock(panel.id) }
                IconButton(symbol: "xmark", help: "Close") { ws.closePopout(panel.id) }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 38)
    }
}
