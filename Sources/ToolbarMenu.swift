import Cocoa

// ============================================================
// 日付・時刻の文字列整形（Android版 formatCurrentDate/Time と同じ3書式ずつ）
// ============================================================
enum DateTimeFormat {
    static let dateFormatSamples = ["2026年07月13日", "2026-07-13", "20260713"]
    static let timeFormatSamples = ["13:05", "13時05分", "午後1時05分"]

    static func currentDateString(formatIndex: Int) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        let y = c.year ?? 0, m = c.month ?? 0, d = c.day ?? 0
        switch formatIndex {
        case 1: return String(format: "%04d-%02d-%02d", y, m, d)
        case 2: return String(format: "%04d%02d%02d", y, m, d)
        default: return String(format: "%04d年%02d月%02d日", y, m, d)
        }
    }

    static func currentTimeString(formatIndex: Int) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: Date())
        let h24 = c.hour ?? 0
        let minuteStr = String(format: "%02d", c.minute ?? 0)
        switch formatIndex {
        case 1:
            return "\(h24)時\(minuteStr)分"
        case 2:
            let ampm = h24 < 12 ? "午前" : "午後"
            let h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24)
            return "\(ampm)\(h12)時\(minuteStr)分"
        default:
            return String(format: "%02d:%02d", h24, c.minute ?? 0)
        }
    }
}

// ============================================================
// ツールバーボタン1個の定義（キー・表示名・動作）
// ============================================================
struct MenuButtonDef {
    let key: String
    let label: String
    let action: () -> Void
}

// ============================================================
// ウインドウ上部のカスタマイズ可能なメニューボタン列
// （Android版の下部タッチメニューと同じ考え方: 並び順・表示/非表示を
//   UserDefaultsの "menuOrder" / "menuHidden" に保存する。
//   Mac版独自の追加として、項目間に空白を挟む「スペース」を挿入できる）
// ============================================================
final class MenuBarView: NSView {

    static let orderChangedNotification = Notification.Name("KageriMenuOrderChanged")

    /// メニューバーに並べられる全項目のキーと表示名。
    /// もとはAndroid版の20項目からMacに機能のない「パッド」を除いたものに、
    /// Mac独自の項目（検索結果一覧・印刷）を足したもの。
    /// 使用頻度の低い項目（別名保存・ファイル名変更・印刷・保存せず閉じる・閲覧モード・設定・使い方）は
    /// メニューバーには置かず、右端「⋮」のプルダウンにまとめている。
    static let labelDefs: [(key: String, label: String)] = [
        ("new", "新規"),
        ("memo", "メモ"),
        ("open", "開く"),
        ("history", "履歴"),
        ("save", "保存"),
        ("selectall", "全選択"),
        ("cut", "カット"),
        ("copy", "コピー"),
        ("paste", "ペースト"),
        ("undo", "元に戻す"),
        ("redo", "やり直す"),
        ("date", "日付"),
        ("time", "時刻"),
        ("search", "検索"),
        ("matchlist", "一覧"),
        ("wrap", "整形"),
        ("removenl", "非整形"),
        ("blankline", "空行除去"),
        // キーは "removespace" のまま据え置き。変えるとユーザーが保存した並び順から
        // 外れて末尾へ飛ぶため、ラベルと中身だけを差し替えている
        ("removespace", "原稿支援"),
        ("close", "閉じる"),
    ]

    /// 既定の並び順（ユーザー指定、2026-07-19／2.0で見直し）。labelDefsの定義順とは別に、
    /// スペースを挟んだ意味のあるグルーピングを既定から用意する。
    static let defaultOrder: [String] = [
        "new", "memo", "open", "history", "spacer",
        "selectall", "cut", "copy", "paste", "spacer",
        "search", "matchlist", "spacer",
        "date", "time", "spacer",
        "undo", "redo", "spacer",
        "wrap", "removenl", "blankline", "removespace", "spacer",
        "save", "close",
    ]

    static func loadOrder() -> [String] {
        guard let saved = UserDefaults.standard.string(forKey: "menuOrder") else { return defaultOrder }
        let known = Set(defaultOrder)
        var order = saved.split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0 == "spacer" || known.contains($0) }
        for key in defaultOrder where !order.contains(key) { order.append(key) }
        return order
    }

    static func loadHidden() -> Set<String> {
        guard let saved = UserDefaults.standard.string(forKey: "menuHidden") else { return [] }
        return Set(saved.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private var defsByKey: [String: MenuButtonDef] = [:]

    /// 右端の「⋮」。押されたときに出すメニューは持ち主（Document）が組み立てる
    private let overflowButton = NSButton()
    var onOverflowClicked: (() -> Void)?

    /// 「⋮」ボタン（プルダウンの表示位置の基準に使う）
    var overflowAnchor: NSView { overflowButton }

    /// trueにすると、ボタン列を薄いまま押せない状態にする（閲覧モード用）。
    /// 隠さずに残すのは、ステータスバーの位置を動かさないため。
    /// 「⋮」は閲覧モードから戻る入口なので、薄くも無効にもしない。
    var isDimmedForReading: Bool = false {
        didSet {
            scrollView.alphaValue = isDimmedForReading ? 0.3 : 1.0
            for view in stack.arrangedSubviews {
                (view as? NSButton)?.isEnabled = !isDimmedForReading
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // 自分では何も描画しないと、背後（行番号ルーラー等）の描画がボタンの隙間から
    // 透けて見えることがあるため、常に不透明な背景を明示的に塗っておく。
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false

        stack.orientation = .horizontal
        stack.spacing = 0
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = stack

        // 右端の「⋮」。ボタン列がどれだけ長くなっても隠れないよう、
        // スクロール領域の外側に固定で置く
        overflowButton.translatesAutoresizingMaskIntoConstraints = false
        overflowButton.title = "⋮"
        overflowButton.bezelStyle = .regularSquare
        overflowButton.isBordered = false
        overflowButton.font = NSFont.systemFont(ofSize: 15)
        overflowButton.target = self
        overflowButton.action = #selector(overflowClicked(_:))
        overflowButton.setContentHuggingPriority(.required, for: .horizontal)
        overflowButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(scrollView)
        addSubview(overflowButton)
        addSubview(separator)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: overflowButton.leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            overflowButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            overflowButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            overflowButton.widthAnchor.constraint(equalToConstant: 24),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func overflowClicked(_ sender: Any?) {
        onOverflowClicked?()
    }

    /// 項目定義を登録して表示を組み立てる（ウインドウ生成時に1回呼ぶ）
    func reload(defs: [MenuButtonDef]) {
        defsByKey = Dictionary(uniqueKeysWithValues: defs.map { ($0.key, $0) })
        rebuild()
    }

    /// 並び順・表示/非表示（UserDefaults）が変わった時に呼び直す
    func rebuild() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let hidden = MenuBarView.loadHidden()
        var needsDivider = false
        for key in MenuBarView.loadOrder() {
            if key == "spacer" {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                spacer.widthAnchor.constraint(equalToConstant: 20).isActive = true
                stack.addArrangedSubview(spacer)
                needsDivider = false
                continue
            }
            guard let def = defsByKey[key] else { continue }
            if hidden.contains(key) && key != "settings" { continue }

            if needsDivider {
                let divider = NSBox()
                divider.boxType = .separator
                divider.translatesAutoresizingMaskIntoConstraints = false
                divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
                divider.heightAnchor.constraint(equalToConstant: 16).isActive = true
                stack.addArrangedSubview(divider)
            }

            let button = NSButton(title: def.label, target: self, action: #selector(buttonTapped(_:)))
            button.bezelStyle = .recessed
            button.font = NSFont.systemFont(ofSize: 12)
            button.identifier = NSUserInterfaceItemIdentifier(key)
            stack.addArrangedSubview(button)
            needsDivider = true
        }
    }

    /// 履歴などのポップアップメニューを、対応するボタンの直下に表示するためのアンカー
    func button(for key: String) -> NSButton? {
        stack.arrangedSubviews.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == key
        }
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue, let def = defsByKey[key] else { return }
        def.action()
    }
}

// ============================================================
// 「メニューの編集」パネル: チェックで表示/非表示、行のドラッグで並べ替え、
// 「スペースを追加」でボタンの間に空白を挿入できる（Android版のRecyclerView編集画面と
// 同じ操作感を、NSTableViewの標準的な行ドラッグ並べ替えパターンで実装）
// ============================================================
final class MenuEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private static let dragType = NSPasteboard.PasteboardType("local.kageri.menuOrderRow")

    private var order: [String] = MenuBarView.loadOrder()
    private var hidden: Set<String> = MenuBarView.loadHidden()
    private let tableView = NSTableView()

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        panel.title = "メニューの編集"
        panel.isReleasedWhenClosed = false
        self.init(window: panel)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let hint = NSTextField(wrappingLabelWithString:
            "チェックでボタンの表示/非表示を切り替えます。右端の「≡」をドラッグすると並べ替えられます。「設定」は常に表示されます。")
        hint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.rowHeight = 30
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.registerForDraggedTypes([Self.dragType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.width = 320
        tableView.addTableColumn(column)
        scroll.documentView = tableView

        let addSpacerButton = NSButton(title: "スペースを追加", target: self, action: #selector(addSpacer))
        let resetButton = NSButton(title: "既定に戻す", target: self, action: #selector(resetToDefault))
        let cancelButton = NSButton(title: "キャンセル", target: self, action: #selector(cancelTapped))
        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveTapped))
        saveButton.keyEquivalent = "\r"
        for b in [addSpacerButton, resetButton, cancelButton, saveButton] {
            b.bezelStyle = .rounded
            b.controlSize = .small
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonRow = NSStackView(views: [addSpacerButton, resetButton, spacer, cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(hint)
        content.addSubview(scroll)
        content.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -12),

            buttonRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    // ---------- NSTableViewDataSource / Delegate ----------

    func numberOfRows(in tableView: NSTableView) -> Int { order.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard order.indices.contains(row) else { return nil }
        let key = order[row]
        let rowView = NSStackView()
        rowView.orientation = .horizontal
        rowView.spacing = 8
        rowView.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)

        if key == "spacer" {
            let label = NSTextField(labelWithString: "── スペース ──")
            label.textColor = .tertiaryLabelColor
            label.font = NSFont.systemFont(ofSize: 12)
            let filler = NSView()
            filler.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let delete = NSButton(title: "削除", target: self, action: #selector(deleteRow(_:)))
            delete.bezelStyle = .inline
            delete.controlSize = .small
            delete.tag = row
            rowView.addArrangedSubview(label)
            rowView.addArrangedSubview(filler)
            rowView.addArrangedSubview(delete)
        } else {
            let title = MenuBarView.labelDefs.first { $0.key == key }?.label ?? key
            let check = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxToggled(_:)))
            check.state = hidden.contains(key) ? .off : .on
            check.isEnabled = key != "settings"
            check.tag = row
            let filler = NSView()
            filler.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let handle = NSTextField(labelWithString: "≡")
            handle.textColor = .tertiaryLabelColor
            handle.font = NSFont.systemFont(ofSize: 15)
            rowView.addArrangedSubview(check)
            rowView.addArrangedSubview(filler)
            rowView.addArrangedSubview(handle)
        }
        return rowView
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.dragType)
        return item
    }

    func tableView(
        _ tableView: NSTableView, validateDrop info: NSDraggingInfo,
        proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        dropOperation == .above ? .move : []
    }

    func tableView(
        _ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
        row: Int, dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let pbItem = info.draggingPasteboard.pasteboardItems?.first,
              let str = pbItem.string(forType: Self.dragType), let from = Int(str),
              order.indices.contains(from) else { return false }
        var to = row
        if from < to { to -= 1 }
        to = min(max(to, 0), order.count - 1)
        guard from != to else { return false }
        let moved = order.remove(at: from)
        order.insert(moved, at: to)
        tableView.reloadData()
        return true
    }

    // ---------- アクション ----------

    @objc private func checkboxToggled(_ sender: NSButton) {
        guard order.indices.contains(sender.tag) else { return }
        let key = order[sender.tag]
        if sender.state == .on { hidden.remove(key) } else { hidden.insert(key) }
    }

    @objc private func deleteRow(_ sender: NSButton) {
        guard order.indices.contains(sender.tag) else { return }
        order.remove(at: sender.tag)
        tableView.reloadData()
    }

    @objc private func addSpacer() {
        order.append("spacer")
        tableView.reloadData()
        tableView.scrollRowToVisible(order.count - 1)
    }

    @objc private func resetToDefault() {
        order = MenuBarView.defaultOrder
        hidden = []
        tableView.reloadData()
    }

    @objc private func cancelTapped() {
        window?.close()
    }

    @objc private func saveTapped() {
        UserDefaults.standard.set(order.joined(separator: ","), forKey: "menuOrder")
        UserDefaults.standard.set(hidden.joined(separator: ","), forKey: "menuHidden")
        NotificationCenter.default.post(name: MenuBarView.orderChangedNotification, object: nil)
        window?.close()
    }
}
