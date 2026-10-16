import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Node renderer

struct NodeView: View {
    let node: Node

    var body: some View {
        if let panel = node.panel {
            PanelView(panel: panel)
                .id(panel.id)
        } else if node.children.isEmpty {
            EmptySpaceView()
        } else {
            SplitContainer(node: node)
        }
    }
}

// MARK: - Empty space

struct EmptySpaceView: View {
    @Environment(\.theme) private var theme
    private let ws = Workspace.shared

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "square.dashed")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(theme.faintC)
            VStack(spacing: 6) {
                Text("Nothing here yet")
                    .font(Typo.ui(17, bold: true))
                    .foregroundStyle(theme.textC)
                Text("Add a panel to start, or pick a layout.")
                    .font(Typo.ui(13))
                    .foregroundStyle(theme.mutedC)
            }
            HStack(spacing: 8) {
                ForEach([PanelKind.note, .terminal, .web, .tasks], id: \.self) { kind in
                    Button { ws.addPanel(kind) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: kind.symbol).font(.system(size: 12, weight: .medium))
                            Text(kind.label).font(Typo.ui(12.5, bold: true))
                        }
                        .foregroundStyle(theme.textC)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(theme.hover))
                        .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Split container with draggable dividers

struct SplitContainer: View {
    @Bindable var node: Node
    @Environment(\.theme) private var theme
    private let appearance = Appearance.shared

    @State private var startWeights: [Double]?
    @State private var activeDivider: Int?

    private let minHorizontal: CGFloat = 190
    private let minVertical: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let horizontal = node.axis == .horizontal
            let gap = CGFloat(appearance.gap)
            let count = node.children.count
            let extent = horizontal ? geo.size.width : geo.size.height
            let total = max(extent - gap * CGFloat(max(count - 1, 0)), 1)
            let weights = safeWeights()
            let sum = max(weights.reduce(0, +), 0.0001)
            let sizes = weights.map { total * CGFloat($0 / sum) }
            let offsets = offsets(for: sizes, gap: gap)

            ZStack(alignment: .topLeading) {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { i, child in
                    NodeView(node: child)
                        .frame(width: horizontal ? sizes[i] : geo.size.width,
                               height: horizontal ? geo.size.height : sizes[i])
                        .offset(x: horizontal ? offsets[i] : 0, y: horizontal ? 0 : offsets[i])
                }

                ForEach(0..<max(count - 1, 0), id: \.self) { i in
                    DividerHandle(horizontal: horizontal,
                                  gap: gap,
                                  length: horizontal ? geo.size.height : geo.size.width,
                                  active: activeDivider == i)
                        .offset(x: horizontal ? offsets[i] + sizes[i] - 4 : 0,
                                y: horizontal ? 0 : offsets[i] + sizes[i] - 4)
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { value in
                                    drag(index: i, translation: horizontal ? value.translation.width : value.translation.height,
                                         total: total, horizontal: horizontal)
                                }
                                .onEnded { _ in
                                    startWeights = nil
                                    activeDivider = nil
                                    Persistence.markDirty()
                                }
                        )
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded { balance(index: i) }
                        )
                }
            }
        }
    }

    private func safeWeights() -> [Double] {
        if node.weights.count == node.children.count { return node.weights.map { max($0, 0.0001) } }
        return Array(repeating: 1, count: node.children.count)
    }

    private func offsets(for sizes: [CGFloat], gap: CGFloat) -> [CGFloat] {
        var out: [CGFloat] = []
        var cursor: CGFloat = 0
        for s in sizes {
            out.append(cursor)
            cursor += s + gap
        }
        return out
    }

    private func drag(index i: Int, translation: CGFloat, total: CGFloat, horizontal: Bool) {
        if startWeights == nil {
            startWeights = safeWeights()
            activeDivider = i
        }
        guard let start = startWeights, i + 1 < start.count else { return }
        let sum = start.reduce(0, +)
        let unit = sum / Double(total)                       // weight per pixel
        let minPx = Double(horizontal ? minHorizontal : minVertical)
        let leftPx = start[i] / unit
        let rightPx = start[i + 1] / unit
        var lo = -(leftPx - minPx)
        var hi = rightPx - minPx
        if lo > 0 { lo = 0 }
        if hi < 0 { hi = 0 }
        let delta = min(max(Double(translation), lo), hi)
        var w = start
        w[i] = start[i] + delta * unit
        w[i + 1] = start[i + 1] - delta * unit
        node.weights = w
    }

    private func balance(index i: Int) {
        guard i + 1 < node.weights.count else { return }
        var w = node.weights
        let avg = (w[i] + w[i + 1]) / 2
        w[i] = avg
        w[i + 1] = avg
        withAnimation(.snappy(duration: 0.3)) { node.weights = w }
        Persistence.markDirty()
    }
}

struct DividerHandle: View {
    @Environment(\.theme) private var theme
    let horizontal: Bool
    let gap: CGFloat
    let length: CGFloat
    let active: Bool
    @State private var hover = false

    var body: some View {
        let hit = gap + 8
        let lit = hover || active
        ZStack {
            Capsule()
                .fill(active ? theme.accentC : theme.hairlineStrong)
                .frame(width: horizontal ? 3 : (lit ? 56 : 0),
                       height: horizontal ? (lit ? 56 : 0) : 3)
                .opacity(lit ? 1 : 0)
        }
        .frame(width: horizontal ? hit : length, height: horizontal ? length : hit)
        .contentShape(Rectangle())
        .pointerStyle(horizontal ? .columnResize : .rowResize)
        .onHover { h in
            withAnimation(.snappy(duration: 0.18)) { hover = h }
        }
        .animation(.snappy(duration: 0.18), value: active)
    }
}

// MARK: - Drag and drop of panels

enum PanelDrag {
    static var timer: Timer?

    static func begin(_ id: UUID) {
        let ws = Workspace.shared
        ws.draggingID = id
        Runtime.shared.setDragging(true)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { t in
            if NSEvent.pressedMouseButtons == 0 {
                t.invalidate()
                end()
            }
        }
    }

    static func end() {
        timer?.invalidate()
        timer = nil
        let ws = Workspace.shared
        guard ws.draggingID != nil else { return }
        ws.draggingID = nil
        Runtime.shared.setDragging(false)
    }
}

struct PanelDropDelegate: DropDelegate {
    let panelID: UUID
    @Binding var zone: DropZone?
    let size: CGSize

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragging = Workspace.shared.draggingID else { return false }
        return dragging != panelID
    }

    func dropEntered(info: DropInfo) { zone = Self.zone(at: info.location, in: size) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let z = Self.zone(at: info.location, in: size)
        if z != zone { withAnimation(.snappy(duration: 0.16)) { zone = z } }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { withAnimation(.snappy(duration: 0.16)) { zone = nil } }

    func performDrop(info: DropInfo) -> Bool {
        let z = Self.zone(at: info.location, in: size)
        guard let source = Workspace.shared.draggingID else { return false }
        zone = nil
        PanelDrag.end()
        Workspace.shared.move(source, onto: panelID, zone: z)
        return true
    }

    static func zone(at p: CGPoint, in size: CGSize) -> DropZone {
        guard size.width > 0, size.height > 0 else { return .center }
        let nx = p.x / size.width
        let ny = p.y / size.height
        let dl = nx, dr = 1 - nx, dt = ny, db = 1 - ny
        let m = min(dl, dr, dt, db)
        if m > 0.27 { return .center }
        if m == dl { return .left }
        if m == dr { return .right }
        if m == dt { return .top }
        return .bottom
    }
}

struct DropZoneOverlay: View {
    @Environment(\.theme) private var theme
    let zone: DropZone
    let accent: Color
    let radius: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let rect: CGRect = {
                switch zone {
                case .left: return CGRect(x: 0, y: 0, width: w / 2, height: h)
                case .right: return CGRect(x: w / 2, y: 0, width: w / 2, height: h)
                case .top: return CGRect(x: 0, y: 0, width: w, height: h / 2)
                case .bottom: return CGRect(x: 0, y: h / 2, width: w, height: h / 2)
                case .center: return CGRect(x: 0, y: 0, width: w, height: h)
                }
            }()
            RoundedRectangle(cornerRadius: max(radius - 4, 6), style: .continuous)
                .fill(accent.opacity(0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: max(radius - 4, 6), style: .continuous)
                        .strokeBorder(accent.opacity(0.9), lineWidth: 1.5)
                )
                .overlay {
                    if zone == .center {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 18, weight: .medium))
                            Text("Swap").font(Typo.ui(12, bold: true))
                        }
                        .foregroundStyle(accent)
                    }
                }
                .frame(width: rect.width - 8, height: rect.height - 8)
                .position(x: rect.midX, y: rect.midY)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
