#!/usr/bin/env python3
"""Allège un judoka riggé (.glb) pour l'afficher en temps réel dans le jeu : regroupement
des sommets (voxels + coordonnées de texture, pour garder les coutures), poids de peau
moyennés, textures réduites.

    python3 tools/rig/decimate.py judoka_rig.glb judoka_jeu.glb --voxel 0.009 --tex 2048
"""
import argparse
import io
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from glb_io import Builder, accessor, read_glb  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("dst")
ap.add_argument("--voxel", type=float, default=0.009)
ap.add_argument("--uvq", type=float, default=96.0)
ap.add_argument("--tex", type=int, default=2048)
a = ap.parse_args()

js, binary = read_glb(a.src)
prim = js["meshes"][0]["primitives"][0]
at = prim["attributes"]
P = accessor(js, binary, at["POSITION"]).astype(np.float64)
N = accessor(js, binary, at["NORMAL"]).astype(np.float64)
UV = accessor(js, binary, at["TEXCOORD_0"]).astype(np.float64)
Jo = accessor(js, binary, at["JOINTS_0"]).astype(np.int64)
We = accessor(js, binary, at["WEIGHTS_0"]).astype(np.float64)
I = accessor(js, binary, prim["indices"]).astype(np.int64)
nb = len(js["skins"][0]["joints"])

key = np.concatenate([np.floor(P / a.voxel), np.floor(UV * a.uvq)], axis=1).astype(np.int64)
_, cl, cnt = np.unique(key, axis=0, return_inverse=True, return_counts=True)
cl = cl.ravel()
n = cnt.size


def avg(x):
    out = np.zeros((n, x.shape[1]))
    np.add.at(out, cl, x)
    return out / cnt[:, None]


P2, UV2 = avg(P), avg(UV)
N2 = avg(N)
N2 /= np.linalg.norm(N2, axis=1, keepdims=True) + 1e-9
dense = np.zeros((len(P), nb))
np.put_along_axis(dense, Jo, We, axis=1)
W2 = avg(dense)
top = np.argsort(-W2, axis=1)[:, :4]
tw = np.take_along_axis(W2, top, axis=1)
tw /= tw.sum(axis=1, keepdims=True) + 1e-12
T = cl[I.reshape(-1, 3)]
ok = (T[:, 0] != T[:, 1]) & (T[:, 1] != T[:, 2]) & (T[:, 0] != T[:, 2])
T = T[ok]
T = np.unique(np.sort(T, axis=1), axis=0, return_index=True)[1]
T = cl[I.reshape(-1, 3)][ok][np.sort(T)]
print(f"sommets {len(P)} → {n}, triangles {len(I) // 3} → {len(T)}")

B = Builder()
attrs = {"POSITION": B.add(P2.astype(np.float32), "VEC3", 5126, 34962, minmax=True),
         "NORMAL": B.add(N2.astype(np.float32), "VEC3", 5126, 34962),
         "TEXCOORD_0": B.add(UV2.astype(np.float32), "VEC2", 5126, 34962),
         "JOINTS_0": B.add(top.astype(np.uint16), "VEC4", 5123, 34962),
         "WEIGHTS_0": B.add(tw.astype(np.float32), "VEC4", 5126, 34962)}
ind = B.add(T.astype(np.uint32).ravel(), "SCALAR", 5125, 34963)
for im in js.get("images", []):
    bv = js["bufferViews"][im["bufferView"]]
    s0 = bv.get("byteOffset", 0)
    img = Image.open(io.BytesIO(binary[s0:s0 + bv["byteLength"]]))
    if max(img.size) > a.tex:
        img = img.resize((a.tex, a.tex), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "PNG", compress_level=6)
    B.add_image(buf.getvalue(), "image/png")
for k in ("samplers", "textures", "materials", "nodes", "skins", "scenes", "scene", "extras"):
    if k in js:
        B.js[k] = js[k]
# matrices de liaison inverses : recopiées
inv_src = js["skins"][0]["inverseBindMatrices"]
B.js["skins"] = [dict(js["skins"][0], inverseBindMatrices=B.add(accessor(js, binary, inv_src).astype(np.float32), "MAT4", 5126))]
B.js["meshes"] = [{"name": "corps", "primitives": [{"attributes": attrs, "indices": ind, "material": prim.get("material", 0)}]}]
B.save(a.dst)
print("écrit", a.dst)
