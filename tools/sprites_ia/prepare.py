#!/usr/bin/env python3
"""Sprites générés par IA (fond gris uni) → sprites du jeu.

Détoure chaque image (fond et ligne de sol retirés), repère la plante du pied d'appui
(point d'ancrage) et la ceinture (échelle), recadre, et écrit un manifeste lu par le combat.

    python3 tools/sprites_ia/prepare.py rushes/sprites_ia uchi_mata tori 40:tori_40_v1.png 42:tori_42_v1.png ...

Sortie : <dossier>/<tech>_<role>/<image>.png et manifest.json (p de l'animation, ancrage, échelle).
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

# image clé de la vidéo → avancement de la chorégraphie (data/anims/<tech>.json)
src_dir, tech, role = sys.argv[1], sys.argv[2], sys.argv[3]
anim = json.load(open(os.path.join(os.path.dirname(__file__), "..", "..", "data", "anims", tech + ".json")))
P_OF = {k["frame"]: k["p"] for k in anim["keys"]}
out_dir = os.path.join(src_dir, f"{tech}_{role}")
os.makedirs(out_dir, exist_ok=True)
frames = []
for spec in sys.argv[4:]:
    key, name = spec.split(":", 1)
    key = int(key)
    rgb = Image.open(os.path.join(src_dir, name)).convert("RGB")
    im = np.asarray(rgb).astype(np.int32)
    bg = np.median(np.concatenate([im[:6].reshape(-1, 3), im[:, :6].reshape(-1, 3), im[:, -6:].reshape(-1, 3)]), axis=0)
    cand = np.abs(im - bg).sum(axis=2) < 30
    sat = im.max(axis=2) - im.min(axis=2)
    line = (sat < 16) & (im.mean(axis=2) < 175) & (im.mean(axis=2) > 80)
    rows = np.where(line.mean(axis=1) > 0.4)[0]
    cand[rows] |= line[rows]
    lab, _ = ndimage.label(cand)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    for r in rows:   # la ligne de sol coupe parfois le fond en deux
        edge |= set(np.unique(lab[r])) - {0}
    body = ~np.isin(lab, list(edge))
    body = ndimage.binary_opening(body, iterations=1)
    lab2, n2 = ndimage.label(body)
    if n2 > 1:  # garde la silhouette principale
        sizes = ndimage.sum(body, lab2, range(1, n2 + 1))
        body = lab2 == (1 + int(np.argmax(sizes)))
    alpha = Image.fromarray((body * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))
    rgba = rgb.convert("RGBA")
    rgba.putalpha(alpha)
    ys, xs = np.nonzero(body)
    # ancrage : plante du pied d'appui (pixels les plus bas)
    low = ys.max()
    sole_x = float(xs[ys >= low - 6].mean())
    # ceinture : grande tache sombre au milieu de la silhouette (contours fins retirés)
    dark = (im.max(axis=2) < 70) & body
    dark = ndimage.binary_opening(dark, iterations=5)
    dl, dn = ndimage.label(dark)
    cy, cx = ys.mean(), xs.mean()
    best, bd = None, 1e18
    for i in range(1, dn + 1):
        yy, xx = np.nonzero(dl == i)
        if len(yy) < 300:
            continue
        d = (yy.mean() - cy) ** 2 + (xx.mean() - cx) ** 2
        if d < bd:
            bd, best = d, (float(xx.mean()), float(yy.mean()))
    x0, y0, x1, y1 = rgba.getbbox()
    rgba.crop((x0, y0, x1, y1)).save(os.path.join(out_dir, f"{key}.png"))
    frames.append({"key": key, "p": P_OF[key], "file": f"{key}.png", "pivot": [sole_x - x0, float(low - y0)],
                   "belt": [best[0] - x0, best[1] - y0] if best else None, "faces": "left"})
    print(key, "ancrage", frames[-1]["pivot"], "ceinture", frames[-1]["belt"], "taille", (x1 - x0, y1 - y0))
frames.sort(key=lambda f: f["p"])
json.dump({"tech": tech, "role": role, "frames": frames}, open(os.path.join(out_dir, "manifest.json"), "w"), indent=1)
