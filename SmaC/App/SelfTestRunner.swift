import AppKit
import SMPKit

/// 確かめる用: 画面に出さずに、データを開く → マウスで動かす → 取り消す → 解析 → 保存して開き直す、を通して確かめる。
/// SMAC_TEST_INPUT=データファイル SMAC_TEST_OUTPUT=出力フォルダ SmaC --selftest
@MainActor
enum SelfTestRunner {
    static var isActive: Bool { CommandLine.arguments.contains("--selftest") }

    static var failures = 0

    static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if ok { print("PASS \(name)") } else { failures += 1; print("FAIL \(name) \(detail())") }
    }

    static func run() {
        let env = ProcessInfo.processInfo.environment
        guard let inPath = env["SMAC_TEST_INPUT"], let outPath = env["SMAC_TEST_OUTPUT"] else { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        setvbuf(stdout, nil, _IOLBF, 0)
        let input = URL(fileURLWithPath: inPath)
        let outDir = URL(fileURLWithPath: outPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        DispatchQueue.main.async {
            do { try scenario(input: input, outDir: outDir) } catch {
                failures += 1
                print("FAIL exception \(error)")
            }
            print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
            NSApp.terminate(nil)
        }
    }

    static func mouse(_ type: NSEvent.EventType, _ p: CGPoint, in window: NSWindow, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    static func tick(_ s: Double = 0.02) {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: s))
    }

    /// 1 回の操作 = 1 つの取り消しの単位(実際のアプリではイベントごとに自動で区切られる)
    static var undo: UndoManager?
    static func step(_ body: () -> Void) {
        undo?.beginUndoGrouping()
        body()
        undo?.endUndoGrouping()
    }

    /// 作業面の上のドラッグ(page は用紙の座標、delta は作業面の点)
    static func drag(_ canvas: CanvasView, from page: CGPoint, by delta: CGSize) {
        tick()
        guard let window = canvas.window else { return }
        let v = canvas.viewPoint(page)
        let w0 = canvas.convert(v, to: nil)
        let w1 = canvas.convert(CGPoint(x: v.x + delta.width, y: v.y + delta.height), to: nil)
        canvas.mouseDown(with: mouse(.leftMouseDown, w0, in: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: (w0.x + w1.x) / 2, y: (w0.y + w1.y) / 2), in: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, w1, in: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, w1, in: window))
        tick()
    }

    static func click(_ canvas: CanvasView, at page: CGPoint) {
        guard let window = canvas.window else { return }
        let w = canvas.convert(canvas.viewPoint(page), to: nil)
        canvas.mouseDown(with: mouse(.leftMouseDown, w, in: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, w, in: window))
        tick()
    }

    static func scenario(input: URL, outDir: URL) throws {
        // 1. データファイルを開く
        let dc = NSDocumentController.shared
        let type = try dc.typeForContents(of: input)
        check(type == GraphDocument.dataType, "データファイルの種類", type)
        guard let doc = try dc.makeDocument(withContentsOf: input, ofType: type) as? GraphDocument else { throw CocoaError(.fileReadUnknown) }
        check(doc.fileURL == nil, "データファイルは名前のないグラフとして開く")
        check(doc.fileType == GraphDocument.smpType, "保存の形式は SMP", doc.fileType ?? "nil")
        check(doc.project.graphs.count == 1 && doc.project.graphs[0].series.count == 1, "グラフ 1 枚・データ 1 つ")
        let pts = doc.plotData()[0][0].finitePoints
        check(pts.count == 7, "見出しとコメント行を除いた 7 点", "\(pts.count)")
        let ax = doc.project.graphs[0].axes[0]
        check(ax.from <= 10 && ax.to >= 1000, "X の範囲が自動で合う", "\(ax.from)〜\(ax.to)")
        doc.undoManager?.groupsByEvent = false
        undo = doc.undoManager

        doc.makeWindowControllers()
        guard let wc = doc.windowControllers.first as? GraphWindowController, let window = wc.window else { throw CocoaError(.fileReadUnknown) }
        window.setFrame(NSRect(x: -9000, y: -9000, width: 1240, height: 800), display: true)
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
        tick(0.3)
        let canvas = wc.canvas
        canvas.updateSize()
        check(wc.splitController.splitViewItems.count == 3, "サイドバー・作業面・インスペクタの 3 つに分かれる")
        check(wc.splitController.splitViewItems.first?.behavior == .sidebar && wc.splitController.splitViewItems.last?.behavior == .inspector,
              "左はサイドバー、右はインスペクタ")
        check(canvas.enclosingScrollView?.allowsMagnification == true, "作業面を拡大・縮小できる")

        // 2. 軸を対数にして、X 軸の題を入れる
        step {
            doc.update(graph: 0, "X 軸") { g in
                g.axes[0].scaleType = .logNormal
                g.axes[0].from = 10; g.axes[0].to = 1000; g.axes[0].increment = 10; g.axes[0].division = 10
            }
        }
        step { wc.insertAxisTitle(NSMenuItem.tagged(4)) }
        guard let item = doc.project.graphs[0].objects.first, case .text(var t0) = item.object else { throw CocoaError(.fileReadUnknown) }
        check(t0.kind == .xTitle, "X 軸の題を入れる")
        check(wc.state.selection == .object(graph: 0, id: item.id), "入れた文字がインスペクタで選ばれる")
        step {
            doc.update(graph: 0, "文字") { g in
                if case .text(var t) = g.objects[0].object { t.text = "Frequency [Hz]"; t.x = 5000; t.y = 11800; g.objects[0].object = .text(t) }
            }
        }
        if case .text(let t) = doc.project.graphs[0].objects[0].object { t0 = t }

        // 3. 文字をドラッグで動かす(右へ 40 点、下へ 20 点)
        let renderer = doc.renderer()
        guard let b = renderer.objectBounds(doc.project.graphs[0].objects[0].object, graphIndex: 0) else { throw CocoaError(.fileReadUnknown) }
        let g0 = doc.project.graphs[0]
        let center = CGPoint(x: b.midX, y: b.midY).applying(GraphRenderer.graphTransform(g0))
        step { drag(canvas, from: center, by: CGSize(width: 40, height: 20)) }
        guard case .text(let moved) = doc.project.graphs[0].objects[0].object else { throw CocoaError(.fileReadUnknown) }
        let expectDX = 40 / canvas.unit, expectDY = 20 / canvas.unit
        check(abs(CGFloat(moved.x - t0.x) - expectDX) <= 60 && abs(CGFloat(moved.y - t0.y) - expectDY) <= 60,
              "文字をドラッグで動かす", "dx \(moved.x - t0.x) 期待 \(Int(expectDX)) / dy \(moved.y - t0.y) 期待 \(Int(expectDY))")
        check(moved.x % 50 == 0 && moved.y % 50 == 0, "0.5 mm 刻みにそろう", "\(moved.x), \(moved.y)")

        // 4. 取り消す・やり直す
        doc.undoManager?.undo()
        if let first = doc.project.graphs[0].objects.first, case .text(let back) = first.object {
            check(back.x == t0.x && back.y == t0.y, "取り消すと元の位置に戻る", "\(back.x), \(back.y)")
        } else {
            check(false, "取り消すと元の位置に戻る", "文字まで消えた")
        }
        doc.undoManager?.redo()
        tick()
        if let first = doc.project.graphs[0].objects.first, case .text(let again) = first.object {
            check(again.x == moved.x, "やり直すと動かした位置に戻る")
        }

        // 5. 何もないところをクリックすると選択が外れ、グラフの選択に戻る
        click(canvas, at: CGPoint(x: 500, y: 500))
        check(canvas.selection.isEmpty && wc.state.selection == .graph(0), "空いた所のクリックでグラフの選択に戻る", "\(wc.state.selection)")

        // 6. 枠の右下の角をドラッグして大きくする
        let w0 = doc.project.graphs[0].width, h0 = doc.project.graphs[0].height
        let corner = CGPoint(x: g0.left + g0.width, y: g0.top + g0.height)
        step { drag(canvas, from: corner, by: CGSize(width: 30, height: 15)) }
        let w1 = doc.project.graphs[0].width, h1 = doc.project.graphs[0].height
        check(w1 > w0 && h1 > h0, "角のドラッグでグラフが大きくなる", "\(w0)→\(w1), \(h0)→\(h1)")

        // 7. グラフの中をドラッグするとグラフごと動く
        let g1 = doc.project.graphs[0]
        let inside = CGPoint(x: g1.left + g1.width / 3, y: g1.top + g1.height / 3)
        step { drag(canvas, from: inside, by: CGSize(width: 0, height: 30)) }
        check(doc.project.graphs[0].top > g1.top && doc.project.graphs[0].width == g1.width, "グラフの中のドラッグでグラフが動く",
              "\(g1.top)→\(doc.project.graphs[0].top)")

        // 8. 多項式(2 次)で当てはめる
        var s = doc.project.graphs[0].series[0]
        s = wc.prepareCurve(s, kind: .polynomialLSQ, graph: doc.project.graphs[0], data: doc.plotData()[0][0])
        s.lsqOrder = 2
        let fitted = s
        step { wc.applyAnalysis(fitted, at: 0, actionName: "多項式で当てはめる") }
        let d = doc.plotData()[0][0]
        check(d.fit != nil && d.curve.count > 50, "当てはめの曲線ができる", d.error ?? "")
        check(wc.state.selection == .series(graph: 0, index: 0) && wc.state.seriesTab == 2, "当てはめのあと、インスペクタで曲線を見せる")
        check(!wc.resultLines(series: 0).isEmpty, "当てはめの結果(係数)がある")

        // 9. 凡例
        step { wc.insertLegend(nil) }
        check(doc.undoManager?.undoActionName == "凡例を入れる", "取り消しのメニューに操作の名前が出る", doc.undoManager?.undoActionName ?? "")
        check(doc.project.graphs[0].objects.count == 2, "凡例が入る")

        // 10. 囲んだ範囲を表示(軸の範囲が変わる)
        let before = doc.project.graphs[0].axes[1]
        let fr = doc.project.graphs[0]
        let zr = CGRect(x: fr.left + fr.width / 4, y: fr.top + fr.height / 4, width: fr.width / 2, height: fr.height / 2)
        step { wc.applyZoomRect(pageRect: zr) }
        let after = doc.project.graphs[0].axes[1]
        check(after.from != before.from && after.to != before.to && abs(after.to - after.from) < abs(before.to - before.from),
              "囲んだ範囲を表示すると Y の範囲が狭くなる", "\(before.from)〜\(before.to) → \(after.from)〜\(after.to)")
        doc.undoManager?.undo()
        check(doc.project.graphs[0].axes[1] == before, "取り消すと範囲が戻る")

        // 11. 囲んだ点を除く
        let n0 = doc.plotData()[0][0].finitePoints.count
        step { doc.update(graph: 0, "除く") { $0.masks = [DataMask(seriesIndex: 0, xMin: 0, xMax: 150, yMin: -1e9, yMax: 1e9)] } }
        let n1 = doc.plotData()[0][0].finitePoints.count
        check(n1 < n0, "除いた範囲の点を描かない", "\(n0)→\(n1)")
        step { wc.clearMasks(nil) }
        check(doc.plotData()[0][0].finitePoints.count == n0, "除いた点をすべて戻す")

        // 12. 値を読む
        wc.state.select(.series(graph: 0, index: 0))
        wc.toggleReadValues(nil)
        check(canvas.mode == .readValue && canvas.readValue != nil, "値を読む(点の値が出る)")
        if let rv = canvas.readValue {
            canvas.stepReadValue(rv, by: 1)
            check(canvas.readValue?.index == rv.index + 1, "→ で隣の点へ")
        }
        WindowCapture.save(canvas, to: outDir.appendingPathComponent("selftest_readvalue.png"))
        wc.toggleReadValues(nil)
        check(canvas.mode == .normal, "もう一度押すと値を読むのをやめる")

        // 13. 保存して読み直す
        let url = outDir.appendingPathComponent("selftest.SMP")
        try doc.write(to: url, ofType: GraphDocument.smpType)
        let raw = try Data(contentsOf: url)
        let head = String(data: raw.prefix(40), encoding: .ascii) ?? ""
        check(head.hasPrefix(" Sma4Win ver. 1.8  SMP file\r\n"), "SMP 形式の見出しと CRLF", head)
        let sjisHeader = "周波数[Hz],加速度[G]".data(using: SMPTextEncoding.windows31J)!
        check(raw.range(of: sjisHeader) != nil, "データは Shift_JIS で入れる")
        let back = try SMPReader.read(data: raw, fileName: url.lastPathComponent)
        check(back.graphs.count == 1 && back.graphs[0].series[0].kind == .polynomialLSQ && back.graphs[0].series[0].lsqOrder == 2,
              "保存した SMP に当てはめの設定が残る")
        check(back.graphs[0].axes[0].scaleType == .logNormal, "保存した SMP に対数の軸が残る")
        check(back.graphs[0].objects.count == 2, "保存した SMP に文字と凡例が残る", "\(back.graphs[0].objects.count)")
        check(back.dataFile(named: input.lastPathComponent)?.lines.count == doc.project.dataFile(named: input.lastPathComponent)?.lines.count,
              "データの行数が同じ")

        // 14. 開き直して同じ絵になるか
        guard let doc2 = try dc.makeDocument(withContentsOf: url, ofType: GraphDocument.smpType) as? GraphDocument else { throw CocoaError(.fileReadUnknown) }
        check(doc2.plotData()[0][0].finitePoints.count == pts.count, "開き直しても 7 点")
        let r1 = GraphExporter.pngData(renderer: doc.renderer(), dpi: 72)
        let r2 = GraphExporter.pngData(renderer: doc2.renderer(), dpi: 72)
        check(r1 != nil && r1 == r2, "開き直しても同じ絵になる")

        // 15. 書き出し
        let pdf = GraphExporter.pdfData(renderer: doc.renderer())
        check(pdf.count > 1000 && pdf.starts(with: Array("%PDF".utf8)), "PDF に書き出せる", "\(pdf.count) bytes")
        try pdf.write(to: outDir.appendingPathComponent("selftest.pdf"))
        WindowCapture.save(canvas, to: outDir.appendingPathComponent("selftest_canvas.png"))
        WindowCapture.save(window.contentView, to: outDir.appendingPathComponent("selftest_window.png"))

        // 16. グラフを加える・複製・削除
        step { wc.addGraph(nil) }
        check(doc.project.graphs.count == 2 && doc.activeGraphIndex == 1 && wc.state.selection == .graph(1), "グラフを加えると、そのグラフを選ぶ")
        step { wc.deleteGraph(nil) }
        check(doc.project.graphs.count == 1, "中が空のグラフはすぐ消せる")
        step { wc.duplicateGraph(nil) }
        check(doc.project.graphs.count == 2 && doc.project.graphs[1].series.count == 1 && doc.project.graphs[1].objects.count == 2,
              "グラフを複製すると、データと文字も写る")
        check(Set(doc.project.graphs[0].objects.map(\.id)).isDisjoint(with: doc.project.graphs[1].objects.map(\.id)), "複製した文字は別のもの")
        doc.undoManager?.undo()
        check(doc.project.graphs.count == 1, "複製を取り消せる")

        // 17. 起動したときの「新規」
        guard let blank = try dc.makeUntitledDocument(ofType: GraphDocument.smpType) as? GraphDocument else { throw CocoaError(.fileReadUnknown) }
        check(blank.project.graphs.count == 1 && blank.project.graphs[0].series.isEmpty, "新規は空のグラフ 1 枚")
        blank.makeWindowControllers()
        check(blank.windowControllers.first?.window != nil, "新規の窓ができる")

        // 18. メニューの全項目が、どれかの受け手につながっている
        var unhandled: [String] = []
        let receivers: [AnyObject] = [wc, window, canvas, doc, NSApp, NSApp.delegate as AnyObject, dc, wc.splitController]
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if let sub = item.submenu { walk(sub); continue }
                guard let action = item.action else { continue }
                if item.target != nil { continue }
                if !receivers.contains(where: { $0.responds(to: action) }) { unhandled.append("\(item.title)(\(action))") }
            }
        }
        if let main = NSApp.mainMenu { walk(main) }
        walk(MainMenuBuilder.shapeMenu())
        walk(MainMenuBuilder.exportMenu())
        check(unhandled.isEmpty, "メニューの全項目がつながっている", unhandled.joined(separator: ", "))
        if let main = NSApp.mainMenu {
            var count = 0
            func validate(_ menu: NSMenu) {
                for item in menu.items {
                    if let sub = item.submenu { validate(sub); continue }
                    if let a = item.action, wc.responds(to: a) { _ = wc.validateMenuItem(item); count += 1 }
                }
            }
            validate(main)
            check(count > 50, "メニューの有効・無効を判定できる", "\(count)")
        }

        // 19. ツールバー
        let items = window.toolbar?.items ?? []
        check(items.count >= 12, "ツールバーのボタンが並ぶ", "\(items.count)")
        let actions = items.compactMap { $0.action } + wc.toggleButtons.values.compactMap(\.action)
        check(actions.allSatisfy { a in receivers.contains(where: { $0.responds(to: a) }) }, "ツールバーのボタンがつながっている")
        let symbols = items.filter { $0.itemIdentifier.rawValue.hasPrefix("smac.") && $0.view == nil }
        check(symbols.allSatisfy { $0.image != nil }, "ツールバーの絵は SF Symbols")

        // 20. シートを出して閉じられる(落ちない)
        let sheetsDir = outDir.appendingPathComponent("sheets")
        try? FileManager.default.createDirectory(at: sheetsDir, withIntermediateDirectories: true)
        var shown = 0
        func sheet(_ name: String, _ open: () -> Void) {
            open()
            tick(0.25)
            if let sh = window.attachedSheet {
                shown += 1
                WindowCapture.save(sh.contentView, to: sheetsDir.appendingPathComponent(name + ".png"))
                window.endSheet(sh)
                tick(0.1)
            } else {
                print("NOTE sheet \(name) が出なかった")
            }
        }
        let gs = doc.project.graphs[0]
        let ser = gs.series[0]
        for kind in [Series.Kind.polynomialLSQ, .expLSQ, .generalLSQ, .spline, .function] {
            var k = ser; k.kind = kind; k.kindRaw = kind.rawValue
            sheet("analysis_\(kind.rawValue)") { Sheets.analysisConditions(k, title: GraphWindowController.analysisTitle(kind), over: window) { _ in } }
        }
        var pk = ser; pk.extensionAnalysis = .gaussian; pk.kind = .extension1
        sheet("peakfit") { Sheets.peakFit(pk, title: ExtensionAnalysis.gaussian.displayTitle, over: window) { _ in } }
        sheet("constants") { Sheets.constants(gs.constants, over: window) { _ in } }
        sheet("choose_one") { Sheets.chooseSeries(title: "当てはめるデータ", message: "", items: gs.series, multiple: false, preselected: [0], over: window) { _ in } }
        sheet("choose_many") { Sheets.chooseSeries(title: "表示するデータ", message: "チェックしたデータだけを描きます。", items: gs.series, multiple: true, preselected: [0], over: window) { _ in } }
        sheet("edit_data") { Sheets.editData(name: ser.name, text: "1 2\n3 4\n", over: window) { _ in } }
        sheet("results") { Sheets.results(title: "結果", lines: wc.resultLines(series: 0), over: window) {} }
        sheet("input") { Sheets.input(title: "式で値を求める", message: "x の値", text: "0", over: window) { _ in } }
        sheet("copy_options") { Sheets.copyOptions(over: window) { _, _, _ in } }
        sheet("paper") { Sheets.paper(gs.page, over: window) { _ in } }
        check(shown == 14, "シートが出て閉じられる", "\(shown) / 14")

        window.orderOut(nil)
    }
}

extension NSMenuItem {
    /// テスト用: tag だけ持つメニュー項目
    static func tagged(_ tag: Int) -> NSMenuItem {
        let i = NSMenuItem()
        i.tag = tag
        return i
    }
}
