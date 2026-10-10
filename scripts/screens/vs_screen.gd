extends Node2D
## Présentation d'avant-combat façon jeu de combat : les deux judokas, leurs builds,
## l'enjeu (tour du tournoi), puis enchaînement automatique sur le combat.

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const Build := preload("res://scripts/build.gd")

const DURATION := 170

var app
var frame = 0
var params: Dictionary
var names: Array
var builds: Array
var subtitle = ""


func on_enter(p: Dictionary) -> void:
	params = p
	names = p.get("names", ["HUGO", "KENJI"])
	builds = p.get("builds", [])
	if builds.size() < 2:
		var d: Array = Build.defaults()
		builds = [d[0], d[1]]
	subtitle = p.get("round_name", "VERSUS" if p.get("mode", "") == "versus" else "COMBAT")


func tick() -> void:
	frame += 1
	if frame >= DURATION and app != null and not app.capture_mode:
		app.goto("match", params)
	queue_redraw()


func nav(action: String, _player: int = 0) -> void:
	if action in ["accept", "start"] and frame > 20:
		app.goto("match", params)
	elif action == "back":
		app.goto("menu", {})


func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Style.INK)
	var t_in = _ease(frame / 22.0)
	# deux moitiés qui glissent depuis les bords, séparées par une diagonale
	var slide = (1.0 - t_in) * 700.0
	var lp = PackedVector2Array([Vector2(-slide, 0), Vector2(720 - slide, 0), Vector2(560 - slide, 720), Vector2(-slide, 720)])
	var rp = PackedVector2Array([Vector2(720 + slide, 0), Vector2(1280 + slide, 0), Vector2(1280 + slide, 720), Vector2(560 + slide, 720)])
	draw_colored_polygon(lp, Style.P1.darkened(0.55))
	draw_colored_polygon(rp, Style.P2.darkened(0.6))
	Style.speed_lines(self, Vector2(300 - slide, 380), 80, 700, 40, Color(Style.P1, 0.18), 3)
	Style.speed_lines(self, Vector2(980 + slide, 380), 80, 700, 40, Color(Style.P2, 0.18), 5)
	Style.halftone(self, Rect2(0, 0, 640, 720), Color(Style.INK, 0.35), 14.0, 4.5, Vector2(1, 0))
	Style.halftone(self, Rect2(640, 0, 640, 720), Color(Style.INK, 0.35), 14.0, 4.5, Vector2(-1, 0))
	# judokas en grand, cadrés à mi-corps
	for i in 2:
		var fc = 1 if i == 0 else -1
		var x = (360.0 - slide) if i == 0 else (920.0 + slide)
		var sc = 4.9
		var bob = sin(frame * 0.07 + i * 1.7) * 3.0
		var xf = Art.stand_xform(Vector2(x, 850 + bob), fc, 0.0, sc, 0.25)
		var pal = Art.palette(i)
		Art.draw_arm(self, xf * Art.SHOULDER_BACK, xf * Art.REST_HANDS[0], pal, true, sc)
		Art.draw_body(self, xf, pal, 0.4)
		Art.draw_arm(self, xf * Art.SHOULDER_FRONT, xf * Art.REST_HANDS[1], pal, false, sc)
	# séparation diagonale
	draw_line(Vector2(720, 0), Vector2(560, 720), Style.INK, 18.0)
	draw_line(Vector2(720, 0), Vector2(560, 720), Style.HOT, 6.0)
	# cartes de nom
	var t_card = _ease((frame - 14) / 18.0)
	for i in 2:
		var b: Dictionary = builds[i]
		var col = Style.P1 if i == 0 else Style.P2
		var w = 470.0
		var x0 = 30.0 - (1.0 - t_card) * 520.0 if i == 0 else 1250.0 - w + (1.0 - t_card) * 520.0
		var r = Rect2(x0, 520, w, 150)
		Style.panel(self, r, Style.INK, col, 4.0, 8.0, Style.SLANT, i == 1)
		Style.text(self, Vector2(r.position.x + 40, r.position.y + 70), names[i], 64, col, "display")
		Style.label(self, Vector2(r.position.x + 44, r.position.y + 96), String(b.get("tag", "")).to_upper(), 15, Style.MUTED, "black")
		var tok: String = Build.entry("technique", b.slots.tokui[0]).get("name", "—")
		var sty: String = Build.catalog().styles[b.style].name
		var chips = ["TOKUI " + tok.to_upper(), sty.to_upper(), String(b.garde).to_upper()]
		var cx = r.position.x + 44
		for c in chips:
			var cw = Style.text_width(c, 13, "black") + 24
			var cr = Rect2(cx, r.position.y + 110, cw, 26)
			Style.chip(self, cr, Style.NIGHT_2, col)
			Style.label(self, Vector2(cr.position.x, cr.position.y + 18), c, 13, col, "black", HORIZONTAL_ALIGNMENT_CENTER, cw)
			cx += cw + 8
	# VS central qui claque
	var t_vs = clampf((frame - 26) / 10.0, 0.0, 1.0)
	if t_vs > 0.0:
		var s = 1.0 + (1.0 - _ease(t_vs)) * 1.6
		var c = Vector2(640, 330)
		Style.burst(self, c, 80 * s, 130 * s, 12, Style.HOT, Style.INK, 9, frame * 0.004)
		Style.text(self, Vector2(c.x - 200, c.y + 44 * s), "VS", int(120 * s), Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, 400, int(10 * s), 8.0)
	# bandeau d'enjeu
	var t_top = _ease((frame - 8) / 16.0)
	var br = Rect2(640 - 260, 30 - (1.0 - t_top) * 120, 520, 64)
	Style.panel(self, br, Style.GOLD, Style.INK, 4.0, 8.0)
	Style.text(self, Vector2(br.position.x, br.position.y + 48), subtitle, 40, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 1, -1.0)
	# barre de chargement façon jeu de combat
	var prog = clampf(float(frame) / float(DURATION), 0.0, 1.0)
	draw_rect(Rect2(0, 714, 1280 * prog, 6), Style.HOT)
