import AppKit
import SMPKit

/// 確かめる用: 画面に出さずに、窓と作業面を PNG にして終わる。
/// SMAC_TEST_INPUT=入力 SMAC_TEST_OUTPUT=出力フォルダ SmaC --snapshot
/// (ファイルの場所を引数にすると AppKit が書類として開こうとするので、環境変数で渡す)
@MainActor
enum SnapshotRunner {
    static var isActive: Bool { CommandLine.arguments.contains("--snapshot") }

    static func run() {
        let env = ProcessInfo.processInfo.environment
        guard let inPath = env["SMAC_TEST_INPUT"], let outPath = env["SMAC_TEST_OUTPUT"] else { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        let input = URL(fileURLWithPath: inPath)
        let outDir = URL(fileURLWithPath: outPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        DispatchQueue.main.async {
            do {
                let dc = NSDocumentController.shared
                let type = try dc.typeForContents(of: input)
                guard let doc = try dc.makeDocument(withContentsOf: input, ofType: type) as? GraphDocument else { throw CocoaError(.fileReadUnknown) }
                doc.makeWindowControllers()
                guard let wc = doc.windowControllers.first as? GraphWindowController, let window = wc.window else { throw CocoaError(.fileReadUnknown) }
                window.setFrame(NSRect(x: -9000, y: -9000, width: 1240, height: 800), display: true)
                window.orderFrontRegardless()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
                wc.zoomToFit()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
                WindowCapture.save(window.contentView, to: outDir.appendingPathComponent("window.png"))
                WindowCapture.saveLayers(window, to: outDir.appendingPathComponent("window_layers.png"))
                if let g = doc.activeGraph, !g.series.isEmpty {
                    wc.state.select(.series(graph: 0, index: 0))
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
                    WindowCapture.saveLayers(window, to: outDir.appendingPathComponent("window_series.png"))
                    for (i, item) in wc.splitController.splitViewItems.enumerated() where i != 1 {
                        WindowCapture.save(item.viewController.view, to: outDir.appendingPathComponent("pane\(i).png"))
                    }
                    // サイドバーの一覧の行(画像に写らないときに数で確かめる)
                    for t in WindowCapture.tables(in: wc.splitController.splitViewItems[0].viewController.view) {
                        print("sidebar rows: \(t.numberOfRows)")
                        WindowCapture.save(t, to: outDir.appendingPathComponent("sidebar_table.png"))
                    }
                    wc.state.seriesTab = 1
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
                    WindowCapture.saveLayers(window, to: outDir.appendingPathComponent("window_series_style.png"))
                    wc.state.seriesTab = 0
                    wc.state.graphTab = 1
                    wc.state.select(.graph(0))
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
                    WindowCapture.saveLayers(window, to: outDir.appendingPathComponent("window_axis.png"))
                }
                WindowCapture.save(wc.canvas, to: outDir.appendingPathComponent("canvas.png"))
                if let g = doc.activeGraph, let id = g.objects.first?.id {
                    wc.canvas.selection = [id]
                    WindowCapture.save(wc.canvas, to: outDir.appendingPathComponent("canvas_selected.png"))
                    wc.canvas.selection = []
                }
                window.orderOut(nil)
                print("snapshot ok: \(outDir.path)")
            } catch {
                print("snapshot error: \(error)")
            }
            NSApp.terminate(nil)
        }
    }
}

/// ビューを PNG にする(確かめる用)
@MainActor
enum WindowCapture {
    static func save(_ view: NSView?, to url: URL) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// ビューの中の表(サイドバーの一覧は画像に写らないことがあるので、表を直接写す)
    static func tables(in v: NSView) -> [NSTableView] {
        if let t = v as? NSTableView { return [t] }
        return v.subviews.flatMap { tables(in: $0) }
    }

    /// 窓の枠ごと(サイドバーなどの層も)描く
    static func saveLayers(_ window: NSWindow, to url: URL) {
        guard let frameView = window.contentView?.superview, let layer = frameView.layer else { return }
        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        let scale = window.backingScaleFactor
        let size = frameView.bounds.size
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        ctx.scaleBy(x: scale, y: scale)
        if layer.isGeometryFlipped || frameView.isFlipped {
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        layer.render(in: ctx)
        guard let img = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
