extends Node2D
## Planche de personnages (outil de travail) : les deux judokas en grand, plusieurs poses.

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const Anims := preload("res://scripts/view/throw_anims.gd")

var app


func on_enter(_params: Dictionary) -> void:
	pass


func nav(action: String, _player: int = 0) -> void:
	if action == "back":
		app.goto("menu", {})


func _draw() -> void:
	Style.menu_background(self, Vector2(1280, 720), Style.HOT)
	Style.header(self, "PLANCHE PERSO", "Placeholders cel-shading — en attendant le rendu Blender", Style.PAPER)
	if app != null and app.args.has("zoom"):
		_draw_zoom()
		return
	if app != null and app.args.has("ground"):
		_draw_ground()
		return
	if app != null and app.args.has("anim"):
		_draw_anim(String(app.args.anim))
		return
	# grands portraits
	var poses = [
		{"x": 230.0, "p": 0, "lean": 0.0, "stance": 0.4, "label": "GARDE"},
		{"x": 520.0, "p": 1, "lean": 0.0, "stance": 0.4, "label": "GARDE"},
		{"x": 810.0, "p": 0, "lean": 0.22, "stance": 1.0, "label": "KUZUSHI AVANT"},
		{"x": 1080.0, "p": 1, "lean": -0.2, "stance": 0.2, "label": "DÉSÉQUILIBRE ARRIÈRE"},
	]
	for po in poses:
		var sc = 4.2
		var feet = Vector2(po.x, 660)
		var xf = Art.stand_xform(feet, 1 if po.p == 0 else -1, (1 if po.p == 0 else -1) * po.lean, sc, 0.0)
		var pal = Art.palette(po.p)
		Art.shadow(self, feet + Vector2(0, 2), sc, 0.4)
		Art.draw_arm(self, xf * Art.SHOULDER_BACK, xf * Art.REST_HANDS[0], pal, true, sc)
		Art.draw_body(self, xf, pal, po.stance)
		Art.draw_arm(self, xf * Art.SHOULDER_FRONT, xf * Art.REST_HANDS[1], pal, false, sc)
		var w = Style.text_width(po.label, 18, "black") + 30
		var r = Rect2(po.x - w / 2, 160, w, 30)
		Style.chip(self, r, Style.INK, pal.accent)
		Style.label(self, Vector2(r.position.x, r.position.y + 21), po.label, 18, pal.accent, "black", HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_zoom() -> void:
	# gros plan tête + bras, les deux judokas en kumikata
	var sc = 5.4
	var xa = Art.stand_xform(Vector2(520, 960), 1, 0.05, sc, 0.0)
	var xb = Art.stand_xform(Vector2(780, 960), -1, -0.03, sc, 0.0)
	var pa = Art.palette(0)
	var pb = Art.palette(1)
	Art.draw_arm(self, xb * Art.SHOULDER_BACK, xa * Art.GRIP_POINTS["sleeve"], pb, true, sc)
	Art.draw_arm(self, xa * Art.SHOULDER_BACK, xb * Art.GRIP_POINTS["sleeve"], pa, true, sc)
	Art.draw_body(self, xb, pb, 0.4)
	Art.draw_body(self, xa, pa, 0.4)
	Art.draw_arm(self, xb * Art.SHOULDER_FRONT, xa * Art.GRIP_POINTS["lapel"], pb, false, sc, 0.3)
	Art.draw_arm(self, xa * Art.SHOULDER_FRONT, xb * Art.GRIP_POINTS["lapel"], pa, false, sc, 0.6)


func _draw_ground() -> void:
	# planche des poses au sol
	var kinds = [["transition", "TRANSITION"], ["osaekomi:kesa_gatame", "KESA-GATAME"], ["osaekomi:yoko_shiho_gatame", "YOKO-SHIHO"],
		["osaekomi:kami_shiho_gatame", "KAMI-SHIHO"], ["kansetsu:juji_gatame", "JUJI-GATAME"], ["shime:okuri_eri_jime", "OKURI-ERI-JIME"]]
	for k in kinds.size():
		var col = k % 3
		var row = k / 3
		var origin = Vector2(150 + col * 400, 390 + row * 270)
		var sc = 2.3
		var xf = Transform2D(0.0, Vector2(sc, sc), 0.0, origin)
		var poses: Array = Art.ground_poses(kinds[k][0], 0, 0.8)
		Art.shadow(self, origin + Vector2(14 * sc, 2), sc * 1.6, 0.35)
		Art.draw_figure(self, xf, Art.palette(1), poses[1])
		Art.draw_figure(self, xf, Art.palette(0), poses[0], 0.6)
		var w = Style.text_width(kinds[k][1], 18, "black") + 30
		var r = Rect2(origin.x + 30 - w / 2, origin.y + 16, w, 30)
		Style.chip(self, r, Style.INK, Style.P1)
		Style.label(self, Vector2(r.position.x, r.position.y + 21), kinds[k][1], 18, Style.P1, "black", HORIZONTAL_ALIGNMENT_CENTER, w)


## Planche d'une projection : 8 étapes de l'animation, tori (blanc) et uke (bleu).
func _draw_anim(tech: String) -> void:
	var ks: Array = Anims.keys(tech, 54.0)
	var steps = [0.0, 0.15, 0.3, 0.45, 0.55, 0.68, 0.82, 1.0]
	var sc = 1.25
	for k in steps.size():
		var col = k % 4
		var row = k / 4
		var cell = Rect2(20 + col * 312, 150 + row * 280, 300, 268)
		draw_rect(cell, Color(0, 0, 0, 0.25))
		draw_line(Vector2(cell.position.x + 10, cell.end.y - 30), Vector2(cell.end.x - 10, cell.end.y - 30), Style.MAT_COMBAT, 3.0)
		var frame = Transform2D(0.0, Vector2(sc, sc), 0.0, Vector2(cell.position.x + 90, cell.end.y - 30))
		var smp: Dictionary = Anims.sample(ks, steps[k])
		var fam = Anims.family(tech)
		var order = ["tori", "uke"] if fam == "sacrifice" else ["uke", "tori"]
		for who in order:
			var a: Dictionary = smp[who]
			var xf: Transform2D = Anims.actor_xform(frame, a)
			Art.draw_fighter(self, xf, Art.palette(0 if who == "tori" else 1), a.pose)
		Style.label(self, Vector2(cell.position.x + 10, cell.position.y + 24), "p = %.2f" % steps[k], 16, Style.PAPER, "black")
	Style.text(self, Vector2(640, 128), tech.to_upper().replace("_", "-"), 34, Style.P1, "display")
