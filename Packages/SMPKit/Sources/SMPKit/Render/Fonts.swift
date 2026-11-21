import Foundation
import CoreText
import CoreGraphics

/// Windows のフォント名を Mac にあるフォントに置き換える
public enum FontMapper {
    static let japaneseMap: [String: String] = [
        "ＭＳ 明朝": "Hiragino Mincho ProN", "ＭＳ Ｐ明朝": "Hiragino Mincho ProN", "MS 明朝": "Hiragino Mincho ProN",
        "MS P明朝": "Hiragino Mincho ProN", "MS Mincho": "Hiragino Mincho ProN", "MS PMincho": "Hiragino Mincho ProN",
        "ＭＳ ゴシック": "Hiragino Sans", "ＭＳ Ｐゴシック": "Hiragino Sans", "MS ゴシック": "Hiragino Sans",
        "MS Pゴシック": "Hiragino Sans", "MS Gothic": "Hiragino Sans", "MS PGothic": "Hiragino Sans",
        "MS UI Gothic": "Hiragino Sans", "メイリオ": "Hiragino Sans", "Meiryo": "Hiragino Sans", "Meiryo UI": "Hiragino Sans",
        "游明朝": "YuMincho", "Yu Mincho": "YuMincho", "游ゴシック": "YuGothic", "Yu Gothic": "YuGothic",
        "ＭＳ ＵＩ ゴシック": "Hiragino Sans", "HG明朝E": "Hiragino Mincho ProN", "HGゴシックE": "Hiragino Sans",
    ]

    static let latinMap: [String: String] = [
        "Century": "Times New Roman", "Century Schoolbook": "Times New Roman", "Courier": "Courier New",
        "Helvetica": "Helvetica", "Arial Narrow": "Arial Narrow", "Symbol": "Symbol", "Times": "Times New Roman",
        "Tahoma": "Tahoma", "Verdana": "Verdana", "Calibri": "Helvetica Neue", "Cambria": "Times New Roman",
        "Segoe UI": "Helvetica Neue",
    ]

    /// Mac で使うファミリー名
    public static func macFamily(_ windowsName: String, japanese: Bool) -> String {
        let name = windowsName.trimmingCharacters(in: .whitespaces)
        if let m = japaneseMap[name] { return available(m) ? m : (japanese ? "Hiragino Mincho ProN" : "Times New Roman") }
        if let m = latinMap[name], available(m) { return m }
        if !name.isEmpty, available(name) { return name }
        // 全角のスペースや "Ｐ" の違いを無視してもう一度探す
        let normalized = name.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
        for (k, v) in japaneseMap where k.replacingOccurrences(of: " ", with: "") == normalized { return v }
        if japanese { return name.contains("ゴシック") || name.lowercased().contains("gothic") ? "Hiragino Sans" : "Hiragino Mincho ProN" }
        return "Times New Roman"
    }

    nonisolated(unsafe) static var availability: [String: Bool] = [:]
    static let lock = NSLock()

    public static func available(_ family: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let v = availability[family] { return v }
        let desc = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute as String: family] as CFDictionary)
        let mandatory: CFSet = Set([kCTFontFamilyNameAttribute as String]) as NSSet
        let found = CTFontDescriptorCreateMatchingFontDescriptors(desc, mandatory) != nil
        availability[family] = found
        return found
    }

    nonisolated(unsafe) static var cache: [String: CTFont] = [:]

    /// family・大きさ(描画単位)・太字・斜体から CTFont を作る
    public static func font(family: String, size: CGFloat, bold: Bool, italic: Bool) -> CTFont {
        let key = "\(family)|\(size)|\(bold)|\(italic)"
        lock.lock()
        if let f = cache[key] { lock.unlock(); return f }
        lock.unlock()
        var traits: CTFontSymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let attrs: [String: Any] = [
            kCTFontFamilyNameAttribute as String: family,
            kCTFontTraitsAttribute as String: [kCTFontSymbolicTrait as String: traits.rawValue],
        ]
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        var f = CTFontCreateWithFontDescriptor(desc, size, nil)
        // 斜体が無いフォント(ヒラギノなど)は斜めにする
        let actual = CTFontGetSymbolicTraits(f)
        if italic && !actual.contains(.traitItalic) {
            var m = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
            let base = CTFontCreateCopyWithSymbolicTraits(f, size, nil, bold ? .traitBold : [], bold ? .traitBold : []) ?? f
            f = CTFontCreateCopyWithAttributes(base, size, &m, nil)
        }
        if bold && !CTFontGetSymbolicTraits(f).contains(.traitBold) {
            // 太字が無いときはそのまま(ヒラギノ明朝は W6 があるので通常は見つかる)
        }
        lock.lock(); cache[key] = f; lock.unlock()
        return f
    }

    /// 和文のフォントで描く文字か
    public static func isJapanese(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x3000...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF,
             0x2E80...0x2FFF, 0x31F0...0x31FF, 0x20000...0x2FFFF, 0x203B, 0x2460...0x24FF, 0x25A0...0x25FF,
             0x2600...0x26FF, 0x3200...0x33FF:
            return true
        default:
            return false
        }
    }
}
