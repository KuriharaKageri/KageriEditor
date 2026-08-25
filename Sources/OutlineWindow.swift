import Cocoa

/// 見出し一覧パネル: 見出しを並べ、クリックした箇所へジャンプする。
/// 見出しごとに、そこから次の見出しまでの原稿用紙の枚数を添える。
/// プロットとして見出しだけを先に並べる書き方だと、これがそのまま進捗表になる
/// （まだ本文のない見出しは「—」と出る）。**本文には触れない**。
final class OutlineWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private weak var textView: NSTextView?
    private let tableView = NSTableView()
    private var headings: [Outline.Heading] = []
    private var appearanceObserver: NSObjectProtocol?
    private var textObserver: NSObjectProtocol?

    // ---- 並べ替えモード ----
    /// 並べ替え中か。**適用するまで本文には触れない**別モード
    private var reordering = false
    private var sections: [Outline.Section] = []
    /// いまの並び（元の節の番号と、置きたい段）
    private var rows: [Outline.Placed] = []
    /// ドラッグを始めた横位置。落とした位置との差で段を決める
    private var dragStartX: CGFloat = 0

    /**
     * いま自分で本文を書き換えている最中か。
     *
     * 「本文が変わったらやめる」という見張りは、**外から編集されたとき**のためのもの。
     * 適用のときの書き換えにも反応してしまい、成功しているのに
     * 「やめました」と出ていた（実機で発覚）。
     */
    private var applyingEdit = false
    // ---- 確定モード（推定した見出しに印を打つ） ----
    /// 推定で拾った候補に、書き手が確認して印を打っている最中か
    private var confirming = false
    private var candidates: [Outline.Heading] = []
    private var checkedFlags: [Bool] = []

    private let startButton = NSButton()
    private let applyButton = NSButton()
    private let cancelButton = NSButton()
    private let hintLabel = NSTextField(labelWithString: "")

    /// 段が変わる横のずれ（pt）。位置だけ動かしたいのに手が横にぶれて
    /// 段が変わらないよう、広めに取る
    private let levelDragThreshold: CGFloat = 40

    deinit {
        if let o = appearanceObserver { NotificationCenter.default.removeObserver(o) }
        if let o = textObserver { NotificationCenter.default.removeObserver(o) }
    }

    convenience init?(textView: NSTextView) {
        let found = Outline.headings(textView.string)
        guard !found.isEmpty else { return nil }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        // 目次と推敲は、まだ実際の原稿で調整を続けている段階なので「β版」と断る
        panel.title = Outline.hasMarks(textView.string)
            ? "目次（\(found.count)件）β版" : "目次（推定 \(found.count)件）β版"
        panel.isReleasedWhenClosed = false
        self.init(window: panel)
        self.textView = textView
        headings = found
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

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
        // 並べ替えに入るまでドラッグは禁じておく（beginReorder で許可する）
        tableView.setDraggingSourceOperationMask([], forLocal: true)
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.usesAlternatingRowBackgroundColors = true
        let title = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        title.width = 320
        tableView.addTableColumn(title)
        let sheets = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sheets"))
        sheets.width = 70
        tableView.addTableColumn(sheets)
        scroll.documentView = tableView

        content.addSubview(scroll)

        for (button, title, action) in [
            (startButton, "並べ替え", #selector(startPressed)),
            (cancelButton, "キャンセル", #selector(cancelPressed)),
            (applyButton, "適用", #selector(applyPressed)),
        ] {
            button.title = title
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
            button.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(button)
        }
        applyButton.keyEquivalent = "\r"
        hintLabel.font = ListAppearance.captionFont
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: startButton.topAnchor, constant: -10),

            startButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            startButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            cancelButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            cancelButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            applyButton.leadingAnchor.constraint(
                equalTo: cancelButton.trailingAnchor, constant: 8),
            applyButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            hintLabel.leadingAnchor.constraint(
                equalTo: applyButton.trailingAnchor, constant: 10),
            hintLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            hintLabel.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
        ])

        // 本文が変わると、覚えている位置がすべてずれる。パネルは閉じずに
        // 開いたままなので、変更を見張って作り直す
        if let tv = textView {
            textObserver = NotificationCenter.default.addObserver(
                forName: NSText.didChangeNotification, object: tv, queue: .main
            ) { [weak self] _ in self?.textDidChangeOutside() }
        }
        updateMode()
    }

    // ---------- 並べ替えモード ----------

    /// 並べ替えは印のある文書でだけ出す。推定見出しのまま動かすと、
    /// 誤検出したところで段落が途中から動いてしまう
    private func updateMode() {
        let sectionCount = textView.map { Outline.sections($0.string).count } ?? 0
        let marked = sectionCount > 0
        let busy = reordering || confirming
        // 印がある文書は並べ替えへ、ない文書は推定した見出しの確定へ進む
        startButton.title = marked ? "並べ替え" : "印を打つ"
        startButton.isHidden = busy || (marked ? sectionCount < 2 : headings.isEmpty)
        cancelButton.isHidden = !busy
        applyButton.isHidden = !busy
        applyButton.title = confirming ? "印を打つ" : "適用"
        if reordering {
            hintLabel.stringValue = "上下で位置、右へずらすと小見出し。適用するまで本文は変わりません。"
        } else if confirming {
            hintLabel.stringValue = "本当の見出しだけを残してください。選ばなかった行は本文に戻ります。"
        } else if marked {
            hintLabel.stringValue = ""
        } else {
            hintLabel.stringValue = "推定で拾った見出しです。印を打つと確定できます。"
        }
        tableView.usesAlternatingRowBackgroundColors = !busy
        tableView.reloadData()
    }

    @objc private func startPressed() {
        if (textView.map { Outline.hasMarks($0.string) } ?? false) {
            beginReorder()
        } else {
            beginConfirm()
        }
    }

    @objc private func cancelPressed() {
        if confirming { endConfirm(reload: false) } else { cancelReorder() }
    }

    @objc private func applyPressed() {
        if confirming { applyMarks() } else { applyReorder() }
    }

    // ---------- 推定した見出しを確定する ----------

    /// **推定は候補を出すところまで**で、どれが本当の見出しかは書き手が決める。
    /// 雑誌の割り付け原稿のように、柱やキャプションが同じ見た目で並ぶ文書では、
    /// 規則だけで本文の見出しと見分けることはできない。面倒な探索だけを機械が
    /// やって、判断は人が持つ、という分担にする。
    private func beginConfirm() {
        guard !headings.isEmpty else { return }
        candidates = headings
        // 初期はすべて外しておく。**どれが本当の見出しかは書き手が決める**もので、
        // 全部入りから始めると、確かめずにそのまま押してしまいやすい
        checkedFlags = Array(repeating: false, count: candidates.count)
        confirming = true
        // 行番号と枚数を並べるぶん、右の列を広げる
        tableView.tableColumns.last?.width = 120
        window?.title = "印を打つ見出しを選ぶ"
        updateMode()
    }

    private func endConfirm(reload: Bool) {
        confirming = false
        tableView.setDraggingSourceOperationMask([], forLocal: true)
        candidates = []
        checkedFlags = []
        tableView.tableColumns.last?.width = 70
        if reload, let tv = textView { headings = Outline.headings(tv.string) }
        window?.title = titleForList()
        updateMode()
    }

    /// 選ばれた行に印を打つ。1回の書き換えなので取り消しも1回で戻る
    private func applyMarks() {
        guard let tv = textView else { return }
        let starts = candidates.indices.filter { checkedFlags[$0] }.map { candidates[$0].start }
        guard let patch = Outline.applyMarks(tv.string, lineStarts: starts) else {
            let alert = NSAlert()
            alert.messageText = "印を打つ見出しが選ばれていません"
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        tv.window?.makeKeyAndOrderFront(nil)
        tv.window?.makeFirstResponder(tv)
        applyingEdit = true
        tv.insertText(
            patch.replacement,
            replacementRange: NSRange(location: patch.start, length: patch.end - patch.start))
        applyingEdit = false
        endConfirm(reload: true)
    }

    @objc private func checkToggled(_ sender: NSButton) {
        guard checkedFlags.indices.contains(sender.tag) else { return }
        checkedFlags[sender.tag] = sender.state == .on
    }

    /// 推定であることを題に出す。出さないと「この原稿にはN個の節がある」と
    /// 誤解されうる（推定は本文の見出しのほかに、柱やキャプションも拾う）
    private func titleForList() -> String {
        let marked = textView.map { Outline.hasMarks($0.string) } ?? false
        return marked
            ? "目次（\(headings.count)件）β版" : "目次（推定 \(headings.count)件）β版"
    }

    @objc private func beginReorder() {
        guard let tv = textView else { return }
        sections = Outline.sections(tv.string)
        guard sections.count >= 2 else { return }
        rows = sections.indices.map { Outline.Placed($0, sections[$0].level) }
        reordering = true
        tableView.registerForDraggedTypes([.string])
        // これを許可しないと、同じ表の中でのドラッグが始まらない
        tableView.setDraggingSourceOperationMask([.move], forLocal: true)
        tableView.draggingDestinationFeedbackStyle = .gap
        window?.title = "並べ替え（\(rows.count)件）"
        updateMode()
    }

    @objc private func cancelReorder() {
        endReorder(reload: false)
    }

    private func endReorder(reload: Bool) {
        reordering = false
        rows = []
        sections = []
        tableView.unregisterDraggedTypes()
        // **並べ替えモードの外ではドラッグを許さない。**
        // 通常の目次で掴めてしまうと、行が持ち上がったまま戻らないことがある
        // （実機で「掴んだ項目が消える」として報告された）
        tableView.setDraggingSourceOperationMask([], forLocal: true)
        if reload, let tv = textView { headings = Outline.headings(tv.string) }
        window?.title = titleForList()
        updateMode()
    }

    /// 並べ替え中に本文が編集されたら、覚えている位置が全部ずれるのでやめる
    private func textDidChangeOutside() {
        guard !applyingEdit else { return }
        guard let tv = textView else { return }
        // 覚えている位置が本文の中のどこを指すかは、編集された時点で分からなくなる。
        // そのまま印を打ったり並べ替えたりすると、狙いと違う場所を書き換えてしまう
        if reordering || confirming {
            let what = reordering ? "並べ替え" : "印を打つの"
            if reordering { endReorder(reload: true) } else { endConfirm(reload: true) }
            let alert = NSAlert()
            alert.messageText = "本文が変わったので、\(what)をやめました"
            alert.informativeText = "見出しの位置がずれるためです。もう一度やり直してください。"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } else {
            headings = Outline.headings(tv.string)
            window?.title = titleForList()
            updateMode()
        }
    }

    @objc private func applyReorder() {
        guard let tv = textView else { return }
        // 本文が変わっていれば計画は当てられない（節の数が合わなくなる）
        guard Outline.sections(tv.string).count == rows.count,
              let patch = Outline.reorderPatch(tv.string, plan: rows)
        else {
            let alert = NSAlert()
            alert.messageText = "並びは変わっていません"
            alert.informativeText = "本文が変わっている場合も、そのままでは適用できません。"
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        tv.window?.makeKeyAndOrderFront(nil)
        tv.window?.makeFirstResponder(tv)
        let range = NSRange(location: patch.start, length: patch.end - patch.start)
        applyingEdit = true
        tv.insertText(patch.replacement, replacementRange: range)
        applyingEdit = false
        let caret = NSRange(location: patch.start, length: 0)
        tv.setSelectedRange(caret)
        tv.scrollRangeToVisible(caret)
        endReorder(reload: true)
    }

    /// その位置から始まる塊の大きさ（大見出しなら続く小見出しを含む）
    private func groupSize(at index: Int) -> Int {
        guard rows.indices.contains(index) else { return 0 }
        if rows[index].level >= 2 { return 1 }
        var n = 1
        while index + n < rows.count, rows[index + n].level >= 2 { n += 1 }
        return n
    }

    /// 大見出しの落とし先を章の境目へ寄せる。
    /// 章と章の間にしか落ちないので、掴んだ章の中身が置き去りになったり、
    /// 他の章の途中へ割り込んだりしない
    private func snapToChapterBoundary(_ index: Int) -> Int {
        var i = index
        while i < rows.count, rows[i].level >= 2 { i += 1 }
        return i
    }
}

extension OutlineWindowController {

    // ---------- 並べ替えのドラッグ ----------

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard reordering else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: .string)
        return item
    }

    /// 掴んだ横位置を控える。落とした位置との差が段の変更になる
    func tableView(
        _ tableView: NSTableView, draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet
    ) {
        guard let window = tableView.window else { return }
        let inWindow = window.convertPoint(fromScreen: screenPoint)
        dragStartX = tableView.convert(inWindow, from: nil).x
    }

    func tableView(
        _ tableView: NSTableView, validateDrop info: NSDraggingInfo,
        proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard reordering, dropOperation == .above else { return [] }
        return .move
    }

    func tableView(
        _ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
        row: Int, dropOperation dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard reordering,
              let raw = info.draggingPasteboard.pasteboardItems?.first?.string(forType: .string),
              let from = Int(raw), rows.indices.contains(from)
        else { return false }

        let size = groupSize(at: from)
        var dest = row
        if rows[from].level <= 1 { dest = snapToChapterBoundary(dest) }
        // 掴んだ塊の中には落とせない
        if dest >= from, dest <= from + size { return false }

        let block = Array(rows[from..<(from + size)])
        rows.removeSubrange(from..<(from + size))
        let insertAt = dest > from ? dest - size : dest
        rows.insert(contentsOf: block, at: insertAt)

        // 横のずれで段を決める。ずれが小さければ位置だけ動かしたとみなす
        let dropX = tableView.convert(info.draggingLocation, from: nil).x
        let dx = dropX - dragStartX
        if abs(dx) >= levelDragThreshold {
            let want = dx > 0 ? 2 : 1
            // 最初の見出しが小見出しになるのは許す（印を打つのは書き手の自由で、
            // アプリが禁じると「なぜ動かないのか」が分からなくなる）
            if rows[insertAt].level != want {
                rows[insertAt] = Outline.Placed(rows[insertAt].index, want)
            }
        }
        tableView.reloadData()
        return true
    }

    // ---------- NSTableViewDataSource / Delegate ----------

    func numberOfRows(in tableView: NSTableView) -> Int {
        if reordering { return rows.count }
        if confirming { return candidates.count }
        return headings.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if reordering { return reorderCell(tableView, tableColumn, row) }
        if confirming { return confirmCell(tableView, tableColumn, row) }
        guard headings.indices.contains(row) else { return nil }
        let h = headings[row]
        let isSheets = tableColumn?.identifier.rawValue == "sheets"
        let identifier = NSUserInterfaceItemIdentifier(isSheets ? "sheetsCell" : "titleCell")
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField) ?? {
            let tf = NSTextField(labelWithString: "")
            tf.identifier = identifier
            tf.lineBreakMode = .byTruncatingTail
            tf.cell?.usesSingleLineMode = true
            if isSheets {
                tf.alignment = .right
                tf.textColor = .secondaryLabelColor
            }
            return tf
        }()
        // 設定で変えたときに、作り直さずとも反映されるよう毎回入れ直す
        field.font = isSheets ? ListAppearance.captionFont : ListAppearance.font
        if isSheets {
            // まだ本文が無い見出しは「—」。プロット段階でどこが未着手か分かる
            field.stringValue = h.sheets <= 0 ? "—" : "\(formatSheets(h.sheets))枚"
        } else {
            // 小見出しは一段下げて、大見出しとの関係が一目で分かるようにする
            field.stringValue = (h.level >= 2 ? "　　" : "") + h.title
        }
        return field
    }

    /// 並べ替え中の行。右端に、掴めることが分かるようツマミを出す
    private func reorderCell(
        _ tableView: NSTableView, _ tableColumn: NSTableColumn?, _ row: Int
    ) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let placed = rows[row]
        let isHandle = tableColumn?.identifier.rawValue == "sheets"
        let identifier = NSUserInterfaceItemIdentifier(isHandle ? "handleCell" : "reorderCell")
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField) ?? {
            let tf = NSTextField(labelWithString: "")
            tf.identifier = identifier
            tf.lineBreakMode = .byTruncatingTail
            tf.cell?.usesSingleLineMode = true
            if isHandle {
                tf.alignment = .right
                tf.textColor = .tertiaryLabelColor
            }
            return tf
        }()
        field.font = isHandle ? ListAppearance.captionFont : ListAppearance.font
        if isHandle {
            field.stringValue = "≡"
        } else {
            field.stringValue = (placed.level >= 2 ? "　　" : "") + sections[placed.index].title
        }
        return field
    }

    /// 確定モードの行。チェックボックスと、判断の材料（行番号と枚数）を出す
    private func confirmCell(
        _ tableView: NSTableView, _ tableColumn: NSTableColumn?, _ row: Int
    ) -> NSView? {
        guard candidates.indices.contains(row) else { return nil }
        let h = candidates[row]
        if tableColumn?.identifier.rawValue == "sheets" {
            let id = NSUserInterfaceItemIdentifier("confirmInfo")
            let tf = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? {
                let t = NSTextField(labelWithString: "")
                t.identifier = id
                t.alignment = .right
                t.textColor = .secondaryLabelColor
                t.cell?.usesSingleLineMode = true
                return t
            }()
            tf.font = ListAppearance.captionFont
            // まだ本文が無い見出しは「—」。柱やキャプションを見分ける手がかりになる
            tf.stringValue = "\(h.line)行目・" + (h.sheets <= 0 ? "—" : "\(formatSheets(h.sheets))枚")
            return tf
        }
        let id = NSUserInterfaceItemIdentifier("confirmCheck")
        let box = (tableView.makeView(withIdentifier: id, owner: self) as? NSButton) ?? {
            let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkToggled(_:)))
            b.identifier = id
            b.lineBreakMode = .byTruncatingTail
            return b
        }()
        box.font = ListAppearance.font
        box.title = (h.level >= 2 ? "　　" : "") + h.title
        box.tag = row
        box.state = checkedFlags[row] ? .on : .off
        return box
    }

    private func formatSheets(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    @objc private func rowClicked() {
        // 並べ替え中は本文がまだ動いていないので、飛ぶと元の位置へ行ってしまう。
        // 確定中はチェックの操作が主なので、こちらも移動しない
        guard !reordering, !confirming else { return }
        let row = tableView.clickedRow
        guard row >= 0, row < headings.count, let tv = textView else { return }
        let h = headings[row]
        let length = (tv.string as NSString).length
        let start = min(h.start, length)
        let range = NSRange(location: start, length: min(h.end, length) - start)
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(range)
        tv.scrollRangeToVisible(range)
    }
}
