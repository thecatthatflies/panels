import SwiftUI
import AppKit
import Observation

// MARK: - Site

struct Site: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var url: String
    var symbol: String = "globe"
    /// Only the web-related fields of PanelSettings are used (zoom, CSS, dark, app mode, session, blockers, refresh).
    var settings = PanelSettings()
}

enum SiteSymbols {
    static let all: [String] = [
        "globe", "safari", "network", "link", "bookmark", "star", "heart", "bolt",
        "scribble.variable", "function", "newspaper", "book.closed", "calendar", "envelope", "bubble.left", "message",
        "play.rectangle", "music.note", "photo", "film", "gamecontroller", "cart", "creditcard", "chart.line.uptrend.xyaxis",
        "chevron.left.forwardslash.chevron.right", "terminal", "hammer", "wrench.and.screwdriver", "cpu", "externaldrive", "cloud", "lock.shield",
        "doc.text", "folder", "tray", "paperplane", "map", "mappin.and.ellipse", "airplane", "graduationcap",
        "brain", "lightbulb", "flame", "leaf", "sun.max", "moon", "sparkles", "wand.and.stars"
    ]
}

// MARK: - Library

@Observable
final class SiteLibrary {
    static let shared = SiteLibrary()

    var sites: [Site] {
        didSet { save() }
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Panels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sites.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([Site].self, from: data) {
            sites = decoded
        } else {
            sites = WebPreset.all.map { Site(name: $0.name, url: $0.url, symbol: $0.symbol) }
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(sites) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    func index(of id: UUID) -> Int? { sites.firstIndex { $0.id == id } }

    @discardableResult
    func add(name: String = "New Site", url: String = "https://") -> Site {
        var s = Site(name: name, url: url)
        s.settings.padding = 0
        sites.append(s)
        return s
    }

    func duplicate(_ id: UUID) -> Site? {
        guard let i = index(of: id) else { return nil }
        var copy = sites[i]
        copy.id = UUID()
        copy.name += " copy"
        sites.insert(copy, at: i + 1)
        return copy
    }

    func remove(_ id: UUID) { sites.removeAll { $0.id == id } }

    func move(_ id: UUID, by delta: Int) {
        guard let i = index(of: id) else { return }
        let j = i + delta
        guard j >= 0, j < sites.count else { return }
        sites.swapAt(i, j)
    }

    /// Creates a site from a live web panel so its URL and tweaks are one click away later.
    @discardableResult
    func saveSite(from panel: Panel) -> Site {
        var s = Site(name: panel.title == "Web" ? (URL(string: panel.url)?.host ?? "Site") : panel.title,
                     url: panel.url, symbol: "globe", settings: panel.settings)
        s.settings.siteID = nil
        sites.append(s)
        return s
    }

    func panelSettings(for site: Site) -> PanelSettings {
        var st = site.settings
        st.siteID = site.id
        return st
    }
}

// MARK: - Opening sites

extension Workspace {
    @discardableResult
    func openSite(_ site: Site) -> Panel {
        let panel = addPanel(.web, url: site.url, title: site.name, settings: SiteLibrary.shared.panelSettings(for: site))
        return panel
    }
}

// MARK: - Settings router

@Observable
final class SettingsRouter {
    static let shared = SettingsRouter()
    enum Tab: String, CaseIterable, Identifiable {
        case general, writing, sites, updates, shortcuts
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .writing: return "pencil.and.outline"
            case .sites: return "globe"
            case .updates: return "arrow.triangle.2.circlepath"
            case .shortcuts: return "command"
            }
        }
    }
    var tab: Tab = .general
    var selectedSite: UUID?

    func show(_ tab: Tab, site: UUID? = nil) {
        self.tab = tab
        if let site { selectedSite = site }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Editor used by Settings and the web settings popover

struct SiteEditor: View {
    @Binding var site: Site
    @Environment(\.theme) private var theme
    private let ws = Workspace.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSection(title: "Site") {
                    labeledField("Name", text: $site.name, placeholder: "Name")
                    labeledField("Address", text: $site.url, placeholder: "https://example.com", mono: true)
                    SettingRow(label: "Icon") { symbolGrid }
                }

                SettingsSection(title: "Behavior") {
                    ToggleRow(label: "App mode (no address bar, links open outside)", isOn: $site.settings.appMode)
                    ToggleRow(label: "Own login session", isOn: $site.settings.isolatedSession)
                    ToggleRow(label: "Request mobile layout", isOn: $site.settings.mobileUA)
                    ToggleRow(label: "Block trackers and ads", isOn: $site.settings.blockTrackers)
                    SliderRow(label: "Page zoom", value: $site.settings.zoom, range: 0.5...2.0, step: 0.05,
                              format: { String(format: "%.0f%%", $0 * 100) })
                    SliderRow(label: "Auto refresh", value: Binding(get: { Double(site.settings.refreshMinutes) },
                                                                      set: { site.settings.refreshMinutes = Int($0) }),
                              range: 0...60, step: 1, format: { $0 == 0 ? "Off" : "\(Int($0)) min" })
                }

                SettingsSection(title: "Appearance") {
                    ToggleRow(label: "Force dark mode", isOn: $site.settings.forceDark)
                    SettingRow(label: "Accent") { AccentSwatches(selection: $site.settings.accent) }
                    SettingRow(label: "Surface") {
                        SegmentedChips(options: SurfaceStyle.allCases, selection: $site.settings.surface, label: { $0.label })
                    }
                    SettingRow(label: "Custom CSS") {
                        TextEditor(text: $site.settings.customCSS)
                            .font(.system(size: 11.5, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(theme.textC)
                            .frame(height: 110)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.hover))
                    }
                    Text("Injected into every page of this site. Example: header { display: none; }")
                        .font(Typo.ui(11)).foregroundStyle(theme.faintC)
                }

                HStack(spacing: 8) {
                    Button { ws.openSite(site) } label: { Label("Open as Panel", systemImage: "plus.rectangle") }
                    Button { _ = SiteLibrary.shared.duplicate(site.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Spacer()
                    Button(role: .destructive) { SiteLibrary.shared.remove(site.id) } label: { Label("Delete", systemImage: "trash") }
                }
                .controlSize(.regular)
            }
            .padding(22)
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String, mono: Bool = false) -> some View {
        SettingRow(label: label) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(mono ? .system(size: 12, design: .monospaced) : Typo.ui(13))
                .foregroundStyle(theme.textC)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.hover))
        }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8), spacing: 6) {
            ForEach(SiteSymbols.all, id: \.self) { sym in
                let on = site.symbol == sym
                Button { withAnimation(.snappy(duration: 0.18)) { site.symbol = sym } } label: {
                    Image(systemName: sym)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(on ? theme.accentC : theme.mutedC)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(on ? theme.accentC.opacity(0.18) : theme.hover))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(on ? theme.accentC.opacity(0.6) : .clear, lineWidth: 1))
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}
