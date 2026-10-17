import SwiftUI
import AppKit

/// First launch walkthrough. Three short steps, skippable at any point. Shown once per `version`
/// (bump it to show a new walkthrough after a big change). "Show Welcome Again" in the Help menu reopens it.
enum Onboarding {
    static let version = 1
    private static let key = "onboardingVersion"

    static var shouldShow: Bool {
        if SelfTest.enabled || SnapshotTool.directory != nil { return false }
        return UserDefaults.standard.integer(forKey: key) < version
    }

    static func markSeen() { UserDefaults.standard.set(version, forKey: key) }
}

struct OnboardingView: View {
    @Environment(\.theme) private var theme
    private let ws = Workspace.shared
    private let appearance = Appearance.shared

    @State private var step: Int
    @State private var templateID: UUID?          // nil keeps the Welcome workspace as it is
    @State private var sound = false

    private let steps = 3

    init(startStep: Int = 0) { _step = State(initialValue: startStep) }

    var body: some View {
        ZStack {
            Color.black.opacity(theme.isDark ? 0.45 : 0.25)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Step \(step + 1) of \(steps)")
                        .font(Typo.ui(11.5, bold: true))
                        .foregroundStyle(theme.faintC)
                    Spacer()
                    Button("Skip") { finish(applyChoices: false) }
                        .buttonStyle(.plain)
                        .font(Typo.ui(12, bold: true))
                        .foregroundStyle(theme.mutedC)
                        .keyboardShortcut(.cancelAction)
                }

                Group {
                    switch step {
                    case 0: lookStep
                    case 1: startStep
                    default: extrasStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)

                HStack {
                    if step > 0 {
                        Button("Back") { withAnimation(.snappy(duration: 0.2)) { step -= 1 } }
                            .buttonStyle(.plain)
                            .font(Typo.ui(12.5, bold: true))
                            .foregroundStyle(theme.mutedC)
                    }
                    Spacer()
                    Button(step == steps - 1 ? "Open Panels" : "Next") {
                        if step == steps - 1 { finish(applyChoices: true) }
                        else { withAnimation(.snappy(duration: 0.2)) { step += 1 } }
                    }
                    .buttonStyle(PressStyle())
                    .font(Typo.ui(12.5, bold: true))
                    .foregroundStyle(theme.isDark ? Color.black.opacity(0.85) : Color.white)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Capsule().fill(theme.accentC))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.raisedC))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
            .shadow(color: theme.shadow, radius: 30, y: 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Panels")
    }

    // MARK: steps

    private func heading(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Typo.ui(20, bold: true)).foregroundStyle(theme.textC)
            Text(body).font(Typo.ui(13)).foregroundStyle(theme.mutedC).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lookStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Welcome to Panels", "A quiet workspace for notes, terminals, web pages, tasks and a focus timer. Pick how it looks. You can change this any time in Settings.")
            Text("Theme").font(Typo.ui(11.5, bold: true)).foregroundStyle(theme.faintC)
            HStack(spacing: 8) {
                ForEach(ThemeChoice.allCases) { choice in
                    let on = appearance.choice == choice
                    Button { appearance.choice = choice } label: {
                        VStack(spacing: 6) {
                            Circle().fill(swatch(choice)).frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                            Text(choice.label).font(Typo.ui(11, bold: on)).foregroundStyle(on ? theme.textC : theme.mutedC)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? theme.accentC.opacity(0.18) : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? theme.accentC.opacity(0.6) : .clear, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.label)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text("Spacing").font(Typo.ui(11.5, bold: true)).foregroundStyle(theme.faintC)
            SegmentedChips(options: Appearance.Density.allCases,
                           selection: Binding(get: { appearance.density }, set: { appearance.apply(density: $0) }),
                           label: { $0.label })
        }
    }

    private func swatch(_ c: ThemeChoice) -> AnyShapeStyle {
        switch c {
        case .auto: return AnyShapeStyle(LinearGradient(stops: [.init(color: Theme.granite.surfaceC, location: 0.5), .init(color: Theme.paleSky.surfaceC, location: 0.5)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
        case .granite: return AnyShapeStyle(Theme.granite.raisedC)
        case .paleSky: return AnyShapeStyle(Theme.paleSky.surfaceC)
        case .taupe: return AnyShapeStyle(Theme.taupe.raisedC)
        case .slate: return AnyShapeStyle(Theme.slate.raisedC)
        }
    }

    private var startStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Pick a starting point", "Add a ready made workspace next to the Welcome one, or keep just the Welcome workspace.")
            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                choiceCard(name: "Just Welcome", symbol: "house", on: templateID == nil) { templateID = nil }
                ForEach(TemplateStore.builtins) { t in
                    choiceCard(name: t.name, symbol: t.symbol, on: templateID == t.id) { templateID = t.id }
                }
            }
        }
    }

    private func choiceCard(name: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 18, weight: .light))
                Text(name).font(Typo.ui(11.5, bold: on)).lineLimit(1)
            }
            .foregroundStyle(on ? theme.textC : theme.mutedC)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? theme.accentC.opacity(0.18) : theme.hover))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? theme.accentC.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var extrasStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("A few extras", "Everything here is optional and lives in Settings later.")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sound").font(Typo.ui(13, bold: true)).foregroundStyle(theme.textC)
                    Text("Soft UI and typing sounds. Off by default.").font(Typo.ui(12)).foregroundStyle(theme.mutedC)
                }
                Spacer()
                Toggle("Sound", isOn: $sound).labelsHidden().toggleStyle(.switch).tint(theme.accentC)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mic").font(.system(size: 14)).foregroundStyle(theme.faintC).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dictation").font(Typo.ui(13, bold: true)).foregroundStyle(theme.textC)
                    Text("Press Cmd Shift M in a note or terminal. macOS asks for the microphone and speech recognition then, not now.")
                        .font(Typo.ui(12)).foregroundStyle(theme.mutedC).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "command").font(.system(size: 14)).foregroundStyle(theme.faintC).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Command palette").font(Typo.ui(13, bold: true)).foregroundStyle(theme.textC)
                    Text("Press Cmd K any time to add panels, switch layouts and change themes.")
                        .font(Typo.ui(12)).foregroundStyle(theme.mutedC).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: finish

    private func finish(applyChoices: Bool) {
        Onboarding.markSeen()
        if applyChoices {
            var p = SoundSettings.shared.prefs
            if p.masterEnabled != sound { p.masterEnabled = sound; SoundSettings.shared.prefs = p }
            if let id = templateID, let t = TemplateStore.builtins.first(where: { $0.id == id }) {
                ws.newSpace(from: t)
            }
        }
        withAnimation(.snappy(duration: 0.22)) { ws.onboardingOpen = false }
    }
}

/// Shown the first time dictation needs the microphone (before the system prompt) and after a denial.
struct DictationPermissionCard: View {
    @Environment(\.theme) private var theme
    let gate: DictationController.Gate
    private let dictation = DictationController.shared

    var body: some View {
        ZStack {
            Color.black.opacity(theme.isDark ? 0.4 : 0.2).ignoresSafeArea()
                .onTapGesture { dictation.dismissPermissionCard() }
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: gate == .denied ? "mic.slash" : "mic")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(theme.accentC)
                Text(gate == .denied ? "Microphone is off" : "Dictation needs your microphone")
                    .font(Typo.ui(17, bold: true)).foregroundStyle(theme.textC)
                Text(gate == .denied
                     ? "Panels cannot hear you because microphone access is off. Turn it on in System Settings, Privacy and Security, Microphone."
                     : "Panels listens only while dictation is on. macOS will ask for permission next.")
                    .font(Typo.ui(13)).foregroundStyle(theme.mutedC)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Not now") { dictation.dismissPermissionCard() }
                        .buttonStyle(.plain).font(Typo.ui(12.5, bold: true)).foregroundStyle(theme.mutedC)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(gate == .denied ? "Open System Settings" : "Continue") {
                        if gate == .denied { dictation.openMicrophoneSettings() } else { dictation.continueAfterPriming() }
                    }
                    .buttonStyle(PressStyle())
                    .font(Typo.ui(12.5, bold: true))
                    .foregroundStyle(theme.isDark ? Color.black.opacity(0.85) : Color.white)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Capsule().fill(theme.accentC))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.raisedC))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
            .shadow(color: theme.shadow, radius: 30, y: 12)
        }
    }
}
