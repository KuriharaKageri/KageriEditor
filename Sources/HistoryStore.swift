import Foundation

/// 版の履歴の置き場所。決まりごと（名前・間引き・縮め方）は VersionHistory にある。
///
/// - 置き場所は `~/Library/Application Support/KageriEditor/History/<文書ごとの名前>/`。
///   **端末ごとの履歴で、ほかの端末とは同期しない**（端末をまたぐ履歴は Dropbox・Google Drive
///   側にあるため。2026-09-30 ユーザーと決めた形）。保存フォルダの中には何も置かない
/// - 書き出しは1本の背景キューで順に行う（保存の手を止めないため。順番が入れ替わると
///   「前の版」が新しい版を追い越すので、1本にしている）
/// - 文書ごとの置き場所には `name.txt`（いまの名前と、束ねるための文字列）を置いておく。
///   将来、名前から迷子の履歴を探せるようにするため
///
/// Android版の HistoryStore.kt と同じ作り。
final class HistoryStore {

    static let shared = HistoryStore()

    private let root: URL
    private let queue = DispatchQueue(label: "local.kageri.history", qos: .utility)

    /// 置き場所を指定できるのは、確かめるための小さなプログラムから使うため。
    /// アプリは `shared`（Application Support の下）だけを使う
    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.root = base.appendingPathComponent("KageriEditor/History", isDirectory: true)
        }
    }

    /// 背景の書き出しが終わるまで待つ（確かめるための小さなプログラム用）
    func waitUntilIdle() { queue.sync {} }

    /// 束ねるための文字列。Macではファイルのパスがそのまま使える（保存で場所が変わらないため）
    /// 合成形にそろえる（VersionHistory.keyOf と同じ理由。name.txt に書く文字列もそろえておく）
    static func identity(of url: URL) -> String {
        url.standardizedFileURL.path.precomposedStringWithCanonicalMapping
    }

    private func dir(_ identity: String) -> URL {
        root.appendingPathComponent(VersionHistory.keyOf(identity), isDirectory: true)
    }

    /// その文書の版。新しい順
    func list(_ identity: String) -> [VersionHistory.Entry] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir(identity).path)) ?? []
        return names.compactMap(VersionHistory.parse).sorted { $0.time > $1.time }
    }

    /// 1つの版の本文。読めなければ nil
    func read(_ identity: String, _ entry: VersionHistory.Entry) -> String? {
        guard let data = try? Data(contentsOf: dir(identity).appendingPathComponent(entry.fileName)) else {
            return nil
        }
        return VersionHistory.decompress(data)
    }

    /// 版を残す（背景で）。**直前の版と同じ中身なら残さない**
    /// （3分ごとの自動保存で、何も書いていない時間の版が並ばないように）
    func snapshot(identity: String, name: String, text: String, reason: VersionHistory.Reason) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        queue.async { [self] in write(identity: identity, name: name, text: text, reason: reason, now: now) }
    }

    /// 背景で呼ぶ本体。終わりを待ちたいとき（版に戻す直前など）はこれを直接呼ぶ
    func write(identity: String, name: String, text: String, reason: VersionHistory.Reason, now: Int64) {
        let hash = VersionHistory.hashOf(text)
        let latest = list(identity).first
        if latest?.hash == hash { return }
        // **書いた順が必ず時刻の順になるようにする。** 同じミリ秒に2つ書くと時刻が並び、
        // 一覧の順番が崩れる（書き出しは1本のキューなので、書いた順＝頼まれた順）
        let now = max(now, (latest?.time ?? 0) + 1)
        let folder = dir(identity)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try "\(name)\n\(identity)".write(to: folder.appendingPathComponent("name.txt"),
                                               atomically: true, encoding: .utf8)
            guard let data = VersionHistory.compress(text) else { return }
            let chars = Int(CharWidth.measure(text).zenkaku.rounded())
            let fileName = VersionHistory.fileName(time: now, reason: reason, chars: chars, hash: hash)
            // 途中で落ちても半端な版が残らないよう、まとめて書いてから置く
            try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
            prune(identity, now: now)
        } catch {
            // 履歴は補助の仕組みなので、失敗しても保存や編集の邪魔はしない
        }
    }

    /// 間引く
    private func prune(_ identity: String, now: Int64) {
        let entries = list(identity)
        let keep = VersionHistory.toKeep(entries.map(\.time), now: now, calendar: .current)
        let folder = dir(identity)
        for e in entries where !keep.contains(e.time) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(e.fileName))
        }
    }

    /// 元のファイルが消えた履歴を片付ける（1日に1回、起動のときに呼ぶ）。
    ///
    /// **消えたと確かめられたときだけ消す。** ファイルの入っていたフォルダはあるのに、
    /// ファイルだけが無い場合に限る。フォルダごと見えないとき（外付けディスクを外している、
    /// フォルダを移したなど）は、見えないだけかもしれないので残す。
    /// 消すのは、最後の版から1年たち翌年の同じ日を過ぎたもの（VersionHistory.orphanExpired）
    func cleanupOrphans() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        queue.async { [self] in
            let fm = FileManager.default
            let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for dir in dirs {
                guard let meta = try? String(contentsOf: dir.appendingPathComponent("name.txt"), encoding: .utf8)
                else { continue }
                let lines = meta.split(separator: "\n", omittingEmptySubsequences: false)
                guard lines.count >= 2 else { continue }
                let path = String(lines[1])
                var isDir: ObjCBool = false
                let parent = (path as NSString).deletingLastPathComponent
                guard fm.fileExists(atPath: parent, isDirectory: &isDir), isDir.boolValue else { continue }
                if fm.fileExists(atPath: path) { continue }
                let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                let last = names.compactMap(VersionHistory.parse).map(\.time).max() ?? 0
                if last == 0 || VersionHistory.orphanExpired(lastTime: last, now: now, calendar: .current) {
                    try? fm.removeItem(at: dir)
                }
            }
        }
    }

    /// 文書の名前や場所が変わったとき、履歴も一緒に移す（アプリ内のファイル名変更）。
    /// 移し先にすでに履歴があれば、中身を足し合わせる
    func move(from oldIdentity: String, to newIdentity: String, name: String) {
        guard oldIdentity != newIdentity else { return }
        queue.async { [self] in
            let fm = FileManager.default
            let from = dir(oldIdentity)
            guard fm.fileExists(atPath: from.path) else { return }
            let to = dir(newIdentity)
            if fm.fileExists(atPath: to.path) {
                for n in (try? fm.contentsOfDirectory(atPath: from.path)) ?? [] where n != "name.txt" {
                    try? fm.moveItem(at: from.appendingPathComponent(n), to: to.appendingPathComponent(n))
                }
                try? fm.removeItem(at: from)
            } else {
                try? fm.moveItem(at: from, to: to)
            }
            try? "\(name)\n\(newIdentity)".write(to: to.appendingPathComponent("name.txt"),
                                                  atomically: true, encoding: .utf8)
        }
    }
}
