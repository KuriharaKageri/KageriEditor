import Cocoa

/// 版の履歴パネル。左に版の一覧（新しい順）、右にその版の本文。
/// 「この版に戻す」で、持ち主の文書の本文をその版に差し替える。
///
/// Android版は一覧→中身のドリルダウンだが、Macは画面が広いので、
/// 一覧を出したまま中身を見比べられるように一画面にしている（使い方ガイドと同じ考え方）。
final class VersionHistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private weak var ownerDocument: Document?
    private let identity: String
    private var entries: [VersionHistory.Entry] = []

    private let tableView = NSTableView()
    private let previewView = NSTextView()
    private let restoreButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var appearanceObserver: NSObjectProtocol?

    private static let sameYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d HH:mm"
        return f
    }()
    private static let otherYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/M/d HH:mm"
        return f
    }()

    static func timeLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let f = cal.component(.year, from: date) == cal.component(.year, from: Date()) ? sameYear : otherYear
        return f.string(from: date)
    }

    deinit {
        if let o = appearanceObserver { NotificationCenter.default.removeObserver(o) }
    }

    init(document: Document, identity: String, title: String) {
        self.ownerDocument = document
        self.identity = identity
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        panel.title = "版の履歴 — \(title)"
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 520, height: 320)
        super.init(window: panel)
        buildUI()
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let listScroll = NSScrollView()
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .bezelBorder
        tableView.headerView = nil
        tableView.rowHeight = ListAppearance.rowHeight(lines: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.width = 220
        tableView.addTableColumn(column)
        listScroll.documentView = tableView
        appearanceObserver = ListAppearance.observeChanges { [weak self] in
            guard let self else { return }
            self.tableView.rowHeight = ListAppearance.rowHeight(lines: 2)
            self.tableView.reloadData()
        }

        let previewScroll = NSScrollView()
        previewScroll.translatesAutoresizingMaskIntoConstraints = false
        previewScroll.hasVerticalScroller = true
        previewScroll.borderType = .bezelBorder
        previewView.isEditable = false
        previewView.isSelectable = true
        previewView.isRichText = false
        previewView.textContainerInset = NSSize(width: 8, height: 8)
        previewView.isVerticallyResizable = true
        previewView.autoresizingMask = [.width]
        previewView.textContainer?.widthTracksTextView = true
        previewScroll.documentView = previewView

        restoreButton.translatesAutoresizingMaskIntoConstraints = false
        restoreButton.title = "この版に戻す"
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreSelected)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = ListAppearance.captionFont
        emptyLabel.lineBreakMode = .byTruncatingTail

        content.addSubview(listScroll)
        content.addSubview(previewScroll)
        content.addSubview(restoreButton)
        content.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            listScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            listScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            listScroll.widthAnchor.constraint(equalToConstant: 240),
            listScroll.bottomAnchor.constraint(equalTo: restoreButton.topAnchor, constant: -10),

            previewScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            previewScroll.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 10),
            previewScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            previewScroll.bottomAnchor.constraint(equalTo: restoreButton.topAnchor, constant: -10),

            restoreButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            restoreButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),

            emptyLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            emptyLabel.centerYAnchor.constraint(equalTo: restoreButton.centerYAnchor),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: restoreButton.leadingAnchor, constant: -10),
        ])
        if let font = ownerDocument?.editorFont { previewView.font = font }
    }

    /// 一覧を読み直す（開いたとき・戻したあと）
    func reload() {
        entries = HistoryStore.shared.list(identity)
        tableView.reloadData()
        if entries.isEmpty {
            emptyLabel.stringValue = "まだ版がありません（保存すると残ります）"
            previewView.string = ""
            restoreButton.isEnabled = false
        } else {
            emptyLabel.stringValue = "\(entries.count)つの版"
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            showPreview(row: 0)
        }
    }

    private func showPreview(row: Int) {
        guard row >= 0, row < entries.count else { return }
        let text = HistoryStore.shared.read(identity, entries[row])
        previewView.string = text ?? "（この版を読めませんでした）"
        previewView.scrollToBeginningOfDocument(nil)
        restoreButton.isEnabled = text != nil
    }

    // ---------- 一覧 ----------

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let e = entries[row]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        let head = NSTextField(labelWithString: Self.timeLabel(e.date))
        head.font = ListAppearance.boldFont
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: e.chars), number: .decimal)
        let sub = NSTextField(labelWithString: "\(e.reason.label)　\(formatted)字")
        sub.font = ListAppearance.captionFont
        sub.textColor = .secondaryLabelColor
        stack.addArrangedSubview(head)
        stack.addArrangedSubview(sub)
        return stack
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        showPreview(row: tableView.selectedRow)
    }

    @objc private func restoreSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count, let document = ownerDocument,
              let text = HistoryStore.shared.read(identity, entries[row]) else { return }
        if document.restoreVersion(text: text, identity: identity) {
            reload()
        }
    }
}
