extends Node
## Judokas en 3D dans le combat : deux modèles riggés rendus dans un SubViewport transparent,
## caméra orthographique calée sur la caméra 2D du combat. Les poses viennent du squelette 2D
## du jeu (garde, kumikata, projections, chorégraphies filmées, ne-waza) : chaque point est
## converti en articulation 3D (profondeur gauche / droite estimée), puis le modèle est posé.
## Par défaut : res://assets/judokas/<homme_blanc|homme_bleu>/rig.glb et joints.json
## (option « Judokas » des réglages d'affichage). --models3d=<dossier> --models3d_who=a,b pour tester.

const RigPose := preload("res://scripts/view/rig_pose.gd")
const Art := preload("res://scripts/view/fighter_art.gd")

const M_PER_UNIT := 1.8 / 100.0
const SHOULDER := Vector2(0.5, -79.5)
const DEFAULT_DIR := "res://assets/judokas"
const DEFAULT_WHO := ["homme_blanc", "homme_bleu"]
const HALF := {"hanche": 0.10, "genou": 0.11, "pied": 0.13, "epaule": 0.18, "coude": 0.21, "main": 0.20}

var vp: SubViewport
var cam: Camera3D
var actors := [null, null]
var ppm := 1.0          # pixels (monde 2D) par mètre
var feet_y := 0.0


func setup(dir: String, who: Array, k: float, floor_y: float) -> bool:
	ppm = k / M_PER_UNIT
	feet_y = floor_y
	vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c4bcf0")
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	for l in [[Color("fff4e4"), 1.25, Vector3(-38, -32, 0)], [Color("ff3fa0"), 1.1, Vector3(-10, 150, 0)], [Color("38d6ff"), 0.9, Vector3(-10, -150, 0)]]:
		var d := DirectionalLight3D.new()
		d.light_color = l[0]
		d.light_energy = l[1]
		d.rotation_degrees = l[2]
		vp.add_child(d)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.1
	cam.far = 40.0
	vp.add_child(cam)
	for i in 2:
		var w: String = who[i] if i < who.size() else DEFAULT_WHO[i]
		var f: Array = model_files(dir, w)
		if f.is_empty():
			f = model_files(dir, DEFAULT_WHO[i])
		if f.is_empty():
			return false
		var a = RigPose.load_model(f[0], f[1], f[2], true)
		if a == null:
			return false
		vp.add_child(a.node)
		actors[i] = a
	return true


## Fichiers d'un modèle : [rig.glb, joints.json, texture de remplacement ou ""].
## Un dossier peut emprunter le rig d'un autre (modele.json : {"rig": "femme_bleu", "texture": "texture.png"}).
static func model_files(dir: String, w: String) -> Array:
	var base := dir.path_join(w)
	if FileAccess.file_exists(base.path_join("rig.glb")):
		return [base.path_join("rig.glb"), base.path_join("joints.json"), ""]
	if FileAccess.file_exists(base.path_join("modele.json")):
		var m = JSON.parse_string(FileAccess.open(base.path_join("modele.json"), FileAccess.READ).get_as_text())
		var src := dir.path_join(String(m.rig))
		if FileAccess.file_exists(src.path_join("rig.glb")):
			return [src.path_join("rig.glb"), src.path_join("joints.json"), base.path_join(String(m.get("texture", "")))]
	return []


## Modèle d'un judoka : homme / femme (look.body3d), judogi blanc pour P1 et bleu pour P2.
static func who_for(look: Dictionary, player: int) -> String:
	return ("femme" if int(look.get("body3d", 0)) == 1 else "homme") + ("_blanc" if player == 0 else "_bleu")


func texture() -> Texture2D:
	return vp.get_texture()


## Caméra 3D = caméra 2D : centre (monde, px), zoom, secousse (écran, px).
func update_camera(center: Vector2, zoom: float, shake: Vector2) -> void:
	var c := center - shake / zoom
	cam.size = (720.0 / zoom) / ppm
	cam.position = Vector3(c.x / ppm, (feet_y - c.y) / ppm, 12.0)


func _m(p: Vector2, depth: float) -> Vector3:
	return Vector3(p.x / ppm, (feet_y - p.y) / ppm, depth)


static func _ik(a: Vector2, b: Vector2, l1: float, l2: float, down: bool) -> Vector2:
	var d := b - a
	var dist := clampf(d.length(), 1.0, l1 + l2 - 0.01)
	var ang := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
	var base := d.angle()
	var k1 := a + Vector2.from_angle(base + ang) * l1
	var k2 := a + Vector2.from_angle(base - ang) * l1
	if down:
		return k1 if k1.y > k2.y else k2
	return k1 if k1.x > k2.x else k2


## Judoka debout ou projeté : repère 2D (monde), pose « debout » du jeu, mains (monde) ou null.
func pose_rig(i: int, xf: Transform2D, pose: Dictionary, hands: Array, ground: bool = true, shift_in = null) -> float:
	var hip: Vector2 = pose.get("hip", Art.HIP0)
	var bow := float(pose.get("bow", 0.0))
	var tilt := float(pose.get("tilt", 0.0))
	var torso := func(p: Vector2) -> Vector2: return hip + (p - Art.HIP0).rotated(bow)
	var neck: Vector2 = torso.call(Art.NECK0)
	var head: Vector2 = neck + (Art.HEAD_CENTER - Art.NECK0).rotated(bow + tilt)
	var sh: Vector2 = torso.call(SHOULDER)
	var inv := xf.affine_inverse()
	var face := -1 if xf.determinant() < 0.0 else 1
	var side_of := {"f": "R", "b": "L"} if face > 0 else {"f": "L", "b": "R"}
	var M := {"bassin": _m(xf * hip, 0.0), "cou": _m(xf * neck, 0.0), "tete": _m(xf * head, 0.0)}
	var hand_local := [pose.get("hb", Art.REST_HANDS[0]), pose.get("hf", Art.REST_HANDS[1])]
	for k in 2:
		if hands.size() > k and hands[k] != null:
			hand_local[k] = inv * Vector2(hands[k])
	for s in ["b", "f"]:
		var a: String = side_of[s]
		var z := 1.0 if s == "f" else -1.0
		var foot: Vector2 = pose["f" + s]
		var knee: Vector2 = pose["k" + s] if pose.has("k" + s) else Art.ik_knee(torso.call(Vector2(-6 if s == "b" else 6, -47)), foot)
		var hand: Vector2 = hand_local[0 if s == "b" else 1]
		var elbow := _ik(sh, hand, Art.ARM_UPPER, Art.ARM_FORE, true)
		M["hanche." + a] = _m(xf * hip, z * HALF.hanche)
		M["genou." + a] = _m(xf * knee, z * HALF.genou)
		M["pied." + a] = _m(xf * foot, z * HALF.pied)
		M["epaule." + a] = _m(xf * sh, z * HALF.epaule)
		M["coude." + a] = _m(xf * elbow, z * HALF.coude)
		M["main." + a] = _m(xf * hand, z * HALF.main)
	return actors[i].pose(M, ground, shift_in)


## Judoka au sol (ne-waza) : repère 2D et articulations de fighter_art.ground_poses().
func pose_ground(i: int, xf: Transform2D, j: Dictionary) -> void:
	var face := -1 if xf.determinant() < 0.0 else 1
	var side_of := {"f": "R", "b": "L"} if face > 0 else {"f": "L", "b": "R"}
	var hip: Vector2 = j.hip
	var neck: Vector2 = j.neck
	var sh: Vector2 = neck + (hip - neck).normalized() * 6.0
	var M := {"bassin": _m(xf * hip, 0.0), "cou": _m(xf * neck, 0.0), "tete": _m(xf * Vector2(j.head), 0.0)}
	for s in ["b", "f"]:
		var a: String = side_of[s]
		var z := 1.0 if s == "f" else -1.0
		M["hanche." + a] = _m(xf * hip, z * HALF.hanche)
		M["genou." + a] = _m(xf * Vector2(j["knee_" + s]), z * HALF.genou)
		M["pied." + a] = _m(xf * Vector2(j["foot_" + s]), z * HALF.pied)
		M["epaule." + a] = _m(xf * sh, z * HALF.epaule)
		M["coude." + a] = _m(xf * Vector2(j["elbow_" + s]), z * HALF.coude)
		M["main." + a] = _m(xf * Vector2(j["hand_" + s]), z * HALF.main)
	actors[i].pose(M, false)
