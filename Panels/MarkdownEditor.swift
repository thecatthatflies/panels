import SwiftUI
import AppKit

// MARK: - Style configuration

struct EditorStyle: Equatable {
    var font: EditorFont
    var size: CGFloat
    var lineHeight: CGFloat
    var rich: Bool
    var text: NSColor
    var muted: NSColor
    var faint: NSColor
    var accent: NSColor
    var codeBackground: NSColor
    var isDark: Bool
}

// MARK: - Markdown styler

enum MarkdownStyler {
    private static let heading = try! NSRegularExpression(pattern: "^(#{1,6})(\\s+)(.*)$")
    private static let bullet = try! NSRegularExpression(pattern: "^(\\s*)([-*+]|\\d{1,3}[.)])(\\s+)(\\[[ xX]\\]\\s+)?")
    private static let quote = try! NSRegularExpression(pattern: "^(\\s*>+\\s?)")
    private static let rule = try! NSRegularExpression(pattern: "^\\s{0,3}([-*_])(\\s*\\1){2,}\\s*$")
    private static let fence = try! NSRegularExpression(pattern: "^\\s*(```|~~~)")
    private static let codeSpan = try! NSRegularExpression(pattern: "(`+)([^`\\n]+?)\\1")
    private static let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italic = try! NSRegularExpression(pattern: "(?<![\\*_\\w])([\\*_])(?=[^\\s\\*_])(.+?)(?<=[^\\s\\*_])\\1(?![\\*_\\w])")
    private static let strike = try! NSRegularExpression(pattern: "~~(?=\\S)(.+?)(?<=\\S)~~")
    private static let link = try! NSRegularExpression(pattern: "(!?\\[)([^\\]\\n]*)(\\]\\()([^)\\n]+)(\\))")
    private static let bareURL = try! NSRegularExpression(pattern: "https?://[^\\s)>\\]]+")
    private static let table = try! NSRegularExpression(pattern: "^\\s*\\|.*\\|\\s*$")

    static func apply(to storage: NSTextStorage, style s: EditorStyle) {
        let full = NSRange(location: 0, length: storage.length)
        let string = storage.string as NSString

        storage.beginEditing()
        defer { storage.endEditing() }

        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = s.lineHeight
        para.paragraphSpacing = s.size * 0.2

        let base: [NSAttributedString.Key: Any] = [
            .font: s.font.regular(s.size),
            .foregroundColor: s.text,
            .paragraphStyle: para,
            .underlineStyle: 0,
            .strikethroughStyle: 0,
            .backgroundColor: NSColor.clear,
            .kern: 0
        ]
        storage.setAttributes(base, range: full)
        guard s.rich, full.length > 0 else { return }

        let mono = NSFont.monospacedSystemFont(ofSize: s.size * 0.88, weight: .regular)
        var inFence = false
        var location = 0

        while location < string.length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(lineRange)
            var content = lineRange
            // trim trailing newline from styling range
            while content.length > 0, [10, 13].contains(string.character(at: NSMaxRange(content) - 1)) { content.length -= 1 }
            let line = string.substring(with: content)
            let ls = NSRange(location: 0, length: (line as NSString).length)

            // blank lines get compact height so paragraph gaps stay tight
            if content.length == 0 {
                let p = NSMutableParagraphStyle()
                p.lineHeightMultiple = inFence ? max(s.lineHeight - 0.1, 1.1) : 0.62
                p.paragraphSpacing = 0
                storage.addAttributes([.paragraphStyle: p, .font: inFence ? mono : s.font.regular(s.size)], range: lineRange)
                continue
            }

            // fences
            if fence.firstMatch(in: line, range: ls) != nil {
                inFence.toggle()
                storage.addAttributes([.foregroundColor: s.faint, .font: mono, .backgroundColor: s.codeBackground], range: content)
                continue
            }
            if inFence {
                let p = NSMutableParagraphStyle()
                p.lineHeightMultiple = max(s.lineHeight - 0.1, 1.1)
                p.paragraphSpacing = 0
                storage.addAttributes([.font: mono, .foregroundColor: s.text.withAlphaComponent(0.92),
                                       .backgroundColor: s.codeBackground, .paragraphStyle: p], range: content)
                continue
            }

            var inlineStart = 0

            if let m = heading.firstMatch(in: line, range: ls) {
                let level = m.range(at: 1).length
                let scale: [CGFloat] = [1.85, 1.5, 1.28, 1.12, 1.0, 0.95]
                let size = s.size * scale[min(level - 1, 5)]
                let p = NSMutableParagraphStyle()
                p.lineHeightMultiple = max(s.lineHeight - 0.25, 1.1)
                p.paragraphSpacingBefore = level <= 2 ? s.size * 0.7 : s.size * 0.3
                p.paragraphSpacing = s.size * 0.25
                storage.addAttributes([.font: s.font.bold(size), .paragraphStyle: p], range: content)
                let marks = NSRange(location: content.location, length: m.range(at: 1).length + m.range(at: 2).length)
                storage.addAttributes([.foregroundColor: s.faint], range: marks)
                inlineStart = marks.length
            } else if rule.firstMatch(in: line, range: ls) != nil {
                storage.addAttributes([.foregroundColor: s.faint, .kern: 3], range: content)
                continue
            } else if let m = quote.firstMatch(in: line, range: ls) {
                let p = NSMutableParagraphStyle()
                p.lineHeightMultiple = s.lineHeight
                p.firstLineHeadIndent = 4
                p.headIndent = 14
                p.paragraphSpacing = s.size * 0.2
                storage.addAttributes([.paragraphStyle: p, .foregroundColor: s.muted], range: content)
                storage.addAttributes([.foregroundColor: s.accent, .font: s.font.bold(s.size)],
                                      range: NSRange(location: content.location, length: m.range.length))
                inlineStart = m.range.length
            } else if let m = bullet.firstMatch(in: line, range: ls) {
                let indentLen = m.range(at: 1).length
                let markerLen = m.range(at: 2).length
                let gapLen = m.range(at: 3).length
                let taskRange = m.range(at: 4)

                let prefix = (line as NSString).substring(to: m.range.length)
                let width = (prefix as NSString).size(withAttributes: [.font: s.font.regular(s.size)]).width
                let p = NSMutableParagraphStyle()
                p.lineHeightMultiple = s.lineHeight
                p.paragraphSpacing = s.size * 0.12
                p.firstLineHeadIndent = 0
                p.headIndent = width
                storage.addAttribute(.paragraphStyle, value: p, range: content)

                let markerR = NSRange(location: content.location + indentLen, length: markerLen)
                storage.addAttributes([.foregroundColor: s.accent, .font: s.font.bold(s.size)], range: markerR)

                if taskRange.location != NSNotFound {
                    let tr = NSRange(location: content.location + taskRange.location, length: taskRange.length)
                    let done = (line as NSString).substring(with: taskRange).lowercased().contains("x")
                    storage.addAttributes([.foregroundColor: s.accent, .font: s.font.bold(s.size)], range: tr)
                    if done {
                        let rest = NSRange(location: tr.location + tr.length, length: max(NSMaxRange(content) - (tr.location + tr.length), 0))
                        storage.addAttributes([.foregroundColor: s.faint, .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                               .strikethroughColor: s.faint], range: rest)
                    }
                }
                inlineStart = indentLen + markerLen + gapLen + (taskRange.location != NSNotFound ? taskRange.length : 0)
            } else if table.firstMatch(in: line, range: ls) != nil {
                storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: s.size * 0.9, weight: .regular),
                                       .foregroundColor: s.muted], range: content)
                continue
            }

            guard inlineStart < ls.length else { continue }
            let sub = NSRange(location: inlineStart, length: ls.length - inlineStart)
            applyInline(line: line, sub: sub, offset: content.location, storage: storage, style: s, mono: mono)
        }
    }

    private static func shift(_ r: NSRange, by o: Int) -> NSRange { NSRange(location: r.location + o, length: r.length) }

    private static func applyInline(line: String, sub: NSRange, offset: Int, storage: NSTextStorage,
                                    style s: EditorStyle, mono: NSFont) {
        // bold
        for m in bold.matches(in: line, range: sub) {
            restyle(storage, shift(m.range(at: 2), by: offset), bold: true, italic: false, style: s)
            storage.addAttribute(.foregroundColor, value: s.faint, range: shift(NSRange(location: m.range.location, length: 2), by: offset))
            storage.addAttribute(.foregroundColor, value: s.faint, range: shift(NSRange(location: NSMaxRange(m.range) - 2, length: 2), by: offset))
        }
        // italic
        for m in italic.matches(in: line, range: sub) {
            restyle(storage, shift(m.range(at: 2), by: offset), bold: false, italic: true, style: s)
            storage.addAttribute(.foregroundColor, value: s.faint, range: shift(NSRange(location: m.range.location, length: 1), by: offset))
            storage.addAttribute(.foregroundColor, value: s.faint, range: shift(NSRange(location: NSMaxRange(m.range) - 1, length: 1), by: offset))
        }
        // strike
        for m in strike.matches(in: line, range: sub) {
            let inner = shift(m.range(at: 1), by: offset)
            storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: s.muted,
                                   .foregroundColor: s.muted], range: inner)
            storage.addAttribute(.foregroundColor, value: s.faint, range: shift(NSRange(location: m.range.location, length: 2), by: offset))
            storage.addAttribute(.foregroundColor, value: s.faint, range: shift(NSRange(location: NSMaxRange(m.range) - 2, length: 2), by: offset))
        }
        // links
        for m in link.matches(in: line, range: sub) {
            let open = shift(m.range(at: 1), by: offset)
            let textR = shift(m.range(at: 2), by: offset)
            let mid = shift(m.range(at: 3), by: offset)
            let url = shift(m.range(at: 4), by: offset)
            let close = shift(m.range(at: 5), by: offset)
            storage.addAttributes([.foregroundColor: s.accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                   .underlineColor: s.accent.withAlphaComponent(0.5)], range: textR)
            for r in [open, mid, url, close] { storage.addAttribute(.foregroundColor, value: s.faint, range: r) }
        }
        for m in bareURL.matches(in: line, range: sub) {
            let r = shift(m.range, by: offset)
            var overlapsLink = false
            storage.enumerateAttribute(.underlineStyle, in: r, options: []) { v, _, stop in
                if let n = v as? Int, n != 0 { overlapsLink = true; stop.pointee = true }
            }
            if overlapsLink { continue }
            storage.addAttributes([.foregroundColor: s.accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                   .underlineColor: s.accent.withAlphaComponent(0.5)], range: r)
        }
        // code spans last so they win
        for m in codeSpan.matches(in: line, range: sub) {
            let r = shift(m.range, by: offset)
            storage.addAttributes([.font: mono, .foregroundColor: s.accent,
                                   .backgroundColor: s.codeBackground, .underlineStyle: 0, .strikethroughStyle: 0], range: r)
            let tick = m.range(at: 1).length
            storage.addAttribute(.foregroundColor, value: s.faint, range: shift(NSRange(location: m.range.location, length: tick), by: offset))
            storage.addAttribute(.foregroundColor, value: s.faint, range: shift(NSRange(location: NSMaxRange(m.range) - tick, length: tick), by: offset))
        }
    }

    private static func restyle(_ storage: NSTextStorage, _ range: NSRange, bold: Bool, italic: Bool, style s: EditorStyle) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        var runs: [(NSRange, NSFont)] = []
        storage.enumerateAttribute(.font, in: range, options: []) { v, r, _ in
            if let f = v as? NSFont { runs.append((r, f)) }
        }
        for (r, f) in runs {
            let t = f.fontDescriptor.symbolicTraits
            let isB = t.contains(.bold) || bold
            let isI = t.contains(.italic) || italic
            let size = f.pointSize
            let nf: NSFont
            switch (isB, isI) {
            case (true, true): nf = s.font.boldItalic(size)
            case (true, false): nf = s.font.bold(size)
            case (false, true): nf = s.font.italic(size)
            default: nf = s.font.regular(size)
            }
            storage.addAttribute(.font, value: nf, range: r)
        }
    }
}

// MARK: - Text view

final class PanelTextView: NSTextView {
    var onFocus: (() -> Void)?
    private static let listLine = try! NSRegularExpression(pattern: "^(\\s*)([-*+]|(\\d{1,3})([.)]))(\\s+)(\\[[ xX]\\]\\s+)?")
    private static let quoteLine = try! NSRegularExpression(pattern: "^(\\s*>+\\s?)")
    private static let checkbox = try! NSRegularExpression(pattern: "\\[[ xX]\\]")
    private static let mdLink = try! NSRegularExpression(pattern: "\\[[^\\]\\n]*\\]\\(([^)\\n]+)\\)|https?://[^\\s)>\\]]+")

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }

    // MARK: current line helpers

    private func lineInfo(at index: Int) -> (range: NSRange, text: String) {
        let ns = string as NSString
        let safe = min(max(index, 0), ns.length)
        let r = ns.lineRange(for: NSRange(location: safe, length: 0))
        var content = r
        while content.length > 0, [10, 13].contains(ns.character(at: NSMaxRange(content) - 1)) { content.length -= 1 }
        return (content, ns.substring(with: content))
    }

    // MARK: Return continues lists

    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        guard sel.length == 0 else { super.insertNewline(sender); return }
        let (lineR, line) = lineInfo(at: sel.location)
        let ls = NSRange(location: 0, length: (line as NSString).length)
        let caretInLine = sel.location - lineR.location

        if let m = Self.listLine.firstMatch(in: line, range: ls) {
            let ns = line as NSString
            let indent = ns.substring(with: m.range(at: 1))
            let marker = ns.substring(with: m.range(at: 2))
            let gap = ns.substring(with: m.range(at: 5))
            let hasTask = m.range(at: 6).location != NSNotFound
            let prefixLen = m.range.length
            let rest = ns.substring(from: prefixLen).trimmingCharacters(in: .whitespaces)

            if caretInLine < prefixLen { super.insertNewline(sender); return }

            if rest.isEmpty {
                // empty item: end the list
                if shouldChangeText(in: lineR, replacementString: "") {
                    textStorage?.replaceCharacters(in: lineR, with: "")
                    didChangeText()
                    setSelectedRange(NSRange(location: lineR.location, length: 0))
                }
                return
            }

            var next = marker
            if m.range(at: 3).location != NSNotFound, let n = Int(ns.substring(with: m.range(at: 3))) {
                next = "\(n + 1)" + ns.substring(with: m.range(at: 4))
            }
            let insertion = "\n" + indent + next + gap + (hasTask ? "[ ] " : "")
            insertText(insertion, replacementRange: sel)
            return
        }

        if let m = Self.quoteLine.firstMatch(in: line, range: ls) {
            let prefix = (line as NSString).substring(with: m.range)
            let rest = (line as NSString).substring(from: m.range.length).trimmingCharacters(in: .whitespaces)
            if caretInLine >= m.range.length {
                if rest.isEmpty {
                    if shouldChangeText(in: lineR, replacementString: "") {
                        textStorage?.replaceCharacters(in: lineR, with: "")
                        didChangeText()
                        setSelectedRange(NSRange(location: lineR.location, length: 0))
                    }
                    return
                }
                insertText("\n" + prefix, replacementRange: sel)
                return
            }
        }

        // keep indentation of plain lines
        let ns = line as NSString
        var indentLen = 0
        while indentLen < ns.length, [32, 9].contains(ns.character(at: indentLen)) { indentLen += 1 }
        if indentLen > 0, caretInLine >= indentLen {
            insertText("\n" + ns.substring(to: indentLen), replacementRange: sel)
            return
        }
        super.insertNewline(sender)
    }

    // MARK: Tab handling

    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        let (lineR, line) = lineInfo(at: sel.location)
        let ls = NSRange(location: 0, length: (line as NSString).length)
        if Self.listLine.firstMatch(in: line, range: ls) != nil {
            if shouldChangeText(in: NSRange(location: lineR.location, length: 0), replacementString: "  ") {
                textStorage?.replaceCharacters(in: NSRange(location: lineR.location, length: 0), with: "  ")
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + 2, length: sel.length))
            }
        } else {
            insertText("    ", replacementRange: sel)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        let sel = selectedRange()
        let (lineR, line) = lineInfo(at: sel.location)
        let ns = line as NSString
        var remove = 0
        while remove < 2, remove < ns.length, ns.character(at: remove) == 32 { remove += 1 }
        guard remove > 0 else { return }
        let r = NSRange(location: lineR.location, length: remove)
        if shouldChangeText(in: r, replacementString: "") {
            textStorage?.replaceCharacters(in: r, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: max(sel.location - remove, lineR.location), length: sel.length))
        }
    }

    // MARK: Formatting shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let ch = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        if flags == [.command, .shift], ch == "k" { insertLink(); return true }
        guard flags == .command else { return super.performKeyEquivalent(with: event) }
        switch ch {
        case "b": wrapSelection(open: "**", close: "**"); return true
        case "i": wrapSelection(open: "*", close: "*"); return true
        case "e": wrapSelection(open: "`", close: "`"); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    private func wrapSelection(open: String, close: String) {
        let sel = selectedRange()
        let ns = string as NSString
        let selected = ns.substring(with: sel)
        let before = sel.location >= open.count ? ns.substring(with: NSRange(location: sel.location - open.count, length: open.count)) : ""
        let afterLoc = NSMaxRange(sel)
        let after = afterLoc + close.count <= ns.length ? ns.substring(with: NSRange(location: afterLoc, length: close.count)) : ""

        if before == open && after == close {
            // unwrap
            let full = NSRange(location: sel.location - open.count, length: sel.length + open.count + close.count)
            if shouldChangeText(in: full, replacementString: selected) {
                textStorage?.replaceCharacters(in: full, with: selected)
                didChangeText()
                setSelectedRange(NSRange(location: full.location, length: selected.count))
            }
            return
        }
        let replacement = open + selected + close
        if shouldChangeText(in: sel, replacementString: replacement) {
            textStorage?.replaceCharacters(in: sel, with: replacement)
            didChangeText()
            if sel.length == 0 {
                setSelectedRange(NSRange(location: sel.location + open.count, length: 0))
            } else {
                setSelectedRange(NSRange(location: sel.location + open.count, length: sel.length))
            }
        }
    }

    private func insertLink() {
        let sel = selectedRange()
        let ns = string as NSString
        let selected = ns.substring(with: sel)
        let label = selected.isEmpty ? "link" : selected
        let replacement = "[\(label)](url)"
        if shouldChangeText(in: sel, replacementString: replacement) {
            textStorage?.replaceCharacters(in: sel, with: replacement)
            didChangeText()
            let urlStart = sel.location + label.count + 3
            setSelectedRange(NSRange(location: urlStart, length: 3))
        }
    }

    // MARK: Mouse: task toggles and cmd-click links

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let idx = characterIndexForInsertion(at: point)
        let (lineR, line) = lineInfo(at: min(idx, max((string as NSString).length - 1, 0)))
        let ls = NSRange(location: 0, length: (line as NSString).length)

        if let m = Self.listLine.firstMatch(in: line, range: ls), m.range(at: 6).location != NSNotFound {
            if let box = Self.checkbox.firstMatch(in: line, range: m.range(at: 6)) {
                let boxRange = NSRange(location: lineR.location + box.range.location, length: box.range.length)
                if idx >= boxRange.location && idx <= NSMaxRange(boxRange) {
                    let cur = (string as NSString).substring(with: boxRange)
                    let toggled = cur.lowercased().contains("x") ? "[ ]" : "[x]"
                    if shouldChangeText(in: boxRange, replacementString: toggled) {
                        textStorage?.replaceCharacters(in: boxRange, with: toggled)
                        didChangeText()
                    }
                    return
                }
            }
        }

        if event.modifierFlags.contains(.command) {
            for m in Self.mdLink.matches(in: line, range: ls) {
                let abs = NSRange(location: lineR.location + m.range.location, length: m.range.length)
                if idx >= abs.location && idx <= NSMaxRange(abs) {
                    let ns = line as NSString
                    let urlString: String
                    if m.range(at: 1).location != NSNotFound { urlString = ns.substring(with: m.range(at: 1)) }
                    else { urlString = ns.substring(with: m.range) }
                    if let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) { NSWorkspace.shared.open(url) }
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}

// MARK: - Scroll view that centers text for measure

final class NoteScrollView: NSScrollView {
    var padding: CGFloat = 22 { didSet { needsLayout = true } }
    var measure: CGFloat = 0 { didSet { needsLayout = true } }
    var wrap: Bool = true { didSet { needsLayout = true } }
    var typewriter: Bool = false { didSet { needsLayout = true } }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let bottom: CGFloat = typewriter ? max(contentSize.height * 0.45, 6) : 6
        if contentInsets.bottom != bottom { contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0) }
        guard let tv = documentView as? PanelTextView else { return }
        let w = contentSize.width
        var h = padding
        if measure > 0 { h = max(padding, (w - measure) / 2) }
        let inset = NSSize(width: h, height: padding)
        if tv.textContainerInset != inset { tv.textContainerInset = inset }
        if wrap {
            if abs(tv.frame.width - w) > 0.5 { tv.setFrameSize(NSSize(width: w, height: tv.frame.height)) }
            tv.textContainer?.containerSize = NSSize(width: max(w - inset.width * 2, 10), height: CGFloat.greatestFiniteMagnitude)
        }
    }
}

// MARK: - Host (cached per panel)

final class NoteEditorHost: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    let scrollView = NoteScrollView()
    let textView: PanelTextView
    weak var panel: Panel?
    private var lastStyle: EditorStyle?
    private var lastWrap: Bool?
    private var applying = false
    private var typewriter = false
    private var dimOthers = false

    init(panel: Panel) {
        self.panel = panel
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        textView = PanelTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textContainer: container)
        super.init()

        textView.delegate = self
        storage.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.selectedTextAttributes = [:]

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 6, right: 0)

        textView.string = panel.text
        textView.onFocus = { [weak self] in
            guard let id = self?.panel?.id else { return }
            Workspace.shared.focus(id, grabFirstResponder: false)
        }
    }

    func apply(settings st: PanelSettings, theme: Theme) {
        let accent = theme.accentNS(st.accent)
        let style = EditorStyle(
            font: st.font,
            size: CGFloat(st.fontSize),
            lineHeight: CGFloat(st.lineHeight),
            rich: st.richStyling,
            text: NSColor(hex: theme.text),
            muted: NSColor(hex: theme.textMuted),
            faint: NSColor(hex: theme.textFaint),
            accent: accent,
            codeBackground: theme.isDark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.055),
            isDark: theme.isDark
        )

        let modeChanged = typewriter != st.typewriter || dimOthers != st.dimParagraphs
        typewriter = st.typewriter
        dimOthers = st.dimParagraphs
        scrollView.typewriter = st.typewriter
        scrollView.padding = CGFloat(st.padding)
        scrollView.measure = CGFloat(st.measure)
        scrollView.wrap = st.wrap
        if textView.isContinuousSpellCheckingEnabled != st.spellcheck {
            textView.isContinuousSpellCheckingEnabled = st.spellcheck
            textView.isGrammarCheckingEnabled = false
        }
        if lastWrap != st.wrap {
            lastWrap = st.wrap
            scrollView.hasHorizontalScroller = !st.wrap
            textView.isHorizontallyResizable = !st.wrap
            textView.autoresizingMask = st.wrap ? [.width] : []
            if !st.wrap {
                textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                               height: CGFloat.greatestFiniteMagnitude)
            }
        }

        textView.insertionPointColor = accent
        textView.selectedTextAttributes = [
            .backgroundColor: accent.withAlphaComponent(theme.isDark ? 0.30 : 0.24)
        ]

        if style != lastStyle {
            lastStyle = style
            textView.typingAttributes = [
                .font: style.font.regular(style.size),
                .foregroundColor: style.text,
                .paragraphStyle: {
                    let p = NSMutableParagraphStyle()
                    p.lineHeightMultiple = style.lineHeight
                    p.paragraphSpacing = style.size * 0.2
                    return p
                }()
            ]
            if let storage = textView.textStorage {
                let sel = textView.selectedRange()
                MarkdownStyler.apply(to: storage, style: style)
                textView.setSelectedRange(sel)
            }
        }
        scrollView.needsLayout = true
        if modeChanged || style != lastStyle { updateDim() }
        if modeChanged && typewriter { DispatchQueue.main.async { self.centerCaret(animated: false) } }
    }

    // MARK: lock in helpers

    private func updateDim() {
        guard let lm = textView.layoutManager, let storage = textView.textStorage else { return }
        let len = storage.length
        let full = NSRange(location: 0, length: len)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        guard dimOthers, len > 0, let style = lastStyle else { return }
        let ns = storage.string as NSString
        let sel = textView.selectedRange()
        let para = ns.paragraphRange(for: NSRange(location: min(sel.location, max(len - 1, 0)), length: 0))
        let dim = style.text.withAlphaComponent(style.isDark ? 0.28 : 0.34)
        if para.location > 0 {
            lm.addTemporaryAttribute(.foregroundColor, value: dim, forCharacterRange: NSRange(location: 0, length: para.location))
        }
        let end = NSMaxRange(para)
        if end < len {
            lm.addTemporaryAttribute(.foregroundColor, value: dim, forCharacterRange: NSRange(location: end, length: len - end))
        }
    }

    private func centerCaret(animated: Bool = true) {
        guard typewriter, let lm = textView.layoutManager, textView.textContainer != nil else { return }
        let len = (textView.string as NSString).length
        guard len > 0 else { return }
        let sel = textView.selectedRange()
        let charIndex = min(sel.location, len - 1)
        let glyph = lm.glyphIndexForCharacter(at: charIndex)
        var rect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        rect.origin.y += textView.textContainerOrigin.y
        let visible = scrollView.contentView.bounds.height
        let maxY = max(textView.frame.height - visible + scrollView.contentInsets.bottom, 0)
        let target = min(max(rect.midY - visible * 0.42, 0), maxY)
        let clip = scrollView.contentView
        if abs(clip.bounds.origin.y - target) < 1 { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.allowsImplicitAnimation = true
                clip.animator().setBoundsOrigin(NSPoint(x: 0, y: target))
            }
        } else {
            clip.setBoundsOrigin(NSPoint(x: 0, y: target))
        }
        scrollView.reflectScrolledClipView(clip)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !applying else { return }
        if dimOthers { updateDim() }
        if typewriter { centerCaret() }
    }

    func pushTextIfNeeded(_ text: String) {
        guard textView.string != text, !applying else { return }
        applying = true
        let sel = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
        applying = false
        if let storage = textView.textStorage, let style = lastStyle { MarkdownStyler.apply(to: storage, style: style) }
    }

    // MARK: delegates

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), let style = lastStyle else { return }
        MarkdownStyler.apply(to: textStorage, style: style)
    }

    func textDidChange(_ notification: Notification) {
        guard !applying, let panel else { return }
        let s = textView.string
        if panel.text != s { panel.text = s }
    }
}

// MARK: - SwiftUI wrapper

struct MarkdownEditor: NSViewRepresentable {
    @Bindable var panel: Panel
    let settings: PanelSettings
    @Environment(\.theme) private var theme

    func makeNSView(context: Context) -> HostContainer {
        let host = Runtime.shared.noteHost(for: panel)
        host.pushTextIfNeeded(panel.text)
        host.apply(settings: settings, theme: theme)
        let c = HostContainer()
        c.attach(host.scrollView, steal: true)
        return c
    }

    func updateNSView(_ container: HostContainer, context: Context) {
        let host = Runtime.shared.noteHost(for: panel)
        container.attach(host.scrollView, steal: false)
        host.pushTextIfNeeded(panel.text)
        host.apply(settings: settings, theme: theme)
    }

    static func dismantleNSView(_ container: HostContainer, coordinator: ()) {
        container.release()
    }
}
