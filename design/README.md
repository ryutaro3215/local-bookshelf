# design/ — 実装担当への受け渡し

iOS アプリ「local-bookshelf」のデザイン資料の入口。

## Figma

- ファイル名: `local-bookshelf`
- URL: https://www.figma.com/design/cj8HJsUvr725vkrJ2RdmH7/local-bookshelf （ファイルキー `cj8HJsUvr725vkrJ2RdmH7`）
- ページ: 「Page 1」
- 正本は Figma。この README や PNG と食い違うときは Figma を正とする
- x=0 から右: 詳細デザイン（実装に使う）
- x=-20000 から左: アーカイブ（旧モック・使わなかった案）。**実装には使わない**

## 行の並び（y 座標）

各行の画面は左から順に並んでいる。

| y | 行 |
| --: | :-- |
| 0 | 基本（閲覧ページ） |
| 1100 | A 登録 |
| 2200 | B 棚の末尾の空き枠 |
| 3300 | C 登録待ち |
| 4400 | D 棚の移動 |
| 5500 | E 詳細・編集・検索 |
| 6600 | F 設定・ジャンル管理 |
| 7700 | G 表示メニュー・棚一覧 |
| 8800 | H 長押し後の操作 |
| 9900 | I グリッド |
| 11000 | J 購入月別 |
| 12100 | K 共有 |
| 13300 | 共有画像（S1） |
| 15600 | L 初回 |
| 16700 | M 買いたい本の棚 |
| 17800 | N 四隅の手動調整 |
| 18900 | O カメラの許可 |
| 20000 | P 100冊以上の棚 |
| 21100 | Q 英語・文字の拡大 |

## 仕様

- `.dev/design-brief.md` — 色・書体・余白などのトークン、部品、画面一覧（ノード ID つき）、動き、共有画像の決まり
- 要件は `.dev/requirements.md`

## 受け渡し資料の置き場所

| 場所 | 中身 | git |
| :-- | :-- | :-- |
| `design/screens/` | 各画面の PNG | 管理外（表紙の写真を含むため） |
| `design/fonts/` | Noto Sans JP・Noto Serif JP（SIL Open Font License） | 管理する |
| `design/sample-covers/` | 開発用の表紙見本 | 管理外（著作物のため） |

## 経緯

- `design/mock-todo.md` — これまでの検討と決定の記録
