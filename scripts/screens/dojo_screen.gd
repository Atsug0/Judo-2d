extends Node2D
## Menu du dojo : catégories de leçons, liste des leçons (avec progression),
## détail de la leçon, et entraînement libre.

const Style := preload("res://scripts/ui/style.gd")
const Lessons := preload("res://scripts/dojo/lessons.gd")
const Progress := preload("res://scripts/dojo/progress.gd")
const Session := preload("res://scripts/dojo/dojo_session.gd")
const Rich := preload("res://scripts/ui/rich.gd")
const Build := preload("res://scripts/build.gd")
const Art := preload("res://scripts/view/fighter_art.gd")

var app
var frame = 0
var cat_i = 0
var lesson_i = 0
var focus = 0  # 0 = catégories, 1 = leçons
var cats: Array = []


func on_enter(p: Dictionary) -> void:
	cats = Lessons.CATEGORIES.duplicate()
	cats.append({"id": "training", "name": "ENTRAÎNEMENT LIBRE", "desc": "Ton build contre un partenaire réglable : immobile, qui résiste, qui suit, qui attaque, IA… Données en direct, affichage des entrées, enregistrement."})
	var want: String = p.get("cat", "base")
	for k in cats.size():
		if cats[k].id == want:
			cat_i = k
	if p.has("cat") and want != "training":
		focus = 1
	if app != null and app.args.has("dojo_focus"):
		focus = int(app.args.dojo_focus)
		lesson_i = int(app.args.get("dojo_lesson", "0"))


func tick() -> void:
	frame += 1
	queue_redraw()


func _lessons() -> Array:
	if cats[cat_i].id == "training":
		return []
	return Lessons.in_category(cats[cat_i].id)


func nav(action: String, _player: int = 0) -> void:
	var list = _lessons()
	match action:
		"up":
			if focus == 0:
				cat_i = (cat_i + cats.size() - 1) % cats.size()
				lesson_i = 0
			elif not list.is_empty():
				lesson_i = (lesson_i + list.size() - 1) % list.size()
		"down":
			if focus == 0:
				cat_i = (cat_i + 1) % cats.size()
				lesson_i = 0
			elif not list.is_empty():
				lesson_i = (lesson_i + 1) % list.size()
		"right":
			if focus == 0 and not list.is_empty():
				focus = 1
		"left":
			focus = 0
		"accept":
			if cats[cat_i].id == "training":
				var bs: Array = Build.load_all()
				var cfg = {"mode": "training", "partner": "garde", "build": bs[0] if not bs.is_empty() else Lessons.player_default()}
				app.goto("match", Session.match_params(cfg, app.human_controller()))
			elif focus == 0:
				focus = 1
			else:
				app.goto("match", Session.match_params({"mode": "lesson", "lesson": list[lesson_i].id}, app.human_controller()))
		"back":
			if focus == 1:
				focus = 0
			else:
				app.goto("menu", {})
	queue_redraw()


func _draw() -> void:
	var size = Vector2(1280, 720)
	Style.menu_background(self, size, Style.GOOD, frame * 0.01)
	Style.header(self, "DOJO", "Apprends le judo du jeu, puis entraîne-toi", Style.GOOD)
	# --- catégories
	for k in cats.size():
		var sel = k == cat_i
		var r = Rect2(30 + (14 if sel else 0), 168 + k * 70, 330, 56)
		var fill = Style.GOOD if sel and focus == 0 else (Style.NIGHT_3 if sel else Style.NIGHT_2)
		Style.panel(self, r, fill, Style.INK, 4.0, 6.0)
		var tcol = Style.INK if sel and focus == 0 else Style.PAPER
		Style.text(self, Vector2(r.position.x + 30, r.position.y + 39), cats[k].name, 26, tcol, "display", HORIZONTAL_ALIGNMENT_LEFT, -1, 3, 0.0)
		if cats[k].id != "training":
			var ls = Lessons.in_category(cats[k].id)
			var ids = ls.map(func(l): return l.id)
			var done = Progress.count_done(ids)
			Style.label(self, Vector2(r.position.x, r.position.y + 35), "%d/%d" % [done, ls.size()], 15,
				Style.INK if sel and focus == 0 else Style.MUTED, "black", HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 26)
	# --- leçons de la catégorie
	var list = _lessons()
	var lx = 400.0
	if cats[cat_i].id == "training":
		_draw_training_panel()
	else:
		var first = clampi(lesson_i - 6, 0, maxi(0, list.size() - 9))
		for k in range(first, mini(list.size(), first + 9)):
			var sel2 = k == lesson_i and focus == 1
			var y = 168 + (k - first) * 50
			var r2 = Rect2(lx + (10 if sel2 else 0), y, 380, 42)
			Style.panel(self, r2, Style.P1 if sel2 else Style.NIGHT_2, Style.INK, 3.0, 4.0)
			var done2 = Progress.is_done(list[k].id)
			Style.label(self, Vector2(r2.position.x + 24, r2.position.y + 28), "%02d" % (k + 1), 15, Style.INK if sel2 else Style.MUTED, "black")
			Style.label(self, Vector2(r2.position.x + 62, r2.position.y + 28), String(list[k].title).to_upper(), 17, Style.INK if sel2 else Style.PAPER, "black")
			if done2:
				var c = Vector2(r2.end.x - 30, r2.position.y + 21)
				draw_circle(c, 11.0, Style.INK)
				draw_circle(c, 9.0, Style.GOOD)
				draw_polyline(PackedVector2Array([c + Vector2(-5, 0), c + Vector2(-1, 4), c + Vector2(5, -4)]), Style.INK, 3.0)
		# --- détail
		if not list.is_empty():
			var l: Dictionary = list[lesson_i]
			var dr = Rect2(810, 168, 440, 446)
			Style.panel(self, dr, Style.NIGHT_2, Style.GOOD, 4.0, 8.0)
			Style.label(self, dr.position + Vector2(34, 36), cats[cat_i].name, 14, Style.GOOD, "black")
			Style.text(self, dr.position + Vector2(30, 82), String(l.title).to_upper(), 34, Style.PAPER, "display")
			var hh = Rich.draw(self, dr.position + Vector2(34, 122), l.intro, 380, 16, Style.PAPER)
			var sy = dr.position.y + 140 + hh
			Style.label(self, Vector2(dr.position.x + 34, sy), "ÉTAPES", 13, Style.MUTED, "black")
			for k in mini(l.steps.size(), 5):
				Style.label(self, Vector2(dr.position.x + 34, sy + 24 + k * 22), "%d · %s" % [k + 1, l.steps[k].title], 15, Style.PAPER, "bold")
	Style.label(self, Vector2(400, 650), cats[cat_i].desc, 15, Style.MUTED, "bold", HORIZONTAL_ALIGNMENT_LEFT, 840)
	Style.hints(self, [["A", "Choisir"], ["B", "Retour"]])


func _draw_training_panel() -> void:
	var r = Rect2(400, 168, 850, 446)
	Style.panel(self, r, Style.NIGHT_2, Style.GOOD, 4.0, 8.0)
	Style.text(self, r.position + Vector2(40, 70), "ENTRAÎNEMENT LIBRE", 44, Style.GOOD, "display")
	var points = [
		"Ton build (le premier de tes builds sauvegardés) contre un partenaire réglable.",
		"Partenaire : immobile, tient sa garde, bataille de mains, se déplace, tire, résiste, suit, attaque, casse tes saisies, IA de niveau 1 à 3.",
		"Données en direct : son déséquilibre dans chaque direction, sa réaction (résiste ou suit), et ce que donnerait {A}, {X} ou {Y} à cet instant.",
		"Affichage des entrées façon jeu de combat, endurance infinie.",
		"Enregistre 10 s de mouvements du partenaire, il les rejoue en boucle.",
		"Pause : réglages. View : replacer les judokas.",
	]
	var y = r.position.y + 112
	for ptxt in points:
		draw_circle(Vector2(r.position.x + 46, y - 6), 5.0, Style.GOOD)
		y += Rich.draw(self, Vector2(r.position.x + 62, y), ptxt, 740, 17, Style.PAPER) + 10
	# deux judokas en garde
	var sc = 2.1
	var xa = Art.stand_xform(Vector2(r.end.x - 230, r.end.y - 18), 1, 0.05, sc, 0.2)
	var xb = Art.stand_xform(Vector2(r.end.x - 130, r.end.y - 18), -1, 0.0, sc, 0.2)
	for pair in [[xa, 0], [xb, 1]]:
		var pal = Art.palette(pair[1])
		Art.draw_arm(self, pair[0] * Art.SHOULDER_BACK, pair[0] * Art.REST_HANDS[0], pal, true, sc)
		Art.draw_body(self, pair[0], pal, 0.3)
		Art.draw_arm(self, pair[0] * Art.SHOULDER_FRONT, pair[0] * Art.REST_HANDS[1], pal, false, sc)
