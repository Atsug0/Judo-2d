#!/usr/bin/env python3
"""Planche de contrôle d'une annotation : le squelette repéré, posé sur les images.

    python3 tools/mocap/apercu.py tools/mocap/uchi_mata_annot.json /tmp/uchi.png
    python3 tools/mocap/apercu.py tools/mocap/*_annot.json --toutes /tmp/lot.png

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


def toutes(annots, sortie, par_tech=3):
    """Une seule planche pour tout un lot : quelques instants de chaque technique.

    C'est la relecture qui compte : on voit d'un coup d'œil quelle technique est tombée
    sur la bonne répétition et laquelle a besoin d'un --debut à la main.
    """
    lignes = []
    for a in annots:
        d = json.load(open(a))
        with tempfile.TemporaryDirectory() as t:
            subprocess.run(["ffmpeg", "-v", "error", "-i", d["source"], "-vf",
                            f"fps={d['fps']},scale=640:360", f"{t}/%05d.png"], check=True)
            noms = sorted(os.listdir(t))
            fr = d["frames"]
            sel = [fr[0], fr[len(fr) // 2], fr[-1]][:par_tech]
            tuiles = []
            for f in sel:
                im = Image.open(os.path.join(t, noms[f["f"]])).convert("RGB").resize((400, 225))
                g = ImageDraw.Draw(im)
                ech = 400.0 / 640.0
                for qui, col in COULEURS.items():
                    p = f[qui]
                    for s0, s1 in SEGMENTS:
                        g.line([(p[s0][0] * ech, p[s0][1] * ech),
                                (p[s1][0] * ech, p[s1][1] * ech)], fill=col, width=2)
                g.text((6, 6), f"{d['tech']}  p={f['p']:.2f}", fill=(255, 230, 0))
                tuiles.append(im)
            lignes.append(tuiles)
    larg = 400 * par_tech
    sheet = Image.new("RGB", (larg, 225 * len(lignes)), (20, 18, 30))
    for r, tuiles in enumerate(lignes):
        for c, im in enumerate(tuiles):
            sheet.paste(im, (c * 400, r * 225))
    sheet.save(sortie)
    return sortie


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--toutes" in sys.argv:
        print(toutes(args[:-1], args[-1]))
    else:
        out = args[1] if len(args) > 1 else "/tmp/apercu.png"
        print(planche(args[0], out))
