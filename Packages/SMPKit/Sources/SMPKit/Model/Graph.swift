import Foundation

/// 系列(データファイル 1 つぶんの描かせ方)。SMP の各値をそのまま持つ。
public struct Series: Hashable, Sendable, Identifiable {
    public enum Kind: Int, Sendable, CaseIterable {
        case normal = 0
        case polynomialLSQ = 1
        case spline = 2
        case function = 3
        case expLSQ = 4
        case logLSQ = 5
        case powerLSQ = 6
        case generalLSQ = 7
        case extension1 = 8
        case extension2 = 9

        public var isLSQ: Bool {
            switch self {
            case .polynomialLSQ, .expLSQ, .logLSQ, .powerLSQ, .generalLSQ: return true
            default: return false
            }
        }

        public var hasCurve: Bool { isLSQ || self == .spline || self == .function }
    }

    public enum ErrorBar: Int, Sendable, CaseIterable {
        case none = 0
        case plusPlus = 1   // (+,+) 次の列と次の次の列を足す
        case plusMinus = 2  // (+/-) 次の列を ± する
    }

    /// 連続データ(最小二乗・スプライン・任意関数)の X の刻み方
    public enum CurveSpacing: Int, Sendable, CaseIterable {
        case linear = 0
        case exponential = 1
        case reciprocal = 2
    }

    public var id = UUID()

    /// [DATA] の見出しにも使う名前(パスを含まない)
    public var name: String
    /// 元のデータファイルの場所(Windows のパスのことが多い)
    public var path: String

    // 1 行目
    public var kind: Kind = .normal
    public var kindRaw: Int = 0
    public var errorBarX: ErrorBar = .none
    public var errorBarY: ErrorBar = .none
    /// 0 始まりの列番号。-1 は Numbering(0,1,2,…)
    public var columnX: Int = 0
    public var columnY: Int = 1
    public var linesRead: Int = 0
    public var skipLines: Int = 0
    public var maxLines: Int = -1
    public var option: String = ""

    // 2 行目
    public var lineWidth: Int = 40
    public var lineColor: SMPColor = .black
    public var pitch: Int = 300
    public var tabAsSpace: Bool = false
    public var absoluteLineCount: Bool = false
    public var skipCommentCount: Bool = false
    public var considerOutOfRange: Bool = false

    // 3 行目
    public var lineType: LineType = .none
    /// プロットの種類(PlotType の値)。既定は 2(●)
    public var dotType: Int = PlotType.defaultCode
    /// プロットの大きさ(直径、0.01 mm)
    public var dotSize: Int = 300
    public var dotColor: SMPColor = .black

    // 4 行目
    public var useUAxis: Bool = false
    public var useRAxis: Bool = false
    public var readStep: Int = 1
    public var horizontalAverage: Int = 0
    public var verticalAverage: Int = 0
    public var brushStyle: Int = 0
    public var brushColor: SMPColor = .white
    public var brushHatch: Int = 5

    // 5〜7 行目
    public var transformX: Bool = false
    public var transformY: Bool = false
    public var converter: Int = 0
    public var expressionX: String = "x"
    public var expressionY: String = "y"

    // 8 行目(連続データ)
    public var curveSpacing: CurveSpacing = .linear
    public var curveDivisions: Int = 101
    public var lsqOrder: Int = 1
    public var passThroughPoint: Bool = false
    public var curveStart: Double = 0
    public var curveEnd: Double = 0
    public var passX: Double = 0
    public var passY: Double = 0
    public var barBase: Double = 0

    // 9 行目(曲線の線)
    public var curveLineType: LineType = .solid
    public var curveWidth: Int = 40
    public var curveColor: SMPColor = .black
    public var curvePitch: Int = 300
    public var curveVisible: Bool = true

    // 一般関数の最小二乗(種類 7)の式と初期値
    public var generalFunction: String = ""
    public var generalDerivatives: [String] = Array(repeating: "", count: 7)
    /// 初期値の行。古い形は "7 a b c d e f g 0"、新しい形は "9 許容誤差 a b c d e f g h i"
    public var generalParameterLine: String = ""
    /// 動かさずに初期値のまま使うパラメータ("a"〜"g"。SMP には書かない)
    public var generalFixed: Set<String> = []
    /// 許容誤差(%)。各パラメータの相対変化がこれより小さくなったら止める(0 なら止めない。新しい形の行から読むが、書くのは行のまま)
    public var generalTolerance: Double = 0.001

    /// 特殊な解析(ExtensionAnalysis)。nil 以外にすると種類は .extension1(8)になり、nil に戻すと .normal に戻る。
    public var extensionAnalysis: ExtensionAnalysis? {
        didSet {
            if extensionAnalysis != nil {
                kind = .extension1; kindRaw = Kind.extension1.rawValue
            } else if oldValue != nil, kind == .extension1 {
                kind = .normal; kindRaw = Kind.normal.rawValue
            }
        }
    }
    /// ガウス関数・ローレンツ関数の当てはめの条件
    public var peakFit = PeakFitSettings()

    /// 読み取ったが意味のわからなかった行・値(書き戻すときに残す)
    public var extraLines: [String] = []

    /// データの表示/非表示(SMP には残らない)
    public var visible: Bool = true

    public init(name: String, path: String = "") {
        self.name = name
        self.path = path.isEmpty ? name : path
    }

    public var displayName: String {
        if kind == .function, !expressionY.isEmpty { return expressionY }
        return name
    }

    /// 曲線(連続データ)を持つか。特殊処理はガウス関数・ローレンツ関数・なめらかにするが曲線を持つ
    public var hasCurve: Bool {
        if kind == .extension1 { return extensionAnalysis?.producesCurve ?? false }
        return kind.hasCurve
    }
}

public struct TickStyle: Hashable, Sendable {
    public var inside: Bool = true
    public var outside: Bool = false
    public var length: Int = 300
    public var width: Int = 40
    public var color: SMPColor = .black
    public var pitch: Int = 0
    public var style: Int = 1

    public init() {}
    public init(inside: Bool, outside: Bool, length: Int, width: Int, color: SMPColor, pitch: Int, style: Int) {
        self.inside = inside; self.outside = outside; self.length = length; self.width = width
        self.color = color; self.pitch = pitch; self.style = style
    }
}

/// 1 本の軸の設定([AXIS-n] の 6 行)。0:X 1:Y 2:U 3:R
public struct AxisSpec: Hashable, Sendable {
    // 1 行目
    public var from: Double = 0
    public var to: Double = 10
    public var increment: Double = 2
    public var limitRange: Bool = false
    public var limitStart: Int = 0
    public var limitEnd: Int = 10000
    public var crossPosition: Int = -1
    public var labelCount: Int = -1
    public var labelStart: Int = 0
    public var labelInterval: Int = 1
    public var plusSign: Bool = false
    public var zeroPadding: Bool = false
    public var zeroAsInteger: Bool = true
    public var integerDigits: Int = 5
    public var decimalDigits: Int = 5
    public var gettaOrder: Double = 1
    public var drawGetta: Bool = true

    // 2 行目
    public var division: Int = 2
    public var scaleType: ScaleType = .linear
    public var autoStep: Bool = true
    public var commonWithOpposite: Bool = true
    public var drawAxis: Bool = true
    public var drawLabels: Bool = true
    public var labelShiftX: Int = 0
    public var labelShiftY: Int = 0
    public var labelColor: SMPColor = .black
    /// 2 行目の 10 個目以降(使っていない値。読んだまま書く)
    public var line2Tail: [String] = ["300", "100", "0"]

    public var font: LogFont = .latinDefault()
    public var major = TickStyle(inside: true, outside: false, length: 300, width: 40, color: .black, pitch: 0, style: 1)
    public var minor = TickStyle(inside: true, outside: false, length: 150, width: 40, color: .black, pitch: 0, style: 1)

    public init() {}

    public static func defaultAxis(index: Int) -> AxisSpec {
        var a = AxisSpec()
        switch index {
        case 0: a.line2Tail = ["300", "100", "0"]
        case 1: a.line2Tail = ["1200", "100", "0"]; a.labelShiftX = -200
        case 2: a.line2Tail = ["900", "100", "0"]; a.drawLabels = false
        default: a.line2Tail = ["-14578", "100", "0"]; a.drawLabels = false
        }
        return a
    }
}

/// [LEGEND] の文字列(種類 4〜8)
public struct TextObject: Hashable, Sendable {
    public enum Kind: Int, Sendable, CaseIterable {
        case xTitle = 4, yTitle = 5, uTitle = 6, rTitle = 7, other = 8

        public var title: String {
            switch self {
            case .xTitle: return "X軸タイトル"
            case .yTitle: return "Y軸タイトル"
            case .uTitle: return "U軸タイトル"
            case .rTitle: return "R軸タイトル"
            case .other: return "その他の文字"
            }
        }
    }

    public var kind: Kind = .other
    /// グラフの枠の左上からの位置(0.01 mm)。文字の開始位置の左下。
    public var x: Int = 0
    public var y: Int = 0
    public var color: SMPColor = .black
    /// 1:透過 2:背景を白で塗る
    public var backgroundMode: Int = 1
    /// 位置を用紙の左上からにするか
    public var absolutePosition: Bool = false
    public var positionTail: [String] = ["0"]
    /// 書式の制御コードを含んだ文字列。改行は \n の 2 文字で持つ。
    public var text: String = ""
    public var latinFont: LogFont = .latinDefault()
    public var japaneseFont: LogFont = .japaneseDefault()
    public var symbolFont: LogFont = .symbolDefault()

    public init() {}

    public var angle: Double {
        get { latinFont.angle }
        set {
            latinFont.angle = newValue
            japaneseFont.angle = newValue
        }
    }
}

/// [LEGEND] の矢印・エラーバー・枠(種類 0〜3)
public struct ShapeObject: Hashable, Sendable {
    public enum Kind: Int, Sendable, CaseIterable {
        case arrow = 0, arrow2 = 1, errorBar = 2, box = 3
    }

    public var objectType: Int = 0
    public var x1: Double = 0
    public var y1: Double = 0
    public var x2: Double = 10
    public var y2: Double = 10
    /// 0:mm 1:X 値 2:U 値
    public var xReference: Int = 0
    /// 0:mm 1:Y 値 2:R 値
    public var yReference: Int = 0
    public var width: Int = 40
    /// 矢じりの長さ・影の長さ(0.01 mm)
    public var length: Int = 500
    public var color: SMPColor = .black
    public var shapeType: Int = 0
    public var pitch: Int = 300
    public var style: Int = 1
    public var shadowColor: SMPColor = .white
    public var size: Int = 0
    public var aspect: Int = 0
    /// 矢じりの付け方 0:なし 1:終点 2:始点 3:両端
    public var headMode: Int = 1
    /// 矢じりの開き(tan × 100)
    public var headOpen: Int = 30
    /// 矢じりの閉じ(%)
    public var headClose: Int = 100
    public var tail: [String] = ["0"]

    public init() {}

    public var kind: Kind { Kind(rawValue: objectType) ?? .arrow }
    public var isBox: Bool { objectType == 3 }
}

/// [LEGEND] のドット(種類 9)
public struct DotObject: Hashable, Sendable {
    public var x: Int = 0
    public var y: Int = 0
    public var dotType: Int = 1
    public var width: Int = 40
    public var length: Int = 0
    public var style: Int = 0
    public var size: Int = 300
    public var color: SMPColor = .black
    public var lineColor: SMPColor = .black
    public var pitch: Int = 300
    public var brushStyle: Int = 0
    public var brushColor: SMPColor = .white
    public var brushHatch: Int = 5
    public var tail: [String] = ["0"]
    public var pointCount: Int = 1
    public var points: [String] = []
    public var reserved: String = "0 0 0.0 0.0"

    public init() {}
}

/// [LEGEND] の図(種類 10)
public struct PictureObject: Hashable, Sendable {
    /// 図のファイル名(「パスを保存」が切ってあれば相対パス)
    public var path: String
    /// 4 つの整数の行(意味は不明。新しく貼るときは newInfo を使う)
    public var info: [Int]
    /// 矢印・枠と同じ 19 個の値の行。x1・y1 が左上、x2・y2 が右下(枠と同じくグラフの枠の左上からの mm)
    public var shape: ShapeObject

    public init(path: String, info: [Int] = [0, 0, 0, 0], shape: ShapeObject = ShapeObject()) {
        self.path = path
        self.info = info
        var s = shape
        s.objectType = PictureObject.objectType
        self.shape = s
    }

    public static let objectType = 10

    /// 新しく貼る図の 4 つの整数(推定: 0 0 幅 高さ[ピクセル])
    public static func newInfo(pixelWidth: Int, pixelHeight: Int) -> [Int] { [0, 0, pixelWidth, pixelHeight] }
}

public enum GraphObject: Hashable, Sendable {
    case text(TextObject)
    case shape(ShapeObject)
    case dot(DotObject)
    /// 図(種類 10)
    case picture(PictureObject)
    /// 読めても意味のわからない種類のもの。行のまま残す。
    case raw(type: Int, lines: [String])
}

public struct ObjectItem: Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var object: GraphObject
    public init(_ object: GraphObject) { self.object = object }
}

public struct PageSetup: Hashable, Sendable {
    public var saveData: Bool = true
    public var savePath: Bool = true
    public var paperWidth: Int = 210
    public var paperHeight: Int = 297
    public var landscape: Bool = false
    public var tail: [Int] = [100, 2]

    public init() {}

    /// 用紙の大きさ(mm)。横置きなら幅と高さを入れ替える。
    public var paperSizeMM: (width: Double, height: Double) {
        let w = Double(max(paperWidth, 50)), h = Double(max(paperHeight, 50))
        return landscape ? (max(w, h), min(w, h)) : (w, h)
    }
}

/// 1 つのグラフ(SMP の 1 枚)
public struct Graph: Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var name: String = "Untitled.SMP"
    public var versionLine: String = " Sma4Win ver. 1.8  SMP file"
    public var comment: String = ""
    public var page = PageSetup()
    public var series: [Series] = []

    // [GRAPH]
    public var left: Int = 4000
    public var top: Int = 2000
    public var width: Int = 14000
    public var height: Int = 10000
    public var zoom: Int = 100
    public var frameType: FrameType = .box
    public var zeroCommon: Bool = false
    public var graphLine2Tail: [String] = ["0", "1", "0"]
    public var frameWidth: Int = 40
    public var frameColor: SMPColor = .black
    public var framePitch: Int = 0
    public var background: SMPColor = .white

    public var axes: [AxisSpec] = (0..<4).map { AxisSpec.defaultAxis(index: $0) }
    public var objects: [ObjectItem] = []

    // [OTHERS]
    public var constants: [Double] = Array(repeating: 0, count: 9)
    public var othersFont: LogFont = .symbolDefault()

    // [MASKS]
    /// 除く範囲(最大 maxMasks 個)
    public var masks: [DataMask] = []
    /// マスクの行の後ろの行(ふつうは "0" と "0"。読んだまま書く)
    public var maskTrailingLines: [String] = ["0", "0"]
    public static let maxMasks = 20

    public init() {}

    public var frameRect: CGRect {
        CGRect(x: Double(left), y: Double(top), width: Double(width), height: Double(height))
    }

    public var zoomFactor: Double { zoom > 0 ? Double(zoom) / 100.0 : 1 }

    public func axis(_ index: Int) -> AxisSpec { axes[index] }

    /// U 軸・R 軸を X・Y と別に持つか(枠が □ のときだけ別にできる)
    public var uIndependent: Bool { !axes[0].commonWithOpposite && frameType == .box }
    public var rIndependent: Bool { !axes[1].commonWithOpposite && frameType == .box }

    /// 系列が使う横軸・縦軸の番号
    public func horizontalAxisIndex(for s: Series) -> Int { s.useUAxis && uIndependent ? 2 : 0 }
    public func verticalAxisIndex(for s: Series) -> Int { s.useRAxis && rIndependent ? 3 : 1 }

    /// 実際に描くときの U・R の軸(共通なら X・Y の値を使う)
    public func effectiveAxis(_ index: Int) -> AxisSpec {
        switch index {
        case 2 where !uIndependent:
            var a = axes[0]
            a.drawLabels = axes[2].drawLabels
            a.drawAxis = axes[2].drawAxis
            return a
        case 3 where !rIndependent:
            var a = axes[1]
            a.drawLabels = axes[3].drawLabels
            a.drawAxis = axes[3].drawAxis
            return a
        default:
            return axes[index]
        }
    }
}

/// 埋め込み・読み込み済みのデータファイルの中身
public struct DataFile: Hashable, Sendable {
    public var name: String
    /// [DATA] の見出しにある日時(なければ空)
    public var timestamp: String
    /// ファイルの行(改行を含まない)
    public var lines: [String]

    public init(name: String, timestamp: String = "", lines: [String]) {
        self.name = name; self.timestamp = timestamp; self.lines = lines
    }
}

/// 1 つの SMP ファイル(複数のグラフを含むことがある)
public struct SMPProject: Hashable, Sendable {
    public var graphs: [Graph] = []
    /// データファイル名(大文字小文字を区別しない)→ 中身
    public var dataFiles: [String: DataFile] = [:]
    /// 複数グラフを 1 ファイルにした SMA 形式で読んだか
    public var multiGraphHeaderTail: [String] = ["0", "0", "0", "0", "100"]

    public init() {}

    public static func key(_ name: String) -> String { name.uppercased() }

    public func dataFile(named name: String) -> DataFile? { dataFiles[SMPProject.key(name)] }

    public mutating func setDataFile(_ file: DataFile) { dataFiles[SMPProject.key(file.name)] = file }
}
