extends SceneTree
## Rendu d'une chorégraphie filmée avec de vrais modèles 3D riggés (tools/rig/autorig.py).
##
##   godot --path . -s tools/rig/pose_model.gd -- \
##       --tori=homme_rig.glb --tori_joints=tools/rig/judoka_joints.json \
##       --uke=homme_rig.glb --uke_joints=tools/rig/judoka_joints.json --uke_texture=gi_bleu.png \
##       --anim=uchi_mata_rig.json --times=0,0.33,0.6 --cam=34 --out=/tmp/rendu
##
## --anim : articulations gauche / droite (tools/rig/mocap_to_rig.py). Chaque os est orienté
## vers l'articulation suivante ; le bassin et la poitrine prennent aussi l'axe des hanches
## et des épaules (pour la rotation du corps). Les pieds d'un judoka au sol sont posés sur
## le tatami (les proportions du modèle ne sont pas celles du squelette filmé).
## --test : pose de repos et pose d'essai (bras levés, genou plié) pour vérifier le rig.

const FLOOR_SOLE := 0.09   # cheville → plante du pied (m)

var keys: Array
var toon := false
var actors := {}


func _init() -> void:
	_run.call_deferred()


class Actor:
	var node: Node3D
	var skel: Skeleton3D
	var J := {}            # articulations au repos (modèle)
	var bones := []        # [nom, tête, queue, parent]
	var idx := {}
	var rest_floor := 0.0  # hauteur de la plante au repos (modèle)


func _load_actor(glb: String, joints_path: String, texture: String) -> Actor:
	var a := Actor.new()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(glb, st) != OK:
		push_error("modèle illisible : " + glb)
		return null
	a.node = doc.generate_scene(st)
	var sk = a.node.find_children("*", "Skeleton3D", true, false)
	a.skel = sk[0]
	var spec = JSON.parse_string(FileAccess.open(joints_path, FileAccess.READ).get_as_text())
	for k in spec.joints:
		var v = spec.joints[k]
		a.J[k] = Vector3(v[0], v[1], v[2])
	a.bones = spec.bones
	for b in a.bones:
		a.idx[b[0]] = a.skel.find_bone(b[0])
		if a.idx[b[0]] < 0:
			push_error("os introuvable : %s (os du modèle : %s)" % [b[0], a.skel.get_concatenated_bone_names()])
	a.rest_floor = minf(a.J["cheville.L"].y, a.J["cheville.R"].y) - FLOOR_SOLE
	var tex: Texture2D = null
	if texture != "":
		tex = ImageTexture.create_from_image(Image.load_from_file(texture))
	for mi in a.node.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m: StandardMaterial3D = mi.mesh.surface_get_material(s).duplicate()
			if tex != null:
				m.albedo_texture = tex
			if toon:
				# cel-shading (aplats), contour d'encre (coque inversée), pas de reflets
				m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				m.metallic = 0.0
				m.roughness = 1.0
				m.rim_enabled = true
				m.rim = 0.35
				m.rim_tint = 0.6
				var ink := StandardMaterial3D.new()
				ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				ink.albedo_color = Color("0b0a14")
				ink.cull_mode = BaseMaterial3D.CULL_FRONT
				ink.grow = true
				ink.grow_amount = 0.011
				m.next_pass = ink
			mi.set_surface_override_material(s, m)
	return a


func _basis_from(lateral: Vector3, up: Vector3) -> Basis:
	var y := up.normalized()
	var x := (lateral - y * lateral.dot(y)).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _arc(from: Vector3, to: Vector3) -> Basis:
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


func _joints_at(t: float, who: String) -> Dictionary:
	var i := 0
	while i < keys.size() - 2 and t > float(keys[i + 1].t):
		i += 1
	var a: Dictionary = keys[i]
	var b: Dictionary = keys[i + 1]
	var u := clampf((t - float(a.t)) / maxf(0.0001, float(b.t) - float(a.t)), 0.0, 1.0)
	var out := {}
	for n in a[who]:
		var p: Array = a[who][n]
		var q: Array = b[who][n]
		out[n] = Vector3(p[0], p[1], p[2]).lerp(Vector3(q[0], q[1], q[2]), u)
	return out


## Pose un acteur d'après les articulations filmées M ; renvoie le décalage vertical appliqué.
func _pose(a: Actor, M: Dictionary, shift_in = null) -> float:
	var J := a.J
	var G := {}
	var torso: Vector3 = M["cou"] - M["bassin"]
	var hip_lat: Vector3 = M["hanche.L"] - M["hanche.R"]
	var sh_lat: Vector3 = M["epaule.L"] - M["epaule.R"]
	var rest_hips := _basis_from(J["hanche.L"] - J["hanche.R"], J["dos"] - J["bassin"])
	var rest_chest := _basis_from(J["epaule.L"] - J["epaule.R"], J["cou"] - J["poitrine"])
	G["hips"] = _basis_from(hip_lat, torso) * rest_hips.inverse()
	G["chest"] = _basis_from(sh_lat, torso) * rest_chest.inverse()
	G["spine"] = Basis(Quaternion(G["hips"]).slerp(Quaternion(G["chest"]), 0.5))
	var targets := {
		"neck": M["tete"] - M["cou"], "head": M["tete"] - M["cou"],
		"upper_arm.L": M["coude.L"] - M["epaule.L"], "forearm.L": M["main.L"] - M["coude.L"],
		"upper_arm.R": M["coude.R"] - M["epaule.R"], "forearm.R": M["main.R"] - M["coude.R"],
		"thigh.L": M["genou.L"] - M["hanche.L"], "shin.L": M["pied.L"] - M["genou.L"],
		"thigh.R": M["genou.R"] - M["hanche.R"], "shin.R": M["pied.R"] - M["genou.R"],
	}
	for b in a.bones:
		var name: String = b[0]
		if G.has(name):
			continue
		var parent: String = b[3]
		var pg: Basis = G[parent]
		if targets.has(name):
			var rest_dir: Vector3 = J[b[2]] - J[b[1]]
			G[name] = _arc(pg * rest_dir, targets[name]) * pg
		else:
			G[name] = pg   # clavicules, mains, pieds : suivent leur parent
	# positions globales des articulations (chaîne depuis le bassin)
	var origin := {}
	var hips_pos: Vector3 = M["bassin"]
	for b in a.bones:
		var name: String = b[0]
		if b[3] == "":
			origin[name] = hips_pos
		else:
			var parent: String = b[3]
			var rest_off: Vector3 = J[b[1]] - J[a.bones[_bone_i(a, parent)][1]]
			origin[name] = origin[parent] + G[parent] * rest_off
	# contact au sol : plante des pieds sur le tatami
	var low := INF
	for s in ["L", "R"]:
		var ankle: Vector3 = origin["foot." + s]
		var toe: Vector3 = ankle + G["foot." + s] * (J["orteils." + s] - J["cheville." + s])
		var sole: Vector3 = ankle + G["foot." + s] * Vector3(0, -FLOOR_SOLE, 0)
		low = minf(low, minf(sole.y, toe.y - 0.015))
	var grounded: bool = minf(M["pied.L"].y, M["pied.R"].y) < 0.12
	var shift := 0.0
	if grounded:
		shift = -low
	elif shift_in != null:
		shift = shift_in
	hips_pos.y += shift
	# application au squelette (rotations locales = parent⁻¹ × global)
	for b in a.bones:
		var name: String = b[0]
		var bi: int = a.idx[name]
		var local: Basis = G[name] if b[3] == "" else G[b[3]].inverse() * G[name]
		a.skel.set_bone_pose_rotation(bi, Quaternion(local.orthonormalized()))
	a.skel.set_bone_pose_position(a.idx["hips"], hips_pos)
	return shift


func _bone_i(a: Actor, name: String) -> int:
	for i in a.bones.size():
		if a.bones[i][0] == name:
			return i
	return -1


func _run() -> void:
	var args := {}
	for x in OS.get_cmdline_user_args():
		var kv := x.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	toon = args.has("toon")
	var root := Node3D.new()
	get_root().add_child(root)
	_stage(root, args)
	var tori := _load_actor(String(args.tori), String(args.tori_joints), String(args.get("tori_texture", "")))
	root.add_child(tori.node)
	var uke: Actor = null
	if args.has("uke"):
		uke = _load_actor(String(args.uke), String(args.uke_joints), String(args.get("uke_texture", "")))
		root.add_child(uke.node)
	var cam := Camera3D.new()
	cam.fov = float(args.get("fov", "34"))
	root.add_child(cam)
	var cams := {"profil": [Vector3(0.35, 1.0, 4.6), Vector3(0.35, 0.9, 0)], "34": [Vector3(-1.5, 1.55, 4.0), Vector3(0.4, 0.85, 0)],
		"face": [Vector3(0.0, 1.0, 3.6), Vector3(0.0, 0.95, 0)], "34r": [Vector3(2.6, 1.5, 3.4), Vector3(0.35, 0.85, 0)]}
	var c: Array = cams[String(args.get("cam", "34"))]
	cam.position = c[0]
	cam.look_at(c[1])
	if args.has("test"):
		# repos, puis bras levés et genou plié : vérification des poids de peau
		tori.node.position = Vector3(0, 0.95, 0)
		await _shot(String(args.out) + "_repos.png")
		var sk := tori.skel
		sk.set_bone_pose_rotation(tori.idx["upper_arm.L"], Quaternion(Vector3.BACK, 1.9))
		sk.set_bone_pose_rotation(tori.idx["upper_arm.R"], Quaternion(Vector3.BACK, -0.9))
		sk.set_bone_pose_rotation(tori.idx["forearm.R"], Quaternion(Vector3.RIGHT, -1.4))
		sk.set_bone_pose_rotation(tori.idx["thigh.L"], Quaternion(Vector3.RIGHT, -1.2))
		sk.set_bone_pose_rotation(tori.idx["shin.L"], Quaternion(Vector3.RIGHT, 1.5))
		sk.set_bone_pose_rotation(tori.idx["spine"], Quaternion(Vector3.RIGHT, 0.35))
		await _shot(String(args.out) + "_essai.png")
		quit()
		return
	keys = JSON.parse_string(FileAccess.open(String(args.anim), FileAccess.READ).get_as_text()).keys
	var times := String(args.get("times", "0,0.33,0.66,1.0,1.33")).split(",")
	for i in times.size():
		var t := float(times[i])
		var shift := _pose(tori, _joints_at(t, "tori"))
		if uke != null:
			_pose(uke, _joints_at(t, "uke"), shift)
		await _shot("%s_%d.png" % [String(args.out), i])
	quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)
	print("rendu : ", path)


func _stage(root: Node3D, args: Dictionary) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("17132b")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b8b0e8")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff1dc")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, -25, 0)
	root.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("ff4a9a")
	rim.light_energy = 0.9
	rim.rotation_degrees = Vector3(-15, 150, 0)
	root.add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("7fb2ff")
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-10, 60, 0)
	root.add_child(fill)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("e9b62c")
	mat.roughness = 0.85
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(7, 7)
	floor.mesh = pm
	floor.material_override = mat
	floor.position = Vector3(0.3, 0, 0)
	root.add_child(floor)
	var seam := StandardMaterial3D.new()
	seam.albedo_color = Color("a87b12")
	for k in 15:
		for d in [0, 1]:
			var line := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(7, 0.003, 0.01) if d == 0 else Vector3(0.01, 0.003, 7)
			line.mesh = bm
			line.material_override = seam
			line.position = Vector3(0.3, 0.0015, -3.5 + k * 0.5) if d == 0 else Vector3(-3.2 + k * 0.5, 0.0015, 0)
			root.add_child(line)
