import SwiftUI
import AppKit
import SMPKit

extension Sheets {
    // MARK: - 図をコピー

    /// 図をコピーする前に、余白・倍率・解像度を決める(次に開いたときは今回の値から始める)
    struct CopyOptionsView: View {
        let close: () -> Void
        let done: (Double, Double, Double) -> Void
        @State private var margin = AppSettings.shared.copyMarginMM
        @State private var scale = AppSettings.shared.stored(CopyOptionsView.scaleKey, as: Double.self) ?? 100
        @State private var dpi = AppSettings.shared.exportDPI
        @State private var finished = false

        static let scaleKey = "copy.scalePercent"

        var body: some View {
            Scaffold(title: "図をコピー", message: "グラフを図にしてクリップボードにコピーします。", width: 400) {
                Form {
                    Section {
                        NumberRow(label: "周りの余白", value: $margin, unit: "mm", width: 80)
                        NumberRow(label: "倍率", value: $scale, unit: "%", width: 80)
                        NumberRow(label: "解像度", value: $dpi, unit: "dpi", width: 80)
                    } footer: {
                        Text("解像度は、画像として貼り付けるときの細かさです。")
                    }
                }
                .formStyle(.grouped)
                .labeledContentStyle(RowStyle())
                .onSubmit { finish() }
            } trailing: {
                CancelButton(close: close)
                DefaultButton(title: "コピー") { finish() }
            }
        }

        private func finish() {
            Sheets.endEditing()
            guard !finished else { return }
            finished = true
            let m = min(max(margin, 0), 100)
            let sc = min(max(scale, 1), 1000)
            let d = min(max(dpi, 36), 2400)
            AppSettings.shared.copyMarginMM = m
            AppSettings.shared.exportDPI = d
            AppSettings.shared.store(sc, key: Self.scaleKey)
            close()
            done(m, sc, d)
        }
    }

    // MARK: - 用紙

    /// 用紙の大きさ・向きと印刷の倍率(PageSetup の tail[0])
    struct PaperView: View {
        struct Preset: Identifiable, Hashable {
            var id: String
            var width: Int
            var height: Int
            var title: String { id + "(" + String(width) + " × " + String(height) + " mm)" }
        }

        static let presets: [Preset] = [
            Preset(id: "A3", width: 297, height: 420),
            Preset(id: "A4", width: 210, height: 297),
            Preset(id: "A5", width: 148, height: 210),
            Preset(id: "B4", width: 257, height: 364),
            Preset(id: "B5", width: 182, height: 257),
            Preset(id: "US レター", width: 216, height: 279),
        ]
        static let custom = "custom"

        let close: () -> Void
        let done: (PageSetup) -> Void
        @State private var page: PageSetup
        @State private var choice: String
        @State private var finished = false

        init(page: PageSetup, close: @escaping () -> Void, done: @escaping (PageSetup) -> Void) {
            self.close = close
            self.done = done
            _page = State(initialValue: page)
            _choice = State(initialValue: Self.match(page.paperWidth, page.paperHeight) ?? Self.custom)
        }

        static func match(_ w: Int, _ h: Int) -> String? {
            presets.first { $0.width == min(w, h) && $0.height == max(w, h) }?.id
        }

        var body: some View {
            Scaffold(title: "用紙", width: 420) {
                Form {
                    Section {
                        Picker("大きさ", selection: choiceBinding) {
                            ForEach(Self.presets) { p in Text(p.title).tag(p.id) }
                            Divider()
                            Text("カスタム").tag(Self.custom)
                        }
                        IntRow(label: "幅", value: $page.paperWidth, unit: "mm")
                        IntRow(label: "高さ", value: $page.paperHeight, unit: "mm")
                        Picker("向き", selection: $page.landscape) {
                            Text("縦").tag(false)
                            Text("横").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    Section {
                        IntRow(label: "印刷の倍率", value: scaleBinding, unit: "%")
                    } footer: {
                        Text("用紙に印刷するときの拡大・縮小の割合です。")
                    }
                }
                .formStyle(.grouped)
                .labeledContentStyle(RowStyle())
                .onSubmit { finish() }
                .onChange(of: page.paperWidth) { syncChoice() }
                .onChange(of: page.paperHeight) { syncChoice() }
            } trailing: {
                CancelButton(close: close)
                DefaultButton { finish() }
            }
        }

        private var choiceBinding: Binding<String> {
            Binding(get: { choice }, set: { id in
                choice = id
                if let p = Self.presets.first(where: { $0.id == id }) {
                    page.paperWidth = p.width
                    page.paperHeight = p.height
                }
            })
        }

        private func syncChoice() {
            choice = Self.match(page.paperWidth, page.paperHeight) ?? Self.custom
        }

        private var scaleBinding: Binding<Int> {
            Binding(get: { page.tail.first ?? 100 }, set: { v in
                let c = min(max(v, 1), 1000)
                if page.tail.isEmpty { page.tail = [c] } else { page.tail[0] = c }
            })
        }

        private func finish() {
            Sheets.endEditing()
            guard !finished else { return }
            finished = true
            var p = page
            p.paperWidth = min(max(p.paperWidth, 50), 2000)
            p.paperHeight = min(max(p.paperHeight, 50), 2000)
            close()
            done(p)
        }
    }
}
