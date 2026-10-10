extends SceneTree
## Banc de test sans affichage :
##   godot --headless --path . -s tools/sim_test.gd -- [--matches=40] [--level=2]
## 1. Déterminisme : même graine = même checksum ; rejouer les entrées enregistrées
##    redonne exactement le même état (propriété nécessaire au rollback).
## 2. Statistiques IA contre IA : vainqueurs, raisons, techniques, durées.

const GameData := preload("res://scripts/game_data.gd")
const Sim := preload("res://scripts/sim/match_sim.gd")
const Ai := preload("res://scripts/sim/ai_controller.gd")
const Build := preload("res://scripts/build.gd")

var builds := []


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var matches := int(args.get("matches", "40"))
	var level := int(args.get("level", "2"))
	var pair: PackedStringArray = String(args.get("builds", "0,1")).split(",")
	var all := Build.defaults()
	builds = [all[int(pair[0])], all[int(pair[1])]]
	print("Builds : %s contre %s" % [builds[0].name, builds[1].name])
	var cfg := GameData.load_json("res://data/config.json")
	var techs := GameData.load_json("res://data/techniques.json")

	var ok := _check_determinism(cfg, techs)
	print("Déterminisme : ", "OK" if ok else "ÉCHEC")

	var stats := {"wins": [0, 0], "reasons": {}, "throws": {}, "attacks": {}, "exposed": 0,
		"counters": 0, "feints": 0, "breaks": 0, "shidos": {}, "ticks": 0, "golden": 0,
		"combo_open": 0, "combo_attacks": 0, "newaza": 0, "osaekomi": 0, "submissions": 0, "toketa": 0, "escape": 0, "kumi": {}}
	var t0 := Time.get_ticks_msec()
	for m in matches:
		var res := _run_match(cfg, techs, 1000 + m, level, stats)
		stats.ticks += res.tick
	var dt := Time.get_ticks_msec() - t0
	print("--- %d combats IA (niveau %d) contre IA, %d ms (%.1f µs/tick)" % [matches, level, dt, dt * 1000.0 / max(1, stats.ticks)])
	print("Victoires J1/J2 : ", stats.wins)
	print("Durée moyenne : %.1f s" % (stats.ticks / 60.0 / matches))
	print("Golden score : ", stats.golden)
	print("Raisons : ", JSON.stringify(stats.reasons))
	print("Attaques engagées : ", JSON.stringify(stats.attacks))
	print("Projections (tech:résultat) : ", JSON.stringify(stats.throws))
	print("Attaques exposées : ", stats.exposed, " | contres : ", stats.counters, " | feintes : ", stats.feints, " | prises cassées : ", stats.breaks)
	print("Shidos : ", JSON.stringify(stats.shidos))
	print("Kumikata : ", JSON.stringify(stats.kumi))
	print("Attaques bloquées : ", stats.get("blocks", 0), " | stoppées : ", stats.get("stuffed", 0))
	print("Enchaînements : %d fenêtres, %d enchaînés" % [stats.combo_open, stats.combo_attacks])
	print("Ne-waza : %d phases, %d osaekomi, %d toketa, %d dégagements, %d soumissions" % [stats.newaza, stats.osaekomi, stats.toketa, stats.escape, stats.submissions])
	quit(0 if ok else 1)


func _run_match(cfg: Dictionary, techs: Dictionary, seed_value: int, level: int, stats: Dictionary) -> Dictionary:
	var sim := Sim.new(cfg, techs, ["J1", "J2"], builds)
	var ais := [Ai.new(0, seed_value, level), Ai.new(1, seed_value + 7, level)]
	var golden_seen := false
	while sim.state.phase != "ended" and sim.state.tick < 60 * 60 * 10:
		sim.step([ais[0].think(sim), ais[1].think(sim)])
		if sim.state.golden and not golden_seen:
			golden_seen = true
			stats.golden += 1
		for e in sim.events:
			if e.type in ["dash", "whiff", "parry", "resist", "follow", "grip"]:
				var key: String = e.type + ("_" + e.dir if e.type == "dash" else "")
				stats.kumi[key] = stats.kumi.get(key, 0) + 1
			match e.type:
				"attack":
					stats.attacks[e.tech] = stats.attacks.get(e.tech, 0) + 1
					if e.get("combo", false):
						stats.combo_attacks += 1
				"combo_open":
					stats.combo_open += 1
				"newaza":
					stats.newaza += 1
				"osaekomi":
					stats.osaekomi += 1
				"submission":
					stats.submissions += 1
				"toketa":
					stats.toketa += 1
				"escape":
					stats.escape += 1
				"throw":
					var k: String = e.tech + ":" + e.result
					stats.throws[k] = stats.throws.get(k, 0) + 1
				"exposed":
					stats.exposed += 1
				"stuffed":
					stats.stuffed = stats.get("stuffed", 0) + 1
				"block":
					stats.blocks = stats.get("blocks", 0) + 1
				"counter":
					stats.counters += 1
				"feint":
					stats.feints += 1
				"break":
					stats.breaks += 1
				"shido":
					stats.shidos[e.reason] = stats.shidos.get(e.reason, 0) + 1
	if sim.state.winner >= 0:
		stats.wins[sim.state.winner] += 1
	var reason: String = sim.state.win_reason.split(" — ")[0]
	stats.reasons[reason] = stats.reasons.get(reason, 0) + 1
	return {"tick": sim.state.tick}


func _check_determinism(cfg: Dictionary, techs: Dictionary) -> bool:
	# Deux exécutions avec la même graine, et un rejeu des entrées enregistrées.
	var sums := []
	var recorded := []
	for run in 2:
		var sim := Sim.new(cfg, techs, ["A", "B"], builds)
		var ais := [Ai.new(0, 42, 2), Ai.new(1, 49, 2)]
		for t in 3000:
			var inputs := [ais[0].think(sim), ais[1].think(sim)]
			if run == 0:
				recorded.append(inputs)
			sim.step(inputs)
		sums.append(sim.checksum())
	var replay := Sim.new(cfg, techs, ["A", "B"], builds)
	for inputs in recorded:
		replay.step(inputs)
	sums.append(replay.checksum())
	# Rollback : sauvegarder un état, avancer, restaurer, rejouer.
	var rb := Sim.new(cfg, techs, ["A", "B"], builds)
	for t in 1500:
		rb.step(recorded[t])
	var saved := rb.get_state()
	for t in range(1500, 2000):
		rb.step(recorded[t])
	rb.set_state(saved)
	for t in range(1500, 3000):
		rb.step(recorded[t])
	sums.append(rb.checksum())
	print("Checksums : ", sums)
	return sums[0] == sums[1] and sums[1] == sums[2] and sums[2] == sums[3]
