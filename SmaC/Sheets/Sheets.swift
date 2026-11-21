import SwiftUI
import AppKit
import SMPKit

/// 書類の窓に付けて出すシート。中身は SwiftUI で書き、AppKit のシートとして出す
@MainActor
enum Sheets {
    /// 出しているシート(閉じ終わるまで放さない)
    private static var openSheets: [ObjectIdentifier: NSWindow] = [:]

    /// SwiftUI の中身をシートとして出す。close を呼ぶとシートを閉じる
    static func present<V: View>(over window: NSWindow, @ViewBuilder _ content: (_ close: @escaping () -> Void) -> V) {
        present(over: window, resizableWith: nil, content)
    }

    /// size を渡すと、その大きさで出し、利用者が大きさを変えられるシートにする(中身は最小の大きさだけを決める)。
    /// nil なら中身の大きさに合わせる(中身が変わると窓も合わせて変わる)
    static func present<V: View>(over window: NSWindow, resizableWith size: NSSize?,
                                 @ViewBuilder _ content: (_ close: @escaping () -> Void) -> V) {
        let sheet = NSWindow(contentRect: NSRect(origin: .zero, size: size ?? NSSize(width: 480, height: 200)),
                             styleMask: size == nil ? [.titled] : [.titled, .resizable],
                             backing: .buffered, defer: true)
        sheet.isReleasedWhenClosed = false
        var ended = false
        let close: () -> Void = { [weak window, weak sheet] in
            guard !ended, let sheet else { return }
            ended = true
            if let parent = sheet.sheetParent ?? window {
                parent.endSheet(sheet)
            } else {
                sheet.orderOut(nil)
            }
        }
        // 中身が画面より高くならないようにする(超えた分は中でスクロールする)
        let visibleHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let root = content(close).environment(\.sheetBodyMaxHeight, max(220, visibleHeight - 230))
        let host = NSHostingController(rootView: root)
        if size != nil { host.sizingOptions = [.minSize] }
        sheet.contentViewController = host
        if let size {
            sheet.setContentSize(size)
        } else {
            let fitting = host.view.fittingSize
            if fitting.width >= 1, fitting.height >= 1 { sheet.setContentSize(fitting) }
        }
        let key = ObjectIdentifier(sheet)
        openSheets[key] = sheet
        window.beginSheet(sheet) { _ in
            // ボタンの処理の途中で窓を放さないよう、次の回で放す
            Task { @MainActor in openSheets[key] = nil }
        }
    }

    /// 入力中の欄の値を確定させる(数値の欄は Return を押すか欄を離れたときに値が入るため、OK の前に呼ぶ)。
    /// 出しているシートの 1 行の欄だけを対象にする(データの編集の欄はそのまま)
    static func endEditing() {
        for window in openSheets.values where window.isVisible {
            guard let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { continue }
            if !window.makeFirstResponder(nil) { window.endEditing(for: nil) }
        }
    }

    // MARK: - 窓から呼ぶシート

    /// 曲線を求める解析(最小二乗・スプライン・関数)の条件。OK で done(変えた系列)
    static func analysisConditions(_ s: Series, title: String, over window: NSWindow, done: @escaping (Series) -> Void) {
        present(over: window) { close in
            AnalysisView(series: s, title: title, close: close, done: done)
        }
    }

    /// ガウス関数・ローレンツ関数による当てはめの条件。OK で done(変えた系列)
    static func peakFit(_ s: Series, title: String, over window: NSWindow, done: @escaping (Series) -> Void) {
        present(over: window) { close in
            PeakFitView(series: s, title: title, close: close, done: done)
        }
    }

    /// 定数 a〜i
    static func constants(_ values: [Double], over window: NSWindow, done: @escaping ([Double]) -> Void) {
        present(over: window) { close in
            ConstantsView(values: values, close: close, done: done)
        }
    }

    /// データ(系列)を選ぶ。multiple なら複数選べる。OK のときだけ done(選んだ番号)
    static func chooseSeries(title: String, message: String, items: [Series], multiple: Bool, preselected: IndexSet,
                             over window: NSWindow, done: @escaping (IndexSet) -> Void) {
        present(over: window) { close in
            ChooseSeriesView(title: title, message: message, items: items, multiple: multiple, preselected: preselected,
                             close: close, done: done)
        }
    }

    /// データファイルの行をそのまま編集する。保存で done(新しい中身)
    static func editData(name: String, text: String, over window: NSWindow, done: @escaping (String) -> Void) {
        present(over: window, resizableWith: NSSize(width: 680, height: 520)) { close in
            EditDataView(name: name, text: text, close: close, done: done)
        }
    }

    /// 解析の結果。「グラフに文字で入れる」で insertAsText を呼んで閉じる
    static func results(title: String, lines: [String], over window: NSWindow, insertAsText: @escaping () -> Void) {
        present(over: window) { close in
            ResultsView(title: title, lines: lines, close: close, insertAsText: insertAsText)
        }
    }

    /// 1 行の入力
    static func input(title: String, message: String, text: String, over window: NSWindow, done: @escaping (String) -> Void) {
        present(over: window) { close in
            InputView(title: title, message: message, text: text, close: close, done: done)
        }
    }

    /// 図をコピーする前に、余白(mm)・倍率(%)・解像度(dpi)を決める
    static func copyOptions(over window: NSWindow, done: @escaping (Double, Double, Double) -> Void) {
        present(over: window) { close in
            CopyOptionsView(close: close, done: done)
        }
    }

    /// 用紙の大きさと向き、印刷の倍率
    static func paper(_ page: PageSetup, over window: NSWindow, done: @escaping (PageSetup) -> Void) {
        present(over: window) { close in
            PaperView(page: page, close: close, done: done)
        }
    }
}
