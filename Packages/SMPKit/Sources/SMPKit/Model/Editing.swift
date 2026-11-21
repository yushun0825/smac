import Foundation

/// データファイルを開いたときの初期値などの設定
public struct DataOpenPreferences: Sendable, Equatable {
    public var autoDotType = true
    public var autoLineType = false
    public var autoDotColor = false
    public var autoLineColor = false
    public var autoScaleX = true
    public var autoScaleY = true

    public init() {}
}

public enum DataImport {
    /// データファイルの中身を行にする(最後の空行は落とす)
    public static func dataFile(name: String, contents: Data, timestamp: String = "") -> DataFile {
        let text = SMPTextEncoding.decodeDataFile(contents)
        var lines = SMPTextEncoding.splitLines(text)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return DataFile(name: name, timestamp: timestamp, lines: lines)
    }

    public static let autoColors: [SMPColor] = [
        .black, SMPColor(r: 255, g: 0, b: 0), SMPColor(r: 0, g: 0, b: 255), SMPColor(r: 0, g: 128, b: 0),
        SMPColor(r: 255, g: 0, b: 255), SMPColor(r: 0, g: 128, b: 128), SMPColor(r: 128, g: 0, b: 0),
        SMPColor(r: 0, g: 0, b: 128),
    ]

    /// 新しい系列。既定は線なし・●・大きさ 300・中塗り白・ハッチ 5。
    /// 自動更新が入っていれば、1 つ前の系列(previous。無ければ index 番目まで既定から順に進めた値)の次にする:
    /// ドットは PlotType.next(after:)、線種は LineType.next(after:)。
    public static func newSeries(name: String, path: String, index: Int, preferences: DataOpenPreferences = DataOpenPreferences(),
                                 previous: Series? = nil) -> Series {
        var s = Series(name: name, path: path)
        if preferences.autoDotType {
            if let p = previous {
                s.dotType = PlotType.next(after: p.dotType)
            } else {
                var code = PlotType.defaultCode
                for _ in 0..<Swift.max(index, 0) { code = PlotType.next(after: code) }
                s.dotType = code
            }
        }
        if preferences.autoLineType {
            if let p = previous {
                s.lineType = LineType.next(after: p.lineType)
            } else {
                var t = s.lineType
                for _ in 0..<Swift.max(index, 0) { t = LineType.next(after: t) }
                s.lineType = t
            }
        }
        if preferences.autoDotColor { s.dotColor = autoColors[Swift.max(index, 0) % autoColors.count] }
        if preferences.autoLineColor { s.lineColor = autoColors[Swift.max(index, 0) % autoColors.count] }
        s.curveColor = s.lineColor
        return s
    }

    /// 同じ名前で中身の違うデータがあるときは名前を変える
    public static func uniqueName(_ name: String, contents: DataFile, in project: SMPProject) -> String {
        guard let existing = project.dataFile(named: name), existing.lines != contents.lines else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var k = 2
        while true {
            let candidate = ext.isEmpty ? "\(base)(\(k))" : "\(base)(\(k)).\(ext)"
            if let e = project.dataFile(named: candidate) {
                if e.lines == contents.lines { return candidate }
            } else { return candidate }
            k += 1
        }
    }

    /// 列の数が 1 つだけのデータなら Numbering にする
    public static func guessColumns(_ file: DataFile, series: inout Series) {
        for line in file.lines.prefix(200) {
            if case .values(let v) = DataParser.parse(line: line, tabAsSpace: series.tabAsSpace) {
                if v.count == 1 { series.columnX = -1; series.columnY = 0 }
                return
            }
        }
    }

    /// データファイル 1 つからグラフを作る(データファイルを開いたとき)
    public static func project(fromDataFile name: String, path: String, contents: Data,
                               base: Graph? = nil, preferences: DataOpenPreferences = DataOpenPreferences()) -> SMPProject {
        var p = SMPProject()
        let file = dataFile(name: name, contents: contents, timestamp: SMPWriter.timestamp(Date()))
        p.setDataFile(file)
        var g = base ?? Graph.makeDefault()
        g.name = ((name as NSString).deletingPathExtension) + ".SMP"
        var s = newSeries(name: name, path: path, index: 0, preferences: preferences)
        guessColumns(file, series: &s)
        s.linesRead = DataParser.rows(for: s, lines: file.lines).count
        g.series = [s]
        p.graphs = [g]
        GraphOps.clearScale(&p, graphIndex: 0, axes: [0, 1])
        return p
    }
}

extension Graph {
    /// 既定のグラフ(14 cm × 10 cm の横長)
    public static func makeDefault() -> Graph {
        var g = Graph()
        g.left = 4000; g.top = 2000; g.width = 14000; g.height = 10000
        g.frameType = .box
        g.axes = (0..<4).map { AxisSpec.defaultAxis(index: $0) }
        return g
    }
}

public enum GraphOps {
    /// 範囲合わせ: データの範囲に合わせて軸を設定し直す(間隔の自動が外れていれば始めと終わりだけ)
    public static func clearScale(_ p: inout SMPProject, graphIndex gi: Int, axes: [Int]) {
        guard gi < p.graphs.count else { return }
        var g = p.graphs[gi]
        // 変換後の値は軸の種類によらないので、一度計算すればよい
        let data = SeriesEvaluator.evaluate(graph: g, project: p)
        for a in axes {
            guard let (lo, hi) = SeriesEvaluator.extent(data, series: g.series, axisIndex: a, graph: g) else { continue }
            let old = g.axes[a]
            var scaled = AxisScale.autoScaled(old, minValue: lo, maxValue: hi)
            if !old.autoStep {
                scaled.increment = old.increment
                scaled.division = old.division
            }
            g.axes[a] = scaled
        }
        p.graphs[gi] = g
    }

    /// 系列に使われていないデータを消す
    public static func pruneData(_ p: inout SMPProject) {
        let used = Set(p.graphs.flatMap { $0.series.filter { $0.kind != .function }.map { SMPProject.key($0.name) } })
        p.dataFiles = p.dataFiles.filter { used.contains($0.key) }
    }

    /// 凡例の文字列("%01E%01N\n%02E%02N" の形)
    public static func legendText(seriesIndices: [Int], useCurve: [Bool] = []) -> String {
        seriesIndices.enumerated().map { k, i in
            let n = String(format: "%02d", i + 1)
            let curve = k < useCurve.count && useCurve[k]
            return "%\(n)\(curve ? "F" : "E")%\(n)N"
        }.joined(separator: "\\n")
    }
}
