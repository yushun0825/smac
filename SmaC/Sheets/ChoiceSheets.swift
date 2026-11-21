import SwiftUI
import AppKit
import SMPKit

extension Sheets {
    // MARK: - 定数

    /// 定数 a〜i
    struct ConstantsView: View {
        let close: () -> Void
        let done: ([Double]) -> Void
        @State private var values: [Double]
        @State private var note: String?
        @State private var finished = false

        static let names = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]

        init(values: [Double], close: @escaping () -> Void, done: @escaping ([Double]) -> Void) {
            self.close = close
            self.done = done
            _values = State(initialValue: Array((values + Array(repeating: 0, count: 9)).prefix(9)))
        }

        var body: some View {
            Scaffold(title: "定数", message: "式の中で a〜i として使える値です。", width: 380) {
                Form {
                    Section {
                        ForEach(0..<9, id: \.self) { k in
                            NumberRow(label: Self.names[k], value: $values[k], width: 150)
                        }
                    } footer: {
                        if let note { Text(note) }
                    }
                }
                .formStyle(.grouped)
                .labeledContentStyle(RowStyle())
                .onSubmit { finish() }
            } leading: {
                Button("コピー") { copy() }
                    .help("「a=値」の形の行にしてクリップボードにコピーします。")
                Button("ペースト") { paste() }
                    .help("クリップボードの「a=値」の形の行を読み込みます。")
            } trailing: {
                CancelButton(close: close)
                DefaultButton { finish() }
            }
        }

        private func copy() {
            Sheets.endEditing()
            let text = (0..<9).map { Self.names[$0] + "=" + Plain.string(values[$0]) }.joined(separator: "\n")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            note = "クリップボードにコピーしました。"
        }

        private func paste() {
            Sheets.endEditing()
            let parsed = Self.parse(NSPasteboard.general.string(forType: .string) ?? "")
            guard !parsed.isEmpty else {
                NSSound.beep()
                note = "クリップボードに「a=値」の形の行がありません。"
                return
            }
            for (k, v) in parsed { values[k] = v }
            note = String(parsed.count) + " 個の値を読み込みました。OK で確定します。"
        }

        /// 「a=1.5」「b = 2」「c: 3」「d<TAB>4」の行を読む。名前が無く数だけが 9 個以下並んでいれば a から順に入れる
        static func parse(_ text: String) -> [Int: Double] {
            var out: [Int: Double] = [:]
            for raw in text.components(separatedBy: .newlines) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard let sep = line.firstIndex(where: { "=＝:：\t".contains($0) }) else { continue }
                let name = line[..<sep].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
                guard let k = names.firstIndex(of: name), let v = DataParser.number(value) else { continue }
                out[k] = v
            }
            if out.isEmpty {
                let tokens = text.split(whereSeparator: { " \t\r\n,;".contains($0) }).map(String.init)
                let numbers = tokens.compactMap { DataParser.number($0) }
                if !numbers.isEmpty, numbers.count == tokens.count, numbers.count <= 9 {
                    for (k, v) in numbers.enumerated() { out[k] = v }
                }
            }
            return out
        }

        private func finish() {
            Sheets.endEditing()
            guard !finished else { return }
            finished = true
            let result = values
            close()
            done(result)
        }
    }

    // MARK: - データを選ぶ

    struct ChooseSeriesView: View {
        let title: String
        let message: String
        let items: [Series]
        let multiple: Bool
        let close: () -> Void
        let done: (IndexSet) -> Void
        @State private var single: Int?
        @State private var checked: Set<Int>
        @State private var finished = false

        init(title: String, message: String, items: [Series], multiple: Bool, preselected: IndexSet,
             close: @escaping () -> Void, done: @escaping (IndexSet) -> Void) {
            self.title = title
            self.message = message
            self.items = items
            self.multiple = multiple
            self.close = close
            self.done = done
            let valid = preselected.filteredIndexSet { $0 >= 0 && $0 < items.count }
            _single = State(initialValue: valid.first)
            _checked = State(initialValue: Set(valid))
        }

        var body: some View {
            Scaffold(title: title, message: message, width: 420) {
                Group {
                    if items.isEmpty {
                        Text("データがありません。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else if multiple {
                        checkList
                    } else {
                        singleList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            } leading: {
                if multiple {
                    Button("すべて選択") { checked = Set(items.indices) }
                        .disabled(items.isEmpty || checked.count == items.count)
                    Button("すべて解除") { checked = [] }
                        .disabled(checked.isEmpty)
                }
            } trailing: {
                CancelButton(close: close)
                DefaultButton(disabled: items.isEmpty || (!multiple && single == nil)) { finish() }
            }
        }

        private var listHeight: CGFloat {
            min(max(CGFloat(items.count) * 24 + 8, 96), 320)
        }

        private var singleList: some View {
            ScrollViewReader { proxy in
                List(selection: $single) {
                    ForEach(items.indices, id: \.self) { i in
                        row(i).tag(i)
                    }
                }
                .listStyle(.bordered)
                .alternatingRowBackgrounds()
                .frame(height: listHeight)
                .contextMenu(forSelectionType: Int.self) { _ in
                    EmptyView()
                } primaryAction: { selection in
                    // ダブルクリックで選んで閉じる
                    if let i = selection.first {
                        single = i
                        finish()
                    }
                }
                .onAppear {
                    if let single { proxy.scrollTo(single) }
                }
            }
        }

        private var checkList: some View {
            List {
                ForEach(items.indices, id: \.self) { i in
                    Toggle(isOn: checkBinding(i)) { row(i) }
                        .toggleStyle(.checkbox)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(height: listHeight)
        }

        private func row(_ i: Int) -> some View {
            HStack(spacing: 8) {
                Text(String(i + 1))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, alignment: .trailing)
                SeriesSwatch(series: items[i])
                Text(items[i].displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }

        private func checkBinding(_ i: Int) -> Binding<Bool> {
            Binding(get: { checked.contains(i) }, set: { on in
                if on { checked.insert(i) } else { checked.remove(i) }
            })
        }

        private func finish() {
            guard !finished else { return }
            let result: IndexSet
            if multiple {
                result = IndexSet(checked)
            } else {
                guard let single else { return }
                result = IndexSet(integer: single)
            }
            finished = true
            close()
            done(result)
        }
    }

    // MARK: - 1 行の入力

    struct InputView: View {
        let title: String
        let message: String
        let close: () -> Void
        let done: (String) -> Void
        @State private var text: String
        @State private var finished = false
        @FocusState private var focused: Bool

        init(title: String, message: String, text: String, close: @escaping () -> Void, done: @escaping (String) -> Void) {
            self.title = title
            self.message = message
            self.close = close
            self.done = done
            _text = State(initialValue: text)
        }

        var body: some View {
            Scaffold(title: title, message: message, width: 420) {
                TextField(message.isEmpty ? title : message, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($focused)
                    .onSubmit { finish() }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            } trailing: {
                CancelButton(close: close)
                DefaultButton(disabled: trimmed.isEmpty) { finish() }
            }
            .onAppear { focused = true }
        }

        private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

        private func finish() {
            guard !trimmed.isEmpty, !finished else { return }
            Sheets.endEditing()
            finished = true
            let result = trimmed
            close()
            done(result)
        }
    }
}
