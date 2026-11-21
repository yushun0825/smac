import Foundation
import Testing
@testable import SMPKit

@Suite("数式変換")
struct ExpressionTests {
    @Test func precedenceAndPower() throws {
        #expect(try Expression("1+2*3").evaluateScalar() == 7)
        #expect(try Expression("-2^2").evaluateScalar() == -4)
        #expect(try Expression("2^-1").evaluateScalar() == 0.5)
        #expect(try Expression("(1+2)*3").evaluateScalar() == 9)
        #expect(try Expression("2^3^2").evaluateScalar() == 512)
    }

    @Test func variablesAreCaseInsensitive() throws {
        #expect(try Expression("Y*10").evaluateScalar(y: 2) == 20)
        #expect(try Expression("1240/X").evaluateScalar(x: 620) == 2)
        #expect(abs(try Expression("sin(pi*x/180)").evaluateScalar(x: 90) - 1) < 1e-12)
    }

    @Test func constantsAndFunctions() throws {
        let c = ExprContext.constantsDictionary([2, 3])
        #expect(try Expression("a*x+b").evaluateScalar(x: 4, constants: c) == 11)
        #expect(try Expression("log(1000)").evaluateScalar() == 3)
        #expect(try Expression("ln(exp(2))").evaluateScalar() == 2)
        #expect(try Expression("max(1, 5)").evaluateScalar() == 5)
        #expect(try Expression("pow(2, 10)").evaluateScalar() == 1024)
        #expect(try Expression("abs(-3)").evaluateScalar() == 3)
        #expect(try Expression("1e-3*1000").evaluateScalar() == 1)
    }

    @Test func columnReference() throws {
        let e = try Expression("y+#0003")
        let ctx = ExprContext(count: 2, x: [0, 1], y: [10, 20], constants: [:], columnProvider: { f, c in
            f == 0 && c == 3 ? [1, 2] : nil
        })
        #expect(try e.evaluate(ctx) == [11, 22])
    }

    @Test func differenceAndIntegral() throws {
        let x: [Double] = [0, 1, 2, 3]
        let d = try Expression("dif(y)").evaluate(ExprContext(count: 4, x: x, y: [0, 1, 4, 9]))
        #expect(d == [1, 2, 4, 5])
        let i = try Expression("integ(y)").evaluate(ExprContext(count: 4, x: x, y: [1, 1, 1, 1]))
        #expect(i == [0, 1, 2, 3])
    }

    @Test func errorsAreReported() {
        #expect(throws: ExpressionError.self) { try Expression("1+") }
        #expect(throws: ExpressionError.self) { try Expression("foo(1)").evaluateScalar() }
        #expect(throws: ExpressionError.self) { try Expression("(1+2") }
    }
}

@Suite("データの読み取り")
struct DataParserTests {
    @Test func separators() {
        #expect(DataParser.parse(line: "0.0 0.70  0.50 -0.50", tabAsSpace: false) == .values([0, 0.7, 0.5, -0.5]))
        #expect(DataParser.parse(line: "1.0, 0.87", tabAsSpace: false) == .values([1, 0.87]))
        #expect(DataParser.parse(line: "4.0,4.10", tabAsSpace: false) == .values([4, 4.1]))
        if case .values(let v) = DataParser.parse(line: "2.0,,1.0", tabAsSpace: false) {
            #expect(v.count == 3 && v[1].isNaN && v[2] == 1)
        } else { Issue.record("値として読めない") }
        if case .values(let v) = DataParser.parse(line: "1\t\t2", tabAsSpace: false) {
            #expect(v.count == 3 && v[1].isNaN)
        } else { Issue.record("値として読めない") }
        #expect(DataParser.parse(line: "1\t\t2", tabAsSpace: true) == .values([1, 2]))
    }

    @Test func missingAndSkipMarks() {
        if case .values(let v) = DataParser.parse(line: "2.0 2.19 = -0.50", tabAsSpace: false) {
            #expect(v.count == 4 && v[2].isNaN)
        } else { Issue.record("値として読めない") }
        #expect(DataParser.parse(line: "2.0 | 2.19", tabAsSpace: false) == .values([2, 2.19]))
    }

    @Test func commentsAndHeaders() {
        #expect(DataParser.parse(line: "# comment", tabAsSpace: false) == .comment)
        #expect(DataParser.parse(line: "%comment", tabAsSpace: false) == .comment)
        #expect(DataParser.parse(line: "time,accel", tabAsSpace: false) == .invalid)
        #expect(DataParser.parse(line: "1.0D+03 2", tabAsSpace: false) == .values([1000, 2]))
    }

    @Test func skipLimitAndStep() {
        var s = Series(name: "d.txt")
        let lines = ["header", "1 10", "2 20", "3 30", "4 40", "5 50"]
        s.skipLines = 1
        #expect(DataParser.rows(for: s, lines: lines).count == 5)
        s.maxLines = 3
        #expect(DataParser.rows(for: s, lines: lines).map { $0[0] } == [1, 2, 3])
        s.maxLines = -1
        s.readStep = 2
        #expect(DataParser.rows(for: s, lines: lines).map { $0[0] } == [1, 3, 5])
    }
}

@Suite("最小二乗")
struct FittingTests {
    @Test func straightLine() throws {
        let r = try Fitting.polynomial(x: [0, 1, 2, 3], y: [1, 3, 5, 7], order: 1)
        guard case .polynomial(let c, _, _, _) = r.model else { Issue.record("型が違う"); return }
        #expect(abs(c[0] - 1) < 1e-9 && abs(c[1] - 2) < 1e-9)
        #expect(abs(r.correlation - 1) < 1e-12)
        #expect(abs(r.evaluate(10) - 21) < 1e-9)
    }

    @Test func passThroughPoint() throws {
        let r = try Fitting.polynomial(x: [1, 2, 3], y: [2.1, 3.9, 6.2], order: 1, passThrough: (0, 0))
        #expect(abs(r.evaluate(0)) < 1e-12)
    }

    @Test func zeroOrderIsMean() throws {
        let r = try Fitting.polynomial(x: [1, 2, 3], y: [1, 2, 6], order: 0)
        #expect(abs(r.evaluate(100) - 3) < 1e-12)
    }

    @Test func highOrderWithLargeX() throws {
        // 周波数のように大きな x でも計算が崩れない
        let xs = stride(from: 1000.0, through: 2000, by: 50).map { $0 }
        let ys = xs.map { 1e-6 * $0 * $0 - 0.002 * $0 + 3 }
        let r = try Fitting.polynomial(x: xs, y: ys, order: 2)
        #expect(abs(r.evaluate(1500) - (1e-6 * 1500 * 1500 - 3 + 3)) < 1e-6)
    }

    @Test func expLogPower() throws {
        let xs: [Double] = [1, 2, 3, 4]
        let e = try Fitting.exponential(x: xs, y: xs.map { 2 * exp(0.5 * $0) })
        #expect(abs(e.evaluate(5) - 2 * exp(2.5)) < 1e-9)
        let l = try Fitting.logarithmic(x: xs, y: xs.map { 1 + 3 * log($0) })
        #expect(abs(l.evaluate(10) - (1 + 3 * log(10))) < 1e-9)
        let p = try Fitting.power(x: xs, y: xs.map { 4 * pow($0, 1.5) })
        #expect(abs(p.evaluate(9) - 4 * 27) < 1e-6)
    }

    @Test func generalFunction() throws {
        let xs: [Double] = [0, 0.5, 1, 1.5, 2, 2.5, 3]
        let ys = xs.map { 0.6 * exp(0.8 * $0) }
        let r = try Fitting.general(x: xs, y: ys, function: "a*exp(b*x)", derivatives: ["exp(b*x)", "a*x*exp(b*x)"],
                                    initial: ["a": 1, "b": 1])
        guard case .general(_, let p) = r.model else { Issue.record("型が違う"); return }
        #expect(abs((p["a"] ?? 0) - 0.6) < 1e-6)
        #expect(abs((p["b"] ?? 0) - 0.8) < 1e-6)
        // 偏微分なし(差分)でも収束する
        let r2 = try Fitting.general(x: xs, y: ys, function: "a*exp(b*x)", initial: ["a": 1, "b": 1])
        #expect(abs(r2.evaluate(1) - 0.6 * exp(0.8)) < 1e-5)
    }

    @Test func generalFunctionWithFixedParameter() throws {
        let xs: [Double] = [0, 0.5, 1, 1.5, 2, 2.5, 3]
        let ys = xs.map { 0.6 * exp(0.8 * $0) }
        // b を初期値 0.5 のまま固定すると a だけを動かす(a は Σ y e^{0.5x} / Σ e^{x} になる)
        let r = try Fitting.general(x: xs, y: ys, function: "a*exp(b*x)", derivatives: ["exp(b*x)", "a*x*exp(b*x)"],
                                    initial: ["a": 1, "b": 0.5], fixed: ["b"])
        guard case .general(_, let p) = r.model else { Issue.record("型が違う"); return }
        #expect(p["b"] == 0.5)
        let best = zip(xs, ys).reduce(0) { $0 + $1.1 * exp(0.5 * $1.0) } / xs.reduce(0) { $0 + exp($1) }
        #expect(abs((p["a"] ?? 0) - best) < 1e-9)
        #expect(r.summary.contains("b = 0.5"))
        // 正しい b で固定すれば a も正しい。許容誤差(%)を付けても収束する
        let r2 = try Fitting.general(x: xs, y: ys, function: "a*exp(b*x)", initial: ["a": 1, "b": 0.8],
                                     fixed: ["b"], tolerancePercent: 0.001)
        guard case .general(_, let p2) = r2.model else { Issue.record("型が違う"); return }
        #expect(p2["b"] == 0.8 && abs((p2["a"] ?? 0) - 0.6) < 1e-6)
        // 全部固定なら計算するだけ
        let r3 = try Fitting.general(x: xs, y: ys, function: "a*exp(b*x)", initial: ["a": 0.6, "b": 0.8], fixed: ["a", "b"])
        #expect(r3.chiSquare < 1e-20)

        // 系列の設定から: 新しい形の初期値の行(9 と 10 個の値)と generalFixed
        let line158 = "9 2.000000e-02 1.000000e+00 5.000000e-01 0.000000e+00 0.000000e+00 0.000000e+00 0.000000e+00 0.000000e+00 3.000000e+00 4.000000e+00"
        #expect(SeriesEvaluator.initialParameters(line158) == ["a": 1, "b": 0.5, "c": 0, "d": 0, "e": 0, "f": 0, "g": 0, "h": 3, "i": 4])
        #expect(SeriesEvaluator.parameterLineTolerance(line158) == 0.02)
        #expect(SeriesEvaluator.initialParameters("7 1 2 3 4 5 6 7 0") == ["a": 1, "b": 2, "c": 3, "d": 4, "e": 5, "f": 6, "g": 7])
        #expect(SeriesEvaluator.parameterLineTolerance("7 1 2 3 4 5 6 7 0") == nil)
        var project = SMPProject()
        project.setDataFile(DataFile(name: "e.dat", lines: zip(xs, ys).map { "\($0) \($1)" }))
        var g = Graph.makeDefault()
        var s = Series(name: "e.dat")
        s.kind = .generalLSQ
        s.kindRaw = 7
        s.generalFunction = "a*exp(b*x)"
        s.generalParameterLine = line158
        s.generalFixed = ["b"]
        g.series = [s]
        project.graphs = [g]
        let d = SeriesEvaluator.evaluate(graph: g, project: project)
        guard case .general(_, let p4)? = d[0].fit?.model else { Issue.record("最小二乗が無い: \(d[0].error ?? "")"); return }
        #expect(p4["b"] == 0.5 && abs((p4["a"] ?? 0) - best) < 1e-6)

        // SMP から: 新しい形の行の許容誤差を読み、行はそのまま書く
        let text = fixtureSMP
            .replacingOccurrences(of: "3 0 0 0 0 1 0 0 -1\n", with: "7 0 0 0 0 1 0 0 -1\n")
            .replacingOccurrences(of: "1 40 0 300 1\n\n\n[GRAPH]",
                                  with: "1 40 0 300 1\n\(line158)\na*exp(b*x)\nexp(b*x)\na*x*exp(b*x)\n" + String(repeating: "\n", count: 7) + "[GRAPH]")
        let read = try SMPReader.read(text: text).graphs[0].series[1]
        #expect(read.kind == .generalLSQ && read.generalFunction == "a*exp(b*x)" && read.generalTolerance == 0.02)
        #expect(read.generalDerivatives.prefix(2) == ["exp(b*x)", "a*x*exp(b*x)"])
        #expect(SMPWriter.text(for: try SMPReader.read(text: text)).contains("\r\n\(line158)\r\na*exp(b*x)\r\n"))
        #expect(Series(name: "n").generalTolerance == 0.001 && Series(name: "n").generalFixed.isEmpty)
    }

    @Test func spline() {
        let c = Spline.curve(x: [0, 1, 2, 3], y: [0, 1, 0, 1], mode: .cubic, samples: [0, 1, 2, 3, 4], divisions: 10)
        #expect(abs(c[1].1 - 1) < 1e-12 && abs(c[2].1) < 1e-12)
        #expect(c[4].1.isNaN)
        let closed = Spline.curve(x: [0, 1, 0, -1], y: [1, 0, -1, 0], mode: .closedParametric, samples: [], divisions: 40)
        #expect(closed.count == 41)
        #expect(abs(closed.first!.0 - closed.last!.0) < 1e-9 && abs(closed.first!.1 - closed.last!.1) < 1e-9)
    }
}

@Suite("目盛り")
struct ScaleTests {
    @Test func linearTicksAreMultiplesOfIncrement() {
        var a = AxisSpec()
        a.from = -200; a.to = 200; a.increment = 90; a.division = 2
        let majors = AxisScale(a).ticks().filter(\.isMajor).map(\.value)
        #expect(majors == [-180, -90, 0, 90, 180])
    }

    @Test func labelFormatting() {
        var a = AxisSpec()
        a.from = 0; a.to = 1.5; a.increment = 0.5
        let labels = AxisScale(a).ticks().filter(\.isMajor).compactMap(\.label)
        #expect(labels == ["0", "0.5", "1.0", "1.5"])
        a.from = 0; a.to = 1200; a.increment = 200
        // 3 桁区切りのコンマは付けない
        #expect(AxisScale(a).ticks().filter(\.isMajor).compactMap(\.label).last == "1200")
    }

    @Test func logTicks() {
        var a = AxisSpec()
        a.scaleType = .logNormal
        a.from = 0.2; a.to = 30; a.increment = 5; a.division = 10
        let t = AxisScale(a).ticks()
        #expect(t.filter(\.isMajor).compactMap(\.label) == ["0.5", "1", "5", "10"])
        #expect(t.filter { !$0.isMajor }.count > 10)
        a.scaleType = .logExponent
        a.from = 0.01; a.to = 1; a.increment = 10
        #expect(AxisScale(a).ticks().filter(\.isMajor).compactMap(\.label) == ["10^-2@", "10^-1@", "10^0@"])
    }

    @Test func autoScale() {
        let a = AxisScale.autoScaled(AxisSpec(), minValue: 0.87, maxValue: 16.29)
        #expect(a.from == 0 && a.to == 20 && a.increment == 5)
        var l = AxisSpec(); l.scaleType = .logNormal
        let b = AxisScale.autoScaled(l, minValue: 3, maxValue: 450)
        #expect(b.from == 1 && b.to == 1000)
    }
}

@Suite("文字列の制御コード")
struct RichTextTests {
    @Test func scriptsAndCodes() {
        let t = RichTextParser.parse("W/m^2@")
        #expect(t == [.text("W/m"), .superscript, .text("2"), .endScript])
        #expect(RichTextParser.parse("A_1@") == [.text("A"), .`subscript`, .text("1"), .endScript])
        #expect(RichTextParser.parse("a\\nb") == [.text("a"), .newline, .text("b")])
        #expect(RichTextParser.parse("%Q176") == [.charCode(176)])
        #expect(RichTextParser.parse("%01E%01N") == [.seriesMarker(1), .seriesName(1, lower: false)])
        #expect(RichTextParser.parse("%X+99ln") == [.shiftX(99), .text("ln")])
        #expect(RichTextParser.parse("%KFF0000赤") == [.color(SMPColor(r: 255, g: 0, b: 0)), .text("赤")])
        #expect(RichTextParser.parse("100%%") == [.text("100%")])
        #expect(RichTextParser.parse("a@b") == [.text("a@b")])
    }

    @Test func plainText() {
        #expect(RichTextParser.plainText("TIME (%Gm%As)") == "TIME (μs)")
        #expect(RichTextParser.plainText("20%Q176C") == "20°C")
        #expect(RichTextParser.plainText("%GDw%A") == "Δω")
    }
}
