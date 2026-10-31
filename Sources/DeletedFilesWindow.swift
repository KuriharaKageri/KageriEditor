import Cocoa

/// 「消したファイルを取り戻す」パネル（アプリに1つ）。左に、元のファイルが見当たらない文書の一覧、
/// 右上に版（いちばん新しい版が初めの選び）、右にその版の本文。「取り戻す」でファイルを作り直して開く。
///
/// 版の履歴パネルは名前のある文書からしか開けないため、消えたファイルの入口は「⋮」（どの文書からでも開ける）。
/// Windows版の DeletedFilesWindow と同じ作り。
final class DeletedFilesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    static var shared: DeletedFilesWindowController?

    private var orphans: [HistoryStore.Orphan] = []
    private var entries: [VersionHistory.Entry] = []

    private let tableView = NSTableView()
    private let versionPopup = NSPopUpButton()
    private let previewView = NSTextView()
    private let restoreButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private var appearanceObserver: NSObjectProtocol?

    deinit {
        if let o = appearanceObserver { NotificationCenter.default.removeObserver(o) }
    }

    /// 開く（すでに開いていれば、一覧を読み直して前へ出す）
    static func show() {
        if let existing = shared, existing.window?.isVisible == true {
            existing.reload()
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = DeletedFilesWindowController()
        shared = controller
        controller.window?.center()
        controller.showWindow(nil)
    }

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        panel.title = "消したファイルを取り戻す"
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 580, height: 340)
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
        column.width = 280
        tableView.addTableColumn(column)
        listScroll.documentView = tableView
        appearanceObserver = ListAppearance.observeChanges { [weak self] in
            guard let self else { return }
            self.tableView.rowHeight = ListAppearance.rowHeight(lines: 2)
            self.tableView.reloadData()
        }

        versionPopup.translatesAutoresizingMaskIntoConstraints = false
        versionPopup.target = self
        versionPopup.action = #selector(versionChanged)

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
        previewView.font = EditorTextView.savedFont()
        previewScroll.documentView = previewView

        restoreButton.translatesAutoresizingMaskIntoConstraints = false
        restoreButton.title = "取り戻す"
        restoreButton.bezelStyle = .rounded
        restoreButton.keyEquivalent = "\r"
        restoreButton.target = self
        restoreButton.action = #selector(restoreSelected)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = ListAppearance.captionFont
        statusLabel.lineBreakMode = .byTruncatingTail

        content.addSubview(listScroll)
        content.addSubview(versionPopup)
        content.addSubview(previewScroll)
        content.addSubview(restoreButton)
        content.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            listScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            listScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            listScroll.widthAnchor.constraint(equalToConstant: 290),
            listScroll.bottomAnchor.constraint(equalTo: restoreButton.topAnchor, constant: -10),

            versionPopup.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            versionPopup.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 10),
            versionPopup.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            previewScroll.topAnchor.constraint(equalTo: versionPopup.bottomAnchor, constant: 8),
            previewScroll.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 10),
            previewScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            previewScroll.bottomAnchor.constraint(equalTo: restoreButton.topAnchor, constant: -10),

            restoreButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            restoreButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            statusLabel.centerYAnchor.constraint(equalTo: restoreButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: restoreButton.leadingAnchor, constant: -10),
        ])
    }

    /// 一覧を読み直す（開いたとき・取り戻したあと）
    func reload() {
        orphans = HistoryStore.shared.listOrphans()
        tableView.reloadData()
        if orphans.isEmpty {
            statusLabel.stringValue = "取り戻せるファイルはありません"
            entries = []
            versionPopup.removeAllItems()
            versionPopup.isEnabled = false
            previewView.string = ""
            restoreButton.isEnabled = false
        } else {
            statusLabel.stringValue = "\(orphans.count)つのファイル"
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            showVersions(row: 0)
        }
    }

    private var selectedOrphan: HistoryStore.Orphan? {
        let row = tableView.selectedRow
        return row >= 0 && row < orphans.count ? orphans[row] : nil
    }

    private func showVersions(row: Int) {
        guard row >= 0, row < orphans.count else { return }
        entries = HistoryStore.shared.list(orphans[row].identity)
        versionPopup.removeAllItems()
        for e in entries {
            let formatted = NumberFormatter.localizedString(from: NSNumber(value: e.chars), number: .decimal)
            versionPopup.addItem(withTitle: "\(VersionHistoryWindowController.timeLabel(e.date))　\(e.reason.label)　\(formatted)字")
        }
        versionPopup.isEnabled = !entries.isEmpty
        if !entries.isEmpty { versionPopup.selectItem(at: 0) }
        showPreview()
    }

    private func showPreview() {
        let index = versionPopup.indexOfSelectedItem
        guard let orphan = selectedOrphan, index >= 0, index < entries.count else {
            previewView.string = ""
            restoreButton.isEnabled = false
            return
        }
        let text = HistoryStore.shared.read(orphan.identity, entries[index])
        previewView.string = text ?? "（この版を読めませんでした）"
        previewView.scrollToBeginningOfDocument(nil)
        restoreButton.isEnabled = text != nil
    }

    @objc private func versionChanged() { showPreview() }

    // ---------- 一覧 ----------

    func numberOfRows(in tableView: NSTableView) -> Int { orphans.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let o = orphans[row]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        let head = NSTextField(labelWithString: o.name)
        head.font = ListAppearance.boldFont
        head.lineBreakMode = .byTruncatingMiddle
        let sub = NSTextField(labelWithString: Self.caption(for: o))
        sub.font = ListAppearance.captionFont
        sub.textColor = .secondaryLabelColor
        sub.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(head)
        stack.addArrangedSubview(sub)
        return stack
    }

    private static func caption(for o: HistoryStore.Orphan) -> String {
        let last = "最後の保存 " + VersionHistoryWindowController.timeLabel(Date(timeIntervalSince1970: Double(o.lastTime) / 1000))
        // 片付けは、元のフォルダはあるのにファイルだけ無いときに限る（HistoryStore.cleanupOrphans）
        if !o.folderExists { return last + "・元のフォルダが見つかりません（片付けません）" }
        let days = VersionHistory.orphanDaysLeft(
            lastTime: o.lastTime, now: Int64(Date().timeIntervalSince1970 * 1000), calendar: .current)
        return last + "・あと\(days)日残ります"
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        showVersions(row: tableView.selectedRow)
    }

    // ---------- 取り戻す ----------

    /// 選んだ版の本文から、ファイルを作り直して開く。元のフォルダがあり同じ名前が無ければ元の場所、
    /// そうでなければ保存フォルダに（同じ名前があれば番号つき）。UTF-8・LF で書く。
    /// 履歴は新しい名前・場所へ移す（同じ場所・名前なら、そのまま続く）
    @objc private func restoreSelected() {
        let index = versionPopup.indexOfSelectedItem
        guard let orphan = selectedOrphan, index >= 0, index < entries.count,
              let text = HistoryStore.shared.read(orphan.identity, entries[index]) else { return }
        let path = HistoryStore.restorePath(of: orphan, saveFolder: Document.saveFolderURL.path) {
            FileManager.default.fileExists(atPath: $0)
        }
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "ファイルを作れませんでした"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window!)
            return
        }
        let newIdentity = HistoryStore.identity(of: url)
        if newIdentity != orphan.identity {
            HistoryStore.shared.move(from: orphan.identity, to: newIdentity, name: url.lastPathComponent)
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
            if let error, let window = self?.window {
                NSAlert(error: error).beginSheetModal(for: window)
                return
            }
            // 履歴の移し替えは背景で行うので、終わってから一覧を読み直す（listOrphans は同じキューで読む）
            self?.reload()
        }
    }
}
