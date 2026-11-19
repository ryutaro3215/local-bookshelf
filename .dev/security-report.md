# Security report — local-bookshelf（iOS アプリ）

## 監査 (2026-11-18) — NO-GO
- 対象: main f59e349（T1〜T15 すべてレビュー PASS 後）。Release 構成のビルド（`xcodebuild build -configuration Release -destination "generic/platform=iOS Simulator"` → BUILD SUCCEEDED）とソース全体
- findings:
  - [high] Bookshelf/Storage/ImageStore.swift:31-32 ほか（entitlements ファイルが無い） requirements S5「OS のデータ保護を有効にし、端末ロック中はデータを読めない状態にする」が実装されていない。プロジェクトに .entitlements（`com.apple.developer.default-data-protection`）が無く、表紙の書き込みは `write(to:options: .atomic)` だけで、SwiftData のストアも既定のまま。iOS の既定の保護クラスは `NSFileProtectionCompleteUntilFirstUserAuthentication` で、**起動後に一度ロックを解除すれば、その後ロック中でも読める**。影響: 端末を盗まれた・ロック中に解析された場合に、表紙の写真・題名・購入日が読める（データの機微性は低いが、要件で明示した保護に届いていない）。推奨修正（dev-builder）: Data Protection の capability を足し、entitlements に `com.apple.developer.default-data-protection` = `NSFileProtectionComplete` を入れて `CODE_SIGN_ENTITLEMENTS` に設定する（アプリのコンテナで新しく作るファイル全部に効く）。あわせて ImageStore の書き込みに `.completeFileProtection` を付ける（既存のファイルは保護クラスが変わらないので、移行が要るかを決める）。バックグラウンドでファイルに触る処理は無いので、Complete にしても動作への影響は無い見込み。実機でロック中に読めないことを確かめる（シミュレータはデータ保護を強制しない）。要件の方を緩める（UntilFirstUserAuthentication で良しとする）なら、オーナー判断で dev-architect が S5 を直す
  - [medium] プロジェクトに PrivacyInfo.xcprivacy（プライバシーマニフェスト）が無い。UserDefaults（BookshelfApp.swift:55-56、Onboarding/OnboardingState.swift:14、Capture/CaptureViewModel.swift:74、RecentShelves）は Apple の「理由の申告が必要な API」（NSPrivacyAccessedAPICategoryUserDefaults）に当たる。影響: App Store Connect への提出で警告・却下（ITMS-91053）になる。脆弱性ではないが**提出前に必須**。推奨修正: Bookshelf/PrivacyInfo.xcprivacy を足し、NSPrivacyTracking=false、NSPrivacyCollectedDataTypes=空、NSPrivacyAccessedAPITypes に UserDefaults（理由 CA92.1: アプリ自身だけが読み書きする）を入れる。ファイルの日付・空き容量などほかの対象 API は、ソースの grep では使っていない（Debug/SeedData.swift のファイルサイズの取得はデバッグのみ）
  - [low] Bookshelf/BookshelfApp.swift:53-70 起動引数 `-UITestReset` の分岐が `#if DEBUG` の外にあり、Release でも有効。この引数で起動すると、メモリ上の空のデータ・一時フォルダで開く（実データは消さない・読まない）。App Store の配布版に利用者が起動引数を渡す手段は無いので実害は無いが、ほかの UI テスト用の分岐（-UITestPersistentStore・-SeedBooks・-FakeCamera）と同じく `#if DEBUG` で囲むことを推奨
  - [low] Bookshelf/Share/InstagramStoriesSharer.swift:57-59 ストーリーズに渡す画像をペーストボードに置くとき `.localOnly` を付けていない。ユニバーサルクリップボードが有効だと、5分の期限の間、同じ Apple ID のほかの端末にも共有画像が届きうる（利用者が共有しようとしている画像で、機微性は低い）。`options: [.expirationDate: …, .localOnly: true]` を推奨（Meta の受け渡しは同じ端末の中なので影響しない）
  - [low] ログ（os.Logger）で `error.localizedDescription` を `privacy: .public` で出している所が約28か所ある（Capture・Detail・Shelf ほか）。題名・棚の名前などの利用者のデータは出しておらず、出るのはエラーの文と表紙の UUID・書体名。端末のログは利用者が sysdiagnose を送らない限り外に出ないので、このままでよい。エラーの文にファイルのパスが含まれる場合がある点だけ記録する
- チェックリスト実施結果（Web 向けの項目は iOS に読み替えた）:
  - 秘密情報: `git log -p --all | grep -iE "api[_-]?key|secret|password|passwd|token|BEGIN … PRIVATE"` → 該当は CFStringTokenizer の「token」と、テスト用のクラス名 FixtureBundleToken だけで、秘密情報なし。`grep -rniE "api[_-]?key|secret|password|bearer|private[_-]?key" Bookshelf BookshelfTests BookshelfUITests scripts Bookshelf.xcodeproj/project.xcproj` → 0件。`.env` は無く、使う設計でもない（S3: 秘密情報が存在しない）。Meta の App ID は Info.plist の `MetaAppID`（秘密ではない公開の ID）から読む設計で、まだ値は無い
  - 外部通信（S1）: `scripts/check-no-network.sh` → OK。`grep URLSession|NWConnection|CFNetwork|WKWebView|SFSafari|http(s)://` → 0件。URL を開くのは設定アプリ（`openSettingsURLString`）と `instagram-stories://share`（App ID は数字だけに検証・URLComponents で組み立て）の2か所で、通信ではない。Release のバイナリの「http」は plist の DTD の文字列だけ。ATS の例外設定なし
  - 入力の検証（S6）: 題名・棚の名前は LibraryStore.sanitize（制御文字の除去・前後の空白・200文字）を、追加・編集・名前の変更のすべての経路で通している（LibraryStore.swift:165・211・282・319）。外部由来の画像は CoverProcessor で再エンコードしてから保存し、元の EXIF・GPS を写さない（CoverProcessorTests の GPS 入りの写真のテストと、ShareRendererTests ④で確認済み）
  - SQL インジェクション: SwiftData の FetchDescriptor・#Predicate だけで、文字列でクエリを組み立てる所は無い
  - XSS: Web ビューが無いので対象外
  - パストラバーサル: ファイル名は UUID だけから作る（ImageStore.originalURL・thumbnailURL）。利用者の入力をパスに使う所は無い
  - 認証・認可: アカウント・ログインが無い設計（S2）なので対象外
  - 権限（S4）: Info.plist（Release）の用途説明は NSCameraUsageDescription と NSPhotoLibraryAddUsageDescription の2つだけ。写真への保存は `.addOnly` の許可だけを求め（ShareFlowUITests で確認済み）、ライブラリの読み取りはシステムの写真ピッカーで行う
  - 依存の既知の脆弱性: サードパーティの依存が無い（project.xcproj に Swift Package の参照なし、swiftpm/configuration は空）ので、npm audit などに当たる確認は対象外。同梱物は Noto Sans JP・Noto Serif JP（SIL OFL）だけ
  - デバッグ設定: Release のバイナリに `SeedPerf`・`PerfProbe`・`SeedBooks`・`FakeCamera`・`UITestPersistentStore`・`UITestOnboarding`・開発機のパス（/Users/…）・`sample-covers` の文字列が無いことを `strings` で確認（`#if DEBUG` で外れている）。`-UITestReset` だけは Release に残る（上の low）。Swift の短い文字列はバイナリに埋め込まれ `strings` に出ないことがあるため、これはソースで確認した
  - CORS: サーバーが無いので対象外
  - バックアップ（N4）: `isExcludedFromBackup` の指定は無く、データは端末のバックアップに含まれる
  - データ保護（S5）: 上の high
- GO にするための条件: 上の [high]（データ保護）を直して実機で確かめる、またはオーナー判断で S5 を緩めて requirements を直す。[medium] のプライバシーマニフェストは App Store の提出前に必須なので、同じ修正で入れることを推奨

## 監査 (2026-11-18 再監査) — GO
- 対象: main f59e349 ＋ 未コミットの修正（Bookshelf.entitlements・Bookshelf/PrivacyInfo.xcprivacy・Bookshelf/Storage/ImageStore.swift・project.xcproj の CODE_SIGN_ENTITLEMENTS）。build-log「セキュリティ監査の修正」
- 前回の findings の扱い:
  - [high] データ保護（S5）: **解消（実装）**。`Bookshelf.entitlements` に `com.apple.developer.default-data-protection` = `NSFileProtectionComplete`、アプリのターゲットの `CODE_SIGN_ENTITLEMENTS` に設定。Release ビルドの処理済み entitlements（Bookshelf.app-Simulated.xcent）に入っていることを自分のビルドで確認。アプリのファイルの書き込みは ImageStore の2か所だけ（`grep "\.write(to:|createFile(|FileHandle(forWriting"`）で、どちらも `.completeFileProtection` 付き。SwiftData のストアと UserDefaults は entitlements の既定の保護に従う。entitlements はアプリの中にリソースとして入っていない
  - [medium] プライバシーマニフェスト: **解消**。アプリの中に PrivacyInfo.xcprivacy があり、NSPrivacyTracking=false・追跡ドメインなし・収集データなし・UserDefaults（CA92.1）。UserDefaults の使い道（最近使った棚・チュートリアルを終えたか。CaptureViewModel.swift:79-88・OnboardingState.swift:19-24）はアプリ自身だけの読み書きで、CA92.1 に合う。ソースで使っているほかの「理由の申告が必要な API」は見つからない
  - [low] 3件（Release の `-UITestReset`、ペーストボードの `.localOnly`、ログの `error.localizedDescription`）: 未対応のまま（オーナー指示の範囲外）。前回の評価のとおり実害は無い
- findings:
  - [medium] データ保護の実機での確認が済んでいない（docs/notices.md N-094）。シミュレータはデータ保護を強制せず、ファイルの保護クラスも返さない（builder の一時テストで nil を確認）ため、設定がビルドに入ったことまでしか確かめられない。App Store に出す前に、実機で `attributesOfItem[.protectionKey]` が `NSFileProtectionComplete` になること、ロック中・ロック解除後の動作に問題が無いことを確かめる。実装は入っているので GO の妨げにはしないが、確認の結果を次の監査で記録する
  - [low] Bookshelf/BookshelfApp.swift:53-70 Release に残る `-UITestReset`（前回と同じ）
  - [low] Bookshelf/Share/InstagramStoriesSharer.swift:57-59 ペーストボードの `.localOnly` なし（前回と同じ）
  - [low] ログの `privacy: .public` の `error.localizedDescription`（前回と同じ。利用者のデータは出していない）
- チェックリスト実施結果:
  - 秘密情報: 新しいファイル（entitlements・xcprivacy）に `api[_-]?key|secret|password|token` 0件。前回の git 履歴・ソースの全文検索の結果から変わった所はこの修正だけ
  - 外部通信: `scripts/check-no-network.sh` → OK、終了コード0（xcprivacy は DTD の URL の行を持たない）
  - 構成: `plutil -lint Bookshelf.entitlements Bookshelf/PrivacyInfo.xcprivacy` → OK。Release ビルド BUILD SUCCEEDED
  - テスト: builder の全テスト（ユニット87・UI 64 通過）をログで確認。今回の差分は書き込みのオプションと署名の設定だけで、動作に関わるコードの変更は ImageStore の2行だけ
  - そのほかの項目（入力の検証・SQL・XSS・パストラバーサル・認証・依存・デバッグ設定・CORS・バックアップ）は前回の監査から変わっていない（今回の差分はそれらに触れていない）

### 追記 (2026-11-19) — 実機でのデータ保護の確認
- N-094: オーナーが実機で確認し、問題なし（保護クラスは Complete。docs/device-checklist.md §9 の手順）。再監査の [medium] は解消
