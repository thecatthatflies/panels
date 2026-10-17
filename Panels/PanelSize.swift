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

    /// Smallest size each panel kind should be given by layout code.
    static func minimum(for kind: PanelKind) -> CGSize {
        switch kind {
        case .note, .tasks: CGSize(width: 160, height: 110)
        case .terminal: CGSize(width: 200, height: 110)
        case .web: CGSize(width: 200, height: 130)
        case .timer: CGSize(width: 150, height: 90)
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
    @State private var dims = CGSize(width: 400, height: 300)
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { dims = $0 }
            .environment(\.panelDims, dims)
            .environment(\.panelSize, PanelSize.classify(dims))
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
