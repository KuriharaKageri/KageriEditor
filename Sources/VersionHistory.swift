import Foundation
import CryptoKit

/// 版の履歴の、決まりごとだけを置く（保存・読み出しは HistoryStore）。
///
/// - 版は**丸ごと**残す（差分にしない）。1つ壊れても他の版に響かないため。
///   日本語の原稿は圧縮で約3分の1になるので、丸ごとでも量は小さい（実測 3.1分の1）
/// - 時間がたつほど**間引く**。Mac の Time Machine と同じ考え方
/// - 1つの版は1つのファイル。名前に「いつ・なぜ・何字・中身の目印」を入れておくので、
///   **一覧を出すのに中身を開かなくてよい**。まとめの目録ファイルは作らない（壊れたら全部を失うため）
///
/// Android版の `VersionHistory.kt` と同じ決まり。画面から独立した純粋関数だけ（Tests/test.swift で守っている）。
enum VersionHistory {

    /// 版を残したきっかけ。名前に入れる短い符号と、一覧に出す言葉
    enum Reason: String, CaseIterable {
        case save, auto, wrap, unwrap, blank, assist, strip, restore

        var label: String {
            switch self {
            case .save: return "保存"
            case .auto: return "自動保存"
            case .wrap: return "整形の前"
            case .unwrap: return "非整形の前"
            case .blank: return "空行除去の前"
            case .assist: return "原稿支援の前"
            case .strip: return "見出しの印を外す前"
            case .restore: return "版を戻す前"
            }
        }
    }

    /// 残してある1つの版
    struct Entry: Equatable {
        /// 残した時刻（エポックミリ秒）
        let time: Int64
        let reason: Reason
        /// 全角換算の字数（ステータスバーと同じ数え方。四捨五入）
        let chars: Int
        /// 中身の目印（同じ中身を続けて残さないために使う）
        let hash: String
        /// 保存先でのファイル名
        let fileName: String

        var date: Date { Date(timeIntervalSince1970: Double(time) / 1000) }
    }

    static let fileExtension = ".deflate"

    /// いつでも残しておく、新しい版の数（古くても消さない）
    static let alwaysKeep = 10

    private static let hour: Int64 = 60 * 60 * 1000
    private static let day: Int64 = 24 * hour

    private static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 中身の目印。SHA-256 の先頭8文字
    static func hashOf(_ text: String) -> String { String(sha256Hex(text).prefix(8)) }

    /// 文書ごとの置き場所の名前。**文書の場所（パス）から作る**。
    /// 名前をそのまま使わないのは、同じ名前のファイルが別の場所にもありうるため。
    ///
    /// **合成形（NFC）にそろえてからハッシュを取る。** MacのファイルURLは日本語のパスを
    /// 分解形に直す（「デ」→「テ」＋濁点）。Swiftの文字列比較では同じとみなされるが、
    /// バイト列は違うので、そろえないと濁点を含む名前の履歴が2つに割れる（実測で確認）
    static func keyOf(_ identity: String) -> String {
        String(sha256Hex(identity.precomposedStringWithCanonicalMapping).prefix(16))
    }

    /// 版のファイル名。`<時刻>_<きっかけ>_<字数>_<目印>.deflate`
    static func fileName(time: Int64, reason: Reason, chars: Int, hash: String) -> String {
        "\(time)_\(reason.rawValue)_\(chars)_\(hash)\(fileExtension)"
    }

    /// ファイル名から版を読み取る。形が違えば nil（関係ないファイルは無視する）
    static func parse(_ fileName: String) -> Entry? {
        guard fileName.hasSuffix(fileExtension) else { return nil }
        let parts = fileName.dropLast(fileExtension.count).split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 4,
              let time = Int64(parts[0]),
              let reason = Reason(rawValue: String(parts[1])),
              let chars = Int(parts[2]),
              parts[3].count == 8 else { return nil }
        return Entry(time: time, reason: reason, chars: chars, hash: String(parts[3]), fileName: fileName)
    }

    /// 版を縮める。**生の DEFLATE**（Android版と同じ形）
    static func compress(_ text: String) -> Data? {
        try? (Data(text.utf8) as NSData).compressed(using: .zlib) as Data
    }

    /// 縮めた版を戻す。壊れていれば nil
    static func decompress(_ data: Data) -> String? {
        if data.isEmpty { return nil }
        guard let raw = try? (data as NSData).decompressed(using: .zlib) as Data else { return nil }
        return String(data: raw, encoding: .utf8)
    }

    /// 元のファイルが消えた履歴を、もう消してよいか。
    /// **最後の版から1年たち、翌年の同じ日を過ぎたら**消す（2026-09-30 ユーザーと決めた形）。
    /// 例：最後の版が 2026-09-30 なら、2027-10-01 になった時点で消してよい。
    /// 2月29日の版は、翌年の2月28日を過ぎた3月1日から
    ///
    /// ファイルが本当に消えたかどうかは、ここでは見ない（呼ぶ側で確かめる）
    static func orphanExpired(lastTime: Int64, now: Int64, calendar: Calendar) -> Bool {
        let last = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(lastTime) / 1000))
        // 1年を足すと、2月29日は翌年の2月28日になる
        guard let sameDayNextYear = calendar.date(byAdding: .year, value: 1, to: last),
              let cutoff = calendar.date(byAdding: .day, value: 1, to: sameDayNextYear) else { return false }
        return Date(timeIntervalSince1970: Double(now) / 1000) >= cutoff
    }

    /// 間引いたあとに残す版の時刻。
    ///
    /// - 新しい `alwaysKeep` 個は、古くても残す
    /// - 24時間以内は全部残す
    /// - 7日以内は1時間に1つ（いちばん新しいもの）
    /// - 90日以内は1日に1つ
    /// - それより前は1週に1つ
    ///
    /// 「1時間」「1日」「1週」の区切りは、その端末の暦で数える（`calendar`）
    static func toKeep(_ times: [Int64], now: Int64, calendar: Calendar) -> Set<Int64> {
        let sorted = times.sorted(by: >)
        var keep = Set<Int64>()
        var seen = Set<String>()
        var iso = calendar
        iso.firstWeekday = 2          // ISO 8601 と同じく月曜はじまり
        iso.minimumDaysInFirstWeek = 4
        for (index, t) in sorted.enumerated() {
            let age = now - t
            let date = Date(timeIntervalSince1970: Double(t) / 1000)
            let bucket: String
            if age < day {
                bucket = "all:\(t)"
            } else if age < 7 * day {
                let c = calendar.dateComponents([.year, .month, .day, .hour], from: date)
                bucket = "h:\(c.year!)-\(c.month!)-\(c.day!):\(c.hour!)"
            } else if age < 90 * day {
                let c = calendar.dateComponents([.year, .month, .day], from: date)
                bucket = "d:\(c.year!)-\(c.month!)-\(c.day!)"
            } else {
                let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                bucket = "w:\(c.yearForWeekOfYear!):\(c.weekOfYear!)"
            }
            // 新しい順に見ているので、区切りごとに最初に出会ったものがいちばん新しい
            let first = seen.insert(bucket).inserted
            if index < alwaysKeep || first { keep.insert(t) }
        }
        return keep
    }
}
