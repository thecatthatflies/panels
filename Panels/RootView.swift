import SwiftUI
import AppKit

struct RootView: View {
    private let ws = Workspace.shared
    private let appearance = Appearance.shared

    /// The window never shrinks below what the panels in the active workspace need.
    private var windowMin: CGSize {
        let need = ws.requiredContentSize(for: ws.space)
        let zoomed = ws.space.zoomedID != nil || ws.focusMode
        let bar = ws.focusMode ? 0 : WindowChrome.barHeight
        return CGSize(width: zoomed ? 760 : max(760, need.width), height: zoomed ? 500 : max(500, need.height + bar))
    }

    /// Sets the window's minimum from AppKit, after layout. Doing it through a SwiftUI min frame made SwiftUI
    /// resize the window during its own layout pass, which could loop and abort.
    private func applyWindowMin(_ need: CGSize) {
        DispatchQueue.main.async {
            guard let w = WindowChrome.mainWindow else { return }
            if w.contentMinSize != need { w.contentMinSize = need }
            let size = w.contentRect(forFrameRect: w.frame).size
            if size.width < need.width - 0.5 || size.height < need.height - 0.5 {
                w.setContentSize(NSSize(width: max(size.width, need.width), height: max(size.height, need.height)))
            }
        }
    }

    var body: some View {
        let theme = appearance.theme(for: ws.space)
        let locked = ws.focusMode

        ZStack {
            WindowBackground(theme: theme, translucency: locked ? max(appearance.translucency, 0.97) : appearance.translucency)

            VStack(spacing: 0) {
                if !locked {
                    TopBar()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                SpaceContent()
            }

            if locked {
                VStack {
                    Spacer()
                    FocusHUD()
                        .padding(.bottom, 22)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(5)
            }

            if DictationController.shared.isActive {
                VStack {
                    Spacer()
                    DictationHUD()
                        .padding(.bottom, locked ? 74 : 26)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(6)
            }

            if ws.paletteOpen {
                CommandPalette()
                    .zIndex(10)
            }

            if let gate = DictationController.shared.permissionCard {
                DictationPermissionCard(gate: gate)
                    .transition(.opacity)
                    .zIndex(29)
            }

            if ws.onboardingOpen {
                OnboardingView()
                    .transition(.opacity)
                    .zIndex(30)
            }

            if let toast = ws.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(Typo.ui(12.5, bold: true))
                        .foregroundStyle(theme.textC)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(theme.raisedC))
                        .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                        .shadow(color: theme.shadow, radius: 16, y: 6)
                        .padding(.bottom, locked ? 70 : 26)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
                .allowsHitTesting(false)
                .zIndex(20)
            }
        }
        .environment(\.theme, theme)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .background(WindowConfigurator())
        .ignoresSafeArea()
        .frame(minWidth: 760, minHeight: 500)
        .onChange(of: windowMin, initial: true) { _, need in applyWindowMin(need) }
        .animation(.smooth(duration: 0.5), value: locked)
        .animation(.snappy(duration: 0.22), value: ws.paletteOpen)
        .animation(.snappy(duration: 0.22), value: ws.onboardingOpen)
        .animation(.snappy(duration: 0.22), value: DictationController.shared.permissionCard)
        .animation(Motion.layout, value: DictationController.shared.isActive)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: ws.toast)
        .animation(.smooth(duration: 0.4), value: theme.id)
        .onChange(of: theme.isDark) { _, dark in
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        }
        .onAppear {
            NSApp.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        }
    }
}

struct WindowBackground: View {
    let theme: Theme
    let translucency: Double

    var body: some View {
        ZStack {
            // Respects System Settings > Accessibility > Display > Reduce transparency.
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                VisualEffectView(material: .underWindowBackground, blending: .behindWindow)
            }
            theme.windowC.opacity(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : translucency)
        }
        .ignoresSafeArea()
    }
}

struct SpaceContent: View {
    @Environment(\.theme) private var theme
    private let ws = Workspace.shared
    private let appearance = Appearance.shared

    var body: some View {
        let s = ws.space
        let gap = CGFloat(appearance.gap)
        let locked = ws.focusMode
        let side = locked ? 0 : gap + 2

        Group {
            if let zid = s.zoomedID, let p = s.panels.first(where: { $0.id == zid }) {
                PanelView(panel: p)
                    .id(p.id)
                    .transition(.scale(scale: 0.985).combined(with: .opacity))
            } else {
                NodeView(node: s.root)
            }
        }
        .padding(.horizontal, side)
        .padding(.bottom, locked ? 0 : gap + 2)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { ws.contentSizeChanged($0) }
        .id(s.id)
    }
}
