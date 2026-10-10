extends Node2D
## Outil : « cuit » les judokas placeholders en images PNG + manifest.json,
## au même format que les sprites qui sortiront de Blender.
## Sert à tester toute la chaîne sprites (chargement, pivots, projections à deux)
## avant d'avoir les vidéos.
##   godot --path . -- --screen=bake --capture=/tmp/x   (le dossier n'est pas utilisé)
## Sortie : res://animations/placeholder_blanc/ et res://animations/placeholder_bleu/

const Art := preload("res://scripts/view/fighter_art.gd")
const Painter := preload("res://scripts/tools/bake_painter.gd")

const UNIT_PX := 4.0
const GAP_UNITS := 33.0   # écart tori/uke en début de projection (min_gap du jeu)
const THROWS := {"seoi_nage": "avant", "o_soto_gari": "arriere", "o_uchi_gari": "arriere", "ko_uchi_gari": "arriere_cote", "de_ashi_barai": "cote"}

var app
var vp: SubViewport
var painter: Node2D


func on_enter(_params: Dictionary) -> void:
	pass


func nav(action: String, _player: int = 0) -> void:
	if action == "back":
		app.goto("menu", {})


func run_bake() -> void:
	for p in 2:
		var char_id := "placeholder_blanc" if p == 0 else "placeholder_bleu"
		var base := "res://animations/" + char_id
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
		var manifest := {"character": char_id, "unit_px": UNIT_PX, "fps": 12, "anims": {}}
		var pal := Art.palette(p)
		# --- garde (respiration)
		var idle_fn := func(ci, k):
			var fr := float(k) / 6.0
			var xf := Art.stand_xform(Vector2(300, 560), 1, 0.0, UNIT_PX, 0.08 + 0.06 * sin(TAU * fr))
			_stand(ci, xf, pal, 0.5)
		await _bake(base, manifest, "idle", 6, Vector2i(600, 600), Vector2(300, 560), true, idle_fn)
		# --- marche avant
		var walk_fn := func(ci, k):
			var fr := float(k) / 6.0
			var xf := Art.stand_xform(Vector2(300, 560), 1, 0.04, UNIT_PX, 0.1)
			_stand(ci, xf, pal, 0.5 + 0.5 * sin(TAU * fr))
		await _bake(base, manifest, "walk_fwd", 6, Vector2i(600, 600), Vector2(300, 560), true, walk_fn)
		# --- entrée de seoi-nage (tori se baisse)
		var entry_fn := func(ci, k):
			var fr := float(k) / 5.0
			var xf := Art.stand_xform(Vector2(300, 560), 1, 0.15 * fr, UNIT_PX, fr)
			_stand(ci, xf, pal, 0.4)
		await _bake(base, manifest, "entry/seoi_nage", 6, Vector2i(600, 600), Vector2(300, 560), false, entry_fn)
		# --- projections : tori et uke partagent la même caméra (ancre = pieds de tori)
		for tech in THROWS:
			var dir: String = THROWS[tech]
			for role in ["tori", "uke"]:
				var throw_fn := func(ci, k):
					var pr := float(k) / 11.0
					var tx := 560.0
					var ux := tx + GAP_UNITS * UNIT_PX
					var pair: Array = Art.throw_xforms(dir, true, 1, tx, ux, 650.0, UNIT_PX, pr)
					if role == "tori":
						var uxf: Transform2D = pair[1]
						Art.draw_arm(ci, pair[0] * Art.SHOULDER_BACK, uxf * Art.GRIP_POINTS["sleeve"], pal, true, UNIT_PX)
						Art.draw_body(ci, pair[0], pal, 0.4)
						Art.draw_arm(ci, pair[0] * Art.SHOULDER_FRONT, uxf * Art.GRIP_POINTS["lapel"], pal, false, UNIT_PX)
					else:
						_stand(ci, pair[1], pal, 0.2)
				await _bake(base, manifest, "throw/%s/%s" % [tech, role], 12, Vector2i(1200, 720), Vector2(560, 650), false, throw_fn, "tori")
		var f := FileAccess.open(base + "/manifest.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(manifest, "  "))
		f.close()
		print("cuit : ", char_id, " (", manifest.anims.size(), " animations)")


func _stand(ci: CanvasItem, xf: Transform2D, pal: Dictionary, stance: float) -> void:
	Art.draw_arm(ci, xf * Art.SHOULDER_BACK, xf * Art.REST_HANDS[0], pal, true, UNIT_PX)
	Art.draw_body(ci, xf, pal, stance)
	Art.draw_arm(ci, xf * Art.SHOULDER_FRONT, xf * Art.REST_HANDS[1], pal, false, UNIT_PX)


## Rend `count` images d'une animation avec la fonction de dessin `draw_fn(ci, k)`.
func _bake(base: String, manifest: Dictionary, name: String, count: int, size: Vector2i, pivot: Vector2,
		loop: bool, draw_fn: Callable, anchor: String = "self") -> void:
	if vp == null:
		vp = SubViewport.new()
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		painter = Node2D.new()
		painter.set_script(Painter)
		vp.add_child(painter)
	vp.size = size
	var dir_name := name.replace("/", "__")
	var abs_dir := ProjectSettings.globalize_path(base + "/" + dir_name)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	for k in count:
		painter.job = draw_fn.bind(k)
		painter.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png("%s/%04d.png" % [abs_dir, k + 1])
	manifest.anims[name] = {"dir": dir_name, "count": count, "loop": loop, "pivot": [pivot.x, pivot.y], "anchor": anchor}
