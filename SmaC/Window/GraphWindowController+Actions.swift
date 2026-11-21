import AppKit
import UniformTypeIdentifiers
import SMPKit

/// メニュー・ツールバー・作業面から呼ぶ操作(ファイル・編集・表示・挿入・グラフ・データ)
extension GraphWindowController {
    static let objectPasteboardType = NSPasteboard.PasteboardType("io.github.yushun0825.smac.objects")
    /// SMP に入れられる数(多すぎると他のソフトで開けなくなるため)
    static let maxGraphs = 50
    static let maxSeries = 40

    var gi: Int { doc?.activeGraphIndex ?? 0 }

    // MARK: - 知らせる・確かめる

    func alert(_ title: String, _ text: String = "", style: NSAlert.Style = .warning) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = style
        if let window, !SelfTestRunner.isActive { a.beginSheetModal(for: window) } else { print("alert: \(title) \(text)") }
    }

    func confirm(_ title: String, _ text: String, ok: String, destructive: Bool = false, _ then: @escaping () -> Void) {
        guard let window else { return }
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        let b = a.addButton(withTitle: ok)
        b.hasDestructiveAction = destructive
        a.addButton(withTitle: "キャンセル")
        a.beginSheetModal(for: window) { r in
            if r == .alertFirstButtonReturn { then() }
        }
    }

    /// 操作の相手の系列: サイドバーで選んでいればそれ、1 つしかなければそれ、ほかは選んでもらう
    func withSeries(_ title: String, where filter: @escaping (Series) -> Bool = { _ in true }, _ body: @escaping (Int) -> Void) {
        guard let doc, let g = doc.activeGraph, let window else { return }
        if case .series(let sg, let si) = state.selection, sg == gi, si < g.series.count, filter(g.series[si]) {
            body(si)
            return
        }
        let indices = g.series.indices.filter { filter(g.series[$0]) }
        guard !indices.isEmpty else {
            alert("使えるデータがありません", g.series.isEmpty ? "先に「データを追加」でデータファイルを開いてください。" : "")
            return
        }
        if indices.count == 1 { body(indices[0]); return }
        Sheets.chooseSeries(title: title, message: "", items: indices.map { g.series[$0] }, multiple: false,
                            preselected: IndexSet(integer: 0), over: window) { sel in
            if let k = sel.first, k < indices.count { body(indices[k]) }
        }
    }

    func selectSeries(_ si: Int, tab: Int? = nil) {
        if let tab { state.seriesTab = tab }
        state.select(.series(graph: gi, index: si))
    }

    func selectObject(_ id: UUID) {
        canvas.selection = [id]
        state.select(.object(graph: gi, id: id))
    }

    // MARK: - ファイル

    /// グラフの読み込み: SMP のグラフをこの書類に足す
    @objc func importGraphs(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(exportedAs: GraphDocument.smpType)]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = true
        panel.message = "この書類に加えるグラフ(SMP ファイル)を選んでください。"
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let self else { return }
            for url in panel.urls { self.loadGraphFile(url) }
        }
    }

    func loadGraphFile(_ url: URL) {
        guard let doc else { return }
        do {
            var p = try SMPReader.read(data: Data(contentsOf: url), fileName: url.lastPathComponent)
            GraphDocument.loadMissingData(&p, baseURL: url.deletingLastPathComponent())
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            doc.update("グラフの読み込み") { proj in
                for (_, var file) in p.dataFiles {
                    let name = DataImport.uniqueName(file.name, contents: file, in: proj)
                    if name != file.name {
                        for gIndex in p.graphs.indices {
                            for sIndex in p.graphs[gIndex].series.indices
                            where SMPProject.key(p.graphs[gIndex].series[sIndex].name) == SMPProject.key(file.name) {
                                p.graphs[gIndex].series[sIndex].name = name
                            }
                        }
                        file.name = name
                    }
                    proj.setDataFile(file)
                }
                proj.graphs.append(contentsOf: p.graphs.prefix(max(GraphWindowController.maxGraphs - proj.graphs.count, 0)))
            }
            doc.activeGraphIndex = doc.project.graphs.count - 1
            state.select(.graph(doc.activeGraphIndex))
            checkMissingData()
        } catch {
            alert("グラフを読み込めませんでした", "\(url.lastPathComponent)\n\(error.localizedDescription)")
        }
    }

    /// このグラフだけを SMP にする
    @objc func saveActiveGraphAs(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, let window else { return }
        let panel = NSSavePanel()
        let base = (g.name as NSString).deletingPathExtension
        panel.nameFieldStringValue = (base.isEmpty ? "Graph" : base) + ".SMP"
        panel.allowedContentTypes = [UTType(exportedAs: GraphDocument.smpType)]
        panel.accessoryView = SaveAccessory.make()
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let url = panel.url, let self else { return }
            var p = SMPProject()
            var single = g
            single.name = url.lastPathComponent
            single.page.saveData = AppSettings.shared.saveDataWithGraph
            p.graphs = [single]
            for s in g.series { if let f = doc.project.dataFile(named: s.name) { p.setDataFile(f) } }
            do {
                try SMPWriter.data(for: p).write(to: url)
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch {
                self.alert("保存できませんでした", error.localizedDescription)
            }
        }
    }

    @objc func saveAsDefaultGraph(_ sender: Any?) {
        guard let g = doc?.activeGraph else { return }
        do {
            try AppSettings.shared.saveAsDefault(g)
            setStatus("このグラフの枠・軸・文字を、新しいグラフの元にしました。")
        } catch {
            alert("保存できませんでした", error.localizedDescription)
        }
    }

    /// 用紙(大きさ・向き・印刷の倍率)
    @objc func paperSetup(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, let window else { return }
        Sheets.paper(g.page, over: window) { [weak self] page in
            doc.update("用紙の設定") { p in
                for i in p.graphs.indices {
                    let keep = p.graphs[i].page.saveData
                    p.graphs[i].page = page
                    p.graphs[i].page.saveData = keep
                }
            }
            self?.canvas.updateSize()
            self?.zoomToFit()
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let (r, rect) = exportRenderer(), let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportBaseName() + ".pdf"
        panel.allowedContentTypes = [.pdf]
        panel.beginSheetModal(for: window) { [weak self] res in
            guard res == .OK, let url = panel.url else { return }
            do { try GraphExporter.pdfData(renderer: r, rect: rect).write(to: url) }
            catch { self?.alert("書き出せませんでした", error.localizedDescription) }
        }
    }

    @objc func exportPNG(_ sender: Any?) {
        guard let (r, rect) = exportRenderer(), let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportBaseName() + ".png"
        panel.allowedContentTypes = [.png]
        let dpi = AppSettings.shared.exportDPI
        panel.beginSheetModal(for: window) { [weak self] res in
            guard res == .OK, let url = panel.url else { return }
            guard let data = GraphExporter.pngData(renderer: r, rect: rect, dpi: dpi) else {
                self?.alert("書き出せませんでした"); return
            }
            do { try data.write(to: url) } catch { self?.alert("書き出せませんでした", error.localizedDescription) }
        }
    }

    func exportBaseName() -> String {
        guard let doc else { return "Graph" }
        return (doc.fileDisplayName as NSString).deletingPathExtension
    }

    /// 書き出す範囲(描いたもの全体 + 余白)
    func exportRenderer(margin: Double? = nil) -> (GraphRenderer, CGRect)? {
        guard let doc else { return nil }
        let r = doc.renderer()
        let m = (margin ?? AppSettings.shared.copyMarginMM) * 100
        let rect = r.contentBounds().insetBy(dx: -m, dy: -m)
        return (r, rect)
    }

    /// 変換したあとの値をファイルにする(TAB かカンマ区切り)
    @objc func exportValues(_ sender: Any?) {
        withSeries("書き出すデータ") { [weak self] si in
            guard let self, let doc = self.doc, let window = self.window else { return }
            let g = doc.project.graphs[self.gi]
            let data = doc.plotData()[self.gi][si]
            let tab = AppSettings.shared.exportSeparatorTab
            let panel = NSSavePanel()
            panel.nameFieldStringValue = (g.series[si].name as NSString).deletingPathExtension + (tab ? ".txt" : ".csv")
            panel.beginSheetModal(for: window) { res in
                guard res == .OK, let url = panel.url else { return }
                let text = GraphWindowController.valuesText(x: data.x, y: data.y, separator: tab ? "\t" : ",")
                do { try text.data(using: .utf8)?.write(to: url) } catch { self.alert("書き出せませんでした", error.localizedDescription) }
            }
        }
    }

    static func valuesText(x: [Double], y: [Double], separator: String) -> String {
        var out = ""
        for i in 0..<min(x.count, y.count) where x[i].isFinite && y[i].isFinite {
            out += NumberText.export(x[i]) + separator + NumberText.export(y[i]) + "\n"
        }
        return out
    }

    // MARK: - 編集

    func selectedItems() -> [ObjectItem] {
        guard let g = doc?.activeGraph else { return [] }
        return g.objects.filter { canvas.selection.contains($0.id) }
    }

    func selectedTexts() -> [ObjectItem] {
        selectedItems().filter { if case .text = $0.object { return true } else { return false } }
    }

    /// コピー: 文字・図形を選んでいればそれを、なければ図として
    @objc func copy(_ sender: Any?) {
        if canvas.mode == .readValue, let rv = canvas.readValue {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(NumberText.g(rv.x) + "\t" + NumberText.g(rv.y), forType: .string)
            setStatus("点の値をコピーしました。")
            return
        }
        if selectedItems().isEmpty { copyAsImage(sender) } else { copyObjects() }
    }

    func copyObjects() {
        let items = selectedItems()
        guard !items.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(SMPWriter.legendLines(items.map(\.object)).joined(separator: "\n"), forType: GraphWindowController.objectPasteboardType)
        let plain = items.compactMap { item -> String? in
            if case .text(let t) = item.object { return RichTextParser.plainText(t.text).replacingOccurrences(of: "\\n", with: "\n") }
            return nil
        }
        if !plain.isEmpty { pb.setString(plain.joined(separator: "\n"), forType: .string) }
    }

    @objc func cut(_ sender: Any?) {
        guard !selectedItems().isEmpty else { return }
        copyObjects()
        delete(sender)
    }

    @objc func paste(_ sender: Any?) {
        guard let doc else { return }
        let pb = NSPasteboard.general
        if let s = pb.string(forType: GraphWindowController.objectPasteboardType) {
            let objects = SMPReader.legendObjects(lines: s.components(separatedBy: "\n"))
            guard !objects.isEmpty else { return }
            let items = objects.map { ObjectItem(offset($0, by: 300)) }
            doc.update(graph: gi, "ペースト") { $0.objects.append(contentsOf: items) }
            canvas.selection = Set(items.map(\.id))
            return
        }
        if let text = pb.string(forType: .string), !text.isEmpty {
            insertText(kind: .other, text: text)
        }
    }

    func offset(_ o: GraphObject, by d: Int) -> GraphObject {
        switch o {
        case .text(var t): t.x += d; t.y += d; return .text(t)
        case .dot(var p): p.x += d; p.y += d; return .dot(p)
        case .shape(var s):
            if s.xReference == 0 { s.x1 += Double(d) / 100; s.x2 += Double(d) / 100 }
            if s.yReference == 0 { s.y1 += Double(d) / 100; s.y2 += Double(d) / 100 }
            return .shape(s)
        case .picture(var p):
            p.shape.x1 += Double(d) / 100; p.shape.x2 += Double(d) / 100
            p.shape.y1 += Double(d) / 100; p.shape.y2 += Double(d) / 100
            return .picture(p)
        case .raw: return o
        }
    }

    /// 削除: 選んだ文字・図形。サイドバーでデータを選んでいればそのデータ
    @objc func delete(_ sender: Any?) {
        guard let doc else { return }
        if !canvas.selection.isEmpty {
            let ids = canvas.selection
            doc.update(graph: gi, "削除") { $0.objects.removeAll { ids.contains($0.id) } }
            canvas.selection = []
            return
        }
        switch state.selection {
        case .series(let g, let si) where g == gi:
            removeSeries(at: si)
        case .graph(let g) where g == gi && doc.project.graphs.count > 1:
            deleteGraph(sender)
        default:
            NSSound.beep()
        }
    }

    @objc override func selectAll(_ sender: Any?) {
        guard let g = doc?.activeGraph else { return }
        canvas.selection = Set(g.objects.map(\.id))
    }

    @objc func bringToFront(_ sender: Any?) {
        guard let doc, !canvas.selection.isEmpty else { return }
        let ids = canvas.selection
        doc.update(graph: gi, "最前面へ") { g in
            let moving = g.objects.filter { ids.contains($0.id) }
            g.objects.removeAll { ids.contains($0.id) }
            g.objects.append(contentsOf: moving)
        }
    }

    @objc func sendToBack(_ sender: Any?) {
        guard let doc, !canvas.selection.isEmpty else { return }
        let ids = canvas.selection
        doc.update(graph: gi, "最背面へ") { g in
            let moving = g.objects.filter { ids.contains($0.id) }
            g.objects.removeAll { ids.contains($0.id) }
            g.objects.insert(contentsOf: moving, at: 0)
        }
    }

    /// 文字をそろえる(tag 0:左 1:中央 2:右)
    @objc func alignTexts(_ sender: Any?) {
        guard let doc else { return }
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        let renderer = doc.renderer()
        let env = renderer.environment(for: gi)
        let items = selectedTexts()
        guard items.count >= 2 else { return }
        var spans: [UUID: (CGFloat, CGFloat)] = [:]
        for item in items {
            if case .text(let t) = item.object {
                let w = renderer.textLayout(t, env: env).bounds.width
                spans[item.id] = (CGFloat(t.x), CGFloat(t.x) + w)
            }
        }
        let lefts = spans.values.map(\.0), rights = spans.values.map(\.1)
        let target: CGFloat
        switch tag {
        case 1: target = ((lefts.min() ?? 0) + (rights.max() ?? 0)) / 2
        case 2: target = rights.max() ?? 0
        default: target = lefts.min() ?? 0
        }
        doc.update(graph: gi, "文字の位置をそろえる") { graph in
            for (k, item) in graph.objects.enumerated() {
                guard let span = spans[item.id], case .text(var t) = item.object else { continue }
                let w = span.1 - span.0
                switch tag {
                case 1: t.x = Int(target - w / 2)
                case 2: t.x = Int(target - w)
                default: t.x = Int(target)
                }
                graph.objects[k].object = .text(t)
            }
        }
    }

    /// 図としてコピー(PDF と PNG をクリップボードへ)
    @objc func copyAsImage(_ sender: Any?) {
        guard let (r, rect) = exportRenderer() else { return }
        putFigureOnPasteboard(renderer: r, rect: rect)
    }

    /// 余白・倍率・解像度を決めてコピー
    @objc func copyWithOptions(_ sender: Any?) {
        guard let window else { return }
        Sheets.copyOptions(over: window) { [weak self] margin, scale, dpi in
            guard let self, let (r, rect) = self.exportRenderer(margin: margin) else { return }
            self.putFigureOnPasteboard(renderer: r, rect: rect, scale: scale / 100, dpi: dpi)
        }
    }

    func putFigureOnPasteboard(renderer r: GraphRenderer, rect: CGRect, scale: Double = 1, dpi: Double? = nil) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(GraphExporter.pdfData(renderer: r, rect: rect, scale: scale), forType: .pdf)
        if let png = GraphExporter.pngData(renderer: r, rect: rect, dpi: (dpi ?? AppSettings.shared.exportDPI) * scale) {
            pb.setData(png, forType: .png)
        }
        setStatus("図をクリップボードにコピーしました。")
    }

    /// 変換したあとの値 (x, y) をクリップボードへ
    @objc func copyValues(_ sender: Any?) {
        withSeries("コピーするデータ") { [weak self] si in self?.copyValues(series: si) }
    }

    func copyValues(series si: Int) {
        guard let doc else { return }
        let data = doc.plotData()
        guard gi < data.count, si < data[gi].count else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(GraphWindowController.valuesText(x: data[gi][si].x, y: data[gi][si].y, separator: "\t"), forType: .string)
        setStatus("\(data[gi][si].finitePoints.count) 点の値をコピーしました。")
    }

    /// クリップボードの文字(数の並び)を新しいデータにする
    @objc func pasteAsData(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            alert("クリップボードに文字がありません"); return
        }
        addEmbeddedData(text: text, baseName: "CLIPBOARD", actionName: "クリップボードの値をデータにする")
    }

    /// SMP の中にだけあるデータを足す(ファイルは作らない)
    func addEmbeddedData(text: String, baseName: String, actionName: String) {
        guard let doc else { return }
        guard doc.activeGraph?.series.count ?? 0 < GraphWindowController.maxSeries else {
            alert("これ以上データを加えられません", "1 つのグラフに入れられるデータは \(GraphWindowController.maxSeries) 個までです。"); return
        }
        var name = baseName + ".DAT"
        var k = 1
        while doc.project.dataFile(named: name) != nil { k += 1; name = "\(baseName)\(k).DAT" }
        let file = DataImport.dataFile(name: name, contents: Data(text.utf8), timestamp: SMPWriter.timestamp(Date()))
        let graphIndex = gi
        var proj = doc.project
        proj.setDataFile(file)
        let index = proj.graphs[graphIndex].series.count
        let wasEmpty = proj.graphs[graphIndex].series.isEmpty
        var s = DataImport.newSeries(name: name, path: name, index: index, preferences: AppSettings.shared.dataOpenPreferences,
                                     previous: proj.graphs[graphIndex].series.last)
        DataImport.guessColumns(file, series: &s)
        s.linesRead = DataParser.rows(for: s, lines: file.lines).count
        proj.graphs[graphIndex].series.append(s)
        let prefs = AppSettings.shared.dataOpenPreferences
        var axes: [Int] = []
        if prefs.autoScaleX || wasEmpty { axes.append(0) }
        if prefs.autoScaleY || wasEmpty { axes.append(1) }
        GraphOps.clearScale(&proj, graphIndex: graphIndex, axes: axes)
        proj.graphs[graphIndex].syncCommonAxes()
        let final = proj
        doc.update(actionName) { $0 = final }
        selectSeries(index, tab: 0)
    }

    // MARK: - 表示

    @objc func zoomIn(_ sender: Any?) { setMagnification(scrollView.magnification * 1.25) }
    @objc func zoomOut(_ sender: Any?) { setMagnification(scrollView.magnification / 1.25) }
    @objc func zoomActualSize(_ sender: Any?) { setMagnification(1) }
    @objc func zoomToFitPage(_ sender: Any?) { zoomToFit() }

    @objc func showAllGraphs(_ sender: Any?) {
        doc?.soloGraph = nil
        canvas.needsDisplay = true
        updateSubtitle()
    }

    @objc func showActiveGraphOnly(_ sender: Any?) {
        guard let doc else { return }
        doc.soloGraph = doc.soloGraph == nil ? doc.activeGraphIndex : nil
        canvas.selection = []
        canvas.needsDisplay = true
        updateSubtitle()
    }

    @objc func toggleGrid(_ sender: Any?) {
        AppSettings.shared.gridMM = AppSettings.shared.gridMM > 0 ? 0 : 10
    }

    /// データファイルを読み直して描き直す(ほかのアプリでデータを直したとき)
    @objc func reloadData(_ sender: Any?) {
        doc?.reloadChangedDataFiles(force: true)
        canvas.needsDisplay = true
        setStatus("データファイルを読み直しました。")
    }

    // MARK: - 挿入

    func newText(kind: TextObject.Kind, graph g: Graph) -> TextObject {
        var t = TextObject()
        t.kind = kind
        t.latinFont = LogFont.latinDefault(points: 24)
        t.japaneseFont = LogFont.japaneseDefault(points: 24)
        t.symbolFont = LogFont.symbolDefault(points: 24)
        switch kind {
        case .xTitle: t.x = g.width / 2 - 1500; t.y = g.height + 1600
        case .yTitle: t.x = -1300; t.y = g.height / 2 + 2000; t.angle = 90
        case .uTitle: t.x = g.width / 2 - 1500; t.y = -1200
        case .rTitle: t.x = g.width + 2200; t.y = g.height / 2 + 2000; t.angle = 90
        case .other: t.x = g.width / 2 - 1500; t.y = g.height / 2
        }
        return t
    }

    @objc func insertTextBox(_ sender: Any?) {
        insertText(kind: .other, text: "文字")
    }

    /// 軸の題(tag 4:X 5:Y 6:上 7:右)。もうあれば、それを選ぶ
    @objc func insertAxisTitle(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 4
        let kind = TextObject.Kind(rawValue: tag) ?? .xTitle
        if let g = doc?.activeGraph,
           let item = g.objects.first(where: { if case .text(let t) = $0.object { return t.kind == kind } else { return false } }) {
            selectObject(item.id)
            showInspector()
            return
        }
        let text: String
        switch kind {
        case .xTitle: text = "X"
        case .yTitle: text = "Y"
        case .uTitle: text = "U"
        case .rTitle: text = "R"
        case .other: text = "文字"
        }
        insertText(kind: kind, text: text)
    }

    func insertText(kind: TextObject.Kind, text: String, at local: CGPoint? = nil) {
        guard let doc, let g = doc.activeGraph else { return }
        var t = newText(kind: kind, graph: g)
        t.text = text.replacingOccurrences(of: "\r\n", with: "\\n").replacingOccurrences(of: "\n", with: "\\n")
        if let local { t.x = Int(local.x); t.y = Int(local.y) }
        let item = ObjectItem(.text(t))
        doc.update(graph: gi, kind.displayTitle + "を入れる") { $0.objects.append(item) }
        selectObject(item.id)
        showInspector()
    }

    @objc func insertClipboardText(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            alert("クリップボードに文字がありません"); return
        }
        insertText(kind: .other, text: text)
    }

    /// 凡例: 表示しているデータの見本と名前
    @objc func insertLegend(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, !g.series.isEmpty else { return }
        let indices = g.series.indices.filter { g.series[$0].visible }
        let use = indices.isEmpty ? Array(g.series.indices) : indices
        let curves = use.map { g.series[$0].hasCurve && g.series[$0].dotType == 0 }
        let text = GraphOps.legendText(seriesIndices: use, useCurve: curves)
        var t = newText(kind: .other, graph: g)
        t.text = text
        t.x = g.width - 4500
        t.y = 1500
        t.latinFont = LogFont.latinDefault(points: 18)
        t.japaneseFont = LogFont.japaneseDefault(points: 18)
        t.symbolFont = LogFont.symbolDefault(points: 18)
        let item = ObjectItem(.text(t))
        doc.update(graph: gi, "凡例を入れる") { $0.objects.append(item) }
        selectObject(item.id)
        showInspector()
    }

    /// グラフの中の真ん中あたり(mm)
    private func graphCenterMM() -> CGPoint {
        guard let g = doc?.activeGraph else { return CGPoint(x: 70, y: 50) }
        return CGPoint(x: Double(g.width) / 200, y: Double(g.height) / 200)
    }

    @objc func insertArrow(_ sender: Any?) {
        let c = graphCenterMM()
        var s = ShapeObject()
        s.objectType = 0; s.shapeType = 0
        s.x1 = c.x - 15; s.y1 = c.y + 10; s.x2 = c.x + 5; s.y2 = c.y - 5
        s.length = 400; s.width = 30; s.headMode = 1; s.headOpen = 30; s.headClose = 100
        insertShape(s, "矢印を入れる")
    }

    @objc func insertLine(_ sender: Any?) {
        let c = graphCenterMM()
        var s = ShapeObject()
        s.objectType = 1; s.shapeType = 0
        s.x1 = c.x - 15; s.y1 = c.y; s.x2 = c.x + 15; s.y2 = c.y
        s.length = 400; s.width = 30; s.headMode = 0; s.headOpen = 30; s.headClose = 100
        insertShape(s, "線を入れる")
    }

    @objc func insertBox(_ sender: Any?) {
        let c = graphCenterMM()
        var s = ShapeObject()
        s.objectType = 3; s.shapeType = 3
        s.x1 = c.x - 25; s.y1 = c.y - 10; s.x2 = c.x + 25; s.y2 = c.y + 10
        s.length = 0; s.width = 30
        s.shadowColor = .black
        insertShape(s, "枠を入れる")
    }

    private func insertShape(_ s: ShapeObject, _ action: String) {
        guard let doc else { return }
        let item = ObjectItem(.shape(s))
        doc.update(graph: gi, action) { $0.objects.append(item) }
        selectObject(item.id)
        showInspector()
    }

    @objc func insertDot(_ sender: Any?) {
        guard let doc else { return }
        let c = graphCenterMM()
        var d = DotObject()
        d.x = Int(c.x * 100); d.y = Int(c.y * 100)
        d.dotType = PlotType.defaultCode
        let item = ObjectItem(.dot(d))
        doc.update(graph: gi, "点を入れる") { $0.objects.append(item) }
        selectObject(item.id)
        showInspector()
    }

    static let pictureTypes: [UTType] = [.png, .jpeg, .tiff, .bmp, .gif, .pdf, .heic]

    @objc func insertPicture(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = GraphWindowController.pictureTypes
        panel.message = "グラフに入れる画像を選んでください。"
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let url = panel.url, let self else { return }
            self.insertPicture(url: url, atMM: nil)
        }
    }

    func insertPicture(url: URL, atMM p: CGPoint?) {
        guard let doc else { return }
        var pic = PictureObject(path: url.path)
        pic.shape.objectType = 10
        let c = p ?? graphCenterMM()
        var w = 50.0, h = 35.0
        if let img = doc.pictureResolver()(url.path), img.width > 0 {
            h = w * Double(img.height) / Double(img.width)
            if h > 80 { w *= 80 / h; h = 80 }
        }
        pic.shape.x1 = Double(c.x) - w / 2; pic.shape.y1 = Double(c.y) - h / 2
        pic.shape.x2 = pic.shape.x1 + w; pic.shape.y2 = pic.shape.y1 + h
        let item = ObjectItem(.picture(pic))
        doc.update(graph: gi, "図を入れる") { $0.objects.append(item) }
        selectObject(item.id)
        showInspector()
    }

    func choosePicture(for id: UUID) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = GraphWindowController.pictureTypes
        panel.message = "入れ替える画像を選んでください。"
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let url = panel.url, let self, let doc = self.doc else { return }
            doc.update(graph: self.gi, "図の入れ替え") { g in
                if let k = g.objects.firstIndex(where: { $0.id == id }), case .picture(var p) = g.objects[k].object {
                    p.path = url.path
                    g.objects[k].object = .picture(p)
                }
            }
        }
    }

    // MARK: - グラフ

    @objc func addGraph(_ sender: Any?) {
        guard let doc else { return }
        guard doc.project.graphs.count < GraphWindowController.maxGraphs else {
            alert("これ以上グラフを加えられません", "1 つの書類に入れられるグラフは \(GraphWindowController.maxGraphs) 枚までです。"); return
        }
        var g = AppSettings.shared.defaultGraph()
        g.name = "Graph\(doc.project.graphs.count + 1).SMP"
        if let last = doc.project.graphs.last {
            g.left = last.left + 1000
            g.top = last.top + 1000
            g.page = last.page
        }
        doc.update("グラフを加える") { $0.graphs.append(g) }
        doc.activeGraphIndex = doc.project.graphs.count - 1
        canvas.selection = []
        state.select(.graph(doc.activeGraphIndex))
    }

    @objc func duplicateGraph(_ sender: Any?) {
        guard let doc, var g = doc.activeGraph else { return }
        guard doc.project.graphs.count < GraphWindowController.maxGraphs else {
            alert("これ以上グラフを加えられません", "1 つの書類に入れられるグラフは \(GraphWindowController.maxGraphs) 枚までです。"); return
        }
        g.id = UUID()
        g.objects = g.objects.map { ObjectItem($0.object) }
        for i in g.series.indices { g.series[i].id = UUID() }
        g.left += 1000
        g.top += 1000
        let copy = g
        doc.update("グラフの複製") { $0.graphs.append(copy) }
        doc.activeGraphIndex = doc.project.graphs.count - 1
        state.select(.graph(doc.activeGraphIndex))
    }

    @objc func deleteGraph(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph else { return }
        let i = gi
        let remove = { [weak self] in
            doc.update("グラフの削除") { p in
                p.graphs.remove(at: i)
                if p.graphs.isEmpty {
                    var ng = AppSettings.shared.defaultGraph(); ng.name = "Untitled.SMP"; p.graphs = [ng]
                }
                GraphOps.pruneData(&p)
            }
            doc.soloGraph = nil
            doc.activeGraphIndex = min(i, doc.project.graphs.count - 1)
            self?.state.select(.graph(doc.activeGraphIndex))
        }
        if g.series.isEmpty && g.objects.isEmpty { remove(); return }
        confirm("このグラフを削除しますか?", "グラフの中のデータ・文字・図形も消えます。「取り消す」で戻せます。", ok: "削除", destructive: true, remove)
    }

    @objc func selectGraph(_ sender: NSMenuItem) {
        guard let doc, sender.tag < doc.project.graphs.count else { return }
        doc.activeGraphIndex = sender.tag
        if doc.soloGraph != nil { doc.soloGraph = sender.tag }
        canvas.selection = []
        state.select(.graph(sender.tag))
    }

    /// 全部の軸の範囲をデータに合わせる
    @objc func autoRangeAll(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph else { return }
        var axes = [0, 1]
        if g.uIndependent { axes.append(2) }
        if g.rIndependent { axes.append(3) }
        let graphIndex = gi
        doc.update("範囲を合わせる") { p in
            GraphOps.clearScale(&p, graphIndex: graphIndex, axes: axes)
            p.graphs[graphIndex].syncCommonAxes()
        }
    }

    /// 1 つの軸の範囲をデータに合わせる(tag 0:X 1:Y 2:上 3:右)
    @objc func autoRangeAxis(_ sender: Any?) {
        guard let doc else { return }
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        let graphIndex = gi
        doc.update("範囲を合わせる") { p in
            GraphOps.clearScale(&p, graphIndex: graphIndex, axes: [tag])
            p.graphs[graphIndex].syncCommonAxes()
        }
    }

    @objc func beginZoomRect(_ sender: Any?) {
        canvas.mode = canvas.mode == .zoomRect ? .normal : .zoomRect
    }

    /// 囲んだ範囲を軸の範囲にする
    func applyZoomRect(pageRect r: CGRect) {
        guard let doc, let g = doc.activeGraph else { return }
        let t = GraphRenderer.graphTransform(g).inverted()
        let a = CGPoint(x: r.minX, y: r.minY).applying(t), b = CGPoint(x: r.maxX, y: r.maxY).applying(t)
        let fr = GraphRenderer.Frame(g)
        func hv(_ x: CGFloat, _ axis: Int) -> Double { fr.scales[axis].value(atFraction: Double(x) / fr.width) }
        func vv(_ y: CGFloat, _ axis: Int) -> Double { fr.scales[axis].value(atFraction: 1 - Double(y) / fr.height) }
        let ranges: [(Bool, Double, Double)] = [
            (true, hv(a.x, 0), hv(b.x, 0)),
            (true, vv(b.y, 1), vv(a.y, 1)),
            (g.uIndependent, hv(a.x, 2), hv(b.x, 2)),
            (g.rIndependent, vv(b.y, 3), vv(a.y, 3)),
        ]
        doc.update(graph: gi, "囲んだ範囲を表示") { graph in
            for (axis, r) in ranges.enumerated() where r.0 && r.1.isFinite && r.2.isFinite && r.1 != r.2 {
                let (lo, hi) = (min(r.1, r.2), max(r.1, r.2))
                let rev = graph.axes[axis].from > graph.axes[axis].to
                graph.axes[axis].from = rev ? hi : lo
                graph.axes[axis].to = rev ? lo : hi
                if graph.axes[axis].autoStep {
                    let auto = AxisScale.autoScaled(graph.axes[axis], minValue: lo, maxValue: hi)
                    graph.axes[axis].increment = auto.increment
                    graph.axes[axis].division = auto.division
                }
            }
            graph.syncCommonAxes()
        }
    }

    @objc func beginMaskRect(_ sender: Any?) {
        canvas.mode = canvas.mode == .maskRect ? .normal : .maskRect
    }

    /// 囲んだ範囲の点を除く(サイドバーでデータを選んでいればそのデータだけ、なければ表示している全部)
    func applyMaskRect(pageRect r: CGRect) {
        guard let doc, let g = doc.activeGraph else { return }
        let t = GraphRenderer.graphTransform(g).inverted()
        let a = CGPoint(x: r.minX, y: r.minY).applying(t), b = CGPoint(x: r.maxX, y: r.maxY).applying(t)
        let fr = GraphRenderer.Frame(g)
        var targets = g.series.indices.filter { g.series[$0].visible }
        if case .series(let sg, let si) = state.selection, sg == gi, si < g.series.count { targets = [si] }
        guard !targets.isEmpty else { return }
        guard g.masks.count < Graph.maxMasks else {
            alert("これ以上は除けません", "1 つのグラフで除ける範囲は \(Graph.maxMasks) 個までです。"); return
        }
        doc.update(graph: gi, "囲んだ点を除く") { graph in
            for si in targets where graph.masks.count < Graph.maxMasks {
                let s = graph.series[si]
                let h = graph.horizontalAxisIndex(for: s), v = graph.verticalAxisIndex(for: s)
                let x0 = fr.scales[h].value(atFraction: Double(a.x) / fr.width), x1 = fr.scales[h].value(atFraction: Double(b.x) / fr.width)
                let y0 = fr.scales[v].value(atFraction: 1 - Double(b.y) / fr.height), y1 = fr.scales[v].value(atFraction: 1 - Double(a.y) / fr.height)
                graph.masks.append(DataMask(seriesIndex: si, xMin: min(x0, x1), xMax: max(x0, x1), yMin: min(y0, y1), yMax: max(y0, y1)))
            }
        }
        setStatus("囲んだ範囲の点を除きました。インスペクタの「データ」で戻せます。")
    }

    @objc func clearMasks(_ sender: Any?) {
        doc?.update(graph: gi, "除いた点をすべて戻す") { $0.masks.removeAll() }
    }

    func removeMask(_ index: Int) {
        doc?.update(graph: gi, "除いた範囲を戻す") { g in
            if index < g.masks.count { g.masks.remove(at: index) }
        }
    }

    // MARK: - データ

    @objc func addData(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = true
        panel.message = "グラフに加えるデータファイル(CSV・TXT・DAT など)を選んでください。"
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let self else { return }
            self.addDataFiles(panel.urls)
        }
    }

    func addDataFiles(_ urls: [URL]) {
        guard let doc, !urls.isEmpty else { return }
        let prefs = AppSettings.shared.dataOpenPreferences
        let graphIndex = gi
        var proj = doc.project
        let wasEmpty = proj.graphs[graphIndex].series.isEmpty
        var added: [Int] = []
        var unreadable: [String] = []
        for url in urls {
            guard proj.graphs[graphIndex].series.count < GraphWindowController.maxSeries else { break }
            guard let data = try? Data(contentsOf: url) else { unreadable.append(url.lastPathComponent); continue }
            var file = DataImport.dataFile(name: url.lastPathComponent, contents: data, timestamp: SMPWriter.timestamp(Date()))
            file.name = DataImport.uniqueName(file.name, contents: file, in: proj)
            proj.setDataFile(file)
            let index = proj.graphs[graphIndex].series.count
            var s = DataImport.newSeries(name: file.name, path: url.path, index: index, preferences: prefs,
                                         previous: proj.graphs[graphIndex].series.last)
            DataImport.guessColumns(file, series: &s)
            s.linesRead = DataParser.rows(for: s, lines: file.lines).count
            proj.graphs[graphIndex].series.append(s)
            doc.noteDataFileDate(file.name, url: url)
            added.append(index)
        }
        if !unreadable.isEmpty { alert("読めないファイルがありました", unreadable.joined(separator: "\n")) }
        guard let last = added.last else { return }
        var axes: [Int] = []
        if prefs.autoScaleX || wasEmpty { axes.append(0) }
        if prefs.autoScaleY || wasEmpty { axes.append(1) }
        GraphOps.clearScale(&proj, graphIndex: graphIndex, axes: axes)
        proj.graphs[graphIndex].syncCommonAxes()
        let final = proj
        doc.update(added.count > 1 ? "データの追加(\(added.count) 個)" : "データの追加") { $0 = final }
        selectSeries(last, tab: 0)
        if let msg = doc.plotData()[graphIndex][last].error { alert("データを描けませんでした", msg) }
    }

    /// 新しいデータを打ち込む(SMP の中にだけ持つ)
    @objc func newData(_ sender: Any?) {
        guard let window else { return }
        Sheets.editData(name: "新しいデータ", text: "# x y\n0 0\n1 1\n2 4\n", over: window) { [weak self] text in
            self?.addEmbeddedData(text: text, baseName: "DATA", actionName: "新しいデータ")
        }
    }

    @objc func editData(_ sender: Any?) {
        withSeries("編集するデータ", where: { $0.kind != .function }) { [weak self] si in self?.editData(series: si) }
    }

    func editData(series si: Int) {
        guard let doc, let window, let g = doc.activeGraph, si < g.series.count else { return }
        let s = g.series[si]
        guard let file = doc.project.dataFile(named: s.name) else {
            alert("データの中身がありません", "\(s.name) のファイルが見つかっていません。"); return
        }
        let graphIndex = gi
        Sheets.editData(name: s.name, text: file.lines.joined(separator: "\n"), over: window) { text in
            var nf = DataImport.dataFile(name: file.name, contents: Data(text.utf8), timestamp: SMPWriter.timestamp(Date()))
            nf.name = file.name
            doc.update("データの編集") { p in
                p.setDataFile(nf)
                for gIndex in p.graphs.indices {
                    for sIndex in p.graphs[gIndex].series.indices where SMPProject.key(p.graphs[gIndex].series[sIndex].name) == SMPProject.key(nf.name) {
                        p.graphs[gIndex].series[sIndex].linesRead = DataParser.rows(for: p.graphs[gIndex].series[sIndex], lines: nf.lines).count
                    }
                }
            }
            _ = graphIndex
        }
    }

    /// 表示するデータを選ぶ
    @objc func chooseVisibleSeries(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, !g.series.isEmpty, let window else { return }
        let visible = IndexSet(g.series.indices.filter { g.series[$0].visible })
        Sheets.chooseSeries(title: "表示するデータ", message: "チェックしたデータだけをグラフに描きます。", items: g.series, multiple: true,
                            preselected: visible, over: window) { [weak self] sel in
            guard let self else { return }
            doc.update(graph: self.gi, "表示するデータを選ぶ") { graph in
                for i in graph.series.indices { graph.series[i].visible = sel.contains(i) }
            }
        }
    }

    @objc func removeSelectedSeries(_ sender: Any?) {
        withSeries("取り除くデータ") { [weak self] si in self?.removeSeries(at: si) }
    }

    /// データをグラフから取り除く(取り消せる)
    func removeSeries(at si: Int) {
        guard let doc, let g = doc.activeGraph, si < g.series.count else { return }
        let graphIndex = gi
        let name = g.series[si].displayName
        doc.update("データを取り除く") { p in
            p.graphs[graphIndex].series.remove(at: si)
            p.graphs[graphIndex].masks = p.graphs[graphIndex].masks.compactMap { m in
                if m.seriesIndex == si { return nil }
                var mm = m
                if m.seriesIndex > si { mm.seriesIndex -= 1 }
                return mm
            }
            GraphOps.pruneData(&p)
        }
        state.select(.graph(graphIndex))
        setStatus("\(name) を取り除きました。")
    }

    @objc func toggleReadValues(_ sender: Any?) {
        if canvas.mode == .readValue {
            canvas.mode = .normal
            return
        }
        guard let g = doc?.activeGraph, !g.series.isEmpty else { return }
        if case .series(let sg, let si) = state.selection, sg == gi, si < g.series.count {
            canvas.readSeries = si
        } else {
            canvas.readSeries = nil
        }
        canvas.mode = .readValue
        if let si = canvas.readSeries ?? g.series.indices.first(where: { g.series[$0].visible }) {
            canvas.setReadValue(series: si, index: 0)
        }
    }

    // MARK: - ファイルを落としたとき

    func handleDroppedFiles(_ urls: [URL], at page: CGPoint) {
        guard let doc else { return }
        var data: [URL] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "smp" || ext == "sma" {
                loadGraphFile(url)
            } else if let t = UTType(filenameExtension: ext), GraphWindowController.pictureTypes.contains(where: { t.conforms(to: $0) }) {
                if let g = doc.activeGraph {
                    let local = page.applying(GraphRenderer.graphTransform(g).inverted())
                    insertPicture(url: url, atMM: CGPoint(x: local.x / 100, y: local.y / 100))
                }
            } else {
                data.append(url)
            }
        }
        if !data.isEmpty { addDataFiles(data) }
    }
}
