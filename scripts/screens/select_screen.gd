extends Node2D
## Sélection versus : chaque joueur choisit son build avec sa manette, puis « prêt ».
## Sans deuxième manette, le joueur 2 est une IA dont on règle le niveau.

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const Build := preload("res://scripts/build.gd")

var app
var frame = 0
var builds: Array
var choice = [0, 1]
var is_ready = [false, false]
var p2_ai = true
var ai_level = 2


func on_enter(_params: Dictionary) -> void:
	builds = Build.load_all()
	p2_ai = Input.get_connected_joypads().size() < 2 or app.capture_mode
	if app.capture_mode:
		is_ready[0] = true


func tick() -> void:
	frame += 1
	queue_redraw()


func nav(action: String, player: int = 0) -> void:
	# sans 2e manette, la manette 1 règle aussi le niveau de l'IA (haut/bas)
	var p = player if not p2_ai else 0
	match action:
		"left":
			if not is_ready[p]:
				choice[p] = (choice[p] + builds.size() - 1) % builds.size()
		"right":
			if not is_ready[p]:
				choice[p] = (choice[p] + 1) % builds.size()
		"up":
			if p2_ai:
				ai_level = mini(3, ai_level + 1)
		"down":
			if p2_ai:
				ai_level = maxi(1, ai_level - 1)
		"x":
			if p2_ai:
				choice[1] = (choice[1] + 1) % builds.size()
		"accept":
			is_ready[p] = true
			if p2_ai:
				is_ready[1] = true
			if is_ready[0] and is_ready[1]:
				_start()
		"back":
			if is_ready[p]:
				is_ready[p] = false
			else:
				app.goto("menu", {})
	queue_redraw()


func _start() -> void:
	var b0: Dictionary = builds[choice[0]]
	var b1: Dictionary = builds[choice[1]]
	app.goto("vs", {"controllers": [app.human_controller(), "ai" if p2_ai else "pad1"],
		"names": [b0.name, b1.name if b1.name != b0.name else b1.name + " 2"],
		"tokui": [b0.slots.tokui[0], b1.slots.tokui[0]], "builds": [b0, b1], "seed": int(app.args.get("seed", str(frame))), "level": ai_level, "mode": "versus"})


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Style.NIGHT)
	# deux moitiés en diagonale
	var left = PackedVector2Array([Vector2(0, 0), Vector2(700, 0), Vector2(580, 720), Vector2(0, 720)])
	var right = PackedVector2Array([Vector2(700, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(580, 720)])
	draw_colored_polygon(left, Style.P1.darkened(0.72))
	draw_colored_polygon(right, Style.P2.darkened(0.74))
	Style.halftone(self, Rect2(0, 0, 640, 720), Color(Style.P1, 0.10), 16.0, 5.0, Vector2(1, 0))
	Style.halftone(self, Rect2(640, 0, 640, 720), Color(Style.P2, 0.10), 16.0, 5.0, Vector2(-1, 0))
	draw_line(Vector2(700, 0), Vector2(580, 720), Style.INK, 14.0)
	draw_line(Vector2(700, 0), Vector2(580, 720), Style.HOT, 5.0)
	for i in 2:
		_draw_side(i)
	# VS
	Style.burst(self, Vector2(640, 330), 70, 112, 12, Style.HOT, Style.INK, 3, frame * 0.01)
	Style.text(self, Vector2(540, 362), "VS", 96, Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, 200, 8, 6.0)
	Style.header(self, "VERSUS LOCAL", "Choisissez vos builds", Style.HOT)
	Style.hints(self, [["←→", "Build"], ["A", "Prêt"], ["B", "Retour"]] if not p2_ai else [["←→", "Ton build"], ["X", "Build IA"], ["↑↓", "Niveau IA"], ["A", "Combattre"], ["B", "Retour"]])


func _draw_side(i: int) -> void:
	var b: Dictionary = builds[choice[i]]
	var col = Style.P1 if i == 0 else Style.P2
	var flip = i == 1
	var cx = 300.0 if i == 0 else 980.0
	# personnage
	var feet = Vector2(cx + (-30 if i == 0 else 30), 652)
	var sc = 2.95
	var xf = Art.stand_xform(feet, 1 if i == 0 else -1, 0.0, sc, 0.4)
	var pal = Art.palette(i)
	Art.shadow(self, feet + Vector2(0, 2), sc, 0.4)
	Art.draw_arm(self, xf * Art.SHOULDER_BACK, xf * Art.REST_HANDS[0], pal, true, sc)
	Art.draw_body(self, xf, pal, 0.5)
	Art.draw_arm(self, xf * Art.SHOULDER_FRONT, xf * Art.REST_HANDS[1], pal, false, sc)
	# carte du build
	var r = Rect2(cx - 230 if i == 0 else cx - 170, 140, 400, 150)
	Style.panel(self, r, Style.INK, col, 4.0, 8.0, Style.SLANT, flip)
	Style.label(self, Vector2(r.position.x + 40, r.position.y + 30), ("JOUEUR %d" % (i + 1)) if not (i == 1 and p2_ai) else "IA · NIVEAU %d" % ai_level, 14, col, "black")
	Style.text(self, Vector2(r.position.x + 36, r.position.y + 80), b.name, 50, Style.PAPER, "display")
	Style.label(self, Vector2(r.position.x + 40, r.position.y + 104), b.tag.to_upper(), 14, Style.MUTED, "black")
	var tok: String = Build.entry("technique", b.slots.tokui[0]).get("name", "—")
	var sty: String = Build.catalog().styles[b.style].name
	Style.label(self, Vector2(r.position.x + 40, r.position.y + 132), "TOKUI %s · %s · %s" % [tok.to_upper(), sty.to_upper(), b.garde.to_upper()], 13, col, "black")
	# flèches de choix
	if not is_ready[i]:
		for d in [-1, 1]:
			var ac = Vector2(r.get_center().x + d * (r.size.x * 0.5 + 26), r.get_center().y)
			draw_colored_polygon(PackedVector2Array([ac + Vector2(d * 14, 0), ac + Vector2(-d * 8, -14), ac + Vector2(-d * 8, 14)]), col)
	# tampon PRÊT
	if is_ready[i]:
		var sr = Rect2(cx - 110, 470, 220, 72)
		draw_set_transform(sr.get_center(), -0.12 if i == 0 else 0.12)
		var lr = Rect2(-sr.size / 2, sr.size)
		Style.panel(self, lr, Style.GOOD, Style.INK, 5.0, 8.0)
		Style.text(self, Vector2(lr.position.x, lr.position.y + 56), "PRÊT !", 54, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, lr.size.x, 1, -1.0)
		draw_set_transform(Vector2.ZERO)
