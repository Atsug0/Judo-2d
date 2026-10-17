#!/usr/bin/env python3
"""Rotoscopie → images clés du jeu.

Lit une annotation (points 2D image par image de tori et d'uke, voir uchi_mata_annot.json)
et la reporte sur le squelette du jeu : on garde les ANGLES (buste, cuisses, tibias,
bras, tête) et on réapplique les longueurs du squelette stylisé, pour que les proportions
du dessin restent celles du jeu. Écrit data/anims/<tech>.json, lu par throw_anims.gd.

    python3 tools/mocap/retarget.py tools/mocap/uchi_mata_annot.json
"""
import json
import math
import os
import sys

HIP0 = (0.0, -47.0)
SHOULDER_FRONT = (9.0, -79.0)
SHOULDER_BACK = (-8.0, -80.0)
THIGH, SHIN = 23.5, 21.5
ARM_MAX = 41.0
LYING = {"hip": [0, -47], "bow": 0.0, "fb": [-8, -6], "ff": [10, -8], "hb": [10, -44], "hf": [24, -64], "tilt": 0.2}
POINTS = ["H", "N", "P", "Kn", "An", "Kf", "Af", "Wn", "Wf"]


def rot(v, a):
    c, s = math.cos(a), math.sin(a)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def mul(a, k):
    return (a[0] * k, a[1] * k)


def norm(v):
    n = math.hypot(*v) or 1.0
    return (v[0] / n, v[1] / n)


def angle_up(v):
    """Angle par rapport à la verticale montante, + = vers +x (sens horaire à l'écran)."""
    return math.atan2(v[0], -v[1])


def smooth(frames, who):
    """Lissage temporel léger (1-2-1) des points, sans toucher aux extrémités."""
    seq = [fr[who] for fr in frames]
    out = []
    for i, a in enumerate(seq):
        if i == 0 or i == len(seq) - 1 or a.get("lying") or seq[i - 1].get("lying") or seq[i + 1].get("lying"):
            out.append(a)
            continue
        b = dict(a)
        for k in POINTS:
            p0, p1, p2 = seq[i - 1][k], a[k], seq[i + 1][k]
            b[k] = [(p0[0] + 2 * p1[0] + p2[0]) / 4, (p0[1] + 2 * p1[1] + p2[1]) / 4]
        out.append(b)
    return out


def actor(a, who, s, x0, floor, prev_rot, shift_in=None):
    if a.get("lying"):
        # face : -1 par défaut ; +1 pour un uke couché sur le dos la tête à gauche (rot ≈ -π/2)
        return {"pos": [round((a["x_px"] - x0) * s, 2), a["y_units"]], "rot": a["rot"], "face": int(a.get("face", -1)), "pose": LYING}, a["rot"]
    F = a["face"]
    P, N, H = a["P"], a["N"], a["H"]
    world_torso = angle_up(sub(N, P))
    if who == "tori":
        r = 0.0
    else:
        r = world_torso
        if prev_rot is not None:  # continuité de la rotation (pas de saut de 2π)
            while r - prev_rot > math.pi:
                r -= 2 * math.pi
            while r - prev_rot < -math.pi:
                r += 2 * math.pi

    def local(v):  # vecteur monde → repère local de l'acteur (rotation puis miroir)
        w = rot(v, -r)
        return (w[0] * F, w[1])

    bow = angle_up(local(sub(N, P)))
    hip = HIP0

    def torso(p):  # point du buste « debout » → local (inclinaison autour du bassin)
        return add(hip, rot(sub(p, HIP0), bow))

    pose = {"hip": list(hip), "bow": round(bow, 3)}
    for side, att_x, K, A in (("b", -6.0, "Kf", "Af"), ("f", 6.0, "Kn", "An")):
        att = torso((att_x, -47.0))
        knee = add(att, mul(norm(local(sub(a[K], P))), THIGH))
        foot = add(knee, mul(norm(local(sub(a[A], a[K]))), SHIN))
        pose["k" + side] = [round(knee[0], 1), round(knee[1], 1)]
        pose["f" + side] = [round(foot[0], 1), round(foot[1], 1)]
    for side, sh, W in (("b", SHOULDER_BACK, "Wf"), ("f", SHOULDER_FRONT, "Wn")):
        v = sub(a[W], N)
        length = max(12.0, min(ARM_MAX, math.hypot(*v) * s * 1.45))
        hand = add(torso(sh), mul(norm(local(v)), length))
        pose["h" + side] = [round(hand[0], 1), round(hand[1], 1)]
    head = angle_up(local(sub(H, N)))
    pose["tilt"] = round(max(-0.7, min(0.7, head - bow)), 3)
    pos = [(P[0] - x0) * s, (P[1] - floor) * s]
    # Au sol : le pied le plus bas posé sur le tatami (les jambes du jeu n'ont pas les
    # proportions réelles, le bassin est donc recalé). En l'air : même recalage que
    # l'autre judoka, pour garder leur position relative (uke sur le dos de tori).
    # « le pied touche le tatami » : 15 % de la hauteur de bassin, et non 22 px en dur —
    # l'échelle change d'une vidéo à l'autre selon la distance de la caméra. (s vaut
    # 47 / hauteur_de_bassin_px, d'où le 7.05 = 0,15 × 47.)
    grounded = max(a["An"][1], a["Af"][1]) >= floor - 7.05 / s
    shift = 0.0
    if grounded:
        low = -1e9
        for k in ("fb", "ff"):
            w = rot((pose[k][0] * F - hip[0] * F, pose[k][1] - hip[1]), r)
            low = max(low, pos[1] + w[1])
        shift = -3.0 - low
    elif shift_in is not None:
        shift = shift_in
    pos[1] += shift - float(a.get("lift", 0.0))
    return {"pos": [round(pos[0], 2), round(pos[1], 2)], "rot": round(r, 3), "face": F, "pose": pose, "_shift": shift}, r


def main():
    src = sys.argv[1]
    ann = json.load(open(src))
    s = 47.0 / ann["hip_height_px"]
    floor = ann["floor_y"]
    frames = ann["frames"]
    x0 = frames[0]["tori"]["P"][0]
    d0 = (frames[0]["uke"]["P"][0] - x0) * s
    # avancement : clés explicites, interpolation linéaire en temps entre elles
    known = [(fr["f"], fr["p"]) for fr in frames if "p" in fr]
    for fr in frames:
        if "p" not in fr:
            for (fa, pa), (fb, pb) in zip(known, known[1:]):
                if fa <= fr["f"] <= fb:
                    fr["p"] = pa + (pb - pa) * (fr["f"] - fa) / (fb - fa)
    tori = smooth(frames, "tori")
    uke = smooth(frames, "uke")
    keys = []
    prev = {"tori": None, "uke": None}
    for fr, t, u in zip(frames, tori, uke):
        kt, prev["tori"] = actor(t, "tori", s, x0, floor, prev["tori"])
        ku, prev["uke"] = actor(u, "uke", s, x0, floor, prev["uke"], kt.get("_shift"))
        kt.pop("_shift", None)
        ku.pop("_shift", None)
        keys.append({"p": round(fr["p"], 4), "frame": fr["f"], "tori": kt, "uke": ku})
    out = {"tech": ann["tech"], "d0": round(d0, 2), "source": ann["source"], "keys": keys}
    dst = os.path.join(os.path.dirname(__file__), "..", "..", "data", "anims", ann["tech"] + ".json")
    json.dump(out, open(dst, "w"), indent=1)
    print("écrit", os.path.normpath(dst), len(keys), "clés, d0 =", round(d0, 1))


main()
