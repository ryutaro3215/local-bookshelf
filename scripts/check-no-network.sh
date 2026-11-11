#!/bin/sh
# 外部通信ゼロの確認（requirements.md S1）。
# 対象フォルダ（既定: Bookshelf/）に通信 API や URL が書かれていないかを調べる。
# 見つからなければ終了コード 0、見つかればその行を出して終了コード 1。
set -eu

target="${1:-Bookshelf}"
pattern='URLSession|URLRequest|NWConnection|http://|https://'

if [ ! -d "$target" ]; then
    echo "check-no-network: フォルダが見つかりません: $target" >&2
    exit 2
fi

if grep -rnE "$pattern" "$target"; then
    echo "check-no-network: 外部通信につながる記述が見つかりました（上の行）" >&2
    exit 1
fi

echo "check-no-network: OK（$target に通信の記述なし）"
exit 0
