import Cocoa

/// 全文検索（保存フォルダのすべてを探す）の結果パネル。
///
/// Android版の `AllTextSearch.kt` と同じ規則。違うのは画面の出し方だけで、
/// Macには戻るボタンが無いので、**一覧は閉じずに出したまま**にする。
/// 行を押すとその文書へ移るので、Androidの「戻るボタンで一覧へ」と同じ使い勝手になる。
///
/// 本文の写し（Android版の SearchIndex）は持たない。Macではフォルダを丸ごと読んでも一瞬で
/// （実測：471件・24.6MBで0.084秒）、費用は揃える処理のほうにある。
/// そこで**揃えた本文だけを開いているあいだ覚えておく**（2回目からは探すだけで済む）。
final class AllTextSearchWindowController: NSWindowController, NSTableViewDataSource,
                                           NSTableViewDelegate, NSSearchFieldDelegate {

    /// 1ファイルぶんの結果
    private struct Result {
        let url: URL
        let name: String
        let modified: Date?
        let hits: [NSRange]
        /// 最初に見つかった所の文字そのもの（検索バーに入れて ▽ で進めるため）
        let firstWord: String
        let snippet: TextSearch.Snippet
    }

    /// 揃えた本文の覚え書き。キーはファイル名・更新日時・長さ
    private typealias Cache = [String: (text: NSString, folded: TextSearch.Folded)]

    private let searchField = NSSearchField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private var results: [Result] = []
    private var appearanceObserver: NSObjectProtocol?
    private var foldedCache: Cache = [:]

    /// 探し直したら古い検索を止めるための番号
    private var generation = 0
    private let queue = DispatchQueue(label: "local.kageri.alltextsearch", qos: .userInitiated)

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    deinit {
        if let o = appearanceObserver { NotificationCenter.default.removeObserver(o) }
    }

    convenience init(initialQuery: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        panel.title = "全文検索"
        panel.isReleasedWhenClosed = false
        self.init(window: panel)
        buildUI()
        searchField.stringValue = initialQuery
        if initialQuery.isEmpty {
            statusLabel.stringValue = "探す言葉を入れてください"
        } else {
            runSearch()
        }
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "保存フォルダのすべてを検索"
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.delegate = self

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = ListAppearance.captionFont
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        tableView.headerView = nil
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
        column.width = 480
        tableView.addTableColumn(column)
        scroll.documentView = tableView

        content.addSubview(searchField)
        content.addSubview(statusLabel)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            scroll.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    // ---------- 探す ----------

    @objc private func searchFieldChanged() { runSearch() }

    /// **打つたびには探さない。** Return（または虫めがね）で探す。
    /// 既存の検索結果一覧は打つたびに探すが、あちらは1文書、こちらはフォルダ全体が相手
    func controlTextDidChange(_ obj: Notification) {}

    private func runSearch() {
        let terms = TextSearch.terms(searchField.stringValue)
        generation += 1
        let gen = generation
        results = []
        tableView.reloadData()
        guard !terms.isEmpty else {
            statusLabel.stringValue = "探す言葉を入れてください"
            window?.title = "全文検索"
            return
        }
        let folder = Document.saveFolderURL
        // 開いている文書は、ファイルではなく画面の本文を探す（書きかけも見つかるように）
        var openTexts: [URL: NSString] = [:]
        for case let doc as Document in NSDocumentController.shared.documents {
            if let url = doc.fileURL, let text = doc.currentTextForSearch() {
                openTexts[url.standardizedFileURL] = text
            }
        }
        statusLabel.stringValue = "探しています…"
        let cache = foldedCache
        queue.async { [weak self] in
            let outcome = Self.search(folder: folder, terms: terms, openTexts: openTexts, cache: cache)
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.foldedCache = outcome.cache
                self.results = outcome.results
                self.tableView.reloadData()
                self.statusLabel.stringValue = Self.summary(
                    outcome.results, searched: outcome.searched, unreadable: outcome.unreadable)
                self.window?.title = outcome.results.isEmpty
                    ? "全文検索（見つかりません）"
                    : "全文検索（\(outcome.results.count)ファイル）"
            }
        }
    }

    /// 探す対象のファイルか。**「開く」の一覧と同じ決まり**にしている
    /// （「開くと出てくるのに探せない」を作らないため）
    static func isTarget(_ name: String) -> Bool {
        if name.hasPrefix(".") || name.hasSuffix(".tmp") || name.hasSuffix(".bak")
            || name.hasSuffix(".tmp.bin") || name == "kageri_renames.json" { return false }
        return ["txt", "log", "md", "markdown"].contains((name as NSString).pathExtension.lowercased())
    }

    private struct Outcome {
        let results: [Result]
        let searched: Int
        let unreadable: Int
        let cache: Cache
    }

    private static func search(folder: URL, terms: [[UInt16]],
                               openTexts: [URL: NSString], cache: Cache) -> Outcome {
        var newCache = Cache()
        var results = [Result]()
        var searched = 0
        var unreadable = 0
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        for url in urls {
            let name = url.lastPathComponent
            guard isTarget(name) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == false { continue }
            let modified = values?.contentModificationDate
            let text: NSString
            if let open = openTexts[url.standardizedFileURL] {
                text = open
            } else if let data = try? Data(contentsOf: url) {
                text = decode(data)
            } else {
                // 読めないファイル（クラウドに実体が無い、権限が無いなど）は数えて飛ばす
                unreadable += 1
                continue
            }
            searched += 1
            // 揃えた本文は、同じファイル・同じ更新日時・同じ長さなら使い回す
            let key = "\(name)|\(modified?.timeIntervalSince1970 ?? 0)|\(text.length)"
            let folded = cache[key]?.folded ?? TextSearch.fold(text)
            newCache[key] = (text, folded)
            let hits = TextSearch.find(text, terms: terms, folded: folded)
            guard let first = hits.first else { continue }
            results.append(Result(
                url: url, name: name, modified: modified, hits: hits,
                firstWord: text.substring(with: first),
                snippet: TextSearch.snippet(text, hits: hits)))
        }
        // 更新の新しい順。**比較の中で重い処理をしない**（日時は上で引いてある）
        results.sort {
            let a = $0.modified?.timeIntervalSince1970 ?? 0
            let b = $1.modified?.timeIntervalSince1970 ?? 0
            return a == b ? $0.name < $1.name : a > b
        }
        return Outcome(results: results, searched: searched, unreadable: unreadable, cache: newCache)
    }

    /// アプリで開くときと同じ形にする（BOMを外し、改行はLFに）
    private static func decode(_ data: Data) -> NSString {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n") as NSString
    }

    private static func summary(_ results: [Result], searched: Int, unreadable: Int) -> String {
        let total = NumberFormatter.localizedString(from: NSNumber(value: searched), number: .decimal)
        let skipped = unreadable > 0 ? "、\(unreadable)ファイルは読めませんでした" : ""
        if results.isEmpty { return "見つかりませんでした（\(total)ファイルを探しました\(skipped)）" }
        let hits = results.reduce(0) { $0 + $1.hits.count }
        return "\(results.count)ファイル・\(hits)件で見つかりました（\(total)ファイルを探しました\(skipped)）"
    }

    // ---------- 一覧 ----------

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = results[row]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)

        let time = r.modified.map { "　" + Self.timeFormatter.string(from: $0) } ?? ""
        let head = NSMutableAttributedString(
            string: r.name, attributes: [.font: ListAppearance.boldFont])
        head.append(NSAttributedString(
            string: "\(time)　\(r.hits.count)件",
            attributes: [.font: ListAppearance.captionFont,
                         .foregroundColor: NSColor.secondaryLabelColor]))
        let title = NSTextField(labelWithAttributedString: head)
        title.lineBreakMode = .byTruncatingMiddle

        let body = NSMutableAttributedString(
            string: r.snippet.text, attributes: [.font: ListAppearance.font])
        for h in r.snippet.hits where NSMaxRange(h) <= body.length {
            // 見つかった言葉は琥珀色の地に太字（Android版と同じ）
            body.addAttribute(.backgroundColor,
                              value: NSColor.systemOrange.withAlphaComponent(0.35), range: h)
            body.addAttribute(.font, value: ListAppearance.boldFont, range: h)
        }
        let snippet = NSTextField(labelWithAttributedString: body)
        snippet.lineBreakMode = .byTruncatingTail

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(snippet)
        return stack
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < results.count else { return }
        let r = results[row]
        let terms = TextSearch.terms(searchField.stringValue)
        let word = r.firstWord
        let near = r.hits.first?.location ?? 0
        NSDocumentController.shared.openDocument(withContentsOf: r.url, display: true) { doc, _, error in
            if let error {
                NSAlert(error: error).runModal()
                return
            }
            // 一覧を作ったあとで本文が変わっていることもあるので、開いた本文で探し直し、
            // 控えた位置にいちばん近い当たりを選ぶ
            (doc as? Document)?.revealSearchHit(near: near, terms: terms, word: word)
        }
    }
}
