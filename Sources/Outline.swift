import Foundation

// ============================================================
// 単位（半角で書くのが一般的なもの）
// ============================================================
/// 数字のすぐ後ろに来たときだけ単位とみなす。
/// 「単語は全角・単位は半角」と使い分ける媒体があるため、アルファベットを
/// 一律に変換するのではなく、**単位だけ**を狙って半角にできるようにしている。
enum Units {

    /// 半角で書くのが一般的な単位（小文字にして比較する）。
    /// 「km/h」「m/s」の分母に来る h・s・min なども含めてある
    static let known: Set<String> = [
        // 長さ・重さ・体積・面積
        "km", "m", "cm", "mm", "kg", "g", "mg", "t", "l", "ml", "kl", "cc", "ha",
        // 時間
        "h", "s", "min", "sec", "ms",
        // 電気・力・音
        "kw", "w", "kwh", "wh", "v", "kv", "a", "ma", "ah", "mah",
        "hz", "khz", "mhz", "ghz", "n", "kn", "pa", "kpa", "mpa", "db", "lx",
        // 機械
        "ps", "hp", "rpm", "mph", "cal", "kcal", "j", "kj",
        // 情報
        "kb", "mb", "gb", "tb", "bps", "dpi", "px", "pt",
    ]

    static func isDigit(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
        return (0x30...0x39).contains(v) || (0xFF10...0xFF19).contains(v)
    }

    static func isLetter(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
        return (0x61...0x7A).contains(v) || (0x41...0x5A).contains(v)
            || (0xFF21...0xFF3A).contains(v) || (0xFF41...0xFF5A).contains(v)
    }

    private static func isSlash(_ c: Character) -> Bool { c == "/" || c == "／" }

    /// その位置から始まる単位の範囲を返す（単位でなければnil）。
    ///
    /// **「km/h」「m/s」のように斜線でつながるものは、ひとまとまりとして返す。**
    /// 分けて扱うと「ｋｍ」と「ｈ」で2件の指摘になり、1つの問題が2回出てしまう。
    ///
    /// 数字のすぐ後ろに来たものだけを単位とみなす。単位でない普通の単語
    /// （ＳＴＯＰｉｔ など）を巻き込まないための線引き。
    static func unitRange(_ chars: [Character], at start: Int) -> Range<Int>? {
        guard start > 0, isDigit(chars[start - 1]) else { return nil }
        guard start < chars.count, isLetter(chars[start]) else { return nil }
        var e = start
        while e < chars.count, isLetter(chars[e]) { e += 1 }
        guard known.contains(toHalfWidthLower(String(chars[start..<e]))) else { return nil }
        // 「/h」「／s」が続けば、そこまでを1つの単位とみなす
        if e < chars.count, isSlash(chars[e]) {
            var d = e + 1
            while d < chars.count, isLetter(chars[d]) { d += 1 }
            if d > e + 1, known.contains(toHalfWidthLower(String(chars[(e + 1)..<d]))) {
                return start..<d
            }
        }
        return start..<e
    }

    /// 単位を半角にする（英字に加えて全角の斜線も半角へ）
    static func toHalfWidth(_ unit: String) -> String {
        String(unit.map { c -> Character in
            guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return c }
            if (0xFF21...0xFF3A).contains(v) || (0xFF41...0xFF5A).contains(v),
               let s = Unicode.Scalar(v - 0xFEE0) {
                return Character(s)
            }
            return c == "／" ? "/" : c
        })
    }

    static func toHalfWidthLower(_ s: String) -> String { toHalfWidth(s).lowercased() }

    /// 全角の文字が含まれているか
    static func hasFullWidth(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0xFF01...0xFF5E).contains($0.value) }
    }
}

// ============================================================
// 簡易アウトライン（見出しを拾って並べる）
// ============================================================
/// 本文から見出しらしい行を拾う。**本文には触れず、読むだけ**。
///
/// 見出しの決め方は2通りある。
///
/// **① 印がある文書：印だけに従う。**
/// 行頭の「# 」（大見出し）「## 」（小見出し）が印。印が1つでもある文書では
/// 推定をやめ、印のある行だけを見出しとする。宣言したものだけが動くので、
/// 並べ替えのように間違えると被害の大きい操作を安心して載せられる。
/// 印は原稿ではなく書き手の道具なので、字数・原稿用紙換算からは除く
/// （CharWidth.headingMarkLength）。
///
/// **② 印がない文書：これまでどおり推定する。**
/// 実際の原稿の見出しには記号が使われていないことが多く、記号方式だけだと
/// 1つも見つからない。かわりに、日本語の原稿では
///
/// 　・本文は行頭が字下げ（全角スペース）されている
/// 　・見出しは句点で終わらない
/// 　・見出しは短い
///
/// という3つの特徴がはっきり出るので、そちらで判定する。
/// 行頭の判定には既存の TextTransform.isParagraphHead をそのまま使う
/// （見出し用に別の記号リストを作ると、非整形や推敲での「行頭の記号」の意味と
/// 食い違って説明がつかなくなるため）。
///
/// 推定は意識して書かれた原稿でないときれいに揃わない。だからこそ①を用意した。
enum Outline {

    /// 見出しとみなす長さの上限（全角換算）
    static let defaultMaxWidth = 30.0

    /// 大見出しの印
    static let mark1 = "# "

    /// 小見出しの印
    static let mark2 = "## "

    struct Heading {
        /// 見出し行の範囲（UTF-16、改行は含まない）
        let start: Int
        let end: Int
        /// 行そのもの（印を含む）
        let text: String
        /// 物理行番号（1始まり）
        let line: Int
        /// この見出しから次の見出しの手前までの、原稿用紙の換算枚数
        let sheets: Double
        /// 1＝大見出し、2＝小見出し。推定で拾ったものは常に1
        let level: Int
        /// 印を除いた見出しの文字列（一覧に出すのはこちら）
        let title: String
    }

    /// 文書に見出しの印が1つでもあるか。あれば推定をやめ、印だけに従う
    static func hasMarks(_ text: String) -> Bool {
        hasMarks(Array(text))
    }

    static func hasMarks(_ chars: [Character]) -> Bool {
        var i = 0
        while i <= chars.count {
            if CharWidth.headingMarkLength(chars, i) > 0 { return true }
            var end = i
            while end < chars.count, chars[end] != "\n" { end += 1 }
            if end >= chars.count { return false }
            i = end + 1
        }
        return false
    }

    static func headings(_ text: String, maxWidth: Double = defaultMaxWidth) -> [Heading] {
        let chars = Array(text)
        let marked = hasMarks(chars)
        var found: [(start: Int, end: Int, line: Int, level: Int)] = []
        var lineNo = 1
        var i = 0
        while i <= chars.count {
            var end = i
            while end < chars.count, chars[end] != "\n" { end += 1 }
            let markLen = CharWidth.headingMarkLength(chars, i)
            if markLen > 0, end <= i + markLen {
                // 印だけで中身のない行は見出しにしない（打ちかけの行）
            } else if marked {
                if markLen > 0 { found.append((i, end, lineNo, markLen == 3 ? 2 : 1)) }
            } else if isHeadingLine(chars, i, end, maxWidth) {
                found.append((i, end, lineNo, 1))
            }
            if end >= chars.count { break }
            i = end + 1
            lineNo += 1
        }

        // UTF-16の位置へ移し替える（NSTextViewのNSRangeにそのまま渡せるように）
        var offsets = [Int](repeating: 0, count: chars.count + 1)
        var acc = 0
        for (k, c) in chars.enumerated() {
            offsets[k] = acc
            acc += String(c).utf16.count
        }
        offsets[chars.count] = acc

        return found.enumerated().map { index, item in
            // 次の見出しの手前までが、この見出しの受け持ち
            let bodyStart = min(item.end + 1, chars.count)
            let bodyEnd = index + 1 < found.count ? found[index + 1].start : chars.count
            let body = bodyEnd > bodyStart ? String(chars[bodyStart..<bodyEnd]) : ""
            let blank = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let markLen = CharWidth.headingMarkLength(chars, item.start)
            return Heading(
                start: offsets[item.start], end: offsets[item.end],
                text: String(chars[item.start..<item.end]), line: item.line,
                sheets: blank ? 0
                    : CharWidth.manuscriptSheets(body, excludeHeadingMarks: true),
                level: item.level,
                title: String(chars[(item.start + markLen)..<item.end]))
        }
    }

    // ---------- 節（並べ替えの単位） ----------

    /// 節。**見出しの直前の空行から、次の見出しの直前の空行まで。**
    ///
    /// 空行は「前の段落の終わり」ではなく**次の見出しのもの**として扱う。
    /// こうしないと、節を動かしたときに空行が置き去りになり、
    /// **本文のすぐ下に見出しが来てしまう**（実際に並べ替えて分かった）。
    /// 見出しは自分の前の余白を連れて動く、というのが読み手の感覚にも合う。
    ///
    /// 空行の数はそのまま運ぶ。実際の原稿では見出しの前が2行空け・1行空けと
    /// 揃っておらず、その数が階層を表していることがある。
    /// アプリが正規化してよいものではない。
    /// 位置はすべて UTF-16（NSTextView の NSRange と同じ数え方）。
    struct Section {
        let start: Int
        let end: Int
        /// 1＝大見出し、2＝小見出し
        let level: Int
        /// 印を除いた見出しの文字列
        let title: String
    }

    /// 並べ替えの計画の1つぶん。元の節の番号と、置きたい段
    struct Placed {
        let index: Int
        let level: Int
        init(_ index: Int, _ level: Int) {
            self.index = index
            self.level = level
        }
    }

    /// 本文の書き換え1回ぶん。変わらない前後は含まない
    struct TextPatch {
        let start: Int
        let end: Int
        let replacement: String
    }

    /// 節に切り出す。**印のある文書でだけ意味がある**（推定見出しで並べ替えると、
    /// 誤検出したところで段落が途中から動いてしまう）。
    static func sections(_ text: String) -> [Section] {
        guard hasMarks(text) else { return [] }
        let h = headings(text)
        let ns = text as NSString
        let starts = h.map { sectionStartFor(ns, $0.start) }
        return h.enumerated().map { i, item in
            Section(
                start: starts[i],
                end: i + 1 < h.count ? starts[i + 1] : ns.length,
                level: item.level,
                title: item.title)
        }
    }

    /// 見出しの直前にある空行の先頭を返す。空行がなければ見出し行の先頭。
    /// 空白だけの行も空行として扱う（書き手には空行に見えるため）。
    private static func sectionStartFor(_ ns: NSString, _ headingStart: Int) -> Int {
        var pos = headingStart
        while pos > 0 {
            let lineEnd = pos - 1
            if ns.character(at: lineEnd) != 0x0A { break }
            let lineStart = ns.lineRange(for: NSRange(location: lineEnd, length: 0)).location
            if lineEnd > lineStart {
                let line = ns.substring(with: NSRange(
                    location: lineStart, length: lineEnd - lineStart))
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            }
            pos = lineStart
            if lineStart == 0 { break }
        }
        return pos
    }

    /// 最初の見出しより前の文章の終わり。どの節にも属さないので、
    /// 並べ替えでは**先頭に固定して動かさない**。見出しがなければ本文の終わり。
    static func preambleEnd(_ text: String) -> Int {
        sections(text).first?.start ?? (text as NSString).length
    }

    /// その節と一緒に動くものの数。**大見出しは、続く小見出しを引き連れて動く**
    /// （章を動かしたら中身もついてくるのが当たり前なので）。小見出しは自分だけ。
    static func groupSize(_ sections: [Section], _ index: Int) -> Int {
        guard sections.indices.contains(index) else { return 0 }
        if sections[index].level >= 2 { return 1 }
        var n = 1
        while index + n < sections.count, sections[index + n].level >= 2 { n += 1 }
        return n
    }

    /// 並べ替えた結果を本文に当てるための書き換えを作る。変わらなければ nil。
    ///
    /// **前後の変わっていない節は書き換えない。** 540万字の文書で節を1つ動かした
    /// だけで全文が作り直されると、取り消しの履歴も画面の位置も丸ごと吹き飛ぶ。
    ///
    /// plan は「新しい並び順」で、元の節の番号を1つずつ、過不足なく含むこと。
    static func reorderPatch(_ text: String, plan: [Placed]) -> TextPatch? {
        let secs = sections(text)
        guard plan.count == secs.count else { return nil }
        guard Set(plan.map { $0.index }) == Set(secs.indices) else { return nil }

        // 先頭から、動いても段も変わっていない節を飛ばす
        var head = 0
        while head < plan.count, plan[head].index == head, plan[head].level == secs[head].level {
            head += 1
        }
        if head == plan.count { return nil } // 何も変わっていない

        // 末尾からも同じように飛ばす
        var tail = 0
        while head + tail < plan.count {
            let p = plan[plan.count - 1 - tail]
            let orig = secs.count - 1 - tail
            if p.index != orig || p.level != secs[orig].level { break }
            tail += 1
        }

        let ns = text as NSString
        let from = secs[head].start
        let to = secs[secs.count - 1 - tail].end
        // 前書きが無い文書か（＝最初の節が本文の先頭から始まるか）
        let noPreamble = secs[0].start == 0
        var out = ""
        for k in head..<(plan.count - tail) {
            // 文書のいちばん最後の節だけは、元の終わり方（改行の有無）をそのまま残す。
            // それ以外は必ず改行で終わらせないと、動かした先で行が繋がってしまう
            let isDocumentLast = k == plan.count - 1
            var body = sectionText(
                ns, secs[plan[k].index], level: plan[k].level, needNewline: !isDocumentLast)
            // 文書のいちばん先頭に来た節は、連れてきた空行を落とす。
            // 空行は「見出しの前の余白」なので、前に何も無ければ意味がない
            if k == 0, noPreamble {
                while body.hasPrefix("\n") { body.removeFirst() }
            }
            out += body
        }
        if out == ns.substring(with: NSRange(location: from, length: to - from)) { return nil }
        return TextPatch(start: from, end: to, replacement: out)
    }

    /// 節1つぶんの本文。見出しの印を、置きたい段のものに付け替える
    private static func sectionText(
        _ ns: NSString, _ sec: Section, level: Int, needNewline: Bool
    ) -> String {
        // 節の先頭は空行かもしれない。印があるのは見出し行の先頭なので、そこまで進む
        var headingStart = sec.start
        while headingStart < sec.end {
            let peek = ns.substring(with: NSRange(
                location: headingStart, length: min(3, sec.end - headingStart)))
            if CharWidth.headingMarkLength(Array(peek), 0) > 0 { break }
            let nl = ns.range(of: "\n", options: [], range: NSRange(
                location: headingStart, length: sec.end - headingStart))
            if nl.location == NSNotFound { break }
            headingStart = nl.location + 1
        }
        let peek = ns.substring(with: NSRange(
            location: headingStart, length: min(3, sec.end - headingStart)))
        let markLen = CharWidth.headingMarkLength(Array(peek), 0)
        var out = ns.substring(with: NSRange(
            location: sec.start, length: headingStart - sec.start))   // 見出しの前の空行
        out += level >= 2 ? mark2 : mark1
        out += ns.substring(with: NSRange(
            location: headingStart + markLen, length: sec.end - headingStart - markLen))
        if needNewline, !out.hasSuffix("\n") { out += "\n" }
        return out
    }

    /// 指定した行の先頭に、見出しの印を打つ。**推定で拾った候補を確定させる**ために使う。
    ///
    /// 推定は候補を出すところまでで、どれが本当の見出しかは書き手が決める。
    /// 面倒な探索だけを機械にやらせて、判断は人が持つ、という分担にする。
    ///
    /// **1回の書き換えにまとめる**ので取り消しも1回で戻る。書き換えるのは
    /// 最初の印から最後の印までで、その外側には触れない。
    /// すでに印のある行は飛ばす。位置は UTF-16。
    static func applyMarks(_ text: String, lineStarts: [Int], level: Int = 1) -> TextPatch? {
        let ns = text as NSString
        let targets = Array(Set(lineStarts))
            .filter { $0 >= 0 && $0 <= ns.length && markLength(ns, at: $0) == 0 }
            .sorted()
        guard let first = targets.first, let last = targets.last else { return nil }
        let mark = level >= 2 ? mark2 : mark1
        var out = ""
        var pos = first
        for t in targets {
            out += ns.substring(with: NSRange(location: pos, length: t - pos))
            out += mark
            pos = t
        }
        return TextPatch(start: first, end: last, replacement: out)
    }

    /// その位置にある見出しの印の長さ（UTF-16の位置で聞く）
    private static func markLength(_ ns: NSString, at location: Int) -> Int {
        let peek = ns.substring(with: NSRange(
            location: location, length: min(3, ns.length - location)))
        return CharWidth.headingMarkLength(Array(peek), 0)
    }

    // ---------- 印の付け外し ----------

    /// 印を送るための書き換え。**本文全体を作り直さず、かかった行だけ**を差し替える
    /// （540万字の文書で一文字ぶんの操作に全文のコピーが走らないようにするため）。
    /// 位置はすべて UTF-16（NSTextView の NSRange と同じ数え方）。
    struct MarkPatch {
        let start: Int
        let end: Int
        let replacement: String
        let selStart: Int
        let selEnd: Int
    }

    /// 印を1段ずつ送る。**なし → 大見出し → 小見出し → なし** の繰り返し。
    ///
    /// 「付ける」「外す」「段を選ぶ」を別々のボタンにすると3つ要るが、送るだけなら
    /// 1つで済む。選択が複数行にかかっているときは、**先頭の行の状態を見て
    /// 全部を同じ段に揃える**（ばらばらのまま送ると、どうなるか予想できないため）。
    ///
    /// 変わるところがなければ nil を返す。
    static func cycleMarkPatch(_ text: String, selStart: Int, selEnd: Int) -> MarkPatch? {
        let ns = text as NSString
        let s = min(max(selStart, 0), ns.length)
        let e0 = min(max(selEnd, s), ns.length)
        // 選択が行頭でちょうど終わっているとき、その行は含めない
        var e = e0
        if e > s, e > 0, ns.character(at: e - 1) == 0x0A { e -= 1 }
        var region = ns.lineRange(for: NSRange(location: s, length: e - s))
        // 行末の改行は書き換えない（含めると末尾の行だけ扱いが変わる）
        if region.length > 0,
           ns.character(at: region.location + region.length - 1) == 0x0A {
            region.length -= 1
        }
        let body = ns.substring(with: region)
        let lines = body.components(separatedBy: "\n")
        guard let head = lines.first else { return nil }

        let firstMark = CharWidth.headingMarkLength(Array(head), 0)
        let next = firstMark == 0 ? mark1 : (firstMark == mark1.count ? mark2 : "")

        var rebuilt: [String] = []
        var edits: [(at: Int, oldLen: Int)] = []
        var at = region.location
        for line in lines {
            let chars = Array(line)
            let oldLen = CharWidth.headingMarkLength(chars, 0)
            rebuilt.append(next + String(chars.dropFirst(oldLen)))
            edits.append((at, oldLen))
            at += (line as NSString).length + 1 // 改行のぶん
        }
        let replacement = rebuilt.joined(separator: "\n")
        if replacement == body { return nil }

        // カーソルは、書き換えた行のぶんだけ後ろへ動かす。
        // 位置は元の座標のままなので、後ろの行から順に当てる
        var newS = s
        var newE = e0
        for edit in edits.reversed() where edit.oldLen != next.count {
            newS = shifted(newS, edit.at, edit.oldLen, next.count)
            newE = shifted(newE, edit.at, edit.oldLen, next.count)
        }
        return MarkPatch(
            start: region.location, end: region.location + region.length,
            replacement: replacement, selStart: newS, selEnd: newE)
    }

    /// cycleMarkPatch を本文全体に当てた結果。テストと、全文を持つ側のための入口
    static func cycleMark(
        _ text: String, selStart: Int, selEnd: Int
    ) -> (text: String, selStart: Int, selEnd: Int) {
        guard let p = cycleMarkPatch(text, selStart: selStart, selEnd: selEnd) else {
            return (text, selStart, selEnd)
        }
        let ns = text as NSString
        let range = NSRange(location: p.start, length: p.end - p.start)
        return (ns.replacingCharacters(in: range, with: p.replacement), p.selStart, p.selEnd)
    }

    /// すべての印を外す。入稿の直前に使う。
    /// これを通したファイルなら、画面の字数と受け取った側で数えた字数が一致する。
    static func stripMarks(_ text: String) -> String {
        guard hasMarks(text) else { return text }
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            let chars = Array(line)
            out.append(String(chars.dropFirst(CharWidth.headingMarkLength(chars, 0))))
        }
        return out.joined(separator: "\n")
    }

    /// 印を付け外ししたあと、位置がどこへ動くか。消えた範囲の中にいたら、その先頭へ寄せる。
    ///
    /// 行頭ちょうど（x == at）は**印の後ろへ送る**。印を付けてすぐ書き始められるように
    /// するため（ここを動かさないと、カーソルが「#」の前に取り残される）。
    private static func shifted(_ x: Int, _ at: Int, _ oldLen: Int, _ newLen: Int) -> Int {
        if x < at { return x }
        if x >= at + oldLen { return x + (newLen - oldLen) }
        return at + newLen
    }

    /// 1行が見出しかどうか。範囲は [start, end)（改行を含まない）
    private static func isHeadingLine(
        _ chars: [Character], _ start: Int, _ end: Int, _ maxWidth: Double
    ) -> Bool {
        guard end > start else { return false }
        let line = String(chars[start..<end])
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // ① 行頭が字下げ・括弧（会話文）・箇条書き記号・丸付き数字なら本文
        guard let first = line.first, !TextTransform.isParagraphHead(first) else { return false }
        // ② 句点で終わっていれば言い切った文＝本文
        if endsWithTerminator(line) { return false }
        // ③ 長ければ本文。ただし**章立ての行は長さで外さない**。
        // 「第1章：淀屋橋駅の朝。限られた番線での秒単位のオペレーション（実況観察）」の
        // ように、章の見出しは副題を伴って30字を超えることがよくある
        if startsWithChapterNumber(line) || startsWithHeadingKeyword(line) { return true }
        return CharWidth.zenkakuCount(line) <= maxWidth
    }

    /// 長さに関わらず見出しとみなす決まり文句。
    /// 副題が付いて30字を超えることがあるので、章立てと同じ扱いにする。
    private static let headingKeywords = [
        "はじめに", "始めに", "まえがき", "前書き", "序文", "序論",
        "おわりに", "終わりに", "あとがき", "後書き", "むすび", "結び",
        "まとめ", "概要", "要約", "目次",
        // 割り付け原稿で、書き手が編集部へ渡す指定に使う語
        "リード", "本文", "大見出し", "中見出し", "小見出し", "見出し", "柱", "キャプション",
    ]

    /// 決まり文句の直後に来てよい文字。**ここで区切られていることを求める**のが要点で、
    /// 「はじめに述べたとおり」「まとめると」のような本文を巻き込まないための条件。
    /// 行末（区切りなし）も認める。
    private static let keywordDelimiters = Set(" 　：:（(【［[・ー－-|｜／/")

    /// 決まり文句で始まり、そこで区切られている行か
    private static func startsWithHeadingKeyword(_ line: String) -> Bool {
        for word in headingKeywords where line.hasPrefix(word) {
            let rest = line.dropFirst(word.count)
            if rest.isEmpty { return true }
            if let next = rest.first, keywordDelimiters.contains(next) { return true }
        }
        return false
    }

    /// 章立ての番号に使う数字（半角・全角・漢数字）
    private static let chapterDigits =
        Set("0123456789０１２３４５６７８９一二三四五六七八九十百千")

    /// 章立ての単位
    private static let chapterUnits = Set("章節部編話回幕講")

    /// 章立ての形（第1章・第一章・2章・第3節 など）で始まる行か。
    /// 「第」は省略できる。番号のない「序章」「終章」は短いので長さの規則で拾える。
    private static func startsWithChapterNumber(_ line: String) -> Bool {
        var chars = Array(line.prefix(8))[...]
        if chars.first == "第" { chars = chars.dropFirst() }
        var digits = 0
        while let c = chars.first, chapterDigits.contains(c) {
            chars = chars.dropFirst()
            digits += 1
        }
        guard digits > 0, let unit = chars.first else { return false }
        return chapterUnits.contains(unit)
    }

    /// 閉じ括弧を取り除いたうえで、句点で終わっているか
    private static func endsWithTerminator(_ line: String) -> Bool {
        var e = Array(line)
        while let last = e.last, ProofCheck.closers.contains(last) { e.removeLast() }
        guard let last = e.last else { return false }
        return ProofCheck.terminators.contains(last)
    }
}
