extends Node2D
## Écran titre.

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")

var app
var frame := 0


func on_enter(_params: Dictionary) -> void:
	pass


func tick() -> void:
	frame += 1
	queue_redraw()


func nav(action: String, _player: int = 0) -> void:
	if action in ["accept", "start"]:
		app.goto("menu", {})


func _draw() -> void:
	var size := Vector2(1280, 720)
	draw_rect(Rect2(Vector2.ZERO, size), Style.NIGHT)
	# rayons depuis le centre
	Style.speed_lines(self, Vector2(640, 400), 160, 900, 60, Color(Style.HOT, 0.10), 21)
	# grands aplats diagonaux
	draw_colored_polygon(PackedVector2Array([Vector2(0, 470), Vector2(1280, 330), Vector2(1280, 720), Vector2(0, 720)]), Style.NIGHT_2)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 600), Vector2(1280, 470), Vector2(1280, 520), Vector2(0, 650)]), Style.HOT)
	Style.halftone(self, Rect2(0, 0, 1280, 470), Color(1, 1, 1, 0.05), 18.0, 5.0, Vector2(0, 1))
	# duel en kumikata, en pied sous le logo
	var sc := 2.7
	var xa := Art.stand_xform(Vector2(582, 606), 1, 0.12, sc, 0.25)
	var xb := Art.stand_xform(Vector2(700, 606), -1, -0.06, sc, 0.1)
	Art.shadow(self, Vector2(641, 608), sc * 1.6, 0.45)
	Art.draw_arm(self, xb * Art.SHOULDER_BACK, xa * Art.GRIP_POINTS["sleeve"], Art.palette(1), true, sc)
	Art.draw_arm(self, xa * Art.SHOULDER_BACK, xb * Art.GRIP_POINTS["sleeve"], Art.palette(0), true, sc)
	Art.draw_body(self, xb, Art.palette(1), 0.6)
	Art.draw_body(self, xa, Art.palette(0), 0.6)
	Art.draw_arm(self, xb * Art.SHOULDER_FRONT, xa * Art.GRIP_POINTS["lapel"], Art.palette(1), false, sc)
	Art.draw_arm(self, xa * Art.SHOULDER_FRONT, xb * Art.GRIP_POINTS["lapel"], Art.palette(0), false, sc)
	# logo
	var pulse := 1.0 + sin(frame * 0.08) * 0.02
	Style.burst(self, Vector2(905, 175), 70 * pulse, 112 * pulse, 12, Style.P1, Style.INK, 4, 0.2)
	Style.text(self, Vector2(250, 250), "JUDO", 210, Style.PAPER, "display", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 12.0)
	Style.text(self, Vector2(842, 216), "2D", 104, Style.INK, "display", HORIZONTAL_ALIGNMENT_LEFT, -1, 2, -1.0)
	var tag := "KUMIKATA  ·  KUZUSHI  ·  IPPON"
	var tr := Rect2(330, 274, 560, 44)
	Style.panel(self, tr, Style.HOT, Style.INK, 4.0, 6.0)
	Style.text(self, Vector2(tr.position.x, tr.position.y + 33), tag, 28, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 1, -1.0)
	# appuie sur A
	if (frame / 30) % 2 == 0 or app == null or app.capture_mode:
		var pr := Rect2(470, 628, 340, 56)
		Style.panel(self, pr, Style.INK, Style.PAPER, 4.0, 6.0)
		Style.text(self, Vector2(pr.position.x + 40, pr.position.y + 40), "APPUIE SUR", 30, Style.PAPER, "display", HORIZONTAL_ALIGNMENT_LEFT, -1, 3, 0.0)
		Style.pad_button(self, Vector2(pr.position.x + 268, pr.position.y + 28), "A", 17.0)
	Style.label(self, Vector2(28, 700), "PROTOTYPE v0.1 — PHASE 1", 14, Style.MUTED, "black")
	Style.label(self, Vector2(0, 700), "© 2026 HUGO MOULARD", 14, Style.MUTED, "black", HORIZONTAL_ALIGNMENT_RIGHT, 1252)
