extends RefCounted
## Judoka placeholder en cel-shading, inspiration 2XKO : proportions héroïques,
## deux tons + liseré de lumière coloré, contours d'encre épais.
## En attendant les sprites issus du pipeline Blender.
## Coordonnées locales : pieds en (0, 0), avant = +x, haut = -y.

const Style := preload("res://scripts/ui/style.gd")

const HEIGHT := 100.0
const SHOULDER_FRONT := Vector2(9, -79)
const SHOULDER_BACK := Vector2(-8, -80)
const GRIP_POINTS := {
	"sleeve": Vector2(16, -60),
	"lapel": Vector2(9, -72),
	"collar": Vector2(-8, -86),
	"belt": Vector2(15, -45),
}
const REST_HANDS := [Vector2(15, -54), Vector2(22, -62)]


static func palette(player: int) -> Dictionary:
	if player == 0:
		return {"gi": Style.GI_WHITE, "gi_shade": Style.GI_WHITE_SHADE, "gi_deep": Color("a59d8f"),
			"skin": Style.SKIN_A, "skin_shade": Style.SKIN_A_SHADE, "hair": Color("3a2416"), "hair_style": 0,
			"accent": Style.P1}
	return {"gi": Style.GI_BLUE, "gi_shade": Style.GI_BLUE_SHADE, "gi_deep": Color("13296b"),
		"skin": Style.SKIN_B, "skin_shade": Style.SKIN_B_SHADE, "hair": Color("120c0a"), "hair_style": 1,
		"accent": Style.P2}


static func stand_xform(feet: Vector2, facing: int, lean: float, scale: float, crouch: float = 0.0) -> Transform2D:
	return Transform2D(facing * lean, Vector2(facing * scale, scale * (1.0 - crouch * 0.12)), 0.0, feet)


static func draw_body(ci: CanvasItem, xf: Transform2D, pal: Dictionary, stance: float = 0.0) -> void:
	ci.draw_set_transform_matrix(xf)
	var ink := Style.INK
	var acc: Color = pal.accent
	var sc := maxf(0.5, absf(xf.get_scale().y))
	var ow := 4.2 / sc   # contour principal ≈ 4 px à l'écran
	var dw := 2.6 / sc   # contour de détail
	var spread := 2.0 + stance * 5.0
	var bend := 3.0 + stance * 3.0
	# --- Jambes (cuisse + tibia, genou fléchi), arrière puis avant
	_limb(ci, [Vector2(-6, -47), Vector2(-11 - spread * 0.4, -24 - bend * 0.2), Vector2(-15 - spread, -4)], 12.0, pal.gi_shade, ow)
	_foot(ci, Vector2(-15 - spread, -2), -1.0, pal.skin_shade, dw)
	_limb(ci, [Vector2(6, -47), Vector2(13 + spread * 0.4 + bend, -25), Vector2(15 + spread, -4)], 12.5, pal.gi, ow)
	_foot(ci, Vector2(15 + spread, -2), 1.0, pal.skin, dw)
	# pli du pantalon (genou avant)
	ci.draw_line(Vector2(11 + spread * 0.4 + bend, -28), Vector2(15 + spread * 0.4 + bend, -23), pal.gi_shade, 1.6)
	# --- Veste : silhouette en V (épaules larges, taille serrée, jupe évasée)
	var jacket := [Vector2(-15, -82), Vector2(-3, -86), Vector2(6, -86), Vector2(15, -81), Vector2(17, -68),
		Vector2(13, -49), Vector2(17, -33), Vector2(-16, -33), Vector2(-13, -49), Vector2(-17, -68)]
	_poly(ci, jacket, pal.gi, 0.0)
	# ombre propre (côté dos) + ombre portée sous les pectoraux
	_poly(ci, [Vector2(-15, -82), Vector2(-3, -86), Vector2(-4, -60), Vector2(-7, -33), Vector2(-16, -33), Vector2(-13, -49), Vector2(-17, -68)], pal.gi_shade, 0.0)
	ci.draw_polyline(PackedVector2Array([Vector2(1, -58), Vector2(7, -56.5), Vector2(14, -58)]), pal.gi_shade, 1.4, true)
	# revers : bande épaisse en diagonale + col
	_poly(ci, [Vector2(-1, -86), Vector2(4, -86), Vector2(13, -50), Vector2(8, -50)], pal.gi_deep, 0.0)
	_poly(ci, [Vector2(4, -86), Vector2(8, -85), Vector2(4, -70), Vector2(2, -74)], pal.gi_deep, 0.0)
	# plis de la jupe
	ci.draw_line(Vector2(3, -40), Vector2(5, -33), pal.gi_shade, 1.6)
	ci.draw_line(Vector2(-9, -40), Vector2(-10, -33), pal.gi_deep, 1.4)
	_outline(ci, jacket, ow)
	# liseré de lumière coloré (côté dos)
	ci.draw_polyline(PackedVector2Array([Vector2(-14, -81), Vector2(-16, -68), Vector2(-12.5, -50), Vector2(-15, -35)]), Color(acc, 0.9), 2.0, true)
	# --- Ceinture noire : nœud et pans qui flottent
	_poly(ci, [Vector2(-14, -49), Vector2(14, -49), Vector2(14.5, -43), Vector2(-14.5, -43)], Color("17141f"), 0.0)
	ci.draw_line(Vector2(-14, -48), Vector2(14, -48), Color(1, 1, 1, 0.12), 1.0)
	_poly(ci, [Vector2(10, -48), Vector2(15, -48), Vector2(15, -43), Vector2(10, -43)], Color("26222f"), 0.0)
	ci.draw_line(Vector2(13, -44), Vector2(19, -32), Color("17141f"), 3.2)
	ci.draw_line(Vector2(12, -44), Vector2(13, -31), Color("17141f"), 3.2)
	# --- Cou
	_poly(ci, [Vector2(-3, -92), Vector2(5, -92), Vector2(5, -85), Vector2(-3, -85)], pal.skin_shade, 0.0)
	# --- Tête (plus petite : proportions héroïques), mâchoire marquée
	var head := [Vector2(-6, -103), Vector2(4, -105), Vector2(9, -99), Vector2(9.5, -94), Vector2(7, -89),
		Vector2(1, -87.5), Vector2(-5, -89), Vector2(-7.5, -95)]
	_poly(ci, head, pal.skin, 0.0)
	_poly(ci, [Vector2(-6, -103), Vector2(-1, -104), Vector2(-2, -92), Vector2(1, -87.5), Vector2(-5, -89), Vector2(-7.5, -95)], pal.skin_shade, 0.0)
	# oreille
	ci.draw_circle(Vector2(-2.5, -95), 1.8, pal.skin_shade)
	# sourcil (regard déterminé) + œil
	ci.draw_line(Vector2(4, -98.5), Vector2(9, -97.2), ink, 1.8)
	ci.draw_line(Vector2(6.2, -95.6), Vector2(8.4, -95.4), ink, 1.6)
	# nez + bouche
	ci.draw_line(Vector2(9.4, -94.5), Vector2(10.2, -92.6), pal.skin_shade, 1.2)
	ci.draw_line(Vector2(6.5, -90.6), Vector2(8.8, -90.9), pal.skin_shade, 1.2)
	_outline(ci, head, dw * 1.2)
	# cheveux
	if pal.hair_style == 0:
		# mèches rabattues vers l'arrière, trois pointes nettes
		_poly(ci, [Vector2(-7.5, -95), Vector2(-8, -102), Vector2(-13, -104), Vector2(-6, -106.5), Vector2(-9, -110),
			Vector2(-1, -108), Vector2(1, -111), Vector2(5, -107), Vector2(10, -104), Vector2(9.6, -100.5),
			Vector2(4, -101.5), Vector2(-1, -100), Vector2(-4, -96)], pal.hair, dw)
	else:
		# coupe courte à plat (fade)
		_poly(ci, [Vector2(-7.5, -96), Vector2(-7, -104), Vector2(-2, -106.5), Vector2(6, -106.5), Vector2(9.5, -102),
			Vector2(9, -100), Vector2(3, -101), Vector2(-2, -100.5), Vector2(-4, -96)], pal.hair, dw)
	# reflet de lumière coloré sur les cheveux (côté dos)
	ci.draw_line(Vector2(-6.5, -102), Vector2(-3, -105.5), Color(acc, 0.75), 1.2)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Bras en coordonnées écran : manche du judogi jusqu'à mi-avant-bras, puis peau et poing.
static func draw_arm(ci: CanvasItem, shoulder: Vector2, hand: Vector2, pal: Dictionary, back: bool, scale: float, grip_strength: float = -1.0) -> void:
	var d := hand - shoulder
	var n := Vector2(-d.y, d.x).normalized()
	if n.y < 0:
		n = -n
	var reach := 34.0 * scale
	var elbow := (shoulder + hand) * 0.5 + n * clampf((reach - d.length()) * 0.45, 0.0, 15.0 * scale)
	var col: Color = pal.gi_shade if back else pal.gi
	var w_up := 6.4 * scale
	var w_fore := 5.6 * scale
	var cuff := elbow.lerp(hand, 0.62)
	# contours
	for seg in [[shoulder, elbow, w_up], [elbow, hand, w_fore]]:
		ci.draw_line(seg[0], seg[1], Style.INK, seg[2] + 8.0, true)
	ci.draw_circle(elbow, (w_up + 8.0) * 0.5, Style.INK)
	ci.draw_circle(shoulder, (w_up + 8.0) * 0.5, Style.INK)
	# peau de l'avant-bras puis manche par-dessus
	ci.draw_line(cuff, hand, pal.skin_shade if back else pal.skin, w_fore * 0.82, true)
	ci.draw_line(shoulder, elbow, col, w_up, true)
	ci.draw_circle(elbow, w_up * 0.5, col)
	ci.draw_circle(shoulder, w_up * 0.5, col)
	ci.draw_line(elbow, cuff, col, w_fore + 1.0, true)
	# bord de la manche
	var cn := Vector2(-(hand - elbow).y, (hand - elbow).x).normalized() * (w_fore + 1.0) * 0.55
	ci.draw_line(cuff - cn, cuff + cn, pal.gi_deep, 2.0, true)
	# poing
	var fist := 3.6 * scale
	ci.draw_circle(hand, fist + 4.0, Style.INK)
	ci.draw_circle(hand, fist, pal.skin_shade if back else pal.skin)
	ci.draw_arc(hand, fist * 0.55, -PI * 0.2, PI * 0.6, 8, pal.skin_shade, 1.5, true)
	if grip_strength >= 0.0:
		var c := Style.GOOD.lerp(Style.DANGER, clampf(grip_strength, 0.0, 1.0))
		ci.draw_arc(hand, fist + 5.5, 0, TAU, 20, c, 3.0, true)


static func shadow(ci: CanvasItem, feet: Vector2, scale: float, alpha: float = 0.35) -> void:
	var pts := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(feet + Vector2(cos(a) * 30.0 * scale, sin(a) * 6.0 * scale))
	ci.draw_colored_polygon(pts, Color(0, 0, 0, alpha))


## Membre en capsule (contour d'encre + remplissage) passant par plusieurs points.
static func _limb(ci: CanvasItem, pts: Array, w: float, col: Color, ow: float = 1.7) -> void:
	for k in pts.size() - 1:
		ci.draw_line(pts[k], pts[k + 1], Style.INK, w + ow * 2.0, true)
	for p in pts:
		ci.draw_circle(p, (w + ow * 2.0) * 0.5, Style.INK)
	for k in pts.size() - 1:
		ci.draw_line(pts[k], pts[k + 1], col, w, true)
	for p in pts:
		ci.draw_circle(p, w * 0.5, col)


static func _foot(ci: CanvasItem, heel: Vector2, dir: float, col: Color, ow: float = 2.4) -> void:
	var pts := [heel + Vector2(-4 * dir, -3), heel + Vector2(6 * dir, -3), heel + Vector2(9 * dir, 2), heel + Vector2(-5 * dir, 2)]
	_poly(ci, pts, col, ow)


static func _poly(ci: CanvasItem, pts: Array, col: Color, outline_w: float) -> void:
	ci.draw_colored_polygon(PackedVector2Array(pts), col)
	if outline_w > 0.0:
		_outline(ci, pts, outline_w)


static func _outline(ci: CanvasItem, pts: Array, wdt: float) -> void:
	var p := PackedVector2Array(pts)
	p.append(pts[0])
	ci.draw_polyline(p, Style.INK, wdt, true)
