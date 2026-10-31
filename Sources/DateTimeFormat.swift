import Foundation

// ============================================================
// 日付・時刻の文字列整形（Android版・Windows版と同じ4書式ずつ・時刻の前に入れる文字）
// ============================================================
enum DateTimeFormat {
    /// 設定の画面に並べる見本（2026年7月13日 13時05分の場合）
    static let dateFormatSamples = ["2026年07月13日", "2026-07-13", "20260713", "2026年07月13日（月）"]
    static let timeFormatSamples = ["13:05", "13時05分", "午後1時05分", "1305"]

    /// 時刻の前に入れるものの見本（番号は 0＝なし・1＝半角スペース・2＝_）。
    /// 日付のあとに時刻を続けるとき「20261029_0942」などにできる
    static let timePrefixSamples = ["なし", "半角スペース", "_（半角アンダーバー）"]

    static func currentDateString(formatIndex: Int) -> String {
        dateString(Date(), formatIndex: formatIndex)
    }

    static func currentTimeString(formatIndex: Int, prefixIndex: Int = 0) -> String {
        timeInsertion(Date(), formatIndex: formatIndex, prefixIndex: prefixIndex)
    }

    static func dateString(_ date: Date, formatIndex: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let y = c.year ?? 0, m = c.month ?? 0, d = c.day ?? 0
        switch formatIndex {
        case 1: return String(format: "%04d-%02d-%02d", y, m, d)
        case 2: return String(format: "%04d%02d%02d", y, m, d)
        case 3:
            let names = Array("日月火水木金土") // weekday は 1＝日曜
            let w = names[max(0, min(6, (c.weekday ?? 1) - 1))]
            return String(format: "%04d年%02d月%02d日（", y, m, d) + String(w) + "）"
        default: return String(format: "%04d年%02d月%02d日", y, m, d)
        }
    }

    static func timeString(_ date: Date, formatIndex: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h24 = c.hour ?? 0
        let minuteStr = String(format: "%02d", c.minute ?? 0)
        switch formatIndex {
        case 3:
            return String(format: "%02d", h24) + minuteStr
        case 1:
            return "\(h24)時\(minuteStr)分"
        case 2:
            // 午前0時は「午前12時」、正午は「午後12時」
            let ampm = h24 < 12 ? "午前" : "午後"
            let h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24)
            return "\(ampm)\(h12)時\(minuteStr)分"
        default:
            return String(format: "%02d:%02d", h24, c.minute ?? 0)
        }
    }

    static func timePrefix(_ index: Int) -> String {
        switch index {
        case 1: return " "
        case 2: return "_"
        default: return ""
        }
    }

    /// 時刻の挿入の文字（前に入れるものも含む）
    static func timeInsertion(_ date: Date, formatIndex: Int, prefixIndex: Int,
                              calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        timePrefix(prefixIndex) + timeString(date, formatIndex: formatIndex, calendar: calendar)
    }
}
