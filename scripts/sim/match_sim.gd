extends RefCounted
## Simulation d'un combat de judo, déterministe, en tick fixe (60 ticks/s).
##
## - Arithmétique entière uniquement, aucun aléatoire : mêmes entrées = même résultat.
## - Aucune dépendance au rendu : l'affichage lit `state`, il ne l'écrit jamais.
## - L'état complet tient dans un Dictionary copiable (get_state / set_state)
##   et vérifiable (checksum) : c'est la base du futur netcode rollback.
##
## Entrées par joueur et par tick : tableau de INPUT_SIZE entiers (états tenus,
## les fronts « appuyé » sont calculés ici à partir de l'entrée précédente).

const MX := 0   # stick gauche X : déplacement (-100..100)
const PX := 1   # stick droit X : kuzushi (-100..100)
const PY := 2   # stick droit Y : kuzushi latéral (-100..100)
const LT := 3   # gâchette gauche : main gauche (0..100)
const RT := 4   # gâchette droite : main droite (0..100)
const LB := 5   # changer la cible de la main gauche
const RB := 6   # changer la cible de la main droite
const BA := 7   # technique principale selon la direction du kuzushi
const BX := 8   # technique de jambe
const BY := 9   # tokui-waza
const BB := 10  # casser la prise / bloquer / contrer
const INPUT_SIZE := 11

const HAND_FREE := 0
const HAND_REACH := 1
const HAND_GRIP := 2

var cfg: Dictionary
var techs: Dictionary
var state: Dictionary
## Événements du dernier tick (pour l'affichage, pas dans l'état).
var events: Array = []


func _init(config: Dictionary, techniques: Dictionary, names: Array = ["Tori", "Uke"], tokui: Array = ["seoi_nage", "o_soto_gari"]) -> void:
	cfg = config
	techs = techniques
	state = {
		"tick": 0,
		"phase": "intro",
		"phase_t": 0,
		"clock": cfg.match_ticks,
		"golden": false,
		"winner": -1,
		"win_reason": "",
		"throw": {},
		"announce": "HAJIME",
		"announce_t": 90,
		"fighters": [_new_fighter(0, names[0], tokui[0]), _new_fighter(1, names[1], tokui[1])],
	}
	_reset_positions()


static func empty_input() -> Array:
	var a := []
	a.resize(INPUT_SIZE)
	a.fill(0)
	return a


func get_state() -> Dictionary:
	return state.duplicate(true)


func set_state(s: Dictionary) -> void:
	state = s.duplicate(true)


func checksum() -> int:
	return hash(var_to_str(state))


# ---------------------------------------------------------------------------
# Boucle principale
# ---------------------------------------------------------------------------

func step(inputs: Array) -> void:
	events.clear()
	var s := state
	s.tick += 1
	s.phase_t += 1
	if s.announce_t > 0:
		s.announce_t -= 1
	match s.phase:
		"intro":
			if s.phase_t >= cfg.intro_ticks:
				_set_phase("fight")
		"fight":
			_fight_tick(inputs)
		"throw":
			_throw_tick()
		"score":
			if s.phase_t >= cfg.score_pause_ticks:
				_matte()
		"matte":
			if s.phase_t >= cfg.matte_ticks:
				_reset_positions()
				_set_phase("fight")
				_announce("HAJIME")
		"ended":
			pass
	for i in 2:
		s.fighters[i].prev = (inputs[i] as Array).duplicate()


func _fight_tick(inputs: Array) -> void:
	var s := state
	if s.golden:
		s.clock += 1
	else:
		s.clock -= 1
		if s.clock <= 0:
			_time_up()
			return
	var fs: Array = s.fighters
	for i in 2:
		fs[i].facing = 1 if fs[1 - i].x > fs[i].x else -1
	for i in 2:
		_update_grips(i, inputs[i])
	for i in 2:
		_update_movement(i, inputs[i])
	for i in 2:
		_apply_pull(i, inputs[i])
	for i in 2:
		_recover(i)
	for i in 2:
		_update_defense(i, inputs[i])
	for i in 2:
		_update_attack(i, inputs[i])
		if s.phase != "fight":
			return
	for i in 2:
		_update_rules(i)
		if s.phase != "fight":
			return


# ---------------------------------------------------------------------------
# Kumikata
# ---------------------------------------------------------------------------

func _update_grips(i: int, inp: Array) -> void:
	var f: Dictionary = state.fighters[i]
	var o: Dictionary = state.fighters[1 - i]
	var in_range: bool = absi(o.x - f.x) <= cfg.grip_range
	# Poigne plafonnée par l'endurance : à bout de souffle, la main lâche.
	var trig_cap: int = 40 + 60 * f.stamina / cfg.stamina_max
	for h in 2:
		var hand: Dictionary = f.hands[h]
		var cyc := LB if h == 0 else RB
		if _pressed(f, inp, cyc):
			hand.target = (hand.target + 1) % cfg.grip_targets.size()
			if hand.state != HAND_FREE:
				hand.state = HAND_REACH
				hand.t = 0
		var trig: int = mini(inp[LT] if h == 0 else inp[RT], trig_cap)
		hand.trig = trig
		if hand.lock > 0:
			hand.lock -= 1
			hand.state = HAND_FREE
			hand.t = 0
			continue
		if trig < cfg.grip_min_trigger or not in_range:
			hand.state = HAND_FREE
			hand.t = 0
			continue
		if hand.state == HAND_FREE:
			hand.state = HAND_REACH
			hand.t = 0
		if hand.state == HAND_REACH:
			hand.t += 1
			if hand.t >= cfg.grip_reach_ticks:
				hand.state = HAND_GRIP
				hand.t = 0
				events.append({"type": "grip", "who": i, "hand": h})
		if hand.state == HAND_GRIP:
			if hand.t < cfg.grip_settle_ticks:
				hand.t += 1  # installation de la garde
			var tname: String = cfg.grip_targets[hand.target]
			var cost: int = trig * cfg.stamina_grip_cost * cfg.grip_cost_mult[tname] / 10000
			f.stamina = maxi(0, f.stamina - cost)


# ---------------------------------------------------------------------------
# Déplacements
# ---------------------------------------------------------------------------

func _update_movement(i: int, inp: Array) -> void:
	var f: Dictionary = state.fighters[i]
	var o: Dictionary = state.fighters[1 - i]
	var speed: int = cfg.move_speed
	if has_grip(o):
		speed = speed * cfg.move_slow_when_gripped / 100
	if not f.attack.is_empty():
		speed = 0
	var dx: int = clampi(inp[MX], -100, 100) * speed / 100
	f.last_move = dx
	var nx: int = f.x + dx
	var gap: int = cfg.min_gap
	if f.facing == 1 and nx > o.x - gap:
		if has_grip(f) and dx > 0:
			o.x += mini(dx, cfg.push_speed)
		nx = o.x - gap
	elif f.facing == -1 and nx < o.x + gap:
		if has_grip(f) and dx < 0:
			o.x -= mini(-dx, cfg.push_speed)
		nx = o.x + gap
	f.x = nx


# ---------------------------------------------------------------------------
# Kuzushi : le stick droit déséquilibre l'adversaire
# ---------------------------------------------------------------------------

func _apply_pull(i: int, inp: Array) -> void:
	var f: Dictionary = state.fighters[i]
	var o: Dictionary = state.fighters[1 - i]
	var px: int = clampi(inp[PX], -100, 100)
	var py: int = clampi(inp[PY], -100, 100)
	if px == 0 and py == 0:
		return
	var force := 0
	for hand in f.hands:
		if hand.state == HAND_GRIP:
			var tname: String = cfg.grip_targets[hand.target]
			var settle: int = cfg.grip_settle_min + (100 - cfg.grip_settle_min) * mini(hand.t, cfg.grip_settle_ticks) / cfg.grip_settle_ticks
			force += cfg.pull_force_per_hand * hand.trig / 100 * cfg.grip_pull_mult[tname] / 100 * settle / 100
	if force == 0:
		return
	force = force * (5000 + f.stamina / 2) / 10000
	# Repère de l'adversaire : « avant » = vers l'attaquant.
	# Tirer le stick vers soi déséquilibre l'adversaire vers l'avant.
	var kx: int = -px * f.facing * force / 100
	var ky: int = py * force / 100
	# Tsukuri : reculer en tirant amplifie le déséquilibre avant,
	# avancer en poussant amplifie le déséquilibre arrière.
	if (kx > 0 and f.last_move * f.facing < 0) or (kx < 0 and f.last_move * f.facing > 0):
		kx = kx * cfg.tsukuri_bonus / 100
	# Suivre le mouvement (marcher dans le sens de la traction) l'atténue.
	var follow := 0
	if kx > 0 and o.last_move * o.facing > 0:
		follow = absi(o.last_move)
	elif kx < 0 and o.last_move * o.facing < 0:
		follow = absi(o.last_move)
	if follow > 0:
		var red: int = cfg.follow_reduction * mini(follow, cfg.move_speed) / cfg.move_speed
		kx = kx * (100 - red) / 100
	var bmax: int = cfg.balance_max
	o.bal_x = clampi(o.bal_x + kx, -bmax, bmax)
	o.bal_y = clampi(o.bal_y + ky, -bmax, bmax)
	f.stamina = maxi(0, f.stamina - cfg.stamina_pull_cost * (absi(px) + absi(py)) / 200)


func _recover(i: int) -> void:
	var f: Dictionary = state.fighters[i]
	f.bal_x -= f.bal_x * cfg.balance_recover_permille / 1000
	f.bal_y -= f.bal_y * cfg.balance_recover_permille / 1000
	if f.attack.is_empty():
		var rec: int = cfg.stamina_recover_gripping if has_grip(f) else cfg.stamina_recover
		f.stamina = mini(cfg.stamina_max, f.stamina + rec)
	if f.break_cd > 0:
		f.break_cd -= 1
	if f.defend_t > 0:
		f.defend_t -= 1


# ---------------------------------------------------------------------------
# Bouton B : casser la prise, ou bloquer / contrer si l'adversaire attaque
# ---------------------------------------------------------------------------

func _update_defense(i: int, inp: Array) -> void:
	var f: Dictionary = state.fighters[i]
	var o: Dictionary = state.fighters[1 - i]
	if not _pressed(f, inp, BB):
		return
	if not o.attack.is_empty() or o.exposed_t > 0:
		f.defend_t = 8
		return
	if f.break_cd > 0 or f.stamina < cfg.break_cost:
		return
	var best := -1
	var best_trig := -1
	for h in 2:
		if o.hands[h].state == HAND_GRIP and o.hands[h].trig > best_trig:
			best = h
			best_trig = o.hands[h].trig
	if best < 0:
		return
	f.stamina -= cfg.break_cost
	f.break_cd = cfg.break_cooldown
	if best_trig < cfg.break_threshold:
		o.hands[best].state = HAND_FREE
		o.hands[best].t = 0
		o.hands[best].lock = 30
		events.append({"type": "break", "who": i})
	else:
		o.stamina = maxi(0, o.stamina - cfg.break_fail_drain)
		events.append({"type": "break_fail", "who": i})


# ---------------------------------------------------------------------------
# Techniques : entrée, feinte, résolution
# ---------------------------------------------------------------------------

func _update_attack(i: int, inp: Array) -> void:
	var f: Dictionary = state.fighters[i]
	var o: Dictionary = state.fighters[1 - i]
	if f.exposed_t > 0:
		f.exposed_t -= 1
		if o.defend_t > 0 and f.exposed_counter != "":
			f.exposed_t = 0
			_counter(1 - i, f.exposed_counter, f.exposed_depth)
		return
	if f.attack.is_empty():
		var btn := -1
		for b in [BA, BX, BY]:
			if _pressed(f, inp, b):
				btn = b
				break
		if btn < 0:
			return
		var tech_id := choose_tech(i, btn)
		var tech: Dictionary = techs[tech_id]
		f.attack = {"tech": tech_id, "btn": btn, "t": 0, "committed": false,
			"entry": 30 - 4 * tech.speed, "blocked": false}
		return
	var atk: Dictionary = f.attack
	var tech: Dictionary = techs[atk.tech]
	atk.t += 1
	if not atk.committed:
		if inp[atk.btn] == 0 and atk.t <= cfg.feint_max_ticks:
			f.attack = {}
			_feint(i, tech)
			return
		if atk.t > cfg.feint_max_ticks:
			atk.committed = true
			f.passive_t = 0
			f.stamina = maxi(0, f.stamina - tech.stamina)
			events.append({"type": "attack", "who": i, "tech": atk.tech})
	elif o.defend_t > 0 and not atk.blocked:
		var dv := dir_value(1 - i, tech.dir)
		if tech.counter != "" and dv < cfg.counter_threshold:
			f.attack = {}
			_counter(1 - i, tech.counter, dv)
			return
		atk.blocked = true
		o.stamina = maxi(0, o.stamina - cfg.block_cost)
		events.append({"type": "block", "who": 1 - i})
	if atk.t >= atk.entry:
		_resolve(i)


## Choisit la technique d'un bouton : Y = tokui-waza, A et X = la technique
## du groupe qui correspond le mieux au déséquilibre actuel de l'adversaire.
func choose_tech(i: int, btn: int) -> String:
	var f: Dictionary = state.fighters[i]
	if btn == BY:
		return f.tokui
	var group: Array = techs._buttons["a" if btn == BA else "x"]
	var best: String = group[0]
	var best_v := -1
	for id in group:
		var v := dir_value(1 - i, techs[id].dir)
		if v > best_v:
			best_v = v
			best = id
	return best


## Valeur du déséquilibre du combattant `i` dans une direction (0..10000).
func dir_value(i: int, dir: String) -> int:
	var f: Dictionary = state.fighters[i]
	match dir:
		"avant":
			return maxi(0, f.bal_x)
		"arriere":
			return maxi(0, -f.bal_x)
		"cote":
			return absi(f.bal_y)
		"arriere_cote":
			return (maxi(0, -f.bal_x) + absi(f.bal_y)) * 7 / 10
	return 0


func grip_mult(i: int, tech: Dictionary) -> int:
	var f: Dictionary = state.fighters[i]
	var held := []
	for hand in f.hands:
		if hand.state == HAND_GRIP:
			held.append(cfg.grip_targets[hand.target])
	if held.is_empty():
		return 0
	var partial := false
	for combo in tech.grips:
		var pool := held.duplicate()
		var ok := true
		for g in combo:
			var k := pool.find(g)
			if k < 0:
				ok = false
			else:
				pool.remove_at(k)
				partial = true
		if ok:
			return 100
	return cfg.partial_grip_mult if partial else 0


func _resolve(i: int) -> void:
	var f: Dictionary = state.fighters[i]
	var o: Dictionary = state.fighters[1 - i]
	var atk: Dictionary = f.attack
	var tech: Dictionary = techs[atk.tech]
	var dv := dir_value(1 - i, tech.dir)
	var gm := grip_mult(i, tech)
	var score: int = dv * gm / 100 + (tech.power - 3) * cfg.power_bonus
	score -= cfg.low_stamina_malus * (cfg.stamina_max - f.stamina) / cfg.stamina_max
	if atk.blocked:
		score -= cfg.block_malus
	if gm == 0:
		score = mini(score, 0)
	f.attack = {}
	f.last_score = score
	if score >= cfg.score_ippon:
		_start_throw(i, atk.tech, "ippon")
	elif score >= cfg.score_waza:
		_start_throw(i, atk.tech, "waza")
	elif score >= cfg.score_stuffed:
		f.stamina = maxi(0, f.stamina - cfg.stuffed_cost)
		o.bal_x /= 2
		o.bal_y /= 2
		events.append({"type": "stuffed", "who": i, "tech": atk.tech})
	else:
		# Attaque ratée : tori est exposé, emporté par son propre élan.
		f.exposed_t = cfg.exposed_ticks
		f.exposed_counter = tech.counter
		f.exposed_depth = score
		f.bal_x = mini(cfg.balance_max, f.bal_x + 4000)
		o.bal_x /= 2
		o.bal_y /= 2
		events.append({"type": "exposed", "who": i, "tech": atk.tech})


func _feint(i: int, tech: Dictionary) -> void:
	var f: Dictionary = state.fighters[i]
	var o: Dictionary = state.fighters[1 - i]
	# L'adversaire se raidit à l'opposé de la feinte : ça prépare la vraie attaque.
	var push: int = cfg.feint_push
	if tech.dir == "avant":
		o.bal_x = clampi(o.bal_x - push, -cfg.balance_max, cfg.balance_max)
	else:
		o.bal_x = clampi(o.bal_x + push, -cfg.balance_max, cfg.balance_max)
	var recent := []
	for t in f.feints:
		if state.tick - t < cfg.feint_window:
			recent.append(t)
	recent.append(state.tick)
	f.feints = recent
	events.append({"type": "feint", "who": i})
	if recent.size() >= cfg.feint_limit:
		f.feints = []
		_shido(i, "Fausse attaque")


func _counter(defender: int, counter_id: String, depth: int) -> void:
	var result := "ippon" if depth < cfg.counter_ippon_below else "waza"
	events.append({"type": "counter", "who": defender, "tech": counter_id})
	_start_throw(defender, counter_id, result)


func tech_name(id: String) -> String:
	if techs.has(id):
		return techs[id].name
	if techs._counters.has(id):
		return techs._counters[id].name
	return id


func tech_dir(id: String) -> String:
	if techs.has(id):
		return techs[id].dir
	return "contre"


# ---------------------------------------------------------------------------
# Projection, score, règles
# ---------------------------------------------------------------------------

func _start_throw(tori: int, tech_id: String, result: String) -> void:
	var fs: Array = state.fighters
	state.throw = {"tori": tori, "uke": 1 - tori, "tech": tech_id, "result": result,
		"t": 0, "dir": tech_dir(tech_id),
		"tori_x": fs[tori].x, "uke_x": fs[1 - tori].x, "facing": fs[tori].facing}
	for f in fs:
		f.attack = {}
		f.exposed_t = 0
	events.append({"type": "throw", "who": tori, "tech": tech_id, "result": result})
	_set_phase("throw")


func _throw_tick() -> void:
	var th: Dictionary = state.throw
	th.t += 1
	if th.t < cfg.throw_ticks:
		return
	var f: Dictionary = state.fighters[th.tori]
	var label := tech_name(th.tech)
	if th.result == "ippon":
		f.ippon = 1
		_end(th.tori, "Ippon — " + label)
		_announce("IPPON !")
		return
	f.waza += 1
	if f.waza >= 2:
		_end(th.tori, "Waza-ari awasete ippon — " + label)
		_announce("IPPON !")
		return
	if state.golden:
		_end(th.tori, "Golden score — " + label)
		_announce("WAZA-ARI")
		return
	_announce("WAZA-ARI")
	_set_phase("score")


func _update_rules(i: int) -> void:
	var f: Dictionary = state.fighters[i]
	f.passive_t += 1
	if f.passive_t >= cfg.passivity_ticks:
		f.passive_t = 0
		_shido(i, "Passivité")
		if state.phase != "fight":
			return
	if f.x < cfg.mat_left or f.x > cfg.mat_right:
		_shido(i, "Sortie de tapis")
		if state.phase == "fight":
			_matte()


func _shido(i: int, reason: String) -> void:
	var f: Dictionary = state.fighters[i]
	f.shidos += 1
	events.append({"type": "shido", "who": i, "reason": reason})
	_announce("SHIDO")
	if f.shidos >= cfg.shido_limit:
		_end(1 - i, "Hansoku-make (3 shidos)")
		_announce("HANSOKU-MAKE")


func _time_up() -> void:
	var fs: Array = state.fighters
	if fs[0].waza != fs[1].waza:
		var w := 0 if fs[0].waza > fs[1].waza else 1
		_end(w, "Waza-ari à la fin du temps")
		_announce("SORE-MADE")
		return
	state.golden = true
	state.clock = 0
	events.append({"type": "golden"})
	_announce("GOLDEN SCORE")
	_set_phase("matte")


func _end(winner: int, reason: String) -> void:
	state.winner = winner
	state.win_reason = reason
	events.append({"type": "end", "who": winner, "reason": reason})
	_set_phase("ended")


func _matte() -> void:
	_set_phase("matte")
	_announce("MATTE")


func _announce(text: String) -> void:
	state.announce = text
	state.announce_t = 90


func _set_phase(p: String) -> void:
	state.phase = p
	state.phase_t = 0


func _reset_positions() -> void:
	var fs: Array = state.fighters
	var center: int = (cfg.mat_left + cfg.mat_right) / 2
	fs[0].x = center - cfg.start_gap / 2
	fs[1].x = center + cfg.start_gap / 2
	fs[0].facing = 1
	fs[1].facing = -1
	for f in fs:
		f.bal_x = 0
		f.bal_y = 0
		f.attack = {}
		f.exposed_t = 0
		f.defend_t = 0
		for hand in f.hands:
			hand.state = HAND_FREE
			hand.t = 0
			hand.lock = 0
	state.throw = {}


func _new_fighter(id: int, fname: String, tokui: String) -> Dictionary:
	return {
		"id": id, "name": fname, "tokui": tokui,
		"x": 0, "facing": 1, "stamina": cfg.stamina_max,
		"bal_x": 0, "bal_y": 0,
		"hands": [_new_hand(0), _new_hand(1)],
		"prev": empty_input(),
		"attack": {}, "exposed_t": 0, "exposed_counter": "", "exposed_depth": 0,
		"defend_t": 0, "break_cd": 0,
		"waza": 0, "ippon": 0, "shidos": 0, "passive_t": 0, "feints": [],
		"last_move": 0, "last_score": 0,
	}


func _new_hand(target: int) -> Dictionary:
	return {"target": target, "state": HAND_FREE, "t": 0, "trig": 0, "lock": 0}


func _pressed(f: Dictionary, inp: Array, idx: int) -> bool:
	return inp[idx] != 0 and f.prev[idx] == 0


func has_grip(f: Dictionary) -> bool:
	for hand in f.hands:
		if hand.state == HAND_GRIP:
			return true
	return false
