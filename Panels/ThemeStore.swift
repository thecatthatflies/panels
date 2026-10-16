import SwiftUI
import AppKit
import Observation

// MARK: - Custom theme

struct CustomThemeSpec: Codable, Identifiable, Equatable {
    var id: String = "custom-" + UUID().uuidString.prefix(8).lowercased()
    var name: String
    var isDark: Bool
    var window: UInt32
    var surface: UInt32
    var raised: UInt32
    var text: UInt32
    var muted: UInt32
    var faint: UInt32
    var accent: UInt32

    init(name: String, from t: Theme) {
        self.name = name
        isDark = t.isDark
        window = t.window; surface = t.surface; raised = t.surfaceRaised
        text = t.text; muted = t.textMuted; faint = t.textFaint; accent = t.accent
    }

    func build() -> Theme {
        let base = isDark ? Theme.granite : Theme.paleSky
        return Theme(id: id, name: name, isDark: isDark,
                     window: window, surface: surface, surfaceRaised: raised,
                     text: text, textMuted: muted, textFaint: faint, accent: accent,
                     ansi: base.ansi,
                     termBackground: ColorMix.blend(surface, window, 0.45),
                     termForeground: text)
    }
}

enum ColorMix {
    static func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) }
        func mix(_ shift: UInt32) -> UInt32 { UInt32(max(0, min(255, (ch(a, shift) * (1 - t) + ch(b, shift) * t).rounded()))) }
        return (mix(16) << 16) | (mix(8) << 8) | mix(0)
    }

    static func hex(from color: Color) -> UInt32 {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        let r = UInt32(max(0, min(255, (ns.redComponent * 255).rounded())))
        let g = UInt32(max(0, min(255, (ns.greenComponent * 255).rounded())))
        let b = UInt32(max(0, min(255, (ns.blueComponent * 255).rounded())))
        return (r << 16) | (g << 8) | b
    }
}

// MARK: - Store

@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var customs: [CustomThemeSpec] {
        didSet { save() }
    }

    private static var fileURL: URL {
        let dir = AppPaths.dir
        return dir.appendingPathComponent("themes.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([CustomThemeSpec].self, from: data) {
            customs = decoded
        } else {
            customs = []
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(customs) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    func index(of id: String) -> Int? { customs.firstIndex { $0.id == id } }

    @discardableResult
    func add(from theme: Theme, name: String? = nil) -> CustomThemeSpec {
        let spec = CustomThemeSpec(name: name ?? theme.name + " copy", from: theme)
        customs.append(spec)
        return spec
    }

    func remove(_ id: String) {
        customs.removeAll { $0.id == id }
        let a = Appearance.shared
        if a.customID == id { a.customID = nil }
        for s in Workspace.shared.spaces where s.themeID == id { s.themeID = nil }
    }

    /// Panels are shown as sheets on the front window so cancelling never touches the Settings window itself.
    private func present(_ panel: NSSavePanel, _ done: @escaping (NSApplication.ModalResponse) -> Void) {
        if let w = NSApp.keyWindow { panel.beginSheetModal(for: w, completionHandler: done) }
        else { done(panel.runModal()) }
    }

    func exportTheme(_ spec: CustomThemeSpec) {
        let sp = NSSavePanel()
        sp.nameFieldStringValue = spec.name + ".panelstheme"
        sp.allowedContentTypes = [.json]
        present(sp) { response in
            guard response == .OK, let url = sp.url else { return }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(spec) { try? data.write(to: url, options: .atomic) }
        }
    }

    func importTheme(then completion: @escaping (CustomThemeSpec) -> Void) {
        let op = NSOpenPanel()
        op.allowedContentTypes = [.json]
        op.allowsMultipleSelection = false
        present(op) { [weak self] response in
            guard response == .OK, let url = op.url else { return }   // cancel does nothing
            guard let self, let data = try? Data(contentsOf: url),
                  var spec = try? JSONDecoder().decode(CustomThemeSpec.self, from: data) else {
                Workspace.shared.showToast("That file is not a Panels theme")
                return
            }
            spec.id = "custom-" + UUID().uuidString.prefix(8).lowercased()
            self.customs.append(spec)
            completion(spec)
        }
    }
}

// MARK: - Editor (Settings tab)

struct ThemesSettings: View {
    @Environment(\.theme) private var theme
    private let store = ThemeStore.shared
    private let appearance = Appearance.shared
    @State private var selected: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Themes").font(Typo.ui(15, bold: true)).foregroundStyle(theme.textC)
                    Spacer()
                    IconButton(symbol: "square.and.arrow.down", help: "Import a theme", size: 12, box: 26) {
                        store.importTheme { spec in selected = spec.id }
                    }
                    IconButton(symbol: "plus", help: "New theme from the current one", size: 12, box: 26) {
                        let s = store.add(from: appearance.theme, name: "My theme")
                        selected = s.id
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        sectionLabel("Built in")
                        ForEach(Theme.all) { t in row(t, custom: false) }
                        if !store.customs.isEmpty {
                            sectionLabel("Yours").padding(.top, 8)
                            ForEach(store.customs) { spec in row(spec.build(), custom: true) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(width: 230)

            Rectangle().fill(theme.hairline).frame(width: 1)

            Group {
                if let id = selected, store.index(of: id) != nil {
                    // Look the theme up by id on every access so a deleted theme can never index out of range.
                    CustomThemeEditor(
                        spec: Binding(
                            get: { store.customs.first { $0.id == id } ?? CustomThemeSpec(name: "", from: .granite) },
                            set: { new in if let i = store.index(of: id) { store.customs[i] = new } }),
                        onDelete: {
                            selected = Theme.all.first?.id
                            store.remove(id)
                        })
                        .id(id)
                } else if let id = selected, let t = Theme.all.first(where: { $0.id == id }) {
                    builtInDetail(t)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "paintpalette").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(theme.faintC)
                        Text("Pick a theme, or press + to design your own")
                            .font(Typo.ui(13)).foregroundStyle(theme.mutedC)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { if selected == nil { selected = appearance.theme.id } }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(Typo.ui(10, bold: true)).tracking(0.9).foregroundStyle(theme.faintC)
            .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func row(_ t: Theme, custom: Bool) -> some View {
        let on = selected == t.id
        let active = appearance.theme.id == t.id
        return HStack(spacing: 10) {
            ThemeSwatch(theme: t).frame(width: 34, height: 24)
            Text(t.name).font(Typo.ui(13, bold: on)).foregroundStyle(theme.textC).lineLimit(1)
            Spacer()
            if active { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.accentC) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? theme.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Motion.quick) { selected = t.id } }
    }

    private func builtInDetail(_ t: Theme) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(t.name).font(Typo.ui(20, bold: true)).foregroundStyle(theme.textC)
            ThemePreview(theme: t).frame(height: 190)
            HStack(spacing: 8) {
                Button { appearance.select(themeID: t.id) } label: { Label("Use This Theme", systemImage: "checkmark.circle") }
                Button {
                    let s = store.add(from: t)
                    selected = s.id
                } label: { Label("Duplicate to Edit", systemImage: "plus.square.on.square") }
            }
            Text("Built-in themes cannot be changed. Duplicate one to make it your own.")
                .font(Typo.ui(12)).foregroundStyle(theme.faintC)
            Spacer()
        }
        .padding(26)
    }
}

struct CustomThemeEditor: View {
    @Binding var spec: CustomThemeSpec
    var onDelete: () -> Void = {}
    @Environment(\.theme) private var theme
    private let store = ThemeStore.shared
    private let appearance = Appearance.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TextField("Name", text: $spec.name)
                    .textFieldStyle(.plain)
                    .font(Typo.ui(20, bold: true))
                    .foregroundStyle(theme.textC)

                ThemePreview(theme: spec.build()).frame(height: 190)

                SettingsSection(title: "Colors") {
                    ToggleRow(label: "Dark theme", isOn: $spec.isDark)
                    VStack(spacing: 8) {
                        colorRow("Window", $spec.window)
                        colorRow("Panel surface", $spec.surface)
                        colorRow("Raised surface", $spec.raised)
                        colorRow("Text", $spec.text)
                        colorRow("Muted text", $spec.muted)
                        colorRow("Faint text", $spec.faint)
                        colorRow("Accent", $spec.accent)
                    }
                }

                HStack(spacing: 8) {
                    Button { appearance.select(themeID: spec.id) } label: { Label("Use This Theme", systemImage: "checkmark.circle") }
                    Button { store.exportTheme(spec) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    Spacer()
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .padding(26)
        }
    }

    private func colorRow(_ label: String, _ hex: Binding<UInt32>) -> some View {
        HStack {
            Text(label).font(Typo.ui(12.5)).foregroundStyle(theme.mutedC)
            Spacer()
            Text(String(format: "#%06X", hex.wrappedValue))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.faintC)
            ColorPicker("", selection: Binding(get: { Color(hex: hex.wrappedValue) },
                                               set: { hex.wrappedValue = ColorMix.hex(from: $0) }),
                        supportsOpacity: false)
                .labelsHidden()
        }
    }
}

// MARK: - Previews

struct ThemeSwatch: View {
    let theme: Theme
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(theme.windowC)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(theme.surfaceC)
                    .overlay(alignment: .bottomLeading) { Circle().fill(theme.accentC).frame(width: 6, height: 6).padding(3) }
                    .padding(3)
            )
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
    }
}

/// A tiny mock of the app so a theme can be judged at a glance.
struct ThemePreview: View {
    let theme: Theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.windowC)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.alignleft").font(.system(size: 9)).foregroundStyle(theme.accentC)
                        Text("Welcome").font(Typo.ui(10, bold: true)).foregroundStyle(theme.textC)
                    }
                    Text("A quiet place to write.").font(Typo.ui(13, bold: true)).foregroundStyle(theme.textC)
                    Capsule().fill(theme.mutedC.opacity(0.7)).frame(height: 4)
                    Capsule().fill(theme.faintC.opacity(0.8)).frame(width: 90, height: 4)
                    Spacer()
                    Text("Make it yours").font(Typo.ui(10, bold: true))
                        .foregroundStyle(theme.isDark ? Color.black.opacity(0.85) : .white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(theme.accentC))
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surfaceC))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.accentC.opacity(0.6), lineWidth: 1))

                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surfaceC)
                        .overlay(Text("Tasks").font(Typo.ui(10, bold: true)).foregroundStyle(theme.mutedC))
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: theme.termBackground))
                        .overlay(Text("~ $").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color(hex: theme.termForeground)))
                }
                .frame(width: 90)
            }
            .padding(10)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
    }
}
