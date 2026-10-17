import Foundation

/// True while the self test or the snapshot tool runs the app. Those runs must be silent, invisible and must
/// never write the owner's preferences (they once played timer chimes, flashed the window and rewrote sound settings).
enum TestMode {
    static let active: Bool = {
        let e = ProcessInfo.processInfo.environment
        return e["PANELS_SELFTEST"] == "1" || e["PANELS_SNAPSHOTS"] != nil
    }()
}
