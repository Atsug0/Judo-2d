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
