import SwiftUI
import AppKit
import SMPKit

// インスペクタとシートで使う部品(数値の欄・色・線種・ドットの形・中塗り・フォント・制御コード)

/// 3 桁区切りを付けない数値の書式
extension FormatStyle where Self == FloatingPointFormatStyle<Double> {
    static var plain: FloatingPointFormatStyle<Double> { .number.grouping(.never).precision(.significantDigits(1...10)) }
}

extension FormatStyle where Self == IntegerFormatStyle<Int> {
    static var plainInt: IntegerFormatStyle<Int> { .number.grouping(.never) }
}

/// 数値の欄(ラベル・単位付き)。値は Return か別の欄へ移ったときに入る
struct NumberRow: View {
    var label: String
    @Binding var value: Double
    var unit: String = ""
    var width: CGFloat = 72

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField("", value: $value, format: .plain)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: width)
                if !unit.isEmpty { Text(unit).foregroundStyle(.secondary).frame(minWidth: 18, alignment: .leading) }
            }
        }
    }
}

struct IntRow: View {
    var label: String
    @Binding var value: Int
    var unit: String = ""
    var width: CGFloat = 60

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField("", value: $value, format: .plainInt)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: width)
                if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
            }
        }
    }
}

/// 0.01 mm の整数を mm の小数として編集する
func mm(_ b: Binding<Int>) -> Binding<Double> {
    Binding(get: { Double(b.wrappedValue) / 100 }, set: { b.wrappedValue = Int(($0 * 100).rounded()) })
}

/// pt の大きさ(LOGFONT の高さ)
func points(_ b: Binding<LogFont>) -> Binding<Double> {
    Binding(get: { b.wrappedValue.pointSize }, set: { b.wrappedValue.pointSize = max($0, 1) })
}

extension SMPColor {
    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }

    var nsColor: NSColor { NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }

    var cgColor: CGColor { CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }

    init(_ c: Color) {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .black
        self.init(r: UInt8(max(0, min(255, (ns.redComponent * 255).rounded()))),
                  g: UInt8(max(0, min(255, (ns.greenComponent * 255).rounded()))),
                  b: UInt8(max(0, min(255, (ns.blueComponent * 255).rounded()))))
    }
}

func colorBinding(_ b: Binding<SMPColor>) -> Binding<Color> {
    Binding(get: { b.wrappedValue.color }, set: { b.wrappedValue = SMPColor($0) })
}

struct ColorRow: View {
    var label: String
    @Binding var color: SMPColor

    var body: some View {
        LabeledContent(label) {
            ColorPicker("", selection: colorBinding($color), supportsOpacity: false)
                .labelsHidden()
        }
    }
}

/// 線種(見本の線つき)
struct LineTypePicker: View {
    var label: String
    @Binding var lineType: LineType
    var allowFill = false

    var body: some View {
        Picker(label, selection: $lineType) {
            ForEach(LineType.allCases.filter { allowFill || $0 != .fill }, id: \.self) { t in
                Label { Text(t.title) } icon: { Image(nsImage: Swatches.line(t.rawValue)) }.tag(t)
            }
        }
    }
}

/// 線種(Int で持つもの。1 実線 2 破線 …)
struct LineStylePicker: View {
    var label: String
    @Binding var style: Int

    var body: some View {
        Picker(label, selection: $style) {
            ForEach(1...5, id: \.self) { t in
                Label { Text(LineType(code: t).title) } icon: { Image(nsImage: Swatches.line(t)) }.tag(t)
            }
        }
    }
}

/// ドットの形
struct PlotTypePicker: View {
    var label: String
    @Binding var code: Int
    var codes: [Int] = PlotType.seriesCodes

    var body: some View {
        Picker(label, selection: $code) {
            ForEach(codes, id: \.self) { c in
                Label { Text(PlotNames.name(c)) } icon: { Image(nsImage: Swatches.mark(c)) }.tag(c)
            }
            if !codes.contains(code) { Text("番号 \(code)").tag(code) }
        }
    }
}

/// ドットの名前(メニューに出す)
enum PlotNames {
    static func name(_ c: Int) -> String {
        switch c {
        case 0: return "なし"
        case 1: return "丸(白抜き)"
        case 2: return "丸"
        case 3: return "三角(白抜き)"
        case 4: return "三角"
        case 5: return "四角(白抜き)"
        case 6: return "四角"
        case 7: return "逆三角(白抜き)"
        case 8: return "逆三角"
        case 9: return "ひし形(白抜き)"
        case 10: return "ひし形"
        case 11: return "十字"
        case 12: return "バツ"
        case 13: return "縦の棒グラフ"
        case 26: return "横の棒グラフ"
        case 27: return "ヒストグラム"
        case 28, 24: return "斜線(/)"
        case 25: return "斜線(\\)"
        case 33: return "階段(縦)"
        case 34: return "階段(横)"
        case 38: return "六角形"
        case 39: return "五角形"
        case 40: return "逆五角形"
        case 41: return "星"
        case 42: return "丸に十字"
        case 43: return "丸にバツ"
        case 44...48: return "半分塗り \(c - 43)"
        case 49...52: return "丸に線 \(c - 48)"
        case 14...18: return "形 \(c)(中塗り色)"
        case 19...23: return "形 \(c)(点の色)"
        default: return "番号 \(c)"
        }
    }
}

/// 中塗り(LOGBRUSH の形と模様)
struct BrushPicker: View {
    var label = "中塗り"
    @Binding var style: Int
    @Binding var hatch: Int
    static let titles = ["塗る", "塗らない", "白", "縦線", "斜線(\\)", "斜線(/)", "格子", "斜め格子", "横線"]

    var body: some View {
        Picker(label, selection: Binding(get: { DotBrush.index(style: style, hatch: hatch) }, set: { i in
            let v = DotBrush.values(index: i)
            style = v.style
            if v.style == 2 { hatch = v.hatch }
        })) {
            ForEach(0..<BrushPicker.titles.count, id: \.self) { i in Text(BrushPicker.titles[i]).tag(i) }
        }
    }
}

/// フォント名(SMP には Windows の名前のまま保存する。描くときは Mac の近いフォントを使う)
struct FontNameField: View {
    var label: String
    @Binding var name: String
    var japanese: Bool

    static let latinChoices = ["Times New Roman", "Arial", "Helvetica", "Courier New", "Century", "Symbol"]
    static let japaneseChoices = ["ＭＳ 明朝", "ＭＳ ゴシック", "游明朝", "游ゴシック", "ヒラギノ明朝", "ヒラギノ角ゴ"]

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 2) {
                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
                Menu {
                    ForEach(japanese ? FontNameField.japaneseChoices : FontNameField.latinChoices, id: \.self) { n in
                        Button(n) { name = n }
                    }
                } label: { Image(systemName: "chevron.down") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }
}

/// 太字・斜体
struct FontStylePicker: View {
    var label: String = "書体"
    @Binding var font: LogFont

    var body: some View {
        Picker(label, selection: Binding(get: { (font.isBold ? 2 : 0) + (font.isItalic ? 1 : 0) }, set: { v in
            font.isBold = v >= 2
            font.isItalic = v % 2 == 1
        })) {
            Text("標準").tag(0)
            Text("斜体").tag(1)
            Text("太字").tag(2)
            Text("太字斜体").tag(3)
        }
    }
}

/// 文字の書式の記号を入れるメニュー
struct ControlCodeMenu: View {
    var insert: (String) -> Void

    var body: some View {
        Menu {
            Button("上付き  ^…@") { insert("^@") }
            Button("下付き  _…@") { insert("_@") }
            Button("改行  \\n") { insert("\\n") }
            Divider()
            Button("斜体  %I") { insert("%I") }
            Button("太字  %B") { insert("%B") }
            Button("標準に戻す  %R") { insert("%R") }
            Button("下線  %U…%U") { insert("%U%U") }
            Button("上線  %L…%L") { insert("%L%L") }
            Divider()
            Menu("ギリシャ文字") {
                ForEach(GreekLetter.all, id: \.code) { g in
                    Button("\(g.glyph)  %G\(g.code)%A") { insert("%G\(g.code)%A") }
                }
            }
            Menu("記号") {
                Button("°  %Q176") { insert("%Q176") }
                Button("±  %Q177") { insert("%Q177") }
                Button("×  %Q215") { insert("%Q215") }
                Button("÷  %Q247") { insert("%Q247") }
                Button("Å  %Q197") { insert("%Q197") }
                Button("µ  %Q181") { insert("%Q181") }
                Divider()
                Button("√  %G%Q214%A") { insert("%G%Q214%A") }
                Button("∞  %G%Q165%A") { insert("%G%Q165%A") }
                Button("∂  %G%Q182%A") { insert("%G%Q182%A") }
                Button("≦  %G%Q163%A") { insert("%G%Q163%A") }
                Button("≧  %G%Q179%A") { insert("%G%Q179%A") }
                Button("→  %G%Q174%A") { insert("%G%Q174%A") }
            }
            Divider()
            Menu("データの情報") {
                Button("データの名前  %01N") { insert("%01N") }
                Button("ドットの見本  %01E") { insert("%01E") }
                Button("曲線の見本  %01F") { insert("%01F") }
                Button("今日の日付  %M") { insert("%M") }
            }
            Button("文字の大きさ  %S080") { insert("%S080") }
            Button("色  %KFF0000") { insert("%KFF0000") }
        } label: {
            Label("書式", systemImage: "textformat.superscript")
        }
        .fixedSize()
    }
}

struct GreekLetter {
    var code: String
    var glyph: String

    static let all: [GreekLetter] = "abgdezhqiklmnxprstufcywGDQLXPSFYW".map { ch in
        GreekLetter(code: String(ch), glyph: SymbolEncoding.map(String(ch)))
    }
}

/// 小さな見本の絵(ドット・線・色)
@MainActor
enum Swatches {
    private static var cache: [String: NSImage] = [:]

    static func mark(_ code: Int, color: SMPColor = .black) -> NSImage {
        let key = "m\(code)-\(color.colorref)"
        if let c = cache[key] { return c }
        let img = NSImage(size: NSSize(width: 18, height: 14), flipped: true) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            if code == 0 { return true }
            GraphRenderer.drawPlotMark(code: code, center: CGPoint(x: r.midX, y: r.midY), diameter: 9, dotColor: color, lineWidth: 1,
                                       brushStyle: 0, brushColor: .white, brushHatch: 0, in: ctx)
            return true
        }
        cache[key] = img
        return img
    }

    static func line(_ type: Int) -> NSImage {
        let key = "l\(type)"
        if let c = cache[key] { return c }
        let img = NSImage(size: NSSize(width: 30, height: 12), flipped: true) { r in
            guard type > 0, type < 6, let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.setStrokeColor(NSColor.labelColor.cgColor)
            ctx.setLineWidth(1.2)
            let d = GraphRenderer.dash(type, pitch: 300, width: 40).map { $0 / 50 }
            if !d.isEmpty { ctx.setLineDash(phase: 0, lengths: d) }
            ctx.move(to: CGPoint(x: 1, y: r.midY)); ctx.addLine(to: CGPoint(x: r.maxX - 1, y: r.midY))
            ctx.strokePath()
            return true
        }
        cache[key] = img
        return img
    }
}

/// 系列の見本(ドットと線)を描く小さなビュー
struct SeriesSwatch: View {
    var series: Series

    var body: some View {
        Canvas { context, size in
            context.withCGContext { ctx in
                let s = series
                let y = size.height / 2
                if s.lineType != .none && s.lineType != .fill {
                    ctx.setStrokeColor(s.lineColor.cgColor)
                    ctx.setLineWidth(1.2)
                    let d = GraphRenderer.dash(s.lineType.rawValue, pitch: 300, width: 40).map { $0 / 60 }
                    if !d.isEmpty { ctx.setLineDash(phase: 0, lengths: d) }
                    ctx.move(to: CGPoint(x: 1, y: y)); ctx.addLine(to: CGPoint(x: size.width - 1, y: y))
                    ctx.strokePath()
                    ctx.setLineDash(phase: 0, lengths: [])
                } else if s.kind.hasCurve || s.extensionAnalysis != nil {
                    ctx.setStrokeColor(s.curveColor.cgColor)
                    ctx.setLineWidth(1.2)
                    ctx.move(to: CGPoint(x: 1, y: y)); ctx.addLine(to: CGPoint(x: size.width - 1, y: y))
                    ctx.strokePath()
                }
                if PlotType.drawsMark(s.dotType) || PlotType.isBarOrStep(s.dotType) {
                    GraphRenderer.drawPlotMark(code: s.dotType, center: CGPoint(x: size.width / 2, y: y), diameter: 8, dotColor: s.dotColor,
                                               lineWidth: 1, brushStyle: s.brushStyle, brushColor: s.brushColor, brushHatch: s.brushHatch, in: ctx)
                }
            }
        }
        .frame(width: 26, height: 14)
    }
}

/// 文字を描いて見せる(インスペクタの見本)
struct RichTextPreview: NSViewRepresentable {
    var text: String
    var latin: LogFont
    var japanese: LogFont
    var color: SMPColor

    func makeNSView(context: Context) -> PreviewView { PreviewView() }

    func updateNSView(_ v: PreviewView, context: Context) {
        v.text = text; v.latin = latin; v.japanese = japanese; v.color = color
        v.needsDisplay = true
    }

    final class PreviewView: NSView {
        var text = ""
        var latin = LogFont.latinDefault()
        var japanese = LogFont.japaneseDefault()
        var color = SMPColor.black
        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
            NSColor.separatorColor.setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).stroke()
            guard let ctx = NSGraphicsContext.current?.cgContext, !text.isEmpty else { return }
            var l = latin; l.angle = 0
            var j = japanese; j.angle = 0
            let lay = TextLayoutEngine.layout(text, latin: l, japanese: j, color: color, environment: TextEnvironment())
            let b = lay.bounds
            let scale = min(1.0, (bounds.width - 16) / max(b.width * Units.pointsPerHundredthMM, 1),
                            (bounds.height - 12) / max(b.height * Units.pointsPerHundredthMM, 1))
            let k = CGFloat(Units.pointsPerHundredthMM) * CGFloat(scale)
            ctx.saveGState()
            ctx.translateBy(x: 8, y: (bounds.height - b.height * k) / 2)
            ctx.scaleBy(x: k, y: k)
            let renderer = GraphRenderer(project: SMPProject(), plotData: [])
            renderer.drawLayout(lay, at: CGPoint(x: -b.minX, y: b.maxY), angle: 0, ctx: ctx)
            ctx.restoreGState()
        }
    }
}

/// インスペクタの見出し付きのまとまり
struct InspectorSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
