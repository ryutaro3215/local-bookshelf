"""Icon Composer 用のレイヤー SVG（地なし・1024×1024）を案ごとに書き出す。
1-shelf 棚板（いちばん手前）/ 2-leaning 傾いた1冊 / 3-books 立っている背表紙（奥）。帯は穴（evenodd）で抜く。回転は座標に焼き込む。"""
import math
import os
import sys

VARIANTS = {
    "E1": dict(spines=[(92, 420), (70, 360), (104, 470), (80, 390), (96, 440)], base=740, bands=2, r=8,
               angle=14, gap=14, band_h=16, board=30),
    "E2": dict(spines=[(128, 500), (100, 420), (140, 560), (120, 470)], base=790, bands=1, r=14,
               angle=16, gap=18, band_h=22, board=40),
    "E3": dict(spines=[(92, 420), (70, 360), (104, 470), (80, 390), (96, 440)], base=740, bands=2, r=8,
               angle=14, gap=14, band_h=16, board=30),
}
GRAYS = {"E1": ["#141414", "#8E8E8E", "#141414", "#BDBDBD", "#5C5C5C"],
         "E2": ["#141414", "#8E8E8E", "#141414", "#5C5C5C"],
         "E3": ["#141414", "#8E8E8E", "#141414", "#BDBDBD", "#5B8A72"]}

# ダークでの塗り替え（Icon Composer で各レイヤーの Dark の塗りに入れる色）
DARK = {"#141414": "#EDEDED", "#5C5C5C": "#BDBDBD", "#5B8A72": "#7FB096"}


def rot(point, center, angle):
    a = math.radians(angle)
    x, y = point[0] - center[0], point[1] - center[1]
    return (center[0] + x * math.cos(a) - y * math.sin(a), center[1] + x * math.sin(a) + y * math.cos(a))


def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def rounded_rect(x, y, w, h, r, center=None, angle=0):
    pts = [(x + r, y), (x + w - r, y), (x + w, y + r), (x + w, y + h - r),
           (x + w - r, y + h), (x + r, y + h), (x, y + h - r), (x, y + r)]
    if center:
        pts = [rot(p, center, angle) for p in pts]
    p = [f"{f(a)} {f(b)}" for a, b in pts]
    return (f"M{p[0]} L{p[1]} A{r} {r} 0 0 1 {p[2]} L{p[3]} A{r} {r} 0 0 1 {p[4]} "
            f"L{p[5]} A{r} {r} 0 0 1 {p[6]} L{p[7]} A{r} {r} 0 0 1 {p[0]} Z")


def rect(x, y, w, h, center=None, angle=0):
    pts = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    if center:
        pts = [rot(p, center, angle) for p in pts]
    return "M" + " L".join(f"{f(a)} {f(b)}" for a, b in pts) + " Z"


def spine(v, x, w, h, center=None, angle=0):
    d = [rounded_rect(x, v["base"] - h, w, h, v["r"], center, angle),
         rect(x, v["base"] - h + 44, w, v["band_h"], center, angle)]
    if v["bands"] == 2:
        d.append(rect(x, v["base"] - 70, w, v["band_h"], center, angle))
    return " ".join(d)


def svg(paths):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            + "".join(paths) + "</svg>\n")


def build(name, v, out):
    width = sum(w for w, _ in v["spines"]) + v["gap"] * (len(v["spines"]) - 1)
    lean = v["spines"][-1][1] * math.sin(math.radians(v["angle"]))
    x0 = round((1024 - width - lean) / 2 + 20)
    x = x0
    books, leaning = [], []
    for i, (w, h) in enumerate(v["spines"]):
        color = GRAYS[name][i]
        if i == len(v["spines"]) - 1:
            d = spine(v, x, w, h, (x, v["base"]), v["angle"])
            leaning.append(f'<path fill-rule="evenodd" fill="{color}" d="{d}"/>')
        else:
            books.append(f'<path fill-rule="evenodd" fill="{color}" d="{spine(v, x, w, h)}"/>')
        x += w + v["gap"]
    board_w = x - v["gap"] - x0 + 160
    shelf = f'<path fill="#141414" d="{rounded_rect(x0 - 40, v["base"], board_w, v["board"], v["board"] // 3)}"/>'
    folder = os.path.join(out, name)
    os.makedirs(folder, exist_ok=True)
    # 黒い背表紙と灰色の背表紙は別レイヤー（ダークで黒だけ白に塗り替えられるように）
    black = [p for p in books if 'fill="#141414"' in p]
    gray = [p for p in books if 'fill="#141414"' not in p]
    for file, paths in (("1-shelf", [shelf]), ("2-leaning", leaning), ("3-books-black", black),
                        ("4-books-gray", gray)):
        open(os.path.join(folder, f"{file}.svg"), "w").write(svg(paths))
    # 確認用: 全部を重ねた1枚（白地）と、ダークで塗り替えたときの見本（黒地）
    open(os.path.join(folder, "preview.svg"), "w").write(
        svg(['<rect width="1024" height="1024" fill="#FFFFFF"/>'] + books + leaning + [shelf]))
    dark = "".join(books + leaning + [shelf])
    for light_color, dark_color in DARK.items():
        dark = dark.replace(f'fill="{light_color}"', f'fill="{dark_color}"')
    open(os.path.join(folder, "preview-dark.svg"), "w").write(
        svg(['<rect width="1024" height="1024" fill="#000000"/>', dark]))


for name, v in VARIANTS.items():
    build(name, v, sys.argv[1])
print("ok")
