extends Node2D
## Planche des légendes (outil de contrôle visuel) : les dix judokas pré-configurés,
## en judogi blanc et bleu, avec leur nom. godot --path . -- --screen=lineup --capture=/tmp/x

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const Build := preload("res://scripts/build.gd")

var app
var frame = 0


func on_enter(_p: Dictionary) -> void:
	pass


func tick() -> void:
	frame += 1
	queue_redraw()


func nav(_a: String, _p: int = 0) -> void:
	pass


func _draw() -> void:
	Style.menu_background(self, Vector2(1280, 720), Style.HOT)
	var ls: Array = Build.legends()
	for k in ls.size():
		var l: Dictionary = ls[k]
		var col = k % 5
		var rowi = k / 5
		var feet = Vector2(130 + col * 255, 330 + rowi * 330)
		var sc = 2.35
		var side = k % 2
		var xf = Art.stand_xform(feet, 1, 0.0, sc, 0.25)
		var pal = Art.palette(side, l.get("look", {}))
		Art.shadow(self, feet + Vector2(0, 2), sc, 0.35)
		Art.draw_arm(self, xf * Art.SHOULDER_BACK, xf * Art.REST_HANDS[0], pal, true, sc)
		Art.draw_body(self, xf, pal, 0.3)
		Art.draw_arm(self, xf * Art.SHOULDER_FRONT, xf * Art.REST_HANDS[1], pal, false, sc)
		Style.text(self, Vector2(feet.x - 110, feet.y + 34), String(l.name), 26, Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, 220)
		Style.label(self, Vector2(feet.x - 110, feet.y + 54), String(l.get("tag", "")).to_upper(), 11, Style.MUTED, "black", HORIZONTAL_ALIGNMENT_CENTER, 220)
