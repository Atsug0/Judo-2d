extends SceneTree
## Tournoi toutes rondes entre les légendes (IA contre IA) : taux de victoire de chacune.
## godot --headless --path . -s tools/legends_rr.gd -- --matches=4 --level=2
const Sim := preload("res://scripts/sim/match_sim.gd")
const Ai := preload("res://scripts/sim/ai_controller.gd")
const GameData := preload("res://scripts/game_data.gd")
const Build := preload("res://scripts/build.gd")


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("matches", "4"))
	var level := int(args.get("level", "2"))
	var cfg := GameData.load_json("res://data/config.json")
	var techs := GameData.load_json("res://data/techniques.json")
	var ls: Array = Build.legends()
	var wins := {}
	var played := {}
	var durs := 0
	var total := 0
	var short := 0       # combats finis en moins de 30 s
	var unresolved := 0  # pas de vainqueur au bout de 8 min
	var firsts := []     # instant de la première marque (s)
	for l in ls:
		wins[l.id] = 0
		played[l.id] = 0
	for a in ls.size():
		for b in range(a + 1, ls.size()):
			for m in n:
				# alternance des côtés
				var pa: Dictionary = ls[a] if m % 2 == 0 else ls[b]
				var pb: Dictionary = ls[b] if m % 2 == 0 else ls[a]
				var sim := Sim.new(cfg, techs, [pa.name, pb.name], [pa, pb])
				var ais := [Ai.new(0, 300 + m * 31 + a * 7, level), Ai.new(1, 307 + m * 31 + b * 7, level)]
				var first := -1
				while sim.state.phase != "ended" and sim.state.tick < 60 * 60 * 8:
					sim.step([ais[0].think(sim), ais[1].think(sim)])
					if first < 0:
						for e in sim.events:
							if e.type in ["throw", "osaekomi", "submission"]:
								first = sim.state.tick
				if first >= 0:
					firsts.append(first / 60)
				if sim.state.tick < 1800 and sim.state.phase == "ended":
					short += 1
				if sim.state.winner < 0:
					unresolved += 1
				durs += sim.state.tick
				total += 1
				played[pa.id] += 1
				played[pb.id] += 1
				if sim.state.winner == 0:
					wins[pa.id] += 1
				elif sim.state.winner == 1:
					wins[pb.id] += 1
	var rows := []
	for l in ls:
		rows.append([wins[l.id] * 100 / maxi(1, played[l.id]), l.id, l.name])
	rows.sort()
	rows.reverse()
	for r in rows:
		print("%-12s %-10s %3d %% de victoires" % [r[1], r[2], r[0]])
	print("Durée moyenne : %.0f s sur %d combats" % [durs / 60.0 / total, total])
	firsts.sort()
	print("Moins de 30 s : %d %% | sans vainqueur après 8 min : %d %% | première marque médiane : %s s" % [short * 100 / total, unresolved * 100 / total,
		str(firsts[firsts.size() / 2]) if not firsts.is_empty() else "-"])
	quit()
