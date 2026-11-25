#!/usr/bin/env python3
"""Generate MileDeck high-conversion comparison promo posters (EN + ZH) and 15s 9:16 vertical reel (<20MB)."""
from __future__ import annotations

import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "build" / "raw_screens"
SHOT_ROOT = Path("/Users/wang/OPC/media/20261125-miledeck/appstore")
RELEASE_DIR = ROOT / "release"

FONT_EN_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_EN_REG = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_CN = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def font(size: int, bold: bool = True, cn: bool = False) -> ImageFont.FreeTypeFont:
    if cn and Path(FONT_CN).exists():
        try:
            return ImageFont.truetype(FONT_CN, size=size, index=2 if bold else 0)
        except Exception:
            return ImageFont.truetype(FONT_CN, size=size, index=0)
    path = FONT_EN_BOLD if bold else FONT_EN_REG
    if Path(path).exists():
        return ImageFont.truetype(path, size=size)
    return ImageFont.load_default()


def paste_phone(canvas: Image.Image, img_path: Path, box: tuple[int, int, int, int], radius: int = 34) -> None:
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    draw = ImageDraw.Draw(canvas)
    pad = 10
    draw.rounded_rectangle([x0 - pad, y0 - pad, x1 + pad, y1 + pad], radius=radius + pad, fill=(10, 14, 22))
    shot = Image.open(img_path).convert("RGBA").resize((w, h), Image.Resampling.LANCZOS)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w, h], radius=radius, fill=255)
    canvas.paste(shot, (x0, y0), mask)


def build_en_compare_card() -> Path:
    W, H = 1080, 1350
    img = Image.new("RGB", (W, H), (17, 24, 39))  # Asphalt Dark #111827
    draw = ImageDraw.Draw(img)

    # Top pill
    f_pill = font(25, bold=True)
    pill = "TIRED OF $90-$140/YR MILEAGE SUBSCRIPTIONS?"
    pb = draw.textbbox((0, 0), pill, font=f_pill)
    pw = pb[2] - pb[0]
    draw.rounded_rectangle([(W - pw) // 2 - 26, 44, (W + pw) // 2 + 26, 96], radius=26, fill=(5, 150, 105))
    draw.text(((W - pw) // 2, 56), pill, font=f_pill, fill=(255, 255, 255))

    # Headline
    f_h1 = font(54, bold=True)
    lines = ["Auto 2026 IRS Mileage Log.", "Pay $14.99 Once. Own Forever."]
    y = 118
    for ln in lines:
        b = draw.textbbox((0, 0), ln, font=f_h1)
        draw.text(((W - (b[2] - b[0])) // 2, y), ln, font=f_h1, fill=(255, 255, 255))
        y += 66

    # Comparison split cards (zero third-party trademarks!)
    cy0, cy1 = 272, 646
    # Left card: Typical Apps
    draw.rounded_rectangle([46, cy0, 520, cy1], radius=22, fill=(29, 39, 54), outline=(66, 80, 102), width=2)
    draw.text((74, cy0 + 24), "TYPICAL MILEAGE APPS", font=font(22, True), fill=(185, 196, 212))
    draw.text((74, cy0 + 60), "$90 - $140 / yr", font=font(44, True), fill=(248, 113, 113))
    draw.line([(74, cy0 + 86), (398, cy0 + 86)], fill=(239, 68, 68), width=5)

    bad_pts = [
        "x  Endless yearly subscription rent",
        "x  Uploads your GPS routes to cloud",
        "x  Manual 2026 rate adjustments",
        "x  Zero honest lifetime option",
    ]
    by = cy0 + 132
    for pt in bad_pts:
        draw.text((74, by), pt, font=font(23, False), fill=(210, 218, 228))
        by += 54

    # Right card: MileDeck
    draw.rounded_rectangle([560, cy0, 1034, cy1], radius=22, fill=(14, 46, 38), outline=(5, 150, 105), width=3)
    draw.text((588, cy0 + 24), "MILEDECK (iPhone & iPad)", font=font(22, True), fill=(110, 231, 183))
    draw.text((588, cy0 + 60), "$14.99 ONCE", font=font(46, True), fill=(255, 255, 255))

    good_pts = [
        "+  2026 Split IRS: 72.5c H1 / 76c H2",
        "+  Swipe Right Business / Left Personal",
        "+  1-Tap Schedule C PDF + CSV",
        "+  100% Offline & 20 Free Drives/mo",
    ]
    gy = cy0 + 132
    for pt in good_pts:
        draw.text((588, gy), pt, font=font(22, True), fill=(134, 239, 172))
        gy += 54

    # Real iOS Screenshots Side-by-Side at Bottom
    home_raw = RAW_DIR / "iphone65_en_home.png"
    swipe_raw = RAW_DIR / "iphone65_en_swipe.png"
    if home_raw.exists() and swipe_raw.exists():
        paste_phone(img, home_raw, (95, 688, 485, 1300), radius=34)
        paste_phone(img, swipe_raw, (595, 688, 985, 1300), radius=34)

    out = RELEASE_DIR / "compare_card_en_1080x1350.png"
    RELEASE_DIR.mkdir(parents=True, exist_ok=True)
    img.save(out, "PNG")
    print(f"✓ Saved {out} ({out.stat().st_size // 1024} KB)")
    return out


def build_zh_compare_card() -> Path:
    W, H = 1080, 1440  # 3:4 Xiaohongshu cover
    img = Image.new("RGB", (W, H), (244, 246, 248))
    draw = ImageDraw.Draw(img)

    # Top Asphalt Dark header slab + Highway Emerald accent stripe
    draw.rectangle([0, 0, W, 382], fill=(17, 24, 39))
    draw.rectangle([0, 372, W, 384], fill=(5, 150, 105))

    badge = "受够了年费 ¥428–¥698 的里程报税软件"
    fb = font(30, True, cn=True)
    bb = draw.textbbox((0, 0), badge, font=fb)
    bw = bb[2] - bb[0]
    draw.rounded_rectangle([(W - bw) // 2 - 28, 42, (W + bw) // 2 + 28, 102], radius=30, fill=(5, 150, 105))
    draw.text(((W - bw) // 2, 56), badge, font=fb, fill=(255, 255, 255))

    fh = font(62, True, cn=True)
    for idx, ln in enumerate(["自动记里程 · 滑卡秒抵税", "一次买断 · 永不续费"]):
        b = draw.textbbox((0, 0), ln, font=fh)
        draw.text(((W - (b[2] - b[0])) // 2, 134 + idx * 86), ln, font=fh, fill=(255, 255, 255))

    sub = "2026 IRS 上下半年分段费率自动算 · 100% 离线隐私 · 一键导出报税 PDF"
    fs = font(26, False, cn=True)
    sb = draw.textbbox((0, 0), sub, font=fs)
    draw.text(((W - (sb[2] - sb[0])) // 2, 316), sub, font=fs, fill=(205, 218, 232))

    # Price bar
    draw.rounded_rectangle([46, 412, 518, 560], radius=20, fill=(255, 255, 255), outline=(226, 232, 240), width=2)
    draw.text((76, 434), "常见订阅制里程报税软件", font=font(24, False, cn=True), fill=(100, 116, 139))
    draw.text((76, 478), "¥428 - ¥698 / 年", font=font(42, True, cn=True), fill=(220, 38, 38))

    draw.rounded_rectangle([562, 412, 1034, 560], radius=20, fill=(236, 253, 245), outline=(5, 150, 105), width=3)
    draw.text((592, 434), "MileDeck 离线买断版", font=font(24, True, cn=True), fill=(5, 150, 105))
    draw.text((592, 478), "每月20趟免费 / ¥48终身", font=font(36, True, cn=True), fill=(17, 24, 39))

    home_zh = RAW_DIR / "iphone65_zh_home.png"
    swipe_zh = RAW_DIR / "iphone65_zh_swipe.png"
    if home_zh.exists() and swipe_zh.exists():
        paste_phone(img, home_zh, (88, 602, 492, 1384), radius=34)
        paste_phone(img, swipe_zh, (588, 602, 992, 1384), radius=34)

    out = RELEASE_DIR / "compare_card_zh_3x4.png"
    img.save(out, "PNG")
    print(f"✓ Saved {out} ({out.stat().st_size // 1024} KB)")
    return out


def build_15s_promo_video(compare_en: Path) -> Path:
    slides = [
        compare_en,
        SHOT_ROOT / "en-US" / "iphone65" / "01_home.png",
        SHOT_ROOT / "en-US" / "iphone65" / "02_swipe.png",
        SHOT_ROOT / "en-US" / "iphone65" / "03_report.png",
        SHOT_ROOT / "en-US" / "iphone65" / "05_paywall.png",
    ]
    tmp_dir = ROOT / "build" / "promo_frames"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    norm_paths: list[Path] = []
    for idx, src in enumerate(slides):
        im = Image.open(src).convert("RGB")
        canvas = Image.new("RGB", (1080, 1920), (17, 24, 39))
        scale = min(1080 / im.width, 1920 / im.height)
        nw, nh = int(im.width * scale), int(im.height * scale)
        resized = im.resize((nw, nh), Image.Resampling.LANCZOS)
        canvas.paste(resized, ((1080 - nw) // 2, (1920 - nh) // 2))
        p = tmp_dir / f"slide_{idx:02d}.png"
        canvas.save(p, "PNG")
        norm_paths.append(p)

    out_mp4 = RELEASE_DIR / "promo_15s_en_9x16.mp4"
    ffmpeg = "/Users/wang/.local/bin/ffmpeg"
    inputs = []
    for p in norm_paths:
        inputs.extend(["-loop", "1", "-t", "3.0", "-i", str(p)])
    filter_complex = (
        "[0:v]fps=30,format=yuv420p[v0];"
        "[1:v]fps=30,format=yuv420p[v1];"
        "[2:v]fps=30,format=yuv420p[v2];"
        "[3:v]fps=30,format=yuv420p[v3];"
        "[4:v]fps=30,format=yuv420p[v4];"
        "[v0][v1]xfade=transition=fade:duration=0.35:offset=2.65[x01];"
        "[x01][v2]xfade=transition=fade:duration=0.35:offset=5.30[x02];"
        "[x02][v3]xfade=transition=fade:duration=0.35:offset=7.95[x03];"
        "[x03][v4]xfade=transition=fade:duration=0.35:offset=10.60,format=yuv420p[vout]"
    )
    subprocess.run([
        ffmpeg, "-y",
        *inputs,
        "-filter_complex", filter_complex,
        "-map", "[vout]",
        "-c:v", "libx264", "-crf", "23", "-preset", "medium", "-movflags", "+faststart",
        str(out_mp4),
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    size_mb = out_mp4.stat().st_size / (1024 * 1024)
    print(f"✓ Generated {out_mp4} ({size_mb:.2f} MB)")
    return out_mp4


def main() -> None:
    en_card = build_en_compare_card()
    build_zh_compare_card()
    build_15s_promo_video(en_card)


if __name__ == "__main__":
    main()
