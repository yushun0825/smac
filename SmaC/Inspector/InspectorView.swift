import SwiftUI
import AppKit
import SMPKit

/// 右側の設定の欄(インスペクタ)。選んでいるもの(グラフ・データ・文字や図形)の設定を出し、その場で変えられるようにする
struct InspectorView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        // 書類が変わるたびに描き直す
        let _ = state.revision
        let graphs = state.project.graphs
        Group {
            switch state.selection {
            case .graph(let gi) where graphs.indices.contains(gi):
                GraphInspector(state: state, gi: gi)
                    .id("graph-\(gi)")
            case .series(let gi, let si) where graphs.indices.contains(gi) && graphs[gi].series.indices.contains(si):
                SeriesInspector(state: state, gi: gi, si: si)
                    .id("series-\(gi)-\(si)")
            case .object(let gi, let id) where graphs.indices.contains(gi) && graphs[gi].objects.contains(where: { $0.id == id }):
                ObjectInspector(state: state, gi: gi, id: id)
                    .id(id)
            default:
                InspectorEmptyView()
            }
        }
        .controlSize(.small)
        .frame(minWidth: 240, idealWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 何も選んでいないとき
struct InspectorEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("グラフやデータを選ぶと、ここに設定が出ます")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 欄のいちばん上の見出し(印・名前・補足)
struct InspectorHeader<Icon: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 26, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

/// 見出しの下のタブ(区切られたボタン)
struct InspectorTabPicker: View {
    @Binding var selection: Int
    var titles: [String]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(titles.indices, id: \.self) { i in
                Text(titles[i]).tag(i)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

/// 設定の並び(まとまりを上から並べ、長ければスクロールする)
struct InspectorForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
        }
        .font(.system(size: NSFont.smallSystemFontSize))
        .labeledContentStyle(InspectorRowStyle())
    }
}

/// 見出し・中身・補足の 1 つのまとまり(下に区切り線)
struct InspectorGroup<Content: View, Footer: View>: View {
    var title: String?
    var content: Content
    var footer: Footer

    init(_ title: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: NSFont.smallSystemFontSize, weight: .bold))
                    .padding(.bottom, 1)
            }
            content
            footer
                .font(.system(size: NSFont.smallSystemFontSize - 1))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

extension InspectorGroup where Footer == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, content: content, footer: { EmptyView() })
    }
}

/// 1 行の並べ方: 名前を左、値を右に置く
struct InspectorRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 8) {
            configuration.label
                .fixedSize()
            Spacer(minLength: 4)
            configuration.content
        }
    }
}

/// 名前を左、選ぶもの(Picker など)を右に置く行。中のものの名前は隠す
struct InspectorPickerRow<Control: View>: View {
    var label: String
    var control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        LabeledContent(label) {
            control
                .labelsHidden()
                .fixedSize()
        }
    }
}

/// 数値の行(NumberRow)。単位の無い欄も単位の幅をあけて、欄の右端をそろえる
struct InspectorNumberRow: View {
    var label: String
    @Binding var value: Double
    var unit = ""

    var body: some View {
        NumberRow(label: label, value: $value, unit: unit.isEmpty ? " " : unit)
    }
}

/// いちばん下の「削除」
struct InspectorDeleteSection: View {
    var action: () -> Void

    var body: some View {
        InspectorGroup {
            Button(role: .destructive, action: action) {
                Label("削除", systemImage: "trash")
            }
        }
    }
}
