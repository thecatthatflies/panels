import SwiftUI

struct SoundSettingsView: View {
    @Environment(\.theme) private var theme
    private let store = SoundSettings.shared
    @State private var typingTest = ""

    var body: some View {
        @Bindable var s = store
        let on = s.prefs.masterEnabled

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sound").font(Typo.ui(20, bold: true)).foregroundStyle(theme.textC)
                    Text("Calm, synthesized sound for the interface, your typing and the background. Everything is optional and off until you switch it on. No audio files are used; every sound is generated on the fly.")
                        .font(Typo.ui(12.5)).foregroundStyle(theme.mutedC)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(title: "Master") {
                    ToggleRow(label: "Enable sound", isOn: $s.prefs.masterEnabled)
                    SliderRow(label: "Master volume", value: $s.prefs.masterVolume, range: 0...1, step: 0.01,
                              format: { String(format: "%.0f%%", $0 * 100) })
                    ToggleRow(label: "Stay quiet when Panels is in the background", isOn: $s.prefs.quietInBackground)
                }

                Group {
                    SettingsSection(title: "Interface") {
                        ToggleRow(label: "Interface sounds", isOn: $s.prefs.uiEnabled)
                        SliderRow(label: "Volume", value: $s.prefs.uiVolume, range: 0...1, step: 0.01,
                                  format: { String(format: "%.0f%%", $0 * 100) })
                        SettingRow(label: "Sound set", value: s.prefs.uiPack.blurb) {
                            SegmentedChips(options: UIPack.allCases, selection: $s.prefs.uiPack, label: { $0.label })
                        }
                        SettingRow(label: "Preview") {
                            FlowLayout(spacing: 6) {
                                ForEach(SoundCue.allCases) { cue in
                                    Button { Sound.play(cue) } label: {
                                        Text(cue.label)
                                            .font(Typo.ui(11.5))
                                            .foregroundStyle(theme.mutedC)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Capsule().fill(theme.hover))
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(PressStyle())
                                }
                            }
                        }
                    }

                    SettingsSection(title: "Typing") {
                        ToggleRow(label: "Typing sounds", isOn: $s.prefs.typingEnabled)
                        SliderRow(label: "Volume", value: $s.prefs.typingVolume, range: 0...1, step: 0.01,
                                  format: { String(format: "%.0f%%", $0 * 100) })
                        SettingRow(label: "Keyboard", value: s.prefs.typingPack.blurb) {
                            SegmentedChips(options: TypingPack.allCases, selection: $s.prefs.typingPack, label: { $0.label })
                        }
                        SettingRow(label: "Try it") {
                            HStack(spacing: 8) {
                                TypingTestField(text: $typingTest)
                                Button { SoundEngine.shared.previewTyping() } label: { Label("Play", systemImage: "play.fill") }
                            }
                        }
                    }

                    SettingsSection(title: "Ambient") {
                        ToggleRow(label: "Background sound", isOn: $s.prefs.ambientEnabled)
                        SliderRow(label: "Volume", value: $s.prefs.ambientVolume, range: 0...1, step: 0.01,
                                  format: { String(format: "%.0f%%", $0 * 100) })
                        SettingRow(label: "Mixes") {
                            FlowLayout(spacing: 6) {
                                ForEach(AmbientPreset.all) { preset in
                                    Button { applyPreset(preset) } label: {
                                        Text(preset.name)
                                            .font(Typo.ui(11.5))
                                            .foregroundStyle(theme.textC)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Capsule().fill(theme.hover))
                                            .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(PressStyle())
                                }
                            }
                        }
                        VStack(spacing: 10) {
                            ForEach(AmbientLayer.allCases) { layer in
                                HStack(spacing: 10) {
                                    Image(systemName: layer.symbol)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(store.layerVolume(layer) > 0 ? theme.accentC : theme.faintC)
                                        .frame(width: 20)
                                    Text(layer.label).font(Typo.ui(12.5)).foregroundStyle(theme.textC).frame(width: 88, alignment: .leading)
                                    Slider(value: Binding(get: { store.layerVolume(layer) }, set: { store.setLayer(layer, $0) }), in: 0...1)
                                        .controlSize(.small)
                                        .tint(theme.accentC)
                                }
                            }
                        }
                        ToggleRow(label: "Only play ambient sound in Lock In", isOn: $s.prefs.ambientOnlyInLockIn)
                        ToggleRow(label: "Lower ambient sound while dictating", isOn: $s.prefs.duckForDictation)
                    }
                }
                .disabled(!on)
                .opacity(on ? 1 : 0.45)
                .animation(Motion.quick, value: on)
            }
            .padding(28)
        }
    }

    private func applyPreset(_ p: AmbientPreset) {
        var layers: [Int: Double] = [:]
        for l in AmbientLayer.allCases { layers[l.rawValue] = p.mix[l] ?? 0 }
        store.prefs.layers = layers
        store.prefs.ambientEnabled = true
    }
}

/// A plain text field that plays the chosen typing sound for each key, so you can hear a set before picking it.
struct TypingTestField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSTextField {
        let f = SoundTestField()
        f.placeholderString = "Type here to hear it"
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = NSFont.systemFont(ofSize: 13)
        f.delegate = context.coordinator
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) { if f.stringValue != text { f.stringValue = text } }
    func makeCoordinator() -> Coord { Coord(self) }

    final class Coord: NSObject, NSTextFieldDelegate {
        let parent: TypingTestField
        init(_ p: TypingTestField) { parent = p }
        func controlTextDidChange(_ obj: Notification) {
            if let f = obj.object as? NSTextField { parent.text = f.stringValue }
        }
    }
}

final class SoundTestField: NSTextField {
    override func keyDown(with event: NSEvent) {
        Sound.type(SoundClassify.kind(for: event) ?? .key)
        super.keyDown(with: event)
    }
}

enum SoundClassify {
    /// Maps a key event to a typing sound kind, or nil for keys that should stay silent.
    static func kind(for event: NSEvent) -> TypingKind? {
        let flags = event.modifierFlags
        if flags.contains(.command) || flags.contains(.control) { return nil }
        switch event.keyCode {
        case 49: return .space
        case 36, 76: return .enter
        case 51, 117: return .back
        case 123...126, 53, 48, 115...121: return nil
        default:
            guard let c = event.characters, let u = c.unicodeScalars.first, u.value >= 32, !(0xF700...0xF8FF).contains(u.value) else { return nil }
            return .key
        }
    }
}
