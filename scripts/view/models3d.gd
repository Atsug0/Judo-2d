extends Node
## Judokas en 3D dans le combat : deux modèles riggés rendus dans un SubViewport transparent,
## caméra orthographique calée sur la caméra 2D du combat. Les poses viennent du squelette 2D
## du jeu (garde, kumikata, projections, chorégraphies filmées, ne-waza) : chaque point est
## converti en articulation 3D (profondeur gauche / droite estimée), puis le modèle est posé.
## Par défaut : res://assets/judokas/<homme_blanc|homme_bleu>/rig.glb et joints.json
## (option « Judokas » des réglages d'affichage). --models3d=<dossier> --models3d_who=a,b pour tester.

const Skins := preload("res://scripts/skins.gd")
const RigPose := preload("res://scripts/view/rig_pose.gd")
const Art := preload("res://scripts/view/fighter_art.gd")

const M_PER_UNIT := 1.8 / 100.0
const SHOULDER := Vector2(0.5, -79.5)
const DEFAULT_DIR := "res://assets/judokas"
const DEFAULT_WHO := ["homme_blanc", "homme_bleu"]
const HALF := {"hanche": 0.10, "genou": 0.11, "pied": 0.13, "epaule": 0.18, "coude": 0.21, "main": 0.20}

var vp: SubViewport
var cam: Camera3D
var actors := [null, null, null]   # les deux judokas, puis l'arbitre
var ppm := 1.0          # pixels (monde 2D) par mètre
var feet_y := 0.0
# Demi-tour : quand le jeu retourne un judoka (face +1 ↔ -1, ex. entrée de seoi-nage), le
# modèle pivote en quelques images face à la caméra au lieu de s'inverser d'un coup, et
# ses articulations passent en fondu de l'ancienne à la nouvelle pose.
const TURN_FRAMES := 9.0
const BLEND_FRAMES := 8.0
var turn := [{}, {}, {}]
var instant_turn := false   # outils de rendu image par image : pas de demi-tour progressif
var clock := -1             # horloge du jeu (images de simulation) ; -1 = images du moteur


func setup(dir: String, who: Array, k: float, floor_y: float, textures: Array = []) -> bool:
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
	e.ambient_light_color = Color("b9c4ef")
	e.ambient_light_energy = 0.22
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# occlusion ambiante : creuse les plis, les emmanchures et le dessous du menton
	e.ssao_enabled = true
	e.ssao_radius = 0.28
	e.ssao_intensity = 3.4
	e.ssao_power = 1.6
	e.ssao_detail = 0.6
	env.environment = e
	vp.add_child(env)
	# Éclairage trois points façon studio : une clé chaude qui porte des ombres (c'est elle
	# qui creuse les plis du judogi et pose les bras sur le buste), une déboucheuse froide
	# sans ombre pour que le côté sombre ne soit pas noir, et un contre-jour qui détache
	# la silhouette du décor.
	for l in [
			[Color("fff6e8"), 1.15, Vector3(-42, -34, 0), true],
			
			]:
		var d := DirectionalLight3D.new()
		d.light_color = l[0]
		d.light_energy = l[1]
		d.rotation_degrees = l[2]
		if l[3]:
			d.shadow_enabled = true
			d.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			d.directional_shadow_max_distance = 4.0
			d.shadow_bias = 0.02
			d.shadow_normal_bias = 0.02
			d.shadow_opacity = 0.78
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
		var tex: String = String(textures[i]) if i < textures.size() else ""
		var a = RigPose.load_model(f[0], f[1], tex if tex != "" else f[2], true)
		if a == null:
			return false
		vp.add_child(a.node)
		actors[i] = a
	return true


## Arbitre : troisième acteur. Il se tient au fond du tatami, donc plus petit et décalé en
## profondeur ; la caméra étant orthographique, c'est l'échelle de son repère 2D qui le
## rapetisse, pas la distance. `lift_px` le remonte à la hauteur de ses pieds sur l'écran
## (il est posé comme les judokas, sur le sol du jeu, puis remonté du décalage de pieds).
func setup_arbitre(dir: String, who: String, echelle: float, lift_px: float, depth: float) -> bool:
	var f: Array = model_files(dir, who)
	if f.is_empty():
		return false
	var a = RigPose.load_model(f[0], f[1], f[2], true)
	if a == null:
		return false
	# `rig_pose` ne fait que tourner les os : il ne redimensionne pas le modèle, qui fait
	# 1,90 m comme les judokas. C'est donc le nœud qui porte l'échelle — et l'appelant doit
	# diviser l'abscisse qu'il passe à pose_rig par cette même échelle (elle s'applique
	# aussi à la position).
	a.node.scale = Vector3(echelle, echelle, echelle)
	a.node.position = Vector3(0.0, lift_px / ppm, depth)
	vp.add_child(a.node)
	actors[2] = a
	return true


## Fichiers d'un modèle : [rig.glb, joints.json, texture de remplacement ou ""].
## `textures` (setup) surcharge la texture, pour reteindre un judogi en bleu pour P2.
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


## Modèle d'un judoka : le skin choisi (look.modele), judogi blanc pour P1 et bleu pour P2.
static func who_for(look: Dictionary, player: int) -> String:
	return Skins.dir_for(Skins.of(look), player)


## Texture de remplacement du judogi (bleu de P2 sur un skin qui n'existe qu'en blanc).
static func texture_for(look: Dictionary, player: int) -> String:
	return Skins.texture_for(Skins.of(look), player)


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
## grips : [main arrière, main avant] du jeu, -1 = pas de prise, 0..1 = force de la prise.
func pose_rig(i: int, xf: Transform2D, pose: Dictionary, hands: Array, ground: bool = true, shift_in = null, grips: Array = []) -> float:
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
	# repère anatomique (pose locale) : a = vers l'avant, y = vers le haut, r = vers la droite (m)
	var s := xf.x.length() / ppm
	var A := {"bassin": _an(hip, hip, s, 0.0), "cou": _an(neck, hip, s, 0.0), "tete": _an(head, hip, s, 0.0)}
	var hand_local := [pose.get("hb", Art.REST_HANDS[0]), pose.get("hf", Art.REST_HANDS[1])]
	for k in 2:
		if hands.size() > k and hands[k] != null:
			hand_local[k] = inv * Vector2(hands[k])
	for sd in ["b", "f"]:
		var a: String = side_of[sd]
		var r := HALF.duplicate()
		var z := 1.0 if a == "R" else -1.0
		var foot: Vector2 = pose["f" + sd]
		var knee: Vector2 = pose["k" + sd] if pose.has("k" + sd) else Art.ik_knee(torso.call(Vector2(-6 if sd == "b" else 6, -47)), foot)
		var hand: Vector2 = hand_local[0 if sd == "b" else 1]
		var elbow := _ik(sh, hand, Art.ARM_UPPER, Art.ARM_FORE, true)
		A["hanche." + a] = _an(hip, hip, s, z * r.hanche)
		A["genou." + a] = _an(knee, hip, s, z * r.genou)
		A["pied." + a] = _an(foot, hip, s, z * r.pied)
		A["epaule." + a] = _an(sh, hip, s, z * r.epaule)
		A["coude." + a] = _an(elbow, hip, s, z * r.coude)
		A["main." + a] = _an(hand, hip, s, z * r.main)
	A = _turn_blend(i, face, A)
	var phi: float = turn[i].phi
	# repère du corps dans la scène : e1 = avant pour face +1, eu = vertical du corps
	var e1 := _dir3(xf.basis_xform(Vector2(face, 0)))
	var eu := _dir3(xf.basis_xform(Vector2(0, -1)))
	var fwd := e1 * cos(phi) + Vector3.BACK * sin(phi)
	var right := -e1 * sin(phi) + Vector3.BACK * cos(phi)
	var o := _m(xf * Vector2(hip.x, hip.y), 0.0)
	var M := {"haut": eu}
	for k in A:
		var v: Vector3 = A[k]
		M[k] = o + fwd * v.x + eu * v.y + right * v.z
	var closed := {}
	for k in 2:
		var g: float = float(grips[k]) if grips.size() > k and grips[k] != null else -1.0
		closed[side_of["b" if k == 0 else "f"]] = 0.3 if g < 0.0 else 0.8 + 0.2 * clampf(g, 0.0, 1.0)
	if pose.has("fist"):
		closed = {"L": float(pose.fist), "R": float(pose.fist)}
	return actors[i].pose(M, ground, shift_in, closed)


## Point de la pose locale (unités du jeu, y vers le bas) → repère anatomique (m) autour du bassin.
static func _an(p: Vector2, hip: Vector2, s: float, r: float) -> Vector3:
	return Vector3((p.x - hip.x) * s, -(p.y - hip.y) * s, r)


static func _dir3(v: Vector2) -> Vector3:
	return Vector3(v.x, -v.y, 0.0).normalized()


## Suit l'orientation (phi : 0 = face +1, PI = face -1, en passant face caméra) et fond
## les articulations pendant BLEND_FRAMES images après un retournement.
func _turn_blend(i: int, face: int, A: Dictionary) -> Dictionary:
	var st: Dictionary = turn[i]
	var frame: int = clock if clock >= 0 else Engine.get_process_frames()
	var target := 0.0 if face > 0 else PI
	var dt := float(frame - int(st.get("frame", -1000)))
	if instant_turn or not st.has("phi") or dt > 20.0 or dt < 0.0:
		st.phi = target
		st.blend = BLEND_FRAMES
		st.face = face
		st.from = {}
		dt = 0.0
	dt = minf(dt, 20.0)
	st.frame = frame
	if face != int(st.face):
		st.face = face
		st.from = st.get("last", {}).duplicate()
		st.blend = 0.0
	st.phi = move_toward(float(st.phi), target, PI / TURN_FRAMES * dt)
	st.blend = minf(float(st.blend) + dt, BLEND_FRAMES)
	var out := A
	if float(st.blend) < BLEND_FRAMES and not st.from.is_empty():
		var w := smoothstep(0.0, 1.0, float(st.blend) / BLEND_FRAMES)
		out = {}
		for k in A:
			out[k] = st.from[k].lerp(A[k], w) if st.from.has(k) else A[k]
	st.last = out
	return out


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
	actors[i].pose(M, false, null, {"L": 0.75, "R": 0.75})  # au sol : on tient le judogi
