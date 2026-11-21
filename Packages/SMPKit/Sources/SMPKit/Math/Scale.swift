import Foundation

/// 軸の値と位置(0〜1)の変換と目盛りの計算
public struct AxisScale: Sendable {
    public let spec: AxisSpec

    public init(_ spec: AxisSpec) { self.spec = spec }

    var type: ScaleType { spec.scaleType }

    /// 値 → 0(From)〜1(To)。描けない値は nil
    public func fraction(_ v: Double) -> Double? {
        guard v.isFinite else { return nil }
        switch type {
        case .linear:
            let d = spec.to - spec.from
            return d == 0 ? nil : (v - spec.from) / d
        case .logNormal, .logExponent:
            guard v > 0, spec.from > 0, spec.to > 0 else { return nil }
            let a = Foundation.log10(spec.from), b = Foundation.log10(spec.to)
            return b == a ? nil : (Foundation.log10(v) - a) / (b - a)
        case .inverseNormal, .inverseReciprocal:
            // From・To は逆数の値で指定する(0.1〜1000 のデータなら 10〜0.001)
            guard v != 0 else { return nil }
            let u = 1 / v
            let d = spec.to - spec.from
            return d == 0 ? nil : (u - spec.from) / d
        }
    }

    /// 0〜1 → 値
    public func value(atFraction f: Double) -> Double {
        switch type {
        case .linear:
            return spec.from + f * (spec.to - spec.from)
        case .logNormal, .logExponent:
            let a = Foundation.log10(Swift.max(spec.from, 1e-300)), b = Foundation.log10(Swift.max(spec.to, 1e-300))
            return Foundation.pow(10, a + f * (b - a))
        case .inverseNormal, .inverseReciprocal:
            let u = spec.from + f * (spec.to - spec.from)
            return u == 0 ? .infinity : 1 / u
        }
    }

    public struct Tick: Sendable, Equatable {
        public var value: Double
        public var fraction: Double
        public var isMajor: Bool
        /// 目盛り数字(書式の制御コードで書く。指数表記なら 10^n@)
        public var label: String?
    }

    /// 主目盛と副目盛
    public func ticks() -> [Tick] {
        switch type {
        case .linear: return linearTicks(lo: spec.from, hi: spec.to, step: spec.increment, divisions: spec.division) { v in v }
        case .inverseReciprocal:
            // 逆数の値を Linear と同じように振る
            return linearTicks(lo: spec.from, hi: spec.to, step: spec.increment, divisions: spec.division) { u in u }
                .map { t in
                    var t = t
                    t.value = t.value == 0 ? .infinity : 1 / t.value
                    return t
                }
        case .inverseNormal: return inverseNormalTicks()
        case .logNormal, .logExponent: return logTicks()
        }
    }

    func linearTicks(lo: Double, hi: Double, step rawStep: Double, divisions: Int, display: (Double) -> Double) -> [Tick] {
        var out: [Tick] = []
        let a = Swift.min(lo, hi), b = Swift.max(lo, hi)
        let span = b - a
        guard span > 0, rawStep.isFinite else { return out }
        var step = Swift.abs(rawStep)
        if step == 0 || span / step > 2000 { step = AxisScale.niceStep(span / 5) }
        let eps = step * 1e-9
        let first = (a / step - 1e-9).rounded(.up)
        let last = (b / step + 1e-9).rounded(.down)
        let div = Swift.max(divisions, 1)
        let minorStep = step / Double(div)
        var labelIndex = 0
        var k = first - 1
        while k <= last + 1 {
            let major = k * step
            if major >= a - eps && major <= b + eps {
                let v = Swift.abs(major) < eps ? 0 : major
                let shown = display(v)
                let label = labelFor(index: labelIndex) ? format(shown, step: step) : nil
                labelIndex += 1
                out.append(Tick(value: v, fraction: (v - lo) / (hi - lo), isMajor: true, label: label))
            }
            if div > 1 {
                for j in 1..<div {
                    let m = major + Double(j) * minorStep
                    if m > a + eps && m < b - eps {
                        out.append(Tick(value: m, fraction: (m - lo) / (hi - lo), isMajor: false, label: nil))
                    }
                }
            }
            k += 1
        }
        return out
    }

    /// 目盛始め・個数・間隔に従って数字を振るか
    func labelFor(index: Int) -> Bool {
        let start = Swift.max(spec.labelStart, 0)
        let interval = Swift.max(spec.labelInterval, 1)
        guard index >= start else { return false }
        let k = index - start
        guard k % interval == 0 else { return false }
        if spec.labelCount >= 0 && k / interval >= spec.labelCount { return false }
        return true
    }

    func inverseNormalTicks() -> [Tick] {
        // 表示は元の値。元の値の 1・2・5 の並びで目盛りを探す
        var out: [Tick] = []
        let u0 = spec.from, u1 = spec.to
        guard u0 != u1 else { return out }
        let vs = [u0, u1].filter { $0 != 0 }.map { 1 / Swift.abs($0) }
        guard let vmin = vs.min(), let vmax = vs.max(), vmin > 0, vmax.isFinite else { return out }
        let e0 = Int(Foundation.floor(Foundation.log10(vmin))) - 1, e1 = Int(Foundation.ceil(Foundation.log10(vmax))) + 1
        var labelIndex = 0
        for e in e0...e1 {
            for m in [1.0, 2.0, 5.0] {
                let v = m * Foundation.pow(10, Double(e))
                guard let f = fraction(v), f >= -1e-9, f <= 1 + 1e-9 else { continue }
                let label = labelFor(index: labelIndex) ? format(v, step: v / 10) : nil
                labelIndex += 1
                out.append(Tick(value: v, fraction: f, isMajor: true, label: label))
            }
        }
        return out
    }

    func logTicks() -> [Tick] {
        var out: [Tick] = []
        guard spec.from > 0, spec.to > 0, spec.from != spec.to else { return out }
        let lo = Swift.min(spec.from, spec.to), hi = Swift.max(spec.from, spec.to)
        let e0 = Int(Foundation.floor(Foundation.log10(lo))) - 1
        let e1 = Int(Foundation.ceil(Foundation.log10(hi))) + 1
        let inc = Int(spec.increment.rounded())
        let mantissas: [Double]
        switch inc {
        case 1: mantissas = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        case 2: mantissas = [1, 2, 4]
        case 3: mantissas = [1, 3]
        case 4: mantissas = [1, 2, 5]
        case 5: mantissas = [1, 5]
        default: mantissas = [1]
        }
        let minorOn = spec.division >= 2
        var labelIndex = 0
        for e in e0...e1 {
            let p = Foundation.pow(10, Double(e))
            for m in 1...9 {
                let v = Double(m) * p
                guard v >= lo * (1 - 1e-9), v <= hi * (1 + 1e-9), let f = fraction(v) else { continue }
                let isMajor = mantissas.contains(Double(m))
                if isMajor {
                    var label: String?
                    if labelFor(index: labelIndex) {
                        if type == .logExponent {
                            label = m == 1 ? "10^\(e)@" : nil
                        } else {
                            label = formatLog(v, exponent: e)
                        }
                    }
                    labelIndex += 1
                    out.append(Tick(value: v, fraction: f, isMajor: true, label: label))
                } else if minorOn {
                    out.append(Tick(value: v, fraction: f, isMajor: false, label: nil))
                }
            }
        }
        return out
    }

    /// 目盛り数字の書き方(Linear)
    public func format(_ raw: Double, step: Double) -> String {
        let getta = spec.gettaOrder != 0 && spec.gettaOrder != 1 ? spec.gettaOrder : 1
        let v = raw / getta
        let s = Swift.abs(step / getta)
        var decimals = 0
        if s > 0 && s.isFinite {
            var t = s
            while decimals < 10 {
                let r = (t * 1).rounded()
                if Swift.abs(t - r) < 1e-6 * Swift.max(1, Swift.abs(t)) { break }
                t *= 10
                decimals += 1
            }
        }
        if spec.decimalDigits >= 0 && spec.decimalDigits < 5 { decimals = spec.decimalDigits }
        var text: String
        if Swift.abs(v) < 1e-12 * Swift.max(1, s) {
            text = spec.zeroAsInteger ? "0" : String(format: "%.\(decimals)f", 0.0)
        } else if Swift.abs(v) >= 1e15 {
            text = String(format: "%g", v)
        } else {
            text = String(format: "%.\(decimals)f", v)
        }
        if text.hasPrefix("-"), Double(text) == 0 { text.removeFirst() }
        if spec.plusSign, v > 0 { text = "+" + text }
        return text
    }

    func formatLog(_ v: Double, exponent e: Int) -> String {
        if e >= 0 { return String(format: "%.0f", v) }
        return String(format: "%.\(-e)f", v)
    }

    /// 1・2・5 の並びのきりのよい刻み
    public static func niceStep(_ raw: Double) -> Double {
        guard raw > 0, raw.isFinite else { return 1 }
        let e = Foundation.floor(Foundation.log10(raw))
        let base = Foundation.pow(10, e)
        let m = raw / base
        let nice: Double = m <= 1 ? 1 : (m <= 2 ? 2 : (m <= 5 ? 5 : 10))
        return nice * base
    }

    /// 範囲合わせ: データの範囲から始め・終わり・目盛りの間隔・分割数を決める
    public static func autoScaled(_ spec: AxisSpec, minValue: Double, maxValue: Double) -> AxisSpec {
        var a = spec
        guard minValue.isFinite, maxValue.isFinite else { return a }
        var lo = Swift.min(minValue, maxValue), hi = Swift.max(minValue, maxValue)
        switch spec.scaleType {
        case .linear:
            if lo == hi {
                let d = lo == 0 ? 1 : Swift.abs(lo) * 0.1
                lo -= d; hi += d
            }
            let step = niceStep((hi - lo) / 5)
            a.from = Foundation.floor(lo / step + 1e-9) * step
            a.to = Foundation.ceil(hi / step - 1e-9) * step
            if a.from == a.to { a.to = a.from + step }
            a.increment = step
            a.division = 2
        case .logNormal, .logExponent:
            let positives = [lo, hi].filter { $0 > 0 }
            let l = positives.min() ?? 1, h = positives.max() ?? 10
            a.from = Foundation.pow(10, Foundation.floor(Foundation.log10(l) + 1e-9))
            a.to = Foundation.pow(10, Foundation.ceil(Foundation.log10(h) - 1e-9))
            if a.from >= a.to { a.to = a.from * 10 }
            a.increment = 10
            a.division = 10
        case .inverseNormal, .inverseReciprocal:
            let us = [lo, hi].filter { $0 != 0 }.map { 1 / $0 }
            guard let u0 = us.min(), let u1 = us.max() else { return a }
            let step = niceStep(Swift.max(u1 - u0, Swift.abs(u1) * 0.1) / 5)
            a.from = Foundation.ceil(u1 / step) * step
            a.to = Foundation.floor(u0 / step) * step
            if a.from == a.to { a.to = a.from - step }
            a.increment = step
            a.division = 2
        }
        return a
    }
}
