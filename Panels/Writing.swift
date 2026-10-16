import SwiftUI
import AppKit
import WebKit
import Observation

// MARK: - Outline

struct OutlineItem: Identifiable {
    let id: Int
    let level: Int
    let title: String
    let location: Int
}

enum Outline {
    private static let heading = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.*?)\\s*#*\\s*$")
    private static let fence = try! NSRegularExpression(pattern: "^\\s*(```|~~~)")

    static func items(in text: String) -> [OutlineItem] {
        let ns = text as NSString
        var out: [OutlineItem] = []
        var inFence = false
        var loc = 0
        var n = 0
        while loc < ns.length {
            let r = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(r)
            var content = r
            while content.length > 0, [10, 13].contains(ns.character(at: NSMaxRange(content) - 1)) { content.length -= 1 }
            let line = ns.substring(with: content)
            let full = NSRange(location: 0, length: (line as NSString).length)
            if fence.firstMatch(in: line, range: full) != nil { inFence.toggle(); continue }
            if inFence { continue }
            if let m = heading.firstMatch(in: line, range: full) {
                let level = m.range(at: 1).length
                let title = (line as NSString).substring(with: m.range(at: 2))
                if !title.isEmpty {
                    out.append(OutlineItem(id: n, level: level, title: title, location: content.location))
                    n += 1
                }
            }
        }
        return out
    }

    static func firstHeading(in text: String) -> String? {
        items(in: text).first?.title
    }
}

// MARK: - Snippets

struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: String
    var expansion: String
}

/// Text expansions. Type `;todo` then a space and it becomes `- [ ] `.
/// Placeholders: {date} {time} {datetime} {weekday} and `$|` for where the caret lands.
@Observable
final class SnippetStore {
    static let shared = SnippetStore()

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "snippetsEnabled") }
    }

    var snippets: [Snippet] {
        didSet { save() }
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Panels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snippets.json")
    }

    static let defaults: [Snippet] = [
        Snippet(trigger: "date", expansion: "{date}"),
        Snippet(trigger: "time", expansion: "{time}"),
        Snippet(trigger: "now", expansion: "{datetime}"),
        Snippet(trigger: "today", expansion: "{weekday}"),
        Snippet(trigger: "todo", expansion: "- [ ] "),
        Snippet(trigger: "h1", expansion: "# "),
        Snippet(trigger: "h2", expansion: "## "),
        Snippet(trigger: "h3", expansion: "### "),
        Snippet(trigger: "quote", expansion: "> "),
        Snippet(trigger: "hr", expansion: "---\n"),
        Snippet(trigger: "code", expansion: "```\n$|\n```"),
        Snippet(trigger: "link", expansion: "[$|](https://)"),
        Snippet(trigger: "wiki", expansion: "[[$|]]"),
        Snippet(trigger: "table", expansion: "| $| | Column |\n| --- | --- |\n|  |  |\n")
    ]

    init() {
        enabled = UserDefaults.standard.object(forKey: "snippetsEnabled") as? Bool ?? true
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = decoded
        } else {
            snippets = Self.defaults
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(snippets) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    func reset() { snippets = Self.defaults }

    /// Returns the expansion text and the caret offset inside it (nil when the caret belongs at the end).
    func expand(_ trigger: String) -> (text: String, caret: Int?)? {
        guard enabled, let s = snippets.first(where: { $0.trigger.caseInsensitiveCompare(trigger) == .orderedSame }) else { return nil }
        var t = s.expansion
        let now = Date()
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "yyyy-MM-dd"; t = t.replacingOccurrences(of: "{date}", with: df.string(from: now))
        df.dateFormat = "HH:mm"; t = t.replacingOccurrences(of: "{time}", with: df.string(from: now))
        df.dateFormat = "yyyy-MM-dd HH:mm"; t = t.replacingOccurrences(of: "{datetime}", with: df.string(from: now))
        df.dateFormat = "EEEE, MMMM d, yyyy"; t = t.replacingOccurrences(of: "{weekday}", with: df.string(from: now))
        if let r = t.range(of: "$|") {
            let offset = (t[t.startIndex..<r.lowerBound] as Substring).utf16.count
            t.replaceSubrange(r, with: "")
            return (t, offset)
        }
        return (t, nil)
    }
}

// MARK: - Wiki links between notes

extension Workspace {
    /// Every note title across workspaces, lowercased, used to tell real links from missing ones.
    func knownNoteTitles() -> Set<String> {
        var out = Set<String>()
        for s in spaces { for p in s.panels where p.kind == .note { out.insert(p.title.lowercased()) } }
        return out
    }

    func openNote(titled raw: String) {
        let title = raw.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        for s in spaces {
            if let p = s.panels.first(where: { $0.kind == .note && $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
                if s.id != activeSpaceID { selectSpace(s.id) }
                if space.zoomedID != nil && space.zoomedID != p.id && !focusMode { space.zoomedID = nil }
                focus(p.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Runtime.shared.noteHost(for: p).flash(range: nil) }
                return
            }
        }
        let p = addPanel(.note, title: title, text: "# \(title)\n\n")
        p.settings.autoTitle = false
        showToast("Created \(title)")
    }
}

// MARK: - HTML export

enum HTMLExporter {
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func sub(_ pattern: String, in s: String, template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    static func inline(_ raw: String) -> String {
        var s = esc(raw)
        var codes: [String] = []
        if let re = try? NSRegularExpression(pattern: "`([^`\\n]+)`") {
            let ns = s as NSString
            var out = ""
            var last = 0
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                out += "\u{0001}\(codes.count)\u{0002}"
                codes.append("<code>" + ns.substring(with: m.range(at: 1)) + "</code>")
                last = NSMaxRange(m.range)
            }
            out += ns.substring(from: last)
            s = out
        }
        s = sub("!\\[([^\\]]*)\\]\\(([^)\\s]+)\\)", in: s, template: "<img alt=\"$1\" src=\"$2\">")
        s = sub("\\[\\[([^\\]|]+)\\|([^\\]]+)\\]\\]", in: s, template: "<span class=\"wiki\">$2</span>")
        s = sub("\\[\\[([^\\]]+)\\]\\]", in: s, template: "<span class=\"wiki\">$1</span>")
        s = sub("\\[([^\\]]+)\\]\\(([^)\\s]+)\\)", in: s, template: "<a href=\"$2\">$1</a>")
        s = sub("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1", in: s, template: "<strong>$2</strong>")
        s = sub("(?<![\\*_\\w])([\\*_])(?=[^\\s\\*_])(.+?)(?<=[^\\s\\*_])\\1(?![\\*_\\w])", in: s, template: "<em>$2</em>")
        s = sub("~~(?=\\S)(.+?)(?<=\\S)~~", in: s, template: "<del>$1</del>")
        for (i, c) in codes.enumerated() { s = s.replacingOccurrences(of: "\u{0001}\(i)\u{0002}", with: c) }
        return s
    }

    static func body(from markdown: String) -> String {
        var out = ""
        for block in MarkdownParser.parse(markdown) {
            switch block.kind {
            case .heading(let level, let t):
                out += "<h\(level)>\(inline(t))</h\(level)>\n"
            case .paragraph(let t):
                out += "<p>\(inline(t))</p>\n"
            case .code(let lang, let code):
                let cls = lang.isEmpty ? "" : " class=\"language-\(esc(lang))\""
                out += "<pre><code\(cls)>\(esc(code))</code></pre>\n"
            case .quote(let lines):
                out += "<blockquote>" + lines.map { "<p>\(inline($0))</p>" }.joined() + "</blockquote>\n"
            case .list(let items):
                let ordered = items.first.map { $0.marker != "bullet" } ?? false
                out += ordered ? "<ol>\n" : "<ul>\n"
                for it in items {
                    let pad = it.indent > 0 ? " style=\"margin-left:\(it.indent * 10)px\"" : ""
                    if let done = it.task {
                        out += "<li class=\"task\"\(pad)><input type=\"checkbox\" disabled\(done ? " checked" : "")> \(inline(it.text))</li>\n"
                    } else {
                        out += "<li\(pad)>\(inline(it.text))</li>\n"
                    }
                }
                out += ordered ? "</ol>\n" : "</ul>\n"
            case .rule:
                out += "<hr>\n"
            case .table(let header, let rows):
                out += "<table><thead><tr>" + header.map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead><tbody>\n"
                for r in rows { out += "<tr>" + r.map { "<td>\(inline($0))</td>" }.joined() + "</tr>\n" }
                out += "</tbody></table>\n"
            case .image(let alt, let url):
                out += "<p><img alt=\"\(esc(alt))\" src=\"\(esc(url))\"></p>\n"
            }
        }
        return out
    }

    static func document(title: String, markdown: String, font: EditorFont) -> String {
        let family: String
        switch font {
        case .instrument: family = "'Instrument Sans', -apple-system, system-ui, sans-serif"
        case .serif: family = "'New York', Georgia, serif"
        case .mono: family = "'SF Mono', ui-monospace, Menlo, monospace"
        case .rounded: family = "ui-rounded, 'SF Pro Rounded', system-ui, sans-serif"
        case .system: family = "-apple-system, system-ui, sans-serif"
        }
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(title))</title>
        <style>
        :root { color-scheme: light dark; --fg:#1e2b2a; --muted:#5b6b69; --bg:#fbfcfd; --rule:#d7dee3; --accent:#7e6551; --code:#eef2f5; }
        @media (prefers-color-scheme: dark) { :root { --fg:#dce7f0; --muted:#8fa3ad; --bg:#141e1d; --rule:#2b3b3a; --accent:#b08b6e; --code:#1d2b2a; } }
        body { margin:0; background:var(--bg); color:var(--fg); font:17px/1.65 \(family); }
        main { max-width:44rem; margin:0 auto; padding:4rem 1.5rem 6rem; }
        h1,h2,h3,h4 { line-height:1.2; margin:2.2em 0 .6em; } h1 { font-size:2.1rem; margin-top:0; } h2 { font-size:1.5rem; } h3 { font-size:1.2rem; }
        p, ul, ol, blockquote, pre, table { margin:0 0 1.1em; }
        a { color:var(--accent); } .wiki { color:var(--accent); border-bottom:1px dotted var(--accent); }
        code { font:.88em 'SF Mono', ui-monospace, Menlo, monospace; background:var(--code); padding:.12em .35em; border-radius:5px; }
        pre { background:var(--code); padding:1rem 1.1rem; border-radius:10px; overflow:auto; } pre code { background:none; padding:0; }
        blockquote { border-left:3px solid var(--accent); margin-left:0; padding-left:1rem; color:var(--muted); }
        hr { border:0; border-top:1px solid var(--rule); margin:2rem 0; } img { max-width:100%; border-radius:10px; }
        table { border-collapse:collapse; width:100%; } th,td { text-align:left; padding:.45rem .7rem; border-bottom:1px solid var(--rule); }
        li.task { list-style:none; margin-left:-1.2rem; }
        @media print { body { background:#fff; color:#111; } main { padding:0; max-width:none; } }
        </style></head><body><main>
        \(body(from: markdown))
        </main></body></html>
        """
    }
}

// MARK: - Export actions

enum ExportOps {
    private static var pdfJobs: [PDFJob] = []

    static func html(for panel: Panel) -> String {
        HTMLExporter.document(title: panel.title, markdown: panel.text, font: panel.settings.font)
    }

    static func saveHTML(_ panel: Panel) {
        let sp = NSSavePanel()
        sp.nameFieldStringValue = (panel.title.isEmpty ? "Untitled" : panel.title) + ".html"
        sp.allowedContentTypes = [.html]
        guard sp.runModal() == .OK, let url = sp.url else { return }
        do {
            try html(for: panel).write(to: url, atomically: true, encoding: .utf8)
            Workspace.shared.showToast("Exported \(url.lastPathComponent)")
        } catch {
            Workspace.shared.showToast("Could not export the file")
        }
    }

    static func copyHTML(_ panel: Panel) {
        let fragment = HTMLExporter.body(from: panel.text)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(fragment, forType: .html)
        pb.setString(fragment, forType: .string)
        Workspace.shared.showToast("Copied as HTML")
    }

    static func savePDF(_ panel: Panel) {
        let sp = NSSavePanel()
        sp.nameFieldStringValue = (panel.title.isEmpty ? "Untitled" : panel.title) + ".pdf"
        sp.allowedContentTypes = [.pdf]
        guard sp.runModal() == .OK, let url = sp.url else { return }
        let job = PDFJob(html: html(for: panel), destination: url)
        pdfJobs.append(job)
        job.start { ok in
            pdfJobs.removeAll { $0 === job }
            Workspace.shared.showToast(ok ? "Exported \(url.lastPathComponent)" : "Could not export the PDF")
        }
    }

    /// Renders HTML in an offscreen web view and writes it as one continuous PDF page.
    final class PDFJob: NSObject, WKNavigationDelegate {
        let html: String
        let destination: URL
        private let width: CGFloat = 820
        private let web: WKWebView
        private let window: NSWindow
        private var completion: ((Bool) -> Void)?

        init(html: String, destination: URL) {
            self.html = html
            self.destination = destination
            web = WKWebView(frame: NSRect(x: 0, y: 0, width: 820, height: 1000))
            window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 820, height: 1000),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            super.init()
            window.contentView = web
            web.navigationDelegate = self
        }

        func start(_ done: @escaping (Bool) -> Void) {
            completion = done
            web.loadHTMLString(html, baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.render() }
        }

        private func render() {
            web.evaluateJavaScript("Math.ceil(document.documentElement.scrollHeight)") { [weak self] value, _ in
                guard let self else { return }
                let height = max(CGFloat((value as? Double) ?? 1000), 400)
                self.web.setFrameSize(NSSize(width: self.width, height: height))
                self.window.setContentSize(NSSize(width: self.width, height: height))
                let config = WKPDFConfiguration()
                config.rect = CGRect(x: 0, y: 0, width: self.width, height: height)
                self.web.createPDF(configuration: config) { result in
                    switch result {
                    case .success(let data):
                        let ok = (try? data.write(to: self.destination, options: .atomic)) != nil
                        self.finish(ok)
                    case .failure:
                        self.finish(false)
                    }
                }
            }
        }

        private func finish(_ ok: Bool) {
            completion?(ok)
            completion = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(false)
        }
    }
}

// MARK: - Find and replace

enum FindOps {
    /// NSTextFinder actions: 1 show find, 12 show replace, 2 next, 3 previous, 7 use selection.
    static func perform(_ tag: Int) {
        let item = NSMenuItem()
        item.tag = tag
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
    }
}

// MARK: - Settings tab

struct WritingSettings: View {
    @Environment(\.theme) private var theme
    private let store = SnippetStore.shared

    var body: some View {
        @Bindable var s = store
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Writing").font(Typo.ui(20, bold: true)).foregroundStyle(theme.textC)

                SettingsSection(title: "Snippets") {
                    ToggleRow(label: "Expand snippets as you type", isOn: $s.enabled)
                    Text("Type a semicolon and a trigger, then a space. For example, ;todo becomes a checkbox.")
                        .font(Typo.ui(11.5)).foregroundStyle(theme.faintC)

                    VStack(spacing: 8) {
                        ForEach($s.snippets) { $snip in
                            HStack(alignment: .top, spacing: 10) {
                                HStack(spacing: 2) {
                                    Text(";").font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.faintC)
                                    TextField("trigger", text: $snip.trigger)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(theme.textC)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .frame(width: 118)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.hover))

                                TextField("expansion", text: $snip.expansion, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(theme.textC)
                                    .lineLimit(1...4)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.hover))

                                IconButton(symbol: "trash", help: "Delete snippet", size: 11, box: 28) {
                                    store.snippets.removeAll { $0.id == snip.id }
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button { store.snippets.append(Snippet(trigger: "new", expansion: "")) } label: {
                            Label("Add Snippet", systemImage: "plus")
                        }
                        Button { store.reset() } label: { Label("Restore Defaults", systemImage: "arrow.counterclockwise") }
                    }

                    Text("Placeholders: {date} {time} {datetime} {weekday}. Use $| to place the caret.")
                        .font(Typo.ui(11.5)).foregroundStyle(theme.faintC)
                }

                SettingsSection(title: "Links") {
                    Text("Write [[Note Title]] to link to another note. Command-click it in the editor, or click it in preview. Missing notes are created for you.")
                        .font(Typo.ui(12.5)).foregroundStyle(theme.mutedC)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
        }
    }
}
