extends RefCounted
## Partenaire d'entraînement du dojo (joueur 2) : comportements simples et lisibles,
## choisis par la leçon ou dans le menu de l'entraînement libre.

const Sim := preload("res://scripts/sim/match_sim.gd")
const Ai := preload("res://scripts/sim/ai_controller.gd")

const BEHAVIORS := ["static", "garde", "reach", "marche", "tire", "resiste", "suit", "attaque", "casse",
	"ia1", "ia2", "ia3", "replay"]
const NAMES := {"static": "Immobile", "garde": "Tient sa garde", "reach": "Bataille de mains", "marche": "Se déplace",
	"tire": "Tire (kuzushi)", "resiste": "Résiste aux tractions", "suit": "Suit les tractions", "attaque": "Attaque",
	"casse": "Casse tes saisies", "ia1": "IA débutant", "ia2": "IA moyen", "ia3": "IA fort", "replay": "Rejoue l'enregistrement",
	"sol_passif": "Sol : passif", "sol_resiste": "Sol : se débat", "sol_dessus": "Sol : contrôle"}

var mode = "garde"
var osae_ai = null
var t = 0
var ai = null
var ai_level = 0
var recording: Array = []   # entrées enregistrées (joueur 2)
var replay_i = 0


func set_mode(m: String) -> void:
	if m == mode:
		return
	mode = m
	t = 0
	ai = null
	replay_i = 0


func think(sim) -> Array:
	t += 1
	var inp = Sim.empty_input()
	var s: Dictionary = sim.state
	var me = 1
	var f: Dictionary = s.fighters[me]
	var o: Dictionary = s.fighters[0]
	if mode.begins_with("ia"):
		var lvl = int(mode.substr(2))
		if ai == null or ai_level != lvl:
			ai = Ai.new(me, 77, lvl)
			ai_level = lvl
		return ai.think(sim)
	if mode == "replay":
		if recording.is_empty():
			return inp
		var r: Array = recording[replay_i % recording.size()]
		replay_i += 1
		return r.duplicate()
	if s.phase == "newaza":
		return _ground(sim, inp)
	if s.phase != "fight":
		return inp
	var facing: int = f.facing
	var dist: int = absi(o.x - f.x)
	var cfg: Dictionary = sim.cfg
	match mode:
		"static":
			pass
		"garde", "marche", "tire", "resiste", "suit", "attaque", "casse":
			if dist > cfg.free_gap + 300 and not sim.has_grip(o):
				inp[Sim.MX] = 70 * facing
			if dist <= cfg.grip_range:
				inp[Sim.LT] = 55
				inp[Sim.RT] = 55
			match mode:
				"marche":
					inp[Sim.MX] = (60 if (t / 90) % 2 == 0 else -60) * facing
				"tire":
					if (t / 70) % 2 == 0:
						inp[Sim.PX] = -100 * facing  # le tire vers l'avant
				"resiste":
					# recule (résiste) quand on le tire vers l'avant, avance quand on le pousse
					if f.bal_x > 1200:
						inp[Sim.MX] = -70 * facing
					elif f.bal_x < -1200:
						inp[Sim.MX] = 70 * facing
				"suit":
					if f.bal_x > 1200:
						inp[Sim.MX] = 70 * facing
					elif f.bal_x < -1200:
						inp[Sim.MX] = -70 * facing
				"attaque":
					var c = t % 200
					if c >= 120 and c < 150:
						inp[Sim.BY] = 1
				"casse":
					if t % 100 == 0 and sim.has_grip(o):
						inp[Sim.BB] = 1
		"reach":
			# tend une main régulièrement sans jamais la garder longtemps
			if dist > cfg.free_gap + 300:
				inp[Sim.MX] = 70 * facing
			var c2 = t % 80
			if c2 < 24:
				inp[Sim.RT if (t / 80) % 2 == 0 else Sim.LT] = 70
	return inp


func _ground(sim, inp: Array) -> Array:
	var nw: Dictionary = sim.state.newaza
	if nw.is_empty():
		return inp
	var top: bool = nw.top == 1
	if nw.osae and nw.sub.is_empty() and nw.has("ct"):
		# immobilisation : le partenaire joue les curseurs, en débutant (niveau 1)
		if osae_ai == null:
			osae_ai = Ai.new(1, 5, 1)
		return osae_ai._think_osae(sim, nw, sim.state.fighters[1], inp)
	match mode:
		"sol_dessus":
			if top:
				inp[Sim.BA] = 1
		"sol_resiste":
			if not top:
				if t % 9 == 0:
					inp[Sim.BB] = 1
				inp[Sim.MX] = 100 if (t / 20) % 2 == 0 else -100
			else:
				inp[Sim.BA] = 1
		_:
			if top:
				inp[Sim.BA] = 1
	return inp
