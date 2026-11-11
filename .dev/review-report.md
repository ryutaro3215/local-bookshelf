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

## T3: PASS (2026-11-11)
- acceptance再実行:
  - `xcodebuild test -project Bookshelf.xcodeproj -scheme Bookshelf -destination "platform=iOS Simulator,id=64DCF75A-D3DE-4660-85D9-2CB8684A2F40"`（iPhone 17 Pro / iOS 26.5）→ `✔ Test run with 18 tests in 3 suites passed`、`** TEST SUCCEEDED **`。CoverProcessorTests（①〜⑤）・LibraryStoreTests・YomiTests のすべてのスイートが成功
  - `scripts/check-no-network.sh` → exit=0
  - `swift format lint -r Bookshelf BookshelfTests` → exit=0
  - BookshelfTests/Fixtures/ の5枚はすべて合成画像（架空の表紙・架空の GPS）で、実在の書籍の表紙を含まないことを確認
- 指摘:
  - [should] Bookshelf/Imaging/CoverDetector.swift 実写25枚（design/sample-covers/raw）での自動検出は 7/25（うち1枚は内側の枠を誤検出）と builder が報告している。合成フィクスチャでは合格するが、書店で手に持って撮る実際の使い方では多くが手動調整（F1-2 の後半・N 画面）に回る見込み。成功指標「100冊を2時間以内」に効くので、T5 で ①撮影ガイド（表紙を枠いっぱいに・背景と分ける）②`VNDetectDocumentSegmentationRequest` の併用や閾値の再調整 ③手動調整の操作を軽くすること、を acceptance に含めるよう dev-architect に推奨
  - [should] BookshelfTests/Fixtures/ フォルダ同期でテストバンドル直下に平らにコピーされるため、T4 の OCR 用フィクスチャとファイル名が重なると衝突する。T4 ではファイル名に接頭辞（例: `ocr-…`）を付けるか、フォルダ参照にすること
  - [should] Bookshelf/Imaging/CoverProcessor.swift:34 `CIContext` を `CoverProcessor` ごとに作っている。T5 の連続撮影で1枚ごとに作り直すと遅くなるので、呼ぶ側で1つを使い回す設計にすること（builder の申し送りと同じ）
  - [nit] scripts/generate-cover-fixtures.py は plan.md の files 外だが、フィクスチャを作り直せるようにするためのもので妥当。plan.md の files への追記を dev-architect に推奨
  - [nit] ④ ImageIO の JPEG 出力には EXIF 辞書の ColorSpace・PixelXDimension・PixelYDimension の3項目が必ず残る。撮影日時・機種・位置情報は残らないので S6 の趣旨は満たしている

## T4: PASS (2026-11-11)
- acceptance再実行:
  - `xcodebuild test -project Bookshelf.xcodeproj -scheme Bookshelf -destination "platform=iOS Simulator,id=64DCF75A-D3DE-4660-85D9-2CB8684A2F40"`（iPhone 17 Pro / iOS 26.5）→ `✔ Test run with 28 tests in 5 suites passed after 39.141 seconds`、`** TEST SUCCEEDED **`。TitleRecognizerTests（①横書き英語・横書き日本語・縦書き日本語で候補に含む／先頭になる、②文字のない表紙・空 Data・画像でない Data で空の候補）と並べ方の単体テストがすべて成功。並行処理の警告なし
  - OCRAccuracyTests の出力（切り抜き23枚・raw 25枚の表、四隅の自動検出 7/25、サンプルごとの判定）が .dev/ocr-accuracy.md の表・サンプルごとの判定と完全に一致することを確認
  - スキップの確認: design/sample-covers の manifest.json と raw-titles.json を一時的に退避して同じコマンドを実行 → `Suite OCRAccuracyTests skipped: "実写のサンプル（design/sample-covers）が無いためスキップ"`、`✔ Test run with 28 tests in 5 suites passed after 2.785 seconds`、`** TEST SUCCEEDED **`。実行後に元へ戻し、shasum と `ls -l` が退避前と一致することを確認
  - `swift format lint -r Bookshelf BookshelfTests` → 出力なし、exit=0
  - `scripts/check-no-network.sh` → exit=0（S1）
  - `git status --porcelain --ignored` → `design/sample-covers/` は `!!`（ignored）。追跡対象の新規ファイルは TitleRecognizer.swift・テスト2本・ocr-*.png 4枚・generate-ocr-fixtures.py・ocr-accuracy.md のみ
  - 著作権の確認: ocr-*.png 4枚を目視し、すべて架空の題名・著者・出版社の合成表紙であることを確認。manifest.json（23件）・raw-titles.json（25件）の正解題名を、`git ls-files` と未追跡（ignore されていない）の全テキストファイルに対して照合（原文と NFKC・空白約物除去後の両方）→ T4 で追加・変更したファイルには一致なし。ocr-accuracy.md はサンプルを番号（Cxx・Rxx）だけで示している
- 要件との整合: F2-4（ja-JP・en-US、縦書きは合成フィクスチャで先頭候補になることを確認）、S1（Vision の端末内認識のみ・通信なし）、S6（候補は制御文字を除き200文字まで。つないだ候補も append 時に再度整える）、失敗時は os.Logger に記録して空配列を返し投げない（空 catch なし）。実測値が暫定なのは raw-titles.json・cover-categories.json が `"status": "draft"`（オーナー確認待ち）のためで、計画どおり。装飾書体が5枚未満であることは ocr-accuracy.md に記録され、追加撮影の依頼が build-log の notes にある
- 指摘:
  - [should] Bookshelf/Imaging/TitleRecognizer.swift:36,45 プロジェクトは `SWIFT_APPROACHABLE_CONCURRENCY=YES`（nonisolated(nonsending) が既定）・`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` のため、`nonisolated` 型の `async` 関数は呼んだ側の actor で動く。T5 で MainActor（画面）から `candidates(in:)` を呼ぶと、`uprightImage`（ImageIO による12MP 画像の縮小デコード）と `rankCandidates` がメインスレッドで実行され、撮影の操作が一瞬止まりうる（F2-2「撮影・登録の操作は OCR 完了を待たない」）。2つの `candidates(in:)` に `@concurrent` を付けて、確実に呼び出し元の actor から外すべき。T4 の acceptance には呼び出し元がないため PASS の判定には影響しない
  - [should] BookshelfTests/OCRAccuracyTests.swift:45 実写ファイルがある環境（オーナーの Mac）では、通常の `xcodebuild test` が 約3秒 → 約39秒になる（OCRAccuracyTests が約36秒）。閾値の判定はなく（件数 23・25 の確認のみ）、結果がぶれてもテストは落ちないので不安定ではないが、T5 以降の毎回のテストが遅くなる。環境変数（例: `OCR_ACCURACY=1`）が立っているときだけ有効にする、またはタグを付けて別のテストプランに分けることを推奨
  - [should] 既存の追跡ファイルに実在の書名が残っている（T4 で追加されたものではない）: BookshelfTests/LibraryStoreTests.swift:40-118（T2。サンプルの本の題名をテストデータに使っている。8件一致）、design/mock-todo.md（モックの作業記録。40件以上一致）、.dev/build-log.md:65（T3 の参考記録に1件）。「実在の表紙・題名を git 追跡ファイルに入れない」方針に反する。テストデータを架空の題名に差し替え、mock-todo.md は ignore するか書名を伏せるべき。すでにコミット済みなので、公開リポジトリにする場合は履歴の書き換えも必要。dev-orchestrator で notices に起票し、修正担当（builder / 文書の所有者）を決めることを推奨
  - [nit] BookshelfTests/OCRAccuracyTests.swift:57 cover-categories.json の読み込みを `try?` で握りつぶしている。ファイルが壊れていると全サンプルのカテゴリが「該当なし」になり、表の数字が黙って変わる。ファイルがあるのに読めないときは `#require` で落とす方が安全
  - [nit] Bookshelf/Imaging/TitleRecognizer.swift:160 `clean` が `LibraryStore.sanitize` と同じ処理の複製になっている（builder の notes のとおり、MainActor の LibraryStore から呼べないため）。将来どちらかの規則を変えたときにずれないよう、nonisolated の共通関数に寄せるとよい
