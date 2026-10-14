extends RefCounted
## Réglages du joueur, sauvegardés dans user://settings.json.

const PATH := "user://settings.json"

static var _data := {}

const DEFAULTS := {
	"vibrations": true,
	"vibration_force": 3,      # 1..5
	"volume_master": 8,        # 0..10
	"volume_music": 6,
	"volume_sfx": 8,
	"fullscreen": false,
	"vsync": true,
	"ai_level": 2,             # 1..3
	"radar": true,             # radar de kuzushi dans le HUD
	"hints": true,             # barre d'aide des commandes en combat
	"feed": true,              # fil des événements en combat
	"readout": true,
	"format": "bo3",           # "bo3" : deux manches gagnantes ; "single" : un seul combat
	"match_minutes": 2,        # durée réglementaire d'une manche
	"golden_limit": 1,         # golden score : 0 = illimité, sinon minutes avant décision
	"replay": true,            # ralenti de la projection gagnante
	"decor": "arena",           # décor de combat (data/stages.json)
	"peripherique": "auto",    # "auto" (manette si branchée, sinon clavier), "manette", "clavier"
	"clavier": {},             # touches redéfinies : action → code touche (voir key_reader.gd)
}


static func get_all() -> Dictionary:
	if _data.is_empty():
		_data = DEFAULTS.duplicate()
		if FileAccess.file_exists(PATH):
			var f := FileAccess.open(PATH, FileAccess.READ)
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				for k in parsed:
					if _data.has(k):
						_data[k] = int(parsed[k]) if typeof(DEFAULTS[k]) == TYPE_INT else parsed[k]
		if typeof(_data.get("clavier")) != TYPE_DICTIONARY:
			_data["clavier"] = {}
	return _data


static func value(key: String):
	return get_all().get(key, DEFAULTS.get(key))


static func set_value(key: String, v) -> void:
	get_all()[key] = v


static func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(get_all(), "  "))


## Applique les réglages d'affichage.
static func apply() -> void:
	var d := get_all()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if d.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if d.vsync else DisplayServer.VSYNC_DISABLED)


## Petite vibration de manette (impact, projection), si activée.
static func rumble(device: int, strength: float, seconds: float) -> void:
	if not value("vibrations"):
		return
	var f: float = clampf(strength * float(value("vibration_force")) / 3.0, 0.0, 1.0)
	Input.start_joy_vibration(device, f * 0.6, f, seconds)
