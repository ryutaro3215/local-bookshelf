import SwiftData
import SwiftUI
import UIKit

@main
struct BookshelfApp: App {
    @State private var environment: Result<AppEnvironment, Error>

    init() {
        BookshelfStyle.registerFonts()
        _environment = State(initialValue: Result { try AppEnvironment.make() })
    }

    var body: some Scene {
        WindowGroup {
            switch environment {
            case .success(let environment):
                // 初回はチュートリアル（F1-7。T14）、終えていれば閲覧画面
                AppRootView(environment: environment)
                    .modelContainer(environment.container)
                    .environment(environment.appearance)
                    .environment(environment.language)
                    // 起動したウインドウに、保存した外観を付ける
                    .onAppear { environment.appearance.apply() }
            case .failure(let error):
                Text("データを開けませんでした（\(error.localizedDescription)）")
                    .padding()
            }
        }
    }
}

/// アプリ全体で1つずつ持つもの（データ・画像の保存先・カメラ）。起動時に作り、初期ジャンルを用意する
@MainActor
final class AppEnvironment {
    let container: ModelContainer
    let store: LibraryStore
    let recent: RecentShelves
    let appearance: AppearanceSettings
    let language: LanguageSettings
    private let arguments: [String]

    init(container: ModelContainer, images: ImageStore, defaults: UserDefaults, arguments: [String]) throws {
        self.container = container
        self.store = LibraryStore(container: container, images: images)
        self.recent = RecentShelves(defaults: defaults)
        self.appearance = AppearanceSettings(defaults: defaults)
        self.language = LanguageSettings(defaults: defaults)
        #if DEBUG
            // UI テスト・スクリーンショット用: 起動引数 `-UITestAppearance dark` で外観を決める
            if let index = arguments.firstIndex(of: "-UITestAppearance"), index + 1 < arguments.count,
                let value = AppAppearance(rawValue: arguments[index + 1])
            {
                appearance.appearance = value
            }
        #endif
        self.arguments = arguments
        try store.seedIfNeeded()
    }

    /// 起動引数 `-UITestReset` のときは、毎回まっさらなデータ（メモリ上）・一時フォルダの画像・専用の設定で起動する（UIテスト用）
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) throws -> AppEnvironment {
        let schema = Schema([Book.self, Shelf.self])
        // UI テスト用の起動引数はデバッグビルドだけで受け付ける（リリース版では無視する。N-036・セキュリティ監査 low）
        #if DEBUG
            if arguments.contains("-UITestPersistentStore") {
                return try makePersistentUITest(schema: schema, arguments: arguments)
            }
            if arguments.contains("-UITestReset") {
                let suite = "com.ryutaro3215.bookshelf.uitest"
                UserDefaults().removePersistentDomain(forName: suite)
                let defaults = UserDefaults(suiteName: suite) ?? .standard
                let container = try ModelContainer(
                    for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
                removeOldUITestCovers()
                let images = ImageStore(
                    directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                        "\(uiTestCoversPrefix)\(UUID().uuidString)", isDirectory: true))
                let environment = try AppEnvironment(
                    container: container, images: images, defaults: defaults, arguments: arguments)
                if let index = arguments.firstIndex(of: "-SeedBooks"), index + 1 < arguments.count {
                    try DebugSeed.apply(arguments[index + 1], to: environment.store)
                }
                return environment
            }
        #endif
        let container = try ModelContainer(for: schema)
        return try AppEnvironment(
            container: container, images: try ImageStore.standard(), defaults: .standard, arguments: arguments)
    }

    #if DEBUG
        private static let uiTestCoversPrefix = "UITestCovers-"

        /// 前回までの `-UITestReset` の表紙の一時フォルダを消す（起動ごとに新しいフォルダを作るため、残り続けないように。N-064）
        private static func removeOldUITestCovers() {
            let temporary = FileManager.default.temporaryDirectory
            do {
                for name in try FileManager.default.contentsOfDirectory(atPath: temporary.path)
                where name.hasPrefix(uiTestCoversPrefix) {
                    try FileManager.default.removeItem(at: temporary.appendingPathComponent(name, isDirectory: true))
                }
            } catch {
                // 消せなくてもテストの動作には関係しない（一時フォルダが残るだけ）
                print("UITestCovers の一時フォルダを消せない: \(error)")
            }
        }

        /// 起動引数 `-UITestPersistentStore` のとき（UIテストの「アプリ再起動後も保持される」の確認用・デバッグビルドのみ）:
        /// 一時フォルダの決まった場所のファイルにデータと画像を保存し、次の起動でも同じものを開く。
        /// `-UITestReset` も付けると、その場所を消してまっさらにしてから `-SeedBooks` を入れる
        private static func makePersistentUITest(schema: Schema, arguments: [String]) throws -> AppEnvironment {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
                "UITestPersistentStore", isDirectory: true)
            let suite = "com.ryutaro3215.bookshelf.uitest.persistent"
            let reset = arguments.contains("-UITestReset")
            if reset {
                if FileManager.default.fileExists(atPath: folder.path) {
                    try FileManager.default.removeItem(at: folder)
                }
                UserDefaults().removePersistentDomain(forName: suite)
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: folder.appendingPathComponent("library.store")))
            let images = ImageStore(directory: folder.appendingPathComponent("Covers", isDirectory: true))
            let environment = try AppEnvironment(
                container: container, images: images, defaults: UserDefaults(suiteName: suite) ?? .standard,
                arguments: arguments)
            if reset, let index = arguments.firstIndex(of: "-SeedBooks"), index + 1 < arguments.count {
                try DebugSeed.apply(arguments[index + 1], to: environment.store)
            }
            // 性能の計測用の500冊（plan T12）
            if reset, let index = arguments.firstIndex(of: "-SeedPerf"), index + 1 < arguments.count,
                let count = Int(arguments[index + 1]), (1...2000).contains(count)
            {
                try PerfSeed.apply(count: count, to: environment.store)
            }
            return environment
        }
    #endif

    /// 撮影に使うカメラ。シミュレータと起動引数 `-FakeCamera <シナリオ>` のときは合成画像のカメラ（デバッグビルドのみ）
    func makeCamera() -> any CameraSource {
        #if DEBUG
            if let index = arguments.firstIndex(of: "-FakeCamera"), index + 1 < arguments.count {
                let text = arguments[index + 1]
                let denied = text.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == "denied" }
                return FakeCameraSource(
                    scenario: FakeCameraSource.parse(text), authorization: denied ? .denied : .authorized)
            }
            #if targetEnvironment(simulator)
                return FakeCameraSource()
            #else
                return CameraController()
            #endif
        #else
            return CameraController()
        #endif
    }
}

#if DEBUG
    /// UIテスト・スクリーンショット用に、架空の本（合成の表紙）を入れる（デバッグビルドの `-UITestReset` のときだけ）。
    /// 起動引数 `-SeedBooks "小説:3,エッセイ:0+2,哲学・思想:120"`（棚の名前:購入済みの冊数[+買いたいの冊数]。カンマ区切り）。
    /// 題名は語を組み合わせて作った架空のもので、実在の本・表紙は使わない
    enum DebugSeed {
        static func apply(_ spec: String, to store: LibraryStore) throws {
            let shelves = try store.shelves()
            var serial = 0
            for part in spec.split(separator: ",") {
                let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
                guard pieces.count == 2, let shelf = shelves.first(where: { $0.name == pieces[0] }) else { continue }
                // 「@YYYY-MM-DD」を付けると、購入済みの本の購入日をその日から1日ずつずらす（購入月別の確認用。T13）
                let dated = pieces[1].split(separator: "@", maxSplits: 1).map(String.init)
                let start = dated.count == 2 ? Self.date(dated[1]) : nil
                let counts = dated[0].split(separator: "+").map { Int($0) ?? 0 }
                let owned = counts.first ?? 0
                let wanted = counts.count > 1 ? counts[1] : 0
                for i in 0..<(owned + wanted) {
                    let title = Self.title(serial)
                    let id = UUID()
                    let cover = Self.cover(title: title, serial: serial)
                    try store.images.save(original: cover.original, thumbnail: cover.thumbnail, for: id)
                    try store.addBook(
                        title: title, shelf: shelf, ownership: i < owned ? .owned : .wanted,
                        // データ追加日は番号の順に少しずつずらす（約100秒前から 0.01 秒刻み。深夜0時すぎでも購入日が今日になるように）
                        now: start.flatMap { Calendar.current.date(byAdding: .day, value: i, to: $0) }
                            ?? Date(timeIntervalSinceNow: Double(serial - 10_000) / 100),
                        id: id)
                    serial += 1
                }
            }
        }

        /// 「2026-10-05」を、その日の正午の日時にする
        private static func date(_ text: String) -> Date? {
            let parts = text.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return Calendar.current.date(
                from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        }

        private static let heads = ["灰色の", "遠い", "静かな", "四角い", "夜更けの", "小さな", "白い", "長い", "眠る", "青い", "古い", "冬の"]
        private static let bodies = ["標本箱", "観測所", "図書係", "灯台", "時計", "鯨", "温室", "地図", "回廊", "郵便局", "書架", "植物園", "惑星"]
        private static let tails = ["の記録", "について", "と午後", "の手帖", "の問題", "", "の作り方", "をめぐって"]

        private static let headsEn = ["Gray", "Distant", "Quiet", "Square", "Midnight", "Small", "White", "Long"]
        private static let bodiesEn = [
            "Specimen Box", "Observatory", "Lighthouse", "Clock", "Whale", "Greenhouse", "Atlas",
        ]

        /// 架空の題名（番号ごとに決まる）。英語表示のとき（T15 の UI テスト・スクリーンショット）は英語の語で作る。
        /// 語の組み合わせは日本語は24冊、英語は56冊で一巡するので、2巡目からは「 2」「 3」…を付けて題名を重ねない（N-055）
        static func title(_ serial: Int) -> String {
            if InitialGenres.displaysInEnglish {
                let head = headsEn[serial % headsEn.count]
                let base = "The \(head) \(bodiesEn[(serial / headsEn.count + serial) % bodiesEn.count])"
                return volume(base, serial: serial, cycle: 56)
            }
            let head = heads[serial % heads.count]
            let body = bodies[(serial / heads.count + serial) % bodies.count]
            let tail = tails[(serial * 7 / 3) % tails.count]
            return volume("\(head)\(body)\(tail)", serial: serial, cycle: 24)
        }

        private static func volume(_ base: String, serial: Int, cycle: Int) -> String {
            serial < cycle ? base : "\(base) \(serial / cycle + 1)"
        }

        /// 合成の表紙（縦横比を少しずつ変える。色の地・帯・題名）
        static func cover(title: String, serial: Int) -> (original: Data, thumbnail: Data) {
            let ratios: [CGFloat] = [0.70, 0.66, 0.72, 0.75, 0.68, 0.62]
            let height: CGFloat = 640
            let size = CGSize(width: (height * ratios[serial % ratios.count]).rounded(), height: height)
            let hue = CGFloat((serial * 47) % 360) / 360
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor(hue: hue, saturation: 0.35, brightness: 0.86, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor(hue: hue, saturation: 0.55, brightness: 0.45, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: size.height * 0.72, width: size.width, height: size.height * 0.12))
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let text = NSAttributedString(
                    string: title,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: size.width * 0.11, weight: .bold),
                        .foregroundColor: UIColor(white: 0.1, alpha: 1),
                        .paragraphStyle: paragraph,
                    ])
                text.draw(
                    in: CGRect(
                        x: size.width * 0.1, y: size.height * 0.16, width: size.width * 0.8, height: size.height * 0.5))
            }
            let original = image.jpegData(compressionQuality: 0.8) ?? Data()
            return (original, original)
        }
    }
#endif
