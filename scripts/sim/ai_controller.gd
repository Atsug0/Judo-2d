extends RefCounted
## IA d'entraînement : produit des entrées manette à partir de l'état du combat.
## Déterministe (générateur pseudo-aléatoire à graine) pour que les simulations
## IA contre IA soient reproductibles (tests, équilibrage).
## Elle exploite le build du combattant : techniques équipées, enchaînements,
## contres équipés, ne-waza.

const Sim := preload("res://scripts/sim/match_sim.gd")

var me: int
var level: int  # 1 = débutant, 2 = moyen, 3 = fort
var rng_state: int
var plan_dir := "avant"
var plan_t := 0
var plan_side := 100
var hold_btn := -1
var hold_t := 0
var b_cooldown := 0
var threshold := 6600
var btn_urgent := false
var last_opportunity := ""
var react_at := 0
var react_roll := 0
var react_mode := ""     # réaction au kuzushi adverse : "suit", "resiste", "subit"
var react_left := 0
var react_cd := 0
var dash_step := 0
var dash_dir_ai := 0
var grip_delay := 10
var parry_cd := 0
var move_intent := 0
var move_left := 0


func _init(index: int, seed_value: int, lvl: int = 2) -> void:
	me = index
	level = lvl
	rng_state = (seed_value * 2654435761 + index * 97) & 0x7fffffff
	if rng_state == 0:
		rng_state = 1


func _rand(n: int) -> int:
	rng_state = (rng_state * 1103515245 + 12345) & 0x7fffffff
	return (rng_state >> 8) % n


func think(sim) -> Array:
	var inp := Sim.empty_input()
	var s: Dictionary = sim.state
	if s.phase == "newaza":
		return _think_newaza(sim, inp)
	if s.phase != "fight":
		hold_btn = -1
		return inp
	var cfg: Dictionary = sim.cfg
	var f: Dictionary = s.fighters[me]
	var o: Dictionary = s.fighters[1 - me]
	var facing: int = f.facing
	var dist: int = absi(o.x - f.x)

	var me_dom: int = sim.dom_of(me)
	var gripped: bool = sim.has_grip(f)
	var linked: bool = gripped or sim.has_grip(o)

	# --- Déplacement : venir à portée de mains, ne pas sortir du tapis.
	# (jamais plus de 80 hors dash : une pichenette à fond depuis le neutre = dash)
	# Intention de déplacement tenue quelques dixièmes de seconde (pas de tremblement).
	var back_room: int = (f.x - cfg.mat_left) if facing == 1 else (cfg.mat_right - f.x)
	move_left -= 1
	if dist > cfg.free_gap + 400 and not linked:
		move_intent = 80  # venir à portée
		move_left = 0
	elif back_room < 6000:
		move_intent = 70
		move_left = 0
	elif move_left <= 0:
		var roll := _rand(100)
		if linked and plan_dir.begins_with("avant") and roll < 45 + 10 * level:
			move_intent = -60  # tsukuri : recule en tirant
		elif linked and plan_dir.begins_with("arriere") and roll < 40 + 10 * level:
			move_intent = 50  # tsukuri : avance en poussant
		elif not linked and roll < 50:
			move_intent = 45 if _rand(2) == 0 else -45  # jeu de jambes en bataille de mains
		else:
			move_intent = 0
		move_left = 18 + _rand(30)
	inp[Sim.MX] = move_intent * facing

	# --- Réaction au kuzushi adverse : suivre, résister, ou subir (un choix par épisode)
	var pulled: int = f.bal_x  # > 0 : tiré vers l'avant ; < 0 : poussé en arrière
	if absi(pulled) > 2200 and linked:
		if react_mode == "" and react_cd <= 0:
			var roll := _rand(100)
			if roll < 15 + 12 * level:
				react_mode = "resiste"
			elif roll < 30 + 20 * level:
				react_mode = "suit"
			else:
				react_mode = "subit"
			react_left = 25 + _rand(30)
	if react_mode != "":
		react_left -= 1
		var toward: int = facing if pulled > 0 else -facing  # sens de la traction
		if react_mode == "resiste":
			inp[Sim.MX] = -80 * toward
		elif react_mode == "suit":
			inp[Sim.MX] = 80 * toward
		if react_left <= 0:
			react_mode = ""
			react_cd = 40
	elif react_cd > 0:
		react_cd -= 1

	# --- Dash : entrée rapide pour saisir, sortie quand on se fait déborder
	if dash_step > 0:
		dash_step -= 1
		inp[Sim.MX] = 0 if dash_step == 1 else 100 * dash_dir_ai  # neutre, puis à fond
	elif f.dash_cd == 0 and f.stamina > 3000 and f.attack.is_empty():
		var o_reaching: bool = o.hands[0].state == Sim.HAND_REACH or o.hands[1].state == Sim.HAND_REACH
		if not linked and dist <= cfg.grip_range and _rand(1000) < 4 + 3 * level:
			_start_dash(facing)  # entrée rapide
		elif o_reaching and me_dom < -1500 and _rand(100) < 6 * level:
			_start_dash(-facing)  # sortie : la main adverse part dans le vide
		elif gripped and level >= 2 and _rand(1000) < 2 * level:
			# changement de rythme en saisie : coup sec dans le sens du plan
			_start_dash(-facing if plan_dir.begins_with("avant") else facing)

	# --- Kumikata : une main après l'autre ; la garde haute monte au col
	if dist <= cfg.grip_range + 600:
		var grip := 80 if f.stamina > f.stamina_max * 3 / 10 else 45
		if f.hands[0].state != Sim.HAND_FREE or grip_delay <= 0:
			inp[Sim.LT] = grip
		if f.hands[1].state != Sim.HAND_FREE or grip_delay <= -10 - _rand(12):
			inp[Sim.RT] = grip
		grip_delay -= 1
		if f.style == "haute" and f.hands[1].target == 1 and f.prev[Sim.RB] == 0 and _rand(100) < 10:
			inp[Sim.RB] = 1  # main droite : du revers au col
	else:
		grip_delay = 6 + _rand(20)

	# --- Bataille de mains : chasser la main qui arrive
	if parry_cd > 0:
		parry_cd -= 1
	for h in 2:
		if o.hands[h].state == Sim.HAND_REACH and o.hands[h].t == 5 + _rand(4) and parry_cd == 0:
			if _rand(100) < 12 + 13 * level:
				inp[Sim.BB] = 1
				parry_cd = 20

	# --- Plan de kuzushi : une direction utile pour les techniques équipées
	var attacking: bool = hold_btn >= 0 or not f.attack.is_empty()
	if not attacking:
		plan_t -= 1
	if plan_t <= 0:
		plan_dir = _pick_dir(sim, f)
		plan_t = 40 + _rand(80)
		plan_side = 100 if _rand(2) == 0 else -100
	# action-réaction : il résiste en s'appuyant d'un côté → on l'emmène de ce côté
	if absi(o.react) > 1800 and level >= 2 and not attacking:
		plan_dir = "arriere" if o.react < 0 else "avant"
		plan_t = maxi(plan_t, 20)
	_pull_toward(inp, plan_dir, facing)

	# --- Défense : contrer ou bloquer une attaque adverse (une décision par occasion)
	if b_cooldown > 0:
		b_cooldown -= 1
	var want_b := false
	var opportunity := ""
	if not o.attack.is_empty() and o.attack.committed:
		opportunity = "atk%d" % (s.tick - o.attack.t)
	elif o.exposed_t > 0:
		opportunity = "exp%d" % (s.tick - (cfg.exposed_ticks - o.exposed_t))
	if opportunity != "" and opportunity != last_opportunity:
		last_opportunity = opportunity
		react_at = s.tick + 9 - 2 * level + _rand(6)
		react_roll = _rand(100)
	if opportunity != "" and s.tick >= react_at and react_at > 0:
		react_at = 0
		if not o.attack.is_empty():
			var tech: Dictionary = sim.techs[o.attack.tech]
			var dv: int = sim.dir_value(me, tech.dir)
			var can_counter: bool = tech.counter != "" and f.set.counters.has(tech.counter)
			if can_counter and dv < cfg.counter_threshold and react_roll < 25 * level:
				want_b = true
			elif dv > 5000 and react_roll < 20 * level:
				want_b = true
		elif o.exposed_counter != "" and o.exposed_depth < 0 and f.set.counters.has(o.exposed_counter) and react_roll < 25 * level:
			want_b = true
	elif sim.has_grip(o) and f.stamina > 3500 and _rand(1000) < 6 * level:
		want_b = true  # casser la garde adverse
	if want_b and b_cooldown == 0:
		inp[Sim.BB] = 1
		b_cooldown = 10

	# --- Attaque en cours : maintenir le bouton
	if hold_btn >= 0:
		hold_t += 1
		if hold_t < 24:
			inp[hold_btn] = 1
		else:
			hold_btn = -1
		return inp
	if not f.attack.is_empty() or f.exposed_t > 0:
		return inp

	# --- Enchaînement : la fenêtre est ouverte, on enchaîne
	if f.combo_t > 0 and _rand(100) < 30 + 20 * level:
		for b in [Sim.BA, Sim.BX, Sim.BY]:
			if sim.button_candidates(me, b).has(f.combo_next):
				_press(inp, b)
				return inp

	# --- Choix d'attaque : le meilleur score prévisible parmi les trois boutons
	# (évalué une image sur trois : temps de réaction et coût de calcul)
	if (s.tick + me) % 3 != 0:
		return inp
	var best_btn := -1
	var best_score := -99999
	var best_dir := plan_dir
	for b in [Sim.BA, Sim.BX, Sim.BY]:
		var id: String = sim.choose_tech(me, b)
		var sc: int = sim.attack_score(me, id)
		if sc > best_score:
			best_score = sc
			best_btn = b
			best_dir = sim.techs[id].dir
	var thr := threshold - 700 + _rand(1400) + level * 250
	# Pression de la passivité : plus le shido approche, moins on est exigeant.
	var urgency: int = f.passive_t - (cfg.passivity_ticks - 900)
	if urgency > 0:
		thr -= urgency * 5
		if urgency > 600 and _rand(100) < 5:
			btn_urgent = true
	var btn := -1
	if best_score > thr:
		btn = best_btn
	elif btn_urgent:
		btn = _safe_button(sim, f, o)  # attaque de sécurité pour éviter le shido
		btn_urgent = false
	elif best_score > thr - 3000 and f.set.combos.size() > 0 and _rand(1000) < 8 + 4 * level:
		# ouvre avec le début d'un enchaînement équipé
		var first: String = f.set.combos[_rand(f.set.combos.size())][0]
		for b in [Sim.BA, Sim.BX, Sim.BY]:
			if sim.choose_tech(me, b) == first:
				btn = b
				best_dir = sim.techs[first].dir
	elif _rand(100000) < 12 * (4 - level):
		btn = Sim.BA  # attaque impatiente (risque d'être exposé)
	elif _rand(10000) < 2:
		inp[Sim.BX] = 1  # feinte : simple tap
		return inp
	if btn >= 0:
		if best_dir != plan_dir:
			# garder la traction dans la direction de la technique pendant l'entrée
			plan_dir = best_dir
			plan_side = 100 if o.bal_y >= 0 else -100
			plan_t = 30
		_press(inp, btn)
	return inp


## Bouton dont la technique ne peut pas être contrée par l'adversaire
## (il connaît les contres équipés en face), la moins risquée possible.
func _safe_button(sim, f: Dictionary, o: Dictionary) -> int:
	var best := Sim.BX
	var best_v := -99999
	for b in [Sim.BX, Sim.BA, Sim.BY]:
		var id: String = sim.choose_tech(me, b)
		var tech: Dictionary = sim.techs[id]
		var v: int = sim.attack_score(me, id) - int(tech.power) * 300
		if tech.counter != "" and o.set.counters.has(tech.counter):
			v -= 5000
		if tech.get("sutemi", false):
			v -= 3000
		if v > best_v:
			best_v = v
			best = b
	return best


func _start_dash(dir: int) -> void:
	dash_step = 2  # neutre, puis pichenette à fond
	dash_dir_ai = dir


func _press(inp: Array, btn: int) -> void:
	hold_btn = btn
	hold_t = 0
	inp[btn] = 1


## Direction de kuzushi utile : celle d'une technique équipée (la tokui plus souvent).
func _pick_dir(sim, f: Dictionary) -> String:
	if _rand(100) < 45:
		return sim.techs[f.tokui].dir
	var list: Array = f.set.main
	return sim.techs[list[_rand(list.size())]].dir


func _pull_toward(inp: Array, dir: String, facing: int) -> void:
	match dir:
		"avant":
			inp[Sim.PX] = -100 * facing
		"arriere":
			inp[Sim.PX] = 100 * facing
		"cote":
			inp[Sim.PY] = plan_side
			inp[Sim.PX] = 30 * facing
		"arriere_cote":
			inp[Sim.PX] = 75 * facing
			inp[Sim.PY] = plan_side * 3 / 4
		"avant_cote":
			inp[Sim.PX] = -75 * facing
			inp[Sim.PY] = plan_side * 3 / 4


## Au sol : le judoka du dessus contrôle (A) et tente clé ou étranglement,
## celui du dessous se dégage (B) et gigote (stick).
func _think_newaza(sim, inp: Array) -> Array:
	var nw: Dictionary = sim.state.newaza
	var f: Dictionary = sim.state.fighters[me]
	if nw.is_empty():
		return inp
	if nw.top == me:
		inp[Sim.BA] = 1
		if not nw.sub.is_empty():
			inp[Sim.BX if nw.sub.kind == "kansetsu" else Sim.BY] = 1
		elif nw.control >= sim.cfg.sub_control and _rand(100) < 3 * level and f.prev[Sim.BX] == 0 and f.prev[Sim.BY] == 0:
			for id in f.set.ground:
				var kind: String = sim.techs._newaza[id].kind
				if kind == "kansetsu":
					inp[Sim.BX] = 1
				elif kind == "shime":
					inp[Sim.BY] = 1
	else:
		var every: int = 14 - level * 3
		if f.prev[Sim.BB] == 0 and _rand(every) == 0:
			inp[Sim.BB] = 1
		inp[Sim.MX] = 100 if _rand(2) == 0 else -100
	return inp
