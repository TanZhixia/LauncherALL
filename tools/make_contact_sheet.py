#!/usr/bin/env python3
"""把 Snapshots 目录里的主题截图拼成对比图（交付用）。"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SNAP = ROOT / "Snapshots"

FONT_CANDIDATES = [
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/System/Library/Fonts/PingFang.ttc",
]

def load_font(size):
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()

THEMES = [
    ("overworld", "翡翠原野 · Overworld"),
    ("nether", "下界熔岩 · Nether"),
    ("end", "末地虚空 · The End"),
    ("sculk", "深暗之域 · Deep Dark"),
    ("aurora", "极光晨曦 · Aurora"),
    ("cherry", "樱花原野 · Cherry Grove"),
]

def sheet(page, cols=3, width=700, title=None, out_name=None):
    rows = (len(THEMES) + cols - 1) // cols
    label_h, pad = 34, 14
    img0 = Image.open(SNAP / f"overworld-{page}.png")
    ratio = img0.height / img0.width
    cell_w, cell_h = width, int(width * ratio)
    title_h = 58 if title else 0
    canvas = Image.new("RGB", (cols * cell_w + (cols + 1) * pad, rows * (cell_h + label_h) + (rows + 1) * pad + title_h), (10, 14, 18))
    draw = ImageDraw.Draw(canvas)
    f_title, f_label = load_font(26), load_font(17)
    if title:
        draw.text((pad, pad + 4), title, font=f_title, fill=(238, 244, 250))
    for i, (tid, name) in enumerate(THEMES):
        r, c = divmod(i, cols)
        x = pad + c * (cell_w + pad)
        y = title_h + pad + r * (cell_h + label_h + pad)
        img = Image.open(SNAP / f"{tid}-{page}.png").convert("RGB").resize((cell_w, cell_h), Image.LANCZOS)
        canvas.paste(img, (x, y))
        draw.text((x + 2, y + cell_h + 8), name, font=f_label, fill=(188, 203, 214))
    out = SNAP / (out_name or f"sheet-{page}.png")
    canvas.save(out, optimize=True)
    print(f"wrote {out.relative_to(ROOT)}  {canvas.size}")

if __name__ == "__main__":
    sheet("demo", title="方块启动器 · 6 套主题下的同一套 UI（Minecraft Launcher UI Kit）", out_name="sheet-themes-demo.png")
    sheet("studio", title="主题工作台 · 令牌驱动的多主题一致性", out_name="sheet-themes-studio.png")
    sheet("buttons", title="按钮系统 · 4 变体 × 3 尺寸 × 多状态", out_name="sheet-buttons.png")
    sheet("selection", title="选择控件 · Toggle / Checkbox / RadioCard / Slider", out_name="sheet-selection.png")
    sheet("inputs", title="输入控件 · TextField / Search / Secure / TextArea", out_name="sheet-inputs.png")
    sheet("surfaces", title="容器与列表 · 三层玻璃 / ListRow / EmptyState", out_name="sheet-surfaces.png")
