import AppKit
import SMPKit

/// 解析(当てはめ・補間・関数・ピーク)と、インスペクタからの頼み
extension GraphWindowController {
    /// 曲線の範囲などを、はじめて解析するときの値にする
    func prepareCurve(_ s0: Series, kind: Series.Kind, graph g: Graph, data: SeriesPlotData) -> Series {
        var s = s0
        let xs = data.finitePoints.map(\.0)
        if s.kind != kind || (s.curveStart == 0 && s.curveEnd == 0) {
            s.curveStart = xs.min() ?? g.axes[0].from
            s.curveEnd = xs.max() ?? g.axes[0].to
        }
        if s.kind != kind && kind == .polynomialLSQ {
            s.lsqOrder = AppSettings.shared.stored("lsq.order", as: Int.self) ?? 1
        }
        s.kind = kind
        s.kindRaw = kind.rawValue
        if s.curveDivisions <= 0 { s.curveDivisions = 101 }
        if g.axes[0].scaleType.isLog && s.curveSpacing == .linear { s.curveSpacing = .exponential }
        return s
    }

    /// 解析の設定を書き込み、結果をインスペクタの「曲線」で見せる
    func applyAnalysis(_ ns: Series, at si: Int, actionName: String) {
        guard let doc else { return }
        let graphIndex = gi
        doc.update(graph: graphIndex, actionName) { g in
            if si < g.series.count { g.series[si] = ns }
        }
        if ns.kind == .polynomialLSQ { AppSettings.shared.store(ns.lsqOrder, key: "lsq.order") }
        selectSeries(si, tab: 2)
        showInspector()
        let d = doc.plotData()
        guard graphIndex < d.count, si < d[graphIndex].count else { return }
        if let e = d[graphIndex][si].error {
            alert("\(actionName)ができませんでした", e)
        } else if let a = ns.extensionAnalysis, !a.producesCurve {
            // 曲線を描かない解析(最大値・ピークなど)は、結果をすぐ見せる
            showResults(series: si)
        }
    }

    /// 最小二乗(tag 1:多項式 4:指数 5:対数 6:べき 7:一般の関数)
    @objc func leastSquares(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 1
        let kind = Series.Kind(rawValue: tag) ?? .polynomialLSQ
        withSeries("当てはめるデータ", where: { $0.kind != .function }) { [weak self] si in
            self?.runCurveSetup(si, kind: kind, splineMode: nil)
        }
    }

    /// スプライン補間(tag 0:3 次 1:パラメトリック 2:閉じた曲線)
    @objc func spline(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        withSeries("補間するデータ", where: { $0.kind != .function }) { [weak self] si in
            self?.runCurveSetup(si, kind: .spline, splineMode: Spline.Mode(rawValue: tag) ?? .cubic)
        }
    }

    static func analysisTitle(_ kind: Series.Kind) -> String {
        switch kind {
        case .spline: return "スプライン補間"
        case .function: return "関数を描く"
        default: return "\(kind.displayTitle)で当てはめる"
        }
    }

    func runCurveSetup(_ si: Int, kind: Series.Kind, splineMode: Spline.Mode?) {
        guard let doc, let g = doc.activeGraph, si < g.series.count, let window else { return }
        let data = doc.plotData()
        guard gi < data.count, si < data[gi].count else { return }
        var s = prepareCurve(g.series[si], kind: kind, graph: g, data: data[gi][si])
        if let m = splineMode { s.lsqOrder = m.rawValue }
        s.extensionAnalysis = nil
        let title = GraphWindowController.analysisTitle(kind)
        Sheets.analysisConditions(s, title: title, over: window) { [weak self] ns in
            self?.applyAnalysis(ns, at: si, actionName: title)
        }
    }

    /// ピークの当てはめ・最大値・なめらかにする など(tag は ExtensionAnalysis の並び)
    @objc func extensionAnalysis(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        guard tag >= 0, tag < ExtensionAnalysis.allCases.count else { return }
        let a = ExtensionAnalysis.allCases[tag]
        withSeries("「\(a.displayTitle)」のデータ", where: { $0.kind != .function }) { [weak self] si in
            self?.runExtension(a, series: si)
        }
    }

    func runExtension(_ a: ExtensionAnalysis, series si: Int) {
        guard let doc, let g = doc.activeGraph, si < g.series.count, let window else { return }
        let data = doc.plotData()
        guard gi < data.count, si < data[gi].count else { return }
        var s = g.series[si]
        if a.usesFittingDialog {
            let wasSame = s.extensionAnalysis == a
            s = prepareCurve(s, kind: .extension1, graph: g, data: data[gi][si])
            if !wasSame {
                let pts = data[gi][si].finitePoints
                s.peakFit = PeakFitSettings.initialGuess(x: pts.map(\.0), y: pts.map(\.1), count: max(s.peakFit.count, 1))
            }
            s.extensionAnalysis = a
            Sheets.peakFit(s, title: a.displayTitle, over: window) { [weak self] ns in
                self?.applyAnalysis(ns, at: si, actionName: a.displayTitle)
            }
        } else {
            if a.producesCurve { s = prepareCurve(s, kind: .extension1, graph: g, data: data[gi][si]) }
            s.kind = .extension1
            s.kindRaw = Series.Kind.extension1.rawValue
            s.extensionAnalysis = a
            applyAnalysis(s, at: si, actionName: a.displayTitle)
        }
    }

    /// 関数を描く(新しいデータとして加える)
    @objc func drawFunction(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, let window else { return }
        guard g.series.count < GraphWindowController.maxSeries else {
            alert("これ以上データを加えられません", "1 つのグラフに入れられるデータは \(GraphWindowController.maxSeries) 個までです。"); return
        }
        var name = "FUNCTION.DAT"
        var k = 1
        while g.series.contains(where: { $0.name.uppercased() == name }) { k += 1; name = "FUNCTION\(k).DAT" }
        var s = Series(name: name)
        s.kind = .function
        s.kindRaw = Series.Kind.function.rawValue
        s.transformY = true
        s.expressionY = "sin(x)"
        s.lineType = .solid
        s.dotType = 0
        let x = g.axes[0]
        s.curveStart = x.scaleType.isInverse ? 1 / x.from : x.from
        s.curveEnd = x.scaleType.isInverse ? 1 / x.to : x.to
        s.curveDivisions = 201
        if x.scaleType.isLog { s.curveSpacing = .exponential }
        let graphIndex = gi
        Sheets.analysisConditions(s, title: "関数を描く", over: window) { [weak self] ns in
            guard let self else { return }
            doc.update(graph: graphIndex, "関数を描く") { $0.series.append(ns) }
            self.selectSeries(doc.project.graphs[graphIndex].series.count - 1, tab: 2)
        }
    }

    /// 解析の条件を変える
    @objc func refitSeries(_ sender: Any?) {
        withSeries("条件を変えるデータ", where: { $0.kind != .normal || $0.extensionAnalysis != nil }) { [weak self] si in
            self?.refit(series: si)
        }
    }

    func refit(series si: Int) {
        guard let doc, let g = doc.activeGraph, si < g.series.count, let window else { return }
        let s = g.series[si]
        if let a = s.extensionAnalysis {
            if a.usesFittingDialog {
                Sheets.peakFit(s, title: a.displayTitle, over: window) { [weak self] ns in
                    self?.applyAnalysis(ns, at: si, actionName: a.displayTitle)
                }
            } else {
                showResults(series: si)
            }
            return
        }
        guard s.kind != .normal else { return }
        let title = GraphWindowController.analysisTitle(s.kind)
        Sheets.analysisConditions(s, title: title, over: window) { [weak self] ns in
            self?.applyAnalysis(ns, at: si, actionName: title)
        }
    }

    @objc func clearSeriesAnalysis(_ sender: Any?) {
        withSeries("解析をやめるデータ", where: { ($0.kind != .normal && $0.kind != .function) || $0.extensionAnalysis != nil }) { [weak self] si in
            self?.clearAnalysis(series: si)
        }
    }

    func clearAnalysis(series si: Int) {
        guard let doc, let g = doc.activeGraph, si < g.series.count else { return }
        if g.series[si].kind == .function { removeSeries(at: si); return }
        doc.update(graph: gi, "解析をやめる") { g in
            g.series[si].kind = .normal
            g.series[si].kindRaw = 0
            g.series[si].extensionAnalysis = nil
        }
        state.seriesTab = 0
    }

    /// 解析の結果(式の係数など)
    @objc func showResultsSheet(_ sender: Any?) {
        withSeries("結果を見るデータ", where: { $0.kind != .normal || $0.extensionAnalysis != nil }) { [weak self] si in
            self?.showResults(series: si)
        }
    }

    func resultLines(series si: Int) -> [String] {
        guard let doc else { return [] }
        let data = doc.plotData()
        guard gi < data.count, si < data[gi].count else { return [] }
        let d = data[gi][si]
        if let e = d.error { return [e] }
        return d.resultLines.isEmpty ? (d.fit?.summary.components(separatedBy: "\n") ?? []) : d.resultLines
    }

    func showResults(series si: Int) {
        guard let doc, let window, let g = doc.activeGraph, si < g.series.count else { return }
        let lines = resultLines(series: si)
        guard !lines.isEmpty else {
            alert("結果はありません", "この解析には、式の係数などの結果がありません。", style: .informational); return
        }
        let s = g.series[si]
        Sheets.results(title: "\(s.displayName) — \(s.analysisTitle ?? "結果")", lines: lines, over: window) { [weak self] in
            self?.insertText(kind: .other, text: lines.joined(separator: "\n"))
        }
    }

    /// 当てはめた式で、x の値から y を求める
    @objc func evaluateFit(_ sender: Any?) {
        guard let doc else { return }
        withSeries("値を求める式", where: { $0.kind.isLSQ }) { [weak self] si in
            guard let self else { return }
            let data = doc.plotData()
            guard self.gi < data.count, si < data[self.gi].count, let fit = data[self.gi][si].fit else {
                self.alert("式がありません", "当てはめに失敗しているか、まだ当てはめていません。"); return
            }
            self.askEvaluate(fit: fit, last: "0")
        }
    }

    private func askEvaluate(fit: FitResult, last: String) {
        guard let window else { return }
        Sheets.input(title: "式で値を求める", message: "x の値(式も使えます)", text: last, over: window) { [weak self] input in
            guard let self, let window = self.window else { return }
            let trimmed = input.trimmingCharacters(in: .whitespaces)
            guard let x = Double(trimmed) ?? (try? Expression(trimmed).evaluateScalar()) else {
                self.alert("x の値を読めませんでした", input); return
            }
            let y = fit.evaluate(x)
            DispatchQueue.main.async {
                let a = NSAlert()
                a.messageText = "y = \(NumberText.g(y))"
                a.informativeText = "x = \(NumberText.g(x))"
                a.alertStyle = .informational
                a.addButton(withTitle: "閉じる")
                a.addButton(withTitle: "ほかの x で求める")
                a.addButton(withTitle: "コピー")
                a.beginSheetModal(for: window) { r in
                    if r == .alertSecondButtonReturn {
                        DispatchQueue.main.async { self.askEvaluate(fit: fit, last: input) }
                    } else if r == .alertThirdButtonReturn {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(NumberText.g(x) + "\t" + NumberText.g(y), forType: .string)
                    }
                }
            }
        }
    }

    /// 曲線の点の値(解析の結果つき)をクリップボードへ
    @objc func copyCurveValues(_ sender: Any?) {
        guard let doc else { return }
        withSeries("曲線の値をコピーするデータ", where: { $0.hasCurve }) { [weak self] si in
            guard let self, let g = doc.activeGraph else { return }
            let data = doc.plotData()
            guard self.gi < data.count, si < data[self.gi].count else { return }
            let d = data[self.gi][si]
            let pts: [(Double, Double)] = g.series[si].kind == .function ? Array(zip(d.x, d.y)) : d.curve.map { (Double($0.x), Double($0.y)) }
            var out = d.resultLines.map { "# " + $0 + "\n" }.joined()
            for p in pts where p.0.isFinite && p.1.isFinite {
                out += NumberText.export(p.0) + "\t" + NumberText.export(p.1) + "\n"
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(out, forType: .string)
            self.setStatus("曲線の \(pts.count) 点の値をコピーしました。")
        }
    }

    /// 式で使う定数 a〜i
    @objc func showConstants(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, let window else { return }
        let graphIndex = gi
        Sheets.constants(g.constants, over: window) { values in
            doc.update(graph: graphIndex, "定数") { $0.constants = values }
        }
    }

    // MARK: - インスペクタからの頼み

    func perform(_ cmd: EditorState.Command) {
        switch cmd {
        case .refit(let si): refit(series: si)
        case .clearAnalysis(let si): clearAnalysis(series: si)
        case .editData(let si): editData(series: si)
        case .removeMask(let i): removeMask(i)
        case .deleteObject(let id):
            doc?.update(graph: gi, "削除") { $0.objects.removeAll { $0.id == id } }
            canvas.selection.remove(id)
        case .choosePicture(let id): choosePicture(for: id)
        case .showResults(let si): showResults(series: si)
        case .copyValues(let si): copyValues(series: si)
        }
    }
}
