extends RefCounted
## Palmarès des judokas (user://records.json) : combats, victoires, ippons,
## séries, techniques qui marquent. Mis à jour à chaque combat joué (hors démo et dojo).

const PATH := "user://records.json"
static var _data: Dictionary = {}
static var _loaded := false


static func all() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		if FileAccess.file_exists(PATH):
			var f := FileAccess.open(PATH, FileAccess.READ)
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


static func of(id: String) -> Dictionary:
	var r: Dictionary = all().get(id, {})
	for k in ["m", "w", "l", "ippon", "waza", "streak", "best"]:
		if not r.has(k):
			r[k] = 0
	if not r.has("techs"):
		r.techs = {}
	return r


## Enregistre un combat terminé. ids : identifiants des deux judokas ; winner : 0, 1 ou -1.
## techs : pour chaque judoka, {technique: nombre de marques}. ippon : judoka ayant gagné par ippon.
static func record(ids: Array, winner: int, techs: Array, wazas: Array, ippon_by: int) -> void:
	var d := all()
	for i in 2:
		var id: String = String(ids[i])
		if id == "":
			continue
		var r := of(id)
		r.m = int(r.m) + 1
		if winner == i:
			r.w = int(r.w) + 1
			r.streak = int(r.streak) + 1
			r.best = maxi(int(r.best), int(r.streak))
		elif winner == 1 - i:
			r.l = int(r.l) + 1
			r.streak = 0
		r.waza = int(r.waza) + int(wazas[i])
		if ippon_by == i:
			r.ippon = int(r.ippon) + 1
		for t in techs[i]:
			r.techs[t] = int(r.techs.get(t, 0)) + int(techs[i][t])
		d[id] = r
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "  "))


## Technique qui a le plus marqué ("" si aucune).
static func favorite(r: Dictionary) -> String:
	var best := ""
	var n := 0
	for t in r.get("techs", {}):
		if int(r.techs[t]) > n:
			n = int(r.techs[t])
			best = t
	return best


static func win_rate(r: Dictionary) -> int:
	return int(r.w) * 100 / maxi(1, int(r.m))
