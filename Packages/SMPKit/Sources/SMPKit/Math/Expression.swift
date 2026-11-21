import Foundation

/// 数式(x, y, 定数 a〜i, pi, #ffcc の列参照, 四則演算と ^)
public indirect enum ExprNode: Sendable, Equatable {
    case number(Double)
    case variable(String)          // 小文字にしたもの
    case column(file: Int, column: Int)
    case unary(Character, ExprNode)
    case binary(Character, ExprNode, ExprNode)
    case call(String, [ExprNode])
}

public struct ExpressionError: Error, LocalizedError, Equatable {
    public var message: String
    public var position: Int
    public var errorDescription: String? { message }
}

public enum ExprValue {
    case scalar(Double)
    case vector([Double])

    func at(_ i: Int) -> Double {
        switch self {
        case .scalar(let v): return v
        case .vector(let a): return i < a.count ? a[i] : .nan
        }
    }

    func materialize(_ n: Int) -> [Double] {
        switch self {
        case .scalar(let v): return Array(repeating: v, count: n)
        case .vector(let a): return a
        }
    }
}

/// 式を評価するときの値
public struct ExprContext {
    public var count: Int
    public var x: [Double]
    public var y: [Double]
    /// dif・integ で使う横の値(ふつうは元の x)
    public var abscissa: [Double]
    public var constants: [String: Double]
    /// (ファイル番号, 列番号 1 始まり) → 列の値。ファイル番号 0 は自分のファイル
    public var columnProvider: ((Int, Int) -> [Double]?)?

    public init(count: Int, x: [Double], y: [Double], abscissa: [Double]? = nil,
                constants: [String: Double] = [:], columnProvider: ((Int, Int) -> [Double]?)? = nil) {
        self.count = count; self.x = x; self.y = y
        self.abscissa = abscissa ?? x
        self.constants = constants
        self.columnProvider = columnProvider
    }

    public static func constantsDictionary(_ values: [Double]) -> [String: Double] {
        var d: [String: Double] = [:]
        let names = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
        for (i, n) in names.enumerated() where i < values.count { d[n] = values[i] }
        return d
    }
}

public struct Expression: Sendable, Equatable {
    public let source: String
    public let root: ExprNode

    public init(_ source: String) throws {
        self.source = source
        var p = ExprParser(source)
        root = try p.parseAll()
    }

    /// x だけ、または y だけの式か(変換しない式の判定)
    public var isIdentityX: Bool { root == .variable("x") }
    public var isIdentityY: Bool { root == .variable("y") }

    public func referencedVariables() -> Set<String> {
        var out = Set<String>()
        func walk(_ n: ExprNode) {
            switch n {
            case .variable(let v): out.insert(v)
            case .unary(_, let a): walk(a)
            case .binary(_, let a, let b): walk(a); walk(b)
            case .call(_, let args): args.forEach(walk)
            default: break
            }
        }
        walk(root)
        return out
    }

    public func evaluate(_ ctx: ExprContext) throws -> [Double] {
        try Expression.eval(root, ctx).materialize(ctx.count)
    }

    /// 1 つの値だけを計算する(四則計算機・値評価など)
    public func evaluateScalar(x: Double = 0, y: Double = 0, constants: [String: Double] = [:]) throws -> Double {
        let ctx = ExprContext(count: 1, x: [x], y: [y], constants: constants)
        return try Expression.eval(root, ctx).at(0)
    }

    static func eval(_ n: ExprNode, _ c: ExprContext) throws -> ExprValue {
        switch n {
        case .number(let v): return .scalar(v)
        case .variable(let name):
            switch name {
            case "x": return .vector(c.x)
            case "y": return .vector(c.y)
            case "pi": return .scalar(Double.pi)
            default:
                if let v = c.constants[name] { return .scalar(v) }
                if ["a", "b", "c", "d", "e", "f", "g", "h", "i"].contains(name) { return .scalar(0) }
                throw ExpressionError(message: "「\(name)」は使えない名前です。", position: 0)
            }
        case .column(let file, let column):
            guard let provider = c.columnProvider, let values = provider(file, column) else {
                throw ExpressionError(message: "#\(String(format: "%02d%02d", file, column)) の列が見つかりません。", position: 0)
            }
            return .vector(values)
        case .unary(let op, let a):
            let v = try eval(a, c)
            return map1(v) { op == "-" ? -$0 : $0 }
        case .binary(let op, let a, let b):
            let l = try eval(a, c), r = try eval(b, c)
            return map2(l, r, c.count) { p, q in
                switch op {
                case "+": return p + q
                case "-": return p - q
                case "*": return p * q
                case "/": return q == 0 ? .nan : p / q
                case "^": return pow(p, q)
                default: return .nan
                }
            }
        case .call(let name, let args):
            return try call(name, args, c)
        }
    }

    static func map1(_ v: ExprValue, _ f: (Double) -> Double) -> ExprValue {
        switch v {
        case .scalar(let s): return .scalar(f(s))
        case .vector(let a): return .vector(a.map(f))
        }
    }

    static func map2(_ a: ExprValue, _ b: ExprValue, _ n: Int, _ f: (Double, Double) -> Double) -> ExprValue {
        if case .scalar(let p) = a, case .scalar(let q) = b { return .scalar(f(p, q)) }
        var out = [Double](repeating: .nan, count: n)
        for i in 0..<n { out[i] = f(a.at(i), b.at(i)) }
        return .vector(out)
    }

    static let oneArg: [String: @Sendable (Double) -> Double] = [
        "abs": { Swift.abs($0) },
        "sqrt": { $0 < 0 ? .nan : Foundation.sqrt($0) },
        "exp": { Foundation.exp($0) },
        "ln": { $0 <= 0 ? .nan : Foundation.log($0) },
        "log": { $0 <= 0 ? .nan : Foundation.log10($0) },
        "sin": { Foundation.sin($0) },
        "cos": { Foundation.cos($0) },
        "tan": { Foundation.tan($0) },
        "asin": { Foundation.asin($0) },
        "acos": { Foundation.acos($0) },
        "atan": { Foundation.atan($0) },
        "sinh": { Foundation.sinh($0) },
        "cosh": { Foundation.cosh($0) },
        "tanh": { Foundation.tanh($0) },
        "theta": { $0 >= 0 ? 1 : 0 },
        "delta": { $0 == 0 ? 1 : 0 },
        "erfc": { Foundation.erfc($0) },
        "erf": { Foundation.erf($0) },
        "gamma": { Foundation.tgamma($0) },
        "int": { $0.rounded(.towardZero) },
        "sign": { $0 > 0 ? 1 : ($0 < 0 ? -1 : 0) },
    ]

    static func call(_ name: String, _ args: [ExprNode], _ c: ExprContext) throws -> ExprValue {
        let values = try args.map { try eval($0, c) }
        if let f = oneArg[name] {
            guard values.count == 1 else { throw ExpressionError(message: "\(name)() の引数は 1 つです。", position: 0) }
            return map1(values[0], f)
        }
        switch name {
        case "max", "min", "pow", "beta", "atan2", "mod":
            guard values.count == 2 else { throw ExpressionError(message: "\(name)() の引数は 2 つです。", position: 0) }
            return map2(values[0], values[1], c.count) { p, q in
                switch name {
                case "max": return Swift.max(p, q)
                case "min": return Swift.min(p, q)
                case "pow": return Foundation.pow(p, q)
                case "beta": return Foundation.exp(Foundation.lgamma(p) + Foundation.lgamma(q) - Foundation.lgamma(p + q))
                case "atan2": return Foundation.atan2(p, q)
                default: return q == 0 ? .nan : Foundation.fmod(p, q)
                }
            }
        case "dif":
            guard values.count == 1 else { throw ExpressionError(message: "dif() の引数は 1 つです。", position: 0) }
            return .vector(Expression.differentiate(values[0].materialize(c.count), c.abscissa))
        case "integ":
            guard values.count == 1 else { throw ExpressionError(message: "integ() の引数は 1 つです。", position: 0) }
            return .vector(Expression.integrate(values[0].materialize(c.count), c.abscissa))
        default:
            throw ExpressionError(message: "\(name)() という関数はありません。", position: 0)
        }
    }

    /// 隣の点との差から微分する(端は片側)
    public static func differentiate(_ v: [Double], _ x: [Double]) -> [Double] {
        let n = v.count
        guard n >= 2, x.count >= n else { return Array(repeating: .nan, count: n) }
        var out = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            let i0 = Swift.max(i - 1, 0), i1 = Swift.min(i + 1, n - 1)
            let dx = x[i1] - x[i0]
            out[i] = dx == 0 ? .nan : (v[i1] - v[i0]) / dx
        }
        return out
    }

    /// 台形則で最初の点から積分する
    public static func integrate(_ v: [Double], _ x: [Double]) -> [Double] {
        let n = v.count
        guard n >= 1, x.count >= n else { return Array(repeating: .nan, count: n) }
        var out = [Double](repeating: 0, count: n)
        var sum = 0.0
        for i in 1..<Swift.max(n, 1) where i < n {
            let a = v[i - 1], b = v[i]
            if a.isFinite, b.isFinite { sum += (a + b) * 0.5 * (x[i] - x[i - 1]) }
            out[i] = sum
        }
        return out
    }
}

struct ExprParser {
    let chars: [Character]
    var pos = 0

    init(_ s: String) { chars = Array(s) }

    mutating func parseAll() throws -> ExprNode {
        skipSpaces()
        if pos >= chars.count { throw ExpressionError(message: "式が空です。", position: 0) }
        let n = try parseExpr()
        skipSpaces()
        if pos < chars.count {
            throw ExpressionError(message: "「\(String(chars[pos...]))」の前に誤りがあります。", position: pos)
        }
        return n
    }

    mutating func skipSpaces() {
        while pos < chars.count, chars[pos] == " " || chars[pos] == "\t" || chars[pos] == "\u{3000}" { pos += 1 }
    }

    func peek() -> Character? { pos < chars.count ? chars[pos] : nil }

    mutating func parseExpr() throws -> ExprNode {
        var lhs = try parseTerm()
        while true {
            skipSpaces()
            guard let c = peek(), c == "+" || c == "-" else { return lhs }
            pos += 1
            let rhs = try parseTerm()
            lhs = .binary(c, lhs, rhs)
        }
    }

    mutating func parseTerm() throws -> ExprNode {
        var lhs = try parseUnary()
        while true {
            skipSpaces()
            guard let c = peek(), c == "*" || c == "/" || c == "×" || c == "÷" else { return lhs }
            pos += 1
            let rhs = try parseUnary()
            lhs = .binary(c == "×" ? "*" : (c == "÷" ? "/" : c), lhs, rhs)
        }
    }

    mutating func parseUnary() throws -> ExprNode {
        skipSpaces()
        if let c = peek(), c == "-" || c == "+" || c == "−" {
            pos += 1
            let operand = try parseUnary()
            return c == "+" ? operand : .unary("-", operand)
        }
        return try parsePower()
    }

    mutating func parsePower() throws -> ExprNode {
        let base = try parsePrimary()
        skipSpaces()
        if let c = peek(), c == "^" {
            pos += 1
            let exponent = try parseUnary()
            return .binary("^", base, exponent)
        }
        if pos + 1 < chars.count, chars[pos] == "*", chars[pos + 1] == "*" {
            pos += 2
            let exponent = try parseUnary()
            return .binary("^", base, exponent)
        }
        return base
    }

    mutating func parsePrimary() throws -> ExprNode {
        skipSpaces()
        guard let c = peek() else { throw ExpressionError(message: "式が途中で終わっています。", position: pos) }
        if c == "(" {
            pos += 1
            let inner = try parseExpr()
            skipSpaces()
            guard peek() == ")" else { throw ExpressionError(message: "かっこが閉じていません。", position: pos) }
            pos += 1
            return inner
        }
        if c == "#" {
            pos += 1
            var digits = ""
            while let d = peek(), d.isASCII, d.isNumber, digits.count < 4 { digits.append(d); pos += 1 }
            guard digits.count == 4, let file = Int(digits.prefix(2)), let col = Int(digits.suffix(2)) else {
                throw ExpressionError(message: "列の指定は #0003 のように # の後に 4 桁で書いてください。", position: pos)
            }
            return .column(file: file, column: col)
        }
        if c.isNumber || c == "." {
            return .number(try parseNumber())
        }
        if c.isLetter || c == "_" || c == "π" {
            if c == "π" { pos += 1; return .variable("pi") }
            var name = ""
            while let d = peek(), d.isLetter || d.isNumber || d == "_" { name.append(d); pos += 1 }
            let lower = name.lowercased()
            skipSpaces()
            if peek() == "(" {
                pos += 1
                var args: [ExprNode] = []
                skipSpaces()
                if peek() == ")" { pos += 1; return .call(lower, args) }
                while true {
                    args.append(try parseExpr())
                    skipSpaces()
                    if peek() == "," { pos += 1; continue }
                    guard peek() == ")" else { throw ExpressionError(message: "\(name)( のかっこが閉じていません。", position: pos) }
                    pos += 1
                    break
                }
                return .call(lower, args)
            }
            return .variable(lower)
        }
        throw ExpressionError(message: "「\(c)」は式に使えません。", position: pos)
    }

    mutating func parseNumber() throws -> Double {
        let start = pos
        while let d = peek(), d.isNumber || d == "." { pos += 1 }
        if let e = peek(), e == "e" || e == "E" {
            // 1e-3 の形(e の後に数字か符号が続くときだけ)
            let save = pos
            pos += 1
            if let s = peek(), s == "+" || s == "-" { pos += 1 }
            if let d = peek(), d.isNumber {
                while let d = peek(), d.isNumber { pos += 1 }
            } else {
                pos = save
            }
        }
        let text = String(chars[start..<pos])
        guard let v = Double(text) else { throw ExpressionError(message: "「\(text)」は数値として読めません。", position: start) }
        return v
    }
}
