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

## T5: FAIL (2026-11-11)
- acceptance再実行:
  - `xcodebuild test -project Bookshelf.xcodeproj -scheme Bookshelf -destination "platform=iOS Simulator,id=64DCF75A-D3DE-4660-85D9-2CB8684A2F40"`（iPhone 17 Pro / iOS 26.5）→ `** TEST SUCCEEDED **`。ユニット `✔ Test run with 29 tests in 6 suites passed after 3.758 seconds`（CoverProcessorTests ①〜⑤ は引き続き成功。OCRAccuracyTests・CoverDetectionAccuracyTests は BOOKSHELF_ACCURACY 未指定でスキップ）。UI は CaptureFlowUITests の8件（①〜⑧）がすべて passed。並行処理の警告なし（実行時の警告は仮の入口の `UIKitToolbar` だけ。builder の notes と同じ）
  - `swift format lint -r Bookshelf BookshelfTests BookshelfUITests` → 出力なし、exit=0
  - `scripts/check-no-network.sh` → `OK（Bookshelf に通信の記述なし）`、exit=0
  - 表紙検出の実測（シミュレータ）: `TEST_RUNNER_BOOKSHELF_ACCURACY=1 TEST_RUNNER_BOOKSHELF_ACCURACY_OUT=<scratchpad> xcodebuild test ... -only-testing:BookshelfTests/CoverDetectionAccuracyTests` → 自動検出 **12/25**（builder の記録は 13/25。1枚の揺れ）。書き出した補正後の画像を目視すると、検出12枚のうち **R01・R07・R13・R14・R18 の5枚は表紙ではなく内側の四角形（帯・絵の枠・帯の文字の枠）**。横長の出力（478x188・783x589・493x253・533x296 など）がそれ。シミュレータで正しく取れたのは最大7/25で、T3（正しく取れた 6/25）とほぼ同じ
  - Mac での 16/25 は再実行していない（builder の検証用プログラムはリポジトリ外）。目標プラットフォーム（実機）での値は未測定
  - CIContext の使い回し: `CoverPipeline`（actor）が `CoverProcessor` を1つだけ持ち、`CaptureViewModel` が1つの `CoverPipeline` を持つ（Bookshelf/Capture/CaptureViewModel.swift:49-56,135）。撮影のたびに作り直していないことを確認
  - 撮影→次の撮影可能の時間: os_signpost `ShutterToReady` と Logger の ms 出力がある（CaptureViewModel.swift:179-188）。実機の計測はオーナー作業（計測手段があるので、これだけでは FAIL にしない）
  - 見た目: スクリーンショット（A-2・A-3・C-2・C-6・N-1 など）を design/screens の PNG と並べて確認。C-2 は見出し・追加ボタン・購入済み n/m とすべて選択/解除・行（チェック・表紙・題名欄・必須・ジャンル・状態）・未入力の案内・登録ボタンの文言と構成が一致。A-3 は上部（閉じる・登録先チップ）・撮影済みのサムネイルと「n / 30冊 撮影済み」・シャッター・完了が一致し、差は builder の notes のとおり（ライブラリボタンがアイコン、撮影ガイドの文言を追加）。最終の一致確認は計画どおりオーナーの Figma 目視
  - 著作権: manifest.json・raw-titles.json の題名（26件）を、T5 で追加・変更した追跡対象・未追跡ファイル（`git ls-files -mo --exclude-standard`）に対して原文と NFKC・空白約物除去後で照合 → 一致は .dev/build-log.md の T3 の記録（既知・T4 で指摘済み）だけで、T5 で増えたものはない。FakeCameraSource の題名・UI テストの題名はすべて架空。リポジトリ内・/tmp に ZZScreenshotTemp などの一時ファイルは残っていない
- 要件との整合: F1-1・F1-3（連続撮影・カメラを閉じない）、F1-5（買いたい本を飛ばす）、F1-6（2つの入口。仮の入口で確認）、F1-8（登録待ち＋処理中＋手動調整待ちで数える・ライブラリは残り冊数まで）、F2-2（補正・OCR を待たない。OCR は `@concurrent`）、F3-4（初期は全冊購入済み）、S1（通信なし）、S4（OS の PhotosPicker で読み取り権限なし）に合っている。FakeCameraSource は `#if DEBUG` のみで、リリースビルドの `makeCamera()` は常に `CameraController`（Bookshelf/BookshelfApp.swift:63-75）。`-UITestReset` はメモリ上の新しいデータ・一時フォルダ・専用の UserDefaults を使うだけで、利用者の保存データ（既定の ModelContainer・Application Support・standard の UserDefaults）は消さない
- 計画とのズレ（files 外）の判断: project.xcproj（UI テストのターゲット）・BookshelfApp.swift／ContentView.swift（T6 までの仮の入口）は acceptance の実行に必要で妥当。TitleRecognizer の `@concurrent`（N-025）と OCRAccuracyTests の環境変数（N-026）は T4 レビューの指摘への対応で妥当。CoverProcessorTests の `@Suite(.serialized)` も妥当と判断する — 同期の `handler.perform` を協調スレッドの上で多数同時に呼ぶと、Vision 内部の Swift Concurrency の処理が動けず止まるという説明は筋が通る。アプリでは同期の検出を呼ぶのは CoverPipeline（actor で1つずつ。協調スレッドを1本ふさぐだけ）とライブ検出（GCD の videoQueue）だけで、協調スレッドが全部ふさがる経路は見当たらない。書体の同梱は design-brief の書体の指定に必要だが、ライセンス文が無い（下の指摘）
- 指摘:
  - [must] Bookshelf/Imaging/CoverDetector.swift:80,106-112 書類の輪郭が使えないときに戻る「従来の四角形検出」が、T3 より緩くなっている。Vision への `minimumSize` を 0.2（寄せる用）に下げたうえで、後の絞り込みを `max(w, h) >= 0.4 × 短辺`（長い方の辺）で判定しているため、表紙の幅いっぱいの帯や絵の枠など、横長の内側の四角形が通る。シミュレータ（書類の輪郭が壊れて全枚がこの経路に落ちる）では検出12枚のうち5枚が帯・枠の誤った切り抜き（R01・R07・R13・R14・R18）で、T3（7枚中の誤り1枚）より悪い。誤った切り抜きは「検出成功」として N 画面を通らず登録待ちに入り、一覧には切り抜きを直す手段も行を消す手段も無いので、利用者は帯だけの表紙を登録するか一覧を全部捨てるしかない。builder の notes の「実機でも輪郭が壊れる場合は約 6/25 に戻る」は楽観的で、実際は誤った切り抜きが増える。T3 と同じ強さに戻す（`min(w, h)` で判定する、または最小 0.4 の `VNDetectRectanglesRequest` を別に走らせる。あわせて縦持ち撮影なので横長の四角形は表紙らしくないとみなす等）こと。直したら同じコマンドでシミュレータの検出・誤りの枚数を build-log に記録する
  - [should] .dev/build-log.md の T5 verify「改善後 16/25」は Mac（macOS の Vision）での値で、acceptance の対象（アプリが動く iOS）では測れていない。シミュレータでは書類の輪郭が使えず値にならないので、計画どおり「15/25 に届いたことを記録」とは扱えない。acceptance の但し書き（届かない場合は到達枚数と原因の見立てを記録しオーナーに判断を仰ぐ）に当たるものとして、実機での CoverDetectionAccuracyTests（または同等の確認）をオーナー作業として dev-orchestrator で管理すること
  - [should] Bookshelf/Capture/PendingListView.swift:244-294・Bookshelf/Capture/CaptureViewModel.swift:270 登録待ちの行を消す操作が無い（`remove(_:)` はどこからも呼ばれていない）。誤った切り抜き・同じ本の撮り直し・間違えて入れた写真を外せず、30冊に達したときに1冊外して撮り直すこともできない。行のスワイプ削除か長押しメニューを付け、「削除すると残り冊数が戻りシャッター・ライブラリが押せるようになる」ことを UI テストで確認するとよい（デザインに無いのでオーナー確認が要る）
  - [should] Bookshelf/Capture/CaptureViewModel.swift:281 `store.images.save` が2冊目以降で失敗すると、内側の `do` の外なので、すでに `addBook` した本を `items` から外さずに投げる。もう一度「登録」を押すとその本が二重に登録される。`save` も同じ `do` に入れて、失敗時に `items.removeFirst(registered)` を通すこと
  - [should] Bookshelf/Capture/CaptureViewModel.swift:241-246・Bookshelf/Capture/CaptureView.swift:524-529・Bookshelf/Capture/PendingListView.swift:61-68 ライブラリの読み込み中（`PhotoLoader.load` と1枚ずつの `handleCaptured` の間）は、選んだ枚数が上限の数（`reservedCount`）に入っていない。その間に撮影すると30冊を超えうる。選んだ時点で枚数分を予約（`processingCount` に先に足す）するか、読み込み中はシャッター・追加ボタンを止めること
  - [should] Bookshelf/Capture/CaptureViewModel.swift:39-45,214・Bookshelf/Capture/CaptureView.swift:536-550 ライブラリから最大30枚を選ぶと、全枚の原寸データを先にまとめて読み込み（大きい HEIC だと数百MB）、検出に失敗した写真は原寸の `original` と展開済みの 1600px の `preview`（1枚約7.7MB）を手動調整待ちとして溜める。撮影では1枚ずつしか溜まらないが、ライブラリでは30枚分になりうる。読み込みを1枚ずつ処理に流す、`preview` は N 画面に出す直前に作る、等で上限を抑えること（iPhone 13 相当での確認を推奨）
  - [should] Bookshelf/Resources/Fonts/ Noto Sans JP・Noto Serif JP（SIL OFL）のライセンス文・著作権表示を同梱していない。OFL は再配布時にライセンスと著作権表示を添えることを求める。check-no-network.sh が URL に反応するという理由は検査側の問題なので、ライセンス文から URL を除いた形で同梱する／検査対象を .swift に絞る（N-010）等で、リリース前に必ず対応すること（dev-security のリリース判定の項目にも入れるべき）
  - [should] Bookshelf/Capture/CaptureView.swift:383-393 「表紙を検出しました」は直前の撮影の結果（`lastCaptureDetected`）でも出るため、次に写っている物に表紙が無くても出続ける（スクリーンショット A-3-camera-after4 で確認）。A-3 のデザインはライブの検出を示す表示なので、ライブの四隅（`liveQuad`）だけで出すか、直前の撮影の結果は短時間で消すこと
  - [should] BookshelfUITests/CaptureFlowUITests.swift O-3（カメラを許可しなかったとき）の UI テストが無い。FakeCameraSource は常に `.authorized` なので、許可なしの経路（`deniedContent` と、そこからのライブラリ選択）が自動で確かめられていない。起動引数で許可なしのシナリオを足して確認するとよい
  - [should] Bookshelf/Capture/CaptureViewModel.swift:49-56 CoverPipeline（actor）は協調スレッドの上で同期の Vision（内部で協調スレッドを使う）を呼んでいる。現状は1本しかふさがないので止まらないが、CoverProcessorTests を直列にしないと止まった原因と同じ形。将来 actor を増やしたり並列化したりすると再発するので、専用の DispatchQueue（またはカスタム executor）で動かすか、builder の提案どおり `process` を async の Vision API に移すことを推奨
  - [nit] Bookshelf/Capture/CornerAdjustView.swift:166-176 手動の四隅は交差・凹んだ四角形にもでき、そのまま補正に回る。確定時に `CoverDetector.isConvex` 等で弾くか、角の位置を入れ替えて整えるとよい
  - [nit] Bookshelf/Capture/PendingListView.swift:28 `selectableShelves()`（SwiftData の取得）を行ごと・再描画ごとに呼んでいる。30行では実害は小さいが、一覧で1回だけ取って渡すとよい
  - [nit] Bookshelf/BookshelfApp.swift:46 `-UITestReset` はリリースでもデータを消さないが、テスト用の分岐なので `#if DEBUG` に入れておくと安心。一時フォルダの `UITestCovers-<UUID>` は消していない（OS が片付けるので実害なし）
  - [nit] Bookshelf/Capture/CameraController.swift:99 `onQuad` は MainActor（init）で書き、videoQueue で読む。セッション開始前に1回書くだけなので実害はないが、`let` にして init で渡すと Sendable の検査が効く
  - [nit] Bookshelf/Resources/Fonts/ 可変フォント2つで約23MB。アプリの容量が大きくなるので、使うウェイト（400・500・600）だけの静的フォントにする等を T12 で検討
- オーナー判断が必要（裁定していない）: ①C-1（自作の写真グリッド）と requirements F1-4・S4（OS の写真ピッカー・読み取り権限なし）の食い違い。実装は OS の PhotosPicker ②C-3（題名の編集画面）・C-4（棚に並ぶ演出）・O-1（許可の説明画面）は未実装（builder は C-4 を T6、O-1 を T14 の想定としている）③撮影ガイド2行目・「この範囲で使う」・閉じるときの確認の文言 ④実機での撮影時間・ライブの四隅表示・検出率の確認

## T5（再レビュー）: PASS (2026-11-11)
- acceptance再実行:
  - `xcodebuild test -project Bookshelf.xcodeproj -scheme Bookshelf -destination "platform=iOS Simulator,id=64DCF75A-D3DE-4660-85D9-2CB8684A2F40"`（iPhone 17 Pro / iOS 26.5）→ `** TEST SUCCEEDED **`。ユニット `✔ Test run with 29 tests in 6 suites passed after 3.901 seconds`（CoverProcessorTests ①〜⑤ 成功、精度の2スイートはスキップ）。UI は CaptureFlowUITests 8件すべて passed（testLimitOfThirtyBooks に追加された「30冊で1行を外す → 29 / 30冊・撮影を追加が押せる → シャッターが押せ、上限の案内が消える」を含む）
  - `swift format lint -r Bookshelf BookshelfTests BookshelfUITests` → 出力なし、exit=0
  - `scripts/check-no-network.sh` → `OK（Bookshelf に通信の記述なし）`、exit=0
  - 表紙検出（シミュレータ）: `TEST_RUNNER_BOOKSHELF_ACCURACY=1 TEST_RUNNER_BOOKSHELF_ACCURACY_OUT=<scratchpad> xcodebuild test ... -only-testing:BookshelfTests/CoverDetectionAccuracyTests` → 自動検出 **7/25**（R02・R04・R08・R10・R11・R13・R21）。書き出した7枚をすべて目視: R04・R08・R10・R11・R21 の **5枚は表紙全体を正しく切り抜き**、**R02（新書の表紙の内側の色の面）と R13（表紙の内側の枠）の2枚が誤り**。builder の記録（正しい5・誤り2）と一致。出力はすべて縦長（横長の帯の切り抜きは無くなった）。前回の誤り R01・R07・R14・R18（帯・絵の枠）は未検出になり N 画面に回る
  - Mac での 16/25（誤り3）は再実行していない（検証用プログラムはリポジトリ外）
- 前回の指摘の確認:
  - [must] 解消。Bookshelf/Imaging/CoverDetector.swift:104-136 四角形検出だけで決めるときは「短い方の辺が画像の短辺の 0.4 以上（ピクセルの比で計算）」「縦長（高さ ≧ 幅×0.95）」「凸」をすべて満たすものに限った。書類の輪郭の側も縦長を必須にした（:165）。シミュレータの「下端 25% の帯」は横長なので輪郭としては採用されず、四角形検出にも合うものが無ければ N 画面に回る（上の実測で確認）。寄せる先の四角形（:96-99）は表紙らしいと判定した輪郭の各頂点から 0.05 以内に限るので、帯・枠に寄ることはない
  - [should] 二重登録: 解消。Bookshelf/Capture/CaptureViewModel.swift:301-315 画像の保存と `addBook` を同じ `do` に入れ、失敗時は画像を消し、登録済みの本を `items.removeFirst(registered)` で外してから投げる。再度の登録で同じ本が二重に入らない（全か無かではなく「登録できた分は登録済み・残りは一覧に残る」の動き。builder の設計どおりで問題なし）
  - [should] 行を外す操作: 解消。Bookshelf/Capture/PendingListView.swift:24-36 List の行を左スワイプで「外す」、VoiceOver のカスタムアクション「登録待ちから外す」もある。30冊で1行外すと残りが戻ることを UI テストで確認した
  - [should] ライブラリ読み込み中の上限: 解消。Bookshelf/Capture/CaptureViewModel.swift:257-268 選んだ時点で `prefix(remaining)` の枚数を `processingCount` に先に足し、読めなかった分だけ戻す。読み込み中に撮影しても `reservedCount` が30を超えない。1枚ずつ読み込んで処理するようになったので、前回のメモリの指摘（全枚の原寸を先に読む）も半分は改善した（手動調整待ちに原寸と preview を溜める点は残る）
  - [should] 「表紙を検出しました」: 解消。Bookshelf/Capture/CaptureView.swift:384・CaptureViewModel.swift:228-235 ライブの四隅があるときか、検出できた撮影の直後 1.5 秒だけ出す。前の Task は cancel してから張り直す
- 検出率の目標（15/25）の扱い: 計画の但し書き（届かない場合は到達枚数と原因の見立てを記録してオーナーに報告し、判断を仰ぐ）に当たると判断する。到達枚数（シミュレータ 5/25・Mac 16/25・実機は未測定）と原因（iOS 26.5 シミュレータの `VNDetectDocumentSegmentationRequest` が画像によらず下端の帯を返す）が build-log に記録されているので、acceptance の手続きとしては満たしている。15/25 に届いたかどうかは実機の値で決まるので、オーナーの実機確認（CoverDetectionAccuracyTests を実機で実行）を dev-orchestrator で管理すること。実機でもシミュレータと同じなら約 5/25 で、目標には届かない
- 残る誤り（シミュレータの R02・R13）の評価: T3（正しい6・誤り1＝R13）と比べると、正しい数は1減り、誤りは R02 が1増えた。ただし ①誤りの種類は T3 と同じ「表紙の内側の大きな四角形」で、前回の must の原因だった横長の帯は無くなった ②今回から一覧で行を外して撮り直せるので、誤った切り抜きの逃げ道がある ③シミュレータは書類の輪郭が壊れた状態の値で、輪郭が使える Mac では正しい16・誤り3。以上から許容範囲とし、must にはしない
- 指摘:
  - [should] Bookshelf/Capture/PendingListView.swift 誤った切り抜きは今も N 画面を通らずに一覧に入り、直す方法は「外して撮り直す」だけ。一覧の行から四隅の調整（N 画面）を開けるようにすると、内側の枠を取った本（R02・R13 の型）も撮り直さずに直せる。デザインに無い操作なのでオーナー確認のうえで
  - [should] 行の左スワイプ「外す」はデザインに無い操作（builder の notes のとおり）。オーナーに確認すること
  - [should] 前回の残り（今回の依頼の範囲外で未対応）: 手動調整待ちに原寸と展開済みの preview を溜める点のメモリ（CaptureViewModel.swift:39-45,214。ライブラリから多数選んで検出に失敗した場合）、Noto フォントの OFL のライセンス文の同梱（リリース前に必須）、O-3 の UI テスト、協調スレッド上の同期 Vision（CoverPipeline）。dev-orchestrator で notices に起票して追跡すること
  - [nit] BookshelfUITests/CaptureFlowUITests.swift testLimitOfThirtyBooks の `print(app.debugDescription)` は調査用の出力。直後の `XCTAssertTrue(remove.exists)` で落ちるので消してよい
  - [nit] 前回の nit（四隅の凸の検査・`-UITestReset` の `#if DEBUG`・`onQuad` の `let` 化・フォントの容量）は未対応のまま。無視してよい
- オーナー判断が必要（裁定していない。前回から変わらず）: C-1 と F1-4・S4 の食い違い／C-3・C-4・O-1 の未実装／撮影ガイド2行目・「この範囲で使う」・閉じるときの確認の文言／行のスワイプ削除／実機での撮影時間・ライブの四隅表示・検出率
