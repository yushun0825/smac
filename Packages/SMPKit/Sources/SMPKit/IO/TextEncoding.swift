import Foundation

/// SMP は Windows の Shift_JIS(CP932)で書かれている。
public enum SMPTextEncoding {
    public static let windows31J: String.Encoding = {
        let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue))
        return String.Encoding(rawValue: cf)
    }()

    public static let windows1252: String.Encoding = .windowsCP1252

    /// SMP を文字列にする(CP932 → だめなら Latin-1)
    public static func decodeSMP(_ data: Data) -> String {
        if let s = String(data: data, encoding: windows31J) { return s }
        if let s = String(data: data, encoding: .shiftJIS) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    /// データファイルを文字列にする(UTF-8 → CP932 → Latin-1)
    public static func decodeDataFile(_ data: Data) -> String {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        if d.starts(with: [0xFF, 0xFE]) || d.starts(with: [0xFE, 0xFF]) {
            if let s = String(data: d, encoding: .utf16) { return s }
        }
        if let s = String(data: d, encoding: .utf8) { return s }
        if let s = String(data: d, encoding: windows31J) { return s }
        return String(data: d, encoding: .isoLatin1) ?? ""
    }

    /// CP932 で書けない文字は ? にして書く
    public static func encodeSMP(_ text: String) -> Data {
        if let d = text.data(using: windows31J, allowLossyConversion: false) { return d }
        return text.data(using: windows31J, allowLossyConversion: true) ?? Data(text.utf8)
    }

    /// CRLF・LF・CR のどれでも行に分ける(空行も残す)
    public static func splitLines(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
            .map(String.init)
    }
}
