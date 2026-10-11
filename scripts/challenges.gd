extends RefCounted
## Défis : liste (data/challenges.json), progression (user://challenges.json),
## suivi des événements pendant le combat et vérification de l'objectif.

const GameData := preload("res://scripts/game_data.gd")
const PATH := "user://challenges.json"
static var _list: Array = []
static var _done: Dictionary = {}
static var _loaded := false


static func all() -> Array:
	if _list.is_empty():
		_list = GameData._to_ints(GameData.load_json("res://data/challenges.json").challenges)
	return _list


static func by_id(id: String) -> Dictionary:
	for c in all():
		if c.id == id:
			return c
	return {}


static func done() -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(PATH):
			var parsed = JSON.parse_string(FileAccess.open(PATH, FileAccess.READ).get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_done = parsed
	return _done


static func is_done(id: String) -> bool:
	return done().has(id)


static func complete(id: String) -> void:
	var d := done()
	d[id] = true
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


static func count_done() -> int:
	var n := 0
	for c in all():
		if is_done(c.id):
			n += 1
	return n


## Suivi d'un combat (joueur = judoka 0).
static func new_tracker() -> Dictionary:
	return {"scores": [], "feint_t": -9999, "reaction_t": -9999, "combo_t": -9999, "strips": 0, "shidos": 0, "toketa": 0}


static func track(tr: Dictionary, sim, e: Dictionary) -> void:
	var t: int = sim.state.tick
	var who: int = e.get("who", -1)
	match e.type:
		"feint":
			if who == 0:
				tr.feint_t = t
		"reaction":
			if who == 0:
				tr.reaction_t = t
		"attack":
			if who == 0 and e.get("combo", false):
				tr.combo_t = t
		"break":
			if who == 0:
				tr.strips += 1
		"shido":
			if who == 0:
				tr.shidos += 1
		"toketa":
			if who == 0:
				tr.toketa += 1
		"score":
			if who == 0:
				var sc := {"result": e.result, "src": e.src, "tech": e.tech, "golden": e.golden,
					"after_feint": t - int(tr.feint_t) <= 150, "after_reaction": t - int(tr.reaction_t) <= 150,
					"combo": t - int(tr.combo_t) <= 120, "counter": sim.techs._counters.has(e.tech),
					"sweep": sim.techs.has(e.tech) and sim.is_sweep(e.tech), "tokui": e.tech == sim.state.fighters[0].tokui}
				tr.scores.append(sc)


## L'objectif est-il rempli ? (state : état final du combat)
static func check(ch: Dictionary, tr: Dictionary, state: Dictionary) -> bool:
	var won: bool = state.winner == 0
	if ch.get("win", false) and not won:
		return false
	var reason: String = String(state.win_reason)
	match String(ch.cond):
		"ippon_throw":
			return _any(tr, func(s): return s.src == "throw" and s.result == "ippon")
		"ippon":
			return won and reason.begins_with("Ippon")
		"tokui":
			return _any(tr, func(s): return s.tokui and s.src == "throw")
		"combo":
			return _any(tr, func(s): return s.combo and s.src == "throw")
		"sweep":
			return _any(tr, func(s): return s.sweep)
		"feint":
			return _any(tr, func(s): return s.after_feint and s.src == "throw")
		"reaction":
			return _any(tr, func(s): return s.after_reaction and s.src == "throw")
		"counter":
			return _any(tr, func(s): return s.counter)
		"osae":
			return _any(tr, func(s): return s.src == "osae")
		"sub":
			return _any(tr, func(s): return s.src == "sub")
		"toketa":
			return int(tr.toketa) > 0
		"strips6":
			return int(tr.strips) >= 6
		"no_shido":
			return int(tr.shidos) == 0
		"fast45":
			return state.tick <= 45 * 60 + 120
		"golden":
			return state.golden
	return false


static func _any(tr: Dictionary, f: Callable) -> bool:
	for s in tr.scores:
		if f.call(s):
			return true
	return false
