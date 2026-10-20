extends Node2D
## Démonstration des projections : chaque technique jouée en boucle, avec les judokas 3D
## et le décor du combat. Sert à juger une chorégraphie en mouvement — c'est le seul
## moyen de voir ce qu'une planche d'images fixes ne montre pas.
##
##   godot --path . -- --screen=demo [--anim=seoi_nage] [--decor=dojo]
##   godot --path . -- --screen=demo --kumikata[=sleeve,lapel] [--lead=R,L --gap=38 --zoom=5]
##   godot --path . -- --screen=demo --sol=osaekomi:kesa_gatame [--fc=-1 --zoom=3]
## (bancs d'essai des saisies et du ne-waza en 3D ; avec --capture=<dossier> --frames=60)
##
## ← → change de technique, A met en pause, ↑ ↓ règle la vitesse, B revient au menu.
## Les techniques dont la chorégraphie a été relevée sur vidéo (data/anims/) passent en
## premier et sont signalées à l'écran.

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const Anims := preload("res://scripts/view/throw_anims.gd")
const Models3D := preload("res://scripts/view/models3d.gd")
const Stages := preload("res://scripts/stages.gd")
const GameData := preload("res://scripts/game_data.gd")
const Skins := preload("res://scripts/skins.gd")

# mêmes valeurs que l'écran de combat : c'est le cadrage qu'il faut juger
const K := 2.2
const FEET := 604.0
const MAT_BACK := 556.0
const CAM_Y := 464.0         # centre de la caméra (monde)
const ZOOM := 1.8
const ARRET_DEBUT := 14      # ticks d'arrêt sur la garde, avant l'entrée
const ARRET_FIN := 26        # ticks d'arrêt sur la chute

var app
var m3d
var techs: Array = []
var i_tech := 0
var t := 0                   # tick dans la boucle courante
var duree := 48              # ticks de projection (vitesse)
var pause := false
var auto := true             # enchaîne les techniques sans rien toucher
var noms: Dictionary = {}


func on_enter(p: Dictionary) -> void:
	noms = GameData.load_json("res://data/catalog.json").get("technique", {})
	techs = _techniques()
	if app != null and app.args.has("anim"):
		var k: int = techs.find(String(app.args.anim))
		if k >= 0:
			i_tech = k
	if String(p.get("tech", "")) != "":
		var k2: int = techs.find(String(p.tech))
		if k2 >= 0:
			i_tech = k2
	if Art.use_3d() and DisplayServer.get_name() != "headless":
		m3d = Models3D.new()
		add_child(m3d)
		var dir := String(app.args.get("models3d", Models3D.DEFAULT_DIR)) if app != null \
			else Models3D.DEFAULT_DIR
		var qui := [Skins.dir_for(Skins.default_id(), 0), Skins.dir_for(Skins.default_id(), 1)]
		if app != null and app.args.has("models3d_who"):
			qui = Array(String(app.args.models3d_who).split(",", false))
		if not m3d.setup(dir, qui, K, FEET):
			m3d = null
		else:
			m3d.instant_turn = true


func tick() -> void:
	if not pause:
		t += 1
		if t > ARRET_DEBUT + duree + ARRET_FIN:
			t = 0
			if auto:
				i_tech = (i_tech + 1) % techs.size()   # on enchaîne tout seul
	queue_redraw()


func nav(action: String, _player: int = 0) -> void:
	match action:
		"right", "next":
			i_tech = (i_tech + 1) % techs.size()
			t = 0
			auto = false                  # on prend la main
		"left", "prev":
			i_tech = (i_tech + techs.size() - 1) % techs.size()
			t = 0
			auto = false
		"up":
			duree = maxi(18, duree - 6)      # plus court = plus rapide
		"down":
			duree = mini(150, duree + 6)
		"accept":
			pause = not pause
		"back":
			app.goto("menu", {})
	queue_redraw()


## Avancement de la projection, avec les temps d'arrêt au départ et à l'arrivée.
func _p() -> float:
	if t < ARRET_DEBUT:
		return 0.0
	return clampf(float(t - ARRET_DEBUT) / float(duree), 0.0, 1.0)


func _draw() -> void:
	if app != null and app.args.has("kumikata"):
		_draw_kumikata()
		return
	if app != null and app.args.has("sol"):
		_draw_sol(String(app.args.sol))
		return
	var tech: String = techs[i_tech]
	var ks: Array = Anims.keys(tech, 54.0)
	var smp: Dictionary = Anims.sample(ks, _p())
	var frame := Transform2D(0.0, Vector2(K, K), 0.0, Vector2(640, FEET))
	var cx := _centre(smp, frame)
	_draw_decor(cx)
	if m3d != null:
		m3d.clock = t
		m3d.update_camera(Vector2(_centre(smp, frame), CAM_Y), ZOOM, Vector2.ZERO)
		var sh = m3d.pose_rig(0, Anims.actor_xform(frame, smp.tori), smp.tori.pose, [], true)
		m3d.pose_rig(1, Anims.actor_xform(frame, smp.uke), smp.uke.pose, [], false, sh)
		draw_texture(m3d.texture(), Vector2.ZERO)
	else:
		# dessin de secours : on reproduit à la main le cadrage de la caméra 3D
		draw_set_transform(Vector2(640, 360) - Vector2(cx, CAM_Y) * ZOOM,
			0.0, Vector2(ZOOM, ZOOM))
		var ordre := ["tori", "uke"] if Anims.family(tech) == "sacrifice" else ["uke", "tori"]
		for who in ordre:
			var a: Dictionary = smp[who]
			Art.draw_fighter(self, Anims.actor_xform(frame, a),
				Art.palette(0 if who == "tori" else 1), a.pose)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_hud(tech)


## Milieu des deux judokas : la caméra les suit, sinon ils sortent du cadre.
func _centre(smp: Dictionary, frame: Transform2D) -> float:
	var a: Vector2 = Anims.actor_xform(frame, smp.tori).origin
	var b: Vector2 = Anims.actor_xform(frame, smp.uke).origin
	return clampf((a.x + b.x) * 0.5, 640.0 / ZOOM, 1280.0 - 640.0 / ZOOM)


func _draw_decor(cx: float) -> void:
	# la caméra est centrée sur (cx, CAM_Y) au zoom ZOOM : un point du monde (x, y) tombe
	# à l'écran en 640 + (x − cx)·ZOOM, 360 + (y − CAM_Y)·ZOOM. Le décor suit la même
	# règle, sinon les judokas flottent au-dessus du tatami.
	var bord := 360.0 + (MAT_BACK - CAM_Y) * ZOOM
	var st: Dictionary = Stages.current()
	var tex: Texture2D = Stages.texture(st)
	if tex != null:
		draw_rect(Rect2(0, 0, 1280, bord), Color("0f0b24"))
		draw_texture_rect(tex, Stages.rect(tex, st, 1280.0, bord), false)
	else:
		for k in 20:
			var f := float(k) / 20.0
			draw_rect(Rect2(0, bord * f, 1280, bord / 20 + 1),
				Color("120e26").lerp(Color("2a1f5e"), f))
	draw_rect(Rect2(0, bord, 1280, 720 - bord), Style.MAT_COMBAT)
	draw_rect(Rect2(0, bord, 1280, 5), Style.MAT_COMBAT.darkened(0.45))
	# ligne de zone de combat, pour donner l'échelle
	var sol := 360.0 + (FEET - CAM_Y) * ZOOM
	draw_line(Vector2(0, sol), Vector2(1280, sol), Style.MAT_COMBAT.darkened(0.25), 3.0)


func _draw_hud(tech: String) -> void:
	var filmee: bool = Anims.has_mocap(tech)
	Style.panel(self, Rect2(-20, 18, 560, 86), Style.NIGHT_2, Style.INK, 4.0, 6.0, 0.1)
	Style.text(self, Vector2(34, 74), tech.to_upper().replace("_", "-"), 40,
		Style.PAPER, "display", HORIZONTAL_ALIGNMENT_LEFT, -1, 2, -1.0)
	var fam := String(noms.get(tech, {}).get("family", ""))
	Style.label(self, Vector2(36, 96), ("FILMÉE" if filmee else "DESSINÉE") +
		("  ·  " + fam if fam != "" else ""), 15,
		Style.GOOD if filmee else Style.MUTED, "black")
	Style.label(self, Vector2(1240 - 200, 54), "%d / %d" % [i_tech + 1, techs.size()],
		18, Style.MUTED, "black", HORIZONTAL_ALIGNMENT_RIGHT, 200)
	# jauge d'avancement
	draw_rect(Rect2(40, 686, 1200, 6), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(40, 686, 1200 * _p(), 6), Style.HOT)
	if auto:
		Style.label(self, Vector2(1040, 96), "DÉFILEMENT AUTOMATIQUE", 13, Style.MUTED,
			"black", HORIZONTAL_ALIGNMENT_RIGHT, 200)
	Style.hints(self, [["←→", "Technique"], ["↑↓", "Vitesse"],
		["A", "Pause" if not pause else "Reprendre"], ["B", "Retour"]])


## Les techniques du jeu, celles relevées sur vidéo en premier.
func _techniques() -> Array:
	var t2: Dictionary = GameData.load_json("res://data/techniques.json")
	var out := []
	for k in t2:
		if not String(k).begins_with("_"):
			out.append(k)
	out.sort()
	out.sort_custom(func(a, b): return int(Anims.has_mocap(a)) > int(Anims.has_mocap(b)))
	return out


## Banc d'essai du kumikata (--kumikata[=sleeve,lapel|collar,…] --gap=40 --zoom=2.6) : les
## deux judokas en garde, les mains partent chercher le judogi puis tiennent. Sert à juger
## les saisies des modèles 3D sans dépendre d'un combat.
func _draw_kumikata() -> void:
	var gap := float(app.args.get("gap", "40"))
	var zoom := float(app.args.get("zoom", "2.6"))
	var pts := String(app.args.kumikata).split(",") if String(app.args.kumikata) not in ["", "true", "1"] else PackedStringArray(["sleeve", "lapel"])
	var w := clampf(float(t - 10) / 30.0, 0.0, 1.0)
	w = w * w * (3.0 - 2.0 * w)
	var cx := 640.0
	var xa := cx - gap * K * 0.5
	var xb := cx + gap * K * 0.5
	_draw_decor(cx)
	if m3d == null:
		return
	m3d.clock = t
	m3d.update_camera(Vector2(cx, float(app.args.get("cam_y", "470"))), zoom, Vector2.ZERO)
	for i in 2:
		var face := 1 if i == 0 else -1
		var xf := Transform2D(0.0, Vector2(face * K, K), 0.0, Vector2(xa if i == 0 else xb, FEET))
		var pose: Dictionary = Art.pose_stand(float(app.args.get("stance", "0.5")))
		pose.bow = float(app.args.get("bow", "0.18"))
		pose.hip += Vector2(float(app.args.get("hipx", "-3")), float(app.args.get("drop", "2")))
		pose.erase("kb")
		pose.erase("kf")
		pose.lead = String(app.args.get("lead", "R,R")).split(",")[i]
		var tg := []
		for k in 2:
			tg.append({"opp": 1 - i, "pt": pts[k] if k < pts.size() else "lapel", "w": w})
		m3d.pose_rig(i, xf, pose, [], true, null, [0.8 if w >= 1.0 else -1.0, 0.8 if w >= 1.0 else -1.0], tg)
	# seconde passe : chacun voit la pose de l'autre de cette image
	for i in 2:
		var face := 1 if i == 0 else -1
		var xf := Transform2D(0.0, Vector2(face * K, K), 0.0, Vector2(xa if i == 0 else xb, FEET))
		var pose: Dictionary = Art.pose_stand(float(app.args.get("stance", "0.5")))
		pose.bow = float(app.args.get("bow", "0.18"))
		pose.hip += Vector2(float(app.args.get("hipx", "-3")), float(app.args.get("drop", "2")))
		pose.erase("kb")
		pose.erase("kf")
		pose.lead = String(app.args.get("lead", "R,R")).split(",")[i]
		var tg := []
		for k in 2:
			tg.append({"opp": 1 - i, "pt": pts[k] if k < pts.size() else "lapel", "w": w})
		m3d.pose_rig(i, xf, pose, [], true, null, [0.8 if w >= 1.0 else -1.0, 0.8 if w >= 1.0 else -1.0], tg)
	draw_texture(m3d.texture(), Vector2.ZERO)
	Style.label(self, Vector2(40, 60), "KUMIKATA · %s · écart %d" % [",".join(pts), int(gap)], 20, Style.PAPER, "black")


## Banc d'essai du ne-waza (--sol=osaekomi:kesa_gatame, transition, kansetsu:juji_gatame…) :
## les deux poses au sol de fighter_art, en 3D, comme dans le combat.
func _draw_sol(kind: String) -> void:
	var zoom := float(app.args.get("zoom", "2.2"))
	var fc := int(app.args.get("fc", "1"))
	var poses: Array = Art.ground_poses(kind, t, float(app.args.get("ctrl", "0.8")))
	var center: float = poses[0].get("center", 12.0)
	var origin := Vector2(640.0 - fc * center * K, FEET + 4.0)
	var xf := Transform2D(0.0, Vector2(fc * K, K), 0.0, origin)
	_draw_decor(640.0)
	if m3d == null:
		return
	m3d.clock = t
	m3d.update_camera(Vector2(640.0, float(app.args.get("cam_y", "532"))), zoom, Vector2.ZERO)
	m3d.pose_ground(1, xf, poses[1])
	m3d.pose_ground(0, xf, poses[0])
	draw_texture(m3d.texture(), Vector2.ZERO)
	Style.label(self, Vector2(40, 60), kind.to_upper(), 22, Style.PAPER, "black")

