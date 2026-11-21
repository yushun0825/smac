import SwiftUI
import SMPKit

/// 窓ごとの「いま何を選んでいるか」と、サイドバー・インスペクタが書類を読み書きするための口
@MainActor
final class EditorState: ObservableObject {
    enum Selection: Hashable {
        case graph(Int)
        case series(graph: Int, index: Int)
        case object(graph: Int, id: UUID)
        case none

        var graphIndex: Int? {
            switch self {
            case .graph(let g), .series(let g, _), .object(let g, _): return g
            case .none: return nil
            }
        }
    }

    /// インスペクタから窓に頼むこと(窓の側が実行する)
    enum Command {
        case refit(series: Int)          // 解析の条件をもう一度設定する
        case clearAnalysis(series: Int)  // 解析をやめる(ふつうのデータに戻す)
        case editData(series: Int)       // データの中身を編集する
        case removeMask(Int)             // データマスクを消す
        case deleteObject(UUID)          // 文字・図形などを消す
        case choosePicture(UUID)         // 図のファイルを選び直す
        case showResults(series: Int)    // 解析の結果を出す
        case copyValues(series: Int)     // 変換後の値をクリップボードへ
    }

    @Published var selection: Selection = .graph(0)
    /// インスペクタからの頼み(窓の側が設定する)
    var perform: ((Command) -> Void)?
    /// 書類が変わるたびに増える(SwiftUI の画面を描き直すため)
    @Published private(set) var revision = 0
    /// インスペクタで開いている軸(0:X 1:Y 2:U 3:R)
    @Published var axisTab = 0
    /// グラフのインスペクタのタブ(0:グラフ 1:軸)。作業面で軸をダブルクリックすると 1 になる
    @Published var graphTab = 0
    /// データのインスペクタのタブ(0:データ 1:見た目 2:曲線)。解析のあとは 2 になる
    @Published var seriesTab = 0
    weak var document: GraphDocument?
    /// サイドバー・インスペクタから選択を変えたとき(キャンバスに伝える)
    var onSelect: ((Selection) -> Void)?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init(document: GraphDocument?) {
        self.document = document
        guard let document else { return }
        for name in [GraphDocument.projectChanged, GraphDocument.selectionChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: document, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.documentChanged() }
            })
        }
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    private func documentChanged() {
        revision += 1
        // 消えたものを選んでいたら、グラフの選択に戻す
        guard let doc = document else { return }
        switch selection {
        case .graph(let g) where g >= doc.project.graphs.count:
            selection = .graph(max(doc.project.graphs.count - 1, 0))
        case .series(let g, let s) where g >= doc.project.graphs.count || s >= doc.project.graphs[g].series.count:
            selection = .graph(min(g, max(doc.project.graphs.count - 1, 0)))
        case .object(let g, let id) where g >= doc.project.graphs.count || !doc.project.graphs[g].objects.contains(where: { $0.id == id }):
            selection = .graph(min(g, max(doc.project.graphs.count - 1, 0)))
        default: break
        }
    }

    var project: SMPProject { document?.project ?? SMPProject() }

    func select(_ s: Selection) {
        selection = s
        if let g = s.graphIndex, let doc = document, doc.activeGraphIndex != g, g < doc.project.graphs.count { doc.activeGraphIndex = g }
        onSelect?(s)
    }

    /// キャンバス側で選択が変わったとき(onSelect は呼ばない)
    func syncFromCanvas(_ s: Selection) {
        if selection != s { selection = s }
    }

    // MARK: - 書類への口(変えると取り消しの記録も残る)

    func graph<T: Equatable>(_ gi: Int, _ kp: WritableKeyPath<Graph, T>, _ action: String) -> Binding<T> {
        Binding(get: { [weak self] in
            guard let p = self?.project, gi < p.graphs.count else { return Graph()[keyPath: kp] }
            return p.graphs[gi][keyPath: kp]
        }, set: { [weak self] v in
            self?.document?.update(graph: gi, action) { g in
                g[keyPath: kp] = v
                g.syncCommonAxes()
            }
        })
    }

    func axis<T: Equatable>(_ gi: Int, _ ai: Int, _ kp: WritableKeyPath<AxisSpec, T>, _ action: String) -> Binding<T> {
        Binding(get: { [weak self] in
            guard let p = self?.project, gi < p.graphs.count else { return AxisSpec()[keyPath: kp] }
            return p.graphs[gi].axes[ai][keyPath: kp]
        }, set: { [weak self] v in
            self?.document?.update(graph: gi, action) { g in
                g.axes[ai][keyPath: kp] = v
                // U・R は X・Y と共通のとき同じ値にしておく(SMP の書き方)
                if ai >= 2 && g.axes[ai - 2].commonWithOpposite {
                    g.axes[ai - 2][keyPath: kp] = v
                }
                g.syncCommonAxes()
            }
        })
    }

    func series<T: Equatable>(_ gi: Int, _ si: Int, _ kp: WritableKeyPath<Series, T>, _ action: String) -> Binding<T> {
        Binding(get: { [weak self] in
            guard let p = self?.project, gi < p.graphs.count, si < p.graphs[gi].series.count else { return Series(name: "")[keyPath: kp] }
            return p.graphs[gi].series[si][keyPath: kp]
        }, set: { [weak self] v in
            guard let self, let doc = self.document else { return }
            doc.update(action) { p in
                guard gi < p.graphs.count, si < p.graphs[gi].series.count else { return }
                p.graphs[gi].series[si][keyPath: kp] = v
                let s = p.graphs[gi].series[si]
                if let f = p.dataFile(named: s.name) {
                    p.graphs[gi].series[si].linesRead = DataParser.rows(for: s, lines: f.lines).count
                }
            }
        })
    }

    /// 文字・矢印・枠・点・図(列挙の中に入っているもの)
    func object<T>(_ gi: Int, _ id: UUID, _ action: String, get: @escaping (GraphObject) -> T?, make: @escaping (T) -> GraphObject,
                   fallback: T) -> Binding<T> {
        Binding(get: { [weak self] in
            guard let p = self?.project, gi < p.graphs.count,
                  let item = p.graphs[gi].objects.first(where: { $0.id == id }), let v = get(item.object) else { return fallback }
            return v
        }, set: { [weak self] v in
            self?.document?.update(graph: gi, action) { g in
                if let k = g.objects.firstIndex(where: { $0.id == id }) { g.objects[k].object = make(v) }
            }
        })
    }

    func textObject(_ gi: Int, _ id: UUID) -> Binding<TextObject> {
        object(gi, id, "文字", get: { if case .text(let t) = $0 { return t } else { return nil } }, make: { .text($0) }, fallback: TextObject())
    }

    func shapeObject(_ gi: Int, _ id: UUID) -> Binding<ShapeObject> {
        object(gi, id, "図形", get: { if case .shape(let s) = $0 { return s } else { return nil } }, make: { .shape($0) }, fallback: ShapeObject())
    }

    func dotObject(_ gi: Int, _ id: UUID) -> Binding<DotObject> {
        object(gi, id, "点", get: { if case .dot(let d) = $0 { return d } else { return nil } }, make: { .dot($0) }, fallback: DotObject())
    }

    func pictureObject(_ gi: Int, _ id: UUID) -> Binding<PictureObject> {
        object(gi, id, "図", get: { if case .picture(let p) = $0 { return p } else { return nil } }, make: { .picture($0) },
               fallback: PictureObject(path: ""))
    }

    func plotData(_ gi: Int, _ si: Int) -> SeriesPlotData? {
        guard let doc = document else { return nil }
        let d = doc.plotData()
        guard gi < d.count, si < d[gi].count else { return nil }
        return d[gi][si]
    }
}

extension Graph {
    /// X・Y と共通の U・R を同じ値にそろえる(目盛り数字の有無などは U・R のまま)
    mutating func syncCommonAxes() {
        for base in 0..<2 where axes[base].commonWithOpposite {
            var m = axes[base]
            let old = axes[base + 2]
            m.drawLabels = old.drawLabels
            m.drawAxis = old.drawAxis
            m.line2Tail = old.line2Tail
            m.labelShiftX = old.labelShiftX
            m.labelShiftY = old.labelShiftY
            axes[base + 2] = m
        }
    }
}
