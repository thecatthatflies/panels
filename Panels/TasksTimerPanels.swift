import SwiftUI
import AppKit
import Observation

// MARK: - Tasks

struct TasksPanelView: View {
    @Bindable var panel: Panel
    @Environment(\.theme) private var theme
    @Environment(\.panelSize) private var size
    @State private var draft = ""
    @State private var addRevealed = false
    @FocusState private var addFocused: Bool

    /// Small panels keep the list on screen and show the add field only on demand.
    private var addVisible: Bool { size >= .regular || addRevealed || panel.tasks.isEmpty && size >= .small }

    private var accent: Color { theme.accent(panel.settings.accent) }
    private var doneCount: Int { panel.tasks.filter { $0.done }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if addVisible {
                addField
                    .padding(.horizontal, size >= .regular ? CGFloat(panel.settings.padding) : 8)
                    .padding(.top, 2)
                    .padding(.bottom, size >= .regular ? 10 : 4)
            } else if size == .small {
                Button { addRevealed = true; addFocused = true } label: {
                    Label("Add a task", systemImage: "plus")
                        .font(Typo.ui(11.5, bold: true))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }

            if panel.tasks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach($panel.tasks) { $task in
                        // Capture the id now: reading `task` inside removeAll would touch panel.tasks mid-mutation and trap.
                        let id = task.id
                        TaskRow(task: $task, accent: accent) {
                            withAnimation(.snappy(duration: 0.25)) { panel.removeTask(id) }
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

                if size >= .regular { footer }
            }
        }
        .onChange(of: addFocused) { _, f in if !f && draft.isEmpty { addRevealed = false } }
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
            Text(size >= .regular ? "Type above and press Return." : "Add your first one.")
                .font(Typo.ui(12))
                .foregroundStyle(theme.faintC)
            if size < .regular {
                Button { addRevealed = true; addFocused = true } label: {
                    Label("Add a task", systemImage: "plus")
                        .font(Typo.ui(11.5, bold: true)).foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
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
    var bonus = 0                       // seconds added with +1 / +5 while running
    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored weak var panel: Panel?

    init(panel: Panel) {
        self.panel = panel
        remaining = panel.settings.focusMinutes * 60
    }

    deinit { ticker?.invalidate() }

    /// Test hook: PANELS_TIMER_SPEED=30 makes the clock run 30x faster. Defaults to real time.
    private static let speed: Double = Double(ProcessInfo.processInfo.environment["PANELS_TIMER_SPEED"] ?? "") ?? 1

    var settings: PanelSettings { panel?.settings ?? PanelSettings() }
    var endsAt: Date? { endDate }

    var isLongBreak: Bool {
        phase == .rest && sessions > 0 && sessions % max(settings.sessionsBeforeLong, 1) == 0
    }

    var baseSeconds: Int {
        switch phase {
        case .focus: return settings.focusMinutes * 60
        case .rest: return (isLongBreak ? settings.longBreakMinutes : settings.breakMinutes) * 60
        }
    }

    var total: Int { baseSeconds + bonus }

    /// Minutes currently chosen for this phase (what the dial and presets edit).
    var chosenMinutes: Int { baseSeconds / 60 }

    var progress: Double { total == 0 ? 0 : 1 - Double(remaining) / Double(total) }

    var display: Display {
        if finished { return .done }
        switch phase {
        case .focus: return running ? .running : (remaining >= total ? .idle : .paused)
        case .rest: return running ? .resting : (remaining >= total ? .restReady : .paused)
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
        startedAt = Date()
        endDate = Date().addingTimeInterval(TimeInterval(remaining) / Self.speed)
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

    func selectPhase(_ p: Phase) {
        guard !running, remaining >= total, phase != p else { return }
        phase = p
        bonus = 0
        remaining = total
        touch(.adjust)
        Sound.play(.tick)
    }

    func extend(minutes: Int) {
        guard display == .running || display == .resting || display == .paused else { return }
        bonus += minutes * 60
        remaining += minutes * 60
        if running, let end = endDate { endDate = end.addingTimeInterval(TimeInterval(minutes * 60) / Self.speed) }
        touch(.adjust)
        Sound.play(.tick)
    }

    func reset() {
        let was = running
        if was { running = false; ticker?.invalidate(); ticker = nil; endDate = nil }
        finished = false
        bonus = 0
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
        case .rest:
            if isLongBreak { panel.settings.longBreakMinutes = min(max(panel.settings.longBreakMinutes + minutes, 1), 90) }
            else { panel.settings.breakMinutes = min(max(panel.settings.breakMinutes + minutes, 1), 60) }
        }
        remaining = total
        touch(.adjust)
        Sound.play(.tick)
    }

    func set(minutes: Int) {
        guard !running, remaining >= total, let panel else { return }
        switch phase {
        case .focus: panel.settings.focusMinutes = min(max(minutes, 1), 180)
        case .rest:
            if isLongBreak { panel.settings.longBreakMinutes = minutes } else { panel.settings.breakMinutes = minutes }
        }
        remaining = total
        touch(.adjust)
        Sound.play(.tick)
    }

    private func tick() {
        guard let end = endDate else { return }
        let left = Int(ceil(end.timeIntervalSinceNow * Self.speed))
        if left <= 0 { complete() }
        else if left != remaining { remaining = left }
    }

    private func complete() {
        // The end chime only follows a session that really ran in this launch; never a stale or instant finish.
        let ranFor = Date().timeIntervalSince(startedAt ?? Date()) * Self.speed
        let genuine = startedAt != nil && ranFor >= 1
        running = false
        ticker?.invalidate(); ticker = nil; endDate = nil
        remaining = 0
        if genuine {
            if SoundSettings.shared.prefs.masterEnabled { Sound.play(.timerEnd) }
            else if settings.timerSound, !TestMode.active { NSSound(named: "Glass")?.play() }
        }
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
        bonus = 0
        remaining = total
    }

    func clock(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}

// MARK: - Timer view

/// Adapts to the room it has: a single row when tiny, ring beside controls when wide, stacked when tall.
struct TimerPanelView: View {
    @Bindable var panel: Panel
    @Environment(\.theme) private var theme

    private var focusTint: Color { theme.accent(panel.settings.accent) }
    private var restTint: Color { Color(hex: AccentID.granite.hex ?? 0x6FA39F) }

    private enum Mode { case compact, wide, tall }

    var body: some View {
        let model = Runtime.shared.timer(for: panel)
        let display = model.display
        let tint = model.phase == .rest ? restTint : focusTint

        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let wideNeeds: CGFloat = 120 + 30 + 300
            let mode: Mode = (h < 340 || w < 260) ? .compact : ((w / h > 1.45 && h < 460 && w >= wideNeeds) ? .wide : .tall)

            Group {
                switch mode {
                case .compact:
                    compact(model, display, tint, width: w)
                case .wide:
                    let ring = max(min(h - 44, w * 0.42, 300), 120)
                    HStack(spacing: 30) {
                        TimerRing(panel: panel, model: model, display: display, tint: tint, size: ring)
                        VStack(alignment: .leading, spacing: 14) {
                            phaseTabs(model, display, tint)
                            pickerOrExtend(model, display, tint)
                            actions(model, display, tint, fill: false)
                            if h > 300 { sessionDots(model, tint) }
                        }
                        .frame(maxWidth: 320)
                    }
                    .padding(.horizontal, 26)
                case .tall:
                    let reserved: CGFloat = 40 + 38 + 52 + (h > 430 ? 22 : 0) + 18 * 4 + 40
                    let ring = max(min(w - 64, h - reserved, 300), 120)
                    VStack(spacing: 18) {
                        phaseTabs(model, display, tint)
                        TimerRing(panel: panel, model: model, display: display, tint: tint, size: ring)
                        pickerOrExtend(model, display, tint)
                        actions(model, display, tint, fill: true)
                        if h > 430 { sessionDots(model, tint) }
                    }
                    .padding(.horizontal, 22)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(Motion.layout, value: display)
        .onChange(of: panel.settings.focusMinutes) { _, _ in model.syncDurations() }
        .onChange(of: panel.settings.breakMinutes) { _, _ in model.syncDurations() }
        .onChange(of: panel.settings.longBreakMinutes) { _, _ in model.syncDurations() }
    }

    // MARK: compact row

    private func compact(_ model: TimerModel, _ display: TimerModel.Display, _ tint: Color, width: CGFloat) -> some View {
        let running = display == .running || display == .resting
        let showTime = model.clock(model.remaining)
        let fraction = display == .idle || display == .restReady ? 0 : model.progress
        return VStack(spacing: 10) {
            HStack(spacing: width < 150 ? 4 : 14) {
                Text(showTime)
                    .font(.system(size: min(max(width * 0.16, 24), 46), weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.textC)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                if display != .idle && display != .restReady && width >= 150 {
                    IconButton(symbol: "xmark", help: "Cancel", size: 11, box: 28) { model.reset() }
                }
                Button { model.toggle() } label: {
                    Image(systemName: running ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.isDark ? Color.black.opacity(0.85) : Color.white)
                        .frame(width: width < 150 ? 30 : 40, height: width < 150 ? 30 : 40)
                        .background(Circle().fill(tint))
                        .contentShape(Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressStyle())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairlineStrong.opacity(0.7))
                    Capsule().fill(tint).frame(width: g.size.width * (1 - fraction))
                        .animation(.linear(duration: 0.3), value: fraction)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 20)
    }

    // MARK: pieces

    @ViewBuilder
    private func phaseTabs(_ model: TimerModel, _ display: TimerModel.Display, _ tint: Color) -> some View {
        let canPick = display == .idle || display == .restReady
        HStack(spacing: 4) {
            ForEach([TimerModel.Phase.focus, .rest], id: \.self) { p in
                let on = model.phase == p
                let minutes = p == .focus ? panel.settings.focusMinutes : panel.settings.breakMinutes
                Button { model.selectPhase(p) } label: {
                    HStack(spacing: 6) {
                        Text(p == .focus ? "Focus" : "Break").font(.system(size: 12.5, weight: on ? .semibold : .regular))
                        Text("\(minutes)m").font(.system(size: 11.5, design: .rounded)).monospacedDigit()
                            .foregroundStyle(on ? tint : theme.faintC)
                    }
                    .foregroundStyle(on ? theme.textC : theme.mutedC)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(on ? tint.opacity(0.16) : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canPick)
                .opacity(canPick || on ? 1 : 0.35)
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.hover))
        .animation(Motion.quick, value: model.phase)
    }

    @ViewBuilder
    private func pickerOrExtend(_ model: TimerModel, _ display: TimerModel.Display, _ tint: Color) -> some View {
        switch display {
        case .idle, .restReady:
            let options = model.phase == .focus ? [5, 10, 15, 25, 45, 60, 90] : [3, 5, 10, 15, 20]
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    IconButton(symbol: "minus", help: "One minute less", size: 11, box: 28) { model.adjust(by: -1) }
                    ForEach(options, id: \.self) { m in
                        let on = model.chosenMinutes == m
                        Button { model.set(minutes: m) } label: {
                            Text("\(m)")
                                .font(.system(size: 12.5, weight: on ? .semibold : .regular, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(on ? tint : theme.mutedC)
                                .frame(minWidth: 26, minHeight: 28)
                                .padding(.horizontal, 2)
                                .background(Capsule().fill(on ? tint.opacity(0.18) : theme.hover))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                    IconButton(symbol: "plus", help: "One minute more", size: 11, box: 28) { model.adjust(by: 1) }
                }
                Text("Drag the ring, scroll over it, or tap the number to type")
                    .font(.system(size: 11)).foregroundStyle(theme.faintC)
            }
            .transition(.opacity)
        default:
            HStack(spacing: 6) {
                extendChip("+1 min", 1, model)
                extendChip("+5 min", 5, model)
                extendChip("+10 min", 10, model)
            }
            .transition(.opacity)
        }
    }

    private func extendChip(_ label: String, _ minutes: Int, _ model: TimerModel) -> some View {
        Button { model.extend(minutes: minutes) } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(theme.mutedC)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(theme.hover))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private func actions(_ model: TimerModel, _ display: TimerModel.Display, _ tint: Color, fill: Bool) -> some View {
        let running = display == .running || display == .resting
        let label = running ? "Pause" : (display == .paused ? "Resume" : "Start")
        let symbol = running ? "pause.fill" : "play.fill"
        let canCancel = display != .idle && display != .restReady

        return HStack(spacing: 10) {
            Button { model.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(label).font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(theme.isDark ? Color.black.opacity(0.85) : Color.white)
                .frame(maxWidth: fill ? .infinity : 150)
                .frame(height: 40)
                .background(Capsule().fill(tint))
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(display == .done)

            if canCancel {
                Button { model.reset() } label: {
                    Text("Cancel")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(theme.mutedC)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(Capsule().fill(theme.hover))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .frame(maxWidth: fill ? 360 : .infinity, alignment: .leading)
        .animation(Motion.quick, value: canCancel)
    }

    private func sessionDots(_ model: TimerModel, _ tint: Color) -> some View {
        let n = max(panel.settings.sessionsBeforeLong, 1)
        let done = model.sessions % n
        let cycle = model.sessions > 0 && done == 0
        return HStack(spacing: 6) {
            ForEach(0..<n, id: \.self) { i in
                Circle().fill((cycle || i < done) ? tint : theme.hairlineStrong).frame(width: 6, height: 6)
            }
            if model.sessions > 0 {
                Text("\(model.sessions) done").font(.system(size: 11)).foregroundStyle(theme.faintC).padding(.leading, 4)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.sessions)
        .frame(height: 10)
    }
}

// MARK: - Ring with a draggable dial

struct TimerRing: View {
    @Bindable var panel: Panel
    let model: TimerModel
    let display: TimerModel.Display
    let tint: Color
    let size: CGFloat
    @Environment(\.theme) private var theme

    @State private var editing = false
    @State private var draft = ""
    @State private var hovering = false
    @State private var scrollBox = ScrollBox()
    @FocusState private var fieldFocused: Bool

    private var lineWidth: CGFloat { max(size * 0.04, 6) }
    private var radius: CGFloat { (size - lineWidth) / 2 }
    private var isPicking: Bool { display == .idle || display == .restReady }

    var body: some View {
        let minutes = model.chosenMinutes
        let dial = min(Double(minutes), 60) / 60
        let remainingFraction = display == .done ? 1 : max(1 - model.progress, 0.002)
        let arc = isPicking ? dial : remainingFraction

        ZStack {
            Circle().stroke(theme.hairlineStrong.opacity(0.55), lineWidth: lineWidth).padding(lineWidth / 2)

            Circle()
                .trim(from: 0, to: arc)
                .stroke(AngularGradient(colors: [tint.opacity(0.55), tint], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(arc, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .padding(lineWidth / 2)
                .rotationEffect(.degrees(-90))
                .animation(isPicking ? .snappy(duration: 0.18) : .linear(duration: 0.3), value: arc)

            if isPicking {
                // the dial knob
                Circle()
                    .fill(Color.white)
                    .frame(width: lineWidth * 2.1, height: lineWidth * 2.1)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .offset(x: radius * sin(arc * 2 * .pi), y: -radius * cos(arc * 2 * .pi))
                    .animation(.snappy(duration: 0.18), value: arc)
            }

            center(minutes: minutes)
                .padding(.horizontal, lineWidth * 2)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(isPicking ? dialGesture : nil)
        .onHover { hovering = $0 }
        .onAppear { installScroll() }
        .onDisappear { scrollBox.remove() }
        .scaleEffect(display == .done ? 1.03 : 1)
        .animation(Motion.layout, value: display)
    }

    // MARK: centre

    @ViewBuilder
    private func center(minutes: Int) -> some View {
        VStack(spacing: size * 0.02) {
            if isPicking {
                if editing {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: size * 0.26, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.textC)
                        .focused($fieldFocused)
                        .onSubmit { commit() }
                        .onExitCommand { editing = false }
                        .frame(maxWidth: size * 0.6)
                } else {
                    Text("\(minutes)")
                        .font(.system(size: size * 0.26, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.textC)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.16), value: minutes)
                        .onTapGesture {
                            draft = "\(minutes)"
                            editing = true
                            DispatchQueue.main.async { fieldFocused = true }
                        }
                }
                Text(minutes == 1 ? "minute" : "minutes")
                    .font(.system(size: max(size * 0.058, 11.5), weight: .medium))
                    .foregroundStyle(tint)
            } else {
                Text(model.clock(display == .done ? 0 : model.remaining))
                    .font(.system(size: size * 0.22, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.textC)
                    .contentTransition(.numericText(countsDown: true))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                subtitle
            }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        let font = Font.system(size: max(size * 0.056, 11.5), weight: .medium)
        switch display {
        case .running, .resting:
            if let end = model.endsAt {
                HStack(spacing: 5) {
                    Image(systemName: "bell.fill").font(.system(size: max(size * 0.044, 9)))
                    Text(end.formatted(.dateTime.hour().minute()))
                }
                .font(font).foregroundStyle(theme.mutedC)
            }
        case .paused: Text("Paused").font(font).foregroundStyle(theme.mutedC)
        case .done: Text("Done").font(font).foregroundStyle(tint)
        default: EmptyView()
        }
    }

    private func commit() {
        editing = false
        let digits = draft.split(separator: ":").first.map(String.init) ?? draft
        if let m = Int(digits.trimmingCharacters(in: .whitespaces)), m > 0 { model.set(minutes: m) }
    }

    // MARK: dial

    private var dialGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let c = CGPoint(x: size / 2, y: size / 2)
                let startDistance = hypot(v.startLocation.x - c.x, v.startLocation.y - c.y)
                guard startDistance > radius - lineWidth * 3.2, startDistance < radius + lineWidth * 3 else { return }
                let dx = v.location.x - c.x, dy = v.location.y - c.y
                var angle = atan2(dx, -dy)                 // 0 at the top, clockwise
                if angle < 0 { angle += 2 * .pi }
                var m = Int((angle / (2 * .pi) * 60).rounded())
                let previous = model.chosenMinutes
                if m == 0 { m = previous > 30 ? 60 : 1 }
                if m % 5 != 0, abs(m - Int((Double(m) / 5).rounded()) * 5) <= 1 { m = Int((Double(m) / 5).rounded()) * 5 }
                m = min(max(m, 1), 60)
                if m != previous { model.set(minutes: m) }
            }
    }

    // MARK: scroll wheel

    final class ScrollBox {
        var monitor: Any?
        var accum: CGFloat = 0
        func remove() { if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }
    }

    private func installScroll() {
        scrollBox.remove()
        let box = scrollBox
        scrollBox.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [model] event in
            guard hovering, isPicking else { return event }
            box.accum += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 9 : event.scrollingDeltaY
            let steps = Int(box.accum)
            if steps != 0 {
                box.accum -= CGFloat(steps)
                model.adjust(by: steps * (event.modifierFlags.contains(.shift) ? 5 : 1))
            }
            return nil
        }
    }
}
