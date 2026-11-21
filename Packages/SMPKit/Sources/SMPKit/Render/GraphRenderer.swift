import Foundation
import CoreGraphics
import CoreText

public struct RenderOptions: Sendable {
    /// 枠の外にはみ出す点もそのまま描くか
    public var clipToFrame: Bool = false
    public var superscriptScale: Double = 0.7
    public var superscriptRise: Double = 0.35
    public var subscriptDrop: Double = 0.15
    public var fileName: String = "Untitled.SMP"
    public var fileDate: Date = Date()
    /// 描かないグラフ(個別表示用)
    public var visibleGraphs: Set<Int>?
    /// 図(種類 10)のファイル名から画像を返す。nil を返したら灰色の枠と × を描く
    public var pictureProvider: (@Sendable (String) -> CGImage?)?

    public init() {}
}

/// 描画の基本: CGContext は 0.01 mm 単位・y 下向き(用紙の左上が原点)にしてから渡す
public final class GraphRenderer {
    public let project: SMPProject
    public var options: RenderOptions
    /// グラフごとの系列の計算結果(呼び出し側で持っておけば再計算しない)
    public private(set) var plotData: [[SeriesPlotData]]

    public init(project: SMPProject, options: RenderOptions = RenderOptions(), plotData: [[SeriesPlotData]]? = nil) {
        self.project = project
        self.options = options
        self.plotData = plotData ?? project.graphs.map { SeriesEvaluator.evaluate(graph: $0, project: project) }
    }

    public func draw(in ctx: CGContext) {
        for (i, g) in project.graphs.enumerated() {
            if let v = options.visibleGraphs, !v.contains(i) { continue }
            drawGraph(index: i, graph: g, in: ctx)
        }
    }

    // MARK: - 座標

    /// グラフの中の座標系(枠の左上が原点、拡大率をかけたもの)
    public struct Frame {
        public let graph: Graph
        public let width: Double
        public let height: Double
        public let scales: [AxisScale]

        public init(_ g: Graph) {
            graph = g
            width = Double(g.width)
            height = Double(g.height)
            scales = (0..<4).map { AxisScale(g.effectiveAxis($0)) }
        }

        public func px(_ v: Double, axis: Int) -> Double? {
            guard let f = scales[axis].fraction(v) else { return nil }
            return f * width
        }

        public func py(_ v: Double, axis: Int) -> Double? {
            guard let f = scales[axis].fraction(v) else { return nil }
            return (1 - f) * height
        }

        public func point(_ x: Double, _ y: Double, h: Int, v: Int) -> CGPoint? {
            guard let a = px(x, axis: h), let b = py(y, axis: v) else { return nil }
            return CGPoint(x: a, y: b)
        }

        public var rect: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
    }

    /// 用紙の座標 → グラフの中の座標
    public static func graphTransform(_ g: Graph) -> CGAffineTransform {
        CGAffineTransform(translationX: CGFloat(g.left), y: CGFloat(g.top)).scaledBy(x: g.zoomFactor, y: g.zoomFactor)
    }

    public func environment(for graphIndex: Int) -> TextEnvironment {
        var env = TextEnvironment()
        let g = project.graphs[graphIndex]
        env.seriesNames = g.series.map(\.displayName)
        env.seriesStyles = g.series
        env.fileName = options.fileName
        env.fileDate = options.fileDate
        env.superscriptScale = options.superscriptScale
        env.superscriptRise = options.superscriptRise
        env.subscriptDrop = options.subscriptDrop
        let project = self.project
        env.dataCell = { file, row, col in
            let si = file == 0 ? 0 : file - 1
            guard si >= 0, si < g.series.count, let f = project.dataFile(named: g.series[si].name) else { return nil }
            let r = row - 1
            guard r >= 0, r < f.lines.count else { return nil }
            if col == 0 { return f.lines[r] }
            let parts = f.lines[r].split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," }).map(String.init)
            return col - 1 < parts.count ? parts[col - 1] : nil
        }
        return env
    }

    // MARK: - グラフ 1 枚

    public func drawGraph(index: Int, graph g: Graph, in ctx: CGContext) {
        let fr = Frame(g)
        let data = index < plotData.count ? plotData[index] : []
        ctx.saveGState()
        ctx.concatenate(GraphRenderer.graphTransform(g))

        // 背景
        if g.background != .white {
            ctx.setFillColor(cg(g.background))
            ctx.fill(fr.rect)
        }
        if g.frameType == .grid { drawGrid(fr, ctx) }

        // データ
        ctx.saveGState()
        if g.frameType != .axes || options.clipToFrame {
            ctx.clip(to: fr.rect.insetBy(dx: -1, dy: -1))
        }
        for (i, s) in g.series.enumerated() where s.visible && i < data.count {
            drawSeriesLines(s, data[i], fr, ctx)
        }
        ctx.restoreGState()
        ctx.saveGState()
        if options.clipToFrame { ctx.clip(to: fr.rect) }
        for (i, s) in g.series.enumerated() where s.visible && i < data.count {
            drawSeriesMarkers(s, data[i], fr, ctx)
        }
        ctx.restoreGState()

        drawFrameAndTicks(fr, ctx)
        drawLabels(fr, ctx, env: environment(for: index))

        for item in g.objects {
            drawObject(item.object, fr, ctx, env: environment(for: index), absolute: false)
        }
        ctx.restoreGState()
    }

    // MARK: - 線の種類

    /// 線種の点線の長さ(線種の値・ピッチ・太さは 0.01 mm。実線・線なしは空)
    public static func dash(_ type: Int, pitch: Int, width: Int) -> [CGFloat] {
        let p = CGFloat(Swift.max(pitch, 20))
        let w = CGFloat(Swift.max(width, 5))
        switch type {
        case 2: return [p * 0.65, p * 0.35]
        case 3: return [w, Swift.max(p * 0.5 - w, w)]
        case 4: return [p * 0.5, p * 0.15, w, p * 0.15]
        case 5: return [p * 0.4, p * 0.12, w, p * 0.12, w, p * 0.12]
        default: return []
        }
    }

    func setLine(_ ctx: CGContext, type: Int, width: Int, pitch: Int, color: SMPColor) {
        ctx.setStrokeColor(cg(color))
        ctx.setLineWidth(CGFloat(Swift.max(width, 1)))
        let d = GraphRenderer.dash(type, pitch: pitch, width: width)
        if d.isEmpty { ctx.setLineDash(phase: 0, lengths: []) } else { ctx.setLineDash(phase: 0, lengths: d) }
        ctx.setLineCap(type == 3 ? .round : .butt)
        ctx.setLineJoin(.round)
    }

    func cg(_ c: SMPColor) -> CGColor {
        CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }

    // MARK: - 方眼

    func drawGrid(_ fr: Frame, _ ctx: CGContext) {
        let g = fr.graph
        for (axis, horizontal) in [(0, true), (1, false)] {
            let spec = g.effectiveAxis(axis)
            for t in fr.scales[axis].ticks() where t.fraction > 1e-6 && t.fraction < 1 - 1e-6 {
                let style = t.isMajor ? spec.major : spec.minor
                setLine(ctx, type: style.style, width: style.width, pitch: style.pitch, color: style.color)
                ctx.beginPath()
                if horizontal {
                    let x = t.fraction * fr.width
                    ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: fr.height))
                } else {
                    let y = (1 - t.fraction) * fr.height
                    ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: fr.width, y: y))
                }
                ctx.strokePath()
            }
        }
        ctx.setLineDash(phase: 0, lengths: [])
    }

    // MARK: - 系列

    func drawSeriesLines(_ s: Series, _ d: SeriesPlotData, _ fr: Frame, _ ctx: CGContext) {
        let h = fr.graph.horizontalAxisIndex(for: s), v = fr.graph.verticalAxisIndex(for: s)

        // 曲線(最小二乗・スプライン)
        if s.kind != .function, s.curveVisible, !d.curve.isEmpty, s.curveLineType != .none {
            setLine(ctx, type: s.curveLineType.rawValue, width: s.curveWidth, pitch: s.curvePitch, color: s.curveColor)
            strokePolyline(d.curve.map { ($0.x, $0.y) }, fr, h, v, ctx)
        }
        // データ点を結ぶ線
        if s.lineType != .none && s.lineType != .fill {
            setLine(ctx, type: s.lineType.rawValue, width: s.lineWidth, pitch: s.pitch, color: s.lineColor)
            strokePolyline(Array(zip(d.x, d.y)), fr, h, v, ctx)
        } else if s.lineType == .fill {
            fillArea(s, d, fr, h, v, ctx)
        }
        // エラーバー
        let cap = CGFloat(Swift.max(s.dotSize, 100)) * 0.35
        if d.errorY != nil || d.errorX != nil {
            setLine(ctx, type: 1, width: s.lineWidth, pitch: s.pitch, color: s.dotColor)
        }
        if let ey = d.errorY {
            for i in 0..<Swift.min(ey.count, d.x.count) {
                guard let x = fr.px(d.x[i], axis: h), let y0 = fr.py(ey[i].lo, axis: v), let y1 = fr.py(ey[i].hi, axis: v) else { continue }
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: y0)); ctx.addLine(to: CGPoint(x: x, y: y1))
                ctx.move(to: CGPoint(x: x - cap, y: y0)); ctx.addLine(to: CGPoint(x: x + cap, y: y0))
                ctx.move(to: CGPoint(x: x - cap, y: y1)); ctx.addLine(to: CGPoint(x: x + cap, y: y1))
                ctx.strokePath()
            }
        }
        if let ex = d.errorX {
            for i in 0..<Swift.min(ex.count, d.y.count) {
                guard let y = fr.py(d.y[i], axis: v), let x0 = fr.px(ex[i].lo, axis: h), let x1 = fr.px(ex[i].hi, axis: h) else { continue }
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1, y: y))
                ctx.move(to: CGPoint(x: x0, y: y - cap)); ctx.addLine(to: CGPoint(x: x0, y: y + cap))
                ctx.move(to: CGPoint(x: x1, y: y - cap)); ctx.addLine(to: CGPoint(x: x1, y: y + cap))
                ctx.strokePath()
            }
        }
    }

    func strokePolyline(_ pts: [(Double, Double)], _ fr: Frame, _ h: Int, _ v: Int, _ ctx: CGContext) {
        ctx.beginPath()
        var open = false
        var count = 0
        for (x, y) in pts {
            guard let p = fr.point(x, y, h: h, v: v), p.x.isFinite, p.y.isFinite,
                  Swift.abs(p.x) < 1e7, Swift.abs(p.y) < 1e7 else { open = false; continue }
            if open { ctx.addLine(to: p) } else { ctx.move(to: p); open = true }
            count += 1
            if count % 4000 == 0 { ctx.strokePath(); ctx.beginPath(); ctx.move(to: p) }
        }
        ctx.strokePath()
    }

    func fillArea(_ s: Series, _ d: SeriesPlotData, _ fr: Frame, _ h: Int, _ v: Int, _ ctx: CGContext) {
        let baseY = fr.py(s.barBase, axis: v) ?? fr.height
        var pts: [CGPoint] = []
        for (x, y) in zip(d.x, d.y) {
            if let p = fr.point(x, y, h: h, v: v) { pts.append(p) }
        }
        guard let first = pts.first, let last = pts.last else { return }
        ctx.beginPath()
        ctx.move(to: CGPoint(x: first.x, y: baseY))
        for p in pts { ctx.addLine(to: p) }
        ctx.addLine(to: CGPoint(x: last.x, y: baseY))
        ctx.closePath()
        ctx.setFillColor(cg(s.lineColor))
        ctx.fillPath()
    }

    // 印(プロットの種類)の描き方は PlotMarks.swift

    // MARK: - 枠と目盛

    /// 枠の各辺と目盛り。軸の種類に応じて描く辺が変わる
    func drawFrameAndTicks(_ fr: Frame, _ ctx: CGContext) {
        let g = fr.graph
        let w = fr.width, h = fr.height
        setLine(ctx, type: 1, width: g.frameWidth, pitch: g.framePitch, color: g.frameColor)
        ctx.setLineCap(.square)
        switch g.frameType {
        case .box, .grid:
            ctx.stroke(fr.rect)
        case .halfBox:
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: 0)); ctx.addLine(to: CGPoint(x: 0, y: h)); ctx.addLine(to: CGPoint(x: w, y: h))
            ctx.strokePath()
        case .axes:
            let o = axesOrigin(fr)
            ctx.beginPath()
            if g.axes[0].drawAxis { ctx.move(to: CGPoint(x: 0, y: o.y)); ctx.addLine(to: CGPoint(x: w, y: o.y)) }
            if g.axes[1].drawAxis { ctx.move(to: CGPoint(x: o.x, y: 0)); ctx.addLine(to: CGPoint(x: o.x, y: h)) }
            ctx.strokePath()
        }
        ctx.setLineCap(.butt)
        if g.frameType == .grid { return }

        // 目盛り線: (軸番号, 辺の位置, 内向きの向き)
        var edges: [(Int, CGFloat, CGFloat, Bool)] = []  // axis, position, inward sign, horizontal
        switch g.frameType {
        case .box:
            edges = [(0, h, -1, true), (2, 0, 1, true), (1, 0, 1, false), (3, w, -1, false)]
        case .halfBox:
            edges = [(0, h, -1, true), (1, 0, 1, false)]
        case .axes:
            let o = axesOrigin(fr)
            edges = [(0, o.y, -1, true), (1, o.x, 1, false)]
        case .grid:
            break
        }
        for (axis, pos, inward, horizontal) in edges {
            let spec = g.effectiveAxis(axis)
            if !spec.drawAxis { continue }
            for t in fr.scales[axis].ticks() {
                let st = t.isMajor ? spec.major : spec.minor
                guard st.inside || st.outside, st.length > 0 else { continue }
                setLine(ctx, type: 1, width: st.width, pitch: st.pitch, color: st.color)
                let len = CGFloat(st.length)
                let a = st.outside ? -len * inward : 0
                let b = st.inside ? len * inward : 0
                ctx.beginPath()
                if horizontal {
                    let x = CGFloat(t.fraction * w)
                    ctx.move(to: CGPoint(x: x, y: pos + a)); ctx.addLine(to: CGPoint(x: x, y: pos + b))
                } else {
                    let y = CGFloat((1 - t.fraction) * h)
                    ctx.move(to: CGPoint(x: pos + a, y: y)); ctx.addLine(to: CGPoint(x: pos + b, y: y))
                }
                ctx.strokePath()
            }
        }
    }

    func axesOrigin(_ fr: Frame) -> CGPoint {
        let x = fr.px(0, axis: 0).flatMap { $0 >= 0 && $0 <= fr.width ? $0 : nil } ?? 0
        let y = fr.py(0, axis: 1).flatMap { $0 >= 0 && $0 <= fr.height ? $0 : nil } ?? fr.height
        return CGPoint(x: x, y: y)
    }

    // MARK: - 目盛り数字

    public struct LabelBox {
        public var rect: CGRect   // グラフの中の座標(y 下向き)
        public var axis: Int
    }

    func drawLabels(_ fr: Frame, _ ctx: CGContext, env: TextEnvironment) {
        _ = layoutLabels(fr, env: env, draw: ctx)
    }

    /// 目盛り数字を並べる(ctx があれば描く)。返り値は数字の外枠
    @discardableResult
    public func layoutLabels(_ fr: Frame, env: TextEnvironment, draw ctx: CGContext?) -> [LabelBox] {
        let g = fr.graph
        var boxes: [LabelBox] = []
        var sides: [(axis: Int, side: Int)] = []  // side 0:下 1:左 2:上 3:右
        switch g.frameType {
        case .box, .grid: sides = [(0, 0), (1, 1), (2, 2), (3, 3)]
        case .halfBox, .axes: sides = [(0, 0), (1, 1)]
        }
        let origin = g.frameType == .axes ? axesOrigin(fr) : CGPoint(x: 0, y: fr.height)
        for (axis, side) in sides {
            let spec = g.effectiveAxis(axis)
            guard spec.drawLabels else { continue }
            let jp = LogFont.japaneseDefault(points: spec.font.pointSize)
            let gap = 100.0 + (spec.major.outside ? Double(spec.major.length) : 0)
            for t in fr.scales[axis].ticks() where t.isMajor {
                guard var label = t.label else { continue }
                if g.frameType == .axes, g.zeroCommon, t.value == 0 {
                    if axis == 1 { continue }   // 0 は 1 つだけ(X 側で原点の左下に描く)
                    label = "0"
                }
                let lay = TextLayoutEngine.layout(label, latin: spec.font, japanese: jp, color: spec.labelColor, environment: env)
                let bw = lay.bounds.width, bh = lay.bounds.height
                var x = 0.0, y = 0.0  // 文字の左下(y 下向きの座標)
                switch side {
                case 0:
                    let cx = t.fraction * fr.width
                    x = cx - bw / 2
                    if g.frameType == .axes, g.zeroCommon, t.value == 0 { x = cx - bw - 100 }
                    y = Double(origin.y) + gap + bh
                case 1:
                    let cy = (1 - t.fraction) * fr.height
                    x = (g.frameType == .axes ? Double(origin.x) : 0) - gap - bw
                    y = cy + bh / 2
                case 2:
                    x = t.fraction * fr.width - bw / 2
                    y = -gap
                default:
                    x = fr.width + gap
                    y = (1 - t.fraction) * fr.height + bh / 2
                }
                x += Double(spec.labelShiftX)
                y += Double(spec.labelShiftY)
                // bounds の原点からのずれを足す
                let refX = x - lay.bounds.minX
                let refY = y + lay.bounds.minY
                if let ctx { drawLayout(lay, at: CGPoint(x: refX, y: refY), angle: 0, ctx: ctx) }
                boxes.append(LabelBox(rect: CGRect(x: x, y: y - bh, width: bw, height: bh), axis: axis))
            }
            // ゲタ(×10^n)
            if spec.drawGetta, spec.gettaOrder != 1, spec.gettaOrder != 0, spec.scaleType == .linear {
                let e = Foundation.log10(Swift.abs(spec.gettaOrder))
                let text = Swift.abs(e - e.rounded()) < 1e-9 ? "%G%Q180%A10^\(Int(e.rounded()))@" : "%G%Q180%A\(Fitting.format(spec.gettaOrder))"
                let lay = TextLayoutEngine.layout(text, latin: spec.font, japanese: jp, color: spec.labelColor, environment: env)
                var p = CGPoint.zero
                switch side {
                case 0: p = CGPoint(x: fr.width - lay.bounds.width, y: Double(origin.y) + 100 + lay.bounds.height * 2.2)
                case 1: p = CGPoint(x: 0, y: -150)
                case 2: p = CGPoint(x: fr.width - lay.bounds.width, y: -100 - lay.bounds.height * 1.2)
                default: p = CGPoint(x: fr.width - lay.bounds.width, y: -150)
                }
                if let ctx { drawLayout(lay, at: p, angle: 0, ctx: ctx) }
            }
        }
        return boxes
    }

    // MARK: - 文字の描画

    /// p は文字の左下(1 行目の左下)の位置(y 下向きの座標)。angle は反時計回りの度
    public func drawLayout(_ lay: TextLayout, at p: CGPoint, angle: Double, ctx: CGContext, opaque: Bool = false) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        if angle != 0 { ctx.rotate(by: CGFloat(-angle * Double.pi / 180)) }
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        if opaque {
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(lay.bounds.insetBy(dx: -20, dy: -10))
        }
        for r in lay.runs {
            switch r.content {
            case .glyphs(let line):
                ctx.setFillColor(cg(r.color))
                ctx.textPosition = r.origin
                CTLineDraw(line, ctx)
            case .marker(let s, let curve, let length, let size):
                ctx.saveGState()
                let y = r.origin.y
                let x0 = r.origin.x, x1 = r.origin.x + length
                if curve {
                    if s.curveLineType != .none {
                        setLine(ctx, type: s.curveLineType.rawValue, width: s.curveWidth, pitch: s.curvePitch, color: s.curveColor)
                        ctx.beginPath(); ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1, y: y)); ctx.strokePath()
                    }
                } else {
                    if s.lineType != .none && s.lineType != .fill {
                        setLine(ctx, type: s.lineType.rawValue, width: s.lineWidth, pitch: s.pitch, color: s.lineColor)
                        ctx.beginPath(); ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1, y: y)); ctx.strokePath()
                    }
                    // ここは文字の座標(y 上向き)なので、印は y を下向きに戻して描く
                    ctx.translateBy(x: (x0 + x1) / 2, y: y)
                    ctx.scaleBy(x: 1, y: -1)
                    GraphRenderer.drawPlotMark(code: s.dotType, center: .zero, diameter: CGFloat(size), dotColor: s.dotColor,
                                               lineWidth: CGFloat(s.lineWidth), brushStyle: s.brushStyle,
                                               brushColor: s.brushColor, brushHatch: s.brushHatch, in: ctx)
                }
                ctx.restoreGState()
            }
            if r.underline || r.overline {
                ctx.setStrokeColor(cg(r.color))
                ctx.setLineWidth(CGFloat(Swift.max(r.emSize * 0.05, 8)))
                ctx.setLineDash(phase: 0, lengths: [])
                ctx.beginPath()
                if r.underline {
                    let y = r.origin.y - r.emSize * 0.12
                    ctx.move(to: CGPoint(x: r.origin.x, y: y)); ctx.addLine(to: CGPoint(x: r.origin.x + r.width, y: y))
                }
                if r.overline {
                    let y = r.origin.y + r.ascent + r.emSize * 0.02
                    ctx.move(to: CGPoint(x: r.origin.x, y: y)); ctx.addLine(to: CGPoint(x: r.origin.x + r.width, y: y))
                }
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }

    // MARK: - オブジェクト

    public func textLayout(_ t: TextObject, env: TextEnvironment) -> TextLayout {
        TextLayoutEngine.layout(t.text, latin: t.latinFont, japanese: t.japaneseFont, color: t.color, environment: env)
    }

    /// 矢印・枠の端の点(グラフの中の座標)
    public static func shapePoints(_ s: ShapeObject, _ fr: Frame) -> (CGPoint, CGPoint)? {
        func cx(_ v: Double) -> Double? {
            switch s.xReference {
            case 1: return fr.px(v, axis: 0)
            case 2: return fr.px(v, axis: 2)
            default: return v * 100
            }
        }
        func cy(_ v: Double) -> Double? {
            switch s.yReference {
            case 1: return fr.py(v, axis: 1)
            case 2: return fr.py(v, axis: 3)
            default: return v * 100
            }
        }
        guard let a = cx(s.x1), let b = cy(s.y1), let c = cx(s.x2), let d = cy(s.y2) else { return nil }
        return (CGPoint(x: a, y: b), CGPoint(x: c, y: d))
    }

    func drawObject(_ o: GraphObject, _ fr: Frame, _ ctx: CGContext, env: TextEnvironment, absolute: Bool) {
        switch o {
        case .text(let t):
            guard !t.text.isEmpty else { return }
            let lay = textLayout(t, env: env)
            var p = CGPoint(x: t.x, y: t.y)
            if t.absolutePosition {
                // 用紙の左上から: グラフの変換を打ち消す
                let inv = GraphRenderer.graphTransform(fr.graph).inverted()
                p = p.applying(inv)
            }
            // 原点(1 行目の左下)に bounds のずれは無い
            drawLayout(lay, at: p, angle: t.angle, ctx: ctx, opaque: t.backgroundMode == 2)
        case .shape(let s):
            guard let (a, b) = GraphRenderer.shapePoints(s, fr) else { return }
            drawShape(s, a, b, ctx)
        case .dot(let d):
            let p = CGPoint(x: d.x, y: d.y)
            ctx.saveGState()
            if d.length > 0 && d.style > 0 {
                setLine(ctx, type: d.style, width: d.width, pitch: d.pitch, color: d.color)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: p.x - CGFloat(d.length) / 2, y: p.y))
                ctx.addLine(to: CGPoint(x: p.x + CGFloat(d.length) / 2, y: p.y))
                ctx.strokePath()
            }
            GraphRenderer.drawPlotMark(code: d.dotType, center: p, diameter: CGFloat(d.size), dotColor: d.lineColor,
                                       lineWidth: CGFloat(d.width), brushStyle: d.brushStyle, brushColor: d.brushColor,
                                       brushHatch: d.brushHatch, in: ctx)
            ctx.restoreGState()
        case .picture(let pic):
            guard let rect = GraphRenderer.pictureRect(pic, fr) else { return }
            drawPicture(pic, in: rect, ctx)
        case .raw:
            break
        }
    }

    /// 図の範囲(グラフの中の座標。x1・y1 が左上、x2・y2 が右下)
    public static func pictureRect(_ pic: PictureObject, _ fr: Frame) -> CGRect? {
        guard let (a, b) = shapePoints(pic.shape, fr) else { return nil }
        let r = CGRect(x: Swift.min(a.x, b.x), y: Swift.min(a.y, b.y), width: Swift.abs(b.x - a.x), height: Swift.abs(b.y - a.y))
        return r.minX.isFinite && r.minY.isFinite && r.width.isFinite && r.height.isFinite ? r : nil
    }

    func drawPicture(_ pic: PictureObject, in rect: CGRect, _ ctx: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if let image = options.pictureProvider?(pic.path) {
            // y 下向きの座標なので、上下を返してから描く
            ctx.interpolationQuality = .high
            ctx.translateBy(x: rect.minX, y: rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
            return
        }
        // 画像が無いときも見えて選べるように、灰色の枠と × を描く
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(CGColor(srgbRed: 0.6, green: 0.6, blue: 0.6, alpha: 1))
        // 細い線(0.1 mm。画面で消えないよう 1 画素より細くはしない)
        ctx.setLineWidth(Swift.max(10, GraphRenderer.hairline(ctx)))
        ctx.beginPath()
        ctx.addRect(rect)
        ctx.move(to: CGPoint(x: rect.minX, y: rect.minY)); ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        ctx.move(to: CGPoint(x: rect.minX, y: rect.maxY)); ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        ctx.strokePath()
    }

    func drawShape(_ s: ShapeObject, _ a: CGPoint, _ b: CGPoint, _ ctx: CGContext) {
        ctx.saveGState()
        switch s.objectType {
        case 3:
            let rect = CGRect(x: Swift.min(a.x, b.x), y: Swift.min(a.y, b.y), width: Swift.abs(b.x - a.x), height: Swift.abs(b.y - a.y))
            let rx = CGFloat(Swift.max(s.size, 0)), ry = CGFloat(s.aspect > 0 ? s.aspect : s.size)
            let path = CGPath(roundedRect: rect, cornerWidth: Swift.min(rx, rect.width / 2), cornerHeight: Swift.min(ry, rect.height / 2), transform: nil)
            if s.length > 0 {
                // 影(枠の色で右下にずらす)と、白で塗った面
                let off = CGFloat(s.length)
                var t = CGAffineTransform(translationX: off, y: off)
                if let shadow = path.copy(using: &t) {
                    ctx.setFillColor(cg(s.color))
                    ctx.addPath(shadow)
                    ctx.fillPath()
                }
                ctx.setFillColor(cg(s.shadowColor))
                ctx.addPath(path); ctx.fillPath()
            }
            setLine(ctx, type: Swift.max(s.style, 1), width: s.width, pitch: s.pitch, color: s.color)
            ctx.addPath(path); ctx.strokePath()
        case 2:
            // エラーバー型: 両端に直交する短い線
            setLine(ctx, type: Swift.max(s.style, 1), width: s.width, pitch: s.pitch, color: s.color)
            let dx = b.x - a.x, dy = b.y - a.y
            let len = Swift.max(Foundation.sqrt(dx * dx + dy * dy), 1)
            let nx = -dy / len, ny = dx / len
            let half = CGFloat(Swift.max(s.length, 100)) / 2
            ctx.beginPath()
            ctx.move(to: a); ctx.addLine(to: b)
            ctx.move(to: CGPoint(x: a.x - nx * half, y: a.y - ny * half)); ctx.addLine(to: CGPoint(x: a.x + nx * half, y: a.y + ny * half))
            ctx.move(to: CGPoint(x: b.x - nx * half, y: b.y - ny * half)); ctx.addLine(to: CGPoint(x: b.x + nx * half, y: b.y + ny * half))
            ctx.strokePath()
        default:
            setLine(ctx, type: Swift.max(s.style, 1), width: s.width, pitch: s.pitch, color: s.color)
            let headLen = CGFloat(Swift.max(s.length, 50))
            let spread = CGFloat(Swift.max(s.headOpen, 1)) / 100
            let mode = s.headMode
            var start = a, end = b
            // 矢じりの分だけ線を短くする(塗りの矢じりと重ならないように)
            let dx = b.x - a.x, dy = b.y - a.y
            let len = Foundation.sqrt(dx * dx + dy * dy)
            if len > 0, s.objectType == 0 {
                let ux = dx / len, uy = dy / len
                let cut = headLen * CGFloat(Swift.max(s.headClose, 0)) / 100 * 0.9
                if mode == 1 || mode == 3 { end = CGPoint(x: b.x - ux * Swift.min(cut, len), y: b.y - uy * Swift.min(cut, len)) }
                if mode == 2 || mode == 3 { start = CGPoint(x: a.x + ux * Swift.min(cut, len), y: a.y + uy * Swift.min(cut, len)) }
            }
            ctx.beginPath(); ctx.move(to: start); ctx.addLine(to: end); ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            if mode == 1 || mode == 3 { arrowHead(from: a, to: b, length: headLen, spread: spread, close: s.headClose, filled: s.objectType == 0, color: s.color, width: s.width, ctx) }
            if mode == 2 || mode == 3 { arrowHead(from: b, to: a, length: headLen, spread: spread, close: s.headClose, filled: s.objectType == 0, color: s.color, width: s.width, ctx) }
        }
        ctx.restoreGState()
    }

    func arrowHead(from a: CGPoint, to b: CGPoint, length: CGFloat, spread: CGFloat, close: Int, filled: Bool,
                   color: SMPColor, width: Int, _ ctx: CGContext) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = Foundation.sqrt(dx * dx + dy * dy)
        guard len > 0 else { return }
        let ux = dx / len, uy = dy / len
        let nx = -uy, ny = ux
        let back = CGPoint(x: b.x - ux * length, y: b.y - uy * length)
        let half = length * spread
        let p1 = CGPoint(x: back.x + nx * half, y: back.y + ny * half)
        let p2 = CGPoint(x: back.x - nx * half, y: back.y - ny * half)
        let notch = CGFloat(Swift.min(Swift.max(close, 0), 100)) / 100
        let mid = CGPoint(x: b.x - ux * length * notch, y: b.y - uy * length * notch)
        ctx.setStrokeColor(cg(color))
        ctx.setFillColor(cg(color))
        ctx.setLineWidth(CGFloat(Swift.max(width, 5)))
        ctx.beginPath()
        if filled {
            ctx.move(to: b); ctx.addLine(to: p1); ctx.addLine(to: mid); ctx.addLine(to: p2); ctx.closePath()
            ctx.fillPath()
        } else {
            ctx.move(to: p1); ctx.addLine(to: b); ctx.addLine(to: p2)
            ctx.strokePath()
        }
    }

    // MARK: - 外枠(図面コピーの範囲・選択)

    /// グラフの中の座標でのオブジェクトの外枠
    public func objectBounds(_ o: GraphObject, graphIndex: Int) -> CGRect? {
        let g = project.graphs[graphIndex]
        let fr = Frame(g)
        switch o {
        case .text(let t):
            guard !t.text.isEmpty else { return nil }
            let lay = textLayout(t, env: environment(for: graphIndex))
            var p = CGPoint(x: t.x, y: t.y)
            if t.absolutePosition { p = p.applying(GraphRenderer.graphTransform(g).inverted()) }
            // 文字の座標(y 上向き)→ グラフの座標(y 下向き)。回転も考える
            let b = lay.bounds
            let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)]
            let ang = -t.angle * Double.pi / 180
            let ca = CGFloat(Foundation.cos(ang)), sa = CGFloat(Foundation.sin(ang))
            var r = CGRect.null
            for c in corners {
                let lx = c.x, ly = -c.y
                let x = p.x + lx * ca - ly * sa
                let y = p.y + lx * sa + ly * ca
                r = r.union(CGRect(x: x, y: y, width: 0, height: 0))
            }
            return r
        case .shape(let s):
            guard let (a, b) = GraphRenderer.shapePoints(s, fr) else { return nil }
            let pad = CGFloat(Swift.max(s.width, 40) + (s.objectType == 3 ? s.length : s.length / 2))
            return CGRect(x: Swift.min(a.x, b.x), y: Swift.min(a.y, b.y), width: Swift.abs(b.x - a.x), height: Swift.abs(b.y - a.y)).insetBy(dx: -pad, dy: -pad)
        case .dot(let d):
            let r = CGFloat(Swift.max(d.size, d.length) / 2 + d.width)
            return CGRect(x: CGFloat(d.x) - r, y: CGFloat(d.y) - r, width: 2 * r, height: 2 * r)
        case .picture(let pic):
            return GraphRenderer.pictureRect(pic, fr)
        case .raw:
            return nil
        }
    }

    /// グラフの描かれる範囲(用紙の座標)。枠・目盛り数字・文字などを含む
    public func contentBounds(graphIndex: Int) -> CGRect {
        let g = project.graphs[graphIndex]
        let fr = Frame(g)
        var r = fr.rect
        for b in layoutLabels(fr, env: environment(for: graphIndex), draw: nil) { r = r.union(b.rect) }
        for item in g.objects {
            if let b = objectBounds(item.object, graphIndex: graphIndex) { r = r.union(b) }
        }
        return r.applying(GraphRenderer.graphTransform(g))
    }

    public func contentBounds() -> CGRect {
        var r = CGRect.null
        for i in project.graphs.indices {
            if let v = options.visibleGraphs, !v.contains(i) { continue }
            r = r.union(contentBounds(graphIndex: i))
        }
        return r.isNull ? .zero : r
    }
}
