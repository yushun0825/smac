import Foundation

/// 3 次スプライン(端点の 2 階微分を 0 とする自然スプライン)と、パラメトリックスプライン
public enum Spline {
    public enum Mode: Int, Sendable, CaseIterable {
        case cubic = 0
        case parametric = 1
        case closedParametric = 2

        public var title: String {
            switch self {
            case .cubic: return "３次スプライン"
            case .parametric: return "パラメトリックスプライン"
            case .closedParametric: return "パラメトリックスプライン(閉曲線)"
            }
        }
    }

    struct Coefficients {
        var x: [Double]
        var a: [Double], b: [Double], c: [Double], d: [Double]

        func value(_ t: Double) -> Double {
            let n = x.count
            guard n >= 2 else { return n == 1 ? a[0] : .nan }
            var lo = 0, hi = n - 1
            if t <= x[0] { lo = 0 } else if t >= x[n - 1] { lo = n - 2 } else {
                while hi - lo > 1 {
                    let mid = (lo + hi) / 2
                    if x[mid] <= t { lo = mid } else { hi = mid }
                }
            }
            let h = t - x[lo]
            return a[lo] + h * (b[lo] + h * (c[lo] + h * d[lo]))
        }
    }

    /// 自然スプライン(x は昇順・重複なし)
    static func natural(_ x: [Double], _ y: [Double]) -> Coefficients? {
        let n = x.count
        guard n >= 2 else { return nil }
        if n == 2 {
            let slope = (y[1] - y[0]) / (x[1] - x[0])
            return Coefficients(x: x, a: y, b: [slope, slope], c: [0, 0], d: [0, 0])
        }
        var h = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) { h[i] = x[i + 1] - x[i] }
        var alpha = [Double](repeating: 0, count: n)
        for i in 1..<(n - 1) {
            alpha[i] = 3 / h[i] * (y[i + 1] - y[i]) - 3 / h[i - 1] * (y[i] - y[i - 1])
        }
        var l = [Double](repeating: 1, count: n), mu = [Double](repeating: 0, count: n), z = [Double](repeating: 0, count: n)
        for i in 1..<(n - 1) {
            l[i] = 2 * (x[i + 1] - x[i - 1]) - h[i - 1] * mu[i - 1]
            mu[i] = h[i] / l[i]
            z[i] = (alpha[i] - h[i - 1] * z[i - 1]) / l[i]
        }
        var c = [Double](repeating: 0, count: n), b = [Double](repeating: 0, count: n), d = [Double](repeating: 0, count: n)
        for j in stride(from: n - 2, through: 0, by: -1) {
            c[j] = z[j] - mu[j] * c[j + 1]
            b[j] = (y[j + 1] - y[j]) / h[j] - h[j] * (c[j + 1] + 2 * c[j]) / 3
            d[j] = (c[j + 1] - c[j]) / (3 * h[j])
        }
        return Coefficients(x: x, a: y, b: b, c: c, d: d)
    }

    /// 周期スプライン(閉曲線用)。y[0] と y[n-1] は同じ値として扱う
    static func periodic(_ t: [Double], _ y: [Double]) -> Coefficients? {
        let n = t.count - 1  // 区間の数
        guard n >= 2 else { return natural(t, y) }
        var h = [Double](repeating: 0, count: n)
        for i in 0..<n { h[i] = t[i + 1] - t[i] }
        // 2 階微分 M_i(i = 0..n-1、M_n = M_0)の巡回三重対角
        var A = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        var r = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let hm = h[(i - 1 + n) % n], hp = h[i]
            A[i][(i - 1 + n) % n] += hm
            A[i][i] += 2 * (hm + hp)
            A[i][(i + 1) % n] += hp
            let yp = y[(i + 1) % n == 0 ? n : i + 1]
            let ym = y[(i - 1 + n) % n]
            let yi = y[i]
            r[i] = 6 * ((yp - yi) / hp - (yi - ym) / hm)
        }
        guard let M = Fitting.solve(A, r) else { return natural(t, y) }
        var a = [Double](repeating: 0, count: n + 1), b = a, c = a, d = a
        for i in 0..<n {
            let m0 = M[i], m1 = M[(i + 1) % n]
            let y0 = y[i], y1 = y[i + 1]
            a[i] = y0
            b[i] = (y1 - y0) / h[i] - h[i] * (2 * m0 + m1) / 6
            c[i] = m0 / 2
            d[i] = (m1 - m0) / (6 * h[i])
        }
        a[n] = y[n]
        return Coefficients(x: t, a: a, b: b, c: c, d: d)
    }

    /// 点列を受け取り、描くための点列を返す
    public static func curve(x: [Double], y: [Double], mode: Mode, samples: [Double], divisions: Int) -> [(Double, Double)] {
        let pts = zip(x, y).filter { $0.0.isFinite && $0.1.isFinite }
        guard pts.count >= 2 else { return [] }
        switch mode {
        case .cubic:
            // x で並べ、同じ x は平均する
            let sorted = pts.sorted { $0.0 < $1.0 }
            var xs: [Double] = [], ys: [Double] = [], counts: [Int] = []
            for (px, py) in sorted {
                if let last = xs.last, last == px {
                    ys[ys.count - 1] += py; counts[counts.count - 1] += 1
                } else { xs.append(px); ys.append(py); counts.append(1) }
            }
            for i in ys.indices { ys[i] /= Double(counts[i]) }
            guard let co = natural(xs, ys) else { return [] }
            let lo = xs.first!, hi = xs.last!
            return samples.map { s in (s, (s < lo || s > hi) ? .nan : co.value(s)) }
        case .parametric, .closedParametric:
            var xs = pts.map(\.0), ys = pts.map(\.1)
            let closed = mode == .closedParametric
            if closed, let fx = xs.first, let fy = ys.first, (xs.last != fx || ys.last != fy) {
                xs.append(fx); ys.append(fy)
            }
            let t = (0..<xs.count).map(Double.init)
            guard let cx = closed ? periodic(t, xs) : natural(t, xs),
                  let cy = closed ? periodic(t, ys) : natural(t, ys) else { return [] }
            let n = Swift.max(divisions, 2)
            let tMax = Double(xs.count - 1)
            return (0...n).map { k in
                let tt = tMax * Double(k) / Double(n)
                return (cx.value(tt), cy.value(tt))
            }
        }
    }
}
