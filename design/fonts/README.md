# フォント（ハンドオフ用）

## ファイルと用途

| ファイル | サイズ | 用途 |
|---|---|---|
| `NotoSerifJP-VariableFont_wght.ttf` | 13,574,352 B（約12.9 MB） | Serif: ジャンル名・棚名・書名 = 600 ／ 共有画像のタイトル = 700 |
| `NotoSansJP-VariableFont_wght.ttf` | 9,589,900 B（約9.1 MB） | Sans: それ以外すべて。本文 = 400 ／ 見出し・ボタン = 500 |
| `OFL.txt` | — | ライセンス本文（google/fonts 公式 OFL.txt） |

どちらも可変フォント（`wght` 軸: Sans 100–900、Serif 200–900）。1ファイルで全ウェイトを賄う。

## 名前（UIFont / Font.custom 用）

| | ファミリー名 | PostScript名（既定インスタンス） | 名前付きインスタンス |
|---|---|---|---|
| Sans | `Noto Sans JP` | `NotoSansJP-Thin` | Regular(400) / Medium(500) ほか（Variations PS接頭辞 `NotoSansJP`） |
| Serif | `Noto Serif JP` | `NotoSerifJP-ExtraLight` | `NotoSerifJP-SemiBold`(600) / `NotoSerifJP-Bold`(700) ほか |

- 既定インスタンスは細いウェイトなので、PostScript名だけで指定すると Thin / ExtraLight になる点に注意。
- 推奨: ファミリー名＋ウェイト指定（例 `Font.custom("Noto Serif JP", size: 17).weight(.semibold)`、UIKit は `UIFontDescriptor` の family + weight trait）。

## アプリへの同梱

- 2つの可変フォントをアプリターゲットに追加して同梱する。
- T6 でビルド設定 `INFOPLIST_KEY_UIAppFonts`（Info.plist の `UIAppFonts`）に以下を登録:
  - `NotoSansJP-VariableFont_wght.ttf`
  - `NotoSerifJP-VariableFont_wght.ttf`

## ライセンス

SIL Open Font License 1.1。アプリへの同梱・再配布可（`OFL.txt` を同梱すること。フォント単体の販売は不可）。
