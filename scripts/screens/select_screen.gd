extends Node2D
## Sélection des judokas, façon jeu de combat : grille de portraits (tes judokas puis
## les légendes), ton judoka en grand à gauche, l'adversaire à droite, fiche et stats.
## Une manette : tu choisis ton judoka puis celui de l'IA (et son niveau).
## Deux manettes : chacun choisit le sien. Mode « tournament » : un seul choix.

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const Build := preload("res://scripts/build.gd")

const COLS := 7
const CELL := Vector2(86, 60)
const GRID_Y := 560.0

var app
var frame = 0
var roster: Array = []
var cursor = [0, 1]
var is_ready = [false, false]
var p2_ai = true
var ai_level = 2
var mode = "versus"   # "versus" ou "tournament"
var stage = 0         # une seule manette : 0 = le joueur choisit, 1 = choix de l'IA
var anim = [0.0, 0.0] # glissement du grand personnage à chaque changement


func on_enter(params: Dictionary) -> void:
	roster = Build.roster()
	roster.append({"id": "random", "name": "?", "random": true})
	mode = params.get("mode", "versus")
	p2_ai = Input.get_connected_joypads().size() < 2 or app.capture_mode or mode == "tournament"
	cursor[1] = mini(roster.size() - 2, Build.load_all().size())  # première légende
	if app.capture_mode and app.args.has("cursor"):
		cursor[0] = int(app.args.cursor)


func tick() -> void:
	frame += 1
	for i in 2:
		anim[i] = minf(1.0, anim[i] + 0.12)
	queue_redraw()


func _active_player(player: int) -> int:
	if mode == "tournament":
		return 0
	if p2_ai:
		return stage
	return player


func nav(action: String, player: int = 0) -> void:
	var p = _active_player(player)
	var n = roster.size()
	match action:
		"left", "right", "up", "down":
			if is_ready[p]:
				return
			var c: int = cursor[p]
			var col = c % COLS
			var row = c / COLS
			match action:
				"left":
					c = c - 1 if col > 0 else mini(n - 1, row * COLS + COLS - 1)
				"right":
					c = c + 1 if c + 1 < n and col < COLS - 1 else row * COLS
				"up":
					c = c - COLS if c - COLS >= 0 else c
				"down":
					c = mini(n - 1, c + COLS)
			cursor[p] = c
			anim[p] = 0.0
		"prev":
			if p2_ai:
				ai_level = maxi(1, ai_level - 1)
		"next":
			if p2_ai:
				ai_level = mini(3, ai_level + 1)
		"accept":
			if is_ready[p]:
				return
			if roster[cursor[p]].get("random", false):
				cursor[p] = (frame * 7 + p * 3) % (roster.size() - 1)
			is_ready[p] = true
			if mode == "tournament":
				app.goto("tournament", {"new": true, "build": roster[cursor[0]]})
				return
			if p2_ai and stage == 0:
				stage = 1
			if is_ready[0] and is_ready[1]:
				_start()
		"back":
			if is_ready[p]:
				is_ready[p] = false
			elif p2_ai and stage == 1:
				stage = 0
				is_ready[0] = false
			else:
				app.goto("menu", {})
	queue_redraw()


func _start() -> void:
	var b0: Dictionary = roster[cursor[0]]
	var b1: Dictionary = roster[cursor[1]]
	var n1: String = b1.name if b1.name != b0.name else b1.name + " 2"
	app.goto("vs", {"controllers": [app.human_controller(), "ai" if p2_ai else "pad1"],
		"names": [b0.name, n1], "tokui": [b0.slots.tokui[0], b1.slots.tokui[0]], "builds": [b0, b1],
		"seed": int(app.args.get("seed", str(frame))), "level": ai_level, "mode": "versus"})


# =============================================================================

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Style.NIGHT)
	var left = PackedVector2Array([Vector2(0, 0), Vector2(700, 0), Vector2(580, 540), Vector2(0, 540)])
	var right = PackedVector2Array([Vector2(700, 0), Vector2(1280, 0), Vector2(1280, 540), Vector2(580, 540)])
	draw_colored_polygon(left, Style.P1.darkened(0.72))
	draw_colored_polygon(right, Style.P2.darkened(0.74))
	Style.halftone(self, Rect2(0, 0, 640, 540), Color(Style.P1, 0.10), 16.0, 5.0, Vector2(1, 0))
	Style.halftone(self, Rect2(640, 0, 640, 540), Color(Style.P2, 0.10), 16.0, 5.0, Vector2(-1, 0))
	draw_line(Vector2(700, 0), Vector2(580, 540), Style.INK, 14.0)
	draw_line(Vector2(700, 0), Vector2(580, 540), Style.HOT, 5.0)
	_draw_side(0)
	if mode != "tournament":
		_draw_side(1)
	else:
		_draw_tournament_info()
	draw_rect(Rect2(0, 530, 1280, 190), Color(Style.INK, 0.92))
	draw_line(Vector2(0, 530), Vector2(1280, 530), Style.HOT, 4.0)
	_draw_grid()
	var title = "TOURNOI" if mode == "tournament" else "VERSUS"
	var sub = "Choisis ton judoka" if mode == "tournament" else ("Choisis ton judoka" if stage == 0 or not p2_ai else "Choisis ton adversaire")
	Style.header(self, title, sub, Style.GOLD if mode == "tournament" else Style.HOT)
	var hints = [["←→↑↓", "Choisir"], ["A", "Valider"], ["B", "Retour"]]
	if p2_ai and mode != "tournament":
		hints.insert(1, ["LB", "RB", "Niveau IA"])
	Style.hints(self, hints)


func _draw_side(i: int) -> void:
	var b: Dictionary = roster[cursor[i]]
	var col = Style.P1 if i == 0 else Style.P2
	var flip = i == 1
	var slide = (1.0 - (1.0 - pow(1.0 - anim[i], 3.0))) * 60.0 * (-1.0 if i == 0 else 1.0)
	# grand personnage, cadré à mi-corps
	if not b.get("random", false):
		var feet = Vector2((215.0 if i == 0 else 1065.0) + slide, 640)
		var sc = 3.4
		var xf = Art.stand_xform(feet, 1 if i == 0 else -1, 0.0, sc, 0.3)
		var pal = Art.palette(i, b.get("look", {}))
		Art.draw_arm(self, xf * Art.SHOULDER_BACK, xf * Art.REST_HANDS[0], pal, true, sc)
		Art.draw_body(self, xf, pal, 0.4)
		Art.draw_arm(self, xf * Art.SHOULDER_FRONT, xf * Art.REST_HANDS[1], pal, false, sc)
	else:
		Style.text(self, Vector2(0 if i == 0 else 640, 380), "?", 220, col, "display", HORIZONTAL_ALIGNMENT_CENTER, 640)
	# fiche
	var r = Rect2(330 if i == 0 else 690, 140, 270, 370) if i == 0 else Rect2(690, 140, 270, 370)
	r = Rect2(372, 128, 250, 392) if i == 0 else Rect2(658, 128, 250, 392)
	Style.panel(self, r, Color(Style.INK, 0.9), col, 3.0, 6.0, 0.06, flip)
	var x = r.position.x + 22
	var who = "JOUEUR %d" % (i + 1)
	if i == 1 and p2_ai:
		who = "IA · NIVEAU %d" % ai_level
	Style.label(self, Vector2(x, r.position.y + 28), who, 13, col, "black")
	if b.get("random", false):
		Style.text(self, Vector2(x, r.position.y + 76), "ALÉATOIRE", 34, Style.PAPER, "display")
		return
	var nm: String = b.name
	var fs = 44 if nm.length() <= 7 else 34
	Style.text(self, Vector2(x, r.position.y + 74), nm, fs, Style.PAPER, "display")
	var nick: String = b.get("nick", "")
	var y = r.position.y + 100
	if nick != "":
		Style.label(self, Vector2(x, y), "« %s »" % nick, 16, col, "black")
		y += 22
	Style.label(self, Vector2(x, y), String(b.get("tag", "")).to_upper(), 12, Style.MUTED, "black")
	y += 26
	var tok: String = Build.entry("technique", b.slots.tokui[0]).get("name", "—")
	var lines = [["TOKUI", tok], ["STYLE", Build.catalog().styles[b.style].name], ["GARDE", String(b.garde).capitalize()]]
	for l in lines:
		Style.label(self, Vector2(x, y), l[0], 11, Style.MUTED, "black")
		Style.label(self, Vector2(x + 64, y), String(l[1]).to_upper(), 14, Style.PAPER, "black")
		y += 22
	y += 6
	var stats = [["EXPLOSIVITÉ", "explosivite"], ["ENDURANCE", "endurance"], ["POIGNE", "poigne"], ["SOL", "sol"]]
	for st in stats:
		var v: int = b.physique[st[1]]
		Style.label(self, Vector2(x, y + 9), st[0], 10, Style.MUTED, "black")
		for k in 10:
			draw_rect(Rect2(x + 92 + k * 12, y, 9, 11), col if k < v else Style.NIGHT_3)
		y += 18
	y += 8
	Style.label(self, Vector2(x, y), "TECHNIQUES", 11, Style.MUTED, "black")
	y += 18
	var techs = []
	for id in b.slots.main:
		if id != "":
			techs.append(Build.entry("technique", id).get("name", id))
	Style.label(self, Vector2(x, y), " · ".join(techs.slice(0, 2)), 12, Style.PAPER, "bold")
	if techs.size() > 2:
		Style.label(self, Vector2(x, y + 16), " · ".join(techs.slice(2, 4)), 12, Style.PAPER, "bold")
	if b.has("inspiration"):
		_wrap_label("Inspiré : " + String(b.inspiration), Vector2(x, r.end.y - 34), r.size.x - 40, 11, Style.MUTED)
	if is_ready[i]:
		var sr = Rect2((120.0 if i == 0 else 970.0), 420, 190, 58)
		draw_set_transform(sr.get_center(), -0.12 if i == 0 else 0.12)
		var lr = Rect2(-sr.size / 2, sr.size)
		Style.panel(self, lr, Style.GOOD, Style.INK, 5.0, 8.0)
		Style.text(self, Vector2(lr.position.x, lr.position.y + 44), "PRÊT !", 42, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, lr.size.x)
		draw_set_transform(Vector2.ZERO)


func _draw_tournament_info() -> void:
	var r = Rect2(700, 150, 540, 300)
	Style.panel(self, r, Color(Style.INK, 0.85), Style.GOLD, 3.0, 6.0, 0.06)
	Style.text(self, Vector2(r.position.x + 30, r.position.y + 62), "TOURNOI", 46, Style.GOLD, "display")
	var pts = ["8 judokas, 3 tours à élimination directe.", "Tes adversaires sont tirés parmi les légendes.", "L'IA devient plus forte à chaque tour."]
	var y = r.position.y + 110
	for p in pts:
		draw_circle(Vector2(r.position.x + 38, y - 6), 5.0, Style.GOLD)
		Style.label(self, Vector2(r.position.x + 54, y), p, 18, Style.PAPER, "bold")
		y += 36


func _wrap_label(s: String, pos: Vector2, width: float, size: int, col: Color) -> void:
	var words = s.split(" ")
	var line = ""
	var y = pos.y
	for w in words:
		var test = (line + " " + w).strip_edges()
		if Style.text_width(test, size, "black") > width and line != "":
			Style.label(self, Vector2(pos.x, y), line, size, col, "black")
			y += size + 4
			line = w
		else:
			line = test
	if line != "":
		Style.label(self, Vector2(pos.x, y), line, size, col, "black")


func _draw_grid() -> void:
	var n = roster.size()
	var rows = (n + COLS - 1) / COLS
	var gw = COLS * (CELL.x + 8)
	var x0 = 640.0 - gw * 0.5
	var y0 = 540.0 + (124.0 - rows * (CELL.y + 4)) * 0.5
	var users = Build.load_all().size()
	for k in n:
		var col = k % COLS
		var row = k / COLS
		var cr = Rect2(x0 + col * (CELL.x + 8) - row * 10, y0 + row * (CELL.y + 4), CELL.x, CELL.y)
		var b: Dictionary = roster[k]
		var legend: bool = b.get("legend", false)
		var bg = Style.NIGHT_3 if legend else Style.NIGHT_2.lightened(0.05)
		Style.panel(self, cr, bg, Style.INK, 3.0, 4.0, 0.15)
		if b.get("random", false):
			Style.text(self, Vector2(cr.position.x, cr.position.y + 48), "?", 44, Style.HOT, "display", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
		else:
			_portrait(cr, b)
			draw_rect(Rect2(cr.position.x + 3, cr.end.y - 15, cr.size.x - 6, 13), Color(Style.INK, 0.85))
			Style.label(self, Vector2(cr.position.x + 3, cr.end.y - 4), String(b.name).substr(0, 10), 10, Style.PAPER, "black", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x - 6)
		if k == users and k > 0:
			Style.label(self, Vector2(cr.position.x, cr.position.y - 6), "LÉGENDES", 10, Style.GOLD, "black")
		for i in 2:
			if mode == "tournament" and i == 1:
				continue
			if cursor[i] == k:
				var c = Style.P1 if i == 0 else Style.P2
				var g = cr.grow(4 + i * 4)
				var pts = Style.slant_points(g, 0.15)
				var closed = pts.duplicate()
				closed.append(pts[0])
				draw_polyline(closed, c, 4.0, true)
				Style.label(self, Vector2(g.position.x + (2 if i == 0 else g.size.x - 26), g.position.y - 4), "%dP" % (i + 1), 13, c, "black")


## Portrait : tête et épaules du judoka dans la case.
func _portrait(cr: Rect2, b: Dictionary) -> void:
	var pal = Art.palette(0, b.get("look", {}))
	var sc = 1.05
	var origin = cr.position + Vector2(cr.size.x * 0.5 - 2 * sc, 2.0 + 113.0 * sc)
	draw_set_transform(origin, 0.0, Vector2(sc, sc))
	# épaules en judogi
	var gi = PackedVector2Array([Vector2(-20, -82), Vector2(20, -84), Vector2(26, -67), Vector2(-26, -67)])
	draw_colored_polygon(gi, pal.gi)
	draw_colored_polygon(PackedVector2Array([Vector2(-3, -86), Vector2(7, -86), Vector2(2, -70)]), pal.skin_shade)
	draw_polyline(PackedVector2Array([Vector2(-3, -86), Vector2(2, -70), Vector2(7, -86)]), pal.gi_deep, 2.0, true)
	Art._draw_head(self, pal, 2.4 / sc, 1.6 / sc)
	draw_set_transform(Vector2.ZERO)
