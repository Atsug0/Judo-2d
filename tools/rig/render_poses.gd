extends SceneTree
## Rend les judokas 3D en images (fond transparent) pour les écrans de menu :
## garde et victoire, légèrement tournés vers la caméra.
##   godot --path . -s tools/rig/render_poses.gd
## Écrit assets/judokas/<modèle>/poses/<pose>.png et poses.json (pivot des pieds, px par unité).

const Models3D := preload("res://scripts/view/models3d.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const Skins := preload("res://scripts/skins.gd")
## Tous les dossiers de modèle référencés par le catalogue des skins (les deux couleurs),
## ou ceux passés en argument : godot --path . -s tools/rig/render_poses.gd -- colosse modern
static func _models() -> Array:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		return Array(args)
	var out := []
	for s in Skins.all():
		for k in ["blanc", "bleu"]:
			var d := String(s.get(k, ""))
			if d != "" and not out.has(d):
				out.append(d)
	return out
const W := 600
const H := 900
const FEET_ROW := 860.0
const PX_PER_M := 375.0
const TURN := -0.42   # quart de tour vers la caméra


func _init() -> void:
	_run.call_deferred()


func _poses() -> Dictionary:
	var garde := Art.pose_stand(0.3)
	var victoire := Art.pose_stand(0.15)
	victoire.hb = Vector2(-14, -126)
	victoire.hf = Vector2(18, -66)
	victoire.fist = 1.0
	garde.fist = 0.35
	return {"garde": garde, "victoire": victoire}


func _run() -> void:
	var dir := Models3D.DEFAULT_DIR
	for w in _models():
		if Models3D.model_files(dir, w).is_empty():
			print("absent : ", w)
			continue
		var m = Models3D.new()
		get_root().add_child(m)
		if not m.setup(dir, [w, w], 2.2, 0.0):
			print("échec : ", w)
			continue
		m.actors[1].node.visible = false
		m.instant_turn = true
		m.vp.size = Vector2i(W, H)
		m.vp.msaa_3d = Viewport.MSAA_4X
		m.cam.size = H / PX_PER_M
		m.cam.position = Vector3(0.0, (FEET_ROW - H / 2.0) / PX_PER_M, 12.0)
		var out := dir.path_join(w).path_join("poses")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
		var poses := _poses()
		for name in poses:
			var node: Node3D = m.actors[0].node
			node.rotation = Vector3.ZERO
			m.pose_rig(0, Transform2D(0.0, Vector2(2.2, 2.2), 0.0, Vector2.ZERO), poses[name], [], true)
			# quart de tour autour des pieds (axe vertical passant par x = 0)
			node.rotation = Vector3(0, TURN, 0)
			for k in 3:
				await RenderingServer.frame_post_draw
			var img: Image = m.vp.get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path(out.path_join(name + ".png")))
			print("rendu : ", w, " ", name)
		var info := {"pivot": [W / 2.0, FEET_ROW], "px_per_unit": PX_PER_M * Models3D.M_PER_UNIT}
		var f := FileAccess.open(ProjectSettings.globalize_path(out.path_join("poses.json")), FileAccess.WRITE)
		f.store_string(JSON.stringify(info, " "))
		f.close()
		m.queue_free()
		await RenderingServer.frame_post_draw
	quit()
