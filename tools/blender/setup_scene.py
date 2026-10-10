"""Prépare une scène Blender pour animer une technique de judo à partir d'une vidéo.

À lancer dans Blender (4.x) :
    blender --python tools/blender/setup_scene.py -- --video rushes/tech_seoi_nage_droitier_prise3.mp4
ou depuis l'éditeur de texte de Blender (Run Script), en réglant VIDEO ci-dessous.

Ce que fait le script :
  1. Règle la scène : 60 i/s, unités en mètres, résolution 1200×720.
  2. Crée la caméra ORTHOGRAPHIQUE de profil (axe -Y), fixe, cadrage « jeu ».
  3. Ajoute un éclairage simple (clé + contre-jour coloré façon 2XKO).
  4. Crée le matériau toon (cel-shading 2 tons) pour judogi blanc / bleu / peau / ceinture,
     et l'outline (modificateur Solidify inversé) appliqués aux objets dont le nom commence
     par « tori » ou « uke ».
  5. Place la vidéo en image de fond de la caméra, à la bonne cadence, pour caler l'animation.
  6. Ajoute deux repères (Empty) : SOL (y = 0) et PIEDS_TORI (point d'ancrage du jeu).

Conventions attendues pour l'export (voir docs/PIPELINE_ANIMATION.md) :
  - 1 unité Blender = 1 mètre ; un judoka d'environ 1,80 m = 100 unités de jeu.
  - tori regarde vers +X au début de la technique.
  - Les objets de tori sont rangés dans la collection « TORI », ceux d'uke dans « UKE ».
"""
import sys
import math
from pathlib import Path

import bpy

VIDEO = ""  # chemin de la vidéo si lancé depuis l'éditeur de texte

# Échelle du jeu : 100 unités de jeu = 1,80 m ; le jeu cuit les sprites à 4 px par unité.
METERS_PER_UNIT = 1.8 / 100.0
UNIT_PX = 4.0
RES_X, RES_Y = 1200, 720
PIVOT_PX = (560, 650)  # position des pieds de tori dans l'image (identique au jeu)

PALETTE = {
    "gi_blanc": ((0.95, 0.93, 0.89), (0.73, 0.69, 0.62)),
    "gi_bleu": ((0.16, 0.37, 0.88), (0.10, 0.23, 0.61)),
    "peau_claire": ((0.91, 0.72, 0.56), (0.75, 0.54, 0.39)),
    "peau_foncee": ((0.60, 0.39, 0.25), (0.45, 0.27, 0.16)),
    "ceinture": ((0.09, 0.08, 0.12), (0.05, 0.04, 0.07)),
}
INK = (0.043, 0.039, 0.078)


def args() -> dict:
    out = {"video": VIDEO}
    if "--" in sys.argv:
        a = sys.argv[sys.argv.index("--") + 1:]
        for k in range(len(a)):
            if a[k] == "--video" and k + 1 < len(a):
                out["video"] = a[k + 1]
    return out


def setup_render(scene: bpy.types.Scene) -> None:
    scene.render.fps = 60
    scene.unit_settings.system = "METRIC"
    scene.render.resolution_x = RES_X
    scene.render.resolution_y = RES_Y
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.engine = "BLENDER_EEVEE_NEXT" if bpy.app.version >= (4, 2, 0) else "BLENDER_EEVEE"
    scene.view_settings.view_transform = "Standard"  # couleurs franches, pas de Filmic/AgX
    # Freestyle : contours d'encre en plus de l'outline (désactivable si trop lent)
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = 2.5
    vl = scene.view_layers[0]
    if vl.freestyle_settings.linesets:
        ls = vl.freestyle_settings.linesets[0]
        ls.linestyle.color = INK
        ls.linestyle.thickness = 2.5


def setup_camera(scene: bpy.types.Scene) -> bpy.types.Object:
    cam_data = bpy.data.cameras.get("CAM_JEU") or bpy.data.cameras.new("CAM_JEU")
    cam_data.type = "ORTHO"
    # largeur de l'image en mètres = RES_X px / UNIT_PX px par unité × METERS_PER_UNIT
    cam_data.ortho_scale = RES_X / UNIT_PX * METERS_PER_UNIT
    cam = bpy.data.objects.get("CAM_JEU") or bpy.data.objects.new("CAM_JEU", cam_data)
    if cam.name not in scene.collection.objects:
        scene.collection.objects.link(cam)
    # caméra de profil, regardant vers +Y, cadrée pour que les pieds de tori soient au pivot
    half_w = cam_data.ortho_scale / 2.0
    half_h = half_w * RES_Y / RES_X
    px_to_m = METERS_PER_UNIT / UNIT_PX
    cam.location = (half_w - PIVOT_PX[0] * px_to_m, -10.0, PIVOT_PX[1] * px_to_m - half_h)
    cam.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    scene.camera = cam
    return cam


def setup_lights(scene: bpy.types.Scene) -> None:
    for name, energy, color, rot in [
        ("CLE", 3.0, (1.0, 0.97, 0.92), (math.radians(50), 0, math.radians(-30))),
        ("CONTRE", 2.0, (1.0, 0.82, 0.25), (math.radians(60), 0, math.radians(150))),
    ]:
        data = bpy.data.lights.get(name) or bpy.data.lights.new(name, "SUN")
        data.energy = energy
        data.color = color
        obj = bpy.data.objects.get(name) or bpy.data.objects.new(name, data)
        if obj.name not in scene.collection.objects:
            scene.collection.objects.link(obj)
        obj.rotation_euler = rot


def toon_material(name: str, lit: tuple, shade: tuple) -> bpy.types.Material:
    """Cel-shading 2 tons : Diffuse → Shader to RGB → ColorRamp (constant)."""
    mat = bpy.data.materials.get("TOON_" + name) or bpy.data.materials.new("TOON_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    to_rgb = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    emit = nt.nodes.new("ShaderNodeEmission")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (*shade, 1.0)
    ramp.color_ramp.elements[1].position = 0.45
    ramp.color_ramp.elements[1].color = (*lit, 1.0)
    nt.links.new(diff.outputs["BSDF"], to_rgb.inputs["Shader"])
    nt.links.new(to_rgb.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


def outline_material() -> bpy.types.Material:
    mat = bpy.data.materials.get("TOON_ENCRE") or bpy.data.materials.new("TOON_ENCRE")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (*INK, 1.0)
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    mat.use_backface_culling = True
    return mat


def setup_materials() -> None:
    mats = {k: toon_material(k, *v) for k, v in PALETTE.items()}
    ink = outline_material()
    for obj in bpy.data.objects:
        n = obj.name.lower()
        if obj.type != "MESH" or not (n.startswith("tori") or n.startswith("uke")):
            continue
        # outline : copie inversée légèrement gonflée
        if "OUTLINE" not in obj.modifiers:
            mod = obj.modifiers.new("OUTLINE", "SOLIDIFY")
            mod.thickness = -0.012
            mod.use_flip_normals = True
            mod.material_offset = 1
        if ink.name not in [m.name for m in obj.data.materials if m]:
            obj.data.materials.append(ink)
    print("Matériaux toon prêts :", ", ".join(m.name for m in mats.values()))
    print("Assigne TOON_gi_blanc / TOON_gi_bleu / TOON_peau_* / TOON_ceinture à tes maillages.")


def setup_reference(cam: bpy.types.Object, video: str) -> None:
    if not video:
        print("Pas de vidéo fournie : ajoute-la plus tard (Caméra > Images de fond).")
        return
    path = Path(video).resolve()
    if not path.exists():
        print("Vidéo introuvable :", path)
        return
    clip = bpy.data.movieclips.load(str(path))
    cam.data.show_background_images = True
    bg = cam.data.background_images.new()
    bg.source = "MOVIE_CLIP"
    bg.clip = clip
    bg.alpha = 0.5
    bg.display_depth = "BACK"
    bg.frame_method = "FIT"
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = clip.frame_duration
    print(f"Référence : {path.name} ({clip.frame_duration} images)")


def setup_markers(scene: bpy.types.Scene) -> None:
    for name, loc in [("SOL", (0, 0, 0)), ("PIEDS_TORI", (0, 0, 0))]:
        if name not in bpy.data.objects:
            e = bpy.data.objects.new(name, None)
            e.empty_display_type = "PLAIN_AXES" if name == "SOL" else "SINGLE_ARROW"
            e.empty_display_size = 0.3
            e.location = loc
            scene.collection.objects.link(e)
    for coll in ["TORI", "UKE"]:
        if coll not in bpy.data.collections:
            c = bpy.data.collections.new(coll)
            scene.collection.children.link(c)


def main() -> None:
    a = args()
    scene = bpy.context.scene
    setup_render(scene)
    cam = setup_camera(scene)
    setup_lights(scene)
    setup_markers(scene)
    setup_materials()
    setup_reference(cam, a["video"])
    print("Scène prête. Anime tori et uke (collections TORI / UKE), puis lance render_sprites.py.")


main()
