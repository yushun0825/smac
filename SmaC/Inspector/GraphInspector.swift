import SwiftUI
import SMPKit

/// グラフを選んでいるとき:「グラフ」と「軸」のタブ
struct GraphInspector: View {
    @ObservedObject var state: EditorState
    let gi: Int

    var body: some View {
        let graphs = state.project.graphs
        let name = graphs.indices.contains(gi) ? graphs[gi].name : ""
        let tab = state.graphTab == 1 ? 1 : 0
        VStack(spacing: 0) {
            InspectorHeader(title: name.isEmpty ? "グラフ" : name,
                            subtitle: graphs.count > 1 ? "グラフ \(gi + 1) / \(graphs.count)" : "グラフ") {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(.secondary)
            }
            InspectorTabPicker(selection: Binding(get: { tab }, set: { state.graphTab = $0 }), titles: ["グラフ", "軸"])
            if tab == 1 {
                AxisInspector(state: state, gi: gi)
            } else {
                InspectorGraphForm(state: state, gi: gi)
            }
        }
    }
}

/// 「グラフ」のタブ: 名前・位置と大きさ・枠
struct InspectorGraphForm: View {
    @ObservedObject var state: EditorState
    let gi: Int

    var body: some View {
        InspectorForm {
            InspectorGroup {
                LabeledContent("名前") {
                    InspectorTextField(text: state.graph(gi, \.name, "グラフの名前"), prompt: "名前なし")
                }
                LabeledContent("メモ") {
                    InspectorTextField(text: state.graph(gi, \.comment, "グラフのメモ"), prompt: "なし")
                }
            }
            InspectorGroup("位置と大きさ") {
                InspectorNumberRow(label: "左から", value: InspectorKit.millimeters(state.graph(gi, \.left, "グラフの位置")), unit: "mm")
                InspectorNumberRow(label: "上から", value: InspectorKit.millimeters(state.graph(gi, \.top, "グラフの位置")), unit: "mm")
                InspectorNumberRow(label: "幅", value: InspectorKit.millimeters(state.graph(gi, \.width, "グラフの大きさ"), min: 1), unit: "mm")
                InspectorNumberRow(label: "高さ", value: InspectorKit.millimeters(state.graph(gi, \.height, "グラフの大きさ"), min: 1), unit: "mm")
                InspectorNumberRow(label: "倍率", value: InspectorKit.integer(state.graph(gi, \.zoom, "グラフの倍率"), 1...10_000), unit: "%")
            } footer: {
                Text("位置は用紙の左上から測ります。")
            }
            InspectorGroup("枠") {
                InspectorPickerRow("形") {
                    Picker("形", selection: state.graph(gi, \.frameType, "枠の形")) {
                        ForEach(FrameType.dialogOrder, id: \.self) { t in
                            Text(InspectorKit.frameName(t)).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                InspectorNumberRow(label: "線の太さ", value: InspectorKit.millimeters(state.graph(gi, \.frameWidth, "枠の線の太さ"), min: 0), unit: "mm")
                ColorRow(label: "線の色", color: state.graph(gi, \.frameColor, "枠の線の色"))
                ColorRow(label: "背景の色", color: state.graph(gi, \.background, "グラフの背景の色"))
            }
        }
    }
}
