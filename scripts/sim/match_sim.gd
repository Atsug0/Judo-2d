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
		"dom": 0,  # domination au kumikata : > 0 pour le joueur 1, < 0 pour le joueur 2
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
		"last_move": 0, "last_score": 0, "nogrip_t": 0, "attacks_n": 0, "reaction_t": -9999,
		"react": 0, "resist_t": 0, "follow_t": 0,
		"stick_t": 0, "dash_t": 0, "dash_dir": 0, "dash_cd": 0, "fast_reach_t": 0,
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
		"entry_delta": clampi((5 - int(ph.explosivite)) * 2 / 3, -3, 3),
		"stamina_pct": 80 + 4 * int(ph.endurance),
		"recover_pct": 70 + 6 * int(ph.endurance),
		"pull_pct": 100 + (int(ph.poigne) - 5) * 4,
		"grip_resist": (int(ph.poigne) - 5) * 4,
		"sol": int(ph.sol),
		"settle_extra": 0, "grip_cost_pct": 100, "koshi_bonus": 0,
		"ippon_extra": 0, "window_extra": 0, "reach_extra": 0, "te_bonus": 0,
		"style_bonus": 0, "dom_pct": 100, "parry_pct": 100, "dash_cut": 0,
	}
	match f.style:
		"classique":
			m.dom_pct = cfg.classique_dom_pct  # maîtrise de la garde manche-revers
		"haute":
			m.settle_extra = cfg.haute_settle
			m.grip_cost_pct = cfg.haute_cost
			m.koshi_bonus = cfg.haute_koshi_bonus
		"courte":
			m.entry_delta -= cfg.courte_entry
			m.ippon_extra = cfg.courte_ippon_extra
			m.window_extra = cfg.courte_window
			m.parry_pct = cfg.courte_parry_pct  # vif à la bataille de mains
			m.dash_cut = cfg.courte_dash_cut
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
		if int(cfg.get("golden_limit_ticks", 0)) > 0 and s.clock >= int(cfg.golden_limit_ticks):
			_hantei()
			return false
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
	_update_dominance()
	_update_movement(inputs)
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
	if f.fast_reach_t > 0:
		reach -= cfg.fast_reach_cut
	# style haut : la prise met plus longtemps à s'installer
	var q_gain: int = cfg.grip_q_gain * cfg.grip_settle_ticks / (cfg.grip_settle_ticks + f.mods.settle_extra)
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
		if hand.state != HAND_GRIP:
			hand.fat = maxi(0, hand.fat - cfg.fat_recover)
		if hand.lock > 0:
			hand.lock -= 1
			hand.state = HAND_FREE
			hand.t = 0
			continue
		# une prise tenue résiste à un bras tendu ; une main qui cherche doit être à portée
		var reach_ok: bool = in_range if hand.state != HAND_GRIP else absi(o.x - f.x) <= cfg.grip_range + cfg.grip_hold_margin
		if trig < cfg.grip_min_trigger or not reach_ok:
			if hand.state == HAND_GRIP:
				events.append({"type": "release", "who": i, "hand": h})
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
				hand.q = cfg.grip_q_start
				events.append({"type": "grip", "who": i, "hand": h})
		if hand.state == HAND_GRIP:
			hand.t += 1
			# qualité : serrer fort l'approfondit (et chauffe l'avant-bras) ; tenir à moitié
			# garde une prise moyenne ; une main molle glisse mais se repose
			if trig >= cfg.grip_hard:
				hand.q = mini(10000, hand.q + q_gain * (trig - cfg.grip_hard + 10) / (110 - cfg.grip_hard))
				hand.fat = mini(10000, hand.fat + cfg.fat_gain * trig / 100)
			elif trig >= cfg.grip_soft:
				if hand.q > cfg.grip_soft_cap:
					hand.q = maxi(cfg.grip_soft_cap, hand.q - cfg.grip_q_slack)
				hand.fat = mini(10000, hand.fat + cfg.fat_gain * trig / 300)
			else:
				hand.q = maxi(500, hand.q - cfg.grip_q_slack)
				hand.fat = maxi(0, hand.fat - cfg.fat_rest)
			if hand.fat > cfg.fat_decay_from:
				hand.q = maxi(0, hand.q - cfg.fat_q_decay * (hand.fat - cfg.fat_decay_from) / (10000 - cfg.fat_decay_from))
			if hand.fat >= 10000 or hand.q <= 0:
				hand.state = HAND_FREE
				hand.t = 0
				hand.lock = cfg.fat_release_lock
				events.append({"type": "grip_tired", "who": i, "hand": h})
				continue
			var tname: String = cfg.grip_targets[hand.target]
			var cost: int = trig * cfg.stamina_grip_cost * cfg.grip_cost_mult[tname] / 10000 * f.mods.grip_cost_pct / 100
			f.stamina = maxi(0, f.stamina - cost)


## Qualité d'une prise de 0 à 100 (pour l'affichage et les calculs en pourcentage).
static func grip_pct(hand: Dictionary) -> int:
	return int(hand.q) / 100 if hand.state == HAND_GRIP else 0


# ---------------------------------------------------------------------------
# Déplacements
# ---------------------------------------------------------------------------

## Déplacements. Sans saisie : chacun marche librement, sans jamais entrer dans
## la distance de garde (free_gap). Dès qu'une saisie est prise : les deux judokas
## se déplacent ensemble, à longueur de bras (distance fixée par les saisies) ;
## avancer pousse le couple, reculer le tire, et l'autre peut suivre ou résister.
func _update_movement(inputs: Array) -> void:
	var fs: Array = state.fighters
	var dxs := [0, 0]
	for i in 2:
		var f: Dictionary = fs[i]
		var mx: int = clampi(inputs[i][MX], -100, 100)
		_check_dash(i, mx)
		var speed: int = cfg.move_speed
		if has_grip(fs[1 - i]) or has_grip(f):
			speed = speed * cfg.move_slow_when_gripped / 100
		if not f.attack.is_empty():
			speed = 0
		dxs[i] = mx * speed / 100
		if f.dash_t > 0:
			f.dash_t -= 1
			dxs[i] = f.dash_dir * cfg.dash_speed
		f.last_move = dxs[i]
	var linked: bool = has_grip(fs[0]) or has_grip(fs[1])
	if linked:
		# le couple se déplace d'un bloc ; quand les deux tirent en sens contraire,
		# celui qui domine le kumikata l'emporte (il emmène l'autre)
		# celui qui pousse ou tire le plus fort (pondéré par la domination) mène le couple ;
		# l'autre suit (le couple accélère) ou résiste (il ralentit, et s'appuie : action-réaction)
		var drv: int = 0
		var sc0: int = absi(dxs[0]) * (10000 + dom_of(0)) / 100
		var sc1: int = absi(dxs[1]) * (10000 + dom_of(1)) / 100
		if sc1 > sc0:
			drv = 1
		var lead: int = dxs[drv]
		var other: int = dxs[1 - drv]
		var pair: int = lead * cfg.pair_move_pct / 100
		if lead != 0 and other != 0:
			if (lead > 0) == (other > 0):
				pair = pair * (100 + cfg.pair_follow_pct) / 100
			else:
				pair = pair * (100 - cfg.pair_resist_pct) / 100
		fs[0].x += pair
		fs[1].x += pair
		# la distance respire : pousser au stick droit tend les bras, tirer rapproche
		var target: int = garde_distance()
		for i in 2:
			var px: int = clampi(int(inputs[i][PX]), -100, 100) * fs[i].facing
			if px > 0:
				target += px * cfg.arm_push_ext / 100
			else:
				target += px * cfg.arm_pull_close / 100
		target = maxi(cfg.min_gap + 600, target)
		var d: int = absi(fs[1].x - fs[0].x)
		var delta: int = clampi(target - d, -cfg.gap_relax, cfg.gap_relax)
		var sgn: int = 1 if fs[1].x >= fs[0].x else -1
		fs[0].x -= sgn * delta / 2
		fs[1].x += sgn * (delta - delta / 2)
		return
	for i in 2:
		var f: Dictionary = fs[i]
		var o: Dictionary = fs[1 - i]
		var nx: int = f.x + dxs[i]
		var gap: int = cfg.free_gap
		# on peut toujours reculer ; on n'avance pas plus près que la distance libre
		if f.facing == 1 and dxs[i] > 0:
			nx = mini(nx, maxi(f.x, o.x - gap))
		elif f.facing == -1 and dxs[i] < 0:
			nx = maxi(nx, mini(f.x, o.x + gap))
		f.x = nx


## Dash (pichenette franche du stick gauche depuis le neutre) : changement de rythme.
## En avant : entrée rapide, les mains saisissent plus vite. En arrière : on sort de
## portée et la main adverse qui arrivait part dans le vide. En saisie : coup sec
## qui tire (dash arrière) ou pousse (dash avant) l'adversaire.
func _check_dash(i: int, mx: int) -> void:
	var f: Dictionary = state.fighters[i]
	var o: Dictionary = state.fighters[1 - i]
	if absi(mx) < 25:
		f.stick_t = 0
		return
	f.stick_t += 1
	if absi(mx) < 85 or absi(int(f.prev[MX])) >= 85 or f.stick_t > cfg.dash_flick_ticks:
		return
	if f.dash_cd > 0 or not f.attack.is_empty() or f.exposed_t > 0 or f.stamina < cfg.dash_cost:
		return
	var dir: int = 1 if mx > 0 else -1
	f.dash_t = cfg.dash_ticks
	f.dash_dir = dir
	f.dash_cd = cfg.dash_cooldown - f.mods.dash_cut
	f.stamina -= cfg.dash_cost
	var forward: bool = dir == f.facing
	events.append({"type": "dash", "who": i, "dir": "in" if forward else "out"})
	if forward:
		f.fast_reach_t = cfg.fast_reach_ticks
	else:
		for h in 2:
			var oh: Dictionary = o.hands[h]
			if oh.state == HAND_REACH:
				oh.state = HAND_FREE
				oh.t = 0
				oh.lock = cfg.whiff_lock
				events.append({"type": "whiff", "who": i, "hand": h})
	# coup sec en saisie : proportionnel aux mains installées
	var held := 0
	for hand in f.hands:
		if hand.state == HAND_GRIP:
			held += 1
	if held > 0:
		var tug: int = cfg.dash_tug * held / 2 * (100 + dom_of(i) * cfg.dom_kuzushi_pct / 10000) / 100
		var kx: int = tug if not forward else -tug
		_kuzushi_on(i, kx, 0)


## Distance de garde : celle de la saisie la plus « proche » tenue par l'un ou l'autre.
func garde_distance() -> int:
	var best: int = cfg.grip_range
	for f in state.fighters:
		for hand in f.hands:
			if hand.state == HAND_GRIP:
				best = mini(best, int(cfg.garde_dist[cfg.grip_targets[hand.target]]))
	return best


## Domination au kumikata : chaque saisie installée fait pencher la jauge, selon
## sa valeur (col haut > ceinture > revers > manche) et la force de la main.
func _update_dominance() -> void:
	var fs: Array = state.fighters
	var r := [0, 0]
	for i in 2:
		var f: Dictionary = fs[i]
		for hand in f.hands:
			if hand.state == HAND_GRIP:
				var tname: String = cfg.grip_targets[hand.target]
				var settle: int = 40 + 60 * hand.q / 10000
				r[i] += int(cfg.dom_gain[tname]) * settle / 100 * (40 + hand.trig * 60 / 100) / 100
		r[i] = r[i] * f.mods.dom_pct / 100
	var d: int = state.dom
	d += (r[0] - r[1]) * cfg.dom_rate
	d -= d * cfg.dom_decay_permille / 1000
	state.dom = clampi(d, -10000, 10000)


## Domination vue du combattant i (-10000..10000, positif = il domine).
func dom_of(i: int) -> int:
	return state.dom if i == 0 else -state.dom


func _push_dom(i: int, amount: int) -> void:
	state.dom = clampi(state.dom + (amount if i == 0 else -amount), -10000, 10000)


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
			var settle: int = cfg.grip_settle_min + (100 - cfg.grip_settle_min) * hand.q / 10000
			force += cfg.pull_force_per_hand * hand.trig / 100 * cfg.grip_pull_mult[tname] / 100 * settle / 100
	if force == 0:
		return
	force = force * (cfg.pull_tired_pct * 100 + f.stamina * (100 - cfg.pull_tired_pct) * 100 / f.stamina_max) / 10000
	# cadre de l'adversaire : ses propres prises profondes le gardent solide sur ses appuis
	var frame := 0
	for oh in o.hands:
		if oh.state == HAND_GRIP:
			frame += cfg.frame_per_hand * oh.q / 10000
	force = force * (100 - frame) / 100
	force = force * f.mods.pull_pct / 100
	force = force * (100 + dom_of(i) * cfg.dom_kuzushi_pct / 10000) / 100
	# Repère de l'adversaire : « avant » = vers l'attaquant.
	var kx: int = -px * f.facing * force / 100
	var ky: int = py * force / 100
	# Tsukuri : reculer en tirant amplifie le déséquilibre avant,
	# avancer en poussant amplifie le déséquilibre arrière.
	if (kx > 0 and f.last_move * f.facing < 0) or (kx < 0 and f.last_move * f.facing > 0):
		kx = kx * cfg.tsukuri_bonus / 100
	_kuzushi_on(i, kx, ky)
	f.stamina = maxi(0, f.stamina - cfg.stamina_pull_cost * (absi(px) + absi(py)) / 200)


## Applique un déséquilibre (repère de l'adversaire : kx > 0 = vers l'attaquant i)
## en tenant compte de sa réaction :
## - il SUIT (marche dans le sens de la traction) : il amortit, mais il est en
##   mouvement, pieds légers → fenêtre pour les balayages ;
## - il RÉSISTE (marche en sens inverse) : il bloque, mais se met en appui dans
##   l'autre sens (react) → fenêtre pour une technique dans la direction opposée ;
## - il ne fait rien : il prend tout.
func _kuzushi_on(i: int, kx: int, ky: int) -> void:
	var o: Dictionary = state.fighters[1 - i]
	var om: int = o.last_move * o.facing  # > 0 : il avance vers i
	var resisting := false
	if kx != 0 and absi(o.react) > 1000 and (kx > 0) == (o.react > 0):
		# action-réaction : on l'emmène dans le sens où il s'appuyait déjà
		kx = kx * (100 + absi(o.react) * cfg.react_amp / 10000) / 100
		if o.resist_t > 0 and absi(o.react) >= 2000:
			events.append({"type": "reaction", "who": i})
			state.fighters[i].reaction_t = state.tick
			o.resist_t = 0
			o.react /= 2  # son appui est « consommé »
	elif kx > 0 and om > 0 or kx < 0 and om < 0:
		var red: int = cfg.follow_reduction * mini(absi(om), cfg.move_speed) / cfg.move_speed
		kx = kx * (100 - red) / 100
		if absi(om) * 2 >= cfg.move_speed:
			if o.follow_t == 0:
				events.append({"type": "follow", "who": 1 - i})
			o.follow_t = cfg.follow_window
	elif kx > 0 and om < 0 or kx < 0 and om > 0:
		resisting = true
		o.react = clampi(o.react - kx * cfg.resist_react / 100, -cfg.react_max, cfg.react_max)
		kx = kx * (100 - cfg.resist_reduction) / 100
		if o.resist_t == 0:
			events.append({"type": "resist", "who": 1 - i})
		o.resist_t = 12
	var bmax: int = cfg.balance_max
	# un déséquilibre se construit : vitesse plafonnée par tick (il faut tenir la traction)
	kx = clampi(kx, -cfg.bal_rate_max, cfg.bal_rate_max)
	ky = clampi(ky, -cfg.bal_rate_max, cfg.bal_rate_max)
	o.bal_x = clampi(o.bal_x + kx, -bmax, bmax)
	o.bal_y = clampi(o.bal_y + ky, -bmax, bmax)


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
	if f.dash_cd > 0:
		f.dash_cd -= 1
	if f.fast_reach_t > 0:
		f.fast_reach_t -= 1
	if f.follow_t > 0:
		f.follow_t -= 1
	if f.resist_t > 0:
		f.resist_t -= 1
	f.react -= f.react * cfg.react_decay_permille / 1000
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
	# bataille de mains : chasser une main qui arrive (prioritaire)
	for h in 2:
		var ph: Dictionary = o.hands[h]
		if ph.state == HAND_REACH and f.stamina >= cfg.parry_cost:
			ph.state = HAND_FREE
			ph.t = 0
			ph.lock = cfg.parry_lock
			f.stamina -= cfg.parry_cost
			_push_dom(i, cfg.dom_parry * f.mods.parry_pct / 100)
			events.append({"type": "parry", "who": i, "hand": h})
			return
	if f.break_cd > 0 or f.stamina < cfg.break_cost:
		return
	# arracher la prise adverse la plus profonde
	var best := -1
	var best_q := -1
	for h in 2:
		if o.hands[h].state == HAND_GRIP and o.hands[h].q > best_q:
			best = h
			best_q = o.hands[h].q
	if best < 0:
		return
	f.stamina -= cfg.break_cost
	f.break_cd = cfg.break_cooldown
	var oh: Dictionary = o.hands[best]
	var dmg: int = cfg.strip_base
	var how := "main"
	if clampi(inp[PX], -100, 100) * f.facing <= -60:
		dmg += cfg.strip_pull_bonus  # on arrache en tirant le bras vers soi
		how = "arrache"
	if not has_grip(f):
		dmg = dmg * cfg.strip_two_hands_pct / 100  # les deux mains sur sa prise
		how = "deux_mains"
	dmg = dmg * maxi(30, 100 - oh.trig * cfg.strip_hold_resist / 100 - o.mods.grip_resist) / 100
	if oh.q <= dmg:
		oh.state = HAND_FREE
		oh.t = 0
		oh.q = 0
		oh.lock = cfg.strip_lock
		_push_dom(i, cfg.dom_break)
		events.append({"type": "break", "who": i, "hand": best, "how": how})
		if not has_grip(o) and not has_grip(f):
			# plus aucun contact : chacun recule d'un pas, la bataille de mains repart
			var sgn: int = 1 if o.x > f.x else -1
			f.x -= sgn * cfg.strip_separation
			o.x += sgn * cfg.strip_separation
	else:
		oh.q -= dmg
		oh.fat = mini(10000, oh.fat + cfg.strip_fail_fatigue)
		o.stamina = maxi(0, o.stamina - cfg.break_fail_drain)
		events.append({"type": "break_fail", "who": i, "hand": best, "how": how})


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
			f.attacks_n += 1
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
## L'appui de résistance (react) compte comme un déséquilibre dans son sens.
func dir_value(i: int, dir: String) -> int:
	var f: Dictionary = state.fighters[i]
	var bx: int = clampi(f.bal_x + f.react, -cfg.balance_max, cfg.balance_max)
	match dir:
		"avant":
			return maxi(0, bx)
		"arriere":
			return maxi(0, -bx)
		"cote":
			return absi(f.bal_y)
		"arriere_cote":
			return (maxi(0, -bx) + absi(f.bal_y)) * 7 / 10
		"avant_cote":
			return (maxi(0, bx) + absi(f.bal_y)) * 7 / 10
	return 0


## Balayage : technique de pied latérale qui cueille un pied en mouvement.
func is_sweep(tech_id: String) -> bool:
	var t: Dictionary = techs[tech_id]
	return t.family == "ashi" and String(t.dir) in ["cote", "avant_cote", "arriere_cote"]


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
	score += dom_of(i) * cfg.dom_score / 10000
	var o: Dictionary = state.fighters[1 - i]
	if is_sweep(tech_id) and (o.follow_t > 0 or o.dash_t > 0 or absi(o.last_move) * 3 > cfg.move_speed):
		# sur le pas : d'autant plus efficace que son pied est en mouvement
		score += cfg.sweep_timing_bonus * mini(absi(o.last_move), cfg.move_speed) / cfg.move_speed
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
	# timing parfait : enchaînement, action-réaction, feinte récente ou balayage sur le pas.
	# Une technique bien préparée qui passe devient ippon bien plus facilement.
	var timing: bool = atk.combo or state.tick - int(f.reaction_t) <= cfg.timing_window \
		or (not f.feints.is_empty() and state.tick - int(f.feints[-1]) <= cfg.timing_window + 30) \
		or (is_sweep(atk.tech) and (o.follow_t > 0 or o.dash_t > 0))
	var ippon_at: int = cfg.score_ippon + f.mods.ippon_extra
	if timing and not atk.blocked:
		ippon_at = mini(ippon_at, cfg.score_waza + cfg.timing_ippon_margin + f.mods.ippon_extra / 2)
	if score >= ippon_at:
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
	if _award(th.tori, th.result, tech_name(th.tech), "throw", th.tech):
		return
	# waza-ari : on enchaîne au sol, tori au-dessus
	_start_newaza(th.tori)


## Attribue un score. Renvoie true si le combat est terminé.
func _award(who: int, result: String, label: String, src: String = "osae", tech: String = "") -> bool:
	var f: Dictionary = state.fighters[who]
	events.append({"type": "score", "who": who, "result": result, "src": src, "tech": tech, "golden": state.golden})
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
	nw.cur_t = int(nw.get("cur_t", 0)) + 1
	if nw.osae:
		if not state.golden and state.clock > 0:
			state.clock -= 1  # un osaekomi en cours continue même après la fin du temps
	elif not _tick_clock():
		_time_up()
		return
	var sol_t: int = ft.mods.sol
	var sol_b: int = fb.mods.sol
	# --- clé de bras ou étranglement en cours : curseurs des deux côtés
	# (dessus : X ou Y dans sa zone pour serrer ; dessous : B dans sa zone pour se dégager)
	if not nw.sub.is_empty():
		var sub: Dictionary = nw.sub
		sub.t += 1
		var hold_btn: int = BX if sub.kind == "kansetsu" else BY
		if not sub.get("cursor", false):
			sub.cursor = true
			_cursor_init(nw, ft, fb, cfg.sub_zone_top, cfg.sub_zone_bot)
		for role in ["top", "bot"]:
			var q := _cursor_press(nw, role, ft if role == "top" else fb, it if role == "top" else ib, hold_btn if role == "top" else BB)
			if q < 0:
				continue
			if q == 0:
				if role == "top":
					sub.tp = maxi(0, sub.tp - cfg.sub_miss)
				else:
					sub.bp = maxi(0, sub.bp - cfg.sub_miss)
				continue
			var gain: int = cfg.sub_perfect if q == 2 else cfg.sub_hit
			if role == "top":
				sub.tp = mini(100, sub.tp + gain + (sol_t - 5))
			else:
				sub.bp = mini(100, sub.bp + gain + cfg.sub_def_bonus + (sol_b - 5))
		if sub.tp >= 100:
			events.append({"type": "submission", "who": top, "tech": sub.tech})
			events.append({"type": "score", "who": top, "result": "ippon", "src": "sub", "tech": sub.tech, "golden": state.golden})
			ft.ippon = 1
			_end(top, "Ippon (maitta) — " + tech_name(sub.tech))
			_announce("IPPON !")
			return
		if sub.bp >= cfg.sub_escape_at or sub.t >= cfg.sub_cursor_ticks:
			nw.sub = {}
			nw.erase("ct")
			nw.erase("cb")
			nw.control -= cfg.newaza_escape
			events.append({"type": "sub_escape", "who": bot})
		_newaza_end_checks(nw)
		return
	# --- garde : celui du dessous, s'il a une clé ou un étranglement et que le contrôle
	# adverse est faible, retourne la situation et part directement sur la soumission
	if not nw.osae and nw.control <= cfg.guard_sub_control:
		for pair in [[BX, "kansetsu"], [BY, "shime"]]:
			if _pressed(fb, ib, pair[0]):
				for id in fb.set.ground:
					if techs._newaza[id].kind == pair[1]:
						nw.top = bot
						nw.bottom = top
						nw.facing = fb.facing
						nw.control = cfg.sub_control
						nw.sub = {"kind": pair[1], "tech": id, "t": 0, "tp": 0, "bp": 0, "guard": true}
						events.append({"type": "reversal", "who": bot})
						events.append({"type": "sub_start", "who": bot, "tech": id})
						_announce(tech_name(id).to_upper())
						return
	# --- immobilisation en cours : mini-jeu des curseurs (tenir / sortir)
	if nw.osae:
		if _osae_cursor_tick(nw, ft, fb, it, ib):
			return
	# --- jauge de contrôle (avant l'osaekomi : la lutte pour prendre le contrôle)
	var c: int = nw.control
	if nw.osae:
		c -= cfg.osae_drift
		nw.control = clampi(c, cfg.toketa_below, 10000)
	else:
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
						nw.erase("ct")
						nw.erase("cb")
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
		_osae_cursor_start(nw, ft, fb)
		events.append({"type": "osaekomi", "who": top, "tech": hold})
		_announce("OSAEKOMI")
	if nw.osae:
		nw.osae_t += 1
		if nw.osae_t == cfg.osaekomi_waza:
			if _award(top, "waza", tech_name(nw.hold), "osae", nw.hold):
				return
		if nw.osae_t >= cfg.osaekomi_ippon:
			events.append({"type": "score", "who": top, "result": "ippon", "src": "osae", "tech": nw.hold, "golden": state.golden})
			ft.ippon = 1
			_end(top, "Ippon — " + tech_name(nw.hold))
			_announce("IPPON !")
			return
		if nw.control < cfg.toketa_below and not nw.has("ct"):
			events.append({"type": "toketa", "who": bot})
			_announce("TOKETA")
			nw.osae = false
			_matte_after(40)
			return
	_newaza_end_checks(nw)


## Mini-jeu d'immobilisation : chaque joueur a une barre (0..10000), un curseur qui fait
## des allers-retours et une zone. Celui du dessus vise la sienne avec A pour maintenir,
## celui du dessous avec B pour sortir. Centre de zone = coup parfait. Rater bloque un instant.
func _osae_cursor_start(nw: Dictionary, ft: Dictionary, fb: Dictionary) -> void:
	nw.prog = 0
	_cursor_init(nw, ft, fb, cfg.osae_zone_top, cfg.osae_zone_bot)


## Barres des deux joueurs (immobilisation, clé, étranglement) : zones et curseurs.
func _cursor_init(nw: Dictionary, ft: Dictionary, fb: Dictionary, top_w: int, bot_w: int) -> void:
	nw.rng = (state.tick * 1103515245 + nw.control + 77) & 0x7fffffff
	var t0: int = int(nw.get("cur_t", 0))
	nw.ct = {"w": maxi(cfg.osae_zone_min, top_w + (ft.mods.sol - 5) * cfg.osae_zone_per_sol), "c": 5000, "lock": 0, "t0": t0}
	nw.cb = {"w": maxi(cfg.osae_zone_min, bot_w + (fb.mods.sol - 5) * cfg.osae_zone_per_sol), "c": 5000, "lock": 0, "t0": t0}
	_osae_move_zone(nw, nw.ct)
	_osae_move_zone(nw, nw.cb)


## Appui sur la barre d'un rôle : -1 = rien (pas d'appui ou bloqué), 0 = raté (bloqué),
## 1 = dans la zone, 2 = parfait. Déplace la zone touchée et rétrécit celle de l'adversaire.
func _cursor_press(nw: Dictionary, role: String, f: Dictionary, inp: Array, btn: int) -> int:
	var z: Dictionary = nw.ct if role == "top" else nw.cb
	var other: Dictionary = nw.cb if role == "top" else nw.ct
	var who: int = nw.top if role == "top" else nw.bottom
	if z.lock > 0:
		z.lock -= 1
		return -1
	if not _pressed(f, inp, btn):
		return -1
	var q := osae_quality(role)
	if q == 0:
		z.lock = cfg.osae_miss_lock
		events.append({"type": "osae_miss", "who": who, "role": role})
		return 0
	var mult: int = cfg.osae_perfect_mult if q == 2 else 1
	other.w = maxi(cfg.osae_zone_min, other.w - cfg.osae_zone_shrink * mult)
	_osae_move_zone(nw, z)
	f.stamina = maxi(0, f.stamina - (40 if role == "top" else 60))
	events.append({"type": "osae_hit", "who": who, "role": role, "perfect": q == 2})
	return q


## Temps écoulé sur la barre d'un rôle (ticks).
func cursor_time(z: Dictionary) -> int:
	return int(state.newaza.get("cur_t", 0)) - int(z.t0)


func _osae_rand(nw: Dictionary, n: int) -> int:
	nw.rng = (int(nw.rng) * 1103515245 + 12345) & 0x7fffffff
	return (int(nw.rng) >> 8) % n


func _osae_move_zone(nw: Dictionary, z: Dictionary) -> void:
	var half: int = z.w / 2 + 400
	z.c = half + _osae_rand(nw, maxi(1, 10000 - 2 * half))


## Période d'aller-retour du curseur (ticks) : celui du dessous accélère quand il fatigue.
func osae_period(role: String, f: Dictionary) -> int:
	if role == "top":
		return cfg.osae_period_top
	return cfg.osae_period_bot_tired + (cfg.osae_period_bot - cfg.osae_period_bot_tired) * f.stamina / f.stamina_max


## Position du curseur (0..10000) : onde triangle à partir du temps d'osaekomi.
func osae_cursor(role: String) -> int:
	var nw: Dictionary = state.newaza
	if nw.is_empty() or not nw.has("ct"):
		return 0
	var f: Dictionary = state.fighters[nw.top if role == "top" else nw.bottom]
	var z: Dictionary = nw.ct if role == "top" else nw.cb
	var per: int = osae_period(role, f)
	var u: int = (cursor_time(z) * 20000 / per) % 20000
	return u if u <= 10000 else 20000 - u


## 0 = raté, 1 = dans la zone, 2 = parfait (centre).
func osae_quality(role: String) -> int:
	var nw: Dictionary = state.newaza
	var z: Dictionary = nw.ct if role == "top" else nw.cb
	var d: int = absi(osae_cursor(role) - int(z.c))
	if d * 6 <= int(z.w):
		return 2
	if d * 2 <= int(z.w):
		return 1
	return 0


## Renvoie true si l'immobilisation s'est terminée (sortie).
func _osae_cursor_tick(nw: Dictionary, ft: Dictionary, fb: Dictionary, it: Array, ib: Array) -> bool:
	if not nw.has("ct"):
		_osae_cursor_start(nw, ft, fb)
	var top: int = nw.top
	var bot: int = nw.bottom
	for role in ["top", "bot"]:
		var q := _cursor_press(nw, role, ft if role == "top" else fb, it if role == "top" else ib, BA if role == "top" else BB)
		if q < 0:
			continue
		if q == 0:
			if role == "bot":
				nw.prog = maxi(0, nw.prog - cfg.osae_miss_progress)
			continue
		var mult: int = cfg.osae_perfect_mult if q == 2 else 1
		if role == "top":
			nw.control = mini(10000, nw.control + cfg.osae_hit_control * mult)
			nw.prog = maxi(0, nw.prog - cfg.osae_top_progress_cut * mult)
		else:
			nw.control = maxi(cfg.toketa_below, nw.control - cfg.osae_hit_escape_control * mult)
			nw.prog = mini(100, nw.prog + cfg.osae_hit_progress * mult)
	if nw.prog >= 100:
		events.append({"type": "toketa", "who": bot})
		events.append({"type": "escape", "who": bot})
		_announce("TOKETA")
		nw.osae = false
		_matte_after(40)
		return true
	return false


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
	var o: Dictionary = state.fighters[1 - i]
	# refus de kumikata : à distance de garde, il casse et chasse sans jamais saisir
	if has_grip(f) or absi(o.x - f.x) > cfg.grip_range or state.phase != "fight":
		f.nogrip_t = 0
	else:
		f.nogrip_t += 1
		if f.nogrip_t >= cfg.kumikata_refuse_ticks:
			f.nogrip_t = 0
			_shido(i, "Refus de kumikata")
			if state.phase != "fight":
				return
	f.passive_t += 1
	# golden score : la passivité est sanctionnée deux fois plus vite
	if f.passive_t >= (cfg.passivity_ticks / 2 if state.golden else cfg.passivity_ticks):
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
	if state.phase == "ended":
		return  # décision déjà rendue (golden score limité)
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


## Décision (hantei) à la fin d'un golden score limité : moins de shidos, puis plus
## d'attaques engagées, puis domination du kumikata.
func _hantei() -> void:
	var fs: Array = state.fighters
	var w := -1
	if fs[0].shidos != fs[1].shidos:
		w = 0 if fs[0].shidos < fs[1].shidos else 1
	elif fs[0].attacks_n != fs[1].attacks_n:
		w = 0 if fs[0].attacks_n > fs[1].attacks_n else 1
	else:
		w = 0 if state.dom >= 0 else 1
	_end(w, "Décision (hantei)")
	_announce("HANTEI")


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
	state.dom = 0
	for f in fs:
		f.nogrip_t = 0
		f.react = 0
		f.resist_t = 0
		f.follow_t = 0
		f.dash_t = 0


func _new_hand(target: int) -> Dictionary:
	return {"target": target, "state": HAND_FREE, "t": 0, "trig": 0, "lock": 0, "q": 0, "fat": 0}


func _pressed(f: Dictionary, inp: Array, idx: int) -> bool:
	return inp[idx] != 0 and f.prev[idx] == 0


func has_grip(f: Dictionary) -> bool:
	for hand in f.hands:
		if hand.state == HAND_GRIP:
			return true
	return false
