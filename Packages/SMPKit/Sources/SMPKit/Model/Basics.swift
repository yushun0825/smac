import Foundation

// SMP は位置・線幅などを 0.01 mm 単位の整数で持つ。ここでもその単位をそのまま使う。
public enum Units {
    /// 0.01 mm → PostScript ポイント
    public static let pointsPerHundredthMM: Double = 72.0 / 2540.0
    /// ポイント → 0.01 mm
    public static let hundredthMMPerPoint: Double = 2540.0 / 72.0

    public static func mm(_ v: Double) -> Double { v * 100 }
}

/// Windows の COLORREF(0x00BBGGRR)と同じ並びで色を持つ。
public struct SMPColor: Hashable, Sendable, Codable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    public init(colorref: Int) {
        let v = colorref & 0xFFFFFF
        r = UInt8(v & 0xFF)
        g = UInt8((v >> 8) & 0xFF)
        b = UInt8((v >> 16) & 0xFF)
    }

    /// 文字列制御コード %K の RRGGBB(16 進)
    public init?(hexRGB: String) {
        guard hexRGB.count == 6, let v = Int(hexRGB, radix: 16) else { return nil }
        r = UInt8((v >> 16) & 0xFF)
        g = UInt8((v >> 8) & 0xFF)
        b = UInt8(v & 0xFF)
    }

    public var colorref: Int { Int(r) | (Int(g) << 8) | (Int(b) << 16) }

    public static let black = SMPColor(r: 0, g: 0, b: 0)
    public static let white = SMPColor(r: 255, g: 255, b: 255)
    public static let red = SMPColor(r: 255, g: 0, b: 0)
    public static let blue = SMPColor(r: 0, g: 0, b: 255)
}

/// Windows の LOGFONT と同じ 13 個の値+フォント名。SMP にはこの形で書かれる。
public struct LogFont: Hashable, Sendable, Codable {
    public var height: Int
    public var width: Int
    public var escapement: Int
    public var orientation: Int
    public var weight: Int
    public var italic: Int
    public var underline: Int
    public var strikeOut: Int
    public var charSet: Int
    public var outPrecision: Int
    public var clipPrecision: Int
    public var quality: Int
    public var pitchAndFamily: Int
    public var faceName: String

    public init(height: Int = -2400, width: Int = 0, escapement: Int = 0, orientation: Int = 0,
                weight: Int = 400, italic: Int = 0, underline: Int = 0, strikeOut: Int = 0,
                charSet: Int = 0, outPrecision: Int = 3, clipPrecision: Int = 2, quality: Int = 1,
                pitchAndFamily: Int = 18, faceName: String = "Times New Roman") {
        self.height = height; self.width = width; self.escapement = escapement
        self.orientation = orientation; self.weight = weight; self.italic = italic
        self.underline = underline; self.strikeOut = strikeOut; self.charSet = charSet
        self.outPrecision = outPrecision; self.clipPrecision = clipPrecision
        self.quality = quality; self.pitchAndFamily = pitchAndFamily; self.faceName = faceName
    }

    /// 文字の大きさ(ポイント)。Ver.1.5 以降の SMP は 1/100 pt、古い SMP は pt で書かれている。
    public var pointSize: Double {
        get {
            let h = abs(Double(height))
            return h >= 100 ? h / 100.0 : h
        }
        set { height = -Int((newValue * 100).rounded()) }
    }

    public var isBold: Bool {
        get { weight >= 600 }
        set { weight = newValue ? 700 : 400 }
    }

    public var isItalic: Bool {
        get { italic != 0 }
        set { italic = newValue ? 255 : 0 }
    }

    /// 描画方向(度、反時計回り)。
    public var angle: Double {
        get { Double(orientation != 0 ? orientation : -escapement) / 10.0 }
        set {
            let v = Int((newValue * 10).rounded())
            orientation = v
            escapement = -v
        }
    }

    /// SMP に書く 13 個の値の行
    public var fieldsLine: String {
        [height, width, escapement, orientation, weight, italic, underline, strikeOut,
         charSet, outPrecision, clipPrecision, quality, pitchAndFamily].map(String.init).joined(separator: " ")
    }

    public static func parse(fields: [String], faceName: String) -> LogFont {
        func at(_ i: Int, _ d: Int) -> Int { i < fields.count ? (Int(fields[i]) ?? Int(Double(fields[i]) ?? Double(d))) : d }
        return LogFont(height: at(0, -2400), width: at(1, 0), escapement: at(2, 0), orientation: at(3, 0),
                       weight: at(4, 400), italic: at(5, 0), underline: at(6, 0), strikeOut: at(7, 0),
                       charSet: at(8, 0), outPrecision: at(9, 3), clipPrecision: at(10, 2),
                       quality: at(11, 1), pitchAndFamily: at(12, 18),
                       faceName: faceName)
    }

    public static func latinDefault(points: Double = 24) -> LogFont {
        var f = LogFont(faceName: "Times New Roman")
        f.pointSize = points
        return f
    }

    public static func japaneseDefault(points: Double = 24) -> LogFont {
        var f = LogFont(charSet: 128, pitchAndFamily: 17, faceName: "ＭＳ 明朝")
        f.pointSize = points
        return f
    }

    public static func symbolDefault(points: Double = 24) -> LogFont {
        var f = LogFont(charSet: 2, faceName: "Symbol")
        f.pointSize = points
        return f
    }
}

/// 線種(SMP の値の順: 線なし・実線・破線・点線・一点鎖線・二点鎖線・面)
public enum LineType: Int, CaseIterable, Sendable, Codable {
    case none = 0
    case solid = 1
    case dash = 2
    case dot = 3
    case dashDot = 4
    case dashDotDot = 5
    case fill = 6

    public var title: String {
        switch self {
        case .none: return "線なし"
        case .solid: return "実線"
        case .dash: return "破線"
        case .dot: return "点線"
        case .dashDot: return "一点鎖線"
        case .dashDotDot: return "二点鎖線"
        case .fill: return "面"
        }
    }

    public init(code: Int) { self = LineType(rawValue: code) ?? .solid }

    /// 「線種を自動更新」の次の線種(実線〜二点鎖線の 1〜5 を順に回る)
    public static func next(after type: LineType) -> LineType {
        let n = type.rawValue + 1
        return LineType(rawValue: (1...5).contains(n) ? n : 1) ?? .solid
    }
}

/// 軸の種類(SMP の値)。画面に並べる順は dialogOrder。
public enum ScaleType: Int, CaseIterable, Sendable, Codable {
    case linear = 0
    case logExponent = 1      // Log10(指数)
    case inverseReciprocal = 2 // Inverse(逆数表示)
    case logNormal = 3        // Log10(通常)
    case inverseNormal = 4    // Inverse(通常)

    public var title: String {
        switch self {
        case .linear: return "Linear"
        case .logExponent: return "Log10(指数)"
        case .logNormal: return "Log10(通常)"
        case .inverseReciprocal: return "Inverse(逆数表示)"
        case .inverseNormal: return "Inverse(通常)"
        }
    }

    public var isLog: Bool { self == .logExponent || self == .logNormal }
    public var isInverse: Bool { self == .inverseNormal || self == .inverseReciprocal }

    /// ダイアログに並べる順
    public static let dialogOrder: [ScaleType] = [.linear, .logExponent, .logNormal, .inverseReciprocal, .inverseNormal]
}

/// 枠の種類(SMP の値)
public enum FrameType: Int, CaseIterable, Sendable, Codable {
    case grid = 0     // 方眼
    case box = 1      // 枠
    case halfBox = 2  // 片枠
    case axes = 3     // 軸

    public var title: String {
        switch self {
        case .grid: return "方眼"
        case .box: return "枠"
        case .halfBox: return "片枠"
        case .axes: return "軸"
        }
    }

    public static let dialogOrder: [FrameType] = [.box, .grid, .halfBox, .axes]
}

// データ点の形(プロットの種類)は PlotType.swift を参照

/// 中塗り(LOGBRUSH の lbStyle)
public enum BrushStyle: Int, Sendable, Codable {
    case solid = 0
    case hollow = 1
    case hatched = 2
}
