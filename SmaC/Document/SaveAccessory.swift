import AppKit

/// 保存の窓の下に付ける「データも一緒に保存する」
@MainActor
enum SaveAccessory {
    static func make() -> NSView {
        let check = NSButton(checkboxWithTitle: "データも一緒に保存する(データファイルがなくても開けるように)",
                             target: SaveAccessoryTarget.shared, action: #selector(SaveAccessoryTarget.toggle(_:)))
        check.state = AppSettings.shared.saveDataWithGraph ? .on : .off
        let stack = NSStackView(views: [check])
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        stack.frame = NSRect(x: 0, y: 0, width: 460, height: 40)
        return stack
    }
}

@MainActor
final class SaveAccessoryTarget: NSObject {
    static let shared = SaveAccessoryTarget()

    @objc func toggle(_ sender: NSButton) {
        AppSettings.shared.saveDataWithGraph = sender.state == .on
    }
}
