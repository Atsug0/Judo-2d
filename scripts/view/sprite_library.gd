extends RefCounted
## Bibliothèque d'animations en sprites pour un personnage (une tenue).
##
## Dossier : res://animations/<id>/manifest.json + un sous-dossier d'images par animation.
## Le même format sert pour les sprites rendus depuis Blender et pour les
## placeholders « cuits » par tools/bake_placeholders.gd.
##
## manifest.json :
## {
##   "character": "hugo_blanc",
##   "unit_px": 4.0,                 # pixels d'image par unité de jeu (un judoka debout = 100 unités)
##   "fps": 12,
##   "anims": {
##     "idle": {"dir": "idle", "count": 8, "loop": true, "pivot": [320, 600]},
##     "throw/seoi_nage/tori": {"dir": "throw__seoi_nage__tori", "count": 12, "pivot": [320, 600], "anchor": "tori"},
##     "throw/seoi_nage/uke":  {"dir": "throw__seoi_nage__uke",  "count": 12, "pivot": [320, 600], "anchor": "tori"}
##   }
## }
## pivot = position des pieds (au sol) dans l'image. anchor "tori" : l'image est cadrée
## sur les pieds de tori au début de la projection (tori et uke partagent la même caméra).

var id := ""
var unit_px := 4.0
var fps := 12
var anims := {}  # nom -> {frames: Array[Texture2D], pivot: Vector2, loop: bool, anchor: String}


static func load_character(char_id: String):
	var base := "res://animations/%s" % char_id
	var mpath := base + "/manifest.json"
	if not FileAccess.file_exists(mpath):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Manifeste invalide : " + mpath)
		return null
	var lib = load("res://scripts/view/sprite_library.gd").new()
	lib.id = char_id
	lib.unit_px = float(parsed.get("unit_px", 4.0))
	lib.fps = int(parsed.get("fps", 12))
	for name in parsed.get("anims", {}):
		var a: Dictionary = parsed.anims[name]
		var frames := []
		for k in int(a.get("count", 0)):
			var tex := _load_tex("%s/%s/%04d.png" % [base, a.dir, k + 1])
			if tex == null:
				break
			frames.append(tex)
		if frames.is_empty():
			continue
		var pv: Array = a.get("pivot", [0, 0])
		lib.anims[name] = {"frames": frames, "pivot": Vector2(pv[0], pv[1]), "loop": bool(a.get("loop", false)),
			"anchor": String(a.get("anchor", "self"))}
	return lib


## Charge une image : ressource importée si possible, sinon directement le PNG
## (utile quand on vient d'ajouter des images sans repasser par l'éditeur).
static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(abs_path):
		return null
	var img := Image.load_from_file(abs_path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func has(name: String) -> bool:
	return anims.has(name)


func frame_count(name: String) -> int:
	return anims[name].frames.size() if anims.has(name) else 0


## Dessine une image d'animation.
## progress : 0..1 (animations à durée imposée) ou -1 pour utiliser `ticks` en boucle.
## feet : position écran des pieds (ou des pieds de tori si anchor = "tori").
## scale : pixels écran par unité de jeu (K dans l'écran de combat).
func draw(ci: CanvasItem, name: String, progress: float, ticks: int, feet: Vector2, facing: int, scale: float,
		lean: float = 0.0, modulate: Color = Color.WHITE) -> void:
	var a: Dictionary = anims[name]
	var n: int = a.frames.size()
	var idx := 0
	if progress >= 0.0:
		idx = clampi(int(progress * n), 0, n - 1)
	else:
		var f := ticks * fps / 60
		idx = f % n if a.loop else mini(f, n - 1)
	var tex: Texture2D = a.frames[idx]
	var s := scale / unit_px
	ci.draw_set_transform_matrix(Transform2D(facing * lean, Vector2(facing * s, s), 0.0, feet))
	ci.draw_texture(tex, -a.pivot, modulate)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
