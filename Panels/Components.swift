import SwiftUI
import AppKit

// MARK: - Environment

private struct ThemeKey: EnvironmentKey { static let defaultValue: Theme = .granite }

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Visual effect

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.state = .active
        v.material = material
        v.blendingMode = blending
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

// MARK: - Window dragging region

final class DragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Honors System Settings > Desktop & Dock > Double-click a window's title bar to.
            let action = UserDefaults(suiteName: "Apple Global Domain")?.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
            switch action {
            case "Minimize": window?.performMiniaturize(nil)
            case "None": break
            default: window?.performZoom(nil)
            }
        } else {
            window?.performDrag(with: event)
        }
    }
}

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragRegionView { DragRegionView() }
    func updateNSView(_ v: DragRegionView, context: Context) {}
}

// MARK: - Window configuration

/// Configures the window the moment the view joins it, before the window is first drawn. Doing it a tick later
/// let the window appear at its default frame and style, then jump to the saved frame (a visible flash, and
/// Stage Manager showed it as a stray thumbnail).
final class WindowConfigView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        WindowConfigurator.configure(window)
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowConfigView() }

    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(v.window) }
    }

    static func configure(_ window: NSWindow?) {
        guard let w = window else { return }
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.styleMask.insert(.fullSizeContentView)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = false
        w.minSize = NSSize(width: 760, height: 500)
        w.collectionBehavior.insert(.fullScreenPrimary)
        if TestMode.active { w.alphaValue = 0; w.ignoresMouseEvents = true }
        WindowChrome.mainWindow = w
        WindowChrome.restoreFrameOnce(w)
        WindowChrome.install(on: w)
    }
}

enum WindowChrome {
    private static var observed = Set<ObjectIdentifier>()
    private static var lockRevealed = false

    // Metrics. The lights sit the same distance from the top and left edges so the corner reads as one
    // deliberate inset, and the top bar derives its own leading gap from them instead of a magic number.
    static let buttonSize: CGFloat = 14
    static let spacing: CGFloat = 8
    static let barHeight: CGFloat = 46
    static var normalInset: CGFloat { (barHeight - buttonSize) / 2 }
    static let lockedInset: CGFloat = 12
    static let lockedSpacing: CGFloat = 7
    static var lightsExtent: CGFloat { 3 * buttonSize + 2 * spacing }
    static var barLeadingGap: CGFloat { normalInset + lightsExtent + 14 }

    private static let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    private static var framed = Set<ObjectIdentifier>()
    static weak var mainWindow: NSWindow?

    /// Uses the system's window restoration: the last frame comes back, and the first launch sizes the window
    /// from the screen instead of a fixed number.
    static func restoreFrameOnce(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard !framed.contains(key) else { return }
        framed.insert(key)
        let name = "PanelsMainWindow"
        if !window.setFrameUsingName(name) {
            let vf = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let w = min(max(vf.width * 0.78, 960), vf.width)
            let h = min(max(vf.height * 0.82, 640), vf.height)
            window.setFrame(NSRect(x: vf.midX - w / 2, y: vf.midY - h / 2, width: w, height: h), display: true)
        }
        window.setFrameAutosaveName(name)
    }

    static func install(on window: NSWindow) {
        layoutTrafficLights(window)
        let key = ObjectIdentifier(window)
        guard !observed.contains(key) else { return }
        observed.insert(key)
        window.acceptsMouseMovedEvents = true
        let nc = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                     NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
                     NSWindow.didResignKeyNotification, NSWindow.didBecomeMainNotification] {
            nc.addObserver(forName: name, object: window, queue: .main) { _ in layoutTrafficLights(window) }
        }
        nc.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { _ in enforce(window) }
    }

    /// Positions the lights for the current mode. Lock In pulls them tighter into the corner and hides them
    /// until the pointer visits the top-left, so the full window height belongs to the work.
    static func layoutTrafficLights(_ window: NSWindow, animated: Bool = false) {
        let locked = Workspace.shared.focusMode
        let inset = locked ? lockedInset : normalInset
        let gap = locked ? lockedSpacing : spacing

        func place() {
            for (i, kind) in kinds.enumerated() {
                guard let b = window.standardWindowButton(kind), let sup = b.superview else { continue }
                let x = inset + CGFloat(i) * (buttonSize + gap)
                let y = sup.frame.height - inset - buttonSize
                let target = NSPoint(x: x, y: y)
                if animated { b.animator().setFrameOrigin(target) } else { b.setFrameOrigin(target) }
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.45
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                place()
            }
        } else {
            place()
        }
    }

    private static var settling = false

    /// Moves the lights for the current mode, then re-applies the final position once the layout has settled,
    /// because AppKit re-lays out the titlebar when the toolbar area changes and would undo a single move.
    static func refresh(animated: Bool) {
        settling = true
        if let w = mainWindow { layoutTrafficLights(w, animated: animated) }
        for delay in [0.15, 0.5, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if let w = mainWindow { layoutTrafficLights(w, animated: false) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { settling = false }
    }

    /// Cheap per-update check: if the system moved the lights, put them back.
    static func enforce(_ window: NSWindow) {
        guard !settling, window === mainWindow else { return }
        let locked = Workspace.shared.focusMode
        let inset = locked ? lockedInset : normalInset
        guard let b = window.standardWindowButton(.closeButton), let sup = b.superview else { return }
        let wantY = sup.frame.height - inset - buttonSize
        if abs(b.frame.origin.x - inset) > 0.5 || abs(b.frame.origin.y - wantY) > 0.5 { layoutTrafficLights(window) }
    }

    static func setTrafficLights(hidden: Bool) {
        lockRevealed = !hidden
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            if let w = mainWindow {
                for k in kinds { w.standardWindowButton(k)?.animator().alphaValue = hidden ? 0 : 1 }
            }
        }
    }

    /// While locked in, reveal the lights when the pointer enters the top-left corner and hide them again after.
    static func updateLockHover(for event: NSEvent) {
        guard Workspace.shared.focusMode, let window = event.window, let content = window.contentView else { return }
        let p = event.locationInWindow
        let zoneW = lockedInset + lightsExtent + 36
        let inZone = p.x < zoneW && p.y > content.bounds.height - (lockedInset + buttonSize + 20)
        if inZone != lockRevealed { setTrafficLights(hidden: !inZone) }
    }
}

// MARK: - Buttons

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

struct IconButton: View {
    @Environment(\.theme) private var theme
    let symbol: String
    var help: String = ""
    var active: Bool = false
    var tint: Color? = nil
    var size: CGFloat = 12
    var box: CGFloat = 24
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? (tint ?? theme.accentC) : (hover ? theme.textC : theme.mutedC))
                .frame(width: box, height: box)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(active ? (tint ?? theme.accentC).opacity(0.16) : (hover ? theme.hover : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(help)
        .onHover { hover = $0 }
    }
}

/// Icon-only menu styled like IconButton.
struct IconMenu<Content: View>: View {
    @Environment(\.theme) private var theme
    let symbol: String
    var help: String = ""
    var size: CGFloat = 12
    var box: CGFloat = 24
    @ViewBuilder var content: () -> Content
    @State private var hover = false

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(hover ? theme.textC : theme.mutedC)
                .frame(width: box, height: box)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? theme.hover : .clear))
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
        .onHover { hover = $0 }
    }
}

// MARK: - Settings controls

struct SettingsSection<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(Typo.ui(10, bold: true))
                .tracking(0.9)
                .foregroundStyle(theme.faintC)
            VStack(alignment: .leading, spacing: 11) { content() }
        }
    }
}

struct SettingRow<Content: View>: View {
    @Environment(\.theme) private var theme
    let label: String
    var value: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(Typo.ui(12)).foregroundStyle(theme.mutedC)
                Spacer()
                if let value {
                    Text(value).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(theme.faintC)
                }
            }
            content()
        }
    }
}

struct SliderRow: View {
    @Environment(\.theme) private var theme
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { String(format: "%.0f", $0) }
    var tint: Color? = nil

    var body: some View {
        SettingRow(label: label, value: format(value)) {
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
                .tint(tint ?? theme.accentC)
        }
    }
}

struct ToggleRow: View {
    @Environment(\.theme) private var theme
    let label: String
    @Binding var isOn: Bool
    var tint: Color? = nil

    var body: some View {
        HStack {
            Text(label).font(Typo.ui(12)).foregroundStyle(theme.mutedC)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(tint ?? theme.accentC)
        }
    }
}

struct SegmentedChips<T: Hashable & Identifiable>: View {
    @Environment(\.theme) private var theme
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { opt in
                let on = opt == selection
                Button { withAnimation(.snappy(duration: 0.18)) { selection = opt } } label: {
                    Text(label(opt))
                        .font(Typo.ui(11.5, bold: on))
                        .foregroundStyle(on ? theme.textC : theme.mutedC)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(on ? (tint ?? theme.accentC).opacity(0.20) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(on ? (tint ?? theme.accentC).opacity(0.55) : .clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.hover))
    }
}

struct AccentSwatches: View {
    @Environment(\.theme) private var theme
    @Binding var selection: AccentID

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccentID.allCases) { a in
                let color = theme.accent(a)
                let on = selection == a
                Button { withAnimation(.snappy(duration: 0.18)) { selection = a } } label: {
                    ZStack {
                        Circle().fill(color).frame(width: 18, height: 18)
                        if a == .theme {
                            Circle().strokeBorder(theme.textC.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .frame(width: 18, height: 18)
                        }
                        if on {
                            Circle().strokeBorder(theme.textC, lineWidth: 1.5).frame(width: 25, height: 25)
                        }
                    }
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .help(a.label)
            }
        }
    }
}

// MARK: - Tiny label chip

struct KeyCap: View {
    @Environment(\.theme) private var theme
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(theme.mutedC)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.hover))
    }
}


// MARK: - Text prompt

enum Prompt {
    /// Runs a small modal asking for a line of text. Returns nil when cancelled.
    static func text(title: String, message: String, defaultValue: String = "", confirm: String = "Save") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespaces)
    }
}


// MARK: - Reparent-safe native host

/// Wraps a cached native view (terminal, web view, editor). During SwiftUI transitions two
/// representables can briefly refer to the same child; the newest container wins and an old
/// container going away never rips the child out of its new home.
final class HostContainer: NSView {
    private weak var child: NSView?

    override var isFlipped: Bool { true }

    func attach(_ view: NSView, steal: Bool) {
        if view.superview === self { child = view; return }
        guard steal || view.superview == nil else { return }
        view.removeFromSuperview()
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        child = view
    }

    func release() {
        if let c = child, c.superview === self { c.removeFromSuperview() }
        child = nil
    }

    override func layout() {
        super.layout()
        if let c = child, c.superview === self, c.frame != bounds { c.frame = bounds }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let c = child, c.superview === self { c.frame = bounds }
    }
}


// MARK: - Motion

/// One place for animation timing so everything feels equally quick.
enum Motion {
    /// Follows the macOS Reduce Motion setting: no animation at all when it is on.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Panels opening, closing, moving, resizing.
    static var layout: Animation? { reduced ? nil : .snappy(duration: 0.22, extraBounce: 0) }
    /// Switching workspaces: nearly instant, just enough to avoid a hard cut.
    static var swap: Animation? { reduced ? nil : .easeOut(duration: 0.12) }
    /// Small state changes: hover, selection, toggles.
    static var quick: Animation? { reduced ? nil : .snappy(duration: 0.16, extraBounce: 0) }
    /// A panel fading in after it is created.
    static var appear: Animation? { reduced ? nil : .easeOut(duration: 0.16) }
}
