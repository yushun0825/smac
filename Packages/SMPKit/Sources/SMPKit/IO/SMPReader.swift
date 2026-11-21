import Foundation

public enum SMPReadError: Error, LocalizedError, Equatable {
    case notSMP
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .notSMP: return "SMP ファイルではありません。"
        case .unsupported(let v): return "この形式の SMP ファイルには対応していません(\(v))。"
        }
    }
}

/// 行を 1 行ずつ読み進めるための道具
struct LineCursor {
    let lines: [String]
    var index = 0

    init(_ lines: [String]) { self.lines = lines }

    var atEnd: Bool { index >= lines.count }

    func peek(_ offset: Int = 0) -> String? {
        let i = index + offset
        return i < lines.count ? lines[i] : nil
    }

    mutating func next() -> String {
        guard index < lines.count else { return "" }
        defer { index += 1 }
        return lines[index]
    }

    mutating func skipBlank() {
        while let l = peek(), l.trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
    }

    /// 次の "[" で始まる行まで(その行は読まない)の行を返す
    mutating func takeUntilSection() -> [String] {
        var out: [String] = []
        while let l = peek(), !l.hasPrefix("[") {
            out.append(l); index += 1
        }
        return out
    }
}

func fields(_ line: String) -> [String] {
    line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
}

func int(_ f: [String], _ i: Int, _ d: Int = 0) -> Int {
    guard i < f.count else { return d }
    if let v = Int(f[i]) { return v }
    if let v = Double(f[i]), v.isFinite { return Int(v.rounded()) }
    return d
}

func dbl(_ f: [String], _ i: Int, _ d: Double = 0) -> Double {
    guard i < f.count, let v = Double(f[i]) else { return d }
    return v
}

func bool(_ f: [String], _ i: Int, _ d: Bool = false) -> Bool {
    guard i < f.count else { return d }
    return int(f, i, d ? 1 : 0) != 0
}

func isLogFontLine(_ line: String?) -> Bool {
    guard let line else { return false }
    let f = fields(line)
    return f.count >= 13 && f.prefix(13).allSatisfy { Int($0) != nil }
}

public enum SMPReader {
    /// SMP(SMA)ファイルを読む。data は CP932 のバイト列。
    public static func read(data: Data, fileName: String = "Untitled.SMP") throws -> SMPProject {
        let text = SMPTextEncoding.decodeSMP(data)
        return try read(text: text, fileName: fileName)
    }

    public static func read(text: String, fileName: String = "Untitled.SMP") throws -> SMPProject {
        let lines = SMPTextEncoding.splitLines(text)
        var cursor = LineCursor(lines)
        cursor.skipBlank()
        guard let first = cursor.peek() else { throw SMPReadError.notSMP }
        var project = SMPProject()

        if first.contains("SMA file") {
            _ = cursor.next()
            let header = fields(cursor.next())
            let count = max(int(header, 0, 0), 0)
            project.multiGraphHeaderTail = Array(header.dropFirst())
            for _ in 0..<count {
                cursor.skipBlank()
                guard let nameLine = cursor.peek(), nameLine.hasPrefix("[") else { break }
                let name = String(nameLine.dropFirst().prefix(while: { $0 != "]" }))
                _ = cursor.next()
                cursor.skipBlank()
                guard let header = cursor.peek(), header.contains("SMP file") else { break }
                var g = try readGraph(&cursor)
                g.name = name
                project.graphs.append(g)
            }
        } else if first.contains("SMP file") {
            var g = try readGraph(&cursor)
            g.name = fileName
            project.graphs.append(g)
        } else {
            throw SMPReadError.notSMP
        }

        // [DATA]
        while !cursor.atEnd {
            let l = cursor.next().trimmingCharacters(in: .whitespaces)
            if l == "[DATA]" {
                readData(&cursor, into: &project)
            }
        }
        return project
    }

    // MARK: - グラフ 1 枚

    static func readGraph(_ c: inout LineCursor) throws -> Graph {
        var g = Graph()
        let versionLine = c.next()
        g.versionLine = versionLine
        let version = parseVersion(versionLine)
        g.comment = c.next()

        // 用紙の設定(Ver.1.40 以降)。古いものは空行。
        if let l = c.peek() {
            let f = fields(l)
            if f.count >= 5, f.allSatisfy({ Int($0) != nil }) {
                _ = c.next()
                g.page.saveData = bool(f, 0, true)
                g.page.savePath = bool(f, 1, true)
                g.page.paperWidth = int(f, 2, 210)
                g.page.paperHeight = int(f, 3, 297)
                g.page.landscape = bool(f, 4)
                g.page.tail = f.dropFirst(5).compactMap { Int($0) }
            } else if f.isEmpty {
                _ = c.next()
            }
        }
        c.skipBlank()
        let seriesCount = int(fields(c.next()), 0, 0)
        for _ in 0..<max(seriesCount, 0) {
            c.skipBlank()
            guard let h = c.peek(), h.hasPrefix("["), !h.hasPrefix("[GRAPH]") else { break }
            g.series.append(readSeries(&c))
        }

        // 残りの区切り
        while !c.atEnd {
            guard let raw = c.peek() else { break }
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { c.index += 1; continue }
            if l == "[DATA]" || l.contains("SMP file") || (l.hasPrefix("[") && l.uppercased().hasSuffix(".SMP]")) {
                break
            }
            c.index += 1
            switch l {
            case "[GRAPH]": readGraphSection(&c, into: &g)
            case "[AXIS-0]", "[AXIS-1]", "[AXIS-2]", "[AXIS-3]":
                let i = Int(String(l.dropFirst(6).prefix(1))) ?? 0
                g.axes[i] = readAxis(&c)
            case "[LEGEND]": readLegend(&c, into: &g)
            case "[TITLE]": readOldTitles(&c, into: &g)
            case "[ARROW]": readOldArrows(&c, into: &g)
            case "[DOT]": readOldDots(&c, into: &g)
            case "[OTHERS]": readOthers(&c, into: &g)
            case "[MASKS]":
                readMasks(&c, into: &g)
                // [MASKS] で 1 枚のグラフは終わる
                return finalize(g, version: version)
            default:
                _ = c.takeUntilSection()
            }
        }
        return finalize(g, version: version)
    }

    static func finalize(_ g: Graph, version: Double) -> Graph {
        var g = g
        if version < 1.5 {
            // 古い SMP のフォントは pt で書かれている。pointSize が自動で判断するのでそのまま。
        }
        if g.page.paperWidth <= 0 { g.page = PageSetup() }
        return g
    }

    static func parseVersion(_ line: String) -> Double {
        // SMP 形式の見出しの行
        guard let r = line.range(of: "ver.") else { return 1.8 }
        let rest = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
        let num = rest.prefix(while: { $0.isNumber || $0 == "." })
        return Double(num) ?? 1.8
    }

    static func readSeries(_ c: inout LineCursor) -> Series {
        let header = c.next()
        let name = String(header.dropFirst().prefix(while: { $0 != "]" }))
        let path = c.next().trimmingCharacters(in: .whitespaces)
        var s = Series(name: name, path: path)

        // 1 行目: 種類 0 誤差X 誤差Y 列X 列Y 読込行数 先頭スキップ 読込終了 [option]
        let typeLine = c.next()
        let f1 = fields(typeLine)
        s.kindRaw = int(f1, 0, 0)
        s.kind = Series.Kind(rawValue: s.kindRaw) ?? .normal
        s.errorBarX = Series.ErrorBar(rawValue: int(f1, 2, 0)) ?? .none
        s.errorBarY = Series.ErrorBar(rawValue: int(f1, 3, 0)) ?? .none
        s.columnX = int(f1, 4, 0)
        s.columnY = int(f1, 5, 1)
        s.linesRead = int(f1, 6, 0)
        s.skipLines = int(f1, 7, 0)
        s.maxLines = int(f1, 8, -1)
        if f1.count > 9 { s.option = f1.dropFirst(9).joined(separator: " ") }

        // 2 行目: 線幅 線色 ピッチ [TAB を空白 行数は絶対 コメント行を数えない 範囲外を考慮]
        let f2 = fields(c.next())
        s.lineWidth = int(f2, 0, 40)
        s.lineColor = SMPColor(colorref: int(f2, 1, 0))
        s.pitch = int(f2, 2, 300)
        s.tabAsSpace = bool(f2, 3)
        s.absoluteLineCount = bool(f2, 4)
        s.skipCommentCount = bool(f2, 5)
        s.considerOutOfRange = bool(f2, 6)

        // 3 行目: 線種 ドット種 プロットサイズ ドット色
        let f3 = fields(c.next())
        s.lineType = LineType(code: int(f3, 0, 0))
        s.dotType = int(f3, 1, PlotType.defaultCode)
        s.dotSize = int(f3, 2, 300)
        s.dotColor = SMPColor(colorref: int(f3, 3, 0))

        // 4 行目: U参照 R参照 ステップ 横平均 縦平均 lbStyle lbColor lbHatch
        let f4 = fields(c.next())
        s.useUAxis = bool(f4, 0)
        s.useRAxis = bool(f4, 1)
        s.readStep = max(int(f4, 2, 1), 1)
        s.horizontalAverage = int(f4, 3, 0)
        s.verticalAverage = int(f4, 4, 0)
        s.brushStyle = int(f4, 5, 0)
        s.brushColor = SMPColor(colorref: int(f4, 6, 0xFFFFFF))
        s.brushHatch = int(f4, 7, 5)

        // 5 行目: X変換 Y変換 [コンバーター]
        let f5 = fields(c.next())
        s.transformX = bool(f5, 0)
        s.transformY = bool(f5, 1)
        s.converter = int(f5, 2, 0)
        s.expressionX = c.next().trimmingCharacters(in: .whitespaces)
        s.expressionY = c.next().trimmingCharacters(in: .whitespaces)
        if s.expressionX.isEmpty { s.expressionX = "x" }
        if s.expressionY.isEmpty { s.expressionY = "y" }

        // 8 行目: 連続曲線のタイプ 分割数 次数 特定点 始点 終点 特定点X 特定点Y 棒の始点
        let f8 = fields(c.next())
        s.curveSpacing = Series.CurveSpacing(rawValue: int(f8, 0, 0)) ?? .linear
        s.curveDivisions = int(f8, 1, 101)
        s.lsqOrder = int(f8, 2, 1)
        s.passThroughPoint = bool(f8, 3)
        s.curveStart = dbl(f8, 4, 0)
        s.curveEnd = dbl(f8, 5, 0)
        s.passX = dbl(f8, 6, 0)
        s.passY = dbl(f8, 7, 0)
        s.barBase = dbl(f8, 8, 0)

        // 9 行目: 曲線の線種 太さ 色 ピッチ [表示]
        let f9 = fields(c.next())
        s.curveLineType = LineType(code: int(f9, 0, 1))
        s.curveWidth = int(f9, 1, 40)
        s.curveColor = SMPColor(colorref: int(f9, 2, 0))
        s.curvePitch = int(f9, 3, 300)
        s.curveVisible = f9.count > 4 ? bool(f9, 4, true) : true

        if s.kind == .generalLSQ {
            s.generalParameterLine = c.peek().map { $0.hasPrefix("[") ? "" : c.next() } ?? ""
            // 新しい形の行の 1 つ目の値は許容誤差(%)。% として無理のない値のときだけ使う
            if let t = SeriesEvaluator.parameterLineTolerance(s.generalParameterLine), t.isFinite, t > 0, t <= 10 {
                s.generalTolerance = t
            }
            if let l = c.peek(), !l.hasPrefix("[") { s.generalFunction = c.next().trimmingCharacters(in: .whitespaces) }
            var ders: [String] = []
            for _ in 0..<7 {
                guard let l = c.peek(), !l.hasPrefix("[") else { break }
                ders.append(c.next().trimmingCharacters(in: .whitespaces))
            }
            while ders.count < 7 { ders.append("") }
            s.generalDerivatives = ders
        }
        var rest = c.takeUntilSection().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if s.kind == .extension1, let ex = parseExtensionBlock(rest) {
            s.extensionAnalysis = ex.analysis
            if let settings = ex.settings { s.peakFit = settings }
            rest.removeFirst(ex.consumed)
        }
        s.extraLines = rest
        return s
    }

    /// 特殊処理(種類 8)の系列の 9 行の後ろの行(SMPWriter.extensionLines の形):
    /// 1 行目は解析の名前(GAUSSF2 など)、2 行目は「ピーク数 Offsetを動かす Offset 精度」、
    /// 3〜8 行目はピーク 1〜6 の「強度 位置 半値幅 強度を動かす 位置を動かす 幅を動かす」。
    /// 2 行目以降が無い・形が違うときは名前だけを読む。
    static func parseExtensionBlock(_ lines: [String]) -> (analysis: ExtensionAnalysis, settings: PeakFitSettings?, consumed: Int)? {
        guard let first = lines.first,
              let analysis = ExtensionAnalysis(rawValue: first.trimmingCharacters(in: .whitespaces)) else { return nil }
        func numeric(_ line: String, _ count: Int) -> [String]? {
            let f = fields(line)
            return f.count >= count && f.prefix(count).allSatisfy({ Double($0) != nil }) ? f : nil
        }
        let n = PeakFitSettings.maxPeaks
        guard lines.count >= 2 + n, let head = numeric(lines[1], 4) else { return (analysis, nil, 1) }
        var peakFields: [[String]] = []
        for k in 0..<n {
            guard let f = numeric(lines[2 + k], 6) else { return (analysis, nil, 1) }
            peakFields.append(f)
        }
        var s = PeakFitSettings()
        s.count = Swift.min(Swift.max(int(head, 0, 1), 1), n)
        s.varyOffset = bool(head, 1, true)
        s.offset = dbl(head, 2, 0)
        s.precision = dbl(head, 3, s.precision)
        for (k, f) in peakFields.enumerated() {
            s.intensity[k] = dbl(f, 0, 1)
            s.position[k] = dbl(f, 1, 0)
            s.width[k] = dbl(f, 2, 1)
            s.varyIntensity[k] = bool(f, 3, true)
            s.varyPosition[k] = bool(f, 4, true)
            s.varyWidth[k] = bool(f, 5, true)
        }
        return (analysis, s, 2 + n)
    }

    static func readGraphSection(_ c: inout LineCursor, into g: inout Graph) {
        let f1 = fields(c.next())
        g.left = int(f1, 0, 4000)
        g.top = int(f1, 1, 2000)
        g.width = int(f1, 2, 14000)
        g.height = int(f1, 3, 10000)
        if let l = c.peek(), !l.hasPrefix("[") {
            let f2 = fields(c.next())
            g.zoom = int(f2, 0, 100)
            g.frameType = FrameType(rawValue: int(f2, 1, 1)) ?? .box
            g.zeroCommon = bool(f2, 2)
            g.graphLine2Tail = Array(f2.dropFirst(3))
        }
        if let l = c.peek(), !l.hasPrefix("["), !l.trimmingCharacters(in: .whitespaces).isEmpty {
            let f3 = fields(c.next())
            g.frameWidth = int(f3, 0, 40)
            g.frameColor = SMPColor(colorref: int(f3, 1, 0))
            g.framePitch = int(f3, 2, 0)
            g.background = f3.count > 3 ? SMPColor(colorref: int(f3, 3, 0xFFFFFF)) : .white
        }
        _ = c.takeUntilSection()
    }

    static func readTick(_ line: String) -> TickStyle {
        let f = fields(line)
        return TickStyle(inside: bool(f, 0, true), outside: bool(f, 1), length: int(f, 2, 300),
                         width: int(f, 3, 40), color: SMPColor(colorref: int(f, 4, 0)),
                         pitch: int(f, 5, 0), style: int(f, 6, 1))
    }

    static func readAxis(_ c: inout LineCursor) -> AxisSpec {
        var a = AxisSpec()
        let f1 = fields(c.next())
        a.from = dbl(f1, 0, 0)
        a.to = dbl(f1, 1, 10)
        a.increment = dbl(f1, 2, 1)
        a.limitRange = bool(f1, 3)
        a.limitStart = int(f1, 4, 0)
        a.limitEnd = int(f1, 5, 10000)
        a.crossPosition = int(f1, 6, -1)
        a.labelCount = int(f1, 7, -1)
        a.labelStart = int(f1, 8, 0)
        a.labelInterval = max(int(f1, 9, 1), 1)
        a.plusSign = bool(f1, 10)
        a.zeroPadding = bool(f1, 11)
        a.zeroAsInteger = bool(f1, 12, true)
        a.integerDigits = int(f1, 13, 5)
        a.decimalDigits = int(f1, 14, 5)
        a.gettaOrder = f1.count > 15 ? dbl(f1, 15, 1) : 1
        a.drawGetta = f1.count > 16 ? bool(f1, 16, true) : true

        let f2 = fields(c.next())
        a.division = max(int(f2, 0, 2), 1)
        a.scaleType = ScaleType(rawValue: int(f2, 1, 0)) ?? .linear
        a.autoStep = bool(f2, 2, true)
        a.commonWithOpposite = bool(f2, 3, true)
        a.drawAxis = bool(f2, 4, true)
        a.drawLabels = bool(f2, 5, true)
        a.labelShiftX = int(f2, 6, 0)
        a.labelShiftY = int(f2, 7, 0)
        a.labelColor = SMPColor(colorref: int(f2, 8, 0))
        a.line2Tail = Array(f2.dropFirst(9))

        let fontLine = c.next()
        let fontName = c.next().trimmingCharacters(in: .whitespaces)
        a.font = LogFont.parse(fields: fields(fontLine), faceName: fontName.isEmpty ? "Times New Roman" : fontName)
        if let l = c.peek(), !l.hasPrefix("[") { a.major = readTick(c.next()) }
        if let l = c.peek(), !l.hasPrefix("["), !l.trimmingCharacters(in: .whitespaces).isEmpty { a.minor = readTick(c.next()) }
        _ = c.takeUntilSection()
        return a
    }

    static func readFonts(_ c: inout LineCursor, into t: inout TextObject) {
        let latinFields = fields(c.next())
        let latinName = c.next().trimmingCharacters(in: .whitespaces)
        t.latinFont = LogFont.parse(fields: latinFields, faceName: latinName.isEmpty ? "Times New Roman" : latinName)
        if isLogFontLine(c.peek()) {
            let jf = fields(c.next())
            let jn = c.next().trimmingCharacters(in: .whitespaces)
            t.japaneseFont = LogFont.parse(fields: jf, faceName: jn.isEmpty ? "ＭＳ 明朝" : jn)
        }
        if isLogFontLine(c.peek()) {
            let sf = fields(c.next())
            let sn = c.next().trimmingCharacters(in: .whitespaces)
            t.symbolFont = LogFont.parse(fields: sf, faceName: sn.isEmpty ? "Symbol" : sn)
        }
    }

    static func readText(_ c: inout LineCursor, kind: TextObject.Kind) -> TextObject {
        var t = TextObject()
        t.kind = kind
        let pf = fields(c.next())
        t.x = int(pf, 0, 0)
        t.y = int(pf, 1, 0)
        t.color = SMPColor(colorref: int(pf, 2, 0))
        t.backgroundMode = int(pf, 3, 1)
        t.absolutePosition = bool(pf, 4)
        t.positionTail = Array(pf.dropFirst(5))
        t.text = c.next()
        readFonts(&c, into: &t)
        return t
    }

    static func readShape(_ line: String, objectType: Int) -> ShapeObject {
        let f = fields(line)
        var s = ShapeObject()
        s.objectType = objectType
        s.x1 = dbl(f, 0); s.y1 = dbl(f, 1); s.x2 = dbl(f, 2); s.y2 = dbl(f, 3)
        s.xReference = int(f, 4, 0)
        s.yReference = int(f, 5, 0)
        s.width = int(f, 6, 40)
        s.length = int(f, 7, 500)
        s.color = SMPColor(colorref: int(f, 8, 0))
        s.shapeType = int(f, 9, objectType)
        s.pitch = int(f, 10, 300)
        s.style = int(f, 11, 1)
        s.shadowColor = SMPColor(colorref: int(f, 12, 0xFFFFFF))
        s.size = int(f, 13, 0)
        s.aspect = int(f, 14, 0)
        if f.count > 17 {
            s.headMode = int(f, 15, 1)
            s.headOpen = int(f, 16, 30)
            s.headClose = int(f, 17, 100)
            s.tail = Array(f.dropFirst(18))
        } else if f.count > 15 {
            // 古い形式: 開き 閉じ
            s.headOpen = int(f, 15, 30)
            s.headClose = int(f, 16, 100)
            s.tail = []
        } else {
            s.tail = []
        }
        return s
    }

    static func readDot(_ c: inout LineCursor) -> DotObject {
        var d = DotObject()
        let f = fields(c.next())
        d.x = int(f, 0); d.y = int(f, 1)
        d.dotType = int(f, 2, 1)
        d.width = int(f, 3, 40)
        d.length = int(f, 4, 0)
        d.style = int(f, 5, 0)
        d.size = int(f, 6, 300)
        d.color = SMPColor(colorref: int(f, 7, 0))
        d.lineColor = SMPColor(colorref: int(f, 8, 0))
        d.pitch = int(f, 9, 300)
        d.brushStyle = int(f, 10, 0)
        d.brushColor = SMPColor(colorref: int(f, 11, 0xFFFFFF))
        d.brushHatch = int(f, 12, 5)
        d.tail = Array(f.dropFirst(13))
        if let l = c.peek(), fields(l).count == 1, let n = Int(fields(l)[0]) {
            _ = c.next()
            d.pointCount = n
            if n >= 2 {
                for _ in 0..<n {
                    guard let p = c.peek(), !p.hasPrefix("[") else { break }
                    d.points.append(c.next())
                }
            }
        }
        if let l = c.peek(), fields(l).count == 4, l.contains("0.0") {
            d.reserved = c.next()
        }
        return d
    }

    static func readLegend(_ c: inout LineCursor, into g: inout Graph) {
        let count = int(fields(c.next()), 0, 0)
        var objects: [ObjectItem] = []
        for _ in 0..<max(count, 0) {
            c.skipBlank()
            guard let tl = c.peek(), !tl.hasPrefix("[") else { break }
            let type = int(fields(c.next()), 0, -1)
            switch type {
            case 0, 1, 2, 3:
                objects.append(ObjectItem(.shape(readShape(c.next(), objectType: type))))
            case 4, 5, 6, 7, 8:
                objects.append(ObjectItem(.text(readText(&c, kind: TextObject.Kind(rawValue: type) ?? .other))))
            case 9:
                objects.append(ObjectItem(.dot(readDot(&c))))
            case PictureObject.objectType:
                // ファイル名、4 つの整数、矢印・枠と同じ 19 個の値
                let path = c.next().trimmingCharacters(in: .whitespaces)
                let infoFields = fields(c.next())
                let info = infoFields.indices.map { int(infoFields, $0, 0) }
                let shape = readShape(c.next(), objectType: PictureObject.objectType)
                objects.append(ObjectItem(.picture(PictureObject(path: path, info: info, shape: shape))))
            default:
                var lines: [String] = []
                while let l = c.peek(), !l.hasPrefix("["), !l.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.append(c.next())
                }
                objects.append(ObjectItem(.raw(type: type, lines: lines)))
            }
        }
        g.objects = objects
        _ = c.takeUntilSection()
    }

    // 古い SMP(Ver.1.4 以前)の [TITLE]: 1 つ目が X 軸、2 つ目が Y 軸のタイトル
    static func readOldTitles(_ c: inout LineCursor, into g: inout Graph) {
        let count = int(fields(c.next()), 0, 0)
        for i in 0..<max(count, 0) {
            c.skipBlank()
            guard let l = c.peek(), !l.hasPrefix("[") else { break }
            let kind: TextObject.Kind = i == 0 ? .xTitle : (i == 1 ? .yTitle : .other)
            let t = readText(&c, kind: kind)
            if !t.text.trimmingCharacters(in: .whitespaces).isEmpty {
                g.objects.append(ObjectItem(.text(t)))
            }
        }
        _ = c.takeUntilSection()
    }

    static func readOldArrows(_ c: inout LineCursor, into g: inout Graph) {
        let count = int(fields(c.next()), 0, 0)
        for _ in 0..<max(count, 0) {
            c.skipBlank()
            guard let l = c.peek(), !l.hasPrefix("[") else { break }
            let f = fields(l)
            let type = f.count > 9 ? int(f, 9, 0) : 0
            g.objects.append(ObjectItem(.shape(readShape(c.next(), objectType: type))))
        }
        _ = c.takeUntilSection()
    }

    static func readOldDots(_ c: inout LineCursor, into g: inout Graph) {
        let count = int(fields(c.next()), 0, 0)
        for _ in 0..<max(count, 0) {
            c.skipBlank()
            guard let l = c.peek(), !l.hasPrefix("[") else { break }
            g.objects.append(ObjectItem(.dot(readDot(&c))))
        }
        _ = c.takeUntilSection()
    }

    /// [MASKS]: 数の行、マスクごとに "系列番号 xMin xMax yMin yMax"、そのあと "0" と "0" の 2 行
    static func readMasks(_ c: inout LineCursor, into g: inout Graph) {
        let count = Swift.max(int(fields(c.next()), 0, 0), 0)
        var masks: [DataMask] = []
        for _ in 0..<count {
            guard let l = c.peek(), !l.hasPrefix("[") else { break }
            let f = fields(l)
            guard f.count >= 5, f.prefix(5).allSatisfy({ Double($0) != nil }) else { break }
            c.index += 1
            masks.append(DataMask(seriesIndex: int(f, 0, 0), xMin: dbl(f, 1), xMax: dbl(f, 2), yMin: dbl(f, 3), yMax: dbl(f, 4)))
        }
        g.masks = masks
        var rest = c.takeUntilSection()
        while let last = rest.last, last.trimmingCharacters(in: .whitespaces).isEmpty { rest.removeLast() }
        g.maskTrailingLines = rest
    }

    static func readOthers(_ c: inout LineCursor, into g: inout Graph) {
        _ = c.next() // " 2"
        if let l = c.peek(), !l.hasPrefix("[") {
            let f = fields(c.next())
            var consts = f.compactMap { Double($0) }
            while consts.count < 9 { consts.append(0) }
            g.constants = Array(consts.prefix(9))
        }
        if isLogFontLine(c.peek()) {
            let ff = fields(c.next())
            let name = c.next().trimmingCharacters(in: .whitespaces)
            g.othersFont = LogFont.parse(fields: ff, faceName: name.isEmpty ? "Symbol" : name)
        }
        _ = c.takeUntilSection()
    }

    // MARK: - [DATA]

    static func readData(_ c: inout LineCursor, into p: inout SMPProject) {
        while !c.atEnd {
            guard let raw = c.peek() else { break }
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { c.index += 1; continue }
            if l == "[EOF]" { c.index += 1; return }
            if l.contains("SMP file") || l.contains("SMA file") { return }
            guard l.hasPrefix("["), let close = l.firstIndex(of: "]") else { c.index += 1; continue }
            let name = String(l[l.index(after: l.startIndex)..<close])
            let rest = String(l[l.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            c.index += 1
            var dataLines: [String] = []
            while !c.atEnd {
                let line = c.next()
                if let r = line.range(of: "[End of Data]") {
                    let before = String(line[..<r.lowerBound])
                    if !before.trimmingCharacters(in: .whitespaces).isEmpty { dataLines.append(before) }
                    break
                }
                dataLines.append(line)
            }
            // 時刻だけを残す(ファイルの大きさの 16 進は書き出すときに付け直す)
            let ts = timestampPart(rest)
            p.setDataFile(DataFile(name: name, timestamp: ts, lines: dataLines))
        }
    }

    static func timestampPart(_ s: String) -> String {
        // "1995-4-23  9:14:02 0000007e 00000000" → "1995-4-23  9:14:02"
        let f = fields(s)
        guard f.count >= 2 else { return s }
        return s.components(separatedBy: " ").filter { !$0.isEmpty }.prefix(2).joined(separator: " ")
    }
}

extension SMPReader {
    /// legendLines で書いた行をオブジェクトに戻す
    public static func legendObjects(lines: [String]) -> [GraphObject] {
        var c = LineCursor(lines)
        var g = Graph()
        readLegend(&c, into: &g)
        return g.objects.map(\.object)
    }
}
