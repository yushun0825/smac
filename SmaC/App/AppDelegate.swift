import AppKit
import SwiftUI
import SMPKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 最初に作った NSDocumentController が使われる
        _ = SmaCDocumentController()
        NSApp.mainMenu = MainMenuBuilder.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SnapshotRunner.isActive { SnapshotRunner.run(); return }
        if SelfTestRunner.isActive { SelfTestRunner.run(); return }
        NSApp.activate()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !SnapshotRunner.isActive && !SelfTestRunner.isActive }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationDidBecomeActive(_ notification: Notification) {
        // ほかのアプリで直したデータファイルを読み直す
        for doc in NSDocumentController.shared.documents.compactMap({ $0 as? GraphDocument }) {
            doc.reloadChangedDataFiles(force: false)
        }
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(
            string: "散布図・最小二乗・スプライン補間のグラフを作る Mac のアプリです。\nSMP 形式のグラフを開いて保存できます。",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc func showSettings(_ sender: Any?) {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: SettingsView(settings: AppSettings.shared))
        let w = NSWindow(contentViewController: host)
        w.title = "設定"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        w.setFrameAutosaveName("SmaCSettings")
        settingsWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    @objc func showHelp(_ sender: Any?) { HelpWindow.show() }
}
