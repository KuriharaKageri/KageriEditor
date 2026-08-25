import Cocoa

/// 検索結果一覧の1件（Android版のMatchEntryと同じ考え方）。
/// lineは表示行（折り返しを含む、行番号ガターと同じ数え方）。
/// snippet中の[hlStart,hlEnd)が検索語の強調表示対象。
private struct DocMatchEntry {
    let start: Int
    let end: Int
    let line: Int
    let snippet: String
    let hlStart: Int
    let hlEnd: Int
}

// ============================================================
// 一覧パネル共通の見た目
// ============================================================
/// 検索結果一覧・推敲・見出しの3つのパネルが共通で使う文字サイズ。
///
/// ディスプレイの解像度や設定によっては既定の12ポイントが小さく感じるため、
/// 設定で変えられるようにしている。**本文の文字サイズとは別に持つ**——
/// 一覧は補助的な表示なので、本文と同じ大きさにすると場所を取りすぎるため。
enum ListAppearance {

    static let defaultSize: Double = 12

    static var size: CGFloat {
        let v = UserDefaults.standard.double(forKey: "listFontSize")
        return CGFloat(v > 0 ? v : defaultSize)
    }

    static var font: NSFont { NSFont.systemFont(ofSize: size) }
    static var boldFont: NSFont { NSFont.boldSystemFont(ofSize: size) }

    /// 見出し行（種類・行番号・説明）や枚数に使う、少し小さい字
    static var captionSize: CGFloat { max(9, size - 2) }
    static var captionFont: NSFont { NSFont.systemFont(ofSize: captionSize) }

    /// 1行の高さ。linesは1行の表示に使う行数（推敲だけ見出し行＋本文の2行）
    static func rowHeight(lines: Int) -> CGFloat {
        lines <= 1 ? size * 1.85 : size * 1.85 + captionSize * 1.7 + 4
    }

    /// 設定で文字サイズが変わったことを知らせる。
    /// 開いたままの一覧にもすぐ反映するために使う（戻り値は解除用のトークン）
    static func observeChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in handler() }
    }
}

/// 検索語の前後に表示する文字数（これを超える分は…で省略する）
private let matchContextChars = 18

/// 検索結果一覧パネル: 検索語に一致する全箇所を表示行番号・前後の文脈つきで列挙し、
/// クリックした箇所へジャンプする（置換は⌘⌥Fの検索/置換バーでそのまま行える）。
final class MatchListWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    private weak var textView: NSTextView?
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private var matches: [DocMatchEntry] = []
    private var appearanceObserver: NSObjectProtocol?

    deinit {
        if let o = appearanceObserver { NotificationCenter.default.removeObserver(o) }
    }

    convenience init(textView: NSTextView, initialQuery: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        panel.title = "検索結果一覧"
        panel.isReleasedWhenClosed = false
        self.init(window: panel)
        self.textView = textView
        buildUI()
        searchField.stringValue = initialQuery
        runSearch()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "検索語"
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.delegate = self

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        tableView.headerView = nil
        tableView.rowHeight = ListAppearance.rowHeight(lines: 1)
        appearanceObserver = ListAppearance.observeChanges { [weak self] in
            guard let self else { return }
            self.tableView.rowHeight = ListAppearance.rowHeight(lines: 1)
            self.tableView.reloadData()
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.usesAlternatingRowBackgroundColors = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.width = 380
        tableView.addTableColumn(column)
        scroll.documentView = tableView

        content.addSubview(searchField)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    @objc private func searchFieldChanged() { runSearch() }

    func controlTextDidChange(_ obj: Notification) { runSearch() }

    private func runSearch() {
        let query = searchField.stringValue
        guard !query.isEmpty, let tv = textView else {
            matches = []
            tableView.reloadData()
            window?.title = "検索結果一覧"
            return
        }
        matches = MatchListWindowController.findAllMatches(in: tv, query: query)
        tableView.reloadData()
        window?.title = matches.isEmpty ? "検索結果一覧（見つかりません）" : "検索結果一覧（\(matches.count)件）"
    }

    /// 検索語に一致する全箇所を、位置・表示行番号・ヒット箇所前後のスニペット付きで列挙する
    private static func findAllMatches(in tv: NSTextView, query: String) -> [DocMatchEntry] {
        guard let lm = tv.layoutManager else { return [] }
        let full = tv.string as NSString
        guard full.length > 0, !query.isEmpty else { return [] }

        // 表示行（折り返しを含む）ごとの開始位置を1回の走査で集めておき、
        // 各ヒットの表示行番号を二分探索で求める（行番号ガターと同じ数え方）
        var lineStarts: [Int] = []
        var glyphIndex = 0
        let numberOfGlyphs = lm.numberOfGlyphs
        while glyphIndex < numberOfGlyphs {
            var fragmentRange = NSRange()
            _ = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &fragmentRange)
            let charRange = lm.characterRange(forGlyphRange: fragmentRange, actualGlyphRange: nil)
            lineStarts.append(charRange.location)
            glyphIndex = NSMaxRange(fragmentRange)
        }
        if lineStarts.isEmpty { lineStarts.append(0) }

        func displayLine(for charIndex: Int) -> Int {
            var lo = 0, hi = lineStarts.count - 1, ans = 0
            while lo <= hi {
                let mid = (lo + hi) / 2
                if lineStarts[mid] <= charIndex { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
            }
            return ans + 1
        }

        func indexOfNewline(before index: Int) -> Int {
            guard index > 0 else { return -1 }
            let r = full.rangeOfCharacter(from: .newlines, options: .backwards,
                                          range: NSRange(location: 0, length: index))
            return r.location == NSNotFound ? -1 : r.location
        }
        func indexOfNewline(from index: Int) -> Int {
            guard index < full.length else { return -1 }
            let r = full.rangeOfCharacter(from: .newlines, options: [],
                                          range: NSRange(location: index, length: full.length - index))
            return r.location == NSNotFound ? -1 : r.location
        }

        var result: [DocMatchEntry] = []
        var searchLoc = 0
        while searchLoc <= full.length {
            let range = full.range(of: query, options: .caseInsensitive,
                                   range: NSRange(location: searchLoc, length: full.length - searchLoc))
            if range.location == NSNotFound { break }

            let line = displayLine(for: range.location)

            let paraStart = indexOfNewline(before: range.location) + 1
            let paraEndRaw = indexOfNewline(from: NSMaxRange(range))
            let paraEnd = paraEndRaw == -1 ? full.length : paraEndRaw

            let snipStart = max(range.location - matchContextChars, paraStart)
            let snipEnd = min(NSMaxRange(range) + matchContextChars, paraEnd)
            let prefix = snipStart > paraStart ? "…" : ""
            let suffix = snipEnd < paraEnd ? "…" : ""
            let body = full.substring(with: NSRange(location: snipStart, length: snipEnd - snipStart))
            let snippet = prefix + body + suffix

            let hlStart = (prefix as NSString).length + (range.location - snipStart)
            let hlEnd = hlStart + range.length

            result.append(DocMatchEntry(start: range.location, end: NSMaxRange(range),
                                        line: line, snippet: snippet, hlStart: hlStart, hlEnd: hlEnd))
            searchLoc = NSMaxRange(range)
        }
        return result
    }

    // ---------- NSTableViewDataSource / Delegate ----------

    func numberOfRows(in tableView: NSTableView) -> Int { matches.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("matchCell")
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField) ?? {
            let tf = NSTextField(labelWithString: "")
            tf.identifier = identifier
            tf.lineBreakMode = .byTruncatingTail
            tf.cell?.usesSingleLineMode = true
            return tf
        }()

        let m = matches[row]
        let label = "\(m.line)行目：\(m.snippet)"
        let content = NSMutableAttributedString(string: label, attributes: [
            .font: ListAppearance.font,
            .foregroundColor: NSColor.labelColor,
        ])
        let prefixLength = (label as NSString).length - (m.snippet as NSString).length
        let hlRange = NSRange(location: prefixLength + m.hlStart, length: m.hlEnd - m.hlStart)
        if hlRange.location >= 0, NSMaxRange(hlRange) <= content.length {
            content.addAttribute(.font, value: ListAppearance.boldFont, range: hlRange)
            content.addAttribute(.foregroundColor, value: NSColor.systemRed, range: hlRange)
        }
        field.attributedStringValue = content
        return field
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < matches.count, let tv = textView else { return }
        let m = matches[row]
        let range = NSRange(location: m.start, length: m.end - m.start)
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(range)
        tv.scrollRangeToVisible(range)
    }
}
