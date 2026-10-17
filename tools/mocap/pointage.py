#!/usr/bin/env python3
"""Pointage à la main d'un clip de projection (clips/<tech>.mp4) → annotation pour retarget.py.

Le pointage (tools/mocap/main/<tech>.json) est fait sur les images d'origine du clip, en
pixels 1920×1080 : uke (judogi foncé) à gauche, tori (blanc) à droite, comme Efficient Judo
filme. Le jeu veut tori à gauche, regard vers la droite : on retourne donc l'image
(x → largeur − x) et le sens du regard. Les membres « près / loin » de la caméra ne
changent pas avec le retournement.

    python3 tools/mocap/pointage.py tools/mocap/main/seoi_nage.json   → tools/mocap/seoi_nage_annot.json
    python3 tools/mocap/retarget.py tools/mocap/seoi_nage_annot.json  → data/anims/seoi_nage.json

Format de main/<tech>.json : {"tech", "clip", "fps", "width", "floor_y", "hip_height_px",
"frames": {"<n° d'image>": {"p"?: avancement, "tori": {...}, "uke": {...}}}} ; points H tête,
N base du cou, P bassin, Kn/An genou/cheville côté caméra, Kf/Af côté opposé, Wn/Wf poignets ;
face +1 = regarde vers la droite DANS LE CLIP ; uke couché : {"lying": true, "x_px", "y_units",
"rot"} (rot dans le repère du jeu, après retournement).
Les clés sans "p" reçoivent un avancement proportionnel au temps entre les clés qui en ont un.
"""
import json
import os
import sys

POINTS = ["H", "N", "P", "Kn", "An", "Kf", "Af", "Wn", "Wf"]


def main():
    src = sys.argv[1]
    d = json.load(open(src))
    W = d.get("width", 1920)
    frames = []
    for k in sorted(d["frames"], key=int):
        fr = d["frames"][k]
        out = {"f": int(k)}
        if "p" in fr:
            out["p"] = fr["p"]
        for who in ("tori", "uke"):
            a = fr[who]
            if a.get("lying"):
                b = dict(a)
                b["x_px"] = W - a["x_px"]
            else:
                b = {"face": -a["face"]}
                for pt in POINTS:
                    b[pt] = [W - a[pt][0], a[pt][1]]
                for extra in ("lift",):
                    if extra in a:
                        b[extra] = a[extra]
            out[who] = b
        frames.append(out)
    ann = {
        "_doc": f"Pointage à la main de {d['clip']} (tools/mocap/main/{d['tech']}.json), image retournée : tori à gauche.",
        "source": d["clip"], "miroir": True, "start_s": 0.0, "fps": d["fps"],
        "floor_y": d["floor_y"], "hip_height_px": d["hip_height_px"], "tech": d["tech"], "frames": frames,
    }
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), d["tech"] + "_annot.json")
    json.dump(ann, open(dst, "w"), indent=1)
    print("écrit", os.path.relpath(dst), len(frames), "images")


main()
