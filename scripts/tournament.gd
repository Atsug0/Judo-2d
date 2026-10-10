extends RefCounted
## Tournoi à élimination directe (8 combattants, 3 tours) contre l'IA.
## Les combats sans le joueur sont résolus de façon déterministe (graine).

const Build := preload("res://scripts/build.gd")

const ROUND_NAMES := ["QUART DE FINALE", "DEMI-FINALE", "FINALE"]
const RIVALS := [
	{"name": "KENJI", "tag": "Jambes & pression", "tokui": "o_soto_gari", "style": "haute", "garde": "gaucher"},
	{"name": "AYA", "tag": "Sol & contres", "tokui": "ko_uchi_gari", "style": "courte", "garde": "droitier"},
	{"name": "MARCO", "tag": "Puissance", "tokui": "o_soto_gari", "style": "classique", "garde": "droitier"},
	{"name": "LÉA", "tag": "Contre-attaque", "tokui": "seoi_nage", "style": "classique", "garde": "gaucher"},
	{"name": "YUKI", "tag": "Vitesse", "tokui": "de_ashi_barai", "style": "courte", "garde": "droitier"},
	{"name": "SAMIR", "tag": "Garde haute", "tokui": "o_uchi_gari", "style": "haute", "garde": "droitier"},
	{"name": "TOM", "tag": "Débutant motivé", "tokui": "o_uchi_gari", "style": "classique", "garde": "droitier"},
]


static func create(human_build: Dictionary, seed_value: int) -> Dictionary:
	var players = [{"name": human_build.name, "tag": human_build.tag, "tokui": human_build.slots.tokui[0],
		"style": human_build.style, "garde": human_build.garde, "human": true, "power": 0}]
	var power = [3, 2, 2, 3, 1, 2, 1]  # force relative des rivaux
	for k in RIVALS.size():
		var r: Dictionary = RIVALS[k].duplicate()
		r.human = false
		r.power = power[k]
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
