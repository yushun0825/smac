import AppKit
import SwiftUI
import SMPKit

/// 書類の窓: 左にサイドバー(グラフ・データ・文字など)、中に紙の作業面、右にインスペクタ(選んだものの設定)
@MainActor
final class GraphWindowController: NSWindowController, NSWindowDelegate {
    let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000))
    let scrollView = NSScrollView()
    let statusBar = CanvasStatusBar()
    let splitController = NSSplitViewController()
    private(set) var state: EditorState!
    private(set) var sidebarItem: NSSplitViewItem!
    private(set) var inspectorItem: NSSplitViewItem!
    /// 拡大率の表示(ツールバー)
    var zoomButton: NSPopUpButton?
    /// 押したままになるツールバーのボタン
    var toggleButtons: [NSToolbarItem.Identifier: NSButton] = [:]
    private var observers: [NSObjectProtocol] = []
    private var didFitOnce = false

    var doc: GraphDocument? { document as? GraphDocument }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 820, height: 520)
        window.toolbarStyle = .unified
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var document: AnyObject? {
        didSet {
            guard let d = doc else { return }
            if state == nil { buildContent(for: d) }
            canvas.document = d
            canvas.controller = self
            state.document = d
            for o in observers { NotificationCenter.default.removeObserver(o) }
            observers = []
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: GraphDocument.projectChanged, object: d, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.projectChanged() }
            })
            observers.append(nc.addObserver(forName: GraphDocument.selectionChanged, object: d, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.activeGraphChanged() }
            })
            observers.append(nc.addObserver(forName: AppSettings.settingsChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.canvas.needsDisplay = true
                    self?.doc?.plotCache.invalidate()
                }
            })
            canvas.updateSize()
            projectChanged()
            DispatchQueue.main.async { [weak self] in
                self?.zoomToFitIfFirstTime()
                self?.checkMissingData()
            }
        }
    }

    // MARK: - 組み立て

    private func buildContent(for d: GraphDocument) {
        guard let window else { return }
        let state = EditorState(document: d)
        self.state = state
        state.perform = { [weak self] cmd in self?.perform(cmd) }
        state.onSelect = { [weak self] sel in self?.selectionChangedFromPanels(sel) }

        let sidebar = NSHostingController(rootView: SidebarView(state: state))
        sidebar.sizingOptions = []
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 360
        sidebarItem.canCollapse = true

        let center = NSViewController()
        center.view = makeCenterView()
        let centerItem = NSSplitViewItem(viewController: center)
        centerItem.minimumThickness = 360

        let inspector = NSHostingController(rootView: InspectorView(state: state))
        inspector.sizingOptions = []
        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspector)
        inspectorItem.minimumThickness = 280
        inspectorItem.maximumThickness = 420
        inspectorItem.canCollapse = true

        splitController.splitViewItems = [sidebarItem, centerItem, inspectorItem]
        splitController.splitView.autosaveName = "SmaCMainSplit"
        let frame = window.frame
        window.contentViewController = splitController
        window.setFrame(frame, display: false)
        window.setFrameAutosaveName("SmaCDocumentWindow")

        let toolbar = NSToolbar(identifier: "SmaCToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar
        window.makeFirstResponder(canvas)
    }

    private func makeCenterView() -> NSView {
        let container = NSView()
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.2
        scrollView.maxMagnification = 8
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        for v in [scrollView, statusBar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: CanvasStatusBar.height),
        ])
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.magnificationChanged() }
        })
        return container
    }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        displayName
    }

    // MARK: - 書類が変わったとき

    func projectChanged() {
        guard let doc else { return }
        canvas.updateSize()
        canvas.needsDisplay = true
        if let g = doc.activeGraph {
            let ids = Set(g.objects.map(\.id))
            if !canvas.selection.isSubset(of: ids) { canvas.selection = canvas.selection.intersection(ids) }
        } else if !canvas.selection.isEmpty {
            canvas.selection = []
        }
        synchronizeWindowTitleWithDocumentName()
        updateSubtitle()
        refreshToolbar()
        if canvas.mode == .readValue, let rv = canvas.readValue { canvas.setReadValue(series: rv.series, index: rv.index) }
    }

    func activeGraphChanged() {
        canvas.needsDisplay = true
        updateSubtitle()
        refreshToolbar()
        // サイドバー・インスペクタの選択も、選んだグラフに合わせる
        if let gi = doc?.activeGraphIndex, state.selection.graphIndex != gi { state.syncFromCanvas(.graph(gi)) }
    }

    func updateSubtitle() {
        guard let doc, let window else { return }
        if doc.project.graphs.count > 1 {
            window.subtitle = "グラフ \(doc.activeGraphIndex + 1) / \(doc.project.graphs.count)" + (doc.soloGraph != nil ? "(このグラフだけ表示)" : "")
        } else {
            window.subtitle = ""
        }
    }

    // MARK: - 選択の受け渡し(作業面 ⇄ サイドバー・インスペクタ)

    /// サイドバー・インスペクタで選んだとき
    func selectionChangedFromPanels(_ sel: EditorState.Selection) {
        switch sel {
        case .object(_, let id):
            if canvas.selection != [id] { canvas.selection = [id] }
        default:
            if !canvas.selection.isEmpty { canvas.selection = [] }
        }
        if canvas.mode == .readValue, case .series(_, let si) = sel {
            canvas.readSeries = si
            canvas.setReadValue(series: si, index: canvas.readValue?.series == si ? canvas.readValue!.index : 0)
        }
        canvas.needsDisplay = true
        refreshToolbar()
    }

    /// 作業面で文字・図形の選択が変わったとき
    func canvasSelectionChanged() {
        guard let doc else { return }
        let gi = doc.activeGraphIndex
        if let g = doc.activeGraph, let first = g.objects.last(where: { canvas.selection.contains($0.id) }) {
            state.syncFromCanvas(.object(graph: gi, id: first.id))
            showSelectionStatus()
        } else if case .object = state.selection {
            state.syncFromCanvas(.graph(gi))
        }
        refreshToolbar()
    }

    /// 作業面をクリックしたとき(グラフの中をクリックしたら、そのグラフを選ぶ)
    func canvasClicked(_ hit: CanvasView.Hit) {
        guard let gi = hit.graphIndex else { return }
        switch hit {
        case .object, .arrowEnd, .corner:
            break   // canvasSelectionChanged で決まる
        default:
            if case .series(let sg, _) = state.selection, sg == gi { break }
            if state.selection != .graph(gi) { state.syncFromCanvas(.graph(gi)) }
        }
    }

    func canvasDoubleClicked(_ hit: CanvasView.Hit) {
        guard let doc else { return }
        switch hit {
        case .object(let gi, let id), .arrowEnd(let gi, let id, _), .corner(let gi, let id, _):
            if doc.activeGraphIndex != gi { doc.activeGraphIndex = gi }
            canvas.selection = [id]
            showInspector()
        case .axis(let gi, let axis):
            if doc.activeGraphIndex != gi { doc.activeGraphIndex = gi }
            let g = doc.project.graphs[gi]
            var a = axis
            if a == 2 && !g.uIndependent { a = 0 }
            if a == 3 && !g.rIndependent { a = 1 }
            state.axisTab = a
            state.graphTab = 1
            state.select(.graph(gi))
            showInspector()
        case .frame(let gi, _), .inside(let gi):
            if doc.activeGraphIndex != gi { doc.activeGraphIndex = gi }
            state.graphTab = 0
            state.select(.graph(gi))
            showInspector()
        case .none:
            break
        }
    }

    func showInspector() {
        if inspectorItem.isCollapsed { inspectorItem.animator().isCollapsed = false }
    }

    // MARK: - 下の行(座標・説明)

    private var message = ""

    func setStatus(_ s: String) {
        message = s
        statusBar.text = s
    }

    func canvasModeChanged() {
        refreshToolbar()
        switch canvas.mode {
        case .zoomRect: setStatus("表示したい範囲をドラッグで囲んでください。esc でやめます。")
        case .maskRect: setStatus("除きたい点をドラッグで囲んでください。esc でやめます。")
        case .readValue: setStatus("点の近くにポインタを置くと値が出ます。← → で隣の点へ動きます。")
        case .normal: setStatus("")
        }
    }

    func canvasMouseMoved(page p: CGPoint?) {
        guard let doc, let p else { statusBar.right = ""; return }
        for gi in canvas.graphOrder() {
            let g = doc.project.graphs[gi]
            let local = p.applying(GraphRenderer.graphTransform(g).inverted())
            let fr = GraphRenderer.Frame(g)
            if fr.rect.contains(local) {
                let x = fr.scales[0].value(atFraction: Double(local.x) / fr.width)
                let y = fr.scales[1].value(atFraction: 1 - Double(local.y) / fr.height)
                statusBar.right = "x = \(NumberText.g(x))   y = \(NumberText.g(y))"
                return
            }
        }
        statusBar.right = String(format: "%.1f mm, %.1f mm", p.x / 100, p.y / 100)
    }

    func canvasRectChanged(_ r: CGRect?, purpose: CanvasView.RectPurpose) {
        guard let r, purpose != .select, let g = doc?.activeGraph else { return }
        let t = GraphRenderer.graphTransform(g).inverted()
        let a = CGPoint(x: r.minX, y: r.minY).applying(t), b = CGPoint(x: r.maxX, y: r.maxY).applying(t)
        let fr = GraphRenderer.Frame(g)
        let x0 = fr.scales[0].value(atFraction: Double(a.x) / fr.width), x1 = fr.scales[0].value(atFraction: Double(b.x) / fr.width)
        let y0 = fr.scales[1].value(atFraction: 1 - Double(b.y) / fr.height), y1 = fr.scales[1].value(atFraction: 1 - Double(a.y) / fr.height)
        statusBar.right = "x: \(NumberText.g(x0)) 〜 \(NumberText.g(x1))   y: \(NumberText.g(y0)) 〜 \(NumberText.g(y1))"
    }

    func canvasGraphDragged(graph gi: Int) {
        guard let doc, gi < doc.project.graphs.count else { return }
        let g = doc.project.graphs[gi]
        statusBar.right = String(format: "左 %.1f mm  上 %.1f mm   %.1f × %.1f mm", Double(g.left) / 100, Double(g.top) / 100,
                                 Double(g.width) * g.zoomFactor / 100, Double(g.height) * g.zoomFactor / 100)
    }

    func showSelectionStatus() {
        guard let doc, let g = doc.activeGraph else { return }
        let items = g.objects.filter { canvas.selection.contains($0.id) }
        guard let first = items.first else { return }
        setStatus(items.count > 1 ? "\(first.object.displayTitle) ほか \(items.count - 1) 個を選んでいます" : "")
    }

    func readValueChanged() {
        guard let doc, let rv = canvas.readValue, rv.graph < doc.project.graphs.count,
              rv.series < doc.project.graphs[rv.graph].series.count else { return }
        let s = doc.project.graphs[rv.graph].series[rv.series]
        setStatus("\(s.displayName)  #\(rv.index + 1)   X = \(NumberText.g(rv.x))   Y = \(NumberText.g(rv.y))")
    }

    // MARK: - 拡大・縮小

    func magnificationChanged() {
        canvas.needsDisplay = true
        refreshZoomButton()
    }

    func setMagnification(_ m: CGFloat, centeredAt p: CGPoint? = nil) {
        let m = max(scrollView.minMagnification, min(scrollView.maxMagnification, m))
        let center = p ?? CGPoint(x: scrollView.contentView.bounds.midX, y: scrollView.contentView.bounds.midY)
        scrollView.setMagnification(m, centeredAt: center)
        magnificationChanged()
    }

    func zoomToFit() {
        scrollView.layoutSubtreeIfNeeded()
        let r = canvas.viewRect(canvas.paperRect).insetBy(dx: -16, dy: -16)
        scrollView.magnify(toFit: r)
        if scrollView.magnification > 2 { setMagnification(2) }
        magnificationChanged()
    }

    private func zoomToFitIfFirstTime() {
        guard !didFitOnce else { return }
        didFitOnce = true
        zoomToFit()
    }

    func refreshZoomButton() {
        guard let b = zoomButton else { return }
        b.item(at: 0)?.title = "\(Int((scrollView.magnification * 100).rounded()))%"
    }

    // MARK: - 窓

    func windowWillClose(_ notification: Notification) {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshToolbar()
    }

    /// SMP にデータが入っておらず、元のファイルも見つからない系列があれば知らせる
    func checkMissingData() {
        guard !SnapshotRunner.isActive, !SelfTestRunner.isActive, let doc, let window else { return }
        let missing = doc.project.graphs.flatMap { g in
            g.series.filter { $0.kind != .function && doc.project.dataFile(named: $0.name) == nil }
        }
        guard !missing.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "見つからないデータファイルがあります"
        let names = missing.prefix(8).map { "・" + ($0.path.isEmpty ? $0.name : ($0.path.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent) }
        alert.informativeText = names.joined(separator: "\n") + (missing.count > 8 ? "\nほか \(missing.count - 8) 個" : "")
            + "\n\nデータファイルのあるフォルダを選ぶと、読み込みます。"
        alert.addButton(withTitle: "フォルダを選ぶ…")
        alert.addButton(withTitle: "あとで")
        alert.beginSheetModal(for: window) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self, let window = self.window else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.message = "データファイルのあるフォルダを選んでください。"
            panel.beginSheetModal(for: window) { r in
                guard r == .OK, let dir = panel.url, let doc = self.doc else { return }
                var p = doc.project
                GraphDocument.loadMissingData(&p, baseURL: dir)
                let found = p.dataFiles.count - doc.project.dataFiles.count
                doc.update("データファイルの読み込み") { $0 = p }
                self.setStatus(found > 0 ? "\(found) 個のデータファイルを読み込みました。" : "そのフォルダには見つかりませんでした。")
            }
        }
    }
}

/// 作業面の下の 1 行(左に説明、右に座標)
@MainActor
final class CanvasStatusBar: NSView {
    static let height: CGFloat = 24
    private let left = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        for l in [left, rightLabel] {
            l.font = .systemFont(ofSize: 11)
            l.textColor = .secondaryLabelColor
            l.lineBreakMode = .byTruncatingTail
            l.translatesAutoresizingMaskIntoConstraints = false
            addSubview(l)
        }
        rightLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        rightLabel.alignment = .right
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rightLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightLabel.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: 12),
        ])
        left.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rightLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }

    convenience init() { self.init(frame: .zero) }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    override var isFlipped: Bool { false }

    var text: String {
        get { left.stringValue }
        set { left.stringValue = newValue }
    }

    var right: String {
        get { rightLabel.stringValue }
        set { rightLabel.stringValue = newValue }
    }
}
