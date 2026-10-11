"""Importe une chorégraphie filmée (data/anims/<tech>.json) dans Blender : deux mannequins 3D
articulés (tori, uke) animés image par image, prêts à être habillés ou remplacés par
de vrais modèles riggés, puis rendus en sprites avec render_sprites.py.

À lancer dans Blender (4.x), de préférence après setup_scene.py :
    blender --python tools/blender/import_mocap.py -- --anim data/anims/uchi_mata.json
Sans Blender (vérification des positions) :
    python3 tools/blender/import_mocap.py --anim data/anims/uchi_mata.json --print

Ce que fait le script :
  1. Recalcule la position 3D de chaque articulation (bassin, cou, tête, épaules, coudes,
     mains, hanches, genoux, pieds) à partir des poses du jeu : profil dans le plan XZ,
     membres côté caméra en -Y, côté opposé en +Y.
  2. Crée un repère (Empty) par articulation et l'anime (interpolation linéaire, 60 i/s).
  3. Crée une armature par judoka dont chaque os suit ses deux repères (Copy Location +
     Stretch To) : on peut ensuite la reprendre (retarget) sur un modèle Rigify ou Mixamo.
  4. Habille chaque os d'un segment de mannequin (capsule) nommé tori_… / uke_…, rangé dans
     les collections TORI / UKE : les matériaux toon de setup_scene.py s'y appliquent.

Échelle : 100 unités de jeu = 1,80 m. Les clés filmées sont à 12 i/s dans la vidéo source ;
l'image clé n de la vidéo devient l'image (n - n0) × 5 + 1 de Blender (60 i/s).
"""
import json
import math
import sys

M = 1.8 / 100.0              # mètres par unité de jeu
HIP0 = (0.0, -47.0)
NECK0 = (1.0, -86.0)
HEAD_CENTER = (1.0, -98.0)
SHOULDER_FRONT = (9.0, -79.0)
SHOULDER_BACK = (-8.0, -80.0)
ARM_UPPER, ARM_FORE = 20.0, 21.5
DEPTH = {"b": 0.10, "f": -0.10, "c": 0.0}   # profondeur (m) : côté opposé / côté caméra / axe
STAND = {"hip": [0, -47], "bow": 0.0, "tilt": 0.0, "kb": [-14.2, -25], "fb": [-19.5, -4], "kf": [17.3, -25],
         "ff": [19.5, -4], "hb": [22, -57], "hf": [29, -65]}

# os du mannequin : (nom, articulation de départ, articulation d'arrivée, rayon en m)
BONES = [
    ("buste", "bassin", "cou", 0.13), ("tete", "cou", "tete", 0.11),
    ("cuisse_b", "hanche_b", "genou_b", 0.075), ("tibia_b", "genou_b", "pied_b", 0.06),
    ("cuisse_f", "hanche_f", "genou_f", 0.075), ("tibia_f", "genou_f", "pied_f", 0.06),
    ("bras_b", "epaule_b", "coude_b", 0.055), ("avbras_b", "coude_b", "main_b", 0.045),
    ("bras_f", "epaule_f", "coude_f", 0.055), ("avbras_f", "coude_f", "main_f", 0.045),
]


def _rot(v, a):
    c, s = math.cos(a), math.sin(a)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def _knee(hip, foot, thigh=23.5, shin=21.5):
    d = _sub(foot, hip)
    dist = max(1.0, min(thigh + shin - 0.01, math.hypot(*d)))
    a = math.acos(max(-1.0, min(1.0, (thigh ** 2 + dist ** 2 - shin ** 2) / (2 * thigh * dist))))
    base = math.atan2(d[1], d[0])
    k1 = _add(hip, (math.cos(base + a) * thigh, math.sin(base + a) * thigh))
    k2 = _add(hip, (math.cos(base - a) * thigh, math.sin(base - a) * thigh))
    return k1 if k1[0] > k2[0] else k2


def _elbow(sh, hand, back):
    """Coude par cinématique inverse (plié vers le bas / l'arrière, comme dans le jeu)."""
    d = _sub(hand, sh)
    dist = max(1.0, min(ARM_UPPER + ARM_FORE - 0.01, math.hypot(*d)))
    a = math.acos(max(-1.0, min(1.0, (ARM_UPPER ** 2 + dist ** 2 - ARM_FORE ** 2) / (2 * ARM_UPPER * dist))))
    base = math.atan2(d[1], d[0])
    k1 = _add(sh, (math.cos(base + a) * ARM_UPPER, math.sin(base + a) * ARM_UPPER))
    k2 = _add(sh, (math.cos(base - a) * ARM_UPPER, math.sin(base - a) * ARM_UPPER))
    return k1 if k1[1] > k2[1] else k2


def joints(actor):
    """Articulations d'un acteur (dict pos/rot/face/pose) → {nom: (x, y, z) en mètres}."""
    pose = actor["pose"]
    hip = tuple(pose.get("hip", HIP0))
    bow = float(pose.get("bow", 0.0))
    tilt = float(pose.get("tilt", 0.0))
    face = actor["face"]
    r = actor["rot"]
    pos = tuple(actor["pos"])

    def torso(p):
        return _add(hip, _rot(_sub(p, HIP0), bow))

    loc = {"bassin": (hip, "c")}
    neck = torso(NECK0)
    loc["cou"] = (neck, "c")
    loc["tete"] = (_add(neck, _rot(_sub(HEAD_CENTER, NECK0), bow + tilt)), "c")
    for side, ax in (("b", -6.0), ("f", 6.0)):
        loc["hanche_" + side] = (torso((ax, -47.0)), side)
        knee = pose.get("k" + side)
        if knee is None:  # genou absent de la pose : même cinématique inverse que le jeu
            knee = _knee(loc["hanche_" + side][0], tuple(pose["f" + side]))
        loc["genou_" + side] = (tuple(knee), side)
        loc["pied_" + side] = (tuple(pose["f" + side]), side)
    for side, sh in (("b", SHOULDER_BACK), ("f", SHOULDER_FRONT)):
        s = torso(sh)
        h = tuple(pose["h" + side])
        loc["epaule_" + side] = (s, side)
        loc["coude_" + side] = (_elbow(s, h, side == "b"), side)
        loc["main_" + side] = (h, side)
    out = {}
    for name, (p, side) in loc.items():
        w = _add(pos, _rot(((p[0] - hip[0]) * face, p[1] - hip[1]), r))
        out[name] = (round(w[0] * M, 4), DEPTH[side], round(-w[1] * M, 4))
    return out


def load(path):
    data = json.load(open(path))
    sx = 1.0  # distance filmée (d0) : pas d'étirement dans Blender
    keys = data["keys"]
    f0 = keys[0]["frame"]
    frames = []
    for k in keys:
        frames.append({"frame": (k["frame"] - f0) * 5 + 1, "tori": joints(k["tori"]), "uke": joints(k["uke"])})
    return data, frames, sx


def build(data, frames):
    import bpy

    scene = bpy.context.scene
    scene.render.fps = 60
    scene.frame_start = 1
    scene.frame_end = frames[-1]["frame"] + 20
    for who in ("tori", "uke"):
        coll = bpy.data.collections.get(who.upper())
        if coll is None:
            coll = bpy.data.collections.new(who.upper())
            scene.collection.children.link(coll)
        names = list(frames[0][who].keys())
        empties = {}
        for n in names:
            e = bpy.data.objects.new(f"{who}_cible_{n}", None)
            e.empty_display_size = 0.04
            e.empty_display_type = "SPHERE"
            coll.objects.link(e)
            empties[n] = e
            for fr in frames:
                e.location = fr[who][n]
                e.keyframe_insert("location", frame=fr["frame"])
            for fc in e.animation_data.action.fcurves:
                for kp in fc.keyframe_points:
                    kp.interpolation = "LINEAR"
        # armature : un os par segment, qui suit ses repères
        arm_data = bpy.data.armatures.new(f"{who}_squelette")
        arm = bpy.data.objects.new(f"{who}_squelette", arm_data)
        coll.objects.link(arm)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        first = frames[0][who]
        for bname, a, b, _r in BONES:
            eb = arm_data.edit_bones.new(bname)
            eb.head = first[a]
            eb.tail = first[b]
        bpy.ops.object.mode_set(mode="POSE")
        for bname, a, b, rad in BONES:
            pb = arm.pose.bones[bname]
            c1 = pb.constraints.new("COPY_LOCATION")
            c1.target = empties[a]
            c2 = pb.constraints.new("STRETCH_TO")
            c2.target = empties[b]
        bpy.ops.object.mode_set(mode="OBJECT")
        # mannequin : une capsule par os, attachée à l'os
        for bname, a, b, rad in BONES:
            length = math.dist(first[a], first[b])
            bpy.ops.mesh.primitive_cylinder_add(radius=rad, depth=max(0.05, length), vertices=16)
            seg = bpy.context.active_object
            seg.name = f"{who}_{bname}"
            for c in seg.users_collection:
                c.objects.unlink(seg)
            coll.objects.link(seg)
            seg.parent = arm
            seg.parent_type = "BONE"
            seg.parent_bone = bname
            # l'origine d'un enfant d'os est la queue de l'os : on recentre la capsule sur l'os
            seg.location = (0.0, -length / 2.0, 0.0)
            seg.rotation_euler = (math.pi / 2.0, 0.0, 0.0)
        for joint, rad in (("tete", 0.13),):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=rad)
            head = bpy.context.active_object
            head.name = f"{who}_crane"
            for c in head.users_collection:
                c.objects.unlink(head)
            coll.objects.link(head)
            con = head.constraints.new("COPY_LOCATION")
            con.target = empties[joint]
    print(f"Chorégraphie {data['tech']} importée : {len(frames)} clés, images 1 à {frames[-1]['frame']}.")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    path = "data/anims/uchi_mata.json"
    if "--anim" in argv:
        path = argv[argv.index("--anim") + 1]
    data, frames, _ = load(path)
    if "--print" in argv:
        for fr in frames:
            t, u = fr["tori"], fr["uke"]
            print(f"image {fr['frame']:3d}  tori bassin {t['bassin']} tête {t['tete']}  uke bassin {u['bassin']} tête {u['tete']}")
        return
    build(data, frames)


main()
