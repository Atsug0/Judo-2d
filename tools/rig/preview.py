#!/usr/bin/env python3
"""Rendu logiciel d'un judoka du jeu, pour vérifier un rig sans lancer Godot.

    python3 tools/rig/preview.py assets/judokas/colosse --out /tmp/colosse.png
    python3 tools/rig/preview.py assets/judokas/colosse --pose garde --vue cote

Charge `rig.glb` + `joints.json`, applique une pose de contrôle (rotations d'os en
degrés), déforme la peau et dessine le modèle en projection orthographique avec un
tampon de profondeur et un éclairage lambertien. Sortie PNG (zlib de la bibliothèque
standard : ni numpy ni Pillow requis).

Poses de contrôle : `repos` (pose T), `garde` (jambes fléchies, bras en avant),
`torsion` (buste vrillé) — elles ne servent qu'à vérifier que chaque os déforme bien
la zone attendue, le jeu pose le rig lui-même (scripts/view/rig_pose.gd).
"""
import json
import math
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_tripo import accessor, read_glb  # noqa: E402

# pose de contrôle : os → (axe, degrés)
POSES = {
    "repos": {},
    "garde": {
        "thigh.L": ("x", -35), "shin.L": ("x", 55), "foot.L": ("x", -20),
        "thigh.R": ("x", -25), "shin.R": ("x", 45), "foot.R": ("x", -20),
        "upper_arm.L": ("z", -70), "forearm.L": ("y", -55),
        "upper_arm.R": ("z", 70), "forearm.R": ("y", 55),
        "spine": ("x", 12), "chest": ("x", 8), "neck": ("x", -10),
    },
    "torsion": {"spine": ("y", 25), "spine2": ("y", 20), "chest": ("y", 20),
                "upper_arm.L": ("z", -80), "upper_arm.R": ("z", 80)},
}


def axis_rot(axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    if axis == "x":
        return [[1, 0, 0], [0, c, -s], [0, s, c]]
    if axis == "y":
        return [[c, 0, s], [0, 1, 0], [-s, 0, c]]
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


def mul3(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def app(m, v):
    return [sum(m[i][j] * v[j] for j in range(3)) for i in range(3)]


def skin(path, pose_name):
    js, d, binoff = read_glb(os.path.join(path, "rig.glb"))
    spec = json.load(open(os.path.join(path, "joints.json")))
    bones = spec["bones"]
    J = spec["joints"]
    prim = js["meshes"][0]["primitives"][0]
    P = accessor(js, d, binoff, prim["attributes"]["POSITION"])
    N = accessor(js, d, binoff, prim["attributes"]["NORMAL"])
    JA = accessor(js, d, binoff, prim["attributes"]["JOINTS_0"])
    WA = accessor(js, d, binoff, prim["attributes"]["WEIGHTS_0"])
    IDX = [v[0] for v in accessor(js, d, binoff, prim["indices"])]
    order = [b[0] for b in bones]
    parent = {b[0]: b[3] for b in bones}
    rest = {b[0]: J[b[1]] for b in bones}

    local = POSES[pose_name]
    R, T = {}, {}
    for b in order:                              # global = parent ∘ local, pivot = tête de l'os
        r = axis_rot(*local[b]) if b in local else [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        p = parent[b]
        if p == "":
            R[b] = r
            T[b] = rest[b]
        else:
            R[b] = mul3(R[p], r)
            off = [rest[b][i] - rest[p][i] for i in range(3)]
            T[b] = [T[p][i] + app(R[p], off)[i] for i in range(3)]
    V, VN = [], []
    for v, n, ja, wa in zip(P, N, JA, WA):
        acc = [0.0, 0.0, 0.0]
        nrm = [0.0, 0.0, 0.0]
        for a, w in zip(ja, wa):
            if w <= 0:
                continue
            b = order[a]
            rel = [v[i] - rest[b][i] for i in range(3)]
            q = app(R[b], rel)
            nq = app(R[b], n)
            for i in range(3):
                acc[i] += w * (T[b][i] + q[i])
                nrm[i] += w * nq[i]
        V.append(acc)
        VN.append(nrm)
    return V, VN, IDX


def render(V, VN, IDX, view, w=420, h=620):
    """Projection orthographique + tampon de profondeur, éclairage lambertien."""
    if view == "cote":          # caméra sur +X : profil, le judoka regarde la droite
        proj = lambda p: (p[2], p[1], p[0])
    elif view == "dos":         # caméra sur −Z, derrière lui
        proj = lambda p: (-p[0], p[1], -p[2])
    else:                        # face : caméra sur +Z, il nous regarde
        proj = lambda p: (p[0], p[1], p[2])
    pts = [proj(v) for v in V]
    lo = [min(p[i] for p in pts) for i in range(2)]
    hi = [max(p[i] for p in pts) for i in range(2)]
    pad = 0.08
    k = min(w * (1 - 2 * pad) / max(1e-6, hi[0] - lo[0]),
            h * (1 - 2 * pad) / max(1e-6, hi[1] - lo[1]))
    cx = (hi[0] + lo[0]) / 2
    cy = (hi[1] + lo[1]) / 2
    scr = [((p[0] - cx) * k + w / 2, h / 2 - (p[1] - cy) * k, p[2]) for p in pts]
    buf = bytearray(w * h * 3)
    for i in range(0, len(buf), 3):          # fond : bleu nuit du jeu (#161131)
        buf[i], buf[i + 1], buf[i + 2] = 0x16, 0x11, 0x31
    zb = [-1e9] * (w * h)
    light = (-0.35, 0.55, 0.75)
    ln = math.sqrt(sum(c * c for c in light))
    for t in range(0, len(IDX) - 2, 3):
        a, b, c = IDX[t], IDX[t + 1], IDX[t + 2]
        x0, y0, z0 = scr[a]
        x1, y1, z1 = scr[b]
        x2, y2, z2 = scr[c]
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-9:
            continue
        n = [sum(VN[v][i] for v in (a, b, c)) / 3 for i in range(3)]
        nn = math.sqrt(sum(x * x for x in n)) or 1.0
        lam = max(0.0, sum(n[i] * light[i] for i in range(3)) / (nn * ln))
        sh = 0.42 + 0.58 * lam ** 0.7
        col = (int(235 * sh), int(238 * sh), int(248 * sh))
        xa, xb = int(max(0, min(x0, x1, x2))), int(min(w - 1, max(x0, x1, x2)))
        ya, yb = int(max(0, min(y0, y1, y2))), int(min(h - 1, max(y0, y1, y2)))
        for py in range(ya, yb + 1):
            for px in range(xa, xb + 1):
                fx, fy = px + 0.5, py + 0.5
                w0 = ((x1 - fx) * (y2 - fy) - (x2 - fx) * (y1 - fy)) / area
                w1 = ((x2 - fx) * (y0 - fy) - (x0 - fx) * (y2 - fy)) / area
                w2 = 1.0 - w0 - w1
                if w0 < 0 or w1 < 0 or w2 < 0:
                    continue
                z = w0 * z0 + w1 * z1 + w2 * z2
                o = py * w + px
                if z > zb[o]:
                    zb[o] = z
                    buf[o * 3:o * 3 + 3] = bytes(col)
    return buf, w, h


def png(buf, w, h, path):
    raw = b"".join(b"\0" + bytes(buf[y * w * 3:(y + 1) * w * 3]) for y in range(h))
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    out = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 6))
           + chunk(b"IEND", b""))
    open(path, "wb").write(out)


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    src = a[0]
    pose = a[a.index("--pose") + 1] if "--pose" in a else "garde"
    view = a[a.index("--vue") + 1] if "--vue" in a else "face"
    out = a[a.index("--out") + 1] if "--out" in a else "/tmp/preview.png"
    V, VN, IDX = skin(src, pose)
    buf, w, h = render(V, VN, IDX, view)
    png(buf, w, h, out)
    print(f"{out} ({pose}, vue {view})")
