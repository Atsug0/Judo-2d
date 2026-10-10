extends Node2D
## Calque de dessin : délègue son _draw à une fonction (Callable) qui reçoit ce calque.
## Permet de séparer un écran en calques (décor, monde filmé par la caméra, HUD)
## avec chacun sa propre transformation.

var fn: Callable


func _draw() -> void:
	if fn.is_valid():
		fn.call(self)
