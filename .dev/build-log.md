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
