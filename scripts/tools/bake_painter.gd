extends Node2D
## Peintre de l'outil de cuisson : exécute la fonction de dessin courante.

var job: Callable


func _draw() -> void:
	if job.is_valid():
		job.call(self)
