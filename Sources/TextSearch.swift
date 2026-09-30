import Foundation

/// 全文検索（保存フォルダのすべてを探す）の、探し方の決まりごと。
///
/// - **全角と半角、大文字と小文字は区別しない**（NFKC ＋ 小文字。「ＵＲＬ」でも「url」でも見つかる）
/// - **空白で区切ると「どれも含むファイル」**を探す（「京都 雨」＝京都にも雨にも触れているファイル）
/// - ひらがなとカタカナは区別する（同じにすると、関係ないものまで出てくる）
/// - 正規表現・あいまい検索は無し
///
/// Android版の `TextSearch.kt` と同じ規則。**位置はすべてUTF-16**で数える
/// （NSRangeと同じ単位。選択と強調にそのまま使えるようにするため）。
/// 画面から独立した純粋関数だけを置く（Tests/test.swift で守っている）。
enum TextSearch {

    /// 探すために揃えた文字列。揃えた1文字ごとに、元の文字列のどこから来たかを持つ
    /// （「ｶﾞ」2文字 →「ガ」1文字、「㈱」1文字 →「(株)」3文字、のように長さが変わるため）
    struct Folded {
        let units: [UInt16]
        /// 揃えた1文字ごとの、元の文字列での開始位置。
        /// **終わりの位置は持たない。** Int32 1本にすることで覚えておく量が
        /// 1文字あたり16バイトから4バイトに減る。終わりは「次のまとまりの始まり」から出せる
        fileprivate let from: [Int32]
        /// 元の文字列の長さ（最後のまとまりの終わりに使う）
        fileprivate let length: Int

        /// 揃えた文字列の [start, end) を、元の文字列の範囲に戻す
        func original(_ start: Int, _ end: Int) -> NSRange {
            let s = Int(from[start])
            // end-1 と同じまとまりから来た文字を読み飛ばし、次のまとまりの始まりを終わりとする
            var j = end - 1
            let base = from[j]
            while j + 1 < from.count, from[j + 1] == base { j += 1 }
            let e = j + 1 < from.count ? Int(from[j + 1]) : length
            return NSRange(location: s, length: e - s)
        }
    }

    /// NFKCでも小文字化でも変わらない、日本語でよく使う文字
    private static func isStable(_ c: UInt16) -> Bool {
        switch c {
        case 0x3041...0x3096: return true   // ひらがな
        case 0x30A1...0x30FA: return true   // カタカナ（全角）
        case 0x4E00...0x9FFF: return true   // 漢字
        case 0x3400...0x4DBF: return true   // 漢字（拡張A）
        case 0x3001, 0x3002, 0x30FC: return true // 、。ー
        default: return false
        }
    }

    /// そこにある符号位置（サロゲートペアなら2つぶんをまとめて1つ）
    private static func codePoint(_ s: NSString, at index: Int) -> (value: UInt32, length: Int)? {
        guard index < s.length else { return nil }
        let c = s.character(at: index)
        if c >= 0xD800, c <= 0xDBFF, index + 1 < s.length {
            let low = s.character(at: index + 1)
            if low >= 0xDC00, low <= 0xDFFF {
                let v = 0x10000 + (UInt32(c - 0xD800) << 10) + UInt32(low - 0xDC00)
                return (v, 2)
            }
        }
        return (UInt32(c), 1)
    }

    /// 異体字セレクタか（見た目の違いだけなので、探すときは無いものとする）
    private static func isVariationSelector(_ v: UInt32) -> Bool {
        (0xFE00...0xFE0F).contains(v) || (0xE0100...0xE01EF).contains(v)
    }

    /// そこに前の文字へ付く印（濁点・結合文字・異体字セレクタ）があるか
    private static func isMark(_ s: NSString, at index: Int) -> Bool {
        guard let (v, _) = codePoint(s, at: index) else { return false }
        if v == 0xFF9E || v == 0xFF9F { return true }   // 半角の濁点・半濁点
        if isVariationSelector(v) { return true }
        guard let scalar = Unicode.Scalar(v) else { return false }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    /// 揃える。探す側の本文と探す言葉の両方に同じものをかける
    static func fold(_ s: NSString) -> Folded {
        var units = [UInt16]()
        var from = [Int32]()
        units.reserveCapacity(s.length)
        from.reserveCapacity(s.length)

        var i = 0
        while i < s.length {
            let c = s.character(at: i)
            // よく出る文字は、そのままか小文字にするだけ
            // （ここを速く通すのが、全文検索の速さになる。実測で3倍以上違う）
            if c < 0x80 {
                units.append(c >= 0x41 && c <= 0x5A ? c + 32 : c)
                from.append(Int32(i))
                i += 1
                continue
            }
            if isStable(c), !isMark(s, at: i + 1) {
                units.append(c)
                from.append(Int32(i))
                i += 1
                continue
            }
            // 1文字＋それに付く濁点・結合文字をひとまとまりにして揃える
            var end = i + (codePoint(s, at: i)?.length ?? 1)
            while isMark(s, at: end) {
                end += codePoint(s, at: end)?.length ?? 1
            }
            // **異体字セレクタは揃える前に落とす。** 補助面のもの（「𠮷」「葛」「辻」に付く）は
            // 2文字ぶんの並びなので、揃えたあとに1文字ずつ見て落とす書き方では取りこぼす
            var chunk = String()
            var k = i
            while k < end {
                guard let (v, len) = codePoint(s, at: k) else { break }
                if !isVariationSelector(v), let scalar = Unicode.Scalar(v) {
                    chunk.unicodeScalars.append(scalar)
                }
                k += len
            }
            // **NFKCのあとにNFCをかける。** `precomposedStringWithCompatibilityMapping` だけだと
            // 「ｶﾞ」が「カ」＋結合濁点のまま返り、precomposedな「ガ」と一致しなくなる（実測）
            let folded = chunk.precomposedStringWithCompatibilityMapping
                .precomposedStringWithCanonicalMapping
                .lowercased()
            for u in folded.utf16 {
                units.append(u)
                from.append(Int32(i))
            }
            i = end
        }
        return Folded(units: units, from: from, length: s.length)
    }

    /// 探す言葉を、揃えたうえで空白で区切る。空なら何も探さない
    static func terms(_ query: String) -> [[UInt16]] {
        let folded = fold(query as NSString)
        let text = String(decoding: folded.units, as: UTF16.self)
        var seen = Set<String>()
        var result = [[UInt16]]()
        for part in text.split(whereSeparator: { $0.isWhitespace }) {
            let word = String(part)
            if seen.insert(word).inserted { result.append(Array(word.utf16)) }
        }
        return result
    }

    /// units の中で term が現れる位置（from 以降で最初のもの）。無ければ nil
    private static func indexOf(_ units: [UInt16], _ term: [UInt16], from: Int) -> Int? {
        guard !term.isEmpty, units.count >= term.count else { return nil }
        let last = units.count - term.count
        guard from <= last else { return nil }
        for start in from...last {
            var matched = true
            for k in 0..<term.count where units[start + k] != term[k] {
                matched = false
                break
            }
            if matched { return start }
        }
        return nil
    }

    /// 揃えた文字の並びに、言葉がすべて含まれているか。
    /// **位置の対応（from/to）を持たずに絞り込める**ので、たくさんのファイルを
    /// 覚えておくときに使う（位置は当たったファイルだけで作り直す）
    static func containsAll(_ units: [UInt16], terms: [[UInt16]]) -> Bool {
        guard !terms.isEmpty else { return false }
        for term in terms where indexOf(units, term, from: 0) == nil { return false }
        return true
    }

    /// 1ファイルの中で見つかった箇所（元の文字列での範囲、前から順）。
    /// **言葉のどれか1つでも無ければ空**（空白区切りは「どれも含む」）
    static func find(_ text: NSString, terms: [[UInt16]]) -> [NSRange] {
        find(text, terms: terms, folded: fold(text))
    }

    /// 揃えた結果を使い回せる形。同じ本文を何度も探すときに、揃える処理を省くために使う
    static func find(_ text: NSString, terms: [[UInt16]], folded: Folded) -> [NSRange] {
        guard !terms.isEmpty else { return [] }
        var hits = [NSRange]()
        for term in terms {
            var found = false
            var at = indexOf(folded.units, term, from: 0)
            while let index = at {
                found = true
                hits.append(folded.original(index, index + term.count))
                at = indexOf(folded.units, term, from: index + term.count)
            }
            if !found { return [] }
        }
        hits.sort { $0.location < $1.location }
        // 言葉どうしが重なったら（「京都」と「都」など）1つにまとめる
        var merged = [NSRange]()
        for h in hits {
            if let last = merged.last, h.location <= NSMaxRange(last) {
                let end = max(NSMaxRange(last), NSMaxRange(h))
                merged[merged.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                merged.append(h)
            }
        }
        return merged
    }

    /// 一覧に出す、見つかった所の前後。hitsはsnippetの中での範囲
    struct Snippet: Equatable {
        let text: String
        let hits: [NSRange]
    }

    /// 最初に見つかった所の前後を切り出す。**段落（改行）をまたがない**。
    /// 前は短め、後ろは長めに取る（言葉のあとに続く文を読めば、何の話か分かることが多い）
    static func snippet(_ text: NSString, hits: [NSRange], before: Int = 12, after: Int = 40) -> Snippet {
        guard let first = hits.first else { return Snippet(text: "", hits: []) }
        let paraStart: Int = {
            var i = first.location - 1
            while i >= 0 {
                if text.character(at: i) == 0x0A { return i + 1 }
                i -= 1
            }
            return 0
        }()
        let paraEnd: Int = {
            var i = NSMaxRange(first)
            while i < text.length {
                if text.character(at: i) == 0x0A { return i }
                i += 1
            }
            return text.length
        }()
        // 後ろが段落の終わりで足りなければ、そのぶん前を多めに取る
        let spare = max(0, after - (paraEnd - NSMaxRange(first)))
        let start = max(paraStart, first.location - before - spare)
        let end = max(NSMaxRange(first), min(paraEnd, NSMaxRange(first) + after))
        let prefix = start > paraStart ? "…" : ""
        let suffix = end < paraEnd ? "…" : ""
        let shift = prefix.utf16.count - start
        let inside = hits.filter { $0.location >= start && NSMaxRange($0) <= end }
            .map { NSRange(location: $0.location + shift, length: $0.length) }
        let body = text.substring(with: NSRange(location: start, length: end - start))
        return Snippet(text: prefix + body + suffix, hits: inside)
    }
}
