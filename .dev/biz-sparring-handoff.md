# biz-sparring への引き継ぎメモ（2026-11-10）

requirements.md（2026-11-10 承認）と business-plan.md（approved）の間に食い違いがある。business-plan.md は biz-sparring の所有なので、ここには直さずにメモとして残す。次に biz-sparring を使うときに business-plan.md を更新すること。

## 食い違い

1. **題名の扱い**
   - business-plan.md 14行目: 「書誌情報の入力は必須にしない（題名は任意）」「撮影日が棚に加えた日として自動記録される」
   - requirements.md: 題名は**必須**（2026-11-09 オーナー判断）。表示する日付は「棚に加えた日」ではなく**購入日**（購入済みの本だけ）。データ追加日は表示しない
   - business-plan.md 59行目の「失敗時は手入力／空欄で登録できる設計で吸収する」も、「空欄では登録できない（文字認識の候補か手入力で題名を埋める）」に直す必要がある

2. **海外展開と価格**
   - requirements.md: UI は日本語・英語の両対応（N7）。ストア掲載情報も ja/en
   - business-plan.md: 価格 600円（日本の支払い意思上限が根拠）。海外での価格設定（ドル建ての価格帯）と、海外の競合（design/competitor-research.md）を踏まえた位置づけが未検討

3. **機能の追加（事業計画の「やること」との関係の確認）**
   - 2026-11-10 に追加した機能: ほしいものリスト（所持状況）、購入月別モード、共有の単位（ジャンル・月・日）と共有先（Instagram フィード・ストーリーズ・X）、初回チュートリアル
   - 「やること（1つ）」に集中する原則と矛盾しないか、MVP の範囲として妥当かを biz-sparring で確認する
   - Instagram ストーリーズへの直接投稿には Meta の開発者登録（App ID）が必要（design/share-image-research.md）。登録の手間を取るかどうかも事業判断

## 参照
- .dev/requirements.md
- design/competitor-research.md
- design/share-image-research.md
