import AppKit
import SMPKit

/// メニューバー(Mac の並び: アプリ・ファイル・編集・表示・挿入・グラフ・データ・解析・ウインドウ・ヘルプ)
@MainActor
enum MainMenuBuilder {
    typealias W = GraphWindowController
    typealias A = AppDelegate

    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(insertMenu()))
        main.addItem(submenu(graphMenu()))
        main.addItem(submenu(dataMenu()))
        let analysis = analysisMenu()
        analysis.title = "解析"
        main.addItem(submenu(analysis))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = helpMenu()
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ m: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: m.title, action: nil, keyEquivalent: "")
        item.submenu = m
        return item
    }

    @discardableResult
    static func item(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                     _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0, symbol: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { i.keyEquivalentModifierMask = mods }
        i.tag = tag
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(i)
        return i
    }

    private static func sub(_ menu: NSMenu, _ title: String, symbol: String? = nil, _ fill: (NSMenu) -> Void) {
        let m = NSMenu(title: title)
        fill(m)
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        i.submenu = m
        menu.addItem(i)
    }

    // MARK: -

    static func appMenu() -> NSMenu {
        let m = NSMenu(title: "SmaC")
        item(m, "SmaC について", #selector(A.showAbout(_:)))
        m.addItem(.separator())
        item(m, "設定…", #selector(A.showSettings(_:)), ",")
        m.addItem(.separator())
        let services = NSMenu(title: "サービス")
        let s = NSMenuItem(title: "サービス", action: nil, keyEquivalent: "")
        s.submenu = services
        m.addItem(s)
        NSApp.servicesMenu = services
        m.addItem(.separator())
        item(m, "SmaC を隠す", #selector(NSApplication.hide(_:)), "h")
        item(m, "ほかを隠す", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        item(m, "すべてを表示", #selector(NSApplication.unhideAllApplications(_:)))
        m.addItem(.separator())
        item(m, "SmaC を終了", #selector(NSApplication.terminate(_:)), "q")
        return m
    }

    static func fileMenu() -> NSMenu {
        let m = NSMenu(title: "ファイル")
        item(m, "新規", #selector(NSDocumentController.newDocument(_:)), "n")
        item(m, "開く…", #selector(NSDocumentController.openDocument(_:)), "o")
        let recent = NSMenu(title: "最近使った項目を開く")
        item(recent, "メニューを消去", #selector(NSDocumentController.clearRecentDocuments(_:)))
        let r = NSMenuItem(title: "最近使った項目を開く", action: nil, keyEquivalent: "")
        r.submenu = recent
        m.addItem(r)
        m.addItem(.separator())
        item(m, "閉じる", #selector(NSWindow.performClose(_:)), "w")
        item(m, "保存", #selector(NSDocument.save(_:)), "s")
        item(m, "別名で保存…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
        item(m, "このグラフだけ保存…", #selector(W.saveActiveGraphAs(_:)))
        item(m, "保存した状態に戻す", #selector(NSDocument.revertToSaved(_:)))
        m.addItem(.separator())
        item(m, "グラフを読み込む…", #selector(W.importGraphs(_:)))
        sub(m, "書き出す") { e in
            item(e, "PDF…", #selector(W.exportPDF(_:)), "e", [.command, .option])
            item(e, "PNG…", #selector(W.exportPNG(_:)))
            e.addItem(.separator())
            item(e, "変換した値…", #selector(W.exportValues(_:)))
        }
        m.addItem(.separator())
        item(m, "用紙…", #selector(W.paperSetup(_:)))
        item(m, "ページ設定…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift])
        item(m, "プリント…", #selector(NSDocument.printDocument(_:)), "p")
        return m
    }

    static func editMenu() -> NSMenu {
        let m = NSMenu(title: "編集")
        item(m, "取り消す", Selector(("undo:")), "z")
        item(m, "やり直す", Selector(("redo:")), "z", [.command, .shift])
        m.addItem(.separator())
        item(m, "カット", #selector(W.cut(_:)), "x")
        item(m, "コピー", #selector(W.copy(_:)), "c")
        item(m, "ペースト", #selector(W.paste(_:)), "v")
        item(m, "削除", #selector(W.delete(_:)))
        item(m, "すべてを選択", #selector(NSResponder.selectAll(_:)), "a")
        m.addItem(.separator())
        item(m, "図としてコピー", #selector(W.copyAsImage(_:)), "c", [.command, .option])
        item(m, "余白と解像度を決めてコピー…", #selector(W.copyWithOptions(_:)))
        item(m, "クリップボードの値をデータにする", #selector(W.pasteAsData(_:)))
        m.addItem(.separator())
        item(m, "最前面へ", #selector(W.bringToFront(_:)), "f", [.command, .shift])
        item(m, "最背面へ", #selector(W.sendToBack(_:)), "b", [.command, .shift])
        sub(m, "文字をそろえる") { a in
            item(a, "左", #selector(W.alignTexts(_:)), tag: 0)
            item(a, "中央", #selector(W.alignTexts(_:)), tag: 1)
            item(a, "右", #selector(W.alignTexts(_:)), tag: 2)
        }
        return m
    }

    static func viewMenu() -> NSMenu {
        let m = NSMenu(title: "表示")
        item(m, "サイドバーを表示/隠す", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control])
        item(m, "インスペクタを表示/隠す", #selector(NSSplitViewController.toggleInspector(_:)), "i", [.command, .option])
        m.addItem(.separator())
        item(m, "拡大", #selector(W.zoomIn(_:)), "+")
        item(m, "縮小", #selector(W.zoomOut(_:)), "-")
        item(m, "実寸", #selector(W.zoomActualSize(_:)), "0")
        item(m, "紙の大きさに合わせる", #selector(W.zoomToFitPage(_:)), "9")
        m.addItem(.separator())
        item(m, "このグラフだけ表示", #selector(W.showActiveGraphOnly(_:)))
        item(m, "すべてのグラフを表示", #selector(W.showAllGraphs(_:)))
        item(m, "方眼を表示", #selector(W.toggleGrid(_:)))
        m.addItem(.separator())
        item(m, "データを読み直す", #selector(W.reloadData(_:)), "r")
        m.addItem(.separator())
        item(m, "ツールバーを表示/隠す", #selector(NSWindow.toggleToolbarShown(_:)), "t", [.command, .option])
        item(m, "ツールバーをカスタマイズ…", #selector(NSWindow.runToolbarCustomizationPalette(_:)))
        m.addItem(.separator())
        item(m, "フルスクリーンにする", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        return m
    }

    static func insertMenu() -> NSMenu {
        let m = NSMenu(title: "挿入")
        item(m, "文字", #selector(W.insertTextBox(_:)), "t", symbol: "textformat")
        sub(m, "軸の題", symbol: "character.textbox") { t in
            item(t, "X 軸の題", #selector(W.insertAxisTitle(_:)), tag: 4)
            item(t, "Y 軸の題", #selector(W.insertAxisTitle(_:)), tag: 5)
            item(t, "上の軸の題", #selector(W.insertAxisTitle(_:)), tag: 6)
            item(t, "右の軸の題", #selector(W.insertAxisTitle(_:)), tag: 7)
        }
        item(m, "凡例", #selector(W.insertLegend(_:)), symbol: "list.bullet.rectangle")
        m.addItem(.separator())
        fillShapes(m)
        m.addItem(.separator())
        item(m, "クリップボードの文字", #selector(W.insertClipboardText(_:)))
        return m
    }

    private static func fillShapes(_ m: NSMenu) {
        item(m, "矢印", #selector(W.insertArrow(_:)), symbol: "arrow.up.right")
        item(m, "線", #selector(W.insertLine(_:)), symbol: "line.diagonal")
        item(m, "枠", #selector(W.insertBox(_:)), symbol: "rectangle")
        item(m, "点", #selector(W.insertDot(_:)), symbol: "smallcircle.filled.circle")
        item(m, "図…", #selector(W.insertPicture(_:)), symbol: "photo")
    }

    /// ツールバーの「図形」
    static func shapeMenu() -> NSMenu {
        let m = NSMenu(title: "図形")
        fillShapes(m)
        return m
    }

    /// ツールバーの「書き出す」
    static func exportMenu() -> NSMenu {
        let m = NSMenu(title: "書き出す")
        item(m, "PDF に書き出す…", #selector(W.exportPDF(_:)), symbol: "doc.richtext")
        item(m, "PNG に書き出す…", #selector(W.exportPNG(_:)), symbol: "photo")
        m.addItem(.separator())
        item(m, "図としてコピー", #selector(W.copyAsImage(_:)), symbol: "doc.on.doc")
        item(m, "余白と解像度を決めてコピー…", #selector(W.copyWithOptions(_:)))
        return m
    }

    static func graphMenu() -> NSMenu {
        let m = NSMenu(title: "グラフ")
        item(m, "グラフを加える", #selector(W.addGraph(_:)), "n", [.command, .option])
        item(m, "グラフを複製", #selector(W.duplicateGraph(_:)))
        item(m, "グラフを削除", #selector(W.deleteGraph(_:)))
        let list = NSMenu(title: "グラフを選ぶ")
        list.delegate = GraphListMenu.shared
        let l = NSMenuItem(title: "グラフを選ぶ", action: nil, keyEquivalent: "")
        l.submenu = list
        m.addItem(l)
        m.addItem(.separator())
        item(m, "範囲を合わせる", #selector(W.autoRangeAll(_:)), "r", [.command, .shift])
        sub(m, "軸ごとに範囲を合わせる") { a in
            item(a, "X 軸", #selector(W.autoRangeAxis(_:)), tag: 0)
            item(a, "Y 軸", #selector(W.autoRangeAxis(_:)), tag: 1)
            item(a, "上の軸", #selector(W.autoRangeAxis(_:)), tag: 2)
            item(a, "右の軸", #selector(W.autoRangeAxis(_:)), tag: 3)
        }
        item(m, "囲んだ範囲を表示", #selector(W.beginZoomRect(_:)))
        m.addItem(.separator())
        item(m, "囲んだ点を除く", #selector(W.beginMaskRect(_:)))
        item(m, "除いた点をすべて戻す", #selector(W.clearMasks(_:)))
        m.addItem(.separator())
        item(m, "既定のグラフにする", #selector(W.saveAsDefaultGraph(_:)))
        return m
    }

    static func dataMenu() -> NSMenu {
        let m = NSMenu(title: "データ")
        item(m, "データを追加…", #selector(W.addData(_:)), "d", [.command, .shift])
        item(m, "新しいデータ…", #selector(W.newData(_:)))
        item(m, "データを編集…", #selector(W.editData(_:)))
        m.addItem(.separator())
        item(m, "表示するデータを選ぶ…", #selector(W.chooseVisibleSeries(_:)))
        item(m, "値を読む", #selector(W.toggleReadValues(_:)), "l")
        item(m, "値をコピー", #selector(W.copyValues(_:)))
        m.addItem(.separator())
        item(m, "データを取り除く", #selector(W.removeSelectedSeries(_:)))
        return m
    }

    /// 解析(メニューバーとツールバーで同じ並び)
    static func analysisMenu() -> NSMenu {
        let m = NSMenu(title: "解析")
        sub(m, "最小二乗で当てはめる") { l in
            item(l, "多項式…", #selector(W.leastSquares(_:)), tag: Series.Kind.polynomialLSQ.rawValue)
            item(l, "指数関数…", #selector(W.leastSquares(_:)), tag: Series.Kind.expLSQ.rawValue)
            item(l, "対数関数…", #selector(W.leastSquares(_:)), tag: Series.Kind.logLSQ.rawValue)
            item(l, "べき関数…", #selector(W.leastSquares(_:)), tag: Series.Kind.powerLSQ.rawValue)
            item(l, "一般の関数…", #selector(W.leastSquares(_:)), tag: Series.Kind.generalLSQ.rawValue)
        }
        sub(m, "スプライン補間") { s in
            for mode in Spline.Mode.allCases {
                item(s, mode.displayTitle + "…", #selector(W.spline(_:)), tag: mode.rawValue)
            }
        }
        sub(m, "ピーク") { p in
            for a in [ExtensionAnalysis.gaussian, .lorentzian, .peakDetect] {
                item(p, a.displayTitle + (a.usesFittingDialog ? "…" : ""), #selector(W.extensionAnalysis(_:)),
                     tag: ExtensionAnalysis.allCases.firstIndex(of: a) ?? 0)
            }
        }
        for a in [ExtensionAnalysis.getMax, .getMin, .smoothing] {
            item(m, a.displayTitle, #selector(W.extensionAnalysis(_:)), tag: ExtensionAnalysis.allCases.firstIndex(of: a) ?? 0)
        }
        item(m, "関数を描く…", #selector(W.drawFunction(_:)))
        m.addItem(.separator())
        item(m, "条件を変える…", #selector(W.refitSeries(_:)))
        item(m, "結果を見る…", #selector(W.showResultsSheet(_:)))
        item(m, "式で値を求める…", #selector(W.evaluateFit(_:)))
        item(m, "曲線の値をコピー", #selector(W.copyCurveValues(_:)))
        item(m, "解析をやめる", #selector(W.clearSeriesAnalysis(_:)))
        m.addItem(.separator())
        item(m, "定数 a〜i…", #selector(W.showConstants(_:)))
        return m
    }

    static func windowMenu() -> NSMenu {
        let m = NSMenu(title: "ウインドウ")
        item(m, "しまう", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(m, "拡大/縮小", #selector(NSWindow.performZoom(_:)))
        m.addItem(.separator())
        item(m, "すべてを手前に移動", #selector(NSApplication.arrangeInFront(_:)))
        return m
    }

    static func helpMenu() -> NSMenu {
        let m = NSMenu(title: "ヘルプ")
        item(m, "SmaC ヘルプ", #selector(A.showHelp(_:)), "?")
        return m
    }
}

/// 「グラフを選ぶ」の中身(開くたびに作り直す)
@MainActor
final class GraphListMenu: NSObject, NSMenuDelegate {
    static let shared = GraphListMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let doc = (NSApp.mainWindow?.windowController as? GraphWindowController)?.doc
        guard let doc else {
            menu.addItem(NSMenuItem(title: "(グラフがありません)", action: nil, keyEquivalent: ""))
            return
        }
        for (i, g) in doc.project.graphs.enumerated() {
            let name = (g.name as NSString).deletingPathExtension
            let item = NSMenuItem(title: "グラフ \(i + 1)" + (name.isEmpty ? "" : "  \(name)"),
                                  action: #selector(GraphWindowController.selectGraph(_:)), keyEquivalent: "")
            item.tag = i
            menu.addItem(item)
        }
    }
}
