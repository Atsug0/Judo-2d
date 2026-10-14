extends Node2D
## Options : manette (schéma annoté), audio, affichage, jeu.

const Style := preload("res://scripts/ui/style.gd")
const Settings := preload("res://scripts/settings.gd")

const CATS := ["COMMANDES", "MANETTE", "AUDIO", "AFFICHAGE", "JEU", "COMBAT"]
const Keys := preload("res://scripts/key_reader.gd")
const VISIBLES := 8     # lignes affichées à la fois (la liste des touches est longue)
## [clé, libellé, type, min, max]
const ROWS := {
	"COMMANDES": [["peripherique", "Périphérique", "choice", ["auto", "manette", "clavier"],
		["AUTO (MANETTE SI BRANCHÉE)", "MANETTE", "CLAVIER"]]],
	"MANETTE": [["vibrations", "Vibrations", "bool"], ["vibration_force", "Force des vibrations", "range", 1, 5]],
	"AUDIO": [["volume_master", "Volume général", "range", 0, 10], ["volume_music", "Musique", "range", 0, 10], ["volume_sfx", "Effets sonores", "range", 0, 10]],
	"AFFICHAGE": [["fullscreen", "Plein écran", "bool"], ["vsync", "Synchronisation verticale", "bool"]],
	"JEU": [["ai_level", "Niveau de l'IA par défaut", "range", 1, 3], ["radar", "Radar de kuzushi", "bool"], ["hints", "Aide des commandes en combat", "bool"], ["feed", "Fil des événements", "bool"], ["readout", "Lecture des techniques (A/X/Y)", "bool"]],
	"COMBAT": [["format", "Format", "choice", ["bo3", "single"], ["2 MANCHES GAGNANTES", "UN SEUL COMBAT"]],
		["match_minutes", "Durée d'une manche", "choice", [2, 3, 4, 5], ["2 MIN", "3 MIN", "4 MIN", "5 MIN"]],
		["golden_limit", "Golden score", "choice", [0, 1, 2, 3], ["ILLIMITÉ", "1 MIN + DÉCISION", "2 MIN + DÉCISION", "3 MIN + DÉCISION"]],
		["replay", "Ralenti de la victoire", "bool"]],
}
## Légendes du schéma de manette (mapping du GDD).
const PAD_LABELS := [
	["LT", "Main gauche : saisir / serrer"], ["RT", "Main droite : saisir / serrer"],
	["LB", "Cible main gauche"], ["RB", "Cible main droite"],
	["LS", "Déplacement"], ["RS", "Kuzushi (traction / poussée)"],
	["A", "Technique selon le kuzushi"], ["X", "Technique de jambe"],
	["Y", "Tokui-waza"], ["B", "Casser la prise / contrer"],
	["START", "Pause"],
]

var app
var frame = 0
var scroll = 0
var capture = ""     # action en cours de reconfiguration ("" = aucune)


static func _rows_of(c: String) -> Array:
	if c != "COMMANDES":
		return ROWS[c]
	var out: Array = ROWS["COMMANDES"].duplicate()
	for a in Keys.ACTIONS:
		out.append([a[0], a[1], "touche", a[2]])
	return out
var cat = 0
var row = -1  # -1 = colonne des catégories


func on_enter(_params: Dictionary) -> void:
	pass


func tick() -> void:
	frame += 1
	queue_redraw()


func _input(event: InputEvent) -> void:
	if capture == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if event.keycode != KEY_ESCAPE:
		var t: Dictionary = Settings.value("clavier")
		t[capture] = event.keycode
		Settings.set_value("clavier", t)
		Settings.save()
	capture = ""
	queue_redraw()


func nav(action: String, _player: int = 0) -> void:
	if capture != "":
		if action == "back":        # annuler la reconfiguration en cours
			capture = ""
			queue_redraw()
		return
	var rows: Array = _rows_of(CATS[cat])
	match action:
		"up":
			if row < 0:
				cat = (cat + CATS.size() - 1) % CATS.size()
				scroll = 0
			else:
				row = maxi(0, row - 1)
		"down":
			if row < 0:
				cat = (cat + 1) % CATS.size()
				scroll = 0
			else:
				row = mini(rows.size() - 1, row + 1)
		"right", "accept":
			if row < 0:
				row = 0
			elif rows[row][2] == "touche":
				capture = rows[row][0]     # on attend une frappe (_input)
			else:
				_change(rows[row], 1)
		"left":
			if row < 0:
				pass
			elif rows[row][2] == "touche":
				pass
			elif rows[row][2] in ["range", "choice"]:
				_change(rows[row], -1)
			else:
				row = -1
		"back":
			if row >= 0:
				row = -1
			else:
				Settings.save()
				Settings.apply()
				app.goto("menu", {})
	scroll = clampi(scroll, maxi(0, row - VISIBLES + 1), maxi(0, mini(row, rows.size() - VISIBLES)))
	queue_redraw()


func _change(r: Array, delta: int) -> void:
	var v = Settings.value(r[0])
	if r[2] == "bool":
		Settings.set_value(r[0], not v)
	elif r[2] == "choice":
		var opts: Array = r[3]
		var k = maxi(0, opts.find(v if typeof(v) == TYPE_STRING else int(v)))
		Settings.set_value(r[0], opts[(k + delta + opts.size()) % opts.size()])
	else:
		Settings.set_value(r[0], clampi(int(v) + delta, r[3], r[4]))
		if String(r[0]).begins_with("volume"):
			Sound.apply_volumes()


func _draw() -> void:
	Style.menu_background(self, Vector2(1280, 720), Style.MUTED)
	Style.header(self, "OPTIONS", "Réglages sauvegardés automatiquement", Style.PAPER)
	# catégories
	for k in CATS.size():
		var sel = k == cat
		var r = Rect2(50 + (10 if sel else 0), 170 + k * 70, 260, 56)
		var focus = sel and row < 0
		Style.panel(self, r, Style.PAPER if sel else Style.NIGHT_2, Style.HOT if focus else Style.INK, 4.0, 6.0)
		Style.text(self, Vector2(r.position.x, r.position.y + 41), CATS[k], 30, Style.INK if sel else Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 1 if sel else 3, -1.0 if sel else 0.0)
	# lignes de réglages
	var rows: Array = _rows_of(CATS[cat])
	var y = 170.0
	for k in range(scroll, mini(rows.size(), scroll + VISIBLES)):
		var rr: Array = rows[k]
		var sel = k == row
		var r = Rect2(350 + (10 if sel else 0), y, 480, 46 if CATS[cat] == "COMMANDES" else 56)
		Style.panel(self, r, Style.NIGHT_3 if sel else Style.NIGHT_2, Style.HOT if sel else Style.INK, 4.0, 5.0, 0.12)
		var lw = r.size.x - 28 - (270.0 if rr[2] in ["choice", "touche"] else 150.0)
		Style.label(self, Vector2(r.position.x + 28, r.position.y + 35), rr[1].to_upper(), 18, Style.PAPER, "black", HORIZONTAL_ALIGNMENT_LEFT, lw)
		if rr[2] == "touche":
			var kr = Rect2(r.end.x - 250, r.position.y + 8, 220, r.size.y - 16)
			Style.panel(self, kr, Style.HOT if capture == rr[0] else Style.NIGHT, Style.INK, 3.0, 0.0)
			var lab := "APPUIE…" if capture == rr[0] else "%s   (%s)" % [Keys.nom_action(rr[0]), rr[3]]
			Style.label(self, Vector2(kr.position.x, kr.position.y + kr.size.y * 0.5 + 6), lab, 15,
				Style.INK if capture == rr[0] else (Style.HOT if sel else Style.PAPER), "black",
				HORIZONTAL_ALIGNMENT_CENTER, kr.size.x)
			y += r.size.y + 8
			continue
		var v = Settings.value(rr[0])
		if rr[2] == "bool":
			var cr = Rect2(r.end.x - 130, r.position.y + 12, 100, 32)
			Style.panel(self, cr, Style.GOOD if v else Style.NIGHT, Style.INK, 3.0, 0.0)
			Style.label(self, Vector2(cr.position.x, cr.position.y + 23), "OUI" if v else "NON", 17, Style.INK if v else Style.MUTED, "black", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
		elif rr[2] == "choice":
			var opts: Array = rr[3]
			var lab: String = rr[4][maxi(0, opts.find(v if typeof(v) == TYPE_STRING else int(v)))]
			var cr2 = Rect2(r.end.x - 250, r.position.y + 12, 220, 32)
			Style.panel(self, cr2, Style.NIGHT, Style.INK, 3.0, 0.0)
			Style.label(self, Vector2(cr2.position.x, cr2.position.y + 23), "‹ %s ›" % lab if sel else lab, 16, Style.HOT if sel else Style.PAPER, "black", HORIZONTAL_ALIGNMENT_CENTER, cr2.size.x)
		else:
			var n: int = rr[4]
			var seg_w = minf(22.0, 210.0 / n)
			for s in range(1, n + 1):
				var sr = Rect2(r.end.x - 40 - (n - s + 1) * (seg_w + 4), r.position.y + 14, seg_w, 28)
				Style.panel(self, sr, Style.HOT if s <= int(v) else Style.NIGHT, Style.INK, 2.0, 0.0, 0.25)
		y += 66
	if rows.size() > VISIBLES:
		Style.label(self, Vector2(350, 690), "%d–%d / %d" % [scroll + 1,
			mini(rows.size(), scroll + VISIBLES), rows.size()], 14, Style.MUTED, "bold")
	if CATS[cat] == "MANETTE":
		_draw_pad_diagram(Vector2(590, 500))
	elif CATS[cat] == "AUDIO":
		Style.label(self, Vector2(350, y + 30), "Sons et musiques arrivent avec la phase d'habillage (phase 9).", 16, Style.MUTED, "bold")
	_draw_side_note()
	Style.hints(self, [["↑↓", "Choisir"], ["←→", "Modifier"], ["B", "Retour"]])


func _draw_side_note() -> void:
	if CATS[cat] == "MANETTE":
		return
	if CATS[cat] == "COMMANDES" and row >= 0:
		return     # la liste des touches occupe la largeur
	var r = Rect2(910, 170, 330, 300)
	Style.panel(self, r, Style.INK, Style.MUTED, 3.0, 6.0, 0.06)
	var notes = {
		"COMMANDES": "Le jeu se joue à la manette ou entièrement au clavier. Choisis une ligne et valide pour réassigner une touche (Échap annule). Les aides en combat et les leçons du dojo affichent automatiquement tes touches.",
		"AUDIO": "Le volume général s'applique à tout ; musique et effets se règlent séparément.",
		"AFFICHAGE": "Résolution de référence 1280×720, mise à l'échelle nette jusqu'en 4K.",
		"JEU": "Le radar et le fil d'événements aident à comprendre le kuzushi. Les experts peuvent les masquer.",
		"COMBAT": "Deux manches gagnantes, comme dans un jeu de combat. En compétition réelle : un seul combat de 4 minutes, golden score illimité. Avec une limite, une décision départage : moins de shidos, puis plus d'attaques.",
	}
	Style.text(self, Vector2(r.position.x + 26, r.position.y + 50), "À SAVOIR", 30, Style.PAPER, "display")
	var words: PackedStringArray = notes.get(CATS[cat], "").split(" ")
	var line = ""
	var ly = r.position.y + 90
	for w in words:
		var test = (line + " " + w).strip_edges()
		if Style.font("bold").get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x > r.size.x - 60:
			Style.label(self, Vector2(r.position.x + 28, ly), line, 17, Style.MUTED, "bold")
			ly += 26
			line = w
		else:
			line = test
	Style.label(self, Vector2(r.position.x + 28, ly), line, 17, Style.MUTED, "bold")


## Schéma de manette stylisé, avec légendes du mapping de combat.
func _draw_pad_diagram(c: Vector2) -> void:
	var body = PackedVector2Array()
	# silhouette de manette (deux poignées)
	var pts = [Vector2(-150, -60), Vector2(-60, -72), Vector2(60, -72), Vector2(150, -60), Vector2(185, 10),
		Vector2(200, 80), Vector2(170, 105), Vector2(120, 80), Vector2(80, 40), Vector2(-80, 40), Vector2(-120, 80),
		Vector2(-170, 105), Vector2(-200, 80), Vector2(-185, 10)]
	for p in pts:
		body.append(c + p * 0.9)
	var sh = PackedVector2Array()
	for p in body:
		sh.append(p + Vector2(6, 6))
	draw_colored_polygon(sh, Style.INK)
	draw_colored_polygon(body, Style.NIGHT_3)
	var closed = body.duplicate()
	closed.append(body[0])
	draw_polyline(closed, Style.INK, 5.0, true)
	# gâchettes / bumpers
	for side in [-1, 1]:
		draw_rect(Rect2(c + Vector2(side * 118 - 32, -86), Vector2(64, 14)), Style.INK)
		draw_rect(Rect2(c + Vector2(side * 118 - 30, -84), Vector2(60, 10)), Style.MUTED)
	# sticks
	for p in [Vector2(-110, -18), Vector2(52, 22)]:
		draw_circle(c + p * 0.9, 24, Style.INK)
		draw_circle(c + p * 0.9, 20, Style.NIGHT)
		draw_circle(c + p * 0.9, 12, Style.NIGHT_2)
	# boutons
	var bc = c + Vector2(110, -22) * 0.9
	Style.pad_button(self, bc + Vector2(0, 22), "A", 11.0)
	Style.pad_button(self, bc + Vector2(22, 0), "B", 11.0)
	Style.pad_button(self, bc + Vector2(-22, 0), "X", 11.0)
	Style.pad_button(self, bc + Vector2(0, -22), "Y", 11.0)
	# croix directionnelle
	var dc = c + Vector2(-52, 22) * 0.9
	draw_rect(Rect2(dc - Vector2(20, 7), Vector2(40, 14)), Style.INK)
	draw_rect(Rect2(dc - Vector2(7, 20), Vector2(14, 40)), Style.INK)
	# légendes (colonne de droite)
	for k in PAD_LABELS.size():
		var lab: Array = PAD_LABELS[k]
		var ly = 186.0 + k * 41.0
		Style.pad_button(self, Vector2(902, ly), lab[0], 12.0)
		Style.label(self, Vector2(934, ly + 6), lab[1], 16, Style.PAPER, "bold")
