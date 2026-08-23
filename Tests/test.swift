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

if failures == 0 {
    print("\nすべてのテストに合格")
} else {
    print("\n\(failures) 件失敗")
    exit(1)
}
