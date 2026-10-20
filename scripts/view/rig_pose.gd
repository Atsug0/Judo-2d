extends RefCounted
## Pilotage d'un modèle 3D riggé (tools/rig/autorig.py) à partir d'articulations 3D
## « anatomiques » (bassin, cou, tête, hanches / genoux / pieds / épaules / coudes / mains
## gauche et droite), en mètres. Chaque os est orienté vers l'articulation suivante ; le
## bassin et la poitrine prennent aussi l'axe des hanches et des épaules (rotation du corps).
## Utilisé par le combat (scripts/view/models3d.gd) et l'outil de rendu (tools/rig/pose_model.gd).

const FLOOR_SOLE := 0.09   # cheville → plante du pied (m)
const BODY_CLEAR := 0.07   # axe du buste / sommet du crâne → tatami, au plus près (m)

var node: Node3D           # scène du modèle
var skel: Skeleton3D
var J := {}                # articulations au repos (modèle)
var bones := []            # [nom, tête, queue, parent, rayon]
var idx := {}
var parent_i := {}
# Saisies : dernière pose calculée (repère de la scène), pour que l'adversaire vienne
# poser ses mains sur ce judogi-ci (revers, manche, col, ceinture).
var last_G := {}
var last_O := {}
var posed := false
var chest_front := 0.13    # avant du buste à hauteur des revers, par rapport à l'axe (m, repos)
var neck_back := 0.07      # arrière du col
var belt_front := 0.13


## Charge un .glb riggé et ses articulations de repos ; texture : remplace la couleur
## de base (judogi bleu pour uke). Renvoie null si le fichier est illisible.
static func load_model(glb: String, joints_path: String, texture: String = "", toon: bool = false):
	var r = load("res://scripts/view/rig_pose.gd").new()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(glb, st) != OK:
		push_error("modèle 3D illisible : " + glb)
		return null
	r.node = doc.generate_scene(st)
	var sk = r.node.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		push_error("modèle 3D sans squelette : " + glb)
		return null
	r.skel = sk[0]
	var spec = JSON.parse_string(FileAccess.open(joints_path, FileAccess.READ).get_as_text())
	for k in spec.joints:
		var v = spec.joints[k]
		r.J[k] = Vector3(v[0], v[1], v[2])
	r.bones = spec.bones
	for i in r.bones.size():
		var b = r.bones[i]
		r.idx[b[0]] = r.skel.find_bone(b[0])
		for j in r.bones.size():
			if r.bones[j][0] == b[3]:
				r.parent_i[b[0]] = j
	r._measure()
	var tex: Texture2D = null
	if texture != "" and FileAccess.file_exists(texture):
		tex = ImageTexture.create_from_image(Image.load_from_file(texture))
	if tex != null or toon:
		for mi in r.node.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var m: StandardMaterial3D = mi.mesh.surface_get_material(s).duplicate()
				if tex != null:
					m.albedo_texture = tex
				if toon:
					_toon(m)
				mi.set_surface_override_material(s, m)
	return r


## Épaisseur du judogi, mesurée sur le maillage au repos : la main qui prend le revers se
## pose sur le tissu, pas dans l'axe du corps (un colosse n'a pas le buste d'une poids léger).
func _measure() -> void:
	var y_lapel: float = lerpf(J["poitrine"].y, J["cou"].y, 0.45)
	var y_col: float = J["cou"].y - 0.02
	var y_belt: float = J["bassin"].y + 0.06
	var cz: float = J["poitrine"].z
	var fr := -INF
	var bk := INF
	var bf := -INF
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			for v in arr[Mesh.ARRAY_VERTEX]:
				if absf(v.x - J["poitrine"].x) > 0.09:
					continue
				if absf(v.y - y_lapel) < 0.035:
					fr = maxf(fr, v.z)
				if absf(v.y - y_col) < 0.035:
					bk = minf(bk, v.z)
				if absf(v.y - y_belt) < 0.03:
					bf = maxf(bf, v.z)
	# garde-fous : maillage dans un autre repère que les articulations
	if fr > cz and fr - cz < 0.35:
		chest_front = fr - cz
	if bk < J["cou"].z and J["cou"].z - bk < 0.25:
		neck_back = J["cou"].z - bk
	if bf > J["bassin"].z and bf - J["bassin"].z < 0.35:
		belt_front = bf - J["bassin"].z


## Rendu « dessiné » : contour d'encre (coque inversée légèrement gonflée, dessinée par
## l'arrière), liseré lumineux, aucun reflet. L'éclairage reste **doux** : les aplats du
## cel-shading (DIFFUSE_TOON) écrasaient complètement le relief du judogi — plis, coutures,
## tissage — qui est tout l'intérêt des modèles. Le contour suffit à garder le trait.
static func _toon(m: StandardMaterial3D) -> void:
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.specular = 0.28          # peau et tissu accrochent un peu la lumière
	m.metallic = 0.0
	m.roughness = 0.72
	m.rim_enabled = true
	m.rim = 0.22
	m.rim_tint = 0.6
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color("0b0a14")
	ink.cull_mode = BaseMaterial3D.CULL_FRONT
	ink.grow = true
	ink.grow_amount = 0.007    # trait fin : il marque la silhouette sans écraser le modelé
	m.next_pass = ink


static func _basis_from(lateral: Vector3, up: Vector3) -> Basis:
	var y := up.normalized()
	var x := (lateral - y * lateral.dot(y))
	if x.length() < 1e-4:
		x = Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _arc(from: Vector3, to: Vector3) -> Basis:
	var f := from.normalized()
	var t := to.normalized()
	if f.dot(t) > 0.99999:
		return Basis()
	if f.dot(t) < -0.9999:
		var axis := f.cross(Vector3.RIGHT)
		if axis.length() < 0.01:
			axis = f.cross(Vector3.UP)
		return Basis(axis.normalized(), PI)
	return Basis(Quaternion(f, t))


## Repère d'un segment : axe Y = direction de l'os, axe X = normale du plan de flexion.
static func _seg(dir: Vector3, n: Vector3) -> Basis:
	return _basis_from(n, dir)


## Point d'une courbe de Bézier quadratique.
static func _bez(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)


## Normale du plan de flexion d'un membre (a → b → c). Membre tendu : on garde l'orientation
## de repos portée par le parent (fallback), sans vrille brutale.
static func _bend_normal(a: Vector3, b: Vector3, c: Vector3, fallback: Vector3) -> Vector3:
	var u := b - a
	var f := c - b
	var n := u.cross(f)
	var k := u.length() * f.length()
	if k < 1e-8:
		return fallback
	return n / k + fallback * 0.12


## Origines des os (cinématique directe) à partir des orientations globales G.
func _fk(G: Dictionary, root: Vector3) -> Dictionary:
	var o := {}
	for b in bones:
		var name: String = b[0]
		if b[3] == "":
			o[name] = root
		else:
			var pb = bones[parent_i[name]]
			o[name] = o[b[3]] + G[b[3]] * (J[b[1]] - J[pb[1]])
	return o


## Paume au repos : entre le poignet et les jointures, là où la main serre le tissu.
func _palm_rest(sd: String) -> Vector3:
	var w: Vector3 = J["poignet." + sd]
	return w + (J["jointure." + sd] - w) * 0.55 if J.has("jointure." + sd) else w


## Bras à deux segments vers une cible (paume), longueurs du modèle ; `pole` : coude voulu.
func _reach(G: Dictionary, O: Dictionary, sd: String, target: Vector3, pole: Vector3) -> void:
	var sh: Vector3 = O["upper_arm." + sd]
	var l1: float = (J["coude." + sd] - J["epaule." + sd]).length()
	var l2: float = (_palm_rest(sd) - J["coude." + sd]).length()
	var d := target - sh
	var dist := clampf(d.length(), absf(l1 - l2) + 0.02, l1 + l2 - 0.005)
	var u := d.normalized()
	var pv := pole - sh
	var perp := pv - u * pv.dot(u)
	if perp.length() < 1e-4:
		perp = Vector3.DOWN - u * Vector3.DOWN.dot(u)
	perp = perp.normalized()
	var a := (l1 * l1 + dist * dist - l2 * l2) / (2.0 * dist)
	var h := sqrt(maxf(0.0, l1 * l1 - a * a))
	var elbow := sh + u * a + perp * h
	var palm := sh + u * dist
	var sg := 1.0 if sd == "L" else -1.0
	var rest_n := Vector3(0, -sg, 0)
	var n := _bend_normal(sh, elbow, palm, G["chest"] * rest_n)
	G["upper_arm." + sd] = _seg(elbow - sh, n) * _seg(J["coude." + sd] - J["epaule." + sd], rest_n).inverse()
	G["forearm." + sd] = _seg(palm - elbow, n) * _seg(_palm_rest(sd) - J["coude." + sd], rest_n).inverse()
	G["hand." + sd] = G["forearm." + sd]


## Point de saisie sur ce judoka (dernière pose) : "lapel" (revers), "sleeve" (manche,
## sous le coude), "collar" (col, dans le dos), "belt" (ceinture), côté `sd` ("L"/"R").
## `from` : position de la main qui vient prendre (le tissu est pris du côté qui fait face).
func grip_point(kind: String, sd: String, from: Vector3):
	if not posed:
		return null
	var sg := 1.0 if sd == "L" else -1.0
	match kind:
		"sleeve":
			var c: Vector3 = last_O["forearm." + sd]
			var w: Vector3 = last_O["hand." + sd]
			var p := c.lerp(w, 0.28)
			var out := from - p
			out -= (w - c).normalized() * out.dot((w - c).normalized())
			return p + out.normalized() * 0.045 if out.length() > 1e-4 else p
		"collar":
			var gc: Basis = last_G["chest"]
			return last_O["neck"] + gc * Vector3(sg * 0.05, 0.0, -neck_back)
		"belt":
			var gh: Basis = last_G["hips"]
			return last_O["hips"] + gh * Vector3(sg * 0.09, 0.06, belt_front)
		_:
			var g: Basis = last_G["chest"]
			var y: float = lerpf(0.0, (J["cou"] - J["poitrine"]).y, 0.45)
			return last_O["chest"] + g * Vector3(sg * 0.075, y, chest_front + 0.01)


## Pose le modèle. M : articulations (m) dans le repère du parent du modèle.
## M["haut"] (facultatif) : vertical du corps (sans la flexion du buste) ; la colonne se
## courbe alors entre le bassin (qui suit les jambes) et la poitrine (qui suit le buste).
## ground : pose la plante des pieds sur le sol (y = 0) quand un pied est bas ;
## shift_in : décalage vertical imposé (judoka en l'air, suit celui qui le projette).
## Renvoie le décalage vertical appliqué.
## grips : fermeture des mains {"L": 0..1, "R": 0..1} (0 = main ouverte, 1 = poing serré).
## targets : {"L"/"R": point de la scène} — la paume de cette main va sur ce point (saisie du
## judogi adverse) par cinématique inverse, avec les vraies longueurs de bras du modèle ;
## le coude du jeu (M["coude.*"]) ne sert plus qu'à choisir le plan du bras.
func pose(M: Dictionary, ground: bool = true, shift_in = null, grips: Dictionary = {}, targets: Dictionary = {}) -> float:
	var G := {}
	var torso: Vector3 = M["cou"] - M["bassin"]
	var tdir := torso.normalized()
	var up: Vector3 = M.get("haut", tdir)
	# --- colonne : bassin peu fléchi, courbure répartie sur spine / spine2, poitrine dans l'axe du buste
	var bend_ang := up.angle_to(tdir)
	var up_h: Vector3 = up if bend_ang < 1e-3 else up.slerp(tdir, 0.35)
	var up_c: Vector3 = tdir if bend_ang < 1e-3 else up.slerp(tdir, 1.25 if bend_ang < 1.2 else 1.0).normalized()
	var lat_h: Vector3 = M["hanche.L"] - M["hanche.R"]
	var lat_c: Vector3 = M["epaule.L"] - M["epaule.R"]
	var Jlat := Vector3.RIGHT
	var spine_chain := ["hips", "spine", "spine2", "chest"]
	var spine_j := ["bassin", "dos", "milieu", "poitrine", "cou"]
	if not idx.has("spine2") or idx["spine2"] < 0:
		spine_chain = ["hips", "spine", "chest"]
		spine_j = ["bassin", "dos", "poitrine", "cou"]
	var rest_len := 0.0
	var acc := [0.0]
	for k in spine_chain.size():
		rest_len += (J[spine_j[k + 1]] - J[spine_j[k]]).length()
		acc.append(rest_len)
	var a0: Vector3 = M["bassin"]
	var a2: Vector3 = M["cou"]
	var L := torso.length()
	# point de contrôle : intersection des tangentes de départ (up_h) et d'arrivée (up_c)
	var ctrl: Vector3 = a0 + up_h * L * 0.5
	ctrl = ctrl.lerp(a2 - up_c * L * 0.5, 0.5)
	var prev := a0
	for k in spine_chain.size():
		var t: float = acc[k + 1] / rest_len
		var pt := _bez(a0, ctrl, a2, t)
		var w := (float(k) + 0.5) / spine_chain.size()
		var lat: Vector3 = lat_h.slerp(lat_c, clampf((w - 0.15) / 0.7, 0.0, 1.0)) if lat_h.length() > 1e-5 and lat_c.length() > 1e-5 else lat_h
		var rest_dir: Vector3 = J[spine_j[k + 1]] - J[spine_j[k]]
		G[spine_chain[k]] = _seg(pt - prev, lat) * _seg(rest_dir, Jlat).inverse()
		prev = pt
	G["neck"] = _arc(G["chest"] * (J["tete"] - J["cou"]), M["tete"] - M["cou"]) * G["chest"]
	G["head"] = G["neck"]
	if M.has("yaw") and absf(float(M["yaw"])) > 1e-3:
		# tête tournée sur le côté (corps à corps : les visages ne se font plus face)
		G["head"] = Basis((M["tete"] - M["cou"]).normalized(), float(M["yaw"])) * G["neck"]
	# --- bras : plan de flexion du coude imposé (le pli du coude suit le coude du jeu)
	for s in ["L", "R"]:
		var sg := 1.0 if s == "L" else -1.0
		var rest_n := Vector3(0, -sg, 0)
		var e: Vector3 = M["epaule." + s]
		var c: Vector3 = M["coude." + s]
		var h: Vector3 = M["main." + s]
		var n := _bend_normal(e, c, h, G["chest"] * rest_n)
		# clavicule : se soulève et s'avance un peu avec le bras
		var cl_rest: Vector3 = G["chest"] * (J["epaule." + s] - J["clavicule." + s])
		var arm_dir := (c - e).normalized()
		var lift := clampf(arm_dir.dot(G["chest"] * Vector3.UP) + 0.15, 0.0, 1.0)
		var cl_to := cl_rest.normalized().slerp(arm_dir, 0.08 + 0.17 * lift)
		G["shoulder." + s] = _arc(cl_rest, cl_to) * G["chest"]
		G["upper_arm." + s] = _seg(c - e, n) * _seg(J["coude." + s] - J["epaule." + s], rest_n).inverse()
		G["forearm." + s] = _seg(h - c, n) * _seg(J["poignet." + s] - J["coude." + s], rest_n).inverse()
		G["hand." + s] = G["forearm." + s]
	# --- jambes : plan de flexion du genou imposé (le genou part toujours vers l'avant)
	for s in ["L", "R"]:
		var hp: Vector3 = M["hanche." + s]
		var kn: Vector3 = M["genou." + s]
		var ft: Vector3 = M["pied." + s]
		var n := _bend_normal(hp, kn, ft, G["hips"] * Vector3.RIGHT)
		G["thigh." + s] = _seg(kn - hp, n) * _seg(J["genou." + s] - J["hanche." + s], Vector3.RIGHT).inverse()
		G["shin." + s] = _seg(ft - kn, n) * _seg(J["cheville." + s] - J["genou." + s], Vector3.RIGHT).inverse()
		G["foot." + s] = G["shin." + s]
		G["toes." + s] = G["shin." + s]
	# os non pilotés (autres rigs) : suivent leur parent
	for b in bones:
		if not G.has(b[0]):
			G[b[0]] = G[b[3]] if b[3] != "" else Basis()
	# --- pieds : à plat sur le tatami quand ils sont bas ; les orteils restent au sol
	# un peu plus longtemps (talon décollé = appui sur l'avant du pied)
	var flat := _basis_from(lat_h, Vector3.UP) * _basis_from(J["hanche.L"] - J["hanche.R"], Vector3.UP).inverse()
	var has_toes: bool = idx.has("toes.L") and idx["toes.L"] >= 0
	for s in ["L", "R"]:
		var h: float = M["pied." + s].y
		if h < 0.16:
			var k := clampf((0.16 - h) / 0.08, 0.0, 1.0)
			G["foot." + s] = Basis(Quaternion(G["foot." + s].orthonormalized()).slerp(Quaternion(flat.orthonormalized()), k))
		G["toes." + s] = G["foot." + s]
		if has_toes and h < 0.24:
			var kt := clampf((0.24 - h) / 0.08, 0.0, 1.0)
			G["toes." + s] = Basis(Quaternion(G["foot." + s].orthonormalized()).slerp(Quaternion(flat.orthonormalized()), kt))
	var hips_pos: Vector3 = M["bassin"]
	var shift := 0.0
	if ground and minf(M["pied.L"].y, M["pied.R"].y) < 0.12:
		var origin := {}
		for b in bones:
			var name: String = b[0]
			if b[3] == "":
				origin[name] = hips_pos
			else:
				var pb = bones[parent_i[name]]
				origin[name] = origin[b[3]] + G[b[3]] * (J[b[1]] - J[pb[1]])
		var low := INF
		for s in ["L", "R"]:
			var ankle: Vector3 = origin["foot." + s]
			var toe: Vector3
			if has_toes:
				toe = origin["toes." + s] + G["toes." + s] * (J["orteils." + s] - J["plante." + s])
				low = minf(low, origin["toes." + s].y - 0.035)
			else:
				toe = ankle + G["foot." + s] * (J["orteils." + s] - J["cheville." + s])
			var sole: Vector3 = ankle + G["foot." + s] * Vector3(0, -FLOOR_SOLE, 0)
			low = minf(low, minf(sole.y, toe.y - 0.015))
		shift = -low
	elif shift_in != null:
		shift = shift_in
		# judoka en l'air (uke) : jamais la tête ni le buste sous le tatami. Entre la dernière clé
		# en vol et la pose couchée, l'interpolation fait pivoter le corps autour du bassin et la
		# tête passait sous le tapis à l'impact.
		var o := {}
		for b in bones:
			var name: String = b[0]
			if b[3] == "":
				o[name] = hips_pos
			else:
				var pb = bones[parent_i[name]]
				o[name] = o[b[3]] + G[b[3]] * (J[b[1]] - J[pb[1]])
		var low_body := INF
		for name in ["hips", "spine", "spine2", "chest", "neck", "head"]:
			if o.has(name):
				low_body = minf(low_body, o[name].y)
		if o.has("head") and J.has("sommet"):
			low_body = minf(low_body, (o["head"] + G["head"] * (J["sommet"] - J["tete"])).y)
		shift = maxf(shift, BODY_CLEAR - low_body)
	hips_pos.y += shift
	# --- saisies : la paume va se poser sur le judogi adverse
	if not targets.is_empty():
		var O := _fk(G, hips_pos)
		for sd in targets:
			var tg = targets[sd]
			var pt: Vector3
			var w := 1.0
			if tg is Array:
				pt = tg[0]
				w = clampf(float(tg[1]), 0.0, 1.0)
			else:
				pt = tg
			if w < 1.0:
				# main qui part chercher la prise : de sa place naturelle vers le judogi
				var nat: Vector3 = O["hand." + sd] + G["hand." + sd] * (_palm_rest(sd) - J["poignet." + sd])
				pt = nat.lerp(pt, w)
			if w > 0.0:
				_reach(G, O, String(sd), pt, M["coude." + sd])
	# --- mains : les doigts s'enroulent vers la paume (paume vers le bas en pose T), le pouce se replie
	for s in ["L", "R"]:
		if not idx.has("fingers1." + s) or idx["fingers1." + s] < 0:
			continue
		var g := clampf(float(grips.get(s, 0.3)), 0.0, 1.0)
		var sg := -1.0 if s == "L" else 1.0
		G["fingers1." + s] = G["hand." + s] * Basis(Vector3.BACK, sg * 1.35 * g)
		G["fingers2." + s] = G["fingers1." + s] * Basis(Vector3.BACK, sg * 1.45 * g)
		G["thumb." + s] = G["hand." + s] * Basis(Vector3.RIGHT, 0.9 * g) * Basis(Vector3.UP, sg * -0.5 * g)
	last_G = G
	last_O = _fk(G, hips_pos)
	posed = true
	for b in bones:
		var name: String = b[0]
		var local: Basis = G[name] if b[3] == "" else G[b[3]].inverse() * G[name]
		skel.set_bone_pose_rotation(idx[name], Quaternion(local.orthonormalized()))
	skel.set_bone_pose_position(idx["hips"], hips_pos)
	return shift
