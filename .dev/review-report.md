# Review Report

## T1: PASS (2026-11-11)
- acceptance再実行:
  - `xcodebuild clean build -project Bookshelf.xcodeproj -scheme Bookshelf -destination "platform=iOS Simulator,id=64DCF75A-D3DE-4660-85D9-2CB8684A2F40"`（iPhone 17 Pro / iOS 26.5）→ `** BUILD SUCCEEDED **`（AppIntents のメタデータ抽出を飛ばした旨の warning 1件のみ。動作に影響なし）
  - `scripts/check-no-network.sh` → exit=0。`Bookshelf/` に `x = "https://example.com"` を含むファイルを置く → 該当行を出して exit=1。`NWConnection` を含むファイル → exit=1。存在しないフォルダを渡す → exit=2。確認用ファイルは削除済み
  - `swift format lint -r Bookshelf` → exit=0（`--strict` でも exit=0）
- 指摘:
  - [should] scripts/check-no-network.sh:7 既定の対象 `Bookshelf` がカレントディレクトリ基準のため、リポジトリ直下以外から実行すると exit=2 になる。スクリプトの場所を基準に `$(dirname "$0")/../Bookshelf` を既定にすると、CI や別ディレクトリからの実行でも安定する
  - [should] scripts/check-no-network.sh:8 検出パターンが plan.md の5語に限られる。`WKWebView`・`NSURLConnection`・`NWBrowser`/`NWListener`・`CFStream` なども外部通信の入口になりうる。リリース前の dev-security で対象語を広げることを推奨（今回の acceptance は満たしている）
  - [should] Bookshelf.xcodeproj/project.xcproj `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` に横向きが残っている。デザイン（design-brief.md の 402×874 縦画面）は縦向きのみなので、T6 で縦だけにするか判断が必要（build-log の notes と同じ認識）
  - [should] リポジトリに `.gitignore` がない。GitHub に上げる前に `xcuserdata/`・`DerivedData/`・`.DS_Store` を除外すべき（build-log の提案と同じ。plan.md の files 外のため、計画の更新か orchestrator 判断で追加）
  - [nit] plan.md の T1 files は `Bookshelf/Info.plist` だが、自動生成の Info.plist ＋ `INFOPLIST_KEY_…` で実現している。生成物に `NSCameraUsageDescription`・`NSPhotoLibraryAddUsageDescription`・`MinimumOSVersion=26.0`・`UIDeviceFamily=[1]` が入ることを確認したので、要件（S4）上は問題なし。plan.md の files の記載を実態に合わせる更新を dev-architect に推奨

## T2: PASS (2026-11-11)
- acceptance再実行:
  - `xcodebuild test -project Bookshelf.xcodeproj -scheme Bookshelf -destination "platform=iOS Simulator,id=64DCF75A-D3DE-4660-85D9-2CB8684A2F40"`（iPhone 17 Pro / iOS 26.5）→ `✔ Test run with 13 tests in 2 suites passed`、`** TEST SUCCEEDED **`。LibraryStoreTests ①〜⑨ の9件と YomiTests 4件（空・漢字かな・英字・カタカナ）がすべて成功。途中でアプリが止まることはなかった
  - `scripts/check-no-network.sh` → exit=0
  - `swift format lint -r Bookshelf BookshelfTests` → exit=0
- 指摘:
  - [should] Bookshelf/Model/LibraryStore.swift:128 `deleteBook` は画像を先に消してから本を消して保存している。保存に失敗すると、本は残るのに画像だけ消えた状態になる。本の削除と保存を先にし、成功したあとで画像を消す順にするとよい
  - [should] Bookshelf/Model/Book.swift:16 `id` に `@Attribute(.unique)` が付いていない。画像ファイル名に使う ID なので、重複を防ぐために一意にしておくとよい（現状は UUID() 生成のため実害はない）
  - [should] Bookshelf.xcodeproj/project.xcproj `SWIFT_VERSION` が 5.0 のまま。plan.md の stack は Swift 6。言語モードを 6 にすると、並行処理の検査が厳しくなり後の T5（カメラ）で効く。早めに上げるか、dev-architect で決めるべき（build-log の気づき①と同じ）
  - [should] Bookshelf.xcodeproj/project.xcproj バンドル ID が `devplaceholder.$(PROJECT_UNIQUE_VALUE…)` のまま。実機での確認（T3 の画像パイプラインの実測、T4 の OCR 精度の実測）より前に決める必要がある（build-log の気づき②と同じ）
  - [nit] Bookshelf/Storage/ImageStore.swift:16 表紙画像を Application Support に置いている。iCloud バックアップの対象にするかどうか（端末の容量・プライバシー）は要件に記載がない。リリース前に dev-security / dev-architect で確認を推奨
- 要件との整合: §10.3（買いたい本は入れ物ではない・ジャンルは所持状況にかかわらず持つ）、§10.6（初期ジャンル28個と ja/en、区分「システム」の表示名「その他」）、S6（200文字・制御文字の除去）、F7-1（よみ）に合っていることをコードで確認した。計画の files 外の project.xcproj の変更（テストのターゲットの追加）は、acceptance の実行に必要なもので妥当
- 追加確認（2026-11-11）: should 4件のうち、`deleteBook` の順番・`id` の一意化・Swift 6・バンドル ID の4件が対応済み。Swift 6 で `xcodebuild test` を再実行し 13件成功・並行処理の警告なしを確認。PASS のまま
