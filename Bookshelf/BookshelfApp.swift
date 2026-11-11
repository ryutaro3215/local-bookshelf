import SwiftData
import SwiftUI

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
                ContentView(environment: environment)
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
            return try AppEnvironment(container: container, images: images, defaults: defaults, arguments: arguments)
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
