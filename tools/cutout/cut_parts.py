#!/usr/bin/env python3
"""Découpe une planche de morceaux de judoka (dessin de profil) en sprites pour l'animation
par découpage : chaque morceau (tête, buste, bras, avant-bras, mains, cuisse, tibia, pied) est
détouré, ses ouvertures grises (épaule, hanche, cou…) sont bouchées, et ses articulations sont
écrites dans parts.json. Une variante en judogi bleu est produite pour le joueur 2.

    python3 tools/cutout/cut_parts.py tools/cutout/homme_blanc.json assets/cutout/homme_blanc [--bleu assets/cutout/homme_bleu]

Le jeu (scripts/view/cutout.gd) pose chaque morceau entre deux articulations du squelette 2D.
"""
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image


def gi_to_blue(rgb, alpha):
    """Judogi blanc → bleu (mêmes ombres et plis) ; peau, cheveux, ceinture et encre inchangés."""
    im = rgb.astype(np.float32) / 255.0
    mx = im.max(axis=2)
    mn = im.min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    gi = np.clip((0.34 - sat) / 0.12, 0, 1) * np.clip((mx - 0.45) / 0.2, 0, 1)
    blue = np.array([0.13, 0.33, 0.86], dtype=np.float32)
    shade = (mx / 0.97) ** 1.4
    target = np.clip(blue[None, None, :] * shade[..., None] * 1.12 + 0.03 * shade[..., None], 0, 1)
    out = im * (1 - gi[..., None]) + target * gi[..., None]
    return (out * 255).astype(np.uint8)


def main():
    spec_path, out_dir = sys.argv[1], sys.argv[2]
    blue_dir = sys.argv[sys.argv.index("--bleu") + 1] if "--bleu" in sys.argv else None
    spec = json.load(open(spec_path))
    sheet = np.asarray(Image.open(spec["sheet"]).convert("RGB")).copy()
    h, w, _ = sheet.shape
    border = np.concatenate([sheet[:4].reshape(-1, 3), sheet[-4:].reshape(-1, 3), sheet[:, :4].reshape(-1, 3), sheet[:, -4:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    dist = np.abs(sheet.astype(int) - bg).max(axis=2)
    # fond = composante reliée au bord, proche de la couleur du fond
    near = (dist < 20).astype(np.uint8)
    n, lab = cv2.connectedComponents(near)
    edge_labels = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bgmask = np.isin(lab, list(edge_labels)) if edge_labels else np.zeros_like(near, bool)
    alpha = np.where(bgmask, 0.0, 1.0).astype(np.float32)
    # bords adoucis : fondu sur les pixels de fond qui touchent le dessin
    soft = np.clip((dist.astype(np.float32) - 6.0) / 14.0, 0, 1)
    ring = cv2.dilate((~bgmask).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    alpha = np.where(bgmask & ring, soft, alpha)
    fills = {"gi": spec.get("gi_fill", [240, 240, 246]), "skin": spec.get("skin_fill", [226, 158, 112])}
    os.makedirs(out_dir, exist_ok=True)
    if blue_dir:
        os.makedirs(blue_dir, exist_ok=True)
    meta = {"_doc": "Morceaux du judoka (pixels de chaque image) : A, B = articulations ; wpx / wu, scale : échelle. Généré par tools/cutout/cut_parts.py.", "parts": {}}
    for name, p in spec["parts"].items():
        x0, y0, x1, y1 = p["box"]
        rgb = sheet[y0:y1, x0:x1].copy()
        a = alpha[y0:y1, x0:x1].copy()
        if "clip" in p:
            m = np.zeros(a.shape, np.uint8)
            cv2.fillPoly(m, [np.array([[x - x0, y - y0] for x, y in p["clip"]], np.int32)], 1)
            m = cv2.GaussianBlur(m.astype(np.float32), (3, 3), 0)
            a *= m
        # bouche les ouvertures (ellipses grises des coupes) : remplissage par diffusion de couleur
        for sx, sy, kind in p.get("plugs", []):
            ff = rgb.copy()
            mask = np.zeros((rgb.shape[0] + 2, rgb.shape[1] + 2), np.uint8)
            cv2.floodFill(ff, mask, (sx - x0, sy - y0), (0, 0, 0), (16, 16, 16), (16, 16, 16), cv2.FLOODFILL_MASK_ONLY | cv2.FLOODFILL_FIXED_RANGE | (255 << 8))
            region = mask[1:-1, 1:-1] > 0
            region = cv2.dilate(region.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
            col = np.array(fills[kind], np.float32)
            # léger dégradé vertical pour ne pas faire un aplat mort
            yy = np.linspace(1.02, 0.94, rgb.shape[0])[:, None, None]
            rgb = np.where(region[..., None], np.clip(col[None, None, :] * yy, 0, 255).astype(np.uint8), rgb)
        # recadre au contenu
        ys, xs = np.where(a > 0.02)
        cx0, cy0, cx1, cy1 = max(xs.min() - 2, 0), max(ys.min() - 2, 0), min(xs.max() + 3, a.shape[1]), min(ys.max() + 3, a.shape[0])
        rgb = rgb[cy0:cy1, cx0:cx1]
        a = a[cy0:cy1, cx0:cx1]
        off = np.array([x0 + cx0, y0 + cy0], float)
        rgba = np.dstack([rgb, (a * 255).astype(np.uint8)])
        # la main qui saisit tient le judogi de l'adversaire : bleu pour le blanc, blanc pour le bleu
        wrgb = gi_to_blue(rgb, a) if (name == "fist" and blue_dir) else rgb
        Image.fromarray(np.dstack([wrgb, (a * 255).astype(np.uint8)]), "RGBA").save(os.path.join(out_dir, name + ".png"), optimize=True)
        if blue_dir:
            skinny = name in ("head", "fist", "foot")
            brgb = rgb if skinny else gi_to_blue(rgb, a)
            Image.fromarray(np.dstack([brgb, (a * 255).astype(np.uint8)]), "RGBA").save(os.path.join(blue_dir, name + ".png"), optimize=True)
        m = {"file": name + ".png", "A": (np.array(p["A"]) - off).tolist(), "B": (np.array(p["B"]) - off).tolist()}
        for k in ("wpx", "wu", "scale"):
            if k in p:
                m[k] = p[k]
        if "points" in p:
            m["points"] = {k: (np.array(v) - off).tolist() for k, v in p["points"].items()}
        meta["parts"][name] = m
        print(f"{name:13s} {rgba.shape[1]}×{rgba.shape[0]}")
    json.dump(meta, open(os.path.join(out_dir, "parts.json"), "w"), indent=1)
    if blue_dir:
        json.dump(meta, open(os.path.join(blue_dir, "parts.json"), "w"), indent=1)


main()
