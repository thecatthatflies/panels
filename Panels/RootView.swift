import SwiftUI
import AppKit

struct RootView: View {
    private let ws = Workspace.shared
    private let appearance = Appearance.shared

    var body: some View {
        let theme = appearance.theme

        ZStack {
            WindowBackground(theme: theme, translucency: appearance.translucency)

            VStack(spacing: 0) {
                TopBar()
                SpaceContent()
            }

            if ws.paletteOpen {
                CommandPalette()
                    .zIndex(10)
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
                        .padding(.bottom, 26)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(20)
            }
        }
        .environment(\.theme, theme)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .background(WindowConfigurator())
        .ignoresSafeArea()
        .frame(minWidth: 760, minHeight: 500)
        .animation(.snappy(duration: 0.22), value: ws.paletteOpen)
        .animation(.snappy(duration: 0.25), value: ws.toast)
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
            VisualEffectView(material: theme.isDark ? .underWindowBackground : .underWindowBackground,
                             blending: .behindWindow)
            theme.windowC.opacity(translucency)
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

        Group {
            if let zid = s.zoomedID, let p = s.panels.first(where: { $0.id == zid }) {
                PanelView(panel: p)
                    .id(p.id)
                    .transition(.scale(scale: 0.985).combined(with: .opacity))
            } else {
                NodeView(node: s.root)
            }
        }
        .padding(.horizontal, gap + 2)
        .padding(.bottom, gap + 2)
        .id(s.id)
        .transition(.opacity)
    }
}
