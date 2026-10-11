extends RefCounted
## Session de dojo, branchée sur l'écran de combat : leçon guidée (étapes validées
## par le jeu) ou entraînement libre (partenaire réglable, données, entrées,
## enregistrement). Pilote le partenaire, assouplit les règles, dessine les panneaux.

const Sim := preload("res://scripts/sim/match_sim.gd")
const Style := preload("res://scripts/ui/style.gd")
const Lessons := preload("res://scripts/dojo/lessons.gd")
const Partner := preload("res://scripts/dojo/partner.gd")
const Progress := preload("res://scripts/dojo/progress.gd")
const Readout := preload("res://scripts/view/readout.gd")
const Pad := preload("res://scripts/pad_reader.gd")
const Rich := preload("res://scripts/ui/rich.gd")

const W := 1280.0
const H := 720.0

var screen  # match_screen
var mode = "lesson"        # "lesson" ou "training"
var lesson: Dictionary = {}
var step_i = 0
var progress = 0
var phase = "intro"        # intro, step, success, done
var phase_t = 0
var latch = false
var partner = Partner.new()
var feint_tick = -9999
var last_attack_combo = false
var newaza_wait = 0
var ended_t = 0
var setup_wait = 0
var frame = 0
var opts = {"stamina": true, "data": true, "inputs": true}
# pause du dojo
var menu_open = false
var menu_i = 0
# entrées affichées (historique façon jeu de combat)
var hist: Array = []        # [{dir, btns, n}]
var last_inp: Array = Sim.empty_input()
# enregistrement du partenaire (entraînement)
var rec_state = ""         # "", "wait", "rec"
var rec_t = 0
var rec_buf: Array = []


func _init(match_screen, cfg_in: Dictionary) -> void:
	screen = match_screen
	mode = cfg_in.get("mode", "lesson")
	if mode == "lesson":
		lesson = Lessons.by_id(cfg_in.get("lesson", "b1_distance"))
		partner.set_mode(_step().partner)
	else:
		phase = "step"
		partner.set_mode(cfg_in.get("partner", "garde"))


## Paramètres de combat pour lancer une leçon ou l'entraînement.
static func match_params(cfg_in: Dictionary, player_controller: String) -> Dictionary:
	var pb: Dictionary
	var ub: Dictionary
	if cfg_in.get("mode", "lesson") == "lesson":
		var l = Lessons.by_id(cfg_in.get("lesson", "b1_distance"))
		pb = l.player
		ub = l.partner_build
	else:
		pb = cfg_in.get("build", Lessons.player_default())
		ub = Lessons.partner_default()
	return {"controllers": [player_controller, "dojo"], "names": [String(pb.get("name", "TOI")), "UKE"],
		"tokui": [pb.slots.tokui[0], ub.slots.tokui[0]], "builds": [pb, ub], "seed": 7, "level": 2,
		"mode": "dojo", "dojo": cfg_in}


func _step() -> Dictionary:
	if lesson.is_empty():
		return {"title": "", "text": "", "goal": {"type": "none"}, "partner": "garde", "count": 1, "setup": "", "tip": ""}
	return lesson.steps[clampi(step_i, 0, lesson.steps.size() - 1)]


# =============================================================================
# Entrées
# =============================================================================

## Entrées du partenaire (joueur 2).
func partner_input(sim) -> Array:
	if rec_state == "rec":
		var inp: Array = Pad.read(0)
		rec_buf.append(inp.duplicate())
		return inp
	if mode == "lesson" and phase != "step":
		return Sim.empty_input()
	return partner.think(sim)


## Entrées du joueur, filtrées (intro, réussite, enregistrement, garde assistée).
func player_input(sim, inp: Array) -> Array:
	_record_history(inp)
	if rec_state != "" or menu_open:
		return Sim.empty_input()
	if mode == "lesson" and phase != "step":
		return Sim.empty_input()
	if mode == "lesson" and _step().setup == "gripped" and sim.state.phase == "fight":
		# garde maintenue automatiquement : on se concentre sur le sujet de l'étape
		inp[Sim.LT] = maxi(inp[Sim.LT], 80)
		inp[Sim.RT] = maxi(inp[Sim.RT], 80)
	return inp


func _record_history(inp: Array) -> void:
	var d = _dir_glyph(inp[Sim.MX], 0)
	var b = []
	for pair in [["A", Sim.BA], ["B", Sim.BB], ["X", Sim.BX], ["Y", Sim.BY], ["LB", Sim.LB], ["RB", Sim.RB]]:
		if inp[pair[1]] != 0:
			b.append(pair[0])
	if inp[Sim.LT] > 25:
		b.append("LT")
	if inp[Sim.RT] > 25:
		b.append("RT")
	var key = d + "|" + ",".join(b)
	if not hist.is_empty() and hist[0].key == key:
		hist[0].n = mini(hist[0].n + 1, 99)
	else:
		hist.push_front({"key": key, "dir": d, "btns": b, "n": 1})
		if hist.size() > 12:
			hist.pop_back()
	last_inp = inp.duplicate()


func _dir_glyph(mx: int, my: int) -> String:
	if absi(mx) < 25 and absi(my) < 25:
		return "•"
	return "→" if mx > 0 else "←"


# =============================================================================
# Règles du dojo et déroulé
# =============================================================================

func pre_step(sim) -> void:
	frame += 1
	var s: Dictionary = sim.state
	var cfg: Dictionary = sim.cfg
	s.clock = cfg.match_ticks
	s.golden = false
	for f in s.fighters:
		f.passive_t = 0
		f.nogrip_t = 0
		f.shidos = 0
		if opts.stamina or mode == "lesson":
			f.stamina = f.stamina_max
		if s.phase == "fight":
			f.waza = 0
			f.ippon = 0
	# fin de « combat » : on repart
	if s.phase == "ended":
		ended_t += 1
		if ended_t > 110:
			ended_t = 0
			s.winner = -1
			s.win_reason = ""
			for f in s.fighters:
				f.waza = 0
				f.ippon = 0
			sim._matte()
	var setup: String = _step().setup if mode == "lesson" else ""
	var ground: bool = setup.begins_with("newaza")
	# debout : pas de sol interminable après un waza-ari
	if s.phase == "newaza" and not ground and mode == "lesson":
		newaza_wait += 1
		if newaza_wait > 70:
			newaza_wait = 0
			sim._matte()
	# mise en place de l'étape
	if mode == "lesson" and phase == "step" and s.phase == "fight":
		setup_wait += 1
		if ground and setup_wait >= 20:
			_place(sim, cfg.garde_dist.lapel)
			sim._start_newaza(0 if setup == "newaza_top" else 1)
			setup_wait = 0
		elif setup == "gripped" and setup_wait == 2 and not sim.has_grip(s.fighters[0]):
			_place(sim, cfg.garde_dist.lapel)
			_set_grips(sim)


## Replace les deux judokas au centre, à une distance donnée.
func _place(sim, gap: int) -> void:
	var fs: Array = sim.state.fighters
	var center: int = (sim.cfg.mat_left + sim.cfg.mat_right) / 2
	fs[0].x = center - gap / 2
	fs[1].x = center + gap / 2
	fs[0].facing = 1
	fs[1].facing = -1


## Garde du joueur installée d'office (cibles de la technique étudiée).
func _set_grips(sim) -> void:
	var f: Dictionary = sim.state.fighters[0]
	var targets: Array = ["sleeve", "lapel"]
	if lesson.has("tech"):
		targets = sim.techs[lesson.tech].grips[0].duplicate()
		if targets.size() == 1:
			targets.append("lapel")
	var tg: Array = sim.cfg.grip_targets
	for h in 2:
		var hand: Dictionary = f.hands[h]
		hand.target = tg.find(targets[h])
		hand.state = Sim.HAND_GRIP
		hand.t = sim.cfg.grip_settle_ticks
		hand.q = 10000
		hand.fat = 0
		hand.lock = 0


func post_step(sim) -> void:
	if rec_state != "":
		_update_recording()
	if mode != "lesson":
		return
	phase_t += 1
	match phase:
		"intro":
			if _auto() and phase_t > 150:
				_start_steps()
		"step":
			var n = _check_goal(sim, _step().goal)
			if n > 0:
				progress += n
				Sound.play("ui_tab", -2.0, 1.4, 0.0)
				if progress >= int(_step().count):
					phase = "success"
					phase_t = 0
					Sound.play("ui_accept", 0.0, 1.0, 0.0)
		"success":
			if phase_t >= 80:
				if step_i + 1 < lesson.steps.size():
					_enter_step(step_i + 1)
				else:
					phase = "done"
					phase_t = 0
					Progress.mark_done(lesson.id)
					Sound.play("stinger_wazaari", -4.0, 1.0, 0.0)
		"done":
			if _auto() and phase_t > 160 and screen.app != null and not screen.app.capture_mode:
				_goto_lesson(Lessons.next_of(lesson.id))


## Joueur piloté par l'IA (démo, captures) : les écrans d'attente avancent seuls.
func _auto() -> bool:
	return screen.controllers[0] == "ai"


func _start_steps() -> void:
	_enter_step(0)


func _enter_step(i: int) -> void:
	step_i = i
	progress = 0
	latch = false
	phase = "step"
	phase_t = 0
	setup_wait = 0
	partner.set_mode(_step().partner)
	var setup: String = _step().setup
	var sim = screen.sim
	if setup == "" and sim.state.phase in ["newaza"]:
		sim._matte()


func _restart_step() -> void:
	var sim = screen.sim
	sim._reset_positions()
	sim._set_phase("fight")
	_enter_step(step_i)


func _goto_lesson(id: String) -> void:
	if screen.app == null:
		return
	if id == "":
		screen.app.goto("dojo", {"cat": lesson.get("cat", "base")})
		return
	screen.app.goto("match", match_params({"mode": "lesson", "lesson": id}, screen.app.human_controller()))


# =============================================================================
# Objectifs
# =============================================================================

## Renvoie le nombre de réussites obtenues à cette image.
func _check_goal(sim, goal: Dictionary) -> int:
	var s: Dictionary = sim.state
	var cfg: Dictionary = sim.cfg
	var me: Dictionary = s.fighters[0]
	var uk: Dictionary = s.fighters[1]
	var dist: int = absi(uk.x - me.x)
	var hits = 0
	# objectifs sur événements
	for e in sim.events:
		if e.get("who", -1) != 0:
			continue
		match e.type:
			"attack":
				last_attack_combo = e.get("combo", false)
			"feint":
				feint_tick = s.tick
		match goal.type:
			"parry", "whiff", "break", "feint", "block", "reaction", "combo_open", "osaekomi":
				if e.type == goal.type:
					hits += 1
			"dash":
				if e.type == "dash" and e.dir == goal.dir:
					hits += 1
			"counter":
				if e.type == "counter" and (not goal.has("tech") or e.tech == goal.tech):
					hits += 1
			"block_or_counter":
				if e.type in ["block", "counter"]:
					hits += 1
			"escape":
				if e.type in ["escape", "toketa", "sub_escape"]:
					hits += 1
			"submission":
				if e.type == "submission" and (not goal.has("tech") or e.tech == goal.tech):
					hits += 1
			"throw", "combo_throw", "feint_throw":
				if e.type == "throw" and _throw_matches(sim, goal, e):
					hits += 1
	if hits > 0:
		return hits
	# objectifs sur l'état (comptés au front montant)
	var ok = false
	match goal.type:
		"range":
			ok = dist <= cfg.grip_range
		"away":
			ok = dist > cfg.grip_range + 1500
		"grip":
			for h in 2:
				var hand: Dictionary = me.hands[h]
				if hand.state == Sim.HAND_GRIP and (int(goal.get("hand", -1)) < 0 or h == int(goal.hand)) \
						and (not goal.has("target") or cfg.grip_targets[hand.target] == goal.target):
					ok = true
		"grip_pair":
			ok = me.hands[0].state == Sim.HAND_GRIP and me.hands[1].state == Sim.HAND_GRIP
		"grip_set":
			var held = []
			for hand in me.hands:
				if hand.state == Sim.HAND_GRIP:
					held.append(cfg.grip_targets[hand.target])
			ok = true
			for g in goal.targets:
				var k = held.find(g)
				if k < 0:
					ok = false
				else:
					held.remove_at(k)
		"settled":
			ok = true
			for hand in me.hands:
				if hand.state != Sim.HAND_GRIP or hand.q < 9000:
					ok = false
		"dom":
			ok = sim.dom_of(0) >= int(goal.min)
		"kuzushi":
			ok = sim.dir_value(1, goal.dir) >= int(goal.min)
		"tsukuri":
			ok = sim.dir_value(1, "avant") >= int(goal.min) and me.last_move * me.facing < 0
		"osae_time":
			var nw: Dictionary = s.newaza
			ok = not nw.is_empty() and nw.top == 0 and nw.osae and nw.osae_t >= int(goal.ticks)
		"control":
			var nw2: Dictionary = s.newaza
			ok = not nw2.is_empty() and nw2.top == 0 and nw2.control >= int(goal.min)
		"read":
			ok = _auto() and phase_t > 200
	if ok and not latch:
		latch = true
		return 1
	if not ok:
		latch = false
	return 0


func _throw_matches(sim, goal: Dictionary, e: Dictionary) -> bool:
	if goal.has("tech") and e.tech != goal.tech:
		return false
	if goal.has("result") and e.result != goal.result:
		return false
	if goal.has("dir") and not String(sim.tech_dir(e.tech)).begins_with(goal.dir):
		return false
	if goal.get("sweep", false) and not (sim.techs.has(e.tech) and sim.is_sweep(e.tech)):
		return false
	if goal.type == "combo_throw" and not last_attack_combo:
		return false
	if goal.type == "feint_throw" and sim.state.tick - feint_tick > 150:
		return false
	return true


# =============================================================================
# Navigation (renvoie true si l'action est consommée)
# =============================================================================

func training_items() -> Array:
	return [["REPRENDRE", ""], ["PARTENAIRE", Partner.NAMES.get(partner.mode, partner.mode)],
		["ENDURANCE INFINIE", "OUI" if opts.stamina else "NON"], ["DONNÉES", "OUI" if opts.data else "NON"],
		["ENTRÉES", "OUI" if opts.inputs else "NON"], ["ENREGISTRER LE PARTENAIRE", "10 s"],
		["REPLACER", ""], ["QUITTER LE DOJO", ""]]


func lesson_items() -> Array:
	return [["REPRENDRE", ""], ["RECOMMENCER L'ÉTAPE", ""], ["ÉTAPE SUIVANTE", ""], ["LEÇON SUIVANTE", ""],
		["DONNÉES", "OUI" if opts.data else "NON"], ["ENTRÉES", "OUI" if opts.inputs else "NON"], ["QUITTER LE DOJO", ""]]


func nav(action: String) -> bool:
	if action == "start":
		menu_open = not menu_open
		menu_i = 0
		screen.paused = menu_open
		return true
	if menu_open:
		_menu_nav(action)
		return true
	if action == "select":
		if mode == "lesson":
			_restart_step()
		else:
			screen.sim._reset_positions()
			screen.sim._set_phase("fight")
		return true
	if mode == "lesson":
		match phase:
			"intro":
				if action == "accept":
					_start_steps()
				elif action == "back":
					_goto_lesson("")
				return true
			"done":
				match action:
					"accept":
						_goto_lesson(Lessons.next_of(lesson.id))
					"x":
						screen.app.goto("match", match_params({"mode": "lesson", "lesson": lesson.id}, screen.app.human_controller()))
					"back":
						_goto_lesson("")
				return true
			"step":
				if action == "accept" and _step().goal.type == "read":
					progress += 1
					if progress >= int(_step().count):
						phase = "success"
						phase_t = 0
						Sound.play("ui_accept", 0.0, 1.0, 0.0)
				return action in ["accept"]
	return false


func _menu_nav(action: String) -> void:
	var items = training_items() if mode == "training" else lesson_items()
	match action:
		"up":
			menu_i = (menu_i + items.size() - 1) % items.size()
		"down":
			menu_i = (menu_i + 1) % items.size()
		"back":
			menu_open = false
			screen.paused = false
		"left", "right", "accept":
			var label: String = items[menu_i][0]
			var d = -1 if action == "left" else 1
			match label:
				"REPRENDRE":
					if action == "accept":
						menu_open = false
						screen.paused = false
				"PARTENAIRE":
					var list: Array = Partner.BEHAVIORS
					var k = list.find(partner.mode)
					partner.set_mode(list[(k + d + list.size()) % list.size()])
				"ENDURANCE INFINIE":
					opts.stamina = not opts.stamina
				"DONNÉES":
					opts.data = not opts.data
				"ENTRÉES":
					opts.inputs = not opts.inputs
				"ENREGISTRER LE PARTENAIRE":
					if action == "accept":
						rec_state = "wait"
						rec_t = 0
						rec_buf = []
						menu_open = false
						screen.paused = false
				"REPLACER":
					if action == "accept":
						screen.sim._reset_positions()
						screen.sim._set_phase("fight")
						menu_open = false
						screen.paused = false
				"RECOMMENCER L'ÉTAPE":
					if action == "accept":
						menu_open = false
						screen.paused = false
						_restart_step()
				"ÉTAPE SUIVANTE":
					if action == "accept":
						menu_open = false
						screen.paused = false
						phase = "success"
						phase_t = 79
				"LEÇON SUIVANTE":
					if action == "accept":
						_goto_lesson(Lessons.next_of(lesson.id))
				"QUITTER LE DOJO":
					if action == "accept":
						screen.app.goto("dojo", {"cat": lesson.get("cat", "training")})


func _update_recording() -> void:
	rec_t += 1
	if rec_state == "wait" and rec_t >= 180:
		rec_state = "rec"
		rec_t = 0
		rec_buf = []
	elif rec_state == "rec" and rec_t >= 600:
		rec_state = ""
		partner.recording = rec_buf.duplicate()
		partner.set_mode("replay")
		partner.replay_i = 0


# =============================================================================
# Dessin (calque HUD, coordonnées écran)
# =============================================================================

func draw(ci: CanvasItem) -> void:
	var sim = screen.sim
	_draw_badge(ci)
	if opts.data and sim.state.phase == "fight":
		_draw_data(ci, sim)
	if opts.inputs:
		_draw_inputs(ci)
	if mode == "lesson":
		match phase:
			"intro":
				_draw_intro(ci)
			"step", "success":
				_draw_step_card(ci)
				if phase == "success":
					_draw_success(ci)
			"done":
				_draw_done(ci)
	else:
		_draw_training_card(ci)
	if rec_state != "":
		_draw_recording(ci)
	if menu_open:
		_draw_menu(ci)


func _draw_badge(ci: CanvasItem) -> void:
	var r = Rect2(552, 16, 176, 76)
	Style.panel(ci, r, Style.INK, Style.GOOD, 4.0, 6.0)
	Style.text(ci, Vector2(r.position.x, r.position.y + 50), "DOJO", 44, Style.GOOD, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 4, 0.0)
	var sub = "ENTRAÎNEMENT"
	if mode == "lesson":
		var cat_list = Lessons.in_category(lesson.cat)
		var idx = 0
		for k in cat_list.size():
			if cat_list[k].id == lesson.id:
				idx = k
		sub = "LEÇON %d / %d" % [idx + 1, cat_list.size()]
	Style.label(ci, Vector2(r.position.x, r.position.y + 68), sub, 12, Style.MUTED, "black", HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## Carte d'introduction de la leçon (au centre).
func _draw_intro(ci: CanvasItem) -> void:
	var t = clampf(phase_t / 14.0, 0.0, 1.0)
	var intro_lines = Rich.layout(lesson.intro, 690, 19)
	var hgt = 200.0 + intro_lines.size() * 26.0
	var r = Rect2(240, clampf(340.0 - hgt * 0.5, 110.0, 300.0) + (1.0 - t) * 40.0, 800, hgt)
	ci.draw_rect(Rect2(0, 0, W, H), Color(0.04, 0.03, 0.1, 0.45 * t))
	Style.panel(ci, r, Style.NIGHT_2, Style.GOOD, 4.0, 8.0)
	var cat_name = ""
	for c in Lessons.CATEGORIES:
		if c.id == lesson.cat:
			cat_name = c.name
	Style.label(ci, r.position + Vector2(48, 40), "DOJO · %s" % cat_name, 15, Style.GOOD, "black", HORIZONTAL_ALIGNMENT_LEFT, 690)
	Style.text(ci, r.position + Vector2(44, 96), String(lesson.title).to_upper(), 46, Style.PAPER, "display", HORIZONTAL_ALIGNMENT_LEFT, 700)
	Rich.draw_lines(ci, r.position + Vector2(48, 140), intro_lines, 19, Style.PAPER, 26.0)
	Style.label(ci, Vector2(r.position.x + 48, r.end.y - 26), "%d ÉTAPES" % lesson.steps.size(), 14, Style.MUTED, "black")
	var hx = r.end.x - 250
	Style.pad_button(ci, Vector2(hx, r.end.y - 31), "A", 13.0)
	Style.label(ci, Vector2(hx + 22, r.end.y - 25), "COMMENCER", 16, Style.PAPER, "black")
	Style.pad_button(ci, Vector2(hx + 150, r.end.y - 31), "B", 13.0)
	Style.label(ci, Vector2(hx + 172, r.end.y - 25), "DOJO", 16, Style.PAPER, "black")


## Carte de consigne de l'étape (à gauche).
func _draw_step_card(ci: CanvasItem) -> void:
	var st = _step()
	var x = 24.0
	var y = 200.0
	var w = 440.0
	var tw = w - 76.0  # marge gauche + coin incliné à droite
	var lines = Rich.layout(st.text, tw, 19)
	var tip_lines: Array = Rich.layout(st.tip, tw, 15) if st.tip != "" else []
	var hgt = 96.0 + lines.size() * 26.0 + (tip_lines.size() * 20.0 + 14.0 if not tip_lines.is_empty() else 0.0)
	if int(st.count) > 1:
		hgt += 30.0
	if st.setup == "gripped":
		hgt += 22.0
	var r = Rect2(x, y, w, hgt)
	Style.panel(ci, r, Color(Style.NIGHT_2, 0.94), Style.GOOD if phase == "success" else Style.P1, 4.0, 6.0)
	Style.label(ci, Vector2(x + 30, y + 26), "ÉTAPE %d / %d  ·  %s" % [step_i + 1, lesson.steps.size(), String(lesson.title).to_upper()], 13, Style.MUTED, "black", HORIZONTAL_ALIGNMENT_LEFT, tw)
	Style.text(ci, Vector2(x + 26, y + 62), String(st.title).to_upper(), 30, Style.P1, "display", HORIZONTAL_ALIGNMENT_LEFT, tw)
	var yy = y + 92.0
	Rich.draw_lines(ci, Vector2(x + 30, yy), lines, 19, Style.PAPER, 26.0)
	yy += lines.size() * 26.0
	if int(st.count) > 1:
		for k in int(st.count):
			var c = Vector2(x + 40 + k * 26, yy + 10)
			ci.draw_circle(c, 9.0, Style.INK)
			ci.draw_circle(c, 7.0, Style.GOOD if k < progress else Style.NIGHT)
		yy += 30.0
	if st.setup == "gripped":
		Style.label(ci, Vector2(x + 30, yy + 14), "Garde maintenue automatiquement", 13, Style.MUTED, "bold")
		yy += 22.0
	if not tip_lines.is_empty():
		yy += 8.0
		ci.draw_line(Vector2(x + 30, yy), Vector2(x + w - 50, yy), Style.NIGHT_3, 2.0)
		Rich.draw_lines(ci, Vector2(x + 30, yy + 20), tip_lines, 15, Style.MUTED, 20.0)


func _draw_success(ci: CanvasItem) -> void:
	var t = phase_t
	var s = 1.0 + maxf(0.0, (8 - t) / 8.0) * 0.5
	var a = 1.0 if t < 60 else maxf(0.0, 1.0 - (t - 60) / 20.0)
	var c = Vector2(640, 300)
	Style.burst(ci, c, 70 * s, 110 * s, 12, Color(Style.GOOD, a), Style.INK, 9, t * 0.01)
	Style.text(ci, Vector2(0, c.y + 30), "RÉUSSI !", int(84 * s), Color(Style.INK, a), "display", HORIZONTAL_ALIGNMENT_CENTER, W, 2, -1.0)


func _draw_done(ci: CanvasItem) -> void:
	var t = clampf(phase_t / 14.0, 0.0, 1.0)
	ci.draw_rect(Rect2(0, 0, W, H), Color(0.04, 0.03, 0.1, 0.55 * t))
	var r = Rect2(300, 200, 680, 250)
	Style.panel(ci, r, Style.GOOD, Style.INK, 5.0, 10.0)
	Style.text(ci, Vector2(r.position.x + 30, r.position.y + 92), "LEÇON TERMINÉE", 60, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 60, 2, -1.0)
	Style.label(ci, Vector2(r.position.x + 30, r.position.y + 132), String(lesson.title).to_upper(), 20, Style.INK, "black", HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 60)
	var items = [["A", "LEÇON SUIVANTE"], ["X", "RECOMMENCER"], ["B", "DOJO"]]
	var x = r.position.x + 60
	for it in items:
		Style.pad_button(ci, Vector2(x, r.end.y - 50), it[0], 14.0)
		Style.label(ci, Vector2(x + 24, r.end.y - 43), it[1], 18, Style.INK, "black")
		x += Style.text_width(it[1], 18, "black") + 70


func _draw_training_card(ci: CanvasItem) -> void:
	var r = Rect2(24, 200, 380, 100)
	Style.panel(ci, r, Color(Style.NIGHT_2, 0.9), Style.GOOD, 3.0, 5.0)
	Style.label(ci, Vector2(r.position.x + 28, r.position.y + 28), "PARTENAIRE", 13, Style.MUTED, "black")
	Style.text(ci, Vector2(r.position.x + 26, r.position.y + 60), Partner.NAMES.get(partner.mode, partner.mode).to_upper(), 24, Style.GOOD, "display", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 70)
	Style.label(ci, Vector2(r.position.x + 28, r.position.y + 86), "Pause : réglages · View : replacer", 13, Style.MUTED, "bold", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 70)


## Données d'entraînement (à droite) : kuzushi du partenaire, réaction, et ce que donne chaque bouton.
func _draw_data(ci: CanvasItem, sim) -> void:
	var x = 836.0
	var y = 200.0
	var r = Rect2(x, y, 420, 214)
	Style.panel(ci, r, Color(Style.NIGHT_2, 0.9), Style.P2, 3.0, 5.0, Style.SLANT, true)
	Style.label(ci, Vector2(x + 26, y + 26), "DÉSÉQUILIBRE DU PARTENAIRE", 13, Style.MUTED, "black")
	var dirs = [["AVANT", "avant"], ["ARRIÈRE", "arriere"], ["CÔTÉ", "cote"]]
	for k in dirs.size():
		var v = float(sim.dir_value(1, dirs[k][1])) / 10000.0
		var yy = y + 44 + k * 24
		Style.label(ci, Vector2(x + 26, yy + 15), dirs[k][0], 13, Style.PAPER, "black")
		Style.gauge(ci, Rect2(x + 110, yy, 190, 18), v, Style.GOOD.lerp(Style.DANGER, v))
		Style.label(ci, Vector2(x + 310, yy + 15), "%d %%" % int(v * 100), 13, Style.PAPER, "black")
	var u: Dictionary = sim.state.fighters[1]
	var react_txt = ""
	if u.resist_t > 0 or absi(u.react) > 1500:
		react_txt = "IL RÉSISTE → emmène-le %s" % ("en arrière" if u.react < 0 else "en avant")
	elif u.follow_t > 0:
		react_txt = "IL SUIT → balaye son pied"
	if react_txt != "":
		Style.label(ci, Vector2(x + 30, y + 130), react_txt, 13, Style.GOLD, "black", HORIZONTAL_ALIGNMENT_LEFT, 360)
	# boutons
	var bx = x + 26
	for k in Readout.BUTTONS.size():
		var pr = Readout.predict(sim, 0, Readout.BUTTONS[k][1])
		var yy2 = y + 146 + k * 22
		Style.pad_button(ci, Vector2(bx + 10, yy2 + 8), Readout.BUTTONS[k][0], 10.0)
		Style.label(ci, Vector2(bx + 30, yy2 + 13), String(pr.name).to_upper(), 13, Style.PAPER, "black", HORIZONTAL_ALIGNMENT_LEFT, 160)
		var oc = Readout.outcome_label(pr.outcome)
		if pr.counter_risk and pr.outcome in ["stoppe", "expose"]:
			oc += " · CONTRE !"
		Style.label(ci, Vector2(x + 220, yy2 + 13), oc, 13, Readout.outcome_color(pr.outcome), "black", HORIZONTAL_ALIGNMENT_LEFT, 170)


## Affichage des entrées (bas gauche) : manette en direct + historique.
func _draw_inputs(ci: CanvasItem) -> void:
	var base = Vector2(28, 600)
	var inp = last_inp
	# sticks
	for k in 2:
		var c = base + Vector2(30 + k * 70, 0)
		ci.draw_circle(c, 24.0, Color(Style.INK, 0.85))
		ci.draw_arc(c, 24.0, 0, TAU, 24, Style.NIGHT_3, 2.0, true)
		var v = Vector2(inp[Sim.MX], 0) if k == 0 else Vector2(inp[Sim.PX], inp[Sim.PY])
		ci.draw_circle(c + v / 100.0 * 16.0, 8.0, Style.P1 if k == 0 else Style.P2)
		Style.label(ci, c + Vector2(-8, 40), "LS" if k == 0 else "RS", 11, Style.MUTED, "black")
	# gâchettes
	for k in 2:
		var gx = base.x + 150 + k * 26
		var val = float(inp[Sim.LT if k == 0 else Sim.RT]) / 100.0
		ci.draw_rect(Rect2(gx, base.y - 24, 16, 48), Color(Style.INK, 0.85))
		ci.draw_rect(Rect2(gx + 2, base.y + 22 - 44 * val, 12, 44 * val), Style.P1)
		Style.label(ci, Vector2(gx - 2, base.y + 40), "LT" if k == 0 else "RT", 11, Style.MUTED, "black")
	# boutons
	var pos = {"Y": Vector2(0, -16), "X": Vector2(-16, 0), "B": Vector2(16, 0), "A": Vector2(0, 16)}
	var idx = {"A": Sim.BA, "B": Sim.BB, "X": Sim.BX, "Y": Sim.BY}
	for b in pos:
		var c2: Vector2 = base + Vector2(244, 0) + pos[b]
		if inp[idx[b]] != 0:
			Style.pad_button(ci, c2, b, 8.0)
		else:
			ci.draw_circle(c2, 8.0, Color(Style.INK, 0.85))
			ci.draw_arc(c2, 8.0, 0, TAU, 16, Style.NIGHT_3, 1.5, true)
	# historique
	var hy = 560.0
	for k in mini(hist.size(), 9):
		var e: Dictionary = hist[k]
		var a = 1.0 - k * 0.08
		var yy = hy - k * 24.0
		if yy < 330:
			break
		Style.label(ci, Vector2(300, yy), "%2d" % e.n, 13, Color(Style.MUTED, a), "black")
		Style.label(ci, Vector2(330, yy), e.dir, 16, Color(Style.PAPER, a), "black")
		var bx = 356.0
		for b in e.btns:
			Style.label(ci, Vector2(bx, yy), b, 13, Color(Style.P1, a), "black")
			bx += Style.text_width(b, 13, "black") + 8


func _draw_recording(ci: CanvasItem) -> void:
	var r = Rect2(440, 150, 400, 60)
	Style.panel(ci, r, Style.DANGER if rec_state == "rec" else Style.NIGHT_2, Style.INK, 4.0, 6.0)
	var txt = "PRÊT… %d" % (3 - rec_t / 60) if rec_state == "wait" else "ENREGISTREMENT %d s" % (10 - rec_t / 60)
	Style.text(ci, Vector2(r.position.x, r.position.y + 42), txt, 30, Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if rec_state == "rec":
		Style.label(ci, Vector2(r.position.x, r.end.y + 22), "Tu contrôles le partenaire", 15, Style.PAPER, "black", HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_menu(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(0, 0, W, H), Color(0.04, 0.03, 0.1, 0.72))
	Style.text(ci, Vector2(0, 150), "DOJO", 80, Style.GOOD, "display", HORIZONTAL_ALIGNMENT_CENTER, W)
	var items = training_items() if mode == "training" else lesson_items()
	for k in items.size():
		var sel = k == menu_i
		var r = Rect2(380 - (10 if sel else 0), 180 + k * 58, 520 + (20 if sel else 0), 48)
		Style.panel(ci, r, Style.GOOD if sel else Style.NIGHT_2, Style.INK, 4.0, 5.0)
		Style.text(ci, Vector2(r.position.x + 30, r.position.y + 35), items[k][0], 26, Style.INK if sel else Style.PAPER, "display", HORIZONTAL_ALIGNMENT_LEFT, -1, 3, 0.0)
		if items[k][1] != "":
			Style.label(ci, Vector2(r.position.x, r.position.y + 32), "‹ %s ›" % items[k][1] if sel else String(items[k][1]), 18,
				Style.INK if sel else Style.MUTED, "black", HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 34)


