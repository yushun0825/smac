import Foundation

/// 文字の書式(制御コード)を読んだ結果
public enum RichToken: Equatable, Sendable {
    public enum FontStyle: Sendable, Equatable { case regular, italic, bold, boldItalic }

    case text(String)
    case newline
    case superscript      // ^
    case `subscript`      // _
    case endScript        // @
    case style(FontStyle) // %R %I %B %O
    case underline        // %U(切り替え)
    case overline         // %L(切り替え)
    case scale(Int)       // %Sxyz(%)
    case shiftX(Int)      // %X±xy(フォントの高さの %)
    case shiftY(Int)      // %Y±xy
    case lineSpacing(Int) // %W???(0.1 mm)
    case symbolOn         // %G
    case symbolOff        // %A
    case charCode(Int)    // %Q???
    case color(SMPColor)  // %K??????
    case font(String)     // %J名前%J
    case sampleLength(Int)  // %H???(0.1 mm)
    case seriesName(Int, lower: Bool)  // %??N
    case seriesMarker(Int)              // %??E
    case seriesCurve(Int)               // %??F
    case seriesDate(Int, alt: Bool)     // %??D
    case seriesTime(Int, alt: Bool)     // %??T
    case seriesCell(Int, row: Int, column: Int) // %??Cxxyy
    case fileName(lower: Bool)           // %N
    case fileDate(alt: Bool)             // %D
    case fileTime(alt: Bool)             // %T
    case systemDate(alt: Bool)           // %M
    case systemTime(alt: Bool)           // %V
}

public enum RichTextParser {
    public static func parse(_ s: String) -> [RichToken] {
        let c = Array(s)
        var out: [RichToken] = []
        var buf = ""
        var i = 0
        func flush() {
            if !buf.isEmpty { out.append(.text(buf)); buf = "" }
        }
        func digits(_ from: Int, _ count: Int) -> Int? {
            guard from + count <= c.count else { return nil }
            let str = String(c[from..<(from + count)])
            guard str.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(str)
        }
        var scriptDepth = 0
        while i < c.count {
            let ch = c[i]
            switch ch {
            case "\\":
                if i + 1 < c.count {
                    let n = c[i + 1]
                    if n == "n" { flush(); out.append(.newline) } else { buf.append(n) }
                    i += 2
                } else { buf.append(ch); i += 1 }
            case "\n", "\r", "\r\n":
                flush(); out.append(.newline)
                i += 1
            case "^":
                flush(); out.append(.superscript); scriptDepth += 1; i += 1
            case "_":
                flush(); out.append(.`subscript`); scriptDepth += 1; i += 1
            case "@":
                if scriptDepth > 0 {
                    flush(); out.append(.endScript); scriptDepth -= 1
                } else { buf.append(ch) }
                i += 1
            case "%":
                guard i + 1 < c.count else { buf.append(ch); i += 1; continue }
                let n = c[i + 1]
                // 2 桁の番号が付くもの: %??N など
                if let num = digits(i + 1, 2), i + 3 < c.count {
                    let k = c[i + 3]
                    switch k {
                    case "N", "n": flush(); out.append(.seriesName(num, lower: k == "n")); i += 4; continue
                    case "E", "e": flush(); out.append(.seriesMarker(num)); i += 4; continue
                    case "F", "f": flush(); out.append(.seriesCurve(num)); i += 4; continue
                    case "D", "d": flush(); out.append(.seriesDate(num, alt: k == "d")); i += 4; continue
                    case "T", "t": flush(); out.append(.seriesTime(num, alt: k == "t")); i += 4; continue
                    case "C", "c":
                        if let r = digits(i + 4, 2), let col = digits(i + 6, 2) {
                            flush(); out.append(.seriesCell(num, row: r, column: col)); i += 8; continue
                        }
                    default: break
                    }
                }
                switch n {
                case "%": buf.append("%"); i += 2
                case "R": flush(); out.append(.style(.regular)); i += 2
                case "I": flush(); out.append(.style(.italic)); i += 2
                case "B": flush(); out.append(.style(.bold)); i += 2
                case "O": flush(); out.append(.style(.boldItalic)); i += 2
                case "U": flush(); out.append(.underline); i += 2
                case "L": flush(); out.append(.overline); i += 2
                case "G": flush(); out.append(.symbolOn); i += 2
                case "A": flush(); out.append(.symbolOff); i += 2
                case "S":
                    if let v = digits(i + 2, 3) { flush(); out.append(.scale(v)); i += 5 } else { buf.append("%S"); i += 2 }
                case "W":
                    if let v = digits(i + 2, 3) { flush(); out.append(.lineSpacing(v)); i += 5 } else { buf.append("%W"); i += 2 }
                case "H":
                    if let v = digits(i + 2, 3) { flush(); out.append(.sampleLength(v)); i += 5 } else { buf.append("%H"); i += 2 }
                case "Q":
                    if let v = digits(i + 2, 3) { flush(); out.append(.charCode(v)); i += 5 } else { buf.append("%Q"); i += 2 }
                case "X", "Y":
                    if i + 4 < c.count, c[i + 2] == "+" || c[i + 2] == "-", let v = digits(i + 3, 2) {
                        flush()
                        let signed = c[i + 2] == "-" ? -v : v
                        out.append(n == "X" ? .shiftX(signed) : .shiftY(signed))
                        i += 5
                    } else { buf.append("%"); buf.append(n); i += 2 }
                case "K":
                    if i + 8 <= c.count, let col = SMPColor(hexRGB: String(c[(i + 2)..<(i + 8)])) {
                        flush(); out.append(.color(col)); i += 8
                        // Qiita などで ~ で終える書き方があるので読み飛ばす
                        if i < c.count, c[i] == "~" || c[i] == "～" { i += 1 }
                    } else { buf.append("%K"); i += 2 }
                case "J":
                    // %J名前%J
                    var j = i + 2
                    var name = ""
                    var closed = false
                    while j < c.count {
                        if c[j] == "%", j + 1 < c.count, c[j + 1] == "J" { closed = true; break }
                        name.append(c[j]); j += 1
                    }
                    if closed { flush(); out.append(.font(name)); i = j + 2 } else { buf.append("%J"); i += 2 }
                case "N", "n": flush(); out.append(.fileName(lower: n == "n")); i += 2
                case "D", "d": flush(); out.append(.fileDate(alt: n == "d")); i += 2
                case "T", "t": flush(); out.append(.fileTime(alt: n == "t")); i += 2
                case "M", "m": flush(); out.append(.systemDate(alt: n == "m")); i += 2
                case "V", "v": flush(); out.append(.systemTime(alt: n == "v")); i += 2
                default:
                    buf.append(ch); i += 1
                }
            default:
                buf.append(ch); i += 1
            }
        }
        flush()
        return out
    }

    /// 制御コードを除いた、だいたいの文字(一覧での表示などに使う)
    public static func plainText(_ s: String) -> String {
        var out = ""
        var symbol = false
        for t in parse(s) {
            switch t {
            case .text(let str): out += symbol ? SymbolEncoding.map(str) : str
            case .newline: out += " "
            case .symbolOn: symbol = true
            case .symbolOff: symbol = false
            case .charCode(let v): out += symbol ? SymbolEncoding.character(v) : SymbolEncoding.windows1252(v)
            default: break
            }
        }
        return out
    }
}

/// Symbol フォントの文字の並び(Adobe Symbol Encoding)を Unicode にする
public enum SymbolEncoding {
    static let table: [Int: String] = {
        var t: [Int: String] = [:]
        let pairs: [(Int, UInt32)] = [
            (0x22, 0x2200), (0x24, 0x2203), (0x27, 0x220B), (0x2A, 0x2217), (0x2D, 0x2212), (0x40, 0x2245),
            (0x41, 0x0391), (0x42, 0x0392), (0x43, 0x03A7), (0x44, 0x0394), (0x45, 0x0395), (0x46, 0x03A6),
            (0x47, 0x0393), (0x48, 0x0397), (0x49, 0x0399), (0x4A, 0x03D1), (0x4B, 0x039A), (0x4C, 0x039B),
            (0x4D, 0x039C), (0x4E, 0x039D), (0x4F, 0x039F), (0x50, 0x03A0), (0x51, 0x0398), (0x52, 0x03A1),
            (0x53, 0x03A3), (0x54, 0x03A4), (0x55, 0x03A5), (0x56, 0x03C2), (0x57, 0x03A9), (0x58, 0x039E),
            (0x59, 0x03A8), (0x5A, 0x0396), (0x5C, 0x2234), (0x5E, 0x22A5), (0x60, 0x203E),
            (0x61, 0x03B1), (0x62, 0x03B2), (0x63, 0x03C7), (0x64, 0x03B4), (0x65, 0x03B5), (0x66, 0x03C6),
            (0x67, 0x03B3), (0x68, 0x03B7), (0x69, 0x03B9), (0x6A, 0x03D5), (0x6B, 0x03BA), (0x6C, 0x03BB),
            (0x6D, 0x03BC), (0x6E, 0x03BD), (0x6F, 0x03BF), (0x70, 0x03C0), (0x71, 0x03B8), (0x72, 0x03C1),
            (0x73, 0x03C3), (0x74, 0x03C4), (0x75, 0x03C5), (0x76, 0x03D6), (0x77, 0x03C9), (0x78, 0x03BE),
            (0x79, 0x03C8), (0x7A, 0x03B6), (0x7E, 0x223C),
            (0xA0, 0x20AC), (0xA1, 0x03D2), (0xA2, 0x2032), (0xA3, 0x2264), (0xA4, 0x2044), (0xA5, 0x221E),
            (0xA6, 0x0192), (0xA7, 0x2663), (0xA8, 0x2666), (0xA9, 0x2665), (0xAA, 0x2660), (0xAB, 0x2194),
            (0xAC, 0x2190), (0xAD, 0x2191), (0xAE, 0x2192), (0xAF, 0x2193), (0xB0, 0x00B0), (0xB1, 0x00B1),
            (0xB2, 0x2033), (0xB3, 0x2265), (0xB4, 0x00D7), (0xB5, 0x221D), (0xB6, 0x2202), (0xB7, 0x2022),
            (0xB8, 0x00F7), (0xB9, 0x2260), (0xBA, 0x2261), (0xBB, 0x2248), (0xBC, 0x2026), (0xBD, 0x23D0),
            (0xBE, 0x23AF), (0xBF, 0x21B5), (0xC0, 0x2135), (0xC1, 0x2111), (0xC2, 0x211C), (0xC3, 0x2118),
            (0xC4, 0x2297), (0xC5, 0x2295), (0xC6, 0x2205), (0xC7, 0x2229), (0xC8, 0x222A), (0xC9, 0x2283),
            (0xCA, 0x2287), (0xCB, 0x2284), (0xCC, 0x2282), (0xCD, 0x2286), (0xCE, 0x2208), (0xCF, 0x2209),
            (0xD0, 0x2220), (0xD1, 0x2207), (0xD2, 0x00AE), (0xD3, 0x00A9), (0xD4, 0x2122), (0xD5, 0x220F),
            (0xD6, 0x221A), (0xD7, 0x22C5), (0xD8, 0x00AC), (0xD9, 0x2227), (0xDA, 0x2228), (0xDB, 0x21D4),
            (0xDC, 0x21D0), (0xDD, 0x21D1), (0xDE, 0x21D2), (0xDF, 0x21D3), (0xE0, 0x25CA), (0xE1, 0x2329),
            (0xE2, 0x00AE), (0xE3, 0x00A9), (0xE4, 0x2122), (0xE5, 0x2211), (0xE6, 0x239B), (0xE7, 0x239C),
            (0xE8, 0x239D), (0xE9, 0x23A1), (0xEA, 0x23A2), (0xEB, 0x23A3), (0xEC, 0x23A7), (0xED, 0x23A8),
            (0xEE, 0x23A9), (0xEF, 0x23AA), (0xF1, 0x232A), (0xF2, 0x222B), (0xF3, 0x2320), (0xF4, 0x23AE),
            (0xF5, 0x2321), (0xF6, 0x239E), (0xF7, 0x239F), (0xF8, 0x23A0), (0xF9, 0x23A4), (0xFA, 0x23A5),
            (0xFB, 0x23A6), (0xFC, 0x23AB), (0xFD, 0x23AC), (0xFE, 0x23AD),
        ]
        for (k, v) in pairs {
            if let u = Unicode.Scalar(v) { t[k] = String(Character(u)) }
        }
        return t
    }()

    public static func character(_ code: Int) -> String {
        if let s = table[code] { return s }
        if code >= 0x20 && code < 0x7F, let u = Unicode.Scalar(code) { return String(Character(u)) }
        return ""
    }

    /// %G で切り替えた後の文字(a → α など)
    public static func map(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            if u.value < 0x80 { out += character(Int(u.value)) } else { out.unicodeScalars.append(u) }
        }
        return out
    }

    /// %Q??? のふつうのフォントでの文字(Windows-1252)
    public static func windows1252(_ code: Int) -> String {
        guard code >= 0 && code <= 255 else { return "" }
        let data = Data([UInt8(code)])
        return String(data: data, encoding: .windowsCP1252) ?? ""
    }
}
