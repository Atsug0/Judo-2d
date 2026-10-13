extends RefCounted
## Judokas dessinés par découpage (« cut-out ») : les morceaux de l'artwork (tête, buste, bras,
## avant-bras, mains, cuisses, tibias, pieds), découpés par tools/cutout/cut_parts.py dans
## assets/cutout/<judoka>/, sont posés entre les articulations du squelette 2D du jeu
## (fighter_art.gd) : garde, kumikata, projections, chorégraphies filmées et ne-waza.
## Chaque morceau est dessiné de profil tourné vers +x ; le repère xf du judoka gère le sens.

const DIR := "res://assets/cutout"
const HIP0 := Vector2(0, -47)
const NECK0 := Vector2(1, -86)
const HEAD_CENTER := Vector2(1, -98)
const ARM_K := 1.18                    # bras un peu plus longs : l'épaule du dessin est plus en arrière
const FAR_TINT := Color(0.74, 0.74, 0.84)
const FAR_SHOULDER := Vector2(6, -1)   # épaule du bras loin de la caméra (décalée vers l'avant)
const WRIST_BACK := 3.4                # poing (point de la main du jeu) → poignet
# copies de fighter_art.gd (pas de préchargement croisé entre les deux scripts)
const REST_HANDS := [Vector2(22, -57), Vector2(29, -65)]
const THIGH := 23.5
const SHIN := 21.5


static func _ik_knee(hip: Vector2, foot: Vector2) -> Vector2:
	var d := foot - hip
	var dist := clampf(d.length(), 1.0, THIGH + SHIN - 0.01)
	var a := acos(clampf((THIGH * THIGH + dist * dist - SHIN * SHIN) / (2.0 * THIGH * dist), -1.0, 1.0))
	var k1 := hip + Vector2.from_angle(d.angle() + a) * THIGH
	var k2 := hip + Vector2.from_angle(d.angle() - a) * THIGH
	return k1 if k1.x > k2.x else k2

static var _sets := {}


## Morceaux d'un judoka ({} si absent) : nom → {tex, A, B, sl/sw ou scale, points}.
static func parts(who: String) -> Dictionary:
	if _sets.has(who):
		return _sets[who]
	var out := {}
	var base := DIR + "/" + who + "/"
	if FileAccess.file_exists(base + "parts.json"):
		var meta = JSON.parse_string(FileAccess.open(base + "parts.json", FileAccess.READ).get_as_text())
		for name in meta.parts:
			var m: Dictionary = meta.parts[name]
			var path: String = base + String(m.file)
			var tex: Texture2D = null
			if ResourceLoader.exists(path):
				tex = load(path)
			if tex == null:
				var img := Image.load_from_file(ProjectSettings.globalize_path(path))
				if img != null:
					tex = ImageTexture.create_from_image(img)
			if tex == null:
				continue
			var p := {"tex": tex, "A": Vector2(m.A[0], m.A[1]), "B": Vector2(m.B[0], m.B[1])}
			if m.has("scale"):
				p.scale = float(m.scale)
			if m.has("wpx"):
				p.sw = float(m.wu) / float(m.wpx)
			var pts := {}
			for k in m.get("points", {}):
				pts[k] = Vector2(m.points[k][0], m.points[k][1])
			p.points = pts
			out[name] = p
	_sets[who] = out
	return out


static var _off := -1


## Judoka découpé disponible pour cette palette ? (--dessin : judokas vectoriels d'origine)
static func has(pal: Dictionary) -> bool:
	if _off < 0:
		_off = 1 if OS.get_cmdline_user_args().has("--dessin") else 0
	return _off == 0 and pal.has("cutout") and not parts(String(pal.cutout)).is_empty()


## Transformation d'un morceau : son articulation A va en P, son axe A→B suit P→Q.
## Longueur ajustée à |PQ| (sauf échelle fixe), largeur à l'échelle du morceau ; flip : miroir.
static func _piece_xf(p: Dictionary, P: Vector2, Q: Vector2, flip: bool = false) -> Transform2D:
	var art: Vector2 = p.B - p.A
	var tgt := Q - P
	var sl: float
	var sw: float
	if p.has("scale"):
		sl = p.scale
		sw = p.scale
	else:
		sl = tgt.length() / maxf(art.length(), 0.001)
		sw = p.get("sw", sl)
	if flip:
		sw = -sw
	return Transform2D(tgt.angle(), P) * Transform2D(0.0, Vector2(sl, sw), 0.0, Vector2.ZERO) \
		* Transform2D(-art.angle(), Vector2.ZERO) * Transform2D(0.0, -p.A)


static func _draw(ci: CanvasItem, M: Transform2D, p: Dictionary, P: Vector2, Q: Vector2, tint: Color, flip: bool = false) -> void:
	ci.draw_set_transform_matrix(M * _piece_xf(p, P, Q, flip))
	ci.draw_texture(p.tex, Vector2.ZERO, tint)


## Épaule (repère « debout ») déduite de l'emmanchure du buste dessiné.
static func _shoulder_stand(ps: Dictionary) -> Vector2:
	var t: Dictionary = ps.torso
	if not t.points.has("shoulder"):
		return Vector2(-2, -76)
	return _piece_xf(t, HIP0, NECK0) * Vector2(t.points.shoulder)


## Bras : coude par IK (plié vers le bas), avant-bras, main (poing si prise), puis manche par-dessus.
static func _arm(ci: CanvasItem, M: Transform2D, ps: Dictionary, sh: Vector2, hand: Vector2, tint: Color, closed: bool, elbow_at = null) -> Vector2:
	var l1 := 20.0 * ARM_K
	var l2 := 21.5 * ARM_K
	var d := hand - sh
	var dl := d.length()
	if dl > (l1 + l2) * 0.999:
		hand = sh + d / maxf(dl, 0.001) * (l1 + l2) * 0.999
		d = hand - sh
		dl = d.length()
	var elbow: Vector2
	if elbow_at != null:
		elbow = elbow_at
	else:
		var dirv := d / maxf(dl, 0.001)
		var c := clampf((l1 * l1 + dl * dl - l2 * l2) / (2.0 * l1 * maxf(dl, 0.001)), -1.0, 1.0)
		var e1 := sh + dirv.rotated(acos(c)) * l1
		var e2 := sh + dirv.rotated(-acos(c)) * l1
		elbow = e1 if e1.y > e2.y else e2
	var u2 := (hand - elbow).normalized()
	var wrist := hand - u2 * WRIST_BACK
	if closed and ps.has("fist") and ps.has("forearm"):
		_draw(ci, M, ps.forearm, elbow, wrist, tint)
		_draw(ci, M, ps.fist, wrist, wrist + u2, tint)
	elif ps.has("forearm_open"):
		_draw(ci, M, ps.forearm_open, elbow, wrist, tint)
	_draw(ci, M, ps.upper_arm, sh, elbow, tint)
	return hand


## Jambe : pied (à plat, tourné comme le tibia s'écarte de sa position de garde), tibia, cuisse.
static func _leg(ci: CanvasItem, M: Transform2D, ps: Dictionary, hip: Vector2, knee: Vector2, foot: Vector2, tint: Color, foot_dir: Vector2) -> void:
	_draw(ci, M, ps.foot, foot, foot + foot_dir, tint, foot_dir.x < 0.0)
	_draw(ci, M, ps.shin, knee, foot, tint)
	_draw(ci, M, ps.thigh, hip, knee, tint)


## Jupe de la veste (sous la ceinture) : entre l'axe du buste et celui des cuisses, pour
## qu'elle tombe sur les jambes au lieu de rester raide quand le buste se penche.
static func _skirt(ci: CanvasItem, M: Transform2D, ps: Dictionary, hip: Vector2, torso_down: Vector2, thighs: Vector2) -> void:
	if not ps.has("skirt"):
		return
	var d := torso_down.normalized() * 0.45 + thighs.normalized() * 0.55
	if d.length() < 0.01:
		d = torso_down
	_draw(ci, M, ps.skirt, hip, hip + d.normalized(), Color.WHITE)


static func _grip_ring(ci: CanvasItem, M: Transform2D, hand: Vector2, strength: float) -> void:
	if strength < 0.0 or strength > 1.0:
		return  # > 1 : main fermée sans indicateur (projection)
	const Style := preload("res://scripts/ui/style.gd")
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	var k := absf(M.get_scale().y)
	var c := Style.GOOD.lerp(Style.DANGER, clampf(strength, 0.0, 1.0))
	ci.draw_arc(M * hand, 6.2 * k, 0, TAU, 24, c, 3.0, true)


## Judoka debout / projeté. Mêmes paramètres que fighter_art.draw_fighter.
static func draw_stand(ci: CanvasItem, xf: Transform2D, pal: Dictionary, pose: Dictionary,
		hands_world: Array = [], grip: Array = [-1.0, -1.0], shin_rest: Array = [1.986, 1.561]) -> void:
	var ps := parts(String(pal.cutout))
	var hip: Vector2 = pose.get("hip", HIP0)
	var bow := float(pose.get("bow", 0.0))
	var tl := Transform2D(bow, hip) * Transform2D(0.0, -HIP0)
	var att_b := tl * Vector2(-4, -47)
	var att_f := tl * Vector2(4, -47)
	var fb: Vector2 = pose.fb
	var ff: Vector2 = pose.ff
	var kb: Vector2 = pose.kb if pose.has("kb") else _ik_knee(att_b, fb)
	var kf: Vector2 = pose.kf if pose.has("kf") else _ik_knee(att_f, ff)
	var inv := xf.affine_inverse()
	var hb: Vector2 = inv * Vector2(hands_world[0]) if hands_world.size() > 0 and hands_world[0] != null else pose.get("hb", REST_HANDS[0])
	var hf: Vector2 = inv * Vector2(hands_world[1]) if hands_world.size() > 1 and hands_world[1] != null else pose.get("hf", REST_HANDS[1])
	var sh0 := _shoulder_stand(ps)
	var sh_f := tl * sh0
	var sh_b := tl * (sh0 + FAR_SHOULDER)
	var fist := pose.has("fist") and float(pose.fist) > 0.5
	var white := Color.WHITE
	# bras loin, jambes (loin puis près), tête, buste, bras près
	var hb2 := _arm(ci, xf, ps, sh_b, hb, FAR_TINT, fist or grip[0] >= 0.0)
	for leg in [[att_b, kb, fb, shin_rest[0], FAR_TINT], [att_f, kf, ff, shin_rest[1], white]]:
		var dev: float = (leg[2] - leg[1]).angle() - float(leg[3])
		_leg(ci, xf, ps, leg[0], leg[1], leg[2], leg[4], Vector2.RIGHT.rotated(dev))
	_skirt(ci, xf, ps, hip, Vector2.DOWN.rotated(bow), (kb - att_b).normalized() + (kf - att_f).normalized())
	var neck := tl * NECK0
	var hd := (HEAD_CENTER - NECK0).rotated(bow + float(pose.get("tilt", 0.0)))
	_draw(ci, xf, ps.head, neck, neck + hd, white)
	_draw(ci, xf, ps.torso, hip, neck, white)
	var hf2 := _arm(ci, xf, ps, sh_f, hf, white, fist or grip[1] >= 0.0)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	_grip_ring(ci, xf, hb2, grip[0])
	_grip_ring(ci, xf, hf2, grip[1])


## Judoka au sol : articulations de fighter_art.ground_poses (hip, neck, head, genoux, pieds, coudes, mains).
static func draw_ground(ci: CanvasItem, xf: Transform2D, pal: Dictionary, j: Dictionary, grip: float = -1.0) -> void:
	var ps := parts(String(pal.cutout))
	var hip: Vector2 = j.hip
	var neck: Vector2 = j.neck
	var u := (neck - hip).normalized()
	var white := Color.WHITE
	# épaules : le long du buste, comme le buste dessiné les place debout
	var sh0 := _shoulder_stand(ps)
	var tor := Transform2D(u.angle() + PI * 0.5, hip) * Transform2D(0.0, -HIP0)
	var sh_f := tor * sh0
	var sh_b := tor * (sh0 + FAR_SHOULDER)
	_arm(ci, xf, ps, sh_b, j.hand_b, FAR_TINT, true, j.elbow_b)
	for leg in [[hip + u.orthogonal() * 2.0, j.knee_b, j.foot_b, FAR_TINT], [hip - u.orthogonal() * 2.0, j.knee_f, j.foot_f, white]]:
		var shin: Vector2 = (leg[2] - leg[1]).normalized()
		var toes := Vector2(1, 0) if shin.x <= 0.35 else Vector2(-1, 0)
		if absf(shin.y) < 0.5:
			toes = Vector2(signf(shin.x) if shin.x != 0.0 else 1.0, 0)
		_leg(ci, xf, ps, leg[0], leg[1], leg[2], leg[3], toes)
	_skirt(ci, xf, ps, hip, -u, (Vector2(j.knee_b) - hip).normalized() + (Vector2(j.knee_f) - hip).normalized())
	var hd: Vector2 = j.head - neck
	_draw(ci, xf, ps.head, neck, neck + hd, white)
	_draw(ci, xf, ps.torso, hip, neck, white)
	var hand := _arm(ci, xf, ps, sh_f, j.hand_f, white, true, j.elbow_f)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	_grip_ring(ci, xf, hand, grip)


## Portrait (tête dessinée) dans un cadre, pour les vignettes. Renvoie false si indisponible.
static func draw_bust(ci: CanvasItem, rect: Rect2, pal: Dictionary) -> bool:
	if not has(pal):
		return false
	var head: Dictionary = parts(String(pal.cutout)).head
	var tex: Texture2D = head.tex
	var r := rect.grow(-2.0)
	var k := minf(r.size.x / tex.get_width(), r.size.y / tex.get_height()) * 1.12
	var size := Vector2(tex.get_width(), tex.get_height()) * k
	var pos := Vector2(r.position.x + (r.size.x - size.x) * 0.5, r.end.y - size.y)
	# recadré dans le cadre (le haut des cheveux peut dépasser : on coupe)
	var src := Rect2(Vector2.ZERO, Vector2(tex.get_width(), tex.get_height()))
	if pos.y < r.position.y:
		var cut := (r.position.y - pos.y) / k
		src.position.y += cut
		src.size.y -= cut
		size.y -= cut * k
		pos.y = r.position.y
	ci.draw_texture_rect_region(tex, Rect2(pos, size), src)
	return true
