import Foundation

enum AppPaths {
    /// Where Panels keeps its JSON data. PANELS_DATA_DIR overrides it, which the self test uses so it never touches real data.
    static var dir: URL {
        let url: URL
        if let override = ProcessInfo.processInfo.environment["PANELS_DATA_DIR"], !override.isEmpty {
            url = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            url = base.appendingPathComponent("Panels", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
