#!/usr/bin/env python3
"""Generate crisp 1024x1024 AppIcon and LaunchBg Assets.xcassets for MileDeck."""
from __future__ import annotations

import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Resources" / "Assets.xcassets"


def draw_icon(out_png: Path) -> None:
    S = 1024
    W = S * 2
    img = Image.new("RGB", (W, W), (17, 24, 39))  # Asphalt Dark #111827
    draw = ImageDraw.Draw(img)

    # Rich layered asphalt radial glow
    cx0, cy0 = W // 2, int(W * 0.42)
    for i in range(42, 0, -1):
        frac = i / 42.0
        rad = int(W * 0.72 * frac)
        r = int(17 + (1 - frac) * 14)
        g = int(24 + (1 - frac) * 44)
        b = int(39 + (1 - frac) * 34)
        draw.ellipse([cx0 - rad, cy0 - rad, cx0 + rad, cy0 + rad], fill=(r, g, b))

    # Subtle dashboard precision grid lines
    grid_col = (29, 44, 58)
    for g in range(192, W, 192):
        draw.line([(g, 0), (g, W)], fill=grid_col, width=3)
        draw.line([(0, g), (W, g)], fill=grid_col, width=3)

    # Back stacked deck card — evokes MileDeck swipe deck
    draw.rounded_rectangle([320, 224, 1728, 1680], radius=128, fill=(24, 36, 52), outline=(5, 150, 105), width=8)
    draw.rounded_rectangle([272, 290, 1660, 1744], radius=128, fill=(12, 18, 29))  # Drop shadow

    # Main Crisp Road-White Deck Card
    card_box = [244, 260, 1636, 1712]
    draw.rounded_rectangle(card_box, radius=124, fill=(244, 246, 248))

    # Top Highway Emerald Header Bar on Card
    draw.rounded_rectangle([244, 260, 1636, 570], radius=124, fill=(5, 150, 105))
    draw.rectangle([244, 440, 1636, 570], fill=(5, 150, 105))

    # Route indicator pills inside emerald header
    draw.ellipse([348, 364, 428, 444], fill=(255, 255, 255))
    draw.ellipse([368, 384, 408, 424], fill=(5, 150, 105))
    draw.rounded_rectangle([466, 382, 960, 426], radius=22, fill=(209, 250, 229))
    draw.rounded_rectangle([466, 456, 780, 494], radius=19, fill=(167, 243, 208))

    # Highway Perspective Road rendered on separate masked layer so strokes clip cleanly
    rx0, ry0, rx1, ry1 = 330, 646, 1550, 1344
    rw, rh = rx1 - rx0, ry1 - ry0
    road_layer = Image.new("RGBA", (rw, rh), (17, 24, 39, 255))
    rdraw = ImageDraw.Draw(road_layer)
    mid_x = rw // 2

    # Perspective highway trapezoid in lighter asphalt
    rdraw.polygon([(mid_x - 165, 0), (mid_x + 165, 0), (mid_x + 485, rh), (mid_x - 485, rh)], fill=(31, 41, 55, 255))
    # Emerald highway shoulders
    rdraw.line([(mid_x - 165, 0), (mid_x - 485, rh)], fill=(16, 185, 129, 255), width=22)
    rdraw.line([(mid_x + 165, 0), (mid_x + 485, rh)], fill=(16, 185, 129, 255), width=22)

    # Signal Amber dashed center highway stripes (cleanly below route pin)
    dashes = [
        (246, 344, 24, 34),
        (396, 514, 36, 48),
        (572, 698, 50, 64),
    ]
    for y0, y1, w0, w1 in dashes:
        rdraw.polygon([
            (mid_x - w0 // 2, y0),
            (mid_x + w0 // 2, y0),
            (mid_x + w1 // 2, y1),
            (mid_x - w1 // 2, y1),
        ], fill=(245, 158, 11, 255))

    # Emerald Route Pin at horizon crest
    px, py = mid_x, 140
    rdraw.ellipse([px - 74, py - 74, px + 74, py + 74], fill=(5, 150, 105, 255), outline=(255, 255, 255, 255), width=14)
    rdraw.ellipse([px - 26, py - 26, px + 26, py + 26], fill=(255, 255, 255, 255))

    road_mask = Image.new("L", (rw, rh), 0)
    ImageDraw.Draw(road_mask).rounded_rectangle([0, 0, rw, rh], radius=76, fill=255)
    img.paste(road_layer, (rx0, ry0), road_mask)

    # Bottom Mechanical Odometer Strip (timeless 014.8 tenths drum)
    draw.rounded_rectangle([330, 1412, 1152, 1618], radius=44, fill=(226, 232, 240))
    drum_x = 368
    for idx in range(4):
        fill_d = (17, 24, 39) if idx < 3 else (5, 150, 105)
        draw.rounded_rectangle([drum_x, 1446, drum_x + 154, 1584], radius=24, fill=fill_d)
        drum_x += 180

    try:
        f_odo = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 104)
        f_badge = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 236)
        f_top = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 112)
    except Exception:
        f_odo = f_badge = f_top = ImageFont.load_default()

    digits = ["0", "1", "4", "8"]
    drum_x = 368
    for d in digits:
        tb = draw.textbbox((0, 0), d, font=f_odo)
        tw, th = tb[2] - tb[0], tb[3] - tb[1]
        draw.text((drum_x + (154 - tw) // 2 - tb[0], 1446 + (138 - th) // 2 - tb[1]), d, font=f_odo, fill=(255, 255, 255))
        drum_x += 180

    # Top-right MI pill in header
    mi_txt = "MI"
    mb = draw.textbbox((0, 0), mi_txt, font=f_top)
    draw.text((1540 - (mb[2] - mb[0]) - mb[0], 350 - mb[1]), mi_txt, font=f_top, fill=(255, 255, 255))

    # Prominent Tax Deduction "$" Badge overlapping bottom-right corner
    bx, by, br = 1528, 1524, 268
    draw.ellipse([bx - br - 28, by - br - 28, bx + br + 28, by + br + 28], fill=(17, 24, 39))
    draw.ellipse([bx - br, by - br, bx + br, by + br], fill=(5, 150, 105))
    draw.ellipse([bx - br + 24, by - br + 24, bx + br - 24, by + br - 24], outline=(167, 243, 208), width=12)

    db = draw.textbbox((0, 0), "$", font=f_badge)
    dw, dh = db[2] - db[0], db[3] - db[1]
    draw.text((bx - dw // 2 - db[0], by - dh // 2 - db[1] - 4), "$", font=f_badge, fill=(255, 255, 255))

    final = img.resize((S, S), Image.Resampling.LANCZOS)
    out_png.parent.mkdir(parents=True, exist_ok=True)
    final.save(out_png, "PNG")


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))

    icon_dir = ASSETS / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    icon_png = icon_dir / "AppIcon-1024.png"
    draw_icon(icon_png)
    (icon_dir / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2))

    # LaunchBg = Crisp Road White #F4F6F8
    launch_dir = ASSETS / "LaunchBg.colorset"
    launch_dir.mkdir(parents=True, exist_ok=True)
    (launch_dir / "Contents.json").write_text(json.dumps({
        "colors": [{
            "color": {
                "color-space": "srgb",
                "components": {"alpha": "1.000", "blue": "0.973", "green": "0.965", "red": "0.957"},
            },
            "idiom": "universal",
        }],
        "info": {"author": "xcode", "version": 1},
    }, indent=2))

    docs_icon = ROOT / "docs" / "icon.png"
    docs_icon.parent.mkdir(parents=True, exist_ok=True)
    Image.open(icon_png).resize((512, 512), Image.Resampling.LANCZOS).save(docs_icon, "PNG")
    print(f"✓ Generated {icon_png} and {docs_icon}")


if __name__ == "__main__":
    main()
