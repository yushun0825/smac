import Foundation
import CoreGraphics
import Testing
@testable import SMPKit

/// RGBA の小さなビットマップ(透明で始まる)
func makeBitmap(_ w: Int = 64, _ h: Int = 64) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

struct RGBA: Equatable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8
}

func pixel(_ ctx: CGContext, _ x: Int, _ y: Int) -> RGBA {
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let i = y * ctx.bytesPerRow + x * 4
    return RGBA(r: p[i], g: p[i + 1], b: p[i + 2], a: p[i + 3])
}

/// 画像の中で色が近い画素の数
func countPixels(_ image: CGImage, where match: (RGBA) -> Bool) -> Int {
    let ctx = makeBitmap(image.width, image.height)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    var n = 0
    for y in 0..<image.height { for x in 0..<image.width where match(pixel(ctx, x, y)) { n += 1 } }
    return n
}

func isReddish(_ p: RGBA) -> Bool { p.a > 200 && p.r > 200 && p.g < 80 && p.b < 80 }

@Suite("プロットの種類")
struct PlotTypeTests {
    @Test func tables() {
        #expect(PlotType.seriesCodes == Array(0...28) + [33, 34] + Array(38...52))
        #expect(PlotType.dotObjectCodes == Array(0...32) + Array(38...52))
        #expect(PlotType.defaultCode == 2)
        let titled = (0...60).compactMap { c in PlotType.title(c).map { (c, $0) } }
        #expect(titled.map(\.0) == [0, 13, 26, 27, 28, 33, 34])
        #expect(titled.map(\.1) == ["なし", "縦棒", "横棒", "矩形", "対角線", "縦階段", "横階段"])
        #expect((0...60).filter(PlotType.isBarOrStep) == [13, 26, 27, 28, 33, 34])
        #expect((0...60).filter(PlotType.fillsWithDotColor) == [2, 4, 6, 8, 10, 13, 19, 20, 21, 22, 23, 26, 27, 33, 34])
        #expect((-1...60).filter { !PlotType.drawsMark($0) } == [-1, 0, 29, 30, 31, 32, 35, 36, 37] + Array(53...60))
    }

    @Test func autoCycle() {
        var c = PlotType.defaultCode
        var seen = [c]
        for _ in 0..<21 { c = PlotType.next(after: c); seen.append(c) }
        #expect(seen == [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 1, 2])
        #expect(PlotType.next(after: 0) == 1 && PlotType.next(after: 30) == 1)
        var t = LineType.none
        var lines: [Int] = []
        for _ in 0..<7 { t = LineType.next(after: t); lines.append(t.rawValue) }
        #expect(lines == [1, 2, 3, 4, 5, 1, 2])
        #expect(LineType.next(after: .fill) == .solid)
    }

    @Test func newSeriesDefaults() {
        let s = Series(name: "a.dat")
        #expect(s.lineType == .none && s.dotType == 2 && s.dotSize == 300)
        #expect(s.brushStyle == 0 && s.brushColor == .white && s.brushHatch == 5)
        var prefs = DataOpenPreferences()
        prefs.autoDotType = true
        prefs.autoLineType = true
        let codes = (0..<13).map { DataImport.newSeries(name: "d", path: "d", index: $0, preferences: prefs).dotType }
        #expect(codes == [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15])
        let first = DataImport.newSeries(name: "d", path: "d", index: 0, preferences: prefs)
        #expect(first.lineType == .none)
        let second = DataImport.newSeries(name: "e", path: "e", index: 1, preferences: prefs, previous: first)
        #expect(second.dotType == 3 && second.lineType == .solid)
        var last = first
        last.dotType = 22
        last.lineType = .dashDotDot
        let wrapped = DataImport.newSeries(name: "f", path: "f", index: 7, preferences: prefs, previous: last)
        #expect(wrapped.dotType == 1 && wrapped.lineType == .solid)
        prefs.autoDotType = false
        prefs.autoLineType = false
        let plain = DataImport.newSeries(name: "g", path: "g", index: 4, preferences: prefs)
        #expect(plain.dotType == 2 && plain.lineType == .none)
    }

    @Test func brushMapping() {
        #expect(DotBrush.titles == ["中塗", "中空", "中白", "ﾊｯﾁ1", "ﾊｯﾁ2", "ﾊｯﾁ3", "ﾊｯﾁ4", "ﾊｯﾁ5", "ﾊｯﾁ6"])
        for i in DotBrush.titles.indices {
            let v = DotBrush.values(index: i)
            #expect(DotBrush.index(style: v.style, hatch: v.hatch) == i)
        }
        #expect(DotBrush.index(style: 0, hatch: 5) == 0)
        #expect(DotBrush.index(style: 1, hatch: 5) == 1)
        #expect(DotBrush.index(style: 2, hatch: 0) == 2)
        #expect(DotBrush.index(style: 2, hatch: 4) == 6)
        let zero = DotBrush.values(index: 0), hollow = DotBrush.values(index: 1), hatch6 = DotBrush.values(index: 8)
        #expect(zero.style == 0 && zero.hatch == 0)
        #expect(hollow.style == 1 && hollow.hatch == 0)
        #expect(hatch6.style == 2 && hatch6.hatch == 6)
    }

    @Test func everyCodeDraws() {
        let ctx = makeBitmap()
        for code in -2...60 {
            for style in 0...3 {
                for hatch in 0...7 {
                    GraphRenderer.drawPlotMark(code: code, center: CGPoint(x: 32, y: 32), diameter: 30, dotColor: .red,
                                               lineWidth: 2, brushStyle: style, brushColor: .blue, brushHatch: hatch, in: ctx)
                }
            }
            // 大きさ 0・太さ 0・描けない中心でも落ちない
            GraphRenderer.drawPlotMark(code: code, center: CGPoint(x: 10, y: 10), diameter: 0, dotColor: .black,
                                       lineWidth: 0, brushStyle: 2, brushColor: .white, brushHatch: 3, in: ctx)
            GraphRenderer.drawPlotMark(code: code, center: CGPoint(x: CGFloat.nan, y: 10), diameter: 10, dotColor: .black,
                                       lineWidth: 1, brushStyle: 0, brushColor: .white, brushHatch: 0, in: ctx)
        }
    }

    /// 中心の画素(大きさ 40 の印を 64×64 の真ん中に描く)
    func center(_ code: Int, style: Int, hatch: Int = 5) -> RGBA {
        let ctx = makeBitmap()
        GraphRenderer.drawPlotMark(code: code, center: CGPoint(x: 32, y: 32), diameter: 40, dotColor: .red, lineWidth: 2,
                                   brushStyle: style, brushColor: .blue, brushHatch: hatch, in: ctx)
        return pixel(ctx, 32, 32)
    }

    @Test func fillRule() {
        let red = RGBA(r: 255, g: 0, b: 0, a: 255), blue = RGBA(r: 0, g: 0, b: 255, a: 255)
        let white = RGBA(r: 255, g: 255, b: 255, a: 255), clear = RGBA(r: 0, g: 0, b: 0, a: 0)
        #expect(center(2, style: 0) == red)      // ● はドットの色
        #expect(center(1, style: 0) == blue)     // ○ は中塗色
        #expect(center(1, style: 1) == clear)    // 中空
        #expect(center(1, style: 2) == blue)     // ドットの色で塗らない値は lbStyle 2 も塗り
        #expect(center(6, style: 2, hatch: 0) == white) // 中白
        #expect(center(6, style: 1) == clear)
        #expect(center(10, style: 0) == red && center(9, style: 0) == blue)
        #expect(center(23, style: 0) == red && center(18, style: 0) == blue)
        #expect(center(13, style: 0) == red && center(26, style: 0) == red && center(27, style: 0) == red)

        // 何も描かない値
        for code in [0, 29, 35] {
            let ctx = makeBitmap()
            GraphRenderer.drawPlotMark(code: code, center: CGPoint(x: 32, y: 32), diameter: 40, dotColor: .red, lineWidth: 2,
                                       brushStyle: 0, brushColor: .blue, brushHatch: 0, in: ctx)
            #expect((0..<64).allSatisfy { y in (0..<64).allSatisfy { x in pixel(ctx, x, y).a == 0 } })
        }

        // 半分塗り: 左はドットの色、右は中塗色
        let half = makeBitmap()
        GraphRenderer.drawPlotMark(code: 44, center: CGPoint(x: 32, y: 32), diameter: 40, dotColor: .red, lineWidth: 2,
                                   brushStyle: 0, brushColor: .blue, brushHatch: 0, in: half)
        #expect(pixel(half, 22, 32) == red && pixel(half, 42, 32) == blue)

        // ハッチ: 中の一部だけがドットの色になる
        let hatched = makeBitmap()
        GraphRenderer.drawPlotMark(code: 6, center: CGPoint(x: 32, y: 32), diameter: 40, dotColor: .red, lineWidth: 2,
                                   brushStyle: 2, brushColor: .blue, brushHatch: 4, in: hatched)
        var painted = 0, total = 0
        for y in 20..<44 { for x in 20..<44 { total += 1; if pixel(hatched, x, y).a > 0 { painted += 1 } } }
        #expect(painted > total / 20 && painted < total * 9 / 10)
        // 斜線はドットの色(なめらかにした線なので、濃さは画素ごとに違う)
        #expect((20..<44).contains { y in (20..<44).contains { x in let q = pixel(hatched, x, y); return q.r > 100 && q.g == 0 && q.b == 0 } })
    }

    @Test func triangleApexIsUp() {
        // y 下向きの座標(グラフと同じ)で描くと、頂点は上(y の小さい側)
        let ctx = makeBitmap()
        ctx.translateBy(x: 0, y: 64)
        ctx.scaleBy(x: 1, y: -1)
        GraphRenderer.drawPlotMark(code: 4, center: CGPoint(x: 32, y: 32), diameter: 40, dotColor: .red, lineWidth: 1,
                                   brushStyle: 0, brushColor: .white, brushHatch: 0, in: ctx)
        // ビットマップのメモリは上の行から並ぶ。頂点の近く(上)は細く、底辺の近く(下)は広い
        func width(_ row: Int) -> Int { (0..<64).filter { pixel(ctx, $0, row).a > 0 }.count }
        #expect(width(12) < width(42))
    }

    func barProject(code: Int) -> SMPProject {
        var p = SMPProject()
        p.setDataFile(DataFile(name: "bars.dat", lines: ["1 2", "2 5", "3 3", "= 4", "4 8", "5 6", "6 4"]))
        var g = Graph.makeDefault()
        var s = Series(name: "bars.dat")
        s.dotType = code
        s.dotColor = .red
        s.dotSize = 400
        s.barBase = code == 26 ? 0 : 1
        g.series = [s]
        p.graphs = [g]
        return p
    }

    @Test func barsAndSteps() throws {
        for code in [13, 26, 27, 28, 33, 34] {
            for style in [0, 1, 2] {
                var p = barProject(code: code)
                p.graphs[0].series[0].brushStyle = style
                p.graphs[0].series[0].brushHatch = 3
                let image = try #require(GraphExporter.cgImage(renderer: GraphRenderer(project: p), dpi: 72))
                #expect(countPixels(image, where: isReddish) > 0, "プロットの種類 \(code)")
            }
            // 対数の軸(barBase 0 は描けない)・1 点だけ・枠が軸のときも落ちない
            var p = barProject(code: code)
            p.graphs[0].axes[1].scaleType = .logNormal
            p.graphs[0].axes[1].from = 1
            p.graphs[0].axes[1].to = 10
            p.graphs[0].series[0].barBase = 0
            _ = GraphExporter.cgImage(renderer: GraphRenderer(project: p), dpi: 36)
            p.setDataFile(DataFile(name: "bars.dat", lines: ["3 3"]))
            p.graphs[0].frameType = .axes
            _ = GraphExporter.cgImage(renderer: GraphRenderer(project: p), dpi: 36)
        }
        // 縦棒は barBase から y まで: 塗りつぶした面積は 対角線(28)の印より大きい
        let bars = try #require(GraphExporter.cgImage(renderer: GraphRenderer(project: barProject(code: 13)), dpi: 72))
        let marks = try #require(GraphExporter.cgImage(renderer: GraphRenderer(project: barProject(code: 28)), dpi: 72))
        #expect(countPixels(bars, where: isReddish) > 4 * countPixels(marks, where: isReddish))
    }

    @Test func spansBetweenMidpoints() {
        let s = GraphRenderer.midpointSpans([0, 10, 30], fallback: 4)
        #expect(s.map(\.lo) == [-5, 5, 20] && s.map(\.hi) == [5, 20, 40])
        let one = GraphRenderer.midpointSpans([7], fallback: 4)
        #expect(one[0].lo == 5 && one[0].hi == 9)
    }
}
