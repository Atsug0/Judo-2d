#!/usr/bin/env python3
"""Rend toutes les animations listées dans tools/blender/render_list.json.

    python3 tools/blender/batch_render.py [--blender /chemin/vers/blender] [--only seoi]

render_list.json :
[
  {"blend": "scenes/seoi_nage.blend", "anim": "throw/seoi_nage", "character": "hugo_blanc",
   "uke_character": "kenji_bleu", "start": 40, "end": 112, "frames": 12},
  {"blend": "scenes/garde.blend", "anim": "idle", "character": "hugo_blanc", "frames": 8, "loop": true}
]
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--blender", default=shutil.which("blender") or "blender")
    ap.add_argument("--list", default=str(ROOT / "tools" / "blender" / "render_list.json"))
    ap.add_argument("--only", default="", help="ne rend que les animations contenant ce texte")
    a = ap.parse_args()
    jobs = json.loads(Path(a.list).read_text(encoding="utf-8"))
    script = ROOT / "tools" / "blender" / "render_sprites.py"
    failed = 0
    for j in jobs:
        if a.only and a.only not in j["anim"]:
            continue
        cmd = [a.blender, str(ROOT / j["blend"]), "--background", "--python", str(script), "--",
               "--anim", j["anim"], "--character", j["character"], "--frames", str(j.get("frames", 12))]
        if j.get("uke_character"):
            cmd += ["--uke-character", j["uke_character"]]
        for key in ("start", "end"):
            if key in j:
                cmd += [f"--{key}", str(j[key])]
        if j.get("loop"):
            cmd += ["--loop"]
        print("→", j["anim"])
        r = subprocess.run(cmd)
        if r.returncode != 0:
            failed += 1
            print("   ÉCHEC", file=sys.stderr)
    print("Terminé" + (f" avec {failed} échec(s)" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
