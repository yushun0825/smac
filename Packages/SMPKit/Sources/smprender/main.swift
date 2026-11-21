import Foundation
import SMPKit

// 確認用: SMP を PNG・PDF にする。読み直し(往復)の確認もできる
// smprender 入力.smp 出力.png [--dpi 150] [--roundtrip 書き直し.smp]
let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: smprender input.smp output.(png|pdf) [--dpi N] [--roundtrip out.smp]\n".data(using: .utf8)!)
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
var dpi = 150.0
var roundtrip: URL?
var i = 3
while i < args.count {
    if args[i] == "--dpi", i + 1 < args.count { dpi = Double(args[i + 1]) ?? dpi; i += 2; continue }
    if args[i] == "--roundtrip", i + 1 < args.count { roundtrip = URL(fileURLWithPath: args[i + 1]); i += 2; continue }
    i += 1
}

do {
    let data = try Data(contentsOf: input)
    var project: SMPProject
    let ext = input.pathExtension.lowercased()
    if ext == "smp" || ext == "sma" {
        project = try SMPReader.read(data: data, fileName: input.lastPathComponent)
    } else {
        project = DataImport.project(fromDataFile: input.lastPathComponent, path: input.path, contents: data)
    }
    if let rt = roundtrip {
        let written = SMPWriter.data(for: project)
        try written.write(to: rt)
        project = try SMPReader.read(data: written, fileName: rt.lastPathComponent)
    }
    var opts = RenderOptions()
    opts.fileName = input.lastPathComponent
    let renderer = GraphRenderer(project: project, options: opts)
    for (gi, d) in renderer.plotData.enumerated() {
        for (si, s) in d.enumerated() {
            let name = project.graphs[gi].series[si].displayName
            if let e = s.error { print("graph \(gi) series \(si) \(name): error \(e)") }
            if !s.resultLines.isEmpty { print("graph \(gi) series \(si) \(name) result:\n\(s.resultLines.joined(separator: "\n"))") }
            print("graph \(gi) series \(si) \(name): \(s.finitePoints.count) points, curve \(s.curve.count)")
        }
    }
    if output.pathExtension.lowercased() == "pdf" {
        try GraphExporter.pdfData(renderer: renderer).write(to: output)
    } else {
        guard let png = GraphExporter.pngData(renderer: renderer, dpi: dpi) else { throw NSError(domain: "render", code: 1) }
        try png.write(to: output)
    }
    print("wrote \(output.path)")
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
