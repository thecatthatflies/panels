import SwiftUI
import AppKit
import AVFoundation
import Speech
import Observation

// MARK: - Preferences

struct DictationPrefs: Codable, Equatable {
    var removeFillers = true
    var autoCapitalize = true
    var spokenCommands = true
    var terminalLowercase = true
}

@Observable
final class DictationSettings {
    static let shared = DictationSettings()
    var prefs: DictationPrefs {
        didSet { if let d = try? JSONEncoder().encode(prefs) { UserDefaults.standard.set(d, forKey: "dictationPrefs") } }
    }
    init() {
        if let d = UserDefaults.standard.data(forKey: "dictationPrefs"),
           let p = try? JSONDecoder().decode(DictationPrefs.self, from: d) { prefs = p } else { prefs = DictationPrefs() }
    }
}

// MARK: - Stage 1 cleanup (rules). panels-dictation-1 replaces this in a later wave.

enum DictationCleaner {
    private static func sub(_ pattern: String, _ s: String, _ template: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    static func startsSentence(_ before: String) -> Bool {
        let trimmed = before.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
        guard let last = trimmed.last else { return true }
        return ".!?\n".contains(last) || trimmed.hasSuffix("- ") || trimmed.hasSuffix("# ")
    }

    static func clean(_ raw: String, before: String, prefs: DictationPrefs, terminal: Bool = false) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }

        if prefs.removeFillers {
            t = sub("\\b(?:um+|uh+|uhm+|erm+|er|hmm+|mm+)\\b[,.]?\\s*", t, "")
            t = t.trimmingCharacters(in: .whitespaces)
        }

        if prefs.spokenCommands && !terminal {
            t = sub("[,.]?\\s*\\bnew paragraph\\b[,.]?\\s*", t, "\n\n")
            t = sub("[,.]?\\s*\\bnew line\\b[,.]?\\s*", t, "\n")
            t = sub("^bullet(?: point)?[,.:]?\\s*", t, "- ")
            t = sub("^heading (?:one|1)[,.:]?\\s*", t, "# ")
            t = sub("^heading (?:two|2)[,.:]?\\s*", t, "## ")
            t = sub("^heading (?:three|3)[,.:]?\\s*", t, "### ")
            t = sub("^to do[,.:]?\\s*", t, "- [ ] ")
            t = sub("[ \\t]+\\n", t, "\n")
        }

        if terminal {
            if prefs.terminalLowercase { t = t.lowercased() }
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
            return t
        }

        if prefs.autoCapitalize {
            if startsSentence(before) { t = capitalizeFirstLetter(t) }
            // letters right after a newline start a new line, so they start a sentence too
            if let re = try? NSRegularExpression(pattern: "(\\n+(?:- (?:\\[ \\] )?|#+ )?)([a-z])") {
                let ns = t as NSString
                var out = ""
                var last = 0
                for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                    out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                    out += ns.substring(with: m.range(at: 1)) + ns.substring(with: m.range(at: 2)).uppercased()
                    last = NSMaxRange(m.range)
                }
                out += ns.substring(from: last)
                t = out
            }
        }

        // spacing against what is already in the document
        if let lastChar = before.last, !before.isEmpty {
            let needsSpace = !lastChar.isWhitespace && !"\n([{".contains(lastChar)
            let startsWithGap = t.first.map { $0.isWhitespace || ",.;:!?)".contains($0) } ?? false
            if needsSpace && !startsWithGap { t = " " + t }
        }
        return t
    }

    private static func capitalizeFirstLetter(_ s: String) -> String {
        var chars = Array(s)
        var i = 0
        // skip list or heading markers
        while i < chars.count, "-#[]x ".contains(chars[i]), i < 8 {
            if chars[i] == "x", i > 0, chars[i - 1] == "[" { i += 1; continue }
            if !"-#[] ".contains(chars[i]) { break }
            i += 1
        }
        if i < chars.count, chars[i].isLetter { chars[i] = Character(String(chars[i]).uppercased()) }
        return String(chars)
    }
}

// MARK: - Controller

@Observable
final class DictationController {
    static let shared = DictationController()

    enum State: Equatable { case idle, preparing(String), listening, finishing }

    var state: State = .idle
    var level: Float = 0
    var preview = ""
    var targetPanelID: UUID?
    var lastError: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var feedTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    var isActive: Bool { state != .idle }
    func isListening(for id: UUID) -> Bool { isActive && targetPanelID == id }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: start and stop

    func toggle(for panel: Panel?) {
        if isActive { stop() } else { start(panel) }
    }

    func start(_ panel: Panel?) {
        guard !isActive else { return }
        guard let panel, panel.kind == .note || panel.kind == .terminal else {
            Workspace.shared.showToast("Select a note or terminal to dictate into")
            return
        }
        generation += 1
        let mine = generation
        targetPanelID = panel.id
        lastError = nil
        preview = ""
        state = .preparing("Starting")
        Task { await run(panel: panel, generation: mine) }
    }

    private func fail(_ message: String) {
        onMain {
            self.lastError = message
            self.cleanup()
            Workspace.shared.showToast(message)
        }
    }

    private func cleanup() {
        if engine.isRunning { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        continuation?.finish()
        continuation = nil
        feedTask?.cancel()
        feedTask = nil
        state = .idle
        level = 0
        Sound.dictating(false)
        if let id = targetPanelID, let p = Workspace.shared.allPanels.first(where: { $0.id == id }), p.kind == .note {
            Runtime.shared.noteHost(for: p).endDictation()
        }
    }

    private func requestMic() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private func run(panel: Panel, generation: Int) async {
        let testFile = ProcessInfo.processInfo.environment["PANELS_DICTATION_FILE"]
        do {
            if testFile == nil {
                guard await requestMic() else {
                    fail("Microphone access is off. Allow it in System Settings, Privacy and Security.")
                    return
                }
            }
            guard SpeechTranscriber.isAvailable else { fail("Speech recognition is not available on this Mac."); return }

            let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale(identifier: "en-US")
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                onMain { self.state = .preparing("Downloading the speech model once") }
                try await request.downloadAndInstall()
            }
            guard generation == self.generation else { return }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            let (stream, cont) = AsyncStream.makeStream(of: AnalyzerInput.self)
            self.continuation = cont

            try await analyzer.start(inputSequence: stream)

            if let testFile {
                feedFile(URL(fileURLWithPath: testFile), format: format, into: cont)
            } else {
                try startMicrophone(format: format, into: cont)
            }

            onMain {
                self.state = .listening
                Sound.play(.dictateStart)
                Sound.dictating(true)
            }

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self else { return }
                        let text = String(result.text.characters)
                        let final = result.isFinal
                        self.onMain { self.deliver(text, final: final) }
                    }
                } catch {
                    self?.onMain { self?.lastError = error.localizedDescription }
                }
            }
        } catch {
            fail("Dictation could not start: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isActive, state != .finishing else { return }
        state = .finishing
        if engine.isRunning { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        continuation?.finish()
        let analyzer = self.analyzer
        let results = resultsTask
        Task { [weak self] in
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            _ = await results?.value
            self?.onMain {
                guard let self else { return }
                self.cleanup()
                Sound.play(.dictateStop)
            }
        }
    }

    // MARK: audio

    private func startMicrophone(format: AVAudioFormat?, into cont: AsyncStream<AnalyzerInput>.Continuation) throws {
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        let converter = format.flatMap { AVAudioConverter(from: inFormat, to: $0) }
        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
            self?.measure(buffer)
            if let converter, let format {
                let ratio = format.sampleRate / inFormat.sampleRate
                let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
                guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap) else { return }
                var error: NSError?
                var supplied = false
                converter.convert(to: out, error: &error) { _, status in
                    if supplied { status.pointee = .noDataNow; return nil }
                    supplied = true
                    status.pointee = .haveData
                    return buffer
                }
                if error == nil, out.frameLength > 0 { cont.yield(AnalyzerInput(buffer: out)) }
            } else {
                cont.yield(AnalyzerInput(buffer: buffer))
            }
        }
        engine.prepare()
        try engine.start()
    }

    /// Test hook: set PANELS_DICTATION_FILE to an audio file and it is streamed in real time instead of the microphone.
    private func feedFile(_ url: URL, format: AVAudioFormat?, into cont: AsyncStream<AnalyzerInput>.Continuation) {
        feedTask = Task.detached { [weak self] in
            guard let file = try? AVAudioFile(forReading: url) else { cont.finish(); return }
            let inFormat = file.processingFormat
            let converter = format.flatMap { AVAudioConverter(from: inFormat, to: $0) }
            let chunk: AVAudioFrameCount = 4096
            while !Task.isCancelled, file.framePosition < file.length {
                guard let buf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: chunk) else { break }
                do { try file.read(into: buf, frameCount: chunk) } catch { break }
                if buf.frameLength == 0 { break }
                self?.measure(buf)
                if let converter, let format {
                    let cap = AVAudioFrameCount(Double(buf.frameLength) * format.sampleRate / inFormat.sampleRate) + 32
                    if let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap) {
                        var error: NSError?
                        var supplied = false
                        converter.convert(to: out, error: &error) { _, status in
                            if supplied { status.pointee = .noDataNow; return nil }
                            supplied = true; status.pointee = .haveData; return buf
                        }
                        if error == nil, out.frameLength > 0 { cont.yield(AnalyzerInput(buffer: out)) }
                    }
                } else {
                    cont.yield(AnalyzerInput(buffer: buf))
                }
                try? await Task.sleep(nanoseconds: UInt64(Double(buf.frameLength) / inFormat.sampleRate * 1_000_000_000))
            }
            cont.finish()
            await MainActor.run { DictationController.shared.stop() }
        }
    }

    private func measure(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = sqrtf(sum / Float(n))
        let scaled = min(max(rms * 7, 0), 1)
        onMain { self.level = self.level * 0.6 + scaled * 0.4 }
    }

    // MARK: delivery

    private func deliver(_ text: String, final: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        preview = trimmed
        guard let id = targetPanelID, let panel = Workspace.shared.allPanels.first(where: { $0.id == id }) else { return }
        let prefs = DictationSettings.shared.prefs
        switch panel.kind {
        case .note:
            Runtime.shared.noteHost(for: panel).dictation(trimmed, final: final, prefs: prefs)
        case .terminal:
            guard final, !trimmed.isEmpty else { return }
            let cleaned = DictationCleaner.clean(trimmed, before: " ", prefs: prefs, terminal: true)
            if !cleaned.isEmpty { Runtime.shared.terminal(for: panel).send(cleaned + " ") }
        default:
            break
        }
    }
}

extension Workspace {
    /// Every panel in every workspace plus pop-out windows.
    var allPanels: [Panel] { spaces.flatMap { $0.panels } + popouts.map { $0.panel } }
}

// MARK: - Note insertion (live text that firms up as you speak)

extension NoteEditorHost {
    func dictation(_ raw: String, final: Bool, prefs: DictationPrefs) {
        let tv = textView
        let ns = tv.string as NSString
        if dictStart == nil {
            dictStart = min(tv.selectedRange().location, ns.length)
            dictLength = 0
        }
        guard let start = dictStart else { return }
        let before = ns.substring(to: min(start, ns.length))
        let cleaned = DictationCleaner.clean(raw, before: before, prefs: prefs)
        let old = NSRange(location: start, length: min(dictLength, max(ns.length - start, 0)))

        if !final {
            // ghost text: no undo entries, softly dimmed
            guard !cleaned.isEmpty || dictLength > 0 else { return }
            tv.undoManager?.disableUndoRegistration()
            if tv.shouldChangeText(in: old, replacementString: cleaned) {
                tv.textStorage?.replaceCharacters(in: old, with: cleaned)
                tv.didChangeText()
            }
            tv.undoManager?.enableUndoRegistration()
            dictLength = (cleaned as NSString).length
            markGhost(NSRange(location: start, length: dictLength))
            tv.setSelectedRange(NSRange(location: start + dictLength, length: 0))
            tv.scrollRangeToVisible(NSRange(location: start + dictLength, length: 0))
        } else {
            clearGhost()
            tv.undoManager?.disableUndoRegistration()
            if old.length > 0, tv.shouldChangeText(in: old, replacementString: "") {
                tv.textStorage?.replaceCharacters(in: old, with: "")
                tv.didChangeText()
            }
            tv.undoManager?.enableUndoRegistration()
            let at = NSRange(location: start, length: 0)
            if !cleaned.isEmpty, tv.shouldChangeText(in: at, replacementString: cleaned) {
                tv.textStorage?.replaceCharacters(in: at, with: cleaned)
                tv.didChangeText()
            }
            let end = start + (cleaned as NSString).length
            dictStart = end
            dictLength = 0
            tv.setSelectedRange(NSRange(location: end, length: 0))
            tv.scrollRangeToVisible(NSRange(location: end, length: 0))
        }
    }

    func endDictation() {
        clearGhost()
        dictStart = nil
        dictLength = 0
    }

    private func markGhost(_ r: NSRange) {
        guard let lm = textView.layoutManager, let style = lastStyle else { return }
        clearGhost()
        lm.addTemporaryAttribute(.foregroundColor, value: style.text.withAlphaComponent(0.55), forCharacterRange: r)
        lm.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.union(.patternDot).rawValue, forCharacterRange: r)
        lm.addTemporaryAttribute(.underlineColor, value: style.accent.withAlphaComponent(0.7), forCharacterRange: r)
    }

    private func clearGhost() {
        guard let lm = textView.layoutManager else { return }
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
        lm.removeTemporaryAttribute(.underlineColor, forCharacterRange: full)
    }
}

// MARK: - HUD

struct DictationHUD: View {
    @Environment(\.theme) private var theme
    private let dictation = DictationController.shared

    var body: some View {
        let state = dictation.state
        HStack(spacing: 12) {
            LevelBars(level: dictation.level, active: state == .listening, tint: theme.accentC)
                .frame(width: 26, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title(state))
                    .font(Typo.ui(12, bold: true))
                    .foregroundStyle(theme.textC)
                if !dictation.preview.isEmpty && state == .listening {
                    Text(dictation.preview.suffix(70))
                        .font(Typo.ui(11.5))
                        .foregroundStyle(theme.mutedC)
                        .lineLimit(1)
                        .frame(maxWidth: 280, alignment: .leading)
                        .id(dictation.preview.count)
                        .transition(.opacity)
                }
            }

            Button { dictation.stop() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill").font(.system(size: 9, weight: .bold))
                    Text("Done").font(Typo.ui(12, bold: true))
                }
                .foregroundStyle(theme.isDark ? Color.black.opacity(0.85) : Color.white)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(theme.accentC))
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 44)
        .glassEffect(.regular, in: Capsule())
        .animation(Motion.quick, value: dictation.preview)
    }

    private func title(_ s: DictationController.State) -> String {
        switch s {
        case .idle: return ""
        case .preparing(let m): return m
        case .listening: return "Listening"
        case .finishing: return "Finishing"
        }
    }
}

struct LevelBars: View {
    let level: Float
    let active: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                let weights: [Float] = [0.5, 0.8, 1, 0.8, 0.5]
                let h = active ? max(0.18, min(1, level * weights[i] * 1.6 + 0.12)) : 0.18
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: 18 * CGFloat(h))
                    .animation(.snappy(duration: 0.12), value: h)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Settings tab

struct DictationSettingsView: View {
    @Environment(\.theme) private var theme
    private let store = DictationSettings.shared

    var body: some View {
        @Bindable var s = store
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dictation").font(Typo.ui(20, bold: true)).foregroundStyle(theme.textC)
                    Text("Talk and your words appear where the caret is, firming up as you speak. Speech is recognized on this Mac. The first time you dictate, macOS downloads its speech model for your language.")
                        .font(Typo.ui(12.5)).foregroundStyle(theme.mutedC)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(title: "How to use it") {
                    row("Start and stop", "Cmd Shift M")
                    row("From a panel", "Microphone button in a note or terminal header")
                    Text("Dictation goes into the focused note or terminal. In a terminal, finished phrases are typed as lowercase text without a trailing return.")
                        .font(Typo.ui(11.5)).foregroundStyle(theme.faintC)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(title: "Cleanup") {
                    ToggleRow(label: "Remove fillers (um, uh, hmm)", isOn: $s.prefs.removeFillers)
                    ToggleRow(label: "Capitalize new sentences", isOn: $s.prefs.autoCapitalize)
                    ToggleRow(label: "Spoken formatting", isOn: $s.prefs.spokenCommands)
                    ToggleRow(label: "Lowercase text in terminals", isOn: $s.prefs.terminalLowercase)
                    Text("Say new line, new paragraph, bullet, to do or heading two at the start of a phrase.")
                        .font(Typo.ui(11.5)).foregroundStyle(theme.faintC)
                }

                SettingsSection(title: "Coming next") {
                    Text("A small on-device model, panels-dictation-1, will refine phrases using the field you are in and correct earlier words as you keep talking.")
                        .font(Typo.ui(12.5)).foregroundStyle(theme.mutedC)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Typo.ui(13)).foregroundStyle(theme.textC)
            Spacer()
            Text(value).font(Typo.ui(12)).foregroundStyle(theme.mutedC).multilineTextAlignment(.trailing)
        }
    }
}
