extends RefCounted
## Décors de combat (data/stages.json).
##
## Un décor ne couvre que le haut de la scène : le tatami reste dessiné par le jeu, parce
## que ses bords sont ceux de la simulation (`cfg.mat_left` / `mat_right`) et qu'un judoka
## sort du tapis à un pixel près. L'image est posée de façon à ce que son `horizon` — la
## hauteur à laquelle le tatami y commence — tombe sur le bord arrière du tatami du jeu,
## puis agrandie pour couvrir la largeur. Un décor plus haut que nécessaire est rogné par
## le haut ; une image en 16:9 se cadre donc mieux qu'une image carrée.

const GameData := preload("res://scripts/game_data.gd")
const Settings := preload("res://scripts/settings.gd")

static var _data: Dictionary = {}
static var _textures: Dictionary = {}


static func _load() -> Dictionary:
	if _data.is_empty():
		_data = GameData.load_json("res://data/stages.json")
	return _data


static func all() -> Array:
	return _load().get("stages", [])


static func ids() -> Array:
	var out := []
	for s in all():
		out.append(String(s.id))
	return out


static func labels() -> Array:
	var out := []
	for s in all():
		out.append(String(s.nom))
	return out


static func default_id() -> String:
	return String(_load().get("defaut", "arena"))


static func get_stage(id: String) -> Dictionary:
	for s in all():
		if String(s.id) == id:
			return s
	for s in all():
		if String(s.id) == default_id():
			return s
	return {}


## Décor choisi dans les options, ou imposé par `--decor=<id>` (captures et vidéos).
static func current() -> Dictionary:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--decor="):
			return get_stage(a.substr(8))
	return get_stage(String(Settings.value("decor")))


## Texture du décor courant, ou null (décor dessiné, ou image manquante).
static func texture(st: Dictionary) -> Texture2D:
	var path := String(st.get("image", ""))
	if path == "":
		return null
	if not _textures.has(path):
		_textures[path] = null
		if ResourceLoader.exists(path):
			_textures[path] = load(path)
		elif FileAccess.file_exists(path):
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img != null:
				_textures[path] = ImageTexture.create_from_image(img)
	return _textures[path]


## Rectangle où dessiner l'image : son horizon tombe sur `mat_back`, et elle couvre au
## moins `w` de large. `marge` élargit un peu pour que la parallaxe ne découvre pas de bord.
static func rect(tex: Texture2D, st: Dictionary, w: float, mat_back: float,
		marge: float = 1.25) -> Rect2:
	var ts := Vector2(tex.get_width(), tex.get_height())
	var h := float(st.get("horizon", 0.5))
	var cible_w := w * marge
	var k := cible_w / ts.x
	if ts.y * h * k < mat_back:              # l'image ne descend pas assez bas
		k = mat_back / maxf(1.0, ts.y * h)
	var size := ts * k
	return Rect2(Vector2((w - size.x) * 0.5, mat_back - size.y * h), size)
