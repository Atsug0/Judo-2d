extends RefCounted
## Chorégraphies des projections, par images clés, pour tori et uke.
##
## Repère : celui de tori au départ de la technique (pieds de tori à l'origine,
## +x vers uke, unités de jeu, sol en y = 0). Chaque acteur a, à chaque clé :
##   pos  : position de son bassin dans ce repère
##   rot  : rotation du corps entier autour du bassin (+ = sens horaire à l'écran)
##   face : +1 regarde vers +x, -1 regarde vers -x
##   pose : pose locale « debout » (voir fighter_art.gd)
## Le début (p < 0.3) correspond à l'entrée (tsukuri), la suite à la projection (kake).
##
## Familles :
##   hanche  : seoi-nage, o-goshi, harai-goshi, uchi-mata, tai-otoshi (tori se retourne, uke passe par-dessus)
##   fauche  : o-soto-gari, o-uchi-gari, ko-uchi-gari (tori fauche, uke tombe en arrière)
##   balaye  : de-ashi-barai, sasae-tsurikomi-ashi (pieds d'uke balayés, chute sur place)
##   sacrifice : tomoe-nage, sumi-gaeshi (tori tombe, uke passe par-dessus sa tête)

const Art := preload("res://scripts/view/fighter_art.gd")

const FAMILY := {
	"seoi_nage": "hanche", "ippon_seoi_nage": "hanche", "o_goshi": "hanche", "harai_goshi": "hanche",
	"uchi_mata": "hanche", "tai_otoshi": "hanche", "utsuri_goshi": "hanche", "uchi_mata_sukashi": "hanche",
	"o_soto_gari": "fauche", "o_uchi_gari": "fauche", "ko_uchi_gari": "fauche", "o_soto_gaeshi": "fauche",
	"de_ashi_barai": "balaye", "sasae_tsurikomi_ashi": "balaye", "tsubame_gaeshi": "balaye",
	"tomoe_nage": "sacrifice", "sumi_gaeshi": "sacrifice", "ura_nage": "sacrifice",
}
## Fraction de l'animation qui correspond à l'entrée (avant la résolution).
const ENTRY := 0.3


static func family(tech: String) -> String:
	return FAMILY.get(tech, "hanche")


static func _p(hip: Vector2, bow: float, fb: Vector2, ff: Vector2, hb: Vector2, hf: Vector2, tilt: float = 0.0) -> Dictionary:
	return {"hip": hip, "bow": bow, "fb": fb, "ff": ff, "hb": hb, "hf": hf, "tilt": tilt}


static func _actor(pos: Vector2, rot: float, face: int, pose: Dictionary) -> Dictionary:
	return {"pos": pos, "rot": rot, "face": face, "pose": pose}


## Images clés d'une technique. d = distance initiale entre les pieds (unités).
static func keys(tech: String, d: float) -> Array:
	var stand = Art.pose_stand(0.5)
	var uke_stand = Art.pose_stand(0.4)
	var lying = _p(Vector2(0, -47), 0.0, Vector2(-8, -6), Vector2(10, -8), Vector2(10, -44), Vector2(24, -64), 0.2)
	var k0 = {"p": 0.0, "tori": _actor(Vector2(0, -47), 0.0, 1, stand), "uke": _actor(Vector2(d, -47), 0.0, -1, uke_stand)}
	match family(tech):
		"fauche":
			return _keys_fauche(tech, d, k0, lying)
		"balaye":
			return _keys_balaye(tech, d, k0, lying)
		"sacrifice":
			return _keys_sacrifice(tech, d, k0, lying)
	return _keys_hanche(tech, d, k0, lying)


static func _keys_hanche(tech: String, d: float, k0: Dictionary, lying: Dictionary) -> Array:
	var sweep = tech in ["uchi_mata", "harai_goshi", "uchi_mata_sukashi"]
	var block = tech == "tai_otoshi"
	var deep = tech in ["seoi_nage", "ippon_seoi_nage"]
	var crouch_hip = -34.0 if deep else (-38.0 if not block else -40.0)
	# entrée : tori se retourne, dos contre uke, et descend sous son centre de gravité
	var t1 = _p(Vector2(0, crouch_hip), 0.35, Vector2(-11, -4), Vector2(12, -4), Vector2(16, -52), Vector2(12, -64))
	if block:
		t1 = _p(Vector2(0, -40), 0.25, Vector2(-30, -6), Vector2(12, -4), Vector2(16, -52), Vector2(12, -64))
	var u1 = _p(Vector2(0, -50), 0.18, Vector2(-12, -6), Vector2(10, -3), Vector2(24, -62), Vector2(28, -70))
	# chargement : tori s'incline profondément, uke décolle par-dessus son dos
	var t2 = _p(Vector2(0, crouch_hip - 2), 1.0 if deep else 0.85, Vector2(-12, -4), Vector2(14, -4), Vector2(14, -38), Vector2(8, -50))
	if sweep:
		t2 = _p(Vector2(0, -44), 1.05, Vector2(-30, -48), Vector2(12, -4), Vector2(14, -38), Vector2(8, -50))
	elif block:
		t2 = _p(Vector2(0, -42), 0.75, Vector2(-34, -6), Vector2(12, -4), Vector2(14, -40), Vector2(8, -52))
	var u2 = _p(Vector2(0, -47), 0.25, Vector2(-22, -16), Vector2(12, -12), Vector2(26, -70), Vector2(20, -60), -0.3)
	var t3 = t2.duplicate()
	t3.bow = 1.2 if not block else 0.9
	if sweep:
		t3.fb = Vector2(-34, -74)
	var u3 = _p(Vector2(0, -47), 0.1, Vector2(-18, -2), Vector2(10, -8), Vector2(28, -60), Vector2(16, -78), -0.4)
	var t4 = _p(Vector2(0, -44), 0.45, Vector2(-14, -4), Vector2(14, -4), Vector2(18, -40), Vector2(10, -52))
	var lift = 112.0 if deep else 104.0
	return [
		k0,
		{"p": ENTRY, "tori": _actor(Vector2(d * 0.55, crouch_hip), 0.0, -1, t1), "uke": _actor(Vector2(d * 0.82, -50), -0.45, -1, u1)},
		{"p": 0.55, "tori": _actor(Vector2(d * 0.5, crouch_hip - 2), 0.0, -1, t2), "uke": _actor(Vector2(d * 0.42, -lift), -1.55, -1, u2)},
		{"p": 0.78, "tori": _actor(Vector2(d * 0.47, crouch_hip - 2), 0.0, -1, t3), "uke": _actor(Vector2(d * 0.08, -92), -2.6, -1, u3)},
		{"p": 1.0, "tori": _actor(Vector2(d * 0.5, -44), 0.0, -1, t4), "uke": _actor(Vector2(d * 0.5 - 50, -9), -4.71, -1, lying)},
	]


static func _keys_fauche(tech: String, d: float, k0: Dictionary, lying: Dictionary) -> Array:
	var high = tech in ["o_soto_gari", "o_soto_gaeshi"]
	var inner = tech == "o_uchi_gari"
	# entrée : tori avance en poussant, uke part en arrière sur les talons
	var t1 = _p(Vector2(0, -46), 0.25, Vector2(-10, -4), Vector2(16, -4), Vector2(26, -60), Vector2(30, -70))
	var u1 = _p(Vector2(0, -48), -0.15, Vector2(-14, -4), Vector2(12, -6), Vector2(22, -60), Vector2(26, -68), 0.15)
	# fauchage : la jambe arrière de tori passe derrière celle d'uke
	var reap = Vector2(38, -38) if high else (Vector2(32, -14) if inner else Vector2(36, -5))
	var t2 = _p(Vector2(0, -46), 0.55 if high else 0.4, reap, Vector2(14, -4), Vector2(26, -56), Vector2(30, -66))
	var u2 = _p(Vector2(0, -47), -0.25, Vector2(-14, -6), Vector2(22, -30 if high else -16), Vector2(24, -70), Vector2(30, -78), 0.25)
	var t3 = t2.duplicate()
	t3.fb = Vector2(30, -62) if high else reap + Vector2(4, -6)
	t3.bow = 0.85 if high else 0.55
	var u3 = _p(Vector2(0, -47), -0.1, Vector2(-8, -16), Vector2(18, -38), Vector2(20, -80), Vector2(30, -82), 0.3)
	var t4 = _p(Vector2(0, -44), 0.5, Vector2(10, -10), Vector2(14, -4), Vector2(24, -42), Vector2(28, -52))
	var lift = 1.0 if high else 0.75
	return [
		k0,
		{"p": ENTRY, "tori": _actor(Vector2(d * 0.38, -46), 0.0, 1, t1), "uke": _actor(Vector2(d * 1.0, -48), 0.3, -1, u1)},
		{"p": 0.55, "tori": _actor(Vector2(d * 0.45, -46), 0.0, 1, t2), "uke": _actor(Vector2(d * 1.02, -50 - 6 * lift), 0.8, -1, u2)},
		{"p": 0.78, "tori": _actor(Vector2(d * 0.5, -46), 0.0, 1, t3), "uke": _actor(Vector2(d * 1.12, -30 - 8 * lift), 1.3, -1, u3)},
		{"p": 1.0, "tori": _actor(Vector2(d * 0.6, -44), 0.0, 1, t4), "uke": _actor(Vector2(d * 1.0 + 20, -9), PI / 2, -1, lying)},
	]


static func _keys_balaye(tech: String, d: float, k0: Dictionary, lying: Dictionary) -> Array:
	# tori reste droit et balaie le pied avancé d'uke en tirant vers le haut
	var t1 = _p(Vector2(0, -47), -0.05, Vector2(-12, -4), Vector2(14, -4), Vector2(28, -66), Vector2(32, -76))
	var u1 = uke_step()
	var t2 = _p(Vector2(0, -47), -0.15, Vector2(d * 0.55, -8), Vector2(10, -4), Vector2(26, -76), Vector2(30, -86))
	var u2 = _p(Vector2(0, -47), -0.2, Vector2(-6, -24), Vector2(24, -34), Vector2(22, -74), Vector2(26, -80), 0.2)
	var t3 = t2.duplicate()
	t3.fb = Vector2(d * 0.6, -14)
	var u3 = _p(Vector2(0, -47), -0.1, Vector2(4, -30), Vector2(26, -40), Vector2(18, -80), Vector2(28, -84), 0.3)
	var t4 = _p(Vector2(0, -46), 0.2, Vector2(-8, -4), Vector2(14, -4), Vector2(26, -46), Vector2(30, -56))
	return [
		k0,
		{"p": ENTRY, "tori": _actor(Vector2(d * 0.25, -47), 0.0, 1, t1), "uke": _actor(Vector2(d * 0.95, -48), -0.1, -1, u1)},
		{"p": 0.55, "tori": _actor(Vector2(d * 0.3, -47), 0.0, 1, t2), "uke": _actor(Vector2(d * 0.95, -58), 0.9, -1, u2)},
		{"p": 0.78, "tori": _actor(Vector2(d * 0.32, -47), 0.0, 1, t3), "uke": _actor(Vector2(d * 0.98, -36), 1.35, -1, u3)},
		{"p": 1.0, "tori": _actor(Vector2(d * 0.35, -46), 0.0, 1, t4), "uke": _actor(Vector2(d * 0.98 + 10, -9), PI / 2, -1, lying)},
	]


## Uke avance le pied (cible du balayage).
static func uke_step() -> Dictionary:
	return _p(Vector2(0, -48), 0.05, Vector2(-14, -4), Vector2(18, -4), Vector2(24, -62), Vector2(28, -70))


static func _keys_sacrifice(tech: String, d: float, k0: Dictionary, lying: Dictionary) -> Array:
	# tori s'assoit en arrière, le pied dans le ventre d'uke, et roule sur le dos
	var t1 = _p(Vector2(0, -47), -0.2, Vector2(-14, -10), Vector2(42, -10), Vector2(26, -62), Vector2(30, -70), 0.2)
	var u1 = _p(Vector2(0, -50), 0.25, Vector2(-14, -4), Vector2(10, -4), Vector2(24, -60), Vector2(28, -68), -0.1)
	var t2 = _p(Vector2(0, -47), -0.1, Vector2(16, -10), Vector2(44, -8), Vector2(26, -74), Vector2(30, -82), 0.3)
	var u2 = _p(Vector2(0, -47), 0.3, Vector2(-22, -14), Vector2(10, -14), Vector2(26, -66), Vector2(18, -58), -0.3)
	var t3 = t2.duplicate()
	t3.ff = Vector2(38, -26)
	var u3 = _p(Vector2(0, -47), 0.1, Vector2(-16, -4), Vector2(12, -8), Vector2(28, -60), Vector2(16, -76), -0.4)
	var t4 = _p(Vector2(0, -47), 0.0, Vector2(30, -8), Vector2(40, -14), Vector2(18, -60), Vector2(26, -70), 0.3)
	return [
		k0,
		{"p": ENTRY, "tori": _actor(Vector2(d * 0.25, -30), -0.55, 1, t1), "uke": _actor(Vector2(d * 0.85, -50), -0.4, -1, u1)},
		{"p": 0.55, "tori": _actor(Vector2(d * 0.15, -11), -1.45, 1, t2), "uke": _actor(Vector2(d * 0.12, -108), -1.7, -1, u2)},
		{"p": 0.78, "tori": _actor(Vector2(d * 0.1, -11), -1.5, 1, t3), "uke": _actor(Vector2(-d * 0.45, -76), -3.0, -1, u3)},
		{"p": 1.0, "tori": _actor(Vector2(d * 0.1, -11), -1.5, 1, t4), "uke": _actor(Vector2(-d * 0.8, -9), -4.71, -1, lying)},
	]


## Échantillonne les clés à l'avancement p (0..1). Renvoie {tori: acteur, uke: acteur}.
static func sample(ks: Array, p: float) -> Dictionary:
	p = clampf(p, 0.0, 1.0)
	var a: Dictionary = ks[0]
	var b: Dictionary = ks[ks.size() - 1]
	for i in ks.size() - 1:
		if p >= ks[i].p and p <= ks[i + 1].p:
			a = ks[i]
			b = ks[i + 1]
			break
	var span: float = maxf(0.0001, b.p - a.p)
	var t: float = (p - a.p) / span
	t = t * t * (3.0 - 2.0 * t)
	var out = {}
	for who in ["tori", "uke"]:
		var x: Dictionary = a[who]
		var y: Dictionary = b[who]
		out[who] = {"pos": x.pos.lerp(y.pos, t), "rot": lerpf(x.rot, y.rot, t),
			"face": x.face if t < 0.5 else y.face, "pose": Art.lerp_pose(x.pose, y.pose, t)}
	return out


## Transformation écran d'un acteur. frame : repère de tori (écran), mis à l'échelle.
static func actor_xform(frame: Transform2D, actor: Dictionary) -> Transform2D:
	var hip: Vector2 = actor.pose.get("hip", Art.HIP0)
	return frame * Transform2D(actor.rot, actor.pos) * Transform2D(0.0, Vector2(actor.face, 1), 0.0, Vector2.ZERO) * Transform2D(0.0, -hip)
