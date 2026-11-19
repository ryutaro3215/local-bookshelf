import Foundation

/// 表紙画像（原寸・サムネイル）をファイルとして保存・読込・削除する（requirements N2）。
/// 保存先は既定で Application Support/Covers。テストでは一時フォルダを渡す。
nonisolated struct ImageStore: Sendable {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// Application Support/Covers を使う既定のストア
    static func standard() throws -> ImageStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return ImageStore(directory: base.appendingPathComponent("Covers", isDirectory: true))
    }

    func originalURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    func thumbnailURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString)_thumb.jpg")
    }

    /// 原寸とサムネイルを保存する（同じ ID があれば上書き）。
    /// 端末のロック中は読めない保護クラスで書く（requirements S5。アプリ全体の既定も Bookshelf.entitlements で同じにしている）
    func save(original: Data, thumbnail: Data, for id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try original.write(to: originalURL(for: id), options: [.atomic, .completeFileProtection])
        try thumbnail.write(to: thumbnailURL(for: id), options: [.atomic, .completeFileProtection])
    }

    func loadOriginal(for id: UUID) -> Data? {
        try? Data(contentsOf: originalURL(for: id))
    }

    func loadThumbnail(for id: UUID) -> Data? {
        try? Data(contentsOf: thumbnailURL(for: id))
    }

    /// 保存先にある表紙のうち、`keep` に無い ID のもの（どの本にも紐付かない画像）を消す。消した ID の数を返す。
    /// 表紙の入れ替えの途中でアプリが落ちたときの仮のファイルなどを片付ける（N-072②）。
    /// `before` より後に書いたファイルは消さない（片付けの間に登録・入れ替えで書いた表紙を消さないため）
    @discardableResult
    func removeFiles(except keep: Set<UUID>, modifiedBefore before: Date) throws -> Int {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        var removed = Set<UUID>()
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) where name.hasSuffix(".jpg") {
            let stem = name.dropLast(4)
            let idText = stem.hasSuffix("_thumb") ? String(stem.dropLast(6)) : String(stem)
            guard let id = UUID(uuidString: idText), !keep.contains(id) else { continue }
            let url = directory.appendingPathComponent(name)
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard let modified, modified < before else { continue }
            try FileManager.default.removeItem(at: url)
            removed.insert(id)
        }
        return removed.count
    }

    /// 原寸とサムネイルを消す。もともと無いファイルは無視する
    func delete(for id: UUID) throws {
        for url in [originalURL(for: id), thumbnailURL(for: id)] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
}
