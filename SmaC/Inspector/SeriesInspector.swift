import SwiftUI
import AppKit
import SMPKit

/// データ(系列)を選んでいるとき:「データ」「見た目」「曲線」のタブ
struct SeriesInspector: View {
    @ObservedObject var state: EditorState
    let gi: Int
    let si: Int

    var body: some View {
        let s = InspectorKit.series(state, gi, si)
        let hasCurve = s.kind.hasCurve || s.extensionAnalysis != nil
        // 曲線の無いデータで「曲線」が選ばれていたら「データ」を出す
        let tab = (state.seriesTab == 2 && !hasCurve) ? 0 : Swift.min(Swift.max(state.seriesTab, 0), 2)
        VStack(spacing: 0) {
            InspectorHeader(title: s.displayName, subtitle: s.kind == .function ? s.kind.displayTitle : s.path) {
                SeriesSwatch(series: s)
            }
            .help(s.kind == .function ? s.displayName : s.path)
            InspectorTabPicker(selection: Binding(get: { tab }, set: { state.seriesTab = $0 }),
                               titles: hasCurve ? ["データ", "見た目", "曲線"] : ["データ", "見た目"])
            switch tab {
            case 1:
                InspectorSeriesStyleForm(state: state, gi: gi, si: si)
            case 2:
                InspectorSeriesCurveForm(state: state, gi: gi, si: si)
            default:
                InspectorSeriesDataForm(state: state, gi: gi, si: si)
            }
        }
    }
}

// MARK: - データ

/// 「データ」のタブ: 表示・列・誤差・軸・読み込み・変換・除外する範囲
struct InspectorSeriesDataForm: View {
    @ObservedObject var state: EditorState
    let gi: Int
    let si: Int

    private func bind<T: Equatable>(_ kp: WritableKeyPath<Series, T>, _ action: String) -> Binding<T> {
        state.series(gi, si, kp, action)
    }

    var body: some View {
        let g = InspectorKit.graph(state, gi)
        let s = InspectorKit.series(state, gi, si)
        let isFunction = s.kind == .function
        let file = isFunction ? nil : state.project.dataFile(named: s.name)
        InspectorForm {
            InspectorGroup {
                Toggle("表示する", isOn: bind(\.visible, "データの表示"))
            }
            if isFunction {
                InspectorGroup("関数") {
                    expressionRow("y =", bind(\.expressionY, "関数の式"))
                } footer: {
                    Text("x の範囲と点の数は「曲線」で変えます。")
                }
            } else {
                columnGroup(s, file: file)
            }
            InspectorGroup("軸") {
                Toggle("上の軸の目盛りで描く", isOn: bind(\.useUAxis, "使う軸"))
                    .disabled(!g.uIndependent)
                Toggle("右の軸の目盛りで描く", isOn: bind(\.useRAxis, "使う軸"))
                    .disabled(!g.rIndependent)
            } footer: {
                if !g.uIndependent || !g.rIndependent {
                    Text("上・右の軸を X・Y 軸と別の目盛りにすると選べます。")
                }
            }
            if !isFunction {
                readingGroup(s, file: file)
                averageGroup
                transformGroup(s)
            }
            maskGroup(g)
            InspectorGroup {
                HStack {
                    if !isFunction {
                        Button("データを編集…") { state.perform?(.editData(series: si)) }
                    }
                    Button("値をコピー") { state.perform?(.copyValues(series: si)) }
                }
            }
        }
    }

    // MARK: 列と誤差

    private func columnGroup(_ s: Series, file: DataFile?) -> some View {
        let found = Swift.min(Swift.max(InspectorKit.columnCount(file, tabAsSpace: s.tabAsSpace), 2), 256)
        let count = Swift.max(found, s.columnX + 1, s.columnY + 1)
        return InspectorGroup("列") {
            if file == nil {
                Label("データファイルが見つかりません", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            InspectorPickerRow("X の列") {
                Picker("X の列", selection: bind(\.columnX, "X の列")) { columnChoices(count) }
            }
            InspectorPickerRow("Y の列") {
                Picker("Y の列", selection: bind(\.columnY, "Y の列")) { columnChoices(count) }
            }
            InspectorPickerRow("X の誤差") {
                Picker("X の誤差", selection: bind(\.errorBarX, "X の誤差")) { errorChoices }
            }
            InspectorPickerRow("Y の誤差") {
                Picker("Y の誤差", selection: bind(\.errorBarY, "Y の誤差")) { errorChoices }
            }
        } footer: {
            if s.errorBarX != Series.ErrorBar.none || s.errorBarY != Series.ErrorBar.none {
                Text("誤差は、X・Y の列のすぐ後ろの列から読みます。")
            }
        }
    }

    @ViewBuilder
    private func columnChoices(_ count: Int) -> some View {
        Text("番号(0, 1, 2…)").tag(-1)
        ForEach(0..<count, id: \.self) { c in
            Text("\(c + 1) 列目").tag(c)
        }
    }

    @ViewBuilder
    private var errorChoices: some View {
        Text("なし").tag(Series.ErrorBar.none)
        Text("+ と − を別の列").tag(Series.ErrorBar.plusPlus)
        Text("± を 1 列").tag(Series.ErrorBar.plusMinus)
    }

    // MARK: 読み込み

    private func readingGroup(_ s: Series, file: DataFile?) -> some View {
        let maxLines = bind(\.maxLines, "読む行数")
        return InspectorGroup("読み込み") {
            InspectorNumberRow(label: "先頭で飛ばす行", value: InspectorKit.integer(bind(\.skipLines, "飛ばす行"), 0...100_000_000), unit: "行")
            Toggle("最後の行まで読む", isOn: Binding(get: { maxLines.wrappedValue < 0 }, set: { all in
                maxLines.wrappedValue = all ? -1 : Swift.max(file?.lines.count ?? 100, 1)
            }))
            if s.maxLines >= 0 {
                InspectorNumberRow(label: "読む行数", value: InspectorKit.integer(maxLines, 0...100_000_000), unit: "行")
            }
            InspectorNumberRow(label: "何行ごとに読むか", value: InspectorKit.integer(bind(\.readStep, "読む間隔"), 1...1_000_000), unit: "行")
            Toggle("行数をファイルの先頭から数える", isOn: bind(\.absoluteLineCount, "行数の数え方"))
            Toggle("コメントの行を数えない", isOn: bind(\.skipCommentCount, "行数の数え方"))
            Toggle("タブを空白と同じに扱う", isOn: bind(\.tabAsSpace, "区切りの扱い"))
        } footer: {
            Text("\(s.linesRead) 点を読み込んでいます。")
        }
    }

    private var averageGroup: some View {
        InspectorGroup("移動平均") {
            InspectorNumberRow(label: "X", value: InspectorKit.integer(bind(\.horizontalAverage, "移動平均"), 0...10_000), unit: "点")
            InspectorNumberRow(label: "Y", value: InspectorKit.integer(bind(\.verticalAverage, "移動平均"), 0...10_000), unit: "点")
        } footer: {
            Text("前後それぞれの点の数です。0 なら平均しません。")
        }
    }

    // MARK: 変換

    private func transformGroup(_ s: Series) -> some View {
        InspectorGroup("変換") {
            Toggle("X を式で変える", isOn: bind(\.transformX, "X の変換"))
            if s.transformX {
                expressionRow("x =", bind(\.expressionX, "X の式"))
            }
            Toggle("Y を式で変える", isOn: bind(\.transformY, "Y の変換"))
            if s.transformY {
                expressionRow("y =", bind(\.expressionY, "Y の式"))
            }
        } footer: {
            Text("x・y・定数 a〜i・pi と、ほかの列(#0102 は 1 番目のデータの 2 列目)が使えます。")
        }
    }

    private func expressionRow(_ label: String, _ text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: NSFont.smallSystemFontSize, design: .monospaced))
                .foregroundStyle(.secondary)
            InspectorTextField(text: text, prompt: "式", monospaced: true, validate: InspectorKit.expressionProblem)
        }
    }

    // MARK: 除外する範囲

    @ViewBuilder
    private func maskGroup(_ g: Graph) -> some View {
        let indices = g.masks.indices.filter { g.masks[$0].seriesIndex == si }
        if !indices.isEmpty {
            InspectorGroup("除外している範囲") {
                ForEach(indices, id: \.self) { k in
                    let m = g.masks[k]
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("X  \(NumberText.g(m.xMin)) 〜 \(NumberText.g(m.xMax))")
                            Text("Y  \(NumberText.g(m.yMin)) 〜 \(NumberText.g(m.yMax))")
                        }
                        .monospacedDigit()
                        Spacer(minLength: 0)
                        Button(role: .destructive) {
                            state.perform?(.removeMask(k))
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("この範囲を外す")
                    }
                }
            } footer: {
                Text("この範囲に入る点は描かず、解析にも使いません。")
            }
        }
    }
}

// MARK: - 見た目

/// 「見た目」のタブ: 点と線
struct InspectorSeriesStyleForm: View {
    @ObservedObject var state: EditorState
    let gi: Int
    let si: Int

    private func bind<T: Equatable>(_ kp: WritableKeyPath<Series, T>, _ action: String) -> Binding<T> {
        state.series(gi, si, kp, action)
    }

    var body: some View {
        let s = InspectorKit.series(state, gi, si)
        InspectorForm {
            InspectorGroup("点") {
                InspectorPickerRow("形") {
                    PlotTypePicker(label: "形", code: bind(\.dotType, "点の形"))
                }
                if PlotType.drawsMark(s.dotType) {
                    InspectorNumberRow(label: "大きさ", value: InspectorKit.millimeters(bind(\.dotSize, "点の大きさ"), min: 0), unit: "mm")
                    ColorRow(label: "色", color: bind(\.dotColor, "点の色"))
                    InspectorPickerRow("中塗り") {
                        BrushPicker(label: "中塗り", style: bind(\.brushStyle, "中塗り"), hatch: bind(\.brushHatch, "中塗り"))
                    }
                    ColorRow(label: "中塗りの色", color: bind(\.brushColor, "中塗りの色"))
                        .disabled(PlotType.fillsWithDotColor(s.dotType) || s.brushStyle == 1)
                }
            }
            InspectorGroup("線") {
                InspectorPickerRow("種類") {
                    LineTypePicker(label: "種類", lineType: bind(\.lineType, "線の種類"), allowFill: true)
                }
                InspectorNumberRow(label: "太さ", value: InspectorKit.millimeters(bind(\.lineWidth, "線の太さ"), min: 0), unit: "mm")
                ColorRow(label: "色", color: bind(\.lineColor, "線の色"))
                if InspectorKit.isDashed(s.lineType.rawValue) {
                    InspectorNumberRow(label: "破線の間隔", value: InspectorKit.millimeters(bind(\.pitch, "破線の間隔"), min: 0.2), unit: "mm")
                }
            } footer: {
                Text("線の太さは、点の縁と誤差の棒にも使います。")
            }
            if PlotType.isBarOrStep(s.dotType) || s.lineType == .fill {
                InspectorGroup("棒と面") {
                    InspectorNumberRow(label: "基準の値", value: InspectorKit.finite(bind(\.barBase, "棒の基準")))
                } footer: {
                    Text("棒と面は、軸のこの値の位置から描きます。")
                }
            }
        }
    }
}
