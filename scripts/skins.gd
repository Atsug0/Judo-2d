extends RefCounted
## Catalogue des personnages 3D (data/skins.json).
##
## On ne personnalise plus le visage, les cheveux ni la carrure : on choisit un
## **personnage**. `look.modele` porte l'identifiant du skin (l'ancienne clé `look.skin`
## reste la teinte de peau du dessin vectoriel de secours, à ne pas confondre).
##
## La couleur du judogi n'est pas un choix : P1 est en blanc, P2 en bleu, comme en
## compétition. Chaque skin donne donc deux dossiers de modèle. Les quatre « basic »
## existent vraiment dans les deux couleurs ; pour les autres, le même modèle est réutilisé
## avec une texture bleue (`texture_bleu.jpg`, générée par tools/rig/gi_variantes.py).

const GameData := preload("res://scripts/game_data.gd")
const MODELS_DIR := "res://assets/judokas"

static var _data: Dictionary = {}


static func _load() -> Dictionary:
	if _data.is_empty():
		_data = GameData.load_json("res://data/skins.json")
	return _data


## Tous les skins du catalogue, dans l'ordre d'affichage.
static func all() -> Array:
	return _load().get("skins", [])


static func default_id() -> String:
	return String(_load().get("defaut", "basic_h"))


static func ids() -> Array:
	var out := []
	for s in all():
		out.append(String(s.id))
	return out


## Fiche d'un skin ; repli sur le skin par défaut si l'identifiant est inconnu
## (sauvegarde d'une ancienne version, skin retiré du catalogue).
static func get_skin(id: String) -> Dictionary:
	for s in all():
		if String(s.id) == id:
			return s
	for s in all():
		if String(s.id) == default_id():
			return s
	return {}


## Nom affiché, avec le sexe en second plan pour distinguer les deux « CLASSIQUE ».
static func label(id: String) -> String:
	var s := get_skin(id)
	if s.is_empty():
		return id
	if bool(s.get("base", false)):
		return String(s.nom) + (" (F)" if String(s.get("sexe", "h")) == "f" else " (H)")
	return String(s.nom)


## Dossier du modèle à charger pour ce joueur (0 = judogi blanc, 1 = bleu).
static func dir_for(id: String, player: int) -> String:
	var s := get_skin(id)
	if s.is_empty():
		return "men_basic_white"
	return String(s.get("bleu" if player == 1 else "blanc", s.get("blanc", "")))


## Texture à plaquer sur le modèle, quand il faut reteindre le judogi en bleu pour P2
## (skins qui n'existent pas en bleu). "" = garder la texture d'origine du modèle.
static func texture_for(id: String, player: int) -> String:
	if player != 1:
		return ""
	var s := get_skin(id)
	if s.is_empty() or String(s.get("bleu", "")) != String(s.get("blanc", "")):
		return ""       # le modèle bleu existe pour de vrai
	var path := MODELS_DIR + "/" + String(s.blanc) + "/texture_bleu.jpg"
	return path if FileAccess.file_exists(path) else ""


## Skin d'un judoka, avec repli sur le défaut du catalogue.
static func of(look: Dictionary) -> String:
	var id := String(look.get("modele", ""))
	if id == "":        # ancienne clé body3d : 0 = homme, 1 = femme
		id = "basic_f" if int(look.get("body3d", 0)) == 1 else default_id()
	return id
