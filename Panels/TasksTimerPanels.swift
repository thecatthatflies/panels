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

    var phase: Phase = .focus
    var remaining: Int
    var running = false
    var sessions = 0
    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored weak var panel: Panel?

    init(panel: Panel) {
        self.panel = panel
        remaining = panel.settings.focusMinutes * 60
    }

    deinit { ticker?.invalidate() }

    var total: Int {
        guard let s = panel?.settings else { return 1500 }
        return (phase == .focus ? s.focusMinutes : s.breakMinutes) * 60
    }

    var progress: Double { total == 0 ? 0 : 1 - Double(remaining) / Double(total) }

    func syncDurations() {
        if !running && (remaining == total || remaining > total) { remaining = total }
    }

    func toggle() { running ? pause() : start() }

    func start() {
        guard !running else { return }
        running = true
        endDate = Date().addingTimeInterval(TimeInterval(remaining))
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    func pause() {
        running = false
        ticker?.invalidate()
        ticker = nil
        endDate = nil
    }

    func reset() {
        pause()
        remaining = total
    }

    func skip() {
        pause()
        switchPhase()
    }

    private func tick() {
        guard let end = endDate else { return }
        let left = Int(ceil(end.timeIntervalSinceNow))
        if left <= 0 {
            NSSound(named: "Glass")?.play()
            if phase == .focus { sessions += 1 }
            switchPhase()
            start()
        } else if left != remaining {
            remaining = left
        }
    }

    private func switchPhase() {
        phase = phase == .focus ? .rest : .focus
        remaining = total
    }
}

struct TimerPanelView: View {
    @Bindable var panel: Panel
    @Environment(\.theme) private var theme

    private var accent: Color { theme.accent(panel.settings.accent) }

    var body: some View {
        let model = Runtime.shared.timer(for: panel)
        GeometryReader { geo in
            let side = min(geo.size.width - 40, geo.size.height - 120)
            VStack(spacing: 18) {
                ZStack {
                    Circle().strokeBorder(theme.hairlineStrong, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: max(model.progress, 0.0001))
                        .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2.5)
                        .animation(.linear(duration: 0.3), value: model.progress)
                    VStack(spacing: 4) {
                        Text(format(model.remaining))
                            .font(Typo.ui(max(min(side * 0.24, 56), 24), bold: true))
                            .monospacedDigit()
                            .foregroundStyle(theme.textC)
                            .contentTransition(.numericText())
                        Text(model.phase == .focus ? "Focus" : "Break")
                            .font(Typo.ui(12.5, bold: true))
                            .foregroundStyle(model.phase == .focus ? accent : theme.mutedC)
                    }
                }
                .frame(width: max(side, 80), height: max(side, 80))

                HStack(spacing: 10) {
                    IconButton(symbol: "arrow.counterclockwise", help: "Reset", size: 13, box: 34) { model.reset() }
                    Button { model.toggle() } label: {
                        Image(systemName: model.running ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.isDark ? Color.black.opacity(0.85) : Color.white)
                            .frame(width: 52, height: 40)
                            .background(Capsule().fill(accent))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    IconButton(symbol: "forward.end", help: "Skip", size: 13, box: 34) { model.skip() }
                }

                HStack(spacing: 6) {
                    ForEach(0..<max(model.sessions, 0), id: \.self) { _ in
                        Capsule().fill(accent).frame(width: 14, height: 4)
                    }
                    if model.sessions == 0 {
                        Text("No sessions yet").font(Typo.ui(11.5)).foregroundStyle(theme.faintC)
                    }
                }
                .frame(height: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: panel.settings.focusMinutes) { _, _ in model.syncDurations() }
        .onChange(of: panel.settings.breakMinutes) { _, _ in model.syncDurations() }
    }

    private func format(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }
}
