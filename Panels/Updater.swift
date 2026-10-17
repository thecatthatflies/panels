import SwiftUI
import AppKit
import Observation

/// Where releases are published. Every push to `main` runs the release workflow, which
/// creates a GitHub release containing Panels.dmg. The app polls the latest release, downloads the
/// disk image and copies the app out of it. A Panels.zip asset (older releases) still works.
enum UpdateConfig {
    static let owner = "thecatthatflies"
    static let repo = "panels"
    /// Asset names in order of preference, then any file with one of `assetExtensions`.
    static let assetNames = ["Panels.dmg", "Panels.zip"]
    static let assetExtensions = ["dmg", "zip"]
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

/// App Translocation: macOS runs a quarantined app that the user never moved from a random read-only
/// path. The Security functions that detect it and find the original are not in the public headers,
/// so they are looked up at run time, with a path check as the fallback.
enum Translocation {
    private typealias IsTranslocatedFn = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutableRawPointer?) -> UInt8
    private typealias OriginalPathFn = @convention(c) (CFURL, UnsafeMutableRawPointer?) -> Unmanaged<CFURL>?

    private static let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        guard let security, let sym = dlsym(security, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    static func isTranslocated(_ url: URL) -> Bool {
        if url.path.contains("/AppTranslocation/") { return true }
        guard let fn = symbol("SecTranslocateIsTranslocatedURL", as: IsTranslocatedFn.self) else { return false }
        var result = false
        return fn(url as CFURL, &result, nil) != 0 && result
    }

    static func originalURL(_ url: URL) -> URL? {
        guard let fn = symbol("SecTranslocateCreateOriginalPathForURL", as: OriginalPathFn.self),
              let original = fn(url as CFURL, nil)?.takeRetainedValue() as URL? else { return nil }
        return original.path.contains("/AppTranslocation/") ? nil : original
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
        func name(_ a: [String: Any]) -> String { a["name"] as? String ?? "" }
        let named = UpdateConfig.assetNames.lazy.compactMap { n in assets.first { name($0) == n } }.first
        let typed = UpdateConfig.assetExtensions.lazy.compactMap { ext in
            assets.first { (name($0) as NSString).pathExtension.lowercased() == ext }
        }.first
        guard let asset = named ?? typed,
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
        // A missing file still "downloads" (as an error page), so check the status first.
        if let problem = Self.downloadProblem(status: (downloadTask.response as? HTTPURLResponse)?.statusCode) {
            state = .failed(problem)
            return
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("PanelsUpdate-\(UUID().uuidString)", isDirectory: true)
        let ext = release.assetURL.pathExtension.lowercased() == "zip" ? "zip" : "dmg"
        let archive = work.appendingPathComponent("update.\(ext)")
        let out = work.appendingPathComponent("unpacked", isDirectory: true)
        do {
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            try fm.moveItem(at: location, to: archive)
        } catch {
            state = .failed("Could not save the update. Make sure your disk has room and try again.")
            return
        }

        // Unpack off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let app = Self.unpack(archive, into: out)
            DispatchQueue.main.async {
                guard let app, self.isValidBundle(app) else {
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

    /// Gets the app out of a downloaded .dmg or .zip into `out`. Blocks; call it off the main thread.
    static func unpack(_ archive: URL, into out: URL) -> URL? {
        let fm = FileManager.default
        func run(_ tool: String, _ args: [String]) -> Bool {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }
        func firstApp(in dir: URL) -> URL? {
            (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.first { $0.pathExtension == "app" }
        }
        if archive.pathExtension.lowercased() == "zip" {
            return run("/usr/bin/ditto", ["-x", "-k", archive.path, out.path]) ? firstApp(in: out) : nil
        }
        // Disk image: mount it out of sight, copy the app out, unmount.
        let mount = archive.deletingLastPathComponent().appendingPathComponent("mount", isDirectory: true)
        try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-noverify",
                                        "-mountpoint", mount.path, archive.path]) else { return nil }
        defer {
            if !run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) {
                _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"])
            }
        }
        guard let src = firstApp(in: mount) else { return nil }
        let dest = out.appendingPathComponent(src.lastPathComponent)
        return run("/usr/bin/ditto", [src.path, dest.path]) ? dest : nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, task is URLSessionDownloadTask {
            state = .failed("Could not download the update. Check your internet connection and try again.")
        }
    }

    /// nil when the download answered normally. Local test feeds have no status code.
    static func downloadProblem(status: Int?) -> String? {
        guard let status, status != 200 else { return nil }
        if status == 404 { return "The update file is not on the download page yet. Try again later." }
        if status == 403 || status == 429 { return "The download page is busy right now. Try again in a few minutes." }
        return "Could not download the update. Try again later."
    }

    private func isValidBundle(_ url: URL) -> Bool {
        guard let b = Bundle(url: url), b.bundleIdentifier == Bundle.main.bundleIdentifier else { return false }
        let exec = b.executableURL?.path ?? ""
        return FileManager.default.isExecutableFile(atPath: exec)
    }

    // MARK: install

    /// Explains why this copy cannot update itself, or nil when it can.
    var installBlocker: String? {
        Self.installBlocker(running: Bundle.main.bundleURL, target: Self.installTarget(running: Bundle.main.bundleURL))
    }

    /// The bundle the update replaces. macOS runs a quarantined app that was never moved (for example
    /// one opened straight from Downloads) from a temporary read-only copy ("App Translocation"), so
    /// the update has to go to the original copy instead. nil when that original cannot be found.
    static func installTarget(running: URL,
                              translocated: (URL) -> Bool = Translocation.isTranslocated,
                              original: (URL) -> URL? = Translocation.originalURL) -> URL? {
        guard translocated(running) else { return running }
        return original(running)
    }

    static func installBlocker(running: URL, target: URL?,
                               canWrite: (String) -> Bool = { FileManager.default.isWritableFile(atPath: $0) }) -> String? {
        guard let target else {
            return "macOS opened Panels from a temporary read-only copy, so it cannot update itself. Drag Panels into Applications, open it from there, and try again."
        }
        let path = target.path
        if path.contains("/DerivedData/") || path.contains("/Build/Products/") {
            return "This copy is running from a build folder. Move Panels to Applications to enable updating."
        }
        if path.hasPrefix("/Volumes/") {
            return "Panels is running from the disk image. Drag it into Applications, open it from there, and try again."
        }
        let parent = target.deletingLastPathComponent()
        if !canWrite(parent.path) {
            return "Panels cannot replace itself in the \(parent.lastPathComponent) folder. Move Panels to Applications and try again."
        }
        return nil
    }

    /// Swaps `dest` for `new`, keeping the old copy next to it until the relaunch. Rolls back on failure.
    /// Returns where the old copy went.
    @discardableResult
    static func replaceBundle(at dest: URL, with new: URL) throws -> URL {
        let fm = FileManager.default
        let backup = dest.deletingLastPathComponent().appendingPathComponent(dest.lastPathComponent + ".previous")
        try? fm.removeItem(at: backup)
        try fm.moveItem(at: dest, to: backup)
        do {
            try fm.moveItem(at: new, to: dest)
        } catch {
            try? fm.removeItem(at: dest)
            try? fm.moveItem(at: backup, to: dest)
            throw error
        }
        // A quarantined copy would be translocated again on the next launch.
        removexattr(dest.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        if let items = fm.enumerator(atPath: dest.path) {
            for case let sub as String in items {
                removexattr(dest.appendingPathComponent(sub).path, "com.apple.quarantine", XATTR_NOFOLLOW)
            }
        }
        return backup
    }

    func installAndRelaunch() {
        guard case .ready(_, let newApp) = state else { return }
        let running = Bundle.main.bundleURL
        let target = Self.installTarget(running: running)
        if let blocker = Self.installBlocker(running: running, target: target) {
            state = .failed(blocker)
            return
        }
        guard let target else { return }
        state = .installing
        Persistence.saveNow()

        // Swap the files here, while the app can still say what went wrong. The running code stays
        // mapped, so moving the bundle under it is safe for the moment before quitting.
        let backup: URL
        do {
            backup = try Self.replaceBundle(at: target, with: newApp)
        } catch {
            state = .failed("Could not replace Panels in the \(target.deletingLastPathComponent().lastPathComponent) folder. Move Panels to Applications and try again.")
            return
        }

        let script = """
        #!/bin/bash
        PID="$1"; DEST="$2"; BACKUP="$3"; WORK="$4"
        for i in $(seq 1 100); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        open "$DEST"
        rm -rf "$BACKUP" "$WORK"
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("panels-update-\(UUID().uuidString).sh")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [scriptURL.path, String(ProcessInfo.processInfo.processIdentifier), target.path, backup.path,
                       newApp.deletingLastPathComponent().deletingLastPathComponent().path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try p.run()
        } catch {
            // The new version is already in place; it only needs a manual restart.
            state = .failed("Panels was updated. Quit Panels and open it again to finish.")
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
        case .failed(let message) where !message.isEmpty && updater.lastChecked != nil:
            pill(symbol: "exclamationmark.triangle", text: "Update failed") { Workspace.shared.showToast(message) }
        default:
            EmptyView()
        }
    }

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
