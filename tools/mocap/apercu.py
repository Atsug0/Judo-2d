#!/usr/bin/env python3
"""Planche de contrôle d'une annotation : le squelette repéré, posé sur les images.

    python3 tools/mocap/apercu.py tools/mocap/uchi_mata_annot.json /tmp/uchi.png

À regarder avant de lancer le retargeting : c'est le seul moyen de voir si les points
suivent vraiment les judokas, et si tori et uke ne sont pas inversés.
"""
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

SEGMENTS = [("H", "N"), ("N", "P"), ("P", "Kn"), ("Kn", "An"),
            ("P", "Kf"), ("Kf", "Af"), ("N", "Wn"), ("N", "Wf")]
COULEURS = {"tori": (255, 70, 160), "uke": (70, 220, 255)}


def planche(annot, sortie, colonnes=5):
    d = json.load(open(annot))
    with tempfile.TemporaryDirectory() as t:
        # la cadence stockée est celle réellement obtenue à l'échantillonnage (voir
        # auto_annot.suivre) : l'utiliser telle quelle, sinon l'aperçu dérive
        subprocess.run(["ffmpeg", "-v", "error", "-i", d["source"], "-vf",
                        f"fps={d['fps']},scale=640:360", f"{t}/%05d.png"], check=True)
        noms = sorted(os.listdir(t))
        frames = d["frames"]
        pas = max(1, len(frames) // (colonnes * 2))
        sel = frames[::pas][:colonnes * 2]
        tuiles = []
        for fr in sel:
            im = Image.open(os.path.join(t, noms[fr["f"]])).convert("RGB")
            g = ImageDraw.Draw(im)
            for qui, col in COULEURS.items():
                p = fr[qui]
                for a, b in SEGMENTS:
                    g.line([tuple(p[a]), tuple(p[b])], fill=col, width=3)
                for k in ("H", "N", "P", "Kn", "An", "Kf", "Af", "Wn", "Wf"):
                    x, y = p[k]
                    g.ellipse([x - 3, y - 3, x + 3, y + 3], fill=col)
                g.text((p["H"][0] - 12, p["H"][1] - 24), qui, fill=col)
            g.text((8, 8), f"p={fr['p']:.2f}", fill=(255, 255, 0))
            tuiles.append(im)
    lignes = (len(tuiles) + colonnes - 1) // colonnes
    sheet = Image.new("RGB", (640 * colonnes, 360 * lignes))
    for i, im in enumerate(tuiles):
        sheet.paste(im, ((i % colonnes) * 640, (i // colonnes) * 360))
    sheet.save(sortie)
    return sortie


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out = sys.argv[2] if len(sys.argv) > 2 else "/tmp/apercu.png"
    print(planche(sys.argv[1], out))
