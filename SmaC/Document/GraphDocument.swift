import AppKit
import UniformTypeIdentifiers
import SMPKit

/// 1 つの SMP ファイル(複数のグラフを持てる)
final class GraphDocument: NSDocument {
    nonisolated static let smpType = "io.github.yushun0825.smac.smp"
    nonisolated static let dataType = "io.github.yushun0825.smac.data"

    private(set) var project = SMPProject()
    /// 選択中のグラフ
    var activeGraphIndex = 0 {
        didSet { NotificationCenter.default.post(name: GraphDocument.selectionChanged, object: self) }
    }
    /// データファイルから作ったときの名前(保存の既定名に使う)
    var suggestedBaseName: String?
    /// グラフの個別表示(nil なら全表示)
    var soloGraph: Int?

    static let projectChanged = Notification.Name("SmaCProjectChanged")
    static let selectionChanged = Notification.Name("SmaCSelectionChanged")

    let plotCache = PlotCache()
    /// project が変わるたびに増える番号(描画の計算を使い回すため)
    private(set) var revision = 0
    /// データファイルの中身が変わるたびに増える番号
    private(set) var dataRevision = 0

    override init() {
        super.init()
        hasUndoManager = true
    }

    override class var autosavesInPlace: Bool { false }
    override class var readableTypes: [String] { [smpType, dataType, UTType.commaSeparatedText.identifier, UTType.tabSeparatedText.identifier, UTType.plainText.identifier] }
    override class var writableTypes: [String] { [smpType] }
    override class func isNativeType(_ type: String) -> Bool { type == smpType }
    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] { [GraphDocument.smpType] }
    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? { "SMP" }

    override func makeWindowControllers() {
        addWindowController(GraphWindowController())
    }

    override var displayName: String! {
        get {
            if fileURL == nil, let n = suggestedBaseName { return n }
            return super.displayName
        }
        set { super.displayName = newValue }
    }

    // MARK: - 読み書き

    override func read(from url: URL, ofType typeName: String) throws {
        let data = try Data(contentsOf: url)
        // NSDocument は書類をメインスレッドで読む(canConcurrentlyReadDocuments は false のまま)
        try MainActor.assumeIsolated {
            if typeName == GraphDocument.smpType || ["smp", "sma"].contains(url.pathExtension.lowercased()) {
                var p = try SMPReader.read(data: data, fileName: url.lastPathComponent)
                GraphDocument.loadMissingData(&p, baseURL: url.deletingLastPathComponent())
                project = p
            } else {
                project = DataImport.project(fromDataFile: url.lastPathComponent, path: url.path, contents: data,
                                             base: AppSettings.shared.defaultGraph(),
                                             preferences: AppSettings.shared.dataOpenPreferences)
            }
            activeGraphIndex = 0
            revision += 1
            dataRevision += 1
            plotCache.invalidate()
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        MainActor.assumeIsolated { makeData() }
    }

    private func makeData() -> Data {
        var p = project
        let (saveData, omit) = (AppSettings.shared.saveDataWithGraph, AppSettings.shared.omitPathInSameFolder)
        let dir = fileURL?.deletingLastPathComponent().path
        for i in p.graphs.indices {
            p.graphs[i].page.saveData = saveData
            if let url = fileURL { p.graphs[i].name = p.graphs.count == 1 ? url.lastPathComponent : p.graphs[i].name }
            if omit, let dir {
                for j in p.graphs[i].series.indices {
                    let path = p.graphs[i].series[j].path
                    if (path as NSString).deletingLastPathComponent == dir {
                        p.graphs[i].series[j].path = (path as NSString).lastPathComponent
                    }
                }
            }
        }
        return SMPWriter.data(for: p)
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        if fileURL == nil {
            let n = suggestedBaseName ?? (project.graphs.first?.name ?? "Untitled.SMP")
            savePanel.nameFieldStringValue = (n as NSString).deletingPathExtension + ".SMP"
        }
        savePanel.allowsOtherFileTypes = false
        savePanel.isExtensionHidden = false
        // 保存の窓の下に「データも一緒に保存する」
        savePanel.accessoryView = SaveAccessory.make()
        return true
    }

    /// SMP に埋め込まれていないデータは、SMP と同じ場所などから探して読む
    static func loadMissingData(_ p: inout SMPProject, baseURL: URL?) {
        for g in p.graphs {
            for s in g.series where s.kind != .function && p.dataFile(named: s.name) == nil {
                for url in candidateURLs(for: s, baseURL: baseURL) {
                    if let data = try? Data(contentsOf: url) {
                        p.setDataFile(DataImport.dataFile(name: s.name, contents: data))
                        break
                    }
                }
            }
        }
    }

    static func candidateURLs(for s: Series, baseURL: URL?) -> [URL] {
        var out: [URL] = []
        let windowsName = s.path.replacingOccurrences(of: "\\", with: "/")
        let base = (windowsName as NSString).lastPathComponent
        if s.path.hasPrefix("/") { out.append(URL(fileURLWithPath: s.path)) }
        if let b = baseURL {
            out.append(b.appendingPathComponent(s.name))
            if !base.isEmpty { out.append(b.appendingPathComponent(base)) }
        }
        return out
    }

    // MARK: - 変更(取り消せるように)

    /// project を変える。取り消し・やり直しの記録もする
    func update(_ actionName: String, _ change: (inout SMPProject) -> Void) {
        let old = project
        var new = project
        change(&new)
        guard new != old else { return }
        setProject(new, actionName: actionName, previous: old)
    }

    func update(graph index: Int? = nil, _ actionName: String, _ change: (inout Graph) -> Void) {
        let gi = index ?? activeGraphIndex
        guard gi >= 0, gi < project.graphs.count else { return }
        update(actionName) { change(&$0.graphs[gi]) }
    }

    private func setProject(_ new: SMPProject, actionName: String, previous: SMPProject) {
        if new.dataFiles != project.dataFiles { dataRevision += 1 }
        project = new
        revision += 1
        if activeGraphIndex >= project.graphs.count { activeGraphIndex = max(project.graphs.count - 1, 0) }
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.setProject(previous, actionName: actionName, previous: new)
            }
        }
        undoManager?.setActionName(actionName)
        NotificationCenter.default.post(name: GraphDocument.projectChanged, object: self)
    }

    /// ドラッグ中など、取り消しの記録をせずに見た目だけ変える
    func preview(_ change: (inout SMPProject) -> Void) {
        let oldData = project.dataFiles
        change(&project)
        revision += 1
        if project.dataFiles != oldData { dataRevision += 1 }
        NotificationCenter.default.post(name: GraphDocument.projectChanged, object: self)
    }

    /// preview で変えたものを、元の値から 1 回の変更として記録する
    func commitPreview(from original: SMPProject, actionName: String) {
        let new = project
        guard new != original else { return }
        project = original
        setProject(new, actionName: actionName, previous: original)
    }

    var activeGraph: Graph? {
        project.graphs.indices.contains(activeGraphIndex) ? project.graphs[activeGraphIndex] : nil
    }

    var fileDisplayName: String { fileURL?.lastPathComponent ?? (suggestedBaseName.map { ($0 as NSString).deletingPathExtension + ".SMP" } ?? "Untitled.SMP") }

    var fileDate: Date {
        (try? fileURL?.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }

    /// 描画に使う系列の値(変わっていないグラフは前の結果を使う)
    func plotData() -> [[SeriesPlotData]] {
        plotCache.data(for: project, revision: revision, dataRevision: dataRevision)
    }

    func renderer(visibleOnly: Bool = true) -> GraphRenderer {
        var opts = AppSettings.shared.renderOptions(fileName: fileDisplayName, fileDate: fileDate)
        if visibleOnly, let solo = soloGraph, solo < project.graphs.count { opts.visibleGraphs = [solo] }
        let resolve = pictureResolver()
        opts.pictureProvider = { path in resolve(path) }
        return GraphRenderer(project: project, options: opts, plotData: plotData())
    }

    // MARK: - 図(BMP・PNG など)

    private static let pictureCache = PictureCache()

    /// 図のファイルを探して読む(フルパス → SMP と同じフォルダ → Windows のパスの名前だけ)
    func pictureResolver() -> @Sendable (String) -> CGImage? {
        let base = fileURL?.deletingLastPathComponent()
        let cache = GraphDocument.pictureCache
        return { path in
            var candidates: [URL] = []
            if path.hasPrefix("/") { candidates.append(URL(fileURLWithPath: path)) }
            let name = (path.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
            if let base {
                candidates.append(base.appendingPathComponent(path))
                candidates.append(base.appendingPathComponent(name))
            }
            for url in candidates where FileManager.default.fileExists(atPath: url.path) {
                if let img = cache.image(url) { return img }
            }
            return nil
        }
    }

    // MARK: - データファイルの読み直し(エディタで直したとき・再描画)

    private var dataFileDates: [String: Date] = [:]

    func noteDataFileDate(_ name: String, url: URL) {
        dataFileDates[SMPProject.key(name)] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    func reloadChangedDataFiles(force: Bool) {
        var p = project
        var changed = false
        for g in p.graphs {
            for s in g.series where s.kind != .function {
                let url = URL(fileURLWithPath: s.path)
                guard s.path.hasPrefix("/"), FileManager.default.fileExists(atPath: url.path),
                      let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
                let key = SMPProject.key(s.name)
                if !force, let known = dataFileDates[key], known >= date { continue }
                if !force && dataFileDates[key] == nil { dataFileDates[key] = date; continue }
                guard let data = try? Data(contentsOf: url) else { continue }
                let file = DataImport.dataFile(name: s.name, contents: data, timestamp: SMPWriter.timestamp(date))
                if p.dataFile(named: s.name)?.lines != file.lines {
                    p.setDataFile(file)
                    changed = true
                }
                dataFileDates[key] = date
            }
        }
        if changed {
            for gi in p.graphs.indices {
                for si in p.graphs[gi].series.indices {
                    if let f = p.dataFile(named: p.graphs[gi].series[si].name) {
                        p.graphs[gi].series[si].linesRead = DataParser.rows(for: p.graphs[gi].series[si], lines: f.lines).count
                    }
                }
            }
            update("データファイルの読み直し") { $0 = p }
        } else if force {
            plotCache.invalidate()
            NotificationCenter.default.post(name: GraphDocument.projectChanged, object: self)
        }
    }

    // MARK: - 印刷

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo.copy() as! NSPrintInfo
        if let g = project.graphs.first {
            info.orientation = g.page.landscape ? .landscape : .portrait
        }
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.leftMargin = 0; info.rightMargin = 0; info.topMargin = 0; info.bottomMargin = 0
        let view = PrintView(renderer: renderer(), paper: info.paperSize)
        view.scale = Double(project.graphs.first?.page.tail.first ?? 100) / 100
        if AppSettings.shared.printFooter {
            let f = DateFormatter()
            f.dateFormat = "yyyy-M-d H:mm:ss"
            view.footer = "[\(fileDisplayName)] \(f.string(from: Date()))"
        }
        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        return op
    }
}

/// グラフごとの系列の計算結果を覚えておく(文字を動かしただけなら計算し直さない)
final class PlotCache: @unchecked Sendable {
    private var keys: [Int] = []
    private var values: [[SeriesPlotData]] = []
    private var lastRevision = -1

    func invalidate() { keys = []; values = []; lastRevision = -1 }

    func data(for project: SMPProject, revision: Int, dataRevision: Int) -> [[SeriesPlotData]] {
        if revision == lastRevision && values.count == project.graphs.count { return values }
        var newKeys: [Int] = []
        var newValues: [[SeriesPlotData]] = []
        for g in project.graphs {
            var h = Hasher()
            h.combine(g.series)
            h.combine(g.axes)
            h.combine(g.constants)
            h.combine(g.frameType)
            h.combine(g.masks)
            h.combine(dataRevision)
            let key = h.finalize()
            if let j = keys.firstIndex(of: key), j < values.count {
                newValues.append(values[j])
            } else {
                newValues.append(SeriesEvaluator.evaluate(graph: g, project: project))
            }
            newKeys.append(key)
        }
        keys = newKeys
        values = newValues
        lastRevision = revision
        return values
    }
}

/// 印刷用の 1 ページ(用紙の左上を原点に、実寸で描く)
final class PrintView: NSView {
    let renderer: GraphRenderer
    var scale: Double = 1
    var background: SMPColor?
    var footer: String?

    init(renderer: GraphRenderer, paper: NSSize) {
        self.renderer = renderer
        super.init(frame: NSRect(origin: .zero, size: paper))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if let bg = background {
            bg.nsColor.setFill()
            bounds.fill()
        }
        ctx.saveGState()
        let k = CGFloat(Units.pointsPerHundredthMM) * CGFloat(scale)
        ctx.scaleBy(x: k, y: k)
        renderer.draw(in: ctx)
        ctx.restoreGState()
        if let footer {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.black]
            (footer as NSString).draw(at: NSPoint(x: 28, y: bounds.height - 24), withAttributes: attrs)
        }
    }
}


/// 図の画像の読み込みを覚えておく
final class PictureCache: @unchecked Sendable {
    private var images: [URL: (Date?, CGImage)] = [:]
    private let lock = NSLock()

    func image(_ url: URL) -> CGImage? {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        lock.lock(); defer { lock.unlock() }
        if let c = images[url], c.0 == date { return c.1 }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) ?? pdfImage(url) else { return nil }
        images[url] = (date, img)
        return img
    }

    private func pdfImage(_ url: URL) -> CGImage? {
        guard let doc = CGPDFDocument(url as CFURL), let page = doc.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 4
        guard let ctx = CGContext(data: nil, width: Int(box.width * scale), height: Int(box.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }
}
