import SwiftUI
import AppKit
import SMPKit

// シートに共通の部品(枠・ボタン・数値の欄・式の確かめ)

extension Sheets {
    /// シートの枠: 題・説明・中身・下のボタン(左と右)
    struct Scaffold<Content: View, Leading: View, Trailing: View>: View {
        var title: String
        var message: String?
        var width: CGFloat
        var content: Content
        var leading: Leading
        var trailing: Trailing
        @Environment(\.sheetBodyMaxHeight) private var maxBodyHeight

        init(title: String, message: String? = nil, width: CGFloat, @ViewBuilder content: () -> Content,
             @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
            self.title = title
            self.message = message
            self.width = width
            self.content = content()
            self.leading = leading()
            self.trailing = trailing()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    if let message, !message.isEmpty {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                content
                    .frame(maxHeight: maxBodyHeight)
                HStack(spacing: 8) {
                    leading
                    Spacer(minLength: 16)
                    trailing
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// シートの中を切り替える(「条件」と「曲線」など)
    struct PageSwitcher: View {
        @Binding var selection: Int
        var titles: [String]

        var body: some View {
            Picker("表示する項目", selection: $selection) {
                ForEach(titles.indices, id: \.self) { i in Text(titles[i]).tag(i) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
        }
    }

    /// 行の見出しと中身を上下の真ん中でそろえる(数値の欄の空のラベルが行を押し広げないようにする)。
    /// 中身には先に幅を渡す(欄の間の「〜」などが詰められて消えないように)
    struct RowStyle: LabeledContentStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(alignment: .center, spacing: 12) {
                configuration.label
                Spacer(minLength: 0)
                configuration.content
                    .labelsHidden()
                    .layoutPriority(1)
            }
        }
    }

    struct CancelButton: View {
        var close: () -> Void

        var body: some View {
            Button(role: .cancel) {
                close()
            } label: {
                Text("キャンセル").frame(minWidth: 60)
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    /// Return で押されるボタン
    struct DefaultButton: View {
        var title: String = "OK"
        var disabled: Bool = false
        var action: () -> Void

        var body: some View {
            Button {
                action()
            } label: {
                Text(title).frame(minWidth: 60)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(disabled)
        }
    }

    /// キャンセルのボタンが無いシートで、esc キーでも閉じられるようにする(見えないボタン)
    struct EscapeCatcher: View {
        var close: () -> Void

        var body: some View {
            Button("閉じる") { close() }
                .keyboardShortcut(.cancelAction)
                .focusable(false)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// ラベルの無い数値の欄(表の中などに使う)
    struct NumberField: View {
        @Binding var value: Double
        var width: CGFloat = 90

        var body: some View {
            TextField("", value: $value, format: .plain)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
                .frame(width: width)
        }
    }

    /// 式の欄の下の 1 行(誤りがあれば赤で、なければ書き方の説明)
    struct StatusLine: View {
        var error: String?
        var hint: String

        var body: some View {
            Group {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Text(hint)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 式の確かめ
    enum ExpressionCheck {
        /// 式の誤り(なければ nil。空の式も nil)。allowColumns が false なら列の指定(#ffcc)を誤りにする
        static func problem(_ text: String, allowColumns: Bool) -> String? {
            let t = text.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            let expression: SMPKit.Expression
            do {
                expression = try SMPKit.Expression(t)
            } catch {
                return describe(error)
            }
            // 1 点で計算してみて、使えない名前・関数・引数の数を見つける
            var usesColumn = false
            var constants: [String: Double] = [:]
            for name in ["a", "b", "c", "d", "e", "f", "g", "h", "i"] { constants[name] = 1 }
            let context = ExprContext(count: 1, x: [1], y: [1], constants: constants, columnProvider: { _, _ in
                usesColumn = true
                return [1]
            })
            do {
                _ = try expression.evaluate(context)
            } catch {
                return describe(error)
            }
            if usesColumn && !allowColumns { return "この式では列の指定(#ffcc)は使えません。" }
            return nil
        }

        static func describe(_ error: Error) -> String {
            if let e = error as? ExpressionError { return e.message }
            return (error as? LocalizedError)?.errorDescription ?? "式を読み取れません。"
        }
    }

    /// SMP の行やクリップボードに書く数(有効数字 15 桁。3 桁区切りは付けない)
    enum Plain {
        static func string(_ v: Double) -> String {
            v.isFinite ? String(format: "%.15g", v) : "0"
        }
    }
}

extension Sheets.Scaffold where Leading == EmptyView {
    init(title: String, message: String? = nil, width: CGFloat, @ViewBuilder content: () -> Content,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, message: message, width: width, content: content, leading: { EmptyView() }, trailing: trailing)
    }
}

private struct SheetBodyMaxHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 640
}

extension EnvironmentValues {
    /// シートの中身の高さの上限(画面の高さから決める)
    var sheetBodyMaxHeight: CGFloat {
        get { self[SheetBodyMaxHeightKey.self] }
        set { self[SheetBodyMaxHeightKey.self] = newValue }
    }
}
