import SwiftUI
import AppKit
import SMPKit

/// 「設定」の窓の中身
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var confirmingReset = false
    @State private var hasCustomDefault = SettingsView.customDefaultExists()

    var body: some View {
        Form {
            Section("保存") {
                Toggle("データもグラフのファイルに保存する", isOn: $settings.saveDataWithGraph)
                Toggle("同じフォルダにあるデータはファイル名だけを記録する", isOn: $settings.omitPathInSameFolder)
            }

            Section("データを開くとき") {
                Toggle("データごとにドットの形を変える", isOn: $settings.autoDotType)
                Toggle("データごとに線の種類を変える", isOn: $settings.autoLineType)
                Toggle("データごとにドットの色を変える", isOn: $settings.autoDotColor)
                Toggle("データごとに線の色を変える", isOn: $settings.autoLineColor)
                Toggle("横軸の範囲をデータに合わせる", isOn: $settings.autoScaleX)
                Toggle("縦軸の範囲をデータに合わせる", isOn: $settings.autoScaleY)
            }

            Section {
                Toggle("グラフの枠の外にはみ出す部分を描かない", isOn: $settings.clipToFrame)
                Picker("動かすときの刻み", selection: $settings.snapMM) {
                    Text("なし").tag(0.0)
                    Text("0.5 mm").tag(0.5)
                    Text("1 mm").tag(1.0)
                    Text("2 mm").tag(2.0)
                    Text("5 mm").tag(5.0)
                    if ![0.0, 0.5, 1.0, 2.0, 5.0].contains(settings.snapMM) {
                        Text(NumberText.g(settings.snapMM) + " mm").tag(settings.snapMM)
                    }
                }
                Picker("キャンバスの方眼", selection: $settings.gridMM) {
                    Text("なし").tag(0.0)
                    Text("5 mm").tag(5.0)
                    Text("10 mm").tag(10.0)
                    if ![0.0, 5.0, 10.0].contains(settings.gridMM) {
                        Text(NumberText.g(settings.gridMM) + " mm").tag(settings.gridMM)
                    }
                }
                NumberRow(label: "上付き・下付きの文字の大きさ", value: clamped(\.superscriptScale, 10...100), unit: "%")
                NumberRow(label: "上付きの文字の高さ", value: clamped(\.superscriptRise, 0...100), unit: "%")
                NumberRow(label: "下付きの文字の下げ幅", value: clamped(\.subscriptDrop, 0...100), unit: "%")
            } header: {
                Text("描画と操作")
            } footer: {
                Text("上付き・下付きの値は、元の文字の大きさに対する割合です。")
            }

            Section("書き出し") {
                NumberRow(label: "図をコピーするときの余白", value: clamped(\.copyMarginMM, 0...100), unit: "mm")
                NumberRow(label: "画像の解像度", value: clamped(\.exportDPI, 36...2400), unit: "dpi")
                Picker("値を書き出すときの区切り", selection: $settings.exportSeparatorTab) {
                    Text("タブ").tag(true)
                    Text("カンマ").tag(false)
                }
                Toggle("印刷するときにファイル名と日時を入れる", isOn: $settings.printFooter)
            }

            Section {
                HStack {
                    Text("書式")
                    Spacer(minLength: 12)
                    Button("既定のグラフを元に戻す…") { confirmingReset = true }
                        .disabled(!hasCustomDefault)
                }
            } header: {
                Text("新しいグラフ")
            } footer: {
                Text(hasCustomDefault
                     ? "「既定のグラフにする」で保存した書式を消し、新しいグラフを最初の書式(140 × 100 mm の枠)で作るようにします。"
                     : "新しいグラフは最初の書式(140 × 100 mm の枠)で作られます。")
            }
        }
        .formStyle(.grouped)
        .labeledContentStyle(Sheets.RowStyle())
        .frame(width: 520, height: Self.preferredHeight)
        .confirmationDialog("既定のグラフを元に戻しますか？", isPresented: $confirmingReset) {
            Button("元に戻す", role: .destructive) {
                AppSettings.shared.resetDefaultGraph()
                hasCustomDefault = Self.customDefaultExists()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("これから作るグラフが最初の書式になります。開いているグラフは変わりません。")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasCustomDefault = Self.customDefaultExists()
        }
    }

    /// 窓の高さ(全部は入らないので、画面に収まる高さにして中をスクロールする)
    static var preferredHeight: CGFloat {
        min(680, max(420, (NSScreen.main?.visibleFrame.height ?? 800) - 120))
    }

    static func customDefaultExists() -> Bool {
        FileManager.default.fileExists(atPath: AppSettings.defaultGraphURL.path)
    }

    private func clamped(_ key: ReferenceWritableKeyPath<AppSettings, Double>, _ range: ClosedRange<Double>) -> Binding<Double> {
        let s = settings
        return Binding(get: { s[keyPath: key] }, set: { s[keyPath: key] = min(max($0, range.lowerBound), range.upperBound) })
    }
}
