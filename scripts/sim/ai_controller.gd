extends RefCounted
## IA d'entraînement : produit des entrées manette à partir de l'état du combat.
## Déterministe (générateur pseudo-aléatoire à graine) pour que les simulations
## IA contre IA soient reproductibles (tests, équilibrage).

const Sim := preload("res://scripts/sim/match_sim.gd")

var me: int
var level: int  # 1 = débutant, 2 = moyen, 3 = fort
var rng_state: int
var plan_dir := 0  # 0 avant, 1 arrière, 2 côté
var plan_t := 0
var plan_side := 100
var hold_btn := -1
var hold_t := 0
var b_cooldown := 0
var threshold := 7200
var btn_urgent := false
var last_opportunity := ""
var react_at := 0
var react_roll := 0


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
	var cfg: Dictionary = sim.cfg
	if s.phase != "fight":
		hold_btn = -1
		return inp
	var f: Dictionary = s.fighters[me]
	var o: Dictionary = s.fighters[1 - me]
	var facing: int = f.facing
	var dist: int = absi(o.x - f.x)

	# --- Déplacement : venir à distance de garde, ne pas sortir du tapis.
	var back_room: int = (f.x - cfg.mat_left) if facing == 1 else (cfg.mat_right - f.x)
	if dist > cfg.grip_range - 900:
		inp[Sim.MX] = 100 * facing
	elif back_room < 6000:
		inp[Sim.MX] = 70 * facing
	elif plan_dir == 0 and _rand(100) < 35:
		inp[Sim.MX] = -60 * facing  # tsukuri : recule en tirant
	# Suivre la traction adverse pour amortir le kuzushi (niveaux 2 et 3).
	if level >= 2 and dist <= cfg.grip_range and f.bal_x > 3500 and _rand(100) < 8 * level:
		inp[Sim.MX] = 80 * facing

	# --- Kumikata
	if dist <= cfg.grip_range + 600:
		var grip := 80 if f.stamina > 3000 else 45
		inp[Sim.LT] = grip
		inp[Sim.RT] = grip

	# --- Plan de kuzushi (figé pendant une attaque : on garde la traction)
	var attacking: bool = hold_btn >= 0 or not f.attack.is_empty()
	if not attacking:
		plan_t -= 1
	if plan_t <= 0:
		plan_dir = _rand(3)
		plan_t = 40 + _rand(80)
		plan_side = 100 if _rand(2) == 0 else -100
	match plan_dir:
		0:
			inp[Sim.PX] = -100 * facing
		1:
			inp[Sim.PX] = 100 * facing
		2:
			inp[Sim.PY] = plan_side
			inp[Sim.PX] = 30 * facing

	# --- Défense : contrer ou bloquer une attaque adverse.
	if b_cooldown > 0:
		b_cooldown -= 1
	# Une seule décision de réaction par attaque adverse (temps de réaction humain).
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
			if tech.counter != "" and dv < cfg.counter_threshold and react_roll < 25 * level:
				want_b = true
			elif dv > 5000 and react_roll < 20 * level:
				want_b = true
		elif o.exposed_counter != "" and react_roll < 25 * level:
			want_b = true
	elif sim.has_grip(o) and f.stamina > 3500 and _rand(1000) < 6 * level:
		want_b = true  # casser la garde adverse
	if want_b and b_cooldown == 0:
		inp[Sim.BB] = 1
		b_cooldown = 10

	# --- Attaque
	if hold_btn >= 0:
		hold_t += 1
		if hold_t < 24:
			inp[hold_btn] = 1
		else:
			hold_btn = -1
		return inp
	if not f.attack.is_empty() or f.exposed_t > 0:
		return inp
	var av: int = sim.dir_value(1 - me, "avant")
	var ar: int = sim.dir_value(1 - me, "arriere")
	var co: int = sim.dir_value(1 - me, "cote")
	var thr := threshold - 1000 + _rand(2000) + level * 300
	# Pression de la passivité : plus le shido approche, moins on est exigeant.
	var urgency: int = f.passive_t - (cfg.passivity_ticks - 900)
	if urgency > 0:
		thr -= urgency * 5
		if urgency > 600 and _rand(100) < 5:
			btn_urgent = true
	var btn := -1
	var dir := plan_dir
	if av > thr:
		btn = Sim.BY if f.tokui == "seoi_nage" else Sim.BA
		dir = 0
	elif ar > thr:
		btn = Sim.BA if _rand(2) == 0 else Sim.BX
		dir = 1
	elif co > thr:
		btn = Sim.BA
		dir = 2
	elif ar > thr - 2500 and _rand(1000) < 8:
		btn = Sim.BX  # petite technique pour ouvrir
		dir = 1
	if btn >= 0 and dir != plan_dir:
		# Garder la traction dans la direction de la technique pendant l'entrée.
		plan_dir = dir
		plan_side = 100 if o.bal_y >= 0 else -100
		plan_t = 30
	elif btn_urgent:
		btn = Sim.BX  # attaque de sécurité pour éviter le shido
		btn_urgent = false
	elif _rand(100000) < 12 * (4 - level):
		btn = Sim.BA  # attaque impatiente (risque d'être exposé)
	elif _rand(10000) < 2:
		inp[Sim.BX] = 1  # feinte : simple tap
		return inp
	if btn >= 0:
		hold_btn = btn
		hold_t = 0
		inp[btn] = 1
	return inp
