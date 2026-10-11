extends SceneTree
## Faisabilité des défis : le judoka 0 (IA niveau 3, build HUGO) tente chaque défi plusieurs fois.
## godot --headless --path . -s tools/challenge_test.gd -- --tries=6
const Sim := preload("res://scripts/sim/match_sim.gd")
const Ai := preload("res://scripts/sim/ai_controller.gd")
const GameData := preload("res://scripts/game_data.gd")
const Build := preload("res://scripts/build.gd")
const Challenges := preload("res://scripts/challenges.gd")


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var tries := int(args.get("tries", "6"))
	var cfg := GameData.load_json("res://data/config.json")
	var techs := GameData.load_json("res://data/techniques.json")
	var me: Dictionary = Build.defaults()[0]
	for ch in Challenges.all():
		var ok := 0
		for t in tries:
			var opp: Dictionary = Build.find(String(ch.opp))
			var sim := Sim.new(cfg, techs, [me.name, opp.name], [me, opp])
			var ais := [Ai.new(0, 50 + t * 13, 3), Ai.new(1, 57 + t * 13, int(ch.level))]
			var tr := Challenges.new_tracker()
			while sim.state.phase != "ended" and sim.state.tick < 60 * 60 * 6:
				sim.step([ais[0].think(sim), ais[1].think(sim)])
				for e in sim.events:
					Challenges.track(tr, sim, e)
			if Challenges.check(ch, tr, sim.state):
				ok += 1
		print("%-14s %d / %d" % [ch.id, ok, tries])
	quit()
