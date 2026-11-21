import SwiftUI
import SMPKit

/// 文字・矢印・枠・点・図を選んでいるとき
struct ObjectInspector: View {
    @ObservedObject var state: EditorState
    let gi: Int
    let id: UUID

    var body: some View {
        let g = InspectorKit.graph(state, gi)
        if let item = g.objects.first(where: { $0.id == id }) {
            VStack(spacing: 0) {
                InspectorHeader(title: title(item.object), subtitle: subtitle(item.object)) {
                    Image(systemName: item.object.symbolName)
                        .foregroundStyle(.secondary)
                }
                switch item.object {
                case .text:
                    InspectorTextForm(state: state, gi: gi, id: id)
                case .shape(let s):
                    if s.isBox {
                        InspectorBoxForm(state: state, gi: gi, id: id)
                    } else {
                        InspectorArrowForm(state: state, gi: gi, id: id)
                    }
                case .dot:
                    InspectorDotForm(state: state, gi: gi, id: id)
                case .picture:
                    InspectorPictureForm(state: state, gi: gi, id: id)
                case .raw(let type, _):
                    InspectorRawObjectForm(type: type) { state.perform?(.deleteObject(id)) }
                }
            }
        } else {
            InspectorEmptyView()
        }
    }

    private func title(_ o: GraphObject) -> String {
        switch o {
        case .text(let t): return t.kind.displayTitle
        case .picture: return "図"
        default: return o.displayTitle
        }
    }

    private func subtitle(_ o: GraphObject) -> String? {
        switch o {
        case .text, .picture:
            let d = o.displayTitle
            return d == title(o) ? nil : d
        default:
            return nil
        }
    }
}

// MARK: - 矢印・線・エラーバー

struct InspectorArrowForm: View {
    @ObservedObject var state: EditorState
    let gi: Int
    let id: UUID

    var body: some View {
        let b = state.shapeObject(gi, id)
        let s = b.wrappedValue
        let isErrorBar = s.objectType == 2
        InspectorForm {
            InspectorGroup("形") {
                InspectorPickerRow("種類") {
                    Picker("種類", selection: b.objectType) {
                        Text("塗った矢じり").tag(0)
                        Text("線の矢じり").tag(1)
                        Text("エラーバー").tag(2)
                    }
                }
                if !isErrorBar {
                    InspectorPickerRow("矢じり") {
                        Picker("矢じり", selection: b.headMode) {
                            Text("なし").tag(0)
                            Text("終点").tag(1)
                            Text("始点").tag(2)
                            Text("両端").tag(3)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if isErrorBar || s.headMode != 0 {
                    InspectorNumberRow(label: isErrorBar ? "端の線の長さ" : "矢じりの長さ", value: InspectorKit.millimeters(b.length, min: 0), unit: "mm")
                }
                if !isErrorBar && s.headMode != 0 {
                    InspectorNumberRow(label: "矢じりの開き", value: InspectorKit.headOpening(b.headOpen))
                }
            }
            InspectorGroup("線") {
                InspectorNumberRow(label: "太さ", value: InspectorKit.millimeters(b.width, min: 0), unit: "mm")
                ColorRow(label: "色", color: b.color)
                InspectorPickerRow("種類") {
                    LineStylePicker(label: "種類", style: InspectorKit.lineStyle(b.style))
                }
                if InspectorKit.isDashed(s.style) {
                    InspectorNumberRow(label: "破線の間隔", value: InspectorKit.millimeters(b.pitch, min: 0.2), unit: "mm")
                }
            }
            InspectorShapePositionGroup(state: state, gi: gi, shape: b, first: "始点", second: "終点")
            InspectorDeleteSection { state.perform?(.deleteObject(id)) }
        }
    }
}

// MARK: - 枠

struct InspectorBoxForm: View {
    @ObservedObject var state: EditorState
    let gi: Int
    let id: UUID

    var body: some View {
        let b = state.shapeObject(gi, id)
        let s = b.wrappedValue
        InspectorForm {
            InspectorGroup("線") {
                InspectorNumberRow(label: "太さ", value: InspectorKit.millimeters(b.width, min: 0), unit: "mm")
                ColorRow(label: "色", color: b.color)
                InspectorPickerRow("種類") {
                    LineStylePicker(label: "種類", style: InspectorKit.lineStyle(b.style))
                }
                if InspectorKit.isDashed(s.style) {
                    InspectorNumberRow(label: "破線の間隔", value: InspectorKit.millimeters(b.pitch, min: 0.2), unit: "mm")
                }
            }
            InspectorGroup("影と中の色") {
                InspectorNumberRow(label: "影の長さ", value: InspectorKit.millimeters(b.length, min: 0), unit: "mm")
                if s.length > 0 {
                    ColorRow(label: "中の色", color: b.shadowColor)
                }
            } footer: {
                Text(s.length > 0 ? "影は線と同じ色で、右下に付きます。" : "影の長さを 0 より大きくすると、右下に影が付き、枠の中を塗ります。")
            }
            InspectorGroup("角の丸み") {
                InspectorNumberRow(label: "横", value: InspectorKit.millimeters(b.size, min: 0), unit: "mm")
                InspectorNumberRow(label: "縦", value: InspectorKit.millimeters(b.aspect, min: 0), unit: "mm")
            } footer: {
                Text("縦を 0 にすると横と同じになります。")
            }
            InspectorShapePositionGroup(state: state, gi: gi, shape: b, first: "左上", second: "右下")
            InspectorDeleteSection { state.perform?(.deleteObject(id)) }
        }
    }
}

/// 矢印・枠の位置(単位は mm か、軸の値)
struct InspectorShapePositionGroup: View {
    @ObservedObject var state: EditorState
    let gi: Int
    @Binding var shape: ShapeObject
    var first: String
    var second: String

    var body: some View {
        let xUnit = shape.xReference == 0 ? "mm" : ""
        let yUnit = shape.yReference == 0 ? "mm" : ""
        InspectorGroup("位置") {
            InspectorPickerRow("横の単位") {
                Picker("横の単位", selection: reference(horizontal: true)) {
                    Text("mm").tag(0)
                    Text("X 軸の値").tag(1)
                    Text("上の軸の値").tag(2)
                }
            }
            InspectorPickerRow("縦の単位") {
                Picker("縦の単位", selection: reference(horizontal: false)) {
                    Text("mm").tag(0)
                    Text("Y 軸の値").tag(1)
                    Text("右の軸の値").tag(2)
                }
            }
            InspectorNumberRow(label: "\(first) X", value: InspectorKit.finite($shape.x1), unit: xUnit)
            InspectorNumberRow(label: "\(first) Y", value: InspectorKit.finite($shape.y1), unit: yUnit)
            InspectorNumberRow(label: "\(second) X", value: InspectorKit.finite($shape.x2), unit: xUnit)
            InspectorNumberRow(label: "\(second) Y", value: InspectorKit.finite($shape.y2), unit: yUnit)
        } footer: {
            Text("mm はグラフの枠の左上から測ります。単位を変えても、置いた場所はそのままです。")
        }
    }

    /// 単位を変えるとき、値も同じ場所を指すように直す
    private func reference(horizontal: Bool) -> Binding<Int> {
        let shape = $shape
        let state = state
        let gi = gi
        return Binding(get: {
            horizontal ? shape.wrappedValue.xReference : shape.wrappedValue.yReference
        }, set: { r in
            var s = shape.wrappedValue
            let g = InspectorKit.graph(state, gi)
            if horizontal {
                guard r != s.xReference else { return }
                s.x1 = InspectorKit.convertPosition(s.x1, horizontal: true, from: s.xReference, to: r, graph: g)
                s.x2 = InspectorKit.convertPosition(s.x2, horizontal: true, from: s.xReference, to: r, graph: g)
                s.xReference = r
            } else {
                guard r != s.yReference else { return }
                s.y1 = InspectorKit.convertPosition(s.y1, horizontal: false, from: s.yReference, to: r, graph: g)
                s.y2 = InspectorKit.convertPosition(s.y2, horizontal: false, from: s.yReference, to: r, graph: g)
                s.yReference = r
            }
            shape.wrappedValue = s
        })
    }
}

// MARK: - 点

struct InspectorDotForm: View {
    @ObservedObject var state: EditorState
    let gi: Int
    let id: UUID

    var body: some View {
        let b = state.dotObject(gi, id)
        let d = b.wrappedValue
        let hasLine = d.style > 0 && d.length > 0
        InspectorForm {
            InspectorGroup("点") {
                InspectorPickerRow("形") {
                    PlotTypePicker(label: "形", code: b.dotType, codes: PlotType.dotObjectCodes)
                }
                InspectorNumberRow(label: "大きさ", value: InspectorKit.millimeters(b.size, min: 0), unit: "mm")
                ColorRow(label: "色", color: b.lineColor)
                InspectorNumberRow(label: "線の太さ", value: InspectorKit.millimeters(b.width, min: 0), unit: "mm")
                InspectorPickerRow("中塗り") {
                    BrushPicker(label: "中塗り", style: b.brushStyle, hatch: b.brushHatch)
                }
                ColorRow(label: "中塗りの色", color: b.brushColor)
            }
            InspectorGroup("横線") {
                Toggle("点を通る横線を引く", isOn: Binding(get: { hasLine }, set: { on in
                    var v = b.wrappedValue
                    if on {
                        v.style = max(v.style, 1)
                        if v.length <= 0 { v.length = 1000 }
                    } else {
                        v.style = 0
                    }
                    b.wrappedValue = v
                }))
                if hasLine {
                    InspectorPickerRow("種類") {
                        LineStylePicker(label: "種類", style: InspectorKit.lineStyle(b.style))
                    }
                    InspectorNumberRow(label: "長さ", value: InspectorKit.millimeters(b.length, min: 0), unit: "mm")
                    ColorRow(label: "色", color: b.color)
                }
            } footer: {
                Text("凡例の見本のように、点の左右に線を引きます。")
            }
            InspectorGroup("位置") {
                InspectorNumberRow(label: "左から", value: InspectorKit.millimeters(b.x), unit: "mm")
                InspectorNumberRow(label: "上から", value: InspectorKit.millimeters(b.y), unit: "mm")
            } footer: {
                Text("グラフの枠の左上から測ります。")
            }
            InspectorDeleteSection { state.perform?(.deleteObject(id)) }
        }
    }
}

// MARK: - 図

struct InspectorPictureForm: View {
    @ObservedObject var state: EditorState
    let gi: Int
    let id: UUID

    var body: some View {
        let b = state.pictureObject(gi, id)
        let path = b.wrappedValue.path
        InspectorForm {
            InspectorGroup("ファイル") {
                Text(path.isEmpty ? "なし" : path)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(path)
                Button("選び直す…") { state.perform?(.choosePicture(id)) }
            }
            InspectorGroup("位置と大きさ") {
                InspectorNumberRow(label: "左から", value: InspectorKit.pictureGeometry(b, .left), unit: "mm")
                InspectorNumberRow(label: "上から", value: InspectorKit.pictureGeometry(b, .top), unit: "mm")
                InspectorNumberRow(label: "幅", value: InspectorKit.pictureGeometry(b, .width), unit: "mm")
                InspectorNumberRow(label: "高さ", value: InspectorKit.pictureGeometry(b, .height), unit: "mm")
            } footer: {
                Text("グラフの枠の左上から測ります。")
            }
            InspectorDeleteSection { state.perform?(.deleteObject(id)) }
        }
    }
}

// MARK: - 読めても形のわからないもの

struct InspectorRawObjectForm: View {
    let type: Int
    var delete: () -> Void

    var body: some View {
        InspectorForm {
            InspectorGroup {
                Text("この図形(種類 \(type))は、ここでは変えられません。保存すると元のまま残ります。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InspectorDeleteSection(action: delete)
        }
    }
}
