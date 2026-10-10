extends RefCounted
## Lecture d'une manette (mapping du GDD, notation Xbox) vers le tableau
## d'entrées de la simulation. Une manette = un joueur (device 0 et 1).

const Sim := preload("res://scripts/sim/match_sim.gd")
const DEADZONE := 0.2


static func read(device: int) -> Array:
	var a := Sim.empty_input()
	a[Sim.MX] = _axis(device, JOY_AXIS_LEFT_X)
	a[Sim.PX] = _axis(device, JOY_AXIS_RIGHT_X)
	a[Sim.PY] = _axis(device, JOY_AXIS_RIGHT_Y)
	a[Sim.LT] = int(round(clampf(Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT), 0.0, 1.0) * 100.0))
	a[Sim.RT] = int(round(clampf(Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0) * 100.0))
	a[Sim.LB] = _btn(device, JOY_BUTTON_LEFT_SHOULDER)
	a[Sim.RB] = _btn(device, JOY_BUTTON_RIGHT_SHOULDER)
	a[Sim.BA] = _btn(device, JOY_BUTTON_A)
	a[Sim.BX] = _btn(device, JOY_BUTTON_X)
	a[Sim.BY] = _btn(device, JOY_BUTTON_Y)
	a[Sim.BB] = _btn(device, JOY_BUTTON_B)
	return a


static func _axis(device: int, axis: int) -> int:
	var v := Input.get_joy_axis(device, axis)
	if absf(v) < DEADZONE:
		return 0
	# Remet l'échelle après la zone morte, puis quantifie en entier.
	var s := (absf(v) - DEADZONE) / (1.0 - DEADZONE)
	return int(round(signf(v) * clampf(s, 0.0, 1.0) * 100.0))


static func _btn(device: int, button: int) -> int:
	return 1 if Input.is_joy_button_pressed(device, button) else 0
