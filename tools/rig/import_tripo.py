#!/usr/bin/env python3
"""Importe un judoka riggé sorti de Tripo (squelette Mixamo, 65 os) dans le format du jeu.

    python3 tools/rig/import_tripo.py "new asset/colosse.glb" colosse
    python3 tools/rig/import_tripo.py "new asset"/*.glb --tous

Produit `assets/judokas/<id>/rig.glb` + `assets/judokas/<id>/joints.json`, au même format
que les modèles historiques (tools/rig/autorig.py) pour que scripts/view/rig_pose.gd les
pilote sans rien changer :

  - orientation du jeu : mètres, Y vers le haut, tourné vers +Z, sa gauche vers +X
    (l'orientation du modèle source est détectée depuis l'axe des épaules et des pieds) ;
  - taille normalisée : 1,90 m, pieds à y = −0,95, tête à +0,95 ;
  - 28 os aux noms du jeu (hips, spine, spine2, chest, neck, head, shoulder/upper_arm/
    forearm/hand/fingers1/fingers2/thumb et thigh/shin/foot/toes ×2), les quatre doigts
    Mixamo étant fondus dans fingers1/fingers2 ;
  - **os au repos sans rotation** (translation seule), comme l'ancien rig : rig_pose.gd
    calcule des orientations globales et les pose telles quelles ;
  - seule la couleur de base est gardée (la normal map et la metallic/roughness ne servent
    pas au cel-shading et pèsent les deux tiers du fichier).

Le script refuse un modèle défectueux (voir tools/rig/check_tripo.py).
"""
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_tripo import accessor, check, globals_of, read_glb  # noqa: E402

HEIGHT = 1.90          # taille du judoka (m)

# --- correspondance squelette Mixamo → articulations du jeu -------------------------
JOINT_OF = {
    "Hips": "bassin", "Spine": "dos", "Spine1": "milieu", "Spine2": "poitrine",
    "Neck": "cou", "Head": "tete", "HeadTop_End": "sommet",
}
SIDE_JOINTS = {
    "Shoulder": "clavicule", "Arm": "epaule", "ForeArm": "coude", "Hand": "poignet",
    "HandMiddle1": "jointure", "HandMiddle2": "doigt_mi", "HandMiddle3": "doigt_bout",
    "HandThumb1": "pouce_base", "HandThumb3": "pouce_bout",
    "UpLeg": "hanche", "Leg": "genou", "Foot": "cheville",
    "ToeBase": "plante", "Toe_End": "orteils",
}

# os du jeu : [nom, articulation tête, articulation queue, parent, rayon]
BONES = [
    ["hips", "bassin", "dos", "", 0.16],
    ["spine", "dos", "milieu", "hips", 0.17],
    ["spine2", "milieu", "poitrine", "spine", 0.175],
    ["chest", "poitrine", "cou", "spine2", 0.18],
    ["neck", "cou", "tete", "chest", 0.07],
    ["head", "tete", "sommet", "neck", 0.15],
]
for S in ("L", "R"):
    BONES += [
        [f"shoulder.{S}", f"clavicule.{S}", f"epaule.{S}", "chest", 0.06],
        [f"upper_arm.{S}", f"epaule.{S}", f"coude.{S}", f"shoulder.{S}", 0.11],
        [f"forearm.{S}", f"coude.{S}", f"poignet.{S}", f"upper_arm.{S}", 0.11],
        [f"hand.{S}", f"poignet.{S}", f"jointure.{S}", f"forearm.{S}", 0.035],
        [f"thigh.{S}", f"hanche.{S}", f"genou.{S}", "hips", 0.13],
        [f"shin.{S}", f"genou.{S}", f"cheville.{S}", f"thigh.{S}", 0.12],
        [f"foot.{S}", f"cheville.{S}", f"plante.{S}", f"shin.{S}", 0.08],
        [f"toes.{S}", f"plante.{S}", f"orteils.{S}", f"foot.{S}", 0.05],
        [f"fingers1.{S}", f"jointure.{S}", f"doigt_mi.{S}", f"hand.{S}", 0.022],
        [f"fingers2.{S}", f"doigt_mi.{S}", f"doigt_bout.{S}", f"fingers1.{S}", 0.02],
        [f"thumb.{S}", f"pouce_base.{S}", f"pouce_bout.{S}", f"hand.{S}", 0.022],
    ]

# os Mixamo → os du jeu (pour le report des poids de peau)
def bone_of(mixamo):
    """Nom de l'os du jeu qui porte les poids de cet os Mixamo (ou None)."""
    n = mixamo.replace("mixamorig:", "")
    flat = {"Hips": "hips", "Spine": "spine", "Spine1": "spine2", "Spine2": "chest",
            "Neck": "neck", "Head": "head", "HeadTop_End": "head"}
    if n in flat:
        return flat[n]
    if not (n.startswith("Left") or n.startswith("Right")):
        return None
    s = "L" if n.startswith("Left") else "R"
    p = n[4:] if s == "L" else n[5:]
    if p == "Shoulder":
        return f"shoulder.{s}"
    if p == "Arm":
        return f"upper_arm.{s}"
    if p == "ForeArm":
        return f"forearm.{s}"
    if p == "Hand":
        return f"hand.{s}"
    if p.startswith("HandThumb"):
        return f"thumb.{s}"
    for f in ("HandIndex", "HandMiddle", "HandRing", "HandPinky"):
        if p.startswith(f):          # 1 → première phalange, 2/3/4 → seconde
            return f"fingers1.{s}" if p[len(f):] == "1" else f"fingers2.{s}"
    if p == "UpLeg":
        return f"thigh.{s}"
    if p == "Leg":
        return f"shin.{s}"
    if p == "Foot":
        return f"foot.{s}"
    if p in ("ToeBase", "Toe_End"):
        return f"toes.{s}"
    return None


# --- petite algèbre (sans numpy : il n'est pas installé partout) --------------------
def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def apply(m, v):
    return [sum(m[i][j] * v[j] for j in range(3)) for i in range(3)]


def bind_positions(js, d, binoff):
    """Position au repos de chaque os, lue dans les inverse bind matrices.

    Rattrape les exports Tripo dont les nœuds n'ont aucune transformation : la pose de
    repos y est quand même présente, cachée dans les matrices de la peau.
    """
    ibm = accessor(js, d, binoff, js["skins"][0]["inverseBindMatrices"])
    out = {}
    for j, m in zip(js["skins"][0]["joints"], ibm):
        rot = [[m[0], m[4], m[8]], [m[1], m[5], m[9]], [m[2], m[6], m[10]]]
        t = [m[12], m[13], m[14]]
        out[js["nodes"][j].get("name", "")] = [
            -sum(rot[k][i] * t[k] for k in range(3)) for i in range(3)]
    return out


def source_joints(js, d, binoff):
    """Position au repos de chaque articulation du jeu, dans le repère du modèle."""
    gl, _ = globals_of(js)
    posed = sum(1 for n in js["nodes"]
                if "translation" in n or "rotation" in n or "matrix" in n)
    bind = None if posed >= len(js["skins"][0]["joints"]) * 0.8 \
        else bind_positions(js, d, binoff)
    pos = {}
    for i, n in enumerate(js["nodes"]):
        name = n.get("name", "")
        if not name.startswith("mixamorig:"):
            continue
        if bind is not None:
            if name not in bind:
                continue
            p = bind[name]
        else:
            p = [gl[i][r][3] for r in range(3)]
        n = name[len("mixamorig:"):]
        if n in JOINT_OF:
            pos[JOINT_OF[n]] = p
        elif n.startswith("Left") or n.startswith("Right"):
            s = "L" if n.startswith("Left") else "R"
            part = n[4:] if s == "L" else n[5:]
            if part in SIDE_JOINTS:
                pos[f"{SIDE_JOINTS[part]}.{s}"] = p
    for s in ("L", "R"):                      # bout des doigts = bout de l'os « main »
        if f"doigt_bout.{s}" in pos:
            pos[f"doigts.{s}"] = list(pos[f"doigt_bout.{s}"])
    return pos


def orientation(pos):
    """Angle de rotation autour de Y qui met sa gauche en +X et son regard en +Z."""
    left = [pos["epaule.L"][i] - pos["epaule.R"][i] for i in range(3)]
    ang_left = math.atan2(-left[2], left[0])          # amener `left` sur +X
    ahead = [0.0, 0.0, 0.0]
    for s in ("L", "R"):                               # cheville → orteils = l'avant
        for i in range(3):
            ahead[i] += pos[f"orteils.{s}"][i] - pos[f"cheville.{s}"][i]
    ang_ahead = math.atan2(ahead[0], ahead[2])         # amener `ahead` sur +Z
    # les deux mesures doivent concorder ; l'axe des épaules est le plus fiable
    gap = (ang_left - ang_ahead + math.pi) % (2 * math.pi) - math.pi
    if abs(gap) > 0.6:
        print(f"   ! épaules et pieds en désaccord de {math.degrees(gap):.0f}° "
              "(orientation prise sur les épaules)")
    return -ang_left


def convert(src, ident, outdir, repair=False):
    js, d, binoff = read_glb(src)
    name, faults, _ = check(src)
    fatal = [f for f in faults if f.startswith("inverse bind")
             or f.startswith("aucun squelette")]
    if faults and not repair:
        print(f"✗ {ident} : modèle défectueux, import refusé "
              "(--reparer pour recalculer la peau)")
        for f in faults:
            print(f"    - {f}")
        return False
    if fatal:
        print(f"✗ {ident} : irréparable, la pose de repos elle-même est perdue")
        for f in fatal:
            print(f"    - {f}")
        return False

    pos = source_joints(js, d, binoff)
    prim = js["meshes"][0]["primitives"][0]
    P = [list(v) for v in accessor(js, d, binoff, prim["attributes"]["POSITION"])]
    N = [list(v) for v in accessor(js, d, binoff, prim["attributes"]["NORMAL"])]
    UV = accessor(js, d, binoff, prim["attributes"]["TEXCOORD_0"])
    JA = accessor(js, d, binoff, prim["attributes"]["JOINTS_0"])
    WA = accessor(js, d, binoff, prim["attributes"]["WEIGHTS_0"])
    IDX = [v[0] for v in accessor(js, d, binoff, prim["indices"])]

    if "sommet" not in pos:        # HeadTop_End absent de la peau : sommet du crâne
        top = max(v[1] for v in P)
        pos["sommet"] = [pos["tete"][0], top, pos["tete"][2]]
    for s in ("L", "R"):           # Toe_End absent : bout du pied dans l'axe cheville→plante
        if f"orteils.{s}" in pos:
            continue
        a, b = pos[f"cheville.{s}"], pos[f"plante.{s}"]
        fwd = [b[0] - a[0], b[2] - a[2]]
        n = math.hypot(*fwd) or 1.0
        step = 0.045 * (max(v[1] for v in P) - min(v[1] for v in P))
        pos[f"orteils.{s}"] = [b[0] + fwd[0] / n * step, b[1] - step * 0.25,
                               b[2] + fwd[1] / n * step]
    missing = {j for b in BONES for j in (b[1], b[2])} - set(pos)
    if missing:
        print(f"✗ {ident} : articulations manquantes {sorted(missing)}")
        return False

    # --- repère du jeu : rotation, échelle, pieds à −0,95
    R = rot_y(orientation(pos))
    P = [apply(R, v) for v in P]
    N = [apply(R, v) for v in N]
    for k in pos:
        pos[k] = apply(R, pos[k])
    ys = [v[1] for v in P]
    xs = [v[0] for v in P]
    zs = sorted(v[2] for v in P)
    k = HEIGHT / (max(ys) - min(ys))
    c = [(max(xs) + min(xs)) / 2, min(ys), zs[len(zs) // 2]]
    def place(v):
        return [(v[0] - c[0]) * k, (v[1] - c[1]) * k - HEIGHT / 2, (v[2] - c[2]) * k]
    P = [place(v) for v in P]
    for key in pos:
        pos[key] = place(pos[key])

    os.makedirs(outdir, exist_ok=True)
    write_joints(outdir, pos)

    if repair:
        # peau inutilisable : on ne garde que le maillage et le squelette, et on
        # recalcule les poids avec l'auto-rig du projet (diffusion sur la surface).
        static = os.path.join(outdir, "_statique.glb")
        B = Builder()
        attrs = {"POSITION": B.add_floats([v for p in P for v in p], "VEC3", P, 34962),
                 "NORMAL": B.add_floats([v for p in N for v in p], "VEC3", None, 34962),
                 "TEXCOORD_0": B.add_floats([v for p in UV for v in p], "VEC2", None,
                                            34962)}
        ind = B.add_uints(IDX)
        B.add_image(*basecolor(js, d, binoff))
        B.js.update(COMMON_MATERIAL)
        B.js["meshes"] = [{"name": "corps", "primitives": [
            {"attributes": attrs, "indices": ind, "material": 0}]}]
        B.js["nodes"] = [{"name": "corps", "mesh": 0}]
        B.js["scenes"] = [{"nodes": [0]}]
        B.js["scene"] = 0
        B.save(static)
        rig = os.path.join(outdir, "rig.glb")
        cmd = [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                            "autorig.py"),
               static, os.path.join(outdir, "joints.json"), rig]
        import subprocess
        r = subprocess.run(cmd, capture_output=True, text=True)
        os.remove(static)
        if r.returncode != 0:
            print(f"✗ {ident} : auto-rig en échec\n{r.stderr.strip()[-600:]}")
            return False
        size = os.path.getsize(rig) / 1e6
        print(f"✓ {ident:16s} {len(P)} sommets, peau recalculée, {size:.1f} Mo")
        return True

    # --- squelette du jeu : os au repos sans rotation, translation seule
    order = [b[0] for b in BONES]
    parent = {b[0]: b[3] for b in BONES}
    head = {b[0]: b[1] for b in BONES}
    bone_pos = {b: pos[head[b]] for b in order}

    # report des poids : os Mixamo → index d'os du jeu
    skin_names = [js["nodes"][j].get("name", "") for j in js["skins"][0]["joints"]]
    remap = []
    for nm in skin_names:
        g = bone_of(nm)
        remap.append(order.index(g) if g in order else order.index("hips"))
    JW = []
    for ja, wa in zip(JA, WA):
        acc = {}
        for a, w in zip(ja, wa):
            if w > 0:
                acc[remap[a]] = acc.get(remap[a], 0.0) + w
        top = sorted(acc.items(), key=lambda kv: -kv[1])[:4]
        tot = sum(w for _, w in top) or 1.0
        top += [(0, 0.0)] * (4 - len(top))
        JW.append(([b for b, _ in top], [w / tot for _, w in top]))

    # --- écriture du .glb
    B = Builder()
    attrs = {
        "POSITION": B.add_floats([v for p in P for v in p], "VEC3", P, 34962),
        "NORMAL": B.add_floats([v for p in N for v in p], "VEC3", None, 34962),
        "TEXCOORD_0": B.add_floats([v for p in UV for v in p], "VEC2", None, 34962),
        "JOINTS_0": B.add_ushorts([v for j, _ in JW for v in j], "VEC4"),
        "WEIGHTS_0": B.add_floats([v for _, w in JW for v in w], "VEC4", None, 34962),
    }
    ind = B.add_uints(IDX)
    ibm = []
    for b in order:                       # inverse de la pose de repos = translation inverse
        p = bone_pos[b]
        m = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -p[0], -p[1], -p[2], 1]
        ibm += m
    ibm_acc = B.add_floats(ibm, "MAT4", None, None)

    B.add_image(*basecolor(js, d, binoff))

    nodes = [{"name": "judoka", "children": [1, 2]},
             {"name": "corps", "mesh": 0, "skin": 0}]
    index = {b: 2 + i for i, b in enumerate(order)}
    for b in order:
        p = bone_pos[b]
        par = parent[b]
        t = p if par == "" else [p[i] - bone_pos[par][i] for i in range(3)]
        node = {"name": b, "translation": [round(v, 6) for v in t]}
        kids = [index[c] for c in order if parent[c] == b]
        if kids:
            node["children"] = kids
        nodes.append(node)
    B.js.update({
        "nodes": nodes,
        "scenes": [{"nodes": [0]}],
        "scene": 0,
        "skins": [{"joints": [index[b] for b in order],
                   "inverseBindMatrices": ibm_acc, "skeleton": index["hips"]}],
        "meshes": [{"name": "corps", "primitives": [
            {"attributes": attrs, "indices": ind, "material": 0}]}],
    })
    B.js.update(COMMON_MATERIAL)
    B.save(os.path.join(outdir, "rig.glb"))
    size = os.path.getsize(os.path.join(outdir, "rig.glb")) / 1e6
    print(f"✓ {ident:16s} {len(P)} sommets, {len(order)} os, {size:.1f} Mo "
          f"(tête {pos['sommet'][1]:.2f} m, pieds {pos['cheville.L'][1]:.2f} m)")
    return True


COMMON_MATERIAL = {
    "textures": [{"source": 0, "sampler": 0}],
    "samplers": [{"magFilter": 9729, "minFilter": 9987}],
    "materials": [{"name": "judoka", "doubleSided": True, "pbrMetallicRoughness": {
        "baseColorTexture": {"index": 0}, "metallicFactor": 0.0,
        "roughnessFactor": 0.9}}],
}


def basecolor(js, d, binoff):
    """Octets et type MIME de la texture de couleur de base."""
    mat = js["materials"][js["meshes"][0]["primitives"][0].get("material", 0)]
    tex = js["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]
    img = js["images"][tex.get("source", 0)]
    bv = js["bufferViews"][img["bufferView"]]
    s0 = binoff + bv.get("byteOffset", 0)
    return d[s0:s0 + bv["byteLength"]], img.get("mimeType", "image/jpeg")


def write_joints(outdir, pos):
    doc = ("Squelette d'un judoka importé de Tripo (tools/rig/import_tripo.py) : mètres, "
           "Y vers le haut, tourné vers +Z, sa gauche vers +X, 1,90 m (pieds à −0,95). "
           "Os au repos sans rotation : rig_pose.gd pose des orientations globales.")
    with open(os.path.join(outdir, "joints.json"), "w") as f:
        json.dump({"_doc": doc,
                   "joints": {k: [round(v, 4) for v in p] for k, p in sorted(pos.items())},
                   "bones": BONES}, f, ensure_ascii=False, indent=1)


class Builder:
    """Construit un .glb : un seul buffer, un bufferView par accesseur."""

    def __init__(self):
        self.js = {"asset": {"version": "2.0", "generator": "judo/import_tripo"},
                   "accessors": [], "bufferViews": [], "images": []}
        self.blob = bytearray()

    def _view(self, data, target=None):
        while len(self.blob) % 4:
            self.blob.append(0)
        off = len(self.blob)
        self.blob += data
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        self.js["bufferViews"].append(v)
        return len(self.js["bufferViews"]) - 1

    def _acc(self, view, ctype, kind, count, minmax=None):
        a = {"bufferView": view, "componentType": ctype, "count": count, "type": kind}
        if minmax:
            a["min"], a["max"] = minmax
        self.js["accessors"].append(a)
        return len(self.js["accessors"]) - 1

    def add_floats(self, flat, kind, minmax_src, target):
        n = {"VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[kind]
        v = self._view(struct.pack("<%df" % len(flat), *flat), target)
        mm = None
        if minmax_src:
            mm = ([min(p[i] for p in minmax_src) for i in range(n)],
                  [max(p[i] for p in minmax_src) for i in range(n)])
        return self._acc(v, 5126, kind, len(flat) // n, mm)

    def add_ushorts(self, flat, kind):
        n = {"VEC4": 4}[kind]
        v = self._view(struct.pack("<%dH" % len(flat), *flat), 34962)
        return self._acc(v, 5123, kind, len(flat) // n)

    def add_uints(self, flat):
        v = self._view(struct.pack("<%dI" % len(flat), *flat), 34963)
        return self._acc(v, 5125, "SCALAR", len(flat))

    def add_image(self, data, mime):
        v = self._view(data)
        self.js["images"].append({"bufferView": v, "mimeType": mime})

    def save(self, path):
        self.js["buffers"] = [{"byteLength": len(self.blob)}]
        js = json.dumps(self.js, separators=(",", ":")).encode()
        js += b" " * (-len(js) % 4)
        blob = bytes(self.blob) + b"\0" * (-len(self.blob) % 4)
        with open(path, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob)))
            f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
            f.write(struct.pack("<II", len(blob), 0x004E4942) + blob)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    rep = "--reparer" in sys.argv
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    if "--tous" in sys.argv:
        ok = sum(convert(p, os.path.basename(p)[:-4],
                         os.path.join(root, "assets/judokas", os.path.basename(p)[:-4]),
                         rep)
                 for p in args)
        print(f"\n{ok}/{len(args)} modèles importés")
        sys.exit(0 if ok == len(args) else 1)
    if len(args) != 2:
        sys.exit(__doc__)
    sys.exit(0 if convert(args[0], args[1],
                          os.path.join(root, "assets/judokas", args[1]), rep) else 1)
