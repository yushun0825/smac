import Foundation
import CoreGraphics
import Testing
@testable import SMPKit

let fixedNow = Date(timeIntervalSince1970: 0)

/// ID は保存しないので揃えてから比べる
func sameGraph(_ a: Graph, _ b: Graph) -> Bool {
    var b = b
    b.id = a.id
    b.name = a.name
    guard a.series.count == b.series.count, a.objects.count == b.objects.count else { return false }
    for i in a.series.indices { b.series[i].id = a.series[i].id }
    for i in a.objects.indices { b.objects[i].id = a.objects[i].id }
    return a == b
}

@Suite("除く範囲")
struct DataMaskTests {
    static let maskedFixture = fixtureSMP.replacingOccurrences(
        of: "[MASKS]\n 0\n0\n0\n",
        with: "[MASKS]\n 2\n0 1.500000e+01 6.000000e+01 0.000000e+00 1.000000e+01\n5 0.000000e+00 1.000000e+00 0.000000e+00 1.000000e+00\n0\n0\n")

    func data() -> Data { SMPTextEncoding.encodeSMP(DataMaskTests.maskedFixture.replacingOccurrences(of: "\n", with: "\r\n")) }

    @Test func readsAndWritesMasks() throws {
        #expect(DataMaskTests.maskedFixture != fixtureSMP)
        let p = try SMPReader.read(data: data(), fileName: "m.SMP")
        let g = p.graphs[0]
        #expect(g.masks == [DataMask(seriesIndex: 0, xMin: 15, xMax: 60, yMin: 0, yMax: 10),
                            DataMask(seriesIndex: 5, xMin: 0, xMax: 1, yMin: 0, yMax: 1)])
        #expect(g.maskTrailingLines == ["0", "0"])
        let text = SMPWriter.text(for: p, now: fixedNow)
        #expect(text.contains("[MASKS]\r\n 2\r\n0 1.500000e+01 6.000000e+01 0.000000e+00 1.000000e+01\r\n5 0.000000e+00 1.000000e+00 0.000000e+00 1.000000e+00\r\n0\r\n0\r\n\r\n[DATA]"))
        let back = try SMPReader.read(data: SMPWriter.data(for: p, now: fixedNow), fileName: "m.SMP")
        #expect(sameGraph(g, back.graphs[0]))
        #expect(SMPWriter.text(for: back, now: fixedNow) == text)

        // マスクの無いファイルはこれまでと同じ形
        let plain = try SMPReader.read(data: fixtureData())
        #expect(plain.graphs[0].masks.isEmpty)
        #expect(SMPWriter.text(for: plain, now: fixedNow).contains("[MASKS]\r\n 0\r\n0\r\n0\r\n\r\n[DATA]"))
        // マスクの後ろの知らない行も残る
        let odd = fixtureSMP.replacingOccurrences(of: "[MASKS]\n 0\n0\n0\n", with: "[MASKS]\n 0\n0\n0\n7 7\n")
        let oddProject = try SMPReader.read(text: odd)
        #expect(oddProject.graphs[0].maskTrailingLines == ["0", "0", "7 7"])
        #expect(SMPWriter.text(for: oddProject, now: fixedNow).contains("[MASKS]\r\n 0\r\n0\r\n0\r\n7 7\r\n\r\n"))
    }

    @Test func maskedPointsAreMissing() throws {
        let p = try SMPReader.read(data: data())
        let d = SeriesEvaluator.evaluate(graph: p.graphs[0], project: p)
        // x = 20・50(y は 1 前後)がマスクの中
        #expect(d[0].masked == [false, true, true, false, false, false, false])
        #expect(d[0].x[1].isNaN && d[0].y[2].isNaN && d[0].x[3] == 100)
        #expect(d[0].finitePoints.count == 5)
        #expect(d[0].fit?.pointCount == 5)
        // 範囲外の系列番号(5)のマスクは無視し、他の系列は除かない
        #expect(d[1].masked.isEmpty)
    }

    @Test func maskExcludedFromFitAndScale() throws {
        var p = SMPProject()
        p.setDataFile(DataFile(name: "line.dat", lines: ["1 3 0.5", "2 5 0.5", "3 100 50", "4 9 0.5", "5 11 0.5"]))
        var g = Graph.makeDefault()
        var s = Series(name: "line.dat")
        s.kind = .polynomialLSQ
        s.kindRaw = 1
        s.lsqOrder = 1
        s.considerOutOfRange = true
        s.errorBarY = .plusMinus
        g.series = [s]
        g.masks = [DataMask(seriesIndex: 0, xMin: 3.5, xMax: 2.5, yMin: 50, yMax: 150)]
        p.graphs = [g]
        let d = SeriesEvaluator.evaluate(graph: g, project: p)
        guard case .polynomial(let c, _, _, _) = d[0].fit?.model else { Issue.record("最小二乗が無い"); return }
        #expect(abs(c[0] - 1) < 1e-9 && abs(c[1] - 2) < 1e-9)
        #expect(d[0].masked == [false, false, true, false, false])
        #expect(d[0].errorY?[2].hi.isNaN == true && d[0].errorY?[3].hi == 9.5)
        // 範囲合わせにも入らない(エラーバーも)
        #expect(SeriesEvaluator.extent(d, series: g.series, axisIndex: 1, graph: g)?.1 == 11.5)
        GraphOps.clearScale(&p, graphIndex: 0, axes: [1])
        #expect(p.graphs[0].axes[1].to < 100)
        // 系列を消して番号が合わなくなっても落ちない
        p.graphs[0].masks.append(DataMask(seriesIndex: -1, xMin: 0, xMax: 1, yMin: 0, yMax: 1))
        p.graphs[0].masks.append(DataMask(seriesIndex: 99, xMin: 0, xMax: 1, yMin: 0, yMax: 1))
        #expect(SeriesEvaluator.evaluate(graph: p.graphs[0], project: p).count == 1)
    }
}

/// 赤い 4×4 の画像
func redImage() -> CGImage? {
    let ctx = makeBitmap(4, 4)
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    return ctx.makeImage()
}

@Suite("図")
struct PictureTests {
    func picture() -> PictureObject {
        var shape = ShapeObject()
        shape.x1 = 10; shape.y1 = 20; shape.x2 = 60; shape.y2 = 50
        shape.tail = ["0", "7"]
        return PictureObject(path: "C:\\Users\\lab\\写真.bmp", info: [0, 0, 640, 480], shape: shape)
    }

    @Test func roundTripInSMP() throws {
        var p = try SMPReader.read(data: fixtureData(), fileName: "test.SMP")
        let pic = picture()
        #expect(pic.shape.objectType == 10)
        p.graphs[0].objects.insert(ObjectItem(.picture(pic)), at: 1)
        let text = SMPWriter.text(for: p, now: fixedNow)
        #expect(text.contains("[LEGEND]\r\n5\r\n"))
        #expect(text.contains("\r\n10\r\nC:\\Users\\lab\\写真.bmp\r\n0 0 640 480\r\n1.000000e+01 2.000000e+01 6.000000e+01 5.000000e+01 0 0 40 500 0 0 300 1 16777215 0 0 1 30 100 0 7\r\n\r\n5\r\n"))
        let back = try SMPReader.read(data: SMPWriter.data(for: p, now: fixedNow), fileName: "test.SMP")
        #expect(back.graphs[0].objects.count == 5)
        guard case .picture(let q) = back.graphs[0].objects[1].object else { Issue.record("図が無い"); return }
        #expect(q == pic)
        // 図の後ろのオブジェクトもずれずに読める
        guard case .text(let yTitle) = back.graphs[0].objects[2].object else { Issue.record("Y 軸タイトルが無い"); return }
        #expect(yTitle.kind == .yTitle)
        #expect(sameGraph(p.graphs[0], back.graphs[0]))
        #expect(SMPWriter.text(for: back, now: fixedNow) == text)
        // コピー・貼り付けの行
        #expect(SMPReader.legendObjects(lines: SMPWriter.legendLines([.picture(pic), .shape(ShapeObject())])).first == .picture(pic))
        // 情報の行が無いものは 0 0 0 0 で書く
        let bare = PictureObject(path: "a.wmf", info: [])
        #expect(SMPWriter.legendLines([.picture(bare)])[3] == "0 0 0 0")
        #expect(PictureObject.newInfo(pixelWidth: 320, pixelHeight: 200) == [0, 0, 320, 200])
    }

    @Test func boundsAndDrawing() throws {
        var p = try SMPReader.read(data: fixtureData(), fileName: "test.SMP")
        // 系列(赤い線を含む)は消して、図だけを描く
        p.graphs[0].series = []
        p.graphs[0].objects = []
        let rect = CGRect(x: 0, y: 0, width: 20000, height: 16000)
        let empty = try #require(GraphExporter.cgImage(renderer: GraphRenderer(project: p), rect: rect, dpi: 72))
        p.graphs[0].objects = [ObjectItem(.picture(picture()))]
        let r = GraphRenderer(project: p)
        #expect(r.objectBounds(.picture(picture()), graphIndex: 0) == CGRect(x: 1000, y: 2000, width: 5000, height: 3000))
        #expect(r.contentBounds(graphIndex: 0).contains(CGRect(x: 5000, y: 4000, width: 5000, height: 3000)))

        // 画像が無いときは灰色の枠と ×
        let missing = try #require(GraphExporter.cgImage(renderer: r, rect: rect, dpi: 72))
        func inked(_ p: RGBA) -> Bool { p.r < 250 || p.g < 250 || p.b < 250 }
        #expect(countPixels(missing, where: inked) > countPixels(empty, where: inked) + 300)
        #expect(countPixels(missing, where: isReddish) == 0)

        var options = RenderOptions()
        options.pictureProvider = { _ in redImage() }
        let shown = try #require(GraphExporter.cgImage(renderer: GraphRenderer(project: p, options: options), rect: rect, dpi: 72))
        // 50 mm × 30 mm ≒ 142 × 85 画素が赤い
        #expect(countPixels(shown, where: isReddish) > 10000)
    }
}

/// 2 つのピークと offset の合成データ
func peakData(_ shape: ExtensionAnalysis, noise: Bool = false) -> (x: [Double], y: [Double]) {
    let k = 4 * log(2.0)
    let xs = stride(from: 0.0, through: 100, by: 0.5).map { $0 }
    let ys = xs.enumerated().map { i, x -> Double in
        let bump = noise ? 0.01 * sin(Double(i) * 1.7) : 0
        switch shape {
        case .lorentzian:
            return 2 + 10 / (1 + 4 * pow(x - 30, 2) / 64) + 6 / (1 + 4 * pow(x - 62, 2) / 144) + bump
        default:
            return 2 + 10 * exp(-k * pow(x - 30, 2) / 64) + 6 * exp(-k * pow(x - 62, 2) / 144) + bump
        }
    }
    return (xs, ys)
}

func roughStart() -> PeakFitSettings {
    var s = PeakFitSettings()
    s.count = 2
    s.offset = 1
    s.intensity[0] = 8; s.position[0] = 28; s.width[0] = 10
    s.intensity[1] = 5; s.position[1] = 65; s.width[1] = 9
    return s
}

@Suite("特殊処理")
struct ExtensionAnalysisTests {
    @Test func menu() {
        #expect(ExtensionAnalysis.allCases.map(\.rawValue) == ["GAUSSF2", "LORENF2", "GetMax", "GetMin", "PeakDct", "SMOOTH"])
        #expect(ExtensionAnalysis.allCases.map(\.rawValue) == ["GAUSSF2", "LORENF2", "GetMax", "GetMin", "PeakDct", "SMOOTH"])
        #expect(ExtensionAnalysis.allCases.filter(\.usesFittingDialog) == [.gaussian, .lorentzian])
        var s = Series(name: "a.dat")
        s.extensionAnalysis = .peakDetect
        #expect(s.kind == .extension1 && s.kindRaw == 8 && !s.hasCurve)
        s.extensionAnalysis = .smoothing
        #expect(s.hasCurve)
        s.extensionAnalysis = nil
        #expect(s.kind == .normal && s.kindRaw == 0)
    }

    @Test(arguments: [ExtensionAnalysis.gaussian, .lorentzian])
    func recoversTwoPeaks(_ a: ExtensionAnalysis) throws {
        let (xs, ys) = peakData(a)
        let r = try ExtensionAnalyzer.run(a, x: xs, y: ys, settings: roughStart(), samples: [30, 62])
        let f = r.fitted
        #expect(abs(f.offset - 2) < 1e-6)
        #expect(abs(f.intensity[0] - 10) < 1e-6 && abs(f.position[0] - 30) < 1e-6 && abs(f.width[0] - 8) < 1e-6)
        #expect(abs(f.intensity[1] - 6) < 1e-6 && abs(f.position[1] - 62) < 1e-6 && abs(f.width[1] - 12) < 1e-6)
        #expect(r.lines == ["offset= 2", "1:Int.= 10", "1:Pos = 30", "1:Width=8", "2:Int.= 6", "2:Pos = 62", "2:Width=12"])
        #expect(r.curve.count == 2 && abs(r.curve[0].y - ys[60]) < 1e-6 && abs(r.curve[1].y - ys[124]) < 1e-6)

        // データから作った初期値からでも、少し揺らしたデータでも収束する
        let (nx, ny) = peakData(a, noise: true)
        let guess = PeakFitSettings.initialGuess(x: nx, y: ny, count: 2)
        #expect(guess.count == 2 && abs(guess.position[0] - 30) <= 1 && abs(guess.position[1] - 62) <= 1)
        let g = try ExtensionAnalyzer.run(a, x: nx, y: ny, settings: guess, samples: []).fitted
        #expect(abs(g.position[0] - 30) < 0.01 && abs(g.position[1] - 62) < 0.01)
        #expect(abs(g.width[0] - 8) < 0.05 && abs(g.intensity[1] - 6) < 0.05 && abs(g.offset - 2) < 0.05)
    }

    @Test func uncheckedParametersStayFixed() throws {
        let (xs, ys) = peakData(.gaussian)
        var s = roughStart()
        s.position[0] = 31
        s.varyPosition[0] = false
        s.offset = 2
        s.varyOffset = false
        let f = try ExtensionAnalyzer.run(.gaussian, x: xs, y: ys, settings: s, samples: []).fitted
        #expect(f.position[0] == 31 && f.offset == 2)
        #expect(abs(f.position[1] - 62) < 0.1)
        // 何も動かさなければ初期値のまま曲線を描く
        var none = roughStart()
        none.varyOffset = false
        for i in 0..<PeakFitSettings.maxPeaks { none.varyIntensity[i] = false; none.varyPosition[i] = false; none.varyWidth[i] = false }
        let r = try ExtensionAnalyzer.run(.gaussian, x: xs, y: ys, settings: none, samples: [28])
        #expect(r.fitted == none.normalized && abs(r.curve[0].y - 9) < 1e-12)
        #expect(throws: FitError.self) { try ExtensionAnalyzer.run(.gaussian, x: [], y: [], settings: roughStart(), samples: []) }
    }

    @Test func maxMinPeakSmooth() throws {
        let x: [Double] = [1, 2, 3, 4, 5]
        let y: [Double] = [3, 9, .nan, 1, 9]
        #expect(try ExtensionAnalyzer.run(.getMax, x: x, y: y, settings: PeakFitSettings(), samples: []).lines == ["MAX(X,Y)= 2, 9"])
        #expect(try ExtensionAnalyzer.run(.getMin, x: x, y: y, settings: PeakFitSettings(), samples: []).lines == ["MIN(X,Y)= 4, 1"])
        #expect(throws: FitError.self) { try ExtensionAnalyzer.run(.getMax, x: [.nan], y: [1], settings: PeakFitSettings(), samples: []) }

        // 2 つのピーク + (最大 − 最小) の 5 % に届かない小さな山
        var (px, py) = peakData(.gaussian)
        py = zip(px, py).map { $1 + 0.2 * exp(-pow($0 - 85, 2) / 2) }
        let peaks = try ExtensionAnalyzer.run(.peakDetect, x: px.reversed(), y: py.reversed(), settings: PeakFitSettings(), samples: [])
        #expect(peaks.lines == ["(x,y)=(30, 12)", "(x,y)=(62, 8)"])
        #expect(peaks.curve.isEmpty)
        #expect(ExtensionAnalyzer.detectPeaks(x: px, y: py, minimumFraction: 0.01).count == 3)
        // 平らな頂上は真ん中
        #expect(ExtensionAnalyzer.detectPeaks(x: [0, 1, 2, 3, 4, 5], y: [0, 1, 5, 5, 5, 0]).map(\.x) == [3])

        let sx = (0..<10).map(Double.init)
        let spike: [Double] = [0, 0, 0, 0, 10, 0, 0, 0, 0, 0]
        let sm = try ExtensionAnalyzer.run(.smoothing, x: sx, y: spike, settings: PeakFitSettings(), samples: [1, 2])
        #expect(sm.curve.map(\.x) == sx)
        #expect(sm.curve.map(\.y) == [0, 0, 2, 2, 2, 2, 2, 0, 0, 0])
        #expect(sm.lines.isEmpty)
        let line = sx.map { 2 * $0 + 1 }
        #expect(ExtensionAnalyzer.movingAverage(line)[2..<8].elementsEqual(line[2..<8]))
        #expect(ExtensionAnalyzer.movingAverage([4, 8]) == [6, 6])
    }

    func extensionProject(_ a: ExtensionAnalysis) -> SMPProject {
        let (xs, ys) = peakData(a == .lorentzian ? .lorentzian : .gaussian)
        var p = SMPProject()
        p.setDataFile(DataFile(name: "peaks.dat", timestamp: "2026-11-21 10:00:00", lines: zip(xs, ys).map { "\($0) \($1)" }))
        var g = Graph.makeDefault()
        g.axes[0].from = 0; g.axes[0].to = 100; g.axes[0].increment = 20
        g.axes[1].from = 0; g.axes[1].to = 15; g.axes[1].increment = 5
        var s = Series(name: "peaks.dat")
        s.extensionAnalysis = a
        s.peakFit = PeakFitSettings.initialGuess(x: xs, y: ys, count: 2)
        s.curveDivisions = 100
        s.curveLineType = .dash
        g.series = [s]
        p.graphs = [g]
        return p
    }

    @Test func evaluatorRunsAnalyses() throws {
        for a in ExtensionAnalysis.allCases {
            let p = extensionProject(a)
            let d = SeriesEvaluator.evaluate(graph: p.graphs[0], project: p)[0]
            #expect(d.error == nil, "\(a)")
            #expect(d.x.count == 201)
            #expect(d.curve.isEmpty == !a.producesCurve, "\(a)")
            #expect(d.resultLines.isEmpty == (a == .smoothing), "\(a)")
            #expect((d.fittedPeaks != nil) == a.usesFittingDialog)
            if a.usesFittingDialog {
                #expect(d.curve.count == 101 && d.curve.first?.x == 0 && d.curve.last?.x == 100)
                #expect(abs((d.fittedPeaks?.position[1] ?? 0) - 62) < 1e-4)
            }
            _ = GraphExporter.cgImage(renderer: GraphRenderer(project: p), dpi: 36)
        }
        // 最小二乗の結果も同じ形で出る
        let fixture = try SMPReader.read(data: fixtureData())
        let d = SeriesEvaluator.evaluate(graph: fixture.graphs[0], project: fixture)
        #expect(!d[0].resultLines.isEmpty && d[0].resultLines == d[0].fit?.summary.components(separatedBy: "\n"))
    }

    @Test func kind8InSMP() throws {
        var p = extensionProject(.gaussian)
        p.graphs[0].series[0].peakFit.precision = 1e-8
        p.graphs[0].series[0].peakFit.varyWidth[1] = false
        p.graphs[0].series[0].extraLines = ["UNKNOWN 1"]
        let s = p.graphs[0].series[0]
        let text = SMPWriter.text(for: p, now: fixedNow)
        #expect(text.contains("[peaks.dat]\r\npeaks.dat\r\n8 0 0 0 0 1 "))
        let f = s.peakFit
        let expected = ["GAUSSF2", "2 1 \(f.offset) 1e-08",
                        "\(f.intensity[0]) \(f.position[0]) \(f.width[0]) 1 1 1",
                        "\(f.intensity[1]) \(f.position[1]) \(f.width[1]) 1 1 0",
                        "1.0 0.0 1.0 1 1 1", "1.0 0.0 1.0 1 1 1", "1.0 0.0 1.0 1 1 1", "1.0 0.0 1.0 1 1 1", "UNKNOWN 1"]
        #expect(text.contains("\r\n" + expected.joined(separator: "\r\n") + "\r\n\r\n\r\n[GRAPH]"))
        let back = try SMPReader.read(data: SMPWriter.data(for: p, now: fixedNow))
        let t = back.graphs[0].series[0]
        #expect(t.kind == .extension1 && t.extensionAnalysis == .gaussian)
        #expect(t.peakFit == s.peakFit)
        #expect(t.extraLines == ["UNKNOWN 1"])
        #expect(sameGraph(p.graphs[0], back.graphs[0]))
        #expect(SMPWriter.text(for: back, now: fixedNow) == text)

        // 名前だけの形・知らない形も読める
        let named = text.replacingOccurrences(of: expected.dropLast().joined(separator: "\r\n"), with: "SMOOTH")
        let n = try SMPReader.read(text: named).graphs[0].series[0]
        #expect(n.extensionAnalysis == .smoothing && n.peakFit == PeakFitSettings() && n.extraLines == ["UNKNOWN 1"])
        let foreign = text.replacingOccurrences(of: expected.dropLast().joined(separator: "\r\n"), with: "FOO 1 2 3")
        let foreignProject = try SMPReader.read(text: foreign)
        let u = foreignProject.graphs[0].series[0]
        #expect(u.kind == .extension1 && u.extensionAnalysis == nil && u.extraLines == ["FOO 1 2 3", "UNKNOWN 1"])
        #expect(SMPWriter.text(for: foreignProject, now: fixedNow).contains("\r\nFOO 1 2 3\r\nUNKNOWN 1\r\n"))
        #expect(SeriesEvaluator.evaluate(graph: foreignProject.graphs[0], project: foreignProject)[0].curve.isEmpty)
    }
}

/// 手元の SMP ファイルで確かめる(環境変数 SMP_SAMPLE_DIR のフォルダの *.SMP。なければ飛ばす)
@Suite("手元の SMP ファイル")
struct LocalSampleTests {
    static var files: [URL] {
        guard let path = ProcessInfo.processInfo.environment["SMP_SAMPLE_DIR"],
              let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return names.filter { $0.lowercased().hasSuffix(".smp") }.sorted().map { URL(fileURLWithPath: path).appendingPathComponent($0) }
    }
    static var available: Bool { !files.isEmpty }

    /// オブジェクトの種類と中身の要点(読み直しで形の揃う細かい値は除く)
    func summary(_ o: GraphObject) -> String {
        switch o {
        case .text(let t): return "text \(t.kind.rawValue) \(t.x) \(t.y) \(t.text)"
        case .shape(let s): return "shape \(s.objectType) \(s.x1) \(s.y1) \(s.x2) \(s.y2) \(s.width) \(s.length)"
        case .dot(let d): return "dot \(d.x) \(d.y) \(d.dotType) \(d.size)"
        case .picture(let p): return "picture \(p.path)"
        case .raw(let type, let lines): return "raw \(type) \(lines)"
        }
    }

    @Test(.enabled(if: LocalSampleTests.available))
    func samplesKeepEverything() throws {
        for url in LocalSampleTests.files {
            let n = url.lastPathComponent
            guard let data = try? Data(contentsOf: url) else { continue }
            let p = try SMPReader.read(data: data, fileName: url.lastPathComponent)
            let written = SMPWriter.data(for: p, now: fixedNow)
            let again = try SMPReader.read(data: written, fileName: url.lastPathComponent)
            #expect(again.graphs.count == 1 && p.graphs.count == 1)
            let a = p.graphs[0], b = again.graphs[0]
            #expect(b.series.count == a.series.count, "\(n)")
            #expect(b.objects.count == a.objects.count && !a.objects.isEmpty, "\(n)")
            #expect(b.objects.map { summary($0.object) } == a.objects.map { summary($0.object) }, "\(n)")
            #expect(b.series.map(\.dotType) == a.series.map(\.dotType))
            #expect(b.masks == a.masks)
            #expect(again.dataFiles.mapValues(\.lines) == p.dataFiles.mapValues(\.lines))
            // 書き直したものをもう一度書いても同じ
            #expect(SMPWriter.data(for: again, now: fixedNow) == written, "\(n)")
            // 描ける
            #expect(GraphExporter.cgImage(renderer: GraphRenderer(project: p), dpi: 36) != nil)
        }
    }
}
