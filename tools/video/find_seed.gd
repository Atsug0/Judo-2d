extends SceneTree
## Cherche une graine de combat IA contre IA spectaculaire pour la vidéo de présentation :
## un waza-ari, de la bataille de mains, et un ippon sur projection avant ~70 s.
## godot --headless --path . -s tools/video/find_seed.gd -- --from=1 --to=300 --builds=0,1 --level=2
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
	var bi: PackedStringArray = String(args.get("builds", "0,1")).split(",")
	# indices des builds par défaut, ou identifiants de légendes (ex. lame,mur)
	var b0: Dictionary = bs[int(bi[0])] if bi[0].is_valid_int() else Build.find(bi[0])
	var b1: Dictionary = bs[int(bi[1])] if bi[1].is_valid_int() else Build.find(bi[1])
	var level := int(args.get("level", "2"))
	var results := []
	for sd in range(int(args.get("from", "1")), int(args.get("to", "200"))):
		var sim := Sim.new(cfg, techs, [b0.name, b1.name], [b0, b1])
		var ais := [Ai.new(0, sd, level), Ai.new(1, sd + 7, level)]
		var kumi := 0
		var reaction := 0
		var waza_t := -1
		var newaza := 0
		while sim.state.phase != "ended" and sim.state.tick < 60 * 90:
			sim.step([ais[0].think(sim), ais[1].think(sim)])
			for e in sim.events:
				if e.type in ["parry", "dash", "whiff", "break"]:
					kumi += 1
				if e.type == "reaction":
					reaction += 1
				if e.type == "waza" and waza_t < 0:
					waza_t = sim.state.tick
				if e.type == "newaza":
					newaza += 1
		var t: int = sim.state.tick
		var reason: String = sim.state.win_reason
		if sim.state.phase != "ended" or not reason.begins_with("Ippon —"):
			continue
		var score := 0
		score += 30 if waza_t > 0 else 0
		score += mini(kumi, 12) * 2
		score += mini(reaction, 3) * 4
		score += 10 if newaza > 0 else 0
		score -= absi(t - 60 * 45) / 60  # idéal : ~45 s de combat
		if sim.state.winner != 0:
			score -= 5  # on préfère que le joueur 1 gagne
		results.append([score, sd, t / 60.0, reason, waza_t / 60.0, kumi, reaction, sim.state.winner])
	results.sort_custom(func(a, b): return a[0] > b[0])
	for r in results.slice(0, 8):
		print("score %d  graine %d  fin %.1f s  %s  waza-ari %.1f s  kumi %d  réactions %d  vainqueur %d" % r)
	quit()
