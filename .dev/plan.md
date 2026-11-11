# Plan — local-bookshelf（仮称）
status: approved
stack: Swift 6 / Xcode（フォルダ同期グループ）/ iOS 26+ / iPhoneのみ / SwiftUI（アプリ全体）＋ UIKit UICollectionView（棚の表示・ドラッグ並べ替え）/ SwiftData（Book・Shelf）＋ 画像はApplication Support配下のファイル保存（原寸・サムネイル）/ AVFoundation（自作カメラ）/ Vision（四隅検出・日本語英語OCR）/ Core Image（台形補正）/ ImageRenderer（共有画像）/ PhotoKit（追加のみ権限）/ Swift Testing ＋ XCUITest / swift-format（Xcode付属）。サードパーティ依存なし（外部通信ゼロの保証のため）。2026-11-09 ユーザー承認（UI: SwiftUI＋棚だけUIKit、保存: SwiftData、カメラ: 自作）/ バンドルID: com.ryutaro3215.bookshelf（2026-11-11 オーナー決定）
external_skills:
  - （デザインはオーナーが Figma で作成する。Figma の要約として .dev/design-brief.md を使う（2026-11-11 作成・オーナー承認）。dev-design スキルは使わない — 2026-11-09 オーナー判断）
  - figma:figma-swiftui: オーナーの Figma デザインを SwiftUI 画面へ落とし込む（T5・T6・T8・T9・T10・T11）
  - figma:figma-design-to-code: Figma のノードからデザインコンテキスト（寸法・色・タイポグラフィ）を取得する際の前提手順（UI タスク全般）
  - designagent:design-to-code: Figma から DESIGN.md をエクスポートした場合、デザイントークン（色・書体・余白）を Swift のトークン定義に実装する（T6）
  - dev-reviewer / dev-security / dev-docs: 各タスクの検収、リリース前の監査（外部通信ゼロの確認を含む）、README

## 変更メモ
- 2026-11-11 オーナー承認: ①T4 を「自動テスト用の合成フィクスチャ（git 管理）」と「オーナーの実写での精度実測（git 管理外）」に分けた（表紙は著作物のため git に入れない）②T5 の acceptance に表紙検出の改善（撮影ガイド・`VNDetectDocumentSegmentationRequest` 併用と閾値の再調整・手動調整の軽量化。現状の実写自動検出 7/25 → 目標 15/25 以上）と CIContext の使い回しを追加（T3 レビューより）③stack にバンドルIDを記録 ④T1・T3 の files を実態に合わせた（自動生成 Info.plist、.gitignore、scripts/generate-cover-fixtures.py）

## 共通事項
- `$SIM` は利用可能な iPhone シミュレータ名（例: `xcrun simctl list devices available` で確認）
- テストの実行: `xcodebuild test -scheme Bookshelf -destination "platform=iOS Simulator,name=$SIM"`
- UI タスクは、オーナーが該当画面の Figma デザインを用意した後に着手する。デザインの正は Figma（URL は design/README.md に記録、DESIGN.md をエクスポートした場合は design/DESIGN.md）。acceptance の「Figma と一致」は、シミュレータのスクリーンショットを Figma の該当フレームと並べてオーナーが確認する
- すべてのタスクで `scripts/check-no-network.sh` が終了コード0であること（外部通信ゼロ: S1）

## T1: プロジェクト初期化
- goal: ビルド可能な空のiOSアプリと、外部通信ゼロを機械的に確認するスクリプトを用意する
- files: Bookshelf.xcodeproj（Xcodeで新規作成 — ユーザー作業: App / SwiftUI / Swift Testing / iOS 26 / iPhone）, Bookshelf/BookshelfApp.swift, Bookshelf.xcodeproj のビルド設定 `INFOPLIST_KEY_*`（Info.plist は自動生成。カメラ用途説明・写真追加用途説明）, .gitignore, .swift-format, scripts/check-no-network.sh
- acceptance: `xcodebuild build -scheme Bookshelf -destination "platform=iOS Simulator,name=$SIM"` が BUILD SUCCEEDED を出力する / `scripts/check-no-network.sh` が `URLSession|URLRequest|NWConnection|http://|https://` を Bookshelf/ 配下に検出せず終了コード0を返し、テスト用にそれらを含むファイルを置くと終了コード1を返す / `swift format lint -r Bookshelf` がエラー0件
- depends: なし
- skills: なし

## T2: データモデルと画像ストア
- goal: Book（題名・よみ・ジャンル・所持状況・購入日・データ追加日）と Shelf（ジャンル: 区分・並び順。システム棚「買いたい本」「未分類」）、初期ジャンル（ja/en）、よみの自動生成、画像ファイルの保存・読込・削除を実装する（requirements §10・F7-1。2026-11-10 更新）
- files: Bookshelf/Model/Book.swift, Bookshelf/Model/Shelf.swift, Bookshelf/Model/InitialGenres.swift, Bookshelf/Model/LibraryStore.swift, Bookshelf/Text/Yomi.swift, Bookshelf/Storage/ImageStore.swift, BookshelfTests/LibraryStoreTests.swift, BookshelfTests/YomiTests.swift
- acceptance: テスト実行で LibraryStoreTests の次のケースが全て通る — ①本の追加でジャンルの末尾に並ぶ ②ジャンルの削除で中の本が未分類へ移り、本数と所持状況が変わらない ③買いたい本・未分類は削除も名前変更もできない ④本の削除で画像ファイル（原寸・サムネ）も消える ⑤題名・ジャンル名が200文字に切り詰められ制御文字が除去される（S6）⑥新しいModelContainer（再起動相当）後もデータと並び順が保たれる ⑦所持状況を「買いたい」にすると購入日が消え、「購入済み」にすると購入日が今日になる（ジャンルは変わらない）⑧ジャンル別の一覧に「買いたい」の本が含まれず、買いたい本の一覧にだけ含まれる ⑨初回起動で初期ジャンルが区分付き・ja/en 名付きで作られる / YomiTests で題名からひらがなのよみが生成される（例:「存在と時間」→「そんざいとじかん」、英字はそのまま）
- depends: T1
- skills: なし

## T3: 画像パイプライン
- goal: 撮影画像から表紙の四隅を検出して台形補正し、縮小・メタデータ除去・サムネイル生成を行う
- files: Bookshelf/Imaging/CoverDetector.swift, Bookshelf/Imaging/CoverProcessor.swift, BookshelfTests/CoverProcessorTests.swift, BookshelfTests/Fixtures/（表紙を斜めから撮った画像3枚以上。合成画像）, scripts/generate-cover-fixtures.py（フィクスチャ生成）
- acceptance: テスト実行で CoverProcessorTests が通る — ①フィクスチャ画像で四隅が検出され出力が矩形になる ②出力の長辺が1600px以下 ③サムネイルが生成される ④出力画像に位置情報（GPS）等のEXIFが含まれない（CGImageSourceで確認）⑤四隅が検出できない画像では元画像を返し「検出失敗」を示す
- depends: T1
- skills: なし

## T4: 端末内OCRによる題名候補と精度の実測
- goal: 表紙画像から題名候補を非同期に抽出し、オーナーの蔵書サンプルで精度を実測する（business-plan 検証方法1）
- files: Bookshelf/Imaging/TitleRecognizer.swift, BookshelfTests/TitleRecognizerTests.swift, BookshelfTests/OCRAccuracyTests.swift（実写での精度実測。実写ファイルが無いときはスキップ）, BookshelfTests/Fixtures/ocr-*.png（スクリプトで生成した架空の表紙。フォルダ同期グループがテストバンドルへ平らにコピーするため、サブフォルダにせず `ocr-` を接頭辞にする）, scripts/generate-ocr-fixtures.py（または scripts/generate-cover-fixtures.py を拡張）, .dev/ocr-accuracy.md
- data（git 管理外・.gitignore 済み。files ではない）: design/sample-covers/manifest.json（切り抜き済み23枚の正解題名）, design/sample-covers/raw/（未加工の実写25枚）, design/sample-covers/raw-titles.json（raw の正解題名。builder が写真を読んで下書きし、オーナーが確認して確定する）
- acceptance: テスト実行で TitleRecognizerTests が通る — ①合成フィクスチャの横書き英語・横書き日本語で正解題名を候補に含む ②認識失敗時は空の候補を返しエラーにしない / 実写ファイル（manifest.json・raw-titles.json）が無い環境（CI・クリーンなチェックアウト）では OCRAccuracyTests がスキップされ、テスト全体が通る / 実写での実測結果が .dev/ocr-accuracy.md に表で記録されている — 全体・縦書き・装飾書体・帯ありの各カテゴリについてサンプル数と正解数・正解率（切り抜き23枚と raw 25枚を分けて記載）。表紙画像は含めず、本の題名も載せない（サンプルは番号で示す）/ サンプル数が5未満のカテゴリはその旨を ocr-accuracy.md に記録し、オーナーに追加撮影を依頼するよう報告する / 表紙画像・正解題名のファイルが git の追跡対象に入っていない（`git status --ignored` で ignored と表示される）
- depends: T3
- skills: なし

## T5: 撮影登録フロー（自作カメラ・連続撮影・登録待ちの一覧）
- goal: アプリ内カメラで表紙を連続撮影し、登録待ちの一覧で題名・ジャンル・購入済みチェックを確認して登録できるようにする。入口は下部バーの＋と棚の末尾の空き枠（F1-6。2026-11-10 更新）
- files: Bookshelf/Capture/CameraController.swift, Bookshelf/Capture/CaptureView.swift（撮影ガイドを含む）, Bookshelf/Capture/CaptureViewModel.swift, Bookshelf/Capture/PendingListView.swift, Bookshelf/Capture/CornerAdjustView.swift（N画面: 手動の四隅調整）, Bookshelf/Capture/FakeCameraSource.swift（シミュレータ・UIテスト用）, Bookshelf/Imaging/CoverDetector.swift（検出の改善）, BookshelfTests/CoverDetectionAccuracyTests.swift（実写での検出率の実測。実写ファイルが無いときはスキップ）, BookshelfUITests/CaptureFlowUITests.swift
- acceptance: UIテスト実行で CaptureFlowUITests が通る — ①FakeCameraSource で3冊を連続撮影し、カメラを閉じずに登録待ちの一覧に3冊並ぶ ②一覧の初期状態は全冊が購入済みにチェックされ、「すべて解除」で全冊が外れ、1冊だけチェックを外して登録するとその本は買いたい本に、残りは選んだジャンルに購入日=今日で並ぶ ③題名が空の本があると登録ボタンが押せない ④棚の末尾の空き枠から始めると、その棚が登録先になる ⑤直前に使った棚が買いたい本のときは、それ以外で直前に使った棚が初期値になる ⑥登録待ちが30冊になると撮影ボタンが押せなくなり上限の案内が出る。ライブラリの選択は残りの冊数までに制限される（F1-8。2026-11-11 追加）⑦カメラ画面に撮影ガイド（表紙を枠いっぱいに入れる・背景と分ける旨の枠と文言）が表示される ⑧四隅の検出に失敗した本は N 画面で、画像の内側（各辺から約10%内側）に初期の四隅が置かれ、四隅のハンドルをドラッグして「確定」すると補正済みの表紙が登録待ちの一覧に入る（2026-11-11 追加） / 表紙検出の改善（F1-2。T3 レビューより。2026-11-11 追加）: `VNDetectDocumentSegmentationRequest` を `VNDetectRectanglesRequest` と併用し閾値を再調整したうえで、design/sample-covers/raw の実写25枚（git 管理外）で CoverDetectionAccuracyTests を実行し、自動検出の成功（表紙の四隅を正しく取れた枚数。表紙の内側の枠など表紙以外を取ったものは失敗に数える。正誤は builder が出力画像を目視確認）が現状 7/25 から **15/25 以上** になったことを build-log に枚数で記録する（実写ファイルが無い環境ではテストはスキップされテスト全体が通る。15/25 に届かない場合は到達枚数と原因の見立てを記録してオーナーに報告し、判断を仰ぐ）/ T3 の合成フィクスチャでの CoverProcessorTests が引き続き通る / 連続撮影中は1つの CIContext を使い回し、1枚ごとに作り直さない（コードレビューで確認）/ 実機（iPhone 13相当）で撮影ボタン押下から次の撮影可能までの時間を計測し1秒以内であることを build-log に記録 / 見た目・演出が Figma の A・B・C 行と一致 / 見た目・文言・画面構成が .dev/design-brief.md と Figma の詳細デザイン（A・C・N 行）に一致
- depends: T2, T3
- skills: figma:figma-swiftui

## T6: 閲覧画面（棚表示・グリッド表示・詳細）
- goal: ジャンルごとの棚を表紙の縦横比のまま表示し（棚表示＝横スワイプで本・縦スワイプで棚、グリッド表示＝縦スクロール・左右スワイプで棚）、閲覧画面の配置（上: 棚の名前▾と冊数・右上の共有マーク、下部バー: 表示・検索欄・＋）と詳細ページを実装する（F6・F6-8。2026-11-10 更新）
- files: Bookshelf/Shelf/ShelfCollectionView.swift, Bookshelf/Shelf/ShelfCell.swift, Bookshelf/Shelf/ShelfScreen.swift, Bookshelf/Shelf/ShelfGridView.swift, Bookshelf/Shelf/ShelfPickerSheet.swift, Bookshelf/Shelf/DisplayMenu.swift, Bookshelf/Detail/BookDetailView.swift, BookshelfUITests/ShelfUITests.swift
- acceptance: UIテスト実行で ShelfUITests が通る — ①縦スワイプの対象は本が1冊以上ある棚だけで、買いたい本は0冊でも出し（0冊のときは案内文）、「買いたい」の本しかないジャンルは出ない ②棚の名前をタップすると分類見出し・冊数付きの「棚を選ぶ」リストが開き、選んだ棚に移る ③「表示」メニューでグリッドに切り替わり、グリッドで左右スワイプすると棚が変わる ④本のタップで詳細に表紙・題名・ジャンル・所持状況が出て、購入日は購入済みの本だけに出て、データ追加日は出ない ⑤VoiceOverラベルが題名になる（N5）/ 見た目が Figma の閲覧ページ・G・I 行・E-1・E-2 と一致 / 見た目・文言・画面構成が .dev/design-brief.md と Figma の詳細デザイン（基本・G・I・M・P 行）に一致
- depends: T2
- skills: figma:figma-swiftui, designagent:design-to-code

## T7: 並べ替え・棚間移動・削除・一括整列
- goal: 長押し＋横スワイプでの並べ替え、上スワイプで移動先の棚を選ぶリスト、下スワイプでの削除確認、グリッドの長押しメニュー、一括整列（手動・購入日・データ追加日・題名＝よみ順）を実装する（F5・F6-4。2026-11-10 更新）
- files: Bookshelf/Shelf/ShelfReorderHandler.swift, Bookshelf/Model/ShelfOrdering.swift, BookshelfTests/ShelfOrderingTests.swift, BookshelfUITests/ReorderUITests.swift
- acceptance: テスト実行で ShelfOrderingTests（1冊の移動・棚間移動・購入日の新しい順/古い順・データ追加日の新しい順/古い順・題名順はよみで並ぶ）が通る / ReorderUITests で ①長押し＋横スワイプで位置が変わりアプリ再起動後も保持される ②長押し＋上スワイプで「移動先の棚を選ぶ」リスト（0冊のジャンルも出る）から別の棚へ移り「取り消す」で戻る ③長押し＋下スワイプで確認ダイアログが出て、削除で本が消える / 並べ替えの動きが Figma の D・H 行と一致 / 見た目・文言・画面構成が .dev/design-brief.md と Figma の詳細デザイン（D・H 行）に一致
- depends: T6
- skills: figma:figma-swiftui

## T8: ジャンルの管理
- goal: 設定画面からジャンルの追加（区分を選ぶ）・名前変更・削除・並び順変更を行えるようにする（F4。2026-11-10 更新）
- files: Bookshelf/Settings/SettingsView.swift, Bookshelf/Shelf/ShelfListView.swift, Bookshelf/Shelf/ShelfEditView.swift, BookshelfUITests/ShelfManagementUITests.swift
- acceptance: UIテスト実行で ShelfManagementUITests が通る — 「表示」メニュー →「設定」→ ジャンル管理で、区分を選んでジャンルを作成→名前変更→並び順変更→削除し、削除したジャンルの本が未分類に表示される。買いたい本と未分類には削除・名前変更の操作が出ない / 見た目が Figma の F 行と一致 / 見た目・文言・画面構成が .dev/design-brief.md と Figma の詳細デザイン（F 行）に一致
- depends: T6
- skills: figma:figma-swiftui

## T9: 本の編集・購入した・写真ライブラリからの登録
- goal: 詳細ページの「編集」で題名（OCR候補の採用・修正）・ジャンル・所持状況（購入済み｜買いたい）・購入日・表紙の撮り直しを編集でき、買いたい本の「購入した」と写真ピッカーからの登録を実装する（F6-4・§10.3。2026-11-10 更新）
- files: Bookshelf/Detail/BookEditView.swift, Bookshelf/Detail/PurchaseAction.swift, Bookshelf/Capture/PhotoImportHandler.swift, BookshelfTests/PhotoImportTests.swift, BookshelfUITests/BookEditUITests.swift
- acceptance: テスト実行で PhotoImportTests（写真ライブラリから登録した本のデータ追加日は登録日時、購入済みなら購入日の初期値はその日付）が通る / BookEditUITests で ①OCR候補を採用→題名を修正→ジャンル変更→保存 ②所持状況を「買いたい」にすると購入日の行が入力できなくなり、「購入済み」に戻すと今日の日付が入る（編集画面の項目と並びは所持状況で変わらない）③買いたい本の詳細で「購入した」を押すとそのジャンルの棚に並び購入日が今日になり、通知の「取り消す」で元に戻る ④「キャンセル」で変更が破棄される / Info.plist に写真ライブラリ読み取り権限の用途説明が無い（S4）/ 見た目が Figma の E 行と一致 / 見た目・文言・画面構成が .dev/design-brief.md と Figma の詳細デザイン（E 行・C-1）に一致
- depends: T4, T6
- skills: figma:figma-swiftui

## T10: 検索（題名・よみ）
- goal: 下部バーの検索欄から、全ジャンルの購入済みの本を題名とよみの部分一致で検索できるようにする（F7。2026-11-10 更新）
- files: Bookshelf/Search/SearchView.swift, Bookshelf/Model/LibraryStore.swift（検索クエリ追加）, BookshelfTests/SearchTests.swift
- acceptance: テスト実行で SearchTests が通る — ①題名の部分一致 ②よみの部分一致（「じかん」で「存在と時間」が見つかる）③ひらがな・カタカナ、英字の大文字・小文字を区別しない ④「買いたい」の本は結果に含まれない / 0件時に「題名やよみの一部だけでも検索できます」の案内が出る（UIテストまたはスクリーンショットで確認）/ 見た目が Figma の E-4・E-5 と一致 / 見た目・文言・画面構成が .dev/design-brief.md と Figma の詳細デザイン（E-4・E-5）に一致
- depends: T2
- skills: figma:figma-swiftui

## T11: 共有（ジャンル別・月別・日別）
- goal: 右上の共有マークから、ジャンル別（その棚）・購入月別（この日／この月／この年）の購入済みの本で画像を端末上で生成し、Instagram フィード（4:5）・Instagram ストーリーズ（9:16）・X（4:5）・写真に保存（4:5）へ渡す（F8。2026-11-10 更新）
- files: Bookshelf/Share/ShareFlowView.swift, Bookshelf/Share/ShareTemplateView.swift, Bookshelf/Share/ShareRenderer.swift, Bookshelf/Share/InstagramStoriesSharer.swift, BookshelfTests/ShareRendererTests.swift, BookshelfUITests/ShareFlowUITests.swift
- acceptance: テスト実行で ShareRendererTests が通る — ①ジャンル30冊・日3冊・月9冊それぞれで 1080×1350 と 1080×1920 の画像が生成される ②「買いたい」の本が含まれない ③アプリ名が入る ④EXIFの位置情報が無い ⑤生成時間が3秒以内 / ShareFlowUITests で共有マーク→（購入月別では範囲の選択）→共有先の選択→プレビューまで進める / 写真への保存で「追加のみ」権限が要求される / 実機でストーリーズ・フィード・X への受け渡しを手動確認し build-log に記録（ストーリーズは Meta の App ID が必要。オーナーが Meta 開発者登録をして ID を用意する）/ 見た目が Figma の K 行と、S1 で確定する共有画像のデザインと一致 / 見た目・文言・画面構成が .dev/design-brief.md と Figma の詳細デザイン（K 行・共有画像の行）に一致
- depends: T6, T13
- skills: figma:figma-swiftui

## T13: 購入月別モード
- goal: 「表示」メニューのまとめ方で購入月別に切り替え、その月の購入済みの本を横に並べて縦スワイプで月を移動し、ピンチインで年・ピンチアウトで月に切り替える（F6-7。2026-11-10 追加）
- files: Bookshelf/Month/MonthBrowseView.swift, Bookshelf/Month/MonthGridView.swift, Bookshelf/Model/MonthGrouping.swift, BookshelfTests/MonthGroupingTests.swift, BookshelfUITests/MonthModeUITests.swift
- acceptance: テスト実行で MonthGroupingTests が通る — ①購入日で月ごと・年ごとにまとまり、中の並びは購入日の古い順（1日→31日）②本のない月・年は含まれない ③「買いたい」の本は含まれない / MonthModeUITests で「表示」→「購入月別」に切り替わり、上部の月の名前に「▾」が無く、「表示」メニューに「並べ順」が出ない。ピンチインで年、ピンチアウトで月に戻る / 見た目が Figma の J 行と一致 / 見た目・文言・画面構成が .dev/design-brief.md と Figma の詳細デザイン（J 行）に一致
- depends: T6
- skills: figma:figma-swiftui

## T14: 初回チュートリアル
- goal: 初めて起動したとき、チュートリアルで最初の1冊の登録まで案内し、登録を必須にする（F1-7。2026-11-10 追加）
- files: Bookshelf/Onboarding/OnboardingView.swift, Bookshelf/Onboarding/OnboardingState.swift, BookshelfUITests/OnboardingUITests.swift
- acceptance: UIテスト実行で OnboardingUITests が通る — ①初回起動でチュートリアルが表示され、1冊の登録が終わるまで閲覧画面に進めない ②登録後は閲覧画面に1冊並ぶ ③2回目以降の起動ではチュートリアルが出ない / 見た目が Figma のチュートリアルのフレーム（デザインのタスク D1）と一致 / 見た目・文言・画面構成が .dev/design-brief.md と Figma の詳細デザイン（L・O 行）に一致
- depends: T5
- skills: figma:figma-swiftui

## T15: 日英ローカライズ
- goal: UI文言・初期ジャンル名・区分名・システム棚名・日付表記を日本語と英語に対応させる（N7。2026-11-10 追加）
- files: Bookshelf/Localizable.xcstrings, Bookshelf/Model/InitialGenres.swift（en 名）, BookshelfUITests/LocalizationUITests.swift
- acceptance: Localizable.xcstrings の en に未翻訳の文字列が0件（`xcodebuild -exportLocalizations` の結果で確認）/ LocalizationUITests を英語ロケールで実行し、閲覧・登録・詳細・設定・共有の各画面に日本語が残っていない / 日付が端末のロケールの表記で出る / 英語の長い文言・最大の文字サイズで主要画面が崩れないことをスクリーンショットで確認し build-log に記録 / 見た目・文言・画面構成が .dev/design-brief.md と Figma の詳細デザイン（Q 行）に一致
- depends: T6
- skills: なし

## T12: 性能・アクセシビリティ・オフラインの確認
- goal: 500冊のデータで非機能要件 N1〜N5 を満たすことを計測し、必要な改善を行う
- files: Bookshelf/Debug/SeedData.swift（デバッグビルドのみ）, BookshelfUITests/PerformanceTests.swift, .dev/perf-report.md
- acceptance: PerformanceTests（XCTApplicationLaunchMetric、スクロールのXCTOSSignpostMetric）を500冊シードで実行し、結果が .dev/perf-report.md に記録され、コールドスタートから棚表示1秒以内・共有画像3秒以内・500冊のデータ容量300MB以下を満たす / 機内モードの実機で全機能の手動確認チェックリストが perf-report.md に記録されている / `scripts/check-no-network.sh` が終了コード0
- depends: T5, T7, T8, T9, T10, T11, T13, T14, T15
- skills: なし

## 実施順（requirements.md §8 の優先度より。2026-11-10 更新）
1. T1 → T2 → T3 → **T4（OCR精度の実測を早期に）**
2. オーナーが Figma で詳細デザインを作成（UI タスクの前提。T1〜T4 と並行可。design/mock-todo.md の S1・D1〜D8） → 2026-11-11 ほぼ完了（D8 の棚板の表現だけ未検討。T6 で詰める）。仕様は .dev/design-brief.md
3. T6 → T5 → T14（撮影→棚に並ぶ一連の流れと初回体験を最初に通す）
4. T7 → T9 → T13 → T8 → T10 → T11
5. T15 → T12 → dev-security（リリース前監査）→ dev-docs
