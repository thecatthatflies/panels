import SwiftUI
import AppKit

// MARK: - Panel container

struct PanelView: View {
    @Bindable var panel: Panel
    @Environment(\.theme) private var theme
    private let ws = Workspace.shared
    private let appearance = Appearance.shared

    @State private var hovering = false
    @State private var showSettings = false
    @State private var renaming = false
    @State private var zone: DropZone?
    @State private var appeared = false
    @State private var settingsPulse = 0
    @FocusState private var titleFocused: Bool

    private var isFocused: Bool { ws.space.focusedID == panel.id }
    private var accent: Color { theme.accent(panel.settings.accent) }
    private var locked: Bool { ws.focusMode }
    private var radius: CGFloat { CGFloat(appearance.cornerRadius) + (locked ? 6 : 0) }
    private var order: Int { ws.space.panels.firstIndex { $0.id == panel.id } ?? 0 }
    private var isZoomed: Bool { ws.space.zoomedID == panel.id }
    private var showActions: Bool { !locked && (hovering || showSettings || isFocused) }
    private var surfaceColor: Color { panel.kind == .terminal ? Color(hex: theme.termBackground) : theme.surfaceC }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { surfaceBackground(shape) }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(locked ? Color.clear : (isFocused ? accent.opacity(0.65) : theme.hairline), lineWidth: 1)
        }
        .overlay { dragLayer(shape) }
        .shadow(color: locked ? .clear : theme.shadow.opacity(isFocused ? 0.9 : 0.5),
                radius: isFocused ? 14 : 8, y: isFocused ? 6 : 3)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ws.frames[panel.id] = $0 }
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.22), value: isFocused)
        .scaleEffect(appeared ? 1 : 0.965)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.84).delay(Double(order) * 0.05)) { appeared = true }
        }
        .onChange(of: ws.settingsRequest) { _, id in
            if id == panel.id { showSettings = true; ws.settingsRequest = nil }
        }
        .onChange(of: ws.renameRequest) { _, id in
            if id == panel.id {
                renaming = true
                ws.renameRequest = nil
                DispatchQueue.main.async { titleFocused = true }
            }
        }
        .environment(\.theme, theme)
    }

    // MARK: surface

    @ViewBuilder
    private func surfaceBackground(_ shape: RoundedRectangle) -> some View {
        switch panel.settings.surface {
        case .solid:
            shape.fill(surfaceColor)
        case .glass:
            ZStack {
                VisualEffectView(material: theme.isDark ? .hudWindow : .popover, blending: .behindWindow)
                shape.fill(surfaceColor.opacity(0.42))
            }
            .clipShape(shape)
        case .clear:
            shape.fill(surfaceColor.opacity(0.18))
        }
    }

    // MARK: drag and drop layer

    @ViewBuilder
    private func dragLayer(_ shape: RoundedRectangle) -> some View {
        if let dragging = ws.draggingID {
            ZStack {
                shape.fill(theme.surfaceC)
                VStack(spacing: 8) {
                    Image(systemName: panel.kind.symbol)
                        .font(.system(size: 22, weight: .light))
                    Text(panel.title).font(Typo.ui(13, bold: true))
                }
                .foregroundStyle(theme.faintC)
                .opacity(dragging == panel.id ? 0.45 : 1)

                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onDrop(of: [.plainText], delegate: PanelDropDelegate(panelID: panel.id, zone: $zone, size: geo.size))
                }

                if let z = zone {
                    DropZoneOverlay(zone: z, accent: accent, radius: radius)
                }
            }
            .clipShape(shape)
            .transition(.opacity)
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: panel.kind.symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 16)

            if renaming {
                TextField("Title", text: $panel.title)
                    .textFieldStyle(.plain)
                    .font(Typo.ui(12.5, bold: true))
                    .foregroundStyle(theme.textC)
                    .focused($titleFocused)
                    .onSubmit {
                        renaming = false
                        if panel.kind == .note { panel.settings.autoTitle = false }
                    }
                    .onExitCommand { renaming = false }
                    .frame(maxWidth: 220)
            } else {
                Text(panel.title.isEmpty ? panel.kind.defaultTitle : panel.title)
                    .font(Typo.ui(12.5, bold: true))
                    .foregroundStyle(isFocused ? theme.textC : theme.mutedC)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            if panel.kind == .note && !locked && (showActions || isFocused) {
                OutlineMenu(panel: panel)
                    .transition(.opacity)
                NoteModePicker(panel: panel, accent: accent)
                    .transition(.opacity)
            }

            HStack(spacing: 1) {
                IconMenu(symbol: "rectangle.split.2x1", help: "Split right (Cmd D)") {
                    splitMenu(axis: .horizontal)
                }
                IconMenu(symbol: "rectangle.split.1x2", help: "Split down (Cmd Shift D)") {
                    splitMenu(axis: .vertical)
                }
                IconButton(symbol: "slider.horizontal.3", help: "Panel settings (Cmd Option I)", active: showSettings, tint: accent) {
                    settingsPulse += 1
                    showSettings.toggle()
                }
                .symbolEffect(.bounce, value: settingsPulse)
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    PanelSettingsView(panel: panel)
                        .environment(\.theme, theme)
                }
                IconButton(symbol: isZoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           help: "Zoom panel (Cmd Shift Return)") {
                    ws.toggleZoom(panel.id)
                }
                IconButton(symbol: "xmark", help: "Close panel (Cmd W)") {
                    ws.close(panel.id)
                }
            }
            .opacity(showActions ? 1 : 0)
            .offset(x: showActions ? 0 : 8)
            .blur(radius: showActions ? 0 : 2)
            .animation(.snappy(duration: 0.22), value: showActions)
        }
        .padding(.horizontal, 12)
        .frame(height: locked ? 30 : 38)
        .opacity(locked ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            renaming = true
            DispatchQueue.main.async { titleFocused = true }
        }
        .onTapGesture { ws.focus(panel.id) }
        .onDrag {
            PanelDrag.begin(panel.id)
            return NSItemProvider(object: panel.id.uuidString as NSString)
        } preview: {
            HStack(spacing: 8) {
                Image(systemName: panel.kind.symbol).foregroundStyle(accent)
                Text(panel.title).font(Typo.ui(13, bold: true)).foregroundStyle(theme.textC)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(theme.raisedC))
            .overlay(Capsule().strokeBorder(accent.opacity(0.7), lineWidth: 1))
        }
        .contextMenu {
            Button("Rename") { renaming = true; DispatchQueue.main.async { titleFocused = true } }
            Button("Duplicate") { ws.duplicate(panel.id) }
            Button(isZoomed ? "Restore" : "Zoom") { ws.toggleZoom(panel.id) }
            if ws.spaces.count > 1 {
                Menu("Move to Workspace") {
                    ForEach(ws.spaces.filter { $0.id != ws.activeSpaceID }) { sp in
                        Button { ws.move(panel: panel.id, toSpace: sp.id) } label: { Label(sp.name, systemImage: sp.symbol) }
                    }
                }
            }
            if panel.kind == .note { Button("Save as Markdown...") { FileOps.saveMarkdown(panel) } }
            Divider()
            Button("Close", role: .destructive) { ws.close(panel.id) }
        }
    }

    @ViewBuilder
    private func splitMenu(axis: SplitAxis) -> some View {
        ForEach(PanelKind.allCases) { kind in
            Button {
                ws.split(panel.id, axis: axis, kind: kind)
            } label: {
                Label(kind.label, systemImage: kind.symbol)
            }
        }
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        switch panel.kind {
        case .note: NotePanelView(panel: panel)
        case .terminal: TerminalPanelView(panel: panel)
        case .web: WebPanelView(panel: panel)
        case .tasks: TasksPanelView(panel: panel)
        case .timer: TimerPanelView(panel: panel)
        }
    }
}

// MARK: - Note mode picker

struct NoteModePicker: View {
    @Bindable var panel: Panel
    let accent: Color
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NoteMode.allCases) { mode in
                let on = panel.settings.noteMode == mode
                Button {
                    withAnimation(.snappy(duration: 0.28)) { panel.settings.noteMode = mode }
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(on ? accent : theme.faintC)
                        .frame(width: 24, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(on ? accent.opacity(0.16) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .help(mode.label)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.hover))
    }
}

// MARK: - Settings popover

struct PanelSettingsView: View {
    @Bindable var panel: Panel
    @Environment(\.theme) private var theme
    private let ws = Workspace.shared

    private var accent: Color { theme.accent(panel.settings.accent) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 8) {
                    Image(systemName: panel.kind.symbol).foregroundStyle(accent)
                    Text("\(panel.kind.label) settings")
                        .font(Typo.ui(14, bold: true))
                        .foregroundStyle(theme.textC)
                }

                SettingsSection(title: "Look") {
                    SettingRow(label: "Accent") {
                        AccentSwatches(selection: $panel.settings.accent)
                    }
                    SettingRow(label: "Surface") {
                        SegmentedChips(options: SurfaceStyle.allCases, selection: $panel.settings.surface,
                                       label: { $0.label }, tint: accent)
                    }
                    SliderRow(label: "Inner padding", value: $panel.settings.padding, range: 0...56, tint: accent)
                }

                switch panel.kind {
                case .note: noteSettings
                case .terminal: terminalSettings
                case .web: webSettings
                case .tasks: tasksSettings
                case .timer: timerSettings
                }

                SettingsSection(title: "Panel") {
                    HStack(spacing: 8) {
                        actionChip("Apply look to all \(panel.kind.label.lowercased()) panels", symbol: "square.on.square") {
                            applyToSiblings()
                        }
                    }
                    HStack(spacing: 8) {
                        actionChip("Reset", symbol: "arrow.counterclockwise") {
                            let keepMode = panel.settings.noteMode
                            panel.settings = PanelSettings()
                            panel.settings.noteMode = keepMode
                        }
                        actionChip("Duplicate", symbol: "plus.square.on.square") { ws.duplicate(panel.id) }
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 320, height: 520)
        .background(theme.surfaceC)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    // MARK: per kind

    @ViewBuilder
    private var noteSettings: some View {
        SettingsSection(title: "Typography") {
            SettingRow(label: "Typeface") {
                Picker("", selection: $panel.settings.font) {
                    ForEach(EditorFont.allCases) { f in Text(f.label).tag(f) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            SliderRow(label: "Size", value: $panel.settings.fontSize, range: 11...30, step: 0.5,
                      format: { String(format: "%.1f", $0) }, tint: accent)
            SliderRow(label: "Line height", value: $panel.settings.lineHeight, range: 1.1...2.2, step: 0.05,
                      format: { String(format: "%.2f", $0) }, tint: accent)
            SettingRow(label: "Text width", value: panel.settings.measure == 0 ? "Full" : "\(Int(panel.settings.measure)) pt") {
                Slider(value: $panel.settings.measure, in: 0...1000, step: 20)
                    .controlSize(.small)
                    .tint(accent)
            }
        }
        SettingsSection(title: "Editor") {
            SettingRow(label: "View") {
                SegmentedChips(options: NoteMode.allCases, selection: $panel.settings.noteMode,
                               label: { $0.label }, tint: accent)
            }
            ToggleRow(label: "Style markdown as you type", isOn: $panel.settings.richStyling, tint: accent)
            ToggleRow(label: "Title from first heading", isOn: $panel.settings.autoTitle, tint: accent)
            ToggleRow(label: "Typewriter scrolling", isOn: $panel.settings.typewriter, tint: accent)
            ToggleRow(label: "Dim other paragraphs", isOn: $panel.settings.dimParagraphs, tint: accent)
            ToggleRow(label: "Wrap long lines", isOn: $panel.settings.wrap, tint: accent)
            ToggleRow(label: "Check spelling", isOn: $panel.settings.spellcheck, tint: accent)
            ToggleRow(label: "Show word count", isOn: $panel.settings.showStats, tint: accent)
        }
    }

    @ViewBuilder
    private var terminalSettings: some View {
        SettingsSection(title: "Terminal") {
            SliderRow(label: "Font size", value: $panel.settings.termFontSize, range: 9...24, step: 0.5,
                      format: { String(format: "%.1f", $0) }, tint: accent)
            SettingRow(label: "Cursor") {
                SegmentedChips(options: CursorStyle.allCases, selection: $panel.settings.cursor,
                               label: { $0.label }, tint: accent)
            }
            SliderRow(label: "Background opacity", value: $panel.settings.termOpacity, range: 0.3...1, step: 0.05,
                      format: { String(format: "%.0f%%", $0 * 100) }, tint: accent)
            SettingRow(label: "Shell", value: panel.settings.shell.isEmpty ? "Default" : nil) {
                TextField("/bin/zsh", text: $panel.settings.shell)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.textC)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.hover))
            }
            Text("Shell changes apply to the next session. Close and reopen the panel to restart.")
                .font(Typo.ui(11))
                .foregroundStyle(theme.faintC)
        }
    }

    @ViewBuilder
    private var webSettings: some View {
        SettingsSection(title: "Web") {
            SliderRow(label: "Page zoom", value: $panel.settings.zoom, range: 0.5...2.0, step: 0.05,
                      format: { String(format: "%.0f%%", $0 * 100) }, tint: accent)
            ToggleRow(label: "Show address bar", isOn: $panel.settings.showAddressBar, tint: accent)
            ToggleRow(label: "Request mobile sites", isOn: $panel.settings.mobileUA, tint: accent)
        }
        SettingsSection(title: "Web apps") {
            ForEach(WebPreset.all) { preset in
                Button {
                    panel.url = preset.url
                    panel.title = preset.name
                    Runtime.shared.web(for: panel).load(preset.url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: preset.symbol).frame(width: 18).foregroundStyle(accent)
                        Text(preset.name).font(Typo.ui(12.5)).foregroundStyle(theme.textC)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var tasksSettings: some View {
        SettingsSection(title: "Tasks") {
            actionChip("Clear completed", symbol: "checkmark.circle") {
                panel.tasks.removeAll { $0.done }
            }
        }
    }

    @ViewBuilder
    private var timerSettings: some View {
        SettingsSection(title: "Timer") {
            SliderRow(label: "Focus", value: Binding(get: { Double(panel.settings.focusMinutes) },
                                                     set: { panel.settings.focusMinutes = Int($0) }),
                      range: 5...90, step: 5, format: { "\(Int($0)) min" }, tint: accent)
            SliderRow(label: "Break", value: Binding(get: { Double(panel.settings.breakMinutes) },
                                                     set: { panel.settings.breakMinutes = Int($0) }),
                      range: 1...30, step: 1, format: { "\(Int($0)) min" }, tint: accent)
        }
    }

    // MARK: helpers

    private func actionChip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                Text(title).font(Typo.ui(12))
            }
            .foregroundStyle(theme.textC)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(theme.hover))
            .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }

    private func applyToSiblings() {
        var shared = panel.settings
        for p in ws.space.panels where p.kind == panel.kind && p.id != panel.id {
            var s = p.settings
            s.accent = shared.accent
            s.surface = shared.surface
            s.padding = shared.padding
            s.font = shared.font
            s.fontSize = shared.fontSize
            s.lineHeight = shared.lineHeight
            s.measure = shared.measure
            s.wrap = shared.wrap
            s.richStyling = shared.richStyling
            s.termFontSize = shared.termFontSize
            s.cursor = shared.cursor
            s.termOpacity = shared.termOpacity
            p.settings = s
        }
        shared = panel.settings
        ws.showToast("Applied to matching panels")
    }
}


// MARK: - Outline menu

struct OutlineMenu: View {
    @Bindable var panel: Panel

    var body: some View {
        let items = Outline.items(in: panel.text)
        if !items.isEmpty {
            IconMenu(symbol: "list.bullet.indent", help: "Outline") {
                ForEach(items.prefix(60)) { item in
                    Button {
                        Runtime.shared.noteHost(for: panel).jump(to: item.location)
                    } label: {
                        Text(String(repeating: "\u{2003}", count: max(item.level - 1, 0)) + item.title)
                    }
                }
            }
        }
    }
}
