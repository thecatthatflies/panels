import SwiftUI
import AppKit
import Observation

// MARK: - Tasks

struct TasksPanelView: View {
    @Bindable var panel: Panel
    @Environment(\.theme) private var theme
    @State private var draft = ""
    @FocusState private var addFocused: Bool

    private var accent: Color { theme.accent(panel.settings.accent) }
    private var doneCount: Int { panel.tasks.filter { $0.done }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            addField
                .padding(.horizontal, CGFloat(panel.settings.padding))
                .padding(.top, 2)
                .padding(.bottom, 10)

            if panel.tasks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach($panel.tasks) { $task in
                        TaskRow(task: $task, accent: accent) {
                            withAnimation(.snappy(duration: 0.25)) { panel.tasks.removeAll { $0.id == task.id } }
                        }
                        .opacity(panel.settings.hideDone && task.done ? 0 : 1)
                        .frame(height: panel.settings.hideDone && task.done ? 0 : nil)
                        .clipped()
                        .listRowInsets(EdgeInsets(top: 1, leading: CGFloat(panel.settings.padding) - 8,
                                                  bottom: 1, trailing: CGFloat(panel.settings.padding) - 8))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { panel.tasks.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                footer
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(addFocused ? accent : theme.faintC)
            TextField("Add a task", text: $draft)
                .textFieldStyle(.plain)
                .font(Typo.ui(13.5))
                .foregroundStyle(theme.textC)
                .focused($addFocused)
                .onSubmit {
                    let t = draft.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    withAnimation(.snappy(duration: 0.28)) { panel.tasks.append(TaskItem(title: t)) }
                    Sound.play(.tick)
                    draft = ""
                    addFocused = true
                }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.hover))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(addFocused ? accent.opacity(0.7) : .clear, lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.faintC)
            Text("No tasks yet")
                .font(Typo.ui(13.5, bold: true))
                .foregroundStyle(theme.mutedC)
            Text("Type above and press Return.")
                .font(Typo.ui(12))
                .foregroundStyle(theme.faintC)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 30)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(doneCount) of \(panel.tasks.count) done")
                .font(Typo.ui(11))
                .foregroundStyle(theme.faintC)
            GeometryReader { geo in
                Capsule()
                    .fill(accent)
                    .frame(width: geo.size.width * CGFloat(doneCount) / CGFloat(max(panel.tasks.count, 1)), height: 2)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .animation(.snappy(duration: 0.3), value: doneCount)
            }
            .frame(height: 12)
        }
        .padding(.horizontal, CGFloat(panel.settings.padding))
        .frame(height: 28)
    }
}

struct TaskRow: View {
    @Binding var task: TaskItem
    let accent: Color
    let onDelete: () -> Void
    @Environment(\.theme) private var theme
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { task.done.toggle() }
                if task.done { Sound.play(.success) } else { Sound.play(.tick) }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(task.done ? accent : theme.faintC, lineWidth: 1.5)
                        .frame(width: 17, height: 17)
                    if task.done {
                        Circle().fill(accent).frame(width: 17, height: 17)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(theme.surfaceC)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(PressStyle())

            TextField("Task", text: $task.title)
                .textFieldStyle(.plain)
                .font(Typo.ui(13.5))
                .foregroundStyle(task.done ? theme.faintC : theme.textC)
                .strikethrough(task.done, color: theme.faintC)

            if hover {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.faintC)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? theme.hover : .clear))
        .onHover { h in withAnimation(.snappy(duration: 0.15)) { hover = h } }
    }
}

// MARK: - Timer

@Observable
final class TimerModel {
    enum Phase { case focus, rest }
    enum Interaction { case none, start, pause, reset, skip, adjust, finish }
    enum Display { case idle, running, paused, resting, restReady, done }

    var phase: Phase = .focus
    var remaining: Int
    var running = false
    var sessions = 0
    var finished = false
    var interaction: Interaction = .none
    var interactionTick = 0
    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored weak var panel: Panel?

    init(panel: Panel) {
        self.panel = panel
        remaining = panel.settings.focusMinutes * 60
    }

    deinit { ticker?.invalidate() }

    var settings: PanelSettings { panel?.settings ?? PanelSettings() }

    var isLongBreak: Bool {
        phase == .rest && sessions > 0 && sessions % max(settings.sessionsBeforeLong, 1) == 0
    }

    var total: Int {
        switch phase {
        case .focus: return settings.focusMinutes * 60
        case .rest: return (isLongBreak ? settings.longBreakMinutes : settings.breakMinutes) * 60
        }
    }

    var progress: Double { total == 0 ? 0 : 1 - Double(remaining) / Double(total) }

    var display: Display {
        if finished { return .done }
        switch phase {
        case .focus: return running ? .running : (remaining >= total ? .idle : .paused)
        case .rest: return running ? .resting : .restReady
        }
    }

    private func touch(_ i: Interaction) {
        interaction = i
        interactionTick += 1
    }

    func syncDurations() {
        if !running && remaining >= total { remaining = total }
        if !running && remaining > total { remaining = total }
    }

    func toggle() { running ? pause() : start() }

    func start() {
        guard !running else { return }
        finished = false
        running = true
        touch(.start)
        endDate = Date().addingTimeInterval(TimeInterval(remaining))
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    func pause() {
        guard running else { return }
        running = false
        touch(.pause)
        ticker?.invalidate()
        ticker = nil
        endDate = nil
    }

    func reset() {
        let was = running
        if was { running = false; ticker?.invalidate(); ticker = nil; endDate = nil }
        finished = false
        remaining = total
        touch(.reset)
    }

    func skip() {
        running = false
        ticker?.invalidate(); ticker = nil; endDate = nil
        finished = false
        touch(.skip)
        switchPhase()
    }

    func adjust(by minutes: Int) {
        guard !running, remaining >= total, let panel else { return }
        switch phase {
        case .focus: panel.settings.focusMinutes = min(max(panel.settings.focusMinutes + minutes, 1), 180)
        case .rest: panel.settings.breakMinutes = min(max(panel.settings.breakMinutes + minutes, 1), 60)
        }
        remaining = total
        touch(.adjust)
        Sound.play(.tick)
    }

    private func tick() {
        guard let end = endDate else { return }
        let left = Int(ceil(end.timeIntervalSinceNow))
        if left <= 0 { complete() }
        else if left != remaining { remaining = left }
    }

    private func complete() {
        running = false
        ticker?.invalidate(); ticker = nil; endDate = nil
        remaining = 0
        if SoundSettings.shared.prefs.masterEnabled { Sound.play(.timerEnd) }
        else if settings.timerSound { NSSound(named: "Glass")?.play() }
        let wasFocus = phase == .focus
        if wasFocus { sessions += 1 }
        finished = true
        touch(.finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, self.finished else { return }
            self.finished = false
            self.switchPhase()
            if wasFocus { self.start() }
        }
    }

    private func switchPhase() {
        phase = phase == .focus ? .rest : .focus
        remaining = total
    }

    func clock(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}

// MARK: - Timer view

struct TimerPanelView: View {
    @Bindable var panel: Panel
    @Environment(\.theme) private var theme
    @State private var dragAccum: CGFloat = 0
    @State private var hovering = false

    private var focusTint: Color { theme.accent(panel.settings.accent) }
    private var restTint: Color { Color(hex: AccentID.granite.hex ?? 0x6FA39F) }

    private struct Kick { var scale = 1.0; var rotation = 0.0; var shift = 0.0 }

    var body: some View {
        let model = Runtime.shared.timer(for: panel)
        let display = model.display
        let tint = (model.phase == .rest || display == .resting) ? restTint : focusTint

        GeometryReader { geo in
            let side = max(min(geo.size.width * 0.62, geo.size.height * 0.56, 270), 110)
            let spec = shapeSpec(display, side: side)

            VStack(spacing: 22) {
                ZStack {
                    // soft glow behind the shape
                    Circle()
                        .fill(RadialGradient(colors: [tint.opacity(display == .running || display == .resting ? 0.20 : 0.08), .clear],
                                             center: .center, startRadius: 4, endRadius: side * 0.95))
                        .frame(width: side * 2, height: side * 2)
                        .allowsHitTesting(false)

                    if display == .done { ripples(tint: tint, side: side) }

                    morphShape(model: model, display: display, tint: tint, spec: spec)
                        .keyframeAnimator(initialValue: Kick(), trigger: model.interactionTick) { view, v in
                            view.scaleEffect(v.scale).rotationEffect(.degrees(v.rotation)).offset(x: v.shift)
                        } keyframes: { _ in
                            KeyframeTrack(\.scale) {
                                switch model.interaction {
                                case .start: SpringKeyframe(0.9, duration: 0.12); SpringKeyframe(1.0, spring: .bouncy)
                                case .pause: SpringKeyframe(0.96, duration: 0.1); SpringKeyframe(1.0, spring: .smooth)
                                case .reset: SpringKeyframe(0.94, duration: 0.1); SpringKeyframe(1.0, spring: .bouncy)
                                case .finish: SpringKeyframe(1.08, duration: 0.2); SpringKeyframe(1.0, spring: .bouncy)
                                default: LinearKeyframe(1.0, duration: 0.01)
                                }
                            }
                            KeyframeTrack(\.rotation) {
                                if model.interaction == .reset { SpringKeyframe(-14, duration: 0.12); SpringKeyframe(0, spring: .bouncy) }
                                else if model.interaction == .skip { SpringKeyframe(10, duration: 0.1); SpringKeyframe(0, spring: .bouncy) }
                                else { LinearKeyframe(0, duration: 0.01) }
                            }
                            KeyframeTrack(\.shift) {
                                if model.interaction == .skip { SpringKeyframe(-12, duration: 0.1); SpringKeyframe(0, spring: .smooth) }
                                else { LinearKeyframe(0, duration: 0.01) }
                            }
                        }
                }
                .frame(height: side * 1.25)

                controls(model: model, display: display, tint: tint)

                sessionDots(model: model, tint: tint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: panel.settings.focusMinutes) { _, _ in model.syncDurations() }
        .onChange(of: panel.settings.breakMinutes) { _, _ in model.syncDurations() }
        .onChange(of: panel.settings.longBreakMinutes) { _, _ in model.syncDurations() }
    }

    // MARK: shape

    private struct ShapeSpec { var width: CGFloat; var height: CGFloat; var corner: CGFloat }

    private func shapeSpec(_ d: TimerModel.Display, side: CGFloat) -> ShapeSpec {
        switch d {
        case .idle: return ShapeSpec(width: side, height: side, corner: side * 0.30)
        case .running: return ShapeSpec(width: side, height: side, corner: side * 0.5)
        case .paused: return ShapeSpec(width: side * 1.28, height: side * 0.5, corner: side * 0.25)
        case .resting: return ShapeSpec(width: side * 0.94, height: side * 0.94, corner: side * 0.40)
        case .restReady: return ShapeSpec(width: side * 1.1, height: side * 0.66, corner: side * 0.33)
        case .done: return ShapeSpec(width: side * 1.06, height: side * 1.06, corner: side * 0.53)
        }
    }

    @ViewBuilder
    private func morphShape(model: TimerModel, display: TimerModel.Display, tint: Color, spec: ShapeSpec) -> some View {
        let outline = RoundedRectangle(cornerRadius: spec.corner, style: .continuous)
        let showProgress = display == .running || display == .paused || display == .resting

        ZStack {
            outline.fill(theme.raisedC)
            outline.fill(LinearGradient(colors: [tint.opacity(0.26), tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
            outline.strokeBorder(theme.hairlineStrong, lineWidth: 1)

            if showProgress {
                outline.inset(by: 6)
                    .stroke(theme.hairline, lineWidth: 4)
                outline.inset(by: 6)
                    .trim(from: 0, to: max(model.progress, 0.003))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .animation(.linear(duration: 0.3), value: model.progress)
            }

            content(model: model, display: display, tint: tint, side: spec.width)
        }
        .frame(width: spec.width, height: spec.height)
        .scaleEffect(display == .running || display == .resting ? breathing : 1)
        .shadow(color: theme.shadow.opacity(0.5), radius: 14, y: 6)
        .contentShape(outline)
        .onTapGesture { if display == .done { return }; model.toggle() }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { v in
                    guard display == .idle || display == .restReady else { return }
                    dragAccum = -v.translation.height
                    let steps = Int(dragAccum / 10)
                    if steps != 0 { model.adjust(by: steps); dragAccum = 0 }
                }
                .onEnded { _ in dragAccum = 0 }
        )
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.62, dampingFraction: 0.74), value: display)
        .help(display == .running || display == .resting ? "Pause" : "Start. Drag up or down to change the length")
    }

    private var breathing: CGFloat { 1 }

    @ViewBuilder
    private func content(model: TimerModel, display: TimerModel.Display, tint: Color, side: CGFloat) -> some View {
        switch display {
        case .idle:
            VStack(spacing: 2) {
                Text("\(panel.settings.focusMinutes)")
                    .font(Typo.ui(side * 0.30, bold: true))
                    .monospacedDigit()
                    .foregroundStyle(theme.textC)
                    .contentTransition(.numericText())
                Text("minutes").font(Typo.ui(12.5, bold: true)).foregroundStyle(tint)
                Text(hovering ? "drag to change" : " ").font(Typo.ui(10.5)).foregroundStyle(theme.faintC)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        case .running, .resting:
            VStack(spacing: 4) {
                Text(model.clock(model.remaining))
                    .font(Typo.ui(side * 0.21, bold: true))
                    .monospacedDigit()
                    .foregroundStyle(theme.textC)
                    .contentTransition(.numericText(countsDown: true))
                Text(display == .running ? "Focus" : (model.isLongBreak ? "Long break" : "Break"))
                    .font(Typo.ui(12.5, bold: true)).foregroundStyle(tint)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        case .paused:
            HStack(spacing: 12) {
                Image(systemName: "pause.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                Text(model.clock(model.remaining))
                    .font(Typo.ui(side * 0.16, bold: true))
                    .monospacedDigit()
                    .foregroundStyle(theme.textC)
                    .contentTransition(.numericText(countsDown: true))
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        case .restReady:
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.isLongBreak ? "Long break" : "Break").font(Typo.ui(14, bold: true)).foregroundStyle(theme.textC)
                    Text("\(model.total / 60) min").font(Typo.ui(11.5)).foregroundStyle(theme.mutedC)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        case .done:
            VStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: side * 0.22, weight: .bold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: model.interactionTick)
                Text("Done").font(Typo.ui(13, bold: true)).foregroundStyle(theme.textC)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    private func ripples(tint: Color, side: CGFloat) -> some View {
        PhaseAnimator([0.0, 1.0]) { phase in
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .strokeBorder(tint.opacity(0.5 - Double(i) * 0.14), lineWidth: 2)
                        .frame(width: side * (1.05 + CGFloat(i) * 0.22) * (0.9 + 0.35 * phase),
                               height: side * (1.05 + CGFloat(i) * 0.22) * (0.9 + 0.35 * phase))
                        .opacity(1 - phase * 0.85)
                }
            }
        } animation: { _ in .easeOut(duration: 1.3) }
        .allowsHitTesting(false)
    }

    // MARK: controls

    private func controls(model: TimerModel, display: TimerModel.Display, tint: Color) -> some View {
        HStack(spacing: 10) {
            IconButton(symbol: "arrow.counterclockwise", help: "Reset", size: 13, box: 34) { model.reset() }

            if display == .idle || display == .restReady {
                IconButton(symbol: "minus", help: "Shorter", size: 12, box: 30) { model.adjust(by: -5) }
            }

            Button { model.toggle() } label: {
                Image(systemName: (display == .running || display == .resting) ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.isDark ? Color.black.opacity(0.85) : Color.white)
                    .frame(width: 54, height: 40)
                    .background(Capsule().fill(tint))
                    .contentShape(Capsule())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressStyle())

            if display == .idle || display == .restReady {
                IconButton(symbol: "plus", help: "Longer", size: 12, box: 30) { model.adjust(by: 5) }
            }

            IconButton(symbol: "forward.end", help: "Skip", size: 13, box: 34) { model.skip() }
        }
        .animation(Motion.layout, value: display)
    }

    private func sessionDots(model: TimerModel, tint: Color) -> some View {
        let n = max(panel.settings.sessionsBeforeLong, 1)
        let done = model.sessions % n
        let cycleComplete = model.sessions > 0 && done == 0
        return HStack(spacing: 7) {
            ForEach(0..<n, id: \.self) { i in
                Capsule()
                    .fill((cycleComplete || i < done) ? tint : theme.hairlineStrong)
                    .frame(width: (cycleComplete || i < done) ? 18 : 8, height: 5)
            }
            if model.sessions > 0 {
                Text("\(model.sessions)").font(Typo.ui(11)).foregroundStyle(theme.faintC).padding(.leading, 4)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: model.sessions)
        .frame(height: 12)
    }
}
