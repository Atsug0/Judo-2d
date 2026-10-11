extends SceneTree
## Vues d'un modèle 3D (.glb) chargé à l'exécution : face, profil, dos, trois-quarts.
##   godot --path . -s tools/mocap/view_model.gd -- --model=/chemin/model.glb --out=/tmp/vue
## Option --fit : recadre sur la boîte englobante ; --mesh=chemin.res non utilisé.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(String(args.model), state)
	if err != OK:
		print("échec du chargement : ", err)
		quit(1)
		return
	var model: Node = doc.generate_scene(state)
	var root := Node3D.new()
	get_root().add_child(root)
	root.add_child(model)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2a2440")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.2
	root.add_child(sun)
	# boîte englobante
	var aabb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	print("boîte : ", aabb)
	var c := aabb.get_center()
	var h := maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = h * 1.1
	root.add_child(cam)
	var views := {"face": Vector3(0, 0, 1), "profil": Vector3(1, 0, 0), "dos": Vector3(0, 0, -1), "gauche": Vector3(-1, 0, 0)}
	for name in views:
		cam.position = c + views[name] * h * 2.0
		cam.look_at(c)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s_%s.png" % [String(args.out), name])
	quit()
