import SwiftUI
import WebKit
import Observation

// MARK: - Seed presets (the editable library starts from these)

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

// MARK: - Tracker blocking

enum TrackerBlocklist {
    static let domains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
        "googletagmanager.com", "googletagservices.com", "facebook.net", "scorecardresearch.com",
        "hotjar.com", "segment.io", "segment.com", "mixpanel.com", "amplitude.com", "adnxs.com",
        "taboola.com", "outbrain.com", "criteo.com", "criteo.net", "quantserve.com", "fullstory.com",
        "adsrvr.org", "rubiconproject.com", "pubmatic.com", "openx.net", "moatads.com", "bing.com/bat"
    ]

    static var json: String {
        let alternation = domains
            .map { $0.replacingOccurrences(of: ".", with: "\\\\.").replacingOccurrences(of: "/", with: "\\\\/") }
            .joined(separator: "|")
        return """
        [{"trigger":{"url-filter":"^https?://([a-z0-9-]+\\\\.)*(\(alternation))"},"action":{"type":"block"}}]
        """
    }

    static let identifier = "panels.trackers.v1"
}

// MARK: - Web view

final class PanelWebView: WKWebView {
    var onFocus: (() -> Void)?
    var onFind: (() -> Void)?
    var onPrint: (() -> Void)?
    var onSavePDF: (() -> Void)?

    /// Renames WebKit's own items to match the app (links open in a new panel, not a window) and adds page actions.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items {
            switch item.identifier?.rawValue {
            case "WKMenuItemIdentifierOpenLinkInNewWindow": item.title = "Open Link in New Panel"
            case "WKMenuItemIdentifierOpenImageInNewWindow": item.title = "Open Image in New Panel"
            case "WKMenuItemIdentifierOpenFrameInNewWindow": item.title = "Open Frame in New Panel"
            default: break
            }
        }
        menu.addItem(.separator())
        for (title, action) in [("Find in Page", onFind), ("Print...", onPrint), ("Save as PDF...", onSavePDF)] {
            let item = ClosureMenuItem(title: title) { action?() }
            menu.addItem(item)
        }
    }

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

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { handler() }
}

@Observable
final class WebController: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    @ObservationIgnored let webView: PanelWebView
    @ObservationIgnored weak var panel: Panel?
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []
    @ObservationIgnored private var homeHost: String?
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var appliedCSS: String?
    @ObservationIgnored private var appliedBlock: Bool?
    @ObservationIgnored private var ruleList: WKContentRuleList?

    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var progress: Double = 0
    var pageTitle = ""
    var downloads: [DownloadItem] = []
    var findOpen = false
    var findText = ""
    /// nil before a search, then whether the last search found a match.
    var findFound: Bool?

    /// Safari style suffix so sites that sniff for Safari treat the panel as Safari.
    static let safariToken = "Version/\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).0 Safari/605.1.15"

    static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// `configuration` is set for popups: WebKit requires the window.open view to be built from the
    /// configuration it hands us, which also keeps the opener's data store and the window.opener link.
    init(panel: Panel, configuration: WKWebViewConfiguration? = nil) {
        self.panel = panel
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil {
            if panel.settings.isolatedSession {
                let ident = panel.settings.siteID ?? panel.id
                config.websiteDataStore = WKWebsiteDataStore(forIdentifier: ident)
            } else {
                config.websiteDataStore = .default()
            }
            config.applicationNameForUserAgent = Self.safariToken
        }
        config.preferences.isElementFullscreenEnabled = true
        // Standard popup blocking: a page can only open a window from a click or key press, never on its own.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = PanelWebView(frame: .zero, configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.onFind = { [weak self] in self?.openFind() }
        webView.onPrint = { [weak self] in self?.printPage() }
        webView.onSavePDF = { [weak self] in self?.savePDF() }

        observers = [
            webView.observe(\.canGoBack, options: [.new]) { [weak self] v, _ in self?.canGoBack = v.canGoBack },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] v, _ in self?.canGoForward = v.canGoForward },
            webView.observe(\.isLoading, options: [.new]) { [weak self] v, _ in self?.isLoading = v.isLoading },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] v, _ in self?.progress = v.estimatedProgress },
            webView.observe(\.title, options: [.new]) { [weak self] v, _ in self?.pageTitle = v.title ?? "" }
        ]

        applyTweaks(settings: panel.settings)
        if configuration == nil, !panel.url.isEmpty { load(panel.url) }
    }

    deinit { refreshTimer?.invalidate() }

    // MARK: settings

    func apply(settings: PanelSettings) {
        if abs(webView.pageZoom - CGFloat(settings.zoom)) > 0.001 {
            webView.pageZoom = CGFloat(settings.zoom)
            if let host = webView.url?.host { SiteZoom.shared.remember(host: host, zoom: settings.zoom) }
        }
        let ua: String? = settings.mobileUA ? Self.mobileUA : nil
        if webView.customUserAgent != ua {
            webView.customUserAgent = ua
            if webView.url != nil { webView.reload() }
        }
        applyTweaks(settings: settings)
        configureRefresh(minutes: settings.refreshMinutes)
    }

    private static let darkCSS = """
    html { filter: invert(1) hue-rotate(180deg) !important; background: #fff; }
    img, video, picture, canvas, svg image, iframe, [style*="background-image"] { filter: invert(1) hue-rotate(180deg) !important; }
    """

    private func applyTweaks(settings: PanelSettings) {
        let css = (settings.forceDark ? Self.darkCSS : "") + "\n" + settings.customCSS
        if css != appliedCSS {
            appliedCSS = css
            let ucc = webView.configuration.userContentController
            ucc.removeAllUserScripts()
            let trimmed = css.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let js = Self.styleScript(css: css)
                ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false))
                webView.evaluateJavaScript(js, completionHandler: nil)
            } else {
                webView.evaluateJavaScript("var e=document.getElementById('panels-css'); if(e){e.remove();}", completionHandler: nil)
            }
        }
        if settings.blockTrackers != appliedBlock {
            appliedBlock = settings.blockTrackers
            updateBlocker(enabled: settings.blockTrackers)
        }
    }

    private static func styleScript(css: String) -> String {
        let literal = (try? JSONSerialization.data(withJSONObject: [css]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return """
        (function(){
          var css = \(literal)[0];
          var el = document.getElementById('panels-css');
          if (!el) { el = document.createElement('style'); el.id = 'panels-css'; (document.head || document.documentElement).appendChild(el); }
          el.textContent = css;
        })();
        """
    }

    private func updateBlocker(enabled: Bool) {
        let ucc = webView.configuration.userContentController
        if let list = ruleList { ucc.remove(list); ruleList = nil }
        guard enabled else { return }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: TrackerBlocklist.identifier,
                                                                encodedContentRuleList: TrackerBlocklist.json) { [weak self] list, _ in
            DispatchQueue.main.async {
                guard let self, let list, self.appliedBlock == true else { return }
                self.ruleList = list
                self.webView.configuration.userContentController.add(list)
            }
        }
    }

    private func configureRefresh(minutes: Int) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard minutes > 0 else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            self?.webView.reload()
        }
    }

    // MARK: navigation

    static func normalize(_ input: String) -> URL? {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("file://") { return URL(string: t) }
        if t.hasPrefix("localhost") || t.hasPrefix("127.0.0.1") { return URL(string: "http://" + t) }
        if !t.contains(" "), t.contains(".") { return URL(string: "https://" + t) }
        var comps = URLComponents(string: "https://www.google.com/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: t)]
        return comps.url
    }

    func load(_ input: String) {
        guard let url = Self.normalize(input) else { return }
        homeHost = url.host
        panel?.url = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    // MARK: find, print, pdf

    func openFind() {
        findOpen = true
        NotificationCenter.default.post(name: .panelsFocusFind, object: panel?.id)
    }

    func closeFind() {
        findOpen = false
        findFound = nil
        webView.evaluateJavaScript("window.getSelection().removeAllRanges()", completionHandler: nil)
        webView.window?.makeFirstResponder(webView)
    }

    func find(backwards: Bool = false) {
        guard !findText.isEmpty else { findFound = nil; return }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.wraps = true
        config.caseSensitive = false
        webView.find(findText, configuration: config) { [weak self] result in
            DispatchQueue.main.async { self?.findFound = result.matchFound }
        }
    }

    func printPage() {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        let op = webView.printOperation(with: info)
        op.view?.frame = webView.bounds
        if let window = webView.window {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    func savePDF() {
        guard let window = webView.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (pageTitle.isEmpty ? "Page" : pageTitle).replacingOccurrences(of: "/", with: "-") + ".pdf"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.webView.createPDF { result in
                switch result {
                case .success(let data):
                    do { try data.write(to: url, options: .atomic); Workspace.shared.showToast("Saved \(url.lastPathComponent)") }
                    catch { Workspace.shared.showToast("Could not save the PDF") }
                case .failure: Workspace.shared.showToast("Could not save this page as a PDF")
                }
            }
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }

    func clearSiteData() {
        let store = webView.configuration.websiteDataStore
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let host = self.webView.url?.host ?? ""
            let mine = records.filter { host.hasSuffix($0.displayName) || $0.displayName.hasSuffix(host) }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: mine) {
                DispatchQueue.main.async { self.webView.reload() }
            }
        }
    }

    // MARK: delegate

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncURL()
        // Each site keeps the zoom you last set on it.
        if let host = webView.url?.host, let z = SiteZoom.shared.zoom(host: host), let panel, abs(panel.settings.zoom - z) > 0.001 {
            panel.settings.zoom = z
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncURL()
        if let p = panel, p.title == "Web", let host = webView.url?.host {
            p.title = host.replacingOccurrences(of: "www.", with: "")
        }
    }

    private func syncURL() {
        if let u = webView.url?.absoluteString, panel?.url != u { panel?.url = u }
        if homeHost == nil { homeHost = webView.url?.host }
    }

    private func registrableDomain(_ host: String?) -> String {
        guard let host else { return "" }
        let parts = host.split(separator: ".")
        return parts.suffix(2).joined(separator: ".")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if panel?.settings.appMode == true,
           navigationAction.navigationType == .linkActivated,
           let target = navigationAction.request.url,
           target.scheme?.hasPrefix("http") == true,
           registrableDomain(target.host) != registrableDomain(homeHost) {
            NSWorkspace.shared.open(target)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if navigationResponse.isForMainFrame, disposition.hasPrefix("attachment") || !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        adopt(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        adopt(download)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    private func showError(_ error: Error) {
        let e = error as NSError
        // Cancelled loads, and loads replaced by a download, are not failures.
        guard e.domain == NSURLErrorDomain, e.code != NSURLErrorCancelled else { return }
        let failing = (e.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? webView.url
        webView.loadHTMLString(WebDialogs.errorPage(for: e, url: failing), baseURL: failing)
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        WebDialogs.credentials(host: challenge.protectionSpace.host, realm: challenge.protectionSpace.realm,
                               webView: webView) { cred in
            if let cred { completionHandler(.useCredential, cred) } else { completionHandler(.cancelAuthenticationChallenge, nil) }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    // MARK: popups

    /// Opens a new web panel for window.open and target=_blank. The returned view is built from `configuration`.
    func makePopup(configuration: WKWebViewConfiguration) -> WKWebView? {
        var st = panel?.settings ?? PanelSettings()
        st.appMode = false
        guard let popup = Workspace.shared.addPanel(.web, settings: st) else { return nil }
        return Runtime.shared.web(for: popup, configuration: configuration).webView
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url ?? URL(string: "about:blank") else { return nil }
        if panel?.settings.appMode == true, url.scheme?.hasPrefix("http") == true,
           registrableDomain(url.host) != registrableDomain(homeHost) {
            NSWorkspace.shared.open(url)
            return nil
        }
        return makePopup(configuration: configuration)
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let id = panel?.id else { return }
        DispatchQueue.main.async { Workspace.shared.close(id) }
    }

    // MARK: dialogs, uploads, permissions

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        WebDialogs.alert(message, frame: frame, webView: webView, done: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        WebDialogs.confirm(message, frame: frame, webView: webView, done: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        WebDialogs.prompt(prompt, defaultText: defaultText, frame: frame, webView: webView, done: completionHandler)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let open = NSOpenPanel()
        open.allowsMultipleSelection = parameters.allowsMultipleSelection
        open.canChooseDirectories = parameters.allowsDirectories
        open.canChooseFiles = true
        if let window = webView.window {
            open.beginSheetModal(for: window) { completionHandler($0 == .OK ? open.urls : nil) }
        } else {
            completionHandler(open.runModal() == .OK ? open.urls : nil)
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        WebDialogs.permission(host: origin.host, SitePermission(type), webView: webView) {
            decisionHandler($0 ? .grant : .deny)
        }
    }

    func resetPermissions() {
        guard let host = webView.url?.host else { return }
        SitePermissions.shared.reset(host: host)
        Workspace.shared.showToast("Permissions reset for \(host)")
    }

    // MARK: downloads

    private func adopt(_ download: WKDownload) {
        download.delegate = self
        let item = DownloadItem(name: download.originalRequest?.url?.lastPathComponent ?? "download")
        item.download = download
        item.observation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak item] p, _ in
            DispatchQueue.main.async { item?.fraction = p.fractionCompleted }
        }
        downloads.append(item)
    }

    private func item(for download: WKDownload) -> DownloadItem? { downloads.first { $0.download === download } }

    /// Starts a download without a navigation (save image, save link).
    func startDownload(_ request: URLRequest, completion: ((DownloadItem?) -> Void)? = nil) {
        webView.startDownload(using: request) { [weak self] download in
            self?.adopt(download)
            completion?(self?.item(for: download))
        }
    }

    func cancel(_ item: DownloadItem) {
        item.download?.cancel { _ in }
        dismiss(item)
    }

    func dismiss(_ item: DownloadItem) { downloads.removeAll { $0.id == item.id } }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let dest = DownloadFolder.uniqueURL(for: suggestedFilename)
        if let it = item(for: download) { it.name = dest.lastPathComponent; it.destination = dest }
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let it = item(for: download) else { return }
        it.finished = true
        it.fraction = 1
        Workspace.shared.showToast("Downloaded \(it.name)")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let it = item(for: download) else { return }
        it.failed = true
        Workspace.shared.showToast("Could not download \(it.name)")
    }
}

// MARK: - SwiftUI

struct WebRepresentable: NSViewRepresentable {
    let panel: Panel

    func makeNSView(context: Context) -> HostContainer {
        let c = Runtime.shared.web(for: panel)
        c.apply(settings: panel.settings)
        let host = HostContainer()
        host.attach(c.webView, steal: true)
        return host
    }

    func updateNSView(_ container: HostContainer, context: Context) {
        let c = Runtime.shared.web(for: panel)
        container.attach(c.webView, steal: false)
        c.apply(settings: panel.settings)
    }

    static func dismantleNSView(_ container: HostContainer, coordinator: ()) {
        container.release()
    }
}

struct WebPanelView: View {
    @Bindable var panel: Panel
    @Environment(\.theme) private var theme
    private let ws = Workspace.shared

    private var accent: Color { theme.accent(panel.settings.accent) }
    private var showBar: Bool { panel.settings.showAddressBar && !panel.settings.appMode && !ws.focusMode }

    var body: some View {
        let controller = Runtime.shared.web(for: panel)
        VStack(spacing: 0) {
            if showBar {
                AddressBar(panel: panel, controller: controller, accent: accent)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if controller.findOpen { FindBar(controller: controller, accent: accent) }
            ZStack {
                WebRepresentable(panel: panel)
                if panel.url.isEmpty && controller.webView.url == nil { WebStartView(panel: panel, controller: controller, accent: accent) }
                if !controller.downloads.isEmpty {
                    VStack { Spacer(); HStack { Spacer(); DownloadStrip(controller: controller, accent: accent) } }
                }
                if panel.settings.appMode && controller.isLoading {
                    VStack {
                        Rectangle().fill(accent).frame(height: 2)
                            .scaleEffect(x: max(controller.progress, 0.05), anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .id(ws.webEpoch[panel.id] ?? 0)
        .animation(.snappy(duration: 0.25), value: showBar)
    }
}

struct AddressBar: View {
    @Bindable var panel: Panel
    let controller: WebController
    let accent: Color
    @Environment(\.theme) private var theme
    @Environment(\.panelSize) private var size
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if size >= .regular {
                    IconButton(symbol: "chevron.left", help: "Back", size: 11, box: 24) { controller.goBack() }
                        .opacity(controller.canGoBack ? 1 : 0.35)
                        .disabled(!controller.canGoBack)
                    IconButton(symbol: "chevron.right", help: "Forward", size: 11, box: 24) { controller.goForward() }
                        .opacity(controller.canGoForward ? 1 : 0.35)
                        .disabled(!controller.canGoForward)
                }
                IconButton(symbol: controller.isLoading ? "xmark" : "arrow.clockwise",
                           help: controller.isLoading ? "Stop" : "Reload", size: 11, box: 24) {
                    controller.isLoading ? controller.stop() : controller.reload()
                }

                HStack(spacing: 7) {
                    Image(systemName: panel.settings.isolatedSession ? "lock.shield" : "magnifyingglass")
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
                .frame(minWidth: 40)
                .frame(height: 26)
                .background(Capsule().fill(theme.hover))
                .overlay(Capsule().strokeBorder(focused ? accent.opacity(0.7) : .clear, lineWidth: 1))
                .animation(.snappy(duration: 0.18), value: focused)

                IconMenu(symbol: "ellipsis", help: "More", size: 12, box: 24) {
                    Button { if let u = URL(string: panel.url) { NSWorkspace.shared.open(u) } } label: {
                        Label("Open in Browser", systemImage: "safari")
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(panel.url, forType: .string)
                        Workspace.shared.showToast("Address copied")
                    } label: { Label("Copy Address", systemImage: "doc.on.doc") }
                    Divider()
                    Toggle(isOn: $panel.settings.forceDark) { Label("Force Dark Mode", systemImage: "moon") }
                    Toggle(isOn: $panel.settings.blockTrackers) { Label("Block Trackers", systemImage: "shield") }
                    Toggle(isOn: $panel.settings.mobileUA) { Label("Mobile Layout", systemImage: "iphone") }
                    Toggle(isOn: $panel.settings.appMode) { Label("App Mode", systemImage: "macwindow") }
                    Divider()
                    Button {
                        let s = SiteLibrary.shared.saveSite(from: panel)
                        Workspace.shared.showToast("Saved \(s.name) to your sites")
                    } label: { Label("Save as Site", systemImage: "bookmark") }
                    Button { controller.resetPermissions() } label: { Label("Reset Site Permissions", systemImage: "hand.raised.slash") }
                    Button { controller.clearSiteData() } label: { Label("Clear Site Data", systemImage: "trash") }
                }
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
        .onReceive(NotificationCenter.default.publisher(for: .panelsFocusAddressBar)) { note in
            if (note.object as? UUID) == panel.id { focused = true }
        }
    }

    private func display(_ s: String) -> String {
        s.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }
}

extension Notification.Name {
    static let panelsFocusAddressBar = Notification.Name("panelsFocusAddressBar")
}

struct WebStartView: View {
    @Bindable var panel: Panel
    let controller: WebController
    let accent: Color
    @Environment(\.theme) private var theme
    private let library = SiteLibrary.shared

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Open something")
                        .font(Typo.ui(20, bold: true))
                        .foregroundStyle(theme.textC)
                    Text("Type an address above, or start from one of your sites.")
                        .font(Typo.ui(13))
                        .foregroundStyle(theme.mutedC)
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(library.sites) { site in
                        Button { open(site) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: site.symbol)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(accent)
                                    .frame(width: 22)
                                Text(site.name)
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
                    Button { SettingsRouter.shared.show(.sites, site: library.add().id) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                            Text("Add site").font(Typo.ui(13, bold: true))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(theme.mutedC)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(theme.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(CGFloat(max(panel.settings.padding, 16)))
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.surfaceC)
    }

    private func open(_ site: Site) {
        var s = SiteLibrary.shared.panelSettings(for: site)
        s.noteMode = panel.settings.noteMode
        panel.settings = s
        panel.title = site.name
        Workspace.shared.webEpoch[panel.id, default: 0] += 1
        Runtime.shared.releaseWeb(panel.id)
        panel.url = site.url
    }
}

// MARK: - Find in page

extension Notification.Name {
    static let panelsFocusFind = Notification.Name("panelsFocusFind")
}

struct FindBar: View {
    @Bindable var controller: WebController
    let accent: Color
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 10.5, weight: .medium)).foregroundStyle(theme.faintC)
            TextField("Find in page", text: $controller.findText)
                .textFieldStyle(.plain)
                .font(Typo.ui(12.5))
                .foregroundStyle(theme.textC)
                .focused($focused)
                .onSubmit { controller.find() }
                .onChange(of: controller.findText) { _, _ in controller.find() }
                .onExitCommand { controller.closeFind() }
            if controller.findFound == false {
                Text("Not found").font(Typo.ui(11)).foregroundStyle(theme.faintC)
            }
            IconButton(symbol: "chevron.up", help: "Previous match (Cmd Shift G)", size: 10, box: 22) { controller.find(backwards: true) }
            IconButton(symbol: "chevron.down", help: "Next match (Cmd G)", size: 10, box: 22) { controller.find() }
            IconButton(symbol: "xmark", help: "Close (Escape)", size: 10, box: 22) { controller.closeFind() }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(theme.hover)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .panelsFocusFind)) { note in
            focused = true
        }
    }
}
