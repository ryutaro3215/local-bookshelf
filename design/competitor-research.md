# 競合調査（海外中心・日英対応の観点）— local-bookshelf（仮称）

> 作成: 2026-11-10 / 対象: iOS の蔵書管理・本棚表示アプリ
> 既存資料 `.dev/competitor-research.md`（2026-11-09、ユーザー提供メモ・未検証）と `.dev/business-plan.md` の競合欄を補完・検証するもの。
> 数値（評価・価格）は 2026-11-10 時点で App Store ページなどから取得した値。**価格は国・時期で変わる**。App Store の更新日の多くは年の表示がない。

---

## 1. 調査概要

| 項目 | 内容 |
| :-- | :-- |
| 調査日 | 2026-11-10 |
| 方法 | Web 検索と App Store 公式ページ（US / JP）の取得。一部は第三者サイト（mwm.ai、レビュー記事）で補った。第三者情報はその旨を明記した |
| 範囲 | ①海外（英語圏・グローバル）の蔵書管理／本棚表示アプリ ②国内の主要読書管理アプリ（簡易） ③日英対応にかかわる技術・ASO の論点 |
| 重点 | 表紙・棚の見せ方（ビジュアル）、写真での登録、オフライン／プライバシー、アカウント要否 |
| 限界 | 実機では触っていない。表示形式は掲載文・スクリーンショットの説明に基づく。プライバシーラベルは開発者の自己申告（Apple は検証していない） |

---

## 2. 結論サマリー

- **「自分で撮った表紙写真がそのまま書影になり、カバーフローの棚に並ぶ」アプリは、今回の調査では見つからなかった**（ただし網羅的ではない）。いちばん近いのは **Shelfy**（表紙写真で登録でき、斜め撮りを補正する。3D の背表紙棚）と **Shelfieline**（日本人開発者。棚を横スワイプで切り替えるカルーセル。リアルな背表紙棚）。どちらも書誌の照会（検索・ISBN・外部 API）が前提で、表紙を正面に向けて並べる「面陳」型でもない。
- **2025〜26 年に「プライバシー重視・オフライン・登録不要」を掲げる個人開発の読書トラッカーが急に増えた**（PageFlow、Leafed、ShelfLog、Bookrise、Pinakes など）。「通信ゼロ・登録不要」だけでは差別化にならない。これは既存メモの所感と同じで、今回裏付けが取れた。
- **ビジュアル棚の競合は課金が重い。** Shelfy は週 $4.99〜生涯 $99.99、Bookshelf (SquidBit) は年 $19.99〜生涯 $79.99。買い切り 600 円は「安く、しかも課金で迷わせない」位置に置ける。
- **ISBN・バーコード型の定番アプリは表紙の見せ方が弱い**（Libib はアプリ版で表紙一覧が弱いと不満が出ている。CLZ・BookBuddy はリストや表紙グリッド止まり）。一方、書誌を自動で取れるので「検索・並べ替え・著者で整理」は強い。local-bookshelf の弱みはここ。
- **海外の大手 SNS 型（Goodreads・StoryGraph）は英語のみ**で、アカウント前提・データ収集が多い。日本語 UI を持つ海外アプリは BookBuddy・Book Tracker・Bookshelf (SquidBit)・ShelfSnap などに限られる。
- **日本語の縦書き OCR は Vision の弱点。** Apple の DTS エンジニアは「画像を回転・再配置してから認識する」「新 API `RecognizeTextRequest` の orientation を使う」と回答しており、標準設定で縦書きを読める保証はない。日本語の表紙（縦書きの題名が多い）での精度検証を、日英対応の最優先リスクとして扱う。
- **日英対応で設計が変わる点は 3 つ。** ①題名の並べ替え（漢字は読みがないと五十音順にできない）②初期 28 ジャンルの英訳（書店の売り場区分は日米で違う）③ASO（日本ストアでは英語(米国)のキーワードも索引されるとする資料が多い）。

---

## 3. 海外競合一覧

凡例: ◯=あり ／ △=一部・条件付き ／ ×=なし ／ ?=未確認

| アプリ（開発者） | コンセプト | 登録方法 | 表示 | アカウント／オフライン | 価格（US） | 日本語 UI | 評価（US） |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| **Shelfy: Book Tracker & TBR**（O. Murakhovskyi） | 居心地のよい 3D 本棚＋読書記録 | 検索・バーコード・**表紙写真**・スクショ読取・Goodreads/StoryGraph 取込 | **3D 背表紙棚**（本の回転・傾け、棚の装飾） | iCloud 同期。要否は? | 無料＋課金（週 $4.99、月 $9.99〜14.99、年 $38.99、生涯 $99.99、背表紙パック） | × | 4.6（1.4K） |
| **Shelfieline**（Takayuki Hamuro） | リアルなデジタル本棚 | ISBN バーコード（連続）・手入力・Safari から表紙共有 | **リアル背表紙棚**／表紙グリッド。棚を横スワイプで切り替えるカルーセル | アカウント不要・端末保存・iCloud なし。ただし openBD・NDL・Open Library を照会 | 無料（3 棚・30 冊まで）＋Pro 買い切り ¥980 | ?（2 ロケール。言語名は未確認） | 評価なし（2026-05 公開） |
| **Bookshelf: Book Tracker & List**（SquidBit） | 仮想ライブラリ＋読書トラッカー | ISBN バーコード（一括）・検索・手入力・CSV/Goodreads 取込 | グリッド・カスタム棚 | 開発者サーバーに保存・アカウント連携。広告目的の追跡ラベルあり | 無料＋Pro（月 $2.99、年 $19.99、生涯 $59.99/$79.99） | ◯（24 言語） | 4.8（3.1K） |
| **BookBuddy**（Kimico） | 蔵書カタログ（二重買い防止・ウィッシュリスト） | バーコード（BT スキャナ可）・ISBN・検索・手入力・CSV | リスト／グリッド（表紙サイズ小・中・大） | 端末保存を明言。iCloud/Dropbox 同期 | 無料（50 冊まで）＋Pro 生涯 $9.99、共有は月 $1.99〜 | ◯ | 4.8（16K） |
| **Libib**（Libib, Inc.） | クラウド型カタログ（個人〜学校図書館） | バーコード・手入力（表紙画像アップロード可） | リスト中心（アプリの表紙表示に不満の声） | Web アカウントと連携（SSO あり） | アプリ無料。Pro は Web で月 $9／年 $99 | △（リリースノートに日本語訳の記載あり） | 4.4（1.2K） |
| **CLZ Books**（Collectorz.com） | コレクター向け書籍 DB | ISBN バーコード・ISBN の OCR・著者/題名検索 | リスト／カード／Cover Wall | CLZ Cloud（同期・共有）。追跡ラベルあり | サブスク 月 $1.99／年 $19.99 | × | 4.8（2.7K） |
| **Book Tracker**（Simone Montalto） | 個人開発の読書・蔵書トラッカー | バーコード・検索・手入力・他サービス取込 | 表紙＋詳細、統計・ウィジェット | **データ収集なし** | 無料（5 冊まで）＋Pro 買い切り（US $19.99／JP ¥1,400） | ◯ | JP 4.7（58） |
| **PageFlow**（Robert Clegg） | 脱ソーシャル・ストリークなしの読書ログ | 追加＋スキャン（方式は未記載）・CSV/Goodreads 取込 | ライブラリのグリッド、ウィジェット | 「No accounts」・**データ収集なし**。iOS 26 以上・iPhone のみ | 無料＋Lifetime $19.99 | ×（英・蘭・仏・独・伊・葡・西） | 3.3（7） |
| **Bookshelf: Tracker & Catalog**（Tien Do） | 自宅蔵書のカタログ | カメラ撮影（表紙画像）・ライブラリから選択（ISBN の有無は不明） | 不明（並べ替え・統計・タグ） | アカウント不要・iCloud 同期。広告関連のラベルあり | 無料＋生涯 $99.99 ほか | × | 5.0（1） |
| **Book Shelfie**（S. Bommakanti） | AI で表紙・背表紙を一括認識 | カメラで複数冊を AI 認識 | 不明 | オフライン可と記載。アカウント設定あり | 無料 | × | 評価なし |
| **ShelfSnap**（Hue Ha） | 本の識別（棚・背・表紙・ISBN） | 棚／背表紙／表紙／扉スキャン、ISBN | 不明 | 広告・追跡ラベルあり | 週 $4.99／年 $39.99 | ◯ | 5.0（5） |
| **Goodreads**（Amazon 傘下） | 最大手の読書 SNS | 表紙スキャン・題名/著者/ISBN 検索 | リスト中心 | アカウント前提。収集データが多く、広告あり | 無料 | × | 4.8（762K） |
| **StoryGraph** | 気分・統計重視の読書トラッカー（Goodreads の代替） | バーコード・Goodreads 取込・Kobo 同期 | リスト／統計 | アカウント前提 | 無料＋Plus 月 $4.99／年 $49.99 | × | 4.5（3.6K） |
| **Delicious Library**（Delicious Monster） | 木の棚に表紙が並ぶ Mac の元祖 | Amazon データ＋バーコード | 木の本棚 | — | **2024-11 に販売終了** | — | — |

その他（詳細は未検証）: Bookly（ゲーム化した読書習慣、Pro 年 $29.99〜34.99 と資料により差）、Basmo（読書統計・セッション、年 $39.99〜59.99 と資料により差）、Fable（読書会 SNS、Fable Plus あり、価格未確認）、Beanstack（図書館が運営する読書チャレンジ。個人の蔵書管理ではない）、Oku（iOS/Web。デザイン重視の「静かな本棚」。価格は第三者情報のみ）、Handy Library（表紙写真から照合・棚写真で約 20 冊認識・買い切り。Google Play の掲載のみ確認）。

---

## 4. 主要競合の詳細

### 4.1 Shelfy: Book Tracker & TBR — ビジュアル棚で最も近い競合
- **コンセプト:** 「Reading journal & Cozy shelf」。3D の背表紙棚を装飾して楽しむ。Books カテゴリ無料ランキング 61 位。
- **登録:** 検索・バーコード・表紙写真。v2.3.9 で「どの角度で撮っても補正する」機能と表紙の選択機能が入った。v2.2.1 では表紙やリストのスクリーンショットから題名を読む機能が入った。**写真を書影として使うのか、照会の手がかりにするだけなのかは掲載文からは判断できない（未確認）。**
- **表示:** 背表紙の 3D 棚。本を回したり傾けたりでき、棚は木目・壁・小物で飾れる。表紙を正面に向ける面陳やカバーフローの記載はない。
- **プライバシー:** iCloud 同期。「Data Not Linked to You」として分析目的の利用データを収集。広告なし。
- **課金:** 週・月・年のサブスク、生涯 $99.99、背表紙パック（10 本 $2.99）。課金がかなり重い。
- **言語:** 英語のみ。
- **local-bookshelf との違い:** 背表紙棚 vs 面陳カバーフロー／課金が重い vs 買い切り 600 円／英語のみ vs 日英対応／書誌照会あり vs 通信ゼロ。

### 4.2 Shelfieline — 国内開発者による「棚カルーセル」型
- **コンセプト:** 物理の本棚を再現する。背表紙の高さと質感（紙・布・革）を変え、棚材（Walnut・Ebony は無料、Oak など 4 種は Pro）を選べる。
- **登録:** ISBN バーコード（連続スキャン）で題名・著者・ページ数を自動入力。手入力もできる。表紙画像はカメラ・写真ライブラリ・Safari からの共有で入れる。**書誌は openBD・国立国会図書館サーチ・Open Library を照会する**と記載されている。一方、FAQ には「サードパーティからの自動取得なし」ともあり、記述が矛盾している（未確認）。
- **表示:** 「Study Carousel」で複数の棚を横に並べ、左右スワイプで切り替える（隣の棚が端からのぞく）。表紙グリッドにも切り替えられる。**local-bookshelf の「縦スワイプで棚を切り替え・横スワイプで本」とは軸が逆だが、発想は近い。**
- **プライバシー:** アカウントもメールも不要。端末保存のみで iCloud 同期はない。
- **課金:** 無料版は 3 棚・30 冊まで。Pro 買い切りは ¥980。
- **言語:** 2 ロケール（日英と推測されるが未確認）。
- **注記:** 出典は第三者サイト（mwm.ai）。App Store の原文での確認を推奨。2026-05-11 公開、評価はまだない。

### 4.3 Bookshelf: Book Tracker & List（SquidBit）
- 仮想の棚とタグで整理する。登録は ISBN の一括スキャン・検索・手入力・取込。OCR は「引用の取り込み」用で、本の登録用ではない。
- データは開発者のサーバーに保存され、アカウントに紐づく。プライバシーラベルには追跡用の識別子・広告データがある。
- 日本語を含む 24 言語に対応。4.8（3.1K）。生涯版の価格は、検索スニペットの $44.99/$59.99 と取得ページの $59.99/$79.99 で食い違う。後者を採用した。

### 4.4 BookBuddy（Kimico）
- 「二重買いの心配がなくなった」というレビューがあり、蔵書カタログの定番。バーコード（BT スキャナにも対応）・ISBN・検索・CSV で登録する。表示はリストか、小・中・大の表紙グリッド。
- 「端末に保存」を明言しており、iCloud/Dropbox 同期は任意。日本語を含む 10 言語。4.8（16K）で海外の個人蔵書アプリでは最大級の規模。Pro は生涯 $9.99 と安い（無料版は 50 冊まで）。
- **示唆:** 「蔵書を把握する」用途は BookBuddy が安価に満たしている。local-bookshelf は「眺める・作る楽しさ」で別の土俵に立つ必要がある。

### 4.5 Libib
- 個人から学校図書館まで使えるクラウド型カタログ。本以外（映画・ゲームなど）も扱う。アプリ版は表紙の見せ方が弱く、「Perfect, except for the covers」というレビューや、表紙グリッドへの切り替えを求める声が多い。
- Pro（月 $9／年 $99）はアプリ内では購入できず、Web で申し込む。

### 4.6 CLZ Books
- コレクター向け。ISBN の OCR は「98% の成功率を保証」とうたう。表示はリスト／カード／Cover Wall。サブスク（年 $19.99）。英語のみ。追跡ラベルあり。

### 4.7 Book Tracker（Simone Montalto）／PageFlow — 「データ収集なし」の個人開発
- どちらも App Store のプライバシーラベルは「データの収集なし」。Book Tracker は日本語に対応し、5 冊まで無料、買い切りは ¥1,400。PageFlow は iOS 26 以上・iPhone のみで、Lifetime は $19.99。日本語には非対応。
- 既存メモの PageFlow 情報（「無料枠は同時進行 5 冊まで」）は今回の掲載文では確認できなかった。代わりに確認できたのは「Lifetime $19.99」「No accounts」。
- **示唆:** 「収集なし・買い切り」は個人開発の定番になった。local-bookshelf の「通信ゼロ」は同じ水準のうえに、**ネットワークを使う機能そのものがない**という一段強い主張として打ち出せる（ストアのラベルも「データの収集なし」にできる）。

### 4.8 Goodreads／StoryGraph — 対極の SNS 型
- Goodreads は 762K 件の評価がある最大手で、表紙スキャンを含む検索で登録する。英語のみ。データ収集が多く、広告もある。StoryGraph は 3.6K 件、Plus は年 $49.99、英語のみ。
- 「SNS が嫌い」層の受け皿として、両者は**比較対象（反面教師）**としてストア説明文に使える。

### 4.9 Delicious Library — 「木の棚に表紙が並ぶ」体験の元祖が消えた
- Mac で表紙を木の棚に並べた先駆け。Amazon のデータ提供停止を主因に、2024-11 に販売終了とサイト閉鎖が報じられた（iOS 版はそれ以前に終了したとの報道あり）。
- **示唆:** ①外部の書誌データに依存すると、提供元の都合で機能が止まる。local-bookshelf の「書誌照会なし」は、この事例を根拠に長く使えることを訴求できる。②「棚に表紙が並ぶ楽しさ」を懐かしむ層（英語圏の Mac ユーザー）が存在する。Delicious Library を再現しようとする記事もある（morrick.me）。

---

## 5. 国内競合（簡易）

| アプリ | コンセプト | 登録 | 表示 | アカウント／通信 | 価格 | 言語 | 評価（JP） |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| **ブクログ**（Booklog, Inc.） | Web 本棚＋読書記録 SNS。「250 万人以上」 | バーコード（連続）・検索 | 表紙が並ぶ本棚 | 会員登録を推奨（X ログイン可） | 無料＋プレミアム 月 480 円／年 4,600 円 | 日本語 | 4.5（約 2.8 万） |
| **読書メーター**（BOOKWALKER） | 感想・レビュー SNS。感想 1,800 万件超 | バーコード | 不明（未確認） | 外部アカウントでのサインインあり | 無料 | 日本語 | 4.5（7,216） |
| **読書管理ビブリア**（Keisuke Uchida） | バーコード登録＋メモのロングセラー | バーコード・検索・手入力 | リスト／表紙グリッド | 独自アカウントの記載なし。iCloud/Dropbox。**広告あり・追跡ラベルあり** | 無料＋ビブリアクラブ ¥780 | 日本語・英語 | 4.6（1.2 万） |
| **Yomoo**（Ryunosuke Nagase） | 会員登録不要のシンプル読書記録 | バーコード・題名/著者検索 | 本棚（詳細は未確認） | 登録不要。**広告あり・追跡ラベルあり** | 無料＋プレミアム 月 ¥350／年 ¥3,500 ほか | 日・独・英・韓 | 4.7（5,943） |
| **Libri 読書管理**（BasaApp） | 本棚と栞で作る自分だけの図書館 | バーコード・**表紙撮影**（AI で高画質化） | 棚（「画集のように」と説明） | 未記載 | 無料 | 英語表記（説明文は日本語） | 評価なし |
| **Book Tracker**（海外・日本語対応） | §4.7 参照 | — | — | データ収集なし | ¥1,400 買い切り | 日本語ほか | 4.7（58） |

**既存メモとの差異:** `.dev/competitor-research.md` ではビブリアを「アカウント不要・端末内完結、無駄な通信なし」と書いていた。しかし App Store では**広告を含み、位置情報・識別子などが追跡に使われる可能性がある**と申告されている。Yomoo も同じ。「登録不要」と「通信なし・追跡なし」は別物で、国内の「プライベート系」定番は**通信ゼロではない**。この点は local-bookshelf の訴求余地になる。

---

## 6. ポジショニングと差別化／弱み

### 6.1 ポジショニング（2 軸）

| | 書誌照会あり（ISBN・検索） | 書誌照会なし（写真・手入力のみ） |
| :-- | :-- | :-- |
| **ビジュアル棚（背表紙・3D・面陳）** | Shelfy、Shelfieline、Delicious Library（終了）、ブクログ（表紙の本棚） | **local-bookshelf（空き地）**。近いのは Libri（表紙撮影、ただしバーコードも主軸） |
| **リスト・グリッド・記録中心** | BookBuddy、Libib、CLZ、Bookshelf、Book Tracker、ビブリア、Yomoo、Goodreads、StoryGraph | Bookshelf: Tracker & Catalog（撮影のみ？未確認） |

### 6.2 差別化できる点

| 軸 | local-bookshelf | 競合の状況 |
| :-- | :-- | :-- |
| 写真が先（撮った写真 = 書影） | 自分の本の実物の見た目（帯・版・汚れまで）が書影になる | 多くはデータベースの書影。写真は「照合の手がかり」か「書影がないときの代わり」。Shelfy・Libri は表紙写真に対応するが、書影として保存するかは不明 |
| ISBN 不要 | 古書・同人誌・洋書・ZINE・帯付きの版でも同じ手順で登録できる | 主流は ISBN 前提。Libib には「英語以外の本は ISBN がうまく認識されない」というレビューがある |
| 通信ゼロ | ネットワークを使う機能がない。ラベルは「データの収集なし」 | 「収集なし」は Book Tracker・PageFlow など少数。国内の定番（ビブリア・Yomoo）は広告と追跡あり。Shelfieline も外部 API を照会する |
| 書店の面陳＋カバーフロー | 中央の 1 冊が正面、左右は角度つき。縦スワイプで棚（ジャンル）を切り替え | 背表紙棚（Shelfy・Shelfieline）かグリッドが主流。面陳カバーフローは今回見つからなかった |
| 買い切り 600 円・課金なし | 迷わせない | ビジュアル棚の競合はサブスク・パック課金が重い（Shelfy は最大 $99.99） |
| 日英対応 | 日本語の縦書き表紙と英語の表紙の両方を想定 | ビジュアル棚の競合は英語のみ（Shelfy）か日本中心（Shelfieline） |

### 6.3 弱み・リスク

| 弱み | 内容 | 競合の強み |
| :-- | :-- | :-- |
| 登録の手間（1 冊ずつ撮る） | 数百冊の初回登録が重い | バーコードの連続スキャン（ブクログ・Shelfieline・Bookshelf の一括）、棚写真の一括認識（Handy Library・ShelfSnap・Book Shelfie） |
| 題名の手間 | 題名は必須で、OCR は縦書き・装飾書体に弱い | ISBN なら題名・著者が自動で入る |
| 著者・シリーズで整理できない | 著者別の棚を手で作るしかない | 書誌がある競合は著者別・シリーズ順の並べ替えができる |
| 検索が題名の部分一致だけ | 読みで探せない（例:「ちくま」で「筑摩」が出ない） | 書誌 DB のある競合は著者・ISBN でも検索できる |
| 移行手段がない | Goodreads/CSV の取り込みがない。英語圏では乗り換え障壁 | Shelfy・Bookshelf・Book Tracker・PageFlow は Goodreads/CSV を取り込める |
| 端末間の同期がない | 機種変更は OS のバックアップ頼み | iCloud 同期が標準化（Book Tracker・Shelfy・Bookrise など） |
| 書影の画質がばらつく | 自分で撮るので明るさ・反射・歪みが出る | データベースの書影は均一 |
| 「見た目」の差が伝わりにくい | 機能一覧では違いが見えない | ストアのスクリーンショットと動画で勝負になる |

### 6.4 「表紙を撮る → カバーフローの棚」をすでにやっているアプリはあるか
- **今回の調査範囲では、完全に一致するアプリは見つからなかった（網羅性は保証しない）。**
- 部分的に重なるアプリ:
  - Shelfy: 表紙写真と斜め補正、3D 棚。ただし背表紙棚で、課金が重く、英語のみ。
  - Shelfieline: 棚を横スワイプで切り替えるカルーセル。ただし背表紙棚で、ISBN が主軸。
  - Libri: 表紙撮影で登録し、棚に並べる。表示の詳細は不明。
  - Bookshelf: Tracker & Catalog: カメラで撮る。表示は不明。
  - CLZ: Cover Wall がある。ただし ISBN 前提。
- **類似アプリは 2025〜26 年に急増中**（Shelfy・Shelfieline・Libri・Book Shelfie はいずれも新しい）。リリースまでにカバーフロー型が出る可能性は高い。差別化は「型」より**作り込みの質**に置くべきで、これは business-plan の判断と一致する。

---

## 7. 日英対応で考慮すべき点

### 7.1 OCR（Vision）
| 論点 | 状況 | 対応案 |
| :-- | :-- | :-- |
| 日本語の対応 | Vision のテキスト認識は iOS 16 から日本語（`ja`）に対応したとの報告がある（開発者ブログ。Apple の公式の言語一覧は未確認） | 実行時に `supportedRecognitionLanguages` で確かめる |
| **縦書き（tategaki）** | 2025-01 の Apple Developer Forums で、縦書きは認識結果が空になるという質問が出た。DTS エンジニアは「画像を回転・再配置してから認識する」「`RecognizeTextRequest` の orientation を使う」「`recognitionLanguages` を `ja` だけにする」と回答した。解決は確認されていない | 表紙を 0°／90°回転の 2 通りで認識し、信頼度の高い方を候補にする。題名の候補は「採用・修正・破棄」で吸収する（要件どおり） |
| 単語単位の出力 | WWDC25「RecognizeDocumentsRequest」は 26 言語に対応するが、日中韓タイ語では単語単位の出力に対応しないと説明された | 題名は行単位で扱う |
| 言語の自動判定 | 日英が混ざった表紙（英字ロゴ＋日本語の題名）が多い | `recognitionLanguages = ["ja", "en"]` の順序、言語の自動判定の有無で精度が変わるかを実測する |
| 英語の表紙 | 横書きで、Vision の得意領域。ただし装飾書体・大文字のロゴ・著者名が題名より大きいことが多い | 「いちばん大きい文字列 = 題名」という推定は英語の表紙では外れやすい。候補を複数出す |

### 7.2 題名の並べ替え（「題名順」の整列）
- **英語:** `localizedStandardCompare` などのロケール対応比較で、おおむね期待どおりに並ぶ。冠詞（The / A / An）を無視して並べるかは仕様で決める（図書館や iTunes の慣習では無視する）。
- **日本語:** 漢字は**読みがないと五十音順にならない**。iOS の標準の照合は漢字を中国語の規則で扱うことがあるという指摘がある（atadistance.net。未検証）。
  - 案 A: 「よみ（任意）」欄を隠し項目として持ち、OCR の確定時に自動で推定する。`CFStringTokenizer` の日本語トークナイザでラテン文字の読みを得る手法が一般に知られるが、精度は未検証。
  - 案 B: 日本語の題名順は「かな・カナ・英数字・漢字（Unicode 順）」で妥協し、仕様に明記する。
  - 要件の「題名の部分一致検索」でも、読みを持てば「かな入力でも漢字題名が見つかる」という改善につながる（§6.3 の弱み対策）。
- 日英が混ざる棚での並び順（英字を先に置くか、五十音の後に置くか）を決める。

### 7.3 ジャンル名（初期 28 件）の翻訳
- 初期ジャンルは**日本の書店の売り場区分**をもとにしている。英語圏の書店区分（Fiction / Nonfiction / Mystery & Thriller / Sci-Fi & Fantasy / Romance / Biography / Self-Help / Cookbooks など。BISAC 分類が業界標準）とは粒度が違う。
- 「文庫」「新書」「ライトノベル」「コミック」のような日本特有の区分は、直訳すると意味が伝わらない。
- 案:
  - (a) 言語ごとに別の初期ジャンルセットを持つ。英語ロケールでは英語圏の区分を出す。
  - (b) 同じ 28 件を意訳する。
  - どちらの案でも「初期ジャンル」と「ユーザーが作ったジャンル」は区別する。初期ジャンルは名前を変えていなければ表示言語に追従させ、ユーザーが作った・名前を変えたジャンルは翻訳しない。そのためにデータに「初期ジャンル ID」を持たせる。
- 区分（文芸・人文・社会・自然科学・技術・医療・芸術・生活／マイジャンル／システム）も同じ扱いにする。

### 7.4 App Store（ASO）
| 市場 | キーワード候補（例・未検証） | 補足 |
| :-- | :-- | :-- |
| 日本 | 本棚、蔵書管理、読書記録、書庫、表紙、積読、本 管理、オフライン | 既存の business-plan どおり、アプリ名の先頭に「本棚」「蔵書管理」を置く。競合の名前は「読書管理〇〇」が多い（ブクログ・ビブリア・Yomoo） |
| 英語圏 | bookshelf, book collection, home library, book catalog, cover, private, offline, no account | 「book tracker」「reading tracker」は競合が非常に多い。棚・コレクション側の語を軸にする。「bookshelf」は SquidBit・Shelfy などが使っている |
| 日本ストアの副ロケール | 日本ストアでは英語(米国)のメタデータも索引されるとする資料が多い（AppTweak・AppRadar・Phiture）。英語(英国)とする資料もある（AppFigures） | 日本ストア向けに英語(米国)のキーワード欄を使える可能性がある。App Store Connect で確かめる。ロケールをまたいだ語の組み合わせは効かないとの検証がある（Phiture） |

- スクリーンショットも言語別に用意する。日本語は縦書きの文庫が並ぶ棚、英語は洋書のハードカバーが並ぶ棚を見せ、**それぞれの市場の「本棚らしさ」**を出す。
- 共有画像の小さなアプリ名・文言もローカライズの対象になる。

---

## 8. 示唆・次のアクション候補

1. **ストアの実機確認（優先）:** Shelfy・Shelfieline・Libri・Bookshelf: Tracker & Catalog を実際に入れ、①表紙写真を書影にするか ②棚の切り替えの手触り ③課金の出し方、を確かめる。今回の「完全一致なし」の結論もここで裏取りする。
2. **縦書き OCR の実測:** オーナーの蔵書から日本語（縦書き・横書き）と英語の表紙を数十冊選び、`RecognizeTextRequest` を「回転なし／90°回転」「言語は ja のみ／ja,en」で比べる。business-plan の検証 1 に日英の観点を加える。
3. **「読み」欄の要否を決める:** 題名順の整列とかな検索のために、隠し項目の「よみ」を持つかを dev-architect で決める。持たない場合は、日本語の題名順の規則を仕様に明記する。
4. **ジャンルのローカライズ方式を決める:** 初期ジャンル ID を持たせ、英語ロケール用の初期セット（翻訳か別セットか）を決める。
5. **訴求文の軸を「通信ゼロ」から一段上げる:** 「登録不要・データ収集なし」は競合も掲げている。「ネットワーク機能がない＝書誌提供の終了で壊れない（Delicious Library の事例）」「自分の本の実物の表紙」「書店の面陳」を前面に出す。
6. **移行手段は将来の候補として記録:** 英語圏では Goodreads の CSV 取り込みがほぼ標準。ただし題名しか取り込めず書影は撮り直しになるため、効果は限定的。MVP 外のまま「要検討」とする。
7. **business-plan の競合欄を更新（提案のみ）:** Shelfy・Shelfieline・BookBuddy・Book Tracker を加える。PageFlow の価格（Lifetime $19.99・日本語非対応）、ビブリア（¥780 の IAP・広告あり）、Yomoo（サブスク・広告あり）の情報を反映する。※本書では business-plan を編集していない。

---

## 9. 出典

### 海外アプリ（App Store・公式）
- Shelfy: https://apps.apple.com/us/app/id6755626127
- Shelfieline（第三者サイト）: https://mwm.ai/apps/shelfieline/6767300403
- Bookshelf (SquidBit): https://apps.apple.com/us/app/id1464032274
- BookBuddy: https://apps.apple.com/us/app/bookbuddy-book-tracker/id395150347
- Libib: https://apps.apple.com/us/app/libib/id721908216 ／ 価格: https://libib.com/pricing ／ Pro はアプリ内で購入不可: https://support.libib.com/getting-started/get-libib-pro.html
- Libib のレビュー（表紙表示への不満）: https://justuseapp.com/en/app/721908216/libib/reviews
- CLZ Books: https://apps.apple.com/us/app/clz-books-library-organizer/id318799163 ／ Cover Wall: https://clz.com/books/mobile/manual/ios/2.0/en/topic/choosing-view-modes
- Book Tracker（JP）: https://apps.apple.com/jp/app/id1491660771
- PageFlow: https://apps.apple.com/app/id6753876053
- Bookshelf: Tracker & Catalog: https://apps.apple.com/us/app/id6757687876
- Book Shelfie: https://apps.apple.com/us/app/id6753343399
- ShelfSnap: https://apps.apple.com/us/app/shelfsnap-book-identifier/id6763460954
- Handy Library: https://www.handylibrary.com/
- Goodreads: https://apps.apple.com/us/app/goodreads-book-reviews/id355833469
- StoryGraph: https://apps.apple.com/us/app/-/id1570489264
- プライバシー重視の新しいトラッカー（Leafed など）: https://apps.apple.com/us/app/leafed-app/id6754466418 ／ https://apps.apple.com/us/app/-/id6739496861
- Bookly・Basmo・Fable・Beanstack（第三者比較・価格は資料によって差がある）: https://brighterly.com/blog/best-book-tracking-apps ／ https://bookwise-iota.vercel.app/blog/bookly-alternatives ／ https://apps.apple.com/ca/app/id1542456934?l=en-ca
- Oku（第三者情報）: https://bookwise-iota.vercel.app/blog/oku-app ／ https://www.alternativeto.net/software/readng/about/

### Delicious Library
- https://mjtsai.com/blog/2024/11/25/the-end-of-delicious-library
- https://vanderwal.net/random/entrysel.php?blog=2114
- https://www.apfeltalk.de/magazin/news/endgueltiges-aus-fuer-delicious-library/
- https://morrick.me/archives/9944

### 国内アプリ（App Store JP）
- ブクログ: https://apps.apple.com/jp/app/id359066582
- 読書メーター: https://apps.apple.com/jp/app/id509979590
- 読書管理ビブリア: https://apps.apple.com/JP/app/id894377244
- Yomoo: https://apps.apple.com/JP/app/id1516860157 ／ 登録不要の記載: https://appmatch.jp/1516860157-2/
- Libri 読書管理: https://apps.apple.com/us/app/-/id6756832379

### 技術・ASO
- 縦書き OCR（Apple Developer Forums、DTS の回答）: https://developer.apple.com/forums/thread/772972
- 中国語の縦書きが VNRecognizeTextRequest で読めない報告: https://developer.apple.com/forums/thread/749234
- iOS 16 で日本語 OCR に対応（開発者ブログ）: https://dev.to/john-rocky/japanese-ocr-on-iphone-with-the-vision-framework-446c
- WWDC25 Session 272（RecognizeDocumentsRequest、26 言語、日中韓は単語単位の出力に非対応）: https://developer.apple.com/videos/play/wwdc2025/272/
- 漢字の並べ替えと読み: https://help.claris.com/en/pro-help/content/furigana.html ／ https://atadistance.net/2020/09/20/power-and-responsibility-and-cultural-respect ／ https://nshipster.com/cfstringtransform
- ASO の副ロケール: https://www.apptweak.com/en/aso-blog/how-to-benefit-from-cross-localization-on-the-app-store ／ https://appradar.com/blog/ios-localization-list-of-primary-secondary-languages ／ https://phiture.com/?p=83231 ／ https://appfigures.com/resources/extend-keyword-list ／ https://adapty.io/blog/how-to-optimize-aso-for-japan/

### 未検証・注意事項のまとめ
- Shelfy が表紙写真を書影として保存するか、照合だけに使うか。
- Shelfieline の対応言語名と、外部 API を照会するかどうか（記述が矛盾）。
- Libib・読書メーター・Yomoo の表示形式の詳細。
- Bookly・Basmo・Fable・Oku の価格（第三者情報で、資料ごとに差がある）。
- Vision の日本語対応の公式な言語一覧。漢字の読みを推定する精度。
- 日本ストアの副ロケール（英語(米国)か英語(英国)か）。
