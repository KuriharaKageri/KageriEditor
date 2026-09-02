import Foundation

/// 閲覧モードのMarkdownプレビュー。**どこをどう描くか**だけを算出し、本文には一切触れない。
///
/// ここは「見出しの印」（Outline/CharWidth.headingMarkLength）とは**別の判定**である。
/// 印は書き手が自分の原稿に打つ道具で、1〜2段だけを認め、目次・並べ替え・字数・ファイル名を動かす。
/// こちらは**よそから持ってきた文書を読むため**だけのもので、`###` 以上も普通に使われるので受け入れる。
/// 混ぜると、印の側の「宣言したものしか見出しにならない」という保証が壊れるため、必ず分けておくこと。
///
/// Android版のMarkdownPreview.ktと同じ規則の移植。インデックスはこのファイル内で完結する
/// Character配列基準で、ProofCheck.swiftと同じくNSRangeのlocationとしてそのまま使う。
enum MarkdownPreview {

    enum Kind {
        /// 見出し。levelに1〜6が入る
        case heading
        case bold
        case italic
        case boldItalic
        case strike
        /// 行中のコード（`…`）
        case code
        /// ``` で囲んだ中の行
        case codeBlock
        /// 引用。levelに入れ子の深さが入る
        case quote
        /// 箇条書き。levelに字下げの深さが入る
        case bullet
        /// 番号つき箇条書き。番号自体は意味を持つので隠さない
        case ordered
        /// 水平線（--- など）。文字は描かず線で表す
        case rule
        /// [文字](URL) の「文字」の部分
        case link
        /// 記法そのもの。見えなくする
        case hidden
    }

    /// [start, end) の範囲をkindとして描く、という指示
    struct Mark {
        let start: Int
        let end: Int
        let kind: Kind
        let level: Int
        init(_ start: Int, _ end: Int, _ kind: Kind, _ level: Int = 0) {
            self.start = start; self.end = end; self.kind = kind; self.level = level
        }
    }

    /// その文書が「よそから持ってきた読み物」かどうか。
    ///
    /// `# ` `## ` **だけ**なら、書き手が自分の原稿に打った見出しの印とみなす（原稿である）。
    /// それ以外の記法（`###` 以上・強調・箇条書き・引用・表・コードなど）が1つでもあれば、
    /// Markdownで書かれた読み物とみなす。閲覧モード中だけ字数・原稿用紙の枚数を隠すために使う。
    static func looksLikeForeignMarkdown(_ text: [Character], _ marks: [Mark]) -> Bool {
        let styled = marks.contains { m in
            switch m.kind {
            case .hidden: return false
            case .heading: return m.level >= 3
            default: return true
            }
        }
        if styled { return true }
        return hasTableRow(text)
    }

    /// 「| … | …」の形の行があるか（描画はしないが、読み物かどうかの判定には使う）
    private static func hasTableRow(_ text: [Character]) -> Bool {
        var lineStart = 0
        while lineStart <= text.count {
            let lineEnd = index(of: "\n", in: text, from: lineStart) ?? text.count
            var i = lineStart
            while i < lineEnd && text[i] == " " { i += 1 }
            if i < lineEnd, text[i] == "|", indexOf("|", text, i + 1, lineEnd) != nil {
                return true
            }
            if lineEnd == text.count { break }
            lineStart = lineEnd + 1
        }
        return false
    }

    private static func index(of c: Character, in text: [Character], from: Int) -> Int? {
        var i = from
        while i < text.count { if text[i] == c { return i }; i += 1 }
        return nil
    }

    /// 本文全体を走査して描画指示を組み立てる
    static func marks(_ text: [Character]) -> [Mark] {
        var out: [Mark] = []
        var lineStart = 0
        var inFence = false
        var fenceChar: Character = " "
        while lineStart <= text.count {
            let lineEnd = index(of: "\n", in: text, from: lineStart) ?? text.count

            if let fence = fenceRun(text, lineStart, lineEnd) {
                if !inFence {
                    inFence = true
                    fenceChar = fence
                    out.append(Mark(lineStart, lineEnd, .hidden))
                } else if fence == fenceChar {
                    inFence = false
                    out.append(Mark(lineStart, lineEnd, .hidden))
                } else {
                    out.append(Mark(lineStart, lineEnd, .codeBlock))
                }
            } else if inFence {
                out.append(Mark(lineStart, lineEnd, .codeBlock))
            } else {
                parseLine(text, lineStart, lineEnd, &out)
            }

            if lineEnd == text.count { break }
            lineStart = lineEnd + 1
        }
        return out
    }

    /// ``` または ~~~ で始まる囲みの行なら、その文字を返す
    private static func fenceRun(_ text: [Character], _ lineStart: Int, _ lineEnd: Int) -> Character? {
        var i = lineStart
        while i < lineEnd && text[i] == " " { i += 1 }
        guard i < lineEnd else { return nil }
        let c = text[i]
        guard c == "`" || c == "~" else { return nil }
        var run = 0
        while i + run < lineEnd && text[i + run] == c { run += 1 }
        return run >= 3 ? c : nil
    }

    /// 行頭の記法（見出し・引用・箇条書き・水平線）を見てから、残りを行中の記法にかける
    private static func parseLine(_ text: [Character], _ lineStart: Int, _ lineEnd: Int, _ out: inout [Mark]) {
        guard lineStart < lineEnd else { return }

        var i = lineStart
        var indent = 0
        while i < lineEnd && (text[i] == " " || text[i] == "\t") {
            indent += 1
            i += 1
        }
        guard i < lineEnd else { return }

        // 水平線（--- *** ___）。文字は描かず線にするので、中身は解釈しない
        if isRule(text, i, lineEnd) {
            out.append(Mark(lineStart, lineEnd, .rule))
            return
        }

        // 引用（> の入れ子）。剥がした残りは、その先の記法として続けて見る
        if text[i] == ">" {
            var depth = 0
            var j = i
            while j < lineEnd && text[j] == ">" {
                depth += 1
                j += 1
                if j < lineEnd && text[j] == " " { j += 1 }
            }
            out.append(Mark(lineStart, j, .hidden))
            out.append(Mark(lineStart, lineEnd, .quote, depth))
            if j < lineEnd { parseLine(text, j, lineEnd, &out) }
            return
        }

        // 見出し（# から ###### まで）。印の側と違い、6段まで受け入れる
        if text[i] == "#" {
            var run = 0
            while i + run < lineEnd && text[i + run] == "#" { run += 1 }
            if (1...6).contains(run), i + run < lineEnd, text[i + run] == " " {
                let contentStart = i + run + 1
                out.append(Mark(lineStart, contentStart, .hidden))
                out.append(Mark(contentStart, lineEnd, .heading, run))
                parseInline(text, contentStart, lineEnd, &out)
                return
            }
        }

        // 表（| で始まる行）には手を出さない。文字のまま見せる
        // （Android版と同じく、日本語混じりでは等幅にしても桁が揃わず、かえって読みにくいため見送り）

        // 箇条書き（- * +）。記号は隠して、字下げだけ付ける
        let c = text[i]
        if (c == "-" || c == "*" || c == "+"), i + 1 < lineEnd, text[i + 1] == " " {
            out.append(Mark(lineStart, i + 2, .hidden))
            out.append(Mark(lineStart, lineEnd, .bullet, indent / 2))
            parseInline(text, i + 2, lineEnd, &out)
            return
        }

        // 番号つき箇条書き（1. や 1) ）。番号は意味を持つので隠さず、字下げだけ付ける
        if c.isASCIIDigit {
            var j = i
            while j < lineEnd && text[j].isASCIIDigit { j += 1 }
            if j < lineEnd, (text[j] == "." || text[j] == ")"), j + 1 < lineEnd, text[j + 1] == " " {
                out.append(Mark(lineStart, lineEnd, .ordered, indent / 2))
                parseInline(text, j + 2, lineEnd, &out)
                return
            }
        }

        parseInline(text, i, lineEnd, &out)
    }

    /// --- *** ___ だけ（と空白）でできた行か
    private static func isRule(_ text: [Character], _ start: Int, _ end: Int) -> Bool {
        let c = text[start]
        guard c == "-" || c == "*" || c == "_" else { return false }
        var count = 0
        for k in start..<end {
            let ch = text[k]
            if ch == c { count += 1 } else if ch != " " { return false }
        }
        return count >= 3
    }

    // ---------- 行中の記法 ----------

    /// コード → 画像/リンク → 強調・打ち消し の順に見る（コードの中身を強調として解釈しないため）。
    /// **閉じ側が見つからない記号は、記法として扱わず文字のまま残す。**
    private static func parseInline(_ text: [Character], _ start: Int, _ end: Int, _ out: inout [Mark]) {
        var i = start
        while i < end {
            switch text[i] {
            case "`":
                if let close = indexOf("`", text, i + 1, end), close > i + 1 {
                    out.append(Mark(i, i + 1, .hidden))
                    out.append(Mark(i + 1, close, .code))
                    out.append(Mark(close, close + 1, .hidden))
                    i = close + 1
                    continue
                }
            case "!":
                // 画像。読むための表示なので絵は出せない。**説明文（代替文字）だけを残し、記法は消す**
                if i + 1 < end, text[i + 1] == "[" {
                    if let bracket = indexOf("]", text, i + 2, end), bracket + 1 < end, text[bracket + 1] == "(",
                       let paren = indexOf(")", text, bracket + 2, end) {
                        out.append(Mark(i, i + 2, .hidden))
                        parseInline(text, i + 2, bracket, &out)
                        out.append(Mark(bracket, paren + 1, .hidden))
                        i = paren + 1
                        continue
                    }
                }
            case "[":
                if let bracket = indexOf("]", text, i + 1, end), bracket + 1 < end, text[bracket + 1] == "(",
                   let paren = indexOf(")", text, bracket + 2, end) {
                    out.append(Mark(i, i + 1, .hidden))
                    out.append(Mark(i + 1, bracket, .link))
                    parseInline(text, i + 1, bracket, &out)
                    out.append(Mark(bracket, paren + 1, .hidden))
                    i = paren + 1
                    continue
                }
            case "~":
                let consumed = emphasis(text, i, start, end, "~", &out, strike: true)
                if consumed > 0 { i = consumed; continue }
            case "*", "_":
                let consumed = emphasis(text, i, start, end, text[i], &out, strike: false)
                if consumed > 0 { i = consumed; continue }
            default:
                break
            }
            i += 1
        }
    }

    /// 強調（* _）と打ち消し（~）。処理できたら次に見る位置を返し、できなければ0を返す。
    /// `_` は英単語の途中（snake_caseなど）では強調にしない
    private static func emphasis(
        _ text: [Character], _ at: Int, _ lineStart: Int, _ end: Int, _ d: Character,
        _ out: inout [Mark], strike: Bool
    ) -> Int {
        var run = 0
        while at + run < end && text[at + run] == d { run += 1 }
        let markerLen: Int
        if strike {
            guard run >= 2 else { return 0 }
            markerLen = 2
        } else {
            markerLen = run >= 3 ? 3 : run
        }
        guard markerLen > 0 else { return 0 }
        if d == "_", at > lineStart, isWordChar(text[at - 1]) { return 0 }

        guard let close = findClosingRun(text, at + markerLen, end, d, markerLen), close > at + markerLen else { return 0 }

        let kind: Kind = strike ? .strike : (markerLen >= 3 ? .boldItalic : (markerLen == 2 ? .bold : .italic))
        out.append(Mark(at, at + markerLen, .hidden))
        out.append(Mark(at + markerLen, close, kind))
        out.append(Mark(close, close + markerLen, .hidden))
        // 入れ子（**`code`** など）も描けるように、中身をもう一度見る
        parseInline(text, at + markerLen, close, &out)
        return close + markerLen
    }

    private static func findClosingRun(_ text: [Character], _ from: Int, _ end: Int, _ d: Character, _ len: Int) -> Int? {
        var j = from
        while j < end {
            if text[j] != d { j += 1; continue }
            var run = 0
            while j + run < end && text[j + run] == d { run += 1 }
            if run >= len {
                if d == "_", j + run < end, isWordChar(text[j + run]) {
                    j += run
                    continue
                }
                return j
            }
            j += run
        }
        return nil
    }

    private static func indexOf(_ c: Character, _ text: [Character], _ from: Int, _ end: Int) -> Int? {
        var k = from
        while k < end { if text[k] == c { return k }; k += 1 }
        return nil
    }

    private static func isWordChar(_ c: Character) -> Bool {
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c.isASCIIDigit
    }
}

private extension Character {
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
