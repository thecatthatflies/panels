import SwiftUI
import AppKit
import Observation

/// Where releases are published. Every push to `main` runs the release workflow, which
/// creates a GitHub release containing Panels.zip. The app polls the latest release.
enum UpdateConfig {
    static let owner = "thecatthatflies"
    static let repo = "panels"
    static let assetSuffix = ".zip"
    static let checkInterval: TimeInterval = 60 * 60 * 3

    /// Overridable for testing: PANELS_UPDATE_FEED=http://localhost:8000/latest.json
    static var feedURL: URL {
        if let s = ProcessInfo.processInfo.environment["PANELS_UPDATE_FEED"], let u = URL(string: s) { return u }
        return URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }
}

struct ReleaseInfo: Equatable {
    let version: String
    let notes: String
    let assetURL: URL
    let pageURL: URL?
}

enum Version {
    /// Compares dotted numeric versions. "1.0.12" > "1.0.9", "v2" > "1.9.9".
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

@Observable
final class Updater: NSObject, URLSessionDownloadDelegate {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading(ReleaseInfo, Double)
        case ready(ReleaseInfo, URL)
        case installing
        case failed(String)
    }

    var state: State = .idle
    var lastChecked: Date?

    var autoDownload: Bool {
        didSet { UserDefaults.standard.set(autoDownload, forKey: "autoDownloadUpdates") }
    }

    @ObservationIgnored private var session: URLSession!
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pendingRelease: ReleaseInfo?
    @ObservationIgnored private var userInitiated = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    override init() {
        autoDownload = UserDefaults.standard.object(forKey: "autoDownloadUpdates") as? Bool ?? true
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    // MARK: scheduling

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.check(userInitiated: false) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: UpdateConfig.checkInterval, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if let last = self.lastChecked, Date().timeIntervalSince(last) < 60 * 20 { return }
            self.check(userInitiated: false)
        }
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    // MARK: check

    func check(userInitiated: Bool) {
        if isBusy { return }
        if case .ready = state { return }
        self.userInitiated = userInitiated
        state = .checking

        var request = URLRequest(url: UpdateConfig.feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Panels/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.handleFeed(data: data, response: response, error: error) }
        }.resume()
    }

    private func handleFeed(data: Data?, response: URLResponse?, error: Error?) {
        lastChecked = Date()
        if let error {
            state = userInitiated ? .failed("Could not check for updates. Check your internet connection and try again.") : .idle
            return
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { state = .upToDate; return }
        guard status == 200, let data, let release = Self.parse(data) else {
            state = userInitiated ? .failed("Could not check for updates right now. Try again in a moment.") : .idle
            return
        }
        if Version.compare(release.version, currentVersion) == .orderedDescending {
            state = .available(release)
            if autoDownload || userInitiated { download(release) }
        } else {
            state = .upToDate
        }
    }

    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(UpdateConfig.assetSuffix) == true }),
              let urlString = asset["browser_download_url"] as? String,
              let url = URL(string: urlString) else { return nil }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        return ReleaseInfo(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                           notes: json["body"] as? String ?? "",
                           assetURL: url, pageURL: page)
    }

    // MARK: download

    func download(_ release: ReleaseInfo) {
        if case .downloading = state { return }
        pendingRelease = release
        state = .downloading(release, 0)
        session.downloadTask(with: release.assetURL).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let release = pendingRelease, totalBytesExpectedToWrite > 0 else { return }
        state = .downloading(release, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let release = pendingRelease else { return }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("PanelsUpdate-\(UUID().uuidString)", isDirectory: true)
        let zip = work.appendingPathComponent("update.zip")
        let out = work.appendingPathComponent("unpacked", isDirectory: true)
        do {
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            try fm.moveItem(at: location, to: zip)
        } catch {
            state = .failed("Could not save the update. Make sure your disk has room and try again.")
            return
        }

        // Unzip off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", zip.path, out.path]
            do { try p.run() } catch {
                DispatchQueue.main.async { self.state = .failed("Could not open the update. Try again.") }
                return
            }
            p.waitUntilExit()

            let apps = (try? fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "app" } ?? []
            DispatchQueue.main.async {
                guard p.terminationStatus == 0, let app = apps.first, self.isValidBundle(app) else {
                    self.state = .failed("The update did not download correctly. Try again.")
                    return
                }
                self.state = .ready(release, app)
                Sound.play(.update)
                // Test hook for the end-to-end update test: install without clicking the pill.
                if ProcessInfo.processInfo.environment["PANELS_UPDATE_AUTOINSTALL"] == "1" { self.installAndRelaunch() }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, task is URLSessionDownloadTask {
            state = .failed("Could not download the update. Check your internet connection and try again.")
        }
    }

    private func isValidBundle(_ url: URL) -> Bool {
        guard let b = Bundle(url: url), b.bundleIdentifier == Bundle.main.bundleIdentifier else { return false }
        let exec = b.executableURL?.path ?? ""
        return FileManager.default.isExecutableFile(atPath: exec)
    }

    // MARK: install

    var installBlocker: String? {
        let path = Bundle.main.bundleURL.path
        if path.contains("/DerivedData/") || path.contains("/Build/Products/") || path.hasPrefix("/Volumes/") {
            return "This copy is running from a build folder or disk image. Move Panels to Applications to enable updating."
        }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().path
        if !FileManager.default.isWritableFile(atPath: parent) {
            return "Panels cannot replace itself in \(parent). Move it to a folder you can write to."
        }
        return nil
    }

    func installAndRelaunch() {
        guard case .ready(_, let newApp) = state else { return }
        if let blocker = installBlocker {
            state = .failed(blocker)
            return
        }
        state = .installing
        Persistence.saveNow()

        let dest = Bundle.main.bundleURL.path
        let script = """
        #!/bin/bash
        PID="$1"; NEW="$2"; DEST="$3"
        for i in $(seq 1 100); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        BACKUP="${DEST}.previous"
        rm -rf "$BACKUP"
        if mv "$DEST" "$BACKUP"; then
            if ditto "$NEW" "$DEST"; then
                xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
                rm -rf "$BACKUP"
            else
                rm -rf "$DEST"; mv "$BACKUP" "$DEST"
            fi
        fi
        rm -rf "$(dirname "$NEW")"
        open "$DEST"
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("panels-update-\(UUID().uuidString).sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            state = .failed("Could not install the update. Try again.")
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [scriptURL.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, dest]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            state = .failed("Could not install the update. Try again.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NSApp.terminate(nil) }
    }

    // MARK: summary text

    var statusLine: String {
        switch state {
        case .idle: return "Version \(currentVersion)"
        case .checking: return "Checking for updates"
        case .upToDate: return "Panels \(currentVersion) is up to date"
        case .available(let r): return "Version \(r.version) is available"
        case .downloading(let r, let p): return "Downloading \(r.version), \(Int(p * 100))%"
        case .ready(let r, _): return "Version \(r.version) is ready to install"
        case .installing: return "Installing"
        case .failed(let m): return m
        }
    }
}

// MARK: - Top bar pill

struct UpdatePill: View {
    @Environment(\.theme) private var theme
    private let updater = Updater.shared

    var body: some View {
        switch updater.state {
        case .available(let r):
            pill(symbol: "arrow.down.circle", text: "Update \(r.version)") { updater.download(r) }
        case .downloading(_, let p):
            pill(symbol: "arrow.triangle.2.circlepath", text: "Downloading \(Int(p * 100))%") {}
        case .ready(let r, _):
            pill(symbol: "arrow.clockwise.circle.fill", text: "Restart to update to \(r.version)") { updater.installAndRelaunch() }
        case .installing:
            pill(symbol: "arrow.triangle.2.circlepath", text: "Installing") {}
        case .failed(let message) where !message.isEmpty && updater.lastChecked != nil && isActionable(message):
            pill(symbol: "exclamationmark.triangle", text: "Update failed") { Workspace.shared.showToast(message) }
        default:
            EmptyView()
        }
    }

    private func isActionable(_ m: String) -> Bool { m.contains("Move Panels") || m.contains("cannot replace") || m.contains("valid") }

    private func pill(symbol: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(text).font(Typo.ui(12, bold: true))
            }
            .foregroundStyle(theme.isDark ? Color.black.opacity(0.85) : Color.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(theme.accentC))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

// MARK: - Settings section

struct UpdateSettingsSection: View {
    @Environment(\.theme) private var theme
    private let updater = Updater.shared

    var body: some View {
        @Bindable var u = updater
        SettingsSection(title: "Updates") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Panels \(updater.currentVersion)")
                        .font(Typo.ui(13, bold: true))
                        .foregroundStyle(theme.textC)
                    Text(updater.statusLine)
                        .font(Typo.ui(11.5))
                        .foregroundStyle(theme.mutedC)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if case .ready = updater.state {
                    Button("Restart and Update") { updater.installAndRelaunch() }
                } else {
                    Button("Check Now") { updater.check(userInitiated: true) }
                        .disabled(updater.isBusy)
                }
            }
            ToggleRow(label: "Download updates automatically", isOn: $u.autoDownload)
        }
    }
}
