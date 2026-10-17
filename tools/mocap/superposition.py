#!/usr/bin/env python3
"""overlay.py <annot.json> <dossier images> <sortie.png> [échelle] [x0,y0,x1,y1] : squelettes dessinés sur les images."""
import json, sys
from PIL import Image, ImageDraw
ann = json.load(open(sys.argv[1])); d = sys.argv[2]; out = sys.argv[3]
sc = float(sys.argv[4]) if len(sys.argv) > 4 else 0.5
box = tuple(map(int, sys.argv[5].split(","))) if len(sys.argv) > 5 else (0, 0, 960, 540)
BONES = [("H", "N"), ("N", "P"), ("P", "Kf"), ("Kf", "Af"), ("P", "Kn"), ("Kn", "An"), ("N", "Wf"), ("N", "Wn")]
tiles = []
for fr in ann["frames"]:
    im = Image.open(f"{d}/f{fr['f']:03d}.png").convert("RGB")
    dr = ImageDraw.Draw(im)
    dr.line([(0, ann["floor_y"]), (960, ann["floor_y"])], fill=(0, 200, 0), width=1)
    for who, col in (("tori", (255, 40, 40)), ("uke", (40, 120, 255))):
        a = fr[who]
        if a.get("lying"):
            dr.text((a["x_px"], 470), "COUCHÉ", fill=col)
            continue
        for p, q in BONES:
            far = p.endswith("f") or q.endswith("f")
            dr.line([tuple(a[p]), tuple(a[q])], fill=tuple(c // 2 for c in col) if far else col, width=2 if far else 4)
        dr.ellipse([a["H"][0] - 9, a["H"][1] - 9, a["H"][0] + 9, a["H"][1] + 9], outline=col, width=3)
    im = im.crop(box)
    im = im.resize((int(im.width * sc), int(im.height * sc)))
    ImageDraw.Draw(im).text((4, 4), f"f{fr['f']} p={fr.get('p', '')}", fill=(255, 255, 0))
    tiles.append(im)
cols = 5
w, h = tiles[0].size
sheet = Image.new("RGB", (cols * w, ((len(tiles) + cols - 1) // cols) * h))
for i, t in enumerate(tiles):
    sheet.paste(t, ((i % cols) * w, (i // cols) * h))
sheet.save(out)
