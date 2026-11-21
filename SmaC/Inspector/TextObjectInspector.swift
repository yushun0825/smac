import SwiftUI
import AppKit
import SMPKit

/// 文字(軸の題・そのほかの文字)
struct InspectorTextForm: View {
    @ObservedObject var state: EditorState
    let gi: Int
    let id: UUID

    var body: some View {
        let b = state.textObject(gi, id)
        let t = b.wrappedValue
        InspectorForm {
            InspectorGroup {
                InspectorRichTextEditor(text: b.text, latin: t.latinFont, japanese: t.japaneseFont, color: t.color)
            }
            InspectorGroup("フォント") {
                InspectorFontNameRow(label: "欧文", name: b.latinFont.faceName, japanese: false)
                InspectorFontNameRow(label: "和文", name: b.japaneseFont.faceName, japanese: true)
                InspectorNumberRow(label: "大きさ", value: InspectorKit.textSize(b), unit: "pt")
                InspectorPickerRow("書体") {
                    FontStylePicker(font: InspectorKit.textStyle(b))
                }
                ColorRow(label: "色", color: b.color)
            }
            InspectorGroup("向きと位置") {
                InspectorAngleRow(angle: InspectorKit.finite(b.angle))
                InspectorNumberRow(label: "左から", value: InspectorKit.millimeters(b.x), unit: "mm")
                InspectorNumberRow(label: "上から", value: InspectorKit.millimeters(b.y), unit: "mm")
                Toggle("用紙の左上から測る", isOn: b.absolutePosition)
                Toggle("後ろを白で塗る", isOn: InspectorKit.opaqueBackground(b))
            } footer: {
                Text(t.absolutePosition ? "位置は用紙の左上から、1 行目の左下までを測ります。"
                                        : "位置はグラフの枠の左上から、1 行目の左下までを測ります。")
            }
            InspectorDeleteSection { state.perform?(.deleteObject(id)) }
        }
    }
}

/// 文字の中身の欄と見本。打ち込んでいる間は見本だけ変え、ほかへ移ったときか「反映」で書類へ入れる
struct InspectorRichTextEditor: View {
    /// SMP の書き方の文字(改行は \n の 2 文字)
    @Binding var text: String
    var latin: LogFont
    var japanese: LogFont
    var color: SMPColor

    /// 編集欄の文字(改行は本当の改行)
    @State private var draft = ""
    /// 打ち込み中の行き先(打ち込んでいる間に選ぶものが変わっても、元のものへ入れる)
    @State private var editing: Binding<String>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draft)
                .font(.system(size: NSFont.systemFontSize))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .frame(minHeight: 64, maxHeight: 160)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                .focused($focused)
            HStack(spacing: 8) {
                ControlCodeMenu { code in insert(code) }
                Spacer(minLength: 0)
                Button("反映") { commit() }
                    .disabled(!isDirty)
            }
            RichTextPreview(text: InspectorTextCodes.stored(draft), latin: latin, japanese: japanese, color: color)
                .frame(height: 56)
                .accessibilityLabel("文字の見本")
        }
        .onAppear { draft = InspectorTextCodes.editable(text) }
        .onChange(of: text) { _, new in
            if editing == nil { draft = InspectorTextCodes.editable(new) }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                editing = $text
            } else {
                commit()
                editing = nil
                draft = InspectorTextCodes.editable(text)
            }
        }
        .onDisappear(perform: commit)
    }

    private var isDirty: Bool {
        draft != InspectorTextCodes.editable((editing ?? $text).wrappedValue)
    }

    /// 書式の記号は最後に足して、すぐ書類へ入れる
    private func insert(_ code: String) {
        draft += InspectorTextCodes.editable(code)
        commit()
    }

    private func commit() {
        let target = editing ?? $text
        guard draft != InspectorTextCodes.editable(target.wrappedValue) else { return }
        target.wrappedValue = InspectorTextCodes.stored(draft)
    }
}

/// SMP の文字(改行を \n の 2 文字で持つ)と、編集欄の文字(本当の改行)の変換
enum InspectorTextCodes {
    /// SMP → 編集欄。\n だけを改行にし、ほかの \ の組(\\ など)はそのまま残す
    static func editable(_ s: String) -> String {
        let c = Array(s)
        var out = ""
        var i = 0
        while i < c.count {
            if c[i] == "\\", i + 1 < c.count {
                if c[i + 1] == "n" {
                    out.append("\n")
                } else {
                    out.append(c[i])
                    out.append(c[i + 1])
                }
                i += 2
            } else {
                out.append(c[i])
                i += 1
            }
        }
        return out
    }

    /// 編集欄 → SMP
    static func stored(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
