import Foundation
import CoreGraphics

// プロットの種類(SMP のドット番号)の描き方。38〜52 の形は推定
extension GraphRenderer {
    /// 中の塗り方
    enum MarkFill: Equatable {
        case none
        case color(SMPColor)
        case hatch(SMPColor, Int)
    }

    /// 塗り方: fillsWithDotColor の値はドットの色(中白=lbStyle 2・ハッチ 0 は白、ハッチ 1〜6 はドットの色の斜線)、
    /// それ以外は中塗色(lbStyle 2 も塗りとして扱う)。lbStyle 1 は塗らない。
    static func markFill(code: Int, dotColor: SMPColor, brushStyle: Int, brushColor: SMPColor, brushHatch: Int) -> MarkFill {
        if PlotType.fillsWithDotColor(code) {
            switch brushStyle {
            case 1: return .none
            case 2: return brushHatch == 0 ? .color(.white) : .hatch(dotColor, brushHatch)
            default: return .color(dotColor)
            }
        }
        return brushStyle == 1 ? .none : .color(brushColor)
    }

    /// 印の形。body は塗って縁を描く閉じた形、lines はペンで描くだけの線
    struct MarkGeometry {
        var body: CGPath?
        var lines: CGPath?
        /// body の左半分をドットの色で塗る(44〜48)
        var halfFilled = false
    }

    /// 中心 p・半径 r(= プロットの大きさ / 2)の印。y は下向き。何も描かない値は nil
    static func markGeometry(code: Int, center p: CGPoint, radius r: CGFloat) -> MarkGeometry? {
        func pt(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }
        func polygon(_ pts: [CGPoint], closed: Bool = true) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: pts)
            if closed { path.closeSubpath() }
            return path
        }
        func segments(_ pairs: [(CGPoint, CGPoint)]) -> CGPath {
            let path = CGMutablePath()
            for (a, b) in pairs { path.move(to: a); path.addLine(to: b) }
            return path
        }
        func circle() -> CGPath { CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r), transform: nil) }
        func square() -> CGPath { CGPath(rect: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r), transform: nil) }
        func triangleUp() -> CGPath { polygon([pt(0, -1.24 * r), pt(1.08 * r, 0.62 * r), pt(-1.08 * r, 0.62 * r)]) }
        func triangleDown() -> CGPath { polygon([pt(0, 1.24 * r), pt(1.08 * r, -0.62 * r), pt(-1.08 * r, -0.62 * r)]) }
        func diamond() -> CGPath {
            let c = 10 * r / 7
            return polygon([pt(-c, 0), pt(0, -c), pt(c, 0), pt(0, c)])
        }
        /// 正多角形(startDegrees は 1 つ目の頂点の向き。-90 が真上)
        func regular(_ n: Int, radius R: CGFloat, startDegrees: Double) -> CGPath {
            polygon((0..<n).map { k in
                let a = (startDegrees + 360 * Double(k) / Double(n)) * Double.pi / 180
                return pt(R * CGFloat(Foundation.cos(a)), R * CGFloat(Foundation.sin(a)))
            })
        }
        func star() -> CGPath {
            let outer = 1.3 * r, inner = outer * 0.382
            return polygon((0..<10).map { k in
                let a = (-90 + 36 * Double(k)) * Double.pi / 180
                let R = k % 2 == 0 ? outer : inner
                return pt(R * CGFloat(Foundation.cos(a)), R * CGFloat(Foundation.sin(a)))
            })
        }
        let d = r / CGFloat(2.0.squareRoot())
        let slash = (pt(-r, r), pt(r, -r))
        let backslash = (pt(-r, -r), pt(r, r))

        switch code {
        case 1, 2, 14, 19: return MarkGeometry(body: circle())
        case 3, 4, 15, 20: return MarkGeometry(body: triangleUp())
        case 5, 6, 16, 21, 27: return MarkGeometry(body: square())
        case 7, 8, 17, 22: return MarkGeometry(body: triangleDown())
        case 9, 10, 18, 23: return MarkGeometry(body: diamond())
        case 11: return MarkGeometry(lines: segments([(pt(0, -r), pt(0, r)), (pt(-r, 0), pt(r, 0))]))
        case 12: return MarkGeometry(lines: segments([backslash, slash]))
        case 24, 28: return MarkGeometry(lines: segments([slash]))
        case 25: return MarkGeometry(lines: segments([backslash]))
        case 13: return MarkGeometry(body: CGPath(rect: CGRect(x: p.x - r / 3, y: p.y - r, width: 2 * r / 3, height: 2 * r), transform: nil))
        case 26: return MarkGeometry(body: CGPath(rect: CGRect(x: p.x - r, y: p.y - r / 3, width: 2 * r, height: 2 * r / 3), transform: nil))
        case 33: return MarkGeometry(lines: polygon([pt(-2 * r, -r), pt(0, -r), pt(0, r), pt(2 * r, r)], closed: false))
        case 34: return MarkGeometry(lines: polygon([pt(-r, 2 * r), pt(-r, 0), pt(r, 0), pt(r, -2 * r)], closed: false))
        case 38: return MarkGeometry(body: regular(6, radius: 1.1 * r, startDegrees: -90))
        case 39: return MarkGeometry(body: regular(5, radius: 1.15 * r, startDegrees: -90))
        case 40: return MarkGeometry(body: regular(5, radius: 1.15 * r, startDegrees: 90))
        case 41: return MarkGeometry(body: star())
        case 42: return MarkGeometry(body: circle(), lines: segments([(pt(0, -r), pt(0, r)), (pt(-r, 0), pt(r, 0))]))
        case 43: return MarkGeometry(body: circle(), lines: segments([(pt(-d, -d), pt(d, d)), (pt(-d, d), pt(d, -d))]))
        case 44: return MarkGeometry(body: circle(), halfFilled: true)
        case 45: return MarkGeometry(body: triangleUp(), halfFilled: true)
        case 46: return MarkGeometry(body: square(), halfFilled: true)
        case 47: return MarkGeometry(body: triangleDown(), halfFilled: true)
        case 48: return MarkGeometry(body: diamond(), halfFilled: true)
        case 49: return MarkGeometry(body: circle(), lines: segments([(pt(0, -r), pt(0, r))]))
        case 50: return MarkGeometry(body: circle(), lines: segments([(pt(-r, 0), pt(r, 0))]))
        case 51: return MarkGeometry(body: circle(), lines: segments([(pt(-d, d), pt(d, -d))]))
        case 52: return MarkGeometry(body: circle(), lines: segments([(pt(-d, -d), pt(d, d))]))
        default: return nil
        }
    }

    static func cgColor(_ c: SMPColor) -> CGColor {
        CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }

    /// 1 デバイスピクセルの太さ(GDI の太さ 0 のペン)
    static func hairline(_ ctx: CGContext) -> CGFloat {
        let s = ctx.convertToUserSpace(CGSize(width: 1, height: 1))
        let w = Swift.abs(s.width)
        return w.isFinite && w > 0 ? w : 1
    }

    /// 印を 1 つ描く(ダイアログの見本・凡例にも使う)。単位は ctx のもの、diameter はプロットの大きさ。
    /// 形は y が下向きの座標で決めてあるので、y が上向きの ctx なら先に反転しておく。
    /// 縁はドットの色・lineWidth の太さ(0 以下なら最も細い線)。中の塗りは PlotType.fillsWithDotColor による。
    public static func drawPlotMark(code: Int, center: CGPoint, diameter: CGFloat, dotColor: SMPColor, lineWidth: CGFloat,
                                    brushStyle: Int, brushColor: SMPColor, brushHatch: Int, in ctx: CGContext) {
        guard diameter.isFinite, center.x.isFinite, center.y.isFinite,
              let geo = markGeometry(code: code, center: center, radius: Swift.max(diameter, 0) / 2) else { return }
        let fill = markFill(code: code, dotColor: dotColor, brushStyle: brushStyle, brushColor: brushColor, brushHatch: brushHatch)
        let lw = lineWidth.isFinite && lineWidth > 0 ? lineWidth : hairline(ctx)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineDash(phase: 0, lengths: [])
        if let body = geo.body {
            fillShape(body, fill, size: Swift.max(diameter, lw), lineWidth: lw, ctx: ctx)
            if geo.halfFilled {
                let b = body.boundingBox
                ctx.saveGState()
                ctx.clip(to: CGRect(x: b.minX - b.width, y: b.minY - b.height, width: center.x - (b.minX - b.width), height: 3 * b.height))
                ctx.setFillColor(cgColor(dotColor))
                ctx.addPath(body)
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
        // GDI の CreatePen の線は端も角も丸い
        ctx.setLineWidth(lw)
        ctx.setStrokeColor(cgColor(dotColor))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.beginPath()
        if let body = geo.body { ctx.addPath(body) }
        if let lines = geo.lines { ctx.addPath(lines) }
        ctx.strokePath()
    }

    /// 形の中を塗る(size は斜線の間隔を決める大きさ)
    static func fillShape(_ path: CGPath, _ fill: MarkFill, size: CGFloat, lineWidth: CGFloat, ctx: CGContext) {
        switch fill {
        case .none:
            break
        case .color(let c):
            ctx.setFillColor(cgColor(c))
            ctx.addPath(path)
            ctx.fillPath()
        case .hatch(let c, let h):
            let spacing = Swift.max(size / 5, lineWidth * 2)
            let width = Swift.max(Swift.min(lineWidth * 0.6, spacing / 3), hairline(ctx))
            strokeHatch(path, hatch: h, color: cgColor(c), spacing: spacing, lineWidth: width, ctx: ctx)
        }
    }

    /// Windows の HS_ のハッチ: 1 縦 2 "\" 3 "/" 4 縦横 5 斜めの格子、それ以外(6 など)は横。背景は塗らない
    static func strokeHatch(_ path: CGPath, hatch: Int, color: CGColor, spacing: CGFloat, lineWidth: CGFloat, ctx: CGContext) {
        let b = path.boundingBox
        guard !b.isNull, b.width.isFinite, b.height.isFinite, spacing > 0 else { return }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.butt)
        let span = b.width + b.height + spacing
        let n = Swift.min(Int(span / spacing) + 1, 2000)
        ctx.beginPath()
        func vertical() {
            for k in -n...n {
                let x = b.midX + CGFloat(k) * spacing
                ctx.move(to: CGPoint(x: x, y: b.minY)); ctx.addLine(to: CGPoint(x: x, y: b.maxY))
            }
        }
        func horizontal() {
            for k in -n...n {
                let y = b.midY + CGFloat(k) * spacing
                ctx.move(to: CGPoint(x: b.minX, y: y)); ctx.addLine(to: CGPoint(x: b.maxX, y: y))
            }
        }
        // y は下向き: "\" は (+1, +1) の向き、"/" は (+1, -1) の向き
        func diagonal(_ dy: CGFloat) {
            let step = spacing * CGFloat(2.0.squareRoot())
            for k in -n...n {
                let x = b.midX + CGFloat(k) * step
                ctx.move(to: CGPoint(x: x - span, y: b.midY - dy * span))
                ctx.addLine(to: CGPoint(x: x + span, y: b.midY + dy * span))
            }
        }
        switch hatch {
        case 1: vertical()
        case 2: diagonal(1)
        case 3: diagonal(-1)
        case 4: vertical(); horizontal()
        case 5: diagonal(1); diagonal(-1)
        default: horizontal()
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - 系列の印

    func drawSeriesMarkers(_ s: Series, _ d: SeriesPlotData, _ fr: Frame, _ ctx: CGContext) {
        let code = s.dotType
        guard PlotType.drawsMark(code) else { return }
        let h = fr.graph.horizontalAxisIndex(for: s), v = fr.graph.verticalAxisIndex(for: s)
        switch code {
        case 13, 26, 27, 33, 34:
            ctx.saveGState()
            if fr.graph.frameType != .axes || options.clipToFrame { ctx.clip(to: fr.rect.insetBy(dx: -1, dy: -1)) }
            if code == 33 || code == 34 { drawSteps(s, d, fr, h, v, ctx) } else { drawBars(s, d, fr, h, v, ctx) }
            ctx.restoreGState()
        default:
            let tol = 1.0
            for i in 0..<Swift.min(d.x.count, d.y.count) {
                guard let p = fr.point(d.x[i], d.y[i], h: h, v: v) else { continue }
                if p.x < -tol || p.x > fr.width + tol || p.y < -tol || p.y > fr.height + tol { continue }
                GraphRenderer.drawPlotMark(code: code, center: p, diameter: CGFloat(s.dotSize), dotColor: s.dotColor,
                                           lineWidth: CGFloat(s.lineWidth), brushStyle: s.brushStyle, brushColor: s.brushColor,
                                           brushHatch: s.brushHatch, in: ctx)
            }
        }
    }

    /// 続いている点のまとまり(欠損・マスク・描けない値で切る)。グラフの中の座標
    static func pointRuns(_ d: SeriesPlotData, _ fr: Frame, _ h: Int, _ v: Int) -> [[CGPoint]] {
        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []
        for i in 0..<Swift.min(d.x.count, d.y.count) {
            if let p = fr.point(d.x[i], d.y[i], h: h, v: v), p.x.isFinite, p.y.isFinite,
               Swift.abs(p.x) < 1e7, Swift.abs(p.y) < 1e7 {
                current.append(p)
            } else if !current.isEmpty {
                runs.append(current); current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// 隣の点との中点で区切った範囲(両端は隣との間隔の半分だけ外へ。1 点だけなら fallback の幅)
    static func midpointSpans(_ c: [CGFloat], fallback: CGFloat) -> [(lo: CGFloat, hi: CGFloat)] {
        let n = c.count
        guard n > 1 else { return c.map { (lo: $0 - fallback / 2, hi: $0 + fallback / 2) } }
        return (0..<n).map { i in
            let lo = i > 0 ? (c[i - 1] + c[i]) / 2 : c[0] - (c[1] - c[0]) / 2
            let hi = i < n - 1 ? (c[i] + c[i + 1]) / 2 : c[n - 1] + (c[n - 1] - c[n - 2]) / 2
            return (lo: lo, hi: hi)
        }
    }

    /// 棒の基準(barBase)の位置。描けない値なら枠の端。極端な値は枠の近くに寄せる
    static func barBase(_ value: Double, along length: Double, convert: (Double) -> Double?, fallback: Double) -> CGFloat {
        let raw = convert(value) ?? fallback
        let limit = Swift.max(length, 1) * 10
        return CGFloat(Swift.min(Swift.max(raw.isFinite ? raw : fallback, -limit), length + limit))
    }

    /// 13 縦棒・26 横棒・27 矩形(すき間のない縦棒)
    func drawBars(_ s: Series, _ d: SeriesPlotData, _ fr: Frame, _ h: Int, _ v: Int, _ ctx: CGContext) {
        let code = s.dotType
        let size = CGFloat(Swift.max(s.dotSize, 0))
        var rects: [CGRect] = []
        let runs = GraphRenderer.pointRuns(d, fr, h, v)
        switch code {
        case 26:
            let base = GraphRenderer.barBase(s.barBase, along: fr.width, convert: { fr.px($0, axis: h) }, fallback: 0)
            for p in runs.joined() {
                rects.append(CGRect(x: Swift.min(p.x, base), y: p.y - size / 2, width: Swift.abs(p.x - base), height: size))
            }
        case 27:
            let base = GraphRenderer.barBase(s.barBase, along: fr.height, convert: { fr.py($0, axis: v) }, fallback: fr.height)
            for run in runs {
                for (p, span) in zip(run, GraphRenderer.midpointSpans(run.map(\.x), fallback: size)) {
                    rects.append(CGRect(x: Swift.min(span.lo, span.hi), y: Swift.min(p.y, base),
                                        width: Swift.abs(span.hi - span.lo), height: Swift.abs(p.y - base)))
                }
            }
        default:
            let base = GraphRenderer.barBase(s.barBase, along: fr.height, convert: { fr.py($0, axis: v) }, fallback: fr.height)
            for p in runs.joined() {
                rects.append(CGRect(x: p.x - size / 2, y: Swift.min(p.y, base), width: size, height: Swift.abs(p.y - base)))
            }
        }
        guard !rects.isEmpty else { return }
        let fill = GraphRenderer.markFill(code: code, dotColor: s.dotColor, brushStyle: s.brushStyle,
                                          brushColor: s.brushColor, brushHatch: s.brushHatch)
        let lw = s.lineWidth > 0 ? CGFloat(s.lineWidth) : GraphRenderer.hairline(ctx)
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [])
        for r in rects {
            GraphRenderer.fillShape(CGPath(rect: r, transform: nil), fill, size: Swift.max(size, lw), lineWidth: lw, ctx: ctx)
        }
        ctx.setStrokeColor(cg(s.dotColor))
        ctx.setLineWidth(lw)
        ctx.setLineJoin(.miter)
        ctx.setLineCap(.square)
        ctx.beginPath()
        for r in rects { ctx.addRect(r) }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// 34 横階段(各点の y の横線を x の中点で区切り、中点で縦につなぐ)・33 縦階段(その縦横を入れ替えたもの)
    func drawSteps(_ s: Series, _ d: SeriesPlotData, _ fr: Frame, _ h: Int, _ v: Int, _ ctx: CGContext) {
        let size = CGFloat(Swift.max(s.dotSize, 0))
        let path = CGMutablePath()
        for run in GraphRenderer.pointRuns(d, fr, h, v) {
            if s.dotType == 34 {
                let spans = GraphRenderer.midpointSpans(run.map(\.x), fallback: size)
                for (i, (p, span)) in zip(run, spans).enumerated() {
                    let a = CGPoint(x: span.lo, y: p.y), b = CGPoint(x: span.hi, y: p.y)
                    if i == 0 { path.move(to: a) } else { path.addLine(to: a) }
                    path.addLine(to: b)
                }
            } else {
                let spans = GraphRenderer.midpointSpans(run.map(\.y), fallback: size)
                for (i, (p, span)) in zip(run, spans).enumerated() {
                    let a = CGPoint(x: p.x, y: span.lo), b = CGPoint(x: p.x, y: span.hi)
                    if i == 0 { path.move(to: a) } else { path.addLine(to: a) }
                    path.addLine(to: b)
                }
            }
        }
        guard !path.isEmpty else { return }
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(cg(s.dotColor))
        ctx.setLineWidth(s.lineWidth > 0 ? CGFloat(s.lineWidth) : GraphRenderer.hairline(ctx))
        ctx.setLineJoin(.miter)
        ctx.setLineCap(.butt)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
