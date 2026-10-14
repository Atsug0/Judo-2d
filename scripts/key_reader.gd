extends RefCounted
## Lecture du clavier vers le tableau d'entrées de la simulation, en miroir de
## scripts/pad_reader.gd. Une instance par joueur : contrairement à la manette, le clavier
## demande de la mémoire d'un tick à l'autre (voir les rampes ci-dessous).
##
## La manette donne trois signaux analogiques que le clavier n'a pas :
##
## - **le déplacement** (`MX`). La simulation lit un *dash* quand `|MX|` passe de moins de
##   85 à plus de 85 en moins de `dash_flick_ticks` (3) ticks — une pichenette franche du
##   stick. Une touche, qui passe de 0 à 100 d'un coup, déclencherait donc un dash à chaque
##   appui. On fait monter `MX` par paliers de `RAMPE_PAS` : il franchit 85 au 5ᵉ tick,
##   quand le compteur de la simulation a déjà dépassé 3, et le judoka marche simplement.
##   Le dash a sa propre touche, qui elle force 100 tout de suite.
## - **la force des saisies** (`LT`, `RT`) : monte tant que la touche est tenue, retombe à
##   zéro dès qu'on la lâche (lâcher la gâchette, c'est lâcher la prise).
## - **le kuzushi** (`PX`, `PY`) : 8 directions au lieu de 360°, ce qui suffit — les seuils
##   de la simulation sont à ±60.
##
## Les rampes sont comptées en **ticks de simulation** (read() est appelé une fois par tick),
## jamais en temps réel : le déterminisme et les replays en dépendent.

const Sim := preload("res://scripts/sim/match_sim.gd")
const Settings := preload("res://scripts/settings.gd")

const RAMPE_PAS := 20      # déplacement : +20 par tick (85 franchi au 5ᵉ tick)
const RAMPE_PRISE := 14    # saisie : pleine force en ~7 ticks
const DASH_TICKS := 5      # 1 tick au neutre (pour que la simulation voie la pichenette) + 4 à fond

## Touches par défaut, pensées pour un clavier AZERTY : main gauche sur les déplacements et
## les saisies, main droite sur le kuzushi (flèches) et les attaques.
const DEFAUT := {
	"gauche": KEY_Q, "droite": KEY_D, "dash": KEY_SHIFT,
	"main_g": KEY_A, "main_d": KEY_E,
	"cible_g": KEY_Z, "cible_d": KEY_R,
	"kuzushi_ar": KEY_LEFT, "kuzushi_av": KEY_RIGHT,
	"kuzushi_g": KEY_UP, "kuzushi_d": KEY_DOWN,
	"technique": KEY_K, "jambe": KEY_L, "tokui": KEY_O, "casser": KEY_M,
}

## Ordre d'affichage dans les options, avec le libellé et le bouton de manette équivalent.
const ACTIONS := [
	["gauche", "Reculer", "LS"], ["droite", "Avancer", "LS"],
	["dash", "Dash (avec une direction)", "LS"],
	["main_g", "Main gauche : saisir", "LT"], ["main_d", "Main droite : saisir", "RT"],
	["cible_g", "Cible main gauche", "LB"], ["cible_d", "Cible main droite", "RB"],
	["kuzushi_ar", "Kuzushi : tirer", "RS"], ["kuzushi_av", "Kuzushi : pousser", "RS"],
	["kuzushi_g", "Kuzushi : côté gauche", "RS"], ["kuzushi_d", "Kuzushi : côté droit", "RS"],
	["technique", "Technique selon le kuzushi", "A"], ["jambe", "Technique de jambe", "X"],
	["tokui", "Tokui-waza", "Y"], ["casser", "Casser la prise / contrer", "B"],
]

var _mx := 0            # amplitude courante du déplacement (0..100)
var _sens := 0          # -1 / +1 : direction tenue
var _lt := 0
var _rt := 0
var _dash := 0          # ticks restants de la pichenette
var _dash_tenu := false # état de la touche de dash au tick précédent


## Touches réglées par le joueur, complétées par les valeurs par défaut.
static func touches() -> Dictionary:
	var t := DEFAUT.duplicate()
	var reglees = Settings.value("clavier")
	if typeof(reglees) == TYPE_DICTIONARY:
		for k in reglees:
			if t.has(k):
				t[k] = int(reglees[k])
	return t


## Nom affichable d'une touche (« Q », « MAJ », « ← »).
static func nom(code: int) -> String:
	match code:
		KEY_SHIFT: return "MAJ"
		KEY_CTRL: return "CTRL"
		KEY_ALT: return "ALT"
		KEY_SPACE: return "ESPACE"
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
		KEY_ENTER: return "ENTRÉE"
	var s := OS.get_keycode_string(code)
	return s if s != "" else "?"


## Nom de la touche liée à une action (pour l'affichage des aides en combat).
static func nom_action(action: String) -> String:
	return nom(int(touches().get(action, DEFAUT.get(action, 0))))


static func _on(t: Dictionary, action: String) -> bool:
	return Input.is_key_pressed(int(t.get(action, DEFAUT.get(action, 0))))


## Entrées d'un tick de simulation. À appeler **une fois par tick**, pas par image.
func read() -> Array:
	var a := Sim.empty_input()
	var t := touches()

	# --- déplacement : rampe, et pichenette franche sur la touche de dash
	var sens := 0
	if _on(t, "gauche"):
		sens -= 1
	if _on(t, "droite"):
		sens += 1
	var dash_tenu := _on(t, "dash")
	if dash_tenu and not _dash_tenu and sens != 0:
		_dash = DASH_TICKS
	_dash_tenu = dash_tenu
	if sens != _sens:
		_mx = 0                     # changement de sens : on repart du neutre
	_sens = sens
	if _dash > 0:
		_dash -= 1
		# un tick au neutre pour que la simulation voie bien le passage sous 85,
		# puis plein régime : c'est ce saut qu'elle lit comme une pichenette
		_mx = 0 if _dash >= DASH_TICKS - 1 else 100
	elif sens == 0:
		_mx = 0
	else:
		_mx = mini(100, _mx + RAMPE_PAS)
	a[Sim.MX] = _mx * sens

	# --- kuzushi : 8 directions
	if _on(t, "kuzushi_av"):
		a[Sim.PX] += 100
	if _on(t, "kuzushi_ar"):
		a[Sim.PX] -= 100
	if _on(t, "kuzushi_d"):
		a[Sim.PY] += 100
	if _on(t, "kuzushi_g"):
		a[Sim.PY] -= 100

	# --- saisies : la force monte tant que la touche est tenue
	_lt = mini(100, _lt + RAMPE_PRISE) if _on(t, "main_g") else 0
	_rt = mini(100, _rt + RAMPE_PRISE) if _on(t, "main_d") else 0
	a[Sim.LT] = _lt
	a[Sim.RT] = _rt

	a[Sim.LB] = 1 if _on(t, "cible_g") else 0
	a[Sim.RB] = 1 if _on(t, "cible_d") else 0
	a[Sim.BA] = 1 if _on(t, "technique") else 0
	a[Sim.BX] = 1 if _on(t, "jambe") else 0
	a[Sim.BY] = 1 if _on(t, "tokui") else 0
	a[Sim.BB] = 1 if _on(t, "casser") else 0
	return a
