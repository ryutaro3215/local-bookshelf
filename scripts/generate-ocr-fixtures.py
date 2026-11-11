"""T4 のテスト用フィクスチャ（架空の本の表紙。題名の文字認識用）を作る。

実在の本の表紙・題名は使わない。架空の題名・著者名・出版社名を、macOS 付属の書体で
台形補正済みの表紙（CoverProcessor の出力に相当）として描く。一度だけ実行して結果をコミットする。
フォルダ同期グループはテストバンドルへ平らにコピーするため、ファイル名に ocr- を付ける。

使い方: python3 scripts/generate-ocr-fixtures.py BookshelfTests/Fixtures
必要なもの: pillow, numpy（macOS の /System/Library/Fonts の書体を使う）
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 800, 1160  # 表紙の縦横比 1:1.45
FONTS = Path("/System/Library/Fonts")
GOTHIC_BOLD = FONTS / "ヒラギノ角ゴシック W6.ttc"
GOTHIC = FONTS / "ヒラギノ角ゴシック W3.ttc"
MINCHO = FONTS / "ヒラギノ明朝 ProN.ttc"
SANS_EN = FONTS / "Avenir Next.ttc"


def font(path, size, index=0):
    return ImageFont.truetype(str(path), size, index=index)


def base(seed, top, bottom):
    """上から下へのグラデーションに、細い線の模様を重ねた地"""
    grad = np.linspace(0, 1, H)[:, None, None]
    arr = (np.array(top) * (1 - grad) + np.array(bottom) * grad) * np.ones((H, W, 3))
    img = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    for _ in range(5):
        x, y = int(rng.integers(0, W)), int(rng.integers(H // 2, H))
        r = int(rng.integers(40, 160))
        d.ellipse([x - r, y - r, x + r, y + r], outline=tuple(int(c * 0.8) for c in bottom), width=6)
    return img, d


def centered(d, y, text, f, fill):
    w = d.textlength(text, font=f)
    d.text(((W - w) / 2, y), text, font=f, fill=fill)


def vertical(d, x, y, text, f, fill, step):
    """縦書き（1文字ずつ下へ。中心を x にそろえる）"""
    for i, ch in enumerate(text):
        w = d.textlength(ch, font=f)
        d.text((x - w / 2, y + i * step), ch, font=f, fill=fill)


def horizontal_en(out):
    # 横書き英語: 題名は大きく1行、副題・著者・出版社は小さく
    img, d = base(11, (24, 44, 92), (8, 16, 40))
    d.rectangle([50, 50, W - 50, 62], fill=(236, 196, 60))
    centered(d, 150, "a novel", font(SANS_EN, 34), (220, 220, 220))
    centered(d, 220, "PAPER COMETS", font(SANS_EN, 96, index=2), (255, 255, 255))
    centered(d, 360, "Imaginary stories from nowhere", font(SANS_EN, 32), (230, 230, 230))
    centered(d, 960, "Ada Fable", font(SANS_EN, 48), (255, 255, 255))
    centered(d, 1060, "FICTION PRESS", font(SANS_EN, 28), (200, 200, 200))
    img.save(out / "ocr-horizontal-en.png", optimize=True)


def horizontal_ja(out):
    # 横書き日本語: 題名は2行にわたる。下に帯（宣伝文）がある
    img, d = base(12, (250, 246, 236), (226, 214, 190))
    centered(d, 120, "架空書店の", font(GOTHIC_BOLD, 104), (30, 30, 30))
    centered(d, 250, "ちいさな地図帳", font(GOTHIC_BOLD, 104), (30, 30, 30))
    centered(d, 400, "まだ誰も読んでいない本のはなし", font(GOTHIC, 36), (70, 70, 70))
    centered(d, 480, "空野 しおり", font(MINCHO, 44), (40, 40, 40))
    d.rectangle([0, 820, W, H], fill=(196, 40, 48))
    centered(d, 870, "この帯の文は架空の宣伝です", font(GOTHIC_BOLD, 44), (255, 255, 255))
    centered(d, 950, "存在しない出版社の存在しない本", font(GOTHIC, 32), (255, 240, 240))
    centered(d, 1080, "フィクション文庫", font(GOTHIC, 28), (255, 255, 255))
    img.save(out / "ocr-horizontal-ja.png", optimize=True)


def vertical_ja(out):
    # 縦書き日本語: 題名は右に縦1列、著者はその左に小さく
    img, d = base(13, (232, 240, 236), (180, 204, 196))
    vertical(d, 600, 110, "星をかぞえる灯台", font(MINCHO, 92), (20, 30, 40), 104)
    vertical(d, 470, 160, "架空の物語集", font(MINCHO, 40), (60, 70, 80), 46)
    vertical(d, 200, 520, "月島 ほとり", font(MINCHO, 44), (30, 40, 50), 52)
    img.save(out / "ocr-vertical-ja.png", optimize=True)


def blank(out):
    # 文字のない表紙（模様だけ）: 題名の候補は空になる
    img, d = base(14, (120, 160, 90), (40, 70, 30))
    for i in range(6):
        d.rectangle([80 + i * 40, 120 + i * 60, W - 80 - i * 40, 200 + i * 60], outline=(230, 240, 200), width=4)
    img.save(out / "ocr-blank.png", optimize=True)


def main(out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    horizontal_en(out)
    horizontal_ja(out)
    vertical_ja(out)
    blank(out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "BookshelfTests/Fixtures")
