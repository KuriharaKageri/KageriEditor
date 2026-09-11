import Foundation

// ============================================================
// 全角換算の文字幅計算
// 全角文字 = 1、半角文字 = 0.5 として数える
// ============================================================
enum CharWidth {
    /// Unicode上は半角（Neutral/Ambiguous）幅だが、日本語の文章内では
    /// 全角と同じ1文字として扱いたい記号（○◎●■□▲△▼▶◀★☆※→↑↓←↘↙↗↖♪♩♫♬×）。
    static let extraFullWidthScalars: Set<UInt32> = [
        0x25CB, 0x25CE, 0x25CF, 0x25A0, 0x25A1, // ○◎●■□
        0x25B2, 0x25B3, 0x25BC, 0x25B6, 0x25C0, // ▲△▼▶◀
        0x2605, 0x2606, // ★☆
        0x203B, // ※
        0x2192, 0x2191, 0x2193, 0x2190, // →↑↓←
        0x2198, 0x2199, 0x2197, 0x2196, // ↘↙↗↖
        0x266A, 0x2669, 0x266B, 0x266C, // ♪♩♫♬
        0x00D7, // ×
    ]

    /// 幅を持たない書式制御文字（ゼロ幅空白・単語結合子・BOMなど）。
    ///
    /// ウェブから貼ると混ざることがある。**目に見えず幅も持たないので0字**として数える
    /// （以前は半角1つぶんとして数えていて、字数が実際より多く出ていた）。
    /// カーソルの位置だけは1つ占めるので、見た目と操作が食い違う原因にもなる。
    static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00AD, 0xFEFF: return true          // ソフトハイフン、BOM
        case 0x200B...0x200F: return true         // ゼロ幅空白・接合子・方向指定
        case 0x202A...0x202E: return true         // 方向の埋め込み
        case 0x2060...0x206F: return true         // 単語結合子ほか
        case 0xFFF9...0xFFFB: return true         // ルビの区切り
        default: return false
        }
    }

    static func isFullWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,   // ハングル字母
             0x2E80...0x303E,   // CJK部首・約物・記号
             0x3041...0x33FF,   // ひらがな・カタカナ・CJK互換
             0x3400...0x4DBF,   // CJK拡張A
             0x4E00...0x9FFF,   // CJK統合漢字
             0xA000...0xA4CF,
             0xAC00...0xD7A3,   // ハングル音節
             0xF900...0xFAFF,   // CJK互換漢字
             0xFE30...0xFE4F,
             0xFF00...0xFF60,   // 全角英数・記号
             0xFFE0...0xFFE6,
             0x1B000...0x1B2FF, // 仮名補助
             0x20000...0x2FFFD, // CJK拡張B〜
             0x30000...0x3FFFD:
            return true
        default:
            return extraFullWidthScalars.contains(scalar.value)
        }
    }

    static func width(of ch: Character) -> Double {
        guard let s = ch.unicodeScalars.first else { return 0.5 }
        if isZeroWidth(s) { return 0.0 }
        return isFullWidth(s) ? 1.0 : 0.5
    }

    /// 全角換算の字数と、400字詰め原稿用紙の行数を**1回の走査で**まとめて求める。
    ///
    /// 以前は zenkakuCount と manuscriptSheets を別々に呼んでいたため、
    /// 打鍵のたびに全文を3回走査し、さらに manuscriptLines の
    /// components(separatedBy:) が全行を配列に確保していた。
    /// 34万字・540万字といった文書では、これだけで入力が追いつかなくなる。
    /// （Android版2.15の CharWidth.measure と同じ考え方）
    struct Metrics {
        let zenkaku: Double
        let manuscriptLines: Int
        /// 数から除いた見出しの印の文字数（excludeHeadingMarks が false のときは0）
        var marks: Int = 0
    }

    /// 行頭にある見出しの印の長さ。印でなければ0。
    ///
    /// 印は半角の「# 」「## 」の2段だけ。「###」以上は印ではない。
    /// 全角の「＃」も印にしない（印はボタンで入れるので、書き手が打ち分けに迷うことはない）。
    /// 印は原稿ではなく書き手の道具なので、字数・原稿用紙換算からは除く。
    static func headingMarkLength(_ chars: [Character], _ lineStart: Int) -> Int {
        guard lineStart < chars.count, chars[lineStart] == "#" else { return 0 }
        var i = lineStart + 1
        if i < chars.count, chars[i] == "#" { i += 1 }
        guard i < chars.count, chars[i] == " " else { return 0 }
        return i - lineStart + 1
    }

    static func measure(
        _ text: String, charsPerLine: Int = 20, excludeHeadingMarks: Bool = false
    ) -> Metrics {
        var total = 0.0
        var lineWidth = 0.0
        var lines = 0
        var marks = 0
        // 印は行頭にあるものだけが印なので、行の先頭かどうかを持ち回る。
        // 「#」を見た時点ではまだ印か分からないので、後ろの空白まで見てから決める
        var atLineStart = true
        var pendingHashes = 0
        let hashWidth = width(of: "#")

        func flushHashes() {
            guard pendingHashes > 0 else { return }
            let w = hashWidth * Double(pendingHashes)
            total += w
            lineWidth += w
            pendingHashes = 0
        }

        for ch in text {
            if excludeHeadingMarks {
                if atLineStart, ch == "#" {
                    pendingHashes = 1
                    atLineStart = false
                    continue
                }
                if pendingHashes == 1, ch == "#" {
                    pendingHashes = 2
                    continue
                }
                if pendingHashes > 0 {
                    if ch == " " {
                        marks += pendingHashes + 1
                        pendingHashes = 0
                        continue
                    }
                    flushHashes() // 印ではなかったので、ためていた「#」を数え直す
                }
                atLineStart = false
            }
            if ch == "\n" {
                // 段落の途中で改行すると行末の余白もマスを消費する（空行も1行）
                lines += max(1, Int((lineWidth / Double(charsPerLine)).rounded(.up)))
                lineWidth = 0
                atLineStart = true
                continue
            }
            if ch == "\r" { continue }
            let w = width(of: ch)
            total += w
            lineWidth += w
        }
        flushHashes()
        lines += max(1, Int((lineWidth / Double(charsPerLine)).rounded(.up))) // 最後の行
        return Metrics(zenkaku: total, manuscriptLines: lines, marks: marks)
    }

    /// 改行を除いた全角換算の文字数
    static func zenkakuCount(_ text: String) -> Double {
        var total = 0.0
        for ch in text {
            if ch == "\n" || ch == "\r" || ch == "\r\n" { continue }
            total += width(of: ch)
        }
        return total
    }

    /// 400字詰め原稿用紙（20字×20行）に換算した行数。
    /// 出版の慣例にならい、段落の途中で改行すると行末の余白もマスとして消費する
    /// （1段落は20字ごとに1行を使い、空行も1行として数える）。
    /// measure に通す（以前は components(separatedBy:) で全行を配列に確保していた）
    static func manuscriptLines(
        _ text: String, charsPerLine: Int = 20, excludeHeadingMarks: Bool = false
    ) -> Int {
        measure(text, charsPerLine: charsPerLine, excludeHeadingMarks: excludeHeadingMarks)
            .manuscriptLines
    }

    /// 400字詰め原稿用紙の換算枚数。端数は小数第1位までで切り捨てるので、
    /// 「1枚」と表示されていれば本当に1枚分書けている。
    static func manuscriptSheets(
        _ text: String, charsPerLine: Int = 20, linesPerSheet: Int = 20,
        excludeHeadingMarks: Bool = false
    ) -> Double {
        let lines = manuscriptLines(
            text, charsPerLine: charsPerLine, excludeHeadingMarks: excludeHeadingMarks)
        let sheets = Double(lines) / Double(linesPerSheet)
        return (sheets * 10).rounded(.down) / 10
    }
}

// ============================================================
// テキスト変換コマンド（非整形＝改行除去・整形＝指定文字数で改行）
// ============================================================
enum TextTransform {

    /// 行頭にあると「段落の先頭」とみなす文字（全角スペース・括弧類・箇条書き記号）
    static let paragraphHeads: Set<Character> = [
        "\u{3000}", // 全角スペース
        "「", "」", "『", "』", "（", "）", "(", ")",
        "【", "】", "〈", "〉", "《", "》", "〔", "〕",
        "［", "］", "[", "]", "｛", "｝", "{", "}",
        "〝", "〟", "“", "”", "‘", "’", "\"", "'", "＂", "＇",
        "・", "･", "●", "○", "◎", "■", "□", "◆", "◇",
        // 箇条書き・注記の印。行頭に置かれたものは本文であって見出しではない
        "*", "＊", "※", "-", "－",
        // ダッシュ。会話や強調で段落の先頭に置かれる
        "―", "—", "–",
        "#", // 見出しの印
    ]

    /// 日本語（ひらがな・カタカナ・漢字）が1文字でも入っている行か。
    ///
    /// 一字下げは日本語の段落の作法なので、英文の行には足さない。
    /// **「行頭が英字か」ではなく「行に日本語があるか」で見る。**
    /// そうしないと「iPadは便利だ」のように英単語で始まる日本語の段落まで
    /// 字下げされなくなる。
    static func containsJapanese(_ line: String) -> Bool {
        line.unicodeScalars.contains { u in
            switch u.value {
            case 0x3041...0x309F: return true   // ひらがな
            case 0x30A0...0x30FF: return true   // カタカナ
            case 0x4E00...0x9FFF: return true   // 漢字
            case 0x3400...0x4DBF: return true   // 漢字（拡張A）
            case 0x3005: return true            // 々
            case 0xFF66...0xFF9D: return true   // 半角カタカナ
            default: return false
            }
        }
    }

    /// 見出しの印（「# 」「## 」）で始まる行かどうか。
    /// 整形・非整形は、この行に手を触れない
    static func isHeadingLine(_ line: String) -> Bool {
        let chars = Array(line.prefix(3))
        return CharWidth.headingMarkLength(chars, 0) > 0
    }

    /// 行頭にあると「段落の先頭」とみなす文字かどうか。
    /// 上記の集合に加えて、①②…㊿ などの丸付き数字類も対象。
    static func isParagraphHead(_ ch: Character) -> Bool {
        if paragraphHeads.contains(ch) { return true }
        guard let value = ch.unicodeScalars.first?.value else { return false }
        switch value {
        case 0x2460...0x24FF, // ①〜⑳・⒈・⑴・Ⓐ など（囲み英数字）
             0x3251...0x325F, // ㉑〜㉟
             0x32B1...0x32BF, // ㊱〜㊿
             0x2776...0x2793: // ❶〜❿・➀〜➓ など
            return true
        default:
            return false
        }
    }

    /// 改行を除去する。ただし次の行の行頭が全角スペース・括弧類・
    /// 箇条書き記号（丸付き数字を含む）の場合は段落とみなして
    /// 直前の改行を残す。空行も段落区切りとして残す。
    ///
    /// recognizeParagraphs=false（設定「段落を区別しない」）の場合は、
    /// 記号による段落認識（isParagraphHead）を行わず、空行だけを
    /// 段落区切りとして残す。
    static func removeNewlines(_ text: String, recognizeParagraphs: Bool = true) -> String {
        let lines = text.components(separatedBy: "\n")
        var out = ""
        for i in lines.indices {
            let line = lines[i]
            if i > 0,
               keepsNewline(between: lines[i - 1], and: line,
                            recognizeParagraphs: recognizeParagraphs) {
                out += "\n"
            }
            out += line
        }
        return out
    }

    /// 非整形が、この2行の間の改行を残すかどうか。**段落の切れ目の判定そのもの**なので、
    /// 「カーソルのある段落だけを非整形する」ときの範囲決めからも同じ規則で呼ぶ。
    /// ふつうの改行は切れ目にならない。切れ目になるのは次のどれか。
    /// ・空行（空白だけの行も書き手には空行に見えるので同じ扱い）
    /// ・見出し行の前後（行頭の記号だけ見ていると見出しの「後ろ」を守れない）
    /// ・段落の印で始まる行（一字下げ・括弧・箇条書き記号・丸付き数字など）。
    /// 　ただし recognizeParagraphs が false のときはこの判定をしない
    static func keepsNewline(between prev: String, and line: String,
                             recognizeParagraphs: Bool) -> Bool {
        if line.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if prev.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if isHeadingLine(line) || isHeadingLine(prev) { return true }
        if recognizeParagraphs, let first = line.first, isParagraphHead(first) { return true }
        return false
    }

    /// 全角・半角スペースを行単位で除去する（原稿支援の除去処理の中核）。
    /// ただし行頭の全角スペース（段落の字下げ）はprotectLeadingIndent=trueの間は
    /// 設定に関わらず常に残す。「行頭の字下げも除去する」がオンのときはfalseを渡し、
    /// 行頭の字下げも他の全角スペースと同様に除去できるようにする。
    static func removeSpaces(
        _ text: String,
        removeFullWidth: Bool,
        removeHalfWidth: Bool,
        protectLeadingIndent: Bool = true
    ) -> String {
        guard removeFullWidth || removeHalfWidth else { return text }
        return text.components(separatedBy: "\n").map {
            removeSpacesFromLine($0,
                                 removeFullWidth: removeFullWidth,
                                 removeHalfWidth: removeHalfWidth,
                                 protectLeadingIndent: protectLeadingIndent)
        }.joined(separator: "\n")
    }

    /// removeSpacesの1行ぶん。原稿支援（assist）からも使う
    /// 半角スペースと同じ扱いにする見えない空白。
    /// ウェブから貼ると混ざるが、見た目は空白なのに `U+0020` ではないので
    /// 「半角スペースを除去」で消えず、書き手には**消せない空白**に見える。
    /// 半角の英数字・記号（空白を除く印字可能なASCII）。
    /// 英文の中の空白を守るために、半角スペースの前後を見るのに使う。
    private static func isAsciiVisible(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1 else {
            return false
        }
        return (0x21...0x7E).contains(v)
    }

    private static func isInvisibleSpace(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return false }
        switch v {
        case 0x00A0: return true            // 改行しない空白
        case 0x2000...0x200A: return true   // 各種の幅の空白
        case 0x202F, 0x205F: return true    // 狭い改行しない空白、数式用の空白
        default: return false
        }
    }

    private static func removeSpacesFromLine(
        _ line: String,
        removeFullWidth: Bool,
        removeHalfWidth: Bool,
        protectLeadingIndent: Bool
    ) -> String {
        guard !line.isEmpty else { return line }
        let chars = Array(line)
        // **見出しの印は除去の対象にしない。**「# 」の後ろは半角スペースなので、
        // 「半角スペースを除去」で一緒に消えると印が壊れ、目次も並べ替えも失われる。
        // 印は原稿ではなく書き手の道具なので、原稿の体裁を整える処理は触らない
        let markLen = CharWidth.headingMarkLength(chars, 0)
        let leadingFullWidthSpace =
            markLen == 0 && protectLeadingIndent && chars[0] == "\u{3000}"
        var kept: [Character] = markLen > 0
            ? Array(chars[0..<markLen])
            : (leadingFullWidthSpace ? [chars[0]] : [])
        kept.reserveCapacity(chars.count)
        for index in max(markLen, leadingFullWidthSpace ? 1 : 0)..<chars.count {
            let ch = chars[index]
            if removeFullWidth && ch == "\u{3000}" { continue }
            if removeHalfWidth {
                // **英文の中の空白は残す。**
                // この項目を使うのは、OCRやウェブから来た日本語に混じった
                // 余分な空白を掃除するため。英単語の「間」を詰めたい場面は無い。
                // 前後がどちらも半角の英数字・記号なら英文の一部とみなす
                // （「rule of law」は残り、「ICC の判断」は消える）
                if ch == " " {
                    let prev = index > 0 ? chars[index - 1] : "\n"
                    let next = index + 1 < chars.count ? chars[index + 1] : "\n"
                    if isAsciiVisible(prev) && isAsciiVisible(next) { kept.append(ch) }
                    continue
                }
                // 見えない空白と幅ゼロの文字も、半角スペースと一緒に消す。
                // 書き手が意図して入れることはまずなく、放っておくと消せない
                if isInvisibleSpace(ch) { continue }
                if let v = ch.unicodeScalars.first, CharWidth.isZeroWidth(v) { continue }
            }
            kept.append(ch)
        }
        return String(kept)
    }

    // ---------- 原稿支援 ----------

    /// 原稿支援のアルファベット変換
    enum AlphabetMode {
        case keep, fullWidth, halfWidth
    }

    /// 原稿支援（ダイアログで選んだ内容を1回でまとめて適用する）の設定。
    /// 何も選ばれていなければ何もしない。
    struct AssistOptions {
        var removeHalfWidthSpace = false
        var removeFullWidthSpace = false
        var removeTab = false
        /// 行頭の全角スペース（一字下げ）も除去するか。falseなら字下げは残す
        var removeLeadingIndent = false
        var digitsToHalfWidth = false
        var alphabet: AlphabetMode = .keep
        /// 単位（km・L など）だけを半角にする。
        /// アルファベットを一律に変換すると「単語は全角・単位は半角」という
        /// 使い分けができないので、単位だけを狙えるように分けている
        var unitsToHalfWidth = false
        var addLeadingIndent = false
        /// すべての改行の直後に空行を入れる（段落の間を1行あけてWeb記事向けに読みやすくする）
        var addBlankLines = false

        var hasAnyAction: Bool {
            removeHalfWidthSpace || removeFullWidthSpace || removeTab
                || digitsToHalfWidth || alphabet != .keep || unitsToHalfWidth
                || addLeadingIndent || addBlankLines
        }
    }

    /// 原稿支援。除去 → 文字種の変換 → 追加 の順に、1回の走査でまとめて適用する。
    /// この順序には意味があり、「行頭スペースをいったん除去してから規則正しく付け直す」
    /// というバラバラの字下げを整える手順が、そのまま1回の実行で行える。
    static func assist(_ text: String, options: AssistOptions) -> String {
        guard options.hasAnyAction else { return text }
        var result = text.components(separatedBy: "\n")
            .map { assistLine($0, options) }
            .joined(separator: "\n")
        // 空行の挿入だけは行単位ではなく全体に対して行う（行を増やす処理のため）。
        // 一字下げや会話文かどうかは見ずに、すべての改行の直後へ機械的に1行入れる。
        // 段落の判定に頼ると、一字下げをしないWeb向けの文章や「で始まる会話文で
        // 効いたり効かなかったりするため、結果が読める単純な規則にしている
        if options.addBlankLines {
            result = result.replacingOccurrences(of: "\n", with: "\n\n")
        }
        return result
    }

    private static func assistLine(_ raw: String, _ o: AssistOptions) -> String {
        // ⓪ 空白だけの行は、行頭の字下げを残す設定でも丸ごと空にする。
        //    そうしないと「行頭の全角スペース＝段落の字下げ」とみなされて1つだけ残り、
        //    見た目は空行なのに空行ではない、という行ができてしまう
        //    （空行除去でも消えず、非整形でも段落の先頭と誤認される）。
        //    もともと文字が無い行なので、どの空白を残すかを選ぶ意味がない
        if !raw.isEmpty, raw.allSatisfy({ $0 == " " || $0 == "\u{3000}" || $0 == "\t" }) {
            let removingAnySpace = o.removeHalfWidthSpace || o.removeFullWidthSpace || o.removeTab
            return removingAnySpace ? "" : raw
        }

        var line = raw

        // ① タブ。行頭のタブは字下げのつもりで入っていることが多いので全角スペース1つに
        //    変換し、行中のタブは取り除く（変換後の全角スペースは、このあとの②で
        //    「行頭の字下げも除去する」が選ばれていれば一緒に消える）
        if o.removeTab && line.contains("\t") {
            let leadingTabs = line.prefix(while: { $0 == "\t" }).count
            let rest = String(line.dropFirst(leadingTabs))
                .replacingOccurrences(of: "\t", with: "")
            line = leadingTabs > 0 ? "\u{3000}" + rest : rest
        }

        // ② スペースの除去
        if o.removeHalfWidthSpace || o.removeFullWidthSpace {
            line = removeSpacesFromLine(line,
                                        removeFullWidth: o.removeFullWidthSpace,
                                        removeHalfWidth: o.removeHalfWidthSpace,
                                        protectLeadingIndent: !o.removeLeadingIndent)
        }

        // ③ 文字種の変換（全角と半角は0xFEE0だけ離れている）
        if o.digitsToHalfWidth || o.alphabet != .keep {
            line = String(line.map { convertWidth($0, o) })
        }

        // ③\' 単位だけを半角に。アルファベットの一律変換のあとに行うので、
        //     「アルファベットを全角に」と同時に選んでも単位は半角のまま残る
        if o.unitsToHalfWidth { line = unitsToHalfWidth(line) }

        // ④ 行頭の字下げを追加。空行は対象外。会話文のカッコ・箇条書き記号・丸付き数字で
        //    始まる行と、すでに字下げ済みの行にも足さない（isParagraphHeadがすべて含む）。
        //    **英文の行にも足さない**（一字下げは日本語の段落の作法なので）
        if o.addLeadingIndent, let first = line.first, !isParagraphHead(first),
           containsJapanese(line) {
            line = "\u{3000}" + line
        }
        return line
    }

    /// 数字のすぐ後ろに来た単位（ｋｍ→km、Ｌ→L）だけを半角にする。
    /// 「km/h」のように単位が斜線でつながる場合も、斜線の後ろを単位とみなす。
    /// アルファベットを一律に変換しないので、「単語は全角・単位は半角」という
    /// 媒体の決まりに合わせられる
    static func unitsToHalfWidth(_ line: String) -> String {
        let chars = Array(line)
        var out = ""
        var i = 0
        while i < chars.count {
            if let range = Units.unitRange(chars, at: i) {
                out += Units.toHalfWidth(String(chars[range]))
                i = range.upperBound
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }

    /// 数字・アルファベットの全角／半角を1文字ぶん変換する
    private static func convertWidth(_ ch: Character, _ o: AssistOptions) -> Character {
        guard ch.unicodeScalars.count == 1, let value = ch.unicodeScalars.first?.value else { return ch }
        if o.digitsToHalfWidth, (0xFF10...0xFF19).contains(value) {
            return shifted(ch, by: -0xFEE0)
        }
        switch o.alphabet {
        case .halfWidth:
            if (0xFF21...0xFF3A).contains(value) || (0xFF41...0xFF5A).contains(value) {
                return shifted(ch, by: -0xFEE0)
            }
        case .fullWidth:
            if (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) {
                return shifted(ch, by: 0xFEE0)
            }
        case .keep:
            break
        }
        return ch
    }

    private static func shifted(_ ch: Character, by delta: Int) -> Character {
        guard let value = ch.unicodeScalars.first?.value,
              let scalar = Unicode.Scalar(UInt32(Int(value) + delta)) else { return ch }
        return Character(scalar)
    }

    /// 行頭に来ると読みにくい（行頭禁則）文字。整形（wrap）で改行を
    /// 入れる際、これらの文字が行頭に来る場合は前の行の末尾に
    /// 追い出す（ぶら下げる）。句読点・ピリオド・カンマ・各種閉じ括弧・
    /// 小書き文字（拗促音）・長音符・繰り返し記号が対象。
    static let lineStartProhibited: Set<Character> = [
        "、", "。", ".", ",", "．", "，",
        "」", "』", "）", ")", "】", "〉", "》", "〕", "］", "]", "｝", "}", "〟", "”", "’",
        "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "っ", "ゃ", "ゅ", "ょ", "ゎ",
        "ァ", "ィ", "ゥ", "ェ", "ォ", "ッ", "ャ", "ュ", "ョ", "ヮ", "ヵ", "ヶ",
        "ー", "ゝ", "ゞ", "々", "〻",
    ]

    /// 改行のみの行（空行）を段階的に削除する。連続する空行は1回につき1行だけ減らすので、
    /// 3行あけ→2行あけ→1行あけ→詰める、と実行するたびに1段階ずつ詰まっていく。
    /// 空行が1行だけの箇所は1回で消える。
    static func removeBlankLinesStep(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var i = 0
        while i < lines.count {
            if lines[i].isEmpty {
                var runEnd = i
                while runEnd < lines.count && lines[runEnd].isEmpty { runEnd += 1 }
                // 連続数から1行だけ減らして書き戻す
                out.append(contentsOf: Array(repeating: "", count: runEnd - i - 1))
                i = runEnd
            } else {
                out.append(lines[i])
                i += 1
            }
        }
        return out.joined(separator: "\n")
    }

    /// 全角換算で limit 文字を超えないように改行を挿入する。
    /// 呼び出し側が常に行頭から始まる範囲を渡す前提なので、字数は
    /// 渡された文字列の先頭（＝行頭）から数える。
    /// 行頭禁則文字（lineStartProhibited）が行頭に来る場合は前の行に
    /// ぶら下げる。ぶら下げが2文字連続した場合は、3文字目以降は
    /// 禁則を無視して強制的に改行する（無限にぶら下げ続けない）。
    static func wrap(_ text: String, limit: Double) -> String {
        guard limit > 0 else { return text }
        var out = ""
        var acc = 0.0
        var hangCount = 0
        // 見出し行はそのまま出す。折り返すと後半が独立した行になり、
        // 見出しが切れて本文が1行増えてしまう
        var atLineStart = true
        var hashRun = 0
        var inHeading = false
        for ch in text {
            if ch == "\n" {
                out.append(ch)
                acc = 0
                hangCount = 0
                atLineStart = true
                hashRun = 0
                inHeading = false
                continue
            }
            if atLineStart {
                atLineStart = false
                hashRun = ch == "#" ? 1 : 0
            } else if hashRun >= 1, ch == "#", hashRun < 2 {
                hashRun = 2
            } else if hashRun >= 1, ch == " " {
                inHeading = true
                hashRun = 0
            } else {
                hashRun = 0
            }
            if inHeading {
                out.append(ch)
                continue
            }
            let w = CharWidth.width(of: ch)
            if acc > 0 && acc + w > limit {
                if lineStartProhibited.contains(ch) && hangCount < 2 {
                    hangCount += 1
                } else {
                    out.append("\n")
                    acc = 0
                    hangCount = 0
                }
            }
            out.append(ch)
            acc += w
        }
        return out
    }

    // --------------------------------------------------------
    // 変換コマンドが対象にする範囲
    // --------------------------------------------------------

    /// 何も選択されていないとき、変換コマンドが何を対象にするか。
    enum NoSelectionScope {
        /// 文書全体（非整形・空行除去・原稿支援・見出しの印を外す）
        case wholeDocument
        /// カーソルのある論理行だけ（整形）。
        /// 「論理行」は画面上の折り返しではなく、行頭から改行までのひとまとまり
        case currentLine
        /// カーソルのある段落だけ（非整形）。
        /// 段落の切れ目は [keepsNewline] が決める＝非整形が改行を残す場所と同じ。
        /// ふつうの改行では切れないので、細切れの改行は1つの段落にまとまる
        case currentParagraph
    }

    /// 変換の前後で、カーソルを「同じ文字」のところに保つための位置の対応づけ。
    ///
    /// 整形は改行を足すだけ、非整形は改行を取るだけで、どちらも他の文字は動かさない。
    /// そこで2つの文字列を先頭から突き合わせ、増えた改行ぶんは進め、減った改行ぶんは
    /// 飛ばす。offset は変換前の位置で、返り値は変換後の位置。
    static func mappedCaret(from target: NSString, to replaced: NSString, offset: Int) -> Int {
        let limit = max(0, min(offset, target.length))
        var t = 0
        var r = 0
        while t < limit {
            if r < replaced.length, replaced.character(at: r) == target.character(at: t) {
                t += 1
                r += 1
            } else if r < replaced.length, replaced.character(at: r) == 0x0A {
                r += 1                                  // 整形が足した改行
            } else if target.character(at: t) == 0x0A {
                t += 1                                  // 非整形が取った改行
            } else {
                // 改行以外が変わる変換（原稿支援など）は想定していない。
                // ずれを最小にするため同じだけ進める
                t += 1
                if r < replaced.length { r += 1 }
            }
        }
        return r
    }

    /// 変換コマンド（整形・非整形・空行除去・原稿支援）が実際に書き換える範囲を決める。
    ///
    /// 選択があるときは、行の途中から始まっていても・途中で終わっていても、
    /// その行全体を選んだものとみなして行単位に広げる。
    /// 選択がないときは scope に従う。
    /// recognizeParagraphs は currentParagraph のときだけ意味を持ち、
    /// 設定「非整形で段落を区別しない」を裏返した値（＝非整形へ渡すものと同じ）を受け取る。
    static func targetRange(in text: NSString,
                            selection: NSRange,
                            noSelectionScope: NoSelectionScope,
                            recognizeParagraphs: Bool = true) -> NSRange {
        guard selection.length > 0 else {
            switch noSelectionScope {
            case .wholeDocument:
                return NSRange(location: 0, length: text.length)
            case .currentLine:
                let caret = min(selection.location, text.length)
                var line = text.lineRange(for: NSRange(location: caret, length: 0))
                // その行をそっくり選んで実行したときと同じ範囲になるよう、行末の改行は含めない
                while line.length > 0 {
                    let last = text.character(at: NSMaxRange(line) - 1)
                    guard last == 0x0A || last == 0x0D else { break }
                    line.length -= 1
                }
                return line
            case .currentParagraph:
                return paragraphRange(in: text,
                                      caret: min(selection.location, text.length),
                                      recognizeParagraphs: recognizeParagraphs)
            }
        }
        var range = selection
        // 行の途中から始まる選択は行頭まで広げる
        let lineStart = text.lineRange(for: NSRange(location: range.location, length: 0)).location
        if lineStart < range.location {
            range.length += range.location - lineStart
            range.location = lineStart
        }
        // 行の途中で終わる選択は行末まで広げる
        let end = NSMaxRange(range)
        if end < text.length, end > 0, text.character(at: end - 1) != 0x0A {
            let lineRange = text.lineRange(for: NSRange(location: end, length: 0))
            var lineEnd = NSMaxRange(lineRange)
            if lineEnd > 0 && text.character(at: lineEnd - 1) == 0x0A { lineEnd -= 1 }
            if lineEnd > end { range.length = lineEnd - range.location }
        }
        return range
    }

    /// カーソルのある段落（＝非整形が改行を残す切れ目に挟まれたひとまとまり）の範囲。
    /// 行末の改行は含めない。空行や見出しの上にカーソルがあるときは、その1行だけになる。
    private static func paragraphRange(in text: NSString,
                                       caret: Int,
                                       recognizeParagraphs: Bool) -> NSRange {
        let lines = text.components(separatedBy: "\n")
        var starts = [Int](repeating: 0, count: lines.count)
        var pos = 0
        for i in lines.indices {
            starts[i] = pos
            pos += (lines[i] as NSString).length + 1     // +1 は行末の改行ぶん
        }
        // カーソルのある行。改行の上にカーソルがあるときは、その改行の手前の行とみなす
        var index = 0
        for i in lines.indices where starts[i] <= caret { index = i }
        var first = index
        var last = index
        while first > 0,
              !keepsNewline(between: lines[first - 1], and: lines[first],
                            recognizeParagraphs: recognizeParagraphs) {
            first -= 1
        }
        while last < lines.count - 1,
              !keepsNewline(between: lines[last], and: lines[last + 1],
                            recognizeParagraphs: recognizeParagraphs) {
            last += 1
        }
        let start = starts[first]
        let end = starts[last] + (lines[last] as NSString).length
        return NSRange(location: start, length: end - start)
    }
}


// ============================================================
// 原稿支援のプリセット（Android版2.31と同じ考え方）
// ============================================================

/// 原稿支援ダイアログの8項目のチェック状態に名前を付けて保存したもの
struct AssistPreset: Codable, Equatable {
    var name: String
    var removeHalf: Bool
    var removeFull: Bool
    var removeTab: Bool
    var removeIndent: Bool
    var digits: Bool
    var units: Bool
    var addIndent: Bool
    var addBlank: Bool
    /// "keep" / "full" / "half"
    var alphabet: String
}

/// プリセットの読み書き。JSON文字列としてprefsに1本で持つ（Android版のassistPresetsと同じ形）。
/// エンコード・デコードはUserDefaultsから切り離した純粋関数にして単体テストできるようにしている
enum AssistPresetStore {
    static func encode(_ presets: [AssistPreset]) -> String {
        guard let data = try? JSONEncoder().encode(presets),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    static func decode(_ json: String?) -> [AssistPreset] {
        guard let json, let data = json.data(using: .utf8),
              let presets = try? JSONDecoder().decode([AssistPreset].self, from: data) else { return [] }
        return presets
    }

    /// 同名があれば上書き、無ければ末尾に追加した配列を返す（保存側の呼び出し元でJSON化する）
    static func upserted(_ presets: [AssistPreset], with preset: AssistPreset) -> [AssistPreset] {
        var result = presets
        if let index = result.firstIndex(where: { $0.name == preset.name }) {
            result[index] = preset
        } else {
            result.append(preset)
        }
        return result
    }

    static func removed(_ presets: [AssistPreset], name: String) -> [AssistPreset] {
        presets.filter { $0.name != name }
    }
}

// ============================================================
// 1行目からのファイル名生成
// ============================================================
enum FileNaming {

    /// 本文の中で最初に文字がある行から、全角換算で maxZenkaku 文字までを
    /// 取り出してファイル名（拡張子なし）を作る。冒頭が改行のみ（空行や
    /// 空白だけの行）の場合は、それらを読み飛ばして最初に文字がある行を
    /// 使う。文字がある行が一つもなければ「無題」。
    static func fileName(fromFirstLineOf text: String, maxZenkaku: Double = 20) -> String {
        // 見出しの印は原稿ではないので、ファイル名にも入れない。
        // 印を外した中身が空の行（「# 」まで打った行）は飛ばして次の行を見る
        let candidate = text.components(separatedBy: "\n").lazy
            .map { line -> String in
                let chars = Array(line)
                return String(chars.dropFirst(CharWidth.headingMarkLength(chars, 0)))
            }
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        var name = ""
        var acc = 0.0
        for ch in candidate {
            if ch == "\r" { break }
            let w = CharWidth.width(of: ch)
            if acc + w > maxZenkaku { break }
            name.append(ch)
            acc += w
        }
        // ファイル名に使えない・不向きな文字を全角に置き換える
        name = name
            .replacingOccurrences(of: "/", with: "／")
            .replacingOccurrences(of: ":", with: "：")
            // 「#」はURLの断片の区切りなので、ファイルの場所を表す文字列に混ざると
            // そこから後ろを切り落とされる。ファイル名には入れない
            .replacingOccurrences(of: "#", with: "＃")
        // 制御文字を除去
        name = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        name = name.trimmingCharacters(in: .whitespaces)
        // 先頭のドットは不可視ファイルになるので取り除く
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "無題" }
        return name
    }

    /// 新しく作る文書は必ずこの拡張子（原則）
    static let defaultExtension = "txt"
    /// ピッカー・ファイル名変更で明示的に指定できる拡張子
    static let knownExtensions: Set<String> = ["txt", "md"]

    /// ファイル名変更で入力された文字列から、拡張子込みで書かれていれば
    /// それを解釈する。既知の拡張子（txt/md）ならその拡張子を切り出し、
    /// 知らない拡張子（や拡張子なし）は全体を題名の一部とみなしてfallbackを補う
    /// （「第3章.決意」→「第3章.決意.txt」のようになる。Android版と同じ規則）
    static func withExtension(typed: String, fallback: String = defaultExtension) -> (base: String, ext: String) {
        guard let dot = typed.lastIndex(of: "."), typed.index(after: dot) < typed.endIndex else {
            return (typed, fallback)
        }
        let base = String(typed[typed.startIndex..<dot])
        let ext = String(typed[typed.index(after: dot)...]).lowercased()
        guard !base.isEmpty, knownExtensions.contains(ext) else {
            return (typed, fallback)
        }
        return (base, ext)
    }
}
