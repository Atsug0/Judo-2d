extends RefCounted
## Pilotage d'un modèle 3D riggé (tools/rig/autorig.py) à partir d'articulations 3D
## « anatomiques » (bassin, cou, tête, hanches / genoux / pieds / épaules / coudes / mains
## gauche et droite), en mètres. Chaque os est orienté vers l'articulation suivante ; le
## bassin et la poitrine prennent aussi l'axe des hanches et des épaules (rotation du corps).
## Utilisé par le combat (scripts/view/models3d.gd) et l'outil de rendu (tools/rig/pose_model.gd).

const FLOOR_SOLE := 0.09   # cheville → plante du pied (m)

var node: Node3D           # scène du modèle
var skel: Skeleton3D
var J := {}                # articulations au repos (modèle)
var bones := []            # [nom, tête, queue, parent, rayon]
var idx := {}
var parent_i := {}


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


## Cel-shading : ombres en aplats, sans reflets, liseré lumineux, contour d'encre
## (coque inversée légèrement gonflée, dessinée par l'arrière).
static func _toon(m: StandardMaterial3D) -> void:
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.metallic = 0.0
	m.roughness = 1.0
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.7
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color("0b0a14")
	ink.cull_mode = BaseMaterial3D.CULL_FRONT
	ink.grow = true
	ink.grow_amount = 0.012
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


## Pose le modèle. M : articulations (m) dans le repère du parent du modèle.
## ground : pose la plante des pieds sur le sol (y = 0) quand un pied est bas ;
## shift_in : décalage vertical imposé (judoka en l'air, suit celui qui le projette).
## Renvoie le décalage vertical appliqué.
func pose(M: Dictionary, ground: bool = true, shift_in = null) -> float:
	var G := {}
	var torso: Vector3 = M["cou"] - M["bassin"]
	G["hips"] = _basis_from(M["hanche.L"] - M["hanche.R"], torso) * _basis_from(J["hanche.L"] - J["hanche.R"], J["dos"] - J["bassin"]).inverse()
	G["chest"] = _basis_from(M["epaule.L"] - M["epaule.R"], torso) * _basis_from(J["epaule.L"] - J["epaule.R"], J["cou"] - J["poitrine"]).inverse()
	G["spine"] = Basis(Quaternion(G["hips"].orthonormalized()).slerp(Quaternion(G["chest"].orthonormalized()), 0.5))
	var targets := {
		"neck": M["tete"] - M["cou"], "head": M["tete"] - M["cou"],
		"upper_arm.L": M["coude.L"] - M["epaule.L"], "forearm.L": M["main.L"] - M["coude.L"],
		"upper_arm.R": M["coude.R"] - M["epaule.R"], "forearm.R": M["main.R"] - M["coude.R"],
		"thigh.L": M["genou.L"] - M["hanche.L"], "shin.L": M["pied.L"] - M["genou.L"],
		"thigh.R": M["genou.R"] - M["hanche.R"], "shin.R": M["pied.R"] - M["genou.R"],
	}
	for b in bones:
		var name: String = b[0]
		if G.has(name):
			continue
		var pg: Basis = G[b[3]]
		if targets.has(name) and targets[name].length() > 1e-5:
			G[name] = _arc(pg * (J[b[2]] - J[b[1]]), targets[name]) * pg
		else:
			G[name] = pg
	# pied posé : à plat sur le tatami, orienté comme le bassin (pas de pointe tendue)
	var flat := _basis_from(M["hanche.L"] - M["hanche.R"], Vector3.UP) * _basis_from(J["hanche.L"] - J["hanche.R"], Vector3.UP).inverse()
	for s in ["L", "R"]:
		var h: float = M["pied." + s].y
		if h < 0.16:
			var k := clampf((0.16 - h) / 0.08, 0.0, 1.0)
			G["foot." + s] = Basis(Quaternion(G["foot." + s].orthonormalized()).slerp(Quaternion(flat.orthonormalized()), k))
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
			var toe: Vector3 = ankle + G["foot." + s] * (J["orteils." + s] - J["cheville." + s])
			var sole: Vector3 = ankle + G["foot." + s] * Vector3(0, -FLOOR_SOLE, 0)
			low = minf(low, minf(sole.y, toe.y - 0.015))
		shift = -low
	elif shift_in != null:
		shift = shift_in
	hips_pos.y += shift
	for b in bones:
		var name: String = b[0]
		var local: Basis = G[name] if b[3] == "" else G[b[3]].inverse() * G[name]
		skel.set_bone_pose_rotation(idx[name], Quaternion(local.orthonormalized()))
	skel.set_bone_pose_position(idx["hips"], hips_pos)
	return shift
