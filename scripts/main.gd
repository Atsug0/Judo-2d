extends Node2D
## Point d'entrée : gestion des écrans, navigation manette, mode capture.
##
## Arguments (après `--`) :
##   --screen=title|menu|match|customize|...   écran de départ
##   --capture=<dossier>                       mode capture d'écran (quitte à la fin)
##   --until=<tick> --ticks=a,b,c --events     (combat) instants à capturer
##   --frames=<n> --nav=down,down,accept       (menus) animer puis naviguer avant la capture
##   --seed=<n> --level=<1..3>                 combat IA
##   --demo=<fichier.json>                     pilotage scripté des menus (vidéos de présentation)

const SCREENS := {
	"title": "res://scripts/screens/title_screen.gd",
	"menu": "res://scripts/screens/menu_screen.gd",
	"match": "res://scripts/screens/match_screen.gd",
	"customize": "res://scripts/screens/customize_screen.gd",
	"select": "res://scripts/screens/select_screen.gd",
	"tournament": "res://scripts/screens/tournament_screen.gd",
	"results": "res://scripts/screens/results_screen.gd",
	"options": "res://scripts/screens/options_screen.gd",
	"online": "res://scripts/screens/online_screen.gd",
	"art": "res://scripts/screens/art_screen.gd",
	"lineup": "res://scripts/screens/lineup_screen.gd",
	"bake": "res://scripts/screens/bake_screen.gd",
	"vs": "res://scripts/screens/vs_screen.gd",
	"dojo": "res://scripts/screens/dojo_screen.gd",
	"challenges": "res://scripts/screens/challenges_screen.gd",
}

const NAV_BUTTONS := {
	"accept": JOY_BUTTON_A, "back": JOY_BUTTON_B, "start": JOY_BUTTON_START,
	"x": JOY_BUTTON_X, "y": JOY_BUTTON_Y, "prev": JOY_BUTTON_LEFT_SHOULDER, "next": JOY_BUTTON_RIGHT_SHOULDER,
	"select": JOY_BUTTON_BACK, "up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT,
}
const REPEAT_DELAY := 18
const REPEAT_EVERY := 6

var current: Node2D
var current_name := ""
var capture_mode := false
var args := {}
var last_match_params := {}
## État de la session de jeu (tournoi en cours, etc.).
var session := {}
var _held := {}  # "device:action" -> frames tenus
var _demo: Array = []  # [[image, action], ...] : navigation scriptée
var _demo_frame := 0
## Transition entre écrans : bandes inclinées qui se retirent.
var _trans_layer: CanvasLayer
var _trans_draw: Node2D
var _trans_t := 99
const TRANS_FRAMES := 20


func _setup_transition() -> void:
	_trans_layer = CanvasLayer.new()
	_trans_layer.layer = 10
	add_child(_trans_layer)
	_trans_draw = Node2D.new()
	_trans_draw.set_script(load("res://scripts/ui/draw_proxy.gd"))
	_trans_draw.fn = Callable(self, "_draw_transition")
	_trans_layer.add_child(_trans_draw)


func _draw_transition(ci: CanvasItem) -> void:
	if _trans_t >= TRANS_FRAMES:
		return
	var Style = load("res://scripts/ui/style.gd")
	var cols := [Style.HOT, Style.P1, Style.P2, Style.INK]
	var p := float(_trans_t) / float(TRANS_FRAMES)
	for k in cols.size():
		# chaque bande part un peu après la précédente, vers la droite
		var q := clampf(p * 1.6 - k * 0.15, 0.0, 1.0)
		q = q * q * (3.0 - 2.0 * q)
		var x0 := -200.0 + q * 2000.0
		var pts := PackedVector2Array([Vector2(x0, 0), Vector2(x0 + 2100, 0), Vector2(x0 + 2100 - 360, 720), Vector2(x0 - 360, 720)])
		ci.draw_colored_polygon(pts, cols[cols.size() - 1 - k])


var _results_frames := 0


func _ready() -> void:
	_setup_transition()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	capture_mode = args.has("capture")
	if not capture_mode:
		preload("res://scripts/settings.gd").apply()
	if args.has("demo"):
		var f := FileAccess.open(String(args.demo), FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_demo = d.get("steps", [])
	var start: String = args.get("screen", "title")
	var params := {}
	if start == "match" or start == "vs":
		params = default_match_params()
	if args.has("lesson") or args.has("training"):
		start = "match"
		var dcfg := {"mode": "training", "partner": String(args.get("partner", "garde"))} if args.has("training") else {"mode": "lesson", "lesson": String(args.lesson)}
		params = preload("res://scripts/dojo/dojo_session.gd").match_params(dcfg, human_controller())
	goto(start, params)
	if capture_mode:
		_run_capture.call_deferred()


func default_match_params() -> Dictionary:
	var pads := Input.get_connected_joypads()
	var c1 := human_controller()
	var c2 := "pad1" if pads.size() >= 2 and not capture_mode else "ai"
	var BuildS = preload("res://scripts/build.gd")
	var bs: Array = BuildS.defaults()
	# --p1build / --p2build : indice d'un build par défaut, ou identifiant de légende (ex. lame, mur)
	var a1: String = String(args.get("p1build", "0"))
	var a2: String = String(args.get("p2build", "1"))
	var b1: Dictionary = bs[int(a1)] if a1.is_valid_int() else BuildS.find(a1)
	var b2: Dictionary = bs[int(a2)] if a2.is_valid_int() else BuildS.find(a2)
	return {"controllers": [c1, c2], "names": [b1.name, b2.name], "tokui": [b1.slots.tokui[0], b2.slots.tokui[0]], "builds": [b1, b2],
		"sprites": String(args.get("sprites", "")), "seed": int(args.get("seed", "3")), "level": int(args.get("level", str(preload("res://scripts/settings.gd").value("ai_level")))), "mode": "demo"}


## Contrôleur du joueur humain : selon le réglage « périphérique », manette 0 si elle
## est branchée, sinon le clavier. Toujours l'IA en mode capture (démos et vidéos).
func human_controller() -> String:
	var choix := String(preload("res://scripts/settings.gd").value("peripherique"))
	var pads := Input.get_connected_joypads().size()
	# sans manette branchée, le clavier plutôt que la démo IA — sauf si le joueur impose la manette
	var clavier := choix == "clavier" or (choix != "manette" and pads == 0)
	# les aides en combat et les leçons affichent les touches plutôt que les boutons
	preload("res://scripts/ui/style.gd").clavier = clavier
	if capture_mode:
		return "ai"
	if clavier:
		return "clavier"
	return "pad0" if pads >= 1 else "ai"


func goto(screen_name: String, params: Dictionary = {}) -> void:
	if current != null:
		current.queue_free()
	current = Node2D.new()
	var scr = load(SCREENS[screen_name])
	current.set_script(scr)
	if not current.has_method("on_enter"):
		push_error("Écran invalide (erreur de script) : " + screen_name)
		if capture_mode:
			get_tree().quit(2)
		return
	current.set("app", self)
	current_name = screen_name
	add_child(current)
	if screen_name == "match":
		last_match_params = params
	elif screen_name == "vs" and params.is_empty():
		params = default_match_params()
	current.on_enter(params)
	current.queue_redraw()
	_screen_audio(screen_name)
	if not capture_mode:
		_trans_t = 0


## Musique et ambiance associées à chaque écran.
const SCREEN_MUSIC := {"title": "menu", "menu": "menu", "customize": "menu", "select": "menu",
	"tournament": "menu", "options": "menu", "online": "menu", "art": "menu", "challenges": "menu",
	"match": "match", "dojo": "dojo", "results": "victory", "vs": ""}


func _screen_audio(screen_name: String) -> void:
	if capture_mode:
		return
	if SCREEN_MUSIC.has(screen_name):
		Sound.music(SCREEN_MUSIC[screen_name], 0.4 if screen_name == "vs" else 0.8)
	Sound.crowd(screen_name in ["match", "vs"])


func _physics_process(_delta: float) -> void:
	if capture_mode or current == null:
		return
	if _trans_t < TRANS_FRAMES:
		_trans_t += 1
		_trans_draw.queue_redraw()
	_poll_nav()
	_run_demo()
	if args.has("quit_results") and current_name == "results":
		# vidéos : on arrête l'enregistrement un peu après l'écran de résultats
		_results_frames += 1
		if _results_frames >= int(args.quit_results):
			get_tree().quit()
			return
	if current.has_method("tick"):
		current.tick()


func _run_demo() -> void:
	if _demo.is_empty():
		return
	_demo_frame += 1
	while not _demo.is_empty() and int(_demo[0][0]) <= _demo_frame:
		var action: String = _demo.pop_front()[1]
		if args.has("demo_log"):
			print("démo ", _demo_frame, " ", current_name, " ← ", action)
		if action == "quit":
			get_tree().quit()
			return
		if action.begins_with("goto:"):
			goto(action.trim_prefix("goto:"), default_match_params() if action.ends_with("match") else {})
			continue
		if action == "force_win" and current_name == "match":
			# vidéos : victoire immédiate du joueur 1 (parcours du tournoi sans jouer chaque combat)
			var st: Dictionary = current.sim.get_state()
			st.winner = 0
			st.win_reason = "Ippon — Uchi-mata"
			st.fighters[0].ippon = 1
			goto("results", {"state": st, "names": current.names, "stats": current.stats, "match_params": current.params})
			continue
		Sound.ui(action)
		current.nav(action, 0)


func _poll_nav() -> void:
	for device in [0, 1]:
		for action in NAV_BUTTONS:
			var down := Input.is_joy_button_pressed(device, NAV_BUTTONS[action])
			match action:
				"up":
					down = down or Input.get_joy_axis(device, JOY_AXIS_LEFT_Y) < -0.6
				"down":
					down = down or Input.get_joy_axis(device, JOY_AXIS_LEFT_Y) > 0.6
				"left":
					down = down or Input.get_joy_axis(device, JOY_AXIS_LEFT_X) < -0.6
				"right":
					down = down or Input.get_joy_axis(device, JOY_AXIS_LEFT_X) > 0.6
			_edge("%d:%s" % [device, action], down, action, device)
	# Clavier : confort de développement uniquement (le jeu se joue à la manette).
	var keys := {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
		"accept": KEY_ENTER, "back": KEY_ESCAPE, "start": KEY_P, "select": KEY_R, "x": KEY_X}
	for action in keys:
		_edge("k:%s" % action, Input.is_physical_key_pressed(keys[action]), action, 0)


func _edge(key: String, down: bool, action: String, device: int) -> void:
	if not down:
		_held.erase(key)
		return
	var n: int = _held.get(key, 0)
	_held[key] = n + 1
	var directional := action in ["up", "down", "left", "right"]
	if n == 0 or (directional and n >= REPEAT_DELAY and (n - REPEAT_DELAY) % REPEAT_EVERY == 0):
		# en plein combat, les boutons pilotent le judoka : pas de bruit de menu
		var in_fight: bool = current_name == "match" and not current.get("paused") and action != "start"
		if not in_fight:
			Sound.ui(action)
		current.nav(action, device)


# --- Mode capture --------------------------------------------------------------

func _run_capture() -> void:
	var dir: String = args.capture
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().process_frame
	if current.has_method("run_bake"):
		await current.run_bake()
		get_tree().quit()
		return
	if current_name == "match" and not args.has("frames"):
		var until := int(args.get("until", "4000"))
		var max_shots := int(args.get("max", "10"))
		var wanted := {}
		if args.has("ticks"):
			for t in String(args.ticks).split(","):
				wanted[int(t)] = true
		var shots := 0
		var last_t := -1
		var settle := int(args.get("settle", "0"))  # images d'effets à laisser passer avant la capture
		while current.sim.state.tick < until and shots < max_shots:
			current.tick()
			var t: int = current.sim.state.tick
			if t < last_t:
				last_t = -1  # nouvelle manche : le chrono de la simulation repart de zéro
			if t == last_t:
				continue  # arrêt sur image / ralenti : même instant de simulation
			if wanted.has(t) or (args.has("events") and current.capture_flag) or (args.has("attack") and current.attack_flag and t > int(args.get("after", "0"))):
				for k in settle:
					current.tick()
				await _shot("%s/match_%05d.png" % [dir, t])
				last_t = current.sim.state.tick
				shots += 1
			if current.sim.state.phase == "ended" and current.end_timer > 30 and not args.has("bo3"):
				break
	else:
		var frames := int(args.get("frames", "20"))
		for k in frames:
			if current.has_method("tick"):
				current.tick()
		if args.has("nav"):
			for action in String(args.nav).split(","):
				var parts := action.split(":")
				current.nav(parts[0], int(parts[1]) if parts.size() > 1 else 0)
				for k in 4:
					if current.has_method("tick"):
						current.tick()
		await _shot("%s/%s.png" % [dir, args.get("name", current_name)])
	get_tree().quit()


func _shot(path: String) -> void:
	current.queue_redraw()
	await RenderingServer.frame_post_draw
	current.queue_redraw()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
