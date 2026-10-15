extends SceneTree
## Mesure les images par seconde de l'écran de combat, rendu réel (pas headless).
##   godot --path . -s tools/bench_fps.gd -- --p1build=kesa --p2build=sambiste [--dessin]
## Affiche la moyenne sur 3 fenêtres d'une seconde, puis quitte.
var app
var t := 0.0
var frames := 0
var mesures := []

func _init() -> void:
	_start.call_deferred()

func _start() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	app = scene

func _process(delta: float) -> bool:
	t += delta
	frames += 1
	if t >= 1.0:
		mesures.append(frames / t)
		print("  %.1f img/s" % (frames / t))
		t = 0.0
		frames = 0
		if mesures.size() >= 4:
			mesures.pop_front()   # la première seconde contient le chargement
			var s := 0.0
			for m in mesures:
				s += m
			print("moyenne : %.1f img/s" % (s / mesures.size()))
			quit()
	return false
