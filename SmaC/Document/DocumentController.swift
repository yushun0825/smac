import AppKit
import UniformTypeIdentifiers
import SMPKit

/// データファイル(拡張子は何でもよい)も開けるようにする
final class SmaCDocumentController: NSDocumentController {
    override func typeForContents(of url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "smp" || ext == "sma" { return GraphDocument.smpType }
        if let t = try? super.typeForContents(of: url), t == GraphDocument.smpType { return t }
        return GraphDocument.dataType
    }

    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        // 拡張子にかかわらずデータファイルも選べるようにする
        openPanel.allowedContentTypes = []
        openPanel.allowsOtherFileTypes = true
        openPanel.message = "グラフ(SMP)か、データファイル(CSV・TXT・DAT など)を選んでください。"
        return super.runModalOpenPanel(openPanel, forTypes: nil)
    }

    override func makeDocument(withContentsOf url: URL, ofType typeName: String) throws -> NSDocument {
        if typeName == GraphDocument.smpType {
            return try super.makeDocument(withContentsOf: url, ofType: typeName)
        }
        // データファイルは新しい(名前のない)グラフとして開く。元のファイルを SMP で上書きしないため。
        guard let doc = try makeUntitledDocument(ofType: GraphDocument.smpType) as? GraphDocument else {
            throw CocoaError(.fileReadUnknown)
        }
        try doc.read(from: url, ofType: typeName)
        doc.suggestedBaseName = url.deletingPathExtension().lastPathComponent
        return doc
    }

    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let doc = GraphDocument()
        doc.fileType = GraphDocument.smpType
        doc.loadNewProject()
        return doc
    }
}

extension GraphDocument {
    /// 新規(グラフ 1 枚・データなし)
    func loadNewProject() {
        var p = SMPProject()
        var g = AppSettings.shared.defaultGraph()
        g.name = "Untitled.SMP"
        p.graphs = [g]
        replaceProjectWithoutUndo(p)
    }

    func replaceProjectWithoutUndo(_ p: SMPProject) {
        preview { $0 = p }
        activeGraphIndex = 0
    }
}
