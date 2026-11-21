import Foundation
import Testing
@testable import SMPKit

/// SMP 形式で書いた試験用のファイル(内容はこのテスト用に作ったもの)
let fixtureSMP = """
 Sma4Win ver. 1.8  SMP file
振動試験の結果
1 1 210 297 0 100 2
2
[sweep.csv]
C:\\Users\\lab\\sweep.csv
1 0 0 2 0 1 7 1 -1
40 255 300 0 0 1 0
1 2 250 16711680
0 0 1 0 0 0 16777215 5
0 1 0
x
y*9.80665
0 201 2 0 1.000000e+01 1.000000e+03 0.000000e+00 0.000000e+00 0.000000e+00
2 60 0 300 1


[fit.dat]
fit.dat
3 0 0 0 0 1 0 0 -1
40 0 300 0 0 0 0
1 0 300 0
0 0 1 0 0 0 16777215 5
0 1 0
x
a*x
0 101 0 0 1.000000e+00 1.000000e+03 0.000000e+00 0.000000e+00 0.000000e+00
1 40 0 300 1


[GRAPH]
4000 2000 14000 10000
100 1 0 0 1 0
40 0 0 16777215

[AXIS-0]
1.000000e+01 1.000000e+03 1.000000e+01 0 0 10000 -1 -1 0 1 0 0 1 5 5 1.000000e+00 1
10 3 0 1 1 1 0 0 0 300 100 0
-2400 0 0 0 400 0 0 0 0 3 2 1 18
Times New Roman
1 0 300 40 0 0 1
1 0 150 40 0 0 1

[AXIS-1]
0.000000e+00 1.000000e+01 2.000000e+00 0 0 10000 -1 -1 0 1 0 0 1 5 5 1.000000e+00 1
2 0 0 1 1 1 -200 0 0 1200 100 0
-2400 0 0 0 400 0 0 0 0 3 2 1 18
Times New Roman
1 0 300 40 0 0 1
1 0 150 40 0 0 1

[AXIS-2]
1.000000e+01 1.000000e+03 1.000000e+01 0 0 10000 -1 -1 0 1 0 0 1 5 5 1.000000e+00 1
10 3 0 1 1 0 0 0 0 900 100 0
-2400 0 0 0 400 0 0 0 0 3 2 1 18
Times New Roman
1 0 300 40 0 0 1
1 0 150 40 0 0 1

[AXIS-3]
0.000000e+00 1.000000e+01 2.000000e+00 0 0 10000 -1 -1 0 1 0 0 1 5 5 1.000000e+00 1
2 0 0 1 1 0 0 0 0 -14578 100 0
-2400 0 0 0 400 0 0 0 0 3 2 1 18
Times New Roman
1 0 300 40 0 0 1
1 0 150 40 0 0 1

[LEGEND]
4
4
5000 11800 0 1 0 0
Frequency [Hz]
-2400 0 0 0 400 0 0 0 0 3 2 1 18
Times New Roman
-2400 0 0 0 400 0 0 0 128 3 2 1 17
ＭＳ 明朝
-2400 0 0 0 400 0 0 0 2 3 2 1 18
Symbol

5
-1500 7000 0 1 0 0
加速度 [m/s^2@]
-2400 0 -900 900 400 0 0 0 0 3 2 1 18
Times New Roman
-2400 0 -900 900 400 0 0 0 128 3 2 1 17
ＭＳ 明朝
-2400 0 0 0 400 0 0 0 2 3 2 1 18
Symbol

0
1.000000e+02 2.000000e+01 8.000000e+01 3.000000e+01 0 0 40 500 0 0 300 1 16777215 0 0 1 30 100 0

9
10000 1000 1 40 1000 1 300 255 0 300 0 16777215 5 0
1
0 0 0.0 0.0

[OTHERS]
 2
2.000000e+00 0.000000e+00 0.000000e+00 0.000000e+00 0.000000e+00 0.000000e+00 0.000000e+00 0.000000e+00 0.000000e+00
-2400 0 0 0 400 0 0 0 2 3 2 1 18
Symbol

[MASKS]
 0
0
0

[DATA]
[sweep.csv] 2026-11-1  9:05:30 00000050 00000000
周波数[Hz],加速度[G]
10,0.101
20,0.105
50,0.131
100,0.208
200,0.912
500,0.421
1000,0.117
[End of Data]


"""

func fixtureData() -> Data {
    SMPTextEncoding.encodeSMP(fixtureSMP.replacingOccurrences(of: "\n", with: "\r\n"))
}

@Suite("SMP の読み書き")
struct SMPTests {
    @Test func readsAllSections() throws {
        let p = try SMPReader.read(data: fixtureData(), fileName: "test.SMP")
        #expect(p.graphs.count == 1)
        let g = p.graphs[0]
        #expect(g.comment == "振動試験の結果")
        #expect(g.series.count == 2)
        let s = g.series[0]
        #expect(s.name == "sweep.csv" && s.path == "C:\\Users\\lab\\sweep.csv")
        #expect(s.kind == .polynomialLSQ && s.errorBarY == .plusMinus)
        #expect(s.columnX == 0 && s.columnY == 1 && s.skipLines == 1 && s.maxLines == -1)
        #expect(s.lineColor == SMPColor(r: 255, g: 0, b: 0))
        #expect(s.lineType == .solid && s.dotType == 2 && s.dotSize == 250)
        #expect(s.dotColor == SMPColor(r: 0, g: 0, b: 255))
        #expect(s.skipCommentCount)
        #expect(!s.transformX && s.transformY && s.expressionY == "y*9.80665")
        #expect(s.curveDivisions == 201 && s.lsqOrder == 2 && s.curveStart == 10 && s.curveEnd == 1000)
        #expect(s.curveLineType == .dash && s.curveWidth == 60)
        #expect(g.series[1].kind == .function && g.series[1].expressionY == "a*x")

        #expect(g.left == 4000 && g.width == 14000 && g.frameType == .box)
        #expect(g.axes[0].scaleType == .logNormal && g.axes[0].from == 10 && g.axes[0].to == 1000)
        #expect(g.axes[0].division == 10 && !g.axes[0].autoStep)
        #expect(g.axes[1].labelShiftX == -200)
        #expect(g.axes[0].font.pointSize == 24)
        #expect(g.objects.count == 4)
        guard case .text(let yTitle) = g.objects[1].object else { Issue.record("Y 軸タイトルが無い"); return }
        #expect(yTitle.kind == .yTitle && yTitle.text == "加速度 [m/s^2@]" && yTitle.angle == 90)
        guard case .shape(let arrow) = g.objects[2].object else { Issue.record("矢印が無い"); return }
        #expect(arrow.x1 == 100 && arrow.y2 == 30 && arrow.length == 500 && arrow.headMode == 1)
        guard case .dot(let dot) = g.objects[3].object else { Issue.record("ドットが無い"); return }
        #expect(dot.x == 10000 && dot.size == 300)
        #expect(g.constants[0] == 2)
        let data = try #require(p.dataFile(named: "SWEEP.CSV"))
        #expect(data.lines.count == 8 && data.lines[0] == "周波数[Hz],加速度[G]")
    }

    @Test func evaluatesSeries() throws {
        let p = try SMPReader.read(data: fixtureData())
        let d = SeriesEvaluator.evaluate(graph: p.graphs[0], project: p)
        #expect(d[0].x == [10, 20, 50, 100, 200, 500, 1000])
        #expect(abs(d[0].y[0] - 0.101 * 9.80665) < 1e-12)
        #expect(d[0].fit != nil && d[0].curve.count == 202)
        // 任意関数 a*x(a = 2)
        #expect(d[1].x.first == 1 && d[1].y.first == 2)
        #expect(d[1].x.count == 102)
    }

    @Test func writesWhatItReads() throws {
        let p = try SMPReader.read(data: fixtureData(), fileName: "test.SMP")
        let text = SMPWriter.text(for: p, now: Date(timeIntervalSince1970: 0))
        #expect(text.contains("\r\n"))
        #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(text.hasPrefix(" Sma4Win ver. 1.8  SMP file\r\n振動試験の結果\r\n1 1 210 297 0 100 2\r\n2\r\n[sweep.csv]\r\n"))
        // 軸の範囲は %e の形で書く
        #expect(text.contains("[AXIS-0]\r\n1.000000e+01 1.000000e+03 1.000000e+01 0 0 10000 -1 -1 0 1 0 0 1 5 5 1.000000e+00 1\r\n"))
        #expect(text.contains("1 0 0 2 0 1 7 1 -1 \r\n"))
        #expect(text.contains("[sweep.csv] 2026-11-1  9:05:30 "))
        let p2 = try SMPReader.read(data: SMPWriter.data(for: p), fileName: "test.SMP")
        var a = p.graphs[0], b = p2.graphs[0]
        // ID は保存しないので揃えてから比べる
        b.id = a.id
        for i in a.series.indices { b.series[i].id = a.series[i].id }
        for i in a.objects.indices { b.objects[i].id = a.objects[i].id }
        a.name = b.name
        #expect(a == b)
        #expect(p.dataFiles.mapValues(\.lines) == p2.dataFiles.mapValues(\.lines))
        // 2 回目の書き出しは 1 回目と同じ
        #expect(SMPWriter.text(for: p2, now: Date(timeIntervalSince1970: 0)) == text)
    }

    @Test func multiGraphFile() throws {
        var p = try SMPReader.read(data: fixtureData(), fileName: "a.SMP")
        var second = p.graphs[0]
        second.name = "b.SMP"
        second.top = 14000
        p.graphs.append(second)
        let data = SMPWriter.data(for: p)
        let text = SMPTextEncoding.decodeSMP(data)
        #expect(text.hasPrefix(" Sma4Win ver. 1.1  SMA file\r\n 2 0 0 0 0 100\r\n[a.SMP]\r\n Sma4Win ver. 1.8  SMP file"))
        #expect(text.components(separatedBy: "[DATA]").count == 2)
        let back = try SMPReader.read(data: data)
        #expect(back.graphs.count == 2 && back.graphs[1].top == 14000 && back.graphs[1].name == "b.SMP")
        #expect(back.dataFile(named: "sweep.csv")?.lines.count == 8)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: SMPReadError.self) { try SMPReader.read(text: "hello\nworld") }
    }

    @Test func dataFileImport() throws {
        let url = try #require(Bundle.module.url(forResource: "sweep_sjis", withExtension: "csv", subdirectory: "Fixtures"))
        let p = DataImport.project(fromDataFile: "sweep_sjis.csv", path: url.path, contents: try Data(contentsOf: url))
        let d = SeriesEvaluator.evaluate(graph: p.graphs[0], project: p)
        #expect(d[0].x == [10, 20, 50, 100, 200, 500, 1000])
        #expect(p.dataFile(named: "sweep_sjis.csv")?.lines.first == "周波数[Hz],加速度[G]")
        // 自動のスケールで全部が入る
        let ax = p.graphs[0].axes[0]
        #expect(ax.from <= 10 && ax.to >= 1000)

        let url2 = try #require(Bundle.module.url(forResource: "tabbed_utf8", withExtension: "txt", subdirectory: "Fixtures"))
        let p2 = DataImport.project(fromDataFile: "tabbed_utf8.txt", path: url2.path, contents: try Data(contentsOf: url2))
        #expect(SeriesEvaluator.evaluate(graph: p2.graphs[0], project: p2)[0].y == [0.1, 0.2])
    }

    /// 手元の SMP ファイル(SMP_SAMPLE_DIR のフォルダにあるとき)を読んで書き直せる
    @Test func localSamplesIfPresent() throws {
        for url in LocalSampleTests.files {
            guard let data = try? Data(contentsOf: url) else { continue }
            let p = try SMPReader.read(data: data, fileName: url.lastPathComponent)
            #expect(p.graphs.count == 1)
            let again = try SMPReader.read(data: SMPWriter.data(for: p))
            #expect(again.graphs[0].series.count == p.graphs[0].series.count)
            #expect(again.graphs[0].objects.count == p.graphs[0].objects.count)
        }
    }
}
