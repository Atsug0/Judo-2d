#!/usr/bin/env python3
"""grid.py <dossier> <x0,y0,x1,y1> <échelle> <image> [<image> ...] -> <dossier>_g.png
Images côte à côte, recadrées, quadrillage tous les 10 px (repères tous les 50), en pixels 960x540."""
import sys
from PIL import Image, ImageDraw
d = sys.argv[1]
x0, y0, x1, y1 = map(int, sys.argv[2].split(","))
s = float(sys.argv[3])
frames = sys.argv[4:]
tiles = []
for f in frames:
    im = Image.open(f"{d}/f{int(f):03d}.png").convert("RGB").crop((x0, y0, x1, y1))
    im = im.resize((int(im.width * s), int(im.height * s)))
    dr = ImageDraw.Draw(im, "RGBA")
    for x in range((x0 // 10 + 1) * 10, x1, 10):
        xx = (x - x0) * s; big = x % 50 == 0
        dr.line([(xx, 0), (xx, im.height)], fill=(0, 90, 255, 150 if big else 55))
        if big: dr.text((xx + 2, 2), str(x), fill=(0, 60, 255))
    for y in range((y0 // 10 + 1) * 10, y1, 10):
        yy = (y - y0) * s; big = y % 50 == 0
        dr.line([(0, yy), (im.width, yy)], fill=(255, 0, 0, 150 if big else 55))
        if big: dr.text((2, yy + 1), str(y), fill=(230, 0, 0))
    dr.rectangle([im.width - 40, 0, im.width, 16], fill=(255, 255, 0))
    dr.text((im.width - 36, 2), f"f{f}", fill=(0, 0, 0))
    tiles.append(im)
W = sum(t.width for t in tiles) + 6 * (len(tiles) - 1)
out = Image.new("RGB", (W, tiles[0].height), (255, 255, 255))
x = 0
for t in tiles:
    out.paste(t, (x, 0)); x += t.width + 6
out.save(d + "_g.png")
