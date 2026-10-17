import SwiftUI
import AppKit
import WebKit
import Observation

// MARK: - Downloads

@Observable
final class DownloadItem: Identifiable {
    let id = UUID()
    var name: String
    var destination: URL?
    var fraction: Double = 0
    var finished = false
    var failed = false
    @ObservationIgnored var download: WKDownload?
    @ObservationIgnored var observation: NSKeyValueObservation?

    init(name: String) { self.name = name }
}

enum DownloadFolder {
    /// Overridable so the self test never writes into the real Downloads folder.
    static var override: URL?

    static var url: URL {
        override ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// "name.ext", then "name 2.ext", "name 3.ext" and so on.
    static func uniqueURL(for filename: String) -> URL {
        let clean = filename.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let base = clean.isEmpty ? "download" : clean
        let ns = base as NSString
        let stem = ns.deletingPathExtension, ext = ns.pathExtension
        var candidate = url.appendingPathComponent(base)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            candidate = url.appendingPathComponent(name)
            n += 1
        }
        return candidate
    }
}

// MARK: - Site permissions (camera, microphone, location)

enum SitePermission: String {
    case camera, microphone, cameraAndMicrophone

    var noun: String {
        switch self {
        case .camera: return "your camera"
        case .microphone: return "your microphone"
        case .cameraAndMicrophone: return "your camera and microphone"
        }
    }

    init(_ type: WKMediaCaptureType) {
        switch type {
        case .camera: self = .camera
        case .microphone: self = .microphone
        default: self = .cameraAndMicrophone
        }
    }
}

/// Remembered allow and deny answers, keyed by "host|permission". Stored in permissions.json.
final class SitePermissions {
    static let shared = SitePermissions()
    private var answers: [String: Bool]

    private static var fileURL: URL { AppPaths.dir.appendingPathComponent("permissions.json") }

    init() {
        answers = (try? JSONDecoder().decode([String: Bool].self, from: Data(contentsOf: Self.fileURL))) ?? [:]
    }

    private func key(_ host: String, _ p: SitePermission) -> String { "\(host.lowercased())|\(p.rawValue)" }

    func answer(host: String, _ p: SitePermission) -> Bool? { answers[key(host, p)] }

    func remember(host: String, _ p: SitePermission, allow: Bool) {
        answers[key(host, p)] = allow
        save()
    }

    func reset(host: String) {
        let prefix = host.lowercased() + "|"
        answers = answers.filter { !$0.key.hasPrefix(prefix) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(answers) { try? data.write(to: Self.fileURL, options: .atomic) }
    }
}

// MARK: - Native dialogs for page requests

enum WebDialogs {
    /// Runs the alert as a sheet on the web view's window, or modally when there is none.
    static func run(_ alert: NSAlert, in webView: WKWebView, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = webView.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    static func heading(for frame: WKFrameInfo) -> String {
        let host = frame.request.url?.host ?? ""
        return host.isEmpty ? "This page says" : "\(host) says"
    }

    static func alert(_ message: String, frame: WKFrameInfo, webView: WKWebView, done: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = heading(for: frame)
        a.informativeText = message
        a.addButton(withTitle: "OK")
        run(a, in: webView) { _ in done() }
    }

    static func confirm(_ message: String, frame: WKFrameInfo, webView: WKWebView, done: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = heading(for: frame)
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        run(a, in: webView) { done($0 == .alertFirstButtonReturn) }
    }

    static func prompt(_ message: String, defaultText: String?, frame: WKFrameInfo, webView: WKWebView,
                       done: @escaping (String?) -> Void) {
        let a = NSAlert()
        a.messageText = heading(for: frame)
        a.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        a.accessoryView = field
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        run(a, in: webView) { done($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    static func credentials(host: String, realm: String?, webView: WKWebView,
                            done: @escaping (URLCredential?) -> Void) {
        let a = NSAlert()
        a.messageText = "Sign in to \(host)"
        a.informativeText = realm.map { "The site says: \($0)" } ?? "This site asks for a name and password."
        let user = NSTextField(frame: NSRect(x: 0, y: 28, width: 260, height: 24))
        user.placeholderString = "Name"
        let pass = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        pass.placeholderString = "Password"
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        box.addSubview(user)
        box.addSubview(pass)
        a.accessoryView = box
        a.addButton(withTitle: "Sign In")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = user
        run(a, in: webView) { r in
            done(r == .alertFirstButtonReturn
                 ? URLCredential(user: user.stringValue, password: pass.stringValue, persistence: .forSession) : nil)
        }
    }

    static func permission(host: String, _ p: SitePermission, webView: WKWebView, done: @escaping (Bool) -> Void) {
        if let known = SitePermissions.shared.answer(host: host, p) { done(known); return }
        let a = NSAlert()
        a.messageText = "\(host) wants to use \(p.noun)"
        a.informativeText = "You can change this later from the More menu."
        a.addButton(withTitle: "Allow")
        a.addButton(withTitle: "Don't Allow")
        a.showsSuppressionButton = true
        a.suppressionButton?.title = "Remember for this site"
        run(a, in: webView) { r in
            let allow = r == .alertFirstButtonReturn
            if a.suppressionButton?.state == .on { SitePermissions.shared.remember(host: host, p, allow: allow) }
            done(allow)
        }
    }

    static func errorPage(for error: NSError, url: URL?) -> String {
        let host = url?.host ?? "this page"
        let reason: String
        switch error.code {
        case NSURLErrorNotConnectedToInternet: reason = "You are offline."
        case NSURLErrorCannotFindHost: reason = "Panels could not find \(host)."
        case NSURLErrorTimedOut: reason = "\(host) took too long to answer."
        case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid, NSURLErrorSecureConnectionFailed:
            reason = "The connection to \(host) is not private, so Panels did not open it."
        default: reason = error.localizedDescription
        }
        let target = url?.absoluteString ?? ""
        let escaped = reason.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        let link = target.replacingOccurrences(of: "\"", with: "%22")
        return """
        <html><head><meta name="color-scheme" content="light dark"><style>
        body { font: 15px -apple-system, sans-serif; display: flex; min-height: 100vh; align-items: center; justify-content: center; margin: 0; }
        div { max-width: 420px; padding: 24px; } h1 { font-size: 20px; margin: 0 0 8px; } p { opacity: .7; line-height: 1.5; }
        a { color: inherit; }
        </style></head><body><div><h1>Can't open this page</h1><p>\(escaped)</p><p><a href="\(link)">Try again</a></p></div></body></html>
        """
    }
}

// MARK: - Download strip (bottom of a web panel)

struct DownloadStrip: View {
    let controller: WebController
    let accent: Color
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(controller.downloads.suffix(3)) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.failed ? "exclamationmark.triangle" : (item.finished ? "checkmark.circle" : "arrow.down.circle"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(item.failed ? theme.mutedC : accent)
                    Text(item.name)
                        .font(Typo.ui(12, bold: true))
                        .foregroundStyle(theme.textC)
                        .lineLimit(1)
                        .frame(maxWidth: 160, alignment: .leading)
                    if !item.finished && !item.failed {
                        ProgressView(value: item.fraction).progressViewStyle(.linear).frame(width: 60).tint(accent)
                        IconButton(symbol: "xmark", help: "Cancel", size: 9, box: 20) { controller.cancel(item) }
                    } else {
                        if item.finished, let url = item.destination {
                            IconButton(symbol: "magnifyingglass", help: "Show in Finder", size: 10, box: 20) {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                        IconButton(symbol: "xmark", help: "Dismiss", size: 9, box: 20) { controller.dismiss(item) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(theme.surfaceC))
                .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
        }
        .padding(10)
        .animation(.snappy(duration: 0.2), value: controller.downloads.count)
    }
}

// MARK: - Per-site zoom

final class SiteZoom {
    static let shared = SiteZoom()
    private var zooms: [String: Double]

    private static var fileURL: URL { AppPaths.dir.appendingPathComponent("zoom.json") }

    init() {
        zooms = (try? JSONDecoder().decode([String: Double].self, from: Data(contentsOf: Self.fileURL))) ?? [:]
    }

    func zoom(host: String) -> Double? { zooms[host.lowercased()] }

    /// Stores the zoom for a host. A zoom of 1 removes the entry so the file only holds real choices.
    func remember(host: String, zoom: Double) {
        let key = host.lowercased()
        if abs(zoom - 1) < 0.001 { zooms.removeValue(forKey: key) } else { zooms[key] = zoom }
        if let data = try? JSONEncoder().encode(zooms) { try? data.write(to: Self.fileURL, options: .atomic) }
    }
}
