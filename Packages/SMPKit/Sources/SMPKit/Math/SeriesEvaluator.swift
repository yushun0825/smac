import Foundation

/// 1 つの系列を描くための値(数式変換をした後の値)
public struct SeriesPlotData: Sendable {
    public var x: [Double] = []
    public var y: [Double] = []
    /// 元の行の値(値を読む・値のコピー用)
    public var rawRows: [[Double]] = []
    public var errorX: [(lo: Double, hi: Double)]?
    public var errorY: [(lo: Double, hi: Double)]?
    /// 最小二乗・スプライン・任意関数・特殊処理の曲線
    public var curve: [(x: Double, y: Double)] = []
    public var fit: FitResult?
    /// 結果の文(最小二乗は FitResult.summary の各行、特殊処理はその結果の行)
    public var resultLines: [String] = []
    /// Gaussian・Lorentzian fitting で求めた値
    public var fittedPeaks: PeakFitSettings?
    /// 除く範囲に入った点(x・y と同じ並び。この系列にマスクが無ければ空)。除いた点の x・y は NaN にしてある
    public var masked: [Bool] = []
    public var error: String?

    public init() {}

    public var finitePoints: [(Double, Double)] {
        zip(x, y).filter { $0.0.isFinite && $0.1.isFinite }
    }
}

public enum SeriesEvaluator {
    /// グラフの全系列を計算する(#ffcc の列参照のため、前の系列の値を使えるようにまとめて計算する)
    public static func evaluate(graph: Graph, project: SMPProject) -> [SeriesPlotData] {
        var rowsCache: [[[Double]]] = graph.series.map { s in
            guard s.kind != .function, let f = project.dataFile(named: s.name) else { return [] }
            return DataParser.rows(for: s, lines: f.lines)
        }
        // 関数の系列は行を作っておく(x を入れる)
        for (i, s) in graph.series.enumerated() where s.kind == .function {
            rowsCache[i] = curveSamples(s, graph: graph).map { [$0, $0] }
        }
        return graph.series.indices.map { i in
            evaluate(index: i, graph: graph, rowsCache: rowsCache)
        }
    }

    static func column(_ rows: [[Double]], _ c: Int) -> [Double] {
        if c < 0 { return rows.indices.map(Double.init) }
        return rows.map { c < $0.count ? $0[c] : .nan }
    }

    static func movingAverage(_ v: [Double], _ n: Int) -> [Double] {
        guard n > 0, v.count > 1 else { return v }
        var out = v
        for i in v.indices {
            var s = 0.0, k = 0
            for j in Swift.max(0, i - n)...Swift.min(v.count - 1, i + n) where v[j].isFinite { s += v[j]; k += 1 }
            out[i] = k > 0 ? s / Double(k) : .nan
        }
        return out
    }

    static func evaluate(index: Int, graph: Graph, rowsCache: [[[Double]]]) -> SeriesPlotData {
        let s = graph.series[index]
        var out = SeriesPlotData()
        let rows = rowsCache[index]
        out.rawRows = rows
        let n = rows.count

        var x: [Double], y: [Double]
        if s.kind == .function {
            x = column(rows, 0); y = column(rows, 1)
        } else {
            x = column(rows, s.columnX)
            y = column(rows, s.columnY)
        }
        x = movingAverage(x, s.horizontalAverage)
        y = movingAverage(y, s.verticalAverage)
        let baseX = x, baseY = y

        let constants = ExprContext.constantsDictionary(graph.constants)
        let provider: (Int, Int) -> [Double]? = { file, col in
            let src = file == 0 ? index : file - 1
            guard src >= 0, src < rowsCache.count else { return nil }
            var c = column(rowsCache[src], col - 1)
            if c.count < n { c += Array(repeating: .nan, count: n - c.count) }
            return Array(c.prefix(n))
        }
        func transform(_ expr: String, useX: Bool, xv: [Double], yv: [Double]) -> [Double]? {
            let t = expr.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.lowercased() == (useX ? "x" : "y") { return useX ? xv : yv }
            do {
                let e = try Expression(t)
                let ctx = ExprContext(count: n, x: xv, y: yv, abscissa: baseX, constants: constants, columnProvider: provider)
                return try e.evaluate(ctx)
            } catch {
                out.error = "\(s.displayName): \((error as? ExpressionError)?.message ?? error.localizedDescription)"
                return nil
            }
        }
        let needXTransform = s.transformX || s.kind == .function && s.expressionX.lowercased() != "x"
        let needYTransform = s.transformY || s.kind == .function
        let tx = needXTransform ? (transform(s.expressionX, useX: true, xv: baseX, yv: baseY) ?? baseX) : baseX
        let ty = needYTransform ? (transform(s.expressionY, useX: false, xv: baseX, yv: baseY) ?? baseY) : baseY
        out.x = tx
        out.y = ty

        // エラーバー
        func bars(_ mode: Series.ErrorBar, valueColumn: Int, isY: Bool) -> [(lo: Double, hi: Double)]? {
            guard mode != .none, s.kind != .function, valueColumn >= 0 else { return nil }
            let c1 = column(rows, valueColumn + 1)
            let c2 = column(rows, valueColumn + 2)
            let base = isY ? baseY : baseX
            var hiRaw = [Double](repeating: .nan, count: n), loRaw = hiRaw
            for i in 0..<n {
                switch mode {
                case .plusPlus: hiRaw[i] = base[i] + c1[i]; loRaw[i] = base[i] + c2[i]
                case .plusMinus: hiRaw[i] = base[i] + c1[i]; loRaw[i] = base[i] - c1[i]
                case .none: break
                }
            }
            let doTransform = isY ? needYTransform : needXTransform
            let expr = isY ? s.expressionY : s.expressionX
            var hi = hiRaw, lo = loRaw
            if doTransform {
                hi = transform(expr, useX: !isY, xv: isY ? baseX : hiRaw, yv: isY ? hiRaw : baseY) ?? hiRaw
                lo = transform(expr, useX: !isY, xv: isY ? baseX : loRaw, yv: isY ? loRaw : baseY) ?? loRaw
            }
            return (0..<n).map { (lo: Swift.min(lo[$0], hi[$0]), hi: Swift.max(lo[$0], hi[$0])) }
        }
        out.errorY = bars(s.errorBarY, valueColumn: s.columnY, isY: true)
        out.errorX = bars(s.errorBarX, valueColumn: s.columnX, isY: false)

        // 除く範囲(描画・値を読む・最小二乗・範囲合わせのどれからも除く)
        applyMasks(graph.masks, seriesIndex: index, to: &out)

        // 曲線
        if s.kind.isLSQ || s.kind == .spline || s.kind == .extension1 {
            computeCurve(s, graph: graph, out: &out)
        }
        return out
    }

    /// 系列 seriesIndex のマスクの範囲に入る点を欠損(NaN)にする。範囲外の番号のマスクは無視する
    static func applyMasks(_ masks: [DataMask], seriesIndex: Int, to out: inout SeriesPlotData) {
        let mine = masks.filter { $0.seriesIndex == seriesIndex }
        guard !mine.isEmpty else { return }
        let n = Swift.min(out.x.count, out.y.count)
        var masked = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let x = out.x[i], y = out.y[i]
            guard x.isFinite, y.isFinite, mine.contains(where: { $0.contains(x: x, y: y) }) else { continue }
            masked[i] = true
            out.x[i] = .nan
            out.y[i] = .nan
            if let e = out.errorX, i < e.count { out.errorX![i] = (lo: .nan, hi: .nan) }
            if let e = out.errorY, i < e.count { out.errorY![i] = (lo: .nan, hi: .nan) }
        }
        out.masked = masked
    }

    /// 連続データの X の並び
    public static func curveSamples(_ s: Series, graph: Graph, dataRange: (Double, Double)? = nil) -> [Double] {
        var a = s.curveStart, b = s.curveEnd
        if a == b {
            if let r = dataRange { a = r.0; b = r.1 } else {
                let ax = graph.axes[graph.horizontalAxisIndex(for: s)]
                a = ax.from; b = ax.to
                if ax.scaleType.isInverse { a = ax.from == 0 ? 0 : 1 / ax.from; b = ax.to == 0 ? 0 : 1 / ax.to }
            }
        }
        let n = Swift.min(Swift.max(s.curveDivisions, 2), 20000)
        switch s.curveSpacing {
        case .exponential where a > 0 && b > 0:
            return (0...n).map { a * Foundation.pow(b / a, Double($0) / Double(n)) }
        case .reciprocal where a != 0 && b != 0:
            let ua = 1 / a, ub = 1 / b
            return (0...n).map { k in 1 / (ua + (ub - ua) * Double(k) / Double(n)) }
        default:
            return (0...n).map { a + (b - a) * Double($0) / Double(n) }
        }
    }

    static func inAxisRange(_ v: Double, _ a: AxisSpec) -> Bool {
        guard let f = AxisScale(a).fraction(v) else { return false }
        return f >= -1e-9 && f <= 1 + 1e-9
    }

    static func computeCurve(_ s: Series, graph: Graph, out: inout SeriesPlotData) {
        let hAxis = graph.axes[graph.horizontalAxisIndex(for: s)]
        let vAxis = graph.axes[graph.verticalAxisIndex(for: s)]
        var pts = out.finitePoints
        if !s.considerOutOfRange {
            pts = pts.filter { inAxisRange($0.0, hAxis) && inAxisRange($0.1, vAxis) }
        }
        let xs = pts.map(\.0), ys = pts.map(\.1)
        let range: (Double, Double)? = xs.isEmpty ? nil : (xs.min()!, xs.max()!)
        do {
            switch s.kind {
            case .polynomialLSQ:
                let fit = try Fitting.polynomial(x: xs, y: ys, order: s.lsqOrder,
                                                 passThrough: s.passThroughPoint ? (s.passX, s.passY) : nil)
                out.fit = fit
                let sx = curveSamples(s, graph: graph, dataRange: range)
                out.curve = zip(sx, fit.evaluate(sx)).map { (x: $0.0, y: $0.1) }
            case .expLSQ, .logLSQ, .powerLSQ:
                let fit: FitResult
                switch s.kind {
                case .expLSQ: fit = try Fitting.exponential(x: xs, y: ys)
                case .logLSQ: fit = try Fitting.logarithmic(x: xs, y: ys)
                default: fit = try Fitting.power(x: xs, y: ys)
                }
                out.fit = fit
                let sx = curveSamples(s, graph: graph, dataRange: range)
                out.curve = zip(sx, fit.evaluate(sx)).map { (x: $0.0, y: $0.1) }
            case .generalLSQ:
                let initial = initialParameters(s.generalParameterLine)
                let fit = try Fitting.general(x: xs, y: ys, function: s.generalFunction, derivatives: s.generalDerivatives,
                                              initial: initial, constants: ExprContext.constantsDictionary(graph.constants),
                                              fixed: s.generalFixed, tolerancePercent: s.generalTolerance)
                out.fit = fit
                let sx = curveSamples(s, graph: graph, dataRange: range)
                out.curve = zip(sx, fit.evaluate(sx)).map { (x: $0.0, y: $0.1) }
            case .spline:
                let mode = Spline.Mode(rawValue: s.lsqOrder) ?? .cubic
                let logX = hAxis.scaleType.isLog, logY = vAxis.scaleType.isLog
                let fx = logX ? xs.map { $0 > 0 ? Foundation.log10($0) : .nan } : xs
                let fy = logY ? ys.map { $0 > 0 ? Foundation.log10($0) : .nan } : ys
                var samples = curveSamples(s, graph: graph, dataRange: range)
                if logX { samples = samples.map { $0 > 0 ? Foundation.log10($0) : .nan } }
                let c = Spline.curve(x: fx, y: fy, mode: mode, samples: samples, divisions: s.curveDivisions)
                out.curve = c.map { p in
                    (x: logX ? Foundation.pow(10, p.0) : p.0, y: logY ? Foundation.pow(10, p.1) : p.1)
                }
            case .extension1:
                guard let a = s.extensionAnalysis else { break }
                let samples = a.usesFittingDialog ? curveSamples(s, graph: graph, dataRange: range) : []
                let r = try ExtensionAnalyzer.run(a, x: xs, y: ys, settings: s.peakFit, samples: samples)
                out.resultLines = r.lines
                out.curve = r.curve
                if a.usesFittingDialog { out.fittedPeaks = r.fitted }
            default:
                break
            }
            if let fit = out.fit { out.resultLines = fit.summary.components(separatedBy: "\n") }
        } catch {
            out.error = "\(s.displayName): \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
        }
    }

    /// 一般関数の初期値の行。1.4 までは "7 1 1 1 1 1 1 1 0"(個数と a〜g)。
    /// 新しい形は "%d %le …"(9 と 10 個の値: 1 つ目は許容誤差、そのあと a〜i)
    public static func initialParameters(_ line: String) -> [String: Double] {
        let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Double($0) }
        var d: [String: Double] = [:]
        if isVersion158ParameterLine(f) {
            for (i, name) in ["a", "b", "c", "d", "e", "f", "g", "h", "i"].enumerated() { d[name] = f[i + 2] }
            return d
        }
        guard f.count >= 2 else { return d }
        for (i, name) in Fitting.parameterNames.enumerated() where i + 1 < f.count { d[name] = f[i + 1] }
        return d
    }

    /// 新しい形の初期値の行の 1 つ目の値(許容誤差 %)。古い形なら nil
    public static func parameterLineTolerance(_ line: String) -> Double? {
        let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Double($0) }
        return isVersion158ParameterLine(f) ? f[1] : nil
    }

    static func isVersion158ParameterLine(_ f: [Double]) -> Bool { f.count >= 11 && f[0] == 9 }

    /// 系列の X・Y の最小値と最大値(範囲合わせ用)
    public static func extent(_ data: [SeriesPlotData], series: [Series], axisIndex: Int, graph: Graph) -> (Double, Double)? {
        var lo = Double.infinity, hi = -Double.infinity
        let horizontal = axisIndex == 0 || axisIndex == 2
        let positiveOnly = graph.axes[axisIndex].scaleType.isLog
        for (i, s) in series.enumerated() where s.visible && i < data.count {
            let idx = horizontal ? graph.horizontalAxisIndex(for: s) : graph.verticalAxisIndex(for: s)
            guard idx == axisIndex else { continue }
            let d = data[i]
            var values = horizontal ? d.x : d.y
            if let e = horizontal ? d.errorX : d.errorY {
                values += e.flatMap { [$0.lo, $0.hi] }
            }
            for v in values where v.isFinite && (!positiveOnly || v > 0) {
                lo = Swift.min(lo, v); hi = Swift.max(hi, v)
            }
        }
        return lo <= hi ? (lo, hi) : nil
    }
}
