import AppKit
import Foundation

/// アプリ内ヘルプの1項目。groupは目次での見出しグループ
struct HelpSection {
    let group: String
    let title: String
    let body: String
}

/// アプリ内ヘルプ（使い方ガイド）の全文。
/// Android版のHelpContent.ktと同じ構成だが、パッド・高速スクロールなど
/// タッチ専用の節を落とし、Mac固有の内容（ネイティブのタブ、Servicesメニュー、
/// 印刷、初回起動時のセキュリティ警告）に差し替えている。
enum HelpContent {

    static let sections: [HelpSection] = [

        // ============================================================
        HelpSection(
            group: "はじめに",
            title: "3分でわかるチュートリアル",
            body: """
            起動すると、上部にボタンの並んだ横長のウインドウが開きます。これがすべてです。ダイアログはほとんど出てきません。

            1. まずは何か書いてみてください。左端の数字は行番号、その上の目盛りは全角換算の文字数（10・20・30…）です。ウインドウ下部には現在の行数・全角の文字数・原稿用紙の換算枚数が常に表示されます。

            2. ⌘S（保存）を押します。ファイル名は聞かれず、本文の1行目がそのままファイル名になって保存フォルダに保存されます。これがこのアプリいちばんの特徴です（詳しくは「保存のしくみ」）。

            3. もう一度開きたくなったら「履歴」（Ctrl+D）で、最近保存したファイルの一覧がすぐ出ます。「開く」（⌘O）を使えば保存フォルダの中身も選べます。

            4. 文章の中の言葉を探したいときは「検索」（⌘F）。何箇所もヒットする言葉は「一覧」（⌘⇧F）でまとめて見比べられます。

            5. 上部のボタンは自分の使い方に合わせて並べ替えたり隠したりできます（詳しくは「上部ボタン列の並び替え」）。

            6. 書き終えたら「閉じる」（⌘W）。確認ダイアログは出ず、必ず保存してから閉じます。保存せず閉じたいときだけ「保存せず閉じる」（Ctrl+Q）。この操作だけは元に戻せないため、確認ダイアログが出ます。

            7. ボタン列の右端の「⋮」には、設定や使い方など、いつも使うわけではない機能がまとまっています（詳しくは「右端の⋮メニュー」）。

            ひとまずこれだけ覚えておけば、あとは書くことに集中できます。
            """
        ),

        // ============================================================
        HelpSection(
            group: "ファイルとフォルダ",
            title: "保存のしくみ",
            body: """
            このアプリいちばんの特徴です。

            ・⌘S を押すと、保存ダイアログは出ずに、本文の中で最初に文字がある行（全角換算20文字まで）をそのままファイル名にして保存します。冒頭が空行の場合は読み飛ばして、最初に文字がある行を使います。
            ・文字列を選択した状態で本文を右クリックすると、「選択部分をファイル名に」でその場でファイル名を変更できます。
            ・ファイル名が付くのは最初の保存のときだけです。以後は ⌘S でも自動保存でも同じ名前のまま上書き保存され、勝手にリネームされることはありません。
            ・名前や場所を自分で決めたいときは「別名保存」（⌘⇧S）。すでに保存済みのファイルの名前だけを変えたいときは「ファイル名変更…」（Ctrl+T）。
            ・自動保存は既定でオフです。設定で間隔（分）を指定すると有効になります。
            ・「閉じる」（⌘W）は必ず保存してから閉じます。「保存しますか？」という確認は出ません。保存せず破棄したいときだけ「保存せず閉じる」（Ctrl+Q）――このアプリで唯一、確認ダイアログが出る操作です。

            他の端末（Android版など）が同じファイルを外部で変更していた場合は、上書き保存の前に確認のダイアログが出ます。本文が大幅に減っている場合（誤操作の疑い）も、自動保存が一時的に止まって確認が出ます。手動の ⌘S はこの確認をスキップして常に実行されます。
            """
        ),

        HelpSection(
            group: "ファイルとフォルダ",
            title: "保存フォルダについて",
            body: """
            保存フォルダは設定（⌘,）の「保存フォルダを選択…」で指定します。指定しない限り、保存したファイルはすべて「書類」フォルダに直接たまっていきます。どこに保存したのか迷わないよう、専用のフォルダを最初に決めておくことをお勧めします。

            ▼ このMacだけで使う場合
            iCloud Drive でも Dropbox でもお好みのクラウド同期フォルダで構いません。他のMacとも併用するなら、そのフォルダが両方のMacで同期されていることを確認してください。

            ▼ Android版とも同期したい場合
            iCloud Drive はAndroid側から読み書きできないため使えません。Google Drive のフォルダを保存先に指定することをお勧めします（Dropboxも技術的には使えますが、Android版はGoogle Driveを保存フォルダに指定する運用を前提に作られています）。Macでは Google Drive デスクトップ版が作るローカル同期フォルダを、Android版では「開く」からGoogle Driveのフォルダをそのまま指定してください。どちらの端末で保存しても、もう一方の「履歴」または「開く」からすぐに続きが書けます。

            いずれの場合も、保存フォルダの中には自分のテキストファイル（.txt・.log・.md）だけを置いてください。
            """
        ),

        HelpSection(
            group: "ファイルとフォルダ",
            title: "タブとウインドウ",
            body: """
            開いているファイルは、macOS標準のウインドウタブとしてまとめられます。タブをクリックで切り替え、右端の「＋」で新規タブを追加します。

            設定の「ウインドウをタブでまとめる」をオフにすると、ファイルごとに別々のウインドウで開くようになります。オンのままなら、ファイルが1つのときもタブバーが表示されます。

            タブはmacOS標準のものなので、タブを画面外へドラッグして別ウインドウに切り離す、逆に別ウインドウをタブとして合流させる、といったMac標準の操作がそのまま使えます。「ウインドウ」メニューの「タブを結合」「タブバーを表示」なども同じように働きます。

            タブを閉じる操作は ⌘W（閉じる）です。必ず保存してから閉じるので、閉じるときに確認は出ません。
            """
        ),

        HelpSection(
            group: "ファイルとフォルダ",
            title: "メモ",
            body: """
            上部ボタンの「メモ」（Ctrl+M）を選ぶと、保存フォルダ内の「quickmemo.txt」という決まった名前のファイルを開きます。既に開いていればそのタブに切り替わるだけです。削除してしまっても、次に開いたときに空の状態で自動的に作り直されます。

            他のアプリで見つけた文章を書き留めておきたいときは、その文字列をコピーしてから ⌘⇧M を押してください。日時を添えて quickmemo.txt の末尾に追記されます。メモを開いていなくても、ファイルに直接追記されます。

            ▼ Servicesメニューについて
            他のアプリで文字列を選択したときの「サービス」メニューにも「メモに追記」という項目を用意していますが、このアプリはApp Store外の配布で署名・公証を受けていないため、アプリによってはこの項目が一覧に出てきません。出てこない場合は、上の ⌘⇧M（コピーしてから追記）を使ってください。結果はどちらも同じです。
            """
        ),

        HelpSection(
            group: "ファイルとフォルダ",
            title: "最初にしておくと良い設定",
            body: """
            メニューの KageriEditor > 設定…（⌘, または Ctrl+I）で次を指定できます。

            ・保存フォルダ（⌘S・自動保存の保存先）
            ・画面表示の文字サイズ（1ポイント単位。フォントパネルのサイズ一覧より細かく調整したいときに使います）
            ・整形の文字数（⌃E で使う字数。初期値40）
            ・非整形で段落を区別しない（「整形・非整形・空行除去・原稿支援」を参照）
            ・ウインドウをタブでまとめるか
            ・ダークモード（端末に従う／ライト／ダーク）
            ・印刷時の文字サイズ（0で画面と同じサイズ）
            ・自動保存の間隔（分。初期値0＝無効）
            ・日付／時刻を挿入したときの書式（それぞれ3種類）
            ・上部ボタン列のカスタマイズ（「メニューの編集…」）

            フォントの種類は フォーマット > フォントパネルを表示（⌘T）で選べ、次回以降も保持されます。文字サイズは設定の「画面表示の文字サイズ」でも1ポイント単位で調整でき、フォントパネルのサイズ欄と値を共有します。
            """
        ),

        // ============================================================
        HelpSection(
            group: "基本の使い方",
            title: "右端の⋮メニュー",
            body: """
            ウインドウ上部のボタン列、その右端にある「⋮」を押すとプルダウンメニューが開きます。毎回は使わない機能をここにまとめてあるので、ボタン列は書くための操作だけで済みます。

            ・別名保存　今の本文を別の名前・別の場所で保存します
            ・ファイル名変更…　開いているファイルの名前を変えます
            ・印刷…　印刷パネルを開きます
            ・保存せず閉じる　変更を保存せずに閉じます（元に戻せないため確認が出ます）
            ・閲覧モード　読むことに専念するモードに切り替えます
            ・設定…　設定パネルを開きます
            ・使い方　このガイドを開きます

            「閲覧モード」は、今オンになっていればチェックが付きます。

            これらはすべてMac標準のメニューバー（ファイル・編集・フォーマットなど）からも選べます。「⋮」は、メニューバーまで視線を上げずに手元で済ませたいときのための入口です。
            """
        ),

        HelpSection(
            group: "基本の使い方",
            title: "閲覧モード",
            body: """
            書いた文章をじっくり読み返すためのモードです。ウインドウ下部のいちばん右にある「編集」を押すと切り替わります（「⋮」＞閲覧モード、フォーマット > 閲覧モード、Ctrl+B でも同じです）。閲覧モード中はここが「閲覧」に変わるので、もう一度押すと元に戻ります。

            閲覧モードにすると、次のように変わります。
            ・文字を入力できなくなり、カーソルも表示されなくなります（文字を選んでコピーすることはできます）
            ・上部の文字数の目盛りが隠れ、そのぶん本文が広く表示されます
            ・上部のボタンは薄く表示されたまま残り、押しても働きません（隠してしまうとウインドウ下部の位置が動いてしまうためです）

            スクロールはこれまで通り使えます。アプリを開き直したときは必ず解除された状態から始まります。
            """
        ),

        HelpSection(
            group: "基本の使い方",
            title: "印刷",
            body: """
            「印刷…」（⌘P、または「⋮」＞印刷…）で標準的な印刷パネルが開きます。行番号のガターや、改行・全角スペースを示す「↩」「□」など画面上だけの表示は含まれず、本文だけがページ分割されて印刷されます。用紙サイズや向き、部数などはmacOS標準の印刷パネルで指定してください。

            PDFとして保存したい場合も、印刷パネル左下の「PDF」メニューから「PDFとして保存…」が使えます。

            印刷時の文字サイズは、画面表示のフォントサイズとは別に指定できます。設定の「印刷時の文字サイズ」を0のままにしておくと画面と同じサイズで印刷されます。画面よりも大きく（または小さく）印刷したい場合は、ここにポイント数を指定してください（フォントの種類は画面と同じものが使われ、サイズだけが変わります）。
            """
        ),

        // ============================================================
        HelpSection(
            group: "操作をカスタマイズ",
            title: "上部ボタン列の並び替え",
            body: """
            ウインドウ上部のボタンは、自分の使い方に合わせて並べ替えたり隠したりできます。ボタンが多くて画面に入りきらない場合は、この列を左右にスクロールできます。

            初期状態の並び順は次の通りです（｜はボタンの間の「スペース」）。
            　新規／メモ／開く／履歴｜全選択／カット／コピー／ペースト｜検索／一覧｜日付／時刻｜元に戻す／やり直す｜整形／非整形／空行除去／原稿支援｜保存／閉じる

            別名保存・ファイル名変更・印刷・保存せず閉じる・閲覧モード・設定・使い方は、この列ではなく右端の「⋮」にまとめられているため、並び替えの対象には出てきません。

            設定（⌘,）の「メニューの編集…」から：
            ・チェックを外すとそのボタンを非表示にできます
            ・右端の「≡」を上下にドラッグすると並べ替えられます
            ・「スペースを追加」で、ボタンの間に余白を挿入してグループごとに見やすく区切れます
            ・「既定に戻す」でいつでも初期状態に戻せます

            変更は「保存」を押すと、開いているすべてのウインドウに即座に反映されます。
            """
        ),

        // ============================================================
        HelpSection(
            group: "検索",
            title: "検索・検索結果一覧・置換",
            body: """
            ⌘F で検索バーが出ます。⌘G／⌘⇧G で次／前の一致箇所へ移動します。置換したいときは ⌘⌥F（検索と置換）で置換欄が使えます。選択中の文字列をそのまま検索語にしたいときは ⌘E です。

            文章の中に同じ言葉が何箇所もあって、どこにどう出てくるかをまとめて見比べたいときは「検索結果一覧」（上部ボタンの「一覧」、または ⌘⇧F）を使ってください。

            ・検索語に一致するすべての箇所を、表示行番号とヒット箇所の前後の文脈つきで一覧表示します。同じ段落の中に複数回出てくる場合も、それぞれ違う前後の文脈で見分けられます。
            ・検索語そのものは太字の赤字で強調表示されます。
            ・一覧の項目をクリックすると、本文中の該当箇所へジャンプして選択状態になります。
            ・一覧パネルを開いたまま、上部の検索欄に別の語を入力して絞り込み直すこともできます。
            ・すでに ⌘F や ⌘E で検索語を指定していた場合、その語を引き継いだ状態で開きます。
            ・置換は一覧パネル自体では行いません。ジャンプした後、⌘⌥F の検索と置換バーでそのまま置換してください。
            """
        ),

        // ============================================================
        HelpSection(
            group: "リファレンス",
            title: "整形・非整形・空行除去・原稿支援",
            body: """
            いずれも選択した範囲（未選択なら文書全体）が対象です。行の途中から選んでも・行の途中まで選んでも、その行全体を選んだものとして処理します。

            ▼ 非整形（⌃R）
            改行を取り除きます。行頭が全角スペース・括弧類（「『（など）・箇条書き記号（・●○◎■□◆◇）・丸付き数字（①など）の行は段落の先頭とみなし、その前の改行は残します。空行も残します。設定の「非整形で段落を区別しない」を入れると、記号による段落の判定をやめ、空行だけを残すようになります。

            ▼ 整形（⌃E）
            設定した全角換算の文字数で改行を入れます。半角文字は0.5文字として数えます。句読点（、。）・ピリオドやカンマ・閉じ括弧（」）】など）・小書き文字（っ・ゃなど）・長音符（ー）が行頭に来る場合は、自動的に前の行の末尾にぶら下げます。これらの文字が3つ以上連続する場合は、3文字目以降は行頭に来ることがあります。

            ▼ 空行除去（⌃L）
            改行だけの行（空行）を取り除きます。空行が2行以上続いている場所は、1回の実行につき1行ずつ詰まります。3行あけ→2行あけ→1行あけ→詰める、と繰り返し押して好みの間隔で止められます。

            ▼ 原稿支援（⌃K）
            書き上げたあとに体裁を整えるための機能です。押すとダイアログが開き、行いたい処理をチェックで選んで「実行」を押すと、1回でまとめて適用されます。前回の選択は覚えているので、同じ処理を繰り返すときは開いて実行を押すだけです。別の処理をしたいときは「すべてオフ」を押すと、一度にすべてのチェックが外れます。何も選ばずに実行した場合は何も起きません。

            ・除去する：半角スペース／全角スペース／タブ
            　全角スペースを除去する場合も、段落の字下げにあたる行頭の全角スペースは残します。これも消したいときは「行頭の字下げも除去する」にチェックを入れてください。
            　行頭のタブは字下げのつもりで入っていることが多いため、除去ではなく全角スペース1つに変換します（行の途中のタブは取り除きます）。

            ・文字種を揃える：数字を半角に／アルファベットをそのまま・全角に・半角に

            ・追加する：行頭の字下げ（一字下げ）／段落の間に空行
            　「行頭の字下げ」は各行の先頭に全角スペースを加えます。会話文のカッコ（「『（など）や箇条書き記号（・●○など）、丸付き数字で始まる行、空行、すでに字下げ済みの行には加えません。
            　「段落の間に空行」は、すべての改行の直後に1行あけます。noteなどに貼るとき、段落の間が空いていた方が読みやすい場合に使います。こちらは段落かどうかの見分けをしません（一字下げをしない書き方や会話文では見分けがつかないためです）。そのため、すでに空行がある場所はそのぶん行数が増えます。行のあけ方を細かく決めたいときは、この機能で一度あけてから「空行除去」を必要な回数押して詰めてください。

            処理は「除去 → 文字種を揃える → 追加」の順に走ります。そのため「行頭の字下げも除去する」と「行頭の字下げ」の両方にチェックを入れると、バラバラだった字下げを取り払ってから規則正しく付け直せます。
            """
        ),

        HelpSection(
            group: "リファレンス",
            title: "キーボードショートカット",
            body: """
            ⌘系はMac標準のショートカット、Ctrl系はAndroid版と共通の操作です。どちらを覚えても構いません。

            ▼ ファイル
            新規　⌘N ／ Ctrl+N
            開く…　⌘O ／ Ctrl+O
            履歴　Ctrl+D
            メモ　Ctrl+M
            保存　⌘S ／ Ctrl+S
            別名で保存…　⌘⇧S ／ Ctrl+G
            ファイル名変更…　Ctrl+T
            閉じる　⌘W ／ Ctrl+W
            保存せず閉じる　Ctrl+Q
            プリント…　⌘P

            ▼ 編集
            取り消す　⌘Z
            やり直す　⌘⇧Z ／ Ctrl+Y
            カット／コピー／ペースト／すべてを選択　⌘X ／ ⌘C ／ ⌘V ／ ⌘A
            非整形　Ctrl+R
            整形　Ctrl+E
            空行除去　Ctrl+L
            原稿支援　Ctrl+K
            日付を挿入　Ctrl+;
            時刻を挿入　Ctrl+Shift+;
            クリップボードをメモに追記　⌘⇧M

            ▼ 検索
            検索…　⌘F ／ Ctrl+F
            検索と置換…　⌘⌥F
            次を検索／前を検索　⌘G ／ ⌘⇧G
            選択部分を検索　⌘E
            検索結果一覧　⌘⇧F

            ▼ 表示・その他
            閲覧モードの切替　Ctrl+B
            設定…　⌘, ／ Ctrl+I
            ウインドウをしまう　⌘M
            キーボードショートカット一覧を表示　Ctrl+/
            KageriEditorを終了　⌘Q

            非整形・整形・空行除去・原稿支援・ファイル名変更・保存せず閉じるは、Shiftを押したままでも動きます（⌃⇧R など）。かな入力中に指がずれても効くようにするためです。
            """
        ),

        HelpSection(
            group: "リファレンス",
            title: "その他の機能",
            body: """
            ・行番号は画面での折り返しを含めた「表示行」で数えます。検索結果一覧の行番号もこれと同じ数え方です。
            ・ウインドウ下部に行数・全角の文字数・400字詰め原稿用紙の換算枚数を常時表示します（全角=1、半角=0.5。○●■□▲▼★☆※→↑↓×などの記号も全角と同じ1文字として数えます。選択中は選択部分の字数も表示）。
            ・ウインドウ下部の右側では、自動保存の間隔（オフ／1／3／5／10／30分）・文字コード・改行コードをその場で選び直せます。いちばん右の「編集」「閲覧」を押すと閲覧モードを切り替えられます。
            ・ステータスバーの行数は改行の数（物理行）で数えます。折り返しを含む表示行数の厳密な集計は大きな文書で処理が重くなるため、あえて行っていません。
            ・改行は「↩」、全角スペースは「□」とグレーで表示されます。フォーマット > 改行・全角スペースを表示 でオン／オフできます。
            ・文字コード（UTF-8／Shift-JIS）と改行コード（macOS／Windows）はウインドウ右下で切り替えられます。開くときは自動判別します。

            ▼ 原稿用紙の換算枚数の数え方
            出版社や公募で使われる「400字詰めで○枚」と同じ、20字×20行の行単位で数えます。段落の途中で改行すると、実際の原稿用紙と同じように行末の余白もマスとして消費します（たとえば5字で改行し次の段落が2字なら、字数は7字でも2行を使います）。空行も1行と数えます。半角文字は2文字で1マスです。

            枚数の端数は切り捨てるので、「1枚」と表示されていれば原稿用紙を1枚使い切っている状態です。20行目に1字でも入った時点で1枚になります（改行のない文章なら381字で1枚）。
            """
        ),

        HelpSection(
            group: "リファレンス",
            title: "その他",
            body: """
            ・本アプリは無保証です。大切な原稿はバックアップをお勧めします。
            ・アンインストールは「アプリケーション」フォルダの KageriEditor.app をゴミ箱に入れるだけです。
            """
        ),
    ]
}


// ============================================================
// 使い方ガイドのウインドウ
// ============================================================

/// 左に目次、右に本文という一画面構成。Android版は一覧→詳細のドリルダウンだが、
/// Macは画面が広く、目次を出したまま項目を行き来できる方が読みやすいので分けている。
final class HelpWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    /// 目次の1行。見出し（グループ名）か、本文を持つ項目のどちらか
    private enum Row {
        case group(String)
        case section(Int)
    }

    private let rows: [Row] = {
        var rows: [Row] = []
        var lastGroup: String? = nil
        for (index, section) in HelpContent.sections.enumerated() {
            if section.group != lastGroup {
                rows.append(.group(section.group))
                lastGroup = section.group
            }
            rows.append(.section(index))
        }
        return rows
    }()

    private let tableView = NSTableView()
    private let bodyTextView = NSTextView()

    convenience init() {
        // 「3分でわかるチュートリアル」が最後まで、目次も全項目がスクロールなしで
        // 収まる大きさ。画面が小さい環境ではその画面に収まるところまで縮める
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: min(980, visible.width - 40),
                                height: min(720, visible.height - 40)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "使い方ガイド"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 400)
        // 書きかけの本文の上にガイドを重ねて読むので、ドキュメントのタブには合流させない
        window.tabbingMode = .disallowed
        self.init(window: window)
        buildUI()
        selectSection(0)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // ---- 左：目次 ----
        let sidebarScroll = NSScrollView()
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.drawsBackground = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        // 項目名が長いものがあるので、行の高さは中身に合わせて伸ばす（切り詰めない）
        tableView.usesAutomaticRowHeights = true
        tableView.rowHeight = 24
        tableView.style = .sourceList
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("toc")))
        sidebarScroll.documentView = tableView

        // ---- 右：本文 ----
        let bodyScroll = NSScrollView()
        bodyScroll.translatesAutoresizingMaskIntoConstraints = false
        bodyScroll.hasVerticalScroller = true
        bodyScroll.borderType = .noBorder
        bodyTextView.isEditable = false
        bodyTextView.isSelectable = true
        bodyTextView.drawsBackground = false
        bodyTextView.textContainerInset = NSSize(width: 22, height: 20)
        bodyTextView.autoresizingMask = [.width]
        bodyTextView.isVerticallyResizable = true
        bodyTextView.textContainer?.widthTracksTextView = true
        bodyScroll.documentView = bodyTextView

        let split = NSSplitView()
        split.translatesAutoresizingMaskIntoConstraints = false
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(sidebarScroll)
        split.addArrangedSubview(bodyScroll)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)

        content.addSubview(split)
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: content.topAnchor),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebarScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            bodyScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 380),
        ])
        split.setPosition(240, ofDividerAt: 0)
    }

    /// 指定した節を目次でも選択し、本文を表示する
    private func selectSection(_ sectionIndex: Int) {
        guard let rowIndex = rows.firstIndex(where: {
            if case .section(let i) = $0 { return i == sectionIndex }
            return false
        }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(rowIndex)
        showBody(of: sectionIndex)
    }

    private func showBody(of sectionIndex: Int) {
        guard HelpContent.sections.indices.contains(sectionIndex) else { return }
        let section = HelpContent.sections[sectionIndex]
        bodyTextView.textStorage?.setAttributedString(Self.attributedBody(of: section))
        bodyTextView.scroll(NSPoint(x: 0, y: 0))
    }

    /// 見出し＋本文の整形。本文中の「▼」で始まる行は小見出しとして太字にする
    private static func attributedBody(of section: HelpSection) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.paragraphSpacing = 14
        result.append(NSAttributedString(string: section.title + "\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 17),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: titleStyle,
        ]))

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = 4
        bodyStyle.paragraphSpacing = 6
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let headFont = NSFont.boldSystemFont(ofSize: 13)

        let lines = section.body.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let text = line + (index == lines.count - 1 ? "" : "\n")
            result.append(NSAttributedString(string: text, attributes: [
                .font: line.hasPrefix("▼") ? headFont : bodyFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: bodyStyle,
            ]))
        }
        return result
    }

    // ---------- NSTableViewDataSource / Delegate ----------

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .group = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .group = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label: NSTextField
        switch rows[row] {
        case .group(let name):
            label = NSTextField(wrappingLabelWithString: name)
            label.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
        case .section(let index):
            label = NSTextField(wrappingLabelWithString: HelpContent.sections[index].title)
            label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }
        // wrappingLabelは既定で選択可能なので、目次の行としてはクリックを行に通す
        label.isSelectable = false
        label.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        let cell = NSTableCellView()
        cell.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard rows.indices.contains(row), case .section(let index) = rows[row] else { return }
        showBody(of: index)
    }
}
