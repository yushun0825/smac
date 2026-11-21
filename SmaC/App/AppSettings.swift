import AppKit
import Combine
import SMPKit

/// SmaC の設定(UserDefaults に保存する)
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    // 保存
    @Published var saveDataWithGraph: Bool { didSet { d.set(saveDataWithGraph, forKey: "saveDataWithGraph") } }
    @Published var omitPathInSameFolder: Bool { didSet { d.set(omitPathInSameFolder, forKey: "omitPathInSameFolder") } }
    // データを開くとき
    @Published var autoDotType: Bool { didSet { d.set(autoDotType, forKey: "autoDotType") } }
    @Published var autoLineType: Bool { didSet { d.set(autoLineType, forKey: "autoLineType") } }
    @Published var autoDotColor: Bool { didSet { d.set(autoDotColor, forKey: "autoDotColor") } }
    @Published var autoLineColor: Bool { didSet { d.set(autoLineColor, forKey: "autoLineColor") } }
    @Published var autoScaleX: Bool { didSet { d.set(autoScaleX, forKey: "autoScaleX") } }
    @Published var autoScaleY: Bool { didSet { d.set(autoScaleY, forKey: "autoScaleY") } }
    // 描画・操作
    @Published var clipToFrame: Bool { didSet { d.set(clipToFrame, forKey: "clipToFrame"); changed() } }
    /// 動かすときの刻み(mm、0 は刻まない)
    @Published var snapMM: Double { didSet { d.set(snapMM, forKey: "snapMM") } }
    /// 方眼の目安(mm、0 は出さない)
    @Published var gridMM: Double { didSet { d.set(gridMM, forKey: "gridMM"); changed() } }
    @Published var superscriptScale: Double { didSet { d.set(superscriptScale, forKey: "superscriptScale"); changed() } }
    @Published var superscriptRise: Double { didSet { d.set(superscriptRise, forKey: "superscriptRise"); changed() } }
    @Published var subscriptDrop: Double { didSet { d.set(subscriptDrop, forKey: "subscriptDrop"); changed() } }
    // 書き出し・印刷
    @Published var copyMarginMM: Double { didSet { d.set(copyMarginMM, forKey: "copyMarginMM") } }
    @Published var exportDPI: Double { didSet { d.set(exportDPI, forKey: "exportDPI") } }
    @Published var exportSeparatorTab: Bool { didSet { d.set(exportSeparatorTab, forKey: "exportSeparatorTab") } }
    @Published var printFooter: Bool { didSet { d.set(printFooter, forKey: "printFooter") } }

    static let settingsChanged = Notification.Name("SmaCSettingsChanged")

    private init() {
        d.register(defaults: [
            "saveDataWithGraph": true, "omitPathInSameFolder": false,
            "autoDotType": true, "autoLineType": false, "autoDotColor": false, "autoLineColor": false,
            "autoScaleX": true, "autoScaleY": true, "clipToFrame": false, "snapMM": 0.5, "gridMM": 0.0,
            "superscriptScale": 70.0, "superscriptRise": 50.0, "subscriptDrop": 20.0,
            "copyMarginMM": 5.0, "exportDPI": 300.0, "exportSeparatorTab": true, "printFooter": false,
        ])
        saveDataWithGraph = d.bool(forKey: "saveDataWithGraph")
        omitPathInSameFolder = d.bool(forKey: "omitPathInSameFolder")
        autoDotType = d.bool(forKey: "autoDotType")
        autoLineType = d.bool(forKey: "autoLineType")
        autoDotColor = d.bool(forKey: "autoDotColor")
        autoLineColor = d.bool(forKey: "autoLineColor")
        autoScaleX = d.bool(forKey: "autoScaleX")
        autoScaleY = d.bool(forKey: "autoScaleY")
        clipToFrame = d.bool(forKey: "clipToFrame")
        snapMM = d.double(forKey: "snapMM")
        gridMM = d.double(forKey: "gridMM")
        superscriptScale = d.double(forKey: "superscriptScale")
        superscriptRise = d.double(forKey: "superscriptRise")
        subscriptDrop = d.double(forKey: "subscriptDrop")
        copyMarginMM = d.double(forKey: "copyMarginMM")
        exportDPI = d.double(forKey: "exportDPI")
        exportSeparatorTab = d.bool(forKey: "exportSeparatorTab")
        printFooter = d.bool(forKey: "printFooter")
    }

    private func changed() {
        NotificationCenter.default.post(name: AppSettings.settingsChanged, object: nil)
    }

    var dataOpenPreferences: DataOpenPreferences {
        var p = DataOpenPreferences()
        p.autoDotType = autoDotType
        p.autoLineType = autoLineType
        p.autoDotColor = autoDotColor
        p.autoLineColor = autoLineColor
        p.autoScaleX = autoScaleX
        p.autoScaleY = autoScaleY
        return p
    }

    func renderOptions(fileName: String, fileDate: Date) -> RenderOptions {
        var o = RenderOptions()
        o.clipToFrame = clipToFrame
        o.superscriptScale = superscriptScale / 100
        o.superscriptRise = superscriptRise / 100
        o.subscriptDrop = subscriptDrop / 100
        o.fileName = fileName
        o.fileDate = fileDate
        return o
    }

    // MARK: - 既定のグラフ

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SmaC", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var defaultGraphURL: URL { supportDirectory.appendingPathComponent("default.SMP") }

    /// 新しいグラフの元(「既定のグラフにする」で保存したもの。なければ 140 × 100 mm の枠)
    func defaultGraph() -> Graph {
        if let data = try? Data(contentsOf: AppSettings.defaultGraphURL), let p = try? SMPReader.read(data: data), var g = p.graphs.first {
            g.series = []
            g.masks = []
            g.id = UUID()
            g.objects = g.objects.map { ObjectItem($0.object) }
            return g
        }
        return Graph.makeDefault()
    }

    func saveAsDefault(_ graph: Graph) throws {
        var p = SMPProject()
        var g = graph
        g.series = []
        g.masks = []
        g.page.saveData = false
        p.graphs = [g]
        try SMPWriter.data(for: p).write(to: AppSettings.defaultGraphURL)
    }

    func resetDefaultGraph() {
        try? FileManager.default.removeItem(at: AppSettings.defaultGraphURL)
    }

    // MARK: - 覚えておく値

    func stored<T: Codable>(_ key: String, as type: T.Type) -> T? {
        guard let data = d.data(forKey: "memo." + key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func store<T: Codable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { d.set(data, forKey: "memo." + key) }
    }
}
