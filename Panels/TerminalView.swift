import SwiftUI
import AppKit
import Darwin

// MARK: - Controller (process + emulator + view)

final class TerminalController {
    let panelID: UUID
    let emulator: TerminalEmulator
    let view: TerminalNSView

    private var master: Int32 = -1
    private var pid: pid_t = 0
    private var readSource: DispatchSourceRead?
    private var procSource: DispatchSourceProcess?
    private let readQueue = DispatchQueue(label: "panels.pty.read")
    private let writeQueue = DispatchQueue(label: "panels.pty.write")
    private(set) var started = false
    private(set) var exited = false
    private var shellPath = ""

    init(panel: Panel) {
        panelID = panel.id
        emulator = TerminalEmulator(cols: 80, rows: 24)
        view = TerminalNSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.controller = self
        view.emulator = emulator
        shellPath = panel.settings.shell

        emulator.onResponse = { [weak self] bytes in self?.write(bytes) }
        emulator.onBell = { NSSound.beep() }
        emulator.onScrollbackTrim = { [weak self] n in self?.view.scrollbackTrimmed(n) }
    }

    deinit { terminate() }

    // MARK: lifecycle

    func startIfNeeded() {
        guard !started, view.cols >= 2, view.rows >= 2 else { return }
        start()
    }

    func start() {
        started = true
        exited = false

        let configured = shellPath.trimmingCharacters(in: .whitespaces)
        let shell = !configured.isEmpty && FileManager.default.isExecutableFile(atPath: configured)
            ? configured
            : (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Panels"
        env["TERM_PROGRAM_VERSION"] = "1.0"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        env.removeValue(forKey: "TERM_SESSION_ID")

        let argv0 = "-" + (shell as NSString).lastPathComponent
        let cArgs: [UnsafeMutablePointer<CChar>?] = [strdup(argv0), nil]
        let cEnv: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let cPath = strdup(shell)
        let cHome = strdup(NSHomeDirectory())

        var size = winsize(ws_row: UInt16(emulator.rows), ws_col: UInt16(emulator.cols),
                           ws_xpixel: UInt16(max(view.bounds.width, 1)), ws_ypixel: UInt16(max(view.bounds.height, 1)))
        var m: Int32 = 0
        let child = forkpty(&m, nil, nil, &size)
        if child == 0 {
            chdir(cHome)
            execve(cPath, cArgs, cEnv)
            _exit(127)
        }
        free(cPath)
        free(cHome)
        cArgs.forEach { free($0) }
        cEnv.forEach { free($0) }

        guard child > 0 else {
            emulator.feed(Array("Could not start a shell.\r\n".utf8))
            exited = true
            view.contentChanged()
            return
        }

        pid = child
        master = m
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

        let fd = master
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
        src.setEventHandler { [weak self] in
            var buf = [UInt8](repeating: 0, count: 65536)
            let n = Darwin.read(fd, &buf, buf.count)
            if n > 0 {
                let chunk = Array(buf[0..<n])
                DispatchQueue.main.async { self?.received(chunk) }
            } else if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) {
                src.cancel()
            }
        }
        src.resume()
        readSource = src

        let proc = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: .main)
        proc.setEventHandler { [weak self] in self?.processExited() }
        proc.resume()
        procSource = proc
    }

    private func processExited() {
        var status: Int32 = 0
        waitpid(pid, &status, WNOHANG)
        exited = true
        readSource?.cancel()
        readSource = nil
        procSource?.cancel()
        procSource = nil
        if master >= 0 { close(master); master = -1 }
        emulator.feed(Array("\r\n\u{1B}[2m[Process finished. Press any key to restart.]\u{1B}[0m\r\n".utf8))
        view.contentChanged()
    }

    func restart() {
        guard exited else { return }
        started = false
        emulator.feed(Array("\u{1B}[2J\u{1B}[H".utf8))
        startIfNeeded()
    }

    func terminate() {
        readSource?.cancel()
        readSource = nil
        procSource?.cancel()
        procSource = nil
        if pid > 0 && !exited {
            kill(pid, SIGHUP)
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
        }
        if master >= 0 { close(master); master = -1 }
        pid = 0
    }

    // MARK: io

    private func received(_ bytes: [UInt8]) {
        emulator.feed(bytes)
        view.contentChanged()
    }

    func write(_ bytes: [UInt8]) {
        guard master >= 0, !bytes.isEmpty else { return }
        let fd = master
        writeQueue.async {
            var offset = 0
            while offset < bytes.count {
                let n = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
                if n < 0 {
                    if errno == EAGAIN || errno == EINTR { usleep(1000); continue }
                    break
                }
                offset += n
            }
        }
    }

    func send(_ s: String) { write(Array(s.utf8)) }

    func resizePTY(cols: Int, rows: Int, width: CGFloat, height: CGFloat) {
        emulator.resize(cols: cols, rows: rows)
        guard master >= 0 else { return }
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols),
                           ws_xpixel: UInt16(max(width, 1)), ws_ypixel: UInt16(max(height, 1)))
        _ = ioctl(master, UInt(TIOCSWINSZ), &size)
    }

    func apply(settings: PanelSettings, theme: Theme) {
        shellPath = settings.shell
        view.configure(fontSize: CGFloat(settings.termFontSize),
                       cursor: settings.cursor,
                       padding: CGFloat(min(max(settings.padding, 4), 40)),
                       theme: theme,
                       accent: theme.accentNS(settings.accent))
    }
}

// MARK: - View

final class TerminalNSView: NSView {
    weak var controller: TerminalController?
    var emulator: TerminalEmulator!
    var onFocus: (() -> Void)?

    private(set) var cols = 0
    private(set) var rows = 0
    private var cellW: CGFloat = 8
    private var cellH: CGFloat = 16
    private var fontAscent: CGFloat = 12
    private var fontSize: CGFloat = 12.5
    private var pad: CGFloat = 12
    private var cursorStyle: CursorStyle = .block
    private var accent = NSColor.systemGreen
    private var defaultFG = NSColor.white
    private var defaultBG = NSColor.black
    private var isDarkTheme = true
    private var palette: [NSColor] = []

    private var fontRegular = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    private var fontBold = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .bold)
    private var fontItalic = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    private var fontBoldItalic = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .bold)

    private var scrollOffset = 0
    private var scrollAccum: CGFloat = 0
    private var cursorPhase = true
    private var blinkTimer: Timer?

    private struct GridPoint: Equatable { var col: Int; var row: Int }
    private var selAnchor: GridPoint?
    private var selHead: GridPoint?
    private var mouseButtonDown: Int?
    private var lastMouseReport: GridPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([.fileURL])
        rebuildFonts()
        startBlink()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { blinkTimer?.invalidate() }

    // MARK: configuration

    func configure(fontSize size: CGFloat, cursor: CursorStyle, padding: CGFloat, theme: Theme, accent a: NSColor) {
        var needsLayout = false
        if size != fontSize { fontSize = size; rebuildFonts(); needsLayout = true }
        if padding != pad { pad = padding; needsLayout = true }
        cursorStyle = cursor
        accent = a
        defaultFG = NSColor(hex: theme.termForeground)
        defaultBG = NSColor(hex: theme.termBackground)
        isDarkTheme = theme.isDark
        palette = Self.makePalette(theme)
        if needsLayout { recomputeGrid() }
        needsDisplay = true
    }

    private static func makePalette(_ theme: Theme) -> [NSColor] {
        var p: [NSColor] = theme.ansi.map { NSColor(hex: $0) }
        let steps: [CGFloat] = [0, 95, 135, 175, 215, 255]
        for r in 0..<6 { for g in 0..<6 { for b in 0..<6 {
            p.append(NSColor(srgbRed: steps[r] / 255, green: steps[g] / 255, blue: steps[b] / 255, alpha: 1))
        } } }
        for i in 0..<24 {
            let v = CGFloat(8 + i * 10) / 255
            p.append(NSColor(srgbRed: v, green: v, blue: v, alpha: 1))
        }
        return p
    }

    private func rebuildFonts() {
        fontRegular = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        fontBold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let fm = NSFontManager.shared
        fontItalic = fm.convert(fontRegular, toHaveTrait: .italicFontMask)
        fontBoldItalic = fm.convert(fontBold, toHaveTrait: .italicFontMask)
        let adv = ("M" as NSString).size(withAttributes: [.font: fontRegular]).width
        cellW = adv
        let natural = fontRegular.ascender - fontRegular.descender + fontRegular.leading
        cellH = ceil(natural * 1.14)
        fontAscent = fontRegular.ascender + (cellH - natural) / 2
    }

    // MARK: grid

    override func layout() {
        super.layout()
        recomputeGrid()
        controller?.startIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recomputeGrid()
    }

    private func recomputeGrid() {
        guard cellW > 0, cellH > 0, bounds.width > 0, bounds.height > 0 else { return }
        let newCols = max(Int((bounds.width - pad * 2) / cellW), 2)
        let newRows = max(Int((bounds.height - pad * 1.5) / cellH), 2)
        if newCols != cols || newRows != rows {
            cols = newCols
            rows = newRows
            controller?.resizePTY(cols: cols, rows: rows, width: bounds.width, height: bounds.height)
            scrollOffset = min(scrollOffset, emulator.scrollback.count)
            needsDisplay = true
        }
    }

    // MARK: change notifications

    func contentChanged() {
        if scrollOffset > 0 && !emulator.usingAlt {
            scrollOffset = min(scrollOffset, emulator.scrollback.count)
        }
        if emulator.usingAlt { scrollOffset = 0 }
        needsDisplay = true
    }

    func scrollbackTrimmed(_ n: Int) {
        selAnchor = nil
        selHead = nil
        scrollOffset = min(scrollOffset, emulator.scrollback.count)
    }

    // MARK: focus + blink

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?(); cursorPhase = true; needsDisplay = true }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    private func startBlink() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            guard let self, self.window?.firstResponder === self, self.window?.isKeyWindow == true else { return }
            self.cursorPhase.toggle()
            self.setNeedsDisplay(self.cursorRect().insetBy(dx: -2, dy: -2))
        }
    }

    // MARK: colors

    private func color(_ c: TCol, fallback: NSColor, bold: Bool = false) -> NSColor {
        switch c.kind {
        case 1:
            var i = Int(c.r)
            if bold && i < 8 { i += 8 }
            return i < palette.count ? palette[i] : fallback
        case 2:
            return NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
        default:
            return fallback
        }
    }

    private func resolve(_ cell: TCell) -> (fg: NSColor, bg: NSColor?) {
        var fg = color(cell.fg, fallback: defaultFG, bold: cell.attr.contains(.bold))
        var bg: NSColor? = cell.bg.kind == 0 ? nil : color(cell.bg, fallback: defaultBG)
        if cell.attr.contains(.inverse) {
            let f = fg
            fg = bg ?? defaultBG
            bg = f
        }
        if cell.attr.contains(.dim) { fg = fg.withAlphaComponent(0.62) }
        if cell.attr.contains(.hidden) { fg = .clear }
        return (fg, bg)
    }

    // MARK: drawing

    private var firstAbsoluteRow: Int {
        emulator.usingAlt ? 0 : emulator.scrollback.count - scrollOffset
    }

    private func cellOrigin(col: Int, visibleRow: Int) -> NSPoint {
        NSPoint(x: pad + CGFloat(col) * cellW, y: pad * 0.75 + CGFloat(visibleRow) * cellH)
    }

    private func cursorRect() -> NSRect {
        let o = cellOrigin(col: emulator.cx, visibleRow: emulator.cy)
        return NSRect(x: o.x, y: o.y, width: cellW, height: cellH)
    }

    private func selectionBounds() -> (GridPoint, GridPoint)? {
        guard let a = selAnchor, let b = selHead, a != b else { return nil }
        if a.row < b.row || (a.row == b.row && a.col <= b.col) { return (a, b) }
        return (b, a)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard emulator != nil, !palette.isEmpty else { return }
        let first = firstAbsoluteRow
        let sel = selectionBounds()
        let selColor = accent.withAlphaComponent(isDarkTheme ? 0.34 : 0.28)

        for r in 0..<min(rows, emulator.rows) {
            let y = pad * 0.75 + CGFloat(r) * cellH
            if y + cellH < dirtyRect.minY || y > dirtyRect.maxY { continue }
            guard let line = emulator.line(at: first + r) else { continue }
            let absRow = first + r

            // backgrounds
            var x = 0
            let limit = min(line.count, cols)
            while x < limit {
                let (_, bg) = resolve(line[x])
                var end = x + 1
                while end < limit, sameBG(resolve(line[end]).bg, bg) { end += 1 }
                if let bg {
                    bg.setFill()
                    NSRect(x: pad + CGFloat(x) * cellW, y: y, width: CGFloat(end - x) * cellW + 0.5, height: cellH).fill()
                }
                x = end
            }

            // selection
            if let (a, b) = sel, absRow >= a.row, absRow <= b.row {
                let c0 = absRow == a.row ? a.col : 0
                let c1 = absRow == b.row ? b.col : cols
                if c1 > c0 {
                    selColor.setFill()
                    NSRect(x: pad + CGFloat(c0) * cellW, y: y, width: CGFloat(c1 - c0) * cellW, height: cellH).fill()
                }
            }

            // text
            x = 0
            while x < limit {
                let cell = line[x]
                if cell.wide == 2 || (cell.ch == 32 && !cell.attr.contains(.underline) && !cell.attr.contains(.strike)) {
                    x += 1
                    continue
                }
                let (fg, _) = resolve(cell)
                if cell.wide == 1 {
                    drawText(String(scalar(cell.ch)), at: NSPoint(x: pad + CGFloat(x) * cellW, y: y), cell: cell, fg: fg)
                    x += 2
                    continue
                }
                var end = x + 1
                var text = String(scalar(cell.ch))
                while end < limit {
                    let n = line[end]
                    if n.wide != 0 { break }
                    if n.attr != cell.attr || n.fg != cell.fg || n.bg != cell.bg { break }
                    text.unicodeScalars.append(scalar(n.ch))
                    end += 1
                }
                drawText(text, at: NSPoint(x: pad + CGFloat(x) * cellW, y: y), cell: cell, fg: fg)
                x = end
            }
        }

        drawCursor()
        drawScrollIndicator()
    }

    private func sameBG(_ a: NSColor?, _ b: NSColor?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let x?, let y?): return x == y
        default: return false
        }
    }

    private func scalar(_ v: UInt32) -> Unicode.Scalar { Unicode.Scalar(v) ?? " " }

    private func drawText(_ text: String, at origin: NSPoint, cell: TCell, fg: NSColor) {
        let bold = cell.attr.contains(.bold)
        let italic = cell.attr.contains(.italic)
        let font = bold && italic ? fontBoldItalic : bold ? fontBold : italic ? fontItalic : fontRegular
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
        if cell.attr.contains(.underline) { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if cell.attr.contains(.strike) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let drawY = origin.y + (cellH - (fontRegular.ascender - fontRegular.descender + fontRegular.leading)) / 2
        NSAttributedString(string: text, attributes: attrs).draw(at: NSPoint(x: origin.x, y: drawY))
    }

    private func drawCursor() {
        guard emulator.cursorVisible, scrollOffset == 0 else { return }
        let rect = cursorRect()
        let focused = window?.firstResponder === self && window?.isKeyWindow == true
        guard rect.maxY <= bounds.maxY + cellH else { return }

        if !focused {
            accent.withAlphaComponent(0.8).setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
            return
        }
        guard cursorPhase else { return }

        switch cursorStyle {
        case .block:
            accent.withAlphaComponent(0.92).setFill()
            rect.fill()
            if emulator.cy < emulator.screen.count, emulator.cx < emulator.screen[emulator.cy].count {
                let cell = emulator.screen[emulator.cy][emulator.cx]
                if cell.ch != 32 && cell.ch != 0 {
                    drawText(String(scalar(cell.ch)), at: rect.origin, cell: TCell(ch: cell.ch, fg: cell.fg, bg: cell.bg, attr: cell.attr.subtracting([.underline, .strike]), wide: 0), fg: defaultBG)
                }
            }
        case .bar:
            accent.setFill()
            NSRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height).fill()
        case .underline:
            accent.setFill()
            NSRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 2).fill()
        }
    }

    private func drawScrollIndicator() {
        guard scrollOffset > 0, !emulator.usingAlt else { return }
        let total = CGFloat(emulator.scrollback.count + emulator.rows)
        let visible = CGFloat(emulator.rows)
        let h = max(bounds.height * visible / total, 24)
        let progress = 1 - CGFloat(scrollOffset) / CGFloat(max(emulator.scrollback.count, 1))
        let y = (bounds.height - h) * progress
        defaultFG.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.width - 7, y: y, width: 3, height: h), xRadius: 1.5, yRadius: 1.5).fill()
    }

    // MARK: keyboard

    override func keyDown(with event: NSEvent) {
        guard let controller else { return }
        if controller.exited { controller.restart(); return }
        if scrollOffset != 0 { scrollOffset = 0; needsDisplay = true }
        selAnchor = nil
        selHead = nil
        cursorPhase = true

        let flags = event.modifierFlags.intersection([.shift, .option, .control, .command])
        let app = emulator.appCursorKeys
        let shift = flags.contains(.shift), opt = flags.contains(.option), ctrl = flags.contains(.control)
        let mod = 1 + (shift ? 1 : 0) + (opt ? 2 : 0) + (ctrl ? 4 : 0)

        func csi(_ final: String) -> String {
            if mod > 1 { return "\u{1B}[1;\(mod)\(final)" }
            return app ? "\u{1B}O\(final)" : "\u{1B}[\(final)"
        }
        func tilde(_ n: Int) -> String { mod > 1 ? "\u{1B}[\(n);\(mod)~" : "\u{1B}[\(n)~" }

        switch event.keyCode {
        case 36, 76: controller.send("\r"); return
        case 48: controller.send(shift ? "\u{1B}[Z" : "\t"); return
        case 51:
            if flags.contains(.command) { controller.send("\u{15}") }
            else { controller.send(opt ? "\u{1B}\u{7F}" : "\u{7F}") }
            return
        case 117: controller.send(tilde(3)); return
        case 53: controller.send("\u{1B}"); return
        case 126: controller.send(csi("A")); return
        case 125: controller.send(csi("B")); return
        case 124:
            if flags == .option { controller.send("\u{1B}f") }
            else if flags.contains(.command) { controller.send("\u{05}") }
            else { controller.send(csi("C")) }
            return
        case 123:
            if flags == .option { controller.send("\u{1B}b") }
            else if flags.contains(.command) { controller.send("\u{01}") }
            else { controller.send(csi("D")) }
            return
        case 115: controller.send(mod > 1 ? "\u{1B}[1;\(mod)H" : (app ? "\u{1B}OH" : "\u{1B}[H")); return
        case 119: controller.send(mod > 1 ? "\u{1B}[1;\(mod)F" : (app ? "\u{1B}OF" : "\u{1B}[F")); return
        case 116: controller.send(tilde(5)); return
        case 121: controller.send(tilde(6)); return
        case 114: controller.send(tilde(2)); return
        case 122: controller.send("\u{1B}OP"); return
        case 120: controller.send("\u{1B}OQ"); return
        case 99: controller.send("\u{1B}OR"); return
        case 118: controller.send("\u{1B}OS"); return
        case 96: controller.send("\u{1B}[15~"); return
        case 97: controller.send("\u{1B}[17~"); return
        case 98: controller.send("\u{1B}[18~"); return
        case 100: controller.send("\u{1B}[19~"); return
        case 101: controller.send("\u{1B}[20~"); return
        case 109: controller.send("\u{1B}[21~"); return
        case 103: controller.send("\u{1B}[23~"); return
        case 111: controller.send("\u{1B}[24~"); return
        default: break
        }

        if ctrl, let ch = event.charactersIgnoringModifiers, ch == " " || ch == "@" {
            controller.send("\u{0}")
            return
        }
        if opt, !ctrl, let base = event.charactersIgnoringModifiers, base.unicodeScalars.count == 1,
           let u = base.unicodeScalars.first, u.isASCII {
            controller.send("\u{1B}" + base)
            return
        }
        if let chars = event.characters, !chars.isEmpty {
            // ignore private-use function key codepoints
            if let u = chars.unicodeScalars.first, (0xF700...0xF8FF).contains(u.value) { return }
            controller.send(chars)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == .command {
            switch key {
            case "c":
                if selectionBounds() != nil { copy(nil); return true }
                return true
            case "v": paste(nil); return true
            case "a": selectAll(nil); return true
            case "k": clearBuffer(); return true
            default: break
            }
        }
        // Cmd + arrows/backspace are terminal line editing keys
        if [123, 124, 51].contains(event.keyCode) && flags == .command {
            keyDown(with: event)
            return true
        }
        return false
    }

    @objc func copy(_ sender: Any?) {
        guard let text = selectedText(), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        guard let s = NSPasteboard.general.string(forType: .string), let controller else { return }
        pasteText(s, controller: controller)
    }

    private func pasteText(_ raw: String, controller: TerminalController) {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        if emulator.bracketedPaste { controller.send("\u{1B}[200~" + text + "\u{1B}[201~") }
        else { controller.send(text) }
        scrollOffset = 0
        needsDisplay = true
    }

    override func selectAll(_ sender: Any?) {
        let first = firstAbsoluteRow
        selAnchor = GridPoint(col: 0, row: first)
        selHead = GridPoint(col: cols, row: first + rows - 1)
        needsDisplay = true
    }

    func clearBuffer() {
        controller?.send("\u{0C}")
        emulator.scrollback.removeAll()
        scrollOffset = 0
        selAnchor = nil
        selHead = nil
        needsDisplay = true
    }

    // MARK: selection text

    private func selectedText() -> String? {
        guard let (a, b) = selectionBounds() else { return nil }
        var out: [String] = []
        for r in a.row...b.row {
            guard let line = emulator.line(at: r) else { continue }
            let c0 = r == a.row ? a.col : 0
            let c1 = r == b.row ? min(b.col, line.count) : line.count
            var s = ""
            if c1 > c0 {
                for x in c0..<min(c1, line.count) where line[x].wide != 2 { s.unicodeScalars.append(scalar(line[x].ch == 0 ? 32 : line[x].ch)) }
            }
            while s.last == " " { s.removeLast() }
            out.append(s)
        }
        return out.joined(separator: "\n")
    }

    // MARK: mouse

    private func gridPoint(for event: NSEvent) -> GridPoint {
        let p = convert(event.locationInWindow, from: nil)
        let col = min(max(Int((p.x - pad) / cellW), 0), max(cols - 1, 0))
        let row = min(max(Int((p.y - pad * 0.75) / cellH), 0), max(rows - 1, 0))
        return GridPoint(col: col, row: firstAbsoluteRow + row)
    }

    private func visiblePoint(for event: NSEvent) -> GridPoint {
        let g = gridPoint(for: event)
        return GridPoint(col: g.col, row: g.row - firstAbsoluteRow)
    }

    private var reporting: Bool { emulator.mouseMode != 0 }

    private func report(button: Int, point: GridPoint, press: Bool, motion: Bool = false, event: NSEvent) {
        guard let controller else { return }
        var b = button
        if event.modifierFlags.contains(.shift) { b += 4 }
        if event.modifierFlags.contains(.option) { b += 8 }
        if event.modifierFlags.contains(.control) { b += 16 }
        if motion { b += 32 }
        if emulator.mouseSGR {
            controller.send("\u{1B}[<\(b);\(point.col + 1);\(point.row + 1)\(press ? "M" : "m")")
        } else {
            let cb = press ? b : 3
            let bytes: [UInt8] = [0x1B, 0x5B, 0x4D, UInt8(clamping: 32 + cb), UInt8(clamping: 32 + point.col + 1), UInt8(clamping: 32 + point.row + 1)]
            controller.write(bytes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let g = gridPoint(for: event)

        if reporting, !event.modifierFlags.contains(.option) {
            mouseButtonDown = 0
            lastMouseReport = visiblePoint(for: event)
            report(button: 0, point: lastMouseReport!, press: true, event: event)
            return
        }

        if event.modifierFlags.contains(.command), let url = url(at: g) {
            NSWorkspace.shared.open(url)
            return
        }

        switch event.clickCount {
        case 2:
            let (s, e) = wordRange(at: g)
            selAnchor = GridPoint(col: s, row: g.row)
            selHead = GridPoint(col: e, row: g.row)
        case 3:
            selAnchor = GridPoint(col: 0, row: g.row)
            selHead = GridPoint(col: cols, row: g.row)
        default:
            selAnchor = g
            selHead = g
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if reporting, !event.modifierFlags.contains(.option) {
            let v = visiblePoint(for: event)
            if emulator.mouseMode >= 1002, v != lastMouseReport {
                lastMouseReport = v
                report(button: 0, point: v, press: true, motion: true, event: event)
            }
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        if p.y < 0 { scrollOffset = min(scrollOffset + 1, emulator.scrollback.count) }
        else if p.y > bounds.height { scrollOffset = max(scrollOffset - 1, 0) }
        selHead = gridPoint(for: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if reporting, mouseButtonDown != nil {
            report(button: 0, point: visiblePoint(for: event), press: false, event: event)
            mouseButtonDown = nil
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if reporting, !event.modifierFlags.contains(.option) {
            report(button: 2, point: visiblePoint(for: event), press: true, event: event)
            return
        }
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        if reporting, !event.modifierFlags.contains(.option) {
            report(button: 2, point: visiblePoint(for: event), press: false, event: event)
            return
        }
        super.rightMouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let precise = event.hasPreciseScrollingDeltas
        let delta = event.scrollingDeltaY
        if reporting, !event.modifierFlags.contains(.option) {
            scrollAccum += precise ? delta / cellH : delta
            let lines = Int(scrollAccum)
            if lines != 0 {
                scrollAccum -= CGFloat(lines)
                for _ in 0..<min(abs(lines), 6) {
                    report(button: lines > 0 ? 64 : 65, point: visiblePoint(for: event), press: true, event: event)
                }
            }
            return
        }
        if emulator.usingAlt {
            scrollAccum += precise ? delta / cellH : delta
            let lines = Int(scrollAccum)
            if lines != 0 {
                scrollAccum -= CGFloat(lines)
                let key = lines > 0 ? (emulator.appCursorKeys ? "\u{1B}OA" : "\u{1B}[A") : (emulator.appCursorKeys ? "\u{1B}OB" : "\u{1B}[B")
                for _ in 0..<min(abs(lines), 8) { controller?.send(key) }
            }
            return
        }
        scrollAccum += precise ? delta / cellH : delta * 3
        let lines = Int(scrollAccum)
        if lines != 0 {
            scrollAccum -= CGFloat(lines)
            scrollOffset = min(max(scrollOffset + lines, 0), emulator.scrollback.count)
            needsDisplay = true
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        let copyItem = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        copyItem.isEnabled = selectionBounds() != nil
        m.addItem(copyItem)
        m.addItem(NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: ""))
        m.addItem(NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: ""))
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Clear Buffer", action: #selector(clearBufferAction), keyEquivalent: ""))
        m.items.forEach { $0.target = self }
        return m
    }

    @objc private func clearBufferAction() { clearBuffer() }

    // MARK: words + links

    private func wordRange(at g: GridPoint) -> (Int, Int) {
        guard let line = emulator.line(at: g.row) else { return (g.col, g.col) }
        func isWordChar(_ c: TCell) -> Bool {
            guard let u = Unicode.Scalar(c.ch), c.ch != 0 else { return true }
            if c.ch == 32 { return false }
            return !"\"'`()[]{}<>|;,".unicodeScalars.contains(u)
        }
        var s = min(g.col, line.count - 1)
        var e = s
        if !isWordChar(line[s]) { return (s, s + 1) }
        while s > 0, isWordChar(line[s - 1]) { s -= 1 }
        while e + 1 < line.count, isWordChar(line[e + 1]) { e += 1 }
        return (s, e + 1)
    }

    private func url(at g: GridPoint) -> URL? {
        guard let line = emulator.line(at: g.row) else { return nil }
        var text = ""
        var map: [Int] = []
        for (i, c) in line.enumerated() where c.wide != 2 {
            text.unicodeScalars.append(scalar(c.ch == 0 ? 32 : c.ch))
            map.append(i)
        }
        guard let re = try? NSRegularExpression(pattern: "(https?://|file://)[^\\s<>\"')\\]]+") else { return nil }
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let lo = m.range.location, hi = NSMaxRange(m.range)
            if lo < map.count, map[lo] <= g.col, g.col < (hi - 1 < map.count ? map[hi - 1] + 1 : cols) {
                return URL(string: ns.substring(with: m.range))
            }
        }
        return nil
    }

    // MARK: drag and drop of files

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                               options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let controller else { return false }
        let quoted = urls.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        pasteText(quoted + " ", controller: controller)
        return true
    }
}

// MARK: - SwiftUI

struct TerminalRepresentable: NSViewRepresentable {
    let panel: Panel
    let theme: Theme

    func makeNSView(context: Context) -> TerminalNSView {
        let controller = Runtime.shared.terminal(for: panel)
        controller.apply(settings: panel.settings, theme: theme)
        return controller.view
    }

    func updateNSView(_ view: TerminalNSView, context: Context) {
        Runtime.shared.terminal(for: panel).apply(settings: panel.settings, theme: theme)
    }
}

struct TerminalPanelView: View {
    @Bindable var panel: Panel
    @Environment(\.theme) private var theme

    var body: some View {
        TerminalRepresentable(panel: panel, theme: theme)
            .padding(.bottom, 4)
    }
}
