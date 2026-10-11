#!/usr/bin/env python3
"""Rig automatique d'un judoka 3D statique (.glb sans squelette).

    python3 tools/rig/autorig.py model.glb tools/rig/judoka_joints.json sortie_riggee.glb

1. Redresse le maillage (transformation du nœud appliquée aux sommets).
2. Pose un squelette humain (articulations lues dans le JSON, en mètres, Y vers le haut,
   personnage tourné vers +Z, sa gauche vers +X).
3. Calcule les poids de peau par diffusion sur la surface (fonctions harmoniques) : un
   sommet suit les os auxquels il est relié par la surface, pas seulement les plus
   proches dans l'espace (la main ne colle pas à la cuisse).
4. Écrit un .glb skinné (os, poids, textures d'origine), lisible par Godot ou Blender.
"""
import json
import sys

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.linalg import splu

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from glb_io import Builder, accessor, read_glb  # noqa: E402

VOXEL = 0.012


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(1e-9, ab @ ab), 0.0, 1.0)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


_TEX = {}


def tex_color(js, binary, prim, UV):
    """Couleur de la texture de base sous chaque sommet (0..1)."""
    import io
    from PIL import Image
    if "c" in _TEX:
        return _TEX["c"]
    mat = js["materials"][prim.get("material", 0)]
    tex = js["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]
    im = js["images"][tex["source"]]
    bv = js["bufferViews"][im["bufferView"]]
    s0 = bv.get("byteOffset", 0)
    img = np.asarray(Image.open(io.BytesIO(binary[s0:s0 + bv["byteLength"]])).convert("RGB")).astype(np.float32) / 255.0
    h, w = img.shape[:2]
    px = np.clip((UV[:, 0] % 1.0) * w, 0, w - 1).astype(int)
    py = np.clip((UV[:, 1] % 1.0) * h, 0, h - 1).astype(int)
    _TEX["c"] = img[py, px]
    return _TEX["c"]


def skin_mask(js, binary, prim, UV):
    """Sommets couleur peau (teinte orangée, saturée), lus dans la texture de base."""
    c = tex_color(js, binary, prim, UV)
    mx, mn = c.max(axis=1), c.min(axis=1)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    redish = (c[:, 0] >= c[:, 1]) & (c[:, 1] >= c[:, 2] * 0.85)
    return redish & (sat > 0.22) & (mx > 0.25)


def main():
    src, joints_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
    js, binary = read_glb(src)
    prim = js["meshes"][0]["primitives"][0]
    node = js["nodes"][0]
    R = quat_mat(node.get("rotation", [0, 0, 0, 1]))
    S = np.array(node.get("scale", [1, 1, 1]))
    T = np.array(node.get("translation", [0, 0, 0]))
    P = accessor(js, binary, prim["attributes"]["POSITION"]).astype(np.float64)
    N = accessor(js, binary, prim["attributes"]["NORMAL"]).astype(np.float64)
    UV = accessor(js, binary, prim["attributes"]["TEXCOORD_0"]).astype(np.float32)
    I = accessor(js, binary, prim["indices"]).astype(np.uint32)
    P = (P * S) @ R.T + T
    N = N @ R.T
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
    print("sommets", len(P), "triangles", len(I) // 3)

    spec = json.load(open(joints_path))
    J = {k: np.array(v, dtype=np.float64) for k, v in spec["joints"].items()}
    bones = spec["bones"]  # [nom, articulation tête, articulation queue, parent, rayon_graine]
    names = [b[0] for b in bones]

    # --- grappes de sommets (voxels) et graphe de surface
    key = np.floor(P / VOXEL).astype(np.int64)
    _, cl, counts = np.unique(key, axis=0, return_inverse=True, return_counts=True)
    cl = cl.ravel()
    nc = counts.size
    C = np.zeros((nc, 3))
    np.add.at(C, cl, P)
    C /= counts[:, None]
    tri = I.reshape(-1, 3)
    e = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]])
    ce = cl[e]
    ce = ce[ce[:, 0] != ce[:, 1]]
    ce = np.unique(np.sort(ce, axis=1), axis=0)
    print("grappes", nc, "arêtes", len(ce))
    # Surfaces soudées (une main posée sur la veste, une manche collée au flanc) : on coupe
    # les arêtes entre faces de sens opposés, et entre peau et tissu loin des poignets.
    CN = np.zeros((nc, 3))
    np.add.at(CN, cl, N)
    CN /= np.linalg.norm(CN, axis=1, keepdims=True) + 1e-9
    keep = np.einsum("ij,ij->i", CN[ce[:, 0]], CN[ce[:, 1]]) > spec.get("fold_cut", -0.2)
    if spec.get("protect", {}).get("skin_ok"):
        vskin = skin_mask(js, binary, prim, UV)
        cskin = np.zeros(nc)
        np.add.at(cskin, cl, vskin.astype(float))
        cskin = cskin / counts > 0.5
        wrists = np.stack([J["poignet.L"], J["poignet.R"]])
        mid = (C[ce[:, 0]] + C[ce[:, 1]]) / 2
        near_wrist = np.min(np.linalg.norm(mid[:, None, :] - wrists[None], axis=2), axis=1) < 0.05
        keep &= ~((cskin[ce[:, 0]] != cskin[ce[:, 1]]) & ~near_wrist)
    print("arêtes coupées", int((~keep).sum()))
    ce = ce[keep]
    wts = 1.0 / (np.linalg.norm(C[ce[:, 0]] - C[ce[:, 1]], axis=1) + 1e-4)
    A = coo_matrix((np.concatenate([wts, wts]), (np.concatenate([ce[:, 0], ce[:, 1]]), np.concatenate([ce[:, 1], ce[:, 0]]))),
                   shape=(nc, nc)).tocsr()
    deg = np.asarray(A.sum(axis=1)).ravel()

    # --- distances aux os, graines (cœur de chaque os)
    D = np.stack([seg_dist(C, J[b[1]], J[b[2]]) for b in bones], axis=1)
    near = D.argmin(axis=1)
    seed = np.full(nc, -1)
    for bi, b in enumerate(bones):
        side = b[0][-2:]
        ok = (near == bi) & (D[:, bi] < b[4])
        if side == ".L":
            ok &= C[:, 0] > 0.02
        elif side == ".R":
            ok &= C[:, 0] < -0.02
        seed[ok] = bi
    # grappes isolées (sans arête) : os le plus proche
    iso = deg == 0
    seed[iso] = near[iso]
    fixed = seed >= 0
    free = ~fixed
    print("graines", fixed.sum(), "libres", free.sum())
    L = (coo_matrix((deg, (np.arange(nc), np.arange(nc))), shape=(nc, nc)).tocsr() - A).tocsr()
    Lff = L[free][:, free].tocsc()
    Lfs = L[free][:, fixed]
    Ws = np.zeros((fixed.sum(), len(bones)))
    Ws[np.arange(fixed.sum()), seed[fixed]] = 1.0
    # léger rappel vers l'os le plus proche (du bon côté) : rend le système toujours
    # soluble, même pour un morceau de surface isolé par les coupes
    Dm = D.copy()
    for bi, b in enumerate(bones):
        if b[0].endswith(".L"):
            Dm[C[:, 0] < -0.02, bi] = np.inf
        elif b[0].endswith(".R"):
            Dm[C[:, 0] > 0.02, bi] = np.inf
    near_side = Dm.argmin(axis=1)
    lam = 1e-3 * float(deg.mean())
    Nf = np.zeros((free.sum(), len(bones)))
    Nf[np.arange(free.sum()), near_side[free]] = 1.0
    from scipy.sparse import identity
    lu = splu((Lff + lam * identity(Lff.shape[0], format="csc")).tocsc())
    Wf = lu.solve(-(Lfs @ Ws) + lam * Nf)
    W = np.zeros((nc, len(bones)))
    W[fixed] = Ws
    W[free] = np.clip(Wf, 0.0, None)
    W /= W.sum(axis=1, keepdims=True) + 1e-12
    # grappes libres déconnectées des graines (somme nulle) : os le plus proche
    bad = W.sum(axis=1) < 0.5
    W[bad] = 0.0
    W[bad, near[bad]] = 1.0

    # --- poids par sommet : 4 os principaux
    Wv = W[cl]
    prot = spec.get("protect")
    if prot:
        # Zone du buste protégée : ni la main ni l'avant-bras n'y emportent la veste
        # (mains posées sur les hanches au repos). La peau (les doigts) reste à la main.
        axis_a, axis_b = J["bassin"], J["cou"]
        dist_axis = seg_dist(P, axis_a, axis_b)
        inside = (dist_axis < prot["radius"]) & (P[:, 1] > prot["y"][0]) & (P[:, 1] < prot["y"][1])
        skin = skin_mask(js, binary, prim, UV) if prot.get("skin_ok") else np.zeros(len(P), bool)
        for bi, b in enumerate(bones):
            if b[0] in prot["bones"]:
                y0, y1 = prot["bones"][b[0]]
                band = inside & (P[:, 1] > y0) & (P[:, 1] < y1)
                kill = band & ~(skin & (b[0] in prot.get("skin_ok", [])))
                Wv[kill, bi] = 0.0
        if prot.get("belt_free"):
            # ceinture (noire dans la texture) : jamais emportée par un bras
            c = tex_color(js, binary, prim, UV)
            belt = (c.max(axis=1) < 0.2) & (P[:, 1] < prot["belt_free"])
            for bi, b in enumerate(bones):
                if b[0].endswith((".L", ".R")) and not b[0].startswith(("thigh", "shin", "foot")):
                    Wv[belt, bi] = 0.0
            print("ceinture protégée :", int(belt.sum()), "sommets")
        tot = Wv.sum(axis=1)
        empty = tot < 1e-6
        torso_ids = [names.index(n) for n in ("hips", "spine", "chest")]
        if empty.any():
            dd = np.stack([seg_dist(P[empty], J[bones[i][1]], J[bones[i][2]]) for i in torso_ids], axis=1)
            Wv[np.where(empty)[0], np.array(torso_ids)[dd.argmin(axis=1)]] = 1.0
        Wv /= Wv.sum(axis=1, keepdims=True)
        print("zone protégée :", int(inside.sum()), "sommets, dont peau", int((inside & skin).sum()))
    top = np.argsort(-Wv, axis=1)[:, :4]
    tw = np.take_along_axis(Wv, top, axis=1)
    tw[tw < 0.02] = 0.0
    tw /= tw.sum(axis=1, keepdims=True)
    joints = top.astype(np.uint16)
    weights = tw.astype(np.float32)
    for bi, b in enumerate(bones):
        print(f"  {b[0]:12s} sommets dominants {(top[:, 0] == bi).sum()}")
    if prot and prot.get("drop_bridges"):
        # triangles « pont » entre une main ou une manche et le buste (surfaces soudées au
        # contact) : ils s'étireraient dès que le bras bouge, on les retire
        group = np.zeros(len(P), dtype=np.int8)
        for bi, b in enumerate(bones):
            if b[0].endswith(".L") and not b[0].startswith(("thigh", "shin", "foot")):
                group[top[:, 0] == bi] = 1
            elif b[0].endswith(".R") and not b[0].startswith(("thigh", "shin", "foot")):
                group[top[:, 0] == bi] = 2
        t3 = I.reshape(-1, 3)
        g = group[t3]
        mixed = (g.min(axis=1) == 0) & (g.max(axis=1) > 0)
        low = P[t3][:, :, 1].max(axis=1) < prot["drop_bridges"]
        drop = mixed & low
        I = t3[~drop].ravel()
        print("triangles pont retirés :", int(drop.sum()))

    # --- écriture du .glb
    B = Builder()
    pos = B.add(P.astype(np.float32), "VEC3", 5126, 34962, minmax=True)
    nor = B.add(N.astype(np.float32), "VEC3", 5126, 34962)
    uv = B.add(UV, "VEC2", 5126, 34962)
    jo = B.add(joints, "VEC4", 5123, 34962)
    we = B.add(weights, "VEC4", 5126, 34962)
    ind = B.add(I, "SCALAR", 5125, 34963)
    # textures et matériau d'origine
    img_map = {}
    for i, im in enumerate(js.get("images", [])):
        bv = js["bufferViews"][im["bufferView"]]
        s0 = bv.get("byteOffset", 0)
        img_map[i] = B.add_image(binary[s0:s0 + bv["byteLength"]], im.get("mimeType", "image/png"))
    B.js["samplers"] = js.get("samplers", [{}])
    B.js["textures"] = [{"sampler": t.get("sampler", 0), "source": img_map[t.get("source", t.get("extensions", {}).get("EXT_texture_webp", {}).get("source"))]} for t in js.get("textures", [])]
    B.js["materials"] = js.get("materials", [])
    # nœuds : 0 = racine, 1 = maillage, 2.. = os
    base = 2
    nodes = [{"name": "judoka", "children": [1, base]}, {"name": "corps", "mesh": 0, "skin": 0}]
    heads = {b[0]: J[b[1]] for b in bones}
    for bi, b in enumerate(bones):
        parent = b[3]
        rel = heads[b[0]] - (heads[parent] if parent else np.zeros(3))
        children = [base + ci for ci, c in enumerate(bones) if c[3] == b[0]]
        n = {"name": b[0], "translation": [float(x) for x in rel]}
        if children:
            n["children"] = children
        nodes.append(n)
    # bout de chaque os feuille : nœud « _fin » (utile pour orienter l'os)
    ibm = np.zeros((len(bones), 16), dtype=np.float32)
    for bi, b in enumerate(bones):
        m = np.eye(4)
        m[:3, 3] = -heads[b[0]]
        ibm[bi] = m.T.ravel()
    inv = B.add(ibm, "MAT4", 5126)
    B.js["nodes"] = nodes
    B.js["skins"] = [{"joints": [base + i for i in range(len(bones))], "inverseBindMatrices": inv, "skeleton": base}]
    attrs = {"POSITION": pos, "NORMAL": nor, "TEXCOORD_0": uv, "JOINTS_0": jo, "WEIGHTS_0": we}
    B.js["meshes"] = [{"name": "corps", "primitives": [{"attributes": attrs, "indices": ind, "material": prim.get("material", 0)}]}]
    B.js["scenes"] = [{"nodes": [0]}]
    B.js["scene"] = 0
    B.js["extras"] = {"bone_tails": {b[0]: [float(x) for x in J[b[2]]] for b in bones}}
    B.save(out)
    print("écrit", out)


main()
