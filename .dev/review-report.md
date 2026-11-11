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
