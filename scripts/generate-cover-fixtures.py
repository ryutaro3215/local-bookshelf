"""T3 のテスト用フィクスチャ（架空の表紙を斜めから撮った風の合成画像）を作る。

実在の本の表紙は著作物なのでリポジトリに入れない。代わりに、色・図形・架空の文字だけで
表紙を描き、透視変換して机のような背景に合成する。一度だけ実行して結果をコミットする。

使い方: python3 scripts/generate-cover-fixtures.py BookshelfTests/Fixtures
必要なもの: pillow, opencv-python, numpy
"""

import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 1536, 2048  # 写真らしい縦長（3:4）
COVER_W, COVER_H = 1000, 1450  # 表紙の縦横比 1:1.45


def font(size):
    return ImageFont.load_default(size=size)


def draw_cover(seed, title, sub, top, bottom, accent):
    rng = np.random.default_rng(seed)
    grad = np.linspace(0, 1, COVER_H)[:, None, None]
    arr = (np.array(top) * (1 - grad) + np.array(bottom) * grad) * np.ones((COVER_H, COVER_W, 3))
    img = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(img)
    for _ in range(6):
        x, y = rng.integers(0, COVER_W), rng.integers(300, COVER_H - 300)
        r = int(rng.integers(60, 220))
        d.ellipse([x - r, y - r, x + r, y + r], outline=accent, width=14)
    d.rectangle([60, 60, COVER_W - 60, 90], fill=accent)
    d.text((80, 160), title, font=font(130), fill=(255, 255, 255))
    d.text((80, 340), sub, font=font(60), fill=(240, 240, 240))
    d.rectangle([60, COVER_H - 220, COVER_W - 60, COVER_H - 60], fill=(250, 250, 245))
    d.text((100, COVER_H - 180), "FICTION PRESS", font=font(70), fill=(30, 30, 30))
    return np.array(img)


def background(seed, base):
    rng = np.random.default_rng(seed)
    y = np.arange(H)[:, None]
    x = np.arange(W)[None, :]
    grain = 18 * np.sin(x / 23.0 + 6 * np.sin(y / 180.0)) + 8 * np.sin(x / 7.0)
    noise = rng.normal(0, 6, (H, W))
    lum = grain + noise
    bg = np.clip(np.array(base)[None, None, :] + lum[..., None], 0, 255)
    return bg.astype(np.uint8)


def composite(cover, bg, corners):
    src = np.float32([[0, 0], [COVER_W, 0], [COVER_W, COVER_H], [0, COVER_H]])
    dst = np.float32(corners)
    m = cv2.getPerspectiveTransform(src, dst)
    warped = cv2.warpPerspective(cover, m, (W, H), flags=cv2.INTER_LINEAR)
    mask = cv2.warpPerspective(np.full((COVER_H, COVER_W), 255, np.uint8), m, (W, H))
    # 影（右下に少しずらしてぼかす）
    shadow = cv2.GaussianBlur(np.roll(mask, (25, 25), axis=(0, 1)), (0, 0), 20) / 255.0
    out = bg.astype(np.float32) * (1 - 0.45 * shadow[..., None])
    a = cv2.GaussianBlur(mask, (0, 0), 1.2)[..., None] / 255.0
    out = out * (1 - a) + warped.astype(np.float32) * a
    out = cv2.GaussianBlur(out, (0, 0), 0.8)  # レンズのにじみ
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def gps_exif():
    exif = Image.Exif()
    exif[0x010F] = "FictionCam"  # Make
    exif[0x0110] = "Model X"  # Model
    exif[0x0132] = "2026:11:11 10:00:00"  # DateTime
    exif[0x8769] = {0x9003: "2026:11:11 10:00:00", 0x829A: (1, 120)}  # Exif IFD
    exif[0x8825] = {  # GPS IFD（東京駅付近の架空の値）
        0x0001: "N",
        0x0002: (35.0, 40.0, 52.0),
        0x0003: "E",
        0x0004: (139.0, 46.0, 0.0),
    }
    return exif


def main(out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    specs = [
        # name, cover args, bg color, corners (TL, TR, BR, BL)
        ("cover-tilt-left.jpg", (1, "ORBIT", "a made-up novel", (30, 60, 140), (10, 20, 60), (250, 200, 40)),
         (150, 120, 90), [(330, 380), (1220, 300), (1290, 1720), (260, 1610)], False),
        ("cover-tilt-right.jpg", (2, "MOSS", "notes on nothing", (170, 40, 40), (90, 10, 30), (255, 230, 200)),
         (200, 190, 170), [(260, 330), (1150, 420), (1210, 1640), (200, 1760)], False),
        ("cover-rotated.jpg", (3, "TIDE", "an invented atlas", (20, 120, 90), (5, 50, 40), (240, 240, 120)),
         (90, 70, 60), [(420, 260), (1290, 470), (1060, 1780), (170, 1520)], False),
        ("cover-top-down-gps.jpg", (4, "LUMEN", "fictional essays", (100, 40, 140), (40, 10, 70), (120, 220, 255)),
         (160, 140, 110), [(300, 420), (1190, 360), (1250, 1690), (240, 1720)], True),
    ]
    for name, cargs, bgc, corners, with_gps in specs:
        img = composite(draw_cover(*cargs), background(cargs[0] + 100, bgc), corners)
        if with_gps:
            img.save(out / name, quality=88, exif=gps_exif())
        else:
            img.save(out / name, quality=88)
    # 表紙が写っていない画像（ノイズ＋なだらかなグラデーション）
    rng = np.random.default_rng(9)
    grad = np.linspace(60, 190, W)[None, :, None] * np.ones((H, W, 3))
    noise = cv2.GaussianBlur(rng.normal(0, 40, (H, W, 3)), (0, 0), 6)
    Image.fromarray(np.clip(grad + noise, 0, 255).astype(np.uint8)).save(
        out / "no-cover.jpg", quality=88, exif=gps_exif())


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "BookshelfTests/Fixtures")
