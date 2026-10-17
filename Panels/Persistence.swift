import Foundation
import AppKit

struct WorkspaceSnapshot: Codable {
    static let currentVersion = 1
    var schemaVersion: Int? = WorkspaceSnapshot.currentVersion
    var spaces: [Space]
    var active: UUID
    var popouts: [Popout]?
}

enum Persistence {
    private static var dirty = false
    private static var timer: Timer?

    private static var fileURL: URL {
        let dir = AppPaths.dir
        return dir.appendingPathComponent("workspace.json")
    }

    static func markDirty() { dirty = true }

    static func startAutosave() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
            if dirty { saveNow() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { _ in saveNow() }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { _ in if dirty { saveNow() } }
    }

    /// Set when the last load found a workspace file it could not read. Shown once as a toast.
    static var loadNotice: String?

    static var backupsDir: URL {
        let d = AppPaths.dir.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func saveNow() {
        dirty = false
        let ws = Workspace.shared
        let snap = WorkspaceSnapshot(spaces: ws.spaces, active: ws.activeSpaceID, popouts: ws.popouts)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(snap) else { return }
        backupIfDue(file: fileURL, into: backupsDir)
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load() -> WorkspaceSnapshot? { load(from: fileURL) }

    /// Returns nil when there is no file. When the file exists but cannot be read, it is moved aside to
    /// workspace.corrupt-<time>.json (never overwritten) and `loadNotice` is set.
    static func load(from url: URL) -> WorkspaceSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let snap = try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data) { return snap }
        let stamp = stampFormatter.string(from: Date())
        let aside = url.deletingLastPathComponent().appendingPathComponent("workspace.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        loadNotice = "Workspace file could not be read. A copy was kept as \(aside.lastPathComponent)"
        return nil
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// Copies `file` into `dir` as workspace-<time>.json if the newest backup is older than `interval`.
    /// Keeps the newest `keep` backups. Returns true when a backup was written.
    @discardableResult
    static func backupIfDue(file: URL, into dir: URL, interval: TimeInterval = 600, keep: Int = 20, now: Date = Date()) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return false }
        let existing = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("workspace-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let newest = existing.last,
           let date = (try? newest.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           now.timeIntervalSince(date) < interval { return false }
        let dest = dir.appendingPathComponent("workspace-\(stampFormatter.string(from: now)).json")
        guard (try? fm.copyItem(at: file, to: dest)) != nil else { return false }
        let all = existing + [dest]
        for old in all.dropLast(keep) { try? fm.removeItem(at: old) }
        return true
    }
}
