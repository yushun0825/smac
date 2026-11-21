import SwiftUI
import SMPKit

/// 「曲線」のタブ: 当てはめ・スプライン・関数・そのほかの解析の範囲、曲線の線、結果
struct InspectorSeriesCurveForm: View {
    @ObservedObject var state: EditorState
    let gi: Int
    let si: Int

    private func bind<T: Equatable>(_ kp: WritableKeyPath<Series, T>, _ action: String) -> Binding<T> {
        state.series(gi, si, kp, action)
    }

    var body: some View {
        let s = InspectorKit.series(state, gi, si)
        let analysis = s.extensionAnalysis
        let isFunction = s.kind == .function
        // x を刻んで曲線を作るもの(当てはめ・スプライン・関数・ピークの当てはめ)
        let usesSamples = s.kind.hasCurve || (analysis?.usesFittingDialog ?? false)
        // 曲線の線を持つもの(関数は「見た目」の線で描く)
        let drawsCurve = !isFunction && (s.kind.hasCurve || (analysis?.producesCurve ?? false))
        InspectorForm {
            InspectorGroup {
                Label(InspectorKit.curveTitle(s), systemImage: isFunction ? "function" : "chart.line.uptrend.xyaxis")
                    .font(.system(size: NSFont.smallSystemFontSize, weight: .semibold))
                HStack {
                    Button("条件を変える…") { state.perform?(.refit(series: si)) }
                    if !isFunction {
                        Button("解析をやめる") { state.perform?(.clearAnalysis(series: si)) }
                    }
                }
            }
            if usesSamples {
                InspectorGroup("描く範囲") {
                    InspectorNumberRow(label: "始め", value: InspectorKit.finite(bind(\.curveStart, "曲線の範囲")))
                    InspectorNumberRow(label: "終わり", value: InspectorKit.finite(bind(\.curveEnd, "曲線の範囲")))
                    InspectorNumberRow(label: "分割数", value: InspectorKit.integer(bind(\.curveDivisions, "曲線の分割数"), 2...20_000))
                    InspectorPickerRow("刻み方") {
                        Picker("刻み方", selection: bind(\.curveSpacing, "曲線の刻み方")) {
                            Text("等間隔").tag(Series.CurveSpacing.linear)
                            Text("指数的").tag(Series.CurveSpacing.exponential)
                            Text("逆数的").tag(Series.CurveSpacing.reciprocal)
                        }
                    }
                    if !isFunction {
                        Toggle("軸の範囲の外の点も使う", isOn: bind(\.considerOutOfRange, "解析に使う点"))
                    }
                } footer: {
                    Text(isFunction ? "始めと終わりを同じにすると、軸の範囲で描きます。線は「見た目」で変えます。"
                                    : "始めと終わりを同じにすると、データの範囲で描きます。")
                }
            } else if !isFunction {
                InspectorGroup {
                    Toggle("軸の範囲の外の点も使う", isOn: bind(\.considerOutOfRange, "解析に使う点"))
                }
            }
            if drawsCurve {
                InspectorGroup("曲線") {
                    Toggle("曲線を描く", isOn: bind(\.curveVisible, "曲線の表示"))
                    Group {
                        InspectorPickerRow("種類") {
                            LineTypePicker(label: "種類", lineType: bind(\.curveLineType, "曲線の種類"))
                        }
                        InspectorNumberRow(label: "太さ", value: InspectorKit.millimeters(bind(\.curveWidth, "曲線の太さ"), min: 0), unit: "mm")
                        ColorRow(label: "色", color: bind(\.curveColor, "曲線の色"))
                        if InspectorKit.isDashed(s.curveLineType.rawValue) {
                            InspectorNumberRow(label: "破線の間隔", value: InspectorKit.millimeters(bind(\.curvePitch, "曲線の破線の間隔"), min: 0.2), unit: "mm")
                        }
                    }
                    .disabled(!s.curveVisible)
                }
            }
            if !isFunction {
                resultGroup(state.plotData(gi, si))
            }
        }
    }

    @ViewBuilder
    private func resultGroup(_ data: SeriesPlotData?) -> some View {
        if let error = data?.error {
            InspectorGroup("結果") {
                Label {
                    Text(error)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        } else {
            let lines = resultLines(data)
            if !lines.isEmpty {
                InspectorGroup("結果") {
                    InspectorResultsView(lines: lines)
                    HStack {
                        Button {
                            InspectorKit.copyToPasteboard(lines.joined(separator: "\n"))
                        } label: {
                            Label("コピー", systemImage: "doc.on.doc")
                        }
                        Button("別の窓で見る…") { state.perform?(.showResults(series: si)) }
                    }
                }
            }
        }
    }

    private func resultLines(_ data: SeriesPlotData?) -> [String] {
        guard let data else { return [] }
        if !data.resultLines.isEmpty { return data.resultLines }
        if let fit = data.fit { return fit.summary.components(separatedBy: "\n") }
        return []
    }
}
