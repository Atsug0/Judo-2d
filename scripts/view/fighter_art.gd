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
const REST_HANDS := [Vector2(22, -57), Vector2(29, -65)]


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


## Poses d'une projection à l'avancement p (0..1), en coordonnées écran.
## dir : direction de la technique ("avant", "contre", "arriere", ...), big : ippon.
## tx, ux : x écran des pieds de tori et d'uke au départ ; k : échelle (px par unité).
## Renvoie [transform de tori, transform d'uke].
static func throw_xforms(dir: String, big: bool, fc: int, tx: float, ux: float, feet_y: float, k: float, p: float) -> Array:
	var e := p * p * (3.0 - 2.0 * p)  # ease in-out
	var uke_f := -fc
	var tori_xf: Transform2D
	var uke_xf: Transform2D
	if dir in ["avant", "contre", "avant_cote"]:
		# uke passe par-dessus tori et retombe de l'autre côté
		var end_x := tx - fc * 32.0 * k
		var mid := Vector2(lerpf(ux, end_x, e), lerpf(feet_y - 22.0 * k, feet_y - 10.9 * k, e) - sin(PI * p) * (95.5 if big else 81.8) * k)
		var rot := -fc * PI * 1.5 * e
		uke_xf = Transform2D(rot, Vector2(uke_f * k, k), 0.0, mid) * Transform2D(0.0, Vector2(0, 22.0))
		var tori_lean := (0.55 * sin(PI * minf(p * 1.3, 1.0))) if dir != "contre" else (-0.45 * sin(PI * minf(p * 1.2, 1.0)))
		var tori_face := -fc if dir != "contre" and p > 0.15 and p < 0.9 else fc
		tori_xf = stand_xform(Vector2(tx, feet_y), tori_face, tori_lean * tori_face, k, 0.6 * sin(PI * p))
	else:
		# uke bascule en arrière, loin de tori
		var end_x := ux + fc * 15.5 * k
		var lift := (15.5 if big else 9.1) * k
		var mid := Vector2(lerpf(ux, end_x, e), lerpf(feet_y - 22.0 * k, feet_y - 10.9 * k, e) - sin(PI * p) * lift)
		var rot := fc * PI * 0.5 * e
		uke_xf = Transform2D(rot, Vector2(uke_f * k, k), 0.0, mid) * Transform2D(0.0, Vector2(0, 22.0))
		tori_xf = stand_xform(Vector2(tx + fc * 4.5 * k * e, feet_y), fc, 0.32 * sin(PI * minf(p * 1.2, 1.0)), k, 0.3 * sin(PI * p))
	return [tori_xf, uke_xf]


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
	_foot(ci, Vector2(-15 - spread, -1.4), -1.0, pal.skin_shade, dw * 1.3)
	_limb(ci, [Vector2(6, -47), Vector2(13 + spread * 0.4 + bend, -25), Vector2(15 + spread, -4)], 12.5, pal.gi, ow)
	_foot(ci, Vector2(15 + spread, -1.4), 1.0, pal.skin, dw * 1.3)
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
	_draw_head(ci, pal, ow, dw)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Bras en coordonnées écran : manche large du judogi avec plis et ourlet,
## avant-bras musclé, main en poing orientée selon l'avant-bras.
static func draw_arm(ci: CanvasItem, shoulder: Vector2, hand: Vector2, pal: Dictionary, back: bool, scale: float, grip_strength: float = -1.0, elbow_at: Vector2 = Vector2.INF) -> void:
	var d := hand - shoulder
	var bendn := Vector2(-d.y, d.x).normalized()
	if bendn.y < 0:
		bendn = -bendn
	var reach := 36.0 * scale
	var elbow := (shoulder + hand) * 0.5 + bendn * clampf((reach - d.length()) * 0.45, 0.0, 15.0 * scale)
	if elbow_at != Vector2.INF:
		elbow = elbow_at
	var u1 := (elbow - shoulder).normalized()
	var u2 := (hand - elbow).normalized()
	var n1 := Vector2(-u1.y, u1.x)
	var n2 := Vector2(-u2.y, u2.x)
	var ne := (n1 + n2).normalized()
	var gi: Color = pal.gi_shade if back else pal.gi
	var gi_sh: Color = pal.gi_deep if back else pal.gi_shade
	var skin: Color = pal.skin_shade if back else pal.skin
	var skin_sh: Color = pal.skin_shade.darkened(0.15) if back else pal.skin_shade
	var k := scale
	var wrist := hand - u2 * 3.4 * k
	var cuff := elbow.lerp(wrist, 0.5)
	var ink_w := 4.0
	# --- avant-bras (peau), légèrement conique, sous la manche
	var fore := PackedVector2Array([cuff + n2 * 3.4 * k, wrist + n2 * 2.4 * k, wrist - n2 * 2.4 * k, cuff - n2 * 3.4 * k])
	ci.draw_colored_polygon(fore, skin)
	ci.draw_colored_polygon(PackedVector2Array([cuff - n2 * 0.4 * k, wrist - n2 * 0.6 * k, wrist - n2 * 2.4 * k, cuff - n2 * 3.4 * k]), skin_sh)
	_pline(ci, fore, ink_w)
	# --- main (poing) orientée selon l'avant-bras
	var hp := PackedVector2Array([
		wrist + n2 * 2.6 * k, wrist + u2 * 2.2 * k + n2 * 3.4 * k, wrist + u2 * 5.0 * k + n2 * 3.0 * k,
		wrist + u2 * 6.0 * k + n2 * 1.0 * k, wrist + u2 * 6.0 * k - n2 * 1.6 * k, wrist + u2 * 4.6 * k - n2 * 3.2 * k,
		wrist + u2 * 2.0 * k - n2 * 3.6 * k, wrist - n2 * 2.6 * k])
	ci.draw_colored_polygon(hp, skin)
	# pouce + jointures
	ci.draw_polyline(PackedVector2Array([wrist + u2 * 1.6 * k + n2 * 2.4 * k, wrist + u2 * 3.8 * k + n2 * 1.2 * k, wrist + u2 * 4.4 * k - n2 * 0.6 * k]), skin_sh, 1.8, true)
	for t in [0.0, 1.0, 2.0]:
		var kp: Vector2 = wrist + u2 * 5.2 * k + n2 * (1.6 - t * 1.4) * k
		ci.draw_line(kp, kp - u2 * 1.2 * k, skin_sh, 1.4, true)
	_pline(ci, hp, ink_w)
	# --- manche : large, évasée à l'ourlet, coude plié
	var s0 := shoulder - u1 * 2.0 * k
	var sleeve := PackedVector2Array([
		s0 - u1 * 2.4 * k, s0 + n1 * 4.6 * k, elbow + ne * 4.4 * k, cuff + n2 * 5.0 * k,
		cuff - n2 * 5.0 * k, elbow - ne * 4.0 * k, s0 - n1 * 4.6 * k])
	ci.draw_colored_polygon(sleeve, gi)
	# ombre propre sous la manche
	ci.draw_colored_polygon(PackedVector2Array([s0 - n1 * 1.0 * k, elbow - ne * 0.8 * k, cuff - n2 * 1.4 * k,
		cuff - n2 * 5.0 * k, elbow - ne * 4.0 * k, s0 - n1 * 4.6 * k]), gi_sh)
	# plis au coude
	ci.draw_line(elbow + ne * 2.6 * k - u1 * 1.6 * k, elbow + ne * 0.4 * k + u2 * 0.6 * k, gi_sh, 1.8, true)
	ci.draw_line(elbow - ne * 1.0 * k - u1 * 2.4 * k, elbow - ne * 2.8 * k - u1 * 0.4 * k, pal.gi_deep, 1.6, true)
	# ourlet de la manche
	ci.draw_line(cuff + n2 * 5.0 * k - u2 * 1.4 * k, cuff - n2 * 5.0 * k - u2 * 1.4 * k, gi_sh, 1.8, true)
	_pline(ci, sleeve, ink_w)
	if grip_strength >= 0.0:
		var c := Style.GOOD.lerp(Style.DANGER, clampf(grip_strength, 0.0, 1.0))
		ci.draw_arc(wrist + u2 * 3.4 * k, 6.2 * k, 0, TAU, 24, c, 3.0, true)


static func _pline(ci: CanvasItem, pts: PackedVector2Array, w: float) -> void:
	var c := pts.duplicate()
	c.append(pts[0])
	ci.draw_polyline(c, Style.INK, w, true)


## Tête de profil 3/4 : crâne, mâchoire carrée, nez, yeux expressifs, cou épais.
static func _draw_head(ci: CanvasItem, pal: Dictionary, ow: float, dw: float) -> void:
	var ink := Style.INK
	var acc: Color = pal.accent
	# cou épais + trapèzes
	var neck := [Vector2(-5.5, -93), Vector2(4.5, -91), Vector2(6.5, -85.5), Vector2(-7.5, -84.5)]
	_poly(ci, neck, pal.skin_shade, 0.0)
	ci.draw_polyline(PackedVector2Array([Vector2(-5.5, -93), Vector2(-7.5, -86), Vector2(-12, -83)]), ink, dw, true)
	ci.draw_polyline(PackedVector2Array([Vector2(4.5, -91), Vector2(6.5, -86)]), ink, dw, true)
	# crâne + visage (profil vers +x)
	var head := [Vector2(-7.5, -104), Vector2(-4, -109.5), Vector2(2, -111), Vector2(7, -108.5), Vector2(9, -103.5),
		Vector2(9.3, -101.5), Vector2(11.8, -97.6), Vector2(9.8, -96.4), Vector2(10.3, -94.8), Vector2(9.6, -93.8),
		Vector2(10, -92.6), Vector2(9.2, -90.2), Vector2(6, -88.4), Vector2(0.5, -89.4), Vector2(-3.5, -92.5),
		Vector2(-7.5, -96.5), Vector2(-8.5, -100.5)]
	_poly(ci, head, pal.skin, 0.0)
	# ombre propre : arrière du crâne, sous la pommette, sous la mâchoire
	_poly(ci, [Vector2(-7.5, -104), Vector2(-4, -109.5), Vector2(-1, -110), Vector2(-1.5, -99), Vector2(1.5, -91),
		Vector2(0.5, -89.4), Vector2(-3.5, -92.5), Vector2(-7.5, -96.5), Vector2(-8.5, -100.5)], pal.skin_shade, 0.0)
	_poly(ci, [Vector2(3, -96.5), Vector2(8.6, -96.2), Vector2(9.2, -90.2), Vector2(6, -88.4), Vector2(4.5, -92)], Color(pal.skin_shade, 0.55), 0.0)
	_outline(ci, head, ow * 0.85)
	# oreille
	var ear := [Vector2(-2.6, -100.6), Vector2(0.2, -100.8), Vector2(0.6, -97.4), Vector2(-0.6, -95), Vector2(-2.8, -96)]
	_poly(ci, ear, pal.skin, dw)
	ci.draw_arc(Vector2(-1.2, -98.2), 1.1, -PI * 0.6, PI * 0.6, 8, pal.skin_shade, dw, true)
	# sourcil épais (regard déterminé, incliné vers le nez)
	_poly(ci, [Vector2(3.2, -104.4), Vector2(9.2, -103.2), Vector2(9.0, -101.8), Vector2(3.6, -102.8)], ink, 0.0)
	# œil en amande : blanc, iris, paupière
	_poly(ci, [Vector2(4.4, -101.0), Vector2(8.4, -101.4), Vector2(8.8, -99.8), Vector2(5.0, -99.6)], Color("fbf7ee"), 0.0)
	ci.draw_circle(Vector2(7.3, -100.5), 0.95, ink)
	ci.draw_polyline(PackedVector2Array([Vector2(4.0, -100.9), Vector2(8.6, -101.6), Vector2(9.2, -100.6)]), ink, dw * 1.1, true)
	# arête du nez, narine, bouche, menton
	ci.draw_line(Vector2(9.8, -97.2), Vector2(10.6, -96.9), pal.skin_shade, dw * 0.8, true)
	ci.draw_line(Vector2(7.2, -93.6), Vector2(9.6, -93.8), ink, dw * 0.8, true)
	ci.draw_line(Vector2(6.6, -90.2), Vector2(8.6, -90.4), pal.skin_shade, dw * 0.8, true)
	# cheveux
	if pal.hair_style == 0:
		# volume plaqué vers l'arrière, mèches en pointes vers l'arrière
		var hair := [Vector2(-8.6, -99.5), Vector2(-14.5, -101.5), Vector2(-9.5, -104), Vector2(-15, -108.5),
			Vector2(-8, -109), Vector2(-10.5, -114), Vector2(-2, -112.6), Vector2(3, -114.4), Vector2(6.5, -111.6),
			Vector2(10.4, -108.8), Vector2(8.6, -105.6), Vector2(5.5, -107), Vector2(1, -106.4), Vector2(-3, -104.2),
			Vector2(-4.8, -100.2)]
		_poly(ci, hair, pal.hair, ow * 0.8)
		ci.draw_polyline(PackedVector2Array([Vector2(-9, -108.2), Vector2(-3, -110.6), Vector2(4, -111.4)]), pal.hair.lightened(0.28), dw, true)
	else:
		# fade : côtés courts (ombre), dessus texturé
		var top := [Vector2(-7.6, -105.5), Vector2(-5.5, -111), Vector2(0, -113), Vector2(6, -112), Vector2(9.6, -108.4),
			Vector2(9.2, -105.6), Vector2(5, -106.8), Vector2(0, -106), Vector2(-3.5, -104.6)]
		_poly(ci, top, pal.hair, ow * 0.8)
		for t in 5:
			var x := -5.0 + t * 3.0
			ci.draw_arc(Vector2(x, -109.0 + absf(t - 2) * 0.4), 1.2, PI, TAU, 6, pal.hair.lightened(0.25), dw * 0.6, true)
	# reflet coloré (liseré) sur l'arrière du crâne
	ci.draw_polyline(PackedVector2Array([Vector2(-8.0, -100.5), Vector2(-7.2, -104.5), Vector2(-4.5, -108.6)]), Color(acc, 0.9), dw * 0.9, true)


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
	# pied nu de profil : talon arrondi, cheville, cou-de-pied, orteils
	var p := func(x: float, y: float) -> Vector2: return heel + Vector2(x * dir, y)
	var pts := [p.call(-3.6, -4.6), p.call(2.6, -4.8), p.call(6.2, -2.8), p.call(10.6, -1.6), p.call(12.6, -0.6),
		p.call(12.8, 1.4), p.call(-3.2, 1.4), p.call(-5.0, 0.2), p.call(-4.8, -2.4)]
	_poly(ci, pts, col, 0.0)
	# ombre de la voûte plantaire
	_poly(ci, [p.call(-3.2, 1.4), p.call(12.8, 1.4), p.call(10, 0.4), p.call(2, 0.0)], col.darkened(0.25), 0.0)
	# orteils
	ci.draw_line(p.call(10.4, -1.2), p.call(10.6, 1.0), col.darkened(0.3), ow * 0.6, true)
	ci.draw_line(p.call(8.4, -1.8), p.call(8.6, 0.6), col.darkened(0.3), ow * 0.5, true)
	_outline(ci, pts, ow)


static func _poly(ci: CanvasItem, pts: Array, col: Color, outline_w: float) -> void:
	ci.draw_colored_polygon(PackedVector2Array(pts), col)
	if outline_w > 0.0:
		_outline(ci, pts, outline_w)


static func _outline(ci: CanvasItem, pts: Array, wdt: float) -> void:
	var p := PackedVector2Array(pts)
	p.append(pts[0])
	ci.draw_polyline(p, Style.INK, wdt, true)


# =============================================================================
# Figures articulées (poses au sol)
# =============================================================================
# Une pose = positions locales des articulations (unités de jeu, sol en y = 0,
# avant = +x) : hip, neck, head, knee_b, foot_b, knee_f, foot_f,
# elbow_b, hand_b, elbow_f, hand_f. Le suffixe _b = membre arrière (dessiné derrière).

const HEAD_CENTER := Vector2(1, -98)  # centre de la tête dans le repère « debout »


static func draw_figure(ci: CanvasItem, xf: Transform2D, pal: Dictionary, j: Dictionary, grip: float = -1.0) -> void:
	var sc := maxf(0.5, absf(xf.get_scale().y))
	var ow := 4.2 / sc
	var dw := 2.6 / sc
	var k := absf(xf.get_scale().y)
	# --- membres arrière
	ci.draw_set_transform_matrix(xf)
	_limb(ci, [j.hip + Vector2(-3, 0), j.knee_b, j.foot_b], 12.0, pal.gi_shade, ow)
	_foot_at(ci, j.knee_b, j.foot_b, pal.skin_shade, dw * 1.3)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	var shoulder_b: Vector2 = j.neck + (j.hip - j.neck).normalized() * 6.0
	draw_arm(ci, xf * shoulder_b, xf * j.hand_b, pal, true, k, -1.0, xf * j.elbow_b)
	# --- jambe avant, buste, ceinture, tête
	ci.draw_set_transform_matrix(xf)
	_limb(ci, [j.hip + Vector2(3, 0), j.knee_f, j.foot_f], 12.5, pal.gi, ow)
	_foot_at(ci, j.knee_f, j.foot_f, pal.skin, dw * 1.3)
	var u: Vector2 = (j.neck - j.hip).normalized()
	var n := Vector2(-u.y, u.x)
	var skirt: Vector2 = j.hip - u * 8.0
	var torso := [j.neck + n * 16.0, j.neck - n * 16.0, j.hip - n * 13.0, skirt - n * 16.0, skirt + n * 16.0, j.hip + n * 13.0]
	_poly(ci, torso, pal.gi, 0.0)
	# ombre propre : moitié du buste
	_poly(ci, [j.neck + n * 16.0, j.neck + n * 3.0, j.hip + n * 2.0, skirt + n * 2.0, skirt + n * 16.0, j.hip + n * 13.0], pal.gi_shade, 0.0)
	# revers
	ci.draw_line(j.neck - n * 2.0, j.hip - n * 6.0 + u * 4.0, pal.gi_deep, 3.6)
	_outline(ci, torso, ow)
	# ceinture
	var b0: Vector2 = j.hip + u * 2.0
	var belt := [b0 + n * 14.0, b0 - n * 14.0, b0 - n * 14.0 - u * 6.0, b0 + n * 14.0 - u * 6.0]
	_poly(ci, belt, Color("17141f"), 0.0)
	# tête orientée selon l'axe cou → tête
	var hd: Vector2 = j.head - j.neck
	var ang := hd.angle() + PI * 0.5
	ci.draw_set_transform_matrix(xf * Transform2D(ang, j.head) * Transform2D(0.0, -HEAD_CENTER))
	_draw_head(ci, pal, ow, dw)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	# --- bras avant
	var shoulder_f: Vector2 = j.neck + (j.hip - j.neck).normalized() * 5.0
	draw_arm(ci, xf * shoulder_f, xf * j.hand_f, pal, false, k, grip, xf * j.elbow_f)


static func _foot_at(ci: CanvasItem, knee: Vector2, foot: Vector2, col: Color, ow: float) -> void:
	# pied orienté perpendiculairement au tibia, orteils vers l'avant du tibia
	var shin: Vector2 = (foot - knee).normalized()
	var dir := 1.0 if shin.x <= 0.35 else -1.0
	if absf(shin.y) < 0.5:
		dir = 1.0 if shin.x > 0 else -1.0
	_foot(ci, foot, dir, col, ow)


## Poses au sol, dans un repère où tori est à gauche (+x vers la tête d'uke).
## kind : "transition", "osaekomi:<id>", "kansetsu:<id>", "shime:<id>".
## t : temps (ticks) pour une légère respiration / lutte ; ctrl : contrôle 0..1.
static func ground_poses(kind: String, t: int, ctrl: float) -> Array:
	var w := sin(t * 0.18) * 1.5          # petite lutte
	var push := (1.0 - ctrl) * 6.0         # uke repousse plus quand il a l'avantage
	# uke allongé sur le dos, tête vers +x, genoux levés
	var uke := {
		"hip": Vector2(0, -9), "neck": Vector2(34, -10), "head": Vector2(46, -12),
		"knee_b": Vector2(-12, -27), "foot_b": Vector2(-26, -3),
		"knee_f": Vector2(-16, -29 + w), "foot_f": Vector2(-31, -4),
		"elbow_b": Vector2(42, -3), "hand_b": Vector2(54, -6),
		"elbow_f": Vector2(30, -26 - push), "hand_f": Vector2(22, -40 - push + w),
	}
	var tori := {}
	var id := kind.split(":")[1] if kind.contains(":") else ""
	match id:
		"yoko_shiho_gatame":
			# à genoux sur le côté, buste en travers du buste d'uke
			tori = {"hip": Vector2(4, -27), "neck": Vector2(32, -30 + w), "head": Vector2(42, -28 + w),
				"knee_b": Vector2(-6, -4), "foot_b": Vector2(-24, -2), "knee_f": Vector2(4, -4), "foot_f": Vector2(-14, -2),
				"elbow_b": Vector2(46, -16), "hand_b": Vector2(50, -6), "elbow_f": Vector2(18, -18), "hand_f": Vector2(4, -12)}
		"kami_shiho_gatame":
			# au-dessus de la tête d'uke, buste sur son buste, mains à la ceinture
			tori = {"hip": Vector2(74, -24), "neck": Vector2(46, -27 + w), "head": Vector2(36, -26 + w),
				"knee_b": Vector2(72, -4), "foot_b": Vector2(90, -2), "knee_f": Vector2(64, -4), "foot_f": Vector2(82, -2),
				"elbow_b": Vector2(26, -22), "hand_b": Vector2(8, -16), "elbow_f": Vector2(24, -18), "hand_f": Vector2(6, -12), "center": 30.0}
		"juji_gatame":
			# tori sur le dos au-delà de la tête d'uke, jambes repliées sur son buste,
			# bras d'uke tendu à la verticale entre ses jambes
			uke.elbow_f = Vector2(42, -30)
			uke.hand_f = Vector2(50, -48 + w)
			tori = {"hip": Vector2(60, -9), "neck": Vector2(90, -9), "head": Vector2(102, -11),
				"knee_b": Vector2(46, -32), "foot_b": Vector2(28, -20), "knee_f": Vector2(48, -36 + w), "foot_f": Vector2(30, -26),
				"elbow_b": Vector2(70, -28), "hand_b": Vector2(54, -44 + w), "elbow_f": Vector2(72, -24), "hand_f": Vector2(56, -40 + w),
				"center": 36.0}
		"okuri_eri_jime", "sankaku_jime":
			# derrière la tête d'uke, buste relevé, mains au col
			tori = {"hip": Vector2(70, -24), "neck": Vector2(60, -54 + w), "head": Vector2(58, -66 + w),
				"knee_b": Vector2(72, -4), "foot_b": Vector2(88, -2), "knee_f": Vector2(62, -4), "foot_f": Vector2(80, -2),
				"elbow_b": Vector2(50, -36), "hand_b": Vector2(42, -18), "elbow_f": Vector2(48, -30), "hand_f": Vector2(40, -14), "center": 30.0}
		"kesa_gatame":
			# assis à côté d'uke, jambes écartées, bras autour de la tête, tient le bras d'uke
			uke.elbow_f = Vector2(24, -24)
			uke.hand_f = Vector2(14, -34 - push + w)
			tori = {"hip": Vector2(8, -17), "neck": Vector2(28, -44 + w), "head": Vector2(35, -55 + w),
				"knee_b": Vector2(-8, -10), "foot_b": Vector2(-26, -2), "knee_f": Vector2(22, -8), "foot_f": Vector2(8, -1),
				"elbow_b": Vector2(50, -30), "hand_b": Vector2(56, -12), "elbow_f": Vector2(20, -30), "hand_f": Vector2(14, -30 - push + w),
				"center": 14.0}
		_:
			# transition : à genoux à côté d'uke, buste penché, mains au col et à la manche
			tori = {"hip": Vector2(-8, -26), "neck": Vector2(16, -50 + w), "head": Vector2(24, -60 + w),
				"knee_b": Vector2(-6, -4), "foot_b": Vector2(-24, -2), "knee_f": Vector2(4, -4), "foot_f": Vector2(-14, -2),
				"elbow_b": Vector2(30, -30), "hand_b": Vector2(34, -14), "elbow_f": Vector2(20, -28), "hand_f": Vector2(24, -16)}
	return [tori, uke]
