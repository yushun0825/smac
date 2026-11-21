import SwiftUI
import AppKit
import SMPKit

// インスペクタの欄と、値の変換の道具

/// 文字の欄。打ち込むたびではなく、Return を押したときと、ほかの欄へ移ったときに書類へ入れる
struct InspectorTextField: View {
    @Binding var text: String
    var prompt: String = ""
    var monospaced = false
    /// 入っている文字の問題(なければ nil)。赤い字で欄の下に出す
    var validate: ((String) -> String?)? = nil

    @State private var draft = ""
    /// 打ち込み中の行き先(打ち込んでいる間に選ぶものが変わっても、元のものへ入れる)
    @State private var editing: Binding<String>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField("", text: $draft, prompt: prompt.isEmpty ? nil : Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(monospaced ? .system(size: NSFont.smallSystemFontSize, design: .monospaced) : nil)
                .focused($focused)
                .onSubmit(commit)
            if let validate, let message = validate(draft) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { draft = text }
        .onChange(of: text) { _, new in
            if editing == nil { draft = new }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                editing = $text
            } else {
                commit()
                editing = nil
                draft = text
            }
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        let target = editing ?? $text
        // SMP では 1 行で持つので、改行は空白にする
        let value = draft.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        if target.wrappedValue != value { target.wrappedValue = value }
    }
}

/// フォント名(打ち込むか、よく使うものから選ぶ)。選べる名前は FontNameField と同じ
struct InspectorFontNameRow: View {
    var label: String
    @Binding var name: String
    var japanese: Bool

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 2) {
                InspectorTextField(text: $name, prompt: japanese ? "和文のフォント" : "欧文のフォント")
                Menu {
                    ForEach(japanese ? FontNameField.japaneseChoices : FontNameField.latinChoices, id: \.self) { n in
                        Button(n) { name = n }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("よく使うフォントから選ぶ")
            }
        }
    }
}

/// 角度(数で入れるか、0°・90°・180°・270° から選ぶ)
struct InspectorAngleRow: View {
    var label = "角度"
    @Binding var angle: Double

    var body: some View {
        LabeledContent(label) {
            // 欄の幅と右端は NumberRow(幅 72・単位 18)にそろえる
            HStack(spacing: 4) {
                TextField("", value: $angle, format: .plain)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                HStack(spacing: 0) {
                    Text("°")
                        .foregroundStyle(.secondary)
                    Menu {
                        ForEach([0, 90, 180, 270], id: \.self) { a in
                            Button("\(a)°") { angle = Double(a) }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("よく使う角度から選ぶ")
                }
                .frame(minWidth: 18, alignment: .leading)
            }
        }
    }
}

/// 解析の結果の文(等幅・選んでコピーできる)
struct InspectorResultsView: View {
    var lines: [String]

    var body: some View {
        Text(lines.joined(separator: "\n"))
            .font(.system(size: NSFont.smallSystemFontSize, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// インスペクタで使う小さな道具(値の範囲・変換・名前)
enum InspectorKit {
    // MARK: 書類から読む(添字がずれていても落ちない)

    @MainActor
    static func graph(_ state: EditorState, _ gi: Int) -> Graph {
        let p = state.project
        return p.graphs.indices.contains(gi) ? p.graphs[gi] : Graph()
    }

    @MainActor
    static func series(_ state: EditorState, _ gi: Int, _ si: Int) -> Series {
        let g = graph(state, gi)
        return g.series.indices.contains(si) ? g.series[si] : Series(name: "")
    }

    // MARK: 値の範囲

    static func clamped(_ b: Binding<Int>, _ range: ClosedRange<Int>) -> Binding<Int> {
        Binding(get: { b.wrappedValue }, set: { b.wrappedValue = Swift.min(Swift.max($0, range.lowerBound), range.upperBound) })
    }

    /// 整数の値を数値の欄(NumberRow)で編集する(四捨五入して範囲に収める)
    static func integer(_ b: Binding<Int>, _ range: ClosedRange<Int>) -> Binding<Double> {
        Binding(get: { Double(b.wrappedValue) }, set: { v in
            guard v.isFinite else { return }
            let r = Swift.min(Swift.max(v.rounded(), Double(range.lowerBound)), Double(range.upperBound))
            b.wrappedValue = Int(r)
        })
    }

    /// 数でない値(∞ など)は入れない
    static func finite(_ b: Binding<Double>) -> Binding<Double> {
        Binding(get: { b.wrappedValue }, set: { v in
            if v.isFinite { b.wrappedValue = v }
        })
    }

    /// 0.01 mm の整数を mm で編集する(mm() に下限と、大きすぎる値の止めを足したもの)
    static func millimeters(_ b: Binding<Int>, min lo: Double = -100_000) -> Binding<Double> {
        let inner = mm(b)
        return Binding(get: { inner.wrappedValue }, set: { v in
            guard v.isFinite else { return }
            inner.wrappedValue = Swift.min(Swift.max(v, lo), 100_000)
        })
    }

    /// フォントの大きさ(pt)
    static func pointSize(_ font: Binding<LogFont>) -> Binding<Double> {
        let inner = points(font)
        return Binding(get: { inner.wrappedValue }, set: { v in
            guard v.isFinite else { return }
            inner.wrappedValue = Swift.min(Swift.max(v, 1), 999)
        })
    }

    /// 線種(1 実線〜5 二点鎖線)。0 などは実線として見せる
    static func lineStyle(_ b: Binding<Int>) -> Binding<Int> {
        Binding(get: { Swift.min(Swift.max(b.wrappedValue, 1), 5) }, set: { b.wrappedValue = $0 })
    }

    /// 破線・点線など、間隔を持つ線種か
    static func isDashed(_ code: Int) -> Bool { (2...5).contains(code) }

    // MARK: 軸

    static func scaleName(_ t: ScaleType) -> String {
        switch t {
        case .linear: return "線形"
        case .logExponent: return "対数(指数表示)"
        case .logNormal: return "対数"
        case .inverseReciprocal: return "逆数(逆数表示)"
        case .inverseNormal: return "逆数"
        }
    }

    static func frameName(_ t: FrameType) -> String {
        switch t {
        case .box: return "枠"
        case .grid: return "方眼"
        case .halfBox: return "L 字"
        case .axes: return "軸"
        }
    }

    /// 目盛りの向き(1 内側 2 外側 3 両側 0 なし)
    static func tickDirection(_ t: Binding<TickStyle>) -> Binding<Int> {
        Binding(get: { (t.wrappedValue.inside ? 1 : 0) + (t.wrappedValue.outside ? 2 : 0) }, set: { v in
            var s = t.wrappedValue
            s.inside = v & 1 != 0
            s.outside = v & 2 != 0
            t.wrappedValue = s
        })
    }

    /// 対数の軸の主目盛りの位置(Increment の 1〜5。それ以外は「1 のみ」として 10 で見せる)
    static func logMajor(_ inc: Binding<Double>) -> Binding<Int> {
        Binding(get: {
            let v = inc.wrappedValue
            guard v.isFinite, Swift.abs(v) < 1_000 else { return 10 }
            let i = Int(v.rounded())
            return (1...5).contains(i) ? i : 10
        }, set: { inc.wrappedValue = Double($0) })
    }

    /// 対数の軸の副目盛り(Division が 2 以上なら付く)
    static func logMinor(_ division: Binding<Int>) -> Binding<Bool> {
        Binding(get: { division.wrappedValue >= 2 }, set: { division.wrappedValue = $0 ? 10 : 1 })
    }

    /// 桁数(範囲の外は「自動」= 5 として見せる)
    static func digits(_ b: Binding<Int>, _ range: ClosedRange<Int>) -> Binding<Int> {
        Binding(get: { range.contains(b.wrappedValue) ? b.wrappedValue : 5 }, set: { b.wrappedValue = $0 })
    }

    // MARK: データ

    /// データファイルの列の数(先頭 200 行で数えたいちばん多いもの)
    static func columnCount(_ file: DataFile?, tabAsSpace: Bool) -> Int {
        guard let file else { return 0 }
        var n = 0
        for line in file.lines.prefix(200) {
            if case .values(let v) = DataParser.parse(line: line, tabAsSpace: tabAsSpace) { n = Swift.max(n, v.count) }
        }
        return n
    }

    static let variableNames: Set<String> = ["x", "y", "pi", "a", "b", "c", "d", "e", "f", "g", "h", "i"]

    /// 変換の式の問題(なければ nil)。式の形と、使えない名前を調べる
    static func expressionProblem(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        do {
            let e = try SMPKit.Expression(t)
            if let bad = e.referencedVariables().subtracting(variableNames).sorted().first {
                return "「\(bad)」は使えない名前です。"
            }
            return nil
        } catch let e as ExpressionError {
            return e.message
        } catch {
            return error.localizedDescription
        }
    }

    /// 曲線の解析の名前
    static func curveTitle(_ s: Series) -> String {
        if let a = s.extensionAnalysis { return a.displayTitle }
        switch s.kind {
        case .polynomialLSQ: return "多項式(\(s.lsqOrder) 次)で当てはめ"
        case .spline: return (Spline.Mode(rawValue: s.lsqOrder) ?? .cubic).displayTitle
        case .function: return s.kind.displayTitle
        default: return s.analysisTitle ?? s.kind.displayTitle
        }
    }

    @MainActor
    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: 文字・図形

    /// 文字の大きさ(欧文・和文・記号のフォントをそろえて変える)
    static func textSize(_ b: Binding<TextObject>) -> Binding<Double> {
        Binding(get: { b.wrappedValue.latinFont.pointSize }, set: { v in
            guard v.isFinite else { return }
            let p = Swift.min(Swift.max(v, 1), 999)
            var t = b.wrappedValue
            t.latinFont.pointSize = p
            t.japaneseFont.pointSize = p
            t.symbolFont.pointSize = p
            b.wrappedValue = t
        })
    }

    /// 太字・斜体(欧文・和文・記号のフォントをそろえて変える)
    static func textStyle(_ b: Binding<TextObject>) -> Binding<LogFont> {
        Binding(get: { b.wrappedValue.latinFont }, set: { f in
            var t = b.wrappedValue
            t.latinFont.weight = f.weight
            t.latinFont.italic = f.italic
            t.japaneseFont.weight = f.weight
            t.japaneseFont.italic = f.italic
            t.symbolFont.weight = f.weight
            t.symbolFont.italic = f.italic
            b.wrappedValue = t
        })
    }

    /// 文字の後ろを白で塗るか(backgroundMode 2 = 塗る、1 = 透かす)
    static func opaqueBackground(_ b: Binding<TextObject>) -> Binding<Bool> {
        Binding(get: { b.wrappedValue.backgroundMode == 2 }, set: { b.wrappedValue.backgroundMode = $0 ? 2 : 1 })
    }

    /// 矢じりの開き(headOpen / 100)
    static func headOpening(_ b: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(b.wrappedValue) / 100 }, set: { v in
            guard v.isFinite else { return }
            b.wrappedValue = Int((Swift.min(Swift.max(v, 0.01), 100) * 100).rounded())
        })
    }

    enum PictureEdge { case left, top, width, height }

    /// 図の左・上・幅・高さ(x2 = x1 + 幅、y2 = y1 + 高さ に保つ)
    static func pictureGeometry(_ b: Binding<PictureObject>, _ edge: PictureEdge) -> Binding<Double> {
        Binding(get: {
            let s = b.wrappedValue.shape
            switch edge {
            case .left: return Swift.min(s.x1, s.x2)
            case .top: return Swift.min(s.y1, s.y2)
            case .width: return Swift.abs(s.x2 - s.x1)
            case .height: return Swift.abs(s.y2 - s.y1)
            }
        }, set: { v in
            guard v.isFinite else { return }
            var p = b.wrappedValue
            var s = p.shape
            let left = Swift.min(s.x1, s.x2), top = Swift.min(s.y1, s.y2)
            let w = Swift.abs(s.x2 - s.x1), h = Swift.abs(s.y2 - s.y1)
            switch edge {
            case .left: s.x1 = v; s.x2 = v + w
            case .top: s.y1 = v; s.y2 = v + h
            case .width: s.x1 = left; s.x2 = left + Swift.max(v, 0.1)
            case .height: s.y1 = top; s.y2 = top + Swift.max(v, 0.1)
            }
            p.shape = s
            b.wrappedValue = p
        })
    }

    /// 矢印・枠の位置の単位を変えるとき、同じ場所のままになるよう値を直す。
    /// reference 0: mm(グラフの枠の左上から)、1: X・Y 軸の値、2: 上・右の軸の値
    static func convertPosition(_ v: Double, horizontal: Bool, from: Int, to: Int, graph g: Graph) -> Double {
        guard from != to, v.isFinite else { return v }
        let fr = GraphRenderer.Frame(g)
        func axisIndex(_ ref: Int) -> Int { horizontal ? (ref == 2 ? 2 : 0) : (ref == 2 ? 3 : 1) }
        // 枠の中の位置(0.01 mm)
        let position: Double?
        if from == 0 {
            position = v * 100
        } else {
            position = horizontal ? fr.px(v, axis: axisIndex(from)) : fr.py(v, axis: axisIndex(from))
        }
        guard let p = position, p.isFinite else { return v }
        if to == 0 { return p.rounded() / 100 }
        let length = horizontal ? fr.width : fr.height
        guard length > 0 else { return v }
        let f = horizontal ? p / length : 1 - p / length
        let value = fr.scales[axisIndex(to)].value(atFraction: f)
        guard value.isFinite else { return v }
        return Double(String(format: "%.6g", value)) ?? value
    }
}
