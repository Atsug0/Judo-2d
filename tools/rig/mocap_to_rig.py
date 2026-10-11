#!/usr/bin/env python3
"""Chorégraphie filmée (data/anims/<tech>.json) → articulations anatomiques 3D (gauche /
droite) pour piloter un modèle riggé dans Godot (tools/rig/pose_model.gd).

    python3 tools/rig/mocap_to_rig.py data/anims/uchi_mata.json sortie.json

Repère de sortie : mètres, Y vers le haut, X vers la droite de l'écran (sens du jeu),
Z vers la caméra. La vidéo est vue de profil : la profondeur (écart gauche / droite)
est fixée par des largeurs d'épaules et de hanches réalistes, et change de signe quand
le judoka se retourne (son côté gauche passe vers la caméra).
"""
import json
import math
import sys

M = 1.8 / 100.0
HIP0 = (0.0, -47.0)
NECK0 = (1.0, -86.0)
HEAD_CENTER = (1.0, -98.0)
SHOULDER = (0.5, -79.5)
ARM_UPPER, ARM_FORE = 20.0, 21.5
HALF = {"hanche": 0.10, "genou": 0.11, "pied": 0.13, "epaule": 0.18, "coude": 0.21, "main": 0.20}


def rot(v, a):
    c, s = math.cos(a), math.sin(a)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def knee_ik(hip, foot, thigh=23.5, shin=21.5):
    d = sub(foot, hip)
    dist = max(1.0, min(thigh + shin - 0.01, math.hypot(*d)))
    a = math.acos(max(-1.0, min(1.0, (thigh ** 2 + dist ** 2 - shin ** 2) / (2 * thigh * dist))))
    base = math.atan2(d[1], d[0])
    k1 = add(hip, (math.cos(base + a) * thigh, math.sin(base + a) * thigh))
    k2 = add(hip, (math.cos(base - a) * thigh, math.sin(base - a) * thigh))
    return k1 if k1[0] > k2[0] else k2


def elbow_ik(sh, hand):
    d = sub(hand, sh)
    dist = max(1.0, min(ARM_UPPER + ARM_FORE - 0.01, math.hypot(*d)))
    a = math.acos(max(-1.0, min(1.0, (ARM_UPPER ** 2 + dist ** 2 - ARM_FORE ** 2) / (2 * ARM_UPPER * dist))))
    base = math.atan2(d[1], d[0])
    k1 = add(sh, (math.cos(base + a) * ARM_UPPER, math.sin(base + a) * ARM_UPPER))
    k2 = add(sh, (math.cos(base - a) * ARM_UPPER, math.sin(base - a) * ARM_UPPER))
    return k1 if k1[1] > k2[1] else k2


def anatomical(actor):
    pose = actor["pose"]
    hip = tuple(pose.get("hip", HIP0))
    bow = float(pose.get("bow", 0.0))
    tilt = float(pose.get("tilt", 0.0))
    face = int(actor["face"])
    r = float(actor["rot"])
    pos = tuple(actor["pos"])

    def torso(p):
        return add(hip, rot(sub(p, HIP0), bow))

    def world(p, depth=0.0):
        w = add(pos, rot(((p[0] - hip[0]) * face, p[1] - hip[1]), r))
        return [round(w[0] * M, 4), round(-w[1] * M, 4), round(depth, 4)]

    neck = torso(NECK0)
    out = {"bassin": world(hip), "cou": world(neck),
           "tete": world(add(neck, rot(sub(HEAD_CENTER, NECK0), bow + tilt)))}
    sh = torso(SHOULDER)
    # côté du jeu (b = loin de la caméra, f = près) → côté anatomique
    side_of = {"f": "R", "b": "L"} if face > 0 else {"f": "L", "b": "R"}
    for s in ("b", "f"):
        a = side_of[s]
        zsign = 1.0 if s == "f" else -1.0   # près de la caméra = +Z
        foot = tuple(pose["f" + s])
        knee = tuple(pose["k" + s]) if ("k" + s) in pose else knee_ik(torso((0, -47)), foot)
        hand = tuple(pose["h" + s])
        out["hanche." + a] = world(hip, zsign * HALF["hanche"])
        out["genou." + a] = world(knee, zsign * HALF["genou"])
        out["pied." + a] = world(foot, zsign * HALF["pied"])
        out["epaule." + a] = world(sh, zsign * HALF["epaule"])
        out["coude." + a] = world(elbow_ik(sh, hand), zsign * HALF["coude"])
        out["main." + a] = world(hand, zsign * HALF["main"])
    return out


def main():
    data = json.load(open(sys.argv[1]))
    f0 = data["keys"][0]["frame"]
    keys = [{"t": round((k["frame"] - f0) / 12, 4), "frame": k["frame"],
             "tori": anatomical(k["tori"]), "uke": anatomical(k["uke"])} for k in data["keys"]]
    json.dump({"tech": data["tech"], "keys": keys}, open(sys.argv[2], "w"), indent=0)
    print(len(keys), "images clés →", sys.argv[2])


main()
