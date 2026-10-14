#!/usr/bin/env python3
"""Judogi blanc et bleu de chaque skin, pour respecter le blanc/bleu de compétition.

    python3 tools/rig/gi_variantes.py            # tous les skins de data/skins.json
    python3 tools/rig/gi_variantes.py colosse

En compétition, un judoka est en blanc et l'autre en bleu : la couleur n'est pas un choix
du joueur, elle dépend du côté. Les quatre modèles « basic » existent vraiment dans les
deux couleurs ; pour les autres, on reteint la texture du modèle et le jeu la plaque sur
le même rig (scripts/skins.gd → texture_for). Selon la couleur d'origine du personnage,
on génère la variante qui manque : `texture_bleu.jpg` pour un judogi blanc,
`texture_blanc.jpg` pour un judogi bleu, noir ou gris.

Le judogi ne se reconnaît pas à sa couleur — celui d'un vétéran est crème, des cheveux
blancs sont tout aussi clairs et peu saturés, et un kimono noir est aussi sombre que des
cheveux. Le masque est donc **construit depuis le squelette** : masque UV des triangles
qui ne sont ni tête, ni cou, ni mains (voir masque_judogi).
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
BLEU = np.array([0.09, 0.24, 0.72], dtype=np.float32)   # bleu judogi de compétition
MAX_PX = 2048


def basecolor(path):
    """Image de couleur de base d'un .glb (Pillow)."""
    d = open(path, "rb").read()
    jlen = struct.unpack_from("<I", d, 12)[0]
    js = json.loads(d[20:20 + jlen])
    binoff = 20 + jlen + 8
    mat = js["materials"][js["meshes"][0]["primitives"][0].get("material", 0)]
    tex = js["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]
    img = js["images"][tex.get("source", 0)]
    bv = js["bufferViews"][img["bufferView"]]
    s0 = binoff + bv.get("byteOffset", 0)
    return Image.open(io.BytesIO(d[s0:s0 + bv["byteLength"]])).convert("RGB")


def masque_judogi(path, taille):
    """Masque UV des parties habillées : tout sauf la tête, le cou et les mains.

    Le judogi ne se reconnaît pas de façon fiable à sa couleur (celui d'un vétéran est
    crème, des cheveux blancs sont tout aussi clairs et peu saturés). On s'appuie donc
    sur le squelette : chaque triangle dont les sommets sont pilotés par la tête, le cou
    ou une main est exclu, les autres sont rastérisés dans l'espace UV.
    """
    d = open(path, "rb").read()
    jlen = struct.unpack_from("<I", d, 12)[0]
    js = json.loads(d[20:20 + jlen])
    binoff = 20 + jlen + 8

    def acc(i, fmt, n):
        a = js["accessors"][i]
        bv = js["bufferViews"][a["bufferView"]]
        base = binoff + bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        sz = {"f": 4, "H": 2, "I": 4, "B": 1}[fmt]
        st = bv.get("byteStride") or n * sz
        return [struct.unpack_from("<%d%s" % (n, fmt), d, base + st * k)
                for k in range(a["count"])]

    prim = js["meshes"][0]["primitives"][0]
    noms = [js["nodes"][j].get("name", "") for j in js["skins"][0]["joints"]]
    nu = acc(prim["attributes"]["TEXCOORD_0"], "f", 2)
    ja = acc(prim["attributes"]["JOINTS_0"], "H", 4)
    wa = acc(prim["attributes"]["WEIGHTS_0"], "f", 4)
    idx = [v[0] for v in acc(prim["indices"], "I", 1)]
    nus = {"neck", "head", "hand.L", "hand.R", "fingers1.L", "fingers1.R",
           "fingers2.L", "fingers2.R", "thumb.L", "thumb.R", "toes.L", "toes.R"}
    habille = [noms[j[max(range(4), key=lambda i: w[i])]] not in nus
               for j, w in zip(ja, wa)]
    m = Image.new("L", (taille, taille), 0)
    g = ImageDraw.Draw(m)
    for t in range(0, len(idx) - 2, 3):
        tri = idx[t:t + 3]
        if not all(habille[v] for v in tri):
            continue
        g.polygon([(nu[v][0] * taille, nu[v][1] * taille) for v in tri], fill=255)
    return np.asarray(m).astype(np.float32) / 255.0


def teinte(im, couleur, masque=None):
    """Reteint le judogi en « bleu » ou « blanc », en gardant ombres et plis.

    Dans la zone habillée, le tissu est tout ce qui n'est pas une peau orangée. On garde
    la luminance relative du pixel (les plis et les ombres survivent) et on ne remplace
    que la teinte et la saturation.
    """
    a = np.asarray(im).astype(np.float32) / 255.0
    mx, mn = a.max(axis=2), a.min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    peau = (sat > 0.26) & (a[..., 0] > a[..., 1]) & (a[..., 1] >= a[..., 2])
    gi = (~peau).astype(np.float32)
    if masque is not None:
        gi = gi * masque
    if couleur == "bleu":
        shade = np.clip(mx / 0.9, 0.3, 1.1) ** 1.15
        cible = np.clip(BLEU[None, None, :] * shade[..., None]
                        + 0.03 * shade[..., None], 0, 1)
    else:
        # vers le blanc : on étire la luminance du tissu (un kimono bleu marine est
        # sombre) et on désature presque complètement
        lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
        p = np.percentile(lum[gi > 0.5], [5, 95]) if (gi > 0.5).any() else [0.0, 1.0]
        etire = np.clip((lum - p[0]) / max(1e-3, p[1] - p[0]), 0, 1)
        v = 0.52 + 0.46 * etire
        cible = np.stack([v, v, v * 1.01], axis=-1)
        cible = np.clip(cible * 0.94 + a * 0.06, 0, 1)
    out = a * (1 - gi[..., None]) + cible * gi[..., None]
    return Image.fromarray((out * 255).astype(np.uint8)), float(gi.mean())


if __name__ == "__main__":
    skins = json.load(open(os.path.join(ROOT, "data/skins.json")))["skins"]
    only = [a for a in sys.argv[1:] if not a.startswith("-")]
    n = 0
    for s in skins:
        if only and s["id"] not in only:
            continue
        if s["blanc"] != s["bleu"]:
            continue                      # les deux modèles existent pour de vrai
        # on génère la couleur que le personnage n'a pas
        couleur = "blanc" if s.get("gi") != "blanc" else "bleu"
        d = os.path.join(ROOT, "assets/judokas", s["blanc"])
        rig = os.path.join(d, "rig.glb")
        if not os.path.exists(rig):
            print(f"✗ {s['id']:16s} rig.glb absent")
            continue
        out = os.path.join(d, f"texture_{couleur}.jpg")
        src = basecolor(rig)
        im, part = teinte(src, couleur, masque_judogi(rig, src.size[0]))
        if max(im.size) > MAX_PX:         # 2048 suffit : le judoka fait ~400 px à l'écran
            im = im.resize((MAX_PX, MAX_PX), Image.LANCZOS)
        im.save(out, quality=88)
        n += 1
        print(f"✓ {s['id']:16s} judogi {s.get('gi'):10s} → {couleur:6s} "
              f"({part * 100:.0f} % de la texture) {os.path.relpath(out, ROOT)}")
    print(f"\n{n} variante(s) de judogi")
