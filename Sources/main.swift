import Cocoa
import UniformTypeIdentifiers

// ============================================================
// 改行・全角スペースをグレーで可視化するレイアウトマネージャ
// ============================================================
final class InvisiblesLayoutManager: NSLayoutManager {

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard UserDefaults.standard.bool(forKey: "showInvisibles"),
              let storage = textStorage else { return }

        let content = storage.string as NSString
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let color = NSColor.tertiaryLabelColor

        var i = charRange.location
        while i < NSMaxRange(charRange) {
            let ch = content.character(at: i)
            let symbol: String
            switch ch {
            case 0x000A: symbol = "↩"       // 改行
            case 0x3000: symbol = "□"       // 全角スペース
            default:
                i += 1
                continue
            }

            let font = (storage.attribute(.font, at: i, effectiveRange: nil) as? NSFont)
                ?? NSFont.systemFont(ofSize: 14)
            let glyphIndex = glyphIndexForCharacter(at: i)
            let fragmentRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let glyphLocation = location(forGlyphAt: glyphIndex) // フラグメント原点基準、y はベースライン
            let point = NSPoint(
                x: origin.x + fragmentRect.minX + glyphLocation.x,
                y: origin.y + fragmentRect.minY + glyphLocation.y - font.ascender)
            NSAttributedString(string: symbol, attributes: [
                .font: font,
                .foregroundColor: color,
            ]).draw(at: point)

            i += 1
        }
    }
}

// ============================================================
// エディタ本体の NSTextView（フォント変更を UserDefaults に保存）
// ============================================================
final class EditorTextView: NSTextView {

    static func savedFont() -> NSFont {
        let d = UserDefaults.standard
        let name = d.string(forKey: "fontName") ?? "HiraMinProN-W3"
        var size = d.double(forKey: "fontSize")
        if size <= 0 { size = 16 }
        return NSFont(name: name, size: size)
            ?? NSFont.userFont(ofSize: size)
            ?? NSFont.systemFont(ofSize: size)
    }

    override func changeFont(_ sender: Any?) {
        let manager = NSFontManager.shared
        let newFont = manager.convert(font ?? EditorTextView.savedFont())
        font = newFont
        let d = UserDefaults.standard
        d.set(newFont.fontName, forKey: "fontName")
        d.set(Double(newFont.pointSize), forKey: "fontSize")
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
        enclosingScrollView?.horizontalRulerView?.needsDisplay = true
    }

    /// 右クリック（コンテクスト）メニューに、選択中の文字列があるときだけ
    /// 「選択部分をファイル名に」を追加する。実処理はDocument.renameCommand(_:)を
    /// レスポンダーチェーン経由で呼ぶ（File > 名前を変更…と同じ仕組み）。
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        if selectedRange().length > 0 {
            menu?.addItem(.separator())
            menu?.addItem(withTitle: "選択部分をファイル名に",
                          action: #selector(Document.renameCommand(_:)), keyEquivalent: "")
        }
        return menu
    }
}

// ============================================================
// 行番号ルーラー（表示行 = 画面右端での折り返し行にも番号を付ける）
// ============================================================
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    override var isFlipped: Bool { true }

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44

        NotificationCenter.default.addObserver(
            self, selector: #selector(layoutChanged),
            name: NSText.didChangeNotification, object: textView)
        // ウインドウ幅の変更で折り返し位置が変わるため、フレーム変更も監視する
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(layoutChanged),
            name: NSView.frameDidChangeNotification, object: textView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func scrolled() { needsDisplay = true }

    /**
     * （グリフ位置 → 表示行番号）の控え。
     *
     * 可視範囲の先頭が何行目かは、本来なら文書の先頭から数えるしかない。
     * それをやると**描画のたびに文書全体のレイアウトが走る**ので、大きな文書では
     * スクロールも入力も追いつかなくなる（540万字で応答なしになった原因）。
     * 一定行ごとに控えを取り、近い地点から数え直すことで、毎回の仕事を
     * 「直前の控えから可視範囲まで」に抑える。
     */
    private var lineCheckpoints: [(glyph: Int, line: Int)] = []

    /// 控えを取る間隔（表示行）
    private let checkpointInterval = 500

    @objc func layoutChanged() {
        // 編集された位置より後ろの控えは当てにならないので捨てる。
        // 手前の控えは行番号が変わらないので残せる（先頭から数え直さずに済む）
        let editPoint = textView?.selectedRange().location ?? 0
        lineCheckpoints.removeAll { $0.glyph >= editPoint }
        updateThickness()
        needsDisplay = true
    }

    /// 文書全体の表示行数の見積もり（ガター幅の桁数を決めるためだけに使う）。
    /// TextKitのlineFragmentRectを全文書に対して呼ぶと文書全体のレイアウトが
    /// 強制され、大きな文書を開くたびに固まる原因になっていたため、実際の
    /// レイアウトを要求しない文字数ベースの概算に変更した（数字が数桁ずれても
    /// ガター幅が多少余分/不足するだけで実害はない。実際に描画する行番号自体は
    /// drawHashMarksAndLabels側で可視範囲のみを正確に計算している）。
    private var cachedEstimate = 1
    private var cachedLength = -1
    private var cachedContainerWidth: CGFloat = -1

    private func estimatedDisplayLines() -> Int {
        guard let tv = textView else { return 1 }
        let ns = tv.string as NSString
        let length = ns.length          // NSStringの長さはO(1)
        guard length > 0 else { return 1 }
        let containerWidth = tv.textContainer?.size.width ?? 600

        // この値はガター幅の**桁数**を決めるためだけに使う。1文字打つたびに
        // 全文を数え直す意味はないので、長さが大きく変わったときだけ数え直す
        if cachedLength >= 0,
           abs(length - cachedLength) < 4096,
           abs(containerWidth - cachedContainerWidth) < 1 {
            return cachedEstimate
        }

        var newlines = 0
        for u in tv.string.utf16 where u == 10 { newlines += 1 }
        let physicalLines = newlines + 1

        let font = tv.font ?? NSFont.systemFont(ofSize: 14)
        let charWidth = max(NSAttributedString(string: "全", attributes: [.font: font]).size().width, 1)
        let padding = tv.textContainer?.lineFragmentPadding ?? 0
        let usableWidth = max(containerWidth - padding * 2, charWidth)
        let charsPerLine = max(Int(usableWidth / charWidth), 1)
        // text.count（書記素の数）は大きな文書で重いので、UTF-16の長さで見積もる
        let wrapEstimate = length / charsPerLine + 1

        cachedLength = length
        cachedContainerWidth = containerWidth
        cachedEstimate = max(physicalLines, wrapEstimate, 1)
        return cachedEstimate
    }

    /// 控えを位置順に保つ（同じ位置の重複は上書きする）
    private func addCheckpoint(glyph: Int, line: Int) {
        if let index = lineCheckpoints.firstIndex(where: { $0.glyph >= glyph }) {
            if lineCheckpoints[index].glyph == glyph {
                lineCheckpoints[index] = (glyph, line)
            } else {
                lineCheckpoints.insert((glyph, line), at: index)
            }
        } else {
            lineCheckpoints.append((glyph, line))
        }
    }

    private func updateThickness() {
        let digits = max(2, String(estimatedDisplayLines()).count)
        let t = CGFloat(digits) * 9 + 18
        if abs(ruleThickness - t) > 0.5 { ruleThickness = t }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView,
              let layoutManager = tv.layoutManager,
              let container = tv.textContainer else { return }

        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()

        let visibleRect = tv.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let relY = convert(NSPoint.zero, from: tv).y
        let originY = tv.textContainerOrigin.y

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        func draw(_ number: Int, fragmentRect: NSRect) {
            let s = NSAttributedString(string: String(number), attributes: attrs)
            let size = s.size()
            let x = ruleThickness - size.width - 8
            let y = fragmentRect.minY + originY + relY + (fragmentRect.height - size.height) / 2
            s.draw(at: NSPoint(x: x, y: y))
        }

        // 可視範囲の直前までの表示行数を数える。
        // 文書の先頭からではなく、**手前でいちばん近い控えから**再開する
        var line = 1
        var glyphIndex = 0
        if let checkpoint = lineCheckpoints.last(where: { $0.glyph <= glyphRange.location }) {
            line = checkpoint.line
            glyphIndex = checkpoint.glyph
        }
        var fragmentRange = NSRange()
        var sinceCheckpoint = 0
        while glyphIndex < glyphRange.location {
            layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &fragmentRange)
            if NSMaxRange(fragmentRange) > glyphRange.location { break }
            glyphIndex = NSMaxRange(fragmentRange)
            line += 1
            sinceCheckpoint += 1
            if sinceCheckpoint >= checkpointInterval {
                sinceCheckpoint = 0
                addCheckpoint(glyph: glyphIndex, line: line)
            }
        }

        // 可視範囲の各表示行（折り返し行を含む）に行番号を描画
        let numberOfGlyphs = layoutManager.numberOfGlyphs
        while glyphIndex < NSMaxRange(glyphRange) && glyphIndex < numberOfGlyphs {
            let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &fragmentRange)
            draw(line, fragmentRect: fragmentRect)
            glyphIndex = NSMaxRange(fragmentRange)
            line += 1
        }

        // 末尾が改行で終わる場合・空文書の場合の最終行
        if layoutManager.extraLineFragmentTextContainer != nil,
           NSMaxRange(glyphRange) >= numberOfGlyphs {
            draw(line, fragmentRect: layoutManager.extraLineFragmentRect)
        }
    }
}

// ============================================================
// 全角換算の文字数ルーラー（横方向、テキスト上部）
// 明朝・ゴシックとも全角文字はほぼ等幅なので、実際のフォントで
// 「全」を実測した幅を1文字ぶんとして、毎文字＝細目盛り／10文字ごと＝
// 太目盛り＋数字、を描く。テキストは折り返し表示のため横スクロールはなく、
// 常に固定のスケールを示すだけでよい（垂直ルーラーと違いスクロール追従は不要）。
// ============================================================
final class CharacterRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .horizontalRuler)
        clientView = textView
        ruleThickness = 20

        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: NSView.frameDidChangeNotification, object: textView)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc func refresh() { needsDisplay = true }

    /// 現在のフォントで全角1文字ぶんのピクセル幅を実測する
    private func zenkakuWidth(font: NSFont) -> CGFloat {
        NSAttributedString(string: "全", attributes: [.font: font]).size().width
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView else { return }
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

        let font = tv.font ?? NSFont.systemFont(ofSize: 14)
        let charWidth = zenkakuWidth(font: font)
        guard charWidth > 1 else { return }

        let originX = convert(NSPoint(x: tv.textContainerOrigin.x, y: 0), from: tv).x
        let maxX = bounds.maxX

        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        var n = 0
        var x = originX
        while x < maxX {
            let isMajor = n > 0 && n % 10 == 0
            let tickHeight: CGFloat = isMajor ? 8 : 4
            (isMajor ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setFill()
            NSRect(x: x, y: bounds.maxY - tickHeight, width: 1, height: tickHeight).fill()
            if isMajor {
                NSAttributedString(string: "\(n)", attributes: numberAttrs)
                    .draw(at: NSPoint(x: x + 2, y: 2))
            }
            n += 1
            x += charWidth
        }
    }
}

// ============================================================
// ドキュメント
// ============================================================
@objc(Document)
final class Document: NSDocument, NSTextViewDelegate {

    /// クイックメモの固定ファイル名（保存フォルダ直下）。削除しても次回自動で作り直す
    static let quickMemoFileName = "quickmemo.txt"

    enum LineEnding: Int {
        case lf = 0    // macOS
        case crlf = 1  // Windows
        var string: String { self == .lf ? "\n" : "\r\n" }
    }

    var text = ""
    var fileEncoding: String.Encoding = .utf8
    var lineEnding: LineEnding = .lf

    /// 読み込んだファイルの先頭に BOM（U+FEFF）があったか。
    ///
    /// BOM は文字コードの目印であって本文ではないので、**読み込んだ時点で外す**。
    /// 外さないと目に見えない1文字が字数と原稿用紙換算に乗り、看板の数が狂う
    /// （半角扱いなので0.5字ぶんずれる）。改行コードと同じく、
    /// **元のファイルにあったなら保存時に書き戻す**ので、ファイルは変わらない。
    var hadByteOrderMark = false

    private var autoSaveTimer: Timer?
    private var scheduledAutoSaveInterval: Double = -1

    private weak var textView: EditorTextView?
    private weak var statusLabel: NSTextField?
    private weak var encodingPopup: NSPopUpButton?
    private weak var lineEndingPopup: NSPopUpButton?
    private weak var autoSavePopup: NSPopUpButton?
    private weak var modeButton: NSButton?
    private weak var menuBarView: MenuBarView?
    private var matchListController: MatchListWindowController?
    private var statusUpdateTimer: Timer?
    private var proofListController: ProofListWindowController?
    private var outlineController: OutlineWindowController?

    // 外部変更の競合検出・大幅変更ガードの基準値（Android版のTabが持つ値と同じ）
    private var baseModified: Date?
    private var baseSize: Int64 = -1
    private var baseHash = ""
    private var baselineLen = 0
    private var conflictHold = false
    private var bigChangeHold = false
    private var conflictAlertShowing = false
    /// 閲覧モード（読むことに専念するモード。起動のたびに解除された状態から始まる）
    private var readingMode = false

    override class var autosavesInPlace: Bool { false }

    // ---------- 読み込み・保存 ----------

    override func read(from data: Data, ofType typeName: String) throws {
        if let s = String(data: data, encoding: .utf8) {
            text = s
            fileEncoding = .utf8
        } else if let s = String(data: data, encoding: .shiftJIS) {
            text = s
            fileEncoding = .shiftJIS
        } else {
            throw NSError(domain: "KageriEditor", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "テキストを読み込めませんでした（UTF-8 / Shift-JIS のいずれでもありません）。",
            ])
        }
        hadByteOrderMark = text.hasPrefix("\u{FEFF}")
        if hadByteOrderMark { text.removeFirst() }
        lineEnding = text.contains("\r\n") ? .crlf : .lf
        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // 「復帰」などで既にウインドウがある場合は反映
        if let tv = textView {
            tv.string = text
            syncPopups()
            // 前回終了時のカーソル位置を復元する（記録が無い、または文書が短くなっていれば先頭）
            if let url = fileURL {
                let pos = RecentHistory.position(for: url)
                let len = (tv.string as NSString).length
                let start = min(max(pos.selStart, 0), len)
                let end = min(max(pos.selEnd, start), len)
                tv.setSelectedRange(NSRange(location: start, length: end - start))
            }
            updateStatus()
        }

        if let url = fileURL {
            recordBaseline(at: url)
            addHistory(name: url.lastPathComponent, url: url)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        if let tv = textView { text = tv.string }
        var out = lineEnding == .crlf
            ? text.replacingOccurrences(of: "\n", with: "\r\n")
            : text
        // 元のファイルにあった BOM は書き戻す（勝手に落とさない）
        if hadByteOrderMark { out = "\u{FEFF}" + out }
        guard let data = out.data(using: fileEncoding, allowLossyConversion: false) else {
            throw NSError(domain: "KageriEditor", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "Shift-JIS では表現できない文字が含まれているため保存できません。エンコーディングを UTF-8 に変更するか、該当の文字を修正してください。",
            ])
        }
        return data
    }

    // ---------- 保存（⌘S はダイアログなしで1行目をファイル名にして保存） ----------

    /// 設定された保存フォルダ（未設定なら ~/Documents）
    static var saveFolderURL: URL {
        if let path = UserDefaults.standard.string(forKey: "saveFolder"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private var documentFileType: String { fileType ?? "Plain Text" }

    private func currentAutoFileName() -> String {
        if let tv = textView { text = tv.string }
        return FileNaming.fileName(fromFirstLineOf: text)
    }

    override func save(_ sender: Any?) {
        if let tv = textView { text = tv.string }

        // すでにファイル名が付いている文書は、リネームせずその場所へ上書き保存する
        if fileURL != nil {
            writeToExistingFile(fromAutoSave: false)
            return
        }
        saveAutomatically()
    }

    /// 「閉じる」: 標準の確認ダイアログ（保存しますか？）は出さず、必ず保存してから閉じる。
    /// 一度も保存されていない文書は、このアプリの規則（1行目をファイル名に）で保存する。
    /// 外部変更の競合（②）が検出された場合は、その確認を優先し閉じない。
    @objc func closeSavingFirst(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        if let tv = textView { text = tv.string }

        if fileURL == nil {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 空の無題文書は保存せずそのまま閉じる（空ファイルを増やさないため）
                window.close()
            } else {
                saveAutomatically { window.close() }
            }
            return
        }
        writeToExistingFile(fromAutoSave: false) { window.close() }
    }

    /// 「保存せず閉じ」: 保存せずに変更を破棄して閉じる。
    /// 他のコマンドと違い、破棄すると取り消せない（元に戻す手段が無い）ため、
    /// ここだけは例外的に確認ダイアログを挟む（アプリ全体のダイアログレス
    /// 方針の唯一の例外。隣接する「閉じる」との誤操作を考慮したユーザー指示）。
    @objc func closeDiscardingChanges(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        let alert = NSAlert()
        alert.messageText = "保存せず閉じますか？"
        alert.informativeText = "このウインドウの変更は保存されず、元に戻せません。"
        alert.addButton(withTitle: "保存せず閉じる")
        alert.addButton(withTitle: "キャンセル")
        alert.buttons.last?.keyEquivalent = "\u{1b}" // Escape
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            window.close()
        }
    }

    /// 初回保存：1行目（全角換算20文字まで）をファイル名にして、
    /// 設定フォルダへダイアログなしで保存する。以後この名前は変更しない。
    private func saveAutomatically(completion: (() -> Void)? = nil) {
        let folder = Document.saveFolderURL
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            presentError(error)
            return
        }

        let base = currentAutoFileName()
        var target = folder.appendingPathComponent(base).appendingPathExtension("txt")

        // 同名ファイルがあれば「名前 2.txt」のように番号を付ける
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension("txt")
            n += 1
        }

        save(to: target, ofType: documentFileType, for: .saveAsOperation) { [weak self] error in
            guard let self else { return }
            if let error {
                self.presentError(error)
                return
            }
            self.recordBaseline(at: target)
            self.addHistory(name: target.lastPathComponent, url: target)
            if let tv = self.textView {
                let sel = tv.selectedRange()
                RecentHistory.updatePosition(url: target, selStart: sel.location, selEnd: NSMaxRange(sel))
            }
            self.updateStatus()
            completion?()
        }
    }

    /// 未保存の文書を、指定した名前で保存フォルダに新規保存する（「名前を変更」から使用）
    private func saveWithExplicitName(base: String) {
        let folder = Document.saveFolderURL
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            presentError(error)
            return
        }
        var target = folder.appendingPathComponent(base).appendingPathExtension("txt")
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension("txt")
            n += 1
        }
        save(to: target, ofType: documentFileType, for: .saveAsOperation) { [weak self] error in
            guard let self else { return }
            if let error {
                self.presentError(error)
                return
            }
            self.recordBaseline(at: target)
            self.addHistory(name: target.lastPathComponent, url: target)
            self.updateStatus()
        }
    }

    // ---------- ② 外部変更の競合検出 ----------

    /// 保存フォルダ内にウインドウを持つこのDocumentの、書き込み先が既に存在するfileURLへの上書き。
    /// 他端末でのリネーム追従→外部変更の照合→保存、の順に行う（Android版のwriteTo()と同じ流れ）。
    private func writeToExistingFile(fromAutoSave: Bool, force: Bool = false, completion: (() -> Void)? = nil) {
        guard var url = fileURL else { return }
        if let tv = textView { text = tv.string }

        // 他端末での名前変更に追従（ファイルが見つからない場合）
        if !FileManager.default.fileExists(atPath: url.path) {
            let folder = url.deletingLastPathComponent()
            if let renamed = RenameJournal.resolve(name: url.lastPathComponent, in: folder) {
                let candidate = folder.appendingPathComponent(renamed)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    removeHistory(url)
                    url = candidate
                    fileURL = url
                    addHistory(name: renamed, url: url)
                    synchronizeWindowTitle()
                }
            }
        }

        if !force {
            if conflictHold && fromAutoSave { return } // 停止中は静かに見送る
            if detectExternalChange(at: url) {
                conflictHold = true
                updateStatus()
                showConflictAlert(for: url)
                return
            }
        }

        save(to: url, ofType: documentFileType, for: .saveOperation) { [weak self] error in
            guard let self else { return }
            if let error {
                self.presentError(error)
                return
            }
            self.conflictHold = false
            self.bigChangeHold = false
            self.recordBaseline(at: url)
            if let tv = self.textView {
                let sel = tv.selectedRange()
                RecentHistory.updatePosition(url: url, selStart: sel.location, selEnd: NSMaxRange(sel))
            }
            self.updateStatus()
            completion?()
        }
    }

    /// 開いた時点・最後の保存時点を基準として記録する
    private func recordBaseline(at url: URL) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        baseModified = attrs?[.modificationDate] as? Date
        baseSize = (attrs?[.size] as? NSNumber)?.int64Value ?? -1
        if let data = try? Data(contentsOf: url) {
            baseHash = DocumentSafety.sha256(data)
        }
        baselineLen = (textView?.string ?? text).count
    }

    /// 基準記録時点からファイルが外部で変わったか
    private func detectExternalChange(at url: URL) -> Bool {
        guard baseSize >= 0 else { return false } // 基準未記録は検出しない
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        let modified = attrs[.modificationDate] as? Date
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
        if size == baseSize, modified == baseModified { return false }
        // 日時やサイズが違うときだけ、内容ハッシュで確定させる
        guard let data = try? Data(contentsOf: url) else { return false }
        return DocumentSafety.sha256(data) != baseHash
    }

    private func showConflictAlert(for url: URL) {
        guard !conflictAlertShowing, let window = windowControllers.first?.window else { return }
        conflictAlertShowing = true
        let alert = NSAlert()
        alert.messageText = "「\(url.lastPathComponent)」は外部で変更された可能性があります"
        alert.informativeText = "どうしますか？"
        alert.addButton(withTitle: "キャンセル（自動保存停止のまま）")
        alert.addButton(withTitle: "外部版を開く（今の編集内容は破棄）")
        alert.addButton(withTitle: "現在の内容を別名保存（競合コピー）")
        alert.addButton(withTitle: "強制的に上書き")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.conflictAlertShowing = false
            switch response {
            case .alertSecondButtonReturn:
                self.reloadExternalVersion(url: url)
            case .alertThirdButtonReturn:
                self.saveAsConflictCopy()
            case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + 3):
                self.writeToExistingFile(fromAutoSave: false, force: true)
            default:
                break // キャンセル：停止状態を維持
            }
            self.updateStatus()
        }
    }

    /// 外部版を読み込み直す（今の編集内容は破棄）
    private func reloadExternalVersion(url: URL) {
        do {
            try revert(toContentsOf: url, ofType: documentFileType)
            conflictHold = false
            bigChangeHold = false
            updateStatus()
        } catch {
            presentError(error)
        }
    }

    /// 現在の内容を「元名_競合コピー_日時.txt」として保存フォルダに保存する
    private func saveAsConflictCopy() {
        if let tv = textView { text = tv.string }
        let folder = fileURL?.deletingLastPathComponent() ?? Document.saveFolderURL
        let baseName = fileURL?.deletingPathExtension().lastPathComponent ?? "無題"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())
        let target = folder.appendingPathComponent("\(baseName)_競合コピー_\(stamp)").appendingPathExtension("txt")
        conflictHold = false
        save(to: target, ofType: documentFileType, for: .saveAsOperation) { [weak self] error in
            guard let self else { return }
            if let error {
                self.presentError(error)
                return
            }
            self.recordBaseline(at: target)
            self.addHistory(name: target.lastPathComponent, url: target)
            self.updateStatus()
        }
    }

    // ---------- ④ 履歴 ----------

    private func addHistory(name: String, url: URL) {
        RecentHistory.add(name: name, url: url)
    }

    private func removeHistory(_ url: URL) {
        RecentHistory.remove(url: url)
    }

    /// プログラムから fileURL を変更した後、タイトルバー・プロキシアイコンを反映する
    private func synchronizeWindowTitle() {
        windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
    }

    // ---------- ⑤ ファイル名の変更（選択文字列を候補に） ----------

    @objc func renameCommand(_ sender: Any?) {
        guard let tv = textView, let window = windowControllers.first?.window else { return }
        let sel = tv.selectedRange()
        var suggested = fileURL?.deletingPathExtension().lastPathComponent ?? "無題"
        if sel.length > 0 {
            let selected = (tv.string as NSString).substring(with: sel)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !selected.isEmpty { suggested = FileNaming.fileName(fromFirstLineOf: selected) }
        }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = suggested

        let alert = NSAlert()
        alert.messageText = "ファイル名を変更"
        alert.accessoryView = field
        alert.addButton(withTitle: "変更")
        alert.addButton(withTitle: "キャンセル")
        alert.buttons.last?.keyEquivalent = "\u{1b}" // Escape
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let base = FileNaming.fileName(fromFirstLineOf: field.stringValue)
            self.performRename(base: base)
        }
    }

    private func performRename(base: String) {
        guard let oldURL = fileURL else {
            // 未保存の文書は、この名前で新規保存する
            saveWithExplicitName(base: base)
            return
        }
        let newName = "\(base).\(oldURL.pathExtension)"
        guard newName != oldURL.lastPathComponent else { return }
        let folder = oldURL.deletingLastPathComponent()
        let newURL = folder.appendingPathComponent(newName)
        if FileManager.default.fileExists(atPath: newURL.path) {
            let alert = NSAlert()
            alert.messageText = "同じ名前のファイルがあります"
            if let window = windowControllers.first?.window {
                alert.beginSheetModal(for: window)
            }
            return
        }
        let oldName = oldURL.lastPathComponent
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            presentError(error)
            return
        }
        removeHistory(oldURL)
        fileURL = newURL
        synchronizeWindowTitle()
        addHistory(name: newName, url: newURL)
        // 内容は変わっていないので、基準の日時・サイズだけ取り直す（ハッシュ・文字数は既存のまま）
        let attrs = try? FileManager.default.attributesOfItem(atPath: newURL.path)
        baseModified = attrs?[.modificationDate] as? Date
        baseSize = (attrs?[.size] as? NSNumber)?.int64Value ?? baseSize
        RenameJournal.append(from: oldName, to: newName, in: folder)
        updateStatus()
    }

    // ---------- 一定時間ごとの自動保存 ----------

    /// 設定「自動保存の間隔（分）」に従ってタイマーを張り直す。0 以下なら無効。
    func scheduleAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        let minutes = UserDefaults.standard.double(forKey: "autoSaveInterval")
        scheduledAutoSaveInterval = minutes
        guard minutes > 0 else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: true) { [weak self] _ in
            self?.autoSaveTick()
        }
        timer.tolerance = 5
        autoSaveTimer = timer
    }

    /// 設定変更（UserDefaults）で間隔が変わったときだけ張り直す
    @objc private func defaultsDidChange(_ notification: Notification) {
        if UserDefaults.standard.double(forKey: "autoSaveInterval") != scheduledAutoSaveInterval {
            scheduleAutoSaveTimer()
        }
    }

    private func autoSaveTick() {
        guard isDocumentEdited, let tv = textView else { return }
        // 日本語入力の変換中は保存を見送る（次回のタイマーで保存される）
        if tv.hasMarkedText() { return }
        text = tv.string

        guard fileURL != nil else {
            // 未命名：空白だけの文書は対象外（空の「無題.txt」を作らない）
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
            saveAutomatically()
            return
        }

        // 本文が元の量に戻っていれば、大幅変更ガードは自動解除する
        if bigChangeHold, !detectBigLoss() {
            bigChangeHold = false
            updateStatus()
        }
        if conflictHold || bigChangeHold { return } // 停止中（②/③）
        if detectBigLoss() {
            bigChangeHold = true
            updateStatus()
            showBigChangeAlert()
            return
        }
        writeToExistingFile(fromAutoSave: true)
    }

    // ---------- ③ 大幅変更ガード ----------

    /// 前回保存時より本文が大幅に減っていないか（空・8割以上の減少）
    private func detectBigLoss() -> Bool {
        guard baselineLen >= 200 else { return false }
        // メモは書き溜めては消す使い方をするため、大幅変更ガードの対象外にする
        if fileURL?.lastPathComponent == Document.quickMemoFileName { return false }
        let now = textView?.string ?? text
        return now.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || now.count < baselineLen / 5
    }

    private func showBigChangeAlert() {
        guard let window = windowControllers.first?.window else { return }
        let nowLen = textView?.string.count ?? 0
        let alert = NSAlert()
        alert.messageText = "本文が大幅に減っています"
        alert.informativeText = """
            前回保存時 \(baselineLen) 文字 → 現在 \(nowLen) 文字です。
            操作ミスの可能性があるため、自動保存を一時停止しました。
            （手動の「保存」はいつでも実行できます）
            """
        alert.addButton(withTitle: "自動保存を止めておく")
        alert.addButton(withTitle: "このまま保存を続ける")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertSecondButtonReturn {
                self.bigChangeHold = false
                self.writeToExistingFile(fromAutoSave: false)
            }
            self.updateStatus()
        }
    }

    /// 設定の「ウインドウをタブでまとめる」を、このウインドウに反映する。
    /// オンならファイルが1つの時もタブバーを表示、オフならタブバーを消す
    func applyTabSetting() {
        guard let window = windowControllers.first?.window else { return }
        let tabsEnabled = UserDefaults.standard.bool(forKey: "tabsEnabled")
        window.tabbingMode = tabsEnabled ? .preferred : .disallowed
        if tabsEnabled {
            // 「開く」（NSOpenPanelが閉じた直後）はmacOSの自動タブ合流が効かないことが
            // あるため、既存のドキュメントウインドウのタブグループへ明示的に合流させる
            if let other = Document.anotherVisibleDocumentWindow(excluding: window),
               other.tabGroup !== window.tabGroup {
                other.addTabbedWindow(window, ordered: .above)
            }
        }
        let barVisible = window.tabGroup?.isTabBarVisible ?? false
        if barVisible != tabsEnabled {
            window.toggleTabBar(nil)
        }
    }

    private static func anotherVisibleDocumentWindow(excluding window: NSWindow) -> NSWindow? {
        for case let doc as Document in NSDocumentController.shared.documents {
            if let w = doc.windowControllers.first?.window, w !== window, w.isVisible {
                return w
            }
        }
        return nil
    }

    override func close() {
        if let url = fileURL, let tv = textView {
            let sel = tv.selectedRange()
            RecentHistory.updatePosition(url: url, selStart: sel.location, selEnd: NSMaxRange(sel))
        }
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        NotificationCenter.default.removeObserver(self)
        super.close()
    }

    /// 表示設定（改行・全角スペースの可視化）変更時の再描画用
    func redrawText() {
        textView?.needsDisplay = true
    }

    /// 設定パネルの「画面表示の文字サイズ」の変更をこのウインドウに反映する。
    /// フォントの種類は変えずサイズだけ差し替える（changeFont(_:)と同様）。
    func applyFontSize() {
        guard let tv = textView, let currentFont = tv.font else { return }
        var size = UserDefaults.standard.double(forKey: "fontSize")
        if size <= 0 { size = 16 }
        guard abs(currentFont.pointSize - CGFloat(size)) > 0.01 else { return }
        tv.font = NSFont(name: currentFont.fontName, size: CGFloat(size)) ?? currentFont.withSize(CGFloat(size))
        enclosingScrollViewRulersNeedDisplay(for: tv)
    }

    private func enclosingScrollViewRulersNeedDisplay(for tv: NSTextView) {
        tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        tv.enclosingScrollView?.horizontalRulerView?.needsDisplay = true
    }

    override func saveAs(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.directoryURL = fileURL?.deletingLastPathComponent() ?? Document.saveFolderURL
        panel.nameFieldStringValue = currentAutoFileName() + ".txt"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            self.save(to: url, ofType: self.documentFileType, for: .saveAsOperation) { error in
                if let error { self.presentError(error) }
            }
        }
    }

    // ---------- 印刷 ----------

    /// 標準的な印刷。行番号ガターや改行・全角スペースの可視化記号など画面上だけの
    /// 装飾は含めず、本文だけを現在のフォントでページ分割して印刷する
    /// （印刷専用の使い捨てNSTextViewをNSPrintOperationに渡すと、TextKitが
    /// 自動でページをまたいだレイアウトをしてくれる標準的なやり方）。
    override func printOperation(withSettings settings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let tv = textView else {
            throw NSError(domain: "KageriEditor", code: 12, userInfo: [
                NSLocalizedDescriptionKey: "印刷する本文がありません。",
            ])
        }

        let info = printInfo.copy() as! NSPrintInfo
        for (key, value) in settings { info.dictionary()[key] = value }
        info.horizontalPagination = .fit
        info.isVerticallyCentered = false
        if info.topMargin < 36 { info.topMargin = 36 }
        if info.bottomMargin < 36 { info.bottomMargin = 36 }
        if info.leftMargin < 36 { info.leftMargin = 36 }
        if info.rightMargin < 36 { info.rightMargin = 36 }

        let printableWidth = info.paperSize.width - info.leftMargin - info.rightMargin

        // NSTextViewの自動ページ分割（knowsPageRange/rectForPage）は、
        // ビュー自身のframeの高さ＝本文全体の高さになっていて初めて正しく働く。
        // NSTextView(frame:)の既定コンテナは指定したframeの高さで打ち切られて
        // しまうため、テキストコンテナの高さを無制限にしてレイアウトを確定させ、
        // 実際に必要な高さぶんへ後からframeを広げる。
        let printContainer = NSTextContainer(
            containerSize: NSSize(width: printableWidth, height: .greatestFiniteMagnitude))
        printContainer.widthTracksTextView = true
        let printLayoutManager = NSLayoutManager()
        printLayoutManager.addTextContainer(printContainer)

        // 印刷時の文字サイズは画面表示用フォントと別に設定できる
        // （「設定」の「印刷時の文字サイズ」。0＝画面と同じサイズを使う）
        let screenFont = tv.font ?? EditorTextView.savedFont()
        let printFontSize = UserDefaults.standard.double(forKey: "printFontSize")
        let printFont: NSFont = printFontSize > 0
            ? (NSFont(name: screenFont.fontName, size: printFontSize) ?? screenFont.withSize(printFontSize))
            : screenFont

        let printStorage = NSTextStorage(string: tv.string, attributes: [.font: printFont])
        printStorage.addLayoutManager(printLayoutManager)

        let printView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: printableWidth, height: info.paperSize.height),
            textContainer: printContainer)
        printView.isEditable = false
        printView.isVerticallyResizable = true
        printView.isHorizontallyResizable = false
        printView.minSize = NSSize(width: 0, height: 0)
        printView.maxSize = NSSize(width: printableWidth, height: .greatestFiniteMagnitude)
        printView.textContainerInset = NSSize(width: 0, height: 0)

        printLayoutManager.ensureLayout(for: printContainer)
        let usedHeight = printLayoutManager.usedRect(for: printContainer).height
        printView.frame = NSRect(x: 0, y: 0, width: printableWidth,
                                 height: max(usedHeight, info.paperSize.height))

        let operation = NSPrintOperation(view: printView, printInfo: info)
        operation.printPanel.options.insert(.showsPaperSize)
        operation.printPanel.options.insert(.showsOrientation)
        return operation
    }

    // ---------- ウインドウ構築 ----------

    override func makeWindowControllers() {
        // 縦長の執筆向けサイズで開く（画面に収まらなければ画面の高さまで）
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 900)
        let contentWidth = min(870, visibleFrame.width - 40)
        let contentHeight = min(1300, visibleFrame.height - 28)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        // 既に他のドキュメントウインドウが開いている時は、既定の中央位置・サイズに
        // 戻すのではなく、そのウインドウの位置とサイズを維持する（「新規」でも「開く」でも）。
        // タブでまとめる設定がオンの場合は、一度既定位置で作ってから合流させることで
        // その一瞬のフレーム不一致のせいで毎回位置がずれて見える問題も同時に防げる。
        // 1つも開いていない時（全部閉じたあとの「新規」やアプリ起動直後）は、
        // 最後に使っていた枠を覚えているのでそこへ開く。覚えていなければ中央。
        if let existing = Document.anotherVisibleDocumentWindow(excluding: window) {
            window.setFrame(existing.frame, display: false)
        } else if let remembered = Document.lastWindowFrame() {
            window.setFrame(remembered, display: false)
        } else {
            window.center()
        }

        let contentView = NSView()
        window.contentView = contentView

        // --- スクロールビュー + テキストビュー ---
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        // 行番号ルーラーの内部コンテナが実際のscrollViewの高さより大きく確保され、
        // 上端がメニューバーの領域にまではみ出して描画されることがあったため、
        // scrollView自身の枠でクリップして確実に隠す
        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = true

        let contentSize = scrollView.contentSize

        // 改行・全角スペースの可視化のため、テキストシステムを手動で組み立てる（TextKit 1）
        let storage = NSTextStorage()
        let layoutManager = InvisiblesLayoutManager()
        storage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let tv = EditorTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 6, height: 8)

        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFontPanel = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        // 横ルーラーを設置するとNSTextViewが既定でリッチテキスト用の
        // 段落ルーラー（タブ位置マーカー▶・スタイル選択）を自動的に
        // ルーラーへ割り込ませてくる。プレーンテキスト専用アプリなので無効化する。
        tv.usesRuler = false

        // 日本語の文書作成向け：自動置換の類いをすべて無効化
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false

        let font = EditorTextView.savedFont()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.3
        tv.defaultParagraphStyle = paragraphStyle
        tv.typingAttributes = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.textColor,
        ]

        tv.string = text
        tv.font = font
        if let storage = tv.textStorage, storage.length > 0 {
            storage.addAttribute(.paragraphStyle, value: paragraphStyle,
                                 range: NSRange(location: 0, length: storage.length))
        }
        tv.delegate = self

        scrollView.documentView = tv

        // --- 上部メニューボタン列（Android版の下部タッチメニューに相当） ---
        let menuBar = MenuBarView(frame: .zero)
        menuBar.reload(defs: menuItemDefs())
        menuBar.onOverflowClicked = { [weak self] in self?.showOverflowMenu(nil) }

        // --- 行番号ルーラー ---
        let ruler = LineNumberRulerView(textView: tv, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        // --- 文字数ルーラー（横） ---
        let charRuler = CharacterRulerView(textView: tv, scrollView: scrollView)
        scrollView.horizontalRulerView = charRuler
        scrollView.hasHorizontalRuler = true

        // --- ステータスバー ---
        let statusBar = NSView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail

        // 自動保存の間隔。うっかり切り替わらないよう、その場のトグルではなく
        // 一覧から選び直す形にしている（文字コード・改行コードと同じ操作感）
        let autoSavePopup = NSPopUpButton()
        autoSavePopup.translatesAutoresizingMaskIntoConstraints = false
        autoSavePopup.controlSize = .small
        autoSavePopup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        autoSavePopup.target = self
        autoSavePopup.action = #selector(autoSaveIntervalChanged(_:))

        // 閲覧モードの切替（押すたびに「編集」⇄「閲覧」）
        let modeButton = NSButton()
        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.controlSize = .small
        modeButton.bezelStyle = .rounded
        modeButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        modeButton.target = self
        modeButton.action = #selector(toggleReadingMode(_:))

        let encPopup = NSPopUpButton()
        encPopup.translatesAutoresizingMaskIntoConstraints = false
        encPopup.controlSize = .small
        encPopup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        encPopup.addItems(withTitles: ["UTF-8", "Shift-JIS"])
        encPopup.target = self
        encPopup.action = #selector(encodingChanged(_:))

        let eolPopup = NSPopUpButton()
        eolPopup.translatesAutoresizingMaskIntoConstraints = false
        eolPopup.controlSize = .small
        eolPopup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        eolPopup.addItems(withTitles: ["LF（macOS）", "CRLF（Windows）"])
        eolPopup.target = self
        eolPopup.action = #selector(lineEndingChanged(_:))

        statusBar.addSubview(separator)
        statusBar.addSubview(label)
        statusBar.addSubview(autoSavePopup)
        statusBar.addSubview(encPopup)
        statusBar.addSubview(eolPopup)
        statusBar.addSubview(modeButton)

        contentView.addSubview(menuBar)
        contentView.addSubview(scrollView)
        contentView.addSubview(statusBar)

        NSLayoutConstraint.activate([
            menuBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            menuBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            menuBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            menuBar.heightAnchor.constraint(equalToConstant: 34),

            scrollView.topAnchor.constraint(equalTo: menuBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 30),

            separator.topAnchor.constraint(equalTo: statusBar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor),

            label.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: autoSavePopup.leadingAnchor, constant: -12),

            // 右端から「閲覧/編集」「改行コード」「文字コード」「自動保存」の順に並べる
            modeButton.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -10),
            modeButton.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            eolPopup.trailingAnchor.constraint(equalTo: modeButton.leadingAnchor, constant: -8),
            eolPopup.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            encPopup.trailingAnchor.constraint(equalTo: eolPopup.leadingAnchor, constant: -8),
            encPopup.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            autoSavePopup.trailingAnchor.constraint(equalTo: encPopup.leadingAnchor, constant: -8),
            autoSavePopup.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
        ])

        self.textView = tv
        self.statusLabel = label
        self.encodingPopup = encPopup
        self.lineEndingPopup = eolPopup
        self.autoSavePopup = autoSavePopup
        self.modeButton = modeButton
        self.menuBarView = menuBar

        let windowController = NSWindowController(window: window)
        // AppKitの自動カスケードを切る。既定のままだと、上で決めた枠が表示の直前に
        // 右下へ少しずつずらされ、ウインドウが開くたびに位置が変わってしまう
        windowController.shouldCascadeWindows = false
        addWindowController(windowController)
        // ウインドウがまだ画面に出る前にタブグループへ合流させておく（表示後に合流させると
        // 単独ウインドウとして一瞬映ってからタブへ吸い込まれるように見えてしまうため）
        applyTabSetting()
        // ファイルを開いた時、残っている空の「名称未設定」ウインドウは自動的に閉じる
        // （Android版のタブ再利用と同じ考え方）。上のタブ合流より後に行うことで、
        // 「名称未設定」を閉じる際のちらつきが新規ウインドウの表示に重ならないようにする
        closeOtherBlankUntitledDocuments()
        window.makeFirstResponder(tv)

        syncPopups()
        updateStatus()

        scheduleAutoSaveTimer()
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuOrderChanged),
            name: MenuBarView.orderChangedNotification, object: nil)
        // 次にウインドウが1つも無い状態から開くときのために、枠を覚えておく
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(rememberWindowFrame(_:)), name: name, object: window)
        }
    }

    // ---------- ウインドウ位置の記憶 ----------

    private static let lastWindowFrameKey = "lastWindowFrame"

    @objc private func rememberWindowFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Document.lastWindowFrameKey)
    }

    /// 最後に使っていたドキュメントウインドウの枠。外部ディスプレイを外した後などに
    /// 画面の外へ開いてしまわないよう、今つながっている画面と十分に重なる場合だけ返す
    static func lastWindowFrame() -> NSRect? {
        guard let saved = UserDefaults.standard.string(forKey: lastWindowFrameKey) else { return nil }
        let frame = NSRectFromString(saved)
        guard frame.width >= 200, frame.height >= 200 else { return nil }
        let usable = NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return overlap.width >= 160 && overlap.height >= 160
        }
        return usable ? frame : nil
    }

    @objc private func menuOrderChanged() {
        menuBarView?.rebuild()
    }

    private func syncPopups() {
        encodingPopup?.selectItem(at: fileEncoding == .utf8 ? 0 : 1)
        lineEndingPopup?.selectItem(at: lineEnding.rawValue)
    }

    // ---------- ステータスバー ----------

    private func formatCount(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// 本文が変わるたびに全文を数え直すと大きな文書で入力が追いつかなくなるので、
    /// 少し待ってからまとめて数える。保存やタブ切替など、すぐ反映したい経路は
    /// updateStatus() を直接呼ぶ（Android版2.15と同じ考え方）。
    func scheduleStatusUpdate() {
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.updateStatus()
        }
    }

    func updateStatus() {
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = nil
        guard let tv = textView else { return }
        let string = tv.string
        // 表示行数（折り返し込み）ではなく物理行数（改行の数）を数える。
        // TextKitのlineFragmentRectを文書全体に対して呼ぶと強制的にレイアウトが
        // 発生し、大きな文書で毎回のステータス更新のたびに重くなる・過去に
        // 無限再帰でクラッシュした原因そのものになるため（LineNumberRulerViewの
        // estimatedDisplayLines()と同じ理由）、あえて正確な表示行数は数えない。
        //
        // 字数・原稿用紙の行数・改行の数は**1回の走査でまとめて**求める。
        // 以前は3回別々に走査したうえ、manuscriptLinesが全行を配列に確保していた
        var lines = 1
        for u in string.utf16 where u == 10 { lines += 1 }
        let metrics = CharWidth.measure(string, excludeHeadingMarks: true)
        let sheets = formatCount((Double(metrics.manuscriptLines) / 20 * 10).rounded(.down) / 10)
        var status = "\(lines) 行 ｜ \(formatCount(metrics.zenkaku)) 字 ｜ \(sheets) 枚"
        // 見出しの印を数から除いていることは、ステータスバーには出さない
        // （除く決まりは使い方に書いてあり、入稿前に「見出しの印をすべて外す」を
        // 通せば、画面の数と渡したファイルの数は完全に一致する）
        let sel = tv.selectedRange()
        if sel.length > 0 {
            // 全体と選択で数え方が違うと説明がつかないので、選択も同じに数える
            let selected = (string as NSString).substring(with: sel)
            let selMetrics = CharWidth.measure(selected, excludeHeadingMarks: true)
            status += "（選択 \(formatCount(selMetrics.zenkaku)) 字）"
        }
        statusLabel?.stringValue = status
        syncAutoSavePopup()
        modeButton?.title = readingMode ? "閲覧" : "編集"
    }

    /// 自動保存の間隔の選択肢。設定画面で一覧に無い値を入れている場合は、その値も足す
    private func autoSaveChoices() -> [Double] {
        var choices: [Double] = [0, 1, 3, 5, 10, 30]
        let current = UserDefaults.standard.double(forKey: "autoSaveInterval")
        if !choices.contains(current) { choices.append(current) }
        return choices.sorted()
    }

    private func syncAutoSavePopup() {
        guard let popup = autoSavePopup else { return }
        let choices = autoSaveChoices()
        let titles = choices.map { $0 <= 0 ? "自動保存 off" : "自動保存 \(formatCount($0))分" }
        if popup.itemTitles != titles {
            popup.removeAllItems()
            popup.addItems(withTitles: titles)
        }
        let current = UserDefaults.standard.double(forKey: "autoSaveInterval")
        if let index = choices.firstIndex(of: current) {
            popup.selectItem(at: index)
        }
    }

    @objc private func autoSaveIntervalChanged(_ sender: NSPopUpButton) {
        let choices = autoSaveChoices()
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < choices.count else { return }
        UserDefaults.standard.set(choices[index], forKey: "autoSaveInterval")
        // 全ウインドウのタイマーと表示を張り直す
        for case let document as Document in NSDocumentController.shared.documents {
            document.scheduleAutoSaveTimer()
            document.updateStatus()
        }
    }

    // ---------- NSTextViewDelegate ----------

    func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

    func textDidChange(_ notification: Notification) {
        scheduleStatusUpdate()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        // カーソルを動かしただけでも呼ばれる。大きな文書では矢印キーの1回ごとに
        // 全文を数え直すことになるので、こちらも間引く
        scheduleStatusUpdate()
    }

    // ---------- エンコーディング / 改行コード ----------

    @objc private func encodingChanged(_ sender: NSPopUpButton) {
        let newValue: String.Encoding = sender.indexOfSelectedItem == 0 ? .utf8 : .shiftJIS
        guard newValue != fileEncoding else { return }
        fileEncoding = newValue
        updateChangeCount(.changeDone)
    }

    @objc private func lineEndingChanged(_ sender: NSPopUpButton) {
        guard let newValue = LineEnding(rawValue: sender.indexOfSelectedItem),
              newValue != lineEnding else { return }
        lineEnding = newValue
        updateChangeCount(.changeDone)
    }

    // ---------- 変換コマンド ----------

    /// 選択範囲（なければ文書全体）にテキスト変換を適用する。
    /// 選択が行の途中から始まっていても・途中で終わっていても、その行全体を
    /// 選択しているものとみなして行単位で処理する（整形・非整形・空行除去・原稿支援で共通）。
    private func applyTransform(_ transform: (String) -> String) {
        guard let tv = textView else { return }
        let full = tv.string as NSString
        let selection = tv.selectedRange()
        let hasSelection = selection.length > 0
        var range = selection
        if !hasSelection {
            range = NSRange(location: 0, length: full.length)
        } else {
            // 行の途中から始まる選択は行頭まで広げる
            let lineStart = full.lineRange(for: NSRange(location: range.location, length: 0)).location
            if lineStart < range.location {
                range.length += range.location - lineStart
                range.location = lineStart
            }
            // 行の途中で終わる選択は行末まで広げる
            let end = NSMaxRange(range)
            if end < full.length, end > 0, full.character(at: end - 1) != 0x0A {
                let lineRange = full.lineRange(for: NSRange(location: end, length: 0))
                var lineEnd = NSMaxRange(lineRange)
                if lineEnd > 0 && full.character(at: lineEnd - 1) == 0x0A { lineEnd -= 1 }
                if lineEnd > end { range.length = lineEnd - range.location }
            }
        }
        guard range.length > 0 else { return }
        let target = full.substring(with: range)
        let replaced = transform(target)
        guard replaced != target else { return }
        tv.insertText(replaced, replacementRange: range)
        // 変換後は選択を解除する。カーソルは、選択して実行したときは対象の先頭へ、
        // 文書全体に実行したときは元の位置へ寄せて、画面が大きく飛ばないようにする
        let newLength = (tv.string as NSString).length
        let caret = hasSelection ? range.location : selection.location
        tv.setSelectedRange(NSRange(location: min(caret, newLength), length: 0))
    }

    /// 改行だけを取り除く（スペースの除去は「原稿支援」のダイアログが担当する）
    @objc func removeNewlinesCommand(_ sender: Any?) {
        let noParagraphDetect = UserDefaults.standard.bool(forKey: "noParagraphDetect")
        applyTransform { TextTransform.removeNewlines($0, recognizeParagraphs: !noParagraphDetect) }
    }

    /// 原稿支援。書き上げたあとの体裁を整える処理をダイアログでまとめて選び、1回で適用する。
    /// 除去 → 文字種の変換 → 追加 の順に走るので、「行頭スペースをいったん除去してから
    /// 規則正しく付け直す」といった手順もチェックを2つ入れるだけで済む。
    /// 頻繁に使う機能ではないためダイアログを挟む（空行除去・非整形は即実行のまま残す）。
    @objc func manuscriptAssistCommand(_ sender: Any?) {
        let defaults = UserDefaults.standard

        func heading(_ label: String) -> NSTextField {
            let field = NSTextField(labelWithString: label)
            field.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            return field
        }
        func note(_ label: String) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: label)
            field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            field.textColor = .secondaryLabelColor
            field.preferredMaxLayoutWidth = assistDialogWidth - 44
            return field
        }
        func check(_ label: String, _ key: String) -> NSButton {
            let box = NSButton(checkboxWithTitle: label, target: nil, action: nil)
            box.state = defaults.bool(forKey: key) ? .on : .off
            return box
        }
        /// 見出しの下にぶら下がる項目を字下げして、どの見出しに属するか見分けられるようにする
        func indented(_ view: NSView, by amount: CGFloat) -> NSView {
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.widthAnchor.constraint(equalToConstant: amount).isActive = true
            let row = NSStackView(views: [spacer, view])
            row.orientation = .horizontal
            row.spacing = 0
            row.alignment = .top
            return row
        }

        let removeHalf = check("半角スペース", "assistRemoveHalf")
        let removeFull = check("全角スペース", "assistRemoveFull")
        let removeTab = check("タブ", "assistRemoveTab")
        let removeIndent = check("行頭の字下げも除去する", "assistRemoveIndent")
        let digits = check("数字を半角に", "assistDigits")
        let units = check("単位を半角に（km・L など）", "assistUnits")
        let addIndent = check("行頭の字下げ（一字下げ）", "assistAddIndent")
        let addBlank = check("段落の間に空行", "assistAddBlank")

        // ラジオボタンは同じ親ビュー・同じアクションを共有することで排他になる。
        // 選ばれた値は「実行」を押した時点でまとめて読むので、アクション自体は何もしない
        let alphaKeep = NSButton(radioButtonWithTitle: "そのまま",
                                 target: self, action: #selector(assistAlphabetChanged(_:)))
        let alphaFull = NSButton(radioButtonWithTitle: "全角に",
                                 target: self, action: #selector(assistAlphabetChanged(_:)))
        let alphaHalf = NSButton(radioButtonWithTitle: "半角に",
                                 target: self, action: #selector(assistAlphabetChanged(_:)))
        switch defaults.string(forKey: "assistAlphabet") ?? "keep" {
        case "full": alphaFull.state = .on
        case "half": alphaHalf.state = .on
        default: alphaKeep.state = .on
        }
        let alphabetRow = NSStackView(views: [alphaKeep, alphaFull, alphaHalf])
        alphabetRow.orientation = .horizontal
        alphabetRow.spacing = 16

        // 前回の選択が残るので、選び直したいときに1つずつ外さなくて済むようにする
        let allOffButton = NSButton(title: "すべてオフ", target: self, action: #selector(assistAllOff(_:)))
        allOffButton.bezelStyle = .rounded
        allOffButton.controlSize = .small

        let stack = NSStackView(views: [
            heading("除去する"),
            indented(removeHalf, by: 12),
            indented(removeFull, by: 12),
            indented(removeTab, by: 12),
            indented(removeIndent, by: 12),
            heading("文字種を揃える"),
            indented(digits, by: 12),
            indented(units, by: 12),
            indented(note("数字のすぐ後ろにある単位だけを半角にします。アルファベットの変換より後に効くので、「全角に」と一緒に選べば「単語は全角・単位は半角」にできます。"), by: 32),
            indented(NSTextField(labelWithString: "アルファベット"), by: 12),
            indented(alphabetRow, by: 32),
            heading("追加する"),
            indented(addIndent, by: 12),
            indented(note("会話文のカッコや箇条書き記号で始まる行、空行には字下げを追加しません。"), by: 32),
            indented(addBlank, by: 12),
            indented(note("すべての改行の直後に1行あけます。段落の見分けはしないので、すでに空行がある場所はそのぶん増えます。"), by: 32),
            allOffButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        // NSAlertのアクセサリビューは自動レイアウトの結果をframeに落とし込んでから渡す必要がある
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.widthAnchor.constraint(equalToConstant: assistDialogWidth),
        ])
        container.frame = NSRect(x: 0, y: 0, width: assistDialogWidth, height: stack.fittingSize.height)

        let checkBoxes = [removeHalf, removeFull, removeTab, removeIndent, digits, units, addIndent, addBlank]
        Document.assistDialogControls = (checkBoxes, [alphaKeep, alphaFull, alphaHalf])
        defer { Document.assistDialogControls = nil }

        let alert = NSAlert()
        alert.messageText = "原稿支援"
        alert.informativeText = "行いたい処理をチェックで選ぶと、除去→文字種→追加の順に1回でまとめて適用します。"
            + "文字列を選択しているときは、その範囲だけが対象になります。"
        alert.accessoryView = container
        alert.addButton(withTitle: "実行")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let alphabet: TextTransform.AlphabetMode
        if alphaFull.state == .on {
            alphabet = .fullWidth
        } else if alphaHalf.state == .on {
            alphabet = .halfWidth
        } else {
            alphabet = .keep
        }

        // 次回も同じ選択から始められるよう覚えておく
        defaults.set(removeHalf.state == .on, forKey: "assistRemoveHalf")
        defaults.set(removeFull.state == .on, forKey: "assistRemoveFull")
        defaults.set(removeTab.state == .on, forKey: "assistRemoveTab")
        defaults.set(removeIndent.state == .on, forKey: "assistRemoveIndent")
        defaults.set(digits.state == .on, forKey: "assistDigits")
        defaults.set(units.state == .on, forKey: "assistUnits")
        defaults.set(addIndent.state == .on, forKey: "assistAddIndent")
        defaults.set(addBlank.state == .on, forKey: "assistAddBlank")
        switch alphabet {
        case .fullWidth: defaults.set("full", forKey: "assistAlphabet")
        case .halfWidth: defaults.set("half", forKey: "assistAlphabet")
        case .keep: defaults.set("keep", forKey: "assistAlphabet")
        }

        let options = TextTransform.AssistOptions(
            removeHalfWidthSpace: removeHalf.state == .on,
            removeFullWidthSpace: removeFull.state == .on,
            removeTab: removeTab.state == .on,
            removeLeadingIndent: removeIndent.state == .on,
            digitsToHalfWidth: digits.state == .on,
            alphabet: alphabet,
            unitsToHalfWidth: units.state == .on,
            addLeadingIndent: addIndent.state == .on,
            addBlankLines: addBlank.state == .on
        )
        // 何も選ばれていなければ何もしない
        guard options.hasAnyAction else { return }
        applyTransform { TextTransform.assist($0, options: options) }
    }

    /// 原稿支援ダイアログの横幅（説明文の折り返し幅もここから決める）
    private var assistDialogWidth: CGFloat { 380 }

    /// 「すべてオフ」から触るためにダイアログ表示中だけ控えておく。
    /// モーダルなので同時に2つ開くことはない
    private static var assistDialogControls: (checks: [NSButton], alphabet: [NSButton])?

    @objc private func assistAllOff(_ sender: Any?) {
        guard let controls = Document.assistDialogControls else { return }
        for box in controls.checks { box.state = .off }
        // アルファベットは先頭の「そのまま」へ戻す
        for (index, radio) in controls.alphabet.enumerated() {
            radio.state = index == 0 ? .on : .off
        }
    }

    /// ラジオボタンを排他にするためだけのアクション（値は「実行」時にまとめて読む）
    @objc private func assistAlphabetChanged(_ sender: NSButton) {}

    /// 推敲。書き上げた原稿の「気になる箇所」を並べる。**直さず、指摘するだけ**。
    /// 原稿支援と違って本文を書き換えないので、ダイアログで選ばせず即座に一覧を出す。
    /// 選択範囲があればその範囲だけを見る（整形・原稿支援と同じ扱い）。
    @objc func proofreadCommand(_ sender: Any?) {
        guard let tv = textView else { return }
        guard let controller = ProofListWindowController(textView: tv) else {
            let alert = NSAlert()
            alert.messageText = tv.selectedRange().length > 0
                ? "選択範囲に気になる箇所はありません"
                : "気になる箇所は見つかりませんでした"
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        proofListController = controller
        controller.shouldCascadeWindows = false
        controller.window?.center()
        controller.showWindow(nil)
    }

    /// 見出しを拾って並べ、クリックでその場所へ移動する。**本文には触れない**。
    @objc func outlineCommand(_ sender: Any?) {
        guard let tv = textView else { return }
        guard let controller = OutlineWindowController(textView: tv) else {
            let alert = NSAlert()
            alert.messageText = "見出しが見つかりませんでした"
            alert.informativeText = "行頭が字下げされておらず、句点で終わらない短い行を見出しとみなします。"
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        outlineController = controller
        controller.shouldCascadeWindows = false
        controller.window?.center()
        controller.showWindow(nil)
    }

    // ---------- 見出しの印 ----------

    /// 見出しの印を1段送る（なし → 大見出し → 小見出し → なし）。
    ///
    /// 印は行頭の「# 」「## 」で、**字数と原稿用紙換算からは除かれる**
    /// （印は原稿ではなく書き手の道具なので）。印のある文書では、見出しの推定を
    /// やめて印だけに従うので、並べ替えのように間違えると被害の大きい操作を
    /// 安心して載せられる。
    ///
    /// 書き換えるのは**かかった行だけ**で、全文は作り直さない。1回の書き換えに
    /// まとめているので、取り消しも1回で戻る。
    @objc func headingMarkCommand(_ sender: Any?) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        guard let patch = Outline.cycleMarkPatch(
            tv.string, selStart: sel.location, selEnd: NSMaxRange(sel)) else { return }
        let range = NSRange(location: patch.start, length: patch.end - patch.start)
        tv.insertText(patch.replacement, replacementRange: range)
        let newLength = (tv.string as NSString).length
        let start = min(patch.selStart, newLength)
        tv.setSelectedRange(
            NSRange(location: start, length: min(patch.selEnd, newLength) - start))
        updateStatus()
    }

    /// 印をすべて外す。入稿の直前に使う。
    /// これを通したファイルなら、画面の字数と受け取った側で数えた字数が一致する。
    @objc func stripHeadingMarksCommand(_ sender: Any?) {
        applyTransform { Outline.stripMarks($0) }
    }

    /// 改行のみの行を1段階ぶん削除する（連続する空行は1回につき1行ずつ詰まる）
    @objc func removeBlankLinesCommand(_ sender: Any?) {
        applyTransform { TextTransform.removeBlankLinesStep($0) }
    }

    @objc func wrapCommand(_ sender: Any?) {
        var count = UserDefaults.standard.integer(forKey: "wrapWidth")
        if count <= 0 { count = 40 }
        // 行の途中から／途中まで選択した場合も、applyTransformがその行全体へ広げる
        applyTransform { TextTransform.wrap($0, limit: Double(count)) }
    }

    // ---------- 日付・時刻の挿入 ----------

    private func insertAtCursor(_ string: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        tv.insertText(string, replacementRange: range)
        tv.setSelectedRange(NSRange(location: range.location + (string as NSString).length, length: 0))
        updateStatus()
    }

    @objc func insertDateCommand(_ sender: Any?) {
        insertAtCursor(DateTimeFormat.currentDateString(formatIndex: UserDefaults.standard.integer(forKey: "dateFormat")))
    }

    /// このドキュメントがメモ（quickmemo.txt）として既に開かれている時、末尾に1件追記して保存する
    /// （他アプリのServicesメニュー「メモに追記」から呼ばれる）
    func appendQuickMemoEntry(_ entry: String) {
        guard let tv = textView else { return }
        let end = NSRange(location: (tv.string as NSString).length, length: 0)
        let sep = tv.string.isEmpty || tv.string.hasSuffix("\n") ? "" : "\n"
        tv.setSelectedRange(end)
        tv.insertText(sep + entry, replacementRange: end)
        text = tv.string
        updateStatus()
        save(nil)
    }

    @objc func insertTimeCommand(_ sender: Any?) {
        insertAtCursor(DateTimeFormat.currentTimeString(formatIndex: UserDefaults.standard.integer(forKey: "timeFormat")))
    }

    // ---------- 検索（ツールバーボタン用） ----------

    private func showFindInterface() {
        guard let tv = textView else { return }
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        tv.performTextFinderAction(item)
    }

    /// 検索結果一覧（Android版の「一覧」ボタンと同じ機能）。
    /// 初期の検索語はシステム共通の検索文字列（⌘Fや⌘Eで使われるもの）を引き継ぐ。
    @objc func showMatchList(_ sender: Any?) {
        guard let tv = textView else { return }
        let initialQuery = NSPasteboard(name: .find).string(forType: .string) ?? ""
        let controller = MatchListWindowController(textView: tv, initialQuery: initialQuery)
        matchListController = controller
        controller.window?.center()
        controller.showWindow(nil)
    }

    // ---------- 履歴ポップアップ（ツールバーの「履歴」ボタン用） ----------

    private func showHistoryPopup() {
        guard let window = windowControllers.first?.window, let contentView = window.contentView else { return }
        let menu = NSMenu()
        let history = RecentHistory.load()
        if history.isEmpty {
            let empty = NSMenuItem(title: "履歴はまだありません", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for entry in history {
                let item = NSMenuItem(title: entry.name, action: #selector(openHistoryEntry(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.url
                menu.addItem(item)
            }
        }
        if let button = menuBarView?.button(for: "history") {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: button)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: 20, y: contentView.bounds.height - 20), in: contentView)
        }
    }

    @objc private func openHistoryEntry(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        (NSApp.delegate as? AppDelegate)?.openFollowingRename(url)
    }

    // ---------- 上部メニューボタン列の項目定義 ----------

    private func menuActions() -> [String: () -> Void] {
        [
            "new": { NSDocumentController.shared.newDocument(nil) },
            "memo": { (NSApp.delegate as? AppDelegate)?.showQuickMemo(nil) },
            "open": { NSDocumentController.shared.openDocument(nil) },
            "history": { [weak self] in self?.showHistoryPopup() },
            "save": { [weak self] in self?.save(nil) },
            "selectall": { [weak self] in self?.textView?.selectAll(nil) },
            "cut": { [weak self] in self?.textView?.cut(nil) },
            "copy": { [weak self] in self?.textView?.copy(nil) },
            "paste": { [weak self] in self?.textView?.paste(nil) },
            "undo": { [weak self] in self?.undoManager?.undo() },
            "redo": { [weak self] in self?.undoManager?.redo() },
            "date": { [weak self] in self?.insertDateCommand(nil) },
            "time": { [weak self] in self?.insertTimeCommand(nil) },
            "search": { [weak self] in self?.showFindInterface() },
            "matchlist": { [weak self] in self?.showMatchList(nil) },
            "wrap": { [weak self] in self?.wrapCommand(nil) },
            "removenl": { [weak self] in self?.removeNewlinesCommand(nil) },
            "blankline": { [weak self] in self?.removeBlankLinesCommand(nil) },
            "removespace": { [weak self] in self?.manuscriptAssistCommand(nil) },
            "proofread": { [weak self] in self?.proofreadCommand(nil) },
            "outline": { [weak self] in self?.outlineCommand(nil) },
            "headingmark": { [weak self] in self?.headingMarkCommand(nil) },
            "close": { [weak self] in self?.closeSavingFirst(nil) },
        ]
    }

    // ---------- 右上「⋮」のプルダウンメニュー ----------

    /// メニューバーに常駐させるほどではない項目をまとめたプルダウン。
    /// 性質ごとに3つのまとまりにしてある（ファイル操作／表示の切替／アプリ全体）。
    /// 取り消せない「保存せず閉じる」を先頭に置かないための並びでもある。
    @objc func showOverflowMenu(_ sender: Any?) {
        guard let bar = menuBarView else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "別名保存", action: #selector(saveAs(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "ファイル名変更…", action: #selector(renameCommand(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "印刷…", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "保存せず閉じる", action: #selector(closeDiscardingChanges(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let reading = menu.addItem(withTitle: "閲覧モード", action: #selector(toggleReadingMode(_:)), keyEquivalent: "")
        reading.state = readingMode ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "設定…", action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "使い方", action: #selector(AppDelegate.showUserGuide(_:)), keyEquivalent: "")
        // ボタンの真下に出す
        let anchor = bar.overflowAnchor
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: anchor)
    }

    // ---------- 閲覧モード ----------

    /// 閲覧モードの切り替え。読むことに専念するためのモードで、
    /// 起動のたびに解除された状態から始まる（書けない状態でアプリを開いて
    /// 戸惑わないよう、あえて設定として保存していない）。
    @objc func toggleReadingMode(_ sender: Any?) {
        readingMode.toggle()
        applyReadingMode()
    }

    /// 閲覧モードの状態を画面へ反映する。入力とカーソルを止め、
    /// 文字数の目盛りを隠す。メニューバーは薄く表示したまま残すので、
    /// ステータスバーの位置は変わらない（Android版と同じ考え方）。
    /// 文字を選んでコピーすることはできる。
    func applyReadingMode() {
        guard let tv = textView else { return }
        tv.isEditable = !readingMode
        // 読むときは横の文字数目盛りが不要なので隠す（縦の行番号は残す）
        tv.enclosingScrollView?.hasHorizontalRuler = !readingMode
        tv.enclosingScrollView?.rulersVisible = true
        menuBarView?.isDimmedForReading = readingMode
        updateStatus()
    }

    private func menuItemDefs() -> [MenuButtonDef] {
        let actions = menuActions()
        return MenuBarView.labelDefs.compactMap { key, label in
            guard let action = actions[key] else { return nil }
            return MenuButtonDef(key: key, label: label, action: action)
        }
    }

    /// 「名称未設定」のまま何も入力されていない空の文書か（ファイルを開いた時の自動整理に使う）
    var isBlankUntitled: Bool {
        fileURL == nil && !isDocumentEdited && (textView?.string.isEmpty ?? true)
    }

    /// ファイル（fileURLを持つ）を新しく開いた時だけ、残っている他の空の「名称未設定」を閉じる。
    /// ⌘Nで新規の空文書を作った時はここでは何もしない
    private func closeOtherBlankUntitledDocuments() {
        guard fileURL != nil else { return }
        for case let doc as Document in NSDocumentController.shared.documents where doc !== self {
            if doc.isBlankUntitled {
                doc.close()
            }
        }
    }
}

// ============================================================
// ドキュメントコントローラ（NSDocumentController.sharedを自前のサブクラスに
// するためだけに生成している。「名称未設定」の自動整理はDocument側で行う）
// ============================================================
final class KageriDocumentController: NSDocumentController {
}

// ============================================================
// アプリケーションデリゲート（メニュー構築・設定ウインドウ）
// ============================================================
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {

    // 最初に生成された NSDocumentController（のサブクラス）が共有インスタンスになる仕様のため、
    // どの文書よりも先にここでKageriDocumentControllerを生成しておく必要がある。
    private let documentController = KageriDocumentController()

    private var preferencesPanel: NSPanel?
    private weak var saveFolderLabel: NSTextField?
    private weak var historyMenu: NSMenu?
    private var menuEditorController: MenuEditorWindowController?
    private var helpWindowController: HelpWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "wrapWidth": 40,
            "fontSize": 16.0,
            "listFontSize": 12.0, // 検索結果一覧・推敲・目次の一覧に使う文字サイズ
            "showInvisibles": true,
            "autoSaveInterval": 0.0, // 分。0 で無効（既定はオフ）
            "dateFormat": 0,
            "timeFormat": 0,
            "assistAlphabet": "keep", // 原稿支援のアルファベット変換（keep/full/half）
            "noParagraphDetect": false, // ⌃Rの非整形で記号による段落認識をしないか
            "darkMode": "system", // "system"/"light"/"dark"
            "printFontSize": 0.0, // 印刷時の文字サイズ。0で画面表示と同じサイズを使う
            "tabsEnabled": true, // ウインドウをタブでまとめるか
        ])
        applyDarkModeSetting()
        NSApp.mainMenu = buildMainMenu()
        NSApp.servicesProvider = self
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        promptInitialSaveFolderIfNeeded()
    }

    /// 初回起動時（保存フォルダが未設定かつこの案内をまだ出したことがない場合）だけ、
    /// 保存フォルダを選ぶパネルを自動的に開く。一度出したら選んでもキャンセルしても
    /// 二度と自動では出さない（UserDefaultsの"initialFolderPromptShown"で管理）。
    private func promptInitialSaveFolderIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "initialFolderPromptShown") else { return }
        defaults.set(true, forKey: "initialFolderPromptShown")
        guard defaults.string(forKey: "saveFolder") == nil else { return }

        let alert = NSAlert()
        alert.messageText = "保存フォルダを選んでください"
        alert.informativeText = "KageriEditorで書いた文章の保存先フォルダです。\n"
            + "「書類」フォルダを初期候補として表示します。\n"
            + "他の端末（Android版など）と同期して使いたい場合は、Dropbox や Google Drive が同期しているフォルダを選んでください。"
        alert.addButton(withTitle: "選択する")
        alert.addButton(withTitle: "あとで")
        if alert.runModal() == .alertFirstButtonReturn {
            chooseSaveFolder(nil)
        }
    }

    // ---------- 設定ウインドウ ----------

    @objc func showPreferences(_ sender: Any?) {
        if preferencesPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            panel.title = "設定"
            panel.isReleasedWhenClosed = false
            panel.delegate = self

            // --- 保存フォルダ ---
            let folderTitle = NSTextField(labelWithString: "保存フォルダ:")
            let folderLabel = NSTextField(labelWithString: Document.saveFolderURL.path)
            folderLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            folderLabel.textColor = .secondaryLabelColor
            folderLabel.lineBreakMode = .byTruncatingMiddle
            folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let folderButton = NSButton(title: "変更…", target: self,
                                        action: #selector(chooseSaveFolder(_:)))
            let folderRow = NSStackView(views: [folderTitle, folderLabel, folderButton])
            folderRow.orientation = .horizontal
            folderRow.spacing = 8
            saveFolderLabel = folderLabel

            // --- 画面表示の文字サイズ（1ポイント単位。フォントパネルの
            //     サイズ一覧は9,10,11,12,13,14,18,24...のように刻みが粗いため、
            //     1pt単位で調整したい場合はこちらを使う。フォントの種類は
            //     引き続きフォントパネル（⌘T）で選ぶ） ---
            let fontSizeTitle = NSTextField(labelWithString: "画面表示の文字サイズ:")

            let fontSizeFormatter = NumberFormatter()
            fontSizeFormatter.allowsFloats = false
            fontSizeFormatter.minimum = 8
            fontSizeFormatter.maximum = 96

            let fontSizeField = NSTextField()
            fontSizeField.formatter = fontSizeFormatter
            fontSizeField.alignment = .right
            fontSizeField.bind(.value,
                               to: NSUserDefaultsController.shared,
                               withKeyPath: "values.fontSize",
                               options: [.continuouslyUpdatesValue: true])
            fontSizeField.widthAnchor.constraint(equalToConstant: 50).isActive = true
            fontSizeField.target = self
            fontSizeField.action = #selector(fontSizeChanged(_:))

            let fontSizeStepper = NSStepper()
            fontSizeStepper.minValue = 8
            fontSizeStepper.maxValue = 96
            fontSizeStepper.increment = 1
            fontSizeStepper.valueWraps = false
            fontSizeStepper.bind(.value,
                                 to: NSUserDefaultsController.shared,
                                 withKeyPath: "values.fontSize",
                                 options: [.continuouslyUpdatesValue: true])
            fontSizeStepper.target = self
            fontSizeStepper.action = #selector(fontSizeChanged(_:))

            let fontSizeRow = NSStackView(views: [fontSizeTitle, fontSizeField, fontSizeStepper])
            fontSizeRow.orientation = .horizontal
            fontSizeRow.spacing = 8

            // --- 一覧の文字サイズ（検索結果一覧・推敲・目次）。
            //     本文とは別に持つ。一覧は補助的な表示なので本文と同じ大きさに
            //     すると場所を取りすぎるが、画面によっては既定の12ptが小さい ---
            let listFontTitle = NSTextField(labelWithString: "一覧の文字サイズ:")

            let listFontFormatter = NumberFormatter()
            listFontFormatter.allowsFloats = false
            listFontFormatter.minimum = 9
            listFontFormatter.maximum = 36

            let listFontField = NSTextField()
            listFontField.formatter = listFontFormatter
            listFontField.alignment = .right
            listFontField.bind(.value,
                               to: NSUserDefaultsController.shared,
                               withKeyPath: "values.listFontSize",
                               options: [.continuouslyUpdatesValue: true])
            listFontField.widthAnchor.constraint(equalToConstant: 50).isActive = true

            let listFontStepper = NSStepper()
            listFontStepper.minValue = 9
            listFontStepper.maxValue = 36
            listFontStepper.increment = 1
            listFontStepper.valueWraps = false
            listFontStepper.bind(.value,
                                 to: NSUserDefaultsController.shared,
                                 withKeyPath: "values.listFontSize",
                                 options: [.continuouslyUpdatesValue: true])

            let listFontNote = NSTextField(labelWithString: "（検索結果一覧・推敲・目次）")
            listFontNote.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            listFontNote.textColor = .secondaryLabelColor

            let listFontRow = NSStackView(views: [listFontTitle, listFontField, listFontStepper, listFontNote])
            listFontRow.orientation = .horizontal
            listFontRow.spacing = 8

            // --- 整形の文字数 ---
            let wrapTitle = NSTextField(labelWithString: "整形の文字数（全角換算）:")

            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            formatter.minimum = 1
            formatter.maximum = 1000

            let field = NSTextField()
            field.formatter = formatter
            field.alignment = .right
            field.bind(.value,
                       to: NSUserDefaultsController.shared,
                       withKeyPath: "values.wrapWidth",
                       options: [.continuouslyUpdatesValue: true])
            field.widthAnchor.constraint(equalToConstant: 64).isActive = true

            let wrapRow = NSStackView(views: [wrapTitle, field])
            wrapRow.orientation = .horizontal
            wrapRow.spacing = 8

            // --- 非整形（⌃R）の段落判定 ---
            // 除去するスペースの指定は「原稿支援」（⌃K）のダイアログへ移した。
            // 以前はこのpref1つを非整形とスペース除去で共用しており、片方を変えると
            // もう片方の挙動まで変わっていた
            let noParagraphCheck = NSButton(checkboxWithTitle: "非整形で段落を区別しない",
                                            target: self, action: #selector(toggleNoParagraphDetect(_:)))
            noParagraphCheck.state = UserDefaults.standard.bool(forKey: "noParagraphDetect") ? .on : .off
            let noParagraphRow = NSStackView(views: [noParagraphCheck])
            noParagraphRow.orientation = .horizontal

            // --- タブ ---
            let tabsCheck = NSButton(checkboxWithTitle: "ウインドウをタブでまとめる（ファイルが1つの時もタブバーを表示）",
                                     target: self, action: #selector(toggleTabsEnabled(_:)))
            tabsCheck.state = UserDefaults.standard.bool(forKey: "tabsEnabled") ? .on : .off
            let tabsRow = NSStackView(views: [tabsCheck])
            tabsRow.orientation = .horizontal

            // --- ダークモード ---
            let darkModeTitle = NSTextField(labelWithString: "ダークモード:")
            let currentDarkMode = UserDefaults.standard.string(forKey: "darkMode") ?? "system"
            let darkSystemRadio = NSButton(radioButtonWithTitle: "端末に従う",
                                           target: self, action: #selector(darkModeChanged(_:)))
            darkSystemRadio.tag = 0
            darkSystemRadio.state = currentDarkMode == "system" ? .on : .off
            let darkLightRadio = NSButton(radioButtonWithTitle: "ライト",
                                          target: self, action: #selector(darkModeChanged(_:)))
            darkLightRadio.tag = 1
            darkLightRadio.state = currentDarkMode == "light" ? .on : .off
            let darkDarkRadio = NSButton(radioButtonWithTitle: "ダーク",
                                         target: self, action: #selector(darkModeChanged(_:)))
            darkDarkRadio.tag = 2
            darkDarkRadio.state = currentDarkMode == "dark" ? .on : .off
            let darkModeRow = NSStackView(views: [darkSystemRadio, darkLightRadio, darkDarkRadio])
            darkModeRow.orientation = .horizontal
            darkModeRow.spacing = 16

            // --- 印刷時の文字サイズ ---
            let printFontTitle = NSTextField(labelWithString: "印刷時の文字サイズ（0で画面と同じ）:")

            let printFontFormatter = NumberFormatter()
            printFontFormatter.allowsFloats = false
            printFontFormatter.minimum = 0
            printFontFormatter.maximum = 200

            let printFontField = NSTextField()
            printFontField.formatter = printFontFormatter
            printFontField.alignment = .right
            printFontField.bind(.value,
                                to: NSUserDefaultsController.shared,
                                withKeyPath: "values.printFontSize",
                                options: [.continuouslyUpdatesValue: true])
            printFontField.widthAnchor.constraint(equalToConstant: 64).isActive = true

            let printFontRow = NSStackView(views: [printFontTitle, printFontField])
            printFontRow.orientation = .horizontal
            printFontRow.spacing = 8

            // --- 自動保存の間隔 ---
            let autoSaveTitle = NSTextField(labelWithString: "自動保存の間隔（分）:")

            let autoSaveFormatter = NumberFormatter()
            autoSaveFormatter.allowsFloats = false
            autoSaveFormatter.minimum = 0
            autoSaveFormatter.maximum = 120

            let autoSaveField = NSTextField()
            autoSaveField.formatter = autoSaveFormatter
            autoSaveField.alignment = .right
            autoSaveField.bind(.value,
                               to: NSUserDefaultsController.shared,
                               withKeyPath: "values.autoSaveInterval",
                               options: [.continuouslyUpdatesValue: true])
            autoSaveField.widthAnchor.constraint(equalToConstant: 64).isActive = true

            let autoSaveRow = NSStackView(views: [autoSaveTitle, autoSaveField])
            autoSaveRow.orientation = .horizontal
            autoSaveRow.spacing = 8

            // --- 日付・時刻の書式 ---
            let dateTitle = NSTextField(labelWithString: "日付の書式:")
            let datePopup = NSPopUpButton()
            datePopup.controlSize = .small
            datePopup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            datePopup.addItems(withTitles: DateTimeFormat.dateFormatSamples)
            datePopup.selectItem(at: UserDefaults.standard.integer(forKey: "dateFormat"))
            datePopup.target = self
            datePopup.action = #selector(dateFormatChanged(_:))
            let dateRow = NSStackView(views: [dateTitle, datePopup])
            dateRow.orientation = .horizontal
            dateRow.spacing = 8

            let timeTitle = NSTextField(labelWithString: "時刻の書式:")
            let timePopup = NSPopUpButton()
            timePopup.controlSize = .small
            timePopup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            timePopup.addItems(withTitles: DateTimeFormat.timeFormatSamples)
            timePopup.selectItem(at: UserDefaults.standard.integer(forKey: "timeFormat"))
            timePopup.target = self
            timePopup.action = #selector(timeFormatChanged(_:))
            let timeRow = NSStackView(views: [timeTitle, timePopup])
            timeRow.orientation = .horizontal
            timeRow.spacing = 8

            // --- 上部メニューボタンの編集 ---
            let menuEditButton = NSButton(title: "メニューの編集…", target: self, action: #selector(openMenuEditor(_:)))
            menuEditButton.bezelStyle = .rounded
            menuEditButton.controlSize = .small
            let menuEditRow = NSStackView(views: [menuEditButton])
            menuEditRow.orientation = .horizontal

            // 詳しい説明は設定パネルには置かず「はじめにお読みください.txt」にまとめている
            // （設定パネルが長くなりすぎるのを避けるため。2026-07-19、ユーザー指示）。

            let stack = NSStackView(views: [
                folderRow, fontSizeRow, listFontRow, wrapRow, noParagraphRow,
                tabsRow,
                darkModeTitle, darkModeRow,
                printFontRow, autoSaveRow, dateRow, timeRow, menuEditRow,
            ])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false
            folderRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            if let content = panel.contentView {
                content.addSubview(stack)
                NSLayoutConstraint.activate([
                    stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                    stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                    stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                ])
            }
            panel.center()
            preferencesPanel = panel
        }
        saveFolderLabel?.stringValue = Document.saveFolderURL.path
        preferencesPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 設定パネルの「画面表示の文字サイズ」（フィールド or ステッパー）が
    /// 変更されたら、開いている全ウインドウに即座に反映する
    /// （toggleInvisiblesと同じ「全Documentへブロードキャスト」パターン）。
    @objc private func fontSizeChanged(_ sender: Any?) {
        for case let document as Document in NSDocumentController.shared.documents {
            document.applyFontSize()
        }
    }

    @objc private func toggleNoParagraphDetect(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "noParagraphDetect")
    }

    /// 開いている全ドキュメントウインドウに即座に反映する（新規に開くウインドウにも設定を使う）。
    /// 設定パネル自体はドキュメントではないので対象に含めない
    /// （以前ここでNSApp.windows全体をタブ化対象にしてしまい、設定パネルまでタブ化されて
    ///   メインウインドウのタブ機能が壊れる不具合があった）
    /// チェック自体はすぐにUserDefaultsへ反映するが、タブの合流・分離という見た目の
    /// 変化は設定ウインドウを閉じた瞬間（windowWillClose）にまとめて行う
    @objc private func toggleTabsEnabled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "tabsEnabled")
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === preferencesPanel else { return }
        let enabled = UserDefaults.standard.bool(forKey: "tabsEnabled")
        if !enabled {
            detachAllTabbedWindows()
        }
        for case let document as Document in NSDocumentController.shared.documents {
            document.applyTabSetting()
        }
    }

    /// オフにした時、現在タブでまとまっているウインドウをそれぞれ個別のウインドウへ戻す
    /// （AppKitのタブ右クリックメニュー「タブを新規ウインドウとして移動」と同じ機構を使う）
    private func detachAllTabbedWindows() {
        var processedGroups = Set<ObjectIdentifier>()
        for case let document as Document in NSDocumentController.shared.documents {
            guard let window = document.windowControllers.first?.window,
                  let group = window.tabGroup, group.windows.count > 1 else { continue }
            let groupID = ObjectIdentifier(group)
            guard !processedGroups.contains(groupID) else { continue }
            processedGroups.insert(groupID)
            let selector = Selector(("moveTabToNewWindow:"))
            for w in group.windows.dropFirst() where w.responds(to: selector) {
                w.perform(selector, with: nil)
            }
        }
    }

    @objc private func darkModeChanged(_ sender: NSButton) {
        let value: String
        switch sender.tag {
        case 1: value = "light"
        case 2: value = "dark"
        default: value = "system"
        }
        UserDefaults.standard.set(value, forKey: "darkMode")
        applyDarkModeSetting()
    }

    /// 「darkMode」設定（system/light/dark）をNSApp.appearanceに反映する
    func applyDarkModeSetting() {
        switch UserDefaults.standard.string(forKey: "darkMode") ?? "system" {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    @objc func toggleInvisibles(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        let newValue = !defaults.bool(forKey: "showInvisibles")
        defaults.set(newValue, forKey: "showInvisibles")
        sender.state = newValue ? .on : .off
        for case let document as Document in NSDocumentController.shared.documents {
            document.redrawText()
        }
    }

    @objc private func dateFormatChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: "dateFormat")
    }

    @objc private func timeFormatChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: "timeFormat")
    }

    @objc private func openMenuEditor(_ sender: Any?) {
        let controller = MenuEditorWindowController()
        menuEditorController = controller
        controller.window?.center()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// アプリ内の「使い方ガイド」を開く。既に開いていれば同じウインドウを前面に出すだけ
    /// （毎回作り直すと、読んでいた位置が失われるため）
    @objc func showUserGuide(_ sender: Any?) {
        if let controller = helpWindowController, let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = HelpWindowController()
        // ドキュメントウインドウと同じく、AppKitに位置をずらされないようにする
        controller.shouldCascadeWindows = false
        helpWindowController = controller
        controller.window?.center()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Ctrl+/ で表示する、現在のキーボードショートカット一覧
    @objc func showShortcutHelp(_ sender: Any?) {
        let text = """
            Ctrl+N　新規
            Ctrl+O　開く
            Ctrl+D　履歴
            Ctrl+S　保存
            Ctrl+G　別名保存
            Ctrl+T　ファイル名変更
            Ctrl+W　閉じる
            Ctrl+Q　保存せず閉じる（確認あり）
            Ctrl+Z　取り消す
            Ctrl+Y　やり直す
            Ctrl+F　検索
            Ctrl+R　非整形
            Ctrl+E　整形
            Ctrl+L　空行除去（連続する空行は1回に1行ずつ）
            Ctrl+K　原稿支援
            Ctrl+J　推敲
            Ctrl+U　目次
            Ctrl+H　見出しの印を送る（なし→大見出し→小見出し→なし）
            Ctrl+B　閲覧モードの切替
            Ctrl+;　日付を挿入
            Ctrl+Shift+;　時刻を挿入
            Ctrl+I　設定
            Ctrl+/　このショートカット一覧を表示

            （⌘系のMac標準ショートカットもそのまま使えます）
            """
        let alert = NSAlert()
        alert.messageText = "キーボードショートカット一覧"
        alert.informativeText = text
        alert.addButton(withTitle: "閉じる")
        alert.runModal()
    }

    @objc func chooseSaveFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = Document.saveFolderURL
        panel.prompt = "選択"
        panel.message = "⌘S での保存先フォルダを選択してください"
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "saveFolder")
            saveFolderLabel?.stringValue = url.path
        }
    }

    // ---------- 履歴（最近開いたファイル） ----------

    /// メニューが開かれる直前に呼ばれる。毎回最新の履歴で作り直す
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let history = RecentHistory.load()
        if history.isEmpty {
            let empty = NSMenuItem(title: "履歴はまだありません", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for entry in history {
            let item = NSMenuItem(title: entry.name,
                                  action: #selector(openHistoryItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.url
            menu.addItem(item)
        }
    }

    @objc private func openHistoryItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openFollowingRename(url)
    }

    /// Ctrl+D: 履歴をその場にポップアップ表示する（Android版の「履歴」ダイアログに相当）
    @objc func showHistoryMenu(_ sender: Any?) {
        guard let menu = historyMenu,
              let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView else { return }
        let origin = NSPoint(x: 20, y: contentView.bounds.height - 20)
        menu.popUp(positioning: nil, at: origin, in: contentView)
    }

    /// 「メモ」（quickmemo.txt固定ファイル）を開く。保存フォルダに存在すればそれを、
    /// なければ空の新規ファイルを作って開く（削除しても次回はここで自動的に作り直される）。
    /// 既に開いていればNSDocumentControllerが自動的にそのウインドウ／タブへ切り替える
    @objc func showQuickMemo(_ sender: Any?) {
        let url = Document.saveFolderURL.appendingPathComponent(Document.quickMemoFileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                NSAlert(error: error).runModal()
            }
        }
    }

    // ---------- 他アプリからの「メモに追記」（Servicesメニュー） ----------

    /// Info.plistのNSServicesに登録した「メモに追記」サービスの入口。
    /// 他アプリで選択した文字列を、日時を添えてメモ（quickmemo.txt）の末尾に追記する。
    /// Android版のACTION_PROCESS_TEXT（選択メニューからのメモ追記）に相当
    @objc func appendSelectionToMemo(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let selected = pboard.string(forType: .string),
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "選択された文字列がありません" as NSString
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        appendToQuickMemo("\(formatter.string(from: Date()))\n\(selected)\n")
    }

    /// ⌘⇧M：クリップボードの内容を、日時を添えてメモの末尾に追記する。
    /// Servicesメニュー（署名・公証がないと一部アプリの一覧に出ない）に代わる、
    /// 「他アプリで文字列をコピー→この操作」で使える簡易版
    @objc func appendClipboardToMemo(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        appendToQuickMemo("\(formatter.string(from: Date()))\n\(text)\n")
    }

    /// メモの末尾に1件追記する。既に開いていればそのウインドウへ挿入して保存し、
    /// 開いていなければファイルへ直接追記する（Android版のappendToQuickMemoと同じ考え方）
    private func appendToQuickMemo(_ entry: String) {
        let url = Document.saveFolderURL.appendingPathComponent(Document.quickMemoFileName)
        if let openDoc = NSDocumentController.shared.documents
            .compactMap({ $0 as? Document })
            .first(where: { $0.fileURL == url }) {
            openDoc.appendQuickMemoEntry(entry)
            return
        }
        var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if !existing.isEmpty, !existing.hasSuffix("\n") { existing += "\n" }
        existing += entry
        try? existing.write(to: url, atomically: true, encoding: .utf8)
    }

    /// ファイルが見つからなければリネーム記録を辿ってから開く
    func openFollowingRename(_ url: URL) {
        var target = url
        if !FileManager.default.fileExists(atPath: target.path) {
            let folder = target.deletingLastPathComponent()
            if let renamed = RenameJournal.resolve(name: target.lastPathComponent, in: folder) {
                let candidate = folder.appendingPathComponent(renamed)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    RecentHistory.remove(url: target)
                    target = candidate
                }
            }
        }
        NSDocumentController.shared.openDocument(withContentsOf: target, display: true) { _, _, error in
            if let error {
                NSAlert(error: error).runModal()
            }
        }
    }

    // ---------- メニュー ----------

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // アプリメニュー
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "KageriEditorについて",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "設定…",
                        action: #selector(AppDelegate.showPreferences(_:)),
                        keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "KageriEditorを隠す",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "ほかを隠す",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "すべてを表示",
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "KageriEditorを終了",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, title: "KageriEditor", to: mainMenu)

        // ファイル
        let fileMenu = NSMenu(title: "ファイル")
        fileMenu.addItem(withTitle: "新規",
                         action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        // ⌘M はmacOS標準の「ウインドウを最小化」と衝突するため⌘⌥Mを使う
        let memoItem = fileMenu.addItem(withTitle: "メモ",
                         action: #selector(AppDelegate.showQuickMemo(_:)), keyEquivalent: "m")
        memoItem.target = self
        memoItem.keyEquivalentModifierMask = [.command, .option]
        // Servicesメニュー（他アプリの選択文字列からメモへ追記）は署名/公証がないと
        // 一部アプリのサービス一覧に出ないため、当面はクリップボード経由の代替として用意
        let pasteMemoItem = fileMenu.addItem(withTitle: "クリップボードからメモに追記",
                         action: #selector(AppDelegate.appendClipboardToMemo(_:)), keyEquivalent: "m")
        pasteMemoItem.target = self
        pasteMemoItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "開く…",
                         action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")

        let historyMenu = NSMenu(title: "履歴")
        historyMenu.delegate = self
        let historyItem = NSMenuItem(title: "履歴", action: nil, keyEquivalent: "")
        historyItem.submenu = historyMenu
        fileMenu.addItem(historyItem)
        self.historyMenu = historyMenu

        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "閉じる",
                         action: #selector(Document.closeSavingFirst(_:)), keyEquivalent: "w")
        // 保存せず閉じ・名前を変更…は⌘系の既定ショートカットを持たないため、
        // Ctrl+文字をこの項目自体に設定してメニュー上にも表示させる
        // （⌘系と両方使う非整形/整形と同じ「可視項目+非表示Shift複製」の形）。
        let closeDiscard = fileMenu.addItem(withTitle: "保存せず閉じる",
                         action: #selector(Document.closeDiscardingChanges(_:)), keyEquivalent: "q")
        closeDiscard.keyEquivalentModifierMask = [.control]
        let closeDiscardShift = fileMenu.addItem(withTitle: "保存せず閉じる",
                         action: #selector(Document.closeDiscardingChanges(_:)), keyEquivalent: "q")
        closeDiscardShift.keyEquivalentModifierMask = [.control, .shift]
        closeDiscardShift.isHidden = true
        closeDiscardShift.allowsKeyEquivalentWhenHidden = true
        fileMenu.addItem(withTitle: "保存",
                         action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let saveAs = fileMenu.addItem(withTitle: "別名で保存…",
                                      action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        let rename = fileMenu.addItem(withTitle: "ファイル名変更…",
                         action: #selector(Document.renameCommand(_:)), keyEquivalent: "t")
        rename.keyEquivalentModifierMask = [.control]
        let renameShift = fileMenu.addItem(withTitle: "ファイル名変更…",
                         action: #selector(Document.renameCommand(_:)), keyEquivalent: "t")
        renameShift.keyEquivalentModifierMask = [.control, .shift]
        renameShift.isHidden = true
        renameShift.allowsKeyEquivalentWhenHidden = true
        fileMenu.addItem(withTitle: "最後に保存した状態に戻す",
                         action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "プリント…",
                         action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p")
        addSubmenu(fileMenu, title: "ファイル", to: mainMenu)

        // 編集
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "やり直す", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "削除", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "すべてを選択",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())

        let removeNL = editMenu.addItem(withTitle: "非整形",
                                        action: #selector(Document.removeNewlinesCommand(_:)),
                                        keyEquivalent: "r")
        removeNL.keyEquivalentModifierMask = [.control]
        // Shift を押したまま（大文字 R）でも動くよう、非表示の別項目でも受ける
        let removeNLShift = editMenu.addItem(withTitle: "非整形",
                                             action: #selector(Document.removeNewlinesCommand(_:)),
                                             keyEquivalent: "r")
        removeNLShift.keyEquivalentModifierMask = [.control, .shift]
        removeNLShift.isHidden = true
        removeNLShift.allowsKeyEquivalentWhenHidden = true

        let wrap = editMenu.addItem(withTitle: "整形",
                                    action: #selector(Document.wrapCommand(_:)),
                                    keyEquivalent: "e")
        wrap.keyEquivalentModifierMask = [.control]
        let wrapShift = editMenu.addItem(withTitle: "整形",
                                         action: #selector(Document.wrapCommand(_:)),
                                         keyEquivalent: "e")
        wrapShift.keyEquivalentModifierMask = [.control, .shift]
        wrapShift.isHidden = true
        wrapShift.allowsKeyEquivalentWhenHidden = true

        let blankLine = editMenu.addItem(withTitle: "空行除去",
                                         action: #selector(Document.removeBlankLinesCommand(_:)),
                                         keyEquivalent: "l")
        blankLine.keyEquivalentModifierMask = [.control]
        let blankLineShift = editMenu.addItem(withTitle: "空行除去",
                                              action: #selector(Document.removeBlankLinesCommand(_:)),
                                              keyEquivalent: "l")
        blankLineShift.keyEquivalentModifierMask = [.control, .shift]
        blankLineShift.isHidden = true
        blankLineShift.allowsKeyEquivalentWhenHidden = true

        let assist = editMenu.addItem(withTitle: "原稿支援…",
                                      action: #selector(Document.manuscriptAssistCommand(_:)),
                                      keyEquivalent: "k")
        assist.keyEquivalentModifierMask = [.control]
        let assistShift = editMenu.addItem(withTitle: "原稿支援…",
                                           action: #selector(Document.manuscriptAssistCommand(_:)),
                                           keyEquivalent: "k")
        assistShift.keyEquivalentModifierMask = [.control, .shift]
        assistShift.isHidden = true
        assistShift.allowsKeyEquivalentWhenHidden = true

        let proofread = editMenu.addItem(withTitle: "推敲…",
                                         action: #selector(Document.proofreadCommand(_:)),
                                         keyEquivalent: "j")
        proofread.keyEquivalentModifierMask = [.control]
        let proofreadShift = editMenu.addItem(withTitle: "推敲…",
                                              action: #selector(Document.proofreadCommand(_:)),
                                              keyEquivalent: "j")
        proofreadShift.keyEquivalentModifierMask = [.control, .shift]
        proofreadShift.isHidden = true
        proofreadShift.allowsKeyEquivalentWhenHidden = true

        let outline = editMenu.addItem(withTitle: "目次…",
                                       action: #selector(Document.outlineCommand(_:)),
                                       keyEquivalent: "u")
        outline.keyEquivalentModifierMask = [.control]
        let outlineShift = editMenu.addItem(withTitle: "目次…",
                                            action: #selector(Document.outlineCommand(_:)),
                                            keyEquivalent: "u")
        outlineShift.keyEquivalentModifierMask = [.control, .shift]
        outlineShift.isHidden = true
        outlineShift.allowsKeyEquivalentWhenHidden = true

        // Ctrl+D は履歴で使っている。見出しの印は「見出し／Heading」で Ctrl+H
        let headingMark = editMenu.addItem(withTitle: "見出しの印を送る",
                                           action: #selector(Document.headingMarkCommand(_:)),
                                           keyEquivalent: "h")
        headingMark.keyEquivalentModifierMask = [.control]
        let headingMarkShift = editMenu.addItem(withTitle: "見出しの印を送る",
                                                action: #selector(Document.headingMarkCommand(_:)),
                                                keyEquivalent: "h")
        headingMarkShift.keyEquivalentModifierMask = [.control, .shift]
        headingMarkShift.isHidden = true
        headingMarkShift.allowsKeyEquivalentWhenHidden = true

        editMenu.addItem(withTitle: "見出しの印をすべて外す",
                         action: #selector(Document.stripHeadingMarksCommand(_:)),
                         keyEquivalent: "")

        let dateItem = editMenu.addItem(withTitle: "日付を挿入",
                                        action: #selector(Document.insertDateCommand(_:)),
                                        keyEquivalent: ";")
        dateItem.keyEquivalentModifierMask = [.control]
        let timeItem = editMenu.addItem(withTitle: "時刻を挿入",
                                        action: #selector(Document.insertTimeCommand(_:)),
                                        keyEquivalent: ";")
        timeItem.keyEquivalentModifierMask = [.control, .shift]
        editMenu.addItem(.separator())

        // 検索サブメニュー
        let findMenu = NSMenu(title: "検索")
        let findItem = findMenu.addItem(withTitle: "検索…",
                                        action: #selector(NSTextView.performTextFinderAction(_:)),
                                        keyEquivalent: "f")
        findItem.tag = NSTextFinder.Action.showFindInterface.rawValue
        let replaceItem = findMenu.addItem(withTitle: "検索と置換…",
                                           action: #selector(NSTextView.performTextFinderAction(_:)),
                                           keyEquivalent: "f")
        replaceItem.keyEquivalentModifierMask = [.command, .option]
        replaceItem.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        let nextItem = findMenu.addItem(withTitle: "次を検索",
                                        action: #selector(NSTextView.performTextFinderAction(_:)),
                                        keyEquivalent: "g")
        nextItem.tag = NSTextFinder.Action.nextMatch.rawValue
        let prevItem = findMenu.addItem(withTitle: "前を検索",
                                        action: #selector(NSTextView.performTextFinderAction(_:)),
                                        keyEquivalent: "g")
        prevItem.keyEquivalentModifierMask = [.command, .shift]
        prevItem.tag = NSTextFinder.Action.previousMatch.rawValue
        let useSelItem = findMenu.addItem(withTitle: "選択部分を検索に使用",
                                          action: #selector(NSTextView.performTextFinderAction(_:)),
                                          keyEquivalent: "e")
        useSelItem.tag = NSTextFinder.Action.setSearchString.rawValue
        findMenu.addItem(.separator())
        let matchListItem = findMenu.addItem(withTitle: "検索結果一覧…",
                                             action: #selector(Document.showMatchList(_:)),
                                             keyEquivalent: "f")
        matchListItem.keyEquivalentModifierMask = [.command, .shift]

        let findMenuItem = NSMenuItem(title: "検索", action: nil, keyEquivalent: "")
        findMenuItem.submenu = findMenu
        editMenu.addItem(findMenuItem)
        addSubmenu(editMenu, title: "編集", to: mainMenu)

        // フォーマット
        let formatMenu = NSMenu(title: "フォーマット")
        let fontPanelItem = formatMenu.addItem(withTitle: "フォントパネルを表示…",
                                               action: #selector(NSFontManager.orderFrontFontPanel(_:)),
                                               keyEquivalent: "t")
        fontPanelItem.target = NSFontManager.shared
        formatMenu.addItem(.separator())
        let invisiblesItem = formatMenu.addItem(withTitle: "改行・全角スペースを表示",
                                                action: #selector(AppDelegate.toggleInvisibles(_:)),
                                                keyEquivalent: "")
        invisiblesItem.state = UserDefaults.standard.bool(forKey: "showInvisibles") ? .on : .off
        formatMenu.addItem(.separator())
        let readingItem = formatMenu.addItem(withTitle: "閲覧モード",
                                             action: #selector(Document.toggleReadingMode(_:)),
                                             keyEquivalent: "b")
        readingItem.keyEquivalentModifierMask = [.control]
        addSubmenu(formatMenu, title: "フォーマット", to: mainMenu)

        // ウインドウ
        let windowMenu = NSMenu(title: "ウインドウ")
        windowMenu.addItem(withTitle: "しまう",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "拡大／縮小",
                           action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "すべてを手前に移動",
                           action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        addSubmenu(windowMenu, title: "ウインドウ", to: mainMenu)
        NSApp.windowsMenu = windowMenu

        // ヘルプ
        let helpMenu = NSMenu(title: "ヘルプ")
        // ヘルプブックを持たないアプリでは、AppKitがヘルプメニューの「先頭の項目」を
        // 標準の「◯◯ヘルプ」とみなして実行時に取り除く。そのため先頭には置かない
        // （先頭に置いた「使い方ガイド」がメニューから消える不具合の原因だった）
        let shortcutHelpItem = helpMenu.addItem(withTitle: "キーボードショートカット一覧",
                                                action: #selector(AppDelegate.showShortcutHelp(_:)),
                                                keyEquivalent: "/")
        shortcutHelpItem.keyEquivalentModifierMask = [.control]
        helpMenu.addItem(withTitle: "使い方ガイド",
                         action: #selector(AppDelegate.showUserGuide(_:)),
                         keyEquivalent: "")
        addSubmenu(helpMenu, title: "ヘルプ", to: mainMenu)
        NSApp.helpMenu = helpMenu

        // ---------------------------------------------------------------
        // Android版に合わせた Ctrl+英字 のショートカット（既存の ⌘ 系はそのまま残す）
        // 各アクションには既にOS標準の ⌘ ショートカットを持つ可視項目があるため、
        // ここではキーボードだけで反応する非表示の複製アイテムを追加する。
        // 非整形(R)・整形(E)は上のeditMenu構築時に既に設定済み。
        // これらの文字はCocoa標準のEmacs系カーソル移動（行末へ/前進/次の行/
        // 1文字削除/改行を開く/文字入れ替え/ペースト）と衝突するが、
        // Android版とのショートカット統一を優先する方針でユーザー承認済み。
        // ---------------------------------------------------------------
        addControlAlias(to: fileMenu, title: "新規",
                        action: #selector(NSDocumentController.newDocument(_:)), key: "n")
        addControlAlias(to: fileMenu, title: "開く…",
                        action: #selector(NSDocumentController.openDocument(_:)), key: "o")
        addControlAlias(to: fileMenu, title: "履歴",
                        action: #selector(AppDelegate.showHistoryMenu(_:)), key: "d")
        addControlAlias(to: fileMenu, title: "保存",
                        action: #selector(NSDocument.save(_:)), key: "s")
        addControlAlias(to: fileMenu, title: "別名で保存…",
                        action: #selector(NSDocument.saveAs(_:)), key: "g")
        // 名前を変更…／保存せず閉じのCtrl+T・Ctrl+Qは、上のfileMenu構築時に
        // 可視項目へ直接設定済み（メニューに表示させるため）。
        addControlAlias(to: fileMenu, title: "閉じる",
                        action: #selector(Document.closeSavingFirst(_:)), key: "w")
        addControlAlias(to: editMenu, title: "取り消す",
                        action: Selector(("undo:")), key: "z")
        addControlAlias(to: editMenu, title: "やり直す",
                        action: Selector(("redo:")), key: "y")
        addControlAlias(to: findMenu, title: "検索…",
                        action: #selector(NSTextView.performTextFinderAction(_:)), key: "f",
                        tag: NSTextFinder.Action.showFindInterface.rawValue)
        addControlAlias(to: appMenu, title: "設定…",
                        action: #selector(AppDelegate.showPreferences(_:)), key: "i")

        return mainMenu
    }

    /// Ctrl+文字（Shift併用の大文字判定にも耐える非表示の複製込み）のショートカットを追加する。
    /// 既存の removeNL/removeNLShift と同じパターン。
    @discardableResult
    private func addControlAlias(
        to menu: NSMenu, title: String, action: Selector, key: String, tag: Int? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.control]
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
        if let tag { item.tag = tag }
        menu.addItem(item)

        let shiftItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        shiftItem.keyEquivalentModifierMask = [.control, .shift]
        shiftItem.isHidden = true
        shiftItem.allowsKeyEquivalentWhenHidden = true
        if let tag { shiftItem.tag = tag }
        menu.addItem(shiftItem)
        return item
    }

    private func addSubmenu(_ menu: NSMenu, title: String, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        mainMenu.addItem(item)
    }
}

// ============================================================
// エントリポイント
// ============================================================
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
