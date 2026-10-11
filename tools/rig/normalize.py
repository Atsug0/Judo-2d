#!/usr/bin/env python3
"""Normalise un modèle généré (TRELLIS, etc.) : pieds à y = -0,95 / tête à +0,95 (1,90 m centré,
comme les autres judokas), textures WebP réencodées en PNG, matériau non métallique.

    python3 tools/rig/normalize.py brut.glb propre.glb [--height 1.9]
"""
import io
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from glb_io import Builder, accessor, read_glb  # noqa: E402

src, dst = sys.argv[1], sys.argv[2]
H = float(sys.argv[sys.argv.index("--height") + 1]) if "--height" in sys.argv else 1.9
js, binary = read_glb(src)
mesh_node = next(n for n in js["nodes"] if "mesh" in n)
prim = js["meshes"][mesh_node["mesh"]]["primitives"][0]
P = accessor(js, binary, prim["attributes"]["POSITION"]).astype(np.float64)
N = accessor(js, binary, prim["attributes"]["NORMAL"]).astype(np.float64)
UV = accessor(js, binary, prim["attributes"]["TEXCOORD_0"]).astype(np.float32)
I = accessor(js, binary, prim["indices"]).astype(np.uint32)
k = H / (P[:, 1].max() - P[:, 1].min())
c = np.array([(P[:, 0].max() + P[:, 0].min()) / 2, P[:, 1].min(), np.median(P[:, 2])])
P = (P - c) * k
P[:, 1] -= H / 2
print(f"échelle ×{k:.3f}, boîte {P.min(0).round(3)} → {P.max(0).round(3)}")
B = Builder()
attrs = {"POSITION": B.add(P.astype(np.float32), "VEC3", 5126, 34962, minmax=True),
         "NORMAL": B.add(N.astype(np.float32), "VEC3", 5126, 34962),
         "TEXCOORD_0": B.add(UV, "VEC2", 5126, 34962)}
ind = B.add(I, "SCALAR", 5125, 34963)
mat = js["materials"][prim.get("material", 0)]
pbr = mat["pbrMetallicRoughness"]
t = js["textures"][pbr["baseColorTexture"]["index"]]
src_img = t.get("source", t.get("extensions", {}).get("EXT_texture_webp", {}).get("source"))
bv = js["bufferViews"][js["images"][src_img]["bufferView"]]
s0 = bv.get("byteOffset", 0)
pil = Image.open(io.BytesIO(binary[s0:s0 + bv["byteLength"]])).convert("RGB")
buf = io.BytesIO()
pil.save(buf, "PNG", compress_level=6)
B.add_image(buf.getvalue(), "image/png")   # seule la couleur de base est gardée
B.js["textures"] = [{"source": 0, "sampler": 0}]
B.js["samplers"] = [{"magFilter": 9729, "minFilter": 9987}]
B.js["materials"] = [{"name": "judoka", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0},
                      "metallicFactor": 0.0, "roughnessFactor": 0.9}, "doubleSided": True}]
B.js["meshes"] = [{"name": "corps", "primitives": [{"attributes": attrs, "indices": ind, "material": 0}]}]
B.js["nodes"] = [{"name": "Object_01", "mesh": 0}]
B.js["scenes"] = [{"nodes": [0]}]
B.js["scene"] = 0
B.save(dst)
print("écrit", dst)
