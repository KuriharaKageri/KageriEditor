import Foundation

// ============================================================
// 推敲（書き上げた原稿を読み返すときの手がかりを集める）
// Android版 ProofCheck.kt の移植
// ============================================================
/**
 「気になる箇所」を見つけて並べるだけで、**直さない**。
 体裁を機械的に整える原稿支援（TextTransform.assist）とはそこが違う。
 文章の良し悪しは書き手が決めるもので、一括置換すると原稿が壊れるため。

 方針は「指摘は少なく確実に」。判定に自信が持てない場合は黙っている。
 見逃しは読み返しで拾えるが、誤った指摘が続くと機能ごと使われなくなるので、
 迷ったら指摘しない側に倒している。

 誤字脱字・変換ミスの検出と、文法の正誤判定は範囲外。

 **位置はすべてUTF-16の単位で返す**（NSTextViewのNSRangeにそのまま渡せるように）。
 内部の判定は[Character]の添字で行い、最後にまとめて変換している。
 */
enum ProofCheck {

    enum Kind: CaseIterable {
        case sentenceEnd, particleRepeat, noChain, longSentence, variant, typo

        var label: String {
            switch self {
            case .sentenceEnd: return "語尾"
            case .particleRepeat: return "助詞"
            case .noChain: return "の"
            case .longSentence: return "長文"
            case .variant: return "ゆれ"
            case .typo: return "誤植"
            }
        }
    }

    /// 指摘1件。
    /// start/end は**ジャンプしたときに選ばれる範囲**（指摘の意味的な広がり）。
    /// spots は**赤く示す箇所**で、問題そのものを指す短い範囲を並べたもの。
    /// 空なら start..<end 全体を示す。
    struct Finding {
        let start: Int
        let end: Int
        let kind: Kind
        let note: String
        var spots: [Range<Int>] = []
    }

    struct Options {
        var sentenceEnd = true
        var particleRepeat = true
        var noChain = true
        var longSentence = true
        var variant = true
        var typo = true
        /// 同じ型の語尾がこの数だけ続いたら指摘する（2だと出過ぎる）
        var sentenceEndRun = 3
        /// 一文の中で同じ助詞がこの数以上使われていたら指摘する。
        /// 実際の取材原稿では3回はごく普通に出るため4にしている
        var particleLimit = 4
        /// 「の」がこの数だけ連なったら指摘する
        var noChainLimit = 3
        /// 全角換算でこの字数を超えた文を指摘する
        var longSentenceLimit = 100.0
    }

    // ---------- 入口 ----------

    static func run(_ text: String, options: Options = Options()) -> [Finding] {
        let chars = Array(text)
        guard !chars.isEmpty else { return [] }
        var findings: [Finding] = []
        let sentences = splitSentences(chars)
        if options.sentenceEnd {
            findings += checkSentenceEndRuns(chars, sentences, run: options.sentenceEndRun)
        }
        if options.particleRepeat {
            findings += checkParticleRepeat(chars, sentences, limit: options.particleLimit)
        }
        if options.longSentence {
            findings += checkLongSentences(chars, sentences, limit: options.longSentenceLimit)
        }
        if options.noChain { findings += checkNoChain(chars, limit: options.noChainLimit) }
        if options.variant {
            findings += checkVariants(chars)
            findings += checkWidthVariants(chars)
        }
        if options.typo { findings += checkTypos(chars) }

        findings.sort {
            $0.start != $1.start ? $0.start < $1.start : kindOrder($0.kind) < kindOrder($1.kind)
        }
        return convertToUTF16(findings, chars: chars)
    }

    private static func kindOrder(_ kind: Kind) -> Int {
        Kind.allCases.firstIndex(of: kind) ?? 0
    }

    /// 文字の添字で組み立てた指摘を、UTF-16の位置へ移し替える
    private static func convertToUTF16(_ findings: [Finding], chars: [Character]) -> [Finding] {
        var offsets = [Int](repeating: 0, count: chars.count + 1)
        var acc = 0
        for (i, c) in chars.enumerated() {
            offsets[i] = acc
            acc += String(c).utf16.count
        }
        offsets[chars.count] = acc
        func at(_ i: Int) -> Int { offsets[min(max(i, 0), chars.count)] }
        return findings.map {
            Finding(start: at($0.start), end: at($0.end), kind: $0.kind, note: $0.note,
                    spots: $0.spots.map { at($0.lowerBound)..<at($0.upperBound) })
        }
    }

    // ---------- 文の切り出し ----------

    struct Sentence {
        let start: Int
        let end: Int
        let text: String
        /// 箇条書き・番号付き・▼見出しの行にある文。文末が揃うのが自然なので
        /// 語尾・長さ・助詞の判定からは外す。
        /// 文の先頭の文字ではなく**その文が始まる行の先頭**で見る
        /// （1つの項目が2文以上あると2文目は「・」を持たないため）
        let isBullet: Bool

        /// 「。！？」で終わっている＝ちゃんと言い切った文かどうか。
        /// 見出し・箇条書きの項目・表組みの行は終止符を持たないので、
        /// 語尾や長さを判定しても意味がない
        var isComplete: Bool {
            var e = Array(text)
            while let last = e.last, closers.contains(last) { e.removeLast() }
            guard let last = e.last else { return false }
            return terminators.contains(last)
        }
    }

    static let bulletHeads: Set<Character> = Set("・･●○◎■□◆◇▼▲▽△※-*＊")
    static let terminators: Set<Character> = Set("。！？!?")
    static let closers: Set<Character> = Set("」』）)】〉》〕］]｝}”’〟")
    static let breakers: Set<Character> = Set("、。，．！？!?\n（）()「」『』【】・…—")

    /// 「。！？」と**空行**と**箇条書き行の開始**と**閉じ括弧で終わる行**で文に区切る。
    ///
    /// **改行1つでは切らない。** このアプリの「整形」（⌃E）は指定字数で改行を入れるので、
    /// 1つの文が複数行にまたがるのが普通だからである。
    static func splitSentences(_ chars: [Character]) -> [Sentence] {
        var result: [Sentence] = []
        var start = 0
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if terminators.contains(ch) {
                var end = i + 1
                while end < chars.count, closers.contains(chars[end]) { end += 1 }
                addSentence(&result, chars, start, end)
                start = end
                i = end
            } else if ch == "\n",
                      blankLineFollows(chars, i) || isListLine(chars, i + 1) || closerBefore(chars, i) {
                addSentence(&result, chars, start, i)
                start = i + 1
                i += 1
            } else {
                i += 1
            }
        }
        addSentence(&result, chars, start, chars.count)
        return result
    }

    /// その改行の直前が閉じ括弧か。
    /// 「……と思いました」のように会話文は句点を伴わずに閉じることが多く、
    /// ここで切らないと会話の段落が次の地の文とひとつながりの1文になる
    private static func closerBefore(_ chars: [Character], _ newlineIndex: Int) -> Bool {
        var i = newlineIndex - 1
        while i >= 0, isBlankChar(chars[i]) { i -= 1 }
        return i >= 0 && closers.contains(chars[i])
    }

    /// その改行の直後が空行（空白だけの行）か。段落の切れ目とみなす
    private static func blankLineFollows(_ chars: [Character], _ newlineIndex: Int) -> Bool {
        var i = newlineIndex + 1
        while i < chars.count {
            if chars[i] == "\n" { return true }
            if !isBlankChar(chars[i]) { return false }
            i += 1
        }
        return true
    }

    private static func addSentence(_ into: inout [Sentence], _ chars: [Character], _ start: Int, _ end: Int) {
        var s = start
        var e = end
        while s < e, isBlankChar(chars[s]) { s += 1 }
        while e > s, isBlankChar(chars[e - 1]) { e -= 1 }
        guard e > s else { return }
        into.append(Sentence(start: s, end: e, text: String(chars[s..<e]),
                             isBullet: isListLine(chars, s)))
    }

    private static func isBlankChar(_ c: Character) -> Bool {
        c == "\n" || c == "\r" || c == " " || c == "\u{3000}" || c == "\t"
    }

    /// その位置を含む行が、箇条書き・番号付き・▼見出しで始まっているか
    private static func isListLine(_ chars: [Character], _ index: Int) -> Bool {
        var i = index - 1
        while i >= 0, chars[i] != "\n" { i -= 1 }
        i += 1
        while i < chars.count, chars[i] != "\n", isBlankChar(chars[i]) { i += 1 }
        guard i < chars.count else { return false }
        if bulletHeads.contains(chars[i]) { return true }
        var j = i
        while j < chars.count, isDigit(chars[j]) { j += 1 }
        return j > i && j < chars.count && ".．、)）:：".contains(chars[j])
    }

    private static func isDigit(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
        return (0x30...0x39).contains(v) || (0xFF10...0xFF19).contains(v)
    }

    // ---------- 語尾の連続 ----------

    enum EndingType {
        case ta, ru, da, dearu, nai, darou, masu, mashita, masen, desu, deshita, other
    }

    /// 文末表現。長いものから先に照合する（「ました」を「た」より先に見るため）
    private static let endingPatterns: [(String, EndingType)] = [
        ("ませんでした", .masen), ("ましょう", .masu), ("ました", .mashita),
        ("ません", .masen), ("ます", .masu),
        ("でしょう", .desu), ("でした", .deshita), ("です", .desu),
        ("であろう", .darou), ("だろう", .darou),
        // 「である」と「だ」は同じ断定でも読むと調子が違う（3音と1音）。
        // 敬体で「ます／ました／ません」を分けているのと同じ細かさに揃える
        ("である", .dearu),
        ("なかった", .nai), ("ない", .nai), ("ぬ", .nai),
    ].sorted { $0.0.count > $1.0.count }

    /// 文末を「型」に分ける。
    /// 「運んだ」「増えた」「高まった」は文字はどれも違うが、読むと同じ調子になる。
    /// 文字の一致では拾えないので、型に落としてから比べる。
    ///
    /// 敬体は「ます／ました／ません」を別の型に分けている。まとめてしまうと
    /// 「〜になります。〜差し替えます。〜ありません。」が連続と判定されるため。
    /// 判定できないものはotherにし、**other同士は同じ型とみなさない**。
    static func endingType(_ sentence: String) -> EndingType {
        var body = Array(sentence)
        while let last = body.last, closers.contains(last) || terminators.contains(last) {
            body.removeLast()
        }
        guard !body.isEmpty else { return .other }
        let text = String(body)
        for (suffix, type) in endingPatterns where text.hasSuffix(suffix) { return type }
        // 「だ」は直前が「ん」なら動詞の過去（読んだ・運んだ）、そうでなければ断定（必要だ）
        if text.hasSuffix("んだ") { return .ta }
        if text.hasSuffix("だ") { return .da }
        if text.hasSuffix("た") { return .ta }
        if text.hasSuffix("る") { return .ru }
        return .other
    }

    /// 文末のうち「調子」を決めている部分の長さ（活用語尾＋終止符＋閉じ括弧）。
    /// 一覧でここだけを赤くすると、3文の語尾が同じ形であることが一目で分かる
    static func endingSpotLength(_ sentence: String) -> Int {
        var body = Array(sentence)
        var tail = 0
        while let last = body.last, closers.contains(last) || terminators.contains(last) {
            body.removeLast()
            tail += 1
        }
        let text = String(body)
        for (suffix, _) in endingPatterns where text.hasSuffix(suffix) { return tail + suffix.count }
        if text.hasSuffix("んだ") { return tail + 2 }
        if text.hasSuffix("だ") || text.hasSuffix("た") || text.hasSuffix("る") { return tail + 1 }
        return tail
    }

    /// 判定できない文（見出し・箇条書き・言い切っていない行）は**取り除かず、連続を切る**。
    /// 取り除くと、間に見出しや箇条書きが挟まっていても前後の文が隣り合ったことになり、
    /// 章をまたいだ「連続」を報告してしまう。
    /// **段落をまたぐ連続も数えない**（話題が変われば単調には感じないため）。
    private static func checkSentenceEndRuns(
        _ chars: [Character], _ sentences: [Sentence], run: Int
    ) -> [Finding] {
        func typeOf(_ s: Sentence) -> EndingType {
            (s.isBullet || !s.isComplete) ? .other : endingType(s.text)
        }
        var findings: [Finding] = []
        var i = 0
        while i < sentences.count {
            let type = typeOf(sentences[i])
            if type == .other {
                i += 1
                continue
            }
            var j = i + 1
            while j < sentences.count, typeOf(sentences[j]) == type,
                  !paragraphBreakBetween(chars, sentences[j - 1].end, sentences[j].start) {
                j += 1
            }
            let count = j - i
            if count >= run {
                // 赤くするのは語尾そのものだけ。文全体を赤くしても何が同じなのか分からない
                let spots = (i..<j).map { k -> Range<Int> in
                    let s = sentences[k]
                    return (s.end - endingSpotLength(s.text))..<s.end
                }
                findings.append(Finding(
                    start: sentences[i].start, end: sentences[j - 1].end, kind: .sentenceEnd,
                    note: "同じ調子の文末が\(count)文続いています", spots: spots))
            }
            i = j
        }
        return findings
    }

    /// 2つの文のあいだに改行があるか＝段落が変わっているか
    private static func paragraphBreakBetween(_ chars: [Character], _ from: Int, _ to: Int) -> Bool {
        for i in from..<max(from, to) where chars[i] == "\n" { return true }
        return false
    }

    // ---------- 同じ助詞の多用 ----------

    private static let particles: [Character] = ["が", "は", "を", "に", "で", "と", "も"]

    /// 助詞の直後に来やすい文字。読点で受ける接続の助詞を拾うために使う
    private static let particleFollowers: Set<Character> = Set("、。，．\n）」』】")

    /// 「です」の後ろに来ると、断定の助動詞だと分かる文字（文がそこで切れる）
    private static let afterDesu: Set<Character> = Set("。、，．\n）」』】！？がかねよ")

    /// その位置の平仮名を助詞として数えてよさそうか。
    /// ① 直前が漢字・カタカナ・英数字・閉じ括弧（「鉄道が」「ハワイは」）
    /// ② 直後が読点・句点・閉じ括弧（「〜したが、」「〜だが、」）
    /// ①だけだと接続の助詞を取りこぼす（実際に積み重なるのはむしろこちら）
    private static func looksLikeParticle(_ chars: [Character], _ index: Int) -> Bool {
        if index > 0 {
            let prev = chars[index - 1]
            if isKanji(prev) || isKatakana(prev) || isAlnum(prev) || closers.contains(prev) {
                return true
            }
        }
        let next = index + 1 < chars.count ? chars[index + 1] : "\n"
        return particleFollowers.contains(next)
    }

    /// 助詞として数えてよいか。文体のクセとは言えない用法を除く
    private static func countableParticle(_ chars: [Character], _ index: Int, _ p: Character) -> Bool {
        guard looksLikeParticle(chars, index) else { return false }
        // 引用の「と」（「……」と語った）。取材原稿では避けようがなく、クセではない
        if p == "と", index > 0, closers.contains(chars[index - 1]) { return false }
        // 「ので」の「で」は接続の働きで、場所や手段の「で」とは別のもの
        if p == "で", index > 0, chars[index - 1] == "の" { return false }
        // 「です」の「で」は断定の助動詞。ただし「これですぐ」「〜ですべて」の
        // 「で」は助詞なので、文が切れる形（です。／です、／ですが／ですね）だけを除く
        if p == "で", index + 1 < chars.count, chars[index + 1] == "す" {
            let after = index + 2 < chars.count ? chars[index + 2] : "\n"
            if afterDesu.contains(after) { return false }
        }
        // 「こと」の「と」は形式名詞の一部で、助詞ではない
        if p == "と", index > 0, chars[index - 1] == "こ" { return false }
        // 「できる」「できた」の「で」は助詞ではない
        if p == "で", index + 1 < chars.count, chars[index + 1] == "き" { return false }
        // 「上がる」「広がり」「見積もる」のような動詞の一部
        if p == "が" || p == "も", index + 1 < chars.count,
           "るりっら".contains(chars[index + 1]) { return false }
        return true
    }

    private static func isKanji(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
            || c == "々" || (0xF900...0xFAFF).contains(v)
    }

    private static func isKatakana(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x30A1...0x30FA).contains(v) || (0xFF66...0xFF9D).contains(v) || c == "ー"
    }

    private static func isAlnum(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
        return (0x30...0x39).contains(v) || (0x61...0x7A).contains(v) || (0x41...0x5A).contains(v)
            || (0xFF10...0xFF19).contains(v) || (0xFF21...0xFF3A).contains(v)
            || (0xFF41...0xFF5A).contains(v)
    }

    private static func isHiragana(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3041...0x309F).contains(v)
    }

    /// 読点。ここで意味が切り分けられていれば、繰り返しの重さを割り引く
    private static let commas: Set<Character> = ["、", "，"]

    /// 読点をまたぐ繰り返しを、何回ぶんとして数えるか。
    /// 文脈上どうしても同じ助詞が続くとき、読点で意味を切り分けてリズムを整えるのは
    /// 書き手の技術なので、続けざまに重なる場合と同じには扱わない。
    private static let commaWeight = 0.5


    private static func checkParticleRepeat(
        _ chars: [Character], _ sentences: [Sentence], limit: Int
    ) -> [Finding] {
        var findings: [Finding] = []
        for s in sentences where !s.isBullet && s.isComplete {
            for p in particles {
                var at: [Int] = []
                for i in s.start..<s.end where chars[i] == p && countableParticle(chars, i, p) {
                    at.append(i)
                }
                // 割り引きは指摘を減らす側にしか働かせない
                if at.count < limit { continue }
                // 隣り合う2つの間に読点があれば、その1回ぶんを軽く数える
                var weight = 1.0
                for k in 1..<at.count {
                    let separated = ((at[k - 1] + 1)..<at[k]).contains { commas.contains(chars[$0]) }
                    weight += separated ? commaWeight : 1.0
                }
                if weight < Double(limit) { continue }
                findings.append(Finding(
                    start: s.start, end: s.end, kind: .particleRepeat,
                    note: "「\(p)」が1文に\(at.count)回出てきます",
                    spots: at.map { $0..<($0 + 1) }))
            }
        }
        return findings
    }

    // ---------- 一文が長い ----------

    private static func checkLongSentences(
        _ chars: [Character], _ sentences: [Sentence], limit: Double
    ) -> [Finding] {
        var findings: [Finding] = []
        for s in sentences where !s.isBullet && s.isComplete {
            let width = CharWidth.zenkakuCount(s.text)
            if width > limit {
                let shown = width == width.rounded() ? String(Int(width)) : String(format: "%.1f", width)
                findings.append(Finding(start: s.start, end: s.end, kind: .longSentence,
                                        note: "この文は\(shown)字あります"))
            }
        }
        return findings
    }

    // ---------- 「の」の連続 ----------

    /// 「日本の鉄道の歴史の転換点」のように「の」で名詞をつなぎ続けている箇所。
    /// 「の」と「の」の間が短く、その間に句読点や括弧が挟まらない場合だけ
    /// ひと続きの名詞句とみなす
    /// 名詞をつなぐ「の」か。**直前が名詞のときだけ**数える。
    ///
    /// 助詞の判定にある「直後が読点・句点なら数える」という条件は、「の」には効かせない。
    /// つなぐ「の」の後ろには必ず名詞が来るので、「そのもの。」「〜のだ、」のように
    /// 句読点が続く「の」は、つなぐ「の」ではありえない（実際の原稿で誤検出した）。
    private static func looksLikeLinkingNo(_ chars: [Character], _ index: Int) -> Bool {
        guard index > 0 else { return false }
        let prev = chars[index - 1]
        return isKanji(prev) || isKatakana(prev) || isAlnum(prev) || closers.contains(prev)
    }

    private static func checkNoChain(_ chars: [Character], limit: Int) -> [Finding] {
        var positions: [Int] = []
        for i in chars.indices where chars[i] == "の" && looksLikeLinkingNo(chars, i) {
            positions.append(i)
        }
        var findings: [Finding] = []
        var i = 0
        while i < positions.count {
            var j = i
            while j + 1 < positions.count, chained(chars, positions[j], positions[j + 1]) { j += 1 }
            let count = j - i + 1
            if count >= limit {
                findings.append(Finding(
                    start: positions[i], end: positions[j] + 1, kind: .noChain,
                    note: "「の」が\(count)回続いています",
                    spots: (i...j).map { positions[$0]..<(positions[$0] + 1) }))
            }
            i = j + 1
        }
        return findings
    }

    private static func chained(_ chars: [Character], _ a: Int, _ b: Int) -> Bool {
        let gap = b - a - 1
        guard gap >= 1, gap <= 8 else { return false }
        for i in (a + 1)..<b {
            if breakers.contains(chars[i]) || isBlankChar(chars[i]) { return false }
        }
        return true
    }

    // ---------- 表記ゆれ（かな漢字） ----------

    /// よく揺れる表記の組。**両方が本文に出ているときだけ**、少ない方を指摘する。
    struct VariantPair {
        let kanji: String
        let kana: String
        var formal = false
        /// 仮名側の直前にこの文字があれば数えない（「という」の「いう」など）
        var kanaNotAfter = ""
        /// 漢字側の直前にこの文字があれば数えない。「変更に」は「更に」を部分文字列として
        /// 含んでしまうので、「更」の直前が「変」なら複合語（変更）とみなして除く
        var kanjiNotAfter = ""
        /// 直前に来てよい文字を絞る（空なら平仮名すべて）。
        /// 「もの」は慣用的な用法が多いので連体形の語尾に限る
        var precededBy = ""
        /// 直後にこの文字が来たら数えない（「ものの」＝逆接）
        var notBefore = ""
    }

    static let variantPairs: [VariantPair] = [
        VariantPair(kanji: "事", kana: "こと", formal: true),
        // 「ごとき」（助動詞ごとし）と「ひととき」は形式名詞ではない。
        // 直前が平仮名なので連体形の条件では外れず、ここで個別に除く
        VariantPair(kanji: "時", kana: "とき", formal: true, kanaNotAfter: "ごと"),
        // 「もの」は形式名詞のほかに「そのもの」（＝itself）「ものの」（逆接）という
        // 慣用的な用法があり、「物」の側も「食べ物」「生き物」のような複合名詞が多い
        VariantPair(kanji: "物", kana: "もの", formal: true, precededBy: "ただなる", notBefore: "の"),
        VariantPair(kanji: "所", kana: "ところ", formal: true),
        VariantPair(kanji: "為", kana: "ため", formal: true),
        VariantPair(kanji: "子供", kana: "子ども"),
        VariantPair(kanji: "出来る", kana: "できる"),
        VariantPair(kanji: "下さい", kana: "ください"),
        VariantPair(kanji: "致します", kana: "いたします"),
        VariantPair(kanji: "頂く", kana: "いただく"),
        // 「いよいよ」の中の「よい」は「良い」ではない
        VariantPair(kanji: "良い", kana: "よい", kanaNotAfter: "い"),
        // 「という」「そういう」の「いう」は動詞ではない
        // 「という」「っていう」の「いう」は動詞ではない
        VariantPair(kanji: "言う", kana: "いう", kanaNotAfter: "とうて"),
        VariantPair(kanji: "行う", kana: "おこなう"),
        VariantPair(kanji: "分かる", kana: "わかる"),
        VariantPair(kanji: "初めて", kana: "はじめて"),
        VariantPair(kanji: "全て", kana: "すべて"),
        VariantPair(kanji: "既に", kana: "すでに"),
        VariantPair(kanji: "更に", kana: "さらに", kanjiNotAfter: "変"),
        VariantPair(kanji: "特に", kana: "とくに"),
        VariantPair(kanji: "殆ど", kana: "ほとんど"),
        VariantPair(kanji: "但し", kana: "ただし"),
        VariantPair(kanji: "従って", kana: "したがって"),
        VariantPair(kanji: "及び", kana: "および"),
        VariantPair(kanji: "並びに", kana: "ならびに"),
        VariantPair(kanji: "或いは", kana: "あるいは"),
        VariantPair(kanji: "即ち", kana: "すなわち"),
        VariantPair(kanji: "様々", kana: "さまざま"),
        VariantPair(kanji: "色々", kana: "いろいろ"),
    ]

    private static let afterFormal: Set<Character> = Set("がはをにでともやかのねよ、。，．！？!?\n）」』")

    private static func checkVariants(_ chars: [Character]) -> [Finding] {
        var findings: [Finding] = []
        for pair in variantPairs {
            let kanjiHits = occurrences(chars, Array(pair.kanji), pair.formal, kanjiSide: true,
                                        notAfter: pair.kanjiNotAfter, precededBy: pair.precededBy,
                                        notBefore: pair.notBefore)
            let kanaHits = occurrences(chars, Array(pair.kana), pair.formal, kanjiSide: false,
                                       notAfter: pair.kanaNotAfter, precededBy: pair.precededBy,
                                       notBefore: pair.notBefore)
            guard !kanjiHits.isEmpty, !kanaHits.isEmpty else { continue }
            // 少ない方を指摘する（多い方に揃える方が直す手間が少ない）。同数なら仮名側
            let kanjiIsFewer = kanjiHits.count < kanaHits.count
            let fewer = kanjiIsFewer ? kanjiHits : kanaHits
            let fewerWord = kanjiIsFewer ? pair.kanji : pair.kana
            let otherWord = kanjiIsFewer ? pair.kana : pair.kanji
            let otherCount = kanjiIsFewer ? kanaHits.count : kanjiHits.count
            for at in fewer {
                findings.append(Finding(
                    start: at, end: at + fewerWord.count, kind: .variant,
                    note: "「\(otherWord)」が\(otherCount)箇所あります",
                    spots: [at..<(at + fewerWord.count)]))
            }
        }
        return findings
    }

    private static func occurrences(
        _ chars: [Character], _ word: [Character], _ formal: Bool, kanjiSide: Bool,
        notAfter: String, precededBy: String, notBefore: String
    ) -> [Int] {
        guard !word.isEmpty, chars.count >= word.count else { return [] }
        var result: [Int] = []
        for idx in 0...(chars.count - word.count) {
            guard Array(chars[idx..<(idx + word.count)]) == word else { continue }
            let before: Character = idx > 0 ? chars[idx - 1] : " "
            let end = idx + word.count
            let after: Character = end < chars.count ? chars[end] : "\n"
            if !notAfter.isEmpty, idx > 0, notAfter.contains(before) { continue }
            if !notBefore.isEmpty, notBefore.contains(after) { continue }
            if !precededBy.isEmpty, !precededBy.contains(before) { continue }
            if formal {
                // 直後が助詞や句読点でなければ、複合語の一部（記事・事故など）とみなす
                if !afterFormal.contains(after) { continue }
                // **形式名詞は連体形の語尾に続くときだけ。** 直前が平仮名であることを
                // 仮名側にも求める。文頭の「ところが」「ところで」「ことに」「ときに」は
                // 接続の働きで、漢字で書くことはない。直前が句点や改行になるので、
                // この1つの条件でまとめて外れる（個別に並べても切りがない）
                if precededBy.isEmpty, !isHiragana(before) { continue }
            }
            result.append(idx)
        }
        return result
    }

    // ---------- 表記ゆれ（全角と半角） ----------

    /// 同じ語が全角と半角の両方で出ている箇所。
    ///
    /// **全角と半角が同居していること自体は問題にしない。**
    /// 媒体によっては「単語は全角、単位は半角」のように意図して使い分けるため。
    /// ただし**登録された単位だけは別扱い**で、揃っているかを問わず半角を促す。
    private static func checkWidthVariants(_ chars: [Character]) -> [Finding] {
        var findings: [Finding] = []

        // ① 単位（km・km/h など）。揃っているかを問わず、全角なら半角を促す
        var unitRanges: [Range<Int>] = []
        var u = 0
        while u < chars.count {
            guard let range = Units.unitRange(chars, at: u) else {
                u += 1
                continue
            }
            unitRanges.append(range)
            let form = String(chars[range])
            if Units.hasFullWidth(form) {
                findings.append(Finding(
                    start: range.lowerBound, end: range.upperBound, kind: .variant,
                    note: "単位は半角が一般的です（\(form) → \(Units.toHalfWidth(form))）",
                    spots: [range]))
            }
            u = range.upperBound
        }

        // ② 単位以外は、同じ語が両方の幅で出ているときだけ指摘する。
        //    英数字の連なりは**数字と英字の境目で区切る**（「100km」と「85ｋｍ」を
        //    丸ごと比べると数字が違うだけで別の語になり、単位の揺れを見つけられない）
        var runs: [(Int, String)] = []
        var i = 0
        while i < chars.count {
            guard isAlnum(chars[i]) else {
                i += 1
                continue
            }
            let start = i
            let digit = isDigit(chars[i])
            while i < chars.count, isAlnum(chars[i]), isDigit(chars[i]) == digit { i += 1 }
            runs.append((start, String(chars[start..<i])))
        }
        let others = runs.filter { at, _ in !unitRanges.contains { $0.contains(at) } }
        for (_, group) in Dictionary(grouping: others, by: { Units.toHalfWidth($0.1) }) {
            let byForm = Dictionary(grouping: group, by: { $0.1 })
            guard byForm.count >= 2 else { continue }
            let sorted = byForm.sorted { $0.value.count < $1.value.count }
            guard let fewer = sorted.first, let other = sorted.last else { continue }
            let label = Units.hasFullWidth(other.key) ? "全角" : "半角"
            for (at, form) in fewer.value {
                findings.append(Finding(
                    start: at, end: at + form.count, kind: .variant,
                    note: "\(label)の「\(other.key)」が\(other.value.count)箇所あります",
                    spots: [at..<(at + form.count)]))
            }
        }
        return findings
    }

    // ---------- 打鍵ミス（助詞の重複） ----------

    /// 取りこぼしにくい重複だけを見る。
    /// 「のの」は「彼ののち」、「でで」は「木でできた」、「とと」は「彼とともに」で
    /// 誤検出するので入れていない
    private static let doubledParticles = ["がが", "をを", "にに", "へへ"]

    private static func checkTypos(_ chars: [Character]) -> [Finding] {
        var findings: [Finding] = []
        for pattern in doubledParticles {
            let p = Array(pattern)
            guard chars.count >= p.count else { continue }
            for idx in 0...(chars.count - p.count) {
                guard Array(chars[idx..<(idx + p.count)]) == p else { continue }
                guard looksLikeParticle(chars, idx) else { continue }
                findings.append(Finding(
                    start: idx, end: idx + p.count, kind: .typo,
                    note: "「\(pattern)」と重なっています", spots: [idx..<(idx + p.count)]))
            }
        }
        return findings
    }
}
