extends Node2D
## Résultats d'un combat : vainqueur, méthode, statistiques des deux judokas.

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const GameData := preload("res://scripts/game_data.gd")
const Sim := preload("res://scripts/sim/match_sim.gd")
const Ai := preload("res://scripts/sim/ai_controller.gd")
const Tournament := preload("res://scripts/tournament.gd")

var app
var frame = 0
var state: Dictionary
var names: Array
var stats: Array
var match_params: Dictionary
var mode = "demo"
var index = 0
var items: Array = []


func on_enter(params: Dictionary) -> void:
	if params.is_empty():
		params = _demo()
	state = params.state
	names = params.names
	stats = params.stats
	match_params = params.get("match_params", {})
	mode = match_params.get("mode", "demo")
	if mode == "tournament" and not app.session.get("tournament", {}).is_empty():
		Tournament.record(app.session.tournament, state.winner == 0)
		items = ["CONTINUER", "MENU PRINCIPAL"]
	elif mode == "versus":
		items = ["REVANCHE", "CHANGER DE BUILD", "MENU PRINCIPAL"]
	else:
		items = ["REJOUER", "MENU PRINCIPAL"]


## Combat IA contre IA joué instantanément (capture d'écran / démo).
func _demo() -> Dictionary:
	var cfg = GameData.load_json("res://data/config.json")
	var techs = GameData.load_json("res://data/techniques.json")
	var bs = preload("res://scripts/build.gd").defaults()
	var sim = Sim.new(cfg, techs, ["HUGO", "KENJI"], [bs[0], bs[1]])
	var ais = [Ai.new(0, 11, 2), Ai.new(1, 18, 2)]
	var st = []
	for i in 2:
		st.append({"attacks": 0, "throws": 0, "counters": 0, "breaks": 0, "feints": 0, "exposed": 0, "blocks": 0, "shidos": 0, "kuzushi_max": 0, "method": ""})
	while sim.state.phase != "ended" and sim.state.tick < 40000:
		sim.step([ais[0].think(sim), ais[1].think(sim)])
		for i in 2:
			var o: Dictionary = sim.state.fighters[1 - i]
			st[i].kuzushi_max = maxi(st[i].kuzushi_max, maxi(absi(o.bal_x), absi(o.bal_y)))
		for e in sim.events:
			if e.has("who") and e.who >= 0:
				match e.type:
					"attack":
						st[e.who].attacks += 1
					"throw":
						st[e.who].throws += 1
						st[e.who].method = sim.tech_name(e.tech)
					"counter":
						st[e.who].counters += 1
					"break":
						st[e.who].breaks += 1
					"shido":
						st[e.who].shidos += 1
	return {"state": sim.state, "names": ["HUGO", "KENJI"], "stats": st, "match_params": {"mode": "demo"}}


func tick() -> void:
	frame += 1
	queue_redraw()


func nav(action: String, _player: int = 0) -> void:
	match action:
		"up":
			index = (index + items.size() - 1) % items.size()
		"down":
			index = (index + 1) % items.size()
		"accept":
			match items[index]:
				"CONTINUER":
					app.goto("tournament", {})
				"REVANCHE", "REJOUER":
					app.goto("match", match_params if not match_params.is_empty() else app.default_match_params())
				"CHANGER DE BUILD":
					app.goto("select", {})
				_:
					app.goto("menu", {})
	queue_redraw()


func _draw() -> void:
	var w: int = state.winner
	var wcol = Style.P1 if w == 0 else Style.P2
	Style.menu_background(self, Vector2(1280, 720), wcol)
	# bandeau vainqueur
	var spect = mode in ["versus", "demo"]  # deux joueurs ou IA contre IA : on nomme le vainqueur
	var title = "VICTOIRE" if (not spect and w == 0) else ("DÉFAITE" if not spect else "%s GAGNE" % names[w])
	if spect and w >= 0:
		title = "%s GAGNE !" % names[w]
	var tcol = Style.GOLD if title != "DÉFAITE" else Style.DANGER
	Style.speed_lines(self, Vector2(480, 380), 120, 520, 40, Color(wcol, 0.18), 13)
	# judoka vainqueur, poing levé
	var feet = Vector2(480, 655)
	var xf = Art.stand_xform(feet, 1 if w == 0 else -1, 0.0, 3.6, 0.0)
	var mbs = match_params.get("builds", [])
	var pal = Art.palette(w, mbs[w].get("look", {}) if mbs is Array and w >= 0 and mbs.size() > w and mbs[w] is Dictionary else {})
	Art.shadow(self, feet + Vector2(0, 2), 3.6, 0.45)
	Art.draw_arm(self, xf * Art.SHOULDER_BACK, xf * Vector2(-14, -126), pal, true, 3.6)
	Art.draw_body(self, xf, pal, 0.3)
	Art.draw_arm(self, xf * Art.SHOULDER_FRONT, xf * Art.REST_HANDS[1], pal, false, 3.6)
	var tr = Rect2(-20, 40, 680, 120)
	Style.panel(self, tr, tcol, Style.INK, 5.0, 10.0)
	var tsize = mini(104, int(104.0 * 580.0 / maxf(1.0, Style.text_width(title, 104))))
	Style.text(self, Vector2(40, 100 + tsize * 0.35), title, tsize, Style.INK, "display", HORIZONTAL_ALIGNMENT_LEFT, -1, 2, -1.0)
	# méthode
	var reason: String = state.win_reason
	var mr = Rect2(40, 176, Style.text_width(reason.to_upper(), 22, "black") + 50, 40)
	Style.panel(self, mr, Style.INK, wcol, 3.0, 4.0)
	Style.label(self, Vector2(mr.position.x, mr.position.y + 28), reason.to_upper(), 22, wcol, "black", HORIZONTAL_ALIGNMENT_CENTER, mr.size.x)
	_draw_score_table()
	_draw_menu()
	Style.hints(self, [["A", "Valider"]])


func _draw_score_table() -> void:
	var r = Rect2(660, 60, 590, 440)
	Style.panel(self, r, Style.NIGHT_2, Style.INK, 4.0, 10.0, 0.05)
	var fs: Array = state.fighters
	var cx = [r.position.x + 330, r.position.x + 480]
	for i in 2:
		var col = Style.P1 if i == 0 else Style.P2
		var hr = Rect2(cx[i] - 64, r.position.y + 22, 128, 40)
		Style.panel(self, hr, col, Style.INK, 3.0, 4.0)
		Style.text(self, Vector2(hr.position.x, hr.position.y + 31), names[i], 26, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, hr.size.x, 1, -1.0)
	var secs = 240 - int(ceil(state.clock / 60.0)) if not state.golden else 240 + state.clock / 60
	var rows = [
		["WAZA-ARI", fs[0].waza, fs[1].waza],
		["IPPON", fs[0].ippon, fs[1].ippon],
		["SHIDOS", fs[0].shidos, fs[1].shidos],
		["ATTAQUES", stats[0].attacks, stats[1].attacks],
		["PROJECTIONS", stats[0].throws, stats[1].throws],
		["CONTRES", stats[0].counters, stats[1].counters],
		["GARDES CASSÉES", stats[0].breaks, stats[1].breaks],
		["KUZUSHI MAX", "%d %%" % (stats[0].kuzushi_max / 100), "%d %%" % (stats[1].kuzushi_max / 100)],
	]
	var y = r.position.y + 100
	for k in rows.size():
		var row: Array = rows[k]
		if k % 2 == 0:
			draw_rect(Rect2(r.position.x + 20, y - 24, r.size.x - 50, 36), Color(1, 1, 1, 0.04))
		Style.label(self, Vector2(r.position.x + 34, y), row[0], 17, Style.MUTED, "black")
		for i in 2:
			var v = row[i + 1]
			var better: bool = typeof(v) == TYPE_INT and typeof(row[2 - i]) == TYPE_INT and v > row[2 - i] and row[0] != "SHIDOS"
			Style.label(self, Vector2(cx[i] - 60, y), str(v), 22, Style.GOLD if better else Style.PAPER, "black", HORIZONTAL_ALIGNMENT_CENTER, 120)
		y += 38
	Style.label(self, Vector2(r.position.x + 34, r.end.y - 22), "DURÉE : %d:%02d%s" % [secs / 60, secs % 60, " (GOLDEN SCORE)" if state.golden else ""], 15, Style.MUTED, "black")


func _draw_menu() -> void:
	for k in items.size():
		var sel = k == index
		var r = Rect2(700 + (10 if sel else 0), 520 + k * 50, 400, 42)
		Style.panel(self, r, Style.HOT if sel else Style.NIGHT_2, Style.INK, 3.0, 5.0)
		Style.text(self, Vector2(r.position.x, r.position.y + 32), items[k], 26, Style.INK if sel else Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 1 if sel else 3, -1.0 if sel else 0.0)
