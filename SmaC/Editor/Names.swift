import Foundation
import SMPKit

// SmaC の画面に出す名前(SMP の中の名前とは別に、ふつうの日本語で書く)

extension ExtensionAnalysis {
    var displayTitle: String {
        switch self {
        case .gaussian: return "ガウス関数で当てはめる"
        case .lorentzian: return "ローレンツ関数で当てはめる"
        case .getMax: return "最大値を探す"
        case .getMin: return "最小値を探す"
        case .peakDetect: return "ピークを探す"
        case .smoothing: return "なめらかにする"
        }
    }

    /// 短い名前(サイドバーなど)
    var shortTitle: String {
        switch self {
        case .gaussian: return "ガウス関数"
        case .lorentzian: return "ローレンツ関数"
        case .getMax: return "最大値"
        case .getMin: return "最小値"
        case .peakDetect: return "ピーク"
        case .smoothing: return "なめらかに"
        }
    }
}

extension Series.Kind {
    var displayTitle: String {
        switch self {
        case .normal: return "データ"
        case .polynomialLSQ: return "多項式"
        case .spline: return "スプライン"
        case .function: return "関数"
        case .expLSQ: return "指数関数"
        case .logLSQ: return "対数関数"
        case .powerLSQ: return "べき関数"
        case .generalLSQ: return "一般の関数"
        case .extension1, .extension2: return "そのほかの解析"
        }
    }
}

extension Series {
    /// 解析の名前(なければ nil)
    var analysisTitle: String? {
        if let a = extensionAnalysis { return a.shortTitle }
        switch kind {
        case .normal: return nil
        case .function: return "関数"
        case .spline: return "スプライン"
        default: return kind.displayTitle + "で当てはめ"
        }
    }
}

extension Spline.Mode {
    var displayTitle: String {
        switch self {
        case .cubic: return "3 次スプライン"
        case .parametric: return "パラメトリック"
        case .closedParametric: return "パラメトリック(閉じた曲線)"
        }
    }
}

extension TextObject.Kind {
    var displayTitle: String {
        switch self {
        case .xTitle: return "X 軸の題"
        case .yTitle: return "Y 軸の題"
        case .uTitle: return "上の軸の題"
        case .rTitle: return "右の軸の題"
        case .other: return "文字"
        }
    }
}

extension GraphObject {
    /// サイドバーなどに出す名前
    var displayTitle: String {
        switch self {
        case .text(let t):
            let plain = RichTextParser.plainText(t.text).replacingOccurrences(of: "\\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            if plain.isEmpty { return t.kind.displayTitle }
            return plain.count > 28 ? String(plain.prefix(28)) + "…" : plain
        case .shape(let s):
            if s.isBox { return "枠" }
            switch s.objectType {
            case 2: return "エラーバー"
            default: return s.headMode == 0 ? "線" : "矢印"
            }
        case .dot: return "点"
        case .picture(let p):
            let name = (p.path.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
            return name.isEmpty ? "図" : name
        case .raw: return "そのほかの図形"
        }
    }

    /// SF Symbols の名前
    var symbolName: String {
        switch self {
        case .text: return "textformat"
        case .shape(let s): return s.isBox ? "rectangle" : (s.headMode == 0 ? "line.diagonal" : "arrow.up.right")
        case .dot: return "smallcircle.filled.circle"
        case .picture: return "photo"
        case .raw: return "questionmark.square.dashed"
        }
    }
}

/// 数の見せ方
enum NumberText {
    /// 有効数字 6 桁(%g と同じ考え方)
    static func g(_ v: Double) -> String {
        guard v.isFinite else { return v.isNaN ? "—" : (v > 0 ? "∞" : "-∞") }
        return String(format: "%.6g", v)
    }

    /// 書き出す値(指数表記・符号つき)
    static func export(_ v: Double) -> String {
        v.isFinite ? String(format: "%+.9e", v) : "NaN"
    }
}
