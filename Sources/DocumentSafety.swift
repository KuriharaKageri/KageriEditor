import Foundation
import CryptoKit

// ============================================================
// 保存の安全機構まわりの純粋なI/Oユーティリティ（UIに依存しない）
// Android版（KageriEditor-Android）と同一のファイル形式・スキーマを使う
// ============================================================

enum DocumentSafety {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// ============================================================
// リネーム記録: 端末をまたいで名前変更を伝えるための小さなジャーナル
// 保存フォルダに .kageri_renames.json として置く（Android版と同一スキーマ）
// ============================================================
enum RenameJournal {
    private static let fileNamePrimary = ".kageri_renames.json"
    private static let fileNameFallback = "kageri_renames.json"
    private static let maxEntries = 50

    private static func journalURL(in folder: URL) -> URL? {
        let fm = FileManager.default
        let primary = folder.appendingPathComponent(fileNamePrimary)
        if fm.fileExists(atPath: primary.path) { return primary }
        let fallback = folder.appendingPathComponent(fileNameFallback)
        if fm.fileExists(atPath: fallback.path) { return fallback }
        return nil
    }

    private struct Entry: Codable {
        let from: String
        let to: String
        let at: Int64
    }

    /// リネームを記録する（直近50件のみ保持）
    static func append(from: String, to: String, in folder: URL) {
        DispatchQueue.global(qos: .utility).async {
            let url = journalURL(in: folder) ?? folder.appendingPathComponent(fileNamePrimary)
            var entries: [Entry] = []
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
                entries = decoded
            }
            entries.append(Entry(from: from, to: to, at: Int64(Date().timeIntervalSince1970 * 1000)))
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
            guard let out = try? JSONEncoder().encode(entries) else { return }
            try? out.write(to: url, options: .atomic)
        }
    }

    /// oldName の現在の名前を記録から辿って返す（変更がなければ nil）
    static func resolve(name oldName: String, in folder: URL) -> String? {
        guard let url = journalURL(in: folder),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return nil
        }
        var name = oldName
        var changed = false
        for entry in entries where entry.from == name {
            name = entry.to
            changed = true
        }
        return (changed && name != oldName) ? name : nil
    }
}

// ============================================================
// 履歴（最近開いたファイル）: UserDefaults に JSON 配列で保持
// Android版の history（直近20件）と同型
// ============================================================
enum RecentHistory {
    private static let key = "history"
    private static let maxEntries = 20

    private struct Entry: Codable {
        let name: String
        let path: String
        var selStart: Int = 0
        var selEnd: Int = 0
    }

    private static func loadEntries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }

    private static func saveEntries(_ list: [Entry]) {
        guard let data = try? JSONEncoder().encode(Array(list.prefix(maxEntries))) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> [(name: String, url: URL)] {
        loadEntries().map { ($0.name, URL(fileURLWithPath: $0.path)) }
    }

    static func add(name: String, url: URL) {
        // 同じURLの古いエントリがあれば、記憶していたカーソル位置は引き継ぐ
        let existing = loadEntries()
        let prevPos = existing.first { $0.path == url.path }
        var list = existing.filter { $0.path != url.path }
        list.insert(Entry(name: name, path: url.path,
                          selStart: prevPos?.selStart ?? 0, selEnd: prevPos?.selEnd ?? 0), at: 0)
        saveEntries(list)
    }

    static func remove(url: URL) {
        saveEntries(loadEntries().filter { $0.path != url.path })
    }

    /// 前回終了時のカーソル位置を記録する（履歴に無いURL＝未命名の文書などは対象外）
    static func updatePosition(url: URL, selStart: Int, selEnd: Int) {
        var list = loadEntries()
        guard let idx = list.firstIndex(where: { $0.path == url.path }) else { return }
        if list[idx].selStart == selStart, list[idx].selEnd == selEnd { return }
        list[idx].selStart = selStart
        list[idx].selEnd = selEnd
        saveEntries(list)
    }

    /// 前回終了時のカーソル位置を取得する（記録が無ければ0,0）
    static func position(for url: URL) -> (selStart: Int, selEnd: Int) {
        guard let e = loadEntries().first(where: { $0.path == url.path }) else { return (0, 0) }
        return (e.selStart, e.selEnd)
    }
}
