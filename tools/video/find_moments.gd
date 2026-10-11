extends SceneTree
## Repère les beaux moments d'un combat (projections marquées, contres, sol) pour monter une vidéo.
## Rejoue la manche 1 comme l'écran de combat (2 min, golden 1 min).
##   godot --headless --path . -s tools/video/find_moments.gd -- --pairs=lame:mur,seoi:kesa --from=1 --to=20 --level=3
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
	cfg.match_ticks = 7200
	cfg.golden_limit_ticks = 3600
	var techs := GameData.load_json("res://data/techniques.json")
	var level := int(args.get("level", "3"))
	for pair in String(args.get("pairs", "lame:mur")).split(","):
		var ab := pair.split(":")
		var ba: Dictionary = Build.find(ab[0])
		var bb: Dictionary = Build.find(ab[1])
		for sd in range(int(args.get("from", "1")), int(args.get("to", "20"))):
			var sim := Sim.new(cfg, techs, [ba.name, bb.name], [ba, bb])
			var ais := [Ai.new(0, sd, level), Ai.new(1, sd + 7, level)]
			var marks := []
			while sim.state.phase != "ended" and sim.state.tick < 60 * 60 * 4:
				sim.step([ais[0].think(sim), ais[1].think(sim)])
				for e in sim.events:
					match e.type:
						"score":
							marks.append("%d:%s/%s/%s/P%d" % [sim.state.tick, e.result, e.src, e.tech, int(e.who) + 1])
						"counter", "osaekomi", "sub_start", "toketa", "feint", "combo_open":
							marks.append("%d:%s/P%d" % [sim.state.tick, e.type, int(e.get("who", -1)) + 1])
			print("%s graine %d fin %d : %s" % [pair, sd, sim.state.tick, " ".join(marks)])
	quit()
