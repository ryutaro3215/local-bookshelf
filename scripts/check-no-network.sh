#!/bin/sh
# 外部通信ゼロの確認（requirements.md S1）。
# 対象フォルダ（既定: リポジトリの Bookshelf/）に通信 API や URL が書かれていないかを調べる。
# 見つからなければ終了コード 0、見つかればその行を出して終了コード 1。
# どこから実行してもよい（フォルダはこのスクリプトの場所を基準に決める。N-010）。
# 同梱の書体のライセンス文（Bookshelf/Resources/Licenses/）は著作権表示に URL を含むが、
# 表示するだけの文書でアプリは開かないので対象から外す（N-033）。
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-$root/Bookshelf}"
# 通信の API（URL 読み込み・ソケット・Network.framework・Web 表示・近距離通信）と URL の書き方
pattern='URLSession|URLRequest|NSURLConnection|NWConnection|NWBrowser|NWListener|NWEndpoint|CFStream|CFSocket|getaddrinfo|WKWebView|SFSafariViewController|MultipeerConnectivity|MCSession|http://|https://|wss?://|ftp://'

if [ ! -d "$target" ]; then
    echo "check-no-network: フォルダが見つかりません: $target" >&2
    exit 2
fi

if grep -rnIE --exclude-dir=Licenses "$pattern" "$target"; then
    echo "check-no-network: 外部通信につながる記述が見つかりました（上の行）" >&2
    exit 1
fi

echo "check-no-network: OK（$target に通信の記述なし）"
exit 0
