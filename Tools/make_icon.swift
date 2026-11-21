// SmaC のアイコンを描いて、Assets.xcassets/AppIcon.appiconset に PNG を書く
// 使い方: swift Tools/make_icon.swift SmaC/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let k = s / 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // 本体(macOS のアイコンの枠: 1024 の中に 824 の角丸)
    let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = CGPath(roundedRect: body, cornerWidth: 186 * k, cornerHeight: 186 * k, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * k), blur: 20 * k, color: color(0x000000, 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x2F6BEA))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [color(0x4C8DFF), color(0x1F4FC8), color(0x16338F)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // 紙(白いカード)
    let card = CGRect(x: 196 * k, y: 206 * k, width: 632 * k, height: 600 * k)
    let cardPath = CGPath(roundedRect: card, cornerWidth: 54 * k, cornerHeight: 54 * k, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * k), blur: 34 * k, color: color(0x081A4A, 0.45))
    ctx.addPath(cardPath)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // 方眼
    let plot = CGRect(x: card.minX + 92 * k, y: card.minY + 86 * k, width: card.width - 150 * k, height: card.height - 150 * k)
    ctx.setStrokeColor(color(0x2F6BEA, 0.13))
    ctx.setLineWidth(max(1, 6 * k))
    for i in 1...4 {
        let x = plot.minX + plot.width * CGFloat(i) / 4
        ctx.move(to: CGPoint(x: x, y: plot.minY)); ctx.addLine(to: CGPoint(x: x, y: plot.maxY))
        let y = plot.minY + plot.height * CGFloat(i) / 4
        ctx.move(to: CGPoint(x: plot.minX, y: y)); ctx.addLine(to: CGPoint(x: plot.maxX, y: y))
    }
    ctx.strokePath()

    // 軸(左と下)
    ctx.setStrokeColor(color(0x15244F))
    ctx.setLineWidth(max(1.2, 16 * k))
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: plot.minX, y: plot.maxY + 10 * k))
    ctx.addLine(to: CGPoint(x: plot.minX, y: plot.minY))
    ctx.addLine(to: CGPoint(x: plot.maxX + 10 * k, y: plot.minY))
    ctx.strokePath()

    // 当てはめた曲線(なめらかに立ち上がる)
    func curve(_ t: Double) -> Double { 0.10 + 0.78 / (1 + exp(-(t - 0.5) * 9)) }
    ctx.setStrokeColor(color(0xFF7A2F))
    ctx.setLineWidth(max(1.5, 26 * k))
    ctx.setLineJoin(.round)
    for i in 0...160 {
        let t = Double(i) / 160
        let p = CGPoint(x: plot.minX + plot.width * CGFloat(0.04 + 0.92 * t), y: plot.minY + plot.height * CGFloat(curve(t)))
        if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
    }
    ctx.strokePath()

    // データの点(曲線のまわりに散らばる)
    let pts: [(Double, Double)] = [(0.06, 0.08), (0.2, 0.1), (0.34, -0.09), (0.47, 0.08), (0.6, -0.08), (0.74, 0.06), (0.9, -0.06)]
    for (t, dy) in pts {
        let c = CGPoint(x: plot.minX + plot.width * CGFloat(0.04 + 0.92 * t), y: plot.minY + plot.height * CGFloat(curve(t) + dy))
        let r = 27 * k
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        ctx.setFillColor(color(0x1F4FC8))
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(color(0xFFFFFF))
        ctx.setLineWidth(max(1, 9 * k))
        ctx.strokeEllipse(in: rect)
    }
    ctx.restoreGState()

    // 上の縁の光
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(color(0xFFFFFF, 0.18))
    ctx.setLineWidth(max(1, 4 * k))
    ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var images: [[String: String]] = []
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = pt * scale
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    try! draw(size: px).write(to: out.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
}
let json: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
try! data.write(to: out.appendingPathComponent("Contents.json"))
print("ok")
