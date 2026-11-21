import Foundation

/// 特殊な解析(ピークの当てはめ・最大値と最小値・ピーク検出・平滑化)。rawValue は SMP に書く名前。メニューはこの順。
public enum ExtensionAnalysis: String, CaseIterable, Sendable {
    case gaussian = "GAUSSF2"
    case lorentzian = "LORENF2"
    case getMax = "GetMax"
    case getMin = "GetMin"
    case peakDetect = "PeakDct"
    case smoothing = "SMOOTH"

    /// 当てはめの条件(ピークの数・初期値)を決めてから計算するか
    public var usesFittingDialog: Bool { self == .gaussian || self == .lorentzian }

    /// 曲線を描くか(ガウス関数・ローレンツ関数・なめらかにする)
    public var producesCurve: Bool { usesFittingDialog || self == .smoothing }
}

/// ガウス関数・ローレンツ関数の当てはめの条件。各配列は maxPeaks 個。
/// vary〜 が true のパラメータを動かし、false のものは初期値のまま固定する。
public struct PeakFitSettings: Hashable, Sendable {
    public static let maxPeaks = 6

    /// ピークの数(1〜6)
    public var count: Int = 1
    /// 強度
    public var intensity: [Double] = Array(repeating: 1, count: PeakFitSettings.maxPeaks)
    /// ピーク位置
    public var position: [Double] = Array(repeating: 0, count: PeakFitSettings.maxPeaks)
    /// 半値幅(FWHM)
    public var width: [Double] = Array(repeating: 1, count: PeakFitSettings.maxPeaks)
    public var varyIntensity: [Bool] = Array(repeating: true, count: PeakFitSettings.maxPeaks)
    public var varyPosition: [Bool] = Array(repeating: true, count: PeakFitSettings.maxPeaks)
    public var varyWidth: [Bool] = Array(repeating: true, count: PeakFitSettings.maxPeaks)
    public var offset: Double = 0
    public var varyOffset: Bool = true
    /// 精度(二乗和の相対変化がこれより小さくなったら止める)
    public var precision: Double = 1e-6

    public init() {}

    /// 配列を 6 個に揃え、count を 1〜6 にしたもの
    public var normalized: PeakFitSettings {
        var s = self
        let n = PeakFitSettings.maxPeaks
        func pad<T>(_ a: [T], _ d: T) -> [T] { Array((a + Array(repeating: d, count: Swift.max(n - a.count, 0))).prefix(n)) }
        s.count = Swift.min(Swift.max(count, 1), n)
        s.intensity = pad(intensity, 1)
        s.position = pad(position, 0)
        s.width = pad(width, 1)
        s.varyIntensity = pad(varyIntensity, true)
        s.varyPosition = pad(varyPosition, true)
        s.varyWidth = pad(varyWidth, true)
        if !(precision.isFinite && precision > 0) { s.precision = 1e-6 }
        return s
    }

    /// データから初期値を作る(目立つピークから count 個。足りなければ x の範囲に等間隔に置く)
    public static func initialGuess(x: [Double], y: [Double], count: Int) -> PeakFitSettings {
        var s = PeakFitSettings()
        let n = Swift.min(Swift.max(count, 1), maxPeaks)
        s.count = n
        let pts = zip(x, y).filter { $0.0.isFinite && $0.1.isFinite }.sorted { $0.0 < $1.0 }
        guard let first = pts.first, let last = pts.last else { return s }
        let xs = pts.map(\.0), ys = pts.map(\.1)
        let lo = ys.min() ?? 0, hi = ys.max() ?? 1
        let height = hi > lo ? hi - lo : Swift.max(Swift.abs(hi), 1)
        let span = last.0 - first.0
        let fallbackWidth = span > 0 ? span / Double(4 * n) : 1
        s.offset = lo

        var chosen = PeakFinder.maxima(ys).sorted { $0.prominence > $1.prominence }.prefix(n).map(\.index)
        if chosen.isEmpty, let iMax = ys.indices.max(by: { ys[$0] < ys[$1] }) { chosen = [iMax] }
        var peaks: [(a: Double, p: Double, w: Double)] = chosen.map { i in
            (ys[i] - lo, xs[i], PeakFinder.fullWidthAtHalfMaximum(xs, ys, peak: i, base: lo) ?? fallbackWidth)
        }
        let missing = n - peaks.count
        for j in 0..<Swift.max(missing, 0) {
            let px = first.0 + span * Double(j + 1) / Double(missing + 1)
            let nearest = xs.indices.min(by: { Swift.abs(xs[$0] - px) < Swift.abs(xs[$1] - px) }) ?? 0
            peaks.append((Swift.max(ys[nearest] - lo, height * 0.1), px, fallbackWidth))
        }
        peaks.sort { $0.p < $1.p }
        for (i, pk) in peaks.enumerated() {
            s.intensity[i] = pk.a > 0 && pk.a.isFinite ? pk.a : height
            s.position[i] = pk.p
            s.width[i] = pk.w > 0 && pk.w.isFinite ? pk.w : fallbackWidth
        }
        return s
    }
}

public enum ExtensionAnalyzer {
    /// 特殊処理を 1 つ行う。x・y は変換と、除く範囲を除いたあとの値(欠損は NaN のままでよい)。
    /// samples は Gaussian・Lorentzian の曲線を描く x(空ならデータの範囲を 200 等分)。
    /// なめらかにした曲線はデータの x の上に描く。fitted は Gaussian・Lorentzian の結果(それ以外は settings のまま)。
    public static func run(_ a: ExtensionAnalysis, x: [Double], y: [Double], settings: PeakFitSettings,
                           samples: [Double]) throws -> (lines: [String], curve: [(x: Double, y: Double)], fitted: PeakFitSettings) {
        let pts = zip(x, y).filter { $0.0.isFinite && $0.1.isFinite }
        let xs = pts.map(\.0), ys = pts.map(\.1)
        switch a {
        case .gaussian, .lorentzian:
            let shape: PeakShape = a == .gaussian ? .gaussian : .lorentzian
            let fitted = try fitPeaks(shape, x: xs, y: ys, settings: settings)
            var sx = samples.filter(\.isFinite)
            if sx.isEmpty, let lo = xs.min(), let hi = xs.max() {
                sx = (0...200).map { lo + (hi - lo) * Double($0) / 200 }
            }
            let curve = sx.map { (x: $0, y: shape.value(fitted, at: $0)) }
            return (fitLines(fitted), curve, fitted)
        case .getMax:
            guard let i = ys.indices.max(by: { ys[$0] < ys[$1] }) else { throw FitError.notEnoughPoints(needed: 1) }
            return ([String(format: "MAX(X,Y)= %g, %g", xs[i], ys[i])], [], settings)
        case .getMin:
            guard let i = ys.indices.min(by: { ys[$0] < ys[$1] }) else { throw FitError.notEnoughPoints(needed: 1) }
            return ([String(format: "MIN(X,Y)= %g, %g", xs[i], ys[i])], [], settings)
        case .peakDetect:
            let peaks = detectPeaks(x: xs, y: ys)
            return (peaks.map { String(format: "(x,y)=(%g, %g)", $0.x, $0.y) }, [], settings)
        case .smoothing:
            let sm = movingAverage(ys, window: 5)
            return ([], zip(xs, sm).map { (x: $0.0, y: $0.1) }, settings)
        }
    }

    /// 結果の文("offset= %g" と、ピークごとに "%1d:Int.= %g" "%1d:Pos = %g" "%1d:Width=%g")
    public static func fitLines(_ s: PeakFitSettings) -> [String] {
        let s = s.normalized
        var lines = [String(format: "offset= %g", s.offset)]
        for i in 0..<s.count {
            lines.append(String(format: "%1ld:Int.= %g", i + 1, s.intensity[i]))
            lines.append(String(format: "%1ld:Pos = %g", i + 1, s.position[i]))
            lines.append(String(format: "%1ld:Width=%g", i + 1, s.width[i]))
        }
        return lines
    }

    /// ピークを探す: 極大のうち、高さ(prominence)が (最大 − 最小) の 5 % 以上のもの。x の順。
    public static func detectPeaks(x: [Double], y: [Double], minimumFraction: Double = 0.05) -> [(x: Double, y: Double)] {
        let pts = zip(x, y).filter { $0.0.isFinite && $0.1.isFinite }.sorted { $0.0 < $1.0 }
        let xs = pts.map(\.0), ys = pts.map(\.1)
        guard let lo = ys.min(), let hi = ys.max(), hi > lo else { return [] }
        let threshold = (hi - lo) * minimumFraction
        return PeakFinder.maxima(ys).filter { $0.prominence >= threshold }.map { (x: xs[$0.index], y: ys[$0.index]) }
    }

    /// n 点の移動平均(両端は窓を短くする)
    public static func movingAverage(_ v: [Double], window: Int = 5) -> [Double] {
        let h = Swift.max(window, 1) / 2
        guard v.count > 1, h > 0 else { return v }
        var prefix = [Double](repeating: 0, count: v.count + 1)
        for i in v.indices { prefix[i + 1] = prefix[i] + v[i] }
        return v.indices.map { i in
            let lo = Swift.max(0, i - h), hi = Swift.min(v.count - 1, i + h)
            return (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
        }
    }

    // MARK: - Gaussian・Lorentzian

    /// パラメータの並び: [offset, 強度1, 位置1, 幅1, 強度2, …]
    static func fitPeaks(_ shape: PeakShape, x: [Double], y: [Double], settings: PeakFitSettings) throws -> PeakFitSettings {
        let s = settings.normalized
        let n = s.count
        // 幅 0 では形が決まらないので、データの範囲から仮の幅にする
        let span = (x.max() ?? 0) - (x.min() ?? 0)
        let fallbackWidth = span > 0 ? span / Double(4 * n) : 1
        var p = [s.offset]
        var vary = [s.varyOffset]
        for i in 0..<n {
            let w = s.width[i].isFinite && s.width[i] != 0 ? s.width[i] : fallbackWidth
            p += [s.intensity[i], s.position[i], w]
            vary += [s.varyIntensity[i], s.varyPosition[i], s.varyWidth[i]]
        }
        guard !x.isEmpty else { throw FitError.notEnoughPoints(needed: Swift.max(vary.filter { $0 }.count, 1)) }
        let r = try Fitting.marquardt(x: x, y: y, initial: p, vary: vary, precision: s.precision,
                                      model: { shape.value($0, at: $1, count: n) },
                                      gradient: { shape.gradient($0, at: $1, count: n) })
        var out = s
        out.offset = r.parameters[0]
        for i in 0..<n {
            out.intensity[i] = r.parameters[1 + 3 * i]
            out.position[i] = r.parameters[2 + 3 * i]
            out.width[i] = Swift.abs(r.parameters[3 + 3 * i])
        }
        return out
    }
}

/// ピークの形
enum PeakShape {
    case gaussian
    case lorentzian

    static let k = 4 * Foundation.log(2.0)

    func value(_ p: [Double], at x: Double, count: Int) -> Double {
        var v = p[0]
        for i in 0..<count {
            let a = p[1 + 3 * i], c = p[2 + 3 * i], w = p[3 + 3 * i]
            let u = x - c
            let w2 = Swift.max(w * w, 1e-300)
            switch self {
            case .gaussian: v += a * Foundation.exp(-PeakShape.k * u * u / w2)
            case .lorentzian: v += a / (1 + 4 * u * u / w2)
            }
        }
        return v
    }

    func gradient(_ p: [Double], at x: Double, count: Int) -> [Double] {
        var g = [Double](repeating: 0, count: p.count)
        g[0] = 1
        for i in 0..<count {
            let a = p[1 + 3 * i], c = p[2 + 3 * i]
            let raw = p[3 + 3 * i]
            let w = Swift.abs(raw) < 1e-150 ? (raw < 0 ? -1e-150 : 1e-150) : raw
            let u = x - c
            let w2 = w * w
            let w3 = w2 * w
            switch self {
            case .gaussian:
                let e = Foundation.exp(-PeakShape.k * u * u / w2)
                g[1 + 3 * i] = e
                g[2 + 3 * i] = a * e * 2 * PeakShape.k * u / w2
                g[3 + 3 * i] = a * e * 2 * PeakShape.k * u * u / w3
            case .lorentzian:
                let l = 1 / (1 + 4 * u * u / w2)
                g[1 + 3 * i] = l
                g[2 + 3 * i] = a * l * l * 8 * u / w2
                g[3 + 3 * i] = a * l * l * 8 * u * u / w3
            }
        }
        return g
    }

    func value(_ s: PeakFitSettings, at x: Double) -> Double {
        let s = s.normalized
        var p = [s.offset]
        for i in 0..<s.count { p += [s.intensity[i], s.position[i], s.width[i]] }
        return value(p, at: x, count: s.count)
    }
}

/// 極大と、その目立ち方(prominence: 周りの谷からの高さ)
enum PeakFinder {
    struct Peak: Equatable {
        var index: Int
        var prominence: Double
    }

    /// 極大(両端は除く。平らな頂上はその真ん中)。y は x の順に並べたもの
    static func maxima(_ y: [Double]) -> [Peak] {
        let n = y.count
        guard n >= 3 else { return [] }
        var candidates: [Int] = []
        var i = 1
        while i < n - 1 {
            if y[i - 1] < y[i] {
                var ahead = i + 1
                while ahead < n - 1 && y[ahead] == y[i] { ahead += 1 }
                if y[ahead] < y[i] {
                    candidates.append((i + ahead - 1) / 2)
                    i = ahead
                }
            }
            i += 1
        }
        guard !candidates.isEmpty else { return [] }

        // それぞれの点から見て、左右でいちばん近い「より高い点」
        var higherLeft = [Int](repeating: -1, count: n)
        var higherRight = [Int](repeating: n, count: n)
        var stack: [Int] = []
        for j in 0..<n {
            while let t = stack.last, y[t] <= y[j] { stack.removeLast() }
            higherLeft[j] = stack.last ?? -1
            stack.append(j)
        }
        stack.removeAll()
        for j in stride(from: n - 1, through: 0, by: -1) {
            while let t = stack.last, y[t] <= y[j] { stack.removeLast() }
            higherRight[j] = stack.last ?? n
            stack.append(j)
        }
        let rmq = RangeMinimum(y)
        return candidates.map { p in
            let leftMin = rmq.min(higherLeft[p] + 1, p)
            let rightMin = rmq.min(p, higherRight[p] - 1)
            return Peak(index: p, prominence: y[p] - Swift.max(leftMin, rightMin))
        }
    }

    /// 半値全幅(base からの高さの半分で切ったときの幅)。切れなければ nil
    static func fullWidthAtHalfMaximum(_ x: [Double], _ y: [Double], peak i: Int, base: Double) -> Double? {
        let half = base + (y[i] - base) / 2
        guard y[i] > half else { return nil }
        func cross(_ a: Int, _ b: Int) -> Double {
            let dy = y[b] - y[a]
            return dy == 0 ? x[a] : x[a] + (half - y[a]) * (x[b] - x[a]) / dy
        }
        var left: Double?
        var j = i
        while j > 0 {
            if y[j - 1] <= half { left = cross(j - 1, j); break }
            j -= 1
        }
        var right: Double?
        j = i
        while j < y.count - 1 {
            if y[j + 1] <= half { right = cross(j, j + 1); break }
            j += 1
        }
        switch (left, right) {
        case let (l?, r?): return r - l
        case let (l?, nil): return 2 * (x[i] - l)
        case let (nil, r?): return 2 * (r - x[i])
        default: return nil
        }
    }
}

/// 区間の最小値(セグメント木)
struct RangeMinimum {
    let n: Int
    var tree: [Double]

    init(_ a: [Double]) {
        n = a.count
        tree = [Double](repeating: .infinity, count: 2 * Swift.max(n, 1))
        for i in 0..<n { tree[n + i] = a[i] }
        if n > 1 {
            for i in stride(from: n - 1, through: 1, by: -1) { tree[i] = Swift.min(tree[2 * i], tree[2 * i + 1]) }
        }
    }

    /// lo...hi(両端を含む)の最小値
    func min(_ lo: Int, _ hi: Int) -> Double {
        var res = Double.infinity
        var l = Swift.max(lo, 0) + n, r = Swift.min(hi, n - 1) + n + 1
        while l < r {
            if l & 1 == 1 { res = Swift.min(res, tree[l]); l += 1 }
            if r & 1 == 1 { r -= 1; res = Swift.min(res, tree[r]) }
            l >>= 1; r >>= 1
        }
        return res
    }
}
