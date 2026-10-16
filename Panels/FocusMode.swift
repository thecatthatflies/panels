import SwiftUI
import AppKit

// MARK: - Lock In HUD

struct FocusHUD: View {
    @Environment(\.theme) private var theme
    private let ws = Workspace.shared
    @State private var hover = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let elapsed = max(Int(ctx.date.timeIntervalSince(ws.focusStart ?? ctx.date)), 0)
            let panel = ws.focused
            let written = max(ws.wordCount(of: panel) - ws.focusStartWords, 0)

            HStack(spacing: 14) {
                Image(systemName: "scope")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accentC)
                    .symbolEffect(.pulse, options: .repeating.speed(0.4))

                Text(format(elapsed))
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.textC)
                    .contentTransition(.numericText())

                if panel?.kind == .note {
                    Text("+\(written) \(written == 1 ? "word" : "words")")
                        .font(Typo.ui(12))
                        .foregroundStyle(written > 0 ? theme.accentC : theme.faintC)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.25), value: written)
                }

                Rectangle().fill(theme.hairlineStrong).frame(width: 1, height: 14)

                Button { ws.exitFocusMode() } label: {
                    HStack(spacing: 7) {
                        Text("Exit").font(Typo.ui(12, bold: true))
                        KeyCap(text: "Cmd Shift L")
                    }
                    .foregroundStyle(theme.mutedC)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .glassEffect(.regular, in: Capsule())
            .opacity(hover ? 1 : 0.42)
            .scaleEffect(hover ? 1 : 0.98)
            .animation(.snappy(duration: 0.28), value: hover)
        }
        .onHover { hover = $0 }
    }

    private func format(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Soft edge darkening while locked in, so the writing surface feels lit from the middle.
struct FocusVignette: View {
    @Environment(\.theme) private var theme

    var body: some View {
        RadialGradient(colors: [.clear, theme.windowC.opacity(theme.isDark ? 0.55 : 0.30)],
                       center: .center, startRadius: 220, endRadius: 900)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}
