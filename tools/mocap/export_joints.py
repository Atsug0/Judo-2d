#!/usr/bin/env python3
"""Exporte les articulations 3D (mètres) de chaque image clé d'une chorégraphie filmée,
pour l'aperçu 3D (preview3d.gd) ou une visionneuse web.

    python3 tools/mocap/export_joints.py data/anims/uchi_mata.json sortie.json
"""
import json
import os
import sys

src = open(os.path.join(os.path.dirname(__file__), "..", "blender", "import_mocap.py")).read()
ns = {}
exec(compile(src.replace("\nmain()\n", "\n"), "import_mocap", "exec"), ns)
data = json.load(open(sys.argv[1]))
f0 = data["keys"][0]["frame"]
out = [{"t": round((k["frame"] - f0) / 12, 4),
        "tori": {n: list(v) for n, v in ns["joints"](k["tori"]).items()},
        "uke": {n: list(v) for n, v in ns["joints"](k["uke"]).items()}} for k in data["keys"]]
json.dump(out, open(sys.argv[2], "w"), separators=(",", ":"))
print(len(out), "images clés →", sys.argv[2])
