import SwiftUI
import AppKit

// MARK: - Panel container

struct PanelView: View {
    @Bindable var panel: Panel
    @Environment(\.theme) private var theme
    @Environment(\.panelSize) private var size
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
    private var radius: CGFloat { locked ? 0 : CGFloat(appearance.cornerRadius) }
    private var order: Int { ws.space.panels.firstIndex { $0.id == panel.id } ?? 0 }
    private var isZoomed: Bool { ws.space.zoomedID == panel.id }
    private var showActions: Bool { !locked && (hovering || showSettings || isFocused) }
    private var surfaceColor: Color { panel.kind == .terminal ? Color(hex: theme.termBackground) : theme.surfaceC }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        VStack(spacing: 0) {
            if !locked { header }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) {
            if locked { WindowDragRegion().frame(height: 26) }
        }
        .background { surfaceBackground(shape) }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(locked ? Color.clear : (isFocused ? accent.opacity(0.65) : theme.hairline), lineWidth: 1)
        }
        .overlay { dragLayer(shape) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ws.frames[panel.id] = $0 }
        .onHover { hovering = $0 }
        .measuresPanelSize()
        .animation(Motion.quick, value: isFocused)
        .scaleEffect(appeared ? 1 : 0.985)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(Motion.appear) { appeared = true }
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
            shape.fill(surfaceColor.opacity(panel.kind == .terminal ? panel.settings.termOpacity : 1))
                .shadow(color: locked ? .clear : theme.shadow.opacity(isFocused ? 0.8 : 0.45),
                        radius: isFocused ? 12 : 7, y: isFocused ? 5 : 3)
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
        headerRow
            .frame(height: locked ? 30 : headerHeight)
            .opacity(locked ? 0.55 : 1)
            .contentShape(Rectangle())
            .onTapGesture { ws.focus(panel.id) }
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                renaming = true
                DispatchQueue.main.async { titleFocused = true }
            })
            .onDrag {
                PanelDrag.begin(panel.id)
                return NSItemProvider(object: panel.id.uuidString as NSString)
            } preview: { dragPreview }
            .contextMenu { panelMenuItems }
    }

    private var headerHeight: CGFloat { size == .tiny ? 20 : CGFloat(appearance.headerHeight) }

    @ViewBuilder
    private var headerRow: some View {
        if size == .tiny { tinyHeader }
        else if size == .small { smallHeader }
        else { fullHeader }
    }

    private var tinyHeader: some View {
        HStack(spacing: 0) {
            overflowMenu
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }

    private var smallHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: panel.kind.symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 16)
            Text(panel.title.isEmpty ? panel.kind.defaultTitle : panel.title)
                .font(Typo.ui(12, bold: true))
                .foregroundStyle(isFocused ? theme.textC : theme.mutedC)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 4)
            overflowMenu
        }
        .padding(.horizontal, 8)
    }

    /// One menu that holds every header action, for panels too small for the full button row.
    private var overflowMenu: some View {
        Menu {
            if panel.kind == .note || panel.kind == .terminal {
                Button("Dictate", systemImage: "mic") { DictationController.shared.toggle(for: panel) }
            }
            Menu("Split Right", systemImage: "rectangle.split.2x1") { splitMenu(axis: .horizontal) }
            Menu("Split Down", systemImage: "rectangle.split.1x2") { splitMenu(axis: .vertical) }
            Button("Panel Settings", systemImage: "slider.horizontal.3") { showSettings = true }
            Button(isZoomed ? "Restore" : "Zoom", systemImage: "arrow.up.left.and.arrow.down.right") { ws.toggleZoom(panel.id) }
            Button("Pop Out", systemImage: "arrow.up.forward.square") { ws.popOut(panel.id) }
            Divider()
            Button("Close", systemImage: "xmark", role: .destructive) { ws.close(panel.id) }
        } label: {
            Image(systemName: size == .tiny ? "circle.fill" : "ellipsis")
                .font(.system(size: size == .tiny ? 7 : 11, weight: .semibold))
                .foregroundStyle(size == .tiny ? accent : theme.mutedC)
                .frame(width: size == .tiny ? 14 : 22, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: size == .tiny ? 14 : 22, height: 20)
        .help("Panel actions")
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            PanelSettingsView(panel: panel).environment(\.theme, theme)
        }
    }

    private var dragPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: panel.kind.symbol).foregroundStyle(accent)
            Text(panel.title).font(Typo.ui(13, bold: true)).foregroundStyle(theme.textC)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(theme.raisedC))
        .overlay(Capsule().strokeBorder(accent.opacity(0.7), lineWidth: 1))
    }

    @ViewBuilder
    private var panelMenuItems: some View {
        Button("Rename") { renaming = true; DispatchQueue.main.async { titleFocused = true } }
        Button("Duplicate") { ws.duplicate(panel.id) }
        Button(isZoomed ? "Restore" : "Zoom") { ws.toggleZoom(panel.id) }
        Button("Pop Out into Window") { ws.popOut(panel.id) }
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

    private var fullHeader: some View {
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
                if panel.kind == .note || panel.kind == .terminal {
                    IconButton(symbol: DictationController.shared.isListening(for: panel.id) ? "mic.fill" : "mic",
                               help: "Dictate (Cmd Shift M)", active: DictationController.shared.isListening(for: panel.id), tint: accent) {
                        DictationController.shared.toggle(for: panel)
                    }
                }
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
                IconButton(symbol: "arrow.up.forward.square", help: "Pop out into its own window") {
                    ws.popOut(panel.id)
                }
                IconButton(symbol: "xmark", help: "Close panel (Cmd W)") {
                    ws.close(panel.id)
                }
            }
            .opacity(showActions ? 1 : 0)
            .offset(x: showActions ? 0 : 6)
            .animation(Motion.quick, value: showActions)
        }
        .padding(.horizontal, 12)
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

    private var content: some View { PanelBodyView(panel: panel) }
}

/// The inside of a panel, shared by the main window and pop-out windows.
struct PanelBodyView: View {
    @Bindable var panel: Panel

    var body: some View {
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
            SettingRow(label: "Typeface", value: panel.settings.fontFamily.isEmpty ? nil : panel.settings.fontFamily) {
                Picker("", selection: Binding(get: { panel.settings.font },
                                              set: { panel.settings.font = $0; panel.settings.fontFamily = "" })) {
                    ForEach(EditorFont.allCases) { f in Text(f.label).tag(f) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            SliderRow(label: "Size", value: $panel.settings.fontSize, range: 11...30, step: 0.5,
                      format: { String(format: "%.1f", $0) }, tint: accent)
            SliderRow(label: "Line height", value: $panel.settings.lineHeight, range: 1.1...2.2, step: 0.05,
                      format: { String(format: "%.2f", $0) }, tint: accent)
            SliderRow(label: "Paragraph spacing", value: $panel.settings.paragraphSpacing, range: 0...1, step: 0.05,
                      format: { String(format: "%.2f", $0) }, tint: accent)
            SliderRow(label: "Heading size", value: $panel.settings.headingScale, range: 0...1.6, step: 0.05,
                      format: { String(format: "%.0f%%", $0 * 100) }, tint: accent)
            SliderRow(label: "Code size", value: $panel.settings.codeScale, range: 0.7...1.1, step: 0.02,
                      format: { String(format: "%.0f%%", $0 * 100) }, tint: accent)
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

    private static let monoFamilies: [String] = {
        let fm = NSFontManager.shared
        var set = Set<String>()
        for name in fm.availableFontNames(with: .fixedPitchFontMask) ?? [] {
            if let fam = NSFont(name: name, size: 12)?.familyName, !fam.hasPrefix(".") { set.insert(fam) }
        }
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()

    @ViewBuilder
    private var terminalSettings: some View {
        SettingsSection(title: "Terminal") {
            SettingRow(label: "Font", value: panel.settings.termFont.isEmpty ? "SF Mono" : nil) {
                Picker("", selection: $panel.settings.termFont) {
                    Text("SF Mono").tag("")
                    ForEach(Self.monoFamilies, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            SliderRow(label: "Font size", value: $panel.settings.termFontSize, range: 9...24, step: 0.5,
                      format: { String(format: "%.1f", $0) }, tint: accent)
            SliderRow(label: "Line height", value: $panel.settings.termLineHeight, range: 1.0...1.6, step: 0.02,
                      format: { String(format: "%.2f", $0) }, tint: accent)
            SettingRow(label: "Cursor") {
                SegmentedChips(options: CursorStyle.allCases, selection: $panel.settings.cursor,
                               label: { $0.label }, tint: accent)
            }
            ToggleRow(label: "Blinking cursor", isOn: $panel.settings.cursorBlink, tint: accent)
            ToggleRow(label: "Option key acts as Meta", isOn: $panel.settings.optionAsMeta, tint: accent)
            SliderRow(label: "Background opacity", value: $panel.settings.termOpacity, range: 0.3...1, step: 0.05,
                      format: { String(format: "%.0f%%", $0 * 100) }, tint: accent)
            SliderRow(label: "Scrollback", value: Binding(get: { Double(panel.settings.scrollbackLines) },
                                                          set: { panel.settings.scrollbackLines = Int($0) }),
                      range: 500...50000, step: 500, format: { "\(Int($0)) lines" }, tint: accent)
        }
        SettingsSection(title: "Startup") {
            textField("Shell", $panel.settings.shell, placeholder: "/bin/zsh")
            textField("Start in folder", $panel.settings.startDirectory, placeholder: "~/Projects")
            textField("Run on start", $panel.settings.startCommand, placeholder: "npm run dev")
            Text("Startup options apply to the next session. Close and reopen the panel to restart.")
                .font(Typo.ui(11))
                .foregroundStyle(theme.faintC)
        }
    }

    private func textField(_ label: String, _ text: Binding<String>, placeholder: String) -> some View {
        SettingRow(label: label) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.textC)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.hover))
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
            ToggleRow(label: "Hide completed tasks", isOn: $panel.settings.hideDone, tint: accent)
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
            SliderRow(label: "Long break", value: Binding(get: { Double(panel.settings.longBreakMinutes) },
                                                          set: { panel.settings.longBreakMinutes = Int($0) }),
                      range: 5...60, step: 5, format: { "\(Int($0)) min" }, tint: accent)
            SliderRow(label: "Sessions before long break", value: Binding(get: { Double(panel.settings.sessionsBeforeLong) },
                                                                          set: { panel.settings.sessionsBeforeLong = Int($0) }),
                      range: 2...8, step: 1, format: { "\(Int($0))" }, tint: accent)
            ToggleRow(label: "Play a sound when a session ends", isOn: $panel.settings.timerSound, tint: accent)
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
