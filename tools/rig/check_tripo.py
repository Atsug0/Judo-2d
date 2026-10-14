#!/usr/bin/env python3
"""Vérifie qu'un .glb riggé sorti de Tripo est exploitable par le jeu.

Trois défauts ont été observés sur les exports Tripo, tous invisibles à l'œil dans un
visualiseur qui affiche le modèle au repos :

  1. os sans transformation : les nœuds du squelette n'ont ni translation ni rotation
     (tout le squelette est tassé à l'origine) — le modèle s'affiche déformé dès qu'on
     le pose ;
  2. peau morte : la quasi-totalité des sommets est accrochée au bassin, le reste du
     squelette ne déforme rien ;
  3. fin de fichier écrasée : la zone binaire des « inverse bind matrices » contient du
     texte JSON (téléchargement tronqué) — les matrices sont singulières.

Un export sain a ~65 os transformés, moins de 20 % des sommets dominés par le bassin,
et global(os) × inverse_bind(os) = identité.

    python3 tools/rig/check_tripo.py "new asset"/*.glb
"""
import json
import struct
import sys
from collections import Counter

CT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2),
      5125: ("I", 4), 5126: ("f", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    """Renvoie (json, octets du fichier, offset du chunk binaire)."""
    d = open(path, "rb").read()
    magic, _, total = struct.unpack_from("<4sII", d, 0)
    if magic != b"glTF":
        raise ValueError("pas un .glb")
    jlen = struct.unpack_from("<I", d, 12)[0]
    return json.loads(d[20:20 + jlen]), d, 20 + jlen + 8


def accessor(js, d, binoff, i):
    """Lit l'accesseur i sous forme de liste de tuples."""
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    fmt, sz = CT[a["componentType"]]
    n = NC[a["type"]]
    base = binoff + bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride") or n * sz
    return [struct.unpack_from("<%d%s" % (n, fmt), d, base + stride * k)
            for k in range(a["count"])]


def trs(node):
    """Transformation locale d'un nœud glTF, en matrice 4×4 (lignes)."""
    t = node.get("translation", [0, 0, 0])
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    s = node.get("scale", [1, 1, 1])
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[r[i][j] * s[j] for j in range(3)] + [t[i]] for i in range(3)] + [[0, 0, 0, 1]]


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def globals_of(js):
    """Transformation globale de chaque nœud (matrices 4×4)."""
    nodes = js["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    out = {}

    def g(i):
        if i not in out:
            m = trs(nodes[i])
            out[i] = matmul(g(parent[i]), m) if i in parent else m
        return out[i]

    for i in range(len(nodes)):
        g(i)
    return out, parent


def check(path):
    js, d, binoff = read_glb(path)
    name = path.rsplit("/", 1)[-1]
    faults = []
    if not js.get("skins"):
        return name, ["aucun squelette (modèle non riggé)"], {}
    skin = js["skins"][0]
    joints = skin["joints"]
    nodes = js["nodes"]

    # 1. os sans transformation
    posed = sum(1 for n in nodes
                if "translation" in n or "rotation" in n or "matrix" in n)
    if posed < len(joints) * 0.8:
        faults.append(f"os sans transformation : {posed}/{len(nodes)} nœuds transformés "
                      "(squelette tassé à l'origine)")

    # 2. fin de fichier écrasée / matrices singulières
    ibm = accessor(js, d, binoff, skin["inverseBindMatrices"])
    singular = sum(1 for m in ibm if abs(m[0] * m[5] * m[10]) < 1e-9 and
                   max(abs(v) for v in m) > 1e6 or all(v == 0.0 for v in m[:12]))
    if singular:
        faults.append(f"inverse bind matrices corrompues : {singular}/{len(ibm)} "
                      "(fin de fichier écrasée par du texte)")

    # 3. peau morte : part des sommets dont l'os dominant est le bassin
    prim = js["meshes"][0]["primitives"][0]
    jj = accessor(js, d, binoff, prim["attributes"]["JOINTS_0"])
    ww = accessor(js, d, binoff, prim["attributes"]["WEIGHTS_0"])
    names = [nodes[j].get("name", "") for j in joints]
    dom = Counter()
    for a, b in zip(jj, ww):
        dom[names[a[max(range(len(b)), key=lambda k: b[k])]]] += 1
    hips = next((n for n in names if n.endswith("Hips")), "")
    share = dom[hips] / max(1, len(jj))
    if share > 0.30:
        faults.append(f"peau morte : {share * 100:.0f} % des sommets accrochés au bassin "
                      "(le reste du squelette ne déforme rien)")

    # cohérence globale × inverse bind (seulement si le squelette est transformé)
    stats = {"os": len(joints), "sommets": len(jj), "bassin%": round(share * 100, 1)}
    if posed >= len(joints) * 0.8 and not singular:
        gl, _ = globals_of(js)
        worst = 0.0
        for k, j in enumerate(joints):
            a = gl[j]
            b = [[ibm[k][c * 4 + r] for c in range(4)] for r in range(4)]
            p = matmul(a, b)
            worst = max(worst, max(abs(p[r][c] - (1.0 if r == c else 0.0))
                                   for r in range(4) for c in range(4)))
        stats["écart repos"] = round(worst, 5)
        if worst > 1e-3:
            faults.append(f"pose de repos incohérente (écart {worst:.4f})")
    return name, faults, stats


if __name__ == "__main__":
    files = sys.argv[1:]
    if not files:
        sys.exit(__doc__)
    bad = 0
    for p in files:
        name, faults, stats = check(p)
        info = " ".join(f"{k}={v}" for k, v in stats.items())
        if faults:
            bad += 1
            print(f"✗ {name:24s} {info}")
            for f in faults:
                print(f"    - {f}")
        else:
            print(f"✓ {name:24s} {info}")
    print(f"\n{len(files) - bad}/{len(files)} modèles exploitables")
    sys.exit(1 if bad else 0)
