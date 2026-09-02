import Cocoa

/// MarkdownPreview が出した指示を、実際の見た目に変える。
///
/// **本文の文字は1文字も変えない。** NSTextStorageの属性（フォント・色など）を
/// 付け替えるだけなので、保存（tv.string）・字数（文字を数える）には影響しない。
/// `beginEditing/endEditing` による属性だけの変更はNSTextViewの編集パイプラインを
/// 通らないため、undoに積まれず編集済み（dirty）にもならない（Android版のTextWatcherを
/// 呼ばない、というのと同じ理屈）。
///
/// Android版は個々のspanを`applied`に控えて解除時にそれだけを外すが、Macの主エディタは
/// 検索結果の色づけなどを本文のNSTextStorageに直接載せる機能を持たない（一覧はどれも
/// 別ウインドウの別NSTextStorage）ため、もっと単純に「毎回、全体をベースの属性へ戻して
/// から重ね直す」方式にしている。
final class MarkdownPreviewRenderer {

    private(set) var isApplied = false

    /// spanの数が多すぎると描画・レイアウトが重くなるので上限を設ける
    private static let maxMarks = 20000

    func apply(to storage: NSTextStorage, marks: [MarkdownPreview.Mark],
               baseFont: NSFont, paragraphStyle: NSParagraphStyle) {
        storage.beginEditing()
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.setAttributes(Self.baseAttributes(font: baseFont, paragraphStyle: paragraphStyle), range: fullRange)

        var count = 0
        for m in marks {
            guard count < Self.maxMarks else { break }
            let start = max(0, min(m.start, storage.length))
            let end = max(start, min(m.end, storage.length))
            guard end > start else { continue }
            apply(mark: m, range: NSRange(location: start, length: end - start),
                  to: storage, baseFont: baseFont, paragraphStyle: paragraphStyle)
            count += 1
        }
        storage.endEditing()
        isApplied = true
    }

    func clear(_ storage: NSTextStorage, baseFont: NSFont, paragraphStyle: NSParagraphStyle) {
        guard isApplied else { return }
        storage.beginEditing()
        storage.setAttributes(Self.baseAttributes(font: baseFont, paragraphStyle: paragraphStyle),
                              range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        isApplied = false
    }

    private static func baseAttributes(font: NSFont, paragraphStyle: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [.font: font, .paragraphStyle: paragraphStyle, .foregroundColor: NSColor.textColor]
    }

    /// 見出しの大きさ。1段目だけを大きくし、下の段は控えめに差をつける
    private func headingScale(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 1.6
        case 2: return 1.4
        case 3: return 1.25
        case 4: return 1.15
        case 5: return 1.05
        default: return 1.0
        }
    }

    private func apply(mark: MarkdownPreview.Mark, range: NSRange, to storage: NSTextStorage,
                        baseFont: NSFont, paragraphStyle: NSParagraphStyle) {
        switch mark.kind {
        case .hidden:
            // 極端に小さいフォントサイズ（実質ゼロ幅）でTextKitのレイアウトを
            // 壊すことがあった（閲覧モードを抜けると本文が丸ごと表示されなくなる
            // 不具合の原因だった）ため、色だけを消して幅は残す方式にしている。
            // ただしそのままだと、見出しの前などに透明な余白が残って字下げのように
            // 見えてしまう。1文字ずつ「自分の幅ぶんの負のカーニング」を載せて、
            // 1文字ごとに自分の場所を詰める（範囲の最後の1文字だけにまとめて
            // 負のカーニングを載せる方式は、`##`のように隠す文字が複数（特に
            // 見出しの井桁が2つ以上）のときに詰めきれずに残ることがあった）
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? baseFont
            let hiddenText = (storage.string as NSString).substring(with: range)
            for (offset, ch) in hiddenText.enumerated() {
                let charWidth = String(ch).size(withAttributes: [.font: font]).width
                guard charWidth > 0 else { continue }
                storage.addAttribute(.kern, value: -charWidth, range: NSRange(location: range.location + offset, length: 1))
            }

        case .rule:
            // Androidは行の中ほどへ横線を描くが、本文を1文字も変えない作りのままMacで
            // 同じ線を引くにはTextKitの層をもう1つ足す必要があり見送った。
            // 代わりに記法の文字（--- など）へ取り消し線を重ね、区切りであることを示す
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.thick.rawValue, range: range)
            storage.addAttribute(.strikethroughColor, value: NSColor.tertiaryLabelColor, range: range)

        case .heading:
            let size = baseFont.pointSize * headingScale(mark.level)
            storage.addAttribute(.font, value: styledFont(baseFont, size: size, bold: true, italic: false), range: range)

        case .bold:
            storage.addAttribute(.font, value: styledFont(baseFont, size: baseFont.pointSize, bold: true, italic: false), range: range)

        case .italic:
            storage.addAttribute(.font, value: styledFont(baseFont, size: baseFont.pointSize, bold: false, italic: true), range: range)

        case .boldItalic:
            storage.addAttribute(.font, value: styledFont(baseFont, size: baseFont.pointSize, bold: true, italic: true), range: range)

        case .strike:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)

        case .code, .codeBlock:
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular), range: range)
            storage.addAttribute(.backgroundColor, value: NSColor(white: 0.5, alpha: 0.13), range: range)

        case .quote:
            storage.addAttribute(.paragraphStyle, value: indented(paragraphStyle, by: mark.level, unit: 16), range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)

        case .bullet, .ordered:
            // 行頭の記号は隠すので、箇条書きであることは字下げの深さだけで表す
            // （AndroidのBulletSpanのような、文字を足さずに余白へ点を描く手段がMacのTextKitには
            // 単純には無いため、字下げのみの簡略表示にした）
            storage.addAttribute(.paragraphStyle, value: indented(paragraphStyle, by: mark.level + 1, unit: 16), range: range)

        case .link:
            // URLは隠してあるので、文字に下線を引くだけ。色は変えない
            // （明暗どちらの配色でも読めるようにするため。押しても何も起きない＝読むための表示）
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    private func styledFont(_ base: NSFont, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        var font = base.withSize(size)
        let manager = NSFontManager.shared
        if bold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    private func indented(_ base: NSParagraphStyle, by level: Int, unit: CGFloat) -> NSParagraphStyle {
        guard let mutable = base.mutableCopy() as? NSMutableParagraphStyle else { return base }
        let amount = unit * CGFloat(level)
        mutable.headIndent = amount
        mutable.firstLineHeadIndent = amount
        return mutable
    }
}
