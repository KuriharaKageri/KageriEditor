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

    /// 全角・半角スペースを行単位で除去する（非整形とあわせて使う「スペース除去」）。
    /// ただしprotectLeadingIndent=trueの間は、行頭の全角スペース（段落の字下げ）を
    /// 設定に関わらず常に残す。「段落を区別しない」がオンのときはfalseを渡し、
    /// 行頭の字下げも他の全角スペースと同様に除去できるようにする。
    static func removeSpaces(
        _ text: String,
        removeFullWidth: Bool,
        removeHalfWidth: Bool,
        protectLeadingIndent: Bool = true
    ) -> String {
        guard removeFullWidth || removeHalfWidth else { return text }
        let lines = text.components(separatedBy: "\n")
        var outLines: [String] = []
        outLines.reserveCapacity(lines.count)
        for line in lines {
            guard !line.isEmpty else {
                outLines.append(line)
                continue
            }
            let chars = Array(line)
            let leadingFullWidthSpace = protectLeadingIndent && chars[0] == "\u{3000}"
            let startIndex = leadingFullWidthSpace ? 1 : 0
            var kept = leadingFullWidthSpace ? [chars[0]] : []
            for ch in chars[startIndex...] {
                if removeFullWidth && ch == "\u{3000}" { continue }
                if removeHalfWidth && ch == " " { continue }
                kept.append(ch)
            }
            outLines.append(String(kept))
        }
        return outLines.joined(separator: "\n")
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
