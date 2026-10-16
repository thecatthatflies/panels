import Foundation
import AppKit

struct WorkspaceSnapshot: Codable {
    var spaces: [Space]
    var active: UUID
    var popouts: [Popout]?
}

enum Persistence {
    private static var dirty = false
    private static var timer: Timer?

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Panels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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

    static func saveNow() {
        dirty = false
        let ws = Workspace.shared
        let snap = WorkspaceSnapshot(spaces: ws.spaces, active: ws.activeSpaceID, popouts: ws.popouts)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(snap) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load() -> WorkspaceSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
    }
}
