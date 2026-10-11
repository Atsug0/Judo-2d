extends SceneTree
## Liste les leçons du dojo (id, catégorie, longueur de l'intro).
func _init() -> void:
	for l in preload("res://scripts/dojo/lessons.gd").all():
		print("%s %s %d %d" % [l.id, l.cat, String(l.intro).length(), l.steps.size()])
	quit()
