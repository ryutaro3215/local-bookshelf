#if DEBUG
    import Darwin
    import Foundation
    import SwiftData
    import SwiftUI
    import os

    /// 性能の計測用に、500冊の本を入れる（plan T12。N1・N2。デバッグビルドの `-UITestPersistentStore -UITestReset` のときだけ）。
    /// 起動引数 `-SeedPerf 500`。題名は DebugSeed の架空のもの。表紙は実際の登録と同じ CoverProcessor を通した JPEG で、
    /// 手元に実写のサンプル（design/sample-covers/raw。git 管理外）があればそれを順に使い、無ければ合成の表紙を使う。
    /// 実写は一時フォルダ（シミュレータの中）にだけ保存し、リポジトリには入れない
    enum PerfSeed {
        private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "PerfSeed")

        /// 実写のサンプルのフォルダ（このファイルの位置から辿る。シミュレータからはホストのパスを読める）
        static let samples = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "design/sample-covers/raw")

        /// 入れ方: 小説に 200 冊（モザイク・300 冊の上限の手前）、残りをほかの棚に均等に。1割は「買いたい」。
        /// 購入日は 2025-01-01 から1日ずつ（約2年分）
        @MainActor
        static func apply(count: Int, to store: LibraryStore) throws {
            let clock = ContinuousClock()
            let start = clock.now
            let covers = try makeCovers()
            let shelves = try store.shelves().filter { $0.kind == .genre }
            guard let fiction = shelves.first(where: { $0.name == "小説" }) else { return }
            let others = shelves.filter { $0.persistentModelID != fiction.persistentModelID }
            let calendar = Calendar(identifier: .gregorian)
            let first = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 12)) ?? .now
            for serial in 0..<count {
                let shelf = serial % 5 < 2 || others.isEmpty ? fiction : others[serial % others.count]
                let cover = covers[serial % covers.count]
                let id = UUID()
                try store.images.save(original: cover.image, thumbnail: cover.thumbnail, for: id)
                let day = calendar.date(byAdding: .day, value: serial * 700 / max(count, 1), to: first) ?? first
                try store.addBook(
                    title: DebugSeed.title(serial), shelf: shelf, ownership: serial % 10 == 9 ? .wanted : .owned,
                    now: day, id: id)
            }
            logger.notice(
                "500冊のシード: \(count) 冊・表紙 \(covers.count) 種類・\(String(describing: clock.now - start), privacy: .public)"
            )
        }

        /// 表紙（実写のサンプル、無ければ合成）を CoverProcessor で処理したもの
        private static func makeCovers() throws -> [ProcessedCover] {
            let processor = CoverProcessor()
            let files =
                (try? FileManager.default.contentsOfDirectory(at: samples, includingPropertiesForKeys: nil))?
                .filter { ["png", "jpg", "jpeg", "heic"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
            var covers: [ProcessedCover] = []
            for file in files {
                do {
                    covers.append(try processor.process(try Data(contentsOf: file)))
                } catch {
                    logger.error("サンプルを処理できない: \(file.lastPathComponent, privacy: .public)")
                }
            }
            if covers.isEmpty {
                for serial in 0..<12 {
                    let cover = DebugSeed.cover(title: DebugSeed.title(serial), serial: serial)
                    covers.append(try processor.process(cover.original))
                }
            }
            return covers
        }
    }

    /// 起動から棚の表示までの時間と、データの容量を測る（起動引数 `-PerfProbe` のときだけ。plan T12 の PerformanceTests が読む）。
    /// 閲覧画面の右下に見えない小さな要素（識別子 `perf.probe`）を置き、値を読み上げ用のラベルに入れる
    @MainActor
    @Observable
    final class PerfProbe {
        static let shared = PerfProbe()
        static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-PerfProbe") }

        /// プロセスの開始から、棚に本が出るまで（ミリ秒）
        private(set) var launchMilliseconds: Int?
        /// データの容量（バイト。データベースと表紙のフォルダ）
        private(set) var dataBytes: Int64?

        var label: String {
            "launch=\(launchMilliseconds.map(String.init) ?? "-");bytes=\(dataBytes.map(String.init) ?? "-")"
        }

        /// 棚に本が出たとき（最初の1回だけ）。次の描画のあとで時間を取る
        func shelfShown(dataFolder: URL?) {
            guard Self.isEnabled, launchMilliseconds == nil else { return }
            DispatchQueue.main.async {
                guard self.launchMilliseconds == nil, let started = Self.processStart() else { return }
                self.launchMilliseconds = Int(Date().timeIntervalSince(started) * 1000)
                if let dataFolder {
                    Task.detached {
                        let bytes = Self.size(of: dataFolder)
                        await MainActor.run { self.dataBytes = bytes }
                    }
                }
            }
        }

        /// プロセスの開始時刻（sysctl の kinfo_proc）
        private nonisolated static func processStart() -> Date? {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
            guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
            let time = info.kp_proc.p_un.__p_starttime
            return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000)
        }

        /// フォルダの中のファイルの大きさの合計
        nonisolated static func size(of folder: URL) -> Int64 {
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
            guard
                let items = FileManager.default.enumerator(
                    at: folder, includingPropertiesForKeys: keys, options: [], errorHandler: nil)
            else { return 0 }
            var total: Int64 = 0
            for case let url as URL in items {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                    continue
                }
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
            return total
        }
    }

    /// 閲覧画面に置く、計測値の見えない要素（`-PerfProbe` のときだけ）
    struct PerfProbeMarker: View {
        let probe = PerfProbe.shared

        var body: some View {
            Text(verbatim: probe.label)
                .font(.system(size: 1))
                .opacity(0.01)
                .frame(width: 2, height: 2)
                .accessibilityLabel(Text(verbatim: probe.label))
                .accessibilityIdentifier("perf.probe")
        }
    }
#endif
