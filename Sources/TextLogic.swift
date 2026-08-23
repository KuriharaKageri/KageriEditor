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
        return isFullWidth(s) ? 1.0 : 0.5
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
    static func manuscriptLines(_ text: String, charsPerLine: Int = 20) -> Int {
        var lines = 0
        for line in text.components(separatedBy: "\n") {
            lines += max(1, Int((zenkakuCount(line) / Double(charsPerLine)).rounded(.up)))
        }
        return lines
    }

    /// 400字詰め原稿用紙の換算枚数。端数は小数第1位までで切り捨てるので、
    /// 「1枚」と表示されていれば本当に1枚分書けている。
    static func manuscriptSheets(_ text: String, charsPerLine: Int = 20, linesPerSheet: Int = 20) -> Double {
        let sheets = Double(manuscriptLines(text, charsPerLine: charsPerLine)) / Double(linesPerSheet)
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
    ]

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
            if i > 0 {
                let prevEmpty = lines[i - 1].isEmpty
                let keep: Bool
                if line.isEmpty || prevEmpty {
                    keep = true
                } else if recognizeParagraphs, let first = line.first, isParagraphHead(first) {
                    keep = true
                } else {
                    keep = false
                }
                if keep { out += "\n" }
            }
            out += line
        }
        return out
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
    private static func removeSpacesFromLine(
        _ line: String,
        removeFullWidth: Bool,
        removeHalfWidth: Bool,
        protectLeadingIndent: Bool
    ) -> String {
        guard !line.isEmpty else { return line }
        let chars = Array(line)
        let leadingFullWidthSpace = protectLeadingIndent && chars[0] == "\u{3000}"
        var kept: [Character] = leadingFullWidthSpace ? [chars[0]] : []
        kept.reserveCapacity(chars.count)
        for ch in chars[(leadingFullWidthSpace ? 1 : 0)...] {
            if removeFullWidth && ch == "\u{3000}" { continue }
            if removeHalfWidth && ch == " " { continue }
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
        var addLeadingIndent = false
        /// すべての改行の直後に空行を入れる（段落の間を1行あけてWeb記事向けに読みやすくする）
        var addBlankLines = false

        var hasAnyAction: Bool {
            removeHalfWidthSpace || removeFullWidthSpace || removeTab
                || digitsToHalfWidth || alphabet != .keep
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

        // ④ 行頭の字下げを追加。空行は対象外。会話文のカッコ・箇条書き記号・丸付き数字で
        //    始まる行と、すでに字下げ済みの行にも足さない（isParagraphHeadがすべて含む）
        if o.addLeadingIndent, let first = line.first, !isParagraphHead(first) {
            line = "\u{3000}" + line
        }
        return line
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
        for ch in text {
            if ch == "\n" {
                out.append(ch)
                acc = 0
                hangCount = 0
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
        let lines = text.components(separatedBy: "\n")
        let candidate = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
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
        // 制御文字を除去
        name = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        name = name.trimmingCharacters(in: .whitespaces)
        // 先頭のドットは不可視ファイルになるので取り除く
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "無題" }
        return name
    }
}
