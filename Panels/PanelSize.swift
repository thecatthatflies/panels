import SwiftUI

/// How much room a panel has. Computed from the rendered size of the whole panel (header included)
/// and passed down so headers and bodies can drop detail instead of clipping.
enum PanelSize: Int, Comparable {
    case tiny, small, regular, roomy

    static func < (a: PanelSize, b: PanelSize) -> Bool { a.rawValue < b.rawValue }

    static func classify(_ s: CGSize) -> PanelSize {
        if s.height < 110 || s.width < 150 { return .tiny }
        if s.height < 170 || s.width < 260 { return .small }
        if min(s.width, s.height) < 360 { return .regular }
        return .roomy
    }

    /// Hard minimum for each panel kind. Layout never goes below it: the window grows to fit, and adding a panel
    /// that cannot fit on screen is refused.
    static func minimum(for kind: PanelKind) -> CGSize {
        switch kind {
        case .note: CGSize(width: 440, height: 320)
        case .tasks: CGSize(width: 340, height: 280)
        case .terminal: CGSize(width: 480, height: 280)
        case .web: CGSize(width: 520, height: 360)
        case .timer: CGSize(width: 300, height: 220)
        }
    }
}

private struct PanelSizeKey: EnvironmentKey { static let defaultValue = PanelSize.regular }
private struct PanelDimsKey: EnvironmentKey { static let defaultValue = CGSize(width: 400, height: 300) }

extension EnvironmentValues {
    var panelSize: PanelSize {
        get { self[PanelSizeKey.self] }
        set { self[PanelSizeKey.self] = newValue }
    }
    var panelDims: CGSize {
        get { self[PanelDimsKey.self] }
        set { self[PanelDimsKey.self] = newValue }
    }
}

private struct PanelSizeReader: ViewModifier {
    /// Reads the size the parent gives this view (not the size of its content), then forces the content into
    /// exactly that size. Without this, content with a wide minimum overflows its slot, gets centered and
    /// clipped, and the size class is computed from the overflowing width instead of the real slot.
    func body(content: Content) -> some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .environment(\.panelDims, geo.size)
                .environment(\.panelSize, PanelSize.classify(geo.size))
        }
    }
}

extension View {
    /// Measure this view and publish `\.panelSize` and `\.panelDims` to everything inside it.
    func measuresPanelSize() -> some View { modifier(PanelSizeReader()) }
}

extension Node {
    /// Smallest extent this subtree needs along `axis`, so layout code can keep every panel usable.
    func minExtent(along axis: SplitAxis, gap: CGFloat) -> CGFloat {
        if let panel {
            let m = PanelSize.minimum(for: panel.kind)
            return axis == .horizontal ? m.width : m.height
        }
        let parts = children.map { $0.minExtent(along: axis, gap: gap) }
        if self.axis == axis { return parts.reduce(0, +) + gap * CGFloat(max(parts.count - 1, 0)) }
        return parts.max() ?? 0
    }
}

enum SplitFit {
    /// New pixel sizes after dragging the divider between child `i` and `i + 1` by `translation`.
    /// Works on the sizes as drawn (not on raw weights, which can differ once minimums lift a child), so the
    /// divider follows the cursor exactly and stops when either side reaches its minimum.
    static func drag(sizes: [CGFloat], index i: Int, translation: CGFloat, minLeft: CGFloat, minRight: CGFloat) -> [CGFloat] {
        guard i >= 0, i + 1 < sizes.count else { return sizes }
        let lo = min(minLeft - sizes[i], 0)          // furthest the divider can move toward the left child
        let hi = max(sizes[i + 1] - minRight, 0)     // furthest toward the right child
        let delta = Swift.min(Swift.max(translation, lo), hi)
        var out = sizes
        out[i] += delta
        out[i + 1] -= delta
        return out
    }

    /// Turns weights into pixel sizes that add up to `total` while keeping each at or above its minimum.
    /// If the minimums cannot all fit, they are scaled down evenly (the best we can do without collapsing).
    static func sizes(weights: [Double], mins: [CGFloat], total: CGFloat) -> [CGFloat] {
        let sum = max(weights.reduce(0, +), 0.0001)
        var out = weights.map { total * CGFloat($0 / sum) }
        let minSum = mins.reduce(0, +)
        if minSum >= total {
            return mins.map { total * $0 / max(minSum, 1) }
        }
        var pinned = Array(repeating: false, count: out.count)
        for _ in 0..<out.count {
            var changed = false
            for i in out.indices where !pinned[i] && out[i] < mins[i] { out[i] = mins[i]; pinned[i] = true; changed = true }
            guard changed else { break }
            let fixed = out.indices.filter { pinned[$0] }.reduce(CGFloat(0)) { $0 + out[$1] }
            let freeIdx = out.indices.filter { !pinned[$0] }
            let freeWeight = freeIdx.reduce(0.0) { $0 + weights[$1] }
            guard freeWeight > 0 else { break }
            for i in freeIdx { out[i] = (total - fixed) * CGFloat(weights[i] / freeWeight) }
        }
        return out
    }
}
