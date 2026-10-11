extends RefCounted
## Tournoi à élimination directe (8 combattants, 3 tours) contre l'IA.
## Les combats sans le joueur sont résolus de façon déterministe (graine).

const Build := preload("res://scripts/build.gd")

const ROUND_NAMES := ["QUART DE FINALE", "DEMI-FINALE", "FINALE"]
## Rivaux du tournoi : chacun a un build complet (set à ~15 points, style, garde, profil).
const RIVALS := [
	{"name": "KENJI", "tag": "Jambes & pression", "style": "haute", "garde": "gaucher",
		"slots": {"tokui": ["o_soto_gari"], "main": ["o_uchi_gari", "de_ashi_barai", "uchi_mata", ""], "combo": ["o_uchi_o_soto", ""],
			"counter": ["tsubame_gaeshi", ""], "ground": ["kesa_gatame", "yoko_shiho_gatame"]},
		"physique": {"explosivite": 5, "endurance": 6, "poigne": 6, "sol": 3}},
	{"name": "AYA", "tag": "Sol & contres", "style": "courte", "garde": "droitier",
		"slots": {"tokui": ["ko_uchi_gari"], "main": ["o_uchi_gari", "tai_otoshi", "", ""], "combo": ["ko_uchi_seoi", ""],
			"counter": ["ura_nage", "o_soto_gaeshi"], "ground": ["juji_gatame", "okuri_eri_jime"]},
		"physique": {"explosivite": 4, "endurance": 5, "poigne": 4, "sol": 8}},
	{"name": "MARCO", "tag": "Puissance", "style": "classique", "garde": "droitier",
		"slots": {"tokui": ["o_soto_gari"], "main": ["uchi_mata", "o_uchi_gari", "ko_uchi_gari", ""], "combo": ["o_uchi_o_soto", ""],
			"counter": ["tsubame_gaeshi", ""], "ground": ["kesa_gatame", ""]},
		"physique": {"explosivite": 6, "endurance": 4, "poigne": 7, "sol": 3}},
	{"name": "LÉA", "tag": "Contre-attaque", "style": "classique", "garde": "gaucher",
		"slots": {"tokui": ["seoi_nage"], "main": ["ko_uchi_gari", "o_uchi_gari", "tai_otoshi", ""], "combo": ["ko_uchi_seoi", ""],
			"counter": ["ura_nage", "o_soto_gaeshi"], "ground": ["kesa_gatame", "yoko_shiho_gatame"]},
		"physique": {"explosivite": 6, "endurance": 5, "poigne": 5, "sol": 4}},
	{"name": "YUKI", "tag": "Vitesse", "style": "courte", "garde": "droitier",
		"slots": {"tokui": ["de_ashi_barai"], "main": ["ko_uchi_gari", "sasae_tsurikomi_ashi", "o_uchi_gari", "tai_otoshi"], "combo": ["de_ashi_harai", ""],
			"counter": ["tsubame_gaeshi", ""], "ground": ["kesa_gatame", "juji_gatame"]},
		"physique": {"explosivite": 8, "endurance": 5, "poigne": 4, "sol": 4}},
	{"name": "SAMIR", "tag": "Garde haute", "style": "haute", "garde": "droitier",
		"slots": {"tokui": ["harai_goshi"], "main": ["o_goshi", "o_soto_gari", "o_uchi_gari", ""], "combo": ["", ""],
			"counter": ["utsuri_goshi", ""], "ground": ["kesa_gatame", "yoko_shiho_gatame"]},
		"physique": {"explosivite": 4, "endurance": 6, "poigne": 7, "sol": 4}},
	{"name": "TOM", "tag": "Débutant motivé", "style": "classique", "garde": "droitier",
		"slots": {"tokui": ["o_uchi_gari"], "main": ["o_goshi", "ko_uchi_gari", "", ""], "combo": ["", ""],
			"counter": ["", ""], "ground": ["kesa_gatame", ""]},
		"physique": {"explosivite": 4, "endurance": 4, "poigne": 4, "sol": 4}},
]


static func create(human_build: Dictionary, seed_value: int) -> Dictionary:
	var players = [{"name": human_build.name, "tag": human_build.get("tag", ""), "tokui": human_build.slots.tokui[0],
		"style": human_build.style, "garde": human_build.garde, "human": true, "power": 0, "build": human_build.duplicate(true)}]
	var power = [3, 2, 2, 3, 1, 2, 1]  # force relative des rivaux
	# rivaux : 7 légendes tirées de façon déterministe (sans le judoka choisi)
	var pool: Array = []
	for lg in preload("res://scripts/build.gd").legends():
		if lg.get("id", "") != human_build.get("id", "-"):
			pool.append(lg)
	var rivals: Array = []
	var st: int = seed_value * 2654435761 % 2147483647 + 1
	while rivals.size() < 7 and not pool.is_empty():
		st = (st * 1103515245 + 12345) & 0x7fffffff
		rivals.append(pool.pop_at(st % pool.size()))
	while rivals.size() < 7:
		rivals.append(RIVALS[rivals.size() % RIVALS.size()])
	for k in rivals.size():
		var rb: Dictionary = rivals[k].duplicate(true)
		var r := {"name": rb.name, "tag": rb.tag, "tokui": rb.slots.tokui[0], "style": rb.style, "garde": rb.garde,
			"human": false, "power": power[k], "build": rb}
		players.append(r)
	# placement : le joueur en haut, les rivaux répartis de façon déterministe
	var order = [0, 7, 4, 3, 2, 5, 6, 1]
	var seeded = []
	for idx in order:
		seeded.append(players[idx])
	var t = {"players": seeded, "round": 0, "seed": seed_value, "done": false, "champion": -1,
		"eliminated": false, "rounds": [[], [], []]}
	for m in 4:
		t.rounds[0].append({"a": m * 2, "b": m * 2 + 1, "winner": -1})
	return t


## Match du joueur pour le tour courant : {a, b} (indices dans players), ou {} si fini.
static func current_match(t: Dictionary) -> Dictionary:
	if t.done:
		return {}
	for m in t.rounds[t.round]:
		if t.players[m.a].human or t.players[m.b].human:
			return m
	return {}


static func opponent(t: Dictionary) -> Dictionary:
	var m = current_match(t)
	if m.is_empty():
		return {}
	return t.players[m.b] if t.players[m.a].human else t.players[m.a]


## Niveau de l'IA selon le tour et la force du rival.
static func ai_level(t: Dictionary) -> int:
	var o = opponent(t)
	return clampi(1 + t.round + (1 if o.get("power", 1) >= 3 else 0), 1, 3)


## Enregistre le résultat du joueur, résout les autres combats et passe au tour suivant.
static func record(t: Dictionary, human_won: bool) -> void:
	t.fresh = t.round  # tour qui vient d'être décidé (animation du tableau)
	var rng = t.seed * 31 + t.round * 7
	for m in t.rounds[t.round]:
		var pa: Dictionary = t.players[m.a]
		var pb: Dictionary = t.players[m.b]
		if pa.human or pb.human:
			var human_is_a: bool = pa.human
			m.winner = m.a if (human_won == human_is_a) else m.b
		else:
			rng = (rng * 1103515245 + 12345) & 0x7fffffff
			var bias: int = (pa.power - pb.power) * 20
			m.winner = m.a if (rng >> 8) % 100 < 50 + bias else m.b
	if not human_won:
		t.eliminated = true
		t.done = true
		return
	if t.round == 2:
		t.done = true
		t.champion = t.rounds[2][0].winner
		return
	var winners = []
	for m in t.rounds[t.round]:
		winners.append(m.winner)
	t.round += 1
	for k in winners.size() / 2:
		t.rounds[t.round].append({"a": winners[k * 2], "b": winners[k * 2 + 1], "winner": -1})
