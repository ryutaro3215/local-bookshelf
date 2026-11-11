# Build Log

## T1: プロジェクト初期化 — done (2026-11-11)
- changed:
  - Bookshelf.xcodeproj/project.xcproj（Xcode 27 の JSON 形式。オーナーが Xcode で作成し、オーケストレーターが "Untitled Project" から Bookshelf に改名・直下へ移動済み）: SDKROOT=iphoneos、SUPPORTED_PLATFORMS=iphoneos iphonesimulator、TARGETED_DEVICE_FAMILY=1（iPhone のみ）、IPHONEOS_DEPLOYMENT_TARGET=26.0、INFOPLIST_KEY_NSCameraUsageDescription / INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription を追加
  - Bookshelf/BookshelfApp.swift: テンプレートの MyApp.swift を改名し、`@main struct BookshelfApp: App` にした
  - .swift-format: 4スペース字下げ・1行120文字・空行は最大1行
  - scripts/check-no-network.sh: 対象フォルダ（既定 Bookshelf/）を `URLSession|URLRequest|NWConnection|http://|https://` で検索し、なければ 0、あれば該当行を出して 1、フォルダがなければ 2 で終了
- verify:
  - `xcodebuild build -project Bookshelf.xcodeproj -scheme Bookshelf -destination "platform=iOS Simulator,id=64DCF75A-D3DE-4660-85D9-2CB8684A2F40"`（iPhone 17 Pro / iOS 26.5）→ `** BUILD SUCCEEDED **`
  - `scripts/check-no-network.sh` → `OK（Bookshelf に通信の記述なし）`、exit=0
  - `Bookshelf/_tmp_net_check.swift` に `let u = URLSession.shared` を置いて実行 → 該当行を出力、exit=1。ファイル削除後 → exit=0
  - `swift format lint -r Bookshelf` → 出力なし、exit=0
  - 生成された Info.plist（DerivedData の Bookshelf.app）→ MinimumOSVersion=26.0、UIDeviceFamily=[1]、NSCameraUsageDescription と NSPhotoLibraryAddUsageDescription が入っていることを `plutil -p` で確認
- notes:
  - **計画とのズレ（files）**: plan.md は `Bookshelf/Info.plist` を作る前提だが、このプロジェクトは Info.plist を自動生成（GENERATE_INFOPLIST_FILE=YES）し、Bookshelf/ フォルダを丸ごと取り込む形式のため、Info.plist ファイルを置くと生成物と衝突する。用途説明はビルド設定 `INFOPLIST_KEY_…` で入れた（生成された Info.plist に入ることを確認済み）。用途説明の英語化は T15（InfoPlist の String Catalog）で行う
  - テンプレートの Bookshelf/ContentView.swift（Hello, world! と #Playground）はそのまま。T6 で閲覧画面に置き換わる
  - テストのターゲット（Swift Testing・UI テスト）はまだない。T2 で追加が必要（plan.md の T2 以降の acceptance がテストの実行を前提にしているため）
  - 提案: GitHub に上げる前に `.gitignore`（xcuserdata/、DerivedData、.DS_Store）を追加したい（plan.md の T1 の files にないので未作成）。ほかに、デザインは縦向きだけなので iPhone の向きを縦だけに絞る設定も、今は横向きが残っている（T6 で決める）

## T2: データモデルと画像ストア — done (2026-11-11)
- changed:
  - Bookshelf/Model/Book.swift: `@Model Book`（id・題名・よみ・データ追加日・所持状況・購入日・ジャンル内の並び順・所属ジャンル）と `Ownership`（owned／wanted）
  - Bookshelf/Model/Shelf.swift: `@Model Shelf`（名前・英語名・区分 ID・並び順・種類）と `ShelfKind`（genre／wishlist／unsorted）。本との関係は削除時 nullify
  - Bookshelf/Model/InitialGenres.swift: 区分8つ（文芸〜芸術・生活、マイジャンル、システム＝表示名「その他」/Other）と初期ジャンル28個（ja/en。requirements §10.6 の表どおり）、システム棚の名前（買いたい本/Wishlist、未分類/Unsorted）
  - Bookshelf/Model/LibraryStore.swift: 初回の棚作成、本の追加（ジャンルの末尾・購入済みなら購入日＝データ追加日の日付）、本の削除（画像も削除）、所持状況の切り替え（買いたい→購入日を消す、購入済み→今日）、ジャンル一覧（購入済みだけ）、買いたい本の一覧、ジャンルの追加・名前変更・削除（中の本は未分類の末尾へ）、題名・ジャンル名の整形（制御文字を除去し200文字まで）。ModelContainer を保持する
  - Bookshelf/Text/Yomi.swift: CFStringTokenizer のローマ字表記→ひらがな変換でよみを作る。英字・数字のトークンはそのまま、かなだけのトークンはローマ字を経由せずにひらがなへ（長音「ー」を保つ）
  - Bookshelf/Storage/ImageStore.swift: 原寸 `<id>.jpg`・サムネイル `<id>_thumb.jpg` を Application Support/Covers（テストでは一時フォルダ）に保存・読込・削除
  - BookshelfTests/LibraryStoreTests.swift: acceptance ①〜⑨ の9ケース
  - BookshelfTests/YomiTests.swift: 漢字かな・カタカナ（長音）・英字・空の4ケース
  - Bookshelf.xcodeproj/project.xcproj: ユニットテストのターゲット BookshelfTests（Swift Testing、テストホスト Bookshelf、フォルダ同期「BookshelfTests」、iOS・iPhone のみ）を追加
- verify:
  - `xcodebuild test -project Bookshelf.xcodeproj -scheme Bookshelf -destination "platform=iOS Simulator,id=64DCF75A-D3DE-4660-85D9-2CB8684A2F40"`（iPhone 17 Pro / iOS 26.5）→ `✔ Test run with 13 tests in 2 suites passed`、`** TEST SUCCEEDED **`（LibraryStoreTests 9件・YomiTests 4件）
  - YomiTests の例: 「存在と時間」→「そんざいとじかん」、「アーモンド」→「あーもんど」、「Swift入門」→「Swiftにゅうもん」、「NARUTO」→「NARUTO」
  - `scripts/check-no-network.sh` → exit=0
  - `swift format lint -r Bookshelf BookshelfTests` → 出力なし、exit=0
  - `xcodebuild build`（同じシミュレータ）→ `** BUILD SUCCEEDED **`
- notes:
  - **計画とのズレ（files）**: テストを動かすため、plan.md の T2 の files にない Bookshelf.xcodeproj/project.xcproj にテストのターゲットを足した。共有スキームは作らずに済んだ（自動のスキーム Bookshelf がテストを含む）。Xcode 27 の JSON 形式で、`"product-type": "bundle.unit-test"`・`"test-host-target"`・`"dependencies"` を使い、`xcprojformatter` で読めることを確認済み
  - 設計の判断: ①「買いたい本」の棚は本の入れ物ではないので、`addBook` に買いたい本の棚を渡すと `invalidShelfForBook` を投げる（UI 側では登録先として選ばせない想定）②買いたい本の一覧はデータ追加日の順 ③ジャンルの追加はシステム棚（買いたい本・未分類）の直前に入れる ④ジャンル名を変えると英語名を消す（ユーザーの名前は翻訳しない。N7）⑤ ModelContainer が先に解放されると SwiftData が落ちるため、LibraryStore がコンテナを保持する形にした
  - テスト中にシミュレータが「テスト用アプリを起動できない」と2回失敗した（コードの問題ではなく、シミュレータを再起動すると通った）。並行して別の作業がシミュレータを使っていると起きやすい
  - 気づき（未対応）: ①プロジェクトの SWIFT_VERSION が 5.0（plan.md の stack は Swift 6）②バンドル ID がテンプレートの `devplaceholder.…` のまま。どちらも実機・リリース前に dev-architect で決めたい
- follow-up (2026-11-11, review-report T2 の should とオーナー判断への対応):
  - Bookshelf/Model/LibraryStore.swift: `deleteBook` を「本の削除と保存 → 成功後に画像を削除」の順に変えた（保存失敗時に画像だけ消えるのを防ぐ）
  - Bookshelf/Model/Book.swift: `id` に `@Attribute(.unique)` を付けた
  - Bookshelf.xcodeproj/project.xcproj: SWIFT_VERSION を 5.0 → 6.0（アプリ・テストとも。オーナー判断）。バンドル ID をアプリ `com.ryutaro3215.bookshelf`・テスト `com.ryutaro3215.bookshelf.tests` にした（オーナー判断）
  - verify: Swift 6 で `xcodebuild test`（iPhone 17 Pro / iOS 26.5）→ `✔ Test run with 13 tests in 2 suites passed`、`** TEST SUCCEEDED **`、並行処理のエラー・警告なし / `scripts/check-no-network.sh` → exit=0 / `swift format lint -r Bookshelf BookshelfTests` → exit=0 / 生成された Info.plist の CFBundleIdentifier = com.ryutaro3215.bookshelf
