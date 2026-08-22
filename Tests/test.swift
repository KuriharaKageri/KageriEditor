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
