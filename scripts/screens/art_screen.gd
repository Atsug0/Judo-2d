extends Node2D
## Planche de personnages (outil de travail) : les deux judokas en grand, plusieurs poses.

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")

var app


func on_enter(_params: Dictionary) -> void:
	pass


func nav(action: String, _player: int = 0) -> void:
	if action == "back":
		app.goto("menu", {})


func _draw() -> void:
	Style.menu_background(self, Vector2(1280, 720), Style.HOT)
	Style.header(self, "PLANCHE PERSO", "Placeholders cel-shading — en attendant le rendu Blender", Style.PAPER)
	if app != null and app.args.has("zoom"):
		_draw_zoom()
		return
	# grands portraits
	var poses := [
		{"x": 230.0, "p": 0, "lean": 0.0, "stance": 0.4, "label": "GARDE"},
		{"x": 520.0, "p": 1, "lean": 0.0, "stance": 0.4, "label": "GARDE"},
		{"x": 810.0, "p": 0, "lean": 0.22, "stance": 1.0, "label": "KUZUSHI AVANT"},
		{"x": 1080.0, "p": 1, "lean": -0.2, "stance": 0.2, "label": "DÉSÉQUILIBRE ARRIÈRE"},
	]
	for po in poses:
		var sc := 4.2
		var feet := Vector2(po.x, 660)
		var xf := Art.stand_xform(feet, 1 if po.p == 0 else -1, (1 if po.p == 0 else -1) * po.lean, sc, 0.0)
		var pal := Art.palette(po.p)
		Art.shadow(self, feet + Vector2(0, 2), sc, 0.4)
		Art.draw_arm(self, xf * Art.SHOULDER_BACK, xf * Art.REST_HANDS[0], pal, true, sc)
		Art.draw_body(self, xf, pal, po.stance)
		Art.draw_arm(self, xf * Art.SHOULDER_FRONT, xf * Art.REST_HANDS[1], pal, false, sc)
		var w := Style.text_width(po.label, 18, "black") + 30
		var r := Rect2(po.x - w / 2, 160, w, 30)
		Style.chip(self, r, Style.INK, pal.accent)
		Style.label(self, Vector2(r.position.x, r.position.y + 21), po.label, 18, pal.accent, "black", HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_zoom() -> void:
	# gros plan tête + bras, les deux judokas en kumikata
	var sc := 5.4
	var xa := Art.stand_xform(Vector2(520, 960), 1, 0.05, sc, 0.0)
	var xb := Art.stand_xform(Vector2(780, 960), -1, -0.03, sc, 0.0)
	var pa := Art.palette(0)
	var pb := Art.palette(1)
	Art.draw_arm(self, xb * Art.SHOULDER_BACK, xa * Art.GRIP_POINTS["sleeve"], pb, true, sc)
	Art.draw_arm(self, xa * Art.SHOULDER_BACK, xb * Art.GRIP_POINTS["sleeve"], pa, true, sc)
	Art.draw_body(self, xb, pb, 0.4)
	Art.draw_body(self, xa, pa, 0.4)
	Art.draw_arm(self, xb * Art.SHOULDER_FRONT, xa * Art.GRIP_POINTS["lapel"], pb, false, sc, 0.3)
	Art.draw_arm(self, xa * Art.SHOULDER_FRONT, xb * Art.GRIP_POINTS["lapel"], pa, false, sc, 0.6)
