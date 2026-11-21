import AppKit
import SMPKit

extension NSToolbarItem.Identifier {
    static let addData = NSToolbarItem.Identifier("smac.addData")
    static let insertText = NSToolbarItem.Identifier("smac.insertText")
    static let insertShape = NSToolbarItem.Identifier("smac.insertShape")
    static let insertLegend = NSToolbarItem.Identifier("smac.insertLegend")
    static let analysis = NSToolbarItem.Identifier("smac.analysis")
    static let readValues = NSToolbarItem.Identifier("smac.readValues")
    static let zoomRect = NSToolbarItem.Identifier("smac.zoomRect")
    static let autoRange = NSToolbarItem.Identifier("smac.autoRange")
    static let zoom = NSToolbarItem.Identifier("smac.zoom")
    static let export = NSToolbarItem.Identifier("smac.export")
}

extension GraphWindowController: NSToolbarDelegate, NSToolbarItemValidation {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator,
         .addData, .space, .insertText, .insertShape, .insertLegend, .space,
         .analysis, .readValues, .zoomRect, .autoRange,
         .flexibleSpace, .zoom, .export,
         .inspectorTrackingSeparator, .flexibleSpace, .toggleInspector]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .inspectorTrackingSeparator, .toggleInspector,
         .addData, .insertText, .insertShape, .insertLegend, .analysis, .readValues, .zoomRect, .autoRange, .zoom, .export,
         .space, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        typealias W = GraphWindowController
        switch id {
        case .addData:
            return button(id, "データを追加", "doc.badge.plus", #selector(W.addData(_:)), "データファイルを開いて、このグラフに加えます")
        case .insertText:
            return button(id, "文字", "textformat", #selector(W.insertTextBox(_:)), "文字を入れます")
        case .insertShape:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "図形"
            item.paletteLabel = "図形"
            item.toolTip = "矢印・線・枠・点・図を入れます"
            item.image = NSImage(systemSymbolName: "square.on.circle", accessibilityDescription: "図形")
            item.menu = MainMenuBuilder.shapeMenu()
            item.showsIndicator = true
            return item
        case .insertLegend:
            return button(id, "凡例", "list.bullet.rectangle", #selector(W.insertLegend(_:)), "データの見本と名前を並べた凡例を入れます")
        case .analysis:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "解析"
            item.paletteLabel = "解析"
            item.toolTip = "当てはめ・補間・関数の描画"
            item.image = NSImage(systemSymbolName: "function", accessibilityDescription: "解析")
            item.menu = MainMenuBuilder.analysisMenu()
            item.showsIndicator = true
            return item
        case .readValues:
            return toggle(id, "値を読む", "scope", #selector(W.toggleReadValues(_:)), "グラフの点の値を読みます")
        case .zoomRect:
            return toggle(id, "範囲を囲む", "crop", #selector(W.beginZoomRect(_:)), "囲んだ範囲を軸の範囲にします")
        case .autoRange:
            return button(id, "範囲を合わせる", "arrow.up.left.and.arrow.down.right", #selector(W.autoRangeAll(_:)),
                          "軸の範囲をデータに合わせます")
        case .zoom:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = "拡大/縮小"
            item.paletteLabel = "拡大/縮小"
            let b = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 86, height: 24), pullsDown: true)
            b.bezelStyle = .toolbar
            b.addItem(withTitle: "100%")
            for (title, tag) in [("50%", 50), ("75%", 75), ("100%", 100), ("125%", 125), ("150%", 150), ("200%", 200), ("300%", 300), ("400%", 400)] {
                b.addItem(withTitle: title)
                b.lastItem?.tag = tag
            }
            b.menu?.addItem(.separator())
            b.addItem(withTitle: "紙の大きさに合わせる")
            b.lastItem?.tag = -1
            b.target = self
            b.action = #selector(W.zoomPopupChanged(_:))
            item.view = b
            item.toolTip = "表示の大きさ"
            zoomButton = b
            refreshZoomButton()
            return item
        case .export:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "書き出す"
            item.paletteLabel = "書き出す"
            item.toolTip = "PDF・PNG に書き出す、図としてコピーする"
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "書き出す")
            item.menu = MainMenuBuilder.exportMenu()
            item.showsIndicator = true
            return item
        default:
            return nil
        }
    }

    private func button(_ id: NSToolbarItem.Identifier, _ label: String, _ symbol: String, _ action: Selector, _ tip: String) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.paletteLabel = label
        item.toolTip = tip
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.action = action
        item.target = nil
        item.isBordered = true
        return item
    }

    /// 押すと入ったままになるボタン(もう一度押すと切れる)
    private func toggle(_ id: NSToolbarItem.Identifier, _ label: String, _ symbol: String, _ action: Selector, _ tip: String) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.paletteLabel = label
        item.toolTip = tip
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(), target: nil, action: action)
        b.bezelStyle = .toolbar
        b.setButtonType(.pushOnPushOff)
        b.imagePosition = .imageOnly
        b.setAccessibilityLabel(label)
        b.toolTip = tip
        item.view = b
        toggleButtons[id] = b
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard let action = item.action else { return true }
        return isActionEnabled(action)
    }

    /// 押せるか・入っているかを決め直す(書類や選択が変わるたび)
    func refreshToolbar() {
        if let b = toggleButtons[.readValues] {
            b.state = canvas.mode == .readValue ? .on : .off
            b.isEnabled = isActionEnabled(#selector(toggleReadValues(_:)))
        }
        if let b = toggleButtons[.zoomRect] {
            b.state = canvas.mode == .zoomRect ? .on : .off
            b.isEnabled = isActionEnabled(#selector(beginZoomRect(_:)))
        }
        window?.toolbar?.validateVisibleItems()
    }

    @objc func zoomPopupChanged(_ sender: NSPopUpButton) {
        guard let tag = sender.selectedItem?.tag else { return }
        if tag == -1 { zoomToFit() } else if tag > 0 { setMagnification(CGFloat(tag) / 100) }
        refreshZoomButton()
    }
}
