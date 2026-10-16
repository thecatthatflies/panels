import SwiftUI
import AppKit

enum AboutLinks {
    static let support = URL(string: "https://buy.stripe.com/7sYeVd7Sw5fN6PH3nVaVa07")!
    static let portfolio = URL(string: "https://aiyan.tech")!
    static let github = URL(string: "https://github.com/\(UpdateConfig.owner)/\(UpdateConfig.repo)")!
    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

struct AboutView: View {
    @Environment(\.theme) private var theme
    private let updater = Updater.shared
    @State private var heartBeat = 0

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 34)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 104, height: 104)
                .shadow(color: theme.shadow, radius: 16, y: 8)

            Text("Panels")
                .font(Typo.ui(30, bold: true))
                .foregroundStyle(theme.textC)
                .padding(.top, 18)

            Text(version)
                .font(Typo.ui(12))
                .foregroundStyle(theme.faintC)
                .padding(.top, 2)

            Text("A calm, windowless workspace where writing, terminals, web apps and focus live side by side. Arrange panels your way, lock in, and get things done.")
                .font(Typo.ui(13.5))
                .foregroundStyle(theme.mutedC)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 300)
                .padding(.top, 16)

            VStack(spacing: 10) {
                Button {
                    heartBeat += 1
                    AboutLinks.open(AboutLinks.support)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .symbolEffect(.bounce, value: heartBeat)
                        Text("Support Panels").font(Typo.ui(13.5, bold: true))
                    }
                    .foregroundStyle(theme.isDark ? Color.black.opacity(0.85) : Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Capsule().fill(theme.accentC))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())

                HStack(spacing: 10) {
                    linkButton("Portfolio", symbol: "globe", url: AboutLinks.portfolio)
                    linkButton("GitHub", symbol: "chevron.left.forwardslash.chevron.right", url: AboutLinks.github)
                }
            }
            .frame(maxWidth: 300)
            .padding(.top, 26)

            Button { updater.check(userInitiated: true) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10.5, weight: .medium))
                    Text(updater.isBusy ? "Checking" : (updater.state == .upToDate ? "You are up to date" : "Check for updates"))
                        .font(Typo.ui(12))
                }
                .foregroundStyle(theme.mutedC)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 18)

            Spacer(minLength: 20)

            VStack(spacing: 3) {
                Text("Made by Aiyan Chowdhury").font(Typo.ui(11.5)).foregroundStyle(theme.mutedC)
                Text("Set in Instrument Sans, SIL Open Font License").font(Typo.ui(10.5)).foregroundStyle(theme.faintC)
            }
            .padding(.bottom, 22)
        }
        .frame(width: 400, height: 560)
        .background(theme.surfaceC)
        .background(AboutWindowConfigurator())
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private func linkButton(_ title: String, symbol: String, url: URL) -> some View {
        Button { AboutLinks.open(url) } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 11.5, weight: .medium))
                Text(title).font(Typo.ui(13, bold: true))
            }
            .foregroundStyle(theme.textC)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Capsule().fill(theme.hover))
            .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// Gives the About window a clean, chrome-free look.
struct AboutWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.center()
        }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

/// About inside the Settings window, reusing the same view.
struct AboutSettingsView: View {
    var body: some View { AboutView().frame(maxWidth: .infinity, maxHeight: .infinity) }
}
