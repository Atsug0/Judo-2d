extends SceneTree
## Compare une projection dessinée (squelette 2D du jeu) et sa version 3D, image par image.
##   godot --path . -s tools/rig/compare_anim.gd -- --tech=seoi_nage --out=/tmp/cmp --steps=0,0.3,0.45,0.55,0.7,0.85,1
## Écrit une planche : en haut le dessin, en bas les judokas 3D, pour chaque avancement.

const Art := preload("res://scripts/view/fighter_art.gd")
const Anims := preload("res://scripts/view/throw_anims.gd")
const Models3D := preload("res://scripts/view/models3d.gd")
var K := 2.2
const FEET := 600.0


class Canvas extends Node2D:
	var smp: Dictionary
	var frame: Transform2D
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1280, 720), Color("17132b"))
		draw_line(Vector2(0, 600), Vector2(1280, 600), Color("e9b62c"), 3.0)
		for who in ["uke", "tori"]:
			var a: Dictionary = smp[who]
			Art.draw_fighter(self, Anims.actor_xform(frame, a), Art.palette(0 if who == "tori" else 1), a.pose)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for x in OS.get_cmdline_user_args():
		var kv := x.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var tech := String(args.get("tech", "seoi_nage"))
	var steps := String(args.get("steps", "0,0.3,0.45,0.55,0.7,0.85,1")).split(",")
	var who := String(args.get("who", "homme_blanc,homme_bleu")).split(",")
	K = float(args.get("k", "2.2"))
	var crop_r := Rect2i(400, 220, 520, 487)
	if args.has("crop"):
		var c := String(args.crop).split(",")
		crop_r = Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3]))
	var ks: Array = Anims.keys(tech, 54.0)
	var frame := Transform2D(0.0, Vector2(K, K), 0.0, Vector2(float(args.get("x0", "560")), FEET))
	var cv := Canvas.new()
	get_root().add_child(cv)
	var m = Models3D.new()
	get_root().add_child(m)
	m.setup(Models3D.DEFAULT_DIR, Array(who), K, FEET)
	m.instant_turn = true
	m.update_camera(Vector2(float(args.get("cx", "640")), float(args.get("cy", "420"))), float(args.get("zoom", "1")), Vector2.ZERO)
	var tex_node := Sprite2D.new()
	tex_node.centered = false
	tex_node.texture = m.texture()
	tex_node.visible = false
	get_root().add_child(tex_node)
	var shots := []
	for st in steps:
		var smp: Dictionary = Anims.sample(ks, float(st))
		cv.smp = smp
		cv.frame = frame
		cv.visible = true
		tex_node.visible = false
		cv.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var a: Image = get_root().get_texture().get_image()
		var sh = m.pose_rig(0, Anims.actor_xform(frame, smp.tori), smp.tori.pose, [], true)
		m.pose_rig(1, Anims.actor_xform(frame, smp.uke), smp.uke.pose, [], false, sh)
		cv.visible = true
		cv.smp = {"tori": smp.tori, "uke": smp.uke}
		# fond seul + 3D
		var bg := Canvas.new()
		tex_node.visible = true
		cv.visible = false
		var under := ColorRect.new()
		under.color = Color("17132b")
		under.size = Vector2(1280, 720)
		get_root().add_child(under)
		get_root().move_child(under, 0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var b: Image = get_root().get_texture().get_image()
		under.queue_free()
		shots.append([a, b])
	var cw := int(args.get("cw", "320"))
	var ch := int(float(cw) * crop_r.size.y / crop_r.size.x)
	var sheet := Image.create(cw * shots.size(), ch * 2, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		for r in 2:
			var im: Image = shots[i][r]
			im.convert(Image.FORMAT_RGBA8)
			var crop := im.get_region(crop_r)
			crop.resize(cw, ch)
			sheet.blit_rect(crop, Rect2i(0, 0, cw, ch), Vector2i(i * cw, r * ch))
	sheet.save_png(String(args.get("out", "/tmp/cmp")) + "_" + tech + ".png")
	print("planche : ", tech)
	quit()
