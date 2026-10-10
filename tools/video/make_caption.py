#!/usr/bin/env python3
"""Génère un bandeau de légende PNG transparent dans la DA du jeu (panneau incliné,
contour d'encre, ombre portée, texte italique noir) pour le montage vidéo.

    python3 tools/video/make_caption.py "KUMIKATA" "Bataille de mains, domination" out.png [couleur]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
INK = (11, 10, 20, 255)
COLORS = {"hot": (255, 46, 136, 255), "p1": (255, 210, 63, 255), "p2": (61, 231, 255, 255), "gold": (255, 194, 26, 255)}


def slant(x, y, w, h, s=0.22):
    o = h * s
    return [(x + o, y), (x + w, y), (x + w - o, y + h), (x, y + h)]


def main():
    title, sub, out = sys.argv[1], sys.argv[2], sys.argv[3]
    col = COLORS.get(sys.argv[4] if len(sys.argv) > 4 else "hot", COLORS["hot"])
    ft = ImageFont.truetype(os.path.join(ROOT, "fonts", "InterDisplay-BlackItalic.otf"), 54)
    fs = ImageFont.truetype(os.path.join(ROOT, "fonts", "Inter-Black.otf"), 24)
    tw = ft.getbbox(title)[2]
    sw = fs.getbbox(sub.upper())[2] if sub else 0
    w = max(tw, sw) + 120
    h_t, h_s = 78, 42 if sub else 0
    img = Image.new("RGBA", (w + 30, h_t + h_s + 40), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # ombre puis panneau du titre
    d.polygon(slant(14, 14, tw + 90, h_t), fill=INK)
    d.polygon(slant(4, 4, tw + 90, h_t), fill=col, outline=INK)
    d.line(slant(4, 4, tw + 90, h_t) + [slant(4, 4, tw + 90, h_t)[0]], fill=INK, width=5)
    # texte avec contour
    d.text((40, 12), title, font=ft, fill=INK, stroke_width=0)
    d.text((38, 10), title, font=ft, fill=(11, 10, 20, 255))
    if sub:
        y = h_t + 6
        d.polygon(slant(30, y + 6, sw + 50, h_s - 6), fill=INK)
        d.polygon(slant(24, y, sw + 50, h_s - 6), fill=(22, 17, 49, 255))
        d.line(slant(24, y, sw + 50, h_s - 6) + [slant(24, y, sw + 50, h_s - 6)[0]], fill=col, width=3)
        d.text((52, y + 4), sub.upper(), font=fs, fill=col)
    img.save(out)


if __name__ == "__main__":
    main()
