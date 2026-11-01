#!/usr/bin/env python3
"""把 Snapshots 目录里的主题截图拼成对比图（深色 / 浅色 两套主题）。"""
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
    ("graphite", "深色主题 · 石墨 Graphite"),
    ("porcelain", "浅色主题 · 瓷白 Porcelain"),
]

def sheet(page, width=1000, title=None, out_name=None):
    pad, label_h = 16, 34
    img0 = Image.open(SNAP / f"graphite-{page}.png")
    cell_w = width
    cell_h = int(width * img0.height / img0.width)
    title_h = 60 if title else 0
    canvas = Image.new("RGB", (len(THEMES) * cell_w + (len(THEMES) + 1) * pad, cell_h + label_h + 2 * pad + title_h), (10, 11, 13))
    draw = ImageDraw.Draw(canvas)
    f_title, f_label = load_font(26), load_font(17)
    if title:
        draw.text((pad, pad + 6), title, font=f_title, fill=(238, 240, 243))
    for i, (tid, name) in enumerate(THEMES):
        x = pad + i * (cell_w + pad)
        y = title_h + pad
        img = Image.open(SNAP / f"{tid}-{page}.png").convert("RGB").resize((cell_w, cell_h), Image.LANCZOS)
        canvas.paste(img, (x, y))
        draw.text((x + 2, y + cell_h + 8), name, font=f_label, fill=(186, 192, 200))
    out = SNAP / (out_name or f"sheet-{page}.png")
    canvas.save(out, optimize=True)
    print(f"wrote {out.relative_to(ROOT)}  {canvas.size}")

XML_SAMPLES = [
    ("launcher", "启动器首屏"),
    ("components", "控件总览"),
    ("settings", "设置页"),
]

def sheet_xml():
    """XML 示例：3 个界面 × 深/浅两套主题。"""
    folder = SNAP / "XML"
    if not folder.exists():
        print("skip xml sheet: Snapshots/XML 不存在")
        return
    pad, label_h = 14, 32
    img0 = Image.open(folder / "graphite-launcher.png")
    cell_w = 660
    cell_h = int(cell_w * img0.height / img0.width)
    cols, rows = len(XML_SAMPLES), 2
    title_h = 58
    canvas = Image.new("RGB", (cols * cell_w + (cols + 1) * pad, rows * (cell_h + label_h) + (rows + 1) * pad + title_h), (10, 11, 13))
    draw = ImageDraw.Draw(canvas)
    f_title, f_label = load_font(26), load_font(17)
    draw.text((pad, pad + 6), "XML 描述的界面 · 同一份 XML 在深色 / 浅色主题下渲染", font=f_title, fill=(238, 240, 243))
    for row, (theme_id, theme_name) in enumerate([("graphite", "深色 · 石墨"), ("porcelain", "浅色 · 瓷白")]):
        for col, (sample_id, sample_name) in enumerate(XML_SAMPLES):
            path = folder / f"{theme_id}-{sample_id}.png"
            if not path.exists():
                continue
            x = pad + col * (cell_w + pad)
            y = title_h + pad + row * (cell_h + label_h + pad)
            img = Image.open(path).convert("RGB").resize((cell_w, cell_h), Image.LANCZOS)
            canvas.paste(img, (x, y))
            draw.text((x + 2, y + cell_h + 6), f"{sample_name} · {theme_name}", font=f_label, fill=(186, 192, 200))
    out = SNAP / "sheet-xml.png"
    canvas.save(out, optimize=True)
    print(f"wrote {out.relative_to(ROOT)}  {canvas.size}")

APP_TABS = [
    ("launch", "启动"),
    ("download", "下载"),
    ("settings", "设置"),
    ("more", "更多"),
]

def sheet_app():
    """启动器主界面：4 个导航页 × 深/浅两套主题。"""
    folder = SNAP / "App"
    if not folder.exists():
        print("skip app sheet: Snapshots/App 不存在")
        return
    pad, label_h = 12, 30
    img0 = Image.open(folder / "app-graphite-launch.png")
    cell_w = 500
    cell_h = int(cell_w * img0.height / img0.width)
    title_h = 58
    canvas = Image.new("RGB", (4 * cell_w + 5 * pad, 2 * (cell_h + label_h) + 3 * pad + title_h), (10, 11, 13))
    draw = ImageDraw.Draw(canvas)
    f_title, f_label = load_font(26), load_font(17)
    draw.text((pad, pad + 6), "方块启动器 · 启动 / 下载 / 设置 / 更多（深色 + 浅色）", font=f_title, fill=(238, 240, 243))
    for row, (theme_id, theme_name) in enumerate([("graphite", "深色"), ("porcelain", "浅色")]):
        for col, (tab_id, tab_name) in enumerate(APP_TABS):
            path = folder / f"app-{theme_id}-{tab_id}.png"
            if not path.exists():
                continue
            x = pad + col * (cell_w + pad)
            y = title_h + pad + row * (cell_h + label_h + pad)
            img = Image.open(path).convert("RGB").resize((cell_w, cell_h), Image.LANCZOS)
            canvas.paste(img, (x, y))
            draw.text((x + 2, y + cell_h + 6), f"{tab_name} · {theme_name}", font=f_label, fill=(186, 192, 200))
    out = SNAP / "sheet-app.png"
    canvas.save(out, optimize=True)
    print(f"wrote {out.relative_to(ROOT)}  {canvas.size}")

if __name__ == "__main__":
    sheet("demo", title="方块启动器 · 同一套 UI 的深色 / 浅色主题（Minecraft Launcher UI Kit）", out_name="sheet-themes-demo.png")
    sheet("studio", title="主题工作台 · 一深一浅，只换色不换结构", out_name="sheet-themes-studio.png")
    sheet("buttons", title="按钮系统 · 4 变体 × 3 尺寸 × 多状态", out_name="sheet-buttons.png")
    sheet("inputs", title="输入控件 · TextField / Search / Secure / TextArea", out_name="sheet-inputs.png")
    sheet("selection", title="选择控件 · Toggle / Checkbox / RadioCard / Slider", out_name="sheet-selection.png")
    sheet("surfaces", title="容器与列表 · 三层面板 / ListRow / EmptyState", out_name="sheet-surfaces.png")
    sheet("feedback", title="反馈与状态 · 进度 / 加载 / 骨架屏 / 横幅 / Toast", out_name="sheet-feedback.png")
    sheet_xml()
    sheet_app()
