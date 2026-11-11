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
                ShelfScreen(environment: environment)
                    .modelContainer(environment.container)
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
    private let arguments: [String]

    init(container: ModelContainer, images: ImageStore, defaults: UserDefaults, arguments: [String]) throws {
        self.container = container
        self.store = LibraryStore(container: container, images: images)
        self.recent = RecentShelves(defaults: defaults)
        self.arguments = arguments
        try store.seedIfNeeded()
    }

    /// 起動引数 `-UITestReset` のときは、毎回まっさらなデータ（メモリ上）・一時フォルダの画像・専用の設定で起動する（UIテスト用）
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) throws -> AppEnvironment {
        let schema = Schema([Book.self, Shelf.self])
        if arguments.contains("-UITestReset") {
            let suite = "com.ryutaro3215.bookshelf.uitest"
            UserDefaults().removePersistentDomain(forName: suite)
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            let container = try ModelContainer(
                for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            let images = ImageStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "UITestCovers-\(UUID().uuidString)", isDirectory: true))
            let environment = try AppEnvironment(
                container: container, images: images, defaults: defaults, arguments: arguments)
            #if DEBUG
                if let index = arguments.firstIndex(of: "-SeedBooks"), index + 1 < arguments.count {
                    try DebugSeed.apply(arguments[index + 1], to: environment.store)
                }
            #endif
            return environment
        }
        let container = try ModelContainer(for: schema)
        return try AppEnvironment(
            container: container, images: try ImageStore.standard(), defaults: .standard, arguments: arguments)
    }

    /// 撮影に使うカメラ。シミュレータと起動引数 `-FakeCamera <シナリオ>` のときは合成画像のカメラ（デバッグビルドのみ）
    func makeCamera() -> any CameraSource {
        #if DEBUG
            if let index = arguments.firstIndex(of: "-FakeCamera"), index + 1 < arguments.count {
                return FakeCameraSource(scenario: FakeCameraSource.parse(arguments[index + 1]))
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
                let counts = pieces[1].split(separator: "+").map { Int($0) ?? 0 }
                let owned = counts.first ?? 0
                let wanted = counts.count > 1 ? counts[1] : 0
                for i in 0..<(owned + wanted) {
                    let title = Self.title(serial)
                    let id = UUID()
                    let cover = Self.cover(title: title, serial: serial)
                    try store.images.save(original: cover.original, thumbnail: cover.thumbnail, for: id)
                    try store.addBook(
                        title: title, shelf: shelf, ownership: i < owned ? .owned : .wanted,
                        now: Date(timeIntervalSinceNow: Double(serial - 10_000)), id: id)
                    serial += 1
                }
            }
        }

        private static let heads = ["灰色の", "遠い", "静かな", "四角い", "夜更けの", "小さな", "白い", "長い", "眠る", "青い", "古い", "冬の"]
        private static let bodies = ["標本箱", "観測所", "図書係", "灯台", "時計", "鯨", "温室", "地図", "回廊", "郵便局", "書架", "植物園", "惑星"]
        private static let tails = ["の記録", "について", "と午後", "の手帖", "の問題", "", "の作り方", "をめぐって"]

        /// 架空の題名（番号ごとに決まる）
        static func title(_ serial: Int) -> String {
            let head = heads[serial % heads.count]
            let body = bodies[(serial / heads.count + serial) % bodies.count]
            let tail = tails[(serial * 7 / 3) % tails.count]
            return "\(head)\(body)\(tail)"
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
