extends Node2D
## Tableau du tournoi et carte du prochain combat.

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const Build := preload("res://scripts/build.gd")
const Tournament := preload("res://scripts/tournament.gd")

var app
var frame = 0
var t: Dictionary
var anim_round = -1    # tour dont les résultats s'animent
var anim = 1.0
var celebrate = false  # écran du champion


func on_enter(params: Dictionary) -> void:
	if app.session.get("tournament", {}).is_empty() or params.get("new", false):
		app.session.tournament = Tournament.create(params.get("build", Build.load_all()[0]), int(Time.get_unix_time_from_system()) % 100000 if not app.capture_mode else 7)
	t = app.session.tournament
	if app.capture_mode and app.args.has("demo_round"):
		# capture : simule une progression (demi-finale, ou victoire finale avec --demo_round=3)
		for k in int(app.args.demo_round):
			if not t.done:
				Tournament.record(t, true)
	if t.has("fresh"):
		anim_round = int(t.fresh)
		anim = 0.0
		t.erase("fresh")
	celebrate = t.done and t.champion >= 0 and t.players[t.champion].human


func tick() -> void:
	frame += 1
	if anim < 1.0:
		anim = minf(1.0, anim + 1.0 / 50.0)
	queue_redraw()


func nav(action: String, _player: int = 0) -> void:
	match action:
		"accept":
			if celebrate:
				celebrate = false
				return
			if t.done:
				app.session.tournament = {}
				app.goto("menu", {})
				return
			var me: Dictionary = t.players[0]
			for p in t.players:
				if p.human:
					me = p
			var o = Tournament.opponent(t)
			app.goto("vs", {"controllers": [app.human_controller(), "ai"], "names": [me.name, o.name], "round_name": Tournament.ROUND_NAMES[t.round],
				"tokui": [me.tokui, o.tokui], "builds": [me.build, o.build], "seed": t.seed + t.round * 13, "level": Tournament.ai_level(t),
				"mode": "tournament"})
		"back":
			app.goto("menu", {})


func _draw() -> void:
	Style.menu_background(self, Vector2(1280, 720), Style.GOLD)
	Style.header(self, "TOURNOI", "Élimination directe · 8 combattants", Style.GOLD)
	_draw_bracket()
	_draw_next_card()
	if celebrate:
		_draw_champion()
		return
	if t.done:
		Style.hints(self, [["A", "Terminer"], ["B", "Menu"]])
	else:
		Style.hints(self, [["A", "Combattre"], ["B", "Menu"]])


func _slot_rect(round_i: int, k: int) -> Rect2:
	var x0 = 40.0 + round_i * 250.0
	var h = 44.0
	var span = 58.0 * pow(2.0, round_i)
	var y = 176.0 + span * k + (span - 58.0) * 0.5
	return Rect2(x0, y, 210, h)


func _draw_bracket() -> void:
	for r in 3:
		Style.label(self, Vector2(40 + r * 250, 164), Tournament.ROUND_NAMES[r], 14, Style.GOLD if r == t.round and not t.done else Style.MUTED, "black")
	# QF : les 8 combattants
	for r in 3:
		var matches: Array = t.rounds[r]
		for mi in range(matches.size(), 4 >> r):
			for side in 2:
				var er = _slot_rect(r, mi * 2 + side)
				Style.panel(self, er, Style.NIGHT, Style.INK, 3.0, 0.0, 0.18)
				Style.label(self, Vector2(er.position.x + 20, er.position.y + 29), "?", 20, Style.NIGHT_3, "black")
		for mi in matches.size():
			var m: Dictionary = matches[mi]
			for side in 2:
				var pi: int = m.a if side == 0 else m.b
				var rect = _slot_rect(r, mi * 2 + side)
				if r == anim_round + 1 and anim < 1.0:
					# nouveaux qualifiés : ils glissent depuis le tour précédent
					var e2 = clampf(anim * 1.4 - 0.3, 0.0, 1.0)
					if e2 <= 0.0:
						continue
					rect.position.x -= (1.0 - e2 * e2 * (3.0 - 2.0 * e2)) * 120.0
				_draw_player_slot(rect, t.players[pi], m.winner, pi)
			# connecteur vers le tour suivant
			var ra = _slot_rect(r, mi * 2)
			var rb = _slot_rect(r, mi * 2 + 1)
			var xr = ra.end.x + 6
			var xm = xr + 18
			var ya = ra.get_center().y
			var yb = rb.get_center().y
			var col = Style.NIGHT_3
			if m.winner >= 0:
				col = Style.GOLD if t.players[m.winner].human else Style.MUTED
			draw_polyline(PackedVector2Array([Vector2(xr, ya), Vector2(xm, ya), Vector2(xm, yb), Vector2(xr, yb)]), col, 3.0)
			var reach = 16.0
			if r == anim_round and m.winner >= 0:
				# le vainqueur avance : le trait part vers le tour suivant
				reach = 16.0 + 0.0 * anim
				var e = clampf(anim * 1.6, 0.0, 1.0)
				var wy = ya if m.winner == m.a else yb
				draw_line(Vector2(xr, wy), Vector2(xm, wy), Style.PAPER if t.players[m.winner].human else col, 5.0 * (1.0 - e) + 3.0)
			draw_line(Vector2(xm, (ya + yb) * 0.5), Vector2(xm + reach, (ya + yb) * 0.5), col, 3.0)
	# champion
	var cr = Rect2(790, 368, 200, 70)
	var champ = "?"
	if t.champion >= 0:
		champ = t.players[t.champion].name
	Style.panel(self, cr, Style.GOLD if t.champion >= 0 else Style.NIGHT_2, Style.INK, 4.0, 6.0)
	Style.label(self, Vector2(cr.position.x, cr.position.y + 22), "CHAMPION", 13, Style.INK if t.champion >= 0 else Style.MUTED, "black", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	Style.text(self, Vector2(cr.position.x, cr.position.y + 56), champ, 32, Style.INK if t.champion >= 0 else Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 1 if t.champion >= 0 else 3, -1.0 if t.champion >= 0 else 0.0)
	_draw_trophy(Vector2(890, 300), t.champion >= 0)


func _draw_player_slot(r: Rect2, p: Dictionary, winner: int, pi: int) -> void:
	var lost = winner >= 0 and winner != pi
	var fill = Style.NIGHT_2
	var border = Style.INK
	var tcol = Style.PAPER
	if p.human:
		fill = Style.P1 if not lost else Style.P1.darkened(0.6)
		tcol = Style.INK if not lost else Style.MUTED
	elif lost:
		fill = Style.NIGHT
		tcol = Style.MUTED
	Style.panel(self, r, fill, border, 3.0, 4.0 if not lost else 0.0, 0.18)
	Style.label(self, Vector2(r.position.x + 20, r.position.y + 29), p.name, 20, tcol, "black")
	if not lost:
		var nw2 = Style.text_width(p.name, 20, "black")
		var tw = maxf(20.0, r.size.x - 50 - nw2)
		Style.label(self, Vector2(r.end.x - 24 - tw, r.position.y + 28), p.tag.to_upper() if not p.human else "TOI", 11, tcol if p.human else Style.MUTED, "black", HORIZONTAL_ALIGNMENT_RIGHT, tw)
	if lost:
		var nw = Style.text_width(p.name, 20, "black")
		draw_line(Vector2(r.position.x + 14, r.get_center().y - 2), Vector2(r.position.x + 26 + nw, r.get_center().y - 2), Style.DANGER, 2.5)


func _draw_trophy(c: Vector2, lit: bool) -> void:
	var col = Style.GOLD if lit else Style.NIGHT_3
	var cup = PackedVector2Array([c + Vector2(-34, -40), c + Vector2(34, -40), c + Vector2(26, -6), c + Vector2(10, 6), c + Vector2(-10, 6), c + Vector2(-26, -6)])
	var sh = PackedVector2Array()
	for p in cup:
		sh.append(p + Vector2(5, 5))
	draw_colored_polygon(sh, Style.INK)
	draw_colored_polygon(cup, col)
	var closed = cup.duplicate()
	closed.append(cup[0])
	draw_polyline(closed, Style.INK, 4.0, true)
	draw_arc(c + Vector2(-36, -22), 12, PI * 0.5, PI * 1.5, 12, Style.INK, 9.0)
	draw_arc(c + Vector2(-36, -22), 12, PI * 0.5, PI * 1.5, 12, col, 4.0)
	draw_arc(c + Vector2(36, -22), 12, -PI * 0.5, PI * 0.5, 12, Style.INK, 9.0)
	draw_arc(c + Vector2(36, -22), 12, -PI * 0.5, PI * 0.5, 12, col, 4.0)
	draw_rect(Rect2(c + Vector2(-6, 6), Vector2(12, 16)), Style.INK)
	draw_rect(Rect2(c + Vector2(-22, 22), Vector2(44, 12)), Style.INK)
	draw_rect(Rect2(c + Vector2(-19, 24), Vector2(38, 8)), col)
	if lit:
		Style.speed_lines(self, c + Vector2(0, -20), 60, 110, 18, Color(Style.GOLD, 0.6), 4)


func _draw_next_card() -> void:
	var r = Rect2(1010, 164, 240, 470)
	Style.panel(self, r, Style.NIGHT_2, Style.INK, 4.0, 8.0, 0.05)
	if t.done:
		var won: bool = t.champion >= 0 and t.players[t.champion].human
		Style.text(self, Vector2(r.position.x, r.position.y + 120), "CHAMPION !" if won else "ÉLIMINÉ", 38, Style.GOLD if won else Style.DANGER, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		Style.label(self, Vector2(r.position.x + 20, r.position.y + 160), "Le tournoi est terminé." if won else "Retente ta chance !", 16, Style.PAPER, "bold", HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 40)
		return
	var o = Tournament.opponent(t)
	Style.label(self, Vector2(r.position.x + 24, r.position.y + 36), "PROCHAIN COMBAT", 13, Style.MUTED, "black")
	Style.text(self, Vector2(r.position.x + 22, r.position.y + 70), Tournament.ROUND_NAMES[t.round], 24, Style.GOLD, "display")
	# portrait de l'adversaire
	var pr = Rect2(r.position.x + 20, r.position.y + 90, r.size.x - 50, 200)
	draw_rect(pr, Style.INK)
	draw_rect(pr.grow(-4), Style.P2.darkened(0.6))
	Style.halftone(self, pr.grow(-4), Color(Style.P2, 0.3), 12.0, 4.0, Vector2(0, -1))
	var xf = Art.stand_xform(Vector2(pr.get_center().x + 6, pr.end.y + 120), -1, 0.0, 2.6, 0.0)
	var opal = Art.palette(1, o.get("build", {}).get("look", {}))
	Art.draw_arm(self, xf * Art.SHOULDER_BACK, xf * Art.REST_HANDS[0], opal, true, 2.6)
	Art.draw_body(self, xf, opal, 0.3)
	Art.draw_arm(self, xf * Art.SHOULDER_FRONT, xf * Art.REST_HANDS[1], opal, false, 2.6)
	# recouvre ce qui dépasse sous le cadre
	draw_rect(Rect2(pr.position.x - 4, pr.end.y, pr.size.x + 8, 130), Style.NIGHT_2)
	draw_rect(pr, Style.INK, false, 4.0)
	Style.text(self, Vector2(r.position.x + 22, r.position.y + 334), o.name, 40, Style.P2, "display")
	Style.label(self, Vector2(r.position.x + 24, r.position.y + 358), o.tag.to_upper(), 14, Style.MUTED, "black")
	var lines = [["TOKUI", Build.entry("technique", o.tokui).get("name", o.tokui)],
		["STYLE", Build.catalog().styles[o.style].name], ["IA", "NIVEAU %d" % Tournament.ai_level(t)]]
	var y = r.position.y + 392
	for l in lines:
		Style.label(self, Vector2(r.position.x + 24, y), l[0], 13, Style.MUTED, "black")
		Style.label(self, Vector2(r.position.x + 24, y), str(l[1]).to_upper(), 14, Style.PAPER, "black", HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 56)
		y += 24


## Écran du champion : trophée, confettis, judoka poing levé.
func _draw_champion() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.03, 0.1, 0.82))
	Style.speed_lines(self, Vector2(640, 330), 120, 760, 46, Color(Style.GOLD, 0.22), 21)
	# confettis (déterministes, ils tombent en boucle)
	var cols = [Style.GOLD, Style.HOT, Style.P2, Style.GOOD, Style.PAPER]
	for k in 90:
		var sx = float((k * 7919) % 1280)
		var sp = 1.2 + float((k * 31) % 17) / 10.0
		var y = fmod(float(k * 53) + frame * sp, 760.0) - 30.0
		var x = sx + sin(frame * 0.05 + k) * 14.0
		var c: Color = cols[k % cols.size()]
		draw_set_transform(Vector2(x, y), frame * 0.08 + k, Vector2.ONE)
		draw_rect(Rect2(-5, -3, 10, 6), c)
		draw_set_transform(Vector2.ZERO)
	var me: Dictionary = t.players[t.champion]
	var feet = Vector2(420, 640)
	var xf = Art.stand_xform(feet, 1, 0.0, 3.4, 0.0)
	var pal = Art.palette(0, me.get("build", {}).get("look", {}))
	Art.shadow(self, feet + Vector2(0, 2), 3.4, 0.45)
	Art.draw_arm(self, xf * Art.SHOULDER_BACK, xf * Vector2(-12, -126), pal, true, 3.4)
	Art.next_pose = "victoire"
	Art.draw_body(self, xf, pal, 0.3)
	Art.draw_arm(self, xf * Art.SHOULDER_FRONT, xf * Vector2(16, -128), pal, false, 3.4)
	draw_set_transform(Vector2(830, 330), 0.0, Vector2(2.4, 2.4))
	_draw_trophy(Vector2.ZERO, true)
	draw_set_transform(Vector2.ZERO)
	var r = Rect2(640, 470, 520, 100)
	Style.panel(self, r, Style.GOLD, Style.INK, 5.0, 10.0)
	Style.text(self, Vector2(r.position.x, r.position.y + 74), "CHAMPION !", 72, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 2, -1.0)
	Style.label(self, Vector2(r.position.x, r.end.y + 34), "%s REMPORTE LE TOURNOI" % String(me.name).to_upper(), 22, Style.PAPER, "black", HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	Style.hints(self, [["A", "Voir le tableau"]])

