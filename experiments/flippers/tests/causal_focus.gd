extends "res://experiments/flippers/tests/causal_audit.gd"


func _run() -> void:
	_config = TRIALS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	for node: Node in _main.get_node("Playfield").find_children("*", "StaticBody2D", true, false):
		if not node is PinballFlipper:
			_static_bodies.append({"node": node, "layer": node.collision_layer})
	_full_events = true
	var row := await _scenario(Vector3(.99, 3, -36), ENVIRONMENTS[10])
	_main.free()
	_write("causal_focus.json", {"checks": _checks, "failures": _failures, "case": row})
	quit(0 if _failures == 0 else 1)
