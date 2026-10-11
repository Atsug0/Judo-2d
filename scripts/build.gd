extends RefCounted
## Build d'un combattant : set de techniques (budget 15), garde, style de kumikata,
## profil physique (budget à rendements décroissants). Sauvegarde dans user://builds.json.

const GameData := preload("res://scripts/game_data.gd")
const SAVE_PATH := "user://builds.json"

static var _catalog := {}


static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = GameData.load_json("res://data/catalog.json")
	return _catalog


static func defaults() -> Array:
	return [
		{"name": "HUGO", "tag": "Spécialiste seoi", "garde": "droitier", "style": "classique",
			"slots": {"tokui": ["seoi_nage"], "main": ["o_soto_gari", "o_uchi_gari", "ko_uchi_gari", "de_ashi_barai"],
				"combo": ["ko_uchi_seoi", ""], "counter": ["ura_nage", ""], "ground": ["kesa_gatame", ""]},
			"physique": {"explosivite": 6, "endurance": 5, "poigne": 5, "sol": 3}},
		{"name": "KENJI", "tag": "Jambes & pression", "garde": "gaucher", "style": "haute",
			"slots": {"tokui": ["o_soto_gari"], "main": ["o_uchi_gari", "de_ashi_barai", "uchi_mata", ""],
				"combo": ["o_uchi_o_soto", ""], "counter": ["tsubame_gaeshi", ""], "ground": ["kesa_gatame", "yoko_shiho_gatame"]},
			"physique": {"explosivite": 5, "endurance": 6, "poigne": 6, "sol": 3}},
		{"name": "AYA", "tag": "Sol & contres", "garde": "droitier", "style": "courte",
			"slots": {"tokui": ["ko_uchi_gari"], "main": ["o_uchi_gari", "tai_otoshi", "", ""],
				"combo": ["ko_uchi_seoi", ""], "counter": ["ura_nage", "o_soto_gaeshi"], "ground": ["juji_gatame", "okuri_eri_jime"]},
			"physique": {"explosivite": 4, "endurance": 5, "poigne": 4, "sol": 8}},
	]


static func kind_of(slot_id: String) -> String:
	for s in catalog().slots:
		if s.id == slot_id:
			return s.kind
	return "technique"


static func entry(kind: String, id: String) -> Dictionary:
	if id == "":
		return {}
	return catalog()[kind].get(id, {})


static func set_cost(b: Dictionary) -> int:
	var total := 0
	for s in catalog().slots:
		for id in b.slots[s.id]:
			total += int(entry(s.kind, id).get("cost", 0))
	return total


## Coût en points pour passer une stat physique de v à v+1 (rendements décroissants).
static func step_cost(v: int) -> int:
	if v < 5:
		return 1
	if v < 7:
		return 2
	return 3


static func physique_cost(b: Dictionary) -> int:
	var phys: Dictionary = catalog().physique
	var total := 0
	for st in phys.stats:
		var v: int = phys.base
		while v < int(b.physique[st.id]):
			total += step_cost(v)
			v += 1
	return total


static func load_all() -> Array:
	var list: Array = defaults()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_ARRAY and parsed.size() > 0:
			list = GameData._to_ints(parsed)
	for k in list.size():
		_normalize(list[k], k)
	return list


## Complète un judoka créé par le joueur (identifiant, apparence, surnom).
static func _normalize(b: Dictionary, k: int) -> void:
	if not b.has("id"):
		b.id = "u%d_%s" % [k, String(b.get("name", "J")).to_lower()]
	if not b.has("look"):
		b.look = {"skin": [1, 3, 2, 0][k % 4], "hair": [0, 1, 3, 2][k % 4], "hair_color": [1, 0, 0, 2][k % 4]}
	if not b.look.has("body3d"):
		b.look.body3d = 1 if String(b.get("name", "")).to_upper() in ["AYA"] else 0
	if not b.has("nick"):
		b.nick = ""
	if not b.has("tag"):
		b.tag = "Mon judoka"


static var _legends: Array = []


## Judokas pré-configurés (data/legends.json).
static func legends() -> Array:
	if _legends.is_empty():
		_legends = GameData._to_ints(GameData.load_json("res://data/legends.json").legends)
	return _legends


## Tous les judokas jouables : ceux du joueur, puis les légendes.
static func roster() -> Array:
	return load_all() + legends()


static func find(id: String) -> Dictionary:
	for b in roster():
		if b.get("id", "") == id:
			return b
	return {}


## Nouveau judoka (copie d'un modèle, ou base classique).
static func new_judoka(from: Dictionary = {}, index: int = 0) -> Dictionary:
	var b: Dictionary = (from if not from.is_empty() else defaults()[0]).duplicate(true)
	b.erase("legend")
	b.erase("bio")
	b.erase("inspiration")
	b.id = "u%d_%d" % [index, Time.get_ticks_msec() % 100000]
	b.name = "JUDOKA %d" % (index + 1) if from.is_empty() else String(from.name)
	b.nick = "" if from.is_empty() else String(from.get("nick", ""))
	b.tag = "Mon judoka"
	if not b.has("look"):
		b.look = {"skin": 1, "hair": 0, "hair_color": 1}
	return b


static func save_all(builds: Array) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(builds, "  "))
