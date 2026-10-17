import SwiftUI

/// How a workspace arranges its panels by itself. A workspace with no layout (nil) is fully manual.
enum TileLayout: String, Codable, CaseIterable, Identifiable {
    case balanced, main, columns, rows, spiral

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced: return "Balanced"
        case .main: return "Main and Stack"
        case .columns: return "Columns"
        case .rows: return "Rows"
        case .spiral: return "Spiral"
        }
    }

    var symbol: String {
        switch self {
        case .balanced: return "square.grid.2x2"
        case .main: return "rectangle.lefthalf.inset.filled"
        case .columns: return "rectangle.split.3x1"
        case .rows: return "rectangle.split.1x2"
        case .spiral: return "rectangle.split.2x2"
        }
    }

    var blurb: String {
        switch self {
        case .balanced: return "An even grid that fits the window"
        case .main: return "One big panel, the rest stacked beside it"
        case .columns: return "Everything side by side"
        case .rows: return "Everything stacked"
        case .spiral: return "Each panel takes half of what is left"
        }
    }
}

/// Builds a layout tree from an ordered list of panels. Pure: no model state, so it is easy to test.
enum TileEngine {
    /// Rows of a balanced grid as item counts per row, for example [3, 3] or [2, 2, 1].
    /// Picks the grid whose cells stay closest to comfortable proportions and above each panel's minimum size,
    /// so a wide window gets columns and a tall one gets rows, and six panels never become six thin strips.
    static func gridRows(count n: Int, size: CGSize, gap: CGFloat, minimum: CGSize) -> [Int] {
        guard n > 1 else { return [max(n, 0)] }
        var best: (rows: [Int], score: Double)?
        for cols in 1...n {
            let rowCount = (n + cols - 1) / cols
            var counts = Array(repeating: cols, count: rowCount)
            counts[rowCount - 1] = n - cols * (rowCount - 1)
            // The widest cells are in the shortest row, the tightest in the fullest.
            let cellW = (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH = (size.height - gap * CGFloat(rowCount - 1)) / CGFloat(rowCount)
            guard cellW > 0, cellH > 0 else { continue }
            let fit = min(Double(cellW / max(minimum.width, 1)), Double(cellH / max(minimum.height, 1)))
            let ratio = Double(cellW / cellH)
            // A grid that keeps every cell at its minimum always beats one that does not.
            var score = (fit >= 0.999 ? 10.0 : 0.0) + min(fit, 1.3)   // roomy beyond comfortable is not worth more
            score -= abs(log(ratio / 1.4)) * 0.5
            // Prefer fuller grids: an empty-looking last row is a small cost.
            score -= Double(cols * rowCount - n) * 0.04
            if best == nil || score > best!.score + 0.0001 { best = (counts, score) }
        }
        return best?.rows ?? [n]
    }

    /// A short string that changes only when the arrangement itself would change (not on every pixel of resize).
    static func signature(layout: TileLayout, count: Int, size: CGSize, gap: CGFloat, minimum: CGSize) -> String {
        switch layout {
        case .balanced: return "b" + gridRows(count: count, size: size, gap: gap, minimum: minimum).map(String.init).joined(separator: ",")
        case .main, .spiral: return layout.rawValue + (size.width >= size.height ? "w" : "t")
        case .columns, .rows: return layout.rawValue
        }
    }

    /// Smallest layout area that keeps every cell at its minimum, for the most compact arrangement of this layout.
    /// It depends only on the panels and `limit` (the biggest area available), never on the current window size,
    /// so it can drive the window's minimum size without feeding back on itself.
    static func requiredSize(layout: TileLayout, panels: [Panel], gap: CGFloat, limit: CGSize) -> CGSize {
        let n = panels.count
        let min = minimum(for: panels)
        guard n > 1 else { return n == 1 ? PanelSize.minimum(for: panels[0].kind) : .zero }
        if layout == .balanced {
            var best: (size: CGSize, fits: Bool, cost: CGFloat)?
            for cols in 1...n {
                let rows = (n + cols - 1) / cols
                let size = CGSize(width: CGFloat(cols) * min.width + gap * CGFloat(cols - 1),
                                  height: CGFloat(rows) * min.height + gap * CGFloat(rows - 1))
                let fits = size.width <= limit.width + 0.5 && size.height <= limit.height + 0.5
                // Smallest area, but not at the price of a strip: odd shapes cost extra.
                let cost = size.width * size.height * (1 + 0.6 * abs(CGFloat(log(Double(size.width / size.height) / 1.5))))
                if let b = best {
                    if (fits && !b.fits) || (fits == b.fits && cost < b.cost) { best = (size, fits, cost) }
                } else { best = (size, fits, cost) }
            }
            return best!.size
        }
        let root = build(panels: panels, layout: layout, size: limit, gap: gap)
        return CGSize(width: root.minExtent(along: .horizontal, gap: gap), height: root.minExtent(along: .vertical, gap: gap))
    }

    static func minimum(for panels: [Panel]) -> CGSize {
        var m = CGSize.zero
        for p in panels {
            let k = PanelSize.minimum(for: p.kind)
            m.width = max(m.width, k.width)
            m.height = max(m.height, k.height)
        }
        return m
    }

    static func build(panels: [Panel], layout: TileLayout, size: CGSize, gap: CGFloat) -> Node {
        guard !panels.isEmpty else { return Node.empty() }
        if panels.count == 1 { return Node(panel: panels[0]) }
        let leaves = panels.map { Node(panel: $0) }
        let wide = size.width >= size.height
        switch layout {
        case .columns:
            return Node(axis: .horizontal, children: leaves)
        case .rows:
            return Node(axis: .vertical, children: leaves)
        case .balanced:
            let counts = gridRows(count: panels.count, size: size, gap: gap, minimum: minimum(for: panels))
            var i = 0
            let rows: [Node] = counts.map { c in
                let slice = Array(leaves[i..<(i + c)])
                i += c
                return slice.count == 1 ? slice[0] : Node(axis: .horizontal, children: slice)
            }
            return rows.count == 1 ? rows[0] : Node(axis: .vertical, children: rows)
        case .main:
            let rest = Array(leaves.dropFirst())
            let stack = rest.count == 1 ? rest[0] : Node(axis: wide ? .vertical : .horizontal, children: rest)
            return Node(axis: wide ? .horizontal : .vertical, children: [leaves[0], stack], weights: [1.35, 1])
        case .spiral:
            func dwindle(_ items: ArraySlice<Node>, horizontal: Bool) -> Node {
                guard let first = items.first else { return Node.empty() }
                if items.count == 1 { return first }
                let rest = dwindle(items.dropFirst(), horizontal: !horizontal)
                return Node(axis: horizontal ? .horizontal : .vertical, children: [first, rest])
            }
            return dwindle(leaves[...], horizontal: wide)
        }
    }
}

// MARK: - Workspace operations

extension Workspace {
    /// Turns auto tiling on with a layout (or off with nil) and arranges the current panels.
    func setTiling(_ layout: TileLayout?) {
        let s = space
        s.tiling = layout
        if layout == nil {
            showToast("Auto tiling off")
        } else {
            s.zoomedID = nil
            retile(force: true)
            showToast(layout!.label)
        }
        Persistence.markDirty()
    }

    /// Rearranges the panels of the active workspace by its layout. Without `force` it only acts when the
    /// arrangement would actually differ (used on window resize so divider drags are not undone needlessly).
    func retile(force: Bool = false) {
        retile(space, force: force)
    }

    func retile(_ s: Space, force: Bool = false) {
        guard let layout = s.tiling else { return }
        let panels = s.panels
        let gap = CGFloat(Appearance.shared.gap)
        let area = layoutArea(contentSize)
        let sig = TileEngine.signature(layout: layout, count: panels.count, size: area, gap: gap,
                                       minimum: TileEngine.minimum(for: panels))
        guard force || sig != s.tileSignature else { return }
        let root = TileEngine.build(panels: panels, layout: layout, size: area, gap: gap)
        root.normalize()
        withAnimation(Motion.layout) { s.root = root }
        s.tileSignature = sig
        Persistence.markDirty()
    }

    /// Called when the window's content area changes size.
    func contentSizeChanged(_ size: CGSize) {
        guard size.width > 50, size.height > 50, abs(size.width - contentSize.width) > 1 || abs(size.height - contentSize.height) > 1 else { return }
        contentSize = size
        if space.tiling != nil { retile() }
    }

    private func neighbor(_ dir: Direction) -> Panel? {
        guard let cur = focused, let from = frames[cur.id] else { return nil }
        let c0 = CGPoint(x: from.midX, y: from.midY)
        var best: (Panel, CGFloat)?
        for p in space.panels where p.id != cur.id {
            guard let f = frames[p.id] else { continue }
            let c1 = CGPoint(x: f.midX, y: f.midY)
            let along: CGFloat, across: CGFloat
            switch dir {
            case .left:  along = c0.x - c1.x; across = abs(c0.y - c1.y)
            case .right: along = c1.x - c0.x; across = abs(c0.y - c1.y)
            case .up:    along = c0.y - c1.y; across = abs(c0.x - c1.x)
            case .down:  along = c1.y - c0.y; across = abs(c0.x - c1.x)
            }
            if along <= 1 { continue }
            let score = along + across * 2
            if best == nil || score < best!.1 { best = (p, score) }
        }
        return best?.0
    }

    /// Swaps the focused panel with its neighbour in a direction. The focus follows the panel.
    func swapFocused(_ dir: Direction) {
        guard let cur = focused, let other = neighbor(dir) else { return }
        move(cur.id, onto: other.id, zone: .center)
    }

    /// Grows or shrinks the focused panel along an axis by moving the divider between it and a sibling.
    /// Works on drawn pixel sizes and stops at each side's real minimum.
    func resizeFocused(_ axis: SplitAxis, grow: Bool) {
        let s = space
        guard let cur = focused, let leaf = s.root.leaf(for: cur.id) else { return }
        let gap = CGFloat(Appearance.shared.gap)
        var node = leaf
        while let (parent, i) = s.root.parent(of: node) {
            if parent.axis == axis, parent.children.count > 1 {
                // extent this split gets along the axis: the layout area narrowed by every same axis ancestor
                let area = layoutArea(contentSize)
                var total = axis == .horizontal ? area.width : area.height
                var up: Node = parent
                while let (gp, gi) = s.root.parent(of: up) {
                    if gp.axis == axis {
                        let sumW = max(gp.weights.reduce(0, +), 0.0001)
                        total = max(total - gap * CGFloat(gp.children.count - 1), 1) * CGFloat(gp.weights[gi] / sumW)
                    }
                    up = gp
                }
                let n = parent.children.count
                total = max(total - gap * CGFloat(n - 1), 1)
                let mins = parent.children.map { $0.minExtent(along: axis, gap: gap) }
                let sizes = SplitFit.sizes(weights: parent.weights, mins: mins, total: total)
                let j = i + 1 < n ? i + 1 : i - 1
                let lo = min(i, j)
                let step = total / CGFloat(n) * 0.12 * (grow ? 1 : -1)
                // dragging the divider right grows the left child; if the focused one is on the right, flip
                let translation = (i == lo) ? step : -step
                let moved = SplitFit.drag(sizes: sizes, index: lo, translation: translation, minLeft: mins[lo], minRight: mins[lo + 1])
                guard moved != sizes else { return }
                let oldSum = parent.weights.reduce(0, +)
                let newSum = max(moved.reduce(0, +), 1)
                withAnimation(Motion.quick) {
                    for k in 0..<n { parent.weights[k] = Double(moved[k] / newSum) * oldSum }
                }
                Persistence.markDirty()
                return
            }
            node = parent
        }
    }
}

// MARK: - Hard minimums

extension Workspace {
    private var sidePad: CGFloat { CGFloat(Appearance.shared.gap) + 2 }

    /// The area panels actually get inside a content size (the workspace view adds side and bottom padding).
    func layoutArea(_ content: CGSize) -> CGSize {
        CGSize(width: max(content.width - sidePad * 2, 1), height: max(content.height - sidePad, 1))
    }

    /// Largest content area this Mac can show, or a test override.
    var maxContentSize: CGSize {
        if let o = maxContentOverride { return o }
        let screen = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: screen.width, height: screen.height - WindowChrome.barHeight)
    }

    /// Content size (below the top bar) a workspace needs so no panel drops under its minimum.
    /// With auto tiling this is the arrangement chosen for `layoutSize`; otherwise it is the current tree.
    func requiredContentSize(for s: Space) -> CGSize {
        let gap = CGFloat(Appearance.shared.gap)
        let need: CGSize
        if let layout = s.tiling, !s.panels.isEmpty {
            need = TileEngine.requiredSize(layout: layout, panels: s.panels, gap: gap, limit: layoutArea(maxContentSize))
        } else {
            need = CGSize(width: s.root.minExtent(along: .horizontal, gap: gap), height: s.root.minExtent(along: .vertical, gap: gap))
        }
        return CGSize(width: need.width + sidePad * 2, height: need.height + sidePad)
    }

    /// Whether the workspace, as arranged for the biggest window this Mac allows, keeps every panel at its minimum.
    func fits(_ s: Space) -> Bool {
        let need = requiredContentSize(for: s)
        let have = maxContentSize
        return need.width <= have.width + 0.5 && need.height <= have.height + 0.5
    }

    /// Takes a just added panel back out, without touching the undo stack.
    func removeWithoutUndo(_ id: UUID, from s: Space) {
        if let leaf = s.root.leaf(for: id) {
            if s.root === leaf {
                s.root = Node.empty()
            } else if let (parent, i) = s.root.parent(of: leaf) {
                parent.children.remove(at: i)
                parent.weights.remove(at: i)
                s.root.normalize()
            }
        }
        Runtime.shared.release(id)
        retile(s, force: true)
        if s.focusedID == id { s.focusedID = s.panels.first?.id }
    }

    func showNoRoom() {
        showToast("No room for another panel. Close one or open a new workspace.")
    }
}
