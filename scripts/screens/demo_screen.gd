extends Node2D
## Démonstration des projections : chaque technique jouée en boucle, avec les judokas 3D
## et le décor du combat. Sert à juger une chorégraphie en mouvement — c'est le seul
## moyen de voir ce qu'une planche d'images fixes ne montre pas.
##
##   godot --path . -- --screen=demo [--anim=seoi_nage] [--decor=dojo]
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

const K := 2.6
const FEET := 610.0
const MAT_BACK := 556.0
const CAM_Y := 430.0         # centre de la caméra 3D (monde)
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
	var tech: String = techs[i_tech]
	var ks: Array = Anims.keys(tech, 54.0)
	var smp: Dictionary = Anims.sample(ks, _p())
	var frame := Transform2D(0.0, Vector2(K, K), 0.0, Vector2(640, FEET))
	_draw_decor()
	if m3d != null:
		m3d.clock = t
		m3d.update_camera(Vector2(640, CAM_Y), 1.0, Vector2.ZERO)
		var sh = m3d.pose_rig(0, Anims.actor_xform(frame, smp.tori), smp.tori.pose, [], true)
		m3d.pose_rig(1, Anims.actor_xform(frame, smp.uke), smp.uke.pose, [], false, sh)
		draw_texture(m3d.texture(), Vector2.ZERO)
	else:
		var ordre := ["tori", "uke"] if Anims.family(tech) == "sacrifice" else ["uke", "tori"]
		for who in ordre:
			var a: Dictionary = smp[who]
			Art.draw_fighter(self, Anims.actor_xform(frame, a),
				Art.palette(0 if who == "tori" else 1), a.pose)
	_draw_hud(tech)


func _draw_decor() -> void:
	# la caméra 3D est centrée sur CAM_Y : un point du monde y tombe à l'écran en
	# 360 + (y − CAM_Y). Le décor doit suivre la même règle, sinon les judokas flottent
	# au-dessus du tatami.
	var bord := 360.0 + (MAT_BACK - CAM_Y)
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
	var sol := 360.0 + (FEET - CAM_Y)
	draw_line(Vector2(120, sol), Vector2(1160, sol), Style.MAT_COMBAT.darkened(0.25), 3.0)


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
