import SwiftUI
import AppKit
import SMPKit

extension Sheets {
    /// ガウス関数・ローレンツ関数による当てはめの条件。「ピーク」と「曲線」の 2 つの面に分ける
    struct PeakFitView: View {
        let title: String
        let close: () -> Void
        let done: (Series) -> Void

        @State private var s: Series
        @State private var p: PeakFitSettings
        @State private var autoRange: Bool
        @State private var page = 0
        @State private var finished = false

        init(series: Series, title: String, close: @escaping () -> Void, done: @escaping (Series) -> Void) {
            self.title = title
            self.close = close
            self.done = done
            _s = State(initialValue: series)
            _p = State(initialValue: series.peakFit.normalized)
            _autoRange = State(initialValue: series.curveStart == series.curveEnd)
        }

        var body: some View {
            Scaffold(title: title, message: "データ: \(s.name)", width: 540) {
                VStack(spacing: 0) {
                    PageSwitcher(selection: $page, titles: ["ピーク", "曲線"])
                    Form {
                        if page == 0 {
                            peakSections
                        } else {
                            CurveSections(series: $s, autoRange: $autoRange, rangeApplies: true,
                                          autoRangeHint: "データのある範囲に曲線を描きます。")
                        }
                    }
                    .formStyle(.grouped)
                    .labeledContentStyle(RowStyle())
                    .onSubmit { finish() }
                }
            } trailing: {
                CancelButton(close: close)
                DefaultButton { finish() }
            }
        }

        @ViewBuilder private var peakSections: some View {
            Section {
                LabeledContent("式") { Text(formula) }
                Picker("ピークの数", selection: $p.count) {
                    ForEach(1...PeakFitSettings.maxPeaks, id: \.self) { n in Text(String(n)).tag(n) }
                }
            } header: {
                Text("ピークの形")
            } footer: {
                Text("A: 強度、x₀: 位置、w: 半値幅、y₀: オフセット")
            }
            Section {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text(verbatim: "")
                        Text("強度(A)")
                        Text("位置(x₀)")
                        Text("半値幅(w)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(0..<p.count, id: \.self) { i in
                        GridRow {
                            Text(String(i + 1))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            cell($p.intensity[i], vary: $p.varyIntensity[i])
                            cell($p.position[i], vary: $p.varyPosition[i])
                            cell($p.width[i], vary: $p.varyWidth[i])
                        }
                    }
                }
                LabeledContent("オフセット(y₀)") {
                    cell($p.offset, vary: $p.varyOffset)
                }
            } header: {
                Text("初期値")
            } footer: {
                Text("チェックを入れた値は当てはめで求め、外した値は固定します。")
            }
            Section {
                NumberRow(label: "精度", value: $p.precision, width: 96)
                OutOfRangeToggle(series: $s)
            } footer: {
                Text("二乗和の変化の割合が精度より小さくなったら計算を終えます。")
            }
        }

        private var formula: String {
            if s.extensionAnalysis == .lorentzian {
                return "y = y₀ + Σ A / (1 + 4 (x − x₀)² / w²)"
            }
            return "y = y₀ + Σ A exp(−4 ln2 (x − x₀)² / w²)"
        }

        private func cell(_ value: Binding<Double>, vary: Binding<Bool>) -> some View {
            HStack(spacing: 4) {
                NumberField(value: value, width: 96)
                Toggle("当てはめる", isOn: vary)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("当てはめる")
            }
        }

        private func finish() {
            Sheets.endEditing()
            guard !finished else { return }
            finished = true
            var r = s
            r.peakFit = p.normalized
            if autoRange {
                r.curveStart = 0
                r.curveEnd = 0
            }
            r.curveDivisions = min(max(r.curveDivisions, 1), 3999)
            close()
            done(r)
        }
    }
}
