#!/usr/bin/env python3
"""Sort les images à annoter à la main, pour l'éditeur de rotoscopie.

    python3 tools/mocap/extraire.py seoi_nage
    python3 tools/mocap/extraire.py uchi_mata --debut 5.2 --duree 1.8 --fps 12

Écrit `rushes/decoupe/<technique>/00001.png…`, qu'on dépose ensuite dans
`tools/mocap/editeur.html`.

Sans `--debut`, le passage est repris de l'annotation automatique existante
(`tools/mocap/<technique>_annot.json`) : elle trouve correctement **quelle** projection
retenir et **quand**, c'est le placement des articulations qu'elle rate quand les corps
s'emmêlent. Autant partir de son repérage.

Douze images par seconde suffisent : l'annotation d'origine en utilisait treize pour un
uchi-mata entier, et le jeu interpole entre les clés.
"""
import json
import os
import shutil
import subprocess
import sys

RACINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")


def passage(tech):
    """(début, durée) en secondes, repris de l'annotation automatique."""
    f = os.path.join(RACINE, "tools", "mocap", tech + "_annot.json")
    if not os.path.exists(f):
        return None
    d = json.load(open(f))
    fps = float(d["fps"])
    frames = d["frames"]
    return float(d["start_s"]), (frames[-1]["f"] - frames[0]["f"]) / fps


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__)
    tech = args[0]
    opt = {}
    for k in ("--debut", "--duree", "--fps"):
        if k in sys.argv:
            opt[k] = float(sys.argv[sys.argv.index(k) + 1])

    video = os.path.join(RACINE, "rushes", "efficientjudo", tech + ".mp4")
    if not os.path.exists(video):
        sys.exit(f"vidéo absente : {video}")

    auto = passage(tech)
    debut = opt.get("--debut", auto[0] if auto else 0.0)
    duree = opt.get("--duree", auto[1] if auto else 2.0)
    fps = opt.get("--fps", 12.0)

    dest = os.path.join(RACINE, "rushes", "decoupe", tech)
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest)
    subprocess.run(["ffmpeg", "-v", "error", "-ss", str(debut), "-t", str(duree),
                    "-i", video, "-vf", f"fps={fps},scale=640:360",
                    os.path.join(dest, "%05d.png")], check=True)
    n = len(os.listdir(dest))
    print(f"{n} images de {debut:.1f} s à {debut + duree:.1f} s "
          f"({fps:.0f} i/s) → {os.path.relpath(dest, RACINE)}")
    print("Ouvre tools/mocap/editeur.html et dépose ces images.")
