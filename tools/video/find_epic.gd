extends SceneTree
## Cherche un combat « épique » pour la vidéo de démo : échanges de waza-ari, bataille
## de mains, osaekomi joué aux curseurs, et fin sur une projection ippon (ralenti).
## godot --headless --path . -s tools/video/find_epic.gd -- --a=lame --b=mur --from=1 --to=200 --level=2
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
	var ba: Dictionary = Build.find(String(args.get("a", "lame")))
	var bb: Dictionary = Build.find(String(args.get("b", "mur")))
	var level := int(args.get("level", "2"))
	var res := []
	for sd in range(int(args.get("from", "1")), int(args.get("to", "200"))):
		var sim := Sim.new(cfg, techs, [ba.name, bb.name], [ba, bb])
		var ais := [Ai.new(0, sd, level), Ai.new(1, sd + 7, level)]
		var waza := [0, 0]
		var strips := 0
		var osae_t := 0
		var rev := 0
		var ippon_throw := false
		var counters := 0
		while sim.state.phase != "ended" and sim.state.tick < 60 * 60 * 6:
			sim.step([ais[0].think(sim), ais[1].think(sim)])
			var nw: Dictionary = sim.state.newaza
			if not nw.is_empty() and nw.osae and nw.has("ct"):
				osae_t += 1
			for e in sim.events:
				match e.type:
					"throw":
						if e.result == "waza":
							waza[e.who] += 1
						ippon_throw = true  # dernière marque sur projection (ralenti)
					"osaekomi", "submission":
						ippon_throw = false
					"break":
						strips += 1
					"reversal":
						rev += 1
					"counter":
						counters += 1
		var secs: float = sim.state.tick / 60.0
		if args.has("debug"):
			print(sd, " ", int(secs), " ", sim.state.win_reason, " ippon_throw=", ippon_throw)
		if not ippon_throw or sim.state.phase != "ended" or secs < 50 or secs > 200:
			continue
		var score := 0
		score += 30 if waza[0] > 0 and waza[1] > 0 else (10 if waza[0] + waza[1] > 0 else 0)
		score += mini(osae_t / 60, 8) * 3
		score += mini(strips, 12)
		score += rev * 10 + counters * 12
		res.append([score, sd, int(secs), waza, strips, osae_t / 60, rev, counters])
	res.sort()
	res.reverse()
	for r in res.slice(0, 8):
		print("score %d graine %d durée %d s waza %s arrachages %d osaekomi %d s retournements %d contres %d" % r)
	quit()
