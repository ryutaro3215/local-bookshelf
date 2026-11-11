import Foundation

/// 表紙画像（原寸・サムネイル）をファイルとして保存・読込・削除する（requirements N2）。
/// 保存先は既定で Application Support/Covers。テストでは一時フォルダを渡す。
struct ImageStore: Sendable {
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

    /// 原寸とサムネイルを保存する（同じ ID があれば上書き）
    func save(original: Data, thumbnail: Data, for id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try original.write(to: originalURL(for: id), options: .atomic)
        try thumbnail.write(to: thumbnailURL(for: id), options: .atomic)
    }

    func loadOriginal(for id: UUID) -> Data? {
        try? Data(contentsOf: originalURL(for: id))
    }

    func loadThumbnail(for id: UUID) -> Data? {
        try? Data(contentsOf: thumbnailURL(for: id))
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
