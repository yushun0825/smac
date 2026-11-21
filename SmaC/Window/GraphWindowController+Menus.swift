import AppKit
import SMPKit

/// メニューの有効・無効、作業面の右クリックのメニュー
extension GraphWindowController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return true }
        switch action {
        case #selector(toggleReadValues(_:)): item.state = canvas.mode == .readValue ? .on : .off
        case #selector(beginZoomRect(_:)): item.state = canvas.mode == .zoomRect ? .on : .off
        case #selector(beginMaskRect(_:)): item.state = canvas.mode == .maskRect ? .on : .off
        case #selector(showActiveGraphOnly(_:)): item.state = doc?.soloGraph != nil ? .on : .off
        case #selector(toggleGrid(_:)): item.state = AppSettings.shared.gridMM > 0 ? .on : .off
        case #selector(selectGraph(_:)): item.state = item.tag == gi ? .on : .off
        default: break
        }
        return isActionEnabled(action, tag: item.tag)
    }

    func isActionEnabled(_ action: Selector, tag: Int = 0) -> Bool {
        guard let doc, let g = doc.activeGraph else { return false }
        let hasSeries = !g.series.isEmpty
        let dataSeries = g.series.contains { $0.kind != .function }
        let hasSelection = !canvas.selection.isEmpty
        let pb = NSPasteboard.general
        switch action {
        case #selector(cut(_:)), #selector(bringToFront(_:)), #selector(sendToBack(_:)):
            return hasSelection
        case #selector(delete(_:)):
            if hasSelection { return true }
            switch state.selection {
            case .series: return true
            case .graph: return doc.project.graphs.count > 1
            default: return false
            }
        case #selector(alignTexts(_:)):
            return selectedTexts().count >= 2
        case #selector(paste(_:)):
            return pb.availableType(from: [GraphWindowController.objectPasteboardType, .string]) != nil
        case #selector(pasteAsData(_:)), #selector(insertClipboardText(_:)):
            return pb.availableType(from: [.string]) != nil
        case #selector(selectAll(_:)):
            return !g.objects.isEmpty
        case #selector(toggleReadValues(_:)), #selector(copyValues(_:)), #selector(exportValues(_:)),
             #selector(chooseVisibleSeries(_:)), #selector(insertLegend(_:)), #selector(beginMaskRect(_:)),
             #selector(removeSelectedSeries(_:)):
            return hasSeries
        case #selector(editData(_:)), #selector(leastSquares(_:)), #selector(spline(_:)), #selector(extensionAnalysis(_:)):
            return dataSeries
        case #selector(refitSeries(_:)), #selector(showResultsSheet(_:)):
            return g.series.contains { $0.kind != .normal || $0.extensionAnalysis != nil }
        case #selector(clearSeriesAnalysis(_:)):
            return g.series.contains { ($0.kind != .normal && $0.kind != .function) || $0.extensionAnalysis != nil }
        case #selector(evaluateFit(_:)):
            return g.series.contains { $0.kind.isLSQ }
        case #selector(copyCurveValues(_:)):
            return g.series.contains { $0.hasCurve }
        case #selector(clearMasks(_:)):
            return !g.masks.isEmpty
        case #selector(showAllGraphs(_:)):
            return doc.soloGraph != nil
        case #selector(showActiveGraphOnly(_:)):
            return doc.project.graphs.count > 1
        case #selector(deleteGraph(_:)):
            return doc.project.graphs.count > 1 || !g.series.isEmpty || !g.objects.isEmpty
        case #selector(autoRangeAxis(_:)):
            return tag < 2 || (tag == 2 && g.uIndependent) || (tag == 3 && g.rIndependent)
        case #selector(zoomIn(_:)):
            return scrollView.magnification < scrollView.maxMagnification - 0.001
        case #selector(zoomOut(_:)):
            return scrollView.magnification > scrollView.minMagnification + 0.001
        default:
            return true
        }
    }

    // MARK: - 右クリックのメニュー

    func contextMenu(for hit: CanvasView.Hit) -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ action: Selector, tag: Int = 0) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.tag = tag
            i.target = self
            m.addItem(i)
        }
        switch hit {
        case .object, .arrowEnd, .corner:
            add("カット", #selector(cut(_:)))
            add("コピー", #selector(copy(_:)))
            add("削除", #selector(delete(_:)))
            m.addItem(.separator())
            add("最前面へ", #selector(bringToFront(_:)))
            add("最背面へ", #selector(sendToBack(_:)))
            if selectedTexts().count >= 2 {
                m.addItem(.separator())
                add("左をそろえる", #selector(alignTexts(_:)), tag: 0)
                add("中央をそろえる", #selector(alignTexts(_:)), tag: 1)
                add("右をそろえる", #selector(alignTexts(_:)), tag: 2)
            }
        case .none:
            add("ペースト", #selector(paste(_:)))
            m.addItem(.separator())
            add("グラフを加える", #selector(addGraph(_:)))
            add("図としてコピー", #selector(copyAsImage(_:)))
        default:
            add("データを追加…", #selector(addData(_:)))
            m.addItem(.separator())
            add("文字", #selector(insertTextBox(_:)))
            add("凡例", #selector(insertLegend(_:)))
            add("矢印", #selector(insertArrow(_:)))
            add("枠", #selector(insertBox(_:)))
            m.addItem(.separator())
            add("範囲を合わせる", #selector(autoRangeAll(_:)))
            add("囲んだ範囲を表示", #selector(beginZoomRect(_:)))
            add("囲んだ点を除く", #selector(beginMaskRect(_:)))
            m.addItem(.separator())
            add("図としてコピー", #selector(copyAsImage(_:)))
            add("ペースト", #selector(paste(_:)))
        }
        return m
    }

    /// 右ボタンのドラッグで囲んだ範囲のメニュー
    func showRegionMenu(pageRect r: CGRect, event: NSEvent, in view: NSView) {
        let m = NSMenu()
        let handler = RegionMenuHandler(controller: self, rect: r)
        for (title, tag) in [("この範囲を図としてコピー", 0), ("この範囲を PDF に書き出す…", 1)] {
            let i = NSMenuItem(title: title, action: #selector(RegionMenuHandler.run(_:)), keyEquivalent: "")
            i.target = handler; i.tag = tag; m.addItem(i)
        }
        m.addItem(.separator())
        for (title, tag) in [("この範囲を表示する", 2), ("この範囲の点を除く", 3)] {
            let i = NSMenuItem(title: title, action: #selector(RegionMenuHandler.run(_:)), keyEquivalent: "")
            i.target = handler; i.tag = tag; m.addItem(i)
        }
        objc_setAssociatedObject(m, &RegionMenuHandler.key, handler, .OBJC_ASSOCIATION_RETAIN)
        NSMenu.popUpContextMenu(m, with: event, for: view)
    }

    func regionAction(_ tag: Int, rect r: CGRect) {
        guard let doc, let window else { return }
        switch tag {
        case 0: putFigureOnPasteboard(renderer: doc.renderer(), rect: r)
        case 1:
            let panel = NSSavePanel()
            panel.nameFieldStringValue = exportBaseName() + ".pdf"
            panel.allowedContentTypes = [.pdf]
            let renderer = doc.renderer()
            panel.beginSheetModal(for: window) { [weak self] res in
                guard res == .OK, let url = panel.url else { return }
                do { try GraphExporter.pdfData(renderer: renderer, rect: r).write(to: url) }
                catch { self?.alert("書き出せませんでした", error.localizedDescription) }
            }
        case 2: applyZoomRect(pageRect: r)
        case 3: applyMaskRect(pageRect: r)
        default: break
        }
    }
}

/// 右ボタンで囲んだ範囲のメニューの受け手
@MainActor
final class RegionMenuHandler: NSObject {
    nonisolated(unsafe) static var key: UInt8 = 0
    weak var controller: GraphWindowController?
    let rect: CGRect

    init(controller: GraphWindowController, rect: CGRect) {
        self.controller = controller
        self.rect = rect
    }

    @objc func run(_ sender: NSMenuItem) { controller?.regionAction(sender.tag, rect: rect) }
}
