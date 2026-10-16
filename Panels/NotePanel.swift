import SwiftUI
import AppKit

// MARK: - Markdown block model

struct MDItem: Identifiable {
    let id: Int
    let indent: Int
    let marker: String
    let text: String
    let task: Bool?      // nil = not a task, false = open, true = done
    let line: Int
}

struct MDBlock: Identifiable {
    enum Kind {
        case heading(Int, String)
        case paragraph(String)
        case code(String, String)
        case quote([String])
        case list([MDItem])
        case rule
        case table([String], [[String]])
        case image(String, String)
    }
    let id: Int
    let kind: Kind
}

enum MarkdownParser {
    private static let heading = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.*?)\\s*#*\\s*$")
    private static let listItem = try! NSRegularExpression(pattern: "^(\\s*)([-*+]|\\d{1,3}[.)])\\s+(\\[([ xX])\\]\\s+)?(.*)$")
    private static let rule = try! NSRegularExpression(pattern: "^\\s{0,3}([-*_])(\\s*\\1){2,}\\s*$")
    private static let fence = try! NSRegularExpression(pattern: "^\\s*(```|~~~)\\s*([\\w+-]*)")
    private static let image = try! NSRegularExpression(pattern: "^\\s*!\\[(.*?)\\]\\((.*?)\\)\\s*$")
    private static let tableSep = try! NSRegularExpression(pattern: "^\\s*\\|?\\s*:?-{2,}:?\\s*(\\|\\s*:?-{2,}:?\\s*)*\\|?\\s*$")

    private static func matches(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }

    private static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func parse(_ text: String) -> [MDBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MDBlock] = []
        var i = 0
        var nextID = 0
        func add(_ k: MDBlock.Kind) { blocks.append(MDBlock(id: nextID, kind: k)); nextID += 1 }

        func isSpecial(_ line: String) -> Bool {
            matches(heading, line) != nil || matches(fence, line) != nil || matches(rule, line) != nil
                || matches(listItem, line) != nil || line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
                || matches(image, line) != nil
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { i += 1; continue }

            if let m = matches(fence, line) {
                let ns = line as NSString
                let lang = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
                var code: [String] = []
                i += 1
                while i < lines.count, matches(fence, lines[i]) == nil { code.append(lines[i]); i += 1 }
                i += 1
                add(.code(lang, code.joined(separator: "\n")))
                continue
            }
            if let m = matches(heading, line) {
                let ns = line as NSString
                add(.heading(m.range(at: 1).length, ns.substring(with: m.range(at: 2))))
                i += 1
                continue
            }
            if matches(rule, line) != nil { add(.rule); i += 1; continue }
            if let m = matches(image, line) {
                let ns = line as NSString
                add(.image(ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2))))
                i += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                var q: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var l = lines[i].trimmingCharacters(in: .whitespaces)
                    while l.hasPrefix(">") { l.removeFirst() }
                    q.append(l.trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                add(.quote(q))
                continue
            }
            if trimmed.hasPrefix("|"), i + 1 < lines.count, matches(tableSep, lines[i + 1]) != nil {
                let header = cells(line)
                i += 2
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(lines[i]))
                    i += 1
                }
                add(.table(header, rows))
                continue
            }
            if matches(listItem, line) != nil {
                var items: [MDItem] = []
                var itemID = 0
                while i < lines.count {
                    let l = lines[i]
                    if let m = matches(listItem, l) {
                        let ns = l as NSString
                        let indent = m.range(at: 1).length
                        let marker = ns.substring(with: m.range(at: 2))
                        let task: Bool? = m.range(at: 4).location != NSNotFound
                            ? ns.substring(with: m.range(at: 4)).lowercased() == "x" : nil
                        let body = ns.substring(with: m.range(at: 5))
                        let isOrdered = marker.first?.isNumber ?? false
                        items.append(MDItem(id: itemID, indent: indent, marker: isOrdered ? marker : "bullet",
                                            text: body, task: task, line: i))
                        itemID += 1
                        i += 1
                    } else if l.hasPrefix("  "), !l.trimmingCharacters(in: .whitespaces).isEmpty, var last = items.popLast() {
                        last = MDItem(id: last.id, indent: last.indent, marker: last.marker,
                                      text: last.text + " " + l.trimmingCharacters(in: .whitespaces),
                                      task: last.task, line: last.line)
                        items.append(last)
                        i += 1
                    } else { break }
                }
                add(.list(items))
                continue
            }

            var para: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let l = lines[i]
                if l.trimmingCharacters(in: .whitespaces).isEmpty || isSpecial(l) { break }
                para.append(l.trimmingCharacters(in: .whitespaces))
                i += 1
            }
            add(.paragraph(para.joined(separator: " ")))
        }
        return blocks
    }
}

// MARK: - Preview

struct MarkdownPreview: View {
    let text: String
    let settings: PanelSettings
    let accent: Color
    let onToggle: (Int) -> Void
    @Environment(\.theme) private var theme

    private var size: CGFloat { CGFloat(settings.fontSize) }
    private var blocks: [MDBlock] { MarkdownParser.parse(text) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: size * 0.75) {
                ForEach(blocks) { block in
                    render(block)
                }
            }
            .frame(maxWidth: settings.measure > 0 ? CGFloat(settings.measure) : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: settings.measure > 0 ? .center : .leading)
            .padding(CGFloat(settings.padding))
        }
        .scrollIndicators(.automatic)
    }

    // MARK: inline

    private func font(_ size: CGFloat, bold: Bool, italic: Bool) -> Font {
        let f: NSFont
        switch (bold, italic) {
        case (true, true): f = settings.font.boldItalic(size)
        case (true, false): f = settings.font.bold(size)
        case (false, true): f = settings.font.italic(size)
        default: f = settings.font.regular(size)
        }
        return Font(f as CTFont)
    }

    private func inline(_ s: String, size: CGFloat, bold: Bool = false, color: Color? = nil) -> Text {
        var attr = (try? AttributedString(markdown: s, options: AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)

        struct Edit { let range: Range<AttributedString.Index>; let intent: InlinePresentationIntent?; let isLink: Bool }
        let edits = attr.runs.map { Edit(range: $0.range, intent: $0.inlinePresentationIntent, isLink: $0.link != nil) }
        let mono = Font.system(size: size * 0.88, design: .monospaced)

        for e in edits {
            let isBold = bold || (e.intent?.contains(.stronglyEmphasized) ?? false)
            let isItalic = e.intent?.contains(.emphasized) ?? false
            if e.intent?.contains(.code) ?? false {
                attr[e.range].font = mono
                attr[e.range].foregroundColor = accent
                attr[e.range].backgroundColor = theme.hover
            } else {
                attr[e.range].font = font(size, bold: isBold, italic: isItalic)
                if let c = color { attr[e.range].foregroundColor = c }
            }
            if e.intent?.contains(.strikethrough) ?? false {
                attr[e.range].strikethroughStyle = .single
                attr[e.range].foregroundColor = theme.mutedC
            }
            if e.isLink {
                attr[e.range].foregroundColor = accent
                attr[e.range].underlineStyle = .single
            }
        }
        return Text(attr)
    }

    // MARK: blocks

    @ViewBuilder
    private func render(_ block: MDBlock) -> some View {
        switch block.kind {
        case .heading(let level, let t):
            let scale: [CGFloat] = [1.85, 1.5, 1.28, 1.12, 1.0, 0.95]
            let hs = size * scale[min(level - 1, 5)]
            inline(t, size: hs, bold: true, color: theme.textC)
                .padding(.top, level <= 2 ? size * 0.5 : size * 0.15)
                .textSelection(.enabled)

        case .paragraph(let t):
            inline(t, size: size, color: theme.textC)
                .lineSpacing(size * CGFloat(settings.lineHeight - 1) * 0.8)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .code(let lang, let code):
            VStack(alignment: .leading, spacing: 6) {
                if !lang.isEmpty {
                    Text(lang)
                        .font(Typo.ui(10.5, bold: true))
                        .foregroundStyle(theme.faintC)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: size * 0.86, design: .monospaced))
                        .foregroundStyle(theme.textC.opacity(0.92))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.hover))

        case .quote(let lines):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        inline(l, size: size, color: theme.mutedC)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .list(let items):
            VStack(alignment: .leading, spacing: size * 0.32) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        marker(for: item)
                        let done = item.task ?? false
                        inline(item.text, size: size, color: done ? theme.faintC : theme.textC)
                            .strikethrough(done, color: theme.faintC)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(.leading, CGFloat(item.indent) * 9)
                }
            }

        case .rule:
            Rectangle().fill(theme.hairlineStrong).frame(height: 1).padding(.vertical, size * 0.4)

        case .table(let header, let rows):
            TableBlock(header: header, rows: rows, size: size, accent: accent, inline: { inline($0, size: size, bold: $1, color: theme.textC) })

        case .image(let alt, let url):
            MarkdownImage(alt: alt, url: url)
        }
    }

    @ViewBuilder
    private func marker(for item: MDItem) -> some View {
        if let done = item.task {
            Button { onToggle(item.line) } label: {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: size * 0.95))
                    .foregroundStyle(done ? accent : theme.mutedC)
            }
            .buttonStyle(PressStyle())
        } else if item.marker == "bullet" {
            Circle().fill(accent).frame(width: 5, height: 5).offset(y: -size * 0.12)
        } else {
            Text(item.marker).font(font(size, bold: true, italic: false)).foregroundStyle(accent)
        }
    }
}

struct TableBlock: View {
    @Environment(\.theme) private var theme
    let header: [String]
    let rows: [[String]]
    let size: CGFloat
    let accent: Color
    let inline: (String, Bool) -> Text

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 9) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, h in inline(h, true) }
                }
                Divider().overlay(theme.hairlineStrong)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    GridRow {
                        ForEach(Array(r.enumerated()), id: \.offset) { _, c in inline(c, false) }
                    }
                }
            }
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.hover))
    }
}

struct MarkdownImage: View {
    @Environment(\.theme) private var theme
    let alt: String
    let url: String

    var body: some View {
        Group {
            if let u = URL(string: url), u.scheme?.hasPrefix("http") == true {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    case .failure: placeholder("Image failed to load")
                    default: placeholder("Loading image")
                    }
                }
            } else if let img = NSImage(contentsOfFile: (url as NSString).expandingTildeInPath) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                placeholder(alt.isEmpty ? "Image not found" : alt)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholder(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
            Text(text).font(Typo.ui(12))
        }
        .foregroundStyle(theme.faintC)
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.hover))
    }
}

// MARK: - Note panel

struct NotePanelView: View {
    @Bindable var panel: Panel
    @Environment(\.theme) private var theme

    private var accent: Color { theme.accent(panel.settings.accent) }

    private var stats: (words: Int, chars: Int, minutes: Int) {
        let t = panel.text
        var words = 0
        var inWord = false
        for u in t.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(u) { inWord = false }
            else if !inWord { inWord = true; words += 1 }
        }
        return (words, t.count, max(Int((Double(words) / 230).rounded(.up)), words == 0 ? 0 : 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch panel.settings.noteMode {
                case .edit:
                    editor
                case .preview:
                    preview
                case .split:
                    HStack(spacing: 0) {
                        editor
                        Rectangle().fill(theme.hairline).frame(width: 1)
                        preview
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if panel.settings.showStats { footer }
        }
    }

    private var editor: some View {
        MarkdownEditor(panel: panel)
            .overlay(alignment: .topLeading) {
                if panel.text.isEmpty {
                    Text("Start writing. Markdown works as you type.")
                        .font(Font(panel.settings.font.regular(CGFloat(panel.settings.fontSize)) as CTFont))
                        .foregroundStyle(theme.faintC)
                        .padding(CGFloat(panel.settings.padding))
                        .allowsHitTesting(false)
                }
            }
    }

    private var preview: some View {
        MarkdownPreview(text: panel.text, settings: panel.settings, accent: accent) { line in
            toggleTask(at: line)
        }
    }

    private var footer: some View {
        let s = stats
        return HStack(spacing: 14) {
            Text("\(s.words) \(s.words == 1 ? "word" : "words")")
            Text("\(s.chars) characters")
            if s.minutes > 0 { Text("\(s.minutes) min read") }
            Spacer()
            Text(panel.settings.font.label)
        }
        .font(Typo.ui(11))
        .foregroundStyle(theme.faintC)
        .padding(.horizontal, 14)
        .frame(height: 28)
    }

    private func toggleTask(at line: Int) {
        var lines = panel.text.components(separatedBy: "\n")
        guard line < lines.count else { return }
        let l = lines[line]
        if let r = l.range(of: "[ ]") {
            lines[line] = l.replacingCharacters(in: r, with: "[x]")
        } else if let r = l.range(of: "[x]") ?? l.range(of: "[X]") {
            lines[line] = l.replacingCharacters(in: r, with: "[ ]")
        }
        panel.text = lines.joined(separator: "\n")
    }
}
