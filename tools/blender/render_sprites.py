"""Rend une animation Blender en sprites pour le jeu (tori et uke séparés).

    blender scenes/seoi_nage.blend --background --python tools/blender/render_sprites.py -- \\
        --anim throw/seoi_nage --character hugo_blanc --uke-character kenji_bleu \\
        --start 40 --end 112 --frames 12

Sortie (dans le projet Godot) :
    animations/<character>/<anim>__tori/0001.png ...  (collection TORI seule)
    animations/<uke-character>/<anim>__uke/0001.png ...   (collection UKE seule)
    + mise à jour des manifest.json de chaque personnage (création si besoin).

Les deux rendus partagent la même caméra : le pivot (pieds de tori) est le même,
ce qui garde la projection synchronisée dans le jeu (anchor = "tori").

Pour une animation à un seul personnage (garde, marche, entrée…), omettre --uke-character :
seule la collection TORI est rendue, sous animations/<character>/<anim>/.
"""
import json
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
PIVOT = [560, 650]   # doit correspondre à setup_scene.py
UNIT_PX = 4.0


def parse() -> dict:
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"anim": None, "character": None, "uke-character": None, "start": None, "end": None,
            "frames": 12, "loop": False}
    k = 0
    while k < len(a):
        key = a[k].lstrip("-")
        if key == "loop":
            opts["loop"] = True
            k += 1
            continue
        opts[key] = a[k + 1]
        k += 2
    if not opts["anim"] or not opts["character"]:
        raise SystemExit("--anim et --character sont obligatoires")
    return opts


def set_visible(coll_name: str, visible: bool) -> None:
    coll = bpy.data.collections.get(coll_name)
    if coll is None:
        raise SystemExit(f"Collection {coll_name} introuvable (voir setup_scene.py)")
    coll.hide_render = not visible


def render_role(coll_visible: str, coll_hidden: str | None, out_dir: Path, frames: list[int]) -> None:
    set_visible(coll_visible, True)
    if coll_hidden:
        set_visible(coll_hidden, False)
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("*.png"):
        old.unlink()
    scene = bpy.context.scene
    for idx, f in enumerate(frames, start=1):
        scene.frame_set(f)
        scene.render.filepath = str(out_dir / f"{idx:04d}.png")
        bpy.ops.render.render(write_still=True)
    if coll_hidden:
        set_visible(coll_hidden, True)


def update_manifest(character: str, anim: str, dir_name: str, count: int, loop: bool, anchor: str) -> None:
    base = ROOT / "animations" / character
    path = base / "manifest.json"
    data = {"character": character, "unit_px": UNIT_PX, "fps": 12, "anims": {}}
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
    data["anims"][anim] = {"dir": dir_name, "count": count, "loop": loop, "pivot": PIVOT, "anchor": anchor}
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def main() -> None:
    o = parse()
    scene = bpy.context.scene
    start = int(o["start"] or scene.frame_start)
    end = int(o["end"] or scene.frame_end)
    n = int(o["frames"])
    # échantillonnage régulier de la plage à n images (12 i/s dans le jeu)
    frames = [round(start + (end - start) * k / max(1, n - 1)) for k in range(n)]
    anim = o["anim"]
    dir_name = anim.replace("/", "__")
    if o["uke-character"]:
        render_role("TORI", "UKE", ROOT / "animations" / o["character"] / f"{dir_name}__tori", frames)
        update_manifest(o["character"], anim + "/tori", f"{dir_name}__tori", n, o["loop"], "tori")
        render_role("UKE", "TORI", ROOT / "animations" / o["uke-character"] / f"{dir_name}__uke", frames)
        update_manifest(o["uke-character"], anim + "/uke", f"{dir_name}__uke", n, o["loop"], "tori")
    else:
        render_role("TORI", "UKE", ROOT / "animations" / o["character"] / dir_name, frames)
        update_manifest(o["character"], anim, dir_name, n, o["loop"], "self")
    print(f"{anim} : {n} images rendues (images {start} → {end}).")


main()
