import Foundation

/// 本文の中のURL（http・https）を見つける。Windows版・Android版と同じ規則。
///
/// 本文は1文字も書き換えず、URLの範囲だけを返す。画面は、その範囲に色と下線を（一時的な属性で）当て、
/// 閲覧モードではクリック、編集中は ⌘クリックで、既定のブラウザーで開く。
///
/// 見つけ方：
/// ・「http://」「https://」で始まるもの（大文字小文字は区別しない）。www. だけのもの・ftp・file・mailto などは対象外
/// ・URLの中身は ASCII の範囲だけ。**日本語の文章では、URLのすぐあとに全角の文字・句読点・かっこが続く**ので、
///   ASCII でない文字、空白、改行、引用符（"）、< > \ ^ ` { | } で切る
///   （日本語のまま書かれたURLは、ASCII の部分までがリンクになる）
/// ・末尾の . , ; : ! ? ' * は含めない。かっこ ) ] は、URLの中で対になっていれば含め、閉じるほうが多ければ外す
///   （「(see https://a.example)」や Wikipedia の「…/Foo_(bar)」の両方で、期待どおりになる）
/// ・「xhttps://」のように英数字のすぐあとの http は、ほかの語の一部とみなして対象外
/// ・「https://」のあとが英数字でなければ（空・「/」・日本語）、URLとみなさない
enum UrlLinks {

    /// 閲覧モードの「[文字](URL)」の、文字の範囲と行き先。範囲は MarkdownPreview の印と同じ数え方（Character の位置）
    struct Target: Equatable {
        let start: Int
        let end: Int
        let url: String
    }

    /// URLの範囲（UTF-16 の位置。NSTextView の範囲と同じ数え方。始まりの順・重ならない）
    static func find(_ string: String) -> [NSRange] {
        let text = Array(string.utf16)
        var result: [NSRange] = []
        var i = 0
        while i < text.count {
            guard let p = indexOfHttp(text, from: i) else { break }
            let bodyStart = schemeEnd(text, p)
            if bodyStart < 0 || (p > 0 && isAsciiAlnum(text[p - 1])) {
                i = p + 4
                continue
            }
            var end = bodyStart
            while end < text.count && isUrlChar(text[end]) { end += 1 }
            end = trimTail(text, bodyStart, end)
            // 「https://」のあとが英数字で始まっていなければ、URLとはみなさない
            if end > bodyStart && isAsciiAlnum(text[bodyStart]) {
                result.append(NSRange(location: p, length: end - p))
            }
            i = max(end, p + 4)
        }
        return result
    }

    /// 「[文字](URL)」の、文字の範囲と行き先。URLのあとの空白以降（"題名" など）と < > は除く。
    /// 行き先が空のものは含めない。開けるかどうか（http・https だけ）は、開く側が決める
    static func linkTargets(_ text: [Character], marks: [MarkdownPreview.Mark]) -> [Target] {
        var result: [Target] = []
        for m in marks where m.kind == .link {
            let open = m.end // 「]」の位置
            guard open + 1 < text.count, text[open] == "]", text[open + 1] == "(" else { continue }
            var close = open + 2
            var found = false
            while close < text.count {
                if text[close] == ")" { found = true; break }
                if text[close] == "\n" || text[close] == "\r\n" || text[close] == "\r" { break }
                close += 1
            }
            guard found else { continue }
            var url = String(text[(open + 2)..<close]).trimmingCharacters(in: .whitespaces)
            if let space = url.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "\u{3000}" }) {
                url = String(url[url.startIndex..<space])
            }
            url = url.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            if !url.isEmpty && m.end > m.start { result.append(Target(start: m.start, end: m.end, url: url)) }
        }
        return result
    }

    /// ブラウザーで開いてよい行き先か。**http・https だけ**（ほかの形式は開かない）
    static func isOpenable(_ url: String) -> Bool {
        let lower = url.lowercased()
        return (lower.hasPrefix("http://") && lower.count > 7) || (lower.hasPrefix("https://") && lower.count > 8)
    }

    // ---------- 内部 ----------

    /// "http"（大文字小文字不問）の位置
    private static func indexOfHttp(_ text: [UInt16], from: Int) -> Int? {
        var i = from
        while i + 3 < text.count {
            if lower(text[i]) == 0x68, lower(text[i + 1]) == 0x74, lower(text[i + 2]) == 0x74, lower(text[i + 3]) == 0x70 {
                return i
            }
            i += 1
        }
        return nil
    }

    private static func lower(_ c: UInt16) -> UInt16 { (c >= 0x41 && c <= 0x5A) ? c + 32 : c }

    /// 「http://」「https://」の直後の位置。そうでなければ -1
    private static func schemeEnd(_ text: [UInt16], _ p: Int) -> Int {
        var i = p + 4 // "http" の次
        if i < text.count && lower(text[i]) == 0x73 { i += 1 } // s
        if i + 2 < text.count && text[i] == 0x3A && text[i + 1] == 0x2F && text[i + 2] == 0x2F { return i + 3 }
        return -1
    }

    private static func isAsciiAlnum(_ c: UInt16) -> Bool {
        (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39)
    }

    private static let urlSymbols: Set<UInt16> = Set("-._~:/?#[]@!$&'()*+,;=%".utf16)

    /// URLの中に置ける文字（ASCII の記号は RFC 3986 のもの）
    private static func isUrlChar(_ c: UInt16) -> Bool { isAsciiAlnum(c) || urlSymbols.contains(c) }

    /// URLの末尾に付いた句読点・対にならない閉じかっこを外した終わりの位置
    private static func trimTail(_ text: [UInt16], _ start: Int, _ end0: Int) -> Int {
        var end = end0
        let tailMarks = Set(".,;:!?'*".utf16)
        while end > start {
            let c = text[end - 1]
            if tailMarks.contains(c) {
                end -= 1
            } else if c == 0x29, count(text, start, end, 0x29) > count(text, start, end, 0x28) { // ) と (
                end -= 1
            } else if c == 0x5D, count(text, start, end, 0x5D) > count(text, start, end, 0x5B) { // ] と [
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    private static func count(_ text: [UInt16], _ start: Int, _ end: Int, _ c: UInt16) -> Int {
        var n = 0
        for i in start..<end where text[i] == c { n += 1 }
        return n
    }
}
