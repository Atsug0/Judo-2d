extends SceneTree
## Aperçu 3D d'une chorégraphie filmée : deux mannequins (capsules, cel-shading) posés
## sur un tatami, rendus sous plusieurs angles et à plusieurs instants.
##   python3 tools/mocap/export_joints.py data/anims/uchi_mata.json /tmp/j.json
##   godot --path . -s tools/mocap/preview3d.gd -- --joints=/tmp/j.json --out=/tmp/apercu --times=0,0.33,0.6,0.85,1.0,1.33 --cam=34
## Écrit une image PNG par instant (apercu_<i>.png).

var keys: Array
var parts := {"tori": [], "uke": []}
var cam: Camera3D


func _init() -> void:
	_run.call_deferred()


func _v(p: Array) -> Vector3:
	return Vector3(p[0], p[2], -p[1])


func _mat(hex: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.9
	return m


func _limb(root: Node3D, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 1.0
	mi.mesh = cm
	mi.material_override = mat
	root.add_child(mi)
	return mi


func _ball(root: Node3D, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = mat
	root.add_child(mi)
	return mi


func _build(root: Node3D, who: String) -> void:
	var gi := _mat("f4efe4" if who == "tori" else "2a5fe0")
	var skin := _mat("e7b78f" if who == "tori" else "c98b5e")
	var spec := [[0.145, gi, "bassin", "cou"], [0.15, gi, "bassin", ""], [0.13, gi, "cou", ""], [0.05, skin, "cou", "tete"], [0.11, skin, "tete", ""]]
	for s in ["b", "f"]:
		spec += [[0.072, gi, "epaule_" + s, ""], [0.062, gi, "epaule_" + s, "coude_" + s], [0.06, gi, "coude_" + s, ""],
			[0.05, gi, "coude_" + s, "main_" + s], [0.05, skin, "main_" + s, ""], [0.085, gi, "hanche_" + s, ""],
			[0.082, gi, "hanche_" + s, "genou_" + s], [0.072, gi, "genou_" + s, ""], [0.066, gi, "genou_" + s, "pied_" + s], [0.06, skin, "pied_" + s, ""]]
	for p in spec:
		var mi := _limb(root, p[0], p[1]) if p[3] != "" else _ball(root, p[0], p[1])
		parts[who].append([mi, p[2], p[3]])


func _joints(t: float, who: String) -> Dictionary:
	var i := 0
	while i < keys.size() - 2 and t > float(keys[i + 1].t):
		i += 1
	var a: Dictionary = keys[i]
	var b: Dictionary = keys[i + 1]
	var u := clampf((t - float(a.t)) / maxf(0.0001, float(b.t) - float(a.t)), 0.0, 1.0)
	var out := {}
	for n in a[who]:
		out[n] = _v(a[who][n]).lerp(_v(b[who][n]), u)
	return out


func _pose(t: float) -> void:
	for who in ["tori", "uke"]:
		var j := _joints(t, who)
		for p in parts[who]:
			var mi: MeshInstance3D = p[0]
			var a: Vector3 = j[p[1]]
			if p[2] == "":
				mi.transform = Transform3D(Basis(), a)
				continue
			var b: Vector3 = j[p[2]]
			var d := b - a
			var len := maxf(0.001, d.length())
			var y := d / len
			var x := y.cross(Vector3(0, 0, 1))
			if x.length() < 0.01:
				x = y.cross(Vector3(1, 0, 0))
			x = x.normalized()
			var z := x.cross(y).normalized()
			mi.transform = Transform3D(Basis(x, y * len, z), a + d * 0.5)


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	keys = JSON.parse_string(FileAccess.open(String(args.joints), FileAccess.READ).get_as_text())
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("120f24")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("8f88c8")
	e.ambient_light_energy = 0.55
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff3dc")
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55, 35, 0)
	root.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("ff2e88")
	rim.light_energy = 0.8
	rim.rotation_degrees = Vector3(-20, -140, 0)
	root.add_child(rim)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5, 5)
	floor.mesh = pm
	floor.material_override = _mat("f2c230")
	floor.position = Vector3(0.3, 0, 0)
	root.add_child(floor)
	for k in 9:
		for dirn in [0, 1]:
			var line := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(5, 0.004, 0.012) if dirn == 0 else Vector3(0.012, 0.004, 5)
			line.mesh = bm
			line.material_override = _mat("b58a1a")
			line.position = Vector3(0.3, 0.002, -2.0 + k * 0.5) if dirn == 0 else Vector3(-1.7 + k * 0.5, 0.002, 0)
			root.add_child(line)
	_build(root, "tori")
	_build(root, "uke")
	cam = Camera3D.new()
	cam.fov = 38
	root.add_child(cam)
	var cams := {"profil": [Vector3(0.35, 0.95, 4.4), Vector3(0.35, 0.85, 0)], "34": [Vector3(2.9, 1.7, 3.3), Vector3(0.35, 0.8, 0)],
		"dos": [Vector3(-2.6, 1.5, 2.2), Vector3(0.4, 0.8, 0)], "34b": [Vector3(-1.3, 1.5, 3.9), Vector3(0.4, 0.8, 0)]}
	var c: Array = cams[String(args.get("cam", "34"))]
	cam.position = c[0]
	cam.look_at(c[1])
	var times := String(args.get("times", "0,0.33,0.66,1.0,1.33")).split(",")
	for i in times.size():
		_pose(float(times[i]))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s_%d.png" % [String(args.out), i])
	quit()
