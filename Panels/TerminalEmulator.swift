import Foundation

// MARK: - Cell model

struct TCol: Equatable {
    var kind: UInt8 = 0      // 0 default, 1 indexed, 2 rgb
    var r: UInt8 = 0
    var g: UInt8 = 0
    var b: UInt8 = 0

    static let none = TCol()
    static func idx(_ i: Int) -> TCol { TCol(kind: 1, r: UInt8(clamping: i), g: 0, b: 0) }
    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> TCol {
        TCol(kind: 2, r: UInt8(clamping: r), g: UInt8(clamping: g), b: UInt8(clamping: b))
    }
}

struct TAttr: OptionSet, Equatable {
    let rawValue: UInt8
    static let bold = TAttr(rawValue: 1)
    static let dim = TAttr(rawValue: 2)
    static let italic = TAttr(rawValue: 4)
    static let underline = TAttr(rawValue: 8)
    static let blink = TAttr(rawValue: 16)
    static let inverse = TAttr(rawValue: 32)
    static let hidden = TAttr(rawValue: 64)
    static let strike = TAttr(rawValue: 128)
}

struct TCell: Equatable {
    var ch: UInt32 = 32
    var fg = TCol()
    var bg = TCol()
    var attr: TAttr = []
    var wide: UInt8 = 0       // 0 normal, 1 wide lead, 2 wide continuation
}

// MARK: - Width

@inline(__always)
func termCharWidth(_ u: UInt32) -> Int {
    if u < 0x300 { return 1 }
    if (0x300...0x36F).contains(u) || (0x200B...0x200F).contains(u) || (0xFE00...0xFE0F).contains(u)
        || (0x20D0...0x20FF).contains(u) || u == 0x200D || (0x1AB0...0x1AFF).contains(u) { return 0 }
    if (0x1100...0x115F).contains(u) || (0x2E80...0xA4CF).contains(u) || (0xAC00...0xD7A3).contains(u)
        || (0xF900...0xFAFF).contains(u) || (0xFE30...0xFE6F).contains(u) || (0xFF00...0xFF60).contains(u)
        || (0xFFE0...0xFFE6).contains(u) || (0x1F300...0x1F64F).contains(u) || (0x1F900...0x1F9FF).contains(u)
        || (0x1F680...0x1F6FF).contains(u) || (0x20000...0x3FFFD).contains(u) { return 2 }
    return 1
}

private let decGraphics: [UInt32: UInt32] = [
    0x60: 0x25C6, 0x61: 0x2592, 0x66: 0xB0, 0x67: 0xB1, 0x6A: 0x2518, 0x6B: 0x2510, 0x6C: 0x250C,
    0x6D: 0x2514, 0x6E: 0x253C, 0x6F: 0x23BA, 0x70: 0x23BB, 0x71: 0x2500, 0x72: 0x23BC, 0x73: 0x23BD,
    0x74: 0x251C, 0x75: 0x2524, 0x76: 0x2534, 0x77: 0x252C, 0x78: 0x2502, 0x79: 0x2264, 0x7A: 0x2265,
    0x7B: 0x3C0, 0x7C: 0x2260, 0x7D: 0xA3, 0x7E: 0xB7
]

// MARK: - Emulator

final class TerminalEmulator {
    private(set) var cols: Int
    private(set) var rows: Int

    var screen: [[TCell]]
    private var mainScreenBackup: [[TCell]]?
    var scrollback: [[TCell]] = []
    var maxScrollback = 5000
    private(set) var usingAlt = false

    var cx = 0
    var cy = 0
    private var wrapPending = false

    private var curFG = TCol()
    private var curBG = TCol()
    private var curAttr: TAttr = []

    private var scrollTop = 0
    private var scrollBottom: Int

    private struct Saved { var x = 0, y = 0, fg = TCol(), bg = TCol(), attr: TAttr = [], wrap = false, g0Graphics = false }
    private var saved = Saved()
    private var savedMain = Saved()

    private(set) var appCursorKeys = false
    private(set) var bracketedPaste = false
    private(set) var cursorVisible = true
    private(set) var mouseMode = 0            // 0 off, 1000 press/release, 1002 drag, 1003 any
    private(set) var mouseSGR = false
    private var autoWrap = true
    private var originMode = false
    private var insertMode = false
    private var g0Graphics = false
    private var tabStops: [Bool]
    private var lastPrinted: UInt32 = 32

    var title = ""
    var onResponse: (([UInt8]) -> Void)?
    var onTitle: ((String) -> Void)?
    var onBell: (() -> Void)?
    var onScrollbackTrim: ((Int) -> Void)?

    // parser
    private enum PState { case ground, escape, escapeInter, csi, osc, oscEscape, ignoreString, ignoreStringEscape }
    private var state: PState = .ground
    private var params: [Int] = []
    private var currentParam: Int = -1
    private var hasParam = false
    private var privMarker: UInt8 = 0
    private var inter: [UInt8] = []
    private var oscBuffer: [UInt8] = []
    private var utf8Need = 0
    private var utf8Acc: UInt32 = 0

    init(cols: Int, rows: Int) {
        self.cols = max(cols, 2)
        self.rows = max(rows, 2)
        scrollBottom = max(rows, 2) - 1
        tabStops = Array(repeating: false, count: max(cols, 2))
        screen = []
        screen = (0..<self.rows).map { _ in Array(repeating: TCell(), count: self.cols) }
        resetTabs()
    }

    // MARK: helpers

    private func blankCell() -> TCell { TCell(ch: 32, fg: TCol(), bg: curBG, attr: [], wide: 0) }
    private func blankRow() -> [TCell] { Array(repeating: blankCell(), count: cols) }

    private func resetTabs() {
        tabStops = (0..<cols).map { $0 % 8 == 0 }
    }

    func line(at absolute: Int) -> [TCell]? {
        if usingAlt {
            return absolute >= 0 && absolute < rows ? screen[absolute] : nil
        }
        if absolute < scrollback.count { return absolute >= 0 ? scrollback[absolute] : nil }
        let r = absolute - scrollback.count
        return r < rows ? screen[r] : nil
    }

    var totalLines: Int { usingAlt ? rows : scrollback.count + rows }

    // MARK: resize

    func resize(cols newCols: Int, rows newRows: Int) {
        let nc = max(newCols, 2)
        let nr = max(newRows, 2)
        if nc == cols && nr == rows { return }

        // columns: pad or truncate every row
        func fit(_ row: [TCell]) -> [TCell] {
            if row.count == nc { return row }
            if row.count > nc { return Array(row[0..<nc]) }
            return row + Array(repeating: TCell(), count: nc - row.count)
        }
        screen = screen.map(fit)
        if !usingAlt { scrollback = scrollback.map { $0.count > nc ? Array($0[0..<nc]) : $0 } }
        mainScreenBackup = mainScreenBackup?.map(fit)

        // rows
        if nr < rows {
            let drop = rows - nr
            if usingAlt {
                screen.removeLast(drop)
                cy = min(cy, nr - 1)
            } else {
                // remove blank lines from the bottom first, then push top lines to scrollback
                var removedBottom = 0
                while removedBottom < drop, screen.count > cy + 1, screen.last.map(isBlank) ?? false {
                    screen.removeLast()
                    removedBottom += 1
                }
                let remaining = drop - removedBottom
                for _ in 0..<remaining {
                    scrollback.append(screen.removeFirst())
                    cy = max(cy - 1, 0)
                }
                trimScrollback()
            }
        } else if nr > rows {
            let add = nr - rows
            if !usingAlt && !scrollback.isEmpty {
                let pull = min(add, scrollback.count)
                for _ in 0..<pull {
                    screen.insert(fit(scrollback.removeLast()), at: 0)
                    cy += 1
                }
                for _ in 0..<(add - pull) { screen.append(Array(repeating: TCell(), count: nc)) }
            } else {
                for _ in 0..<add { screen.append(Array(repeating: TCell(), count: nc)) }
            }
        }

        cols = nc
        rows = nr
        scrollTop = 0
        scrollBottom = nr - 1
        cx = min(cx, nc - 1)
        cy = min(max(cy, 0), nr - 1)
        wrapPending = false
        resetTabs()
    }

    private func isBlank(_ row: [TCell]) -> Bool {
        row.allSatisfy { $0.ch == 32 && $0.bg.kind == 0 }
    }

    private func trimScrollback() {
        if scrollback.count > maxScrollback {
            let n = scrollback.count - maxScrollback
            scrollback.removeFirst(n)
            onScrollbackTrim?(n)
        }
    }

    // MARK: feed

    func feed(_ data: [UInt8]) {
        for b in data { process(b) }
    }

    private func process(_ b: UInt8) {
        switch state {
        case .ground:
            ground(b)
        case .escape:
            escape(b)
        case .escapeInter:
            if b >= 0x20 && b <= 0x2F { inter.append(b); return }
            escapeIntermediateFinal(b)
            state = .ground
        case .csi:
            csi(b)
        case .osc:
            if b == 0x07 { finishOSC(); state = .ground }
            else if b == 0x1B { state = .oscEscape }
            else if b == 0x9C { finishOSC(); state = .ground }
            else if oscBuffer.count < 4096 { oscBuffer.append(b) }
        case .oscEscape:
            if b == 0x5C { finishOSC() }
            state = .ground
        case .ignoreString:
            if b == 0x07 || b == 0x9C { state = .ground }
            else if b == 0x1B { state = .ignoreStringEscape }
        case .ignoreStringEscape:
            state = .ground
        }
    }

    private func ground(_ b: UInt8) {
        if utf8Need > 0 {
            if b & 0xC0 == 0x80 {
                utf8Acc = (utf8Acc << 6) | UInt32(b & 0x3F)
                utf8Need -= 1
                if utf8Need == 0 { put(utf8Acc) }
                return
            }
            utf8Need = 0   // malformed, fall through and reprocess
        }
        switch b {
        case 0x00: break
        case 0x07: onBell?()
        case 0x08: if cx > 0 { cx -= 1 }; wrapPending = false
        case 0x09: tab()
        case 0x0A, 0x0B, 0x0C: lineFeed(); wrapPending = false
        case 0x0D: cx = 0; wrapPending = false
        case 0x0E, 0x0F: break
        case 0x1B: state = .escape; inter.removeAll()
        case 0x20...0x7E: put(UInt32(b))
        case 0xC2...0xDF: utf8Need = 1; utf8Acc = UInt32(b & 0x1F)
        case 0xE0...0xEF: utf8Need = 2; utf8Acc = UInt32(b & 0x0F)
        case 0xF0...0xF4: utf8Need = 3; utf8Acc = UInt32(b & 0x07)
        case 0x9B: beginCSI()
        default: break
        }
    }

    private func beginCSI() {
        state = .csi
        params.removeAll(keepingCapacity: true)
        currentParam = -1
        hasParam = false
        privMarker = 0
        inter.removeAll(keepingCapacity: true)
    }

    private func escape(_ b: UInt8) {
        switch b {
        case 0x5B: beginCSI()
        case 0x5D: state = .osc; oscBuffer.removeAll()
        case 0x50, 0x58, 0x5E, 0x5F: state = .ignoreString
        case 0x20...0x2F: inter = [b]; state = .escapeInter
        case 0x37: saveCursor(); state = .ground
        case 0x38: restoreCursor(); state = .ground
        case 0x44: lineFeed(); state = .ground
        case 0x45: cx = 0; lineFeed(); state = .ground
        case 0x4D: reverseIndex(); state = .ground
        case 0x48: if cx < tabStops.count { tabStops[cx] = true }; state = .ground
        case 0x63: fullReset(); state = .ground
        case 0x3D, 0x3E: state = .ground
        case 0x1B: break
        default: state = .ground
        }
    }

    private func escapeIntermediateFinal(_ b: UInt8) {
        guard let i = inter.first else { return }
        if i == 0x28 {          // designate G0
            g0Graphics = (b == 0x30)
        } else if i == 0x23, b == 0x38 {   // DECALN
            for r in 0..<rows { screen[r] = Array(repeating: TCell(ch: 0x45), count: cols) }
        }
    }

    private func csi(_ b: UInt8) {
        switch b {
        case 0x30...0x39:
            hasParam = true
            currentParam = (currentParam < 0 ? 0 : currentParam) * 10 + Int(b - 0x30)
            if currentParam > 100_000 { currentParam = 100_000 }
        case 0x3B, 0x3A:
            params.append(hasParam ? currentParam : -1)
            currentParam = -1
            hasParam = false
        case 0x3C...0x3F:
            privMarker = b
        case 0x20...0x2F:
            inter.append(b)
        case 0x40...0x7E:
            if hasParam || !params.isEmpty { params.append(hasParam ? currentParam : -1) }
            dispatchCSI(b)
            state = .ground
        case 0x1B:
            state = .escape
        case 0x18, 0x1A:
            state = .ground
        case 0x0A, 0x0D, 0x08, 0x09, 0x0B, 0x0C:
            ground(b)
        default:
            break
        }
    }

    @inline(__always) private func p(_ i: Int, _ def: Int) -> Int {
        i < params.count && params[i] >= 0 ? params[i] : def
    }
    @inline(__always) private func pn(_ i: Int) -> Int { max(p(i, 1), 1) }

    // MARK: CSI dispatch

    private func dispatchCSI(_ f: UInt8) {
        if privMarker == 0x3F {
            switch f {
            case 0x68: setPrivateModes(true)
            case 0x6C: setPrivateModes(false)
            default: break
            }
            return
        }
        if privMarker == 0x3E {
            if f == 0x63 { respond("\u{1B}[>0;276;0c") }
            return
        }
        if privMarker != 0 { return }
        if !inter.isEmpty {
            // DECSCUSR and friends: ignore
            return
        }

        switch f {
        case 0x41: cy = max(cy - pn(0), originMode ? scrollTop : 0); wrapPending = false
        case 0x42: cy = min(cy + pn(0), originMode ? scrollBottom : rows - 1); wrapPending = false
        case 0x43: cx = min(cx + pn(0), cols - 1); wrapPending = false
        case 0x44: cx = max(cx - pn(0), 0); wrapPending = false
        case 0x45: cy = min(cy + pn(0), rows - 1); cx = 0; wrapPending = false
        case 0x46: cy = max(cy - pn(0), 0); cx = 0; wrapPending = false
        case 0x47, 0x60: cx = min(max(p(0, 1) - 1, 0), cols - 1); wrapPending = false
        case 0x48, 0x66:
            moveTo(row: p(0, 1) - 1, col: p(1, 1) - 1)
        case 0x64: moveTo(row: p(0, 1) - 1, col: cx, relativeCol: true)
        case 0x65: cy = min(cy + pn(0), rows - 1); wrapPending = false
        case 0x49:
            for _ in 0..<pn(0) { tab() }
        case 0x5A:
            for _ in 0..<pn(0) { backTab() }
        case 0x4A: eraseDisplay(p(0, 0))
        case 0x4B: eraseLine(p(0, 0))
        case 0x4C: insertLines(pn(0))
        case 0x4D: deleteLines(pn(0))
        case 0x50: deleteChars(pn(0))
        case 0x40: insertChars(pn(0))
        case 0x58: eraseChars(pn(0))
        case 0x53: scrollUp(pn(0))
        case 0x54: scrollDown(pn(0))
        case 0x6D: sgr()
        case 0x72:
            let t = max(p(0, 1) - 1, 0)
            let bt = min(p(1, rows) - 1, rows - 1)
            if t < bt { scrollTop = t; scrollBottom = bt; moveTo(row: 0, col: 0) }
        case 0x73: saveCursor()
        case 0x75: restoreCursor()
        case 0x68: if p(0, 0) == 4 { insertMode = true }
        case 0x6C: if p(0, 0) == 4 { insertMode = false }
        case 0x6E:
            if p(0, 0) == 5 { respond("\u{1B}[0n") }
            else if p(0, 0) == 6 { respond("\u{1B}[\(cy + 1 - (originMode ? scrollTop : 0));\(cx + 1)R") }
        case 0x63: if p(0, 0) == 0 { respond("\u{1B}[?1;2c") }
        case 0x67:
            if p(0, 0) == 0 { if cx < tabStops.count { tabStops[cx] = false } }
            else if p(0, 0) == 3 { tabStops = Array(repeating: false, count: cols) }
        case 0x62:
            for _ in 0..<min(pn(0), 500) { put(lastPrinted) }
        default: break
        }
    }

    private func moveTo(row: Int, col: Int, relativeCol: Bool = false) {
        let top = originMode ? scrollTop : 0
        let bottom = originMode ? scrollBottom : rows - 1
        cy = min(max(row + top, top), bottom)
        cx = min(max(col, 0), cols - 1)
        wrapPending = false
    }

    private func setPrivateModes(_ on: Bool) {
        for v in params {
            switch v {
            case 1: appCursorKeys = on
            case 6: originMode = on; moveTo(row: 0, col: 0)
            case 7: autoWrap = on
            case 25: cursorVisible = on
            case 47, 1047: on ? enterAlt(save: false) : exitAlt(restore: false)
            case 1049: on ? enterAlt(save: true) : exitAlt(restore: true)
            case 1000, 1002, 1003: mouseMode = on ? v : 0
            case 1006: mouseSGR = on
            case 2004: bracketedPaste = on
            default: break
            }
        }
    }

    private func respond(_ s: String) { onResponse?(Array(s.utf8)) }

    // MARK: SGR

    private func sgr() {
        if params.isEmpty { resetSGR(); return }
        var i = 0
        while i < params.count {
            let v = params[i] < 0 ? 0 : params[i]
            switch v {
            case 0: resetSGR()
            case 1: curAttr.insert(.bold)
            case 2: curAttr.insert(.dim)
            case 3: curAttr.insert(.italic)
            case 4, 21: curAttr.insert(.underline)
            case 5, 6: curAttr.insert(.blink)
            case 7: curAttr.insert(.inverse)
            case 8: curAttr.insert(.hidden)
            case 9: curAttr.insert(.strike)
            case 22: curAttr.remove([.bold, .dim])
            case 23: curAttr.remove(.italic)
            case 24: curAttr.remove(.underline)
            case 25: curAttr.remove(.blink)
            case 27: curAttr.remove(.inverse)
            case 28: curAttr.remove(.hidden)
            case 29: curAttr.remove(.strike)
            case 30...37: curFG = .idx(v - 30)
            case 38, 48:
                var col: TCol?
                if i + 1 < params.count {
                    let mode = params[i + 1]
                    if mode == 5, i + 2 < params.count {
                        col = .idx(max(params[i + 2], 0)); i += 2
                    } else if mode == 2 {
                        var j = i + 2
                        if j < params.count, params[j] < 0, j + 3 < params.count { j += 1 }
                        if j + 2 < params.count {
                            col = .rgb(max(params[j], 0), max(params[j + 1], 0), max(params[j + 2], 0))
                            i = j + 2
                        } else { i = params.count }
                    }
                }
                if let c = col { if v == 38 { curFG = c } else { curBG = c } }
            case 39: curFG = TCol()
            case 40...47: curBG = .idx(v - 40)
            case 49: curBG = TCol()
            case 90...97: curFG = .idx(v - 90 + 8)
            case 100...107: curBG = .idx(v - 100 + 8)
            default: break
            }
            i += 1
        }
    }

    private func resetSGR() {
        curFG = TCol()
        curBG = TCol()
        curAttr = []
    }

    // MARK: cursor and screen ops

    private func saveCursor() {
        saved = Saved(x: cx, y: cy, fg: curFG, bg: curBG, attr: curAttr, wrap: wrapPending, g0Graphics: g0Graphics)
    }

    private func restoreCursor() {
        cx = min(saved.x, cols - 1)
        cy = min(saved.y, rows - 1)
        curFG = saved.fg
        curBG = saved.bg
        curAttr = saved.attr
        wrapPending = saved.wrap
        g0Graphics = saved.g0Graphics
    }

    private func tab() {
        var x = cx + 1
        while x < cols - 1, !tabStops[x] { x += 1 }
        cx = min(x, cols - 1)
        wrapPending = false
    }

    private func backTab() {
        var x = cx - 1
        while x > 0, !tabStops[x] { x -= 1 }
        cx = max(x, 0)
        wrapPending = false
    }

    private func lineFeed() {
        if cy == scrollBottom { scrollUp(1) }
        else if cy < rows - 1 { cy += 1 }
    }

    private func reverseIndex() {
        if cy == scrollTop { scrollDown(1) }
        else if cy > 0 { cy -= 1 }
    }

    private func scrollUp(_ n: Int) {
        let count = min(n, scrollBottom - scrollTop + 1)
        for _ in 0..<count {
            let removed = screen.remove(at: scrollTop)
            screen.insert(blankRow(), at: scrollBottom)
            if scrollTop == 0 && !usingAlt {
                scrollback.append(removed)
                trimScrollback()
            }
        }
    }

    private func scrollDown(_ n: Int) {
        let count = min(n, scrollBottom - scrollTop + 1)
        for _ in 0..<count {
            screen.remove(at: scrollBottom)
            screen.insert(blankRow(), at: scrollTop)
        }
    }

    private func insertLines(_ n: Int) {
        guard cy >= scrollTop, cy <= scrollBottom else { return }
        let count = min(n, scrollBottom - cy + 1)
        for _ in 0..<count {
            screen.remove(at: scrollBottom)
            screen.insert(blankRow(), at: cy)
        }
        cx = 0
        wrapPending = false
    }

    private func deleteLines(_ n: Int) {
        guard cy >= scrollTop, cy <= scrollBottom else { return }
        let count = min(n, scrollBottom - cy + 1)
        for _ in 0..<count {
            screen.remove(at: cy)
            screen.insert(blankRow(), at: scrollBottom)
        }
        cx = 0
        wrapPending = false
    }

    private func insertChars(_ n: Int) {
        let count = min(n, cols - cx)
        var row = screen[cy]
        row.insert(contentsOf: Array(repeating: blankCell(), count: count), at: cx)
        row.removeLast(count)
        screen[cy] = row
    }

    private func deleteChars(_ n: Int) {
        let count = min(n, cols - cx)
        var row = screen[cy]
        row.removeSubrange(cx..<(cx + count))
        row.append(contentsOf: Array(repeating: blankCell(), count: count))
        screen[cy] = row
    }

    private func eraseChars(_ n: Int) {
        let end = min(cx + n, cols)
        let blank = blankCell()
        for x in cx..<end { screen[cy][x] = blank }
    }

    private func eraseLine(_ mode: Int) {
        let blank = blankCell()
        switch mode {
        case 0: for x in cx..<cols { screen[cy][x] = blank }
        case 1: for x in 0...min(cx, cols - 1) { screen[cy][x] = blank }
        default: screen[cy] = blankRow()
        }
    }

    private func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseLine(0)
            if cy + 1 < rows { for y in (cy + 1)..<rows { screen[y] = blankRow() } }
        case 1:
            eraseLine(1)
            if cy > 0 { for y in 0..<cy { screen[y] = blankRow() } }
        case 2:
            for y in 0..<rows { screen[y] = blankRow() }
        case 3:
            scrollback.removeAll()
            onScrollbackTrim?(Int.max)
        default: break
        }
    }

    // MARK: alt screen

    private func enterAlt(save: Bool) {
        guard !usingAlt else { return }
        if save { savedMain = Saved(x: cx, y: cy, fg: curFG, bg: curBG, attr: curAttr, wrap: wrapPending, g0Graphics: g0Graphics) }
        mainScreenBackup = screen
        screen = (0..<rows).map { _ in blankRow() }
        usingAlt = true
        if save { cx = 0; cy = 0 }
        scrollTop = 0
        scrollBottom = rows - 1
    }

    private func exitAlt(restore: Bool) {
        guard usingAlt else { return }
        usingAlt = false
        if let back = mainScreenBackup {
            screen = back
            // heal size mismatches from resizing while in alt screen
            if screen.count != rows {
                if screen.count > rows { screen.removeFirst(screen.count - rows) }
                else { while screen.count < rows { screen.append(Array(repeating: TCell(), count: cols)) } }
            }
        }
        mainScreenBackup = nil
        if restore {
            cx = min(savedMain.x, cols - 1)
            cy = min(savedMain.y, rows - 1)
            curFG = savedMain.fg
            curBG = savedMain.bg
            curAttr = savedMain.attr
            wrapPending = savedMain.wrap
            g0Graphics = savedMain.g0Graphics
        }
        scrollTop = 0
        scrollBottom = rows - 1
    }

    private func fullReset() {
        screen = (0..<rows).map { _ in Array(repeating: TCell(), count: cols) }
        scrollback.removeAll()
        usingAlt = false
        mainScreenBackup = nil
        cx = 0; cy = 0
        wrapPending = false
        resetSGR()
        scrollTop = 0
        scrollBottom = rows - 1
        appCursorKeys = false
        bracketedPaste = false
        cursorVisible = true
        mouseMode = 0
        mouseSGR = false
        autoWrap = true
        originMode = false
        insertMode = false
        g0Graphics = false
        resetTabs()
    }

    // MARK: OSC

    private func finishOSC() {
        state = .ground
        guard let s = String(bytes: oscBuffer, encoding: .utf8) else { return }
        guard let semi = s.firstIndex(of: ";") else { return }
        let code = String(s[s.startIndex..<semi])
        let value = String(s[s.index(after: semi)...])
        switch code {
        case "0", "2", "1":
            title = value
            onTitle?(value)
        default: break
        }
    }

    // MARK: printing

    private func put(_ scalar: UInt32) {
        var u = scalar
        if g0Graphics, let m = decGraphics[u] { u = m }
        let w = termCharWidth(u)
        if w == 0 { return }
        lastPrinted = u

        if wrapPending {
            if autoWrap { cx = 0; lineFeed() }
            wrapPending = false
        }
        if cx + w > cols {
            if autoWrap { cx = 0; lineFeed() } else { cx = cols - w }
        }

        // clean up half-overwritten wide characters
        if screen[cy][cx].wide == 2, cx > 0 { screen[cy][cx - 1] = blankCell() }
        if screen[cy][cx].wide == 1, cx + 1 < cols { screen[cy][cx + 1] = blankCell() }

        if insertMode {
            var row = screen[cy]
            row.insert(contentsOf: Array(repeating: blankCell(), count: w), at: cx)
            row.removeLast(w)
            screen[cy] = row
        }

        screen[cy][cx] = TCell(ch: u, fg: curFG, bg: curBG, attr: curAttr, wide: w == 2 ? 1 : 0)
        if w == 2, cx + 1 < cols {
            screen[cy][cx + 1] = TCell(ch: 0, fg: curFG, bg: curBG, attr: curAttr, wide: 2)
        }
        cx += w
        if cx >= cols {
            cx = cols - 1
            wrapPending = true
        }
    }
}
