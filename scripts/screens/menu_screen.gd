extends Node2D
## Menu principal.

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")

var app
var frame := 0
var index := 0
var anim := 0.0  # glissement du panneau de droite

const ITEMS := [
	{"id": "tournament", "label": "TOURNOI", "accent": "gold", "desc": "Affronte l'IA dans un tableau à élimination directe. Idéal pour prendre en main la garde, le kuzushi et le timing.",
		"points": ["8 combattants, 3 tours", "IA de plus en plus forte", "Builds typés en face"]},
	{"id": "select", "label": "VERSUS LOCAL", "accent": "hot", "desc": "Deux manettes, un tatami. Chaque joueur choisit son build et c'est hajime.",
		"points": ["2 manettes", "Builds personnalisés", "Revanche immédiate"]},
	{"id": "dojo", "label": "DOJO", "accent": "good", "desc": "Apprends tout le judo du jeu, leçon par leçon, puis entraîne-toi librement contre un partenaire réglable.",
		"points": ["Tutoriel complet", "Guide de chaque technique", "Entraînement libre"]},
	{"id": "online", "label": "EN LIGNE", "accent": "cyan", "desc": "Parties rapides, classées et salons privés, avec un netcode rollback pensé dès le premier jour.",
		"points": ["Netcode rollback", "Matchmaking Steam", "Phase 8 du plan"], "badge": "BIENTÔT"},
	{"id": "customize", "label": "PERSONNALISATION", "accent": "yellow", "desc": "Construis ton judoka : set de techniques à 15 points, garde, style de kumikata et profil physique.",
		"points": ["Budget de 15 points", "Garde et style", "Profil physique"]},
	{"id": "options", "label": "OPTIONS", "accent": "muted", "desc": "Manette, vibrations, audio, affichage et règles.",
		"points": ["Remapping manette", "Vibrations", "Audio et vidéo"]},
	{"id": "quit", "label": "QUITTER", "accent": "danger", "desc": "Retour au bureau. Rei !", "points": []},
]


func on_enter(_params: Dictionary) -> void:
	pass


func tick() -> void:
	frame += 1
	anim = minf(1.0, anim + 0.12)
	queue_redraw()


func nav(action: String, _player: int = 0) -> void:
	match action:
		"up":
			index = (index + ITEMS.size() - 1) % ITEMS.size()
			anim = 0.0
		"down":
			index = (index + 1) % ITEMS.size()
			anim = 0.0
		"back":
			app.goto("title", {})
		"accept":
			var id: String = ITEMS[index].id
			if id == "quit":
				get_tree().quit()
			elif id == "tournament" and app.session.get("tournament", {}).is_empty():
				app.goto("select", {"mode": "tournament"})  # choisir son judoka d'abord
			else:
				app.goto(id, {})
	queue_redraw()


func _accent(name: String) -> Color:
	match name:
		"gold":
			return Style.GOLD
		"cyan":
			return Style.P2
		"yellow":
			return Style.P1
		"muted":
			return Style.MUTED
		"danger":
			return Style.DANGER
		"good":
			return Style.GOOD
	return Style.HOT


func _draw() -> void:
	var it: Dictionary = ITEMS[index]
	var acc := _accent(it.accent)
	Style.menu_background(self, Vector2(1280, 720), acc)
	Style.header(self, "JUDO 2D", "Menu principal", Style.PAPER)
	# profil
	var pr := Rect2(1000, 30, 250, 56)
	Style.panel(self, pr, Style.NIGHT_2, Style.INK, 4.0, 6.0)
	draw_circle(Vector2(1042, 58), 20, Style.INK)
	draw_circle(Vector2(1042, 58), 17, Style.P1)
	Style.label(self, Vector2(1030, 65), "H", 20, Style.INK, "black", HORIZONTAL_ALIGNMENT_CENTER, 24)
	Style.label(self, Vector2(1072, 56), "HUGO", 20, Style.PAPER, "black")
	Style.label(self, Vector2(1072, 76), "SPÉCIALISTE SEOI", 12, Style.MUTED, "black")
	# boutons
	for k in ITEMS.size():
		var sel := k == index
		var y := 160.0 + k * 68.0
		var x := 60.0 - k * 9.0
		var w := 470.0 + (40.0 if sel else 0.0)
		var r := Rect2(x + (16.0 if sel else 0.0), y, w, 56)
		var c := _accent(ITEMS[k].accent)
		Style.panel(self, r, c if sel else Style.NIGHT_2, Style.INK, 4.0, 7.0 if sel else 5.0)
		if not sel:
			draw_colored_polygon(Style.slant_points(Rect2(r.position + Vector2(4, 4), Vector2(14, r.size.y - 8))), c)
		Style.text(self, Vector2(r.position.x + 40, r.position.y + 42), ITEMS[k].label, 36 if sel else 32,
			Style.INK if sel else Style.PAPER, "display", HORIZONTAL_ALIGNMENT_LEFT, -1, 3 if sel else 4, 0.0 if sel else 3.0)
		if ITEMS[k].has("badge"):
			var br := Rect2(r.end.x - 130, r.position.y + 16, 96, 30)
			Style.panel(self, br, Style.INK, c, 2.5, 0.0)
			Style.label(self, Vector2(br.position.x, br.position.y + 22), ITEMS[k].badge, 15, c, "black", HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
		if sel:
			var ax := r.end.x + 14
			draw_colored_polygon(PackedVector2Array([Vector2(ax, y + 11), Vector2(ax + 22, y + 28), Vector2(ax, y + 45)]), Style.INK)
			draw_colored_polygon(PackedVector2Array([Vector2(ax - 4, y + 15), Vector2(ax + 14, y + 28), Vector2(ax - 4, y + 41)]), c)
	# panneau de description
	var slide := (1.0 - anim) * 60.0
	var dr := Rect2(650 + slide, 150, 580, 470)
	Style.panel(self, dr, Style.NIGHT_2, Style.INK, 4.0, 10.0, 0.08)
	# illustration
	var ill := Rect2(dr.position.x + 30, dr.position.y + 24, dr.size.x - 70, 200)
	draw_rect(ill, Style.INK)
	draw_rect(ill.grow(-4), acc.darkened(0.55))
	Style.halftone(self, ill.grow(-4), Color(acc, 0.35), 12.0, 4.0, Vector2(-1, 0))
	Style.speed_lines(self, ill.get_center() + Vector2(0, 20), 40, 115, 30, Color(acc, 0.35), index + 2)
	var xa := Art.stand_xform(Vector2(ill.get_center().x - 50, ill.end.y - 8), 1, 0.15, 1.75, 0.3)
	var xb := Art.stand_xform(Vector2(ill.get_center().x + 46, ill.end.y - 8), -1, -0.1, 1.75, 0.1)
	Art.draw_arm(self, xa * Art.SHOULDER_BACK, xb * Art.GRIP_POINTS["sleeve"], Art.palette(0), true, 1.75)
	Art.draw_body(self, xb, Art.palette(1), 0.8)
	Art.draw_arm(self, xb * Art.SHOULDER_FRONT, xa * Art.GRIP_POINTS["lapel"], Art.palette(1), false, 1.75)
	Art.draw_body(self, xa, Art.palette(0), 0.8)
	Art.draw_arm(self, xa * Art.SHOULDER_FRONT, xb * Art.GRIP_POINTS["lapel"], Art.palette(0), false, 1.75)
	draw_rect(ill, Style.INK, false, 4.0)
	# textes
	Style.text(self, Vector2(dr.position.x + 30, dr.position.y + 274), it.label, 44, acc, "display")
	var desc_end := _wrap(it.desc, Vector2(dr.position.x + 32, dr.position.y + 306), dr.size.x - 70, 18, Style.PAPER)
	var px := dr.position.x + 32
	var py := desc_end + 14.0
	for p in it.points:
		var up: String = p.to_upper()
		var w := Style.text_width(up, 14, "black") + 34
		if px + w > dr.end.x - 30:
			px = dr.position.x + 32
			py += 38
		var cr := Rect2(px, py, w, 30)
		Style.chip(self, cr, Style.INK, acc)
		Style.label(self, Vector2(cr.position.x, cr.position.y + 21), up, 14, acc, "black", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
		px += w + 12
	Style.hints(self, [["A", "Valider"], ["B", "Retour"]])


func _wrap(s: String, pos: Vector2, width: float, size: int, col: Color) -> float:
	var words := s.split(" ")
	var line := ""
	var y := pos.y
	var f := Style.font("bold")
	for w in words:
		var test := (line + " " + w).strip_edges()
		if f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			draw_string(f, Vector2(pos.x, y + size), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			y += size * 1.35
			line = w
		else:
			line = test
	if line != "":
		draw_string(f, Vector2(pos.x, y + size), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return y + size * 1.35
