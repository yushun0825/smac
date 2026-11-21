import Foundation

/// データファイルの 1 行を読んだ結果
public enum DataLine: Sendable, Equatable {
    /// # か % で始まる行
    case comment
    /// 数値が 1 つもない行(見出しなど)
    case invalid
    /// 各列の値。欠損(=)と数値でない欄は NaN
    case values([Double])
}

public enum DataParser {
    /// データファイルの 1 行を数に分ける。
    /// コンマは必ず区切り(",," は欠損)、空白は続いても 1 つの区切り、TAB は設定でどちらかにする。
    /// 欄が "=" なら欠損(エラー値)、"|" なら読み飛ばして列を詰める。
    public static func parse(line raw: String, tabAsSpace: Bool) -> DataLine {
        let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \u{3000}\u{FEFF}"))
        if line.isEmpty { return .invalid }
        if let f = line.first, f == "#" || f == "%" { return .comment }

        var cells: [Substring] = []
        var current = Substring()
        var start = line.startIndex
        var inToken = false
        var lastWasHardSeparator = true
        var idx = line.startIndex
        func flush(_ end: String.Index) {
            current = line[start..<end]
            cells.append(current)
        }
        while idx < line.endIndex {
            let ch = line[idx]
            let hard = ch == "," || (ch == "\t" && !tabAsSpace) || ch == ";"
            let soft = ch == " " || (ch == "\t" && tabAsSpace) || ch == "\u{3000}"
            if hard {
                if inToken { flush(idx); inToken = false }
                else if lastWasHardSeparator { cells.append("") }
                lastWasHardSeparator = true
            } else if soft {
                if inToken { flush(idx); inToken = false; lastWasHardSeparator = false }
            } else {
                if !inToken { start = idx; inToken = true }
                lastWasHardSeparator = false
            }
            idx = line.index(after: idx)
        }
        if inToken { flush(line.endIndex) }
        else if lastWasHardSeparator, line.last == "," { cells.append("") }

        var values: [Double] = []
        values.reserveCapacity(cells.count)
        var anyNumber = false
        for c in cells {
            let t = c.trimmingCharacters(in: .whitespaces)
            if t == "|" { continue }
            if t.isEmpty || t == "=" { values.append(.nan); continue }
            if let v = number(t) {
                values.append(v); anyNumber = true
            } else {
                values.append(.nan)
            }
        }
        return anyNumber ? .values(values) : .invalid
    }

    public static func number(_ s: String) -> Double? {
        if let v = Double(s) { return v.isFinite ? v : nil }
        // Fortran の 1.0D+03 や、全角の数字にも対応
        var t = s.replacingOccurrences(of: "D", with: "E").replacingOccurrences(of: "d", with: "e")
        t = t.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? t
        if let v = Double(t), v.isFinite { return v }
        return nil
    }

    /// 系列の設定(先頭スキップ・読込行数・ステップ・コメント行の数え方)に従って行を選ぶ
    public static func rows(for series: Series, lines: [String]) -> [[Double]] {
        var rows: [[Double]] = []
        let skip = max(series.skipLines, 0)
        let limit = series.maxLines
        let step = max(series.readStep, 1)
        var counted = 0
        var stepIndex = 0
        for (i, raw) in lines.enumerated() {
            if i < skip { continue }
            let parsed = parse(line: raw, tabAsSpace: series.tabAsSpace)
            var isData = false
            var values: [Double] = []
            switch parsed {
            case .comment, .invalid:
                if series.skipCommentCount { continue }
            case .values(let v):
                isData = true
                values = v
            }
            // 読込み行数の判定(絶対指定ならスキップ行も含めて数える)
            let position = series.absoluteLineCount ? i + 1 : counted + 1
            if limit >= 0, position > limit { break }
            counted += 1
            if isData {
                if stepIndex % step == 0 { rows.append(values) }
                stepIndex += 1
            }
        }
        return rows
    }
}
