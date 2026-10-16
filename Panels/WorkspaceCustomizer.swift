import SwiftUI

/// Popover for a workspace: name, icon grid, accent and theme.
struct WorkspaceCustomizer: View {
    @Bindable var space: Space
    @Environment(\.theme) private var theme

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: space.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.accent(space.tint))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.accent(space.tint).opacity(0.16)))
                    .contentTransition(.symbolEffect(.replace))
                TextField("Workspace name", text: $space.name)
                    .textFieldStyle(.plain)
                    .font(Typo.ui(15, bold: true))
                    .foregroundStyle(theme.textC)
            }

            VStack(alignment: .leading, spacing: 8) {
                label("Icon")
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(WorkspaceSymbols.all, id: \.self) { sym in
                            let on = space.symbol == sym
                            Button {
                                withAnimation(Motion.quick) { space.symbol = sym }
                                Sound.play(.tick)
                            } label: {
                                Image(systemName: sym)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(on ? theme.accent(space.tint) : theme.mutedC)
                                    .frame(width: 36, height: 36)
                                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(on ? theme.accent(space.tint).opacity(0.18) : theme.hover))
                                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(on ? theme.accent(space.tint).opacity(0.7) : .clear, lineWidth: 1))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .help(sym.replacingOccurrences(of: ".", with: " "))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 188)
            }

            VStack(alignment: .leading, spacing: 8) {
                label("Accent")
                AccentSwatches(selection: $space.tint)
            }

            VStack(alignment: .leading, spacing: 8) {
                label("Theme")
                themeChips
            }
        }
        .padding(18)
        .frame(width: 300)
        .background(theme.surfaceC)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typo.ui(10, bold: true))
            .tracking(0.9)
            .foregroundStyle(theme.faintC)
    }

    private var themeChips: some View {
        let all = Appearance.shared.allThemes
        return VStack(alignment: .leading, spacing: 6) {
            chip("Follow app", isOn: space.themeID == nil) { space.themeID = nil }
            FlowLayout(spacing: 6) {
                ForEach(all) { t in
                    chip(t.name, isOn: space.themeID == t.id, swatch: t) { space.themeID = t.id }
                }
            }
        }
    }

    private func chip(_ title: String, isOn: Bool, swatch: Theme? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let swatch {
                    Circle().fill(swatch.surfaceC).overlay(Circle().strokeBorder(swatch.accentC, lineWidth: 2))
                        .frame(width: 12, height: 12)
                }
                Text(title).font(Typo.ui(12, bold: isOn)).foregroundStyle(isOn ? theme.textC : theme.mutedC)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(isOn ? theme.accentC.opacity(0.18) : theme.hover))
            .overlay(Capsule().strokeBorder(isOn ? theme.accentC.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
