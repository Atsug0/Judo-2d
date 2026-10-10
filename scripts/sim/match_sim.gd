extends RefCounted
## Simulation d'un combat de judo, déterministe, en tick fixe (60 ticks/s).
##
## - Arithmétique entière uniquement, aucun aléatoire : mêmes entrées = même résultat.
## - Aucune dépendance au rendu : l'affichage lit `state`, il ne l'écrit jamais.
## - L'état complet tient dans un Dictionary copiable (get_state / set_state)
##   et vérifiable (checksum) : c'est la base du futur netcode rollback.
## - Chaque combattant a un « set » issu de son build (techniques, enchaînements,
##   contres, ne-waza) et des modificateurs (style de kumikata, garde, profil physique).
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
const BA := 7   # technique selon la direction du kuzushi / osaekomi au sol
const BX := 8   # technique de jambe / clé de bras au sol
const BY := 9   # tokui-waza / étranglement au sol
const BB := 10  # casser la prise, bloquer, contrer / se dégager au sol
const INPUT_SIZE := 11

const HAND_FREE := 0
const HAND_REACH := 1
const HAND_GRIP := 2

## Pierre-feuille-ciseaux des styles de kumikata : clé bat valeur.
const STYLE_BEATS := {"haute": "classique", "courte": "haute", "classique": "courte"}

var cfg: Dictionary
var techs: Dictionary
var state: Dictionary
## Événements du dernier tick (pour l'affichage, pas dans l'état).
var events: Array = []


## `loadouts` : pour chaque joueur, soit un build complet (Dictionary), soit
## simplement l'identifiant de sa tokui-waza (String, set par défaut).
func _init(config: Dictionary, techniques: Dictionary, names: Array = ["Tori", "Uke"], loadouts: Array = ["seoi_nage", "o_soto_gari"]) -> void:
	cfg = config
	techs = techniques
	var fs := []
	for i in 2:
		fs.append(_new_fighter(i, names[i], loadouts[i]))
	state = {
		"tick": 0,
		"phase": "intro",
		"phase_t": 0,
		"clock": cfg.match_ticks,
		"golden": false,
		"winner": -1,
		"win_reason": "",
		"throw": {},
		"newaza": {},
		"announce": "HAJIME",
		"announce_t": 90,
		"fighters": fs,
	}
	_apply_matchup()
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
# Construction des combattants
# ---------------------------------------------------------------------------

func _new_fighter(id: int, fname: String, loadout) -> Dictionary:
	var loadset := _make_set(loadout)
	var f := {
		"id": id, "name": fname, "tokui": loadset.tokui, "set": loadset,
		"style": "classique", "garde": "droitier",
		"physique": {"explosivite": 5, "endurance": 5, "poigne": 5, "sol": 5},
		"x": 0, "facing": 1, "stamina": 0, "stamina_max": cfg.stamina_max,
		"bal_x": 0, "bal_y": 0,
		"hands": [_new_hand(0), _new_hand(1)],
		"prev": empty_input(),
		"attack": {}, "exposed_t": 0, "exposed_counter": "", "exposed_depth": 0, "exposed_sutemi": false,
		"defend_t": 0, "break_cd": 0,
		"combo_t": 0, "combo_next": "",
		"waza": 0, "ippon": 0, "shidos": 0, "passive_t": 0, "feints": [],
		"last_move": 0, "last_score": 0,
		"mods": {},
	}
	if typeof(loadout) == TYPE_DICTIONARY:
		f.style = loadout.get("style", "classique")
		f.garde = loadout.get("garde", "droitier")
		var ph: Dictionary = loadout.get("physique", {})
		for k in f.physique:
			f.physique[k] = int(ph.get(k, 5))
	f.mods = _make_mods(f)
	f.stamina_max = cfg.stamina_max * f.mods.stamina_pct / 100
	f.stamina = f.stamina_max
	return f


## Set de techniques à partir d'un build (ou d'une simple tokui-waza).
func _make_set(loadout) -> Dictionary:
	var d: Dictionary = techs._default_set
	if typeof(loadout) == TYPE_STRING:
		var s1 := d.duplicate(true)
		s1.tokui = loadout
		if not s1.main.has(loadout):
			s1.main.append(loadout)
		return s1
	var slots: Dictionary = loadout.get("slots", {})
	var ls := {"tokui": "", "main": [], "combos": [], "counters": [], "ground": []}
	for id in slots.get("tokui", []):
		if techs.has(id):
			ls.tokui = id
	for id in slots.get("main", []):
		if techs.has(id) and not ls.main.has(id):
			ls.main.append(id)
	if ls.tokui != "" and not ls.main.has(ls.tokui):
		ls.main.append(ls.tokui)
	if ls.main.is_empty():
		ls.main = d.main.duplicate()
	if ls.tokui == "":
		ls.tokui = ls.main[0]
	for id in slots.get("combo", []):
		if techs._combos.has(id):
			ls.combos.append(techs._combos[id].duplicate())
	for id in slots.get("counter", []):
		if techs._counters.has(id):
			ls.counters.append(id)
	for id in slots.get("ground", []):
		if techs._newaza.has(id):
			ls.ground.append(id)
	# un enchaînement donne accès à ses deux techniques
	for c in ls.combos:
		for id in c:
			if not ls.main.has(id):
				ls.main.append(id)
	return ls


## Modificateurs issus du style, de la garde et du profil physique.
func _make_mods(f: Dictionary) -> Dictionary:
	var ph: Dictionary = f.physique
	var m := {
		"entry_delta": clampi(5 - int(ph.explosivite), -3, 3),
		"stamina_pct": 80 + 4 * int(ph.endurance),
		"recover_pct": 70 + 6 * int(ph.endurance),
		"pull_pct": 100 + (int(ph.poigne) - 5) * 4,
		"grip_resist": (int(ph.poigne) - 5) * 4,
		"sol": int(ph.sol),
		"settle_extra": 0, "grip_cost_pct": 100, "koshi_bonus": 0,
		"ippon_extra": 0, "window_extra": 0, "reach_extra": 0, "te_bonus": 0,
		"style_bonus": 0,
	}
	match f.style:
		"haute":
			m.settle_extra = cfg.haute_settle
			m.grip_cost_pct = cfg.haute_cost
			m.koshi_bonus = cfg.haute_koshi_bonus
		"courte":
			m.entry_delta -= cfg.courte_entry
			m.ippon_extra = cfg.courte_ippon_extra
			m.window_extra = cfg.courte_window
	return m


## Effets qui dépendent des deux combattants : kenka-yotsu, style contre style.
func _apply_matchup() -> void:
	var fs: Array = state.fighters
	var kenka: bool = fs[0].garde != fs[1].garde
	for i in 2:
		var f: Dictionary = fs[i]
		var o: Dictionary = fs[1 - i]
		if kenka:
			f.mods.reach_extra = cfg.kenka_reach
			f.mods.te_bonus = cfg.kenka_te_bonus
		if STYLE_BEATS.get(f.style, "") == o.style:
			f.mods.style_bonus = cfg.style_bonus


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
		"newaza":
			_newaza_tick(inputs)
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


## Fait avancer le chrono. Renvoie false si le temps réglementaire est écoulé.
func _tick_clock() -> bool:
	var s := state
	if s.golden:
		s.clock += 1
	else:
		s.clock -= 1
		if s.clock <= 0:
			s.clock = 0
			return false
	return true


func _fight_tick(inputs: Array) -> void:
	var s := state
	if not _tick_clock():
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
	var trig_cap: int = 40 + 60 * f.stamina / f.stamina_max
	var reach: int = cfg.grip_reach_ticks + f.mods.reach_extra
	var settle_max: int = cfg.grip_settle_ticks + f.mods.settle_extra
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
			if hand.t >= reach:
				hand.state = HAND_GRIP
				hand.t = 0
				events.append({"type": "grip", "who": i, "hand": h})
		if hand.state == HAND_GRIP:
			if hand.t < settle_max:
				hand.t += 1  # installation de la garde
			var tname: String = cfg.grip_targets[hand.target]
			var cost: int = trig * cfg.stamina_grip_cost * cfg.grip_cost_mult[tname] / 10000 * f.mods.grip_cost_pct / 100
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
	var settle_max: int = cfg.grip_settle_ticks + f.mods.settle_extra
	for hand in f.hands:
		if hand.state == HAND_GRIP:
			var tname: String = cfg.grip_targets[hand.target]
			var settle: int = cfg.grip_settle_min + (100 - cfg.grip_settle_min) * mini(hand.t, settle_max) / settle_max
			force += cfg.pull_force_per_hand * hand.trig / 100 * cfg.grip_pull_mult[tname] / 100 * settle / 100
	if force == 0:
		return
	force = force * (5000 + f.stamina * 5000 / f.stamina_max) / 10000
	force = force * f.mods.pull_pct / 100
	# Repère de l'adversaire : « avant » = vers l'attaquant.
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
		rec = rec * f.mods.recover_pct / 100
		f.stamina = mini(f.stamina_max, f.stamina + maxi(1, rec))
	if f.break_cd > 0:
		f.break_cd -= 1
	if f.defend_t > 0:
		f.defend_t -= 1
	if f.combo_t > 0:
		f.combo_t -= 1
		if f.combo_t == 0:
			f.combo_next = ""


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
	if best_trig + o.mods.grip_resist < cfg.break_threshold:
		o.hands[best].state = HAND_FREE
		o.hands[best].t = 0
		o.hands[best].lock = 30
		events.append({"type": "break", "who": i})
	else:
		o.stamina = maxi(0, o.stamina - cfg.break_fail_drain)
		events.append({"type": "break_fail", "who": i})


# ---------------------------------------------------------------------------
# Techniques : entrée, feinte, enchaînement, résolution
# ---------------------------------------------------------------------------

func _update_attack(i: int, inp: Array) -> void:
	var f: Dictionary = state.fighters[i]
	var o: Dictionary = state.fighters[1 - i]
	if f.exposed_t > 0:
		f.exposed_t -= 1
		if o.defend_t > 0 and f.exposed_counter != "" and f.exposed_depth < 0 and o.set.counters.has(f.exposed_counter):
			f.exposed_t = 0
			_counter(1 - i, f.exposed_counter, f.exposed_depth)
			return
		if f.exposed_t == 0 and f.exposed_sutemi:
			# sutemi raté : tori est resté au sol, l'adversaire passe au-dessus
			f.exposed_sutemi = false
			_start_newaza(1 - i)
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
		var entry: int = 30 - 4 * int(tech.speed) + f.mods.entry_delta
		var combo := false
		if f.combo_t > 0 and tech_id == f.combo_next:
			combo = true
			entry -= cfg.combo_entry_cut
		f.attack = {"tech": tech_id, "btn": btn, "t": 0, "committed": false,
			"entry": maxi(cfg.feint_max_ticks + 3, entry), "blocked": false, "combo": combo}
		f.combo_t = 0
		f.combo_next = ""
		return
	var atk: Dictionary = f.attack
	var tech: Dictionary = techs[atk.tech]
	atk.t += 1
	if not atk.committed:
		if inp[atk.btn] == 0 and atk.t <= cfg.feint_max_ticks and not atk.combo:
			f.attack = {}
			_feint(i, tech)
			return
		if atk.t > cfg.feint_max_ticks:
			atk.committed = true
			f.passive_t = 0
			f.stamina = maxi(0, f.stamina - tech.stamina)
			events.append({"type": "attack", "who": i, "tech": atk.tech, "combo": atk.combo})
	elif o.defend_t > 0 and not atk.blocked:
		var dv := dir_value(1 - i, tech.dir)
		if tech.counter != "" and o.set.counters.has(tech.counter) and dv < cfg.counter_threshold:
			f.attack = {}
			_counter(1 - i, tech.counter, dv)
			return
		atk.blocked = true
		o.stamina = maxi(0, o.stamina - cfg.block_cost)
		events.append({"type": "block", "who": 1 - i})
	if atk.t >= atk.entry:
		_resolve(i)


## Techniques que le bouton peut déclencher pour ce combattant.
func button_candidates(i: int, btn: int) -> Array:
	var f: Dictionary = state.fighters[i]
	if btn == BY:
		return [f.tokui]
	var res := []
	for id in f.set.main:
		var fam: String = techs[id].family
		if btn == BX and fam == "ashi":
			res.append(id)
		elif btn == BA and fam != "ashi":
			res.append(id)
	if res.is_empty():
		res = f.set.main.duplicate()
	return res


## Choisit la technique d'un bouton : Y = tokui-waza ; A et X = la technique
## équipée qui correspond le mieux au déséquilibre actuel de l'adversaire.
## Pendant une fenêtre d'enchaînement, la suite de l'enchaînement est prioritaire.
func choose_tech(i: int, btn: int) -> String:
	var f: Dictionary = state.fighters[i]
	var group := button_candidates(i, btn)
	if f.combo_t > 0 and group.has(f.combo_next):
		return f.combo_next
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
		"avant_cote":
			return (maxi(0, f.bal_x) + absi(f.bal_y)) * 7 / 10
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


## Score d'une technique si elle était résolue maintenant (utile à l'IA et au HUD).
func attack_score(i: int, tech_id: String, blocked: bool = false, combo: bool = false) -> int:
	var f: Dictionary = state.fighters[i]
	var tech: Dictionary = techs[tech_id]
	var dv := dir_value(1 - i, tech.dir)
	var gm := grip_mult(i, tech)
	var score: int = dv * gm / 100 + (int(tech.power) - 3) * cfg.power_bonus
	score -= cfg.low_stamina_malus * (f.stamina_max - f.stamina) / f.stamina_max
	if tech_id == f.tokui:
		score += cfg.power_bonus / 2  # tokui-waza : bonus de réussite
	if tech.family == "koshi":
		score += f.mods.koshi_bonus
	if tech.family == "te":
		score += f.mods.te_bonus
	score += f.mods.style_bonus
	if combo:
		score += cfg.combo_bonus
	if blocked:
		score -= cfg.block_malus
	if gm == 0:
		score = mini(score, 0)
	return score


func _resolve(i: int) -> void:
	var f: Dictionary = state.fighters[i]
	var o: Dictionary = state.fighters[1 - i]
	var atk: Dictionary = f.attack
	var tech: Dictionary = techs[atk.tech]
	var score := attack_score(i, atk.tech, atk.blocked, atk.combo)
	f.attack = {}
	f.last_score = score
	if score >= cfg.score_ippon + f.mods.ippon_extra:
		_start_throw(i, atk.tech, "ippon")
	elif score >= cfg.score_waza:
		_start_throw(i, atk.tech, "waza")
	elif score >= cfg.score_stuffed:
		f.stamina = maxi(0, f.stamina - cfg.stuffed_cost)
		o.bal_x /= 2
		o.bal_y /= 2
		events.append({"type": "stuffed", "who": i, "tech": atk.tech})
		_open_combo(i, atk.tech)
	else:
		# Attaque ratée : tori est exposé, emporté par son propre élan.
		f.exposed_t = cfg.exposed_ticks
		f.exposed_counter = tech.counter
		f.exposed_depth = score
		f.exposed_sutemi = tech.get("sutemi", false)
		f.bal_x = mini(cfg.balance_max, f.bal_x + 4000)
		o.bal_x /= 2
		o.bal_y /= 2
		events.append({"type": "exposed", "who": i, "tech": atk.tech})


## Si la technique est le début d'un enchaînement équipé, l'adversaire réagit
## (il résiste à l'opposé) et une fenêtre s'ouvre pour la suite.
func _open_combo(i: int, tech_id: String) -> void:
	var f: Dictionary = state.fighters[i]
	var o: Dictionary = state.fighters[1 - i]
	for c in f.set.combos:
		if c[0] == tech_id:
			var push: int = cfg.combo_push
			var dir: String = techs[c[0]].dir
			if dir.begins_with("arriere"):
				o.bal_x = clampi(o.bal_x + push, -cfg.balance_max, cfg.balance_max)
			elif dir.begins_with("avant"):
				o.bal_x = clampi(o.bal_x - push, -cfg.balance_max, cfg.balance_max)
			else:
				o.bal_x = clampi(o.bal_x + push * 2 / 3, -cfg.balance_max, cfg.balance_max)
			f.combo_t = cfg.combo_window + f.mods.window_extra
			f.combo_next = c[1]
			events.append({"type": "combo_open", "who": i, "tech": c[1]})
			return


func _feint(i: int, tech: Dictionary) -> void:
	var f: Dictionary = state.fighters[i]
	var o: Dictionary = state.fighters[1 - i]
	# L'adversaire se raidit à l'opposé de la feinte : ça prépare la vraie attaque.
	var push: int = cfg.feint_push
	if String(tech.dir).begins_with("avant"):
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
	if techs._newaza.has(id):
		return techs._newaza[id].name
	return id


func tech_dir(id: String) -> String:
	if techs.has(id):
		return techs[id].dir
	if techs._counters.has(id):
		return techs._counters[id].dir
	return "contre"


# ---------------------------------------------------------------------------
# Projection, score
# ---------------------------------------------------------------------------

func _start_throw(tori: int, tech_id: String, result: String) -> void:
	var fs: Array = state.fighters
	state.throw = {"tori": tori, "uke": 1 - tori, "tech": tech_id, "result": result,
		"t": 0, "dir": tech_dir(tech_id),
		"tori_x": fs[tori].x, "uke_x": fs[1 - tori].x, "facing": fs[tori].facing}
	for f in fs:
		f.attack = {}
		f.exposed_t = 0
		f.exposed_sutemi = false
		f.combo_t = 0
	events.append({"type": "throw", "who": tori, "tech": tech_id, "result": result})
	_set_phase("throw")


func _throw_tick() -> void:
	var th: Dictionary = state.throw
	th.t += 1
	if th.t < cfg.throw_ticks:
		return
	if _award(th.tori, th.result, tech_name(th.tech)):
		return
	# waza-ari : on enchaîne au sol, tori au-dessus
	_start_newaza(th.tori)


## Attribue un score. Renvoie true si le combat est terminé.
func _award(who: int, result: String, label: String) -> bool:
	var f: Dictionary = state.fighters[who]
	if result == "ippon":
		f.ippon = 1
		_end(who, "Ippon — " + label)
		_announce("IPPON !")
		return true
	f.waza += 1
	if f.waza >= 2:
		_end(who, "Waza-ari awasete ippon — " + label)
		_announce("IPPON !")
		return true
	if state.golden:
		_end(who, "Golden score — " + label)
		_announce("WAZA-ARI")
		return true
	_announce("WAZA-ARI")
	events.append({"type": "waza", "who": who})
	return false


# ---------------------------------------------------------------------------
# Ne-waza : jauge de contrôle, osaekomi, clés et étranglements
# ---------------------------------------------------------------------------

func _start_newaza(top: int) -> void:
	var fs: Array = state.fighters
	var base: int = cfg.newaza_start_control + (fs[top].mods.sol - fs[1 - top].mods.sol) * 250
	state.newaza = {"top": top, "bottom": 1 - top, "control": clampi(base, 3000, 9000), "osae": false,
		"osae_t": 0, "t": 0, "sub": {}, "hold": "", "x": (fs[0].x + fs[1].x) / 2, "facing": fs[top].facing}
	for f in fs:
		f.attack = {}
		for hand in f.hands:
			hand.state = HAND_FREE
	state.throw = {}
	events.append({"type": "newaza", "who": top})
	_set_phase("newaza")


func _newaza_tick(inputs: Array) -> void:
	var nw: Dictionary = state.newaza
	var top: int = nw.top
	var bot: int = nw.bottom
	var ft: Dictionary = state.fighters[top]
	var fb: Dictionary = state.fighters[bot]
	var it: Array = inputs[top]
	var ib: Array = inputs[bot]
	nw.t += 1
	if nw.osae:
		if not state.golden and state.clock > 0:
			state.clock -= 1  # un osaekomi en cours continue même après la fin du temps
	elif not _tick_clock():
		_time_up()
		return
	var sol_t: int = ft.mods.sol
	var sol_b: int = fb.mods.sol
	# --- clé de bras ou étranglement en cours : bras de fer d'entrées
	if not nw.sub.is_empty():
		var sub: Dictionary = nw.sub
		sub.t += 1
		var hold_btn: int = BX if sub.kind == "kansetsu" else BY
		if it[hold_btn] != 0:
			sub.tp += 6 + sol_t
		if _pressed(fb, ib, BB):
			sub.bp += 40 + sol_b * 6
		if ib[MX] != 0:
			sub.bp += 3
		if sub.t >= cfg.sub_ticks:
			if sub.tp > sub.bp:
				events.append({"type": "submission", "who": top, "tech": sub.tech})
				ft.ippon = 1
				_end(top, "Ippon (maitta) — " + tech_name(sub.tech))
				_announce("IPPON !")
				return
			nw.sub = {}
			nw.control -= cfg.newaza_escape
			events.append({"type": "sub_escape", "who": bot})
		_newaza_end_checks(nw)
		return
	# --- jauge de contrôle
	var c: int = nw.control
	if it[BA] != 0:
		c += cfg.newaza_hold_gain * (80 + sol_t * 4) / 100
		ft.stamina = maxi(0, ft.stamina - 3)
	if _pressed(fb, ib, BB) and fb.stamina > 60:
		c -= cfg.newaza_escape_burst * (80 + sol_b * 4) / 100 * (50 + fb.stamina * 50 / fb.stamina_max) / 100
		fb.stamina -= 60
	if ib[MX] != 0:
		c -= cfg.newaza_stick_escape
	c -= cfg.newaza_drift
	nw.control = clampi(c, 0, 10000)
	# tentative de clé / étranglement (si équipé)
	if nw.control >= cfg.sub_control:
		for pair in [[BX, "kansetsu"], [BY, "shime"]]:
			if _pressed(ft, it, pair[0]):
				for id in ft.set.ground:
					if techs._newaza[id].kind == pair[1]:
						nw.sub = {"kind": pair[1], "tech": id, "t": 0, "tp": 0, "bp": 0}
						nw.osae = false
						events.append({"type": "sub_start", "who": top, "tech": id})
						_announce(tech_name(id).to_upper())
						return
	# osaekomi
	if not nw.osae and nw.control >= cfg.osaekomi_on:
		nw.osae = true
		nw.osae_t = 0
		var hold := "kesa_gatame"
		for id in ft.set.ground:
			if techs._newaza[id].kind == "osaekomi":
				hold = id
				break
		nw.hold = hold
		events.append({"type": "osaekomi", "who": top, "tech": hold})
		_announce("OSAEKOMI")
	if nw.osae:
		nw.osae_t += 1
		if nw.osae_t == cfg.osaekomi_waza:
			if _award(top, "waza", tech_name(nw.hold)):
				return
		if nw.osae_t >= cfg.osaekomi_ippon:
			ft.ippon = 1
			_end(top, "Ippon — " + tech_name(nw.hold))
			_announce("IPPON !")
			return
		if nw.control < cfg.toketa_below:
			events.append({"type": "toketa", "who": bot})
			_announce("TOKETA")
			nw.osae = false
			_matte_after(40)
			return
	_newaza_end_checks(nw)


func _newaza_end_checks(nw: Dictionary) -> void:
	if state.phase != "newaza":
		return
	if nw.control < cfg.newaza_escape and nw.sub.is_empty():
		events.append({"type": "escape", "who": nw.bottom})
		_matte()
		return
	if not nw.osae and nw.sub.is_empty() and nw.t >= cfg.newaza_stall:
		_matte()
		return
	if not nw.osae and state.clock <= 0 and not state.golden:
		_time_up()


func _matte_after(ticks: int) -> void:
	_set_phase("score")
	state.phase_t = cfg.score_pause_ticks - ticks


# ---------------------------------------------------------------------------
# Règles
# ---------------------------------------------------------------------------

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
	state.newaza = {}
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
		f.exposed_sutemi = false
		f.defend_t = 0
		f.combo_t = 0
		f.combo_next = ""
		for hand in f.hands:
			hand.state = HAND_FREE
			hand.t = 0
			hand.lock = 0
	state.throw = {}
	state.newaza = {}


func _new_hand(target: int) -> Dictionary:
	return {"target": target, "state": HAND_FREE, "t": 0, "trig": 0, "lock": 0}


func _pressed(f: Dictionary, inp: Array, idx: int) -> bool:
	return inp[idx] != 0 and f.prev[idx] == 0


func has_grip(f: Dictionary) -> bool:
	for hand in f.hands:
		if hand.state == HAND_GRIP:
			return true
	return false
