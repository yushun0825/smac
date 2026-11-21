import SwiftUI
import AppKit
import SMPKit

extension Sheets {
    /// 曲線を求める解析(最小二乗・スプライン・関数)の条件。「条件」と「曲線」の 2 つの面に分ける
    struct AnalysisView: View {
        let title: String
        let close: () -> Void
        let done: (Series) -> Void

        @State private var s: Series
        /// 一般の関数の a〜g の初期値
        @State private var initial: [Double]
        @State private var history: [String]
        @State private var autoRange: Bool
        @State private var page = 0
        @State private var finished = false
        private let originalLine: String
        private let originalTolerance: Double

        static let historyKey = "lsq.functions"
        static let historyLimit = 10

        init(series: Series, title: String, close: @escaping () -> Void, done: @escaping (Series) -> Void) {
            var s = series
            switch s.kind {
            case .polynomialLSQ:
                s.lsqOrder = min(max(s.lsqOrder, 0), 9)
            case .spline:
                if Spline.Mode(rawValue: s.lsqOrder) == nil { s.lsqOrder = Spline.Mode.cubic.rawValue }
            case .function:
                // 式が "y" のままなら空の欄から始める
                if s.expressionY.trimmingCharacters(in: .whitespaces).lowercased() == "y" { s.expressionY = "" }
            case .generalLSQ:
                s.generalDerivatives = Array((s.generalDerivatives + Array(repeating: "", count: 7)).prefix(7))
            default:
                break
            }
            self.title = title
            self.close = close
            self.done = done
            originalLine = series.generalParameterLine
            originalTolerance = series.generalTolerance
            _s = State(initialValue: s)
            _initial = State(initialValue: ParameterLine.values(series.generalParameterLine))
            _history = State(initialValue: AppSettings.shared.stored(Self.historyKey, as: [String].self) ?? [])
            _autoRange = State(initialValue: series.curveStart == series.curveEnd)
        }

        var body: some View {
            Scaffold(title: title, message: s.kind == .function ? nil : "データ: \(s.name)",
                     width: s.kind == .generalLSQ ? 580 : 500) {
                VStack(spacing: 0) {
                    PageSwitcher(selection: $page, titles: [s.kind == .function ? "式" : "条件", "曲線"])
                    Form {
                        if page == 0 {
                            conditions
                        } else {
                            CurveSections(series: $s, autoRange: $autoRange, rangeApplies: rangeApplies,
                                          autoRangeHint: s.kind == .function ? "横軸の範囲に曲線を描きます。" : "データのある範囲に曲線を描きます。")
                        }
                    }
                    .formStyle(.grouped)
                    .labeledContentStyle(RowStyle())
                    .onSubmit { finish() }
                }
            } trailing: {
                CancelButton(close: close)
                DefaultButton(disabled: !canFinish) { finish() }
            }
        }

        /// パラメトリックスプラインは範囲と点の取り方を使わない
        private var rangeApplies: Bool {
            !(s.kind == .spline && s.lsqOrder != Spline.Mode.cubic.rawValue)
        }

        @ViewBuilder private var conditions: some View {
            switch s.kind {
            case .polynomialLSQ:
                polynomialSection
            case .expLSQ, .logLSQ, .powerLSQ:
                transformedSection
            case .generalLSQ:
                generalFunctionSection
                generalParameterSection
            case .spline:
                splineSection
            case .function:
                functionSection
            default:
                EmptyView()
            }
        }

        // MARK: - 多項式

        private var polynomialSection: some View {
            Section {
                LabeledContent("式") { Text(Self.polynomialFormula(s.lsqOrder)) }
                Picker("次数", selection: $s.lsqOrder) {
                    ForEach(0...9, id: \.self) { n in Text(Self.orderTitle(n)).tag(n) }
                }
                Toggle("特定の点を通す", isOn: $s.passThroughPoint)
                Group {
                    NumberRow(label: "通る点の x", value: $s.passX, width: 110)
                    NumberRow(label: "通る点の y", value: $s.passY, width: 110)
                }
                .disabled(!s.passThroughPoint)
                OutOfRangeToggle(series: $s)
            } header: {
                Text("当てはめの条件")
            }
        }

        static func orderTitle(_ n: Int) -> String {
            switch n {
            case 0: return "0 次(平均値)"
            case 1: return "1 次(直線)"
            default: return String(n) + " 次"
            }
        }

        static func polynomialFormula(_ order: Int) -> String {
            let sub = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]
            let sup = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
            func term(_ k: Int) -> String {
                switch k {
                case 0: return "a₀"
                case 1: return "a₁x"
                default: return "a" + sub[k] + "x" + sup[k]
                }
            }
            let n = min(max(order, 0), 9)
            let terms = n <= 3 ? (0...n).map(term) : [term(0), term(1), "…", term(n)]
            return "y = " + terms.joined(separator: " + ")
        }

        // MARK: - 指数・対数・べき

        private var transformedSection: some View {
            Section {
                LabeledContent("式") { Text(transformedFormula) }
                OutOfRangeToggle(series: $s)
            } header: {
                Text("当てはめの条件")
            } footer: {
                Text(transformedNote)
            }
        }

        private var transformedFormula: String {
            switch s.kind {
            case .expLSQ: return "ln y = a₀ + a₁x"
            case .logLSQ: return "y = a₀ + a₁ ln x"
            default: return "ln y = a₀ + a₁ ln x"
            }
        }

        private var transformedNote: String {
            switch s.kind {
            case .expLSQ: return "y = A exp(a₁x) の形です(A = exp(a₀))。y が正の点だけを使います。"
            case .logLSQ: return "x が正の点だけを使います。"
            default: return "y = A x^a₁ の形です(A = exp(a₀))。x と y がともに正の点だけを使います。"
            }
        }

        // MARK: - 一般の関数

        private var generalFunctionSection: some View {
            Section {
                HStack(spacing: 6) {
                    Text(verbatim: "f(x) =")
                        .font(.body.monospaced())
                    TextField("関数", text: $s.generalFunction, prompt: Text(verbatim: "a*exp(-b*x)+c"))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .labelsHidden()
                    historyMenu
                }
                OutOfRangeToggle(series: $s)
            } header: {
                Text("当てはめる関数")
            } footer: {
                StatusLine(error: functionError, hint: "x とパラメータ a〜g で書きます。h と i は定数の値を使います。")
            }
        }

        private var historyMenu: some View {
            Menu {
                ForEach(history, id: \.self) { f in
                    Button(f) {
                        Sheets.endEditing()
                        s.generalFunction = f
                    }
                }
                Divider()
                Button("履歴を消去") {
                    history = []
                    AppSettings.shared.store(history, key: Self.historyKey)
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(history.isEmpty)
            .help("最近使った関数")
        }

        private var generalParameterSection: some View {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        Text(verbatim: "")
                        Text("初期値")
                        Text("固定")
                        Text("偏導関数(省略できます)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(0..<7, id: \.self) { k in parameterRow(k) }
                }
                NumberRow(label: "許容誤差", value: toleranceBinding, unit: "%")
            } header: {
                Text("パラメータ")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let derivativeError { StatusLine(error: derivativeError, hint: "") }
                    Text("偏導関数を空欄にすると差分で近似します。パラメータの変化が許容誤差を下回ると計算を終えます。")
                }
            }
        }

        private func parameterRow(_ k: Int) -> some View {
            let name = Fitting.parameterNames[k]
            let fade = usedParameters?.contains(name) == false ? 0.45 : 1
            return GridRow {
                Text(name)
                    .font(.body.monospaced())
                    .opacity(fade)
                NumberField(value: $initial[k], width: 96)
                    .opacity(fade)
                Toggle("固定", isOn: fixedBinding(name))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("固定")
                    .gridColumnAlignment(.center)
                    .opacity(fade)
                TextField("∂f/∂" + name, text: $s.generalDerivatives[k], prompt: Text(verbatim: "∂f/∂" + name))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .opacity(fade)
            }
        }

        private func fixedBinding(_ name: String) -> Binding<Bool> {
            Binding(get: { s.generalFixed.contains(name) },
                    set: { on in
                        if on { s.generalFixed.insert(name) } else { s.generalFixed.remove(name) }
                    })
        }

        private var toleranceBinding: Binding<Double> {
            Binding(get: { s.generalTolerance }, set: { s.generalTolerance = min(max($0, 0), 10) })
        }

        /// 関数に使われている名前(関数が空か読めなければ nil)
        private var usedParameters: Set<String>? {
            let t = s.generalFunction.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, let e = try? SMPKit.Expression(t) else { return nil }
            return e.referencedVariables()
        }

        private var functionError: String? {
            let t = s.generalFunction.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            if let p = ExpressionCheck.problem(t, allowColumns: false) { return p }
            if let used = usedParameters, used.isDisjoint(with: Fitting.parameterNames) {
                return "パラメータ(a〜g)を 1 つ以上使ってください。"
            }
            return nil
        }

        private var derivativeError: String? {
            for (k, d) in s.generalDerivatives.prefix(7).enumerated() {
                if let p = ExpressionCheck.problem(d, allowColumns: false) {
                    return "∂f/∂" + Fitting.parameterNames[k] + ": " + p
                }
            }
            return nil
        }

        // MARK: - スプライン

        private var splineSection: some View {
            Section {
                Picker("種類", selection: $s.lsqOrder) {
                    ForEach(Spline.Mode.allCases, id: \.self) { m in Text(m.displayTitle).tag(m.rawValue) }
                }
                OutOfRangeToggle(series: $s)
            } header: {
                Text("スプライン")
            } footer: {
                Text(splineNote)
            }
        }

        private var splineNote: String {
            switch Spline.Mode(rawValue: s.lsqOrder) ?? .cubic {
            case .cubic: return "x の小さい順に点をなめらかに結びます。同じ x の点は平均します。"
            case .parametric: return "データの並び順に点をなめらかに結びます。x が戻るデータにも使えます。"
            case .closedParametric: return "データの並び順に点を結び、最後の点から最初の点へ戻って閉じます。"
            }
        }

        // MARK: - 関数

        private var functionSection: some View {
            Section {
                HStack(spacing: 6) {
                    Text(verbatim: "y =")
                        .font(.body.monospaced())
                    TextField("式", text: $s.expressionY, prompt: Text(verbatim: "sin(x)/x"))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .labelsHidden()
                }
            } header: {
                Text("関数")
            } footer: {
                StatusLine(error: expressionError, hint: "x を使った式で y を表します。定数 a〜i も使えます。")
            }
        }

        private var expressionError: String? {
            ExpressionCheck.problem(s.expressionY, allowColumns: true)
        }

        // MARK: - OK

        private var canFinish: Bool {
            switch s.kind {
            case .generalLSQ:
                return !s.generalFunction.trimmingCharacters(in: .whitespaces).isEmpty && functionError == nil && derivativeError == nil
            case .function:
                return !s.expressionY.trimmingCharacters(in: .whitespaces).isEmpty && expressionError == nil
            default:
                return true
            }
        }

        private func finish() {
            // 式に誤りがあるあいだは、Return を押しても欄から離れずに待つ
            guard canFinish, !finished else { return }
            Sheets.endEditing()
            finished = true
            var r = s
            switch r.kind {
            case .generalLSQ:
                r.generalFunction = r.generalFunction.trimmingCharacters(in: .whitespaces)
                r.generalDerivatives = r.generalDerivatives.map { $0.trimmingCharacters(in: .whitespaces) }
                let toleranceChanged = r.generalTolerance != originalTolerance
                r.generalParameterLine = ParameterLine.line(original: originalLine, values: initial,
                                                            tolerance: toleranceChanged ? r.generalTolerance : nil)
                rememberFunction(r.generalFunction)
            case .function:
                r.expressionY = r.expressionY.trimmingCharacters(in: .whitespaces)
                r.transformY = true
            default:
                break
            }
            if autoRange {
                r.curveStart = 0
                r.curveEnd = 0
            }
            r.curveDivisions = min(max(r.curveDivisions, 1), 3999)
            close()
            done(r)
        }

        private func rememberFunction(_ f: String) {
            var list = history.filter { $0 != f }
            list.insert(f, at: 0)
            AppSettings.shared.store(Array(list.prefix(Self.historyLimit)), key: Self.historyKey)
        }
    }

    /// 一般の関数の初期値の行(古い形は "7 a b c d e f g 0"、新しい形は "9 許容誤差 a b c d e f g h i")
    enum ParameterLine {
        /// a〜g の初期値(書かれていないものは 1)
        static func values(_ line: String) -> [Double] {
            let d = SeriesEvaluator.initialParameters(line)
            return Fitting.parameterNames.map { d[$0] ?? 1 }
        }

        /// 初期値を入れた行。元の行の形を残し、変えていない値は元の書き方のままにする。
        /// tolerance(変えたときだけ渡す)は新しい形の行にしか書けないので、その形にする
        static func line(original: String, values: [Double], tolerance: Double?) -> String {
            var tokens = original.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            let numbers = tokens.map { Double($0) }
            let allNumeric = !numbers.contains { $0 == nil }
            var changed = false
            func put(_ i: Int, _ v: Double) {
                guard i < tokens.count, numbers[i] != v else { return }
                tokens[i] = Plain.string(v)
                changed = true
            }
            if allNumeric, tokens.count >= 11, numbers[0] == 9 {
                for k in 0..<7 { put(k + 2, values[k]) }
                if let tolerance { put(1, tolerance) }
                return changed ? tokens.joined(separator: " ") : original
            }
            if let tolerance {
                // h・i の初期値は使わないので 1 にしておく
                return (["9", Plain.string(tolerance)] + values.map(Plain.string) + ["1", "1"]).joined(separator: " ")
            }
            if allNumeric, tokens.count >= 8, numbers[0] == 7 {
                for k in 0..<7 { put(k + 1, values[k]) }
                return changed ? tokens.joined(separator: " ") : original
            }
            return (["7"] + values.map(Plain.string) + ["0"]).joined(separator: " ")
        }
    }

    /// 軸の範囲外の点を計算に使うか(データを使う解析に共通)
    struct OutOfRangeToggle: View {
        @Binding var series: Series

        var body: some View {
            Toggle("軸の範囲外にある点も計算に使う", isOn: $series.considerOutOfRange)
                .help("オフにすると、軸の範囲に入っている点だけで計算します。")
        }
    }

    /// 曲線を描く範囲と、曲線の線(解析のシートに共通)
    struct CurveSections: View {
        @Binding var series: Series
        @Binding var autoRange: Bool
        /// false なら範囲と点の取り方を使わない(パラメトリックスプライン)
        var rangeApplies: Bool
        /// 範囲を自動にしたときの説明
        var autoRangeHint: String

        var body: some View {
            Section {
                Toggle("範囲を自動で決める", isOn: $autoRange)
                    .disabled(!rangeApplies)
                LabeledContent("範囲") {
                    HStack(spacing: 6) {
                        NumberField(value: $series.curveStart, width: 100)
                        Text(verbatim: "〜").foregroundStyle(.secondary)
                        NumberField(value: $series.curveEnd, width: 100)
                    }
                }
                .disabled(autoRange || !rangeApplies)
                IntRow(label: "分割数", value: divisions)
                    .help("曲線を区切る数です(1〜3999)。")
                Picker("点の取り方", selection: $series.curveSpacing) {
                    Text("等間隔").tag(Series.CurveSpacing.linear)
                    Text("指数的").tag(Series.CurveSpacing.exponential)
                    Text("逆数的").tag(Series.CurveSpacing.reciprocal)
                }
                .disabled(!rangeApplies)
                .help("指数的は log x が、逆数的は 1/x が等間隔になるように点を取ります。指数的は範囲が正のときに使えます。")
            } header: {
                Text("曲線を描く範囲")
            } footer: {
                if let note { Text(note) }
            }
            Section {
                LineTypePicker(label: "線の種類", lineType: $series.curveLineType)
                Group {
                    NumberRow(label: "太さ", value: mm($series.curveWidth), unit: "mm")
                    ColorRow(label: "色", color: $series.curveColor)
                    NumberRow(label: "破線の間隔", value: mm($series.curvePitch), unit: "mm")
                        .disabled(series.curveLineType == .solid)
                }
                .disabled(series.curveLineType == .none)
            } header: {
                Text("曲線の線")
            }
        }

        private var note: String? {
            if !rangeApplies { return "パラメトリックスプラインはデータの並び順に描くため、範囲と点の取り方は使いません。" }
            return autoRange ? autoRangeHint : nil
        }

        private var divisions: Binding<Int> {
            Binding(get: { series.curveDivisions }, set: { series.curveDivisions = min(max($0, 1), 3999) })
        }
    }
}
