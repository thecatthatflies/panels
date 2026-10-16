import SwiftUI
import WebKit
import Observation

// MARK: - Presets

struct WebPreset: Identifiable {
    let id: String
    let name: String
    let url: String
    let symbol: String

    init(_ name: String, _ url: String, _ symbol: String) {
        id = name
        self.name = name
        self.url = url
        self.symbol = symbol
    }

    static let all: [WebPreset] = [
        WebPreset("Excalidraw", "https://excalidraw.com", "scribble.variable"),
        WebPreset("Desmos", "https://www.desmos.com/calculator", "function"),
        WebPreset("Hacker News", "https://news.ycombinator.com", "newspaper"),
        WebPreset("GitHub", "https://github.com", "chevron.left.forwardslash.chevron.right"),
        WebPreset("Wikipedia", "https://en.wikipedia.org", "book.closed"),
        WebPreset("Google Calendar", "https://calendar.google.com", "calendar"),
        WebPreset("YouTube", "https://www.youtube.com", "play.rectangle")
    ]
}

// MARK: - Web view

final class PanelWebView: WKWebView {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }

    override func mouseDown(with event: NSEvent) {
        onFocus?()
        super.mouseDown(with: event)
    }
}

@Observable
final class WebController: NSObject, WKNavigationDelegate, WKUIDelegate {
    @ObservationIgnored let webView: PanelWebView
    @ObservationIgnored weak var panel: Panel?
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []

    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var progress: Double = 0
    var pageTitle = ""

    static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    init(panel: Panel) {
        self.panel = panel
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = true
        webView = PanelWebView(frame: .zero, configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")

        observers = [
            webView.observe(\.canGoBack, options: [.new]) { [weak self] v, _ in self?.canGoBack = v.canGoBack },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] v, _ in self?.canGoForward = v.canGoForward },
            webView.observe(\.isLoading, options: [.new]) { [weak self] v, _ in self?.isLoading = v.isLoading },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] v, _ in self?.progress = v.estimatedProgress },
            webView.observe(\.title, options: [.new]) { [weak self] v, _ in self?.pageTitle = v.title ?? "" }
        ]

        if !panel.url.isEmpty { load(panel.url) }
    }

    func apply(settings: PanelSettings) {
        if abs(webView.pageZoom - CGFloat(settings.zoom)) > 0.001 { webView.pageZoom = CGFloat(settings.zoom) }
        let ua: String? = settings.mobileUA ? Self.mobileUA : nil
        if webView.customUserAgent != ua {
            webView.customUserAgent = ua
            if webView.url != nil { webView.reload() }
        }
    }

    static func normalize(_ input: String) -> URL? {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("file://") { return URL(string: t) }
        if t.hasPrefix("localhost") || t.hasPrefix("127.0.0.1") { return URL(string: "http://" + t) }
        if !t.contains(" "), t.contains(".") { return URL(string: "https://" + t) }
        var comps = URLComponents(string: "https://duckduckgo.com/")!
        comps.queryItems = [URLQueryItem(name: "q", value: t)]
        return comps.url
    }

    func load(_ input: String) {
        guard let url = Self.normalize(input) else { return }
        panel?.url = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }

    // MARK: delegate

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { syncURL() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncURL()
        if let p = panel, p.title == "Web", let host = webView.url?.host {
            p.title = host.replacingOccurrences(of: "www.", with: "")
        }
    }

    private func syncURL() {
        if let u = webView.url?.absoluteString, panel?.url != u { panel?.url = u }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

// MARK: - SwiftUI

struct WebRepresentable: NSViewRepresentable {
    let panel: Panel

    func makeNSView(context: Context) -> PanelWebView {
        let c = Runtime.shared.web(for: panel)
        c.apply(settings: panel.settings)
        return c.webView
    }

    func updateNSView(_ view: PanelWebView, context: Context) {
        Runtime.shared.web(for: panel).apply(settings: panel.settings)
    }
}

struct WebPanelView: View {
    @Bindable var panel: Panel
    @Environment(\.theme) private var theme

    private var accent: Color { theme.accent(panel.settings.accent) }

    var body: some View {
        let controller = Runtime.shared.web(for: panel)
        VStack(spacing: 0) {
            if panel.settings.showAddressBar {
                AddressBar(panel: panel, controller: controller, accent: accent)
            }
            ZStack {
                WebRepresentable(panel: panel)
                if panel.url.isEmpty { WebStartView(panel: panel, controller: controller, accent: accent) }
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 0, bottomTrailingRadius: 0))
        }
    }
}

struct AddressBar: View {
    @Bindable var panel: Panel
    let controller: WebController
    let accent: Color
    @Environment(\.theme) private var theme
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                IconButton(symbol: "chevron.left", help: "Back", size: 11, box: 24) { controller.goBack() }
                    .opacity(controller.canGoBack ? 1 : 0.35)
                    .disabled(!controller.canGoBack)
                IconButton(symbol: "chevron.right", help: "Forward", size: 11, box: 24) { controller.goForward() }
                    .opacity(controller.canGoForward ? 1 : 0.35)
                    .disabled(!controller.canGoForward)
                IconButton(symbol: controller.isLoading ? "xmark" : "arrow.clockwise",
                           help: controller.isLoading ? "Stop" : "Reload", size: 11, box: 24) {
                    controller.isLoading ? controller.stop() : controller.reload()
                }

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.faintC)
                    TextField("Search or enter address", text: $text)
                        .textFieldStyle(.plain)
                        .font(Typo.ui(12.5))
                        .foregroundStyle(theme.textC)
                        .focused($focused)
                        .onSubmit {
                            controller.load(text)
                            focused = false
                        }
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(theme.hover))
                .overlay(Capsule().strokeBorder(focused ? accent.opacity(0.7) : .clear, lineWidth: 1))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Rectangle()
                .fill(accent)
                .frame(height: 2)
                .scaleEffect(x: controller.isLoading ? max(controller.progress, 0.05) : 0, anchor: .leading)
                .opacity(controller.isLoading ? 1 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.25), value: controller.progress)
        }
        .onAppear { text = display(panel.url) }
        .onChange(of: panel.url) { _, new in if !focused { text = display(new) } }
        .onChange(of: focused) { _, f in if !f { text = display(panel.url) } }
    }

    private func display(_ s: String) -> String {
        s.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }
}

struct WebStartView: View {
    @Bindable var panel: Panel
    let controller: WebController
    let accent: Color
    @Environment(\.theme) private var theme

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Open something")
                        .font(Typo.ui(20, bold: true))
                        .foregroundStyle(theme.textC)
                    Text("Type an address above, or start from a web app.")
                        .font(Typo.ui(13))
                        .foregroundStyle(theme.mutedC)
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(WebPreset.all) { preset in
                        Button {
                            panel.title = preset.name
                            controller.load(preset.url)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: preset.symbol)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(accent)
                                    .frame(width: 22)
                                Text(preset.name)
                                    .font(Typo.ui(13, bold: true))
                                    .foregroundStyle(theme.textC)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(theme.hover))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            .padding(CGFloat(max(panel.settings.padding, 16)))
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.surfaceC)
    }
}
