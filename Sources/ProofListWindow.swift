import Cocoa

/// 一覧に出す1行ぶん。snippet中のhighlightsを赤くする
private struct ProofRow {
    let finding: ProofCheck.Finding
    let line: Int
    let snippet: String
    /// snippet の中で赤くする範囲（複数、UTF-16）
    let highlights: [NSRange]
}

/// 赤く示す箇所の前後に足す文脈の文字数
private let proofContextChars = 14

/// 推敲パネル: 気になる箇所を種類のしぼりこみつきで並べ、
/// クリックした箇所へジャンプする。**本文は書き換えない**。
final class ProofListWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private weak var textView: NSTextView?
    private let tableView = NSTableView()
    private let filterBar = NSStackView()
    private var allRows: [ProofRow] = []
    private var shown: [ProofRow] = []
    private var chips: [(NSButton, ProofCheck.Kind?)] = []
    private var appearanceObserver: NSObjectProtocol?

    deinit {
        if let o = appearanceObserver { NotificationCenter.default.removeObserver(o) }
    }

    convenience init?(textView: NSTextView) {
        let text = textView.string
        // 選択範囲があればその範囲だけを見る（整形・原稿支援と同じ扱い）
        let selection = textView.selectedRange()
        let hasSelection = selection.length > 0
        let full = text as NSString
        let target = hasSelection ? full.substring(with: selection) : text
        let offset = hasSelection ? selection.location : 0

        let findings = ProofCheck.run(target).map {
            ProofCheck.Finding(start: $0.start + offset, end: $0.end + offset, kind: $0.kind,
                               note: $0.note,
                               spots: $0.spots.map { ($0.lowerBound + offset)..<($0.upperBound + offset) })
        }
        guard !findings.isEmpty else { return nil }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        // 目次と推敲は、まだ実際の原稿で調整を続けている段階なので「β版」と断る
        panel.title = "気になる箇所（\(findings.count)件）β版"
        panel.isReleasedWhenClosed = false
        self.init(window: panel)
        self.textView = textView
        allRows = findings.map { Self.buildRow(full, $0) }
        shown = allRows
        buildUI()
        applyFilter(nil)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        filterBar.orientation = .horizontal
        filterBar.spacing = 4
        filterBar.translatesAutoresizingMaskIntoConstraints = false
        addChip("すべて \(allRows.count)", nil)
        for kind in ProofCheck.Kind.allCases {
            let count = allRows.filter { $0.finding.kind == kind }.count
            if count > 0 { addChip("\(kind.label) \(count)", kind) }
        }

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        tableView.headerView = nil
        // 見出し行＋本文の2行を出すので、検索結果一覧より行を高くする
        tableView.rowHeight = ListAppearance.rowHeight(lines: 2)
        appearanceObserver = ListAppearance.observeChanges { [weak self] in
            guard let self else { return }
            self.tableView.rowHeight = ListAppearance.rowHeight(lines: 2)
            self.tableView.reloadData()
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.usesAlternatingRowBackgroundColors = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.width = 520
        tableView.addTableColumn(column)
        scroll.documentView = tableView

        content.addSubview(filterBar)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            filterBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            filterBar.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -14),

            scroll.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    private func addChip(_ label: String, _ kind: ProofCheck.Kind?) {
        let button = NSButton(title: label, target: self, action: #selector(chipClicked(_:)))
        button.bezelStyle = .recessed
        button.setButtonType(.pushOnPushOff)
        button.controlSize = .small
        button.tag = kind.map { ProofCheck.Kind.allCases.firstIndex(of: $0) ?? 0 } ?? -1
        chips.append((button, kind))
        filterBar.addArrangedSubview(button)
    }

    @objc private func chipClicked(_ sender: NSButton) {
        applyFilter(chips.first { $0.0 === sender }?.1)
    }

    private func applyFilter(_ kind: ProofCheck.Kind?) {
        shown = kind == nil ? allRows : allRows.filter { $0.finding.kind == kind }
        for (chip, k) in chips { chip.state = (k == kind) ? .on : .off }
        tableView.reloadData()
    }

    // ---------- 行の組み立て ----------

    /// 指摘1件を一覧の1行に整える。
    ///
    /// 語尾の連続のように、指摘が数文にまたがることがある。全体をそのまま載せると
    /// 一覧が本文で埋まり、かといって長さで機械的に切ると**赤が文の途中で終わって
    /// 何を指しているのか分からなくなる**。
    /// そこで、**赤くする箇所（spots）の前後だけを切り出して「…」で繋ぐ**。
    /// 3つの語尾なら「…開業し【た。】…運ん【だ。】…増え【た。】」のように出る。
    private static func buildRow(_ full: NSString, _ f: ProofCheck.Finding) -> ProofRow {
        // 段落（空行で区切られたかたまり）の内側に収める。折り返しの改行はまたいでよい
        let paraStart = paragraphStart(full, f.start)
        let paraEnd = paragraphEnd(full, f.start)
        var line = 1
        for i in 0..<min(f.start, full.length) where full.character(at: i) == 0x0A { line += 1 }

        let rawSpots = f.spots.isEmpty ? [f.start..<f.end] : f.spots
        let spots = rawSpots
            .map { max($0.lowerBound, paraStart)..<min($0.upperBound, paraEnd) }
            .filter { $0.lowerBound < $0.upperBound }
        guard !spots.isEmpty else { return ProofRow(finding: f, line: line, snippet: "", highlights: []) }

        // 赤くする箇所の前後に文脈を足した窓を作り、重なるものは繋ぐ
        var windows: [Range<Int>] = []
        for spot in spots {
            let from = max(spot.lowerBound - proofContextChars, paraStart)
            let to = min(spot.upperBound + proofContextChars, paraEnd)
            if let last = windows.last, from <= last.upperBound {
                windows[windows.count - 1] = last.lowerBound..<max(last.upperBound, to)
            } else {
                windows.append(from..<to)
            }
        }

        var snippet = ""
        var highlights: [NSRange] = []
        for (index, w) in windows.enumerated() {
            if index == 0 {
                if w.lowerBound > paraStart { snippet += "…" }
            } else {
                snippet += "…"
            }
            let base = (snippet as NSString).length - w.lowerBound
            snippet += full.substring(with: NSRange(location: w.lowerBound, length: w.count))
            for spot in spots where spot.lowerBound >= w.lowerBound && spot.upperBound <= w.upperBound {
                highlights.append(NSRange(location: base + spot.lowerBound, length: spot.count))
            }
        }
        if let last = windows.last, last.upperBound < paraEnd { snippet += "…" }
        // 折り返しの改行はそのまま出すと行が縦に伸びるので空白に詰める
        return ProofRow(finding: f, line: line,
                        snippet: snippet.replacingOccurrences(of: "\n", with: " "),
                        highlights: highlights)
    }

    /// 空行で区切られた段落の始まり
    private static func paragraphStart(_ full: NSString, _ at: Int) -> Int {
        var i = at
        while i > 0 {
            let lineRange = full.lineRange(for: NSRange(location: max(i - 1, 0), length: 0))
            let text = full.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return NSMaxRange(lineRange) }
            if lineRange.location == 0 { return 0 }
            i = lineRange.location
        }
        return 0
    }

    /// 空行で区切られた段落の終わり
    private static func paragraphEnd(_ full: NSString, _ at: Int) -> Int {
        var i = min(at, full.length)
        while i < full.length {
            let lineRange = full.lineRange(for: NSRange(location: i, length: 0))
            let end = NSMaxRange(lineRange)
            if end >= full.length { return full.length }
            let nextRange = full.lineRange(for: NSRange(location: end, length: 0))
            let next = full.substring(with: nextRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if next.isEmpty {
                var e = end
                if e > 0, full.character(at: e - 1) == 0x0A { e -= 1 }
                return e
            }
            i = end
        }
        return full.length
    }

    // ---------- NSTableViewDataSource / Delegate ----------

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard shown.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("proofCell")
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField) ?? {
            let tf = NSTextField(labelWithString: "")
            tf.identifier = identifier
            tf.lineBreakMode = .byTruncatingTail
            tf.maximumNumberOfLines = 2
            return tf
        }()

        let r = shown[row]
        let head = "［\(r.finding.kind.label)］\(r.line)行目　\(r.finding.note)\n"
        let content = NSMutableAttributedString(string: head + r.snippet, attributes: [
            .font: ListAppearance.font,
            .foregroundColor: NSColor.labelColor,
        ])
        // 見出し行は小さめ・薄めにして、本文のスニペットを目立たせる
        let headRange = NSRange(location: 0, length: (head as NSString).length)
        content.addAttribute(.font, value: ListAppearance.captionFont, range: headRange)
        content.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: headRange)
        // 問題の箇所だけを検索結果一覧と同じく太字＋赤字にする
        for h in r.highlights {
            let range = NSRange(location: headRange.length + h.location, length: h.length)
            guard NSMaxRange(range) <= content.length else { continue }
            content.addAttribute(.font, value: ListAppearance.boldFont, range: range)
            content.addAttribute(.foregroundColor, value: NSColor.systemRed, range: range)
        }
        field.attributedStringValue = content
        return field
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < shown.count, let tv = textView else { return }
        let f = shown[row].finding
        let length = (tv.string as NSString).length
        let start = min(f.start, length)
        let range = NSRange(location: start, length: min(f.end, length) - start)
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(range)
        tv.scrollRangeToVisible(range)
    }
}
