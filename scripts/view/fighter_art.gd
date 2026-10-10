extends RefCounted
## Judoka placeholder en cel-shading (deux tons + contour d'encre),
## en attendant les sprites issus du pipeline Blender.
## Coordonnées locales : pieds en (0, 0), avant = +x, haut = -y (1 unité = 1 px à l'échelle 1).

const Style := preload("res://scripts/ui/style.gd")

const HEIGHT := 92.0
## Points d'ancrage locaux (épaules, cibles de saisie).
const SHOULDER_FRONT := Vector2(6, -70)
const SHOULDER_BACK := Vector2(-5, -71)
const GRIP_POINTS := {
	"sleeve": Vector2(13, -50),
	"lapel": Vector2(10, -64),
	"collar": Vector2(-7, -76),
	"belt": Vector2(15, -38),
}
const REST_HANDS := [Vector2(14, -46), Vector2(20, -54)]


static func palette(player: int) -> Dictionary:
	if player == 0:
		return {"gi": Style.GI_WHITE, "gi_shade": Style.GI_WHITE_SHADE, "skin": Style.SKIN_A,
			"skin_shade": Style.SKIN_A_SHADE, "hair": Color("2b1d14"), "accent": Style.P1}
	return {"gi": Style.GI_BLUE, "gi_shade": Style.GI_BLUE_SHADE, "skin": Style.SKIN_B,
		"skin_shade": Style.SKIN_B_SHADE, "hair": Color("120c0a"), "accent": Style.P2}


## Transform local → écran pour un judoka debout.
static func stand_xform(feet: Vector2, facing: int, lean: float, scale: float, crouch: float = 0.0) -> Transform2D:
	var t := Transform2D(facing * lean, Vector2(facing * scale, scale * (1.0 - crouch * 0.12)), 0.0, feet)
	return t


static func draw_body(ci: CanvasItem, xf: Transform2D, pal: Dictionary, stance: float = 0.0) -> void:
	ci.draw_set_transform_matrix(xf)
	var ink := Style.INK
	var w := 2.6 / maxf(0.5, xf.get_scale().y)  # épaisseur du contour constante à l'écran
	var w_ink := 3.4
	# Ombre au sol (dessinée hors transform plus bas)
	# --- Jambes (arrière puis avant)
	var spread := 3.0 + stance * 4.0
	_poly(ci, [Vector2(-10, -40), Vector2(-1, -40), Vector2(-9 - spread, -2), Vector2(-19 - spread, -2)], pal.gi_shade, w_ink)
	_poly(ci, [Vector2(0, -40), Vector2(11, -40), Vector2(15 + spread, -2), Vector2(5 + spread, -2)], pal.gi, w_ink)
	# pieds
	_poly(ci, [Vector2(-20 - spread, -3), Vector2(-8 - spread, -3), Vector2(-6 - spread, 0), Vector2(-21 - spread, 0)], pal.skin_shade, w_ink)
	_poly(ci, [Vector2(4 + spread, -3), Vector2(16 + spread, -3), Vector2(19 + spread, 0), Vector2(3 + spread, 0)], pal.skin, w_ink)
	# --- Veste (dos ombré, face éclairée)
	_poly(ci, [Vector2(-14, -73), Vector2(13, -73), Vector2(16, -30), Vector2(-16, -30)], pal.gi, w_ink)
	_poly(ci, [Vector2(-14, -73), Vector2(-3, -73), Vector2(-6, -30), Vector2(-16, -30)], pal.gi_shade, 0.0)
	# revers croisés
	ci.draw_line(Vector2(-1, -73), Vector2(10, -48), pal.gi_shade, 3.0)
	ci.draw_line(Vector2(7, -73), Vector2(3, -56), pal.gi_shade, 2.4)
	_outline(ci, [Vector2(-14, -73), Vector2(13, -73), Vector2(16, -30), Vector2(-16, -30)], w_ink)
	# --- Ceinture noire + nœud
	_poly(ci, [Vector2(-16, -42), Vector2(16, -42), Vector2(16, -36), Vector2(-16, -36)], Color("16131c"), 0.0)
	ci.draw_line(Vector2(13, -38), Vector2(18, -28), Color("16131c"), 3.0)
	ci.draw_line(Vector2(12, -38), Vector2(13, -27), Color("16131c"), 3.0)
	# --- Cou + tête
	_poly(ci, [Vector2(-4, -78), Vector2(5, -78), Vector2(5, -72), Vector2(-4, -72)], pal.skin_shade, 0.0)
	ci.draw_circle(Vector2(1, -85), 10.5, ink)
	ci.draw_circle(Vector2(1, -85), 9.0, pal.skin)
	# ombre de la tête (côté arrière)
	ci.draw_arc(Vector2(1, -85), 6.0, PI * 0.55, PI * 1.45, 12, pal.skin_shade, 6.0)
	# cheveux
	ci.draw_arc(Vector2(0, -86), 7.5, PI * 0.95, PI * 2.05, 16, pal.hair, 6.0)
	# œil (regarde vers l'avant)
	ci.draw_line(Vector2(6, -86), Vector2(8.5, -86), ink, 2.0)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Bras : de l'épaule (repère du corps) à la main (coordonnées écran), coude fléchi.
static func draw_arm(ci: CanvasItem, shoulder: Vector2, hand: Vector2, pal: Dictionary, back: bool, scale: float, grip_strength: float = -1.0) -> void:
	var mid := (shoulder + hand) * 0.5
	var d := hand - shoulder
	var n := Vector2(-d.y, d.x).normalized()
	if n.y < 0:
		n = -n
	var elbow := mid + n * clampf(30.0 * scale - d.length() * 0.25, 0.0, 14.0 * scale)
	var col: Color = pal.gi_shade if back else pal.gi
	var wi := 12.0 * scale * 0.5
	for seg in [[shoulder, elbow], [elbow, hand]]:
		ci.draw_line(seg[0], seg[1], Style.INK, wi + 6.0, true)
	ci.draw_circle(elbow, (wi + 6.0) * 0.5, Style.INK)
	for seg in [[shoulder, elbow], [elbow, hand]]:
		ci.draw_line(seg[0], seg[1], col, wi, true)
	ci.draw_circle(elbow, wi * 0.5, col)
	# main
	ci.draw_circle(hand, 5.5 * scale * 0.5 + 3.0, Style.INK)
	ci.draw_circle(hand, 5.5 * scale * 0.5, pal.skin)
	if grip_strength >= 0.0:
		var c := Style.GOOD.lerp(Style.DANGER, clampf(grip_strength, 0.0, 1.0))
		ci.draw_arc(hand, 5.5 * scale * 0.5 + 5.0, 0, TAU, 20, c, 3.0, true)


static func shadow(ci: CanvasItem, feet: Vector2, scale: float, alpha: float = 0.35) -> void:
	var pts := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(feet + Vector2(cos(a) * 30.0 * scale, sin(a) * 6.0 * scale))
	ci.draw_colored_polygon(pts, Color(0, 0, 0, alpha))


static func _poly(ci: CanvasItem, pts: Array, col: Color, outline_w: float) -> void:
	var p := PackedVector2Array(pts)
	ci.draw_colored_polygon(p, col)
	if outline_w > 0.0:
		_outline(ci, pts, outline_w)


static func _outline(ci: CanvasItem, pts: Array, wdt: float) -> void:
	var p := PackedVector2Array(pts)
	p.append(pts[0])
	ci.draw_polyline(p, Style.INK, wdt, true)
