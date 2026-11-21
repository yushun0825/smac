import SwiftUI
import AppKit

/// 「SmaC ヘルプ」の窓(使い方・文字の書式・式・キーボード)
@MainActor
enum HelpWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "SmaC ヘルプ"
        panel.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: HelpView())
        host.sizingOptions = [.minSize]
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: 620, height: 680))
        panel.center()
        panel.setFrameAutosaveName("SmaCHelp")
        window = panel
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct HelpView: View {
    @State private var topic = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("項目", selection: $topic) {
                ForEach(HelpContent.topics.indices, id: \.self) { i in
                    Text(HelpContent.topics[i].title).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(HelpContent.topics[topic].blocks.indices, id: \.self) { i in
                        HelpBlockView(block: HelpContent.topics[topic].blocks[i])
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .id(topic)
        }
        .frame(minWidth: 460, minHeight: 360)
    }
}

private struct HelpBlockView: View {
    var block: HelpBlock

    var body: some View {
        switch block {
        case .heading(let s):
            Text(s)
                .font(.title3.weight(.semibold))
                .padding(.top, 10)
        case .text(let s):
            Text(s)
                .fixedSize(horizontal: false, vertical: true)
        case .items(let list):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(list.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(list[i]).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .table(let rows):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 7) {
                ForEach(rows.indices, id: \.self) { i in
                    GridRow {
                        Text(rows[i].key)
                            .font(.body.monospaced())
                            .gridColumnAlignment(.leading)
                        Text(rows[i].value)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }
}

private struct HelpRow: Sendable {
    var key: String
    var value: String
}

private enum HelpBlock: Sendable {
    case heading(String)
    case text(String)
    case items([String])
    case table([HelpRow])
}

private struct HelpTopic: Sendable {
    var title: String
    var blocks: [HelpBlock]
}

private func rows(_ pairs: [(String, String)]) -> HelpBlock {
    .table(pairs.map { HelpRow(key: $0.0, value: $0.1) })
}

private enum HelpContent {
    static let topics: [HelpTopic] = [basics, formatting, expressions, keyboard]

    static let basics = HelpTopic(title: "使い方", blocks: [
        .heading("グラフを開く"),
        .text("「ファイル」メニューの「開く…」(⌘O)で、SMP ファイルかデータファイルを選びます。"),
        .items([
            "SMP は SmaC のグラフの形式(.SMP)です。グラフ・データ・文字などが 1 つのファイルに入ります。",
            "データファイルは、数値が列に並んだテキスト(CSV・TXT・DAT など)です。開くと新しいグラフになります。",
            "開いているグラフにデータを加えるときは、「データ」メニューの「データを追加…」(⇧⌘D)を使います。",
        ]),
        .heading("画面の見方"),
        .items([
            "サイドバー: グラフ・データ・文字や図形の一覧です。選ぶと、その設定がインスペクタに表示されます。",
            "インスペクタ: 選んだものの設定です。数値の欄は、Return キーを押すか別の欄に移ると確定します。",
            "キャンバス: 用紙とグラフです。ダブルクリックすると、そのものの設定をインスペクタに表示します。",
        ]),
        .heading("キャンバスでの操作"),
        .items([
            "文字・矢印・枠・点・図は、ドラッグで動かせます。⇧ か ⌘ を押しながらクリックすると、複数を選べます。何もない所からドラッグすると、囲んだものをまとめて選べます。",
            "枠や図は、角をドラッグすると大きさが変わります。",
            "グラフの枠の辺や角をドラッグすると、グラフの大きさが変わります。枠の中や目盛りのあたりをドラッグすると、グラフ全体が動きます。",
            "副ボタン(右ボタン)でドラッグして範囲を囲むと、その範囲を図としてコピーしたり、PDF に書き出したり、拡大して表示したり、範囲の中の点を除いたりするメニューが表示されます。",
            "矢印キーで、選んだものを少しずつ動かせます(⌥ を押しながらで 0.1 mm、⇧ で 5 mm)。何も選んでいないときはグラフが動きます。",
            "ドラッグで動かすときの刻みは、「設定」の「描画と操作」で変えられます。",
        ]),
        .heading("解析"),
        .text("「解析」メニューから、最小二乗による当てはめ、スプライン補間、ピークの当てはめ、関数の描画ができます。求めた値は「結果を見る…」で表示し、グラフに文字として入れられます。条件は「条件を変える…」で変えられます。"),
        .heading("取り消しと保存"),
        .items([
            "変更は「編集」メニューの「取り消す」(⌘Z)で元に戻せます。",
            "「保存」(⌘S)で SMP として保存します。データをファイルに含めるかどうかは、「設定」の「保存」で選べます。",
        ]),
    ])

    static let formatting = HelpTopic(title: "文字の書式", blocks: [
        .text("グラフに入れる文字には、次の記号で書式を付けられます。インスペクタの「書式」メニューからも入れられます。"),
        .heading("上付き・下付き・改行"),
        rows([
            ("^…@", "上付き。例: x^2@ → x²"),
            ("_…@", "下付き。例: H_2@O → H₂O"),
            ("\\n", "改行"),
            ("\\文字", "次の 1 文字をそのまま表示する(例: \\^ で ^)"),
            ("%%", "% を表示する"),
        ]),
        .heading("書体と線"),
        rows([
            ("%R", "標準に戻す"),
            ("%I", "斜体"),
            ("%B", "太字"),
            ("%O", "太字の斜体"),
            ("%U…%U", "下線"),
            ("%L…%L", "上線"),
        ]),
        .heading("大きさと位置"),
        rows([
            ("%Sxyz", "大きさを xyz % にする(例: %S080 で 80 %)"),
            ("%X±xy", "横にずらす(文字の高さの xy %。例: %X+20)"),
            ("%Y±xy", "縦にずらす(例: %Y-10)"),
            ("%W???", "行の間隔を ??? × 0.1 mm にする"),
        ]),
        .heading("記号・色・フォント"),
        rows([
            ("%G…%A", "ギリシャ文字と記号(例: %Ga%A → α、%GD%A → Δ)"),
            ("%Q???", "番号 ???(10 進 3 桁)の文字(例: %Q176 → °)"),
            ("%K??????", "色を RRGGBB(16 進 6 桁)にする(例: %KFF0000 で赤)"),
            ("%J名前%J", "フォントを変える(例: %JArial%J)"),
        ]),
        .heading("データとファイルの情報"),
        .text("?? にはデータの番号(01、02 …)を 2 桁で書きます。"),
        rows([
            ("%??N", "データの名前(%??n は小文字で)"),
            ("%??E", "データのドットの見本"),
            ("%??F", "データの曲線の見本"),
            ("%H???", "見本の長さを ??? × 0.1 mm にする"),
            ("%??D", "データの日付"),
            ("%??T", "データの時刻"),
            ("%??Cxxyy", "データファイルの xx 行目・yy 列目の値(yy が 00 なら行全体)"),
            ("%N", "グラフのファイル名(%n は小文字で)"),
            ("%D  %T", "グラフのファイルの日付・時刻"),
            ("%M  %V", "今日の日付・今の時刻"),
        ]),
        .text("日付と時刻の記号を小文字にすると、日付は 2026/01/05 の形、時刻は時と分だけになります。凡例は %01E %01N のように、見本と名前を並べて作ります。"),
    ])

    static let expressions = HelpTopic(title: "式", blocks: [
        .text("データの変換、関数を描く、一般の関数で当てはめる、などの式は次のように書きます。"),
        .heading("使える名前"),
        rows([
            ("x  y", "そのデータの X・Y の値(変換する前の値)"),
            ("a 〜 i", "定数(「解析」メニューの「定数 a〜i…」で決めた値)。一般の関数で当てはめるときは a〜g がパラメータになります"),
            ("pi", "円周率(π とも書けます)"),
            ("#ffcc", "ff 番目のデータの cc 列目の値(ff が 00 なら、そのデータ自身)。例: #0003 は自分の 3 列目"),
        ]),
        .heading("演算"),
        rows([
            ("+  -  *  /", "足し算・引き算・掛け算・割り算(× と ÷ も使えます)"),
            ("^", "べき乗(** とも書けます)。例: x^2"),
            ("( )", "計算の順番を変える"),
        ]),
        .text("数は 1.5 や 2e-3 のように書きます。0 で割った値や負の数の平方根などは欠けた値になり、その点は描きません。"),
        .heading("関数"),
        rows([
            ("abs  sqrt  exp", "絶対値・平方根・指数関数"),
            ("ln  log", "自然対数・常用対数"),
            ("sin  cos  tan", "三角関数(角度はラジアン)"),
            ("asin  acos  atan", "逆三角関数"),
            ("sinh  cosh  tanh", "双曲線関数"),
            ("erf  erfc", "誤差関数・相補誤差関数"),
            ("gamma(x)", "ガンマ関数"),
            ("beta(p, q)", "ベータ関数"),
            ("theta(x)", "x ≥ 0 なら 1、それ以外は 0"),
            ("delta(x)", "x = 0 なら 1、それ以外は 0"),
            ("int(x)  sign(x)", "小数点以下の切り捨て・符号(−1、0、1)"),
            ("max(p, q)  min(p, q)", "大きいほう・小さいほう"),
            ("pow(p, q)", "p の q 乗"),
            ("atan2(y, x)  mod(p, q)", "偏角・余り"),
            ("dif(式)", "x で微分した値(隣の点との差から求めます)"),
            ("integ(式)", "最初の点から x で積分した値(台形の公式で求めます)"),
        ]),
        .heading("データファイルの書き方"),
        .items([
            "数値はカンマ・セミコロン・空白・タブで区切ります。",
            "# か % で始まる行は、コメントとして読み飛ばします。",
            "= と書いた欄は欠けた値として扱い、その点は描きません。",
            "| と書いた欄は飛ばして、後ろの列を前に詰めます。",
        ]),
    ])

    static let keyboard = HelpTopic(title: "キーボード", blocks: [
        .heading("ファイル"),
        rows([
            ("⌘N", "新規"),
            ("⌘O", "開く"),
            ("⌘S", "保存"),
            ("⇧⌘S", "別名で保存"),
            ("⌘W", "閉じる"),
            ("⌥⌘E", "PDF に書き出す"),
            ("⇧⌘P", "ページ設定"),
            ("⌘P", "プリント"),
        ]),
        .heading("編集"),
        rows([
            ("⌘Z", "取り消す"),
            ("⇧⌘Z", "やり直す"),
            ("⌘X  ⌘C  ⌘V", "カット・コピー・ペースト"),
            ("⌘A", "すべてを選択"),
            ("⌥⌘C", "図としてコピー"),
            ("⇧⌘F  ⇧⌘B", "最前面へ・最背面へ"),
            ("⌫", "選んだものを削除"),
        ]),
        .heading("表示"),
        rows([
            ("⌘+  ⌘-", "拡大・縮小"),
            ("⌘0", "実寸"),
            ("⌘9", "紙の大きさに合わせる"),
            ("⌘R", "データを読み直す"),
            ("⌃⌘S", "サイドバーを表示/隠す"),
            ("⌥⌘I", "インスペクタを表示/隠す"),
        ]),
        .heading("グラフとデータ"),
        rows([
            ("⌘T", "文字を入れる"),
            ("⌥⌘N", "グラフを加える"),
            ("⇧⌘R", "範囲を合わせる"),
            ("⇧⌘D", "データを追加"),
            ("⌘L", "値を読む"),
        ]),
        .heading("キャンバス"),
        rows([
            ("矢印キー", "選んだものを動かす(⌥ で 0.1 mm、⇧ で 5 mm)"),
            ("esc", "選択を外す・囲む操作をやめる"),
            ("⇧ / ⌘ + クリック", "選択に加える"),
            ("ダブルクリック", "設定をインスペクタに表示する"),
        ]),
        .heading("シート"),
        rows([
            ("Return", "OK"),
            ("esc", "キャンセル"),
            ("⌘Return", "データの編集を保存する"),
        ]),
        .heading("そのほか"),
        rows([
            ("⌘,", "設定"),
            ("⌘?", "SmaC ヘルプ"),
        ]),
    ])
}
