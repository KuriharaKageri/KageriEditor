import Foundation

var failures = 0
func check(_ name: String, _ actual: String, _ expected: String) {
    if actual == expected {
        print("OK  \(name)")
    } else {
        failures += 1
        print("NG  \(name)\n  expected: \(expected.debugDescription)\n  actual:   \(actual.debugDescription)")
    }
}
func checkB(_ name: String, _ actual: Bool, _ expected: Bool) {
    if actual == expected {
        print("OK  \(name)")
    } else {
        failures += 1
        print("NG  \(name)  expected \(expected), got \(actual)")
    }
}
func checkArr(_ name: String, _ actual: [String], _ expected: [String]) {
    check(name, actual.joined(separator: "｜"), expected.joined(separator: "｜"))
}
func checkArrI(_ name: String, _ actual: [Int], _ expected: [Int]) {
    check(name, actual.map(String.init).joined(separator: "｜"), expected.map(String.init).joined(separator: "｜"))
}
func checkD(_ name: String, _ actual: Double, _ expected: Double) {
    if abs(actual - expected) < 0.0001 {
        print("OK  \(name)")
    } else {
        failures += 1
        print("NG  \(name)  expected \(expected), got \(actual)")
    }
}

// ---- 全角換算カウント ----
checkD("全角のみ", CharWidth.zenkakuCount("あいうえお"), 5)
checkD("半角のみ", CharWidth.zenkakuCount("abcde"), 2.5)
checkD("混在＋改行は数えない", CharWidth.zenkakuCount("あa\nい1"), 3)
checkD("全角スペース・全角英数", CharWidth.zenkakuCount("\u{3000}Ａ１"), 3)
checkD("句読点・かぎ括弧", CharWidth.zenkakuCount("「こんにちは。」"), 8)

// ---- 改行除去 ----
check("単純な連結",
      TextTransform.removeNewlines("春は\nあけぼの。"),
      "春はあけぼの。")
check("全角スペース行頭は段落として維持",
      TextTransform.removeNewlines("\u{3000}春はあけぼの。やうやう\n白くなりゆく山際\n\u{3000}夏は夜。"),
      "\u{3000}春はあけぼの。やうやう白くなりゆく山際\n\u{3000}夏は夜。")
check("かぎ括弧行頭は段落として維持",
      TextTransform.removeNewlines("と言った。\n「なるほど」\nと彼は返した。"),
      "と言った。\n「なるほど」と彼は返した。")
check("空行は維持",
      TextTransform.removeNewlines("一段落目の\n続き\n\n二段落目"),
      "一段落目の続き\n\n二段落目")
check("末尾改行の維持（次行が空）",
      TextTransform.removeNewlines("本文\n"),
      "本文\n")

// ---- スペース除去 ----
check("半角スペースのみ除去",
      TextTransform.removeSpaces("東京 大阪 名古屋", removeFullWidth: false, removeHalfWidth: true),
      "東京大阪名古屋")
check("全角スペースのみ除去（行頭以外）",
      TextTransform.removeSpaces("東京　大阪　名古屋", removeFullWidth: true, removeHalfWidth: false),
      "東京大阪名古屋")
check("行頭の全角スペースは全角除去オンでも常に維持",
      TextTransform.removeSpaces("\u{3000}東京　大阪", removeFullWidth: true, removeHalfWidth: false),
      "\u{3000}東京大阪")
check("行頭の全角スペースは複数行それぞれで維持",
      TextTransform.removeSpaces("\u{3000}一段落目　です\n\u{3000}二段落目　です", removeFullWidth: true, removeHalfWidth: false),
      "\u{3000}一段落目です\n\u{3000}二段落目です")
check("全角・半角どちらもオフなら変更しない",
      TextTransform.removeSpaces("東京 大阪　名古屋", removeFullWidth: false, removeHalfWidth: false),
      "東京 大阪　名古屋")
check("全角・半角両方オンで両方除去（行頭全角スペースは維持）",
      TextTransform.removeSpaces("\u{3000}東京 大阪　名古屋", removeFullWidth: true, removeHalfWidth: true),
      "\u{3000}東京大阪名古屋")
check("空行はそのまま",
      TextTransform.removeSpaces("一行目\n\n三行目", removeFullWidth: true, removeHalfWidth: true),
      "一行目\n\n三行目")

// ---- 原稿支援 ----
func assist(_ text: String, _ o: TextTransform.AssistOptions) -> String {
    TextTransform.assist(text, options: o)
}

check("支援_何も選ばなければ変化しない",
      assist("あ い　う", TextTransform.AssistOptions()),
      "あ い　う")
check("支援_半角スペースだけ除去",
      assist("あ い　う", TextTransform.AssistOptions(removeHalfWidthSpace: true)),
      "あい　う")
// 行頭の全角スペース（字下げ）は既定では残る
check("支援_全角スペース除去でも行頭の字下げは残る",
      assist("\u{3000}あい　う", TextTransform.AssistOptions(removeFullWidthSpace: true)),
      "\u{3000}あいう")
check("支援_行頭の字下げも除去するを選べば消える",
      assist("\u{3000}あい　う",
             TextTransform.AssistOptions(removeFullWidthSpace: true, removeLeadingIndent: true)),
      "あいう")
// 行頭タブは字下げとみなして全角スペースへ、行中タブは除去
check("支援_行頭タブは全角スペースになり行中タブは消える",
      assist("\tあい\tう", TextTransform.AssistOptions(removeTab: true)),
      "\u{3000}あいう")
// 行頭タブ→全角スペースにした上で、字下げも除去するなら消える
check("支援_行頭タブ変換後に字下げ除去も効く",
      assist("\tあい\tう",
             TextTransform.AssistOptions(removeFullWidthSpace: true, removeTab: true,
                                         removeLeadingIndent: true)),
      "あいう")
check("支援_数字を半角に",
      assist("２０２６年３月１日", TextTransform.AssistOptions(digitsToHalfWidth: true)),
      "2026年3月1日")
check("支援_アルファベットを半角に",
      assist("ＫａｇｅｒｉＥｄｉｔｏｒ", TextTransform.AssistOptions(alphabet: .halfWidth)),
      "KageriEditor")
check("支援_アルファベットを全角に",
      assist("ABC", TextTransform.AssistOptions(alphabet: .fullWidth)),
      "ＡＢＣ")
check("支援_数字とアルファベットは同時に変換できる",
      assist("ＡＢＣ１２３",
             TextTransform.AssistOptions(digitsToHalfWidth: true, alphabet: .halfWidth)),
      "ABC123")
check("支援_行頭に字下げを追加",
      assist("あいう\nかきく", TextTransform.AssistOptions(addLeadingIndent: true)),
      "\u{3000}あいう\n\u{3000}かきく")
check("支援_空行には字下げを追加しない",
      assist("あいう\n\nかきく", TextTransform.AssistOptions(addLeadingIndent: true)),
      "\u{3000}あいう\n\n\u{3000}かきく")
check("支援_カッコで始まる会話文には字下げを追加しない",
      assist("あいう\n「そうですね」\n」と続く", TextTransform.AssistOptions(addLeadingIndent: true)),
      "\u{3000}あいう\n「そうですね」\n」と続く")
check("支援_箇条書きや丸付き数字にも字下げを追加しない",
      assist("・りんご\n①手順\n本文", TextTransform.AssistOptions(addLeadingIndent: true)),
      "・りんご\n①手順\n\u{3000}本文")
check("支援_すでに字下げ済みの行を二重に下げない",
      assist("\u{3000}あいう", TextTransform.AssistOptions(addLeadingIndent: true)),
      "\u{3000}あいう")
check("支援_すべての改行の直後に空行を入れる",
      assist("あ\nい\nう", TextTransform.AssistOptions(addBlankLines: true)),
      "あ\n\nい\n\nう")
// 一字下げのない行も会話文も、区別せず一律に1行あける
check("支援_空行追加は段落の判定をしない",
      assist("あ\n「い」\n\u{3000}う", TextTransform.AssistOptions(addBlankLines: true)),
      "あ\n\n「い」\n\n\u{3000}う")
// 既に空行がある箇所も同じ規則で処理する（改行の数だけ増える）
check("支援_既存の空行も同様に増える",
      assist("あ\n\nい", TextTransform.AssistOptions(addBlankLines: true)),
      "あ\n\n\n\nい")
check("支援_改行がなければ空行は増えない",
      assist("あいう", TextTransform.AssistOptions(addBlankLines: true)),
      "あいう")
// 字下げを付けてから空行を入れる（空行に字下げが入らない）
check("支援_字下げ追加と空行追加を同時に使える",
      assist("あ\nい", TextTransform.AssistOptions(addLeadingIndent: true, addBlankLines: true)),
      "\u{3000}あ\n\n\u{3000}い")
// 除去→追加の順に走るので、バラバラの字下げを一度で揃えられる
check("支援_字下げを除去してから付け直せる",
      assist("\u{3000}\u{3000}あいう\nかきく",
             TextTransform.AssistOptions(removeFullWidthSpace: true, removeLeadingIndent: true,
                                         addLeadingIndent: true)),
      "\u{3000}あいう\n\u{3000}かきく")

// ---- 指定文字数で改行 ----
check("全角10字で折り返し",
      TextTransform.wrap("あいうえおかきくけこさしすせそ", limit: 10),
      "あいうえおかきくけこ\nさしすせそ")
check("半角は0.5換算",
      TextTransform.wrap("abcdefghijklmnopqrst", limit: 5),
      "abcdefghij\nklmnopqrst")
check("既存の改行でカウンタがリセットされる",
      TextTransform.wrap("あいう\nえおかきくけこさしすせ", limit: 10),
      "あいう\nえおかきくけこさしす\nせ")
check("ちょうど上限なら改行しない",
      TextTransform.wrap("あいうえお", limit: 5),
      "あいうえお")
check("混在幅（全角換算3字で折り返し）",
      TextTransform.wrap("あaいiうuえeおo", limit: 3),
      "あaいi\nうuえe\nおo")
check("整形は渡された文字列の先頭（＝行頭）から字数を数える",
      TextTransform.wrap("あいうえおかきくけこ", limit: 5),
      "あいうえお\nかきくけこ")

// ---- 整形：行頭禁則（追い出し・ぶら下がり） ----
check("句読点は行頭に来ず前行末にぶら下がる",
      TextTransform.wrap("あいうえおかきくけこ、さしすせそ", limit: 10),
      "あいうえおかきくけこ、\nさしすせそ")
check("閉じ括弧は行頭に来ず前行末にぶら下がる",
      TextTransform.wrap("あいうえおかきくけこ）さしすせそ", limit: 10),
      "あいうえおかきくけこ）\nさしすせそ")
check("小書き文字（拗促音）は行頭に来ず前行末にぶら下がる",
      TextTransform.wrap("あいうえおかきくけこっさしすせそ", limit: 10),
      "あいうえおかきくけこっ\nさしすせそ")
check("長音符は行頭に来ず前行末にぶら下がる",
      TextTransform.wrap("あいうえおかきくけこーさしすせそ", limit: 10),
      "あいうえおかきくけこー\nさしすせそ")
check("半角ピリオドも行頭禁則の対象",
      TextTransform.wrap("abcdefghij.klmnop", limit: 5),
      "abcdefghij.\nklmnop")
check("禁則文字が2文字連続してもぶら下がる",
      TextTransform.wrap("あいうえおかきくけこ。」さしすせそ", limit: 10),
      "あいうえおかきくけこ。」\nさしすせそ")
check("禁則文字が3文字連続する場合は3文字目で強制改行",
      TextTransform.wrap("あいうえおかきくけこ。」）さしすせそ", limit: 10),
      "あいうえおかきくけこ。」\n）さしすせそ")


// ---- 1行目からのファイル名生成 ----
check("基本：1行目を名前に",
      FileNaming.fileName(fromFirstLineOf: "吾輩は猫である\n名前はまだ無い"),
      "吾輩は猫である")
check("全角20文字で切り詰め",
      FileNaming.fileName(fromFirstLineOf: "あいうえおかきくけこさしすせそたちつてとなにぬねの"),
      "あいうえおかきくけこさしすせそたちつてと")
check("半角は0.5換算（半角40文字まで）",
      FileNaming.fileName(fromFirstLineOf: String(repeating: "a", count: 50)),
      String(repeating: "a", count: 40))
check("スラッシュ・コロンは全角に置換",
      FileNaming.fileName(fromFirstLineOf: "企画/メモ: 第1回"),
      "企画／メモ： 第1回")
check("冒頭の空行は読み飛ばして次の行を名前にする",
      FileNaming.fileName(fromFirstLineOf: "\n本文"),
      "本文")
check("冒頭の空白だけの行も読み飛ばす",
      FileNaming.fileName(fromFirstLineOf: "  \n本文"),
      "本文")
check("冒頭に複数の空行があっても読み飛ばす",
      FileNaming.fileName(fromFirstLineOf: "\n\n\n本文タイトル\n続き"),
      "本文タイトル")
check("文字がある行が一つもなければ無題",
      FileNaming.fileName(fromFirstLineOf: "\n\n  \n"),
      "無題")
check("先頭のドットは除去",
      FileNaming.fileName(fromFirstLineOf: "...メモ"),
      "メモ")


// ---- 箇条書き記号・丸付き数字の段落判定 ----
check("丸付き数字の行頭は段落として維持",
      TextTransform.removeNewlines("手順は次のとおり。\n①電源を入れる\n②起動を待つ\n続きの文章"),
      "手順は次のとおり。\n①電源を入れる\n②起動を待つ続きの文章")
check("㊿など拡張の丸付き数字も維持",
      TextTransform.removeNewlines("前文\n㊿最後の項目"),
      "前文\n㊿最後の項目")
check("中黒・各種記号の行頭は段落として維持",
      TextTransform.removeNewlines("一覧\n・りんご\n●みかん\n○ぶどう\n◎もも\n■なし\n□かき\n◆うめ\n◇すもも"),
      "一覧\n・りんご\n●みかん\n○ぶどう\n◎もも\n■なし\n□かき\n◆うめ\n◇すもも")


// ---- 400字詰め原稿用紙の換算（20字×20行・行ベース・切り捨て） ----
func checkI(_ name: String, _ actual: Int, _ expected: Int) {
    if actual == expected {
        print("OK  \(name)")
    } else {
        failures += 1
        print("NG  \(name)  expected \(expected), got \(actual)")
    }
}

checkI("原稿用紙行_20字は1行", CharWidth.manuscriptLines(String(repeating: "あ", count: 20)), 1)
checkI("原稿用紙行_21字は2行", CharWidth.manuscriptLines(String(repeating: "あ", count: 21)), 2)
checkI("原稿用紙行_改行すると行末の余白も1行を消費する",
       CharWidth.manuscriptLines("あいうえお\nかき"), 2)
checkI("原稿用紙行_空行も1行と数える", CharWidth.manuscriptLines("あ\n\nい"), 3)
checkI("原稿用紙行_半角40字は1行", CharWidth.manuscriptLines(String(repeating: "a", count: 40)), 1)

checkD("原稿用紙枚_20行で1枚",
       CharWidth.manuscriptSheets(String(repeating: "あ", count: 20) + String(repeating: "\n", count: 19)), 1.0)
checkD("原稿用紙枚_19行は09枚で1枚にしない",
       CharWidth.manuscriptSheets(String(repeating: "あ\n", count: 18) + "あ"), 0.9)
checkD("原稿用紙枚_改行なし400字は1枚",
       CharWidth.manuscriptSheets(String(repeating: "あ", count: 400)), 1.0)
checkD("原稿用紙枚_381字で20行に達し1枚",
       CharWidth.manuscriptSheets(String(repeating: "あ", count: 381)), 1.0)
checkD("原稿用紙枚_380字は19行で09枚",
       CharWidth.manuscriptSheets(String(repeating: "あ", count: 380)), 0.9)
checkD("原稿用紙枚_空文字は0枚", CharWidth.manuscriptSheets(""), 0.0)

// ---- 空行の段階的削除 ----
check("空行1行は1回で消える", TextTransform.removeBlankLinesStep("あ\n\nい"), "あ\nい")
check("空行2行は1回で1行だけ減る", TextTransform.removeBlankLinesStep("あ\n\n\nい"), "あ\n\nい")
check("空行3行は2回で1行になる",
      TextTransform.removeBlankLinesStep(TextTransform.removeBlankLinesStep("あ\n\n\n\nい")), "あ\n\nい")
check("複数箇所の空行はそれぞれ1行ずつ減る",
      TextTransform.removeBlankLinesStep("あ\n\nい\n\n\nう"), "あ\nい\n\nう")
check("空行がなければ変化しない", TextTransform.removeBlankLinesStep("あ\nい\nう"), "あ\nい\nう")

// ---- 原稿支援: 空白だけの行 ----
check("支援_空白だけの行は字下げを残す設定でも空になる",
      TextTransform.assist("\u{3000}本文\n\u{3000}\u{3000}\u{3000}\n\u{3000}次の段落",
                           options: TextTransform.AssistOptions(removeFullWidthSpace: true)),
      "\u{3000}本文\n\n\u{3000}次の段落")
check("支援_除去を選んでいなければ空白の行はそのまま",
      TextTransform.assist("あ\n\u{3000}\u{3000}\u{3000}\nい",
                           options: TextTransform.AssistOptions(addLeadingIndent: true)),
      "\u{3000}あ\n\u{3000}\u{3000}\u{3000}\n\u{3000}い")

// ---- 原稿支援: 単位を半角に ----
check("支援_単位だけを半角にする",
      TextTransform.assist("全長158.1ｋｍの路線",
                           options: TextTransform.AssistOptions(unitsToHalfWidth: true)),
      "全長158.1kmの路線")
check("支援_数字の後ろでない英字は単位とみなさない",
      TextTransform.assist("ＳＴＯＰｉｔは158.1ｋｍを走る",
                           options: TextTransform.AssistOptions(unitsToHalfWidth: true)),
      "ＳＴＯＰｉｔは158.1kmを走る")
check("支援_斜線でつながる単位も半角にする",
      TextTransform.assist("最高速度は100ｋｍ／ｈ、風速は20ｍ／ｓ",
                           options: TextTransform.AssistOptions(unitsToHalfWidth: true)),
      "最高速度は100km/h、風速は20m/s")
check("支援_アルファベットを全角にしても単位は半角に残る",
      TextTransform.assist("STOPitは100km/hで走る",
                           options: TextTransform.AssistOptions(alphabet: .fullWidth, unitsToHalfWidth: true)),
      "ＳＴＯＰｉｔは100km/hで走る")

// ---- 推敲 ----
func proofOnly(_ kind: ProofCheck.Kind) -> ProofCheck.Options {
    var o = ProofCheck.Options()
    o.sentenceEnd = kind == .sentenceEnd
    o.particleRepeat = kind == .particleRepeat
    o.noChain = kind == .noChain
    o.longSentence = kind == .longSentence
    o.variant = kind == .variant
    o.typo = kind == .typo
    return o
}
func proof(_ text: String, _ kind: ProofCheck.Kind) -> [ProofCheck.Finding] {
    ProofCheck.run(text, options: proofOnly(kind))
}

// 語尾は文字ではなく型で比べる
checkI("推敲_文字が違っても過去は同じ型",
       ProofCheck.endingType("人々を運んだ。") == .ta &&
       ProofCheck.endingType("輸送量も増えた。") == .ta &&
       ProofCheck.endingType("需要が高まった。") == .ta ? 1 : 0, 1)
checkI("推敲_断定と過去を取り違えない",
       ProofCheck.endingType("これは転換点だ。") == .da &&
       ProofCheck.endingType("荷物を運んだ。") == .ta ? 1 : 0, 1)
checkI("推敲_丁寧はます_ました_ませんを分ける",
       ProofCheck.endingType("走ります。") == .masu &&
       ProofCheck.endingType("開業しました。") == .mashita &&
       ProofCheck.endingType("ありません。") == .masen ? 1 : 0, 1)
checkI("推敲_体言止めは判定しない",
       ProofCheck.endingType("新橋―横浜間の開業。") == .other ? 1 : 0, 1)

checkI("推敲_語尾が三文続くと指摘する",
       proof("人々を運んだ。輸送量も増えた。需要が高まった。", .sentenceEnd).count, 1)
checkI("推敲_二文なら指摘しない",
       proof("人々を運んだ。輸送量も増えた。", .sentenceEnd).count, 0)
checkI("推敲_段落をまたぐ連続は数えない",
       proof("運んだ。増えた。\n高まった。広がった。", .sentenceEnd).count, 0)
checkI("推敲_箇条書きは対象外",
       proof("・新橋に着いた\n・横浜に着いた\n・神戸に着いた", .sentenceEnd).count, 0)
checkI("推敲_ますとませんが混ざれば連続としない",
       proof("土台になります。差し替えます。ダイアログがありません。", .sentenceEnd).count, 0)

checkI("推敲_同じ助詞が四回で指摘する",
       proof("新橋が起点となった鉄道が横浜まで延びる工事が遅れて開業が翌年になった。", .particleRepeat).count, 1)
// 文脈上どうしても同じ助詞が続くとき、読点で意味を切り分けてリズムを整えるのは
// 書き手の技術なので、続けざまに重なる場合と同じには扱わない（4回でも黙る）
checkI("推敲_読点で切り分けてあれば指摘しない",
       proof("新橋が起点となったが、横浜側が先に完成し、開業が遅れた。", .particleRepeat).count, 0)
// 読点1つぶんの割り引きでは4回に届かない（4 − 0.5 = 3.5）
checkI("推敲_四回で読点が一つなら指摘しない",
       proof("新橋が起点となった鉄道が横浜まで延び、工事が遅れて開業が翌年になった。", .particleRepeat).count, 0)
// 割り引いてもなお多ければ指摘する（5 − 0.5 = 4.5）
checkI("推敲_読点があっても回数が多ければ指摘する",
       proof("新橋が起点となった鉄道が横浜まで延び、工事が遅れて開業が翌年になり利用者が戸惑った。", .particleRepeat).count, 1)
checkI("推敲_三回なら指摘しない",
       proof("新橋が起点となったが、横浜側が先に完成した。", .particleRepeat).count, 0)
checkI("推敲_引用のとは数えない",
       proof("「日本でも展開すべき」と要望を送るうちに呼ばれ、渡米すると「あなたがやればいい」と押されて代理店として創業した。", .particleRepeat).count, 0)
checkI("推敲_できるのでは数えない",
       proof("駅前では匿名で相談できるが、窓口では受け付けできない。", .particleRepeat).count, 0)
checkI("推敲_動詞のがるは数えない",
       proof("確率が上がる。物語が盛り上がり、費用が膨れ上がった。", .particleRepeat).count, 0)

checkI("推敲_のが三つ続くと指摘する",
       proof("日本の鉄道の歴史の転換点だった。", .noChain).count, 1)
checkI("推敲_読点を挟めば途切れる",
       proof("日本の鉄道の、歴史の転換点だった。", .noChain).count, 0)

checkI("推敲_長い文を指摘する",
       proof(String(repeating: "あ", count: 120) + "。", .longSentence).count, 1)
checkI("推敲_上限以下なら指摘しない",
       proof(String(repeating: "あ", count: 50) + "。", .longSentence).count, 0)

checkI("推敲_表記ゆれは少ない方を指摘する",
       proof("子供が来た。子どもが遊ぶ。子どもが帰る。", .variant).count, 1)
checkI("推敲_片方で統一されていれば黙る",
       proof("子どもが来た。子どもが遊ぶ。", .variant).count, 0)
checkI("推敲_複合語の漢字を巻き込まない",
       proof("記事を書く。事故が起きた。仕事をする。", .variant).count, 0)
checkI("推敲_というやそういうのいうは数えない",
       proof("谷山氏は言う。そういう心理が働くという。相談しやすいという環境がいる。", .variant).count, 0)
checkI("推敲_そのものは数えない",
       proof("未来そのものを変える。読んだ物を並べる。", .variant).count, 0)
checkI("推敲_ものの逆接は数えない",
       proof("出来事だったものの、1分しかたっていない。読んだ物を並べる。", .variant).count, 0)
checkI("推敲_複合名詞の物は数えない",
       proof("大切な食べ物であり、海の生き物が減る。買い物に行く。読んだものを並べる。", .variant).count, 0)
checkI("推敲_連体形に続く物とものは拾う",
       proof("読んだ物を並べる。読んだものを数える。読んだものを片づける。", .variant).count, 1)
checkI("推敲_変更にの更を更にと混同しない",
       proof("運用変更に合わせて組み換える。", .variant).count, 0)
checkI("推敲_変更にがあっても更にとさらにの表記ゆれは拾う",
       proof("運用変更に合わせて、さらに更に手を加える。", .variant).count, 1)

// 会話文は句点なしで「」を閉じるので、そこで文が切れないと次の段落とつながる
checkI("推敲_閉じ括弧で終わる行は文が切れる",
       ProofCheck.splitSentences(Array("「そう思いました」\n\u{3000}起業のきっかけは出会いだった。")).count, 2)
// 整形が入れた改行で文が分断されないよう、改行1つでは切らない
checkI("推敲_改行だけでは文を切らない",
       ProofCheck.splitSentences(Array("次の一致箇所へ\n移動します。")).count, 1)

// ---- 単位 ----
checkI("単位_全角の単位は揺れていなくても指摘する",
       proof("全長158.1ｋｍの路線だ。", .variant).count, 1)
checkI("単位_半角なら何も言わない",
       proof("全長158.1kmの路線だ。", .variant).count, 0)
checkI("単位_全角の単語と半角の単位が同居していてよい",
       proof("ＳＴＯＰｉｔを導入した。全長158.1kmだ。", .variant).count, 0)
checkI("単位_斜線でつながる単位はひとまとまりで1件",
       proof("最高速度は100ｋｍ/ｈだ。", .variant).count, 1)
checkI("単位_毎秒メートルも拾う",
       proof("風速は20ｍ/ｓだった。", .variant).count, 1)
checkI("単位_数字の後ろでなければ単位ではない",
       proof("ＬはＬでも大文字だ。", .variant).count, 0)

checkI("推敲_誤植の助詞の重複を拾う", proof("鉄道がが開業した。", .typo).count, 1)
checkI("推敲_語頭の重なりは拾わない", proof("がががんばる。", .typo).count, 0)
checkI("推敲_問題がなければ空を返す",
       ProofCheck.run("春はあけぼの。やうやう白くなりゆく山際、少し明かりて。").count, 0)
checkI("推敲_空文字でも落ちない", ProofCheck.run("").count, 0)

// 文頭の「ところが」は接続で、漢字で書くことはない。形式名詞として数えない
checkI("推敲_文頭のところがは形式名詞ではない",
       proof("訪れた所は静かだった。ところが、誰もいなかった。", .variant).count, 0)
checkI("推敲_文頭のところでも数えない",
       proof("訪れた所は静かだった。ところで、話は変わる。", .variant).count, 0)
// 連体形の語尾に続く本当の形式名詞は、これまでどおり拾う
checkI("推敲_連体形に続くところは拾う",
       proof("読んだところ、正しかった。訪れた所は静かだった。", .variant).count, 1)

// 「ごとき」は助動詞「ごとし」で、形式名詞の「とき」ではない
checkI("推敲_ごときはときと数えない",
       proof("小供のごときは。その時は静かだった。", .variant).count, 0)
checkI("推敲_ひとときもときと数えない",
       proof("ひとときの静けさ。その時は過ぎた。", .variant).count, 0)
// 本当の形式名詞の「とき」は、これまでどおり拾う
checkI("推敲_連体形に続くときは拾う",
       proof("読んだとき、正しかった。その時は静かだった。", .variant).count, 1)

// ---- 英文の行には字下げを足さない ----
var assistIndentOnly = TextTransform.AssistOptions()
assistIndentOnly.addLeadingIndent = true
// 一字下げは日本語の段落の作法なので、英文の行には足さない
check("原稿支援_英文の行には字下げを足さない",
      TextTransform.assist("The quick brown fox.", options: assistIndentOnly),
      "The quick brown fox.")
check("原稿支援_URLの行にも足さない",
      TextTransform.assist("https://example.com/article", options: assistIndentOnly),
      "https://example.com/article")
// 英単語で始まっても、日本語が入っていれば段落なので字下げする
check("原稿支援_英単語で始まる日本語の段落は字下げする",
      TextTransform.assist("iPadは便利だ。", options: assistIndentOnly), "\u{3000}iPadは便利だ。")
check("原稿支援_日本語の段落はこれまでどおり字下げする",
      TextTransform.assist("本文です。", options: assistIndentOnly), "\u{3000}本文です。")

// ---- 英文の中の空白は残す ----
var assistHalfOnly = TextTransform.AssistOptions()
assistHalfOnly.removeHalfWidthSpace = true
// 英単語の「間」を詰めたい場面は無い。前後が半角なら英文の一部とみなす
check("原稿支援_英文の空白は残す",
      TextTransform.assist("これでは「法の支配（rule of law）」ではない。", options: assistHalfOnly),
      "これでは「法の支配（rule of law）」ではない。")
check("原稿支援_日本語に混じった空白は消す",
      TextTransform.assist("ICC の判断 について。", options: assistHalfOnly), "ICCの判断について。")
// 「Mr. Smith」のように、前が記号でも後ろが英字なら英文
check("原稿支援_英文の記号のあとの空白も残す",
      TextTransform.assist("Mr. Smith が来た。", options: assistHalfOnly), "Mr. Smithが来た。")
// 「1. はじめに」は日本語なので消える
check("原稿支援_番号のあとの日本語は詰める",
      TextTransform.assist("1. はじめに", options: assistHalfOnly), "1.はじめに")
// 英文の中は残り、日本語との境目だけが消える
check("原稿支援_英文と日本語の境目だけ消す",
      TextTransform.assist("the ICC でした", options: assistHalfOnly), "the ICCでした")

// ---- 見えない文字 ----
// 幅ゼロの書式制御文字は0字。以前は半角1つぶんとして数えていた
checkD("字数_ゼロ幅空白は数えない", CharWidth.measure("あ\u{200B}い").zenkaku, 2.0)
checkD("字数_BOMは数えない", CharWidth.measure("あ\u{FEFF}い").zenkaku, 2.0)
checkD("字数_単語結合子は数えない", CharWidth.measure("あ\u{2060}い").zenkaku, 2.0)
// 見えない空白は、半角スペースと同じ扱いで除去できる
var assistInvisible = TextTransform.AssistOptions()
assistInvisible.removeHalfWidthSpace = true
check("原稿支援_見えない空白も除去する",
      TextTransform.assist("あ\u{00A0}い", options: assistInvisible), "あい")
check("原稿支援_幅ゼロの文字も除去する",
      TextTransform.assist("あ\u{200B}\u{FEFF}い", options: assistInvisible), "あい")
// 選んでいなければ手を触れない
var assistFullOnly = TextTransform.AssistOptions()
assistFullOnly.removeFullWidthSpace = true
check("原稿支援_選ばなければ見えない空白も残す",
      TextTransform.assist("あ\u{00A0}い", options: assistFullOnly), "あ\u{00A0}い")

// ---- 原稿支援は見出しの印に触れない ----
// 「# 」の後ろは半角スペース。除去されると印が壊れ、目次も並べ替えも失われる
var assistHalf = TextTransform.AssistOptions()
assistHalf.removeHalfWidthSpace = true
check("原稿支援_半角スペース除去で印を壊さない",
      TextTransform.assist("# 見出し\n\u{3000}本 文です。", options: assistHalf),
      "# 見出し\n\u{3000}本文です。")
var assistFull = TextTransform.AssistOptions()
assistFull.removeFullWidthSpace = true
assistFull.removeLeadingIndent = true
check("原稿支援_全角スペース除去でも印は残る",
      TextTransform.assist("## 小見出し\n\u{3000}本文です。", options: assistFull),
      "## 小見出し\n本文です。")
// 見出しには字下げを付けない
var assistIndent = TextTransform.AssistOptions()
assistIndent.addLeadingIndent = true
check("原稿支援_見出しには字下げを付けない",
      TextTransform.assist("# 見出し\n本文です。", options: assistIndent),
      "# 見出し\n\u{3000}本文です。")

// ---- 見出し行は整形・非整形しない ----
// 次の行が字下げされていなくても、見出しは飲み込まれない
check("非整形_見出しの後ろの改行を残す",
      TextTransform.removeNewlines("# 見出し\n字下げなしの本文です。"),
      "# 見出し\n字下げなしの本文です。")
check("非整形_見出しの前の改行を残す",
      TextTransform.removeNewlines("字下げなしの本文です。\n# 見出し"),
      "字下げなしの本文です。\n# 見出し")
check("非整形_小見出しも同じ",
      TextTransform.removeNewlines("## 小見出し\n本文です。"), "## 小見出し\n本文です。")
// 本文どうしは、これまでどおり連結する
check("非整形_本文どうしは連結する",
      TextTransform.removeNewlines("あいう。\nえお。"), "あいう。えお。")
// 空行は非整形では詰めない（詰めるのは「空行除去」だけ）
check("非整形_空行は詰めない",
      TextTransform.removeNewlines("あ。\n\nい。"), "あ。\n\nい。")
// 空白だけの行も、書き手には空行に見える。次の行に吸収させない
check("非整形_空白だけの行も詰めない",
      TextTransform.removeNewlines("あ。\n\u{3000}\nい。"), "あ。\n\u{3000}\nい。")
// 長い見出しを折り返すと、後半が本文の行として独立してしまう
check("整形_見出しは折り返さない",
      TextTransform.wrap("# " + String(repeating: "あ", count: 30) + "\n", limit: 20),
      "# " + String(repeating: "あ", count: 30) + "\n")
check("整形_本文はこれまでどおり折り返す",
      TextTransform.wrap(String(repeating: "あ", count: 30), limit: 20),
      String(repeating: "あ", count: 20) + "\n" + String(repeating: "あ", count: 10))
// 印ではない「#」で始まる行は本文なので、これまでどおり折り返す
check("整形_印でないシャープの行は折り返す",
      TextTransform.wrap("#" + String(repeating: "あ", count: 30), limit: 20),
      "#" + String(repeating: "あ", count: 19) + "\n" + String(repeating: "あ", count: 11))
check("整形_空行は詰めない",
      TextTransform.wrap("あ。\n\nい。", limit: 20), "あ。\n\nい。")

// ---- 見出し（簡易アウトライン） ----
func headingTitles(_ text: String) -> [String] { Outline.headings(text).map { $0.text } }

checkI("見出し_字下げのない短い行を拾う",
       headingTitles("姫新線の歴史\n\n\u{3000}姫新線は兵庫県の路線です。") == ["姫新線の歴史"] ? 1 : 0, 1)
checkI("見出し_字下げのある行は本文",
       headingTitles("\u{3000}姫新線は兵庫県の路線です。").count, 0)
checkI("見出し_句点で終わる行は字下げがなくても本文",
       headingTitles("姫新線は兵庫県の路線です。").count, 0)
checkI("見出し_長い行は本文", headingTitles(String(repeating: "あ", count: 40)).count, 0)
checkI("見出し_会話文は見出しにしない", headingTitles("「最初の1年は苦しかったです」").count, 0)
checkI("見出し_箇条書きは見出しにしない", headingTitles("・新橋に着いた\n・横浜に着いた").count, 0)
checkI("見出し_大見出しと小見出しが続いていても両方拾う",
       headingTitles("姫新線の歴史\n伯備線との接続を目指す\n\n\u{3000}姫新線は兵庫県の路線です。").count, 2)
checkI("見出し_プロットは全部拾える",
       headingTitles("姫新線の歴史\n急行列車の時代\n姫新線の車両").count, 3)
checkD("見出し_本文のない見出しは0枚",
       Outline.headings("姫新線の歴史\n急行列車の時代").first?.sheets ?? -1, 0.0)
checkD("見出し_見出しから次の見出しまでを数える",
       Outline.headings("見出し一\n\u{3000}" + String(repeating: "あ", count: 399) + "\n見出し二\n").first?.sheets ?? -1, 1.0)
checkI("見出し_空文字でも落ちない", Outline.headings("").count, 0)
// 「です」の「で」は断定の助動詞で、助詞ではない
checkI("推敲_ですのでは数えない",
       proof("水流の中で育てるので、1カ月で出荷でき、何度でも連作が可能です。", .particleRepeat).count, 0)
// ただし「駅ですぐ」の「で」は助詞なので、これまでどおり数える
checkI("推敲_ですぐのでは数える",
       proof("駅ですぐ乗れる列車で移動し現地で食事をとり宿で休む。", .particleRepeat).count, 1)
// 「こと」の「と」は形式名詞の一部で、助詞ではない
checkI("推敲_ことのとは数えない",
       proof("対等であること、機能が一体になること、共同販売とすること。", .particleRepeat).count, 0)
// 「である」と「だ」は読むと調子が違うので、連続とみなさない
checkI("推敲_であるとだは別の調子",
       proof("この点はデリケートである。差別の記憶に直結するからだ。美化することにも慎重である。", .sentenceEnd).count, 0)
checkI("推敲_であるが三つ続けば指摘する",
       proof("これは事実である。あれも事実である。それも事実である。", .sentenceEnd).count, 1)
// 「いよいよ」の中の「よい」は「良い」の表記ゆれではない
checkI("推敲_いよいよはよいと数えない",
       proof("いよいよ車窓に太平洋が見えてきた。眺めは良い。", .variant).count, 0)
// 「っていう」の「いう」は動詞ではない
checkI("推敲_っていうはいうと数えない",
       proof("便利すぎる物語だなっていうより。彼はこう言う。", .variant).count, 0)
// つなぐ「の」の後ろには必ず名詞が来る。「そのもの。」の「の」は数えない
checkI("推敲_そのものは数えない",
       proof("同じ仕事をする親子の意地の張り合いそのもの。", .noChain).count, 0)

// ---- 章立ての行 ----
// 章の見出しは副題を伴って30字を超えることがよくある
checkI("見出し_長い章見出しも拾う",
       Outline.headings("第1章：淀屋橋駅の朝。限られた番線での秒単位のオペレーション（実況観察）\n\u{3000}本文です。").count, 1)
checkI("見出し_漢数字の章も拾う",
       Outline.headings("第十二章　" + String(repeating: "あ", count: 40) + "\n\u{3000}本文です。").count, 1)
checkI("見出し_第のない章も拾う",
       Outline.headings("2章　" + String(repeating: "あ", count: 40) + "\n\u{3000}本文です。").count, 1)
checkI("見出し_節や話も拾う",
       Outline.headings("第3節　" + String(repeating: "あ", count: 40) + "\n第4話　" + String(repeating: "あ", count: 40) + "\n").count, 2)
// 字下げと句点の規則はそのまま。本文中の「第三章では〜」は拾わない
checkI("見出し_字下げされた章の言及は拾わない",
       Outline.headings("\u{3000}第三章では" + String(repeating: "あ", count: 40) + "\n").count, 0)
checkI("見出し_句点で終わる章の言及は拾わない",
       Outline.headings("第三章では" + String(repeating: "あ", count: 40) + "。\n").count, 0)
// 章立てでない長い行は、これまでどおり本文
checkI("見出し_章立てでない長い行は本文",
       Outline.headings("第一印象は" + String(repeating: "あ", count: 40) + "\n").count, 0)

// ---- 決まり文句の見出し ----
// 副題が付いて長くなっても拾う
checkI("見出し_決まり文句は長さで外さない",
       Outline.headings("はじめに　" + String(repeating: "あ", count: 40) + "\nまとめ：" + String(repeating: "あ", count: 40) + "\n").count, 2)
checkI("見出し_決まり文句だけの行も拾う",
       Outline.headings("おわりに\n\u{3000}本文です。").count, 1)
// 区切りがなければ本文。「はじめに述べたとおり」を巻き込まない
checkI("見出し_決まり文句に続く本文は拾わない",
       Outline.headings("はじめに述べたとおり" + String(repeating: "あ", count: 40) + "\n").count, 0)
checkI("見出し_まとめるとも拾わない",
       Outline.headings("まとめると" + String(repeating: "あ", count: 40) + "\n").count, 0)
// 字下げと句点の規則はそのまま
checkI("見出し_字下げされた決まり文句は拾わない",
       Outline.headings("\u{3000}まとめ　" + String(repeating: "あ", count: 40) + "\n").count, 0)
checkI("見出し_句点で終わる決まり文句は拾わない",
       Outline.headings("おわりに　" + String(repeating: "あ", count: 40) + "。\n").count, 0)

// 箇条書きや注記の印で始まる行は、短くても句点がなくても本文
checkI("見出し_アスタリスクの行は見出しにしない",
       Outline.headings("*注記の行\n\u{3000}本文です。").count, 0)
checkI("見出し_米印の行は見出しにしない",
       Outline.headings("※注記の行\n\u{3000}本文です。").count, 0)
checkI("見出し_ハイフンの行は見出しにしない",
       Outline.headings("-箇条書き\n\u{3000}本文です。").count, 0)
checkI("見出し_ダッシュの行は見出しにしない",
       Outline.headings("――そして誰もいなくなった\n\u{3000}本文です。").count, 0)

// ---- 見出しの印 ----
func headingNames(_ text: String) -> [String] { Outline.headings(text).map { $0.title } }

// 印が1つでもあれば推定をやめる。宣言したものだけが見出しになる
checkI("印_印がある文書では印だけを見出しにする",
       headingNames("# 第一章\n\u{3000}本文です。\n推定なら見出しになる行\n# 第二章\n")
           == ["第一章", "第二章"] ? 1 : 0, 1)
checkI("印_印がなければこれまでどおり推定する",
       headingNames("推定の見出し\n\u{3000}本文です。\n") == ["推定の見出し"] ? 1 : 0, 1)
checkI("印_大見出しと小見出しの段が分かれる",
       Outline.headings("# 大見出し\n## 小見出し\n").map { $0.level } == [1, 2] ? 1 : 0, 1)
// 見出しは2段まで。「###」以上は印ではない
checkI("印_シャープ三つは印ではない", Outline.hasMarks("### 見出し") ? 1 : 0, 0)
// 印はボタンで入れるので、全角と半角の打ち分けに迷うことはない
checkI("印_全角シャープは印ではない", Outline.hasMarks("＃ 見出し") ? 1 : 0, 0)
// 「# 」まで打って中身がまだない行を、見出しとして並べても仕方がない
checkI("印_印だけの行は見出しにしない", Outline.headings("# \n\u{3000}本文です。").count, 0)

// ---- 印は数から除く ----
checkD("印_字数から印を除く",
       CharWidth.measure("# 第一章\n\u{3000}本文", excludeHeadingMarks: true).zenkaku, 6.0)
checkI("印_除いた字数を数えておく",
       CharWidth.measure("# 第一章\n\u{3000}本文", excludeHeadingMarks: true).marks, 2)
checkD("印_除かなければこれまでどおり数える",
       CharWidth.measure("# 第一章\n\u{3000}本文").zenkaku, 7.0)
// 20字ちょうどの見出しは、印を入れると21字になって2行を食う
checkI("印_原稿用紙の行数からも除く",
       CharWidth.manuscriptLines("# " + String(repeating: "あ", count: 20),
                                 excludeHeadingMarks: true), 1)
checkI("印_除かなければ印も行を食う",
       CharWidth.manuscriptLines("# " + String(repeating: "あ", count: 20)), 2)
// 印ではない「#」は、これまでどおり本文として数える
checkD("印_印でないシャープは本文のまま",
       CharWidth.measure("#1 の札", excludeHeadingMarks: true).zenkaku, 3.5)

// ---- 印を付け外しする ----
check("印_なしから大見出しになる",
      Outline.cycleMark("第一章\n\u{3000}本文", selStart: 0, selEnd: 0).text,
      "# 第一章\n\u{3000}本文")
check("印_大見出しから小見出しになる",
      Outline.cycleMark("# 第一章", selStart: 0, selEnd: 0).text, "## 第一章")
check("印_小見出しをもう一度送ると外れる",
      Outline.cycleMark("## 第一章", selStart: 0, selEnd: 0).text, "第一章")
check("印_選択した行をまとめて送る",
      Outline.cycleMark("一\n二\n三", selStart: 0, selEnd: 5).text, "# 一\n# 二\n# 三")
// ばらついている行をそのまま送ると結果が予想できないので、先頭の行に揃える
check("印_ばらついていても先頭の行に揃える",
      Outline.cycleMark("# 一\n二", selStart: 0, selEnd: 6).text, "## 一\n## 二")
// 印を付けた行では、カーソルが印のぶん後ろへ動く
checkI("印_カーソルが印のぶん動く",
       Outline.cycleMark("第一章", selStart: 1, selEnd: 1).selStart, 3)
// 行頭で押したときは印の後ろへ送る。印を付けてすぐ書き始められるように
checkI("印_行頭で押すとカーソルは印の後ろへ",
       Outline.cycleMark("第一章", selStart: 0, selEnd: 0).selStart, 2)
// 空の行に印を付けた直後から書き始められる
checkI("印_空の行でもカーソルは印の後ろへ",
       Outline.cycleMark("\u{3000}本文です。\n\n次の行", selStart: 7, selEnd: 7).selStart, 9)
// 印を外したときは、カーソルが行頭へ戻る
checkI("印_外すとカーソルは行頭へ",
       Outline.cycleMark("## 第一章", selStart: 3, selEnd: 3).selStart, 0)
// 入稿の直前に外せば、画面の字数と受け取った側で数えた字数が一致する
check("印_一括で外す", Outline.stripMarks("# 一\n## 二\n\u{3000}本文"), "一\n二\n\u{3000}本文")
check("印_印がなければ一括で外しても変わらない", Outline.stripMarks("一\n二"), "一\n二")

// ---- ファイル名と見出しの印 ----
// 印は原稿ではないので、ファイル名にも入れない
check("ファイル名_見出しの印は入れない",
      FileNaming.fileName(fromFirstLineOf: "# 姫新線の歴史\n\u{3000}本文です。"), "姫新線の歴史")
check("ファイル名_小見出しの印も入れない",
      FileNaming.fileName(fromFirstLineOf: "## 第一章\n\u{3000}本文です。"), "第一章")
// 「# 」まで打った行はまだ中身がないので、次の行から名前を作る
check("ファイル名_印だけの行は飛ばす",
      FileNaming.fileName(fromFirstLineOf: "# \n姫新線の歴史\n"), "姫新線の歴史")
// 「#」はURLの断片の区切りなので、ファイル名には残さない
check("ファイル名_印でないシャープは全角にする",
      FileNaming.fileName(fromFirstLineOf: "#1 の札"), "＃1 の札")

// ---- 拡張子の解釈（ファイル名変更） ----
// 既知の拡張子（txt/md）ならそれを切り出し、知らない拡張子は題名の一部として扱う
check("拡張子_既知のmdは切り出す",
      FileNaming.withExtension(typed: "メモ.md", fallback: "txt").base, "メモ")
check("拡張子_既知のmdは切り出す_拡張子側",
      FileNaming.withExtension(typed: "メモ.md", fallback: "txt").ext, "md")
check("拡張子_大文字も既知として扱う",
      FileNaming.withExtension(typed: "メモ.MD", fallback: "txt").ext, "md")
check("拡張子_知らない拡張子は題名の一部",
      FileNaming.withExtension(typed: "第3章.決意", fallback: "txt").base, "第3章.決意")
check("拡張子_知らない拡張子はfallbackを補う",
      FileNaming.withExtension(typed: "第3章.決意", fallback: "txt").ext, "txt")
check("拡張子_拡張子なしはfallbackを補う",
      FileNaming.withExtension(typed: "メモ", fallback: "txt").ext, "txt")
check("拡張子_先頭ドットのみは拡張子扱いしない",
      FileNaming.withExtension(typed: ".envrc", fallback: "txt").base, ".envrc")

// ---- 原稿支援のプリセット ----
let samplePreset = AssistPreset(
    name: "出し先A", removeHalf: true, removeFull: false, removeTab: true, removeIndent: false,
    digits: true, units: false, addIndent: true, addBlank: false, alphabet: "full")
let decodedPresets = AssistPresetStore.decode(AssistPresetStore.encode([samplePreset]))
check("プリセット_エンコードデコードで名前が保たれる",
      decodedPresets.first?.name ?? "", "出し先A")
check("プリセット_エンコードデコードでアルファベット設定が保たれる",
      decodedPresets.first?.alphabet ?? "", "full")
checkI("プリセット_チェック項目が保たれる（半角除去オン）",
       (decodedPresets.first?.removeHalf ?? false) ? 1 : 0, 1)
checkI("プリセット_チェック項目が保たれる（全角除去オフ）",
       (decodedPresets.first?.removeFull ?? true) ? 1 : 0, 0)
check("プリセット_不正なJSONは空配列",
      AssistPresetStore.decode("not json").isEmpty ? "空" : "空でない", "空")
check("プリセット_未保存キーは空配列",
      AssistPresetStore.decode(nil).isEmpty ? "空" : "空でない", "空")

let upsertedNew = AssistPresetStore.upserted([samplePreset], with: AssistPreset(
    name: "出し先B", removeHalf: false, removeFull: false, removeTab: false, removeIndent: false,
    digits: false, units: false, addIndent: false, addBlank: false, alphabet: "keep"))
checkI("プリセット_同名が無ければ追加", upsertedNew.count, 2)

let upsertedOverwrite = AssistPresetStore.upserted([samplePreset], with: AssistPreset(
    name: "出し先A", removeHalf: false, removeFull: false, removeTab: false, removeIndent: false,
    digits: false, units: false, addIndent: false, addBlank: false, alphabet: "keep"))
checkI("プリセット_同名があれば上書き（件数は変わらない）", upsertedOverwrite.count, 1)
checkI("プリセット_同名があれば上書き（半角除去はオフになる）",
       (upsertedOverwrite.first?.removeHalf ?? true) ? 1 : 0, 0)

let removedPresets = AssistPresetStore.removed([samplePreset], name: "出し先A")
checkI("プリセット_削除で件数が減る", removedPresets.count, 0)

// ---- 節の並べ替え ----
let reorderDoc = "まえがき。\n# 一章\n\u{3000}本文一。\n\n# 二章\n\u{3000}本文二。\n\n# 三章\n\u{3000}本文三。\n"

func applyPlan(_ text: String, _ plan: [Outline.Placed]) -> String {
    guard let p = Outline.reorderPatch(text, plan: plan) else { return text }
    let ns = text as NSString
    return ns.replacingCharacters(
        in: NSRange(location: p.start, length: p.end - p.start), with: p.replacement)
}

check("節_見出しの前の空行は自分の節に含む",
      (reorderDoc as NSString).substring(with: NSRange(
        location: Outline.sections(reorderDoc)[1].start,
        length: Outline.sections(reorderDoc)[1].end - Outline.sections(reorderDoc)[1].start)),
      "\n# 二章\n\u{3000}本文二。\n")
check("節_最初の見出しより前は節に入らない",
      (reorderDoc as NSString).substring(to: Outline.preambleEnd(reorderDoc)), "まえがき。\n")
// 動かした節が、自分の前の空行を連れていく
check("節_入れ替えても見出しの前の空行が残る",
      applyPlan(reorderDoc, [Outline.Placed(0, 1), Outline.Placed(2, 1), Outline.Placed(1, 1)]),
      "まえがき。\n# 一章\n\u{3000}本文一。\n\n# 三章\n\u{3000}本文三。\n\n# 二章\n\u{3000}本文二。\n")
// 変わっていない前後は書き換えない（大きな文書で全文が作り直されないように）
checkI("節_変わっていない前後は書き換えに含めない",
       Outline.reorderPatch(reorderDoc,
                            plan: [Outline.Placed(0, 1), Outline.Placed(2, 1), Outline.Placed(1, 1)])?.start ?? -1,
       Outline.sections(reorderDoc)[1].start)
checkI("節_変わっていなければ書き換えない",
       Outline.reorderPatch(reorderDoc,
                            plan: [Outline.Placed(0, 1), Outline.Placed(1, 1), Outline.Placed(2, 1)]) == nil ? 1 : 0, 1)
// 取りこぼしや重複のある計画は当てない（本文が消えるため）
checkI("節_壊れた計画は当てない",
       Outline.reorderPatch(reorderDoc,
                            plan: [Outline.Placed(0, 1), Outline.Placed(0, 1), Outline.Placed(2, 1)]) == nil ? 1 : 0, 1)
// 大見出しは、続く小見出しを引き連れて動く
checkI("節_大見出しは小見出しを連れて動く",
       Outline.groupSize(Outline.sections("# A\n## a1\n## a2\n# B\n"), 0), 3)
check("節_段を変えると印が付け替わる",
      applyPlan("# 一\n本文\n# 二\n本文\n", [Outline.Placed(0, 1), Outline.Placed(1, 2)]),
      "# 一\n本文\n## 二\n本文\n")
// 末尾の節には改行がないことがある。そのまま動かすと行が繋がってしまう
check("節_末尾の節を前へ動かすと改行が補われる",
      applyPlan("# 一章\n\u{3000}本文一。\n\n# 二章\n\u{3000}本文二。",
                [Outline.Placed(1, 1), Outline.Placed(0, 1)]),
      "# 二章\n\u{3000}本文二。\n# 一章\n\u{3000}本文一。\n")
// 空行の数はそのまま運ぶ。ただし文書の先頭に来た節は、連れてきた空行を落とす
check("節_先頭に来た節は空行を落とす",
      applyPlan("# 一\n本文一。\n\n\n# 二\n本文二。\n",
                [Outline.Placed(1, 1), Outline.Placed(0, 1)]),
      "# 二\n本文二。\n# 一\n本文一。\n")
// 前書きがあれば、先頭に来た節の空行は前書きとの区切りとして残る
check("節_前書きの後ろでは空行が残る",
      applyPlan("まえがき。\n# 一\n本文一。\n\n\n# 二\n本文二。\n",
                [Outline.Placed(1, 1), Outline.Placed(0, 1)]),
      "まえがき。\n\n\n# 二\n本文二。\n# 一\n本文一。\n")
// 印のない文書は並べ替えの対象にしない（推定の誤りで段落が分断されるため）
checkI("節_印のない文書には節がない",
       Outline.sections("推定の見出し\n\u{3000}本文です。\n").count, 0)

// ---- 推定した見出しに印を打つ ----
func applyMarks(_ text: String, _ starts: [Int]) -> String {
    guard let p = Outline.applyMarks(text, lineStarts: starts) else { return text }
    return (text as NSString).replacingCharacters(
        in: NSRange(location: p.start, length: p.end - p.start), with: p.replacement)
}

let candidateDoc = "見出し一\n\u{3000}本文です。\nキャプション\n見出し二\n"
checkI("確定_推定は三件拾う", Outline.headings(candidateDoc).count, 3)
// 書き手が1件目と3件目だけを選ぶ
check("確定_選んだ行にだけ印を打つ",
      applyMarks(candidateDoc, [Outline.headings(candidateDoc)[0].start,
                                Outline.headings(candidateDoc)[2].start]),
      "# 見出し一\n\u{3000}本文です。\nキャプション\n# 見出し二\n")
// 印を打った文書では推定が止まり、選ばなかった行は見出しでなくなる
checkI("確定_打ったあとは印だけに従う",
       Outline.headings(applyMarks(candidateDoc,
                                   [Outline.headings(candidateDoc)[0].start,
                                    Outline.headings(candidateDoc)[2].start])).count, 2)
checkI("確定_すでに印のある行は飛ばす",
       Outline.applyMarks("# 見出し\n\u{3000}本文です。", lineStarts: [0]) == nil ? 1 : 0, 1)
checkI("確定_一つも選ばなければ何もしない",
       Outline.applyMarks("見出し\n", lineStarts: []) == nil ? 1 : 0, 1)

// ---- 閲覧モードのMarkdownプレビュー（β）----
// Android版のMarkdownPreviewTest.ktと同じ観点の移植

func mdMarks(_ text: String) -> [MarkdownPreview.Mark] { MarkdownPreview.marks(Array(text)) }
func mdTexts(_ src: String, _ kind: MarkdownPreview.Kind) -> [String] {
    let chars = Array(src)
    return mdMarks(src).filter { $0.kind == kind }.map { String(chars[$0.start..<$0.end]) }
}
func mdHidden(_ src: String) -> [String] { mdTexts(src, .hidden) }
func mdLevels(_ src: String, _ kind: MarkdownPreview.Kind) -> [Int] {
    mdMarks(src).filter { $0.kind == kind }.map { $0.level }
}
func mdForeign(_ src: String) -> Bool { MarkdownPreview.looksLikeForeignMarkdown(Array(src), mdMarks(src)) }

// -- 見出し（印の側と違い6段まで受け入れる）
checkArr("MD_大見出しを拾う", mdTexts("# はじめに", .heading), ["はじめに"])
checkArrI("MD_三段以上の見出しも拾う", mdLevels("### 小さな見出し", .heading), [3])
checkArrI("MD_六段まで拾う", mdLevels("###### 最小", .heading), [6])
checkArr("MD_七段は見出しにしない", mdTexts("####### 行き過ぎ", .heading), [])
checkArr("MD_井桁のあとに空白がなければ見出しにしない", mdTexts("#見出しではない", .heading), [])
checkArr("MD_全角の井桁は見出しにしない", mdTexts("＃ 本文です", .heading), [])
checkArr("MD_見出しの記号は画面から消える", mdHidden("## 小見出し"), ["## "])

// -- 強調
checkArr("MD_太字を拾う", mdTexts("これは**強調**です", .bold), ["強調"])
checkArr("MD_斜体を拾う", mdTexts("これは*斜め*です", .italic), ["斜め"])
checkArr("MD_太字斜体を拾う", mdTexts("***両方***", .boldItalic), ["両方"])
checkArr("MD_打ち消しを拾う", mdTexts("~~消し~~", .strike), ["消し"])
checkArr("MD_強調の記号は画面から消える", mdHidden("**強調**"), ["**", "**"])
checkArr("MD_閉じない星印は記法として扱わない", mdTexts("5*3の答え", .italic), [])
checkArr("MD_閉じない星印は何も消さない", mdHidden("5*3の答え"), [])
checkArr("MD_中身が空の強調は記法として扱わない", mdTexts("****", .bold), [])
checkArr("MD_英単語の途中の下線は強調にしない", mdTexts("save_folder_name を見る", .italic), [])
checkArr("MD_単語の外の下線は強調にする", mdTexts("これは_強調_です", .italic), ["強調"])

// -- コード
checkArr("MD_行中のコードを拾う", mdTexts("`val x = 1` と書く", .code), ["val x = 1"])
checkArr("MD_囲みの中の行をコードとして拾う",
         mdTexts("```kotlin\nval x = 1\nprintln(x)\n```", .codeBlock), ["val x = 1", "println(x)"])
checkB("MD_囲みの行そのものは画面から消える",
       Set(mdHidden("```\nコード\n```")).isSuperset(of: ["```", "```"]), true)
checkArr("MD_囲みの中の星印は強調にしない", mdTexts("```\n**これは文字**\n```", .bold), [])
checkArr("MD_囲みの中の井桁は見出しにしない", mdTexts("```\n# 文字\n```", .heading), [])

// -- 箇条書き・引用
checkArr("MD_箇条書きを拾う", mdTexts("- 朝に出た", .bullet), ["- 朝に出た"])
checkArr("MD_箇条書きの記号は画面から消える", mdHidden("- 朝に出た"), ["- "])
checkArr("MD_記号のあとに空白がなければ箇条書きにしない", mdTexts("-朝に出た", .bullet), [])
checkArr("MD_番号つき箇条書きは番号を消さない", mdHidden("1. 朝に出た"), [])
checkArr("MD_番号つき箇条書きを拾う", mdTexts("1. 朝に出た", .ordered), ["1. 朝に出た"])
checkArrI("MD_引用を拾う", mdLevels("> 引用文", .quote), [1])
checkArrI("MD_入れ子の引用の深さを数える", mdLevels(">> 深い引用", .quote), [2])
checkArr("MD_引用の中の見出しを拾う", mdTexts("> # 題", .heading), ["題"])

// -- 水平線・表・リンク
checkArr("MD_水平線を拾う", mdTexts("---", .rule), ["---"])
checkArr("MD_短い連続は水平線にしない", mdTexts("--", .rule), [])
checkArr("MD_全角ダッシュは水平線にしない", mdTexts("――――", .rule), [])
checkI("MD_表の行には何もしない", mdMarks("| 駅 | 時刻 |").count, 0)
checkArr("MD_表の区切り行も消さない", mdHidden("|---|---|"), [])
checkArr("MD_表の中の強調は効く", mdTexts("| **三芳** | 14:00 |", .bold), ["三芳"])
checkArr("MD_リンクは文字だけを残す", mdTexts("[ここ](https://example.com)", .link), ["ここ"])

// -- 画像（絵は出せないので説明文だけ残す）
checkArr("MD_画像は記法をすべて消す",
         mdHidden("![写真](https://example.com/a.png)"), ["![", "](https://example.com/a.png)"])
checkArr("MD_画像はリンクとして扱わない", mdTexts("![写真](https://example.com/a.png)", .link), [])
checkI("MD_閉じない画像記法は文字のまま", mdMarks("びっくり! すごい").count, 0)
checkArr("MD_リンクのURLは画面から消える",
         mdHidden("[ここ](https://example.com)"), ["[", "](https://example.com)"])

// -- 原稿を壊さないこと（普通の日本語の文章に何も起きない）
checkI("MD_普通の日本語の段落には何も起きない", mdMarks("　姫新線は兵庫県の路線です。").count, 0)
checkI("MD_会話文には何も起きない", mdMarks("「最初の1年は苦しかったです」").count, 0)
checkI("MD_中黒の箇条書きには何も起きない", mdMarks("・新橋に着いた\n・横浜に着いた").count, 0)
checkI("MD_空の本文でも落ちない", mdMarks("").count, 0)
checkI("MD_改行だけでも落ちない", mdMarks("\n\n\n").count, 0)

// -- 「よそのMarkdownか」の判定（字数を隠すかどうかを決める）
checkB("MD_普通の原稿はよそのMarkdownではない",
       mdForeign("　姫新線は兵庫県の路線です。\n\n　次の日も乗った。"), false)
checkB("MD_見出しの印だけならよそのMarkdownではない",
       mdForeign("# 第一章\n\n　姫新線に乗った。\n\n## 出発\n\n　朝だった。"), false)
checkB("MD_三段の見出しがあればよそのMarkdown", mdForeign("### 小見出し"), true)
checkB("MD_強調があればよそのMarkdown", mdForeign("これは**強調**です"), true)
checkB("MD_箇条書きがあればよそのMarkdown", mdForeign("- 朝に出た"), true)
checkB("MD_引用があればよそのMarkdown", mdForeign("> 引用文"), true)
checkB("MD_表があればよそのMarkdown", mdForeign("| 駅 | 時刻 |"), true)
checkB("MD_印だけの見出しと表でもよそのMarkdown", mdForeign("## 行程\n\n| 駅 | 時刻 |"), true)
checkB("MD_縦棒が1本だけなら表とみなさない", mdForeign("これは a | b という書き方です。"), false)
checkB("MD_コードの囲みがあればよそのMarkdown", mdForeign("```\nval x = 1\n```"), true)
checkB("MD_リンクがあればよそのMarkdown", mdForeign("[ここ](https://example.com)"), true)
checkB("MD_閉じない星印ではよそのMarkdownにしない", mdForeign("5*3の答えを書く。"), false)
checkB("MD_中黒の箇条書きではよそのMarkdownにしない", mdForeign("・新橋に着いた\n・横浜に着いた"), false)

// -- 見出しの印との独立（ここが崩れると目次・並べ替えが壊れる）
checkI("MD_三段の見出しは印としては本文のまま", CharWidth.headingMarkLength(Array("### 小さな見出し"), 0), 0)
checkI("MD_印の側は今までどおり二段まで_1", CharWidth.headingMarkLength(Array("# 大見出し"), 0), 2)
checkI("MD_印の側は今までどおり二段まで_2", CharWidth.headingMarkLength(Array("## 小見出し"), 0), 3)

// ============================================================
// 変換コマンドが対象にする範囲（2.32：整形は未選択ならカーソル行だけ）
// ============================================================

/// 対象範囲を「実際に切り出される文字列」に直して見比べる
func scoped(_ text: String, _ loc: Int, _ len: Int,
            _ scope: TextTransform.NoSelectionScope) -> String {
    let ns = text as NSString
    let r = TextTransform.targetRange(in: ns,
                                      selection: NSRange(location: loc, length: len),
                                      noSelectionScope: scope)
    return ns.substring(with: r)
}

let 三行 = "一行目です\n二行目です\n三行目です"

// -- 未選択のとき
check("範囲_未選択の整形はカーソルのある行だけ", scoped(三行, 8, 0, .currentLine), "二行目です")
check("範囲_未選択の整形は行頭でもその行", scoped(三行, 6, 0, .currentLine), "二行目です")
check("範囲_未選択の整形は行末でもその行", scoped(三行, 11, 0, .currentLine), "二行目です")
check("範囲_未選択の整形は改行の直後なら次の行", scoped(三行, 12, 0, .currentLine), "三行目です")
check("範囲_未選択の整形は最終行では改行なし", scoped(三行, 14, 0, .currentLine), "三行目です")
check("範囲_未選択の非整形は文書全体", scoped(三行, 8, 0, .wholeDocument), 三行)
check("範囲_末尾の空行では対象なし", scoped("一行目です\n", 6, 0, .currentLine), "")
check("範囲_空の文書では対象なし", scoped("", 0, 0, .currentLine), "")

// -- 選択があるとき（どちらのscopeでも同じ＝含まれる論理行すべて）
check("範囲_行の途中からの選択は行頭まで広がる", scoped(三行, 8, 2, .currentLine), "二行目です")
check("範囲_行をまたぐ選択はその論理行すべて", scoped(三行, 3, 8, .currentLine), "一行目です\n二行目です")
check("範囲_選択があれば非整形も同じ範囲", scoped(三行, 3, 8, .wholeDocument), "一行目です\n二行目です")
check("範囲_行頭から改行までの選択はそのまま", scoped(三行, 6, 6, .currentLine), "二行目です\n")
check("範囲_最終行の途中までの選択は行末まで広がる", scoped(三行, 13, 2, .currentLine), "三行目です")

// -- 整形と組み合わせたときに、他の行へ手が及ばないこと
let 長い行 = "あああああ\nいいいいいいいいいい\nううううう"
check("範囲_整形はカーソル行だけを折り返す",
      { let ns = 長い行 as NSString
        let r = TextTransform.targetRange(in: ns,
                                          selection: NSRange(location: 8, length: 0),
                                          noSelectionScope: .currentLine)
        return ns.replacingCharacters(in: r,
                                      with: TextTransform.wrap(ns.substring(with: r), limit: 5)) }(),
      "あああああ\nいいいいい\nいいいいい\nううううう")

// ============================================================
// 非整形が対象にする段落（2.33：未選択ならカーソルのある段落だけ）
// ============================================================

func scopedP(_ text: String, _ loc: Int, _ len: Int, _ recognize: Bool = true) -> String {
    let ns = text as NSString
    let r = TextTransform.targetRange(in: ns,
                                      selection: NSRange(location: loc, length: len),
                                      noSelectionScope: .currentParagraph,
                                      recognizeParagraphs: recognize)
    return ns.substring(with: r)
}

// 一字下げで分かれた2段落。細切れの改行は切れ目にならない
let 二段落 = "　春はあけぼの。\nやうやう白くなりゆく。\n　夏は夜。\n月のころはさらなり。"
check("段落_ふつうの改行では切れない", scopedP(二段落, 12, 0), "　春はあけぼの。\nやうやう白くなりゆく。")
check("段落_次の一字下げから先は別の段落", scopedP(二段落, 24, 0), "　夏は夜。\n月のころはさらなり。")
check("段落_段落の先頭の行でも同じ範囲", scopedP(二段落, 0, 0), "　春はあけぼの。\nやうやう白くなりゆく。")

// 空行で分かれた2段落（一字下げなし）
let 空行区切り = "春はあけぼの。\nやうやう白く。\n\n夏は夜。\n月のころ。"
check("段落_空行で切れる", scopedP(空行区切り, 3, 0), "春はあけぼの。\nやうやう白く。")
check("段落_空行の次は別の段落", scopedP(空行区切り, 17, 0), "夏は夜。\n月のころ。")
check("段落_空行の上では対象なし", scopedP(空行区切り, 16, 0), "")

// 段落の印いろいろ
check("段落_箇条書きの行はそこで切れる",
      scopedP("本文です。\n続きです。\n・ひとつめ\n・ふたつめ", 3, 0), "本文です。\n続きです。")
check("段落_かぎ括弧の会話文はそこで切れる",
      scopedP("地の文です。\n「こんにちは」\n「さようなら」", 20, 0), "「さようなら」")
check("段落_見出しの前後は切れる",
      scopedP("# 見出し\n本文です。\n続きです。", 8, 0), "本文です。\n続きです。")
check("段落_見出しの行そのものは1行だけ", scopedP("# 見出し\n本文です。", 2, 0), "# 見出し")

// 設定「非整形で段落を区別しない」を入れると、記号では切れず空行だけで切れる
check("段落_区別しない設定では一字下げで切れない",
      scopedP(二段落, 12, 0, false), 二段落)
check("段落_区別しない設定でも空行では切れる",
      scopedP(空行区切り, 3, 0, false), "春はあけぼの。\nやうやう白く。")

// 選択があれば段落ではなく選んだ論理行すべて（scopeによらず同じ）
check("段落_選択があれば選んだ行だけ", scopedP(二段落, 0, 3), "　春はあけぼの。")

// 非整形と組み合わせて、隣の段落に手が及ばないこと
check("段落_非整形はカーソルの段落だけをつなぐ",
      { let ns = 二段落 as NSString
        let r = TextTransform.targetRange(in: ns,
                                          selection: NSRange(location: 12, length: 0),
                                          noSelectionScope: .currentParagraph)
        return ns.replacingCharacters(in: r,
                                      with: TextTransform.removeNewlines(ns.substring(with: r))) }(),
      "　春はあけぼの。やうやう白くなりゆく。\n　夏は夜。\n月のころはさらなり。")

// -- カーソルの位置合わせ
func caretAfter(_ text: String, _ offset: Int, _ transform: (String) -> String) -> Int {
    TextTransform.mappedCaret(from: text as NSString,
                              to: transform(text) as NSString,
                              offset: offset)
}
checkI("カーソル_整形で足した改行のぶん後ろへ",
       caretAfter("あいうえおかきくけこ", 7) { TextTransform.wrap($0, limit: 5) }, 8)
checkI("カーソル_非整形で取った改行のぶん手前へ",
       caretAfter("あいう\nかきく", 4) { TextTransform.removeNewlines($0) }, 3)
checkI("カーソル_変わらない位置はそのまま",
       caretAfter("あいう\nかきく", 2) { TextTransform.removeNewlines($0) }, 2)
checkI("カーソル_先頭は動かない",
       caretAfter("あいうえおかきくけこ", 0) { TextTransform.wrap($0, limit: 5) }, 0)
checkI("カーソル_末尾は変換後の末尾へ",
       caretAfter("あいうえおかきくけこ", 10) { TextTransform.wrap($0, limit: 5) }, 11)

if failures == 0 {
    print("\nすべてのテストに合格")
} else {
    print("\n\(failures) 件失敗")
    exit(1)
}
