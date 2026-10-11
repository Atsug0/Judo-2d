extends SceneTree
## Cherche une graine dont les premières secondes montrent une vraie bataille de mains
## (arrachages, mains chassées) sans projection trop tôt.
## godot --headless --path . -s tools/video/find_kumikata_seed.gd -- --from=1 --to=150 --ticks=1200
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
	var techs := GameData.load_json("res://data/techniques.json")
	var bs: Array = Build.defaults()
	var ticks := int(args.get("ticks", "1200"))
	var res := []
	for sd in range(int(args.get("from", "1")), int(args.get("to", "150"))):
		var sim := Sim.new(cfg, techs, [bs[0].name, bs[1].name], [bs[0], bs[1]])
		var ais := [Ai.new(0, sd, 2), Ai.new(1, sd + 7, 2)]
		var score := 0
		var thrown := false
		while sim.state.tick < ticks:
			sim.step([ais[0].think(sim), ais[1].think(sim)])
			for e in sim.events:
				match e.type:
					"break":
						score += 3
					"break_fail", "parry":
						score += 1
					"throw", "newaza":
						thrown = true
		if not thrown:
			res.append([score, sd])
	res.sort()
	res.reverse()
	print("meilleures graines [score, graine] : ", res.slice(0, 6))
	quit()
