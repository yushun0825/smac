import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// PDF・PNG への書き出し(図面コピー・エクスポート・確認用)
public enum GraphExporter {
    /// 用紙の座標(0.01 mm)での書き出す範囲。nil なら全グラフの外枠に余白 margin(既定 1 cm)を付ける
    public static func exportRect(renderer: GraphRenderer, margin: Double = 1000) -> CGRect {
        let b = renderer.contentBounds()
        return b.insetBy(dx: -margin, dy: -margin)
    }

    /// 0.01 mm・y 下向きの座標で描けるように ctx を合わせる(ctx は y 上向き)
    static func prepare(_ ctx: CGContext, rect: CGRect, pixelsPerUnit k: CGFloat, height: CGFloat) {
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: k, y: -k)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
    }

    public static func pdfData(renderer: GraphRenderer, rect: CGRect? = nil, scale: Double = 1) -> Data {
        let r = rect ?? exportRect(renderer: renderer)
        let k = CGFloat(Units.pointsPerHundredthMM * scale)
        var media = CGRect(x: 0, y: 0, width: r.width * k, height: r.height * k)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &media, nil) else { return Data() }
        ctx.beginPDFPage(nil)
        prepare(ctx, rect: r, pixelsPerUnit: k, height: media.height)
        renderer.draw(in: ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    public static func cgImage(renderer: GraphRenderer, rect: CGRect? = nil, dpi: Double = 300, transparent: Bool = false) -> CGImage? {
        let r = rect ?? exportRect(renderer: renderer)
        let k = CGFloat(dpi / 2540.0)
        let w = Int((r.width * k).rounded(.up)), h = Int((r.height * k).rounded(.up))
        guard w > 0, h > 0, w * h < 400_000_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if !transparent {
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        prepare(ctx, rect: r, pixelsPerUnit: k, height: CGFloat(h))
        renderer.draw(in: ctx)
        return ctx.makeImage()
    }

    public static func pngData(renderer: GraphRenderer, rect: CGRect? = nil, dpi: Double = 300, transparent: Bool = false) -> Data? {
        guard let img = cgImage(renderer: renderer, rect: rect, dpi: dpi, transparent: transparent) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
