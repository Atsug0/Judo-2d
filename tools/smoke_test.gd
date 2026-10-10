extends SceneTree
## Test de parcours : charge le jeu, enchaîne des navigations réelles entre écrans
## et vérifie qu'on arrive bien où on doit. Échoue (code 1) au premier écart.
##   godot --headless --path . -s tools/smoke_test.gd

var app
var failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	app.capture_mode = true  # pas de lecture manette, pas d'enchaînement automatique
	root.add_child(app)
	await process_frame
	await _flow("titre → menu", "title", ["accept"], "menu")
	await _flow("menu → tournoi → combat", "menu", ["accept", "accept"], "match")
	await _flow("menu → versus → combat", "menu", ["down", "accept", "accept"], "match")
	await _flow("menu → en ligne → retour", "menu", ["down", "down", "accept", "back"], "menu")
	await _flow("menu → personnalisation → retour", "menu", ["down", "down", "down", "accept", "next", "right", "next", "right", "x", "accept", "back"], "menu")
	await _flow("menu → options → retour", "menu", ["down", "down", "down", "down", "accept", "right", "right", "left", "down", "right", "back", "back"], "menu")
	await _flow("combat → pause → menu", "match", ["start", "down", "down", "down", "accept"], "menu")
	await _flow("combat → pause → personnalisation", "match", ["start", "down", "down", "accept"], "customize")
	await _flow("combat → pause → recommencer", "match", ["start", "down", "accept"], "match")
	await _flow("résultats (démo) → rejouer", "results", ["accept"], "match")
	await _flow("planche → retour", "art", ["back"], "menu")
	await _tournament_flow()
	print("Parcours : ", "OK" if failures == 0 else "%d ÉCHEC(S)" % failures)
	quit(1 if failures else 0)


func _flow(label: String, start: String, actions: Array, expect: String) -> void:
	var params := {}
	if start == "match":
		params = app.default_match_params()
	app.goto(start, params)
	for k in 3:
		if app.current.has_method("tick"):
			app.current.tick()
	for a in actions:
		app.current.nav(a, 0)
		await process_frame
		if app.current.has_method("tick"):
			app.current.tick()
	_check(label, app.current_name == expect, "attendu %s, obtenu %s" % [expect, app.current_name])


## Tournoi complet : 3 victoires simulées → champion, puis retour au menu.
func _tournament_flow() -> void:
	app.session = {}
	app.goto("tournament", {"new": true})
	var Sim = load("res://scripts/sim/match_sim.gd")
	for round_i in 3:
		app.current.nav("accept", 0)  # lance le combat
		await process_frame
		_check("tournoi tour %d : combat" % (round_i + 1), app.current_name == "match", app.current_name)
		var m = app.current
		# victoire forcée du joueur : on passe directement par l'écran de résultats
		var st: Dictionary = m.sim.get_state()
		st.winner = 0
		st.win_reason = "Ippon — test"
		app.goto("results", {"state": st, "names": m.names, "stats": m.stats, "match_params": m.params})
		await process_frame
		app.current.nav("accept", 0)  # CONTINUER
		await process_frame
		_check("tournoi tour %d : retour au tableau" % (round_i + 1), app.current_name == "tournament", app.current_name)
	var t: Dictionary = app.session.tournament
	_check("tournoi : champion", t.done and t.champion >= 0 and t.players[t.champion].human, str(t.champion))
	app.current.nav("accept", 0)
	await process_frame
	_check("tournoi terminé → menu", app.current_name == "menu", app.current_name)
	# défaite au premier tour → éliminé
	app.goto("tournament", {"new": true})
	app.current.nav("accept", 0)
	await process_frame
	var m2 = app.current
	var st2: Dictionary = m2.sim.get_state()
	st2.winner = 1
	app.goto("results", {"state": st2, "names": m2.names, "stats": m2.stats, "match_params": m2.params})
	await process_frame
	_check("tournoi : éliminé", app.session.tournament.eliminated, "")


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  OK   ", label)
	else:
		failures += 1
		print("  ÉCHEC ", label, " — ", detail)
