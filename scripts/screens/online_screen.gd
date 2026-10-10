extends Node2D
## En ligne : maquette du lobby (le réseau arrive en phase 8).
## L'état technique affiché est réel : il reflète ce qui est fait dans le code.

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")

const MODES := [
	{"label": "PARTIE RAPIDE", "desc": "Un adversaire de ton niveau, tout de suite.", "accent": "cyan"},
	{"label": "CLASSÉE", "desc": "Monte les ceintures, du blanc au noir.", "accent": "gold"},
	{"label": "SALON PRIVÉ", "desc": "Crée un code et invite un ami.", "accent": "hot"},
]
const CHECKS := [
	["Simulation déterministe (entiers, tick fixe)", true],
	["Sauvegarde / restauration d'état", true],
	["Rejeu des entrées vérifié (checksums)", true],
	["Netcode rollback (prédiction + correction)", false],
	["Matchmaking et salons Steam", false],
]

var app
var frame = 0
var index = 0


func on_enter(_params: Dictionary) -> void:
	pass


func tick() -> void:
	frame += 1
	queue_redraw()


func nav(action: String, _player: int = 0) -> void:
	match action:
		"up":
			index = (index + MODES.size() - 1) % MODES.size()
		"down":
			index = (index + 1) % MODES.size()
		"back", "accept":
			app.goto("menu", {})
	queue_redraw()


func _accent(n: String) -> Color:
	return Style.P2 if n == "cyan" else (Style.GOLD if n == "gold" else Style.HOT)


func _draw() -> void:
	Style.menu_background(self, Vector2(1280, 720), Style.P2)
	Style.header(self, "EN LIGNE", "Bientôt disponible — phase 8 du plan", Style.P2)
	for k in MODES.size():
		var m: Dictionary = MODES[k]
		var sel = k == index
		var acc = _accent(m.accent)
		var r = Rect2(60 + (14 if sel else 0), 170 + k * 120, 560, 100)
		Style.panel(self, r, Style.NIGHT_3 if sel else Style.NIGHT_2, acc if sel else Style.INK, 4.0, 7.0)
		Style.text(self, Vector2(r.position.x + 36, r.position.y + 50), m.label, 40, acc, "display")
		Style.label(self, Vector2(r.position.x + 38, r.position.y + 80), m.desc, 17, Style.PAPER, "bold")
		var br = Rect2(r.end.x - 150, r.position.y + 14, 116, 30)
		Style.chip(self, br, Style.INK, Style.MUTED)
		Style.label(self, Vector2(br.position.x, br.position.y + 21), "BIENTÔT", 15, Style.MUTED, "black", HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
	# état technique
	var sr = Rect2(680, 170, 560, 320)
	Style.panel(self, sr, Style.INK, Style.P2, 3.0, 8.0, 0.05)
	Style.text(self, Vector2(sr.position.x + 30, sr.position.y + 50), "PRÊT POUR LE ROLLBACK", 32, Style.P2, "display")
	var y = sr.position.y + 96
	for c in CHECKS:
		var ok: bool = c[1]
		var cc = Vector2(sr.position.x + 46, y - 6)
		draw_circle(cc, 13, Style.INK)
		draw_circle(cc, 11, Style.GOOD if ok else Style.NIGHT_3)
		if ok:
			draw_polyline(PackedVector2Array([cc + Vector2(-6, 0), cc + Vector2(-1, 5), cc + Vector2(7, -5)]), Style.INK, 3.0, true)
		Style.label(self, Vector2(sr.position.x + 72, y), c[0], 17, Style.PAPER if ok else Style.MUTED, "bold")
		y += 46
	Style.label(self, Vector2(sr.position.x + 30, sr.end.y - 24), "CONNEXION : HORS LIGNE", 15, Style.MUTED, "black")
	# illustration : deux judokas reliés par un câble
	var xa = Art.stand_xform(Vector2(820, 664), 1, 0.0, 1.35, 0.3)
	var xb = Art.stand_xform(Vector2(1100, 664), -1, 0.0, 1.35, 0.3)
	draw_line(Vector2(850, 590), Vector2(1070, 590), Style.P2, 3.0)
	for k in 6:
		var px = 850.0 + fmod(frame * 2.0 + k * 40.0, 220.0)
		draw_circle(Vector2(px, 590), 4.0, Style.PAPER)
	for pair in [[xa, 0], [xb, 1]]:
		Art.draw_arm(self, pair[0] * Art.SHOULDER_BACK, pair[0] * Art.REST_HANDS[0], Art.palette(pair[1]), true, 1.35)
		Art.draw_body(self, pair[0], Art.palette(pair[1]), 0.4)
		Art.draw_arm(self, pair[0] * Art.SHOULDER_FRONT, pair[0] * Art.REST_HANDS[1], Art.palette(pair[1]), false, 1.35)
	Style.hints(self, [["↑↓", "Mode"], ["B", "Retour"]])
