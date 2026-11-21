import SwiftUI
import AppKit
import SMPKit

extension Sheets {
    // MARK: - データの編集

    /// データファイルの行をそのまま編集する(大きさを変えられるシート)
    struct EditDataView: View {
        let name: String
        let text: String
        let close: () -> Void
        let done: (String) -> Void
        @State private var handle = TextViewHandle()

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("データの編集")
                        .font(.headline)
                    Text(name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                DataTextEditor(text: text, handle: handle)
                    .frame(minWidth: 460, maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                HStack(spacing: 8) {
                    Spacer(minLength: 16)
                    CancelButton(close: close)
                    // 編集の欄では Return が改行になるので、保存は ⌘Return
                    Button {
                        save()
                    } label: {
                        Text("保存").frame(minWidth: 60)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("保存(⌘Return)")
                }
                .padding(20)
            }
        }

        private func save() {
            let result = handle.textView?.string ?? text
            close()
            done(result)
        }
    }

    /// 編集の欄の文字を保存のときに読むための口
    @MainActor
    final class TextViewHandle {
        weak var textView: NSTextView?
    }

    /// 等幅・折り返しなしの編集の欄(引用符やダッシュの自動置き換えをしない)
    struct DataTextEditor: NSViewRepresentable {
        var text: String
        var handle: TextViewHandle

        func makeNSView(context: Context) -> NSScrollView {
            let scroll = NSTextView.scrollableTextView()
            scroll.borderType = .bezelBorder
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true
            guard let tv = scroll.documentView as? NSTextView else { return scroll }
            tv.isRichText = false
            tv.importsGraphics = false
            tv.allowsUndo = true
            tv.usesFindBar = true
            tv.isIncrementalSearchingEnabled = true
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.isAutomaticLinkDetectionEnabled = false
            tv.isAutomaticDataDetectionEnabled = false
            tv.isContinuousSpellCheckingEnabled = false
            tv.isGrammarCheckingEnabled = false
            tv.smartInsertDeleteEnabled = false
            tv.textContainerInset = NSSize(width: 4, height: 6)
            // 折り返さずに横へ流す(列がそろって見えるように)
            let huge: CGFloat = 10_000_000
            tv.isHorizontallyResizable = true
            tv.maxSize = NSSize(width: huge, height: huge)
            tv.textContainer?.widthTracksTextView = false
            tv.textContainer?.containerSize = NSSize(width: huge, height: huge)
            tv.string = text
            tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            handle.textView = tv
            Task { @MainActor [handle] in
                if let tv = handle.textView { tv.window?.makeFirstResponder(tv) }
            }
            return scroll
        }

        func updateNSView(_ nsView: NSScrollView, context: Context) {}
    }

    // MARK: - 解析の結果

    struct ResultsView: View {
        let title: String
        let lines: [String]
        let close: () -> Void
        let insertAsText: () -> Void
        @State private var copied = false

        var body: some View {
            Scaffold(title: title, width: 480) {
                Group {
                    if lines.isEmpty {
                        Text("表示する結果がありません。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    } else {
                        ScrollView {
                            Text(lines.joined(separator: "\n"))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(maxHeight: 360)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            } leading: {
                Button("コピー") { copy() }
                    .disabled(lines.isEmpty)
                if copied {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                        .help("コピーしました")
                }
            } trailing: {
                Button("グラフに文字で入れる") {
                    insertAsText()
                    close()
                }
                .disabled(lines.isEmpty)
                DefaultButton(title: "閉じる") { close() }
                    .background(EscapeCatcher(close: close))
            }
        }

        private func copy() {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
            copied = true
        }
    }
}
