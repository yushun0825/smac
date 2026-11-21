import Foundation

/// プロットの種類(SMP の「ドット種」の値)。
///
/// 既定の並びでは 1=○ 2=● 3=△ 4=▲ 5=□ 6=■ 7=▽ 8=▼ 9=◇ 10=◆ 11=+ 12=×。
/// 中を塗る色は `fillsWithDotColor` の値ならドットの色、それ以外は「中塗色」(lbColor)。
public enum PlotType {
    /// データの「プロットの種類」に並べる値(この順)
    public static let seriesCodes: [Int] = Array(0...28) + [33, 34] + Array(38...52)
    /// ドット(凡例のオブジェクト)に並べる値(この順)
    public static let dotObjectCodes: [Int] = Array(0...32) + Array(38...52)
    /// 新しいデータの既定(●)
    public static let defaultCode = 2

    static let titles: [Int: String] = [
        0: "なし", 13: "縦棒", 26: "横棒", 27: "矩形", 28: "対角線", 33: "縦階段", 34: "横階段",
    ]

    /// 印の代わりに文字で見せる値の名前(それ以外は nil)
    public static func title(_ code: Int) -> String? { titles[code] }

    /// 棒・階段など、データでは点ごとの印でなく形で描く値
    public static func isBarOrStep(_ code: Int) -> Bool {
        code == 13 || code == 26 || code == 27 || code == 28 || code == 33 || code == 34
    }

    /// 「ドットタイプを自動更新」の次の値(2, 3, …, 12, 14, …, 22, 1, 2, …)
    public static func next(after code: Int) -> Int {
        var n = code + 1
        if n == 13 { n = 14 }
        if n >= 23 || n < 1 { n = 1 }
        return n
    }

    static let dotColorFilled: Set<Int> = [2, 4, 6, 8, 10, 13, 19, 20, 21, 22, 23, 26, 27, 33, 34]

    /// 中をドットの色で塗る値か(それ以外は中塗色で塗る)
    public static func fillsWithDotColor(_ code: Int) -> Bool { dotColorFilled.contains(code) }

    /// 何かを描く値か(0, 29〜32, 35〜37 などは何も描かない)
    public static func drawsMark(_ code: Int) -> Bool {
        (1...28).contains(code) || code == 33 || code == 34 || (38...52).contains(code)
    }
}

/// 「ドットのブラシ」の選択肢と LOGBRUSH(lbStyle・lbHatch)の対応
public enum DotBrush {
    public static let titles: [String] = ["中塗", "中空", "中白", "ﾊｯﾁ1", "ﾊｯﾁ2", "ﾊｯﾁ3", "ﾊｯﾁ4", "ﾊｯﾁ5", "ﾊｯﾁ6"]

    /// (lbStyle, lbHatch) → 選択肢の番号
    public static func index(style: Int, hatch: Int) -> Int {
        switch style {
        case 1: return 1
        case 2: return Swift.min(Swift.max(hatch, 0), 6) + 2
        default: return 0
        }
    }

    /// 選択肢の番号 → (lbStyle, lbHatch)
    public static func values(index: Int) -> (style: Int, hatch: Int) {
        switch index {
        case 1: return (1, 0)
        case 2: return (2, 0)
        case 3...8: return (2, index - 2)
        default: return (0, 0)
        }
    }
}

/// 除く範囲([MASKS] の 1 行)。系列 1 つの、変換後の値がこの範囲に入る点を欠損と同じに扱う。
public struct DataMask: Hashable, Sendable {
    /// 0 始まりの系列の番号
    public var seriesIndex: Int
    public var xMin: Double
    public var xMax: Double
    public var yMin: Double
    public var yMax: Double

    public init(seriesIndex: Int, xMin: Double, xMax: Double, yMin: Double, yMax: Double) {
        self.seriesIndex = seriesIndex
        self.xMin = xMin; self.xMax = xMax; self.yMin = yMin; self.yMax = yMax
    }

    /// 点が範囲に入るか(境界を含む。最小と最大が逆でもよい)
    public func contains(x: Double, y: Double) -> Bool {
        let x0 = Swift.min(xMin, xMax), x1 = Swift.max(xMin, xMax)
        let y0 = Swift.min(yMin, yMax), y1 = Swift.max(yMin, yMax)
        return x >= x0 && x <= x1 && y >= y0 && y <= y1
    }
}
