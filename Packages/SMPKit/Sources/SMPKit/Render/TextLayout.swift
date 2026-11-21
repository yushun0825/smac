import Foundation
import CoreText
import CoreGraphics

/// 文字列の %N・%E などを埋めるための情報
public struct TextEnvironment {
    public var seriesNames: [String] = []
    /// 描画順の番号(0 始まり)→ 系列の描き方
    public var seriesStyles: [Series] = []
    public var fileName: String = "Untitled.SMP"
    public var fileDate: Date = Date()
    public var seriesDates: [Date?] = []
    public var dataCell: ((Int, Int, Int) -> String?)?
    public var superscriptScale: Double = 0.7
    public var superscriptRise: Double = 0.35
    public var subscriptDrop: Double = 0.15

    public init() {}
}

/// 1 つの文字列を並べた結果(原点 = 1 行目の左下、y は上向き。単位は 0.01 mm)
public struct TextLayout {
    public enum Content {
        case glyphs(CTLine)
        case marker(Series, curve: Bool, length: Double, size: Double)
    }

    public struct Run {
        public var content: Content
        public var origin: CGPoint      // ベースラインの左端
        public var width: Double
        public var ascent: Double
        public var descent: Double
        public var color: SMPColor
        public var underline: Bool
        public var overline: Bool
        public var emSize: Double
    }

    public var runs: [Run] = []
    public var bounds: CGRect = .zero

    public var isEmpty: Bool { runs.isEmpty }
}

public enum TextLayoutEngine {
    struct State {
        var latinFamily: String
        var japaneseFamily: String
        var latinSize: Double
        var japaneseSize: Double
        var bold: Bool
        var italic: Bool
        var jpBold: Bool
        var jpItalic: Bool
        var scale: Double = 1
        var color: SMPColor
        var underline = false
        var overline = false
        var symbol = false
        var baseline: Double = 0
        var scriptFactor: Double = 1
    }

    /// 文字列を並べる。latin/japanese は LOGFONT(大きさは pt)
    public static func layout(_ text: String, latin: LogFont, japanese: LogFont, color: SMPColor,
                              environment env: TextEnvironment) -> TextLayout {
        let tokens = RichTextParser.parse(text)
        let pt = Units.hundredthMMPerPoint
        let latinFamily = FontMapper.macFamily(latin.faceName, japanese: false)
        let jpFamily = FontMapper.macFamily(japanese.faceName, japanese: true)
        var st = State(latinFamily: latinFamily, japaneseFamily: jpFamily,
                       latinSize: latin.pointSize * pt, japaneseSize: japanese.pointSize * pt,
                       bold: latin.isBold, italic: latin.isItalic, jpBold: japanese.isBold, jpItalic: japanese.isItalic,
                       color: color)
        let baseLatinFont = FontMapper.font(family: latinFamily, size: st.latinSize, bold: st.bold, italic: st.italic)
        let baseAscent = Double(CTFontGetAscent(baseLatinFont))
        let baseDescent = Double(CTFontGetDescent(baseLatinFont))
        var lineSpacing = baseAscent + baseDescent
        var sampleLength = 1000.0

        var layout = TextLayout()
        var penX = 0.0
        var lineIndex = 0
        // 原点は 1 行目のベースラインの左端(文字の開始位置の左下)
        var lineBaseline = 0.0
        var scriptStack: [(baseline: Double, factor: Double)] = []
        var shiftY = 0.0

        func emSize() -> Double { st.latinSize * st.scale * st.scriptFactor }

        func appendText(_ s: String) {
            guard !s.isEmpty else { return }
            let mapped = st.symbol ? SymbolEncoding.map(s) : s
            // 欧文と和文で分ける
            var chunk = ""
            var chunkJapanese: Bool?
            func emit() {
                guard !chunk.isEmpty, let jp = chunkJapanese else { return }
                let size = (jp ? st.japaneseSize : st.latinSize) * st.scale * st.scriptFactor
                let family = jp ? st.japaneseFamily : st.latinFamily
                let font = FontMapper.font(family: family, size: CGFloat(Swift.max(size, 1)),
                                           bold: jp ? st.jpBold : st.bold, italic: jp ? st.jpItalic : st.italic)
                let attrs: [CFString: Any] = [
                    kCTFontAttributeName: font,
                    kCTForegroundColorFromContextAttributeName: true,
                ]
                let attr = CFAttributedStringCreate(nil, chunk as CFString, attrs as CFDictionary)!
                let line = CTLineCreateWithAttributedString(attr)
                var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
                let w = CTLineGetTypographicBounds(line, &asc, &desc, &lead)
                layout.runs.append(TextLayout.Run(content: .glyphs(line),
                                                  origin: CGPoint(x: penX, y: lineBaseline + st.baseline + shiftY),
                                                  width: w, ascent: Double(asc), descent: Double(desc), color: st.color,
                                                  underline: st.underline, overline: st.overline, emSize: size))
                penX += w
                chunk = ""
            }
            for u in mapped.unicodeScalars {
                let jp = FontMapper.isJapanese(u)
                if chunkJapanese != nil && chunkJapanese != jp { emit() }
                chunkJapanese = jp
                chunk.unicodeScalars.append(u)
            }
            emit()
        }

        func appendMarker(_ index: Int, curve: Bool) {
            let i = index == 0 ? 0 : index - 1
            guard i >= 0, i < env.seriesStyles.count else { return }
            let s = env.seriesStyles[i]
            let size = Double(s.dotSize)
            let hasLine = curve ? s.curveLineType != .none : s.lineType != .none
            let length = curve || hasLine ? sampleLength : Swift.max(size * 1.2, emSize() * 0.6)
            let em = emSize()
            // 文字の中ほど(x の高さ)に合わせる
            let mid = lineBaseline + st.baseline + shiftY + em * 0.3
            layout.runs.append(TextLayout.Run(content: .marker(s, curve: curve, length: length, size: size),
                                              origin: CGPoint(x: penX, y: mid), width: length,
                                              ascent: Swift.max(size / 2, em * 0.7), descent: Swift.max(size / 2 - em * 0.3, 0),
                                              color: st.color, underline: false, overline: false, emSize: em))
            penX += length + em * 0.25
        }

        func dateString(_ d: Date?, alt: Bool, time: Bool) -> String {
            guard let d else { return "" }
            let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
            if time {
                return alt ? String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
                           : String(format: "%d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
            }
            return alt ? String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
                       : String(format: "%d-%d-%d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }

        func seriesName(_ index: Int) -> String {
            let i = index == 0 ? 0 : index - 1
            return i >= 0 && i < env.seriesNames.count ? env.seriesNames[i] : ""
        }

        for t in tokens {
            switch t {
            case .text(let s): appendText(s)
            case .newline:
                lineIndex += 1
                penX = 0
                lineBaseline = -Double(lineIndex) * lineSpacing
                st.baseline = 0
                shiftY = 0
                scriptStack.removeAll()
                st.scriptFactor = 1
            case .superscript:
                scriptStack.append((st.baseline, st.scriptFactor))
                st.baseline += emSize() * env.superscriptRise
                st.scriptFactor *= env.superscriptScale
            case .`subscript`:
                scriptStack.append((st.baseline, st.scriptFactor))
                st.baseline -= emSize() * env.subscriptDrop
                st.scriptFactor *= env.superscriptScale
            case .endScript:
                if let last = scriptStack.popLast() { st.baseline = last.baseline; st.scriptFactor = last.factor }
            case .style(let s):
                switch s {
                case .regular: st.bold = false; st.italic = false
                case .italic: st.bold = false; st.italic = true
                case .bold: st.bold = true; st.italic = false
                case .boldItalic: st.bold = true; st.italic = true
                }
                st.jpBold = st.bold; st.jpItalic = st.italic
            case .underline: st.underline.toggle()
            case .overline: st.overline.toggle()
            case .scale(let v): st.scale = Double(Swift.max(v, 1)) / 100
            case .shiftX(let v): penX += emSize() * Double(v) / 100
            case .shiftY(let v): shiftY += emSize() * Double(v) / 100
            case .lineSpacing(let v): lineSpacing = Double(v) * 10
            case .symbolOn: st.symbol = true
            case .symbolOff: st.symbol = false
            case .charCode(let v): appendText(st.symbol ? SymbolEncoding.character(v) : SymbolEncoding.windows1252(v))
            case .color(let c): st.color = c
            case .font(let name):
                let jp = name.unicodeScalars.contains(where: FontMapper.isJapanese)
                if jp { st.japaneseFamily = FontMapper.macFamily(name, japanese: true) }
                else { st.latinFamily = FontMapper.macFamily(name, japanese: false) }
            case .sampleLength(let v): sampleLength = Double(v) * 10
            case .seriesName(let i, let lower):
                let n = seriesName(i)
                appendText(lower ? n.lowercased() : n)
            case .seriesMarker(let i): appendMarker(i, curve: false)
            case .seriesCurve(let i): appendMarker(i, curve: true)
            case .seriesDate(let i, let alt):
                let k = i == 0 ? 0 : i - 1
                appendText(dateString(k < env.seriesDates.count ? env.seriesDates[k] : nil, alt: alt, time: false))
            case .seriesTime(let i, let alt):
                let k = i == 0 ? 0 : i - 1
                appendText(dateString(k < env.seriesDates.count ? env.seriesDates[k] : nil, alt: alt, time: true))
            case .seriesCell(let i, let r, let c):
                appendText(env.dataCell?(i, r, c) ?? "")
            case .fileName(let lower): appendText(lower ? env.fileName.lowercased() : env.fileName)
            case .fileDate(let alt): appendText(dateString(env.fileDate, alt: alt, time: false))
            case .fileTime(let alt): appendText(dateString(env.fileDate, alt: alt, time: true))
            case .systemDate(let alt): appendText(dateString(Date(), alt: alt, time: false))
            case .systemTime(let alt): appendText(dateString(Date(), alt: alt, time: true))
            }
        }

        // 外枠
        var rect = CGRect.null
        for r in layout.runs {
            let rr = CGRect(x: r.origin.x, y: r.origin.y - r.descent, width: r.width, height: r.ascent + r.descent)
            rect = rect.union(rr)
        }
        if rect.isNull {
            rect = CGRect(x: 0, y: -baseDescent, width: baseAscent * 0.5, height: baseAscent + baseDescent)
        }
        layout.bounds = rect
        return layout
    }
}
