import AVFoundation
import AppKit
import Observation

// MARK: - Vocabulary

enum SoundCue: String, CaseIterable, Identifiable {
    case tick, open, close, split, swap, lockIn, lockOut, drop, toggle, success, toast, timerEnd, dictateStart, dictateStop, error, update
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tick: return "Tick"
        case .open: return "Open"
        case .close: return "Close"
        case .split: return "Split"
        case .swap: return "Workspace"
        case .lockIn: return "Lock in"
        case .lockOut: return "Lock out"
        case .drop: return "Drop"
        case .toggle: return "Toggle"
        case .success: return "Done"
        case .toast: return "Notice"
        case .timerEnd: return "Timer end"
        case .dictateStart: return "Listen"
        case .dictateStop: return "Stop"
        case .error: return "Error"
        case .update: return "Update"
        }
    }
}

enum UIPack: String, CaseIterable, Identifiable, Codable {
    case soft, glass, wood, pluck
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var blurb: String {
        switch self {
        case .soft: return "Warm, rounded blips"
        case .glass: return "Bright, bell-like"
        case .wood: return "Marimba, short and dry"
        case .pluck: return "Plucked strings"
        }
    }
}

enum TypingPack: String, CaseIterable, Identifiable, Codable {
    case soft, thock, typewriter, bubble, mechanical
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var blurb: String {
        switch self {
        case .soft: return "Quiet membrane keys"
        case .thock: return "Deep, creamy switches"
        case .typewriter: return "Strikes and a bell on return"
        case .bubble: return "Little water pops"
        case .mechanical: return "Clicky, two-stage"
        }
    }
}

enum TypingKind: Int, CaseIterable { case key, space, back, enter }

enum AmbientLayer: Int, CaseIterable, Identifiable, Codable {
    case rain, ocean, fire, brown, pink, pad
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .rain: return "Rain"
        case .ocean: return "Ocean"
        case .fire: return "Fireplace"
        case .brown: return "Deep hum"
        case .pink: return "Soft static"
        case .pad: return "Warm pad"
        }
    }
    var symbol: String {
        switch self {
        case .rain: return "cloud.rain"
        case .ocean: return "water.waves"
        case .fire: return "flame"
        case .brown: return "waveform.path"
        case .pink: return "wind"
        case .pad: return "pianokeys"
        }
    }
}

struct AmbientPreset: Identifiable {
    let id: String
    let name: String
    let mix: [AmbientLayer: Double]

    static let all: [AmbientPreset] = [
        AmbientPreset(id: "rainy", name: "Rainy focus", mix: [.rain: 0.7, .brown: 0.25, .pad: 0.2]),
        AmbientPreset(id: "ocean", name: "Ocean desk", mix: [.ocean: 0.75, .pink: 0.1, .pad: 0.15]),
        AmbientPreset(id: "fire", name: "Fireplace", mix: [.fire: 0.7, .brown: 0.3]),
        AmbientPreset(id: "deep", name: "Deep brown", mix: [.brown: 0.8]),
        AmbientPreset(id: "quiet", name: "Quiet pad", mix: [.pad: 0.6, .pink: 0.08])
    ]
}

// MARK: - Preferences

struct SoundPrefs: Codable, Equatable {
    var masterEnabled = false
    var masterVolume = 0.7

    var uiEnabled = true
    var uiVolume = 0.6
    var uiPack: UIPack = .soft

    var typingEnabled = true
    var typingVolume = 0.5
    var typingPack: TypingPack = .soft

    var ambientEnabled = true
    var ambientVolume = 0.5
    var layers: [Int: Double] = [AmbientLayer.rain.rawValue: 0.6, AmbientLayer.pad.rawValue: 0.2]
    var ambientOnlyInLockIn = false
    var duckForDictation = true
    var quietInBackground = true
}

@Observable
final class SoundSettings {
    static let shared = SoundSettings()

    var prefs: SoundPrefs {
        didSet {
            if let data = try? JSONEncoder().encode(prefs) { UserDefaults.standard.set(data, forKey: "soundPrefs") }
            SoundEngine.shared.prefsChanged(old: oldValue, new: prefs)
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "soundPrefs"),
           let decoded = try? JSONDecoder().decode(SoundPrefs.self, from: data) {
            prefs = decoded
        } else {
            prefs = SoundPrefs()
        }
    }

    func layerVolume(_ l: AmbientLayer) -> Double { prefs.layers[l.rawValue] ?? 0 }
    func setLayer(_ l: AmbientLayer, _ v: Double) { prefs.layers[l.rawValue] = v }
}

/// Fire-and-forget entry points used across the app.
enum Sound {
    static func play(_ cue: SoundCue) { SoundEngine.shared.play(cue) }
    static func type(_ kind: TypingKind) { SoundEngine.shared.type(kind) }
    static func lockIn(_ on: Bool) { SoundEngine.shared.setLockIn(on) }
    static func dictating(_ on: Bool) { SoundEngine.shared.setDictating(on) }
}

// MARK: - DSP helpers

struct SynthRNG {
    var s: UInt32
    init(seed: UInt32) { s = seed == 0 ? 0x9E3779B9 : seed }
    mutating func next() -> Float {
        s ^= s << 13; s ^= s >> 17; s ^= s << 5
        return Float(Int32(bitPattern: s)) / 2_147_483_648
    }
    mutating func unit() -> Float { (next() + 1) * 0.5 }
}

struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0

    enum Kind { case low, high, band }

    init(_ kind: Kind, freq: Float, q: Float, sr: Float) {
        let w0 = 2 * Float.pi * min(freq, sr * 0.45) / sr
        let alpha = sin(w0) / (2 * q)
        let c = cos(w0)
        var a0: Float = 1 + alpha
        switch kind {
        case .low:
            b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2
        case .high:
            b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2
        case .band:
            b0 = alpha; b1 = 0; b2 = -alpha
        }
        a1 = -2 * c; a0 = 1 + alpha
        let a2n = 1 - alpha
        b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 = a2n / a0
    }

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

enum Synth {
    static let sr: Float = 44100

    static func hz(_ midi: Float) -> Float { 440 * pow(2, (midi - 69) / 12) }

    static func format() -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: Double(sr), channels: 2)!
    }

    static func makeBuffer(_ mono: [Float], pan: Float = 0, gain: Float = 1) -> AVAudioPCMBuffer {
        let n = mono.count
        let buf = AVAudioPCMBuffer(pcmFormat: format(), frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        let l = buf.floatChannelData![0], r = buf.floatChannelData![1]
        let gl = gain * (pan <= 0 ? 1 : 1 - pan * 0.6)
        let gr = gain * (pan >= 0 ? 1 : 1 + pan * 0.6)
        for i in 0..<n { l[i] = mono[i] * gl; r[i] = mono[i] * gr }
        return buf
    }

    static func normalize(_ x: inout [Float], peak: Float = 0.9) {
        let m = x.reduce(0) { max($0, abs($1)) }
        guard m > 0.0001 else { return }
        let g = peak / m
        for i in 0..<x.count { x[i] *= g }
    }

    // MARK: tonal voices

    static func addTone(_ out: inout [Float], start: Float, freq: Float, dur: Float, amp: Float, timbre: UIPack) {
        let s0 = Int(start * sr)
        let n = Int(dur * sr)
        guard s0 < out.count else { return }
        let end = min(out.count, s0 + n)
        switch timbre {
        case .soft:
            let tau = dur / 4.2
            for i in s0..<end {
                let t = Float(i - s0) / sr
                let env = min(t / 0.008, 1) * exp(-t / tau)
                let p = 2 * Float.pi * freq * t
                out[i] += amp * env * (sin(p) + 0.16 * sin(2 * p) + 0.04 * sin(3 * p))
            }
        case .glass:
            let partials: [(Float, Float, Float)] = [(1, 1, 1), (2.76, 0.42, 0.55), (5.4, 0.2, 0.3), (8.93, 0.09, 0.18)]
            for i in s0..<end {
                let t = Float(i - s0) / sr
                var v: Float = 0
                for (ratio, a, d) in partials {
                    v += a * exp(-t / (dur / 3 * d)) * sin(2 * Float.pi * freq * ratio * t)
                }
                out[i] += amp * min(t / 0.002, 1) * v * 0.7
            }
        case .wood:
            for i in s0..<end {
                let t = Float(i - s0) / sr
                let env = min(t / 0.0015, 1) * exp(-t / (dur / 6))
                let p = 2 * Float.pi * freq * t
                out[i] += amp * env * (sin(p) + 0.35 * exp(-t * 40) * sin(4.0 * p) + 0.08 * sin(9.9 * p) * exp(-t * 80))
            }
        case .pluck:
            let delay = max(Int(sr / freq), 2)
            var line = [Float](repeating: 0, count: delay)
            var rng = SynthRNG(seed: UInt32(freq * 10) &+ 77)
            for i in 0..<delay { line[i] = rng.next() * 0.9 }
            var idx = 0
            for i in s0..<end {
                let cur = line[idx]
                let nxt = line[(idx + 1) % delay]
                line[idx] = (cur + nxt) * 0.5 * 0.9965
                out[i] += amp * cur * 0.9 * min(Float(i - s0) / 60, 1)
                idx = (idx + 1) % delay
            }
        }
    }

    static func addNoiseSweep(_ out: inout [Float], start: Float, dur: Float, from: Float, to: Float, amp: Float, seed: UInt32) {
        let s0 = Int(start * sr)
        let n = Int(dur * sr)
        var rng = SynthRNG(seed: seed)
        var bp = Biquad(.band, freq: from, q: 1.2, sr: sr)
        for i in 0..<n where s0 + i < out.count {
            let t = Float(i) / Float(n)
            if i % 32 == 0 { bp = Biquad(.band, freq: from + (to - from) * t, q: 1.2, sr: sr) }
            let env = sin(Float.pi * t)
            out[s0 + i] += amp * env * bp.process(rng.next()) * 2.2
        }
    }

    static func addThump(_ out: inout [Float], start: Float, freq: Float, drop: Float, decay: Float, amp: Float) {
        let s0 = Int(start * sr)
        let n = Int(decay * 5 * sr)
        var phase: Float = 0
        for i in 0..<n where s0 + i < out.count {
            let t = Float(i) / sr
            let f = freq * (1 - drop * (1 - exp(-t / (decay * 0.6))))
            phase += 2 * Float.pi * f / sr
            out[s0 + i] += amp * min(t / 0.0015, 1) * exp(-t / decay) * sin(phase)
        }
    }

    static func addClick(_ out: inout [Float], start: Float, center: Float, q: Float, dur: Float, amp: Float, seed: UInt32) {
        let s0 = Int(start * sr)
        let n = Int(dur * 6 * sr)
        var rng = SynthRNG(seed: seed)
        var bp = Biquad(.band, freq: center, q: q, sr: sr)
        for i in 0..<n where s0 + i < out.count {
            let t = Float(i) / sr
            out[s0 + i] += amp * exp(-t / dur) * bp.process(rng.next()) * 2.4
        }
    }

    // MARK: one-shot cues

    static func render(_ cue: SoundCue, pack: UIPack, variant: Int) -> AVAudioPCMBuffer {
        let pv: Float = 1 + (Float(variant % 4) - 1.5) * 0.012
        var out = [Float](repeating: 0, count: Int(sr * 2.4))
        func tone(_ midi: Float, _ at: Float, _ dur: Float, _ amp: Float = 0.5) {
            addTone(&out, start: at, freq: hz(midi) * pv, dur: dur, amp: amp, timbre: pack)
        }
        switch cue {
        case .tick: tone(88, 0, 0.09, 0.38)
        case .toggle: tone(84, 0, 0.1, 0.4)
        case .open: tone(76, 0, 0.18, 0.42); tone(83, 0.055, 0.24, 0.42)
        case .close: tone(83, 0, 0.14, 0.32); tone(76, 0.05, 0.2, 0.32)
        case .split:
            tone(79, 0, 0.11, 0.36); tone(86, 0.045, 0.15, 0.36)
            addNoiseSweep(&out, start: 0, dur: 0.12, from: 1200, to: 3200, amp: 0.06, seed: 91 &+ UInt32(variant))
        case .swap:
            addNoiseSweep(&out, start: 0, dur: 0.16, from: 700, to: 2400, amp: 0.2, seed: 133 &+ UInt32(variant))
            tone(72, 0.02, 0.1, 0.12)
        case .lockIn:
            let n = Int(0.95 * sr)
            for i in 0..<n {
                let t = Float(i) / sr
                let env = pow(sin(Float.pi * min(t / 0.95, 1) * 0.5 + 0.0001), 2) * exp(-max(t - 0.45, 0) * 2.4)
                let v = sin(2 * Float.pi * 110 * t) + 0.6 * sin(2 * Float.pi * 164.8 * t) + 0.4 * sin(2 * Float.pi * 220 * t)
                out[i] += 0.22 * env * v
            }
        case .lockOut:
            let n = Int(0.55 * sr)
            for i in 0..<n {
                let t = Float(i) / sr
                let env = exp(-t * 4.5) * min(t / 0.01, 1)
                out[i] += 0.2 * env * (sin(2 * Float.pi * 196 * t) + 0.5 * sin(2 * Float.pi * 294 * t))
            }
        case .drop:
            addThump(&out, start: 0, freq: 170, drop: 0.4, decay: 0.05, amp: 0.6)
            addClick(&out, start: 0, center: 1500, q: 0.8, dur: 0.008, amp: 0.3, seed: 41 &+ UInt32(variant))
        case .success: tone(76, 0, 0.7, 0.3); tone(80, 0.06, 0.7, 0.28); tone(83, 0.12, 0.85, 0.28)
        case .toast: tone(88, 0, 0.18, 0.34)
        case .timerEnd:
            tone(72, 0, 1.2, 0.3); tone(76, 0.35, 1.2, 0.3); tone(79, 0.7, 1.3, 0.3); tone(84, 1.05, 1.3, 0.3)
        case .dictateStart: tone(79, 0, 0.1, 0.36); tone(86, 0.07, 0.15, 0.36)
        case .dictateStop: tone(86, 0, 0.09, 0.3); tone(79, 0.06, 0.16, 0.3)
        case .error:
            addThump(&out, start: 0, freq: 90, drop: 0.2, decay: 0.12, amp: 0.7)
            addClick(&out, start: 0, center: 600, q: 0.7, dur: 0.02, amp: 0.2, seed: 7)
        case .update: tone(74, 0, 0.5, 0.3); tone(81, 0.12, 0.6, 0.3); tone(86, 0.24, 0.8, 0.3)
        }
        // trim trailing silence
        var last = out.count - 1
        while last > 0 && abs(out[last]) < 0.0008 { last -= 1 }
        out = Array(out[0...min(last + 200, out.count - 1)])
        normalize(&out, peak: 0.8)
        // short fade out to avoid a click
        let fade = min(400, out.count)
        for i in 0..<fade { out[out.count - 1 - i] *= Float(i) / Float(fade) }
        return makeBuffer(out, pan: (Float(variant % 3) - 1) * 0.08)
    }

    // MARK: typing

    static func renderKey(_ pack: TypingPack, kind: TypingKind, variant: Int) -> AVAudioPCMBuffer {
        var rng = SynthRNG(seed: UInt32(variant * 977 + kind.rawValue * 131 + 17))
        let pv: Float = 0.94 + rng.unit() * 0.12
        let amp: Float = 0.82 + rng.unit() * 0.18
        var out = [Float](repeating: 0, count: Int(sr * 1.1))
        let sd = UInt32(variant * 31 + kind.rawValue * 7 + 5)

        switch pack {
        case .soft:
            switch kind {
            case .key:
                addThump(&out, start: 0, freq: 170 * pv, drop: 0.35, decay: 0.045, amp: 0.55)
                addClick(&out, start: 0, center: 2200 * pv, q: 0.7, dur: 0.012, amp: 0.22, seed: sd)
            case .space:
                addThump(&out, start: 0, freq: 120 * pv, drop: 0.35, decay: 0.07, amp: 0.65)
                addClick(&out, start: 0, center: 1600, q: 0.7, dur: 0.016, amp: 0.2, seed: sd)
            case .back:
                addThump(&out, start: 0, freq: 215 * pv, drop: 0.3, decay: 0.035, amp: 0.45)
                addClick(&out, start: 0, center: 2800, q: 0.8, dur: 0.01, amp: 0.2, seed: sd)
            case .enter:
                addThump(&out, start: 0, freq: 135 * pv, drop: 0.35, decay: 0.07, amp: 0.65)
                addThump(&out, start: 0.03, freq: 100, drop: 0.3, decay: 0.08, amp: 0.4)
                addClick(&out, start: 0, center: 1800, q: 0.7, dur: 0.018, amp: 0.25, seed: sd)
            }
        case .thock:
            let base: Float = kind == .space ? 90 : (kind == .enter ? 100 : (kind == .back ? 125 : 110))
            addThump(&out, start: 0, freq: base * pv, drop: 0.45, decay: kind == .space ? 0.11 : 0.08, amp: 0.75)
            addClick(&out, start: 0, center: 1400 * pv, q: 0.8, dur: 0.015, amp: 0.25, seed: sd)
            addClick(&out, start: 0, center: 4500, q: 1, dur: 0.004, amp: 0.1, seed: sd &+ 1)
            if kind == .enter { addThump(&out, start: 0.035, freq: 80, drop: 0.3, decay: 0.1, amp: 0.4) }
        case .typewriter:
            addClick(&out, start: 0, center: 2800 * pv, q: 1.2, dur: 0.01, amp: 0.6, seed: sd)
            addThump(&out, start: 0, freq: 140, drop: 0.4, decay: 0.05, amp: 0.35)
            let ping = 4200 * pv
            for i in 0..<Int(0.14 * sr) {
                let t = Float(i) / sr
                out[i] += 0.1 * exp(-t / 0.03) * sin(2 * Float.pi * ping * t)
            }
            if kind == .space { addThump(&out, start: 0, freq: 100, drop: 0.4, decay: 0.07, amp: 0.4) }
            if kind == .enter {
                let bellBase: Float = 2093
                let bellParts: [(Float, Float)] = [(1, 0.3), (2.76, 0.1), (5.4, 0.1)]
                let shift = Int(0.05 * sr)
                let count = Int(0.9 * sr)
                for (ratio, a) in bellParts {
                    let freq: Float = bellBase * ratio
                    for i in 0..<count {
                        let t: Float = Float(i) / sr + 0.05
                        let idx = i + shift
                        if idx < out.count {
                            let decay: Float = exp(-t / 0.28)
                            let wave: Float = sin(2 * Float.pi * freq * t)
                            out[idx] += a * decay * wave
                        }
                    }
                }
                addNoiseSweep(&out, start: 0.02, dur: 0.22, from: 1200, to: 600, amp: 0.15, seed: sd)
            }
        case .bubble:
            let (f0, f1): (Float, Float)
            switch kind {
            case .key: (f0, f1) = (380 * pv, 950 * pv)
            case .space: (f0, f1) = (260 * pv, 560 * pv)
            case .back: (f0, f1) = (760 * pv, 320 * pv)
            case .enter: (f0, f1) = (420 * pv, 1100 * pv)
            }
            let n = Int(0.09 * sr)
            var phase: Float = 0
            for i in 0..<n {
                let t = Float(i) / sr
                let f = f0 + (f1 - f0) * min(t / 0.035, 1)
                phase += 2 * Float.pi * f / sr
                out[i] += 0.55 * exp(-t / 0.028) * min(t / 0.002, 1) * sin(phase)
            }
        case .mechanical:
            addClick(&out, start: 0, center: 3400 * pv, q: 1.4, dur: 0.007, amp: 0.62, seed: sd)
            addThump(&out, start: 0, freq: (kind == .space ? 105 : 150) * pv, drop: 0.45, decay: 0.045, amp: 0.4)
            addClick(&out, start: 0.075, center: 2600, q: 1.2, dur: 0.005, amp: 0.24, seed: sd &+ 3)
            if kind == .enter { addThump(&out, start: 0.02, freq: 90, drop: 0.3, decay: 0.08, amp: 0.4) }
        }
        var last = out.count - 1
        while last > 0 && abs(out[last]) < 0.0008 { last -= 1 }
        out = Array(out[0...min(last + 100, out.count - 1)])
        normalize(&out, peak: 0.85)
        return makeBuffer(out, pan: (rng.next() * 0.12), gain: amp)
    }
}

// MARK: - Ambient synthesizer (real time)

final class AmbientSynth {
    static let layerCount = 6
    let sr: Float
    let targets = UnsafeMutablePointer<Float>.allocate(capacity: 8)   // layer volumes 0..5, master at 6
    private let current = UnsafeMutablePointer<Float>.allocate(capacity: 8)

    private var rng = SynthRNG(seed: 0xA5A5)
    private var pinkL = [Float](repeating: 0, count: 7)
    private var pinkR = [Float](repeating: 0, count: 7)
    private var brownL: Float = 0, brownR: Float = 0
    private var rainHpL: Float = 0, rainHpR: Float = 0
    private var oceanPhaseL: Float = 0, oceanPhaseR: Float = 0.9
    private var oceanLowL: Float = 0, oceanLowR: Float = 0
    private var fireLowL: Float = 0, fireLowR: Float = 0
    private var crackle: Float = 0, crackleHp: Float = 0
    private var padPhase = [Float](repeating: 0, count: 10)
    private var padLfo = [Float](repeating: 0, count: 5)
    private var padLow: (Float, Float) = (0, 0)
    private var dropAmp = [Float](repeating: 0, count: 24)
    private var dropFreq = [Float](repeating: 0, count: 24)
    private var dropPhase = [Float](repeating: 0, count: 24)
    private var dropPan = [Float](repeating: 0, count: 24)
    private var dropIdx = 0
    private let padFreqs: [Float] = [110, 164.81, 220, 277.18, 329.63]

    init(sampleRate: Float) {
        sr = sampleRate
        for i in 0..<8 { targets[i] = 0; current[i] = 0 }
        for i in 0..<5 { padLfo[i] = Float(i) * 1.3 }
    }

    deinit { targets.deallocate(); current.deallocate() }

    @inline(__always) private func pink(_ w: Float, _ b: inout [Float]) -> Float {
        b[0] = 0.99886 * b[0] + w * 0.0555179
        b[1] = 0.99332 * b[1] + w * 0.0750759
        b[2] = 0.96900 * b[2] + w * 0.1538520
        b[3] = 0.86650 * b[3] + w * 0.3104856
        b[4] = 0.55000 * b[4] + w * 0.5329522
        b[5] = -0.7616 * b[5] - w * 0.0168980
        let p = b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + w * 0.5362
        b[6] = w * 0.115926
        return p * 0.11
    }

    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        let smooth: Float = 0.0004
        let twoPi = 2 * Float.pi
        for n in 0..<frames {
            for k in 0..<7 { current[k] += (targets[k] - current[k]) * smooth }
            let master = current[6]
            if master < 0.0002 { left[n] = 0; right[n] = 0; continue }
            var l: Float = 0, r: Float = 0

            let wl = rng.next(), wr = rng.next()

            // rain
            if current[0] > 0.001 {
                let pl = pink(wl, &pinkL), pr = pink(wr, &pinkR)
                rainHpL += 0.07 * (pl - rainHpL); rainHpR += 0.07 * (pr - rainHpR)
                var rl = (pl - rainHpL) * 1.5, rr = (pr - rainHpR) * 1.5
                if rng.unit() < 26 / sr {
                    dropAmp[dropIdx] = 0.25 + rng.unit() * 0.5
                    dropFreq[dropIdx] = 2200 + rng.unit() * 4200
                    dropPhase[dropIdx] = 0
                    dropPan[dropIdx] = rng.next()
                    dropIdx = (dropIdx + 1) % 24
                }
                for d in 0..<24 where dropAmp[d] > 0.001 {
                    dropPhase[d] += twoPi * dropFreq[d] / sr
                    let v = dropAmp[d] * sin(dropPhase[d]) * 0.35
                    dropAmp[d] *= 0.9965
                    rl += v * (1 - max(dropPan[d], 0)); rr += v * (1 + min(dropPan[d], 0))
                }
                l += rl * current[0] * 0.8; r += rr * current[0] * 0.8
            }

            // ocean
            if current[1] > 0.001 {
                oceanPhaseL += twoPi * 0.055 / sr; oceanPhaseR += twoPi * 0.062 / sr
                let swL = 0.5 + 0.5 * sin(oceanPhaseL), swR = 0.5 + 0.5 * sin(oceanPhaseR)
                brownL = (brownL + 0.02 * wl) / 1.02; brownR = (brownR + 0.02 * wr) / 1.02
                oceanLowL += 0.05 * (brownL * 3.5 - oceanLowL); oceanLowR += 0.05 * (brownR * 3.5 - oceanLowR)
                let hissL = pink(wl, &pinkL) * pow(swL, 3) * 0.5, hissR = pink(wr, &pinkR) * pow(swR, 3) * 0.5
                l += (oceanLowL * (0.25 + 0.75 * pow(swL, 1.6)) * 1.6 + hissL) * current[1]
                r += (oceanLowR * (0.25 + 0.75 * pow(swR, 1.6)) * 1.6 + hissR) * current[1]
            }

            // fire
            if current[2] > 0.001 {
                fireLowL += 0.012 * (wl - fireLowL); fireLowR += 0.012 * (wr - fireLowR)
                if rng.unit() < 14 / sr { crackle = 0.4 + rng.unit() * 0.6 }
                else if crackle > 0.05, rng.unit() < 0.0006 { crackle = max(crackle, 0.3 + rng.unit() * 0.4) }
                crackle *= 0.9987
                let nz = rng.next()
                crackleHp += 0.4 * (nz - crackleHp)
                let c = (nz - crackleHp) * crackle * crackle
                l += (fireLowL * 3.2 + c * 0.9) * current[2]
                r += (fireLowR * 3.2 + c * 0.9 * (0.6 + rng.unit() * 0.4)) * current[2]
            }

            // deep hum (brown)
            if current[3] > 0.001 {
                brownL = (brownL + 0.02 * wl) / 1.02; brownR = (brownR + 0.02 * wr) / 1.02
                l += brownL * 3.0 * current[3]; r += brownR * 3.0 * current[3]
            }

            // soft static (pink)
            if current[4] > 0.001 {
                l += pink(wl, &pinkL) * 0.9 * current[4]; r += pink(wr, &pinkR) * 0.9 * current[4]
            }

            // warm pad
            if current[5] > 0.001 {
                var pl: Float = 0, pr: Float = 0
                for v in 0..<5 {
                    padLfo[v] += twoPi * (0.03 + 0.012 * Float(v)) / sr
                    let amp = 0.5 + 0.5 * sin(padLfo[v])
                    padPhase[v * 2] += twoPi * padFreqs[v] * 0.9985 / sr
                    padPhase[v * 2 + 1] += twoPi * padFreqs[v] * 1.0015 / sr
                    pl += sin(padPhase[v * 2]) * amp
                    pr += sin(padPhase[v * 2 + 1]) * amp
                }
                padLow.0 += 0.08 * (pl - padLow.0); padLow.1 += 0.08 * (pr - padLow.1)
                l += padLow.0 * 0.11 * current[5]; r += padLow.1 * 0.11 * current[5]
            }

            // soft limiter
            l = tanhf(l * master); r = tanhf(r * master)
            left[n] = l * 0.7; right[n] = r * 0.7
        }
        if padPhase[0] > 100_000 { for i in 0..<padPhase.count { padPhase[i] = fmodf(padPhase[i], twoPi) } }
    }
}

// MARK: - Engine

final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let uiMixer = AVAudioMixerNode()
    private let typingMixer = AVAudioMixerNode()
    private let ambientMixer = AVAudioMixerNode()
    private var uiPlayers: [AVAudioPlayerNode] = []
    private var typingPlayers: [AVAudioPlayerNode] = []
    private var uiIndex = 0
    private var typingIndex = 0
    private var uiBuffers: [SoundCue: [AVAudioPCMBuffer]] = [:]
    private var typingBuffers: [TypingKind: [AVAudioPCMBuffer]] = [:]
    private var builtUIPack: UIPack?
    private var builtTypingPack: TypingPack?
    private var ambient: AmbientSynth?
    private var ambientNode: AVAudioSourceNode?
    private var built = false
    private var lockedIn = false
    private var dictating = false
    private var lastTypeTime: CFAbsoluteTime = 0
    private var stopWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "panels.sound", qos: .userInitiated)

    private var prefs: SoundPrefs { SoundSettings.shared.prefs }
    var isEngineRunning: Bool { engine.isRunning }

    // MARK: lifecycle

    private func buildGraphIfNeeded() {
        guard !built else { return }
        built = true
        let fmt = Synth.format()
        for m in [uiMixer, typingMixer, ambientMixer] { engine.attach(m); engine.connect(m, to: engine.mainMixerNode, format: fmt) }
        for _ in 0..<6 {
            let p = AVAudioPlayerNode(); engine.attach(p); engine.connect(p, to: uiMixer, format: fmt); uiPlayers.append(p)
        }
        for _ in 0..<8 {
            let p = AVAudioPlayerNode(); engine.attach(p); engine.connect(p, to: typingMixer, format: fmt); typingPlayers.append(p)
        }
        let synth = AmbientSynth(sampleRate: Synth.sr)
        ambient = synth
        let node = AVAudioSourceNode(format: fmt) { [unowned synth] _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let l = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = abl[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(frames: Int(frameCount), left: l, right: r)
            return noErr
        }
        ambientNode = node
        engine.attach(node)
        engine.connect(node, to: ambientMixer, format: fmt)
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.shouldRun { try? self.engine.start(); self.startPlayers() }
        }
    }

    private var shouldRun: Bool {
        let p = prefs
        return p.masterEnabled && (p.uiEnabled || p.typingEnabled || p.ambientEnabled)
    }

    private func startPlayers() {
        for p in uiPlayers + typingPlayers where !p.isPlaying { p.play() }
    }

    private func ensureRunning() {
        guard shouldRun else { return }
        buildGraphIfNeeded()
        stopWork?.cancel()
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return }
        }
        startPlayers()
    }

    private func scheduleStopIfIdle() {
        stopWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.shouldRun else { return }
            self.engine.pause()
        }
        stopWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
    }

    // MARK: prefs

    func prefsChanged(old: SoundPrefs, new: SoundPrefs) {
        if shouldRun { ensureRunning() } else { applyAmbientTargets(); scheduleStopIfIdle() }
        if shouldRun {
            uiMixer.outputVolume = Float(new.uiEnabled ? new.uiVolume : 0)
            typingMixer.outputVolume = Float(new.typingEnabled ? new.typingVolume : 0)
            if new.uiPack != old.uiPack { builtUIPack = nil; uiBuffers.removeAll() }
            if new.typingPack != old.typingPack { builtTypingPack = nil; typingBuffers.removeAll() }
            engine.mainMixerNode.outputVolume = Float(new.masterVolume)
            applyAmbientTargets()
        }
    }

    func setLockIn(_ on: Bool) { lockedIn = on; applyAmbientTargets() }
    func setDictating(_ on: Bool) { dictating = on; applyAmbientTargets() }

    private func applyAmbientTargets() {
        guard let a = ambient else { if shouldRun { buildGraphIfNeeded() }; return }
        let p = prefs
        let active = shouldRun && p.ambientEnabled && (!p.ambientOnlyInLockIn || lockedIn)
        for layer in AmbientLayer.allCases {
            a.targets[layer.rawValue] = active ? Float(p.layers[layer.rawValue] ?? 0) : 0
        }
        var master = Float(p.ambientVolume)
        if dictating && p.duckForDictation { master *= 0.25 }
        a.targets[6] = active ? master : 0
        ambientMixer.outputVolume = 1
        if shouldRun { ensureRunning() }
    }

    // MARK: playback

    private var appIsQuiet: Bool { prefs.quietInBackground && !NSApp.isActive }

    private func uiBuffer(for cue: SoundCue) -> AVAudioPCMBuffer? {
        if builtUIPack != prefs.uiPack { uiBuffers.removeAll(); builtUIPack = prefs.uiPack }
        if let list = uiBuffers[cue] { return list.randomElement() }
        let list = (0..<4).map { Synth.render(cue, pack: prefs.uiPack, variant: $0) }
        uiBuffers[cue] = list
        return list.randomElement()
    }

    func play(_ cue: SoundCue) {
        let p = prefs
        guard p.masterEnabled, p.uiEnabled, !appIsQuiet else { return }
        ensureRunning()
        applyAmbientTargetsIfNeeded()
        guard let buf = uiBuffer(for: cue) else { return }
        uiMixer.outputVolume = Float(p.uiVolume)
        engine.mainMixerNode.outputVolume = Float(p.masterVolume)
        let player = uiPlayers[uiIndex % uiPlayers.count]
        uiIndex += 1
        player.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    func type(_ kind: TypingKind) {
        let p = prefs
        guard p.masterEnabled, p.typingEnabled, !appIsQuiet else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastTypeTime < 0.012 { return }
        lastTypeTime = now
        ensureRunning()
        if builtTypingPack != p.typingPack {
            typingBuffers.removeAll()
            builtTypingPack = p.typingPack
        }
        if typingBuffers.isEmpty {
            for k in TypingKind.allCases {
                typingBuffers[k] = (0..<6).map { Synth.renderKey(p.typingPack, kind: k, variant: $0) }
            }
        }
        guard let buf = typingBuffers[kind]?.randomElement() else { return }
        typingMixer.outputVolume = Float(p.typingVolume)
        engine.mainMixerNode.outputVolume = Float(p.masterVolume)
        let player = typingPlayers[typingIndex % typingPlayers.count]
        typingIndex += 1
        player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func applyAmbientTargetsIfNeeded() {
        if ambient == nil || shouldRun { applyAmbientTargets() }
    }

    /// Used by the Sound settings to hear a pack without waiting for real typing.
    func previewTyping() {
        for (i, k) in [TypingKind.key, .key, .space, .key, .key, .back, .key, .enter].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.14) { SoundEngine.shared.type(k) }
        }
    }
}
