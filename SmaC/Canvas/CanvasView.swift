import AppKit
import UniformTypeIdentifiers
import SMPKit

/// 作業面: 紙の上にグラフを描き、マウスで選ぶ・動かす・大きさを変える。
/// 拡大・縮小はスクロールビューの拡大率で行う(線や文字は拡大してもくっきり描き直される)。
@MainActor
final class CanvasView: NSView {
    weak var document: GraphDocument?
    weak var controller: GraphWindowController?

    /// 100% のときの 0.01 mm の長さ(点)。72 点 = 1 インチの実寸
    static let unit = CGFloat(Units.pointsPerHundredthMM)
    /// 紙のまわりの余白(点)
    static let margin: CGFloat = 36

    var unit: CGFloat { CanvasView.unit }

    /// 選んでいる文字・図形など(選択中のグラフの中)
    var selection: Set<UUID> = [] {
        didSet {
            guard oldValue != selection else { return }
            needsDisplay = true
            controller?.canvasSelectionChanged()
        }
    }

    enum Mode: Equatable {
        case normal
        /// 囲んだ範囲を軸の範囲にする
        case zoomRect
        /// 囲んだ範囲の点を除く
        case maskRect
        /// グラフの点の値を読む
        case readValue
    }

    var mode: Mode = .normal {
        didSet {
            guard oldValue != mode else { return }
            dragRect = nil
            if mode != .readValue { readValue = nil }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            controller?.canvasModeChanged()
        }
    }

    // 値を読む
    struct ReadValue: Equatable { var graph: Int; var series: Int; var index: Int; var x: Double; var y: Double }
    var readValue: ReadValue? { didSet { if oldValue != readValue { needsDisplay = true; controller?.readValueChanged() } } }
    /// 値を読む系列(nil なら表示中の全部から近い点)
    var readSeries: Int?

    private enum Drag {
        case objects(graph: Int, ids: Set<UUID>, original: SMPProject, start: CGPoint)
        case arrowEnd(graph: Int, id: UUID, end: Int, original: SMPProject)
        case corner(graph: Int, id: UUID, corner: Int, original: SMPProject)
        case graph(graph: Int, edges: Edges, original: SMPProject, start: CGPoint)
        case rect(start: CGPoint, purpose: RectPurpose)
    }

    enum RectPurpose { case select, zoom, mask, region }

    private var drag: Drag?
    private(set) var dragRect: CGRect?
    private var dragPurpose: RectPurpose = .select
    private var mouseDownView: CGPoint = .zero
    private var didDrag = false
    private var additive = false
    private var rightDown: CGPoint?

    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1), right = Edges(rawValue: 2), top = Edges(rawValue: 4), bottom = Edges(rawValue: 8)
        static let move = Edges(rawValue: 16)
    }

    /// 紙とグラフが入る範囲(0.01 mm)
    private(set) var contentRect = CGRect(x: 0, y: 0, width: 21000, height: 29700)

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    // MARK: - 座標

    var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }

    /// 1 画面点が何 0.01 mm か(当たり判定の幅などに使う)
    var pagePerScreenPoint: CGFloat { 1 / (unit * magnification) }

    var origin: CGPoint {
        CGPoint(x: CanvasView.margin - contentRect.minX * unit, y: CanvasView.margin - contentRect.minY * unit)
    }

    /// 用紙の大きさ(0.01 mm)。印刷の倍率が 100% でなければ、その分だけ紙を大きく(小さく)見せる
    var pageSize: CGSize {
        let page = document?.project.graphs.first?.page ?? PageSetup()
        let s = page.paperSizeMM
        let scale = Double(page.tail.first ?? 100) / 100
        let k = scale > 0 ? 1 / scale : 1
        return CGSize(width: s.width * 100 * k, height: s.height * 100 * k)
    }

    var paperRect: CGRect { CGRect(origin: .zero, size: pageSize) }

    func viewPoint(_ p: CGPoint) -> CGPoint {
        let o = origin
        return CGPoint(x: o.x + p.x * unit, y: o.y + p.y * unit)
    }

    func pagePoint(_ v: CGPoint) -> CGPoint {
        let o = origin
        return CGPoint(x: (v.x - o.x) / unit, y: (v.y - o.y) / unit)
    }

    func viewRect(_ r: CGRect) -> CGRect {
        let a = viewPoint(r.origin)
        return CGRect(x: a.x, y: a.y, width: r.width * unit, height: r.height * unit)
    }

    func pagePoint(of event: NSEvent) -> CGPoint { pagePoint(convert(event.locationInWindow, from: nil)) }

    func frameRectOnPage(_ g: Graph) -> CGRect {
        CGRect(x: 0, y: 0, width: g.width, height: g.height).applying(GraphRenderer.graphTransform(g))
    }

    /// 紙とグラフ全部が入るように大きさを決め直す(ドラッグ中は変えない)
    func updateSize() {
        guard drag == nil else { return }
        var r = paperRect
        if let doc = document {
            for g in doc.project.graphs { r = r.union(frameRectOnPage(g).insetBy(dx: -3000, dy: -3000)) }
        }
        let oldOrigin = origin
        contentRect = r.integral
        let size = NSSize(width: ceil(contentRect.width * unit + CanvasView.margin * 2),
                          height: ceil(contentRect.height * unit + CanvasView.margin * 2))
        if frame.size != size {
            // 左上に広がったときも、見ている所がずれないようにする
            let shift = CGPoint(x: origin.x - oldOrigin.x, y: origin.y - oldOrigin.y)
            setFrameSize(size)
            if shift != .zero, let clip = enclosingScrollView?.contentView {
                clip.scroll(to: CGPoint(x: clip.bounds.minX + shift.x, y: clip.bounds.minY + shift.y))
            }
        }
        needsDisplay = true
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor.underPageBackgroundColor.setFill()
        dirtyRect.fill()
        guard let doc = document else { return }

        // 紙(白・影つき)
        let paper = viewRect(paperRect)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 5, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        NSColor.white.setFill()
        ctx.fill(paper)
        ctx.restoreGState()
        if AppSettings.shared.gridMM > 0 { drawGrid(ctx, paper: paper, stepMM: AppSettings.shared.gridMM) }

        let renderer = doc.renderer()
        ctx.saveGState()
        let o = origin
        ctx.translateBy(x: o.x, y: o.y)
        ctx.scaleBy(x: unit, y: unit)
        renderer.draw(in: ctx)
        ctx.restoreGState()

        drawOverlay(ctx, renderer: renderer)
    }

    /// 方眼の目安(紙の上に薄い線)
    func drawGrid(_ ctx: CGContext, paper: CGRect, stepMM: Double) {
        let step = CGFloat(stepMM) * 100 * unit
        guard step * magnification >= 4 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(calibratedRed: 0.2, green: 0.45, blue: 0.9, alpha: 0.12).cgColor)
        ctx.setLineWidth(1 / magnification)
        var x = paper.minX
        while x <= paper.maxX { ctx.move(to: CGPoint(x: x, y: paper.minY)); ctx.addLine(to: CGPoint(x: x, y: paper.maxY)); x += step }
        var y = paper.minY
        while y <= paper.maxY { ctx.move(to: CGPoint(x: paper.minX, y: y)); ctx.addLine(to: CGPoint(x: paper.maxX, y: y)); y += step }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private var accent: NSColor { NSColor.controlAccentColor }

    /// 四角いつまみ(白地に色の縁)
    private func handle(_ ctx: CGContext, at p: CGPoint, round: Bool = false) {
        let s = 7 / magnification
        let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1.2 / magnification)
        if round { ctx.fillEllipse(in: r); ctx.strokeEllipse(in: r) } else { ctx.fill(r); ctx.stroke(r) }
    }

    func drawOverlay(_ ctx: CGContext, renderer: GraphRenderer) {
        guard let doc = document else { return }
        let px = 1 / magnification
        ctx.saveGState()
        // 選んでいるグラフ: 枠の線と 8 つのつまみ(文字などを選んでいないとき)
        if selection.isEmpty, mode == .normal, let g = doc.activeGraph, isVisible(doc.activeGraphIndex) {
            let r = viewRect(frameRectOnPage(g))
            ctx.setStrokeColor(accent.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(px)
            ctx.stroke(r.insetBy(dx: -px / 2, dy: -px / 2))
            for p in handlePoints(r) { handle(ctx, at: p) }
        }
        // 選んだ文字・図形
        if let g = doc.activeGraph {
            let t = GraphRenderer.graphTransform(g)
            let fr = GraphRenderer.Frame(g)
            for item in g.objects where selection.contains(item.id) {
                switch item.object {
                case .shape(let s) where !s.isBox:
                    guard let (a, b) = GraphRenderer.shapePoints(s, fr) else { continue }
                    let va = viewPoint(a.applying(t)), vb = viewPoint(b.applying(t))
                    ctx.setStrokeColor(accent.withAlphaComponent(0.5).cgColor)
                    ctx.setLineWidth(px)
                    ctx.move(to: va); ctx.addLine(to: vb); ctx.strokePath()
                    handle(ctx, at: va, round: true)
                    handle(ctx, at: vb, round: true)
                case .shape, .picture:
                    guard let r = cornerRect(item.object, graph: g) else { continue }
                    let vr = viewRect(r.applying(t))
                    ctx.setStrokeColor(accent.cgColor)
                    ctx.setLineWidth(px)
                    ctx.stroke(vr)
                    for p in [CGPoint(x: vr.minX, y: vr.minY), CGPoint(x: vr.maxX, y: vr.minY),
                              CGPoint(x: vr.minX, y: vr.maxY), CGPoint(x: vr.maxX, y: vr.maxY)] { handle(ctx, at: p) }
                default:
                    guard let b = renderer.objectBounds(item.object, graphIndex: doc.activeGraphIndex) else { continue }
                    let r = viewRect(b.applying(t)).insetBy(dx: -3 * px, dy: -3 * px)
                    ctx.setStrokeColor(accent.cgColor)
                    ctx.setLineWidth(px)
                    ctx.stroke(r)
                }
            }
        }
        // ドラッグ中の四角
        if let r = dragRect {
            let vr = viewRect(r)
            let color: NSColor = dragPurpose == .mask ? .systemRed : accent
            ctx.setFillColor(color.withAlphaComponent(0.1).cgColor)
            ctx.fill(vr)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(px)
            if dragPurpose != .select { ctx.setLineDash(phase: 0, lengths: [4 * px, 3 * px]) }
            ctx.stroke(vr)
            ctx.setLineDash(phase: 0, lengths: [])
        }
        // 値を読む: 点を通る縦と横の線と、値の札
        if let rv = readValue, rv.graph < doc.project.graphs.count, rv.series < doc.project.graphs[rv.graph].series.count {
            let g = doc.project.graphs[rv.graph]
            let s = g.series[rv.series]
            let fr = GraphRenderer.Frame(g)
            if let p = fr.point(rv.x, rv.y, h: g.horizontalAxisIndex(for: s), v: g.verticalAxisIndex(for: s)) {
                let v = viewPoint(p.applying(GraphRenderer.graphTransform(g)))
                let box = viewRect(frameRectOnPage(g))
                ctx.setStrokeColor(accent.withAlphaComponent(0.8).cgColor)
                ctx.setLineWidth(px)
                ctx.move(to: CGPoint(x: box.minX, y: v.y)); ctx.addLine(to: CGPoint(x: box.maxX, y: v.y))
                ctx.move(to: CGPoint(x: v.x, y: box.minY)); ctx.addLine(to: CGPoint(x: v.x, y: box.maxY))
                ctx.strokePath()
                let d = 9 * px
                ctx.setStrokeColor(accent.cgColor)
                ctx.setLineWidth(2 * px)
                ctx.strokeEllipse(in: CGRect(x: v.x - d / 2, y: v.y - d / 2, width: d, height: d))
                drawValueTag(at: v, lines: ["\(s.displayName)  #\(rv.index + 1)", "X = \(NumberText.g(rv.x))", "Y = \(NumberText.g(rv.y))"],
                             within: visibleRect)
            }
        }
        ctx.restoreGState()
    }

    /// 値の札(拡大率にかかわらず同じ大きさ)
    private func drawValueTag(at p: CGPoint, lines: [String], within visible: CGRect) {
        let k = 1 / magnification
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11 * k, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let text = NSAttributedString(string: lines.joined(separator: "\n"), attributes: attrs)
        let size = text.boundingRect(with: CGSize(width: 1e6, height: 1e6), options: [.usesLineFragmentOrigin]).size
        let pad = 6 * k
        var r = CGRect(x: p.x + 12 * k, y: p.y + 12 * k, width: size.width + pad * 2, height: size.height + pad * 2)
        if r.maxX > visible.maxX { r.origin.x = p.x - 12 * k - r.width }
        if r.maxY > visible.maxY { r.origin.y = p.y - 12 * k - r.height }
        let path = NSBezierPath(roundedRect: r, xRadius: 6 * k, yRadius: 6 * k)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = k
        path.stroke()
        text.draw(with: r.insetBy(dx: pad, dy: pad), options: [.usesLineFragmentOrigin])
    }

    func handlePoints(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }

    func isVisible(_ gi: Int) -> Bool {
        guard let doc = document else { return false }
        return doc.soloGraph == nil || doc.soloGraph == gi
    }

    /// 枠・図の四隅(グラフの中の座標)
    func cornerRect(_ o: GraphObject, graph g: Graph) -> CGRect? {
        switch o {
        case .shape(let s) where s.isBox:
            guard let (a, b) = GraphRenderer.shapePoints(s, GraphRenderer.Frame(g)) else { return nil }
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        case .picture(let p):
            let x1 = p.shape.x1 * 100, y1 = p.shape.y1 * 100, x2 = p.shape.x2 * 100, y2 = p.shape.y2 * 100
            return CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
        default:
            return nil
        }
    }

    // MARK: - 当たり判定

    enum Hit {
        case object(graph: Int, id: UUID)
        case arrowEnd(graph: Int, id: UUID, end: Int)
        case corner(graph: Int, id: UUID, corner: Int)
        case frame(graph: Int, edges: Edges)
        case axis(graph: Int, axis: Int)
        case inside(graph: Int)
        case none

        var graphIndex: Int? {
            switch self {
            case .object(let g, _), .arrowEnd(let g, _, _), .corner(let g, _, _), .frame(let g, _), .axis(let g, _), .inside(let g): return g
            case .none: return nil
            }
        }
    }

    func hitTest(page p: CGPoint) -> Hit {
        guard let doc = document else { return .none }
        let renderer = doc.renderer()
        let order = graphOrder()
        let tolScreen = pagePerScreenPoint * 5
        // 選んでいるものの角・端が先
        if let g = doc.activeGraph, !selection.isEmpty {
            let gi = doc.activeGraphIndex
            let t = GraphRenderer.graphTransform(g)
            let local = p.applying(t.inverted())
            let tol = tolScreen / g.zoomFactor
            for item in g.objects.reversed() where selection.contains(item.id) {
                if case .shape(let s) = item.object, !s.isBox, let (a, b) = GraphRenderer.shapePoints(s, GraphRenderer.Frame(g)) {
                    if hypot(local.x - a.x, local.y - a.y) <= tol * 1.4 { return .arrowEnd(graph: gi, id: item.id, end: 0) }
                    if hypot(local.x - b.x, local.y - b.y) <= tol * 1.4 { return .arrowEnd(graph: gi, id: item.id, end: 1) }
                }
                if let r = cornerRect(item.object, graph: g) {
                    let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
                    for (k, c) in corners.enumerated() where hypot(local.x - c.x, local.y - c.y) <= tol * 1.4 {
                        return .corner(graph: gi, id: item.id, corner: k)
                    }
                }
            }
        }
        for gi in order {
            let g = doc.project.graphs[gi]
            let t = GraphRenderer.graphTransform(g)
            let local = p.applying(t.inverted())
            let fr = GraphRenderer.Frame(g)
            let tol = tolScreen / g.zoomFactor
            for item in g.objects.reversed() {
                switch item.object {
                case .shape(let s) where !s.isBox:
                    guard let (a, b) = GraphRenderer.shapePoints(s, fr) else { continue }
                    if distance(local, a, b) <= tol + CGFloat(s.width) { return .object(graph: gi, id: item.id) }
                case .shape(let s):
                    guard let (a, b) = GraphRenderer.shapePoints(s, fr) else { continue }
                    let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                    // 枠は縁をつかむ(中はその下のものを選べるように)
                    if r.insetBy(dx: -tol, dy: -tol).contains(local) && !r.insetBy(dx: tol * 2, dy: tol * 2).contains(local) {
                        return .object(graph: gi, id: item.id)
                    }
                default:
                    if let b = renderer.objectBounds(item.object, graphIndex: gi), b.insetBy(dx: -tol, dy: -tol).contains(local) {
                        return .object(graph: gi, id: item.id)
                    }
                }
            }
        }
        for gi in order {
            let g = doc.project.graphs[gi]
            let r = frameRectOnPage(g)
            let tol = tolScreen
            let nearL = abs(p.x - r.minX) <= tol, nearR = abs(p.x - r.maxX) <= tol
            let nearT = abs(p.y - r.minY) <= tol, nearB = abs(p.y - r.maxY) <= tol
            let inX = p.x >= r.minX - tol && p.x <= r.maxX + tol
            let inY = p.y >= r.minY - tol && p.y <= r.maxY + tol
            var e: Edges = []
            if nearL && inY { e.insert(.left) }
            if nearR && inY { e.insert(.right) }
            if nearT && inX { e.insert(.top) }
            if nearB && inX { e.insert(.bottom) }
            if !e.isEmpty { return .frame(graph: gi, edges: e) }
        }
        for gi in order {
            let g = doc.project.graphs[gi]
            let r = frameRectOnPage(g)
            if r.contains(p) { return .inside(graph: gi) }
            let band = 1500.0 * g.zoomFactor
            if p.x >= r.minX && p.x <= r.maxX {
                if p.y > r.maxY && p.y < r.maxY + band { return .axis(graph: gi, axis: 0) }
                if p.y < r.minY && p.y > r.minY - band { return .axis(graph: gi, axis: 2) }
            }
            if p.y >= r.minY && p.y <= r.maxY {
                if p.x < r.minX && p.x > r.minX - band * 1.6 { return .axis(graph: gi, axis: 1) }
                if p.x > r.maxX && p.x < r.maxX + band * 1.6 { return .axis(graph: gi, axis: 3) }
            }
        }
        return .none
    }

    /// 当たり判定の順番(選んでいるグラフが先)
    func graphOrder() -> [Int] {
        guard let doc = document else { return [] }
        var all = Array(doc.project.graphs.indices).filter { isVisible($0) }
        if let i = all.firstIndex(of: doc.activeGraphIndex) { all.remove(at: i); all.insert(doc.activeGraphIndex, at: 0) }
        return all
    }

    func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let l2 = dx * dx + dy * dy
        guard l2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    // MARK: - マウス

    func snapped(_ v: CGFloat) -> CGFloat {
        let s = CGFloat(AppSettings.shared.snapMM) * 100
        guard s > 0 else { return v.rounded() }
        return (v / s).rounded() * s
    }

    func snappedPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: snapped(p.x), y: snapped(p.y)) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.modifierFlags.contains(.control) {
            showContextMenu(for: event)
            return
        }
        guard let doc = document else { return }
        let p = pagePoint(of: event)
        mouseDownView = convert(event.locationInWindow, from: nil)
        didDrag = false
        additive = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)

        switch mode {
        case .zoomRect, .maskRect:
            dragPurpose = mode == .zoomRect ? .zoom : .mask
            drag = .rect(start: p, purpose: dragPurpose)
            dragRect = CGRect(origin: p, size: .zero)
            return
        case .readValue:
            updateReadValue(at: p)
            return
        case .normal:
            break
        }

        let hit = hitTest(page: p)
        if event.clickCount >= 2 {
            controller?.canvasDoubleClicked(hit)
            return
        }
        switch hit {
        case .object(let gi, let id):
            activate(gi)
            if additive {
                if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            } else if !selection.contains(id) {
                selection = [id]
            }
            drag = selection.isEmpty ? nil : .objects(graph: gi, ids: selection, original: doc.project, start: p)
        case .arrowEnd(let gi, let id, let end):
            activate(gi)
            selection = [id]
            drag = .arrowEnd(graph: gi, id: id, end: end, original: doc.project)
        case .corner(let gi, let id, let corner):
            activate(gi)
            selection = [id]
            drag = .corner(graph: gi, id: id, corner: corner, original: doc.project)
        case .frame(let gi, let edges):
            activate(gi)
            selection = []
            drag = .graph(graph: gi, edges: edges, original: doc.project, start: p)
        case .inside(let gi), .axis(let gi, _):
            activate(gi)
            selection = []
            // グラフの中をドラッグするとグラフごと動く
            drag = .graph(graph: gi, edges: .move, original: doc.project, start: p)
        case .none:
            if !additive { selection = [] }
            dragPurpose = .select
            drag = .rect(start: p, purpose: .select)
        }
        controller?.canvasClicked(hit)
        needsDisplay = true
    }

    private func activate(_ gi: Int) {
        guard let doc = document, doc.activeGraphIndex != gi else { return }
        doc.activeGraphIndex = gi
        selection = []
    }

    override func mouseDragged(with event: NSEvent) {
        guard let doc = document, let d = drag else { return }
        let v = convert(event.locationInWindow, from: nil)
        if !didDrag {
            // 少し動かしただけではドラッグにしない(クリックのつもりで動かさないように)
            guard hypot(v.x - mouseDownView.x, v.y - mouseDownView.y) * magnification >= 3 else { return }
            didDrag = true
        }
        let p = pagePoint(v)
        autoscroll(with: event)
        switch d {
        case .rect(let start, _):
            dragRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            controller?.canvasRectChanged(dragRect, purpose: dragPurpose)
        case .objects(let gi, let ids, let original, let start):
            let g0 = original.graphs[gi]
            let z = g0.zoomFactor
            let dx = (p.x - start.x) / z, dy = (p.y - start.y) / z
            doc.preview { proj in
                proj = original
                for (k, item) in proj.graphs[gi].objects.enumerated() where ids.contains(item.id) {
                    proj.graphs[gi].objects[k].object = moved(item.object, dx: dx, dy: dy, graph: g0)
                }
            }
            NSCursor.closedHand.set()
        case .arrowEnd(let gi, let id, let end, let original):
            let g0 = original.graphs[gi]
            let local = p.applying(GraphRenderer.graphTransform(g0).inverted())
            doc.preview { proj in
                proj = original
                guard let k = proj.graphs[gi].objects.firstIndex(where: { $0.id == id }),
                      case .shape(var s) = proj.graphs[gi].objects[k].object else { return }
                setShapeEnd(&s, end: end, local: snappedPoint(local), graph: g0)
                proj.graphs[gi].objects[k].object = .shape(s)
            }
        case .corner(let gi, let id, let corner, let original):
            let g0 = original.graphs[gi]
            let local = snappedPoint(p.applying(GraphRenderer.graphTransform(g0).inverted()))
            doc.preview { proj in
                proj = original
                guard let k = proj.graphs[gi].objects.firstIndex(where: { $0.id == id }) else { return }
                proj.graphs[gi].objects[k].object = resized(proj.graphs[gi].objects[k].object, corner: corner, to: local, graph: g0)
            }
        case .graph(let gi, let edges, let original, let start):
            let g0 = original.graphs[gi]
            let dx = p.x - start.x, dy = p.y - start.y
            doc.preview { proj in
                proj = original
                var g = g0
                let z = g0.zoomFactor
                if edges.contains(.move) {
                    g.left = Int(snapped(CGFloat(g0.left) + dx)); g.top = Int(snapped(CGFloat(g0.top) + dy))
                } else {
                    var l = CGFloat(g0.left), t = CGFloat(g0.top)
                    var w = CGFloat(g0.width), h = CGFloat(g0.height)
                    if edges.contains(.left) { let nl = snapped(l + dx); w -= (nl - l) / z; l = nl }
                    if edges.contains(.right) { w = snapped(w * z + dx) / z }
                    if edges.contains(.top) { let nt = snapped(t + dy); h -= (nt - t) / z; t = nt }
                    if edges.contains(.bottom) { h = snapped(h * z + dy) / z }
                    g.left = Int(l); g.top = Int(t)
                    g.width = Int(max(w, 500)); g.height = Int(max(h, 500))
                }
                proj.graphs[gi] = g
            }
            controller?.canvasGraphDragged(graph: gi)
            if edges.contains(.move) { NSCursor.closedHand.set() }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let doc = document, let d = drag else { return }
        drag = nil
        defer {
            updateSize()
            needsDisplay = true
            updateCursor(page: pagePoint(of: event))
        }
        switch d {
        case .rect(_, let purpose):
            let r = dragRect
            dragRect = nil
            controller?.canvasRectChanged(nil, purpose: purpose)
            guard didDrag, let r else { return }
            switch purpose {
            case .select:
                selectObjects(in: r)
            case .zoom:
                mode = .normal
                if r.width > 30 && r.height > 30 { controller?.applyZoomRect(pageRect: r) }
            case .mask:
                mode = .normal
                if r.width > 30 && r.height > 30 { controller?.applyMaskRect(pageRect: r) }
            case .region:
                break
            }
        case .objects(_, _, let original, _):
            if didDrag { doc.commitPreview(from: original, actionName: "移動") }
        case .arrowEnd(_, _, _, let original):
            if didDrag { doc.commitPreview(from: original, actionName: "線の端の移動") }
        case .corner(_, _, _, let original):
            if didDrag { doc.commitPreview(from: original, actionName: "大きさの変更") }
        case .graph(_, let edges, let original, _):
            if didDrag { doc.commitPreview(from: original, actionName: edges.contains(.move) ? "グラフの移動" : "グラフの大きさの変更") }
        }
    }

    /// 囲んだ範囲にかかる文字・図形を選ぶ(選んでいるグラフの中)
    func selectObjects(in r: CGRect) {
        guard let doc = document, let g = doc.activeGraph else { return }
        let renderer = doc.renderer()
        let t = GraphRenderer.graphTransform(g)
        var ids = additive ? selection : []
        for item in g.objects {
            if let b = renderer.objectBounds(item.object, graphIndex: doc.activeGraphIndex), b.applying(t).intersects(r) {
                ids.insert(item.id)
            }
        }
        selection = ids
    }

    // 右ボタン: その場のメニュー。ドラッグで囲むと、その範囲のメニュー
    override func rightMouseDown(with event: NSEvent) {
        rightDown = pagePoint(of: event)
        dragRect = nil
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let s = rightDown else { return }
        let p = pagePoint(of: event)
        dragPurpose = .region
        dragRect = CGRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
        needsDisplay = true
    }

    override func rightMouseUp(with event: NSEvent) {
        defer { rightDown = nil }
        if let r = dragRect, r.width * unit * magnification > 8, r.height * unit * magnification > 8 {
            controller?.showRegionMenu(pageRect: r, event: event, in: self)
            dragRect = nil
            needsDisplay = true
            return
        }
        dragRect = nil
        showContextMenu(for: event)
    }

    private func showContextMenu(for event: NSEvent) {
        let p = pagePoint(of: event)
        let hit = hitTest(page: p)
        switch hit {
        case .object(let gi, let id), .arrowEnd(let gi, let id, _), .corner(let gi, let id, _):
            activate(gi)
            if !selection.contains(id) { selection = [id] }
        case .frame(let gi, _), .axis(let gi, _), .inside(let gi):
            activate(gi)
            selection = []
        case .none:
            selection = []
        }
        controller?.canvasClicked(hit)
        if let menu = controller?.contextMenu(for: hit) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = pagePoint(of: event)
        if mode == .readValue { updateReadValue(at: p) }
        controller?.canvasMouseMoved(page: p)
        updateCursor(page: p)
    }

    override func mouseExited(with event: NSEvent) {
        controller?.canvasMouseMoved(page: nil)
    }

    override func scrollWheel(with event: NSEvent) {
        // 値を読むときは、上下のスクロールで隣の点へ
        if mode == .readValue, let rv = readValue, !event.modifierFlags.contains(.command) {
            let d = event.scrollingDeltaY
            if abs(d) >= 1 && abs(d) > abs(event.scrollingDeltaX) {
                stepReadValue(rv, by: d > 0 ? -1 : 1)
                return
            }
        }
        super.scrollWheel(with: event)
    }

    func updateCursor(page p: CGPoint) {
        switch mode {
        case .zoomRect, .maskRect, .readValue: NSCursor.crosshair.set(); return
        case .normal: break
        }
        switch hitTest(page: p) {
        case .frame(_, let e):
            let horizontal = e.contains(.left) || e.contains(.right), vertical = e.contains(.top) || e.contains(.bottom)
            if horizontal && !vertical { NSCursor.resizeLeftRight.set() }
            else if vertical && !horizontal { NSCursor.resizeUpDown.set() }
            else { NSCursor.crosshair.set() }
        case .arrowEnd, .corner: NSCursor.crosshair.set()
        case .object, .inside, .axis: NSCursor.arrow.set()
        case .none: NSCursor.arrow.set()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(page: pagePoint(of: event))
    }

    // MARK: - 動かす・大きさを変える

    func moved(_ o: GraphObject, dx: CGFloat, dy: CGFloat, graph g: Graph) -> GraphObject {
        switch o {
        case .text(var t):
            let z = t.absolutePosition ? g.zoomFactor : 1
            t.x = Int(snapped(CGFloat(t.x) + dx * z))
            t.y = Int(snapped(CGFloat(t.y) + dy * z))
            return .text(t)
        case .dot(var d):
            d.x = Int(snapped(CGFloat(d.x) + dx)); d.y = Int(snapped(CGFloat(d.y) + dy))
            return .dot(d)
        case .shape(var s):
            let fr = GraphRenderer.Frame(g)
            guard let (a, b) = GraphRenderer.shapePoints(s, fr) else { return o }
            let na = CGPoint(x: snapped(a.x + dx), y: snapped(a.y + dy))
            let nb = CGPoint(x: na.x + (b.x - a.x), y: na.y + (b.y - a.y))
            setShapeEnd(&s, end: 0, local: na, graph: g)
            setShapeEnd(&s, end: 1, local: nb, graph: g)
            return .shape(s)
        case .picture(var pic):
            let w = pic.shape.x2 - pic.shape.x1, h = pic.shape.y2 - pic.shape.y1
            pic.shape.x1 = Double(snapped(CGFloat(pic.shape.x1 * 100) + dx)) / 100
            pic.shape.y1 = Double(snapped(CGFloat(pic.shape.y1 * 100) + dy)) / 100
            pic.shape.x2 = pic.shape.x1 + w
            pic.shape.y2 = pic.shape.y1 + h
            return .picture(pic)
        case .raw:
            return o
        }
    }

    /// 枠・図の角を動かす(0:左上 1:右上 2:左下 3:右下)
    func resized(_ o: GraphObject, corner: Int, to p: CGPoint, graph g: Graph) -> GraphObject {
        guard let r = cornerRect(o, graph: g) else { return o }
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        if corner == 0 || corner == 2 { minX = p.x } else { maxX = p.x }
        if corner == 0 || corner == 1 { minY = p.y } else { maxY = p.y }
        let a = CGPoint(x: min(minX, maxX), y: min(minY, maxY)), b = CGPoint(x: max(minX, maxX), y: max(minY, maxY))
        switch o {
        case .shape(var s):
            setShapeEnd(&s, end: 0, local: a, graph: g)
            setShapeEnd(&s, end: 1, local: b, graph: g)
            return .shape(s)
        case .picture(var pic):
            pic.shape.x1 = Double(a.x) / 100; pic.shape.y1 = Double(a.y) / 100
            pic.shape.x2 = Double(b.x) / 100; pic.shape.y2 = Double(b.y) / 100
            return .picture(pic)
        default:
            return o
        }
    }

    /// 矢印などの端をグラフの中の位置に合わせる(位置の単位が軸の値なら値に直す)
    func setShapeEnd(_ s: inout ShapeObject, end: Int, local p: CGPoint, graph g: Graph) {
        let fr = GraphRenderer.Frame(g)
        func vx(_ x: CGFloat) -> Double {
            switch s.xReference {
            case 1: return fr.scales[0].value(atFraction: Double(x) / fr.width)
            case 2: return fr.scales[2].value(atFraction: Double(x) / fr.width)
            default: return Double(x) / 100
            }
        }
        func vy(_ y: CGFloat) -> Double {
            switch s.yReference {
            case 1: return fr.scales[1].value(atFraction: 1 - Double(y) / fr.height)
            case 2: return fr.scales[3].value(atFraction: 1 - Double(y) / fr.height)
            default: return Double(y) / 100
            }
        }
        if end == 0 { s.x1 = vx(p.x); s.y1 = vy(p.y) } else { s.x2 = vx(p.x); s.y2 = vy(p.y) }
    }

    func movedExact(_ o: GraphObject, dx: CGFloat, dy: CGFloat, graph g: Graph) -> GraphObject {
        switch o {
        case .text(var t):
            let z = t.absolutePosition ? g.zoomFactor : 1
            t.x += Int(dx * z); t.y += Int(dy * z); return .text(t)
        case .dot(var d): d.x += Int(dx); d.y += Int(dy); return .dot(d)
        case .shape(var s):
            let fr = GraphRenderer.Frame(g)
            guard let (a, b) = GraphRenderer.shapePoints(s, fr) else { return o }
            setShapeEnd(&s, end: 0, local: CGPoint(x: a.x + dx, y: a.y + dy), graph: g)
            setShapeEnd(&s, end: 1, local: CGPoint(x: b.x + dx, y: b.y + dy), graph: g)
            return .shape(s)
        case .picture(var pic):
            pic.shape.x1 += Double(dx) / 100; pic.shape.x2 += Double(dx) / 100
            pic.shape.y1 += Double(dy) / 100; pic.shape.y2 += Double(dy) / 100
            return .picture(pic)
        case .raw: return o
        }
    }

    // MARK: - キー

    override func keyDown(with event: NSEvent) {
        guard let doc = document else { return }
        if event.keyCode == 53 { // esc
            if mode != .normal { mode = .normal } else { selection = [] }
            return
        }
        if mode == .readValue, let rv = readValue, event.keyCode == 123 || event.keyCode == 124 {
            stepReadValue(rv, by: event.keyCode == 123 ? -1 : 1)
            return
        }
        // 矢印で少しずつ動かす(⌥ で 0.1 mm、⇧ で 5 mm)
        var step = CGFloat(max(AppSettings.shared.snapMM, 0.5)) * 100
        if event.modifierFlags.contains(.option) { step = 10 }
        if event.modifierFlags.contains(.shift) { step = 500 }
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch event.keyCode {
        case 51, 117: controller?.delete(nil); return
        case 123: dx = -step
        case 124: dx = step
        case 125: dy = step
        case 126: dy = -step
        default: super.keyDown(with: event); return
        }
        let gi = doc.activeGraphIndex
        guard let g = doc.activeGraph else { return }
        if selection.isEmpty {
            // 何も選んでいなければグラフを動かす
            doc.update(graph: gi, "グラフの移動") { graph in
                graph.left += Int(dx); graph.top += Int(dy)
            }
            updateSize()
            return
        }
        let ids = selection
        doc.update(graph: gi, "移動") { graph in
            for (k, item) in graph.objects.enumerated() where ids.contains(item.id) {
                graph.objects[k].object = self.movedExact(item.object, dx: dx / g.zoomFactor, dy: dy / g.zoomFactor, graph: g)
            }
        }
    }

    // MARK: - 値を読む

    func updateReadValue(at p: CGPoint) {
        guard let doc = document, let g = doc.activeGraph else { readValue = nil; return }
        let gi = doc.activeGraphIndex
        let data = doc.plotData()
        guard gi < data.count else { return }
        let local = p.applying(GraphRenderer.graphTransform(g).inverted())
        let fr = GraphRenderer.Frame(g)
        var best: (ReadValue, CGFloat)?
        for (si, s) in g.series.enumerated() where s.visible && si < data[gi].count {
            if let only = readSeries, only != si { continue }
            let d = data[gi][si]
            let h = g.horizontalAxisIndex(for: s), v = g.verticalAxisIndex(for: s)
            for i in 0..<min(d.x.count, d.y.count) {
                guard d.x[i].isFinite, d.y[i].isFinite, let q = fr.point(d.x[i], d.y[i], h: h, v: v) else { continue }
                let dist = hypot(q.x - local.x, (q.y - local.y) * (readSeries == nil ? 1 : 0.25))
                if best == nil || dist < best!.1 {
                    best = (ReadValue(graph: gi, series: si, index: i, x: d.x[i], y: d.y[i]), dist)
                }
            }
        }
        if let b = best?.0 { readValue = b }
    }

    func stepReadValue(_ rv: ReadValue, by delta: Int) {
        guard let doc = document else { return }
        let data = doc.plotData()
        guard rv.graph < data.count, rv.series < data[rv.graph].count else { return }
        let d = data[rv.graph][rv.series]
        let n = min(d.x.count, d.y.count)
        guard n > 0 else { return }
        var i = max(0, min(n - 1, rv.index + delta))
        // 値のない点は飛ばす
        while i > 0 && i < n - 1 && !(d.x[i].isFinite && d.y[i].isFinite) { i += delta > 0 ? 1 : -1 }
        guard d.x[i].isFinite, d.y[i].isFinite else { return }
        readValue = ReadValue(graph: rv.graph, series: rv.series, index: i, x: d.x[i], y: d.y[i])
    }

    func setReadValue(series si: Int, index i: Int) {
        guard let doc = document else { return }
        let gi = doc.activeGraphIndex
        let data = doc.plotData()
        guard gi < data.count, si < data[gi].count else { return }
        let d = data[gi][si]
        let n = min(d.x.count, d.y.count)
        guard n > 0 else { return }
        var k = max(0, min(i, n - 1))
        while k < n - 1 && !(d.x[k].isFinite && d.y[k].isFinite) { k += 1 }
        readValue = ReadValue(graph: gi, series: si, index: k, x: d.x[k], y: d.y[k])
    }

    // MARK: - ファイルを落とす(データ・SMP・画像)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        let p = pagePoint(convert(sender.draggingLocation, from: nil))
        controller?.handleDroppedFiles(urls, at: p)
        return true
    }

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
}

/// 作業面が窓より小さいとき、真ん中に置く
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return r }
        let f = doc.frame
        if r.width > f.width { r.origin.x = (f.width - r.width) / 2 }
        if r.height > f.height { r.origin.y = (f.height - r.height) / 2 }
        return r
    }
}
