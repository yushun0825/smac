import SwiftUI
import SMPKit

/// 「軸」のタブ: X・Y・上・右の軸を選んで、範囲・目盛り・数字を変える
struct AxisInspector: View {
    @ObservedObject var state: EditorState
    let gi: Int

    var body: some View {
        let g = InspectorKit.graph(state, gi)
        let ai = Swift.min(Swift.max(state.axisTab, 0), 3)
        // 上・右の軸は、枠が「枠」で X・Y と別の目盛りにしたときだけ細かく変えられる
        let linked = ai >= 2 && !(g.frameType == .box && !g.axes[ai - 2].commonWithOpposite)
        VStack(spacing: 0) {
            InspectorTabPicker(selection: Binding(get: { ai }, set: { state.axisTab = $0 }), titles: ["X", "Y", "上", "右"])
                .help("X 軸・Y 軸・上の軸・右の軸")
            if linked {
                InspectorLinkedAxisForm(state: state, gi: gi, ai: ai)
                    .id(ai)
            } else {
                InspectorAxisForm(state: state, gi: gi, ai: ai)
                    .id(ai)
            }
        }
    }
}

/// 1 本の軸の設定
struct InspectorAxisForm: View {
    @ObservedObject var state: EditorState
    let gi: Int
    let ai: Int

    private func bind<T: Equatable>(_ kp: WritableKeyPath<AxisSpec, T>, _ action: String) -> Binding<T> {
        state.axis(gi, ai, kp, action)
    }

    var body: some View {
        let g = InspectorKit.graph(state, gi)
        let a = ai < g.axes.count ? g.axes[ai] : AxisSpec()
        InspectorForm {
            if ai >= 2 {
                InspectorGroup {
                    Toggle(ai == 2 ? "X 軸と同じにする" : "Y 軸と同じにする",
                           isOn: state.axis(gi, ai - 2, \.commonWithOpposite, "軸を共通にする"))
                }
            }
            rangeGroup(a)
            if g.frameType == .grid {
                gridLineGroup("方眼の線(主目盛り)", bind(\.major, "方眼の線"))
                gridLineGroup("方眼の線(副目盛り)", bind(\.minor, "方眼の線"))
            } else {
                tickGroup("主目盛り", bind(\.major, "主目盛り"), a: a, frame: g.frameType, showsSwitch: true)
                tickGroup("副目盛り", bind(\.minor, "副目盛り"), a: a, frame: g.frameType, showsSwitch: false)
            }
            labelGroup(a)
        }
    }

    // MARK: 範囲

    private func rangeGroup(_ a: AxisSpec) -> some View {
        let horizontal = ai % 2 == 0
        return InspectorGroup("範囲") {
            InspectorNumberRow(label: horizontal ? "左端" : "下端", value: InspectorKit.finite(bind(\.from, "軸の範囲")))
            InspectorNumberRow(label: horizontal ? "右端" : "上端", value: InspectorKit.finite(bind(\.to, "軸の範囲")))
            InspectorPickerRow("目盛りの種類") {
                Picker("目盛りの種類", selection: bind(\.scaleType, "目盛りの種類")) {
                    ForEach(ScaleType.dialogOrder, id: \.self) { t in
                        Text(InspectorKit.scaleName(t)).tag(t)
                    }
                }
            }
            switch a.scaleType {
            case .linear, .inverseReciprocal:
                InspectorNumberRow(label: "主目盛りの間隔", value: InspectorKit.finite(bind(\.increment, "目盛りの間隔")))
                InspectorNumberRow(label: "副目盛り", value: InspectorKit.integer(bind(\.division, "副目盛りの数"), 1...1_000), unit: "等分")
            case .logNormal, .logExponent:
                InspectorPickerRow("主目盛り") {
                    Picker("主目盛り", selection: InspectorKit.logMajor(bind(\.increment, "主目盛りの位置"))) {
                        Text("1 のみ").tag(10)
                        Text("1 と 5").tag(5)
                        Text("1・2・5").tag(4)
                        Text("1 と 3").tag(3)
                        Text("1・2・4").tag(2)
                        Text("1〜9 すべて").tag(1)
                    }
                }
                Toggle("副目盛りを付ける", isOn: InspectorKit.logMinor(bind(\.division, "副目盛り")))
            case .inverseNormal:
                EmptyView()
            }
            Toggle("間隔を自動で決める", isOn: bind(\.autoStep, "間隔の自動設定"))
        } footer: {
            Text(rangeNote(a.scaleType))
        }
    }

    private func rangeNote(_ t: ScaleType) -> String {
        var notes: [String] = []
        if t.isInverse { notes.append("逆数の目盛りでは、両端を 1/x の値で入れます。") }
        if t == .inverseNormal { notes.append("目盛りは 1・2・5 の値に付きます。") }
        notes.append("間隔を自動にすると、範囲をデータに合わせ直すとき間隔も決め直します。")
        return notes.joined()
    }

    // MARK: 目盛り

    private func tickGroup(_ title: String, _ t: Binding<TickStyle>, a: AxisSpec, frame: FrameType, showsSwitch: Bool) -> some View {
        InspectorGroup(title) {
            if showsSwitch {
                Toggle(frame == .axes ? "軸の線と目盛りを描く" : "目盛りを描く", isOn: bind(\.drawAxis, "目盛りの表示"))
            }
            Group {
                InspectorPickerRow("向き") {
                    Picker("向き", selection: InspectorKit.tickDirection(t)) {
                        Text("内側").tag(1)
                        Text("外側").tag(2)
                        Text("両側").tag(3)
                        Text("なし").tag(0)
                    }
                    .pickerStyle(.segmented)
                }
                InspectorNumberRow(label: "長さ", value: InspectorKit.millimeters(t.length, min: 0), unit: "mm")
                InspectorNumberRow(label: "太さ", value: InspectorKit.millimeters(t.width, min: 0), unit: "mm")
                ColorRow(label: "色", color: t.color)
            }
            .disabled(!a.drawAxis)
        }
    }

    /// 方眼の線(枠が方眼のとき。目盛りの線種・間隔で引く)
    private func gridLineGroup(_ title: String, _ t: Binding<TickStyle>) -> some View {
        InspectorGroup(title) {
            InspectorPickerRow("線の種類") {
                LineStylePicker(label: "線の種類", style: InspectorKit.lineStyle(t.style))
            }
            InspectorNumberRow(label: "太さ", value: InspectorKit.millimeters(t.width, min: 0), unit: "mm")
            ColorRow(label: "色", color: t.color)
            if InspectorKit.isDashed(t.wrappedValue.style) {
                InspectorNumberRow(label: "破線の間隔", value: InspectorKit.millimeters(t.pitch, min: 0.2), unit: "mm")
            }
        }
    }

    // MARK: 数字

    private func labelGroup(_ a: AxisSpec) -> some View {
        let font = bind(\.font, "目盛りの数字のフォント")
        return InspectorGroup("数字") {
            Toggle("数字を描く", isOn: bind(\.drawLabels, "目盛りの数字の表示"))
            Group {
                InspectorFontNameRow(label: "フォント", name: bind(\.font.faceName, "目盛りの数字のフォント"), japanese: false)
                InspectorPickerRow("書体") {
                    FontStylePicker(font: font)
                }
                InspectorNumberRow(label: "大きさ", value: InspectorKit.pointSize(font), unit: "pt")
                ColorRow(label: "色", color: bind(\.labelColor, "目盛りの数字の色"))
                InspectorNumberRow(label: "右へずらす", value: InspectorKit.millimeters(bind(\.labelShiftX, "目盛りの数字の位置")), unit: "mm")
                InspectorNumberRow(label: "下へずらす", value: InspectorKit.millimeters(bind(\.labelShiftY, "目盛りの数字の位置")), unit: "mm")
                if !a.scaleType.isLog {
                    InspectorPickerRow("小数の桁") {
                        Picker("小数の桁", selection: InspectorKit.digits(bind(\.decimalDigits, "数字の桁"), 0...4)) {
                            Text("自動").tag(5)
                            ForEach(0...4, id: \.self) { n in
                                Text("\(n) 桁").tag(n)
                            }
                        }
                    }
                    Toggle("正の数に + を付ける", isOn: bind(\.plusSign, "数字の書き方"))
                    Toggle("0 は小数点を付けずに書く", isOn: bind(\.zeroAsInteger, "数字の書き方"))
                }
            }
            .disabled(!a.drawLabels)
        }
    }
}

/// 上・右の軸が X・Y 軸と同じ目盛りのとき(または描かない枠のとき)
struct InspectorLinkedAxisForm: View {
    @ObservedObject var state: EditorState
    let gi: Int
    let ai: Int

    var body: some View {
        let g = InspectorKit.graph(state, gi)
        let base = ai - 2
        let baseName = base == 0 ? "X 軸" : "Y 軸"
        let side = ai == 2 ? "上" : "右"
        InspectorForm {
            InspectorGroup {
                Toggle("\(baseName)と同じにする", isOn: state.axis(gi, base, \.commonWithOpposite, "軸を共通にする"))
                    .disabled(g.frameType != .box)
            } footer: {
                Text(note(g.frameType, side: side, baseName: baseName))
            }
            if g.frameType == .box || g.frameType == .grid {
                // 同じ目盛りでも、数字と目盛りを描くかは上・右の軸ごとに決められる
                InspectorGroup("\(side)の軸") {
                    Toggle("数字を描く", isOn: state.graph(gi, \.axes[ai].drawLabels, "目盛りの数字の表示"))
                    if g.frameType == .box {
                        Toggle("目盛りを描く", isOn: state.graph(gi, \.axes[ai].drawAxis, "目盛りの表示"))
                    }
                }
            }
        }
    }

    private func note(_ frame: FrameType, side: String, baseName: String) -> String {
        switch frame {
        case .box: return "\(side)の軸は\(baseName)と同じ目盛りです。別の目盛りにするときは、チェックを外します。"
        case .grid: return "方眼では、\(side)の軸はいつも\(baseName)と同じ目盛りです。"
        case .halfBox, .axes: return "この枠の形では、\(side)の軸を描きません。"
        }
    }
}
