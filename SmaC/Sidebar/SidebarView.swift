import SwiftUI
import SMPKit

/// 左のサイドバー: グラフごとに「枠と軸」・データ・文字や図形を並べる
struct SidebarView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        let _ = state.revision
        let p = state.project
        List(selection: selectionBinding) {
            ForEach(Array(p.graphs.enumerated()), id: \.element.id) { gi, g in
                Section {
                    GraphRow(graph: g).tag(EditorState.Selection.graph(gi))
                    ForEach(Array(g.series.enumerated()), id: \.element.id) { si, s in
                        SeriesRow(series: s, error: error(gi, si)) { state.toggleVisible(gi, si) }
                            .tag(EditorState.Selection.series(graph: gi, index: si))
                    }
                    .onMove { from, to in state.moveSeries(gi, from: from, to: to) }
                    // 文字・図形は手前のものを上に
                    let objects = Array(g.objects.reversed())
                    ForEach(objects, id: \.id) { item in
                        Label(item.object.displayTitle, systemImage: item.object.symbolName)
                            .lineLimit(1)
                            .tag(EditorState.Selection.object(graph: gi, id: item.id))
                    }
                    .onMove { from, to in state.moveObjects(gi, fromReversed: from, toReversed: to) }
                } header: {
                    Text(p.graphs.count > 1 ? "グラフ \(gi + 1)" : "グラフ")
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: EditorState.Selection.self) { items in
            if let first = items.first { contextItems(first) }
        }
        .onDeleteCommand {
            NSApp.sendAction(#selector(GraphWindowController.delete(_:)), to: nil, from: nil)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 4) {
                Menu {
                    Button("データを追加…") { send(#selector(GraphWindowController.addData(_:))) }
                    Button("新しいデータ…") { send(#selector(GraphWindowController.newData(_:))) }
                    Divider()
                    Button("文字") { send(#selector(GraphWindowController.insertTextBox(_:))) }
                    Button("凡例") { send(#selector(GraphWindowController.insertLegend(_:))) }
                    Button("矢印") { send(#selector(GraphWindowController.insertArrow(_:))) }
                    Button("枠") { send(#selector(GraphWindowController.insertBox(_:))) }
                    Button("点") { send(#selector(GraphWindowController.insertDot(_:))) }
                    Button("図…") { send(#selector(GraphWindowController.insertPicture(_:))) }
                    Divider()
                    Button("グラフを加える") { send(#selector(GraphWindowController.addGraph(_:))) }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("データ・文字・図形・グラフを加えます")
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    private var selectionBinding: Binding<EditorState.Selection?> {
        Binding(get: { state.selection == .none ? nil : state.selection },
                set: { state.select($0 ?? .none) })
    }

    private func error(_ gi: Int, _ si: Int) -> String? {
        state.plotData(gi, si)?.error
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    @ViewBuilder
    private func contextItems(_ sel: EditorState.Selection) -> some View {
        switch sel {
        case .graph(let gi):
            Button("グラフを複製") { state.select(sel); send(#selector(GraphWindowController.duplicateGraph(_:))) }
            Button("範囲を合わせる") { state.select(sel); send(#selector(GraphWindowController.autoRangeAll(_:))) }
            Button("既定のグラフにする") { state.select(sel); send(#selector(GraphWindowController.saveAsDefaultGraph(_:))) }
            Divider()
            Button("グラフを削除", role: .destructive) { state.select(.graph(gi)); send(#selector(GraphWindowController.deleteGraph(_:))) }
        case .series(let gi, let si):
            let s = gi < state.project.graphs.count && si < state.project.graphs[gi].series.count ? state.project.graphs[gi].series[si] : nil
            Button(s?.visible == false ? "表示する" : "隠す") { state.toggleVisible(gi, si) }
            if s?.kind != .function {
                Button("データを編集…") { state.select(sel); state.perform?(.editData(series: si)) }
            }
            if let s, s.kind != .normal || s.extensionAnalysis != nil {
                Button("条件を変える…") { state.select(sel); state.perform?(.refit(series: si)) }
                Button("結果を見る…") { state.select(sel); state.perform?(.showResults(series: si)) }
                if s.kind != .function {
                    Button("解析をやめる") { state.select(sel); state.perform?(.clearAnalysis(series: si)) }
                }
            }
            Button("値をコピー") { state.select(sel); state.perform?(.copyValues(series: si)) }
            Divider()
            Button("データを取り除く", role: .destructive) { state.select(sel); state.removeSeries(gi, si) }
        case .object(_, let id):
            Button("最前面へ") { state.select(sel); send(#selector(GraphWindowController.bringToFront(_:))) }
            Button("最背面へ") { state.select(sel); send(#selector(GraphWindowController.sendToBack(_:))) }
            Divider()
            Button("削除", role: .destructive) { state.select(sel); state.perform?(.deleteObject(id)) }
        case .none:
            EmptyView()
        }
    }
}

private struct GraphRow: View {
    var graph: Graph

    var body: some View {
        let name = (graph.name as NSString).deletingPathExtension
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text("枠と軸")
                if !name.isEmpty && !name.hasPrefix("Untitled") {
                    Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: "chart.xyaxis.line")
        }
    }
}

private struct SeriesRow: View {
    var series: Series
    var error: String?
    var toggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            SeriesSwatch(series: series)
                .opacity(series.visible ? 1 : 0.35)
            VStack(alignment: .leading, spacing: 1) {
                Text(series.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(series.visible ? .primary : .secondary)
                if let a = series.analysisTitle {
                    Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            if error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(error ?? "")
            }
            Button(action: toggle) {
                Image(systemName: series.visible ? "eye" : "eye.slash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(series.visible ? "隠す" : "表示する")
        }
    }
}

// MARK: - サイドバーからの書き換え

extension EditorState {
    func toggleVisible(_ gi: Int, _ si: Int) {
        guard let doc = document, gi < doc.project.graphs.count, si < doc.project.graphs[gi].series.count else { return }
        let v = doc.project.graphs[gi].series[si].visible
        doc.update(graph: gi, v ? "データを隠す" : "データを表示") { $0.series[si].visible = !v }
    }

    /// データの並べ替え(除いた範囲の番号も付け直す)
    func moveSeries(_ gi: Int, from: IndexSet, to: Int) {
        guard let doc = document, gi < doc.project.graphs.count else { return }
        doc.update(graph: gi, "データの並べ替え") { g in
            let oldIDs = g.series.map(\.id)
            g.series.move(fromOffsets: from, toOffset: to)
            let newIndex = Dictionary(uniqueKeysWithValues: g.series.enumerated().map { ($0.element.id, $0.offset) })
            g.masks = g.masks.compactMap { m in
                guard m.seriesIndex < oldIDs.count, let n = newIndex[oldIDs[m.seriesIndex]] else { return nil }
                var mm = m; mm.seriesIndex = n; return mm
            }
        }
        select(.graph(gi))
    }

    /// 文字・図形の重なりの順番を変える(サイドバーは手前が上なので逆に数える)
    func moveObjects(_ gi: Int, fromReversed: IndexSet, toReversed: Int) {
        guard let doc = document, gi < doc.project.graphs.count else { return }
        doc.update(graph: gi, "重なりの順番") { g in
            var reversed = Array(g.objects.reversed())
            reversed.move(fromOffsets: fromReversed, toOffset: toReversed)
            g.objects = reversed.reversed()
        }
    }

    func removeSeries(_ gi: Int, _ si: Int) {
        guard let doc = document, gi < doc.project.graphs.count, si < doc.project.graphs[gi].series.count else { return }
        doc.update("データを取り除く") { p in
            p.graphs[gi].series.remove(at: si)
            p.graphs[gi].masks = p.graphs[gi].masks.compactMap { m in
                if m.seriesIndex == si { return nil }
                var mm = m
                if m.seriesIndex > si { mm.seriesIndex -= 1 }
                return mm
            }
            GraphOps.pruneData(&p)
        }
        select(.graph(gi))
    }
}
