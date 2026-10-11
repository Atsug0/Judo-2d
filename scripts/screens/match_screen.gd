extends Node2D
## Écran de combat : fait tourner la simulation et dessine l'arène, les judokas et le HUD.

const Style := preload("res://scripts/ui/style.gd")
const Rich := preload("res://scripts/ui/rich.gd")
const Readout := preload("res://scripts/view/readout.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const GameData := preload("res://scripts/game_data.gd")
const Sim := preload("res://scripts/sim/match_sim.gd")
const Ai := preload("res://scripts/sim/ai_controller.gd")
const Pad := preload("res://scripts/pad_reader.gd")
const Settings := preload("res://scripts/settings.gd")
const SpriteLib := preload("res://scripts/view/sprite_library.gd")
const Anims := preload("res://scripts/view/throw_anims.gd")
const DojoSession := preload("res://scripts/dojo/dojo_session.gd")

const W := 1280.0
const H := 720.0
const FEET_Y := 604.0
const K := 2.2  # échelle des personnages
const MAT_BACK := 556.0
const MAT_FRONT := 652.0
const GRIP_LABELS := ["MANCHE", "REVERS", "COL HAUT", "CEINTURE"]

var app  # main.gd
var cfg: Dictionary
var techs: Dictionary
var sim
var controllers = ["ai", "ai"]  # "pad0", "pad1" ou "ai"
var ais = [null, null]
var names = ["J1", "J2"]
var feed: Array = []        # [{text, color, t}]
var popups: Array = []      # [{text, who, color, t}]
var shake = 0.0
var paused = false
var pause_index = 0
var end_timer = 0
var capture_flag = false   # demande de capture (mode capture d'écran)
var attack_flag = false    # une attaque est à mi-entrée
var frame = 0
var params: Dictionary = {}
var stats = []  # statistiques par joueur pour l'écran de résultats
var libs = [null, null]  # sprites par joueur (null = dessin placeholder)
## Calques : décor (parallaxe), monde (filmé par la caméra), HUD (fixe).
var layer_bg: Node2D
var layer_world: Node2D
var layer_hud: Node2D
var _ci: CanvasItem  # calque en cours de dessin
## Caméra : centre (coordonnées monde, px) et zoom, lissés.
var cam_c = Vector2(640, 380)
var cam_z = 1.0
var hitstop = 0       # images figées restantes (impact)
var slowmo_acc = 0    # compteur pour le ralenti
var flash = 0.0       # flash blanc (0..1)
var excite = 0.0      # excitation de la foule (0..1)
var particles: Array = []  # poussière : {p, v, life, max, size, col}
var shown = [null, null]  # squelettes affichés (lissés) : {xf, pose}
var ref_x = 790.0         # arbitre : position (monde, px) et sens du regard
var ref_face = -1
var ref_walk = 0.0
var ref_side = 1.0
var ref_walking = false
var dojo = null  # session de dojo (leçon ou entraînement), sinon null
var knock = [[0, 0], [0, 0]]
var impacts: Array = []          # chocs visuels (mains chassées, blocages…) : {p, col, s, t}
var walk_ph = [0.0, 0.0]         # cycle de marche, avancé à la distance réellement parcourue
var walk_amp = [0.0, 0.0]
var walk_dir = [1.0, 1.0]
var prev_dx = [-1.0, -1.0]  # main chassée : images restantes de l'animation, par joueur et par main
var last_reaction_popup = -9999
## Ralenti de l'ippon : derniers états de la simulation, rejoués à la fin du combat.
const REPLAY_KEEP := 300
var replay_buf: Array = []
var replay_ok = false      # le combat s'est fini sur une projection ippon
var replaying = false
var replay_i = 0
var replay_sub = 0
var replay_done = false
var replay_final = {}
var vel = [0.0, 0.0]          # vitesse affichée vers l'avant (px/image), lissée
var gap_shown = -1.0         # écart affiché entre les deux judokas (px), lissé
var tug = [[Vector2.ZERO, Vector2.ZERO], [Vector2.ZERO, Vector2.ZERO]]  # main qui tire / pousse
var grip_shake = [[0, 0], [0, 0]]  # prise attaquée : la main tremble
var chop = [0, 0]                  # combat de mains : coup sur la prise adverse (images restantes)
var chop_hand = [0, 0]             # main adverse visée
var osae_fx = {"top": 0, "bot": 0, "top_perfect": false, "bot_perfect": false, "top_miss": 0, "bot_miss": 0}
const PAUSE_ITEMS := ["REPRENDRE", "RECOMMENCER", "PERSONNALISATION", "MENU PRINCIPAL"]


func on_enter(p: Dictionary) -> void:
	params = p
	var Proxy = load("res://scripts/ui/draw_proxy.gd")
	for spec in [["bg", "_draw_layer_bg"], ["world", "_draw_layer_world"], ["hud", "_draw_layer_hud"]]:
		var n = Node2D.new()
		n.set_script(Proxy)
		n.fn = Callable(self, spec[1])
		add_child(n)
		set("layer_" + spec[0], n)
	stats = [_new_stats(), _new_stats()]
	cfg = GameData.load_json("res://data/config.json")
	techs = GameData.load_json("res://data/techniques.json")
	controllers = p.get("controllers", ["ai", "ai"])
	names = p.get("names", ["HUGO", "KENJI"])
	var tokui: Array = p.get("tokui", ["seoi_nage", "o_soto_gari"])
	var seed_value: int = p.get("seed", 1)
	var level: int = p.get("level", 2)
	sim = Sim.new(cfg, techs, names, p.get("builds", tokui))
	# Sprites : "placeholder" (images cuites) ou un identifiant de personnage par joueur.
	var sprite_set: String = p.get("sprites", "")
	if sprite_set != "":
		for i in 2:
			var cid = sprite_set
			if sprite_set == "placeholder":
				cid = "placeholder_blanc" if i == 0 else "placeholder_bleu"
			libs[i] = SpriteLib.load_character(cid)
	for i in 2:
		if controllers[i] == "ai":
			ais[i] = Ai.new(i, seed_value + i * 7, level)
	if p.has("dojo"):
		dojo = DojoSession.new(self, p.dojo)


func tick() -> void:
	frame += 1
	if paused:
		_redraw_all()
		return
	if replaying:
		_replay_tick()
		_update_fx()
		_redraw_all()
		return
	_update_fx()
	if hitstop > 0:
		hitstop -= 1
		_redraw_all()
		return
	if _slowmo_active():
		slowmo_acc += 1
		if slowmo_acc % 3 != 0:
			_redraw_all()
			return
	_step_sim()
	_redraw_all()


func _redraw_all() -> void:
	_update_camera()
	_update_referee()
	queue_redraw()
	for l in [layer_bg, layer_world, layer_hud]:
		if l != null:
			l.queue_redraw()


## Ralenti pendant le vol d'uke sur un ippon.
func _slowmo_active() -> bool:
	if sim.state.phase != "throw":
		return false
	var th: Dictionary = sim.state.throw
	return th.result == "ippon" and th.t >= cfg.throw_ticks * 35 / 100 and th.t < cfg.throw_ticks - 4


func _step_sim() -> void:
	var inputs = []
	for i in 2:
		match controllers[i]:
			"pad0":
				inputs.append(Pad.read(0))
			"pad1":
				inputs.append(Pad.read(1))
			"dojo":
				inputs.append(dojo.partner_input(sim))
			_:
				inputs.append(ais[i].think(sim))
	if dojo != null:
		inputs[0] = dojo.player_input(sim, inputs[0])
		dojo.pre_step(sim)
	if dojo == null:
		if sim.state.phase in ["fight", "throw"]:
			replay_buf.append(sim.get_state())
			if replay_buf.size() > REPLAY_KEEP:
				replay_buf.pop_front()
		elif sim.state.phase == "matte":
			replay_buf.clear()
	sim.step(inputs)
	_consume_events()
	if dojo != null:
		dojo.post_step(sim)
	_sound_frame()
	for p in popups:
		p.t += 1
	popups = popups.filter(func(p): return p.t < 70)
	for e in feed:
		e.t += 1
	if sim.state.phase == "ended":
		end_timer += 1
		if end_timer == 120 and replay_ok and not replay_done and (app == null or not app.capture_mode or app.args.has("replay")):
			_start_replay()
			return
		if end_timer == 200 and app != null and not app.capture_mode and dojo == null:
			app.goto("results", {"state": sim.get_state(), "names": names, "stats": stats, "match_params": params})


func nav(action: String, _player: int = 0) -> void:
	if dojo != null:
		if dojo.nav(action):
			queue_redraw()
		return
	if action == "start":
		paused = not paused
		pause_index = 0
	elif paused:
		match action:
			"up":
				pause_index = (pause_index + PAUSE_ITEMS.size() - 1) % PAUSE_ITEMS.size()
			"down":
				pause_index = (pause_index + 1) % PAUSE_ITEMS.size()
			"back":
				paused = false
			"accept":
				match pause_index:
					0:
						paused = false
					1:
						app.goto("match", app.last_match_params)
					2:
						app.goto("customize", {})
					3:
						app.goto("menu", {})
	queue_redraw()


## Palette du judoka i : judogi du côté (blanc/bleu), apparence de son build.
var _pals = [null, null]
func _pal(i: int) -> Dictionary:
	if _pals[i] == null:
		var bs = params.get("builds", [])
		var look = {}
		if bs is Array and bs.size() > i and bs[i] is Dictionary:
			look = bs[i].get("look", {})
		_pals[i] = Art.palette(i, look)
	return _pals[i]


func _new_stats() -> Dictionary:
	return {"attacks": 0, "throws": 0, "counters": 0, "breaks": 0, "feints": 0, "exposed": 0,
		"blocks": 0, "shidos": 0, "kuzushi_max": 0, "method": ""}


func _consume_events() -> void:
	capture_flag = false
	for i in 2:
		var o: Dictionary = sim.state.fighters[1 - i]
		var mag = maxi(absi(o.bal_x), absi(o.bal_y))
		stats[i].kuzushi_max = maxi(stats[i].kuzushi_max, mag)
	for e in sim.events:
		_sound_event(e)
		var who: int = e.get("who", -1)
		if who >= 0:
			var st: Dictionary = stats[who]
			match e.type:
				"attack":
					st.attacks += 1
				"throw":
					st.throws += 1
					st.method = sim.tech_name(e.tech)
				"counter":
					st.counters += 1
				"break":
					st.breaks += 1
				"feint":
					st.feints += 1
				"exposed":
					st.exposed += 1
				"block":
					st.blocks += 1
				"shido":
					st.shidos += 1
		var nm: String = names[who] if who >= 0 else ""
		var col: Color = Style.P1 if who == 0 else Style.P2
		match e.type:
			"attack":
				pass  # le nom de la technique s'affiche déjà au-dessus du judoka : pas de doublon dans le fil
			"throw":
				if e.result == "ippon":
					replay_ok = true
				var res = "IPPON" if e.result == "ippon" else "WAZA-ARI"
				_feed("%s : %s → %s" % [nm, sim.tech_name(e.tech), res], Style.GOLD)
			"counter":
				excite = maxf(excite, 0.8)
				_feed("%s contre : %s !" % [nm, sim.tech_name(e.tech)], Style.HOT)
				_popup("CONTRE !", who, Style.HOT)
			"exposed":
				_impact(_between(0.55), Style.DANGER, 1.0)
			"stuffed":
				_impact(_between(0.62), Style.PAPER, 1.1)
				hitstop = maxi(hitstop, 3)
			"block":
				_impact(_between(0.62), Style.PAPER, 1.3)
				hitstop = maxi(hitstop, 3)
				shake = maxf(shake, 3.0)
			"break":
				knock[1 - who][e.get("hand", 0)] = 14
				chop[who] = 12
				chop_hand[who] = e.get("hand", 0)
				_impact(_between(0.75), Style.GOOD, 0.8)
				hitstop = maxi(hitstop, 2)
				if e.get("how", "") == "deux_mains":
					_popup("DEUX MAINS !", who, Style.GOOD)
			"break_fail":
				grip_shake[1 - who][e.get("hand", 0)] = 12
				chop[who] = 10
				chop_hand[who] = e.get("hand", 0)
				_impact(_between(0.74), Style.PAPER, 0.5)
			"grip_tired":
				knock[who][e.get("hand", 0)] = 14
				_popup("AVANT-BRAS CUIT", who, Style.MUTED)
			"parry":
				knock[1 - who][e.hand] = 14
				_impact(_between(0.72), Style.P1 if who == 0 else Style.P2, 0.7)
				hitstop = maxi(hitstop, 2)
			"whiff":
				pass
			"dash":
				_dust(Vector2(_draw_x(who), FEET_Y), 6, 0.45)
				if sim.has_grip(sim.state.fighters[who]):
					shake = maxf(shake, 2.5)
			"reaction":
				if frame - last_reaction_popup > 600:
					_popup("ACTION-RÉACTION !", who, Style.GOLD)  # au plus une fois toutes les 10 s
					last_reaction_popup = frame
				_impact(_between(0.6), Style.GOLD, 1.2)
				excite = maxf(excite, 0.5)
			"feint":
				pass
			"shido":
				_feed("Shido %s : %s" % [nm, e.reason], Style.P1)
				capture_flag = true
			"golden":
				_feed("Golden score !", Style.GOLD)
			"combo_open":
				_popup("ENCHAÎNE !", who, Style.GOLD)
			"newaza":
				_feed("%s passe au sol" % nm, col)
			"osaekomi":
				excite = maxf(excite, 0.6)
				_feed("%s : osaekomi (%s)" % [nm, sim.tech_name(e.tech)], Style.GOLD)
				capture_flag = true
			"toketa":
				_popup("TOKETA", who, Style.PAPER)
			"osae_hit":
				osae_fx[e.role] = 12
				osae_fx[e.role + "_perfect"] = e.perfect
				if e.perfect:
					_popup("PARFAIT !", who, Style.GOLD)
					shake = maxf(shake, 2.0)
				_impact(_ground_center(), Style.P1 if who == 0 else Style.P2, 0.6)
			"osae_miss":
				osae_fx[e.role + "_miss"] = 16
			"reversal":
				_popup("RETOURNEMENT !", who, Style.HOT)
				_feed("%s attaque depuis la garde" % nm, col)
				excite = maxf(excite, 0.5)
			"escape":
				_popup("SORTIE !", who, Style.GOOD)
			"sub_start":
				_feed("%s tente %s" % [nm, sim.tech_name(e.tech)], Style.HOT)
				capture_flag = true
			"sub_escape":
				_popup("RÉSISTE !", who, Style.GOOD)
			"submission":
				_feed("%s : %s, maitta !" % [nm, sim.tech_name(e.tech)], Style.GOLD)
			"end":
				_feed("Victoire de %s — %s" % [nm, e.reason], Style.GOLD)
	attack_flag = false
	for f in sim.state.fighters:
		if not f.attack.is_empty() and f.attack.t == 9:
			attack_flag = true
	var th: Dictionary = sim.state.throw
	if sim.state.phase == "throw" and th.t == cfg.throw_ticks - 4:
		var big: bool = th.result == "ippon"
		shake = 12.0 if big else 7.0
		hitstop = 14 if big else 7
		flash = 1.0 if big else 0.45
		excite = 1.0 if big else 0.7
		var land = _throw_landing_point(th)
		_dust(land, 26 if big else 14, 1.0 if big else 0.7)
		for i in 2:
			if controllers[i].begins_with("pad"):
				Settings.rumble(int(controllers[i].substr(3)), 1.0 if th.result == "ippon" else 0.7, 0.35)
	if sim.state.phase == "throw" and th.t == cfg.throw_ticks / 2:
		capture_flag = true
	if sim.state.phase in ["score", "ended"] and sim.state.phase_t == 14:
		capture_flag = true
	if sim.state.phase == "newaza" and sim.state.newaza.t in [12, 400]:
		capture_flag = true


# --- Son ------------------------------------------------------------------------

var _snd_announce = ""
var _snd_announce_t = 0
var _snd_clock_s = -1
var _snd_osae_s = -1
var _snd_prev_x = [0.0, 0.0]
var _snd_step_cd = [0, 0]
var _snd_rustle_cd = 0


## Bruitage associé à un événement de la simulation.
func _sound_event(e: Dictionary) -> void:
	var who: int = e.get("who", -1)
	match e.type:
		"grip":
			Sound.play("grip", -6.0, 1.0, 0.08)
		"break":
			Sound.play("grip_break", -3.0)
		"break_fail":
			Sound.play("slap", -6.0, 1.1, 0.1)
		"osae_hit":
			Sound.play("taiko_small", -4.0 if e.perfect else -8.0, 1.15 if e.role == "top" else 0.9)
			Sound.play("rustle", -6.0, 1.0, 0.1)
		"osae_miss":
			Sound.play("ui_error", -12.0)
		"parry":
			Sound.play("slap", -2.0, 1.0, 0.08)
		"whiff":
			Sound.play("whoosh_0", -8.0, 1.2)
		"dash":
			Sound.play("dash", -5.0, 1.0, 0.06)
		"reaction":
			Sound.play("reaction", -4.0, 1.0, 0.0)
		"break_fail":
			Sound.play("grip", -10.0, 0.8)
		"attack":
			Sound.play("whoosh_1", -5.0)
			Sound.play("kiai_%d" % maxi(who, 0), -4.0, 1.0, 0.05)
		"feint":
			Sound.play("whoosh_0", -9.0)
		"block":
			Sound.play("block", -2.0)
		"stuffed":
			Sound.play("block", -4.0, 0.85)
		"counter":
			Sound.play("counter", -2.0)
			Sound.play("crowd_ooh", -8.0)
		"throw":
			Sound.play("whoosh_2", -3.0)
		"combo_open":
			Sound.play("taiko_small", -8.0, 1.2, 0.0)
		"newaza":
			Sound.play("rustle", -6.0)
		"escape", "sub_escape":
			Sound.play("grip_break", -4.0, 0.9)
		"sub_start":
			Sound.play("grunt_%d" % maxi(who, 0), -4.0)
			Sound.play("crowd_ooh", -9.0)
		"submission":
			Sound.play("tap_out", -2.0, 1.0, 0.0)
			Sound.play("crowd_cheer", -4.0)


## Sons liés à l'état courant : annonces de l'arbitre, chrono, pas, sol.
func _sound_frame() -> void:
	var st: Dictionary = sim.state
	# annonces (une seule fois par annonce)
	if st.announce_t > 0 and (st.announce != _snd_announce or st.announce_t > _snd_announce_t):
		_sound_announce(st.announce)
	_snd_announce = st.announce
	_snd_announce_t = st.announce_t
	# chrono : tic à chacune des dix dernières secondes
	var s = int(ceil(float(st.clock) / 60.0))
	if st.phase == "fight" and s != _snd_clock_s and s <= 10 and s > 0 and not st.golden:
		Sound.play("tick", -2.0, 1.0, 0.0)
	_snd_clock_s = s
	# osaekomi : tic-tac à chaque seconde d'immobilisation
	var nw: Dictionary = st.newaza
	if not nw.is_empty() and nw.get("osae", false):
		var os_s = int(nw.get("osae_t", 0)) / 60
		if os_s != _snd_osae_s:
			Sound.play("tock", -4.0, 1.0 + minf(os_s, 20) * 0.01, 0.0)
		_snd_osae_s = os_s
	else:
		_snd_osae_s = -1
	# froissements au sol
	if st.phase == "newaza":
		_snd_rustle_cd -= 1
		if _snd_rustle_cd <= 0:
			Sound.play("rustle", -12.0, 1.0, 0.1)
			_snd_rustle_cd = 26 + (st.get("tick", frame) * 7) % 20
	# pas glissés quand un judoka se déplace
	for i in 2:
		var x = wx(st.fighters[i].x)
		var moving = absf(x - _snd_prev_x[i]) > 0.6
		_snd_prev_x[i] = x
		_snd_step_cd[i] -= 1
		if moving and st.phase == "fight" and _snd_step_cd[i] <= 0:
			Sound.play("step", -16.0, 1.0, 0.1)
			_snd_step_cd[i] = 16
	Sound.crowd_level(0.25 + excite * 0.75)


func _sound_announce(text: String) -> void:
	match text:
		"HAJIME":
			Sound.play("taiko", -3.0, 1.0, 0.0)
			Sound.play("ref_hajime", -2.0, 1.0, 0.0)
		"MATTE":
			Sound.play("clack", -4.0, 1.0, 0.0)
			Sound.play("ref_matte", -3.0, 1.0, 0.0)
		"IPPON !":
			Sound.play("stinger_ippon", -1.0, 1.0, 0.0)
			Sound.play("ref_ippon", 0.0, 1.0, 0.0)
		"WAZA-ARI":
			Sound.play("stinger_wazaari", -3.0, 1.0, 0.0)
			Sound.play("ref_wazaari", -1.0, 1.0, 0.0)
		"OSAEKOMI":
			Sound.play("stinger_osaekomi", -5.0, 1.0, 0.0)
			Sound.play("ref_osaekomi", -1.0, 1.0, 0.0)
		"TOKETA":
			Sound.play("ref_toketa", -2.0, 1.0, 0.0)
		"SHIDO":
			Sound.play("buzzer", -6.0, 1.0, 0.0)
			Sound.play("ref_shido", -2.0, 1.0, 0.0)
		"SORE-MADE", "HANSOKU-MAKE":
			Sound.play("gong", -2.0, 1.0, 0.0)
			Sound.play("ref_soremade", -2.0, 1.0, 0.0)
		"GOLDEN SCORE":
			Sound.play("taiko", -3.0, 0.9, 0.0)
			Sound.play("gong", -8.0, 1.2, 0.0)
		_:
			# nom d'une soumission annoncée (ex. JUJI-GATAME)
			Sound.play("taiko_small", -5.0, 1.0, 0.0)


func _feed(text: String, color: Color) -> void:
	feed.append({"text": text, "color": color, "t": 0})
	if feed.size() > 3:
		feed.pop_front()


func _popup(text: String, who: int, color: Color) -> void:
	for p in popups:
		if p.text == text and p.who == who and p.t < 45:
			return  # pas de doublon empilé
	popups.append({"text": text, "who": who, "color": color, "t": 0})
	var mine = popups.filter(func(q): return q.who == who)
	if mine.size() > 2:
		popups.erase(mine[0])  # au plus deux bulles par judoka


# =============================================================================
# Dessin
# =============================================================================

func _draw() -> void:
	pass  # tout est dessiné par les calques


func _draw_layer_bg(ci: CanvasItem) -> void:
	if sim == null:
		return
	_ci = ci
	_draw_arena()


func _draw_layer_world(ci: CanvasItem) -> void:
	if sim == null:
		return
	_ci = ci
	_draw_mat()
	_draw_referee()
	_draw_fighters()
	_draw_particles()
	_draw_impacts()
	_draw_popups()


func _draw_layer_hud(ci: CanvasItem) -> void:
	if sim == null:
		return
	_ci = ci
	if replaying:
		_draw_replay_banner()
		return
	_draw_hud()
	_draw_announce()
	if Settings.value("feed") and dojo == null:
		_draw_feed()
	if Settings.value("hints"):
		_draw_hints()
	if dojo != null:
		dojo.draw(ci)
	if flash > 0.01:
		ci.draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, flash * 0.55))
	if paused and dojo == null:
		_draw_pause()


# =============================================================================
# Caméra et effets
# =============================================================================

## Démarre le ralenti : depuis un peu avant l'entrée de la technique gagnante.
func _start_replay() -> void:
	if replay_buf.is_empty():
		replay_done = true
		return
	replay_final = sim.get_state()
	var start = 0
	for k in range(replay_buf.size() - 1, -1, -1):
		var st: Dictionary = replay_buf[k]
		if st.phase == "fight" and not (st.fighters[0].attack.is_empty() and st.fighters[1].attack.is_empty()):
			start = k
		elif start > 0 and st.phase == "fight":
			break
	replay_i = maxi(0, start - 50)
	replay_sub = 0
	replaying = true
	shown = [null, null]
	popups.clear()


func _replay_tick() -> void:
	var st: Dictionary = replay_buf[replay_i]
	sim.state = st
	replay_sub += 1
	var slow = 3 if st.phase == "throw" else 2
	if replay_sub >= slow:
		replay_sub = 0
		replay_i += 1
	if replay_i >= replay_buf.size():
		replaying = false
		replay_done = true
		sim.set_state(replay_final)
		shown = [null, null]
		end_timer = 140


func _draw_replay_banner() -> void:
	_ci.draw_rect(Rect2(0, 0, W, 64), Style.INK)
	_ci.draw_rect(Rect2(0, H - 64, W, 64), Style.INK)
	var r = Rect2(W / 2 - 150, 16, 300, 60)
	Style.panel(_ci, r, Style.HOT, Style.INK, 4.0, 6.0)
	Style.text(_ci, Vector2(r.position.x, r.position.y + 45), "RALENTI", 40, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 2, -1.0)
	if frame % 60 < 40:
		_ci.draw_circle(Vector2(r.position.x + 30, r.get_center().y), 8.0, Style.DANGER)
	var th: Dictionary = sim.state.throw
	if not th.is_empty():
		Style.text(_ci, Vector2(0, H - 22), sim.tech_name(th.tech).to_upper(), 30, Style.GOLD, "display", HORIZONTAL_ALIGNMENT_CENTER, W)


## Cible de la caméra selon la phase : suit les judokas, zoome quand ils sont proches,
## serre sur les projections et le sol.
func _camera_target() -> Array:
	var st: Dictionary = sim.state
	var c = Vector2(640, 380)
	var z = 1.0
	match st.phase:
		"fight", "intro":
			var x0 = _draw_x(0)
			var x1 = _draw_x(1)
			var d = absf(x1 - x0)
			z = clampf(remap(d, 330.0, 110.0, 1.0, 1.1), 1.0, 1.1)
			# zone morte : la caméra ne suit le couple que s'il s'éloigne du centre de l'image,
			# pour qu'on voie les judokas traverser le tapis
			var mid = (x0 + x1) * 0.5
			var cx = cam_c.x
			if mid - cx > CAM_DEADZONE:
				cx = mid - CAM_DEADZONE
			elif cx - mid > CAM_DEADZONE:
				cx = mid + CAM_DEADZONE
			c = Vector2(cx, 430.0)
		"throw", "score":
			var th: Dictionary = st.throw
			if not th.is_empty():
				var p = clampf(float(th.t) / float(cfg.throw_ticks), 0.0, 1.0)
				c = Vector2((wx(th.tori_x) + wx(th.uke_x)) * 0.5, 440.0)
				z = 1.28 + (0.22 * sin(PI * minf(p * 1.2, 1.0)) if th.result == "ippon" else 0.08)
			elif not st.newaza.is_empty():
				c = Vector2(_newaza_center_x(st.newaza), 470.0)
				z = 1.45
		"newaza":
			c = Vector2(_newaza_center_x(st.newaza), 470.0)
			z = 1.45
		"ended":
			z = 1.15
			c = Vector2((_draw_x(0) + _draw_x(1)) * 0.5, 440.0)
	if replaying:
		z *= 1.18
	return [c, z]


func _update_camera() -> void:
	var t: Array = _camera_target()
	var k = 0.12 if sim.state.phase != "throw" else 0.2
	cam_z = lerpf(cam_z, t[1], k)
	cam_c = cam_c.lerp(t[0], k)
	# la vue ne sort jamais de l'arène
	var hw = 640.0 / cam_z
	var hh = 360.0 / cam_z
	cam_c.x = clampf(cam_c.x, hw, W - hw)
	cam_c.y = clampf(cam_c.y, hh, H - hh)
	var off = Vector2.ZERO
	if shake > 0.0:
		off = Vector2(sin(frame * 1.7) * shake, cos(frame * 2.3) * shake * 0.6)
	if layer_world != null:
		layer_world.transform = Transform2D(0.0, Vector2(cam_z, cam_z), 0.0, Vector2(640, 360) - cam_c * cam_z + off)
	if layer_bg != null:
		# parallaxe : le décor bouge et zoome moins que le tatami
		var zb = 1.0 + (cam_z - 1.0) * 0.45
		var cb = Vector2(640, 360).lerp(cam_c, 0.45)
		layer_bg.transform = Transform2D(0.0, Vector2(zb, zb), 0.0, Vector2(640, 360) - cb * zb + off * 0.5)


func _update_fx() -> void:
	# marche : la foulée suit le déplacement réel (pas de pieds qui glissent)
	if sim != null and sim.state.phase == "fight":
		for i in 2:
			var x = _draw_x(i)
			if prev_dx[i] < 0.0:
				prev_dx[i] = x
			var dx = x - prev_dx[i]
			prev_dx[i] = x
			walk_ph[i] += absf(dx) * 0.12
			vel[i] = lerpf(vel[i], dx * sim.state.fighters[i].facing, 0.15)
			walk_amp[i] = lerpf(walk_amp[i], clampf(absf(dx) / 1.4, 0.0, 1.0), 0.2)
			if absf(dx) > 0.05:
				walk_dir[i] = signf(dx * sim.state.fighters[i].facing)
	else:
		prev_dx = [-1.0, -1.0]
		walk_amp = [walk_amp[0] * 0.8, walk_amp[1] * 0.8]
	if sim != null:
		var gt = _gap_target()
		gap_shown = gt if gap_shown < 0.0 else lerpf(gap_shown, gt, 0.14)
		for i in 2:
			var f: Dictionary = sim.state.fighters[i]
			var pull = clampf(float(f.prev[Sim.PX]) * f.facing / 100.0, -1.0, 1.0)  # < 0 : tire vers soi
			var lift = clampf(float(f.prev[Sim.PY]) / 100.0, -1.0, 1.0)
			for h in 2:
				var want = Vector2(pull * 10.0 * f.facing, -lift * 4.0) * K if f.hands[h].state == Sim.HAND_GRIP else Vector2.ZERO
				tug[i][h] = tug[i][h].lerp(want, 0.22)
				if grip_shake[i][h] > 0:
					grip_shake[i][h] -= 1
			if chop[i] > 0:
				chop[i] -= 1
		for k in ["top", "bot", "top_miss", "bot_miss"]:
			if osae_fx[k] > 0:
				osae_fx[k] -= 1
	for im in impacts:
		im.t += 1
	impacts = impacts.filter(func(im): return im.t < 12)
	for i in 2:
		for h in 2:
			if knock[i][h] > 0:
				knock[i][h] -= 1
	shake = maxf(0.0, shake * 0.86 - 0.15)
	flash = maxf(0.0, flash - 0.07)
	excite = maxf(0.0, excite - 0.006)
	for p in particles:
		p.p += p.v
		p.v.y += 0.12
		p.v.x *= 0.95
		p.life -= 1
	particles = particles.filter(func(p): return p.life > 0)


## Point d'impact au sol d'une projection (monde, px).
func _throw_landing_point(th: Dictionary) -> Vector2:
	var fr: Array = _throw_frame(th)
	var smp: Dictionary = Anims.sample(Anims.keys(th.tech, fr[1]), 1.0)
	return Vector2((fr[0] * smp.uke.pos).x, FEET_Y)


## Poussière de tatami (déterministe : ne dépend que du numéro d'image).
func _dust(at: Vector2, count: int, power: float) -> void:
	var s = frame * 7919 + int(at.x)
	for k in count:
		s = (s * 1103515245 + 12345) & 0x7fffffff
		var a = PI + float(s % 1000) / 1000.0 * PI  # vers le haut
		var sp = (1.5 + float((s >> 10) % 100) / 100.0 * 4.5) * power
		var life = 22 + (s >> 4) % 18
		particles.append({"p": at + Vector2(float((s >> 6) % 60) - 30.0, 0), "v": Vector2(cos(a) * sp * 1.6, sin(a) * sp),
			"life": life, "max": life, "size": 3.0 + float((s >> 12) % 5), "col": Color("fff3c4") if k % 3 else Style.PAPER})


## Point entre les deux judokas, à une hauteur relative (0 = pieds, 1 = tête).
func _between(h: float) -> Vector2:
	var x = (_draw_x(0) + _draw_x(1)) * 0.5
	return Vector2(x, FEET_Y - h * 124.0 * K / 2.2 * 2.2)


func _impact(p: Vector2, col: Color, size: float) -> void:
	impacts.append({"p": p, "col": col, "s": size, "t": 0})


func _draw_impacts() -> void:
	for im in impacts:
		var q = float(im.t) / 12.0
		var r = (14.0 + 26.0 * q) * im.s
		var a = 1.0 - q
		Style.burst(_ci, im.p, r * 0.45, r, 8, Color(im.col, a), Color(Style.INK, a), 3, im.t * 0.05)


func _draw_particles() -> void:
	for p in particles:
		var a: float = float(p.life) / float(p.max)
		_ci.draw_circle(p.p, p.size * (0.6 + 0.4 * a), Color(p.col, 0.75 * a))


func wx(x_cpx: int) -> float:
	return float(x_cpx) / 50.0


func _persp(x: float, y: float) -> float:
	return 640.0 + (x - 640.0) * (1.0 + (y - FEET_Y) * 0.0013)


func _draw_arena() -> void:
	# ciel de salle : bandes de dégradé
	var top = Color("0f0b24")
	var bottom = Color("2a1f5e")
	var steps = 24
	for k in steps:
		var y0 = MAT_BACK * k / steps
		_ci.draw_rect(Rect2(0, y0, W, MAT_BACK / steps + 1), top.lerp(bottom, float(k) / steps))
	# projecteurs
	for sx in [260.0, 640.0, 1020.0]:
		var pts = PackedVector2Array([Vector2(sx - 18, 0), Vector2(sx + 18, 0), Vector2(sx + 210, MAT_BACK), Vector2(sx - 210, MAT_BACK)])
		_ci.draw_colored_polygon(pts, Color(1, 1, 1, 0.035))
	# tribunes : rangées de silhouettes
	var s = 12345
	for row in 5:
		var y = 330.0 + row * 34.0
		var col = Color("1a1440").lerp(Color("2e2465"), row / 5.0)
		var x = -10.0 + (row % 2) * 14.0
		while x < W + 20:
			s = (s * 1103515245 + 12345) & 0x7fffffff
			var hy = y + float(s % 9)
			_ci.draw_circle(Vector2(x, hy), 10.0, col)
			_ci.draw_rect(Rect2(x - 15, hy + 7, 30, 30), col)
			if s % 19 == 0:
				var glow = Style.HOT if s % 2 == 0 else Style.P2
				_ci.draw_circle(Vector2(x + 8, hy - 16), 7.0, Color(glow, 0.18))
				_ci.draw_line(Vector2(x + 6, hy + 4), Vector2(x + 8, hy - 16), col.lightened(0.15), 4.0)
				_ci.draw_circle(Vector2(x + 8, hy - 16), 3.0, glow)  # bâton lumineux
			x += 28.0 + float(s % 6)
	Style.halftone(_ci, Rect2(0, 320, W, 190), Color(0, 0, 0, 0.28), 12.0, 3.6, Vector2(0, -1))
	# bandeau LED
	var led = Rect2(0, 498, W, 44)
	_ci.draw_rect(led, Style.INK)
	_ci.draw_rect(led.grow_individual(0, -5, 0, -5), Color("1c1048"))
	var segs = [["JUDO 2D", 26, Style.HOT], ["★", 20, Style.PAPER], ["TOURNOI", 24, Style.P2], ["★", 20, Style.PAPER],
		["KUMIKATA · KUZUSHI · IPPON", 20, Style.P1], ["★", 20, Style.PAPER]]
	var seg_w = []
	var total = 0.0
	for sg in segs:
		var sw = Style.text_width(sg[0], sg[1]) + 34.0
		seg_w.append(sw)
		total += sw
	var x2 = -fmod(frame * 1.5, total)
	while x2 < W:
		for k in segs.size():
			Style.label(_ci, Vector2(x2, 529), segs[k][0], segs[k][1], segs[k][2], "display")
			x2 += seg_w[k]
	# grands éclats décoratifs aux bords (couleurs des joueurs)
	_ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(150, 0), Vector2(30, 330), Vector2(0, 330)]), Style.P1.darkened(0.72))
	_ci.draw_colored_polygon(PackedVector2Array([Vector2(W, 0), Vector2(W - 150, 0), Vector2(W - 30, 330), Vector2(W, 330)]), Style.P2.darkened(0.72))


func _draw_mat() -> void:
	# face avant du tatami
	var fr = PackedVector2Array([Vector2(_persp(40, MAT_FRONT), MAT_FRONT), Vector2(_persp(1240, MAT_FRONT), MAT_FRONT),
		Vector2(_persp(1240, MAT_FRONT) + 4, MAT_FRONT + 16), Vector2(_persp(40, MAT_FRONT) - 4, MAT_FRONT + 16)])
	_ci.draw_colored_polygon(fr, Style.MAT_SAFETY_SHADE.darkened(0.3))
	_ci.draw_rect(Rect2(0, MAT_FRONT + 16, W, H - MAT_FRONT - 16), Color("0d0a1e"))
	# zone de sécurité (bleu) puis zone de combat (jaune)
	_mat_quad(40, 1240, Style.MAT_SAFETY)
	_mat_quad(wx(cfg.mat_left), wx(cfg.mat_right), Style.MAT_COMBAT)
	# coutures des tatamis
	var x = 40.0
	while x <= 1240.0:
		var c = Style.MAT_COMBAT_SHADE if x >= wx(cfg.mat_left) and x <= wx(cfg.mat_right) else Style.MAT_SAFETY_SHADE
		_ci.draw_line(Vector2(_persp(x, MAT_BACK), MAT_BACK), Vector2(_persp(x, MAT_FRONT), MAT_FRONT), c, 2.0)
		x += 80.0
	_ci.draw_line(Vector2(_persp(40, 604), 604), Vector2(_persp(1240, 604), 604), Color(0, 0, 0, 0.08), 2.0)
	# contour d'encre
	var outline = PackedVector2Array([Vector2(_persp(40, MAT_BACK), MAT_BACK), Vector2(_persp(1240, MAT_BACK), MAT_BACK),
		Vector2(_persp(1240, MAT_FRONT), MAT_FRONT), Vector2(_persp(40, MAT_FRONT), MAT_FRONT), Vector2(_persp(40, MAT_BACK), MAT_BACK)])
	_ci.draw_polyline(outline, Style.INK, 4.0, true)
	# bandes de départ (repères tori / uke)
	for sx in [-1, 1]:
		var cx = 640.0 + sx * wx(cfg.start_gap) / 2.0
		var col = Style.GI_WHITE if sx < 0 else Style.GI_BLUE
		_ci.draw_line(Vector2(_persp(cx, 590), 590), Vector2(_persp(cx, 618), 618), col, 5.0)


func _mat_quad(x0: float, x1: float, col: Color) -> void:
	_ci.draw_colored_polygon(PackedVector2Array([Vector2(_persp(x0, MAT_BACK), MAT_BACK), Vector2(_persp(x1, MAT_BACK), MAT_BACK),
		Vector2(_persp(x1, MAT_FRONT), MAT_FRONT), Vector2(_persp(x0, MAT_FRONT), MAT_FRONT)]), col)


# --- Judokas -----------------------------------------------------------------

func _fighter_xform(i: int) -> Transform2D:
	var f: Dictionary = sim.state.fighters[i]
	var lean = clampf(float(f.bal_x) / 10000.0, -1.0, 1.0) * 0.2
	var crouch = 0.0
	if not f.attack.is_empty():
		var atk: Dictionary = f.attack
		crouch = clampf(float(atk.t) / float(atk.entry), 0.0, 1.0)
	return Art.stand_xform(Vector2(_draw_x(i), FEET_Y), f.facing, lean, K, crouch)


## Position d'affichage : écart visuel minimum entre les deux judokas (lisibilité du kumikata).
const VIS_GAP := 110.0
const LINK_GAP := 92.0
const GAP_SCALE := 0.76  # écart affiché / écart simulé (bras de longueur réaliste)
const CAM_DEADZONE := 150.0
func _draw_x(i: int) -> float:
	var fs: Array = sim.state.fighters
	var x = wx(fs[i].x)
	var ox = wx(fs[1 - i].x)
	var d = absf(ox - x)
	var g = gap_shown if gap_shown > 0.0 else maxf(d, VIS_GAP)
	var sgn = signf(ox - x) if d > 0.01 else float(fs[i].facing)
	return (x + ox) * 0.5 - sgn * g * 0.5


## Écart d'affichage voulu : à distance, l'écart réel ; en garde, assez près pour que
## les bras restent pliés (la distance de simulation sert au jeu, pas à l'image).
func _gap_target() -> float:
	var fs: Array = sim.state.fighters
	var d = absf(wx(fs[1].x) - wx(fs[0].x))
	return maxf(d * GAP_SCALE, LINK_GAP)


func _draw_fighters() -> void:
	var nwz: Dictionary = sim.state.newaza
	if not nwz.is_empty() and sim.state.phase in ["newaza", "score", "ended"]:
		_draw_newaza(nwz)
		return
	var th: Dictionary = sim.state.throw
	var throwing: bool = not th.is_empty() and sim.state.phase in ["throw", "score", "ended"]
	if _draw_sprites(th, throwing):
		return
	var rigs: Array = _throw_rigs(th) if throwing else _standing_rigs()
	# ombres
	for i in 2:
		var hip_x: float = (rigs[i].xf * Vector2(0, -47)).x
		Art.shadow(_ci, Vector2(hip_x, FEET_Y + 2), K, 0.3)
	var order = [1, 0]
	if throwing:
		order = [th.tori, th.uke] if Anims.family(th.tech) == "sacrifice" else [th.uke, th.tori]
	for i in order:
		var hw: Array = _hands_world(i, rigs, th, throwing)
		Art.draw_fighter(_ci, rigs[i].xf, _pal(i), rigs[i].pose, hw[0], hw[1])
		if not throwing:
			_draw_callout(i, _base_xf(i))


## Repère d'un judoka debout (pieds, sens du regard, échelle).
func _base_xf(i: int) -> Transform2D:
	var f: Dictionary = sim.state.fighters[i]
	return Transform2D(0.0, Vector2(f.facing * K, K), 0.0, Vector2(_draw_x(i), FEET_Y))


## Pose de garde vivante : respiration, marche, déséquilibre subi, fatigue, défense.
func _standing_pose(i: int) -> Dictionary:
	var f: Dictionary = sim.state.fighters[i]
	var pose: Dictionary = Art.pose_stand(0.5)
	var breath = sin(frame * 0.06 + i * 1.3)
	pose.hip += Vector2(0, breath * 0.7)
	var free_legs = false
	if walk_amp[i] > 0.04:
		# suri-ashi : pas glissés, le pied arrière ne dépasse jamais l'avant
		var ph = walk_ph[i]
		var am = walk_amp[i]
		var dir = walk_dir[i]
		pose.fb += Vector2(sin(ph) * 9.0 * dir * am, -maxf(0.0, cos(ph)) * 4.5 * am)
		pose.ff += Vector2(sin(ph + PI) * 9.0 * dir * am, -maxf(0.0, -cos(ph)) * 4.5 * am)
		pose.hip += Vector2(dir * 2.0 * am, -absf(sin(ph)) * 2.2 * am)
		free_legs = true
	# déséquilibre subi : bal_x > 0 = tiré vers l'avant (vers l'adversaire)
	var bx = clampf(float(f.bal_x + f.react) / 10000.0, -1.0, 1.0)
	var by = clampf(float(f.bal_y) / 10000.0, -1.0, 1.0)
	pose.bow = bx * 0.5
	pose.tilt = -bx * 0.25
	pose.hip += Vector2(bx * 7.0, absf(bx) * 2.0 + absf(by) * 3.0)
	if bx > 0.45:
		pose.fb.y -= (bx - 0.45) * 8.0  # sur la pointe des pieds
	elif bx < -0.45:
		pose.ff.y -= (-bx - 0.45) * 8.0
	if absf(bx) > 0.05 or absf(by) > 0.05:
		free_legs = true
	# kumikata : légère inclinaison vers l'adversaire quand on le tient
	if sim.has_grip(f) or sim.has_grip(sim.state.fighters[1 - i]):
		# posture de kumikata : buste vers l'avant, hanches en retrait ; on se tire,
		# on se pousse, le poids passe d'un pied sur l'autre
		var pull = clampf(float(f.prev[Sim.PX]) * f.facing / 100.0, -1.0, 1.0)
		var sway = sin(frame * 0.045 + i * 2.0)
		# il pousse (le couple avance vers l'autre) : buste en avant ; il recule en tirant : hanches en arrière
		var drive = clampf(vel[i] / 1.4, -1.0, 1.0)
		pose.bow += drive * (0.14 if drive > 0.0 else 0.08)
		pose.hip += Vector2(drive * 3.0, absf(drive) * 2.0)
		# à distance (bras tendus), le buste se penche pour aller chercher la prise
		var ext = clampf((gap_shown / K - 46.0) / 18.0, -0.6, 1.0) if gap_shown > 0.0 else 0.0
		pose.bow += 0.12 + ext * 0.2 + pull * 0.12 + sway * 0.03
		pose.hip += Vector2(-3 - ext * 5.0 + pull * 4.0 + sway * 1.6, 2 + absf(pull) * 1.5 + maxf(0.0, ext) * 3.0)
		pose.ff += Vector2(sway * 1.2, 0)
		free_legs = true
		var shook = maxi(grip_shake[i][0], grip_shake[i][1])
		if shook > 0:
			pose.bow += sin(frame * 1.7) * 0.04 * float(shook) / 12.0
	# domination : le dominé se fait courber, le dominant se tient droit
	var dm = float(sim.dom_of(i)) / 10000.0
	if dm < -0.2:
		var k = (-dm - 0.2) / 0.8
		pose.bow += 0.42 * k
		pose.hip += Vector2(-3.0 * k, 5.0 * k)
		free_legs = true
	elif dm > 0.3:
		pose.bow -= 0.05
	# dash : grand pas explosif, buste dans le sens du mouvement
	if f.dash_t > 0:
		var fwd = 1.0 if f.dash_dir == f.facing else -1.0
		var e2 = float(f.dash_t) / float(cfg.dash_ticks)
		pose.bow += 0.18 * fwd * e2
		pose.ff += Vector2(9.0 * fwd * e2, -2.0 * e2)
		pose.fb += Vector2(-7.0 * fwd * e2, -3.0 * e2)
		pose.hip += Vector2(4.0 * fwd * e2, 3.0 * e2)
		free_legs = true
	# fatigue : épaules qui tombent, garde plus basse
	var tired = 1.0 - float(f.stamina) / float(f.stamina_max)
	if tired > 0.5:
		var t = (tired - 0.5) * 2.0
		pose.bow += t * 0.18
		pose.hip.y += t * 4.0
		pose.tilt += t * 0.2
		free_legs = true
	# défense : hanches basses et en arrière
	if f.defend_t > 0:
		pose.hip += Vector2(-4, 6)
		pose.bow -= 0.15
		free_legs = true
	# attaque ratée : emporté vers l'avant
	if f.exposed_t > 0:
		var e = float(f.exposed_t) / float(cfg.exposed_ticks)
		pose.bow += 0.55 * e
		pose.hip += Vector2(8.0 * e, 4.0 * e)
		pose.ff += Vector2(10.0 * e, 0)
		free_legs = true
	if free_legs:
		pose.erase("kb")
		pose.erase("kf")
	return pose


func _standing_rigs() -> Array:
	var rigs = []
	for i in 2:
		var f: Dictionary = sim.state.fighters[i]
		var target = {"xf": _base_xf(i), "pose": _standing_pose(i)}
		if not f.attack.is_empty():
			# entrée de la technique : début de la chorégraphie, côté tori
			var atk: Dictionary = f.attack
			var e = clampf(float(atk.t) / float(atk.entry), 0.0, 1.0)
			var d = absf(_draw_x(1 - i) - _draw_x(i)) / K
			var smp: Dictionary = Anims.sample(Anims.keys(atk.tech, d), Anims.ENTRY * e)
			target = {"xf": Anims.actor_xform(_base_xf(i), smp.tori), "pose": smp.tori.pose}
		rigs.append(_smooth(i, target))
	return rigs


## Lissage visuel des squelettes (pas de saut quand une attaque s'interrompt).
func _smooth(i: int, target: Dictionary) -> Dictionary:
	var prev = shown[i]
	var out = target
	if prev != null and signf(prev.xf.x.x) == signf(target.xf.x.x):
		out = {"xf": prev.xf.interpolate_with(target.xf, 0.4), "pose": Art.lerp_pose(prev.pose, target.pose, 0.4)}
		if target.pose.has("kb") and target.pose.has("kf"):
			out.pose.kb = target.pose.kb
			out.pose.kf = target.pose.kf
	shown[i] = out
	return out


## Positions d'affichage de deux judokas à partir de leurs x de simulation (écart visuel minimum).
func _vis_pair(xa_cpx: int, xb_cpx: int) -> Array:
	var xa = wx(xa_cpx)
	var xb = wx(xb_cpx)
	var d = absf(xb - xa)
	if d < VIS_GAP:
		var push = signf(xb - xa) * (VIS_GAP - d) * 0.5
		xa -= push
		xb += push
	return [xa, xb]


func _throw_progress(th: Dictionary) -> float:
	return Anims.ENTRY + (1.0 - Anims.ENTRY) * clampf(float(th.t) / float(cfg.throw_ticks), 0.0, 1.0)


func _throw_frame(th: Dictionary) -> Array:
	var vp: Array = _vis_pair(th.tori_x, th.uke_x)
	var frame_xf = Transform2D(0.0, Vector2(th.facing * K, K), 0.0, Vector2(vp[0], FEET_Y))
	var d = absf(vp[1] - vp[0]) / K
	return [frame_xf, d]


func _throw_rigs(th: Dictionary) -> Array:
	var fr: Array = _throw_frame(th)
	var smp: Dictionary = Anims.sample(Anims.keys(th.tech, fr[1]), _throw_progress(th))
	var rigs = [null, null]
	rigs[th.tori] = {"xf": Anims.actor_xform(fr[0], smp.tori), "pose": smp.tori.pose}
	rigs[th.uke] = {"xf": Anims.actor_xform(fr[0], smp.uke), "pose": smp.uke.pose}
	shown = rigs.duplicate()
	return rigs


## Mains en coordonnées écran : saisies sur le judogi adverse (qui suivent son buste).
func _hands_world(i: int, rigs: Array, th: Dictionary, throwing: bool) -> Array:
	var o = 1 - i
	var orig: Dictionary = rigs[o]
	var f: Dictionary = sim.state.fighters[i]
	if throwing:
		var p = clampf(float(th.t) / float(cfg.throw_ticks), 0.0, 1.0)
		if i == th.tori:
			var sleeve = Art.torso_point(orig.xf, orig.pose, Art.GRIP_POINTS["sleeve"])
			var lapel = Art.torso_point(orig.xf, orig.pose, Art.GRIP_POINTS["lapel"])
			return [[sleeve, lapel if p < 0.85 else null], [0.6, 0.6 if p < 0.85 else -1.0]]
		if p < 0.25:
			return [[Art.torso_point(orig.xf, orig.pose, Art.GRIP_POINTS["sleeve"]), null], [-1.0, -1.0]]
		return [[null, null], [-1.0, -1.0]]
	var me: Dictionary = rigs[i]
	var hands = [null, null]
	var strength = [-1.0, -1.0]
	for h in 2:
		var hand: Dictionary = f.hands[h]
		var target = Art.torso_point(orig.xf, orig.pose, Art.GRIP_POINTS[cfg.grip_targets[hand.target]])
		var rest = Art.torso_point(me.xf, me.pose, Art.REST_HANDS[h])
		if hand.state == Sim.HAND_GRIP:
			# prise vivante : la main tire ou pousse le judogi, glisse si la prise est faible,
			# tremble quand on l'attaque ou que l'avant-bras est cuit
			var slip = (1.0 - float(hand.q) / 10000.0) * 3.0 * K
			hands[h] = target + tug[i][h] + Vector2(-f.facing * slip, slip * 0.3)
			var jit = 0.0
			if grip_shake[i][h] > 0:
				jit = float(grip_shake[i][h]) / 12.0 * 3.0 * K
			elif hand.fat > 7000:
				jit = float(hand.fat - 7000) / 3000.0 * 0.9 * K
			if jit > 0.0:
				hands[h] += Vector2(sin(frame * 2.3 + h * 1.7), cos(frame * 1.9 + h)) * jit
			strength[h] = float(hand.trig) / 100.0
		elif hand.state == Sim.HAND_REACH:
			var reach = float(cfg.grip_reach_ticks - (cfg.fast_reach_cut if f.fast_reach_t > 0 else 0))
			var q = clampf(float(hand.t) / reach, 0.0, 1.0)
			hands[h] = rest.lerp(target, q * q * (3.0 - 2.0 * q))
		elif hand.state == Sim.HAND_FREE and sim.state.phase == "fight" and hand.lock == 0 \
				and absi(sim.state.fighters[o].x - f.x) <= cfg.grip_range:
			# bataille de mains : les mains cherchent, avancent, se retirent
			var paw = 0.28 + 0.16 * sin(frame * 0.14 + h * 2.1 + i * 1.3) + 0.06 * sin(frame * 0.37 + h)
			hands[h] = rest.lerp(target, paw)
		if chop[i] > 0 and hand.state != Sim.HAND_GRIP:
			# combat de mains : la main libre frappe et arrache la prise adverse sur soi
			var oh: Dictionary = sim.state.fighters[o].hands[chop_hand[i]]
			var on_me = Art.torso_point(me.xf, me.pose, Art.GRIP_POINTS[cfg.grip_targets[oh.target]])
			var cq = float(chop[i]) / 12.0
			var reach_t = sin(cq * PI)
			hands[h] = rest.lerp(on_me + Vector2(f.facing * 4.0 * K, -4.0 * K), reach_t) + Vector2(0, (1.0 - cq) * 6.0 * K * reach_t)
		if knock[i][h] > 0:
			# main chassée : projetée vers le bas et en arrière, puis revient en garde
			var kq = float(knock[i][h]) / 14.0
			var base = rest.lerp(target, 0.55 * kq)
			hands[h] = base + Vector2(-f.facing * 10.0, 26.0) * kq * sin(kq * PI)
	return [hands, strength]


## Rendu par sprites quand les animations existent. Renvoie false pour retomber
## sur le dessin placeholder (animation absente).
func _draw_sprites(th: Dictionary, throwing: bool) -> bool:
	if libs[0] == null or libs[1] == null:
		return false
	if throwing:
		var a_t = "throw/%s/tori" % th.tech
		var a_u = "throw/%s/uke" % th.tech
		var lt = libs[th.tori]
		var lu = libs[th.uke]
		if not (lt.has(a_t) and lu.has(a_u)):
			return false
		var p = clampf(float(th.t) / float(cfg.throw_ticks), 0.0, 1.0)
		var feet = Vector2(wx(th.tori_x), FEET_Y)
		Art.shadow(_ci, feet + Vector2(0, 2), K * 1.4, 0.3)
		var first_uke: bool = th.dir in ["avant", "contre"] and p < 0.5
		if first_uke:
			lu.draw(_ci, a_u, p, 0, feet, th.facing, K)
		lt.draw(_ci, a_t, p, 0, feet, th.facing, K)
		if not first_uke:
			lu.draw(_ci, a_u, p, 0, feet, th.facing, K)
		return true
	for i in [1, 0]:
		var f: Dictionary = sim.state.fighters[i]
		var lib = libs[i]
		var feet = Vector2(_draw_x(i), FEET_Y)
		var lean = clampf(float(f.bal_x) / 10000.0, -1.0, 1.0) * 0.2
		Art.shadow(_ci, feet + Vector2(0, 2), K, 0.3)
		if not f.attack.is_empty() and lib.has("entry/" + f.attack.tech):
			lib.draw(_ci, "entry/" + f.attack.tech, float(f.attack.t) / float(f.attack.entry), 0, feet, f.facing, K)
		elif f.last_move * f.facing > 0 and lib.has("walk_fwd"):
			lib.draw(_ci, "walk_fwd", -1.0, frame, feet, f.facing, K, lean)
		elif lib.has("idle"):
			lib.draw(_ci, "idle", -1.0, frame, feet, f.facing, K, lean)
		else:
			return false
		_draw_callout(i, Art.stand_xform(feet, f.facing, lean, K))
	return true


## Centre horizontal de la scène au sol (monde, px).
func _newaza_center_x(nw: Dictionary) -> float:
	return clampf(wx(nw.x), 260.0, W - 260.0)


## Ne-waza : poses articulées selon la situation (transition, osaekomi, clé, étranglement).
func _draw_newaza(nw: Dictionary) -> void:
	var fc: int = nw.facing
	var ctrl = float(nw.control) / 10000.0
	var kind = "transition"
	if not nw.sub.is_empty():
		kind = "%s:%s" % [nw.sub.kind, nw.sub.tech]
	elif nw.osae:
		kind = "osaekomi:%s" % nw.hold
	var poses: Array = Art.ground_poses(kind, frame, ctrl)
	# la caméra zoome au sol : la scène est dessinée à l'échelle normale
	var center: float = poses[0].get("center", 12.0)
	var origin = Vector2(_newaza_center_x(nw) - fc * center * K, FEET_Y + 4.0)
	var xf = Transform2D(0.0, Vector2(fc * K, K), 0.0, origin)
	Art.shadow(_ci, origin + Vector2(fc * center * K, 2), K * 1.9, 0.32)
	Art.draw_figure(_ci, xf, _pal(nw.bottom), poses[1])
	Art.draw_figure(_ci, xf, _pal(nw.top), poses[0], ctrl)


## Jauge de contrôle au sol, chrono d'osaekomi, bras de fer des clés et étranglements.
func _draw_newaza_hud() -> void:
	var nw: Dictionary = sim.state.newaza
	if nw.is_empty() or sim.state.phase != "newaza":
		return
	var top: int = nw.top
	var col: Color = Style.P1 if top == 0 else Style.P2
	var r = Rect2(440, 104, 400, 84)
	Style.panel(_ci, r, Style.INK, col, 3.0, 6.0)
	Style.label(_ci, Vector2(r.position.x + 28, r.position.y + 26), "NE-WAZA · %s CONTRÔLE" % names[top], 14, col, "black")
	var gr = Rect2(r.position.x + 22, r.position.y + 38, r.size.x - 60, 24)
	Style.gauge(_ci, gr, float(nw.control) / 10000.0, col)
	for mark in [cfg.toketa_below, cfg.osaekomi_on]:
		var mx = gr.position.x + 4 + (gr.size.x - 8) * float(mark) / 10000.0
		_ci.draw_line(Vector2(mx, gr.position.y - 4), Vector2(mx, gr.end.y + 4), Style.PAPER, 2.0)
	if nw.osae and nw.has("ct"):
		_draw_osae_bar("top", nw, Rect2(370, 214, 540, 58))
		_draw_osae_bar("bot", nw, Rect2(370, 584, 540, 58))
	if nw.osae:
		var secs: int = nw.osae_t / 60
		var c = Vector2(r.position.x - 50, r.get_center().y)
		_ci.draw_circle(c + Vector2(3, 3), 38, Style.INK)
		_ci.draw_circle(c, 38, Style.INK)
		_ci.draw_arc(c, 32, -PI / 2, -PI / 2 + TAU * clampf(float(nw.osae_t) / float(cfg.osaekomi_ippon), 0.0, 1.0), 48, Style.GOLD, 7.0, true)
		Style.text(_ci, Vector2(c.x - 40, c.y + 14), str(secs), 38, Style.GOLD, "display", HORIZONTAL_ALIGNMENT_CENTER, 80, 3, 0.0)
		Style.label(_ci, Vector2(r.position.x + 28, r.end.y - 6), "OSAEKOMI — %s" % sim.tech_name(nw.hold).to_upper(), 13, Style.GOLD, "black")
	elif not nw.sub.is_empty():
		var sub: Dictionary = nw.sub
		var tot = maxf(1.0, float(sub.tp + sub.bp))
		var tr = Rect2(r.position.x, r.end.y + 10, r.size.x, 34)
		Style.panel(_ci, tr, Style.INK, Style.HOT, 3.0, 4.0)
		var split = tr.position.x + tr.size.x * float(sub.tp) / tot
		_ci.draw_rect(Rect2(tr.position.x + 6, tr.position.y + 6, split - tr.position.x - 6, tr.size.y - 12), col)
		_ci.draw_rect(Rect2(split, tr.position.y + 6, tr.end.x - 6 - split, tr.size.y - 12), Style.P2 if top == 0 else Style.P1)
		Style.label(_ci, Vector2(tr.position.x, tr.position.y + 24), sim.tech_name(sub.tech).to_upper(), 16, Style.INK, "black", HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)


## Barre du mini-jeu d'immobilisation : zone à viser, centre parfait, curseur qui va et vient.
func _draw_osae_bar(role: String, nw: Dictionary, r: Rect2) -> void:
	var who: int = nw.top if role == "top" else nw.bottom
	var col: Color = Style.P1 if who == 0 else Style.P2
	var z: Dictionary = nw.ct if role == "top" else nw.cb
	var locked: bool = z.lock > 0
	var hit = float(osae_fx[role]) / 12.0
	var rr = r.grow(hit * 4.0)
	Style.panel(_ci, rr, Style.INK, Style.GOLD if hit > 0.0 and osae_fx[role + "_perfect"] else col, 3.0 + hit * 2.0, 5.0)
	var btn = "{A}" if role == "top" else "{B}"
	var title = "%s · %s %s" % [names[who], "TENIR" if role == "top" else "SORTIR", btn]
	Rich.draw(_ci, Vector2(r.position.x + 26, r.position.y + 22), title.to_upper(), r.size.x - 200, 13, col)
	if role == "bot":
		var pr = Rect2(r.end.x - 170, r.position.y + 10, 120, 12)
		_ci.draw_rect(pr, Style.NIGHT)
		_ci.draw_rect(Rect2(pr.position, Vector2(pr.size.x * float(nw.prog) / 100.0, pr.size.y)), col)
		Style.label(_ci, Vector2(pr.position.x - 66, pr.end.y), "SORTIE", 11, Style.MUTED, "black")
	# barre
	var b = Rect2(r.position.x + 26, r.position.y + 30, r.size.x - 64, 18)
	_ci.draw_rect(b, Style.NIGHT if not locked else Style.NIGHT_2)
	var zx0 = b.position.x + b.size.x * float(int(z.c) - int(z.w) / 2) / 10000.0
	var zw = b.size.x * float(z.w) / 10000.0
	var zcol = col if not locked else Style.MUTED
	_ci.draw_rect(Rect2(zx0, b.position.y, zw, b.size.y), Color(zcol, 0.85))
	_ci.draw_rect(Rect2(zx0 + zw / 3.0, b.position.y, zw / 3.0, b.size.y), Style.GOLD if not locked else Style.MUTED.lightened(0.2))
	_ci.draw_rect(b, Style.INK, false, 2.0)
	# curseur
	var cx = b.position.x + b.size.x * float(sim.osae_cursor(role)) / 10000.0
	var miss = float(osae_fx[role + "_miss"]) / 16.0
	var ccol = Style.DANGER if miss > 0.0 else Style.PAPER
	_ci.draw_line(Vector2(cx, b.position.y - 6), Vector2(cx, b.end.y + 6), Style.INK, 7.0)
	_ci.draw_line(Vector2(cx, b.position.y - 5), Vector2(cx, b.end.y + 5), ccol, 3.0)
	_ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - 6, b.position.y - 10), Vector2(cx + 6, b.position.y - 10), Vector2(cx, b.position.y - 3)]), ccol)
	if locked:
		Style.label(_ci, Vector2(b.position.x, b.end.y - 3), "RATÉ — BLOQUÉ", 13, Style.DANGER, "black", HORIZONTAL_ALIGNMENT_CENTER, b.size.x)


func _ground_center() -> Vector2:
	var nw: Dictionary = sim.state.newaza
	return Vector2(_newaza_center_x(nw), FEET_Y - 30.0) if not nw.is_empty() else _between(0.5)


## Transforms des deux judokas pendant une projection (p de 0 à 1).
func _throw_xforms(th: Dictionary, p: float) -> Array:
	var pair: Array = Art.throw_xforms(th.dir, th.result == "ippon", th.facing, wx(th.tori_x), wx(th.uke_x), FEET_Y, K, p)
	var res = [Transform2D(), Transform2D()]
	res[th.tori] = pair[0]
	res[th.uke] = pair[1]
	return res


func _draw_callout(i: int, xf: Transform2D) -> void:
	var f: Dictionary = sim.state.fighters[i]
	if f.attack.is_empty():
		return
	var atk: Dictionary = f.attack
	var head: Vector2 = xf * Vector2(0, -124)
	var nm = sim.tech_name(atk.tech).to_upper()
	var col: Color = Style.P1 if i == 0 else Style.P2
	var wdt = Style.text_width(nm, 22) + 40.0
	var r = Rect2(head.x - wdt / 2.0, head.y - 34.0, wdt, 34.0)
	Style.panel(_ci, r, Style.INK, col, 3.0, 4.0)
	Style.text(_ci, Vector2(r.position.x, r.position.y + 26), nm, 22, col, "display", HORIZONTAL_ALIGNMENT_CENTER, wdt, 3, 0.0)
	var ratio = clampf(float(atk.t) / float(atk.entry), 0.0, 1.0)
	Style.gauge(_ci, Rect2(r.position.x + 8, r.end.y + 4, wdt - 16, 12), ratio, col)


# --- HUD ---------------------------------------------------------------------

func _draw_hud() -> void:
	for i in 2:
		_draw_player_hud(i)
		if sim.state.phase == "fight" and dojo == null and Settings.value("readout") \
				and (String(controllers[i]).begins_with("pad") or app != null and app.args.has("readout")):
			_draw_readout(i)
	if dojo == null:
		_draw_timer()
	if sim.state.phase in ["fight", "intro", "matte"]:
		_draw_dominance()
	_draw_newaza_hud()


## Lecture des boutons pour un joueur humain : technique de A / X / Y et issue prévisible,
## plus une alerte quand l'attaque adverse peut être contrée (B).
func _draw_readout(i: int) -> void:
	var f: Dictionary = sim.state.fighters[i]
	var o: Dictionary = sim.state.fighters[1 - i]
	var flip = i == 1
	if not sim.has_grip(f) and o.attack.is_empty():
		return
	for k in Readout.BUTTONS.size():
		var pr: Dictionary = Readout.predict(sim, i, Readout.BUTTONS[k][1])
		var r = _mirror(Rect2(30, 170 + k * 26, 250, 22), i)
		_ci.draw_rect(r, Color(Style.INK, 0.72))
		var bar = Rect2(r.position.x + 30, r.end.y - 4, (r.size.x - 34) * Readout.ratio(sim, pr.score), 3)
		if flip:
			bar.position.x = r.end.x - 4 - bar.size.x
		_ci.draw_rect(bar, Readout.outcome_color(pr.outcome))
		var bx = r.position.x + 15 if not flip else r.end.x - 15
		Style.pad_button(_ci, Vector2(bx, r.position.y + 10), Readout.BUTTONS[k][0], 9.0)
		var nm = String(pr.name).to_upper()
		var lab = Readout.outcome_label(pr.outcome)
		if pr.counter_risk and pr.outcome in ["stoppe", "expose"]:
			lab = "CONTRE !"
		var tx = r.position.x + 30 if not flip else r.position.x + 4
		Style.label(_ci, Vector2(tx, r.position.y + 15), nm, 12, Style.PAPER, "black", HORIZONTAL_ALIGNMENT_LEFT if not flip else HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 34 - 80)
		var lx = r.end.x - 84 if not flip else r.position.x + 4
		Style.label(_ci, Vector2(lx, r.position.y + 15), lab, 11, Style.DANGER if lab == "CONTRE !" else Readout.outcome_color(pr.outcome), "black",
			HORIZONTAL_ALIGNMENT_RIGHT if not flip else HORIZONTAL_ALIGNMENT_LEFT, 80)
	# alerte : son attaque est mal préparée et tu as le contre équipé
	if not o.attack.is_empty() and o.attack.committed:
		var tech: Dictionary = sim.techs[o.attack.tech]
		if tech.counter != "" and f.set.counters.has(tech.counter) and sim.dir_value(i, tech.dir) < cfg.counter_threshold:
			var pulse = 0.6 + 0.4 * sin(frame * 0.5)
			var ar = _mirror(Rect2(30, 252, 250, 34), i)
			Style.panel(_ci, ar, Color(Style.DANGER, pulse), Style.INK, 3.0, 4.0)
			Rich.draw(_ci, Vector2(ar.position.x + 18, ar.position.y + 23), "{B} CONTRE : %s" % sim.tech_name(tech.counter).to_upper(), ar.size.x - 30, 15, Style.INK)


func _mirror(r: Rect2, i: int) -> Rect2:
	if i == 0:
		return r
	return Rect2(W - r.end.x, r.position.y, r.size.x, r.size.y)


func _draw_player_hud(i: int) -> void:
	var f: Dictionary = sim.state.fighters[i]
	var col: Color = Style.P1 if i == 0 else Style.P2
	var flip = i == 1
	# panneau principal
	var pr = _mirror(Rect2(24, 20, 478, 66), i)
	Style.panel(_ci, pr, Style.NIGHT_2, Style.INK, 4.0, 6.0, Style.SLANT, flip)
	# badge joueur
	var br = _mirror(Rect2(34, 26, 74, 54), i)
	Style.panel(_ci, br, col, Style.INK, 3.0, 0.0, Style.SLANT, flip)
	Style.text(_ci, Vector2(br.position.x, br.position.y + 42), "%dP" % (i + 1), 34, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 1, -1.0)
	# nom
	var name_x = 122.0 if i == 0 else W - 122.0 - 260.0
	var align = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	Style.text(_ci, Vector2(name_x, 66), names[i], 38, Style.PAPER, "display", align, 260)
	# tokui-waza
	Style.label(_ci, Vector2(name_x, 82), "TOKUI : " + sim.tech_name(f.tokui).to_upper(), 12, Style.MUTED, "bold", align, 260)
	# waza-ari (2 cases) + ippon
	for k in 2:
		var wr = _mirror(Rect2(390 + k * 52, 30, 46, 22), i)
		var on: bool = f.waza > k or f.ippon > 0
		Style.panel(_ci, wr, Style.GOLD if on else Style.NIGHT, Style.INK, 3.0, 0.0, Style.SLANT, flip)
		Style.label(_ci, Vector2(wr.position.x, wr.position.y + 17), "W", 16, Style.INK if on else Style.MUTED, "black", HORIZONTAL_ALIGNMENT_CENTER, wr.size.x)
	# shidos (cartons jaunes)
	for k in cfg.shido_limit:
		var sr = _mirror(Rect2(398 + k * 30, 58, 20, 24), i)
		var on2: bool = f.shidos > k
		_ci.draw_rect(Rect2(sr.position + Vector2(2, 2), sr.size), Style.INK)
		_ci.draw_rect(sr, Style.P1 if on2 else Style.NIGHT)
		_ci.draw_rect(sr, Style.INK, false, 2.5)
	# endurance
	var ratio = float(f.stamina) / float(cfg.stamina_max)
	var gcol = Style.GOOD if ratio > 0.5 else (Style.P1 if ratio > 0.25 else Style.DANGER)
	var gr = _mirror(Rect2(30, 96, 330, 22), i)
	Style.gauge(_ci, gr, ratio, gcol, flip)
	Style.label(_ci, Vector2(gr.position.x + (14 if i == 0 else 0), gr.position.y + 16), "ENDURANCE", 12, Style.INK, "black",
		HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT, gr.size.x - 14)
	# saisies
	for h in 2:
		var hand: Dictionary = f.hands[h]
		var cr = _mirror(Rect2(30 + h * 168, 126, 160, 28), i)
		var st: int = hand.state
		var fill = Style.NIGHT
		var tcol = Style.MUTED
		if st == Sim.HAND_GRIP:
			fill = col
			tcol = Style.INK
		elif st == Sim.HAND_REACH:
			fill = Style.NIGHT_3
			tcol = Style.PAPER
		Style.panel(_ci, cr, fill, Style.INK, 3.0, 3.0, Style.SLANT, flip)
		var side = "G" if h == 0 else "D"
		Style.label(_ci, Vector2(cr.position.x, cr.position.y + 20), "%s · %s" % [side, GRIP_LABELS[hand.target]], 14, tcol, "black", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
		# profondeur de la prise (barre sous la puce) et avant-bras qui chauffe
		if st == Sim.HAND_GRIP:
			var qr = Rect2(cr.position.x + 8, cr.end.y + 3, (cr.size.x - 16) * float(hand.q) / 10000.0, 5)
			_ci.draw_rect(Rect2(cr.position.x + 8, cr.end.y + 3, cr.size.x - 16, 5), Style.INK)
			_ci.draw_rect(qr, Style.GOOD if hand.q >= 7000 else (col if hand.q >= 4000 else Style.DANGER))
			if hand.fat > 6500:
				var hot = float(hand.fat - 6500) / 3500.0
				var pulse = 0.5 + 0.5 * sin(frame * 0.3)
				Style.panel(_ci, cr, Color(Style.DANGER, 0.25 + 0.35 * hot * pulse), Style.DANGER, 2.0, 0.0, Style.SLANT, flip)
	# radar de kuzushi
	var rc = Vector2(430.0 if i == 0 else W - 430.0, 152.0)
	if Settings.value("radar") and sim.state.phase != "newaza":
		_draw_radar(rc, f, col)


func _draw_radar(c: Vector2, f: Dictionary, col: Color) -> void:
	var r = 30.0
	_ci.draw_circle(c + Vector2(3, 3), r + 4, Style.INK)
	_ci.draw_circle(c, r + 4, Style.INK)
	_ci.draw_circle(c, r, Style.NIGHT)
	_ci.draw_arc(c, r * 0.5, 0, TAU, 24, Style.NIGHT_3, 2.0, true)
	_ci.draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Style.NIGHT_3, 1.5)
	_ci.draw_line(c - Vector2(0, r), c + Vector2(0, r), Style.NIGHT_3, 1.5)
	var fc: int = f.facing
	Style.label(_ci, c + Vector2(fc * (r + 8) - (0 if fc > 0 else 18), 5), "AV", 11, Style.MUTED, "black")
	Style.label(_ci, c + Vector2(-fc * (r + 8) - (18 if fc > 0 else 0), 5), "AR", 11, Style.MUTED, "black")
	var v = Vector2(fc * float(f.bal_x), float(f.bal_y)) / float(cfg.balance_max)
	var mag = clampf(v.length(), 0.0, 1.0)
	var dot = c + v.limit_length(1.0) * r
	var dcol = Style.GOOD.lerp(Style.DANGER, mag)
	_ci.draw_line(c, dot, dcol, 3.0, true)
	_ci.draw_circle(dot, 7.0, Style.INK)
	_ci.draw_circle(dot, 5.0, dcol)
	if mag > 0.65:
		_ci.draw_arc(c, r + 4, 0, TAU, 32, Style.DANGER, 3.0, true)


func _draw_timer() -> void:
	var r = Rect2(552, 16, 176, 76)
	Style.panel(_ci, r, Style.INK, Style.HOT if sim.state.golden else Style.PAPER, 4.0, 6.0)
	var ticks: int = sim.state.clock
	var secs = int(ceil(ticks / 60.0)) if not sim.state.golden else ticks / 60
	var txt = "%d:%02d" % [secs / 60, secs % 60]
	if sim.state.golden:
		txt = "+" + txt
	Style.text(_ci, Vector2(r.position.x, r.position.y + 60), txt, 58, Style.HOT if sim.state.golden else Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 4, 0.0)
	if sim.state.golden:
		var gr = Rect2(562, 96, 156, 26)
		Style.panel(_ci, gr, Style.HOT, Style.INK, 3.0, 3.0)
		Style.label(_ci, Vector2(gr.position.x, gr.position.y + 19), "GOLDEN SCORE", 16, Style.INK, "black", HORIZONTAL_ALIGNMENT_CENTER, gr.size.x)


## Jauge de domination au kumikata : bras de fer entre les deux joueurs.
var dom_shown = 0.0
func _draw_dominance() -> void:
	dom_shown = lerpf(dom_shown, float(sim.state.dom) / 10000.0, 0.15)
	var y = 132.0 if sim.state.golden else 102.0
	var r = Rect2(500, y, 280, 22)
	Style.panel(_ci, r, Style.NIGHT, Style.INK, 3.0, 3.0)
	var c = r.position.x + r.size.x * 0.5
	var inner = r.grow(-4)
	var half = inner.size.x * 0.5
	var v = clampf(dom_shown, -1.0, 1.0)
	if absf(v) * half > 3.0:
		var col = Style.P1 if v > 0.0 else Style.P2
		var w = half * absf(v)
		var fr = Rect2(c - w, inner.position.y, w, inner.size.y) if v > 0.0 else Rect2(c, inner.position.y, w, inner.size.y)
		_ci.draw_colored_polygon(Style.slant_points(fr, Style.SLANT, v < 0.0), col)
		if absf(v) > 0.6:
			var pulse = 0.5 + 0.5 * sin(frame * 0.3)
			_ci.draw_colored_polygon(Style.slant_points(fr, Style.SLANT, v < 0.0), Color(1, 1, 1, 0.25 * pulse))
	_ci.draw_line(Vector2(c, r.position.y - 3), Vector2(c, r.end.y + 3), Style.PAPER, 3.0)
	var txt = "KUMIKATA"
	if v > 0.3:
		txt = "%s DOMINE" % names[0]
	elif v < -0.3:
		txt = "%s DOMINE" % names[1]
	Style.label(_ci, Vector2(r.position.x, r.end.y + 17), txt, 13, Style.MUTED if absf(v) <= 0.3 else (Style.P1 if v > 0 else Style.P2), "black", HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_popups() -> void:
	var stack = [0, 0]
	for p in popups:
		# chaque judoka a sa colonne de bulles, décalée vers l'extérieur du couple
		var out = signf(_draw_x(p.who) - _draw_x(1 - p.who))
		var x = _draw_x(p.who) + out * 70.0
		var y = FEET_Y - 250.0 - stack[p.who] * 32.0 - minf(p.t, 20) * 1.2
		stack[p.who] += 1
		var a = 1.0 if p.t < 50 else 1.0 - (p.t - 50) / 20.0
		var col: Color = p.color
		col.a = a
		var wdt = Style.text_width(p.text, 24) + 20
		Style.text(_ci, Vector2(x - wdt / 2, y), p.text, 24, col, "display", HORIZONTAL_ALIGNMENT_CENTER, wdt, 4, 2.0)


func _draw_announce() -> void:
	var t: int = sim.state.announce_t
	if t <= 0:
		return
	var txt: String = sim.state.announce
	var age = 90 - t
	var s = 1.0 + maxf(0.0, (8 - age) / 8.0) * 0.35
	var alpha = 1.0 if t > 15 else t / 15.0
	var c = Vector2(640, 300)
	var col = Style.PAPER
	var fsize = 96
	match txt:
		"OSAEKOMI":
			col = Style.INK
			var ob = Rect2(c.x - 300 * s, c.y - 66 * s, 600 * s, 110 * s)
			Style.panel(_ci, ob, Color(Style.GOLD, alpha), Style.INK, 5.0, 8.0)
			fsize = 84
		"IPPON !":
			col = Style.GOLD
			fsize = 132
			Style.speed_lines(_ci, c, 150, 420, 46, Color(1, 0.85, 0.2, 0.55 * alpha))
			Style.burst(_ci, c, 120 * s, 190 * s, 14, Color(Style.HOT, alpha), Style.INK, 11, age * 0.01)
		"WAZA-ARI":
			col = Style.PAPER
			fsize = 100
			Style.speed_lines(_ci, c, 130, 360, 36, Color(0.24, 0.9, 1, 0.45 * alpha))
			Style.burst(_ci, c, 100 * s, 150 * s, 12, Color(Style.P2_DEEP, alpha), Style.INK, 5)
		"SHIDO", "HANSOKU-MAKE":
			col = Style.INK if txt == "SHIDO" else Style.PAPER
			var card = Rect2(c.x - 230 * s, c.y - 70 * s, 460 * s, 120 * s)
			Style.panel(_ci, card, Color(Style.P1 if txt == "SHIDO" else Style.DANGER, alpha), Style.INK, 5.0, 8.0)
			fsize = 88
		_:
			var pc = Style.HOT if txt in ["HAJIME", "GOLDEN SCORE"] else Style.NIGHT_2
			if txt == "GOLDEN SCORE":
				pc = Style.GOLD
				col = Style.INK
			var band = Rect2(c.x - 300 * s, c.y - 66 * s, 600 * s, 110 * s)
			Style.panel(_ci, band, Color(pc, alpha), Style.INK, 5.0, 8.0)
			fsize = 84
	var tc = col
	tc.a = alpha
	Style.text(_ci, Vector2(0, c.y + fsize * 0.36), txt, int(fsize * s), tc, "display", HORIZONTAL_ALIGNMENT_CENTER, W, int(fsize * s / 10), 6.0)


func _draw_feed() -> void:
	var y = 662.0
	for k in range(feed.size() - 1, -1, -1):
		var e: Dictionary = feed[k]
		var a = 1.0 if e.t < 300 else maxf(0.0, 1.0 - (e.t - 300) / 60.0)
		if a <= 0.0:
			continue
		var wdt = Style.text_width(e.text, 15, "black") + 34
		var r = Rect2(24, y - 24, wdt, 26)
		Style.panel(_ci, r, Color(Style.INK, 0.85 * a), Color(e.color, a), 2.0, 0.0)
		Style.label(_ci, Vector2(r.position.x + 14, r.position.y + 19), e.text, 15, Color(e.color, a), "black")
		y -= 31.0


func _draw_hints() -> void:
	var y = 694.0
	var x = 28.0
	if sim.state.phase == "newaza":
		var nitems = [["A", "Contrôler"], ["X", "Clé de bras"], ["Y", "Étranglement"], ["B", "Se dégager"], ["R", "Stick gauche : gigoter (dessous)"]]
		var nwh: Dictionary = sim.state.newaza
		if not nwh.is_empty() and nwh.osae and nwh.has("ct"):
			nitems = [["A", "Dessus : tenir, quand ton curseur est dans ta zone"], ["B", "Dessous : sortir, même principe"], ["X", "Clé"], ["Y", "Étranglement"], ["R", "Centre doré = parfait · raté = bloqué"]]
		for it in nitems:
			if it[0] == "R":
				Style.label(_ci, Vector2(x, y + 6), it[1], 15, Style.MUTED, "bold")
				continue
			Style.pad_button(_ci, Vector2(x + 12, y), it[0], 12.0)
			x += 34.0
			Style.label(_ci, Vector2(x, y + 6), it[1], 15, Style.MUTED, "bold")
			x += Style.text_width(it[1], 15, "bold") + 26
		return
	var items = [["LT", "RT", "Saisir"], ["LB", "RB", "Cible"], ["R", "", "Stick D : kuzushi"], ["R", "", "Pichenette stick G : dash"], ["A", "", "Technique"],
		["X", "", "Jambe"], ["Y", "", "Tokui"], ["B", "", "Chasser / casser / contrer"]]
	for it in items:
		if it[0] == "R":
			Style.label(_ci, Vector2(x, y + 6), it[2], 15, Style.MUTED, "bold")
			x += Style.text_width(it[2], 15, "bold") + 26
			continue
		Style.pad_button(_ci, Vector2(x + 12, y), it[0], 12.0)
		x += 34.0 if it[0].length() == 1 else 40.0
		if it[1] != "":
			Style.pad_button(_ci, Vector2(x + 12, y), it[1], 12.0)
			x += 40.0
		Style.label(_ci, Vector2(x, y + 6), it[2], 15, Style.MUTED, "bold")
		x += Style.text_width(it[2], 15, "bold") + 26


func _draw_pause() -> void:
	_ci.draw_rect(Rect2(0, 0, W, H), Color(0.04, 0.03, 0.1, 0.72))
	Style.halftone(_ci, Rect2(0, 0, W, H), Color(1, 1, 1, 0.04), 18.0, 5.0, Vector2(1, 0))
	Style.text(_ci, Vector2(0, 200), "PAUSE", 96, Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, W)
	for k in PAUSE_ITEMS.size():
		var sel = k == pause_index
		var r = Rect2(440 - (12 if sel else 0), 250 + k * 70, 400 + (24 if sel else 0), 56)
		Style.panel(_ci, r, Style.HOT if sel else Style.NIGHT_2, Style.INK, 4.0, 6.0)
		Style.text(_ci, Vector2(r.position.x, r.position.y + 41), PAUSE_ITEMS[k], 32, Style.INK if sel else Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 3, 0.0)


# =============================================================================
# Arbitre
# =============================================================================

const REF_SCALE := 0.74    # au fond du tatami, donc plus petit
const REF_FEET_Y := 566.0
const REF_OFFSET := 150.0  # distance latérale à l'action


## Centre de l'action (monde, px) et éventuel judoka désigné par le geste en cours.
func _action_center() -> float:
	var st: Dictionary = sim.state
	if not st.newaza.is_empty() and st.phase in ["newaza", "score", "ended"]:
		return _newaza_center_x(st.newaza)
	if not st.throw.is_empty() and st.phase in ["throw", "score", "ended"]:
		return (wx(st.throw.tori_x) + wx(st.throw.uke_x)) * 0.5
	return (_draw_x(0) + _draw_x(1)) * 0.5


## Geste officiel selon l'annonce en cours : [main arrière, main avant, inclinaison, joueur visé].
func _referee_gesture() -> Dictionary:
	var st: Dictionary = sim.state
	var g = {"hb": Vector2(-3, -44), "hf": Vector2(5, -44), "bow": 0.0, "target": -1}
	var call: String = st.announce if st.announce_t > 0 else ""
	if st.phase == "newaza" and st.newaza.get("osae", false):
		call = "OSAEKOMI"
	var scorer = -1
	if not st.throw.is_empty():
		scorer = st.throw.tori
	elif not st.newaza.is_empty():
		scorer = st.newaza.top
	match call:
		"IPPON !":
			g.hf = Vector2(10, -122)  # bras tendu vers le ciel
			g.target = st.winner if st.winner >= 0 else scorer
		"WAZA-ARI":
			g.hf = Vector2(40, -76)  # bras à l'horizontale, côté du marqueur
			g.target = scorer
		"MATTE":
			g.hf = Vector2(38, -86)  # main levée, paume vers la table
			g.hb = Vector2(-2, -46)
		"HAJIME":
			g.hb = Vector2(24, -70)
			g.hf = Vector2(30, -74)
		"OSAEKOMI":
			g.hf = Vector2(38, -52)  # bras tendu vers les combattants, penché
			g.bow = 0.35
			g.target = scorer
		"TOKETA":
			var wave = sin(frame * 0.5) * 8.0
			g.hf = Vector2(38, -70 + wave)
			g.target = scorer
		"SHIDO":
			g.hf = Vector2(38, -60)  # désigne le pénalisé
			var pen = 0 if st.fighters[0].shidos > st.fighters[1].shidos else 1
			g.target = pen
		"SORE-MADE", "HANSOKU-MAKE", "GOLDEN SCORE":
			g.hb = Vector2(22, -68)
			g.hf = Vector2(30, -72)
	if st.phase == "ended" and st.announce_t <= 0 and st.winner >= 0:
		g.hf = Vector2(28, -112)  # désigne le vainqueur
		g.target = st.winner
	return g


## Palette de l'arbitre légèrement fondue dans le décor (profondeur).
var _ref_pal: Dictionary = _make_ref_pal()


static func _make_ref_pal() -> Dictionary:
	var pal: Dictionary = Art.referee_palette()
	for key in pal.keys():
		if pal[key] is Color:
			pal[key] = (pal[key] as Color).lerp(Color("2a2350"), 0.18)
	return pal


## Déplacement de l'arbitre (appelé à chaque image, même quand rien n'est redessiné).
func _update_referee() -> void:
	if sim == null:
		return
	var center = _action_center()
	# au fond, dans le champ de la caméra
	var hw = 640.0 / cam_z
	var lo = cam_c.x - hw + 70.0
	var hi = cam_c.x + hw - 70.0
	# entre les deux judokas quand ils sont écartés (comme au hajime), sinon sur le côté
	var gap = 0.0
	if sim.state.throw.is_empty() and sim.state.newaza.is_empty():
		gap = absf(_draw_x(0) - _draw_x(1))
	var off = 0.0 if gap > 230.0 else maxf(REF_OFFSET, gap * 0.5 + 200.0)
	var target_x = center + ref_side * off
	if target_x < lo or target_x > hi:
		var other = center - ref_side * off
		if other >= lo and other <= hi:
			ref_side = -ref_side
			target_x = other
	target_x = clampf(target_x, maxf(lo, 110.0), minf(hi, W - 110.0))
	var dx = target_x - ref_x
	ref_x += clampf(dx * 0.1, -6.5, 6.5)
	ref_walking = absf(dx) > 6.0
	if ref_walking:
		ref_walk += 0.25


func _draw_referee() -> void:
	var g = _referee_gesture()
	var center = _action_center()
	var walking = ref_walking
	# regarde l'action, ou le judoka désigné par son geste
	var look_x = center
	if g.target >= 0:
		look_x = _draw_x(g.target) if sim.state.newaza.is_empty() else center
	ref_face = 1 if look_x > ref_x else -1
	var pose: Dictionary = Art.pose_stand(0.15)
	pose.hb = g.hb
	pose.hf = g.hf
	pose.bow = g.bow
	if walking:
		pose.fb += Vector2(sin(ref_walk) * 4.0, -maxf(0.0, cos(ref_walk)) * 3.0)
		pose.ff += Vector2(-sin(ref_walk) * 4.0, -maxf(0.0, -cos(ref_walk)) * 3.0)
		pose.erase("kb")
		pose.erase("kf")
	if g.bow > 0.0:
		pose.hip += Vector2(-2, 4)
		pose.erase("kb")
		pose.erase("kf")
	var k = K * REF_SCALE
	var xf = Transform2D(0.0, Vector2(ref_face * k, k), 0.0, Vector2(ref_x, REF_FEET_Y))
	Art.shadow(_ci, Vector2(ref_x, REF_FEET_Y + 2), k, 0.22)
	Art.draw_fighter(_ci, xf, _ref_pal, pose)
