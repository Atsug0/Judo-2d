extends SceneTree
## Cherche un combat « épique » en BO3 pour la vidéo de présentation, en rejouant
## exactement les manches comme l'écran de combat (graines, durée 2 min, golden 1 min).
## Note : feintes, arrachages, combos, contres, osaekomi aux curseurs, toketa,
## renversements, clés / étranglements, et une dernière manche gagnée sur projection.
## godot --headless --path . -s tools/video/find_epic_bo3.gd -- --a=lame --b=sambiste --from=1 --to=200 --level=3
const Sim := preload("res://scripts/sim/match_sim.gd")
const Ai := preload("res://scripts/sim/ai_controller.gd")
const GameData := preload("res://scripts/game_data.gd")
const Build := preload("res://scripts/build.gd")


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var cfg := GameData.load_json("res://data/config.json")
	cfg.match_ticks = int(args.get("minutes", "2")) * 3600
	cfg.golden_limit_ticks = 3600
	var techs := GameData.load_json("res://data/techniques.json")
	var ba: Dictionary = Build.find(String(args.get("a", "lame")))
	var bb: Dictionary = Build.find(String(args.get("b", "sambiste")))
	var level := int(args.get("level", "2"))
	var res := []
	for sd in range(int(args.get("from", "1")), int(args.get("to", "200"))):
		var wins := [0, 0]
		var round_no := 1
		var c := {"feint": 0, "break": 0, "combo_open": 0, "counter": 0, "reaction": 0, "toketa": 0,
			"reversal": 0, "sub_start": 0, "sub_escape": 0, "osae_hit": 0, "waza": 0, "golden": 0}
		var rounds := []
		var total := 0
		var last_src := ""
		var ok := true
		while wins[0] < 2 and wins[1] < 2:
			var sim := Sim.new(cfg, techs, [ba.name, bb.name], [ba, bb])
			var s: int = sd + round_no * 101 if round_no > 1 else sd
			var ais := [Ai.new(0, s, level), Ai.new(1, s + 7, level)]
			var marks := []
			while sim.state.phase != "ended" and sim.state.tick < 60 * 60 * 5:
				sim.step([ais[0].think(sim), ais[1].think(sim)])
				for e in sim.events:
					if c.has(e.type):
						c[e.type] += 1
					match e.type:
						"score":
							last_src = String(e.src)
							marks.append("%d:%s/%s/%s" % [sim.state.tick / 60, e.result, e.src, e.tech])
							if e.result == "waza":
								c.waza += 1
						"toketa", "reversal", "sub_start", "golden":
							marks.append("%d:%s" % [sim.state.tick / 60, e.type])
			if sim.state.phase != "ended":
				ok = false
				break
			var w: int = sim.state.winner
			if w >= 0:
				wins[w] += 1
			total += sim.state.tick
			rounds.append("M%d %ds %s %s" % [round_no, sim.state.tick / 60, "P%d" % (w + 1), " ".join(marks)])
			round_no += 1
		if not ok:
			continue
		var score := 0
		score += 40 if rounds.size() == 3 else 0
		score += 25 if last_src == "throw" else 0
		score += mini(c.feint, 6) * 3 + mini(c.break, 10) + mini(c.combo_open, 5) * 3 + mini(c.counter, 3) * 10
		score += mini(c.reaction, 4) * 3 + mini(c.toketa, 2) * 15 + mini(c.reversal, 2) * 15 + mini(c.sub_start, 2) * 12
		score += mini(c.osae_hit, 10) + mini(c.waza, 4) * 6 + c.golden * 10
		var secs: int = total / 60
		if secs > 330:
			score -= (secs - 330) / 4
		res.append([score, sd, secs, str(c), " | ".join(rounds)])
	res.sort_custom(func(x, y): return x[0] > y[0])
	for r in res.slice(0, int(args.get("top", "6"))):
		print("score %d graine %d total %d s %s\n    %s" % r)
	quit()
